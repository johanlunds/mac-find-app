import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var store: CatalogStore
    @ObservedObject var generator: CatalogGenerator
    @State var showWelcome: Bool
    @State private var filter = ""

    var body: some View {
        if showWelcome {
            WelcomeView(
                onAnalyze: {
                    store.markWelcomeSeen()
                    showWelcome = false
                    generator.start(targets: store.rows, store: store)
                },
                onSkip: {
                    store.markWelcomeSeen()
                    showWelcome = false
                }
            )
        } else {
            catalogPane
        }
    }

    private var filteredRows: [CatalogRow] {
        let f = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !f.isEmpty else { return store.rows }
        return store.rows.filter {
            $0.name.lowercased().contains(f)
                || $0.description.lowercased().contains(f)
                || $0.keywords.contains { $0.contains(f) }
        }
    }

    private var catalogPane: some View {
        VStack(spacing: 0) {
            header
                .padding(16)
            Divider()
            if case .running = generator.state {
                progressBar
                Divider()
            } else {
                statusBanner
            }
            rowList
        }
        .onAppear { store.refreshRows() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("App Catalog")
                    .font(.title3.weight(.semibold))
                Text("\(store.rows.count) apps installed · \(store.describedCount) described · \(store.missingRows.count) missing")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if generator.state.isRunning {
                Button("Cancel") { generator.cancel() }
            } else {
                Button("Generate Missing (\(store.missingRows.count))") {
                    generator.start(targets: store.missingRows, store: store)
                }
                .disabled(store.missingRows.isEmpty)
                Button("Regenerate All") {
                    generator.start(targets: store.rows, store: store)
                }
            }
        }
    }

    @ViewBuilder
    private var progressBar: some View {
        if case let .running(done, total, current) = generator.state {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                HStack(spacing: 6) {
                    // The determinate bar only moves per finished batch, so a
                    // small spinner signals that work is ongoing in between.
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .scaleEffect(0.7)
                    Text("Analyzing \(done)/\(total) — \(current)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    /// Failure/success banner shown where the progress bar sits while running
    /// (above the filter field).
    @ViewBuilder
    private var statusBanner: some View {
        switch generator.state {
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
        case .finished(let added) where added > 0:
            Label("Updated \(added) app\(added == 1 ? "" : "s"). You can now close this window.",
                  systemImage: "checkmark.circle")
                .foregroundStyle(.green)
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
        default:
            EmptyView()
        }
    }

    private var rowList: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter apps…", text: $filter)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Divider()

            List(filteredRows) { row in
                CatalogRowView(row: row) {
                    generator.start(targets: [row], store: store)
                }
                .listRowSeparator(.visible)
            }
            .listStyle(.inset)
        }
    }
}

struct CatalogRowView: View {
    let row: CatalogRow
    let onRegenerate: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: row.url.path))
                .resizable()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.name)
                        .font(.system(size: 13, weight: .semibold))
                    Text(row.id)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if row.isMissing {
                    Text("No description")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.orange.opacity(0.2)))
                        .foregroundStyle(.orange)
                } else if !row.description.isEmpty {
                    Text(row.description)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !row.keywords.isEmpty {
                    KeywordChips(keywords: row.keywords)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .contextMenu {
            Button("Regenerate This App", action: onRegenerate)
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([row.url])
            }
        }
    }
}

/// Simple flowing wrap of keyword chips.
struct KeywordChips: View {
    let keywords: [String]

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(keywords, id: \.self) { kw in
                Text(kw)
                    .font(.system(size: 9.5))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color.primary.opacity(0.07))
                    )
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        let positions = arrange(proposal: proposal, subviews: subviews).positions
        for (subview, position) in zip(subviews, positions) {
            subview.place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                          proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize,
                         subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return (CGSize(width: width, height: y + rowHeight), positions)
    }
}

struct WelcomeView: View {
    let onAnalyze: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Welcome to Find App")
                .font(.title.weight(.semibold))
            Text("""
                It lets you find apps by what they *do* — for example \
                "menubar utility" or "code editor". To build its index, it \
                analyzes your installed apps with AI (using your local \
                `claude` CLI) and writes a short description for each one. \
                The analysis takes a few minutes the first time.
                """)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: 440, alignment: .leading)
            HStack(spacing: 12) {
                Button("Skip for Now", action: onSkip)
                Button("Analyze My Apps", action: onAnalyze)
                    .keyboardShortcut(.defaultAction)
            }
            Text("You can run this anytime from Settings.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(24)
    }
}
