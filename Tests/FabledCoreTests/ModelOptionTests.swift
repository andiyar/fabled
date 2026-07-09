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

        // All but one known model survives (opus-4-8 deduped).
        XCTAssertEqual(merged.count, catalog.count + ModelOption.knownModels.count - 1)
    }

    /// A catalog entry whose resolvedModel is the dated Opus 4.5 id
    /// ("claude-opus-4-5-20251101") must dedupe the known "claude-opus-4-5"
    /// alias even though the alias value never matches the dated id — merge
    /// dedupes on the known entry's resolvedModel as well as its value.
    func testMergedDedupesKnownAliasAgainstCatalogResolvedId() {
        let catalog = [
            ModelOption(value: "opus-4-5", resolvedModel: "claude-opus-4-5-20251101",
                        displayName: "Opus 4.5", optionDescription: nil),
        ]

        let merged = ModelOption.merged(catalog: catalog)
        let values = merged.map(\.value)

        // The known claude-opus-4-5 alias is dropped, no duplicate 4.5 row.
        XCTAssertFalse(values.contains("claude-opus-4-5"))
        XCTAssertEqual(values.filter { $0 == "opus-4-5" }.count, 1)

        // Other known models still appended.
        XCTAssertTrue(values.contains("claude-opus-4-6"))
        XCTAssertTrue(values.contains("claude-fable-5"))

        // One known model deduped away.
        XCTAssertEqual(merged.count, catalog.count + ModelOption.knownModels.count - 1)
    }

    func testMergedWithEmptyCatalogReturnsAllKnownModels() {
        let merged = ModelOption.merged(catalog: [])
        XCTAssertEqual(merged.map(\.value), ModelOption.knownModels.map(\.value))
        XCTAssertEqual(merged.count, 8)
    }
}
