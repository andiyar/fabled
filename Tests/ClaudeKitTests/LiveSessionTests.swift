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
                    await session.respond(to: perm, decision: .allowAsRequested)
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

    /// Regression for the 2026-07-09 probe finding: a plain approval must
    /// actually run the tool (no ZodError denial).
    func testLiveAllowAsRequestedRunsTool() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CLAUDEKIT_LIVE"] == "1",
                          "live test — set CLAUDEKIT_LIVE=1 to run")
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        var config = SessionConfiguration(workingDirectory: scratch)
        config.model = "haiku"
        config.extraArguments = ["--setting-sources", ""]

        let session = AgentSession(configuration: config)
        try await session.start()
        await session.send("Run exactly this bash command: git init")

        var denials: [JSONValue] = []
        for await event in await session.events {
            switch event {
            case .controlRequest(let request):
                if let permission = PermissionRequest(request) {
                    await session.respond(to: permission, decision: .allowAsRequested)
                }
            case .result(let turn):
                denials = turn.permissionDenials
                await session.terminate()
            case .terminated:
                break
            default:
                break
            }
        }
        XCTAssertTrue(denials.isEmpty, "allowAsRequested must not be denied: \(denials)")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: scratch.appendingPathComponent(".git").path),
            "the allowed tool must actually have run")
    }

    func testLiveStreamDeltasArrive() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CLAUDEKIT_LIVE"] == "1",
                          "live test — set CLAUDEKIT_LIVE=1 to run")
        var config = SessionConfiguration(
            workingDirectory: FileManager.default.temporaryDirectory)
        config.model = "haiku"
        config.extraArguments = ["--setting-sources", ""]
        let session = AgentSession(configuration: config)
        try await session.start()
        await session.send("Reply with one short sentence about rivers.")

        var sawTextDelta = false
        for await event in await session.events {
            switch event {
            case .streamEvent(let stream):
                if case .textDelta = stream.kind { sawTextDelta = true }
            case .result:
                await session.terminate()
            default:
                break
            }
        }
        XCTAssertTrue(sawTextDelta, "partial messages must produce text deltas")
    }
}
