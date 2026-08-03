import Foundation

/// Scans the app folders and produces the canonical file keys shared by the
/// catalog, the search engine and the settings pane: bare/relative under
/// /Applications ("Thaw.app", "ISTP/ISTP.app"), "~/Applications/..." for user
/// apps, or an absolute path for Apple system apps
/// ("/System/Applications/Notes.app").
enum AppScanner {
    static let applicationsDir = URL(fileURLWithPath: "/Applications")
    static let userApplicationsDir = FileManager.default
        .homeDirectoryForCurrentUser.appendingPathComponent("Applications")
    /// Apple's built-in apps live here (Finder shows Utilities merged into
    /// /Applications, but on disk it's under /System).
    static let systemRoots = [
        URL(fileURLWithPath: "/System/Applications"),
        URL(fileURLWithPath: "/System/Applications/Utilities"),
    ]

    /// Currently installed apps, keyed by catalog file key. Scans /Applications
    /// and ~/Applications one level deep, plus the Apple system app folders.
    static func installedApps() -> [String: URL] {
        var found: [String: URL] = [:]

        scanTwoLevels(applicationsDir, into: &found) { $0 }
        scanTwoLevels(userApplicationsDir, into: &found) { "~/Applications/\($0)" }

        for root in systemRoots {
            for s in contents(of: root) where s.pathExtension == "app" {
                found[s.path] = s
            }
        }
        return found
    }

    /// Directory listing that keeps hidden-flagged entries (on macOS 26,
    /// /Applications/Safari.app is a hidden cryptex symlink that
    /// .skipsHiddenFiles would drop) but still ignores dotfiles.
    private static func contents(of root: URL,
                                 keys: [URLResourceKey]? = nil) -> [URL] {
        let all = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: keys)) ?? []
        return all.filter { !$0.lastPathComponent.hasPrefix(".") }
    }

    /// Adds .app bundles directly in `root` and in its immediate subfolders.
    /// `key` maps a path relative to `root` to the catalog's `file` value.
    private static func scanTwoLevels(_ root: URL, into found: inout [String: URL],
                                      key: (String) -> String) {
        for url in contents(of: root, keys: [.isDirectoryKey]) {
            if url.pathExtension == "app" {
                found[key(url.lastPathComponent)] = url
            } else if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                for s in contents(of: url) where s.pathExtension == "app" {
                    found[key("\(url.lastPathComponent)/\(s.lastPathComponent)")] = s
                }
            }
        }
    }

    /// Display name for a file key (last path component without ".app").
    static func displayName(forFileKey file: String) -> String {
        ((file as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    static func bundleId(at url: URL) -> String? {
        Bundle(url: url)?.bundleIdentifier
    }
}
