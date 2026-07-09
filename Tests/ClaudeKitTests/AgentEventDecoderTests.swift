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

    /// Real line from fixtures/2026-07-09-control-ops.jsonl. Top-level
    /// `rate_limit_event` must route to `.system` (which the timeline reducer
    /// drops), never `.unknown` — an unknown would render as a raw-JSON card
    /// in the conversation on every rate-limit tick.
    func testRateLimitEventRoutesToSystemNotUnknown() throws {
        let line = Data(#"""
        {"type":"rate_limit_event","rate_limit_info":{"status":"allowed_warning","resetsAt":1783954800,"rateLimitType":"seven_day","utilization":0.6,"isUsingOverage":false},"uuid":"315277c0-dda9-40fd-b3e4-a3248e51f193","session_id":"45247314-616b-4812-b88d-fd05ae445534"}
        """#.utf8)
        guard case .system(let subtype, let raw) = try AgentEventDecoder.decode(line) else {
            return XCTFail("rate_limit_event must decode as .system")
        }
        XCTAssertEqual(subtype, "rate_limit_event")
        XCTAssertEqual(raw["rate_limit_info"]?["utilization"], .number(0.6))
    }

    func testDecodesCanUseToolControlRequest() throws {
        let line = Data(#"""
        {"type":"control_request","request_id":"4565ced1-e35b-4fbc-bb6a-c87dc03b4747","request":{"subtype":"can_use_tool","tool_name":"Bash","display_name":"Bash","input":{"command":"git init","description":"Initialize a new git repository"},"description":"Initialize a new git repository","permission_suggestions":[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"git init *"}],"behavior":"allow","destination":"localSettings"}],"decision_reason":"This command requires approval"}}
        """#.utf8)
        guard case .controlRequest(let req) = try AgentEventDecoder.decode(line) else {
            return XCTFail("expected controlRequest")
        }
        XCTAssertEqual(req.requestID, "4565ced1-e35b-4fbc-bb6a-c87dc03b4747")
        XCTAssertEqual(req.subtype, "can_use_tool")
        let perm = try XCTUnwrap(PermissionRequest(req))
        XCTAssertEqual(perm.toolName, "Bash")
        XCTAssertEqual(perm.input["command"]?.stringValue, "git init")
        XCTAssertEqual(perm.suggestions.count, 1)
    }

    func testDecodesControlResponse() throws {
        let line = Data(#"""
        {"type":"control_response","response":{"subtype":"success","request_id":"init-1","response":{"commands":[{"name":"review","description":"Review a PR","argumentHint":""}]}}}
        """#.utf8)
        guard case .controlResponse(let resp) = try AgentEventDecoder.decode(line) else {
            return XCTFail("expected controlResponse")
        }
        XCTAssertEqual(resp.requestID, "init-1")
        XCTAssertEqual(resp.payload?["commands"]?.arrayValue?.count, 1)
    }
}
