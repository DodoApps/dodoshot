import AppKit
import CoreGraphics
import Foundation
// MARK: - SwiftUI Overlay View
import SwiftUI

/// Service for capturing scrolling content by stitching multiple screenshots
class ScrollingCaptureService: ObservableObject {
    static let shared = ScrollingCaptureService()

    @Published var isCapturing = false
    @Published var capturedFrames: [NSImage] = []
    @Published var progress: CGFloat = 0

    private var scrollWindow: NSWindow?
    private var targetWindow: WindowInfo?
    private var captureTimer: Timer?
    private var lastScrollPosition: CGFloat = 0
    private var scrollDirection: ScrollDirection = .down
    private var onComplete: ((NSImage?) -> Void)?

    enum ScrollDirection {
        case down
        case up
    }

    private init() {}

    // MARK: - Public Methods

    /// Start scrolling capture for a specific window
    func startScrollingCapture(
        for window: WindowInfo, direction: ScrollDirection = .down,
        completion: @escaping (NSImage?) -> Void
    ) {
        guard !isCapturing else { return }

        self.isCapturing = true
        self.capturedFrames = []
        self.progress = 0
        self.targetWindow = window
        self.scrollDirection = direction
        self.onComplete = completion

        // Show the scrolling capture overlay
        showScrollingOverlay(for: window)
    }

    /// Manual capture mode - user controls scrolling
    func captureCurrentFrame() {
        guard let window = targetWindow else { return }

        if let image = captureWindowFrame(window) {
            self.capturedFrames.append(image)
            self.progress = min(1.0, CGFloat(self.capturedFrames.count) / 10.0)
        }
    }

    /// Finish capture and stitch images
    func finishCapture() {
        isCapturing = false
        scrollWindow?.close()
        scrollWindow = nil
        captureTimer?.invalidate()
        captureTimer = nil

        // Stitch captured frames
        if capturedFrames.count > 0 {
            let stitchedImage = stitchImages(capturedFrames, direction: scrollDirection)
            onComplete?(stitchedImage)
        } else {
            onComplete?(nil)
        }

        capturedFrames = []
        progress = 0
        targetWindow = nil
    }

    /// Cancel the capture
    func cancelCapture() {
        isCapturing = false
        scrollWindow?.close()
        scrollWindow = nil
        captureTimer?.invalidate()
        captureTimer = nil
        capturedFrames = []
        progress = 0
        targetWindow = nil
        onComplete?(nil)
    }

    // MARK: - Private Methods

    private func showScrollingOverlay(for window: WindowInfo) {
        let windowFrame = window.frame

        // Get screen for proper coordinate conversion
        guard
            let screen = NSScreen.screens.first(where: { screen in
                screen.frame.intersects(windowFrame)
            }) ?? NSScreen.main
        else {
            cancelCapture()
            return
        }

        // Convert to screen coordinates (flip Y)
        let screenHeight = screen.frame.height
        let flippedY = screenHeight - windowFrame.origin.y - windowFrame.height
        let overlayFrame = CGRect(
            x: windowFrame.origin.x,
            y: flippedY,
            width: windowFrame.width,
            height: windowFrame.height
        )

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let overlayWindow = ScrollingCaptureWindow(
                contentRect: overlayFrame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )

            overlayWindow.level = .floating
            overlayWindow.backgroundColor = .clear
            overlayWindow.isOpaque = false
            overlayWindow.hasShadow = false
            overlayWindow.ignoresMouseEvents = false
            overlayWindow.isReleasedWhenClosed = false
            overlayWindow.onEscape = { [weak self] in
                self?.cancelCapture()
            }
            overlayWindow.onEnter = { [weak self] in
                self?.finishCapture()
            }

            let overlayView = ScrollingCaptureOverlayView(
                service: self,
                windowTitle: window.title ?? window.ownerName ?? "Window"
            )
            overlayWindow.contentView = NSHostingView(rootView: overlayView)
            overlayWindow.makeKeyAndOrderFront(nil)

            self.scrollWindow = overlayWindow

            // Capture first frame immediately
            self.captureCurrentFrame()
        }
    }

    private func captureWindowFrame(_ window: WindowInfo) -> NSImage? {
        guard
            let cgImage = LegacyWindowImageCapture.createImage(
                window.frame,
                .optionIncludingWindow,
                window.windowID,
                [.bestResolution, .boundsIgnoreFraming]
            )
        else {
            print("Failed to capture window frame")
            return nil
        }

        return NSImage(
            cgImage: cgImage,
            size: NSSize(
                width: window.frame.width,
                height: window.frame.height
            ))
    }

    /// Stitch multiple images together vertically
    private func stitchImages(_ images: [NSImage], direction: ScrollDirection) -> NSImage? {
        guard !images.isEmpty else { return nil }
        guard images.count > 1 else { return images.first }

        // Find overlapping regions and stitch
        var stitchedImages: [NSImage] = [images[0]]

        for i in 1..<images.count {
            let previousImage = stitchedImages.last!
            let currentImage = images[i]

            // Find overlap between consecutive images
            if let stitched = stitchTwoImages(previousImage, currentImage, direction: direction) {
                stitchedImages[stitchedImages.count - 1] = stitched
            } else {
                // If no overlap found, just append vertically
                if let combined = combineVertically(
                    stitchedImages.last!, currentImage, direction: direction)
                {
                    stitchedImages[stitchedImages.count - 1] = combined
                }
            }
        }

        return stitchedImages.last
    }

    /// Stitch two images by finding overlapping region
    private func stitchTwoImages(_ top: NSImage, _ bottom: NSImage, direction: ScrollDirection)
        -> NSImage?
    {
        guard let topCG = top.cgImage(forProposedRect: nil, context: nil, hints: nil),
            let bottomCG = bottom.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            return nil
        }

        // Find overlap using image comparison
        let overlapHeight = findOverlap(topImage: topCG, bottomImage: bottomCG)

        if overlapHeight > 0 {
            // Create combined image
            let totalHeight = top.size.height + bottom.size.height - CGFloat(overlapHeight)
            let width = max(top.size.width, bottom.size.width)

            let newImage = NSImage(size: NSSize(width: width, height: totalHeight))
            newImage.lockFocus()

            if direction == .down {
                // Draw top image at top
                top.draw(
                    in: NSRect(
                        x: 0, y: totalHeight - top.size.height, width: top.size.width,
                        height: top.size.height))
                // Draw bottom image below, accounting for overlap
                bottom.draw(
                    in: NSRect(x: 0, y: 0, width: bottom.size.width, height: bottom.size.height))
            } else {
                // For upward scrolling, reverse order
                bottom.draw(
                    in: NSRect(
                        x: 0, y: totalHeight - bottom.size.height, width: bottom.size.width,
                        height: bottom.size.height))
                top.draw(in: NSRect(x: 0, y: 0, width: top.size.width, height: top.size.height))
            }

            newImage.unlockFocus()
            return newImage
        }

        return nil
    }

    /// Find vertical overlap between two images
    private func findOverlap(topImage: CGImage, bottomImage: CGImage) -> Int {
        let maxOverlap = min(topImage.height, bottomImage.height) / 2
        let stripHeight = 20  // Compare 20-pixel strips

        guard let topData = topImage.dataProvider?.data,
            let bottomData = bottomImage.dataProvider?.data
        else {
            return 0
        }

        let topPtr = CFDataGetBytePtr(topData)
        let bottomPtr = CFDataGetBytePtr(bottomData)

        let bytesPerRow = topImage.bytesPerRow
        let width = min(topImage.width, bottomImage.width)

        // Search for matching rows
        for overlap in stride(from: stripHeight, to: maxOverlap, by: stripHeight) {
            var matches = 0
            let samplesNeeded = 5

            for sample in 0..<samplesNeeded {
                let topRow = topImage.height - overlap + (sample * stripHeight / samplesNeeded)
                let bottomRow = sample * stripHeight / samplesNeeded

                if compareRows(
                    topPtr, bottomPtr, topRow: topRow, bottomRow: bottomRow,
                    bytesPerRow: bytesPerRow, width: width)
                {
                    matches += 1
                }
            }

            if matches >= samplesNeeded - 1 {
                return overlap
            }
        }

        return 0
    }

    /// Compare two rows of pixels
    private func compareRows(
        _ topPtr: UnsafePointer<UInt8>?, _ bottomPtr: UnsafePointer<UInt8>?, topRow: Int,
        bottomRow: Int, bytesPerRow: Int, width: Int
    ) -> Bool {
        guard let topPtr = topPtr, let bottomPtr = bottomPtr else { return false }

        let topOffset = topRow * bytesPerRow
        let bottomOffset = bottomRow * bytesPerRow

        var differences = 0
        let tolerance = 10  // Allow some color difference
        let sampleInterval = max(1, width / 100)  // Sample 100 pixels across width

        for x in stride(from: 0, to: width * 4, by: sampleInterval * 4) {
            for channel in 0..<3 {  // RGB
                let topValue = Int(topPtr[topOffset + x + channel])
                let bottomValue = Int(bottomPtr[bottomOffset + x + channel])
                if abs(topValue - bottomValue) > tolerance {
                    differences += 1
                }
            }
        }

        return differences < 10
    }

    /// Combine two images vertically without overlap detection
    private func combineVertically(_ top: NSImage, _ bottom: NSImage, direction: ScrollDirection)
        -> NSImage?
    {
        let totalHeight = top.size.height + bottom.size.height
        let width = max(top.size.width, bottom.size.width)

        let newImage = NSImage(size: NSSize(width: width, height: totalHeight))
        newImage.lockFocus()

        if direction == .down {
            top.draw(
                in: NSRect(
                    x: 0, y: bottom.size.height, width: top.size.width, height: top.size.height))
            bottom.draw(
                in: NSRect(x: 0, y: 0, width: bottom.size.width, height: bottom.size.height))
        } else {
            bottom.draw(
                in: NSRect(
                    x: 0, y: top.size.height, width: bottom.size.width, height: bottom.size.height))
            top.draw(in: NSRect(x: 0, y: 0, width: top.size.width, height: top.size.height))
        }

        newImage.unlockFocus()
        return newImage
    }
}

struct ScrollingCaptureOverlayView: View {
    @ObservedObject var service: ScrollingCaptureService
    let windowTitle: String

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.3)

            VStack(spacing: 16) {
                // Header
                HStack {
                    Image(systemName: "scroll")
                        .font(.system(size: 24))
                    Text("Scrolling capture")
                        .font(.headline)
                }
                .foregroundColor(.white)

                Text("Scroll in the window behind, then click capture for each section")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)

                // Progress indicator
                VStack(spacing: 8) {
                    Text("\(service.capturedFrames.count) frames captured")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)

                    ProgressView(value: service.progress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .orange))
                        .frame(width: 200)
                }

                // Action buttons
                HStack(spacing: 12) {
                    Button(action: { service.captureCurrentFrame() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "camera.fill")
                            Text("Capture")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

                    Button(action: { service.finishCapture() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark")
                            Text("Done")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(service.capturedFrames.isEmpty)

                    Button(action: { service.cancelCapture() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark")
                            Text("Cancel")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }

                // Instructions
                Text("Press ESC to cancel • Press Enter when done")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.7))
                    .shadow(radius: 10)
            )
        }
    }
}

// MARK: - Scrolling Capture Window (handles ESC key properly)
class ScrollingCaptureWindow: NSWindow {
    var onEscape: (() -> Void)?
    var onEnter: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {  // ESC key
            onEscape?()
        } else if event.keyCode == 36 {  // Enter key
            onEnter?()
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
            return true
        }
        if event.keyCode == 36 {  // Enter key
            onEnter?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
