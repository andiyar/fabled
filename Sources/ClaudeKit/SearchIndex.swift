import Foundation

/// One full-text match. `lineNumber` is 1-based within the session file, so
/// the UI can jump straight to the matching transcript entry.
public struct SearchHit: Sendable, Identifiable {
    /// "\(session.id):\(lineNumber)"
    public let id: String
    public let session: SessionSummary
    /// FTS5 snippet with [ ] markers around matched terms.
    public let snippet: String
    public let lineNumber: Int

    public init(id: String, session: SessionSummary, snippet: String, lineNumber: Int) {
        self.id = id
        self.session = session
        self.snippet = snippet
        self.lineNumber = lineNumber
    }
}

/// Full-text index over every main session file, incremental by
/// (path, mtime, size). SQLite FTS5 via the system library; the database
/// lives wherever the app points `databaseURL` (Fabled will use
/// ~/Library/Application Support/Fabled/index.sqlite).
public actor SearchIndex {
    private let db: SQLiteDatabase
    private let store: SessionStore

    public init(databaseURL: URL, store: SessionStore) throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        self.db = try SQLiteDatabase(path: databaseURL.path)
        self.store = store
        try db.exec("""
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS files(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                path TEXT NOT NULL UNIQUE,
                session_id TEXT NOT NULL,
                project TEXT NOT NULL,
                mtime REAL NOT NULL,
                size INTEGER NOT NULL,
                title TEXT
            );
            CREATE VIRTUAL TABLE IF NOT EXISTS lines
                USING fts5(text, tokenize='unicode61 remove_diacritics 2');
            """)
    }

    private struct KnownFile {
        let id: Int64
        let mtime: Double
        let size: Int64
    }

    private var reindexChain: Task<Int, any Error>?

    /// Walks every project; parses only files whose (mtime, size) changed;
    /// drops index rows for files that vanished. Returns the number of
    /// files (re)parsed — 0 on a warm no-change pass.
    ///
    /// Overlapping calls serialize: each pass waits for the previous one, so
    /// two watcher ticks can never race the files-table snapshot (the
    /// UNIQUE(path) violation from the Plan 2 review).
    @discardableResult
    public func reindex() async throws -> Int {
        let previous = reindexChain
        let task = Task { [self] in
            _ = try? await previous?.value
            return try await performReindex()
        }
        reindexChain = task
        return try await task.value
    }

    private func performReindex() async throws -> Int {
        var known: [String: KnownFile] = [:]
        let select = try db.prepare("SELECT id, path, mtime, size FROM files")
        while try select.step() {
            known[select.columnText(1)] = KnownFile(
                id: select.columnInt64(0),
                mtime: select.columnDouble(2),
                size: select.columnInt64(3))
        }

        var seen = Set<String>()
        var reindexed = 0
        for project in try await store.projects() {
            for stamp in try await store.sessionFileStamps(in: project) {
                let path = stamp.url.path
                seen.insert(path)
                let mtime = stamp.modified.timeIntervalSince1970
                if let existing = known[path],
                   existing.mtime == mtime, existing.size == Int64(stamp.size) {
                    continue
                }
                // A session deleted (or made unreadable) between the stat and
                // this read must not abort the pass — skip it; the next pass
                // prunes its rows once enumeration stops listing it.
                guard let data = try? Data(contentsOf: stamp.url, options: .mappedIfSafe) else {
                    continue
                }
                try indexFile(stamp, data: data, project: project, replacing: known[path]?.id)
                reindexed += 1
            }
        }
        for (path, file) in known where !seen.contains(path) {
            try remove(fileID: file.id)
        }
        return reindexed
    }

    /// Ranked full-text search. Hits are built entirely from index rows —
    /// no session files are opened, so search stays fast even when hits
    /// land in 50 MB transcripts.
    public func search(_ query: String, limit: Int) async throws -> [SearchHit] {
        let match = Self.ftsQuery(from: query)
        guard !match.isEmpty, limit > 0 else { return [] }
        let projectsByName = Dictionary(
            uniqueKeysWithValues: try await store.projects().map { ($0.flattenedName, $0) })

        // A wrap-only sanitizer keeps free text immune to FTS5 operators, but
        // pathological quote runs can still yield an expression SQLite rejects
        // ("unterminated string") when it parses the MATCH value at step time.
        // Treat any such rejection as "no matches" rather than surfacing it.
        do {
            let statement = try db.prepare("""
                SELECT files.path, files.session_id, files.project, files.mtime,
                       files.size, files.title, lines.rowid,
                       snippet(lines, 0, '[', ']', '…', 16)
                FROM lines
                JOIN files ON files.id = (lines.rowid >> 32)
                WHERE lines MATCH ?
                ORDER BY rank
                LIMIT ?
                """)
            try statement.bind(1, match)
            try statement.bind(2, Int64(limit))

            var hits: [SearchHit] = []
            while try statement.step() {
                let path = statement.columnText(0)
                let sessionID = statement.columnText(1)
                let projectName = statement.columnText(2)
                let fileURL = URL(fileURLWithPath: path)
                let project = projectsByName[projectName] ?? ProjectFolder(
                    flattenedName: projectName,
                    originalPath: projectName,
                    directoryURL: fileURL.deletingLastPathComponent())
                let lineNumber = Int(statement.columnInt64(6) & 0xFFFF_FFFF)
                let session = SessionSummary(
                    id: sessionID,
                    project: project,
                    fileURL: fileURL,
                    title: statement.columnIsNull(5) ? sessionID : statement.columnText(5),
                    lastActivity: Date(timeIntervalSince1970: statement.columnDouble(3)),
                    approximateSizeBytes: Int(statement.columnInt64(4)))
                hits.append(SearchHit(
                    id: "\(sessionID):\(lineNumber)",
                    session: session,
                    snippet: statement.columnText(7),
                    lineNumber: lineNumber))
            }
            return hits
        } catch is SQLiteError {
            return []
        }
    }

    /// Sidebar list source: every indexed session, newest first, straight
    /// from the files table — no session files are opened. Titles here are
    /// the whole-file authoritative ones (DECISIONS: title-source authority),
    /// falling back to the session id for untitled sessions.
    public func sessionSummaries() async throws -> [SessionSummary] {
        let projectsByName = Dictionary(
            uniqueKeysWithValues: try await store.projects().map { ($0.flattenedName, $0) })
        let statement = try db.prepare("""
            SELECT path, session_id, project, mtime, size, title
            FROM files ORDER BY mtime DESC
            """)
        var summaries: [SessionSummary] = []
        while try statement.step() {
            let path = statement.columnText(0)
            let sessionID = statement.columnText(1)
            let projectName = statement.columnText(2)
            let fileURL = URL(fileURLWithPath: path)
            let project = projectsByName[projectName] ?? ProjectFolder(
                flattenedName: projectName,
                originalPath: projectName,
                directoryURL: fileURL.deletingLastPathComponent())
            summaries.append(SessionSummary(
                id: sessionID,
                project: project,
                fileURL: fileURL,
                title: statement.columnIsNull(5) ? sessionID : statement.columnText(5),
                lastActivity: Date(timeIntervalSince1970: statement.columnDouble(3)),
                approximateSizeBytes: Int(statement.columnInt64(4))))
        }
        return summaries
    }

    /// Converts free-typed input into a safe FTS5 expression: each
    /// whitespace-separated token is wrapped in double quotes so FTS5 treats
    /// it as a literal phrase (immune to operator syntax like `AND`, `NOT`,
    /// parens), the final one with a prefix star for as-you-type search.
    static func ftsQuery(from userQuery: String) -> String {
        let tokens = userQuery.split(whereSeparator: \.isWhitespace)
        guard !tokens.isEmpty else { return "" }
        return tokens.enumerated().map { offset, token in
            let phrase = "\"\(token)\""
            return offset == tokens.count - 1 ? phrase + "*" : phrase
        }.joined(separator: " ")
    }

    private func indexFile(
        _ stamp: SessionFileStamp, data: Data, project: ProjectFolder, replacing existingID: Int64?
    ) throws {
        try db.exec("BEGIN IMMEDIATE")
        do {
            let fileID: Int64
            if let existingID {
                try deleteLines(fileID: existingID)
                let update = try db.prepare("UPDATE files SET mtime = ?, size = ? WHERE id = ?")
                try update.bind(1, stamp.modified.timeIntervalSince1970)
                try update.bind(2, Int64(stamp.size))
                try update.bind(3, existingID)
                try update.step()
                fileID = existingID
            } else {
                let insert = try db.prepare("""
                    INSERT INTO files(path, session_id, project, mtime, size)
                    VALUES(?, ?, ?, ?, ?)
                    """)
                try insert.bind(1, stamp.url.path)
                try insert.bind(2, stamp.sessionID)
                try insert.bind(3, project.flattenedName)
                try insert.bind(4, stamp.modified.timeIntervalSince1970)
                try insert.bind(5, Int64(stamp.size))
                try insert.step()
                fileID = db.lastInsertRowID
            }

            var accumulator = TitleAccumulator()
            var lineNumber: Int64 = 0
            let insertLine = try db.prepare("INSERT INTO lines(rowid, text) VALUES(?, ?)")
            for line in JSONLines(data: data) {
                lineNumber += 1
                guard let entry = try? TranscriptDecoder.decode(line) else { continue }
                accumulator.consume(entry)
                guard let text = Self.indexableText(from: entry) else { continue }
                try insertLine.reset()
                try insertLine.bind(1, (fileID << 32) | lineNumber)
                try insertLine.bind(2, text)
                try insertLine.step()
            }

            let updateTitle = try db.prepare("UPDATE files SET title = ? WHERE id = ?")
            if let title = accumulator.best {
                try updateTitle.bind(1, title)
            } else {
                try updateTitle.bindNull(1)
            }
            try updateTitle.bind(2, fileID)
            try updateTitle.step()

            try db.exec("COMMIT")
        } catch {
            try? db.exec("ROLLBACK")
            throw error
        }
    }

    private func deleteLines(fileID: Int64) throws {
        let delete = try db.prepare("DELETE FROM lines WHERE rowid >= ? AND rowid < ?")
        try delete.bind(1, fileID << 32)
        try delete.bind(2, (fileID + 1) << 32)
        try delete.step()
    }

    private func remove(fileID: Int64) throws {
        try db.exec("BEGIN IMMEDIATE")
        do {
            try deleteLines(fileID: fileID)
            let delete = try db.prepare("DELETE FROM files WHERE id = ?")
            try delete.bind(1, fileID)
            try delete.step()
            try db.exec("COMMIT")
        } catch {
            try? db.exec("ROLLBACK")
            throw error
        }
    }

    /// Human-relevant text only: non-sidechain prompts (compaction summaries
    /// count — they summarize the session), non-sidechain assistant text,
    /// titles, legacy summaries. Tool results, sidechain traffic, and
    /// bookkeeping lines are never indexed.
    static func indexableText(from entry: TranscriptEntry) -> String? {
        func nonEmpty(_ text: String) -> String? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        switch entry {
        case .userPrompt(let text, let context, _):
            guard !context.isSidechain, !context.isMeta else { return nil }
            return nonEmpty(text)
        case .event(.assistant(let message), let context):
            guard !context.isSidechain else { return nil }
            let text = message.content
                .compactMap { block -> String? in
                    if case .text(let blockText) = block { return blockText }
                    return nil
                }
                .joined(separator: "\n")
            return nonEmpty(text)
        case .title(let text, _, _), .summary(let text, _):
            return nonEmpty(text)
        default:
            return nil
        }
    }

    // MARK: test hooks (internal)

    func indexedFileCount() throws -> Int {
        let statement = try db.prepare("SELECT COUNT(*) FROM files")
        _ = try statement.step()
        return Int(statement.columnInt64(0))
    }

    func indexedLineCount() throws -> Int {
        let statement = try db.prepare("SELECT COUNT(*) FROM lines")
        _ = try statement.step()
        return Int(statement.columnInt64(0))
    }

    func indexedTitle(forSessionID sessionID: String) throws -> String? {
        let statement = try db.prepare("SELECT title FROM files WHERE session_id = ?")
        try statement.bind(1, sessionID)
        guard try statement.step() else { return nil }
        return statement.columnIsNull(0) ? nil : statement.columnText(0)
    }
}
