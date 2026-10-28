import AppKit
import Foundation
import Observation
import OSLog

struct ClockEntry: Codable, Identifiable {
    let id = UUID()
    var label: String
    var timezoneID: String
    var countryCode: String

    private enum CodingKeys: String, CodingKey {
        case label, timezoneID, countryCode
    }

    var timezone: TimeZone { TimeZone(identifier: timezoneID) ?? .current }

    static func cityName(from timezoneID: String) -> String {
        (timezoneID.components(separatedBy: "/").last ?? timezoneID)
            .replacingOccurrences(of: "_", with: " ")
    }
}

private func loadTimezoneCountryMap() -> [String: String] {
    do {
        let content = try String(
            contentsOfFile: "/usr/share/zoneinfo/zone.tab",
            encoding: .utf8
        )
        var map: [String: String] = [:]
        for line in content.components(separatedBy: "\n") {
            if line.hasPrefix("#") || line.isEmpty { continue }
            let parts = line.components(separatedBy: "\t")
            if parts.count >= 3 { map[parts[2]] = parts[0] }
        }
        return map
    } catch {
        Logger(subsystem: "com.local.glance.time", category: "timezones")
            .error("Could not load timezone country labels: \(error.localizedDescription)")
        return [:]
    }
}

func clockTimeString(for date: Date, in timezone: TimeZone) -> String {
    date.formatted(Date.VerbatimFormatStyle(
        format: "\(hour: .defaultDigits(clock: .twelveHour, hourCycle: .oneBased)):\(minute: .twoDigits) \(dayPeriod: .standard(.abbreviated))",
        locale: Locale(identifier: "en_US_POSIX"),
        timeZone: timezone,
        calendar: Calendar(identifier: .gregorian)
    ))
}

@MainActor
@Observable
final class WorldClockMonitor {
    private(set) var clocks: [ClockEntry] = []
    private(set) var persistenceError: String?
    private let configURL: URL
    private let logger = Logger(subsystem: "com.local.glance.time", category: "settings")
    @ObservationIgnored private var preservesUnreadableConfiguration = false

    static let countryMap = loadTimezoneCountryMap()

    init(configURL: URL = URL(fileURLWithPath: "\(NSHomeDirectory())/.config/glance-clocks.json")) {
        self.configURL = configURL
        do {
            let data = try Data(contentsOf: configURL)
            clocks = try JSONDecoder().decode([ClockEntry].self, from: data)
        } catch CocoaError.fileReadNoSuchFile {
            clocks = [
                ClockEntry(label: "Berlin", timezoneID: "Europe/Berlin", countryCode: "DE"),
                ClockEntry(label: "New York", timezoneID: "America/New_York", countryCode: "US")
            ]
            save()
        } catch {
            preservesUnreadableConfiguration = true
            persistenceError = "Clock settings could not be loaded. The existing file has been preserved; changes cannot be saved until it is repaired."
            logger.error("Could not load clock settings: \(error.localizedDescription)")
        }
    }

    func timeString(for clock: ClockEntry, atLocalMinute minute: Int? = nil) -> String {
        clockTimeString(for: dateForMinute(minute), in: clock.timezone)
    }

    func hour(for clock: ClockEntry, atLocalMinute minute: Int? = nil) -> Int {
        var calendar = Calendar.current
        calendar.timeZone = clock.timezone
        return calendar.component(.hour, from: dateForMinute(minute))
    }

    private func dateForMinute(_ minute: Int?) -> Date {
        let now = Date()
        guard let minute else { return now }
        let calendar = Calendar.current
        let current = calendar.component(.hour, from: now) * 60
            + calendar.component(.minute, from: now)
        return now.addingTimeInterval(TimeInterval((minute - current) * 60))
    }

    static func isDaytime(hour: Int) -> Bool { hour >= 4 && hour < 21 }

    var currentMinuteOfDay: Int {
        let calendar = Calendar.current
        let now = Date()
        return calendar.component(.hour, from: now) * 60
            + calendar.component(.minute, from: now)
    }

    var localTimezoneLabel: String {
        let timezone = TimeZone.current
        let abbreviation = timezone.abbreviation() ?? ""
        let hours = timezone.secondsFromGMT() / 3600
        return "\(abbreviation), \(hours >= 0 ? "+" : "")\(hours)"
    }

    func addClock(label: String, timezoneID: String) {
        let country = Self.countryMap[timezoneID] ?? ""
        clocks.append(ClockEntry(
            label: country.isEmpty ? label : "\(label), \(country)",
            timezoneID: timezoneID,
            countryCode: country
        ))
        save()
    }

    func removeClock(at index: Int) {
        guard clocks.indices.contains(index) else { return }
        clocks.remove(at: index)
        save()
    }

    func moveClock(from: Int, to: Int) {
        guard clocks.indices.contains(from), (0...clocks.count).contains(to) else { return }
        let clock = clocks.remove(at: from)
        clocks.insert(clock, at: to > from ? to - 1 : to)
        save()
    }

    private func save() {
        guard !preservesUnreadableConfiguration else {
            logger.error("Clock settings were not saved because the existing configuration could not be loaded")
            return
        }
        do {
            let data = try JSONEncoder().encode(clocks)
            try FileManager.default.createDirectory(
                at: configURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: configURL, options: .atomic)
            persistenceError = nil
        } catch {
            persistenceError = "Clock changes could not be saved: \(error.localizedDescription)"
            logger.error("Could not save clock settings: \(error.localizedDescription)")
        }
    }

    static let allTimezones: [(id: String, city: String, country: String)] =
        TimeZone.knownTimeZoneIdentifiers
            .filter { $0.contains("/") && !$0.hasPrefix("US/") && !$0.hasPrefix("Etc/") }
            .map { (id: $0, city: ClockEntry.cityName(from: $0), country: countryMap[$0] ?? "") }
            .sorted { $0.city < $1.city }
}

// MARK: - Time Scrubber

final class TimeScrubber: NSView {
    var minuteOfDay = 0 {
        didSet {
            guard minuteOfDay != oldValue else { return }
            needsDisplay = true
            updateLabels()
        }
    }
    var onChanged: ((Int) -> Void)?
    var onReleased: (() -> Void)?
    private var isDragging = false

    private let fromLabel = NSTextField(labelWithString: "12:00 AM")
    private let toLabel = NSTextField(labelWithString: "11:59 PM")
    private let nowLabel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        let labelColor = NSColor(white: 1, alpha: 0.3)
        for label in [fromLabel, toLabel] {
            label.font = labelFont
            label.textColor = labelColor
            label.isBezeled = false
            label.drawsBackground = false
            addSubview(label)
        }
        toLabel.alignment = .right
        nowLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        nowLabel.textColor = .white
        nowLabel.isBezeled = false
        nowLabel.drawsBackground = false
        addSubview(nowLabel)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var mouseDownCanMoveWindow: Bool { false }

    override func layout() {
        super.layout()
        let height = bounds.height
        fromLabel.frame = NSRect(x: 0, y: (height - 14) / 2, width: 64, height: 14)
        toLabel.frame = NSRect(x: bounds.width - 64, y: (height - 14) / 2, width: 64, height: 14)
        updateLabels()
    }

    private func updateLabels() {
        guard bounds.width > 0 else { return }
        let width = bounds.width
        let height = bounds.height
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = minuteOfDay / 60
        components.minute = minuteOfDay % 60
        if let date = calendar.date(from: components) {
            nowLabel.stringValue = clockTimeString(for: date, in: .current)
        }

        let thumbX = CGFloat(minuteOfDay) / 1439 * width
        let labelWidth: CGFloat = 60
        let labelX = minuteOfDay < 1260 ? thumbX + 10 : thumbX - labelWidth - 5
        nowLabel.frame = NSRect(
            x: max(0, min(width - labelWidth, labelX)),
            y: (height - 14) / 2,
            width: labelWidth,
            height: 14
        )

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .linear)
            fromLabel.animator().alphaValue = minuteOfDay < 250 ? 0 : 1
            toLabel.animator().alphaValue = minuteOfDay > 950 ? 0 : 1
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let thumbX = CGFloat(minuteOfDay) / 1439 * bounds.width
        context.setStrokeColor(NSColor(red: 0.133, green: 0.467, blue: 1, alpha: 1).cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: thumbX, y: 0))
        context.addLine(to: CGPoint(x: thumbX, y: bounds.height))
        context.strokePath()
    }

    private func updateFromEvent(_ event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        minuteOfDay = Int(max(0, min(1, location.x / bounds.width)) * 1439)
        onChanged?(minuteOfDay)
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        updateFromEvent(event)
    }

    override func mouseDragged(with event: NSEvent) {
        if isDragging { updateFromEvent(event) }
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        onReleased?()
    }
}
