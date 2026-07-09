import ClaudeKit
import Foundation
import Observation

/// One live conversation: owns the transport, folds events into the
/// timeline on the main actor, and exposes everything the views bind to.
@MainActor
@Observable
public final class ChatSession: Identifiable {
    /// CLI version the current fixtures were recorded against.
    public static let testedCLIVersion = "2.1.204"

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
    /// startup-failure banner: set when the child dies before `system init`.
    public private(set) var versionNote: String?

    private let connection: AgentConnection
    private var consumeTask: Task<Void, Never>?
    private var turnsInFlight = 0

    public init(connection: AgentConnection, workingDirectory: URL,
                permissionMode: String = "default", model: String? = nil) {
        self.connection = connection
        self.workingDirectory = workingDirectory
        self.permissionMode = permissionMode
        self.currentModel = model
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

    private func handle(_ event: AgentEvent) {
        switch event {
        case .systemInit(let info):
            self.info = info
            if currentModel == nil { currentModel = info.model }
            if !info.permissionMode.isEmpty { permissionMode = info.permissionMode }
            if !info.cliVersion.isEmpty, info.cliVersion != Self.testedCLIVersion {
                versionNote = "CLI \(info.cliVersion) differs from the tested "
                    + "\(Self.testedCLIVersion) — unrecognized events render generically."
            }
        case .controlResponse(let envelope)
            where envelope.requestID == AgentSession.initializeRequestID:
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
            // Dead before `system init` ever arrived — almost always a missing
            // or unresolvable CLI. Surface it loudly instead of a silent dead
            // session in the sidebar.
            if info == nil {
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
    }
}
