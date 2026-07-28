import AppKit

// CLI mode for testing matching quality: FindApp --search "some query"
let args = CommandLine.arguments
if args.count >= 3, args[1] == "--search" {
    let engine = SearchEngine(catalog: CatalogLoader.load())
    let query = args[2...].joined(separator: " ")
    let results = engine.search(query)
    if results.isEmpty {
        print("(no results)")
    }
    for r in results {
        let desc = r.description.isEmpty ? "" : " — \(r.description)"
        print(String(format: "%6.1f  %@%@", r.score, r.name, desc))
    }
    exit(0)
}

/// Renders the panel offscreen to a PNG for design review:
///   FindApp --render-preview out.png "query"
/// (The blurred background renders as transparent offscreen, so it's
/// composited onto a neutral backdrop.)
@MainActor
func renderPreview(to path: String, query: String) {
    let controller = PanelController(engine: SearchEngine(catalog: CatalogLoader.load()))
    controller.model.query = query
    controller.panel.setContentSize(NSSize(width: PanelController.panelWidth,
                                           height: controller.previewHeight))
    guard let view = controller.panel.contentView else { exit(1) }
    view.layoutSubtreeIfNeeded()
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
    view.cacheDisplay(in: view.bounds, to: rep)

    let canvas = NSImage(size: view.bounds.size)
    canvas.lockFocus()
    NSColor(calibratedWhite: 0.22, alpha: 1).setFill()
    view.bounds.fill()
    rep.draw(in: view.bounds)
    canvas.unlockFocus()
    let out = NSBitmapImageRep(data: canvas.tiffRepresentation!)!
    try! out.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: path))
    print("wrote \(path) (\(controller.model.results.count) results)")
    exit(0)
}

/// Verifies that the Edit-menu key equivalents reach the search field's editor.
@MainActor
func runKeyEquivalentSelfTest() {
    let controller = PanelController(engine: SearchEngine(catalog: CatalogLoader.load()))
    controller.show()
    controller.model.query = "menubar utility"
    // Let SwiftUI push the query into the NSTextField before testing.
    RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    guard let field = FocusTarget.shared.field else { print("FAIL: no field"); exit(1) }
    controller.panel.makeFirstResponder(field)
    guard !field.stringValue.isEmpty else { print("FAIL: field empty"); exit(1) }

    func event(_ chars: String) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                         timestamp: 0, windowNumber: controller.panel.windowNumber,
                         context: nil, characters: chars,
                         charactersIgnoringModifiers: chars, isARepeat: false, keyCode: 0)!
    }

    let handled = NSApp.mainMenu!.performKeyEquivalent(with: event("a"))
    let editor = controller.panel.fieldEditor(false, for: field) as? NSTextView
    let selected = editor.map { NSStringFromRange($0.selectedRange()) } ?? "nil"
    print("cmd+A: handled=\(handled) selectedRange=\(selected) text=\"\(field.stringValue)\"")
    var ok = handled && editor?.selectedRange().length == field.stringValue.count

    func sendEscape() {
        let esc = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                   timestamp: 0, windowNumber: controller.panel.windowNumber,
                                   context: nil, characters: "\u{1B}",
                                   charactersIgnoringModifiers: "\u{1B}",
                                   isARepeat: false, keyCode: 53)!
        controller.panel.sendEvent(esc)
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
    }

    // Esc #1: query is non-empty, so it should clear the field, not hide.
    sendEscape()
    let clearedText = editor?.string ?? field.stringValue
    print("esc (non-empty): query=\"\(controller.model.query)\" field=\"\(clearedText)\" "
          + "visible=\(controller.panel.isVisible)")
    ok = ok && controller.model.query.isEmpty && clearedText.isEmpty
        && controller.panel.isVisible

    // Esc #2: field is now empty, so it should hide the panel.
    sendEscape()
    print("esc (empty): visible=\(controller.panel.isVisible)")
    ok = ok && !controller.panel.isVisible

    print(ok ? "PASS" : "FAIL")
    exit(ok ? 0 : 1)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: PanelController!
    var previewArgs: (path: String, query: String)?
    var selfTest = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if selfTest { runKeyEquivalentSelfTest() }
        if let p = previewArgs {
            renderPreview(to: p.path, query: p.query)
        }
        let engine = SearchEngine(catalog: CatalogLoader.load())
        controller = PanelController(engine: engine)
        controller.show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        controller.show()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if !controller.panel.isVisible {
            controller.show()
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
app.mainMenu = buildMainMenu()
// Explicitly set the Dock tile icon; the Dock's LaunchServices-based icon
// lookup can serve a stale/generic icon after the bundle's icon changes.
if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
   let icon = NSImage(contentsOf: iconURL) {
    app.applicationIconImage = icon
}
let delegate = AppDelegate()
if args.count >= 4, args[1] == "--render-preview" {
    delegate.previewArgs = (path: args[2], query: args[3])
}
if args.contains("--selftest-keys") { delegate.selfTest = true }
app.delegate = delegate
app.run()
