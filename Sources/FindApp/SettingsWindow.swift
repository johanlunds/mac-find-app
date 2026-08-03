import AppKit
import SwiftUI

/// Manages the single settings window (the app doesn't use the SwiftUI app
/// lifecycle, so this is a plain NSWindow + hosting view).
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    // Set once by the app delegate at launch.
    var store: CatalogStore!
    var generator: CatalogGenerator!

    func show(welcome: Bool = false) {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            w.title = "Find App Settings"
            w.minSize = NSSize(width: 560, height: 380)
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        let hosting = NSHostingView(
            rootView: SettingsView(store: store, generator: generator, showWelcome: welcome))
        // Don't let SwiftUI's ideal size shrink the window; keep our frame.
        hosting.sizingOptions = []
        window!.contentView = hosting
        NSApp.activate(ignoringOtherApps: true)
        window!.makeKeyAndOrderFront(nil)
    }

    @objc func openSettings(_ sender: Any?) {
        show()
    }

    var isVisible: Bool { window?.isVisible ?? false }
}
