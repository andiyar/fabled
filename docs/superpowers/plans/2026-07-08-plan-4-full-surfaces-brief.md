# Plan 4 brief: full surfaces — daily-driver completeness

**Status:** design brief — expand with superpowers:writing-plans before implementing (see `../COORDINATION.md`).
**Prerequisite:** Plan 3 complete (Fabled.app usable for basic sessions).
**Goal:** Close the gap between "usable" and "never opens the Electron app": rich tool rendering, interactive protocol surfaces, the embedded terminal escape hatch, chat/cowork presets, and notification plumbing.

## Feature set (each becomes 1–3 tasks when expanded)

1. **Diff rendering.** `Edit`/`Write`/`MultiEdit` tool calls render as unified diffs with +/− counts (compute from `input` old/new strings; no git needed). Collapsed summary row → expandable full diff.
2. **AskUserQuestion.** Arrives as a `can_use_tool` control request for tool `AskUserQuestion` (**verify by probing**: exact input shape with questions/options, and the answer-return path — likely `allow` with `updatedInput` carrying answers). Render as native option picker card; multi-select support.
3. **Plan mode.** `ExitPlanMode` tool call carries the plan markdown (**verify by probing**). Render plan as a review sheet with approve/reject; rejection sends a deny-with-message. Permission-mode menu already exists (Plan 3); add the plan-approval flow.
4. **TodoWrite checklist.** Pinned, updating progress card driven by `TodoWrite` tool inputs; collapses when all complete.
5. **Subagent grouping.** Events with `parent_tool_use_id` group under their spawning `Task`/`Agent` tool call as a disclosure (count, live status), keeping the main transcript readable.
6. **Embedded terminal escape hatch.** SwiftTerm (app-layer dependency — ledgered as accepted). "Open in Terminal" on any session: suspend the GUI process for that session (terminate CLI cleanly), open a SwiftTerm tab running `claude --resume <id>`; on tab close, offer to re-attach GUI via resume. Never two processes on one session ID.
7. **Notifications + dock badge.** UserNotifications on: permission request while unfocused, turn complete on long tasks, session error. Dock badge = count of pending approvals. Notification click focuses the right session.
8. **Chat preset.** "New chat" = session in `~/Library/Application Support/Fabled/chats/<uuid>/` scratch dir, tool chrome de-emphasized (tool cards start fully collapsed), composer-first layout.
9. **Cowork preset.** Folder picker + permission mode `acceptEdits` + a visible working-folder chip; background-running sessions listed in sidebar with progress; check-in flow = notification → click → review timeline.
10. **Session management.** Archive (move JSONL to an archive subdir), delete with confirmation, rename (local title override stored in app support — transcripts stay untouched).
11. **Resilience surfaces.** CLI-version banner (init event vs codec-tested version), crash → interrupted state → one-click resume, auth-expired detection (assistant text "Not logged in" + `error:authentication_failed` on the message envelope) → offer terminal tab for `/login`.
12. **App identity.** Icon, About window, Sparkle-free manual update check (just link releases page if public; skip entirely if personal-only — ask Ben).

## Locked decisions

- SwiftTerm is the only new dependency, app target only. ClaudeKit stays zero-dep.
- GUI↔TUI handoff rule: one process per session ID, ever. The suspend/re-attach dance above is the invariant that keeps transcripts uncorrupted.
- Chat scratch dirs live under Fabled's app support, not `/tmp` — they must survive reboots because their transcripts are the chat history.

## Verify by probing (during plan-writing)

- AskUserQuestion request/response shapes end to end.
- ExitPlanMode input shape (plan markdown location) and approve/deny semantics.
- Whether `--resume` on a session that has a live GUI process misbehaves (test the invariant's failure mode deliberately, in a scratch project).
- Notification-worthy signal for "turn finished": `result` event suffices, but check long multi-turn autonomous runs (post_turn_summary cadence) on a real cowork-style task.

## Definition of done (v1)

Ben retires the Electron app for daily work: coding sessions, chats, and folder tasks all run in Fabled; the terminal is optional, not required; nothing in a normal week forces a fallback.
