import SwiftUI
import AppKit

/// Paper-and-ink theme palette matching Muesli Windows (Light & Dark modes).
/// Kept named `CoastalTheme` + `Color.oat` so existing views compile seamlessly.
enum CoastalTheme {
    private static func dynamic(light: UInt32, dark: UInt32, alpha: Double = 1.0) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            let r = CGFloat((hex >> 16) & 0xFF) / 255.0
            let g = CGFloat((hex >> 8) & 0xFF) / 255.0
            let b = CGFloat(hex & 0xFF) / 255.0
            return NSColor(srgbRed: r, green: g, blue: b, alpha: alpha)
        })
    }

    static let background = dynamic(light: 0xF7F6F2, dark: 0x161614)      // --bg
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x1F1F1C)         // --panel
    static let surfaceSoft = dynamic(light: 0xFBFAF7, dark: 0x262622)     // --panel-soft
    static let surfaceRaised = dynamic(light: 0xEFECE3, dark: 0x2A2A25)
    static let text = dynamic(light: 0x21201C, dark: 0xF2F0E8)            // --ink
    static let bodyText = dynamic(light: 0x3D3B34, dark: 0xD5D2C8)        // --body-c
    static let secondaryText = dynamic(light: 0x75726A, dark: 0x9E9B90)   // --muted
    static let faintText = dynamic(light: 0xA9A69B, dark: 0x6F6C63)       // --faint
    static let accent = dynamic(light: 0x5F7A24, dark: 0x9EC24B)          // --accent
    static let accentSoft = dynamic(light: 0xEFF1E3, dark: 0x28301B)      // --accent-soft
    static let accentBright = dynamic(light: 0x5F7A24, dark: 0x9EC24B)
    static let separator = dynamic(light: 0xE8E6DE, dark: 0x2F2F2A)       // --border
    static let border = dynamic(light: 0xD9D6CB, dark: 0x3E3E37)          // --border-strong
    static let selectionBg = dynamic(light: 0xE4E2D5, dark: 0x3C3E2D)
    static let hoverBg = dynamic(light: 0x21201C, dark: 0xF2F0E8, alpha: 0.05)

    static let danger = dynamic(light: 0xB3402F, dark: 0xE06C5A)
    static let dangerSoft = dynamic(light: 0xF9ECE9, dark: 0x36201D)
    static let ok = dynamic(light: 0x16A34A, dark: 0x4ADE80)
    static let infoBg = dynamic(light: 0xEDF4FF, dark: 0x172336)
    static let infoBorder = dynamic(light: 0xC7DCFF, dark: 0x274066)
    static let infoFg = dynamic(light: 0x1E40AF, dark: 0x93C5FD)
    static let badgeBg = dynamic(light: 0xDBEAFE, dark: 0x1E3A5F)
    static let badgeFg = dynamic(light: 0x1E40AF, dark: 0x93C5FD)
    static let warnBg = dynamic(light: 0xFCF7EA, dark: 0x2C2514)
    static let warnFg = dynamic(light: 0x79601E, dark: 0xE9C46A)
    static let warnBorder = dynamic(light: 0xEDE3C6, dark: 0x4A3D1D)
    static let btnInkBg = dynamic(light: 0x21201C, dark: 0xF2F0E8)
    static let btnInkFg = dynamic(light: 0xFFFFFF, dark: 0x181815)
}

extension Color {
    static let oat = CoastalTheme.accent
}

extension View {
    func coastalShell() -> some View {
        self.background(CoastalTheme.background)
    }

    func muesliCard(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .background(CoastalTheme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(CoastalTheme.separator, lineWidth: 1))
    }
}
