import SwiftUI
import FabledCore

/// One renderable checklist row — TodoItem (legacy TodoWrite) and TaskItem
/// (task tools) both map here.
struct ChecklistRow: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String?
    let status: TodoItem.Status
}

extension TodoItem {
    var checklistRow: ChecklistRow {
        ChecklistRow(id: content, title: content,
                     detail: status == .inProgress ? activeForm : nil,
                     status: status)
    }
}

extension TaskItem {
    var checklistRow: ChecklistRow {
        ChecklistRow(id: id, title: subject,
                     detail: status == .inProgress ? activeForm : nil,
                     status: status)
    }
}

/// Pinned progress card for the session's checklist (task tools, or legacy
/// TodoWrite). Auto-collapses once every item completes; the header always
/// toggles manually (sticky preference — T10 decision).
struct TodoChecklistView: View {
    let rows: [ChecklistRow]
    /// nil = follow auto behavior (open while work remains).
    @State private var userCollapsed: Bool?

    private var allDone: Bool { rows.allSatisfy { $0.status == .completed } }
    private var isCollapsed: Bool { userCollapsed ?? allDone }
    private var doneCount: Int { rows.count { $0.status == .completed } }
    private var current: ChecklistRow? { rows.first { $0.status == .inProgress } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                userCollapsed = !isCollapsed
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: allDone
                        ? "checklist.checked" : "checklist")
                        .foregroundStyle(allDone ? Color.green : Theme.clay)
                    Text("\(doneCount)/\(rows.count)")
                        .font(.caption.monospacedDigit()).fontWeight(.semibold)
                    if isCollapsed, let current {
                        Text(current.detail ?? current.title)
                            .font(.caption).italic()
                            .foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !isCollapsed {
                // Offset-keyed: legacy TodoItem ids are content strings, which
                // the CLI does not guarantee unique (T3 review note).
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        icon(for: row.status)
                        Text(row.status == .inProgress ? (row.detail ?? row.title) : row.title)
                            .font(.caption)
                            .italic(row.status == .inProgress)
                            .foregroundStyle(row.status == .completed
                                ? Color.secondary : Color.primary)
                            .strikethrough(row.status == .completed,
                                           color: .secondary)
                    }
                }
            }
        }
        .padding(10)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func icon(for status: TodoItem.Status) -> some View {
        switch status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case .inProgress:
            Image(systemName: "arrow.right.circle.fill")
                .font(.caption).foregroundStyle(Theme.clay)
        case .pending:
            Image(systemName: "circle")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
