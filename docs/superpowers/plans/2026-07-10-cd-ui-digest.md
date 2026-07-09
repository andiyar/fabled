# Claude Desktop UI digest — QoL & nav patterns to consider (2026-07-10)

**Source:** Ben's 24 screenshots of Claude Desktop (v1.20186.0, Code tab) in `Screenshots for GUI etc/CD UI Shots to Consider/`, plus 3 Fabled comparison shots in `.../Fabled/`. Ben's framing: **not a 1:1 copy** — these are QoL features and nav options to consider when expanding Plans 4b/4c.

**Scope decision captured same conversation:** Ben doesn't necessarily want Cowork — "pure CC for now." Recommendation ledgered below (§5).

---

## 1. Confirms / refines features already in the 4b/4c briefs

### Welcome screen (4b, feature 13)
CD's home is an **attention inbox, not just a launcher**:
- "Welcome back, Ben" + **Sessions list across all projects**, each row: status chip with words ("Needs input" orange / "Ready for review" blue), session title, **preview of what the agent is waiting on** ("Want the A/B, or shall I build with…"), project name, age, chevron. Needs-input sessions sort to top; "Show 1 more" truncation.
- A **Pull requests section** below (GitHub-backed; optional for us / later).
- **The composer lives on the welcome screen** with full context chips (see §1-composer). Starting a session = pick project chips + type. The `NSOpenPanel` is only the "Open folder…" fallback (cd-06).
- Project selection is a **recents dropdown on a composer chip** (cd-03: ~30 recent folders, checkmark on current), not a file dialog.
- "What's new" link top-right.

### Sidebar organization (4b, feature 18 — big upgrade path)
One funnel button opens a filter/sort popover (cd-07..13):
- **Status:** Active ✓ / Archived / All — ties into feature 10's archive.
- **Project:** All / per-folder list (with disambiguating path subtitle when needed).
- **Environment:** All / Local / Cloud / Remote Control / Slack — for us: skip (local-only).
- **Last activity:** 1d / 3d / 7d / 30d / All.
- **Group by:** Date ✓ / Project / State / PR status / Environment / Custom groups / None.
- **Sort by:** Alphabetically / Created time / Recency ✓.
- CD defaults to group-by-date; current Fabled groups by project. Make grouping user-switchable rather than picking one.
- Session rows carry a small blue unread/attention dot; date-group headers (Today/Yesterday/Jul 8).

### Status legibility (4b, feature 14)
CD pairs the dot with **words** for attention states ("Needs input", "Ready for review") everywhere it matters (welcome inbox rows). Sidebar rows stay compact (dot only) but the welcome screen is the unmissable-approvals surface. Adopt: text labels for attention states, colour+shape not colour alone.

### Session management (4c, feature 10) + resume semantics (4b, feature 16)
Session overflow menu (cd-23): **Rename (R), Transcript view ›, Fork (F), Archive (A), Delete (D)**, Open in ›, plus panel toggles (Artifacts, Files ⇧⌘F, Background tasks).
- Confirms our action set; adds **Fork as an explicit, labelled action** — exactly feature 16's "forks labelled as forks."
- Single-key shortcuts inside the menu are a nice touch.

### Update affordance (4c, feature 12)
"Relaunch to update — v1.20186.0" as a quiet sidebar-bottom banner with arrow (cd-01). Pattern worth copying if we do updates at all.

### Terminal (4c, feature 6 — suggests a rescope)
CD's right panel has a **plain Terminal tab** (cd-20): shell in the workspace cwd, with "[shell reconnected — replaying buffered output]" on reattach, and a "+" for more shells. This is *not* a claude-resume handoff — it's a workspace shell.
- Suggested rescope: **6a = plain terminal panel** (SwiftTerm, project cwd, cheap, huge daily-driver value); **6b = `claude --resume` GUI↔TUI handoff** (the one-process-per-session invariant dance) as the second step or later.
- **SSH (Ben 2026-07-10):** no SSH-environment plumbing needed — 6a's panel is a full login shell, so `ssh` to bare metal is free from inside it. That's the whole SSH story for v1; CD's "SSH environment" (running *sessions* on remote hosts) stays out of scope.

### Composer as context surface (touches 13/16/18)
Bottom composer chips (cd-02): environment (Local ⌄ — popover offers Local/Cloud/Remote Control/SSH, cd-04), **project folder**, **git branch**, **worktree toggle**, **add-another-folder** (+ tooltip, cd-05 — multi-root session via `--add-dir`), permission-mode chip ("Auto"), model ("Fable 5"), usage tier ("Extra"), mic. Also a dismissible model-notice banner above the composer, and a pixel-pig easter egg.
- For us: project/branch/worktree/permission/model chips on the composer are a strong pattern (Fabled has model+permission in the toolbar today). Environment picker: skip. Multi-root: note for later (see §3).

---

## 2. New patterns NOT in the briefs — recommend adding

### a. Collapsed step groups in the transcript (candidate: 4b, pairs with inspector work)
CD collapses a run of tool calls into a single summarized row — "Committed WIP convergence state ›", "Ran 2 commands ›", "Saved 3 memories ›" — which **expands inline** to the full tool rows / code blocks / diffs (cd-14/15/16). The main transcript reads as prose + a few summary lines instead of 15 Bash rows.
- Biggest transcript-hygiene delta between CD and current Fabled (fabled-01 shows every tool row).
- Fits our reducer/timeline architecture (a grouping pass over consecutive tool items). Summary text can be derived (tool count / first description) even without model-authored labels.

### b. Working-tree diff panel + git footer bar (candidate: 4c, or its own slice)
- Transcript footer strip (cd-14): `fabled · master · +13,412 −48 · [Create PR ⌄]` — cumulative session diff at a glance.
- Right panel "master → working tree" (cd-21): per-file list with +N/−N, collapsed for large diffs, click to expand a file. ⇧⌘F "Files" panel.
- High daily-driver value ("what did this session actually change?"). Create PR button optional (gh CLI exists); the *view* is the valuable part.

### c. Background tasks panel (candidate: 4c, pairs with features 5/11)
Right panel listing background/finished tasks (cd-01/19): each Bash task shows description + Completed; each **agent task shows duration, token count, tool-use count, and a "View transcript" link**. Header: "Finished 86 ⌄" + Clear.
- We already have subagent drill-down (4a T11); this generalizes it into a session-wide activity ledger. Good home for liveness/long-running-work visibility (feature 11).

### d. Inline-expandable file-edit chips (observation only — 4a locked inspector-first)
CD renders edits as "Edited fabled-plan-status.md +7 −3 ⌄" chips expanding **inline** to a line-numbered diff with red/green region highlights (cd-16/17/18). We deliberately routed full diffs to the side inspector (ledgered 4a decision — do not relitigate for v1). Ledger as a possible later "peek inline" affordance. Our +N/−N chips (T7) already match CD's grammar.

## 3. Note for later (don't schedule yet)
- **Multi-root sessions** ("Add another folder", cd-05) — CLI `--add-dir`; touches session model, sidebar grouping, welcome chips.
- **PR inbox on welcome** (cd-02) — needs GitHub integration; revisit if/when gh-backed features land. (Fabled itself is now public at github.com/andiyar/fabled, 2026-07-10 — so gh-backed features have a live testbed, and feature 12's update-check question resolves to "link the releases page.")
- **Browser preview panel** ("Browse and verify", dev-server preview, cd-22) — out of scope for pure-CC v1.
- **Global search in titlebar** (magnifier next to sidebar toggle) — Fabled has sidebar search; fine for now.

## 4. Explicitly skip (not Fabled's product)
- Cloud / Slack environments and the environment *picker* (cd-04, cd-10) — Fabled is local-native by design.
  - **Remote Control nuance (Ben 2026-07-10):** Ben uses the `/remote-control` slash command; Fabled must be able to trigger it in a live session. Likely free (slash commands are just user text on the wire) — **PROBE at 4b/4c plan-writing:** confirm `/remote-control` round-trips through stream-json input on a live session and whether its output/QR/link renders usefully in the transcript.
  - **SSH:** covered by the terminal panel (§1 terminal rescope) — `ssh` from a real shell, no environment integration.
- Home/Code product tabs, Artifacts, Customize (CD is a multi-product client).
- Account/plan chip ("Ben · Max"), product notice banners.

## 5. Scope change: Cowork descope (needs DECISIONS.md entry when acted on)
Ben 2026-07-10: "I don't know that I want cowork necessarily. i think we can do a pure CC for now."
- **Recommendation:** drop feature 9 (Cowork preset) from 4c; mark feature 8 (Chat preset) deferred-pending-Ben (also non-CC); keep 4c = terminal, session management, resilience, app identity. 4b unaffected.
- Not yet ledgered in DECISIONS.md — do that (and amend the Plan 4 brief) when 4b/4c expansion starts, with Ben's confirmation on feature 8.

## 6. Design language directive (Ben 2026-07-10 — new workstream)
Ben: the app needs to be *attractive, sexy, mac-assed* — "a thing to do properly," not incidental polish.
- **Sequencing matters:** 4b builds the app's most visible chrome (welcome screen, sidebar, status signalling). Define the design language BEFORE or WITH 4b so those surfaces are built right once, not built plain and repainted. Recommendation: a short design-direction phase at the top of 4b (typography scale, color/material palette, spacing tokens, iconography, motion rules — extending the existing `Theme.swift` token approach) + a dedicated polish gate.
- Scope of "mac-assed": native materials (sidebar vibrancy, toolbar treatment), SF Symbols discipline, proper dark mode, animation/transitions (inspector slide, card appearance), empty states, app icon (feature 12 pulls forward here), keyboard-first affordances. CD shots show the *bones* to steal (density, chips, collapsed groups); the *skin* should be Fabled's own — warmer/serif-touched identity is already hinted by the current welcome screen's serif "Fabled" wordmark (fabled-02).
- **Resolved (Ben 2026-07-10):** the "Luminous" design system is LifeSync-only (`~/Developer/lifesync`) and doesn't translate well — Fabled's design language is its own, built from scratch. Starting cues: the serif wordmark, the existing clay-accent Theme tokens, and native macOS materials.
- **App icon already exists and is committed** (79e2240): aged-bronze harp with code-rain strings on midnight teal. Full set in `docs/assets/` — source art, 1024/256 PNGs, complete `Fabled.iconset` + `Fabled.icns`. **Not yet wired into the app target** (no icon ref in `project.yml`, no asset catalog) — trivial wiring task; pull it forward into the 4b design phase rather than waiting for 4c feature 12. The icon's palette (verdigris bronze + midnight teal + code-glow) is a strong seed for the whole design language.

## 7. Fabled-today deltas the shots make obvious (fabled-01..03)
- Welcome screen is a title + "New Session…" button over an empty pane (fabled-02) and the NSOpenPanel flow (fabled-03) — feature 13 replaces this.
- Transcript shows every tool row (no step grouping) — §2a.
- No cumulative-diff/git strip; no terminal, files, or background-tasks panels — §2b/c, feature 6.
- Sidebar: project-grouped with relative times + search (already decent); no filter/sort/archive — feature 18/10.
