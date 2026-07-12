# Handoff — 4c Work Stream B: B1 BUILT + Ben-GATED + REWORKED; B2 next — 2026-07-12 (session 06fcac68)

> If the next session reads nothing else: 4c is executing on branch `plan-4c-work-stream-b` (worktree `.worktrees/plan-4c-work-stream-b`, **pushed to origin**). **All of B1 is built** (B1.4 composer chips, B1.6 multi-folder, B1.5 type-to-resume) via the implementer→review triplet. **Ben ran the B1 gate on the real app and it went well** — several rows CLOSE. He found real gaps; they were **reworked and re-verified with him the same session** (11 commits, R1–R4). Tests **308 XCTest + 3 swift-testing = 311, 0 failures**; app builds + launches clean. Remaining: a couple of small B1 nitpicks (Home left/right-of-filter noodle) + more nitpicks Ben paused before giving. **Next: finish B1 nitpicks with Ben, then PHASE B2 (conversation) — do the row-25 step-grouping fix FIRST (his headline grievance, root cause verified).** Spec: `docs/superpowers/plans/2026-07-12-4c-work-stream-b.md`.

## TL;DR state

| item | status |
|---|---|
| B0 theme | ✅ DONE + Ben-gated (row 29 CLOSED) |
| B1.1 sticky model / B1.2 Home affordance / B1.3 home inbox | ✅ DONE (prior session) |
| B1.4 composer chips (model/effort/Auto) | ✅ DONE + reviewed (`2b69752` + `31e71d1`) |
| B1.6 multi-folder (`--add-dir`) core | ✅ DONE + reviewed, TDD (`8905b65` + `1e7947b`) |
| B1.5 type-to-resume | ✅ DONE + reviewed, TDD (`55f2db3` + `36cf39d`) |
| **B1 gate (Ben ran the built app)** | ✅ RAN 2026-07-12 — went well; issues reworked same-session |
| B1 rework R1–R4 (gate fallout) | ✅ DONE (`f4ff348`, `22eef20`, `76ad929`, `91f8092`, `0c13314`) |
| B1 residual nitpicks | ⏳ Home L/R-of-filter placement; more nitpicks Ben paused before giving |
| B2 conversation (row 25 FIRST) / B3 sidebar / B4 tags | ❌ OPEN — next phases |

## What happened this session

Picked up at B1.4 from the prior handoff. Built **B1.4** (composer chips), **B1.6** (multi-folder core, TDD), **B1.5** (type-to-resume, TDD) — each implementer→spec-review→quality-review, every subagent commit verified against `git log` (they flaked once — see landmines). Then **Ben ran the B1 gate on the real app.** Verdict: "a good try" → after rework, clearly landing. He confirmed: old Continue/Fork gone ("yeay"), resume chips show model/effort/mode ("great"), multi-folder works ("yes… okay, I like the pills"), Lately-3, bigger wordmark, bigger hit targets — all yes. Reworked his gate feedback in four passes (R1–R4) and relaunched between each so he could react. Ended on a clean, pushed tree at his request to save + hand off.

## Ben's B1 gate feedback → what was done (all committed this session)

1. **Continue/Fork unwanted** — both removed from the past-chat toolbar (typing resumes now). `f4ff348`. ✅ Ben: "yeay"
2. **Resume flew blind ("default default default")** — the past-chat message box now **shows + lets you change** that chat's real model + permission (recovered from its transcript) and effort. ⚠️ *Effort is NOT recorded in a chat's transcript* (`SessionResumeState` only carries model + permissionMode) — so the effort chip shows the user's default, settable, never a silent switch; model + permission show the chat's actual last values. Overrides thread through `resume(_:fork:model:effort:permissionMode:)`. `22eef20` (TDD: `testResumeUsesExplicitOverrides`). ✅ Ben: "great"
3. **Multi-folder only picked siblings** — Ben needs folders from different locations (manuscript + notes). Reworked to: pick a **primary** + **"Add folder…"** from ANY location (own single-select panels), removable pills, `+N` label. Old `allowsMultipleSelection` panel + `RootView` fileImporter removed; `AppModel.isPickingFolder` now dead-but-harmless (removing it would touch a test — left it). `76ad929`. ✅
4. **Home button in the wrong place** (next to the chat title) — moved out of the detail toolbars (R1) → sidebar top toolbar. ⚠️ LANDMINE: `ToolbarItem(placement: .navigation)` on the **sidebar** column re-hoists to the **detail** title area (Ben: "home is next to the name of the session. Again."). Fix: plain `ToolbarItem { }` (automatic, mirrors the Filter button) → lands in the sidebar. `0c13314`. Ben: fine, just noodling whether it sits left or right of the filter control.
5. **Too many latelies / "just a list"** — Lately trimmed 8 → 3. `f4ff348`
6. **Wordmark too small** — `Theme.wordmark` 22 → 34pt (used only by the home header). `f4ff348`
7. **Hit targets too small for easy picking** — `ChipLabel` enlarged (font 12→13, more padding) → all composer/resume chips bigger; folder pills + remove-× enlarged with a real tap target. `91f8092` / `0c13314`

## UX-LEDGER rows this gate CLOSES (Ben-verified in build)
7 (legible home), 16 (type-to-resume), 17 (composer-adjacent controls — home; conversation = B2.2), 18 (curated Auto), 22 (model/effort on start composer), 23 (way back to welcome), 33 (multi-folder). **Row 15 PARTIAL** — resume box now shows the last model; the sidebar/history-header last-model label is still B3.5. New rows 34–40 logged in the ledger's "4c B1 GATE RESULTS" section, all reworked this session.

## Landmines / gotchas for the next session

- ⚠️ **Bash cwd does NOT reliably persist between tool calls here** (unlike the memory's old `git -C` note — same lesson). The parent repo `/Users/andiyar/Developer/Fabled` is a **different checkout on `master`**; a `git`/`swift`/`xcodebuild` without an explicit `cd .worktrees/plan-4c-work-stream-b` may silently run against master. **Always prefix every command with `cd /Users/andiyar/Developer/Fabled/.worktrees/plan-4c-work-stream-b &&`.**
- ⚠️ **`ToolbarItem(placement: .navigation)` in a `NavigationSplitView` sidebar hoists to the DETAIL column's title area**, not the sidebar. For a sidebar-toolbar button use a plain `ToolbarItem { }` (automatic), matching the existing Filter item.
- ⚠️ **LaunchServices multi-copy**: there are ≥5 `Fabled.app` bundles in DerivedData sharing one bundle id. The worktree build is `~/Library/Developer/Xcode/DerivedData/Fabled-dytognfovtfrerayyqomuwhlvgpd/Build/Products/Debug/Fabled.app` — `open` that exact path. To relaunch after a rebuild: `osascript -e 'quit app "Fabled"'; sleep 2; open <that path>`.
- ⚠️ **`Fabled.xcodeproj/` is gitignored** (xcodegen-generated). Run `xcodegen generate` after adding any new `App/` file; never commit `project.pbxproj`; `git add -A` is safe.
- ⚠️ **Subagents flaked twice this session** (once 0 tool uses on a background dispatch; once the opus code-reviewer returned garbled text with 0 tool uses). Re-dispatch fresh with an explicit "you MUST actually use your tools" preamble, and **verify every subagent commit against `git log` + read the files** — never trust the report.
- **`swift test` baseline is 308 XCTest (0 fail, 6 env-gated skips) + 3 swift-testing.** No GUI test target (`Fabled` scheme `testTargets: []`); views are verified by build + Ben's gate.
- **Screenshotting the app from here is unreliable** — the window sits on a Mission-Control Space `screencapture` can't reach, and scripted `System Events` peeks are blocked (no assistive access). Ben drives the app himself; hand him the build + a plain-English checklist.

## Invariants (held; keep holding)
No raw hex in views (colours via `Theme` tokens); no `.preferredColorScheme`; row activation via `TapGesture` not `Button` in transcript rows; type-to-resume routes through `AppModel.resume(_:fork:)` (one-process); never sum `total_cost_usd`; tags get their own `tags.json` (B4). The composer chip look is now the shared `App/ChipLabel.swift` — one place to change; `ComposerChips` is generalized to three `Binding<String?>` (home binds `$app.preferred*`, resume binds per-chat `@State`).

## Landed this session (all on `plan-4c-work-stream-b`, pushed; 11 commits since the handoff doc `e83e585`)
`2b69752` B1.4 chips · `31e71d1` B1.4 review (shared ChipLabel, drop dead `.live`) · `8905b65` B1.6 core · `1e7947b` B1.6 review · `55f2db3` B1.5 · `36cf39d` B1.5 review (draft-on-failure + reattach test) · `f4ff348` R1 (sidebar Home row, drop Continue/Fork+toolbar Home, Lately→3, wordmark→34) · `22eef20` R2 (resume-aware model/effort/permission) · `76ad929` R3 (multi-folder from anywhere) · `91f8092` R4 (Home→sidebar toolbar, bigger chips/pills) · `0c13314` R4-fix (Home toolbar placement).

## Open work, ordered
1. **Finish B1 nitpicks with Ben** — Home left/right-of-filter placement; whatever else he flags (he paused mid-nitpick to save). Small.
2. **PHASE B2 — conversation.** Do **B2.1 (row-25 step-grouping) FIRST** — Ben's headline grievance, root cause verified (`thinking` between tools flushes the run in `TimelineDisplay.grouped`, `TimelineDisplay.swift:38-45`; fix = transparent interstitials; full failing tests already written in the plan §B2.1). Then B2.2 (conversation composer adopts the SAME `ComposerChips` — bind it to a live `ChatSession` via `setModel/setEffort/setPermissionMode`; the `.live` behaviour was deliberately deferred out of B1.4 and should be built against the real conversation composer now), B2.3 Activity list, B2.4 git strip.
3. **B3 sidebar** (incl. row-15 last-model label on the history header, B3.5) · **B4 tags** (`tags.json`).

## For Ben (next session, ~2 min)
- The Home button now lives in the sidebar's top toolbar. Only open call: should it sit **left or right** of the filter control? (Trivial either way.)
- A couple of first-cut looks you saw but haven't ruled on: the **folder pills** shape, and how the **resume box presents effort** (it shows your default because a chat's history never recorded effort — happy to label that, or leave it).
- You paused mid-nitpick — bring the rest and I'll fold them into the B2 pass.

## Resume phrase
> "Continue Fabled 4c Work Stream B. Read `docs/superpowers/plans/handoff-2026-07-12-4c-b1-gate-reworked.md`, then the plan `docs/superpowers/plans/2026-07-12-4c-work-stream-b.md`. B1 is built + Ben-gated + reworked (11 commits on `plan-4c-work-stream-b`, pushed; 311 tests green). Finish the small B1 nitpicks with me (Home left/right-of-filter + any I add), then start PHASE B2 (conversation) with the **row-25 step-grouping fix FIRST**. Use the implementer→review triplet, verify behaviourally (relaunch the worktree build for me — quit first, `open` the exact DerivedData path), co-design taste calls with mockups, describe gate items in plain English, and verify every subagent commit against `git log` — they flaked twice. Always `cd` into the worktree in every shell command."
