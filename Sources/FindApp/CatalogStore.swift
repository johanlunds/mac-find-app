import Foundation

extension Notification.Name {
    static let catalogDidChange = Notification.Name("FindAppCatalogDidChange")
}

/// One row in the settings pane: an installed app joined with its catalog
/// entry (if any).
struct CatalogRow: Identifiable {
    let id: String          // file key
    let name: String
    let url: URL
    let bundleId: String?
    let description: String
    let keywords: [String]
    var isMissing: Bool { description.isEmpty }
}

/// Owns the live catalog: joins it with the installed apps for display,
/// merges generated entries, and persists to Application Support (keeping the
/// 5 newest timestamped backups of the previous file).
@MainActor
final class CatalogStore: ObservableObject {
    @Published private(set) var catalog: Catalog
    @Published private(set) var rows: [CatalogRow] = []

    private static let hasSeenWelcomeKey = "hasSeenWelcome"

    init() {
        catalog = CatalogLoader.load()
        refreshRows()
    }

    var isFirstRun: Bool {
        !FileManager.default.fileExists(atPath: CatalogLoader.appSupportURL.path)
            && !UserDefaults.standard.bool(forKey: Self.hasSeenWelcomeKey)
    }

    func markWelcomeSeen() {
        UserDefaults.standard.set(true, forKey: Self.hasSeenWelcomeKey)
    }

    var describedCount: Int { rows.filter { !$0.isMissing }.count }
    var missingRows: [CatalogRow] { rows.filter(\.isMissing) }

    /// Re-joins the catalog with what's installed right now.
    func refreshRows() {
        let installed = AppScanner.installedApps()
        let entries = Dictionary(uniqueKeysWithValues: catalog.apps.map { ($0.file, $0) })
        rows = installed
            .map { file, url in
                let entry = entries[file]
                return CatalogRow(
                    id: file,
                    name: entry?.name ?? AppScanner.displayName(forFileKey: file),
                    url: url,
                    bundleId: entry?.bundleId ?? AppScanner.bundleId(at: url),
                    description: entry?.description ?? "",
                    keywords: entry?.keywords ?? []
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Inserts or replaces generated entries, prunes entries for apps that are
    /// no longer installed, saves, and notifies the search engine.
    func merge(entries newEntries: [CatalogEntry]) {
        guard !newEntries.isEmpty else { return }
        let installed = AppScanner.installedApps()
        var byFile = Dictionary(uniqueKeysWithValues: catalog.apps.map { ($0.file, $0) })
        for entry in newEntries where installed[entry.file] != nil {
            byFile[entry.file] = entry
        }
        byFile = byFile.filter { installed[$0.key] != nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        catalog = Catalog(
            generated: formatter.string(from: Date()),
            apps: byFile.values.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        )
        refreshRows()
        do {
            try CatalogLoader.save(catalog)
        } catch {
            FileHandle.standardError.write(
                Data("FindApp: failed to save catalog: \(error)\n".utf8))
        }
        NotificationCenter.default.post(name: .catalogDidChange, object: catalog)
    }
}
