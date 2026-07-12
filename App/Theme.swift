import SwiftUI
import AppKit
import FabledCore

/// Fabled design tokens, v1 (2026-07-11). The language is Fabled's own —
/// seeded by the harp icon's palette (aged bronze, midnight teal, code-glow)
/// over native macOS structure, with Claude's serif warmth in conversation.
/// Rules: App views take every color, font, spacing, radius, and animation
/// from here. A raw literal in a view is a review failure.
enum Theme {
    // MARK: - Palette (mode-aware, from FabledCore.Palette)

    /// Light/dark-adaptive color without an asset catalog entry.
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    /// Pack a 0xRRGGBB hex into an sRGB NSColor at the given alpha.
    private static func ns(_ hex: UInt32, alpha: Double) -> NSColor {
        NSColor(srgbRed: Double((hex >> 16) & 0xFF) / 255,
                green: Double((hex >> 8) & 0xFF) / 255,
                blue: Double(hex & 0xFF) / 255, alpha: alpha)
    }
    /// Bridge one locked `Palette.Tone` to a mode-aware SwiftUI Color.
    static func token(_ tone: Palette.Tone) -> Color {
        dynamic(light: ns(tone.light, alpha: tone.lightAlpha),
                dark: ns(tone.dark, alpha: tone.darkAlpha))
    }
    // Surfaces
    static let ground = token(Palette.ground)
    static let surfaceSide = token(Palette.surfaceSide)
    static let panel = token(Palette.panel)
    static let panelRecessed = token(Palette.panelRecessed)
    static let hairline = token(Palette.hairline)
    static let windowBorder = token(Palette.windowBorder)
    // Text
    static let ink = token(Palette.ink)
    static let muted = token(Palette.muted)
    static let faint = token(Palette.faint)
    // Accent + status
    static let accentBronze = token(Palette.accent)
    static let accent2 = token(Palette.accent2)
    static let live = token(Palette.live)
    static let needsYou = token(Palette.needsYou)
    static let review = token(Palette.review)
    static let diffAddColor = token(Palette.diffAdd)
    static let diffDelColor = token(Palette.diffDel)

    // MARK: - Brand (retuned to the mode-aware palette)

    /// Claude clay (#D97757) — send button, working state, warm accents.
    static let clay = Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255)
    /// Aged harp bronze — brand chrome: wordmark, selected chips.
    /// Now mode-aware via `Palette.accent` (bronze in dark, umber in light).
    static let bronze = accentBronze
    /// Welcome backdrop — the app ground (Teal Midnight dark / Linen light).
    static let welcomeBackdrop = ground

    // MARK: - Status (color + shape + words, never color alone — feature 14)

    /// Needs input — unmissable amber. Icon: exclamationmark.bubble.fill.
    static let statusNeedsInput = needsYou
    /// Working — live teal. Icon: circle.dotted.circle.
    static let statusWorking = live
    /// Idle-with-history / ready for review — calm blue. Icon: tray.full.
    static let statusReady = review
    /// Ended / archived — neutral. Icon: moon.zzz.
    static let statusEnded = Color.secondary

    // MARK: - Wordmark

    /// Wordmark colour + size to match the mockup's 22 pt serif "Fabled".
    static let wordmarkColor = token(Palette.accent)
    static let wordmark = Font.system(size: 22, design: .serif).weight(.semibold)

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
