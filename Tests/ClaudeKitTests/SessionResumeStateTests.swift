import XCTest
@testable import ClaudeKit

final class SessionResumeStateTests: XCTestCase {
    private func data(_ lines: [String]) -> Data {
        Data(lines.joined(separator: "\n").utf8)
    }

    func testDerivesLastAssistantModelAndLastPermissionMode() {
        // Real on-disk shapes: assistant lines carry `message.model`; user
        // lines carry a top-level `permissionMode` that updates every prompt.
        let transcript = data([
            #"{"type":"user","permissionMode":"default","message":{"content":"hi"}}"#,
            #"{"type":"assistant","message":{"model":"claude-haiku-4-5-20251001","content":[]}}"#,
            #"{"type":"user","permissionMode":"bypassPermissions","message":{"content":"go"}}"#,
            #"{"type":"assistant","message":{"model":"claude-opus-4-8","content":[]}}"#,
        ])
        let state = SessionResumeState.derive(fromFileData: transcript)
        XCTAssertEqual(state.model, "claude-opus-4-8", "last assistant model wins")
        XCTAssertEqual(state.permissionMode, "bypassPermissions", "last permission mode wins")
    }

    func testAbsentFieldsStayNil() {
        let transcript = data([
            #"{"type":"user","message":{"content":"hi"}}"#,
            #"{"type":"custom-title","customTitle":"Whatever"}"#,
        ])
        let state = SessionResumeState.derive(fromFileData: transcript)
        XCTAssertNil(state.model, "no assistant line → no model to restore")
        XCTAssertNil(state.permissionMode, "no permissionMode field → nil, caller falls back")
    }

    func testAutoIsCarriedThroughVerbatim() {
        // Claude Desktop records its "Auto" mode as the wire string "auto".
        let transcript = data([
            #"{"type":"user","permissionMode":"auto","message":{"content":"hi"}}"#,
            #"{"type":"assistant","message":{"model":"claude-opus-4-8","content":[]}}"#,
        ])
        let state = SessionResumeState.derive(fromFileData: transcript)
        XCTAssertEqual(state.permissionMode, "auto")
    }

    func testDerivesFromRealTranscriptFixtures() throws {
        // Pins the derivation to the actual on-disk corpus shapes.
        let cases = [
            ("real-tooluse-session.jsonl", "claude-opus-4-8", "auto"),
            ("real-untitled-session.jsonl", "claude-haiku-4-5-20251001", "default"),
        ]
        for (fixture, expectedModel, expectedMode) in cases {
            let data = try Fixtures.transcriptData(fixture)
            let state = SessionResumeState.derive(fromFileData: data)
            XCTAssertEqual(state.model, expectedModel, "\(fixture) model")
            XCTAssertEqual(state.permissionMode, expectedMode, "\(fixture) mode")
        }
    }

    func testEmptyStringsAreIgnored() {
        let transcript = data([
            #"{"type":"assistant","message":{"model":"claude-opus-4-8","content":[]}}"#,
            #"{"type":"user","permissionMode":"","message":{"content":"go"}}"#,
            #"{"type":"assistant","message":{"model":"","content":[]}}"#,
        ])
        let state = SessionResumeState.derive(fromFileData: transcript)
        XCTAssertEqual(state.model, "claude-opus-4-8", "an empty later model does not clobber a real one")
        XCTAssertNil(state.permissionMode, "an empty permissionMode is not a real mode")
    }
}
