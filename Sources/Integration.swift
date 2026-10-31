// System integration toggled from the welcome window: default app for Office documents
// and the sync helper registered as a login item.

import AppKit
import ServiceManagement
import UniformTypeIdentifiers

let officeExtensions = ["docx", "doc", "pptx", "ppt", "xlsx", "xls"]

enum Integration {
    static var officeTypes: [UTType] { officeExtensions.compactMap { UTType(filenameExtension: $0) } }

    /// Word / PowerPoint / Excel for Mac for a file extension, if installed.
    static func desktopApp(forExtension ext: String) -> URL? {
        let bundleIDs = ["doc": "com.microsoft.Word", "ppt": "com.microsoft.Powerpoint", "xls": "com.microsoft.Excel"]
        guard let id = bundleIDs[String(ext.lowercased().prefix(3))] else { return nil }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
    }

    // MARK: Default app

    static var isDefaultApp: Bool {
        let me = Bundle.main.bundleURL.resolvingSymlinksInPath()
        return officeTypes.allSatisfy { NSWorkspace.shared.urlForApplication(toOpen: $0)?.resolvingSymlinksInPath() == me }
    }

    /// enabled: this app opens Office documents. Disabled: hand them back to the Office desktop apps.
    static func setDefaultApp(_ enabled: Bool) async {
        for ext in officeExtensions {
            guard let type = UTType(filenameExtension: ext),
                  let app = enabled ? Bundle.main.bundleURL : desktopApp(forExtension: ext)
            else { continue }
            do {
                try await NSWorkspace.shared.setDefaultApplication(at: app, toOpen: type)
            } catch {
                log("Could not change default app for .\(ext): \(error.localizedDescription)")
            }
        }
    }

    // MARK: Sync helper

    static let syncService = SMAppService.agent(plistName: "io.github.chdominguez.OpenInOfficeWeb.Sync.plist")

    static var syncStatus: SMAppService.Status { syncService.status }

    static func setSync(_ enabled: Bool) throws {
        if enabled {
            try syncService.register()
        } else {
            try syncService.unregister()
        }
    }
}
