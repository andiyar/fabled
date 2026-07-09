import XCTest
import ClaudeKit
@testable import FabledCore

/// End-to-end against the real CLI: the exact pipeline the app binds
/// (spawn → decoder → AsyncStream → MainActor fold → reducer → timeline),
/// everything short of SwiftUI rendering. This is the dead-stream
/// regression from the 2.1.205 update: a fresh session emits nothing
/// until the first user turn, and the timeline must populate as soon as
/// one is sent. Env-gated and on haiku, like LiveSessionTests.
@MainActor
final class ChatSessionLiveTests: XCTestCase {
    func testLiveTimelinePopulatesAfterFirstMessage() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CLAUDEKIT_LIVE"] == "1",
                          "live test: set CLAUDEKIT_LIVE=1 to run")
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fabled-live-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        var config = SessionConfiguration(workingDirectory: dir)
        config.model = "haiku"
        config.extraArguments = ["--setting-sources", ""]
        let session = try await ChatSession.launch(configuration: config)
        defer { session.terminate() }

        // The initialize ack arrives at spawn; `system init` does not
        // (2.1.205 defers it) — the session must read as ready, not dead.
        await waitUntil(timeout: .seconds(15), "initialize ack") { session.isReady }
        XCTAssertTrue(session.isAwaitingFirstMessage)
        XCTAssertFalse(session.hasEnded)
        XCTAssertNotNil(session.currentModel, "picker must not sit blank pre-turn")

        session.send("Reply with exactly: FABLED-LIVE-OK")
        await waitUntil(timeout: .seconds(90), "assistant reply in timeline") {
            session.timeline.contains { item in
                if case .assistantText(_, let markdown, _) = item {
                    return markdown.contains("FABLED-LIVE-OK")
                }
                return false
            }
        }
        await waitUntil(timeout: .seconds(30), "turn completes") { !session.isWorking }
        XCTAssertNotNil(session.info, "init arrives with the first turn")
    }
}
