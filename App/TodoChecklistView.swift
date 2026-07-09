import SwiftUI
import FabledCore

/// Pinned progress card for the session's TodoWrite list. Auto-collapses
/// once every item completes; the header always toggles manually.
struct TodoChecklistView: View {
    let todos: [TodoItem]
    /// nil = follow auto behavior (open while work remains).
    @State private var userCollapsed: Bool?

    private var allDone: Bool { todos.allSatisfy { $0.status == .completed } }
    private var isCollapsed: Bool { userCollapsed ?? allDone }
    private var doneCount: Int { todos.count { $0.status == .completed } }
    private var current: TodoItem? { todos.first { $0.status == .inProgress } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                userCollapsed = !isCollapsed
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: allDone
                        ? "checklist.checked" : "checklist")
                        .foregroundStyle(allDone ? Color.green : Theme.clay)
                    Text("\(doneCount)/\(todos.count)")
                        .font(.caption.monospacedDigit()).fontWeight(.semibold)
                    if isCollapsed, let current {
                        Text(current.activeForm)
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
                // Offset-keyed: TodoItem.id is content, which the CLI does
                // not guarantee unique (T3 review note).
                ForEach(Array(todos.enumerated()), id: \.offset) { _, todo in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        icon(for: todo.status)
                        Text(todo.status == .inProgress ? todo.activeForm : todo.content)
                            .font(.caption)
                            .italic(todo.status == .inProgress)
                            .foregroundStyle(todo.status == .completed
                                ? Color.secondary : Color.primary)
                            .strikethrough(todo.status == .completed,
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
