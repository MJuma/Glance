import AppKit
import Darwin
import Foundation

public enum ApplicationInstanceError: Error, LocalizedError {
    case invalidBundleIdentifier
    case invalidLockFile
    case systemCall(String, Int32)

    public var errorDescription: String? {
        switch self {
        case .invalidBundleIdentifier:
            "The application bundle identifier is missing or invalid. Launch the packaged app."
        case .invalidLockFile:
            "The application instance lock is not a regular file."
        case let .systemCall(operation, code):
            "Application instance \(operation) failed (errno \(code))."
        }
    }
}

public final class ApplicationInstanceLock: Sendable {
    private let descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    deinit {
        if flock(descriptor, LOCK_UN) != 0 {
            AppLog.lifecycle.error("Could not unlock application instance (errno \(errno))")
        }
        if close(descriptor) != 0 {
            AppLog.lifecycle.error("Could not close application instance lock (errno \(errno))")
        }
    }

    public static func acquire(at url: URL) throws -> ApplicationInstanceLock? {
        let descriptor = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, mode_t(0o600))
        guard descriptor >= 0 else { throw ApplicationInstanceError.systemCall("open", errno) }
        var keepDescriptor = false
        defer { if !keepDescriptor { close(descriptor) } }
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0 else {
            throw ApplicationInstanceError.systemCall("stat", errno)
        }
        guard attributes.st_mode & S_IFMT == S_IFREG else { throw ApplicationInstanceError.invalidLockFile }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            if code == EWOULDBLOCK { return nil }
            throw ApplicationInstanceError.systemCall("lock", code)
        }
        keepDescriptor = true
        return ApplicationInstanceLock(descriptor: descriptor)
    }

    @MainActor
    public static func claimApplication(directory: URL? = nil, bundle: Bundle = .main) throws -> ApplicationInstanceLock? {
        guard let identifier = bundle.bundleIdentifier,
              !identifier.isEmpty, identifier.utf8.count <= 200,
              identifier.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty }),
              identifier.utf8.allSatisfy({
                  (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 46
              }) else {
            throw ApplicationInstanceError.invalidBundleIdentifier
        }
        let manager = FileManager.default
        let lockDirectory: URL
        if let directory {
            lockDirectory = directory
        } else {
            lockDirectory = try manager.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            ).appendingPathComponent("Glance/Instances", isDirectory: true)
        }
        try manager.createDirectory(
            at: lockDirectory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let instance = try acquire(at: lockDirectory.appendingPathComponent("\(identifier).lock"))
        if instance == nil {
            AppLog.lifecycle.notice("Another instance of \(identifier, privacy: .public) is already running")
        }
        return instance
    }
}

@MainActor
public func presentStartupFailure(_ error: any Error) {
    AppLog.lifecycle.error("Application startup failed: \(error.localizedDescription)")
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Glance could not start"
    alert.informativeText = error.localizedDescription
    alert.addButton(withTitle: "Quit")
    NSApp.activate()
    alert.runModal()
}

@MainActor
public func claimPrimaryApplicationInstance() -> ApplicationInstanceLock? {
    do {
        #if DEBUG
            let directory = DebugLifecycleHarness.isRequested ? try DebugLifecycleHarness.fixtureDirectory() : nil
            return try ApplicationInstanceLock.claimApplication(directory: directory)
        #else
            return try ApplicationInstanceLock.claimApplication()
        #endif
    } catch {
        #if DEBUG
            if DebugLifecycleHarness.isRequested { DebugLifecycleHarness.fail(error) }
        #endif
        presentStartupFailure(error)
        return nil
    }
}
