import XCTest
import ClaudeKit
@testable import FabledCore

final class TaskChecklistTests: XCTestCase {
    private func input(_ json: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    func testCreateAssignsIDFromStructuredResult() throws {
        var checklist = TaskChecklist()
        checklist.noteToolUse(id: "toolu_1", name: "TaskCreate",
                              input: try input(#"{"subject":"Alpha task","description":"d","activeForm":"Alpha running"}"#))
        XCTAssertEqual(checklist.items.count, 1)
        XCTAssertNil(checklist.items[0].taskID, "provisional until the result lands")
        XCTAssertEqual(checklist.items[0].subject, "Alpha task")
        XCTAssertEqual(checklist.items[0].status, .pending)
        checklist.noteResult(ToolResult(
            toolUseID: "toolu_1",
            content: .string("Task #1 created successfully: Alpha task"),
            isError: false,
            toolUseResult: try input(#"{"task":{"id":"1","subject":"Alpha task"}}"#)))
        XCTAssertEqual(checklist.items[0].taskID, "1")
    }

    func testCreateFallsBackToResultTextParsing() throws {
        // tool_use_result is dropped on multi-result lines (T1) — the text
        // "Task #N created successfully: …" still carries the id.
        var checklist = TaskChecklist()
        checklist.noteToolUse(id: "toolu_1", name: "TaskCreate",
                              input: try input(#"{"subject":"Beta task","description":"d"}"#))
        checklist.noteResult(ToolResult(
            toolUseID: "toolu_1",
            content: .string("Task #7 created successfully: Beta task"),
            isError: false))
        XCTAssertEqual(checklist.items[0].taskID, "7")
    }

    func testUpdateAppliesOnMatchingResult() throws {
        var checklist = TaskChecklist()
        checklist.noteToolUse(id: "toolu_1", name: "TaskCreate",
                              input: try input(#"{"subject":"Alpha task","description":"d"}"#))
        checklist.noteResult(ToolResult(
            toolUseID: "toolu_1",
            content: .string("Task #1 created successfully: Alpha task"), isError: false,
            toolUseResult: try input(#"{"task":{"id":"1"}}"#)))
        checklist.noteToolUse(id: "toolu_2", name: "TaskUpdate",
                              input: try input(#"{"taskId":"1","status":"in_progress"}"#))
        // Not yet applied — the CLI hasn't confirmed.
        XCTAssertEqual(checklist.items[0].status, .pending)
        checklist.noteResult(ToolResult(
            toolUseID: "toolu_2", content: .string("Updated task #1 status"), isError: false))
        XCTAssertEqual(checklist.items[0].status, .inProgress)
    }

    func testErroredUpdateDoesNotApply() throws {
        var checklist = TaskChecklist()
        checklist.noteToolUse(id: "toolu_1", name: "TaskCreate",
                              input: try input(#"{"subject":"Alpha task","description":"d"}"#))
        checklist.noteResult(ToolResult(
            toolUseID: "toolu_1",
            content: .string("Task #1 created successfully: Alpha task"), isError: false,
            toolUseResult: try input(#"{"task":{"id":"1"}}"#)))
        checklist.noteToolUse(id: "toolu_2", name: "TaskUpdate",
                              input: try input(#"{"taskId":"1","status":"completed"}"#))
        checklist.noteResult(ToolResult(
            toolUseID: "toolu_2", content: .string("Task not found"), isError: true))
        XCTAssertEqual(checklist.items[0].status, .pending)
    }

    func testDeleteRemovesItem() throws {
        var checklist = TaskChecklist()
        checklist.noteToolUse(id: "toolu_1", name: "TaskCreate",
                              input: try input(#"{"subject":"Gamma task","description":"d"}"#))
        checklist.noteResult(ToolResult(
            toolUseID: "toolu_1",
            content: .string("Task #3 created successfully: Gamma task"), isError: false,
            toolUseResult: try input(#"{"task":{"id":"3"}}"#)))
        checklist.noteToolUse(id: "toolu_2", name: "TaskUpdate",
                              input: try input(#"{"taskId":"3","status":"deleted"}"#))
        checklist.noteResult(ToolResult(
            toolUseID: "toolu_2", content: .string("Updated task #3 deleted"), isError: false))
        XCTAssertTrue(checklist.items.isEmpty)
    }

    func testTaskListResultReconcilesFullState() throws {
        var checklist = TaskChecklist()
        checklist.noteToolUse(id: "toolu_9", name: "TaskList", input: .object([:]))
        checklist.noteResult(ToolResult(
            toolUseID: "toolu_9",
            content: .string("#1 [completed] Alpha task\n#2 [pending] Beta task"),
            isError: false))
        XCTAssertEqual(checklist.items.map(\.taskID), ["1", "2"])
        XCTAssertEqual(checklist.items.map(\.status), [.completed, .pending])
        XCTAssertEqual(checklist.items.map(\.subject), ["Alpha task", "Beta task"])
    }

    func testUnrelatedToolsAreIgnored() throws {
        var checklist = TaskChecklist()
        checklist.noteToolUse(id: "toolu_1", name: "Bash",
                              input: try input(#"{"command":"ls"}"#))
        checklist.noteResult(ToolResult(toolUseID: "toolu_1",
                                        content: .string("x"), isError: false))
        XCTAssertTrue(checklist.items.isEmpty)
    }
}
