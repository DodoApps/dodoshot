import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settingsManager = SettingsManager.shared
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab()
                .tabItem {
                    Label(L10n.Settings.general, systemImage: "gearshape")
                }
                .tag(0)

            AISettingsTab()
                .tabItem {
                    Label(L10n.Settings.ai, systemImage: "sparkles")
                }
                .tag(1)

            AboutTab()
                .tabItem {
                    Label(L10n.Settings.about, systemImage: "info.circle")
                }
                .tag(2)
        }
        .frame(width: 520, height: 420)
    }
}

// MARK: - General Settings
struct GeneralSettingsTab: View {
    @ObservedObject private var settingsManager = SettingsManager.shared
    @State private var isHoveringPath = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Startup Section
                SettingsSection(
                    icon: "power",
                    title: "Startup",
                    iconColor: .green
                ) {
                    SettingsToggleRow(
                        icon: "arrow.clockwise",
                        title: "Launch at login",
                        description: "Automatically start DodoShot when you log in",
                        isOn: Binding(
                            get: { settingsManager.settings.launchAtStartup },
                            set: { newValue in
                                settingsManager.settings.launchAtStartup = newValue
                                LaunchAtLoginManager.shared.setEnabled(newValue)
                            }
                        )
                    )
                }

                // Appearance Section
                SettingsSection(
                    icon: "paintbrush",
                    title: L10n.Settings.appearance,
                    iconColor: .purple
                ) {
                    VStack(spacing: 12) {
                        Text(L10n.Settings.appearanceDescription)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: 8) {
                            ForEach(AppearanceMode.allCases, id: \.self) { mode in
                                AppearanceModeButton(
                                    mode: mode,
                                    isSelected: settingsManager.settings.appearanceMode == mode
                                ) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        settingsManager.settings.appearanceMode = mode
                                    }
                                }
                            }
                        }
                    }
                }

                // Capture Settings Section
                SettingsSection(
                    icon: "camera",
                    title: L10n.Settings.capture,
                    iconColor: .blue
                ) {
                    VStack(spacing: 12) {
                        SettingsToggleRow(
                            icon: "doc.on.clipboard",
                            title: L10n.Settings.autoCopy,
                            description: L10n.Settings.autoCopyDescription,
                            isOn: $settingsManager.settings.autoCopyToClipboard
                        )

                        Divider()
                            .padding(.horizontal, -16)

                        SettingsToggleRow(
                            icon: "rectangle.on.rectangle",
                            title: L10n.Settings.showOverlay,
                            description: L10n.Settings.showOverlayDescription,
                            isOn: $settingsManager.settings.showQuickOverlay
                        )

                        Divider()
                            .padding(.horizontal, -16)

                        SettingsToggleRow(
                            icon: "desktopcomputer",
                            title: L10n.Settings.hideDesktopIcons,
                            description: L10n.Settings.hideDesktopIconsDescription,
                            isOn: $settingsManager.settings.hideDesktopIcons
                        )
                    }
                }

                // Storage Section
                SettingsSection(
                    icon: "folder",
                    title: L10n.Settings.storage,
                    iconColor: .orange
                ) {
                    VStack(spacing: 16) {
                        // Save location
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.Settings.saveLocation)
                                    .font(.system(size: 13, weight: .medium))

                                Text(settingsManager.settings.saveLocation)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            Spacer()

                            Button(action: chooseSaveLocation) {
                                HStack(spacing: 6) {
                                    Image(systemName: "folder.badge.gearshape")
                                        .font(.system(size: 12))
                                    Text(L10n.Settings.choose)
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.primary.opacity(isHoveringPath ? 0.1 : 0.06))
                                )
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                isHoveringPath = hovering
                            }
                        }

                        Divider()

                        // Image format
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Image format")
                                .font(.system(size: 13, weight: .medium))

                            HStack(spacing: 8) {
                                ForEach(ImageFormat.allCases, id: \.self) { format in
                                    ImageFormatButton(
                                        format: format,
                                        isSelected: settingsManager.settings.imageFormat == format
                                    ) {
                                        settingsManager.settings.imageFormat = format
                                    }
                                }
                            }

                            if settingsManager.settings.imageFormat == .auto {
                                Text("Automatically selects PNG for screenshots with text/UI, JPG for photos")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }

                        // JPG Quality (only show when JPG or Auto is selected)
                        if settingsManager.settings.imageFormat != .png {
                            Divider()

                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("JPG quality")
                                        .font(.system(size: 13, weight: .medium))
                                    Spacer()
                                    Text("\(Int(settingsManager.settings.jpgQuality * 100))%")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }

                                Slider(value: $settingsManager.settings.jpgQuality, in: 0.5...1.0, step: 0.05)
                                    .tint(.orange)

                                HStack {
                                    Text("Smaller file")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("Better quality")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private func chooseSaveLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            settingsManager.settings.saveLocation = url.path
        }
    }
}

// MARK: - Image Format Button
struct ImageFormatButton: View {
    let format: ImageFormat
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: format.icon)
                    .font(.system(size: 11, weight: .medium))

                Text(format.rawValue)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.orange : Color.primary.opacity(isHovered ? 0.08 : 0.04))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Settings Section
struct SettingsSection<Content: View>: View {
    let icon: String
    let title: String
    let iconColor: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(iconColor)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(iconColor.opacity(0.12))
                    )

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
            }

            // Content
            content()
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.primary.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                )
        }
    }
}

// MARK: - Appearance Mode Button
struct AppearanceModeButton: View {
    let mode: AppearanceMode
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: mode.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(isSelected ? .white : .primary)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isSelected ? Color.accentColor : Color.primary.opacity(isHovered ? 0.1 : 0.06))
                    )

                Text(mode.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Settings Toggle Row
struct SettingsToggleRow: View {
    let icon: String
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)

                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

// MARK: - Hotkeys Settings
struct HotkeysSettingsTab: View {
    @ObservedObject private var settingsManager = SettingsManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Shortcuts Section
                SettingsSection(
                    icon: "keyboard",
                    title: L10n.Settings.shortcuts,
                    iconColor: .green
                ) {
                    VStack(spacing: 0) {
                        HotkeyRow(
                            label: L10n.Settings.areaCapture,
                            icon: "rectangle.dashed",
                            iconColor: .purple,
                            hotkey: $settingsManager.settings.hotkeys.areaCapture
                        )

                        Divider()
                            .padding(.vertical, 12)

                        HotkeyRow(
                            label: L10n.Settings.windowCapture,
                            icon: "macwindow",
                            iconColor: .blue,
                            hotkey: $settingsManager.settings.hotkeys.windowCapture
                        )

                        Divider()
                            .padding(.vertical, 12)

                        HotkeyRow(
                            label: L10n.Settings.fullscreenCapture,
                            icon: "rectangle.inset.filled",
                            iconColor: .green,
                            hotkey: $settingsManager.settings.hotkeys.fullscreenCapture
                        )
                    }
                }

                // Permissions notice
                PermissionsNotice()
            }
            .padding(20)
        }
    }
}

// MARK: - Hotkey Row
struct HotkeyRow: View {
    let label: String
    let icon: String
    let iconColor: Color
    @Binding var hotkey: String

    @State private var isRecording = false
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(iconColor.opacity(0.12))
                )

            // Label
            Text(label)
                .font(.system(size: 13, weight: .medium))

            Spacer()

            // Hotkey button
            Button(action: { isRecording.toggle() }) {
                HStack(spacing: 4) {
                    if isRecording {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                        Text(L10n.Settings.recording)
                            .foregroundColor(.orange)
                    } else {
                        Text(hotkey)
                            .foregroundColor(.primary)
                    }
                }
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isRecording ? Color.orange.opacity(0.15) : Color.primary.opacity(isHovered ? 0.1 : 0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isRecording ? Color.orange : Color.clear, lineWidth: 1.5)
                        )
                )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovered = hovering
            }
        }
    }
}

// MARK: - Permissions Notice
struct PermissionsNotice: View {
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.shield")
                .font(.system(size: 20))
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.Settings.permissions)
                    .font(.system(size: 12, weight: .medium))

                Text(L10n.Settings.permissionsDescription)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: openAccessibilitySettings) {
                Text(L10n.Settings.openSettings)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.orange)
                    )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovered = hovering
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - AI Settings
struct AISettingsTab: View {
    @ObservedObject private var settingsManager = SettingsManager.shared
    @State private var showAPIKey = false
    @State private var isHoveredEye = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // LLM Configuration Section
                SettingsSection(
                    icon: "sparkles",
                    title: L10n.Settings.llmConfig,
                    iconColor: .pink
                ) {
                    VStack(spacing: 16) {
                        // Provider selector
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.Settings.provider)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)

                            HStack(spacing: 8) {
                                ForEach(LLMProvider.allCases, id: \.self) { provider in
                                    ProviderButton(
                                        provider: provider,
                                        isSelected: settingsManager.settings.llmProvider == provider
                                    ) {
                                        settingsManager.settings.llmProvider = provider
                                    }
                                }
                            }
                        }

                        Divider()

                        // API Key field
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.Settings.apiKey)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)

                            HStack(spacing: 8) {
                                Group {
                                    if showAPIKey {
                                        TextField(L10n.Settings.apiKeyPlaceholder, text: $settingsManager.settings.llmApiKey)
                                    } else {
                                        SecureField(L10n.Settings.apiKeyPlaceholder, text: $settingsManager.settings.llmApiKey)
                                    }
                                }
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.primary.opacity(0.04))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                                        )
                                )

                                Button(action: { showAPIKey.toggle() }) {
                                    Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                        .font(.system(size: 14))
                                        .foregroundColor(isHoveredEye ? .primary : .secondary)
                                        .frame(width: 32, height: 32)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(Color.primary.opacity(isHoveredEye ? 0.08 : 0.04))
                                        )
                                }
                                .buttonStyle(.plain)
                                .onHover { hovering in
                                    isHoveredEye = hovering
                                }
                            }

                            HStack(spacing: 4) {
                                Image(systemName: "lock.shield")
                                    .font(.system(size: 10))
                                Text(L10n.Settings.apiKeySecure)
                                    .font(.system(size: 10))
                            }
                            .foregroundColor(.secondary)
                        }
                    }
                }

                // AI Features info
                AIFeaturesInfo()
            }
            .padding(20)
        }
    }
}

// MARK: - Provider Button
struct ProviderButton: View {
    let provider: LLMProvider
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    private var providerIcon: String {
        switch provider {
        case .anthropic: return "sparkle"
        case .openai: return "brain"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: providerIcon)
                    .font(.system(size: 12, weight: .medium))

                Text(provider.rawValue)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor : Color.primary.opacity(isHovered ? 0.08 : 0.04))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - AI Features Info
struct AIFeaturesInfo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.blue.opacity(0.12))
                    )

                Text(L10n.Settings.aiFeatures)
                    .font(.system(size: 13, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(
                    icon: "text.viewfinder",
                    title: L10n.Settings.smartDescriptions,
                    description: L10n.Settings.smartDescriptionsDescription
                )

                FeatureRow(
                    icon: "doc.text.magnifyingglass",
                    title: L10n.Settings.ocrExtraction,
                    description: L10n.Settings.ocrExtractionDescription
                )

                FeatureRow(
                    icon: "sparkles.rectangle.stack",
                    title: L10n.Settings.contentSuggestions,
                    description: L10n.Settings.contentSuggestionsDescription
                )
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
            )
        }
    }
}

// MARK: - Feature Row
struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))

                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - About Tab
struct AboutTab: View {
    @State private var isHoveredGitHub = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // App icon - use the actual app icon
            ZStack {
                // Glow effect
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.purple.opacity(0.3), Color.blue.opacity(0.1), Color.clear],
                            center: .center,
                            startRadius: 30,
                            endRadius: 70
                        )
                    )
                    .frame(width: 140, height: 140)
                    .blur(radius: 15)

                // App icon from bundle
                if let appIcon = NSImage(named: NSImage.applicationIconName) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 96, height: 96)
                } else {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 48, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }

            // App name and version
            VStack(spacing: 6) {
                Text("DodoShot")
                    .font(.system(size: 28, weight: .bold))

                Text(L10n.Settings.version("1.2.1"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.primary.opacity(0.06))
                    )
            }

            Text(L10n.Settings.tagline)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // Divider
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 160, height: 1)

            // License and links
            VStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 11))
                    Text(L10n.Settings.openSource)
                        .font(.system(size: 11))
                }
                .foregroundColor(.secondary)

                Button(action: openGitHub) {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                            .font(.system(size: 12))
                        Text(L10n.Settings.viewOnGitHub)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(isHoveredGitHub ? .primary : .accentColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor.opacity(isHoveredGitHub ? 0.15 : 0.1))
                    )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHoveredGitHub = hovering
                    }
                }
            }

            Spacer()

            // Footer - Made by Dr. Gorkem Cetin
            Text("Made by Dr. Gorkem Cetin")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }

    private func openGitHub() {
        if let url = URL(string: "https://github.com/bluewave-labs/DodoShot") {
            NSWorkspace.shared.open(url)
        }
    }
}

#Preview {
    SettingsView()
}
