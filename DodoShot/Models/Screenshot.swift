import Foundation
import AppKit

/// Represents a captured screenshot with metadata
struct Screenshot: Identifiable {
    let id: UUID
    let image: NSImage
    let capturedAt: Date
    let captureType: CaptureType
    var annotations: [Annotation]
    var extractedText: String?
    var aiDescription: String?

    init(
        id: UUID = UUID(),
        image: NSImage,
        capturedAt: Date = Date(),
        captureType: CaptureType,
        annotations: [Annotation] = [],
        extractedText: String? = nil,
        aiDescription: String? = nil
    ) {
        self.id = id
        self.image = image
        self.capturedAt = capturedAt
        self.captureType = captureType
        self.annotations = annotations
        self.extractedText = extractedText
        self.aiDescription = aiDescription
    }
}

/// Type of screen capture
enum CaptureType: String, Codable, CaseIterable {
    case area = "Area"
    case window = "Window"
    case fullscreen = "Fullscreen"

    var icon: String {
        switch self {
        case .area: return "rectangle.dashed"
        case .window: return "macwindow"
        case .fullscreen: return "rectangle.inset.filled"
        }
    }

    var shortcut: String {
        switch self {
        case .area: return "⌘⇧4"
        case .window: return "⌘⇧5"
        case .fullscreen: return "⌘⇧3"
        }
    }
}

/// Callout arrow direction
enum CalloutArrowDirection: String, Codable, CaseIterable {
    case bottomLeft = "Bottom Left"
    case bottomRight = "Bottom Right"
    case topLeft = "Top Left"
    case topRight = "Top Right"
}

/// Annotation on a screenshot
struct Annotation: Identifiable, Codable {
    let id: UUID
    var type: AnnotationType
    var startPoint: CGPoint
    var endPoint: CGPoint
    var colorHex: String
    var strokeWidth: CGFloat
    var text: String?
    var points: [CGPoint]  // For freehand drawing
    var fontSize: CGFloat
    var fontWeight: String
    var fontName: String
    var calloutArrowDirection: CalloutArrowDirection  // For callout annotations
    var stepNumber: Int?  // For step counter annotations
    var stepCounterFormat: StepCounterFormat  // Format for step counter
    var redactionStyle: RedactionStyle  // For blur/pixelate redaction
    var redactionIntensity: CGFloat  // 0.0 to 1.0 for blur/pixelate intensity
    var zIndex: Int  // For layer ordering (higher = on top)

    // Computed property for NSColor (not encoded)
    var color: NSColor {
        get { NSColor(hex: colorHex) ?? .systemRed }
        set { colorHex = newValue.hexString }
    }

    init(
        id: UUID = UUID(),
        type: AnnotationType,
        startPoint: CGPoint,
        endPoint: CGPoint = .zero,
        color: NSColor = .systemRed,
        strokeWidth: CGFloat = 3.0,
        text: String? = nil,
        points: [CGPoint] = [],
        fontSize: CGFloat = 16,
        fontWeight: String = "medium",
        fontName: String = "System",
        calloutArrowDirection: CalloutArrowDirection = .bottomLeft,
        stepNumber: Int? = nil,
        stepCounterFormat: StepCounterFormat = .numeric,
        redactionStyle: RedactionStyle = .blur,
        redactionIntensity: CGFloat = 0.7,
        zIndex: Int = 0
    ) {
        self.id = id
        self.type = type
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.colorHex = color.hexString
        self.strokeWidth = strokeWidth
        self.text = text
        self.points = points
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.fontName = fontName
        self.calloutArrowDirection = calloutArrowDirection
        self.stepNumber = stepNumber
        self.stepCounterFormat = stepCounterFormat
        self.redactionStyle = redactionStyle
        self.redactionIntensity = redactionIntensity
        self.zIndex = zIndex
    }

    enum CodingKeys: String, CodingKey {
        case id, type, startPoint, endPoint, colorHex, strokeWidth, text, points, fontSize, fontWeight, fontName, calloutArrowDirection, stepNumber, stepCounterFormat, redactionStyle, redactionIntensity, zIndex
    }
}

/// Step counter format for numbered annotations
enum StepCounterFormat: String, Codable, CaseIterable {
    case numeric = "1, 2, 3"
    case alphabeticUpper = "A, B, C"
    case alphabeticLower = "a, b, c"
    case romanUpper = "I, II, III"
    case romanLower = "i, ii, iii"

    func format(_ number: Int) -> String {
        switch self {
        case .numeric:
            return "\(number)"
        case .alphabeticUpper:
            return number <= 26 ? String(Character(UnicodeScalar(64 + number)!)) : "\(number)"
        case .alphabeticLower:
            return number <= 26 ? String(Character(UnicodeScalar(96 + number)!)) : "\(number)"
        case .romanUpper:
            return toRoman(number).uppercased()
        case .romanLower:
            return toRoman(number).lowercased()
        }
    }

    private func toRoman(_ number: Int) -> String {
        let romanValues: [(Int, String)] = [
            (1000, "M"), (900, "CM"), (500, "D"), (400, "CD"),
            (100, "C"), (90, "XC"), (50, "L"), (40, "XL"),
            (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")
        ]
        var result = ""
        var remaining = number
        for (value, numeral) in romanValues {
            while remaining >= value {
                result += numeral
                remaining -= value
            }
        }
        return result
    }
}

/// Redaction style for privacy tools
enum RedactionStyle: String, Codable, CaseIterable {
    case blur = "Blur"
    case pixelate = "Pixelate"
    case solidBlack = "Black"
    case solidWhite = "White"

    var icon: String {
        switch self {
        case .blur: return "drop.halffull"
        case .pixelate: return "square.grid.3x3"
        case .solidBlack: return "rectangle.fill"
        case .solidWhite: return "rectangle"
        }
    }
}

/// Types of annotations available
enum AnnotationType: String, Codable, CaseIterable {
    case select = "Select"
    case arrow = "Arrow"
    case rectangle = "Rectangle"
    case ellipse = "Ellipse"
    case line = "Line"
    case text = "Text"
    case callout = "Callout"
    case blur = "Blur"
    case pixelate = "Pixelate"
    case highlight = "Highlight"
    case freehand = "Freehand"
    case erase = "Erase"
    case stepCounter = "Step"

    var icon: String {
        switch self {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .line: return "line.diagonal"
        case .text: return "textformat"
        case .callout: return "text.bubble"
        case .blur: return "drop.halffull"
        case .pixelate: return "square.grid.3x3"
        case .highlight: return "highlighter"
        case .freehand: return "pencil.tip"
        case .erase: return "eraser"
        case .stepCounter: return "number.circle"
        }
    }
}

/// App appearance mode
enum AppearanceMode: String, Codable, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon.fill"
        }
    }
}

/// Image format for saving
enum ImageFormat: String, Codable, CaseIterable {
    case png = "PNG"
    case jpg = "JPG"
    case webp = "WebP"
    case pdf = "PDF"
    case auto = "Auto"

    var icon: String {
        switch self {
        case .png: return "doc.richtext"
        case .jpg: return "photo"
        case .webp: return "doc.zipper"
        case .pdf: return "doc.fill"
        case .auto: return "wand.and.stars"
        }
    }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpg: return "jpg"
        case .webp: return "webp"
        case .pdf: return "pdf"
        case .auto: return "png" // Default for auto
        }
    }
}

/// Text annotation settings
struct TextAnnotationSettings: Codable, Equatable {
    var fontName: String
    var fontSize: CGFloat
    var fontWeight: String
    var colorHex: String

    static var `default`: TextAnnotationSettings {
        TextAnnotationSettings(
            fontName: "System",
            fontSize: 16,
            fontWeight: "medium",
            colorHex: "#FF0000"
        )
    }

    var nsFont: NSFont {
        let weight: NSFont.Weight
        switch fontWeight {
        case "ultralight": weight = .ultraLight
        case "thin": weight = .thin
        case "light": weight = .light
        case "regular": weight = .regular
        case "medium": weight = .medium
        case "semibold": weight = .semibold
        case "bold": weight = .bold
        case "heavy": weight = .heavy
        case "black": weight = .black
        default: weight = .medium
        }

        if fontName == "System" {
            return NSFont.systemFont(ofSize: fontSize, weight: weight)
        } else {
            return NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize, weight: weight)
        }
    }
}

/// App settings model
struct AppSettings: Codable {
    var llmApiKey: String
    var llmProvider: LLMProvider
    var saveLocation: String
    var autoCopyToClipboard: Bool
    var showQuickOverlay: Bool
    var quickOverlayAutoDismiss: Bool  // Auto-dismiss overlay after timeout
    var quickOverlayTimeout: Double  // Seconds before auto-dismiss (0 = never)
    var hideDesktopIcons: Bool
    var hotkeys: HotkeySettings
    var appearanceMode: AppearanceMode
    var launchAtStartup: Bool
    var imageFormat: ImageFormat
    var jpgQuality: Double
    var webpQuality: Double
    var defaultAnnotationColor: String
    var defaultStrokeWidth: Double
    var defaultAnnotationTool: String
    var textAnnotationSettings: TextAnnotationSettings
    var filenameTemplate: String
    var sequentialNumber: Int
    var autoSaveOnEditorClose: Bool
    var autoCopyOnEditorClose: Bool
    var maxVideoRecordingDuration: Int  // seconds (max 20)
    var defaultRedactionStyle: RedactionStyle
    var defaultRedactionIntensity: Double
    var defaultStepCounterFormat: StepCounterFormat

    static var `default`: AppSettings {
        let desktopPath = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.path ?? "~/Desktop"
        let screenshotsPath = (desktopPath as NSString).appendingPathComponent("Screenshots")

        return AppSettings(
            llmApiKey: "",
            llmProvider: .anthropic,
            saveLocation: screenshotsPath,
            autoCopyToClipboard: true,
            showQuickOverlay: true,
            quickOverlayAutoDismiss: true,
            quickOverlayTimeout: 5.0,
            hideDesktopIcons: false,
            hotkeys: .default,
            appearanceMode: .dark,
            launchAtStartup: false,
            imageFormat: .auto,
            jpgQuality: 0.8,
            webpQuality: 0.8,
            defaultAnnotationColor: "red",
            defaultStrokeWidth: 3.0,
            defaultAnnotationTool: "arrow",
            textAnnotationSettings: .default,
            filenameTemplate: "DodoShot_{date}_{time}",
            sequentialNumber: 1,
            autoSaveOnEditorClose: false,
            autoCopyOnEditorClose: true,
            maxVideoRecordingDuration: 20,
            defaultRedactionStyle: .blur,
            defaultRedactionIntensity: 0.7,
            defaultStepCounterFormat: .numeric
        )
    }

    /// Generate filename from template
    mutating func generateFilename(extension ext: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = dateFormatter.string(from: Date())

        dateFormatter.dateFormat = "HH-mm-ss"
        let time = dateFormatter.string(from: Date())

        let filename = filenameTemplate
            .replacingOccurrences(of: "{date}", with: date)
            .replacingOccurrences(of: "{time}", with: time)
            .replacingOccurrences(of: "{n}", with: String(format: "%04d", sequentialNumber))
            .replacingOccurrences(of: "{num}", with: String(sequentialNumber))

        // Increment sequential number
        sequentialNumber += 1

        return "\(filename).\(ext)"
    }
}

enum LLMProvider: String, Codable, CaseIterable {
    case anthropic = "Anthropic"
    case openai = "OpenAI"

    var baseURL: String {
        switch self {
        case .anthropic: return "https://api.anthropic.com/v1"
        case .openai: return "https://api.openai.com/v1"
        }
    }
}

struct HotkeySettings: Codable {
    var areaCapture: String
    var windowCapture: String
    var fullscreenCapture: String

    static var `default`: HotkeySettings {
        HotkeySettings(
            areaCapture: "⌘⇧4",
            windowCapture: "⌘⇧5",
            fullscreenCapture: "⌘⇧3"
        )
    }
}

// MARK: - NSColor Hex Extension
extension NSColor {
    var hexString: String {
        guard let rgbColor = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(rgbColor.redComponent * 255)
        let g = Int(rgbColor.greenComponent * 255)
        let b = Int(rgbColor.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        self.init(
            srgbRed: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}

// MARK: - DodoShot Project File Format (.dodo)
/// A file format that stores the screenshot image and annotations together
struct DodoShotProject: Codable {
    static let fileExtension = "dodo"
    static let utType = "com.dodoshot.project"

    let version: Int
    let createdAt: Date
    var modifiedAt: Date
    let captureType: CaptureType
    var annotations: [Annotation]
    let imageData: Data  // PNG data of the original image

    init(screenshot: Screenshot) throws {
        self.version = 1
        self.createdAt = screenshot.capturedAt
        self.modifiedAt = Date()
        self.captureType = screenshot.captureType
        self.annotations = screenshot.annotations

        // Convert image to PNG data
        guard let tiffData = screenshot.image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw DodoShotProjectError.imageConversionFailed
        }
        self.imageData = pngData
    }

    func toScreenshot() -> Screenshot? {
        guard let image = NSImage(data: imageData) else { return nil }
        return Screenshot(
            image: image,
            capturedAt: createdAt,
            captureType: captureType,
            annotations: annotations
        )
    }

    /// Save project to file
    func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(self)
        try data.write(to: url)
    }

    /// Load project from file
    static func load(from url: URL) throws -> DodoShotProject {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DodoShotProject.self, from: data)
    }
}

enum DodoShotProjectError: Error, LocalizedError {
    case imageConversionFailed
    case invalidFileFormat

    var errorDescription: String? {
        switch self {
        case .imageConversionFailed:
            return "Failed to convert image to PNG format"
        case .invalidFileFormat:
            return "Invalid DodoShot project file"
        }
    }
}
