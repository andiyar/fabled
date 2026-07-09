# Plan 4 brief: full surfaces — daily-driver completeness

**Status:** design brief — being expanded as THREE sequential plans (ledgered 2026-07-09): **4a** interactive surfaces & side inspector (features 2, 3, 1, 4, 5, 17), **4b** shell & signals (13, 14, 15, 16, 18, 7 + liveness from 11), **4c** lifecycle, terminal & presets (6, 8, 9, 10, rest of 11, 12). Expand one at a time with superpowers:writing-plans (see `../COORDINATION.md`); tech-debt riders travel with their layer.
**Probing complete 2026-07-09:** all five verify-by-probing items answered on CLI 2.1.205 — see fixtures `2026-07-09-{askuserquestion-*,exitplanmode-*,resume-collision-*,longturn-signals,badmodel-ack}.jsonl` and the two 2026-07-09 DECISIONS entries. Headlines: AskUserQuestion answers return via `allow.updatedInput.answers` keyed by question text; ExitPlanMode approval emits a `system/status` event with the new permissionMode; `--resume` never forks (same session id, dead or alive); `result` fires exactly once per user turn and `post_turn_summary.status_detail` is ready-made notification text; there is no wire heartbeat during tool execution (liveness is client-timed); `set_model` error-acks with subtype `error`, `set_permission_mode` validates nothing.
**Prerequisite:** Plan 3 complete — satisfied 2026-07-09 (merged to master).
**Goal:** Close the gap between "usable" and "never opens the Electron app": rich tool rendering, interactive protocol surfaces, the embedded terminal escape hatch, chat/cowork presets, and notification plumbing.
**Rescoped 2026-07-09:** folded in Ben's Plan 3 gate feedback and the deferred-to-Plan-4 review items from `../FOLLOWUPS.md`. Features 13–18 are the gate additions; the tech-debt list at the bottom rides along with whichever feature touches its layer.

## Feature set (each becomes 1–3 tasks when expanded)

1. **Diff rendering.** `Edit`/`Write`/`MultiEdit` tool calls render as unified diffs with +/− counts (compute from `input` old/new strings; no git needed). Collapsed summary row → expandable full diff. *Route the full view through the side inspector (feature 17), not inline disclosure.*
2. **AskUserQuestion.** Arrives as a `can_use_tool` control request for tool `AskUserQuestion` (**verify by probing**: exact input shape with questions/options, and the answer-return path — likely `allow` with `updatedInput` carrying answers). Render as native option picker card; multi-select support.
3. **Plan mode.** `ExitPlanMode` tool call carries the plan markdown (**verify by probing**). Render plan as a review sheet with approve/reject; rejection sends a deny-with-message. Permission-mode menu already exists (Plan 3); add the plan-approval flow.
4. **TodoWrite checklist.** Pinned, updating progress card driven by `TodoWrite` tool inputs; collapses when all complete.
5. **Subagent grouping.** Events with `parent_tool_use_id` group under their spawning `Task`/`Agent` tool call as a disclosure (count, live status), keeping the main transcript readable.
6. **Embedded terminal escape hatch.** SwiftTerm (app-layer dependency — ledgered as accepted). "Open in Terminal" on any session: suspend the GUI process for that session (terminate CLI cleanly), open a SwiftTerm tab running `claude --resume <id>`; on tab close, offer to re-attach GUI via resume. Never two processes on one session ID.
7. **Notifications + dock badge.** UserNotifications on: permission request while unfocused, turn complete on long tasks, session error. Dock badge = count of pending approvals. Notification click focuses the right session.
8. **Chat preset.** "New chat" = session in `~/Library/Application Support/Fabled/chats/<uuid>/` scratch dir, tool chrome de-emphasized (tool cards start fully collapsed), composer-first layout.
9. **Cowork preset.** Folder picker + permission mode `acceptEdits` + a visible working-folder chip; background-running sessions listed in sidebar with progress; check-in flow = notification → click → review timeline.
10. **Session management.** Archive (move JSONL to an archive subdir), delete with confirmation, rename (local title override stored in app support — transcripts stay untouched). *Include the SIGKILL-after-timeout escalation for stuck children (FOLLOWUPS: SIGTERM-only terminate).*
11. **Resilience surfaces.** ~~CLI-version banner~~ (shipped in Plan 3: disk-derived at spawn, init-authoritative). Remaining: crash → interrupted state → one-click resume; auth-expired detection (assistant text "Not logged in" + `error:authentication_failed` on the message envelope) → offer terminal tab for `/login`; **liveness indicator** — a working session with no wire events for N seconds says so ("no response for 45s…"), instead of sitting silent (gate feedback, born of the opus-4-8[1m] outage evening). *Include ack correlation for `set_model`/`set_permission_mode` so a rejected control op can't leave a stale toolbar label (FOLLOWUPS: optimistic control ops).*
12. **App identity.** Icon, About window, Sparkle-free manual update check (just link releases page if public; skip entirely if personal-only — ask Ben).

### Added from the Plan 3 gate (2026-07-09)

13. **Welcome / new-session screen.** Replace the bare `NSOpenPanel` flow with a Claude-Desktop-style welcome pane: recent projects as chips, recent sessions, "Open folder…" as the explicit fallback. First thing seen on launch and on ⌘N.
14. **Sidebar status legibility.** The 8 px clay "working" dot and red "needsApproval" dot are indistinguishable at a glance. Redesign session-state signalling — shape + color + tooltip, and approvals must be unmissable (badge/pulse). Pairs with the dock badge (feature 7).
15. **History hygiene: subagent transcripts.** Subagent transcript files currently appear as ordinary sessions in sidebar history. Filter or group them under their parent session (the on-disk analog of feature 5; share the detection logic).
16. **Resume semantics.** Resume-from-history silently spawns a new live session, which surprises (fork-like behavior, new session ID). Make the affordance explicit — "Continue" vs "View transcript" as separate actions, forks labelled as forks. *Also surface (don't silently accept) the `$HOME` fallback when a session's original cwd no longer exists (FOLLOWUPS).*
17. **Side inspector (Electron parity).** Tool/code activity as compact one-line summaries in the transcript that open a side inspector panel with the full payload — not inline disclosure. Design the inspector once; route diff detail (1), raw tool I/O, and subagent drill-down (5) through it. Include bubble-width tuning while in the layout.
18. **Sidebar organization QoL.** Sorting options (recency / name / project) and pinning in v1; tagging only if it falls out cheaply (gate wishlist — keep minimal).

## Locked decisions

- SwiftTerm is the only new dependency, app target only. ClaudeKit stays zero-dep.
- GUI↔TUI handoff rule: one process per session ID, ever. The suspend/re-attach dance above is the invariant that keeps transcripts uncorrupted.
- Chat scratch dirs live under Fabled's app support, not `/tmp` — they must survive reboots because their transcripts are the chat history.

## Tech debt riding along (from FOLLOWUPS — bundle with the feature touching that layer)

- `events`-before-`start()` returns a dead placeholder stream — ClaudeKit API sharp edge (with feature 6, which manipulates session lifecycle).
- Tool/raw card expansion `@State` resets when LazyVStack recycles rows (with feature 17 — the inspector likely obsoletes inline expansion state).
- `HistoricalSessionView.task(id:)` stale-assignment window on rapid switching (with feature 16).
- `transcript(for:)` heavy reads on the store executor — only if transcript-open feels slow during feature 16 work.

## Verify by probing (during plan-writing)

- AskUserQuestion request/response shapes end to end.
- ExitPlanMode input shape (plan markdown location) and approve/deny semantics.
- Whether `--resume` on a session that has a live GUI process misbehaves (test the invariant's failure mode deliberately, in a scratch project).
- Notification-worthy signal for "turn finished": `result` event suffices, but check long multi-turn autonomous runs (post_turn_summary cadence) on a real cowork-style task.
- How subagent transcript files are distinguishable on disk (path shape `<session>/subagents/`? sidechain flags?) — feature 15 needs a reliable predicate.

## Definition of done (v1)

Ben retires the Electron app for daily work: coding sessions, chats, and folder tasks all run in Fabled; the terminal is optional, not required; nothing in a normal week forces a fallback. The gate irritants are gone: sessions never look dead (shipped in Plan 3), approval-needed is unmissable, history shows only real sessions, and a new session starts from a welcome screen rather than a file dialog.
