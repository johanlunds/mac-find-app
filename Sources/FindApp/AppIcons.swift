import AppKit

enum AppIcons {
    /// Icon for an app bundle. Symlinks are resolved first so linked apps
    /// (e.g. /Applications/Safari.app is a cryptex symlink on macOS 26)
    /// show their real icon instead of one with an alias badge arrow.
    static func icon(for url: URL) -> NSImage {
        NSWorkspace.shared.icon(forFile: url.resolvingSymlinksInPath().path)
    }
}
