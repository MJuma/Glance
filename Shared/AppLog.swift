import Foundation
import OSLog

public enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "glance.unbundled"

    public static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    public static let menus = Logger(subsystem: subsystem, category: "menus")
    public static let preferences = Logger(subsystem: subsystem, category: "preferences")
    public static let telemetry = Logger(subsystem: subsystem, category: "telemetry")
    public static let processes = Logger(subsystem: subsystem, category: "processes")
    public static let graphs = Logger(subsystem: subsystem, category: "graphs")
}
