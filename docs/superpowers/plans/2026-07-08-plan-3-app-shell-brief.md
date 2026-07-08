# Plan 3 brief: app shell + conversation UI

**Status:** design brief — expand with superpowers:writing-plans before implementing (see `../COORDINATION.md`).
**Prerequisite:** Plans 1–2 complete.
**Goal:** The Fabled.app a person can live in: sidebar (live sessions + history), streaming conversation view, composer, model picker, permission cards. After this plan, Ben can use Fabled instead of the Electron app for ordinary coding sessions.

## Locked structural decisions

- **Packaging: XcodeGen.** SwiftUI apps need a real bundle (notifications, dock badge, icon). Commit `project.yml`; generate with `xcodegen generate`; build with `xcodebuild -project Fabled.xcodeproj -scheme Fabled build`. Never hand-edit or hand-create the `.xcodeproj` — it is generated output (gitignore it). `brew install xcodegen` if missing. ClaudeKit stays a local SPM package dependency; its `swift test` suite keeps working unchanged.
- **App architecture: @Observable view models over ClaudeKit actors.**
  - `AppModel` — owns `SessionStore`/`SearchIndex`, publishes sidebar state (live sessions, project history), routes selection.
  - `ChatSession` (one per live conversation) — owns an `AgentSession`, consumes its `events` stream, exposes `timeline: [TimelineItem]`, `pendingPermission: PermissionRequest?`, `isWorking: Bool`, `usage`. All UI-facing mutation on `@MainActor`.
- **The timeline reducer is a pure function** — `reduce(_ items: [TimelineItem], _ event: AgentEvent) -> [TimelineItem]` in ClaudeKit or an app-core module, unit-tested by replaying fixture streams. UI never pattern-matches raw events. This is where correctness lives; spend the tests here.

```swift
public enum TimelineItem: Sendable, Identifiable {
    case userMessage(id: String, text: String)
    case assistantText(id: String, markdown: String, isStreaming: Bool)
    case toolCall(id: String, name: String, summary: String,
                  input: JSONValue, result: JSONValue?, isError: Bool?, isRunning: Bool)
    case permission(id: String, request: PermissionRequest,
                    resolution: PermissionDecision?)
    case turnSummary(id: String, result: TurnResult)
    case notice(id: String, text: String)     // terminated, version banner, errors
    case raw(id: String, type: String, raw: JSONValue)   // .unknown passthrough
}
```

- **Streaming deltas:** add `--include-partial-messages` to `SessionConfiguration` and typed decoding for `stream_event` lines (Plan 1 deliberately deferred this; they currently flow through `.unknown`, so ClaudeKit needs a small codec addition — record a fixture first with `record_handshake_fixture.py` + the flag).
- **Markdown:** `AttributedString(markdown:)` first. No swift-markdown-ui dependency in this plan; revisit only if code blocks/tables prove unacceptable, and ledger it.
- **Aesthetic (approved in spec):** native macOS chrome (SF Pro, system materials, `NavigationSplitView`), Claude warmth inside the conversation — serif (`.system(.body, design: .serif)`) for Claude's prose, clay `#D97757` send button, warm neutrals. The approved mockup is described in the spec's UI section.
- **Model picker:** static known-alias list + free-text field for any full model ID; mid-session switch calls `AgentSession.setModel`. Verify with a live probe that `set_model` takes effect mid-conversation (control response shape unverified as of 2026-07-08 — "verify by probing").

## Task outline (expand into full TDD tasks)

1. XcodeGen scaffold: `project.yml`, empty SwiftUI app boots, ClaudeKit linked, `xcodebuild` green in CI-style invocation.
2. `stream_event` codec support in ClaudeKit (fixture-first: record, then TDD).
3. Timeline reducer: user/assistant/toolCall items (replay `fixtures/*.jsonl`, assert item sequences).
4. Timeline reducer: permission, turnSummary, notice, raw items; streaming-delta coalescing.
5. `ChatSession` view model binding `AgentSession` → reducer → `@MainActor` published timeline.
6. Conversation view: timeline rendering (serif assistant text, tool cards collapsed/expandable), auto-scroll.
7. Composer: multiline input, ⌘⏎ send, working/interrupt states (`AgentSession.interrupt`).
8. Permission card UI: Allow once / Always-allow-with-suggested-rule / Deny with message; keyboard shortcuts; wire to `respond(to:decision:)`. (Always-allow persists via the CLI's `permission_suggestions` `destination` — send `updatedPermissions` in the allow response; **verify exact response shape by probing before writing the task**.)
9. Sidebar: live sessions (state dots: running/needs-approval/idle) + SessionStore history by project; search field over SearchIndex.
10. Session lifecycle: new session (folder picker), open historical read-only (transcript → reducer), Resume / Fork buttons spawning live sessions.
11. Model picker + permission-mode menu in toolbar.
12. Polish gate: launch → resume yesterday's session → send message → approve a permission → switch model, all without touching the terminal.

## Verify by probing (during plan-writing)

- `stream_event` line shapes with `--include-partial-messages` (record fixture).
- `set_model` / `set_permission_mode` acknowledgment shapes and mid-turn behavior.
- Allow-response `updatedPermissions` field shape for persisting "always allow" rules.
- How a second `user` message behaves while a turn is in flight (queue vs reject) — decides composer behavior while `isWorking`.
