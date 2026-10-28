import Foundation

struct PackagingTestError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

func require(_ condition: Bool, _ message: String) throws {
    guard condition else { throw PackagingTestError(message: message) }
}

func runReplacement(source: URL, destination: URL, shouldSucceed: Bool) throws {
    let helper = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().appendingPathComponent("replace-app.swift")
    let process = Process()
    let errors = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["swift", "-swift-version", "6", helper.path, source.path, destination.path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = errors
    try process.run()
    let errorData = try errors.fileHandleForReading.readToEnd() ?? Data()
    process.waitUntilExit()
    try require(
        (process.terminationStatus == 0) == shouldSucceed,
        "Unexpected replacement status: \(String(decoding: errorData, as: UTF8.self))"
    )
}

let manager = FileManager.default
let root = manager.temporaryDirectory.appendingPathComponent("glance-packaging-\(UUID().uuidString)")
try manager.createDirectory(at: root, withIntermediateDirectories: false)
defer {
    do { try manager.removeItem(at: root) } catch {
        FileHandle.standardError.write(Data("Packaging fixture cleanup failed: \(error)\n".utf8))
    }
}
let destination = root.appendingPathComponent("Test.app")
let firstStage = root.appendingPathComponent("first/Test.app")
try manager.createDirectory(at: firstStage, withIntermediateDirectories: true)
try Data("first".utf8).write(to: firstStage.appendingPathComponent("current"))
try runReplacement(source: firstStage, destination: destination, shouldSucceed: true)
try require(manager.fileExists(atPath: destination.appendingPathComponent("current").path), "Fresh install failed")
try Data("stale".utf8).write(to: destination.appendingPathComponent("obsolete-resource"))
try Data("old executable".utf8).write(to: destination.appendingPathComponent("obsolete-executable"))
let secondStage = root.appendingPathComponent("second/Test.app")
try manager.createDirectory(at: secondStage, withIntermediateDirectories: true)
try Data("second".utf8).write(to: secondStage.appendingPathComponent("current"))
try runReplacement(source: secondStage, destination: destination, shouldSucceed: true)
try require(!manager.fileExists(atPath: destination.appendingPathComponent("obsolete-resource").path), "Stale resource survived")
try require(!manager.fileExists(atPath: destination.appendingPathComponent("obsolete-executable").path), "Stale executable survived")
try require(try Data(contentsOf: destination.appendingPathComponent("current")) == Data("second".utf8), "New payload missing")
try runReplacement(source: secondStage, destination: destination, shouldSucceed: false)
try require(try Data(contentsOf: destination.appendingPathComponent("current")) == Data("second".utf8), "Failed replacement changed the existing app")
let linkedStage = root.appendingPathComponent("linked")
try manager.createDirectory(at: linkedStage, withIntermediateDirectories: false)
let linkedApp = linkedStage.appendingPathComponent("Test.app")
try manager.createSymbolicLink(at: linkedApp, withDestinationURL: destination)
try runReplacement(source: linkedApp, destination: destination, shouldSucceed: false)
try require(try Data(contentsOf: destination.appendingPathComponent("current")) == Data("second".utf8), "Symlink rejection changed the existing app")
print("Packaging checks passed: fresh install, stale removal, failed replacement preservation, symlink rejection.")
