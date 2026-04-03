import Foundation

struct ChatMessage: Identifiable, Equatable, Sendable {
    enum Role: String, Sendable {
        case user
        case assistant
        case system

        var title: String {
            switch self {
            case .user:
                "You"
            case .assistant:
                "Assistant"
            case .system:
                "Helm"
            }
        }
    }

    enum DeliveryState: Equatable, Sendable {
        case pending
        case sent
        case streaming
        case failed(UserFacingError)
    }

    let id: UUID
    let role: Role
    var body: String
    let createdAt: Date
    var deliveryState: DeliveryState

    init(
        id: UUID = UUID(),
        role: Role,
        body: String,
        createdAt: Date = .now,
        deliveryState: DeliveryState)
    {
        self.id = id
        self.role = role
        self.body = body
        self.createdAt = createdAt
        self.deliveryState = deliveryState
    }

    var failure: UserFacingError? {
        guard case let .failed(error) = self.deliveryState else {
            return nil
        }
        return error
    }

    var isRetryable: Bool {
        self.role == .user && self.failure?.isRecoverable == true
    }
}
