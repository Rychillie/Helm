import SwiftUI

struct ChatView: View {
    let connectionModel: ConnectionModel
    @Bindable var chatModel: ChatModel
    let onSend: () -> Void
    let onRetry: (ChatMessage) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if chatModel.messages.isEmpty {
                    self.emptyState
                } else {
                    TranscriptView(messages: chatModel.messages, onRetry: onRetry)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(
            Color(.systemBackground).opacity(0.82),
            in: RoundedRectangle(cornerRadius: HelmTheme.CornerRadius.card))
        .overlay {
            RoundedRectangle(cornerRadius: HelmTheme.CornerRadius.card)
                .strokeBorder(Color.primary.opacity(0.05))
        }
        .safeAreaInset(edge: .bottom, spacing: 12) {
            VStack(spacing: 10) {
                if let composerError = chatModel.composerError {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(composerError.title)
                                .font(.footnote)
                                .bold()
                            Text(composerError.message)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 4)
                }

                MessageComposerView(
                    chatModel: chatModel,
                    connectionState: connectionModel.state,
                    onSend: onSend)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
            .background(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch connectionModel.state {
        case .connected:
            ContentUnavailableView {
                Label("Start the conversation", systemImage: "bubble.left.and.bubble.right")
            } description: {
                Text("Helm is ready. Send the first message when you want the assistant loop to begin.")
            }

        case .connectionLost:
            ContentUnavailableView {
                Label("Connection lost", systemImage: "bolt.slash")
            } description: {
                Text("The transcript stays visible, but sending is paused until the gateway reconnects.")
            }

        case .failed:
            ContentUnavailableView {
                Label("Unable to connect", systemImage: "exclamationmark.triangle")
            } description: {
                Text("Review the gateway settings or retry the connection.")
            }

        default:
            ContentUnavailableView {
                Label("Connect to begin", systemImage: "bolt.horizontal")
            } description: {
                Text("Helm will keep the conversation surface ready as soon as the gateway is reachable.")
            }
        }
    }
}
