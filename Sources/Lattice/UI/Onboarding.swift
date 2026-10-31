import SwiftUI
import AppKit
import LatticeKit

// MARK: - OnboardingWindowController

/// The first-run window. Separate from the main window on purpose: it is a short,
/// linear conversation, not a tab. Dismissible at any time with the close button or Esc.
@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {

    private static var current: OnboardingWindowController?

    static func show() {
        if current == nil {
            current = OnboardingWindowController(model: .shared)
        }
        guard let controller = current else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller.window?.center()
        controller.window?.makeKeyAndOrderFront(nil)
    }

    /// First-run gate: no completed onboarding, or no Accessibility grant yet.
    static func showIfNeeded() {
        let prefs = PreferencesStore.shared.prefs
        guard !prefs.hasCompletedOnboarding || !AppModel.shared.accessibilityGranted else { return }
        show()
    }

    private let model: AppModel

    init(model: AppModel) {
        self.model = model

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Lattice"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        // The conversation is a fixed size: nothing inside it reflows with the window.
        window.contentMinSize = NSSize(width: 560, height: 600)
        window.contentMaxSize = NSSize(width: 560, height: 600)
        window.center()

        super.init(window: window)

        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: OnboardingFlow(
                model: model,
                onClose: { [weak self] in self?.close() },
                onOpenShortcuts: { Self.openShortcuts() },
                onFinish: { [weak self] in
                    self?.close()
                    NotificationCenter.default.post(name: .latticeShowMainWindow, object: nil)
                }
            )
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func close() {
        super.close()
        Self.current = nil
    }

    func windowWillClose(_ notification: Notification) {
        Self.current = nil
    }

    private static func openShortcuts() {
        if let delegate = AppDelegate.shared {
            delegate.showMainWindow(tab: .shortcuts)
        } else {
            NotificationCenter.default.post(name: .latticeShowMainWindow, object: nil)
        }
    }
}

// MARK: - Flow

@MainActor
struct OnboardingFlow: View {

    @ObservedObject var model: AppModel
    var onClose: () -> Void
    var onOpenShortcuts: () -> Void
    var onFinish: () -> Void

    @State private var step = 0
    @State private var showWhy = false
    /// True once the user has asked macOS for the grant, so the banner can show the
    /// live "waiting" state instead of the untouched "needed" state.
    @State private var requestedAccess = false

    /// The grant is read live from TCC; one tick a second is enough to feel immediate.
    private let permissionPoll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private let gutter: CGFloat = 24
    private let bodyWidth: CGFloat = 512

    private var animation: Animation? { LatticeTheme.animation }

    var body: some View {
        ZStack {
            OnboardingMaterialView()
                .ignoresSafeArea()
            Color(nsColor: .windowBackgroundColor)
                .opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Clears the traffic lights; the title bar itself stays invisible.
                Color.clear
                    .frame(height: 30)

                Group {
                    switch step {
                    case 0: welcomeStep
                    case 1: permissionStep
                    default: keysStep
                    }
                }
                .id(step)
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, LatticeTheme.Spacing.md)
                .padding(.horizontal, gutter)

                footer
            }
        }
        .frame(width: 560, height: 600)
        .onExitCommand(perform: onClose)
        .onAppear { model.refreshPermissions() }
        .onReceive(permissionPoll) { _ in
            model.refreshPermissions()
            if model.accessibilityGranted { model.bootstrap() }
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 0) {
            LatticeDivider()
            HStack(spacing: LatticeTheme.Spacing.sm) {
                if step > 0 {
                    Button {
                        goBack()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .font(.system(size: 12))
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Back")
                }

                Text("Step \(step + 1) of 3")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()

                Spacer(minLength: LatticeTheme.Spacing.sm)

                secondaryAction
                primaryAction
            }
            .padding(.horizontal, gutter)
            .padding(.vertical, 14)
        }
    }

    @ViewBuilder
    private var secondaryAction: some View {
        switch step {
        case 1 where !model.accessibilityGranted:
            quietButton("Not now") { advance() }
                .accessibilityLabel("Continue without Accessibility")
                .accessibilityHint("Tiling stays off until you grant access in System Settings")
        case 2:
            quietButton("Open all shortcuts") { onOpenShortcuts() }
                .accessibilityLabel("Open every shortcut in the main window")
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch step {
        case 0:
            primaryButton("Continue") { advance() }
                .accessibilityLabel("Continue to Accessibility permission")
        case 1:
            primaryButton("Continue", enabled: model.accessibilityGranted) { advance() }
                .accessibilityLabel("Continue to shortcuts")
        default:
            primaryButton("Start tiling") { finish() }
                .accessibilityLabel("Start tiling and close this window")
        }
    }

    private func primaryButton(_ title: String,
                               enabled: Bool = true,
                               action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!enabled)
    }

    private func quietButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderless)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .frame(minHeight: 28)
            .contentShape(Rectangle())
    }

    // MARK: Step 1 — welcome

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            LatticeBrandMark(size: 88)

            Text("Welcome to Lattice")
                .font(.system(size: 26, weight: .semibold))
                .tracking(-0.35)
                .padding(.top, 24)

            Text("Lattice arranges every window on your Mac — on the Spaces you already use.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)
                .padding(.top, LatticeTheme.Spacing.xs)

            whatItDoes
                .padding(.top, 28)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var whatItDoes: some View {
        VStack(alignment: .leading, spacing: 10) {
            featureRow("rectangle.split.3x1", "Tiles every window on the Space you are on.")
            featureRow("keyboard", "Moves and resizes with the keyboard, not the mouse.")
            featureRow("rectangle.on.rectangle", "Remembers a layout for each Space and display.")
        }
        .frame(maxWidth: 380, alignment: .leading)
    }

    private func featureRow(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 16, alignment: .center)
            Text(text)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Step 2 — permission

    private var permissionStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Grant Accessibility")
                .font(.system(size: 24, weight: .semibold))
                .tracking(-0.3)

            Text("Lattice moves other apps' windows through macOS Accessibility, which you grant once — tiling starts the moment it is on.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            permissionState
                .padding(.top, LatticeTheme.Spacing.lg)
                .animation(animation, value: model.accessibilityGranted)

            whyDisclosure
                .padding(.top, 14)
        }
        .frame(maxWidth: bodyWidth, alignment: .leading)
    }

    @ViewBuilder
    private var permissionState: some View {
        if model.accessibilityGranted {
            grantedBanner
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        } else {
            PermissionBanner(
                onOpenSettings: {
                    withAnimation(animation) { requestedAccess = true }
                    SettingsLinks.openAccessibilitySettings()
                },
                onRequest: {
                    withAnimation(animation) { requestedAccess = true }
                    model.requestAccessibility()
                }
            )
            .overlay(alignment: .bottomTrailing) {
                if requestedAccess {
                    waitingPill
                        .padding(.trailing, LatticeTheme.Spacing.md)
                        .padding(.bottom, LatticeTheme.Spacing.md)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
        }
    }

    /// The live state that lives inside the banner while TCC has not answered yet.
    private var waitingPill: some View {
        HStack(spacing: 5) {
            ProgressView()
                .controlSize(.mini)
            Text("Waiting for macOS…")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background {
            Capsule(style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.latticeHairline, lineWidth: LatticeTheme.hairline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Waiting for macOS to grant Accessibility")
    }

    private var grantedBanner: some View {
        HStack(spacing: LatticeTheme.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(Color(nsColor: .systemGreen))
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 28, height: 28)
            .transition(.scale(scale: 0.5).combined(with: .opacity))

            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility is on")
                    .font(.system(size: 13, weight: .semibold))
                Text("Lattice can move windows now. There is nothing else to do here.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(LatticeTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: LatticeTheme.Radius.lg, style: .continuous)
            shape
                .fill(Color(nsColor: .systemGreen).opacity(0.10))
                .overlay {
                    shape.strokeBorder(Color(nsColor: .systemGreen).opacity(0.34),
                                       lineWidth: LatticeTheme.hairline * 2)
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Accessibility is on. Lattice can move windows now, nothing else is needed.")
    }

    private var whyDisclosure: some View {
        DisclosureGroup(isExpanded: $showWhy) {
            Text("Lattice reads window frames and titles so it can place each window and name it. It never reads what is inside a window, never captures the screen, and contains no network code.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        } label: {
            Text("Why does Lattice need this?")
                .font(.system(size: 12))
        }
        .accessibilityLabel("Why does Lattice need Accessibility")
    }

    // MARK: Step 3 — keys

    private var keysStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Set your keys")
                .font(.system(size: 24, weight: .semibold))
                .tracking(-0.3)

            Text("The six you will reach for most — focus, move, layout and the command palette. Every other shortcut lives in Shortcuts.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            Card(padding: LatticeTheme.Spacing.xs, elevated: false) {
                VStack(spacing: 0) {
                    keyRow(.focusLeft)
                    LatticeDivider(insetLeading: 26)
                    keyRow(.moveLeft)
                    LatticeDivider(insetLeading: 26)
                    keyRow(.nextSpace)
                    LatticeDivider(insetLeading: 26)
                    keyRow(.toggleFloat)
                    LatticeDivider(insetLeading: 26)
                    keyRow(.cycleLayout)
                    LatticeDivider(insetLeading: 26)
                    keyRow(.commandPalette)
                }
            }
            .padding(.top, LatticeTheme.Spacing.lg)
        }
        .frame(maxWidth: bodyWidth, alignment: .leading)
    }

    private func keyRow(_ command: CommandID) -> some View {
        HStack(spacing: LatticeTheme.Spacing.xs) {
            Image(systemName: command.symbol)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(command.title)
                .font(.system(size: 13))
            Spacer(minLength: LatticeTheme.Spacing.sm)
            SettingsKeyChord(combo: PreferencesStore.shared.prefs.bindings[command])
        }
        .frame(height: 34)
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(command.title): \(PreferencesStore.shared.prefs.bindings[command]?.display ?? "not assigned")")
    }

    // MARK: Navigation & actions

    private func advance() {
        guard step < 2 else { return }
        withAnimation(animation) { step += 1 }
    }

    private func goBack() {
        guard step > 0 else { return }
        withAnimation(animation) { step -= 1 }
    }

    private func finish() {
        SettingsPreferences.shared.update { $0.hasCompletedOnboarding = true }
        model.setEnabled(true)
        onFinish()
    }
}

// MARK: - Material background

struct OnboardingMaterialView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blending
    }
}
