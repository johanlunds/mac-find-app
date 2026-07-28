import Foundation
import NaturalLanguage

struct SearchResult: Identifiable, Equatable {
    let id: String          // file name, e.g. "Thaw.app"
    let name: String
    let description: String
    let url: URL
    let score: Double

    static func == (lhs: SearchResult, rhs: SearchResult) -> Bool { lhs.id == rhs.id }
}

/// Combines classic keyword/prefix matching with on-device semantic matching
/// (Apple NaturalLanguage word + sentence embeddings). Rescans /Applications on
/// every search so removed apps never appear and new apps still match by name.
final class SearchEngine {
    static let applicationsDir = URL(fileURLWithPath: "/Applications")
    static let userApplicationsDir = FileManager.default
        .homeDirectoryForCurrentUser.appendingPathComponent("Applications")
    /// Apple's built-in apps live here (Finder shows Utilities merged into
    /// /Applications, but on disk it's under /System).
    static let systemRoots = [
        URL(fileURLWithPath: "/System/Applications"),
        URL(fileURLWithPath: "/System/Applications/Utilities"),
    ]

    private struct IndexedApp {
        let file: String
        let name: String
        let nameLower: String
        let description: String
        let keywords: [String]          // lowercased
        let descTokens: Set<String>
        var semanticTokens: [String]    // tokens used for word-embedding similarity
        var descVector: [Double]?
    }

    private var index: [String: IndexedApp] = [:]   // keyed by file name
    private let wordEmbedding = NLEmbedding.wordEmbedding(for: .english)
    private let sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: .english)
    private var tokenVectors: [String: [Double]?] = [:]  // cache, nil = not in vocabulary

    private static let stopwords: Set<String> = [
        "a", "an", "the", "app", "apps", "application", "mac", "macos", "osx",
        "for", "to", "of", "my", "that", "with", "i", "on", "in"
    ]

    init(catalog: Catalog) {
        for entry in catalog.apps {
            add(entry: entry)
        }
    }

    private func add(entry: CatalogEntry) {
        let descTokens = Set(Self.tokenize(entry.description))
        let keywords = entry.keywords.map { $0.lowercased() }
        var semantic = Set<String>()
        for kw in keywords { semantic.formUnion(Self.tokenize(kw)) }
        semantic.formUnion(Self.tokenize(entry.name))
        semantic.formUnion(descTokens)
        semantic.subtract(Self.stopwords)
        var app = IndexedApp(
            file: entry.file,
            name: entry.name,
            nameLower: entry.name.lowercased(),
            description: entry.description,
            keywords: keywords,
            descTokens: descTokens,
            semanticTokens: Array(semantic),
            descVector: nil
        )
        if let se = sentenceEmbedding, !entry.description.isEmpty {
            app.descVector = se.vector(for: entry.description.lowercased())
        }
        index[entry.file] = app
    }

    /// Minimal entry for an installed app that isn't in the catalog yet.
    private func addUncataloged(file: String) {
        let name = ((file as NSString).lastPathComponent as NSString).deletingPathExtension
        add(entry: CatalogEntry(file: file, name: name, bundleId: nil,
                                description: "", keywords: []))
    }

    static func tokenize(_ s: String) -> [String] {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 || ($0.count == 1 && Int($0) != nil) }
    }

    private func vector(for token: String) -> [Double]? {
        if let cached = tokenVectors[token] { return cached }
        let v = wordEmbedding?.vector(for: token)
        tokenVectors[token] = v
        return v
    }

    private static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        let denom = (na * nb).squareRoot()
        return denom > 0 ? dot / denom : 0
    }

    /// Currently installed apps, keyed the same way as the catalog's `file`
    /// field: bare/relative under /Applications ("Thaw.app", "ISTP/ISTP.app"),
    /// "~/Applications/..." for user apps, or an absolute path for system apps
    /// ("/System/Applications/Notes.app"). Scans /Applications and
    /// ~/Applications one level deep, plus the Apple system app folders.
    private func installedApps() -> [String: URL] {
        var found: [String: URL] = [:]

        scanTwoLevels(Self.applicationsDir, into: &found) { $0 }
        scanTwoLevels(Self.userApplicationsDir, into: &found) { "~/Applications/\($0)" }

        for root in Self.systemRoots {
            let sub = (try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            for s in sub where s.pathExtension == "app" {
                found[s.path] = s
            }
        }
        return found
    }

    /// Adds .app bundles directly in `root` and in its immediate subfolders.
    /// `key` maps a path relative to `root` to the catalog's `file` value.
    private func scanTwoLevels(_ root: URL, into found: inout [String: URL],
                               key: (String) -> String) {
        let fm = FileManager.default
        let top = (try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])) ?? []
        for url in top {
            if url.pathExtension == "app" {
                found[key(url.lastPathComponent)] = url
            } else if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                let sub = (try? fm.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                for s in sub where s.pathExtension == "app" {
                    found[key("\(url.lastPathComponent)/\(s.lastPathComponent)")] = s
                }
            }
        }
    }

    func search(_ rawQuery: String, limit: Int = 8) -> [SearchResult] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }

        let installed = installedApps()
        for file in installed.keys where index[file] == nil {
            addUncataloged(file: file)
        }

        let qTokens = Self.tokenize(query)
        let meaningfulTokens = qTokens.filter { !Self.stopwords.contains($0) }
        let qTokenVectors: [(String, [Double])] = meaningfulTokens.compactMap { t in
            vector(for: t).map { (t, $0) }
        }
        let queryVector: [Double]? =
            meaningfulTokens.count >= 2 ? sentenceEmbedding?.vector(for: query) : nil

        var results: [SearchResult] = []
        for (file, url) in installed {
            guard let app = index[file] else { continue }
            if let r = score(app: app, url: url, query: query, qTokens: qTokens,
                             qTokenVectors: qTokenVectors, queryVector: queryVector) {
                results.append(r)
            }
        }
        return Array(results.sorted { $0.score > $1.score }.prefix(limit))
    }

    private func score(app: IndexedApp, url: URL, query: String, qTokens: [String],
                       qTokenVectors: [(String, [Double])],
                       queryVector: [Double]?) -> SearchResult? {
        var total = 0.0

        // Whole-query name matching (classic launcher behavior).
        if app.nameLower == query { total += 120 }
        else if app.nameLower.hasPrefix(query) { total += 95 }
        else if app.nameLower.contains(query) { total += 65 }
        else if isSubsequence(query, of: app.nameLower) && query.count >= 3 { total += 30 }

        var unmatched = 0
        for token in qTokens {
            let generic = Self.stopwords.contains(token)
            var best = 0.0

            if app.nameLower.contains(token) { best = 45 }
            else if app.keywords.contains(where: { $0 == token }) { best = 45 }
            else if app.keywords.contains(where: { $0.hasPrefix(token) || $0.contains(" \(token)") }) { best = 34 }
            else if app.descTokens.contains(token) { best = 22 }
            else if app.descTokens.contains(where: { $0.hasPrefix(token) }) { best = 12 }

            // Semantic fallback: closest word-embedding neighbor among the app's terms.
            if best < 30, !generic,
               let qv = qTokenVectors.first(where: { $0.0 == token })?.1 {
                var bestSim = 0.0
                for appToken in app.semanticTokens {
                    if let av = vector(for: appToken) {
                        bestSim = max(bestSim, Self.cosine(qv, av))
                    }
                }
                if bestSim > 0.45 {
                    best = max(best, bestSim * 38)
                }
            }

            if generic {
                total += min(best, 10)  // generic words barely count, never disqualify
            } else {
                total += best
                if best < 10 { unmatched += 1 }
            }
        }

        // Whole-query semantic similarity against the app description.
        var sentenceSim = 0.0
        if let qv = queryVector, let dv = app.descVector {
            sentenceSim = Self.cosine(qv, dv)
            if sentenceSim > 0.5 {
                total += (sentenceSim - 0.5) * 130
            }
        }

        // Every meaningful token must land somewhere, unless the query as a
        // whole is semantically close to the description.
        if unmatched > 0 && sentenceSim < 0.6 { return nil }
        guard total >= 22 else { return nil }

        return SearchResult(
            id: app.file,
            name: app.name,
            description: app.description,
            url: url,
            score: total
        )
    }

    private func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var it = haystack.makeIterator()
        outer: for ch in needle {
            while let h = it.next() {
                if h == ch { continue outer }
            }
            return false
        }
        return true
    }
}
