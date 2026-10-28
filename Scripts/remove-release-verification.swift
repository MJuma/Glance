import Foundation

guard CommandLine.arguments.count == 2 else {
    fatalError("Expected the generated verification directory")
}
let directory = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
let info = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
guard directory.lastPathComponent.hasPrefix(".verify."),
      directory.deletingLastPathComponent().lastPathComponent.hasPrefix(".release."),
      info.isDirectory == true, info.isSymbolicLink != true else {
    fatalError("Refusing to remove a directory outside the generated release staging area")
}
try FileManager.default.removeItem(at: directory)
