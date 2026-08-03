import AppKit

/// AppKit delivers the standard editing shortcuts (⌘A, ⌘C, ⌘V, ⌘X, ⌘Z) via
/// main-menu key-equivalent matching, not via the text system's key bindings —
/// so without an Edit menu those keystrokes do nothing. (⌘⌫ works regardless
/// because `deleteToBeginningOfLine:` *is* in the standard key-binding table.)
@MainActor
func buildMainMenu() -> NSMenu {
    let main = NSMenu()

    let appItem = NSMenuItem()
    main.addItem(appItem)
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "About Find App",
                    action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                    keyEquivalent: "")
    appMenu.addItem(.separator())
    let settings = NSMenuItem(title: "Settings…",
                              action: #selector(SettingsWindowController.openSettings(_:)),
                              keyEquivalent: ",")
    settings.target = SettingsWindowController.shared
    appMenu.addItem(settings)
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "Hide Find App",
                    action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "Quit Find App",
                    action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appItem.submenu = appMenu

    let editItem = NSMenuItem()
    main.addItem(editItem)
    let edit = NSMenu(title: "Edit")
    edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
    redo.keyEquivalentModifierMask = [.command, .shift]
    edit.addItem(.separator())
    edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
    edit.addItem(withTitle: "Select All",
                 action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editItem.submenu = edit

    // ⌘W closes the settings window. AppKit disables performClose: for windows
    // without a close button, so the borderless search panel ignores it — Esc
    // dismisses that one.
    let windowItem = NSMenuItem()
    main.addItem(windowItem)
    let windowMenu = NSMenu(title: "Window")
    windowMenu.addItem(withTitle: "Close",
                       action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    windowMenu.addItem(withTitle: "Minimize",
                       action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
    windowItem.submenu = windowMenu

    return main
}
