import Foundation
import AppKit

/// Window information retrieved via CGWindowList API (doesn't trigger permission dialogs)
struct WindowInfo: Identifiable {
    let id: CGWindowID
    let windowID: CGWindowID
    let frame: CGRect
    let title: String?
    let ownerName: String?
    let ownerPID: pid_t
    let bundleIdentifier: String?

    init?(from dict: [String: Any]) {
        guard let windowID = dict[kCGWindowNumber as String] as? CGWindowID,
              let boundsDict = dict[kCGWindowBounds as String] as? [String: Any],
              let x = boundsDict["X"] as? CGFloat,
              let y = boundsDict["Y"] as? CGFloat,
              let width = boundsDict["Width"] as? CGFloat,
              let height = boundsDict["Height"] as? CGFloat else {
            return nil
        }

        self.id = windowID
        self.windowID = windowID
        self.frame = CGRect(x: x, y: y, width: width, height: height)
        self.title = dict[kCGWindowName as String] as? String
        self.ownerName = dict[kCGWindowOwnerName as String] as? String
        self.ownerPID = dict[kCGWindowOwnerPID as String] as? pid_t ?? 0

        // Try to get bundle identifier from PID
        if let app = NSRunningApplication(processIdentifier: ownerPID) {
            self.bundleIdentifier = app.bundleIdentifier
        } else {
            self.bundleIdentifier = nil
        }
    }

    /// Get list of visible windows using CGWindowList API (no permission dialog)
    static func getVisibleWindows() -> [WindowInfo] {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let myBundleID = Bundle.main.bundleIdentifier

        // System processes to exclude from window capture
        let excludedOwners = ["Dock", "Window Server", "SystemUIServer", "Spotlight"]
        let excludedBundleIDs = ["com.apple.dock", "com.apple.WindowServer", "com.apple.systemuiserver", "com.apple.Spotlight"]

        return windowList.compactMap { WindowInfo(from: $0) }
            .filter { window in
                // Filter out small windows, our own app, and system processes
                window.frame.width > 100 &&
                window.frame.height > 100 &&
                window.bundleIdentifier != myBundleID &&
                window.ownerName != nil &&
                !excludedOwners.contains(window.ownerName ?? "") &&
                !excludedBundleIDs.contains(window.bundleIdentifier ?? "")
            }
    }
}
