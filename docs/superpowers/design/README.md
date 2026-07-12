# Fabled design — co-design sprint mockups (2026-07-12)

These HTML mockups were built **with Ben**, iterated round-by-round on his reactions (the design-consultation repair after the 4b gate). They are the reference for building the real app. Open them in a browser.

| File | Screen | Notes |
|------|--------|-------|
| `palette-and-light-temperatures.html` | Palette | The mode-aware system: **Teal Midnight** (dark) locked; light dialled to **Linen** — the warm-neutral halfway between Bone and Paper (teal-tinted light was rejected as cold, cream as too warm). Also shows the compact home layout in each tile. |
| `conversation-view.html` | Conversation | Collapsed step-group summaries; right panel defaults to a clickable **Activity/task list** (drill in → detail → Back); composer **grows as you type**; git footer strip. |
| `sidebar.html` | Sidebar | Attention as a **section not a badge** ("Needs you" / "Working" float); **two-level grouping** (default Date › Project); pins; multi-select scoped to tagging. |
| `tags.html` | Tags | **Plain** text chips (colour reserved for projects); searchable picker with counts; rename/delete; AND-filter. Tuned for Ben's creative/PhD tagging (characters, scenes, papers). |

## Locked palette values

**Dark — Teal Midnight:** ground `#0C1618`, panel `#122120`, sidebar `#0A1315`, ink `#E9EEEA`, muted `#8EA29A`, hairline `rgba(120,160,150,.15)`, bronze accent `#CFA669` / wordmark `#D8AE6D`, code-glow cyan `#5AC9B4` (live/attention), amber `#E0B15C` (needs-you).

**Light — Linen:** ground `#F5F4EF`, sidebar `#EBEAE3`, panel `#FFFFFF`, ink `#23211C`, muted `#6F6B61`, hairline `#E6E4DB`, bronze accent `#A9703B`, amber `#B2751C` (needs-you), slate-blue `#4E6E8C` (ready-to-review).

**Type:** New York (`ui-serif`) for the "Fabled" wordmark; SF (`-apple-system`) for UI; SF Mono for code. Native by intent.

## Canonical decisions & status
- `../DECISIONS.md` — entries "Fabled design language locked WITH Ben" and "Sidebar + tags settled" (full spec + why + revisit-when).
- `../UX-LEDGER.md` — "Design sprint — decisions" section; rows 26–32.
- Next-session brief: `../plans/2026-07-12-design-sprint-handoff.md`.

> Note: the full-window **home screen** mockup (attention inbox + composer with model/effort/Auto chips + Home button) lived in earlier rounds of `palette-and-light-temperatures.html` before it became the palette dial; its layout is fully specified in DECISIONS and echoed by the palette tiles + the sidebar's "Needs you" rows. Reconstruct from there, or regenerate as the first build step.
