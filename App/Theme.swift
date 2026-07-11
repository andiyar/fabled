import SwiftUI
import AppKit

/// Fabled design tokens, v1 (2026-07-11). The language is Fabled's own —
/// seeded by the harp icon's palette (aged bronze, midnight teal, code-glow)
/// over native macOS structure, with Claude's serif warmth in conversation.
/// Rules: App views take every color, font, spacing, radius, and animation
/// from here. A raw literal in a view is a review failure.
enum Theme {
    // MARK: - Palette

    /// Claude clay (#D97757) — send button, working state, warm accents.
    static let clay = Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255)
    /// Aged harp bronze (#B08D57) — brand chrome: wordmark, selected chips.
    static let bronze = Color(red: 0xB0 / 255, green: 0x8D / 255, blue: 0x57 / 255)
    /// Midnight teal (#12333B) — the icon's field; welcome backdrop in dark.
    static let midnightTeal = Color(red: 0x12 / 255, green: 0x33 / 255, blue: 0x3B / 255)
    /// Code-glow (#69D2B4) — the strings' phosphor; sparing highlights only.
    static let glow = Color(red: 0x69 / 255, green: 0xD2 / 255, blue: 0xB4 / 255)

    /// Light/dark-adaptive color without an asset catalog entry.
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    /// Welcome backdrop: whisper of teal in dark, warm paper in light.
    static let welcomeBackdrop = dynamic(
        light: NSColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1),
        dark: NSColor(red: 0.07, green: 0.13, blue: 0.15, alpha: 1))

    // MARK: - Status (color + shape + words, never color alone — feature 14)

    /// Needs input — unmissable orange. Icon: exclamationmark.bubble.fill.
    static let statusNeedsInput = Color(red: 0xE0 / 255, green: 0x8A / 255, blue: 0x3C / 255)
    /// Working — clay. Icon: circle.dotted.circle.
    static let statusWorking = clay
    /// Idle-with-history / ready for review — calm blue. Icon: tray.full.
    static let statusReady = Color(red: 0x4E / 255, green: 0x8F / 255, blue: 0xD1 / 255)
    /// Ended / archived — neutral. Icon: moon.zzz.
    static let statusEnded = Color.secondary

    // MARK: - Type

    /// Claude's voice is serif; chrome stays SF Pro.
    static func assistantFont(_ style: Font.TextStyle = .body) -> Font {
        .system(style, design: .serif)
    }
    /// Wordmark / welcome hero.
    static let display = Font.system(.largeTitle, design: .serif).weight(.semibold)
    /// Section headings on the welcome surface.
    static let heading = Font.system(.title3, design: .serif).weight(.medium)

    // MARK: - Layout

    /// Conversation column cap (Plan 4a T12).
    static let contentMaxWidth: CGFloat = 820
    /// 4-pt spacing grid.
    static let spaceXS: CGFloat = 4
    static let spaceS: CGFloat = 8
    static let spaceM: CGFloat = 12
    static let spaceL: CGFloat = 16
    static let spaceXL: CGFloat = 24
    /// Corner radii: rows/cards vs panels/sheets.
    static let radiusCard: CGFloat = 8
    static let radiusPanel: CGFloat = 12

    // MARK: - Motion

    /// Row/card state changes (selection, chips appearing).
    static let snap = Animation.snappy(duration: 0.18)
    /// Larger settles (cards expanding, welcome sections).
    static let settle = Animation.smooth(duration: 0.25)
}
