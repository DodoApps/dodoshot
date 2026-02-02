import SwiftUI

struct MenuBarView: View {
    @ObservedObject private var captureService = ScreenCaptureService.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            // Main capture options (prominent)
            mainCaptureSection

            // Divider with label
            sectionDivider(label: L10n.Menu.tools)

            // Tools section (secondary)
            toolsSection

            // Recent captures
            if !captureService.recentCaptures.isEmpty {
                sectionDivider(label: L10n.Menu.recentCaptures)
                recentCapturesSection
            }

            // Footer
            footerSection
        }
        .frame(width: 300)
        .background(
            ZStack {
                VisualEffectBlur(material: .popover, blendingMode: .behindWindow)
                Color(nsColor: .windowBackgroundColor).opacity(0.5)
            }
        )
        .preferredColorScheme(.dark)
    }

    // MARK: - Header
    private var headerSection: some View {
        HStack(spacing: 10) {
            // App icon with glow effect
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.3), Color.blue.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                    .blur(radius: 4)

                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.purple, Color.blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("DodoShot")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)

                Text("menu.ready".localized)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // History button
            HeaderButton(icon: "clock.arrow.circlepath", tooltip: L10n.Menu.history) {
                CaptureHistoryWindowController.shared.showHistory()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Main Capture Section
    private var mainCaptureSection: some View {
        VStack(spacing: 6) {
            // Primary capture buttons in a grid
            HStack(spacing: 8) {
                PrimaryCaptureButton(
                    icon: "rectangle.dashed",
                    label: L10n.Menu.area,
                    shortcut: "⌘⇧4",
                    color: .purple
                ) {
                    startCapture(type: .area)
                }

                PrimaryCaptureButton(
                    icon: "macwindow",
                    label: L10n.Menu.window,
                    shortcut: "⌘⇧5",
                    color: .blue
                ) {
                    startCapture(type: .window)
                }

                PrimaryCaptureButton(
                    icon: "rectangle.inset.filled",
                    label: L10n.Menu.fullscreen,
                    shortcut: "⌘⇧3",
                    color: .green
                ) {
                    startCapture(type: .fullscreen)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Tools Section
    private var toolsSection: some View {
        HStack(spacing: 8) {
            MenuToolButton(
                icon: "ruler",
                label: L10n.Menu.ruler,
                color: .cyan
            ) {
                startPixelRuler()
            }

            MenuToolButton(
                icon: "eyedropper",
                label: L10n.Menu.colorPicker,
                color: .pink
            ) {
                startColorPicker()
            }

            MenuToolButton(
                icon: "timer",
                label: "Timed",
                color: .orange
            ) {
                startTimedCapture()
            }

            MenuToolButton(
                icon: "text.viewfinder",
                label: L10n.Menu.ocr,
                color: .teal
            ) {
                startOCRCapture()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Recent Captures
    private var recentCapturesSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(captureService.recentCaptures.prefix(6)) { screenshot in
                    RecentCaptureThumbnail(screenshot: screenshot)
                }

                // Show all button if more than 6
                if captureService.recentCaptures.count > 6 {
                    ShowAllButton {
                        CaptureHistoryWindowController.shared.showHistory()
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Footer
    private var footerSection: some View {
        HStack {
            if !captureService.recentCaptures.isEmpty {
                Button(action: { captureService.clearRecents() }) {
                    Label("menu.clearHistory".localized, systemImage: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(0.7)
            }

            Spacer()

            Button(action: quitApp) {
                Label(L10n.Menu.quit, systemImage: "power")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(0.7)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.03))
    }

    // MARK: - Section Divider
    private func sectionDivider(label: String) -> some View {
        HStack(spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.6))
                .tracking(0.5)

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Actions
    private func startCapture(type: CaptureType) {
        NSApp.sendAction(#selector(AppDelegate.closePopover), to: nil, from: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            captureService.startCapture(type: type)
        }
    }

    private func startPixelRuler() {
        NSApp.sendAction(#selector(AppDelegate.closePopover), to: nil, from: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            MeasurementService.shared.startPixelRuler()
        }
    }

    private func startColorPicker() {
        NSApp.sendAction(#selector(AppDelegate.closePopover), to: nil, from: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            MeasurementService.shared.startColorPicker()
        }
    }

    private func startTimedCapture() {
        // Close the popover first
        NSApp.sendAction(#selector(AppDelegate.closePopover), to: nil, from: nil)
        // Show timer selection modal after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            ScreenCaptureService.shared.showTimedCaptureModal()
        }
    }

    private func startOCRCapture() {
        NSApp.sendAction(#selector(AppDelegate.closePopover), to: nil, from: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            ScreenCaptureService.shared.startOCRCapture()
        }
    }

    private func openSettings() {
        NSApp.sendAction(#selector(AppDelegate.closePopover), to: nil, from: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.openSettingsWindow()
            }
        }
    }

    private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Header Button
struct HeaderButton: View {
    let icon: String
    let tooltip: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isHovered ? .primary : .secondary)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(isHovered ? 0.1 : 0.05))
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Primary Capture Button
struct PrimaryCaptureButton: View {
    let icon: String
    let label: String
    let shortcut: String
    let color: Color
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    // Background
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            isHovered
                                ? color.opacity(0.2)
                                : color.opacity(0.1)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(color.opacity(isHovered ? 0.3 : 0.15), lineWidth: 1)
                        )

                    // Icon
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(color)
                }
                .frame(height: 52)
                .scaleEffect(isPressed ? 0.95 : 1.0)

                // Label
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary.opacity(0.8))

                // Shortcut
                Text(shortcut)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation(.easeInOut(duration: 0.08)) { isPressed = true } }
                .onEnded { _ in withAnimation(.easeInOut(duration: 0.08)) { isPressed = false } }
        )
    }
}

// MARK: - Tool Button
struct MenuToolButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(isHovered ? color : .secondary)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isHovered ? color.opacity(0.15) : Color.primary.opacity(0.05))
                    )

                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Recent Capture Thumbnail
struct RecentCaptureThumbnail: View {
    let screenshot: Screenshot

    @State private var isHovered = false

    var body: some View {
        Button(action: showQuickActions) {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: screenshot.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 52, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(isHovered ? 0.3 : 0.1), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(isHovered ? 0.2 : 0.1), radius: isHovered ? 4 : 2, y: 1)

                // Overlay on hover
                if isHovered {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.4))
                        .frame(width: 52, height: 40)

                    Image(systemName: "ellipsis")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button(action: { copyToClipboard() }) {
                Label(L10n.ContextMenu.copy, systemImage: "doc.on.clipboard")
            }
            Button(action: { saveToFile() }) {
                Label(L10n.ContextMenu.save, systemImage: "square.and.arrow.down")
            }
            Button(action: { pinScreenshot() }) {
                Label(L10n.ContextMenu.pin, systemImage: "pin")
            }
            Divider()
            Button(action: { deleteScreenshot() }) {
                Label(L10n.ContextMenu.delete, systemImage: "trash")
            }
        }
    }

    private func showQuickActions() {
        QuickOverlayManager.shared.showOverlay(for: screenshot)
    }

    private func copyToClipboard() {
        ScreenCaptureService.shared.copyToClipboard(screenshot)
    }

    private func saveToFile() {
        ScreenCaptureService.shared.saveToFile(screenshot)
    }

    private func pinScreenshot() {
        FloatingWindowService.shared.pinScreenshot(screenshot)
    }

    private func deleteScreenshot() {
        // Remove from recents
        ScreenCaptureService.shared.recentCaptures.removeAll { $0.id == screenshot.id }
    }
}

// MARK: - Show All Button
struct ShowAllButton: View {
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: "chevron.right.2")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                Text(L10n.Menu.showAll)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .frame(width: 36, height: 40)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(isHovered ? 0.08 : 0.04))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Legacy components for compatibility
struct CaptureOptionButton: View {
    let type: CaptureType
    let action: () -> Void

    var body: some View {
        PrimaryCaptureButton(
            icon: type.icon,
            label: type.rawValue,
            shortcut: type.shortcut,
            color: type == .area ? .purple : (type == .window ? .blue : .green),
            action: action
        )
    }
}

struct MeasurementMenuToolButton: View {
    let icon: String
    let label: String
    let description: String
    let gradient: [Color]
    let action: () -> Void

    var body: some View {
        MenuToolButton(
            icon: icon,
            label: label,
            color: gradient.first ?? .gray,
            action: action
        )
    }
}

struct RecentCaptureThumb: View {
    let screenshot: Screenshot

    var body: some View {
        RecentCaptureThumbnail(screenshot: screenshot)
    }
}

#Preview {
    MenuBarView()
        .frame(height: 420)
}
