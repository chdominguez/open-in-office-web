import AppKit
import UniformTypeIdentifiers

let uploadTimeout: TimeInterval = 180

enum UploadResult { case uploaded, failed(String), cancelled }

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let ui = ProgressPanel()
    let oneDrive = OneDrive.detect()
    var welcome: WelcomeWindow?
    var queue: [URL] = []
    var running = false
    var cancelled = false
    var receivedFiles = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        ui.onCancel = { [weak self] in self?.cancelled = true }
        if let oneDrive {
            DispatchQueue.global(qos: .utility).async { oneDrive.cleanupTempFolder() }
        }
        // Launched without documents (first run, Launchpad, Dock): show the welcome window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in
            if !receivedFiles { showWelcome() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !running && welcome == nil { showWelcome() }
        return true
    }

    func showWelcome() {
        let window = WelcomeWindow(oneDrive: oneDrive)
        window.onOpenDocuments = { [weak self] urls in self?.application(NSApp, open: urls) }
        window.onClose = { [weak self] in
            self?.welcome = nil
            if self?.running == false { NSApp.terminate(nil) }
        }
        welcome = window
        window.show()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        receivedFiles = true
        queue.append(contentsOf: urls)
        if !running {
            running = true
            Task { await runQueue() }
        }
        welcome?.close()
        welcome = nil
    }

    func runQueue() async {
        while !queue.isEmpty {
            await process(queue.removeFirst())
        }
        running = false
        ui.hide()
        NSApp.terminate(nil)
    }

    func process(_ file: URL) async {
        cancelled = false
        ui.show(file: file)
        ui.update(L("Preparing…"), 0.05)

        guard let oneDrive else {
            fail(file, L("OneDrive for Business was not found in ~/Library/CloudStorage. Install OneDrive and sign in with your work or school account."))
            return
        }

        var target = file
        var wrote = false
        if oneDrive.relativePath(of: file) == nil {
            ui.update(L("Copying to OneDrive › %@…", tempFolderName), 0.15)
            do {
                (target, wrote) = try copyToTemp(file, oneDrive: oneDrive)
            } catch {
                fail(file, L("Couldn't copy the file to OneDrive: %@", error.localizedDescription))
                return
            }
        }

        switch await waitForUpload(target, justCopied: wrote) {
        case .cancelled:
            return
        case .failed(let message):
            fail(file, message)
            return
        case .uploaded:
            break
        }

        guard let web = oneDrive.webURL(for: target) else {
            fail(file, L("Couldn't build the web address for this file."))
            return
        }
        ui.update(L("Opening in Office for the web…"), 1)
        NSWorkspace.shared.open(web)
        try? await Task.sleep(nanoseconds: 700_000_000)
    }

    /// Returns the copy in OneDrive and whether new content was written to it.
    /// An original that already has a linked copy reuses it (refreshed if the original changed).
    func copyToTemp(_ file: URL, oneDrive: OneDrive) throws -> (URL, wrote: Bool) {
        let fm = FileManager.default
        if let link = SyncLinks.existing(for: file) {
            let temp = URL(fileURLWithPath: link.tempPath)
            let origHash = sha256(of: file)
            // Only overwrite the copy when the original is the newer one; if the copy has
            // web edits, the sync agent handles them (or the conflict).
            guard origHash != link.lastSyncedHash, sha256(of: temp) == link.lastSyncedHash else { return (temp, false) }
            try Data(contentsOf: file).write(to: temp)
            if let updated = SyncLinks.makeLink(original: file, temp: temp) {
                SyncLinks.update { links in
                    links.removeAll { $0.tempPath == temp.path }
                    links.append(updated)
                }
            }
            return (temp, true)
        }

        try fm.createDirectory(at: oneDrive.tempFolder, withIntermediateDirectories: true)
        let dest = uniqueURL(oneDrive.tempFolder, file.deletingPathExtension().lastPathComponent, file.pathExtension)
        try fm.copyItem(at: file, to: dest)
        if let link = SyncLinks.makeLink(original: file, temp: dest) {
            SyncLinks.update { $0.append(link) }
        }
        return (dest, true)
    }

    /// Waits until File Provider reports the file as uploaded.
    /// Shows upload progress if the system publishes it; otherwise an animated bar.
    func waitForUpload(_ file: URL, justCopied: Bool) async -> UploadResult {
        var uploadFraction: Double?
        let token = Progress.addSubscriber(forFileURL: file) { progress in
            let observation = progress.observe(\.fractionCompleted) { p, _ in
                let fraction = p.fractionCompleted
                DispatchQueue.main.async { uploadFraction = fraction }
            }
            return { observation.invalidate() }
        }
        defer { Progress.removeSubscriber(token) }

        var start = Date()
        while true {
            if cancelled { return .cancelled }
            let state = syncState(of: file)
            let elapsed = Date().timeIntervalSince(start)

            if let error = state.error {
                return .failed(L("OneDrive couldn't upload the file: %@", error.localizedDescription))
            }
            // Right after copying, give File Provider a moment to register the file
            // before trusting "uploaded".
            if state.uploaded && (!justCopied || elapsed > 2) {
                ui.update(L("Synced ✓"), 0.95)
                // Short grace period so SharePoint serves the new path.
                if justCopied { try? await Task.sleep(nanoseconds: 1_500_000_000) }
                return .uploaded
            }

            if let fraction = uploadFraction {
                ui.update(L("Uploading to OneDrive… %d%%", Int(fraction * 100)), 0.2 + fraction * 0.75)
            } else if state.uploading {
                ui.update(L("Uploading to OneDrive…"), nil)
            } else {
                ui.update(L("Waiting for OneDrive to sync…"), nil)
            }

            if elapsed > uploadTimeout {
                let alert = NSAlert()
                alert.messageText = L("OneDrive hasn't finished uploading the file")
                alert.informativeText = L("It's been more than %d minutes. Check that OneDrive is running and online.", Int(uploadTimeout / 60))
                alert.addButton(withTitle: L("Keep Waiting"))
                alert.addButton(withTitle: L("Open in Desktop App"))
                alert.addButton(withTitle: L("Cancel"))
                switch alert.runModal() {
                case .alertFirstButtonReturn: start = Date()
                case .alertSecondButtonReturn: openInDesktop(file); return .cancelled
                default: return .cancelled
                }
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    func fail(_ file: URL, _ message: String) {
        ui.hide()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("Couldn't open %@ in Office for the web", file.lastPathComponent)
        alert.informativeText = message
        alert.addButton(withTitle: L("Open in Desktop App"))
        alert.addButton(withTitle: L("Close"))
        if alert.runModal() == .alertFirstButtonReturn { openInDesktop(file) }
    }

    func openInDesktop(_ file: URL) {
        guard let app = Integration.desktopApp(forExtension: file.pathExtension) else {
            NSWorkspace.shared.activateFileViewerSelecting([file])
            return
        }
        NSWorkspace.shared.open([file], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
}
