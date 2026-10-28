import AppKit

@MainActor
public func makeIcon(
    symbolName: String,
    color: NSColor,
    size: CGFloat = 18
) -> NSImage {
    let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
    guard let base = NSImage(
        systemSymbolName: symbolName,
        accessibilityDescription: nil
    )?.withSymbolConfiguration(configuration) else {
        return NSImage(size: NSSize(width: size, height: size))
    }

    let image = NSImage(size: base.size, flipped: false) { bounds in
        base.draw(
            in: bounds,
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        color.set()
        bounds.fill(using: .sourceAtop)
        return true
    }
    image.isTemplate = false
    return image
}

@MainActor
public func makeMenuItem(
    _ title: String,
    action: Selector? = nil,
    target: AnyObject? = nil
) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = target
    return item
}

@MainActor
public func makeInfoItem(
    _ title: String,
    font: NSFont? = nil,
    color: NSColor? = nil
) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.attributedTitle = NSAttributedString(
        string: title,
        attributes: [
            .font: font ?? NSFont.menuFont(ofSize: 12),
            .foregroundColor: color ?? NSColor.secondaryLabelColor
        ]
    )
    return item
}

@MainActor
public func makeMonoItem(
    _ title: String,
    size: CGFloat = 11,
    color: NSColor = .secondaryLabelColor
) -> NSMenuItem {
    makeInfoItem(
        title,
        font: NSFont.monospacedSystemFont(ofSize: size, weight: .regular),
        color: color
    )
}
