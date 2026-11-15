import SwiftUI

/// Graphite + muted amber palette. Dual light/dark; not inverted black/white.
public enum StudioColor {
    public static func resolved(_ name: Semantic, scheme: ColorScheme) -> Color {
        switch (name, scheme) {
        case (.bgBase, .dark): return Color(red: 0.10, green: 0.105, blue: 0.11)
        case (.bgBase, .light): return Color(red: 0.965, green: 0.96, blue: 0.95)
        case (.bgElevated, .dark): return Color(red: 0.145, green: 0.15, blue: 0.155)
        case (.bgElevated, .light): return Color(red: 1.0, green: 0.995, blue: 0.99)
        case (.bgSidebar, .dark): return Color(red: 0.08, green: 0.085, blue: 0.09)
        case (.bgSidebar, .light): return Color(red: 0.94, green: 0.935, blue: 0.925)
        case (.border, .dark): return Color.white.opacity(0.08)
        case (.border, .light): return Color.black.opacity(0.08)
        case (.textPrimary, .dark): return Color(red: 0.93, green: 0.925, blue: 0.91)
        case (.textPrimary, .light): return Color(red: 0.12, green: 0.12, blue: 0.11)
        case (.textSecondary, .dark): return Color(red: 0.62, green: 0.61, blue: 0.58)
        case (.textSecondary, .light): return Color(red: 0.42, green: 0.41, blue: 0.38)
        case (.textTertiary, .dark): return Color(red: 0.45, green: 0.44, blue: 0.42)
        case (.textTertiary, .light): return Color(red: 0.58, green: 0.56, blue: 0.53)
        case (.accent, _): return Color(red: 0.78, green: 0.58, blue: 0.28)
        case (.accentMuted, .dark): return Color(red: 0.78, green: 0.58, blue: 0.28).opacity(0.22)
        case (.accentMuted, .light): return Color(red: 0.78, green: 0.58, blue: 0.28).opacity(0.14)
        case (.success, _): return Color(red: 0.35, green: 0.62, blue: 0.42)
        case (.warning, _): return Color(red: 0.82, green: 0.58, blue: 0.22)
        case (.danger, _): return Color(red: 0.78, green: 0.32, blue: 0.28)
        @unknown default:
            return Color.gray
        }
    }

    public enum Semantic: Sendable {
        case bgBase, bgElevated, bgSidebar, border
        case textPrimary, textSecondary, textTertiary
        case accent, accentMuted, success, warning, danger
    }
}

public struct StudioPalette {
    public let scheme: ColorScheme

    public init(scheme: ColorScheme) {
        self.scheme = scheme
    }

    public var bgBase: Color { StudioColor.resolved(.bgBase, scheme: scheme) }
    public var bgElevated: Color { StudioColor.resolved(.bgElevated, scheme: scheme) }
    public var bgSidebar: Color { StudioColor.resolved(.bgSidebar, scheme: scheme) }
    public var border: Color { StudioColor.resolved(.border, scheme: scheme) }
    public var textPrimary: Color { StudioColor.resolved(.textPrimary, scheme: scheme) }
    public var textSecondary: Color { StudioColor.resolved(.textSecondary, scheme: scheme) }
    public var textTertiary: Color { StudioColor.resolved(.textTertiary, scheme: scheme) }
    public var accent: Color { StudioColor.resolved(.accent, scheme: scheme) }
    public var accentMuted: Color { StudioColor.resolved(.accentMuted, scheme: scheme) }
    public var success: Color { StudioColor.resolved(.success, scheme: scheme) }
    public var warning: Color { StudioColor.resolved(.warning, scheme: scheme) }
    public var danger: Color { StudioColor.resolved(.danger, scheme: scheme) }
}

private struct StudioPaletteKey: EnvironmentKey {
    static let defaultValue = StudioPalette(scheme: .dark)
}

public extension EnvironmentValues {
    var studioPalette: StudioPalette {
        get { self[StudioPaletteKey.self] }
        set { self[StudioPaletteKey.self] = newValue }
    }
}

public struct StudioPaletteInjector: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    public func body(content: Content) -> some View {
        content.environment(\.studioPalette, StudioPalette(scheme: colorScheme))
    }
}

public extension View {
    func studioPaletteEnvironment() -> some View {
        modifier(StudioPaletteInjector())
    }
}
