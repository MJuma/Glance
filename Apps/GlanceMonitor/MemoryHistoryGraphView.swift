import AppKit

final class MemoryHistoryGraphView: NSView {
    private let history: [MemoryHistoryEntry]
    private let now: Date
    private var tracking: NSTrackingArea?
    private var selectedIndex: Int?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(history: [MemoryHistoryEntry], now: Date = Date()) {
        self.history = history
        self.now = now
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 128))
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Memory usage history")
        if let latest = history.last {
            setAccessibilityValue(description(for: latest))
        }
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    private var graphRect: NSRect {
        NSRect(x: 14, y: 6, width: max(1, bounds.width - 28), height: 90)
    }

    private var start: Date {
        max(
            now.addingTimeInterval(-MemoryMonitor.historyDuration),
            history.first?.timestamp ?? now.addingTimeInterval(-MemoryMonitor.historyDuration)
        )
    }

    private var duration: TimeInterval {
        max(1, now.timeIntervalSince(start))
    }

    private var totalGB: Double {
        Double(history.last?.snapshot.totalGB ?? 0)
    }

    private func xPosition(_ timestamp: Date) -> CGFloat {
        graphRect.minX + CGFloat(timestamp.timeIntervalSince(start) / duration) * graphRect.width
    }

    private func yPosition(_ usedGB: Double) -> CGFloat {
        let fraction = totalGB > 0 ? min(1, max(0, usedGB / totalGB)) : 0
        return graphRect.maxY - 4 - CGFloat(fraction) * (graphRect.height - 8)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let graph = NSBezierPath(roundedRect: graphRect, xRadius: 6, yRadius: 6)
        NSColor.controlBackgroundColor.withAlphaComponent(0.35).setFill()
        graph.fill()

        NSGraphicsContext.saveGraphicsState()
        graph.addClip()
        for (index, entry) in history.enumerated() {
            let nextDate = index + 1 < history.count ? history[index + 1].timestamp : now
            let endDate = min(nextDate, entry.timestamp.addingTimeInterval(30))
            let left = max(graphRect.minX, xPosition(entry.timestamp))
            let right = min(graphRect.maxX, xPosition(endDate))
            guard right > left else { continue }
            entry.snapshot.pressure.color.withAlphaComponent(0.18).setFill()
            NSRect(x: left, y: graphRect.minY, width: right - left, height: graphRect.height).fill()
        }

        if totalGB > 0 {
            for fraction in [0.25, 0.5, 0.75] {
                let y = yPosition(totalGB * fraction)
                let line = NSBezierPath()
                line.move(to: NSPoint(x: graphRect.minX, y: y))
                line.line(to: NSPoint(x: graphRect.maxX, y: y))
                line.lineWidth = 0.5
                NSColor.secondaryLabelColor.withAlphaComponent(0.2).setStroke()
                line.stroke()
            }

            let usage = NSBezierPath()
            var previous: MemoryHistoryEntry?
            for entry in history where entry.timestamp >= start && entry.timestamp <= now {
                let point = NSPoint(x: xPosition(entry.timestamp), y: yPosition(entry.snapshot.usedGB))
                if let previous, entry.timestamp.timeIntervalSince(previous.timestamp) <= 30 {
                    usage.line(to: point)
                } else {
                    usage.move(to: point)
                }
                previous = entry
            }
            NSColor.systemBlue.setStroke()
            usage.lineWidth = 1.5
            usage.stroke()

            if let latest = history.last {
                let point = NSPoint(x: xPosition(latest.timestamp), y: yPosition(latest.snapshot.usedGB))
                NSColor.systemBlue.setFill()
                NSBezierPath(ovalIn: NSRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)).fill()
            }
        }

        if let selectedIndex, history.indices.contains(selectedIndex) {
            let entry = history[selectedIndex]
            let x = xPosition(entry.timestamp)
            let line = NSBezierPath()
            line.move(to: NSPoint(x: x, y: graphRect.minY))
            line.line(to: NSPoint(x: x, y: graphRect.maxY))
            NSColor.labelColor.withAlphaComponent(0.35).setStroke()
            line.lineWidth = 1
            line.stroke()
            entry.snapshot.pressure.color.setFill()
            let dot = NSBezierPath(ovalIn: NSRect(
                x: x - 4, y: yPosition(entry.snapshot.usedGB) - 4, width: 8, height: 8
            ))
            dot.fill()
            NSColor.labelColor.setStroke()
            dot.lineWidth = 1
            dot.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()

        NSColor.separatorColor.setStroke()
        graph.lineWidth = 1
        graph.stroke()

        drawLabel("\(Int(totalGB)) GB", at: NSPoint(x: graphRect.minX + 4, y: graphRect.minY + 2))
        drawLabel("0 GB", at: NSPoint(x: graphRect.minX + 4, y: graphRect.maxY - 13))
        if history.count < 2 {
            drawLabel(
                "Collecting memory history…",
                at: NSPoint(x: graphRect.midX - 65, y: graphRect.midY - 6)
            )
        }
        let minutes = Int(now.timeIntervalSince(start) / 60)
        let elapsed = minutes > 0 ? "\(minutes)m ago" : "\(Int(duration))s ago"
        drawLabel(elapsed, at: NSPoint(x: graphRect.minX, y: graphRect.maxY + 3))
        drawLabel("now", at: NSPoint(x: graphRect.maxX - 20, y: graphRect.maxY + 3))
        drawLabel(
            "RAM used · background shows memory pressure",
            at: NSPoint(x: graphRect.minX, y: graphRect.maxY + 16)
        )
        drawTooltip()
    }

    private func drawLabel(_ text: String, at point: NSPoint) {
        (text as NSString).draw(at: point, withAttributes: [
            .font: NSFont.systemFont(ofSize: 8),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
    }

    private func description(for entry: MemoryHistoryEntry) -> String {
        let timestamp = entry.timestamp.formatted(date: .omitted, time: .shortened)
        let snapshot = entry.snapshot
        return String(
            format: "%@ · %.1f/%d GB · %@\nAvailable %.1f GB · Compressed %.1f GB\nSwap %.1f GB",
            timestamp,
            snapshot.usedGB,
            snapshot.totalGB,
            snapshot.pressure.displayName,
            snapshot.availableGB,
            snapshot.compressedGB,
            Double(snapshot.swapUsedMB) / 1024
        )
    }

    private func drawTooltip() {
        guard let selectedIndex, history.indices.contains(selectedIndex) else { return }
        let text = description(for: history[selectedIndex])
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let box = NSRect(
            x: max(graphRect.minX + 2, graphRect.maxX - size.width - 12),
            y: graphRect.minY + 2,
            width: min(graphRect.width - 4, size.width + 10),
            height: size.height + 8
        )
        NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill()
        NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).fill()
        (text as NSString).draw(in: box.insetBy(dx: 5, dy: 4), withAttributes: attributes)
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
        guard graphRect.contains(point), !history.isEmpty else {
            selectedIndex = nil
            needsDisplay = true
            return
        }
        selectedIndex = history.indices.min {
            abs(xPosition(history[$0].timestamp) - point.x) <
                abs(xPosition(history[$1].timestamp) - point.x)
        }
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
        guard !history.isEmpty else { return }
        switch event.keyCode {
        case 123: selectedIndex = max(0, (selectedIndex ?? history.count) - 1)
        case 124: selectedIndex = min(history.count - 1, (selectedIndex ?? -1) + 1)
        default: super.keyDown(with: event); return
        }
        updateSelection()
    }

    private func updateSelection() {
        if let selectedIndex, history.indices.contains(selectedIndex) {
            setAccessibilityValue(description(for: history[selectedIndex]))
        }
        needsDisplay = true
    }
}
