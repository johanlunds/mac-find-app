import SwiftUI
import AppKit

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query: String = "" {
        didSet { runSearch() }
    }
    @Published var results: [SearchResult] = []
    @Published var selection: Int = 0

    let engine: SearchEngine
    var onResultsChanged: (() -> Void)?
    var onLaunch: ((SearchResult) -> Void)?
    var onDismiss: (() -> Void)?

    init(engine: SearchEngine) {
        self.engine = engine
    }

    private func runSearch() {
        results = engine.search(query)
        selection = 0
        onResultsChanged?()
    }

    func reset() {
        query = ""
        results = []
        selection = 0
        onResultsChanged?()
    }

    func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + delta + results.count) % results.count
    }

    func launchSelected() {
        guard results.indices.contains(selection) else { return }
        onLaunch?(results[selection])
    }
}

/// AppKit-backed text field so the panel controller can deterministically make
/// it first responder, and so we can intercept arrows/return/escape.
struct SearchField: NSViewRepresentable {
    @ObservedObject var model: SearchViewModel

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 24, weight: .light)
        field.placeholderString = "Search apps…"
        field.delegate = context.coordinator
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        FocusTarget.shared.field = field
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != model.query {
            nsView.stringValue = model.query
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        let model: SearchViewModel
        init(model: SearchViewModel) { self.model = model }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            model.query = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveDown(_:)):
                model.moveSelection(1); return true
            case #selector(NSResponder.moveUp(_:)):
                model.moveSelection(-1); return true
            case #selector(NSResponder.insertNewline(_:)):
                model.launchSelected(); return true
            case #selector(NSResponder.cancelOperation(_:)):
                // Esc clears a non-empty query first, and only hides the
                // panel once the field is already empty.
                if model.query.isEmpty {
                    model.onDismiss?()
                } else {
                    textView.string = ""
                    model.query = ""
                }
                return true
            default:
                return false
            }
        }
    }
}

final class FocusTarget {
    static let shared = FocusTarget()
    weak var field: NSTextField?
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct SearchWindowView: View {
    @ObservedObject var model: SearchViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
                SearchField(model: model)
            }
            .padding(.horizontal, 18)
            .frame(height: 60)

            if !model.results.isEmpty {
                Divider()
                VStack(spacing: 2) {
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { i, result in
                        ResultRow(result: result, selected: i == model.selection)
                            .onTapGesture {
                                model.selection = i
                                model.launchSelected()
                            }
                    }
                }
                .padding(8)
            }

            Divider()
            FooterBar(hasResults: !model.results.isEmpty)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }
}

/// Thin bottom strip: app identity on the left, key hints on the right.
struct FooterBar: View {
    let hasResults: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .frame(width: 16, height: 16)
            Text("Find App")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if hasResults {
                KeyHint(key: "↑↓", label: "navigate")
                KeyHint(key: "↵", label: "open")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 27)
        .background(Color.primary.opacity(0.045))
    }
}

struct KeyHint: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 9.5, weight: .semibold))
                .frame(minWidth: 16)
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.1))
                )
            Text(label)
                .font(.system(size: 10))
        }
        .foregroundStyle(.tertiary)
        .padding(.leading, 10)
    }
}

struct ResultRow: View {
    let result: SearchResult
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(result.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(selected ? Color.white : Color.primary)
                if !result.description.isEmpty {
                    Text(result.description)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(selected ? Color.white.opacity(0.75) : Color.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(height: 50)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.accentColor : Color.clear)
        )
        .contentShape(Rectangle())
    }

    private var icon: NSImage {
        NSWorkspace.shared.icon(forFile: result.url.path)
    }
}
