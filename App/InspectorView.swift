import SwiftUI
import ClaudeKit
import FabledCore

/// Cards request inspection by timeline-item id; the conversation container
/// owns the panel state.
struct InspectItemAction {
    let action: (String) -> Void
    func callAsFunction(_ id: String) { action(id) }
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
    @Binding var inspectedID: String?

    var body: some View {
        if let item {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
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
        // Task 7 inserts the diff section here for Edit/Write/MultiEdit.
        if input != .object([:]), input != .null {
            sectionHeader("Input", systemImage: "arrow.down.circle")
            monospacedBlock(JSONPretty.string(input))
        }
        if let result {
            sectionHeader("Result", systemImage: "arrow.up.circle")
            monospacedBlock(JSONPretty.string(result),
                            tint: isError == true ? .red : nil)
        }
        // Task 11 inserts the subagent drill-down here for Task/Agent.
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
