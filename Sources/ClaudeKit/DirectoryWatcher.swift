import Foundation

/// kqueue-backed dispatch sources for a set of watched directories.
/// Directory-level kqueue fires on entry create/delete/rename — NOT on
/// appends to existing files — which is why SessionStore pairs this with a
/// cheap mtime poll. Not Sendable: confined to the SessionStore actor.
final class DirectoryWatcher {
    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private let queue = DispatchQueue(label: "claudekit.directory-watcher")
    private let onEvent: @Sendable () -> Void

    init(onEvent: @escaping @Sendable () -> Void) {
        self.onEvent = onEvent
    }

    /// Idempotent per path; silently skips paths that can't be opened
    /// (deleted between scan and watch — the poll still covers them).
    func watch(directoryAt path: String) {
        guard sources[path] == nil else { return }
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename],
            queue: queue)
        let handler = onEvent
        source.setEventHandler { handler() }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        sources[path] = source
    }

    func cancelAll() {
        for source in sources.values { source.cancel() }
        sources.removeAll()
    }

    deinit { cancelAll() }
}
