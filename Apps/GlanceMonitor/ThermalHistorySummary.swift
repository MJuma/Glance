import Foundation

struct ThermalHistorySummary: Sendable {
    let timeInEachState: [(pressure: ThermalPressure, duration: TimeInterval)]
    let totalDuration: TimeInterval

    init(history: [ThermalHistoryEntry], now: Date) {
        var durations: [ThermalPressure: TimeInterval] = [:]
        for (index, entry) in history.enumerated() {
            let next = index + 1 < history.count ? history[index + 1].timestamp : now
            let end = min(next, now, entry.timestamp.addingTimeInterval(MonitorSampling.maximumGap))
            let observed = max(0, end.timeIntervalSince(entry.timestamp))
            if observed > 0 { durations[entry.pressure, default: 0] += observed }
        }
        totalDuration = durations.values.reduce(0, +)
        timeInEachState = durations.map { (pressure: $0.key, duration: $0.value) }
            .sorted { $0.pressure.rawValue < $1.pressure.rawValue }
    }
}
