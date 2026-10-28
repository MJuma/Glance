import Foundation
import Testing
@testable import GlanceMonitor

@Test @MainActor func historicalPressureIsCapturedByValue() {
    let monitor = MemoryMonitor()
    let time = Date(timeIntervalSince1970: 1_000)
    var snapshot = MemorySnapshot(activeGB: 8, totalGB: 16, pressure: .normal)
    monitor.record(snapshot, at: time)
    snapshot.pressure = .critical
    snapshot.activeGB = 12
    monitor.record(snapshot, at: time.addingTimeInterval(10))
    #expect(monitor.history[0].snapshot.pressure == .normal)
    #expect(monitor.history[0].snapshot.usedGB == 8)
    #expect(monitor.history[1].snapshot.pressure == .critical)
}

@Test @MainActor func historyRetainsTenMinutes() {
    let monitor = MemoryMonitor()
    let time = Date(timeIntervalSince1970: 1_000)
    for index in 0...120 {
        monitor.record(
            MemorySnapshot(totalGB: 16),
            at: time.addingTimeInterval(Double(index * 10))
        )
    }
    #expect(monitor.history.count == 61)
    #expect(monitor.history.first?.timestamp == time.addingTimeInterval(600))
    #expect(monitor.history.last?.timestamp == time.addingTimeInterval(1_200))
}

@Test @MainActor func rapidManualRefreshesCannotGrowHistoryIndefinitely() {
    let monitor = MemoryMonitor()
    let time = Date(timeIntervalSince1970: 1_000)
    for index in 0..<1_000 {
        monitor.record(
            MemorySnapshot(),
            at: time.addingTimeInterval(Double(index) / 100)
        )
    }
    #expect(monitor.history.count == 121)
}

@Test func usedMemoryIncludesActiveWiredAndCompressed() {
    let snapshot = MemorySnapshot(activeGB: 5, wiredGB: 2, compressedGB: 1)
    #expect(snapshot.usedGB == 8)
}
