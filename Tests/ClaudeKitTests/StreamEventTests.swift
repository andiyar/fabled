import XCTest
@testable import ClaudeKit

final class StreamEventTests: XCTestCase {
    /// Decode every line of a fixture through the live-stream decoder.
    private func decodeEvents(_ fixture: String) throws -> [AgentEvent] {
        try Fixtures.lines(fixture).map { try AgentEventDecoder.decode($0) }
    }

    func testPartialMessagesFixtureCensus() throws {
        let events = try decodeEvents("2026-07-09-partial-messages.jsonl")
        XCTAssertEqual(events.count, 24)

        var messageStart = 0, blockStart = 0, textDelta = 0, thinkingDelta = 0
        var other = 0, blockStop = 0, messageDelta = 0, messageStop = 0
        var texts: [String] = []
        var stopReasons: [String?] = []
        for event in events {
            guard case .streamEvent(let stream) = event else { continue }
            XCTAssertNotNil(stream.sessionID)
            XCTAssertNotNil(stream.uuid)
            switch stream.kind {
            case .messageStart: messageStart += 1
            case .contentBlockStart: blockStart += 1
            case .textDelta(_, let text): textDelta += 1; texts.append(text)
            case .thinkingDelta: thinkingDelta += 1
            case .inputJSONDelta: XCTFail("fixture has no tool_use deltas")
            case .contentBlockStop: blockStop += 1
            case .messageDelta(let reason): messageDelta += 1; stopReasons.append(reason)
            case .messageStop: messageStop += 1
            case .other: other += 1
            }
        }
        // Counts pinned from the recorded capture (see plan "Probe findings").
        XCTAssertEqual(messageStart, 1)
        XCTAssertEqual(blockStart, 2)          // 1 thinking block + 1 text block
        XCTAssertEqual(thinkingDelta, 3)
        XCTAssertEqual(textDelta, 1)
        XCTAssertEqual(texts, ["The quick brown fox jumps over the lazy dog."])
        XCTAssertEqual(other, 1)               // signature_delta → .other, tolerant
        XCTAssertEqual(blockStop, 2)
        XCTAssertEqual(messageDelta, 1)
        XCTAssertEqual(stopReasons, ["end_turn"])
        XCTAssertEqual(messageStop, 1)
    }

    func testContentBlockStartCarriesTypedBlocks() throws {
        let events = try decodeEvents("2026-07-09-partial-messages.jsonl")
        var blocks: [ContentBlock] = []
        for event in events {
            if case .streamEvent(let stream) = event,
               case .contentBlockStart(_, let block) = stream.kind {
                blocks.append(block)
            }
        }
        guard blocks.count == 2 else { return XCTFail("expected 2 block starts") }
        guard case .thinking = blocks[0] else { return XCTFail("first block is thinking") }
        guard case .text = blocks[1] else { return XCTFail("second block is text") }
    }

    /// Protocol-drift gate: every line of every 2026-07-09 capture decodes to
    /// a typed event — zero `.unknown` across the whole probe corpus.
    func testAllProbeFixturesDecodeWithZeroUnknowns() throws {
        let fixtures = [
            "2026-07-09-partial-messages.jsonl",
            "2026-07-09-control-ops.jsonl",
            "2026-07-09-perm-allow-noinput.jsonl",
            "2026-07-09-perm-allow-persist.jsonl",
            "2026-07-09-interrupt.jsonl",
        ]
        for fixture in fixtures {
            for line in try Fixtures.lines(fixture) {
                let event = try AgentEventDecoder.decode(line)
                if case .unknown(let type, _) = event {
                    XCTFail("\(fixture): unknown event type \(type)")
                }
            }
        }
    }

    /// No probe fixture streams tool input, but Task 5's reducer consumes
    /// this branch — pin the decode shape with a synthetic line.
    func testInputJSONDeltaDecodes() throws {
        let line = Data(#"""
        {"type":"stream_event","event":{"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"{\"comm"}},"session_id":"s1","uuid":"u1"}
        """#.utf8)
        guard case .streamEvent(let stream) = try AgentEventDecoder.decode(line) else {
            return XCTFail("expected a stream event")
        }
        XCTAssertEqual(stream.kind, .inputJSONDelta(index: 2, partialJSON: #"{"comm"#))
    }

    func testUnknownStreamEventKindsStayTolerant() throws {
        let line = Data(#"""
        {"type":"stream_event","event":{"type":"hologram_delta","index":0},"session_id":"s1","uuid":"u1"}
        """#.utf8)
        guard case .streamEvent(let stream) = try AgentEventDecoder.decode(line),
              case .other(let type) = stream.kind else {
            return XCTFail("unknown stream kinds must decode to .other, never throw")
        }
        XCTAssertEqual(type, "hologram_delta")
    }
}
