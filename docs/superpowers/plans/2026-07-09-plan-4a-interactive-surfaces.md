# Interactive Surfaces & Side Inspector Implementation Plan (Fabled Plan 4a)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The conversation pane stops being a JSON viewer: AskUserQuestion renders as a native option picker, plan mode gets a real review sheet, Edit/Write render as diffs, TodoWrite becomes a pinned checklist, subagent traffic groups under its Task card, and all deep detail moves into a side inspector (Electron parity) instead of inline disclosure.

**Architecture:** All logic lands in `FabledCore` (`swift test`-covered): a pure `Diff` engine, parsed models for the two interactive tools (`QuestionPrompt`, `PlanApproval`), a `TodoItem` parser, an `InteractionGate` queue on `ChatSession` replacing the permissions-only queue, and subagent routing (`parentToolUseID` → per-parent sub-timelines) moved from a silent reducer drop to explicit `ChatSession` routing. The app target gains one architectural piece — the side inspector (`.inspector` on macOS 15) — and thin card views that route through it. ClaudeKit changes are minimal and fixture-pinned: `toolResult` learns its `parent_tool_use_id`, `PermissionRequest` learns `requires_user_interaction` and `tool_use_id`.

**Tech Stack:** Swift 6, SwiftUI (`.inspector`), Observation, SwiftPM + XcodeGen, XCTest. macOS 15+. Zero third-party dependencies (unchanged; ledgered).

**Roadmap context:** First of three Plan 4 sub-plans (ledgered 2026-07-09): **4a = this plan** (brief features 2, 3, 1, 4, 5, 17 + the tool-card expansion-state rider). 4b = shell & signals (welcome screen, sidebar status, history hygiene, resume semantics, notifications, liveness). 4c = lifecycle, terminal & presets. Brief: `2026-07-08-plan-4-full-surfaces-brief.md`. Spec: `../specs/2026-07-08-fabled-native-client-design.md`. Read `../COORDINATION.md` first if you are picking this up cold.

---

## Probe findings (2026-07-09, CLI 2.1.205)

All shapes below were verified live during plan-writing; the fixtures are ground truth. **Trust these over intuition.**

| Fixture | What it captures |
|---|---|
| `2026-07-09-askuserquestion-answer.jsonl` | full AskUserQuestion round-trip with answers |
| `2026-07-09-askuserquestion-echo.jsonl` | AskUserQuestion allowed with NO answers (skip path) |
| `2026-07-09-exitplanmode-approve.jsonl` | plan approval → `system/status` mode switch → implementation |
| `2026-07-09-exitplanmode-deny.jsonl` | plan rejection → `is_error` tool_result → revise → approve |
| `2026-07-09-longturn-signals.jsonl` | 13-API-turn autonomous run: exactly one `result` |
| `2026-07-09-badmodel-ack.jsonl` | `set_model` error ack; bogus `set_permission_mode` accepted |
| `2026-07-09-resume-collision-{A,B}.jsonl` | two processes on one session id (4b input, recorded here) |

1. **AskUserQuestion arrives as `can_use_tool`** with `tool_name:"AskUserQuestion"`, plus a field the spec census never saw: **`requires_user_interaction: true`** (also present on ExitPlanMode requests, absent on ordinary permission requests). The request also carries `tool_use_id` matching the `tool_use` block that the assistant message already streamed — the timeline already has a card for it.
   `input` shape: `{"questions":[{"question":String,"header":String,"options":[{"label":String,"description":String}],"multiSelect":Bool}]}` (1–4 questions, 2–4 options each).
2. **Answers return inside the allow response:** `{"behavior":"allow","updatedInput":{"questions":<echo>,"answers":{"<question text>":"<answer string>"}}}` — the `answers` record is keyed by **exact question text**; a multi-select answer is one **comma-separated string** (`"Small, Medium"`); any free-text string is a valid answer value (the TUI's own "Other" path uses this). The CLI then emits the tool_result `Your questions have been answered: …` and `tool_use_result` echoes `{questions, answers}` structurally.
3. **Skip = allow with no `answers`:** echoing `updatedInput` = request `input` verbatim produces tool_result `"The user did not answer the questions."` and `tool_use_result.answers = {}`. No error, turn continues. (Deny also works but reads as rejection — the GUI's Skip must use the echo path.)
4. **ExitPlanMode arrives as `can_use_tool`** with `tool_name:"ExitPlanMode"`, `requires_user_interaction:true`, and `input`: `{"plan":"<markdown>","planFilePath":"/Users/…/.claude/plans/<slug>.md"}` — the CLI writes the plan to a plan file *before* requesting approval; `planFilePath` may be absent in older flows, treat as optional.
5. **Plan approval:** allow (echoing input) makes the CLI emit **`{"type":"system","subtype":"status","status":null,"permissionMode":"default"}`** — the permission-mode switch is observable on the wire — followed by tool_result `"User has approved your plan. You can now start coding. …## Approved Plan (edited by user):\n<plan>"`. Passing an edited `updatedInput.plan` back is legal (the CLI labels the result "edited by user" — it does so even for a verbatim echo).
6. **Plan rejection:** deny-with-message produces tool_result with `is_error:true` and the deny message **verbatim** as the content; the session **stays in plan mode** (no `status` event), the model revises and calls ExitPlanMode again, and the denial is listed in that turn's `result.permission_denials`. ⚠️ Phrase the deny message as user feedback (`"The user rejected the plan: …"`): a bare imperative made haiku treat it as prompt injection in the probe.
7. **Ordinary permission requests grew fields** since the Plan 3 census (all optional): `decision_reason_type` (`"workingDir"`, `"subcommandResults"`…), `blocked_path`, and new `permission_suggestions` entry types **`{"type":"setMode","mode":"acceptEdits","destination":"session"}`** and `{"type":"addDirectories","directories":[…],"destination":"session"}` alongside the known `addRules`. Suggestions must keep flowing through as opaque `JSONValue` (echo-back contract unchanged).
8. **`result` fires exactly once per user turn**, even for a 13-API-turn autonomous run; `system/post_turn_summary` fires once right before it with `{status_category, status_detail, needs_action}` (notification fodder for 4b — nothing in 4a consumes it). There is **no wire event during long tool executions** — liveness (4b) must be client-timed.
9. **`system/status` may carry `permissionMode`** (finding 5) — but `set_permission_mode` itself validates **nothing** (a bogus mode string acks `success` and echoes back). The GUI must keep offering only known modes.
10. **TodoWrite input shape** (from the live probes and this very session's transcripts): `{"todos":[{"content":String,"status":"pending"|"in_progress"|"completed","activeForm":String}]}`. The whole list is re-sent on every call — latest call wins, no merging.
11. **Subagent traffic on the live wire** shares the parent's stream with `parent_tool_use_id` set: `stream_event` and `assistant` events already expose it (decoded since Plan 3), and **`user` (tool_result) events carry it too — but ClaudeKit currently drops it** for tool results (`AgentEventDecoder.swift:24-34` never reads it). Task 1 fixes that.

## Contract amendments vs the brief (conscious; already consistent with DECISIONS.md)

- **No new TimelineItem cases for questions or plans.** The assistant's own `tool_use` block already puts an AskUserQuestion/ExitPlanMode card in the timeline, and the CLI's tool_result fills it with the outcome ("Your questions have been answered: …" / "User has approved your plan…"). The interactive UI is *composer-slot state* (`ChatSession.pendingGates`), not timeline vocabulary. The reducer stops emitting `.permission` rows for these two tools only.
- **`ChatSession.pendingPermissions` is replaced by `pendingGates: [InteractionGate]`** (permission | question | planApproval). `pendingPermission` → `pendingGate`. Consumers updated in this plan: `RootView` dock badge, `ComposerView` card slot; `activityState` logic unchanged in meaning (any gate = `.needsApproval`).
- **`AgentEvent.toolResult` gains the parent id:** `case toolResult([ToolResult], parentToolUseID: String?)`. Source-breaking for pattern matches; every match site is updated in Task 1.
- **The reducer no longer silently drops parented events** — routing (main vs subagent timeline) moves up to `ChatSession`, which is the only caller that sees live parented traffic. `TimelineReducer.items(fromTranscript:)` keeps skipping sidechain lines (on-disk analog is Plan 4b, feature 15).
- **Diff rendering is git-free** per the brief: computed from `old_string`/`new_string` (Edit), `content` (Write, rendered as all-insertions), `edits[]` (MultiEdit, hunk per edit).
- **The side inspector replaces inline disclosure** for tool/raw detail (gate feedback). Collapsed cards keep a one-line summary; clicking opens the inspector. The `@State`-expansion-reset rider is resolved by deletion — there is no per-row expansion state anymore.

## Conventions for implementing agents

- Repo root: `~/Developer/Fabled`. All commands run from there. (Bash `cd` state can reset between calls — prefix git commands with `git -C ~/Developer/Fabled` or re-`cd` per call.)
- Package build/test: `swift build && swift test` — green before **every** commit. Never commit red.
- App build: `xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled -configuration Debug build` (expected final line `** BUILD SUCCEEDED **`). Never hand-edit `Fabled.xcodeproj` — generated, gitignored; `project.yml` is source of truth. No `project.yml` changes are needed in this plan.
- Swift 6 strict concurrency is ON. Everything public is `Sendable` (or `@MainActor`). View models `@MainActor @Observable`; views stay logic-free.
- Zero third-party dependencies. AttributedString for markdown (inline-only; ledgered).
- Protocol ground truth: the fixtures in the table above + "Probe findings". When a shape is in question, open the fixture and look. Do not guess.
- Tolerant decoding is load-bearing: unknown types keep flowing through `.unknown`/`.system`/`.other`, never throw.
- `fixtures/` content is real data from Ben's machine, approved for **local** use only. Do not publish or quote transcript content in commit messages.
- All new tests are offline. No new live tests in this plan (the fixtures pin every shape).
- UI tasks (6–12) end with a build + scripted smoke check instead of unit tests; anything with logic goes in FabledCore where `swift test` reaches it.
- Existing tests stay green. Tasks that deliberately change existing tests say so explicitly (Tasks 1, 4, 5 do); any other breakage is a bug in your change.

## File structure

```
Sources/ClaudeKit/
  AgentEvent.swift               # MODIFY T1: toolResult case + PermissionRequest fields + parentToolUseID helper
  AgentEventDecoder.swift        # MODIFY T1: decode parent_tool_use_id on user events
Sources/FabledCore/
  Diff.swift                     # CREATE T2: line diff engine + ToolDiff extraction
  InteractionModels.swift        # CREATE T3: QuestionPrompt, PlanApproval, TodoItem
  ToolCallSummary.swift          # MODIFY T3: AskUserQuestion/ExitPlanMode/TodoWrite summaries
  TimelineReducer.swift          # MODIFY T4: gate-tool filter; parent guards removed
  ChatSession.swift              # MODIFY T5: pendingGates, answer/skip/approve/reject, status→mode, todos, subagent routing
App/
  InspectorView.swift            # CREATE T6: inspector panel + content routing
  TimelineItemViews.swift        # MODIFY T6/T7/T11: compact rows, diff chips, Task badges
  ConversationView.swift         # MODIFY T6/T9/T10: inspector wiring, plan sheet, todo card
  HistoricalSessionView.swift    # MODIFY T6: inspector wiring (read-only)
  RootView.swift                 # MODIFY T5-consumer: dock badge counts gates
  ComposerView.swift             # MODIFY T8/T9: gate-card slot switch
  QuestionCardView.swift         # CREATE T8: option picker card
  PlanApprovalViews.swift        # CREATE T9: composer card + review sheet
  TodoChecklistView.swift        # CREATE T10: pinned checklist card
  Theme.swift                    # MODIFY T12: content-width tokens
Tests/ClaudeKitTests/
  AgentEventDecoderTests.swift   # MODIFY T1: parent id + new-field tests
  Fixtures.swift                 # (no change; loader already generic)
Tests/FabledCoreTests/
  DiffTests.swift                # CREATE T2
  InteractionModelTests.swift    # CREATE T3
  TimelineReducerTests.swift     # MODIFY T4/T5: gate filter + subagent routing
  ChatSessionTests.swift         # MODIFY T5: gates, status, todos, subagents
```

---
## Task 1: ClaudeKit wire additions — tool-result parentage + interactive-request fields

The live wire tags subagent traffic with `parent_tool_use_id` on three event types; ClaudeKit decodes it on two (probe finding 11). And `can_use_tool` requests for interactive tools carry `requires_user_interaction` + `tool_use_id` (finding 1) that the gate UI needs.

**Files:**
- Modify: `Sources/ClaudeKit/AgentEvent.swift`
- Modify: `Sources/ClaudeKit/AgentEventDecoder.swift:24-34`
- Modify: `Sources/FabledCore/TimelineReducer.swift:14-17` (match-site update only)
- Test: `Tests/ClaudeKitTests/AgentEventDecoderTests.swift`

- [ ] **Step 1: Write the failing tests** — append to `AgentEventDecoderTests.swift`:

```swift
    func testToolResultCarriesParentToolUseID() throws {
        let event = try AgentEventDecoder.decode(Data(
            #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"done","is_error":false}]},"parent_tool_use_id":"task-99","uuid":"u1"}"#
            .utf8))
        guard case .toolResult(let results, "task-99") = event else {
            return XCTFail("expected parented toolResult, got \(event)")
        }
        XCTAssertEqual(results.first?.toolUseID, "t1")
    }

    func testToolResultWithoutParentDecodesNil() throws {
        let event = try AgentEventDecoder.decode(Data(
            #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]},"parent_tool_use_id":null,"uuid":"u1"}"#
            .utf8))
        guard case .toolResult(_, nil) = event else {
            return XCTFail("got \(event)")
        }
    }

    func testEventParentToolUseIDHelper() throws {
        let parented = try AgentEventDecoder.decode(Data(
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"hi"}]},"parent_tool_use_id":"task-7","uuid":"a1"}"#
            .utf8))
        XCTAssertEqual(parented.parentToolUseID, "task-7")
        let main = try AgentEventDecoder.decode(Data(
            #"{"type":"result","subtype":"success","is_error":false}"#.utf8))
        XCTAssertNil(main.parentToolUseID)
    }

    /// Shape pinned from fixtures/2026-07-09-askuserquestion-answer.jsonl.
    func testPermissionRequestInteractiveFields() throws {
        let lines = try Fixtures.lines("2026-07-09-askuserquestion-answer.jsonl")
        let events = try lines.map { try AgentEventDecoder.decode($0) }
        let request = events.compactMap { event -> PermissionRequest? in
            if case .controlRequest(let control) = event { return PermissionRequest(control) }
            return nil
        }.first
        let unwrapped = try XCTUnwrap(request, "fixture must contain a can_use_tool request")
        XCTAssertEqual(unwrapped.toolName, "AskUserQuestion")
        XCTAssertTrue(unwrapped.requiresUserInteraction)
        XCTAssertNotNil(unwrapped.toolUseID)
        XCTAssertNotNil(unwrapped.input["questions"]?.arrayValue)
    }

    /// Ordinary Bash permission: interactive fields default off/nil.
    func testPermissionRequestOrdinaryDefaults() throws {
        let control = ControlRequest(
            requestID: "r1", subtype: "can_use_tool",
            payload: try JSONDecoder().decode(JSONValue.self, from: Data(
                #"{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"ls"}}"#.utf8)))
        let request = try XCTUnwrap(PermissionRequest(control))
        XCTAssertFalse(request.requiresUserInteraction)
        XCTAssertNil(request.toolUseID)
    }
```

(`Fixtures.lines(_ name:) throws -> [Data]` is the existing ClaudeKitTests loader in `Tests/ClaudeKitTests/Fixtures.swift` — verified, use as-is.)

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter AgentEventDecoderTests 2>&1 | tail -5`
Expected: compile errors (`toolResult` pattern arity, missing `parentToolUseID`, missing fields) — a compile failure is this step's "red".

- [ ] **Step 3: Implement.** In `Sources/ClaudeKit/AgentEvent.swift`:

Replace line 18:
```swift
    case toolResult([ToolResult], parentToolUseID: String?)
```

Append after the `AgentEvent` enum (below line 25):
```swift
public extension AgentEvent {
    /// Non-nil when the event belongs to a subagent (Task tool) side-stream.
    /// The three event types the CLI tags: assistant, stream_event, user.
    var parentToolUseID: String? {
        switch self {
        case .assistant(let message): message.parentToolUseID
        case .streamEvent(let stream): stream.parentToolUseID
        case .toolResult(_, let parent): parent
        default: nil
        }
    }
}
```

In `PermissionRequest` add two stored properties after `suggestions` (line 71) and parse them in `init?` after the `suggestions` line (line 82):
```swift
    /// The tool_use block this request gates — present on interactive tools.
    public let toolUseID: String?
    /// True for AskUserQuestion/ExitPlanMode-style requests that want a
    /// dedicated UI, not an allow/deny prompt (probe finding 1).
    public let requiresUserInteraction: Bool
```
```swift
        self.toolUseID = request.payload["tool_use_id"]?.stringValue
        self.requiresUserInteraction =
            request.payload["requires_user_interaction"]?.boolValue ?? false
```

In `Sources/ClaudeKit/AgentEventDecoder.swift` replace line 34 (`return .toolResult(results)`):
```swift
            return .toolResult(results,
                               parentToolUseID: raw["parent_tool_use_id"]?.stringValue)
```

In `Sources/FabledCore/TimelineReducer.swift` update the single match site (line 14):
```swift
        case .toolResult(let results, _):
```

- [ ] **Step 4: Fix remaining match sites the compiler finds.** `swift build 2>&1 | grep error` — any test or source pattern-matching `.toolResult(` with one associated value needs the second binding added (`Tests/FabledCoreTests/TimelineReducerTests.swift` constructs events via JSON, so most tests are untouched). Do not change behavior anywhere — bind and ignore (`_`).

- [ ] **Step 5: Run the full suite**

Run: `swift build && swift test 2>&1 | grep "Executed"`
Expected: all tests pass, 0 failures (count grows by 5).

- [ ] **Step 6: Commit**

```bash
git -C ~/Developer/Fabled add -A Sources Tests
git -C ~/Developer/Fabled commit -m "feat(claudekit): tool-result parentage + interactive permission fields"
```

---

## Task 2: Diff engine (FabledCore, pure)

Git-free unified diff computed from tool inputs (brief feature 1). Line-based LCS; falls back to delete-block/insert-block beyond a size cap so a pathological input can't freeze the UI thread that calls this.

**Files:**
- Create: `Sources/FabledCore/Diff.swift`
- Test: `Tests/FabledCoreTests/DiffTests.swift`

- [ ] **Step 1: Write the failing tests** — create `Tests/FabledCoreTests/DiffTests.swift`:

```swift
import XCTest
import ClaudeKit
@testable import FabledCore

final class DiffTests: XCTestCase {
    func testEqualStringsProduceOnlyContext() {
        let lines = Diff.lines(old: "a\nb", new: "a\nb")
        XCTAssertEqual(lines.map(\.kind), [.context, .context])
    }

    func testSimpleReplacement() {
        let lines = Diff.lines(old: "a\nb\nc", new: "a\nX\nc")
        XCTAssertEqual(lines.map(\.kind),
                       [.context, .deletion, .insertion, .context])
        XCTAssertEqual(lines[1].text, "b")
        XCTAssertEqual(lines[2].text, "X")
    }

    func testInsertionOnly() {
        let lines = Diff.lines(old: "a", new: "a\nb")
        XCTAssertEqual(lines.map(\.kind), [.context, .insertion])
    }

    func testDeletionOnly() {
        let lines = Diff.lines(old: "a\nb", new: "b")
        XCTAssertEqual(lines.map(\.kind), [.deletion, .context])
    }

    func testEmptyOldIsAllInsertions() {
        let lines = Diff.lines(old: "", new: "x\ny")
        XCTAssertEqual(lines.map(\.kind), [.insertion, .insertion])
    }

    func testCounts() {
        let lines = Diff.lines(old: "a\nb\nc", new: "a\nX\nY\nc")
        let counts = Diff.counts(lines)
        XCTAssertEqual(counts.added, 2)
        XCTAssertEqual(counts.removed, 1)
    }

    func testOversizeFallsBackToBlocks() {
        let old = Array(repeating: "same", count: 600).joined(separator: "\n")
        let new = old + "\nextra"
        let lines = Diff.lines(old: old, new: new)
        // Above the LCS cap the whole thing renders as delete-block + insert-block;
        // correctness (every line present) matters, minimality doesn't.
        XCTAssertEqual(lines.filter { $0.kind == .deletion }.count, 600)
        XCTAssertEqual(lines.filter { $0.kind == .insertion }.count, 601)
    }

    // MARK: ToolDiff extraction

    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    func testEditExtraction() throws {
        let input = try json(
            #"{"file_path":"/tmp/a.swift","old_string":"let x = 1","new_string":"let x = 2"}"#)
        let diff = try XCTUnwrap(ToolDiff.from(toolName: "Edit", input: input))
        XCTAssertEqual(diff.filePath, "/tmp/a.swift")
        XCTAssertEqual(diff.hunks.count, 1)
        XCTAssertEqual(diff.added, 1)
        XCTAssertEqual(diff.removed, 1)
    }

    func testWriteExtractionIsAllInsertions() throws {
        let input = try json(#"{"file_path":"/tmp/b.txt","content":"one\ntwo"}"#)
        let diff = try XCTUnwrap(ToolDiff.from(toolName: "Write", input: input))
        XCTAssertEqual(diff.added, 2)
        XCTAssertEqual(diff.removed, 0)
    }

    func testMultiEditExtractionOneHunkPerEdit() throws {
        let input = try json(
            #"{"file_path":"/tmp/c.swift","edits":[{"old_string":"a","new_string":"b"},{"old_string":"c\nd","new_string":"c"}]}"#)
        let diff = try XCTUnwrap(ToolDiff.from(toolName: "MultiEdit", input: input))
        XCTAssertEqual(diff.hunks.count, 2)
        // hunk 1: a→b = 1 deletion + 1 insertion; hunk 2: "c\nd"→"c" =
        // 1 context (c) + 1 deletion (d). Totals: +1 −2.
        XCTAssertEqual(diff.added, 1)
        XCTAssertEqual(diff.removed, 2)
    }

    func testNonDiffToolReturnsNil() throws {
        XCTAssertNil(ToolDiff.from(toolName: "Bash",
                                   input: try json(#"{"command":"ls"}"#)))
        XCTAssertNil(ToolDiff.from(toolName: "Edit", input: .null))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter DiffTests 2>&1 | tail -3`
Expected: compile failure (`Diff` unresolved).

- [ ] **Step 3: Implement** — create `Sources/FabledCore/Diff.swift`:

```swift
import ClaudeKit

public struct DiffLine: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case context, insertion, deletion }
    public let kind: Kind
    public let text: String
    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }
}

/// Line-based diff, no git. LCS (dynamic programming) up to a size cap;
/// beyond it, a delete-block/insert-block rendering — always correct,
/// just not minimal. Inputs are tool-call strings (old_string/new_string),
/// so the cap is rarely hit.
public enum Diff {
    /// Above this many lines on either side, skip LCS (O(n·m) table).
    static let lcsCap = 500

    public static func lines(old: String, new: String) -> [DiffLine] {
        let oldLines = split(old)
        let newLines = split(new)
        if oldLines.count > lcsCap || newLines.count > lcsCap {
            return oldLines.map { DiffLine(kind: .deletion, text: $0) }
                + newLines.map { DiffLine(kind: .insertion, text: $0) }
        }
        // LCS table: table[i][j] = LCS length of oldLines[i...] vs newLines[j...]
        var table = Array(
            repeating: Array(repeating: 0, count: newLines.count + 1),
            count: oldLines.count + 1)
        for i in stride(from: oldLines.count - 1, through: 0, by: -1) {
            for j in stride(from: newLines.count - 1, through: 0, by: -1) {
                table[i][j] = oldLines[i] == newLines[j]
                    ? table[i + 1][j + 1] + 1
                    : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var result: [DiffLine] = []
        var i = 0, j = 0
        while i < oldLines.count, j < newLines.count {
            if oldLines[i] == newLines[j] {
                result.append(DiffLine(kind: .context, text: oldLines[i]))
                i += 1; j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                result.append(DiffLine(kind: .deletion, text: oldLines[i]))
                i += 1
            } else {
                result.append(DiffLine(kind: .insertion, text: newLines[j]))
                j += 1
            }
        }
        while i < oldLines.count {
            result.append(DiffLine(kind: .deletion, text: oldLines[i])); i += 1
        }
        while j < newLines.count {
            result.append(DiffLine(kind: .insertion, text: newLines[j])); j += 1
        }
        return result
    }

    public static func counts(_ lines: [DiffLine]) -> (added: Int, removed: Int) {
        (lines.count { $0.kind == .insertion },
         lines.count { $0.kind == .deletion })
    }

    /// "" → [] (not [""]) so empty old_string means pure insertion.
    private static func split(_ text: String) -> [String] {
        text.isEmpty ? [] : text.components(separatedBy: "\n")
    }
}

/// A tool call rendered as a diff: Edit (one hunk), MultiEdit (hunk per
/// edit), Write (new content, all insertions). Anything else → nil.
public struct ToolDiff: Equatable, Sendable {
    public let filePath: String
    public let hunks: [[DiffLine]]
    public let added: Int
    public let removed: Int

    public static func from(toolName: String, input: JSONValue) -> ToolDiff? {
        guard let filePath = input["file_path"]?.stringValue else { return nil }
        let hunks: [[DiffLine]]
        switch toolName {
        case "Edit":
            guard let old = input["old_string"]?.stringValue,
                  let new = input["new_string"]?.stringValue else { return nil }
            hunks = [Diff.lines(old: old, new: new)]
        case "Write":
            guard let content = input["content"]?.stringValue else { return nil }
            hunks = [Diff.lines(old: "", new: content)]
        case "MultiEdit":
            guard let edits = input["edits"]?.arrayValue, !edits.isEmpty else { return nil }
            hunks = edits.compactMap { edit in
                guard let old = edit["old_string"]?.stringValue,
                      let new = edit["new_string"]?.stringValue else { return nil }
                return Diff.lines(old: old, new: new)
            }
            guard !hunks.isEmpty else { return nil }
        default:
            return nil
        }
        let totals = hunks.reduce(into: (added: 0, removed: 0)) { acc, hunk in
            let counts = Diff.counts(hunk)
            acc.added += counts.added
            acc.removed += counts.removed
        }
        return ToolDiff(filePath: filePath, hunks: hunks,
                        added: totals.added, removed: totals.removed)
    }
}
```

(`Array.count(where:)` requires the Swift 6 standard library shipped with Xcode 16 — already used elsewhere in the repo; if the compiler objects, use `filter{}.count`.)

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter DiffTests 2>&1 | tail -3`
Expected: all DiffTests pass (fix the MultiEdit arithmetic per the note — the structure assertions must stay).

- [ ] **Step 5: Full suite + commit**

```bash
swift build && swift test 2>&1 | grep "Executed"
git -C ~/Developer/Fabled add Sources/FabledCore/Diff.swift Tests/FabledCoreTests/DiffTests.swift
git -C ~/Developer/Fabled commit -m "feat(core): git-free line diff engine + tool-input extraction"
```

---

## Task 3: Interactive-tool models + summaries (FabledCore, pure)

Parsed views over the two `requires_user_interaction` tools and TodoWrite, plus collapsed-card summaries for all three. Shapes pinned by probe findings 1, 4, 10.

**Files:**
- Create: `Sources/FabledCore/InteractionModels.swift`
- Modify: `Sources/FabledCore/ToolCallSummary.swift`
- Test: `Tests/FabledCoreTests/InteractionModelTests.swift`

- [ ] **Step 1: Write the failing tests** — create `Tests/FabledCoreTests/InteractionModelTests.swift`:

```swift
import XCTest
import ClaudeKit
@testable import FabledCore

final class InteractionModelTests: XCTestCase {
    private func permissionRequest(fixture: String) throws -> PermissionRequest {
        let events = try CoreFixtures.events(fixture)
        let request = events.compactMap { event -> PermissionRequest? in
            if case .controlRequest(let control) = event { return PermissionRequest(control) }
            return nil
        }.first
        return try XCTUnwrap(request)
    }

    func testQuestionPromptParsesFixture() throws {
        let request = try permissionRequest(fixture: "2026-07-09-askuserquestion-answer.jsonl")
        let prompt = try XCTUnwrap(QuestionPrompt(request))
        XCTAssertEqual(prompt.questions.count, 2)
        XCTAssertEqual(prompt.questions[0].text, "Which color do you prefer?")
        XCTAssertEqual(prompt.questions[0].header, "Color")
        XCTAssertFalse(prompt.questions[0].multiSelect)
        XCTAssertEqual(prompt.questions[0].options.map(\.label), ["Red", "Blue"])
        XCTAssertEqual(prompt.questions[0].options[0].detail, "The color red")
        XCTAssertTrue(prompt.questions[1].multiSelect)
    }

    func testQuestionPromptRejectsOtherTools() throws {
        let request = try permissionRequest(fixture: "2026-07-09-exitplanmode-approve.jsonl")
        // First can_use_tool in that fixture is Bash — definitely not a question.
        XCTAssertNil(QuestionPrompt(request))
    }

    /// The answer payload is the request input + answers keyed by question
    /// text, multi-select joined with ", " (probe finding 2).
    func testAnsweredInputShape() throws {
        let request = try permissionRequest(fixture: "2026-07-09-askuserquestion-answer.jsonl")
        let prompt = try XCTUnwrap(QuestionPrompt(request))
        let updated = prompt.answeredInput([
            "Which color do you prefer?": "Blue",
            "Which sizes do you want?": "Small, Large",
        ])
        XCTAssertEqual(updated["questions"], request.input["questions"])
        XCTAssertEqual(updated["answers"]?["Which color do you prefer?"]?.stringValue, "Blue")
        XCTAssertEqual(updated["answers"]?["Which sizes do you want?"]?.stringValue, "Small, Large")
    }

    func testPlanApprovalParsesFixture() throws {
        let events = try CoreFixtures.events("2026-07-09-exitplanmode-approve.jsonl")
        let approval = events.compactMap { event -> PlanApproval? in
            guard case .controlRequest(let control) = event,
                  let request = PermissionRequest(control) else { return nil }
            return PlanApproval(request)
        }.first
        let unwrapped = try XCTUnwrap(approval)
        XCTAssertTrue(unwrapped.plan.hasPrefix("# Plan:"))
        XCTAssertNotNil(unwrapped.planFilePath)
    }

    func testPlanApprovalRejectsOtherTools() throws {
        let request = try permissionRequest(fixture: "2026-07-09-askuserquestion-answer.jsonl")
        XCTAssertNil(PlanApproval(request))
    }

    func testTodoItemsParse() throws {
        let input = try JSONDecoder().decode(JSONValue.self, from: Data(
            #"{"todos":[{"content":"Write tests","status":"completed","activeForm":"Writing tests"},{"content":"Implement","status":"in_progress","activeForm":"Implementing"},{"content":"Commit","status":"pending","activeForm":"Committing"}]}"#
            .utf8))
        let todos = TodoItem.list(from: input)
        XCTAssertEqual(todos.count, 3)
        XCTAssertEqual(todos[0].status, .completed)
        XCTAssertEqual(todos[1].status, .inProgress)
        XCTAssertEqual(todos[1].activeForm, "Implementing")
        XCTAssertEqual(todos[2].status, .pending)
    }

    func testTodoUnknownStatusIsPending() throws {
        let input = try JSONDecoder().decode(JSONValue.self, from: Data(
            #"{"todos":[{"content":"x","status":"someday","activeForm":"x"}]}"#.utf8))
        XCTAssertEqual(TodoItem.list(from: input).first?.status, .pending)
    }

    // MARK: summaries

    func testSummaries() throws {
        let question = try JSONDecoder().decode(JSONValue.self, from: Data(
            #"{"questions":[{"question":"Which color?","header":"Color","options":[],"multiSelect":false}]}"#.utf8))
        XCTAssertEqual(ToolCallSummary.summarize(name: "AskUserQuestion", input: question),
                       "Which color?")
        let plan = try JSONDecoder().decode(JSONValue.self, from: Data(
            #"{"plan":"# Add README\nmore"}"#.utf8))
        XCTAssertEqual(ToolCallSummary.summarize(name: "ExitPlanMode", input: plan),
                       "# Add README")
        let todos = try JSONDecoder().decode(JSONValue.self, from: Data(
            #"{"todos":[{"content":"a","status":"completed","activeForm":"a"},{"content":"b","status":"pending","activeForm":"b"}]}"#.utf8))
        XCTAssertEqual(ToolCallSummary.summarize(name: "TodoWrite", input: todos),
                       "1/2 done")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter InteractionModelTests 2>&1 | tail -3`
Expected: compile failure (`QuestionPrompt` unresolved).

- [ ] **Step 3: Implement** — create `Sources/FabledCore/InteractionModels.swift`:

```swift
import ClaudeKit

/// AskUserQuestion, parsed. Wraps the originating PermissionRequest — the
/// answer travels back as that request's allow response (probe finding 2).
public struct QuestionPrompt: Equatable, Sendable, Identifiable {
    public struct Option: Equatable, Sendable {
        public let label: String
        public let detail: String
    }
    public struct Question: Equatable, Sendable, Identifiable {
        public let text: String
        public let header: String
        public let multiSelect: Bool
        public let options: [Option]
        public var id: String { text }
    }

    public let request: PermissionRequest
    public let questions: [Question]
    public var id: String { request.requestID }

    public init?(_ request: PermissionRequest) {
        guard request.toolName == "AskUserQuestion",
              let rawQuestions = request.input["questions"]?.arrayValue,
              !rawQuestions.isEmpty else { return nil }
        self.request = request
        self.questions = rawQuestions.compactMap { raw in
            guard let text = raw["question"]?.stringValue else { return nil }
            return Question(
                text: text,
                header: raw["header"]?.stringValue ?? "",
                multiSelect: raw["multiSelect"]?.boolValue ?? false,
                options: (raw["options"]?.arrayValue ?? []).compactMap { option in
                    guard let label = option["label"]?.stringValue else { return nil }
                    return Option(label: label,
                                  detail: option["description"]?.stringValue ?? "")
                })
        }
        guard !questions.isEmpty else { return nil }
    }

    /// The allow payload: original input + answers keyed by exact question
    /// text; multi-select answers are ", "-joined by the caller. An empty
    /// record is the Skip path (probe finding 3) — omit `answers` entirely.
    public func answeredInput(_ answers: [String: String]) -> JSONValue {
        guard var object = request.input.objectValue else { return request.input }
        if !answers.isEmpty {
            object["answers"] = .object(answers.mapValues { .string($0) })
        }
        return .object(object)
    }
}

/// ExitPlanMode, parsed (probe finding 4).
public struct PlanApproval: Equatable, Sendable, Identifiable {
    public let request: PermissionRequest
    public let plan: String
    public let planFilePath: String?
    public var id: String { request.requestID }

    public init?(_ request: PermissionRequest) {
        guard request.toolName == "ExitPlanMode",
              let plan = request.input["plan"]?.stringValue else { return nil }
        self.request = request
        self.plan = plan
        self.planFilePath = request.input["planFilePath"]?.stringValue
    }
}

/// One TodoWrite entry (probe finding 10). The CLI re-sends the whole list
/// per call — latest list wins.
public struct TodoItem: Equatable, Sendable, Identifiable {
    public enum Status: Equatable, Sendable {
        case pending, inProgress, completed
    }
    public let content: String
    public let status: Status
    public let activeForm: String
    public var id: String { content }

    public static func list(from input: JSONValue) -> [TodoItem] {
        (input["todos"]?.arrayValue ?? []).compactMap { raw in
            guard let content = raw["content"]?.stringValue else { return nil }
            let status: Status = switch raw["status"]?.stringValue {
            case "completed": .completed
            case "in_progress": .inProgress
            default: .pending  // tolerant: unknown status renders as pending
            }
            return TodoItem(content: content, status: status,
                            activeForm: raw["activeForm"]?.stringValue ?? content)
        }
    }
}
```

If `JSONValue` has no `objectValue` accessor returning `[String: JSONValue]?`, check `Sources/ClaudeKit/JSONValue.swift` — the Explore census says it exists; if the name differs, adapt the call site.

In `Sources/FabledCore/ToolCallSummary.swift`, extend the `switch name` (insert before `default:`):

```swift
        case "AskUserQuestion":
            input["questions"]?.arrayValue?.first?["question"]?.stringValue
        case "ExitPlanMode": input["plan"]?.stringValue
        case "TodoWrite": todoSummary(input)
```

and add below `summarize`:

```swift
    private static func todoSummary(_ input: JSONValue) -> String? {
        let todos = TodoItem.list(from: input)
        guard !todos.isEmpty else { return nil }
        let done = todos.count { $0.status == .completed }
        return "\(done)/\(todos.count) done"
    }
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter InteractionModelTests 2>&1 | tail -3`
Expected: all pass.

- [ ] **Step 5: Full suite + commit**

```bash
swift build && swift test 2>&1 | grep "Executed"
git -C ~/Developer/Fabled add Sources/FabledCore Tests/FabledCoreTests
git -C ~/Developer/Fabled commit -m "feat(core): QuestionPrompt/PlanApproval/TodoItem models + gate-tool summaries"
```

---
## Task 4: Reducer — interactive-gate filter + explicit parent routing contract

Two behavior changes, both small: (a) `can_use_tool` requests with `requires_user_interaction` stop producing `.permission` timeline rows (their tool_use card already tells the story; the dedicated UI lives in the composer slot), and (b) the reducer stops silently dropping parented events — the *caller* routes main vs subagent traffic (ChatSession does so in Task 5; transcript replay already filters sidechain lines upstream).

**Files:**
- Modify: `Sources/FabledCore/TimelineReducer.swift`
- Test: `Tests/FabledCoreTests/TimelineReducerTests.swift`

- [ ] **Step 1: Write the failing tests** — append to `TimelineReducerTests.swift`:

```swift
    func testInteractiveGateRequestsRenderNoPermissionRow() throws {
        let items = try reduceAll([
            #"{"type":"control_request","request_id":"q1","request":{"subtype":"can_use_tool","tool_name":"AskUserQuestion","input":{"questions":[{"question":"Color?","header":"C","options":[{"label":"Red","description":""}],"multiSelect":false}]},"requires_user_interaction":true}}"#,
        ])
        XCTAssertTrue(items.isEmpty,
                      "interactive gates render in the composer slot, not the timeline")
    }

    func testOrdinaryPermissionStillRendersRow() throws {
        let items = try reduceAll([
            #"{"type":"control_request","request_id":"p1","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"rm x"}}}"#,
        ])
        guard case .permission("p1", _, nil) = items.first else {
            return XCTFail("got \(items)")
        }
    }

    /// New contract: reduce() takes events as given — the CALLER routes
    /// subagent traffic. A parented event handed to reduce() is rendered.
    func testReducerNoLongerDropsParentedEvents() throws {
        let items = try reduceAll([
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"sub"}]},"parent_tool_use_id":"task-1","uuid":"a1"}"#,
        ])
        XCTAssertEqual(items.count, 1, "routing is the caller's job now")
    }
```

**Delete the existing `testSubagentTrafficIsIgnored`** (`TimelineReducerTests.swift:84-90`) — it pins the old drop-in-reducer behavior that this task deliberately inverts ("grouped UI is Plan 4" — this is that plan). `testReducerNoLongerDropsParentedEvents` is its replacement.

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter TimelineReducerTests 2>&1 | tail -4`
Expected: `testInteractiveGateRequestsRenderNoPermissionRow` and `testReducerNoLongerDropsParentedEvents` FAIL (row appended / event dropped). `testOrdinaryPermissionStillRendersRow` passes already.

- [ ] **Step 3: Implement.** In `Sources/FabledCore/TimelineReducer.swift`:

Replace the `.controlRequest` case body (lines 20-26) with:

```swift
        case .controlRequest(let request):
            if let permission = PermissionRequest(request),
               !permission.requiresUserInteraction {
                items.append(.permission(id: permission.requestID,
                                         request: permission, resolution: nil))
            }
            // Interactive gates (AskUserQuestion, ExitPlanMode) render as
            // composer-slot cards via ChatSession.pendingGates; their
            // tool_use card + tool_result already narrate the outcome here.
            // Other control requests (hook_callback, mcp_message) stay
            // plumbing, not conversation.
```

Delete the two parent guards:
- line 96: `guard stream.parentToolUseID == nil else { return }  // subagent traffic: Plan 4`
- line 118: `guard message.parentToolUseID == nil else { return }`

and update the doc comment above `reduce` (line 6-7) to state the new contract:

```swift
/// Pure translation from protocol events to UI items. This is where
/// correctness lives — every behavior is replay-tested against recorded
/// fixtures. Routing is the caller's job: events with a parentToolUseID
/// belong to a subagent sub-timeline (ChatSession routes them); reduce()
/// renders whatever it is handed.
```

- [ ] **Step 4: Run to verify pass, watch for collateral**

Run: `swift test 2>&1 | grep -E "Executed|failed"`
Expected: all pass. If a replay test over the transcript fixtures now shows extra items, the fixture contains sidechain events that `items(fromTranscript:)` no longer filters — it must keep filtering via `context.isSidechain` (it does, line 84); investigate before touching anything.

- [ ] **Step 5: Commit**

```bash
git -C ~/Developer/Fabled add Sources/FabledCore/TimelineReducer.swift Tests/FabledCoreTests/TimelineReducerTests.swift
git -C ~/Developer/Fabled commit -m "feat(core): reducer gate-tool filter; parent routing moves to caller"
```

---

## Task 5: ChatSession — interaction gates, mode-status tracking, todos, subagent routing

The heart of the plan. `pendingPermissions` becomes a typed gate queue; ExitPlanMode approval's `system/status` updates the toolbar's permission mode; TodoWrite maintains `todos`; parented events land in per-parent sub-timelines. Includes the two thin app-side consumer patches (dock badge, composer slot) so the app target still builds at this commit — their real UI lands in Tasks 8–9.

**Files:**
- Modify: `Sources/FabledCore/ChatSession.swift`
- Modify: `Sources/FabledCore/InteractionModels.swift` (add `InteractionGate`)
- Modify: `App/RootView.swift:8-10`, `App/ComposerView.swift:11-16` (consumer bridge)
- Test: `Tests/FabledCoreTests/ChatSessionTests.swift`, `Tests/FabledCoreTests/Support.swift`

- [ ] **Step 1: Extend the outbound recorder** so tests can assert response payloads. In `Tests/FabledCoreTests/Support.swift` replace the `respond` entry case and closure:

```swift
        case respond(requestID: String, behavior: String, updatedInput: JSONValue?,
                     message: String?)
```
```swift
        respond: { request, decision in
            switch decision {
            case .allow(let updatedInput, _):
                await recorder.record(.respond(
                    requestID: request.requestID, behavior: "allow",
                    updatedInput: updatedInput, message: nil))
            case .deny(let message):
                await recorder.record(.respond(
                    requestID: request.requestID, behavior: "deny",
                    updatedInput: nil, message: message))
            }
        },
```

This **deliberately breaks existing `.respond(...)` assertions** in `ChatSessionTests.swift` — update each to the 4-field pattern (bind extras with `_`). No behavioral edits to those tests.

- [ ] **Step 2: Write the failing tests** — append to `ChatSessionTests.swift` (mirror the file's existing setup idiom: `makeFakeConnection()`, `session.begin()`, `continuation.yield(...)`, `waitUntil`/`waitForEntries`):

```swift
    private func yieldEvent(_ continuation: AsyncStream<AgentEvent>.Continuation,
                            _ json: String) throws {
        continuation.yield(try AgentEventDecoder.decode(Data(json.utf8)))
    }

    func testQuestionGateAnswerRoundTrip() async throws {
        let (connection, continuation, recorder) = makeFakeConnection()
        let session = ChatSession(connection: connection, workingDirectory: .init(filePath: "/tmp"))
        session.begin()
        try yieldEvent(continuation,
            #"{"type":"control_request","request_id":"q1","request":{"subtype":"can_use_tool","tool_name":"AskUserQuestion","input":{"questions":[{"question":"Color?","header":"C","options":[{"label":"Red","description":""},{"label":"Blue","description":""}],"multiSelect":false}]},"requires_user_interaction":true,"tool_use_id":"t9"}}"#)
        await waitUntil("question gate") { session.pendingGates.count == 1 }
        guard case .question(let prompt)? = session.pendingGate else {
            return XCTFail("expected question gate, got \(String(describing: session.pendingGate))")
        }
        XCTAssertEqual(session.activityState, .needsApproval)

        session.answer(prompt, answers: ["Color?": "Blue"])
        let entries = await waitForEntries(recorder, count: 1)
        guard case .respond("q1", "allow", let updated, nil) = entries[0] else {
            return XCTFail("got \(entries)")
        }
        XCTAssertEqual(updated?["answers"]?["Color?"]?.stringValue, "Blue")
        XCTAssertTrue(session.pendingGates.isEmpty)
        XCTAssertTrue(session.timeline.isEmpty, "no permission row for gates")
    }

    func testSkipSendsEchoWithoutAnswers() async throws {
        let (connection, continuation, recorder) = makeFakeConnection()
        let session = ChatSession(connection: connection, workingDirectory: .init(filePath: "/tmp"))
        session.begin()
        try yieldEvent(continuation,
            #"{"type":"control_request","request_id":"q2","request":{"subtype":"can_use_tool","tool_name":"AskUserQuestion","input":{"questions":[{"question":"Color?","header":"C","options":[{"label":"Red","description":""}],"multiSelect":false}]},"requires_user_interaction":true}}"#)
        await waitUntil("gate") { session.pendingGate != nil }
        guard case .question(let prompt)? = session.pendingGate else { return XCTFail() }
        session.skipQuestions(prompt)
        let entries = await waitForEntries(recorder, count: 1)
        guard case .respond("q2", "allow", let updated, nil) = entries[0] else {
            return XCTFail("got \(entries)")
        }
        XCTAssertNil(updated?["answers"], "skip = echo, no answers key (probe finding 3)")
    }

    func testPlanApprovalAndStatusModeSwitch() async throws {
        let (connection, continuation, recorder) = makeFakeConnection()
        let session = ChatSession(connection: connection, workingDirectory: .init(filePath: "/tmp"),
                                  permissionMode: "plan")
        session.begin()
        try yieldEvent(continuation,
            #"{"type":"control_request","request_id":"e1","request":{"subtype":"can_use_tool","tool_name":"ExitPlanMode","input":{"plan":"# The Plan"},"requires_user_interaction":true}}"#)
        await waitUntil("plan gate") { session.pendingGate != nil }
        guard case .planApproval(let approval)? = session.pendingGate else { return XCTFail() }
        XCTAssertEqual(approval.plan, "# The Plan")

        session.approvePlan(approval)
        _ = await waitForEntries(recorder, count: 1)
        XCTAssertEqual(session.permissionMode, "plan", "mode changes only on the CLI's status event")

        try yieldEvent(continuation,
            #"{"type":"system","subtype":"status","status":null,"permissionMode":"default","uuid":"s1"}"#)
        await waitUntil("mode switch") { session.permissionMode == "default" }
    }

    func testPlanRejectionPhrasing() async throws {
        let (connection, continuation, recorder) = makeFakeConnection()
        let session = ChatSession(connection: connection, workingDirectory: .init(filePath: "/tmp"))
        session.begin()
        try yieldEvent(continuation,
            #"{"type":"control_request","request_id":"e2","request":{"subtype":"can_use_tool","tool_name":"ExitPlanMode","input":{"plan":"# P"},"requires_user_interaction":true}}"#)
        await waitUntil("gate") { session.pendingGate != nil }
        guard case .planApproval(let approval)? = session.pendingGate else { return XCTFail() }
        session.rejectPlan(approval, feedback: "needs a licence section")
        let entries = await waitForEntries(recorder, count: 1)
        guard case .respond("e2", "deny", nil, let message) = entries[0] else {
            return XCTFail("got \(entries)")
        }
        XCTAssertEqual(message,
            "The user rejected the plan with this feedback: needs a licence section")
    }

    func testTodosTrackLatestList() async throws {
        let (connection, continuation, _) = makeFakeConnection()
        let session = ChatSession(connection: connection, workingDirectory: .init(filePath: "/tmp"))
        session.begin()
        try yieldEvent(continuation,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"td1","name":"TodoWrite","input":{"todos":[{"content":"a","status":"in_progress","activeForm":"a"},{"content":"b","status":"pending","activeForm":"b"}]}}]},"uuid":"a1"}"#)
        await waitUntil("todos") { session.todos.count == 2 }
        try yieldEvent(continuation,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"td2","name":"TodoWrite","input":{"todos":[{"content":"a","status":"completed","activeForm":"a"},{"content":"b","status":"completed","activeForm":"b"}]}}]},"uuid":"a2"}"#)
        await waitUntil("todos update") { session.todos.allSatisfy { $0.status == .completed } }
    }

    func testSubagentEventsRouteToSubTimeline() async throws {
        let (connection, continuation, _) = makeFakeConnection()
        let session = ChatSession(connection: connection, workingDirectory: .init(filePath: "/tmp"))
        session.begin()
        // Parent Task call in the main timeline…
        try yieldEvent(continuation,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"task-1","name":"Task","input":{"description":"explore"}}]},"uuid":"a1"}"#)
        // …then parented traffic.
        try yieldEvent(continuation,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"sub-t1","name":"Bash","input":{"command":"ls"}}]},"parent_tool_use_id":"task-1","uuid":"a2"}"#)
        try yieldEvent(continuation,
            #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"sub-t1","content":"ok","is_error":false}]},"parent_tool_use_id":"task-1","uuid":"u1"}"#)
        await waitUntil("routing") { session.subagentTimelines["task-1"]?.count == 1 }
        XCTAssertEqual(session.timeline.count, 1, "main timeline holds only the Task card")
        guard case .toolCall("sub-t1", "Bash", _, _, .string("ok"), false, false) =
            session.subagentTimelines["task-1"]![0] else {
            return XCTFail("sub-timeline should reduce normally: \(session.subagentTimelines)")
        }
        XCTAssertFalse(session.isThinking,
                       "subagent stream state must not drive the parent spinner")
    }
```

- [ ] **Step 3: Run to verify failure**

Run: `swift test --filter ChatSessionTests 2>&1 | tail -4`
Expected: compile failure (`pendingGates` unresolved).

- [ ] **Step 4: Implement.** First, append to `Sources/FabledCore/InteractionModels.swift`:

```swift
/// One thing the CLI is waiting on the user for. Rendered in the composer
/// slot; arrival order preserved (first gate is the active card).
public enum InteractionGate: Equatable, Sendable, Identifiable {
    case permission(PermissionRequest)
    case question(QuestionPrompt)
    case planApproval(PlanApproval)

    public var requestID: String {
        switch self {
        case .permission(let request): request.requestID
        case .question(let prompt): prompt.request.requestID
        case .planApproval(let approval): approval.request.requestID
        }
    }
    public var id: String { requestID }
}
```

Then in `Sources/FabledCore/ChatSession.swift`:

Replace the two pending-permission properties (lines 18-19) with:

```swift
    public private(set) var pendingGates: [InteractionGate] = []
    public var pendingGate: InteractionGate? { pendingGates.first }
```

Add new state below `versionNote` (after line 33):

```swift
    /// Latest TodoWrite list — the CLI re-sends the whole list per call.
    public private(set) var todos: [TodoItem] = []
    /// Subagent traffic grouped by the spawning Task's tool_use id,
    /// reduced through the same TimelineReducer vocabulary.
    public private(set) var subagentTimelines: [String: [TimelineItem]] = [:]
```

Replace `respond(to:decision:)` (lines 135-144) and add the gate methods:

```swift
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
```

In `handle(_:)` — route subagent traffic before anything else (insert at the top of the function, after the wire-log line):

```swift
        // Subagent side-streams: same vocabulary, separate timeline. Routed
        // here (not in the reducer) so sub-traffic can't touch parent state
        // like isThinking or gates.
        if let parentID = event.parentToolUseID {
            subagentTimelines[parentID] = TimelineReducer.reduce(
                subagentTimelines[parentID] ?? [], event)
            return
        }
```

Replace the `.controlRequest` case (lines 219-222):

```swift
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
```

In the `.result` case replace `pendingPermissions.removeAll()` (line 230) with `pendingGates.removeAll()` (comment unchanged — aborted turns abandon gates).

Add two cases before `default:` (after the `.terminated` case):

```swift
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
                    if !parsed.isEmpty { todos = parsed }
                }
            }
```

Update `activityState` (line 175): `if !pendingGates.isEmpty { return .needsApproval }`.

- [ ] **Step 5: Bridge the two app-side consumers** (keeps the app building; real UI in Tasks 8–9).

`App/RootView.swift` — `pendingApprovals` (lines 8-10) counts gates now:

```swift
    private var pendingApprovals: Int {
        app.liveSessions.reduce(0) { $0 + $1.pendingGates.count }
    }
```

`App/ComposerView.swift` — replace the permission-card block (lines 11-16):

```swift
            if let gate = session.pendingGate {
                switch gate {
                case .permission(let request):
                    PermissionCardView(request: request) { decision in
                        session.respond(to: request, decision: decision)
                    }
                    .id(request.requestID)
                case .question(let prompt):
                    // Placeholder until Task 8's QuestionCardView.
                    HStack {
                        Text(prompt.questions.first?.text ?? "Claude has a question")
                            .font(.callout)
                        Spacer()
                        Button("Skip") { session.skipQuestions(prompt) }
                    }
                    .padding(10)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
                case .planApproval(let approval):
                    // Placeholder until Task 9's PlanApprovalViews.
                    HStack {
                        Text("Claude proposes a plan").font(.callout)
                        Spacer()
                        Button("Reject") { session.rejectPlan(approval, feedback: nil) }
                        Button("Approve") { session.approvePlan(approval) }
                            .buttonStyle(.borderedProminent).tint(Theme.clay)
                    }
                    .padding(10)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
                }
            }
```

Also update the send button's shortcut condition (line 40): `session.pendingGate == nil`.

- [ ] **Step 6: Run everything**

Run: `swift build && swift test 2>&1 | grep -E "Executed|failed"` — all green (update any remaining `pendingPermissions` references the compiler finds in tests; bind-and-adapt, no behavior edits).
Run: `xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled -configuration Debug build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git -C ~/Developer/Fabled add -A Sources Tests App
git -C ~/Developer/Fabled commit -m "feat(core): interaction gates, status-driven mode, todos, subagent routing"
```

---
## Task 6: Side inspector — infrastructure + compact tool rows

The architectural piece (brief feature 17). Tool/raw cards become one-line rows; clicking routes detail into a right-hand `.inspector` panel. This deletes the per-row `DisclosureGroup` — and with it the `@State`-reset-on-recycle bug (FOLLOWUPS rider, resolved by removal).

**Files:**
- Create: `App/InspectorView.swift`
- Modify: `App/TimelineItemViews.swift` (`ToolCallCard`, `RawEventView`, `TimelineItemView`)
- Modify: `App/ConversationView.swift`, `App/HistoricalSessionView.swift`

No FabledCore changes — pure view work; verification is build + smoke.

- [ ] **Step 1: Create `App/InspectorView.swift`:**

```swift
import SwiftUI
import ClaudeKit
import FabledCore

/// Cards request inspection by timeline-item id; the conversation container
/// owns the panel state.
struct InspectItemAction {
    let action: (String) -> Void
    func callAsFunction(_ id: String) { action(id) }
}

extension EnvironmentValues {
    @Entry var inspectItem: InspectItemAction? = nil
}

/// Right-hand detail panel: full tool I/O, diffs (Task 7), subagent
/// drill-down (Task 11), raw events. The transcript shows one-liners;
/// everything deep lives here (Electron-parity gate feedback).
struct InspectorPanel: View {
    let items: [TimelineItem]
    let subagentTimelines: [String: [TimelineItem]]
    @Binding var inspectedID: String?

    var body: some View {
        if let item = resolvedItem {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Spacer()
                        // In-panel close (deliberately not a toolbar item —
                        // toolbar placement inside .inspector content is
                        // unreliable across macOS releases).
                        Button {
                            inspectedID = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Clear selection")
                    }
                    content(for: item)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView(
                "Nothing selected",
                systemImage: "sidebar.right",
                description: Text("Click a tool card to see its full detail."))
        }
    }

    private var resolvedItem: TimelineItem? {
        guard let inspectedID else { return nil }
        if let item = items.first(where: { $0.id == inspectedID }) { return item }
        for timeline in subagentTimelines.values {
            if let item = timeline.first(where: { $0.id == inspectedID }) { return item }
        }
        return nil
    }

    @ViewBuilder
    private func content(for item: TimelineItem) -> some View {
        switch item {
        case .toolCall(let id, let name, let summary, let input, let result,
                       let isError, let isRunning):
            toolDetail(id: id, name: name, summary: summary, input: input,
                       result: result, isError: isError, isRunning: isRunning)
        case .raw(_, let type, let raw):
            sectionHeader(type, systemImage: "questionmark.square.dashed")
            monospacedBlock(JSONPretty.string(raw))
        default:
            // Other item kinds are fully visible inline; nothing deeper to show.
            Text("No additional detail for this item.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func toolDetail(id: String, name: String, summary: String,
                            input: JSONValue, result: JSONValue?,
                            isError: Bool?, isRunning: Bool) -> some View {
        HStack(spacing: 8) {
            ToolStatusIcon(isError: isError, isRunning: isRunning)
            Text(name).font(.title3).fontWeight(.semibold)
        }
        Text(summary).font(.callout).foregroundStyle(.secondary)
        // Task 7 inserts the diff section here for Edit/Write/MultiEdit.
        if input != .object([:]), input != .null {
            sectionHeader("Input", systemImage: "arrow.down.circle")
            monospacedBlock(JSONPretty.string(input))
        }
        if let result {
            sectionHeader("Result", systemImage: "arrow.up.circle")
            monospacedBlock(JSONPretty.string(result),
                            tint: isError == true ? .red : nil)
        }
        // Task 11 inserts the subagent drill-down here for Task/Agent.
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption).fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    /// Full payloads, sanely capped — the inspector is the "see everything"
    /// surface, but a 50 MB tool result must not hang the window.
    private func monospacedBlock(_ text: String, tint: Color? = nil) -> some View {
        Text(String(text.prefix(200_000)))
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(tint ?? Color.primary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Shared by the compact row and the panel header.
struct ToolStatusIcon: View {
    let isError: Bool?
    let isRunning: Bool
    var body: some View {
        if isRunning {
            ProgressView().controlSize(.small)
        } else if isError == true {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        } else {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        }
    }
}
```

- [ ] **Step 2: Compact the cards.** In `App/TimelineItemViews.swift` replace `ToolCallCard` (lines 67-114) entirely:

```swift
/// One-line tool row; all detail opens in the side inspector. Deliberately
/// stateless — the old DisclosureGroup's @State reset when LazyVStack
/// recycled rows (FOLLOWUPS rider, resolved by this design).
struct ToolCallCard: View {
    let id: String
    let name: String
    let summary: String
    let input: JSONValue
    let result: JSONValue?
    let isError: Bool?
    let isRunning: Bool
    @Environment(\.inspectItem) private var inspectItem

    var body: some View {
        Button {
            inspectItem?(id)
        } label: {
            HStack(spacing: 6) {
                ToolStatusIcon(isError: isError, isRunning: isRunning)
                Text(name).fontWeight(.medium)
                Text(summary).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                // Task 7 inserts diff count chips here.
                Image(systemName: "chevron.right")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .font(.callout)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(8)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
        .help("Show full input/output in the inspector")
    }
}
```

Replace `RawEventView` (lines 169-185):

```swift
struct RawEventView: View {
    let id: String
    let type: String
    let raw: JSONValue
    @Environment(\.inspectItem) private var inspectItem

    var body: some View {
        Button {
            inspectItem?(id)
        } label: {
            HStack(spacing: 6) {
                Label(type, systemImage: "questionmark.square.dashed")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(6)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
    }
}
```

Update the two construction sites in `TimelineItemView.body`:

```swift
        case .toolCall(let id, let name, let summary, let input, let result, let isError, let isRunning):
            ToolCallCard(id: id, name: name, summary: summary, input: input,
                         result: result, isError: isError, isRunning: isRunning)
```
```swift
        case .raw(let id, let type, let raw):
            RawEventView(id: id, type: type, raw: raw)
```

- [ ] **Step 3: Wire the panel into both conversation surfaces.**

`App/ConversationView.swift` — add state (below line 5):

```swift
    @State private var inspectedID: String?
    @State private var isInspectorPresented = false
```

Attach to the outer `VStack` (after `.navigationSubtitle`, before `.toolbar`):

```swift
        .environment(\.inspectItem, InspectItemAction { id in
            inspectedID = id
            isInspectorPresented = true
        })
        .inspector(isPresented: $isInspectorPresented) {
            InspectorPanel(items: session.timeline,
                           subagentTimelines: session.subagentTimelines,
                           inspectedID: $inspectedID)
                .inspectorColumnWidth(min: 300, ideal: 420, max: 640)
        }
```

Add a toolbar toggle as the LAST item in the existing `ToolbarItemGroup`:

```swift
                Button {
                    isInspectorPresented.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help("Toggle inspector")
                .keyboardShortcut("i", modifiers: [.command, .option])
```

`App/HistoricalSessionView.swift` — same pattern, read-only data. Add below the existing `@State private var items` (line 8):

```swift
    @State private var inspectedID: String?
    @State private var isInspectorPresented = false
```

and attach after `.navigationSubtitle(...)` (line 35):

```swift
        .environment(\.inspectItem, InspectItemAction { id in
            inspectedID = id
            isInspectorPresented = true
        })
        .inspector(isPresented: $isInspectorPresented) {
            InspectorPanel(items: items ?? [],
                           subagentTimelines: [:],
                           inspectedID: $inspectedID)
                .inspectorColumnWidth(min: 300, ideal: 420, max: 640)
        }
```

- [ ] **Step 4: Build + smoke**

Run: `swift build && swift test 2>&1 | grep Executed && xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled -configuration Debug build 2>&1 | tail -3`
Expected: tests unchanged-green; `** BUILD SUCCEEDED **`.

Smoke (manual, launch the built app): open a historical session with tool calls → rows are one-liners with chevrons → click one → inspector opens with full input/result → ⌥⌘I toggles → scrolling a long transcript keeps inspector selection stable.

- [ ] **Step 5: Commit**

```bash
git -C ~/Developer/Fabled add App
git -C ~/Developer/Fabled commit -m "feat(app): side inspector replaces inline tool disclosure"
```

---

## Task 7: Diff rendering — inspector section + row count chips

Brief feature 1: Edit/Write/MultiEdit render as diffs with +/− counts; collapsed row shows counts, the inspector shows the full unified diff (routed per feature 17).

**Files:**
- Modify: `App/InspectorView.swift` (diff section)
- Modify: `App/TimelineItemViews.swift` (`ToolCallCard` chips)

- [ ] **Step 1: Diff section view.** Append to `App/InspectorView.swift`:

```swift
/// Unified diff for Edit/Write/MultiEdit tool inputs — computed from the
/// tool call's own strings, no git (brief feature 1).
struct DiffSectionView: View {
    let diff: ToolDiff

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(diff.filePath)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1).truncationMode(.head)
                Spacer()
                DiffCountChips(added: diff.added, removed: diff.removed)
            }
            ForEach(Array(diff.hunks.enumerated()), id: \.offset) { index, hunk in
                if diff.hunks.count > 1 {
                    Text("Edit \(index + 1)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(hunk.enumerated()), id: \.offset) { _, line in
                        DiffLineView(line: line)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

private struct DiffLineView: View {
    let line: DiffLine

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(marker)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: 10, alignment: .leading)
            Text(line.text.isEmpty ? " " : line.text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(background)
    }

    private var marker: String {
        switch line.kind {
        case .insertion: "+"
        case .deletion: "−"
        case .context: " "
        }
    }
    private var color: Color {
        switch line.kind {
        case .insertion: .green
        case .deletion: .red
        case .context: .secondary
        }
    }
    private var background: Color {
        switch line.kind {
        case .insertion: .green.opacity(0.12)
        case .deletion: .red.opacity(0.12)
        case .context: .clear
        }
    }
}

struct DiffCountChips: View {
    let added: Int
    let removed: Int
    var body: some View {
        HStack(spacing: 4) {
            Text("+\(added)").foregroundStyle(.green)
            Text("−\(removed)").foregroundStyle(.red)
        }
        .font(.caption.monospacedDigit())
    }
}
```

- [ ] **Step 2: Route diffs in the panel.** In `InspectorPanel.toolDetail`, insert directly under the `Text(summary)` line (replacing the Task 7 placeholder comment):

```swift
        if let diff = ToolDiff.from(toolName: name, input: input) {
            sectionHeader("Changes", systemImage: "plus.forwardslash.minus")
            DiffSectionView(diff: diff)
        }
```

and make the raw Input section skip diff tools' bulky strings — wrap the existing Input section in:

```swift
        if ToolDiff.from(toolName: name, input: input) == nil,
           input != .object([:]), input != .null {
```

(For diff tools the "Changes" section IS the input; the raw JSON added nothing but noise. `ToolDiff.from` is called twice per render — small strings, LCS is micro­seconds; do not cache prematurely.)

- [ ] **Step 3: Count chips on the compact row.** In `ToolCallCard` (Task 6 version), replace the chips placeholder comment with:

```swift
                if let diff = ToolDiff.from(toolName: name, input: input) {
                    DiffCountChips(added: diff.added, removed: diff.removed)
                }
```

- [ ] **Step 4: Build + smoke**

Run: `swift build && xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled -configuration Debug build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

Smoke: open a historical coding session with Edit/Write calls → rows show `+N −M` chips → inspector shows the colored unified diff for an Edit (old/new lines correct), a Write (all green), and — if the history has one — a MultiEdit (hunk per edit).

- [ ] **Step 5: Commit**

```bash
git -C ~/Developer/Fabled add App
git -C ~/Developer/Fabled commit -m "feat(app): unified diff rendering for Edit/Write/MultiEdit"
```

---

## Task 8: AskUserQuestion — native option picker card

Brief feature 2. Replaces the Task 5 placeholder. Single-select questions answer with one click when they're the whole prompt; multi-question and multi-select forms submit once, with free-text "Other" per question (any string is a legal answer — probe finding 2).

**Files:**
- Create: `App/QuestionCardView.swift`
- Modify: `App/ComposerView.swift` (swap placeholder)

- [ ] **Step 1: Create `App/QuestionCardView.swift`:**

```swift
import SwiftUI
import FabledCore

/// Native rendering for AskUserQuestion (probe findings 1-3). Claude waits
/// on this card — it must always offer Skip so the turn can proceed.
struct QuestionCardView: View {
    let prompt: QuestionPrompt
    let respond: ([String: String]) -> Void
    let skip: () -> Void

    @State private var selections: [String: Set<String>] = [:]
    @State private var otherText: [String: String] = [:]

    /// One single-select question = click-to-answer, no Submit ceremony.
    private var isSingleShot: Bool {
        prompt.questions.count == 1 && !(prompt.questions.first?.multiSelect ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.bubble.fill")
                    .foregroundStyle(Theme.clay)
                Text("Claude asks").fontWeight(.semibold)
                Spacer()
                Button("Skip", action: skip)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                    .help("Continue without answering")
            }
            ForEach(prompt.questions) { question in
                questionBlock(question)
            }
            if !isSingleShot {
                HStack {
                    Spacer()
                    Button("Answer") { submit() }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.clay)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(!isComplete)
                }
            }
        }
        .padding(12)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Theme.clay.opacity(0.5)))
    }

    @ViewBuilder
    private func questionBlock(_ question: QuestionPrompt.Question) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if !question.header.isEmpty {
                    Text(question.header)
                        .font(.caption2).fontWeight(.semibold)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Text(question.text).font(.callout)
            }
            ForEach(question.options, id: \.label) { option in
                optionRow(question: question, option: option)
            }
            TextField("Other…", text: otherBinding(question))
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .onSubmit { if isSingleShot { submit() } }
        }
    }

    private func optionRow(question: QuestionPrompt.Question,
                           option: QuestionPrompt.Option) -> some View {
        let isSelected = selections[question.text, default: []].contains(option.label)
        return Button {
            toggle(question: question, option: option.label)
            if isSingleShot { submit() }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: question.multiSelect
                    ? (isSelected ? "checkmark.square.fill" : "square")
                    : (isSelected ? "largecircle.fill.circle" : "circle"))
                    .foregroundStyle(isSelected ? Theme.clay : Color.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label)
                    if !option.detail.isEmpty {
                        Text(option.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggle(question: QuestionPrompt.Question, option: String) {
        var selected = selections[question.text, default: []]
        if question.multiSelect {
            if selected.contains(option) { selected.remove(option) }
            else { selected.insert(option) }
        } else {
            selected = [option]
        }
        selections[question.text] = selected
    }

    private func otherBinding(_ question: QuestionPrompt.Question) -> Binding<String> {
        Binding(get: { otherText[question.text] ?? "" },
                set: { otherText[question.text] = $0 })
    }

    private func answerText(_ question: QuestionPrompt.Question) -> String? {
        let other = (otherText[question.text] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Catalog order, not click order — multi-select joins with ", "
        // (probe finding 2). Free text rides along as one more value.
        var parts = question.options.map(\.label)
            .filter { selections[question.text, default: []].contains($0) }
        if !other.isEmpty { parts.append(other) }
        guard !parts.isEmpty else { return nil }
        return question.multiSelect ? parts.joined(separator: ", ") : parts[0]
    }

    private var isComplete: Bool {
        prompt.questions.allSatisfy { answerText($0) != nil }
    }

    private func submit() {
        var answers: [String: String] = [:]
        for question in prompt.questions {
            guard let answer = answerText(question) else { return }
            answers[question.text] = answer
        }
        respond(answers)
    }
}
```

Note the single-select + free-text interaction: for a single-select question the free text wins only when no option is selected (parts[0] is an option label when one is picked; free text is appended after). If both are set, the option wins — acceptable; do not over-engineer.

- [ ] **Step 2: Swap the placeholder.** In `App/ComposerView.swift`, replace the `.question` placeholder case body from Task 5 with:

```swift
                case .question(let prompt):
                    QuestionCardView(
                        prompt: prompt,
                        respond: { session.answer(prompt, answers: $0) },
                        skip: { session.skipQuestions(prompt) })
                    .id(prompt.request.requestID)
```

- [ ] **Step 3: Build + smoke**

Run: `xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled -configuration Debug build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

Smoke (live, cheap): new session in a scratch folder, model haiku (picker), send: *"Use the AskUserQuestion tool to ask me my favorite color (Red/Blue) and — multiSelect — which sizes I want (S/M/L). Then summarize my answers in one line."* → card renders both questions → answer → Claude's summary matches the picks. Repeat once and press Skip → Claude reports no answer was given.

- [ ] **Step 4: Commit**

```bash
git -C ~/Developer/Fabled add App
git -C ~/Developer/Fabled commit -m "feat(app): native AskUserQuestion option picker"
```

---

## Task 9: Plan-mode approval — composer card + review sheet

Brief feature 3. The composer card announces the plan; "Review Plan…" opens a sheet with the full markdown, feedback field, Approve / Request Changes. Approval flips the toolbar's permission mode via the CLI's own `status` event (already handled in Task 5) — nothing here touches mode state directly.

**Files:**
- Create: `App/PlanApprovalViews.swift`
- Modify: `App/ComposerView.swift` (swap placeholder, host the sheet)

- [ ] **Step 1: Create `App/PlanApprovalViews.swift`:**

```swift
import SwiftUI
import FabledCore

/// Composer-slot announcement for a pending ExitPlanMode gate.
struct PlanApprovalCard: View {
    let approval: PlanApproval
    let review: () -> Void
    let approve: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "list.clipboard.fill").foregroundStyle(Theme.clay)
            VStack(alignment: .leading, spacing: 1) {
                Text("Claude proposes a plan").fontWeight(.semibold)
                Text(planTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button("Review Plan…", action: review)
                .keyboardShortcut(.return, modifiers: .command)
            Button("Approve", action: approve)
                .buttonStyle(.borderedProminent)
                .tint(Theme.clay)
        }
        .padding(12)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Theme.clay.opacity(0.5)))
    }

    private var planTitle: String {
        approval.plan.split(separator: "\n", omittingEmptySubsequences: true)
            .first.map { $0.trimmingCharacters(in: .init(charactersIn: "# ")) }
            ?? "Untitled plan"
    }
}

/// Full-plan review sheet: approve (⌘⏎) or send revision feedback.
struct PlanReviewSheet: View {
    let approval: PlanApproval
    let approve: () -> Void
    let reject: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var feedback = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Proposed plan", systemImage: "list.clipboard")
                    .font(.title3).fontWeight(.semibold)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Close — decide later")
            }
            ScrollView {
                // Inline-only markdown (ledgered AttributedString decision):
                // headings render as plain lines — readable, not pretty.
                // Serif matches Claude's voice.
                AssistantTextView(markdown: approval.plan, isStreaming: false)
                    .padding(12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
            TextField("Feedback (sent with Request Changes)",
                      text: $feedback, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
            HStack {
                Button("Request Changes") {
                    reject(feedback)
                    dismiss()
                }
                Spacer()
                Button("Approve Plan") {
                    approve()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.clay)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(16)
        .frame(minWidth: 540, idealWidth: 640, minHeight: 420, idealHeight: 560)
    }
}
```

- [ ] **Step 2: Host the sheet + swap the placeholder.** In `App/ComposerView.swift`:

Add state below `@FocusState` (line 7):

```swift
    @State private var reviewingPlan: PlanApproval?
```

Replace the `.planApproval` placeholder case body from Task 5 with:

```swift
                case .planApproval(let approval):
                    PlanApprovalCard(
                        approval: approval,
                        review: { reviewingPlan = approval },
                        approve: { session.approvePlan(approval) })
                    .id(approval.request.requestID)
```

Attach the sheet to the outer `VStack` (after `.onAppear`):

```swift
        .sheet(item: $reviewingPlan) { approval in
            PlanReviewSheet(
                approval: approval,
                approve: { session.approvePlan(approval) },
                reject: { session.rejectPlan(approval, feedback: $0) })
        }
        // An aborted turn abandons the gate; a stale sheet must not send
        // decisions into the void (ChatSession's removeGate guard makes such
        // sends no-ops, but the open sheet would still mislead).
        .onChange(of: session.pendingGate?.requestID) {
            if let reviewing = reviewingPlan,
               session.pendingGates.first(where: { $0.requestID == reviewing.request.requestID }) == nil {
                reviewingPlan = nil
            }
        }
```

- [ ] **Step 3: Build + smoke**

Run: `xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled -configuration Debug build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

Smoke (live, cheap — mirrors `fixtures/probe_plan.py`): new session in a scratch folder, haiku, toolbar permission mode → **Plan**, send *"Plan how to add a README.md describing this project, then request approval. If approved, implement it."* →
1. Plan card appears → Review Plan… → sheet shows the markdown.
2. Request Changes with "add a licence section" → Claude revises → second card arrives.
3. Approve → toolbar permission-mode picker flips to Default (the `status` event, watch it happen) → Claude writes the README (approving any Write permission card).

- [ ] **Step 4: Commit**

```bash
git -C ~/Developer/Fabled add App
git -C ~/Developer/Fabled commit -m "feat(app): plan-mode review sheet + approval flow"
```

---
## Task 10: TodoWrite — pinned checklist card

Brief feature 4: a pinned, live-updating progress card above the composer; collapses when everything is done. Data (`ChatSession.todos`) landed in Task 5; the row summary ("2/5 done") landed in Task 3.

**Files:**
- Create: `App/TodoChecklistView.swift`
- Modify: `App/ConversationView.swift` (pin above the composer)

- [ ] **Step 1: Create `App/TodoChecklistView.swift`:**

```swift
import SwiftUI
import FabledCore

/// Pinned progress card for the session's TodoWrite list. Auto-collapses
/// once every item completes; the header always toggles manually.
struct TodoChecklistView: View {
    let todos: [TodoItem]
    /// nil = follow auto behavior (open while work remains).
    @State private var userCollapsed: Bool?

    private var allDone: Bool { todos.allSatisfy { $0.status == .completed } }
    private var isCollapsed: Bool { userCollapsed ?? allDone }
    private var doneCount: Int { todos.count { $0.status == .completed } }
    private var current: TodoItem? { todos.first { $0.status == .inProgress } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                userCollapsed = !isCollapsed
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: allDone
                        ? "checklist.checked" : "checklist")
                        .foregroundStyle(allDone ? Color.green : Theme.clay)
                    Text("\(doneCount)/\(todos.count)")
                        .font(.caption.monospacedDigit()).fontWeight(.semibold)
                    if isCollapsed, let current {
                        Text(current.activeForm)
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
                ForEach(todos) { todo in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        icon(for: todo.status)
                        Text(todo.status == .inProgress ? todo.activeForm : todo.content)
                            .font(.caption)
                            .italic(todo.status == .inProgress)
                            .foregroundStyle(todo.status == .completed
                                ? Color.secondary : Color.primary)
                            .strikethrough(todo.status == .completed,
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

- [ ] **Step 2: Pin it.** In `App/ConversationView.swift`, between the `GeometryReader` block's closing brace and `Divider()` (line 70-71):

```swift
            if !session.todos.isEmpty {
                TodoChecklistView(todos: session.todos)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                    .frame(maxWidth: 760)
            }
```

(760 matches the conversation column width until Task 12 tokenizes it — then both change together.)

- [ ] **Step 3: Build + smoke**

Run: `xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled -configuration Debug build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

Smoke (live, cheap): scratch session, haiku: *"Use TodoWrite to plan 3 tiny steps (create a.txt, create b.txt, list files), then do them, updating the todo list as you go."* → card appears pinned, items flip pending → in_progress (italic activeForm) → completed as the turn runs → card collapses itself at 3/3 → header click re-expands. The TodoWrite rows in the transcript read "N/M done" (Task 3).

- [ ] **Step 4: Commit**

```bash
git -C ~/Developer/Fabled add App
git -C ~/Developer/Fabled commit -m "feat(app): pinned TodoWrite checklist card"
```

---

## Task 11: Subagent grouping — Task card badge + inspector drill-down

Brief feature 5: parented traffic (routed since Task 5) becomes visible — the Task/Agent row shows live sub-step count, and the inspector shows the subagent's own mini-timeline (routed through the inspector per feature 17).

**Files:**
- Modify: `App/TimelineItemViews.swift` (`TimelineItemView`, `ToolCallCard`)
- Modify: `App/InspectorView.swift` (panel: drill-down section; pass-through of live sub-timelines already wired in Task 6)

- [ ] **Step 1: Badge data into the card.** In `App/TimelineItemViews.swift`, `ToolCallCard` gains one property (after `isRunning`):

```swift
    /// "N steps" chip for Task/Agent calls with routed subagent activity.
    let subagentSteps: Int?
```

and renders it in the label `HStack`, next to the diff-chips slot:

```swift
                if let subagentSteps, subagentSteps > 0 {
                    Text("\(subagentSteps) steps")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
```

`TimelineItemView` computes it from the session (nil in history — on-disk subagent transcripts are Plan 4b, feature 15):

```swift
        case .toolCall(let id, let name, let summary, let input, let result, let isError, let isRunning):
            ToolCallCard(id: id, name: name, summary: summary, input: input,
                         result: result, isError: isError, isRunning: isRunning,
                         subagentSteps: session?.subagentTimelines[id]?.count)
```

(Other `ToolCallCard(...)` construction sites, if any, pass `subagentSteps: nil`.)

- [ ] **Step 2: Drill-down in the panel.** `InspectorPanel` already receives `subagentTimelines` (Task 6). In `toolDetail`, replace the Task 11 placeholder comment with:

```swift
        if let sub = subagentTimelines[id], !sub.isEmpty {
            sectionHeader("Subagent activity (\(sub.count) items)",
                          systemImage: "person.2.circle")
            VStack(alignment: .leading, spacing: 6) {
                // Same vocabulary, read-only. Sub tool rows are inspectable
                // too — resolvedItem already searches sub-timelines.
                ForEach(sub) { item in
                    TimelineItemView(item: item, session: nil)
                }
            }
        }
```

- [ ] **Step 3: Build + smoke**

Run: `xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled -configuration Debug build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

Smoke (live — the one costlier check in this plan, still haiku): scratch session containing a couple of Swift files, send *"Use the Task tool with the Explore agent to find every function name in this folder, then report them."* → the Task row grows a live "N steps" chip while the subagent works → main transcript stays clean (no interleaved subagent rows) → clicking the Task row shows the subagent's mini-timeline in the inspector → clicking a subagent Bash row shows its full I/O → the Task row's own result fills when the subagent reports back.

- [ ] **Step 4: Commit**

```bash
git -C ~/Developer/Fabled add App
git -C ~/Developer/Fabled commit -m "feat(app): subagent grouping — Task badges + inspector drill-down"
```

---

## Task 12: Width tokens, docs, and the 4a gate

Close-out: the bubble-width tuning that rides feature 17, follow-ups bookkeeping, and the consolidated manual gate for Ben.

**Files:**
- Modify: `App/Theme.swift`, `App/ConversationView.swift`, `App/HistoricalSessionView.swift`
- Modify: `docs/superpowers/FOLLOWUPS.md`, `docs/superpowers/plans/2026-07-09-plan-4a-interactive-surfaces.md` (status)

- [ ] **Step 1: Tokenize the conversation column.** In `App/Theme.swift` add:

```swift
    /// Conversation column cap. 760 shipped in Plan 3; widened with the
    /// inspector layout so diffs breathe (gate feedback: bubble-width tuning).
    static let contentMaxWidth: CGFloat = 820
```

Replace the literal `760` in `App/ConversationView.swift` (two places after Task 10: the LazyVStack `.frame(maxWidth: 760, …)` and the TodoChecklistView `.frame(maxWidth: 760)`) and in `App/HistoricalSessionView.swift` (LazyVStack frame) with `Theme.contentMaxWidth`.

- [ ] **Step 2: Bookkeeping.**

In `docs/superpowers/FOLLOWUPS.md`, under "Deferred from Plan 3", annotate the resolved rider:

```markdown
- ~~Tool/raw card expansion `@State` resets when the LazyVStack recycles offscreen rows.~~ → resolved in Plan 4a Task 6: the inspector design removed per-row expansion state entirely.
```

In this plan file's header, set the status line (mirror Plan 3's convention):

```markdown
> **STATUS: COMPLETE — <date>.** <one-paragraph summary of what landed, amendments, gate outcome.>
```

(Write the paragraph from what actually happened during execution; do not pre-write it.)

- [ ] **Step 3: Full verification**

```bash
swift build && swift test 2>&1 | grep Executed
xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled -configuration Debug build 2>&1 | tail -3
```
Expected: everything green, `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual gate (Ben) — the daily-driver checks for 4a**

Run through in the built app; every line must feel right, not merely function:

1. **Inspector**: tool rows are calm one-liners; click → detail panel; ⌥⌘I; selection survives scrolling a 1000-item transcript (LazyVStack recycling).
2. **Diffs**: an Edit shows a correct colored diff + `+N −M` chips; Write is all-green; MultiEdit shows hunk-per-edit.
3. **AskUserQuestion**: single-question click-through; multi-question form; Skip; answers echoed correctly by Claude.
4. **Plan mode**: full probe-plan flow — propose → request changes → revised → approve → toolbar mode flips to Default via the wire → implementation proceeds.
5. **TodoWrite**: pinned card updates live, collapses at completion.
6. **Subagents**: Task chip counts steps live; main transcript uncluttered; drill-down works; no parent spinner flicker from subagent thinking.
7. **Regressions**: ordinary permission cards (allow/always-allow/deny), interrupt (⌘.), model picker, resume/fork from history, multi-window — all as in Plan 3.

- [ ] **Step 5: Final commit**

```bash
git -C ~/Developer/Fabled add -A
git -C ~/Developer/Fabled commit -m "docs: Plan 4a complete — width tokens, followups, gate notes"
```

---

## Execution notes for the coordinator

- Dispatch order is task order; no parallel tasks (5 depends on 1+3+4; 7 on 2+6; 8-11 on 5+6).
- Between-task review checklist lives in `../COORDINATION.md` — real `swift test` output pasted, diff matches plan, no scope creep, tree clean.
- Tasks 8, 9, 10, 11 end with cheap live smokes on haiku — they replace unit tests for view wiring; insist on the transcript/screenshot evidence in the subagent report.
- If the CLI updates mid-plan: re-run `fixtures/probe_ask.py` and `fixtures/probe_plan.py` before trusting the gate shapes; fixture drift shows up as decode-test failures first (that is the design working).
