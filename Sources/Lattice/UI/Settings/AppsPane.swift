import SwiftUI
import AppKit
import LatticeKit

// MARK: - Rule draft
//
// One editable view of an app. It is built from every source a rule can live in:
// `prefs.rules`, the legacy `unmanagedBundleIDs` set and the built-in float set.

private struct AppRuleDraft: Identifiable {
    var bundleID: String
    var name: String
    var float: Bool
    var unmanaged: Bool
    var layout: LayoutKind?
    var spaceNumber: Int?
    var titleContains: String?
    var builtInFloat: Bool
    var hasRule: Bool

    var id: String { bundleID }

    var status: (text: String, tone: StatusPill.Tone, symbol: String) {
        if unmanaged { return ("Leave alone", .neutral, "hand.raised") }
        if float || builtInFloat { return ("Floating", .accent, "square.on.square") }
        return ("Tiled", .positive, "rectangle.split.3x1")
    }

    var summary: String {
        var parts: [String] = []
        if let layout { parts.append("\(layout.title) layout") }
        if let spaceNumber { parts.append("Space \(spaceNumber)") }
        if let titleContains, !titleContains.isEmpty { parts.append("Title contains “\(titleContains)”") }
        if parts.isEmpty {
            parts.append(builtInFloat ? "Built-in exception" : "Uses the Space's layout")
        }
        return parts.joined(separator: " · ")
    }
}

private struct InstalledApp: Identifiable, Hashable {
    var bundleID: String
    var name: String
    var url: URL
    var id: String { bundleID }
}

// MARK: - Settings › Apps

/// Every app whose windows are treated differently, in one list. Floating and leaving
/// alone are the same table, so an app is never shown twice. One search field filters
/// this list and adds from Applications.
@MainActor
struct SettingsAppsSection: View {

    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var store = SettingsPreferences.shared

    @State private var installed: [InstalledApp] = []
    @State private var isLoading = true
    @State private var query = ""
    @State private var editing: AppRuleDraft?

    var body: some View {
        SettingsSection("Apps", subtitle: "Leave alone wins over floating.") {
            searchRow

            let rows = filteredRules

            if rows.isEmpty, addCandidates.isEmpty {
                SettingsContentRow(showsDivider: false) {
                    InlineHint(
                        text: query.isEmpty
                            ? "Every app is tiled."
                            : "No app matches “\(query)”.",
                        symbol: "app.badge"
                    )
                }
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, draft in
                    ruleRow(draft, showsDivider: index < rows.count - 1 || !addCandidates.isEmpty)
                }
            }

            ForEach(Array(addCandidates.enumerated()), id: \.element.id) { index, app in
                addRow(app, showsDivider: index < addCandidates.count - 1)
            }
        }
        .sheet(item: $editing) { draft in
            AppRuleEditor(
                draft: draft,
                onSave: { save($0) },
                onDelete: { delete($0) }
            )
        }
        .onAppear { loadInstalledApps() }
    }

    // MARK: Search

    private var searchRow: some View {
        SettingsContentRow(showsDivider: true) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Search apps, or add one", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .accessibilityLabel("Search apps, or add one")

                if isLoading {
                    ProgressView().controlSize(.small)
                } else if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear the app search")
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
    }

    // MARK: Rows

    private func ruleRow(_ draft: AppRuleDraft, showsDivider: Bool) -> some View {
        HStack(spacing: LatticeTheme.Spacing.sm) {
            AppIcon(bundleID: draft.bundleID, appName: draft.name, size: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(draft.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    StatusPill(text: draft.status.text, tone: draft.status.tone, symbol: draft.status.symbol)
                }

                Text(draft.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: LatticeTheme.Spacing.sm)

            rowMenu(draft)
        }
        .padding(.horizontal, LatticeTheme.Spacing.md)
        .frame(minHeight: 52)
        .accessibilityElement(children: .contain)
        .overlay(alignment: .bottom) {
            if showsDivider {
                LatticeDivider(insetLeading: LatticeTheme.Spacing.md)
            }
        }
    }

    private func rowMenu(_ draft: AppRuleDraft) -> some View {
        Menu {
            Button("Tile it") { setBehaviour(.tiled, for: draft) }
            Button("Float it") { setBehaviour(.floating, for: draft) }
            Button("Leave it alone") { setBehaviour(.leaveAlone, for: draft) }

            Divider()

            Menu("Layout") {
                checkable("Use the Space's layout", selected: draft.layout == nil) {
                    setLayout(nil, for: draft)
                }
                Divider()
                ForEach(LayoutKind.allCases) { kind in
                    checkable(kind.title, selected: draft.layout == kind) {
                        setLayout(kind, for: draft)
                    }
                }
            }

            Menu("Send to Space") {
                checkable("Don't move it", selected: draft.spaceNumber == nil) {
                    setSpace(nil, for: draft)
                }
                Divider()
                ForEach(1...9, id: \.self) { number in
                    checkable("Space \(number)", selected: draft.spaceNumber == number) {
                        setSpace(number, for: draft)
                    }
                }
            }

            Divider()

            Button("Title contains…") { editing = draft }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Change how \(draft.name) is handled")
        .accessibilityLabel("Options for \(draft.name)")
    }

    @ViewBuilder
    private func checkable(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if selected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private func addRow(_ app: InstalledApp, showsDivider: Bool) -> some View {
        Button {
            editing = AppRuleDraft(
                bundleID: app.bundleID,
                name: app.name,
                float: false,
                unmanaged: false,
                layout: nil,
                spaceNumber: nil,
                titleContains: nil,
                builtInFloat: false,
                hasRule: false
            )
        } label: {
            HStack(spacing: LatticeTheme.Spacing.sm) {
                AppIcon(bundleID: app.bundleID, appName: app.name, size: 22)

                Text(app.name)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: LatticeTheme.Spacing.sm)

                Image(systemName: "plus.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, LatticeTheme.Spacing.md)
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Add a rule for \(app.name)")
        .accessibilityLabel("Add a rule for \(app.name)")
        .overlay(alignment: .bottom) {
            if showsDivider {
                LatticeDivider(insetLeading: LatticeTheme.Spacing.md)
            }
        }
    }

    // MARK: Data

    private var allRules: [AppRuleDraft] {
        var ids = Set(store.prefs.rules.map(\.bundleID))
        ids.formUnion(store.prefs.unmanagedBundleIDs)
        ids.formUnion(store.prefs.floatBundleIDs)

        return ids.map { bundleID in
            let rule = store.prefs.rule(for: bundleID)
            return AppRuleDraft(
                bundleID: bundleID,
                name: SettingsAppNames.name(for: bundleID),
                float: rule?.float ?? false,
                unmanaged: rule?.unmanaged ?? store.prefs.unmanagedBundleIDs.contains(bundleID),
                layout: rule?.layout,
                spaceNumber: rule?.spaceNumber,
                titleContains: rule?.titleContains,
                builtInFloat: store.prefs.floatBundleIDs.contains(bundleID),
                hasRule: rule != nil
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredRules: [AppRuleDraft] {
        let needle = trimmedQuery.lowercased()
        guard !needle.isEmpty else { return allRules }
        return allRules.filter { draft in
            draft.name.lowercased().contains(needle)
                || draft.bundleID.lowercased().contains(needle)
                || (draft.titleContains ?? "").lowercased().contains(needle)
        }
    }

    /// Apps that match the search but have no rule yet. Nothing is listed until you type.
    private var addCandidates: [InstalledApp] {
        let needle = trimmedQuery.lowercased()
        guard !needle.isEmpty else { return [] }
        let configured = Set(allRules.map(\.bundleID))
        return installed
            .filter { app in
                !configured.contains(app.bundleID)
                    && (app.name.lowercased().contains(needle)
                        || app.bundleID.lowercased().contains(needle))
            }
            .prefix(6)
            .map { $0 }
    }

    // MARK: Writes

    private enum Behaviour {
        case tiled, floating, leaveAlone
    }

    private func setBehaviour(_ behaviour: Behaviour, for draft: AppRuleDraft) {
        withRule(draft) { rule, prefs in
            switch behaviour {
            case .tiled:
                rule.float = false
                rule.unmanaged = false
                prefs.unmanagedBundleIDs.remove(draft.bundleID)
                prefs.floatBundleIDs.remove(draft.bundleID)
            case .floating:
                rule.float = true
                rule.unmanaged = false
                prefs.unmanagedBundleIDs.remove(draft.bundleID)
            case .leaveAlone:
                rule.float = false
                rule.unmanaged = true
                prefs.unmanagedBundleIDs.insert(draft.bundleID)
            }
        }
    }

    private func setLayout(_ kind: LayoutKind?, for draft: AppRuleDraft) {
        withRule(draft) { rule, _ in rule.layout = kind }
    }

    private func setSpace(_ number: Int?, for draft: AppRuleDraft) {
        withRule(draft) { rule, _ in rule.spaceNumber = number }
    }

    /// Writes one rule through PreferencesStore, keeping the legacy `unmanagedBundleIDs`
    /// set in step, and drops the rule when it would no longer do anything.
    private func withRule(_ draft: AppRuleDraft,
                          _ change: (inout AppRule, inout Preferences) -> Void) {
        store.update { prefs in
            var rule = prefs.rule(for: draft.bundleID)
                ?? AppRule(bundleID: draft.bundleID, name: draft.name)
            rule.name = draft.name
            rule.float = draft.float
            rule.unmanaged = draft.unmanaged
            rule.layout = draft.layout
            rule.spaceNumber = draft.spaceNumber
            let title = (draft.titleContains ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            rule.titleContains = title.isEmpty ? nil : title

            change(&rule, &prefs)

            if rule.unmanaged {
                prefs.unmanagedBundleIDs.insert(draft.bundleID)
            } else {
                prefs.unmanagedBundleIDs.remove(draft.bundleID)
            }

            prefs.rules.removeAll { $0.bundleID == draft.bundleID }

            let keepsSomething = rule.float || rule.unmanaged || rule.layout != nil
                || rule.spaceNumber != nil || rule.titleContains != nil
            if keepsSomething {
                prefs.rules.append(rule)
            }
        }
        model.tiler.reconcile()
    }

    private func save(_ draft: AppRuleDraft) {
        let title = (draft.titleContains ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let edited = AppRuleDraft(
            bundleID: draft.bundleID,
            name: draft.name,
            float: draft.float,
            unmanaged: draft.unmanaged,
            layout: draft.layout,
            spaceNumber: draft.spaceNumber,
            titleContains: title.isEmpty ? nil : title,
            builtInFloat: draft.builtInFloat,
            hasRule: draft.hasRule
        )

        withRule(edited) { rule, prefs in
            if edited.unmanaged {
                prefs.unmanagedBundleIDs.insert(edited.bundleID)
            } else {
                prefs.unmanagedBundleIDs.remove(edited.bundleID)
            }
            // Turning floating off for an app that floated by default has to remove the
            // built-in exception, or it would float again on the next pass.
            if !edited.float, edited.builtInFloat {
                prefs.floatBundleIDs.remove(edited.bundleID)
            }
        }
    }

    private func delete(_ draft: AppRuleDraft) {
        store.update { prefs in
            prefs.rules.removeAll { $0.bundleID == draft.bundleID }
            prefs.unmanagedBundleIDs.remove(draft.bundleID)
            // A built-in exception with no rule of its own means "let Lattice tile it".
            prefs.floatBundleIDs.remove(draft.bundleID)
        }
        model.tiler.reconcile()
    }

    // MARK: Installed apps

    private func loadInstalledApps() {
        guard installed.isEmpty, isLoading else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let apps = Self.scanApplications()
            DispatchQueue.main.async {
                self.installed = apps
                self.isLoading = false
            }
        }
    }

    private static func scanApplications() -> [InstalledApp] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let roots = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            home + "/Applications",
        ]

        var seen = Set<String>()
        var out: [InstalledApp] = []
        let ownBundleID = Bundle.main.bundleIdentifier

        for root in roots {
            guard let entries = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let url = URL(fileURLWithPath: root).appendingPathComponent(entry)
                guard let bundle = Bundle(url: url),
                      let bundleID = bundle.bundleIdentifier,
                      bundleID != ownBundleID,
                      seen.insert(bundleID).inserted else { continue }

                let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? entry.replacingOccurrences(of: ".app", with: "")
                out.append(InstalledApp(bundleID: bundleID, name: name, url: url))
            }
        }

        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Rule editor sheet

private struct AppRuleEditor: View {
    let draft: AppRuleDraft
    let onSave: (AppRuleDraft) -> Void
    let onDelete: (AppRuleDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var float: Bool
    @State private var unmanaged: Bool
    @State private var layout: LayoutKind?
    @State private var spaceNumber: Int?
    @State private var titleContains: String

    init(draft: AppRuleDraft,
         onSave: @escaping (AppRuleDraft) -> Void,
         onDelete: @escaping (AppRuleDraft) -> Void) {
        self.draft = draft
        self.onSave = onSave
        self.onDelete = onDelete
        _float = State(initialValue: !draft.unmanaged
            && (draft.float || (draft.builtInFloat && !draft.hasRule)))
        _unmanaged = State(initialValue: draft.unmanaged)
        _layout = State(initialValue: draft.layout)
        _spaceNumber = State(initialValue: draft.spaceNumber)
        _titleContains = State(initialValue: draft.titleContains ?? "")
    }

    private var isBuiltInOnly: Bool {
        draft.builtInFloat && !draft.hasRule && !draft.unmanaged
    }

    private var canSave: Bool {
        float || unmanaged || layout != nil || spaceNumber != nil
            || !trimmedTitle.isEmpty || (draft.builtInFloat && !draft.hasRule)
    }

    private var trimmedTitle: String {
        titleContains.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            LatticeDivider()
            form
            LatticeDivider()
            footer
        }
        .frame(width: 520, height: 470)
        .background(Color.latticeCanvas)
        .onChange(of: unmanaged) { _, isUnmanaged in
            if isUnmanaged { float = false }
        }
    }

    private var header: some View {
        HStack(spacing: LatticeTheme.Spacing.sm) {
            AppIcon(bundleID: draft.bundleID, appName: draft.name, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(draft.name)
                    .font(.system(size: 17, weight: .semibold))
                Text(draft.bundleID)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: LatticeTheme.Spacing.sm)

            if draft.builtInFloat, !draft.hasRule {
                StatusPill(text: "Built-in exception", tone: .neutral, symbol: "shippingbox")
            }
        }
        .padding(.horizontal, LatticeTheme.Spacing.lg)
        .padding(.vertical, LatticeTheme.Spacing.md)
    }

    private var form: some View {
        Form {
            Section {
                Toggle("Float this app", isOn: $float)
                    .toggleStyle(.switch)
                    .disabled(unmanaged)
                    .accessibilityLabel("Float \(draft.name)")

                Toggle("Leave this app alone", isOn: $unmanaged)
                    .toggleStyle(.switch)
                    .accessibilityLabel("Leave \(draft.name) alone")
            } header: {
                Text("Behaviour")
            }

            Section {
                Picker("Layout", selection: $layout) {
                    Text("Use the Space's layout").tag(LayoutKind?.none)
                    ForEach(LayoutKind.allCases) { kind in
                        Text(kind.title).tag(Optional(kind))
                    }
                }
                .disabled(unmanaged)
                .accessibilityLabel("Layout override for \(draft.name)")

                Picker("Send to Space", selection: $spaceNumber) {
                    Text("Don't move it").tag(Int?.none)
                    ForEach(1...9, id: \.self) { number in
                        Text("Space \(number)").tag(Optional(number))
                    }
                }
                .disabled(unmanaged)
                .accessibilityLabel("Send \(draft.name) to a Space when it appears")

                TextField("Title contains", text: $titleContains, prompt: Text("e.g. Picture in Picture"))
                    .disabled(unmanaged)
                    .accessibilityLabel("Only apply this rule to windows whose title contains")
            } header: {
                Text("Placement")
            }
        }
        .formStyle(.grouped)
    }

    private var footer: some View {
        HStack(spacing: LatticeTheme.Spacing.xs) {
            if draft.hasRule || draft.builtInFloat || draft.unmanaged {
                Button(isBuiltInOnly ? "Tile this app" : "Remove rule", role: .destructive) {
                    onDelete(draft)
                    dismiss()
                }
                .controlSize(.regular)
                .accessibilityLabel(isBuiltInOnly
                                    ? "Remove the exception and let Lattice tile \(draft.name)"
                                    : "Remove the rule for \(draft.name)")
            }

            Spacer(minLength: LatticeTheme.Spacing.sm)

            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .controlSize(.regular)
                .accessibilityLabel("Cancel")

            Button("Save") {
                onSave(AppRuleDraft(
                    bundleID: draft.bundleID,
                    name: draft.name,
                    float: float,
                    unmanaged: unmanaged,
                    layout: layout,
                    spaceNumber: spaceNumber,
                    titleContains: trimmedTitle.isEmpty ? nil : trimmedTitle,
                    builtInFloat: draft.builtInFloat,
                    hasRule: draft.hasRule
                ))
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(!canSave)
            .accessibilityLabel("Save the rule for \(draft.name)")
        }
        .padding(.horizontal, LatticeTheme.Spacing.lg)
        .padding(.vertical, LatticeTheme.Spacing.sm)
        .background(.bar)
    }
}

// MARK: - AppsPane
//
// The shell still has an Apps sidebar row, so this pane stays alive as the same section
// rather than a second copy of the controls. There is one implementation, in Settings.

@MainActor
struct AppsPane: View {

    @ObservedObject private var store = SettingsPreferences.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LatticeTheme.Spacing.xl) {
                Text("Apps")
                    .latticeTitle()

                SettingsAppsSection()
            }
            .frame(maxWidth: 880, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, LatticeTheme.gutter)
            .padding(.top, 18)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.latticeCanvas)
        .onAppear { store.beginObserving() }
        .onDisappear { store.endObserving() }
    }
}

// MARK: - App name resolution

enum SettingsAppNames {
    /// The name a person would recognise for a bundle id, without inventing one.
    static func name(for bundleID: String) -> String {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let localized = running.localizedName {
            return localized
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: url) {
            if let display = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
                return display
            }
            if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
                return name
            }
            return url.deletingPathExtension().lastPathComponent
        }
        return bundleID
    }
}
