import XCTest
@testable import ClaudeKit

/// Real-CLI tests. Run with: CLAUDEKIT_LIVE=1 swift test --filter LiveSessionTests
/// Uses haiku for cost; requires the user to be logged in to claude.
final class LiveSessionTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["CLAUDEKIT_LIVE"] == "1",
            "set CLAUDEKIT_LIVE=1 to run live CLI tests")
    }

    private func scratchDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudekit-live-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testLivePingPong() async throws {
        var config = SessionConfiguration(workingDirectory: try scratchDir())
        config.model = "haiku"
        config.extraArguments = ["--setting-sources", ""]

        let session = AgentSession(configuration: config)
        try await session.start()
        await session.send("Reply with exactly the word: pong")

        var sawInit = false
        var text = ""
        for await event in await session.events {
            switch event {
            case .systemInit(let info):
                sawInit = true
                XCTAssertFalse(info.sessionID.isEmpty)
            case .assistant(let msg):
                for case .text(let t) in msg.content { text += t }
            case .result:
                await session.terminate()
            default: break
            }
        }
        XCTAssertTrue(sawInit)
        XCTAssertTrue(text.lowercased().contains("pong"), "got: \(text)")
    }

    func testLivePermissionRoundTrip() async throws {
        var config = SessionConfiguration(workingDirectory: try scratchDir())
        config.model = "haiku"
        config.extraArguments = ["--setting-sources", ""]

        let session = AgentSession(configuration: config)
        try await session.start()
        await session.send("Run exactly this bash command: git init")

        var approved = false
        var toolSucceeded = false
        for await event in await session.events {
            switch event {
            case .controlRequest(let req):
                if let perm = PermissionRequest(req) {
                    approved = true
                    await session.respond(
                        to: perm, decision: .allow(updatedInput: perm.input))
                }
            case .toolResult(let results):
                if results.contains(where: { !$0.isError }) { toolSucceeded = true }
            case .result(let r):
                XCTAssertTrue(r.permissionDenials.isEmpty)
                await session.terminate()
            default: break
            }
        }
        XCTAssertTrue(approved, "expected a can_use_tool request for git init")
        XCTAssertTrue(toolSucceeded)
    }
}
