# Fabled decisions ledger

Append-only. Format per `~/Developer/fable-kit/decisions-ledger-template.md`: date · decision · why · revisit-when.

- **2026-07-08 · Pure Swift, no Node sidecar.** The Agent SDK just wraps the same CLI; a sidecar adds a runtime and an IPC hop to outsource a codec we can own. Tolerant decoding + fixtures make drift manageable. *Revisit if:* Anthropic breaks the stream-json protocol incompatibly more than ~once a quarter.
- **2026-07-08 · Depend on hidden flag `--permission-prompt-tool stdio`.** Only mechanism that turns auto-deny into interactive `can_use_tool` control requests; it is the SDK's own path, verified working on CLI 2.1.202. *Revisit if:* a CLI update removes/renames it (live tests will catch this immediately).
- **2026-07-08 · Opus subagents implement; coordinator (Fable while credits last, any model after) designs, dispatches, reviews.** Credit economics; the fable-kit method makes it work. Full handoff pack in `docs/superpowers/COORDINATION.md` + plan briefs.
- **2026-07-08 · ClaudeKit is zero-dependency.** SQLite via system C library, markdown via AttributedString, no GRDB/swift-markdown-ui. Keeps the engine auditable and the build trivial. SwiftTerm accepted later, app target only. *Revisit if:* AttributedString markdown proves unusable for code blocks (ledger the swap).
- **2026-07-08 · XcodeGen for the app target (Plan 3).** Agents can't drive Xcode GUI; `project.yml` is reviewable text; `.xcodeproj` becomes generated output. *Revisit if:* XcodeGen goes unmaintained.
- **2026-07-08 · Aesthetic: native macOS structure + Claude warmth in conversation** (serif voice, clay send button). Chosen by Ben over pure-native and dense-power-tool options.
- **2026-07-08 · Name: Fabled.** Chosen by Ben.
