import Foundation
import Synchronization

public enum CommandError: Error, LocalizedError {
    case failed(String, Int32)
    case invalidEncoding(String)

    public var errorDescription: String? {
        switch self {
        case let .failed(path, status): "\(path) exited with status \(status)."
        case let .invalidEncoding(path): "\(path) returned invalid UTF-8 output."
        }
    }
}

public func runCommand(_ path: String, _ arguments: [String]) async throws -> String {
    let state = Mutex((cancelled: false, process: Optional<Process>.none))
    return try await withTaskCancellationHandler {
        try Task.checkCancellation()
        return try await Task.detached(priority: .utility) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            defer {
                state.withLock {
                    if process.isRunning { process.terminate() }
                    $0.process = nil
                }
            }
            try state.withLock {
                guard !$0.cancelled else { throw CancellationError() }
                $0.process = process
                try process.run()
            }
            let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
            process.waitUntilExit()
            try state.withLock {
                if $0.cancelled { throw CancellationError() }
            }
            guard process.terminationStatus == 0 else {
                throw CommandError.failed(path, process.terminationStatus)
            }
            guard let output = String(data: data, encoding: .utf8) else {
                throw CommandError.invalidEncoding(path)
            }
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
    } onCancel: {
        state.withLock {
            $0.cancelled = true
            if let process = $0.process, process.isRunning {
                process.terminate()
            }
        }
    }
}
