#if DEBUG
    import AppKit
    import Darwin
    import Foundation

    @MainActor
    public enum DebugLifecycleHarness {
        public static var isRequested: Bool {
            ProcessInfo.processInfo.environment["GLANCE_UI_SMOKE"] == "1"
        }

        private static var fixtureRoot: URL?

        public static func fixtureDirectory() throws -> URL {
            if let fixtureRoot { return fixtureRoot }
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("glance-smoke-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            fixtureRoot = directory
            return directory
        }

        public static func clockSettingsURL() throws -> URL {
            let url = try fixtureDirectory().appendingPathComponent("clocks.json")
            try Data("[]".utf8).write(to: url, options: .atomic)
            return url
        }

        public static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else { throw SmokeError(message: message) }
        }

        public static func value<T>(_ value: T?, _ message: String) throws -> T {
            guard let value else { throw SmokeError(message: message) }
            return value
        }

        public static func note(_ message: String) {
            FileHandle.standardOutput.write(Data("GLANCE_UI_SMOKE_STEP \(message)\n".utf8))
        }

        public static func waitUntil(
            timeout: Duration = .seconds(5),
            condition: @escaping @MainActor () -> Bool
        ) async throws {
            let deadline = ContinuousClock.now + timeout
            while !condition() {
                guard ContinuousClock.now < deadline else {
                    throw SmokeError(message: "Timed out waiting for a lifecycle condition")
                }
                try await Task.sleep(for: .milliseconds(25))
            }
        }

        public static func track(
            _ menu: NSMenu,
            relativeTo view: NSView,
            ready: @escaping @MainActor () -> Bool
        ) async throws {
            let result = TrackingResult(menu: menu, view: view)
            let started = ContinuousClock.now
            let deadline = ContinuousClock.now + .seconds(5)
            let timer = Timer(timeInterval: 0.02, repeats: true) { _ in
                MainActor.assumeIsolated {
                    if ready() {
                        result.passed = true
                        result.finished = true
                        result.menu.cancelTracking()
                    } else if ContinuousClock.now >= deadline {
                        result.finished = true
                        result.menu.cancelTracking()
                    }
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            defer { timer.invalidate() }
            // Native menu tracking must not block the caller's MainActor task on the stack.
            RunLoop.main.perform(inModes: [.default]) {
                MainActor.assumeIsolated { result.openMenu() }
            }
            try await waitUntil(timeout: .seconds(6)) { result.finished }
            note("Menu tracking completed after \(started.duration(to: .now)); items \(menu.items.count)")
            try require(result.passed, "Native menu did not reach its expected rendered state")
        }

        public static func run(_ body: @escaping @MainActor () async throws -> Void) {
            Task { @MainActor in
                do {
                    try await body()
                    finish(error: nil)
                } catch {
                    finish(error: error)
                }
            }
        }

        public static func fail(_ error: any Error) -> Never {
            finish(error: error)
        }

        private static func finish(error: (any Error)?) -> Never {
            var failure = error
            if let fixtureRoot {
                do { try FileManager.default.removeItem(at: fixtureRoot) } catch {
                    failure = error
                }
                self.fixtureRoot = nil
            }
            let result = failure.map { "GLANCE_UI_SMOKE_FAILURE: \($0.localizedDescription)" }
                ?? "GLANCE_UI_SMOKE_SUCCESS"
            FileHandle.standardOutput.write(Data("\(result)\n".utf8))
            Darwin.exit(failure == nil ? EXIT_SUCCESS : EXIT_FAILURE)
        }

        @MainActor
        private final class TrackingResult {
            let menu: NSMenu
            let view: NSView
            var passed = false
            var finished = false
            init(menu: NSMenu, view: NSView) {
                self.menu = menu
                self.view = view
            }
            func openMenu() {
                _ = menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: view)
            }
        }

        private struct SmokeError: LocalizedError {
            let message: String
            var errorDescription: String? { message }
        }
    }
#endif
