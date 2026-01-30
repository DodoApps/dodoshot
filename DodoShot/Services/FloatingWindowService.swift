import Foundation
import AppKit
import SwiftUI

/// Stores floating window state for persistence
struct FloatingWindowState {
    var opacity: CGFloat = 1.0
    var isClickThrough: Bool = false
    var frame: NSRect?
}

/// Service for managing floating screenshot windows
class FloatingWindowService: ObservableObject {
    static let shared = FloatingWindowService()

    @Published var floatingWindows: [UUID: NSWindow] = [:]
    @Published var windowStates: [UUID: FloatingWindowState] = [:]

    private init() {}

    // MARK: - Public Methods

    /// Pin a screenshot as a floating window
    func pinScreenshot(_ screenshot: Screenshot) {
        let windowSize = calculateWindowSize(for: screenshot.image)

        // Create floating window
        let window = FloatingWindow(
            contentRect: NSRect(
                x: 100,
                y: 100,
                width: windowSize.width,
                height: windowSize.height
            ),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Initialize window state
        windowStates[screenshot.id] = FloatingWindowState()

        let contentView = FloatingScreenshotView(
            screenshot: screenshot,
            onClose: { [weak self] in
                self?.closeFloatingWindow(id: screenshot.id)
            },
            onOpacityChange: { [weak self, weak window] opacity in
                window?.alphaValue = opacity
                self?.windowStates[screenshot.id]?.opacity = opacity
            },
            onClickThroughToggle: { [weak self, weak window] isClickThrough in
                window?.ignoresMouseEvents = isClickThrough
                self?.windowStates[screenshot.id]?.isClickThrough = isClickThrough
                // Show a brief overlay when click-through is enabled
                if isClickThrough {
                    window?.level = .floating
                }
            }
        )

        window.contentView = NSHostingView(rootView: contentView)

        // Position near cursor
        if let mouseLocation = NSEvent.mouseLocation as CGPoint? {
            window.setFrameOrigin(NSPoint(
                x: mouseLocation.x - windowSize.width / 2,
                y: mouseLocation.y - windowSize.height / 2
            ))
        }

        window.makeKeyAndOrderFront(nil)
        floatingWindows[screenshot.id] = window
    }

    /// Toggle click-through mode for a floating window
    func toggleClickThrough(id: UUID) {
        guard let window = floatingWindows[id] else { return }
        let currentState = windowStates[id]?.isClickThrough ?? false
        window.ignoresMouseEvents = !currentState
        windowStates[id]?.isClickThrough = !currentState
    }

    /// Set opacity for a floating window
    func setOpacity(id: UUID, opacity: CGFloat) {
        floatingWindows[id]?.alphaValue = opacity
        windowStates[id]?.opacity = opacity
    }

    /// Close a specific floating window
    func closeFloatingWindow(id: UUID) {
        floatingWindows[id]?.close()
        floatingWindows.removeValue(forKey: id)
    }

    /// Close all floating windows
    func closeAllFloatingWindows() {
        for (_, window) in floatingWindows {
            window.close()
        }
        floatingWindows.removeAll()
    }

    /// Toggle pin state for a screenshot
    func togglePin(_ screenshot: Screenshot) {
        if floatingWindows[screenshot.id] != nil {
            closeFloatingWindow(id: screenshot.id)
        } else {
            pinScreenshot(screenshot)
        }
    }

    /// Check if a screenshot is pinned
    func isPinned(_ screenshot: Screenshot) -> Bool {
        return floatingWindows[screenshot.id] != nil
    }

    // MARK: - Private Methods

    private func calculateWindowSize(for image: NSImage) -> NSSize {
        let maxDimension: CGFloat = 400
        let imageSize = image.size

        if imageSize.width > imageSize.height {
            let ratio = maxDimension / imageSize.width
            return NSSize(
                width: maxDimension,
                height: min(imageSize.height * ratio, maxDimension)
            )
        } else {
            let ratio = maxDimension / imageSize.height
            return NSSize(
                width: min(imageSize.width * ratio, maxDimension),
                height: maxDimension
            )
        }
    }
}

// MARK: - Floating Window Class
class FloatingWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        // ESC to close
        if event.keyCode == 53 {
            close()
        } else {
            super.keyDown(with: event)
        }
    }
}

// MARK: - Floating Screenshot View
struct FloatingScreenshotView: View {
    let screenshot: Screenshot
    let onClose: () -> Void
    let onOpacityChange: (CGFloat) -> Void
    var onClickThroughToggle: ((Bool) -> Void)?

    @State private var isHovered = false
    @State private var opacity: Double = 1.0
    @State private var showControls = false
    @State private var isClickThrough = false
    @State private var showCopiedFeedback = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Screenshot image
            Image(nsImage: screenshot.image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isClickThrough ? Color.orange.opacity(0.5) : Color.white.opacity(0.2), lineWidth: isClickThrough ? 2 : 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)

            // Click-through indicator
            if isClickThrough && !isHovered {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "cursorarrow.click.badge.clock")
                            .font(.system(size: 10))
                        Text("Click-through")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.7))
                    )
                    .padding(8)
                }
            }

            // Copied feedback
            if showCopiedFeedback {
                VStack {
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                        Text("Copied")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.green)
                    )
                    Spacer()
                }
                .transition(.scale.combined(with: .opacity))
            }

            // Controls overlay
            if isHovered && !isClickThrough {
                VStack(alignment: .trailing, spacing: 8) {
                    // Close button
                    FloatingControlButton(icon: "xmark", color: .red, action: onClose)

                    // Copy button
                    FloatingControlButton(icon: "doc.on.doc", color: .blue) {
                        copyToClipboard()
                    }

                    // Click-through toggle
                    FloatingControlButton(
                        icon: isClickThrough ? "cursorarrow.click.badge.clock" : "cursorarrow.click",
                        color: isClickThrough ? .orange : .gray
                    ) {
                        isClickThrough.toggle()
                        onClickThroughToggle?(isClickThrough)
                    }

                    // Expanded controls
                    if showControls {
                        VStack(spacing: 8) {
                            // Opacity control
                            VStack(spacing: 4) {
                                HStack {
                                    Image(systemName: "circle.lefthalf.filled")
                                        .font(.system(size: 10))
                                    Text("\(Int(opacity * 100))%")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundColor(.white)

                                Slider(value: $opacity, in: 0.2...1.0)
                                    .frame(width: 80)
                                    .onChange(of: opacity) { _, newValue in
                                        onOpacityChange(newValue)
                                    }
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.8))
                        )
                    }

                    // Toggle controls button
                    FloatingControlButton(icon: showControls ? "chevron.up" : "slider.horizontal.3", color: .gray) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showControls.toggle()
                        }
                    }
                }
                .padding(8)
                .transition(.opacity)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([screenshot.image])

        withAnimation(.spring(response: 0.3)) {
            showCopiedFeedback = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.spring(response: 0.3)) {
                showCopiedFeedback = false
            }
        }
    }
}

// MARK: - Floating Control Button
struct FloatingControlButton: View {
    let icon: String
    var color: Color = .white
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isHovered ? .white : color)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(isHovered ? color.opacity(0.9) : Color.black.opacity(0.7))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

