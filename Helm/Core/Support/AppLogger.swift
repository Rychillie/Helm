import Foundation
import OSLog

enum AppLogger {
    static let subsystem = Bundle.main.bundleIdentifier ?? "net.rychillie.Helm"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let connection = Logger(subsystem: subsystem, category: "connection")
    static let chat = Logger(subsystem: subsystem, category: "chat")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let gateway = Logger(subsystem: subsystem, category: "gateway")
}
