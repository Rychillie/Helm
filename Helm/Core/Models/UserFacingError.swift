import Foundation

struct UserFacingError: Error, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let message: String
    let recoverySuggestion: String?
    let isRecoverable: Bool

    init(
        id: String = UUID().uuidString,
        title: String,
        message: String,
        recoverySuggestion: String? = nil,
        isRecoverable: Bool = true)
    {
        self.id = id
        self.title = title
        self.message = message
        self.recoverySuggestion = recoverySuggestion
        self.isRecoverable = isRecoverable
    }

    static func invalidEndpoint() -> UserFacingError {
        UserFacingError(
            title: "Invalid gateway URL",
            message: "Use a WebSocket URL that starts with ws:// or wss://.",
            recoverySuggestion: "Check the gateway address and try again.")
    }

    static func missingCredential(for authMode: GatewayAuthMode) -> UserFacingError {
        let label = authMode.fieldTitle?.lowercased() ?? "credential"
        return UserFacingError(
            title: "Missing credential",
            message: "This connection requires a \(label).",
            recoverySuggestion: "Enter the credential and try again.")
    }

    static func invalidTimeout() -> UserFacingError {
        UserFacingError(
            title: "Invalid timeout",
            message: "Choose a timeout between 5 and 120 seconds.",
            recoverySuggestion: "Adjust the timeout and try again.")
    }

    static func connectionRequired() -> UserFacingError {
        UserFacingError(
            title: "Connection required",
            message: "Connect to OpenClaw before sending a message.",
            recoverySuggestion: "Reconnect and try again.")
    }

    static func connectionFailed(details: String) -> UserFacingError {
        UserFacingError(
            title: "Unable to connect",
            message: details,
            recoverySuggestion: "Check the gateway and try again.")
    }

    static func connectionLost(details: String? = nil) -> UserFacingError {
        UserFacingError(
            title: "Connection lost",
            message: details ?? "The gateway is no longer reachable.",
            recoverySuggestion: "Reconnect to continue.")
    }

    static func sendFailed(details: String) -> UserFacingError {
        UserFacingError(
            title: "Message failed",
            message: details,
            recoverySuggestion: "Retry when the connection is ready.")
    }

    static func persistenceFailed(details: String) -> UserFacingError {
        UserFacingError(
            title: "Unable to save settings",
            message: details,
            recoverySuggestion: "Review the settings and try again.")
    }

    static func wrapped(_ error: Error, fallbackTitle: String, recoverySuggestion: String? = nil) -> UserFacingError {
        if let userFacingError = error as? UserFacingError {
            return userFacingError
        }

        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return UserFacingError(
            title: fallbackTitle,
            message: description.isEmpty ? "Something went wrong." : description,
            recoverySuggestion: recoverySuggestion)
    }
}
