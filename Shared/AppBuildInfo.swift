import AppKit
import Foundation

public struct AppBuildInfo: Sendable {
    public let version: String
    public let build: String
    public let source: String
    public let builtAt: String

    public init(bundle: Bundle = .main) throws {
        try self.init(info: bundle.infoDictionary ?? [:])
    }

    public init(info: [String: Any]) throws {
        func value(_ key: String) throws -> String {
            guard let value = info[key] as? String, !value.isEmpty else {
                throw BuildInfoError.missingField(key)
            }
            return value
        }
        version = try value("CFBundleShortVersionString")
        build = try value("CFBundleVersion")
        source = try value("GlanceSourceRevision")
        builtAt = try value("GlanceBuildDate")
    }

    public var diagnosticText: String {
        "Version \(version) (\(build))\nSource \(source)\nBuilt \(builtAt)"
    }
}

public enum BuildInfoError: Error, LocalizedError {
    case missingField(String)
    public var errorDescription: String? {
        switch self {
        case let .missingField(key): "Build metadata is missing \(key)."
        }
    }
}

@MainActor
public func makeAboutItem(applicationName: String) -> NSMenuItem {
    let item = NSMenuItem(title: "About \(applicationName)", action: nil, keyEquivalent: "")
    let menu = NSMenu()
    do {
        let info = try AppBuildInfo()
        menu.addItem(makeInfoItem("Version \(info.version) (\(info.build))"))
        menu.addItem(makeInfoItem("Source: \(info.source)"))
        menu.addItem(makeInfoItem("Built: \(info.builtAt)"))
    } catch {
        AppLog.lifecycle.error("Cannot read build metadata: \(error.localizedDescription)")
        menu.addItem(makeInfoItem("Build information unavailable", color: .systemOrange))
    }
    item.submenu = menu
    return item
}
