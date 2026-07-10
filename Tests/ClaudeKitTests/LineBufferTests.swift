import XCTest
@testable import ClaudeKit

/// Pins the chunk-splitting behavior the pipe reader depends on: pipes
/// fragment lines arbitrarily, so mid-line and mid-UTF-8 splits are the
/// common production case (2026-07-10 final review, Important 2).
final class LineBufferTests: XCTestCase {
    private func data(_ s: String) -> Data { Data(s.utf8) }

    func testWholeLinesInOneChunk() {
        var buffer = LineBuffer()
        let lines = buffer.append(data("{\"a\":1}\n{\"b\":2}\n"))
        XCTAssertEqual(lines, [data("{\"a\":1}"), data("{\"b\":2}")])
        XCTAssertNil(buffer.finish())
    }

    func testLineSplitMidLineAcrossChunks() {
        var buffer = LineBuffer()
        XCTAssertEqual(buffer.append(data("{\"type\":\"sys")), [])
        XCTAssertEqual(buffer.append(data("tem\"}\n")), [data("{\"type\":\"system\"}")])
        XCTAssertNil(buffer.finish())
    }

    func testLineSplitMidUTF8SequenceAcrossChunks() {
        var buffer = LineBuffer()
        let full = data("{\"text\":\"café\"}\n")
        let cut = full.count - 4 // inside the two-byte é sequence
        XCTAssertEqual(buffer.append(full.prefix(cut)), [])
        XCTAssertEqual(buffer.append(full.suffix(from: cut)), [data("{\"text\":\"café\"}")])
    }

    func testOneChunkManyLinesAndRemainder() {
        var buffer = LineBuffer()
        let lines = buffer.append(data("{\"a\":1}\n{\"b\":2}\n{\"c\":"))
        XCTAssertEqual(lines, [data("{\"a\":1}"), data("{\"b\":2}")])
        XCTAssertEqual(buffer.append(data("3}\n")), [data("{\"c\":3}")])
    }

    func testEmptyLinesAreSkipped() {
        var buffer = LineBuffer()
        XCTAssertEqual(buffer.append(data("\n\n{\"a\":1}\n\n")), [data("{\"a\":1}")])
    }

    func testFinishFlushesUnterminatedFinalLine() {
        var buffer = LineBuffer()
        XCTAssertEqual(buffer.append(data("{\"a\":1}\n{\"tail\":true}")), [data("{\"a\":1}")])
        XCTAssertEqual(buffer.finish(), data("{\"tail\":true}"))
        XCTAssertNil(buffer.finish(), "finish drains the buffer")
    }

    func testByteAtATimeDelivery() {
        var buffer = LineBuffer()
        var collected: [Data] = []
        for byte in data("{\"a\":1}\n{\"b\":2}\n") {
            collected += buffer.append(Data([byte]))
        }
        XCTAssertEqual(collected, [data("{\"a\":1}"), data("{\"b\":2}")])
    }
}
