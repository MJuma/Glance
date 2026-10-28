import AppKit
import GlanceSupport

@MainActor
func makeFanMenuItem(for state: FanState) -> NSMenuItem? {
    switch state {
    case .notPresent:
        nil
    case let .available(fan):
        makeMonoItem(
            String(format: "Fan: %.0f RPM (%.0f%%)", fan.rpm, fan.percentage),
            color: .systemCyan
        )
    case .unavailable:
        makeMonoItem("Fan: Unavailable")
    }
}

@MainActor
final class MonitorAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let memory: MemoryMonitor
    private let thermal: ThermalMonitor
    private var statusItem: NSStatusItem!
    private let overviewMenu = NSMenu()
    private let memoryMenu = NSMenu()
    private let thermalMenu = NSMenu()
    private var timers: [Timer] = []
    private var openMenus: Set<ObjectIdentifier> = []
    private var lastStatusPresentationKey: String?
    private var processListTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private static let processRowTag = 10

    init(memory: MemoryMonitor = MemoryMonitor(), thermal: ThermalMonitor = ThermalMonitor()) {
        self.memory = memory
        self.thermal = thermal
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = overviewMenu
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        overviewMenu.addItem(makeInfoItem("Glance Monitor"))
        thermalMenu.addItem(makeInfoItem("Thermal Details"))
        memoryMenu.addItem(makeInfoItem("Memory Details"))
        for menu in [overviewMenu, thermalMenu, memoryMenu] {
            menu.delegate = self
        }
        memory.poll()
        thermal.poll()
        updateStatusItem()

        let timer = makeMonitorPollingTimer { [weak self] in
            guard let self else { return }
            self.memory.poll()
            self.thermal.poll()
            self.updateStatusItem()
        }
        timers.append(timer)
        #if DEBUG
            if DebugLifecycleHarness.isRequested {
                DebugLifecycleHarness.run { try await self.runLifecycleSmokeTest() }
            }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        timers.forEach { $0.invalidate() }
        processListTasks.values.forEach { $0.cancel() }
    }

    func menuWillOpen(_ menu: NSMenu) {
        openMenus.insert(ObjectIdentifier(menu))
        menu.removeAllItems()
        if menu === overviewMenu {
            buildOverviewMenu()
            addApplicationActions(to: menu)
        } else if menu === memoryMenu {
            buildMemoryMenu()
        } else if menu === thermalMenu {
            buildThermalMenu()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        openMenus.remove(ObjectIdentifier(menu))
        processListTasks.removeValue(forKey: ObjectIdentifier(menu))?.cancel()
        guard menu === memoryMenu || menu === thermalMenu else { return }
        DispatchQueue.main.async { [weak self, weak menu] in
            guard let self, let menu,
                  !self.openMenus.contains(ObjectIdentifier(menu)) else { return }
            menu.removeAllItems()
            menu.addItem(makeInfoItem(menu === self.thermalMenu ? "Thermal Details" : "Memory Details"))
        }
    }

    private var memoryStatus: (label: String, color: NSColor) {
        guard let snapshot = memory.snapshot else { return ("Unavailable", .systemGray) }
        return (snapshot.pressure.displayName, snapshot.pressure.color)
    }

    private func updateStatusItem() {
        let pressure = thermal.snapshot.pressure
        let memoryStatus = memoryStatus
        let appearance = statusItem.button?.effectiveAppearance.name.rawValue ?? ""
        let usage = memory.snapshot.map { "\($0.usedPercent)%" } ?? "—"
        let presentationKey = "\(pressure.displayName)|\(memoryStatus.label)|\(usage)|\(appearance)|\(memory.issue ?? "")|\(thermal.snapshot.issue ?? "")"
        guard presentationKey != lastStatusPresentationKey else { return }
        lastStatusPresentationKey = presentationKey
        let symbol: String
        switch pressure {
        case .nominal, .unknown: symbol = "thermometer.low"
        case .moderate: symbol = "thermometer.medium"
        case .heavy: symbol = "thermometer.high"
        case .critical: symbol = "thermometer.sun.fill"
        }
        let indicators: [(NSImage, NSRect)] = [
            (
                makeIcon(symbolName: symbol, color: pressure.color),
                NSRect(x: 0, y: 1, width: 18, height: 18)
            ),
            (
                makeIcon(symbolName: "memorychip.fill", color: memoryStatus.color),
                NSRect(x: 22, y: 1, width: 18, height: 18)
            )
        ]
        let image = NSImage(size: NSSize(width: 40, height: 20), flipped: false) { _ in
            for (indicator, bounds) in indicators {
                let scale = min(
                    bounds.width / indicator.size.width,
                    bounds.height / indicator.size.height
                )
                let size = NSSize(
                    width: indicator.size.width * scale,
                    height: indicator.size.height * scale
                )
                indicator.draw(
                    in: NSRect(
                        x: bounds.midX - size.width / 2,
                        y: bounds.midY - size.height / 2,
                        width: size.width,
                        height: size.height
                    ),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1
                )
            }
            return true
        }
        image.isTemplate = false
        statusItem.button?.image = image
        statusItem.button?.title = usage
        let summary = [
            "Glance Monitor",
            "Thermal: \(pressure.displayName)",
            "Memory: \(memoryStatus.label) (\(usage) used)",
            thermal.snapshot.issue,
            memory.issue
        ].compactMap { $0 }.joined(separator: "\n")
        statusItem.button?.toolTip = summary
        statusItem.button?.setAccessibilityLabel(summary)
    }

    private func buildOverviewMenu() {
        let thermalSnapshot = thermal.snapshot
        let memorySnapshot = memory.snapshot
        let memoryStatus = memoryStatus
        overviewMenu.addItem(makeInfoItem(
            "Glance Monitor",
            font: NSFont.menuFont(ofSize: 14)
        ))
        overviewMenu.addItem(makeInfoItem(
            "Thermal: \(thermalSnapshot.pressure.displayName)",
            color: thermalSnapshot.stateColor
        ))
        overviewMenu.addItem(makeInfoItem(
            "CPU \(formatTemperature(thermalSnapshot.cpuMax)) · GPU \(formatTemperature(thermalSnapshot.gpuMax))"
        ))
        overviewMenu.addItem(makeInfoItem(
            "Memory: \(memoryStatus.label)" + (memorySnapshot.map { " · \($0.usedPercent)% used" } ?? ""),
            color: memoryStatus.color
        ))
        if let memorySnapshot {
            overviewMenu.addItem(makeInfoItem(String(
                format: "%.1f/%d GB used (%d%% free)",
                memorySnapshot.usedGB, memorySnapshot.totalGB, memorySnapshot.freePercent
            )))
        }
        if let issue = memory.issue {
            overviewMenu.addItem(makeInfoItem(issue, color: .systemOrange))
        }
        overviewMenu.addItem(.separator())
        let thermalDetails = NSMenuItem(title: "Thermal Details", action: nil, keyEquivalent: "")
        thermalDetails.submenu = thermalMenu
        overviewMenu.addItem(thermalDetails)
        let memoryDetails = NSMenuItem(title: "Memory Details", action: nil, keyEquivalent: "")
        memoryDetails.submenu = memoryMenu
        overviewMenu.addItem(memoryDetails)
        overviewMenu.addItem(.separator())
        overviewMenu.addItem(makeMenuItem(
            "Refresh Now",
            action: #selector(refreshAll),
            target: self
        ))
    }

    private func buildMemoryMenu() {
        guard let snapshot = memory.snapshot else {
            memoryMenu.addItem(makeInfoItem("Memory: Unavailable", color: .systemOrange))
            memoryMenu.addItem(makeInfoItem(memory.issue ?? "Waiting for a memory sample."))
            return
        }
        let pressure = snapshot.pressure.displayName
        let color = snapshot.pressure.color
        memoryMenu.addItem(makeInfoItem(
            "Memory Pressure: \(pressure)",
            font: NSFont.menuFont(ofSize: 14),
            color: color
        ))
        if let issue = memory.issue {
            memoryMenu.addItem(makeInfoItem(issue, color: .systemOrange))
        }
        memoryMenu.addItem(makeInfoItem(
            String(
                format: "%.1f/%d GB used (%d%% free)",
                Double(snapshot.totalGB) * Double(snapshot.usedPercent) / 100,
                snapshot.totalGB,
                snapshot.freePercent
            ),
            color: .tertiaryLabelColor
        ))

        if snapshot.pressure == .elevated {
            memoryMenu.addItem(makeInfoItem(
                "Memory pressure elevated — close unused apps",
                color: .tertiaryLabelColor
            ))
        } else if snapshot.pressure == .critical {
            memoryMenu.addItem(makeInfoItem(
                "Close heavy apps to free memory and reduce swap",
                color: .tertiaryLabelColor
            ))
        }

        memoryMenu.addItem(NSMenuItem.separator())
        memoryMenu.addItem(makeInfoItem("Breakdown", font: NSFont.menuFont(ofSize: 12)))
        memoryMenu.addItem(makeMonoItem(
            String(format: "  App Memory:   %.1f GB", snapshot.activeGB),
            color: NSColor(red: 0.29, green: 0.56, blue: 0.85, alpha: 1)
        ))
        memoryMenu.addItem(makeMonoItem(
            String(format: "  Wired (OS):   %.1f GB", snapshot.wiredGB),
            color: NSColor(red: 0.91, green: 0.33, blue: 0.24, alpha: 1)
        ))
        memoryMenu.addItem(makeMonoItem(
            String(format: "  Compressed:   %.1f GB", snapshot.compressedGB),
            color: NSColor(red: 0.96, green: 0.65, blue: 0.14, alpha: 1)
        ))
        memoryMenu.addItem(makeMonoItem(
            String(format: "  Inactive:     %.1f GB", snapshot.inactiveGB),
            color: .tertiaryLabelColor
        ))
        memoryMenu.addItem(makeMonoItem(
            String(format: "  Available:    %.1f GB", snapshot.availableGB),
            color: NSColor(red: 0.49, green: 0.83, blue: 0.13, alpha: 1)
        ))
        memoryMenu.addItem(makeMonoItem(
            String(format: "  Swap Used:    %.1f GB", Double(snapshot.swapUsedMB) / 1024),
            color: NSColor(red: 0.74, green: 0.06, blue: 0.88, alpha: 1)
        ))

        memoryMenu.addItem(NSMenuItem.separator())
        memoryMenu.addItem(makeInfoItem("Top Processes", font: NSFont.menuFont(ofSize: 12)))
        addProcessList(to: memoryMenu, kind: .memory)
        memoryMenu.addItem(NSMenuItem.separator())
        let graphItem = NSMenuItem()
        graphItem.view = MemoryHistoryGraphView(history: memory.history)
        memoryMenu.addItem(graphItem)
        memoryMenu.addItem(NSMenuItem.separator())
        memoryMenu.addItem(makeMenuItem(
            "Open Activity Monitor",
            action: #selector(openActivityMonitor),
            target: self
        ))
    }

    private func buildThermalMenu() {
        let snapshot = thermal.snapshot
        thermalMenu.addItem(makeInfoItem(
            "Thermal: \(snapshot.pressure.displayName)",
            font: NSFont.menuFont(ofSize: 14),
            color: snapshot.stateColor
        ))
        if let issue = snapshot.issue {
            thermalMenu.addItem(makeInfoItem(issue, color: .systemOrange))
        }
        if snapshot.pressure.isThrottling {
            thermalMenu.addItem(makeInfoItem("Your Mac is being throttled", color: .systemOrange))
        }
        thermalMenu.addItem(.separator())
        for (name, value) in [
            ("CPU Max", snapshot.cpuMax),
            ("CPU Avg", snapshot.cpuAvg),
            ("GPU Max", snapshot.gpuMax),
            ("Battery", snapshot.batteryTemp)
        ] {
            thermalMenu.addItem(makeMonoItem(
                "\(name): \(formatTemperature(value))",
                size: 12,
                color: .labelColor
            ))
        }
        if let fanItem = makeFanMenuItem(for: snapshot.fanState) {
            thermalMenu.addItem(fanItem)
        }
        if thermal.history.count >= 2 {
            thermalMenu.addItem(.separator())
            let now = Date()
            let graph = ThermalGraphView(
                history: thermal.history,
                now: now
            )
            let graphItem = NSMenuItem()
            graphItem.view = graph
            thermalMenu.addItem(graphItem)
            let summary = thermal.historySummary(at: now)
            let breakdown = ThermalBreakdownView(
                timeInEachState: summary.timeInEachState,
                totalDuration: summary.totalDuration
            )
            let breakdownItem = NSMenuItem()
            breakdownItem.view = breakdown
            thermalMenu.addItem(breakdownItem)
        }
        thermalMenu.addItem(NSMenuItem.separator())
        thermalMenu.addItem(makeInfoItem(
            "Top CPU Processes",
            font: NSFont.menuFont(ofSize: 12)
        ))
        addProcessList(to: thermalMenu, kind: .cpu)
        thermalMenu.addItem(NSMenuItem.separator())
        thermalMenu.addItem(makeInfoItem(
            "Sensors: \(snapshot.sensorCount)",
            color: .tertiaryLabelColor
        ))
        thermalMenu.addItem(makeMenuItem(
            "Refresh Now",
            action: #selector(refreshThermal),
            target: self
        ))
    }

    private func addApplicationActions(to menu: NSMenu) {
        menu.addItem(.separator())
        menu.addItem(makeAboutItem(applicationName: "Glance Monitor"))
        menu.addItem(makeMenuItem(
            "Quit Glance Monitor",
            action: #selector(quit),
            target: self
        ))
    }

    private func addProcessList(to menu: NSMenu, kind: ProcessListKind) {
        let placeholder = makeInfoItem("Loading processes…")
        menu.addItem(placeholder)
        let identifier = ObjectIdentifier(menu)
        processListTasks[identifier]?.cancel()
        processListTasks[identifier] = Task { @MainActor [weak self, weak menu, weak placeholder] in
            do {
                let labels = try await kind.load()
                try Task.checkCancellation()
                guard let self, let menu, let placeholder,
                      self.openMenus.contains(identifier) else { return }
                let index = menu.index(of: placeholder)
                guard index >= 0 else { return }
                menu.removeItem(placeholder)
                for (offset, label) in labels.enumerated() {
                    let row = makeMonoItem(label)
                    row.tag = Self.processRowTag
                    menu.insertItem(row, at: index + offset)
                }
                AppLog.processes.debug("Loaded \(labels.count, privacy: .public) process rows")
            } catch is CancellationError {
                // Closing or rebuilding the menu intentionally cancels its request.
            } catch {
                guard let self, let placeholder, menu != nil,
                      self.openMenus.contains(identifier) else { return }
                AppLog.processes.error("Process list failed: \(error.localizedDescription, privacy: .public)")
                placeholder.attributedTitle = makeInfoItem(
                    "Could not load processes. Reopen to retry.",
                    color: .systemOrange
                ).attributedTitle
            }
        }
    }

    @objc private func refreshThermal() {
        thermal.poll()
        updateStatusItem()
    }

    @objc private func refreshAll() {
        thermal.poll()
        memory.poll()
        updateStatusItem()
    }

    @objc private func openActivityMonitor() {
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"),
            configuration: .init(),
            completionHandler: nil
        )
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    #if DEBUG
        private func runLifecycleSmokeTest() async throws {
            try await DebugLifecycleHarness.waitUntil { self.statusItem.button?.window != nil }
            let button = try DebugLifecycleHarness.value(statusItem.button, "Smoke status button is unavailable")
            memory.poll()
            thermal.poll()
            DebugLifecycleHarness.note("Monitor native overview")
            try await DebugLifecycleHarness.track(overviewMenu, relativeTo: button) {
                self.openMenus.contains(ObjectIdentifier(self.overviewMenu))
            }
            try await DebugLifecycleHarness.waitUntil { self.openMenus.isEmpty }
            for _ in 0..<2 {
                for menu in [thermalMenu, memoryMenu] {
                    DebugLifecycleHarness.note(menu === thermalMenu ? "Monitor thermal view lifecycle" : "Monitor memory view lifecycle")
                    menuWillOpen(menu)
                    for view in menu.items.compactMap(\.view) {
                        let bitmap = try DebugLifecycleHarness.value(
                            view.bitmapImageRepForCachingDisplay(in: view.bounds),
                            "Could not render a detail view into its local bitmap"
                        )
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                    }
                    try await DebugLifecycleHarness.waitUntil {
                        menu.items.filter { $0.tag == Self.processRowTag }.count == 5
                    }
                    try DebugLifecycleHarness.require(menu.items.contains {
                        ($0.view as? ThermalGraphView)?.renderedForSmokeTest == true ||
                            ($0.view as? MemoryHistoryGraphView)?.renderedForSmokeTest == true
                    }, "A detail graph did not draw")
                    menuDidClose(menu)
                    try await DebugLifecycleHarness.waitUntil {
                        !self.openMenus.contains(ObjectIdentifier(menu)) &&
                            menu.items.allSatisfy { $0.view == nil }
                    }
                }
            }
            try DebugLifecycleHarness.require(processListTasks.isEmpty, "A menu request survived tracking teardown")
            applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }
    #endif
}

@main
@MainActor
struct GlanceMonitorApp {
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        guard let instanceLock = claimPrimaryApplicationInstance() else { return }
        let delegate: MonitorAppDelegate
        #if DEBUG
            if DebugLifecycleHarness.isRequested {
                delegate = MonitorAppDelegate(
                    memory: MemoryMonitor {
                        MemorySnapshot(usedPercent: 25, activeGB: 4, totalGB: 16, freePercent: 75, pressure: .normal)
                    },
                    thermal: ThermalMonitor {
                        ThermalSnapshot(
                            pressure: .nominal, cpuMax: 55, cpuAvg: 50, gpuMax: 45,
                            batteryTemp: 30, sensorCount: 4,
                            fanState: .available(FanSpeed(rpm: 2_000, percentage: 20))
                        )
                    }
                )
            } else {
                delegate = MonitorAppDelegate()
            }
        #else
            delegate = MonitorAppDelegate()
        #endif
        application.delegate = delegate
        withExtendedLifetime((delegate, instanceLock)) {
            application.run()
        }
    }
}
