import XCTest
@testable import ClaudeKit

/// Counts entries per TranscriptEntry case across a decoded file.
struct EntryCensus: Equatable {
    var userPrompt = 0, event = 0, title = 0, summary = 0
    var queueOperation = 0, attachment = 0, sessionMeta = 0, unknown = 0

    var total: Int {
        userPrompt + event + title + summary + queueOperation + attachment + sessionMeta + unknown
    }

    static func of(_ lines: [Data]) throws -> EntryCensus {
        var census = EntryCensus()
        for line in lines {
            switch try TranscriptDecoder.decode(line) {
            case .userPrompt: census.userPrompt += 1
            case .event: census.event += 1
            case .title: census.title += 1
            case .summary: census.summary += 1
            case .queueOperation: census.queueOperation += 1
            case .attachment: census.attachment += 1
            case .sessionMeta: census.sessionMeta += 1
            case .unknown: census.unknown += 1
            }
        }
        return census
    }
}

final class TranscriptDecoderTests: XCTestCase {

    // MARK: whole-file censuses (exact values measured 2026-07-08)

    func testRealTitledSessionCensus() throws {
        let census = try EntryCensus.of(try Fixtures.transcriptLines("real-titled-session.jsonl"))
        XCTAssertEqual(census.userPrompt, 6)
        XCTAssertEqual(census.event, 2)        // 1 assistant + 1 system
        XCTAssertEqual(census.title, 6)        // custom-title x6
        XCTAssertEqual(census.summary, 0)
        XCTAssertEqual(census.queueOperation, 4)
        XCTAssertEqual(census.attachment, 5)
        XCTAssertEqual(census.sessionMeta, 5)  // last-prompt x2 + mode x3
        XCTAssertEqual(census.unknown, 0, "zero-unknown gate")
        XCTAssertEqual(census.total, 28)
    }

    func testRealTooluseSessionCensus() throws {
        let census = try EntryCensus.of(try Fixtures.transcriptLines("real-tooluse-session.jsonl"))
        XCTAssertEqual(census.userPrompt, 5)   // 3 string prompts + 2 text-block prompts
        XCTAssertEqual(census.event, 85)       // 60 assistant + 1 system + 24 tool-result user lines
        XCTAssertEqual(census.title, 15)
        XCTAssertEqual(census.queueOperation, 6)
        XCTAssertEqual(census.attachment, 15)
        XCTAssertEqual(census.sessionMeta, 15) // last-prompt x12 + mode x3
        XCTAssertEqual(census.unknown, 0, "zero-unknown gate")
        XCTAssertEqual(census.total, 141)
    }

    func testRealUntitledSessionCensus() throws {
        let census = try EntryCensus.of(try Fixtures.transcriptLines("real-untitled-session.jsonl"))
        XCTAssertEqual(census.userPrompt, 1)
        XCTAssertEqual(census.event, 2)        // 2 assistant
        XCTAssertEqual(census.title, 0)
        XCTAssertEqual(census.queueOperation, 2)
        XCTAssertEqual(census.attachment, 5)
        XCTAssertEqual(census.sessionMeta, 1)  // last-prompt
        XCTAssertEqual(census.unknown, 0, "zero-unknown gate")
        XCTAssertEqual(census.total, 11)
    }

    func testSyntheticEdgeCasesCensus() throws {
        let census = try EntryCensus.of(try Fixtures.transcriptLines("synthetic-edge-cases.jsonl"))
        XCTAssertEqual(census.userPrompt, 5)   // sidechain, meta, compact, plain, text+image
        XCTAssertEqual(census.event, 2)        // tool_result user + assistant
        XCTAssertEqual(census.title, 2)        // ai-title + custom-title
        XCTAssertEqual(census.summary, 1)
        XCTAssertEqual(census.queueOperation, 1)
        XCTAssertEqual(census.attachment, 1)
        XCTAssertEqual(census.sessionMeta, 9)  // result-cache, started, worktree-state, frame-link,
                                               // file-history-snapshot, permission-mode, agent-name,
                                               // mode, last-prompt
        XCTAssertEqual(census.unknown, 1)      // flux-capacitor
        XCTAssertEqual(census.total, 22)
    }

    // MARK: individual decode branches

    private func decode(_ json: String) throws -> TranscriptEntry {
        try TranscriptDecoder.decode(Data(json.utf8))
    }

    func testStringUserPrompt() throws {
        let entry = try decode(#"{"parentUuid":null,"isSidechain":false,"type":"user","message":{"role":"user","content":"first real synthetic prompt about wombats"},"uuid":"00000000-0000-0000-0000-000000000006","timestamp":"2026-07-08T00:00:04.123Z","sessionId":"s"}"#)
        guard case .userPrompt(let text, let context, _) = entry else {
            return XCTFail("expected userPrompt, got \(entry)")
        }
        XCTAssertEqual(text, "first real synthetic prompt about wombats")
        XCTAssertFalse(context.isSidechain)
        XCTAssertFalse(context.isMeta)
        XCTAssertFalse(context.isCompactSummary)
        XCTAssertEqual(context.uuid, "00000000-0000-0000-0000-000000000006")
        let timestamp = try XCTUnwrap(context.timestamp)
        XCTAssertEqual(timestamp.timeIntervalSince1970, 1_783_468_804.123, accuracy: 0.001)
    }

    func testTimestampWithoutFractionalSeconds() throws {
        let entry = try decode(#"{"type":"user","isSidechain":false,"message":{"role":"user","content":"x"},"timestamp":"2026-07-08T00:00:05Z"}"#)
        guard case .userPrompt(_, let context, _) = entry else { return XCTFail() }
        let timestamp = try XCTUnwrap(context.timestamp)
        XCTAssertEqual(timestamp.timeIntervalSince1970, 1_783_468_805, accuracy: 0.001)
    }

    func testTextBlockArrayUserPrompt() throws {
        let entry = try decode(#"{"type":"user","isSidechain":false,"message":{"role":"user","content":[{"type":"text","text":"look at this screenshot please"},{"type":"image","source":{"type":"base64","media_type":"image/png","data":"iVBORw0KGgo="}}]}}"#)
        guard case .userPrompt(let text, _, _) = entry else {
            return XCTFail("expected userPrompt, got \(entry)")
        }
        XCTAssertEqual(text, "look at this screenshot please")
    }

    func testToolResultUserLineBecomesEvent() throws {
        let entry = try decode(#"{"type":"user","isSidechain":false,"message":{"role":"user","content":[{"tool_use_id":"toolu_01","type":"tool_result","content":"file contents here","is_error":false}]}}"#)
        guard case .event(.toolResult(let results), _) = entry else {
            return XCTFail("expected event(.toolResult), got \(entry)")
        }
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].toolUseID, "toolu_01")
        XCTAssertFalse(results[0].isError)
    }

    func testSidechainFlagsSurfaceInContext() throws {
        let entry = try decode(#"{"parentUuid":null,"isSidechain":true,"agentId":"a1","type":"user","message":{"role":"user","content":"sidechain subagent prompt zebra"}}"#)
        guard case .userPrompt(_, let context, _) = entry else { return XCTFail() }
        XCTAssertTrue(context.isSidechain)
        XCTAssertEqual(context.agentID, "a1")
    }

    func testAssistantLineBecomesEvent() throws {
        let entry = try decode(#"{"isSidechain":false,"type":"assistant","message":{"role":"assistant","model":"claude-opus-4-8","content":[{"type":"text","text":"assistant reply about wombats and marsupials"}]},"uuid":"u9"}"#)
        guard case .event(.assistant(let message), let context) = entry else {
            return XCTFail("expected event(.assistant), got \(entry)")
        }
        XCTAssertEqual(message.content, [.text("assistant reply about wombats and marsupials")])
        XCTAssertEqual(context.uuid, "u9")
    }

    func testCustomAndAITitles() throws {
        let custom = try decode(#"{"type":"custom-title","customTitle":"Synthetic custom title","sessionId":"s"}"#)
        guard case .title("Synthetic custom title", isCustom: true, _) = custom else {
            return XCTFail("expected custom title, got \(custom)")
        }
        let ai = try decode(#"{"type":"ai-title","aiTitle":"Synthetic AI title","sessionId":"s"}"#)
        guard case .title("Synthetic AI title", isCustom: false, _) = ai else {
            return XCTFail("expected ai title, got \(ai)")
        }
    }

    func testLegacySummary() throws {
        let entry = try decode(#"{"type":"summary","summary":"Legacy summary title","leafUuid":"l1"}"#)
        guard case .summary(let text, _) = entry else { return XCTFail() }
        XCTAssertEqual(text, "Legacy summary title")
    }

    func testQueueOperation() throws {
        let entry = try decode(#"{"type":"queue-operation","operation":"enqueue","timestamp":"2026-07-08T00:00:10.000Z","sessionId":"s","content":"queued follow-up prompt"}"#)
        guard case .queueOperation(let operation, let content, _) = entry else { return XCTFail() }
        XCTAssertEqual(operation, "enqueue")
        XCTAssertEqual(content, "queued follow-up prompt")
    }

    func testResultCacheLineIsSessionMetaNotTurnResult() throws {
        let entry = try decode(#"{"type":"result","key":"v2:deadbeefcafe","agentId":"a2","result":{"x":1}}"#)
        guard case .sessionMeta(let type, _) = entry else {
            return XCTFail("result-cache lines must not decode as TurnResult; got \(entry)")
        }
        XCTAssertEqual(type, "result")
    }

    func testUnknownTypeIsPreservedNotThrown() throws {
        let entry = try decode(#"{"type":"flux-capacitor","payload":{"charge":88}}"#)
        guard case .unknown(let raw) = entry else { return XCTFail() }
        XCTAssertEqual(raw["type"]?.stringValue, "flux-capacitor")
    }

    func testMalformedJSONThrows() {
        XCTAssertThrowsError(try TranscriptDecoder.decode(Data("not json at all".utf8)))
    }
}
