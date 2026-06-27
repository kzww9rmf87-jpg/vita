import SwiftUI

// MARK: — Design System VITA
// Principe : charge cognitive minimale, 3 couleurs maximum par écran,
// navigation instantanée, décisions en < 5 secondes.

enum VitaColor {
    // Fond principal — ne jamais utiliser blanc pur (fatigue oculaire)
    static let background    = Color("Background")       // Gris très clair
    static let surface       = Color("Surface")          // Blanc cassé
    static let surfaceHigh   = Color("SurfaceHigh")      // Légèrement plus sombre

    // Accent principal — vert sauge (santé, sécurité)
    static let accent        = Color("Accent")           // #6B8F71
    static let accentLight   = Color("AccentLight")      // #A8C4AC
    static let accentDark    = Color("AccentDark")       // #4A6B50

    // États
    static let warning       = Color("Warning")          // Ambre — jamais rouge
    static let success       = Color("Success")          // Vert doux
    static let neutral       = Color("Neutral")          // Gris moyen

    // Texte
    static let textPrimary   = Color("TextPrimary")      // Quasi-noir
    static let textSecondary = Color("TextSecondary")    // Gris
    static let textTertiary  = Color("TextTertiary")     // Gris clair
}

enum VitaFont {
    static func title(_ size: CGFloat = 28) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
    static func headline(_ size: CGFloat = 18) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
    static func body(_ size: CGFloat = 16) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }
    static func caption(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .medium, design: .default)
    }
    static func mono(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }
}

enum VitaSpacing {
    static let xs: CGFloat  = 4
    static let sm: CGFloat  = 8
    static let md: CGFloat  = 16
    static let lg: CGFloat  = 24
    static let xl: CGFloat  = 32
    static let xxl: CGFloat = 48
}

enum VitaRadius {
    static let sm: CGFloat  = 8
    static let md: CGFloat  = 12
    static let lg: CGFloat  = 20
    static let full: CGFloat = 999
}

// MARK: — Animation
extension Animation {
    static let vitaDefault = Animation.spring(response: 0.35, dampingFraction: 0.8)
    static let vitaFast    = Animation.easeOut(duration: 0.18)
}

// MARK: — ViewModifiers
struct VitaCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(VitaColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: VitaRadius.lg))
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

struct VitaPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(VitaFont.headline(16))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(VitaColor.accent)
            .clipShape(RoundedRectangle(cornerRadius: VitaRadius.md))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.vitaFast, value: configuration.isPressed)
    }
}

struct VitaSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(VitaFont.body())
            .foregroundColor(VitaColor.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .overlay(
                RoundedRectangle(cornerRadius: VitaRadius.md)
                    .stroke(VitaColor.accentLight, lineWidth: 1.5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.vitaFast, value: configuration.isPressed)
    }
}

extension View {
    func vitaCard() -> some View {
        modifier(VitaCardStyle())
    }
}
