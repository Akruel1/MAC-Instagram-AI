import SwiftUI

public struct DonateButton: View {
    public let action: () -> Void

    @Environment(\.studioPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var shimmerPhase: CGFloat = 0

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text("Donate pls 🥺")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Color(red: 0.14, green: 0.11, blue: 0.08))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(palette.accent.opacity(hovering ? 0.95 : 0.88))
                    if hovering && !reduceMotion {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0),
                                        Color.white.opacity(0.28),
                                        Color.white.opacity(0)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .mask(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                            )
                            .offset(x: shimmerPhase)
                            .opacity(0.55)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(palette.accent.opacity(0.35), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .help("Support the project")
        .accessibilityLabel("Donate please")
        .accessibilityHint("Opens optional donation options")
        .onHover { hovering in
            self.hovering = hovering
            guard hovering, !reduceMotion else {
                shimmerPhase = 0
                return
            }
            shimmerPhase = -80
            withAnimation(.easeInOut(duration: 0.85)) {
                shimmerPhase = 80
            }
        }
        .animation(StudioMotion.reduced(reduceMotion, StudioMotion.hover), value: hovering)
    }
}
