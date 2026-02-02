import SwiftUI
import AppKit

struct AreaSelectionView: View {
    let onComplete: (CGRect) -> Void
    let onCancel: () -> Void

    @State private var startPoint: CGPoint?
    @State private var currentPoint: CGPoint?
    @State private var isDragging = false
    @State private var mouseLocation: CGPoint = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Mouse tracking layer (must be first to receive events)
                MouseTrackingView(
                    onMouseMove: { location in
                        mouseLocation = location
                    },
                    onMouseDown: { location in
                        startPoint = location
                        currentPoint = location
                        isDragging = true
                    },
                    onMouseDragged: { location in
                        currentPoint = location
                    },
                    onMouseUp: { location in
                        if let start = startPoint {
                            let rect = selectionRect(from: start, to: location)
                            if rect.width > 10 && rect.height > 10 {
                                onComplete(rect)
                            } else {
                                // Too small, cancel
                                onCancel()
                            }
                        }
                        isDragging = false
                    },
                    onEscape: {
                        onCancel()
                    }
                )

                // Semi-transparent overlay
                Color.black.opacity(0.3)
                    .allowsHitTesting(false)

                // Selection rectangle
                if let start = startPoint, let current = currentPoint {
                    let rect = selectionRect(from: start, to: current)

                    // Clear hole in overlay
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .blendMode(.destinationOut)
                        .allowsHitTesting(false)

                    // Selection border
                    SelectionBorder(rect: rect)
                        .allowsHitTesting(false)

                    // Dimension label
                    DimensionLabel(rect: rect)
                        .allowsHitTesting(false)
                }

                // Crosshair when not dragging
                if !isDragging {
                    CrosshairView(position: mouseLocation, size: geometry.size)
                        .allowsHitTesting(false)
                }

                // Instructions
                if !isDragging {
                    VStack {
                        InstructionBadge(text: "areaSelection.instruction".localized)
                            .padding(.top, 60)
                        Spacer()
                    }
                    .allowsHitTesting(false)
                }
            }
            .compositingGroup()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
    }

    private func selectionRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        let x = min(start.x, end.x)
        let y = min(start.y, end.y)
        let width = abs(end.x - start.x)
        let height = abs(end.y - start.y)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

// MARK: - Selection Border
struct SelectionBorder: View {
    let rect: CGRect

    var body: some View {
        ZStack {
            // Main border
            Rectangle()
                .stroke(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            // Corner handles
            ForEach(corners, id: \.0) { corner in
                Circle()
                    .fill(Color.white)
                    .frame(width: 8, height: 8)
                    .shadow(color: .black.opacity(0.3), radius: 2)
                    .position(corner.1)
            }
        }
    }

    private var corners: [(String, CGPoint)] {
        [
            ("tl", CGPoint(x: rect.minX, y: rect.minY)),
            ("tr", CGPoint(x: rect.maxX, y: rect.minY)),
            ("bl", CGPoint(x: rect.minX, y: rect.maxY)),
            ("br", CGPoint(x: rect.maxX, y: rect.maxY))
        ]
    }
}

// MARK: - Dimension Label
struct DimensionLabel: View {
    let rect: CGRect

    var body: some View {
        Text("\(Int(rect.width)) × \(Int(rect.height))")
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.7))
            )
            .position(x: rect.midX, y: rect.maxY + 25)
    }
}

// MARK: - Crosshair View
struct CrosshairView: View {
    let position: CGPoint
    let size: CGSize

    var body: some View {
        ZStack {
            // Horizontal line
            Rectangle()
                .fill(Color.white.opacity(0.5))
                .frame(width: size.width, height: 1)
                .position(x: size.width / 2, y: position.y)

            // Vertical line
            Rectangle()
                .fill(Color.white.opacity(0.5))
                .frame(width: 1, height: size.height)
                .position(x: position.x, y: size.height / 2)

            // Center crosshair
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: 20, height: 20)

                Rectangle()
                    .fill(Color.white)
                    .frame(width: 1, height: 12)

                Rectangle()
                    .fill(Color.white)
                    .frame(width: 12, height: 1)
            }
            .position(position)
        }
    }
}

// MARK: - Instruction Badge
struct InstructionBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.6))
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
    }
}

// MARK: - Mouse Tracking NSView
struct MouseTrackingView: NSViewRepresentable {
    let onMouseMove: (CGPoint) -> Void
    let onMouseDown: (CGPoint) -> Void
    let onMouseDragged: (CGPoint) -> Void
    let onMouseUp: (CGPoint) -> Void
    let onEscape: () -> Void

    func makeNSView(context: Context) -> MouseTrackingNSView {
        let view = MouseTrackingNSView()
        view.onMouseMove = onMouseMove
        view.onMouseDown = onMouseDown
        view.onMouseDragged = onMouseDragged
        view.onMouseUp = onMouseUp
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ nsView: MouseTrackingNSView, context: Context) {}
}

class MouseTrackingNSView: NSView {
    var onMouseMove: ((CGPoint) -> Void)?
    var onMouseDown: ((CGPoint) -> Void)?
    var onMouseDragged: ((CGPoint) -> Void)?
    var onMouseUp: ((CGPoint) -> Void)?
    var onEscape: (() -> Void)?

    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    // Accept mouse events even when window is not key (fixes first click issue)
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true  // Accept first click even if window is not key
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
        // Make this view the first responder immediately
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let window = self.window else { return }
            window.makeFirstResponder(self)
            window.makeKey()
        }
    }

    override func becomeFirstResponder() -> Bool {
        return true
    }

    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let flippedY = bounds.height - location.y
        onMouseMove?(CGPoint(x: location.x, y: flippedY))
    }

    override func mouseDown(with event: NSEvent) {
        // Ensure we're first responder on click
        if window?.firstResponder != self {
            window?.makeFirstResponder(self)
        }
        let location = convert(event.locationInWindow, from: nil)
        let flippedY = bounds.height - location.y
        onMouseDown?(CGPoint(x: location.x, y: flippedY))
    }

    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let flippedY = bounds.height - location.y
        onMouseDragged?(CGPoint(x: location.x, y: flippedY))
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let flippedY = bounds.height - location.y
        onMouseUp?(CGPoint(x: location.x, y: flippedY))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC key
            onEscape?()
            // Don't call super - consume the event to prevent app termination
        } else {
            super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 53 { // ESC key
            onEscape?()
            return true // Event handled
        }
        return super.performKeyEquivalent(with: event)
    }
}
