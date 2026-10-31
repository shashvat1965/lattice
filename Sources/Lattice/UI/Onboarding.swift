import AppKit
import SwiftUI
import LatticeKit

/// First run, once. One window, no steps, no counter: a permission row that flips to a check,
/// an escape hatch, and one line about what Lattice reads.
@MainActor
final class OnboardingWindowController {

    private static var shared: OnboardingWindowController?
    private let window: NSWindow

    private init(model: AppModel) {
        let size = NSSize(width: 440, height: 420)
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable, .fullSizeContentView],
                          backing: .buffered,
                          defer: false)
        window.title = "Welcome"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.contentMinSize = size
        window.contentMaxSize = size
        window.collectionBehavior = [.moveToActiveSpace, .managed]

        let root = OnboardingView(
            model: model,
            dismiss: { [weak self] in
                PreferencesStore.shared.update { $0.hasCompletedOnboarding = true }
                self?.close()
            }
        )
        window.contentViewController = NSHostingController(rootView: root)
        window.center()
    }

    static func showIfNeeded() {
        let prefs = PreferencesStore.shared.prefs
        guard !prefs.hasCompletedOnboarding || !AppModel.shared.accessibilityGranted else { return }
        show()
    }

    static func show() {
        if shared == nil { shared = OnboardingWindowController(model: .shared) }
        NSApp.activate(ignoringOtherApps: true)
        shared?.window.makeKeyAndOrderFront(nil)
    }

    private func close() {
        window.orderOut(nil)
        NotificationCenter.default.post(name: .latticeShowMainWindow, object: nil)
    }
}

// MARK: - Content

private struct OnboardingView: View {
    @ObservedObject var model: AppModel
    var dismiss: () -> Void

    @State private var requested = false
    @State private var showPrivacy = false

    private var granted: Bool { model.accessibilityGranted }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .padding(.bottom, 18)

            Text("Every window in its place.")
                .font(.system(size: 24, weight: .semibold))
                .padding(.bottom, 6)

            Text("Lattice tiles the Spaces you already use. No config file, no helper, no network access.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 24)

            permissionRow
                .padding(.bottom, 14)

            if !granted {
                Button("Continue without it") {
                    PreferencesStore.shared.update { $0.hasCompletedOnboarding = true }
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                showPrivacy.toggle()
            } label: {
                HStack(spacing: 4) {
                    Text("What Lattice can read")
                        .font(.system(size: 11))
                    Image(systemName: showPrivacy ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)

            if showPrivacy {
                Text("Window positions and titles, so it can place and name each window. Never window contents, never the screen, never the keyboard.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 44)
        .padding(.bottom, 24)
        .frame(width: 440, height: 420, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(LatticeTheme.animation, value: granted)
    }

    private var permissionRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(granted ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                    .frame(width: 30, height: 30)
                Image(systemName: granted ? "checkmark" : "lock.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(granted ? .green : .orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility")
                    .font(.system(size: 13, weight: .medium))
                Text(granted ? "On" : requested ? "Waiting for macOS…" : "Required to move windows")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if !granted {
                Button("Turn on Lattice") {
                    requested = true
                    model.requestAccessibility()
                }
                .controlSize(.regular)
                .buttonStyle(.borderedProminent)
            } else {
                Button("Done", action: dismiss)
                    .controlSize(.regular)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}
