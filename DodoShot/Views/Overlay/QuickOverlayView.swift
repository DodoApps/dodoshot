import SwiftUI
import AppKit

// MARK: - Quick Overlay Manager
/// Manages multiple stacking overlays like CleanShot X
class QuickOverlayManager: ObservableObject {
    static let shared = QuickOverlayManager()

    @Published var overlays: [OverlayItem] = []

    private var windows: [UUID: NSWindow] = [:]
    private var autoDismissTimers: [UUID: Timer] = [:]

    struct OverlayItem: Identifiable {
        let id: UUID
        let screenshot: Screenshot
        var isExpanded: Bool = false
        var isPaused: Bool = false  // Pause auto-dismiss when hovered
    }

    private init() {}

    func showOverlay(for screenshot: Screenshot) {
        let item = OverlayItem(id: screenshot.id, screenshot: screenshot)
        overlays.append(item)
        createCompactOverlayWindow(for: item)

        // Setup auto-dismiss if enabled
        let settings = SettingsManager.shared.settings
        if settings.quickOverlayAutoDismiss && settings.quickOverlayTimeout > 0 {
            startAutoDismissTimer(for: screenshot.id, timeout: settings.quickOverlayTimeout)
        }
    }

    func pauseAutoDismiss(for id: UUID) {
        autoDismissTimers[id]?.invalidate()
        autoDismissTimers.removeValue(forKey: id)
        if let index = overlays.firstIndex(where: { $0.id == id }) {
            overlays[index].isPaused = true
        }
    }

    func resumeAutoDismiss(for id: UUID) {
        let settings = SettingsManager.shared.settings
        if settings.quickOverlayAutoDismiss && settings.quickOverlayTimeout > 0 {
            if let index = overlays.firstIndex(where: { $0.id == id }) {
                overlays[index].isPaused = false
            }
            startAutoDismissTimer(for: id, timeout: settings.quickOverlayTimeout)
        }
    }

    private func startAutoDismissTimer(for id: UUID, timeout: Double) {
        autoDismissTimers[id]?.invalidate()
        autoDismissTimers[id] = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            self?.dismissOverlay(id: id)
        }
    }

    func dismissOverlay(id: UUID) {
        // Cancel auto-dismiss timer
        autoDismissTimers[id]?.invalidate()
        autoDismissTimers.removeValue(forKey: id)

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            overlays.removeAll { $0.id == id }
        }

        // Animate window out
        if let window = windows[id] {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                window.animator().alphaValue = 0
            } completionHandler: {
                window.close()
            }
        }
        windows.removeValue(forKey: id)
        repositionOverlays()
    }

    func dismissAll() {
        for (_, window) in windows {
            window.close()
        }
        windows.removeAll()
        overlays.removeAll()
    }

    /// Creates a compact overlay window in the corner (lightweight post-capture overlay)
    private func createCompactOverlayWindow(for item: OverlayItem) {
        guard let screen = NSScreen.main else { return }

        let windowSize = NSSize(width: 300, height: 88)
        let padding: CGFloat = 20

        // Position in bottom-right corner, stacking upward for multiple overlays
        let existingCount = CGFloat(overlays.count - 1)
        let windowOrigin = NSPoint(
            x: screen.visibleFrame.maxX - windowSize.width - padding,
            y: screen.visibleFrame.minY + padding + (existingCount * (windowSize.height + 10))
        )

        let window = NSWindow(
            contentRect: NSRect(origin: windowOrigin, size: windowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let contentView = CompactOverlayView(
            screenshot: item.screenshot,
            onDismiss: { [weak self] in
                self?.dismissOverlay(id: item.id)
            },
            onExpand: { [weak self] in
                Task { @MainActor in
                    self?.openEditor(for: item.screenshot)
                    self?.dismissOverlay(id: item.id)
                }
            },
            onHoverStart: { [weak self] in
                self?.pauseAutoDismiss(for: item.id)
            },
            onHoverEnd: { [weak self] in
                self?.resumeAutoDismiss(for: item.id)
            }
        )

        window.contentView = NSHostingView(rootView: contentView)

        // Animate in from right
        window.setFrameOrigin(NSPoint(x: windowOrigin.x + 50, y: windowOrigin.y))
        window.alphaValue = 0
        window.orderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrameOrigin(windowOrigin)
            window.animator().alphaValue = 1
        }

        windows[item.id] = window
    }

    /// Opens the full annotation editor (used when expanding from compact overlay)
    @MainActor
    func openEditor(for screenshot: Screenshot) {
        AnnotationEditorWindowController.shared.showEditor(for: screenshot) { updatedScreenshot in
            Task { @MainActor in
                ScreenCaptureService.shared.saveToFile(updatedScreenshot)
            }
        }
    }

    private func createWindow(for item: OverlayItem) {
        guard let screen = NSScreen.main else { return }

        // Calculate window size based on image aspect ratio
        let imageSize = item.screenshot.image.size
        let maxWidth: CGFloat = min(screen.visibleFrame.width * 0.85, 1200)
        let maxHeight: CGFloat = min(screen.visibleFrame.height * 0.85, 900)

        // Calculate size maintaining aspect ratio
        var windowWidth = imageSize.width + 48  // padding for toolbar
        var windowHeight = imageSize.height + 140  // toolbar + bottom bar

        if windowWidth > maxWidth {
            let scale = maxWidth / windowWidth
            windowWidth = maxWidth
            windowHeight = windowHeight * scale
        }
        if windowHeight > maxHeight {
            let scale = maxHeight / windowHeight
            windowHeight = maxHeight
            windowWidth = windowWidth * scale
        }

        // Ensure minimum size
        windowWidth = max(windowWidth, 700)
        windowHeight = max(windowHeight, 500)

        let windowSize = NSSize(width: windowWidth, height: windowHeight)
        let windowOrigin = NSPoint(
            x: screen.visibleFrame.midX - windowSize.width / 2,
            y: screen.visibleFrame.midY - windowSize.height / 2
        )

        let window = NSWindow(
            contentRect: NSRect(origin: windowOrigin, size: windowSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Edit Screenshot"
        window.level = .floating
        window.isOpaque = true
        window.backgroundColor = NSColor.windowBackgroundColor
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.minSize = NSSize(width: 600, height: 450)

        let contentView = AnnotationEditorView(
            screenshot: item.screenshot,
            onSave: { [weak self] updatedScreenshot in
                // Save the annotated screenshot
                Task { @MainActor in
                    ScreenCaptureService.shared.saveToFile(updatedScreenshot)
                }
                self?.dismissOverlay(id: item.id)
            },
            onCancel: { [weak self] in
                self?.dismissOverlay(id: item.id)
            }
        )

        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Animate in
        window.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }

        windows[item.id] = window
    }

    private func repositionOverlays() {
        guard let screen = NSScreen.main else { return }
        let baseY = screen.visibleFrame.minY + 20

        for (index, item) in overlays.enumerated() {
            if let window = windows[item.id] {
                let yOffset = CGFloat(index) * 90
                let newOrigin = NSPoint(
                    x: screen.visibleFrame.maxX - window.frame.width - 20,
                    y: baseY + yOffset
                )

                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.25
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    window.animator().setFrameOrigin(newOrigin)
                }
            }
        }
    }

    private func toggleExpand(id: UUID) {
        if let index = overlays.firstIndex(where: { $0.id == id }) {
            overlays[index].isExpanded.toggle()

            if let window = windows[id] {
                let newHeight: CGFloat = overlays[index].isExpanded ? 320 : 80

                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

                    var newFrame = window.frame
                    newFrame.size.height = newHeight
                    newFrame.size.width = overlays[index].isExpanded ? 300 : 280
                    window.animator().setFrame(newFrame, display: true)
                }

                // Update content
                let contentView = overlays[index].isExpanded
                    ? AnyView(ExpandedOverlayView(
                        screenshot: overlays[index].screenshot,
                        onDismiss: { [weak self] in self?.dismissOverlay(id: id) },
                        onCollapse: { [weak self] in self?.toggleExpand(id: id) }
                    ))
                    : AnyView(CompactOverlayView(
                        screenshot: overlays[index].screenshot,
                        onDismiss: { [weak self] in self?.dismissOverlay(id: id) },
                        onExpand: { [weak self] in self?.toggleExpand(id: id) }
                    ))

                window.contentView = NSHostingView(rootView: contentView)
            }
        }
    }
}

// MARK: - Compact Overlay View (CleanShot X style)
struct CompactOverlayView: View {
    let screenshot: Screenshot
    let onDismiss: () -> Void
    let onExpand: () -> Void
    var onHoverStart: (() -> Void)?
    var onHoverEnd: (() -> Void)?

    @State private var isHovered = false
    @State private var showCopiedBadge = false
    @State private var dragOffset: CGSize = .zero
    @State private var isDraggingImage = false

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail (draggable for drag-and-drop)
            Image(nsImage: screenshot.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isDraggingImage ? Color.blue.opacity(0.5) : Color.white.opacity(0.15), lineWidth: isDraggingImage ? 2 : 1)
                )
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                .scaleEffect(isDraggingImage ? 1.05 : 1.0)
                .onDrag {
                    isDraggingImage = true
                    // Create drag item with image
                    let provider = NSItemProvider(object: screenshot.image)
                    return provider
                }
                .onChange(of: isDraggingImage) { _, newValue in
                    if !newValue {
                        // Drag ended - dismiss if dropped successfully
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            // Reset state
                            isDraggingImage = false
                        }
                    }
                }

            // Info & Actions
            VStack(alignment: .leading, spacing: 6) {
                // Title & time
                HStack {
                    Text(screenshot.captureType.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)

                    Spacer()

                    Text(timeAgo(screenshot.capturedAt))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                // Quick actions
                HStack(spacing: 4) {
                    CompactActionButton(icon: "doc.on.clipboard", tooltip: L10n.Overlay.copy) {
                        copyToClipboard()
                    }
                    CompactActionButton(icon: "square.and.arrow.down", tooltip: L10n.Overlay.save) {
                        saveScreenshot()
                    }
                    CompactActionButton(icon: "pencil.tip", tooltip: L10n.Overlay.annotate) {
                        openAnnotationEditor()
                    }
                    CompactActionButton(icon: "pin", tooltip: L10n.Overlay.pin) {
                        pinScreenshot()
                    }

                    Spacer()

                    // Expand/Edit button
                    Button(action: onExpand) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 24, height: 24)
                            .background(
                                Circle()
                                    .fill(Color.primary.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Open in editor")
                }
            }

            // Close button (shows on hover)
            if isHovered {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(12)
        .frame(height: 80)
        .background(
            ZStack {
                // Glass effect
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)

                // Gradient overlay
                LinearGradient(
                    colors: [Color.white.opacity(0.08), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
            if hovering {
                onHoverStart?()
            } else {
                onHoverEnd?()
            }
        }
        .overlay(
            // Copied badge
            Group {
                if showCopiedBadge {
                    CopiedBadge()
                        .transition(.scale.combined(with: .opacity))
                }
            }
        )
        .gesture(
            DragGesture()
                .onChanged { value in
                    // Swipe to dismiss
                    if value.translation.width > 50 {
                        dragOffset = value.translation
                    }
                }
                .onEnded { value in
                    if value.translation.width > 100 {
                        onDismiss()
                    } else {
                        withAnimation(.spring()) {
                            dragOffset = .zero
                        }
                    }
                }
        )
        .offset(x: dragOffset.width)
        .opacity(Double(1.0 - (dragOffset.width / 200.0)))
    }

    private func copyToClipboard() {
        ScreenCaptureService.shared.copyToClipboard(screenshot)
        withAnimation(.spring(response: 0.3)) {
            showCopiedBadge = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.spring(response: 0.3)) {
                showCopiedBadge = false
            }
        }
    }

    private func saveScreenshot() {
        ScreenCaptureService.shared.saveToFile(screenshot)
        onDismiss()
    }

    private func openAnnotationEditor() {
        AnnotationEditorWindowController.shared.showEditor(for: screenshot) { _ in }
        onDismiss()
    }

    private func pinScreenshot() {
        FloatingWindowService.shared.pinScreenshot(screenshot)
        onDismiss()
    }

    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return L10n.Overlay.justNow }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }
}

// MARK: - Expanded Overlay View
struct ExpandedOverlayView: View {
    let screenshot: Screenshot
    let onDismiss: () -> Void
    let onCollapse: () -> Void

    @State private var showCopiedBadge = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onCollapse) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(screenshot.captureType.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            // Image preview
            Image(nsImage: screenshot.image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 160)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .padding(.horizontal, 14)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)

            // Actions grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ExpandedActionButton(icon: "doc.on.clipboard", label: L10n.Overlay.copy, color: .blue) {
                    copyToClipboard()
                }
                ExpandedActionButton(icon: "square.and.arrow.down", label: L10n.Overlay.save, color: .green) {
                    ScreenCaptureService.shared.saveToFile(screenshot)
                    onDismiss()
                }
                ExpandedActionButton(icon: "pencil.tip", label: L10n.Overlay.annotate, color: .purple) {
                    onDismiss()
                }
                ExpandedActionButton(icon: "pin", label: L10n.Overlay.pin, color: .orange) {
                    FloatingWindowService.shared.pinScreenshot(screenshot)
                    onDismiss()
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 14)

            // Metadata
            HStack {
                Label("\(Int(screenshot.image.size.width))×\(Int(screenshot.image.size.height))", systemImage: "aspectratio")
                Spacer()
                Label(formatFileSize(screenshot.image), systemImage: "doc")
            }
            .font(.system(size: 10))
            .foregroundColor(.secondary)
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                LinearGradient(
                    colors: [Color.white.opacity(0.06), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .overlay(
            Group {
                if showCopiedBadge {
                    CopiedBadge()
                        .transition(.scale.combined(with: .opacity))
                }
            }
        )
    }

    private func copyToClipboard() {
        ScreenCaptureService.shared.copyToClipboard(screenshot)
        withAnimation(.spring(response: 0.3)) {
            showCopiedBadge = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.spring(response: 0.3)) {
                showCopiedBadge = false
            }
        }
    }

    private func formatFileSize(_ image: NSImage) -> String {
        guard let tiffData = image.tiffRepresentation else { return "—" }
        let bytes = tiffData.count
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}

// MARK: - Compact Action Button
struct CompactActionButton: View {
    let icon: String
    let tooltip: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isHovered ? .primary : .secondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(isHovered ? 0.12 : 0.06))
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Expanded Action Button
struct ExpandedActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isHovered ? .white : color)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isHovered ? color : color.opacity(0.15))
                    )
                    .scaleEffect(isPressed ? 0.9 : 1.0)

                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
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
                .onChanged { _ in withAnimation(.easeInOut(duration: 0.1)) { isPressed = true } }
                .onEnded { _ in withAnimation(.easeInOut(duration: 0.1)) { isPressed = false } }
        )
    }
}

// MARK: - Copied Badge
struct CopiedBadge: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
            Text("overlay.copied".localized)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.green)
                .shadow(color: .green.opacity(0.4), radius: 8)
        )
    }
}

// MARK: - Visual Effect Blur
struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Legacy QuickOverlayView (for compatibility)
struct QuickOverlayView: View {
    let screenshot: Screenshot
    let onDismiss: () -> Void

    var body: some View {
        CompactOverlayView(
            screenshot: screenshot,
            onDismiss: onDismiss,
            onExpand: {}
        )
    }
}

// MARK: - Quick Action Button (Legacy)
struct QuickActionButton: View {
    let icon: String
    let label: String
    let gradient: [Color]
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: gradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .scaleEffect(isPressed ? 0.92 : (isHovered ? 1.05 : 1.0))
                        .shadow(
                            color: gradient.first?.opacity(isHovered ? 0.4 : 0.2) ?? .clear,
                            radius: isHovered ? 8 : 4,
                            y: 2
                        )

                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                }

                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
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
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Feedback Badge (Legacy)
struct FeedbackBadge: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
            Text(text)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.green)
                .shadow(color: .green.opacity(0.4), radius: 10)
        )
        .transition(.scale.combined(with: .opacity))
    }
}

#Preview {
    VStack(spacing: 20) {
        CompactOverlayView(
            screenshot: Screenshot(
                image: NSImage(systemSymbolName: "photo", accessibilityDescription: nil)!,
                captureType: .area
            ),
            onDismiss: {},
            onExpand: {}
        )
        .frame(width: 280)
    }
    .padding(40)
    .background(Color.gray.opacity(0.3))
}
