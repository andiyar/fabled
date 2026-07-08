import XCTest
@testable import ClaudeKit

final class TranscriptFixturesTests: XCTestCase {
    func testFixtureInventory() throws {
        XCTAssertEqual(try Fixtures.transcriptLines("real-titled-session.jsonl").count, 28)
        XCTAssertEqual(try Fixtures.transcriptLines("real-tooluse-session.jsonl").count, 141)
        XCTAssertEqual(try Fixtures.transcriptLines("real-untitled-session.jsonl").count, 11)
        XCTAssertEqual(try Fixtures.transcriptLines("synthetic-edge-cases.jsonl").count, 22)
    }

    func testEveryFixtureLineIsValidJSONObjectWithType() throws {
        for name in ["real-titled-session.jsonl", "real-tooluse-session.jsonl",
                     "real-untitled-session.jsonl", "synthetic-edge-cases.jsonl"] {
            for (index, line) in try Fixtures.transcriptLines(name).enumerated() {
                let object = try JSONSerialization.jsonObject(with: line)
                let dictionary = try XCTUnwrap(object as? [String: Any], "\(name):\(index + 1)")
                XCTAssertNotNil(dictionary["type"] as? String, "\(name):\(index + 1) has no type")
            }
        }
    }
}
