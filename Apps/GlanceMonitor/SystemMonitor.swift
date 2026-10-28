import AppKit
import Darwin

enum MonitorSampling {
    static let interval: TimeInterval = 10
    static let maximumGap: TimeInterval = 30
}

@MainActor
func makeMonitorPollingTimer(
    interval: TimeInterval = MonitorSampling.interval,
    poll: @escaping @MainActor @Sendable () -> Void
) -> Timer {
    let timer = Timer(timeInterval: interval, repeats: true) { _ in
        MainActor.assumeIsolated { poll() }
    }
    timer.tolerance = interval / 10
    RunLoop.main.add(timer, forMode: .common)
    return timer
}

struct MemorySnapshot: Sendable {
    var usedPercent: Int = 0
    var activeGB: Double = 0
    var wiredGB: Double = 0
    var compressedGB: Double = 0
    var inactiveGB: Double = 0
    var availableGB: Double = 0
    var swapUsedMB: Int = 0
    var totalGB: Int = 0
    var freePercent: Int = 100

    enum Pressure: Sendable {
        case normal, elevated, critical, unknown

        var displayName: String {
            switch self {
            case .normal: "Normal"
            case .elevated: "Elevated"
            case .critical: "Critical"
            case .unknown: "Unknown"
            }
        }

        var color: NSColor {
            switch self {
            case .normal: .systemGreen
            case .elevated: .systemOrange
            case .critical: .systemRed
            case .unknown: .systemGray
            }
        }
    }

    var pressure: Pressure = .unknown
    var pressureIssue: String?
    var usedGB: Double { activeGB + wiredGB + compressedGB }

    static func read() throws -> MemorySnapshot {
        var totalRAM: UInt64 = 0
        try readSystemValue("hw.memsize", into: &totalRAM)
        guard totalRAM > 0 else { throw TelemetryIssue(message: "macOS reported no physical memory.") }
        var vmInfo = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = withUnsafeMutablePointer(to: &vmInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            throw TelemetryIssue(message: "Memory statistics are unavailable (\(result)).")
        }
        var pageSize: vm_size_t = 0
        let pageResult = host_page_size(host, &pageSize)
        guard pageResult == KERN_SUCCESS, pageSize > 0 else {
            throw TelemetryIssue(message: "Memory page size is unavailable (\(pageResult)).")
        }
        var swap = xsw_usage()
        try readSystemValue("vm.swapusage", into: &swap)
        let bytesPerPage = UInt64(pageSize)
        let active = UInt64(vmInfo.active_count) * bytesPerPage
        let wired = UInt64(vmInfo.wire_count) * bytesPerPage
        let compressed = UInt64(vmInfo.compressor_page_count) * bytesPerPage
        let inactive = UInt64(vmInfo.inactive_count) * bytesPerPage
        let usedPercent = Int((active + wired + compressed) * 100 / totalRAM)
        let pressure: Pressure
        let pressureIssue: String?
        do {
            pressure = try MemoryPressureCompatibility.read()
            pressureIssue = nil
        } catch {
            pressure = .unknown
            pressureIssue = error.localizedDescription
        }
        let gb = 1_073_741_824.0
        return MemorySnapshot(
            usedPercent: usedPercent,
            activeGB: Double(active) / gb,
            wiredGB: Double(wired) / gb,
            compressedGB: Double(compressed) / gb,
            inactiveGB: Double(inactive) / gb,
            availableGB: Double(availableBytes(in: vmInfo, pageSize: bytesPerPage)) / gb,
            swapUsedMB: Int(swap.xsu_used / 1_048_576),
            totalGB: Int(totalRAM / 1_073_741_824),
            freePercent: max(0, 100 - usedPercent),
            pressure: pressure,
            pressureIssue: pressureIssue
        )
    }

    static func availableBytes(in statistics: vm_statistics64, pageSize: UInt64) -> UInt64 {
        // Free already includes speculative pages; purgeable pages can overlap other counters.
        (UInt64(statistics.free_count) + UInt64(statistics.inactive_count)) * pageSize
    }
}

func formatTemperature(_ value: Double?) -> String {
    guard let value else { return "Unavailable" }
    return String(format: "%.1f°C", value)
}

struct MemoryHistoryEntry: Sendable {
    let timestamp: Date
    let snapshot: MemorySnapshot
}

@MainActor
final class MemoryMonitor {
    private(set) var snapshot: MemorySnapshot?
    private(set) var issue: String?
    private(set) var history: [MemoryHistoryEntry] = []
    private var diagnostics = TelemetryDiagnostics()
    private let readSnapshot: @MainActor () throws -> MemorySnapshot
    static let historyDuration: TimeInterval = 600

    init(readSnapshot: @escaping @MainActor () throws -> MemorySnapshot = MemorySnapshot.read) {
        self.readSnapshot = readSnapshot
    }

    func poll() {
        do {
            let value = try readSnapshot()
            snapshot = value
            issue = value.pressureIssue
            record(value, at: Date())
        } catch {
            snapshot = nil
            issue = error.localizedDescription
        }
        diagnostics.report(issue)
    }

    func record(_ snapshot: MemorySnapshot, at timestamp: Date) {
        history.append(MemoryHistoryEntry(timestamp: timestamp, snapshot: snapshot))
        let cutoff = timestamp.addingTimeInterval(-Self.historyDuration)
        history.removeAll { $0.timestamp < cutoff }
        if history.count > 121 { history.removeFirst(history.count - 121) }
    }
}

enum ThermalPressure: String, Sendable {
    case nominal, moderate, heavy, critical, unknown

    var displayName: String { rawValue.capitalized }
    var isThrottling: Bool { self == .heavy || self == .critical }
    var color: NSColor {
        switch self {
        case .nominal: .systemGreen
        case .moderate: .systemYellow
        case .heavy: .systemOrange
        case .critical: .systemRed
        case .unknown: .gray
        }
    }
}

struct ThermalHistoryEntry: Sendable {
    let pressure: ThermalPressure
    let cpuMax: Double?
    let fanPercent: Double?
    let timestamp: Date
}

enum FanState: Sendable {
    case notPresent
    case available(FanSpeed)
    case unavailable(String)
}

struct ThermalSnapshot: Sendable {
    var pressure: ThermalPressure = .unknown
    var cpuMax: Double?
    var cpuAvg: Double?
    var gpuMax: Double?
    var batteryTemp: Double?
    var sensorCount = 0
    var fanState = FanState.unavailable("Fan status is unavailable.")
    var issue: String?

    var stateColor: NSColor { pressure.color }
    var fanRPM: Double? {
        if case let .available(fan) = fanState { fan.rpm } else { nil }
    }
    var fanPercent: Double? {
        if case let .available(fan) = fanState { fan.percentage } else { nil }
    }
    @MainActor
    static func read() -> ThermalSnapshot {
        var snapshot = ThermalSnapshot()
        var issues: [String] = []
        let pressure = ThermalPressureReader.shared.readPressure()
        snapshot.pressure = pressure.pressure
        if let issue = pressure.issue { issues.append(issue) }
        do {
            let temperatures = try SMCReader.shared.readAllTemperatures()
            let cpu = temperatures.filter { reading in
                ["Tp", "Tf", "Te", "TC"].contains { prefix in reading.key.hasPrefix(prefix) }
            }.map(\.value)
            snapshot.cpuMax = cpu.max()
            snapshot.cpuAvg = cpu.isEmpty ? nil : cpu.reduce(0, +) / Double(cpu.count)
            snapshot.gpuMax = temperatures.filter { $0.key.hasPrefix("Tg") }.map(\.value).max()
            snapshot.batteryTemp = temperatures.filter { $0.key.hasPrefix("TB") }.map(\.value).max()
            snapshot.sensorCount = temperatures.count
        } catch {
            issues.append(error.localizedDescription)
        }

        do {
            snapshot.fanState = try SMCReader.shared.readFanSpeed().map(FanState.available) ?? .notPresent
        } catch {
            snapshot.fanState = .unavailable(error.localizedDescription)
            if !issues.contains(error.localizedDescription) { issues.append(error.localizedDescription) }
        }
        snapshot.issue = issues.isEmpty ? nil : issues.joined(separator: " ")
        return snapshot
    }
}

@MainActor
final class ThermalMonitor {
    private(set) var snapshot = ThermalSnapshot()
    private(set) var history: [ThermalHistoryEntry] = []
    private var diagnostics = TelemetryDiagnostics()
    private let readSnapshot: @MainActor () -> ThermalSnapshot
    private static let historyDuration: TimeInterval = 600

    init(readSnapshot: @escaping @MainActor () -> ThermalSnapshot = ThermalSnapshot.read) {
        self.readSnapshot = readSnapshot
    }

    func poll() {
        snapshot = readSnapshot()
        diagnostics.report(snapshot.issue)
        let now = Date()
        history.append(ThermalHistoryEntry(
            pressure: snapshot.pressure,
            cpuMax: snapshot.cpuMax,
            fanPercent: snapshot.fanPercent,
            timestamp: now
        ))
        history.removeAll { $0.timestamp < now.addingTimeInterval(-Self.historyDuration) }
        if history.count > 121 { history.removeFirst(history.count - 121) }
    }

    func historySummary(at now: Date = Date()) -> ThermalHistorySummary {
        ThermalHistorySummary(history: history, now: now)
    }
}
