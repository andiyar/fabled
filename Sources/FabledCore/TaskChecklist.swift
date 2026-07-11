import ClaudeKit
import Foundation

/// One task-tool entry (probe finding 9). Unlike TodoWrite (whole list
/// re-sent per call) the task tools are incremental — creates, updates,
/// deletes — so the checklist is a fold, not a swap.
public struct TaskItem: Equatable, Sendable, Identifiable {
    /// CLI-assigned id ("1", "2", …); nil while the create is in flight.
    public var taskID: String?
    /// The spawning tool_use id — the fold's correlation key.
    public let toolUseID: String
    public var subject: String
    public var activeForm: String?
    public var status: TodoItem.Status
    public var id: String { toolUseID }
}

/// Pure fold from task-tool traffic to checklist state. ChatSession feeds
/// it tool_use blocks (assistant events) and their results; the update only
/// applies when the CLI confirms (non-error result) — an optimistic apply
/// would show a completed step the CLI rejected.
public struct TaskChecklist: Equatable, Sendable {
    public private(set) var items: [TaskItem] = []
    /// TaskUpdate inputs awaiting their result, keyed by tool_use id.
    private var pendingUpdates: [String: JSONValue] = [:]
    /// TaskCreate tool_use ids awaiting their id-assigning result.
    private var pendingCreates: Set<String> = []
    /// TaskList tool_use ids awaiting their reconciling result.
    private var pendingLists: Set<String> = []

    public init() {}

    public mutating func noteToolUse(id: String, name: String, input: JSONValue) {
        switch name {
        case "TaskCreate":
            guard let subject = input["subject"]?.stringValue else { return }
            items.append(TaskItem(
                taskID: nil, toolUseID: id, subject: subject,
                activeForm: input["activeForm"]?.stringValue, status: .pending))
            pendingCreates.insert(id)
        case "TaskUpdate":
            pendingUpdates[id] = input
        case "TaskList":
            pendingLists.insert(id)
        default:
            break
        }
    }

    public mutating func noteResult(_ result: ToolResult) {
        if pendingCreates.remove(result.toolUseID) != nil {
            applyCreateResult(result)
        } else if let input = pendingUpdates.removeValue(forKey: result.toolUseID) {
            guard !result.isError else { return }
            applyUpdate(input)
        } else if pendingLists.remove(result.toolUseID) != nil {
            guard !result.isError,
                  let text = result.content.stringValue else { return }
            reconcile(fromListText: text)
        }
    }

    private mutating func applyCreateResult(_ result: ToolResult) {
        guard !result.isError,
              let index = items.firstIndex(where: { $0.toolUseID == result.toolUseID })
        else {
            items.removeAll { $0.toolUseID == result.toolUseID && $0.taskID == nil }
            return
        }
        // Structured id when the line carried tool_use_result (T1)…
        if let id = result.toolUseResult?["task"]?["id"]?.stringValue {
            items[index].taskID = id
            return
        }
        // …else parse "Task #N created successfully: …".
        if let text = result.content.stringValue,
           let match = text.firstMatch(of: /Task #(\d+) created/) {
            items[index].taskID = String(match.1)
        }
    }

    private mutating func applyUpdate(_ input: JSONValue) {
        guard let taskID = input["taskId"]?.stringValue,
              let index = items.firstIndex(where: { $0.taskID == taskID })
        else { return }
        if let status = input["status"]?.stringValue {
            switch status {
            case "deleted":
                items.remove(at: index)
                return
            case "completed": items[index].status = .completed
            case "in_progress": items[index].status = .inProgress
            case "pending": items[index].status = .pending
            default: break   // tolerant: unknown status ignored
            }
        }
        if let subject = input["subject"]?.stringValue { items[index].subject = subject }
        if let activeForm = input["activeForm"]?.stringValue {
            items[index].activeForm = activeForm
        }
    }

    /// TaskList output is authoritative full state: "#1 [completed] Alpha task".
    /// Reconciling catches anything the fold missed (e.g. traffic before a
    /// resume seed). Items keep stable identity via taskID when possible.
    private mutating func reconcile(fromListText text: String) {
        var parsed: [TaskItem] = []
        for line in text.split(separator: "\n") {
            guard let match = line.wholeMatch(of: /#(\d+) \[(\w+)\] (.+)/) else { continue }
            let status: TodoItem.Status = switch String(match.2) {
            case "completed": .completed
            case "in_progress": .inProgress
            default: .pending
            }
            let taskID = String(match.1)
            let existing = items.first { $0.taskID == taskID }
            parsed.append(TaskItem(
                taskID: taskID,
                toolUseID: existing?.toolUseID ?? "list-\(taskID)",
                subject: String(match.3),
                activeForm: existing?.activeForm,
                status: status))
        }
        items = parsed
    }
}
