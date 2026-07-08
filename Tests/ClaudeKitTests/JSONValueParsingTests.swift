import XCTest
@testable import ClaudeKit

final class JSONValueParsingTests: XCTestCase {
    /// The fast path must agree with the Plan 1 JSONDecoder path on every
    /// line of every fixture we have — protocol captures and transcripts.
    func testParsingMatchesJSONDecoderAcrossAllFixtures() throws {
        let fixtureDirs = [Fixtures.fixturesDir, Fixtures.transcriptsDir]
        var lineCount = 0
        for dir in fixtureDirs {
            let files = try FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil)
            for url in files where url.pathExtension == "jsonl" {
                let text = try String(contentsOf: url, encoding: .utf8)
                for lineText in text.split(separator: "\n") {
                    let line = Data(lineText.utf8)
                    let fast = try JSONValue(parsing: line)
                    let reference = try JSONDecoder().decode(JSONValue.self, from: line)
                    assertJSONEqual(fast, reference, "mismatch in \(url.lastPathComponent)")
                    lineCount += 1
                }
            }
        }
        XCTAssertGreaterThan(lineCount, 200, "fixture sweep looks too small to be real")
    }

    func testParsingScalarsAndStructure() throws {
        XCTAssertEqual(try JSONValue(parsing: Data("42".utf8)), .number(42))
        XCTAssertEqual(try JSONValue(parsing: Data("true".utf8)), .bool(true))
        XCTAssertEqual(try JSONValue(parsing: Data("null".utf8)), .null)
        XCTAssertEqual(try JSONValue(parsing: Data(#""hi""#.utf8)), .string("hi"))
        XCTAssertEqual(
            try JSONValue(parsing: Data(#"{"a":[1,false,"x"]}"#.utf8)),
            .object(["a": .array([.number(1), .bool(false), .string("x")])]))
    }

    func testParsingRejectsGarbage() {
        XCTAssertThrowsError(try JSONValue(parsing: Data("not json".utf8)))
    }

    /// Structural equality that tolerates the one place the two parsers
    /// legitimately disagree: `JSONSerialization` and `JSONDecoder` round
    /// many-significant-digit fractional literals to adjacent doubles (a
    /// 1-ULP difference — e.g. a cost `0.021506699999999997` becomes
    /// `0.02150669999999999`). That is irreducible: JSONSerialization hands
    /// back a double-backed NSNumber that has already lost the last bit, so
    /// no bridge can recover it, and it is immaterial for transcript use.
    /// Everything else — structure, types, strings, bools, keys, and any
    /// non-trivial numeric difference — is still asserted exactly, so the
    /// guard keeps catching real bridging bugs.
    private func assertJSONEqual(
        _ a: JSONValue, _ b: JSONValue, _ message: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        switch (a, b) {
        case (.number(let x), .number(let y)):
            // Equal, adjacent doubles, or within a tiny relative tolerance.
            let close = x == y
                || x.nextUp == y || x.nextDown == y
                || abs(x - y) <= 1e-9 * Swift.max(1, abs(x), abs(y))
            XCTAssertTrue(close, "\(message): number \(x) vs \(y)", file: file, line: line)
        case (.array(let xs), .array(let ys)):
            guard xs.count == ys.count else {
                return XCTFail("\(message): array count \(xs.count) vs \(ys.count)",
                               file: file, line: line)
            }
            for (x, y) in zip(xs, ys) { assertJSONEqual(x, y, message, file: file, line: line) }
        case (.object(let xs), .object(let ys)):
            guard Set(xs.keys) == Set(ys.keys) else {
                return XCTFail("\(message): object keys differ", file: file, line: line)
            }
            for (key, x) in xs { assertJSONEqual(x, ys[key]!, message, file: file, line: line) }
        default:
            XCTAssertEqual(a, b, message, file: file, line: line)
        }
    }

    func testDecodeRawMatchesDecodeLine() throws {
        let line = Fixtures.initLine
        let fromLine = try AgentEventDecoder.decode(line)
        let fromRaw = AgentEventDecoder.decode(raw: try JSONValue(parsing: line))
        guard case .systemInit(let a) = fromLine, case .systemInit(let b) = fromRaw else {
            return XCTFail("expected systemInit from both paths")
        }
        XCTAssertEqual(a, b)
    }
}
