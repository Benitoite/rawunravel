import SwiftUI
import UniformTypeIdentifiers
import ImageIO
import MobileCoreServices
extension View {
    @ViewBuilder
    func `if`<Transform: View>(
        _ condition: Bool,
        transform: (Self) -> Transform
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
struct FileView: View {
    let fileURL: URL
    @State private var image: UIImage?
    @State private var metadata: [String: Any] = [:]
    @State private var isLoading = true
    @State private var showDevelopScreen = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                if geometry.size.width > geometry.size.height {
                    headerBar()
                    // LANDSCAPE LAYOUT: Side-by-side image & data
                    HStack(alignment: .top, spacing: 20) {
                        imageSection()
                            .frame(width: geometry.size.width * 0.5)
                        dataSection()
                            .frame(width: geometry.size.width * 0.5)
                    }
                    .padding()
                } else {
                    // PORTRAIT LAYOUT: Stack vertically
                    VStack(spacing: 16) {
                                   headerBar()
                                   imageSection()
                                       .frame(width: geometry.size.width * 0.5)
                                   dataSection()
                               
                    
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            }
        
             
        }
        .navigationDestination(isPresented: $showDevelopScreen) {
            DevelopScreen(fileURL: fileURL)
        
        }
        .onAppear(perform: loadThumbnailAndMetadata)
    }

    @ViewBuilder
    func headerBar() -> some View {
        HStack {
            Text(fileURL.lastPathComponent)
                .font(.headline)
            Spacer()
            if isRawImage(fileURL) {
                Button("Develop RAW") {
                    showDevelopScreen = true
                }
            }
        }
        .padding(.bottom, 2)
    }
    
    func imageSection() -> some View {
        VStack( spacing: 8) {
             

            if isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(8)

                if isRawImage(fileURL) {
                    if let width = metadata[kCGImagePropertyPixelWidth as String] as? Int,
                       let height = metadata[kCGImagePropertyPixelHeight as String] as? Int {
                        Text("RAW Dimensions: \(width) × \(height)")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                } else if let width = img.cgImage?.width,
                          let height = img.cgImage?.height {
                    Text("Dimensions: \(width) × \(height)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    func dataSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !metadata.isEmpty {
                Divider()
                metadataSection(for: fileURL)
            }

            if let coords = extractGPSCoordinates(from: metadata) {
                Button {
                    let latitude = coords.latitude
                    let longitude = coords.longitude
                    let googleMapsURL = URL(string: "comgooglemaps://?q=\(latitude),\(longitude)&center=\(latitude),\(longitude)&zoom=14")!
                    let appleMapsURL = URL(string: "http://maps.apple.com/?q=\(latitude),\(longitude)&ll=\(latitude),\(longitude)")!

                    if UIApplication.shared.canOpenURL(googleMapsURL) {
                        UIApplication.shared.open(googleMapsURL)
                    } else {
                        UIApplication.shared.open(appleMapsURL)
                    }
                } label: {
                    Label("GPS", systemImage: "map")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    func loadThumbnailAndMetadata() {
        DispatchQueue.global(qos: .userInitiated).async {
            defer { isLoading = false }

            let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, imageSourceOptions) else { return }

            let thumbnailOptions = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 800,
                kCGImageSourceCreateThumbnailWithTransform: true
            ] as CFDictionary

            if let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) {
                image = UIImage(cgImage: cgThumb)
            }

            if let imageMetadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
                metadata = imageMetadata
            }
        }
    }

    func isRawImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
            return false
        }
        return type.conforms(to: .rawImage)
    }

    @ViewBuilder
    func metadataSection(for url: URL) -> some View {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            VStack(alignment: .leading, spacing: 6) {
                if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                    if let model = tiff[kCGImagePropertyTIFFModel] {
                        Text("Camera Model: \(model)")
                    }
                    if let make = tiff[kCGImagePropertyTIFFMake] {
                        Text("Manufacturer: \(make)")
                    }
                }

                if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                    Group {
                        if let iso = exif[kCGImagePropertyExifISOSpeedRatings] {
                            Text("ISO: \(iso)")
                        }
                        if let exposureTime = exif[kCGImagePropertyExifExposureTime] {
                            Text("Exposure: \(exposureTime) sec")
                        }
                        if let aperture = exif[kCGImagePropertyExifFNumber] {
                            Text("Aperture: ƒ\(aperture)")
                        }
                        if let focalLength = exif[kCGImagePropertyExifFocalLength] {
                            Text("Focal Length: \(focalLength) mm")
                        }
                        if let whiteBalance = exif[kCGImagePropertyExifWhiteBalance] as? Int {
                            Text("White Balance: \((whiteBalance == 1) ? "Manual" : "Auto")")
                        }
                        if let flash = exif[kCGImagePropertyExifFlash] as? Int {
                            let flashString = switch flash {
                                case 0: "No Flash"
                                case 1: "Flash Fired"
                                case 5: "Flash Fired (No Return)"
                                case 7: "Flash Fired, Return Detected"
                                default: "Flash Info: \(flash)"
                            }
                            Text("Flash: \(flashString)")
                        }
                        if let exposureProgram = exif[kCGImagePropertyExifExposureProgram] as? Int {
                            let exposureString = switch exposureProgram {
                                case 1: "Manual"
                                case 2: "Program AE"
                                case 3: "Aperture Priority"
                                case 4: "Shutter Priority"
                                case 5: "Creative Program"
                                case 6: "Action Program"
                                case 7: "Portrait Mode"
                                case 8: "Landscape Mode"
                                default: "Unknown Program"
                            }
                            Text("Program: \(exposureString)")
                        }
                        if let meteringMode = exif[kCGImagePropertyExifMeteringMode] as? Int {
                            let meteringString = switch meteringMode {
                                case 1: "Average"
                                case 2: "Center-weighted"
                                case 3: "Spot"
                                case 4: "Multi-spot"
                                case 5: "Pattern"
                                case 6: "Partial"
                                default: "Unknown Mode"
                            }
                            Text("Metering: \(meteringString)")
                        }
                        if let date = exif[kCGImagePropertyExifDateTimeOriginal] {
                            Text("Date Taken: \(date)")
                        }
                    }
                }
            }
            .font(.system(.body, design: .monospaced))
            .padding(.top)
        }
    }
}

func extractGPSCoordinates(from metadata: [String: Any]) -> (latitude: Double, longitude: Double)? {
    guard
        let gps = metadata[kCGImagePropertyGPSDictionary as String] as? [String: Any],
        let lat = gps[kCGImagePropertyGPSLatitude as String] as? Double,
        let latRef = gps[kCGImagePropertyGPSLatitudeRef as String] as? String,
        let lon = gps[kCGImagePropertyGPSLongitude as String] as? Double,
        let lonRef = gps[kCGImagePropertyGPSLongitudeRef as String] as? String
    else {
        return nil
    }

    let latitude = (latRef == "S") ? -lat : lat
    let longitude = (lonRef == "W") ? -lon : lon
    return (latitude, longitude)
}
