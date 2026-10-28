import AppKit
import OSLog
import SwiftUI

@MainActor
final class AddClockPopover: NSObject, NSPopoverDelegate {
    private let worldClock: WorldClockMonitor
    private let onAdded: () -> Void
    private let popover = NSPopover()
    private var clockWasAdded = false

    var hasContent: Bool { popover.contentViewController != nil }

    init(worldClock: WorldClockMonitor, onAdded: @escaping () -> Void) {
        self.worldClock = worldClock
        self.onAdded = onAdded
        super.init()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
    }

    func showNear(_ statusItem: NSStatusItem) {
        guard let button = statusItem.button, button.window != nil else {
            Logger(subsystem: "com.local.glance.time", category: "menus")
                .error("Cannot open city search because the status button has no window")
            return
        }
        prepareContent()
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func prepareContent() {
        clockWasAdded = false
        let controller = NSHostingController(rootView: AddClockView(
            worldClock: worldClock,
            onAdded: { [weak self] in
                self?.clockWasAdded = true
                self?.dismiss()
            },
            onCancel: { [weak self] in self?.dismiss() }
        ))
        controller.sizingOptions = [.intrinsicContentSize]
        popover.contentViewController = controller
        popover.contentSize = controller.view.fittingSize
    }

    func dismiss() {
        if popover.isShown {
            popover.close()
        } else {
            popover.contentViewController = nil
        }
    }

    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
        Logger(subsystem: "com.local.glance.time", category: "menus")
            .debug("City search closed and content released")
        if clockWasAdded {
            clockWasAdded = false
            onAdded()
        }
    }
}

private struct AddClockView: View {
    let worldClock: WorldClockMonitor
    let onAdded: () -> Void
    let onCancel: () -> Void
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add World Clock").font(.headline)
            TextField("Search city or timezone", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredTimezones.prefix(40), id: \.id) { timezone in
                        Button {
                            worldClock.addClock(label: timezone.city, timezoneID: timezone.id)
                            onAdded()
                        } label: {
                            HStack {
                                Text(timezone.country.isEmpty
                                    ? timezone.city : "\(timezone.city), \(timezone.country)")
                                Spacer()
                                Text(timezone.id).font(.caption2).foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    }
                }
            }
            .frame(width: 330, height: 230)
            if filteredTimezones.isEmpty {
                Text(searchText.isEmpty ? "Type a city name to search." : "No matching timezone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
            }
        }
        .padding(14)
        .onAppear { searchFocused = true }
    }

    private var filteredTimezones: [(id: String, city: String, country: String)] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }
        return WorldClockMonitor.allTimezones.filter {
            $0.city.lowercased().contains(query) || $0.id.lowercased().contains(query)
                || $0.country.lowercased().contains(query)
        }
    }
}
