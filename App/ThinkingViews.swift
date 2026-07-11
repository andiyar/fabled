import SwiftUI
import FabledCore

/// A thinking row: dimmed, italic, deliberately quiet. While streaming it
/// shows a live tail of the thought (perceived activation — Ben's FASTER
/// directive); finalized it collapses to one summary line. Full text opens
/// in the inspector (no per-row expansion @State — 4a scar).
struct ThinkingItemView: View {
    let id: String
    let text: String
    let isStreaming: Bool
    @Environment(\.inspectItem) private var inspectItem

    /// Last ~240 characters, from a line boundary where possible.
    private var streamingTail: String {
        guard text.count > 240 else { return text }
        let tail = text.suffix(240)
        if let newline = tail.firstIndex(of: "\n"), newline != tail.endIndex {
            return "…" + tail[tail.index(after: newline)...]
        }
        return "…" + tail
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "sparkle")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
            if isStreaming {
                Text(streamingTail)
                    .font(Theme.assistantFont(.callout)).italic()
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(summaryLine)
                    .font(Theme.assistantFont(.callout)).italic()
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption2).foregroundStyle(.quaternary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { inspectItem?(id) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Thinking. \(summaryLine)")
        .help("Show the full thought in the inspector")
    }

    private var summaryLine: String {
        let firstLine = text.split(separator: "\n", omittingEmptySubsequences: true)
            .first.map(String.init) ?? text
        return "Thought — " + String(firstLine.prefix(120))
    }
}
