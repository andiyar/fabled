# Handoff — 4c Work Stream B: LOCKED; B0 + B1.1–B1.3 landed; B1.4/B1.6/B1.5 + B1 gate next — 2026-07-12 (session e87008fa)

> If the next session reads nothing else: 4c is **LOCKED** and executing on branch `plan-4c-work-stream-b` (worktree `.worktrees/plan-4c-work-stream-b`, pushed to origin). **B0** (theme) is DONE + Ben-gated (mode-flip confirmed, row 29 CLOSED). **B1.1/B1.2/B1.3** landed (sticky model, Home affordance, home-inbox rebuild). The **home mockup is Ben-APPROVED**. Next in order: **B1.4** (composer chips) → **B1.6** (multi-folder, Ben-added) → **B1.5** (type-to-resume) → **B1 gate** (Ben's eyes on the built home). Execute the triplet; verify behaviourally. Spec: `docs/superpowers/plans/2026-07-12-4c-work-stream-b.md`.

## TL;DR state

| item | status |
|---|---|
| 4c plan | ✅ LOCKED 2026-07-12 (Ben) — on branch |
| B0 theme (palette + mode-aware tokens + serif wordmark + shell) | ✅ DONE, Ben-gated — row 29 CLOSED ("yes the app was mode responsive") |
| B1.1 sticky `preferredModel` | ✅ DONE (abc1b85), reviewed |
| B1.2 Home affordance / ⌘N=Home | ✅ DONE (2d4ae7c), reviewed |
| Home-screen mockup | ✅ Ben-APPROVED (`scratchpad/fabled-home-mockup.html` + hosted artifact) |
| B1.3 home inbox rebuild | ✅ done, pending-verification (7d9cb16; build green, invariants clean) — **Ben has NOT seen the BUILT home yet** |
| B1.4 composer chips (model/effort/Auto) | ❌ OPEN — next; context prepped below |
| B1.6 multi-folder / `--add-dir` (row 33, Ben-added) | ❌ OPEN |
| B1.5 type-to-resume | ❌ OPEN |
| B1 gate (Ben verifies built home + chips + resume + multi-folder) | ❌ OPEN |
| B2 / B3 / B4 | ❌ OPEN (later phases) |

## What happened this session

Reviewed the DRAFT 4c plan against **live source** before trusting it (verified the palette hex are really in the mockups; verified row-25's grouping cause in `TimelineDisplay.swift:38-45`). Took Ben's 3 lock-time scope calls and LOCKED the plan. Set up the worktree, baseline **301 green**, pushed. Built **B0** (palette test-pinned + mode-aware `Theme` tokens + serif wordmark + shell) via implementer→review; Ben ran the B0 gate and confirmed mode-responsiveness (**row 29 CLOSED**) — he found the dark reads near-black on a bare screen but **kept the locked values** once shown a bare-vs-accented swatch. Built **B1.1** (sticky model) + **B1.2** (Home affordance). Ben asked for multi-folder / "dual use" sessions → verified the CLI supports `--add-dir` → added it to 4c as **B1.6** (row 33, DECISIONS). Co-designed the **home screen** (it had no prior pixel mockup) via a hosted Artifact → **Ben approved** → built **B1.3** (home inbox rebuild). Stopped here on a clean commit for a fresh session (context budget).

## Ruled out / corrected WITH EVIDENCE — do not re-chase

1. **Row-25 (step-grouping) is broken by `thinking`, NOT by permission lines.** On-disk transcripts have no control/permission lines; `TimelineDisplay.grouped` (`TimelineDisplay.swift:38-45`) flushes the run on ANY non-tool item, so a `thinking` between tools breaks it and `minimumRun=3` almost never fires. The B2.1 fix (transparent interstitials) targets this. Verified against source this session.
2. **Git identity is `andiyar@gmail.com`** (not the `Moonlit-Studio.local` the old handoff/memory claimed — that was STALE). Push is fine (Ben approved). Origin: `github.com/andiyar/fabled`.
3. **Tag storage is a dedicated `tags.json`, NOT "the custom-title sidecar store"** (that store is read-only — titles come from CLI-written transcript lines). Corrected in the plan's invariant 2 / B4.2; noted in DECISIONS to confirm with Ben at B4.

## Landed (all committed on `plan-4c-work-stream-b`, pushed)

- `c8d23c6` docs: lock 4c plan + 3 scope calls (row-15 last-model→session page; Create-PR omitted from git-strip v1; Screenshots→.gitignore)
- `c71492b` B0.1 Palette (test-pinned locked values)
- `eb6ea0f` B0.2 mode-aware Theme tokens + serif wordmark + shell
- `2ffef8e` docs: close UX-LEDGER row 29 (Ben-gated)
- `abc1b85` B1.1 sticky `preferredModel`
- `2d4ae7c` B1.2 `goHome` + Home toolbar button + ⌘N=Home
- `6eb9ab5` docs: add multi-folder (B1.6 / row 33) to scope
- `7d9cb16` B1.3 home inbox rebuild

Tests: baseline 301 → **306, 0 failures** (B0.1 +3, B1.1 +1, B1.2 +1). App **BUILD SUCCEEDED**.

## Key facts / landmines for the next session

- **`Fabled.xcodeproj/` is GITIGNORED** (xcodegen-generated). Run `xcodegen generate` locally after adding any `App/` file; **never** commit `project.pbxproj`. `git add -A` is safe (it's ignored). Worktree DerivedData = `Fabled-dytognfovtfrerayyqomuwhlvgpd` (its `Build/Products/Debug/Fabled.app` is the one to launch — NOT the Jul-9 main-checkout build).
- **Subagents can flake**: B1.1's first background dispatch returned 0 tool uses / no work. Re-dispatch with an explicit "you MUST actually use your tools" preamble, and **VERIFY every subagent's commit against `git log` + grep the files** — never trust the report alone.
- **Invariants (held so far, keep holding):** no raw hex in views (colours via `Theme` tokens); no `.preferredColorScheme`; row activation via `.onTapGesture` not `Button`; `xcodegen generate` after new `App/` files; type-to-resume MUST route through `AppModel.resume(_:fork:)` (one-process); never sum `total_cost_usd` (assign); tags get `tags.json`, never write CLI transcripts.
- **Ben's working rules:** plain English in gate checklists (never code/plan names); **co-design the look** — mockups he reacts to, never ship-then-ask. Memories: `fabled-plan-status`, `fable-kit-method`, `ben-plain-english`, `ben-design-consultation`, `ben-creative-phd-use`, `fabled-ux-ledger`.
- **CLI**: 2.1.206. `--add-dir <directories...>` confirmed present (for B1.6). `--permission-mode`, `--model`, `--effort` are threaded at spawn (permission hotfix) — B1.6 extends the SAME arg builder.

## Open work, ordered

1. **B1.4 — composer chips (model/effort/Auto).** Create `App/ComposerChips.swift`, `enum Target { case newSession; case live(ChatSession) }`. REUSE existing picker logic (read this session): `PermissionPickerMenu.modes` (default/plan/acceptEdits/bypassPermissions/**auto**) → writes `app.preferredPermissionMode` for `.newSession` (its "New sessions" section already does this — `PermissionPickerMenu.swift:62-70`); `EffortPickerMenu.fallbackLevels` (low/medium/high/xhigh/max) → `app.preferredEffort`; **model chip for `.newSession` uses `ModelOption.merged(catalog: [])`** (NO live catalog pre-spawn — `ModelPickerMenu.swift:92-97`) → writes `app.preferredModel`. For `.live`: `session.setModel/setEffort/setPermissionMode` over `session.models`. Style per plan §1.2/§2.5 (`Theme.panelRecessed` fill, `Theme.hairline`, radius 7–8, model-chip text `Theme.accentBronze`). Wire `ComposerChips(target: .newSession)` into `WelcomeView`'s composer chip row (beside the existing project chip). Build + review.
2. **B1.6 — multi-folder / `--add-dir` (ClaudeKit core FIRST, TDD).** `SessionConfiguration.additionalDirectories: [URL] = []`; `AgentSession` emits one `--add-dir <path>` per dir (extend the hotfix's arg builder); `AppModel.newSession(at:additionalDirectories:…)`. Then `App/RootView.swift` picker `allowsMultipleSelection: true` (first = primary cwd, rest = added) + composer project chip shows `<primary> +N`. **v1 = composer-started sessions; carrying added dirs across resume is a flagged follow-up.** Land the ClaudeKit core with/before B1.4's view.
3. **B1.5 — type-to-resume (TDD + view).** `AppModel.resumeAndSend(summary,text)` → `resume(_:fork:)` (one-process) then `session.send`. Add a resume composer (with `ComposerChips`) below the transcript in `HistoricalSessionView`.
4. **B1 gate (Ben).** Plain-English checklist: launch → inbox reads clearly; Home button returns; start composer's model/effort/Auto chips persist + drive the next spawn; a primary+extra folder starts a dual-use session; typing on a past session resumes+sends. PLUS the B1.3 built-home visual + the 3 deviations in "For Ben".
5. Then **B2** (conversation — do the **row-25 step-grouping fix FIRST**, it's Ben's headline grievance and the diagnosis is verified; then chips/grow-as-you-type/Activity list/read-only git strip), **B3** (sidebar), **B4** (tags).

## For Ben (~5 min, at the B1 gate — NOT before B1.4/B1.6/B1.5 land)

The built home (B1.3) needs your eyes, but it's cleaner to see it with the composer chips (B1.4) + multi-folder (B1.6) in place — so it's held for the B1 gate. Three known, deliberate deviations from your approved mockup to rule on then:
1. **Status label style** — I reused the existing pill+icon badge (little icon + "Needs your reply" in a capsule), not the mockup's flat coloured dot + text. Both carry the right word + colour. Want the flatter dot? One-line change.
2. **Wordmark size** — the home "Fabled" uses the 22 pt wordmark token (smaller than the mockup's larger title). If it feels small on the home, I bump it.
3. **Send button colour** — it's Claude "clay" (the established send colour), not bronze as the mockup drew it.

## Resume phrase

> "Continue Fabled 4c Work Stream B. Read `docs/superpowers/plans/handoff-2026-07-12-4c-b1-partial.md`, then the plan `docs/superpowers/plans/2026-07-12-4c-work-stream-b.md`. B0 + B1.1–B1.3 are done on branch `plan-4c-work-stream-b` (worktree). Pick up at B1.4 (composer chips), then B1.6 (multi-folder), B1.5 (type-to-resume), then the B1 gate with me. Use the implementer→review triplet, verify behaviourally (not build-green), co-design any taste calls with mockups, and describe gate items in plain English. Verify each subagent's commit against git log — they flaked once."
