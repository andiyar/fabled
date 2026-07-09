import XCTest
import ClaudeKit
@testable import FabledCore

final class PermissionPromptTests: XCTestCase {
    /// Suggestion shape recorded live 2026-07-09.
    private let suggestion = JSONValue.object([
        "type": .string("addRules"),
        "rules": .array([.object([
            "toolName": .string("Bash"),
            "ruleContent": .string("git init *"),
        ])]),
        "behavior": .string("allow"),
        "destination": .string("localSettings"),
    ])

    func testAlwaysAllowLabel() {
        XCTAssertEqual(PermissionPrompt.alwaysAllowLabel(for: [suggestion]),
                       "Always allow: Bash(git init *)")
        XCTAssertNil(PermissionPrompt.alwaysAllowLabel(for: []))
        XCTAssertNil(PermissionPrompt.alwaysAllowLabel(
            for: [.object(["type": .string("setMode")])]),
            "only addRules suggestions make an always-allow button")
    }

    func testCommandSummaryPrefersBashCommand() throws {
        let event = try AgentEventDecoder.decode(Data(#"""
        {"type":"control_request","request_id":"p1","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"git init"},"permission_suggestions":[]}}
        """#.utf8))
        guard case .controlRequest(let request) = event,
              let permission = PermissionRequest(request) else {
            return XCTFail("fixture line must decode to a permission request")
        }
        XCTAssertEqual(PermissionPrompt.commandSummary(for: permission), "git init")
    }
}
