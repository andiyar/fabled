# Fabled

A native macOS client for [Claude Code](https://claude.com/claude-code), built directly on the CLI's stream-json protocol — no Electron, no Node sidecar.

## Why

The Claude desktop app is Electron. The Claude Code CLI already exposes everything a client needs: a bidirectional streaming JSON protocol, on-disk session transcripts, and OAuth via keychain. Fabled is a SwiftUI app that spawns and drives the CLI directly, aiming for native performance and a UI shaped around how the user actually works.

- **Platform:** macOS 15+, Swift 6, SwiftUI
- **Approach:** pure Swift, no Node dependency — the app spawns and speaks the CLI's protocol itself
- **Escape hatch:** an embedded terminal (SwiftTerm) for anything the GUI doesn't cover yet

See [`docs/superpowers/specs/2026-07-08-fabled-native-client-design.md`](docs/superpowers/specs/2026-07-08-fabled-native-client-design.md) for the full design spec, including the empirically-verified CLI protocol facts this project is built against.

## Structure

- `Sources/ClaudeKit` — the Swift package implementing the CLI's stream-json protocol: process spawning, event decoding, session configuration, outbound control messages.
- `Sources/fabled-probe` — a small CLI for probing/recording live protocol behavior against the `claude` binary.
- `Tests/ClaudeKitTests` — unit tests (offline, fixture-driven) plus env-gated live tests (`CLAUDEKIT_LIVE=1`) against a real CLI.
- `fixtures/` — recorded real CLI protocol transcripts (`.jsonl`) used as ground truth by the test suite.
- `docs/superpowers/` — planning and coordination docs:
  - `specs/` — approved design specs
  - `plans/` — TDD implementation plans (some fully expanded, some still design briefs)
  - `COORDINATION.md` — how this project is coordinated (fresh subagent per task, reviewed against the plan)
  - `DECISIONS.md` — append-only decisions ledger

## Status

- **Plan 1 — ClaudeKit engine:** done. Protocol codec, session process management, `fabled-probe`.
- **Plan 2 — SessionStore + history search:** planned, not yet implemented.
- **Plans 3–4 — app shell and full surfaces:** design briefs only.

## Building

```sh
swift build
swift test          # offline suite
CLAUDEKIT_LIVE=1 swift test   # + live tests against a real claude CLI (costs money, uses haiku)
```
