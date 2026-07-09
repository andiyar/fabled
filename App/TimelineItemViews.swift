import SwiftUI
import ClaudeKit
import FabledCore

/// One timeline row. `session` is nil in read-only history.
struct TimelineItemView: View {
    let item: TimelineItem
    let session: ChatSession?

    var body: some View {
        switch item {
        case .userMessage(_, let text):
            UserBubble(text: text)
        case .assistantText(_, let markdown, let isStreaming):
            AssistantTextView(markdown: markdown, isStreaming: isStreaming)
        case .toolCall(_, let name, let summary, let input, let result, let isError, let isRunning):
            ToolCallCard(name: name, summary: summary, input: input,
                         result: result, isError: isError, isRunning: isRunning)
        case .permission(_, let request, let resolution):
            // Static status row — the interactive card renders in ComposerView while pending.
            PermissionStatusView(request: request, resolution: resolution)
        case .turnSummary(_, let result):
            TurnSummaryView(result: result)
        case .notice(_, let text):
            NoticeView(text: text)
        case .raw(_, let type, let raw):
            RawEventView(type: type, raw: raw)
        }
    }
}

struct UserBubble: View {
    let text: String
    var body: some View {
        HStack {
            Spacer(minLength: 48)
            Text(text)
                .textSelection(.enabled)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.quaternary.opacity(0.6),
                            in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct AssistantTextView: View {
    let markdown: String
    let isStreaming: Bool

    var body: some View {
        Text(attributed)
            .font(Theme.assistantFont())
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(isStreaming ? 0.85 : 1)
    }

    private var attributed: AttributedString {
        // Ledgered decision: AttributedString first, no markdown package.
        (try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(markdown)
    }
}

struct ToolCallCard: View {
    let name: String
    let summary: String
    let input: JSONValue
    let result: JSONValue?
    let isError: Bool?
    let isRunning: Bool
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                if input != .object([:]), input != .null {
                    Text(String(JSONPretty.string(input).prefix(4000)))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                if let result {
                    Divider()
                    Text(String(JSONPretty.string(result).prefix(4000)))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(isError == true ? Color.red : Color.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(.top, 4)
        } label: {
            HStack(spacing: 6) {
                statusIcon
                Text(name).fontWeight(.medium)
                Text(summary).foregroundStyle(.secondary).lineLimit(1)
            }
            .font(.callout)
        }
        .padding(8)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private var statusIcon: some View {
        if isRunning {
            ProgressView().controlSize(.small)
        } else if isError == true {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        } else {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        }
    }
}

struct PermissionStatusView: View {
    let request: PermissionRequest
    let resolution: PermissionDecision?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield")
            Text(PermissionPrompt.commandSummary(for: request))
                .font(.system(.callout, design: .monospaced)).lineLimit(1)
            Spacer()
            switch resolution {
            case .allow: Text("Allowed").foregroundStyle(.green)
            case .deny: Text("Denied").foregroundStyle(.red)
            case nil: Text("Awaiting approval").foregroundStyle(.orange)
            }
        }
        .font(.callout)
        .padding(8)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct TurnSummaryView: View {
    let result: TurnResult
    var body: some View {
        HStack(spacing: 8) {
            if result.isError {
                Text(result.subtype.replacingOccurrences(of: "_", with: " "))
                    .foregroundStyle(.orange)
            }
            if let cost = result.totalCostUSD {
                Text(String(format: "$%.4f", cost))
            }
            if let ms = result.durationMS {
                Text(String(format: "%.1fs", ms / 1000))
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct NoticeView: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 4)
    }
}

struct RawEventView: View {
    let type: String
    let raw: JSONValue
    @State private var isExpanded = false
    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(String(JSONPretty.string(raw).prefix(4000)))
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
        } label: {
            Label(type, systemImage: "questionmark.square.dashed")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(6)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
    }
}
