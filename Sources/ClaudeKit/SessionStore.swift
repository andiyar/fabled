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

    // MARK: change watching

    private var subscribers: [UUID: AsyncStream<[URL]>.Continuation] = [:]
    private var watcher: DirectoryWatcher?
    private var pollTask: Task<Void, Never>?
    private var rescanTask: Task<Void, Never>?
    private var snapshot: [String: FileStamp] = [:]

    struct FileStamp: Equatable {
        let mtime: Date
        let size: Int
    }

    public init(
        projectsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects"),
        pollInterval: Duration = .seconds(2)
    ) {
        self.projectsRoot = projectsRoot
        self.pollInterval = pollInterval
    }

    /// Watcher tasks hold `self` weakly, so they don't keep the store alive —
    /// but nothing else cancels them if the owner drops the store while
    /// subscribers are still consuming. Kill them here. The kqueue sources
    /// need no explicit cancel: `watcher` is solely owned by the store, so
    /// it deallocates with us and its own deinit runs cancelAll() (a
    /// nonisolated deinit can't touch the non-Sendable property anyway).
    deinit {
        pollTask?.cancel()
        rescanTask?.cancel()
        // Dropping a Continuation does NOT finish its stream — do it
        // explicitly or consumers hang forever on a dead store.
        for continuation in subscribers.values { continuation.finish() }
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

    /// Fires on any session-file change under projectsRoot (create, append,
    /// delete, rename), throttled to at most one batch per 250 ms. Payload =
    /// affected session file URLs. Each access returns an independent
    /// stream; watching starts on first access and stops when the last
    /// subscriber cancels.
    public var changes: AsyncStream<[URL]> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<[URL]>.makeStream()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id) }
        }
        startWatchingIfNeeded()
        return stream
    }

    /// Internal, for tests.
    var subscriberCount: Int { subscribers.count }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
        if subscribers.isEmpty { stopWatching() }
    }

    private func startWatchingIfNeeded() {
        guard watcher == nil else { return }
        snapshot = (try? currentSnapshot()) ?? [:]
        let newWatcher = DirectoryWatcher(onEvent: { [weak self] in
            Task { await self?.scheduleRescan() }
        })
        newWatcher.watch(directoryAt: projectsRoot.path)
        for project in (try? projects()) ?? [] {
            newWatcher.watch(directoryAt: project.directoryURL.path)
        }
        watcher = newWatcher

        let interval = pollInterval
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                // Break, don't just skip: if the store is gone the loop must
                // die too, or repeated store create/drop cycles leak spinners.
                guard let self else { break }
                await self.scheduleRescan()
            }
        }
    }

    private func stopWatching() {
        watcher?.cancelAll()
        watcher = nil
        pollTask?.cancel()
        pollTask = nil
        rescanTask?.cancel()
        rescanTask = nil
    }

    /// Throttle, not restartable debounce: kqueue bursts and poll ticks
    /// coalesce into one rescan at most every 250 ms, and a steady signal
    /// stream can never starve the rescan.
    private func scheduleRescan() {
        guard watcher != nil, rescanTask == nil else { return }
        rescanTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.performScheduledRescan()
        }
    }

    private func performScheduledRescan() {
        rescanTask = nil
        guard !subscribers.isEmpty else { return }
        let current = (try? currentSnapshot()) ?? snapshot
        var changed: [URL] = []
        for (path, stamp) in current where snapshot[path] != stamp {
            changed.append(URL(fileURLWithPath: path))
        }
        for path in snapshot.keys where current[path] == nil {
            changed.append(URL(fileURLWithPath: path))
        }
        snapshot = current
        // Newly created project directories need their own kqueue source.
        for project in (try? projects()) ?? [] {
            watcher?.watch(directoryAt: project.directoryURL.path)
        }
        guard !changed.isEmpty else { return }
        let batch = changed.sorted { $0.path < $1.path }
        for continuation in subscribers.values {
            continuation.yield(batch)
        }
    }

    private func currentSnapshot() throws -> [String: FileStamp] {
        var result: [String: FileStamp] = [:]
        for project in try projects() {
            for stamp in (try? sessionFileStamps(in: project)) ?? [] {
                result[stamp.url.path] = FileStamp(mtime: stamp.modified, size: stamp.size)
            }
        }
        return result
    }
}
