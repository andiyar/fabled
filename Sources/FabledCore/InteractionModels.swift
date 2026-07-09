import ClaudeKit

/// AskUserQuestion, parsed. Wraps the originating PermissionRequest — the
/// answer travels back as that request's allow response (probe finding 2).
public struct QuestionPrompt: Equatable, Sendable, Identifiable {
    public struct Option: Equatable, Sendable {
        public let label: String
        public let detail: String
    }
    public struct Question: Equatable, Sendable, Identifiable {
        public let text: String
        public let header: String
        public let multiSelect: Bool
        public let options: [Option]
        public var id: String { text }
    }

    public let request: PermissionRequest
    public let questions: [Question]
    public var id: String { request.requestID }

    public init?(_ request: PermissionRequest) {
        guard request.toolName == "AskUserQuestion",
              let rawQuestions = request.input["questions"]?.arrayValue,
              !rawQuestions.isEmpty else { return nil }
        self.request = request
        self.questions = rawQuestions.compactMap { raw in
            guard let text = raw["question"]?.stringValue else { return nil }
            return Question(
                text: text,
                header: raw["header"]?.stringValue ?? "",
                multiSelect: raw["multiSelect"]?.boolValue ?? false,
                options: (raw["options"]?.arrayValue ?? []).compactMap { option in
                    guard let label = option["label"]?.stringValue else { return nil }
                    return Option(label: label,
                                  detail: option["description"]?.stringValue ?? "")
                })
        }
        guard !questions.isEmpty else { return nil }
    }

    /// The allow payload: original input + answers keyed by exact question
    /// text; multi-select answers are ", "-joined by the caller. An empty
    /// record is the Skip path (probe finding 3) — omit `answers` entirely.
    public func answeredInput(_ answers: [String: String]) -> JSONValue {
        guard var object = request.input.objectValue else { return request.input }
        if !answers.isEmpty {
            object["answers"] = .object(answers.mapValues { .string($0) })
        }
        return .object(object)
    }
}

/// ExitPlanMode, parsed (probe finding 4).
public struct PlanApproval: Equatable, Sendable, Identifiable {
    public let request: PermissionRequest
    public let plan: String
    public let planFilePath: String?
    public var id: String { request.requestID }

    public init?(_ request: PermissionRequest) {
        guard request.toolName == "ExitPlanMode",
              let plan = request.input["plan"]?.stringValue else { return nil }
        self.request = request
        self.plan = plan
        self.planFilePath = request.input["planFilePath"]?.stringValue
    }
}

/// One TodoWrite entry (probe finding 10). The CLI re-sends the whole list
/// per call — latest list wins.
public struct TodoItem: Equatable, Sendable, Identifiable {
    public enum Status: Equatable, Sendable {
        case pending, inProgress, completed
    }
    public let content: String
    public let status: Status
    public let activeForm: String
    public var id: String { content }

    public static func list(from input: JSONValue) -> [TodoItem] {
        (input["todos"]?.arrayValue ?? []).compactMap { raw in
            guard let content = raw["content"]?.stringValue else { return nil }
            let status: Status = switch raw["status"]?.stringValue {
            case "completed": .completed
            case "in_progress": .inProgress
            default: .pending  // tolerant: unknown status renders as pending
            }
            return TodoItem(content: content, status: status,
                            activeForm: raw["activeForm"]?.stringValue ?? content)
        }
    }
}

/// One thing the CLI is waiting on the user for. Rendered in the composer
/// slot; arrival order preserved (first gate is the active card).
public enum InteractionGate: Equatable, Sendable, Identifiable {
    case permission(PermissionRequest)
    case question(QuestionPrompt)
    case planApproval(PlanApproval)

    public var requestID: String {
        switch self {
        case .permission(let request): request.requestID
        case .question(let prompt): prompt.request.requestID
        case .planApproval(let approval): approval.request.requestID
        }
    }
    public var id: String { requestID }
}
