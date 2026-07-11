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
    private let defaults: UserDefaults

    /// AppKit-side seams: is the app frontmost, and post a notification.
    /// Injected by the app target at startup (FabledCore cannot import AppKit).
    public var isAppActive: () -> Bool = { true }
    public var postNotification: (LocalNotification) -> Void = { _ in }

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
            defaults.set(preferredEffort, forKey: Self.preferredEffortKey)
        }
    }
    private static let preferredEffortKey = "preferredEffort"

    /// Sidebar organization (feature 18). Persisted as JSON.
    public var sidebarOptions = SidebarOptions() {
        didSet {
            guard sidebarOptions != oldValue else { return }
            if let data = try? JSONEncoder().encode(sidebarOptions) {
                defaults.set(data, forKey: Self.sidebarOptionsKey)
            }
        }
    }
    private static let sidebarOptionsKey = "sidebarOptions"
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

    public init(store: SessionStore = SessionStore(), databaseURL: URL? = nil,
                defaults: UserDefaults = .standard) throws {
        self.store = store
        self.defaults = defaults
        let dbURL = databaseURL
            ?? FileManager.default.urls(for: .applicationSupportDirectory,
                                        in: .userDomainMask)[0]
                .appendingPathComponent("Fabled/index.sqlite")
        self.index = try SearchIndex(databaseURL: dbURL, store: store)
        self.preferredEffort = defaults.string(forKey: Self.preferredEffortKey)
        if let data = defaults.data(forKey: Self.sidebarOptionsKey),
           let options = try? JSONDecoder().decode(SidebarOptions.self, from: data) {
            self.sidebarOptions = options
        }
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

    /// Sidebar sections under the user's organization options.
    public var sidebarSections: [SidebarSection] {
        SidebarOrganizer.organize(allSummaries, options: sidebarOptions, now: Date())
    }
    private var allSummaries: [SessionSummary] = []

    public func togglePin(_ sessionID: String) {
        if sidebarOptions.pinnedSessionIDs.contains(sessionID) {
            sidebarOptions.pinnedSessionIDs.remove(sessionID)
        } else {
            sidebarOptions.pinnedSessionIDs.insert(sessionID)
        }
    }

    public func refreshHistory() async {
        guard let summaries = try? await index.sessionSummaries() else { return }
        allSummaries = summaries
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

    /// Welcome inbox recents: newest sessions across ALL projects (the
    /// sidebar groups; the welcome screen interleaves), excluding sessions
    /// currently attached to a live ChatSession (those render in the live
    /// sections above).
    public func welcomeRecents(limit: Int) -> [SessionSummary] {
        let liveIDs = Set(liveSessions.compactMap(\.resumedSessionID))
        var seen = Set<String>()
        var result: [SessionSummary] = []
        for group in history {
            for summary in group.sessions where !liveIDs.contains(summary.id) {
                if seen.insert(summary.id).inserted { result.append(summary) }
            }
        }
        result.sort { $0.lastActivity > $1.lastActivity }
        return Array(result.prefix(limit))
    }

    /// Composer project chip: recent projects, newest-session first
    /// (history is already ordered that way).
    public func recentProjects(limit: Int) -> [ProjectFolder] {
        Array(history.map(\.project).prefix(limit))
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

    public func newSession(at directory: URL, model: String? = nil,
                           firstMessage: String? = nil) async {
        var configuration = SessionConfiguration(workingDirectory: directory)
        configuration.model = model
        configuration.effort = preferredEffort
        await launch(configuration, seed: [])
        if let firstMessage, case .live(let id) = selection,
           let session = liveSessions.first(where: { $0.id == id }) {
            session.send(firstMessage)
        }
    }

    /// Continues in flight: the collision guard checks liveSessions, but the
    /// session lands there only after two awaits — without this set, a rapid
    /// double-Continue passes the guard twice and spawns two processes on one
    /// session id (T12 quality review).
    private var resumingSessionIDs: Set<String> = []

    /// Resume/fork replays nothing on the wire (probe finding 8) — the
    /// timeline is seeded from the on-disk transcript. Continue reattaches
    /// the SAME session id, so a second live process on that id is forbidden
    /// (one-process invariant): an existing attachment is selected instead.
    public func resume(_ summary: SessionSummary, fork: Bool) async {
        if !fork, let existing = liveSessions.first(
            where: { $0.resumedSessionID == summary.id }) {
            selection = .live(existing.id)
            return
        }
        // Forks deliberately unguarded — each fork is a new identity, so a
        // double-click forking twice is benign.
        if !fork {
            guard !resumingSessionIDs.contains(summary.id) else { return }
            resumingSessionIDs.insert(summary.id)
        }
        defer { if !fork { resumingSessionIDs.remove(summary.id) } }
        var seed = await historicalTimeline(for: summary)
        let resolved = resolveWorkingDirectory(for: summary)
        if fork {
            seed = [.notice(id: "fork-origin",
                            text: "Forked from “\(summary.title)” — this is a new session id.")]
                + seed
        }
        if resolved.didFallBack {
            seed = seed + [.notice(id: "cwd-fallback",
                                   text: "Original folder \(summary.project.originalPath) no longer exists — running in your home folder instead.")]
        }
        var configuration = SessionConfiguration(workingDirectory: resolved.url)
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

    /// Notification click: focus the session (feature 7).
    public func focusSession(id: UUID) {
        guard liveSessions.contains(where: { $0.id == id }) else { return }
        selection = .live(id)
    }

    /// Test seam: registers a live session without spawning a process.
    public func adoptForTesting(_ session: ChatSession) {
        liveSessions.append(session)
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
            session.onNoteworthy = { [weak self, weak session] event in
                guard let self, let session else { return }
                let selected = self.selection == .live(session.id)
                if let note = NotificationPolicy.decide(
                    event, sessionTitle: session.title, sessionID: session.id,
                    isAppActive: self.isAppActive(), isSessionSelected: selected) {
                    self.postNotification(note)
                }
            }
            selection = .live(session.id)
            launchError = nil
        } catch {
            launchError = "Could not start claude: \(error)"
        }
    }

    /// Resolves a summary's original cwd; falls back to $HOME when the
    /// project folder no longer exists — and SAYS so (feature 16 rider:
    /// the fallback used to be silent).
    public func resolveWorkingDirectory(for summary: SessionSummary)
        -> (url: URL, didFallBack: Bool) {
        let path = summary.project.originalPath
        guard path.hasPrefix("/"),
              FileManager.default.fileExists(atPath: path) else {
            return (FileManager.default.homeDirectoryForCurrentUser, true)
        }
        return (URL(fileURLWithPath: path), false)
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
