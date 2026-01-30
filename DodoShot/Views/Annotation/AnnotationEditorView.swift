import SwiftUI
import AppKit

// MARK: - Annotation Editor Window Controller
class AnnotationEditorWindowController {
    static let shared = AnnotationEditorWindowController()

    private var window: NSWindow?
    private var onSaveCallback: ((Screenshot) -> Void)?

    private init() {}

    func showEditor(for screenshot: Screenshot, onSave: @escaping (Screenshot) -> Void) {
        // Close existing window if any
        window?.close()
        onSaveCallback = onSave

        let editorView = AnnotationEditorView(
            screenshot: screenshot,
            onSave: { [weak self] updatedScreenshot in
                self?.onSaveCallback?(updatedScreenshot)
                self?.closeEditor()
            },
            onCancel: { [weak self] in
                self?.closeEditor()
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "DodoShot - Edit screenshot"
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.backgroundColor = NSColor.windowBackgroundColor
        window.minSize = NSSize(width: 1300, height: 700)
        window.level = .normal  // Regular window level, not floating
        window.collectionBehavior = [.managed, .participatesInCycle]  // Show in cmd-tab
        window.center()

        window.contentView = NSHostingView(rootView: editorView)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    func closeEditor() {
        window?.close()
        window = nil
        onSaveCallback = nil
    }
}

struct AnnotationEditorView: View {
    @State var screenshot: Screenshot
    let onSave: (Screenshot) -> Void
    let onCancel: () -> Void

    @State private var selectedTool: AnnotationType = .arrow
    @State private var selectedColor: Color = .red
    @State private var strokeWidth: CGFloat = 3.0
    @State private var currentText: String = ""
    @State private var isAddingText = false
    @State private var textPosition: CGPoint = .zero
    @State private var isColorPickerHovered = false
    @State private var actualImageSize: CGSize = .zero
    @State private var annotations: [Annotation] = []
    @State private var currentAnnotation: Annotation?
    @State private var imageSize: CGSize = .zero
    @State private var zoom: CGFloat = 1.0
    @State private var selectedAnnotationId: UUID? = nil
    @State private var isPerformingOCR = false
    @State private var ocrResult: String? = nil
    @State private var showOCRResult = false

    // Color picker state
    @State private var hoveredColor: Color? = nil
    @State private var hoveredColorHex: String = ""

    // Backdrop state
    @State private var showBackdropPanel = false
    @State private var backdropEnabled = false
    @State private var backdropType: BackdropType = .solid
    @State private var selectedSolidColor: Color = .blue
    @State private var selectedGradient: GradientPreset = .oceanBlue
    @State private var gradientDirection: GradientDirection = .linear
    @State private var shadowEnabled = false
    @State private var shadowBlur: CGFloat = 20
    @State private var shadowOffset: CGFloat = 10
    @State private var shadowOpacity: CGFloat = 0.3
    @State private var innerRadius: CGFloat = 12
    @State private var outerRadius: CGFloat = 20

    private let colors: [Color] = [
        .red, .orange, .yellow, .green, .blue, .purple, .pink, .white, .black
    ]

    // Helper to select annotation at point
    fileprivate func selectAnnotationAt(_ point: CGPoint) {
        // Find annotation at point (reverse order to select topmost first)
        for annotation in annotations.reversed() {
            if annotationContainsPoint(annotation, point: point) {
                selectedAnnotationId = annotation.id
                return
            }
        }
        selectedAnnotationId = nil
    }

    private func annotationContainsPoint(_ annotation: Annotation, point: CGPoint) -> Bool {
        let tolerance: CGFloat = 10
        let start = annotation.startPoint
        let end = annotation.endPoint

        switch annotation.type {
        case .arrow, .line:
            // Check if point is near the line
            return pointNearLine(point: point, lineStart: start, lineEnd: end, tolerance: tolerance)
        case .rectangle, .blur, .pixelate, .highlight:
            let rect = CGRect(
                x: min(start.x, end.x) - tolerance,
                y: min(start.y, end.y) - tolerance,
                width: abs(end.x - start.x) + tolerance * 2,
                height: abs(end.y - start.y) + tolerance * 2
            )
            return rect.contains(point)
        case .ellipse:
            let rect = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            return rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case .text:
            let textRect = CGRect(x: start.x - tolerance, y: start.y - tolerance, width: 100 + tolerance * 2, height: 30 + tolerance * 2)
            return textRect.contains(point)
        case .stepCounter:
            // Step counter is a circle at startPoint
            let radius = annotation.fontSize + 10
            let distance = hypot(point.x - start.x, point.y - start.y)
            return distance < radius + tolerance
        case .freehand, .erase:
            for pathPoint in annotation.points {
                if abs(pathPoint.x - point.x) < tolerance && abs(pathPoint.y - point.y) < tolerance {
                    return true
                }
            }
            return false
        case .select:
            return false
        }
    }

    private func pointNearLine(point: CGPoint, lineStart: CGPoint, lineEnd: CGPoint, tolerance: CGFloat) -> Bool {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let lengthSquared = dx * dx + dy * dy

        if lengthSquared == 0 {
            return hypot(point.x - lineStart.x, point.y - lineStart.y) < tolerance
        }

        let t = max(0, min(1, ((point.x - lineStart.x) * dx + (point.y - lineStart.y) * dy) / lengthSquared))
        let nearestX = lineStart.x + t * dx
        let nearestY = lineStart.y + t * dy
        let distance = hypot(point.x - nearestX, point.y - nearestY)

        return distance < tolerance
    }

    private func deleteSelectedAnnotation() {
        if let selectedId = selectedAnnotationId {
            annotations.removeAll { $0.id == selectedId }
            selectedAnnotationId = nil
        }
    }

    private func updateSelectedAnnotationStrokeWidth(_ newWidth: CGFloat) {
        if let selectedId = selectedAnnotationId,
           let index = annotations.firstIndex(where: { $0.id == selectedId }) {
            annotations[index].strokeWidth = newWidth
        }
    }

    private func updateSelectedAnnotationColor(_ newColor: Color) {
        if let selectedId = selectedAnnotationId,
           let index = annotations.firstIndex(where: { $0.id == selectedId }) {
            annotations[index].color = NSColor(newColor)
        }
    }

    // MARK: - Layer Management (Z-Order)

    /// Bring selected annotation forward (one layer up)
    private func bringForward() {
        guard let selectedId = selectedAnnotationId,
              let index = annotations.firstIndex(where: { $0.id == selectedId }),
              index < annotations.count - 1 else { return }

        annotations.swapAt(index, index + 1)
        updateZIndices()
    }

    /// Send selected annotation backward (one layer down)
    private func sendBackward() {
        guard let selectedId = selectedAnnotationId,
              let index = annotations.firstIndex(where: { $0.id == selectedId }),
              index > 0 else { return }

        annotations.swapAt(index, index - 1)
        updateZIndices()
    }

    /// Bring selected annotation to front (top layer)
    private func bringToFront() {
        guard let selectedId = selectedAnnotationId,
              let index = annotations.firstIndex(where: { $0.id == selectedId }) else { return }

        let annotation = annotations.remove(at: index)
        annotations.append(annotation)
        updateZIndices()
    }

    /// Send selected annotation to back (bottom layer)
    private func sendToBack() {
        guard let selectedId = selectedAnnotationId,
              let index = annotations.firstIndex(where: { $0.id == selectedId }) else { return }

        let annotation = annotations.remove(at: index)
        annotations.insert(annotation, at: 0)
        updateZIndices()
    }

    /// Update z-index values based on array position
    private func updateZIndices() {
        for (index, _) in annotations.enumerated() {
            annotations[index].zIndex = index
        }
    }

    /// Get current step counter number (for auto-increment)
    private func getNextStepNumber() -> Int {
        let stepAnnotations = annotations.filter { $0.type == .stepCounter }
        return stepAnnotations.count + 1
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar
                .frame(height: 60)

            Divider()

            // Main content area with canvas and optional backdrop panel
            HStack(spacing: 0) {
                // Canvas area - fills remaining space
                ZStack {
                    // Background pattern
                    CanvasBackground()

                    GeometryReader { geometry in
                        ScrollView([.horizontal, .vertical], showsIndicators: true) {
                            ZStack {
                                // Backdrop (if enabled)
                                if backdropEnabled {
                                    backdropView
                                }

                                // Screenshot image with backdrop styling
                                screenshotImageView
                            }
                            .frame(
                                minWidth: geometry.size.width - 48,
                                minHeight: geometry.size.height - 48
                            )
                        }
                    }
                    .padding(24)

                    // OCR result notification
                    if showOCRResult, let result = ocrResult {
                        ocrResultOverlay(result: result)
                    }
                }
                .clipped()

                // Backdrop settings panel (right side)
                if showBackdropPanel {
                    Divider()
                    backdropSettingsPanel
                }
            }

            Divider()

            // Bottom action bar
            bottomBar
                .frame(height: 50)
        }
        .frame(minWidth: 1100, idealWidth: showBackdropPanel ? 1300 : 1100, minHeight: 700)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Screenshot Image View
    private var screenshotImageView: some View {
        Image(nsImage: screenshot.image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .scaleEffect(zoom)
            .background(
                GeometryReader { imageGeometry in
                    Color.clear
                        .onAppear {
                            imageSize = imageGeometry.size
                            actualImageSize = imageGeometry.size
                        }
                        .onChange(of: imageGeometry.size) { newSize in
                            imageSize = newSize
                            actualImageSize = newSize
                        }
                }
            )
            .overlay(
                AnnotationCanvasView(
                    annotations: $annotations,
                    currentAnnotation: $currentAnnotation,
                    selectedTool: selectedTool,
                    selectedColor: NSColor(selectedColor),
                    strokeWidth: strokeWidth,
                    isAddingText: $isAddingText,
                    textPosition: $textPosition,
                    currentText: $currentText,
                    selectedAnnotationId: $selectedAnnotationId,
                    onSelectAnnotation: { point in
                        selectAnnotationAt(point)
                    },
                    onDeleteSelected: {
                        deleteSelectedAnnotation()
                    },
                    onUndo: {
                        undo()
                    },
                    onColorPicked: { color, hex in
                        hoveredColor = color
                        hoveredColorHex = hex
                    },
                    onTextAdded: { text, position in
                        addTextAnnotationDirect(text: text, position: position)
                    }
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: backdropEnabled ? innerRadius : 8))
            .overlay(
                RoundedRectangle(cornerRadius: backdropEnabled ? innerRadius : 8)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .shadow(
                color: shadowEnabled ? .black.opacity(shadowOpacity) : .black.opacity(0.4),
                radius: shadowEnabled ? shadowBlur : 20,
                y: shadowEnabled ? shadowOffset : 5
            )
    }

    // MARK: - Backdrop View
    private var backdropView: some View {
        GeometryReader { geometry in
            let padding: CGFloat = 40
            let imageAspect = screenshot.image.size.width / screenshot.image.size.height
            let containerAspect = geometry.size.width / geometry.size.height

            let fittedSize: CGSize = {
                if imageAspect > containerAspect {
                    let width = geometry.size.width
                    let height = width / imageAspect
                    return CGSize(width: width, height: height)
                } else {
                    let height = geometry.size.height
                    let width = height * imageAspect
                    return CGSize(width: width, height: height)
                }
            }()

            let backdropWidth = fittedSize.width * zoom + padding * 2
            let backdropHeight = fittedSize.height * zoom + padding * 2

            Group {
                switch backdropType {
                case .solid:
                    RoundedRectangle(cornerRadius: outerRadius)
                        .fill(selectedSolidColor)
                case .gradient:
                    RoundedRectangle(cornerRadius: outerRadius)
                        .fill(selectedGradient.gradient(direction: gradientDirection))
                case .transparent:
                    // Transparent backdrop - show checkerboard pattern for preview
                    RoundedRectangle(cornerRadius: outerRadius)
                        .fill(Color.clear)
                        .background(
                            CheckerboardPattern()
                                .clipShape(RoundedRectangle(cornerRadius: outerRadius))
                        )
                }
            }
            .frame(width: backdropWidth, height: backdropHeight)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }

    private func addTextAnnotationDirect(text: String, position: CGPoint) {
        let annotation = Annotation(
            type: .text,
            startPoint: position,
            color: NSColor(selectedColor),
            text: text
        )
        annotations.append(annotation)
    }

    // MARK: - Backdrop Settings Panel
    private var backdropSettingsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Text("Backdrop")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Toggle("", isOn: $backdropEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                if backdropEnabled {
                    // Backdrop Type
                    HStack {
                        Text("Type")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("", selection: $backdropType) {
                            ForEach(BackdropType.allCases, id: \.self) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                    }

                    Divider()

                    // Colors (not shown for transparent)
                    if backdropType == .solid {
                        solidColorPicker
                    } else if backdropType == .gradient {
                        gradientPicker
                    }
                    // Transparent backdrop shows nothing here - it's just transparent

                    Divider()

                    // Shadow
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Shadow")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            Toggle("", isOn: $shadowEnabled)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }

                        if shadowEnabled {
                            VStack(spacing: 12) {
                                SliderRow(label: "Blur", value: $shadowBlur, range: 0...50)
                                SliderRow(label: "Offset", value: $shadowOffset, range: 0...30)
                                SliderRow(label: "Opacity", value: $shadowOpacity, range: 0...1, format: "%.0f%%", multiplier: 100)
                            }
                        }
                    }

                    Divider()

                    // Border Radius
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Border radius")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)

                        SliderRow(label: "Inner", value: $innerRadius, range: 0...50)
                        SliderRow(label: "Outer", value: $outerRadius, range: 0...50)
                    }
                }
            }
            .padding(16)
        }
        .frame(width: 280)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Solid Color Picker
    private var solidColorPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Solid colors")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(0..<SolidColorPalette.colors.count, id: \.self) { index in
                    let color = SolidColorPalette.colors[index]
                    Button(action: { selectedSolidColor = color }) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(color)
                            .frame(height: 36)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(selectedSolidColor == color ? Color.white : Color.primary.opacity(0.1), lineWidth: selectedSolidColor == color ? 2 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Gradient Picker
    private var gradientPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Direction toggle
            HStack {
                Text("Direction")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    ForEach(GradientDirection.allCases, id: \.self) { dir in
                        Button(action: { gradientDirection = dir }) {
                            Image(systemName: dir.icon)
                                .font(.system(size: 12))
                                .foregroundColor(gradientDirection == dir ? .white : .primary)
                                .frame(width: 28, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(gradientDirection == dir ? Color.purple : Color.primary.opacity(0.06))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text("Gradients")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(GradientPreset.allCases, id: \.self) { preset in
                    Button(action: { selectedGradient = preset }) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(preset.gradient(direction: gradientDirection))
                            .frame(height: 36)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(selectedGradient == preset ? Color.white : Color.clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(preset.rawValue)
                }
            }
        }
    }

    // MARK: - OCR Result Overlay
    private func ocrResultOverlay(result: String) -> some View {
        VStack {
            Spacer()

            HStack(spacing: 12) {
                if result.hasPrefix("Error:") {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(result.hasPrefix("Error:") ? "OCR failed" : "Text copied to clipboard")
                        .font(.system(size: 13, weight: .semibold))

                    if !result.hasPrefix("Error:") {
                        Text("\(result.prefix(100))\(result.count > 100 ? "..." : "")")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    } else {
                        Text(result.replacingOccurrences(of: "Error: ", with: ""))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button(action: { showOCRResult = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
            .frame(maxWidth: 400)
            .padding(.bottom, 80)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.3), value: showOCRResult)
    }

    // MARK: - Toolbar
    private var toolbar: some View {
        HStack(spacing: 16) {
            // Tool selection
            HStack(spacing: 2) {
                ForEach(AnnotationType.allCases, id: \.self) { tool in
                    AnnotationToolButton(
                        tool: tool,
                        isSelected: selectedTool == tool,
                        action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedTool = tool
                            }
                        }
                    )
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(0.04))
            )

            // Separator
            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(width: 1, height: 28)

            // Color picker
            HStack(spacing: 4) {
                ForEach(colors, id: \.self) { color in
                    AnnotationColorButton(
                        color: color,
                        isSelected: selectedColor == color,
                        action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedColor = color
                                // Also update selected annotation if any
                                updateSelectedAnnotationColor(color)
                            }
                        }
                    )
                }
            }

            // Separator
            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(width: 1, height: 28)

            // Stroke width
            HStack(spacing: 10) {
                Image(systemName: "lineweight")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)

                HStack(spacing: 6) {
                    ForEach([2, 4, 6, 8], id: \.self) { width in
                        StrokeWidthButton(
                            width: CGFloat(width),
                            isSelected: strokeWidth == CGFloat(width),
                            color: selectedColor
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                strokeWidth = CGFloat(width)
                                // Also update selected annotation if any
                                updateSelectedAnnotationStrokeWidth(CGFloat(width))
                            }
                        }
                    }
                }
            }

            Spacer()

            // Zoom controls
            HStack(spacing: 8) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        zoom = max(0.25, zoom - 0.25)
                    }
                }) {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Text("\(Int(zoom * 100))%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 44)

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        zoom = min(3.0, zoom + 0.25)
                    }
                }) {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.04))
            )

            // Separator
            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(width: 1, height: 28)

            // Color under cursor display (clickable to copy hex)
            if hoveredColor != nil {
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(hoveredColorHex, forType: .string)
                }) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(hoveredColor ?? .clear)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                            )

                        Text(hoveredColorHex)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(isColorPickerHovered ? .primary : .secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isColorPickerHovered ? Color.primary.opacity(0.08) : Color.primary.opacity(0.04))
                    )
                }
                .buttonStyle(.plain)
                .help("Click to copy hex code")
                .onHover { hovering in
                    isColorPickerHovered = hovering
                }
            }

            // Separator
            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(width: 1, height: 28)

            // Backdrop button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showBackdropPanel.toggle()
                    if showBackdropPanel && !backdropEnabled {
                        backdropEnabled = true
                    }
                }
            }) {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(showBackdropPanel ? .white : .primary.opacity(0.8))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(showBackdropPanel ? Color.purple : Color.primary.opacity(0.05))
                    )
            }
            .buttonStyle(.plain)
            .help("Backdrop settings")

            // Separator
            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(width: 1, height: 28)

            // Undo/Clear
            HStack(spacing: 6) {
                ToolbarActionButton(
                    icon: "arrow.uturn.backward",
                    label: L10n.Annotation.undo,
                    isDisabled: annotations.isEmpty,
                    action: undo
                )

                ToolbarActionButton(
                    icon: "trash",
                    label: L10n.Annotation.clear,
                    isDisabled: annotations.isEmpty,
                    isDestructive: true,
                    action: clearAll
                )
            }

            // Layer controls (only shown when annotation is selected)
            if selectedAnnotationId != nil {
                Rectangle()
                    .fill(Color.primary.opacity(0.1))
                    .frame(width: 1, height: 28)

                HStack(spacing: 4) {
                    ToolbarActionButton(
                        icon: "square.3.layers.3d.down.left",
                        label: "Back",
                        isDisabled: false,
                        action: sendToBack
                    )

                    ToolbarActionButton(
                        icon: "square.2.layers.3d.bottom.filled",
                        label: "↓",
                        isDisabled: false,
                        action: sendBackward
                    )

                    ToolbarActionButton(
                        icon: "square.2.layers.3d.top.filled",
                        label: "↑",
                        isDisabled: false,
                        action: bringForward
                    )

                    ToolbarActionButton(
                        icon: "square.3.layers.3d.down.right",
                        label: "Front",
                        isDisabled: false,
                        action: bringToFront
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                Color.primary.opacity(0.02)
            }
        )
    }

    // MARK: - Bottom Bar
    private var bottomBar: some View {
        HStack(spacing: 16) {
            // Cancel button
            Button(action: onCancel) {
                HStack(spacing: 5) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                    Text(L10n.Annotation.cancel)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.06))
                )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape)

            Spacer()

            // Annotations count
            if !annotations.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "pencil.and.scribble")
                        .font(.system(size: 11))
                    Text(L10n.Annotation.annotations(annotations.count))
                        .font(.system(size: 11))
                }
                .foregroundColor(.secondary)
            }

            Spacer()

            // Action buttons
            HStack(spacing: 10) {
                // OCR Button
                Button(action: performOCR) {
                    HStack(spacing: 5) {
                        if isPerformingOCR {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "text.viewfinder")
                                .font(.system(size: 10, weight: .medium))
                        }
                        Text("OCR")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
                .disabled(isPerformingOCR)
                .help("Extract text from image and copy to clipboard")

                Button(action: copyToClipboard) {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 10, weight: .medium))
                        Text(L10n.Overlay.copy)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)

                // Save as editable project
                Button(action: saveProject) {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 10, weight: .medium))
                        Text("Save project")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
                .help("Save as editable .dodo project file")

                Button(action: saveImage) {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 10, weight: .medium))
                        Text(L10n.Overlay.save)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.accentColor)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                Color.primary.opacity(0.02)
            }
        )
    }

    // MARK: - Actions
    private func undo() {
        guard !annotations.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            _ = annotations.removeLast()
        }
    }

    private func clearAll() {
        withAnimation(.easeInOut(duration: 0.2)) {
            annotations.removeAll()
        }
    }

    private func cancelTextInput() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isAddingText = false
            currentText = ""
        }
    }

    private func addTextAnnotation() {
        guard !currentText.isEmpty else { return }

        let annotation = Annotation(
            type: .text,
            startPoint: textPosition,
            color: NSColor(selectedColor),
            text: currentText
        )
        annotations.append(annotation)
        cancelTextInput()
    }

    private func copyToClipboard() {
        let finalImage = renderAnnotatedImage()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([finalImage])
    }

    private func performOCR() {
        isPerformingOCR = true

        OCRService.shared.extractText(from: screenshot.image) { result in
            isPerformingOCR = false

            switch result {
            case .success(let text):
                // Copy to clipboard
                OCRService.shared.copyToClipboard(text)
                ocrResult = text
                showOCRResult = true

                // Auto-hide after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    showOCRResult = false
                }

            case .failure(let error):
                ocrResult = "Error: \(error.localizedDescription)"
                showOCRResult = true

                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    showOCRResult = false
                }
            }
        }
    }

    private func saveImage() {
        let finalImage = renderAnnotatedImage()
        // Create a new screenshot with the rendered image including annotations
        let updatedScreenshot = Screenshot(
            id: screenshot.id,
            image: finalImage,
            capturedAt: screenshot.capturedAt,
            captureType: screenshot.captureType,
            annotations: annotations,
            extractedText: screenshot.extractedText,
            aiDescription: screenshot.aiDescription
        )
        onSave(updatedScreenshot)
    }

    private func saveProject() {
        // Update screenshot with current annotations
        var projectScreenshot = screenshot
        projectScreenshot.annotations = annotations

        do {
            let project = try DodoShotProject(screenshot: projectScreenshot)

            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.init(filenameExtension: "dodo")!]
            savePanel.nameFieldStringValue = "Screenshot_\(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-"))"

            if savePanel.runModal() == .OK, let url = savePanel.url {
                try project.save(to: url)
            }
        } catch {
            print("Failed to save project: \(error)")
        }
    }

    static func openProject() -> Screenshot? {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.init(filenameExtension: "dodo")!]
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false

        if openPanel.runModal() == .OK, let url = openPanel.url {
            do {
                let project = try DodoShotProject.load(from: url)
                return project.toScreenshot()
            } catch {
                print("Failed to load project: \(error)")
            }
        }
        return nil
    }

    private func renderAnnotatedImage() -> NSImage {
        let originalImage = screenshot.image
        let imageSize = originalImage.size

        // If backdrop is enabled, render with backdrop
        if backdropEnabled {
            return renderImageWithBackdrop(originalImage: originalImage)
        }

        // Create a new image with the same size
        let newImage = NSImage(size: imageSize)
        newImage.lockFocus()

        // Draw the original image
        originalImage.draw(in: NSRect(origin: .zero, size: imageSize))

        // Get the current graphics context
        guard let context = NSGraphicsContext.current?.cgContext else {
            newImage.unlockFocus()
            return originalImage
        }

        // Calculate scale factor between canvas size and actual image size
        // The canvas displays the image fitted within the view, so we need to scale annotations
        let scaleX = imageSize.width / self.imageSize.width
        let scaleY = imageSize.height / self.imageSize.height

        // Draw all annotations
        for annotation in annotations {
            drawAnnotationOnImage(annotation, in: context, scaleX: scaleX, scaleY: scaleY)
        }

        newImage.unlockFocus()
        return newImage
    }

    private func renderImageWithBackdrop(originalImage: NSImage) -> NSImage {
        let imageSize = originalImage.size

        // Add padding for backdrop (proportional to image size)
        let paddingPercent: CGFloat = 0.15
        let paddingX = imageSize.width * paddingPercent
        let paddingY = imageSize.height * paddingPercent
        let backdropSize = NSSize(
            width: imageSize.width + paddingX * 2,
            height: imageSize.height + paddingY * 2
        )

        let newImage = NSImage(size: backdropSize)
        newImage.lockFocus()

        guard let context = NSGraphicsContext.current?.cgContext else {
            newImage.unlockFocus()
            return originalImage
        }

        // Draw backdrop
        let backdropRect = NSRect(origin: .zero, size: backdropSize)
        let backdropPath = NSBezierPath(roundedRect: backdropRect, xRadius: outerRadius, yRadius: outerRadius)

        switch backdropType {
        case .solid:
            NSColor(selectedSolidColor).setFill()
            backdropPath.fill()

        case .gradient:
            // Draw gradient
            let colors = selectedGradient.colors.map { NSColor($0) }
            let nsColors = colors as [NSColor]
            let cgColors = nsColors.map { $0.cgColor } as CFArray

            if gradientDirection == .linear {
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: nil) {
                    context.saveGState()
                    backdropPath.addClip()
                    context.drawLinearGradient(
                        gradient,
                        start: CGPoint(x: 0, y: backdropSize.height),
                        end: CGPoint(x: backdropSize.width, y: 0),
                        options: []
                    )
                    context.restoreGState()
                }
            } else {
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: nil) {
                    context.saveGState()
                    backdropPath.addClip()
                    let center = CGPoint(x: backdropSize.width / 2, y: backdropSize.height / 2)
                    let radius = max(backdropSize.width, backdropSize.height)
                    context.drawRadialGradient(
                        gradient,
                        startCenter: center,
                        startRadius: 0,
                        endCenter: center,
                        endRadius: radius,
                        options: []
                    )
                    context.restoreGState()
                }
            }

        case .transparent:
            // Don't fill backdrop - leave it transparent
            // The backdrop area still provides padding and allows shadow/corner rounding
            break
        }

        // Calculate image rect (centered with padding)
        let imageRect = NSRect(
            x: paddingX,
            y: paddingY,
            width: imageSize.width,
            height: imageSize.height
        )

        // Draw shadow if enabled
        if shadowEnabled {
            context.saveGState()
            context.setShadow(
                offset: CGSize(width: 0, height: -shadowOffset),
                blur: shadowBlur,
                color: NSColor.black.withAlphaComponent(shadowOpacity).cgColor
            )

            // Draw a rounded rect for shadow
            let shadowPath = NSBezierPath(roundedRect: imageRect, xRadius: innerRadius, yRadius: innerRadius)
            NSColor.black.setFill()
            shadowPath.fill()
            context.restoreGState()
        }

        // Clip to rounded rect for the image
        context.saveGState()
        let imagePath = NSBezierPath(roundedRect: imageRect, xRadius: innerRadius, yRadius: innerRadius)
        imagePath.addClip()

        // Draw the original image
        originalImage.draw(in: imageRect)

        // Draw annotations
        let scaleX = imageSize.width / self.imageSize.width
        let scaleY = imageSize.height / self.imageSize.height

        // Translate context to image origin
        context.translateBy(x: paddingX, y: paddingY)

        for annotation in annotations {
            drawAnnotationOnImage(annotation, in: context, scaleX: scaleX, scaleY: scaleY)
        }

        context.restoreGState()

        newImage.unlockFocus()
        return newImage
    }

    private func drawAnnotationOnImage(_ annotation: Annotation, in context: CGContext, scaleX: CGFloat, scaleY: CGFloat) {
        // Scale points
        let start = CGPoint(x: annotation.startPoint.x * scaleX, y: annotation.startPoint.y * scaleY)
        let end = CGPoint(x: annotation.endPoint.x * scaleX, y: annotation.endPoint.y * scaleY)
        let scaledStrokeWidth = annotation.strokeWidth * min(scaleX, scaleY)

        context.setStrokeColor(annotation.color.cgColor)
        context.setFillColor(annotation.color.cgColor)
        context.setLineWidth(scaledStrokeWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch annotation.type {
        case .arrow:
            drawArrowOnImage(from: start, to: end, in: context, strokeWidth: scaledStrokeWidth)

        case .rectangle:
            let rect = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            context.stroke(rect)

        case .ellipse:
            let rect = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            context.strokeEllipse(in: rect)

        case .line:
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()

        case .text:
            if let text = annotation.text {
                let fontSize = 16 * min(scaleX, scaleY)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
                    .foregroundColor: annotation.color
                ]
                let string = NSAttributedString(string: text, attributes: attributes)
                string.draw(at: start)
            }

        case .blur:
            let rect = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            context.setFillColor(NSColor.gray.withAlphaComponent(0.5).cgColor)
            context.fill(rect)

        case .highlight:
            let rect = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            context.setFillColor(annotation.color.withAlphaComponent(0.3).cgColor)
            context.fill(rect)

        case .freehand:
            guard annotation.points.count > 1 else { return }
            let scaledPoints = annotation.points.map { CGPoint(x: $0.x * scaleX, y: $0.y * scaleY) }
            context.move(to: scaledPoints[0])
            for i in 1..<scaledPoints.count {
                context.addLine(to: scaledPoints[i])
            }
            context.strokePath()

        case .erase:
            // Erase draws white over the image
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(scaledStrokeWidth * 3)
            guard annotation.points.count > 1 else { return }
            let scaledPoints = annotation.points.map { CGPoint(x: $0.x * scaleX, y: $0.y * scaleY) }
            context.move(to: scaledPoints[0])
            for i in 1..<scaledPoints.count {
                context.addLine(to: scaledPoints[i])
            }
            context.strokePath()

        case .pixelate:
            let rect = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            // Draw pixelation pattern for export
            drawPixelateOnImage(in: context, rect: rect, intensity: annotation.redactionIntensity)

        case .stepCounter:
            // Draw step counter circle with number
            let fontSize = 16 * min(scaleX, scaleY)
            let radius = max(scaledStrokeWidth * 2, 16)
            let stepNumber = annotation.stepNumber ?? 1
            let displayText = annotation.stepCounterFormat.format(stepNumber)

            // Draw filled circle
            let circleRect = CGRect(
                x: start.x - radius,
                y: start.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.setFillColor(annotation.color.cgColor)
            context.fillEllipse(in: circleRect)

            // Draw text
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let string = NSAttributedString(string: displayText, attributes: attributes)
            let textSize = string.size()
            let textPoint = CGPoint(
                x: start.x - textSize.width / 2,
                y: start.y - textSize.height / 2
            )
            string.draw(at: textPoint)

        case .select:
            break
        }
    }

    private func drawPixelateOnImage(in context: CGContext, rect: CGRect, intensity: CGFloat) {
        // Draw a grid pattern to represent pixelation
        let pixelSize = max(4, (1.0 - intensity) * 20 + 4)
        context.saveGState()
        context.clip(to: rect)

        var y = rect.minY
        while y < rect.maxY {
            var x = rect.minX
            var colorIndex = 0
            while x < rect.maxX {
                let gray = colorIndex % 2 == 0 ? 0.4 : 0.6
                context.setFillColor(NSColor(white: CGFloat(gray), alpha: 0.8).cgColor)
                let pixelRect = CGRect(x: x, y: y, width: pixelSize, height: pixelSize)
                context.fill(pixelRect)
                x += pixelSize
                colorIndex += 1
            }
            y += pixelSize
        }

        context.restoreGState()
    }

    private func drawArrowOnImage(from start: CGPoint, to end: CGPoint, in context: CGContext, strokeWidth: CGFloat) {
        let headLength: CGFloat = 15 + strokeWidth
        let headAngle: CGFloat = .pi / 6

        let angle = atan2(end.y - start.y, end.x - start.x)

        // Draw line
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        // Draw arrowhead
        let arrowPoint1 = CGPoint(
            x: end.x - headLength * cos(angle - headAngle),
            y: end.y - headLength * sin(angle - headAngle)
        )
        let arrowPoint2 = CGPoint(
            x: end.x - headLength * cos(angle + headAngle),
            y: end.y - headLength * sin(angle + headAngle)
        )

        context.move(to: end)
        context.addLine(to: arrowPoint1)
        context.move(to: end)
        context.addLine(to: arrowPoint2)
        context.strokePath()
    }

}

// MARK: - Canvas Background
struct CanvasBackground: View {
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let gridSize: CGFloat = 20
                let dotRadius: CGFloat = 1

                for x in stride(from: 0, to: size.width, by: gridSize) {
                    for y in stride(from: 0, to: size.height, by: gridSize) {
                        context.fill(
                            Path(ellipseIn: CGRect(x: x - dotRadius, y: y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)),
                            with: .color(.primary.opacity(0.05))
                        )
                    }
                }
            }
        }
        .background(Color.primary.opacity(0.02))
    }
}

// MARK: - Annotation Tool Button
struct AnnotationToolButton: View {
    let tool: AnnotationType
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    private var toolColor: Color {
        switch tool {
        case .arrow: return .red
        case .rectangle: return .blue
        case .ellipse: return .green
        case .line: return .orange
        case .text: return .purple
        case .blur: return .gray
        case .pixelate: return .orange
        case .highlight: return .yellow
        case .freehand: return .pink
        case .select: return .blue
        case .erase: return .white
        case .stepCounter: return .red
        }
    }

    private var toolName: String {
        switch tool {
        case .select: return "Select (to delete)"
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Circle"
        case .line: return "Line"
        case .text: return "Text"
        case .blur: return "Blur"
        case .pixelate: return "Pixelate"
        case .highlight: return "Highlight"
        case .freehand: return "Draw"
        case .erase: return "Erase"
        case .stepCounter: return "Step"
        }
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: tool.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isSelected ? .white : (isHovered ? toolColor : .primary.opacity(0.8)))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? toolColor : (isHovered ? toolColor.opacity(0.15) : Color.primary.opacity(0.05)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? toolColor : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(toolName)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Annotation Color Button
struct AnnotationColorButton: View {
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // Outer ring (selection indicator)
                Circle()
                    .stroke(isSelected ? color : Color.clear, lineWidth: 2)
                    .frame(width: 24, height: 24)

                // Color circle
                Circle()
                    .fill(color)
                    .frame(width: 18, height: 18)
                    .overlay(
                        Circle()
                            .stroke(color == .white ? Color.gray.opacity(0.3) : Color.white.opacity(0.2), lineWidth: 1)
                    )
            }
            .scaleEffect(isHovered ? 1.1 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Stroke Width Button
struct StrokeWidthButton: View {
    let width: CGFloat
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 2)
                .fill(isSelected ? color : Color.primary.opacity(0.6))
                .frame(width: 24, height: width)
                .padding(.vertical, (12 - width) / 2)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? color.opacity(0.2) : (isHovered ? Color.primary.opacity(0.1) : Color.primary.opacity(0.03)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? color.opacity(0.5) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help("\(Int(width))px")
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Slider Row
struct SliderRow: View {
    let label: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    var format: String = "%.0f"
    var multiplier: CGFloat = 1

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .leading)

            Slider(value: $value, in: range)
                .controlSize(.small)

            Text(String(format: format, value * multiplier))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 35, alignment: .trailing)
        }
    }
}

// MARK: - Toolbar Action Button
struct ToolbarActionButton: View {
    let icon: String
    let label: String
    let isDisabled: Bool
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(
                    isDisabled ? .secondary.opacity(0.3) :
                    (isDestructive ? (isHovered ? .red : .primary.opacity(0.7)) : .primary.opacity(0.8))
                )
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered && !isDisabled ? (isDestructive ? Color.red.opacity(0.1) : Color.primary.opacity(0.1)) : Color.primary.opacity(0.03))
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(label)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Annotation Canvas View
struct AnnotationCanvasView: NSViewRepresentable {
    @Binding var annotations: [Annotation]
    @Binding var currentAnnotation: Annotation?
    let selectedTool: AnnotationType
    let selectedColor: NSColor
    let strokeWidth: CGFloat
    @Binding var isAddingText: Bool
    @Binding var textPosition: CGPoint
    @Binding var currentText: String
    @Binding var selectedAnnotationId: UUID?
    let onSelectAnnotation: (CGPoint) -> Void
    let onDeleteSelected: () -> Void
    let onUndo: () -> Void
    var onColorPicked: ((Color, String) -> Void)?
    var onTextAdded: ((String, CGPoint) -> Void)?

    func makeNSView(context: Context) -> AnnotationCanvasNSView {
        let view = AnnotationCanvasNSView()
        view.delegate = context.coordinator
        context.coordinator.canvasView = view
        view.onColorPicked = onColorPicked
        view.onTextAdded = onTextAdded
        view.selectedColor = selectedColor
        return view
    }

    func updateNSView(_ nsView: AnnotationCanvasNSView, context: Context) {
        nsView.annotations = annotations
        nsView.currentAnnotation = currentAnnotation
        nsView.selectedTool = selectedTool
        nsView.selectedColor = selectedColor
        nsView.strokeWidth = strokeWidth
        nsView.selectedAnnotationId = selectedAnnotationId
        nsView.onDeleteSelected = onDeleteSelected
        nsView.onUndo = onUndo
        nsView.onColorPicked = onColorPicked
        nsView.onTextAdded = onTextAdded
        nsView.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, AnnotationCanvasDelegate {
        var parent: AnnotationCanvasView
        weak var canvasView: AnnotationCanvasNSView?
        private var dragStartPoint: CGPoint?
        private var isDraggingAnnotation = false
        private var draggedAnnotationIndex: Int?
        private var dragOffset: CGPoint = .zero

        init(_ parent: AnnotationCanvasView) {
            self.parent = parent
        }

        func didStartDrawing(at point: CGPoint) {
            dragStartPoint = point

            // Get current tool from the NSView (which is updated by SwiftUI)
            let currentTool = canvasView?.selectedTool ?? parent.selectedTool
            let currentColor = canvasView?.selectedColor ?? parent.selectedColor
            let currentStrokeWidth = canvasView?.strokeWidth ?? parent.strokeWidth

            if currentTool == .text {
                // Start inline text editing
                canvasView?.startTextEditing(at: point, color: currentColor)
            } else if currentTool == .select {
                // Selection mode - check if clicking on an annotation
                // First check if clicking on already selected annotation to start dragging
                if let selectedId = parent.selectedAnnotationId,
                   let index = parent.annotations.firstIndex(where: { $0.id == selectedId }) {
                    let annotation = parent.annotations[index]
                    if annotationContainsPoint(annotation, point: point) {
                        // Start dragging the selected annotation
                        isDraggingAnnotation = true
                        draggedAnnotationIndex = index
                        // Calculate offset from click point to annotation's start point
                        dragOffset = CGPoint(
                            x: point.x - annotation.startPoint.x,
                            y: point.y - annotation.startPoint.y
                        )
                        return
                    }
                }
                // If not dragging, try to select an annotation at the point
                parent.onSelectAnnotation(point)
            } else {
                // Clear selection when starting to draw
                parent.selectedAnnotationId = nil
                isDraggingAnnotation = false
                draggedAnnotationIndex = nil

                var annotation = Annotation(
                    type: currentTool,
                    startPoint: point,
                    endPoint: point,  // Initialize endPoint to startPoint to prevent flash from origin
                    color: currentColor,
                    strokeWidth: currentStrokeWidth
                )

                // Set z-index for new annotation
                annotation.zIndex = parent.annotations.count

                // For freehand and erase, start with the first point
                if currentTool == .freehand || currentTool == .erase {
                    annotation.points = [point]
                }

                // For step counter, set auto-increment step number
                if currentTool == .stepCounter {
                    let stepAnnotations = parent.annotations.filter { $0.type == .stepCounter }
                    annotation.stepNumber = stepAnnotations.count + 1
                }

                parent.currentAnnotation = annotation
            }
        }

        func didContinueDrawing(at point: CGPoint) {
            let currentTool = canvasView?.selectedTool ?? parent.selectedTool

            // Handle annotation dragging
            if isDraggingAnnotation, let index = draggedAnnotationIndex {
                moveAnnotation(at: index, to: point)
                return
            }

            if currentTool == .freehand || currentTool == .erase {
                parent.currentAnnotation?.points.append(point)
            }
            parent.currentAnnotation?.endPoint = point
        }

        func didEndDrawing(at point: CGPoint) {
            // Finish annotation dragging
            if isDraggingAnnotation {
                if let index = draggedAnnotationIndex {
                    moveAnnotation(at: index, to: point)
                }
                isDraggingAnnotation = false
                draggedAnnotationIndex = nil
                dragOffset = .zero
                return
            }

            let currentTool = canvasView?.selectedTool ?? parent.selectedTool
            if var annotation = parent.currentAnnotation {
                annotation.endPoint = point
                if currentTool == .freehand || currentTool == .erase {
                    annotation.points.append(point)
                }

                // Only add annotation if it has meaningful size (not just a click)
                // Exception: step counter works with single clicks
                let minSize: CGFloat = 5
                let width = abs(annotation.endPoint.x - annotation.startPoint.x)
                let height = abs(annotation.endPoint.y - annotation.startPoint.y)
                let hasSize = width > minSize || height > minSize

                // For freehand/erase, check if there's actual movement
                let hasFreehandMovement = (currentTool == .freehand || currentTool == .erase) && annotation.points.count > 2

                // Step counter is point-based - always allow
                let isStepCounter = currentTool == .stepCounter

                if hasSize || hasFreehandMovement || isStepCounter {
                    parent.annotations.append(annotation)
                }
                parent.currentAnnotation = nil
            }
            dragStartPoint = nil
        }

        private func moveAnnotation(at index: Int, to point: CGPoint) {
            guard index < parent.annotations.count else { return }

            var annotation = parent.annotations[index]
            let newStartPoint = CGPoint(
                x: point.x - dragOffset.x,
                y: point.y - dragOffset.y
            )

            // Calculate the delta movement
            let deltaX = newStartPoint.x - annotation.startPoint.x
            let deltaY = newStartPoint.y - annotation.startPoint.y

            // Move start and end points
            annotation.startPoint = newStartPoint
            annotation.endPoint = CGPoint(
                x: annotation.endPoint.x + deltaX,
                y: annotation.endPoint.y + deltaY
            )

            // Move freehand/erase points if applicable
            if annotation.type == .freehand || annotation.type == .erase {
                annotation.points = annotation.points.map { pt in
                    CGPoint(x: pt.x + deltaX, y: pt.y + deltaY)
                }
            }

            parent.annotations[index] = annotation
        }

        private func annotationContainsPoint(_ annotation: Annotation, point: CGPoint) -> Bool {
            let tolerance: CGFloat = 10
            let start = annotation.startPoint
            let end = annotation.endPoint

            switch annotation.type {
            case .arrow, .line:
                return pointNearLine(point: point, lineStart: start, lineEnd: end, tolerance: tolerance)
            case .rectangle, .blur, .highlight, .pixelate:
                let rect = CGRect(
                    x: min(start.x, end.x) - tolerance,
                    y: min(start.y, end.y) - tolerance,
                    width: abs(end.x - start.x) + tolerance * 2,
                    height: abs(end.y - start.y) + tolerance * 2
                )
                return rect.contains(point)
            case .stepCounter:
                // Step counter is a circle around the start point
                let radius: CGFloat = max(annotation.strokeWidth * 2, 16) + tolerance
                let distance = hypot(point.x - start.x, point.y - start.y)
                return distance <= radius
            case .ellipse:
                let rect = CGRect(
                    x: min(start.x, end.x),
                    y: min(start.y, end.y),
                    width: abs(end.x - start.x),
                    height: abs(end.y - start.y)
                )
                return rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
            case .text:
                let textRect = CGRect(x: start.x - tolerance, y: start.y - tolerance, width: 100 + tolerance * 2, height: 30 + tolerance * 2)
                return textRect.contains(point)
            case .freehand, .erase:
                for pathPoint in annotation.points {
                    if abs(pathPoint.x - point.x) < tolerance && abs(pathPoint.y - point.y) < tolerance {
                        return true
                    }
                }
                return false
            case .select:
                return false
            }
        }

        private func pointNearLine(point: CGPoint, lineStart: CGPoint, lineEnd: CGPoint, tolerance: CGFloat) -> Bool {
            let dx = lineEnd.x - lineStart.x
            let dy = lineEnd.y - lineStart.y
            let lengthSquared = dx * dx + dy * dy

            if lengthSquared == 0 {
                return hypot(point.x - lineStart.x, point.y - lineStart.y) < tolerance
            }

            let t = max(0, min(1, ((point.x - lineStart.x) * dx + (point.y - lineStart.y) * dy) / lengthSquared))
            let nearestX = lineStart.x + t * dx
            let nearestY = lineStart.y + t * dy
            let distance = hypot(point.x - nearestX, point.y - nearestY)

            return distance < tolerance
        }
    }
}

// MARK: - Canvas Delegate Protocol
protocol AnnotationCanvasDelegate: AnyObject {
    func didStartDrawing(at point: CGPoint)
    func didContinueDrawing(at point: CGPoint)
    func didEndDrawing(at point: CGPoint)
}

// MARK: - Annotation Canvas NSView
class AnnotationCanvasNSView: NSView, NSTextFieldDelegate {
    weak var delegate: AnnotationCanvasDelegate?

    var annotations: [Annotation] = []
    var currentAnnotation: Annotation?
    var selectedTool: AnnotationType = .arrow
    var selectedColor: NSColor = .red
    var strokeWidth: CGFloat = 3.0
    var selectedAnnotationId: UUID?
    var onDeleteSelected: (() -> Void)?
    var onColorPicked: ((Color, String) -> Void)?
    var onTextAdded: ((String, CGPoint) -> Void)?
    var sourceImage: NSImage?

    private var trackingArea: NSTrackingArea?
    private var textField: NSTextField?
    private var textEditingPosition: CGPoint?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }

        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )

        if let trackingArea = trackingArea {
            addTrackingArea(trackingArea)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    // MARK: - Inline Text Editing
    func startTextEditing(at point: CGPoint, color: NSColor) {
        // Remove existing text field if any
        textField?.removeFromSuperview()

        textEditingPosition = point

        let field = NSTextField(frame: NSRect(x: point.x, y: point.y - 10, width: 200, height: 24))
        field.font = NSFont.systemFont(ofSize: 16, weight: .medium)
        field.textColor = color
        field.backgroundColor = NSColor.white.withAlphaComponent(0.9)
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .none
        field.placeholderString = "Type text..."
        field.delegate = self
        field.target = self
        field.action = #selector(textFieldDidFinish(_:))

        addSubview(field)
        field.becomeFirstResponder()
        textField = field
    }

    @objc private func textFieldDidFinish(_ sender: NSTextField) {
        finishTextEditing()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        finishTextEditing()
    }

    private func finishTextEditing() {
        guard let field = textField, let position = textEditingPosition else { return }

        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            onTextAdded?(text, position)
        }

        field.removeFromSuperview()
        textField = nil
        textEditingPosition = nil
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)

        // Update cursor based on hover state over selected annotation
        if selectedTool == .select, let selectedId = selectedAnnotationId,
           let annotation = annotations.first(where: { $0.id == selectedId }) {
            if isPointInsideAnnotation(location, annotation: annotation) {
                NSCursor.openHand.set()
            } else {
                NSCursor.arrow.set()
            }
        } else {
            NSCursor.arrow.set()
        }

        pickColorAt(location)
    }

    private func isPointInsideAnnotation(_ point: CGPoint, annotation: Annotation) -> Bool {
        let tolerance: CGFloat = 10
        let start = annotation.startPoint
        let end = annotation.endPoint

        switch annotation.type {
        case .arrow, .line:
            return isPointNearLine(point: point, lineStart: start, lineEnd: end, tolerance: tolerance)
        case .rectangle, .blur, .highlight, .pixelate:
            let rect = CGRect(
                x: min(start.x, end.x) - tolerance,
                y: min(start.y, end.y) - tolerance,
                width: abs(end.x - start.x) + tolerance * 2,
                height: abs(end.y - start.y) + tolerance * 2
            )
            return rect.contains(point)
        case .stepCounter:
            let radius: CGFloat = max(annotation.strokeWidth * 2, 16) + tolerance
            let distance = hypot(point.x - start.x, point.y - start.y)
            return distance <= radius
        case .ellipse:
            let rect = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            return rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case .text:
            let textRect = CGRect(x: start.x - tolerance, y: start.y - tolerance, width: 100 + tolerance * 2, height: 30 + tolerance * 2)
            return textRect.contains(point)
        case .freehand, .erase:
            for pathPoint in annotation.points {
                if abs(pathPoint.x - point.x) < tolerance && abs(pathPoint.y - point.y) < tolerance {
                    return true
                }
            }
            return false
        case .select:
            return false
        }
    }

    private func isPointNearLine(point: CGPoint, lineStart: CGPoint, lineEnd: CGPoint, tolerance: CGFloat) -> Bool {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let lengthSquared = dx * dx + dy * dy

        if lengthSquared == 0 {
            return hypot(point.x - lineStart.x, point.y - lineStart.y) < tolerance
        }

        let t = max(0, min(1, ((point.x - lineStart.x) * dx + (point.y - lineStart.y) * dy) / lengthSquared))
        let nearestX = lineStart.x + t * dx
        let nearestY = lineStart.y + t * dy
        let distance = hypot(point.x - nearestX, point.y - nearestY)

        return distance < tolerance
    }

    private func pickColorAt(_ point: CGPoint) {
        // Get the window's backing image
        guard let window = self.window,
              let cgImage = CGWindowListCreateImage(
                  window.frame,
                  .optionIncludingWindow,
                  CGWindowID(window.windowNumber),
                  [.bestResolution]
              ) else { return }

        // Convert point to image coordinates
        let scale = window.backingScaleFactor
        let imageX = Int(point.x * scale)
        let imageY = Int(point.y * scale)

        // Get pixel color
        guard imageX >= 0, imageY >= 0,
              imageX < cgImage.width, imageY < cgImage.height else { return }

        guard let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data,
              let ptr = CFDataGetBytePtr(data) else { return }

        let bytesPerRow = cgImage.bytesPerRow
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let offset = imageY * bytesPerRow + imageX * bytesPerPixel

        let r = ptr[offset]
        let g = ptr[offset + 1]
        let b = ptr[offset + 2]

        let color = Color(
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0
        )
        let hex = String(format: "#%02X%02X%02X", r, g, b)

        DispatchQueue.main.async { [weak self] in
            self?.onColorPicked?(color, hex)
        }
    }

    var onUndo: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // Handle Delete and Backspace keys
        if event.keyCode == 51 || event.keyCode == 117 { // Backspace or Delete
            if selectedAnnotationId != nil {
                onDeleteSelected?()
                return
            }
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Handle CMD+Z for undo
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "z" {
            onUndo?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Draw all completed annotations
        for annotation in annotations {
            drawAnnotation(annotation, in: context)

            // Draw selection highlight if this annotation is selected
            if annotation.id == selectedAnnotationId {
                drawSelectionHighlight(for: annotation, in: context)
            }
        }

        // Draw current annotation being created
        if let current = currentAnnotation {
            drawAnnotation(current, in: context)
        }
    }

    private func drawSelectionHighlight(for annotation: Annotation, in context: CGContext) {
        let selectionColor = NSColor.systemBlue.cgColor
        context.setStrokeColor(selectionColor)
        context.setLineWidth(2)
        context.setLineDash(phase: 0, lengths: [5, 3])

        let bounds = getAnnotationBounds(annotation)
        let selectionRect = bounds.insetBy(dx: -6, dy: -6)

        context.stroke(selectionRect)

        // Draw corner handles
        let handleSize: CGFloat = 8
        context.setFillColor(NSColor.white.cgColor)
        context.setLineDash(phase: 0, lengths: [])

        let corners = [
            CGPoint(x: selectionRect.minX, y: selectionRect.minY),
            CGPoint(x: selectionRect.maxX, y: selectionRect.minY),
            CGPoint(x: selectionRect.minX, y: selectionRect.maxY),
            CGPoint(x: selectionRect.maxX, y: selectionRect.maxY)
        ]

        for corner in corners {
            let handleRect = CGRect(
                x: corner.x - handleSize / 2,
                y: corner.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            context.fill(handleRect)
            context.stroke(handleRect)
        }

        // Reset line dash
        context.setLineDash(phase: 0, lengths: [])
    }

    private func getAnnotationBounds(_ annotation: Annotation) -> CGRect {
        let start = annotation.startPoint
        let end = annotation.endPoint

        switch annotation.type {
        case .arrow, .line:
            return CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
        case .rectangle, .ellipse, .blur, .highlight, .pixelate:
            return CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
        case .stepCounter:
            let radius: CGFloat = max(annotation.strokeWidth * 2, 16)
            return CGRect(
                x: start.x - radius,
                y: start.y - radius,
                width: radius * 2,
                height: radius * 2
            )
        case .text:
            return CGRect(x: start.x, y: start.y, width: 100, height: 30)
        case .freehand, .erase:
            guard !annotation.points.isEmpty else {
                return CGRect(origin: start, size: .zero)
            }
            var minX = annotation.points[0].x
            var maxX = annotation.points[0].x
            var minY = annotation.points[0].y
            var maxY = annotation.points[0].y
            for point in annotation.points {
                minX = min(minX, point.x)
                maxX = max(maxX, point.x)
                minY = min(minY, point.y)
                maxY = max(maxY, point.y)
            }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        case .select:
            return .zero
        }
    }

    private func drawAnnotation(_ annotation: Annotation, in context: CGContext) {
        context.setStrokeColor(annotation.color.cgColor)
        context.setFillColor(annotation.color.cgColor)
        context.setLineWidth(annotation.strokeWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let start = annotation.startPoint
        let end = annotation.endPoint

        switch annotation.type {
        case .arrow:
            drawArrow(from: start, to: end, in: context, strokeWidth: annotation.strokeWidth)

        case .rectangle:
            let rect = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            context.stroke(rect)

        case .ellipse:
            let rect = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            context.strokeEllipse(in: rect)

        case .line:
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()

        case .text:
            if let text = annotation.text {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 16, weight: .medium),
                    .foregroundColor: annotation.color
                ]
                let string = NSAttributedString(string: text, attributes: attributes)
                string.draw(at: start)
            }

        case .blur:
            // Draw blur effect preview (crosshatch pattern to indicate blur)
            let rect = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            drawRedactionPreview(in: context, rect: rect, style: annotation.redactionStyle, intensity: annotation.redactionIntensity)

        case .pixelate:
            // Draw pixelate effect preview (grid pattern to indicate pixelation)
            let rect = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            drawRedactionPreview(in: context, rect: rect, style: .pixelate, intensity: annotation.redactionIntensity)

        case .stepCounter:
            drawStepCounter(annotation: annotation, in: context)

        case .highlight:
            let rect = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            context.setFillColor(annotation.color.withAlphaComponent(0.3).cgColor)
            context.fill(rect)

        case .freehand:
            guard annotation.points.count > 1 else { return }
            context.move(to: annotation.points[0])
            for i in 1..<annotation.points.count {
                context.addLine(to: annotation.points[i])
            }
            context.strokePath()

        case .erase:
            // Erase is handled differently - it removes parts of annotations
            // For now, draw a white/background colored stroke
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(annotation.strokeWidth * 3) // Wider eraser
            guard annotation.points.count > 1 else { return }
            context.move(to: annotation.points[0])
            for i in 1..<annotation.points.count {
                context.addLine(to: annotation.points[i])
            }
            context.strokePath()

        case .select:
            break
        }
    }

    private func drawArrow(from start: CGPoint, to end: CGPoint, in context: CGContext, strokeWidth: CGFloat) {
        let headLength: CGFloat = 15 + strokeWidth
        let headAngle: CGFloat = .pi / 6

        let angle = atan2(end.y - start.y, end.x - start.x)

        // Draw line
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        // Draw arrowhead
        let arrowPoint1 = CGPoint(
            x: end.x - headLength * cos(angle - headAngle),
            y: end.y - headLength * sin(angle - headAngle)
        )
        let arrowPoint2 = CGPoint(
            x: end.x - headLength * cos(angle + headAngle),
            y: end.y - headLength * sin(angle + headAngle)
        )

        context.move(to: end)
        context.addLine(to: arrowPoint1)
        context.move(to: end)
        context.addLine(to: arrowPoint2)
        context.strokePath()
    }

    // MARK: - Step Counter Drawing
    private func drawStepCounter(annotation: Annotation, in context: CGContext) {
        let center = annotation.startPoint
        let stepNumber = annotation.stepNumber ?? 1
        let format = annotation.stepCounterFormat
        let displayText = format.format(stepNumber)

        // Calculate circle size based on text
        let fontSize = annotation.fontSize
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let textSize = (displayText as NSString).size(withAttributes: attributes)
        let circleRadius = max(textSize.width, textSize.height) / 2 + 10

        // Draw filled circle
        let circleRect = CGRect(
            x: center.x - circleRadius,
            y: center.y - circleRadius,
            width: circleRadius * 2,
            height: circleRadius * 2
        )

        context.setFillColor(annotation.color.cgColor)
        context.fillEllipse(in: circleRect)

        // Draw white border
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(2)
        context.strokeEllipse(in: circleRect)

        // Draw number/letter
        let textRect = CGRect(
            x: center.x - textSize.width / 2,
            y: center.y - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )
        let attributedString = NSAttributedString(string: displayText, attributes: attributes)
        attributedString.draw(in: textRect)
    }

    // MARK: - Redaction Preview Drawing
    private func drawRedactionPreview(in context: CGContext, rect: CGRect, style: RedactionStyle, intensity: CGFloat) {
        switch style {
        case .blur:
            // Draw crosshatch pattern to indicate blur
            context.saveGState()
            context.clip(to: rect)

            // Semi-transparent fill
            context.setFillColor(NSColor.gray.withAlphaComponent(0.4 * intensity).cgColor)
            context.fill(rect)

            // Crosshatch lines
            context.setStrokeColor(NSColor.gray.withAlphaComponent(0.6).cgColor)
            context.setLineWidth(1)

            let spacing: CGFloat = 8
            // Diagonal lines one direction
            var x = rect.minX - rect.height
            while x < rect.maxX {
                context.move(to: CGPoint(x: x, y: rect.maxY))
                context.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
                x += spacing
            }
            context.strokePath()

            // Border
            context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.5).cgColor)
            context.setLineWidth(2)
            context.setLineDash(phase: 0, lengths: [4, 4])
            context.stroke(rect)

            context.restoreGState()

        case .pixelate:
            // Draw grid pattern to indicate pixelation
            context.saveGState()
            context.clip(to: rect)

            let blockSize: CGFloat = max(8, 20 * (1 - intensity))

            // Draw checkerboard-like pattern
            var y = rect.minY
            var rowIndex = 0
            while y < rect.maxY {
                var x = rect.minX
                var colIndex = rowIndex % 2
                while x < rect.maxX {
                    let blockRect = CGRect(x: x, y: y, width: blockSize, height: blockSize)
                    let shade = colIndex % 2 == 0 ? 0.3 : 0.5
                    context.setFillColor(NSColor.gray.withAlphaComponent(shade * intensity).cgColor)
                    context.fill(blockRect)
                    x += blockSize
                    colIndex += 1
                }
                y += blockSize
                rowIndex += 1
            }

            // Border
            context.setStrokeColor(NSColor.systemOrange.withAlphaComponent(0.5).cgColor)
            context.setLineWidth(2)
            context.setLineDash(phase: 0, lengths: [4, 4])
            context.stroke(rect)

            context.restoreGState()

        case .solidBlack:
            context.setFillColor(NSColor.black.cgColor)
            context.fill(rect)

        case .solidWhite:
            context.setFillColor(NSColor.white.cgColor)
            context.fill(rect)
            context.setStrokeColor(NSColor.gray.cgColor)
            context.setLineWidth(1)
            context.stroke(rect)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)

        // Show closed hand cursor if clicking on selected annotation
        if selectedTool == .select, let selectedId = selectedAnnotationId,
           let annotation = annotations.first(where: { $0.id == selectedId }),
           isPointInsideAnnotation(location, annotation: annotation) {
            NSCursor.closedHand.set()
        }

        delegate?.didStartDrawing(at: location)
    }

    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        delegate?.didContinueDrawing(at: location)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        delegate?.didEndDrawing(at: location)

        // Reset cursor after drag
        if selectedTool == .select {
            NSCursor.arrow.set()
        }

        needsDisplay = true
    }
}

// MARK: - Backdrop Types
enum BackdropType: String, CaseIterable {
    case solid = "Solid"
    case gradient = "Gradient"
    case transparent = "Transparent"

    var icon: String {
        switch self {
        case .solid: return "square.fill"
        case .gradient: return "circle.lefthalf.filled"
        case .transparent: return "checkerboard.rectangle"
        }
    }
}

enum GradientDirection: String, CaseIterable {
    case linear = "Linear"
    case radial = "Radial"

    var icon: String {
        switch self {
        case .linear: return "arrow.down"
        case .radial: return "circle.dotted"
        }
    }
}

// MARK: - Solid Color Palette (20 curated colors)
struct SolidColorPalette {
    static let colors: [Color] = [
        // Row 1 - Neutrals
        Color(hex: "FFFFFF"), // White
        Color(hex: "F5F5F5"), // Light Gray
        Color(hex: "E0E0E0"), // Gray
        Color(hex: "424242"), // Dark Gray
        Color(hex: "212121"), // Almost Black

        // Row 2 - Blues & Purples
        Color(hex: "E3F2FD"), // Light Blue
        Color(hex: "2196F3"), // Blue
        Color(hex: "1565C0"), // Dark Blue
        Color(hex: "7C4DFF"), // Purple
        Color(hex: "4A148C"), // Deep Purple

        // Row 3 - Greens & Teals
        Color(hex: "E8F5E9"), // Light Green
        Color(hex: "4CAF50"), // Green
        Color(hex: "1B5E20"), // Dark Green
        Color(hex: "00BCD4"), // Cyan
        Color(hex: "006064"), // Dark Cyan

        // Row 4 - Warm Colors
        Color(hex: "FFF3E0"), // Light Orange
        Color(hex: "FF9800"), // Orange
        Color(hex: "E65100"), // Dark Orange
        Color(hex: "F44336"), // Red
        Color(hex: "B71C1C"), // Dark Red
    ]
}

// MARK: - Gradient Presets (20 curated gradients)
enum GradientPreset: String, CaseIterable {
    case oceanBlue = "Ocean Blue"
    case sunset = "Sunset"
    case forest = "Forest"
    case lavender = "Lavender"
    case coral = "Coral"
    case midnight = "Midnight"
    case aurora = "Aurora"
    case peach = "Peach"
    case mint = "Mint"
    case rose = "Rose"
    case sky = "Sky"
    case fire = "Fire"
    case grape = "Grape"
    case emerald = "Emerald"
    case golden = "Golden"
    case arctic = "Arctic"
    case berry = "Berry"
    case ocean = "Ocean"
    case dusk = "Dusk"
    case spring = "Spring"

    var colors: [Color] {
        switch self {
        case .oceanBlue: return [Color(hex: "667eea"), Color(hex: "764ba2")]
        case .sunset: return [Color(hex: "f093fb"), Color(hex: "f5576c")]
        case .forest: return [Color(hex: "11998e"), Color(hex: "38ef7d")]
        case .lavender: return [Color(hex: "a18cd1"), Color(hex: "fbc2eb")]
        case .coral: return [Color(hex: "ff9a9e"), Color(hex: "fecfef")]
        case .midnight: return [Color(hex: "232526"), Color(hex: "414345")]
        case .aurora: return [Color(hex: "00c6ff"), Color(hex: "0072ff")]
        case .peach: return [Color(hex: "ffecd2"), Color(hex: "fcb69f")]
        case .mint: return [Color(hex: "a8edea"), Color(hex: "fed6e3")]
        case .rose: return [Color(hex: "ff758c"), Color(hex: "ff7eb3")]
        case .sky: return [Color(hex: "89f7fe"), Color(hex: "66a6ff")]
        case .fire: return [Color(hex: "f12711"), Color(hex: "f5af19")]
        case .grape: return [Color(hex: "8e2de2"), Color(hex: "4a00e0")]
        case .emerald: return [Color(hex: "43cea2"), Color(hex: "185a9d")]
        case .golden: return [Color(hex: "f7971e"), Color(hex: "ffd200")]
        case .arctic: return [Color(hex: "c9d6ff"), Color(hex: "e2e2e2")]
        case .berry: return [Color(hex: "8360c3"), Color(hex: "2ebf91")]
        case .ocean: return [Color(hex: "2193b0"), Color(hex: "6dd5ed")]
        case .dusk: return [Color(hex: "2c3e50"), Color(hex: "fd746c")]
        case .spring: return [Color(hex: "c6ffdd"), Color(hex: "fbd786"), Color(hex: "f7797d")]
        }
    }

    func gradient(direction: GradientDirection) -> some ShapeStyle {
        if direction == .linear {
            return AnyShapeStyle(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
        } else {
            return AnyShapeStyle(RadialGradient(colors: colors, center: .center, startRadius: 0, endRadius: 400))
        }
    }
}

// MARK: - Color Hex Extension
extension Color {
    init(hex: String) {
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
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    func toHex() -> String {
        guard let components = NSColor(self).cgColor.components else { return "000000" }
        let r = Int(components[0] * 255)
        let g = Int(components.count > 1 ? components[1] * 255 : 0)
        let b = Int(components.count > 2 ? components[2] * 255 : 0)
        return String(format: "%02X%02X%02X", r, g, b)
    }
}

// MARK: - Checkerboard Pattern (for transparent preview)
struct CheckerboardPattern: View {
    let squareSize: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let rows = Int(ceil(size.height / squareSize))
                let cols = Int(ceil(size.width / squareSize))

                for row in 0..<rows {
                    for col in 0..<cols {
                        let isLight = (row + col) % 2 == 0
                        let rect = CGRect(
                            x: CGFloat(col) * squareSize,
                            y: CGFloat(row) * squareSize,
                            width: squareSize,
                            height: squareSize
                        )
                        context.fill(
                            Path(rect),
                            with: .color(isLight ? Color(white: 0.9) : Color(white: 0.7))
                        )
                    }
                }
            }
        }
    }
}
