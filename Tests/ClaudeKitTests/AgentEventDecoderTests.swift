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
        guard case .toolResult(let results, _) = try AgentEventDecoder.decode(line) else {
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

    func testToolResultCarriesParentToolUseID() throws {
        let event = try AgentEventDecoder.decode(Data(
            #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"done","is_error":false}]},"parent_tool_use_id":"task-99","uuid":"u1"}"#
            .utf8))
        guard case .toolResult(let results, "task-99") = event else {
            return XCTFail("expected parented toolResult, got \(event)")
        }
        XCTAssertEqual(results.first?.toolUseID, "t1")
    }

    func testToolResultWithoutParentDecodesNil() throws {
        let event = try AgentEventDecoder.decode(Data(
            #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]},"parent_tool_use_id":null,"uuid":"u1"}"#
            .utf8))
        guard case .toolResult(_, nil) = event else {
            return XCTFail("got \(event)")
        }
    }

    func testEventParentToolUseIDHelper() throws {
        let parented = try AgentEventDecoder.decode(Data(
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"hi"}]},"parent_tool_use_id":"task-7","uuid":"a1"}"#
            .utf8))
        XCTAssertEqual(parented.parentToolUseID, "task-7")
        let main = try AgentEventDecoder.decode(Data(
            #"{"type":"result","subtype":"success","is_error":false}"#.utf8))
        XCTAssertNil(main.parentToolUseID)
    }

    /// Shape pinned from fixtures/2026-07-09-askuserquestion-answer.jsonl.
    func testPermissionRequestInteractiveFields() throws {
        let lines = try Fixtures.lines("2026-07-09-askuserquestion-answer.jsonl")
        let events = try lines.map { try AgentEventDecoder.decode($0) }
        let request = events.compactMap { event -> PermissionRequest? in
            if case .controlRequest(let control) = event { return PermissionRequest(control) }
            return nil
        }.first
        let unwrapped = try XCTUnwrap(request, "fixture must contain a can_use_tool request")
        XCTAssertEqual(unwrapped.toolName, "AskUserQuestion")
        XCTAssertTrue(unwrapped.requiresUserInteraction)
        XCTAssertNotNil(unwrapped.toolUseID)
        XCTAssertNotNil(unwrapped.input["questions"]?.arrayValue)
    }

    /// Ordinary Bash permission: interactive fields default off/nil.
    func testPermissionRequestOrdinaryDefaults() throws {
        let control = ControlRequest(
            requestID: "r1", subtype: "can_use_tool",
            payload: try JSONDecoder().decode(JSONValue.self, from: Data(
                #"{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"ls"}}"#.utf8)))
        let request = try XCTUnwrap(PermissionRequest(control))
        XCTAssertFalse(request.requiresUserInteraction)
        XCTAssertNil(request.toolUseID)
    }

    func testToolResultCarriesToolUseResult() throws {
        let line = ##"{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_01M4","type":"tool_result","content":"Task #1 created successfully: Alpha task"}]},"parent_tool_use_id":null,"session_id":"7d97","uuid":"u1","tool_use_result":{"task":{"id":"1","subject":"Alpha task"}}}"##
        let event = try AgentEventDecoder.decode(Data(line.utf8))
        guard case .toolResult(let results, _) = event else {
            return XCTFail("expected toolResult, got \(event)")
        }
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].toolUseResult?["task"]?["id"]?.stringValue, "1")
        XCTAssertEqual(results[0].toolUseResult?["task"]?["subject"]?.stringValue,
                       "Alpha task")
    }

    func testToolUseResultOnlyAttachesToSingleResultLines() throws {
        // Two tool_result blocks + one line-level tool_use_result is ambiguous;
        // the decoder must drop it rather than guess (probe finding 10).
        let line = ##"{"type":"user","message":{"role":"user","content":[{"tool_use_id":"a","type":"tool_result","content":"one"},{"tool_use_id":"b","type":"tool_result","content":"two"}]},"tool_use_result":{"task":{"id":"1"}}}"##
        let event = try AgentEventDecoder.decode(Data(line.utf8))
        guard case .toolResult(let results, _) = event else {
            return XCTFail("expected toolResult, got \(event)")
        }
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.toolUseResult == nil })
    }

    func testControlErrorAckCarriesMessage() throws {
        let line = ##"{"type":"control_response","response":{"subtype":"error","request_id":"badmodel-1","error":"Model \"totally-bogus-model-9000\" is not a recognized model id. Run /model to see available models."}}"##
        let event = try AgentEventDecoder.decode(Data(line.utf8))
        guard case .controlResponse(let envelope) = event else {
            return XCTFail("expected controlResponse, got \(event)")
        }
        XCTAssertEqual(envelope.subtype, "error")
        XCTAssertEqual(envelope.requestID, "badmodel-1")
        XCTAssertEqual(envelope.errorMessage,
                       #"Model "totally-bogus-model-9000" is not a recognized model id. Run /model to see available models."#)
    }

    func testSuccessAckHasNoErrorMessage() throws {
        let line = ##"{"type":"control_response","response":{"subtype":"success","request_id":"ok-1","response":{"mode":"plan"}}}"##
        let event = try AgentEventDecoder.decode(Data(line.utf8))
        guard case .controlResponse(let envelope) = event else {
            return XCTFail("expected controlResponse, got \(event)")
        }
        XCTAssertNil(envelope.errorMessage)
        XCTAssertEqual(envelope.payload?["mode"]?.stringValue, "plan")
    }
}
