import Foundation
import GlanceSupport

enum ProcessListKind: Sendable {
    case memory, cpu

    func load() async throws -> [String] {
        let arguments = self == .memory ? ["-eo", "rss,comm", "-m"] : ["-eo", "%cpu,comm", "-r"]
        return try Self.parse(try await runCommand("/bin/ps", arguments), kind: self)
    }

    static func parse(_ output: String, kind: ProcessListKind) throws -> [String] {
        var results: [String] = []
        for line in output.split(separator: "\n").dropFirst() {
            let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard parts.count == 2, let value = Double(parts[0]), value.isFinite else { continue }
            let command = String(parts[1])
            let name: String
            if let range = command.range(of: #"[^/]+\.app"#, options: .regularExpression) {
                name = String(command[range].dropLast(4))
            } else {
                name = String(command.split(separator: "/").last ?? parts[1])
            }
            results.append(kind == .memory
                ? ProcessMenuLabel.memory(name: name, megabytes: value / 1024)
                : ProcessMenuLabel.cpu(name: name, percent: value))
            if results.count == 5 { break }
        }
        guard !results.isEmpty else {
            throw TelemetryIssue(message: "The process list could not be decoded.")
        }
        return results
    }
}
