# Fabled 4c — Work Stream B (build the locked design) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the co-designed, Ben-locked mockups (Teal Midnight dark / Linen light, bronze accent, New York serif wordmark) into the real SwiftUI app — home + composer, conversation, sidebar, tags — consuming every OPEN UX-LEDGER row.

**Architecture:** Logic lives in `FabledCore`/`ClaudeKit` (Swift Package, `swift test`-covered) and is built test-first; SwiftUI bodies live in the `App/` target (verified by build + Ben's gate, matching the existing split — DECISIONS 2026-07-09 "View models live in FabledCore, views in the app target"). B0 lays a mode-aware `Theme` token layer seeded by a pure, unit-pinned `Palette`; every screen below consumes those tokens (no hardcoded hex in views). Friction-first order: session-continuity (home/composer/resume) before panels (conversation/sidebar/tags).

**Tech Stack:** Swift 6, SwiftUI, AppKit (`NSColor` appearance for mode-aware tokens), XcodeGen (`project.yml` → `Fabled.xcodeproj`), zero third-party deps (DECISIONS 2026-07-08).

**Status:** LOCKED (Ben approved 2026-07-12). **Spec:** `docs/superpowers/DECISIONS.md` (2026-07-12 "Fabled design language locked WITH Ben" + "Sidebar + tags settled") · `docs/superpowers/design/` (mockups) · `docs/superpowers/UX-LEDGER.md`. **Branch:** `plan-4c-work-stream-b` (off `master`; Task 0). **Execution:** the triplet — implementer → spec-compliance reviewer → quality reviewer — per task; verify behaviourally at each gate (build-green is not "done").

---

## How to read / execute this plan

- **Five phases, B0 → B4.** Each phase produces working, testable software and is a natural review checkpoint. Execute in order (B0 is the foundation everything imports).
- **Testing strategy (a conscious, stated choice — not a placeholder lapse):** `FabledCore`/`ClaudeKit` changes are pure and get full TDD (real failing test → implement → pass → commit). SwiftUI view bodies are **not** unit-tested (the codebase has never unit-tested views; AppKit render state isn't meaningfully assertable here) — they are verified by `xcodegen generate && xcodebuild … build` **and** Ben running the screen at the gate. This is why so much behavior is pushed *down* into `FabledCore` where it can be pinned by a test.
- **A UX-LEDGER row CLOSES only when Ben verifies it in a build** (ledger rule 4). This plan's job is to *reach the gate*, not to self-certify rows closed.
- **Commands** (from `README.md`):
  - Logic tests: `swift test` — single test: `swift test --filter <TestName>`
  - App build: `xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled build`
  - `xcodegen generate` is required whenever a **new file is added under `App/`** (SwiftPM auto-globs new `Sources/**` files; the xcodeproj does not).
- Baseline before starting: `swift test` is green (301 tests per the permission-hotfix ledger). Every phase must keep it green.

---

## UX-LEDGER coverage map (REQUIRED — every OPEN row accounted for)

Ledger rule 3: no row silently demoted; descoping needs a DECISIONS entry Ben signs. Status key: 🔨 = built here; ✅-hotfix = behavior already shipped in the permission hotfix (commit 5d7a61d), this plan surfaces it in the designed home; 🚩 = Ben's-discretion, flagged not descoped.

| Row | What it is (plain English) | Phase · Task |
|---|---|---|
| 6 | Sidebar grouping/sorting | B3.1, B3.3 |
| 7 | A legible "what's waiting on you" home | B1.3 |
| 11 | The font (New York serif wordmark) | B0.2 |
| 13 | Tags on sessions | B4 (all) |
| 14 | Permission modes actually take effect | ✅-hotfix → surfaced as the composer **Auto/permission chip** B1.4 / B2.2 |
| 15 | Come back on the same model + mode; know the last model | ✅-hotfix (resume) → **last-model shown** in the historical header B3.5 |
| 16 | Type-to-resume (composer on a past session) | B1.5 |
| 17 | Model/permission pickers next to the text box | B1.4 (home), B2.2 (conversation) |
| 18 | Curated "Auto" mode instead of wire names | ✅-hotfix → **Auto chip** B1.4 / B2.2 |
| 19 | The design phase itself | This whole plan builds the sprint's output |
| 21 | "Mac-assed": mode-aware materials, motion, git strip | B0 (tokens/motion), B2.4 (git strip), throughout |
| 22 | Model/effort on the *start* composer | B1.4 |
| 23 | A way back to the home/welcome screen | B1.2 |
| 24 | Replace the useless status badge with words + a list | B1.3 (home inbox), B3.2 (sidebar attention sections) |
| 25 | Step-grouping never collapses in real sessions | B2.1 (root cause: `thinking` between tools — grounded in a real transcript) |
| 26 | Right panel = clickable Activity/task list by default | B2.3 |
| 27 | Composer grows as you type | B2.2 |
| 28 | Git footer strip (branch · ±diff · time · cost) — **Create PR omitted v1** (Ben 2026-07-12) | B2.4 |
| 29 | Mode-aware appearance (follows system light/dark) | B0.2 |
| 30 | Two-level sidebar grouping (Date › Project) | B3.1, B3.3 |
| 31 | Multi-select scoped to tagging; pin/archive per-row | B3.3 (per-row), B3.4 + B4.7 (multi-select Tag…) |
| 32 | Tags scale to creative/PhD workload (characters/scenes/papers) | B4.1, B4.3, B4.4 |
| 20 | `Screenshots for GUI etc/` | ✅ **Decided 2026-07-12: add to `.gitignore`** (make the intentional untrack explicit; 46 MB / 27 PNGs stay out of history) — Task 0 |

Rows 1–5, 8, 9, 10, 12 are already CLOSED/confirmed in the ledger. Nothing OPEN is omitted.

---

## Verification model (read first)

How "done" gets proven in Fabled's reality — there is **no view-level test harness** (the codebase has never unit-tested SwiftUI bodies; DECISIONS 2026-07-09).

- **Machine-verifiable (the implementer/reviewer closes alone):**
  - Logic: `swift test` (single: `swift test --filter <Name>`). Every `FabledCore`/`ClaudeKit` task is TDD'd — failing test first.
  - App compiles: `xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled build` → BUILD SUCCEEDED.
  - Baseline: `swift test` green (301 tests, permission-hotfix ledger). No phase may leave it red.
- **Honesty gates (only Ben can close — a row is `pending-verification` until then, ledger rule 4):** each screen's look and behaviour — the two palettes flipping with system appearance (B0), the inbox legibility (B1), step-groups collapsing on HIS real transcript (B2), the funnel/attention/tags (B3/B4). Describe every gate item in plain English (what he sees/does), never code names (memory `ben-plain-english`).
- **Known deltas to disclose up front (so an expected gap is not read as a bug):**
  1. Some **light-mode** shades (cyan-live, diff green/red, window border, bronze-lt) are ⚠️ provisional — the mockups only render dark; Ben vets them at the B0 gate.
  2. **Create PR is omitted from v1** (Ben 2026-07-12) — the git strip ships read-only (branch · ±diff · cost); no PR button, no `gh`/network affordance this pass. Revisit as its own outward-facing feature.
  3. The **sidebar rows carry no model label** by design (the mockup shows time only); last-model appears on the historical session page instead (row 15) — **Ben confirmed 2026-07-12**.
  4. **Row 25 residual:** the fix collapses across `thinking`; if Ben's real transcript still walls because Claude *narrates* (`.assistantText`) between steps, that is a co-design call, flagged not pre-decided.

## Non-negotiable invariants (override any task step on conflict)

1. **One live process per session id.** Type-to-resume (B1.5) MUST route through `AppModel.resume(_:fork:)` — never spawn a second process on a resumed id (`AppModel.swift:249-262`). ⚠️ LANDMINE: bypassing the guard interleaves two writers on one transcript.
2. ⚠️ **Never write Fabled data into the CLI's `.jsonl` transcripts.** The "custom-title sidecar store" (DECISIONS) does not exist as a writable thing — `customTitle` is *read* from `custom-title` lines the CLI wrote (`TranscriptDecoder.swift:22-24`). Tags get their **own** file (`tags.json`, B4.2). Corrupting a CLI transcript loses Ben's history.
3. ⚠️ **`total_cost_usd` is session-cumulative — assign, never sum** (`ChatSession.swift:421-425`; DECISIONS 2026-07-11). The git-strip cost reads `session.cumulativeCostUSD` as-is.
4. ⚠️ **The row-25 fix hides only resolved-ALLOW permissions.** A denied or pending permission stays a hard break and stays visible (B2.1) — never silently swallow a denial.
5. ⚠️ **`xcodegen generate` after adding ANY new file under `App/`** or the build won't see it. SwiftPM auto-globs `Sources/**`; the xcodeproj does not.
6. ⚠️ **Tokens are law** (LifeSync DN12 parallel): no raw hex in a view — every colour routes through a `Theme` token (Task B0.2). A literal in a view is a review failure.
7. ⚠️ **No `.preferredColorScheme`** anywhere — it defeats mode-aware appearance (row 29). Appearance follows the system only.
8. ⚠️ **Row activation uses `TapGesture`, not `Button`, in transcript/Activity rows** — the documented click-saga (`TimelineItemViews.swift:115-127`): environment churn cancels Button press-dispatch. New `ActivityListView` rows follow the same pattern, hit-target outside padding/background.
9. **`\.inspectItem` is handed across presentation boundaries explicitly** — `.inspector`/`.sheet` content does not inherit `.environment` (`InspectorView.swift:40-46`). The Activity list (B2.3) passes it in, never relies on inheritance.

## Research notes the implementer must know (verified against source, 2026-07-12)

Each is a trap someone would otherwise fall into.

1. **Row 25's real cause is `thinking`, not permissions.** On-disk transcripts contain **no** control/permission lines (verified against `409fdeca…jsonl`) — the pattern is `thinking → thinking → tool → tool_result → …`. `.thinking` items hit the `else` branch of `TimelineDisplay.grouped` and flush the run (`TimelineDisplay.swift:38-45`), so ≥3 consecutive tool calls (`minimumRun`, :22) almost never occur. Fix = make `thinking` (and resolved-allow permission) transparent.
2. **Tool_result user lines don't add rows** — they fill the matching tool call (`TimelineReducer.fillToolResult`, `TimelineReducer.swift:212-219`); so in history the only interstitial between two tool calls is `thinking`.
3. **The spawn defaults are already wired.** `AppModel.newSession` sets `configuration.model/effort/permissionMode` from `preferred*` (`AppModel.swift:223-234`); `resume` restores model+mode from the transcript then falls back to the spawn defaults (`:274-284`). B1 chips just write those three `preferred*` fields.
4. **The picker menus' "New sessions" sections already write the sticky defaults** (`PermissionPickerMenu.swift:62-70`, `EffortPickerMenu.swift:70-79`) — reuse that logic in `ComposerChips` for the `.newSession` target; do not invent a parallel path.
5. **Pre-spawn there is no model catalog.** The home composer's model menu must use `ModelOption.merged(catalog: [])` (hardcoded known list; `ModelPickerMenu.swift:92-97`), not `session.models` (empty until a live init).
6. **`SessionResumeState.derive` already recovers the last model** (`SessionStore.swift:110-113`) — B3.5 reuses it for the historical-header label; no index-schema change.
7. **`SidebarOptions` is persisted JSON in UserDefaults** (`AppModel.swift:58-66`); adding `thenBy`/`archivedSessionIDs` (B3.1) is a Codable change — old stored blobs must still decode (defaulted fields do).
8. **Grouped runs never contain Task/Agent** — anchors are excluded (`TimelineDisplay.swift:20`); the Activity list (B2.3) surfaces subagent Tasks as their own `.agent` rows from `subagentTimelines`.
9. **`ChatSession.draft` is session state, not view state** (`ChatSession.swift:37-40`) — the conversation composer already survives session switches; the home/resume composers are separate `@State`.

## Scope

- **Does (observable done-when):** the four screens match the locked mockups in dark and light; the home inbox reads in plain English with working sticky chips; a past session resumes by typing; step-groups collapse on a real thinking-interleaved transcript; the right panel is a drill-in Activity list; a git strip shows branch/±diff/cost; the sidebar floats attention + groups two-level with per-row pin/archive; tags work end-to-end (chip / filter-AND / picker / rename / delete-asks-first / in-session / batch). Every OPEN UX-LEDGER row reaches its gate.
- **Untouched (load-bearing claim):** the CLI transport + protocol decoding (`AgentSession`, `AgentEventDecoder`), the permission-prompt mechanism, the one-process invariant, the search FTS5 schema, and the on-disk transcript format. This plan adds views + view-models + a `tags.json` sidecar + a read-only `git`/`GitInfo` read; it changes no wire behaviour.
- **Explicitly deferred (nothing vanishes):** The **Create-PR button entirely** → out of v1 by Ben's call 2026-07-12 (git strip ships read-only); revisit as its own feature. Row-25 escalation to narration-grouping → co-design only if the thinking fix is insufficient at Ben's gate. `Screenshots for GUI etc/` → **decided: add to `.gitignore`** (Ben 2026-07-12, row 20) — done in Task 0, not deferred. Chat/Cowork presets → already deferred (DECISIONS 2026-07-11).

---

## Design token reference (the single source of truth for all view tasks)

All values from `docs/superpowers/design/README.md` + the four mockups. **Dark is locked** (every mockup renders dark). **Light** ground/sidebar/panel/ink/muted/faint/hairline/accent/amber/slate are locked; the remaining light values (⚠️ below) are unspecified in the mockups — use the given default and **flag for Ben at the B0 gate** (co-design: not invented-and-hidden).

| Token (`Theme.` / `Palette.`) | Dark | Light | Used for |
|---|---|---|---|
| `ground` | `#0C1618` | `#F5F4EF` | window/thread background |
| `surfaceSide` | `#0A1315` | `#EBEAE3` | title bar, sidebar, composer bar, inspector, footer |
| `panel` | `#122120` | `#FFFFFF` | cards, chips, step-group rows, Home button |
| `panelRecessed` | `#0F1C1D` | `#F6F6F0` | search field, recessed chips, row hover |
| `ink` | `#E9EEEA` | `#23211C` | primary text |
| `muted` | `#8EA29A` | `#6F6B61` | secondary text, previews |
| `faint` | `#5C6F68` | `#A39F93` | tertiary, counts, carets, placeholder |
| `hairline` | `rgba(120,160,150,.15)` | `#E6E4DB` | all internal borders/dividers |
| `windowBorder` | `#1D2E2D` | ⚠️ `#DAD8CE` | 1px window outline |
| `accent` (bronze) | `#CFA669` | `#A9703B` | icons, keys, pins, PR button, send, wordmark |
| `accent2` (bronze-lt) | `#D8AE6D` | ⚠️ `#8A5A2E` | subagent groups, wordmark tint |
| `live` (cyan glow) | `#5AC9B4` | ⚠️ `#2FA28C` | running/live, success checks, Working dot |
| `needsYou` (amber) | `#E0B15C` | `#B2751C` | "Needs you / your reply" attention |
| `review` (slate) | `#7FB0D0` | `#4E6E8C` | "Ready to review" attention |
| `diffAdd` | `#7FD8A2` | ⚠️ `#3B9E63` | `+N`, added diff lines |
| `diffDel` | `#E7A79B` | ⚠️ `#C0503F` | `−N`, removed diff lines |

**Type:** wordmark + panel/section titles = serif (`.system(design: .serif)` = New York on macOS 15); all UI = SF (`-apple-system`, the default); code/paths/branch/diff/cost = `.system(design: .monospaced)` (SF Mono).

**Radii:** window 12 · cards/step-groups/attention rows 10 · home composer 11 · conversation composer box 13 · buttons/chips 7–8 · tag chip & tool-tag badge 5 · pills/filter chips `Capsule()` · popovers 10–11.

**Motion:** `pulse` live dots — `1.4s ease-in-out` repeat, opacity 1↔.3 (inspector) / 1↔.35 + scale 1↔.8 (sidebar Working dot). `blink` text carets — 1.1s step-end, opacity→0 at 50%. Reuse existing `Theme.snap` (0.18) / `Theme.settle` (0.25) for expand/select.

**Selected/active conventions:** bronze ring = `shadow/overlay 1.5px accent, border transparent` (step-group selected, tag-rename editing); inset hairline = `panel bg + inset 1px hairline` (sidebar/session row selected); filled bronze check = checkbox on (`accent` fill, `ground` glyph).

**Responsive:** conversation/sidebar/tags collapse to single column below 720 pt (inspector/right pane hidden). Sidebar width ~300–308 pt; conversation inspector fixed ~310 pt.

---

## File Structure

**New — `FabledCore` / `ClaudeKit` (tested logic):**
- `Sources/FabledCore/Palette.swift` — pure locked color values (dark+light hex), unit-pinned. **One responsibility:** the numbers Ben approved.
- `Sources/FabledCore/ActivityList.swift` — derive the right-panel Activity rows from a timeline + subagent timelines + live state (row 26).
- `Sources/ClaudeKit/TagIndex.swift` — pure tag algebra: registry, per-session tags, counts, AND-filter, rename, delete (Codable).
- `Sources/ClaudeKit/TagStore.swift` — actor persisting `TagIndex` to `Application Support/Fabled/tags.json`.
- `Sources/ClaudeKit/GitInfo.swift` — read branch + `±diff` for a working directory via `git` (row 28).

**Modified — `FabledCore` / `ClaudeKit`:**
- `TimelineDisplay.swift` — grouping tolerates transparent interstitials (row 25).
- `SidebarOrganizer.swift` — two-level `Group by › Then by` + archive filter (rows 6, 30).
- `AppModel.swift` — `preferredModel`, `goHome()`, `resumeAndSend`, tag state + ops, archive, live-attention partition, activity for a live session.
- `SessionStore.swift` / `SessionSummary.swift` — expose last-model for the historical header (row 15).

**New — `App/` (views):**
- `ComposerChips.swift` — the reusable model/effort/Auto chip row (home + conversation).
- `ActivityListView.swift` — the inspector's default Activity list + drill-in.
- `GitFooterStrip.swift` — the conversation footer.
- `FunnelPopover.swift` — sidebar Group/Then/Sort popover.
- `TagChip.swift`, `TagPickerPopover.swift`, `ManageTagsView.swift`, `TagFilterBar.swift` — tag surfaces.

**Modified — `App/`:** `Theme.swift`, `WelcomeView.swift`, `ComposerView.swift`, `ConversationView.swift`, `InspectorView.swift`, `SidebarView.swift`, `HistoricalSessionView.swift`, `StatusBadge.swift`, `RootView.swift`, `FabledApp.swift`.

---

## Task 0 — Branch / worktree (always first)

- [ ] Create an isolated worktree off `master` (superpowers:using-git-worktrees), branch `plan-4c-work-stream-b`. Confirm `swift test` is green (baseline 301) before any change. **Add `Screenshots for GUI etc/` to `.gitignore` and commit** (row 20, Ben 2026-07-12). **Push the branch** — Ben approved 2026-07-12; git identity is already `andiyar@gmail.com` (the stale `Moonlit-Studio.local` claim is obsolete).

---
---

# PHASE B0 — Theme foundation (mode-aware tokens)

**Outcome:** a pure, test-pinned `Palette`, a mode-aware `Theme` token layer consuming it, the New York serif wordmark, and the app shell (window ground + title bar) painted from tokens and following the system light/dark setting. Rows 11, 29, 21 (foundation).

### Task B0.1 — Palette: the locked values, pinned by a test

**Files:**
- Create: `Sources/FabledCore/Palette.swift`
- Test: `Tests/FabledCoreTests/PaletteTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import FabledCore

struct PaletteTests {
    @Test func lockedDarkValuesMatchTheMockups() {
        #expect(Palette.ground.dark == 0x0C1618)
        #expect(Palette.surfaceSide.dark == 0x0A1315)
        #expect(Palette.panel.dark == 0x122120)
        #expect(Palette.ink.dark == 0xE9EEEA)
        #expect(Palette.accent.dark == 0xCFA669)
        #expect(Palette.live.dark == 0x5AC9B4)
        #expect(Palette.needsYou.dark == 0xE0B15C)
    }
    @Test func lockedLightValuesMatchTheReadme() {
        #expect(Palette.ground.light == 0xF5F4EF)
        #expect(Palette.surfaceSide.light == 0xEBEAE3)
        #expect(Palette.panel.light == 0xFFFFFF)
        #expect(Palette.ink.light == 0x23211C)
        #expect(Palette.accent.light == 0xA9703B)
        #expect(Palette.review.light == 0x4E6E8C)
    }
    @Test func hairlineCarriesItsDarkAlpha() {
        #expect(Palette.hairline.darkAlpha == 0.15)
    }
}
```

- [ ] **Step 2: Run it — expect failure**

Run: `swift test --filter PaletteTests`
Expected: FAIL — `cannot find 'Palette' in scope`.

- [ ] **Step 3: Implement `Palette`**

```swift
import Foundation

/// The Ben-locked Fabled colors (co-design sprint 2026-07-12), as raw hex so the
/// values can be pinned by a unit test — a typo in a value Ben approved is a test
/// failure, not a silent drift. `App/Theme.swift` maps these to mode-aware SwiftUI
/// Colors. Dark is fully locked (every mockup renders dark); some light values are
/// provisional (README locks the core; the rest are flagged for Ben at the B0 gate).
public enum Palette {
    public struct Tone: Sendable {
        public let dark: UInt32
        public let light: UInt32
        public let darkAlpha: Double
        public let lightAlpha: Double
        public init(dark: UInt32, light: UInt32, darkAlpha: Double = 1, lightAlpha: Double = 1) {
            self.dark = dark; self.light = light
            self.darkAlpha = darkAlpha; self.lightAlpha = lightAlpha
        }
    }
    // Locked (README + mockups)
    public static let ground        = Tone(dark: 0x0C1618, light: 0xF5F4EF)
    public static let surfaceSide   = Tone(dark: 0x0A1315, light: 0xEBEAE3)
    public static let panel         = Tone(dark: 0x122120, light: 0xFFFFFF)
    public static let panelRecessed = Tone(dark: 0x0F1C1D, light: 0xF6F6F0)
    public static let ink           = Tone(dark: 0xE9EEEA, light: 0x23211C)
    public static let muted         = Tone(dark: 0x8EA29A, light: 0x6F6B61)
    public static let faint         = Tone(dark: 0x5C6F68, light: 0xA39F93)
    public static let hairline      = Tone(dark: 0x78A096, light: 0xE6E4DB, darkAlpha: 0.15)
    public static let accent        = Tone(dark: 0xCFA669, light: 0xA9703B)
    public static let needsYou      = Tone(dark: 0xE0B15C, light: 0xB2751C)
    public static let review        = Tone(dark: 0x7FB0D0, light: 0x4E6E8C)
    // Provisional light (⚠️ verify with Ben at the B0 gate)
    public static let windowBorder  = Tone(dark: 0x1D2E2D, light: 0xDAD8CE)
    public static let accent2       = Tone(dark: 0xD8AE6D, light: 0x8A5A2E)
    public static let live          = Tone(dark: 0x5AC9B4, light: 0x2FA28C)
    public static let diffAdd       = Tone(dark: 0x7FD8A2, light: 0x3B9E63)
    public static let diffDel       = Tone(dark: 0xE7A79B, light: 0xC0503F)
}
```

- [ ] **Step 4: Run — expect pass**

Run: `swift test --filter PaletteTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/FabledCore/Palette.swift Tests/FabledCoreTests/PaletteTests.swift
git commit -m "feat(theme): pin the Ben-locked Fabled palette values (B0.1)"
```

### Task B0.2 — Theme: mode-aware tokens + serif wordmark, consuming Palette

**Files:**
- Modify: `App/Theme.swift`

- [ ] **Step 1: Add a Palette→Color bridge and the semantic tokens.** Replace the ad-hoc color block; keep `clay` (send button, DECISIONS 2026-07-08) and the layout/motion sections. Add:

```swift
import SwiftUI
import AppKit
import FabledCore

extension Theme {
    private static func ns(_ hex: UInt32, alpha: Double) -> NSColor {
        NSColor(srgbRed: Double((hex >> 16) & 0xFF) / 255,
                green: Double((hex >> 8) & 0xFF) / 255,
                blue: Double(hex & 0xFF) / 255, alpha: alpha)
    }
    static func token(_ tone: Palette.Tone) -> Color {
        dynamic(light: ns(tone.light, alpha: tone.lightAlpha),
                dark: ns(tone.dark, alpha: tone.darkAlpha))
    }
    // Surfaces
    static let ground = token(Palette.ground)
    static let surfaceSide = token(Palette.surfaceSide)
    static let panel = token(Palette.panel)
    static let panelRecessed = token(Palette.panelRecessed)
    static let hairline = token(Palette.hairline)
    static let windowBorder = token(Palette.windowBorder)
    // Text
    static let ink = token(Palette.ink)
    static let muted = token(Palette.muted)
    static let faint = token(Palette.faint)
    // Accent + status
    static let accentBronze = token(Palette.accent)
    static let accent2 = token(Palette.accent2)
    static let live = token(Palette.live)
    static let needsYou = token(Palette.needsYou)
    static let review = token(Palette.review)
    static let diffAddColor = token(Palette.diffAdd)
    static let diffDelColor = token(Palette.diffDel)
}
```

- [ ] **Step 2: Retune the existing brand + status tokens to the locked palette** (existing views reference these — retuning is the mode-aware repaint). In `Theme`:
  - `bronze` → `accentBronze` (or repoint `static let bronze = accentBronze`). Keep the name `bronze` as an alias so existing references compile.
  - `welcomeBackdrop` → `ground`.
  - `statusNeedsInput` → `needsYou`; `statusWorking` → `live`; `statusReady` → `review`; keep `statusEnded`.
  - `glow` → `live`.
  - Keep `clay` unchanged (send button only).

- [ ] **Step 3: Wordmark font.** Confirm `Theme.display` uses `.system(.largeTitle, design: .serif).weight(.semibold)` (New York on macOS 15) — already correct. Add `static let wordmarkColor = token(Palette.accent)` and a small `static let wordmark = Font.system(size: 22, design: .serif).weight(.semibold)` matching the mockup's 22 pt.

- [ ] **Step 4: Paint the app shell.** In `RootView.swift`, wrap the `NavigationSplitView` content background with `.background(Theme.ground)` and set the window to follow system appearance (no manual toggle — SwiftUI honors it by default; verify no `.preferredColorScheme` override exists). No functional change beyond color.

- [ ] **Step 5: Build.**

Run: `xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled build`
Expected: BUILD SUCCEEDED. Manually confirm (screenshot) the window ground + wordmark read as Teal Midnight in dark and Linen in light (toggle System Settings → Appearance).

- [ ] **Step 6: Commit**

```bash
git add App/Theme.swift App/RootView.swift
git commit -m "feat(theme): mode-aware tokens + serif wordmark from locked palette (B0.2)"
```

**B0 gate checkpoint (Ben):** show the empty shell in light and dark. Plain-English ask: *"Does this read as the two looks you picked — the dark teal and the warm Linen — and does it flip when you change your Mac's appearance?"* Vet the ⚠️ provisional light values (accent2, live-cyan, diff colors, window border).

---
---

# PHASE B1 — Home + composer (the front door)

**Outcome:** launching or pressing the Home button lands on the attention inbox ("Waiting on you" with plain word-labels + a preview of what each session wants, then "Lately"); the composer is the front door with model/effort/Auto chips that drive the next spawn; a past session shows a composer and typing resumes it. Rows 7, 16, 17, 18, 22, 23, 24.

### Task B1.1 — `AppModel.preferredModel` (sticky start-composer model)

**Files:**
- Modify: `Sources/FabledCore/AppModel.swift`
- Test: `Tests/FabledCoreTests/AppModelTests.swift`

- [ ] **Step 1: Write the failing test** (mirror the existing `preferredEffort`/`preferredPermissionMode` persistence tests in the file):

```swift
@Test @MainActor func preferredModelPersistsAndSpawns() async throws {
    let defaults = UserDefaults(suiteName: "b1.1.\(UUID())")!
    let model = try AppModel(defaults: defaults)
    model.preferredModel = "claude-opus-4-8"
    var captured: SessionConfiguration?
    model.launcher = { config in captured = config; return try makeTestSession(config) }
    await model.newSession(at: URL(fileURLWithPath: "/tmp"))
    #expect(captured?.model == "claude-opus-4-8")
    // persistence
    let reloaded = try AppModel(defaults: defaults)
    #expect(reloaded.preferredModel == "claude-opus-4-8")
}
```
(Reuse the file's existing `launcher` test seam + `makeTestSession` helper in `Support.swift`; if none exists for a config→session stub, add a minimal one returning a `ChatSession` built from an in-memory `AgentConnection` stub as the other AppModel tests do.)

- [ ] **Step 2: Run — expect failure** (`value of type 'AppModel' has no member 'preferredModel'`).
Run: `swift test --filter preferredModelPersistsAndSpawns`

- [ ] **Step 3: Implement.** In `AppModel`, add next to `preferredPermissionMode`:

```swift
public var preferredModel: String? {
    didSet { defaults.set(preferredModel, forKey: Self.preferredModelKey) }
}
private static let preferredModelKey = "preferredModel"
```
Load it in `init` (`self.preferredModel = defaults.string(forKey: Self.preferredModelKey)`). In `newSession(at:model:firstMessage:)`, default the model param to `preferredModel`: change the signature call site so a nil `model` falls back to `preferredModel` — set `configuration.model = model ?? preferredModel`.

- [ ] **Step 4: Run — expect pass.** `swift test --filter preferredModelPersistsAndSpawns`

- [ ] **Step 5: Commit**
```bash
git add Sources/FabledCore/AppModel.swift Tests/FabledCoreTests/AppModelTests.swift
git commit -m "feat(home): sticky preferredModel for the start composer (B1.1)"
```

### Task B1.2 — Home affordance: return to the inbox (row 23)

**Files:**
- Modify: `Sources/FabledCore/AppModel.swift`, `App/FabledApp.swift`, `App/RootView.swift`, `App/ConversationView.swift`, `App/HistoricalSessionView.swift`
- Test: `Tests/FabledCoreTests/AppModelTests.swift`

- [ ] **Step 1: Write the failing test:**

```swift
@Test @MainActor func goHomeReturnsToTheInbox() async throws {
    let model = try AppModel(defaults: UserDefaults(suiteName: "b1.2.\(UUID())")!)
    model.selection = .historical("abc")
    model.goHome()
    #expect(model.selection == nil)
    #expect(model.isPickingFolder == false)   // Home is the inbox, NOT the folder picker
}
```

- [ ] **Step 2: Run — expect failure** (`no member 'goHome'`). `swift test --filter goHomeReturnsToTheInbox`

- [ ] **Step 3: Implement.** Add to `AppModel`:
```swift
/// Return to the attention inbox (welcome). ⌘N and the toolbar Home button call
/// this — the inbox is the front door, not the folder picker (UX-LEDGER row 23).
public func goHome() { selection = nil; isPickingFolder = false }
```

- [ ] **Step 4: Run — expect pass.**

- [ ] **Step 5: Rewire ⌘N to Home, not the folder picker.** In `FabledApp.swift` replace the `New Session…` command body `model.isPickingFolder = true` with `model.goHome()` and rename to `Home` semantics:
```swift
CommandGroup(replacing: .newItem) {
    Button("Home") { model.goHome() }
        .keyboardShortcut("n", modifiers: .command)
}
```
(Folder choice now lives on the composer's project chip — B1.4 — so ⌘N no longer needs the picker.)

- [ ] **Step 6: Add a persistent toolbar Home button.** Add to the `.toolbar` in both `ConversationView.swift` and `HistoricalSessionView.swift` (leading, before the model chips) — matches the mockup's `.tb-home` (§2.2):
```swift
Button { app.goHome() } label: { Label("Home", systemImage: "house") }
    .help("Back to the home inbox")
```
`ConversationView` needs `@Environment(AppModel.self) private var app` added (it currently only takes `session`).

- [ ] **Step 7: Build + commit.**
```bash
xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled build
git add -A && git commit -m "feat(home): persistent Home affordance returns to the inbox; ⌘N=Home (B1.2)"
```

### Task B1.3 — Rebuild the home inbox: "Waiting on you" + "Lately" (rows 7, 24)

**Files:**
- Modify: `App/WelcomeView.swift`, `App/StatusBadge.swift`

- [ ] **Step 1: Word-labels (plain English).** In `StatusBadge.swift`, change `word` for the inbox to Ben's mandated phrasing (memory `ben-plain-english`): map `.needsApproval → "Needs your reply"`, `.idle → "Ready to review"`, `.working → "Working"`, `.ended → "Ended"`. Repoint colors to the new tokens (`needsYou`, `review`, `live`, `faint`).

- [ ] **Step 2: Rebuild `WelcomeView` body** to the mockup (§1). Structure (exact tokens from the reference table):
  - Background `Theme.ground`.
  - Greeting `Text("Welcome back, Ben")` — `.font(.system(size: 11.5))`, `Theme.muted`.
  - Wordmark `Text("Fabled")` — `Theme.wordmark`, `Theme.wordmarkColor`.
  - **"Waiting on you"** section — the union of `needsInput` (reply) + idle-with-history live sessions (review), each rendered as an **attention card** (`WelcomeAttentionRow`): rounded 10, `Theme.panel` fill, 1px `Theme.hairline`, padding 10×12; left = the labeled `SessionStatusBadge`; right column = title (13, semibold, `Theme.ink`) over preview line (12, `Theme.muted`) where preview = `session.pendingGate?.summaryLine ?? (session.isWorking ? "Working…" : "Ready")`. Only render the section when non-empty (silence = nothing waiting — row 24).
  - **"Working"** section — `working` sessions with a pulsing `Theme.live` dot (reuse the pulse from §motion).
  - **"Lately"** — `app.welcomeRecents(limit: 8)` as quiet `.prow`-style rows (title + `Theme.muted` project + relative time). Rename the current "Recent" heading to **"Lately"** (DECISIONS wording).
  - **Composer** pinned last (built in B1.4).
  - Section headings use `Theme.heading` (serif).

- [ ] **Step 3: Build.** `xcodegen generate && xcodebuild … build` → BUILD SUCCEEDED. Screenshot: confirm a needs-reply session shows "Needs your reply" + its question preview; an idle one shows "Ready to review"; empty state shows only "Lately".

- [ ] **Step 4: Commit.** `git add -A && git commit -m "feat(home): legible 'Waiting on you' + 'Lately' inbox in plain English (B1.3)"`

### Task B1.4 — Composer chips: model / effort / Auto (rows 17, 18, 22)

**Files:**
- Create: `App/ComposerChips.swift`
- Modify: `App/WelcomeView.swift`

- [ ] **Step 1: Build the reusable chip row.** `ComposerChips` renders three menu-backed chips styled per §1.2/§2.5 (`Theme.panelRecessed` fill, 1px `Theme.hairline`, radius 7–8, model chip text in `Theme.accentBronze`, others `Theme.ink`, trailing caret). Two modes via an enum so it serves both the home composer (no live session — sets the **persisted spawn defaults**) and the conversation composer (B2.2 — a live session):

```swift
struct ComposerChips: View {
    enum Target { case newSession; case live(ChatSession) }
    let target: Target
    @Environment(AppModel.self) private var app
    // model chip: newSession → app.preferredModel over ModelOption.merged(catalog: []) known list;
    //             live → session.setModel over session.models (reuse ModelPickerMenu logic)
    // effort chip: newSession → app.preferredEffort; live → session.setEffort
    // permission/Auto chip: newSession → app.preferredPermissionMode over PermissionPickerMenu.modes;
    //                       live → session.setPermissionMode
}
```
For the home (`.newSession`) model menu, use `ModelOption.merged(catalog: [])` (the hardcoded known-models list — no live catalog exists pre-spawn) and show `app.preferredModel`'s display name or "Default". Effort menu = `EffortPickerMenu.fallbackLevels` + a "CLI default". Permission menu = `PermissionPickerMenu.modes` (includes "Auto") + "CLI default". These write `app.preferredModel/preferredEffort/preferredPermissionMode` — the sticky spawn defaults the hotfix already threads into `newSession`.

- [ ] **Step 2: Wire into the home composer.** In `WelcomeView`'s composer, add `ComposerChips(target: .newSession)` in a chip row beneath the `TextField`, before/around the send button, matching §1.2. The project chip stays (folder choice); `startSession` already exists.

- [ ] **Step 3: Build + verify.** BUILD SUCCEEDED. Screenshot: chips show under the home text box; picking Opus/High/Auto persists (relaunch keeps them) and the next new session spawns with them (confirm via the conversation toolbar showing the chosen model/mode).

- [ ] **Step 4: Commit.** `git add -A && git commit -m "feat(home): model/effort/Auto chips on the start composer (B1.4)"`

### Task B1.5 — Type-to-resume: composer on a past session (row 16)

**Files:**
- Modify: `Sources/FabledCore/AppModel.swift`, `App/HistoricalSessionView.swift`
- Test: `Tests/FabledCoreTests/AppModelTests.swift`

- [ ] **Step 1: Write the failing test** — resuming from a summary and immediately sending should reattach (same id) then deliver the message:

```swift
@Test @MainActor func resumeAndSendReattachesThenDelivers() async throws {
    let model = try AppModel(defaults: UserDefaults(suiteName: "b1.5.\(UUID())")!)
    var captured: SessionConfiguration?
    model.launcher = { config in captured = config; return try makeTestSession(config) }
    let summary = makeHistoricalSummary(id: "sess-1")   // Support.swift helper
    await model.resumeAndSend(summary, text: "keep going")
    #expect(captured?.resumeSessionID == "sess-1")
    #expect(captured?.forkSession == false)
    if case .live(let id)? = model.selection,
       let live = model.liveSessions.first(where: { $0.id == id }) {
        #expect(live.timeline.contains { if case .userMessage(_, let t) = $0 { return t == "keep going" } else { return false } })
    } else { Issue.record("expected a live selection") }
}
```

- [ ] **Step 2: Run — expect failure** (`no member 'resumeAndSend'`).

- [ ] **Step 3: Implement.** Add to `AppModel`:
```swift
/// Type-to-resume (UX-LEDGER row 16): the composer on a past session resumes it
/// (Continue = same id, one-process invariant) and delivers the first message.
public func resumeAndSend(_ summary: SessionSummary, text: String) async {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    await resume(summary, fork: false)
    if case .live(let id) = selection,
       let session = liveSessions.first(where: { $0.id == id }) {
        session.send(trimmed)
    }
}
```
(`resume(_:fork:)` already enforces the one-process guard and seeds from disk.)

- [ ] **Step 4: Run — expect pass.**

- [ ] **Step 5: Add the composer to `HistoricalSessionView`.** Below the transcript `VStack`, add a `Divider().overlay(Theme.hairline)` and a resume composer: a `TextField` (axis `.vertical`, `lineLimit(1...8)`) + `ComposerChips(target: .newSession)` (the resume will restore sticky model/mode; the chips set the spawn defaults) + a send button that calls `Task { await app.resumeAndSend(summary, text: draft); draft = "" }`. Keep the existing Continue/Fork toolbar buttons as the explicit path (ledger row 16: composer-first is the friction fix, explicit actions stay "also available").

- [ ] **Step 6: Build + commit.**
```bash
xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled build
git add -A && git commit -m "feat(home): type-to-resume — composer on a past session resumes and sends (B1.5)"
```

**B1 gate checkpoint (Ben):** launch → the inbox; open a session → Home button returns to it; the start composer has working model/effort/Auto chips; typing on a past session and hitting send picks it back up. Plain-English asks per memory `ben-plain-english`.

---
---

# PHASE B2 — Conversation view

**Outcome:** step-groups actually collapse in real (thinking-interleaved) sessions and expand inline; composer-adjacent chips; composer grows as you type; the right panel defaults to a clickable Activity list that drills in/out with Back; a git footer strip. Rows 17, 25, 26, 27, 28.

### Task B2.1 — Step-grouping survives interleaving (row 25 — THE root-cause fix)

**Root cause (grounded in a real transcript, `409fdeca…jsonl`):** on-disk transcripts contain **no permission lines** — permissions are live-only. What breaks every run is that Claude emits `thinking` between nearly every tool call (`thinking → thinking → tool → tool_result → thinking → tool …`), and `.thinking` items flush the run, so ≥3 *consecutive* tool calls almost never occur. Fix: make **transparent interstitials** (`.thinking`, and — for live sessions — a *resolved-allow* `.permission`) not break a run; absorb them into the group (visible on expand, ignored by the summary/count); a resolved-**deny** permission and any `.assistantText`/`.userMessage`/`.turnSummary` stay hard breaks.

**Files:**
- Modify: `Sources/FabledCore/TimelineDisplay.swift`
- Modify: `App/TimelineItemViews.swift` (group badge counts tool calls, not items)
- Test: `Tests/FabledCoreTests/TimelineDisplayTests.swift`

- [ ] **Step 1: Write the failing tests:**

```swift
import Testing
import ClaudeKit
@testable import FabledCore

struct TimelineDisplayGroupingTests {
    private func tool(_ id: String, _ name: String) -> TimelineItem {
        .toolCall(id: id, name: name, summary: name, input: .null,
                  result: .string("ok"), isError: false, isRunning: false)
    }
    private func thinking(_ id: String) -> TimelineItem { .thinking(id: id, text: "…", isStreaming: false) }

    @Test func thinkingBetweenToolsDoesNotBreakTheRun() {
        let items = [thinking("t1"), tool("a","Read"), thinking("t2"),
                     tool("b","Read"), thinking("t3"), tool("c","Read")]
        let rows = TimelineDisplay.grouped(items)
        // One group of three Reads; interior thinking absorbed.
        #expect(rows.count == 1)
        guard case .toolGroup(_, let grouped, let summary) = rows[0] else {
            Issue.record("expected a group"); return
        }
        #expect(summary == "Read 3 files" || summary == "3 × Read")
        #expect(grouped.filter { $0.toolCallID != nil }.count == 3)
    }

    @Test func trailingThinkingStaysOutsideTheGroup() {
        let items = [tool("a","Bash"), tool("b","Bash"), tool("c","Bash"), thinking("t")]
        let rows = TimelineDisplay.grouped(items)
        #expect(rows.count == 2)                     // group, then thinking
        if case .item(let last) = rows[1] { #expect(last.id == "t") } else { Issue.record("thinking should be a loose item") }
    }

    @Test func assistantTextStillBreaksTheRun() {
        let items = [tool("a","Read"), .assistantText(id: "x", markdown: "Now…", isStreaming: false),
                     tool("b","Read"), tool("c","Read")]
        let rows = TimelineDisplay.grouped(items)
        // text is a hard break: [Read] [text] [group? only 2 → loose] → no group
        #expect(!rows.contains { if case .toolGroup = $0 { return true } else { return false } })
    }

    @Test func resolvedAllowPermissionIsTransparentButDenyBreaks() {
        // build via helper reqs; allow-gated run of 3 collapses, a deny splits
        // (see PermissionRequest fixtures). Asserts one group for the allow case,
        // and the deny permission renders as a loose item splitting the run.
    }
}
```
(Flesh out the fourth test using the existing `PermissionRequest`/`PermissionDecision` fixtures in `ClaudeKitTests`/`FabledCoreTests` — construct `.permission(id:request:resolution:)` with `.allow` vs `.deny`.)

- [ ] **Step 2: Run — expect failure** (the first test currently yields 5 rows: thinking/group-of-nothing/… because thinking breaks). `swift test --filter TimelineDisplayGroupingTests`

- [ ] **Step 3: Implement the transparent-interstitial algorithm** in `TimelineDisplay.grouped`:

```swift
public static func grouped(_ items: [TimelineItem]) -> [TimelineRow] {
    var rows: [TimelineRow] = []
    var run: [TimelineItem] = []        // groupable tool calls + absorbed interstitials, in order
    var toolCount = 0                   // groupable tool calls in `run`
    var pending: [TimelineItem] = []    // transparent items seen since the last tool call (trailing)

    func flush() {
        if toolCount >= minimumRun, let first = run.first(where: { $0.toolCallID != nil }) {
            rows.append(.toolGroup(id: first.id, items: run, summary: summary(for: run)))
        } else {
            rows += run.map(TimelineRow.item)
        }
        rows += pending.map(TimelineRow.item)   // trailing transparents render normally
        run = []; toolCount = 0; pending = []
    }

    for item in items {
        if isGroupable(item) {
            run += pending; pending = []       // interior transparents join the run
            run.append(item); toolCount += 1
        } else if isTransparent(item) {
            if run.isEmpty { rows.append(.item(item)) }   // outside any run → normal
            else { pending.append(item) }                  // hold; absorb only if more tools follow
        } else {
            flush(); rows.append(.item(item))
        }
    }
    flush()
    return rows
}

private static func isGroupable(_ item: TimelineItem) -> Bool {
    if case .toolCall(_, let name, _, _, _, let isError, let isRunning) = item {
        return !isRunning && isError != true && !anchors.contains(name)
    }
    return false
}

private static func isTransparent(_ item: TimelineItem) -> Bool {
    switch item {
    case .thinking: return true
    case .permission(_, _, .some(.allow)): return true   // resolved-allow is noise once decided
    default: return false                                 // deny/nil permission, text, user, summary = hard break
    }
}
```
`summary(for:)` already `compactMap`s tool calls only, so absorbed thinking is naturally ignored. (`.permission`'s associated `resolution` is a `PermissionDecision?`; match `.some(.allow)`.)

- [ ] **Step 4: Fix the collapsed count in the view.** In `ToolGroupRow` (`App/TimelineItemViews.swift`), the badge `Text("\(items.count)")` must count tool calls, not absorbed thinking: change to `Text("\(items.filter { $0.toolCallID != nil }.count)")`. (Expanded body still `ForEach(items)` so thinking shows in order on expand — reasoning is preserved, just collapsed by default.)

- [ ] **Step 5: Run — expect pass.** `swift test --filter TimelineDisplayGroupingTests` then full `swift test` (guard no regression in existing `TimelineDisplayTests`/replay tests; if an existing test asserted the old "thinking breaks" behavior, update it to the new contract and note it).

- [ ] **Step 6: Build + commit.**
```bash
xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled build
git add Sources/FabledCore/TimelineDisplay.swift App/TimelineItemViews.swift Tests/FabledCoreTests/TimelineDisplayTests.swift
git commit -m "fix(conversation): step-groups collapse across thinking/allow-gate interleaving (row 25, B2.1)"
```

> **Investigation checkpoint (bring to Ben, do not silently widen):** this fixes the confirmed breaker (thinking). If Ben's actual 22-step session still shows a wall after this, the residual breaker is `.assistantText` between tools (Claude narrating each step). That is a *product* call — collapse across narration, or group-by-turn — and must be co-designed, not guessed. Capture his transcript as a fixture and decide together.

### Task B2.2 — Conversation composer: chips + grows-as-you-type (rows 17, 27)

**Files:**
- Modify: `App/ComposerView.swift`, `App/ConversationView.swift`

- [ ] **Step 1: Add chips to the live composer.** In `ComposerView`, add `ComposerChips(target: .live(session))` in a chip row under the `TextField` (§2.5), matching the mockup's "Opus 4.8 ▾ · Effort: High ▾ · Auto ▾". This is the designed home for the model/effort/permission controls — **remove `ModelPickerMenu`/`EffortPickerMenu`/`PermissionPickerMenu` from the `ConversationView` toolbar** (they move to chips; the active-model text + cost stay in the toolbar). Keeps rows 14/18 controls where Ben asked (next to the text box).

- [ ] **Step 2: Grows-as-you-type.** The `TextField` already uses `axis: .vertical` + `lineLimit(1...8)` — confirm it grows to ~8 lines then scrolls internally and never runs horizontally (the mockup's explicit rule §2.5). Add `.lineLimit(1...8)` if not already the effective cap and verify wrapping (no `.fixedSize(horizontal:)`).

- [ ] **Step 3: Repaint the composer bar** to `Theme.surfaceSide` with the composer box `Theme.panel`, 1px `Theme.hairline`, radius 13 (§2.5). Send button stays `Theme.clay` (existing).

- [ ] **Step 4: Build + verify.** Screenshot: chips under the text box drive the live session (change model → toolbar model text updates); typing many lines grows the box to ~8 then scrolls.

- [ ] **Step 5: Commit.** `git add -A && git commit -m "feat(conversation): composer chips + grow-as-you-type (rows 17/27, B2.2)"`

### Task B2.3 — Right panel defaults to a clickable Activity list (row 26)

**Files:**
- Create: `Sources/FabledCore/ActivityList.swift`, `App/ActivityListView.swift`
- Modify: `App/InspectorView.swift`, `App/ConversationView.swift`, `App/HistoricalSessionView.swift`
- Test: `Tests/FabledCoreTests/ActivityListTests.swift`

- [ ] **Step 1: Write the failing test** for the pure derivation — the Activity list = one row per meaningful unit (running tool = live; each subagent Task = agent group; finished tool-runs summarized; edits carry `+N −N`), newest-relevant first, live rows first:

```swift
import Testing
import ClaudeKit
@testable import FabledCore

struct ActivityListTests {
    @Test func liveToolBecomesALivePulsingRow() {
        let timeline: [TimelineItem] = [
            .toolCall(id: "1", name: "Bash", summary: "swift build", input: .null,
                      result: nil, isError: nil, isRunning: true)]
        let rows = ActivityList.rows(timeline: timeline, subagents: [:])
        #expect(rows.first?.isLive == true)
        #expect(rows.first?.title == "swift build" || rows.first?.title == "Bash")
    }
    @Test func subagentTaskBecomesAnAgentRowWithStepCount() {
        let timeline: [TimelineItem] = [
            .toolCall(id: "T", name: "Task", summary: "Explore", input: .null,
                      result: .string("done"), isError: false, isRunning: false)]
        let subs = ["T": [TimelineItem.assistantText(id: "s", markdown: "hi", isStreaming: false)]]
        let rows = ActivityList.rows(timeline: timeline, subagents: subs)
        #expect(rows.contains { $0.kind == .agent && $0.drillID == "T" })
    }
    @Test func liveRowsSortAboveFinished() { /* one running + one finished → running first */ }
}
```

- [ ] **Step 2: Run — expect failure.** `swift test --filter ActivityListTests`

- [ ] **Step 3: Implement `ActivityList`** — a pure enum with:
```swift
public struct ActivityRow: Identifiable, Equatable, Sendable {
    public enum Kind: Sendable { case command, edit, read, agent, live, other }
    public let id: String            // == drillID (the timeline item id)
    public let drillID: String       // inspect target
    public let kind: Kind
    public let title: String
    public let subtitle: String      // "done" / "+12 −13 · done" / "3 agents · running"
    public let isLive: Bool
}
public enum ActivityList {
    public static func rows(timeline: [TimelineItem],
                            subagents: [String: [TimelineItem]]) -> [ActivityRow] { … }
}
```
Rules: running tool calls → `.live` rows (isLive, subtitle "running"); `Task`/`Agent` anchors with a `subagents[id]` slice → `.agent` rows (subtitle "\(steps) steps"); finished tool runs grouped like `TimelineDisplay` → one row per run (kind by tool family: Bash→command, Edit/Write→edit with `DiffCount` if resolvable, Read→read); title/subtitle from the same summaries. Live rows first, else preserve timeline order reversed (newest first). Reuse `TimelineDisplay.summary` where possible (extract a shared helper if needed).

- [ ] **Step 4: Run — expect pass.**

- [ ] **Step 5: Build `ActivityListView`** (§2.6/§2.7): a header ("Activity" serif 14 + count + "Clear"); a `List`/`VStack` of activity rows (`Theme.panel` card, 1px `Theme.hairline`, radius 9; leading icon bronze, `.agent`→`accent2`, `.live`→`live` with a pulsing dot; title 12.5 semibold `Theme.ink`, subtitle 11 `Theme.muted`; trailing chevron for drillable rows). Clicking a row calls the existing `inspectItem(row.drillID)` → the panel switches to the item **detail** (the current `InspectorPanel.content`), with the existing **Back** button returning to… the Activity list. Implement Back-to-list by: when `inspectedID == nil` the inspector shows `ActivityListView`; when non-nil it shows the detail with `onBack` popping to nil (list). (The trail stack still handles sub→sub drilling.)

- [ ] **Step 6: Make the inspector default to the list.** In `InspectorView.InspectorPanel`, replace the `else { ContentUnavailableView(...) }` (shown when `item == nil`) with the `ActivityListView`. Feed it the session's `timeline`+`subagentTimelines` (live) or the historical `items`+`subagentTimelines`. In `ConversationView`/`HistoricalSessionView`, **default `isInspectorPresented` context so the panel is meaningful on open** (the Activity list is now always useful, so opening the inspector shows the list, not "Nothing selected"). Row 26.

- [ ] **Step 7: Build + verify.** Screenshot: inspector opens to a list of activity summaries; a live build shows a pulsing cyan row; clicking a finished row shows its detail with Back → returns to the list.

- [ ] **Step 8: Commit.**
```bash
xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled build
git add -A && git commit -m "feat(conversation): right panel defaults to a clickable Activity list, drill-in/Back (row 26, B2.3)"
```

### Task B2.4 — Git footer strip (row 28)

**Files:**
- Create: `Sources/ClaudeKit/GitInfo.swift`, `App/GitFooterStrip.swift`
- Modify: `App/ConversationView.swift`
- Test: `Tests/ClaudeKitTests/GitInfoTests.swift`

- [ ] **Step 1: Write the failing test** against a real temp git repo:

```swift
import Testing
import Foundation
@testable import ClaudeKit

struct GitInfoTests {
    @Test func readsBranchAndDiffFromARepo() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        func git(_ args: String...) throws { /* run `git` in dir via Process, throw on failure */ }
        try git("init", "-q"); try git("config", "user.email", "t@t"); try git("config", "user.name", "t")
        try "hello\n".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try git("add", "."); try git("commit", "-qm", "init")
        try "hello\nworld\n".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let info = try await GitInfo.read(at: dir)
        #expect(info?.branch == "main" || info?.branch == "master")
        #expect((info?.added ?? 0) >= 1)
    }
    @Test func nonRepoReturnsNil() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(try await GitInfo.read(at: dir) == nil)
    }
}
```

- [ ] **Step 2: Run — expect failure** (`no type 'GitInfo'`).

- [ ] **Step 3: Implement `GitInfo`** — a `Sendable struct { branch: String; added: Int; removed: Int }` and `static func read(at: URL) async throws -> GitInfo?`. Run `git rev-parse --abbrev-ref HEAD` and `git diff --numstat` (sum columns) via `Process` (app is un-sandboxed — DECISIONS dev-build note). Return nil when not a repo (non-zero exit / no `.git`). Keep it best-effort and off the main actor.

- [ ] **Step 4: Run — expect pass.**

- [ ] **Step 5: Build `GitFooterStrip`** (§2.8): a strip on `Theme.surfaceSide`, 1px top `Theme.hairline`, 12 `Theme.muted`, `·`-separated segments: branch (mono, `Theme.ink`) · `+added −removed` (`Theme.diffAddColor`/`Theme.diffDelColor`, mono) · session time (from turn summaries if available, else omit) · cost (mono, from `session.cumulativeCostUSD`, existing). **(No Create-PR button — omitted v1 per Ben 2026-07-12; the strip is read-only.)** Poll `GitInfo.read(at: session.workingDirectory)` on appear + on turn completion (cheap; debounce). Hide the strip entirely when `GitInfo` is nil (non-repo session).

- [ ] **Step 6: (Create PR omitted for v1 — Ben's call 2026-07-12.)** The git strip ships **read-only** this pass: branch · ±diff · cost, with **no** PR / `gh` / network affordance at all. Recorded in DECISIONS 2026-07-12 and UX-LEDGER row 28 (partial defer, Ben-signed). If Ben later wants it, it returns as its own outward-facing task (confirm-gated, never a silent push). Nothing to build here — this step is the explicit "we consciously left it out" marker so it isn't read as forgotten.

- [ ] **Step 7: Wire into `ConversationView`.** Add `GitFooterStrip(session: session)` at the very bottom (below the composer), spanning the width (§2.1 footer spans both columns).

- [ ] **Step 8: Build + commit.**
```bash
xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled build
git add -A && git commit -m "feat(conversation): quiet read-only git footer strip — branch · ±diff · cost (row 28, B2.4)"
```

**B2 gate checkpoint (Ben):** open his real multi-step session — does it collapse into "Read N files"/"Ran N commands" summaries now, and expand? Chips by the text box; box grows; right panel is the Activity list (drill in, Back out); git strip along the bottom. **Verify row 25 against his actual 22-step transcript** (the investigation checkpoint).

---
---

# PHASE B3 — Sidebar

**Outcome:** attention floats above grouping as sections (not a lone badge); two-level Date › Project grouping via a funnel (Group by / Then by / Sort within); a pinned section; per-row pin/archive; multi-select scoped to Tag…; and the last-model shown in the historical header. Rows 6, 15, 24, 30, 31.

### Task B3.1 — Two-level grouping + archive in `SidebarOrganizer`

**Files:**
- Modify: `Sources/FabledCore/SidebarOrganizer.swift`
- Test: `Tests/FabledCoreTests/SidebarOrganizerTests.swift`

- [ ] **Step 1: Write the failing tests** for the new shape — `SidebarOptions` gains `thenBy: GroupBy` (secondary) + `archivedSessionIDs: Set<String>`; `organize` returns nested sections (primary → sub-groups). Assert default Date › Project:

```swift
@Test func twoLevelDateThenProjectNestsCorrectly() {
    var opts = SidebarOptions(); opts.groupBy = .date; opts.thenBy = .project
    let now = Date()
    let s = [ summary(id:"a", project:"P1", at: now),
              summary(id:"b", project:"P2", at: now),
              summary(id:"c", project:"P1", at: now.addingTimeInterval(-2*86_400)) ]
    let tree = SidebarOrganizer.organizeTwoLevel(s, options: opts, now: now)
    #expect(tree.map(\.title) == ["Today", "Earlier"])          // primary = date
    #expect(tree[0].subgroups.map(\.title).sorted() == ["P1","P2"])  // sub = project
}
@Test func archivedSessionsAreHidden() {
    var opts = SidebarOptions(); opts.archivedSessionIDs = ["x"]
    let tree = SidebarOrganizer.organizeTwoLevel([summary(id:"x", project:"P", at: Date())], options: opts, now: Date())
    #expect(tree.allSatisfy { $0.subgroups.allSatisfy { $0.sessions.isEmpty } } || tree.isEmpty)
}
```

- [ ] **Step 2: Run — expect failure.** `swift test --filter SidebarOrganizerTests`

- [ ] **Step 3: Implement.** Add to `SidebarOptions`: `public var thenBy: GroupBy = .project` and `public var archivedSessionIDs: Set<String> = []`; set defaults `groupBy = .date`, `thenBy = .project` (DECISIONS default Date › Project). Add a `SidebarPrimaryGroup { id, title, subgroups: [SidebarSection] }` type and `organizeTwoLevel(_:options:now:)` that (a) drops archived ids, (b) applies the activity window (pins bypass, as today), (c) buckets by `groupBy`, then within each primary bucket buckets by `thenBy` reusing the existing per-axis bucketing (extract the date/project bucketers into helpers so both levels share them), (d) keeps the leading Pinned section. `none` at either level collapses that level. Keep the old `organize` for any remaining single-level callers (or migrate them).

- [ ] **Step 4: Run — expect pass.**

- [ ] **Step 5: Commit.** `git add -A && git commit -m "feat(sidebar): two-level Date › Project grouping + archive (rows 6/30, B3.1)"`

### Task B3.2 — Live-attention partition (Needs you / Working) above grouping

**Files:**
- Modify: `Sources/FabledCore/AppModel.swift`
- Test: `Tests/FabledCoreTests/AppModelTests.swift`

- [ ] **Step 1: Write the failing test** — `AppModel` exposes the two attention buckets from live sessions:

```swift
@Test @MainActor func attentionPartitionsLiveSessions() throws {
    let model = try AppModel(defaults: UserDefaults(suiteName: "b3.2.\(UUID())")!)
    // adopt one needs-approval + one working + one idle test session
    // (reuse adoptForTesting + the ChatSession stubs used in existing AppModel tests)
    #expect(model.needsYouSessions.count == 1)
    #expect(model.workingSessions.count == 1)
}
```

- [ ] **Step 2: Run — expect failure.**

- [ ] **Step 3: Implement** computed properties on `AppModel`:
```swift
public var needsYouSessions: [ChatSession] { liveSessions.filter { $0.activityState == .needsApproval } }
public var workingSessions: [ChatSession] { liveSessions.filter { $0.activityState == .working } }
```
(Idle live sessions fall into normal grouping/history; this matches row 24 — silence carries no decoration.)

- [ ] **Step 4: Run — expect pass. Commit** with B3.3 (view consumes it).

### Task B3.3 — Rebuild `SidebarView`: funnel, attention, two-level rows, per-row pin/archive

**Files:**
- Create: `App/FunnelPopover.swift`
- Modify: `App/SidebarView.swift`

- [ ] **Step 1: Attention sections (§3.4).** At the top of the list (above grouping, only when non-empty): a **"Needs you"** header (`Theme.needsYou`, count) with rows carrying a 2px amber left-border + `needsYou.opacity(.08)` fill, title + preview (`gate.summaryLine`) + meta; a **"Ready to review"** variant in `Theme.review`; a **"Working"** header (bronze count) with rows carrying a pulsing `Theme.live` dot + "running · <cmd>". Feed from `app.needsYouSessions`/`app.workingSessions`. Replaces the old "Live" section (kills row 24's lone badge).

- [ ] **Step 2: Funnel popover (§3.3).** Build `FunnelPopover` — a `Menu`/`Popover` with three labeled groups: **Group by** (Date/Project/State), **Then by** (Project/Date/None, with the current primary dimmed/disabled), **Sort within** (Recent activity/A–Z) — bound to `app.sidebarOptions.groupBy/thenBy/sortBy`. The funnel button label reflects the pair ("Date › Project"). Replace the current single "Group by/Sort/Last activity" toolbar menu.

- [ ] **Step 3: Two-level rows (§3.5).** Render `SidebarOrganizer.organizeTwoLevel(app.allSummaries, options:, now:)`: primary header (`.pgrp`, top hairline divider, uppercase) → sub-group header (`.sgrp`, indented, with a **project color dot** — a 6pt rounded square; assign per-project colors from a small stable hash → a fixed bronze/blue/teal/… set, **projects only**, DECISIONS) → session rows (`.prow`: title + relative time, hover `Theme.panelRecessed`, selected inset-hairline). Keep search results + indexing overlay.

- [ ] **Step 4: Per-row pin + archive (§3.6, row 31).** Context menu on each session row: Pin/Unpin (`app.togglePin`), **Archive** (`app.toggleArchive(id)` — add: insert/remove in `sidebarOptions.archivedSessionIDs`), Continue, Fork. Pinned rows show the inline bronze pin icon; a leading Pinned section already comes from the organizer.

- [ ] **Step 5: Build + verify.** Screenshot: needs-you/working float on top; funnel switches Date›Project vs Project›Date; project dots; right-click pins/archives a row.

- [ ] **Step 6: Commit.**
```bash
xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled build
git add -A && git commit -m "feat(sidebar): attention sections + funnel + two-level rows + per-row pin/archive (rows 6/24/30/31, B3.3)"
```

### Task B3.4 — Multi-select scoped to tagging (Select → checkboxes → Tag…/Archive)

**Files:**
- Modify: `App/SidebarView.swift`
- Modify: `Sources/FabledCore/AppModel.swift` (selection set)

- [ ] **Step 1: Selection state.** Add `@State private var isSelecting = false` and `@State private var selectedIDs: Set<String> = []` to `SidebarView` (view-local — it's a transient mode). A **"Select"** button (§3.2 `.selbtn`) toggles `isSelecting`; in that mode each row shows a checkbox (§3.7 `.msbox`, filled bronze when on); ⌘/⇧-click and plain click toggle membership.

- [ ] **Step 2: Action bar (§3.7).** When `!selectedIDs.isEmpty`, show a bottom `.msbar` (`Theme.panelRecessed`) with "N selected" (bronze) + **Tag…** (opens the `TagPickerPopover` from B4 scoped to the batch → `app.applyTags(add:remove:to: selectedIDs)`) + **Archive** (`selectedIDs.forEach(app.toggleArchive)`) + Pin. Per DECISIONS this exists **only** to tag/archive many at once — no general bulk system.

- [ ] **Step 3: Build.** (Tag… is wired in B4.7; here it can be present-but-disabled until B4 lands, or land B4 first — see execution note.) Commit:
`git add -A && git commit -m "feat(sidebar): multi-select scoped to tagging/archive (row 31, B3.4)"`

### Task B3.5 — Last-model in the historical header (row 15 display remainder)

**Files:**
- Modify: `App/HistoricalSessionView.swift`, `Sources/FabledCore/AppModel.swift`
- Test: `Tests/FabledCoreTests/AppModelTests.swift`

- [ ] **Step 1: Write the failing test** — `AppModel` can report a summary's last model cheaply (reuse `store.resumeState(for:)`, which already derives it):

```swift
@Test @MainActor func lastModelForSummaryComesFromResumeState() async throws {
    // point a test SessionStore at a fixture transcript whose last assistant
    // message.model == "claude-opus-4-8"; assert app.lastModel(for: summary) == that.
}
```
(Use the existing `SessionResumeStateTests` fixture / `SessionStore` test seam.)

- [ ] **Step 2: Run — expect failure. Step 3: Implement** `AppModel.lastModel(for:) async -> String?` delegating to `store.resumeState(for:).model`. **Step 4: Run — expect pass.**

- [ ] **Step 5: Show it.** In `HistoricalSessionView`, load `lastModel` in the `.task` (alongside the transcript — the view already loads the whole file, so no new cost) and render it as a `navigationSubtitle` addendum or a quiet line under the title: "Last model: Opus 4.8" (resolve the display name via `ModelOption.merged`). This satisfies row 15's "know what the last model was" exactly where Ben decides whether to resume. (Sidebar rows stay model-free — the mockup's `.prow` shows time only; DECISIONS-faithful.)

- [ ] **Step 6: Build + commit.**
```bash
xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled build
git add -A && git commit -m "feat(sidebar): show last model in the historical header (row 15, B3.5)"
```

**B3 gate checkpoint (Ben):** attention on top; Date›Project by default, switchable; project color dots; right-click pin/archive; Select → tag several at once; a past session tells you its last model before you resume.

---
---

# PHASE B4 — Tags

**Outcome:** plain text tag chips (colour reserved for projects), a searchable picker with per-tag counts, a starter set, rename + delete-asks-first, an AND filter chip row, tags editable inside a session, and batch tagging via multi-select — built for Ben's creative/PhD workload (characters, scenes, chapters, papers). Rows 13, 31, 32.

### Task B4.1 — `TagIndex`: the pure tag algebra

**Files:**
- Create: `Sources/ClaudeKit/TagIndex.swift`
- Test: `Tests/ClaudeKitTests/TagIndexTests.swift`

- [ ] **Step 1: Write the failing tests:**

```swift
import Testing
@testable import ClaudeKit

struct TagIndexTests {
    @Test func startsWithTheStarterSet() {
        let i = TagIndex()
        #expect(Set(i.allTags) == ["bug","review","design","release"])
    }
    @Test func setAndCount() {
        var i = TagIndex()
        i.setTags(["design","scene"], for: "s1")
        i.setTags(["design"], for: "s2")
        #expect(i.tags(for: "s1") == ["design","scene"])
        #expect(i.count(of: "design") == 2)
        #expect(i.allTags.contains("scene"))          // new tag registered
    }
    @Test func filterMultipleTagsIsAND() {
        var i = TagIndex()
        i.setTags(["design","scene"], for: "s1")
        i.setTags(["design"], for: "s2")
        #expect(i.sessions(matchingAll: ["design","scene"]) == ["s1"])
    }
    @Test func renamePreservesAssignments() {
        var i = TagIndex(); i.setTags(["protag"], for: "s1")
        i.rename("protag", to: "protagonist")
        #expect(i.tags(for: "s1") == ["protagonist"])
        #expect(!i.allTags.contains("protag"))
    }
    @Test func deleteRemovesEverywhereKeepsSessions() {
        var i = TagIndex(); i.setTags(["design","scene"], for: "s1")
        i.delete("design")
        #expect(i.tags(for: "s1") == ["scene"])       // session kept, tag gone
        #expect(!i.allTags.contains("design"))
    }
    @Test func codableRoundTrips() throws {
        var i = TagIndex(); i.setTags(["a","b"], for: "s1")
        let data = try JSONEncoder().encode(i)
        #expect(try JSONDecoder().decode(TagIndex.self, from: data).tags(for: "s1") == ["a","b"])
    }
}
```

- [ ] **Step 2: Run — expect failure.** `swift test --filter TagIndexTests`

- [ ] **Step 3: Implement `TagIndex`** — a `Codable, Equatable, Sendable struct` holding `registry: [String]` (all known tags incl. unused, ordered) and `assignments: [String: [String]]` (session id → its tags). Methods: `allTags`, `tags(for:)`, `count(of:)` (derived from assignments), `setTags(_:for:)` (registers new tags), `addTag`/`removeTag(for:)`, `sessions(matchingAll:)` (AND), `rename(_:to:)`, `delete(_:)` (strip from registry + every assignment, keep sessions). Init seeds the starter set `["bug","review","design","release"]`. Tags are lowercased/trimmed on entry; dedupe.

- [ ] **Step 4: Run — expect pass. Commit.**
```bash
git add Sources/ClaudeKit/TagIndex.swift Tests/ClaudeKitTests/TagIndexTests.swift
git commit -m "feat(tags): pure TagIndex — registry, counts, AND-filter, rename, delete (rows 13/32, B4.1)"
```

### Task B4.2 — `TagStore` persistence + `AppModel` integration

**Files:**
- Create: `Sources/ClaudeKit/TagStore.swift`
- Modify: `Sources/FabledCore/AppModel.swift`
- Test: `Tests/ClaudeKitTests/TagStoreTests.swift`, `Tests/FabledCoreTests/AppModelTests.swift`

- [ ] **Step 1: Write the failing store test** (temp dir, like `SessionStoreTests`):

```swift
@Test func persistsAndReloads() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let store = TagStore(fileURL: url)
    var i = await store.load(); i.setTags(["design"], for: "s1"); await store.save(i)
    #expect(await TagStore(fileURL: url).load().tags(for: "s1") == ["design"])
}
```

- [ ] **Step 2: Run — expect failure. Step 3: Implement `TagStore`** — an `actor` with `init(fileURL:)` (default `Application Support/Fabled/tags.json`, sibling of `index.sqlite`), `load() -> TagIndex` (missing file → `TagIndex()`), `save(_:)` (atomic write, create dir). **Step 4: Run — expect pass.**

- [ ] **Step 5: AppModel integration test + impl.** Add to `AppModel`: a `tagStore`, an in-memory `public private(set) var tags = TagIndex()`, load it in `bootstrap()`, and `@MainActor` ops that mutate `tags` + persist async: `tags(for:)`, `applyTags(add:remove:to ids:Set<String>)`, `renameTag`, `deleteTag`, plus `public var tagFilter: Set<String> = []` (the active AND filter) and a computed `filteredSummaries` = `allSummaries` narrowed by `tags.sessions(matchingAll: tagFilter)` when the filter is non-empty. Test `applyTags`/`filteredSummaries` with a stub store.

- [ ] **Step 6: Commit.**
```bash
git add -A && git commit -m "feat(tags): TagStore persistence + AppModel tag ops and AND-filter (B4.2)"
```

### Task B4.3 — Plain tag chips on session rows + AND filter bar

**Files:**
- Create: `App/TagChip.swift`, `App/TagFilterBar.swift`
- Modify: `App/SidebarView.swift`

- [ ] **Step 1: `TagChip`** (§4.3, PLAIN — no colour): inline text, `600 10`, padding 3×7, radius 5, `Theme.panelRecessed` fill, 1px `Theme.hairline`, **`Theme.muted` text** (deliberately quiet). No per-tag colour (colour is projects-only — DECISIONS).

- [ ] **Step 2: Show chips under session rows** — in the sidebar session row, a wrap of `TagChip` for `app.tags.tags(for: summary.id)` below the title (§4.3).

- [ ] **Step 3: `TagFilterBar`** (§4.2): a wrap row of filter chips — "All" + each active filter tag as a `Capsule` chip (bronze inset ring when on) + a `＋` chip that opens the picker to add a filter tag; toggling a chip mutates `app.tagFilter`; multiple = AND (row 13). Place it under the sidebar search field; when `tagFilter` is non-empty the sidebar renders `app.filteredSummaries`.

- [ ] **Step 4: Build + verify.** Screenshot: tag chips under sessions; selecting `design` + `scene` narrows to sessions having both.

- [ ] **Step 5: Commit.** `git add -A && git commit -m "feat(tags): plain chips on rows + AND filter bar (rows 13/32, B4.3)"`

### Task B4.4 — Searchable tag picker (counts, inline new tag)

**Files:**
- Create: `App/TagPickerPopover.swift`

- [ ] **Step 1: Build the picker** (§4.4): a popover with a header ("Tags · <session/batch>", "Edit" → Manage), a search field ("Filter tags…"), a scrollable list of `TagPickerRow`s (checkbox filled-bronze when on; tag name; per-tag count right-aligned via `app.tags.count(of:)`), and a **New-tag row** that appears when the search text matches no existing tag ("New tag "act 2"…", bronze, plus icon) creating + applying it. Checking/unchecking calls the caller's apply closure. Searchable keeps the everyday list short even at 40+ tags (row 32).

- [ ] **Step 2: Present it** from (a) a per-session tag affordance (B4.6) and (b) the multi-select **Tag…** action (B4.7) — the popover takes an `apply: (_ add: Set<String>, _ remove: Set<String>) -> Void` closure so both callers reuse it.

- [ ] **Step 3: Build + commit.** `git add -A && git commit -m "feat(tags): searchable picker with counts + inline new-tag (row 13, B4.4)"`

### Task B4.5 — Manage tags: rename + delete-asks-first

**Files:**
- Create: `App/ManageTagsView.swift`

- [ ] **Step 1: Build Manage** (§4.5): "Edit" flips the picker into a managed list — each row: name (editable inline on the rename pencil → commits `app.renameTag`), per-tag count, a rename (pencil) and delete (trash, soft-red `Theme.diffDelColor`). **Delete-asks-first (DECISIONS):** deleting a tag used by >1 session presents a confirm ("Remove "scene" from 12 sessions? The sessions are kept.") and is **undoable** (keep the last-deleted `(tag, assignments)` for a single Undo). Single-use/unused tags delete without a prompt.

- [ ] **Step 2: Build + commit.** `git add -A && git commit -m "feat(tags): manage — rename + delete-asks-first, undoable (row 13, B4.5)"`

### Task B4.6 — Tags editable inside a session

**Files:**
- Modify: `App/ConversationView.swift`, `App/HistoricalSessionView.swift`

- [ ] **Step 1: Title-adjacent tags** (§4.6): next to the conversation title (both live and historical), render the session's `TagChip`s + a `＋` that opens `TagPickerPopover` scoped to this session id (`app.applyTags(add:remove:to:[id])`). Live sessions key by `session.resumedSessionID ?? session.info?.sessionID` (the on-disk id) so tags persist across resume; historical by `summary.id`. Editing here writes through the same store — no trip to the sidebar (row 13).

- [ ] **Step 2: Build + commit.** `git add -A && git commit -m "feat(tags): edit tags beside the session title (row 13, B4.6)"`

### Task B4.7 — Wire multi-select Tag… to the batch

**Files:**
- Modify: `App/SidebarView.swift`

- [ ] **Step 1: Connect** the B3.4 action-bar **Tag…** button to `TagPickerPopover` with `apply: { add, remove in app.applyTags(add: add, remove: remove, to: selectedIDs) }`, then exit select mode. This is the whole reason multi-select exists (DECISIONS row 31).

- [ ] **Step 2: Build + verify + commit.**
```bash
xcodegen generate && xcodebuild -project Fabled.xcodeproj -scheme Fabled build
git add -A && git commit -m "feat(tags): batch-tag many sessions via multi-select (row 31, B4.7)"
```

**B4 gate checkpoint (Ben):** tag a session (creative tags: a character, a scene, a chapter); filter by two tags (AND); rename and delete (delete asks first); tag several at once; edit tags from inside a session. Confirm it feels built for his novel/thesis tagging, not just dev.

---
---

## Execution order (waves)

Ben's friction-first ordering (DECISIONS "Post-4b roadmap", his sign-off) is the spine and overrides a generic harden-first: **B0 → B1 → B2 → B3 → B4**. Within that:
- B0 is the foundation everything imports — it lands first, whole.
- Inside each phase: the TDD'd `FabledCore`/`ClaudeKit` core lands before the view that consumes it (the view is built on a green model).
- **B2.1 (the confirmed step-grouping bug) is the one "harden-first" item** — do it first within B2, before the B2 view work, so Ben's headline grievance is provable early.
- **B4.1–B4.4 before B3.4's Tag… wiring** (mutually referential); if B3 lands first, ship B3.4 with Tag… disabled and B4.7 connects it.
- Commit per task; each ends green (`swift test`) or building (`xcodebuild`). Batch every honesty-gate item into one plain-English checklist per phase for Ben.

## Pre-execution self-audit (adversarial — tried to break this plan)

Per `driving-opus.md` "Plan something": a plan that survives its own audit unmodified is suspicious. Outcomes recorded inline.

1. **Every OPEN ledger row has a task?** ✅ ok — coverage map maps all; row 20 flagged Ben's-discretion (not descoped); 14/15/18 surfaced from the hotfix.
2. **Row 25 — diagnosis real or assumed?** ✅→FIXED: originally inherited the 4b reviewer's "gated tools" hypothesis; verifying a real transcript showed permissions aren't on disk and `thinking` is the breaker. Fix + tests retargeted; residual (narration) made a co-design gate, not silently widened.
3. **Tag storage — is "the custom-title sidecar store" writable?** ✅→FIXED: it is not (titles are read from CLI-written transcript lines). Invariant 2 + B4.2 create a dedicated `tags.json`; the DECISIONS phrase is treated as aspirational and called out to Ben.
4. **Do the composer chips have a model catalog before a session exists?** ✅→FIXED: no — B1.4 / research-note 5 use `ModelOption.merged(catalog: [])` for the `.newSession` target.
5. **Does removing the toolbar pickers (B2.2) strand any control?** ✅ ok — model/effort/permission move to chips; active-model text + cost stay in the toolbar; the hotfix's "New sessions" logic is reused, not deleted.
6. **Two-level grouping — will old persisted `SidebarOptions` still decode?** ✅ ok — `thenBy`/`archivedSessionIDs` are defaulted Codable fields (research note 7); B3.1 adds a missing-key decode test if the suite doesn't already cover it.
7. **Type-to-resume — can it spawn a second process on one id?** ✅ ok — routes through `resume(_:fork:)`'s guard (invariant 1); the test asserts `resumeSessionID` + a single live selection.
8. **Does the row-25 fix hide denials or lose thinking?** ✅ ok — only resolved-allow is transparent (invariant 4); absorbed thinking is preserved and shown on expand (B2.1 step 4).
9. **Git strip on a non-repo session?** ✅ ok — `GitInfo.read` returns nil → strip hidden (B2.4 test `nonRepoReturnsNil`).
10. **New App files without `xcodegen generate`?** ✅ ok — invariant 5; every view task's build step runs it.
11. **Placeholders / type drift?** ✅ ok — logic tasks carry real test+impl code; view tasks carry exact tokens + the non-obvious code with a *stated* build+gate strategy (not "TBD"). Shared names (`ComposerChips(target:)`, `ActivityList.rows(timeline:subagents:)`, `SidebarOrganizer.organizeTwoLevel`, `TagIndex`/`TagStore`, `AppModel.goHome/resumeAndSend/preferredModel/applyTags/tagFilter/filteredSummaries/lastModel`, `GitInfo.read(at:)`) are consistent across defining and consuming tasks.

This audit changed items 2, 3, 4 — the plan did not survive unmodified.

---

## Handoff note

Built to the fable-kit standard (`plan-template.md`, `driving-opus.md` "Plan something"): verification model + honesty gates, non-negotiable invariants with ⚠️ landmines, source-cited research notes, a Does/Untouched/Deferred scope fence, Task 0 = branch, risk-aware waves, and this adversarial self-audit. Execute with the triplet (implementer → spec-compliance reviewer → quality reviewer), verifying behaviourally at each gate. When a phase's honesty gate is met, the corresponding UX-LEDGER rows move from `pending-verification` to CLOSED — only on Ben's build-verify.
