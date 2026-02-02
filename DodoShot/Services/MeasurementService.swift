import Foundation
import AppKit
import SwiftUI

/// Service for screen measurements - pixel ruler and color picker
class MeasurementService: ObservableObject {
    static let shared = MeasurementService()

    @Published var isRulerActive = false
    @Published var isColorPickerActive = false
    @Published var pickedColor: NSColor?
    @Published var lastMeasurement: Measurement?

    private var measurementWindow: NSWindow?
    private var colorInfoWindow: NSWindow?

    struct Measurement {
        let start: CGPoint
        let end: CGPoint

        var width: CGFloat { abs(end.x - start.x) }
        var height: CGFloat { abs(end.y - start.y) }
        var diagonal: CGFloat { sqrt(width * width + height * height) }
    }

    private init() {}

    // MARK: - Pixel Ruler

    /// Start the pixel ruler mode
    func startPixelRuler() {
        guard !isRulerActive else { return }
        isRulerActive = true

        guard let screen = NSScreen.main else {
            isRulerActive = false
            return
        }

        let window = createMeasurementWindow(for: screen)
        let contentView = PixelRulerView(
            onMeasure: { [weak self] measurement in
                self?.lastMeasurement = measurement
            },
            onComplete: { [weak self] in
                self?.stopPixelRuler()
            },
            onCancel: { [weak self] in
                self?.stopPixelRuler()
            }
        )

        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        measurementWindow = window
    }

    /// Stop the pixel ruler mode
    func stopPixelRuler() {
        measurementWindow?.close()
        measurementWindow = nil
        isRulerActive = false
    }

    // MARK: - Color Picker

    /// Start the color picker mode
    func startColorPicker() {
        guard !isColorPickerActive else { return }
        isColorPickerActive = true

        guard let screen = NSScreen.main else {
            isColorPickerActive = false
            return
        }

        let window = createMeasurementWindow(for: screen)

        // Order front first to get a valid window number
        window.orderFront(nil)
        let windowNumber = CGWindowID(window.windowNumber)

        let contentView = ColorPickerOverlayView(
            excludeWindowNumber: windowNumber,
            onPick: { [weak self] color in
                self?.pickedColor = color
                self?.showColorInfo(color)
            },
            onCancel: { [weak self] in
                self?.stopColorPicker()
            }
        )

        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        measurementWindow = window
    }

    /// Stop the color picker mode
    func stopColorPicker() {
        measurementWindow?.close()
        measurementWindow = nil
        isColorPickerActive = false
    }

    /// Copy color to clipboard
    func copyColorToClipboard(_ color: NSColor, format: ColorFormat) {
        let colorString = formatColor(color, format: format)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(colorString, forType: .string)
    }

    // MARK: - Private Methods

    private func createMeasurementWindow(for screen: NSScreen) -> NSWindow {
        let window = MeasurementWindow(
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

        return window
    }

    private func showColorInfo(_ color: NSColor) {
        // Close the picker FIRST (before creating new window)
        // This ensures window management is clean
        stopColorPicker()

        // Close any existing color info window
        colorInfoWindow?.close()
        colorInfoWindow = nil

        // Create a floating window showing the picked color
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 160),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isReleasedWhenClosed = false

        let colorInfoView = ColorInfoView(
            color: color,
            onDismiss: { [weak self] in
                self?.colorInfoWindow?.close()
                self?.colorInfoWindow = nil
            },
            onCopy: { [weak self] format in
                self?.copyColorToClipboard(color, format: format)
            }
        )

        window.contentView = NSHostingView(rootView: colorInfoView)

        // Store reference BEFORE showing (prevents deallocation)
        colorInfoWindow = window

        // Position near cursor
        if let mouseLocation = NSEvent.mouseLocation as CGPoint? {
            window.setFrameOrigin(NSPoint(
                x: mouseLocation.x + 20,
                y: mouseLocation.y - 160
            ))
        }

        window.makeKeyAndOrderFront(nil)
    }

    private func formatColor(_ color: NSColor, format: ColorFormat) -> String {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)
        let a = rgb.alphaComponent

        switch format {
        case .hex:
            return String(format: "#%02X%02X%02X", r, g, b)
        case .rgb:
            return "rgb(\(r), \(g), \(b))"
        case .rgba:
            return String(format: "rgba(%d, %d, %d, %.2f)", r, g, b, a)
        case .hsl:
            let (h, s, l) = rgbToHSL(r: r, g: g, b: b)
            return String(format: "hsl(%d, %d%%, %d%%)", Int(h), Int(s * 100), Int(l * 100))
        case .swiftUI:
            return String(format: "Color(red: %.3f, green: %.3f, blue: %.3f)", rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
        case .nsColor:
            return String(format: "NSColor(red: %.3f, green: %.3f, blue: %.3f, alpha: %.3f)", rgb.redComponent, rgb.greenComponent, rgb.blueComponent, a)
        }
    }

    private func rgbToHSL(r: Int, g: Int, b: Int) -> (CGFloat, CGFloat, CGFloat) {
        let rf = CGFloat(r) / 255.0
        let gf = CGFloat(g) / 255.0
        let bf = CGFloat(b) / 255.0

        let maxVal = max(rf, gf, bf)
        let minVal = min(rf, gf, bf)
        let l = (maxVal + minVal) / 2.0

        if maxVal == minVal {
            return (0, 0, l)
        }

        let d = maxVal - minVal
        let s = l > 0.5 ? d / (2.0 - maxVal - minVal) : d / (maxVal + minVal)

        var h: CGFloat
        if maxVal == rf {
            h = (gf - bf) / d + (gf < bf ? 6.0 : 0.0)
        } else if maxVal == gf {
            h = (bf - rf) / d + 2.0
        } else {
            h = (rf - gf) / d + 4.0
        }
        h *= 60.0

        return (h, s, l)
    }
}

// MARK: - Color Format Enum
enum ColorFormat: String, CaseIterable {
    case hex = "HEX"
    case rgb = "RGB"
    case rgba = "RGBA"
    case hsl = "HSL"
    case swiftUI = "SwiftUI"
    case nsColor = "NSColor"
}

// MARK: - Measurement Window Class
class MeasurementWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        // Don't propagate cancel/ESC to prevent app termination
        // The SwiftUI view handles ESC via .onExitCommand
    }
}

// MARK: - Pixel Ruler View
struct PixelRulerView: View {
    let onMeasure: (MeasurementService.Measurement) -> Void
    let onComplete: () -> Void
    let onCancel: () -> Void

    @State private var startPoint: CGPoint?
    @State private var currentPoint: CGPoint?
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Semi-transparent overlay
                Color.black.opacity(0.3)

                // Instruction badge
                VStack {
                    InstructionBadge(text: "Click and drag to measure • Press ESC to cancel")
                        .padding(.top, 60)
                    Spacer()
                }

                // Measurement lines and info
                if let start = startPoint, let current = currentPoint {
                    MeasurementOverlay(start: start, end: current)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            startPoint = value.startLocation
                        }
                        currentPoint = value.location
                    }
                    .onEnded { value in
                        if let start = startPoint {
                            let measurement = MeasurementService.Measurement(
                                start: start,
                                end: value.location
                            )
                            onMeasure(measurement)
                        }
                        isDragging = false
                        onComplete()
                    }
            )
            .onExitCommand {
                onCancel()
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Measurement Overlay
struct MeasurementOverlay: View {
    let start: CGPoint
    let end: CGPoint

    var width: CGFloat { abs(end.x - start.x) }
    var height: CGFloat { abs(end.y - start.y) }
    var diagonal: CGFloat { sqrt(width * width + height * height) }

    var body: some View {
        ZStack {
            // Selection rectangle
            Path { path in
                path.move(to: start)
                path.addLine(to: CGPoint(x: end.x, y: start.y))
                path.addLine(to: end)
                path.addLine(to: CGPoint(x: start.x, y: end.y))
                path.closeSubpath()
            }
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
            .foregroundColor(.white)

            // Diagonal line
            Path { path in
                path.move(to: start)
                path.addLine(to: end)
            }
            .stroke(Color.orange, lineWidth: 2)

            // Measurement info badge
            measurementBadge
                .position(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 - 30)

            // Width indicator
            if width > 50 {
                Text("\(Int(width))px")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(4)
                    .position(x: (start.x + end.x) / 2, y: start.y - 15)
            }

            // Height indicator
            if height > 50 {
                Text("\(Int(height))px")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(4)
                    .position(x: end.x + 30, y: (start.y + end.y) / 2)
            }

            // Corner markers
            ForEach([start, CGPoint(x: end.x, y: start.y), end, CGPoint(x: start.x, y: end.y)], id: \.x) { point in
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
                    .position(point)
            }
        }
    }

    private var measurementBadge: some View {
        VStack(spacing: 4) {
            Text("\(Int(diagonal))px")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.orange)

            HStack(spacing: 8) {
                Text("W: \(Int(width))")
                Text("H: \(Int(height))")
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.5), lineWidth: 1)
                )
        )
    }
}

// MARK: - Color Picker Overlay View
struct ColorPickerOverlayView: View {
    let excludeWindowNumber: CGWindowID
    let onPick: (NSColor) -> Void
    let onCancel: () -> Void

    @State private var currentColor: NSColor = .white
    @State private var cursorPosition: CGPoint = .zero
    @State private var magnifiedImage: NSImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Fully transparent overlay - we just need to capture mouse events
                Color.clear

                // Instruction badge
                VStack {
                    InstructionBadge(text: "Click to pick color • Press ESC to cancel")
                        .padding(.top, 60)
                    Spacer()
                }

                // Magnifier and color preview
                ColorMagnifier(color: currentColor, position: cursorPosition)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    cursorPosition = location
                    updateColorAtPosition(location)
                case .ended:
                    break
                }
            }
            .onTapGesture { location in
                updateColorAtPosition(location)
                onPick(currentColor)
            }
            .onExitCommand {
                onCancel()
            }
        }
        .ignoresSafeArea()
    }

    private func updateColorAtPosition(_ position: CGPoint) {
        // Get color at screen position
        guard let screen = NSScreen.main else { return }

        // Convert to screen coordinates (flip Y axis for Core Graphics)
        let screenPoint = CGPoint(
            x: position.x + screen.frame.origin.x,
            y: screen.frame.height - position.y + screen.frame.origin.y
        )

        // Capture a 1x1 pixel at the position, excluding our overlay window
        // Use .optionOnScreenBelowWindow with our window number to get content beneath
        if let cgImage = CGWindowListCreateImage(
            CGRect(x: screenPoint.x, y: screenPoint.y, width: 1, height: 1),
            .optionOnScreenBelowWindow,
            excludeWindowNumber,
            []
        ) {
            if let dataProvider = cgImage.dataProvider,
               let data = dataProvider.data,
               let ptr = CFDataGetBytePtr(data) {
                let r = CGFloat(ptr[0]) / 255.0
                let g = CGFloat(ptr[1]) / 255.0
                let b = CGFloat(ptr[2]) / 255.0
                currentColor = NSColor(red: r, green: g, blue: b, alpha: 1.0)
            }
        }
    }
}

// MARK: - Color Magnifier
struct ColorMagnifier: View {
    let color: NSColor
    let position: CGPoint

    var body: some View {
        VStack(spacing: 4) {
            // Color preview
            Circle()
                .fill(Color(nsColor: color))
                .frame(width: 60, height: 60)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 3)
                )
                .shadow(color: .black.opacity(0.3), radius: 5)

            // Color hex value
            Text(colorHex)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.8))
                )
        }
        .position(x: position.x + 50, y: position.y - 50)
    }

    private var colorHex: String {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - Color Info View
struct ColorInfoView: View {
    let color: NSColor
    let onDismiss: () -> Void
    let onCopy: (ColorFormat) -> Void

    @State private var copiedFormat: ColorFormat?

    var body: some View {
        VStack(spacing: 12) {
            // Header with close button
            HStack {
                Text("Picked Color")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Color preview
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: color))
                .frame(height: 50)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )

            // Color formats
            VStack(spacing: 6) {
                ForEach([ColorFormat.hex, .rgb, .swiftUI], id: \.self) { format in
                    ColorFormatRow(
                        format: format,
                        value: formatColor(format),
                        isCopied: copiedFormat == format,
                        onCopy: {
                            onCopy(format)
                            copiedFormat = format
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                copiedFormat = nil
                            }
                        }
                    )
                }
            }
        }
        .padding(12)
        .frame(width: 200)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.3), radius: 10)
        )
    }

    private func formatColor(_ format: ColorFormat) -> String {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)

        switch format {
        case .hex:
            return String(format: "#%02X%02X%02X", r, g, b)
        case .rgb:
            return "rgb(\(r), \(g), \(b))"
        case .swiftUI:
            return String(format: "Color(red: %.2f, green: %.2f, blue: %.2f)", rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
        default:
            return ""
        }
    }
}

// MARK: - Color Format Row
struct ColorFormatRow: View {
    let format: ColorFormat
    let value: String
    let isCopied: Bool
    let onCopy: () -> Void

    var body: some View {
        HStack {
            Text(format.rawValue)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .leading)

            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            Button(action: onCopy) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.clipboard")
                    .font(.system(size: 10))
                    .foregroundColor(isCopied ? .green : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.primary.opacity(0.05))
        )
    }
}
