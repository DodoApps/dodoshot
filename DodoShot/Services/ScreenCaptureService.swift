import AppKit
import Combine
import Foundation
// MARK: - NSHostingView Helper
import SwiftUI

// Centralized compatibility wrapper to avoid direct deprecated symbol usage in Swift call sites.
@_silgen_name("CGWindowListCreateImage")
private func _legacyCGWindowListCreateImage(
    _ screenBounds: CGRect,
    _ listOption: UInt32,
    _ windowID: UInt32,
    _ imageOption: UInt32
) -> Unmanaged<CGImage>?

enum LegacyWindowImageCapture {
    static func createImage(
        _ screenBounds: CGRect,
        _ listOption: CGWindowListOption,
        _ windowID: CGWindowID,
        _ imageOption: CGWindowImageOption
    ) -> CGImage? {
        guard
            let unmanagedImage = _legacyCGWindowListCreateImage(
                screenBounds,
                listOption.rawValue,
                windowID,
                imageOption.rawValue
            )
        else {
            return nil
        }
        return unmanagedImage.takeRetainedValue()
    }
}

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

    /// Show the timed capture modal for selecting delay
    func showTimedCaptureModal() {
        guard let screen = NSScreen.main else { return }

        let windowSize = NSSize(width: 280, height: 200)
        let windowOrigin = NSPoint(
            x: (screen.visibleFrame.width - windowSize.width) / 2 + screen.visibleFrame.origin.x,
            y: (screen.visibleFrame.height - windowSize.height) / 2 + screen.visibleFrame.origin.y
        )

        let window = NSWindow(
            contentRect: NSRect(origin: windowOrigin, size: windowSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "Timed capture"
        window.level = .floating
        window.isReleasedWhenClosed = false

        let modalView = TimedCaptureModalView(
            onSelect: { [weak self] seconds in
                window.close()
                self?.startTimedCapture(delay: Double(seconds))
            },
            onCancel: {
                window.close()
            }
        )

        window.contentView = NSHostingView(rootView: modalView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Start a timed fullscreen capture after a delay (useful for capturing menus/dropdowns)
    func startTimedCapture(delay: Double) {
        isCapturing = true

        // Show a countdown notification
        showTimedCaptureCountdown(seconds: Int(delay))

        // Capture after the delay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.captureFullscreen()
        }
    }

    private func showTimedCaptureCountdown(seconds: Int) {
        // Show a small floating countdown window
        guard let screen = NSScreen.main else { return }

        let windowSize = NSSize(width: 120, height: 120)
        let windowOrigin = NSPoint(
            x: (screen.visibleFrame.width - windowSize.width) / 2 + screen.visibleFrame.origin.x,
            y: (screen.visibleFrame.height - windowSize.height) / 2 + screen.visibleFrame.origin.y
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
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let countdownView = TimedCaptureCountdownView(seconds: seconds) {
            window.close()
        }

        window.contentView = NSHostingView(rootView: countdownView)
        window.orderFront(nil)
    }

    func copyToClipboard(_ screenshot: Screenshot) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([screenshot.image])
    }

    /// Start OCR capture - select an area and extract text
    func startOCRCapture() {
        isCapturing = true

        guard let screen = NSScreen.main else {
            isCapturing = false
            return
        }

        let window = createCaptureOverlayWindow(for: screen)
        let contentView = AreaSelectionView(
            onComplete: { [weak self] rect in
                self?.captureAreaForOCR(rect: rect, screen: screen)
            },
            onCancel: { [weak self] in
                self?.cancelCapture()
            }
        )

        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        captureWindows.append(window)
    }

    private func captureAreaForOCR(rect: CGRect, screen: NSScreen) {
        // Hide capture windows first
        for window in captureWindows {
            window.orderOut(nil)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self else { return }

            // Convert to global display coordinates
            // Both SwiftUI and CGWindowListCreateImage use top-left origin with Y increasing downward
            let screenRect = CGRect(
                x: rect.origin.x + screen.frame.origin.x,
                y: rect.origin.y + screen.frame.origin.y,
                width: rect.width,
                height: rect.height
            )

            guard
                let cgImage = LegacyWindowImageCapture.createImage(
                    screenRect,
                    .optionOnScreenOnly,
                    kCGNullWindowID,
                    [.bestResolution]
                )
            else {
                self.isCapturing = false
                self.closeCaptureWindows()
                return
            }

            // Use rect.size (points) not cgImage size (pixels) for correct Retina display
            let nsImage = NSImage(cgImage: cgImage, size: rect.size)
            self.closeCaptureWindows()
            self.isCapturing = false

            // Perform OCR
            OCRService.shared.extractText(from: nsImage) { result in
                switch result {
                case .success(let text):
                    // Copy to clipboard and show notification
                    OCRService.shared.copyToClipboard(text)
                    self.showOCRResult(text: text)
                case .failure(let error):
                    self.showOCRError(error: error)
                }
            }
        }
    }

    private func showOCRResult(text: String) {
        guard let screen = NSScreen.main else { return }

        let windowSize = NSSize(width: 400, height: 300)
        let windowOrigin = NSPoint(
            x: (screen.visibleFrame.width - windowSize.width) / 2 + screen.visibleFrame.origin.x,
            y: (screen.visibleFrame.height - windowSize.height) / 2 + screen.visibleFrame.origin.y
        )

        let window = NSWindow(
            contentRect: NSRect(origin: windowOrigin, size: windowSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "Extracted text"
        window.level = .floating
        window.isReleasedWhenClosed = false

        let resultView = OCRResultView(text: text) {
            window.close()
        }

        window.contentView = NSHostingView(rootView: resultView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showOCRError(error: Error) {
        let alert = NSAlert()
        alert.messageText = "OCR failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    func saveToFile(_ screenshot: Screenshot, url: URL? = nil) {
        let saveURL = url ?? getDefaultSaveURL()
        let settings = SettingsManager.shared.settings

        // Ensure save directory exists
        let saveDirectory = saveURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: saveDirectory.path) {
            do {
                try FileManager.default.createDirectory(
                    at: saveDirectory, withIntermediateDirectories: true)
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

            // Log the input rect and screen info for debugging
            let scaleFactor = screen.backingScaleFactor
            NSLog(
                "[ScreenCaptureService] captureArea - input rect: %@, screen: %@, scaleFactor: %.1f",
                NSStringFromRect(rect), NSStringFromRect(screen.frame), scaleFactor)

            // Round the rect to integer values to avoid fractional pixel issues
            let roundedRect = CGRect(
                x: round(rect.origin.x),
                y: round(rect.origin.y),
                width: round(rect.width),
                height: round(rect.height)
            )

            // The rect from SwiftUI is in the window's coordinate space where:
            // - Origin (0,0) is at TOP-LEFT of the window
            // - Y increases downward
            //
            // CGWindowListCreateImage expects global display coordinates where:
            // - Origin (0,0) is at TOP-LEFT of the main display
            // - Y increases downward
            //
            // Since our capture window covers the entire screen starting at screen.frame.origin,
            // we just need to add the screen's origin to convert to global coordinates.
            // No Y-flip needed because both coordinate systems have Y increasing downward.
            let screenRect = CGRect(
                x: roundedRect.origin.x + screen.frame.origin.x,
                y: roundedRect.origin.y + screen.frame.origin.y,
                width: roundedRect.width,
                height: roundedRect.height
            )

            NSLog(
                "[ScreenCaptureService] captureArea - screenRect for capture: %@",
                NSStringFromRect(screenRect))

            // Use CGWindowListCreateImage for capture
            guard
                let cgImage = LegacyWindowImageCapture.createImage(
                    screenRect,
                    .optionOnScreenOnly,
                    kCGNullWindowID,
                    [.bestResolution]
                )
            else {
                NSLog("[ScreenCaptureService] captureArea - CGWindowListCreateImage failed")
                self.isCapturing = false
                self.closeCaptureWindows()
                return
            }

            NSLog(
                "[ScreenCaptureService] captureArea - cgImage size: %d x %d, expected points: %.0f x %.0f",
                cgImage.width, cgImage.height, roundedRect.width, roundedRect.height)

            // Create NSImage with the rounded rect size (in points)
            // The cgImage contains high-res pixels, NSImage size is in points
            let nsImage = NSImage(cgImage: cgImage, size: roundedRect.size)
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

        guard
            let cgImage = LegacyWindowImageCapture.createImage(
                windowInfo.frame,
                .optionIncludingWindow,
                windowInfo.windowID,
                [.bestResolution, .boundsIgnoreFraming]
            )
        else {
            isCapturing = false
            return
        }

        // Use windowInfo.frame.size (points) not cgImage size (pixels) for correct Retina display
        let nsImage = NSImage(cgImage: cgImage, size: windowInfo.frame.size)
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

            self.completeCapture(image: image, type: .fullscreen)  // Using fullscreen type for scrolling
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
            guard
                let cgImage = LegacyWindowImageCapture.createImage(
                    screen.frame,
                    .optionOnScreenOnly,
                    kCGNullWindowID,
                    [.bestResolution]
                )
            else {
                self?.isCapturing = false
                return
            }

            // Use screen.frame.size (points) not cgImage size (pixels) for correct Retina display
            let nsImage = NSImage(cgImage: cgImage, size: screen.frame.size)
            self?.completeCapture(image: nsImage, type: .fullscreen)
        }
    }

    // MARK: - Capture Completion

    private func completeCapture(image: NSImage, type: CaptureType) {
        NSLog("[ScreenCaptureService] completeCapture started")

        // Convert NSImage to PNG Data ONCE
        // This creates a completely independent byte buffer with no references to the original image
        guard let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            NSLog("[ScreenCaptureService] Failed to convert image to PNG data")
            isCapturing = false
            return
        }

        let imageSize = image.size
        NSLog(
            "[ScreenCaptureService] PNG data created, size: %d bytes, image size: %@",
            pngData.count, NSStringFromSize(imageSize))

        // Create screenshot directly from PNG data - no NSImage intermediaries
        // Use a single shared ID so history and editor refer to the same logical screenshot
        let screenshotId = UUID()
        let capturedAt = Date()

        let screenshot = Screenshot(
            id: screenshotId,
            pngData: pngData,
            imageSize: imageSize,
            capturedAt: capturedAt,
            captureType: type
        )

        NSLog("[ScreenCaptureService] Screenshot created with id: %@", screenshotId.uuidString)

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

        // Open the annotation editor
        // Pass the PNG data and metadata directly to avoid any reference issues
        openEditorDirectly(
            pngData: pngData,
            imageSize: imageSize,
            screenshotId: screenshotId,
            capturedAt: capturedAt,
            captureType: type
        )

        isCapturing = false
        NSLog("[ScreenCaptureService] completeCapture finished")
    }

    /// Opens the annotation editor directly using PNG data (avoids all reference issues)
    private func openEditorDirectly(
        pngData: Data,
        imageSize: CGSize,
        screenshotId: UUID,
        capturedAt: Date,
        captureType: CaptureType
    ) {
        NSLog(
            "[ScreenCaptureService] openEditorDirectly called with screenshot id: %@",
            screenshotId.uuidString)

        // Create a fresh Screenshot from the PNG data for the editor
        // This is completely independent - just bytes in memory
        let editorScreenshot = Screenshot(
            id: screenshotId,
            pngData: pngData,
            imageSize: imageSize,
            capturedAt: capturedAt,
            captureType: captureType
        )

        NSLog("[ScreenCaptureService] About to call showEditor")
        AnnotationEditorWindowController.shared.showEditor(for: editorScreenshot) {
            updatedScreenshot in
            NSLog("[ScreenCaptureService] Save callback invoked")
            Task { @MainActor in
                ScreenCaptureService.shared.saveToFile(updatedScreenshot)
            }
        }
        NSLog("[ScreenCaptureService] showEditor returned")
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

// Removed problematic NSHostingView extension that caused infinite recursion

// MARK: - OCR Result View
struct OCRResultView: View {
    let text: String
    let onDismiss: () -> Void

    @State private var copied = false

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 18))
                Text("Text copied to clipboard")
                    .font(.system(size: 14, weight: .medium))
                Spacer()
            }

            ScrollView {
                Text(text)
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.05))
            )

            HStack {
                Button(action: {
                    OCRService.shared.copyToClipboard(text)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copied = false
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: copied ? "checkmark" : "doc.on.clipboard")
                        Text(copied ? "Copied" : "Copy again")
                    }
                    .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.08))
                )

                Spacer()

                Button("Close") {
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400, height: 300)
    }
}

// MARK: - Timed Capture Modal View
struct TimedCaptureModalView: View {
    let onSelect: (Int) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Select timer delay")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)

            HStack(spacing: 16) {
                TimerOptionButton(seconds: 3, onSelect: onSelect)
                TimerOptionButton(seconds: 5, onSelect: onSelect)
                TimerOptionButton(seconds: 10, onSelect: onSelect)
            }

            Button("Cancel") {
                onCancel()
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .font(.system(size: 12))
        }
        .padding(24)
        .frame(width: 280, height: 180)
    }
}

struct TimerOptionButton: View {
    let seconds: Int
    let onSelect: (Int) -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: { onSelect(seconds) }) {
            VStack(spacing: 6) {
                Text("\(seconds)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(isHovered ? .white : .primary)

                Text("sec")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isHovered ? .white.opacity(0.8) : .secondary)
            }
            .frame(width: 70, height: 70)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isHovered ? Color.orange : Color.primary.opacity(0.08))
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

// MARK: - Timed Capture Countdown View
struct TimedCaptureCountdownView: View {
    let seconds: Int
    let onComplete: () -> Void

    @State private var countdown: Int

    init(seconds: Int, onComplete: @escaping () -> Void) {
        self.seconds = seconds
        self.onComplete = onComplete
        self._countdown = State(initialValue: seconds)
    }

    var body: some View {
        ZStack {
            // Background
            Circle()
                .fill(Color.black.opacity(0.85))
                .frame(width: 100, height: 100)

            // Progress ring
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 6)
                .frame(width: 90, height: 90)

            Circle()
                .trim(from: 0, to: CGFloat(countdown) / CGFloat(seconds))
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .frame(width: 90, height: 90)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: countdown)

            // Countdown number
            Text("\(countdown)")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(width: 120, height: 120)
        .onAppear {
            startCountdown()
        }
    }

    private func startCountdown() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if countdown > 1 {
                countdown -= 1
            } else {
                timer.invalidate()
                onComplete()
            }
        }
    }
}

// MARK: - Capture Window (handles ESC key)
class CaptureWindow: NSWindow {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {  // ESC key
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
        if event.keyCode == 53 {  // ESC key
            onEscape?()
            return true  // Event handled, don't propagate
        }
        return super.performKeyEquivalent(with: event)
    }
}
