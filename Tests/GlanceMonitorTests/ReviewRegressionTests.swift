import AppKit
import CoreFoundation
import Darwin
import Synchronization
import Testing
@testable import GlanceMonitor

@Test(arguments: [UInt64(4_096), UInt64(16_384)])
func availableMemoryDoesNotAddOverlappingPageCounters(pageSize: UInt64) {
    var statistics = vm_statistics64()
    statistics.free_count = 100
    statistics.inactive_count = 50
    statistics.speculative_count = 25
    statistics.purgeable_count = 40
    #expect(MemorySnapshot.availableBytes(in: statistics, pageSize: pageSize) == 150 * pageSize)
    statistics.speculative_count = 75
    statistics.purgeable_count = 100
    #expect(MemorySnapshot.availableBytes(in: statistics, pageSize: pageSize) == 150 * pageSize)
}

@Test @MainActor func pollingContinuesInEventTrackingMode() {
    // AppKit adds this common mode; a standalone test runner need not have done so.
    CFRunLoopAddCommonMode(CFRunLoopGetMain(), CFRunLoopMode(rawValue: RunLoop.Mode.eventTracking.rawValue as CFString))
    let count = Mutex(0)
    let timer = makeMonitorPollingTimer(interval: 0.01) { count.withLock { $0 += 1 } }
    defer { timer.invalidate() }
    let deadline = Date().addingTimeInterval(0.5)
    while count.withLock({ $0 }) < 2, Date() < deadline {
        _ = RunLoop.main.run(mode: .eventTracking, before: deadline)
    }
    #expect(count.withLock { $0 } >= 2)
}

private func sample(_ pressure: ThermalPressure, at seconds: Double) -> ThermalHistoryEntry {
    ThermalHistoryEntry(
        pressure: pressure,
        cpuMax: 60,
        fanPercent: nil,
        timestamp: Date(timeIntervalSince1970: seconds)
    )
}

@Test func thermalBreakdownExcludesUnobservedGapsFromItsDenominator() {
    let summary = ThermalHistorySummary(
        history: [sample(.heavy, at: 0), sample(.nominal, at: 300)],
        now: Date(timeIntervalSince1970: 310)
    )
    #expect(summary.timeInEachState.first { $0.pressure == .heavy }?.duration == 30)
    #expect(summary.timeInEachState.first { $0.pressure == .nominal }?.duration == 10)
    #expect(summary.totalDuration == 40)
}

@Test func thermalBreakdownCapsAnOldLastSample() {
    let summary = ThermalHistorySummary(
        history: [sample(.critical, at: 0)],
        now: Date(timeIntervalSince1970: 300)
    )
    #expect(summary.totalDuration == MonitorSampling.maximumGap)
    let future = ThermalHistorySummary(
        history: [sample(.critical, at: 10)],
        now: Date(timeIntervalSince1970: 0)
    )
    #expect(future.totalDuration == 0)
}

@Test @MainActor func observedUnknownPressureRemainsVisibleInPercentages() {
    let summary = ThermalHistorySummary(
        history: [sample(.unknown, at: 0), sample(.nominal, at: 20)],
        now: Date(timeIntervalSince1970: 30)
    )
    #expect(summary.totalDuration == 30)
    let view = ThermalBreakdownView(timeInEachState: summary.timeInEachState, totalDuration: summary.totalDuration)
    #expect(view.accessibilityValue() as? String ==
        "Nominal: 10s (33%), Moderate: 0s (0%), Heavy: 0s (0%), Critical: 0s (0%), Unknown: 20s (67%)")
    #expect(view.frame.height == 95)
}

@Test(arguments: [-10.0, 0.0, 15.0, 20.0, 60.0])
func validColdTemperatureReadingsAreAccepted(value: Double) {
    #expect(SMCReader.isValidTemperature(value))
    let data = ThermalGraphData(
        history: [ThermalHistoryEntry(pressure: .nominal, cpuMax: value, fanPercent: nil, timestamp: .now)],
        showFanSpeed: false,
        now: .now
    )
    #expect(data.temperatureRange.contains(value))
}

@Test(arguments: [-127.0, 150.0, Double.nan, Double.infinity])
func invalidTemperatureSentinelsAreRejected(value: Double) {
    #expect(!SMCReader.isValidTemperature(value))
}
