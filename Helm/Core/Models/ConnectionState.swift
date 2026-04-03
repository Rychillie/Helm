import Foundation

enum ConnectionState: Equatable, Sendable {
    case notConfigured
    case disconnected
    case connecting
    case connected
    case disconnecting
    case connectionLost
    case failed(UserFacingError)

    var statusTitle: String {
        switch self {
        case .notConfigured:
            "Not configured"
        case .disconnected:
            "Ready to connect"
        case .connecting:
            "Connecting…"
        case .connected:
            "Connected"
        case .disconnecting:
            "Disconnecting…"
        case .connectionLost:
            "Connection lost"
        case .failed:
            "Unable to connect"
        }
    }

    var systemImage: String {
        switch self {
        case .notConfigured:
            "slider.horizontal.3"
        case .disconnected:
            "bolt.horizontal.circle"
        case .connecting:
            "arrow.trianglehead.2.clockwise.rotate.90"
        case .connected:
            "checkmark.circle.fill"
        case .disconnecting:
            "arrow.trianglehead.2.clockwise.rotate.90"
        case .connectionLost, .failed:
            "exclamationmark.triangle.fill"
        }
    }

    var isBusy: Bool {
        switch self {
        case .connecting, .disconnecting:
            true
        default:
            false
        }
    }

    var allowsSending: Bool {
        self == .connected
    }
}
