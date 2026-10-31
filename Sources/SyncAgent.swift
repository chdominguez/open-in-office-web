// Background helper (`--agent`, registered as a login item): keeps originals outside
// OneDrive in sync with their copies in the OneDrive temp folder, in both directions.

import AppKit
import UserNotifications

let pollInterval: TimeInterval = 10
/// Office for the web autosaves every few seconds: only copy once the file has been quiet this long.
let tempQuietTime: TimeInterval = 30
let originalQuietTime: TimeInterval = 10

@MainActor
final class SyncAgent: NSObject, NSApplicationDelegate {
    /// Last modification date seen per path, and since when it hasn't changed.
    var quietSince: [String: (date: Date, since: Date)] = [:]
    var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        log("Sync agent started")
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tick()
    }

    func tick() {
        for link in SyncLinks.load() {
            check(link)
        }
    }

    /// true if `url` has kept the same modification date for at least `time` seconds.
    func isQuiet(_ url: URL, _ date: Date, for time: TimeInterval) -> Bool {
        if let seen = quietSince[url.path], seen.date == date {
            return Date().timeIntervalSince(seen.since) >= time
        }
        quietSince[url.path] = (date, Date())
        return false
    }

    func check(_ link: SyncLink) {
        let temp = URL(fileURLWithPath: link.tempPath)
        guard FileManager.default.fileExists(atPath: temp.path), let original = SyncLinks.resolveOriginal(link) else {
            log("Link removed (original or copy is gone): \(link.originalPath)")
            SyncLinks.update { $0.removeAll { $0.tempPath == link.tempPath } }
            return
        }
        guard let tempMod = modificationDate(of: temp), let origMod = modificationDate(of: original) else { return }

        // Cheap date check first; the hash confirms whether the content really changed.
        var tempChanged = false
        var origChanged = false
        if tempMod != link.tempModDate {
            let state = syncState(of: temp)
            if !state.downloaded {
                try? FileManager.default.startDownloadingUbiquitousItem(at: temp)
                return
            }
            guard isQuiet(temp, tempMod, for: tempQuietTime) else { return }
            tempChanged = sha256(of: temp) != link.lastSyncedHash
        }
        if origMod != link.originalModDate {
            guard isQuiet(original, origMod, for: originalQuietTime) else { return }
            origChanged = sha256(of: original) != link.lastSyncedHash
        }

        do {
            switch (tempChanged, origChanged) {
            case (true, false):
                try replaceContents(of: original, with: temp)
                log("Web → original: \(original.path)")
                notify(L("Changes saved"), L("%@ was updated with the version from Office for the web.", original.lastPathComponent))
            case (false, true):
                try Data(contentsOf: original).write(to: temp)
                log("Original → OneDrive: \(original.path)")
            case (true, true):
                let webCopy = uniqueURL(original.deletingLastPathComponent(),
                                        L("%@ (web version)", original.deletingPathExtension().lastPathComponent), original.pathExtension)
                try FileManager.default.copyItem(at: temp, to: webCopy)
                try Data(contentsOf: original).write(to: temp)
                log("Conflict: web version saved to \(webCopy.path)")
                notify(L("Conflict in %@", original.lastPathComponent),
                       L("The file changed both on this Mac and on the web. The web version was saved as %@.", webCopy.lastPathComponent))
            case (false, false):
                break
            }
        } catch {
            log("Error syncing \(original.path): \(error.localizedDescription)")
            return
        }

        // Record the new state (also when only the date changed, not the content).
        let hash = sha256(of: original) ?? link.lastSyncedHash
        let bookmark = (try? original.bookmarkData()) ?? link.originalBookmark
        let newTempMod = modificationDate(of: temp)
        let newOrigMod = modificationDate(of: original)
        SyncLinks.update { links in
            guard let i = links.firstIndex(where: { $0.tempPath == link.tempPath }) else { return }
            links[i].lastSyncedHash = hash
            links[i].originalBookmark = bookmark
            links[i].originalPath = original.path
            links[i].tempModDate = newTempMod
            links[i].originalModDate = newOrigMod
        }
    }

    /// Replaces the original's contents without leaving it half-written: stage next to it, then swap.
    func replaceContents(of original: URL, with source: URL) throws {
        let staging = original.deletingLastPathComponent()
            .appendingPathComponent(".\(original.lastPathComponent).sync-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: source, to: staging)
        _ = try FileManager.default.replaceItemAt(original, withItemAt: staging)
    }

    func notify(_ title: String, _ body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

func uniqueURL(_ folder: URL, _ base: String, _ ext: String) -> URL {
    var url = folder.appendingPathComponent("\(base).\(ext)")
    var n = 2
    while FileManager.default.fileExists(atPath: url.path) {
        url = folder.appendingPathComponent("\(base) \(n).\(ext)")
        n += 1
    }
    return url
}
