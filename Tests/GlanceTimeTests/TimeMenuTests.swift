import Foundation
import Testing
@testable import GlanceTime

@Test @MainActor func timeMenuBuildsContentLazilyAndReleasesItAfterTracking() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer {
        do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) }
    }
    let config = directory.appendingPathComponent("clocks.json")
    try Data("[]".utf8).write(to: config)
    let model = WorldClockMonitor(configURL: config)
    let content = TimeAndDateMenu(worldClock: model)
    #expect(!content.hasContent)
    for _ in 0..<3 {
        content.menuWillOpen(content.menu)
        #expect(content.hasContent)
        #expect(content.menu.items.first?.view?.frame.width == TimeAndDateMenu.width)
        content.menuDidClose(content.menu)
        try await Task.sleep(for: .milliseconds(20))
        #expect(!content.hasContent)
        #expect(content.menu.items.first?.view == nil)
    }
}

@Test @MainActor func cityPickerReleasesHiddenContent() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer {
        do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) }
    }
    let config = directory.appendingPathComponent("clocks.json")
    try Data("[]".utf8).write(to: config)
    let picker = AddClockPopover(worldClock: WorldClockMonitor(configURL: config), onAdded: {})
    #expect(!picker.hasContent)
    picker.prepareContent()
    #expect(picker.hasContent)
    picker.dismiss()
    #expect(!picker.hasContent)
}
