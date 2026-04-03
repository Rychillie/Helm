import Foundation

enum PreviewFixtures {
    static let configuration = GatewayConfiguration(
        endpoint: URL(string: "ws://127.0.0.1:18789")!,
        displayName: "Local Gateway",
        timeoutSeconds: 30,
        authMode: .none)

    static let conversation: [ChatMessage] = [
        ChatMessage(role: .user, body: "Summarize the status of my assistant.", deliveryState: .sent),
        ChatMessage(
            role: .assistant,
            body: "Everything is connected. The assistant is ready for the next request.",
            deliveryState: .sent),
    ]
}
