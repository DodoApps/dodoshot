import Foundation

// MARK: - Localization Helper
extension String {
    /// Returns a localized version of the string
    var localized: String {
        NSLocalizedString(self, comment: "")
    }

    /// Returns a localized version of the string with format arguments
    func localized(_ args: CVarArg...) -> String {
        String(format: NSLocalizedString(self, comment: ""), arguments: args)
    }
}

// MARK: - Localization Keys
enum L10n {
    // MARK: - Menu Bar
    enum Menu {
        static let capture = "menu.capture".localized
        static let area = "menu.area".localized
        static let window = "menu.window".localized
        static let fullscreen = "menu.fullscreen".localized
        static let scrolling = "menu.scrolling".localized
        static let scrollingNew = "menu.scrolling.new".localized
        static let tools = "menu.tools".localized
        static let ruler = "menu.ruler".localized
        static let colorPicker = "menu.colorPicker".localized
        static let ocr = "menu.ocr".localized
        static let recentCaptures = "menu.recentCaptures".localized
        static let noRecentCaptures = "menu.noRecentCaptures".localized
        static let showAll = "menu.showAll".localized
        static let settings = "menu.settings".localized
        static let quit = "menu.quit".localized
        static let history = "menu.history".localized
    }

    // MARK: - Capture Types
    enum Capture {
        static let area = "capture.area".localized
        static let window = "capture.window".localized
        static let fullscreen = "capture.fullscreen".localized
        static let scrolling = "capture.scrolling".localized
    }

    // MARK: - Quick Overlay
    enum Overlay {
        static let copy = "overlay.copy".localized
        static let save = "overlay.save".localized
        static let annotate = "overlay.annotate".localized
        static let pin = "overlay.pin".localized
        static let close = "overlay.close".localized
        static let justNow = "overlay.justNow".localized
    }

    // MARK: - Annotation Editor
    enum Annotation {
        static let title = "annotation.title".localized
        static let arrow = "annotation.arrow".localized
        static let rectangle = "annotation.rectangle".localized
        static let ellipse = "annotation.ellipse".localized
        static let line = "annotation.line".localized
        static let text = "annotation.text".localized
        static let blur = "annotation.blur".localized
        static let highlight = "annotation.highlight".localized
        static let freehand = "annotation.freehand".localized
        static let undo = "annotation.undo".localized
        static let clear = "annotation.clear".localized
        static let cancel = "annotation.cancel".localized
        static let addText = "annotation.addText".localized
        static let addTextTitle = "annotation.addTextTitle".localized
        static let textPlaceholder = "annotation.textPlaceholder".localized
        static func annotations(_ count: Int) -> String {
            count == 1 ? "annotation.annotations".localized(count) : "annotation.annotationsPlural".localized(count)
        }
    }

    // MARK: - Settings
    enum Settings {
        static let title = "settings.title".localized
        static let general = "settings.general".localized
        static let hotkeys = "settings.hotkeys".localized
        static let ai = "settings.ai".localized
        static let about = "settings.about".localized

        // General
        static let appearance = "settings.appearance".localized
        static let appearanceDescription = "settings.appearance.description".localized
        static let appearanceSystem = "settings.appearance.system".localized
        static let appearanceLight = "settings.appearance.light".localized
        static let appearanceDark = "settings.appearance.dark".localized
        static let capture = "settings.capture".localized
        static let autoCopy = "settings.autoCopy".localized
        static let autoCopyDescription = "settings.autoCopy.description".localized
        static let showOverlay = "settings.showOverlay".localized
        static let showOverlayDescription = "settings.showOverlay.description".localized
        static let hideDesktopIcons = "settings.hideDesktopIcons".localized
        static let hideDesktopIconsDescription = "settings.hideDesktopIcons.description".localized
        static let closeWindowAfterCopy = "settings.closeWindowAfterCopy".localized
        static let closeWindowAfterCopyDescription = "settings.closeWindowAfterCopy.description".localized
        static let storage = "settings.storage".localized
        static let saveLocation = "settings.saveLocation".localized
        static let choose = "settings.choose".localized

        // Hotkeys
        static let shortcuts = "settings.shortcuts".localized
        static let areaCapture = "settings.areaCapture".localized
        static let windowCapture = "settings.windowCapture".localized
        static let fullscreenCapture = "settings.fullscreenCapture".localized
        static let recording = "settings.recording".localized
        static let permissions = "settings.permissions".localized
        static let permissionsDescription = "settings.permissions.description".localized
        static let openSettings = "settings.openSettings".localized

        // AI
        static let llmConfig = "settings.llmConfig".localized
        static let provider = "settings.provider".localized
        static let apiKey = "settings.apiKey".localized
        static let apiKeyPlaceholder = "settings.apiKeyPlaceholder".localized
        static let apiKeySecure = "settings.apiKeySecure".localized
        static let aiFeatures = "settings.aiFeatures".localized
        static let smartDescriptions = "settings.smartDescriptions".localized
        static let smartDescriptionsDescription = "settings.smartDescriptions.description".localized
        static let ocrExtraction = "settings.ocrExtraction".localized
        static let ocrExtractionDescription = "settings.ocrExtraction.description".localized
        static let contentSuggestions = "settings.contentSuggestions".localized
        static let contentSuggestionsDescription = "settings.contentSuggestions.description".localized

        // About
        static func version(_ v: String) -> String { "settings.version".localized(v) }
        static let tagline = "settings.tagline".localized
        static let openSource = "settings.openSource".localized
        static let viewOnGitHub = "settings.viewOnGitHub".localized
        static let madeWith = "settings.madeWith".localized
    }

    // MARK: - Capture History
    enum History {
        static let title = "history.title".localized
        static let all = "history.all".localized
        static let areas = "history.areas".localized
        static let windows = "history.windows".localized
        static let fullscreens = "history.fullscreens".localized
        static let newest = "history.newest".localized
        static let oldest = "history.oldest".localized
        static let noCaptures = "history.noCaptures".localized
        static let noCapturesDescription = "history.noCaptures.description".localized
        static let startCapturing = "history.startCapturing".localized
        static let delete = "history.delete".localized
        static let showInFinder = "history.showInFinder".localized
    }

    // MARK: - Permissions
    enum Permissions {
        static let title = "permissions.title".localized
        static let description = "permissions.description".localized
        static let screenRecording = "permissions.screenRecording".localized
        static let screenRecordingDescription = "permissions.screenRecording.description".localized
        static let accessibility = "permissions.accessibility".localized
        static let accessibilityDescription = "permissions.accessibility.description".localized
        static let granted = "permissions.granted".localized
        static let continueButton = "permissions.continue".localized
        static let showInFinder = "permissions.showInFinder".localized
        static let restart = "permissions.restart".localized
        static let later = "permissions.later".localized
        static let instructions = "permissions.instructions".localized
        static let step1 = "permissions.step1".localized
        static let step2 = "permissions.step2".localized
        static let step3 = "permissions.step3".localized
    }

    // MARK: - Window Selection
    enum WindowSelection {
        static let title = "windowSelection.title".localized
        static let scrollingTitle = "windowSelection.scrollingTitle".localized
        static let cancel = "windowSelection.cancel".localized
        static let escToCancel = "windowSelection.escToCancel".localized
    }

    // MARK: - Context Menu
    enum ContextMenu {
        static let appearance = "contextMenu.appearance".localized
        static let copy = "contextMenu.copy".localized
        static let save = "contextMenu.save".localized
        static let annotate = "contextMenu.annotate".localized
        static let pin = "contextMenu.pin".localized
        static let delete = "contextMenu.delete".localized
    }
}
