import Testing
@testable import FabledCore

struct PaletteTests {
    @Test func lockedDarkValuesMatchTheMockups() {
        #expect(Palette.ground.dark == 0x0C1618)
        #expect(Palette.surfaceSide.dark == 0x0A1315)
        #expect(Palette.panel.dark == 0x122120)
        #expect(Palette.ink.dark == 0xE9EEEA)
        #expect(Palette.accent.dark == 0xCFA669)
        #expect(Palette.live.dark == 0x5AC9B4)
        #expect(Palette.needsYou.dark == 0xE0B15C)
    }
    @Test func lockedLightValuesMatchTheReadme() {
        #expect(Palette.ground.light == 0xF5F4EF)
        #expect(Palette.surfaceSide.light == 0xEBEAE3)
        #expect(Palette.panel.light == 0xFFFFFF)
        #expect(Palette.ink.light == 0x23211C)
        #expect(Palette.accent.light == 0xA9703B)
        #expect(Palette.review.light == 0x4E6E8C)
    }
    @Test func hairlineCarriesItsDarkAlpha() {
        #expect(Palette.hairline.darkAlpha == 0.15)
    }
}
