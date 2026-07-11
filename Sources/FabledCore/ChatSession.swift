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
    /// The on-disk session id this live session resumed, if any (set at
    /// launch for --resume spawns; nil for fresh sessions). Task 12 uses it
    /// to enforce one live process per session id.
    public let resumedSessionID: String?

    /// Signals AppModel forwards to notification policy (4b feature 7).
    /// Deliberately NOT an AsyncStream: one consumer, main-actor, fire-and-
    /// forget — a closure keeps ordering trivial.
    public enum NoteworthyEvent: Sendable, Equatable {
        case gateArrived(summary: String)
        case turnCompleted(detail: String, durationMS: Double)
        case terminated(exitCode: Int32)
    }
    public var onNoteworthy: ((NoteworthyEvent) -> Void)?
    /// Last post_turn_summary status_detail — ready-made notification body
    /// (4a probe finding 8). Reset when its result consumes it.
    private var lastStatusDetail = ""

    public private(set) var timeline: [TimelineItem] = []
    public private(set) var pendingGates: [InteractionGate] = []
    public var pendingGate: InteractionGate? { pendingGates.first }
    public private(set) var isWorking = false
    public private(set) var isThinking = false
    /// Cumulative estimated thinking tokens for the current turn, from
    /// system/thinking_tokens events (probe finding 7). nil outside turns.
    public private(set) var thinkingTokens: Int?
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
    /// Task-tool checklist (TaskCreate/TaskUpdate/TaskList) — the live
    /// replacement for TodoWrite on 2.1.206 (probe finding 9). The card
    /// renders whichever of tasks/todos is non-empty, tasks winning.
    public private(set) var taskChecklist = TaskChecklist()
    public var sessionTasks: [TaskItem] { taskChecklist.items }
    /// Subagent traffic grouped by the spawning Task's tool_use id,
    /// reduced through the same TimelineReducer vocabulary.
    public private(set) var subagentTimelines: [String: [TimelineItem]] = [:]
    /// The CLI acknowledged the initialize handshake (catalog
    /// control_response) or sent `system init` — the child is alive and
    /// talking, even though 2.1.205+ holds init until the first user turn.
    public private(set) var isReady = false
    /// Wall-clock of the last wire event — liveness is client-timed, there
    /// is no heartbeat during tool execution (4a probe finding 8).
    public private(set) var lastEventAt: Date?
    /// In-flight optimistic control ops: request id → revert closure.
    /// A rejected op runs its revert so the toolbar can't hold a stale label
    /// (FOLLOWUPS: optimistic control ops).
    private var pendingControlReverts: [String: () -> Void] = [:]
    /// Error acks that arrived before their op's revert was registered —
    /// the registration hops through the sending Task's MainActor resume,
    /// so a fast ack can beat it. registerRevert drains this on arrival,
    /// making ack/registration ordering irrelevant. request id → reason.
    private var unmatchedErrorAcks: [String: String] = [:]

    private let connection: AgentConnection
    private var consumeTask: Task<Void, Never>?
    private var turnsInFlight = 0
    private var hasSentMessage = false
    /// Model came from the launch configuration or the user's picker choice —
    /// never overridden by catalog defaults or a late `system init`.
    private var modelExplicitlyChosen: Bool

    public init(connection: AgentConnection, workingDirectory: URL,
                permissionMode: String = "default", model: String? = nil,
                effort: String? = nil, resumedSessionID: String? = nil) {
        self.connection = connection
        self.workingDirectory = workingDirectory
        self.permissionMode = permissionMode
        self.currentModel = model
        self.modelExplicitlyChosen = model != nil
        self.currentEffort = effort
        self.resumedSessionID = resumedSessionID
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
            effort: configuration.effort,
            resumedSessionID: configuration.forkSession ? nil : configuration.resumeSessionID)
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
        // Liveness baseline: without this, the quiet-clock inherits the idle
        // gap since the previous turn's last event and the status row shows an
        // inflated "no response for Ns" the moment a message is sent.
        lastEventAt = Date()
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
        let previous = currentModel
        let previousChosen = modelExplicitlyChosen
        currentModel = value
        modelExplicitlyChosen = true
        Task {
            let requestID = await connection.setModel(value)
            registerRevert(requestID) { [weak self] in
                // Last write wins: only revert if this op's optimistic value
                // is still current — a stale error ack must not clobber a
                // newer successful pick.
                guard let self, self.currentModel == value else { return }
                self.currentModel = previous
                self.modelExplicitlyChosen = previousChosen
            }
        }
    }

    public func setPermissionMode(_ mode: String) {
        let previous = permissionMode
        permissionMode = mode
        Task {
            let requestID = await connection.setPermissionMode(mode)
            registerRevert(requestID) { [weak self] in
                // Last write wins — see setModel.
                guard let self, self.permissionMode == mode else { return }
                self.permissionMode = previous
            }
        }
    }

    private func registerRevert(_ requestID: String, _ revert: @escaping () -> Void) {
        // The ack may have beaten this registration (it hops through the
        // sending Task's MainActor resume) — settle immediately from the stash.
        if let reason = unmatchedErrorAcks.removeValue(forKey: requestID) {
            revert()
            noteControlError(requestID: requestID, reason: reason)
            return
        }
        pendingControlReverts[requestID] = revert
    }

    private func noteControlError(requestID: String, reason: String) {
        timeline = timeline + [.notice(
            id: "control-error-\(requestID)", text: reason)]
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
        lastEventAt = Date()
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
        case .controlResponse(let envelope):
            // Correlate a control op's ack: a rejected set_model/
            // set_permission_mode runs its revert so the toolbar can't hold a
            // stale label; the reason surfaces as a notice. Success acks just
            // clear the pending revert entry.
            if let revert = pendingControlReverts.removeValue(forKey: envelope.requestID) {
                if envelope.subtype == "error" {
                    revert()
                    noteControlError(
                        requestID: envelope.requestID,
                        reason: envelope.errorMessage ?? "The CLI rejected the change.")
                }
            } else if envelope.subtype == "error" {
                // No revert registered yet — the ack beat the registration.
                // Stash it; registerRevert settles it on arrival.
                unmatchedErrorAcks[envelope.requestID] =
                    envelope.errorMessage ?? "The CLI rejected the change."
            }
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
            if let gate = pendingGates.last, gate.requestID == request.requestID {
                onNoteworthy?(.gateArrived(summary: gate.summaryLine))
            }
        case .result(let turn):
            turnsInFlight = max(0, turnsInFlight - 1)
            isWorking = turnsInFlight > 0
            isThinking = false
            thinkingTokens = nil
            // An aborted turn (interrupt → error_during_execution) abandons any
            // open permission gate — the CLI is no longer waiting for a decision.
            // On normal completion the list is already empty, so this is a no-op.
            // EXCEPT synthetic slash-command results (num_turns == 0, probe
            // finding 12): those never close a real turn, and a gate pending
            // while one arrives is still live on the CLI side.
            if turn.raw["num_turns"]?.doubleValue != 0 {
                pendingGates.removeAll()
                lastUsage = turn.usage   // synthetic results carry all-zeros usage
                // A real turn completed — hand the ready-made status_detail to
                // the notification policy (4b feature 7), then consume it.
                onNoteworthy?(.turnCompleted(
                    detail: lastStatusDetail, durationMS: turn.durationMS ?? 0))
                lastStatusDetail = ""
            }
            // total_cost_usd is SESSION-CUMULATIVE on the wire (fixtures:
            // slashfx + control-ops show monotonic growth; synthetic slash
            // results echo it unchanged) — assign, don't sum. The += here
            // double-counted since Plan 3.
            if let cost = turn.totalCostUSD { cumulativeCostUSD = cost }
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
            thinkingTokens = nil
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
            onNoteworthy?(.terminated(exitCode: exitCode))
        case .system(let subtype, let raw):
            // Plan approval (and future mode changes) announce the new mode
            // via system/status (probe finding 5). set_permission_mode acks
            // stay optimistic — 4c adds correlation.
            if subtype == "status",
               let mode = raw["permissionMode"]?.stringValue, !mode.isEmpty {
                permissionMode = mode
            }
            if subtype == "thinking_tokens",
               let estimated = raw["estimated_tokens"]?.doubleValue {
                thinkingTokens = Int(estimated)
            }
            if subtype == "post_turn_summary" {
                lastStatusDetail = raw["status_detail"]?.stringValue ?? ""
            }
        case .assistant(let message):
            for block in message.content {
                if case .toolUse(let id, let name, let input) = block {
                    taskChecklist.noteToolUse(id: id, name: name, input: input)
                    if name == "TodoWrite" {
                        let parsed = TodoItem.list(from: input)
                        // Deliberate: an empty list never clears. The CLI re-sends
                        // the complete list on every call, so an empty todos array
                        // is a malformed write, not a reset (T5 review; test-pinned).
                        if !parsed.isEmpty { todos = parsed }
                    }
                }
            }
        case .toolResult(let results, _):
            for result in results { taskChecklist.noteResult(result) }
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
