import XCTest
import Testing
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

    func testThinkingIsAbsorbedIntoRun() {
        let thinking = TimelineItem.thinking(id: "th", text: "x", isStreaming: false)
        // New row-25 contract: interior thinking no longer splits a run.
        let rows = TimelineDisplay.grouped(
            [tool("t1"), tool("t2"), tool("t3"), thinking,
             tool("t4"), tool("t5"), tool("t6")])
        XCTAssertEqual(rows.count, 1, "thinking is absorbed; the six tools stay one group")
        guard case .toolGroup(let id, let items, let summary) = rows[0] else {
            return XCTFail("expected one group, got \(rows)")
        }
        XCTAssertEqual(id, "t1")
        XCTAssertEqual(items.filter { $0.toolCallID != nil }.count, 6)
        XCTAssertEqual(summary, "Ran 6 commands")
    }
}

struct TimelineDisplayGroupingTests {
    private func tool(_ id: String, _ name: String) -> TimelineItem {
        .toolCall(id: id, name: name, summary: name, input: .null,
                  result: .string("ok"), isError: false, isRunning: false)
    }
    private func thinking(_ id: String) -> TimelineItem { .thinking(id: id, text: "…", isStreaming: false) }

    // Build a PermissionRequest via the decoder (no memberwise init exists).
    private func permission(_ id: String, _ resolution: PermissionDecision?) throws -> TimelineItem {
        let json = #"{"type":"control_request","request_id":"\#(id)","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"echo hi"}}}"#
        let event = try AgentEventDecoder.decode(Data(json.utf8))
        guard case .controlRequest(let control) = event, let req = PermissionRequest(control) else {
            fatalError("fixture shape drifted")
        }
        return .permission(id: id, request: req, resolution: resolution)
    }

    @Test func thinkingBetweenToolsDoesNotBreakTheRun() {
        let items = [thinking("t1"), tool("a","Read"), thinking("t2"),
                     tool("b","Read"), thinking("t3"), tool("c","Read")]
        let rows = TimelineDisplay.grouped(items)
        #expect(rows.count == 1)                        // one group; interior + leading thinking absorbed
        guard case .toolGroup(let id, let grouped, let summary) = rows[0] else {
            Issue.record("expected a group"); return
        }
        #expect(id == "a")   // anchors on the first real tool, not the leading thinking "t1"
        #expect(summary == "3 × Read")
        #expect(grouped.filter { $0.toolCallID != nil }.count == 3)
    }

    @Test func trailingThinkingStaysOutsideTheGroup() {
        let items = [tool("a","Bash"), tool("b","Bash"), tool("c","Bash"), thinking("t")]
        let rows = TimelineDisplay.grouped(items)
        #expect(rows.count == 2)                          // group, then loose thinking
        if case .item(let last) = rows[1] { #expect(last.id == "t") }
        else { Issue.record("thinking should be a loose item") }
    }

    @Test func assistantTextStillBreaksTheRun() {
        let items = [tool("a","Read"), .assistantText(id: "x", markdown: "Now…", isStreaming: false),
                     tool("b","Read"), tool("c","Read")]
        let rows = TimelineDisplay.grouped(items)
        #expect(!rows.contains { if case .toolGroup = $0 { return true } else { return false } })
    }

    @Test func resolvedAllowPermissionIsTransparentButDenyBreaks() throws {
        // allow-gated run of 3 collapses (permission absorbed)
        let allow = try [tool("a","Bash"), tool("b","Bash"),
                         permission("p", .allowAsRequested), tool("c","Bash")]
        let allowRows = TimelineDisplay.grouped(allow)
        #expect(allowRows.filter { if case .toolGroup = $0 { return true } else { return false } }.count == 1)
        // a deny between tools is a hard break → no group forms
        let deny = try [tool("a","Bash"), tool("b","Bash"),
                        permission("p", .deny(message: nil)), tool("c","Bash")]
        let denyRows = TimelineDisplay.grouped(deny)
        #expect(!denyRows.contains { if case .toolGroup = $0 { return true } else { return false } })
        #expect(denyRows.contains { if case .item(let i) = $0, case .permission = i { return true } else { return false } })
        // a pending (unresolved) permission is also a hard break → the prompt
        // must never hide inside a collapsed group.
        let pending = try [tool("a","Bash"), tool("b","Bash"),
                           permission("p", nil), tool("c","Bash")]
        let pendingRows = TimelineDisplay.grouped(pending)
        #expect(!pendingRows.contains { if case .toolGroup = $0 { return true } else { return false } })
        #expect(pendingRows.contains { if case .item(let i) = $0, case .permission = i { return true } else { return false } })
    }
}
