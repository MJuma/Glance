import Darwin
import Foundation

struct AppReplacementError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

do {
    guard CommandLine.arguments.count == 3 else {
        throw AppReplacementError(message: "Usage: replace-app.swift <staged.app> <destination.app>")
    }
    let source = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
    let destination = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL
    guard source != destination,
          source.pathExtension == "app", destination.pathExtension == "app",
          source.lastPathComponent == destination.lastPathComponent,
          source.deletingLastPathComponent().deletingLastPathComponent() == destination.deletingLastPathComponent() else {
        throw AppReplacementError(message: "Replacement requires a sibling staging directory and matching .app names.")
    }
    let manager = FileManager.default
    let sourceInfo = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard sourceInfo.isDirectory == true, sourceInfo.isSymbolicLink != true else {
        throw AppReplacementError(message: "The staged app must be a real directory, not a symbolic link.")
    }
    if manager.fileExists(atPath: destination.path) {
        let destinationInfo = try destination.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard destinationInfo.isDirectory == true, destinationInfo.isSymbolicLink != true else {
            throw AppReplacementError(message: "The destination app must be a real directory, not a symbolic link.")
        }
        _ = try manager.replaceItemAt(destination, withItemAt: source, backupItemName: nil, options: .usingNewMetadataOnly)
    } else {
        try manager.moveItem(at: source, to: destination)
    }
} catch {
    FileHandle.standardError.write(Data("App replacement failed: \(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
