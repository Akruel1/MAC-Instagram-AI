import SwiftUI
import DesignSystem

struct CommandPaletteView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.studioPalette) private var palette
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Go to…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(14)
            Rectangle().fill(palette.border).frame(height: 0.5)
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(filtered) { workspace in
                        Button {
                            model.select(workspace)
                            if workspace.isEnabled {
                                dismiss()
                            }
                        } label: {
                            HStack {
                                Label(workspace.title, systemImage: workspace.systemImage)
                                    .foregroundStyle(workspace.isEnabled ? palette.textPrimary : palette.textTertiary)
                                Spacer()
                                if !workspace.isEnabled {
                                    Text("Coming soon")
                                        .font(StudioType.caption)
                                        .foregroundStyle(palette.textTertiary)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .frame(width: 420, height: 260)
        .background(palette.bgElevated)
        .studioPaletteEnvironment()
    }

    private var filtered: [AppModel.Workspace] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return AppModel.Workspace.allCases }
        return AppModel.Workspace.allCases.filter { $0.title.lowercased().contains(q) }
    }
}
