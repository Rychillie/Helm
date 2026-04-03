import SwiftUI

struct TranscriptView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let messages: [ChatMessage]
    let onRetry: (ChatMessage) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(messages) { message in
                        MessageBubbleView(message: message) {
                            onRetry(message)
                        }
                        .id(message.id)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .padding(.bottom, 12)
            }
            .accessibilityIdentifier("chat.transcript")
            .onAppear {
                self.scrollToBottom(with: proxy)
            }
            .onChange(of: messages.last?.id) { _, _ in
                self.scrollToBottom(with: proxy)
            }
        }
    }

    private func scrollToBottom(with proxy: ScrollViewProxy) {
        guard let lastMessageID = self.messages.last?.id else {
            return
        }

        let action = {
            proxy.scrollTo(lastMessageID, anchor: .bottom)
        }

        if self.reduceMotion {
            action()
        } else {
            withAnimation(HelmTheme.Motion.subtle, action)
        }
    }
}
