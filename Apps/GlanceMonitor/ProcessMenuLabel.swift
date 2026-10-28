import Foundation

enum ProcessMenuLabel {
    static func cpu(name: String, percent: Double) -> String {
        let paddedName = name.padding(toLength: 24, withPad: " ", startingAt: 0)
        return "  \(paddedName) " + String(format: "%5.1f%%", percent)
    }

    static func memory(name: String, megabytes: Double) -> String {
        let paddedName = name.padding(toLength: 22, withPad: " ", startingAt: 0)
        let usage = megabytes >= 1024
            ? String(format: "%5.1f GB", megabytes / 1024)
            : String(format: "%5.0f MB", megabytes)
        return "  \(paddedName) \(usage)"
    }
}
