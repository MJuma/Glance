import Foundation

enum ClockTime {
    static func date(
        forLocalMinute minute: Int?,
        relativeTo reference: Date,
        calendar: Calendar = .current
    ) -> Date {
        guard let minute else { return reference }
        precondition((0..<1_440).contains(minute), "A scrubber minute must be within its local day")
        var components = calendar.dateComponents([.era, .year, .month, .day, .isLeapMonth], from: reference)
        components.hour = minute / 60
        components.minute = minute % 60
        components.second = 0
        guard let normalized = calendar.date(from: components) else {
            preconditionFailure("Calendar could not normalize a valid local scrubber minute")
        }
        let beforeDay = calendar.startOfDay(for: normalized).addingTimeInterval(-1)
        // Construction handles non-hour DST gaps too; the strict match chooses the first repeated time.
        guard let date = calendar.nextDate(
            after: beforeDay,
            matching: calendar.dateComponents([.hour, .minute, .second], from: normalized),
            matchingPolicy: .strict,
            repeatedTimePolicy: .first
        ) else {
            preconditionFailure("Calendar could not resolve a valid local scrubber minute")
        }
        return date
    }

    static func minuteOfDay(at date: Date, calendar: Calendar = .current) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    static func utcOffset(seconds: Int) -> String {
        let minutes = abs(seconds / 60)
        return String(format: "%@%02d:%02d", seconds < 0 ? "-" : "+", minutes / 60, minutes % 60)
    }
}
