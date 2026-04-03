import Foundation

enum GatewayAuthMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case sharedToken
    case password

    var id: String { self.rawValue }

    var title: String {
        switch self {
        case .none:
            "None"
        case .sharedToken:
            "Token"
        case .password:
            "Password"
        }
    }

    var fieldTitle: String? {
        switch self {
        case .none:
            nil
        case .sharedToken:
            "Shared token"
        case .password:
            "Password"
        }
    }
}

struct GatewayConfiguration: Codable, Equatable, Sendable {
    var endpoint: URL
    var displayName: String?
    var timeoutSeconds: Double
    var authMode: GatewayAuthMode

    var title: String {
        let trimmedName = self.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedName, !trimmedName.isEmpty {
            return trimmedName
        }
        return self.endpoint.host ?? self.endpoint.absoluteString
    }

    var endpointLabel: String {
        self.endpoint.absoluteString
    }
}
