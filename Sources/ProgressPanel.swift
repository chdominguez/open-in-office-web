import AppKit

@MainActor
final class ProgressPanel: NSObject {
    let panel: NSPanel
    let fileLabel = NSTextField(labelWithString: "")
    let statusLabel = NSTextField(labelWithString: "")
    let bar = NSProgressIndicator()
    let icon = NSImageView()
    var onCancel: (() -> Void)?

    override init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 120),
                        styleMask: [.titled, .closable],
                        backing: .buffered, defer: false)
        super.init()
        panel.title = L("Open in Office Web")
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false

        fileLabel.font = .boldSystemFont(ofSize: 13)
        fileLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        bar.style = .bar
        bar.minValue = 0
        bar.maxValue = 1
        bar.isIndeterminate = false
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 48).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 48).isActive = true

        let cancel = NSButton(title: L("Cancel"), target: self, action: #selector(cancelPressed))
        cancel.keyEquivalent = "\u{1b}"

        let text = NSStackView(views: [fileLabel, statusLabel, bar])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 6
        bar.widthAnchor.constraint(equalTo: text.widthAnchor).isActive = true
        // 440 window - 2×20 margins - 48 icon - 14 spacing
        text.widthAnchor.constraint(equalToConstant: 338).isActive = true

        let row = NSStackView(views: [icon, text])
        row.alignment = .centerY
        row.spacing = 14

        let buttons = NSStackView(views: [NSView(), cancel])
        let root = NSStackView(views: [row, buttons])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 16, right: 20)
        for view in root.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -40).isActive = true
        }
        root.widthAnchor.constraint(equalToConstant: 440).isActive = true

        panel.contentView = root
    }

    func show(file: URL) {
        show(name: file.lastPathComponent, icon: NSWorkspace.shared.icon(forFile: file.path))
    }

    func show(name: String, icon image: NSImage) {
        fileLabel.stringValue = name
        icon.image = image
        panel.setContentSize(panel.contentView!.fittingSize)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// value == nil -> indeterminate (animated) bar
    func update(_ status: String, _ value: Double?) {
        statusLabel.stringValue = status
        if let value {
            bar.stopAnimation(nil)
            bar.isIndeterminate = false
            bar.doubleValue = value
        } else if !bar.isIndeterminate {
            bar.isIndeterminate = true
            bar.startAnimation(nil)
        }
    }

    func hide() { panel.orderOut(nil) }

    @objc func cancelPressed() { onCancel?() }
}
