import XCTest
import ClaudeKit
@testable import FabledCore

@MainActor
final class AppModelTests: XCTestCase {
    private func makeModel(pollInterval: Duration = .seconds(2)) throws -> (AppModel, URL) {
        let root = try CorpusBuilder.make()
        let store = SessionStore(projectsRoot: root, pollInterval: pollInterval)
        let db = FileManager.default.temporaryDirectory
            .appendingPathComponent("index-\(UUID().uuidString).sqlite")
        let model = try AppModel(store: store, databaseURL: db)
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
}
