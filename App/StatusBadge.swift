import SwiftUI
import FabledCore

/// Session state as shape + color + word (feature 14: never color alone).
/// Compact (icon only, sidebar rows) or labeled (welcome inbox chips).
struct SessionStatusBadge: View {
    let state: ChatSession.ActivityState
    var labeled = false

    var body: some View {
        if labeled {
            Label(word, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .padding(.horizontal, Theme.spaceS)
                .padding(.vertical, 2)
                .background(color.opacity(0.14), in: Capsule())
                .accessibilityLabel(word)
        } else {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(color)
                .symbolEffect(.pulse, options: .repeating,
                              isActive: state == .needsApproval)
                .help(word)
                .accessibilityLabel(word)
        }
    }

    private var word: String {
        switch state {
        case .needsApproval: "Needs input"
        case .working: "Working"
        case .idle: "Ready"
        case .ended: "Ended"
        }
    }
    private var symbol: String {
        switch state {
        case .needsApproval: "exclamationmark.bubble.fill"
        case .working: "circle.dotted.circle"
        case .idle: "checkmark.circle"
        case .ended: "moon.zzz"
        }
    }
    private var color: Color {
        switch state {
        case .needsApproval: Theme.statusNeedsInput
        case .working: Theme.statusWorking
        case .idle: Theme.statusReady
        case .ended: Theme.statusEnded
        }
    }
}
