import SwiftUI

struct ScreenshotToolboxView: View {
    @ObservedObject var manager: ScreenshotToolboxManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Screenshot / Screen Recording Toolbox").font(.title2).bold()

            HStack {
                Button("Full Screen") { manager.captureFullScreen(toClipboard: false) }
                Button("Window…") { manager.captureWindow(toClipboard: false) }
                Button("Select Area…") { manager.captureArea(toClipboard: false) }
                Divider()
                Button("Copy Full Screen") { manager.captureFullScreen(toClipboard: true) }
                Button("Copy Area…") { manager.captureArea(toClipboard: true) }
            }

            Button("Record Screen (click Stop in the menu bar when done)") { manager.recordScreen() }

            if manager.isBusy { ProgressView() }

            if let path = manager.lastCapturePath {
                HStack {
                    Text(path).font(.caption).lineLimit(1)
                    Button("Reveal") { manager.revealLastCapture() }
                    Button("Run OCR") { manager.runOCROnLastCapture() }
                    Button("Resize/Compress") { manager.resizeLastCapture(maxDimension: 1600) }
                }
            }

            if !manager.ocrResult.isEmpty {
                Text("OCR Result").font(.headline)
                ScrollView {
                    Text(manager.ocrResult).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 160)
            }

            Text("Not implemented: annotation, blur/redact, format conversion, GIF export.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
