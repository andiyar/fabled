import Foundation

/// The Ben-locked Fabled colors (co-design sprint 2026-07-12), as raw hex so the
/// values can be pinned by a unit test — a typo in a value Ben approved is a test
/// failure, not a silent drift. `App/Theme.swift` maps these to mode-aware SwiftUI
/// Colors. Dark is fully locked (every mockup renders dark); some light values are
/// provisional (README locks the core; the rest are flagged for Ben at the B0 gate).
public enum Palette {
    public struct Tone: Sendable {
        public let dark: UInt32
        public let light: UInt32
        public let darkAlpha: Double
        public let lightAlpha: Double
        public init(dark: UInt32, light: UInt32, darkAlpha: Double = 1, lightAlpha: Double = 1) {
            self.dark = dark; self.light = light
            self.darkAlpha = darkAlpha; self.lightAlpha = lightAlpha
        }
    }
    // Locked (README + mockups)
    public static let ground        = Tone(dark: 0x0C1618, light: 0xF5F4EF)
    public static let surfaceSide   = Tone(dark: 0x0A1315, light: 0xEBEAE3)
    public static let panel         = Tone(dark: 0x122120, light: 0xFFFFFF)
    public static let panelRecessed = Tone(dark: 0x0F1C1D, light: 0xF6F6F0)
    public static let ink           = Tone(dark: 0xE9EEEA, light: 0x23211C)
    public static let muted         = Tone(dark: 0x8EA29A, light: 0x6F6B61)
    public static let faint         = Tone(dark: 0x5C6F68, light: 0xA39F93)
    public static let hairline      = Tone(dark: 0x78A096, light: 0xE6E4DB, darkAlpha: 0.15)
    public static let accent        = Tone(dark: 0xCFA669, light: 0xA9703B)
    public static let needsYou      = Tone(dark: 0xE0B15C, light: 0xB2751C)
    public static let review        = Tone(dark: 0x7FB0D0, light: 0x4E6E8C)
    // Provisional light (⚠️ verify with Ben at the B0 gate)
    public static let windowBorder  = Tone(dark: 0x1D2E2D, light: 0xDAD8CE)
    public static let accent2       = Tone(dark: 0xD8AE6D, light: 0x8A5A2E)
    public static let live          = Tone(dark: 0x5AC9B4, light: 0x2FA28C)
    public static let diffAdd       = Tone(dark: 0x7FD8A2, light: 0x3B9E63)
    public static let diffDel       = Tone(dark: 0xE7A79B, light: 0xC0503F)
}
