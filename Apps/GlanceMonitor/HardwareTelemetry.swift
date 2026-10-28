import Darwin
import Foundation
import GlancePlatform
import GlanceSupport
import IOKit

struct TelemetryIssue: Error, LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }
}

func readSystemValue<T: BitwiseCopyable>(_ name: String, into value: inout T) throws {
    var size = MemoryLayout<T>.size
    let result = sysctlbyname(name, &value, &size, nil, 0)
    guard result == 0, size == MemoryLayout<T>.size else {
        throw TelemetryIssue(message: "\(name) is unavailable (status \(result), errno \(errno)).")
    }
}

enum MemoryPressureCompatibility {
    static func read() throws -> MemorySnapshot.Pressure {
        var level: Int32 = 0
        try readSystemValue("vm.memory_pressure", into: &level)
        switch level {
        case 0: return .normal
        case 1: return .elevated
        case 2...: return .critical
        default: throw TelemetryIssue(message: "macOS returned an unrecognized memory pressure level.")
        }
    }
}

@MainActor
struct TelemetryDiagnostics {
    private var lastMessage: String?

    mutating func report(_ message: String?) {
        guard message != lastMessage else { return }
        if let message {
            AppLog.telemetry.error("\(message, privacy: .public)")
        } else {
            AppLog.telemetry.debug("Telemetry recovered")
        }
        lastMessage = message
    }
}

@MainActor
final class ThermalPressureReader {
    static let shared = ThermalPressureReader()
    private var token: Int32 = 0
    private let registrationStatus: UInt32

    private init() {
        registrationStatus = notify_register_check("com.apple.system.thermalpressurelevel", &token)
    }

    deinit {
        if registrationStatus == NOTIFY_STATUS_OK { notify_cancel(token) }
    }

    func readPressure() -> (pressure: ThermalPressure, issue: String?) {
        var state: UInt64 = 0
        if registrationStatus == NOTIFY_STATUS_OK,
           notify_get_state(token, &state) == NOTIFY_STATUS_OK,
           let pressure = Self.pressure(for: state) {
            return (pressure, nil)
        }
        let pressure: ThermalPressure
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: pressure = .nominal
        case .fair: pressure = .moderate
        case .serious: pressure = .heavy
        case .critical: pressure = .critical
        @unknown default: pressure = .unknown
        }
        return (pressure, "Detailed thermal pressure unavailable; using macOS thermal state.")
    }

    nonisolated static func pressure(for value: UInt64) -> ThermalPressure? {
        switch value {
        case 0: .nominal
        case 1: .moderate
        case 2: .heavy
        case 3, 4: .critical
        default: nil
        }
    }
}

enum SMCValueDecoder {
    static func fourCC(_ value: String) -> UInt32 {
        value.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    static func number(type: UInt32, bytes: [UInt8]) -> Double? {
        switch type {
        case fourCC("flt ") where bytes.count >= 4:
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8
                | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            let value = Double(Float(bitPattern: bits))
            return value.isFinite ? value : nil
        case fourCC("fpe2") where bytes.count >= 2:
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case fourCC("sp78") where bytes.count >= 2:
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        case fourCC("ui8 ") where !bytes.isEmpty:
            return Double(bytes[0])
        default:
            return nil
        }
    }
}

struct FanSpeed: Sendable {
    let rpm: Double
    let percentage: Double
}

@MainActor
final class SMCReader {
    static let shared = SMCReader()
    private var connection: io_connect_t = 0
    private var connectionIssue: String?
    private var cachedFanCount: Int?
    private let isKnownFanless: Bool

    private static let temperatureKeys: [String] = {
        var keys: Set<String> = [
            "Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b",
            "Tg05", "Tg0D", "Tg0L", "Tg0T", "Tg04", "Tg0C", "Tg0K", "Tg0S",
            "Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp0f", "Tp0j", "Tg0f", "Tg0j",
            "Te05", "Te0L", "Te0P", "Te0S",
            "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E",
            "Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A",
            "Te09", "Te0H", "Tp0V", "Tp0Y", "Tp0e",
            "Tg0G", "Tg0H", "Tg1U", "Tg1k", "Tg0d", "Tg0e", "Tg0k",
            "TB0T", "TB1T", "TB2T"
        ]
        for group in 1...5 {
            for core in 0...3 { keys.insert("TC\(group)\(core)") }
        }
        return keys.sorted()
    }()

    private init() {
        do {
            isKnownFanless = Self.isKnownFanlessModel(try Self.readHardwareModel())
        } catch {
            isKnownFanless = false
            AppLog.telemetry.error("Fanless model identification unavailable: \(error.localizedDescription, privacy: .public)")
        }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else {
            connectionIssue = "AppleSMC is not available on this Mac."
            return
        }
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)
        if result != KERN_SUCCESS {
            connectionIssue = "Could not open AppleSMC (\(result))."
        }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    func readAllTemperatures() throws -> [(key: String, value: Double)] {
        var readings: [(String, Double)] = []
        for key in Self.temperatureKeys {
            if let value = try readNumber(key), Self.isValidTemperature(value) {
                readings.append((key, value))
            }
        }
        guard !readings.isEmpty else {
            throw TelemetryIssue(message: "No supported temperature sensors were found.")
        }
        return readings
    }

    nonisolated static func isValidTemperature(_ value: Double) -> Bool {
        value.isFinite && (-40..<150).contains(value)
    }

    nonisolated static func isKnownFanlessModel(_ model: String) -> Bool {
        // Apple-silicon MacBook Air identifiers: https://support.apple.com/en-us/102869
        switch model {
        case "MacBookAir10,1", "Mac14,2", "Mac14,15", "Mac15,12", "Mac15,13",
             "Mac16,12", "Mac16,13", "Mac17,3", "Mac17,4":
            true
        default:
            false
        }
    }

    nonisolated static func readHardwareModel() throws -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 1 else {
            throw TelemetryIssue(message: "Mac hardware model is unavailable (errno \(errno)).")
        }
        var bytes = [UInt8](repeating: 0, count: size)
        let result = bytes.withUnsafeMutableBytes {
            sysctlbyname("hw.model", $0.baseAddress, &size, nil, 0)
        }
        guard result == 0 else {
            throw TelemetryIssue(message: "Mac hardware model is unavailable (status \(result), errno \(errno)).")
        }
        guard size > 1, size <= bytes.count, bytes[size - 1] == 0,
              let model = String(bytes: bytes.prefix(size - 1), encoding: .utf8) else {
            throw TelemetryIssue(message: "macOS returned an invalid hardware model.")
        }
        return model
    }

    func readFanSpeed() throws -> FanSpeed? {
        guard !isKnownFanless else { return nil }
        let count: Int
        if let cachedFanCount {
            count = cachedFanCount
        } else {
            guard let value = try readNumber("FNum") else {
                throw TelemetryIssue(message: "Fan availability could not be determined.")
            }
            guard (0...255).contains(value), value.rounded() == value else {
                throw TelemetryIssue(message: "AppleSMC returned an invalid fan count.")
            }
            count = Int(value)
            cachedFanCount = count
        }
        guard count > 0 else { return nil }
        var totalRPM = 0.0
        var totalPercentage = 0.0
        for index in 0..<count {
            guard let actual = try readNumber("F\(index)Ac"),
                  let maximum = try readNumber("F\(index)Mx"), actual >= 0, maximum > 0 else {
                throw TelemetryIssue(message: "Fan speed is unavailable.")
            }
            totalRPM += actual
            totalPercentage += actual / maximum * 100
        }
        return FanSpeed(rpm: totalRPM / Double(count), percentage: min(100, totalPercentage / Double(count)))
    }

    private func readNumber(_ key: String) throws -> Double? {
        if let connectionIssue { throw TelemetryIssue(message: connectionIssue) }
        var value = GlanceSMCValue()
        let result = glance_smc_read(connection, SMCValueDecoder.fourCC(key), &value)
        if result == kIOReturnNotFound { return nil }
        guard result == KERN_SUCCESS else {
            throw TelemetryIssue(message: "AppleSMC read failed (\(result)).")
        }
        let bytes = withUnsafeBytes(of: value.bytes) { Array($0.prefix(Int(value.data_size))) }
        guard let number = SMCValueDecoder.number(type: value.data_type, bytes: bytes) else {
            throw TelemetryIssue(message: "AppleSMC returned an unsupported sensor encoding.")
        }
        return number
    }
}
