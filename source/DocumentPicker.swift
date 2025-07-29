import SwiftUI
import UniformTypeIdentifiers

struct DocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void
    @AppStorage("LastOpenDirectory") private var lastDirectoryPath: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, lastDirectoryPath: $lastDirectoryPath)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let supportedTypes: [UTType] = [
            UTType.tiff,
            UTType.jpeg,
            UTType.png
        ] + [
            "com.adobe.raw-image",
            "public.camera-raw-image",
            "com.canon.cr2-raw-image",
            "com.nikon.nef-raw-image",
            "com.sony.arw-raw-image"
        ].compactMap { UTType($0) }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes, asCopy: true)
        print("Restoring picker to:", lastDirectoryPath ?? "<none>")
        // Restore last directory if possible (iOS: just plain URL)
        if let lastDir = lastDirectoryPath {
            picker.directoryURL = URL(fileURLWithPath: lastDir)
        }

        picker.delegate = context.coordinator
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onPick: (URL) -> Void
        @Binding var lastDirectoryPath: String?

        init(onPick: @escaping (URL) -> Void, lastDirectoryPath: Binding<String?>) {
            self.onPick = onPick
            self._lastDirectoryPath = lastDirectoryPath
        }

        func persistPickedRAW(url: URL) -> URL? {
            let fileManager = FileManager.default
            let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            let destURL = docs.appendingPathComponent(url.lastPathComponent)
            do {
                if fileManager.fileExists(atPath: destURL.path) {
                    try fileManager.removeItem(at: destURL)
                }
                try fileManager.copyItem(at: url, to: destURL)
                return destURL
            } catch {
                print("Failed to copy file to Documents: \(error)")
                return nil
            }
        }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let firstURL = urls.first, let stableURL = persistPickedRAW(url: firstURL) {
                let dir = firstURL.deletingLastPathComponent()
                print("Saving last directory:", dir.path)
                lastDirectoryPath = dir.path
                onPick(stableURL)
            } else {
                print("Failed to persist picked file.")
            }
        
            }
        }
    }

