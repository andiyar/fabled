import SwiftUI

enum Theme {
    /// Claude clay (#D97757) — send button and accents.
    static let clay = Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255)

    /// Claude's voice is serif; chrome stays SF Pro.
    static func assistantFont(_ style: Font.TextStyle = .body) -> Font {
        .system(style, design: .serif)
    }
}
