import Foundation

/// Read-only view over `~/.claude/projects`: project folders, session
/// summaries, full transcripts, and (Task 10) a change stream. No CLI
/// processes are involved anywhere in this type.
public actor SessionStore {
    public let projectsRoot: URL
    let pollInterval: Duration

    /// De-flattening is filesystem-search; cache folders by name so repeated
    /// enumeration (rescans, reindexes) doesn't redo it.
    private var projectCache: [String: ProjectFolder] = [:]

    public init(
        projectsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects"),
        pollInterval: Duration = .seconds(2)
    ) {
        self.projectsRoot = projectsRoot
        self.pollInterval = pollInterval
    }

    /// Project folders sorted by flattened name. A missing root is an empty
    /// store, not an error (fresh machines have no ~/.claude/projects).
    public func projects() throws -> [ProjectFolder] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: projectsRoot.path) else { return [] }
        let contents = try fileManager.contentsOfDirectory(
            at: projectsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])
        return contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { url in
                let name = url.lastPathComponent
                if let cached = projectCache[name], cached.directoryURL == url {
                    return cached
                }
                let folder = ProjectFolder(directoryURL: url)
                projectCache[name] = folder
                return folder
            }
            .sorted { $0.flattenedName < $1.flattenedName }
    }

    /// Session summaries for one project, newest first. Title derivation
    /// scans each file's bytes (see SessionTitle) — cheap for typical files,
    /// measured by the Task 11 gate for the pathological ones.
    public func sessions(in project: ProjectFolder) throws -> [SessionSummary] {
        try sessionFileStamps(in: project)
            .map { stamp in
                let title = (try? Data(contentsOf: stamp.url, options: .mappedIfSafe))
                    .flatMap(SessionTitle.derive(fromFileData:))
                return SessionSummary(
                    id: stamp.sessionID,
                    project: project,
                    fileURL: stamp.url,
                    title: title ?? stamp.sessionID,
                    lastActivity: stamp.modified,
                    approximateSizeBytes: stamp.size)
            }
            .sorted { $0.lastActivity > $1.lastActivity }
    }

    /// Full decode of one session file. Malformed lines (e.g. a torn write
    /// at the tail) surface as `.unknown` with the raw text, never an error.
    public func transcript(for session: SessionSummary) throws -> [TranscriptEntry] {
        let data = try Data(contentsOf: session.fileURL, options: .mappedIfSafe)
        var entries: [TranscriptEntry] = []
        for line in JSONLines(data: data) {
            if let entry = try? TranscriptDecoder.decode(line) {
                entries.append(entry)
            } else {
                entries.append(.unknown(raw: .string(String(decoding: line, as: UTF8.self))))
            }
        }
        return entries
    }

    /// Stat-only enumeration of a project's session files (depth 2,
    /// `*.jsonl` regular files only). Shared by sessions(in:), the search
    /// indexer, and the change watcher.
    func sessionFileStamps(in project: ProjectFolder) throws -> [SessionFileStamp] {
        let fileManager = FileManager.default
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        let contents = try fileManager.contentsOfDirectory(
            at: project.directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles])
        var stamps: [SessionFileStamp] = []
        for url in contents where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { continue }
            stamps.append(SessionFileStamp(
                url: url,
                sessionID: url.deletingPathExtension().lastPathComponent,
                modified: values.contentModificationDate ?? .distantPast,
                size: values.fileSize ?? 0))
        }
        return stamps
    }
}
