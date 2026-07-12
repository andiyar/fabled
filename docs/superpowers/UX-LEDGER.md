# UX ledger — Ben's GUI / usability feedback, tracked to outcome

**Why this file exists (2026-07-11):** Ben's UX feedback was reaching the docs but eroding in transit — captured in FOLLOWUPS riders, digest sections, and brief features, then demoted or cut at plan expansion with no visible decision. Audit trail: "tagging systems" (gate feedback 2026-07-09) → brief feature 18 "tagging only if it falls out cheaply" → cut from 4b T8 → absent from 4c. "Permissions has done absolutely nothing" (same gate) → filed as a stale-label cosmetic → the actual bug (no spawn-time `--permission-mode`) sat undiagnosed until 2026-07-11.

**Rules:**
1. Every gate comment and UX request from Ben gets a row here, same day it's made.
2. **The 4c expansion (and every later plan expansion) must read this file and account for every OPEN row.**
3. No row is silently demoted. Descoping a row requires a DECISIONS.md entry with Ben's explicit sign-off, linked from the row.
4. A row is CLOSED only when Ben has seen the fix in a build (gate), not when code merges.

Status legend: ✅ CLOSED (Ben-verified) · 🔨 IN FLIGHT (scheduled in an expanded plan) · 📒 LEDGERED (written down, unscheduled) · ❌ OPEN (nowhere until this file)

**Routing (2026-07-11, Ben-approved — DECISIONS "Post-4b roadmap"):** 4b executes unchanged. Then, in order:
1. **4b gate** → rows 11 (font/token values), 12 (verify Back trail via gate item 8), 21's dark-mode risk check.
2. **Permission hotfix** (immediately post-merge, bug-sized) → row 14.
3. **Design/interaction sprint** (HTML mockups → Ben reacts → DECISIONS entries) → rows 16, 17, 18, 19, 21 decided here; built in 4c.
4. **4c expansion** (friction-first: session-continuity cluster before terminal/diff panels) → rows 13, 15, and the build-out of everything the sprint decided; row 20 at Ben's discretion.

---

## Closed

| # | Date | Comment (session) | Outcome |
|---|------|-------------------|---------|
| 1 | 07-08 | "I don't love the brown background" — icon/header (`975e1785`) | Icon redone: aged-bronze harp, committed 79e2240 |
| 2 | 07-09 | Model picker: show versions by name, hardcode current models, active-model indicator, "which opus is it???" (`9f8443da` gate) | Fixed in Plan 3 gate follow-ups |
| 3 | 07-09 | Conversation layout WEIRD; code paths as summaries opening in a sidebar, not inline (`9f8443da`) | 4a side inspector (feature 17), merged 4d76919 |
| 4 | 07-09 | Row clicks flaky; whole row should be clickable, not just the chevron (`03f7002f`, `409fdeca`) | 4a click fixes ("SwiftUI click saga"), merged |
| 5 | 07-10 | Subagent drill-down ("this is how an agent looks") (`03f7002f`) | 4a T11 subagent grouping, merged |

## In flight (4b, expanded 2026-07-11)

| # | Date | Comment | Where |
|---|------|---------|-------|
| 6 | 07-09 | "Sorting in sidebar" (gate) | 4b T8 — group/sort/filter/pin (**tags did NOT make it** — see row 13) |
| 7 | 07-09 | New-session window comparison, CD vs Fabled (`9f8443da`) | 4b T9/T10 — welcome attention inbox + composer, NSOpenPanel demoted to fallback |
| 8 | 07-09 | 27 CD screenshots + "attractive, sexy, mac-assed" (`03f7002f`) → CD-UI digest | 4b T5 design tokens (harp palette, serif type scale, spacing/motion), icon wired; Ben adjusts values at gate. Digest's 4c-flavored items remain 📒 (diff panel, background-tasks panel); §6's application scope is OPEN — see row 21 |
| 9 | 07-10 | "Make it FASTER" — 30s+ dead activation (`03f7002f`) | 4b T2 effort control + T3 thinking stream (headline priority) |
| 10 | 07-09 | Subagent sessions visible in sidebar history (`9f8443da`) | 4b feature 15 (rescoped to disk reality) + T8 activity filters |
| 11 | 07-11 | "Even the FONT sucks" (`2b161833`) | 4b T5 type scale; **Ben must vet the actual typeface at the 4b gate** — if it still sucks there, reopen this row |

## Ledgered, unscheduled

| # | Date | Comment | Where it sits |
|---|------|---------|---------------|
| 12 | 07-10 | Inspector needs a BACK button between tool views (`03f7002f`) | FOLLOWUPS rider ("Back trail"). Verify whether 4b's inspector work covers it; if not, 4c |

## OPEN — must reach the 4c expansion

| # | Date | Comment | Notes |
|---|------|---------|-------|
| 13 | 07-09 + 07-11 | **Tagging systems** for sessions (gate; re-raised twice) | Demotion trail: gate → brief 18 "only if cheap" → cut from 4b T8. Custom-title sidecar store is the natural home for tag storage |
| 14 | 07-09 + 07-11 | **Permission modes don't work** ("has done absolutely nothing"; bypassPermissions still prompts) | Root cause found 2026-07-11: no code path passes `--permission-mode` at spawn (`newSession`/`resume` never set it; SessionConfiguration supports it). Only route is the toolbar control op, which the CLI doesn't validate. Fix: spawn-time mode + persist per session |
| 15 | 07-11 | **Sticky model + mode on resume** — "the model goes to default… I don't even know what the last model was" | `resume()` builds a bare config; `SessionSummary` doesn't record model. Model is derivable from transcript JSONL (assistant messages carry it). Show last model in sidebar/history too |
| 16 | 07-11 | **Type-to-resume** — composer should be present on a historical session; typing resumes it (CD behavior) | 4b T12 formalizes explicit Continue/View actions — fine as *also available*, but the composer-first path is the friction fix. Compatible with the one-process invariant |
| 17 | 07-11 | **Composer-adjacent controls** — model/permission pickers near the text box, not the toolbar | Digest already calls CD's composer chips "a strong pattern"; never scheduled |
| 18 | 07-11 | **Permission-mode curation** — CD-style "Auto" instead of raw wire-mode names | Probe what CD's "Auto" maps to on the wire; present curated modes |
| 19 | 07-11 | **Design-iteration phase** — the app is "generic, boring, dime a dozen"; iterate the look via HTML mockups before building, then lock into Theme tokens | 4b T5 is foundation only. Proposed: mockup-driven design loop as a first-class 4c phase (or pre-4c mini-phase) |
| 20 | 07-11 | Commit `Screenshots for GUI etc/` — the CD-UI digest cites cd-01..cd-23 / fabled-01..03 from an **untracked** folder | Digest's source material should be in the repo (NOTE: a prior session marked it intentionally untracked — Ben decides) |
| 21 | 07-10 | **Digest §6 "mac-assed" application scope** — native materials/sidebar vibrancy, toolbar treatment, SF Symbols discipline, proper dark mode, applied transitions (inspector slide, card appearance), empty states, keyboard-first affordances | 4b T5 shipped only the foundation (tokens + icon + serif scale); §6's "dedicated polish gate" shrank to one line (T15 gate item 10). The application pass has no scheduled home in 4b or 4c. Risk: T5 tokens are fixed hex — verify light/dark adaptivity at the 4b gate. Pairs with row 19's mockup-driven design phase |

## 4b GATE RESULTS (2026-07-12, Ben ran the build, verbatim reactions)

**Headline:** the plumbing works; the product still reads as a generic SwiftUI app and Ben feels shut out of the design. Effort speed and state-identity are the only unqualified wins. Several 4b features are illegible or unwanted as delivered — not "polish", but "wrong or invisible." **Two meta-failures dwarf the feature bugs: (a) I never brought Ben into the design, and (b) I keep describing the app to him in internal jargon.** Both are logged as feedback memories, not just rows.

| Gate item | Ben's verdict (verbatim / close) | Row impact |
|---|---|---|
| 1. Effort/model on new-session picker | ❌ "The new session picker does NOT include the ability to choose effort or model." Only pick-project + message-to-begin. **Plus: NO WAY to return to the new-session picker without reopening Fabled.** (screenshot on Ben's machine) | NEW row 22 (picker controls) + NEW row 23 (no return-to-welcome). Pulls row 17 forward — it's a gate miss, not a nicety |
| 2. Effort speed | ✅ "yes that seems to be a bit quicker" | Row 9 — effort lever CONFIRMED. (Thinking-stream half still unvetted — see item, Ben didn't call it out) |
| 3. "Welcome inbox" | ❌ "I don't know what this actually refers to, what is the welcome inbox? this is gibberish." | Row 7 REGRESSES to OPEN — the attention-inbox concept is not legible in the build AND I described it in jargon |
| 4. Sidebar status badge | ❌ "the only badge I can see is a tick? and it's under Live? is this meant to be useful" | NEW row 24 — feature 14 status legibility REJECTED as delivered (single idle session = lone green tick, communicates nothing) |
| 5. Notifications | ⚪ "Haven't seen this." Untested (never triggered / never backgrounded into a gate) | Row unchanged; re-demo next gate |
| 6. Continue/Fork resume | ❌ "I don't know why I even want this option at all. This is some[thing] we have discussed earlier." | Row 16 REINFORCED — Ben wants **type-to-resume**, not an explicit Continue/Fork/View choice. T12's framing is not what he asked for |
| 7. Step grouping | ❌ "gibberish. I opened a 22 step task and all i see is continuous transcript. it doesn't collapse into summaries like the CD does." | NEW row 25 — **step grouping DOES NOT WORK in his real session.** Suspect: gated tools break every run (<3 consecutive finished non-anchor calls); the quality reviewer flagged exactly this. Feature is invisible in normal permission-prompted usage |
| 8. Historical drill-down / Back | 🟡 back button confirmed ("there is finally a back button in the inspector"); **the smoke session I named was not findable** so Ben tried another. Annoyed at "walks the trail" jargon | Row 12 (Back button) CONFIRMED present. Findability of a specific session = note. Jargon = feedback memory |
| 9. Liveness | ⚪ not mentioned / untested | Row unchanged |
| 10. Design | ❌ "the icon is nice. the splash screen is a start. **it's still a generic, boring, swiftUI app. you haven't asked me for any feedback on design, GUI, or anything, and I'm sick of being ignored.**" | Rows 11/19/21 ESCALATED — see below. **Loudest signal of the gate.** |
| 11. State identity (drafts) | ✅ "seems to work" | CONFIRMED |
| 12. Task checklist | ⚪ "didn't test got bored of this." | Untested |

### New rows from the 4b gate

| # | Date | Comment | Notes |
|---|------|---------|-------|
| 22 | 07-12 | **New-session picker has no effort/model control** — only project + message | The pickers live in the ConversationView toolbar (post-launch), never on the welcome composer. Ben expects them at session-start. Direct instance of row 17. Small fix but a gate miss |
| 23 | 07-12 | **No way back to the new-session / welcome screen** without quitting Fabled | Welcome shows only on `selection == nil`; nothing deselects. Need a "New session"/home affordance that returns to the welcome inbox (⌘N currently jumps to the folder picker, not the inbox) |
| 24 | 07-12 | **Sidebar badge is useless as delivered** — a single idle session shows a lone green tick under "Live", conveying nothing | Feature 14 (T6/T7) rejected at the gate. Compact icon-only badge on one idle row has no information. Reconsider: is the badge earning its space? Words/context, or drop it |
| 25 | 07-12 | **Step grouping never collapses in real sessions** — 22-step task rendered as continuous transcript, unlike CD | Root suspect: grouping needs ≥3 consecutive finished, error-free, non-anchor tool calls; gated sessions interleave permission rows that break every run (quality-review flagged this pre-merge). Either group across gates, lower/rethink the threshold, or group by turn. **Investigate against Ben's actual 22-step transcript next session** |

### Escalations (design — the row that matters most)

Rows **11, 19, 21** are no longer "verify at the gate" — Ben verified and it **failed**, with the specific charge that *he was never consulted*. The post-4b **design/interaction sprint** (already Ben-approved, DECISIONS "Post-4b roadmap") must now:
- **Lead with Ben, not with tokens.** HTML mockups he reacts to, BEFORE any Theme code. He explicitly wants to be asked. Do not present a built thing and ask him to bless it — co-design it.
- Treat "generic, boring SwiftUI" as the problem statement. T5 tokens are foundation only; the app has no native materials/vibrancy, no real motion, no distinctive layout — digest §6's whole application pass (row 21) is undone.
- Reopen row 11 (font) — still sucks per the gate.
- His design commentary already lives in this ledger + the CD-UI digest + DECISIONS; **read them and engage him** rather than re-deriving.

**Status flips:** rows 7, 11, 19, 21 → ❌ OPEN (were IN FLIGHT / gate-pending). Rows 9 (effort), state-identity → effectively ✅ pending formal close. Rows 16, 17 → reinforced/pulled-forward. New rows 22–25 → ❌ OPEN.

## Design sprint — decisions (2026-07-12, session e1cf0e99)

Row 19's mockup-driven design phase, **executed with Ben** (HTML mockups he reacted to, ~6 rounds; DECISIONS "Fabled design language locked WITH Ben"). New status: 🎨 **DESIGN-DECIDED** = look/interaction settled with Ben in mockup; still ❌ until built and Ben verifies in a build (rule 4 stands — mockup approval is not build approval).

Locked: mode-aware palette (dark **Teal Midnight** / light **Linen** — the warm-neutral halfway; bronze is the organising accent, teal rejected as the light ground, cream as too warm), New York serif wordmark + SF UI, home = attention inbox + bottom composer with model/effort/**Auto** chips + persistent Home + type-to-resume, conversation = collapsed step-group summaries + inspector-defaults-to-Activity-task-list (drill in / Back out) + composer-grows-as-you-type + git footer strip.

Rows now 🎨 design-decided (build in 4c, then gate): **6** (sidebar sorting → two-level Date › Project grouping via the funnel), **13** (tags → plain text chips, searchable picker, rename/delete, AND-filter — the cut row, back in), **7** (legible "waiting on you" inbox), **11** (font → New York serif — reopened row now answered in design), **16** (type-to-resume — composer is the front door), **17** (composer-adjacent model/permission chips), **18** (curated "Auto" mode chip), **19** (this sprint IS the phase), **21** (mac-assed: mode-aware materials, motion, git strip — foundation set), **22** (model/effort on the start composer), **23** (Home affordance returns to the inbox), **24** (useless badge replaced by word-labels + the Activity list), **25** (step grouping — visual settled; **build must still make grouping survive permission-gate interleaving**, the original root cause).

New rows from the sprint:

| # | Date | Comment | Notes |
|---|------|---------|-------|
| 26 | 07-12 | **Right panel = Activity / background-tasks list by default**, each row clickable in-and-out | Ben: "the tasks (background?) showed as a list of summaries… clickable in and out." Generalizes CD's background-tasks panel (digest §2c) + subagent drill-down (4a T11) into a session-wide activity ledger; live tasks pulse, finished ones drill to detail with Back. 🎨 design-decided |
| 27 | 07-12 | **Composer grows as you type** (multi-line, ~8 lines then scrolls) — not a horizontal run-on | Ben asked directly whether it expands like CD. Yes. 🎨 design-decided |
| 28 | 07-12 | **Git footer strip** — branch · session ±diff · time · cost · Create PR | Adopted from digest §2b (cd-14). Quiet transcript-footer at the bottom of the conversation view. 🎨 design-decided |
| 29 | 07-12 | **Mode-aware appearance** — follows the system light/dark setting, no toggle | Direct answer to Ben "so it's mode aware?"; satisfies row 21's proper-dark-mode requirement. 🎨 design-decided |
| 30 | 07-12 | **Two-level sidebar grouping** — primary axis + sub-axis (default **Date › Project**), funnel-driven | Ben: "primary sort by DATE but subsort by PROJECT." Any pair allowed. Attention/Working float above all grouping. 🎨 design-decided (extends row 6) |
| 31 | 07-12 | **Multi-select scoped to tagging** — Pin/Archive are per-row (right-click); select-many exists only to Tag… several at once | Ben: general bulk actions "more effort than it's worth," but multi-select "makes sense for tagging." 🎨 design-decided |
| 32 | 07-12 | **Ben's tag workload is creative/academic, not just dev** — characters, scenes, chapters, papers, lit-review | Tags must scale (searchable, counts, delete/rename); colour reserved for projects (tags plain). See memory [[ben-creative-phd-use]]. Shapes rows 13/30. |

---

*Sources: full transcript sweep 2026-07-11 (`~/.claude/projects/-Users-andiyar-Developer-Fabled/*.jsonl`, sessions `975e1785`, `9f8443da`, `409fdeca`, `03f7002f`, `5a018155`, `2b161833`) + 4b gate 2026-07-12. Companion docs: FOLLOWUPS.md (tech riders), DECISIONS.md (scope calls), plans/2026-07-10-cd-ui-digest.md (screenshot distillation).*
