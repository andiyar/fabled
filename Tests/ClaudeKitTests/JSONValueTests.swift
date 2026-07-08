import XCTest
@testable import ClaudeKit

final class JSONValueTests: XCTestCase {
    func testDecodesArbitraryObject() throws {
        let data = Data(#"{"a":1,"b":"x","c":[true,null],"d":{"e":2.5}}"#.utf8)
        let v = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(v["a"], .number(1))
        XCTAssertEqual(v["b"]?.stringValue, "x")
        XCTAssertEqual(v["c"], .array([.bool(true), .null]))
        XCTAssertEqual(v["d"]?["e"], .number(2.5))
    }

    func testRoundTripsThroughEncoder() throws {
        let data = Data(#"{"nested":{"list":[1,"two",false,null]}}"#.utf8)
        let v = try JSONDecoder().decode(JSONValue.self, from: data)
        let encoded = try JSONEncoder().encode(v)
        let v2 = try JSONDecoder().decode(JSONValue.self, from: encoded)
        XCTAssertEqual(v, v2)
    }

    func testConvenienceAccessors() throws {
        let v = try JSONDecoder().decode(
            JSONValue.self,
            from: Data(#"{"s":"hi","n":3,"b":true,"arr":[{"k":"v"}]}"#.utf8))
        XCTAssertEqual(v["s"]?.stringValue, "hi")
        XCTAssertEqual(v["n"]?.doubleValue, 3)
        XCTAssertEqual(v["b"]?.boolValue, true)
        XCTAssertEqual(v["arr"]?.arrayValue?.first?["k"]?.stringValue, "v")
        XCTAssertNil(v["missing"])
    }
}
