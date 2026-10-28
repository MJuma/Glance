import AppKit
import Testing
@testable import GlanceMonitor

private let thermalTestStart = Date(timeIntervalSince1970: 1_000)

private func thermalEntry(
    seconds: Double,
    temperature: Double = 60,
    pressure: ThermalPressure = .nominal,
    fan: Double? = nil
) -> ThermalHistoryEntry {
    ThermalHistoryEntry(
        pressure: pressure,
        cpuMax: temperature,
        fanPercent: fan,
        timestamp: thermalTestStart.addingTimeInterval(seconds)
    )
}

@Test func emptyThermalGraphHasUsableScale() {
    let data = ThermalGraphData(history: [], showFanSpeed: true, now: thermalTestStart)
    #expect(data.temperatureRange == 30...100)
    #expect(data.duration == 1)
    #expect(data.nearestIndex(to: 0.5) == nil)
    #expect(!data.hasFanData)
}

@Test(arguments: [0.0, 60.0, 110.0, 150.0, Double.nan])
func thermalGraphScaleNeverCollapses(temperature: Double) {
    let data = ThermalGraphData(
        history: [thermalEntry(seconds: 0, temperature: temperature)],
        showFanSpeed: false,
        now: thermalTestStart
    )
    #expect(data.temperatureRange.lowerBound.isFinite)
    #expect(data.temperatureRange.upperBound.isFinite)
    #expect(data.temperatureRange.upperBound > data.temperatureRange.lowerBound)
}

@Test func thermalDownsamplingIsBoundedAndKeepsEndpoints() {
    let history = (0..<1_000).map { thermalEntry(seconds: Double($0)) }
    let data = ThermalGraphData(
        history: history,
        showFanSpeed: false,
        now: thermalTestStart.addingTimeInterval(1_000)
    )
    #expect(data.samples.count == 300)
    #expect(data.samples.first?.timestamp == history.first?.timestamp)
    #expect(data.samples.last?.timestamp == history.last?.timestamp)
}

@Test func thermalHoverUsesSampleTimestamps() {
    let data = ThermalGraphData(
        history: [thermalEntry(seconds: 0), thermalEntry(seconds: 10), thermalEntry(seconds: 90)],
        showFanSpeed: false,
        now: thermalTestStart.addingTimeInterval(100)
    )
    #expect(data.nearestIndex(to: 0.11) == 1)
    #expect(data.nearestIndex(to: 1) == 2)
    #expect(data.nearestIndex(to: -1) == 0)
    #expect(data.fraction(at: thermalTestStart.addingTimeInterval(90)) == 0.9)
}

@Test func thermalFanLineRequiresEnabledFiniteReadings() {
    let now = thermalTestStart.addingTimeInterval(10)
    let history = [thermalEntry(seconds: 0, fan: 0), thermalEntry(seconds: 10, fan: 50)]
    #expect(ThermalGraphData(history: history, showFanSpeed: true, now: now).hasFanData)
    #expect(!ThermalGraphData(history: history, showFanSpeed: false, now: now).hasFanData)
    #expect(!ThermalGraphData(
        history: [thermalEntry(seconds: 0, fan: .nan)],
        showFanSpeed: true,
        now: now
    ).hasFanData)
}

@Test @MainActor func nativeThermalGraphRetainsDetailsAndKeyboardSelection() throws {
    let view = ThermalGraphView(
        history: [
            thermalEntry(seconds: 0, temperature: 60, fan: 25),
            thermalEntry(seconds: 10, temperature: 80, pressure: .heavy, fan: 50)
        ],
        now: thermalTestStart.addingTimeInterval(20)
    )
    #expect(view.frame.size == NSSize(width: 280, height: 120))
    #expect(view.accessibilityValue() as? String == "80° · Heavy · Fan 50% · 10s ago")
    let arrow = try #require(NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "",
        charactersIgnoringModifiers: "",
        isARepeat: false,
        keyCode: 123
    ))
    view.keyDown(with: arrow)
    view.keyDown(with: arrow)
    #expect(view.accessibilityValue() as? String == "60° · Nominal · Fan 25% · 20s ago")
}

@Test @MainActor func thermalBreakdownPreservesDurationsPercentagesAndOrder() {
    let view = ThermalBreakdownView(
        timeInEachState: [(.heavy, 30), (.nominal, 90)],
        totalDuration: 120
    )
    #expect(view.frame.size == NSSize(width: 280, height: 80))
    #expect(view.accessibilityValue() as? String ==
        "Nominal: 1m 30s (75%), Moderate: 0s (0%), Heavy: 30s (25%), Critical: 0s (0%)")
    #expect(ThermalBreakdownView.formatDuration(3_661) == "1h 1m")
}

@Test @MainActor func nativeThermalViewsReleaseWithoutHostingInfrastructure() {
    weak var graph: ThermalGraphView?
    weak var breakdown: ThermalBreakdownView?
    autoreleasepool {
        let graphView = ThermalGraphView(history: [])
        let breakdownView = ThermalBreakdownView(timeInEachState: [], totalDuration: 0)
        graph = graphView
        breakdown = breakdownView
    }
    #expect(graph == nil)
    #expect(breakdown == nil)
}

@Test(arguments: [false, true])
@MainActor
func nativeThermalRenderingPreservesPressureBands(showFan: Bool) throws {
    let view = ThermalGraphView(
        history: [
            thermalEntry(seconds: 0, temperature: 60, fan: 25),
            thermalEntry(seconds: 10, temperature: 80, pressure: .critical, fan: 75)
        ],
        showFanSpeed: showFan,
        now: thermalTestStart.addingTimeInterval(20)
    )
    let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    let scale = Double(bitmap.pixelsWide) / view.bounds.width
    let left = try #require(bitmap.colorAt(x: Int(30 * scale), y: Int(60 * scale))?.usingColorSpace(.deviceRGB))
    let right = try #require(bitmap.colorAt(x: Int(230 * scale), y: Int(60 * scale))?.usingColorSpace(.deviceRGB))
    #expect(left.greenComponent > left.redComponent)
    #expect(right.redComponent > right.greenComponent)
}
