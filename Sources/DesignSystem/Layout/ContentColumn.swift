import SwiftUI

/// Keeps primary content readable on large displays without stretching full-bleed.
public struct ContentColumn<Content: View>: View {
    public let maxWidth: CGFloat
    public let horizontalPadding: CGFloat
    @ViewBuilder public let content: () -> Content

    public init(
        maxWidth: CGFloat = 860,
        horizontalPadding: CGFloat = StudioSpace.xl,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.maxWidth = maxWidth
        self.horizontalPadding = horizontalPadding
        self.content = content
    }

    public var body: some View {
        ScrollView {
            content()
                .frame(maxWidth: maxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, horizontalPadding)
                .padding(.top, StudioSpace.lg)
                .padding(.bottom, StudioSpace.xl)
        }
    }
}

public struct WorkspaceHeader: View {
    public let title: String
    public let status: String?
    public let statusColor: Color?

    @Environment(\.studioPalette) private var palette
    private let trailing: AnyView

    public init(
        title: String,
        status: String? = nil,
        statusColor: Color? = nil
    ) {
        self.title = title
        self.status = status
        self.statusColor = statusColor
        self.trailing = AnyView(EmptyView())
    }

    public init<Trailing: View>(
        title: String,
        status: String? = nil,
        statusColor: Color? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.status = status
        self.statusColor = statusColor
        self.trailing = AnyView(trailing())
    }

    public var body: some View {
        HStack(alignment: .center, spacing: StudioSpace.md) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                if let status {
                    HStack(spacing: 8) {
                        if let statusColor {
                            Circle().fill(statusColor).frame(width: 7, height: 7)
                        }
                        Text(status)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
            Spacer(minLength: StudioSpace.md)
            trailing
        }
        .padding(.bottom, StudioSpace.lg)
    }
}
