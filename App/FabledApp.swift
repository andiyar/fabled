import SwiftUI

@main
struct FabledApp: App {
    init() {
        // Writes to a dead CLI's stdin raise SIGPIPE and the default
        // disposition kills the app. ClaudeKit short-circuits writes after
        // termination; this is the process-level backstop for the race.
        signal(SIGPIPE, SIG_IGN)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
