import Foundation
import Observation

@MainActor
@Observable
final class ChatModel {
    var messages: [ChatMessage] = []
    var draft = ""
    var runtimeContext: ChatRuntimeContext?
    var composerError: UserFacingError?
    var isSending = false

    func clearComposerError() {
        self.composerError = nil
    }

    func send(using client: (any OpenClawClient)?, connectionState: ConnectionState) async {
        let text = self.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return
        }

        guard connectionState.allowsSending, let client else {
            self.composerError = .connectionRequired()
            return
        }

        self.draft = ""
        await self.performSend(text: text, existingUserMessageID: nil, using: client)
    }

    func retry(_ message: ChatMessage, using client: (any OpenClawClient)?, connectionState: ConnectionState) async {
        guard message.isRetryable else {
            return
        }

        guard connectionState.allowsSending, let client else {
            self.composerError = .connectionRequired()
            return
        }

        await self.performSend(text: message.body, existingUserMessageID: message.id, using: client)
    }

    func resetRuntimeState() {
        self.draft = ""
        self.runtimeContext = nil
        self.composerError = nil
        self.isSending = false
        self.messages.removeAll()
    }

    private func performSend(
        text: String,
        existingUserMessageID: UUID?,
        using client: any OpenClawClient) async
    {
        guard !self.isSending else {
            return
        }

        self.composerError = nil
        self.isSending = true

        let userMessageID = existingUserMessageID ?? UUID()
        if let existingUserMessageID {
            self.updateMessage(existingUserMessageID) { message in
                message.deliveryState = .pending
            }
        } else {
            self.messages.append(ChatMessage(
                id: userMessageID,
                role: .user,
                body: text,
                deliveryState: .pending))
        }

        defer {
            self.isSending = false
        }

        do {
            let runtimeContext: ChatRuntimeContext
            if let existingRuntimeContext = self.runtimeContext {
                runtimeContext = existingRuntimeContext
            } else {
                runtimeContext = try await client.prepareChatContext()
                self.runtimeContext = runtimeContext
            }

            self.updateMessage(userMessageID) { message in
                message.deliveryState = .sent
            }

            var assistantMessageID: UUID?
            var streamFailed = false

            for try await event in client.sendMessage(text, context: runtimeContext) {
                switch event {
                case .started:
                    let placeholder = ChatMessage(
                        role: .assistant,
                        body: "",
                        deliveryState: .streaming)
                    assistantMessageID = placeholder.id
                    self.messages.append(placeholder)

                case let .delta(delta):
                    if assistantMessageID == nil {
                        let placeholder = ChatMessage(
                            role: .assistant,
                            body: "",
                            deliveryState: .streaming)
                        assistantMessageID = placeholder.id
                        self.messages.append(placeholder)
                    }

                    if let assistantMessageID {
                        self.updateMessage(assistantMessageID) { message in
                            message.body += delta
                            message.deliveryState = .streaming
                        }
                    }

                case .completed:
                    if let assistantMessageID {
                        self.updateMessage(assistantMessageID) { message in
                            message.deliveryState = .sent
                        }
                    }

                case let .failed(error):
                    streamFailed = true
                    self.handleSendFailure(
                        error,
                        userMessageID: userMessageID,
                        assistantMessageID: assistantMessageID)
                }
            }

            if !streamFailed, let assistantMessageID {
                self.updateMessage(assistantMessageID) { message in
                    if message.body.isEmpty {
                        message.body = "No visible response was returned."
                    }
                    message.deliveryState = .sent
                }
            }

            if !streamFailed, assistantMessageID == nil {
                self.handleSendFailure(
                    .sendFailed(details: "OpenClaw did not return a visible reply."),
                    userMessageID: userMessageID,
                    assistantMessageID: nil)
            }
        } catch {
            self.handleSendFailure(
                .wrapped(
                    error,
                    fallbackTitle: "Message failed",
                    recoverySuggestion: "Retry when the connection is ready."),
                userMessageID: userMessageID,
                assistantMessageID: nil)
        }
    }

    private func handleSendFailure(
        _ error: UserFacingError,
        userMessageID: UUID,
        assistantMessageID: UUID?)
    {
        self.updateMessage(userMessageID) { message in
            message.deliveryState = .failed(error)
        }

        if let assistantMessageID {
            self.updateMessage(assistantMessageID) { message in
                if message.body.isEmpty {
                    message.body = "No response received."
                }
                message.deliveryState = .failed(error)
            }
        }

        self.composerError = error
    }

    private func updateMessage(_ id: UUID, update: (inout ChatMessage) -> Void) {
        guard let index = self.messages.firstIndex(where: { $0.id == id }) else {
            return
        }

        update(&self.messages[index])
    }
}
