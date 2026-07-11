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
    public static let testedCLIVersion = "2.1.206"

    public let id = UUID()
    public let workingDirectory: URL

    public private(set) var timeline: [TimelineItem] = []
    public private(set) var pendingGates: [InteractionGate] = []
    public var pendingGate: InteractionGate? { pendingGates.first }
    public private(set) var isWorking = false
    public private(set) var isThinking = false
    public private(set) var info: SystemInit?
    public private(set) var commands: [SlashCommand] = []
    public private(set) var models: [ModelOption] = []
    public private(set) var currentModel: String?
    /// Session effort level: the spawn --effort value, then whatever the
    /// user last picked (sent as the CLI's own /effort command). nil = CLI
    /// default, never overridden from the wire (the CLI doesn't report it).
    public private(set) var currentEffort: String?
    public private(set) var permissionMode: String
    public private(set) var cumulativeCostUSD = 0.0
    public private(set) var lastUsage: JSONValue?
    public private(set) var hasEnded = false
    /// Yellow banner at the top of ConversationView. Doubles as a
    /// startup-failure banner: set when the child dies before the
    /// initialize handshake was ever acknowledged.
    public private(set) var versionNote: String?
    /// Latest TodoWrite list — the CLI re-sends the whole list per call.
    public private(set) var todos: [TodoItem] = []
    /// Subagent traffic grouped by the spawning Task's tool_use id,
    /// reduced through the same TimelineReducer vocabulary.
    public private(set) var subagentTimelines: [String: [TimelineItem]] = [:]
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
                permissionMode: String = "default", model: String? = nil,
                effort: String? = nil) {
        self.connection = connection
        self.workingDirectory = workingDirectory
        self.permissionMode = permissionMode
        self.currentModel = model
        self.modelExplicitlyChosen = model != nil
        self.currentEffort = effort
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
            model: configuration.model,
            effort: configuration.effort)
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
        guard removeGate(requestID: request.requestID) else { return }
        timeline = TimelineReducer.resolvePermission(
            timeline, requestID: request.requestID, decision: decision)
        Task { await connection.respond(request, decision) }
    }

    /// AskUserQuestion: answers keyed by exact question text, multi-select
    /// values ", "-joined by the caller (probe finding 2).
    public func answer(_ prompt: QuestionPrompt, answers: [String: String]) {
        guard removeGate(requestID: prompt.request.requestID) else { return }
        Task {
            await connection.respond(prompt.request, .allow(
                updatedInput: prompt.answeredInput(answers), updatedPermissions: nil))
        }
    }

    /// Skip = allow with the input echoed unchanged (probe finding 3).
    public func skipQuestions(_ prompt: QuestionPrompt) {
        answer(prompt, answers: [:])
    }

    public func approvePlan(_ approval: PlanApproval) {
        guard removeGate(requestID: approval.request.requestID) else { return }
        Task { await connection.respond(approval.request, .allowAsRequested) }
    }

    /// Deny phrased as user feedback — a bare imperative reads as prompt
    /// injection to the model (probe finding 6).
    public func rejectPlan(_ approval: PlanApproval, feedback: String?) {
        guard removeGate(requestID: approval.request.requestID) else { return }
        let trimmed = feedback?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let message = trimmed.isEmpty
            ? "The user rejected the plan. Revise it and request approval again."
            : "The user rejected the plan with this feedback: \(trimmed)"
        Task { await connection.respond(approval.request, .deny(message: message)) }
    }

    private func removeGate(requestID: String) -> Bool {
        guard let index = pendingGates.firstIndex(where: { $0.requestID == requestID })
        else { return false }
        pendingGates.remove(at: index)
        return true
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

    /// Sends the CLI's own /effort command as user text (probe finding 2):
    /// costs no NEW API spend (duration_api_ms 0; the result echoes
    /// session-cumulative accounting), the CLI replies with a synthetic
    /// assistant message narrating the change, and the result carries
    /// num_turns == 0.
    public func setEffort(_ level: String) {
        guard !hasEnded else { return }
        currentEffort = level
        send("/effort \(level)")
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
        if !pendingGates.isEmpty { return .needsApproval }
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
        // Subagent side-streams: same vocabulary, separate timeline. Routed
        // here (not in the reducer) so sub-traffic can't touch parent state
        // like isThinking or gates.
        if let parentID = event.parentToolUseID {
            subagentTimelines[parentID] = TimelineReducer.reduce(
                subagentTimelines[parentID] ?? [], event)
            return
        }
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
                if let question = QuestionPrompt(permission) {
                    pendingGates.append(.question(question))
                } else if let approval = PlanApproval(permission) {
                    pendingGates.append(.planApproval(approval))
                } else {
                    pendingGates.append(.permission(permission))
                }
            }
        case .result(let turn):
            turnsInFlight = max(0, turnsInFlight - 1)
            isWorking = turnsInFlight > 0
            isThinking = false
            // An aborted turn (interrupt → error_during_execution) abandons any
            // open permission gate — the CLI is no longer waiting for a decision.
            // On normal completion the list is already empty, so this is a no-op.
            // EXCEPT synthetic slash-command results (num_turns == 0, probe
            // finding 12): those never close a real turn, and a gate pending
            // while one arrives is still live on the CLI side.
            if turn.raw["num_turns"]?.doubleValue != 0 {
                pendingGates.removeAll()
            }
            // total_cost_usd is SESSION-CUMULATIVE on the wire (fixtures:
            // slashfx + control-ops show monotonic growth; synthetic slash
            // results echo it unchanged) — assign, don't sum. The += here
            // double-counted since Plan 3.
            if let cost = turn.totalCostUSD { cumulativeCostUSD = cost }
            if turn.raw["num_turns"]?.doubleValue != 0 {
                lastUsage = turn.usage   // synthetic results carry all-zeros usage
            }
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
        case .system(let subtype, let raw):
            // Plan approval (and future mode changes) announce the new mode
            // via system/status (probe finding 5). set_permission_mode acks
            // stay optimistic — 4c adds correlation.
            if subtype == "status",
               let mode = raw["permissionMode"]?.stringValue, !mode.isEmpty {
                permissionMode = mode
            }
        case .assistant(let message):
            for block in message.content {
                if case .toolUse(_, "TodoWrite", let input) = block {
                    let parsed = TodoItem.list(from: input)
                    // Deliberate: an empty list never clears. The CLI re-sends
                    // the complete list on every call, so an empty todos array
                    // is a malformed write, not a reset (T5 review; test-pinned).
                    if !parsed.isEmpty { todos = parsed }
                }
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
                optionDescription: entry["description"]?.stringValue,
                supportsEffort: entry["supportsEffort"]?.boolValue ?? false,
                supportedEffortLevels: (entry["supportedEffortLevels"]?.arrayValue ?? [])
                    .compactMap(\.stringValue))
        }
        // With init deferred to the first turn (2.1.205+), the catalog is the
        // only pre-turn source for what "default" resolves to — without this
        // the picker sits on a blank "Model" until the user types.
        if currentModel == nil {
            currentModel = models.first { $0.value == "default" }?.resolvedModel
        }
    }
}
