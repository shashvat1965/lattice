import AppKit
import SwiftUI
import Combine
import LatticeKit

// MARK: - Rows

struct PaletteRow: Identifiable {
    let item: PaletteItem
    let index: Int
    let title: AttributedString
    let titleSelected: AttributedString
    var id: String { item.id }
}

struct PaletteSection: Identifiable {
    let group: PaletteGroup
    let rows: [PaletteRow]
    var id: Int { group.rawValue }
}

// MARK: - Search field focus

@MainActor
final class PaletteFocusBox {
    weak var field: NSTextField?

    func focus() {
        guard let field else { return }
        field.window?.makeFirstResponder(field)
        field.selectText(nil)
    }
}

// MARK: - State

@MainActor
final class PaletteState: ObservableObject {
    @Published var query = ""
    @Published var selection = 0
    @Published var appeared = false
    /// Bumped only by keyboard navigation, so hover never scrolls the list.
    @Published private(set) var keyboardScroll = 0

    @Published private(set) var sections: [PaletteSection] = []
    @Published private(set) var rows: [PaletteRow] = []

    let focusBox = PaletteFocusBox()
    private var items: [PaletteItem] = []

    var selectedRow: PaletteRow? {
        rows.indices.contains(selection) ? rows[selection] : nil
    }

    func rebuild(model: AppModel) {
        items = PaletteCatalog.items(model: model)
        refresh()
    }

    /// Filtering happens once here, never inside a row body.
    func refresh() {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if needle.isEmpty {
            var sections: [PaletteSection] = []
            var rows: [PaletteRow] = []
            for group in PaletteGroup.allCases {
                let groupItems = items.filter { $0.group == group }
                guard !groupItems.isEmpty else { continue }
                let sectionRows = groupItems.map { item in
                    makeRow(item, indices: [], index: rows.count)
                }
                sections.append(PaletteSection(group: group, rows: sectionRows))
                rows.append(contentsOf: sectionRows)
            }
            publish(sections: sections, rows: rows)
            return
        }

        var scored: [PaletteGroup: [(item: PaletteItem, match: PaletteMatch)]] = [:]
        var best: [PaletteGroup: Int] = [:]

        for item in items {
            guard let match = bestMatch(for: needle, item: item) else { continue }
            scored[item.group, default: []].append((item, match))
            best[item.group] = max(best[item.group] ?? Int.min, match.score)
        }

        // Groups stay contiguous — headers never repeat — but the best-matching
        // group comes first so the top row is always the best result.
        let order = scored.keys.sorted { lhs, rhs in
            let left = best[lhs] ?? 0
            let right = best[rhs] ?? 0
            if left != right { return left > right }
            return lhs.rawValue < rhs.rawValue
        }

        var sections: [PaletteSection] = []
        var rows: [PaletteRow] = []
        for group in order {
            guard let entries = scored[group], !entries.isEmpty else { continue }
            let sorted = entries.sorted { lhs, rhs in
                if lhs.match.score != rhs.match.score { return lhs.match.score > rhs.match.score }
                return lhs.item.title.localizedStandardCompare(rhs.item.title) == .orderedAscending
            }
            let sectionRows = sorted.map { entry in
                makeRow(entry.item, indices: entry.match.indices, index: rows.count)
            }
            sections.append(PaletteSection(group: group, rows: sectionRows))
            rows.append(contentsOf: sectionRows)
        }

        publish(sections: sections, rows: rows)
    }

    private func publish(sections: [PaletteSection], rows: [PaletteRow]) {
        self.sections = sections
        self.rows = rows
        if selection >= rows.count {
            selection = max(0, rows.count - 1)
        }
    }

    private func makeRow(_ item: PaletteItem, indices: [Int], index: Int) -> PaletteRow {
        PaletteRow(
            item: item,
            index: index,
            title: Self.highlight(item.title, indices: indices, selected: false),
            titleSelected: Self.highlight(item.title, indices: indices, selected: true)
        )
    }

    private func bestMatch(for query: String, item: PaletteItem) -> PaletteMatch? {
        var best: PaletteMatch?

        if let match = PaletteFuzzy.match(query: query, in: item.title) {
            best = match
        }

        for keyword in item.keywords where !keyword.isEmpty {
            guard let match = PaletteFuzzy.match(query: query, in: keyword) else { continue }
            let damped = PaletteMatch(score: match.score * 3 / 4, indices: [])
            if best == nil || damped.score > best!.score { best = damped }
        }

        guard !item.group.title.isEmpty else { return best }
        if let match = PaletteFuzzy.match(query: query, in: item.group.title) {
            let damped = PaletteMatch(score: match.score / 2, indices: [])
            if best == nil || damped.score > best!.score { best = damped }
        }

        return best
    }

    private static func highlight(_ text: String, indices: [Int], selected: Bool) -> AttributedString {
        let marked = Set(indices)
        var result = AttributedString()
        for (index, character) in text.enumerated() {
            var piece = AttributedString(String(character))
            if marked.contains(index) {
                piece.foregroundColor = selected ? .white : .accentColor
                piece.inlinePresentationIntent = .stronglyEmphasized
            } else {
                piece.foregroundColor = selected ? .white : .primary
            }
            result += piece
        }
        return result
    }

    // MARK: Keyboard

    func moveSelection(by delta: Int) {
        guard !rows.isEmpty else { return }
        selection = min(max(0, selection + delta), rows.count - 1)
        keyboardScroll += 1
    }

    func selectFirst() {
        selection = 0
    }
}

// MARK: - Search field

final class PaletteTextField: NSTextField {
    var onMove: ((Int) -> Void)?
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 125: onMove?(1)                 // ↓
        case 126: onMove?(-1)                // ↑
        case 36, 76: onCommit?()             // ↩ / keypad enter
        case 53: onCancel?()                 // esc
        default: super.keyDown(with: event)
        }
    }
}

struct PaletteSearchField: NSViewRepresentable {
    @Binding var text: String
    let focusBox: PaletteFocusBox
    let onMove: (Int) -> Void
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> PaletteTextField {
        let field = PaletteTextField()
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 15, weight: .regular)
        field.textColor = .labelColor
        field.placeholderString = "Type a command…"
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        field.setAccessibilityLabel("Search commands")
        field.setAccessibilityHelp("Type to filter commands, windows and layouts")
        apply(field)
        focusBox.field = field
        return field
    }

    func updateNSView(_ field: PaletteTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
        apply(field)
        focusBox.field = field
    }

    private func apply(_ field: PaletteTextField) {
        field.onMove = onMove
        field.onCommit = onCommit
        field.onCancel = onCancel
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PaletteSearchField

        init(_ parent: PaletteSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onMove(-1)
                return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onMove(1)
                return true
            case #selector(NSResponder.insertNewline(_:)):
                parent.onCommit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            case #selector(NSResponder.insertTab(_:)):
                parent.onMove(1)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                parent.onMove(-1)
                return true
            default:
                return false
            }
        }
    }
}

// MARK: - Root view

struct CommandPaletteView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var state: PaletteState
    var onRun: (PaletteRow) -> Void
    var onDismiss: () -> Void

    private var reduceMotion: Bool { SurfaceTokens.reduceMotion }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            SurfaceHairline()
            results
            SurfaceHairline()
            hintBar
        }
        .frame(width: CommandPaletteController.width, height: CommandPaletteController.height)
        .background(SurfaceVisualEffect(material: .menu, blending: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: SurfaceTokens.hairline)
        )
        .scaleEffect(state.appeared || reduceMotion ? 1 : 0.98, anchor: .top)
        .opacity(state.appeared || reduceMotion ? 1 : 0)
        .animation(SurfaceTokens.motion(), value: state.appeared)
        .onAppear { state.rebuild(model: model) }
        .onChange(of: state.query) { _, _ in
            state.refresh()
            state.selectFirst()
        }
        .onReceive(model.$windowsBySpace.dropFirst()) { _ in state.rebuild(model: model) }
        .onReceive(model.$layout.dropFirst()) { _ in state.rebuild(model: model) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Command palette")
    }

    // MARK: Search

    private var searchBar: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            PaletteSearchField(
                text: $state.query,
                focusBox: state.focusBox,
                onMove: { state.moveSelection(by: $0) },
                onCommit: {
                    if let row = state.selectedRow { onRun(row) }
                },
                onCancel: onDismiss
            )
            .frame(height: 22)

            if !state.query.isEmpty {
                Button {
                    state.query = ""
                    state.selectFirst()
                    state.focusBox.focus()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    // MARK: Results

    @ViewBuilder
    private var results: some View {
        if state.rows.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(state.sections) { section in
                            Text(section.group.title.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.6)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 16)
                                .padding(.top, 9)
                                .padding(.bottom, 3)
                                .accessibilityAddTraits(.isHeader)

                            ForEach(section.rows) { row in
                                PaletteRowView(
                                    row: row,
                                    isSelected: state.selection == row.index,
                                    onHover: { state.selection = row.index },
                                    onRun: { onRun(row) }
                                )
                                .padding(.horizontal, 6)
                                .id(row.index)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: state.keyboardScroll) { _, _ in
                    proxy.scrollTo(state.selection, anchor: .center)
                }
                .onChange(of: state.query) { _, _ in
                    proxy.scrollTo(0, anchor: .top)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.tertiary)
            Text(state.query.isEmpty ? "No commands available" : "No matches for “\(state.query)”")
                .font(SurfaceTokens.body)
                .foregroundStyle(.secondary)
            Text(state.query.isEmpty
                 ? "Lattice could not build its command list."
                 : "Try a window title, an app name, or a layout.")
                .font(SurfaceTokens.micro)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 18)
        .accessibilityElement(children: .combine)
    }

    // MARK: Footer

    private var hintBar: some View {
        HStack(spacing: 10) {
            hint(symbol: "↑↓", label: "Select")
            hint(symbol: "↩", label: "Run")
            hint(symbol: "esc", label: "Close")
            Spacer(minLength: 0)
            Text("\(state.rows.count) \(state.rows.count == 1 ? "result" : "results")")
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
        .accessibilityElement(children: .combine)
    }

    private func hint(symbol: String, label: String) -> some View {
        HStack(spacing: 4) {
            SurfaceKeyCap(text: symbol, size: 9)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Row

struct PaletteRowView: View {
    let row: PaletteRow
    let isSelected: Bool
    var onHover: () -> Void
    var onRun: () -> Void

    private var height: CGFloat { row.item.subtitle == nil ? 32 : 40 }

    var body: some View {
        HStack(spacing: 10) {
            rowIcon
                .font(.system(size: 12.5, weight: .medium))
                .frame(width: 18)
                .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(isSelected ? row.titleSelected : row.title)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let subtitle = row.item.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.75) : Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 12)

            if let combo = row.item.combo {
                SurfaceKeyCombo(combo: combo, size: 10)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { inside in if inside { onHover() } }
        .onTapGesture(perform: onRun)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onRun() }
    }

    @ViewBuilder
    private var rowIcon: some View {
        if let pid = row.item.pid, let icon = SurfaceIconCache.shared.icon(for: pid) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: row.item.symbol)
        }
    }

    private var accessibilityLabel: String {
        var parts = [row.item.title, row.item.group.title]
        if let subtitle = row.item.subtitle { parts.append(subtitle) }
        if let combo = row.item.combo { parts.append("shortcut \(combo.display)") }
        return parts.joined(separator: ", ")
    }
}
