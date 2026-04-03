import SwiftUI

struct MessageBubbleView: View {
    let message: ChatMessage
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: self.isUser ? .trailing : .leading, spacing: 8) {
            Text(message.role.title)
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Text(message.body)
                    .font(.body)
                    .foregroundStyle(.primary)

                if message.deliveryState == .streaming {
                    Label("Receiving response…", systemImage: "ellipsis.message")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let failure = message.failure {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(failure.message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if message.isRetryable {
                            Button("Retry message", systemImage: "arrow.clockwise", action: onRetry)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .accessibilityIdentifier("message.retry")
                        }
                    }
                }
            }
            .padding(HelmTheme.Layout.bubblePadding)
            .background(self.backgroundStyle, in: RoundedRectangle(cornerRadius: HelmTheme.CornerRadius.bubble))
        }
        .frame(maxWidth: .infinity, alignment: self.isUser ? .trailing : .leading)
    }

    private var isUser: Bool {
        self.message.role == .user
    }

    private var backgroundStyle: Color {
        switch self.message.role {
        case .user:
            Color.accentColor.opacity(0.16)
        case .assistant:
            Color(.secondarySystemBackground)
        case .system:
            Color.orange.opacity(0.12)
        }
    }
}
