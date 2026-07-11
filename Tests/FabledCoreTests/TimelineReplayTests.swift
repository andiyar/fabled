import XCTest
import ClaudeKit
@testable import FabledCore

final class TimelineReplayTests: XCTestCase {
    private func replay(_ fixture: String) throws -> [TimelineItem] {
        try CoreFixtures.events(fixture).reduce([]) { TimelineReducer.reduce($0, $1) }
    }

    private func census(_ items: [TimelineItem])
        -> (user: Int, text: Int, tool: Int, toolWithResult: Int,
            permission: Int, turn: Int, notice: Int, raw: Int) {
        var c = (user: 0, text: 0, tool: 0, toolWithResult: 0,
                 permission: 0, turn: 0, notice: 0, raw: 0)
        for item in items {
            switch item {
            case .userMessage: c.user += 1
            case .assistantText: c.text += 1
            case .toolCall(_, _, _, _, let result, _, _):
                c.tool += 1
                if result != nil { c.toolWithResult += 1 }
            case .permission: c.permission += 1
            case .turnSummary: c.turn += 1
            case .notice: c.notice += 1
            case .raw: c.raw += 1
            case .thinking: break  // counted by the dedicated thinking test
            }
        }
        return c
    }

    // MARK: reducer completion units

    func testPermissionRequestAppendsAndResolves() throws {
        let event = try AgentEventDecoder.decode(Data(#"""
        {"type":"control_request","request_id":"p1","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"git init"},"permission_suggestions":[]}}
        """#.utf8))
        var items = TimelineReducer.reduce([], event)
        guard case .permission("p1", let request, nil) = items[0] else {
            return XCTFail("got \(items)")
        }
        XCTAssertEqual(request.toolName, "Bash")

        items = TimelineReducer.resolvePermission(
            items, requestID: "p1", decision: .allowAsRequested)
        // Note: .allowAsRequested is a static property, not a case — bind
        // and compare, don't pattern-match it.
        guard case .permission("p1", _, let resolution) = items[0],
              resolution == .allowAsRequested else {
            return XCTFail("resolution must be recorded: \(items)")
        }
    }

    func testNonPermissionControlRequestsRenderNothing() throws {
        let event = try AgentEventDecoder.decode(Data(#"""
        {"type":"control_request","request_id":"h1","request":{"subtype":"hook_callback"}}
        """#.utf8))
        XCTAssertTrue(TimelineReducer.reduce([], event).isEmpty)
    }

    func testResultUnknownAndTerminated() throws {
        var items = TimelineReducer.reduce([], try AgentEventDecoder.decode(Data(#"""
        {"type":"result","subtype":"success","is_error":false,"total_cost_usd":0.01,"uuid":"r1"}
        """#.utf8)))
        guard case .turnSummary("r1", _) = items[0] else { return XCTFail("\(items)") }

        items = TimelineReducer.reduce(items, try AgentEventDecoder.decode(Data(#"""
        {"type":"hologram_projection","payload":{"x":1},"uuid":"h1"}
        """#.utf8)))
        guard case .raw("h1", "hologram_projection", _) = items[1] else { return XCTFail("\(items)") }

        items = TimelineReducer.reduce(items, .terminated(exitCode: 1))
        guard case .notice("terminated", let text) = items[2] else { return XCTFail("\(items)") }
        XCTAssertTrue(text.contains("exit code 1"))
    }

    func testInterruptedStreamTextFinalizesAtTurnEnd() throws {
        // Interrupt mid-text: no finalizing assistant message arrives, the
        // turn ends straight in a result. The dangling streamed item must
        // finalize so the next turn's deltas cannot coalesce onto it.
        var items = TimelineReducer.reduce([], try AgentEventDecoder.decode(Data(
            #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Working"}},"uuid":"u1"}"#.utf8)))
        items = TimelineReducer.reduce(items, try AgentEventDecoder.decode(Data(
            #"{"type":"result","subtype":"error_during_execution","is_error":true,"uuid":"r1"}"#.utf8)))
        guard case .assistantText("u1", "Working", false) = items[0] else {
            return XCTFail("turn end must finalize dangling streamed text: \(items)")
        }
        guard case .turnSummary("r1", _) = items[1] else { return XCTFail("\(items)") }

        items = TimelineReducer.reduce(items, try AgentEventDecoder.decode(Data(
            #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Answer"}},"uuid":"u2"}"#.utf8)))
        XCTAssertEqual(items.count, 3, "next turn's text must start a fresh item")
        guard case .assistantText("u2", "Answer", true) = items[2] else {
            return XCTFail("\(items)")
        }
    }

    // MARK: live-capture replays (ground truth)

    func testPartialMessagesReplay() throws {
        let items = try replay("2026-07-09-partial-messages.jsonl")
        // The turn thinks before answering, so a finalized thinking item now
        // leads the text and turn summary (4b T3).
        XCTAssertEqual(items.count, 3)
        guard case .thinking(_, _, false) = items[0]
        else { return XCTFail("\(items)") }
        guard case .assistantText(_, "The quick brown fox jumps over the lazy dog.", false) = items[1]
        else { return XCTFail("\(items)") }
        guard case .turnSummary = items[2] else { return XCTFail("\(items)") }
    }

    func testControlOpsReplay() throws {
        let items = try replay("2026-07-09-control-ops.jsonl")
        let c = census(items)
        XCTAssertEqual(c.turn, 3, "three turns ran (incl. the queued message)")
        XCTAssertEqual(c.raw, 0)
        let texts = items.compactMap { item -> String? in
            if case .assistantText(_, let markdown, false) = item { return markdown }
            return nil
        }
        XCTAssertEqual(texts.count, 3)
        XCTAssertEqual(texts[1], "QUEUED-OK")
        XCTAssertEqual(texts[2], "4")
    }

    func testPermissionPersistReplay() throws {
        let items = try replay("2026-07-09-perm-allow-persist.jsonl")
        let c = census(items)
        XCTAssertEqual(c.permission, 1)
        XCTAssertEqual(c.tool, 1)
        XCTAssertEqual(c.toolWithResult, 1, "the allowed git init ran and returned")
        XCTAssertEqual(c.turn, 1)
        XCTAssertEqual(c.raw, 0)
    }

    func testInterruptReplay() throws {
        let items = try replay("2026-07-09-interrupt.jsonl")
        guard case .turnSummary(_, let turn) = items.last else {
            return XCTFail("\(items)")
        }
        XCTAssertEqual(turn.subtype, "error_during_execution")
        XCTAssertTrue(turn.isError)
    }

    // MARK: on-disk transcript replays (read-only history)

    func testTitledTranscriptReplay() throws {
        let items = TimelineReducer.items(
            fromTranscript: try CoreFixtures.transcript("real-titled-session.jsonl"))
        let c = census(items)
        XCTAssertEqual(c.user, 1)
        XCTAssertEqual(c.text, 1)
        XCTAssertEqual(c.tool, 0)
        XCTAssertEqual(c.permission, 0)
        XCTAssertEqual(c.notice, 0)
        XCTAssertEqual(c.raw, 0)
        XCTAssertEqual(c.turn, 0, "on-disk result lines are subagent caches, never turn summaries")
    }

    func testToolUseTranscriptReplay() throws {
        let items = TimelineReducer.items(
            fromTranscript: try CoreFixtures.transcript("real-tooluse-session.jsonl"))
        let c = census(items)
        // Counts pinned from a line-by-line census of the fixture during
        // plan-writing. If these fail, the reducer diverged from the rules —
        // investigate the diff, do not blindly update the numbers.
        XCTAssertEqual(c.user, 4)
        XCTAssertEqual(c.text, 17)
        XCTAssertEqual(c.tool, 24)
        XCTAssertEqual(c.toolWithResult, 23)
        XCTAssertEqual(c.raw, 0)
        // First item is the human prompt — machine/meta lines never lead.
        guard case .userMessage = items.first else { return XCTFail("\(items.first.debugDescription)") }
    }

    func testSyntheticEdgeCasesTranscriptReplay() throws {
        let items = TimelineReducer.items(
            fromTranscript: try CoreFixtures.transcript("synthetic-edge-cases.jsonl"))
        let c = census(items)
        // Counts pinned from a manual line-by-line census of the fixture
        // (2026-07-09). The three kept user lines: the compact-summary
        // continuation (isCompactSummary is NOT a drop rule — only
        // sidechain/meta are), the plain prompt, and the text+image block
        // prompt (image block contributes no text). Dropped: the sidechain
        // subagent prompt, the isMeta <command-name> echo, all titles,
        // queue/attachment/session-meta bookkeeping. The orphan tool_result
        // (line 8) matches no tool call and renders nothing.
        XCTAssertEqual(c.user, 3)
        XCTAssertEqual(c.text, 1)
        XCTAssertEqual(c.tool, 0)
        XCTAssertEqual(c.toolWithResult, 0)
        XCTAssertEqual(c.permission, 0)
        XCTAssertEqual(c.notice, 0)
        XCTAssertEqual(c.turn, 0,
            "the on-disk result line is a subagent cache (key + agentId), never a turn summary")
        XCTAssertEqual(c.raw, 0,
            "unknown top-level line types route to TranscriptEntry.unknown and are dropped")
    }

    func testUntitledTranscriptReplay() throws {
        let items = TimelineReducer.items(
            fromTranscript: try CoreFixtures.transcript("real-untitled-session.jsonl"))
        let c = census(items)
        XCTAssertEqual(c.user, 1)
        XCTAssertEqual(c.text, 1)
    }

    func testSlashfxFixtureProducesThinkingItems() throws {
        var items: [TimelineItem] = []
        for event in try CoreFixtures.events("2026-07-11-slashfx.jsonl") {
            items = TimelineReducer.reduce(items, event)
        }
        let thinking = items.compactMap { item -> Bool? in
            if case .thinking(_, _, let streaming) = item { return streaming }
            return nil
        }
        XCTAssertFalse(thinking.isEmpty, "fixture carries thinking turns")
        XCTAssertTrue(thinking.allSatisfy { $0 == false },
                      "every thinking item finalizes by end of fixture")
    }

    @MainActor
    func testTasktoolsFixtureFoldsToFinalChecklist() async throws {
        let (connection, continuation, _) = makeFakeConnection()
        let session = ChatSession(
            connection: connection,
            workingDirectory: URL(fileURLWithPath: "/tmp/demo"))
        session.begin()
        for event in try CoreFixtures.events("2026-07-11-tasktools.jsonl") {
            continuation.yield(event)
        }
        // Probe script: Alpha completed, Beta pending, Gamma deleted.
        await waitUntil("fold") { session.sessionTasks.count == 2 }
        XCTAssertEqual(session.sessionTasks.map(\.subject), ["Alpha task", "Beta task"])
        XCTAssertEqual(session.sessionTasks.map(\.status), [.completed, .pending])
    }
}
