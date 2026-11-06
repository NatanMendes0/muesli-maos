import SwiftUI

/// A restrained dark material system: deep-ocean background, elevated navy
/// surfaces, and cyan reserved for actions and active state.
enum CoastalTheme {
    static let background = Color(red: 5.0 / 255, green: 13.0 / 255, blue: 26.0 / 255)      // #050D1A
    static let surface = Color(red: 13.0 / 255, green: 27.0 / 255, blue: 42.0 / 255)          // #0D1B2A
    static let surfaceRaised = Color(red: 18.0 / 255, green: 38.0 / 255, blue: 57.0 / 255)
    static let text = Color(red: 230.0 / 255, green: 241.0 / 255, blue: 247.0 / 255)          // #E6F1F7
    static let secondaryText = Color(red: 158.0 / 255, green: 181.0 / 255, blue: 194.0 / 255)
    static let accent = Color(red: 20.0 / 255, green: 138.0 / 255, blue: 157.0 / 255)         // #148A9D
    static let accentBright = Color(red: 34.0 / 255, green: 184.0 / 255, blue: 207.0 / 255)   // #22B8CF
    static let separator = Color.white.opacity(0.10)

    static let accentGradient = LinearGradient(
        colors: [Color(red: 13.0 / 255, green: 40.0 / 255, blue: 64.0 / 255), accent],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

}

extension Color {
    /// Backward-compatible name for the app's existing semantic accent.
    static let oat = CoastalTheme.accentBright
}

struct CoastalCard: ViewModifier {
    var padding: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(CoastalTheme.surfaceRaised.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            }
    }
}

extension View {
    func coastalCard(padding: CGFloat = 12) -> some View {
        modifier(CoastalCard(padding: padding))
    }
}

struct CoastalPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .brightness(configuration.isPressed ? -0.035 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct CoastalPanel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(CoastalTheme.background)
            .foregroundStyle(CoastalTheme.text)
    }
}

extension View {
    func coastalPanel() -> some View { modifier(CoastalPanel()) }
}
