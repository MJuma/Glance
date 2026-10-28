import Foundation
import Testing
@testable import GlanceSupport

@Test func commandOutputIsReadAsynchronously() async throws {
    #expect(try await runCommand("/bin/echo", ["hello"]) == "hello")
}

@Test func failedCommandDoesNotReturnSuccessShapedOutput() async {
    do {
        _ = try await runCommand("/usr/bin/false", [])
        Issue.record("Expected a failed command to throw")
    } catch CommandError.failed(_, let status) {
        #expect(status != 0)
    } catch {
        Issue.record(error)
    }
}

@Test func missingExecutableIsReported() async {
    do {
        _ = try await runCommand("/nonexistent/glance-command", [])
        Issue.record("Expected a missing executable to throw")
    } catch {
        #expect(!(error is CancellationError))
    }
}

@Test func largeCommandOutputDoesNotFillPipeAndDeadlock() async throws {
    let output = try await runCommand("/usr/bin/jot", ["20000"])
    #expect(output.split(separator: "\n").count == 20_000)
}

@Test func commandCancellationStopsRunningChild() async throws {
    let start = ContinuousClock.now
    let task = Task { try await runCommand("/bin/sleep", ["10"]) }
    try await Task.sleep(for: .milliseconds(100))
    task.cancel()
    do {
        _ = try await task.value
        Issue.record("Expected cancellation")
    } catch is CancellationError {
        #expect(start.duration(to: .now) < .seconds(3))
    }
}

@Test func alreadyCancelledCommandDoesNotLaunch() async {
    let task = Task { try await runCommand("/bin/sleep", ["10"]) }
    task.cancel()
    do {
        _ = try await task.value
        Issue.record("Expected cancellation")
    } catch is CancellationError {
    } catch {
        Issue.record(error)
    }

}

@Test @MainActor func waitingForACommandDoesNotBlockTheMainActor() async throws {
    let start = ContinuousClock.now
    let task = Task { try await runCommand("/bin/sleep", ["10"]) }
    try await Task.sleep(for: .milliseconds(50))
    #expect(start.duration(to: .now) < .seconds(2))
    task.cancel()
    do { _ = try await task.value } catch is CancellationError {}
}
