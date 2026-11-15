import SwiftUI

public struct StudioSidebarItem: View {
    public let title: String
    public let systemImage: String
    public let isSelected: Bool
    public let isEnabled: Bool
    public let disabledBadge: String
    public let action: () -> Void

    @Environment(\.studioPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    public init(
        title: String,
        systemImage: String,
        isSelected: Bool,
        isEnabled: Bool = true,
        disabledBadge: String = "Coming soon",
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.disabledBadge = disabledBadge
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 16, alignment: .center)
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(titleColor)
                Spacer(minLength: 0)
                if !isEnabled {
                    Text(disabledBadge)
                        .font(StudioType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(backgroundFill)
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule()
                        .fill(palette.accent)
                        .frame(width: 2, height: 14)
                        .padding(.leading, 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Keep disabled items clickable so FeaturePolicy can surface an informational message.
        .opacity(isEnabled || isSelected ? 1 : 0.7)
        .onHover { hovering = $0 }
        .animation(StudioMotion.reduced(reduceMotion, StudioMotion.hover), value: hovering)
        .animation(StudioMotion.reduced(reduceMotion, StudioMotion.state), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(isEnabled ? title : "\(title), \(disabledBadge)")
        .accessibilityHint(isEnabled ? "" : "Opens a short notice about availability")
    }

    private var iconColor: Color {
        if isSelected { return palette.accent }
        return isEnabled ? palette.textSecondary : palette.textTertiary
    }

    private var titleColor: Color {
        if isSelected { return palette.textPrimary }
        return isEnabled ? palette.textSecondary : palette.textTertiary
    }

    private var backgroundFill: Color {
        if isSelected { return palette.accentMuted }
        if hovering && isEnabled { return palette.border.opacity(0.7) }
        return .clear
    }
}

public struct StudioStatusPill: View {
    public enum Kind { case neutral, success, warning, danger, accent }

    public let text: String
    public let kind: Kind

    @Environment(\.studioPalette) private var palette

    public init(_ text: String, kind: Kind = .neutral) {
        self.text = text
        self.kind = kind
    }

    public var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(background)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(palette.border.opacity(0.8), lineWidth: 0.5)
            )
    }

    private var foreground: Color {
        switch kind {
        case .neutral: return palette.textSecondary
        case .success: return palette.success
        case .warning: return palette.warning
        case .danger: return palette.danger
        case .accent: return palette.accent
        }
    }

    private var background: Color {
        foreground.opacity(0.10)
    }
}

public struct StudioInlineStatus: View {
    public let label: String
    public let ok: Bool

    @Environment(\.studioPalette) private var palette

    public init(_ label: String, ok: Bool) {
        self.label = label
        self.ok = ok
    }

    public var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(ok ? palette.success : palette.textTertiary)
                .frame(width: 5, height: 5)
            Text(label)
                .font(StudioType.caption)
                .foregroundStyle(palette.textTertiary)
        }
    }
}

public struct StudioProgressBar: View {
    public let progress: Double

    @Environment(\.studioPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(progress: Double) {
        self.progress = progress
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.border.opacity(0.55))
                Capsule()
                    .fill(palette.accent)
                    .frame(width: max(3, geo.size.width * min(1, max(0, progress))))
                    .animation(StudioMotion.reduced(reduceMotion, StudioMotion.state), value: progress)
            }
        }
        .frame(height: 3)
        .accessibilityValue(Text("\(Int(progress * 100)) percent"))
    }
}

public struct StudioSectionLabel: View {
    public let title: String

    @Environment(\.studioPalette) private var palette

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(palette.textTertiary)
    }
}

public struct StudioToolbarButton: View {
    public let title: String
    public let systemImage: String?
    public let isPrimary: Bool
    public let isEnabled: Bool
    public let action: () -> Void

    @Environment(\.studioPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    public init(
        _ title: String,
        systemImage: String? = nil,
        isPrimary: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isPrimary = isPrimary
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, isPrimary ? 12 : 10)
            .padding(.vertical, 6)
            .foregroundStyle(foreground)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { hovering = $0 }
        .animation(StudioMotion.reduced(reduceMotion, StudioMotion.hover), value: hovering)
    }

    private var foreground: Color {
        if isPrimary { return Color(red: 0.12, green: 0.10, blue: 0.08) }
        return palette.textPrimary
    }

    private var background: Color {
        if isPrimary { return hovering ? palette.accent.opacity(0.92) : palette.accent }
        return hovering ? palette.bgElevated.opacity(0.9) : palette.bgElevated
    }

    private var border: Color {
        isPrimary ? palette.accent.opacity(0.35) : palette.border
    }
}
