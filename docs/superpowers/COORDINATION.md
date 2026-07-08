# Fabled coordination handbook

*Written by Fable, 2026-07-08, so that any capable model — Opus, Sonnet, or future Fable — can coordinate this project end to end. Read this first if you are picking up Fabled cold.*

## The arrangement

Implementation is done by **fresh subagents per task** (Opus by default); the **coordinator** (whoever is reading this) dispatches tasks, reviews results, writes new plans, and makes design decisions. This started as a credit-conservation measure (Fable coordinates, Opus types) but the structure stands on its own: it is the fable-kit method (`~/Developer/fable-kit/fable.md`, esp. §10 "driving Opus") applied to one project.

## What exists and where

- **Spec:** `docs/superpowers/specs/2026-07-08-fabled-native-client-design.md` — approved. Architecture, UI direction, and the *verified protocol facts* (every CLI flag and message shape was empirically tested 2026-07-08 on CLI 2.1.202 — trust these over intuition, and re-verify against the CLI before assuming drift).
- **Plan 1 (full, executable):** `plans/2026-07-08-claudekit-core.md` — ClaudeKit engine. Complete code in every task; a subagent needs zero design judgment.
- **Plans 2–4 (briefs):** `plans/2026-07-08-plan-{2,3,4}-*-brief.md` — design briefs with locked API contracts and task outlines. Each must be expanded into a full plan (superpowers:writing-plans skill, same granularity as Plan 1) *before* dispatching implementation subagents. Expand them one at a time, only when the previous plan's software works.
- **Decisions ledger:** `docs/superpowers/DECISIONS.md` — why things are the way they are. Append, never rewrite.
- **Fixtures:** `fixtures/*.jsonl` — real recorded CLI protocol streams; ground truth for the codec. `fixtures/record_handshake_fixture.py` re-records them against a new CLI version in minutes.

## The coordination loop

1. Read the current plan's next unchecked task.
2. Dispatch a **fresh subagent** with: the full task text (verbatim, including code), the "Conventions for implementing agents" section of the plan, and nothing else. No prior-task chatter — the plan is the interface.
3. On return, review before accepting (checklist below).
4. Check the task's boxes in the plan file, commit, move on.
5. Between tasks is where judgment lives: if a task revealed a wrong assumption, fix the plan (and ledger the decision) before dispatching the next.

### Review checklist (per task)

- Did the subagent actually run `swift test` and paste real output? "Tests should pass" is not evidence (fable-kit: verification-before-completion).
- Does the diff match the plan's code? Deviations need a reason; good reasons get ledgered, bad ones get redone.
- No scope creep: nothing outside the task's file list.
- Commit exists, message matches, tree is clean, tests green at that commit.

### Writing Plans 2–4 from the briefs

- Use the brief's **public API contracts verbatim** — they are locked so plans compose. If a contract proves wrong during planning, change it consciously and record it in DECISIONS.md.
- Follow Plan 1's format exactly: bite-sized TDD tasks, complete code in every step, exact commands with expected output, offline-first tests, env-gated live tests.
- Each brief lists "verify by probing" items — protocol behaviors Fable did not empirically confirm. Verify them with `fabled-probe` or a variant of `record_handshake_fixture.py` *during plan-writing*, and write what you observe into the plan. Do not guess message shapes.

## Ground rules (scars, not preferences)

- **Never commit red.** `swift build && swift test` green before every commit.
- **Fixtures over intuition.** If codec behavior is in question, the recorded capture wins.
- **Tolerant decoding is load-bearing.** Unknown event types must flow through `.unknown`/`.system` paths, never throw. This is the app's protocol-drift insurance; weakening it for convenience is how the app breaks on the next CLI update.
- **Do not remove `--verbose`** (stream-json requires it). **Do not use `--bare`** (kills keychain auth). **`--permission-prompt-tool stdio` is hidden but required** — without it the CLI auto-denies instead of asking.
- **Live tests cost money.** Keep them env-gated (`CLAUDEKIT_LIVE=1`), on haiku, and few.
- **Ben's preferences:** native toolchains (no Docker), macOS 15+, zero third-party deps in ClaudeKit (app-layer deps like SwiftTerm are fine and already ledgered).

## When the CLI updates

The protocol is the Agent SDK's own substrate, so it moves carefully — but it moves. On a new CLI version: run `swift test` (offline suite should still pass), then `CLAUDEKIT_LIVE=1 swift test`, then re-record fixtures if shapes changed and diff them against the old ones. New event types are *expected* to appear as `.unknown` — that is the design working, not a bug. Add typed support only when a feature needs it.

## Escalation

- Stuck after two genuinely different attempts → stop, write up what you know, ask Ben. Do not thrash credits.
- Architecture-level surprises (a locked API contract can't work, the CLI removed a flag we depend on) → ask Ben whether to spend Fable credit on a coordination session; that is the highest-leverage use of it.
