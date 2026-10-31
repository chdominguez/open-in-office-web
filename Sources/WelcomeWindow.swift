// Window shown when the app is launched without documents (first run, Launchpad, Dock):
// OneDrive status, default-app and sync toggles, and a button to open a document.

import AppKit
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
final class WelcomeWindow: NSObject, NSWindowDelegate {
    let window: NSWindow
    let oneDrive: OneDrive?
    var onOpenDocuments: (([URL]) -> Void)?
    var onClose: (() -> Void)?

    let defaultBox = NSButton(checkboxWithTitle: L("Open Word, PowerPoint and Excel files with this app"), target: nil, action: nil)
    let syncBox = NSButton(checkboxWithTitle: L("Sync web edits back to files outside OneDrive"), target: nil, action: nil)
    let syncNote = WelcomeWindow.note("")

    init(oneDrive: OneDrive?) {
        self.oneDrive = oneDrive
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 100),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = L("Open in Office Web")
        window.isReleasedWhenClosed = false
        window.delegate = self

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.widthAnchor.constraint(equalToConstant: 72).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 72).isActive = true
        let title = NSTextField(labelWithString: L("Open in Office Web"))
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        let subtitle = Self.note(L("Double-click a Word, PowerPoint or Excel file and it opens in Microsoft 365 for the web, even if it isn't in OneDrive yet."), size: 12)
        let heading = NSStackView(views: [title, subtitle])
        heading.orientation = .vertical
        heading.alignment = .leading
        heading.spacing = 4
        let header = NSStackView(views: [icon, heading])
        header.alignment = .centerY
        header.spacing = 16

        defaultBox.target = self
        defaultBox.action = #selector(toggleDefault)
        syncBox.target = self
        syncBox.action = #selector(toggleSync)

        let open = NSButton(title: L("Open a Document…"), target: self, action: #selector(openDocument))
        let done = NSButton(title: L("Done"), target: self, action: #selector(closeWindow))
        done.keyEquivalent = "\r"
        let buttons = NSStackView(views: [open, NSView(), done])
        buttons.distribution = .fill

        let content = NSStackView(views: [
            header,
            Self.separator(),
            oneDriveStatus(),
            Self.section(defaultBox, Self.note(L("Prefer the desktop app for one file? Right-click it and choose Open With."))),
            Self.section(syncBox, syncNote),
            Self.separator(),
            buttons,
        ])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 16
        content.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        for view in content.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -48).isActive = true
        }
        content.widthAnchor.constraint(equalToConstant: 500).isActive = true
        window.contentView = content
        refresh()
    }

    func show() {
        window.layoutIfNeeded()
        window.setContentSize(window.contentView!.fittingSize)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window.delegate = nil
        window.close()
    }

    func windowWillClose(_ notification: Notification) { onClose?() }

    func refresh() {
        defaultBox.state = Integration.isDefaultApp ? .on : .off
        let status = Integration.syncStatus
        syncBox.state = status == .enabled || status == .requiresApproval ? .on : .off
        syncNote.stringValue = status == .requiresApproval
            ? L("Almost there: allow “Open in Office Web Sync” in System Settings › General › Login Items.")
            : L("Files from your Desktop, Downloads and other folders are copied to OneDrive › %@. Edits made online are copied back to the original.", tempFolderName)
    }

    func oneDriveStatus() -> NSView {
        let ok = oneDrive != nil
        let symbol = NSImageView(image: NSImage(systemSymbolName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                                                accessibilityDescription: nil)!)
        symbol.contentTintColor = ok ? .systemGreen : .systemOrange
        let text = ok
            ? L("Connected to OneDrive for Business (%@)", oneDrive!.webBase.host ?? "")
            : L("OneDrive for Business not found. Install OneDrive and sign in with your work or school account.")
        let label = Self.note(text, size: 12, color: .labelColor)
        let row = NSStackView(views: [symbol, label])
        row.alignment = .firstBaseline
        row.spacing = 8
        return row
    }

    @objc func toggleDefault() {
        let enable = defaultBox.state == .on
        Task {
            await Integration.setDefaultApp(enable)
            refresh()
        }
    }

    @objc func toggleSync() {
        do {
            try Integration.setSync(syncBox.state == .on)
            if Integration.syncStatus == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
        refresh()
    }

    @objc func openDocument() {
        let panel = NSOpenPanel()
        panel.message = L("Choose the documents to open in Office for the web")
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = Integration.officeTypes
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            self?.onOpenDocuments?(panel.urls)
        }
    }

    @objc func closeWindow() { window.close() }

    // MARK: Layout helpers

    static func note(_ text: String, size: CGFloat = 11, color: NSColor = .secondaryLabelColor) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: size)
        label.textColor = color
        label.isSelectable = false
        return label
    }

    static func section(_ checkbox: NSButton, _ note: NSTextField) -> NSView {
        // Indent the note under the checkbox title.
        let indented = NSStackView(views: [note])
        indented.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 0)
        let stack = NSStackView(views: [checkbox, indented])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        indented.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    static func separator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        return box
    }
}
