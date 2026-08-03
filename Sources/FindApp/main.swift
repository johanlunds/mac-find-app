import AppKit
import SwiftUI

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

/// Renders the settings view offscreen for design review:
///   FindApp --render-settings out.png [welcome]
@MainActor
func renderSettingsPreview(to path: String, welcome: Bool) {
    let store = CatalogStore()
    let generator = CatalogGenerator()
    let view = NSHostingView(rootView:
        SettingsView(store: store, generator: generator,
                     engine: SearchEngine(catalog: store.catalog),
                     showWelcome: welcome))
    view.frame = NSRect(x: 0, y: 0, width: 760, height: 540)
    // List is NSTableView-backed and only populates inside a window with a
    // few runloop turns.
    let window = NSWindow(contentRect: view.frame, styleMask: [.titled],
                          backing: .buffered, defer: false)
    window.contentView = view
    window.orderBack(nil)
    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    view.layoutSubtreeIfNeeded()
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
    view.cacheDisplay(in: view.bounds, to: rep)
    try! rep.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: path))
    print("wrote \(path) (\(store.rows.count) rows, \(store.missingRows.count) missing)")
    exit(0)
}

/// Runs the real generation pipeline for the missing apps (or a named file
/// key) and exits — verifies CLI discovery, the claude run, parsing, merge,
/// save and backup:
///   FindApp --selftest-generate [fileKey] [custom instructions]
@MainActor
func runGenerationSelfTest(fileKey: String?, instructions: String?,
                           store: CatalogStore, generator: CatalogGenerator) {
    let targets: [CatalogRow]
    if let fileKey {
        guard let row = store.rows.first(where: { $0.id == fileKey }) else {
            print("FAIL: no installed app with file key \(fileKey)"); exit(1)
        }
        targets = [row]
    } else {
        targets = store.missingRows
    }
    guard !targets.isEmpty else { print("nothing to generate"); exit(0) }
    print("generating \(targets.count): \(targets.map(\.id).joined(separator: ", "))")
    if let instructions { print("instructions: \(instructions)") }

    generator.start(targets: targets, store: store, instructions: instructions)
    var last = ""
    Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
        Task { @MainActor in
            let state = generator.state
            let desc = "\(state)"
            if desc != last { print(desc); last = desc }
            switch state {
            case .finished(let added):
                for t in targets {
                    if let entry = store.catalog.apps.first(where: { $0.file == t.id }) {
                        print("→ \(entry.name): \(entry.description)")
                        print("  keywords: \(entry.keywords.joined(separator: ", "))")
                    }
                }
                exit(added == targets.count ? 0 : 1)
            case .failed(let message):
                print("FAIL: \(message)"); exit(1)
            default: break
            }
        }
    }
}

/// Reproduces the ⌘, scenario: with the panel focused, opening Settings must
/// hide only the panel — not the settings window or the whole app.
@MainActor
func runWindowSelfTest(controller: PanelController) {
    controller.show()
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    SettingsWindowController.shared.show()
    RunLoop.current.run(until: Date().addingTimeInterval(0.5))

    let panelHidden = !controller.panel.isVisible
    let settingsVisible = SettingsWindowController.shared.isVisible
    let appVisible = !NSApp.isHidden
    print("panelHidden=\(panelHidden) settingsVisible=\(settingsVisible) appVisible=\(appVisible)")

    // The settings window must enforce a minimum content size (via the
    // hosting view's .minSize sizing option).
    let minSize = NSApp.windows.first { $0.title == "Find App Settings" }?
        .contentMinSize ?? .zero
    print("settings contentMinSize=\(minSize)")
    let minOK = minSize.width >= 560 && minSize.height >= 380

    // Closing the settings window must bring the search panel back.
    SettingsWindowController.shared.close()
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    let panelBack = controller.panel.isVisible && !SettingsWindowController.shared.isVisible
    print("panelBackAfterClose=\(panelBack)")

    // ⌘W closes the settings window (the search panel ignores it by design).
    SettingsWindowController.shared.show()
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    let settingsWindow = NSApp.windows.first { $0.title == "Find App Settings" }!
    let event = NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
        windowNumber: settingsWindow.windowNumber, context: nil, characters: "w",
        charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13)!
    _ = NSApp.mainMenu!.performKeyEquivalent(with: event)
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    let settingsClosed = !SettingsWindowController.shared.isVisible
    print("cmdW closes settings=\(settingsClosed)")

    let ok = panelHidden && settingsVisible && appVisible && minOK && panelBack
        && settingsClosed
    print(ok ? "PASS" : "FAIL")
    exit(ok ? 0 : 1)
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
    var store: CatalogStore!
    var generator: CatalogGenerator!
    var previewArgs: (path: String, query: String)?
    var selfTest = false
    /// nil = off; "" = all missing; otherwise a single file key.
    var generateSelfTest: String?
    var generateInstructions: String?
    var windowSelfTest = false

    var settingsPreview: (path: String, welcome: Bool)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if selfTest { runKeyEquivalentSelfTest() }
        if let p = previewArgs {
            renderPreview(to: p.path, query: p.query)
        }
        if let s = settingsPreview {
            renderSettingsPreview(to: s.path, welcome: s.welcome)
        }
        store = CatalogStore()
        generator = CatalogGenerator()
        SettingsWindowController.shared.store = store
        SettingsWindowController.shared.generator = generator
        if let g = generateSelfTest {
            runGenerationSelfTest(fileKey: g.isEmpty ? nil : g,
                                  instructions: generateInstructions,
                                  store: store, generator: generator)
            return
        }

        let engine = SearchEngine(catalog: store.catalog)
        SettingsWindowController.shared.engine = engine
        controller = PanelController(engine: engine)
        // Closing Settings (including Skip for Now) hands over to the panel.
        SettingsWindowController.shared.onClose = { [weak self] in
            self?.controller.show()
        }
        if windowSelfTest {
            runWindowSelfTest(controller: controller)
            return
        }

        // Reload the search index whenever in-app generation updates the catalog.
        NotificationCenter.default.addObserver(
            forName: .catalogDidChange, object: nil, queue: .main
        ) { [weak self] note in
            guard let catalog = note.object as? Catalog else { return }
            Task { @MainActor in
                engine.reload(catalog: catalog)
                self?.controller.model.requery()
            }
        }

        if store.isFirstRun {
            SettingsWindowController.shared.show(welcome: true)
        } else {
            controller.show()
        }
    }

    /// Quitting mid-run would otherwise leave the batch CLI processes running
    /// in the background, still consuming the user's Claude usage.
    func applicationWillTerminate(_ notification: Notification) {
        generator?.cancel()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        if !SettingsWindowController.shared.isVisible {
            controller.show()
        }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if !controller.panel.isVisible && !SettingsWindowController.shared.isVisible {
            controller.show()
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
// Top-level main.swift code runs on the main thread but isn't statically
// MainActor-isolated; assumeIsolated bridges that for the menu build.
MainActor.assumeIsolated { NSApplication.shared.mainMenu = buildMainMenu() }
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
if args.count >= 3, args[1] == "--render-settings" {
    delegate.settingsPreview = (path: args[2], welcome: args.contains("welcome"))
}
if args.contains("--selftest-keys") { delegate.selfTest = true }
if args.contains("--selftest-windows") { delegate.windowSelfTest = true }
if let i = args.firstIndex(of: "--selftest-generate") {
    delegate.generateSelfTest = args.count > i + 1 ? args[i + 1] : ""
    delegate.generateInstructions = args.count > i + 2 ? args[i + 2] : nil
}
app.delegate = delegate
app.run()
