import Foundation
import Testing
@testable import GlanceSupport

private struct InstanceFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("glance-instance-\(UUID().uuidString)")
    init() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    }
    func remove() {
        do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) }
    }
}

@Test func instanceLockRejectsContentionAndReleasesWithoutDeletingTheFile() throws {
    let fixture = try InstanceFixture()
    defer { fixture.remove() }
    let path = fixture.directory.appendingPathComponent("monitor.lock")
    var first = try ApplicationInstanceLock.acquire(at: path)
    #expect(first != nil)
    #expect(try ApplicationInstanceLock.acquire(at: path) == nil)
    first = nil
    #expect(FileManager.default.fileExists(atPath: path.path))
    let replacement = try ApplicationInstanceLock.acquire(at: path)
    #expect(replacement != nil)
    withExtendedLifetime(replacement) {}
}

@Test func monitorAndTimeCanOwnIndependentInstanceLocks() throws {
    let fixture = try InstanceFixture()
    defer { fixture.remove() }
    let monitor = try ApplicationInstanceLock.acquire(at: fixture.directory.appendingPathComponent("monitor.lock"))
    let time = try ApplicationInstanceLock.acquire(at: fixture.directory.appendingPathComponent("time.lock"))
    #expect(monitor != nil)
    #expect(time != nil)
    withExtendedLifetime((monitor, time)) {}
}

@Test func instanceLockRejectsSymlinks() throws {
    let fixture = try InstanceFixture()
    defer { fixture.remove() }
    let target = fixture.directory.appendingPathComponent("target")
    try Data("unchanged".utf8).write(to: target)
    let link = fixture.directory.appendingPathComponent("link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    #expect(throws: ApplicationInstanceError.self) { try ApplicationInstanceLock.acquire(at: link) }
    #expect(try Data(contentsOf: target) == Data("unchanged".utf8))
}

@Test func buildInfoRequiresExplicitIdentityAndReportsIt() throws {
    let info = try AppBuildInfo(info: [
        "CFBundleShortVersionString": "1.0.0", "CFBundleVersion": "7",
        "GlanceSourceRevision": "abc1234-dirty", "GlanceBuildDate": "2026-10-28T00:00:00Z"
    ])
    #expect(info.diagnosticText.contains("abc1234-dirty"))
    #expect(info.diagnosticText.contains("1.0.0 (7)"))
    #expect(throws: BuildInfoError.self) { try AppBuildInfo(info: [:]) }
}
