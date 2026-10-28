import AppKit
import GlanceSupport

@MainActor
final class TimeAppDelegate: NSObject, NSApplicationDelegate {
    private let worldClock: WorldClockMonitor
    private var statusItem: NSStatusItem!
    private var timeMenu: TimeAndDateMenu?
    private var addClockPopover: AddClockPopover?

    init(worldClock: WorldClockMonitor = WorldClockMonitor()) {
        self.worldClock = worldClock
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let timeMenu = TimeAndDateMenu(worldClock: worldClock) { [weak self] in
            self?.showAddClock()
        }
        timeMenu.menu.addItem(.separator())
        timeMenu.menu.addItem(makeAboutItem(applicationName: "Glance Time"))
        timeMenu.menu.addItem(makeMenuItem(
            "Quit Glance Time",
            action: #selector(quit),
            target: self
        ))
        self.timeMenu = timeMenu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = makeIcon(
            symbolName: "calendar.badge.clock",
            color: .labelColor,
            size: 16
        )
        statusItem.button?.toolTip = "Glance Time"
        statusItem.menu = timeMenu.menu
        #if DEBUG
            if DebugLifecycleHarness.isRequested {
                DebugLifecycleHarness.run { try await self.runLifecycleSmokeTest() }
            }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        timeMenu?.menu.cancelTracking()
        addClockPopover?.dismiss()
    }

    private func showAddClock() {
        if addClockPopover == nil {
            addClockPopover = AddClockPopover(worldClock: worldClock) { [weak self] in
                Task { @MainActor [weak self] in self?.statusItem.button?.performClick(nil) }
            }
        }
        addClockPopover?.showNear(statusItem)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    #if DEBUG
        private func runLifecycleSmokeTest() async throws {
            try await DebugLifecycleHarness.waitUntil { self.statusItem.button?.window != nil }
            let button = try DebugLifecycleHarness.value(statusItem.button, "Smoke status button is unavailable")
            let timeMenu = try DebugLifecycleHarness.value(timeMenu, "Smoke Time menu is unavailable")
            for _ in 0..<2 {
                try await DebugLifecycleHarness.track(timeMenu.menu, relativeTo: button) {
                    timeMenu.hasContent && (timeMenu.menu.items.first?.view?.frame.height ?? 0) > 100
                }
                try await DebugLifecycleHarness.waitUntil { !timeMenu.hasContent }
                showAddClock()
                try await DebugLifecycleHarness.waitUntil { self.addClockPopover?.shownForSmokeTest == true }
                addClockPopover?.dismiss()
                try await DebugLifecycleHarness.waitUntil { self.addClockPopover?.hasContent == false }
            }
            worldClock.addClock(label: "UTC", timezoneID: "Etc/UTC")
            try DebugLifecycleHarness.require(worldClock.clocks.count == 1, "Fixture clock was not saved")
            worldClock.removeClock(at: 0)
            try DebugLifecycleHarness.require(worldClock.clocks.isEmpty, "Fixture clock was not removed")
            applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }
    #endif
}

@main
@MainActor
struct GlanceTimeApp {
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        guard let instanceLock = claimPrimaryApplicationInstance() else { return }
        let delegate: TimeAppDelegate
        #if DEBUG
            if DebugLifecycleHarness.isRequested {
                do {
                    delegate = TimeAppDelegate(worldClock: WorldClockMonitor(configURL: try DebugLifecycleHarness.clockSettingsURL()))
                } catch {
                    DebugLifecycleHarness.fail(error)
                }
            } else {
                delegate = TimeAppDelegate()
            }
        #else
            delegate = TimeAppDelegate()
        #endif
        application.delegate = delegate
        withExtendedLifetime((delegate, instanceLock)) {
            application.run()
        }
    }
}
