import ClaudeKit

public struct DiffLine: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case context, insertion, deletion }
    public let kind: Kind
    public let text: String
    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }
}

/// Line-based diff, no git. LCS (dynamic programming) up to a size cap;
/// beyond it, a delete-block/insert-block rendering — always correct,
/// just not minimal. Inputs are tool-call strings (old_string/new_string),
/// so the cap is rarely hit.
public enum Diff {
    /// Above this many lines on either side, skip LCS (O(n·m) table).
    static let lcsCap = 500

    public static func lines(old: String, new: String) -> [DiffLine] {
        let oldLines = split(old)
        let newLines = split(new)
        if oldLines.count > lcsCap || newLines.count > lcsCap {
            return oldLines.map { DiffLine(kind: .deletion, text: $0) }
                + newLines.map { DiffLine(kind: .insertion, text: $0) }
        }
        // LCS table: table[i][j] = LCS length of oldLines[i...] vs newLines[j...]
        var table = Array(
            repeating: Array(repeating: 0, count: newLines.count + 1),
            count: oldLines.count + 1)
        for i in stride(from: oldLines.count - 1, through: 0, by: -1) {
            for j in stride(from: newLines.count - 1, through: 0, by: -1) {
                table[i][j] = oldLines[i] == newLines[j]
                    ? table[i + 1][j + 1] + 1
                    : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var result: [DiffLine] = []
        var i = 0, j = 0
        while i < oldLines.count, j < newLines.count {
            if oldLines[i] == newLines[j] {
                result.append(DiffLine(kind: .context, text: oldLines[i]))
                i += 1; j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                result.append(DiffLine(kind: .deletion, text: oldLines[i]))
                i += 1
            } else {
                result.append(DiffLine(kind: .insertion, text: newLines[j]))
                j += 1
            }
        }
        while i < oldLines.count {
            result.append(DiffLine(kind: .deletion, text: oldLines[i])); i += 1
        }
        while j < newLines.count {
            result.append(DiffLine(kind: .insertion, text: newLines[j])); j += 1
        }
        return result
    }

    public static func counts(_ lines: [DiffLine]) -> (added: Int, removed: Int) {
        (lines.count { $0.kind == .insertion },
         lines.count { $0.kind == .deletion })
    }

    /// "" → [] (not [""]) so empty old_string means pure insertion.
    private static func split(_ text: String) -> [String] {
        text.isEmpty ? [] : text.components(separatedBy: "\n")
    }
}

/// A tool call rendered as a diff: Edit (one hunk), MultiEdit (hunk per
/// edit), Write (new content, all insertions). Anything else → nil.
public struct ToolDiff: Equatable, Sendable {
    public let filePath: String
    public let hunks: [[DiffLine]]
    public let added: Int
    public let removed: Int

    public static func from(toolName: String, input: JSONValue) -> ToolDiff? {
        guard let filePath = input["file_path"]?.stringValue else { return nil }
        let hunks: [[DiffLine]]
        switch toolName {
        case "Edit":
            guard let old = input["old_string"]?.stringValue,
                  let new = input["new_string"]?.stringValue else { return nil }
            hunks = [Diff.lines(old: old, new: new)]
        case "Write":
            guard let content = input["content"]?.stringValue else { return nil }
            hunks = [Diff.lines(old: "", new: content)]
        case "MultiEdit":
            guard let edits = input["edits"]?.arrayValue, !edits.isEmpty else { return nil }
            hunks = edits.compactMap { edit in
                guard let old = edit["old_string"]?.stringValue,
                      let new = edit["new_string"]?.stringValue else { return nil }
                return Diff.lines(old: old, new: new)
            }
            guard !hunks.isEmpty else { return nil }
        default:
            return nil
        }
        let totals = hunks.reduce(into: (added: 0, removed: 0)) { acc, hunk in
            let counts = Diff.counts(hunk)
            acc.added += counts.added
            acc.removed += counts.removed
        }
        return ToolDiff(filePath: filePath, hunks: hunks,
                        added: totals.added, removed: totals.removed)
    }
}
