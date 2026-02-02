import SwiftUI
import AppKit

/// Guided permission onboarding that requests permissions one at a time
struct PermissionOnboardingView: View {
    @ObservedObject private var permissionManager = PermissionManager.shared
    @State private var currentStep: PermissionStep = .screenRecording
    let onComplete: () -> Void

    enum PermissionStep {
        case screenRecording
        case accessibility
        case complete
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Content based on current step
            switch currentStep {
            case .screenRecording:
                screenRecordingStep
            case .accessibility:
                accessibilityStep
            case .complete:
                completeStep
            }
        }
        .frame(width: 480, height: 440)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            permissionManager.startMonitoring()
            updateStep()
        }
        .onDisappear {
            permissionManager.stopMonitoring()
        }
        .onChange(of: permissionManager.isScreenRecordingGranted) { _ in
            updateStep()
        }
        .onChange(of: permissionManager.isAccessibilityGranted) { _ in
            updateStep()
        }
    }

    private func updateStep() {
        if !permissionManager.isScreenRecordingGranted {
            currentStep = .screenRecording
        } else if !permissionManager.isAccessibilityGranted {
            currentStep = .accessibility
        } else {
            currentStep = .complete
            // Auto-close after a brief delay when complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                onComplete()
            }
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack(spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("DodoShot setup")
                    .font(.system(size: 18, weight: .semibold))

                Text("Step \(stepNumber) of 2")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Progress indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(permissionManager.isScreenRecordingGranted ? Color.green : Color.purple)
                    .frame(width: 8, height: 8)

                Circle()
                    .fill(permissionManager.isAccessibilityGranted ? Color.green : (currentStep == .accessibility ? Color.purple : Color.gray.opacity(0.3)))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(20)
    }

    private var stepNumber: Int {
        switch currentStep {
        case .screenRecording: return 1
        case .accessibility: return 2
        case .complete: return 2
        }
    }

    // MARK: - Screen Recording Step
    private var screenRecordingStep: some View {
        VStack(spacing: 20) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: "rectangle.dashed.badge.record")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(.purple)
            }

            // Title and description
            VStack(spacing: 8) {
                Text("Screen recording")
                    .font(.system(size: 20, weight: .semibold))

                Text("DodoShot needs screen recording permission to capture screenshots of your screen.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            Spacer()

            // Action button
            Button(action: {
                permissionManager.requestScreenRecordingPermission()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "gear")
                        .font(.system(size: 14, weight: .medium))
                    Text("Open system settings")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.purple)
                )
            }
            .buttonStyle(.plain)

            // Help text
            VStack(spacing: 4) {
                Text("Enable DodoShot in Privacy & Security → Screen Recording")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text("After enabling, restart DodoShot for changes to take effect")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
            }

            Spacer()
        }
        .padding(20)
    }

    // MARK: - Accessibility Step
    private var accessibilityStep: some View {
        VStack(spacing: 20) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: "keyboard")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(.blue)
            }

            // Title and description
            VStack(spacing: 8) {
                Text("Accessibility")
                    .font(.system(size: 20, weight: .semibold))

                Text("DodoShot needs accessibility permission to enable global keyboard shortcuts.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            Spacer()

            // Action buttons
            VStack(spacing: 12) {
                Button(action: {
                    permissionManager.requestAccessibilityPermission()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "hand.raised")
                            .font(.system(size: 14, weight: .medium))
                        Text("Request permission")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue)
                    )
                }
                .buttonStyle(.plain)

                Button(action: {
                    permissionManager.openAccessibilitySettings()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "gear")
                            .font(.system(size: 13, weight: .medium))
                        Text("Open system settings")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }

            // Help text
            VStack(spacing: 4) {
                Text("Enable DodoShot in Accessibility settings")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text("You may need to use the '+' button to add DodoShot manually")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .multilineTextAlignment(.center)

            Spacer()

            // Skip button
            Button(action: {
                // For debug builds, bypass the accessibility check
                permissionManager.bypassAccessibilityForDebug()
                onComplete()
            }) {
                Text("Skip for now (keyboard shortcuts won't work)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }

    // MARK: - Complete Step
    private var completeStep: some View {
        VStack(spacing: 20) {
            Spacer()

            // Success icon
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundColor(.green)
            }

            // Title and description
            VStack(spacing: 8) {
                Text("You're all set!")
                    .font(.system(size: 20, weight: .semibold))

                Text("DodoShot is ready to use. Click the menu bar icon or use keyboard shortcuts to capture screenshots.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            Spacer()

            // Keyboard shortcuts hint
            VStack(spacing: 6) {
                HStack(spacing: 20) {
                    shortcutHint(shortcut: "⌘⇧4", label: "Area")
                    shortcutHint(shortcut: "⌘⇧5", label: "Window")
                    shortcutHint(shortcut: "⌘⇧3", label: "Fullscreen")
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.05))
            )

            Spacer()
        }
        .padding(20)
    }

    private func shortcutHint(shortcut: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(shortcut)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Permission Onboarding Window Controller
class PermissionOnboardingWindowController {
    static let shared = PermissionOnboardingWindowController()

    private var window: NSWindow?

    private init() {}

    func showIfNeeded(completion: @escaping () -> Void) {
        let permissionManager = PermissionManager.shared
        permissionManager.checkPermissions()

        // Only show if permissions are missing
        guard !permissionManager.allPermissionsGranted else {
            completion()
            return
        }

        show(completion: completion)
    }

    func show(completion: @escaping () -> Void) {
        // Close existing window if any
        window?.close()

        let onboardingView = PermissionOnboardingView {
            self.close()
            completion()
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "DodoShot"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

        // Position window lower on screen so it doesn't cover the OS permission modal
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowWidth: CGFloat = 480
            let _ = 440 // windowHeight - window auto-sizes to content
            // Center horizontally, position in lower third of screen
            let x = screenFrame.origin.x + (screenFrame.width - windowWidth) / 2
            let y = screenFrame.origin.y + screenFrame.height * 0.15 // Lower on screen
            window.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            window.center()
        }

        window.isReleasedWhenClosed = false
        window.level = .floating
        window.contentView = NSHostingView(rootView: onboardingView)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    func close() {
        window?.close()
        window = nil
    }
}

// MARK: - Legacy PermissionView (kept for compatibility)
struct PermissionView: View {
    @ObservedObject private var permissionManager = PermissionManager.shared
    @Binding var isPresented: Bool

    var body: some View {
        PermissionOnboardingView {
            isPresented = false
        }
    }
}

#Preview {
    PermissionOnboardingView(onComplete: {})
}
