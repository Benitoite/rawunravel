import SwiftUI
func fileSizeString(for url: URL) -> String {
    do {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attrs[.size] as? NSNumber {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useKB, .useMB, .useGB]
            formatter.countStyle = .file
            return formatter.string(fromByteCount: size.int64Value)
        }
    } catch {}
    return "Unknown size"
}

func fileCreationDateString(for url: URL) -> String {
    do {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        if let date = attrs[.creationDate] as? Date {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
    } catch {}
    return "Unknown date"
}

import ImageIO

func imageDimensionsString(for url: URL) -> String? {
    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int else {
        return nil
    }
    return "\(width) × \(height) px"
}

struct ContentView: View {
    @State private var isPickerPresented = false
    @State private var selectedFilePath: String?
    @State private var isFileViewPresented = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Button("Select RAW File") {
                    isPickerPresented = true
                }
                .padding()
                .buttonStyle(.borderedProminent)
                if let path = selectedFilePath {
                    let fileURL = URL(fileURLWithPath: path)
                    VStack {
                        // 1. Path label
                        Text("Selected File Path:")
                            .font(.headline)
                            .multilineTextAlignment(.center)
                        
                        // 2. Path itself
                        Text(path)
                            .font(.system(.body, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                            .lineLimit(nil)
                            .padding(.horizontal, 8)

                        Spacer() // Evenly distribute space
                        // Details area under file path
                        VStack(spacing: 8) {
                            Text("Size: \(fileSizeString(for: fileURL))")
                                .font(.headline)
                                .multilineTextAlignment(.center)
                            if let dims = imageDimensionsString(for: fileURL) {
                                Text("Dimensions: \(dims)")
                                    .font(.headline)
                                    .multilineTextAlignment(.center)
                            }
                            Text("Created: \(fileCreationDateString(for: fileURL))")
                                .font(.headline)
                                .multilineTextAlignment(.center)
                        }
                        
                   
                        Spacer() // Evenly distribute space

                        // 4. Button
                        Button("Preview File") {
                            isFileViewPresented = true
                        }
                        .buttonStyle(.bordered)
                        .padding(.bottom, 8)

                        // 5. Filename
                        Text("Filename: \(fileURL.lastPathComponent)")
                            .bold()
                            .padding(.bottom, 16)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.horizontal)
                }
            }
            .fullScreenCover(isPresented: $isPickerPresented) {
                DocumentPicker { url in
                    selectedFilePath = url.path
                    isPickerPresented = false
                }
            }
            .navigationDestination(isPresented: $isFileViewPresented) {
                if let selectedFilePath {
                    FileView(fileURL: URL(fileURLWithPath: selectedFilePath))
                }
            }
        }
    }
}
