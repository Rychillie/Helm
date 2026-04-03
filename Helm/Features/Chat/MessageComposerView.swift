import SwiftUI

struct MessageComposerView: View {
    @Bindable var chatModel: ChatModel
    let connectionState: ConnectionState
    let onSend: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("Message OpenClaw", text: $chatModel.draft, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .padding(HelmTheme.Layout.composerPadding)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: HelmTheme.CornerRadius.composer))
                .overlay {
                    RoundedRectangle(cornerRadius: HelmTheme.CornerRadius.composer)
                        .strokeBorder(Color.primary.opacity(0.05))
                }
                .disabled(chatModel.isSending)
                .accessibilityIdentifier("chat.composer")

            Button("Send", systemImage: "arrow.up.circle.fill", action: onSend)
                .labelStyle(.iconOnly)
                .font(.title2)
                .buttonStyle(.borderedProminent)
                .tint(self.sendTint)
                .disabled(self.isSendDisabled)
                .accessibilityLabel("Send")
                .accessibilityIdentifier("chat.send")
        }
    }

    private var isSendDisabled: Bool {
        self.chatModel.isSending ||
            self.chatModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !self.connectionState.allowsSending
    }

    private var sendTint: Color {
        self.connectionState.allowsSending ? .accentColor : .gray
    }
}
