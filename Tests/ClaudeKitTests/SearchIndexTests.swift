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
}
