import SwiftUI
import AppKit
import UserNotifications
import FabledCore

@main
struct FabledApp: App {
    @State private var model: AppModel
    private let notifier: Notifier

    init() {
        // Writes to a dead CLI's stdin raise SIGPIPE and the default
        // disposition kills the app. ClaudeKit short-circuits writes after
        // termination; this is the process-level backstop for the race.
        signal(SIGPIPE, SIG_IGN)
        do {
            let model = try AppModel()
            let notifier = Notifier()
            notifier.onClick = { [weak model] id in
                NSApp.activate()
                model?.focusSession(id: id)
            }
            model.isAppActive = { NSApp.isActive }
            model.postNotification = { notifier.post($0) }
            _model = State(initialValue: model)
            self.notifier = notifier
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
                Button("Home") { model.goHome() }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

/// Thin UNUserNotificationCenter wrapper: lazy permission, session-id
/// userInfo, click callback. Kept out of FabledCore (AppKit/UN import).
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    var onClick: ((UUID) -> Void)?
    private var authorizationRequested = false

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func post(_ note: LocalNotification) {
        let center = UNUserNotificationCenter.current()
        if !authorizationRequested {
            authorizationRequested = true
            // Use the async request, NOT the completion-handler form: `post` is
            // @MainActor, so an inline completion closure inherits main-actor
            // isolation, but UNUserNotificationCenter invokes it on its own
            // background call-out queue — the Swift 6 runtime then traps on the
            // executor mismatch (EXC_BREAKPOINT via _dispatch_assert_queue_fail,
            // crash 2026-07-13). Awaiting has no main-actor closure to mis-invoke.
            Task { _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge]) }
        }
        let content = UNMutableNotificationContent()
        content.title = note.title
        content.body = note.body
        content.userInfo = ["sessionID": note.sessionID.uuidString]
        center.add(UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let raw = info["sessionID"] as? String, let id = UUID(uuidString: raw)
        else { return }
        await MainActor.run { onClick?(id) }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // App active but session unselected: still show the banner.
        [.banner, .sound]
    }
}
