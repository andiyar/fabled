import ClaudeKit
import Foundation
import Observation

/// App-level state: the stores, live sessions, sidebar history, search,
/// and session lifecycle. One instance per app.
@MainActor
@Observable
public final class AppModel {
    public let store: SessionStore
    public let index: SearchIndex

    public private(set) var liveSessions: [ChatSession] = []
    public private(set) var history: [ProjectHistory] = []
    public private(set) var searchHits: [SearchHit] = []
    public private(set) var isIndexing = false
    public private(set) var launchError: String?
    public var selection: Selection?
    /// The New Session folder picker (menu ⌘N, welcome button) presents
    /// when this flips true; RootView owns the fileImporter.
    public var isPickingFolder = false
    /// Effort applied to every new spawn via --effort (what Claude Desktop
    /// does). Persisted; nil = CLI default. Session-scoped changes go through
    /// ChatSession.setEffort and don't touch this.
    public var preferredEffort: String? {
        didSet {
            UserDefaults.standard.set(preferredEffort, forKey: Self.preferredEffortKey)
        }
    }
    private static let preferredEffortKey = "preferredEffort"
    public var searchQuery = "" {
        didSet { if searchQuery != oldValue { scheduleSearch() } }
    }

    public enum Selection: Hashable {
        case live(UUID)
        case historical(String)   // session id
    }

    public struct ProjectHistory: Identifiable, Sendable {
        public let project: ProjectFolder
        public var sessions: [SessionSummary]
        public var id: String { project.id }
    }

    private var watchTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

    public init(store: SessionStore = SessionStore(), databaseURL: URL? = nil) throws {
        self.store = store
        let dbURL = databaseURL
            ?? FileManager.default.urls(for: .applicationSupportDirectory,
                                        in: .userDomainMask)[0]
                .appendingPathComponent("Fabled/index.sqlite")
        self.index = try SearchIndex(databaseURL: dbURL, store: store)
        self.preferredEffort = UserDefaults.standard.string(forKey: Self.preferredEffortKey)
    }

    // No deinit: Swift 6.0 forbids a nonisolated deinit from touching the
    // MainActor-isolated task properties, and `isolated deinit` isn't stable
    // in this toolchain. Both tasks capture `[weak self]` and self-terminate
    // when the model deallocates — `watchTask`'s loop ends once `store` (solely
    // owned here) drops and finishes its `changes` stream; `searchTask`
    // completes after its debounce.

    // MARK: - Sidebar data

    /// Instant history from the warm index, then a catch-up reindex, then
    /// watcher-driven refreshes for as long as the app lives.
    public func bootstrap() async {
        // App-global model: a second window's RootView calls bootstrap()
        // again via .task. It observes the same shared state; bootstrap must
        // run once or we'd leak the first watchTask and double-subscribe to
        // store.changes (double reindex on every file change).
        guard watchTask == nil else { return }
        await refreshHistory()
        watchTask = Task { [weak self] in
            guard let changes = await self?.store.changes else { return }
            for await _ in changes {
                guard let self else { return }
                await self.reindexAndRefresh()
            }
        }
        await reindexAndRefresh()
    }

    private func reindexAndRefresh() async {
        isIndexing = true
        defer { isIndexing = false }
        _ = try? await index.reindex()
        await refreshHistory()
    }

    public func refreshHistory() async {
        guard let summaries = try? await index.sessionSummaries() else { return }
        var groups: [String: ProjectHistory] = [:]
        var order: [String] = []   // projects ordered by their newest session
        for summary in summaries {
            let key = summary.project.id
            if groups[key] == nil {
                groups[key] = ProjectHistory(project: summary.project, sessions: [])
                order.append(key)
            }
            groups[key]?.sessions.append(summary)
        }
        history = order.compactMap { groups[$0] }
    }

    public func summary(forSessionID id: String) -> SessionSummary? {
        for group in history {
            if let summary = group.sessions.first(where: { $0.id == id }) {
                return summary
            }
        }
        return searchHits.first { $0.session.id == id }?.session
    }

    // MARK: - Search

    private func scheduleSearch() {
        searchTask?.cancel()
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            searchHits = []
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))   // keystroke debounce
            guard !Task.isCancelled, let self else { return }
            let hits = (try? await self.index.search(query, limit: 50)) ?? []
            guard !Task.isCancelled else { return }
            self.searchHits = hits
        }
    }

    // MARK: - Session lifecycle

    public func newSession(at directory: URL, model: String? = nil) async {
        var configuration = SessionConfiguration(workingDirectory: directory)
        configuration.model = model
        configuration.effort = preferredEffort
        await launch(configuration, seed: [])
    }

    /// Resume/fork replays nothing on the wire (probe finding 8) — the
    /// timeline is seeded from the on-disk transcript.
    public func resume(_ summary: SessionSummary, fork: Bool) async {
        let seed = await historicalTimeline(for: summary)
        var configuration = SessionConfiguration(
            workingDirectory: workingDirectory(for: summary))
        configuration.resumeSessionID = summary.id
        configuration.forkSession = fork
        configuration.effort = preferredEffort
        await launch(configuration, seed: seed)
    }

    /// Dismisses the launch-failure alert (RootView's binding calls this).
    public func clearLaunchError() {
        launchError = nil
    }

    public func close(_ session: ChatSession) {
        session.terminate()
        liveSessions.removeAll { $0.id == session.id }
        if selection == .live(session.id) { selection = nil }
    }

    public func historicalTimeline(for summary: SessionSummary) async -> [TimelineItem] {
        let entries = (try? await store.transcript(for: summary)) ?? []
        return TimelineReducer.items(fromTranscript: entries)
    }

    private func launch(_ configuration: SessionConfiguration, seed: [TimelineItem]) async {
        do {
            let session = try await ChatSession.launch(configuration: configuration)
            session.seed(timeline: seed)
            liveSessions.append(session)
            selection = .live(session.id)
            launchError = nil
        } catch {
            launchError = "Could not start claude: \(error)"
        }
    }

    private func workingDirectory(for summary: SessionSummary) -> URL {
        let path = summary.project.originalPath
        // Unresolvable flattened names (deleted directories) fall back to home.
        guard path.hasPrefix("/") else {
            return FileManager.default.homeDirectoryForCurrentUser
        }
        return URL(fileURLWithPath: path)
    }
}

public extension ProjectFolder {
    /// Sidebar section label: the directory's leaf name when the path
    /// resolved, otherwise the raw flattened name.
    var displayName: String {
        originalPath.hasPrefix("/")
            ? URL(fileURLWithPath: originalPath).lastPathComponent
            : flattenedName
    }
}
