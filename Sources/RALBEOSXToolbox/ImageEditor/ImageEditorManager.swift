import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers

/// A single markup annotation (rectangle/ellipse/line/arrow/pen stroke/text).
/// `points` are stored in "image space" - pixel coordinates with the origin
/// at the TOP-LEFT of the image, matching `CGImage.cropping(to:)` and
/// SwiftUI's own view coordinate system (verified empirically - see the
/// Y-flip note on `flattenMarkup()` for where this differs from Core Image).
struct MarkupElement: Identifiable {
    enum Tool: String, CaseIterable, Identifiable {
        case rectangle = "Rectangle", ellipse = "Ellipse", line = "Line", arrow = "Arrow", pen = "Pen", text = "Text"
        var id: String { rawValue }
    }

    let id = UUID()
    var tool: Tool
    var points: [CGPoint]
    var text: String = ""
    var color: NSColor
    var lineWidth: CGFloat
}

/// Which interactive tool a drag/click on the canvas should feed.
enum EditorMode: Equatable {
    case none
    case crop
    case selectArea
    case markup(MarkupElement.Tool)
}

/// Whether the Adjustments panel's sliders apply to the whole image or only
/// to a user-drawn rectangle (composited back over the untouched original).
enum AdjustmentScope: Equatable {
    case fullImage
    case selectedArea
}

/// A real, from-scratch image editor: crop/rotate/flip/resize, Core
/// Image-backed adjustments (brightness/contrast/saturation/exposure/
/// sharpness/whole-image blur) with live preview, a regional blur/redact
/// tool for quickly covering sensitive details, Markup-style annotations
/// (shapes/pen/text), undo/redo, and export. Filters/effects beyond the
/// ones listed (e.g. artistic/stylize filters, layers, selection-by-color)
/// are NOT implemented - kept to a real, working, non-destructive-where-
/// practical core rather than spreading thin.
@MainActor
final class ImageEditorManager: NSObject, ObservableObject {
    static let shared = ImageEditorManager()

    enum SaveFormat: String, CaseIterable, Identifiable {
        case png = "PNG", jpeg = "JPEG", tiff = "TIFF", heic = "HEIC"
        var id: String { rawValue }
        var bitmapFileType: NSBitmapImageRep.FileType? {
            switch self {
            case .png: return .png
            case .jpeg: return .jpeg
            case .tiff: return .tiff
            case .heic: return nil
            }
        }
        var utType: String { self == .heic ? "public.heic" : "" }
    }

    @Published private(set) var currentImage: CGImage?
    @Published private(set) var previewImage: CGImage?
    @Published private(set) var sourcePath: String?
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    /// Bumped on every image mutation so the canvas `Image` view (built
    /// from a raw `CGImage`) can be given a fresh `.id()` - SwiftUI doesn't
    /// reliably notice in-place pixel changes to the same CGImage/Image
    /// view identity otherwise.
    @Published private(set) var revision = 0

    @Published var mode: EditorMode = .none
    @Published var cropRect: CGRect?
    @Published var selectionRect: CGRect?
    @Published var adjustmentScope: AdjustmentScope = .fullImage {
        didSet {
            if adjustmentScope == .fullImage {
                selectionRect = nil
                if mode == .selectArea { mode = .none }
            }
            updatePreview()
        }
    }

    /// Transient gesture state, image-space coordinates - kept on the
    /// manager (not local view @State) per this project's established
    /// "@State can trigger a missing-macro-plugin crash on CLT-only
    /// toolchains" rule; see repo memory / v2.1 gotcha.
    @Published var dragStartPoint: CGPoint?
    @Published var dragCurrentPoint: CGPoint?
    @Published var penStrokePoints: [CGPoint] = []

    @Published var markupElements: [MarkupElement] = []
    @Published var markupColor: NSColor = .systemRed
    @Published var markupLineWidth: CGFloat = 4
    @Published var selectedMarkupTool: MarkupElement.Tool = .rectangle

    @Published var resizeWidthText: String = ""
    @Published var resizeHeightText: String = ""

    @Published var brightness: Double = 0 { didSet { updatePreview() } }   // -1...1, 0 = neutral
    @Published var contrast: Double = 1 { didSet { updatePreview() } }    // 0...4, 1 = neutral
    @Published var saturation: Double = 1 { didSet { updatePreview() } }  // 0...2, 1 = neutral
    @Published var exposure: Double = 0 { didSet { updatePreview() } }    // -2...2, 0 = neutral
    @Published var sharpness: Double = 0 { didSet { updatePreview() } }   // 0...2, 0 = neutral
    @Published var blurAmount: Double = 0 { didSet { updatePreview() } }  // 0...50 radius, 0 = neutral
    @Published var fillColor: NSColor = .systemRed

    @Published var saveFormat: SaveFormat = .png
    @Published var lastSavedPath: String?
    @Published var lastError: String?

    private var undoStack: [CGImage] = []
    private var redoStack: [CGImage] = []
    private let ciContext = CIContext()

    private override init() { super.init() }

    var hasImage: Bool { currentImage != nil }
    var displayImage: CGImage? { previewImage ?? currentImage }
    var hasAdjustments: Bool { brightness != 0 || contrast != 1 || saturation != 1 || exposure != 0 || sharpness != 0 || blurAmount != 0 }
    var imagePixelSize: CGSize {
        guard let image = currentImage else { return .zero }
        return CGSize(width: image.width, height: image.height)
    }

    // MARK: Import

    func openImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let nsImage = NSImage(contentsOf: url), let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            lastError = "Could not read that image."
            return
        }
        load(cgImage, sourcePath: url.path)
    }

    func pasteFromClipboard() {
        let pb = NSPasteboard.general
        let data = pb.data(forType: .tiff) ?? pb.data(forType: .png)
        guard let data, let rep = NSBitmapImageRep(data: data), let cgImage = rep.cgImage else {
            lastError = "No image found on the clipboard."
            return
        }
        load(cgImage, sourcePath: nil)
    }

    private func load(_ image: CGImage, sourcePath: String?) {
        currentImage = image
        self.sourcePath = sourcePath
        undoStack.removeAll()
        redoStack.removeAll()
        markupElements.removeAll()
        cropRect = nil
        selectionRect = nil
        adjustmentScope = .fullImage
        mode = .none
        lastError = nil
        lastSavedPath = nil
        resetAdjustmentSliders(updatingPreview: false)
        updateUndoRedoFlags()
        revision += 1
    }

    /// Clears the editor session without deleting the source image on disk.
    func removeImage() {
        currentImage = nil
        previewImage = nil
        sourcePath = nil
        undoStack.removeAll()
        redoStack.removeAll()
        markupElements.removeAll()
        cropRect = nil
        selectionRect = nil
        adjustmentScope = .fullImage
        mode = .none
        dragStartPoint = nil
        dragCurrentPoint = nil
        penStrokePoints.removeAll()
        resizeWidthText = ""
        resizeHeightText = ""
        resetAdjustmentSliders(updatingPreview: false)
        lastSavedPath = nil
        lastError = nil
        updateUndoRedoFlags()
        revision += 1
    }

    // MARK: Undo / Redo

    private func commit(_ newImage: CGImage) {
        if let current = currentImage { undoStack.append(current) }
        redoStack.removeAll()
        currentImage = newImage
        updateUndoRedoFlags()
        revision += 1
    }

    func undo() {
        guard let previous = undoStack.popLast(), let current = currentImage else { return }
        redoStack.append(current)
        currentImage = previous
        updateUndoRedoFlags()
        revision += 1
    }

    func redo() {
        guard let next = redoStack.popLast(), let current = currentImage else { return }
        undoStack.append(current)
        currentImage = next
        updateUndoRedoFlags()
        revision += 1
    }

    private func updateUndoRedoFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    // MARK: Rotate / Flip / Resize

    func rotateLeft() { rotate(clockwise: false) }
    func rotateRight() { rotate(clockwise: true) }

    private func rotate(clockwise: Bool) {
        guard let image = currentImage else { return }
        let w = image.width, h = image.height
        guard let context = CGContext(data: nil, width: h, height: w, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.translateBy(x: CGFloat(h) / 2, y: CGFloat(w) / 2)
        context.rotate(by: clockwise ? -.pi / 2 : .pi / 2)
        context.translateBy(x: -CGFloat(w) / 2, y: -CGFloat(h) / 2)
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let rotated = context.makeImage() else { return }
        commit(rotated)
    }

    func flipHorizontal() { flip(horizontal: true) }
    func flipVertical() { flip(horizontal: false) }

    private func flip(horizontal: Bool) {
        guard let image = currentImage else { return }
        let w = image.width, h = image.height
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        if horizontal {
            context.translateBy(x: CGFloat(w), y: 0)
            context.scaleBy(x: -1, y: 1)
        } else {
            context.translateBy(x: 0, y: CGFloat(h))
            context.scaleBy(x: 1, y: -1)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let flipped = context.makeImage() else { return }
        commit(flipped)
    }

    func applyResize(width: Int, height: Int) {
        guard let image = currentImage, width > 0, height > 0 else { return }
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let resized = context.makeImage() else { return }
        commit(resized)
    }

    func applyResizeFromTextFields() {
        guard let width = Int(resizeWidthText), let height = Int(resizeHeightText) else { return }
        applyResize(width: width, height: height)
        resizeWidthText = ""
        resizeHeightText = ""
    }

    // MARK: Crop

    /// `cropRect` is top-left-origin image-space, same convention as
    /// `CGImage.cropping(to:)` itself (verified empirically) - no flip needed.
    func applyCrop() {
        guard let image = currentImage, let rect = cropRect, rect.width >= 2, rect.height >= 2 else { return }
        let clamped = rect.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !clamped.isEmpty, let cropped = image.cropping(to: clamped) else { return }
        commit(cropped)
        cropRect = nil
        mode = .none
    }

    func cancelCrop() {
        cropRect = nil
        mode = .none
    }

    func cancelAreaSelection() {
        selectionRect = nil
        mode = .none
        updatePreview()
    }

    // MARK: Adjustments (live preview, explicit commit)

    /// Builds the adjusted Core Image pipeline from the current sliders,
    /// then - for "Selected Area" scope - composites it back over the
    /// untouched original everywhere outside the selected rect (Core
    /// Image's coordinate space is bottom-left/Cartesian, verified
    /// empirically, so the rect's Y is flipped here).
    private func updatePreview() {
        guard let base = currentImage else { previewImage = nil; return }
        guard hasAdjustments else { previewImage = nil; return }
        if adjustmentScope == .selectedArea && selectionRect == nil { previewImage = nil; return }

        let extent = CGRect(x: 0, y: 0, width: base.width, height: base.height)
        let baseCI = CIImage(cgImage: base)
        var ci = baseCI

        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = ci
        colorControls.brightness = Float(brightness)
        colorControls.contrast = Float(contrast)
        colorControls.saturation = Float(saturation)
        ci = colorControls.outputImage ?? ci

        if exposure != 0 {
            let exposureFilter = CIFilter.exposureAdjust()
            exposureFilter.inputImage = ci
            exposureFilter.ev = Float(exposure)
            ci = exposureFilter.outputImage ?? ci
        }
        if sharpness != 0 {
            let sharpen = CIFilter.sharpenLuminance()
            sharpen.inputImage = ci
            sharpen.sharpness = Float(sharpness)
            ci = sharpen.outputImage ?? ci
        }
        if blurAmount > 0 {
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = ci
            blur.radius = Float(blurAmount)
            ci = (blur.outputImage ?? ci).cropped(to: extent)
        }

        guard adjustmentScope == .selectedArea, let rect = selectionRect else {
            previewImage = ciContext.createCGImage(ci, from: extent)
            return
        }

        let ciRect = CGRect(x: rect.minX, y: CGFloat(base.height) - rect.maxY, width: rect.width, height: rect.height)
        let mask = CIImage(color: .white).cropped(to: ciRect).composited(over: CIImage(color: .black).cropped(to: extent))
        let blend = CIFilter.blendWithMask()
        blend.inputImage = ci
        blend.backgroundImage = baseCI
        blend.maskImage = mask
        previewImage = blend.outputImage.flatMap { ciContext.createCGImage($0, from: extent) }
    }

    func applyAdjustments() {
        guard let preview = previewImage else { return }
        commit(preview)
        resetAdjustmentSliders(updatingPreview: true)
    }

    func resetAdjustmentSliders(updatingPreview: Bool = true) {
        brightness = 0; contrast = 1; saturation = 1; exposure = 0; sharpness = 0; blurAmount = 0
        if updatingPreview { previewImage = nil }
    }

    /// Permanently fills the selected rectangle with the chosen colour.
    /// Selection coordinates are top-left-origin, so the Y value is flipped
    /// before creating Core Image's bottom-left-origin mask.
    func fillSelection() {
        guard let base = currentImage, let rect = selectionRect else { return }
        let extent = CGRect(x: 0, y: 0, width: base.width, height: base.height)
        let selectedRect = rect.intersection(extent)
        guard !selectedRect.isEmpty else { return }
        guard let ciColor = CIColor(color: fillColor) else { return }

        let ciRect = CGRect(
            x: selectedRect.minX,
            y: CGFloat(base.height) - selectedRect.maxY,
            width: selectedRect.width,
            height: selectedRect.height
        )
        let mask = CIImage(color: .white)
            .cropped(to: ciRect)
            .composited(over: CIImage(color: .black).cropped(to: extent))
        let blend = CIFilter.blendWithMask()
        blend.inputImage = CIImage(color: ciColor).cropped(to: extent)
        blend.backgroundImage = CIImage(cgImage: base)
        blend.maskImage = mask
        guard let output = blend.outputImage,
              let filled = ciContext.createCGImage(output, from: extent) else { return }
        commit(filled)
    }

    // MARK: Markup

    func beginDrag(at point: CGPoint) {
        if case .markup(.pen) = mode {
            penStrokePoints = [point]
        } else {
            dragStartPoint = point
            dragCurrentPoint = point
        }
    }

    func updateDrag(to point: CGPoint) {
        if case .markup(.pen) = mode {
            penStrokePoints.append(point)
        } else {
            dragCurrentPoint = point
        }
    }

    func endDrag() {
        defer {
            dragStartPoint = nil
            dragCurrentPoint = nil
            penStrokePoints = []
        }
        switch mode {
        case .crop:
            guard let start = dragStartPoint, let end = dragCurrentPoint else { return }
            cropRect = Self.normalizedRect(start, end)
        case .selectArea:
            guard let start = dragStartPoint, let end = dragCurrentPoint else { return }
            selectionRect = Self.normalizedRect(start, end)
            updatePreview()
        case .markup(.pen):
            addMarkupElement(tool: .pen, points: penStrokePoints)
        case .markup(.text):
            guard let start = dragStartPoint else { return }
            addMarkupElement(tool: .text, points: [start])
        case .markup(let tool):
            guard let start = dragStartPoint, let end = dragCurrentPoint else { return }
            addMarkupElement(tool: tool, points: [start, end])
        case .none:
            break
        }
    }

    private static func normalizedRect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    func addMarkupElement(tool: MarkupElement.Tool, points: [CGPoint]) {
        guard !points.isEmpty else { return }
        if tool == .text {
            guard let text = promptForText("Add Text", "Enter the label to place on the image:", "") , !text.isEmpty else { return }
            markupElements.append(MarkupElement(tool: .text, points: points, text: text, color: markupColor, lineWidth: markupLineWidth))
        } else {
            markupElements.append(MarkupElement(tool: tool, points: points, color: markupColor, lineWidth: markupLineWidth))
        }
    }

    func removeLastMarkupElement() {
        _ = markupElements.popLast()
    }

    func clearMarkup() {
        markupElements.removeAll()
    }

    /// Rasterizes every markup element permanently into the image. Markup
    /// points are top-left-origin image-space; CGContext drawing (fill/
    /// stroke) is bottom-left/Cartesian (verified empirically), so each
    /// point's Y is flipped before it's used to build a path.
    func flattenMarkup() {
        guard let image = currentImage, !markupElements.isEmpty else { return }
        let w = image.width, h = image.height
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        func flip(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: CGFloat(h) - p.y) }

        for element in markupElements {
            context.setStrokeColor(element.color.cgColor)
            context.setFillColor(element.color.cgColor)
            context.setLineWidth(element.lineWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            let flipped = element.points.map(flip)

            switch element.tool {
            case .rectangle:
                guard flipped.count >= 2 else { continue }
                context.stroke(CGRect(x: min(flipped[0].x, flipped[1].x), y: min(flipped[0].y, flipped[1].y), width: abs(flipped[1].x - flipped[0].x), height: abs(flipped[1].y - flipped[0].y)))
            case .ellipse:
                guard flipped.count >= 2 else { continue }
                context.strokeEllipse(in: CGRect(x: min(flipped[0].x, flipped[1].x), y: min(flipped[0].y, flipped[1].y), width: abs(flipped[1].x - flipped[0].x), height: abs(flipped[1].y - flipped[0].y)))
            case .line:
                guard flipped.count >= 2 else { continue }
                context.move(to: flipped[0])
                context.addLine(to: flipped[1])
                context.strokePath()
            case .arrow:
                guard flipped.count >= 2 else { continue }
                drawArrow(in: context, from: flipped[0], to: flipped[1], lineWidth: element.lineWidth)
            case .pen:
                guard flipped.count >= 2 else { continue }
                context.move(to: flipped[0])
                for point in flipped.dropFirst() { context.addLine(to: point) }
                context.strokePath()
            case .text:
                guard let point = flipped.first else { continue }
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.boldSystemFont(ofSize: max(12, element.lineWidth * 6)),
                    .foregroundColor: element.color
                ]
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
                (element.text as NSString).draw(at: point, withAttributes: attributes)
                NSGraphicsContext.restoreGraphicsState()
            }
        }

        guard let flattened = context.makeImage() else { return }
        commit(flattened)
        markupElements.removeAll()
        mode = .none
    }

    private func drawArrow(in context: CGContext, from start: CGPoint, to end: CGPoint, lineWidth: CGFloat) {
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = max(10, lineWidth * 4)
        let headAngle = CGFloat.pi / 7
        let p1 = CGPoint(x: end.x - headLength * cos(angle - headAngle), y: end.y - headLength * sin(angle - headAngle))
        let p2 = CGPoint(x: end.x - headLength * cos(angle + headAngle), y: end.y - headLength * sin(angle + headAngle))
        context.move(to: end)
        context.addLine(to: p1)
        context.move(to: end)
        context.addLine(to: p2)
        context.strokePath()
    }

    private func promptForText(_ title: String, _ message: String, _ defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = defaultValue
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    // MARK: Export

    func saveAs() {
        guard let image = currentImage else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = ((sourcePath.map { ($0 as NSString).lastPathComponent }) ?? "Untitled") + "." + saveFormat.rawValue.lowercased()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        write(image, to: url.path)
    }

    func overwriteOriginal() {
        guard let image = currentImage, let path = sourcePath else { return }
        write(image, to: path)
    }

    private func write(_ image: CGImage, to path: String) {
        lastError = nil
        if saveFormat == .heic {
            guard let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.heic" as CFString, 1, nil) else {
                lastError = "HEIC export is not supported on this system."
                return
            }
            CGImageDestinationAddImage(dest, image, nil)
            guard CGImageDestinationFinalize(dest) else { lastError = "HEIC export failed."; return }
            lastSavedPath = path
            return
        }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let fileType = saveFormat.bitmapFileType, let data = rep.representation(using: fileType, properties: [:]) else {
            lastError = "Export failed."
            return
        }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            lastSavedPath = path
        } catch {
            lastError = error.localizedDescription
        }
    }

    func copyToClipboard() {
        guard let image = currentImage else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))])
    }

    func revealLastSaved() {
        guard let path = lastSavedPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
