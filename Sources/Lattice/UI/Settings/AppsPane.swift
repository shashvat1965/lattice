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

    var hasAnyEffect: Bool {
        float || unmanaged || layout != nil || spaceNumber != nil
            || !(titleContains ?? "").isEmpty || builtInFloat
    }
}

// MARK: - AppsPane

/// Per-app rules: a real editor, not a text field for bundle identifiers.
/// One row per app, one sheet with every rule that app can carry.
@MainActor
struct AppsPane: View {

    private struct InstalledApp: Identifiable, Hashable {
        var bundleID: String
        var name: String
        var url: URL
        var id: String { bundleID }
    }

    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var store = SettingsPreferences.shared

    @State private var installed: [InstalledApp] = []
    @State private var isLoading = true
    @State private var query = ""
    @State private var editing: AppRuleDraft?

    var body: some View {
        VStack(spacing: 0) {
            paneHeader
            LatticeDivider()
            Form {
                rulesSection
                addSection
            }
            .formStyle(.grouped)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.latticeCanvas)
        .onAppear {
            store.beginObserving()
            model.rebuildWindowCache()
            loadInstalledApps()
        }
        .onDisappear {
            store.endObserving()
        }
        .sheet(item: $editing) { draft in
            AppRuleEditor(
                draft: draft,
                onSave: { save($0) },
                onDelete: { delete($0) }
            )
        }
    }

    private var paneHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Apps")
                .latticeTitle()
            Text("Decide which apps Lattice tiles, and how.")
                .latticeCaption()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, LatticeTheme.gutter)
        .padding(.top, 18)
        .padding(.bottom, LatticeTheme.Spacing.sm)
    }

    // MARK: Rules

    private var rulesSection: some View {
        Section {
            if rules.isEmpty {
                EmptyState(
                    symbol: "app.badge",
                    title: "Every app is tiled",
                    message: "There are no rules yet. Add an app below to float it, leave it alone, or give it its own layout.",
                    compact: true
                )
            } else {
                ForEach(rules) { draft in
                    ruleRow(draft)
                }
            }
        } header: {
            HStack(alignment: .firstTextBaseline) {
                Text("App rules")
                Text("\(rules.count)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Reload apps") { reloadInstalledApps() }
                    .controlSize(.small)
                    .accessibilityLabel("Reload the list of installed applications")
            }
        } footer: {
            Text("Rules are matched by bundle identifier. Leave alone wins over floating. A title match narrows the rule to windows whose title contains that text, so an app can be tiled normally except for one kind of window.")
        }
    }

    private func ruleRow(_ draft: AppRuleDraft) -> some View {
        HStack(spacing: LatticeTheme.Spacing.xs) {
            AppIcon(bundleID: draft.bundleID, appName: draft.name, size: 22)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(draft.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    statusPill(for: draft)
                }

                Text(draft.bundleID)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let detail = detail(for: draft) {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: LatticeTheme.Spacing.sm)

            Button {
                editing = draft
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Edit the rule for \(draft.name)")
            .accessibilityLabel("Edit rules for \(draft.name)")

            Button {
                delete(draft)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help(draft.builtInFloat && !draft.hasRule && !draft.unmanaged
                  ? "Remove this exception and let Lattice tile \(draft.name)"
                  : "Remove the rule for \(draft.name)")
            .accessibilityLabel("Remove the rule for \(draft.name)")
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func statusPill(for draft: AppRuleDraft) -> some View {
        if draft.unmanaged {
            StatusPill(text: "Leave alone", tone: .neutral, symbol: "hand.raised")
        } else if draft.float || draft.builtInFloat {
            StatusPill(text: "Floating", tone: .accent, symbol: "square.on.square")
        } else {
            StatusPill(text: "Tiled", tone: .positive, symbol: "rectangle.split.3x1")
        }
    }

    private func detail(for draft: AppRuleDraft) -> String? {
        var parts: [String] = []
        if let layout = draft.layout { parts.append("\(layout.title) layout") }
        if let space = draft.spaceNumber { parts.append("send to Space \(space)") }
        if let title = draft.titleContains, !title.isEmpty { parts.append("title contains “\(title)”") }
        if draft.builtInFloat, parts.isEmpty { parts.append("built-in exception") }
        if draft.unmanaged, parts.isEmpty { parts.append("Lattice never touches its windows") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Add app

    private var addSection: some View {
        Section {
            searchField

            if isLoading {
                HStack(spacing: LatticeTheme.Spacing.xs) {
                    ProgressView().controlSize(.small)
                    Text("Reading your Applications folders…")
                        .latticeCaption()
                }
                .frame(height: 40)
            } else if candidates.isEmpty {
                Text(query.isEmpty
                     ? "No applications left to add."
                     : "No application matches “\(query)”.")
                    .latticeCaption()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(candidates) { app in
                            addRow(app)
                            if app.id != candidates.last?.id {
                                LatticeDivider(insetLeading: 34)
                            }
                        }
                    }
                }
                .frame(height: 216)
                .background(
                    RoundedRectangle(cornerRadius: LatticeTheme.Radius.md, style: .continuous)
                        .fill(Color.latticeCardFill.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: LatticeTheme.Radius.md, style: .continuous)
                        .strokeBorder(Color.latticeHairline, lineWidth: LatticeTheme.hairline)
                )
            }
        } header: {
            Text("Add an app…")
        } footer: {
            Text("Read from /Applications and /System/Applications. Only apps with a bundle identifier can be added. Menu bar apps and system agents work too — they simply have no standard window to tile.")
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search applications", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .accessibilityLabel("Search applications to add")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear application search")
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

    private func addRow(_ app: InstalledApp) -> some View {
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
            HStack(spacing: LatticeTheme.Spacing.xs) {
                AppIcon(bundleID: app.bundleID, appName: app.name, size: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                    Text(app.bundleID)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: LatticeTheme.Spacing.xs)

                Image(systemName: "plus.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, LatticeTheme.Spacing.xs)
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Add a rule for \(app.name)")
        .accessibilityLabel("Add a rule for \(app.name)")
    }

    // MARK: Data

    private var rules: [AppRuleDraft] {
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

    private var candidates: [InstalledApp] {
        let configured = Set(rules.map(\.bundleID))
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return installed.filter { app in
            guard !configured.contains(app.bundleID) else { return false }
            guard !needle.isEmpty else { return true }
            return app.name.lowercased().contains(needle)
                || app.bundleID.lowercased().contains(needle)
        }
    }

    // MARK: Writes

    private func save(_ draft: AppRuleDraft) {
        store.update { prefs in
            if draft.unmanaged {
                prefs.unmanagedBundleIDs.insert(draft.bundleID)
            } else {
                prefs.unmanagedBundleIDs.remove(draft.bundleID)
            }

            // Turning floating off for an app that was floating by default has to
            // remove the built-in exception, or it would float again on the next pass.
            if !draft.float, draft.builtInFloat {
                prefs.floatBundleIDs.remove(draft.bundleID)
            }

            var rule = prefs.rule(for: draft.bundleID)
                ?? AppRule(bundleID: draft.bundleID, name: draft.name)
            rule.name = draft.name
            rule.unmanaged = draft.unmanaged
            rule.float = draft.float && !draft.unmanaged
            rule.layout = draft.layout
            rule.spaceNumber = draft.spaceNumber
            let title = (draft.titleContains ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            rule.titleContains = title.isEmpty ? nil : title

            let empty = !rule.float && !rule.unmanaged
                && rule.layout == nil && rule.spaceNumber == nil && rule.titleContains == nil

            prefs.rules.removeAll { $0.bundleID == draft.bundleID }
            if !empty {
                prefs.rules.append(rule)
            }
        }
    }

    private func delete(_ draft: AppRuleDraft) {
        store.update { prefs in
            if draft.hasRule || draft.unmanaged {
                prefs.rules.removeAll { $0.bundleID == draft.bundleID }
                prefs.unmanagedBundleIDs.remove(draft.bundleID)
            } else {
                // A built-in exception with no rule of its own: removing it means
                // "let Lattice tile this app".
                prefs.floatBundleIDs.remove(draft.bundleID)
            }
        }
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

    private func reloadInstalledApps() {
        isLoading = true
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
        .frame(width: 520, height: 590)
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
                    .accessibilityHint("Keep its windows out of the tiling layout")

                Toggle("Leave this app alone", isOn: $unmanaged)
                    .toggleStyle(.switch)
                    .accessibilityLabel("Leave \(draft.name) alone")
                    .accessibilityHint("Lattice will not read or move any of its windows")
            } header: {
                Text("Behaviour")
            } footer: {
                Text(unmanaged
                     ? "Lattice will not touch this app's windows at all. This wins over floating."
                     : "Floating keeps windows where you put them. Leaving an app alone means Lattice ignores it entirely, including new windows.")
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
            } footer: {
                Text("A layout override only applies on displays where this app is tiled. Sending to a Space happens the first time a window from this app appears. A title match narrows every rule above to matching windows.")
            }
        }
        .formStyle(.grouped)
    }

    private var footer: some View {
        HStack(spacing: LatticeTheme.Spacing.xs) {
            if draft.hasRule || draft.builtInFloat || draft.unmanaged {
                Button(isBuiltInOnly ? "Tile This App" : "Remove Rule", role: .destructive) {
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
