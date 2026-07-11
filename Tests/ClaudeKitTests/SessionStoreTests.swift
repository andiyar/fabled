import XCTest
@testable import ClaudeKit

final class SessionStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudekit-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeProject(_ name: String) throws -> URL {
        let dir = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    private func writeSession(
        _ project: URL, id: String, contents: String, modified: Date? = nil
    ) throws -> URL {
        let url = project.appendingPathComponent("\(id).jsonl")
        try Data(contents.utf8).write(to: url)
        if let modified {
            try FileManager.default.setAttributes(
                [.modificationDate: modified], ofItemAtPath: url.path)
        }
        return url
    }

    private let promptLine = #"{"isSidechain":false,"type":"user","message":{"role":"user","content":"hello from the test corpus"}}"#

    func testProjectsSkipsNonDirectoriesAndSorts() async throws {
        _ = try makeProject("-zeta-project")
        _ = try makeProject("-alpha-project")
        try Data("stray".utf8).write(to: root.appendingPathComponent("stray-file.txt"))
        let store = SessionStore(projectsRoot: root)
        let projects = try await store.projects()
        XCTAssertEqual(projects.map(\.flattenedName), ["-alpha-project", "-zeta-project"])
        // Unresolvable names fall back to the flattened form.
        XCTAssertEqual(projects[0].originalPath, "-alpha-project")
    }

    func testProjectsOnMissingRootReturnsEmpty() async throws {
        let store = SessionStore(projectsRoot: root.appendingPathComponent("does-not-exist"))
        let projects = try await store.projects()
        XCTAssertEqual(projects.count, 0)
    }

    func testSessionsSkipsClutterAndSortsByRecency() async throws {
        let project = try makeProject("-alpha-project")
        // Clutter that must be skipped: memory/, sessions-index.json,
        // a bare-UUID directory, a directory named like a session file.
        try FileManager.default.createDirectory(
            at: project.appendingPathComponent("memory"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: project.appendingPathComponent("sessions-index.json"))
        try FileManager.default.createDirectory(
            at: project.appendingPathComponent("0e0e0e0e-1111-2222-3333-444444444444"),
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: project.appendingPathComponent("fake-dir.jsonl"), withIntermediateDirectories: true)

        try writeSession(project, id: "older", contents: promptLine + "\n",
                         modified: Date(timeIntervalSince1970: 1_000_000))
        try writeSession(project, id: "newer", contents: promptLine + "\n",
                         modified: Date(timeIntervalSince1970: 2_000_000))

        let store = SessionStore(projectsRoot: root)
        let project0 = try await store.projects()[0]
        let sessions = try await store.sessions(in: project0)
        XCTAssertEqual(sessions.map(\.id), ["newer", "older"])
        XCTAssertEqual(sessions[0].title, "hello from the test corpus")
        XCTAssertEqual(sessions[0].lastActivity, Date(timeIntervalSince1970: 2_000_000))
        XCTAssertEqual(sessions[0].approximateSizeBytes, promptLine.utf8.count + 1)
        XCTAssertEqual(sessions[0].project, project0)
        XCTAssertEqual(sessions[0].fileURL.lastPathComponent, "newer.jsonl")
    }

    func testTitleFallsBackToSessionID() async throws {
        let project = try makeProject("-alpha-project")
        try writeSession(project, id: "empty-session",
                         contents: #"{"type":"mode","mode":"normal","sessionId":"s"}"# + "\n")
        let store = SessionStore(projectsRoot: root)
        let sessions = try await store.sessions(in: try await store.projects()[0])
        XCTAssertEqual(sessions[0].title, "empty-session")
    }

    func testFixtureTitlesAndTranscriptCounts() async throws {
        let project = try makeProject("-fixture-project")
        for (id, fixture) in [("titled", "real-titled-session.jsonl"),
                              ("tooluse", "real-tooluse-session.jsonl"),
                              ("untitled", "real-untitled-session.jsonl"),
                              ("synthetic", "synthetic-edge-cases.jsonl")] {
            let data = try Fixtures.transcriptData(fixture)
            try data.write(to: project.appendingPathComponent("\(id).jsonl"))
        }
        let store = SessionStore(projectsRoot: root)
        let sessions = try await store.sessions(in: try await store.projects()[0])
        let byID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        XCTAssertEqual(byID["titled"]?.title, "Metal renderer planning review")
        XCTAssertEqual(byID["tooluse"]?.title, "Auto-updating bundles from GitHub")
        XCTAssertEqual(byID["untitled"]?.title, "Reply with exactly: pong")
        XCTAssertEqual(byID["synthetic"]?.title, "Synthetic custom title")

        let titledCount = try await store.transcript(for: XCTUnwrap(byID["titled"])).count
        let tooluseCount = try await store.transcript(for: XCTUnwrap(byID["tooluse"])).count
        let untitledCount = try await store.transcript(for: XCTUnwrap(byID["untitled"])).count
        let syntheticCount = try await store.transcript(for: XCTUnwrap(byID["synthetic"])).count
        XCTAssertEqual(titledCount, 28)
        XCTAssertEqual(tooluseCount, 141)
        XCTAssertEqual(untitledCount, 11)
        XCTAssertEqual(syntheticCount, 22)
    }

    func testTranscriptToleratesMalformedLines() async throws {
        let project = try makeProject("-alpha-project")
        let session = try writeSession(
            project, id: "broken",
            contents: promptLine + "\n" + "this line is not JSON {{{" + "\n")
        let store = SessionStore(projectsRoot: root)
        let sessions = try await store.sessions(in: try await store.projects()[0])
        let entries = try await store.transcript(for: sessions[0])
        XCTAssertEqual(entries.count, 2)
        guard case .userPrompt = entries[0] else { return XCTFail("expected prompt first") }
        guard case .unknown(let raw) = entries[1] else { return XCTFail("expected unknown second") }
        XCTAssertEqual(raw.stringValue, "this line is not JSON {{{")
        _ = session
    }

    func testEmptyProjectHasNoSessions() async throws {
        _ = try makeProject("-alpha-project")
        let store = SessionStore(projectsRoot: root)
        let sessions = try await store.sessions(in: try await store.projects()[0])
        XCTAssertEqual(sessions.count, 0)
    }

    // MARK: - Subagent transcripts (4b Task 14)

    /// Builds a project with one session file plus a nested subagent tree:
    /// `<project>/<id>/subagents/agent-abc.jsonl` (+ optional `.meta.json`).
    /// Returns the project directory so callers can enumerate it.
    @discardableResult
    private func makeSubagentTree(
        writeMeta: Bool
    ) throws -> URL {
        let project = try makeProject("-tmp-proj")
        try writeSession(
            project, id: "aaaa-1111",
            contents: #"{"type":"user","message":{"role":"user","content":"hi"},"sessionId":"aaaa-1111","uuid":"u1","timestamp":"2026-07-11T00:00:00Z"}"# + "\n")
        let subagents = project.appendingPathComponent("aaaa-1111/subagents")
        try FileManager.default.createDirectory(at: subagents, withIntermediateDirectories: true)
        try Data(#"{"type":"user","isSidechain":true,"agentId":"abc","message":{"role":"user","content":"task prompt"},"sessionId":"aaaa-1111","uuid":"u2","timestamp":"2026-07-11T00:00:01Z"}"#.utf8)
            .write(to: subagents.appendingPathComponent("agent-abc.jsonl"))
        if writeMeta {
            let meta = #"{"agentType":"general-purpose","description":"count files","toolUseId":"toolu_XYZ","spawnDepth":1}"#
            try Data(meta.utf8)
                .write(to: subagents.appendingPathComponent("agent-abc.meta.json"))
        }
        return project
    }

    func testSubagentFilesAreInvisibleToEnumeration() async throws {
        // Depth-2 invariant (4b finding 14): nested agent transcripts must
        // never surface as sessions. Guard-tested so a future enumeration
        // change can't silently pollute the sidebar.
        try makeSubagentTree(writeMeta: false)
        let store = SessionStore(projectsRoot: root)
        let project0 = try await store.projects()[0]
        let sessions = try await store.sessions(in: project0)
        XCTAssertEqual(sessions.map(\.id), ["aaaa-1111"],
                       "the nested agent file must not enumerate")
    }

    func testSubagentTimelinesReadByToolUseID() async throws {
        // Same tree as above, plus the meta.json linking file → Task card.
        try makeSubagentTree(writeMeta: true)
        let store = SessionStore(projectsRoot: root)
        let project0 = try await store.projects()[0]
        let summary = try await store.sessions(in: project0)[0]
        let timelines = try await store.subagentTranscripts(for: summary)
        XCTAssertEqual(Array(timelines.keys), ["toolu_XYZ"])
        XCTAssertFalse(timelines["toolu_XYZ"]!.isEmpty)
    }

    func testSubagentTranscriptsSkipMetalessFiles() async throws {
        // Tolerant-skip contract: a jsonl with no sibling meta.json has no
        // toolUseId key to route by — skipped silently, never a throw.
        try makeSubagentTree(writeMeta: false)
        let store = SessionStore(projectsRoot: root)
        let summary = try await store.sessions(in: try await store.projects()[0])[0]
        let timelines = try await store.subagentTranscripts(for: summary)
        XCTAssertTrue(timelines.isEmpty, "meta-less agent file must be skipped, not fatal")
    }
}
