# Handoff — after the design sprint (2026-07-12)

**For the next session.** The post-4b design/interaction sprint is **done**, run with Ben directly (HTML mockups he reacted to, ~10 rounds). It went well — his words: *"getting much better."* All four screens he flagged are design-decided: **home, conversation, sidebar, tags**. What remains is **building**, not designing, plus the real bugs.

## Start here (read order)
1. `docs/superpowers/DECISIONS.md` — the two 2026-07-12 entries ("Fabled design language locked WITH Ben", "Sidebar + tags settled") are the canonical spec.
2. `docs/superpowers/design/` — the mockups + `README.md` with locked palette values.
3. `docs/superpowers/UX-LEDGER.md` — "Design sprint — decisions"; rows 26–32 are the new design-decided items; every OPEN row must still be consumed by the build plan.
4. Memory: `fabled-plan-status`, `ben-design-consultation` (co-design, never ship-then-ask), `ben-plain-english` (describe by what he sees), `ben-creative-phd-use` (he tags novels/thesis, not just code), `fabled-ux-ledger`.

**Rules that still bind:** co-design with Ben, don't present built UI for a bless (`ben-design-consultation`); plain English always (`ben-plain-english`); a UX-LEDGER row CLOSES only when Ben verifies it in a build, not when code merges.

---

## Work stream A — Permission-mode hotfix (bug-sized, do first)

Ben's oldest live grievance: permission modes "have done absolutely nothing" — `bypassPermissions` still prompts "all over the place." Root cause (already diagnosed, UX-LEDGER rows 14/15/18):

- **No code path passes `--permission-mode` at spawn.** `newSession` / `resume` never set it; `SessionConfiguration` supports it. The only route today is the toolbar control op, which the CLI doesn't validate — so it silently does nothing.
- **`resume()` builds a bare config** — restores neither the last model nor the last mode. `SessionSummary` doesn't record model (it's derivable from the transcript JSONL — assistant messages carry it).

**Fix:**
1. Pass `--permission-mode` at spawn; **persist the mode per session** so it survives resume.
2. **Sticky model + mode on resume** — record/derive the last model, restore it (and show it in the sidebar/history so Ben knows what the last model was).
3. **Curated "Auto" mode** — probe what Claude Desktop's "Auto" maps to on the wire (`probe_*.py`); present curated mode names, not raw wire strings. This is the `Auto` chip in every mockup composer.

**Done when:** Ben launches with a mode set and it actually takes effect (bypass stops prompting); resume comes back on the same model + mode; the composer's mode/model chips drive real spawn config. This unblocks the composer chips the whole design leans on.

---

## Work stream B — Build the design (4c, friction-first)

Turn the locked mockups into the real SwiftUI app. Expand this into a proper implementation plan with **`superpowers:writing-plans`**; it MUST consume every OPEN UX-LEDGER row (no silent demotion — descope needs a DECISIONS entry Ben signs).

**B0 — Theme foundation.** Turn the locked palette (design/README.md) into mode-aware `Theme` tokens — Teal Midnight (dark) / Linen (light), following the system appearance; New York serif wordmark + SF UI + SF Mono. Everything below consumes these tokens; no hardcoded hex in views.

**Friction-first ordering** (session-continuity before panels — Ben daily-drives this):

- **B1 — Home + composer.** Attention inbox ("Waiting on you" with plain word-labels + preview of what each session wants; "Lately"); persistent **Home** affordance that returns here (fixes rows 22/23); composer as the front door with model/effort/**Auto** chips at the bottom (rows 17/18/22); **type-to-resume** (row 16). New session must NOT dump into the file browser.
- **B2 — Conversation view.** Collapsed step-group summaries ("Read N files", "Ran N commands", bronze subagent groups) that expand inline; edits show `+N −N`; **the grouping must survive permission-gate interleaving** — the original bug that made step-grouping never fire in Ben's real sessions (row 25). Right panel defaults to the **Activity/task list** (live pulsing + finished, each row drills to detail with **Back**). Composer **grows as you type**. Git footer strip (branch · ±diff · time · cost · Create PR).
- **B3 — Sidebar.** Attention floats ("Needs you" / "Working" above all grouping, no per-row badge — kills row 24); **two-level grouping** default **Date › Project**, funnel-driven (Group by / Then by / Sort within); pinned section; **per-row** pin/archive via right-click.
- **B4 — Tags** (row 13, the cut one). Plain text chips (colour reserved for projects); searchable picker with per-tag session counts; starter set bug/review/design/release + user-created; rename + **delete-asks-first**; **multi-select scoped to tagging** (select many → Tag…); filter by tag via a top chip row, **multiple tags = AND**; tags editable from inside a session too. Storage: the custom-title sidecar store. Design for MANY tags (Ben's characters/scenes/papers).

**Gate:** Ben runs each screen in a real build. Describe every item to him in plain English (what he sees/does), not feature/code names.

---

## Housekeeping
- Mockups + docs committed 2026-07-12. Memory updated (outside repo).
- `Screenshots for GUI etc/` remains untracked — Ben's call (UX-LEDGER row 20).
- Push remains Ben's call; fix `user.email` before any push (currently `Ben <andiyar@Moonlit-Studio.local>`).
- `/remote-control` GUI trigger still blocked upstream — re-probe per CLI update.
