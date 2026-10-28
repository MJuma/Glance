import AppKit
import Foundation
import GlanceSupport
import Observation

struct ClockEntry: Codable, Identifiable {
    let id = UUID()
    var label: String
    let timezoneID: String
    var countryCode: String
    let timezone: TimeZone

    private enum CodingKeys: String, CodingKey {
        case label, timezoneID, countryCode
    }

    init(label: String, timezoneID: String, countryCode: String) throws {
        guard let timezone = TimeZone(identifier: timezoneID) else {
            throw ClockSettingsError.invalidTimezone(timezoneID)
        }
        self.label = label
        self.timezoneID = timezoneID
        self.countryCode = countryCode
        self.timezone = timezone
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            label: values.decode(String.self, forKey: .label),
            timezoneID: values.decode(String.self, forKey: .timezoneID),
            countryCode: values.decode(String.self, forKey: .countryCode)
        )
    }

    static func cityName(from timezoneID: String) -> String {
        (timezoneID.components(separatedBy: "/").last ?? timezoneID)
            .replacingOccurrences(of: "_", with: " ")
    }
}

enum ClockSettingsError: Error, LocalizedError {
    case invalidTimezone(String)

    var errorDescription: String? {
        switch self {
        case let .invalidTimezone(identifier): "Unsupported timezone identifier: \(identifier)."
        }
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
        AppLog.preferences.error("Could not load timezone country labels: \(error.localizedDescription)")
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
    private let logger = AppLog.preferences
    @ObservationIgnored private var preservesUnreadableConfiguration = false

    static let countryMap = loadTimezoneCountryMap()

    init(configURL: URL = URL(fileURLWithPath: "\(NSHomeDirectory())/.config/glance-clocks.json")) {
        self.configURL = configURL
        do {
            let data = try Data(contentsOf: configURL)
            clocks = try JSONDecoder().decode([ClockEntry].self, from: data)
        } catch CocoaError.fileReadNoSuchFile {
            do {
                clocks = try [
                    ClockEntry(label: "Berlin", timezoneID: "Europe/Berlin", countryCode: "DE"),
                    ClockEntry(label: "New York", timezoneID: "America/New_York", countryCode: "US")
                ]
                save()
            } catch {
                persistenceError = "Default clocks could not be created: \(error.localizedDescription)"
                logger.error("Could not initialize default clocks: \(error.localizedDescription)")
            }
        } catch {
            preservesUnreadableConfiguration = true
            persistenceError = "Clock settings could not be loaded: \(error.localizedDescription) The existing file has been preserved; repair it and restart before saving changes."
            logger.error("Could not load clock settings: \(error.localizedDescription)")
        }
    }

    func timeString(for clock: ClockEntry, at date: Date) -> String {
        clockTimeString(for: date, in: clock.timezone)
    }

    func hour(for clock: ClockEntry, at date: Date) -> Int {
        var calendar = Calendar.current
        calendar.timeZone = clock.timezone
        return calendar.component(.hour, from: date)
    }

    static func isDaytime(hour: Int) -> Bool { hour >= 4 && hour < 21 }

    var localTimezoneLabel: String {
        let timezone = TimeZone.current
        let abbreviation = timezone.abbreviation() ?? ""
        return "\(abbreviation), \(ClockTime.utcOffset(seconds: timezone.secondsFromGMT()))"
    }

    func addClock(label: String, timezoneID: String) {
        let country = Self.countryMap[timezoneID] ?? ""
        do {
            let clock = try ClockEntry(
                label: country.isEmpty ? label : "\(label), \(country)",
                timezoneID: timezoneID,
                countryCode: country
            )
            clocks.append(clock)
            save()
        } catch {
            persistenceError = error.localizedDescription
            logger.error("Could not add clock: \(error.localizedDescription)")
        }
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
    var calendar = Calendar.current {
        didSet {
            if calendar != oldValue { updateLabels() }
        }
    }
    var referenceDate = Date() {
        didSet { updateLabels() }
    }
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
        let date = ClockTime.date(forLocalMinute: minuteOfDay, relativeTo: referenceDate, calendar: calendar)
        nowLabel.stringValue = clockTimeString(for: date, in: calendar.timeZone)

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
