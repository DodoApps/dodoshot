import Foundation
import AppKit
import Combine

/// Manager for handling Screen Recording and Accessibility permissions
final class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    /// Whether screen recording permission is granted
    @Published var isScreenRecordingGranted: Bool = false

    /// Whether accessibility permission is granted
    @Published var isAccessibilityGranted: Bool = false

    /// Timer for checking permission status
    private var checkTimer: Timer?

    /// Flag to prevent repeated screen recording checks while system dialog is open
    private var isCheckingScreenRecording: Bool = false

    private init() {
        checkPermissions()
        // Don't auto-start monitoring - let the UI start it when needed
    }

    deinit {
        checkTimer?.invalidate()
    }

    // MARK: - Public Methods

    /// Check all permissions
    func checkPermissions() {
        checkScreenRecordingPermission()
        checkAccessibilityPermission()
    }

    /// Check screen recording permission
    func checkScreenRecordingPermission() {
        // CGPreflightScreenCaptureAccess is UNRELIABLE - it often returns true even without permission
        // The ONLY reliable check is to actually capture and verify we get real content (not gray)
        let hasAccess = canActuallyCaptureScreen()

        NSLog("[PermissionManager] Screen recording check (actual capture test): %@", hasAccess ? "true" : "false")

        DispatchQueue.main.async { [weak self] in
            if self?.isScreenRecordingGranted != hasAccess {
                NSLog("[PermissionManager] Screen recording changed: %@", hasAccess ? "true" : "false")
                self?.isScreenRecordingGranted = hasAccess
            }
        }
    }

    /// Actually try to capture the screen and verify we get real content
    private func canActuallyCaptureScreen() -> Bool {
        // Get the list of windows on screen (excluding our own app)
        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

        // Find a window that's not ours to capture
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        for windowInfo in windowList {
            guard let _ = windowInfo[kCGWindowOwnerName as String] as? String,
                  let windowNumber = windowInfo[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? CGFloat,
                  let height = bounds["Height"] as? CGFloat,
                  width > 10, height > 10 else {
                continue
            }

            // Skip our own windows
            if let ownerBundleID = windowInfo[kCGWindowOwnerPID as String] as? Int32 {
                let app = NSRunningApplication(processIdentifier: ownerBundleID)
                if app?.bundleIdentifier == bundleID {
                    continue
                }
            }

            // Try to capture this specific window
            if let image = CGWindowListCreateImage(.null, .optionIncludingWindow, windowNumber, [.boundsIgnoreFraming]) {
                // Check if the image has actual content by sampling pixels
                // Without permission, we get either nil or an all-gray image
                if imageHasRealContent(image) {
                    return true
                }
            }
        }

        return false
    }

    /// Check if a captured image has real content (not just uniform gray)
    private func imageHasRealContent(_ image: CGImage) -> Bool {
        let width = image.width
        let height = image.height

        guard width > 0, height > 0 else { return false }

        // Create a small bitmap context to sample pixels
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var pixelData = [UInt8](repeating: 0, count: bytesPerRow * height)

        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Sample a few pixels and check for variance
        // If all pixels are the same gray, we don't have real access
        let samplePoints = [
            (width / 4, height / 4),
            (width / 2, height / 2),
            (3 * width / 4, 3 * height / 4),
            (width / 3, 2 * height / 3)
        ]

        var colors = Set<UInt32>()
        for (x, y) in samplePoints {
            let offset = (y * width + x) * bytesPerPixel
            if offset + 3 < pixelData.count {
                let r = pixelData[offset]
                let g = pixelData[offset + 1]
                let b = pixelData[offset + 2]
                let color = UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b)
                colors.insert(color)
            }
        }

        // If we have more than one unique color, we have real content
        return colors.count > 1
    }

    /// Check accessibility permission
    func checkAccessibilityPermission() {
        let trusted = AXIsProcessTrusted()

        // Also check with options for more detailed info
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        let trustedWithOptions = AXIsProcessTrustedWithOptions(options)

        NSLog("[PermissionManager] Accessibility AXIsProcessTrusted: %@, WithOptions: %@",
              trusted ? "true" : "false",
              trustedWithOptions ? "true" : "false")

        // Use the result from AXIsProcessTrustedWithOptions as it's more reliable
        var finalResult = trusted || trustedWithOptions

        // For DEBUG builds, allow bypassing accessibility check since ad-hoc signing
        // causes issues with macOS recognizing the approved app after rebuilds
        #if DEBUG
        if !finalResult {
            // Check if user has previously skipped (stored in UserDefaults)
            if UserDefaults.standard.bool(forKey: "debugAccessibilityBypassed") {
                NSLog("[PermissionManager] DEBUG: Accessibility bypassed by user preference")
                finalResult = true
            }
        }
        #endif

        DispatchQueue.main.async { [weak self] in
            if self?.isAccessibilityGranted != finalResult {
                NSLog("[PermissionManager] Accessibility changed to: %@", finalResult ? "true" : "false")
                self?.isAccessibilityGranted = finalResult
            }
        }
    }

    /// Bypass accessibility check for debug builds
    func bypassAccessibilityForDebug() {
        #if DEBUG
        UserDefaults.standard.set(true, forKey: "debugAccessibilityBypassed")
        isAccessibilityGranted = true
        NSLog("[PermissionManager] DEBUG: Accessibility check bypassed")
        #endif
    }

    /// Request screen recording permission
    func requestScreenRecordingPermission() {
        // Open System Settings to Screen Recording (macOS Ventura and later)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }

        // Fallback: try to trigger the system prompt by attempting a capture
        // This will show the permission dialog if not already granted
        CGRequestScreenCaptureAccess()
    }

    /// Request accessibility permission
    @discardableResult
    func requestAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        DispatchQueue.main.async { [weak self] in
            self?.isAccessibilityGranted = trusted
        }
        return trusted
    }

    /// Open Screen Recording settings
    func openScreenRecordingSettings() {
        // Open System Settings directly to Screen Recording (macOS Sonoma)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Trigger the screen recording system prompt
    func triggerScreenRecordingPrompt() {
        CGRequestScreenCaptureAccess()
    }

    /// Open Accessibility settings
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Show app in Finder (for drag and drop to settings)
    func showAppInFinder() {
        let bundleURL = Bundle.main.bundleURL
        NSWorkspace.shared.selectFile(bundleURL.path, inFileViewerRootedAtPath: bundleURL.deletingLastPathComponent().path)
    }

    /// Restart the app
    func restartApp() {
        guard let bundlePath = Bundle.main.bundlePath as String? else { return }

        let script = """
            sleep 0.5
            open "\(bundlePath)"
            """

        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", script]
        try? task.run()

        NSApp.terminate(nil)
    }

    /// Start monitoring for permission changes
    func startMonitoring() {
        checkTimer?.invalidate()
        checkTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkPermissions()
        }
        RunLoop.main.add(checkTimer!, forMode: .common)
    }

    /// Stop monitoring
    func stopMonitoring() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    /// Whether all required permissions are granted
    var allPermissionsGranted: Bool {
        isScreenRecordingGranted && isAccessibilityGranted
    }
}
