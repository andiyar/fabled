import Foundation

/// A local notification the app should post. FabledCore decides; the app
/// target delivers (UNUserNotificationCenter is AppKit-side).
public struct LocalNotification: Equatable, Sendable {
    public let title: String
    public let body: String
    public let sessionID: UUID
}

/// Pure policy: notify only when Ben is NOT already looking at the session
/// (feature 7). Long-turn threshold 30 s — short turns complete before he
/// has looked away.
public enum NotificationPolicy {
    public static let longTurnThresholdMS: Double = 30_000

    public static func decide(
        _ event: ChatSession.NoteworthyEvent,
        sessionTitle: String, sessionID: UUID,
        isAppActive: Bool, isSessionSelected: Bool
    ) -> LocalNotification? {
        let watching = isAppActive && isSessionSelected
        guard !watching else { return nil }
        switch event {
        case .gateArrived(let summary):
            return LocalNotification(
                title: "\(sessionTitle) needs input", body: summary,
                sessionID: sessionID)
        case .turnCompleted(let detail, let durationMS):
            guard durationMS >= longTurnThresholdMS else { return nil }
            return LocalNotification(
                title: "\(sessionTitle) finished",
                body: detail.isEmpty ? "Turn complete" : detail,
                sessionID: sessionID)
        case .terminated(let exitCode):
            guard exitCode != 0 else { return nil }
            return LocalNotification(
                title: "\(sessionTitle) ended unexpectedly",
                body: "claude exited with code \(exitCode)",
                sessionID: sessionID)
        }
    }
}
