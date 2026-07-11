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
}
