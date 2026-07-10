import XCTest
import ClaudeKit
@testable import FabledCore

final class DiffTests: XCTestCase {
    func testEqualStringsProduceOnlyContext() {
        let lines = Diff.lines(old: "a\nb", new: "a\nb")
        XCTAssertEqual(lines.map(\.kind), [.context, .context])
    }

    func testSimpleReplacement() {
        let lines = Diff.lines(old: "a\nb\nc", new: "a\nX\nc")
        XCTAssertEqual(lines.map(\.kind),
                       [.context, .deletion, .insertion, .context])
        XCTAssertEqual(lines[1].text, "b")
        XCTAssertEqual(lines[2].text, "X")
    }

    func testInsertionOnly() {
        let lines = Diff.lines(old: "a", new: "a\nb")
        XCTAssertEqual(lines.map(\.kind), [.context, .insertion])
    }

    func testDeletionOnly() {
        let lines = Diff.lines(old: "a\nb", new: "b")
        XCTAssertEqual(lines.map(\.kind), [.deletion, .context])
    }

    func testEmptyOldIsAllInsertions() {
        let lines = Diff.lines(old: "", new: "x\ny")
        XCTAssertEqual(lines.map(\.kind), [.insertion, .insertion])
    }

    func testCounts() {
        let lines = Diff.lines(old: "a\nb\nc", new: "a\nX\nY\nc")
        let counts = Diff.counts(lines)
        XCTAssertEqual(counts.added, 2)
        XCTAssertEqual(counts.removed, 1)
    }

    func testOversizeFallsBackToBlocks() {
        let old = Array(repeating: "same", count: 600).joined(separator: "\n")
        let new = old + "\nextra"
        let lines = Diff.lines(old: old, new: new)
        // Above the LCS cap the whole thing renders as delete-block + insert-block;
        // correctness (every line present) matters, minimality doesn't.
        XCTAssertEqual(lines.filter { $0.kind == .deletion }.count, 600)
        XCTAssertEqual(lines.filter { $0.kind == .insertion }.count, 601)
    }

    // MARK: ToolDiff extraction

    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    func testEditExtraction() throws {
        let input = try json(
            #"{"file_path":"/tmp/a.swift","old_string":"let x = 1","new_string":"let x = 2"}"#)
        let diff = try XCTUnwrap(ToolDiff.from(toolName: "Edit", input: input))
        XCTAssertEqual(diff.filePath, "/tmp/a.swift")
        XCTAssertEqual(diff.hunks.count, 1)
        XCTAssertEqual(diff.added, 1)
        XCTAssertEqual(diff.removed, 1)
    }

    func testWriteExtractionIsAllInsertions() throws {
        let input = try json(#"{"file_path":"/tmp/b.txt","content":"one\ntwo"}"#)
        let diff = try XCTUnwrap(ToolDiff.from(toolName: "Write", input: input))
        XCTAssertEqual(diff.added, 2)
        XCTAssertEqual(diff.removed, 0)
    }

    func testMultiEditExtractionOneHunkPerEdit() throws {
        let input = try json(
            #"{"file_path":"/tmp/c.swift","edits":[{"old_string":"a","new_string":"b"},{"old_string":"c\nd","new_string":"c"}]}"#)
        let diff = try XCTUnwrap(ToolDiff.from(toolName: "MultiEdit", input: input))
        XCTAssertEqual(diff.hunks.count, 2)
        // hunk 1: a→b = 1 deletion + 1 insertion; hunk 2: "c\nd"→"c" =
        // 1 context (c) + 1 deletion (d). Totals: +1 −2.
        XCTAssertEqual(diff.added, 1)
        XCTAssertEqual(diff.removed, 2)
    }

    func testNonDiffToolReturnsNil() throws {
        XCTAssertNil(ToolDiff.from(toolName: "Bash",
                                   input: try json(#"{"command":"ls"}"#)))
        XCTAssertNil(ToolDiff.from(toolName: "Edit", input: .null))
    }

    func testMultiEditSkipsMalformedEditsButKeepsRest() throws {
        let input = try json(
            #"{"file_path":"/tmp/d.swift","edits":[{"old_string":"a","new_string":"b"},{"not_an_edit":true}]}"#)
        let diff = try XCTUnwrap(ToolDiff.from(toolName: "MultiEdit", input: input))
        XCTAssertEqual(diff.hunks.count, 1, "malformed edits drop; valid ones survive")
        XCTAssertEqual(diff.added, 1)
        XCTAssertEqual(diff.removed, 1)
    }
}
