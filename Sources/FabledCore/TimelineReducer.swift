import ClaudeKit

/// Pure translation from protocol events to UI items. This is where
/// correctness lives — every behavior is replay-tested against recorded
/// fixtures.
public enum TimelineReducer {
    public static func reduce(_ items: [TimelineItem], _ event: AgentEvent) -> [TimelineItem] {
        var items = items
        switch event {
        case .streamEvent(let stream):
            reduceStream(&items, stream)
        case .assistant(let message):
            reduceAssistant(&items, message)
        case .toolResult(let results):
            // Empty lists (synthetic user lines: interrupts, local-command
            // echoes) fall through harmlessly — nothing matches.
            for result in results { fillToolResult(&items, result) }
        case .systemInit, .system, .controlResponse:
            break  // ChatSession consumes these; nothing renders inline.
        case .controlRequest, .result, .unknown, .terminated:
            break  // Task 6 extends these.
        }
        return items
    }

    /// Local echo for a message the user just sent (the CLI does not echo
    /// prompts back on the live stream).
    public static func appendUserMessage(
        _ items: [TimelineItem], id: String, text: String
    ) -> [TimelineItem] {
        items + [.userMessage(id: id, text: text)]
    }

    // MARK: - Streaming deltas

    private static func reduceStream(_ items: inout [TimelineItem], _ stream: StreamEvent) {
        guard stream.parentToolUseID == nil else { return }  // subagent traffic: Plan 4
        switch stream.kind {
        case .contentBlockStart(_, .toolUse(let id, let name, let input)):
            upsertToolCall(&items, id: id, name: name, input: input)
        case .textDelta(_, let text):
            if case .assistantText(let id, let markdown, true) = items.last {
                items[items.count - 1] = .assistantText(
                    id: id, markdown: markdown + text, isStreaming: true)
            } else {
                items.append(.assistantText(
                    id: stream.uuid ?? "stream-\(items.count)",
                    markdown: text, isStreaming: true))
            }
        case .messageStart, .contentBlockStart, .thinkingDelta, .inputJSONDelta,
             .contentBlockStop, .messageDelta, .messageStop, .other:
            break  // thinking state lives on ChatSession; partial tool input is Plan 4.
        }
    }

    // MARK: - Final assistant messages

    private static func reduceAssistant(_ items: inout [TimelineItem], _ message: AssistantMessage) {
        guard message.parentToolUseID == nil else { return }
        let baseID = message.raw["uuid"]?.stringValue ?? "assistant-\(items.count)"
        var textIndex = 0
        for block in message.content {
            switch block {
            case .text(let text):
                guard !text.isEmpty else { break }
                finalizeText(&items, text: text, fallbackID: "\(baseID)-\(textIndex)")
                textIndex += 1
            case .toolUse(let id, let name, let input):
                upsertToolCall(&items, id: id, name: name, input: input)
            case .thinking, .unknown:
                break
            }
        }
    }

    /// The final message replaces streamed provisional text in place — same
    /// item id, so SwiftUI sees an update, not a remove+insert.
    private static func finalizeText(_ items: inout [TimelineItem], text: String, fallbackID: String) {
        if case .assistantText(let id, _, true) = items.last {
            items[items.count - 1] = .assistantText(id: id, markdown: text, isStreaming: false)
        } else {
            items.append(.assistantText(id: fallbackID, markdown: text, isStreaming: false))
        }
    }

    // MARK: - Tool calls

    private static func upsertToolCall(
        _ items: inout [TimelineItem], id: String, name: String, input: JSONValue
    ) {
        let summary = ToolCallSummary.summarize(name: name, input: input)
        if let index = items.lastIndex(where: { $0.toolCallID == id }) {
            guard case .toolCall(_, _, _, _, let result, let isError, let isRunning) = items[index]
            else { return }
            items[index] = .toolCall(id: id, name: name, summary: summary, input: input,
                                     result: result, isError: isError, isRunning: isRunning)
        } else {
            items.append(.toolCall(id: id, name: name, summary: summary, input: input,
                                   result: nil, isError: nil, isRunning: true))
        }
    }

    private static func fillToolResult(_ items: inout [TimelineItem], _ result: ToolResult) {
        guard let index = items.lastIndex(where: { $0.toolCallID == result.toolUseID }),
              case .toolCall(let id, let name, let summary, let input, _, _, _) = items[index]
        else { return }
        items[index] = .toolCall(id: id, name: name, summary: summary, input: input,
                                 result: result.content, isError: result.isError,
                                 isRunning: false)
    }
}
