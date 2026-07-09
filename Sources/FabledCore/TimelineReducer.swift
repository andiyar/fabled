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
        case .controlRequest(let request):
            if let permission = PermissionRequest(request) {
                items.append(.permission(id: permission.requestID,
                                         request: permission, resolution: nil))
            }
            // Non-permission control requests (hook_callback, mcp_message)
            // are plumbing, not conversation — Plan 4 decides their UI.
        case .result(let turn):
            finalizeDanglingStreamText(&items)
            items.append(.turnSummary(
                id: turn.raw["uuid"]?.stringValue ?? "turn-\(items.count)",
                result: turn))
        case .unknown(let type, let raw):
            items.append(.raw(id: raw["uuid"]?.stringValue ?? "raw-\(items.count)",
                              type: type, raw: raw))
        case .terminated(let exitCode):
            finalizeDanglingStreamText(&items)
            items.append(.notice(
                id: "terminated",
                text: exitCode == 0
                    ? "Session ended."
                    : "Session ended unexpectedly (exit code \(exitCode))."))
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

    /// Records the user's decision on the matching (unresolved) card.
    /// A local action, not a protocol event — the CLI never echoes it.
    public static func resolvePermission(
        _ items: [TimelineItem], requestID: String, decision: PermissionDecision
    ) -> [TimelineItem] {
        items.map { item in
            if case .permission(let id, let request, nil) = item, id == requestID {
                return .permission(id: id, request: request, resolution: decision)
            }
            return item
        }
    }

    /// Read-only history: an on-disk transcript rendered through the same
    /// vocabulary. Main-chain only — sidechain (subagent) traffic, titles,
    /// and bookkeeping lines are not conversation.
    public static func items(fromTranscript entries: [TranscriptEntry]) -> [TimelineItem] {
        var items: [TimelineItem] = []
        var lineIndex = 0
        for entry in entries {
            lineIndex += 1
            switch entry {
            case .userPrompt(let text, let context, _):
                guard !context.isSidechain, !context.isMeta else { continue }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                // Machine-generated prompts (<command-name>…, caveats) are
                // not conversation; same rule as title derivation.
                guard !trimmed.isEmpty, !trimmed.hasPrefix("<") else { continue }
                items = appendUserMessage(items, id: context.uuid ?? "line-\(lineIndex)", text: text)
            case .event(let event, let context):
                guard !context.isSidechain else { continue }
                items = reduce(items, event)
            case .title, .summary, .queueOperation, .attachment, .sessionMeta, .unknown:
                continue
            }
        }
        return items
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

    /// A turn that ends without a finalizing assistant message (interrupt,
    /// error mid-stream) must not leave a streaming item for the next
    /// turn's deltas to coalesce onto.
    private static func finalizeDanglingStreamText(_ items: inout [TimelineItem]) {
        if case .assistantText(let id, let markdown, true) = items.last {
            items[items.count - 1] = .assistantText(id: id, markdown: markdown, isStreaming: false)
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
