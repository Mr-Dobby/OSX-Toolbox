import AppKit
import PDFKit
import ImageIO
import UniformTypeIdentifiers

/// Drag-and-drop-free (file-picker based) conversion utility: image format
/// conversion, images->PDF, PDF->images. Audio/video conversion from the
/// original feature list is NOT implemented (would need AVAssetExportSession
/// plumbing and real media test assets to validate - left out rather than
/// shipped untested).
@MainActor
final class FileConversionManager: ObservableObject {
    static let shared = FileConversionManager()

    enum ImageFormat: String, CaseIterable, Identifiable {
        case png = "PNG", jpeg = "JPEG", tiff = "TIFF", bmp = "BMP", gif = "GIF", heic = "HEIC"
        var id: String { rawValue }
        var bitmapFileType: NSBitmapImageRep.FileType? {
            switch self {
            case .png: return .png
            case .jpeg: return .jpeg
            case .tiff: return .tiff
            case .bmp: return .bmp
            case .gif: return .gif
            case .heic: return nil
            }
        }
    }

    @Published var lastOutputPath: String?
    @Published var lastError: String?
    @Published var selectedFormat: ImageFormat = .png

    private init() {}

    func pickImageAndConvert(to format: ImageFormat) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        convertImage(at: url.path, to: format)
    }

    func convertImage(at sourcePath: String, to format: ImageFormat) {
        lastError = nil
        guard let image = NSImage(contentsOfFile: sourcePath),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            lastError = "Could not read image."
            return
        }
        let outPath = (sourcePath as NSString).deletingPathExtension + "." + format.rawValue.lowercased()

        if format == .heic {
            guard let cgImage = rep.cgImage,
                  let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL, "public.heic" as CFString, 1, nil) else {
                lastError = "HEIC export is not supported on this system."
                return
            }
            CGImageDestinationAddImage(dest, cgImage, nil)
            guard CGImageDestinationFinalize(dest) else {
                lastError = "HEIC export failed."
                return
            }
            lastOutputPath = outPath
            return
        }

        guard let fileType = format.bitmapFileType,
              let data = rep.representation(using: fileType, properties: [:]) else {
            lastError = "Conversion failed."
            return
        }
        try? data.write(to: URL(fileURLWithPath: outPath))
        lastOutputPath = outPath
    }

    func pickImagesAndMakePDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        imagesToPDF(paths: panel.urls.map { $0.path })
    }

    func imagesToPDF(paths: [String]) {
        lastError = nil
        let pdfDocument = PDFDocument()
        for (index, path) in paths.enumerated() {
            guard let image = NSImage(contentsOfFile: path), let page = PDFPage(image: image) else { continue }
            pdfDocument.insert(page, at: index)
        }
        guard pdfDocument.pageCount > 0, let first = paths.first else {
            lastError = "No valid images to convert."
            return
        }
        let outPath = (first as NSString).deletingLastPathComponent + "/Converted.pdf"
        pdfDocument.write(toFile: outPath)
        lastOutputPath = outPath
    }

    func pickPDFAndConvertToImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pdfToImages(path: url.path)
    }

    func pdfToImages(path: String) {
        lastError = nil
        guard let document = PDFDocument(url: URL(fileURLWithPath: path)) else {
            lastError = "Could not open PDF."
            return
        }
        let baseName = (path as NSString).deletingPathExtension
        var lastPath: String?
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let image = NSImage(size: bounds.size)
            image.lockFocus()
            if let context = NSGraphicsContext.current?.cgContext {
                context.saveGState()
                page.draw(with: .mediaBox, to: context)
                context.restoreGState()
            }
            image.unlockFocus()
            guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let data = rep.representation(using: .png, properties: [:]) else { continue }
            let outPath = "\(baseName)-page\(pageIndex + 1).png"
            try? data.write(to: URL(fileURLWithPath: outPath))
            lastPath = outPath
        }
        lastOutputPath = lastPath
    }

    func revealLastOutput() {
        guard let path = lastOutputPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
