import XCTest
@testable import ClaudeKit

final class OutboundTests: XCTestCase {
    private func json(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }

    func testUserMessage() throws {
        let v = try json(Outbound.userMessage("hello"))
        XCTAssertEqual(v["type"]?.stringValue, "user")
        XCTAssertEqual(v["message"]?["role"]?.stringValue, "user")
        XCTAssertEqual(v["message"]?["content"]?.stringValue, "hello")
    }

    func testInitialize() throws {
        let v = try json(Outbound.initialize(requestID: "init-1"))
        XCTAssertEqual(v["type"]?.stringValue, "control_request")
        XCTAssertEqual(v["request_id"]?.stringValue, "init-1")
        XCTAssertEqual(v["request"]?["subtype"]?.stringValue, "initialize")
    }

    func testAllowPermissionResponse() throws {
        let input: JSONValue = .object(["command": .string("git init")])
        let v = try json(Outbound.permissionResponse(
            requestID: "r1", decision: .allow(updatedInput: input)))
        XCTAssertEqual(v["type"]?.stringValue, "control_response")
        XCTAssertEqual(v["response"]?["subtype"]?.stringValue, "success")
        XCTAssertEqual(v["response"]?["request_id"]?.stringValue, "r1")
        XCTAssertEqual(v["response"]?["response"]?["behavior"]?.stringValue, "allow")
        XCTAssertEqual(v["response"]?["response"]?["updatedInput"]?["command"]?.stringValue,
                       "git init")
    }

    func testDenyPermissionResponse() throws {
        let v = try json(Outbound.permissionResponse(
            requestID: "r2", decision: .deny(message: "not now")))
        XCTAssertEqual(v["response"]?["response"]?["behavior"]?.stringValue, "deny")
        XCTAssertEqual(v["response"]?["response"]?["message"]?.stringValue, "not now")
    }

    func testControlRequestOp() throws {
        let v = try json(Outbound.controlRequest(
            requestID: "r3", subtype: "set_model",
            extra: ["model": .string("claude-fable-5")]))
        XCTAssertEqual(v["request"]?["subtype"]?.stringValue, "set_model")
        XCTAssertEqual(v["request"]?["model"]?.stringValue, "claude-fable-5")
    }

    func testOutputEndsWithNewline() {
        XCTAssertEqual(Outbound.userMessage("x").last, UInt8(ascii: "\n"))
        XCTAssertEqual(Outbound.initialize(requestID: "i").last, UInt8(ascii: "\n"))
    }
}
