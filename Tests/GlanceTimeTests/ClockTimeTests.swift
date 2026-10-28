import AppKit
import Testing
@testable import GlanceTime

private struct ScrubCase: Sendable {
    let reference: String
    let minute: Int
    let expected: String
    let timezone: String
}

@Test(arguments: [
    ScrubCase(reference: "2026-03-08T16:00:00Z", minute: 90, expected: "2026-03-08T06:30:00Z", timezone: "America/New_York"),
    ScrubCase(reference: "2026-03-08T16:00:00Z", minute: 150, expected: "2026-03-08T07:30:00Z", timezone: "America/New_York"),
    ScrubCase(reference: "2026-11-01T17:00:00Z", minute: 0, expected: "2026-11-01T04:00:00Z", timezone: "America/New_York"),
    ScrubCase(reference: "2026-11-01T17:00:00Z", minute: 90, expected: "2026-11-01T05:30:00Z", timezone: "America/New_York"),
    ScrubCase(reference: "2026-11-01T17:00:00Z", minute: 900, expected: "2026-11-01T20:00:00Z", timezone: "America/New_York"),
    ScrubCase(reference: "2026-10-04T02:00:00Z", minute: 135, expected: "2026-10-03T15:45:00Z", timezone: "Australia/Lord_Howe")
])
private func selectedCivilTimesRespectDST(_ value: ScrubCase) throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: value.timezone))
    let reference = try Date(value.reference, strategy: .iso8601)
    let expected = try Date(value.expected, strategy: .iso8601)
    #expect(ClockTime.date(forLocalMinute: value.minute, relativeTo: reference, calendar: calendar) == expected)
    #expect(ClockTime.date(forLocalMinute: nil, relativeTo: reference, calendar: calendar) == reference)
}

@Test @MainActor func scrubberAndClockRowsUseTheSameResolvedInstant() throws {
    let fixture = try ClockSettingsFixture()
    defer { fixture.remove() }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
    let reference = try Date("2026-03-08T16:00:00Z", strategy: .iso8601)
    let selected = ClockTime.date(forLocalMinute: 150, relativeTo: reference, calendar: calendar)
    let clock = try ClockEntry(label: "New York", timezoneID: "America/New_York", countryCode: "US")
    let model = WorldClockMonitor(configURL: fixture.configURL)
    #expect(model.timeString(for: clock, at: selected) == "3:30 AM")
    #expect(model.hour(for: clock, at: selected) == 3)
    let scrubber = TimeScrubber(frame: NSRect(x: 0, y: 0, width: 300, height: 38))
    scrubber.calendar = calendar
    scrubber.referenceDate = reference
    scrubber.minuteOfDay = 150
    let labels = scrubber.subviews.compactMap { ($0 as? NSTextField)?.stringValue }
    #expect(labels.contains("3:30 AM"))
}

@Test(arguments: [
    Calendar.Identifier.gregorian, .buddhist, .chinese, .hebrew, .japanese, .islamicUmmAlQura
])
func civilSelectionSupportsUserCalendars(identifier: Calendar.Identifier) throws {
    var calendar = Calendar(identifier: identifier)
    calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
    let reference = try Date("2026-03-08T16:00:00Z", strategy: .iso8601)
    let expected = try Date("2026-03-08T07:30:00Z", strategy: .iso8601)
    #expect(ClockTime.date(forLocalMinute: 150, relativeTo: reference, calendar: calendar) == expected)
}

@Test(arguments: [
    (19_800, "+05:30"), (20_700, "+05:45"), (-12_600, "-03:30"),
    (-1_800, "-00:30"), (0, "+00:00"), (36_000, "+10:00")
])
func utcOffsetIncludesMinutes(seconds: Int, expected: String) {
    #expect(ClockTime.utcOffset(seconds: seconds) == expected)
}

@Test @MainActor func invalidSavedTimezoneIsReportedAndPreserved() throws {
    let fixture = try ClockSettingsFixture()
    defer { fixture.remove() }
    let original = Data("""
    [{"label":"Foreign clock","timezoneID":"Not/A_Timezone","countryCode":"XX"}]
    """.utf8)
    try original.write(to: fixture.configURL)
    let model = WorldClockMonitor(configURL: fixture.configURL)
    #expect(model.clocks.isEmpty)
    #expect(model.persistenceError?.contains("Not/A_Timezone") == true)
    model.addClock(label: "Berlin", timezoneID: "Europe/Berlin")
    #expect(try Data(contentsOf: fixture.configURL) == original)
    #expect(model.persistenceError != nil)
}

@Test @MainActor func invalidNewTimezoneCannotBecomeALocalClock() throws {
    let fixture = try ClockSettingsFixture()
    defer { fixture.remove() }
    try Data("[]".utf8).write(to: fixture.configURL)
    let model = WorldClockMonitor(configURL: fixture.configURL)
    model.addClock(label: "Foreign clock", timezoneID: "Not/A_Timezone")
    #expect(model.clocks.isEmpty)
    #expect(model.persistenceError != nil)
    #expect(throws: ClockSettingsError.self) {
        try ClockEntry(label: "Invalid", timezoneID: "Not/A_Timezone", countryCode: "XX")
    }
}
