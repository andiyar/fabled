import XCTest
@testable import ClaudeKit

final class SessionTitleTests: XCTestCase {

    // MARK: JSONLines

    private func lines(_ text: String) -> [String] {
        var result: [String] = []
        var iterator = JSONLines(data: Data(text.utf8))
        while let line = iterator.next() {
            result.append(String(decoding: line, as: UTF8.self))
        }
        return result
    }

    func testJSONLinesSplitsAndSkipsBlanks() {
        XCTAssertEqual(lines("a\nb\n"), ["a", "b"])
        XCTAssertEqual(lines("a\n\n\nb"), ["a", "b"])   // blank lines skipped
        XCTAssertEqual(lines("a"), ["a"])                // no trailing newline
        XCTAssertEqual(lines(""), [])
        XCTAssertEqual(lines("\n\n"), [])
    }

    // MARK: TitleAccumulator priority chain

    private func consumeAll(_ jsonLines: [String]) throws -> TitleAccumulator {
        var accumulator = TitleAccumulator()
        for line in jsonLines {
            accumulator.consume(try TranscriptDecoder.decode(Data(line.utf8)))
        }
        return accumulator
    }

    private let promptLine = #"{"isSidechain":false,"type":"user","message":{"role":"user","content":"first real synthetic prompt about wombats"}}"#
    private let summaryLine = #"{"type":"summary","summary":"Legacy summary title"}"#
    private let aiTitleLine = #"{"type":"ai-title","aiTitle":"Synthetic AI title","sessionId":"s"}"#
    private let customTitleLine = #"{"type":"custom-title","customTitle":"Synthetic custom title","sessionId":"s"}"#

    func testCustomTitleBeatsEverything() throws {
        let acc = try consumeAll([promptLine, summaryLine, aiTitleLine, customTitleLine])
        XCTAssertEqual(acc.best, "Synthetic custom title")
    }

    func testAITitleBeatsSummaryAndPrompt() throws {
        let acc = try consumeAll([promptLine, summaryLine, aiTitleLine])
        XCTAssertEqual(acc.best, "Synthetic AI title")
    }

    func testSummaryBeatsPrompt() throws {
        let acc = try consumeAll([promptLine, summaryLine])
        XCTAssertEqual(acc.best, "Legacy summary title")
    }

    func testPromptIsLastResort() throws {
        let acc = try consumeAll([promptLine])
        XCTAssertEqual(acc.best, "first real synthetic prompt about wombats")
    }

    func testLastTitleWins() throws {
        let renamed = #"{"type":"custom-title","customTitle":"Renamed later","sessionId":"s"}"#
        let acc = try consumeAll([customTitleLine, renamed])
        XCTAssertEqual(acc.best, "Renamed later")
    }

    func testEmptyCustomTitleFallsThrough() throws {
        let empty = #"{"type":"custom-title","customTitle":"","sessionId":"s"}"#
        let acc = try consumeAll([promptLine, empty])
        XCTAssertEqual(acc.best, "first real synthetic prompt about wombats")
    }

    func testUnusablePromptsAreSkipped() throws {
        let sidechain = #"{"isSidechain":true,"type":"user","message":{"role":"user","content":"subagent noise"}}"#
        let meta = #"{"isSidechain":false,"isMeta":true,"type":"user","message":{"role":"user","content":"meta noise"}}"#
        let compact = #"{"isSidechain":false,"isCompactSummary":true,"type":"user","message":{"role":"user","content":"This session is being continued"}}"#
        let command = #"{"isSidechain":false,"type":"user","message":{"role":"user","content":"<command-name>/clear</command-name>"}}"#
        let blank = #"{"isSidechain":false,"type":"user","message":{"role":"user","content":"   "}}"#
        let acc = try consumeAll([sidechain, meta, compact, command, blank, promptLine])
        XCTAssertEqual(acc.best, "first real synthetic prompt about wombats")
    }

    func testFirstUsablePromptSticks() throws {
        let second = #"{"isSidechain":false,"type":"user","message":{"role":"user","content":"second prompt"}}"#
        let acc = try consumeAll([promptLine, second])
        XCTAssertEqual(acc.best, "first real synthetic prompt about wombats")
    }

    // MARK: cleaning

    func testCleanTakesFirstLineTrimmedAndCapped() {
        XCTAssertEqual(TitleAccumulator.clean("  hello\nworld  "), "hello")
        XCTAssertNil(TitleAccumulator.clean("   \n  "))
        let long = String(repeating: "x", count: 300)
        XCTAssertEqual(TitleAccumulator.clean(long)?.count, 200)
    }

    // MARK: SessionTitle.derive over fixture files

    func testDeriveOnRealFixtures() throws {
        XCTAssertEqual(
            SessionTitle.derive(fromFileData: try Fixtures.transcriptData("real-titled-session.jsonl")),
            "Metal renderer planning review")
        XCTAssertEqual(
            SessionTitle.derive(fromFileData: try Fixtures.transcriptData("real-tooluse-session.jsonl")),
            "Auto-updating bundles from GitHub")
        XCTAssertEqual(
            SessionTitle.derive(fromFileData: try Fixtures.transcriptData("real-untitled-session.jsonl")),
            "Reply with exactly: pong")
        XCTAssertEqual(
            SessionTitle.derive(fromFileData: try Fixtures.transcriptData("synthetic-edge-cases.jsonl")),
            "Synthetic custom title")
    }

    func testTitleLineBeyondPromptScanWindowIsStillFound() throws {
        // 150 queue-operation filler lines, then a custom-title at the end:
        // the byte filter must still find it past the 100-line prompt window.
        let filler = #"{"type":"queue-operation","operation":"enqueue","sessionId":"s"}"#
        var fileText = Array(repeating: filler, count: 150).joined(separator: "\n")
        fileText += "\n" + #"{"type":"custom-title","customTitle":"Found at the end","sessionId":"s"}"# + "\n"
        XCTAssertEqual(SessionTitle.derive(fromFileData: Data(fileText.utf8)), "Found at the end")
    }

    func testPromptBeyondScanWindowYieldsNil() throws {
        let filler = #"{"type":"queue-operation","operation":"enqueue","sessionId":"s"}"#
        var fileText = Array(repeating: filler, count: 150).joined(separator: "\n")
        fileText += "\n" + promptLine + "\n"
        // Documented cutoff: prompts are only sought in the first 100 lines.
        XCTAssertNil(SessionTitle.derive(fromFileData: Data(fileText.utf8)))
    }

    func testPromptContainingTitleKeyBeyondScanWindowYieldsNil() throws {
        // A user line past the window whose raw bytes contain a title-key
        // pattern trips the byte filter and gets decoded — but must still not
        // become the first-prompt fallback. Note the key must appear OUTSIDE
        // string content: quotes inside content are escaped (\"customTitle\"),
        // which never matches the quoted byte patterns.
        let filler = #"{"type":"queue-operation","operation":"enqueue","sessionId":"s"}"#
        let trojan = #"{"isSidechain":false,"type":"user","customTitle":"stray","message":{"role":"user","content":"a usable prompt past the window"}}"#
        var fileText = Array(repeating: filler, count: 150).joined(separator: "\n")
        fileText += "\n" + trojan + "\n"
        XCTAssertNil(SessionTitle.derive(fromFileData: Data(fileText.utf8)))
    }
}
