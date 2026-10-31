import SwiftUI
import AppKit
import LatticeKit

// MARK: - ShortcutsPane

/// Every command, grouped by category, with a recorder on each shortcut.
/// This is the screen Lattice wins on: no config file, no YAML, no restart.
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

    private struct PendingBinding: Equatable {
        var command: CommandID
        var combo: KeyCombo
        var conflictingCommand: CommandID?
        var systemName: String?
    }

    @ObservedObject private var store = SettingsPreferences.shared
    @StateObject private var recorder = KeyRecorder()

    @State private var query = ""
    @State private var filter: BindingFilter = .all
    @State private var pending: PendingBinding?
    @State private var confirmReset = false

    var body: some View {
        VStack(spacing: 0) {
            header
            LatticeDivider()
            shortcutList
        }
        .background(Color.latticeCanvas)
        .onAppear {
            store.beginObserving()
            recorder.onResult = { command, combo in commit(command, combo) }
            recorder.onCancel = { animate { pending = nil } }
        }
        .onDisappear {
            recorder.cancel()
            store.endObserving()
        }
        .confirmationDialog("Reset all shortcuts?", isPresented: $confirmReset) {
            Button("Reset Shortcuts", role: .destructive) {
                store.update { $0.bindings = Preferences.defaultBindings }
                animate { pending = nil }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every Lattice command returns to its shipping shortcut.")
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
                Picker("Show", selection: $filter) {
                    ForEach(BindingFilter.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 196)
                .accessibilityLabel("Filter shortcuts")
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

    // MARK: List

    private var shortcutList: some View {
        List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.commands) { command in
                        shortcutRow(command)

                        if let pending, pending.command == command {
                            conflictRow(pending)
                        }
                    }
                } header: {
                    HStack(alignment: .firstTextBaseline, spacing: LatticeTheme.Spacing.xs) {
                        Text(section.category.title)
                            .latticeSectionHeader()
                        Text("\(section.commands.count)")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.tertiary)
                        Spacer(minLength: 0)
                        Text("Shortcut")
                            .latticeSectionHeader()
                            .padding(.trailing, 30)
                    }
                    .textCase(nil)
                }
            }
        }
        .listStyle(.inset)
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

    private func shortcutRow(_ command: CommandID) -> some View {
        let combo = store.prefs.bindings[command]
        let recording = recorder.target == command

        return HStack(spacing: LatticeTheme.Spacing.sm) {
            Image(systemName: command.symbol)
                .font(.system(size: 12))
                .foregroundStyle(recording ? Color.accentColor : Color.secondary)
                .frame(width: 18)

            Text(command.title)
                .font(.system(size: 13))
                .foregroundStyle(recording ? Color.accentColor : Color.primary)
                .lineLimit(1)

            Spacer(minLength: LatticeTheme.Spacing.sm)

            Button {
                if recording {
                    recorder.cancel()
                } else {
                    pending = nil
                    recorder.begin(command)
                }
            } label: {
                Group {
                    if recording {
                        KeyRecorderField(recorder: recorder, command: command)
                    } else {
                        SettingsKeyChord(combo: combo)
                            .frame(width: 150, alignment: .trailing)
                            .contentShape(Rectangle())
                    }
                }
            }
            .buttonStyle(.plain)
            .help(recording ? "Escape cancels, Delete clears" : "Click to record a new shortcut")
            .accessibilityLabel("Shortcut for \(command.title): \(combo?.display ?? "unbound")")
            .accessibilityHint("Press to record a new shortcut")

            Button {
                if recording { recorder.cancel() }
                apply(command, nil)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .opacity(combo == nil ? 0 : 1)
            .disabled(combo == nil)
            .help("Remove shortcut")
            .accessibilityLabel("Remove shortcut for \(command.title)")
        }
        .frame(height: 34)
        .contentShape(Rectangle())
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

            if pending.conflictingCommand != nil {
                Button("Use anyway") { apply(pending.command, pending.combo) }
                    .controlSize(.small)
                    .accessibilityLabel("Use \(pending.combo.display) anyway")
                Button("Unbind other") { takeOver(pending, unbindingOther: true) }
                    .controlSize(.small)
                    .accessibilityLabel("Unbind the other command and use \(pending.combo.display) here")
            } else {
                Button("Use anyway") { apply(pending.command, pending.combo) }
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

    private func conflictMessage(_ pending: PendingBinding) -> String {
        if let other = pending.conflictingCommand {
            return "\(pending.combo.display) is already used by \(other.title)."
        }
        if let systemName = pending.systemName {
            return "\(pending.combo.display) is macOS \(systemName)."
        }
        return "\(pending.combo.display) is already in use."
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

    private func commit(_ command: CommandID, _ combo: KeyCombo?) {
        guard let combo else {
            apply(command, nil)
            return
        }

        if let other = conflictingCommand(for: combo, excluding: command) {
            animate {
                pending = PendingBinding(command: command, combo: combo, conflictingCommand: other)
            }
            return
        }

        if let system = SettingsSystemShortcuts.conflict(for: combo) {
            animate {
                pending = PendingBinding(command: command, combo: combo, systemName: system.name)
            }
            return
        }

        apply(command, combo)
    }

    private func conflictingCommand(for combo: KeyCombo, excluding command: CommandID) -> CommandID? {
        CommandID.allCases.first { $0 != command && store.prefs.bindings[$0] == combo }
    }

    private func apply(_ command: CommandID, _ combo: KeyCombo?) {
        store.update { prefs in
            if let combo {
                prefs.bindings[command] = combo
            } else {
                prefs.bindings.removeValue(forKey: command)
            }
        }
        animate { pending = nil }
    }

    private func takeOver(_ pending: PendingBinding, unbindingOther: Bool) {
        store.update { prefs in
            if unbindingOther, let other = pending.conflictingCommand {
                prefs.bindings.removeValue(forKey: other)
            }
            prefs.bindings[pending.command] = pending.combo
        }
        animate { self.pending = nil }
    }
}
