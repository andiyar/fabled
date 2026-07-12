import Testing
import ClaudeKit
@testable import FabledCore

/// The inspector's default face is a pure list of "everything that ran",
/// derived from the same timeline + subagent map the transcript uses. These
/// pin the row shape and ordering so the view is a dumb renderer.
struct ActivityListTests {
    @Test func liveToolBecomesALivePulsingRow() {
        let timeline: [TimelineItem] = [
            .toolCall(id: "1", name: "Bash", summary: "swift build", input: .null,
                      result: nil, isError: nil, isRunning: true)]
        let rows = ActivityList.rows(timeline: timeline, subagents: [:])
        #expect(rows.first?.isLive == true)
        #expect(rows.first?.kind == .live)
        #expect(rows.first?.title == "swift build" || rows.first?.title == "Bash")
        #expect(rows.first?.subtitle == "running")
    }

    @Test func subagentTaskBecomesAnAgentRowWithStepCount() {
        let timeline: [TimelineItem] = [
            .toolCall(id: "T", name: "Task", summary: "Explore", input: .null,
                      result: .string("done"), isError: false, isRunning: false)]
        let subs = ["T": [TimelineItem.assistantText(id: "s", markdown: "hi", isStreaming: false)]]
        let rows = ActivityList.rows(timeline: timeline, subagents: subs)
        #expect(rows.contains { $0.kind == .agent && $0.drillID == "T" })
    }

    @Test func liveRowsSortAboveFinished() {
        // one running + one finished tool → running row is first
        let timeline: [TimelineItem] = [
            .toolCall(id: "done", name: "Read", summary: "notes.md", input: .null,
                      result: .string("ok"), isError: false, isRunning: false),
            .toolCall(id: "run", name: "Bash", summary: "swift test", input: .null,
                      result: nil, isError: nil, isRunning: true)]
        let rows = ActivityList.rows(timeline: timeline, subagents: [:])
        #expect(rows.first?.isLive == true)
        #expect(rows.first?.drillID == "run")
        #expect(rows.count == 2)
    }

    // (a) a run of ≥3 finished Bash calls collapses to ONE row.
    @Test func runOfThreeFinishedCommandsCollapsesToOneRow() {
        let timeline: [TimelineItem] = (1...3).map { i in
            .toolCall(id: "b\(i)", name: "Bash", summary: "cmd \(i)", input: .null,
                      result: .string("ok"), isError: false, isRunning: false)
        }
        let rows = ActivityList.rows(timeline: timeline, subagents: [:])
        #expect(rows.count == 1)
        #expect(rows.first?.title == "Ran 3 commands")
        #expect(rows.first?.kind == .command)
        #expect(rows.first?.isLive == false)
        // The row drills into a real timeline id (the run's first tool).
        #expect(rows.first?.drillID == "b1")
    }

    // (b) an Edit tool row's subtitle carries +N −N.
    @Test func editRowSubtitleCarriesAddedRemoved() {
        let input: JSONValue = .object([
            "file_path": .string("/tmp/a.swift"),
            "old_string": .string("foo"),
            "new_string": .string("bar")])
        let timeline: [TimelineItem] = [
            .toolCall(id: "e", name: "Edit", summary: "/tmp/a.swift", input: input,
                      result: .string("ok"), isError: false, isRunning: false)]
        let rows = ActivityList.rows(timeline: timeline, subagents: [:])
        #expect(rows.count == 1)
        #expect(rows.first?.kind == .edit)
        // "foo" → "bar": one line removed, one added.
        #expect(rows.first?.subtitle == "+1 \u{2212}1")
    }

    // Non-tool timeline items (text, thinking, user turns) never become rows.
    @Test func nonToolItemsAreSkipped() {
        let timeline: [TimelineItem] = [
            .userMessage(id: "u", text: "hi"),
            .assistantText(id: "a", markdown: "sure", isStreaming: false),
            .thinking(id: "th", text: "hmm", isStreaming: false)]
        let rows = ActivityList.rows(timeline: timeline, subagents: [:])
        #expect(rows.isEmpty)
    }
}
