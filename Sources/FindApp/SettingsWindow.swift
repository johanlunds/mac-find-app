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
    /// Invoked whenever the settings window closes (delegate shows the panel).
    var onClose: (() -> Void)?

    func show(welcome: Bool = false) {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            w.title = "Find App Settings"
            w.isReleasedWhenClosed = false
            w.center()
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: w, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.onClose?() }
            }
            window = w
        }
        let hosting = NSHostingView(
            rootView: SettingsView(store: store, generator: generator, showWelcome: welcome)
                .frame(minWidth: 560, minHeight: 380))
        // SwiftUI owns the window's sizing constraints when an NSHostingView
        // is the content view: .minSize forwards the root view's minimum to
        // the window (a plain NSWindow.minSize is ignored here), while leaving
        // out .preferredContentSize keeps the ideal size from shrinking our
        // 760×540 frame.
        hosting.sizingOptions = .minSize
        window!.contentView = hosting
        NSApp.activate(ignoringOtherApps: true)
        window!.makeKeyAndOrderFront(nil)
    }

    @objc func openSettings(_ sender: Any?) {
        show()
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func close() {
        window?.close()
    }
}
