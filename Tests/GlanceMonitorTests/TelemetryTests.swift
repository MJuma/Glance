import Foundation
import Synchronization
import Testing
@testable import GlanceMonitor

@Test func smcDecodingChecksTypeAndPayloadLength() {
    #expect(SMCValueDecoder.number(type: SMCValueDecoder.fourCC("flt "), bytes: [0, 0, 0x70, 0x42]) == 60)
    #expect(SMCValueDecoder.number(type: SMCValueDecoder.fourCC("sp78"), bytes: [0x3C, 0x80]) == 60.5)
    #expect(SMCValueDecoder.number(type: SMCValueDecoder.fourCC("fpe2"), bytes: [0x1F, 0x40]) == 2_000)
    #expect(SMCValueDecoder.number(type: SMCValueDecoder.fourCC("ui8 "), bytes: [2]) == 2)
    #expect(SMCValueDecoder.number(type: SMCValueDecoder.fourCC("flt "), bytes: [0, 0]) == nil)
    #expect(SMCValueDecoder.number(type: 0, bytes: [1, 2, 3, 4]) == nil)
    #expect(SMCValueDecoder.number(type: SMCValueDecoder.fourCC("flt "), bytes: [0, 0, 0xC0, 0x7F]) == nil)
}

@Test func unknownThermalLevelsAreNotTreatedAsNominal() {
    #expect(ThermalPressureReader.pressure(for: 0) == .nominal)
    #expect(ThermalPressureReader.pressure(for: 4) == .critical)
    #expect(ThermalPressureReader.pressure(for: 99) == nil)
}

@Test(arguments: [
    "MacBookAir10,1", "Mac14,2", "Mac14,15", "Mac15,12", "Mac15,13",
    "Mac16,12", "Mac16,13", "Mac17,3", "Mac17,4"
])
func appleSiliconMacBookAirModelsAreKnownFanless(model: String) {
    #expect(SMCReader.isKnownFanlessModel(model))
}

@Test(arguments: ["MacBookAir9,1", "MacBookAir8,1", "Mac15,3", "Mac14,3", "Mac18,99", ""])
func otherHardwareIsNotAssumedFanless(model: String) {
    #expect(!SMCReader.isKnownFanlessModel(model))
}

@Test @MainActor func absentFansHaveNoMenuItem() {
    #expect(makeFanMenuItem(for: .notPresent) == nil)
}

@Test @MainActor func fanReadingsAndReadFailuresStillHaveMenuItems() {
    let fan = FanSpeed(rpm: 2_000, percentage: 20)
    #expect(makeFanMenuItem(for: .available(fan))?.title == "Fan: 2000 RPM (20%)")
    #expect(makeFanMenuItem(for: .unavailable("Sensor read failed"))?.title == "Fan: Unavailable")
}

@Test @MainActor func failedMemorySamplingClearsStaleSuccessAndCanRecover() {
    let fail = Mutex(false)
    let monitor = MemoryMonitor {
        if fail.withLock({ $0 }) { throw TelemetryIssue(message: "Test sampling failure") }
        return MemorySnapshot(activeGB: 8, totalGB: 16, pressure: .normal)
    }
    monitor.poll()
    #expect(monitor.snapshot?.usedGB == 8)
    fail.withLock { $0 = true }
    monitor.poll()
    #expect(monitor.snapshot == nil)
    #expect(monitor.issue == "Test sampling failure")
    #expect(monitor.history.count == 1)
    fail.withLock { $0 = false }
    monitor.poll()
    #expect(monitor.snapshot != nil)
    #expect(monitor.issue == nil)
}

@Test @MainActor func unreadablePressureIsUnknownWithVisibleDiagnostic() {
    let monitor = MemoryMonitor {
        MemorySnapshot(totalGB: 16, pressure: .unknown, pressureIssue: "Pressure unavailable")
    }
    monitor.poll()
    #expect(monitor.snapshot?.pressure == .unknown)
    #expect(monitor.issue == "Pressure unavailable")
}

@Test func missingTemperaturesAreNotZeroReadings() {
    #expect(formatTemperature(nil) == "Unavailable")
    #expect(formatTemperature(60) == "60.0°C")
    let snapshot = ThermalSnapshot()
    #expect(snapshot.cpuMax == nil)
    #expect(snapshot.fanRPM == nil)
}

@Test func processListParsingPreservesNamesAndUnits() throws {
    let memory = try ProcessListKind.parse("RSS COMM\n2097152 /Applications/Example App.app/Contents/MacOS/Example\n", kind: .memory)
    #expect(memory == [ProcessMenuLabel.memory(name: "Example App", megabytes: 2_048)])
    let cpu = try ProcessListKind.parse("%CPU COMM\n25.5 /usr/bin/example\n", kind: .cpu)
    #expect(cpu == [ProcessMenuLabel.cpu(name: "example", percent: 25.5)])
    #expect(throws: TelemetryIssue.self) {
        try ProcessListKind.parse("invalid output", kind: .memory)
    }
}

@Test @MainActor func failedThermalReadingsDoNotInventHistoryTemperatures() {
    let monitor = ThermalMonitor { ThermalSnapshot(issue: "Sensors unavailable") }
    monitor.poll()
    #expect(monitor.history.last?.cpuMax == nil)
    #expect(monitor.snapshot.issue == "Sensors unavailable")
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["GLANCE_TEST_HARDWARE"] == "1"))
@MainActor
func localHardwareBridgeDecodesExpectedLiveReadings() throws {
    let memory = try MemorySnapshot.read()
    #expect(memory.totalGB > 0)
    let thermal = ThermalSnapshot.read()
    #expect(thermal.pressure != .unknown)
    #expect(thermal.cpuMax != nil)
    #expect(thermal.gpuMax != nil)
    #expect(thermal.sensorCount > 0)
    if SMCReader.isKnownFanlessModel(try SMCReader.readHardwareModel()) {
        if case .notPresent = thermal.fanState {
            #expect(thermal.fanRPM == nil)
            #expect(thermal.fanPercent == nil)
            #expect(makeFanMenuItem(for: thermal.fanState) == nil)
            #expect(thermal.issue?.localizedCaseInsensitiveContains("fan") != true)
        } else {
            Issue.record("A known fanless Mac reported a fan reading or fan error.")
        }
    } else if case let .unavailable(message) = thermal.fanState {
        #expect(!message.isEmpty)
        #expect(thermal.issue?.contains(message) == true)
    }
}
