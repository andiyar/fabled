import XCTest
import ClaudeKit
@testable import FabledCore

final class TimelineReducerTests: XCTestCase {
    private func event(_ json: String) throws -> AgentEvent {
        try AgentEventDecoder.decode(Data(json.utf8))
    }

    private func reduceAll(_ jsonLines: [String]) throws -> [TimelineItem] {
        try jsonLines.reduce(into: [TimelineItem]()) { items, json in
            items = TimelineReducer.reduce(items, try event(json))
        }
    }

    func testStreamingTextCoalescesThenFinalizes() throws {
        var items: [TimelineItem] = []
        items = TimelineReducer.reduce(items, try event(
            #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hel"}},"session_id":"s1","uuid":"u1"}"#))
        items = TimelineReducer.reduce(items, try event(
            #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"lo"}},"session_id":"s1","uuid":"u2"}"#))
        XCTAssertEqual(items.count, 1, "deltas coalesce into one streaming item")
        guard case .assistantText(let id, "Hello", true) = items[0] else {
            return XCTFail("expected streaming assistantText, got \(items[0])")
        }
        XCTAssertEqual(id, "u1", "first delta's uuid names the item")

        items = TimelineReducer.reduce(items, try event(
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Hello!"}]},"session_id":"s1","uuid":"a1"}"#))
        XCTAssertEqual(items.count, 1)
        guard case .assistantText("u1", "Hello!", false) = items[0] else {
            return XCTFail("final message must replace the streamed text in place, same id")
        }
    }

    func testAssistantWithoutPriorDeltasAppends() throws {
        let items = try reduceAll([
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Hi"}]},"uuid":"a1"}"#,
        ])
        XCTAssertEqual(items.count, 1)
        guard case .assistantText("a1-0", "Hi", false) = items[0] else {
            return XCTFail("got \(items[0])")
        }
    }

    func testEmptyTextBlocksAreSkipped() throws {
        let items = try reduceAll([
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":""},{"type":"thinking","thinking":"hmm"}]},"uuid":"a1"}"#,
        ])
        // The empty text block renders nothing; the thinking block now renders
        // a single finalized item (4b T3) — so exactly one item, no text row.
        XCTAssertEqual(items.count, 1)
        guard case .thinking(_, "hmm", false) = items[0] else {
            return XCTFail("empty text skipped, thinking finalized: \(items)")
        }
    }

    func testToolCallLifecycle() throws {
        var items = try reduceAll([
            // streamed start announces the call…
            #"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"t1","name":"Bash","input":{}}},"uuid":"u1"}"#,
            // …the final assistant message carries the full input…
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"git init"}}]},"uuid":"a1"}"#,
        ])
        XCTAssertEqual(items.count, 1, "same tool_use id must upsert, not duplicate")
        guard case .toolCall("t1", "Bash", let summary, _, nil, nil, true) = items[0] else {
            return XCTFail("got \(items[0])")
        }
        XCTAssertEqual(summary, "git init")

        // …and the tool_result fills it in.
        items = TimelineReducer.reduce(items, try event(
            #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"done","is_error":false}]},"uuid":"r1"}"#))
        guard case .toolCall("t1", "Bash", _, _, .string("done"), false, false) = items[0] else {
            return XCTFail("result must land on the matching call: \(items[0])")
        }
    }

    func testEmptyToolResultListIsNoOp() throws {
        // Synthetic user lines ("[Request interrupted]", local-command echoes)
        // decode to .toolResult([], parentToolUseID: nil) — they must not
        // disturb the timeline.
        let items = try reduceAll([
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Hi"}]},"uuid":"a1"}"#,
            #"{"type":"user","message":{"role":"user","content":"<local-command-stdout>ok</local-command-stdout>"},"isReplay":true,"uuid":"x1"}"#,
        ])
        XCTAssertEqual(items.count, 1)
    }

    func testInteractiveGateRequestsRenderNoPermissionRow() throws {
        let items = try reduceAll([
            #"{"type":"control_request","request_id":"q1","request":{"subtype":"can_use_tool","tool_name":"AskUserQuestion","input":{"questions":[{"question":"Color?","header":"C","options":[{"label":"Red","description":""}],"multiSelect":false}]},"requires_user_interaction":true}}"#,
        ])
        XCTAssertTrue(items.isEmpty,
                      "interactive gates render in the composer slot, not the timeline")
    }

    func testOrdinaryPermissionStillRendersRow() throws {
        let items = try reduceAll([
            #"{"type":"control_request","request_id":"p1","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"rm x"}}}"#,
        ])
        guard case .permission("p1", _, nil) = items.first else {
            return XCTFail("got \(items)")
        }
    }

    /// New contract: reduce() takes events as given — the CALLER routes
    /// subagent traffic. A parented event handed to reduce() is rendered.
    func testReducerNoLongerDropsParentedEvents() throws {
        let items = try reduceAll([
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"sub"}]},"parent_tool_use_id":"task-1","uuid":"a1"}"#,
        ])
        XCTAssertEqual(items.count, 1, "routing is the caller's job now")
    }

    func testUserEchoAppends() {
        let items = TimelineReducer.appendUserMessage([], id: "m1", text: "hello")
        XCTAssertEqual(items, [.userMessage(id: "m1", text: "hello")])
    }

    func testToolSummaries() {
        XCTAssertEqual(ToolCallSummary.summarize(
            name: "Bash", input: .object(["command": .string("git status\n# second line")])),
            "git status")
        XCTAssertEqual(ToolCallSummary.summarize(
            name: "Read", input: .object(["file_path": .string("/tmp/a.txt")])),
            "/tmp/a.txt")
        XCTAssertEqual(ToolCallSummary.summarize(
            name: "MysteryTool", input: .object(["x": .number(1)])),
            "MysteryTool")
        XCTAssertEqual(ToolCallSummary.summarize(
            name: "Bash", input: .object([:])), "Bash")
    }

    func testJSONPretty() {
        XCTAssertEqual(JSONPretty.string(.string("plain text")), "plain text")
        XCTAssertTrue(JSONPretty.string(.object(["b": .number(1), "a": .bool(true)]))
            .contains("\"a\" : true"))
    }

    // MARK: - Thinking (4b T3)

    private func thinkingDelta(_ text: String, uuid: String = "u") throws -> AgentEvent {
        try AgentEventDecoder.decode(Data(#"""
        {"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"\#(text)","estimated_tokens":null}},"session_id":"s","parent_tool_use_id":null,"uuid":"\#(uuid)"}
        """#.utf8))
    }

    func testThinkingDeltasCoalesceIntoOneItem() throws {
        var items: [TimelineItem] = []
        items = TimelineReducer.reduce(items, try thinkingDelta("The user", uuid: "t1"))
        items = TimelineReducer.reduce(items, try thinkingDelta(" wants a plan"))
        XCTAssertEqual(items.count, 1)
        guard case .thinking(let id, let text, let isStreaming) = items[0] else {
            return XCTFail("expected thinking, got \(items)")
        }
        XCTAssertEqual(id, "t1")
        XCTAssertEqual(text, "The user wants a plan")
        XCTAssertTrue(isStreaming)
    }

    func testAssistantThinkingBlockFinalizesStreamedItem() throws {
        var items: [TimelineItem] = []
        items = TimelineReducer.reduce(items, try thinkingDelta("The user wants", uuid: "t1"))
        let assistant = try AgentEventDecoder.decode(Data(#"""
        {"type":"assistant","message":{"role":"assistant","model":"m","content":[{"type":"thinking","thinking":"The user wants a plan.","signature":"sig"},{"type":"text","text":"Here it is."}]},"session_id":"s","uuid":"a1"}
        """#.utf8))
        items = TimelineReducer.reduce(items, assistant)
        guard case .thinking(let id, let text, let isStreaming) = items[0] else {
            return XCTFail("expected finalized thinking first, got \(items)")
        }
        XCTAssertEqual(id, "t1", "same item id — update in place, not remove+insert")
        XCTAssertEqual(text, "The user wants a plan.")
        XCTAssertFalse(isStreaming)
        guard case .assistantText = items[1] else {
            return XCTFail("expected assistant text second, got \(items)")
        }
    }

    func testReplayRendersThinkingFromTranscriptBlocks() throws {
        // No streaming preceded it (replay path) — the block appends finalized.
        let assistant = try AgentEventDecoder.decode(Data(#"""
        {"type":"assistant","message":{"role":"assistant","model":"m","content":[{"type":"thinking","thinking":"Recorded thought.","signature":"sig"}]},"session_id":"s","uuid":"a1"}
        """#.utf8))
        let items = TimelineReducer.reduce([], assistant)
        guard case .thinking(_, "Recorded thought.", false) = items[0] else {
            return XCTFail("expected finalized thinking, got \(items)")
        }
    }

    func testTextDeltaAfterThinkingDoesNotCoalesceIntoIt() throws {
        var items: [TimelineItem] = []
        items = TimelineReducer.reduce(items, try thinkingDelta("hmm", uuid: "t1"))
        let textDelta = try AgentEventDecoder.decode(Data(#"""
        {"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Answer"}},"session_id":"s","uuid":"x1"}
        """#.utf8))
        items = TimelineReducer.reduce(items, textDelta)
        XCTAssertEqual(items.count, 2)
        guard case .assistantText(_, "Answer", true) = items[1] else {
            return XCTFail("expected separate streaming text, got \(items)")
        }
    }

    func testResultFinalizesDanglingThinking() throws {
        var items: [TimelineItem] = []
        items = TimelineReducer.reduce(items, try thinkingDelta("interrupted", uuid: "t1"))
        let result = try AgentEventDecoder.decode(Data(#"""
        {"type":"result","subtype":"error_during_execution","is_error":true,"num_turns":1,"uuid":"r1","session_id":"s"}
        """#.utf8))
        items = TimelineReducer.reduce(items, result)
        guard case .thinking(_, _, false) = items[0] else {
            return XCTFail("dangling thinking must finalize, got \(items)")
        }
    }
}
