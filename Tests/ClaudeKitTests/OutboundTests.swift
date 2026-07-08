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
            requestID: "r1",
            decision: .allow(updatedInput: input, updatedPermissions: nil),
            requestedInput: .object([:])))
        XCTAssertEqual(v["type"]?.stringValue, "control_response")
        XCTAssertEqual(v["response"]?["subtype"]?.stringValue, "success")
        XCTAssertEqual(v["response"]?["request_id"]?.stringValue, "r1")
        XCTAssertEqual(v["response"]?["response"]?["behavior"]?.stringValue, "allow")
        XCTAssertEqual(v["response"]?["response"]?["updatedInput"]?["command"]?.stringValue,
                       "git init")
    }

    func testDenyPermissionResponse() throws {
        let v = try json(Outbound.permissionResponse(
            requestID: "r2", decision: .deny(message: "not now"),
            requestedInput: .object([:])))
        XCTAssertEqual(v["response"]?["response"]?["behavior"]?.stringValue, "deny")
        XCTAssertEqual(v["response"]?["response"]?["message"]?.stringValue, "not now")
    }

    func testAllowWithoutEditsEchoesRequestedInput() throws {
        let requested = JSONValue.object(["command": .string("git init")])
        let data = Outbound.permissionResponse(
            requestID: "r1", decision: .allowAsRequested, requestedInput: requested)
        let decoded = try JSONValue(parsing: data)
        let inner = decoded["response"]?["response"]
        XCTAssertEqual(inner?["behavior"]?.stringValue, "allow")
        XCTAssertEqual(inner?["updatedInput"], requested,
                       "updatedInput is REQUIRED by the CLI's Zod schema — omit it and the tool is denied")
        XCTAssertNil(inner?["updatedPermissions"])
    }

    func testAllowWithRuleSuggestionsCarriesUpdatedPermissions() throws {
        // Shape recorded live: fixtures/2026-07-09-perm-allow-persist.jsonl
        let suggestion = JSONValue.object([
            "type": .string("addRules"),
            "rules": .array([.object([
                "toolName": .string("Bash"),
                "ruleContent": .string("git init *"),
            ])]),
            "behavior": .string("allow"),
            "destination": .string("localSettings"),
        ])
        let data = Outbound.permissionResponse(
            requestID: "r1",
            decision: .allow(updatedInput: nil, updatedPermissions: [suggestion]),
            requestedInput: .object([:]))
        let decoded = try JSONValue(parsing: data)
        let inner = decoded["response"]?["response"]
        XCTAssertEqual(inner?["updatedPermissions"]?.arrayValue?.first, suggestion)
        XCTAssertEqual(inner?["updatedInput"], .object([:]))
    }

    func testAllowWithEditedInputPrefersTheEdit() throws {
        let edited = JSONValue.object(["command": .string("git init --quiet")])
        let data = Outbound.permissionResponse(
            requestID: "r1",
            decision: .allow(updatedInput: edited, updatedPermissions: nil),
            requestedInput: .object(["command": .string("git init")]))
        let decoded = try JSONValue(parsing: data)
        XCTAssertEqual(decoded["response"]?["response"]?["updatedInput"], edited)
    }

    func testDenyStillOmitsInputFields() throws {
        let data = Outbound.permissionResponse(
            requestID: "r1", decision: .deny(message: "not now"),
            requestedInput: .object([:]))
        let decoded = try JSONValue(parsing: data)
        let inner = decoded["response"]?["response"]
        XCTAssertEqual(inner?["behavior"]?.stringValue, "deny")
        XCTAssertEqual(inner?["message"]?.stringValue, "not now")
        XCTAssertNil(inner?["updatedInput"])
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
