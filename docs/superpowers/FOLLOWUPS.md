# Follow-ups

Tracked items that were deliberately deferred. Source: code reviews and task reports. Pull these into the appropriate plan when their layer is next touched.

## Resolved in Plan 3 (2026-07-09)

- **Control-op response correlation (Plan 1).** Control ops now return their `request_id`; `AgentSession.initializeRequestID` lets ChatSession match the initialize `control_response`. → fixed in T1.
- **`.allow(updatedInput: nil)` unverified against the real CLI (Plan 1).** Probed live and reshaped — `updatedInput` is now mandatory (echoed from the request when nil), so the old nil-payload footgun is impossible to misuse. → fixed in T2.
- **`user` events without tool_result blocks decode to `.toolResult([])` (Plan 1).** The reducer treats these semantically-null events as no-ops. → fixed in T5 reducer.
- **`AgentEvent` not Equatable (Plan 1).** Added via extension for SwiftUI diffing. → fixed in T1.
- **Orphaned child on actor dealloc (I2, Plan 1).** `AgentSession` terminates its child on deinit; ChatSession owns the lifecycle. → fixed in T1.
- **SIGPIPE on writes after child death (I3, Plan 1).** A `terminated` flag short-circuits writes and `SIGPIPE` is ignored at app startup. → fixed in T1 + T8.
- **`SearchIndex.reindex()` unsafe under overlapping invocation (Plan 2).** Serializing guard added before the watcher→reindex wiring. → fixed in T4.
- **File vanishing mid-reindex aborts the whole pass (Plan 2).** The vanished file is caught and skipped; the pass and pruning continue. → fixed in T4.
- **Two title sources can disagree (Plan 2 gate review).** Resolved in the index's favor — the sidebar reads `SearchIndex.sessionSummaries()` titles from the files table. → fixed in T4/T9.

## Deferred from Plan 3 (2026-07-09)

Carried forward from the plan's known list:

- `events`-before-`start()` still returns a dead placeholder stream (M3) — ChatSession always starts first, but the ClaudeKit API sharp edge remains. → Plan 4.
- Unbounded AsyncStream buffers (Plan 1 M1 / Plan 2 changes-stream) — consumers drain promptly on MainActor; revisit only if profiling shows growth. → backlog.
- Heavy `transcript(for:)` reads still run on the SessionStore executor (~0.65 s for the 52 MB pathological file) — fine for open-on-click; revisit with nonisolated reads if the sidebar ever stutters. → Plan 4 if felt.

Surfaced by Plan 3's per-task code reviews:

- Optimistic control ops: `setModel`/`setPermissionMode` update UI state before the (unverified) CLI ack; a rejected custom model ID leaves a stale toolbar label. No ack correlation for non-init control ops. → Plan 4.
- ~~Tool/raw card expansion `@State` resets when the LazyVStack recycles offscreen rows.~~ → resolved in Plan 4a Task 6: the inspector design removed per-row expansion state entirely.
- `AssistantTextView` re-parses the full markdown string per streaming delta (O(n²) on very long messages). → watch item; revisit if long replies stutter.
- `HistoricalSessionView.task(id:)` has a tiny stale-assignment window on rapid session switching (no cancellation check before assignment). → Plan 4 polish.
- `resume()` silently falls back to `$HOME` as cwd when a project directory no longer resolves. → Plan 4 (surface in UI).
- Transcript replay hides real user prompts starting with `<` (mirrors the established title heuristic; the live view shows them). → backlog.
- Cosmetic: the custom-model sheet keeps stale text across opens; an unknown permission mode renders an empty picker; the model-menu checkmark misaligns the icon gutter. → backlog.
- PERF enumeration gate (<5 s) fails at ~5.5 s on the current 696-session corpus — pre-existing at the pre-Plan-3 baseline (stash-verified in Task 4), environment-bound. → recalibrate or make corpus-relative; backlog.
- Watcher burst behavior (decision note, resolved): `SessionStore.changes` throttles at 250 ms upstream and `SearchIndex.reindex()` serializes overlapping passes, so watcher bursts are bounded (~4 passes/sec worst case) — no coalescing needed in AppModel.
- Gate feedback wishlist: sidebar sorting options, session tagging, and general QoL organization features. → Plan 4 scoping.
- Gate feedback — Electron-app layout parity: tool/code activity as compact summaries opening in a side inspector panel (not inline disclosure), plus bubble width tuning. → Plan 4 (conversation surfaces).

## From Plan 4a T7 quality review (2026-07-09)

Deferred:

- **DiffCache has no eviction bound.** Entries live for the app's lifetime (LRU by count/bytes, or a size threshold that skips caching giant inputs, would bound it). Consider relocating the cache to FabledCore so the revalidation contract ({} → full input, no stale diffs) becomes unit-testable. → backlog.
- **DiffSectionView renders every diff line in a non-lazy VStack.** A multi-thousand-line Write builds thousands of views on inspector-open in one shot. Cap rendered lines with a "+M more lines" affordance, or fall back to the plain monospaced block above a threshold. → backlog.
- **Optional engine test pins not yet written.** All-edits-malformed MultiEdit → nil; empty edits array → nil; Write missing content → nil; MultiEdit missing file_path → nil. → backlog.

## From Plan 4a T8 quality review (2026-07-09)

Deferred:

- **QuestionCardView a11y.** Custom radio/checkbox option rows carry no `.accessibilityAddTraits(.isSelected)` and aren't grouped as single a11y elements, so VoiceOver can't convey selection state; single-shot mode is also mouse-dependent unless Full Keyboard Access is on (no Answer button, send ⌘⏎ disabled while a gate shows). Also fold in: tap-gesture tool rows (ba55f1f) carry `.isButton` traits but no explicit `.accessibilityAction` and no Full-Keyboard-Access focusability — the Button→TapGesture trade was evidence-driven (press-cancellation under churn), so restore keyboard/assistive activation by other means. → backlog (a11y pass).
- **Answer-assembly logic is untestable where it lives.** Catalog ordering, ", " join, option-wins-over-free-text, trim, and free-text-alone completeness (probe finding 2) are private methods in the App-target view. Extract a pure `QuestionPrompt.assembleAnswers(selections:otherText:)` into FabledCore so FabledCoreTests can pin it — same pattern as the DiffCache relocation note above. → backlog.
- **No height bound on long question forms.** 10+ options grow the composer card unbounded; wrap in a ScrollView with max height if long forms appear in practice. → backlog.

## From Plan 4a T9 quality review (2026-07-09)

Deferred:

- **Empty-feedback plan rejection message is not test-pinned.** `rejectPlan(_:feedback:)` with empty/whitespace feedback sends the default "The user rejected the plan. Revise it..." message; only the non-empty branch has a test. One-line FabledCore test closes it. → backlog.
- **Stale-sheet dismissal invariant lives in a View closure, untestable.** Extract the presence check into a `ChatSession.hasPendingGate(requestID:)` helper if it ever needs pinning across abort/approve/reject transitions. → backlog.
- **`planTitle` trims-to-empty edge.** A first line like "###" yields an empty caption instead of the "Untitled plan" fallback. Cosmetic. → backlog.
- **Esc semantics differ across gate surfaces (note, decided).** Sheet Esc = close/decide-later; question-card Esc = Skip (commits). Matches platform convention for sheets; keep unless gate feedback says otherwise.

## From Plan 4a T10 quality review (2026-07-09)

Deferred:

- **ConversationView is reused across live-session switches without identity.** Root cause of child-`@State` leaks: the todo card's collapse state (fixed in-task with a card-level `.id`) and the pre-existing T6 inspector state (`isInspectorPresented` persists across session switches — an open inspector stays open, by design for now). `inspectedID` and the Back-button trail `inspectBackStack` were also affected until the 2026-07-10 final review: both now reset via `.onChange(of: session.id)` in ConversationView (cross-session timeline ids collide on reducer fallback ids, so a stale trail could walk Back into another session's items). The clean root fix is still `.id(session-identity)` on ConversationView in RootView.detail, then dropping the card-level `.id` — but audit the blast radius first: recreating the hierarchy on switch resets scroll position and would discard any @State composer draft (check where draft text lives before landing). → Plan 4b or a T12 rider.
- **Sticky manual collapse (note, decided).** Once the user toggles the todo card, auto-collapse behavior never resumes for that session — deliberate sticky-preference semantics; revisit only if gate feedback objects.

## From final Plan 1 gate review (2026-07-08)

- **No `--session-id` in SessionConfiguration** (spec lists it; `extraArguments` is the escape hatch). → Plan 2 if SessionStore wants deterministic UUIDs.

## From AgentSession review (2026-07-08, Task 7)

Fixed in-task: trailing-event race (join read task before `.terminated`), undrained stderr deadlock, unfinished stream on launch failure.

Deferred:

- **SIGTERM-only terminate (M2).** No SIGKILL escalation; a stuck child never dies. Add kill-after-timeout. → Plan 4 (session management).
- **Byte-by-byte stdout reads (M4).** Only if profiling shows it matters. → backlog.
- **RESOLVED 2026-07-10 (8b58a7d) — and the original judgment here was wrong.** "Fine at Mac-app session counts" was disproved in production: cooperative-pool exhaustion from blocking pipe reads silenced sibling sessions' readers at 2–4 open sessions (stderr drain + FileHandle.bytes.lines both parked pool threads). All pipe reads now run on dedicated Threads. Scar: never block cooperative-pool threads on pipe/file I/O, at any session count.
- **Dead `Process` retained after termination (M5).** Harmless; tidy when touching the file. → backlog.

## From Plan 2 reviews (2026-07-08, Tasks 1–11)

Fixed in-task: out-of-window prompt leaking into titles via the title-key byte filter (Task 5); zombie watcher tasks + unfinished subscriber streams on store dealloc (Task 10); per-line `subdata` copies in `JSONLines` (Task 11 perf work).

Deferred:

- **Heavy file I/O on the SessionStore actor executor.** `sessions(in:)`/`transcript(for:)` read+scan multi-MB files inline; one large call serializes all store callers (watcher ticks, UI). Consider `nonisolated` reads off-actor when UI + watcher share the store. → Plan 3 design.
- **`search()` error-swallow is broader than intended (Minor).** `prepare`/`bind` sit inside `catch is SQLiteError → []`, so schema corruption reads as empty results; narrow the catch to the `step()` loop. → Plan 3 polish.
- **`performScheduledRescan` enumerates `projects()` twice per tick (Minor perf).** Once inside `currentSnapshot()`, once for new-dir watching; capture one listing. → backlog.
- **`projectCache` freezes `originalPath` at first sight (Minor).** A project unresolvable at first enumeration stays flattened forever even if the cwd later exists. Doc or re-resolve on miss. → backlog.
- **`maxTitleLineBytes` cutoff untested (Minor test gap).** A >4096-byte title line being skipped has no pinning test. → backlog.
- **mmap truncation edge (note).** `.mappedIfSafe` + a writer truncating/replacing a mapped session file ⇒ SIGBUS. Safe today (CLI appends only); revisit if any tooling rewrites session files.
- **`ftsQuery` wrap-only quoting (note).** A token with an interior `"` can't match a literal quote (degrades to no-results via the narrow catch). Accepted; plan doc's "quotes are doubled" text is stale — the tests mandate wrap-only.
- **`SearchHit` not Equatable/Hashable (note).** Add via extension if Plan 3 diffing needs it.
- **Agent rows render "Agent Agent" pre-input (Minor cosmetic, 2026-07-10 smoke).** Between tool_use start and the input arriving, name and summary are both the placeholder "Agent". Suppress the summary until it differs from the name. → 4b polish.
- **Inspector chrome (✕/Back) are plain Buttons (note).** The panel body re-renders during live streams — if the churn-cancellation disease (see TimelineItemViews row note) ever appears on panel chrome, give them the same tap-gesture treatment. Not observed in the 2026-07-10 smoke. → watch.
- **First-turn latency is model thinking, not harness (2026-07-10 measurements).** App-identical spawn: hooks+handshake+API dispatch <1s; opus full turn 5s. Fable-5 on the same repo question: default effort → first visible text +24s; `--effort medium` → +17s (~30% faster, identical tool-use shape). Claude Desktop passes `--effort` on every spawn AND renders the thinking stream (perceived activation ~3s); Fabled does neither. Two 4b levers: (a) session effort control passing `--effort` (flag confirmed on public CLI 2.1.206); (b) render thinking deltas (dimmed/collapsible) + thinking_tokens ticker instead of the bare spinner. → 4b (pairs with feature 11 liveness).
- **TodoWrite is gone from this CLI config (2026-07-09 finding, ledgered 2026-07-10).** Replaced by TaskCreate/TaskUpdate/TaskList. T10's pinned checklist card is correct-but-dormant: models, reducer, card, and tests all target TodoWrite inputs that never arrive. → 4b: feed the checklist from the task tools (shape probe needed), reuse the card as-is.
- **Live-vs-replay diff-count divergence (Minor, one observation).** One Edit row showed +6−6 live but +5−5 on historical replay of the same session — likely a trailing-newline or coalescing asymmetry between wire input and transcript JSON. One repro + pin test when touched. → backlog.

## From Plan 4b reviews (2026-07-11)

- **resume() TOCTOU guard untested** — the in-flight `resumingSessionIDs` set closes the double-Continue race (T12 review), but testing it needs a launcher-injection seam on AppModel. → 4c if felt.
