import SwiftUI
import FabledCore

@main
struct FabledApp: App {
    @State private var model: AppModel

    init() {
        // Writes to a dead CLI's stdin raise SIGPIPE and the default
        // disposition kills the app. ClaudeKit short-circuits writes after
        // termination; this is the process-level backstop for the race.
        signal(SIGPIPE, SIG_IGN)
        do {
            _model = State(initialValue: try AppModel())
        } catch {
            // A failed SQLite open in Application Support means a broken
            // install; there is no UI to recover into yet.
            fatalError("Failed to open the search index: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Session…") { model.isPickingFolder = true }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}
