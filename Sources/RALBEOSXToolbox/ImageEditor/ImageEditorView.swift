import SwiftUI

struct ImageEditorView: View {
    @ObservedObject var manager: ImageEditorManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if manager.hasImage {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        canvas
                        transformsSection
                        adjustmentsSection
                        markupSection
                        exportSection
                    }
                }
            } else {
                emptyState
            }
            if let error = manager.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Header / empty state

    private var header: some View {
        HStack {
            Text("Image Editor").font(.title2).bold()
            Spacer()
            Button("Open Image…") { manager.openImage() }
            Button("Paste from Clipboard") { manager.pasteFromClipboard() }
            if manager.hasImage {
                Button("Undo") { manager.undo() }.disabled(!manager.canUndo)
                Button("Redo") { manager.redo() }.disabled(!manager.canRedo)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("Open an image or paste one from the clipboard to get started.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Canvas

    private var canvas: some View {
        GeometryReader { geo in
            let imageSize = manager.imagePixelSize
            let scale = imageSize.width > 0 && imageSize.height > 0
                ? min(geo.size.width / imageSize.width, geo.size.height / imageSize.height)
                : 1
            let displaySize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
            let origin = CGPoint(x: (geo.size.width - displaySize.width) / 2, y: (geo.size.height - displaySize.height) / 2)

            ZStack {
                if let cg = manager.displayImage {
                    Image(decorative: cg, scale: 1)
                        .resizable()
                        .frame(width: displaySize.width, height: displaySize.height)
                        .id(manager.revision)
                }
                overlay(scale: scale, origin: origin)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(dragGesture(scale: scale, origin: origin, imageSize: imageSize))
        }
        .frame(minHeight: 320, maxHeight: 480)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private func overlay(scale: CGFloat, origin: CGPoint) -> some View {
        Canvas { context, _ in
            func toView(_ p: CGPoint) -> CGPoint { CGPoint(x: origin.x + p.x * scale, y: origin.y + p.y * scale) }

            for element in manager.markupElements {
                draw(element: element, context: context, toView: toView)
            }

            if case .markup(let tool) = manager.mode {
                if tool == .pen, manager.penStrokePoints.count > 1 {
                    let preview = MarkupElement(tool: .pen, points: manager.penStrokePoints, color: manager.markupColor, lineWidth: manager.markupLineWidth)
                    draw(element: preview, context: context, toView: toView)
                } else if tool != .pen, tool != .text, let start = manager.dragStartPoint, let end = manager.dragCurrentPoint {
                    let preview = MarkupElement(tool: tool, points: [start, end], color: manager.markupColor, lineWidth: manager.markupLineWidth)
                    draw(element: preview, context: context, toView: toView)
                }
            }

            if manager.mode == .crop || manager.mode == .selectArea {
                let liveRect: CGRect?
                if let start = manager.dragStartPoint, let end = manager.dragCurrentPoint {
                    liveRect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
                } else {
                    liveRect = manager.mode == .crop ? manager.cropRect : manager.selectionRect
                }
                if let rect = liveRect {
                    let viewRect = CGRect(origin: toView(rect.origin), size: CGSize(width: rect.width * scale, height: rect.height * scale))
                    context.fill(Path(viewRect), with: .color(.yellow.opacity(0.15)))
                    context.stroke(Path(viewRect), with: .color(.yellow), lineWidth: 2)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(element: MarkupElement, context: GraphicsContext, toView: (CGPoint) -> CGPoint) {
        if element.tool == .text, let point = element.points.first {
            context.draw(
                Text(element.text).font(.system(size: max(12, element.lineWidth * 6), weight: .bold)).foregroundColor(Color(nsColor: element.color)),
                at: toView(point), anchor: .topLeading
            )
            return
        }
        context.stroke(path(for: element, toView: toView), with: .color(Color(nsColor: element.color)), lineWidth: element.lineWidth)
    }

    private func path(for element: MarkupElement, toView: (CGPoint) -> CGPoint) -> Path {
        var path = Path()
        let pts = element.points.map(toView)
        switch element.tool {
        case .rectangle:
            guard pts.count >= 2 else { return path }
            path.addRect(CGRect(x: min(pts[0].x, pts[1].x), y: min(pts[0].y, pts[1].y), width: abs(pts[1].x - pts[0].x), height: abs(pts[1].y - pts[0].y)))
        case .ellipse:
            guard pts.count >= 2 else { return path }
            path.addEllipse(in: CGRect(x: min(pts[0].x, pts[1].x), y: min(pts[0].y, pts[1].y), width: abs(pts[1].x - pts[0].x), height: abs(pts[1].y - pts[0].y)))
        case .line:
            guard pts.count >= 2 else { return path }
            path.move(to: pts[0]); path.addLine(to: pts[1])
        case .arrow:
            guard pts.count >= 2 else { return path }
            path.move(to: pts[0]); path.addLine(to: pts[1])
            let angle = atan2(pts[1].y - pts[0].y, pts[1].x - pts[0].x)
            let headLength: CGFloat = max(10, element.lineWidth * 4)
            let headAngle = CGFloat.pi / 7
            let p1 = CGPoint(x: pts[1].x - headLength * cos(angle - headAngle), y: pts[1].y - headLength * sin(angle - headAngle))
            let p2 = CGPoint(x: pts[1].x - headLength * cos(angle + headAngle), y: pts[1].y - headLength * sin(angle + headAngle))
            path.move(to: pts[1]); path.addLine(to: p1)
            path.move(to: pts[1]); path.addLine(to: p2)
        case .pen:
            guard let first = pts.first else { return path }
            path.move(to: first)
            for p in pts.dropFirst() { path.addLine(to: p) }
        case .text:
            break
        }
        return path
    }

    private func dragGesture(scale: CGFloat, origin: CGPoint, imageSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard manager.mode != .none, scale > 0 else { return }
                let point = imagePoint(from: value.location, origin: origin, scale: scale, imageSize: imageSize)
                if manager.dragStartPoint == nil && manager.penStrokePoints.isEmpty {
                    manager.beginDrag(at: point)
                } else {
                    manager.updateDrag(to: point)
                }
            }
            .onEnded { _ in
                guard manager.mode != .none else { return }
                manager.endDrag()
            }
    }

    private func imagePoint(from viewPoint: CGPoint, origin: CGPoint, scale: CGFloat, imageSize: CGSize) -> CGPoint {
        let x = (viewPoint.x - origin.x) / scale
        let y = (viewPoint.y - origin.y) / scale
        return CGPoint(x: min(max(x, 0), imageSize.width), y: min(max(y, 0), imageSize.height))
    }

    // MARK: Transforms (rotate/flip/resize/crop)

    private var transformsSection: some View {
        GroupBox("Transform") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button("Rotate Left") { manager.rotateLeft() }
                    Button("Rotate Right") { manager.rotateRight() }
                    Button("Flip Horizontal") { manager.flipHorizontal() }
                    Button("Flip Vertical") { manager.flipVertical() }
                }
                HStack {
                    Button(manager.mode == .crop ? "Cancel Crop" : "Crop…") {
                        if manager.mode == .crop { manager.cancelCrop() } else { manager.mode = .crop }
                    }
                    if manager.mode == .crop {
                        Text("Drag a rectangle on the image, then Apply.").font(.caption).foregroundStyle(.secondary)
                        if manager.cropRect != nil {
                            Button("Apply Crop") { manager.applyCrop() }.buttonStyle(.borderedProminent)
                        }
                    }
                }
                HStack {
                    Text("Resize to:")
                    TextField("Width", text: $manager.resizeWidthText).frame(width: 70).textFieldStyle(.roundedBorder)
                    Text("×")
                    TextField("Height", text: $manager.resizeHeightText).frame(width: 70).textFieldStyle(.roundedBorder)
                    Button("Apply Resize") { manager.applyResizeFromTextFields() }
                        .disabled(Int(manager.resizeWidthText) == nil || Int(manager.resizeHeightText) == nil)
                    Text("Current: \(Int(manager.imagePixelSize.width))×\(Int(manager.imagePixelSize.height))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(4)
        }
    }

    // MARK: Adjustments

    private var adjustmentsSection: some View {
        GroupBox("Adjustments") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Apply to", selection: $manager.adjustmentScope) {
                    Text("Full Image").tag(AdjustmentScope.fullImage)
                    Text("Selected Area").tag(AdjustmentScope.selectedArea)
                }
                .pickerStyle(.segmented)
                .frame(width: 260)

                if manager.adjustmentScope == .selectedArea {
                    HStack {
                        Button(manager.mode == .selectArea ? "Cancel Drawing" : (manager.selectionRect == nil ? "Select Area…" : "Redraw Area…")) {
                            manager.mode = manager.mode == .selectArea ? .none : .selectArea
                        }
                        if manager.selectionRect != nil {
                            Button("Clear Selection") { manager.cancelAreaSelection() }
                        }
                        Text(manager.selectionRect == nil ? "Drag a rectangle on the image above." : "Adjust the sliders below, then Apply - only the selected area changes.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                slider("Brightness", value: $manager.brightness, range: -1...1)
                slider("Contrast", value: $manager.contrast, range: 0...4)
                slider("Saturation", value: $manager.saturation, range: 0...2)
                slider("Exposure", value: $manager.exposure, range: -2...2)
                slider("Sharpness", value: $manager.sharpness, range: 0...2)
                slider("Blur", value: $manager.blurAmount, range: 0...50)
                HStack {
                    Button("Apply Adjustments") { manager.applyAdjustments() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!manager.hasAdjustments || (manager.adjustmentScope == .selectedArea && manager.selectionRect == nil))
                    Button("Reset Sliders") { manager.resetAdjustmentSliders() }
                        .disabled(!manager.hasAdjustments)
                }
                if manager.adjustmentScope == .selectedArea {
                    Text("After you Apply, the selection clears and sliders reset automatically - ready to pick another area right away.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(4)
        }
    }

    private func slider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(label).frame(width: 80, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: "%.2f", value.wrappedValue)).font(.caption).foregroundStyle(.secondary).frame(width: 40)
        }
    }

    // MARK: Markup

    private var markupSection: some View {
        GroupBox("Markup") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Picker("Tool", selection: markupToolBinding) {
                        ForEach(MarkupElement.Tool.allCases) { tool in Text(tool.rawValue).tag(tool) }
                    }
                    .frame(width: 200)
                    ColorPicker("Color", selection: markupColorBinding)
                    Text("Width")
                    Slider(value: $manager.markupLineWidth, in: 1...20).frame(width: 100)
                    Button(isMarkupModeActive ? "Exit Markup Mode" : "Enter Markup Mode") {
                        manager.mode = isMarkupModeActive ? .none : .markup(manager.selectedMarkupTool)
                    }
                }
                if isMarkupModeActive {
                    Text(helpText(for: manager.selectedMarkupTool))
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Undo Last Element") { manager.removeLastMarkupElement() }
                        .disabled(manager.markupElements.isEmpty)
                    Button("Clear Markup") { manager.clearMarkup() }
                        .disabled(manager.markupElements.isEmpty)
                    Button("Flatten into Image") { manager.flattenMarkup() }
                        .buttonStyle(.borderedProminent)
                        .disabled(manager.markupElements.isEmpty)
                }
            }
            .padding(4)
        }
    }

    private var isMarkupModeActive: Bool {
        if case .markup = manager.mode { return true }
        return false
    }

    private func helpText(for tool: MarkupElement.Tool) -> String {
        switch tool {
        case .pen: return "Drag on the image to draw freehand."
        case .text: return "Click on the image to place a text label."
        default: return "Drag on the image to draw a \(tool.rawValue.lowercased())."
        }
    }

    private var markupToolBinding: Binding<MarkupElement.Tool> {
        Binding(
            get: {
                if case .markup(let tool) = manager.mode { return tool }
                return manager.selectedMarkupTool
            },
            set: { newTool in
                manager.selectedMarkupTool = newTool
                if isMarkupModeActive { manager.mode = .markup(newTool) }
            }
        )
    }

    private var markupColorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: manager.markupColor) },
            set: { manager.markupColor = NSColor($0) }
        )
    }

    // MARK: Export

    private var exportSection: some View {
        GroupBox("Export") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Picker("Format", selection: $manager.saveFormat) {
                        ForEach(ImageEditorManager.SaveFormat.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .frame(width: 160)
                    Button("Save As…") { manager.saveAs() }
                    if manager.sourcePath != nil {
                        Button("Overwrite Original") { manager.overwriteOriginal() }
                    }
                    Button("Copy to Clipboard") { manager.copyToClipboard() }
                    if manager.lastSavedPath != nil {
                        Button("Reveal") { manager.revealLastSaved() }
                    }
                }
                if let saved = manager.lastSavedPath {
                    Text("Saved to \(saved)").font(.caption).foregroundStyle(.green)
                }
            }
            .padding(4)
        }
    }
}
