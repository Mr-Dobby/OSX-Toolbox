import AppKit
@preconcurrency import Vision

/// Wraps the built-in `screencapture` CLI for capture/record, plus Vision
/// for OCR and a simple resize/compress helper. Annotation, blur/redact,
/// format conversion, and GIF export from the original feature list are NOT
/// implemented in this pass (kept the core capture/OCR/resize workflow
/// working well instead of spreading thin).
@MainActor
final class ScreenshotToolboxManager: ObservableObject {
    static let shared = ScreenshotToolboxManager()

    @Published var lastCapturePath: String?
    @Published var ocrResult = ""
    @Published var isBusy = false

    private init() {}

    func captureFullScreen(toClipboard: Bool) { capture(interactive: false, extraArgs: [], toClipboard: toClipboard) }
    func captureWindow(toClipboard: Bool) { capture(interactive: true, extraArgs: ["-w"], toClipboard: toClipboard) }
    func captureArea(toClipboard: Bool) { capture(interactive: true, extraArgs: ["-s"], toClipboard: toClipboard) }

    private func capture(interactive: Bool, extraArgs: [String], toClipboard: Bool) {
        var args = extraArgs
        var outputPath: String?
        if toClipboard {
            args.append("-c")
        } else {
            let path = NSTemporaryDirectory() + "toolbox-capture-\(Int(Date().timeIntervalSince1970)).png"
            args.append(path)
            outputPath = path
        }
        runAsync("/usr/sbin/screencapture", args) { [weak self] in
            if let outputPath { self?.lastCapturePath = outputPath }
        }
    }

    func recordScreen() {
        let path = NSTemporaryDirectory() + "toolbox-recording-\(Int(Date().timeIntervalSince1970)).mov"
        runAsync("/usr/sbin/screencapture", ["-v", path]) { [weak self] in
            self?.lastCapturePath = path
        }
    }

    private func runAsync(_ path: String, _ args: [String], completion: (() -> Void)? = nil) {
        isBusy = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = caffeineShell(path, args)
            Task { @MainActor in
                self?.isBusy = false
                completion?()
            }
        }
    }

    func revealLastCapture() {
        guard let path = lastCapturePath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func runOCROnLastCapture() {
        guard let path = lastCapturePath,
              let image = NSImage(contentsOfFile: path),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        isBusy = true
        let request = VNRecognizeTextRequest { [weak self] request, _ in
            let text = (request.results as? [VNRecognizedTextObservation])?
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n") ?? ""
            Task { @MainActor in
                self?.ocrResult = text
                self?.isBusy = false
            }
        }
        request.recognitionLevel = .accurate
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            try? handler.perform([request])
        }
    }

    func resizeLastCapture(maxDimension: CGFloat) {
        guard let path = lastCapturePath, let image = NSImage(contentsOfFile: path) else { return }
        let scale = min(1.0, maxDimension / max(image.size.width, image.size.height))
        let newSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1)
        newImage.unlockFocus()
        guard let tiff = newImage.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else { return }
        let outPath = (path as NSString).deletingPathExtension + "-resized.jpg"
        try? data.write(to: URL(fileURLWithPath: outPath))
        lastCapturePath = outPath
    }
}
