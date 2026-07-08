import Foundation

/// One directory under `~/.claude/projects`, i.e. one working directory the
/// CLI has ever been run in.
public struct ProjectFolder: Sendable, Hashable, Identifiable {
    public var id: String { flattenedName }
    /// e.g. "-Users-andiyar-Developer-Wine"
    public let flattenedName: String
    /// Best-effort de-flattened path, e.g. "/Users/andiyar/Developer/Wine".
    /// Falls back to `flattenedName` when no candidate path exists on disk.
    public let originalPath: String
    public let directoryURL: URL

    public init(flattenedName: String, originalPath: String, directoryURL: URL) {
        self.flattenedName = flattenedName
        self.originalPath = originalPath
        self.directoryURL = directoryURL
    }

    /// Resolves `originalPath` against the real filesystem.
    public init(directoryURL: URL) {
        let name = directoryURL.lastPathComponent
        self.init(
            flattenedName: name,
            originalPath: PathDeflattener.originalPath(
                for: name, directoryExists: PathDeflattener.realDirectoryExists),
            directoryURL: directoryURL)
    }
}

/// The CLI flattens a session's cwd into a directory name by replacing every
/// non-alphanumeric character with "-". Recovery is ambiguous ("-" may have
/// been "/", ".", " ", "_" or a literal dash), so we search for a path that
/// actually exists, preferring "/" so deeper paths win ties.
enum PathDeflattener {
    /// Characters a "-" may stand for, tried in this order.
    static let joiners = ["/", "-", ".", " ", "_"]
    /// Search-state budget: bounds worst-case cost for unresolvable names
    /// (each state is at most one directory-existence check).
    static let maxStates = 4096

    static let realDirectoryExists: @Sendable (String) -> Bool = { path in
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    static func originalPath(
        for flattenedName: String,
        directoryExists: (String) -> Bool
    ) -> String {
        let segments = flattenedName
            .split(separator: "-", omittingEmptySubsequences: false)
            .map(String.init)
        guard segments.count >= 2, segments[0].isEmpty else { return flattenedName }
        var budget = maxStates
        if let hit = search(
            prefix: "/" + segments[1],
            segments: segments,
            index: 2,
            directoryExists: directoryExists,
            budget: &budget
        ) {
            return hit
        }
        return flattenedName
    }

    /// Depth-first: at each remaining "-" try every joiner. Descending with
    /// "/" requires the prefix so far to be an existing directory, which
    /// prunes almost everything; other joiners just extend the current path
    /// component and are validated at the next "/" or at the end.
    private static func search(
        prefix: String,
        segments: [String],
        index: Int,
        directoryExists: (String) -> Bool,
        budget: inout Int
    ) -> String? {
        guard budget > 0 else { return nil }
        budget -= 1
        if index == segments.count {
            return directoryExists(prefix) ? prefix : nil
        }
        for joiner in joiners {
            if joiner == "/" {
                guard !prefix.hasSuffix("/"), directoryExists(prefix) else { continue }
            }
            if let hit = search(
                prefix: prefix + joiner + segments[index],
                segments: segments,
                index: index + 1,
                directoryExists: directoryExists,
                budget: &budget
            ) {
                return hit
            }
        }
        return nil
    }
}
