import XCTest
@testable import ClaudeKit

final class JSONValueTests: XCTestCase {
    func testPlaceholder() {
        XCTAssertEqual(JSONValue.null, JSONValue.null)
    }
}
