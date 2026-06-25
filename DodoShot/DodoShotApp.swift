import SwiftUI
import AppKit

@main
struct DodoShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var captureService: ScreenCaptureService!
    private var hotkeyManager: HotkeyManager!
    private var settingsWindow: NSWindow?
    private var permissionCheckTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize services
        captureService = ScreenCaptureService.shared
        hotkeyManager = HotkeyManager.shared

        // Set activation policy based on user preference
        let showInDock = SettingsManager.shared.settings.showInDock
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)

        // Setup menu bar
        setupMenuBar()

        // Show permission onboarding if needed, then register hotkeys
        PermissionOnboardingWindowController.shared.showIfNeeded { [weak self] in
            self?.checkPermissionsAndRegisterHotkeys()
            self?.startPermissionMonitoring()

            // Show welcome HUD with shortcuts after permissions are set up
            WelcomeHUDWindowController.shared.showIfNeeded()
        }
    }

    private func checkPermissionsAndRegisterHotkeys() {
        let permissionManager = PermissionManager.shared
        permissionManager.checkPermissions()

        // Try to register hotkeys directly using AXIsProcessTrusted
        // This is more reliable than checking the @Published property
        if AXIsProcessTrusted() {
            hotkeyManager.registerHotkeys()
        } else if permissionManager.isAccessibilityGranted {
            hotkeyManager.registerHotkeys()
        }
    }

    private func startPermissionMonitoring() {
        // Check every 5 seconds if permissions changed.
        // Uses ScreenCaptureKit which provides accurate real-time status
        // without triggering the persistent screen recording indicator.
        // Don't stop polling — macOS can revoke permissions at any time
        // (e.g. after app updates with ad-hoc signing), and
        // CGPreflightScreenCaptureAccess caches stale results per-process.
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            let permissionManager = PermissionManager.shared
            permissionManager.checkPermissions()

            // Register hotkeys once accessibility is granted
            if AXIsProcessTrusted() {
                self?.hotkeyManager.registerHotkeys()
            }
        }
    }

    // MARK: - File Opening

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.pathExtension.lowercased() == "dodo" {
                openDodoProject(at: url)
            }
        }
    }

    private func openDodoProject(at url: URL) {
        do {
            let project = try DodoShotProject.load(from: url)
            if let screenshot = project.toScreenshot() {
                // Screenshot stores image as Data internally, so no deep copy needed
                AnnotationEditorWindowController.shared.showEditor(for: screenshot) { updatedScreenshot in
                    // Save back to the same file
                    do {
                        var updatedProject = project
                        updatedProject.annotations = updatedScreenshot.annotations
                        updatedProject.modifiedAt = Date()
                        try updatedProject.save(to: url)
                    } catch {
                        print("Failed to save project: \(error)")
                    }
                }
            }
        } catch {
            print("Failed to open project: \(error)")
            let alert = NSAlert()
            alert.messageText = "Failed to open project"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Menu bar app should stay running even when all windows are closed
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Log termination for debugging
        print("DodoShot: applicationShouldTerminate called")
        Thread.callStackSymbols.forEach { print($0) }
        return .terminateNow
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            if let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "DodoShot")?.withSymbolConfiguration(config) {
                image.isTemplate = true
                button.image = image
            }
            button.action = #selector(handleStatusItemClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Create popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 400)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: MenuBarView())

        // Create right-click menu
        let menu = NSMenu()

        // Appearance submenu
        let appearanceMenu = NSMenu()
        let darkItem = NSMenuItem(title: "Dark", action: #selector(setDarkMode), keyEquivalent: "")
        let lightItem = NSMenuItem(title: "Light", action: #selector(setLightMode), keyEquivalent: "")
        let systemItem = NSMenuItem(title: "System", action: #selector(setSystemMode), keyEquivalent: "")

        // Mark current mode
        updateAppearanceMenuItems(darkItem: darkItem, lightItem: lightItem, systemItem: systemItem)

        appearanceMenu.addItem(darkItem)
        appearanceMenu.addItem(lightItem)
        appearanceMenu.addItem(systemItem)

        let appearanceMenuItem = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        appearanceMenuItem.submenu = appearanceMenu

        menu.addItem(appearanceMenuItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit DodoShot", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem.menu = nil // We'll show it manually on right-click
    }

    @objc private func handleStatusItemClick() {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            // Show context menu on right-click
            showContextMenu()
        } else {
            // Show popover on left-click
            togglePopover()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        // Appearance submenu
        let appearanceMenu = NSMenu()
        let darkItem = NSMenuItem(title: "Dark", action: #selector(setDarkMode), keyEquivalent: "")
        let lightItem = NSMenuItem(title: "Light", action: #selector(setLightMode), keyEquivalent: "")
        let systemItem = NSMenuItem(title: "System", action: #selector(setSystemMode), keyEquivalent: "")

        darkItem.target = self
        lightItem.target = self
        systemItem.target = self

        // Mark current mode
        updateAppearanceMenuItems(darkItem: darkItem, lightItem: lightItem, systemItem: systemItem)

        appearanceMenu.addItem(darkItem)
        appearanceMenu.addItem(lightItem)
        appearanceMenu.addItem(systemItem)

        let appearanceMenuItem = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        appearanceMenuItem.submenu = appearanceMenu

        menu.addItem(appearanceMenuItem)
        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit DodoShot", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func updateAppearanceMenuItems(darkItem: NSMenuItem, lightItem: NSMenuItem, systemItem: NSMenuItem) {
        let currentMode = SettingsManager.shared.settings.appearanceMode
        darkItem.state = currentMode == .dark ? .on : .off
        lightItem.state = currentMode == .light ? .on : .off
        systemItem.state = currentMode == .system ? .on : .off
    }

    @objc private func setDarkMode() {
        SettingsManager.shared.settings.appearanceMode = .dark
    }

    @objc private func setLightMode() {
        SettingsManager.shared.settings.appearanceMode = .light
    }

    @objc private func setSystemMode() {
        SettingsManager.shared.settings.appearanceMode = .system
    }

    @objc private func openSettings() {
        openSettingsWindow()
    }

    /// Public method to open settings window from anywhere
    @objc func openSettingsWindow() {
        // Close popover if open
        if popover.isShown {
            popover.performClose(nil)
        }

        // Create or show settings window
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "DodoShot Settings"
            window.center()
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView())
            // Ensure the window joins the active Space and floats above other
            // apps. As an accessory (LSUIElement) app we can't reliably pull a
            // plain window to the front, so it would otherwise open hidden
            // behind everything — appearing as "nothing happens" on click.
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.center()
            settingsWindow = window
        }

        // An accessory app cannot reliably foreground a window with
        // makeKeyAndOrderFront alone. Briefly become a regular app so we own
        // the foreground, bring the window forward, then restore the policy.
        let restorePolicy = NSApp.activationPolicy()
        if restorePolicy != .regular {
            NSApp.setActivationPolicy(.regular)
        }

        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()

        // Restore the original activation policy once the window is up so the
        // app stays a menu-bar item (no Dock icon) when not configured to show one.
        if restorePolicy != .regular {
            DispatchQueue.main.async { [weak self] in
                guard self?.settingsWindow != nil else { return }
                NSApp.setActivationPolicy(restorePolicy)
            }
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc func closePopover() {
        popover.performClose(nil)
    }
}

// MARK: - Appearance Extension for Views
extension View {
    func applyAppTheme() -> some View {
        self.preferredColorScheme(SettingsManager.shared.settings.appearanceMode.colorScheme)
    }
}

extension AppearanceMode {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
