# Shell & Signals Implementation Plan (Fabled Plan 4b)

> **STATUS: EXECUTED — 2026-07-11. Manual gate (Step 7 of Task 15) pending.** All 15 tasks landed on `plan-4b-shell-and-signals` via per-task implementer + independent spec and quality reviews; the suite grew 220 → 289 tests (6 skipped), 0 failures with the SwiftPM suite and the Xcode app build both green at every task boundary. Executed amendments beyond the original text (fix-loop catches): cost accounting reads the wire's session-cumulative `total_cost_usd` (assign, not sum — the `+=` had double-counted since Plan 3); thinking rows carry stable `thinkIndex` fallback ids so live coalescing and replay don't collide; T6 added a liveness baseline reset on `send()` plus an unmatched-error-ack buffer that makes ack/registration ordering irrelevant; T8's organizer tests are timezone-safe and grouping keys on project id; T12 closed the double-Continue TOCTOU with an in-flight `resumingSessionIDs` guard; T15 resets historical `inspectedID` on summary switch. The consolidated live smokes (T3/T9/T10/T11) fold into Ben's manual gate (Step 7), which re-covers every surface. Deferred items are ledgered in FOLLOWUPS.md ("From Plan 4b reviews" section); headline riders this plan CLOSED: ConversationView cross-session identity (T15), optimistic control-op ack correlation (T6), the effort + thinking first-turn-latency levers (T2/T3), and the TodoWrite→task-tools re-plumb (T4).

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fabled gets fast and legible: sessions spawn with a chosen effort level and show the thinking stream instead of a dead spinner, the welcome screen becomes an attention inbox, sidebar status states are unmistakable, notifications reach Ben when he's elsewhere, resume/fork semantics are explicit, transcripts collapse tool runs into readable step groups, and the app starts looking like Fabled (design tokens + the bronze harp icon) instead of a default SwiftUI shell.

**Architecture:** Logic lands in `FabledCore`/`ClaudeKit` where `swift test` reaches it: two small wire additions (`--effort` spawn flag, `tool_use_result` + control-op error decoding), effort state + slash-command sends on `ChatSession`, a `.thinking` timeline case with live coalescing and replay, a `TaskChecklist` fold replacing the dormant TodoWrite feed, a pure `SidebarOrganizer` and `TimelineDisplay` grouping pass, `SessionStore` reads of on-disk subagent transcripts, and injected-closure notification policy on `AppModel`. The app target gets a design-token expansion of `Theme`, the app icon, a rebuilt welcome inbox + welcome composer, sidebar filter/sort/pin UI, an effort picker, thinking/liveness rows, and notification wiring via `UNUserNotificationCenter`.

**Tech Stack:** Swift 6, SwiftUI, Observation, UserNotifications, SwiftPM + XcodeGen, XCTest. macOS 15+. Zero third-party dependencies (unchanged).

**Roadmap context:** Second of three Plan 4 sub-plans (ledgered 2026-07-09; scope deltas ledgered 2026-07-11): 4a interactive surfaces — EXECUTED, merged 4d76919. **4b = this plan** (brief features 13, 14, 15, 16, 18, 7, liveness from 11 + ledgered adds: effort control, thinking rendering, step grouping, task-tools checklist, design phase). 4c = lifecycle, terminal & app identity (Cowork preset DROPPED, Chat preset deferred — DECISIONS 2026-07-11). Brief: `2026-07-08-plan-4-full-surfaces-brief.md`. CD-UI digest: `2026-07-10-cd-ui-digest.md`. Spec: `../specs/2026-07-08-fabled-native-client-design.md`. Read `../COORDINATION.md` first if you are picking this up cold.

---

## Probe findings (2026-07-11, CLI 2.1.206)

All shapes verified live during plan-writing; fixtures are ground truth. **Trust these over intuition.**

| Fixture | What it captures |
|---|---|
| `2026-07-11-slashfx.jsonl` | `--effort low` spawn; `/effort medium` mid-session; `/remote-control` refusal; unknown-command refusal; thinking deltas + `system/thinking_tokens`; session healthy after slash commands |
| `2026-07-11-tasktools.jsonl` | TaskCreate ×3 / TaskUpdate ×3 (incl. delete) / TaskList round-trip with `tool_use_result` |
| `2026-07-11-remotecontrol.jsonl` | `/remote-control` refusal WITH user settings loaded |
| `2026-07-11-remotecontrol-flag.jsonl` | `--remote-control` spawn flag silently inert in `-p` mode |
| `2026-07-09-control-ops.jsonl` (4a-era) | thinking `content_block_start`/`thinking_delta`/`signature_delta` shapes; initialize catalog with effort metadata |
| `2026-07-09-badmodel-ack.jsonl` (4a-era) | `set_model` **error** ack `{subtype:"error", request_id, error: String}`; bogus `set_permission_mode` success-acks |

1. **`--effort <low|medium|high|xhigh|max>` is accepted at spawn** alongside the full stream-json flag set (the slashfx session spawned with `--effort low` and behaved normally). This is the flag Claude Desktop passes on every spawn; measured effect on this repo: first visible text 24s → 17s with `medium` (FOLLOWUPS 2026-07-10).
2. **`/effort <level>` works mid-session as plain user text.** The CLI intercepts it and emits: `system/init` (fresh full init event), a **synthetic assistant message** (`message.model == "<synthetic>"`, one text block: `"Set effort level to medium (this session only): Balanced approach with standard implementation and testing"`), and a `result` with `subtype:"success"`, **`num_turns: 0`**, `duration_ms` ≈ 1, and the same text in `result`. **Zero API cost.** The catalog's `/effort` entry has `argumentHint: "<low|medium|high|xhigh|max|auto>"` — `auto` is valid mid-session.
3. **All slash commands round-trip this way** (init event → synthetic assistant → `num_turns: 0` result). Unknown commands produce `"Unknown command: /no-such-command-xyz"` with `is_error: false`. The session takes normal turns afterwards. The synthetic assistant message renders through the existing assistant-text path with no code changes.
4. **`/remote-control` is NOT available over stream-json on 2.1.206** — `"/remote-control isn't available in this environment."` with and without user settings; the command is absent from the initialize catalog in `-p` mode; the `--remote-control` spawn flag is silently inert (no registration events, catalog unchanged, `remote_control_auto_enable: false`). Remote Control is TUI/Desktop-gated. **Ben's "/remote-control from Fabled" requirement is blocked upstream** — ledgered as a watch item; re-probe on CLI updates (`fixtures/probe_slashfx.py` re-runs in minutes).
5. **The initialize model catalog carries effort metadata per model:** `supportsEffort: Bool`, `supportedEffortLevels: ["low","medium","high","xhigh","max"]`, plus `supportsAdaptiveThinking`/`supportsFastMode`/`supportsAutoMode` (unused here). The effort picker is catalog-driven, exactly like the model picker (DECISIONS 2026-07-09).
6. **Thinking stream shapes** (2.1.205 and 2.1.206 identical): `content_block_start` with `{"type":"thinking","thinking":"","signature":""}` → repeated `content_block_delta` `{"type":"thinking_delta","thinking":"<text>","estimated_tokens":null}` → `{"type":"signature_delta","signature":"<opaque>"}` (ignore) → `content_block_stop`. The final `assistant` event carries the complete `{"type":"thinking","thinking":"…","signature":"…"}` content block — **also present in on-disk transcripts**, so historical replay gets thinking for free.
7. **NEW `system/thinking_tokens` events** interleave with thinking deltas: `{"type":"system","subtype":"thinking_tokens","estimated_tokens":N,"estimated_tokens_delta":M,"uuid":…,"session_id":…}` — a ready-made thinking ticker. Flows through the tolerant `.system` path today; nothing renders it.
8. **NEW `system/status` variant:** `{"subtype":"status","status":"requesting"}` fires when a turn starts hitting the API (no `permissionMode` key). The existing handler reads only `permissionMode` from status events, so this is currently inert — fine, but it's a liveness signal worth consuming.
9. **Task tools are live in `-p` stream-json** (even with `--setting-sources ""`), **no permission gates**, and TodoWrite is absent from the init tool list. Wire shapes:
   - `TaskCreate` input `{subject: String, description: String, activeForm?: String, metadata?: {…}}` → tool_result content `"Task #1 created successfully: Alpha task"`, and the `user` event carries **`tool_use_result: {"task": {"id": "1", "subject": "Alpha task"}}`** — a structured id, no text parsing needed.
   - `TaskUpdate` input `{taskId: String, status?: "pending"|"in_progress"|"completed"|"deleted", subject?, description?, activeForm?, owner?, addBlocks?, addBlockedBy?}` → result `"Updated task #1 status"` / `"Updated task #3 deleted"` (the new status is NOT echoed for plain status changes — apply from the input, confirm on non-error result).
   - `TaskList` input `{}` → result text `"#1 [completed] Alpha task\n#2 [pending] Beta task"` — deleted tasks are omitted. Parseable as a full-state resync.
10. **`tool_use_result` placement:** it is a field on the `user` event LINE (sibling of `message`), not on the tool_result content block. Every observed line pairs one tool_result block with one `tool_use_result`. Decode it onto the `ToolResult` only when the line carries exactly one tool_result block; otherwise drop it (the text-parse fallback in Task 4 covers the hypothetical multi-block case).
11. **Control-op error acks carry the reason in `response.error`** (`{"subtype":"error","request_id":…,"error":"Model \"…\" is not a recognized model id.…"}`) — the current decoder drops it (`payload` only captures `response.response`, which error acks don't have). Success acks for `set_permission_mode` echo `{"mode":…}` and validate nothing (4a finding 9 stands).
12. **Slash commands re-emit `system/init`** before their synthetic output. `ChatSession.handle(.systemInit)` is already idempotent-adjacent (re-sets info/isReady/model/permissionMode); harmless, but Task 2's gate-preservation guard matters: a `result` with `num_turns == 0` must NOT clear `pendingGates` or a slash command sent while a gate is pending would strand the CLI's question.
13. **`tool_use` content_block_start now carries `caller: {"type":"direct"}`** — flows through tolerant decoding, no action needed.
14. **On-disk subagent transcripts** (census 2026-07-11, all 761 sessions): the modern CLI writes them to `<project>/<parent-session-id>/subagents/agent-<agentId>.jsonl` with a sibling `agent-<agentId>.meta.json` = `{"agentType": "general-purpose", "description": "…", "toolUseId": "toolu_…", "spawnDepth": 1}`. **`toolUseId` links each file to the parent's Task tool_use card.** Zero top-level sidechain session files exist anywhere — `SessionStore`'s depth-2 `*.jsonl` enumeration already never lists them. The brief's "subagent transcripts appear as ordinary sessions" pollution is actually **probe-scratchpad and worktree PROJECT directories** (18 `-private-tmp-…-probe-*` projects from 4a plan-writing alone) — feature 18's activity filter is the treatment, plus probes now reuse `~/Developer/fabled-smoke-scratch` (this plan's probes already do).

## Contract amendments vs the brief (conscious; ledgered in DECISIONS.md 2026-07-11)

- **`TimelineItem` gains a `.thinking(id:text:isStreaming:)` case.** The Plan 3 locked contract said views never see raw events; extending the vocabulary is the sanctioned mechanism (4a extended it implicitly via toolResult parentage). Replay renders historical thinking dimmed; live coalesces deltas exactly like `.assistantText`.
- **Feature 15 is rescoped to disk reality** (finding 14): the deliverable is historical subagent drill-down (`SessionStore.subagentTimelines(for:)` + inspector wiring) plus a guard test pinning the depth-2 enumeration invariant. No sidebar filtering of subagent files is needed — they were never visible.
- **Feature 16 "Continue vs View" needs no new resume plumbing** — `--resume` reuses the same session id (DECISIONS 2026-07-09); the work is affordance labelling, a duplicate-resume guard (one live process per session id, enforced app-side), fork labelling, and surfacing the `$HOME` cwd fallback.
- **The checklist card reads task tools, not TodoWrite** (finding 9). `ChatSession.todos` and the TodoWrite path stay as dormant legacy (they cost nothing and older CLIs may resurrect them); the card renders whichever source is non-empty, tasks winning.
- **`/remote-control` is out of scope** (finding 4 — blocked upstream). The slash-command transport it would have used ships anyway (effort picker sends `/effort` as user text).
- **Signature changes, every match site updated in the owning task:** `ToolResult` gains `toolUseResult: JSONValue?` (defaulted — non-breaking); `ControlResponseEnvelope` gains `errorMessage: String?` (defaulted); `SessionConfiguration` gains `effort: String?`; `AgentConnection.setModel`/`setPermissionMode` return the control request id (`(String) async -> String`); `TimelineItemView` takes `subagentSteps: Int?` instead of reading `session` (Task 14); `TimelineItem.toolCallID` becomes public.
- **`pendingGates` clearing on `result` is refined:** only results that close a real turn (`num_turns != 0`) abandon gates (finding 12). The 4a behavior for interrupts/errors is preserved and test-pinned.

## Conventions for implementing agents

- Repo root: `~/Developer/Fabled`. All commands run from there. (Bash `cd` state can reset between calls — prefix git commands with `git -C ~/Developer/Fabled` or re-`cd` per call.)
- Package build/test: `swift build && swift test` — green before **every** commit. Never commit red. If unrelated tests SIGSEGV after enum/struct growth, `rm -rf .build` before suspecting your code (stale incremental artifacts — known scar).
- App build: `xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled -configuration Debug build` (expected final line `** BUILD SUCCEEDED **`). Never hand-edit `Fabled.xcodeproj` — generated, gitignored; `project.yml` is source of truth. **Task 5 is the only task that edits `project.yml`.**
- Swift 6 strict concurrency is ON. Everything public is `Sendable` (or `@MainActor`). View models `@MainActor @Observable`; views stay logic-free.
- Zero third-party dependencies. AttributedString for markdown (inline-only; ledgered).
- Protocol ground truth: the fixtures in the table above + "Probe findings". When a shape is in question, open the fixture and look. Do not guess.
- Tolerant decoding is load-bearing: unknown types keep flowing through `.unknown`/`.system`/`.other`, never throw.
- `fixtures/` content is real data from Ben's machine, approved for **local** use only. Do not publish or quote transcript content in commit messages.
- All new tests are offline. No new live tests in this plan (the fixtures pin every shape).
- UI tasks end with a build + scripted smoke check instead of unit tests; anything with logic goes in FabledCore/ClaudeKit where `swift test` reaches it.
- **Design tokens are law after Task 5:** no ad-hoc colors, fonts, spacing, or animation literals in App views — everything routes through `Theme`. A reviewer finding a raw `Color(red:…)` outside Theme.swift should fail the task.
- SwiftUI scars (from 4a, all still apply): rows use `.onTapGesture` + a11y traits, never plain Buttons whose environment churns; `contentShape`+gesture go OUTSIDE `.padding`/`.background`; presentation modifiers attach to stable concrete roots, never `Group`-over-conditional; presented content (`.inspector`, `.sheet`) does NOT inherit custom `.environment` values — pass actions explicitly; no per-row `@State` inside LazyVStack (container-level state keyed by stable ids instead).
- Existing tests stay green. Tasks that deliberately change existing behavior say so explicitly; any other breakage is a bug in your change.

## File structure

```
Sources/ClaudeKit/
  SessionConfiguration.swift     # MODIFY T1: effort property + --effort argument
  AgentEvent.swift               # MODIFY T1: ToolResult.toolUseResult, ControlResponseEnvelope.errorMessage
  AgentEventDecoder.swift        # MODIFY T1: decode tool_use_result + error acks
  SessionStore.swift             # MODIFY T14: subagentTimelines(for:) + meta.json parsing
Sources/FabledCore/
  AgentConnection.swift          # MODIFY T2 (ModelOption effort fields), T6 (control ops return request id)
  ChatSession.swift              # MODIFY T2 (effort, gate guard), T3 (thinking ticker), T4 (task fold), T6 (liveness, acks), T12 (resumedSessionID), T15 (draft)
  InteractionModels.swift        # MODIFY T6: InteractionGate.summaryLine
  TaskChecklist.swift            # CREATE T4: TaskItem + fold + TaskList resync parser
  TimelineItem.swift             # MODIFY T3: .thinking case; T14: public toolCallID
  TimelineReducer.swift          # MODIFY T3: thinking coalescing/replay; T14: allowSidechain
  TimelineDisplay.swift          # CREATE T13: step-grouping pass + summaries
  SidebarOrganizer.swift         # CREATE T8: options model + grouping/sort/filter/pinning
  AppModel.swift                 # MODIFY T2 (preferred effort), T8 (options), T9/T10 (welcome), T11 (notification policy hooks), T12 (resume semantics)
  NotificationPolicy.swift       # CREATE T11: pure decision logic
App/
  Theme.swift                    # MODIFY T5: full token expansion (palette/type/spacing/motion/status)
  Assets.xcassets/               # CREATE T5: AppIcon from docs/assets/icon/Fabled.iconset
  EffortPickerMenu.swift         # CREATE T2: catalog-driven effort picker
  ThinkingViews.swift            # CREATE T3: thinking row + ticker
  TodoChecklistView.swift        # MODIFY T4: generalized checklist rows (tasks + todos)
  StatusBadge.swift              # CREATE T6: shape+color+word session-state badge
  ConversationView.swift         # MODIFY T2/T3/T6 (toolbar, thinking, liveness), T13 (groups), T15 (identity)
  SidebarView.swift              # MODIFY T7 (badges), T8 (filter/sort/pin UI)
  WelcomeView.swift              # REWRITE T9/T10: attention inbox + welcome composer
  HistoricalSessionView.swift    # MODIFY T12 (Continue/Fork, race fix), T13 (groups), T14 (drill-down)
  TimelineItemViews.swift        # MODIFY T13 (group rows), T14 (subagentSteps param, Agent-Agent fix)
  InspectorView.swift            # MODIFY T3 (thinking detail), T14 (historical sub-rows)
  RootView.swift                 # MODIFY T11 (notification wiring), T15 (ConversationView identity)
  ComposerView.swift             # MODIFY T15: draft moves to ChatSession
  FabledApp.swift                # MODIFY T11: notification delegate setup
project.yml                      # MODIFY T5: app icon setting (repo root)
Tests/ClaudeKitTests/
  SessionConfigurationTests.swift # MODIFY T1
  AgentEventDecoderTests.swift    # MODIFY T1
  SessionStoreTests.swift         # MODIFY T14: subagent reads + depth-2 guard
Tests/FabledCoreTests/
  ChatSessionTests.swift          # MODIFY T2/T3/T4/T6/T12
  TimelineReducerTests.swift      # MODIFY T3
  TaskChecklistTests.swift        # CREATE T4
  TimelineDisplayTests.swift      # CREATE T13
  SidebarOrganizerTests.swift     # CREATE T8
  NotificationPolicyTests.swift   # CREATE T11
  AppModelTests.swift             # MODIFY T8/T9/T12
  TimelineReplayTests.swift       # MODIFY T3/T4: new-fixture replays
```

Task order is execution order: Ben's FASTER priority first (T1–T4), the design language before the UI it governs (T5), then signals (T6–T8), the welcome surface (T9–T10), notifications (T11), semantics and hygiene (T12–T14), close-out (T15).

---

## Task 1: ClaudeKit wire additions — effort flag, tool_use_result, control-op errors

The three smallest possible engine changes, all fixture-pinned: `SessionConfiguration` learns `--effort`, `ToolResult` learns the structured `tool_use_result` payload (finding 10), and `ControlResponseEnvelope` learns the error string that error acks carry (finding 11).

**Files:**
- Modify: `Sources/ClaudeKit/SessionConfiguration.swift`
- Modify: `Sources/ClaudeKit/AgentEvent.swift`
- Modify: `Sources/ClaudeKit/AgentEventDecoder.swift`
- Test: `Tests/ClaudeKitTests/SessionConfigurationTests.swift`, `Tests/ClaudeKitTests/AgentEventDecoderTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/ClaudeKitTests/SessionConfigurationTests.swift`:

```swift
    func testEffortArgument() {
        var configuration = SessionConfiguration(
            workingDirectory: URL(fileURLWithPath: "/tmp"))
        XCTAssertFalse(configuration.arguments().contains("--effort"),
                       "nil effort adds no flag")
        configuration.effort = "medium"
        let args = configuration.arguments()
        guard let index = args.firstIndex(of: "--effort") else {
            return XCTFail("--effort missing from \(args)")
        }
        XCTAssertEqual(args[args.index(after: index)], "medium")
    }
```

Append to `Tests/ClaudeKitTests/AgentEventDecoderTests.swift` (shapes verbatim from `2026-07-11-tasktools.jsonl` and `2026-07-09-badmodel-ack.jsonl`):

```swift
    func testToolResultCarriesToolUseResult() throws {
        let line = ##"{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_01M4","type":"tool_result","content":"Task #1 created successfully: Alpha task"}]},"parent_tool_use_id":null,"session_id":"7d97","uuid":"u1","tool_use_result":{"task":{"id":"1","subject":"Alpha task"}}}"##
        let event = try AgentEventDecoder.decode(Data(line.utf8))
        guard case .toolResult(let results, _) = event else {
            return XCTFail("expected toolResult, got \(event)")
        }
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].toolUseResult?["task"]?["id"]?.stringValue, "1")
        XCTAssertEqual(results[0].toolUseResult?["task"]?["subject"]?.stringValue,
                       "Alpha task")
    }

    func testToolUseResultOnlyAttachesToSingleResultLines() throws {
        // Two tool_result blocks + one line-level tool_use_result is ambiguous;
        // the decoder must drop it rather than guess (probe finding 10).
        let line = ##"{"type":"user","message":{"role":"user","content":[{"tool_use_id":"a","type":"tool_result","content":"one"},{"tool_use_id":"b","type":"tool_result","content":"two"}]},"tool_use_result":{"task":{"id":"1"}}}"##
        let event = try AgentEventDecoder.decode(Data(line.utf8))
        guard case .toolResult(let results, _) = event else {
            return XCTFail("expected toolResult, got \(event)")
        }
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.toolUseResult == nil })
    }

    func testControlErrorAckCarriesMessage() throws {
        let line = ##"{"type":"control_response","response":{"subtype":"error","request_id":"badmodel-1","error":"Model \"totally-bogus-model-9000\" is not a recognized model id. Run /model to see available models."}}"##
        let event = try AgentEventDecoder.decode(Data(line.utf8))
        guard case .controlResponse(let envelope) = event else {
            return XCTFail("expected controlResponse, got \(event)")
        }
        XCTAssertEqual(envelope.subtype, "error")
        XCTAssertEqual(envelope.requestID, "badmodel-1")
        XCTAssertEqual(envelope.errorMessage,
                       #"Model "totally-bogus-model-9000" is not a recognized model id. Run /model to see available models."#)
    }

    func testSuccessAckHasNoErrorMessage() throws {
        let line = ##"{"type":"control_response","response":{"subtype":"success","request_id":"ok-1","response":{"mode":"plan"}}}"##
        let event = try AgentEventDecoder.decode(Data(line.utf8))
        guard case .controlResponse(let envelope) = event else {
            return XCTFail("expected controlResponse, got \(event)")
        }
        XCTAssertNil(envelope.errorMessage)
        XCTAssertEqual(envelope.payload?["mode"]?.stringValue, "plan")
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "testEffortArgument|testToolResultCarries|testToolUseResultOnly|testControlErrorAck|testSuccessAckHasNo" 2>&1 | tail -20`
Expected: compile errors — `effort`, `toolUseResult`, `errorMessage` don't exist yet.

- [ ] **Step 3: Implement**

`Sources/ClaudeKit/SessionConfiguration.swift` — add below `public var permissionMode: String?`:

```swift
    /// Model effort level (low|medium|high|xhigh|max) — Claude Desktop passes
    /// this on every spawn; measured on this repo: `medium` cut first visible
    /// text 24s → 17s (probe finding 1). nil = CLI default.
    public var effort: String?
```

and in `arguments()`, after the `if let model` line:

```swift
        if let effort { args += ["--effort", effort] }
```

`Sources/ClaudeKit/AgentEvent.swift` — replace the `ToolResult` struct:

```swift
public struct ToolResult: Sendable, Equatable {
    public let toolUseID: String
    public let content: JSONValue
    public let isError: Bool
    /// The `user` line's structured `tool_use_result` payload (e.g. TaskCreate's
    /// `{"task":{"id":"1",…}}`). Only attached when the line carries exactly one
    /// tool_result block — the field is per-line, not per-block (probe finding 10).
    public let toolUseResult: JSONValue?

    public init(toolUseID: String, content: JSONValue, isError: Bool,
                toolUseResult: JSONValue? = nil) {
        self.toolUseID = toolUseID
        self.content = content
        self.isError = isError
        self.toolUseResult = toolUseResult
    }
}
```

(If the current struct has no explicit `init`, add it as above — the defaulted parameter keeps every existing construction site compiling.)

Replace the `ControlResponseEnvelope` struct:

```swift
public struct ControlResponseEnvelope: Sendable, Equatable {
    public let requestID: String
    public let subtype: String
    public let payload: JSONValue?
    /// `response.error` on error acks — e.g. set_model's "not a recognized
    /// model id" (fixtures/2026-07-09-badmodel-ack.jsonl). nil on success.
    public let errorMessage: String?

    public init(requestID: String, subtype: String, payload: JSONValue?,
                errorMessage: String? = nil) {
        self.requestID = requestID
        self.subtype = subtype
        self.payload = payload
        self.errorMessage = errorMessage
    }
}
```

`Sources/ClaudeKit/AgentEventDecoder.swift` — in `decode(raw:)`, replace the `case "user":` body:

```swift
        case "user":
            let blocks = raw["message"]?["content"]?.arrayValue ?? []
            let resultBlocks = blocks.filter {
                $0["type"]?.stringValue == "tool_result"
            }
            // Line-level field; unambiguous only for single-result lines
            // (probe finding 10).
            let lineResult = resultBlocks.count == 1 ? raw["tool_use_result"] : nil
            let results = resultBlocks.compactMap { block -> ToolResult? in
                guard let id = block["tool_use_id"]?.stringValue else { return nil }
                return ToolResult(
                    toolUseID: id,
                    content: block["content"] ?? .null,
                    isError: block["is_error"]?.boolValue ?? false,
                    toolUseResult: lineResult)
            }
            return .toolResult(results,
                               parentToolUseID: raw["parent_tool_use_id"]?.stringValue)
```

and replace the `case "control_response":` body:

```swift
        case "control_response":
            let response = raw["response"]
            return .controlResponse(ControlResponseEnvelope(
                requestID: response?["request_id"]?.stringValue ?? "",
                subtype: response?["subtype"]?.stringValue ?? "",
                payload: response?["response"],
                errorMessage: response?["error"]?.stringValue))
```

- [ ] **Step 4: Run the full suite**

Run: `swift build && swift test 2>&1 | tail -3`
Expected: `Executed 22x tests, with 6 tests skipped and 0 failures` (224 = 220 + 4 new; exact count in your output). If unrelated tests SIGSEGV, `rm -rf .build` and re-run before debugging.

- [ ] **Step 5: Commit**

```bash
git -C ~/Developer/Fabled add Sources/ClaudeKit Tests/ClaudeKitTests
git -C ~/Developer/Fabled commit -m "feat(claudekit): --effort spawn flag, tool_use_result + control-error decoding (4b T1)"
```

---

## Task 2: Effort control — catalog metadata, ChatSession state, picker, spawn default

Ben's #1 FASTER lever. Effort is settable three ways: a persisted preference applied to every new spawn (`--effort`, what Claude Desktop does), a per-session picker that sends the CLI's own `/effort` command as user text (probe finding 2 — zero API cost), and the model catalog says which levels each model supports (finding 5). This task also lands the gate-preservation guard for synthetic slash results (finding 12).

**Files:**
- Modify: `Sources/FabledCore/AgentConnection.swift` (ModelOption effort fields)
- Modify: `Sources/FabledCore/ChatSession.swift`
- Modify: `Sources/FabledCore/AppModel.swift`
- Create: `App/EffortPickerMenu.swift`
- Modify: `App/ConversationView.swift` (toolbar)
- Test: `Tests/FabledCoreTests/ChatSessionTests.swift`, `Tests/FabledCoreTests/ModelOptionTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/FabledCoreTests/ChatSessionTests.swift`:

```swift
    func testCatalogHarvestsEffortMetadata() async throws {
        let (session, continuation, _) = makeSession()
        try yield(continuation, #"""
        {"type":"control_response","response":{"subtype":"success","request_id":"init","response":{"commands":[],"models":[{"value":"default","resolvedModel":"claude-opus-4-8[1m]","displayName":"Default (recommended)","supportsEffort":true,"supportedEffortLevels":["low","medium","high","xhigh","max"]},{"value":"haiku","displayName":"Haiku","supportsEffort":false}]}}}
        """#)
        await waitUntil("catalog") { !session.models.isEmpty }
        XCTAssertTrue(session.models[0].supportsEffort)
        XCTAssertEqual(session.models[0].supportedEffortLevels,
                       ["low", "medium", "high", "xhigh", "max"])
        XCTAssertFalse(session.models[1].supportsEffort)
        XCTAssertEqual(session.models[1].supportedEffortLevels, [])
    }

    func testSetEffortSendsSlashCommandAndSetsState() async throws {
        let (session, continuation, recorder) = makeSession()
        _ = continuation
        session.setEffort("medium")
        XCTAssertEqual(session.currentEffort, "medium")
        let entries = await waitForEntries(recorder, count: 1)
        XCTAssertEqual(entries, [.send("/effort medium")])
        // The local echo appears in the timeline like any user message.
        XCTAssertTrue(session.timeline.contains {
            if case .userMessage(_, "/effort medium") = $0 { return true }
            return false
        })
    }

    func testSyntheticSlashResultPreservesPendingGates() async throws {
        let (session, continuation, _) = makeSession()
        // A pending permission gate…
        try yield(continuation, #"""
        {"type":"control_request","request_id":"perm-1","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"ls"}}}
        """#)
        await waitUntil("gate") { session.pendingGate != nil }
        // …must survive a synthetic slash-command result (num_turns == 0,
        // probe finding 12)…
        try yield(continuation, #"""
        {"type":"result","subtype":"success","is_error":false,"num_turns":0,"duration_ms":1,"result":"Set effort level to medium (this session only)","session_id":"s"}
        """#)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertNotNil(session.pendingGate, "slash result must not clear gates")
        // …and still be cleared by a real turn's result (4a abort semantics).
        try yield(continuation, #"""
        {"type":"result","subtype":"error_during_execution","is_error":true,"num_turns":3,"duration_ms":100,"session_id":"s"}
        """#)
        await waitUntil("gate cleared") { session.pendingGate == nil }
    }

    func testLaunchEffortSeedsCurrentEffort() {
        let (connection, _, _) = makeFakeConnection()
        let session = ChatSession(
            connection: connection,
            workingDirectory: URL(fileURLWithPath: "/tmp/demo"),
            effort: "medium")
        XCTAssertEqual(session.currentEffort, "medium")
    }
```

Append to `Tests/FabledCoreTests/ModelOptionTests.swift`:

```swift
    func testKnownModelsDefaultToUnknownEffortSupport() {
        // Hand-maintained entries don't claim effort knowledge; the picker
        // falls back to the standard five levels for them.
        for option in ModelOption.knownModels {
            XCTAssertTrue(option.supportsEffort)
            XCTAssertEqual(option.supportedEffortLevels, [])
        }
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "EffortMetadata|SetEffort|SyntheticSlash|LaunchEffortSeeds|UnknownEffortSupport" 2>&1 | tail -15`
Expected: compile errors — `supportsEffort`, `setEffort`, `currentEffort`, `effort:` init parameter don't exist.

- [ ] **Step 3: Implement**

`Sources/FabledCore/AgentConnection.swift` — replace the `ModelOption` struct declaration and init (keep the `knownModels`/`merged` extension as is):

```swift
/// One entry of the initialize response's model catalog (probe finding 9;
/// effort metadata probe finding 5, 2026-07-11).
public struct ModelOption: Sendable, Equatable, Identifiable {
    public let value: String
    public let resolvedModel: String?
    public let displayName: String
    public let optionDescription: String?
    /// Whether the model takes an effort level. Hand-maintained knownModels
    /// entries claim true with an EMPTY levels list = "unknown, offer the
    /// standard five"; only the live catalog states levels authoritatively.
    public let supportsEffort: Bool
    public let supportedEffortLevels: [String]
    public var id: String { value }

    public init(value: String, resolvedModel: String?,
                displayName: String, optionDescription: String?,
                supportsEffort: Bool = true,
                supportedEffortLevels: [String] = []) {
        self.value = value
        self.resolvedModel = resolvedModel
        self.displayName = displayName
        self.optionDescription = optionDescription
        self.supportsEffort = supportsEffort
        self.supportedEffortLevels = supportedEffortLevels
    }
}
```

`Sources/FabledCore/ChatSession.swift`:

1. Below `public private(set) var currentModel: String?` add:

```swift
    /// Session effort level: the spawn --effort value, then whatever the
    /// user last picked (sent as the CLI's own /effort command). nil = CLI
    /// default, never overridden from the wire (the CLI doesn't report it).
    public private(set) var currentEffort: String?
```

2. Extend the initializer signature (existing callers pass no effort — default keeps them compiling):

```swift
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
```

3. In `launch(configuration:)`, pass the configuration's effort through:

```swift
        let session = ChatSession(
            connection: .live(agent),
            workingDirectory: configuration.workingDirectory,
            permissionMode: configuration.permissionMode ?? "default",
            model: configuration.model,
            effort: configuration.effort)
```

4. Below `setPermissionMode(_:)` add:

```swift
    /// Sends the CLI's own /effort command as user text (probe finding 2):
    /// zero API cost, the CLI replies with a synthetic assistant message
    /// narrating the change, and the result carries num_turns == 0.
    public func setEffort(_ level: String) {
        currentEffort = level
        send("/effort \(level)")
    }
```

5. In `handle(_:)`, `case .result(let turn):` — replace the `pendingGates.removeAll()` line and its comment with:

```swift
            // An aborted turn (interrupt → error_during_execution) abandons any
            // open permission gate — the CLI is no longer waiting for a decision.
            // On normal completion the list is already empty, so this is a no-op.
            // EXCEPT synthetic slash-command results (num_turns == 0, probe
            // finding 12): those never close a real turn, and a gate pending
            // while one arrives is still live on the CLI side.
            if turn.raw["num_turns"]?.doubleValue != 0 {
                pendingGates.removeAll()
            }
```

6. In `harvestCatalog(_:)`, replace the `models = …` assignment:

```swift
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
```

7. Bump the tested version constant (fixtures re-recorded on 2.1.206 this plan):

```swift
    /// CLI version the current fixtures were recorded against.
    public static let testedCLIVersion = "2.1.206"
```

(`testSystemInitPopulatesModelAndMode` interpolates this constant, so it stays green; no other test pins the literal.)

`Sources/FabledCore/AppModel.swift`:

1. Below `public var isPickingFolder = false` add:

```swift
    /// Effort applied to every new spawn via --effort (what Claude Desktop
    /// does). Persisted; nil = CLI default. Session-scoped changes go through
    /// ChatSession.setEffort and don't touch this.
    public var preferredEffort: String? {
        didSet {
            UserDefaults.standard.set(preferredEffort, forKey: Self.preferredEffortKey)
        }
    }
    private static let preferredEffortKey = "preferredEffort"
```

2. In `init`, after `self.index = …`:

```swift
        self.preferredEffort = UserDefaults.standard.string(forKey: Self.preferredEffortKey)
```

3. In `newSession(at:model:)` and `resume(_:fork:)`, before `await launch(…)`:

```swift
        configuration.effort = preferredEffort
```

`App/EffortPickerMenu.swift` (new file):

```swift
import SwiftUI
import FabledCore

/// Catalog-driven effort picker (probe finding 5). Session-scoped changes
/// ride the CLI's own /effort command; "Auto" is the CLI's adaptive mode
/// (catalog argumentHint includes it even though supportedEffortLevels
/// doesn't). The "New sessions" section sets the persisted spawn default
/// (--effort, what Claude Desktop passes). Session controls are disabled
/// while a gate is pending — a slash send would queue behind the CLI's
/// open question.
struct EffortPickerMenu: View {
    @Environment(AppModel.self) private var app
    let session: ChatSession
    static let fallbackLevels = ["low", "medium", "high", "xhigh", "max"]

    private var levels: [String] {
        guard let current = session.currentModel,
              let match = session.models.first(where: {
                  $0.value == current || $0.resolvedModel == current
              }),
              match.supportsEffort
        else { return Self.fallbackLevels }
        return match.supportedEffortLevels.isEmpty
            ? Self.fallbackLevels : match.supportedEffortLevels
    }

    var body: some View {
        Menu {
            Section("This session") {
                ForEach(levels, id: \.self) { level in
                    optionButton(level, title: level.capitalized)
                }
                optionButton("auto", title: "Auto")
            }
            .disabled(session.pendingGate != nil || session.hasEnded)
            Section("New sessions") {
                defaultButton(nil, title: "CLI default")
                ForEach(Self.fallbackLevels, id: \.self) { level in
                    defaultButton(level, title: level.capitalized)
                }
            }
        } label: {
            Label(session.currentEffort?.capitalized ?? "Effort",
                  systemImage: "gauge.with.needle")
                .labelStyle(.titleAndIcon)
        }
        .help("Model effort — lower is faster")
    }

    @ViewBuilder
    private func optionButton(_ level: String, title: String) -> some View {
        Button { session.setEffort(level) } label: {
            if session.currentEffort == level {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    @ViewBuilder
    private func defaultButton(_ level: String?, title: String) -> some View {
        Button { app.preferredEffort = level } label: {
            if app.preferredEffort == level {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}
```

`App/ConversationView.swift` — in the toolbar `ToolbarItemGroup`, insert directly after `ModelPickerMenu(session: session)`:

```swift
                EffortPickerMenu(session: session)
```

- [ ] **Step 4: Run the full suite, then build the app**

Run: `swift build && swift test 2>&1 | tail -3`
Expected: 0 failures (5 new tests).
Run: `xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled -configuration Debug build 2>&1 | tail -2`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git -C ~/Developer/Fabled add Sources/FabledCore App Tests/FabledCoreTests
git -C ~/Developer/Fabled commit -m "feat: effort control — catalog metadata, /effort picker, --effort spawn default, gate guard (4b T2)"
```

---

## Task 3: Thinking rendering — timeline case, live coalescing, replay, token ticker

The second FASTER lever: perceived activation. Claude Desktop shows the thinking stream and feels alive in ~3s; Fabled shows a bare spinner for 17–24s. This task renders thinking deltas as a dimmed, live-updating row (finding 6), replays historical thinking from transcript assistant blocks (free — they're on disk), and turns the `system/thinking_tokens` events (finding 7) into a ticker.

**Files:**
- Modify: `Sources/FabledCore/TimelineItem.swift`
- Modify: `Sources/FabledCore/TimelineReducer.swift`
- Modify: `Sources/FabledCore/ChatSession.swift`
- Create: `App/ThinkingViews.swift`
- Modify: `App/TimelineItemViews.swift`, `App/ConversationView.swift`, `App/InspectorView.swift`
- Test: `Tests/FabledCoreTests/TimelineReducerTests.swift`, `Tests/FabledCoreTests/ChatSessionTests.swift`, `Tests/FabledCoreTests/TimelineReplayTests.swift`

- [ ] **Step 1: Write the failing reducer tests**

Append to `Tests/FabledCoreTests/TimelineReducerTests.swift`:

```swift
    // MARK: - Thinking (4b T3)

    private func thinkingDelta(_ text: String, uuid: String = "u") throws -> AgentEvent {
        try AgentEventDecoder.decode(Data(#"""
        {"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"\#(text)","estimated_tokens":null}},"session_id":"s","parent_tool_use_id":null,"uuid":"\#(uuid)"}
        """#.utf8))
    }

    func testThinkingDeltasCoalesceIntoOneItem() throws {
        var items: [TimelineItem] = []
        items = TimelineReducer.reduce(items, try thinkingDelta("The user", uuid: "t1"))
        items = TimelineReducer.reduce(items, try thinkingDelta(" wants a plan"))
        XCTAssertEqual(items.count, 1)
        guard case .thinking(let id, let text, let isStreaming) = items[0] else {
            return XCTFail("expected thinking, got \(items)")
        }
        XCTAssertEqual(id, "t1")
        XCTAssertEqual(text, "The user wants a plan")
        XCTAssertTrue(isStreaming)
    }

    func testAssistantThinkingBlockFinalizesStreamedItem() throws {
        var items: [TimelineItem] = []
        items = TimelineReducer.reduce(items, try thinkingDelta("The user wants", uuid: "t1"))
        let assistant = try AgentEventDecoder.decode(Data(#"""
        {"type":"assistant","message":{"role":"assistant","model":"m","content":[{"type":"thinking","thinking":"The user wants a plan.","signature":"sig"},{"type":"text","text":"Here it is."}]},"session_id":"s","uuid":"a1"}
        """#.utf8))
        items = TimelineReducer.reduce(items, assistant)
        guard case .thinking(let id, let text, let isStreaming) = items[0] else {
            return XCTFail("expected finalized thinking first, got \(items)")
        }
        XCTAssertEqual(id, "t1", "same item id — update in place, not remove+insert")
        XCTAssertEqual(text, "The user wants a plan.")
        XCTAssertFalse(isStreaming)
        guard case .assistantText = items[1] else {
            return XCTFail("expected assistant text second, got \(items)")
        }
    }

    func testReplayRendersThinkingFromTranscriptBlocks() throws {
        // No streaming preceded it (replay path) — the block appends finalized.
        let assistant = try AgentEventDecoder.decode(Data(#"""
        {"type":"assistant","message":{"role":"assistant","model":"m","content":[{"type":"thinking","thinking":"Recorded thought.","signature":"sig"}]},"session_id":"s","uuid":"a1"}
        """#.utf8))
        let items = TimelineReducer.reduce([], assistant)
        guard case .thinking(_, "Recorded thought.", false) = items[0] else {
            return XCTFail("expected finalized thinking, got \(items)")
        }
    }

    func testTextDeltaAfterThinkingDoesNotCoalesceIntoIt() throws {
        var items: [TimelineItem] = []
        items = TimelineReducer.reduce(items, try thinkingDelta("hmm", uuid: "t1"))
        let textDelta = try AgentEventDecoder.decode(Data(#"""
        {"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Answer"}},"session_id":"s","uuid":"x1"}
        """#.utf8))
        items = TimelineReducer.reduce(items, textDelta)
        XCTAssertEqual(items.count, 2)
        guard case .assistantText(_, "Answer", true) = items[1] else {
            return XCTFail("expected separate streaming text, got \(items)")
        }
    }

    func testResultFinalizesDanglingThinking() throws {
        var items: [TimelineItem] = []
        items = TimelineReducer.reduce(items, try thinkingDelta("interrupted", uuid: "t1"))
        let result = try AgentEventDecoder.decode(Data(#"""
        {"type":"result","subtype":"error_during_execution","is_error":true,"num_turns":1,"uuid":"r1","session_id":"s"}
        """#.utf8))
        items = TimelineReducer.reduce(items, result)
        guard case .thinking(_, _, false) = items[0] else {
            return XCTFail("dangling thinking must finalize, got \(items)")
        }
    }
```

Append to `Tests/FabledCoreTests/ChatSessionTests.swift`:

```swift
    func testThinkingTokensTickerAccumulatesAndResets() async throws {
        let (session, continuation, _) = makeSession()
        try yield(continuation, #"""
        {"type":"system","subtype":"thinking_tokens","estimated_tokens":44,"estimated_tokens_delta":17,"uuid":"tt1","session_id":"s"}
        """#)
        await waitUntil("ticker") { session.thinkingTokens == 44 }
        try yield(continuation, #"""
        {"type":"result","subtype":"success","is_error":false,"num_turns":1,"duration_ms":5,"session_id":"s"}
        """#)
        await waitUntil("reset") { session.thinkingTokens == nil }
    }
```

Append to `Tests/FabledCoreTests/TimelineReplayTests.swift` (follow the file's existing replay-over-fixture pattern):

```swift
    func testSlashfxFixtureProducesThinkingItems() throws {
        var items: [TimelineItem] = []
        for event in try CoreFixtures.events("2026-07-11-slashfx.jsonl") {
            items = TimelineReducer.reduce(items, event)
        }
        let thinking = items.compactMap { item -> Bool? in
            if case .thinking(_, _, let streaming) = item { return streaming }
            return nil
        }
        XCTAssertFalse(thinking.isEmpty, "fixture carries thinking turns")
        XCTAssertTrue(thinking.allSatisfy { $0 == false },
                      "every thinking item finalizes by end of fixture")
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "Thinking|thinking" 2>&1 | tail -15`
Expected: compile errors — `TimelineItem.thinking` and `ChatSession.thinkingTokens` don't exist.

- [ ] **Step 3: Implement the core**

`Sources/FabledCore/TimelineItem.swift` — add the case and extend `id`:

```swift
    case thinking(id: String, text: String, isStreaming: Bool)
```

and in the `id` switch add `.thinking(let id, _, _)` to the first pattern group (alongside the other `let id` captures).

`Sources/FabledCore/TimelineReducer.swift`:

1. In `reduceStream`, replace the `.thinkingDelta` handling — remove `.thinkingDelta` from the ignore list and add above it:

```swift
        case .thinkingDelta(_, let thinking):
            if case .thinking(let id, let text, true) = items.last {
                items[items.count - 1] = .thinking(
                    id: id, text: text + thinking, isStreaming: true)
            } else {
                items.append(.thinking(
                    id: stream.uuid ?? "thinking-\(items.count)",
                    text: thinking, isStreaming: true))
            }
```

(the ignore list becomes `case .messageStart, .contentBlockStart, .inputJSONDelta, .contentBlockStop, .messageDelta, .messageStop, .other:`)

2. In `reduceAssistant`, replace `case .thinking, .unknown: break` with:

```swift
            case .thinking(let text):
                guard !text.isEmpty else { break }
                finalizeThinking(&items, text: text, fallbackID: "\(baseID)-think-\(textIndex)")
            case .unknown:
                break
```

3. Add next to `finalizeText`:

```swift
    /// The final assistant message's thinking block replaces the streamed
    /// provisional item in place (same id — SwiftUI update, not remove+insert);
    /// on replay, where nothing streamed, it appends finalized.
    private static func finalizeThinking(_ items: inout [TimelineItem], text: String, fallbackID: String) {
        if case .thinking(let id, _, true) = items.last {
            items[items.count - 1] = .thinking(id: id, text: text, isStreaming: false)
        } else {
            items.append(.thinking(id: fallbackID, text: text, isStreaming: false))
        }
    }
```

4. Replace `finalizeDanglingStreamText` so an interrupted turn can't leave ANY streaming item — a thinking item can be stranded non-last when text deltas started after it (thinking → text → interrupt-before-assistant-event):

```swift
    /// A turn that ends without a finalizing assistant message (interrupt,
    /// error mid-stream) must not leave streaming items for later deltas to
    /// coalesce onto. Sweeps the whole array — see the stranded-thinking note.
    private static func finalizeDanglingStreamText(_ items: inout [TimelineItem]) {
        for index in items.indices {
            switch items[index] {
            case .assistantText(let id, let markdown, true):
                items[index] = .assistantText(id: id, markdown: markdown, isStreaming: false)
            case .thinking(let id, let text, true):
                items[index] = .thinking(id: id, text: text, isStreaming: false)
            default:
                break
            }
        }
    }
```

`Sources/FabledCore/ChatSession.swift`:

1. Below `public private(set) var isThinking = false`:

```swift
    /// Cumulative estimated thinking tokens for the current turn, from
    /// system/thinking_tokens events (probe finding 7). nil outside turns.
    public private(set) var thinkingTokens: Int?
```

2. In `handle(_:)` `case .system(let subtype, let raw):` — extend (keep the status branch):

```swift
            if subtype == "thinking_tokens",
               let estimated = raw["estimated_tokens"]?.doubleValue {
                thinkingTokens = Int(estimated)
            }
```

3. In `case .result`: alongside `isThinking = false` add `thinkingTokens = nil`.

- [ ] **Step 4: Run the core tests**

Run: `swift test 2>&1 | tail -3`
Expected: 0 failures (7 new).

- [ ] **Step 5: Implement the views**

`App/ThinkingViews.swift` (new file):

```swift
import SwiftUI
import FabledCore

/// A thinking row: dimmed, italic, deliberately quiet. While streaming it
/// shows a live tail of the thought (perceived activation — Ben's FASTER
/// directive); finalized it collapses to one summary line. Full text opens
/// in the inspector (no per-row expansion @State — 4a scar).
struct ThinkingItemView: View {
    let id: String
    let text: String
    let isStreaming: Bool
    @Environment(\.inspectItem) private var inspectItem

    /// Last ~240 characters, from a line boundary where possible.
    private var streamingTail: String {
        guard text.count > 240 else { return text }
        let tail = text.suffix(240)
        if let newline = tail.firstIndex(of: "\n"), newline != tail.endIndex {
            return "…" + tail[tail.index(after: newline)...]
        }
        return "…" + tail
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "sparkle")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
            if isStreaming {
                Text(streamingTail)
                    .font(Theme.assistantFont(.callout)).italic()
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(summaryLine)
                    .font(Theme.assistantFont(.callout)).italic()
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption2).foregroundStyle(.quaternary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { inspectItem?(id) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Thinking. \(summaryLine)")
        .help("Show the full thought in the inspector")
    }

    private var summaryLine: String {
        let firstLine = text.split(separator: "\n", omittingEmptySubsequences: true)
            .first.map(String.init) ?? text
        return "Thought — " + String(firstLine.prefix(120))
    }
}
```

`App/TimelineItemViews.swift` — in `TimelineItemView.body`'s switch, add before `case .permission`:

```swift
        case .thinking(let id, let text, let isStreaming):
            ThinkingItemView(id: id, text: text, isStreaming: isStreaming)
```

`App/InspectorView.swift` — in `InspectorPanel.content(for:)`, add a case before `default:`:

```swift
        case .thinking(_, let text, _):
            sectionHeader("Thinking", systemImage: "sparkle")
            Text(text)
                .font(Theme.assistantFont(.callout)).italic()
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
```

`App/ConversationView.swift` — replace the `if session.isThinking { … }` block with:

```swift
                        if session.isThinking {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text(thinkingLabel)
                                    .font(Theme.assistantFont(.callout)).italic()
                                    .foregroundStyle(.secondary)
                                    .contentTransition(.numericText())
                            }
                        }
```

and add the helper alongside `activeModelLabel`:

```swift
    /// Ticker text under the stream: token count when the CLI reports it
    /// (system/thinking_tokens, probe finding 7).
    private var thinkingLabel: String {
        if let tokens = session.thinkingTokens, tokens > 0 {
            return "Thinking… ~\(tokens) tokens"
        }
        return "Thinking…"
    }
```

- [ ] **Step 6: Build the app and smoke**

Run: `swift build && swift test 2>&1 | tail -3` then `xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled -configuration Debug build 2>&1 | tail -2`
Expected: 0 failures; `** BUILD SUCCEEDED **`.
Smoke (coordinator, or fold into the T15 gate): open a live session, send a question — the dimmed thinking tail should appear within a few seconds with the token ticker counting, then collapse to a one-line "Thought — …" row; clicking it opens the inspector with the full text; a historical session with thinking shows the collapsed rows.

- [ ] **Step 7: Commit**

```bash
git -C ~/Developer/Fabled add Sources/FabledCore App Tests/FabledCoreTests
git -C ~/Developer/Fabled commit -m "feat: thinking rendering — timeline case, live tail + ticker, replay, inspector detail (4b T3)"
```

---

## Task 4: Task-tools checklist — TaskItem fold, ChatSession feed, generalized card

TodoWrite is gone from this CLI config (FOLLOWUPS 2026-07-10); the 4a checklist card is correct-but-dormant. This task feeds it from TaskCreate/TaskUpdate/TaskList (finding 9): a pure `TaskChecklist` fold in FabledCore, wired into ChatSession, rendering through a generalized `TodoChecklistView`. The TodoWrite path stays as dormant legacy.

**Files:**
- Create: `Sources/FabledCore/TaskChecklist.swift`
- Modify: `Sources/FabledCore/ChatSession.swift`
- Modify: `App/TodoChecklistView.swift`, `App/ConversationView.swift`
- Test: `Tests/FabledCoreTests/TaskChecklistTests.swift` (create), `Tests/FabledCoreTests/ChatSessionTests.swift`, `Tests/FabledCoreTests/TimelineReplayTests.swift`

- [ ] **Step 1: Write the failing TaskChecklist tests**

Create `Tests/FabledCoreTests/TaskChecklistTests.swift`:

```swift
import XCTest
import ClaudeKit
@testable import FabledCore

final class TaskChecklistTests: XCTestCase {
    private func input(_ json: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    func testCreateAssignsIDFromStructuredResult() throws {
        var checklist = TaskChecklist()
        checklist.noteToolUse(id: "toolu_1", name: "TaskCreate",
                              input: try input(#"{"subject":"Alpha task","description":"d","activeForm":"Alpha running"}"#))
        XCTAssertEqual(checklist.items.count, 1)
        XCTAssertNil(checklist.items[0].taskID, "provisional until the result lands")
        XCTAssertEqual(checklist.items[0].subject, "Alpha task")
        XCTAssertEqual(checklist.items[0].status, .pending)
        checklist.noteResult(ToolResult(
            toolUseID: "toolu_1",
            content: .string("Task #1 created successfully: Alpha task"),
            isError: false,
            toolUseResult: try input(#"{"task":{"id":"1","subject":"Alpha task"}}"#)))
        XCTAssertEqual(checklist.items[0].taskID, "1")
    }

    func testCreateFallsBackToResultTextParsing() throws {
        // tool_use_result is dropped on multi-result lines (T1) — the text
        // "Task #N created successfully: …" still carries the id.
        var checklist = TaskChecklist()
        checklist.noteToolUse(id: "toolu_1", name: "TaskCreate",
                              input: try input(#"{"subject":"Beta task","description":"d"}"#))
        checklist.noteResult(ToolResult(
            toolUseID: "toolu_1",
            content: .string("Task #7 created successfully: Beta task"),
            isError: false))
        XCTAssertEqual(checklist.items[0].taskID, "7")
    }

    func testUpdateAppliesOnMatchingResult() throws {
        var checklist = TaskChecklist()
        checklist.noteToolUse(id: "toolu_1", name: "TaskCreate",
                              input: try input(#"{"subject":"Alpha task","description":"d"}"#))
        checklist.noteResult(ToolResult(
            toolUseID: "toolu_1",
            content: .string("Task #1 created successfully: Alpha task"), isError: false,
            toolUseResult: try input(#"{"task":{"id":"1"}}"#)))
        checklist.noteToolUse(id: "toolu_2", name: "TaskUpdate",
                              input: try input(#"{"taskId":"1","status":"in_progress"}"#))
        // Not yet applied — the CLI hasn't confirmed.
        XCTAssertEqual(checklist.items[0].status, .pending)
        checklist.noteResult(ToolResult(
            toolUseID: "toolu_2", content: .string("Updated task #1 status"), isError: false))
        XCTAssertEqual(checklist.items[0].status, .inProgress)
    }

    func testErroredUpdateDoesNotApply() throws {
        var checklist = TaskChecklist()
        checklist.noteToolUse(id: "toolu_1", name: "TaskCreate",
                              input: try input(#"{"subject":"Alpha task","description":"d"}"#))
        checklist.noteResult(ToolResult(
            toolUseID: "toolu_1",
            content: .string("Task #1 created successfully: Alpha task"), isError: false,
            toolUseResult: try input(#"{"task":{"id":"1"}}"#)))
        checklist.noteToolUse(id: "toolu_2", name: "TaskUpdate",
                              input: try input(#"{"taskId":"1","status":"completed"}"#))
        checklist.noteResult(ToolResult(
            toolUseID: "toolu_2", content: .string("Task not found"), isError: true))
        XCTAssertEqual(checklist.items[0].status, .pending)
    }

    func testDeleteRemovesItem() throws {
        var checklist = TaskChecklist()
        checklist.noteToolUse(id: "toolu_1", name: "TaskCreate",
                              input: try input(#"{"subject":"Gamma task","description":"d"}"#))
        checklist.noteResult(ToolResult(
            toolUseID: "toolu_1",
            content: .string("Task #3 created successfully: Gamma task"), isError: false,
            toolUseResult: try input(#"{"task":{"id":"3"}}"#)))
        checklist.noteToolUse(id: "toolu_2", name: "TaskUpdate",
                              input: try input(#"{"taskId":"3","status":"deleted"}"#))
        checklist.noteResult(ToolResult(
            toolUseID: "toolu_2", content: .string("Updated task #3 deleted"), isError: false))
        XCTAssertTrue(checklist.items.isEmpty)
    }

    func testTaskListResultReconcilesFullState() throws {
        var checklist = TaskChecklist()
        checklist.noteToolUse(id: "toolu_9", name: "TaskList", input: .object([:]))
        checklist.noteResult(ToolResult(
            toolUseID: "toolu_9",
            content: .string("#1 [completed] Alpha task\n#2 [pending] Beta task"),
            isError: false))
        XCTAssertEqual(checklist.items.map(\.taskID), ["1", "2"])
        XCTAssertEqual(checklist.items.map(\.status), [.completed, .pending])
        XCTAssertEqual(checklist.items.map(\.subject), ["Alpha task", "Beta task"])
    }

    func testUnrelatedToolsAreIgnored() throws {
        var checklist = TaskChecklist()
        checklist.noteToolUse(id: "toolu_1", name: "Bash",
                              input: try input(#"{"command":"ls"}"#))
        checklist.noteResult(ToolResult(toolUseID: "toolu_1",
                                        content: .string("x"), isError: false))
        XCTAssertTrue(checklist.items.isEmpty)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter TaskChecklistTests 2>&1 | tail -5`
Expected: compile error — `TaskChecklist` doesn't exist.

- [ ] **Step 3: Implement TaskChecklist**

Create `Sources/FabledCore/TaskChecklist.swift`:

```swift
import ClaudeKit
import Foundation

/// One task-tool entry (probe finding 9). Unlike TodoWrite (whole list
/// re-sent per call) the task tools are incremental — creates, updates,
/// deletes — so the checklist is a fold, not a swap.
public struct TaskItem: Equatable, Sendable, Identifiable {
    /// CLI-assigned id ("1", "2", …); nil while the create is in flight.
    public var taskID: String?
    /// The spawning tool_use id — the fold's correlation key.
    public let toolUseID: String
    public var subject: String
    public var activeForm: String?
    public var status: TodoItem.Status
    public var id: String { toolUseID }
}

/// Pure fold from task-tool traffic to checklist state. ChatSession feeds
/// it tool_use blocks (assistant events) and their results; the update only
/// applies when the CLI confirms (non-error result) — an optimistic apply
/// would show a completed step the CLI rejected.
public struct TaskChecklist: Equatable, Sendable {
    public private(set) var items: [TaskItem] = []
    /// TaskUpdate inputs awaiting their result, keyed by tool_use id.
    private var pendingUpdates: [String: JSONValue] = [:]
    /// TaskCreate tool_use ids awaiting their id-assigning result.
    private var pendingCreates: Set<String> = []
    /// TaskList tool_use ids awaiting their reconciling result.
    private var pendingLists: Set<String> = []

    public init() {}

    public mutating func noteToolUse(id: String, name: String, input: JSONValue) {
        switch name {
        case "TaskCreate":
            guard let subject = input["subject"]?.stringValue else { return }
            items.append(TaskItem(
                taskID: nil, toolUseID: id, subject: subject,
                activeForm: input["activeForm"]?.stringValue, status: .pending))
            pendingCreates.insert(id)
        case "TaskUpdate":
            pendingUpdates[id] = input
        case "TaskList":
            pendingLists.insert(id)
        default:
            break
        }
    }

    public mutating func noteResult(_ result: ToolResult) {
        if pendingCreates.remove(result.toolUseID) != nil {
            applyCreateResult(result)
        } else if let input = pendingUpdates.removeValue(forKey: result.toolUseID) {
            guard !result.isError else { return }
            applyUpdate(input)
        } else if pendingLists.remove(result.toolUseID) != nil {
            guard !result.isError,
                  let text = result.content.stringValue else { return }
            reconcile(fromListText: text)
        }
    }

    private mutating func applyCreateResult(_ result: ToolResult) {
        guard !result.isError,
              let index = items.firstIndex(where: { $0.toolUseID == result.toolUseID })
        else {
            items.removeAll { $0.toolUseID == result.toolUseID && $0.taskID == nil }
            return
        }
        // Structured id when the line carried tool_use_result (T1)…
        if let id = result.toolUseResult?["task"]?["id"]?.stringValue {
            items[index].taskID = id
            return
        }
        // …else parse "Task #N created successfully: …".
        if let text = result.content.stringValue,
           let match = text.firstMatch(of: /Task #(\d+) created/) {
            items[index].taskID = String(match.1)
        }
    }

    private mutating func applyUpdate(_ input: JSONValue) {
        guard let taskID = input["taskId"]?.stringValue,
              let index = items.firstIndex(where: { $0.taskID == taskID })
        else { return }
        if let status = input["status"]?.stringValue {
            switch status {
            case "deleted":
                items.remove(at: index)
                return
            case "completed": items[index].status = .completed
            case "in_progress": items[index].status = .inProgress
            case "pending": items[index].status = .pending
            default: break   // tolerant: unknown status ignored
            }
        }
        if let subject = input["subject"]?.stringValue { items[index].subject = subject }
        if let activeForm = input["activeForm"]?.stringValue {
            items[index].activeForm = activeForm
        }
    }

    /// TaskList output is authoritative full state: "#1 [completed] Alpha task".
    /// Reconciling catches anything the fold missed (e.g. traffic before a
    /// resume seed). Items keep stable identity via taskID when possible.
    private mutating func reconcile(fromListText text: String) {
        var parsed: [TaskItem] = []
        for line in text.split(separator: "\n") {
            guard let match = line.wholeMatch(of: /#(\d+) \[(\w+)\] (.+)/) else { continue }
            let status: TodoItem.Status = switch String(match.2) {
            case "completed": .completed
            case "in_progress": .inProgress
            default: .pending
            }
            let taskID = String(match.1)
            let existing = items.first { $0.taskID == taskID }
            parsed.append(TaskItem(
                taskID: taskID,
                toolUseID: existing?.toolUseID ?? "list-\(taskID)",
                subject: String(match.3),
                activeForm: existing?.activeForm,
                status: status))
        }
        items = parsed
    }
}
```

- [ ] **Step 4: Run the TaskChecklist tests**

Run: `swift test --filter TaskChecklistTests 2>&1 | tail -5`
Expected: 7 tests, 0 failures.

- [ ] **Step 5: Wire into ChatSession (failing tests first)**

Append to `Tests/FabledCoreTests/ChatSessionTests.swift`:

```swift
    func testTaskToolTrafficFeedsSessionTasks() async throws {
        let (session, continuation, _) = makeSession()
        try yield(continuation, #"""
        {"type":"assistant","message":{"role":"assistant","model":"m","content":[{"type":"tool_use","id":"toolu_1","name":"TaskCreate","input":{"subject":"Alpha task","description":"d","activeForm":"Alpha running"}}]},"session_id":"s","uuid":"a1"}
        """#)
        try yield(continuation, #"""
        {"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_1","type":"tool_result","content":"Task #1 created successfully: Alpha task"}]},"session_id":"s","uuid":"u1","tool_use_result":{"task":{"id":"1","subject":"Alpha task"}}}
        """#)
        await waitUntil("task") { !session.sessionTasks.isEmpty }
        XCTAssertEqual(session.sessionTasks[0].taskID, "1")
        XCTAssertEqual(session.sessionTasks[0].subject, "Alpha task")
    }
```

Append to `Tests/FabledCoreTests/TimelineReplayTests.swift`:

```swift
    @MainActor
    func testTasktoolsFixtureFoldsToFinalChecklist() async throws {
        let (connection, continuation, _) = makeFakeConnection()
        let session = ChatSession(
            connection: connection,
            workingDirectory: URL(fileURLWithPath: "/tmp/demo"))
        session.begin()
        for event in try CoreFixtures.events("2026-07-11-tasktools.jsonl") {
            continuation.yield(event)
        }
        // Probe script: Alpha completed, Beta pending, Gamma deleted.
        await waitUntil("fold") { session.sessionTasks.count == 2 }
        XCTAssertEqual(session.sessionTasks.map(\.subject), ["Alpha task", "Beta task"])
        XCTAssertEqual(session.sessionTasks.map(\.status), [.completed, .pending])
    }
```

Run: `swift test --filter "TaskToolTraffic|TasktoolsFixture" 2>&1 | tail -5` — expected: compile error, `sessionTasks` doesn't exist.

`Sources/FabledCore/ChatSession.swift`:

1. Below the `todos` property:

```swift
    /// Task-tool checklist (TaskCreate/TaskUpdate/TaskList) — the live
    /// replacement for TodoWrite on 2.1.206 (probe finding 9). The card
    /// renders whichever of tasks/todos is non-empty, tasks winning.
    public private(set) var taskChecklist = TaskChecklist()
    public var sessionTasks: [TaskItem] { taskChecklist.items }
```

2. In `handle(_:)`, `case .assistant(let message):` — extend the block loop:

```swift
        case .assistant(let message):
            for block in message.content {
                if case .toolUse(let id, let name, let input) = block {
                    taskChecklist.noteToolUse(id: id, name: name, input: input)
                    if name == "TodoWrite" {
                        let parsed = TodoItem.list(from: input)
                        // Deliberate: an empty list never clears (T5 review;
                        // test-pinned).
                        if !parsed.isEmpty { todos = parsed }
                    }
                }
            }
```

(The existing `if case .toolUse(_, "TodoWrite", …)` pattern is replaced by this generalized loop; the TodoWrite semantics — including the empty-list guard — are unchanged and remain covered by the existing tests.)

3. In `handle(_:)`, `case .result` is unrelated; instead extend the toolResult path. The `switch event` currently has no `.toolResult` case (it falls to `default`). Add one:

```swift
        case .toolResult(let results, _):
            for result in results { taskChecklist.noteResult(result) }
```

(Parented results never reach here — the parent-routing guard at the top of `handle` already diverted them, so a subagent's own TaskCreate can't pollute the parent's checklist.)

- [ ] **Step 6: Generalize the card**

`App/TodoChecklistView.swift` — the view currently takes `[TodoItem]`. Give it a display-row vocabulary both sources map into. Replace the view's property and `ForEach` source (keep all collapse/progress logic intact):

```swift
/// One renderable checklist row — TodoItem (legacy TodoWrite) and TaskItem
/// (task tools) both map here.
struct ChecklistRow: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String?
    let status: TodoItem.Status
}

extension TodoItem {
    var checklistRow: ChecklistRow {
        ChecklistRow(id: content, title: content,
                     detail: status == .inProgress ? activeForm : nil,
                     status: status)
    }
}

extension TaskItem {
    var checklistRow: ChecklistRow {
        ChecklistRow(id: id, title: subject,
                     detail: status == .inProgress ? activeForm : nil,
                     status: status)
    }
}
```

The full rewritten view (same collapse/progress behavior, rows instead of todos):

```swift
/// Pinned progress card for the session's checklist (task tools, or legacy
/// TodoWrite). Auto-collapses once every item completes; the header always
/// toggles manually (sticky preference — T10 decision).
struct TodoChecklistView: View {
    let rows: [ChecklistRow]
    /// nil = follow auto behavior (open while work remains).
    @State private var userCollapsed: Bool?

    private var allDone: Bool { rows.allSatisfy { $0.status == .completed } }
    private var isCollapsed: Bool { userCollapsed ?? allDone }
    private var doneCount: Int { rows.count { $0.status == .completed } }
    private var current: ChecklistRow? { rows.first { $0.status == .inProgress } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                userCollapsed = !isCollapsed
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: allDone
                        ? "checklist.checked" : "checklist")
                        .foregroundStyle(allDone ? Color.green : Theme.clay)
                    Text("\(doneCount)/\(rows.count)")
                        .font(.caption.monospacedDigit()).fontWeight(.semibold)
                    if isCollapsed, let current {
                        Text(current.detail ?? current.title)
                            .font(.caption).italic()
                            .foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !isCollapsed {
                // Offset-keyed: legacy TodoItem ids are content strings, which
                // the CLI does not guarantee unique (T3 review note).
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        icon(for: row.status)
                        Text(row.status == .inProgress ? (row.detail ?? row.title) : row.title)
                            .font(.caption)
                            .italic(row.status == .inProgress)
                            .foregroundStyle(row.status == .completed
                                ? Color.secondary : Color.primary)
                            .strikethrough(row.status == .completed,
                                           color: .secondary)
                    }
                }
            }
        }
        .padding(10)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func icon(for status: TodoItem.Status) -> some View {
        switch status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case .inProgress:
            Image(systemName: "arrow.right.circle.fill")
                .font(.caption).foregroundStyle(Theme.clay)
        case .pending:
            Image(systemName: "circle")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
```

(The `ChecklistRow` struct and the two mapping extensions from the snippet above live at the top of this same file.)

`App/ConversationView.swift` — replace the `if !session.todos.isEmpty` block's card construction:

```swift
            let checklistRows = session.sessionTasks.isEmpty
                ? session.todos.map(\.checklistRow)
                : session.sessionTasks.map(\.checklistRow)
            if !checklistRows.isEmpty {
                TodoChecklistView(rows: checklistRows)
                    // Session-scoped identity: RootView reuses this view across
                    // live-session switches (T10 quality review; removed in T15
                    // when the whole hierarchy gets session identity).
                    .id(session.id)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                    .frame(maxWidth: Theme.contentMaxWidth)
            }
```

- [ ] **Step 7: Run everything, build, commit**

Run: `swift build && swift test 2>&1 | tail -3`
Expected: 0 failures (9 new across the task).
Run: `xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled -configuration Debug build 2>&1 | tail -2`
Expected: `** BUILD SUCCEEDED **`

```bash
git -C ~/Developer/Fabled add Sources/FabledCore App Tests/FabledCoreTests
git -C ~/Developer/Fabled commit -m "feat: task-tools checklist — TaskChecklist fold, ChatSession feed, generalized card (4b T4)"
```

---

## Task 5: Design language v1 — Theme tokens + app icon

Ben's directive (digest §6): the app must be *attractive, sexy, mac-assed*, with its own language — NOT LifeSync's Luminous. This task locks the tokens every later task builds with: a palette seeded by the committed harp icon (verdigris bronze / midnight teal / code-glow), a serif-fronted type scale, a 4-pt spacing grid, motion constants, and semantic status colors. It also wires the icon into the app target — the palette's anchor visible in the Dock.

The tokens below are v1-locked for this plan: implementers use them verbatim; Ben adjusts values at the gate, not mid-plan. **After this task, raw color/font/spacing literals in App views are review failures.**

**Files:**
- Modify: `App/Theme.swift` (full rewrite below)
- Create: `App/Assets.xcassets/` (AppIcon from `docs/assets/icon/Fabled.iconset`)
- Modify: `project.yml`
- Modify: `App/WelcomeView.swift` (wordmark only — full rebuild is T9)

- [ ] **Step 1: Build the asset catalog**

```bash
cd ~/Developer/Fabled
mkdir -p App/Assets.xcassets/AppIcon.appiconset
cp docs/assets/icon/Fabled.iconset/*.png App/Assets.xcassets/AppIcon.appiconset/
cat > App/Assets.xcassets/Contents.json <<'EOF'
{
  "info" : { "author" : "xcode", "version" : 1 }
}
EOF
cat > App/Assets.xcassets/AppIcon.appiconset/Contents.json <<'EOF'
{
  "images" : [
    { "filename" : "icon_16x16.png",      "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png",   "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png",      "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png",   "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png",    "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png",    "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png",    "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
EOF
```

- [ ] **Step 2: Wire it in project.yml**

In `project.yml`, under `targets: Fabled: settings: base:`, add:

```yaml
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
```

(`sources: - App` already sweeps the directory, so the new `App/Assets.xcassets` is picked up by XcodeGen automatically — only the setting is needed.)

- [ ] **Step 3: Replace Theme.swift**

Full new contents of `App/Theme.swift`:

```swift
import SwiftUI
import AppKit

/// Fabled design tokens, v1 (2026-07-11). The language is Fabled's own —
/// seeded by the harp icon's palette (aged bronze, midnight teal, code-glow)
/// over native macOS structure, with Claude's serif warmth in conversation.
/// Rules: App views take every color, font, spacing, radius, and animation
/// from here. A raw literal in a view is a review failure.
enum Theme {
    // MARK: - Palette

    /// Claude clay (#D97757) — send button, working state, warm accents.
    static let clay = Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255)
    /// Aged harp bronze (#B08D57) — brand chrome: wordmark, selected chips.
    static let bronze = Color(red: 0xB0 / 255, green: 0x8D / 255, blue: 0x57 / 255)
    /// Midnight teal (#12333B) — the icon's field; welcome backdrop in dark.
    static let midnightTeal = Color(red: 0x12 / 255, green: 0x33 / 255, blue: 0x3B / 255)
    /// Code-glow (#69D2B4) — the strings' phosphor; sparing highlights only.
    static let glow = Color(red: 0x69 / 255, green: 0xD2 / 255, blue: 0xB4 / 255)

    /// Light/dark-adaptive color without an asset catalog entry.
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    /// Welcome backdrop: whisper of teal in dark, warm paper in light.
    static let welcomeBackdrop = dynamic(
        light: NSColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1),
        dark: NSColor(red: 0.07, green: 0.13, blue: 0.15, alpha: 1))

    // MARK: - Status (color + shape + words, never color alone — feature 14)

    /// Needs input — unmissable orange. Icon: exclamationmark.bubble.fill.
    static let statusNeedsInput = Color(red: 0xE0 / 255, green: 0x8A / 255, blue: 0x3C / 255)
    /// Working — clay. Icon: circle.dotted (animated).
    static let statusWorking = clay
    /// Idle-with-history / ready for review — calm blue. Icon: tray.full.
    static let statusReady = Color(red: 0x4E / 255, green: 0x8F / 255, blue: 0xD1 / 255)
    /// Ended / archived — neutral. Icon: moon.zzz.
    static let statusEnded = Color.secondary

    // MARK: - Type

    /// Claude's voice is serif; chrome stays SF Pro.
    static func assistantFont(_ style: Font.TextStyle = .body) -> Font {
        .system(style, design: .serif)
    }
    /// Wordmark / welcome hero.
    static let display = Font.system(.largeTitle, design: .serif).weight(.semibold)
    /// Section headings on the welcome surface.
    static let heading = Font.system(.title3, design: .serif).weight(.medium)

    // MARK: - Layout

    /// Conversation column cap (Plan 4a T12).
    static let contentMaxWidth: CGFloat = 820
    /// 4-pt spacing grid.
    static let spaceXS: CGFloat = 4
    static let spaceS: CGFloat = 8
    static let spaceM: CGFloat = 12
    static let spaceL: CGFloat = 16
    static let spaceXL: CGFloat = 24
    /// Corner radii: rows/cards vs panels/sheets.
    static let radiusCard: CGFloat = 8
    static let radiusPanel: CGFloat = 12

    // MARK: - Motion

    /// Row/card state changes (selection, chips appearing).
    static let snap = Animation.snappy(duration: 0.18)
    /// Larger settles (cards expanding, welcome sections).
    static let settle = Animation.smooth(duration: 0.25)
}
```

- [ ] **Step 4: Wordmark preview on the current welcome screen**

Minimal token adoption only — T9 rebuilds this view. In `App/WelcomeView.swift`, replace the `Text("Fabled").font(.system(.largeTitle, design: .serif))` line with:

```swift
            Text("Fabled")
                .font(Theme.display)
                .foregroundStyle(Theme.bronze)
```

- [ ] **Step 5: Regenerate, build, verify the icon**

Run: `xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled -configuration Debug build 2>&1 | tail -2`
Expected: `** BUILD SUCCEEDED **`
Then verify the compiled app actually carries the icon:

```bash
ICON=$(find ~/Library/Developer/Xcode/DerivedData -path "*Fabled*" -name "Assets.car" -newerct '-5 minutes' | head -1)
test -n "$ICON" && echo "asset catalog compiled in" || echo "MISSING — check ASSETCATALOG_COMPILER_APPICON_NAME"
```

Launch the app once (`open` the newest DerivedData Fabled.app) — the bronze harp should appear in the Dock. `swift test` is unaffected (app-target-only change) but run it anyway: `swift test 2>&1 | tail -3`.

- [ ] **Step 6: Commit**

```bash
git -C ~/Developer/Fabled add App/Theme.swift App/Assets.xcassets App/WelcomeView.swift project.yml
git -C ~/Developer/Fabled commit -m "feat(app): design tokens v1 + app icon wired — bronze/teal/glow palette, type scale, spacing, motion (4b T5)"
```

---

## Task 6: Liveness + control-op ack correlation + status badge

Three signal fixes in one layer: (a) a working session with no wire events for N seconds says so instead of sitting silent (gate feedback, feature 11 — there is no wire heartbeat, liveness is client-timed per 4a probe finding 8); (b) `set_model`/`set_permission_mode` acks are correlated so a rejected control op can't leave a stale toolbar label (FOLLOWUPS: optimistic control ops; error shape probe finding 11); (c) a shared `SessionStatusBadge` — shape + color + word, never color alone (feature 14) — that T7/T9 reuse.

**Files:**
- Modify: `Sources/FabledCore/AgentConnection.swift` (control ops return request id)
- Modify: `Sources/FabledCore/ChatSession.swift`
- Modify: `Sources/FabledCore/InteractionModels.swift` (gate summary lines — T7 and T9 consume them)
- Create: `App/StatusBadge.swift`
- Modify: `App/ConversationView.swift` (liveness row)
- Test: `Tests/FabledCoreTests/ChatSessionTests.swift`, `Tests/FabledCoreTests/InteractionModelTests.swift`, `Tests/FabledCoreTests/Support.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/FabledCoreTests/InteractionModelTests.swift` (the summary lines ship here because T7's sidebar rows — the next task — already need them):

```swift
    // MARK: - Gate summary lines (4b T6; consumed by sidebar rows + welcome inbox)

    private func permissionRequest(_ json: String) throws -> PermissionRequest {
        let event = try AgentEventDecoder.decode(Data(json.utf8))
        guard case .controlRequest(let request) = event,
              let permission = PermissionRequest(request) else {
            fatalError("fixture shape drifted")
        }
        return permission
    }

    func testPermissionGateSummaryLine() throws {
        let request = try permissionRequest(#"""
        {"type":"control_request","request_id":"p1","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"rm -rf build"}}}
        """#)
        XCTAssertEqual(InteractionGate.permission(request).summaryLine,
                       "Approve: rm -rf build")
    }

    func testQuestionGateSummaryLine() throws {
        let request = try permissionRequest(#"""
        {"type":"control_request","request_id":"q1","request":{"subtype":"can_use_tool","tool_name":"AskUserQuestion","requires_user_interaction":true,"input":{"questions":[{"question":"Ship size?","header":"Size","options":[{"label":"S","description":""},{"label":"L","description":""}],"multiSelect":false}]}}}
        """#)
        let prompt = QuestionPrompt(request)!
        XCTAssertEqual(InteractionGate.question(prompt).summaryLine, "Ship size?")
    }

    func testPlanGateSummaryLine() throws {
        let request = try permissionRequest(#"""
        {"type":"control_request","request_id":"e1","request":{"subtype":"can_use_tool","tool_name":"ExitPlanMode","requires_user_interaction":true,"input":{"plan":"# Build the thing\n- step"}}}
        """#)
        let approval = PlanApproval(request)!
        XCTAssertEqual(InteractionGate.planApproval(approval).summaryLine,
                       "Plan ready for review")
    }
```

Append to `Tests/FabledCoreTests/ChatSessionTests.swift`:

```swift
    func testRejectedSetModelRevertsAndNotices() async throws {
        let (session, continuation, recorder) = makeSession()
        // Session knows its model (catalog default path).
        try yield(continuation, #"""
        {"type":"control_response","response":{"subtype":"success","request_id":"init","response":{"commands":[],"models":[{"value":"default","resolvedModel":"claude-opus-4-8","displayName":"Default"}]}}}
        """#)
        await waitUntil("ready") { session.isReady }
        XCTAssertEqual(session.currentModel, "claude-opus-4-8")
        session.setModel("totally-bogus-model-9000")
        XCTAssertEqual(session.currentModel, "totally-bogus-model-9000",
                       "optimistic until the ack")
        let entries = await waitForEntries(recorder, count: 1)
        guard case .setModel(_, let requestID) = entries.first else {
            return XCTFail("expected setModel, got \(entries)")
        }
        // Error ack with the recorded request id (badmodel fixture shape).
        try yield(continuation, #"""
        {"type":"control_response","response":{"subtype":"error","request_id":"\#(requestID)","error":"Model \"totally-bogus-model-9000\" is not a recognized model id."}}
        """#)
        await waitUntil("revert") { session.currentModel == "claude-opus-4-8" }
        XCTAssertTrue(session.timeline.contains {
            if case .notice(_, let text) = $0 { return text.contains("not a recognized") }
            return false
        }, "the rejection reason surfaces as a notice")
    }

    func testRejectedSetPermissionModeReverts() async throws {
        let (session, continuation, recorder) = makeSession()
        session.setPermissionMode("plan")
        XCTAssertEqual(session.permissionMode, "plan")
        let entries = await waitForEntries(recorder, count: 1)
        guard case .setPermissionMode(_, let requestID) = entries.first else {
            return XCTFail("expected setPermissionMode, got \(entries)")
        }
        try yield(continuation, #"""
        {"type":"control_response","response":{"subtype":"error","request_id":"\#(requestID)","error":"nope"}}
        """#)
        await waitUntil("revert") { session.permissionMode == "default" }
    }

    func testSuccessAckKeepsOptimisticValue() async throws {
        let (session, continuation, recorder) = makeSession()
        session.setModel("haiku")
        let entries = await waitForEntries(recorder, count: 1)
        guard case .setModel(_, let requestID) = entries.first else {
            return XCTFail("expected setModel, got \(entries)")
        }
        try yield(continuation, #"""
        {"type":"control_response","response":{"subtype":"success","request_id":"\#(requestID)","response":{}}}
        """#)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(session.currentModel, "haiku")
    }

    func testLastEventAtTracksWireActivity() async throws {
        let (session, continuation, _) = makeSession()
        XCTAssertNil(session.lastEventAt)
        try yield(continuation, #"""
        {"type":"system","subtype":"status","status":"requesting","uuid":"s1","session_id":"s"}
        """#)
        await waitUntil("stamp") { session.lastEventAt != nil }
    }
```

- [ ] **Step 2: Update the test support for the new connection signatures**

In `Tests/FabledCoreTests/Support.swift`, the recorder entries for control ops now carry the request id the connection returned. Replace the two `Entry` cases and the two closures:

```swift
        case setModel(String, requestID: String)
        case setPermissionMode(String, requestID: String)
```

and in `makeFakeConnection()`:

```swift
        setModel: { model in
            let id = "req-\(UUID().uuidString.prefix(8))"
            await recorder.record(.setModel(model, requestID: id))
            return id
        },
        setPermissionMode: { mode in
            let id = "req-\(UUID().uuidString.prefix(8))"
            await recorder.record(.setPermissionMode(mode, requestID: id))
            return id
        },
```

(Any existing test that pattern-matches `.setModel("x")` gains a wildcard: `.setModel("x", _)`. `ChatSessionLiveTests`' connection stubs update the same way.)

Race insurance for all three ack tests: between `waitForEntries` returning and yielding the ack envelope, insert `try await Task.sleep(for: .milliseconds(20))` — the revert registration hops through the sending Task's MainActor resume, and the ack must not be handled before it lands.

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --filter "RejectedSet|SuccessAckKeeps|LastEventAt|GateSummaryLine" 2>&1 | tail -10`
Expected: compile errors (`lastEventAt`, `summaryLine`, connection signature mismatch).

- [ ] **Step 4: Implement**

`Sources/FabledCore/InteractionModels.swift` — append:

```swift
public extension InteractionGate {
    /// One line for inbox/sidebar rows: what is the agent waiting on?
    /// (CD welcome pattern — digest §1.)
    var summaryLine: String {
        switch self {
        case .permission(let request):
            return "Approve: " + PermissionPrompt.commandSummary(for: request)
        case .question(let prompt):
            return prompt.questions.first?.text ?? "Question waiting"
        case .planApproval:
            return "Plan ready for review"
        }
    }
}
```

`Sources/FabledCore/AgentConnection.swift` — the two control ops now return the CLI request id they were sent under (AgentSession already returns it; the fake in tests fabricates one):

```swift
    public var setModel: @Sendable (String) async -> String
    public var setPermissionMode: @Sendable (String) async -> String
```

(update `init` parameter types to match), and in `live(_:)`:

```swift
            setModel: { await session.setModel($0) },
            setPermissionMode: { await session.setPermissionMode($0) },
```

`Sources/FabledCore/ChatSession.swift`:

1. New state, below `isReady`:

```swift
    /// Wall-clock of the last wire event — liveness is client-timed, there
    /// is no heartbeat during tool execution (4a probe finding 8).
    public private(set) var lastEventAt: Date?
    /// In-flight optimistic control ops: request id → revert closure.
    /// A rejected op runs its revert so the toolbar can't hold a stale label
    /// (FOLLOWUPS: optimistic control ops).
    private var pendingControlReverts: [String: () -> Void] = [:]
```

2. Replace `setModel`/`setPermissionMode`:

```swift
    public func setModel(_ value: String) {
        let previous = currentModel
        let previousChosen = modelExplicitlyChosen
        currentModel = value
        modelExplicitlyChosen = true
        Task {
            let requestID = await connection.setModel(value)
            registerRevert(requestID) { [weak self] in
                self?.currentModel = previous
                self?.modelExplicitlyChosen = previousChosen
            }
        }
    }

    public func setPermissionMode(_ mode: String) {
        let previous = permissionMode
        permissionMode = mode
        Task {
            let requestID = await connection.setPermissionMode(mode)
            registerRevert(requestID) { [weak self] in
                self?.permissionMode = previous
            }
        }
    }

    private func registerRevert(_ requestID: String, _ revert: @escaping () -> Void) {
        pendingControlReverts[requestID] = revert
    }
```

3. In `handle(_:)`, first line of the method body (before the parent-routing guard):

```swift
        lastEventAt = Date()
```

4. Add a `controlResponse` branch for non-initialize envelopes — extend the existing `case .controlResponse` (currently a `where`-guarded initialize match) by adding a second case below it:

```swift
        case .controlResponse(let envelope):
            if let revert = pendingControlReverts.removeValue(forKey: envelope.requestID) {
                if envelope.subtype == "error" {
                    revert()
                    let reason = envelope.errorMessage ?? "The CLI rejected the change."
                    timeline = timeline + [.notice(
                        id: "control-error-\(envelope.requestID)", text: reason)]
                }
            }
```

(Order matters: the initialize-matching `case … where` stays FIRST; this general case catches everything else. Success acks simply clear the revert entry.)

- [ ] **Step 5: The status badge component**

Create `App/StatusBadge.swift`:

```swift
import SwiftUI
import FabledCore

/// Session state as shape + color + word (feature 14: never color alone).
/// Compact (icon only, sidebar rows) or labeled (welcome inbox chips).
struct SessionStatusBadge: View {
    let state: ChatSession.ActivityState
    var labeled = false

    var body: some View {
        if labeled {
            Label(word, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .padding(.horizontal, Theme.spaceS)
                .padding(.vertical, 2)
                .background(color.opacity(0.14), in: Capsule())
                .accessibilityLabel(word)
        } else {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(color)
                .symbolEffect(.pulse, options: .repeating,
                              isActive: state == .needsApproval)
                .help(word)
                .accessibilityLabel(word)
        }
    }

    private var word: String {
        switch state {
        case .needsApproval: "Needs input"
        case .working: "Working"
        case .idle: "Ready"
        case .ended: "Ended"
        }
    }
    private var symbol: String {
        switch state {
        case .needsApproval: "exclamationmark.bubble.fill"
        case .working: "circle.dotted.circle"
        case .idle: "checkmark.circle"
        case .ended: "moon.zzz"
        }
    }
    private var color: Color {
        switch state {
        case .needsApproval: Theme.statusNeedsInput
        case .working: Theme.statusWorking
        case .idle: Theme.statusReady
        case .ended: Theme.statusEnded
        }
    }
}
```

- [ ] **Step 6: The liveness row**

`App/ConversationView.swift` — replace the `if session.isThinking { … }` block (from T3) with a combined stream-status row that also covers silent stretches:

```swift
                        if session.isWorking {
                            StreamStatusRow(session: session)
                        }
```

and add at the bottom of the file:

```swift
/// Under-stream status line: thinking ticker while deltas flow, and a
/// client-timed liveness note when the wire goes quiet mid-turn (there is
/// no heartbeat during tool execution — 4a probe finding 8; the opus-outage
/// gate feedback is why silence must be labeled).
private struct StreamStatusRow: View {
    let session: ChatSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(label(now: context.date))
                    .font(Theme.assistantFont(.callout)).italic()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
    }

    private func label(now: Date) -> String {
        if session.isThinking {
            if let tokens = session.thinkingTokens, tokens > 0 {
                return "Thinking… ~\(tokens) tokens"
            }
            return "Thinking…"
        }
        if let last = session.lastEventAt {
            let quiet = Int(now.timeIntervalSince(last))
            if quiet >= 20 {
                return "Still working — no response for \(quiet)s…"
            }
        }
        return "Working…"
    }
}
```

(T3's `thinkingLabel` helper and its `if session.isThinking` block are subsumed — delete them.)

- [ ] **Step 7: Run everything, build, commit**

Run: `swift build && swift test 2>&1 | tail -3` — 0 failures (4 new; existing setModel-pattern tests updated).
Run: `xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled -configuration Debug build 2>&1 | tail -2` — `** BUILD SUCCEEDED **`

```bash
git -C ~/Developer/Fabled add Sources/FabledCore App Tests/FabledCoreTests
git -C ~/Developer/Fabled commit -m "feat: liveness row, control-op ack correlation with revert, SessionStatusBadge (4b T6)"
```

---

## Task 7: Sidebar status signalling

Feature 14's sidebar half: the 8 px clay-vs-red dots become `SessionStatusBadge` shapes with tooltips, approvals pulse, and a session needing input is visually loud even when unselected. Small task — the component exists; this is placement.

**Files:**
- Modify: `App/SidebarView.swift`

- [ ] **Step 1: Replace the dot with the badge**

In `SidebarView.liveSection`, replace the `Circle().fill(dotColor(…))` row prefix:

```swift
                    HStack(spacing: Theme.spaceS) {
                        SessionStatusBadge(state: session.activityState)
                        VStack(alignment: .leading) {
                            Text(session.title).lineLimit(1)
                                .fontWeight(session.activityState == .needsApproval
                                    ? .semibold : .regular)
                            Text(statusLine(for: session))
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .listRowBackground(
                        session.activityState == .needsApproval
                            ? Theme.statusNeedsInput.opacity(0.10) : nil)
```

Add the helper and delete `dotColor(_:)`:

```swift
    /// Second line: what the session is waiting on beats where it lives.
    private func statusLine(for session: ChatSession) -> String {
        if let gate = session.pendingGate { return gate.summaryLine }
        return session.workingDirectory.lastPathComponent
    }
```

(`InteractionGate.summaryLine` landed in Task 6.)

- [ ] **Step 2: Build + smoke**

Run: `xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled -configuration Debug build 2>&1 | tail -2` — `** BUILD SUCCEEDED **`
Smoke: two live sessions, one with a pending permission — its row shows the pulsing orange bubble, semibold title, tinted row, and the gate summary as its second line; hovering any badge names the state in words.

- [ ] **Step 3: Commit**

```bash
git -C ~/Developer/Fabled add App/SidebarView.swift
git -C ~/Developer/Fabled commit -m "feat(app): sidebar rows use SessionStatusBadge — shape+word+pulse, gate summary line (4b T7)"
```

---

## Task 8: Sidebar organization — group/sort/filter/pin

Feature 18 via the CD funnel pattern (digest §1): one toolbar button opens a popover with Group by (Project ✓ / Date / None), Sort (Recency ✓ / Name), Last activity (All ✓ / 1d / 3d / 7d / 30d), plus row-level Pin/Unpin. Pure logic in FabledCore (`SidebarOrganizer`), persisted in UserDefaults, tested offline. This is also the treatment for probe-scratchpad/worktree project noise (finding 14): a 7-day activity window hides dead junk projects.

**Files:**
- Create: `Sources/FabledCore/SidebarOrganizer.swift`
- Modify: `Sources/FabledCore/AppModel.swift`
- Modify: `App/SidebarView.swift`
- Test: `Tests/FabledCoreTests/SidebarOrganizerTests.swift` (create), `Tests/FabledCoreTests/AppModelTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/FabledCoreTests/SidebarOrganizerTests.swift`:

```swift
import XCTest
import ClaudeKit
@testable import FabledCore

final class SidebarOrganizerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func summary(_ id: String, project: String, daysAgo: Double,
                         title: String? = nil) -> SessionSummary {
        let projectFolder = ProjectFolder(
            flattenedName: "-tmp-\(project)", originalPath: "/tmp/\(project)",
            directoryURL: URL(fileURLWithPath: "/tmp/\(project)"))
        return SessionSummary(
            id: id, project: projectFolder,
            fileURL: URL(fileURLWithPath: "/tmp/\(project)/\(id).jsonl"),
            title: title ?? id,
            lastActivity: now.addingTimeInterval(-daysAgo * 86_400),
            approximateSizeBytes: 1)
    }

    func testGroupByProjectPreservesNewestFirstProjectOrder() {
        let sections = SidebarOrganizer.organize(
            [summary("a", project: "one", daysAgo: 2),
             summary("b", project: "two", daysAgo: 0.5),
             summary("c", project: "one", daysAgo: 1)],
            options: SidebarOptions(), now: now)
        XCTAssertEqual(sections.map(\.title), ["two", "one"])
        XCTAssertEqual(sections[1].sessions.map(\.id), ["c", "a"],
                       "recency within the group")
    }

    func testGroupByDateBucketsTodayYesterdayOlder() {
        var options = SidebarOptions()
        options.groupBy = .date
        let sections = SidebarOrganizer.organize(
            [summary("today", project: "p", daysAgo: 0.01),
             summary("yesterday", project: "p", daysAgo: 1.0),
             summary("old", project: "p", daysAgo: 9)],
            options: options, now: now)
        XCTAssertEqual(sections.map(\.title), ["Today", "Yesterday", "Earlier"])
    }

    func testActivityWindowFiltersStaleSessions() {
        var options = SidebarOptions()
        options.activityWindow = .days(7)
        let sections = SidebarOrganizer.organize(
            [summary("fresh", project: "p", daysAgo: 2),
             summary("stale", project: "junk-probe", daysAgo: 30)],
            options: options, now: now)
        XCTAssertEqual(sections.flatMap(\.sessions).map(\.id), ["fresh"],
                       "probe/worktree junk ages out (finding 14)")
    }

    func testSortByNameIsCaseInsensitive() {
        var options = SidebarOptions()
        options.groupBy = .none
        options.sortBy = .name
        let sections = SidebarOrganizer.organize(
            [summary("1", project: "p", daysAgo: 0, title: "beta"),
             summary("2", project: "p", daysAgo: 1, title: "Alpha")],
            options: options, now: now)
        XCTAssertEqual(sections.flatMap(\.sessions).map(\.title), ["Alpha", "beta"])
    }

    func testPinnedSessionsFloatIntoLeadingSection() {
        var options = SidebarOptions()
        options.pinnedSessionIDs = ["c"]
        let sections = SidebarOrganizer.organize(
            [summary("a", project: "one", daysAgo: 2),
             summary("c", project: "two", daysAgo: 5)],
            options: options, now: now)
        XCTAssertEqual(sections.first?.title, "Pinned")
        XCTAssertEqual(sections.first?.sessions.map(\.id), ["c"])
        XCTAssertEqual(sections.dropFirst().flatMap(\.sessions).map(\.id), ["a"],
                       "pinned sessions leave their home group and dodge the window filter")
    }

    func testOptionsRoundTripThroughJSON() throws {
        var options = SidebarOptions()
        options.groupBy = .date
        options.sortBy = .name
        options.activityWindow = .days(30)
        options.pinnedSessionIDs = ["x", "y"]
        let data = try JSONEncoder().encode(options)
        let decoded = try JSONDecoder().decode(SidebarOptions.self, from: data)
        XCTAssertEqual(decoded, options)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter SidebarOrganizerTests 2>&1 | tail -5`
Expected: compile error — `SidebarOrganizer` doesn't exist.

- [ ] **Step 3: Implement**

Create `Sources/FabledCore/SidebarOrganizer.swift`:

```swift
import ClaudeKit
import Foundation

/// User-tunable sidebar organization (feature 18, CD funnel pattern).
/// Persisted as JSON in UserDefaults by AppModel.
public struct SidebarOptions: Codable, Equatable, Sendable {
    public enum GroupBy: String, Codable, CaseIterable, Sendable {
        case project, date, none
    }
    public enum SortBy: String, Codable, CaseIterable, Sendable {
        case recency, name
    }
    public enum ActivityWindow: Codable, Equatable, Sendable {
        case all
        case days(Int)

        public var days: Int? {
            if case .days(let value) = self { return value }
            return nil
        }
        /// Menu presets, CD parity: All / 1d / 3d / 7d / 30d.
        public static let presets: [ActivityWindow] =
            [.all, .days(1), .days(3), .days(7), .days(30)]
        public var label: String {
            switch self {
            case .all: "All time"
            case .days(1): "Last day"
            case .days(let n): "Last \(n) days"
            }
        }
    }

    public var groupBy: GroupBy = .project
    public var sortBy: SortBy = .recency
    public var activityWindow: ActivityWindow = .all
    public var pinnedSessionIDs: Set<String> = []

    public init() {}
}

/// One rendered sidebar section.
public struct SidebarSection: Identifiable, Sendable, Equatable {
    public let title: String
    public var sessions: [SessionSummary]
    public var id: String { title }
}

public enum SidebarOrganizer {
    /// Pure: summaries (already newest-first from the index) + options → sections.
    /// Pinned sessions float to a leading section and bypass the window filter
    /// (a pin means "I care", staleness notwithstanding).
    public static func organize(
        _ summaries: [SessionSummary], options: SidebarOptions, now: Date
    ) -> [SidebarSection] {
        var pinned: [SessionSummary] = []
        var rest: [SessionSummary] = []
        for summary in summaries {
            if options.pinnedSessionIDs.contains(summary.id) {
                pinned.append(summary)
            } else if let days = options.activityWindow.days {
                if summary.lastActivity >= now.addingTimeInterval(-Double(days) * 86_400) {
                    rest.append(summary)
                }
            } else {
                rest.append(summary)
            }
        }
        rest = sorted(rest, by: options.sortBy)
        pinned = sorted(pinned, by: options.sortBy)

        var sections: [SidebarSection] = []
        if !pinned.isEmpty {
            sections.append(SidebarSection(title: "Pinned", sessions: pinned))
        }
        switch options.groupBy {
        case .none:
            if !rest.isEmpty {
                sections.append(SidebarSection(title: "Sessions", sessions: rest))
            }
        case .project:
            var order: [String] = []
            var groups: [String: [SessionSummary]] = [:]
            for summary in rest {
                let key = summary.project.displayName
                if groups[key] == nil { order.append(key) }
                groups[key, default: []].append(summary)
            }
            sections += order.map { SidebarSection(title: $0, sessions: groups[$0]!) }
        case .date:
            let calendar = Calendar.current
            var buckets: [(String, [SessionSummary])] =
                [("Today", []), ("Yesterday", []), ("This week", []), ("Earlier", [])]
            for summary in rest {
                let bucket: Int
                if calendar.isDate(summary.lastActivity, inSameDayAs: now) {
                    bucket = 0
                } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
                          calendar.isDate(summary.lastActivity, inSameDayAs: yesterday) {
                    bucket = 1
                } else if summary.lastActivity >= now.addingTimeInterval(-7 * 86_400) {
                    bucket = 2
                } else {
                    bucket = 3
                }
                buckets[bucket].1.append(summary)
            }
            sections += buckets.compactMap { title, sessions in
                sessions.isEmpty ? nil : SidebarSection(title: title, sessions: sessions)
            }
        }
        return sections
    }

    private static func sorted(
        _ summaries: [SessionSummary], by sort: SidebarOptions.SortBy
    ) -> [SessionSummary] {
        switch sort {
        case .recency:
            summaries.sorted { $0.lastActivity > $1.lastActivity }
        case .name:
            summaries.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }
    }
}
```

`SidebarOptions.ActivityWindow` needs explicit Codable (enum with payload): add inside `ActivityWindow`:

```swift
        private enum CodingKeys: String, CodingKey { case kind, days }
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(String.self, forKey: .kind) {
            case "days":
                self = .days(try container.decode(Int.self, forKey: .days))
            default:
                self = .all
            }
        }
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .all:
                try container.encode("all", forKey: .kind)
            case .days(let n):
                try container.encode("days", forKey: .kind)
                try container.encode(n, forKey: .days)
            }
        }
```

- [ ] **Step 4: Run the organizer tests**

Run: `swift test --filter SidebarOrganizerTests 2>&1 | tail -5`
Expected: 6 tests, 0 failures.

- [ ] **Step 5: AppModel wiring (failing test first)**

Append to `Tests/FabledCoreTests/AppModelTests.swift` (follow the file's existing construction pattern for a temp-database AppModel):

```swift
    @MainActor
    func testSidebarOptionsPersistAcrossModels() async throws {
        let defaults = UserDefaults(suiteName: "4b-t8-\(UUID().uuidString)")!
        let first = try makeModel(defaults: defaults)   // adapt to the file's helper
        first.sidebarOptions.groupBy = .date
        first.sidebarOptions.pinnedSessionIDs.insert("s-1")
        let second = try makeModel(defaults: defaults)
        XCTAssertEqual(second.sidebarOptions.groupBy, .date)
        XCTAssertTrue(second.sidebarOptions.pinnedSessionIDs.contains("s-1"))
    }
```

`Sources/FabledCore/AppModel.swift`:

1. `init` gains a defaults parameter (existing callers unchanged): `public init(store: SessionStore = SessionStore(), databaseURL: URL? = nil, defaults: UserDefaults = .standard) throws` — store it: `private let defaults: UserDefaults`.
2. Options property:

```swift
    /// Sidebar organization (feature 18). Persisted as JSON.
    public var sidebarOptions = SidebarOptions() {
        didSet {
            guard sidebarOptions != oldValue else { return }
            if let data = try? JSONEncoder().encode(sidebarOptions) {
                defaults.set(data, forKey: Self.sidebarOptionsKey)
            }
        }
    }
    private static let sidebarOptionsKey = "sidebarOptions"
```

and in `init`, after storing `defaults`:

```swift
        if let data = defaults.data(forKey: Self.sidebarOptionsKey),
           let options = try? JSONDecoder().decode(SidebarOptions.self, from: data) {
            self.sidebarOptions = options
        }
```

(move the `preferredEffort` UserDefaults reads from T2 onto the injected `defaults` too, same pattern).
3. New derived history: keep `history: [ProjectHistory]` for welcome/recents, and add:

```swift
    /// Sidebar sections under the user's organization options.
    public var sidebarSections: [SidebarSection] {
        SidebarOrganizer.organize(allSummaries, options: sidebarOptions, now: Date())
    }
    private var allSummaries: [SessionSummary] = []
```

In `refreshHistory()`, first line after the `guard`: `allSummaries = summaries`.
4. Pin toggle:

```swift
    public func togglePin(_ sessionID: String) {
        if sidebarOptions.pinnedSessionIDs.contains(sessionID) {
            sidebarOptions.pinnedSessionIDs.remove(sessionID)
        } else {
            sidebarOptions.pinnedSessionIDs.insert(sessionID)
        }
    }
```

- [ ] **Step 6: Sidebar UI**

`App/SidebarView.swift`:

1. Replace `historySections` to iterate `app.sidebarSections` (same row content, section titles from the organizer, keep the 10-row cap + "more — use search" line per section), and add a context menu to each historical row:

```swift
                    .contextMenu {
                        Button(app.sidebarOptions.pinnedSessionIDs.contains(summary.id)
                            ? "Unpin" : "Pin") { app.togglePin(summary.id) }
                        Button("Continue Session") {
                            Task { await app.resume(summary, fork: false) }
                        }
                        Button("Fork Session") {
                            Task { await app.resume(summary, fork: true) }
                        }
                    }
```

2. Add the funnel to the List via `.toolbar`:

```swift
        .toolbar {
            ToolbarItem {
                Menu {
                    Picker("Group by", selection: $app.sidebarOptions.groupBy) {
                        Text("Project").tag(SidebarOptions.GroupBy.project)
                        Text("Date").tag(SidebarOptions.GroupBy.date)
                        Text("None").tag(SidebarOptions.GroupBy.none)
                    }
                    Picker("Sort by", selection: $app.sidebarOptions.sortBy) {
                        Text("Recency").tag(SidebarOptions.SortBy.recency)
                        Text("Name").tag(SidebarOptions.SortBy.name)
                    }
                    Picker("Last activity", selection: Binding(
                        get: { app.sidebarOptions.activityWindow.days ?? 0 },
                        set: { app.sidebarOptions.activityWindow = $0 == 0 ? .all : .days($0) }
                    )) {
                        ForEach(SidebarOptions.ActivityWindow.presets, id: \.label) { preset in
                            Text(preset.label).tag(preset.days ?? 0)
                        }
                    }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
                .help("Group, sort, and filter sessions")
            }
        }
```

- [ ] **Step 7: Run everything, build, commit**

Run: `swift build && swift test 2>&1 | tail -3` — 0 failures (7 new).
Run: `xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled -configuration Debug build 2>&1 | tail -2` — `** BUILD SUCCEEDED **`
Smoke: funnel menu changes grouping live; a 7-day window hides the probe-scratch projects; pin floats a session to the top; options survive relaunch.

```bash
git -C ~/Developer/Fabled add Sources/FabledCore App Tests/FabledCoreTests
git -C ~/Developer/Fabled commit -m "feat: sidebar organization — group/sort/activity filter/pinning with persistence (4b T8)"
```

---

## Task 9: Welcome attention inbox

Feature 13 per the digest: the home surface is an **attention inbox, not a launcher** — sessions needing input sort to the top with a preview of what the agent is waiting on, working sessions show what they're doing, recent history follows. Rows are clickable; the whole thing wears the T5 language. (The composer lands in Task 10.)

**Files:**
- Modify: `Sources/FabledCore/AppModel.swift` (welcome data)
- Modify: `Sources/FabledCore/ChatSession.swift` (`resumedSessionID`)
- Rewrite: `App/WelcomeView.swift`
- Test: `Tests/FabledCoreTests/AppModelTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `Tests/FabledCoreTests/AppModelTests.swift`:

```swift
    @MainActor
    func testWelcomeRecentsExcludeLiveResumedSessions() async throws {
        // Construct via the file's existing corpus/model helper; then:
        let model = try makeModel()                      // adapt to helper
        await model.bootstrap()
        let recents = model.welcomeRecents(limit: 5)
        XCTAssertFalse(recents.isEmpty)
        XCTAssertEqual(recents.map(\.id),
                       recents.sorted { $0.lastActivity > $1.lastActivity }.map(\.id),
                       "newest first, across projects")
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter WelcomeRecents 2>&1 | tail -5`
Expected: compile error — `welcomeRecents` doesn't exist.

- [ ] **Step 3: Implement the core**

`Sources/FabledCore/AppModel.swift` — append near `summary(forSessionID:)`:

```swift
    /// Welcome inbox recents: newest sessions across ALL projects (the
    /// sidebar groups; the welcome screen interleaves), excluding sessions
    /// currently attached to a live ChatSession (those render in the live
    /// sections above).
    public func welcomeRecents(limit: Int) -> [SessionSummary] {
        let liveIDs = Set(liveSessions.compactMap(\.resumedSessionID))
        var seen = Set<String>()
        var result: [SessionSummary] = []
        for group in history {
            for summary in group.sessions where !liveIDs.contains(summary.id) {
                if seen.insert(summary.id).inserted { result.append(summary) }
            }
        }
        result.sort { $0.lastActivity > $1.lastActivity }
        return Array(result.prefix(limit))
    }
```

`ChatSession.resumedSessionID` does not exist until Task 12 — add the stored property NOW as part of this step (Task 12 wires it to resume):

```swift
    /// The on-disk session id this live session resumed, if any (set at
    /// launch for --resume spawns; nil for fresh sessions). Task 12 uses it
    /// to enforce one live process per session id.
    public let resumedSessionID: String?
```

with `resumedSessionID: String? = nil` appended to the initializer and `resumedSessionID: configuration.forkSession ? nil : configuration.resumeSessionID` passed in `launch(configuration:)` (a fork is a NEW identity — it must not block or shadow its source session).

- [ ] **Step 4: Run the core tests**

Run: `swift test 2>&1 | tail -3`
Expected: 0 failures (1 new).

- [ ] **Step 5: Rewrite WelcomeView**

Full new contents of `App/WelcomeView.swift` (the `newSession` closure survives for the "Open folder…" path; Task 10 adds the composer where marked):

```swift
import SwiftUI
import ClaudeKit
import FabledCore

/// The attention inbox (feature 13, CD digest §1): what needs Ben, what's
/// working, what's recent — composer-first once T10 lands. Shown on launch,
/// on ⌘N, and whenever nothing is selected.
struct WelcomeView: View {
    @Environment(AppModel.self) private var app
    let newSession: () -> Void

    private var needsInput: [ChatSession] {
        app.liveSessions.filter { $0.activityState == .needsApproval }
    }
    private var working: [ChatSession] {
        app.liveSessions.filter { $0.activityState == .working }
    }
    private var idleLive: [ChatSession] {
        app.liveSessions.filter {
            $0.activityState == .idle || $0.activityState == .ended
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spaceXL) {
                header
                if !needsInput.isEmpty {
                    inboxSection("Needs your input", sessions: needsInput)
                }
                if !working.isEmpty {
                    inboxSection("Working", sessions: working)
                }
                if !idleLive.isEmpty {
                    inboxSection("Open sessions", sessions: idleLive)
                }
                recentsSection
                // T10 composer slot
            }
            .padding(Theme.spaceXL)
            .frame(maxWidth: Theme.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.welcomeBackdrop)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.spaceXS) {
            Text("Fabled")
                .font(Theme.display)
                .foregroundStyle(Theme.bronze)
            Text("Native Claude Code for the Mac")
                .font(Theme.assistantFont(.callout))
                .foregroundStyle(.secondary)
        }
        .padding(.top, Theme.spaceXL)
    }

    private func inboxSection(_ title: String, sessions: [ChatSession]) -> some View {
        VStack(alignment: .leading, spacing: Theme.spaceS) {
            Text(title).font(Theme.heading)
            ForEach(sessions) { session in
                WelcomeLiveRow(session: session) {
                    app.selection = .live(session.id)
                }
            }
        }
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: Theme.spaceS) {
            HStack {
                Text("Recent").font(Theme.heading)
                Spacer()
                Button("Open folder…", action: newSession)
                    .controlSize(.small)
            }
            let recents = app.welcomeRecents(limit: 8)
            if recents.isEmpty {
                Text("No sessions yet — open a folder to begin.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(recents) { summary in
                WelcomeRecentRow(summary: summary) {
                    app.selection = .historical(summary.id)
                }
            }
        }
    }
}

/// One live-session inbox row: status chip with WORDS, title, and — for
/// needs-input — a preview of what the agent is waiting on (digest §1).
private struct WelcomeLiveRow: View {
    let session: ChatSession
    let open: () -> Void

    var body: some View {
        HStack(spacing: Theme.spaceM) {
            SessionStatusBadge(state: session.activityState, labeled: true)
                .frame(width: 110, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title).lineLimit(1)
                Text(previewLine)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(session.workingDirectory.lastPathComponent)
                .font(.caption).foregroundStyle(.tertiary)
            Image(systemName: "chevron.right")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(Theme.spaceM)
        .background(.quinary, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var previewLine: String {
        if let gate = session.pendingGate { return gate.summaryLine }
        if session.isWorking { return "Working…" }
        return "Ready"
    }
}

private struct WelcomeRecentRow: View {
    let summary: SessionSummary
    let open: () -> Void

    var body: some View {
        HStack(spacing: Theme.spaceM) {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.title).lineLimit(1)
                Text(summary.project.displayName)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(summary.lastActivity, format: .relative(presentation: .named))
                .font(.caption).foregroundStyle(.tertiary)
            Image(systemName: "chevron.right")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(Theme.spaceM)
        .background(.quinary, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
```

(`WelcomeView` now reads the AppModel from the environment — `RootView` already injects it; the two `WelcomeView { app.isPickingFolder = true }` call sites compile unchanged.)

- [ ] **Step 6: Build + smoke**

Run: `swift build && swift test 2>&1 | tail -3` then `xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled -configuration Debug build 2>&1 | tail -2`
Expected: 0 failures; `** BUILD SUCCEEDED **`.
Smoke: with one session holding a permission gate and another streaming, deselect (⌘-click the sidebar selection or open a new window) — the welcome pane shows "Needs your input" on top with the orange chip and the command preview, "Working" below it, recents across projects at the bottom; every row opens the right session.

- [ ] **Step 7: Commit**

```bash
git -C ~/Developer/Fabled add Sources/FabledCore App Tests/FabledCoreTests
git -C ~/Developer/Fabled commit -m "feat: welcome attention inbox — needs-input first with gate previews, working, cross-project recents (4b T9)"
```

---

## Task 10: Welcome composer — start a session from the home surface

The second half of feature 13: starting a session is *pick project chips + type* (digest §1-composer), with `NSOpenPanel` demoted to the explicit fallback. A recents dropdown chip chooses the folder, the draft becomes the session's first message, and the T2 preferred-effort chip rides along.

**Files:**
- Modify: `Sources/FabledCore/AppModel.swift`
- Modify: `App/WelcomeView.swift`
- Test: `Tests/FabledCoreTests/AppModelTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `Tests/FabledCoreTests/AppModelTests.swift`:

```swift
    @MainActor
    func testRecentProjectsAreOrderedAndDeduped() async throws {
        let model = try makeModel()                      // adapt to helper
        await model.bootstrap()
        let projects = model.recentProjects(limit: 10)
        XCTAssertFalse(projects.isEmpty)
        XCTAssertEqual(Set(projects.map(\.id)).count, projects.count, "no duplicates")
    }
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter RecentProjects 2>&1 | tail -5`
Expected: compile error — `recentProjects` doesn't exist.

- [ ] **Step 3: Implement**

`Sources/FabledCore/AppModel.swift`:

1. Append near `welcomeRecents`:

```swift
    /// Composer project chip: recent projects, newest-session first
    /// (history is already ordered that way).
    public func recentProjects(limit: Int) -> [ProjectFolder] {
        Array(history.map(\.project).prefix(limit))
    }
```

2. Extend `newSession` with a first message (typed on the welcome composer):

```swift
    public func newSession(at directory: URL, model: String? = nil,
                           firstMessage: String? = nil) async {
        var configuration = SessionConfiguration(workingDirectory: directory)
        configuration.model = model
        configuration.effort = preferredEffort
        await launch(configuration, seed: [])
        if let firstMessage, case .live(let id) = selection,
           let session = liveSessions.first(where: { $0.id == id }) {
            session.send(firstMessage)
        }
    }
```

(`launch` only sets `selection` on success, so a failed spawn drops the message with the existing error alert — acceptable; the draft also stays in the composer's field only until send, so nothing is silently lost that the user didn't see happen.)

- [ ] **Step 4: The composer UI**

`App/WelcomeView.swift` — replace the `// T10 composer slot` comment with:

```swift
                composer
```

and add to `WelcomeView`:

```swift
    @State private var draft = ""
    @State private var chosenProject: ProjectFolder?
    @FocusState private var composerFocused: Bool

    private var targetProject: ProjectFolder? {
        chosenProject ?? app.recentProjects(limit: 1).first
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: Theme.spaceS) {
            Text("Start a session").font(Theme.heading)
            HStack(spacing: Theme.spaceS) {
                Menu {
                    ForEach(app.recentProjects(limit: 12)) { project in
                        Button {
                            chosenProject = project
                        } label: {
                            if project.id == targetProject?.id {
                                Label(project.displayName, systemImage: "checkmark")
                            } else {
                                Text(project.displayName)
                            }
                        }
                        .help(project.originalPath)
                    }
                    Divider()
                    Button("Open folder…", action: newSession)
                } label: {
                    Label(targetProject?.displayName ?? "Choose project",
                          systemImage: "folder")
                }
                .fixedSize()
                TextField("Message Claude to begin…", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .focused($composerFocused)
                    .onSubmit(startSession)
                Button(action: startSession) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(canStart ? Theme.clay : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canStart)
            }
            .padding(Theme.spaceM)
            .background(.quinary, in: RoundedRectangle(cornerRadius: Theme.radiusPanel))
        }
    }

    private var canStart: Bool {
        targetProject != nil
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func startSession() {
        guard canStart, let project = targetProject,
              project.originalPath.hasPrefix("/") else { return }
        let directory = URL(fileURLWithPath: project.originalPath)
        let message = draft
        draft = ""
        Task { await app.newSession(at: directory, firstMessage: message) }
    }
```

(Unresolvable flattened project names — `originalPath` without a leading `/` — can't be a cwd; the guard leaves them pickable but inert, matching the sidebar's existing display-only handling. FOLLOWUPS already tracks re-resolution.)

- [ ] **Step 5: Run everything, build, smoke, commit**

Run: `swift build && swift test 2>&1 | tail -3` — 0 failures (1 new).
Run: `xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled -configuration Debug build 2>&1 | tail -2` — `** BUILD SUCCEEDED **`
Smoke: on the welcome pane, pick a recent project from the chip, type "hello" and hit return — a live session opens in that folder with "hello" already sent; "Open folder…" still raises the panel.

```bash
git -C ~/Developer/Fabled add Sources/FabledCore App Tests/FabledCoreTests
git -C ~/Developer/Fabled commit -m "feat: welcome composer — project recents chip + type-to-start with first message (4b T10)"
```

---

## Task 11: Notifications + dock badge routing

Feature 7: UserNotifications when Ben isn't looking — a gate arriving while the app is inactive or the session unselected, a long turn completing (body = `post_turn_summary.status_detail`, which 4a probe finding 8 called ready-made notification text), and abnormal termination. Clicking focuses the right session. Policy is pure FabledCore (tested); delivery is a thin app-target manager. The dock badge (gates count) already works in RootView.

**Files:**
- Create: `Sources/FabledCore/NotificationPolicy.swift`
- Modify: `Sources/FabledCore/ChatSession.swift` (noteworthy-event hook + status_detail capture)
- Modify: `Sources/FabledCore/AppModel.swift` (policy wiring)
- Modify: `App/FabledApp.swift`, `App/RootView.swift` (delivery + click routing)
- Test: `Tests/FabledCoreTests/NotificationPolicyTests.swift` (create), `Tests/FabledCoreTests/ChatSessionTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/FabledCoreTests/NotificationPolicyTests.swift`:

```swift
import XCTest
@testable import FabledCore

final class NotificationPolicyTests: XCTestCase {
    func testGateNotifiesWhenAppInactive() {
        let note = NotificationPolicy.decide(
            .gateArrived(summary: "Approve: rm -rf build"),
            sessionTitle: "Fix the tests", sessionID: id,
            isAppActive: false, isSessionSelected: true)
        XCTAssertEqual(note?.title, "Fix the tests needs input")
        XCTAssertEqual(note?.body, "Approve: rm -rf build")
    }

    func testGateNotifiesWhenSessionUnselected() {
        XCTAssertNotNil(NotificationPolicy.decide(
            .gateArrived(summary: "Question waiting"),
            sessionTitle: "T", sessionID: id,
            isAppActive: true, isSessionSelected: false))
    }

    func testGateStaysQuietWhenWatching() {
        XCTAssertNil(NotificationPolicy.decide(
            .gateArrived(summary: "x"),
            sessionTitle: "T", sessionID: id,
            isAppActive: true, isSessionSelected: true))
    }

    func testShortTurnStaysQuiet() {
        XCTAssertNil(NotificationPolicy.decide(
            .turnCompleted(detail: "done", durationMS: 5_000),
            sessionTitle: "T", sessionID: id,
            isAppActive: false, isSessionSelected: false))
    }

    func testLongTurnNotifiesWithStatusDetail() {
        let note = NotificationPolicy.decide(
            .turnCompleted(detail: "replied with EFFORT-OK", durationMS: 45_000),
            sessionTitle: "T", sessionID: id,
            isAppActive: false, isSessionSelected: false)
        XCTAssertEqual(note?.body, "replied with EFFORT-OK")
    }

    func testAbnormalTerminationAlwaysNotifiesUnlessWatching() {
        XCTAssertNotNil(NotificationPolicy.decide(
            .terminated(exitCode: 1),
            sessionTitle: "T", sessionID: id,
            isAppActive: false, isSessionSelected: false))
        XCTAssertNil(NotificationPolicy.decide(
            .terminated(exitCode: 0),
            sessionTitle: "T", sessionID: id,
            isAppActive: false, isSessionSelected: false),
            "clean exits are not emergencies")
    }

    private let id = UUID()
}
```

Append to `Tests/FabledCoreTests/ChatSessionTests.swift`:

```swift
    func testNoteworthyHookFiresForGateTurnAndTermination() async throws {
        let (session, continuation, _) = makeSession()
        var seen: [ChatSession.NoteworthyEvent] = []
        session.onNoteworthy = { seen.append($0) }
        try yield(continuation, #"""
        {"type":"control_request","request_id":"p1","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"ls"}}}
        """#)
        try yield(continuation, #"""
        {"type":"system","subtype":"post_turn_summary","summarizes_uuid":"u","status_category":"review_ready","status_detail":"replied with READY-OK","needs_action":"","uuid":"pts","session_id":"s"}
        """#)
        try yield(continuation, #"""
        {"type":"result","subtype":"success","is_error":false,"num_turns":1,"duration_ms":45000,"session_id":"s"}
        """#)
        await waitUntil("hook") { seen.count >= 2 }
        guard case .gateArrived = seen[0] else { return XCTFail("expected gate, got \(seen)") }
        guard case .turnCompleted(let detail, let duration) = seen[1] else {
            return XCTFail("expected turn, got \(seen)")
        }
        XCTAssertEqual(detail, "replied with READY-OK")
        XCTAssertEqual(duration, 45000)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "NotificationPolicy|NoteworthyHook" 2>&1 | tail -8`
Expected: compile errors.

- [ ] **Step 3: Implement the core**

Create `Sources/FabledCore/NotificationPolicy.swift`:

```swift
import Foundation

/// A local notification the app should post. FabledCore decides; the app
/// target delivers (UNUserNotificationCenter is AppKit-side).
public struct LocalNotification: Equatable, Sendable {
    public let title: String
    public let body: String
    public let sessionID: UUID
}

/// Pure policy: notify only when Ben is NOT already looking at the session
/// (feature 7). Long-turn threshold 30 s — short turns complete before he
/// has looked away.
public enum NotificationPolicy {
    public static let longTurnThresholdMS: Double = 30_000

    public static func decide(
        _ event: ChatSession.NoteworthyEvent,
        sessionTitle: String, sessionID: UUID,
        isAppActive: Bool, isSessionSelected: Bool
    ) -> LocalNotification? {
        let watching = isAppActive && isSessionSelected
        guard !watching else { return nil }
        switch event {
        case .gateArrived(let summary):
            return LocalNotification(
                title: "\(sessionTitle) needs input", body: summary,
                sessionID: sessionID)
        case .turnCompleted(let detail, let durationMS):
            guard durationMS >= longTurnThresholdMS else { return nil }
            return LocalNotification(
                title: "\(sessionTitle) finished",
                body: detail.isEmpty ? "Turn complete" : detail,
                sessionID: sessionID)
        case .terminated(let exitCode):
            guard exitCode != 0 else { return nil }
            return LocalNotification(
                title: "\(sessionTitle) ended unexpectedly",
                body: "claude exited with code \(exitCode)",
                sessionID: sessionID)
        }
    }
}
```

`Sources/FabledCore/ChatSession.swift`:

1. Add the event vocabulary and hook, below the `id`/`workingDirectory` block:

```swift
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
```

2. In `handle(_:)`:
   - `case .controlRequest` — after each of the three `pendingGates.append(…)` calls' shared exit (i.e., after the `if let permission…` block, guarded on a gate actually appended):

```swift
            if let gate = pendingGates.last, gate.requestID == request.requestID {
                onNoteworthy?(.gateArrived(summary: gate.summaryLine))
            }
```

   - `case .system(let subtype, let raw)` — add:

```swift
            if subtype == "post_turn_summary" {
                lastStatusDetail = raw["status_detail"]?.stringValue ?? ""
            }
```

   - `case .result(let turn)` — at the end of the case:

```swift
            if turn.raw["num_turns"]?.doubleValue != 0 {
                onNoteworthy?(.turnCompleted(
                    detail: lastStatusDetail, durationMS: turn.durationMS ?? 0))
                lastStatusDetail = ""
            }
```

(fold this into the same `if` that guards `pendingGates.removeAll()` — one num_turns check, both bodies.)
   - `case .terminated(let exitCode)` — add `onNoteworthy?(.terminated(exitCode: exitCode))`.

`Sources/FabledCore/AppModel.swift`:

1. Injected delivery seams (app target wires them; tests leave them nil):

```swift
    /// AppKit-side seams: is the app frontmost, and post a notification.
    /// Injected by the app target at startup (FabledCore cannot import AppKit).
    public var isAppActive: () -> Bool = { true }
    public var postNotification: (LocalNotification) -> Void = { _ in }
```

2. In `launch(_:seed:)`, after `liveSessions.append(session)`:

```swift
            session.onNoteworthy = { [weak self, weak session] event in
                guard let self, let session else { return }
                let selected = self.selection == .live(session.id)
                if let note = NotificationPolicy.decide(
                    event, sessionTitle: session.title, sessionID: session.id,
                    isAppActive: self.isAppActive(), isSessionSelected: selected) {
                    self.postNotification(note)
                }
            }
```

3. Click routing:

```swift
    /// Notification click: focus the session (feature 7).
    public func focusSession(id: UUID) {
        guard liveSessions.contains(where: { $0.id == id }) else { return }
        selection = .live(id)
    }
```

- [ ] **Step 4: Run the core tests**

Run: `swift test 2>&1 | tail -3`
Expected: 0 failures (7 new).

- [ ] **Step 5: App-target delivery**

`App/FabledApp.swift` — full new contents:

```swift
import SwiftUI
import AppKit
import UserNotifications
import FabledCore

@main
struct FabledApp: App {
    @State private var model: AppModel
    private let notifier: Notifier

    init() {
        // Writes to a dead CLI's stdin raise SIGPIPE and the default
        // disposition kills the app. ClaudeKit short-circuits writes after
        // termination; this is the process-level backstop for the race.
        signal(SIGPIPE, SIG_IGN)
        do {
            let model = try AppModel()
            let notifier = Notifier()
            notifier.onClick = { [weak model] id in
                NSApp.activate()
                model?.focusSession(id: id)
            }
            model.isAppActive = { NSApp.isActive }
            model.postNotification = { notifier.post($0) }
            _model = State(initialValue: model)
            self.notifier = notifier
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
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Session…") { model.isPickingFolder = true }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

/// Thin UNUserNotificationCenter wrapper: lazy permission, session-id
/// userInfo, click callback. Kept out of FabledCore (AppKit/UN import).
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    var onClick: ((UUID) -> Void)?
    private var authorizationRequested = false

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func post(_ note: LocalNotification) {
        let center = UNUserNotificationCenter.current()
        if !authorizationRequested {
            authorizationRequested = true
            center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
        let content = UNMutableNotificationContent()
        content.title = note.title
        content.body = note.body
        content.userInfo = ["sessionID": note.sessionID.uuidString]
        center.add(UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let raw = info["sessionID"] as? String, let id = UUID(uuidString: raw)
        else { return }
        await MainActor.run { onClick?(id) }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // App active but session unselected: still show the banner.
        [.banner, .sound]
    }
}
```

- [ ] **Step 6: Run everything, build, smoke, commit**

Run: `swift build && swift test 2>&1 | tail -3` — 0 failures.
Run: `xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled -configuration Debug build 2>&1 | tail -2` — `** BUILD SUCCEEDED **`
Smoke: start a session, switch to another app, trigger a permission gate (e.g. ask for `git status`) — a banner appears ("<title> needs input / Approve: git status"); clicking it activates Fabled with that session selected. Note: ad-hoc-signed dev builds surface the permission prompt on first post — approve it once.

```bash
git -C ~/Developer/Fabled add Sources/FabledCore App Tests/FabledCoreTests
git -C ~/Developer/Fabled commit -m "feat: notifications — pure policy, noteworthy hooks, UNUserNotificationCenter delivery + click focus (4b T11)"
```

---

## Task 12: Resume semantics — Continue vs Fork vs View, collision guard, cwd fallback

Feature 16. `--resume` continues the SAME session id (DECISIONS 2026-07-09), so the surprises are all presentational: make "Continue" and "View transcript" separate explicit actions (T8 already added the context-menu halves), label forks as forks, refuse to spawn a SECOND live process on one session id (the one-process invariant, app-side), surface the silent `$HOME` fallback when a project folder is gone, and close the `task(id:)` stale-assignment window (FOLLOWUPS).

**Files:**
- Modify: `Sources/FabledCore/AppModel.swift`
- Modify: `App/HistoricalSessionView.swift`
- Test: `Tests/FabledCoreTests/AppModelTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/FabledCoreTests/AppModelTests.swift`:

```swift
    @MainActor
    func testResumeCollisionSelectsExistingLiveSession() async throws {
        let model = try makeModel()                      // adapt to helper
        let (connection, _, _) = makeFakeConnection()
        let live = ChatSession(
            connection: connection,
            workingDirectory: URL(fileURLWithPath: "/tmp/demo"),
            resumedSessionID: "abc-123")
        model.adoptForTesting(live)
        let summary = SessionSummary(
            id: "abc-123",
            project: ProjectFolder(flattenedName: "-tmp-demo",
                                   originalPath: "/tmp/demo",
                                   directoryURL: URL(fileURLWithPath: "/tmp/demo")),
            fileURL: URL(fileURLWithPath: "/tmp/demo/abc-123.jsonl"),
            title: "t", lastActivity: .now, approximateSizeBytes: 1)
        await model.resume(summary, fork: false)
        XCTAssertEqual(model.liveSessions.count, 1, "no duplicate spawn")
        XCTAssertEqual(model.selection, .live(live.id))
    }

    @MainActor
    func testFallbackDirectoryIsFlagged() throws {
        let model = try makeModel()                      // adapt to helper
        let gone = SessionSummary(
            id: "x",
            project: ProjectFolder(flattenedName: "-gone-project",
                                   originalPath: "-gone-project",   // unresolvable
                                   directoryURL: URL(fileURLWithPath: "/nope")),
            fileURL: URL(fileURLWithPath: "/nope/x.jsonl"),
            title: "t", lastActivity: .now, approximateSizeBytes: 1)
        let resolved = model.resolveWorkingDirectory(for: gone)
        XCTAssertTrue(resolved.didFallBack)
        XCTAssertEqual(resolved.url,
                       FileManager.default.homeDirectoryForCurrentUser)
    }
```

Add the test hook to `AppModel` (source, not test target — it is three lines and honest about its purpose):

```swift
    /// Test seam: registers a live session without spawning a process.
    public func adoptForTesting(_ session: ChatSession) {
        liveSessions.append(session)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "ResumeCollision|FallbackDirectory" 2>&1 | tail -8`
Expected: compile errors — `adoptForTesting`, `resolveWorkingDirectory` don't exist.

- [ ] **Step 3: Implement**

`Sources/FabledCore/AppModel.swift`:

1. Replace `workingDirectory(for:)` with the flagged version:

```swift
    /// Resolves a summary's original cwd; falls back to $HOME when the
    /// project folder no longer exists — and SAYS so (feature 16 rider:
    /// the fallback used to be silent).
    public func resolveWorkingDirectory(for summary: SessionSummary)
        -> (url: URL, didFallBack: Bool) {
        let path = summary.project.originalPath
        guard path.hasPrefix("/"),
              FileManager.default.fileExists(atPath: path) else {
            return (FileManager.default.homeDirectoryForCurrentUser, true)
        }
        return (URL(fileURLWithPath: path), false)
    }
```

2. Replace `resume(_:fork:)`:

```swift
    /// Resume/fork replays nothing on the wire (probe finding 8) — the
    /// timeline is seeded from the on-disk transcript. Continue reattaches
    /// the SAME session id, so a second live process on that id is forbidden
    /// (one-process invariant): an existing attachment is selected instead.
    public func resume(_ summary: SessionSummary, fork: Bool) async {
        if !fork, let existing = liveSessions.first(
            where: { $0.resumedSessionID == summary.id }) {
            selection = .live(existing.id)
            return
        }
        var seed = await historicalTimeline(for: summary)
        let resolved = resolveWorkingDirectory(for: summary)
        if fork {
            seed = [.notice(id: "fork-origin",
                            text: "Forked from “\(summary.title)” — this is a new session id.")]
                + seed
        }
        if resolved.didFallBack {
            seed = seed + [.notice(id: "cwd-fallback",
                                   text: "Original folder \(summary.project.originalPath) no longer exists — running in your home folder instead.")]
        }
        var configuration = SessionConfiguration(workingDirectory: resolved.url)
        configuration.resumeSessionID = summary.id
        configuration.forkSession = fork
        configuration.effort = preferredEffort
        await launch(configuration, seed: seed)
    }
```

(T9 Step 3 already routes `configuration.resumeSessionID` → `ChatSession.resumedSessionID` for non-fork launches.)

- [ ] **Step 4: Historical toolbar + the task(id:) race**

`App/HistoricalSessionView.swift`:

1. Toolbar: replace the two buttons:

```swift
                Button("Continue") { Task { await app.resume(summary, fork: false) } }
                    .buttonStyle(.borderedProminent).tint(Theme.clay)
                    .help("Reattach a live session to this same session id")
                Button("Fork") { Task { await app.resume(summary, fork: true) } }
                    .help("Branch a NEW session seeded with this history")
```

2. The stale-assignment window (FOLLOWUPS: rapid switching): replace the `.task(id: summary.id)` body:

```swift
        .task(id: summary.id) {
            let requested = summary.id
            items = nil
            let loaded = await app.historicalTimeline(for: summary)
            // Rapid switching: a slow load must not land on a newer selection
            // (FOLLOWUPS stale-assignment window).
            guard !Task.isCancelled, requested == summary.id else { return }
            items = loaded
        }
```

- [ ] **Step 5: Run everything, build, smoke, commit**

Run: `swift build && swift test 2>&1 | tail -3` — 0 failures (2 new).
Run: `xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled -configuration Debug build 2>&1 | tail -2` — `** BUILD SUCCEEDED **`
Smoke: Continue a historical session twice — the second click selects the existing live row instead of spawning; Fork shows the "Forked from…" notice at the top; a session whose folder was deleted shows the home-folder notice.

```bash
git -C ~/Developer/Fabled add Sources/FabledCore App Tests/FabledCoreTests
git -C ~/Developer/Fabled commit -m "feat: resume semantics — collision guard, fork labelling, cwd-fallback notice, task(id:) race fix (4b T12)"
```

---

## Task 13: Transcript step grouping

Digest §2a — the biggest transcript-hygiene delta vs Claude Desktop: runs of finished tool calls collapse into one summarized row ("Ran 5 commands ›") that expands inline. Pure grouping pass in FabledCore over the reducer's output; expansion state lives at container level (per the 4a LazyVStack scar, no per-row `@State`).

**Grouping rules (locked):** a group is a run of ≥ 3 consecutive `.toolCall` items that are all finished (`isRunning == false`), error-free (`isError != true`), and not drill-down anchors (name ∉ {"Task", "Agent"} — their "N steps" chips must stay visible). Anything else — running tools, errors, permissions, text — breaks the run and renders normally. The live tail therefore stays visible while streaming and collapses when the run finishes.

**Files:**
- Create: `Sources/FabledCore/TimelineDisplay.swift`
- Modify: `Sources/FabledCore/TimelineItem.swift` (public `toolCallID`)
- Modify: `App/TimelineItemViews.swift`, `App/ConversationView.swift`, `App/HistoricalSessionView.swift`
- Test: `Tests/FabledCoreTests/TimelineDisplayTests.swift` (create)

- [ ] **Step 1: Write the failing tests**

Create `Tests/FabledCoreTests/TimelineDisplayTests.swift`:

```swift
import XCTest
import ClaudeKit
@testable import FabledCore

final class TimelineDisplayTests: XCTestCase {
    private func tool(_ id: String, name: String = "Bash",
                      running: Bool = false, error: Bool? = false) -> TimelineItem {
        .toolCall(id: id, name: name, summary: "s", input: .object([:]),
                  result: running ? nil : .string("ok"),
                  isError: error, isRunning: running)
    }
    private func text(_ id: String) -> TimelineItem {
        .assistantText(id: id, markdown: "hi", isStreaming: false)
    }

    func testRunOfThreeCollapses() {
        let rows = TimelineDisplay.grouped(
            [text("a"), tool("t1"), tool("t2"), tool("t3"), text("b")])
        XCTAssertEqual(rows.count, 3)
        guard case .toolGroup(let id, let items, let summary) = rows[1] else {
            return XCTFail("expected group, got \(rows)")
        }
        XCTAssertEqual(id, "t1", "group id = first item id (stable)")
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(summary, "Ran 3 commands")
    }

    func testRunOfTwoStaysFlat() {
        let rows = TimelineDisplay.grouped([tool("t1"), tool("t2")])
        XCTAssertEqual(rows.count, 2)
        for row in rows {
            guard case .item = row else { return XCTFail("no grouping under 3") }
        }
    }

    func testRunningToolBreaksTheRun() {
        let rows = TimelineDisplay.grouped(
            [tool("t1"), tool("t2"), tool("t3", running: true)])
        XCTAssertEqual(rows.count, 3, "live tail stays visible")
    }

    func testErrorBreaksTheRun() {
        let rows = TimelineDisplay.grouped(
            [tool("t1"), tool("t2", error: true), tool("t3"), tool("t4"), tool("t5")])
        // t1 alone, t2 visible error, t3–t5 group.
        XCTAssertEqual(rows.count, 3)
        guard case .toolGroup(_, let items, _) = rows[2] else {
            return XCTFail("expected trailing group, got \(rows)")
        }
        XCTAssertEqual(items.map(\.id), ["t3", "t4", "t5"])
    }

    func testTaskAnchorsNeverGroup() {
        let rows = TimelineDisplay.grouped(
            [tool("t1"), tool("t2", name: "Task"), tool("t3"), tool("t4"), tool("t5")])
        XCTAssertEqual(rows.count, 3, "Task splits: t1 | Task | t3-t5 group")
        guard case .item(let item) = rows[1], item.id == "t2" else {
            return XCTFail("Task row must render alone, got \(rows)")
        }
    }

    func testSummariesByToolMix() {
        func summaryOf(_ names: [String]) -> String {
            let items = names.enumerated().map { tool("x\($0.offset)", name: $0.element) }
            guard case .toolGroup(_, _, let summary) = TimelineDisplay.grouped(items).first
            else { XCTFail("expected group"); return "" }
            return summary
        }
        XCTAssertEqual(summaryOf(["Bash", "Bash", "Bash"]), "Ran 3 commands")
        XCTAssertEqual(summaryOf(["Edit", "Write", "MultiEdit"]), "Edited 3 files")
        XCTAssertEqual(summaryOf(["Read", "Read", "Read", "Read"]), "4 × Read")
        XCTAssertEqual(summaryOf(["Read", "Bash", "Edit"]), "3 steps")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter TimelineDisplayTests 2>&1 | tail -5`
Expected: compile error — `TimelineDisplay` doesn't exist.

- [ ] **Step 3: Implement**

In `Sources/FabledCore/TimelineItem.swift`, make the matching key public (the views need it now):

```swift
    /// Non-nil for tool calls — the reducer's result-matching key.
    public var toolCallID: String? {
        if case .toolCall(let id, _, _, _, _, _, _) = self { return id }
        return nil
    }
```

Create `Sources/FabledCore/TimelineDisplay.swift`:

```swift
import Foundation

/// One rendered transcript row: a plain item, or a collapsed run of tool
/// calls (CD digest §2a). Pure presentation pass — the reducer's output is
/// untouched, so the inspector/id vocabulary is unchanged.
public enum TimelineRow: Identifiable, Equatable, Sendable {
    case item(TimelineItem)
    case toolGroup(id: String, items: [TimelineItem], summary: String)

    public var id: String {
        switch self {
        case .item(let item): item.id
        case .toolGroup(let id, _, _): "group-\(id)"
        }
    }
}

public enum TimelineDisplay {
    /// Names whose rows carry their own affordances and must stay visible.
    private static let anchors: Set<String> = ["Task", "Agent"]
    /// Minimum run length worth collapsing.
    private static let minimumRun = 3

    public static func grouped(_ items: [TimelineItem]) -> [TimelineRow] {
        var rows: [TimelineRow] = []
        var run: [TimelineItem] = []

        func flush() {
            if run.count >= minimumRun, let first = run.first {
                rows.append(.toolGroup(id: first.id, items: run,
                                       summary: summary(for: run)))
            } else {
                rows += run.map(TimelineRow.item)
            }
            run = []
        }

        for item in items {
            if case .toolCall(_, let name, _, _, _, let isError, let isRunning) = item,
               !isRunning, isError != true, !anchors.contains(name) {
                run.append(item)
            } else {
                flush()
                rows.append(.item(item))
            }
        }
        flush()
        return rows
    }

    private static func summary(for run: [TimelineItem]) -> String {
        let names: [String] = run.compactMap {
            if case .toolCall(_, let name, _, _, _, _, _) = $0 { return name }
            return nil
        }
        let unique = Set(names)
        let editors: Set<String> = ["Edit", "Write", "MultiEdit", "NotebookEdit"]
        if unique == ["Bash"] { return "Ran \(names.count) commands" }
        if unique.isSubset(of: editors) { return "Edited \(names.count) files" }
        if unique.count == 1, let name = unique.first {
            return "\(names.count) × \(name)"
        }
        return "\(names.count) steps"
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter TimelineDisplayTests 2>&1 | tail -5`
Expected: 6 tests, 0 failures.

- [ ] **Step 5: Render groups**

`App/TimelineItemViews.swift` — append:

```swift
/// Collapsed tool-run row (digest §2a). Expansion state lives on the
/// container (expandedGroups set) — never per-row @State (4a scar).
struct ToolGroupRow: View {
    let id: String
    let items: [TimelineItem]
    let summary: String
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spaceS) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                Text(summary).fontWeight(.medium)
                Text("\(items.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
                Spacer(minLength: 4)
            }
            .font(.callout)
            .padding(Theme.spaceS)
            .background(.quinary, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(Theme.snap) { toggle() } }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("\(summary), \(isExpanded ? "expanded" : "collapsed")")
            .help(isExpanded ? "Collapse this run" : "Expand \(items.count) steps")
            if isExpanded {
                VStack(alignment: .leading, spacing: Theme.spaceS) {
                    // Grouped runs never contain Task/Agent rows (anchors are
                    // excluded from grouping), so no subagent plumbing here.
                    // T14's signature sweep updates this call site.
                    ForEach(items) { item in
                        TimelineItemView(item: item, session: nil)
                    }
                }
                .padding(.leading, Theme.spaceL)
            }
        }
    }
}
```

`App/ConversationView.swift` — container state + swapped loop. Add alongside the inspector state:

```swift
    @State private var expandedGroups: Set<String> = []
```

reset it in the existing `.onChange(of: session.id)` handler (`expandedGroups.removeAll()`), and replace the timeline `ForEach`:

```swift
                        ForEach(TimelineDisplay.grouped(session.timeline)) { row in
                            switch row {
                            case .item(let item):
                                TimelineItemView(item: item, session: session)
                            case .toolGroup(let id, let items, let summary):
                                ToolGroupRow(
                                    id: id, items: items, summary: summary,
                                    isExpanded: expandedGroups.contains(id),
                                    toggle: {
                                        if expandedGroups.contains(id) {
                                            expandedGroups.remove(id)
                                        } else {
                                            expandedGroups.insert(id)
                                        }
                                    })
                            }
                        }
```

`App/HistoricalSessionView.swift` — same pattern: add `@State private var expandedGroups: Set<String> = []`, wrap the `ForEach(items)` identically (with `session: nil` rows), and clear `expandedGroups` at the top of the `.task(id: summary.id)` body.

Perf note (ledger, don't fix): `TimelineDisplay.grouped` recomputes per render — O(n) over a few hundred items, dwarfed by the row bodies. Revisit only if profiling says so.

- [ ] **Step 6: Run everything, build, smoke, commit**

Run: `swift build && swift test 2>&1 | tail -3` — 0 failures.
Run: `xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled -configuration Debug build 2>&1 | tail -2` — `** BUILD SUCCEEDED **`
Smoke: replay a tool-heavy historical session — runs of ≥3 finished tools read as "Ran N commands ›" rows that expand/collapse; a live session's in-flight tool row never disappears into a group mid-run.

```bash
git -C ~/Developer/Fabled add Sources/FabledCore App Tests/FabledCoreTests
git -C ~/Developer/Fabled commit -m "feat: transcript step grouping — pure display pass, container-level expansion (4b T13)"
```

---

## Task 14: Historical subagent drill-down + history hygiene

Feature 15 as rescoped (finding 14): subagent transcripts live at `<session-dir>/subagents/agent-<id>.jsonl` with a `meta.json` whose `toolUseId` links them to the parent's Task card. This task reads them, feeds the SAME inspector drill-down 4a built for live sessions, pins the depth-2 sidebar invariant with a guard test, and fixes the "Agent Agent" placeholder cosmetic (FOLLOWUPS).

**Files:**
- Modify: `Sources/ClaudeKit/SessionStore.swift`
- Modify: `Sources/FabledCore/TimelineReducer.swift` (allowSidechain), `Sources/FabledCore/AppModel.swift`
- Modify: `App/HistoricalSessionView.swift`, `App/TimelineItemViews.swift`, `App/ConversationView.swift`
- Test: `Tests/ClaudeKitTests/SessionStoreTests.swift`, `Tests/FabledCoreTests/TimelineReducerTests.swift`

- [ ] **Step 1: Write the failing SessionStore tests**

Append to `Tests/ClaudeKitTests/SessionStoreTests.swift` (follow the file's temp-directory pattern for building fake project trees):

```swift
    func testSubagentFilesAreInvisibleToEnumeration() throws {
        // Depth-2 invariant (4b finding 14): nested agent transcripts must
        // never surface as sessions. Guard-tested so a future enumeration
        // change can't silently pollute the sidebar.
        let root = try makeTempProjectsRoot()            // adapt to the file's helper
        let project = root.appendingPathComponent("-tmp-proj")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let sessionFile = project.appendingPathComponent("aaaa-1111.jsonl")
        try Data(#"{"type":"user","message":{"role":"user","content":"hi"},"sessionId":"aaaa-1111","uuid":"u1","timestamp":"2026-07-11T00:00:00Z"}"#.utf8)
            .write(to: sessionFile)
        let subagents = project.appendingPathComponent("aaaa-1111/subagents")
        try FileManager.default.createDirectory(at: subagents, withIntermediateDirectories: true)
        try Data(#"{"type":"user","isSidechain":true,"agentId":"abc","message":{"role":"user","content":"task prompt"},"sessionId":"aaaa-1111","uuid":"u2","timestamp":"2026-07-11T00:00:01Z"}"#.utf8)
            .write(to: subagents.appendingPathComponent("agent-abc.jsonl"))
        let store = SessionStore(projectsDirectory: root)   // adapt to the file's construction
        let project0 = try store.projectsSync()[0]           // adapt: however the tests enumerate
        let sessions = try store.sessionsSync(in: project0)  // adapt likewise
        XCTAssertEqual(sessions.map(\.id), ["aaaa-1111"],
                       "the nested agent file must not enumerate")
    }

    func testSubagentTimelinesReadByToolUseID() throws {
        // Same tree as above, plus the meta.json linking file → Task card.
        // (Build both in a shared helper if the file prefers.)
        let meta = #"{"agentType":"general-purpose","description":"count files","toolUseId":"toolu_XYZ","spawnDepth":1}"#
        // … write agent-abc.meta.json next to agent-abc.jsonl …
        let timelines = try store.subagentTranscriptsSync(for: summary)   // adapt
        XCTAssertEqual(Array(timelines.keys), ["toolu_XYZ"])
        XCTAssertFalse(timelines["toolu_XYZ"]!.isEmpty)
    }
```

**Note for the implementer:** `SessionStore` is an actor — the existing tests already have a calling convention for it (async or sync helpers); mirror it exactly rather than inventing the `…Sync` names above. The assertions are the contract; the plumbing follows the file's precedent.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "SubagentFiles|SubagentTimelines" 2>&1 | tail -5`
Expected: compile error — `subagentTranscripts` doesn't exist (the enumeration guard half may already pass; that is fine, it's insurance).

- [ ] **Step 3: Implement the store read**

In `Sources/ClaudeKit/SessionStore.swift`, add:

```swift
    /// On-disk subagent transcripts for a session, keyed by the parent's
    /// Task tool_use id (from each agent's meta.json — census 2026-07-11).
    /// Layout: <project>/<session-id>/subagents/agent-<agentId>.jsonl
    ///       + <project>/<session-id>/subagents/agent-<agentId>.meta.json
    /// Missing directory (no subagents) returns [:] — not an error.
    public func subagentTranscripts(
        for session: SessionSummary
    ) throws -> [String: [TranscriptEntry]] {
        let directory = session.fileURL.deletingPathExtension()
            .appendingPathComponent("subagents")
        guard fileManager.fileExists(atPath: directory.path) else { return [:] }
        let contents = try fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)
        var result: [String: [TranscriptEntry]] = [:]
        for metaURL in contents where metaURL.lastPathComponent.hasSuffix(".meta.json") {
            guard let metaData = try? Data(contentsOf: metaURL),
                  let meta = try? JSONValue(parsing: metaData),
                  let toolUseID = meta["toolUseId"]?.stringValue else { continue }
            let transcriptURL = URL(fileURLWithPath: metaURL.path
                .replacingOccurrences(of: ".meta.json", with: ".jsonl"))
            guard let data = try? Data(contentsOf: transcriptURL, options: .mappedIfSafe)
            else { continue }
            var entries: [TranscriptEntry] = []
            var lines = JSONLines(data: data)
            while let line = lines.next() {
                if let entry = try? TranscriptDecoder.decode(line) {
                    entries.append(entry)
                }
            }
            if !entries.isEmpty { result[toolUseID] = entries }
        }
        return result
    }
```

(If `JSONValue(parsing:)`'s argument label differs, match the existing call sites in `TranscriptDecoder`/`SearchIndex` — do not add a new decode path.)

- [ ] **Step 4: Reducer sidechain switch + AppModel wrapper (failing test first)**

Append to `Tests/FabledCoreTests/TimelineReducerTests.swift`:

```swift
    func testTranscriptReplayCanIncludeSidechainLines() throws {
        let line = Data(#"{"type":"user","isSidechain":true,"message":{"role":"user","content":"subagent prompt"},"sessionId":"s","uuid":"u1","timestamp":"2026-07-11T00:00:00Z"}"#.utf8)
        let entry = try TranscriptDecoder.decode(line)
        XCTAssertTrue(TimelineReducer.items(fromTranscript: [entry]).isEmpty,
                      "main-chain replay keeps skipping sidechain")
        XCTAssertFalse(TimelineReducer.items(fromTranscript: [entry],
                                             allowSidechain: true).isEmpty,
                       "subagent replay reads its own sidechain lines")
    }
```

Run: `swift test --filter SidechainLines 2>&1 | tail -3` — compile error expected.

`Sources/FabledCore/TimelineReducer.swift` — extend the signature and both guards:

```swift
    public static func items(fromTranscript entries: [TranscriptEntry],
                             allowSidechain: Bool = false) -> [TimelineItem] {
```

with the two guards becoming `guard allowSidechain || !context.isSidechain, !context.isMeta else { continue }` (userPrompt) and `guard allowSidechain || !context.isSidechain else { continue }` (event).

`Sources/FabledCore/AppModel.swift` — append near `historicalTimeline(for:)`:

```swift
    /// Subagent drill-down data for a HISTORICAL session — the on-disk
    /// analog of ChatSession.subagentTimelines (feature 15 as rescoped).
    public func historicalSubagentTimelines(
        for summary: SessionSummary
    ) async -> [String: [TimelineItem]] {
        let transcripts = (try? await store.subagentTranscripts(for: summary)) ?? [:]
        return transcripts.mapValues {
            TimelineReducer.items(fromTranscript: $0, allowSidechain: true)
        }
    }
```

- [ ] **Step 5: The view sweep — `subagentSteps` replaces `session` in rows**

`App/TimelineItemViews.swift`:

1. `TimelineItemView` signature:

```swift
/// One timeline row. `subagentSteps` is the routed sub-item count for
/// Task/Agent rows (live: ChatSession.subagentTimelines; historical: the
/// on-disk read) — passing the COUNT instead of the session decouples rows
/// from live-session observation (T11 4a review note) and lets history
/// share the exact same row.
struct TimelineItemView: View {
    let item: TimelineItem
    var subagentSteps: Int? = nil
```

with the `.toolCall` case passing `subagentSteps: subagentSteps` to `ToolCallCard` (drop the `session?.subagentTimelines[id]?.count` read).

2. In `ToolCallCard.body`, fix the placeholder cosmetic (FOLLOWUPS "Agent Agent"): replace `Text(summary)…` with:

```swift
            if summary != name {
                Text(summary).foregroundStyle(.secondary).lineLimit(1)
            }
```

3. Call-site sweep (compiler-driven, all in this task's file list):
   - `App/ConversationView.swift` `.item` rows: `TimelineItemView(item: item, subagentSteps: item.toolCallID.flatMap { session.subagentTimelines[$0]?.count })`
   - `App/TimelineItemViews.swift` `ToolGroupRow` internal rows: `TimelineItemView(item: item)` — grouped runs exclude Task/Agent anchors, so no counts.
   - `App/HistoricalSessionView.swift`: see Step 6.
   - `App/InspectorView.swift` drill-down sub-rows: `TimelineItemView(item: item)` (no counts inside the panel — unchanged behavior).

- [ ] **Step 6: Historical wiring**

`App/HistoricalSessionView.swift`:

1. New state — the sub-timelines AND the Back trail (drill-down without Back is a one-way door; mirror ConversationView's trail, which Ben specifically asked for on the live side):

```swift
    @State private var subagentTimelines: [String: [TimelineItem]] = [:]
    @State private var inspectBackStack: [String] = []
```

`inspectAction` pushes the previous selection exactly like ConversationView's:

```swift
    private var inspectAction: InspectItemAction {
        InspectItemAction(id: "historical-\(summary.id)") { id in
            if let current = inspectedID, current != id {
                inspectBackStack.append(current)
            }
            inspectedID = id
            isInspectorPresented = true
        }
    }
```

and add the same trail-clearing modifier ConversationView carries (below `.inspector`):

```swift
        .onChange(of: inspectedID) { _, new in
            if new == nil { inspectBackStack.removeAll() }
        }
```

2. In `.task(id: summary.id)`, after the race-guarded `items = loaded` (T12): load the drill-down data with the same guard:

```swift
            let subs = await app.historicalSubagentTimelines(for: summary)
            guard !Task.isCancelled, requested == summary.id else { return }
            subagentTimelines = subs
```

(and reset `subagentTimelines = [:]` next to `items = nil` at the top.)
3. `inspectedItem` extends its search into sub-timelines (mirror ConversationView):

```swift
    private var inspectedItem: TimelineItem? {
        guard let inspectedID else { return nil }
        if let item = (items ?? []).first(where: { $0.id == inspectedID }) { return item }
        for timeline in subagentTimelines.values {
            if let item = timeline.first(where: { $0.id == inspectedID }) { return item }
        }
        return nil
    }
```

4. Rows pass counts, and the panel gets the slice (replacing `subagentItems: nil`):

```swift
                            TimelineItemView(item: item,
                                             subagentSteps: item.toolCallID
                                                 .flatMap { subagentTimelines[$0]?.count })
```

```swift
            InspectorPanel(item: inspectedItem,
                           subagentItems: inspectedID.flatMap { subagentTimelines[$0] },
                           inspectItem: inspectAction,
                           inspectedID: $inspectedID,
                           onBack: inspectBackStack.isEmpty ? nil : {
                               inspectedID = inspectBackStack.popLast()
                           })
```

(The panel keys `subagentItems` by the inspected TOOL id; `inspectedID` is a tool_use id exactly when a Task row was clicked, same convention as ConversationView. Reset `inspectBackStack = []` alongside `items = nil` in the `.task` body — a stale trail must not walk into another summary's items.)

- [ ] **Step 7: Run everything, build, smoke, commit**

Run: `swift build && swift test 2>&1 | tail -3` — 0 failures (3 new).
Run: `xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled -configuration Debug build 2>&1 | tail -2` — `** BUILD SUCCEEDED **`
Smoke: open the `fabled-smoke-scratch` historical session (the designated corpus — it has real subagents): its Task rows show "N steps" chips; clicking one opens the inspector with the subagent's rows; clicking a sub-row switches the panel to it. Live sessions unchanged.

```bash
git -C ~/Developer/Fabled add Sources App Tests
git -C ~/Developer/Fabled commit -m "feat: historical subagent drill-down from on-disk agent files + depth-2 guard + Agent-Agent fix (4b T14)"
```

---

## Task 15: Close-out — session identity root fix, docs, gate

The 4a rider (T10 quality review): `ConversationView` is reused across live-session switches, so session-scoped `@State` leaks and is being suppressed piecemeal (`.id` on the todo card, manual `.onChange` resets). Root fix: the composer draft moves into `ChatSession` (it *belongs* to the session — right now switching sessions carries your half-typed draft to the wrong session), the whole `ConversationView` gets `.id(session.id)`, the piecemeal resets come out, and the inspector's OPEN state hoists to RootView so it still survives switches (the deliberate T6 behavior). Then docs and the manual gate.

**Files:**
- Modify: `Sources/FabledCore/ChatSession.swift`
- Modify: `App/ComposerView.swift`, `App/ConversationView.swift`, `App/RootView.swift`
- Modify: `docs/superpowers/FOLLOWUPS.md`, this plan file
- Test: `Tests/FabledCoreTests/ChatSessionTests.swift`

- [ ] **Step 1: Failing test — the draft lives on the session**

Append to `Tests/FabledCoreTests/ChatSessionTests.swift`:

```swift
    func testDraftIsSessionState() {
        let (connection, _, _) = makeFakeConnection()
        let a = ChatSession(connection: connection,
                            workingDirectory: URL(fileURLWithPath: "/tmp/a"))
        let b = ChatSession(connection: connection,
                            workingDirectory: URL(fileURLWithPath: "/tmp/b"))
        a.draft = "half-typed thought"
        XCTAssertEqual(a.draft, "half-typed thought")
        XCTAssertEqual(b.draft, "", "drafts never leak across sessions")
    }
```

Run: `swift test --filter DraftIsSession 2>&1 | tail -3` — compile error expected.

- [ ] **Step 2: Implement**

`Sources/FabledCore/ChatSession.swift` — below `pendingGates`:

```swift
    /// The composer's unsent text. Session state, not view state: RootView
    /// swaps ConversationView across sessions, and a draft typed for session
    /// A must be waiting when Ben switches back (4a T10 reuse rider).
    public var draft = ""
```

`App/ComposerView.swift` — delete `@State private var draft = ""`, add `@Bindable var session2 = session`-style binding. Concretely: the view's `let session: ChatSession` becomes the binding source; in `body`, first line `@Bindable var session = session`, the TextField binds `$session.draft`, and `send()` becomes:

```swift
    private func send() {
        guard canSend else { return }
        session.send(session.draft)
        session.draft = ""
    }
```

with `canSend` reading `session.draft` instead of `draft`.

`App/RootView.swift` — the detail case for live sessions gains identity, and the inspector-open state moves up:

```swift
    @State private var isInspectorPresented = false
```

```swift
        case .live(let id):
            if let session = app.liveSessions.first(where: { $0.id == id }) {
                ConversationView(session: session,
                                 isInspectorPresented: $isInspectorPresented)
                    // Fresh hierarchy per session: kills every cross-session
                    // @State leak in one move (4a T10 rider). Presentation
                    // state that SHOULD survive switches lives up here.
                    .id(session.id)
            } else {
                WelcomeView { app.isPickingFolder = true }
            }
```

`App/ConversationView.swift`:

1. `@State private var isInspectorPresented = false` becomes `@Binding var isInspectorPresented: Bool` (init parameter after `session`).
2. DELETE the `.onChange(of: session.id)` reset block (`inspectedID`/`inspectBackStack`/`expandedGroups`) — recreation handles all of it; the comment block goes too.
3. DELETE the `.id(session.id)` on `TodoChecklistView` and its "Session-scoped identity" comment (superseded by the hierarchy identity).

- [ ] **Step 3: Run everything, build**

Run: `swift build && swift test 2>&1 | tail -3` — 0 failures.
Run: `xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled -configuration Debug build 2>&1 | tail -2` — `** BUILD SUCCEEDED **`

- [ ] **Step 4: State-identity smoke (scripted, coordinator)**

With two live sessions A and B: type into A's composer without sending → switch to B → its composer is empty → type into B → back to A → A's draft is intact. Open the inspector on A (⌥⌘I) → switch to B → the inspector stays open (panel shows "Nothing selected" — B has no selection yet, correct). Todo/task card collapse toggled in A doesn't affect B. Scroll position resetting on switch is accepted (ledgered below).

- [ ] **Step 5: Docs close-out**

`docs/superpowers/FOLLOWUPS.md`:
- Mark resolved (with commit refs): ConversationView reuse rider (T15 root fix — note scroll-position reset accepted), optimistic control ops (T6 ack correlation), `HistoricalSessionView.task(id:)` window (T12), `resume()` $HOME fallback (T12), "Agent Agent" cosmetic (T14), first-turn latency levers (T2 effort + T3 thinking), TodoWrite-dormancy (T4 task-tools re-plumb — TodoWrite path retained as legacy).
- Add new deferred items: `/remote-control` blocked upstream on 2.1.206 (`-p` environment-gated; re-probe each CLI update — `fixtures/probe_slashfx.py`); `TimelineDisplay.grouped` recomputes per render (profile before optimizing); notification banners need one-time permission approval on ad-hoc-signed builds; welcome-composer first message is dropped if the spawn fails (alert already shows).
- This plan file: flip the header to `**STATUS: EXECUTED — <date>. Manual gate pending.**` with the executed-amendments summary, 4a-style.

- [ ] **Step 6: Commit**

```bash
git -C ~/Developer/Fabled add Sources/FabledCore App Tests/FabledCoreTests docs/superpowers
git -C ~/Developer/Fabled commit -m "feat: session-identity root fix — draft on ChatSession, .id per session, inspector state hoisted; 4b docs close-out (4b T15)"
```

- [ ] **Step 7: Ben's manual gate (after merge — the human checklist)**

1. **Effort:** set preferred effort to `medium` (picker default section), start a new session — first visible text noticeably faster on a real question; flip `/effort low` mid-session via the picker and see the synthetic confirmation in the transcript; toolbar label tracks.
2. **Thinking:** a live turn shows the dimmed thinking tail + token ticker within a few seconds (the FASTER feel — compare against CD); finalized rows read "Thought — …" and open in the inspector; a historical session shows its thinking rows.
3. **Welcome inbox:** with one gated + one working session, deselect — needs-input floats first with the right preview text; every row opens the right thing; composer chip → type → session starts in that folder with the message sent; "Open folder…" fallback intact.
4. **Sidebar:** badges legible at a glance (shape + tooltip words, not color-only); needs-input rows pulse + tint; funnel: group-by-date, 7-day window (probe-junk projects vanish), sort-by-name, pin float — all survive relaunch.
5. **Notifications:** gate while in another app → banner; click focuses the session; a >30 s turn completing unfocused → banner with the status detail text; clean exits stay silent.
6. **Continue/Fork:** Continue twice on the same history row → one live session, second click selects it; Fork shows the fork notice; a deleted-folder session shows the home-folder notice.
7. **Step grouping:** a tool-heavy transcript reads as prose + summary rows; expand/collapse feels snappy; a streaming run never collapses mid-flight; Task rows with "N steps" chips never disappear into groups.
8. **Historical drill-down:** fabled-smoke-scratch session → Task chip → inspector sub-rows → sub-row click switches panel → Back walks the trail.
9. **Liveness:** during a long tool run, "Still working — no response for Ns…" appears after ~20 s of wire silence.
10. **Design:** bronze harp in the Dock; welcome backdrop + serif hierarchy reads as Fabled, not default SwiftUI; nothing else visually regressed. (Token VALUES are explicitly up for adjustment here — say the word and they move.)
11. **State identity:** drafts stay with their session; inspector-open survives switches; card collapse doesn't leak.
12. **Checklist card:** a session using TaskCreate/TaskUpdate shows the live checklist updating (create → in-progress italics → strikethrough complete).

---

## Execution notes for the coordinator

- **Per-task loop** (proven in 4a): fresh implementer subagent (Opus) per task → independent spec review (Sonnet, runs the tests itself) → quality review (superpowers:code-reviewer, Opus) → fix loops → commit → next. Templates: `~/.claude/plugins/cache/superpowers-dev/superpowers/5.0.6/skills/subagent-driven-development/*.md`.
- **Implementer prompts:** paste the FULL task text (code included) + the Conventions section + the worktree path. Forbid skill invocation. Require pasted real `swift test` output (verification-before-completion). Warn about `git -C` and the `rm -rf .build` SIGSEGV scar.
- **Worktree:** execute on a branch in `~/Developer/Fabled/.worktrees/plan-4b` (superpowers:using-git-worktrees), plan copy inside, 4a-style.
- **"Adapt to helper" markers** (T8/T9/T10/T12/T14 tests): AppModelTests/SessionStoreTests have established construction helpers this plan does not restate; implementers follow the file's existing pattern — the ASSERTIONS are the contract. Spec reviewers check the assertions landed, not the plumbing names.
- **Task order is execution order.** T1–T4 are Ben's FASTER priority — if anything forces a pause, pause after T4, not before. T5 gates the UI tasks (tokens must exist). T13/T14 are independent of T9–T12 and can slot earlier if a fix loop stalls elsewhere.
- **Live smokes:** T3/T9/T10/T11 end with smokes needing a live CLI; run them as ONE consolidated coordinator pass (computer-use) after T14, before T15 — same economics as 4a's consolidated smoke. Ben's T15 gate re-covers all of them.
- **Cost note:** effort/slash probes are zero-API-cost (num_turns 0); thinking/task smokes are haiku-cheap. Keep it that way.
- **Contract drift:** if a locked shape proves wrong during execution (e.g. `tool_use_result` moves), fix the plan + ledger in DECISIONS.md BEFORE dispatching the next task — the plan is the interface.




