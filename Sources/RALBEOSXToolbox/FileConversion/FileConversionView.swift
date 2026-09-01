import SwiftUI

struct FileConversionView: View {
    @ObservedObject var manager: FileConversionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("File Conversion Toolbox").font(.title2).bold()

            GroupBox("Convert Image to Another Format") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Picker("Convert to", selection: $manager.selectedFormat) {
                            ForEach(FileConversionManager.ImageFormat.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .frame(width: 200)
                        Button("Choose Source Image…") { manager.pickImageAndConvert(to: manager.selectedFormat) }
                    }
                    Text("Converts PNG, JPEG, TIFF, BMP, GIF, HEIC, and other macOS-readable images. The converted copy is saved beside the original; your source image is unchanged.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }

            GroupBox("Images ↔ PDF") {
                HStack {
                    Button("Images to PDF…") { manager.pickImagesAndMakePDF() }
                    Button("PDF to Images…") { manager.pickPDFAndConvertToImages() }
                }
                .padding(.top, 4)
            }

            if let error = manager.lastError {
                Text(error).foregroundStyle(.red)
            }
            if let output = manager.lastOutputPath {
                HStack {
                    Text(output).font(.caption).lineLimit(1)
                    Button("Reveal") { manager.revealLastOutput() }
                }
            }

            Text("Not implemented: audio/video conversion.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
