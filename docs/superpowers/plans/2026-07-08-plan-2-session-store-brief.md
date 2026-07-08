# Plan 2 brief: SessionStore + history search

**Status:** EXPANDED 2026-07-08 → full plan at `2026-07-08-plan-2-session-store.md` (contract amendments ledgered in `../DECISIONS.md`). This brief is retained for history; work from the full plan.
**Prerequisite:** Plan 1 complete (`ClaudeKit` builds, all tests green).
**Goal:** Read, watch, and search every Claude Code session on disk (`~/.claude/projects/**/*.jsonl`) with zero CLI processes. This is the data layer for the sidebar and the session browser.

## Locked public API (ClaudeKit additions)

```swift
public struct ProjectFolder: Sendable, Hashable, Identifiable {
    public var id: String { flattenedName }
    public let flattenedName: String      // e.g. "-Users-andiyar-Developer-Wine"
    public let originalPath: String       // best-effort de-flattened, e.g. "/Users/andiyar/Developer/Wine"
    public let directoryURL: URL
}

public struct SessionSummary: Sendable, Identifiable {
    public let id: String                 // session UUID (filename stem)
    public let project: ProjectFolder
    public let fileURL: URL
    public let title: String              // summary line if present, else first user text, else id
    public let lastActivity: Date         // file mtime
    public let approximateSizeBytes: Int
}

public enum TranscriptEntry: Sendable {
    case event(AgentEvent)                // reuses Plan 1 decoding for embedded messages
    case queueOperation(raw: JSONValue)
    case summary(text: String, raw: JSONValue)
    case attachment(raw: JSONValue)
    case unknown(raw: JSONValue)
}

public actor SessionStore {
    public init(projectsRoot: URL)        // default: ~/.claude/projects
    public func projects() throws -> [ProjectFolder]
    public func sessions(in project: ProjectFolder) throws -> [SessionSummary]
    public func transcript(for session: SessionSummary) throws -> [TranscriptEntry]
    /// Fires on any change under projectsRoot (debounced ≥250ms). Payload = affected session file URLs.
    public var changes: AsyncStream<[URL]> { get }
}

public struct SearchHit: Sendable, Identifiable {
    public let id: String                 // "\(sessionID):\(lineNumber)"
    public let session: SessionSummary
    public let snippet: String            // FTS snippet with match context
    public let lineNumber: Int
}

public actor SearchIndex {
    public init(databaseURL: URL, store: SessionStore) throws
    /// Incremental: (path, mtime, size) unchanged → skip file.
    public func reindex() async throws
    public func search(_ query: String, limit: Int) async throws -> [SearchHit]
}
```

## Design decisions (ledgered)

- **On-disk transcript ≠ live stream.** Session files contain a superset: `queue-operation` lines, `summary` lines, entries wrapped with `parentUuid`/`isSidechain`/`attachment` fields. `TranscriptEntry` wraps `AgentEvent` rather than forcing everything through it. Real examples: see any file in `~/.claude/projects/-Users-andiyar-Developer/`. **First implementation task must copy 2–3 real session files into `fixtures/transcripts/` (small ones; they may contain personal content — Ben has approved local use, do not publish).**
- **Search = SQLite FTS5 via the system `sqlite3` C library** (`import SQLite3`, ~150-line wrapper). No third-party dependency in ClaudeKit — this is deliberate; do not add GRDB.
- **Index location:** `~/Library/Application Support/Fabled/index.sqlite`. Schema: `files(path PRIMARY KEY, mtime, size)` + FTS5 table `lines(session_id, project, line_no, text)`. Index only human-relevant text (user text, assistant text, summaries) — not raw JSON.
- **Watching:** DispatchSource kqueue on directories + debounced rescan, not FSEventStream (C callback API fights Swift 6 concurrency for no benefit at this scale).
- **De-flattening project names** is heuristic (dashes → slashes is ambiguous for paths containing dashes). Store both; resolve by checking which candidate paths exist on disk; fall back to the flattened name for display.

## Task outline (expand into full TDD tasks)

1. Transcript fixtures: copy real session files, add loader.
2. `TranscriptEntry` decoding (TDD against those fixtures; whole-file decode must produce zero `.unknown` for the fixture set).
3. `ProjectFolder` + de-flattening heuristic (pure, table-driven tests).
4. `SessionSummary` enumeration + title derivation.
5. SQLite wrapper (open/exec/prepare/step; in-memory DB tests).
6. `SearchIndex` schema + incremental reindex.
7. `search()` with FTS5 snippets.
8. `SessionStore.changes` watcher (test with a temp dir, touch files, assert debounced events).
9. Performance gate: index Ben's real `~/.claude/projects` (hundreds of MB) in <30s cold, <1s warm; `transcript(for:)` on the largest real file <500ms. Measure, don't assume — this is a spec risk item.

## Verify by probing (during plan-writing)

- Exact shapes of `summary` and `attachment` lines in current transcripts (inspect real files; shapes above are from 2026-07-08 observations).
- Whether compacted sessions leave markers that affect title/transcript derivation.
