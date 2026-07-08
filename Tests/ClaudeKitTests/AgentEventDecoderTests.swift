import XCTest
@testable import ClaudeKit

final class AgentEventDecoderTests: XCTestCase {
    func testDecodesSystemInit() throws {
        let event = try AgentEventDecoder.decode(Fixtures.initLine)
        guard case .systemInit(let info) = event else {
            return XCTFail("expected systemInit, got \(event)")
        }
        XCTAssertEqual(info.sessionID, "9753c268-9f22-44da-b0c2-2aed628498a9")
        XCTAssertEqual(info.model, "claude-haiku-4-5-20251001")
        XCTAssertEqual(info.tools, ["Bash", "Edit", "Read"])
        XCTAssertEqual(info.permissionMode, "default")
        XCTAssertEqual(info.slashCommands, ["init", "review"])
        XCTAssertEqual(info.cliVersion, "2.1.202")
    }

    func testDecodesOtherSystemSubtypesGenerically() throws {
        let event = try AgentEventDecoder.decode(Fixtures.thinkingLine)
        guard case .system(let subtype, let raw) = event else {
            return XCTFail("expected system, got \(event)")
        }
        XCTAssertEqual(subtype, "thinking_tokens")
        XCTAssertEqual(raw["tokens"], .number(128))
    }

    func testUnknownTypeDoesNotThrow() throws {
        let event = try AgentEventDecoder.decode(Fixtures.futureEventLine)
        guard case .unknown(let type, let raw) = event else {
            return XCTFail("expected unknown, got \(event)")
        }
        XCTAssertEqual(type, "hologram_projection")
        XCTAssertEqual(raw["payload"]?["x"], .number(1))
    }

    func testMalformedLineThrows() {
        XCTAssertThrowsError(try AgentEventDecoder.decode(Data("not json".utf8)))
    }

    func testDecodesAssistantTextAndToolUse() throws {
        let line = Data(#"""
        {"type":"assistant","message":{"role":"assistant","model":"claude-haiku-4-5-20251001","content":[{"type":"text","text":"Done."},{"type":"tool_use","id":"toolu_01","name":"Bash","input":{"command":"echo hi"}}]},"parent_tool_use_id":null,"session_id":"s1","uuid":"u1"}
        """#.utf8)
        guard case .assistant(let msg) = try AgentEventDecoder.decode(line) else {
            return XCTFail("expected assistant")
        }
        XCTAssertEqual(msg.content.count, 2)
        XCTAssertEqual(msg.content[0], .text("Done."))
        XCTAssertEqual(msg.content[1],
            .toolUse(id: "toolu_01", name: "Bash",
                     input: .object(["command": .string("echo hi")])))
    }

    func testDecodesToolResultUserEvent() throws {
        let line = Data(#"""
        {"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_01","type":"tool_result","content":"hello-from-test","is_error":false}]},"session_id":"s1","uuid":"u2"}
        """#.utf8)
        guard case .toolResult(let results) = try AgentEventDecoder.decode(line) else {
            return XCTFail("expected toolResult")
        }
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].toolUseID, "toolu_01")
        XCTAssertEqual(results[0].content.stringValue, "hello-from-test")
        XCTAssertFalse(results[0].isError)
    }

    func testDecodesResultEvent() throws {
        let line = Data(#"""
        {"type":"result","subtype":"success","is_error":false,"duration_ms":15,"num_turns":1,"result":"ok","session_id":"s1","total_cost_usd":0.0021,"usage":{"input_tokens":10,"output_tokens":5},"permission_denials":[{"tool_name":"Bash"}],"uuid":"u3"}
        """#.utf8)
        guard case .result(let r) = try AgentEventDecoder.decode(line) else {
            return XCTFail("expected result")
        }
        XCTAssertEqual(r.subtype, "success")
        XCTAssertFalse(r.isError)
        XCTAssertEqual(r.totalCostUSD, 0.0021)
        XCTAssertEqual(r.permissionDenials.count, 1)
    }

    func testDecodesEntireRecordedCaptureWithoutUnknowns() throws {
        for name in ["2026-07-08-sandboxed-bash-no-handshake.jsonl",
                     "2026-07-08-auto-deny-no-permission-tool.jsonl"] {
            for line in try Fixtures.lines(name) {
                let event = try AgentEventDecoder.decode(line)
                if case .unknown(let type, _) = event {
                    XCTFail("unknown event type \(type) in \(name)")
                }
            }
        }
    }
}
