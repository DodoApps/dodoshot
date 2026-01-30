import Foundation
import AppKit
import Combine

@MainActor
class ScreenCaptureService: ObservableObject {
    static let shared = ScreenCaptureService()

    @Published var recentCaptures: [Screenshot] = []
    @Published var currentCapture: Screenshot?
    @Published var isCapturing = false

    private var captureWindows: [NSWindow] = []
    private var overlayWindow: NSWindow?

    private init() {}

    // MARK: - Public Methods

    func startCapture(type: CaptureType) {
        isCapturing = true

        switch type {
        case .area:
            startAreaCapture()
        case .window:
            startWindowCapture()
        case .fullscreen:
            captureFullscreen()
        }
    }

    func clearRecents() {
        recentCaptures.removeAll()
    }

    func startScrollingCapture() {
        isCapturing = true

        // Get windows using CGWindowList API (no permission dialog)
        let windows = WindowInfo.getVisibleWindows()

        if windows.isEmpty {
            print("No windows found for scrolling capture")
            isCapturing = false
            return
        }

        showWindowPickerForScrolling(windows: windows)
    }

    func copyToClipboard(_ screenshot: Screenshot) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([screenshot.image])
    }

    func saveToFile(_ screenshot: Screenshot, url: URL? = nil) {
        let saveURL = url ?? getDefaultSaveURL()
        let settings = SettingsManager.shared.settings

        // Ensure save directory exists
        let saveDirectory = saveURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: saveDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
            } catch {
                print("Failed to create screenshots directory: \(error)")
            }
        }

        // Use ImageFormatAnalyzer for intelligent format selection
        if let savedURL = ImageFormatAnalyzer.shared.saveImage(
            screenshot.image,
            to: saveURL,
            format: settings.imageFormat,
            jpgQuality: settings.jpgQuality
        ) {
            print("Screenshot saved to: \(savedURL.path)")
        }
    }

    // MARK: - Area Capture

    private func startAreaCapture() {
        // Close any existing capture windows first
        closeCaptureWindows()

        // Get all screens for multi-monitor support
        let screens = NSScreen.screens

        // Create overlay windows for each screen
        for screen in screens {
            let window = createCaptureOverlayWindow(for: screen)
            let contentView = AreaSelectionView(
                onComplete: { [weak self] rect in
                    self?.captureArea(rect: rect, screen: screen)
                },
                onCancel: { [weak self] in
                    self?.cancelCapture()
                }
            )

            window.contentView = NSHostingView(rootView: contentView)
            window.makeKeyAndOrderFront(nil)
            captureWindows.append(window)
        }
    }

    private func createCaptureOverlayWindow(for screen: NSScreen) -> CaptureWindow {
        let window = CaptureWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.onEscape = { [weak self] in
            self?.cancelCapture()
        }

        return window
    }

    private func captureArea(rect: CGRect, screen: NSScreen) {
        // Hide all capture windows first
        for window in captureWindows {
            window.orderOut(nil)
        }

        // Small delay to ensure windows are hidden before capture
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self else { return }

            // Convert to screen coordinates
            let screenRect = CGRect(
                x: rect.origin.x + screen.frame.origin.x,
                y: screen.frame.height - rect.origin.y - rect.height + screen.frame.origin.y,
                width: rect.width,
                height: rect.height
            )

            // Use CGWindowListCreateImage for capture
            guard let cgImage = CGWindowListCreateImage(
                screenRect,
                .optionOnScreenBelowWindow,
                kCGNullWindowID,
                [.bestResolution]
            ) else {
                self.isCapturing = false
                self.closeCaptureWindows()
                return
            }

            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            self.closeCaptureWindows()
            self.completeCapture(image: nsImage, type: .area)
        }
    }

    // MARK: - Window Capture

    private func startWindowCapture() {
        // Get windows using CGWindowList API (no permission dialog)
        let windows = WindowInfo.getVisibleWindows()

        if windows.isEmpty {
            print("No windows found for capture")
            isCapturing = false
            return
        }

        // Auto-capture the frontmost window (first in the list, excluding DodoShot itself)
        if let frontmostWindow = windows.first(where: { $0.ownerName != "DodoShot" }) {
            captureWindow(frontmostWindow)
        } else if let firstWindow = windows.first {
            // Fallback to first window if all are DodoShot windows
            captureWindow(firstWindow)
        } else {
            isCapturing = false
        }
    }

    private func showWindowPicker(windows: [WindowInfo]) {
        guard let screen = NSScreen.main else { return }

        let window = createCaptureOverlayWindow(for: screen)
        let contentView = WindowSelectionView(
            windows: windows,
            onSelect: { [weak self] selectedWindow in
                self?.captureWindow(selectedWindow)
            },
            onCancel: { [weak self] in
                self?.cancelCapture()
            }
        )

        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        captureWindows.append(window)
    }

    private func captureWindow(_ windowInfo: WindowInfo) {
        closeCaptureWindows()

        guard let cgImage = CGWindowListCreateImage(
            windowInfo.frame,
            .optionIncludingWindow,
            windowInfo.windowID,
            [.bestResolution, .boundsIgnoreFraming]
        ) else {
            isCapturing = false
            return
        }

        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        completeCapture(image: nsImage, type: .window)
    }

    // MARK: - Scrolling Capture

    private func showWindowPickerForScrolling(windows: [WindowInfo]) {
        guard let screen = NSScreen.main else { return }

        let window = createCaptureOverlayWindow(for: screen)
        let contentView = WindowSelectionView(
            windows: windows,
            onSelect: { [weak self] selectedWindow in
                self?.startScrollingCaptureForWindow(selectedWindow)
            },
            onCancel: { [weak self] in
                self?.cancelCapture()
            },
            title: "Select window for scrolling capture"
        )

        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        captureWindows.append(window)
    }

    private func startScrollingCaptureForWindow(_ windowInfo: WindowInfo) {
        closeCaptureWindows()

        ScrollingCaptureService.shared.startScrollingCapture(for: windowInfo) { [weak self] image in
            guard let self = self, let image = image else {
                self?.isCapturing = false
                return
            }

            self.completeCapture(image: image, type: .fullscreen) // Using fullscreen type for scrolling
        }
    }

    // MARK: - Fullscreen Capture

    private func captureFullscreen() {
        guard let screen = NSScreen.main else {
            isCapturing = false
            return
        }

        // Small delay to ensure menu bar closes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let cgImage = CGWindowListCreateImage(
                screen.frame,
                .optionOnScreenOnly,
                kCGNullWindowID,
                [.bestResolution]
            ) else {
                self?.isCapturing = false
                return
            }

            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            self?.completeCapture(image: nsImage, type: .fullscreen)
        }
    }

    // MARK: - Capture Completion

    private func completeCapture(image: NSImage, type: CaptureType) {
        let screenshot = Screenshot(image: image, captureType: type)

        currentCapture = screenshot
        recentCaptures.insert(screenshot, at: 0)

        // Keep only last 10 captures
        if recentCaptures.count > 10 {
            recentCaptures = Array(recentCaptures.prefix(10))
        }

        // Auto copy to clipboard
        if SettingsManager.shared.settings.autoCopyToClipboard {
            copyToClipboard(screenshot)
        }

        // Show quick overlay
        if SettingsManager.shared.settings.showQuickOverlay {
            showQuickOverlay(for: screenshot)
        }

        isCapturing = false
    }

    private func showQuickOverlay(for screenshot: Screenshot) {
        // Use the new stacking overlay manager (CleanShot X style)
        QuickOverlayManager.shared.showOverlay(for: screenshot)
    }

    @available(*, deprecated, message: "Use QuickOverlayManager instead")
    private func showQuickOverlayLegacy(for screenshot: Screenshot) {
        guard let screen = NSScreen.main else { return }

        let overlaySize = NSSize(width: 320, height: 280)
        let overlayOrigin = NSPoint(
            x: screen.visibleFrame.maxX - overlaySize.width - 20,
            y: screen.visibleFrame.maxY - overlaySize.height - 20
        )

        let window = NSWindow(
            contentRect: NSRect(origin: overlayOrigin, size: overlaySize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true

        let contentView = QuickOverlayView(
            screenshot: screenshot,
            onDismiss: { [weak self] in
                self?.closeOverlayWindow()
            }
        )

        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        overlayWindow = window

        // Auto dismiss after 5 seconds if not interacted
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.closeOverlayWindow()
        }
    }

    // MARK: - Helpers

    private func closeCaptureWindows() {
        for window in captureWindows {
            window.close()
        }
        captureWindows.removeAll()
    }

    private func closeOverlayWindow() {
        overlayWindow?.close()
        overlayWindow = nil
    }

    private func cancelCapture() {
        closeCaptureWindows()
        isCapturing = false
    }

    private func getDefaultSaveURL() -> URL {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "DodoShot_\(dateFormatter.string(from: Date())).png"

        let saveLocation = SettingsManager.shared.settings.saveLocation
        return URL(fileURLWithPath: saveLocation).appendingPathComponent(filename)
    }
}

// MARK: - NSHostingView Helper
import SwiftUI

// Removed problematic NSHostingView extension that caused infinite recursion

// MARK: - Capture Window (handles ESC key)
class CaptureWindow: NSWindow {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC key
            onEscape?()
            // Don't call super - consume the event completely
        } else {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        // Handle ESC/Cmd+. - don't propagate to prevent app termination
        onEscape?()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 53 { // ESC key
            onEscape?()
            return true // Event handled, don't propagate
        }
        return super.performKeyEquivalent(with: event)
    }
}
