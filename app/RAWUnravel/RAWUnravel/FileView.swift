/*
    RawUnravel - FileView.swift
    --------------------------------
    Copyright (C) 2025 Richard Barber

    This file is part of RawUnravel.

    RawUnravel is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    RawUnravel is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with RawUnravel.  If not, see <https://www.gnu.org/licenses/>.
*/

// MARK: - Imports

import SwiftUI
import UniformTypeIdentifiers
import ImageIO
import MobileCoreServices

// MARK: - View Conditional Modifier

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

// MARK: - FileView (Image/RAW Detail Viewer)

struct FileView: View {
    // MARK: - Inputs & State
    let fileURL: URL
    @State private var image: UIImage?
    @State private var metadata: [String: Any] = [:]
    @State private var isLoading = true
    @State private var showDevelopScreen = false

    /// Computed property for RAW image size (from metadata)
    var rawImageSize: CGSize? {
        if let width = metadata[kCGImagePropertyPixelWidth as String] as? Int,
           let height = metadata[kCGImagePropertyPixelHeight as String] as? Int {
            return CGSize(width: width, height: height)
        }
        return nil
    }

    // MARK: - Main View Layout

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                if geometry.size.width > geometry.size.height {
                    // MARK: - Landscape: Side-by-side
                    headerBar()
                        .padding(.horizontal)
                    HStack(alignment: .top, spacing: 20) {
                        imageSection()
                            .frame(width: geometry.size.width * 0.5)
                        dataSection()
                            .frame(width: geometry.size.width * 0.5)
                    }
                    .padding()
                } else {
                    // MARK: - Portrait: Stacked
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
        // MARK: - RAW Developer Navigation
        .navigationDestination(isPresented: $showDevelopScreen) {
            DevelopScreen(
                fileURL: fileURL,
                rawImageSize: rawImageSize ?? .zero
            )
        }
        .onAppear(perform: loadThumbnailAndMetadata)
    }

    // MARK: - Header Bar (Filename & Develop Button)
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

    // MARK: - Image Section

    func imageSection() -> some View {
        VStack(spacing: 8) {
            if isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(8)
                // Show dimensions for both RAW and standard images
                if isRawImage(fileURL) {
                    if let width = metadata[kCGImagePropertyPixelWidth as String] as? Int,
                       let height = metadata[kCGImagePropertyPixelHeight as String] as? Int {
                        Text("RAW Dimensions: \(width) × \(height)")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    if let tw = img.cgImage?.width, let th = img.cgImage?.height {
                        Text("Thumbnail: \(tw) × \(th)")
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

    // MARK: - Metadata/Info Section

    @ViewBuilder
    func dataSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !metadata.isEmpty {
                Divider()
                metadataSection(for: fileURL)
            }
            // GPS Button if present
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

    // MARK: - Thumbnail/Metadata Loader

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

    // MARK: - File Type Helper

    func isRawImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
            return false
        }
        return type.conforms(to: .rawImage)
    }

    // MARK: - Metadata Section

    @ViewBuilder
    func metadataSection(for url: URL) -> some View {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            VStack(alignment: .leading, spacing: 6) {
                if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                    if let model = tiff[kCGImagePropertyTIFFModel] {
                        Text("Camera Model: \(model)")
                    }
                }
                if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                    Group {
                        if let iso = exif[kCGImagePropertyExifISOSpeedRatings] {
                            Text("ISO: \(iso)")
                        }
                        if let exposureTime = exif[kCGImagePropertyExifExposureTime] as? Double {
                            Text("Exposure: \(exposureTimeFraction(exposureTime))")
                        }
                        if let lensModel = exif[kCGImagePropertyExifLensModel] as? String {
                            Text("Lens Model: \(lensModel)")
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
            .font(.caption)
            .padding(.top)
        }
    }
}

// MARK: - GPS Coordinate Extraction

/// Returns (latitude, longitude) from EXIF GPS metadata if present.
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
func exposureTimeFraction(_ value: Double) -> String {
    // If >= 1 sec, show as plain number (e.g. "2 sec")
    if value >= 1.0 {
        return String(format: "%.1f sec", value)
    }
    // If very short, round denominator
    let denom = Int((1.0 / value).rounded())
    return "1/\(denom)s"
}
