import AppKit
import OSLog

struct ThermalGraphData {
    let history: [ThermalHistoryEntry]
    let samples: [ThermalHistoryEntry]
    let now: Date
    let temperatureRange: ClosedRange<Double>
    let hasFanData: Bool

    init(history: [ThermalHistoryEntry], showFanSpeed: Bool, now: Date) {
        self.history = history
        self.now = now
        if history.count > 300 {
            samples = (0..<300).map {
                history[Int(Double($0) * Double(history.count - 1) / 299)]
            }
        } else {
            samples = history
        }
        let temperatures = samples.compactMap(\.cpuMax).filter(\.isFinite)
        if let minimum = temperatures.min(), let maximum = temperatures.max() {
            let lower = max(30, minimum - 5)
            temperatureRange = lower...max(lower + 10, min(110, maximum + 5))
        } else {
            temperatureRange = 30...100
        }
        hasFanData = showFanSpeed && samples.contains { $0.fanPercent?.isFinite == true }
    }

    var start: Date { history.first?.timestamp ?? now }
    var duration: TimeInterval { max(1, now.timeIntervalSince(start)) }

    func fraction(at timestamp: Date) -> Double {
        min(1, max(0, timestamp.timeIntervalSince(start) / duration))
    }

    func nearestIndex(to fraction: Double) -> Int? {
        let target = start.addingTimeInterval(duration * min(1, max(0, fraction)))
        return history.indices.min {
            abs(history[$0].timestamp.timeIntervalSince(target)) <
                abs(history[$1].timestamp.timeIntervalSince(target))
        }
    }
}

final class ThermalGraphView: NSView {
    private let data: ThermalGraphData
    private var tracking: NSTrackingArea?
    private var selectedIndex: Int?
    private var hasDrawn = false

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(history: [ThermalHistoryEntry], showFanSpeed: Bool = true, now: Date = Date()) {
        data = ThermalGraphData(history: history, showFanSpeed: showFanSpeed, now: now)
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 120))
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Thermal history")
        if let latest = history.last {
            setAccessibilityValue(description(for: latest))
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private var graphRect: NSRect {
        NSRect(x: 14, y: 18, width: max(1, bounds.width - 28), height: 70)
    }

    private func xPosition(_ timestamp: Date) -> CGFloat {
        graphRect.minX + data.fraction(at: timestamp) * graphRect.width
    }

    private func yPosition(_ value: Double, range: ClosedRange<Double>) -> CGFloat {
        let fraction = min(1, max(0, (value - range.lowerBound) / (range.upperBound - range.lowerBound)))
        return graphRect.maxY - 4 - fraction * (graphRect.height - 8)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if !hasDrawn {
            Logger(subsystem: "com.local.glance.monitor", category: "graphs").debug(
                "Rendering native thermal history with \(self.data.history.count, privacy: .public) samples"
            )
            hasDrawn = true
        }
        let graph = NSBezierPath(roundedRect: graphRect, xRadius: 6, yRadius: 6)
        NSGraphicsContext.saveGraphicsState()
        graph.addClip()
        for (index, entry) in data.samples.enumerated() {
            let next = index + 1 < data.samples.count
                ? data.samples[index + 1].timestamp : data.now
            let end = min(next, entry.timestamp.addingTimeInterval(30))
            entry.pressure.color.withAlphaComponent(0.3).setFill()
            NSRect(
                x: xPosition(entry.timestamp),
                y: graphRect.minY,
                width: max(0, xPosition(end) - xPosition(entry.timestamp)),
                height: graphRect.height
            ).fill()
        }
        drawLine(range: data.temperatureRange, color: .labelColor, value: \.cpuMax)
        if data.hasFanData {
            drawLine(range: 0...100, color: .systemCyan, dashed: true, value: \.fanPercent)
        }
        if let selectedIndex, data.history.indices.contains(selectedIndex) {
            let entry = data.history[selectedIndex]
            let x = xPosition(entry.timestamp)
            let line = NSBezierPath()
            line.move(to: NSPoint(x: x, y: graphRect.minY))
            line.line(to: NSPoint(x: x, y: graphRect.maxY))
            NSColor.labelColor.withAlphaComponent(0.3).setStroke()
            line.lineWidth = 1
            line.stroke()
            if let temperature = entry.cpuMax {
                drawDot(
                    x: x,
                    value: temperature,
                    range: data.temperatureRange,
                    color: entry.pressure.color,
                    radius: 4
                )
            }
            if data.hasFanData, let fan = entry.fanPercent {
                drawDot(x: x, value: fan, range: 0...100, color: .systemCyan, radius: 3)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        NSColor.secondaryLabelColor.withAlphaComponent(0.3).setStroke()
        graph.lineWidth = 1
        graph.stroke()
        drawLabel(
            "\(Int(data.temperatureRange.upperBound))°",
            at: NSPoint(x: graphRect.minX + 4, y: graphRect.minY + 3)
        )
        drawLabel(
            "\(Int(data.temperatureRange.lowerBound))°",
            at: NSPoint(x: graphRect.minX + 4, y: graphRect.maxY - 13)
        )
        if data.hasFanData {
            drawLabel("100%", at: NSPoint(x: graphRect.maxX - 28, y: graphRect.minY + 3), color: .systemCyan)
            drawLabel("0%", at: NSPoint(x: graphRect.maxX - 17, y: graphRect.maxY - 13), color: .systemCyan)
        }
        let minutes = Int(data.duration) / 60
        let elapsed = minutes < 60 ? "\(minutes)m ago"
            : minutes % 60 == 0 ? "\(minutes / 60)h ago" : "\(minutes / 60)h \(minutes % 60)m ago"
        drawLabel(elapsed, at: NSPoint(x: graphRect.minX, y: graphRect.maxY + 3), size: 9)
        drawLabel("now", at: NSPoint(x: graphRect.maxX - 20, y: graphRect.maxY + 3), size: 9)
        drawTooltip()
    }

    private func drawLine(
        range: ClosedRange<Double>,
        color: NSColor,
        dashed: Bool = false,
        value: (ThermalHistoryEntry) -> Double?
    ) {
        let line = NSBezierPath()
        var previous: Date?
        for entry in data.samples {
            guard let reading = value(entry), reading.isFinite else {
                previous = nil
                continue
            }
            let point = NSPoint(x: xPosition(entry.timestamp), y: yPosition(reading, range: range))
            if let previous, entry.timestamp.timeIntervalSince(previous) <= 30 {
                line.line(to: point)
            } else {
                line.move(to: point)
            }
            previous = entry.timestamp
        }
        if let latest = data.samples.last, let reading = value(latest), reading.isFinite {
            let x = data.now.timeIntervalSince(latest.timestamp) <= 30
                ? graphRect.maxX : xPosition(latest.timestamp)
            if data.now.timeIntervalSince(latest.timestamp) <= 30 {
                line.line(to: NSPoint(x: x, y: yPosition(reading, range: range)))
            }
            drawDot(x: x, value: reading, range: range, color: color, radius: dashed ? 3 : 4)
        }
        color.withAlphaComponent(dashed ? 0.5 : 0.8).setStroke()
        line.lineWidth = dashed ? 1 : 1.5
        if dashed { line.setLineDash([4, 2], count: 2, phase: 0) }
        line.stroke()
    }

    private func drawDot(x: CGFloat, value: Double, range: ClosedRange<Double>, color: NSColor, radius: CGFloat) {
        guard value.isFinite else { return }
        let dot = NSBezierPath(ovalIn: NSRect(
            x: x - radius,
            y: yPosition(value, range: range) - radius,
            width: radius * 2,
            height: radius * 2
        ))
        color.setFill()
        dot.fill()
        if selectedIndex != nil {
            NSColor.labelColor.setStroke()
            dot.lineWidth = 1
            dot.stroke()
        }
    }

    private func drawLabel(_ text: String, at point: NSPoint, color: NSColor = .secondaryLabelColor, size: CGFloat = 8) {
        (text as NSString).draw(at: point, withAttributes: [
            .font: NSFont.systemFont(ofSize: size),
            .foregroundColor: color
        ])
    }

    private func description(for entry: ThermalHistoryEntry) -> String {
        let seconds = max(0, Int(data.now.timeIntervalSince(entry.timestamp)))
        let elapsed = seconds < 60 ? "\(seconds)s ago" : "\(seconds / 60)m ago"
        let temperature = entry.cpuMax.flatMap { $0.isFinite ? "\(Int($0))°" : nil } ?? "Unavailable"
        let fan: String
        if data.hasFanData, let percent = entry.fanPercent, percent.isFinite {
            fan = " · Fan \(Int(percent))%"
        } else {
            fan = ""
        }
        return "\(temperature) · \(entry.pressure.displayName)\(fan) · \(elapsed)"
    }

    private func drawTooltip() {
        guard let selectedIndex, data.history.indices.contains(selectedIndex) else { return }
        let text = description(for: data.history[selectedIndex]) as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        let size = text.size(withAttributes: attributes)
        let box = NSRect(
            x: max(graphRect.minX + 2, graphRect.maxX - size.width - 16),
            y: graphRect.minY + 4,
            width: min(graphRect.width - 4, size.width + 12),
            height: size.height + 6
        )
        NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill()
        NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
        text.draw(in: box.insetBy(dx: 6, dy: 3), withAttributes: attributes)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let tracking = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(tracking)
        self.tracking = tracking
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        selectedIndex = graphRect.contains(point)
            ? data.nearestIndex(to: (point.x - graphRect.minX) / graphRect.width) : nil
        updateSelection()
    }

    override func mouseExited(with event: NSEvent) {
        selectedIndex = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        mouseMoved(with: event)
    }

    override func keyDown(with event: NSEvent) {
        guard !data.history.isEmpty else { return }
        switch event.keyCode {
        case 123: selectedIndex = max(0, (selectedIndex ?? data.history.count) - 1)
        case 124: selectedIndex = min(data.history.count - 1, (selectedIndex ?? -1) + 1)
        default: super.keyDown(with: event); return
        }
        updateSelection()
    }

    private func updateSelection() {
        if let selectedIndex, data.history.indices.contains(selectedIndex) {
            setAccessibilityValue(description(for: data.history[selectedIndex]))
        }
        needsDisplay = true
    }
}

final class ThermalBreakdownView: NSView {
    private let rows: [(pressure: ThermalPressure, duration: String, percentage: String)]

    override var isFlipped: Bool { true }

    init(timeInEachState: [(pressure: ThermalPressure, duration: TimeInterval)], totalDuration: TimeInterval) {
        rows = [ThermalPressure.nominal, .moderate, .heavy, .critical].map { pressure in
            let duration = timeInEachState.first { $0.pressure == pressure }?.duration ?? 0
            let percentage = totalDuration > 0 ? "(\(Int((duration / totalDuration * 100).rounded()))%)" : ""
            return (pressure, Self.formatDuration(duration), percentage)
        }
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 80))
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("Thermal time in each state")
        setAccessibilityValue(rows.map { "\($0.pressure.displayName): \($0.duration) \($0.percentage)" }.joined(separator: ", "))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        for (index, row) in rows.enumerated() {
            let y = CGFloat(index) * 15 + 10
            row.pressure.color.setFill()
            NSBezierPath(ovalIn: NSRect(x: 14, y: y + 3, width: 7, height: 7)).fill()
            drawText(row.pressure.displayName, in: NSRect(x: 25, y: y, width: 60, height: 14))
            if row.pressure.isThrottling {
                drawText("⚡", in: NSRect(x: 89, y: y, width: 12, height: 14))
            }
            drawText(
                row.duration,
                in: NSRect(x: 104, y: y, width: bounds.width - 162, height: 14),
                color: .secondaryLabelColor,
                alignment: .right
            )
            drawText(
                row.percentage,
                in: NSRect(x: bounds.width - 54, y: y, width: 40, height: 14),
                color: .secondaryLabelColor,
                alignment: .right
            )
        }
    }

    private func drawText(_ text: String, in rect: NSRect, color: NSColor = .labelColor, alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        (text as NSString).draw(in: rect, withAttributes: [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
    }

    static func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = Int(duration)
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(seconds % 60)s" }
        return "\(seconds)s"
    }
}
