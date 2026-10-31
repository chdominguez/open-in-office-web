// `--render-screenshots <dir>`: renders the app's windows off-screen to PNGs (light and dark)
// for the README, so they stay in sync with the real UI.

import AppKit
import UniformTypeIdentifiers

@MainActor
enum Screenshots {
    static func render(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let demo = OneDrive(root: URL(fileURLWithPath: "/tmp"), webBase: URL(string: "https://contoso-my.sharepoint.com/personal/jane_contoso_com")!)
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            NSApp.appearance = NSAppearance(named: appearance)

            let progress = ProgressPanel()
            let docIcon = NSWorkspace.shared.icon(for: UTType(filenameExtension: "docx") ?? .data)
            progress.show(name: "Quarterly Report.docx", icon: docIcon)
            progress.update(L("Uploading to OneDrive… %d%%", 64), 0.2 + 0.64 * 0.75)
            snapshot(progress.panel, to: dir.appendingPathComponent("progress-\(suffix).png"))
            progress.hide()

            let welcome = WelcomeWindow(oneDrive: demo)
            welcome.defaultBox.state = .on
            welcome.syncBox.state = .on
            welcome.show()
            snapshot(welcome.window, to: dir.appendingPathComponent("welcome-\(suffix).png"))
            welcome.close()
        }
    }

    /// Renders the whole window (title bar included) and places it on a transparent
    /// canvas with rounded corners and a soft shadow, like a macOS window screenshot.
    static func snapshot(_ window: NSWindow, to url: URL) {
        window.displayIfNeeded()
        guard let frameView = window.contentView?.superview,
              let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        let windowImage = NSImage(size: frameView.bounds.size)
        windowImage.addRepresentation(rep)

        let scale: CGFloat = 2, margin: CGFloat = 40
        let size = NSSize(width: frameView.bounds.width + margin * 2, height: frameView.bounds.height + margin * 2)
        guard let canvas = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        canvas.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvas)
        let rect = NSRect(x: margin, y: margin, width: frameView.bounds.width, height: frameView.bounds.height)
        let shape = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 24
        shadow.shadowOffset = NSSize(width: 0, height: -8)
        shadow.set()
        NSColor.windowBackgroundColor.setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()

        shape.addClip()
        windowImage.draw(in: rect)
        NSColor.separatorColor.setStroke()
        shape.lineWidth = 1
        shape.stroke()
        NSGraphicsContext.restoreGraphicsState()

        try? canvas.representation(using: .png, properties: [:])?.write(to: url)
    }
}
