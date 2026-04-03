import Foundation

struct ChatRuntimeContext: Equatable, Sendable {
    let id: String
    let sessionKey: String
    let createdAt: Date

    nonisolated static func primary(sessionKey: String) -> ChatRuntimeContext {
        ChatRuntimeContext(
            id: sessionKey,
            sessionKey: sessionKey,
            createdAt: .now)
    }

    nonisolated static func ephemeral(prefix: String = "helm-ios") -> ChatRuntimeContext {
        let token = UUID().uuidString.lowercased()
        return ChatRuntimeContext(
            id: token,
            sessionKey: "\(prefix)-\(token)",
            createdAt: .now)
    }
}
