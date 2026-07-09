import XCTest
import ClaudeKit
@testable import FabledCore

final class InteractionModelTests: XCTestCase {
    private func permissionRequest(fixture: String) throws -> PermissionRequest {
        let events = try CoreFixtures.events(fixture)
        let request = events.compactMap { event -> PermissionRequest? in
            if case .controlRequest(let control) = event { return PermissionRequest(control) }
            return nil
        }.first
        return try XCTUnwrap(request)
    }

    func testQuestionPromptParsesFixture() throws {
        let request = try permissionRequest(fixture: "2026-07-09-askuserquestion-answer.jsonl")
        let prompt = try XCTUnwrap(QuestionPrompt(request))
        XCTAssertEqual(prompt.questions.count, 2)
        XCTAssertEqual(prompt.questions[0].text, "Which color do you prefer?")
        XCTAssertEqual(prompt.questions[0].header, "Color")
        XCTAssertFalse(prompt.questions[0].multiSelect)
        XCTAssertEqual(prompt.questions[0].options.map(\.label), ["Red", "Blue"])
        XCTAssertEqual(prompt.questions[0].options[0].detail, "The color red")
        XCTAssertTrue(prompt.questions[1].multiSelect)
    }

    func testQuestionPromptRejectsOtherTools() throws {
        let request = try permissionRequest(fixture: "2026-07-09-exitplanmode-approve.jsonl")
        // First can_use_tool in that fixture is Bash — definitely not a question.
        XCTAssertNil(QuestionPrompt(request))
    }

    /// The answer payload is the request input + answers keyed by question
    /// text, multi-select joined with ", " (probe finding 2).
    func testAnsweredInputShape() throws {
        let request = try permissionRequest(fixture: "2026-07-09-askuserquestion-answer.jsonl")
        let prompt = try XCTUnwrap(QuestionPrompt(request))
        let updated = prompt.answeredInput([
            "Which color do you prefer?": "Blue",
            "Which sizes do you want?": "Small, Large",
        ])
        XCTAssertEqual(updated["questions"], request.input["questions"])
        XCTAssertEqual(updated["answers"]?["Which color do you prefer?"]?.stringValue, "Blue")
        XCTAssertEqual(updated["answers"]?["Which sizes do you want?"]?.stringValue, "Small, Large")
    }

    func testPlanApprovalParsesFixture() throws {
        let events = try CoreFixtures.events("2026-07-09-exitplanmode-approve.jsonl")
        let approval = events.compactMap { event -> PlanApproval? in
            guard case .controlRequest(let control) = event,
                  let request = PermissionRequest(control) else { return nil }
            return PlanApproval(request)
        }.first
        let unwrapped = try XCTUnwrap(approval)
        XCTAssertTrue(unwrapped.plan.hasPrefix("# Plan:"))
        XCTAssertNotNil(unwrapped.planFilePath)
    }

    func testPlanApprovalRejectsOtherTools() throws {
        let request = try permissionRequest(fixture: "2026-07-09-askuserquestion-answer.jsonl")
        XCTAssertNil(PlanApproval(request))
    }

    func testTodoItemsParse() throws {
        let input = try JSONDecoder().decode(JSONValue.self, from: Data(
            #"{"todos":[{"content":"Write tests","status":"completed","activeForm":"Writing tests"},{"content":"Implement","status":"in_progress","activeForm":"Implementing"},{"content":"Commit","status":"pending","activeForm":"Committing"}]}"#
            .utf8))
        let todos = TodoItem.list(from: input)
        XCTAssertEqual(todos.count, 3)
        XCTAssertEqual(todos[0].status, .completed)
        XCTAssertEqual(todos[1].status, .inProgress)
        XCTAssertEqual(todos[1].activeForm, "Implementing")
        XCTAssertEqual(todos[2].status, .pending)
    }

    func testTodoUnknownStatusIsPending() throws {
        let input = try JSONDecoder().decode(JSONValue.self, from: Data(
            #"{"todos":[{"content":"x","status":"someday","activeForm":"x"}]}"#.utf8))
        XCTAssertEqual(TodoItem.list(from: input).first?.status, .pending)
    }

    // MARK: summaries

    func testSummaries() throws {
        let question = try JSONDecoder().decode(JSONValue.self, from: Data(
            #"{"questions":[{"question":"Which color?","header":"Color","options":[],"multiSelect":false}]}"#.utf8))
        XCTAssertEqual(ToolCallSummary.summarize(name: "AskUserQuestion", input: question),
                       "Which color?")
        let plan = try JSONDecoder().decode(JSONValue.self, from: Data(
            ##"{"plan":"# Add README\nmore"}"##.utf8))
        XCTAssertEqual(ToolCallSummary.summarize(name: "ExitPlanMode", input: plan),
                       "# Add README")
        let todos = try JSONDecoder().decode(JSONValue.self, from: Data(
            #"{"todos":[{"content":"a","status":"completed","activeForm":"a"},{"content":"b","status":"pending","activeForm":"b"}]}"#.utf8))
        XCTAssertEqual(ToolCallSummary.summarize(name: "TodoWrite", input: todos),
                       "1/2 done")
    }
}
