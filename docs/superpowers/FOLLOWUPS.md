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
- Tool/raw card expansion `@State` resets when the LazyVStack recycles offscreen rows. → Plan 4 polish.
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

## From final Plan 1 gate review (2026-07-08)

- **No `--session-id` in SessionConfiguration** (spec lists it; `extraArguments` is the escape hatch). → Plan 2 if SessionStore wants deterministic UUIDs.

## From AgentSession review (2026-07-08, Task 7)

Fixed in-task: trailing-event race (join read task before `.terminated`), undrained stderr deadlock, unfinished stream on launch failure.

Deferred:

- **SIGTERM-only terminate (M2).** No SIGKILL escalation; a stuck child never dies. Add kill-after-timeout. → Plan 4 (session management).
- **Byte-by-byte stdout reads (M4).** Only if profiling shows it matters. → backlog.
- **Blocking stderr drain pins a cooperative-pool thread per live session.** `Task.detached` + blocking `read(upToCount:)` for the child's lifetime is fine at Mac-app session counts; switch to `readabilityHandler` or `handle.bytes` if session counts grow. → backlog (with M4).
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
