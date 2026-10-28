import Testing
@testable import GlanceMonitor

@Test func cpuLabelsPreserveIndentationAndColumns() {
    let short = ProcessMenuLabel.cpu(name: "Finder", percent: 2.5)
    let long = ProcessMenuLabel.cpu(name: "Activity Monitor", percent: 52.3)
    #expect(short == "  " + "Finder".padding(toLength: 24, withPad: " ", startingAt: 0) + "   2.5%")
    #expect(short.count == long.count)
}

@Test func memoryLabelsSwitchUnitsAtOneGigabyte() {
    let megabytes = ProcessMenuLabel.memory(name: "Finder", megabytes: 1023)
    let gigabytes = ProcessMenuLabel.memory(name: "Activity Monitor", megabytes: 1024)
    #expect(megabytes.hasPrefix("  Finder"))
    #expect(megabytes.hasSuffix(" 1023 MB"))
    #expect(gigabytes.hasSuffix("  1.0 GB"))
    #expect(megabytes.count == gigabytes.count)
}

@Test func longProcessNamesDoNotShiftTheValueColumn() {
    let label = ProcessMenuLabel.cpu(
        name: "A process name longer than the column",
        percent: 1
    )
    #expect(label == "  A process name longer th   1.0%")
}
