import XCTest
@testable import FabledCore

final class ModelOptionTests: XCTestCase {
    /// Two catalog aliases both resolving to "claude-opus-4-8[1m]" must dedupe
    /// the hardcoded claude-opus-4-8 known model via [1m] normalization, while
    /// the other known models are appended after the catalog entries.
    func testMergedDedupesLongContextSuffixAndAppendsRest() {
        let catalog = [
            ModelOption(value: "opus", resolvedModel: "claude-opus-4-8[1m]",
                        displayName: "Opus", optionDescription: nil),
            ModelOption(value: "default", resolvedModel: "claude-opus-4-8[1m]",
                        displayName: "Default", optionDescription: nil),
        ]

        let merged = ModelOption.merged(catalog: catalog)
        let values = merged.map(\.value)

        // Catalog entries come first and unchanged.
        XCTAssertEqual(Array(values.prefix(2)), ["opus", "default"])

        // claude-opus-4-8 deduped away (same base model as "[1m]" catalog ids).
        XCTAssertFalse(values.contains("claude-opus-4-8"))

        // Remaining known models still present.
        XCTAssertTrue(values.contains("claude-opus-4-7"))
        XCTAssertTrue(values.contains("claude-sonnet-4-6"))
        XCTAssertTrue(values.contains("claude-fable-5"))
        XCTAssertTrue(values.contains("claude-sonnet-5"))
        XCTAssertTrue(values.contains("claude-opus-4-6"))
        XCTAssertTrue(values.contains("claude-haiku-4-5"))

        // Six of the seven known models survive (opus-4-8 deduped).
        XCTAssertEqual(merged.count, catalog.count + ModelOption.knownModels.count - 1)
    }

    func testMergedWithEmptyCatalogReturnsAllKnownModels() {
        let merged = ModelOption.merged(catalog: [])
        XCTAssertEqual(merged.map(\.value), ModelOption.knownModels.map(\.value))
        XCTAssertEqual(merged.count, 7)
    }
}
