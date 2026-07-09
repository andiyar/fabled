import SwiftUI

enum Theme {
    /// Claude clay (#D97757) — send button and accents.
    static let clay = Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255)

    /// Conversation column cap. 760 shipped in Plan 3; widened with the
    /// inspector layout so diffs breathe (gate feedback: bubble-width tuning).
    static let contentMaxWidth: CGFloat = 820

    /// Claude's voice is serif; chrome stays SF Pro.
    static func assistantFont(_ style: Font.TextStyle = .body) -> Font {
        .system(style, design: .serif)
    }
}
