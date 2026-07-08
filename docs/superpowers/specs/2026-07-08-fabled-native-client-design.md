# Fabled — native macOS client for Claude Code

**Date:** 2026-07-08
**Status:** Approved design, pending implementation plan
**Goal:** A native Mac replacement for the Electron Claude desktop app, built on the Claude Code CLI's stream-json protocol. Full daily driver: coding sessions, general chat, and cowork-style tasks.

## Why

The Electron desktop app carries bundled-Chromium costs: RAM usage, stalls, non-native feel. The Claude Code CLI already exposes everything a client needs — a bidirectional streaming JSON protocol, on-disk session transcripts, and OAuth handled via keychain. A SwiftUI app on top gets native performance and a UI shaped around how the user actually works, with zero new backend.

## Decisions already made

- **Approach:** Pure Swift, direct protocol implementation (no Node sidecar). The app spawns and drives CLI processes itself.
- **Escape hatch:** Embedded terminal (SwiftTerm) for anything the GUI doesn't cover yet.
- **Aesthetic:** Native + Claude warmth — macOS structure (SF Pro chrome, system materials, native sidebar/toolbar), Claude design language in the conversation (serif for Claude's prose, clay send button, warm neutrals).
- **Name:** Fabled, at `~/Developer/Fabled`.
- **Platform:** macOS 15+, Swift 6, SwiftUI.
- **MCP management:** conversational (the agent edits its own config); no dedicated connector UI. OAuth flows open the browser.

## Verified protocol facts (tested 2026-07-08 against CLI 2.1.202)

All of the following were verified empirically on this machine, not assumed:

1. **Spawn command per session:**
   `claude -p --verbose --input-format stream-json --output-format stream-json --permission-prompt-tool stdio [--model X] [--resume <id>] [--fork-session] [--session-id <uuid>] [--permission-mode <mode>]`
   (`--permission-prompt-tool` is hidden from `--help` but present and functional; `stdio` routes permission prompts over the control channel.)
2. **Handshake:** client sends `{"type":"control_request","request_id":"…","request":{"subtype":"initialize","hooks":{}}}` first. The response includes the full slash-command catalog (name, description, argument hint) — the data source for a `/` autocomplete menu.
3. **Events observed on stdout** (one JSON object per line): `system/init` (session id, model, tools, permission mode, slash commands, agents, skills, CLI version), `assistant` (text and `tool_use` content blocks), `user` (tool results), `system/thinking_tokens`, `system/post_turn_summary`, `rate_limit_event`, `result` (usage, cost, duration, `permission_denials`), `control_request`, `control_response`.
4. **Permission round-trip:** without the stdio permission tool, non-sandboxed commands auto-deny ("This command requires approval"). With it, the CLI emits `control_request` subtype `can_use_tool` carrying `tool_name`, `display_name`, `input`, `description`, `decision_reason`, and `permission_suggestions` (ready-made "always allow" rules with destination, e.g. `Bash(git init *)` → localSettings). Client replies `{"type":"control_response","response":{"subtype":"success","request_id":…,"response":{"behavior":"allow","updatedInput":…}}}` (or `deny` with a message). Verified end-to-end: approval → tool executes → zero denials in `result`.
5. **Safe commands** (e.g. `echo`) run in a sandbox without any permission exchange — the UI must not expect a prompt for every Bash call.
6. **Other control subtypes verified present in the binary:** `set_permission_mode`, `set_model`, `interrupt`, `hook_callback`, `mcp_message`. (`set_model` means mid-session model switching is a first-class control message, not a slash-command workaround.)
7. **Sessions on disk:** `~/.claude/projects/<flattened-cwd>/<session-uuid>.jsonl`, one typed event per line (user/assistant messages, tool use, hook output, queue operations). Readable without any process. `--resume <id>` continues one; `--fork-session` branches.
8. **Models:** `--model` accepts aliases and full model IDs — the picker is not limited to a curated subset.
9. **Auth:** the CLI reads keychain OAuth itself. Fabled never touches credentials. (`--bare` disables keychain auth — do not use it.)

## Architecture

Two targets in one repo:

### ClaudeKit (Swift package, no UI dependencies)

- **AgentProcess** — owns one CLI child process per live session. Spawns with the verified flags, performs the initialize handshake, exposes `AsyncStream<AgentEvent>`, accepts outbound user messages and control responses. Supports resume, fork, interrupt, and mid-session `set_permission_mode`. Terminates cleanly; detects crashes and surfaces them as events.
- **ProtocolCodec** — `Codable` types for the event vocabulary with **tolerant decoding**: unknown event types and unknown fields are preserved as raw JSON (`AgentEvent.unknown(type:raw:)`) so a newer CLI degrades to generic rendering, never a crash. This is the protocol-drift insurance that makes the no-sidecar approach safe.
- **SessionStore** — enumerates and incrementally parses `~/.claude/projects/**/*.jsonl`; FSEvents watcher for live updates; SQLite FTS5 index for instant full-text history search. Past sessions render read-only with no process.
- **ModelCatalog** — known aliases plus free-text full model IDs; per-session selection; mid-session switching.

### Fabled (SwiftUI app)

- **Window layout:** native sidebar (live sessions with state badges on top; history grouped by project below; search field), conversation pane, optional inspector (session metadata, files touched, usage/cost). Multiple windows/tabs; one live session = one CLI process.
- **Conversation view:** streaming markdown with thinking indicator; Claude prose in serif, chrome in SF Pro. Tool calls as one-line collapsed cards (icon, summary, status) expanding to full input/output. Edit/Write rendered as diffs with +/− counts. TodoWrite as a pinned progress checklist. Subagent activity grouped under a disclosure.
- **Permission UX:** `can_use_tool` requests render as inline cards in the conversation (not app-modal): exact command, Allow once / Always allow (labelled with the CLI's suggested rule) / Deny with optional message; keyboard shortcuts (⌘⏎ allow, esc deny). Pending approvals badge the dock icon and post a notification; the sidebar shows "needs approval" state. Other sessions are never blocked by one session's prompt.
- **Interactive protocol surfaces:** AskUserQuestion → native option picker; plan-mode approval → review sheet; slash-command autocomplete in the composer fed by the handshake catalog.
- **Toolbar (per session):** model picker, permission mode, open-in-terminal, inspector toggle. Status bar: usage/cost from `result` events, rate-limit state from `rate_limit_event`.
- **Session browser:** browse by project, full-text search, open read-only instantly, then Resume (spawns with `--resume`) or Fork. Archive/delete with confirmation.
- **Escape hatch:** embedded SwiftTerm tab running `claude --resume <id>` for any session — GUI and TUI share the same on-disk state, so sessions move fluidly between them.
- **Chat & cowork presets:** same engine, different defaults. Chat = scratch working directory, de-emphasized tool chrome. Cowork task = folder picker, more permissive permission preset, background run with notification-driven check-ins.

## Error handling & resilience

- CLI process dies → session marked interrupted in sidebar; one-click resume (state is on disk).
- Unknown event types → generic raw-JSON card with a disclosure, plus a debug inspector.
- CLI version newer than codec-tested version (from `init` event) → quiet banner, no behavior change.
- Auth expired → surface the CLI's login message and offer to open the terminal escape hatch to `/login`.

## Testing

- Codec: unit tests against recorded protocol fixtures (real captured streams, like the ones recorded during design verification).
- AgentProcess: integration tests driving a real CLI with `--model haiku` against scratch directories (cheap, real).
- UI: SwiftUI previews and snapshot tests fed by fixture transcripts replayed through SessionStore.
- TDD on ClaudeKit; fixture-replay for views.

## Out of scope (v1)

- Dedicated MCP/connector management UI (conversational instead).
- Windows/Linux, iOS/iPadOS.
- Claude.ai web features not in the CLI (Artifacts gallery, Projects-style knowledge bases).
- Custom API-key/provider configuration UI (the CLI's own config handles it).

## Risks

- **Protocol drift:** the stream-json control protocol is what the Agent SDK rides on, so it's stable in practice but not a frozen public contract. Mitigations: tolerant decoding, version banner, escape hatch, fixture suite that can be re-recorded against new CLI versions in minutes.
- **Hidden-flag dependency:** `--permission-prompt-tool stdio` is undocumented in `--help`. It's the SDK's own mechanism, so removal is unlikely; if it changes, the fixture suite catches it immediately.
- **Long-transcript performance:** JSONL files can be large; SessionStore must parse incrementally and the transcript view must virtualize. Addressed in design; must be validated with the user's real multi-hundred-MB history early.
