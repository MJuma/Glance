import AppKit
import OSLog
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Unified Time and Date Menu

@MainActor
final class TimeAndDateMenu: NSObject, NSMenuDelegate {
    private let worldClock: WorldClockMonitor
    let menu = NSMenu()
    private let contentItem = NSMenuItem()
    private var hostingView: NSHostingView<LiveTimeAndDateView>?
    private var isOpen = false
    private let onAddClock: () -> Void

    static let width: CGFloat = 410
    var hasContent: Bool { hostingView != nil }

    init(worldClock: WorldClockMonitor, onAddClock: @escaping () -> Void = {}) {
        self.worldClock = worldClock
        self.onAddClock = onAddClock
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self
        menu.addItem(contentItem)
    }

    func menuWillOpen(_ menu: NSMenu) {
        isOpen = true
        prepareContent()
        Logger(subsystem: "com.local.glance.time", category: "menus")
            .debug("Time menu opened")
    }

    func menuDidClose(_ menu: NSMenu) {
        isOpen = false
        Task { @MainActor [weak self] in
            guard let self, !self.isOpen else { return }
            self.contentItem.view = nil
            self.hostingView = nil
            Logger(subsystem: "com.local.glance.time", category: "menus")
                .debug("Time menu closed and content released")
        }
    }

    private func prepareContent() {
        let view = NSHostingView(rootView: LiveTimeAndDateView(
            worldClock: worldClock,
            onClockCountChanged: { [weak self] _ in
                Task { @MainActor [weak self] in self?.resizeToFit() }
            },
            onAddClock: { [weak self] in
                guard let self else { return }
                self.menu.cancelTracking()
                Task { @MainActor [weak self] in self?.onAddClock() }
            }
        ))
        view.sizingOptions = [.intrinsicContentSize]
        hostingView = view
        resizeToFit()
        contentItem.view = view
    }

    private func resizeToFit() {
        guard let view = hostingView else { return }
        view.invalidateIntrinsicContentSize()
        view.layoutSubtreeIfNeeded()
        view.setFrameSize(NSSize(width: Self.width, height: ceil(view.fittingSize.height)))
    }
}

private struct LiveTimeAndDateView: View {
    let worldClock: WorldClockMonitor
    let onClockCountChanged: (Int) -> Void
    let onAddClock: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            TimeAndDateView(
                worldClock: worldClock,
                now: context.date,
                onClockCountChanged: onClockCountChanged,
                onAddClock: onAddClock
            )
        }
    }
}

// MARK: - Unified SwiftUI Content

struct TimeAndDateView: View {
    let worldClock: WorldClockMonitor
    let now: Date
    let onClockCountChanged: (Int) -> Void
    let onAddClock: () -> Void

    @State private var scrubMinute: Int?
    @State private var displayedMonth: Date
    @State private var draggedClockIndex: Int?

    private let calendar = Calendar.current

    init(
        worldClock: WorldClockMonitor,
        now: Date = Date(),
        onClockCountChanged: @escaping (Int) -> Void = { _ in },
        onAddClock: @escaping () -> Void = {}
    ) {
        self.worldClock = worldClock
        self.now = now
        self.onClockCountChanged = onClockCountChanged
        self.onAddClock = onAddClock
        _scrubMinute = State(initialValue: nil)
        _displayedMonth = State(initialValue: Self.monthStart(for: now))
    }

    var body: some View {
        VStack(spacing: 10) {
            worldClockSection
            if let error = worldClock.persistenceError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider().opacity(0.25)
            calendarSection
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(
            width: TimeAndDateMenu.width,
            alignment: .top
        )
        .fixedSize(horizontal: false, vertical: true)
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .onChange(of: calendar.startOfDay(for: now)) { oldDay, newDay in
            if calendar.isDate(displayedMonth, equalTo: oldDay, toGranularity: .month) {
                displayedMonth = Self.monthStart(for: newDay)
            }
        }
        .onChange(of: worldClock.persistenceError) { _, _ in
            onClockCountChanged(worldClock.clocks.count)
        }
    }

    private var worldClockSection: some View {
        VStack(spacing: 8) {
            HStack {
                Label("World Clocks", systemImage: "globe.americas.fill")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(worldClock.localTimezoneLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Button {
                    onAddClock()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Add world clock")
            }

            VStack(spacing: 8) {
                TimeScrubberRepresentable(
                    minute: $scrubMinute,
                    currentMinute: worldClock.currentMinuteOfDay
                )
                .frame(height: 38)
                .padding(.horizontal, 8)
                .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))

                VStack(spacing: 4) {
                    ForEach(
                        Array(worldClock.clocks.enumerated()),
                        id: \.element.id
                    ) { index, clock in
                        clockRow(clock, at: index)
                            .onDrag {
                                draggedClockIndex = index
                                return NSItemProvider(
                                    object: "\(index)" as NSString
                                )
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: ClockDropDelegate(
                                    destinationIndex: index,
                                    draggedIndex: $draggedClockIndex,
                                    worldClock: worldClock
                                )
                            )
                    }
                }
            }
        }
    }

    private func clockRow(_ clock: ClockEntry, at index: Int) -> some View {
        let minute = scrubMinute
        let hour = worldClock.hour(for: clock, atLocalMinute: minute)
        let daytime = WorldClockMonitor.isDaytime(hour: hour)

        return HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .help("Drag to reorder")

            Image(systemName: daytime ? "sun.max.fill" : "moon.stars.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(daytime ? .yellow : .indigo)
                .frame(width: 25, height: 25)
                .background(
                    (daytime ? Color.yellow : Color.indigo).opacity(0.12),
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(clock.label)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(clockDayLabel(clock, atLocalMinute: minute))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(worldClock.timeString(
                for: clock,
                atLocalMinute: minute
            ))
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .monospacedDigit()

            Button {
                worldClock.removeClock(at: index)
                onClockCountChanged(worldClock.clocks.count)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove \(clock.label)")
        }
        .padding(.horizontal, 8)
        .frame(height: 38)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
    }

    private var calendarSection: some View {
        VStack(spacing: 9) {
            ZStack {
                Text(displayedMonth.formatted(
                    .dateTime.month(.wide).year()
                ))
                .font(.system(size: 15, weight: .semibold))

                HStack {
                    Button {
                        moveMonth(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.borderless)

                    Spacer()

                    Button {
                        moveMonth(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.borderless)
                }
            }

            Grid(horizontalSpacing: 5, verticalSpacing: 5) {
                GridRow {
                    Text("Wk")
                        .foregroundStyle(.tertiary)
                        .frame(width: 24)
                    ForEach(Array(daySymbols.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .font(.system(size: 9, weight: .medium))

                ForEach(Array(calendarWeeks.enumerated()), id: \.offset) {
                    _, week in
                    GridRow {
                        Text("\(week.number)")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: 24)

                        ForEach(week.days, id: \.self) { date in
                            calendarDay(date)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }

            VStack(spacing: 3) {
                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        displayedMonth = Self.monthStart(for: now)
                    }
                } label: {
                    Label("Back to Today", systemImage: "calendar.badge.clock")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isCurrentMonth)
                .opacity(isCurrentMonth ? 0 : 1)
                .accessibilityHidden(isCurrentMonth)
                .frame(height: 20)

                Text(
                    "Week \(calendar.component(.weekOfYear, from: now)) " +
                    "of \(calendar.component(.yearForWeekOfYear, from: now))"
                )
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func calendarDay(_ date: Date) -> some View {
        let day = calendar.component(.day, from: date)
        let inDisplayedMonth = calendar.isDate(
            date,
            equalTo: displayedMonth,
            toGranularity: .month
        )
        let isToday = calendar.isDate(date, inSameDayAs: now)

        return Button {
            if !inDisplayedMonth {
                withAnimation(.snappy(duration: 0.2)) {
                    displayedMonth = Self.monthStart(for: date)
                }
            }
        } label: {
            ZStack {
                if isToday {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor)
                        .frame(width: 29, height: 25)
                }
                Text("\(day)")
                    .font(.system(
                        size: 11,
                        weight: isToday ? .bold : .regular,
                        design: .rounded
                    ))
                    .foregroundStyle(
                        isToday
                            ? Color.white
                            : inDisplayedMonth
                                ? Color.primary
                                : Color.secondary.opacity(0.4)
                    )
            }
            .frame(maxWidth: .infinity, minHeight: 25)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func clockDayLabel(
        _ clock: ClockEntry,
        atLocalMinute minute: Int?
    ) -> String {
        let date: Date
        if let minute {
            let currentMinute = worldClock.currentMinuteOfDay
            date = Date().addingTimeInterval(
                TimeInterval((minute - currentMinute) * 60)
            )
        } else {
            date = Date()
        }
        var timezoneCalendar = Calendar.current
        timezoneCalendar.timeZone = clock.timezone
        let weekday = timezoneCalendar.component(.weekday, from: date)
        let localWeekday = calendar.component(.weekday, from: date)
        if weekday == localWeekday {
            return clock.timezone.abbreviation(for: date) ?? clock.timezoneID
        }
        var format = Date.FormatStyle.dateTime.weekday(.wide)
        format.timeZone = clock.timezone
        return date.formatted(format)
    }

    private var daySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let startIndex = max(0, calendar.firstWeekday - 1)
        return Array(symbols[startIndex...] + symbols[..<startIndex])
    }

    private var calendarWeeks: [(number: Int, days: [Date])] {
        let firstWeekday = calendar.component(.weekday, from: displayedMonth)
        let offset = (firstWeekday - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(
            byAdding: .day,
            value: -offset,
            to: displayedMonth
        ) else { return [] }

        return (0..<6).map { row in
            let days = (0..<7).compactMap { column in
                calendar.date(
                    byAdding: .day,
                    value: row * 7 + column,
                    to: gridStart
                )
            }
            let weekNumber = days.first.map {
                calendar.component(.weekOfYear, from: $0)
            } ?? 0
            return (weekNumber, days)
        }
    }

    private var isCurrentMonth: Bool {
        calendar.isDate(
            displayedMonth,
            equalTo: now,
            toGranularity: .month
        )
    }

    private func moveMonth(by value: Int) {
        guard let month = calendar.date(
            byAdding: .month,
            value: value,
            to: displayedMonth
        ) else { return }
        withAnimation(.snappy(duration: 0.2)) {
            displayedMonth = Self.monthStart(for: month)
        }
    }

    private static func monthStart(for date: Date) -> Date {
        let calendar = Calendar.current
        return calendar.date(
            from: calendar.dateComponents([.year, .month], from: date)
        ) ?? date
    }
}

private struct TimeScrubberRepresentable: NSViewRepresentable {
    @Binding var minute: Int?
    let currentMinute: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(minute: $minute)
    }

    func makeNSView(context: Context) -> TimeScrubber {
        let scrubber = TimeScrubber(frame: .zero)
        scrubber.minuteOfDay = currentMinute
        scrubber.onChanged = { value in
            context.coordinator.minute.wrappedValue = value
        }
        scrubber.onReleased = {
            context.coordinator.minute.wrappedValue = nil
        }
        return scrubber
    }

    func updateNSView(_ scrubber: TimeScrubber, context: Context) {
        context.coordinator.minute = $minute
        scrubber.minuteOfDay = minute ?? currentMinute
    }

    final class Coordinator {
        var minute: Binding<Int?>

        init(minute: Binding<Int?>) {
            self.minute = minute
        }
    }
}

@MainActor
private struct ClockDropDelegate: DropDelegate {
    let destinationIndex: Int
    @Binding var draggedIndex: Int?
    let worldClock: WorldClockMonitor

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        guard let draggedIndex,
              draggedIndex != destinationIndex else { return }
        let targetIndex = draggedIndex < destinationIndex
            ? destinationIndex + 1
            : destinationIndex
        worldClock.moveClock(
            from: draggedIndex,
            to: targetIndex
        )
        self.draggedIndex = destinationIndex
    }

    func performDrop(info: DropInfo) -> Bool {
        guard draggedIndex != nil else { return false }
        self.draggedIndex = nil
        return true
    }
}
