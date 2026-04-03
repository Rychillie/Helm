import Foundation

enum AssistantStreamEvent: Sendable {
    case started
    case delta(String)
    case completed
    case failed(UserFacingError)
}
