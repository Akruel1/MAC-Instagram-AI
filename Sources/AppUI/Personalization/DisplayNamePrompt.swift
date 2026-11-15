import SwiftUI
import DesignSystem
import Persistence

struct DisplayNamePrompt: View {
    @Bindable var model: AppModel
    @Environment(\.studioPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What should we call you?")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            Text("A friendly name for the sidebar. It stays on this Mac and is never uploaded.")
                .font(.system(size: 13))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Your name", text: $model.displayNameDraft)
                .textFieldStyle(.roundedBorder)
                .onChange(of: model.displayNameDraft) { _, value in
                    if value.count > DisplayNamePolicy.maxLength {
                        model.displayNameDraft = String(value.prefix(DisplayNamePolicy.maxLength))
                    }
                }

            HStack {
                Button("Not now") { model.skipDisplayNamePrompt() }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                StudioToolbarButton("Save", isPrimary: true) {
                    model.saveDisplayNameFromDraft()
                }
            }
        }
        .padding(22)
        .frame(width: 420)
        .background(palette.bgElevated)
        .studioPaletteEnvironment()
    }
}
