import CryptoKit
import Foundation

/// Link between an original outside OneDrive and its copy in the OneDrive temp folder.
struct SyncLink: Codable {
    var tempPath: String
    /// Bookmark to the original: follows the file even if it is moved or renamed.
    var originalBookmark: Data
    /// Last known path of the original (for the log and for matching).
    var originalPath: String
    /// Content hash the last time the original and the copy were identical.
    var lastSyncedHash: String
    var tempModDate: Date?
    var originalModDate: Date?
}

func sha256(of url: URL) -> String? {
    guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func modificationDate(of url: URL) -> Date? {
    var url = url
    url.removeAllCachedResourceValues()
    return (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
}

func log(_ message: String) {
    let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/OpenInOfficeWeb.log")
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
    if let handle = try? FileHandle(forWritingTo: logURL) {
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        try? handle.close()
    } else {
        try? Data(line.utf8).write(to: logURL)
    }
}

/// Store at ~/Library/Application Support/OpenInOfficeWeb/links.json.
/// The app and the sync agent both modify it, so every write goes through `update`,
/// which holds a file lock while it reads, modifies and saves.
enum SyncLinks {
    static let folder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/OpenInOfficeWeb", isDirectory: true)
    static let storeURL = folder.appendingPathComponent("links.json")
    static let lockURL = folder.appendingPathComponent("links.lock")

    static func load() -> [SyncLink] {
        guard let data = try? Data(contentsOf: storeURL) else { return [] }
        return (try? JSONDecoder().decode([SyncLink].self, from: data)) ?? []
    }

    static func update(_ change: (inout [SyncLink]) -> Void) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return }
        flock(fd, LOCK_EX)
        defer { flock(fd, LOCK_UN); close(fd) }
        var links = load()
        change(&links)
        if let data = try? JSONEncoder().encode(links) {
            try? data.write(to: storeURL, options: .atomic)
        }
    }

    /// Resolves the original's bookmark. nil if it no longer exists or is in the Trash.
    static func resolveOriginal(_ link: SyncLink) -> URL? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: link.originalBookmark, options: [.withoutUI], bookmarkDataIsStale: &stale),
              FileManager.default.fileExists(atPath: url.path),
              !url.path.contains("/.Trash/")
        else { return nil }
        return url
    }

    static func makeLink(original: URL, temp: URL) -> SyncLink? {
        guard let bookmark = try? original.bookmarkData(), let hash = sha256(of: original) else { return nil }
        return SyncLink(tempPath: temp.path, originalBookmark: bookmark, originalPath: original.resolvingSymlinksInPath().path,
                        lastSyncedHash: hash, tempModDate: modificationDate(of: temp), originalModDate: modificationDate(of: original))
    }

    /// Existing link for this original whose copy still exists.
    static func existing(for original: URL) -> SyncLink? {
        let path = original.resolvingSymlinksInPath().path
        return load().first { link in
            FileManager.default.fileExists(atPath: link.tempPath)
                && (resolveOriginal(link)?.resolvingSymlinksInPath().path ?? link.originalPath) == path
        }
    }
}
