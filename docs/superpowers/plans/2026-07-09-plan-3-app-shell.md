# App Shell + Conversation UI Implementation Plan (Fabled Plan 3 of 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Fabled.app a person can live in: sidebar (live sessions + searchable history), streaming conversation view, composer, permission cards, model picker — so Ben can use Fabled instead of the Electron app for ordinary coding sessions.

**Architecture:** A new `FabledCore` SPM target holds everything with logic — the pure `TimelineReducer` (AgentEvent → `[TimelineItem]`), the `@Observable` view models (`ChatSession` per live conversation, `AppModel` for the app) — all tested by `swift test`. The `Fabled` app target (XcodeGen-generated `.xcodeproj`) holds only thin SwiftUI views over those models. ClaudeKit gains the protocol pieces Plan 3 needs (stream deltas, permission-response fixes, control-op correlation, SearchIndex hardening), each driven by fixtures recorded from the real CLI during plan-writing.

**Tech Stack:** Swift 6, SwiftUI, Observation framework, SwiftPM + XcodeGen 2.44.1 (`brew install xcodegen` if missing), XCTest. macOS 15+. Zero third-party dependencies (ClaudeKit *and* FabledCore; ledgered).

**Roadmap context:** Plan 3 of 4. Plans 1–2 (ClaudeKit engine, SessionStore + search) are complete and merged. Plan 4 = full surfaces (subagent grouping, TodoWrite checklist, diff rendering, SwiftTerm escape hatch, AskUserQuestion, plan-mode sheet, notifications). Spec: `docs/superpowers/specs/2026-07-08-fabled-native-client-design.md`. Brief: `2026-07-08-plan-3-app-shell-brief.md`.

---

## Probe findings (2026-07-09, CLI 2.1.204)

Every "verify by probing" item from the brief was tested live during plan-writing. Five new fixtures were recorded into `fixtures/` (raw stdout captures, one JSON object per line). **Trust these over intuition**; the fixture files are the ground truth for every shape below.

| Fixture | Lines | What it captures |
|---|---|---|
| `2026-07-09-partial-messages.jsonl` | 24 | `--include-partial-messages` stream: one turn with thinking + text deltas |
| `2026-07-09-control-ops.jsonl` | 66 | `set_permission_mode` + `set_model` acks, queued second user message, 3 turns |
| `2026-07-09-perm-allow-noinput.jsonl` | 89 | allow **without** `updatedInput` → CLI-side ZodError, tool denied |
| `2026-07-09-perm-allow-persist.jsonl` | 70 | allow with `updatedPermissions` → tool runs, rule persisted to settings |
| `2026-07-09-interrupt.jsonl` | 15 | interrupt mid-turn: ack, synthetic user line, `error_during_execution` result |

1. **`stream_event` shape.** With `--include-partial-messages`, every Anthropic SSE event arrives wrapped as
   `{"type":"stream_event","event":{…},"session_id":"…","parent_tool_use_id":null,"uuid":"…"}`.
   Observed `event.type` values: `message_start`, `content_block_start` (with `index` + `content_block` — same block shapes as assistant content: `text`, `thinking`, `tool_use`), `content_block_delta` (with `index` + `delta` of type `text_delta` {text}, `thinking_delta` {thinking}, `signature_delta` {signature}; `input_json_delta` {partial_json} exists per Anthropic API for tool_use blocks), `content_block_stop`, `message_delta` (delta.stop_reason + usage), `message_stop`. The final `assistant` event still arrives after the deltas with the complete message — deltas are *additive*, so a reducer can render deltas provisionally and reconcile on the final message.
2. **`allow` without `updatedInput` is BROKEN.** The CLI validates the allow payload with Zod and `updatedInput` is required: omitting it produces a tool_result "Tool permission request failed: ZodError …", the tool never runs, and the turn's `result` lists it under `permission_denials`. **Every allow response must carry `updatedInput`** — echo the request's `input` when the user made no edits. (`fixtures/2026-07-09-perm-allow-noinput.jsonl`; this invalidates Plan 1's `.allow(updatedInput: nil)` path — fixed in Task 2.)
3. **`updatedPermissions` works and persists.** Echoing the request's `permission_suggestions` array verbatim inside the allow response makes the CLI (a) run the tool, (b) write the rule to the suggestion's `destination`. Observed: suggestion `{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"git init *"}],"behavior":"allow","destination":"localSettings"}` → `<cwd>/.claude/settings.local.json` gains `{"permissions":{"allow":["Bash(git init *)"]}}`. The `can_use_tool` payload also carries `tool_use_id` and `decision_reason_type` (new since the spec census).
4. **`set_permission_mode` ack:** `{"type":"control_response","response":{"subtype":"success","request_id":"…","response":{"mode":"acceptEdits"}}}` — acknowledged immediately, even mid-turn.
5. **`set_model` ack:** `{"subtype":"success","request_id":"…"}` with **no** inner `response` payload. Takes effect for messages sent after the ack (next turn's `assistant.message.model` = new model). A user message already queued before the `set_model` keeps the *old* model. After `set_model`, the CLI also emits a synthetic `user` event `{"message":{"content":"<local-command-stdout>Set model to sonnet (claude-sonnet-5)</local-command-stdout>"},"isReplay":true}` — decodes to `.toolResult([])` under Plan 1's decoder; the reducer must treat empty tool-result events as no-ops.
6. **A second `user` message mid-turn is QUEUED,** not rejected: the CLI finishes the current turn (its own `result`), then runs the queued message as a fresh turn with its own `result`. The composer can stay enabled while `isWorking` — track turns in flight by counting sends vs results.
7. **`interrupt`:** ack `{"subtype":"success","request_id":"…"}`, then a synthetic user line `[Request interrupted by user]` (arrives as `.toolResult([])` — content is a text block, not a tool_result), then `result` with `subtype:"error_during_execution"`, `is_error:true`. **The process survives**: a subsequent user message runs a normal turn. Stop button ≠ session death.
8. **`--resume` does NOT replay history.** A resumed stream-json session emits only init + new-turn events (context intact server-side; same `session_id` unless `--fork-session`). A resumed/forked `ChatSession` must therefore **seed its timeline from the on-disk transcript** before consuming live events.
9. **The `initialize` control_response is a treasure chest** (same `request_id` echoed back): `response.response` carries `commands` (`[{name, description, argumentHint}]`, 37 entries on Ben's machine — the `/` autocomplete source), **`models`** (`[{value, resolvedModel, displayName, description, supportsEffort, supportedEffortLevels, supportsAdaptiveThinking, supportsFastMode, supportsAutoMode}]` — a ready-made model catalog), `account` ({email, organization, subscriptionType, apiProvider}), `output_style`, `available_output_styles`. **The model picker is data-driven from this catalog** (+ a free-text field), not a hardcoded alias list. Requires correlating by request id — hence Task 1.
10. **New `system` subtypes since the spec:** `status` ({status: "requesting"}) and per-turn `thinking_tokens` ({estimated_tokens, estimated_tokens_delta}) flow through the existing tolerant `.system(subtype:raw:)` path — no codec change needed. `result` lines now also carry `errors`, `modelUsage`, `stop_reason`, `terminal_reason` (all preserved in `TurnResult.raw`).

## Contract amendments vs the brief (conscious; ledger in DECISIONS.md during Task 13)

- **`PermissionDecision` is reshaped** (finding 2, 3): `.allow(updatedInput: JSONValue?, updatedPermissions: [JSONValue]?)`; encode always emits `updatedInput` (falling back to the request's own input). The brief's permission card "Always allow" button rides `updatedPermissions`.
- **Model picker is catalog-driven** (finding 9): options come from the initialize response's `models` array + free-text custom field. Replaces the brief's "static known-alias list".
- **Sidebar history is index-backed** (`SearchIndex.sessionSummaries()`, new): one SQL query instead of a 3.7 s title-derivation enumeration, and it resolves the FOLLOWUPS title-source divergence — the index's whole-file title is authoritative everywhere.
- **`TimelineItem.permission.resolution` type is `PermissionDecision?`** exactly as the brief locked; `PermissionDecision` gains `Equatable` so `TimelineItem` can be `Equatable` for SwiftUI diffing.
- **`ChatSession` wraps an injected `AgentConnection`** (closure bundle over `AgentSession`) rather than the actor directly, so every view-model behavior is unit-testable without processes. `AgentSession` itself is unchanged as the production path.

## Conventions for implementing agents

- Repo root: `~/Developer/Fabled`. All commands run from there.
- Package build/test: `swift build && swift test` — green before **every** commit. Never commit red.
- App build: `xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled -configuration Debug build` (from Task 8 on; expected final line `** BUILD SUCCEEDED **`). Never hand-edit `Fabled.xcodeproj` — it is generated output and gitignored; `project.yml` is the source of truth.
- Swift 6 strict concurrency is ON. Everything public is `Sendable` (or `@MainActor`). View models are `@MainActor @Observable`; mutable engine state lives in the existing actors.
- Zero third-party dependencies anywhere in this plan. AttributedString for markdown. System SQLite only.
- Protocol ground truth: the five `fixtures/2026-07-09-*.jsonl` captures + "Probe findings" above. When a shape is in question, open the fixture and look. Do not guess.
- Tolerant decoding is load-bearing: unknown event/line types must keep flowing to `.unknown`/`.system`/`.other` paths, never throw.
- `fixtures/` content is real data from Ben's machine, approved for **local** use only. Do not publish it or quote transcript content in commit messages.
- All new tests are offline by default. The two new live tests are env-gated behind `CLAUDEKIT_LIVE=1` (haiku, cheap, few).
- UI tasks (8–12) end with a build + a scripted manual smoke check instead of unit tests; everything with logic goes in FabledCore where `swift test` reaches it.
- Existing tests must stay green. When a task deliberately changes an existing test (Tasks 1–3 do), the task says so explicitly; any other breakage is a bug in your change.

## File structure

```
project.yml                      # XcodeGen manifest (Task 8, committed)
Fabled.xcodeproj                 # generated output (gitignored)
Package.swift                    # MODIFY: + FabledCore target/product (Task 5)
App/                             # Fabled app target sources (xcodebuild only)
  FabledApp.swift                # @main, SIGPIPE ignore, AppModel bootstrap (Task 8)
  RootView.swift                 # NavigationSplitView shell (Task 8, grows 9/10/12)
  Theme.swift                    # clay color, serif fonts (Task 8)
  SidebarView.swift              # live sessions + history + search (Task 9)
  WelcomeView.swift              # empty-selection pane, New Session (Task 10)
  ConversationView.swift         # live timeline + composer host + toolbar (Task 10)
  TimelineItemViews.swift        # per-item renderers + tool card (Task 10)
  HistoricalSessionView.swift    # read-only transcript + Resume/Fork (Task 10)
  ComposerView.swift             # input, send/stop, shortcuts (Task 11)
  PermissionCardView.swift       # allow / always-allow / deny (Task 11)
  ModelPickerMenu.swift          # catalog menu + custom sheet (Task 12)
Sources/ClaudeKit/
  AgentSession.swift             # MODIFY: request-id returns, deinit, write guard (T1)
  AgentEvent.swift               # MODIFY: Equatable, StreamEvent + case (T1, T3)
  AgentEventDecoder.swift        # MODIFY: stream_event decoding (T3)
  Outbound.swift                 # MODIFY: PermissionDecision reshape (T2)
  SessionConfiguration.swift     # MODIFY: includePartialMessages (T3)
  SearchIndex.swift              # MODIFY: serialize reindex, vanish-skip, sessionSummaries (T4)
Sources/FabledCore/
  TimelineItem.swift             # the locked UI vocabulary (T5)
  TimelineReducer.swift          # pure reducer + transcript replay (T5, T6)
  ToolCallSummary.swift          # one-line tool summaries (T5)
  PermissionPrompt.swift         # card labels from suggestions (T6)
  AgentConnection.swift          # injectable transport (T7)
  ChatSession.swift              # per-conversation view model (T7)
  AppModel.swift                 # sidebar/search/session lifecycle (T9)
  JSONPretty.swift               # JSONValue → display string (T5)
Sources/fabled-probe/main.swift  # MODIFY: new PermissionDecision spelling (T2)
Tests/ClaudeKitTests/
  AgentSessionTests.swift        # MODIFY (T1, T2)
  OutboundTests.swift            # MODIFY (T2)
  SessionConfigurationTests.swift# MODIFY (T3)
  StreamEventTests.swift         # NEW (T3)
  SearchIndexTests.swift         # MODIFY (T4)
  LiveSessionTests.swift         # MODIFY: 2 gated live tests (T2, T3)
  Fixtures.swift                 # MODIFY: 2026-07-09 fixture loaders (T3)
Tests/FabledCoreTests/
  TimelineReducerTests.swift     # NEW (T5)
  TimelineReplayTests.swift      # NEW (T6): fixture + transcript replay
  PermissionPromptTests.swift    # NEW (T6)
  ChatSessionTests.swift         # NEW (T7)
  AppModelTests.swift            # NEW (T9)
  Support.swift                  # NEW: fake connection, waitUntil, corpus builder (T7)
```

Dependency order: Tasks 1–4 (ClaudeKit) → 5–7 (FabledCore) → 8 (scaffold) → 9–12 (UI) → 13 (gate). Tasks 1–4 are independent of each other except 2 after 1 (both touch AgentSession); execute in numeric order.

### Task 1: ClaudeKit — correlatable control ops + AgentSession lifecycle hardening

Fixes the two Plan-1 FOLLOWUPS Plan 3 consumes immediately: control-op methods mint-and-discard their `request_id` (ChatSession must correlate the initialize response to harvest the command/model catalog), and a dropped `AgentSession` leaks a live `claude` process and hangs its stream consumers.

**Files:**
- Modify: `Sources/ClaudeKit/AgentSession.swift`
- Modify: `Sources/ClaudeKit/AgentEvent.swift` (one line: `Equatable`)
- Modify: `Tests/ClaudeKitTests/AgentSessionTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/ClaudeKitTests/AgentSessionTests.swift`:

```swift
    func testControlOpsReturnCorrelatableRequestIDs() async throws {
        let session = AgentSession(configuration: SessionConfiguration(
            workingDirectory: FileManager.default.temporaryDirectory))
        // No start() needed: write() no-ops without a pipe, ids are minted regardless.
        let modelID = await session.setModel("sonnet")
        let permissionID = await session.setPermissionMode("plan")
        let interruptID = await session.interrupt()
        XCTAssertFalse(modelID.isEmpty)
        XCTAssertEqual(Set([modelID, permissionID, interruptID]).count, 3,
                       "every control op must mint a unique id")
        XCTAssertEqual(AgentSession.initializeRequestID, "init",
                       "initialize id is a known constant so ChatSession can correlate the catalog response")
    }

    func testAgentEventIsEquatable() throws {
        let a = try AgentEventDecoder.decode(Fixtures.initLine)
        let b = try AgentEventDecoder.decode(Fixtures.initLine)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, AgentEvent.terminated(exitCode: 0))
    }

    /// A slow child that records SIGTERM to a marker file — deterministic
    /// evidence of `deinit` termination without depending on process reaping.
    private func makeSlowChild() throws -> (executable: URL, marker: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let marker = dir.appendingPathComponent("terminated.marker")
        let script = dir.appendingPathComponent("claude")
        let body = """
        #!/bin/bash
        trap 'echo terminated > '\(marker.path)'; exit 0' TERM
        while true; do sleep 0.1; done
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: script.path)
        return (script, marker)
    }

    func testDeallocTerminatesChildAndFinishesStream() async throws {
        let (fake, marker) = try makeSlowChild()
        var config = SessionConfiguration(
            workingDirectory: FileManager.default.temporaryDirectory)
        config.executable = fake

        var session: AgentSession? = AgentSession(configuration: config)
        try await session!.start()
        let events = await session!.events

        session = nil  // drop the only reference while the child runs

        // 1. The child receives SIGTERM.
        let deadline = ContinuousClock.now + .seconds(5)
        while !FileManager.default.fileExists(atPath: marker.path),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path),
                      "deinit must terminate the child process")

        // 2. The events stream finishes instead of hanging its consumer.
        let consumer = Task { for await _ in events {} }
        let finished = await withTaskGroup(of: Bool.self) { group in
            group.addTask { _ = await consumer.value; return true }
            group.addTask { try? await Task.sleep(for: .seconds(5)); return false }
            let first = await group.next()!
            group.cancelAll()
            return first
        }
        XCTAssertTrue(finished, "events stream must finish when the session deallocates")
    }

    func testSendAfterTerminationIsSafe() async throws {
        // Child exits immediately after init; writes after .terminated must be
        // short-circuited. Before the fix this test can crash the whole test
        // runner with SIGPIPE — that crash IS the failure signal.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("claude")
        let initLine = String(data: Fixtures.initLine, encoding: .utf8)!
        try "#!/bin/bash\necho '\(initLine)'\nexit 0\n"
            .write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: script.path)

        var config = SessionConfiguration(
            workingDirectory: FileManager.default.temporaryDirectory)
        config.executable = script
        let session = AgentSession(configuration: config)
        try await session.start()
        for await event in await session.events {
            if case .terminated = event { break }
        }
        await session.send("into the void")   // must not write to the dead pipe
        await session.interrupt()             // ditto for control ops
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter AgentSessionTests 2>&1 | tail -20`
Expected: compile errors — `setModel` returns `Void` (cannot assign to `let modelID`), `initializeRequestID` and `AgentEvent` `Equatable` don't exist. That is the failure mode for this step.

- [ ] **Step 3: Implement**

In `Sources/ClaudeKit/AgentEvent.swift`, make the enum `Equatable` (all payloads already are):

```swift
public enum AgentEvent: Sendable, Equatable {
```

In `Sources/ClaudeKit/AgentSession.swift`:

1. Add the constant and a deinit right after the actor's stored properties:

```swift
    /// Fixed id for the initialize handshake so consumers can correlate the
    /// CLI's catalog response (commands, models, account) without plumbing.
    /// One id per process is safe: each AgentSession owns its own child.
    public static let initializeRequestID = "init"

    /// Terminating via `terminate()` is the intended path; this is the
    /// safety net for a dropped session. Dropping a Continuation does NOT
    /// finish its stream (Plan 2 scar) — finish explicitly or a consumer
    /// awaiting `events` hangs forever on a dead session.
    deinit {
        process?.terminate()
        readTask?.cancel()
        continuation?.finish()
    }
```

2. Add the termination flag with the other stored properties, and use it:

```swift
    private var isTerminated = false
```

3. Replace the control-op methods, `sendControl`, `write`, and `handleTermination`:

```swift
    @discardableResult
    public func interrupt() -> String {
        sendControl(subtype: "interrupt")
    }

    @discardableResult
    public func setModel(_ model: String) -> String {
        sendControl(subtype: "set_model", extra: ["model": .string(model)])
    }

    @discardableResult
    public func setPermissionMode(_ mode: String) -> String {
        sendControl(subtype: "set_permission_mode", extra: ["mode": .string(mode)])
    }

    private func sendControl(subtype: String, extra: [String: JSONValue] = [:]) -> String {
        let requestID = UUID().uuidString
        write(Outbound.controlRequest(
            requestID: requestID, subtype: subtype, extra: extra))
        return requestID
    }

    private func write(_ data: Data) {
        // After child death the pipe write raises SIGPIPE, which `try?`
        // cannot swallow (it is a signal, not an error) — short-circuit.
        guard !isTerminated else { return }
        try? stdinPipe?.fileHandleForWriting.write(contentsOf: data)
    }

    private func handleTermination(exitCode: Int32) async {
        isTerminated = true
        await readTask?.value
        continuation?.yield(.terminated(exitCode: exitCode))
        continuation?.finish()
        continuation = nil
        readTask = nil
    }
```

4. In `start()`, use the constant for the handshake:

```swift
        write(Outbound.initialize(requestID: Self.initializeRequestID))
```

5. In the existing `testSessionLifecycle`, strengthen the handshake assertion (the capture file must show the constant id):

```swift
        XCTAssertTrue(written.contains(#""request_id":"init""#),
                      "handshake must use the well-known initialize id")
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test 2>&1 | tail -5`
Expected: all tests pass (suite count grows by 4).

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeKit/AgentSession.swift Sources/ClaudeKit/AgentEvent.swift Tests/ClaudeKitTests/AgentSessionTests.swift
git commit -m "feat(claudekit): correlatable control-op request ids, safe teardown on dealloc"
```

---

### Task 2: ClaudeKit — permission responses the CLI actually accepts

The 2026-07-09 probe proved `.allow(updatedInput: nil)` is rejected by the CLI (ZodError → tool denied; `fixtures/2026-07-09-perm-allow-noinput.jsonl`) and that echoing `permission_suggestions` back as `updatedPermissions` persists always-allow rules (`fixtures/2026-07-09-perm-allow-persist.jsonl`). Reshape `PermissionDecision` accordingly.

**Files:**
- Modify: `Sources/ClaudeKit/Outbound.swift`
- Modify: `Sources/ClaudeKit/AgentSession.swift` (respond passes the request's input)
- Modify: `Sources/fabled-probe/main.swift` (new spelling)
- Modify: `Tests/ClaudeKitTests/OutboundTests.swift`
- Modify: `Tests/ClaudeKitTests/AgentSessionTests.swift` (new spelling)
- Modify: `Tests/ClaudeKitTests/LiveSessionTests.swift` (one gated live test)

- [ ] **Step 1: Write the failing tests**

Append to `Tests/ClaudeKitTests/OutboundTests.swift`:

```swift
    func testAllowWithoutEditsEchoesRequestedInput() throws {
        let requested = JSONValue.object(["command": .string("git init")])
        let data = Outbound.permissionResponse(
            requestID: "r1", decision: .allowAsRequested, requestedInput: requested)
        let decoded = try JSONValue(parsing: data)
        let inner = decoded["response"]?["response"]
        XCTAssertEqual(inner?["behavior"]?.stringValue, "allow")
        XCTAssertEqual(inner?["updatedInput"], requested,
                       "updatedInput is REQUIRED by the CLI's Zod schema — omit it and the tool is denied")
        XCTAssertNil(inner?["updatedPermissions"])
    }

    func testAllowWithRuleSuggestionsCarriesUpdatedPermissions() throws {
        // Shape recorded live: fixtures/2026-07-09-perm-allow-persist.jsonl
        let suggestion = JSONValue.object([
            "type": .string("addRules"),
            "rules": .array([.object([
                "toolName": .string("Bash"),
                "ruleContent": .string("git init *"),
            ])]),
            "behavior": .string("allow"),
            "destination": .string("localSettings"),
        ])
        let data = Outbound.permissionResponse(
            requestID: "r1",
            decision: .allow(updatedInput: nil, updatedPermissions: [suggestion]),
            requestedInput: .object([:]))
        let decoded = try JSONValue(parsing: data)
        let inner = decoded["response"]?["response"]
        XCTAssertEqual(inner?["updatedPermissions"]?.arrayValue?.first, suggestion)
        XCTAssertEqual(inner?["updatedInput"], .object([:]))
    }

    func testAllowWithEditedInputPrefersTheEdit() throws {
        let edited = JSONValue.object(["command": .string("git init --quiet")])
        let data = Outbound.permissionResponse(
            requestID: "r1",
            decision: .allow(updatedInput: edited, updatedPermissions: nil),
            requestedInput: .object(["command": .string("git init")]))
        let decoded = try JSONValue(parsing: data)
        XCTAssertEqual(decoded["response"]?["response"]?["updatedInput"], edited)
    }

    func testDenyStillOmitsInputFields() throws {
        let data = Outbound.permissionResponse(
            requestID: "r1", decision: .deny(message: "not now"),
            requestedInput: .object([:]))
        let decoded = try JSONValue(parsing: data)
        let inner = decoded["response"]?["response"]
        XCTAssertEqual(inner?["behavior"]?.stringValue, "deny")
        XCTAssertEqual(inner?["message"]?.stringValue, "not now")
        XCTAssertNil(inner?["updatedInput"])
    }
```

Append to `Tests/ClaudeKitTests/LiveSessionTests.swift` (match the file's existing gating/helper style; the test must skip unless `CLAUDEKIT_LIVE=1`):

```swift
    /// Regression for the 2026-07-09 probe finding: a plain approval must
    /// actually run the tool (no ZodError denial).
    func testLiveAllowAsRequestedRunsTool() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CLAUDEKIT_LIVE"] == "1",
                          "live test — set CLAUDEKIT_LIVE=1 to run")
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        var config = SessionConfiguration(workingDirectory: scratch)
        config.model = "haiku"
        config.extraArguments = ["--setting-sources", ""]

        let session = AgentSession(configuration: config)
        try await session.start()
        await session.send("Run exactly this bash command: git init")

        var denials: [JSONValue] = []
        for await event in await session.events {
            switch event {
            case .controlRequest(let request):
                if let permission = PermissionRequest(request) {
                    await session.respond(to: permission, decision: .allowAsRequested)
                }
            case .result(let turn):
                denials = turn.permissionDenials
                await session.terminate()
            case .terminated:
                break
            default:
                break
            }
        }
        XCTAssertTrue(denials.isEmpty, "allowAsRequested must not be denied: \(denials)")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: scratch.appendingPathComponent(".git").path),
            "the allowed tool must actually have run")
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift build 2>&1 | tail -10`
Expected: compile errors — `allowAsRequested` doesn't exist, `permissionResponse` has no `requestedInput:` parameter.

- [ ] **Step 3: Implement**

In `Sources/ClaudeKit/Outbound.swift`, replace `PermissionDecision` and `permissionResponse`:

```swift
public enum PermissionDecision: Sendable, Equatable {
    /// `updatedInput: nil` means "run with the input exactly as requested".
    /// The CLI *requires* the `updatedInput` field (Zod-validated; omitting
    /// it denies the tool — fixtures/2026-07-09-perm-allow-noinput.jsonl),
    /// so encoding substitutes the request's own input.
    /// `updatedPermissions`: pass the request's `permission_suggestions`
    /// entries verbatim to persist an always-allow rule (the CLI writes it
    /// to the suggestion's `destination`).
    case allow(updatedInput: JSONValue?, updatedPermissions: [JSONValue]?)
    case deny(message: String?)

    /// Plain approval: original input, no persisted rules.
    public static let allowAsRequested = PermissionDecision.allow(
        updatedInput: nil, updatedPermissions: nil)
}
```

```swift
    public static func permissionResponse(
        requestID: String, decision: PermissionDecision, requestedInput: JSONValue
    ) -> Data {
        var inner: [String: JSONValue]
        switch decision {
        case .allow(let updatedInput, let updatedPermissions):
            inner = [
                "behavior": .string("allow"),
                "updatedInput": updatedInput ?? requestedInput,
            ]
            if let updatedPermissions, !updatedPermissions.isEmpty {
                inner["updatedPermissions"] = .array(updatedPermissions)
            }
        case .deny(let message):
            inner = ["behavior": .string("deny")]
            if let message { inner["message"] = .string(message) }
        }
        return encodeLine(.object([
            "type": .string("control_response"),
            "response": .object([
                "subtype": .string("success"),
                "request_id": .string(requestID),
                "response": .object(inner),
            ]),
        ]))
    }
```

In `Sources/ClaudeKit/AgentSession.swift`:

```swift
    public func respond(to request: PermissionRequest, decision: PermissionDecision) {
        write(Outbound.permissionResponse(requestID: request.requestID,
                                          decision: decision,
                                          requestedInput: request.input))
    }
```

Update the two existing callers to the new spelling:
- `Tests/ClaudeKitTests/AgentSessionTests.swift` `testPermissionRoundTrip`: `.allow(updatedInput: perm.input)` → `.allowAsRequested`
- `Sources/fabled-probe/main.swift`: `.allow(updatedInput: perm.input)` → `.allowAsRequested`

If `OutboundTests.swift` has existing `permissionResponse` tests using the old signature, update them mechanically (add `requestedInput: .object([:])` and the second associated value) — do not weaken their assertions.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test 2>&1 | tail -5`
Expected: all pass (live test reports skipped).

- [ ] **Step 5 (optional but recommended, costs ~1¢): Run the live test once**

Run: `CLAUDEKIT_LIVE=1 swift test --filter testLiveAllowAsRequestedRunsTool 2>&1 | tail -5`
Expected: PASS. If it fails with denials, the CLI shape moved — STOP and report to the coordinator with the raw output.

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeKit/Outbound.swift Sources/ClaudeKit/AgentSession.swift Sources/fabled-probe/main.swift Tests/ClaudeKitTests/OutboundTests.swift Tests/ClaudeKitTests/AgentSessionTests.swift Tests/ClaudeKitTests/LiveSessionTests.swift
git commit -m "fix(claudekit): allow responses always carry updatedInput; support updatedPermissions persistence"
```

---

### Task 3: ClaudeKit — `--include-partial-messages` + typed `stream_event` decoding

Plan 1 deliberately deferred streaming deltas; they currently decode to `.unknown`. Fabled needs them for live text. The shapes were recorded on 2026-07-09 (`fixtures/2026-07-09-partial-messages.jsonl`) — fixture-first, exactly as the brief required.

**Files:**
- Modify: `Sources/ClaudeKit/SessionConfiguration.swift`
- Modify: `Sources/ClaudeKit/AgentEvent.swift`
- Modify: `Sources/ClaudeKit/AgentEventDecoder.swift`
- Modify: `Tests/ClaudeKitTests/SessionConfigurationTests.swift`
- Create: `Tests/ClaudeKitTests/StreamEventTests.swift`
- Modify: `Tests/ClaudeKitTests/LiveSessionTests.swift` (one gated live test)

- [ ] **Step 1: Write the failing tests**

Create `Tests/ClaudeKitTests/StreamEventTests.swift`:

```swift
import XCTest
@testable import ClaudeKit

final class StreamEventTests: XCTestCase {
    /// Decode every line of a fixture through the live-stream decoder.
    private func decodeEvents(_ fixture: String) throws -> [AgentEvent] {
        try Fixtures.lines(fixture).map { try AgentEventDecoder.decode($0) }
    }

    func testPartialMessagesFixtureCensus() throws {
        let events = try decodeEvents("2026-07-09-partial-messages.jsonl")
        XCTAssertEqual(events.count, 24)

        var messageStart = 0, blockStart = 0, textDelta = 0, thinkingDelta = 0
        var other = 0, blockStop = 0, messageDelta = 0, messageStop = 0
        var texts: [String] = []
        var stopReasons: [String?] = []
        for event in events {
            guard case .streamEvent(let stream) = event else { continue }
            XCTAssertNotNil(stream.sessionID)
            XCTAssertNotNil(stream.uuid)
            switch stream.kind {
            case .messageStart: messageStart += 1
            case .contentBlockStart: blockStart += 1
            case .textDelta(_, let text): textDelta += 1; texts.append(text)
            case .thinkingDelta: thinkingDelta += 1
            case .inputJSONDelta: XCTFail("fixture has no tool_use deltas")
            case .contentBlockStop: blockStop += 1
            case .messageDelta(let reason): messageDelta += 1; stopReasons.append(reason)
            case .messageStop: messageStop += 1
            case .other: other += 1
            }
        }
        // Counts pinned from the recorded capture (see plan "Probe findings").
        XCTAssertEqual(messageStart, 1)
        XCTAssertEqual(blockStart, 2)          // 1 thinking block + 1 text block
        XCTAssertEqual(thinkingDelta, 3)
        XCTAssertEqual(textDelta, 1)
        XCTAssertEqual(texts, ["The quick brown fox jumps over the lazy dog."])
        XCTAssertEqual(other, 1)               // signature_delta → .other, tolerant
        XCTAssertEqual(blockStop, 2)
        XCTAssertEqual(messageDelta, 1)
        XCTAssertEqual(stopReasons, ["end_turn"])
        XCTAssertEqual(messageStop, 1)
    }

    func testContentBlockStartCarriesTypedBlocks() throws {
        let events = try decodeEvents("2026-07-09-partial-messages.jsonl")
        var blocks: [ContentBlock] = []
        for event in events {
            if case .streamEvent(let stream) = event,
               case .contentBlockStart(_, let block) = stream.kind {
                blocks.append(block)
            }
        }
        guard blocks.count == 2 else { return XCTFail("expected 2 block starts") }
        guard case .thinking = blocks[0] else { return XCTFail("first block is thinking") }
        guard case .text = blocks[1] else { return XCTFail("second block is text") }
    }

    /// Protocol-drift gate: every line of every 2026-07-09 capture decodes to
    /// a typed event — zero `.unknown` across the whole probe corpus.
    func testAllProbeFixturesDecodeWithZeroUnknowns() throws {
        let fixtures = [
            "2026-07-09-partial-messages.jsonl",
            "2026-07-09-control-ops.jsonl",
            "2026-07-09-perm-allow-noinput.jsonl",
            "2026-07-09-perm-allow-persist.jsonl",
            "2026-07-09-interrupt.jsonl",
        ]
        for fixture in fixtures {
            for line in try Fixtures.lines(fixture) {
                let event = try AgentEventDecoder.decode(line)
                if case .unknown(let type, _) = event {
                    XCTFail("\(fixture): unknown event type \(type)")
                }
            }
        }
    }

    func testUnknownStreamEventKindsStayTolerant() throws {
        let line = Data(#"""
        {"type":"stream_event","event":{"type":"hologram_delta","index":0},"session_id":"s1","uuid":"u1"}
        """#.utf8)
        guard case .streamEvent(let stream) = try AgentEventDecoder.decode(line),
              case .other(let type) = stream.kind else {
            return XCTFail("unknown stream kinds must decode to .other, never throw")
        }
        XCTAssertEqual(type, "hologram_delta")
    }
}
```

Append to `Tests/ClaudeKitTests/SessionConfigurationTests.swift`:

```swift
    func testIncludePartialMessagesFlag() {
        var config = SessionConfiguration(workingDirectory: URL(fileURLWithPath: "/tmp"))
        XCTAssertTrue(config.arguments().contains("--include-partial-messages"),
                      "streaming deltas are on by default — Fabled always wants them")
        config.includePartialMessages = false
        XCTAssertFalse(config.arguments().contains("--include-partial-messages"))
    }
```

Also update this file's existing baseline-arguments test (it asserts the exact default argument list): insert `"--include-partial-messages"` after `"--permission-prompt-tool", "stdio"`.

Append to `Tests/ClaudeKitTests/LiveSessionTests.swift`:

```swift
    func testLiveStreamDeltasArrive() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CLAUDEKIT_LIVE"] == "1",
                          "live test — set CLAUDEKIT_LIVE=1 to run")
        var config = SessionConfiguration(
            workingDirectory: FileManager.default.temporaryDirectory)
        config.model = "haiku"
        config.extraArguments = ["--setting-sources", ""]
        let session = AgentSession(configuration: config)
        try await session.start()
        await session.send("Reply with one short sentence about rivers.")

        var sawTextDelta = false
        for await event in await session.events {
            switch event {
            case .streamEvent(let stream):
                if case .textDelta = stream.kind { sawTextDelta = true }
            case .result:
                await session.terminate()
            default:
                break
            }
        }
        XCTAssertTrue(sawTextDelta, "partial messages must produce text deltas")
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter StreamEventTests 2>&1 | tail -10`
Expected: compile errors (`.streamEvent`, `StreamEvent`, `includePartialMessages` don't exist).

- [ ] **Step 3: Implement**

In `Sources/ClaudeKit/SessionConfiguration.swift` add the property and flag:

```swift
    /// Emit Anthropic SSE deltas as `stream_event` lines. On by default:
    /// the conversation UI streams text as it generates.
    public var includePartialMessages = true
```

and in `arguments()`, immediately after the `"--permission-prompt-tool", "stdio",` entry:

```swift
        if includePartialMessages { args.append("--include-partial-messages") }
```

In `Sources/ClaudeKit/AgentEvent.swift`, add the payload type and case:

```swift
/// One `stream_event` line: an Anthropic SSE event wrapped with session
/// routing. Shape recorded 2026-07-09 (fixtures/2026-07-09-partial-messages.jsonl):
/// {"type":"stream_event","event":{…},"session_id":…,"parent_tool_use_id":…,"uuid":…}
public struct StreamEvent: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case messageStart
        case contentBlockStart(index: Int, block: ContentBlock)
        case textDelta(index: Int, text: String)
        case thinkingDelta(index: Int, thinking: String)
        case inputJSONDelta(index: Int, partialJSON: String)
        case contentBlockStop(index: Int)
        case messageDelta(stopReason: String?)
        case messageStop
        /// Tolerant fallback — signature_delta lands here today, and so will
        /// whatever the API adds next. Never a decode failure.
        case other(type: String)
    }

    public let kind: Kind
    public let sessionID: String?
    public let parentToolUseID: String?
    public let uuid: String?
    public let raw: JSONValue
}
```

and the case in the enum:

```swift
    case streamEvent(StreamEvent)
```

In `Sources/ClaudeKit/AgentEventDecoder.swift`, add to the `switch type` in `decode(raw:)` (before `default`):

```swift
        case "stream_event":
            return .streamEvent(Self.streamEvent(from: raw))
```

and the builder alongside the other static helpers:

```swift
    static func streamEvent(from raw: JSONValue) -> StreamEvent {
        let event = raw["event"]
        let type = event?["type"]?.stringValue ?? ""
        let index = (event?["index"]?.doubleValue).map(Int.init) ?? 0
        let kind: StreamEvent.Kind
        switch type {
        case "message_start":
            kind = .messageStart
        case "content_block_start":
            kind = .contentBlockStart(
                index: index, block: contentBlock(event?["content_block"] ?? .null))
        case "content_block_delta":
            switch event?["delta"]?["type"]?.stringValue {
            case "text_delta":
                kind = .textDelta(index: index,
                                  text: event?["delta"]?["text"]?.stringValue ?? "")
            case "thinking_delta":
                kind = .thinkingDelta(index: index,
                                      thinking: event?["delta"]?["thinking"]?.stringValue ?? "")
            case "input_json_delta":
                kind = .inputJSONDelta(index: index,
                                       partialJSON: event?["delta"]?["partial_json"]?.stringValue ?? "")
            case let deltaType:
                kind = .other(type: "content_block_delta/\(deltaType ?? "")")
            }
        case "content_block_stop":
            kind = .contentBlockStop(index: index)
        case "message_delta":
            kind = .messageDelta(stopReason: event?["delta"]?["stop_reason"]?.stringValue)
        case "message_stop":
            kind = .messageStop
        default:
            kind = .other(type: type)
        }
        return StreamEvent(
            kind: kind,
            sessionID: raw["session_id"]?.stringValue,
            parentToolUseID: raw["parent_tool_use_id"]?.stringValue,
            uuid: raw["uuid"]?.stringValue,
            raw: raw)
    }
```

Note: `testUnknownStreamEventKindsStayTolerant` expects `.other(type: "hologram_delta")` — an unknown *event type* reports the bare type; only unknown *delta types* get the `content_block_delta/` prefix.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test 2>&1 | tail -5`
Expected: all pass. The zero-unknown census test proves the whole probe corpus decodes typed.

- [ ] **Step 5 (optional, ~1¢): Run the live delta test once**

Run: `CLAUDEKIT_LIVE=1 swift test --filter testLiveStreamDeltasArrive 2>&1 | tail -5`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeKit/SessionConfiguration.swift Sources/ClaudeKit/AgentEvent.swift Sources/ClaudeKit/AgentEventDecoder.swift Tests/ClaudeKitTests/SessionConfigurationTests.swift Tests/ClaudeKitTests/StreamEventTests.swift Tests/ClaudeKitTests/LiveSessionTests.swift
git commit -m "feat(claudekit): typed stream_event decoding, --include-partial-messages default"
```

---

### Task 4: ClaudeKit — SearchIndex hardening + index-backed session list

The two Important Plan-2 FOLLOWUPS, fixed *before* AppModel wires the watcher to `reindex()`: overlapping reindex passes can violate `UNIQUE(path)` and abort, and a file vanishing mid-pass aborts the remaining files. Plus the new sidebar API: `sessionSummaries()` reads the whole session list from the `files` table (one SQL query, index titles authoritative) instead of a 3.7 s title-derivation walk.

**Files:**
- Modify: `Sources/ClaudeKit/SearchIndex.swift`
- Modify: `Tests/ClaudeKitTests/SearchIndexTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/ClaudeKitTests/SearchIndexTests.swift` (reuse the file's existing temp-corpus helpers for creating a projects root populated from `fixtures/transcripts/`; the names below assume a helper that returns `(store, index)` over a fresh temp corpus — adapt to the file's actual helpers):

```swift
    func testConcurrentReindexPassesSerialize() async throws {
        let (_, index) = try makeStoreAndIndex()   // fresh corpus, nothing indexed yet
        // Before the fix: two passes race the files-table snapshot, both see a
        // new file as absent, and the second INSERT dies on UNIQUE(path).
        try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<8 { group.addTask { try await index.reindex() } }
            for try await _ in group {}   // no pass may throw
        }
        let fileCount = try await index.indexedFileCount()
        XCTAssertEqual(fileCount, 3, "every session indexed exactly once")
    }

    func testVanishedFileIsSkippedNotFatal() async throws {
        let (store, index) = try makeStoreAndIndex()
        _ = try await index.reindex()

        // Make one file unreadable — the enumeration still stamps it, the
        // read fails, exactly like a file deleted between stat and open.
        let project = try await store.projects()[0]
        let stamps = try await store.sessionFileStamps(in: project)
        let victim = stamps[0].url
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000], ofItemAtPath: victim.path)
        defer { try? FileManager.default.setAttributes(
            [.posixPermissions: 0o644], ofItemAtPath: victim.path) }
        // Touch its mtime so the incremental check re-reads it.
        try FileManager.default.setAttributes(
            [.modificationDate: Date()], ofItemAtPath: victim.path)

        // Before the fix this throws out of reindex() and skips everything
        // after the victim; after, it skips only the victim.
        let reindexed = try await index.reindex()
        XCTAssertEqual(reindexed, 0, "unreadable file must be skipped, not counted")
        let fileCount = try await index.indexedFileCount()
        XCTAssertEqual(fileCount, 3, "existing rows for the victim survive")
    }

    func testSessionSummariesComeFromIndexRows() async throws {
        let (_, index) = try makeStoreAndIndex()
        _ = try await index.reindex()
        let summaries = try await index.sessionSummaries()
        XCTAssertEqual(summaries.count, 3)
        // Newest first.
        let dates = summaries.map(\.lastActivity)
        XCTAssertEqual(dates, dates.sorted(by: >))
        // Titles are the index's whole-file titles (authoritative source).
        let titled = summaries.first { $0.id == "97c70bda-ac5d-4e12-982e-8e6e35dd2674" }
        XCTAssertNotNil(titled)
        XCTAssertEqual(titled?.title,
                       try await index.indexedTitle(forSessionID: titled!.id))
        // Untitled sessions fall back to the session id.
        let untitled = summaries.first { $0.id == "036b246d-0898-4ace-89b2-8fdd6c107fc4" }
        XCTAssertEqual(untitled?.title, untitled?.id)
    }
```

(If the existing helper corpus contains a different fixture count, adjust the literals to that corpus — the assertions' *structure* is what matters. The session ids above are the real fixture stems from `fixtures/transcripts/README.md`.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter SearchIndexTests 2>&1 | tail -10`
Expected: `sessionSummaries` does not compile; the two robustness tests fail or compile-fail depending on helper shape.

- [ ] **Step 3: Implement**

In `Sources/ClaudeKit/SearchIndex.swift`:

1. Serialize passes by chaining (rename the existing body to `performReindex`):

```swift
    private var reindexChain: Task<Int, any Error>?

    /// Walks every project; parses only files whose (mtime, size) changed;
    /// drops index rows for files that vanished. Returns the number of
    /// files (re)parsed — 0 on a warm no-change pass.
    ///
    /// Overlapping calls serialize: each pass waits for the previous one, so
    /// two watcher ticks can never race the files-table snapshot (the
    /// UNIQUE(path) violation from the Plan 2 review).
    @discardableResult
    public func reindex() async throws -> Int {
        let previous = reindexChain
        let task = Task { [self] in
            _ = try? await previous?.value
            return try await performReindex()
        }
        reindexChain = task
        return try await task.value
    }

    private func performReindex() async throws -> Int {
        // … existing reindex() body, with ONE change in the stamp loop:
        // the file read moves here and a vanished file skips instead of throwing.
    }
```

2. In the stamp loop inside `performReindex`, replace the `indexFile` call:

```swift
                // A session deleted (or made unreadable) between the stat and
                // this read must not abort the pass — skip it; the next pass
                // prunes its rows once enumeration stops listing it.
                guard let data = try? Data(contentsOf: stamp.url, options: .mappedIfSafe) else {
                    continue
                }
                try indexFile(stamp, data: data, project: project, replacing: known[path]?.id)
                reindexed += 1
```

and change `indexFile` to accept the data instead of reading it:

```swift
    private func indexFile(
        _ stamp: SessionFileStamp, data: Data, project: ProjectFolder, replacing existingID: Int64?
    ) throws {
        try db.exec("BEGIN IMMEDIATE")
        // … rest unchanged (delete the old `let data = try Data(…)` line).
```

3. Add the sidebar API (next to `search`):

```swift
    /// Sidebar list source: every indexed session, newest first, straight
    /// from the files table — no session files are opened. Titles here are
    /// the whole-file authoritative ones (DECISIONS: title-source authority).
    public func sessionSummaries() async throws -> [SessionSummary] {
        let projectsByName = Dictionary(
            uniqueKeysWithValues: try await store.projects().map { ($0.flattenedName, $0) })
        let statement = try db.prepare("""
            SELECT path, session_id, project, mtime, size, title
            FROM files ORDER BY mtime DESC
            """)
        var summaries: [SessionSummary] = []
        while try statement.step() {
            let path = statement.columnText(0)
            let sessionID = statement.columnText(1)
            let projectName = statement.columnText(2)
            let fileURL = URL(fileURLWithPath: path)
            let project = projectsByName[projectName] ?? ProjectFolder(
                flattenedName: projectName,
                originalPath: projectName,
                directoryURL: fileURL.deletingLastPathComponent())
            summaries.append(SessionSummary(
                id: sessionID,
                project: project,
                fileURL: fileURL,
                title: statement.columnIsNull(5) ? sessionID : statement.columnText(5),
                lastActivity: Date(timeIntervalSince1970: statement.columnDouble(3)),
                approximateSizeBytes: Int(statement.columnInt64(4))))
        }
        return summaries
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test 2>&1 | tail -5`
Expected: all pass, including the pre-existing SearchIndex suite.

- [ ] **Step 5: Run the perf gate against the real corpus (read-only, no commit gate change)**

Run: `CLAUDEKIT_PERF=1 swift test --filter PerformanceGateTests 2>&1 | tail -15`
Expected: all gates still green (the chaining adds one suspension per pass, nothing per-file). If the warm-reindex gate (<1 s) regresses, STOP and report numbers.

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeKit/SearchIndex.swift Tests/ClaudeKitTests/SearchIndexTests.swift
git commit -m "fix(claudekit): serialize overlapping reindex passes, survive vanishing files, add sessionSummaries()"
```

---

### Task 5: FabledCore — TimelineItem + reducer core (text streaming, tool calls)

The pure heart of the UI. `TimelineItem` is the brief's locked vocabulary; the reducer translates events and is where the tests concentrate.

**Files:**
- Modify: `Package.swift`
- Create: `Sources/FabledCore/TimelineItem.swift`
- Create: `Sources/FabledCore/TimelineReducer.swift`
- Create: `Sources/FabledCore/ToolCallSummary.swift`
- Create: `Sources/FabledCore/JSONPretty.swift`
- Create: `Tests/FabledCoreTests/TimelineReducerTests.swift`

- [ ] **Step 1: Add the FabledCore target**

Replace `Package.swift`'s `products`/`targets` with:

```swift
    products: [
        .library(name: "ClaudeKit", targets: ["ClaudeKit"]),
        .library(name: "FabledCore", targets: ["FabledCore"]),
        .executable(name: "fabled-probe", targets: ["fabled-probe"]),
    ],
    targets: [
        .target(name: "ClaudeKit"),
        .target(name: "FabledCore", dependencies: ["ClaudeKit"]),
        .executableTarget(name: "fabled-probe", dependencies: ["ClaudeKit"]),
        .testTarget(name: "ClaudeKitTests", dependencies: ["ClaudeKit"]),
        .testTarget(name: "FabledCoreTests", dependencies: ["FabledCore"]),
    ]
```

Run: `mkdir -p Sources/FabledCore Tests/FabledCoreTests`

- [ ] **Step 2: Write the failing tests**

Create `Tests/FabledCoreTests/TimelineReducerTests.swift`:

```swift
import XCTest
import ClaudeKit
@testable import FabledCore

final class TimelineReducerTests: XCTestCase {
    private func event(_ json: String) throws -> AgentEvent {
        try AgentEventDecoder.decode(Data(json.utf8))
    }

    private func reduceAll(_ jsonLines: [String]) throws -> [TimelineItem] {
        try jsonLines.reduce(into: [TimelineItem]()) { items, json in
            items = TimelineReducer.reduce(items, try event(json))
        }
    }

    func testStreamingTextCoalescesThenFinalizes() throws {
        var items: [TimelineItem] = []
        items = TimelineReducer.reduce(items, try event(
            #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hel"}},"session_id":"s1","uuid":"u1"}"#))
        items = TimelineReducer.reduce(items, try event(
            #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"lo"}},"session_id":"s1","uuid":"u2"}"#))
        XCTAssertEqual(items.count, 1, "deltas coalesce into one streaming item")
        guard case .assistantText(let id, "Hello", true) = items[0] else {
            return XCTFail("expected streaming assistantText, got \(items[0])")
        }
        XCTAssertEqual(id, "u1", "first delta's uuid names the item")

        items = TimelineReducer.reduce(items, try event(
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Hello!"}]},"session_id":"s1","uuid":"a1"}"#))
        XCTAssertEqual(items.count, 1)
        guard case .assistantText("u1", "Hello!", false) = items[0] else {
            return XCTFail("final message must replace the streamed text in place, same id")
        }
    }

    func testAssistantWithoutPriorDeltasAppends() throws {
        let items = try reduceAll([
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Hi"}]},"uuid":"a1"}"#,
        ])
        XCTAssertEqual(items.count, 1)
        guard case .assistantText("a1-0", "Hi", false) = items[0] else {
            return XCTFail("got \(items[0])")
        }
    }

    func testEmptyTextBlocksAreSkipped() throws {
        let items = try reduceAll([
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":""},{"type":"thinking","thinking":"hmm"}]},"uuid":"a1"}"#,
        ])
        XCTAssertTrue(items.isEmpty, "thinking-only / empty-text messages render nothing")
    }

    func testToolCallLifecycle() throws {
        var items = try reduceAll([
            // streamed start announces the call…
            #"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"t1","name":"Bash","input":{}}},"uuid":"u1"}"#,
            // …the final assistant message carries the full input…
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"git init"}}]},"uuid":"a1"}"#,
        ])
        XCTAssertEqual(items.count, 1, "same tool_use id must upsert, not duplicate")
        guard case .toolCall("t1", "Bash", let summary, _, nil, nil, true) = items[0] else {
            return XCTFail("got \(items[0])")
        }
        XCTAssertEqual(summary, "git init")

        // …and the tool_result fills it in.
        items = TimelineReducer.reduce(items, try event(
            #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"done","is_error":false}]},"uuid":"r1"}"#))
        guard case .toolCall("t1", "Bash", _, _, .string("done"), false, false) = items[0] else {
            return XCTFail("result must land on the matching call: \(items[0])")
        }
    }

    func testEmptyToolResultListIsNoOp() throws {
        // Synthetic user lines ("[Request interrupted]", local-command echoes)
        // decode to .toolResult([]) — they must not disturb the timeline.
        let items = try reduceAll([
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Hi"}]},"uuid":"a1"}"#,
            #"{"type":"user","message":{"role":"user","content":"<local-command-stdout>ok</local-command-stdout>"},"isReplay":true,"uuid":"x1"}"#,
        ])
        XCTAssertEqual(items.count, 1)
    }

    func testSubagentTrafficIsIgnored() throws {
        let items = try reduceAll([
            #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"sub"}},"parent_tool_use_id":"t9","uuid":"u1"}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"sub"}]},"parent_tool_use_id":"t9","uuid":"a1"}"#,
        ])
        XCTAssertTrue(items.isEmpty, "parent_tool_use_id != nil is subagent chatter (grouped UI is Plan 4)")
    }

    func testUserEchoAppends() {
        let items = TimelineReducer.appendUserMessage([], id: "m1", text: "hello")
        XCTAssertEqual(items, [.userMessage(id: "m1", text: "hello")])
    }

    func testToolSummaries() {
        XCTAssertEqual(ToolCallSummary.summarize(
            name: "Bash", input: .object(["command": .string("git status\n# second line")])),
            "git status")
        XCTAssertEqual(ToolCallSummary.summarize(
            name: "Read", input: .object(["file_path": .string("/tmp/a.txt")])),
            "/tmp/a.txt")
        XCTAssertEqual(ToolCallSummary.summarize(
            name: "MysteryTool", input: .object(["x": .number(1)])),
            "MysteryTool")
        XCTAssertEqual(ToolCallSummary.summarize(
            name: "Bash", input: .object([:])), "Bash")
    }

    func testJSONPretty() {
        XCTAssertEqual(JSONPretty.string(.string("plain text")), "plain text")
        XCTAssertTrue(JSONPretty.string(.object(["b": .number(1), "a": .bool(true)]))
            .contains("\"a\" : true"))
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --filter TimelineReducerTests 2>&1 | tail -10`
Expected: compile errors — the FabledCore types don't exist yet.

- [ ] **Step 4: Implement**

Create `Sources/FabledCore/TimelineItem.swift`:

```swift
import ClaudeKit

/// The UI vocabulary: everything the conversation view renders. Views never
/// pattern-match raw AgentEvents — TimelineReducer is the only translator.
/// This shape is the locked contract from the Plan 3 brief.
public enum TimelineItem: Sendable, Identifiable, Equatable {
    case userMessage(id: String, text: String)
    case assistantText(id: String, markdown: String, isStreaming: Bool)
    case toolCall(id: String, name: String, summary: String,
                  input: JSONValue, result: JSONValue?, isError: Bool?, isRunning: Bool)
    case permission(id: String, request: PermissionRequest,
                    resolution: PermissionDecision?)
    case turnSummary(id: String, result: TurnResult)
    case notice(id: String, text: String)
    case raw(id: String, type: String, raw: JSONValue)

    public var id: String {
        switch self {
        case .userMessage(let id, _),
             .assistantText(let id, _, _),
             .toolCall(let id, _, _, _, _, _, _),
             .permission(let id, _, _),
             .turnSummary(let id, _),
             .notice(let id, _),
             .raw(let id, _, _):
            return id
        }
    }

    /// Non-nil for tool calls — the reducer's result-matching key.
    var toolCallID: String? {
        if case .toolCall(let id, _, _, _, _, _, _) = self { return id }
        return nil
    }
}
```

Create `Sources/FabledCore/ToolCallSummary.swift`:

```swift
import ClaudeKit

/// One-line summaries for collapsed tool cards.
enum ToolCallSummary {
    static func summarize(name: String, input: JSONValue) -> String {
        let detail: String? = switch name {
        case "Bash": input["command"]?.stringValue
        case "Read", "Write", "Edit", "NotebookEdit": input["file_path"]?.stringValue
        case "Glob", "Grep": input["pattern"]?.stringValue
        case "WebFetch": input["url"]?.stringValue
        case "WebSearch": input["query"]?.stringValue
        case "Task", "Agent": input["description"]?.stringValue
        default: nil
        }
        guard let detail, !detail.isEmpty else { return name }
        let firstLine = detail.split(separator: "\n", omittingEmptySubsequences: true)
            .first.map(String.init) ?? detail
        return String(firstLine.prefix(120))
    }
}
```

Create `Sources/FabledCore/JSONPretty.swift`:

```swift
import ClaudeKit
import Foundation

/// Display formatting for JSONValue payloads in tool cards and raw views.
public enum JSONPretty {
    public static func string(_ value: JSONValue) -> String {
        // Bare strings read better unquoted (tool results are usually text).
        if let text = value.stringValue { return text }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
```

Create `Sources/FabledCore/TimelineReducer.swift`:

```swift
import ClaudeKit

/// Pure translation from protocol events to UI items. This is where
/// correctness lives — every behavior is replay-tested against recorded
/// fixtures.
public enum TimelineReducer {
    public static func reduce(_ items: [TimelineItem], _ event: AgentEvent) -> [TimelineItem] {
        var items = items
        switch event {
        case .streamEvent(let stream):
            reduceStream(&items, stream)
        case .assistant(let message):
            reduceAssistant(&items, message)
        case .toolResult(let results):
            // Empty lists (synthetic user lines: interrupts, local-command
            // echoes) fall through harmlessly — nothing matches.
            for result in results { fillToolResult(&items, result) }
        case .systemInit, .system, .controlResponse:
            break  // ChatSession consumes these; nothing renders inline.
        case .controlRequest, .result, .unknown, .terminated:
            break  // Task 6 extends these.
        }
        return items
    }

    /// Local echo for a message the user just sent (the CLI does not echo
    /// prompts back on the live stream).
    public static func appendUserMessage(
        _ items: [TimelineItem], id: String, text: String
    ) -> [TimelineItem] {
        items + [.userMessage(id: id, text: text)]
    }

    // MARK: - Streaming deltas

    private static func reduceStream(_ items: inout [TimelineItem], _ stream: StreamEvent) {
        guard stream.parentToolUseID == nil else { return }  // subagent traffic: Plan 4
        switch stream.kind {
        case .contentBlockStart(_, .toolUse(let id, let name, let input)):
            upsertToolCall(&items, id: id, name: name, input: input)
        case .textDelta(_, let text):
            if case .assistantText(let id, let markdown, true) = items.last {
                items[items.count - 1] = .assistantText(
                    id: id, markdown: markdown + text, isStreaming: true)
            } else {
                items.append(.assistantText(
                    id: stream.uuid ?? "stream-\(items.count)",
                    markdown: text, isStreaming: true))
            }
        case .messageStart, .contentBlockStart, .thinkingDelta, .inputJSONDelta,
             .contentBlockStop, .messageDelta, .messageStop, .other:
            break  // thinking state lives on ChatSession; partial tool input is Plan 4.
        }
    }

    // MARK: - Final assistant messages

    private static func reduceAssistant(_ items: inout [TimelineItem], _ message: AssistantMessage) {
        guard message.parentToolUseID == nil else { return }
        let baseID = message.raw["uuid"]?.stringValue ?? "assistant-\(items.count)"
        var textIndex = 0
        for block in message.content {
            switch block {
            case .text(let text):
                guard !text.isEmpty else { break }
                finalizeText(&items, text: text, fallbackID: "\(baseID)-\(textIndex)")
                textIndex += 1
            case .toolUse(let id, let name, let input):
                upsertToolCall(&items, id: id, name: name, input: input)
            case .thinking, .unknown:
                break
            }
        }
    }

    /// The final message replaces streamed provisional text in place — same
    /// item id, so SwiftUI sees an update, not a remove+insert.
    private static func finalizeText(_ items: inout [TimelineItem], text: String, fallbackID: String) {
        if case .assistantText(let id, _, true) = items.last {
            items[items.count - 1] = .assistantText(id: id, markdown: text, isStreaming: false)
        } else {
            items.append(.assistantText(id: fallbackID, markdown: text, isStreaming: false))
        }
    }

    // MARK: - Tool calls

    private static func upsertToolCall(
        _ items: inout [TimelineItem], id: String, name: String, input: JSONValue
    ) {
        let summary = ToolCallSummary.summarize(name: name, input: input)
        if let index = items.lastIndex(where: { $0.toolCallID == id }) {
            guard case .toolCall(_, _, _, _, let result, let isError, let isRunning) = items[index]
            else { return }
            items[index] = .toolCall(id: id, name: name, summary: summary, input: input,
                                     result: result, isError: isError, isRunning: isRunning)
        } else {
            items.append(.toolCall(id: id, name: name, summary: summary, input: input,
                                   result: nil, isError: nil, isRunning: true))
        }
    }

    private static func fillToolResult(_ items: inout [TimelineItem], _ result: ToolResult) {
        guard let index = items.lastIndex(where: { $0.toolCallID == result.toolUseID }),
              case .toolCall(let id, let name, let summary, let input, _, _, _) = items[index]
        else { return }
        items[index] = .toolCall(id: id, name: name, summary: summary, input: input,
                                 result: result.content, isError: result.isError,
                                 isRunning: false)
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test 2>&1 | tail -5`
Expected: all pass (ClaudeKit suite + new FabledCore suite).

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/FabledCore Tests/FabledCoreTests
git commit -m "feat(core): FabledCore target with TimelineItem and streaming reducer core"
```

---

### Task 6: FabledCore — reducer completion + fixture & transcript replay

Permissions, turn summaries, notices, raw passthrough, local permission resolution, and the read-only transcript mapping — then the reducer is proven against every recorded capture and the real transcript fixtures.

**Files:**
- Modify: `Sources/FabledCore/TimelineReducer.swift`
- Create: `Sources/FabledCore/PermissionPrompt.swift`
- Create: `Tests/FabledCoreTests/TimelineReplayTests.swift`
- Create: `Tests/FabledCoreTests/PermissionPromptTests.swift`
- Create: `Tests/FabledCoreTests/Support.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/FabledCoreTests/Support.swift` (fixture access — Tests/FabledCoreTests sits at the same depth as ClaudeKitTests):

```swift
import Foundation
import ClaudeKit

enum CoreFixtures {
    static var fixturesDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // FabledCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("fixtures")
    }

    static func lines(_ name: String) throws -> [Data] {
        let text = try String(contentsOf: fixturesDir.appendingPathComponent(name),
                              encoding: .utf8)
        return text.split(separator: "\n").map { Data($0.utf8) }
    }

    /// Live-stream fixture → events.
    static func events(_ name: String) throws -> [AgentEvent] {
        try lines(name).map { try AgentEventDecoder.decode($0) }
    }

    /// On-disk transcript fixture → entries.
    static func transcript(_ name: String) throws -> [TranscriptEntry] {
        try lines("transcripts/\(name)").map { try TranscriptDecoder.decode($0) }
    }
}
```

Create `Tests/FabledCoreTests/TimelineReplayTests.swift`:

```swift
import XCTest
import ClaudeKit
@testable import FabledCore

final class TimelineReplayTests: XCTestCase {
    private func replay(_ fixture: String) throws -> [TimelineItem] {
        try CoreFixtures.events(fixture).reduce([]) { TimelineReducer.reduce($0, $1) }
    }

    private func census(_ items: [TimelineItem])
        -> (user: Int, text: Int, tool: Int, toolWithResult: Int,
            permission: Int, turn: Int, notice: Int, raw: Int) {
        var c = (user: 0, text: 0, tool: 0, toolWithResult: 0,
                 permission: 0, turn: 0, notice: 0, raw: 0)
        for item in items {
            switch item {
            case .userMessage: c.user += 1
            case .assistantText: c.text += 1
            case .toolCall(_, _, _, _, let result, _, _):
                c.tool += 1
                if result != nil { c.toolWithResult += 1 }
            case .permission: c.permission += 1
            case .turnSummary: c.turn += 1
            case .notice: c.notice += 1
            case .raw: c.raw += 1
            }
        }
        return c
    }

    // MARK: reducer completion units

    func testPermissionRequestAppendsAndResolves() throws {
        let event = try AgentEventDecoder.decode(Data(#"""
        {"type":"control_request","request_id":"p1","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"git init"},"permission_suggestions":[]}}
        """#.utf8))
        var items = TimelineReducer.reduce([], event)
        guard case .permission("p1", let request, nil) = items[0] else {
            return XCTFail("got \(items)")
        }
        XCTAssertEqual(request.toolName, "Bash")

        items = TimelineReducer.resolvePermission(
            items, requestID: "p1", decision: .allowAsRequested)
        // Note: .allowAsRequested is a static property, not a case — bind
        // and compare, don't pattern-match it.
        guard case .permission("p1", _, let resolution) = items[0],
              resolution == .allowAsRequested else {
            return XCTFail("resolution must be recorded: \(items)")
        }
    }

    func testNonPermissionControlRequestsRenderNothing() throws {
        let event = try AgentEventDecoder.decode(Data(#"""
        {"type":"control_request","request_id":"h1","request":{"subtype":"hook_callback"}}
        """#.utf8))
        XCTAssertTrue(TimelineReducer.reduce([], event).isEmpty)
    }

    func testResultUnknownAndTerminated() throws {
        var items = TimelineReducer.reduce([], try AgentEventDecoder.decode(Data(#"""
        {"type":"result","subtype":"success","is_error":false,"total_cost_usd":0.01,"uuid":"r1"}
        """#.utf8)))
        guard case .turnSummary("r1", _) = items[0] else { return XCTFail("\(items)") }

        items = TimelineReducer.reduce(items, try AgentEventDecoder.decode(Data(#"""
        {"type":"hologram_projection","payload":{"x":1},"uuid":"h1"}
        """#.utf8)))
        guard case .raw("h1", "hologram_projection", _) = items[1] else { return XCTFail("\(items)") }

        items = TimelineReducer.reduce(items, .terminated(exitCode: 1))
        guard case .notice("terminated", let text) = items[2] else { return XCTFail("\(items)") }
        XCTAssertTrue(text.contains("exit code 1"))
    }

    // MARK: live-capture replays (ground truth)

    func testPartialMessagesReplay() throws {
        let items = try replay("2026-07-09-partial-messages.jsonl")
        XCTAssertEqual(items.count, 2)
        guard case .assistantText(_, "The quick brown fox jumps over the lazy dog.", false) = items[0]
        else { return XCTFail("\(items)") }
        guard case .turnSummary = items[1] else { return XCTFail("\(items)") }
    }

    func testControlOpsReplay() throws {
        let items = try replay("2026-07-09-control-ops.jsonl")
        let c = census(items)
        XCTAssertEqual(c.turn, 3, "three turns ran (incl. the queued message)")
        XCTAssertEqual(c.raw, 0)
        let texts = items.compactMap { item -> String? in
            if case .assistantText(_, let markdown, false) = item { return markdown }
            return nil
        }
        XCTAssertEqual(texts.count, 3)
        XCTAssertEqual(texts[1], "QUEUED-OK")
        XCTAssertEqual(texts[2], "4")
    }

    func testPermissionPersistReplay() throws {
        let items = try replay("2026-07-09-perm-allow-persist.jsonl")
        let c = census(items)
        XCTAssertEqual(c.permission, 1)
        XCTAssertEqual(c.tool, 1)
        XCTAssertEqual(c.toolWithResult, 1, "the allowed git init ran and returned")
        XCTAssertEqual(c.turn, 1)
        XCTAssertEqual(c.raw, 0)
    }

    func testInterruptReplay() throws {
        let items = try replay("2026-07-09-interrupt.jsonl")
        guard case .turnSummary(_, let turn) = items.last else {
            return XCTFail("\(items)")
        }
        XCTAssertEqual(turn.subtype, "error_during_execution")
        XCTAssertTrue(turn.isError)
    }

    // MARK: on-disk transcript replays (read-only history)

    func testTitledTranscriptReplay() throws {
        let items = TimelineReducer.items(
            fromTranscript: try CoreFixtures.transcript("real-titled-session.jsonl"))
        let c = census(items)
        XCTAssertEqual(c.user, 1)
        XCTAssertEqual(c.text, 1)
        XCTAssertEqual(c.tool, 0)
        XCTAssertEqual(c.permission, 0)
        XCTAssertEqual(c.notice, 0)
        XCTAssertEqual(c.raw, 0)
        XCTAssertEqual(c.turn, 0, "on-disk result lines are subagent caches, never turn summaries")
    }

    func testToolUseTranscriptReplay() throws {
        let items = TimelineReducer.items(
            fromTranscript: try CoreFixtures.transcript("real-tooluse-session.jsonl"))
        let c = census(items)
        // Counts pinned from a line-by-line census of the fixture during
        // plan-writing. If these fail, the reducer diverged from the rules —
        // investigate the diff, do not blindly update the numbers.
        XCTAssertEqual(c.user, 4)
        XCTAssertEqual(c.text, 17)
        XCTAssertEqual(c.tool, 24)
        XCTAssertEqual(c.toolWithResult, 23)
        XCTAssertEqual(c.raw, 0)
        // First item is the human prompt — machine/meta lines never lead.
        guard case .userMessage = items.first else { return XCTFail("\(items.first.debugDescription)") }
    }

    func testUntitledTranscriptReplay() throws {
        let items = TimelineReducer.items(
            fromTranscript: try CoreFixtures.transcript("real-untitled-session.jsonl"))
        let c = census(items)
        XCTAssertEqual(c.user, 1)
        XCTAssertEqual(c.text, 1)
    }
}
```

Create `Tests/FabledCoreTests/PermissionPromptTests.swift`:

```swift
import XCTest
import ClaudeKit
@testable import FabledCore

final class PermissionPromptTests: XCTestCase {
    /// Suggestion shape recorded live 2026-07-09.
    private let suggestion = JSONValue.object([
        "type": .string("addRules"),
        "rules": .array([.object([
            "toolName": .string("Bash"),
            "ruleContent": .string("git init *"),
        ])]),
        "behavior": .string("allow"),
        "destination": .string("localSettings"),
    ])

    func testAlwaysAllowLabel() {
        XCTAssertEqual(PermissionPrompt.alwaysAllowLabel(for: [suggestion]),
                       "Always allow: Bash(git init *)")
        XCTAssertNil(PermissionPrompt.alwaysAllowLabel(for: []))
        XCTAssertNil(PermissionPrompt.alwaysAllowLabel(
            for: [.object(["type": .string("setMode")])]),
            "only addRules suggestions make an always-allow button")
    }

    func testCommandSummaryPrefersBashCommand() throws {
        let event = try AgentEventDecoder.decode(Data(#"""
        {"type":"control_request","request_id":"p1","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"git init"},"permission_suggestions":[]}}
        """#.utf8))
        guard case .controlRequest(let request) = event,
              let permission = PermissionRequest(request) else {
            return XCTFail("fixture line must decode to a permission request")
        }
        XCTAssertEqual(PermissionPrompt.commandSummary(for: permission), "git init")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "TimelineReplayTests|PermissionPromptTests" 2>&1 | tail -10`
Expected: compile errors (`resolvePermission`, `items(fromTranscript:)`, `PermissionPrompt` missing); the unit tests for result/unknown/terminated fail (reducer currently ignores them).

- [ ] **Step 3: Implement**

In `Sources/FabledCore/TimelineReducer.swift`, replace the `case .controlRequest, .result, .unknown, .terminated: break` placeholder in `reduce` with:

```swift
        case .controlRequest(let request):
            if let permission = PermissionRequest(request) {
                items.append(.permission(id: permission.requestID,
                                         request: permission, resolution: nil))
            }
            // Non-permission control requests (hook_callback, mcp_message)
            // are plumbing, not conversation — Plan 4 decides their UI.
        case .result(let turn):
            items.append(.turnSummary(
                id: turn.raw["uuid"]?.stringValue ?? "turn-\(items.count)",
                result: turn))
        case .unknown(let type, let raw):
            items.append(.raw(id: raw["uuid"]?.stringValue ?? "raw-\(items.count)",
                              type: type, raw: raw))
        case .terminated(let exitCode):
            items.append(.notice(
                id: "terminated",
                text: exitCode == 0
                    ? "Session ended."
                    : "Session ended unexpectedly (exit code \(exitCode))."))
```

and add the two public functions:

```swift
    /// Records the user's decision on the matching (unresolved) card.
    /// A local action, not a protocol event — the CLI never echoes it.
    public static func resolvePermission(
        _ items: [TimelineItem], requestID: String, decision: PermissionDecision
    ) -> [TimelineItem] {
        items.map { item in
            if case .permission(let id, let request, nil) = item, id == requestID {
                return .permission(id: id, request: request, resolution: decision)
            }
            return item
        }
    }

    /// Read-only history: an on-disk transcript rendered through the same
    /// vocabulary. Main-chain only — sidechain (subagent) traffic, titles,
    /// and bookkeeping lines are not conversation.
    public static func items(fromTranscript entries: [TranscriptEntry]) -> [TimelineItem] {
        var items: [TimelineItem] = []
        var lineIndex = 0
        for entry in entries {
            lineIndex += 1
            switch entry {
            case .userPrompt(let text, let context, _):
                guard !context.isSidechain, !context.isMeta else { continue }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                // Machine-generated prompts (<command-name>…, caveats) are
                // not conversation; same rule as title derivation.
                guard !trimmed.isEmpty, !trimmed.hasPrefix("<") else { continue }
                items = appendUserMessage(items, id: context.uuid ?? "line-\(lineIndex)", text: text)
            case .event(let event, let context):
                guard !context.isSidechain else { continue }
                items = reduce(items, event)
            case .title, .summary, .queueOperation, .attachment, .sessionMeta, .unknown:
                continue
            }
        }
        return items
    }
```

Create `Sources/FabledCore/PermissionPrompt.swift`:

```swift
import ClaudeKit

/// Text the permission card shows, derived from the CLI's request payload.
public enum PermissionPrompt {
    /// "Always allow: Bash(git init *)" — from the first addRules suggestion.
    /// nil when the CLI offered no rules (the button is hidden).
    public static func alwaysAllowLabel(for suggestions: [JSONValue]) -> String? {
        for suggestion in suggestions
        where suggestion["type"]?.stringValue == "addRules" {
            let rules = (suggestion["rules"]?.arrayValue ?? []).compactMap { rule -> String? in
                guard let tool = rule["toolName"]?.stringValue else { return nil }
                guard let content = rule["ruleContent"]?.stringValue, !content.isEmpty else {
                    return tool
                }
                return "\(tool)(\(content))"
            }
            if !rules.isEmpty {
                return "Always allow: " + rules.joined(separator: ", ")
            }
        }
        return nil
    }

    /// What is being approved, one line: Bash commands verbatim, other
    /// tools by their summarized input.
    public static func commandSummary(for request: PermissionRequest) -> String {
        request.input["command"]?.stringValue
            ?? ToolCallSummary.summarize(name: request.toolName, input: request.input)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test 2>&1 | tail -5`
Expected: all pass. If a transcript-replay count is off by a small margin, diff the reducer rules against the "on-disk transcript replays" comments — the pinned numbers come from the fixture census, not guesswork.

- [ ] **Step 5: Commit**

```bash
git add Sources/FabledCore/TimelineReducer.swift Sources/FabledCore/PermissionPrompt.swift Tests/FabledCoreTests
git commit -m "feat(core): reducer completion — permissions, summaries, notices, transcript replay"
```

---

### Task 7: FabledCore — ChatSession view model

The `@MainActor @Observable` model one conversation view binds to. Transport is injected (`AgentConnection`) so every behavior is testable without processes; `AgentSession` is the production implementation.

**Files:**
- Create: `Sources/FabledCore/AgentConnection.swift`
- Create: `Sources/FabledCore/ChatSession.swift`
- Modify: `Tests/FabledCoreTests/Support.swift`
- Create: `Tests/FabledCoreTests/ChatSessionTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/FabledCoreTests/Support.swift`:

```swift
/// Records everything a ChatSession sends outward.
actor OutboundRecorder {
    enum Entry: Equatable {
        case send(String)
        case respond(requestID: String, behavior: String)
        case interrupt
        case setModel(String)
        case setPermissionMode(String)
        case terminate
    }
    private(set) var entries: [Entry] = []
    func record(_ entry: Entry) { entries.append(entry) }
}

func makeFakeConnection()
    -> (AgentConnection, AsyncStream<AgentEvent>.Continuation, OutboundRecorder) {
    let (stream, continuation) = AsyncStream.makeStream(of: AgentEvent.self)
    let recorder = OutboundRecorder()
    let connection = AgentConnection(
        events: { stream },
        send: { await recorder.record(.send($0)) },
        respond: { request, decision in
            let behavior = if case .allow = decision { "allow" } else { "deny" }
            await recorder.record(.respond(requestID: request.requestID, behavior: behavior))
        },
        interrupt: { await recorder.record(.interrupt) },
        setModel: { await recorder.record(.setModel($0)) },
        setPermissionMode: { await recorder.record(.setPermissionMode($0)) },
        terminate: { await recorder.record(.terminate) })
    return (connection, continuation, recorder)
}

/// Polls a MainActor condition until it holds or the test fails.
@MainActor
func waitUntil(
    timeout: Duration = .seconds(2),
    _ what: String = "condition",
    _ condition: () -> Bool
) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
        if clock.now > deadline {
            return XCTFail("timed out waiting for \(what)")
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

/// Outbound calls hop through a Task — wait for the recorder to catch up.
func waitForEntries(
    _ recorder: OutboundRecorder, count: Int, timeout: Duration = .seconds(2)
) async -> [OutboundRecorder.Entry] {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        let entries = await recorder.entries
        if entries.count >= count { return entries }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await recorder.entries
}
```

Add `import XCTest` and `import FabledCore` to the top of `Support.swift` as needed (`@testable import FabledCore` for internal access).

Create `Tests/FabledCoreTests/ChatSessionTests.swift`:

```swift
import XCTest
import ClaudeKit
@testable import FabledCore

@MainActor
final class ChatSessionTests: XCTestCase {
    private func makeSession()
        -> (ChatSession, AsyncStream<AgentEvent>.Continuation, OutboundRecorder) {
        let (connection, continuation, recorder) = makeFakeConnection()
        let session = ChatSession(
            connection: connection,
            workingDirectory: URL(fileURLWithPath: "/tmp/demo"))
        session.begin()
        return (session, continuation, recorder)
    }

    private func yield(_ continuation: AsyncStream<AgentEvent>.Continuation,
                       _ json: String) throws {
        continuation.yield(try AgentEventDecoder.decode(Data(json.utf8)))
    }

    func testInitCatalogHarvest() async throws {
        let (session, continuation, _) = makeSession()
        try yield(continuation, #"""
        {"type":"control_response","response":{"subtype":"success","request_id":"init","response":{"commands":[{"name":"compact","description":"Compact the conversation","argumentHint":""}],"models":[{"value":"default","resolvedModel":"claude-opus-4-8","displayName":"Default (recommended)","description":"Opus"},{"value":"haiku","displayName":"Haiku"}],"output_style":"default"}}}
        """#)
        await waitUntil("catalog") { !session.commands.isEmpty }
        XCTAssertEqual(session.commands.map(\.name), ["compact"])
        XCTAssertEqual(session.models.map(\.value), ["default", "haiku"])
        XCTAssertEqual(session.models[0].displayName, "Default (recommended)")
    }

    func testSystemInitPopulatesModelAndMode() async throws {
        let (session, continuation, _) = makeSession()
        try yield(continuation, #"""
        {"type":"system","subtype":"init","session_id":"s1","model":"claude-haiku-4-5-20251001","cwd":"/tmp/demo","permissionMode":"default","tools":[],"slash_commands":[],"agents":[],"skills":[],"claude_code_version":"2.1.204"}
        """#)
        await waitUntil("init") { session.info != nil }
        XCTAssertEqual(session.currentModel, "claude-haiku-4-5-20251001")
        XCTAssertEqual(session.permissionMode, "default")
        XCTAssertNil(session.versionNote, "tested version raises no banner")
    }

    func testVersionNoteOnDrift() async throws {
        let (session, continuation, _) = makeSession()
        try yield(continuation, #"""
        {"type":"system","subtype":"init","session_id":"s1","model":"m","cwd":"/","permissionMode":"default","tools":[],"slash_commands":[],"agents":[],"skills":[],"claude_code_version":"9.9.9"}
        """#)
        await waitUntil("init") { session.info != nil }
        XCTAssertNotNil(session.versionNote)
    }

    func testSendEchoesAndTracksTurns() async throws {
        let (session, continuation, recorder) = makeSession()
        session.send("  hello  ")
        XCTAssertTrue(session.isWorking)
        guard case .userMessage(_, "hello") = session.timeline.first else {
            return XCTFail("send must echo the trimmed prompt: \(session.timeline)")
        }
        let entries = await waitForEntries(recorder, count: 1)
        XCTAssertEqual(entries, [.send("hello")])

        // A queued second message keeps the session working through the
        // first result (probe finding 6).
        session.send("second")
        try yield(continuation, #"{"type":"result","subtype":"success","is_error":false,"total_cost_usd":0.01,"uuid":"r1"}"#)
        await waitUntil("first result") { session.cumulativeCostUSD > 0 }
        XCTAssertTrue(session.isWorking, "one of two turns still in flight")
        try yield(continuation, #"{"type":"result","subtype":"success","is_error":false,"total_cost_usd":0.02,"uuid":"r2"}"#)
        await waitUntil("second result") { !session.isWorking }
        XCTAssertEqual(session.cumulativeCostUSD, 0.03, accuracy: 0.0001)
    }

    func testPermissionFlow() async throws {
        let (session, continuation, recorder) = makeSession()
        try yield(continuation, #"""
        {"type":"control_request","request_id":"p1","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"git init"},"permission_suggestions":[]}}
        """#)
        await waitUntil("pending permission") { session.pendingPermission != nil }
        XCTAssertEqual(session.activityState, .needsApproval)
        let request = session.pendingPermission!

        session.respond(to: request, decision: .allowAsRequested)
        XCTAssertNil(session.pendingPermission)
        let entries = await waitForEntries(recorder, count: 1)
        XCTAssertEqual(entries, [.respond(requestID: "p1", behavior: "allow")])
        let permissionItem = session.timeline.first {
            if case .permission = $0 { return true } else { return false }
        }
        guard case .permission(_, _, let resolution) = permissionItem,
              resolution == .allowAsRequested else {
            return XCTFail("resolution must land in the timeline")
        }
    }

    func testTerminatedEndsSession() async throws {
        let (session, continuation, _) = makeSession()
        continuation.yield(.terminated(exitCode: 0))
        continuation.finish()
        await waitUntil("ended") { session.hasEnded }
        XCTAssertEqual(session.activityState, .ended)
        XCTAssertFalse(session.isWorking)
    }

    func testSeedTimeline() {
        let (session, _, _) = makeSession()
        session.seed(timeline: [.userMessage(id: "m1", text: "old prompt")])
        XCTAssertEqual(session.timeline.count, 1)
        session.seed(timeline: [.userMessage(id: "m2", text: "ignored")])
        XCTAssertEqual(session.timeline.first?.id, "m1",
                       "seed only fills an empty timeline")
    }

    func testTitleFromFirstPrompt() {
        let (session, _, _) = makeSession()
        XCTAssertEqual(session.title, "demo", "falls back to the folder name")
        session.send("Fix the login bug\nplease")
        XCTAssertEqual(session.title, "Fix the login bug")
    }
}
```

Note the polling loops on `recorder.entries`: outbound calls hop through a `Task`, so tests must wait, not assert immediately. Keep the loops as written (bounded by the test's own timeout).

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ChatSessionTests 2>&1 | tail -10`
Expected: compile errors — `ChatSession`, `AgentConnection` don't exist.

- [ ] **Step 3: Implement**

Create `Sources/FabledCore/AgentConnection.swift`:

```swift
import ClaudeKit
import Foundation

/// The transport a ChatSession talks through. Injected so view-model
/// behavior is fully testable; `live(_:)` wraps the real AgentSession.
public struct AgentConnection: Sendable {
    public var events: @Sendable () async -> AsyncStream<AgentEvent>
    public var send: @Sendable (String) async -> Void
    public var respond: @Sendable (PermissionRequest, PermissionDecision) async -> Void
    public var interrupt: @Sendable () async -> Void
    public var setModel: @Sendable (String) async -> Void
    public var setPermissionMode: @Sendable (String) async -> Void
    public var terminate: @Sendable () async -> Void

    public init(
        events: @escaping @Sendable () async -> AsyncStream<AgentEvent>,
        send: @escaping @Sendable (String) async -> Void,
        respond: @escaping @Sendable (PermissionRequest, PermissionDecision) async -> Void,
        interrupt: @escaping @Sendable () async -> Void,
        setModel: @escaping @Sendable (String) async -> Void,
        setPermissionMode: @escaping @Sendable (String) async -> Void,
        terminate: @escaping @Sendable () async -> Void
    ) {
        self.events = events
        self.send = send
        self.respond = respond
        self.interrupt = interrupt
        self.setModel = setModel
        self.setPermissionMode = setPermissionMode
        self.terminate = terminate
    }

    public static func live(_ session: AgentSession) -> AgentConnection {
        AgentConnection(
            events: { await session.events },
            send: { await session.send($0) },
            respond: { await session.respond(to: $0, decision: $1) },
            interrupt: { _ = await session.interrupt() },
            setModel: { _ = await session.setModel($0) },
            setPermissionMode: { _ = await session.setPermissionMode($0) },
            terminate: { await session.terminate() })
    }
}

/// One entry of the initialize response's slash-command catalog.
public struct SlashCommand: Sendable, Equatable, Identifiable {
    public let name: String
    public let commandDescription: String
    public let argumentHint: String
    public var id: String { name }

    public init(name: String, commandDescription: String, argumentHint: String) {
        self.name = name
        self.commandDescription = commandDescription
        self.argumentHint = argumentHint
    }
}

/// One entry of the initialize response's model catalog (probe finding 9).
public struct ModelOption: Sendable, Equatable, Identifiable {
    public let value: String
    public let resolvedModel: String?
    public let displayName: String
    public let optionDescription: String?
    public var id: String { value }

    public init(value: String, resolvedModel: String?,
                displayName: String, optionDescription: String?) {
        self.value = value
        self.resolvedModel = resolvedModel
        self.displayName = displayName
        self.optionDescription = optionDescription
    }
}
```

(`commandDescription`/`optionDescription` avoid colliding with `CustomStringConvertible.description` in SwiftUI contexts. Update the test's `.map(\.name)` expectations accordingly — the test code above already uses only `name`/`value`/`displayName`.)

Create `Sources/FabledCore/ChatSession.swift`:

```swift
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
            cumulativeCostUSD += turn.totalCostUSD ?? 0
            lastUsage = turn.usage
        case .streamEvent(let stream):
            switch stream.kind {
            case .thinkingDelta: isThinking = true
            case .textDelta, .contentBlockStart: isThinking = false
            default: break
            }
        case .terminated:
            hasEnded = true
            isWorking = false
            isThinking = false
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test 2>&1 | tail -5`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/FabledCore/AgentConnection.swift Sources/FabledCore/ChatSession.swift Tests/FabledCoreTests/Support.swift Tests/FabledCoreTests/ChatSessionTests.swift
git commit -m "feat(core): ChatSession view model over injectable AgentConnection"
```

---

### Task 8: XcodeGen scaffold — Fabled.app boots

No TDD here (nothing to unit-test); the gate is a green `xcodebuild` from a committed, reviewable `project.yml`.

**Files:**
- Create: `project.yml`
- Create: `App/FabledApp.swift`
- Create: `App/RootView.swift`
- Create: `App/Theme.swift`
- Modify: `.gitignore` (create if missing)

- [ ] **Step 1: Verify xcodegen is installed**

Run: `xcodegen --version`
Expected: `Version: 2.44.1` (any ≥ 2.40 is fine). If missing: `brew install xcodegen`.

- [ ] **Step 2: Write the manifest and app skeleton**

Create `project.yml`:

```yaml
name: Fabled
options:
  bundleIdPrefix: dev.fabled
  deploymentTarget:
    macOS: "15.0"
  createIntermediateGroups: true
packages:
  ClaudeKit:
    path: .
targets:
  Fabled:
    type: application
    platform: macOS
    sources:
      - App
    dependencies:
      - package: ClaudeKit
        product: ClaudeKit
      - package: ClaudeKit
        product: FabledCore
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: dev.fabled.Fabled
        MARKETING_VERSION: "0.1.0"
        CURRENT_PROJECT_VERSION: 1
        SWIFT_VERSION: "6.0"
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_LSApplicationCategoryType: public.app-category.developer-tools
        INFOPLIST_KEY_NSHumanReadableCopyright: ""
        # Dev build: no sandbox (spawns `claude`, reads ~/.claude), ad-hoc signing.
        ENABLE_HARDENED_RUNTIME: NO
        CODE_SIGN_IDENTITY: "-"
    scheme:
      testTargets: []
```

Create `App/FabledApp.swift`:

```swift
import SwiftUI

@main
struct FabledApp: App {
    init() {
        // Writes to a dead CLI's stdin raise SIGPIPE and the default
        // disposition kills the app. ClaudeKit short-circuits writes after
        // termination; this is the process-level backstop for the race.
        signal(SIGPIPE, SIG_IGN)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
```

Create `App/RootView.swift` (placeholder — Task 9 replaces it):

```swift
import SwiftUI

struct RootView: View {
    var body: some View {
        Text("Fabled")
            .font(.largeTitle)
            .frame(minWidth: 900, minHeight: 560)
    }
}
```

Create `App/Theme.swift`:

```swift
import SwiftUI

enum Theme {
    /// Claude clay (#D97757) — send button and accents.
    static let clay = Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255)

    /// Claude's voice is serif; chrome stays SF Pro.
    static func assistantFont(_ style: Font.TextStyle = .body) -> Font {
        .system(style, design: .serif)
    }
}
```

Append to `.gitignore` (create the file if the repo has none):

```
# XcodeGen output — regenerate with `xcodegen generate`
Fabled.xcodeproj/
DerivedData/
.build/
```

- [ ] **Step 3: Generate and build**

Run:
```bash
xcodegen generate
xcodebuild -project Fabled.xcodeproj -scheme Fabled -configuration Debug build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Boot it once**

Run: `open "$(xcodebuild -project Fabled.xcodeproj -scheme Fabled -configuration Debug -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR/{print $3}')/Fabled.app"`
Expected: a window titled Fabled appears. Quit it.

- [ ] **Step 5: Verify the package suite still passes, then commit**

Run: `swift test 2>&1 | tail -3` — expected green (the app target is invisible to SwiftPM).

```bash
git add project.yml App .gitignore
git commit -m "feat(app): XcodeGen scaffold — Fabled.app boots"
```

---

### Task 9: AppModel + sidebar

`AppModel` (FabledCore, fully tested) owns the stores and session lifecycle; the sidebar renders live sessions with state dots, index-backed history grouped by project, and search.

**Files:**
- Create: `Sources/FabledCore/AppModel.swift`
- Create: `Tests/FabledCoreTests/AppModelTests.swift`
- Modify: `Tests/FabledCoreTests/Support.swift` (corpus builder)
- Create: `App/SidebarView.swift`
- Modify: `App/RootView.swift`
- Modify: `App/FabledApp.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/FabledCoreTests/Support.swift`:

```swift
enum CorpusBuilder {
    /// A temp ~/.claude/projects-shaped tree built from the transcript
    /// fixtures, with staggered mtimes (tooluse newest … titled oldest).
    static func make() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("corpus-\(UUID().uuidString)")
        let project = root.appendingPathComponent("-tmp-fabled-demo")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let fixtures = [
            ("real-titled-session", "97c70bda-ac5d-4e12-982e-8e6e35dd2674", -3.0),
            ("real-untitled-session", "036b246d-0898-4ace-89b2-8fdd6c107fc4", -2.0),
            ("real-tooluse-session", "21feb0f8-e41a-4f72-9efb-9232b5bb64de", -1.0),
        ]
        for (fixture, sessionID, minutesAgo) in fixtures {
            let destination = project.appendingPathComponent("\(sessionID).jsonl")
            try FileManager.default.copyItem(
                at: CoreFixtures.fixturesDir
                    .appendingPathComponent("transcripts/\(fixture).jsonl"),
                to: destination)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSinceNow: minutesAgo * 60)],
                ofItemAtPath: destination.path)
        }
        return root
    }
}
```

Create `Tests/FabledCoreTests/AppModelTests.swift`:

```swift
import XCTest
import ClaudeKit
@testable import FabledCore

@MainActor
final class AppModelTests: XCTestCase {
    private func makeModel(pollInterval: Duration = .seconds(2)) throws -> (AppModel, URL) {
        let root = try CorpusBuilder.make()
        let store = SessionStore(projectsRoot: root, pollInterval: pollInterval)
        let db = FileManager.default.temporaryDirectory
            .appendingPathComponent("index-\(UUID().uuidString).sqlite")
        let model = try AppModel(store: store, databaseURL: db)
        return (model, root)
    }

    func testBootstrapPopulatesGroupedHistory() async throws {
        let (model, _) = try makeModel()
        await model.bootstrap()
        XCTAssertEqual(model.history.count, 1, "one project group")
        let sessions = model.history[0].sessions
        XCTAssertEqual(sessions.count, 3)
        XCTAssertEqual(sessions.map(\.id).first, "21feb0f8-e41a-4f72-9efb-9232b5bb64de",
                       "newest first")
        // Index titles are authoritative: the titled session has a real title,
        // the untitled one falls back to its id.
        let titled = sessions.first { $0.id == "97c70bda-ac5d-4e12-982e-8e6e35dd2674" }!
        XCTAssertNotEqual(titled.title, titled.id)
        let untitled = sessions.first { $0.id == "036b246d-0898-4ace-89b2-8fdd6c107fc4" }!
        XCTAssertEqual(untitled.title, untitled.id)
    }

    func testSearchDebouncedAndScoped() async throws {
        let (model, _) = try makeModel()
        await model.bootstrap()
        model.searchQuery = "pong"
        await waitUntil("search hits") { !model.searchHits.isEmpty }
        XCTAssertTrue(model.searchHits.contains {
            $0.session.id == "036b246d-0898-4ace-89b2-8fdd6c107fc4"
        }, "the pong session must match")
        model.searchQuery = ""
        await waitUntil("hits cleared") { model.searchHits.isEmpty }
    }

    func testWatcherRefreshesHistory() async throws {
        let (model, root) = try makeModel(pollInterval: .milliseconds(50))
        await model.bootstrap()
        XCTAssertEqual(model.history.first?.sessions.count, 3)

        // A new session file appears on disk (as if a CLI ran elsewhere).
        let project = root.appendingPathComponent("-tmp-fabled-demo")
        try FileManager.default.copyItem(
            at: CoreFixtures.fixturesDir
                .appendingPathComponent("transcripts/real-titled-session.jsonl"),
            to: project.appendingPathComponent("aaaaaaaa-0000-0000-0000-000000000001.jsonl"))

        await waitUntil(timeout: .seconds(10), "watcher-driven refresh") {
            model.history.first?.sessions.count == 4
        }
    }

    func testHistoricalTimeline() async throws {
        let (model, _) = try makeModel()
        await model.bootstrap()
        let summary = model.summary(forSessionID: "97c70bda-ac5d-4e12-982e-8e6e35dd2674")!
        let items = await model.historicalTimeline(for: summary)
        XCTAssertEqual(items.count, 2, "1 user prompt + 1 assistant text (Task 6 census)")
    }

    func testProjectDisplayName() {
        XCTAssertEqual(ProjectFolder(
            flattenedName: "-Users-x-Developer-Wine",
            originalPath: "/Users/x/Developer/Wine",
            directoryURL: URL(fileURLWithPath: "/tmp")).displayName, "Wine")
        XCTAssertEqual(ProjectFolder(
            flattenedName: "-gibberish--x",
            originalPath: "-gibberish--x",
            directoryURL: URL(fileURLWithPath: "/tmp")).displayName, "-gibberish--x",
            "unresolvable paths show the flattened name")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter AppModelTests 2>&1 | tail -10`
Expected: compile errors — `AppModel` doesn't exist.

- [ ] **Step 3: Implement AppModel**

Create `Sources/FabledCore/AppModel.swift`:

```swift
import ClaudeKit
import Foundation
import Observation

/// App-level state: the stores, live sessions, sidebar history, search,
/// and session lifecycle. One instance per app.
@MainActor
@Observable
public final class AppModel {
    public let store: SessionStore
    public let index: SearchIndex

    public private(set) var liveSessions: [ChatSession] = []
    public private(set) var history: [ProjectHistory] = []
    public private(set) var searchHits: [SearchHit] = []
    public private(set) var isIndexing = false
    public private(set) var launchError: String?
    public var selection: Selection?
    public var searchQuery = "" {
        didSet { if searchQuery != oldValue { scheduleSearch() } }
    }

    public enum Selection: Hashable {
        case live(UUID)
        case historical(String)   // session id
    }

    public struct ProjectHistory: Identifiable, Sendable {
        public let project: ProjectFolder
        public var sessions: [SessionSummary]
        public var id: String { project.id }
    }

    private var watchTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

    public init(store: SessionStore = SessionStore(), databaseURL: URL? = nil) throws {
        self.store = store
        let dbURL = databaseURL
            ?? FileManager.default.urls(for: .applicationSupportDirectory,
                                        in: .userDomainMask)[0]
                .appendingPathComponent("Fabled/index.sqlite")
        self.index = try SearchIndex(databaseURL: dbURL, store: store)
    }

    deinit {
        watchTask?.cancel()
        searchTask?.cancel()
    }

    // MARK: - Sidebar data

    /// Instant history from the warm index, then a catch-up reindex, then
    /// watcher-driven refreshes for as long as the app lives.
    public func bootstrap() async {
        await refreshHistory()
        watchTask = Task { [weak self] in
            guard let changes = await self?.store.changes else { return }
            for await _ in changes {
                guard let self else { return }
                await self.reindexAndRefresh()
            }
        }
        await reindexAndRefresh()
    }

    private func reindexAndRefresh() async {
        isIndexing = true
        defer { isIndexing = false }
        _ = try? await index.reindex()
        await refreshHistory()
    }

    public func refreshHistory() async {
        guard let summaries = try? await index.sessionSummaries() else { return }
        var groups: [String: ProjectHistory] = [:]
        var order: [String] = []   // projects ordered by their newest session
        for summary in summaries {
            let key = summary.project.id
            if groups[key] == nil {
                groups[key] = ProjectHistory(project: summary.project, sessions: [])
                order.append(key)
            }
            groups[key]?.sessions.append(summary)
        }
        history = order.compactMap { groups[$0] }
    }

    public func summary(forSessionID id: String) -> SessionSummary? {
        for group in history {
            if let summary = group.sessions.first(where: { $0.id == id }) {
                return summary
            }
        }
        return searchHits.first { $0.session.id == id }?.session
    }

    // MARK: - Search

    private func scheduleSearch() {
        searchTask?.cancel()
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            searchHits = []
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))   // keystroke debounce
            guard !Task.isCancelled, let self else { return }
            let hits = (try? await self.index.search(query, limit: 50)) ?? []
            guard !Task.isCancelled else { return }
            self.searchHits = hits
        }
    }

    // MARK: - Session lifecycle

    public func newSession(at directory: URL, model: String? = nil) async {
        var configuration = SessionConfiguration(workingDirectory: directory)
        configuration.model = model
        await launch(configuration, seed: [])
    }

    /// Resume/fork replays nothing on the wire (probe finding 8) — the
    /// timeline is seeded from the on-disk transcript.
    public func resume(_ summary: SessionSummary, fork: Bool) async {
        let seed = await historicalTimeline(for: summary)
        var configuration = SessionConfiguration(
            workingDirectory: workingDirectory(for: summary))
        configuration.resumeSessionID = summary.id
        configuration.forkSession = fork
        await launch(configuration, seed: seed)
    }

    public func close(_ session: ChatSession) {
        session.terminate()
        liveSessions.removeAll { $0.id == session.id }
        if selection == .live(session.id) { selection = nil }
    }

    public func historicalTimeline(for summary: SessionSummary) async -> [TimelineItem] {
        let entries = (try? await store.transcript(for: summary)) ?? []
        return TimelineReducer.items(fromTranscript: entries)
    }

    private func launch(_ configuration: SessionConfiguration, seed: [TimelineItem]) async {
        do {
            let session = try await ChatSession.launch(configuration: configuration)
            session.seed(timeline: seed)
            liveSessions.append(session)
            selection = .live(session.id)
            launchError = nil
        } catch {
            launchError = "Could not start claude: \(error)"
        }
    }

    private func workingDirectory(for summary: SessionSummary) -> URL {
        let path = summary.project.originalPath
        // Unresolvable flattened names (deleted directories) fall back to home.
        guard path.hasPrefix("/") else {
            return FileManager.default.homeDirectoryForCurrentUser
        }
        return URL(fileURLWithPath: path)
    }
}

public extension ProjectFolder {
    /// Sidebar section label: the directory's leaf name when the path
    /// resolved, otherwise the raw flattened name.
    var displayName: String {
        originalPath.hasPrefix("/")
            ? URL(fileURLWithPath: originalPath).lastPathComponent
            : flattenedName
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test 2>&1 | tail -5`
Expected: all pass. The watcher test needs up to ~1 s (50 ms poll + 250 ms throttle); if it flakes, raise its timeout, never the poll rate.

- [ ] **Step 5: Build the sidebar UI**

Create `App/SidebarView.swift`:

```swift
import SwiftUI
import ClaudeKit
import FabledCore

struct SidebarView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        List(selection: $app.selection) {
            if !app.searchQuery.isEmpty {
                searchResults
            } else {
                liveSection
                historySections
            }
        }
        .searchable(text: $app.searchQuery, placement: .sidebar, prompt: "Search sessions")
        .overlay(alignment: .bottom) {
            if app.isIndexing {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Indexing…").font(.caption).foregroundStyle(.secondary)
                }
                .padding(6)
            }
        }
    }

    @ViewBuilder private var liveSection: some View {
        if !app.liveSessions.isEmpty {
            Section("Live") {
                ForEach(app.liveSessions) { session in
                    HStack(spacing: 8) {
                        Circle().fill(dotColor(session.activityState))
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading) {
                            Text(session.title).lineLimit(1)
                            Text(session.workingDirectory.lastPathComponent)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .tag(AppModel.Selection.live(session.id))
                    .contextMenu {
                        Button("End Session", role: .destructive) {
                            app.close(session)
                        }
                    }
                }
            }
        }
    }

    private var historySections: some View {
        ForEach(app.history) { group in
            Section(group.project.displayName) {
                // v1 keeps sections shallow; search covers the deep tail.
                ForEach(group.sessions.prefix(10)) { summary in
                    VStack(alignment: .leading) {
                        Text(summary.title).lineLimit(1)
                        Text(summary.lastActivity, format: .relative(presentation: .named))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(AppModel.Selection.historical(summary.id))
                }
                if group.sessions.count > 10 {
                    Text("\(group.sessions.count - 10) more — use search")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var searchResults: some View {
        Section("Results") {
            ForEach(app.searchHits) { hit in
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.session.title).lineLimit(1)
                    Text(hit.snippet).font(.caption)
                        .foregroundStyle(.secondary).lineLimit(2)
                }
                .tag(AppModel.Selection.historical(hit.session.id))
            }
        }
    }

    private func dotColor(_ state: ChatSession.ActivityState) -> Color {
        switch state {
        case .working: Theme.clay
        case .needsApproval: .red
        case .idle: .green
        case .ended: .gray
        }
    }
}
```

Replace `App/RootView.swift`:

```swift
import SwiftUI
import FabledCore

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 280)
        } detail: {
            detail
        }
        .frame(minWidth: 900, minHeight: 560)
        .task { await app.bootstrap() }
    }

    @ViewBuilder private var detail: some View {
        switch app.selection {
        case .live(let id):
            if let session = app.liveSessions.first(where: { $0.id == id }) {
                Text(session.title)   // Task 10 replaces with ConversationView
            } else {
                Text("Session ended")
            }
        case .historical(let id):
            if let summary = app.summary(forSessionID: id) {
                Text(summary.title)   // Task 10 replaces with HistoricalSessionView
            } else {
                Text("Not found")
            }
        case nil:
            Text("Select a session").foregroundStyle(.secondary)
        }
    }
}
```

Update `App/FabledApp.swift` to own the model:

```swift
import SwiftUI
import FabledCore

@main
struct FabledApp: App {
    @State private var model: AppModel

    init() {
        signal(SIGPIPE, SIG_IGN)   // see Task 8 comment
        do {
            _model = State(initialValue: try AppModel())
        } catch {
            // A failed SQLite open in Application Support means a broken
            // install; there is no UI to recover into yet.
            fatalError("Failed to open the search index: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}
```

- [ ] **Step 6: Build and smoke-test against the real corpus**

Run: `xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled -configuration Debug build 2>&1 | tail -3` — expected `** BUILD SUCCEEDED **`.

Launch the app (same `open` command as Task 8). Verify by hand:
1. Sidebar shows project sections with real session titles (warm index → instant; first-ever run shows "Indexing…" for ~8 s first).
2. Typing in the search field returns snippets; clearing restores history.
3. Selecting a row shows its title in the detail pane.

- [ ] **Step 7: Commit**

```bash
git add Sources/FabledCore/AppModel.swift Tests/FabledCoreTests App/SidebarView.swift App/RootView.swift App/FabledApp.swift
git commit -m "feat(app): AppModel + sidebar — live sessions, index-backed history, search"
```

---

### Task 10: Conversation view — streaming timeline + read-only history

The conversation pane: serif assistant prose, collapsed tool cards, auto-scroll, historical transcripts through the same renderer, and a minimal inline composer (Task 11 replaces it) so live sessions can be smoke-tested end to end.

**Files:**
- Create: `App/ConversationView.swift`
- Create: `App/TimelineItemViews.swift`
- Create: `App/HistoricalSessionView.swift`
- Create: `App/WelcomeView.swift`
- Modify: `App/RootView.swift`

- [ ] **Step 1: Implement the timeline renderers**

Create `App/TimelineItemViews.swift`:

```swift
import SwiftUI
import ClaudeKit
import FabledCore

/// One timeline row. `session` is nil in read-only history.
struct TimelineItemView: View {
    let item: TimelineItem
    let session: ChatSession?

    var body: some View {
        switch item {
        case .userMessage(_, let text):
            UserBubble(text: text)
        case .assistantText(_, let markdown, let isStreaming):
            AssistantTextView(markdown: markdown, isStreaming: isStreaming)
        case .toolCall(_, let name, let summary, let input, let result, let isError, let isRunning):
            ToolCallCard(name: name, summary: summary, input: input,
                         result: result, isError: isError, isRunning: isRunning)
        case .permission(_, let request, let resolution):
            // Static rendering; Task 11 swaps in the interactive card.
            PermissionStatusView(request: request, resolution: resolution)
        case .turnSummary(_, let result):
            TurnSummaryView(result: result)
        case .notice(_, let text):
            NoticeView(text: text)
        case .raw(_, let type, let raw):
            RawEventView(type: type, raw: raw)
        }
    }
}

struct UserBubble: View {
    let text: String
    var body: some View {
        HStack {
            Spacer(minLength: 48)
            Text(text)
                .textSelection(.enabled)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.quaternary.opacity(0.6),
                            in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct AssistantTextView: View {
    let markdown: String
    let isStreaming: Bool

    var body: some View {
        Text(attributed)
            .font(Theme.assistantFont())
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(isStreaming ? 0.85 : 1)
    }

    private var attributed: AttributedString {
        // Ledgered decision: AttributedString first, no markdown package.
        (try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(markdown)
    }
}

struct ToolCallCard: View {
    let name: String
    let summary: String
    let input: JSONValue
    let result: JSONValue?
    let isError: Bool?
    let isRunning: Bool
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                if input != .object([:]), input != .null {
                    Text(String(JSONPretty.string(input).prefix(4000)))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                if let result {
                    Divider()
                    Text(String(JSONPretty.string(result).prefix(4000)))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(isError == true ? Color.red : Color.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(.top, 4)
        } label: {
            HStack(spacing: 6) {
                statusIcon
                Text(name).fontWeight(.medium)
                Text(summary).foregroundStyle(.secondary).lineLimit(1)
            }
            .font(.callout)
        }
        .padding(8)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private var statusIcon: some View {
        if isRunning {
            ProgressView().controlSize(.small)
        } else if isError == true {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        } else {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        }
    }
}

struct PermissionStatusView: View {
    let request: PermissionRequest
    let resolution: PermissionDecision?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield")
            Text(PermissionPrompt.commandSummary(for: request))
                .font(.system(.callout, design: .monospaced)).lineLimit(1)
            Spacer()
            switch resolution {
            case .allow: Text("Allowed").foregroundStyle(.green)
            case .deny: Text("Denied").foregroundStyle(.red)
            case nil: Text("Awaiting approval").foregroundStyle(.orange)
            }
        }
        .font(.callout)
        .padding(8)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct TurnSummaryView: View {
    let result: TurnResult
    var body: some View {
        HStack(spacing: 8) {
            if result.isError {
                Text(result.subtype.replacingOccurrences(of: "_", with: " "))
                    .foregroundStyle(.orange)
            }
            if let cost = result.totalCostUSD {
                Text(String(format: "$%.4f", cost))
            }
            if let ms = result.durationMS {
                Text(String(format: "%.1fs", ms / 1000))
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct NoticeView: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 4)
    }
}

struct RawEventView: View {
    let type: String
    let raw: JSONValue
    @State private var isExpanded = false
    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(String(JSONPretty.string(raw).prefix(4000)))
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
        } label: {
            Label(type, systemImage: "questionmark.square.dashed")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(6)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
    }
}
```

- [ ] **Step 2: Implement the conversation, history, and welcome panes**

Create `App/ConversationView.swift`:

```swift
import SwiftUI
import FabledCore

struct ConversationView: View {
    let session: ChatSession
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            if let note = session.versionNote {
                Text(note)
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(4)
                    .background(.yellow.opacity(0.15))
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(session.timeline) { item in
                        TimelineItemView(item: item, session: session)
                    }
                    if session.isThinking {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Thinking…")
                                .font(Theme.assistantFont(.callout)).italic()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
            }
            .defaultScrollAnchor(.bottom)
            Divider()
            // Minimal inline composer — Task 11 replaces this block with
            // ComposerView (multiline, shortcuts, stop button).
            HStack {
                TextField("Message Claude…", text: $draft)
                    .textFieldStyle(.plain)
                    .onSubmit(sendDraft)
                Button(action: sendDraft) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2).foregroundStyle(Theme.clay)
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(10)
        }
        .navigationTitle(session.title)
        .navigationSubtitle(session.workingDirectory.path)
    }

    private func sendDraft() {
        session.send(draft)
        draft = ""
    }
}
```

Create `App/HistoricalSessionView.swift`:

```swift
import SwiftUI
import ClaudeKit
import FabledCore

struct HistoricalSessionView: View {
    @Environment(AppModel.self) private var app
    let summary: SessionSummary
    @State private var items: [TimelineItem]?

    var body: some View {
        Group {
            if let items {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(items) { item in
                            TimelineItemView(item: item, session: nil)
                        }
                    }
                    .padding()
                }
                .defaultScrollAnchor(.bottom)
            } else {
                ProgressView("Loading transcript…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(summary.title)
        .navigationSubtitle(summary.project.displayName)
        .toolbar {
            ToolbarItemGroup {
                Button("Resume") { Task { await app.resume(summary, fork: false) } }
                Button("Fork") { Task { await app.resume(summary, fork: true) } }
            }
        }
        .task(id: summary.id) {
            items = nil
            items = await app.historicalTimeline(for: summary)
        }
    }
}
```

Create `App/WelcomeView.swift`:

```swift
import SwiftUI

struct WelcomeView: View {
    let newSession: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Fabled")
                .font(.system(.largeTitle, design: .serif))
            Text("Native Claude Code for the Mac")
                .foregroundStyle(.secondary)
            Button("New Session…", action: newSession)
                .buttonStyle(.borderedProminent)
                .tint(Theme.clay)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

In `App/RootView.swift`, replace the `detail` builder with the real panes (Task 12 replaces the temporary scratch-folder action with a folder picker):

```swift
    @ViewBuilder private var detail: some View {
        switch app.selection {
        case .live(let id):
            if let session = app.liveSessions.first(where: { $0.id == id }) {
                ConversationView(session: session)
            } else {
                WelcomeView(newSession: startScratchSession)
            }
        case .historical(let id):
            if let summary = app.summary(forSessionID: id) {
                HistoricalSessionView(summary: summary)
            } else {
                Text("Not found")
            }
        case nil:
            WelcomeView(newSession: startScratchSession)
        }
    }

    /// TEMPORARY (Task 12 replaces with a folder picker): scratch dir session.
    private func startScratchSession() {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("fabled-scratch")
        try? FileManager.default.createDirectory(
            at: scratch, withIntermediateDirectories: true)
        Task { await app.newSession(at: scratch) }
    }
```

Also surface launch failures — add to `RootView.body`, after `.task { … }`:

```swift
        .alert("Session failed", isPresented: .constant(app.launchError != nil)) {
            Button("OK") { }
        } message: {
            Text(app.launchError ?? "")
        }
```

(If the `.constant` binding produces a repeat-alert annoyance during smoke testing, bind it properly with a small `@State` mirror — cosmetic only, don't spend time here; Task 12 doesn't touch it.)

- [ ] **Step 3: Build and smoke-test a live conversation**

Run: `xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled -configuration Debug build 2>&1 | tail -3` — expected `** BUILD SUCCEEDED **`. Then `swift test 2>&1 | tail -3` — still green.

Launch the app and verify by hand:
1. Click "New Session…" → a Live row appears with a clay dot; the init happens silently.
2. Send "Say hello and then run `ls`." → text streams in serif as it generates; an `ls` tool card may appear (sandboxed, no permission needed) and fills with its result; a turn summary line shows cost.
3. Open a historical session with tool use → collapsed tool cards render; expanding shows input/result; the view opens scrolled to the bottom.
4. Send a second message while the first is still streaming → it queues and runs after (probe finding 6).

- [ ] **Step 4: Commit**

```bash
git add App
git commit -m "feat(app): conversation view — streaming timeline, tool cards, read-only history"
```

---

### Task 11: Composer + interactive permission cards

The full composer (multiline, Return sends, ⌘. interrupts) and the interactive permission card (Allow ⌘⏎ / Always-allow with the CLI's suggested rule / Deny with optional message), plus the dock badge for pending approvals.

**Files:**
- Create: `App/ComposerView.swift`
- Create: `App/PermissionCardView.swift`
- Modify: `App/ConversationView.swift` (swap the minimal composer out)
- Modify: `App/RootView.swift` (dock badge)

- [ ] **Step 1: Implement the permission card**

Create `App/PermissionCardView.swift`:

```swift
import SwiftUI
import ClaudeKit
import FabledCore

/// Inline approval card (spec: never app-modal — other sessions stay usable).
struct PermissionCardView: View {
    let request: PermissionRequest
    let respond: (PermissionDecision) -> Void
    @State private var denyMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill").foregroundStyle(Theme.clay)
                Text(request.displayName ?? request.toolName).fontWeight(.semibold)
                Spacer()
            }
            Text(PermissionPrompt.commandSummary(for: request))
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5),
                            in: RoundedRectangle(cornerRadius: 6))
            if let reason = request.decisionReason {
                Text(reason).font(.caption).foregroundStyle(.secondary)
            }
            TextField("Reason (optional, sent with Deny)", text: $denyMessage)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
            HStack {
                Button("Allow") { respond(.allowAsRequested) }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.clay)
                    .keyboardShortcut(.return, modifiers: .command)
                if let label = PermissionPrompt.alwaysAllowLabel(for: request.suggestions) {
                    // Persists via the CLI: suggestions echoed back verbatim
                    // land in the suggestion's destination settings file.
                    Button(label) {
                        respond(.allow(updatedInput: nil,
                                       updatedPermissions: request.suggestions))
                    }
                }
                Spacer()
                Button("Deny") {
                    respond(.deny(message: denyMessage.isEmpty ? nil : denyMessage))
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(12)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Theme.clay.opacity(0.5)))
    }
}
```

- [ ] **Step 2: Implement the composer**

Create `App/ComposerView.swift`:

```swift
import SwiftUI
import FabledCore

struct ComposerView: View {
    let session: ChatSession
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            if let permission = session.pendingPermission {
                PermissionCardView(request: permission) { decision in
                    session.respond(to: permission, decision: decision)
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message Claude…", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...8)
                    .focused($isFocused)
                    .onSubmit(send)   // Return sends; ⌥Return inserts a newline
                if session.isWorking {
                    Button(action: session.interrupt) {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Interrupt (⌘.)")
                    .keyboardShortcut(".", modifiers: .command)
                }
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(canSend ? Theme.clay : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                // ⌘⏎ belongs to the permission card while one is pending.
                .keyboardShortcut(session.pendingPermission == nil
                    ? KeyboardShortcut(.return, modifiers: .command) : nil)
            }
        }
        .padding(10)
        .onAppear { isFocused = true }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !session.hasEnded
    }

    private func send() {
        guard canSend else { return }
        session.send(draft)
        draft = ""
    }
}
```

In `App/ConversationView.swift`, delete the `@State private var draft`, the `sendDraft()` function, and the whole "Minimal inline composer" `HStack` block; replace the block with:

```swift
            ComposerView(session: session)
```

- [ ] **Step 3: Dock badge for pending approvals**

In `App/RootView.swift`, add `import AppKit` at the top, this computed property:

```swift
    private var pendingApprovals: Int {
        app.liveSessions.reduce(0) { $0 + $1.pendingPermissions.count }
    }
```

and this modifier on the `NavigationSplitView` chain:

```swift
        .onChange(of: pendingApprovals) { _, count in
            NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
        }
```

- [ ] **Step 4: Build and smoke-test the permission flow**

Run: `xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled -configuration Debug build 2>&1 | tail -3` — expected `** BUILD SUCCEEDED **`. `swift test 2>&1 | tail -3` — green.

Launch and verify by hand (each in a fresh scratch session):
1. Send "Run exactly this bash command: git init" → clay-bordered card appears with the monospaced command, the sidebar dot turns red, the dock icon badges "1".
2. ⌘⏎ approves → tool card runs and completes; badge clears.
3. Repeat; click "Always allow: Bash(git init *)" → tool runs, and `<scratch>/.claude/settings.local.json` now contains the rule (check in Terminal).
4. Repeat with a deny message "use /tmp instead" → Claude reacts to the message in its next text.
5. Multiline: type text with ⌥Return newlines, Return sends. While a long turn streams, ⌘. interrupts — a notice-free stop (turn summary shows `error during execution`, session stays usable — probe finding 7).

- [ ] **Step 5: Commit**

```bash
git add App
git commit -m "feat(app): composer + interactive permission cards + dock badge"
```

---

### Task 12: Toolbar (model picker, permission mode) + session lifecycle

The catalog-driven model picker with a custom-ID escape hatch, the permission-mode picker, ⌘N new-session with a real folder picker, and Resume/Fork already wired from Task 10 get their seeded-timeline behavior verified.

**Files:**
- Create: `App/ModelPickerMenu.swift`
- Modify: `App/ConversationView.swift` (toolbar)
- Modify: `App/RootView.swift` (folder picker)
- Modify: `App/WelcomeView.swift` (picker instead of scratch)
- Modify: `App/FabledApp.swift` (⌘N command)
- Modify: `Sources/FabledCore/AppModel.swift` (`isPickingFolder`)

- [ ] **Step 1: Implement the model picker**

Create `App/ModelPickerMenu.swift`:

```swift
import SwiftUI
import FabledCore

/// Catalog-driven (initialize response, probe finding 9) + free-text custom
/// IDs — `--model` accepts full model IDs, so the picker must too.
struct ModelPickerMenu: View {
    let session: ChatSession
    @State private var isCustomSheetPresented = false
    @State private var customModel = ""

    var body: some View {
        Menu {
            ForEach(session.models) { option in
                Button {
                    session.setModel(option.value)
                } label: {
                    if option.value == session.currentModel {
                        Label(option.displayName, systemImage: "checkmark")
                    } else {
                        Text(option.displayName)
                    }
                }
                .help(option.optionDescription ?? "")
            }
            Divider()
            Button("Custom Model…") { isCustomSheetPresented = true }
        } label: {
            Label(currentDisplayName, systemImage: "cpu")
        }
        .sheet(isPresented: $isCustomSheetPresented) {
            VStack(spacing: 12) {
                Text("Custom model ID").font(.headline)
                TextField("e.g. claude-sonnet-5", text: $customModel)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
                    .onSubmit(applyCustomModel)
                HStack {
                    Button("Cancel") { isCustomSheetPresented = false }
                        .keyboardShortcut(.cancelAction)
                    Button("Switch", action: applyCustomModel)
                        .buttonStyle(.borderedProminent).tint(Theme.clay)
                        .disabled(customModel.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(20)
        }
    }

    private var currentDisplayName: String {
        session.models.first { $0.value == session.currentModel }?.displayName
            ?? session.currentModel
            ?? "Model"
    }

    private func applyCustomModel() {
        let value = customModel.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        session.setModel(value)
        isCustomSheetPresented = false
    }
}
```

- [ ] **Step 2: Toolbar on the conversation**

In `App/ConversationView.swift`, add below `.navigationSubtitle(…)`:

```swift
        .toolbar {
            ToolbarItemGroup {
                ModelPickerMenu(session: session)
                Picker("Permissions", selection: Binding(
                    get: { session.permissionMode },
                    set: { session.setPermissionMode($0) }
                )) {
                    Text("Default").tag("default")
                    Text("Plan").tag("plan")
                    Text("Accept Edits").tag("acceptEdits")
                    Text("Bypass Permissions").tag("bypassPermissions")
                }
                .pickerStyle(.menu)
                if session.cumulativeCostUSD > 0 {
                    Text(String(format: "$%.2f", session.cumulativeCostUSD))
                        .font(.caption).foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
```

- [ ] **Step 3: Folder-picker new-session flow**

In `Sources/FabledCore/AppModel.swift`, add with the other observable state:

```swift
    /// The New Session folder picker (menu ⌘N, welcome button) presents
    /// when this flips true; RootView owns the fileImporter.
    public var isPickingFolder = false
```

In `App/RootView.swift`:
1. Delete `startScratchSession()` and pass the picker trigger instead — both `WelcomeView(newSession:)` call sites become:

```swift
                WelcomeView { app.isPickingFolder = true }
```

2. Add to the modifier chain (the view already has `@Bindable var app = app` — add it at the top of `body` if not):

```swift
        .fileImporter(isPresented: $app.isPickingFolder,
                      allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                Task { await app.newSession(at: url) }
            }
        }
```

In `App/FabledApp.swift`, add a menu command to the `WindowGroup`:

```swift
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Session…") { model.isPickingFolder = true }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
```

- [ ] **Step 4: Run the package tests, build, and smoke-test**

Run: `swift test 2>&1 | tail -3` then `xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled -configuration Debug build 2>&1 | tail -3` — both green.

Launch and verify by hand:
1. ⌘N → folder picker → choose a real project → session starts there (check the navigation subtitle path).
2. The model menu lists the CLI's catalog with the current model checked. Switch to another model mid-conversation, send "which model are you?" — the reply reflects the switch (and no error arrives). A message *queued before* the switch keeps the old model (probe finding 5) — not a bug.
3. Custom Model… → type `claude-haiku-4-5-20251001` → Switch → next reply is haiku-fast.
4. Permission mode → Plan; ask for a file edit → Claude plans instead of editing.
5. Open an old session from the sidebar → Resume → the full history renders instantly (seeded from disk), then send "what were we doing?" → the reply shows server-side context survived (probe finding 8).
6. Fork the same session → a *new* live session appears; the original file is untouched after chatting in the fork.

- [ ] **Step 5: Commit**

```bash
git add App Sources/FabledCore/AppModel.swift
git commit -m "feat(app): model picker, permission modes, folder-picker session lifecycle"
```

---

### Task 13: Polish gate + documentation

The brief's exit criterion, run as a scripted manual gate, then the paperwork: decisions ledgered, follow-ups reconciled, README updated, plan marked complete.

**Files:**
- Modify: `docs/superpowers/DECISIONS.md`
- Modify: `docs/superpowers/FOLLOWUPS.md`
- Modify: `README.md`
- Modify: `docs/superpowers/plans/2026-07-09-plan-3-app-shell.md` (status header)

- [ ] **Step 1: Full verification pass**

```bash
swift test 2>&1 | tail -3
CLAUDEKIT_LIVE=1 swift test --filter LiveSessionTests 2>&1 | tail -5
CLAUDEKIT_PERF=1 swift test --filter PerformanceGateTests 2>&1 | tail -5
xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled -configuration Debug build 2>&1 | tail -3
```
Expected: everything green. Paste real output in the task report.

- [ ] **Step 2: The polish gate (manual, launch the app once)**

All in one app run, no terminal (except the final settings check):
1. Launch → sidebar populated instantly from the warm index.
2. Search for a phrase from months ago → hit → open read-only.
3. Resume yesterday's (any recent) session → history renders, send a message, get a streamed serif reply.
4. Trigger a permission (ask for `git init` in a scratch folder session) → approve via ⌘⏎.
5. Switch model mid-session, send again — works.
6. Interrupt a long turn with ⌘. — session survives, next message works.
7. Quit the app with a live session open → no zombie `claude` processes: `pgrep -fl "claude.*stream-json"` in Terminal is empty within a few seconds. (In-app closes go through `terminate()`/deinit — Task 1; on app exit the children see stdin EOF and exit themselves, same as the probe scripts closing stdin.)

If any step fails: STOP, fix forward (new task with the coordinator), re-run the gate. Do not check the box on a partial pass.

- [ ] **Step 3: Ledger the decisions**

Append to `docs/superpowers/DECISIONS.md`:

```markdown
- **2026-07-09 · `updatedInput` is mandatory in allow responses.** Probed live: the CLI Zod-validates the allow payload and omitting `updatedInput` denies the tool (fixtures/2026-07-09-perm-allow-noinput.jsonl). `PermissionDecision.allow` reshaped to `(updatedInput:, updatedPermissions:)`; encoding echoes the request's input when nil. *Revisit if:* the CLI relaxes the schema (fixture re-record will show it).
- **2026-07-09 · Model picker is catalog-driven.** The initialize control_response carries a full `models` array (value, resolvedModel, displayName, effort caps); the picker renders it + a free-text custom ID. Replaces the brief's static alias list. *Revisit if:* the catalog disappears from the handshake.
- **2026-07-09 · Sidebar history is index-backed; the index title is authoritative.** `SearchIndex.sessionSummaries()` serves the whole list from the files table (instant vs 3.7 s derivation walk) and resolves the Plan-2 title-divergence follow-up in the index's favor. `SessionStore.sessions(in:)` remains for store-only consumers. *Revisit if:* index staleness becomes visible in the sidebar.
- **2026-07-09 · View models live in FabledCore (SPM), views in the app target.** ChatSession/AppModel/reducer are `swift test`-covered; the xcodeproj holds only SwiftUI bodies. Transport injected via `AgentConnection` closures. *Revisit if:* the split forces awkward API surface.
- **2026-07-09 · Resumed sessions seed their timeline from disk.** Probed live: `--resume` replays nothing on the stream-json wire (context survives server-side). Resume/Fork load the transcript through the reducer, then attach the live stream. *Revisit if:* a CLI update starts replaying (isReplay-flagged events would double-render — the seed guard would need dedupe).
```

- [ ] **Step 4: Reconcile FOLLOWUPS.md**

In `docs/superpowers/FOLLOWUPS.md`, move these items to a new "Resolved in Plan 3 (2026-07-09)" section (keep one line each, note the fixing task): control-op correlation (T1), `.allow(updatedInput: nil)` probe (T2 — was *broken*, now impossible to misuse), `toolResult([])` no-op consumers (T5 reducer), `AgentEvent` Equatable (T1), orphaned child on dealloc I2 (T1), SIGPIPE I3 (T1 + T8), reindex reentrancy (T4), vanished-file abort (T4), title-source divergence (T4/T9).

Add new deferred items observed during Plan 3 (whatever came up in reviews), plus these known ones:
- `events`-before-`start()` still returns a dead placeholder stream (M3) — ChatSession always starts first, but the ClaudeKit API sharp edge remains. → Plan 4.
- Unbounded AsyncStream buffers (Plan 1 M1 / Plan 2 changes-stream) — consumers drain promptly on MainActor; revisit only if profiling shows growth. → backlog.
- Heavy `transcript(for:)` reads still run on the SessionStore executor (~0.65 s for the 52 MB pathological file) — fine for open-on-click; revisit with nonisolated reads if the sidebar ever stutters. → Plan 4 if felt.
- `.alert` binding on `launchError` re-presents on repeated failures (Task 10 note) — cosmetic. → Plan 4 polish.

- [ ] **Step 5: Update README.md**

Add (or replace) a "Building" section:

```markdown
## Building

- Engine + view models (tests): `swift test`
- The app: `brew install xcodegen` once, then
  `xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled build`
  (`Fabled.xcodeproj` is generated output — edit `project.yml`, never the project.)
- Live protocol tests (spends ~cents on haiku): `CLAUDEKIT_LIVE=1 swift test`
- Perf gates against the real local corpus: `CLAUDEKIT_PERF=1 swift test`
```

- [ ] **Step 6: Mark the plan complete and commit**

Edit this plan's header: add `> **STATUS: COMPLETE — <date>.** …` line in the style of Plan 2, summarizing test counts and any gate amendments.

```bash
git add docs/superpowers README.md
git commit -m "docs: Plan 3 complete — decisions ledgered, follow-ups reconciled"
```

---

## Deliberately out of scope (Plan 4)

Held back consciously; do not let them creep in: subagent activity grouping (`parent_tool_use_id` disclosure UI), TodoWrite pinned checklist, Edit/Write diff rendering with ± counts, slash-command autocomplete in the composer (the catalog is already harvested — UI only), AskUserQuestion native picker, plan-mode review sheet, SwiftTerm escape hatch, notifications (dock badge ships now; UNUserNotificationCenter is Plan 4), rate-limit status bar, session archive/delete, multi-window/tabs, chat & cowork presets, SIGKILL escalation on stuck children (M2).

## Self-review checklist (for the plan author, done 2026-07-09)

- Every brief task (1–12) maps to a plan task; the brief's "verify by probing" items are all answered in "Probe findings" with committed fixtures.
- All five 2026-07-09 fixtures are referenced by tests that pin their exact shapes.
- Type spellings cross-checked across tasks: `PermissionDecision.allow(updatedInput:updatedPermissions:)` (T2) matches every later use (T6 resolvePermission tests, T11 card); `AgentSession.initializeRequestID` (T1) matches ChatSession's correlation (T7); `SearchIndex.sessionSummaries()` (T4) matches AppModel (T9); `StreamEvent.Kind` cases (T3) match the reducer (T5).

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-09-plan-3-app-shell.md`. Two execution options:

**1. Subagent-Driven (recommended)** — dispatch a fresh subagent per task with the full task text + the "Conventions for implementing agents" section, review between tasks (superpowers:subagent-driven-development). This is how Plans 1–2 ran.

**2. Inline Execution** — execute tasks in this session with checkpoints (superpowers:executing-plans).

Note for the executor: Tasks 8–12 build a GUI app; their smoke steps need a human at the machine (or at least a screen). Plan the review loop so Ben can eyeball the app at Tasks 10, 11, and 12.





