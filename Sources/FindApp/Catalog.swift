import Foundation

struct CatalogEntry: Codable {
    /// Path relative to /Applications (e.g. "Thaw.app", "ISTP/ISTP.app") or an
    /// absolute path for system apps (e.g. "/System/Applications/Notes.app").
    let file: String
    let name: String
    let bundleId: String?
    let description: String
    let keywords: [String]
}

struct Catalog: Codable {
    let generated: String?
    let apps: [CatalogEntry]
}

enum CatalogLoader {
    /// The live, writable catalog location. In-app generation saves here;
    /// the repo's Resources/catalog.json is only a seed.
    static var appSupportURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FindApp/catalog.json")
    }

    /// Saves to Application Support, first backing up the existing file to a
    /// timestamped sibling (catalog.yyyyMMdd-HHmmss-SSS.backup.json). The 5
    /// newest backups are kept.
    static func save(_ catalog: Catalog) throws {
        let url = appSupportURL
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        if fm.fileExists(atPath: url.path) {
            let stamp = DateFormatter()
            stamp.dateFormat = "yyyyMMdd-HHmmss-SSS"
            let backup = dir.appendingPathComponent(
                "catalog.\(stamp.string(from: Date())).backup.json")
            try? fm.removeItem(at: backup)
            try fm.copyItem(at: url, to: backup)
            pruneBackups(in: dir, keeping: 5)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(catalog).write(to: url)
    }

    /// Deletes all but the newest `keeping` backups (the timestamp in the
    /// name makes lexicographic order chronological).
    private static func pruneBackups(in dir: URL, keeping: Int) {
        let fm = FileManager.default
        let backups = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0.hasPrefix("catalog.") && $0.hasSuffix(".backup.json") }
            .sorted(by: >)
        for old in backups.dropFirst(keeping) {
            try? fm.removeItem(at: dir.appendingPathComponent(old))
        }
    }

    /// Search order: $FINDAPP_CATALOG, ~/Library/Application Support/FindApp/catalog.json,
    /// next to the executable / in the .app's Resources, then the repo's
    /// Resources/catalog.json (or a bare catalog.json) in the current directory.
    static func candidatePaths() -> [URL] {
        var paths: [URL] = []
        if let env = ProcessInfo.processInfo.environment["FINDAPP_CATALOG"],
           !env.trimmingCharacters(in: .whitespaces).isEmpty {
            paths.append(URL(fileURLWithPath: env))
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        paths.append(contentsOf: appSupport.map { $0.appendingPathComponent("FindApp/catalog.json") })
        let execDir = Bundle.main.executableURL?.deletingLastPathComponent()
        if let execDir {
            paths.append(execDir.appendingPathComponent("catalog.json"))
            // Inside an .app bundle: Contents/Resources/catalog.json
            paths.append(execDir.deletingLastPathComponent()
                .appendingPathComponent("Resources/catalog.json"))
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        paths.append(cwd.appendingPathComponent("Resources/catalog.json"))
        paths.append(cwd.appendingPathComponent("catalog.json"))
        return paths
    }

    static func load() -> Catalog {
        for url in candidatePaths() {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                let data = try Data(contentsOf: url)
                return try JSONDecoder().decode(Catalog.self, from: data)
            } catch {
                FileHandle.standardError.write(
                    Data("FindApp: failed to parse catalog at \(url.path): \(error)\n".utf8))
            }
        }
        return Catalog(generated: nil, apps: [])
    }
}
