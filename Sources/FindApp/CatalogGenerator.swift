import Foundation

/// Generates catalog entries by spawning the `claude` CLI. The CLI only
/// researches and returns JSON (web search allowed, no file edits) — the app
/// itself merges and saves via CatalogStore.
@MainActor
final class CatalogGenerator: ObservableObject {
    enum State: Equatable {
        case idle
        case running(done: Int, total: Int, current: String)
        case failed(String)
        case finished(added: Int)

        var isRunning: Bool {
            if case .running = self { return true }
            return false
        }
    }

    @Published private(set) var state: State = .idle

    static let batchSize = 8
    private var worker: Task<Void, Never>?
    private var currentProcess: Process?

    // MARK: - CLI discovery (shell-agnostic)

    /// Finds the claude CLI without assuming any particular login shell:
    /// $FINDAPP_CLAUDE override → well-known install paths → POSIX
    /// `/bin/sh -lc 'command -v claude'` as a last resort.
    nonisolated static func findClaudeCLI() -> String? {
        let env = ProcessInfo.processInfo.environment
        if let override = env["FINDAPP_CLAUDE"], !override.isEmpty {
            return FileManager.default.isExecutableFile(atPath: override) ? override : nil
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.claude/local/claude",
        ]
        if let hit = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return hit
        }
        // Ask a plain POSIX shell (works regardless of the user's login shell).
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-lc", "command -v claude"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        guard (try? proc.run()) != nil else { return nil }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0,
              let data = try? pipe.fileHandleForReading.readToEnd(),
              let path = String(data: data, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else { return nil }
        return path
    }

    // MARK: - Generation

    /// `instructions` is optional user-supplied context about the target apps
    /// (for internal or self-made apps the model can't research).
    func start(targets: [CatalogRow], store: CatalogStore, instructions: String? = nil) {
        guard !state.isRunning, !targets.isEmpty else { return }
        state = .running(done: 0, total: targets.count, current: "Locating claude CLI…")

        worker = Task { [weak self, weak store] in
            guard let self else { return }
            guard let cli = await Task.detached(operation: { Self.findClaudeCLI() }).value else {
                self.state = .failed("""
                    Couldn't find the `claude` CLI. Install Claude Code \
                    (https://claude.com/claude-code) and try again.
                    """)
                return
            }

            // Entries are collected across batches and only merged + saved
            // (one timestamped backup) after ALL batches completed regularly —
            // a cancelled or failed run discards its results.
            var collected: [CatalogEntry] = []
            let batches = stride(from: 0, to: targets.count, by: Self.batchSize).map {
                Array(targets[$0..<min($0 + Self.batchSize, targets.count)])
            }
            for batch in batches {
                if Task.isCancelled { break }
                let names = batch.map(\.name).joined(separator: ", ")
                self.state = .running(done: collected.count, total: targets.count,
                                      current: names)
                do {
                    collected += try await self.runBatch(cli: cli, batch: batch,
                                                         instructions: instructions)
                } catch is CancellationError {
                    break
                } catch {
                    self.state = .failed(error.localizedDescription)
                    return
                }
            }
            if Task.isCancelled {
                self.state = .idle
            } else {
                if let store, !collected.isEmpty {
                    store.merge(entries: collected)
                }
                self.state = .finished(added: collected.count)
            }
        }
    }

    func cancel() {
        worker?.cancel()
        currentProcess?.terminate()
        currentProcess = nil
        state = .idle
    }

    // MARK: - One batch

    private func runBatch(cli: String, batch: [CatalogRow],
                          instructions: String? = nil) async throws -> [CatalogEntry] {
        let prompt = Self.prompt(for: batch, instructions: instructions)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: cli)
        proc.arguments = ["-p", prompt, "--output-format", "json",
                          "--effort", "medium",
                          "--safe-mode", "--allowed-tools", "WebSearch"]
        // Neutral cwd so the CLI doesn't pick up any project context.
        proc.currentDirectoryURL = FileManager.default.temporaryDirectory
        let stdout = Pipe()
        proc.standardOutput = stdout
        proc.standardError = FileHandle.nullDevice
        currentProcess = proc

        defer { currentProcess = nil }
        let data: Data = try await Task.detached {
            try proc.run()
            let data = (try? stdout.fileHandleForReading.readToEnd()) ?? Data()
            proc.waitUntilExit()
            return data
        }.value
        try Task.checkCancellation()
        guard proc.terminationStatus == 0 else {
            throw GenerationError("claude CLI exited with status \(proc.terminationStatus)")
        }
        return try Self.parseEntries(from: data)
    }

    nonisolated static func prompt(for batch: [CatalogRow],
                                   instructions: String? = nil) -> String {
        let list = batch.map { row in
            "- file: \"\(row.id)\", name hint: \"\(row.name)\", bundleId: \(row.bundleId ?? "unknown")"
        }.joined(separator: "\n")

        // User-supplied context wins over research: these are typically
        // internal or self-made apps with no public information.
        var userContext = ""
        if let instructions,
           !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            userContext = """
                The user supplied the following instructions about the app(s) below. \
                Treat them as authoritative — more reliable than anything you know or \
                can find online — and follow them when writing the description and \
                keywords.
                <user-instructions>
                \(instructions)
                </user-instructions>
                """
        }

        return """
        You are researching macOS applications for a search index used by a \
        Spotlight-like app finder. For each app listed below, produce a JSON object \
        with exactly these fields:
        - "file": the file key exactly as given
        - "name": display name (no .app suffix)
        - "bundleId": as given, or null if unknown
        - "description": 1-2 sentences describing what the app does
        - "keywords": 8-14 lowercase strings covering its category, purpose and \
        common synonyms (e.g. a menu bar utility should include "menubar", \
        "menu bar app", "utility")

        Use your own knowledge; use web search only for apps you don't recognize \
        (the bundle id is a strong hint). Apple system apps you can describe \
        directly.

        \(userContext)

        Apps:
        \(list)

        Respond with ONLY a JSON array of these objects — no markdown fences, \
        no commentary.
        """
    }

    /// The CLI's --output-format json wraps the answer in an envelope whose
    /// "result" field holds the model's text; the array may also be wrapped in
    /// markdown fences despite instructions.
    nonisolated static func parseEntries(from data: Data) throws -> [CatalogEntry] {
        var text = String(data: data, encoding: .utf8) ?? ""
        if let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let result = envelope["result"] as? String {
            text = result
        }
        guard let start = text.firstIndex(of: "["), let end = text.lastIndex(of: "]"),
              start < end else {
            throw GenerationError("No JSON array found in claude output")
        }
        let json = Data(text[start...end].utf8)
        return try JSONDecoder().decode([CatalogEntry].self, from: json)
    }
}

struct GenerationError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
