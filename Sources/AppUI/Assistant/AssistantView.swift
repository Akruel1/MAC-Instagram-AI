import SwiftUI
import DesignSystem
import BackendInterface

struct AssistantView: View {
    @Bindable var model: AppModel
    @Environment(\.studioPalette) private var palette

    var body: some View {
        HSplitView {
            conversationList
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
            chatPane
                .frame(minWidth: 420)
        }
        .background(palette.bgBase)
        .task { await model.loadConversations() }
    }

    private var conversationList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Conversations")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
                .padding(14)
            Rectangle().fill(palette.border).frame(height: 0.5)
            if model.conversations.isEmpty {
                Text("No conversations yet")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textTertiary)
                    .padding(14)
                Spacer()
            } else {
                List(model.conversations, id: \.id, selection: $model.selectedConversationId) { conversation in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(conversation.title.isEmpty ? "Untitled" : conversation.title)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Text(conversation.model)
                            .font(StudioType.caption)
                            .foregroundStyle(palette.textTertiary)
                    }
                    .tag(conversation.id)
                }
                .listStyle(.sidebar)
            }
        }
        .background(palette.bgSidebar)
    }

    private var chatPane: some View {
        VStack(spacing: 0) {
            WorkspaceHeader(
                title: "Assistant",
                status: model.features.claudeConfigured ? "Claude connected" : "Claude not configured",
                statusColor: model.features.claudeConfigured ? palette.success : palette.warning
            ) {
                if !model.features.claudeConfigured {
                    StudioToolbarButton("Connect Claude", systemImage: "key.fill", isPrimary: true) {
                        model.claudeSetupPresented = true
                    }
                }
            }
            .padding(.horizontal, StudioSpace.lg)

            if !model.features.claudeConfigured {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No fabricated replies")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text("Connect a Claude API key to chat. Until then, this workspace stays quiet.")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.textSecondary)
                }
                .padding(.horizontal, StudioSpace.lg)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(model.chatMessages, id: \.id) { message in
                                messageBubble(message)
                                    .id(message.id)
                            }
                        }
                        .padding(StudioSpace.lg)
                    }
                    .onChange(of: model.chatMessages.count) { _, _ in
                        if let last = model.chatMessages.last?.id {
                            withAnimation(StudioMotion.state) {
                                proxy.scrollTo(last, anchor: .bottom)
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    TextField("Message Claude…", text: $model.chatDraft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...4)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.border, lineWidth: 0.5))
                    StudioToolbarButton(model.chatBusy ? "Sending…" : "Send", isPrimary: true, isEnabled: !model.chatBusy) {
                        Task { await model.sendChat() }
                    }
                }
                .padding(StudioSpace.lg)
            }
        }
        .onChange(of: model.selectedConversationId) { _, id in
            guard let id else { return }
            model.chatMessages = (try? model.services.chatMessages(conversationId: id)) ?? []
        }
    }

    private func messageBubble(_ message: ChatMessageDTO) -> some View {
        let isUser = message.role == "user"
        return VStack(alignment: .leading, spacing: 4) {
            Text(isUser ? "You" : "Claude")
                .font(StudioType.caption)
                .foregroundStyle(palette.textTertiary)
            Text(message.text)
                .font(.system(size: 13))
                .foregroundStyle(palette.textPrimary)
                .textSelection(.enabled)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isUser ? palette.accentMuted.opacity(0.45) : palette.bgElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(palette.border, lineWidth: 0.5)
                )
        }
        .frame(maxWidth: 640, alignment: .leading)
    }
}
