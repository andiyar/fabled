import SwiftUI
import ClaudeKit
import FabledCore

/// Cards request inspection by timeline-item id; the conversation container
/// owns the panel state.
///
/// Equatable via a stable `id`. The `action` closure is rebuilt every time the
/// owning view's body runs (it captures the current @State), so two closures can
/// never be compared — yet the action is semantically the SAME for a given
/// container. We therefore tag the value with a container-stable id
/// ("conversation-<session>", "historical-<summary>") and compare on that.
/// This matters because the value rides in `@Environment`: a non-Equatable
/// environment value looks "changed" on every render, invalidating the rows
/// subtree mid-interaction, which was cancelling plain-Button press dispatch on
/// the rows (see the row-activation note in TimelineItemViews.swift).
struct InspectItemAction: Equatable {
    let id: String
    let action: (String) -> Void
    func callAsFunction(_ id: String) { action(id) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

extension EnvironmentValues {
    @Entry var inspectItem: InspectItemAction? = nil
}

/// Right-hand detail panel: full tool I/O, diffs (Task 7), subagent
/// drill-down (Task 11), raw events. The transcript shows one-liners;
/// everything deep lives here (Electron-parity gate feedback). The
/// container resolves the inspected item and passes only that item plus
/// its subagent slice — handing the panel whole timelines makes SwiftUI
/// deep-compare every accumulated payload per stream event (T6 quality
/// review).
struct InspectorPanel: View {
    let item: TimelineItem?
    /// Sub-timeline of the inspected Task/Agent call, if any (Task 11).
    let subagentItems: [TimelineItem]?
    /// The container's inspect action, threaded in EXPLICITLY (Task 11
    /// drill-down). SwiftUI presentation content (`.inspector`, `.sheet`, …)
    /// does NOT inherit `.environment` values that the presenting view applied
    /// to itself — the presented tree gets a fresh environment from the window/
    /// scene, so an `@Environment(\.inspectItem)` read inside the panel comes
    /// back nil. We re-inject it here so the drill-down sub-rows can switch the
    /// panel to a sub item (T12 gate). Do not rely on inheritance for this.
    let inspectItem: InspectItemAction?
    @Binding var inspectedID: String?
    /// Pops the drill-down trail (Task detail → sub-row → back). nil hides the
    /// button — historical sessions have no drill-down, so no trail.
    var onBack: (() -> Void)? = nil

    var body: some View {
        if let item {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        if let onBack {
                            Button(action: onBack) {
                                Label("Back", systemImage: "chevron.left")
                                    .labelStyle(.titleAndIcon)
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Back to the previous item")
                        }
                        Spacer()
                        // In-panel close (deliberately not a toolbar item —
                        // toolbar placement inside .inspector content is
                        // unreliable across macOS releases).
                        Button {
                            inspectedID = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Clear selection")
                    }
                    content(for: item)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Injected on the concrete container that directly holds the
            // sub-rows — no conditional/presentation boundary in between — so
            // the drill-down TimelineItemViews reliably see the action.
            .environment(\.inspectItem, inspectItem)
        } else {
            ContentUnavailableView(
                "Nothing selected",
                systemImage: "sidebar.right",
                description: Text("Click a tool card to see its full detail."))
        }
    }

    @ViewBuilder
    private func content(for item: TimelineItem) -> some View {
        switch item {
        case .toolCall(let id, let name, let summary, let input, let result,
                       let isError, let isRunning):
            toolDetail(id: id, name: name, summary: summary, input: input,
                       result: result, isError: isError, isRunning: isRunning)
        case .raw(_, let type, let raw):
            sectionHeader(type, systemImage: "questionmark.square.dashed")
            monospacedBlock(JSONPretty.string(raw))
        case .thinking(_, let text, _):
            sectionHeader("Thinking", systemImage: "sparkle")
            // Same cap as monospacedBlock — the inspector must not hang the
            // window on a pathological payload.
            Text(String(text.prefix(200_000)))
                .font(Theme.assistantFont(.callout)).italic()
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        default:
            // Other item kinds are fully visible inline; nothing deeper to show.
            Text("No additional detail for this item.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func toolDetail(id: String, name: String, summary: String,
                            input: JSONValue, result: JSONValue?,
                            isError: Bool?, isRunning: Bool) -> some View {
        HStack(spacing: 8) {
            ToolStatusIcon(isError: isError, isRunning: isRunning)
            Text(name).font(.title3).fontWeight(.semibold)
        }
        Text(summary).font(.callout).foregroundStyle(.secondary)
        let diff = DiffCache.shared.diff(id: id, toolName: name, input: input)
        if let diff {
            sectionHeader("Changes", systemImage: "plus.forwardslash.minus")
            DiffSectionView(diff: diff)
        }
        if diff == nil, input != .object([:]), input != .null {
            sectionHeader("Input", systemImage: "arrow.down.circle")
            monospacedBlock(JSONPretty.string(input))
        }
        if let result {
            sectionHeader("Result", systemImage: "arrow.up.circle")
            monospacedBlock(JSONPretty.string(result),
                            tint: isError == true ? .red : nil)
        }
        if let sub = subagentItems, !sub.isEmpty {
            sectionHeader("Subagent activity (\(sub.count) items)",
                          systemImage: "person.2.circle")
            VStack(alignment: .leading, spacing: 6) {
                // Same vocabulary, read-only. Sub tool rows are inspectable
                // too — the container's inspectedItem lookup already searches
                // sub-timelines.
                ForEach(sub) { item in
                    TimelineItemView(item: item)
                }
            }
        }
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption).fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    /// Full payloads, sanely capped — the inspector is the "see everything"
    /// surface, but a 50 MB tool result must not hang the window.
    private func monospacedBlock(_ text: String, tint: Color? = nil) -> some View {
        Text(String(text.prefix(200_000)))
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(tint ?? Color.primary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Unified diff for Edit/Write/MultiEdit tool inputs — computed from the
/// tool call's own strings, no git (brief feature 1).
struct DiffSectionView: View {
    let diff: ToolDiff

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(diff.filePath)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1).truncationMode(.head)
                Spacer()
                DiffCountChips(added: diff.added, removed: diff.removed)
            }
            ForEach(Array(diff.hunks.enumerated()), id: \.offset) { index, hunk in
                if diff.hunks.count > 1 {
                    Text("Edit \(index + 1)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(hunk.enumerated()), id: \.offset) { _, line in
                        DiffLineView(line: line)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

private struct DiffLineView: View {
    let line: DiffLine

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(marker)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: 10, alignment: .leading)
            Text(line.text.isEmpty ? " " : line.text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(background)
    }

    private var marker: String {
        switch line.kind {
        case .insertion: "+"
        case .deletion: "−"
        case .context: " "
        }
    }
    private var color: Color {
        switch line.kind {
        case .insertion: .green
        case .deletion: .red
        case .context: .secondary
        }
    }
    private var background: Color {
        switch line.kind {
        case .insertion: .green.opacity(0.12)
        case .deletion: .red.opacity(0.12)
        case .context: .clear
        }
    }
}

struct DiffCountChips: View {
    let added: Int
    let removed: Int
    var body: some View {
        HStack(spacing: 4) {
            Text("+\(added)").foregroundStyle(.green)
            Text("−\(removed)").foregroundStyle(.red)
        }
        .font(.caption.monospacedDigit())
    }
}

/// LCS diffs are cheap for typical fragments but ~2 ms at the size cap
/// (measured, release) — far too hot for a view body that re-renders per
/// scroll tick. One entry per tool_use id, revalidated by input equality
/// (streamed inputs go {} → full input once, then never change).
@MainActor
final class DiffCache {
    static let shared = DiffCache()
    private var store: [String: (input: JSONValue, diff: ToolDiff?)] = [:]

    func diff(id: String, toolName: String, input: JSONValue) -> ToolDiff? {
        if let cached = store[id], cached.input == input { return cached.diff }
        let diff = ToolDiff.from(toolName: toolName, input: input)
        // Cache only real diffs: for non-diff tools ToolDiff.from is an O(1)
        // fast-fail, and skipping them keeps the cache from retaining every
        // tool input for the app's lifetime (T7 quality review).
        if diff != nil { store[id] = (input, diff) }
        return diff
    }
}

/// Shared by the compact row and the panel header.
struct ToolStatusIcon: View {
    let isError: Bool?
    let isRunning: Bool
    var body: some View {
        if isRunning {
            ProgressView().controlSize(.small)
        } else if isError == true {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        } else {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        }
    }
}
