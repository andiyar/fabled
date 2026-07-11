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

---

*Sources: full transcript sweep 2026-07-11 (`~/.claude/projects/-Users-andiyar-Developer-Fabled/*.jsonl`, sessions `975e1785`, `9f8443da`, `409fdeca`, `03f7002f`, `5a018155`, `2b161833`). Companion docs: FOLLOWUPS.md (tech riders), DECISIONS.md (scope calls), plans/2026-07-10-cd-ui-digest.md (screenshot distillation).*
