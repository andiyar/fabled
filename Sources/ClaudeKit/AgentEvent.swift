public struct SystemInit: Sendable, Equatable {
    public let sessionID: String
    public let model: String
    public let cwd: String
    public let tools: [String]
    public let permissionMode: String
    public let slashCommands: [String]
    public let agents: [String]
    public let skills: [String]
    public let cliVersion: String
    public let raw: JSONValue
}

public enum AgentEvent: Sendable, Equatable {
    case systemInit(SystemInit)
    case system(subtype: String, raw: JSONValue)
    case assistant(AssistantMessage)
    case toolResult([ToolResult], parentToolUseID: String?)
    case result(TurnResult)
    case controlRequest(ControlRequest)
    case controlResponse(ControlResponseEnvelope)
    case streamEvent(StreamEvent)
    case unknown(type: String, raw: JSONValue)
    case terminated(exitCode: Int32)
}

public extension AgentEvent {
    /// Non-nil when the event belongs to a subagent (Task tool) side-stream.
    /// The three event types the CLI tags: assistant, stream_event, user.
    var parentToolUseID: String? {
        switch self {
        case .assistant(let message): message.parentToolUseID
        case .streamEvent(let stream): stream.parentToolUseID
        case .toolResult(_, let parent): parent
        default: nil
        }
    }
}

/// One `stream_event` line: an Anthropic SSE event wrapped with session
/// routing. Shape recorded 2026-07-09 (fixtures/2026-07-09-partial-messages.jsonl):
/// {"type":"stream_event","event":{…},"session_id":…,"parent_tool_use_id":…,"uuid":…}
public struct StreamEvent: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case messageStart
        case contentBlockStart(index: Int, block: ContentBlock)
        case textDelta(index: Int, text: String)
        case thinkingDelta(index: Int, thinking: String)
        case inputJSONDelta(index: Int, partialJSON: String)
        case contentBlockStop(index: Int)
        case messageDelta(stopReason: String?)
        case messageStop
        /// Tolerant fallback — signature_delta lands here today, and so will
        /// whatever the API adds next. Never a decode failure.
        case other(type: String)
    }

    public let kind: Kind
    public let sessionID: String?
    public let parentToolUseID: String?
    public let uuid: String?
    public let raw: JSONValue
}

public struct ControlRequest: Sendable, Equatable {
    public let requestID: String
    public let subtype: String
    public let payload: JSONValue
}

public struct ControlResponseEnvelope: Sendable, Equatable {
    public let requestID: String
    public let subtype: String
    public let payload: JSONValue?
    /// `response.error` on error acks — e.g. set_model's "not a recognized
    /// model id" (fixtures/2026-07-09-badmodel-ack.jsonl). nil on success.
    public let errorMessage: String?

    public init(requestID: String, subtype: String, payload: JSONValue?,
                errorMessage: String? = nil) {
        self.requestID = requestID
        self.subtype = subtype
        self.payload = payload
        self.errorMessage = errorMessage
    }
}

public struct PermissionRequest: Sendable, Equatable {
    public let requestID: String
    public let toolName: String
    public let displayName: String?
    public let input: JSONValue
    public let description: String?
    public let decisionReason: String?
    public let suggestions: [JSONValue]
    /// The tool_use block this request gates — present on interactive tools.
    public let toolUseID: String?
    /// True for AskUserQuestion/ExitPlanMode-style requests that want a
    /// dedicated UI, not an allow/deny prompt (probe finding 1).
    public let requiresUserInteraction: Bool

    public init?(_ request: ControlRequest) {
        guard request.subtype == "can_use_tool",
              let toolName = request.payload["tool_name"]?.stringValue else { return nil }
        self.requestID = request.requestID
        self.toolName = toolName
        self.displayName = request.payload["display_name"]?.stringValue
        self.input = request.payload["input"] ?? .null
        self.description = request.payload["description"]?.stringValue
        self.decisionReason = request.payload["decision_reason"]?.stringValue
        self.suggestions = request.payload["permission_suggestions"]?.arrayValue ?? []
        self.toolUseID = request.payload["tool_use_id"]?.stringValue
        self.requiresUserInteraction =
            request.payload["requires_user_interaction"]?.boolValue ?? false
    }
}

public enum ContentBlock: Sendable, Equatable {
    case text(String)
    case thinking(String)
    case toolUse(id: String, name: String, input: JSONValue)
    case unknown(type: String, raw: JSONValue)
}

public struct AssistantMessage: Sendable, Equatable {
    public let content: [ContentBlock]
    public let model: String?
    public let sessionID: String?
    public let parentToolUseID: String?
    public let raw: JSONValue
}

public struct ToolResult: Sendable, Equatable {
    public let toolUseID: String
    public let content: JSONValue
    public let isError: Bool
    /// The `user` line's structured `tool_use_result` payload (e.g. TaskCreate's
    /// `{"task":{"id":"1",…}}`). Only attached when the line carries exactly one
    /// tool_result block — the field is per-line, not per-block (probe finding 10).
    public let toolUseResult: JSONValue?

    public init(toolUseID: String, content: JSONValue, isError: Bool,
                toolUseResult: JSONValue? = nil) {
        self.toolUseID = toolUseID
        self.content = content
        self.isError = isError
        self.toolUseResult = toolUseResult
    }
}

public struct TurnResult: Sendable, Equatable {
    public let subtype: String
    public let isError: Bool
    public let durationMS: Double?
    public let totalCostUSD: Double?
    public let usage: JSONValue?
    public let permissionDenials: [JSONValue]
    public let raw: JSONValue
}
