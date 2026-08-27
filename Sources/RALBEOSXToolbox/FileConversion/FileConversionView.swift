import SwiftUI

struct FileConversionView: View {
    @ObservedObject var manager: FileConversionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("File Conversion Toolbox").font(.title2).bold()

            GroupBox("Image Format Conversion") {
                HStack {
                    Picker("Target format", selection: $manager.selectedFormat) {
                        ForEach(FileConversionManager.ImageFormat.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .frame(width: 200)
                    Button("Choose Image…") { manager.pickImageAndConvert(to: manager.selectedFormat) }
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
