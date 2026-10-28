import Foundation
import Observation
import Synchronization
import Testing
@testable import GlanceTime

private struct ClockSettingsFixture {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("glance-clocks-\(UUID().uuidString)")
    var configURL: URL { directory.appendingPathComponent("clocks.json") }

    init() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func remove() {
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            Issue.record(error)
        }
    }
}

@Test func clockFormattingPreservesTwelveHourText() throws {
    let utc = try #require(TimeZone(secondsFromGMT: 0))
    #expect(clockTimeString(for: Date(timeIntervalSince1970: 0), in: utc) == "12:00 AM")
    #expect(clockTimeString(for: Date(timeIntervalSince1970: 43_200), in: utc) == "12:00 PM")
    #expect(clockTimeString(for: Date(timeIntervalSince1970: 46_800), in: utc) == "1:00 PM")
}

@Test @MainActor func missingConfigurationCreatesDefaults() throws {
    let fixture = try ClockSettingsFixture()
    defer { fixture.remove() }
    let monitor = WorldClockMonitor(configURL: fixture.configURL)
    #expect(monitor.clocks.count == 2)
    #expect(monitor.persistenceError == nil)
    #expect(FileManager.default.fileExists(atPath: fixture.configURL.path))
}

@Test @MainActor func emptyConfigurationStaysEmpty() throws {
    let fixture = try ClockSettingsFixture()
    defer { fixture.remove() }
    try Data("[]".utf8).write(to: fixture.configURL)
    let monitor = WorldClockMonitor(configURL: fixture.configURL)
    #expect(monitor.clocks.isEmpty)
    #expect(monitor.persistenceError == nil)
}

@Test @MainActor func oldConfigurationLoadsAndIdentitySurvivesReordering() throws {
    let fixture = try ClockSettingsFixture()
    defer { fixture.remove() }
    let original = """
    [{"label":"First","timezoneID":"Europe/Berlin","countryCode":"DE"},
     {"label":"Second","timezoneID":"Europe/Berlin","countryCode":"DE"}]
    """
    try Data(original.utf8).write(to: fixture.configURL)
    let monitor = WorldClockMonitor(configURL: fixture.configURL)
    let ids = monitor.clocks.map(\.id)
    #expect(ids[0] != ids[1])
    monitor.moveClock(from: 0, to: 2)
    #expect(monitor.clocks.map(\.id) == Array(ids.reversed()))
    #expect(monitor.clocks.map(\.label) == ["Second", "First"])
    let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.configURL))
    let entries = try #require(saved as? [[String: String]])
    #expect(entries.allSatisfy { Set($0.keys) == ["label", "timezoneID", "countryCode"] })
}

@Test @MainActor func clockMutationsAreObservedAndSaved() throws {
    let fixture = try ClockSettingsFixture()
    defer { fixture.remove() }
    try Data("[]".utf8).write(to: fixture.configURL)
    let monitor = WorldClockMonitor(configURL: fixture.configURL)
    let changed = Mutex(false)
    withObservationTracking {
        _ = monitor.clocks.count
    } onChange: {
        changed.withLock { $0 = true }
    }
    monitor.addClock(label: "Berlin", timezoneID: "Europe/Berlin")
    #expect(changed.withLock { $0 })
    #expect(monitor.clocks.count == 1)
    let reloaded = WorldClockMonitor(configURL: fixture.configURL)
    #expect(reloaded.clocks.map(\.timezoneID) == ["Europe/Berlin"])
    monitor.removeClock(at: 0)
    #expect(WorldClockMonitor(configURL: fixture.configURL).clocks.isEmpty)
}

@Test @MainActor func corruptConfigurationIsReportedAndNeverOverwritten() throws {
    let fixture = try ClockSettingsFixture()
    defer { fixture.remove() }
    let corrupt = Data("not json".utf8)
    try corrupt.write(to: fixture.configURL)
    let monitor = WorldClockMonitor(configURL: fixture.configURL)
    #expect(monitor.persistenceError != nil)
    monitor.addClock(label: "Berlin", timezoneID: "Europe/Berlin")
    #expect(monitor.persistenceError != nil)
    #expect(try Data(contentsOf: fixture.configURL) == corrupt)
}

@Test @MainActor func saveFailureIsReported() throws {
    let fixture = try ClockSettingsFixture()
    defer { fixture.remove() }
    try Data("[]".utf8).write(to: fixture.configURL)
    let monitor = WorldClockMonitor(configURL: fixture.configURL)
    try FileManager.default.removeItem(at: fixture.configURL)
    try FileManager.default.createDirectory(at: fixture.configURL, withIntermediateDirectories: false)
    monitor.addClock(label: "Berlin", timezoneID: "Europe/Berlin")
    #expect(monitor.persistenceError != nil)
}
