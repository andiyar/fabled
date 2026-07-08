import XCTest
@testable import ClaudeKit

/// Collects change batches from an AsyncStream on a background task.
private actor BatchCollector {
    private(set) var batches: [[URL]] = []
    func append(_ batch: [URL]) { batches.append(batch) }
    var allURLs: Set<URL> { Set(batches.flatMap { $0 }) }
}

final class SessionWatcherTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudekit-watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("-watched-project"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var projectDir: URL { root.appendingPathComponent("-watched-project") }

    private func waitUntil(
        timeout: Duration = .seconds(10),
        _ condition: @escaping () async -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let start = clock.now
        while clock.now - start < timeout {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return await condition()
    }

    private func makeStore() -> SessionStore {
        SessionStore(projectsRoot: root, pollInterval: .milliseconds(100))
    }

    func testNewFileAppendAndDeleteAreReported() async throws {
        let store = makeStore()
        let collector = BatchCollector()
        let stream = await store.changes
        let consumer = Task {
            for await batch in stream { await collector.append(batch) }
        }
        defer { consumer.cancel() }

        // 1. New session file appears.
        let sessionURL = projectDir.appendingPathComponent("live-session.jsonl")
        try Data("{\"type\":\"mode\",\"mode\":\"normal\"}\n".utf8).write(to: sessionURL)
        let sawCreate = await waitUntil {
            await collector.allURLs.contains { $0.lastPathComponent == "live-session.jsonl" }
        }
        XCTAssertTrue(sawCreate, "creation not reported")

        // 2. Append to the existing file (only the poll can see this).
        let baseline = await collector.batches.count
        let handle = try FileHandle(forWritingTo: sessionURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"type\":\"mode\",\"mode\":\"plan\"}\n".utf8))
        try handle.close()
        let sawAppend = await waitUntil {
            let batches = await collector.batches
            return batches.count > baseline
                && batches.suffix(from: baseline)
                    .flatMap { $0 }
                    .contains { $0.lastPathComponent == "live-session.jsonl" }
        }
        XCTAssertTrue(sawAppend, "append not reported")

        // 3. Deletion.
        let baseline2 = await collector.batches.count
        try FileManager.default.removeItem(at: sessionURL)
        let sawDelete = await waitUntil {
            let batches = await collector.batches
            return batches.count > baseline2
                && batches.suffix(from: baseline2)
                    .flatMap { $0 }
                    .contains { $0.lastPathComponent == "live-session.jsonl" }
        }
        XCTAssertTrue(sawDelete, "deletion not reported")
    }

    func testNewProjectDirectoryIsWatched() async throws {
        let store = makeStore()
        let collector = BatchCollector()
        let stream = await store.changes
        let consumer = Task {
            for await batch in stream { await collector.append(batch) }
        }
        defer { consumer.cancel() }

        let newProject = root.appendingPathComponent("-brand-new-project")
        try FileManager.default.createDirectory(at: newProject, withIntermediateDirectories: true)
        try Data("{\"type\":\"mode\",\"mode\":\"normal\"}\n".utf8)
            .write(to: newProject.appendingPathComponent("fresh.jsonl"))
        let seen = await waitUntil {
            await collector.allURLs.contains { $0.lastPathComponent == "fresh.jsonl" }
        }
        XCTAssertTrue(seen, "session in new project dir not reported")
    }

    func testNonSessionClutterIsIgnored() async throws {
        let store = makeStore()
        let collector = BatchCollector()
        let stream = await store.changes
        let consumer = Task {
            for await batch in stream { await collector.append(batch) }
        }
        defer { consumer.cancel() }

        try Data("{}".utf8).write(to: projectDir.appendingPathComponent("sessions-index.json"))
        try FileManager.default.createDirectory(
            at: projectDir.appendingPathComponent("memory"), withIntermediateDirectories: true)
        // Give the watcher ample time to (wrongly) report something.
        try await Task.sleep(for: .seconds(1))
        let urls = await collector.allURLs
        XCTAssertTrue(urls.isEmpty, "clutter must not produce change events, got \(urls)")
    }

    func testSubscribersAreReleasedOnCancel() async throws {
        let store = makeStore()
        let streamA = await store.changes
        let streamB = await store.changes
        let consumerA = Task { for await _ in streamA {} }
        let consumerB = Task { for await _ in streamB {} }
        let subscribed = await waitUntil { await store.subscriberCount == 2 }
        XCTAssertTrue(subscribed)

        consumerA.cancel()
        consumerB.cancel()
        let released = await waitUntil { await store.subscriberCount == 0 }
        XCTAssertTrue(released, "cancelled consumers must unsubscribe")
    }

    /// Pins the dealloc path: dropping the store's last owner while a
    /// subscriber is still consuming must deallocate the store (watcher
    /// tasks hold it weakly) and finish the subscriber's stream, rather
    /// than leaving a zombie poll loop spinning forever.
    func testStoreDeallocationFinishesStreamsAndKillsWatcherTasks() async throws {
        let collector = BatchCollector()
        weak var weakStore: SessionStore?
        let stream: AsyncStream<[URL]>
        do {
            let store = makeStore()
            weakStore = store
            stream = await store.changes
        }
        // Last strong reference is gone; watcher tasks must not resurrect it.
        let consumer = Task {
            for await batch in stream { await collector.append(batch) }
            await collector.append([])  // sentinel: stream finished
        }
        defer { consumer.cancel() }

        let deallocated = await waitUntil { weakStore == nil }
        XCTAssertTrue(deallocated, "watcher tasks must not keep the store alive")
        let finished = await waitUntil {
            await collector.batches.last?.isEmpty == true
        }
        XCTAssertTrue(finished, "stream must finish when the store is deallocated")
    }
}
