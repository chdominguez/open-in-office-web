// Open in Office Web
// Opens Word, PowerPoint and Excel documents in Microsoft 365 for the web.
// Documents outside OneDrive are copied to a OneDrive folder first; the app waits until
// macOS (File Provider) reports the upload as finished and then opens the web URL.
// With `--agent` (the sync helper login item) it keeps those originals in sync with their copies.

import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let args = CommandLine.arguments
    if args.contains("--agent") {
        let agent = SyncAgent()
        app.delegate = agent
        app.setActivationPolicy(.prohibited)
        app.run()
    } else if let i = args.firstIndex(of: "--render-screenshots"), i + 1 < args.count {
        app.setActivationPolicy(.accessory)
        Screenshots.render(to: URL(fileURLWithPath: args[i + 1]))
    } else {
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
