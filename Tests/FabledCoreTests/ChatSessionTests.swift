import XCTest
import ClaudeKit
@testable import FabledCore

@MainActor
final class ChatSessionTests: XCTestCase {
    private func makeSession()
        -> (ChatSession, AsyncStream<AgentEvent>.Continuation, OutboundRecorder) {
        let (connection, continuation, recorder) = makeFakeConnection()
        let session = ChatSession(
            connection: connection,
            workingDirectory: URL(fileURLWithPath: "/tmp/demo"))
        session.begin()
        return (session, continuation, recorder)
    }

    private func yield(_ continuation: AsyncStream<AgentEvent>.Continuation,
                       _ json: String) throws {
        continuation.yield(try AgentEventDecoder.decode(Data(json.utf8)))
    }

    func testInitCatalogHarvest() async throws {
        let (session, continuation, _) = makeSession()
        try yield(continuation, #"""
        {"type":"control_response","response":{"subtype":"success","request_id":"init","response":{"commands":[{"name":"compact","description":"Compact the conversation","argumentHint":""}],"models":[{"value":"default","resolvedModel":"claude-opus-4-8","displayName":"Default (recommended)","description":"Opus"},{"value":"haiku","displayName":"Haiku"}],"output_style":"default"}}}
        """#)
        await waitUntil("catalog") { !session.commands.isEmpty }
        XCTAssertEqual(session.commands.map(\.name), ["compact"])
        XCTAssertEqual(session.models.map(\.value), ["default", "haiku"])
        XCTAssertEqual(session.models[0].displayName, "Default (recommended)")
    }

    func testSystemInitPopulatesModelAndMode() async throws {
        let (session, continuation, _) = makeSession()
        try yield(continuation, #"""
        {"type":"system","subtype":"init","session_id":"s1","model":"claude-haiku-4-5-20251001","cwd":"/tmp/demo","permissionMode":"default","tools":[],"slash_commands":[],"agents":[],"skills":[],"claude_code_version":"2.1.204"}
        """#)
        await waitUntil("init") { session.info != nil }
        XCTAssertEqual(session.currentModel, "claude-haiku-4-5-20251001")
        XCTAssertEqual(session.permissionMode, "default")
        XCTAssertNil(session.versionNote, "tested version raises no banner")
    }

    func testVersionNoteOnDrift() async throws {
        let (session, continuation, _) = makeSession()
        try yield(continuation, #"""
        {"type":"system","subtype":"init","session_id":"s1","model":"m","cwd":"/","permissionMode":"default","tools":[],"slash_commands":[],"agents":[],"skills":[],"claude_code_version":"9.9.9"}
        """#)
        await waitUntil("init") { session.info != nil }
        XCTAssertNotNil(session.versionNote)
    }

    func testSendEchoesAndTracksTurns() async throws {
        let (session, continuation, recorder) = makeSession()
        session.send("  hello  ")
        XCTAssertTrue(session.isWorking)
        guard case .userMessage(_, "hello") = session.timeline.first else {
            return XCTFail("send must echo the trimmed prompt: \(session.timeline)")
        }
        let entries = await waitForEntries(recorder, count: 1)
        XCTAssertEqual(entries, [.send("hello")])

        // A queued second message keeps the session working through the
        // first result (probe finding 6).
        session.send("second")
        try yield(continuation, #"{"type":"result","subtype":"success","is_error":false,"total_cost_usd":0.01,"uuid":"r1"}"#)
        await waitUntil("first result") { session.cumulativeCostUSD > 0 }
        XCTAssertTrue(session.isWorking, "one of two turns still in flight")
        try yield(continuation, #"{"type":"result","subtype":"success","is_error":false,"total_cost_usd":0.02,"uuid":"r2"}"#)
        await waitUntil("second result") { !session.isWorking }
        XCTAssertEqual(session.cumulativeCostUSD, 0.03, accuracy: 0.0001)
    }

    func testPermissionFlow() async throws {
        let (session, continuation, recorder) = makeSession()
        try yield(continuation, #"""
        {"type":"control_request","request_id":"p1","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"git init"},"permission_suggestions":[]}}
        """#)
        await waitUntil("pending permission") { session.pendingPermission != nil }
        XCTAssertEqual(session.activityState, .needsApproval)
        let request = session.pendingPermission!

        session.respond(to: request, decision: .allowAsRequested)
        XCTAssertNil(session.pendingPermission)
        let entries = await waitForEntries(recorder, count: 1)
        XCTAssertEqual(entries, [.respond(requestID: "p1", behavior: "allow")])
        let permissionItem = session.timeline.first {
            if case .permission = $0 { return true } else { return false }
        }
        guard case .permission(_, _, let resolution) = permissionItem,
              resolution == .allowAsRequested else {
            return XCTFail("resolution must land in the timeline")
        }
    }

    func testAbortedTurnClearsPendingPermission() async throws {
        let (session, continuation, _) = makeSession()
        try yield(continuation, #"""
        {"type":"control_request","request_id":"p1","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"git init"},"permission_suggestions":[]}}
        """#)
        await waitUntil("pending permission") { session.pendingPermission != nil }
        XCTAssertEqual(session.activityState, .needsApproval)

        // interrupt → error_during_execution abandons the open gate: the CLI
        // is no longer waiting for a decision (fixtures/2026-07-09-interrupt.jsonl).
        try yield(continuation, #"{"type":"result","subtype":"error_during_execution","is_error":true,"uuid":"r1"}"#)
        await waitUntil("gate cleared") { session.pendingPermission == nil }
        XCTAssertEqual(session.activityState, .idle)
        let permissionItem = session.timeline.first {
            if case .permission = $0 { return true } else { return false }
        }
        guard case .permission(_, _, let resolution) = permissionItem else {
            return XCTFail("permission card must remain in the timeline")
        }
        XCTAssertNil(resolution, "abandoned gate stays unresolved-historical")
    }

    func testTerminatedEndsSession() async throws {
        let (session, continuation, _) = makeSession()
        continuation.yield(.terminated(exitCode: 0))
        continuation.finish()
        await waitUntil("ended") { session.hasEnded }
        XCTAssertEqual(session.activityState, .ended)
        XCTAssertFalse(session.isWorking)
    }

    func testTerminatedBeforeInitSurfacesLoudBanner() async throws {
        let (session, continuation, _) = makeSession()
        // Child dies with 127 (env exit) before any `system init` arrived.
        continuation.yield(.terminated(exitCode: 127))
        continuation.finish()
        await waitUntil("ended") { session.hasEnded }
        XCTAssertNil(session.info)
        XCTAssertNotNil(session.versionNote, "dead-at-launch must not be silent")
        XCTAssertTrue(session.versionNote?.contains("127") ?? false,
                      "banner names the exit code: \(session.versionNote ?? "nil")")
    }

    func testSeedTimeline() {
        let (session, _, _) = makeSession()
        session.seed(timeline: [.userMessage(id: "m1", text: "old prompt")])
        XCTAssertEqual(session.timeline.count, 1)
        session.seed(timeline: [.userMessage(id: "m2", text: "ignored")])
        XCTAssertEqual(session.timeline.first?.id, "m1",
                       "seed only fills an empty timeline")
    }

    func testTitleFromFirstPrompt() {
        let (session, _, _) = makeSession()
        XCTAssertEqual(session.title, "demo", "falls back to the folder name")
        session.send("Fix the login bug\nplease")
        XCTAssertEqual(session.title, "Fix the login bug")
    }
}
