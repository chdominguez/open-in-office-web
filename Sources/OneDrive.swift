import Foundation

/// Folder inside OneDrive where documents from outside OneDrive are copied.
let tempFolderName = "Open in Office Web"
let cleanupAge: TimeInterval = 7 * 24 * 3600

struct OneDrive {
    let root: URL
    /// e.g. https://contoso-my.sharepoint.com/personal/jane_contoso_com
    let webBase: URL

    var tempFolder: URL { root.appendingPathComponent(tempFolderName, isDirectory: true) }

    /// Finds the OneDrive for Business folder in ~/Library/CloudStorage and reads the
    /// SharePoint URL from the .url shortcut OneDrive keeps in its root.
    static func detect() -> OneDrive? {
        let fm = FileManager.default
        let cloud = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/CloudStorage")
        let dirs = (try? fm.contentsOfDirectory(at: cloud, includingPropertiesForKeys: nil)) ?? []
        for dir in dirs {
            let name = dir.lastPathComponent
            guard name.hasPrefix("OneDrive-"), !name.hasPrefix("OneDrive-SharedLibraries") else { continue }
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension.lowercased() == "url" {
                guard let text = try? String(contentsOf: file, encoding: .utf8),
                      let range = text.range(of: #"https://[^/\s]+/personal/[^/\s]+"#, options: .regularExpression),
                      let base = URL(string: String(text[range]))
                else { continue }
                return OneDrive(root: dir.resolvingSymlinksInPath(), webBase: base)
            }
        }
        return nil
    }

    func relativePath(of file: URL) -> String? {
        let rootPath = root.path + "/"
        let path = file.resolvingSymlinksInPath().path
        guard path.hasPrefix(rootPath) else { return nil }
        return String(path.dropFirst(rootPath.count))
    }

    func webURL(for file: URL) -> URL? {
        guard let rel = relativePath(of: file) else { return nil }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#&+;=")
        // macOS paths are NFD; SharePoint expects NFC.
        let encoded = rel.precomposedStringWithCanonicalMapping
            .split(separator: "/")
            .compactMap { $0.addingPercentEncoding(withAllowedCharacters: allowed) }
            .joined(separator: "/")
        // "/:w:/r/<path>" links (the kind OneDrive generates) open in Office for the web;
        // a plain file URL would download the document instead.
        let kinds = ["doc": "w", "ppt": "p", "xls": "x"]
        guard let kind = kinds[String(file.pathExtension.lowercased().prefix(3))],
              let host = webBase.host else { return nil }
        return URL(string: "https://\(host)/:\(kind):/r\(webBase.path)/Documents/\(encoded)?csf=1&web=1")
    }

    /// Deletes (to the OneDrive recycle bin) temporary copies untouched for a week,
    /// except those with web edits that haven't reached the original yet.
    func cleanupTempFolder() {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: tempFolder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let links = SyncLinks.load()
        for item in items {
            let modified = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantFuture
            guard Date().timeIntervalSince(modified) > cleanupAge else { continue }
            if let link = links.first(where: { $0.tempPath == item.path }), sha256(of: item) != link.lastSyncedHash {
                continue
            }
            try? fm.removeItem(at: item)
            SyncLinks.update { $0.removeAll { $0.tempPath == item.path } }
        }
    }
}

// MARK: - Sync state (File Provider)

struct SyncState {
    var uploaded = false
    var uploading = false
    var downloaded = false
    var error: Error?
}

func syncState(of file: URL) -> SyncState {
    var url = file
    url.removeAllCachedResourceValues()
    let keys: Set<URLResourceKey> = [.ubiquitousItemIsUploadedKey, .ubiquitousItemIsUploadingKey,
                                     .ubiquitousItemUploadingErrorKey, .ubiquitousItemDownloadingStatusKey]
    guard let values = try? url.resourceValues(forKeys: keys) else { return SyncState() }
    return SyncState(uploaded: values.ubiquitousItemIsUploaded ?? false,
                     uploading: values.ubiquitousItemIsUploading ?? false,
                     downloaded: values.ubiquitousItemDownloadingStatus == .current,
                     error: values.ubiquitousItemUploadingError)
}
