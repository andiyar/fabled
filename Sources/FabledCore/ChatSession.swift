import ClaudeKit
import Foundation
import Observation
import os

/// One live conversation: owns the transport, folds events into the
/// timeline on the main actor, and exposes everything the views bind to.
@MainActor
@Observable
public final class ChatSession: Identifiable {
    /// CLI version the current fixtures were recorded against.
    public static let testedCLIVersion = "2.1.205"

    public let id = UUID()
    public let workingDirectory: URL

    public private(set) var timeline: [TimelineItem] = []
    public private(set) var pendingPermissions: [PermissionRequest] = []
    public var pendingPermission: PermissionRequest? { pendingPermissions.first }
    public private(set) var isWorking = false
    public private(set) var isThinking = false
    public private(set) var info: SystemInit?
    public private(set) var commands: [SlashCommand] = []
    public private(set) var models: [ModelOption] = []
    public private(set) var currentModel: String?
    public private(set) var permissionMode: String
    public private(set) var cumulativeCostUSD = 0.0
    public private(set) var lastUsage: JSONValue?
    public private(set) var hasEnded = false
    /// Yellow banner at the top of ConversationView. Doubles as a
    /// startup-failure banner: set when the child dies before the
    /// initialize handshake was ever acknowledged.
    public private(set) var versionNote: String?
    /// The CLI acknowledged the initialize handshake (catalog
    /// control_response) or sent `system init` — the child is alive and
    /// talking, even though 2.1.205+ holds init until the first user turn.
    public private(set) var isReady = false

    private let connection: AgentConnection
    private var consumeTask: Task<Void, Never>?
    private var turnsInFlight = 0
    private var hasSentMessage = false
    /// Model came from the launch configuration or the user's picker choice —
    /// never overridden by catalog defaults or a late `system init`.
    private var modelExplicitlyChosen: Bool

    public init(connection: AgentConnection, workingDirectory: URL,
                permissionMode: String = "default", model: String? = nil) {
        self.connection = connection
        self.workingDirectory = workingDirectory
        self.permissionMode = permissionMode
        self.currentModel = model
        self.modelExplicitlyChosen = model != nil
    }

    /// Ready, but the CLI is holding `system init` (and all other output)
    /// until the first user turn — 2.1.205+ defers the init event. Views show
    /// a "ready" affordance instead of a dead-looking empty pane.
    public var isAwaitingFirstMessage: Bool {
        isReady && !hasSentMessage && !hasEnded
    }

    /// Launch-time drift warning derived from the binary on disk. Waiting for
    /// `system init` to compare versions means warning only after the user has
    /// already typed into a drifted CLI (init is deferred on 2.1.205+); the
    /// install path knows the version at spawn. Init stays authoritative and
    /// clears or resets this when it arrives.
    public func noteDiskVersion(_ version: String?) {
        guard let version, version != Self.testedCLIVersion else { return }
        versionNote = Self.driftNote(version)
    }

    private static func driftNote(_ version: String) -> String {
        "CLI \(version) differs from the tested \(testedCLIVersion) — "
            + "unrecognized events render generically."
    }

    /// Production path: spawn the CLI and bind a session to it.
    public static func launch(configuration: SessionConfiguration) async throws -> ChatSession {
        var configuration = configuration
        // GUI launches inherit a minimal PATH from LaunchServices, so the
        // `/usr/bin/env claude` fallback exits 127. Resolve the binary from the
        // standard install locations before spawning; nil leaves env in place.
        if configuration.executable == nil {
            configuration.executable = SessionConfiguration.resolveClaudeExecutable()
        }
        let agent = AgentSession(configuration: configuration)
        try await agent.start()
        let session = ChatSession(
            connection: .live(agent),
            workingDirectory: configuration.workingDirectory,
            permissionMode: configuration.permissionMode ?? "default",
            model: configuration.model)
        if let executable = configuration.executable {
            session.noteDiskVersion(
                SessionConfiguration.resolveClaudeVersion(executable: executable))
        }
        session.begin()
        return session
    }

    /// Starts consuming events. Idempotent; separate from init so tests can
    /// construct first and observe from the very first event.
    public func begin() {
        guard consumeTask == nil else { return }
        consumeTask = Task { [weak self] in
            guard let events = await self?.connection.events() else { return }
            for await event in events {
                guard let self else { return }
                self.handle(event)
            }
        }
    }

    /// Resumed/forked sessions preload their on-disk history — the CLI does
    /// NOT replay events on --resume (probe finding 8).
    public func seed(timeline items: [TimelineItem]) {
        guard timeline.isEmpty else { return }
        timeline = items
    }

    // MARK: - User actions

    public func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !hasEnded else { return }
        timeline = TimelineReducer.appendUserMessage(
            timeline, id: UUID().uuidString, text: trimmed)
        hasSentMessage = true
        turnsInFlight += 1
        isWorking = true
        Task { await connection.send(trimmed) }
    }

    public func respond(to request: PermissionRequest, decision: PermissionDecision) {
        // A double-click (or a gate already abandoned by an aborted turn) must
        // not forward a duplicate control_response to the CLI.
        guard pendingPermissions.contains(where: { $0.requestID == request.requestID })
        else { return }
        pendingPermissions.removeAll { $0.requestID == request.requestID }
        timeline = TimelineReducer.resolvePermission(
            timeline, requestID: request.requestID, decision: decision)
        Task { await connection.respond(request, decision) }
    }

    public func interrupt() {
        Task { await connection.interrupt() }
    }

    public func setModel(_ value: String) {
        currentModel = value
        modelExplicitlyChosen = true
        Task { await connection.setModel(value) }
    }

    public func setPermissionMode(_ mode: String) {
        permissionMode = mode
        Task { await connection.setPermissionMode(mode) }
    }

    public func terminate() {
        consumeTask?.cancel()
        Task { await connection.terminate() }
    }

    // MARK: - Derived state

    public enum ActivityState: Equatable {
        case idle, working, needsApproval, ended
    }

    /// Sidebar dot: approval beats working beats idle.
    public var activityState: ActivityState {
        if hasEnded { return .ended }
        if !pendingPermissions.isEmpty { return .needsApproval }
        if isWorking { return .working }
        return .idle
    }

    /// Sidebar label: first prompt's first line, else the folder name.
    public var title: String {
        for item in timeline {
            if case .userMessage(_, let text) = item {
                let firstLine = text.split(separator: "\n", omittingEmptySubsequences: true)
                    .first.map(String.init) ?? text
                return String(firstLine.prefix(60))
            }
        }
        return workingDirectory.lastPathComponent
    }

    // MARK: - Event handling

    /// Debug-level wire trace: `log stream --level debug --predicate
    /// 'subsystem == "dev.fabled.Fabled"'`. Case names only — payloads can
    /// be megabytes.
    private static let wireLog = Logger(
        subsystem: "dev.fabled.Fabled", category: "protocol")

    private func handle(_ event: AgentEvent) {
        let tag = Mirror(reflecting: event).children.first?.label ?? "terminated"
        Self.wireLog.debug("event \(tag, privacy: .public) [\(self.id, privacy: .public)]")
        switch event {
        case .systemInit(let info):
            self.info = info
            isReady = true
            if !modelExplicitlyChosen, !info.model.isEmpty { currentModel = info.model }
            if !info.permissionMode.isEmpty { permissionMode = info.permissionMode }
            // Authoritative over the disk-derived launch note: clears a stale
            // warning or replaces it with the truth.
            if !info.cliVersion.isEmpty {
                versionNote = info.cliVersion == Self.testedCLIVersion
                    ? nil : Self.driftNote(info.cliVersion)
            }
        case .controlResponse(let envelope)
            where envelope.requestID == AgentSession.initializeRequestID:
            isReady = true
            harvestCatalog(envelope.payload)
        case .controlRequest(let request):
            if let permission = PermissionRequest(request) {
                pendingPermissions.append(permission)
            }
        case .result(let turn):
            turnsInFlight = max(0, turnsInFlight - 1)
            isWorking = turnsInFlight > 0
            isThinking = false
            // An aborted turn (interrupt → error_during_execution) abandons any
            // open permission gate — the CLI is no longer waiting for a decision.
            // On normal completion the list is already empty, so this is a no-op.
            pendingPermissions.removeAll()
            cumulativeCostUSD += turn.totalCostUSD ?? 0
            lastUsage = turn.usage
        case .streamEvent(let stream):
            switch stream.kind {
            case .thinkingDelta: isThinking = true
            case .textDelta, .contentBlockStart: isThinking = false
            default: break
            }
        case .terminated(let exitCode):
            hasEnded = true
            isWorking = false
            isThinking = false
            // Dead before the initialize handshake was ever acknowledged —
            // almost always a missing or unresolvable CLI. Surface it loudly
            // instead of a silent dead session in the sidebar. (`info == nil`
            // is no longer the test: 2.1.205+ defers `system init` until the
            // first user turn, so a session closed before typing has no init.)
            if !isReady {
                versionNote = "claude exited immediately (code \(exitCode)) before "
                    + "initializing — is the Claude Code CLI installed and executable? "
                    + "Fabled looks in PATH, ~/.local/bin, ~/.claude/local, "
                    + "/opt/homebrew/bin, /usr/local/bin."
            }
        default:
            break
        }
        timeline = TimelineReducer.reduce(timeline, event)
    }

    private func harvestCatalog(_ payload: JSONValue?) {
        commands = (payload?["commands"]?.arrayValue ?? []).compactMap { entry in
            guard let name = entry["name"]?.stringValue else { return nil }
            return SlashCommand(
                name: name,
                commandDescription: entry["description"]?.stringValue ?? "",
                argumentHint: entry["argumentHint"]?.stringValue ?? "")
        }
        models = (payload?["models"]?.arrayValue ?? []).compactMap { entry in
            guard let value = entry["value"]?.stringValue else { return nil }
            return ModelOption(
                value: value,
                resolvedModel: entry["resolvedModel"]?.stringValue,
                displayName: entry["displayName"]?.stringValue ?? value,
                optionDescription: entry["description"]?.stringValue)
        }
        // With init deferred to the first turn (2.1.205+), the catalog is the
        // only pre-turn source for what "default" resolves to — without this
        // the picker sits on a blank "Model" until the user types.
        if currentModel == nil {
            currentModel = models.first { $0.value == "default" }?.resolvedModel
        }
    }
}
