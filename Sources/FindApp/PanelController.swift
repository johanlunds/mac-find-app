import AppKit
import SwiftUI

final class SearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class PanelController {
    static let panelWidth: CGFloat = 680
    static let fieldHeight: CGFloat = 60
    static let rowHeight: CGFloat = 52
    static let listPadding: CGFloat = 17  // divider + list padding
    static let footerHeight: CGFloat = 28 // divider + footer bar

    let panel: SearchPanel
    let model: SearchViewModel

    init(engine: SearchEngine) {
        model = SearchViewModel(engine: engine)
        panel = SearchPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.fieldHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        // Not hidesOnDeactivate: activation can bounce right after launch on
        // macOS 14+, which would hide the panel before it was ever seen.
        // Instead, hide when the panel loses key status (click outside).
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }

        let hosting = NSHostingView(rootView: SearchWindowView(model: model))
        hosting.frame = panel.contentRect(forFrameRect: panel.frame)
        panel.contentView = hosting

        model.onResultsChanged = { [weak self] in self?.updateHeight() }
        model.onLaunch = { [weak self] result in
            NSWorkspace.shared.openApplication(
                at: result.url, configuration: NSWorkspace.OpenConfiguration())
            self?.hide()
        }
        model.onDismiss = { [weak self] in self?.hide() }
    }

    func show() {
        model.reset()
        positionPanel()
        activateAndFocus()
        // Activation can be denied or land late (cooperative activation on
        // macOS 14+), so retry a couple of times.
        for delay in [0.05, 0.25] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.panel.isVisible, !self.panel.isKeyWindow else { return }
                self.activateAndFocus()
            }
        }
    }

    private func activateAndFocus() {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        panel.makeFirstResponder(FocusTarget.shared.field)
    }

    func hide() {
        panel.orderOut(nil)
        NSApp.hide(nil)
    }

    /// Exposed for the offscreen preview renderer.
    var previewHeight: CGFloat { desiredHeight }

    private var desiredHeight: CGFloat {
        let rows = CGFloat(min(model.results.count, 8))
        return Self.fieldHeight + Self.footerHeight
            + (rows > 0 ? rows * Self.rowHeight + Self.listPadding : 0)
    }

    /// Keep the top edge fixed (Spotlight-style: expands downward).
    private func updateHeight() {
        var frame = panel.frame
        let top = frame.maxY
        frame.size.height = desiredHeight
        frame.origin.y = top - frame.size.height
        panel.setFrame(frame, display: true)
    }

    /// The screen the user is looking at: the one with the mouse pointer.
    private var activeScreen: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }

    private func positionPanel() {
        guard let screen = activeScreen else { return }
        let visible = screen.visibleFrame
        let x = visible.midX - Self.panelWidth / 2
        // Panel top sits at ~68% of screen height, like Spotlight.
        let top = visible.minY + visible.height * 0.68
        panel.setFrame(
            NSRect(x: x, y: top - desiredHeight, width: Self.panelWidth, height: desiredHeight),
            display: true)
    }
}
