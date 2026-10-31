import SwiftUI
import AppKit
import Combine
import LatticeKit

// MARK: - ShortcutsPane

/// Every command, grouped by category, with a recorder on each shortcut.
/// This is the screen Lattice wins on: no config file, no YAML, no restart.
///
/// Two keyboard models live here: AeroSpace-style Space keys (⌥1… jumps, ⇧⌥1… sends the
/// window) and one or two chords per command. Both write straight into `Preferences`
/// and ask `HotkeyCenter` to re-register, so nothing needs a relaunch.
@MainActor
struct ShortcutsPane: View {

    private enum BindingFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case bound = "Bound"
        case unbound = "Unbound"

        var id: String { rawValue }
    }

    private struct ShortcutSection: Identifiable {
        var category: CommandCategory
        var commands: [CommandID]
        var id: CommandCategory { category }
    }

    private struct SpaceKeyEntry: Identifiable {
        var key: String
        var number: Int
        var id: String { key }
    }

    private enum ChordSlot: Equatable {
        case primary
        case alternate
    }

    /// The other side of a conflict. Space keys are stored per key, not per command,
    /// so they get their own case: removing one removes both of its chords.
    private enum ConflictTarget: Equatable {
        case command(CommandID, alternate: Bool)
        case spaceKey(String)
    }

    private struct PendingBinding: Equatable {
        var command: CommandID
        var slot: ChordSlot
        var combo: KeyCombo
        var target: ConflictTarget?
        var systemName: String?
    }

    private static let primaryWidth: CGFloat = 150
    private static let alternateWidth: CGFloat = 112

    @ObservedObject private var store = SettingsPreferences.shared
    @ObservedObject private var model = AppModel.shared
    @StateObject private var recorder = KeyRecorder()
    @StateObject private var alternateRecorder = KeyRecorder()

    @State private var query = ""
    @State private var filter: BindingFilter = .all
    @State private var pending: PendingBinding?
    @State private var confirmReset = false
    @State private var showAddSpaceKey = false
    @State private var showArrowHint = true
    /// Bumped when HotkeyCenter re-registers, so its conflict reasons are re-read.
    @State private var hotkeyTick = 0

    var body: some View {
        ScrollView {
            content
        }
        .background(Color.latticeCanvas)
        .onAppear {
            store.beginObserving()
            recorder.onResult = { command, combo in commit(command, combo, slot: .primary) }
            recorder.onCancel = { animate { pending = nil } }
            alternateRecorder.onResult = { command, combo in commit(command, combo, slot: .alternate) }
            alternateRecorder.onCancel = { animate { pending = nil } }
        }
        .onDisappear {
            recorder.cancel()
            alternateRecorder.cancel()
            store.endObserving()
        }
        .onReceive(NotificationCenter.default.publisher(for: .latticeHotkeysDidChange)) { _ in
            hotkeyTick &+= 1
        }
        .sheet(isPresented: $showAddSpaceKey) {
            AddSpaceKeySheet(existing: store.prefs.spaceKeys) { key, number in
                addSpaceKey(key, number)
            }
        }
        .confirmationDialog("Reset all shortcuts?", isPresented: $confirmReset) {
            Button("Reset Shortcuts", role: .destructive) {
                store.update { prefs in
                    prefs.bindings = Preferences.defaultBindings
                    prefs.alternateBindings = Preferences.defaultAlternates
                    prefs.spaceKeys = Preferences.defaultSpaceKeys
                }
                HotkeyCenter.shared.reload()
                animate { pending = nil }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every command and alternate chord, plus every Space key, returns to its shipping shortcut.")
        }
    }

    private func animate(_ body: () -> Void) {
        withAnimation(LatticeTheme.animation, body)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: LatticeTheme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Shortcuts")
                        .latticeTitle()
                    Text("Click a shortcut, then press the keys you want.")
                        .latticeCaption()
                }
                Spacer(minLength: LatticeTheme.Spacing.sm)
                Button("Reset to defaults") { confirmReset = true }
                    .controlSize(.small)
                    .accessibilityLabel("Reset all shortcuts to their defaults")
            }

            HStack(spacing: LatticeTheme.Spacing.sm) {
                searchField
                    .frame(maxWidth: 300)
                Spacer(minLength: LatticeTheme.Spacing.xs)
                LatticeSegmented(
                    selection: $filter,
                    options: BindingFilter.allCases.map { (value: $0, title: $0.rawValue) }
                )
                .frame(width: 196)
                .accessibilityLabel("Filter shortcuts")
            }

            if showArrowHint {
                arrowHint
            }
        }
        .padding(.horizontal, LatticeTheme.gutter)
        .padding(.top, 18)
        .padding(.bottom, LatticeTheme.Spacing.sm)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search actions or shortcuts", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .accessibilityLabel("Search actions or shortcuts")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, LatticeTheme.Spacing.xs)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: LatticeTheme.Radius.sm, style: .continuous)
                .fill(Color.latticeCardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LatticeTheme.Radius.sm, style: .continuous)
                .strokeBorder(Color.latticeHairline, lineWidth: LatticeTheme.hairline)
        )
    }

    /// A footnote, not a banner: the arrow chords are a real macOS collision and the
    /// user may want them back, but nothing is wrong. Dismissal lasts for this visit only.
    private var arrowHint: some View {
        HStack(alignment: .top, spacing: LatticeTheme.Spacing.xs) {
            InlineHint(
                text: "⌥← → ↑ ↓ move the focused window. macOS uses the same chords to move by word inside text fields, so clear them here if you want that back."
            )
            Spacer(minLength: 0)
            Button {
                animate { showArrowHint = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Hide this note")
            .accessibilityLabel("Dismiss the note about Option-arrow shortcuts")
        }
    }

    // MARK: Space keys

    private var spaceKeyEntries: [SpaceKeyEntry] {
        store.prefs.spaceKeys
            .map { SpaceKeyEntry(key: $0.key, number: $0.value) }
            .sorted { lhs, rhs in
                if lhs.number != rhs.number { return lhs.number < rhs.number }
                return KeyCombo.pretty(lhs.key) < KeyCombo.pretty(rhs.key)
            }
    }

    private var spaceKeysSection: some View {
        VStack(alignment: .leading, spacing: LatticeTheme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: LatticeTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Space keys")
                        .latticeSectionHeader()
                    Text("⌥ plus a key jumps to a Space. ⇧⌥ plus the same key sends the focused window there.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button("Add key…") {
                    recorder.cancel()
                    alternateRecorder.cancel()
                    pending = nil
                    showAddSpaceKey = true
                }
                .controlSize(.small)
                .accessibilityLabel("Add a Space key")
            }

            Card(padding: 0) {
                if spaceKeyEntries.isEmpty {
                    InlineHint(
                        text: "No Space keys — Spaces can still be switched with ⌃⌥← →",
                        symbol: "info.circle"
                    )
                    .padding(.horizontal, LatticeTheme.Spacing.sm)
                    .padding(.vertical, 10)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 286), spacing: LatticeTheme.Spacing.xs)],
                        alignment: .leading,
                        spacing: 2
                    ) {
                        ForEach(spaceKeyEntries) { entry in
                            spaceKeyRow(entry)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)

                    if let count = currentSpaceCount, !orphanedKeys.isEmpty {
                        Text("\(orphanedKeys.count) \(orphanedKeys.count == 1 ? "key points" : "keys point") past this display's \(count) Spaces")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 8)
                            .padding(.bottom, 6)
                    }
                }
            }
        }
        .padding(.horizontal, LatticeTheme.gutter)
        .padding(.bottom, LatticeTheme.Spacing.sm)
    }

    private func spaceKeyRow(_ entry: SpaceKeyEntry) -> some View {
        let option = KeyCombo(key: entry.key, modifiers: [.option])
        let send = KeyCombo(key: entry.key, modifiers: [.option, .shift])
        let pretty = KeyCombo.pretty(entry.key)
        let missing = currentSpaceCount.map { entry.number > $0 } ?? false

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                KeyCap(text: pretty)

                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)

                Text("Space \(entry.number)")
                    .font(.system(size: 12))
                    .latticeMonoDigits()
                    .foregroundStyle(missing ? Color.secondary : Color.primary)
                    .lineLimit(1)

                Spacer(minLength: LatticeTheme.Spacing.xxs)

                HStack(spacing: 5) {
                    SettingsKeyChord(combo: option)
                    Text("·")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    SettingsKeyChord(combo: send)
                        .opacity(0.72)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Option \(pretty) jumps to Space \(entry.number). Shift Option \(pretty) sends the focused window to Space \(entry.number).")

                Button {
                    removeSpaceKey(entry.key)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove the \(pretty) Space key")
                .accessibilityLabel("Remove the \(pretty) key that goes to Space \(entry.number)")
            }
            .frame(height: 26)

        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
    }

    /// Keys pointing at Spaces this display does not have. Reported once under the grid
    /// rather than repeated under every affected row.
    private var orphanedKeys: [String] {
        guard let count = currentSpaceCount else { return [] }
        return store.prefs.spaceKeys.filter { $0.value > count }.map(\.key)
    }

    /// How many user Spaces the display that owns the focused Space has. Fullscreen
    /// Spaces are excluded, matching Mission Control's numbering. `nil` before the
    /// first refresh, so nothing warns on a cold start with no data.
    private var currentSpaceCount: Int? {
        guard !model.spaces.isEmpty else { return nil }
        let entry = model.spaces.first { $0.spaceIDs.contains(model.focusedSpace) }
            ?? model.spaces.first { $0.isMain }
            ?? model.spaces.first
        guard let entry else { return nil }
        let count = entry.userSpaceIDs.count
        return count > 0 ? count : nil
    }

    // MARK: List

    /// Rendered without a ScrollView so the page can be captured offscreen.
    @ViewBuilder var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            LatticeDivider()
            spaceKeysSection
            shortcutList
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var shortcutList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(sections) { section in
                HStack(alignment: .firstTextBaseline, spacing: LatticeTheme.Spacing.xs) {
                    Text(section.category.title)
                        .latticeSectionHeader()
                    Text("\(section.commands.count)")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                    Text("Shortcut")
                        .latticeSectionHeader()
                        .padding(.trailing, 34)
                }
                .padding(.horizontal, LatticeTheme.gutter)
                .padding(.top, LatticeTheme.Spacing.lg)
                .padding(.bottom, LatticeTheme.Spacing.xxs)

                ForEach(section.commands.filter { !Self.isSpaceNumberCommand($0) }) { command in
                    shortcutRow(command)
                        .padding(.horizontal, LatticeTheme.gutter)

                    if let pending, pending.command == command {
                        conflictRow(pending)
                            .padding(.horizontal, LatticeTheme.gutter)
                    }

                    LatticeDivider(insetLeading: LatticeTheme.gutter)
                }

                if section.commands.contains(where: { $0.rawValue.hasPrefix("space") }) {
                    spaceSummaryRow(
                        title: "Go to Space",
                        chords: "⌥ + Space key",
                        detail: "\(store.prefs.spaceKeys.count) keys set above"
                    )
                }
                if section.commands.contains(where: { $0.rawValue.hasPrefix("moveToSpace") }) {
                    spaceSummaryRow(
                        title: "Send to Space",
                        chords: "⇧⌥ + Space key",
                        detail: "Moves the focused window"
                    )
                }
            }
        }
        .overlay {
            if sections.isEmpty {
                EmptyState(
                    symbol: "magnifyingglass",
                    title: "No shortcuts match",
                    message: query.isEmpty
                        ? "Nothing is \(filter == .bound ? "bound" : "unbound") right now."
                        : "Nothing matches “\(query)”.",
                    actionTitle: "Clear filters",
                    action: {
                        animate {
                            query = ""
                            filter = .all
                        }
                    }
                )
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            cheatSheetHint
        }
    }

    private static func isSpaceNumberCommand(_ command: CommandID) -> Bool {
        command.rawValue.hasPrefix("space") || command.rawValue.hasPrefix("moveToSpace")
    }

    /// Nine commands that all do the same thing with a different number do not deserve nine
    /// rows: the mapping lives in the Space keys card above, and this states the pattern.
    private func spaceSummaryRow(title: String, chords: String, detail: String) -> some View {
        HStack(spacing: LatticeTheme.Spacing.sm) {
            Image(systemName: "square.on.square")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13))
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: LatticeTheme.Spacing.xs)
            Text(chords)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(height: 34)
        .padding(.horizontal, LatticeTheme.gutter)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(chords). \(detail).")
    }

    private func shortcutRow(_ command: CommandID) -> some View {
        let primary = store.prefs.bindings[command]
        let alternate = store.prefs.alternateBindings[command]
        let recordingPrimary = recorder.target == command
        let recordingAlternate = alternateRecorder.target == command
        let primaryWarning = warning(for: primary, command: command, slot: .primary)
        let alternateWarning = warning(for: alternate, command: command, slot: .alternate)
        _ = hotkeyTick
        let registrationWarning = HotkeyCenter.shared.conflictReasons[command]

        return HStack(spacing: LatticeTheme.Spacing.sm) {
            Image(systemName: command.symbol)
                .font(.system(size: 12))
                .foregroundStyle(recordingPrimary || recordingAlternate ? Color.accentColor : Color.secondary)
                .frame(width: 18)

            Text(command.title)
                .font(.system(size: 13))
                .foregroundStyle(recordingPrimary || recordingAlternate ? Color.accentColor : Color.primary)
                .lineLimit(1)

            if let registrationWarning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(nsColor: .systemOrange))
                    .help("Lattice could not register this shortcut: \(registrationWarning)")
                    .accessibilityLabel("Shortcut warning for \(command.title): \(registrationWarning)")
            }

            Spacer(minLength: LatticeTheme.Spacing.xs)

            alternateSlot(command, alternate: alternate, recording: recordingAlternate, warning: alternateWarning)
                .frame(width: Self.alternateWidth, alignment: .trailing)

            primarySlot(command, primary: primary, recording: recordingPrimary, warning: primaryWarning)

            Button {
                if recordingPrimary { recorder.cancel() }
                if recordingAlternate { alternateRecorder.cancel() }
                apply(command, nil, slot: .primary)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .opacity(primary == nil ? 0 : 1)
            .disabled(primary == nil)
            .help("Remove shortcut")
            .accessibilityLabel("Remove shortcut for \(command.title)")
        }
        .frame(height: 34)
        .contentShape(Rectangle())
    }

    /// The main chord. Behaviour is unchanged: click to record, minus to clear.
    private func primarySlot(_ command: CommandID,
                             primary: KeyCombo?,
                             recording: Bool,
                             warning: String?) -> some View {
        Button {
            if recording {
                recorder.cancel()
            } else {
                alternateRecorder.cancel()
                pending = nil
                recorder.begin(command)
            }
        } label: {
            Group {
                if recording {
                    KeyRecorderField(recorder: recorder, command: command)
                } else {
                    HStack(spacing: 4) {
                        if let warning {
                            conflictBadge(warning)
                        }
                        SettingsKeyChord(combo: primary)
                    }
                    .frame(width: Self.primaryWidth, alignment: .trailing)
                    .contentShape(Rectangle())
                }
            }
        }
        .buttonStyle(.plain)
        .help(recording ? "Escape cancels, Delete clears" : (warning ?? "Click to record a new shortcut"))
        .accessibilityLabel("Shortcut for \(command.title): \(primary?.display ?? "unbound")")
        .accessibilityHint(recording
                           ? "Press keys. Escape cancels, Delete clears."
                           : "Press to record a new shortcut")
    }

    /// The second chord: dimmed next to the primary, a plus when empty.
    @ViewBuilder
    private func alternateSlot(_ command: CommandID,
                               alternate: KeyCombo?,
                               recording: Bool,
                               warning: String?) -> some View {
        if recording {
            Button {
                alternateRecorder.cancel()
            } label: {
                KeyRecorderField(recorder: alternateRecorder, command: command)
            }
            .buttonStyle(.plain)
            .help("Escape cancels, Delete clears")
            .accessibilityLabel("Recording the alternate shortcut for \(command.title)")
        } else if let alternate {
            HStack(spacing: 4) {
                if let warning {
                    conflictBadge(warning)
                }

                Button {
                    recorder.cancel()
                    pending = nil
                    alternateRecorder.begin(command)
                } label: {
                    SettingsKeyChord(combo: alternate)
                        .opacity(0.62)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(warning ?? "Alternate: \(alternate.display). Click to record a new one.")
                .accessibilityLabel("Alternate shortcut for \(command.title): \(alternate.display)")
                .accessibilityHint("Press to record a new alternate shortcut")
                .contextMenu {
                    Button("Remove Alternate Shortcut", role: .destructive) {
                        apply(command, nil, slot: .alternate)
                    }
                }

                Button {
                    apply(command, nil, slot: .alternate)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove the alternate shortcut")
                .accessibilityLabel("Remove the alternate shortcut for \(command.title)")
            }
        } else {
            Button {
                recorder.cancel()
                pending = nil
                alternateRecorder.begin(command)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Add an alternate shortcut for \(command.title)")
            .accessibilityLabel("Add an alternate shortcut for \(command.title)")
        }
    }

    private func conflictBadge(_ message: String) -> some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 10))
            .foregroundStyle(Color(nsColor: .systemOrange))
            .help(message)
            .accessibilityLabel(message)
    }

    // MARK: Conflicts

    private func conflictRow(_ pending: PendingBinding) -> some View {
        HStack(alignment: .top, spacing: LatticeTheme.Spacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color(nsColor: .systemOrange))
                .padding(.top, 1)
                .help(conflictMessage(pending))

            VStack(alignment: .leading, spacing: 2) {
                Text(conflictMessage(pending))
                    .font(.system(size: 12))
                if let systemName = pending.systemName {
                    Text("macOS reserves that combination for “\(systemName)”.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: LatticeTheme.Spacing.xs)

            if pending.target != nil {
                Button("Use anyway") { apply(pending.command, pending.combo, slot: pending.slot) }
                    .controlSize(.small)
                    .accessibilityLabel("Use \(pending.combo.display) anyway")
                Button(unbindTitle(pending)) { takeOver(pending, unbindingOther: true) }
                    .controlSize(.small)
                    .accessibilityLabel("\(unbindTitle(pending)) and use \(pending.combo.display) here")
            } else {
                Button("Use anyway") { apply(pending.command, pending.combo, slot: pending.slot) }
                    .controlSize(.small)
                Button("Open Keyboard settings") { SettingsLinks.openKeyboardSettings() }
                    .controlSize(.small)
            }

            Button("Cancel") { animate { self.pending = nil } }
                .controlSize(.small)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 9)
        .background(
            RoundedRectangle(cornerRadius: LatticeTheme.Radius.md, style: .continuous)
                .fill(Color(nsColor: .systemOrange).opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: LatticeTheme.Radius.md, style: .continuous)
                .strokeBorder(Color(nsColor: .systemOrange).opacity(0.35),
                              lineWidth: LatticeTheme.hairline)
        )
        .listRowBackground(Color.clear)
    }

    private func unbindTitle(_ pending: PendingBinding) -> String {
        if case .spaceKey = pending.target { return "Remove Space key" }
        return "Unbind other"
    }

    private func conflictMessage(_ pending: PendingBinding) -> String {
        switch pending.target {
        case .command(let other, let alternate):
            return "\(pending.combo.display) is already used by \(other.title)\(alternate ? " (alternate)" : "")."
        case .spaceKey(let key):
            let pretty = KeyCombo.pretty(key)
            if let number = store.prefs.spaceKeys[key] {
                return "\(pending.combo.display) is used by the Space key \(pretty) (Space \(number))."
            }
            return "\(pending.combo.display) is used by a Space key."
        case nil:
            if let systemName = pending.systemName {
                return "\(pending.combo.display) is macOS \(systemName)."
            }
            return "\(pending.combo.display) is already in use."
        }
    }

    /// A human label for the other side of a clash, used in the amber tooltip.
    private func warning(for combo: KeyCombo?,
                         command: CommandID,
                         slot: ChordSlot) -> String? {
        guard let combo else { return nil }

        for (key, number) in store.prefs.spaceKeys {
            let pretty = KeyCombo.pretty(key)
            if combo == KeyCombo(key: key, modifiers: [.option]) {
                return "\(combo.display) is also the Space key for Space \(number) (⌥\(pretty))."
            }
            if combo == KeyCombo(key: key, modifiers: [.option, .shift]) {
                return "\(combo.display) is also the send-to-Space key for Space \(number) (⇧⌥\(pretty))."
            }
        }

        for other in CommandID.allCases where other != command {
            if store.prefs.bindings[other] == combo {
                return "\(combo.display) is also used by \(other.title)."
            }
            if store.prefs.alternateBindings[other] == combo {
                return "\(combo.display) is also the alternate for \(other.title)."
            }
        }

        if slot == .alternate, store.prefs.bindings[command] == combo {
            return "\(combo.display) is also the main shortcut for \(command.title)."
        }
        if slot == .primary, store.prefs.alternateBindings[command] == combo {
            return "\(combo.display) is also the alternate shortcut for \(command.title)."
        }

        return nil
    }

    /// The same search, but as something a conflict row can act on.
    private func conflictTarget(for combo: KeyCombo,
                                command: CommandID,
                                slot: ChordSlot) -> ConflictTarget? {
        for (key, _) in store.prefs.spaceKeys {
            if combo == KeyCombo(key: key, modifiers: [.option])
                || combo == KeyCombo(key: key, modifiers: [.option, .shift]) {
                return .spaceKey(key)
            }
        }

        for other in CommandID.allCases where other != command {
            if store.prefs.bindings[other] == combo {
                return .command(other, alternate: false)
            }
            if store.prefs.alternateBindings[other] == combo {
                return .command(other, alternate: true)
            }
        }

        if slot == .alternate, store.prefs.bindings[command] == combo {
            return .command(command, alternate: false)
        }
        if slot == .primary, store.prefs.alternateBindings[command] == combo {
            return .command(command, alternate: true)
        }

        return nil
    }

    // MARK: Hint bar

    private var cheatSheetHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "keyboard")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if let combo = store.prefs.bindings[.cheatSheet] {
                Text("Hold")
                    .latticeCaption()
                SettingsKeyChord(combo: combo)
                Text("to see every shortcut on screen")
                    .latticeCaption()
            } else {
                Text("No shortcut for the cheat sheet yet. Record one above.")
                    .latticeCaption()
            }

            Spacer(minLength: LatticeTheme.Spacing.xs)
            Button("Show Cheat Sheet") {
                NotificationCenter.default.post(name: .latticeShowCheatSheet, object: nil)
            }
            .buttonStyle(.link)
            .font(.system(size: 11))
            .accessibilityLabel("Show the shortcut cheat sheet on screen")
        }
        .padding(.horizontal, LatticeTheme.gutter)
        .frame(height: 38)
        .background(.bar)
        .overlay(alignment: .top) { LatticeDivider() }
    }

    // MARK: Filtering

    private var sections: [ShortcutSection] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var result: [ShortcutSection] = []

        for category in CommandCategory.allCases {
            var commands = CommandID.allCases.filter { $0.category == category }

            switch filter {
            case .all: break
            case .bound: commands = commands.filter { store.prefs.bindings[$0] != nil }
            case .unbound: commands = commands.filter { store.prefs.bindings[$0] == nil }
            }

            if !needle.isEmpty {
                commands = commands.filter { command in
                    if command.title.lowercased().contains(needle) { return true }
                    if let combo = store.prefs.bindings[command],
                       combo.display.lowercased().contains(needle) { return true }
                    if let combo = store.prefs.alternateBindings[command],
                       combo.display.lowercased().contains(needle) { return true }
                    return false
                }
            }

            if !commands.isEmpty {
                result.append(ShortcutSection(category: category, commands: commands))
            }
        }
        return result
    }

    // MARK: Binding writes

    private func commit(_ command: CommandID, _ combo: KeyCombo?, slot: ChordSlot) {
        guard let combo else {
            apply(command, nil, slot: slot)
            return
        }

        if let target = conflictTarget(for: combo, command: command, slot: slot) {
            animate {
                pending = PendingBinding(command: command, slot: slot, combo: combo, target: target)
            }
            return
        }

        if let system = SettingsSystemShortcuts.conflict(for: combo) {
            animate {
                pending = PendingBinding(command: command, slot: slot, combo: combo, systemName: system.name)
            }
            return
        }

        apply(command, combo, slot: slot)
    }

    private func apply(_ command: CommandID, _ combo: KeyCombo?, slot: ChordSlot) {
        store.update { prefs in
            switch slot {
            case .primary:
                if let combo {
                    prefs.bindings[command] = combo
                } else {
                    prefs.bindings.removeValue(forKey: command)
                }
            case .alternate:
                if let combo {
                    prefs.alternateBindings[command] = combo
                } else {
                    prefs.alternateBindings.removeValue(forKey: command)
                }
            }
        }
        // The shared bridge only watches `bindings`; alternates and Space keys must ask.
        if slot == .alternate { HotkeyCenter.shared.reload() }
        animate { pending = nil }
    }

    private func takeOver(_ pending: PendingBinding, unbindingOther: Bool) {
        store.update { prefs in
            if unbindingOther, let target = pending.target {
                switch target {
                case .command(let other, let alternate):
                    if alternate {
                        prefs.alternateBindings.removeValue(forKey: other)
                    } else {
                        prefs.bindings.removeValue(forKey: other)
                    }
                case .spaceKey(let key):
                    prefs.spaceKeys.removeValue(forKey: key)
                }
            }

            switch pending.slot {
            case .primary:
                prefs.bindings[pending.command] = pending.combo
            case .alternate:
                prefs.alternateBindings[pending.command] = pending.combo
            }
        }
        HotkeyCenter.shared.reload()
        animate { self.pending = nil }
    }

    // MARK: Space key writes

    private func addSpaceKey(_ key: String, _ number: Int) {
        store.update { prefs in
            prefs.spaceKeys[key] = number
        }
        HotkeyCenter.shared.reload()
    }

    private func removeSpaceKey(_ key: String) {
        store.update { prefs in
            prefs.spaceKeys.removeValue(forKey: key)
        }
        HotkeyCenter.shared.reload()
    }
}

// MARK: - Add Space key sheet

/// A small recorder sheet. Pressing a key is the whole interaction; the Space number
/// is a stepper because there are only nine. Escape cancels, Delete clears.
private struct AddSpaceKeySheet: View {

    var existing: [String: Int]
    var onAdd: (String, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = SpaceKeyRecorder()
    @State private var spaceNumber = 1
    @State private var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: LatticeTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Add a Space key")
                    .font(.system(size: 15, weight: .semibold))
                Text("Press a letter, a digit or a function key. Lattice adds ⌥ and ⇧⌥ around it.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            recorderField

            if let message = recorder.message {
                amberNote(message)
            }

            Stepper(value: $spaceNumber, in: 1...9) {
                HStack(spacing: 6) {
                    Text("Goes to Space")
                        .font(.system(size: 13))
                    Text("\(spaceNumber)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .latticeMonoDigits()
                }
            }
            .accessibilityLabel("Space number")
            .accessibilityValue("Space \(spaceNumber)")
            .onChange(of: spaceNumber) { _, _ in note = nil }

            if let note {
                amberNote(note)
            }

            HStack(spacing: LatticeTheme.Spacing.xs) {
                Spacer(minLength: 0)
                Button("Cancel") {
                    recorder.cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Cancel adding a Space key")

                Button("Add Key") { add() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(recorder.key == nil)
                    .accessibilityLabel("Add this Space key")
            }
        }
        .padding(LatticeTheme.Spacing.lg)
        .frame(width: 380)
        .onAppear {
            recorder.onCancel = { dismiss() }
            recorder.begin()
        }
        .onDisappear {
            recorder.cancel()
        }
    }

    private var recorderField: some View {
        HStack(spacing: LatticeTheme.Spacing.sm) {
            if let key = recorder.key {
                KeyCap(text: KeyCombo.pretty(key))
            } else {
                Image(systemName: "keyboard")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            Text(recorder.key == nil ? "Press a key…" : "Ready")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(recorder.key == nil ? Color.secondary : Color.primary)

            Spacer(minLength: 0)

            Button("Clear") { recorder.clear() }
                .controlSize(.small)
                .disabled(recorder.key == nil)
                .accessibilityLabel("Clear the recorded key")
        }
        .padding(.horizontal, LatticeTheme.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LatticeTheme.Radius.md, style: .continuous)
                .fill(Color.latticeCardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LatticeTheme.Radius.md, style: .continuous)
                .strokeBorder(Color.latticeHairline, lineWidth: LatticeTheme.hairline)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(recorder.key == nil
                            ? "Press a key to bind"
                            : "Recorded key \(KeyCombo.pretty(recorder.key ?? ""))")
        .accessibilityHint("Escape cancels, Delete clears")
    }

    private func amberNote(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color(nsColor: .systemOrange))
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Color(nsColor: .systemOrange))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func add() {
        guard let key = recorder.key else { return }

        if let existingSpace = existing[key], existingSpace != spaceNumber {
            note = "“\(KeyCombo.pretty(key))” already jumps to Space \(existingSpace). Remove it first, or choose Space \(existingSpace)."
            return
        }

        recorder.cancel()
        onAdd(key, spaceNumber)
        dismiss()
    }
}
