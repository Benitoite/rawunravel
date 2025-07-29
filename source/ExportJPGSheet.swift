import SwiftUI
import UniformTypeIdentifiers

struct JPEGDocument: FileDocument {
    static var readableContentTypes: [UTType] = [.jpeg]
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct ExportJPGSheet: View {
    let image: UIImage
    let sourceFileURL: URL? // Pass in the source RAW file URL for basename autofill
    let currentPP3: String
    var onComplete: (() -> Void)? = nil

    @State private var basename: String = ""
    @State private var quality = 85
    @State private var maxEdge = 2048

    @State private var isExporting = false
    @State private var exportData: Data?
    @State private var finishedExport = false
    @State private var toastMessage: String = ""

    @State private var isProcessingExport = false
    
    // Determine orientation
    var isVertical: Bool {
        image.size.height > image.size.width
    }

    // Resizing logic always constrains the long edge to maxEdge
    var resized: UIImage {
        let size = image.size
        let longEdge = CGFloat(maxEdge)
        let scale = isVertical
            ? min(1.0, longEdge / size.height)
            : min(1.0, longEdge / size.width)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let result = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return result ?? image
    }

    var body: some View {
        NavigationView {
            ZStack {
                if isProcessingExport {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    ProgressView("Exporting...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .yellow))
                        .scaleEffect(4)
                        .padding()
                        .background(Color.black.opacity(0.5).cornerRadius(16))
                        .zIndex(999)
                }
                
                Form {
                    Section(header: Text("Export Options")) {
                        TextField("Output filename (no .jpg)", text: $basename)
                            .autocorrectionDisabled(true)
                            .disableAutocorrection(true)
                        Stepper(value: $quality, in: 10...100, step: 1) {
                            HStack {
                                Text("JPEG Quality")
                                Spacer()
                                Text("\(quality)")
                            }
                        }
                        Stepper(value: $maxEdge, in: 256...8000, step: 64) {
                            HStack {
                                Text(isVertical ? "Max Height" : "Max Width")
                                Spacer()
                                Text("\(maxEdge) px")
                            }
                        }
                    }
                    Section(header: Text("Preview")) {
                        Image(uiImage: resized)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 120)
                        Text("Exported size: \(Int(resized.size.width)) x \(Int(resized.size.height)) px")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Section(header: Text("Export")) {
#if os(iOS)
                        Button("Save to Photos") {
                            saveToPhotos()
                        }
                        .buttonStyle(.borderedProminent)
#endif
                        Button("Export to File...") {
                            exportJPEG()
                        }
                        .buttonStyle(.bordered)
                        .disabled(basename.isEmpty)
                    }
                }
                // --- Toast overlay ---
                if finishedExport {
                    Text(toastMessage)
                        .font(.headline)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 32)
                        .background(Color.black.opacity(0.85))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .shadow(radius: 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(999)
                        .padding(.bottom, 64)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                                finishedExport = false
                                onComplete?()
                            }
                        }
                }
            }
            .navigationTitle("Export to JPEG")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onComplete?() }
                }
            }
            .fileExporter(
                isPresented: $isExporting,
                document: exportData.map { JPEGDocument(data: $0) },
                contentType: .jpeg,
                defaultFilename: basename
            ) { result in
                if case .success = result {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    toastMessage = "Export successful!"
                    finishedExport = true
                }
            }
            .onAppear {
                // Set default basename on first appear if empty
                if basename.isEmpty, let src = sourceFileURL {
                    let base = src.deletingPathExtension().lastPathComponent
                    basename = base
                }
            }
        }
    }

#if os(iOS)
    func saveToPhotos() {
        let outputImage = resized
        DispatchQueue.main.async {
            UIImageWriteToSavedPhotosAlbum(outputImage, nil, nil, nil)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            toastMessage = "Saved to Photos!"
            finishedExport = true
        }
    }
#endif

    func exportJPEG() {
        guard !basename.isEmpty, let rawURL = sourceFileURL else { return }
        isProcessingExport = true   // <-- start spinner

        let amazePP3 = pp3WithAmaze(currentPP3)
        let tempPP3 = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("amaze_export.pp3")
        try? amazePP3.write(to: tempPP3, atomically: true, encoding: .utf8)

        DispatchQueue.global(qos: .userInitiated).async {
            print("Starting RAW re-decode for JPEG export...")
            if let amazeImage = RTPreviewDecoder.decodeRAWPreview(
                atPath: rawURL.path,
                withPP3Path: tempPP3.path
            ) {
                print("AMaZE demosaic succeeded! Exporting full-quality JPEG.")
                let outputImage = amazeImage.resizedToFit(maxWidth: CGFloat(maxEdge))
                let jpegData = outputImage.jpegData(compressionQuality: CGFloat(quality) / 100.0)
                DispatchQueue.main.async {
                    exportData = jpegData
                    isExporting = true
                    isProcessingExport = false   // <-- stop spinner
                }
            } else {
                print("RAW decode failed—falling back to current preview image.")
                let outputImage = resized
                let jpegData = outputImage.jpegData(compressionQuality: CGFloat(quality) / 100.0)
                DispatchQueue.main.async {
                    exportData = jpegData
                    isExporting = true
                    isProcessingExport = false   // <-- stop spinner
                }
            }
        }
    
    }
}


func pp3WithAmaze(_ pp3: String) -> String {
    var lines = pp3.components(separatedBy: .newlines)
    var inserted = false
    for (i, line) in lines.enumerated() {
        if line.trimmingCharacters(in: .whitespaces) == "[RAW]" {
            if i+1 < lines.count && lines[i+1].hasPrefix("DemosaicMethod=") {
                lines[i+1] = "DemosaicMethod=amaze"
                inserted = true
                break
            } else {
                lines.insert("DemosaicMethod=amaze", at: i+1)
                inserted = true
                break
            }
        }
    }
    if !inserted {
        lines.append("[RAW]")
        lines.append("DemosaicMethod=amaze")
    }
    return lines.joined(separator: "\n")
}
