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
}
