import XCTest
import ClaudeKit
@testable import FabledCore

final class TimelineDisplayTests: XCTestCase {
    private func tool(_ id: String, name: String = "Bash",
                      running: Bool = false, error: Bool? = false) -> TimelineItem {
        .toolCall(id: id, name: name, summary: "s", input: .object([:]),
                  result: running ? nil : .string("ok"),
                  isError: error, isRunning: running)
    }
    private func text(_ id: String) -> TimelineItem {
        .assistantText(id: id, markdown: "hi", isStreaming: false)
    }

    func testRunOfThreeCollapses() {
        let rows = TimelineDisplay.grouped(
            [text("a"), tool("t1"), tool("t2"), tool("t3"), text("b")])
        XCTAssertEqual(rows.count, 3)
        guard case .toolGroup(let id, let items, let summary) = rows[1] else {
            return XCTFail("expected group, got \(rows)")
        }
        XCTAssertEqual(id, "t1", "group id = first item id (stable)")
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(summary, "Ran 3 commands")
    }

    func testRunOfTwoStaysFlat() {
        let rows = TimelineDisplay.grouped([tool("t1"), tool("t2")])
        XCTAssertEqual(rows.count, 2)
        for row in rows {
            guard case .item = row else { return XCTFail("no grouping under 3") }
        }
    }

    func testRunningToolBreaksTheRun() {
        let rows = TimelineDisplay.grouped(
            [tool("t1"), tool("t2"), tool("t3", running: true)])
        XCTAssertEqual(rows.count, 3, "live tail stays visible")
    }

    func testErrorBreaksTheRun() {
        let rows = TimelineDisplay.grouped(
            [tool("t1"), tool("t2", error: true), tool("t3"), tool("t4"), tool("t5")])
        // t1 alone, t2 visible error, t3–t5 group.
        XCTAssertEqual(rows.count, 3)
        guard case .toolGroup(_, let items, _) = rows[2] else {
            return XCTFail("expected trailing group, got \(rows)")
        }
        XCTAssertEqual(items.map(\.id), ["t3", "t4", "t5"])
    }

    func testTaskAnchorsNeverGroup() {
        let rows = TimelineDisplay.grouped(
            [tool("t1"), tool("t2", name: "Task"), tool("t3"), tool("t4"), tool("t5")])
        XCTAssertEqual(rows.count, 3, "Task splits: t1 | Task | t3-t5 group")
        guard case .item(let item) = rows[1], item.id == "t2" else {
            return XCTFail("Task row must render alone, got \(rows)")
        }
    }

    func testSummariesByToolMix() {
        func summaryOf(_ names: [String]) -> String {
            let items = names.enumerated().map { tool("x\($0.offset)", name: $0.element) }
            guard case .toolGroup(_, _, let summary) = TimelineDisplay.grouped(items).first
            else { XCTFail("expected group"); return "" }
            return summary
        }
        XCTAssertEqual(summaryOf(["Bash", "Bash", "Bash"]), "Ran 3 commands")
        XCTAssertEqual(summaryOf(["Edit", "Write", "MultiEdit"]), "Edited 3 files")
        XCTAssertEqual(summaryOf(["Read", "Read", "Read", "Read"]), "4 × Read")
        XCTAssertEqual(summaryOf(["Read", "Bash", "Edit"]), "3 steps")
    }

    // MARK: - Row identity + run-breaking (T13 review rider)

    func testRowIDsArePrefixed() {
        // A grouped run's row id is namespaced so it can't collide with a
        // plain item that happens to share the first tool's id.
        let grouped = TimelineDisplay.grouped([tool("t1"), tool("t2"), tool("t3")])
        XCTAssertEqual(grouped.count, 1)
        XCTAssertEqual(grouped[0].id, "group-t1")
        // A plain item row keeps the item's own id verbatim.
        let plain = TimelineDisplay.grouped([text("a")])
        XCTAssertEqual(plain[0].id, "a")
    }

    func testGroupIDStableAsRunGrows() {
        func firstGroupID(_ items: [TimelineItem]) -> String? {
            guard case .toolGroup(let id, _, _) = TimelineDisplay.grouped(items).first
            else { return nil }
            return id
        }
        // Appending a 4th tool to a run must not shift the group's identity —
        // it stays anchored on the first item so SwiftUI keeps the row.
        XCTAssertEqual(firstGroupID([tool("t1"), tool("t2"), tool("t3")]), "t1")
        XCTAssertEqual(firstGroupID([tool("t1"), tool("t2"), tool("t3"), tool("t4")]), "t1")
    }

    func testThinkingBreaksRun() {
        let thinking = TimelineItem.thinking(id: "th", text: "x", isStreaming: false)
        // Without the thinking line, six tools collapse into ONE group; the
        // thinking item between them must split the run into two groups.
        let rows = TimelineDisplay.grouped(
            [tool("t1"), tool("t2"), tool("t3"), thinking,
             tool("t4"), tool("t5"), tool("t6")])
        XCTAssertEqual(rows.count, 3, "thinking splits: group | thinking | group")
        guard case .toolGroup(let firstID, _, _) = rows[0] else {
            return XCTFail("expected leading group, got \(rows)")
        }
        XCTAssertEqual(firstID, "t1")
        guard case .item(let mid) = rows[1], mid.id == "th" else {
            return XCTFail("thinking must render alone, got \(rows)")
        }
        guard case .toolGroup(let lastID, _, _) = rows[2] else {
            return XCTFail("expected trailing group, got \(rows)")
        }
        XCTAssertEqual(lastID, "t4")
    }
}
