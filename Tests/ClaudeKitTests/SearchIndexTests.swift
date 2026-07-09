import XCTest
@testable import ClaudeKit

final class SearchIndexTests: XCTestCase {
    private var root: URL!
    private var databaseURL: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudekit-index-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("-test-project"), withIntermediateDirectories: true)
        databaseURL = root.appendingPathComponent("index.sqlite")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var projectDir: URL { root.appendingPathComponent("-test-project") }

    /// Two indexable lines: one prompt, one assistant reply.
    private let quokkaSession = """
    {"isSidechain":false,"type":"user","message":{"role":"user","content":"quokka feeding schedule please"}}
    {"isSidechain":false,"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"quokkas eat leaves at dawn"}]}}
    {"type":"mode","mode":"normal","sessionId":"s"}
    """

    private func writeQuokkaSession(id: String = "quokka") throws -> URL {
        let url = projectDir.appendingPathComponent("\(id).jsonl")
        try Data((quokkaSession + "\n").utf8).write(to: url)
        return url
    }

    private func makeStoreAndIndex() throws -> (SessionStore, SearchIndex) {
        let store = SessionStore(projectsRoot: root)
        let index = try SearchIndex(databaseURL: databaseURL, store: store)
        return (store, index)
    }

    func testColdIndexCountsFilesAndLines() async throws {
        // synthetic-edge-cases has exactly 7 indexable lines (3 usable-for-
        // index prompts incl. the compact summary, 1 assistant, 2 titles,
        // 1 legacy summary); the quokka session has 2.
        try Fixtures.transcriptData("synthetic-edge-cases.jsonl")
            .write(to: projectDir.appendingPathComponent("synthetic.jsonl"))
        try writeQuokkaSession()
        let (_, index) = try makeStoreAndIndex()

        let reindexed = try await index.reindex()
        XCTAssertEqual(reindexed, 2)
        let fileCount = try await index.indexedFileCount()
        let lineCount = try await index.indexedLineCount()
        XCTAssertEqual(fileCount, 2)
        XCTAssertEqual(lineCount, 9)
        let title = try await index.indexedTitle(forSessionID: "synthetic")
        XCTAssertEqual(title, "Synthetic custom title")
    }

    func testReindexSkipsUnchangedFiles() async throws {
        try writeQuokkaSession()
        let (_, index) = try makeStoreAndIndex()
        let first = try await index.reindex()
        XCTAssertEqual(first, 1)
        let second = try await index.reindex()
        XCTAssertEqual(second, 0, "unchanged file must be skipped")
        let lineCount = try await index.indexedLineCount()
        XCTAssertEqual(lineCount, 2)
    }

    func testChangedFileIsReindexedNotDuplicated() async throws {
        let url = try writeQuokkaSession()
        let (_, index) = try makeStoreAndIndex()
        _ = try await index.reindex()

        let extra = #"{"isSidechain":false,"type":"user","message":{"role":"user","content":"also a wombat question"}}"#
        try Data((quokkaSession + "\n" + extra + "\n").utf8).write(to: url)
        // Force a clearly different mtime in case the two writes land within
        // filesystem timestamp resolution.
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: url.path)

        let reindexed = try await index.reindex()
        XCTAssertEqual(reindexed, 1)
        let fileCount = try await index.indexedFileCount()
        let lineCount = try await index.indexedLineCount()
        XCTAssertEqual(fileCount, 1)
        XCTAssertEqual(lineCount, 3, "old rows must be replaced, not accumulated")
    }

    func testDeletedFileIsRemovedFromIndex() async throws {
        let keep = try writeQuokkaSession(id: "keep")
        let drop = try writeQuokkaSession(id: "drop")
        let (_, index) = try makeStoreAndIndex()
        _ = try await index.reindex()
        let fileCount = try await index.indexedFileCount()
        let lineCount = try await index.indexedLineCount()
        XCTAssertEqual(fileCount, 2)
        XCTAssertEqual(lineCount, 4)

        try FileManager.default.removeItem(at: drop)
        let reindexed = try await index.reindex()
        XCTAssertEqual(reindexed, 0)
        let fileCount2 = try await index.indexedFileCount()
        let lineCount2 = try await index.indexedLineCount()
        XCTAssertEqual(fileCount2, 1)
        XCTAssertEqual(lineCount2, 2)
        _ = keep
    }

    func testNewProjectDirectoryIsPickedUp() async throws {
        let (_, index) = try makeStoreAndIndex()
        let initial = try await index.reindex()
        XCTAssertEqual(initial, 0)
        let newProject = root.appendingPathComponent("-late-project")
        try FileManager.default.createDirectory(at: newProject, withIntermediateDirectories: true)
        try Data((quokkaSession + "\n").utf8)
            .write(to: newProject.appendingPathComponent("late.jsonl"))
        let reindexed = try await index.reindex()
        XCTAssertEqual(reindexed, 1)
        let fileCount = try await index.indexedFileCount()
        XCTAssertEqual(fileCount, 1)
    }

    func testSidechainAndMetaLinesAreNotIndexed() async throws {
        let noise = """
        {"isSidechain":true,"type":"user","message":{"role":"user","content":"sidechain capybara"}}
        {"isSidechain":true,"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"sidechain reply capybara"}]}}
        {"isSidechain":false,"isMeta":true,"type":"user","message":{"role":"user","content":"meta capybara"}}
        """
        try Data((noise + "\n").utf8).write(to: projectDir.appendingPathComponent("noise.jsonl"))
        let (_, index) = try makeStoreAndIndex()
        _ = try await index.reindex()
        let lineCount = try await index.indexedLineCount()
        XCTAssertEqual(lineCount, 0)
    }

    // MARK: search (Task 9)

    func testSearchFindsPromptAndAssistantLines() async throws {
        try Fixtures.transcriptData("synthetic-edge-cases.jsonl")
            .write(to: projectDir.appendingPathComponent("synthetic.jsonl"))
        let (_, index) = try makeStoreAndIndex()
        _ = try await index.reindex()

        // "wombats" appears on line 6 (prompt) and line 9 (assistant reply).
        let hits = try await index.search("wombats", limit: 10)
        XCTAssertEqual(hits.count, 2)
        XCTAssertEqual(Set(hits.map(\.lineNumber)), [6, 9])
        for hit in hits {
            XCTAssertTrue(hit.snippet.contains("[wombats]"), "snippet: \(hit.snippet)")
            XCTAssertEqual(hit.session.id, "synthetic")
            XCTAssertEqual(hit.session.title, "Synthetic custom title")
            XCTAssertEqual(hit.session.project.flattenedName, "-test-project")
            XCTAssertEqual(hit.session.fileURL.lastPathComponent, "synthetic.jsonl")
            XCTAssertEqual(hit.id, "synthetic:\(hit.lineNumber)")
        }
    }

    func testSearchPrefixMatchesLastToken() async throws {
        try writeQuokkaSession()
        let (_, index) = try makeStoreAndIndex()
        _ = try await index.reindex()
        let hits = try await index.search("quok", limit: 10)
        XCTAssertEqual(hits.count, 2, "prefix star on the final token")
    }

    func testSearchMultiTokenIsImplicitAnd() async throws {
        try writeQuokkaSession()
        let (_, index) = try makeStoreAndIndex()
        _ = try await index.reindex()
        let both = try await index.search("feeding quokka", limit: 10)
        XCTAssertEqual(both.count, 1)
        let none = try await index.search("feeding nonexistentword", limit: 10)
        XCTAssertEqual(none.count, 0)
    }

    func testSearchRespectsLimit() async throws {
        try writeQuokkaSession()
        let (_, index) = try makeStoreAndIndex()
        _ = try await index.reindex()
        let hits = try await index.search("quokka", limit: 1)
        XCTAssertEqual(hits.count, 1)
    }

    func testHostileQueriesDoNotThrow() async throws {
        try writeQuokkaSession()
        let (_, index) = try makeStoreAndIndex()
        _ = try await index.reindex()
        for query in ["\"unbalanced AND (", "NOT", "a* b* OR", "\"\"\"", "   "] {
            _ = try await index.search(query, limit: 10) // must not throw
        }
        let empty = try await index.search("", limit: 10)
        XCTAssertEqual(empty.count, 0)
    }

    func testFTSQuerySanitizer() {
        XCTAssertEqual(SearchIndex.ftsQuery(from: "hello world"), "\"hello\" \"world\"*")
        XCTAssertEqual(SearchIndex.ftsQuery(from: "one"), "\"one\"*")
        XCTAssertEqual(SearchIndex.ftsQuery(from: "  spaced   out  "), "\"spaced\" \"out\"*")
        XCTAssertEqual(SearchIndex.ftsQuery(from: #"say "hi""#), #""say" ""hi""*"#)
        XCTAssertEqual(SearchIndex.ftsQuery(from: ""), "")
    }

    // MARK: reindex hardening + sidebar summaries

    /// A three-file corpus, nothing indexed yet: one titled real session, one
    /// session whose whole-file title is genuinely null (a lone sidechain line
    /// — no custom/ai title, no legacy summary, no usable first prompt), and
    /// the quokka session (titled by its first prompt). The fixture stems are
    /// this corpus's answer to the plan's real-project UUIDs.
    private func makePopulatedStoreAndIndex() throws -> (SessionStore, SearchIndex) {
        try Fixtures.transcriptData("real-titled-session.jsonl")
            .write(to: projectDir.appendingPathComponent("real-titled-session.jsonl"))
        try Data(("{\"isSidechain\":true,\"type\":\"user\","
            + "\"message\":{\"role\":\"user\",\"content\":\"sidechain noise\"}}\n").utf8)
            .write(to: projectDir.appendingPathComponent("untitled-null.jsonl"))
        _ = try writeQuokkaSession()
        return try makeStoreAndIndex()
    }

    func testConcurrentReindexPassesSerialize() async throws {
        let (_, index) = try makePopulatedStoreAndIndex()
        // Before the fix: two passes race the files-table snapshot, both see a
        // new file as absent, and the second INSERT dies on UNIQUE(path).
        try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<8 { group.addTask { try await index.reindex() } }
            for try await _ in group {}   // no pass may throw
        }
        let fileCount = try await index.indexedFileCount()
        XCTAssertEqual(fileCount, 3, "every session indexed exactly once")
    }

    func testVanishedFileIsSkippedNotFatal() async throws {
        let (store, index) = try makePopulatedStoreAndIndex()
        _ = try await index.reindex()

        // Make one file unreadable — the enumeration still stamps it, the
        // read fails, exactly like a file deleted between stat and open.
        let project = try await store.projects()[0]
        let stamps = try await store.sessionFileStamps(in: project)
        let victim = stamps[0].url
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000], ofItemAtPath: victim.path)
        defer { try? FileManager.default.setAttributes(
            [.posixPermissions: 0o644], ofItemAtPath: victim.path) }
        // Touch its mtime so the incremental check re-reads it.
        try FileManager.default.setAttributes(
            [.modificationDate: Date()], ofItemAtPath: victim.path)

        // Before the fix this throws out of reindex() and skips everything
        // after the victim; after, it skips only the victim.
        let reindexed = try await index.reindex()
        XCTAssertEqual(reindexed, 0, "unreadable file must be skipped, not counted")
        let fileCount = try await index.indexedFileCount()
        XCTAssertEqual(fileCount, 3, "existing rows for the victim survive")
    }

    func testSessionSummariesComeFromIndexRows() async throws {
        let (_, index) = try makePopulatedStoreAndIndex()
        _ = try await index.reindex()
        let summaries = try await index.sessionSummaries()
        XCTAssertEqual(summaries.count, 3)
        // Newest first.
        let dates = summaries.map(\.lastActivity)
        XCTAssertEqual(dates, dates.sorted(by: >))
        // Titles are the index's whole-file titles (authoritative source).
        let titled = summaries.first { $0.id == "real-titled-session" }
        XCTAssertNotNil(titled)
        let indexTitle = try await index.indexedTitle(forSessionID: titled!.id)
        XCTAssertEqual(titled?.title, indexTitle)
        // Untitled sessions fall back to the session id.
        let untitled = summaries.first { $0.id == "untitled-null" }
        XCTAssertEqual(untitled?.title, untitled?.id)
    }
}
