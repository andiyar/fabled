import XCTest
import ClaudeKit
@testable import FabledCore

@MainActor
final class AppModelTests: XCTestCase {
    private func makeModel(pollInterval: Duration = .seconds(2),
                           defaults: UserDefaults = .standard) throws -> (AppModel, URL) {
        let root = try CorpusBuilder.make()
        let store = SessionStore(projectsRoot: root, pollInterval: pollInterval)
        let db = FileManager.default.temporaryDirectory
            .appendingPathComponent("index-\(UUID().uuidString).sqlite")
        let model = try AppModel(store: store, databaseURL: db, defaults: defaults)
        return (model, root)
    }

    func testBootstrapPopulatesGroupedHistory() async throws {
        let (model, _) = try makeModel()
        await model.bootstrap()
        XCTAssertEqual(model.history.count, 1, "one project group")
        let sessions = model.history[0].sessions
        XCTAssertEqual(sessions.count, 3)
        XCTAssertEqual(sessions.map(\.id).first, "21feb0f8-e41a-4f72-9efb-9232b5bb64de",
                       "newest first")
        // Index titles are authoritative and flow through history. The titled
        // fixture carries a custom title; the "untitled" fixture has no
        // custom/AI/summary title, so the title-source chain
        // (custom > AI > summary > first prompt > id) falls back to its first
        // user prompt — distinct from both a real title and its id.
        let titled = sessions.first { $0.id == "97c70bda-ac5d-4e12-982e-8e6e35dd2674" }!
        XCTAssertEqual(titled.title, "Metal renderer planning review")
        XCTAssertNotEqual(titled.title, titled.id)
        let untitled = sessions.first { $0.id == "036b246d-0898-4ace-89b2-8fdd6c107fc4" }!
        XCTAssertEqual(untitled.title, "Reply with exactly: pong")
        XCTAssertNotEqual(untitled.title, untitled.id)
    }

    func testSearchDebouncedAndScoped() async throws {
        let (model, _) = try makeModel()
        await model.bootstrap()
        model.searchQuery = "pong"
        await waitUntil("search hits") { !model.searchHits.isEmpty }
        XCTAssertTrue(model.searchHits.contains {
            $0.session.id == "036b246d-0898-4ace-89b2-8fdd6c107fc4"
        }, "the pong session must match")
        model.searchQuery = ""
        await waitUntil("hits cleared") { model.searchHits.isEmpty }
    }

    func testWatcherRefreshesHistory() async throws {
        let (model, root) = try makeModel(pollInterval: .milliseconds(50))
        await model.bootstrap()
        XCTAssertEqual(model.history.first?.sessions.count, 3)

        // A new session file appears on disk (as if a CLI ran elsewhere).
        let project = root.appendingPathComponent("-tmp-fabled-demo")
        try FileManager.default.copyItem(
            at: CoreFixtures.fixturesDir
                .appendingPathComponent("transcripts/real-titled-session.jsonl"),
            to: project.appendingPathComponent("aaaaaaaa-0000-0000-0000-000000000001.jsonl"))

        await waitUntil(timeout: .seconds(10), "watcher-driven refresh") {
            model.history.first?.sessions.count == 4
        }
    }

    func testDoubleBootstrapIsHarmless() async throws {
        // A second window's RootView calls bootstrap() on the shared model;
        // it must be a no-op (no second changes subscriber, no double reindex).
        let (model, root) = try makeModel(pollInterval: .milliseconds(50))
        await model.bootstrap()
        await model.bootstrap()
        XCTAssertEqual(model.history.first?.sessions.count, 3)

        let project = root.appendingPathComponent("-tmp-fabled-demo")
        try FileManager.default.copyItem(
            at: CoreFixtures.fixturesDir
                .appendingPathComponent("transcripts/real-titled-session.jsonl"),
            to: project.appendingPathComponent("bbbbbbbb-0000-0000-0000-000000000002.jsonl"))

        await waitUntil(timeout: .seconds(10), "watcher-driven refresh after double bootstrap") {
            model.history.first?.sessions.count == 4
        }
        XCTAssertEqual(model.history.first?.sessions.count, 4)
    }

    func testHistoricalTimeline() async throws {
        let (model, _) = try makeModel()
        await model.bootstrap()
        let summary = model.summary(forSessionID: "97c70bda-ac5d-4e12-982e-8e6e35dd2674")!
        let items = await model.historicalTimeline(for: summary)
        XCTAssertEqual(items.count, 2, "1 user prompt + 1 assistant text (Task 6 census)")
    }

    func testProjectDisplayName() {
        XCTAssertEqual(ProjectFolder(
            flattenedName: "-Users-x-Developer-Wine",
            originalPath: "/Users/x/Developer/Wine",
            directoryURL: URL(fileURLWithPath: "/tmp")).displayName, "Wine")
        XCTAssertEqual(ProjectFolder(
            flattenedName: "-gibberish--x",
            originalPath: "-gibberish--x",
            directoryURL: URL(fileURLWithPath: "/tmp")).displayName, "-gibberish--x",
            "unresolvable paths show the flattened name")
    }

    func testSidebarOptionsPersistAcrossModels() throws {
        let suite = "4b-t8-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let (first, _) = try makeModel(defaults: defaults)
        first.sidebarOptions.groupBy = .date
        first.sidebarOptions.pinnedSessionIDs.insert("s-1")
        let (second, _) = try makeModel(defaults: defaults)
        XCTAssertEqual(second.sidebarOptions.groupBy, .date)
        XCTAssertTrue(second.sidebarOptions.pinnedSessionIDs.contains("s-1"))
    }

    func testWelcomeRecentsExcludeLiveResumedSessions() async throws {
        let (model, _) = try makeModel()
        await model.bootstrap()
        let recents = model.welcomeRecents(limit: 5)
        XCTAssertFalse(recents.isEmpty)
        XCTAssertEqual(recents.map(\.id),
                       recents.sorted { $0.lastActivity > $1.lastActivity }.map(\.id),
                       "newest first, across projects")
        // Hardening: a live session resuming one of these ids must drop it from
        // the recents (it renders in the live sections above instead).
        let resumedID = recents[0].id
        let (connection, _, _) = makeFakeConnection()
        let live = ChatSession(
            connection: connection,
            workingDirectory: URL(fileURLWithPath: "/tmp/demo"),
            resumedSessionID: resumedID)
        model.adoptForTesting(live)
        XCTAssertFalse(model.welcomeRecents(limit: 10).contains { $0.id == resumedID },
                       "a live resumed session is excluded from welcome recents")
    }

    func testRecentProjectsAreOrderedAndDeduped() async throws {
        let (model, _) = try makeModel()
        await model.bootstrap()
        let projects = model.recentProjects(limit: 10)
        XCTAssertFalse(projects.isEmpty)
        XCTAssertEqual(Set(projects.map(\.id)).count, projects.count, "no duplicates")
        // recentProjects mirrors history order (history.map(\.project) prefixed).
        XCTAssertEqual(projects.map(\.id),
                       Array(model.history.map(\.project.id).prefix(10)),
                       "recentProjects mirrors history order")
        // This corpus is a single project group, so the dedup concern is moot
        // here; the ordering contract above still holds if the corpus grows.
        XCTAssertEqual(projects.count, 1)
    }

    @MainActor
    func testResumeCollisionSelectsExistingLiveSession() async throws {
        let (model, _) = try makeModel()
        let (connection, _, _) = makeFakeConnection()
        let live = ChatSession(
            connection: connection,
            workingDirectory: URL(fileURLWithPath: "/tmp/demo"),
            resumedSessionID: "abc-123")
        model.adoptForTesting(live)
        let summary = SessionSummary(
            id: "abc-123",
            project: ProjectFolder(flattenedName: "-tmp-demo",
                                   originalPath: "/tmp/demo",
                                   directoryURL: URL(fileURLWithPath: "/tmp/demo")),
            fileURL: URL(fileURLWithPath: "/tmp/demo/abc-123.jsonl"),
            title: "t", lastActivity: .now, approximateSizeBytes: 1)
        await model.resume(summary, fork: false)
        XCTAssertEqual(model.liveSessions.count, 1, "no duplicate spawn")
        XCTAssertEqual(model.selection, .live(live.id))
    }

    @MainActor
    func testFallbackDirectoryIsFlagged() throws {
        let (model, _) = try makeModel()
        let gone = SessionSummary(
            id: "x",
            project: ProjectFolder(flattenedName: "-gone-project",
                                   originalPath: "-gone-project",   // unresolvable
                                   directoryURL: URL(fileURLWithPath: "/nope")),
            fileURL: URL(fileURLWithPath: "/nope/x.jsonl"),
            title: "t", lastActivity: .now, approximateSizeBytes: 1)
        let resolved = model.resolveWorkingDirectory(for: gone)
        XCTAssertTrue(resolved.didFallBack)
        XCTAssertEqual(resolved.url,
                       FileManager.default.homeDirectoryForCurrentUser)

        // Absolute but deleted: passes hasPrefix("/") and must be caught by
        // the fileExists check (the T12 widening) — falls back too.
        let deletedPath = "/nonexistent-\(UUID().uuidString)"
        let deleted = SessionSummary(
            id: "y",
            project: ProjectFolder(flattenedName: "-deleted-project",
                                   originalPath: deletedPath,
                                   directoryURL: URL(fileURLWithPath: deletedPath)),
            fileURL: URL(fileURLWithPath: "\(deletedPath)/y.jsonl"),
            title: "t", lastActivity: .now, approximateSizeBytes: 1)
        let resolvedDeleted = model.resolveWorkingDirectory(for: deleted)
        XCTAssertTrue(resolvedDeleted.didFallBack)
        XCTAssertEqual(resolvedDeleted.url,
                       FileManager.default.homeDirectoryForCurrentUser)
    }
}
