import SwiftUI

/// A view that guides the user through granting required permissions
struct PermissionView: View {
    @ObservedObject private var permissionManager = PermissionManager.shared
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .red],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("Permissions Required")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)

                Text("DodoShot needs Screen Recording and Accessibility permissions to capture screenshots and use global hotkeys.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(.top, 24)

            // Permission status cards
            VStack(spacing: 12) {
                PermissionCard(
                    title: "Screen Recording",
                    description: "Required to capture screenshots",
                    icon: "record.circle",
                    isGranted: permissionManager.isScreenRecordingGranted,
                    action: { permissionManager.openScreenRecordingSettings() }
                )

                PermissionCard(
                    title: "Accessibility",
                    description: "Required for global hotkeys",
                    icon: "hand.raised",
                    isGranted: permissionManager.isAccessibilityGranted,
                    action: { permissionManager.openAccessibilitySettings() }
                )
            }
            .padding(.horizontal, 20)

            // Instructions
            if !permissionManager.allPermissionsGranted {
                VStack(spacing: 8) {
                    Text("If already enabled but not working:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. Remove DodoShot from the permission list")
                        Text("2. Click \"Show in Finder\" and drag the app back")
                        Text("3. Restart DodoShot")
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.8))
                }
                .padding(.horizontal, 24)
            }

            Spacer()

            // Actions
            VStack(spacing: 12) {
                if permissionManager.allPermissionsGranted {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("All permissions granted!")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.green)
                    }
                    .padding(.bottom, 8)

                    Button("Continue") {
                        isPresented = false
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } else {
                    HStack(spacing: 12) {
                        Button(action: { permissionManager.showAppInFinder() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "folder")
                                Text("Show in Finder")
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())

                        Button(action: { permissionManager.restartApp() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                Text("Restart")
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }

                    Button("I'll do this later") {
                        isPresented = false
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                }
            }
            .padding(.bottom, 24)
        }
        .frame(width: 400, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Permission Card
struct PermissionCard: View {
    let title: String
    let description: String
    let icon: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(isGranted ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: isGranted ? "checkmark" : icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isGranted ? .green : .orange)
            }

            // Text
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)

                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Status/Action
            if isGranted {
                Text("Granted")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.green)
            } else {
                Button("Grant") {
                    action()
                }
                .buttonStyle(SmallPrimaryButtonStyle())
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isGranted ? Color.green.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Button Styles
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [.blue, .purple],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.08))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
    }
}

struct SmallPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                LinearGradient(
                    colors: [.orange, .red],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
    }
}

#Preview {
    PermissionView(isPresented: .constant(true))
        .preferredColorScheme(.dark)
}
