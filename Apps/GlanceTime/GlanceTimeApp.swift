import AppKit
import GlanceSupport

@MainActor
final class TimeAppDelegate: NSObject, NSApplicationDelegate {
    private let worldClock = WorldClockMonitor()
    private var statusItem: NSStatusItem!
    private var timeMenu: TimeAndDateMenu?
    private var addClockPopover: AddClockPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let timeMenu = TimeAndDateMenu(worldClock: worldClock) { [weak self] in
            self?.showAddClock()
        }
        timeMenu.menu.addItem(.separator())
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
}

@main
@MainActor
struct GlanceTimeApp {
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = TimeAppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
