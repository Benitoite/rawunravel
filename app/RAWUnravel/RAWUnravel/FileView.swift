/*
    RawUnravel - FileView.swift
    ---------------------------
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

 import SwiftUI
 import UIKit
 import UniformTypeIdentifiers
 import ImageIO
 import MobileCoreServices

 var onOpenFile: ((URL) -> Void)?

 struct IdentifiableURL: Identifiable {
     let id = UUID()
     let url: URL
 }

 struct FileView: View {
     let fileURL: URL
     let displayName: String?
     var showCancelButton: Bool = false

     @State private var showFileImporter = false
     @State private var pickedFile: IdentifiableURL? = nil

     @State private var image: UIImage?
     @State private var fullResUIImage: UIImage?          // full-res buffer for Resize/Export
     @State private var metadata: [String: Any] = [:]
     @State private var isLoading = true

     @State private var showResizeSheet = false
     @State private var showDevelop = false
     @State private var rawSize: CGSize? = nil  // set when metadata parsed
     @State private var pickedRawSize: CGSize = .zero

     // generation token so older load attempts don't override newer ones
     @State private var loadGeneration: Int = 0

     // preview info (if we want to show preview pixel size etc)
     @State private var previewPixelSize: CGSize? = nil
     @State private var previewIndex: Int? = nil

     @Environment(\.horizontalSizeClass) private var hSizeClass
     @Environment(\.dismiss) private var dismiss

     var isIpad: Bool { hSizeClass == .regular }

     var rawImageSize: CGSize? {
         if let width = metadata[kCGImagePropertyPixelWidth as String] as? Int,
            let height = metadata[kCGImagePropertyPixelHeight as String] as? Int {
             return CGSize(width: width, height: height)
         }
         return nil
     }

     var body: some View {
         VStack(spacing: 0) {
             // hidden navigation link (your preserved snippet)
             NavigationLink(
                 destination: DevelopScreen(
                     fileURL: pickedFile?.url ?? fileURL,
                     rawImageSize: pickedRawSize == .zero ? (rawSize ?? .zero) : pickedRawSize
                 ),
                 isActive: $showDevelop
             ) { EmptyView() }
             .hidden()

             GeometryReader { geometry in
                 ScrollView {
                     if geometry.size.width > geometry.size.height {
                         // LANDSCAPE
                         headerBar()
                             .padding(.horizontal, isIpad ? 32 : 16)
                             .padding(.top, isIpad ? 20 : 0)
                         HStack(alignment: .top, spacing: isIpad ? 44 : 20) {
                             imageSection(maxWidth: isIpad ? min(geometry.size.width * 0.38, 400) : geometry.size.width * 0.5)
                             dataSection()
                                 .frame(width: geometry.size.width * 0.5)
                         }
                         .padding(isIpad ? 32 : 16)
                     } else {
                         // PORTRAIT
                         VStack(spacing: isIpad ? 32 : 16) {
                             headerBar()
                             imageSection(maxWidth: isIpad ? min(geometry.size.width * 0.5, 400) : geometry.size.width * 0.5)
                             dataSection()
                         }
                         .frame(maxWidth: .infinity)
                         .padding(isIpad ? 32 : 16)
                     }
                 }
             }
             // Full-res resize/export sheet for non-RAW images
             .sheet(isPresented: $showResizeSheet) {
                 let sizeFromImage = fullResUIImage?.pixelSize ?? image?.pixelSize
                 let effectiveSize = rawImageSize ?? sizeFromImage ?? .zero

                 if effectiveSize != .zero {
                     ExportJPGView(
                         rawFileURL: fileURL,
                         pp3String: "",
                         cropRectInPreview: nil,
                         previewFrame: nil,
                         previewUIImageSize: fullResUIImage?.size,
                         previewUIImage: fullResUIImage,
                         rawImageSize: fullResUIImage?.pixelSize ?? .zero,
                         sourceBitmap: fullResUIImage
                     ) {
                         showResizeSheet = false
                     }
                 } else {
                     Text("Image size unknown. Export not available.")
                         .padding()
                         .foregroundColor(.red)
                 }
             }
             .onAppear {
                 // increment generation and start load
                 loadGeneration += 1
                 loadThumbnailAndMetadata(generation: loadGeneration)
                 print("[DBG] FileView onAppear; fileURL=\(fileURL.path) isRaw=\(isRawImage(fileURL))")
             }
         }
         // --- OUTSIDE VStack: Attach fileImporter and sheet for new file ---
         .fileImporter(
             isPresented: $showFileImporter,
             allowedContentTypes: [.rawImage],
             allowsMultipleSelection: true // handle array robustly
         ) { result in
             switch result {
             case .success(let urls):
                 guard let first = urls.first else { return }
                 print("[DBG] fileImporter returned url: \(first.path)")
                 Task {
                     // copy provider to temp (ensures provider has finished writing)
                     if let imported = await FileOpenHelper.shared.copyProviderToTempIfNeeded(first) {
                         // probe RAW active size off-main
                         let size = await withCheckedContinuation { cont in
                             DispatchQueue.global(qos: .userInitiated).async {
                                 let s = RTPreviewDecoder.rawActiveSize(atPath: imported.path)
                                 cont.resume(returning: s)
                             }
                         }

                         await MainActor.run {
                             self.pickedFile = IdentifiableURL(url: imported)
                             self.pickedRawSize = size
                             // set metadata preview values so UI shows correct info if needed
                             self.metadata = self.metadata // keep existing metadata; loadThumbnail will update
                             // navigate to DevelopScreen now that import & size are ready
                             print("[DBG] import completed -> \(imported.path), size=\(size)")
                             self.showDevelop = true
                         }
                     } else {
                         print("[DBG] copyProviderToTempIfNeeded returned nil for \(first.path)")
                     }
                 }

             case .failure(let error):
                 print("Importer error:", error)
             }
         }
     }

     // MARK: - Header Bar

     @ViewBuilder
     func headerBar() -> some View {
         HStack(spacing: isIpad ? 18 : 8) {
             if showCancelButton {
                 Button("Cancel") { dismiss() }
                     .buttonStyle(.bordered)
                     .font(isIpad ? .title3 : .body)
                     .padding(.trailing, 6)
             }

             // Always use sanitized filename
             Text(displayBaseFilename(from: fileURL))
                 .font(isIpad ? .title2 : .headline)
                 .lineLimit(1)
                 .minimumScaleFactor(0.6)
                 .frame(maxWidth: .infinity, alignment: .leading)

             if isRawImage(fileURL) {
                 Button("Develop RAW") {
                     print("[DBG] Develop RAW button tapped")
                     if pickedFile == nil {
                         self.pickedFile = IdentifiableURL(url: fileURL)
                         self.pickedRawSize = self.rawSize ?? self.rawImageSize ?? .zero
                     }
                     Task { await MainActor.run { self.showDevelop = true } }
                 }
                 .font(isIpad ? .title3 : .body)
                 .padding(.horizontal, isIpad ? 32 : 12)
                 .padding(.vertical, isIpad ? 10 : 6)
                 .background(Color.accentColor.opacity(0.09))
                 .cornerRadius(isIpad ? 13 : 8)
                 .applyIf(isIpad) { $0.padding(.trailing, 32) }

             } else if image != nil {
                 Button("Resize") { loadFullResAndPresent() }
                     .font(isIpad ? .title3 : .body)
                     .padding(.horizontal, isIpad ? 32 : 12)
                     .padding(.vertical, isIpad ? 10 : 6)
                     .background(Color.accentColor.opacity(0.09))
                     .cornerRadius(isIpad ? 13 : 8)
                     .applyIf(isIpad) { $0.padding(.trailing, 32) }
             }
         }
         .padding(.bottom, isIpad ? 10 : 2)
         .frame(maxWidth: .infinity)
     }

     // MARK: - Image Section
     func imageSection(maxWidth: CGFloat) -> some View {
         VStack(spacing: 8) {
             if isLoading && image == nil {
                 ProgressView("Loading...")
                     .font(isIpad ? .title3 : .body)
                     .frame(maxWidth: .infinity, alignment: .center)
             } else if let img = image {
                 Image(uiImage: img)
                     .resizable()
                     .scaledToFit()
                     .frame(maxWidth: maxWidth, maxHeight: isIpad ? 320 : .infinity)
                     .cornerRadius(10)

                 if isRawImage(fileURL) {
                     if let width = metadata[kCGImagePropertyPixelWidth as String] as? Int,
                        let height = metadata[kCGImagePropertyPixelHeight as String] as? Int {
                         Text("RAW Dimensions: \(width) × \(height)")
                             .font(isIpad ? .callout : .footnote)
                             .foregroundColor(.secondary)
                     }

                     if isRawImage(fileURL), let p = previewPixelSize {
                         Text("Thumbnail: \(Int(p.width)) × \(Int(p.height))")
                             .font(isIpad ? .callout : .footnote)
                             .foregroundColor(.secondary)
                     }

                 } else if let width = img.cgImage?.width,
                           let height = img.cgImage?.height {
                     Text("Dimensions: \(width) × \(height)")
                         .font(isIpad ? .callout : .footnote)
                         .foregroundColor(.secondary)
                 }
             }
         }
     }

     // MARK: - Metadata/Info Section
     @ViewBuilder
     func dataSection() -> some View {
         VStack(alignment: .leading, spacing: isIpad ? 18 : 10) {
             if !metadata.isEmpty {
                 Divider()
                 metadataSection(for: fileURL)
             }

             if let coords = extractGPSCoordinates(from: metadata) {
                 Text("Found coords: \(coords.latitude), \(coords.longitude)")
                 Button {
                     let latitude = coords.latitude
                     let longitude = coords.longitude
                     let googleMapsURL = URL(string: "comgooglemaps://?q=\(latitude),\(longitude)&center=\(latitude),\(longitude)&zoom=14")!
                     let appleMapsURL  = URL(string: "http://maps.apple.com/?q=\(latitude),\(longitude)&ll=\(latitude),\(longitude)")!
                     if UIApplication.shared.canOpenURL(googleMapsURL) {
                         UIApplication.shared.open(googleMapsURL)
                     } else {
                         UIApplication.shared.open(appleMapsURL)
                     }
                 } label: {
                     Label("GPS", systemImage: "map")
                         .font(isIpad ? .title3 : .headline)
                         .frame(maxWidth: .infinity)
                 }
                 .buttonStyle(.borderedProminent)
             } else {
                 Text("No GPS found")
             }
         }
     }

     // MARK: - Thumbnail/Metadata Loader (robust: security-scoped + retry + copy-to-temp)
     func loadThumbnailAndMetadata(generation gen: Int) {
         DispatchQueue.main.async {
             self.isLoading = true
             // reset per-load so stale values never show
             self.previewPixelSize = nil
             self.previewIndex = nil
         }

         DispatchQueue.global(qos: .userInitiated).async {
             let originalURL = fileURL
             var attemptURL = fileURL
             var didStartAccess = false

             if originalURL.startAccessingSecurityScopedResource() { didStartAccess = true }
             defer { if didStartAccess { originalURL.stopAccessingSecurityScopedResource() } }

             var foundThumb: UIImage? = nil          // what we *display*
             var foundFullRes: UIImage? = nil        // used for JPEG Resize flow
             var foundMetadata: [String: Any]? = nil

             // Embedded preview we will *report* in UI (never falls back to 800 or RAW size)
             var embeddedPreviewSize: CGSize? = nil
             let thumbOptions = [
                 kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                 kCGImageSourceShouldCache: false,
                 kCGImageSourceThumbnailMaxPixelSize: 800,
                 kCGImageSourceCreateThumbnailWithTransform: true
             ] as CFDictionary

             // Don’t consider tiny icons
             let minPreviewArea = 200 * 200

             func probeSource(_ src: CGImageSource) {
                 // Collect per-index sizes and look for an explicit ThumbnailDictionary
                 let count = CGImageSourceGetCount(src)
                 var sizes: [(i: Int, w: Int, h: Int, area: Int)] = []
                 let thumbDictSize: CGSize? = nil

                 for i in 0..<count {
                     if let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [String: Any] {
                         if let w = props[kCGImagePropertyPixelWidth as String] as? Int,
                            let h = props[kCGImagePropertyPixelHeight as String] as? Int,
                            w > 0, h > 0 {
                             sizes.append((i, w, h, w*h))
                         }
                     }
                 }

                 // Decide embedded preview size:
                 if let td = thumbDictSize {
                     embeddedPreviewSize = td
                 } else if sizes.count >= 2 {
                     let sorted = sizes.sorted { $0.area > $1.area }  // largest first
                     let largest = sorted[0]
                     if let cand = sorted.dropFirst().filter({ $0.area < largest.area && $0.area >= minPreviewArea }).max(by: { $0.area < $1.area }) {
                         embeddedPreviewSize = CGSize(width: cand.w, height: cand.h)
                     }
                 }

                 if foundThumb == nil, let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOptions) {
                     foundThumb = UIImage(cgImage: cg)
                 }

                 if foundMetadata == nil,
                    let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any],
                    !props.isEmpty {
                     foundMetadata = props
                 }
             }

             // 1) Try reading from URL
             if let src = CGImageSourceCreateWithURL(attemptURL as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) {
                 probeSource(src)
                 if isRawImage(attemptURL), embeddedPreviewSize == nil {
                     embeddedPreviewSize = getEmbeddedJPEGPreviewSize(attemptURL)
                 }
             }

             // 2) Fallback: read data (also keeps full-res JPEG for Resize flow)
             if (foundMetadata == nil || embeddedPreviewSize == nil) || (!isRawImage(attemptURL) && foundFullRes == nil) {
                 if let data = try? Data(contentsOf: attemptURL, options: .mappedIfSafe) {
                     if !isRawImage(attemptURL), foundFullRes == nil, let ui = UIImage(data: data) {
                         foundFullRes = ui
                         if foundThumb == nil { foundThumb = ui }
                     }
                     if let src = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) {
                         probeSource(src)
                     }
                 }
             }

             // 3) If RAW metadata still missing, force-provider by copying to our tmp and re-reading
             if foundMetadata == nil {
                 let base = FileManager.default.temporaryDirectory.appendingPathComponent("RAWUnravel_Imported", isDirectory: true)
                 do {
                     try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
                     let tmp = base.appendingPathComponent(UUID().uuidString + "-" + attemptURL.lastPathComponent)
                     try FileManager.default.copyItem(at: attemptURL, to: tmp)
                     attemptURL = tmp
                     if let src = CGImageSourceCreateWithURL(attemptURL as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) {
                         probeSource(src)
                     }
                 } catch {
                     // ignore; use whatever we have
                 }
             }

             DispatchQueue.main.async {
                 if gen != loadGeneration { return }

                 self.image = foundThumb
                 if let fr = foundFullRes { self.fullResUIImage = fr }

                 // ⬇️ THIS IS THE KEY LINE:
                 self.previewPixelSize = embeddedPreviewSize

                 if let md = foundMetadata {
                     self.metadata = md
                     if let w = md[kCGImagePropertyPixelWidth as String] as? Int,
                        let h = md[kCGImagePropertyPixelHeight as String] as? Int {
                         self.rawSize = CGSize(width: w, height: h)
                     } else {
                         self.rawSize = nil
                     }
                 } else {
                     self.metadata = [:]
                     self.rawSize = nil
                 }

                 self.isLoading = false
             }
         }
     }

     // MARK: - Full-res loader for non-RAW export
     private func loadFullResAndPresent() {
         isLoading = true
         DispatchQueue.global(qos: .userInitiated).async {
             var loaded: UIImage? = nil

             if let data = try? Data(contentsOf: fileURL),
                let ui = UIImage(data: data) {
                 loaded = ui
             } else {
                 if let src = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
                    let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                     loaded = UIImage(cgImage: cg)
                 }
             }

             DispatchQueue.main.async {
                 self.fullResUIImage = loaded
                 self.isLoading = false
                 self.showResizeSheet = (loaded != nil)
             }
         }
     }

     // MARK: - Type helper
     func isRawImage(_ url: URL) -> Bool {
         guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
             return false
         }
         return type.conforms(to: .rawImage)
     }

     // MARK: - Metadata Section
     @ViewBuilder
     func metadataSection(for url: URL) -> some View {
         // ---- Gather everything first (no ViewBuilder here) ----
         let src = CGImageSourceCreateWithURL(url as CFURL, nil)
         let props = src.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }

         let tiff = props?[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
         let exif = props?[kCGImagePropertyExifDictionary] as? [CFString: Any]
         let author = props.flatMap { extractAuthor(from: $0) }

         let isoKeys: [CFString] = [
             kCGImagePropertyExifISOSpeedRatings,
             "ISOSpeedRatings" as CFString,
             "ISOSpeed" as CFString,
             "PhotographicSensitivity" as CFString,
             "ISO" as CFString
         ]
         let isoValue: Any? = {
             guard let exif = exif else { return nil }
             return isoKeys.lazy.compactMap { exif[$0] }.first
         }()

         let cameraModel = tiff?[kCGImagePropertyTIFFModel] as? String
         let exposureTime = exif?[kCGImagePropertyExifExposureTime] as? Double
         let lensModel = exif?[kCGImagePropertyExifLensModel] as? String
         let aperture = exif?[kCGImagePropertyExifFNumber]
         let focalLength = exif?[kCGImagePropertyExifFocalLength]
         let whiteBalance = exif?[kCGImagePropertyExifWhiteBalance] as? Int
         let flash = exif?[kCGImagePropertyExifFlash] as? Int
         let exposureProgram = exif?[kCGImagePropertyExifExposureProgram] as? Int
         let meteringMode = exif?[kCGImagePropertyExifMeteringMode] as? Int
         let dateTaken = exif?[kCGImagePropertyExifDateTimeOriginal]

         // ---- Views only below (no vars/loops/prints) ----
         if props != nil {
             VStack(alignment: .leading, spacing: 6) {
                 if let cameraModel { Text("Camera Model: \(cameraModel)") }

                 if let isoValue {
                     Text("ISO: \(isoValueString(isoValue).trimmingCharacters(in: .whitespacesAndNewlines))")
                 } else {
                     Text("ISO: (not present)").foregroundColor(.secondary)
                 }

                 if let exposureTime { Text("Exposure: \(exposureTimeFraction(exposureTime))") }
                 if let lensModel { Text("Lens Model: \(lensModel)") }
                 if let aperture { Text("Aperture: ƒ\(formattedAperture(aperture))") }
                 if let focalLength { Text("Focal Length: \(focalLength) mm") }
                 if let whiteBalance { Text("White Balance: \((whiteBalance == 1) ? "Manual" : "Auto")") }
                 if let flash { Text("Flash: \(flashDescription(flash))") }
                 if let exposureProgram { Text("Program: \(exposureProgramDescription(exposureProgram))") }
                 if let meteringMode { Text("Metering: \(meteringModeDescription(meteringMode))") }
                 if let dateTaken { Text("Date Taken: \(dateTaken)") }
                 if let author { Text("Author: \(author)") }
             }
             .font(isIpad ? .callout : .caption)
             .padding(.top)
         }
     }

     // MARK: - GPS helpers
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
         if value >= 1.0 { return String(format: "%.1f sec", value) }
         let denom = Int((1.0 / value).rounded())
         return "1/\(denom)s"
     }
 }

 // MARK: - Utilities (kept as-is)
 // ... (keep the utility helpers from your original file: isoValueString, flashDescription, etc.)

// MARK: - Helpers (unchanged)
func isoValueString(_ isoValue: Any) -> String {
    if let intVal = isoValue as? Int { return "\(intVal)" }
    if let num = isoValue as? NSNumber { return "\(num.intValue)" }
    if let arr = isoValue as? [Any], let first = arr.first {
        if let n = first as? NSNumber { return "\(n.intValue)" }
        else { return "\(first)" }
    }
    if let nsArr = isoValue as? NSArray, let first = nsArr.firstObject {
        if let n = first as? NSNumber { return "\(n.intValue)" }
        else { return "\(first)" }
    }
    return "\(isoValue)"
}
func flashDescription(_ value: Int) -> String {
    switch value {
    case 0: return "No Flash"
    case 1: return "Flash Fired"
    case 5: return "Flash Fired (No Return)"
    case 7: return "Flash Fired, Return Detected"
    default: return "Flash Info: \(value)"
    }
}
func exposureProgramDescription(_ value: Int) -> String {
    switch value {
    case 1: return "Manual"
    case 2: return "Program AE"
    case 3: return "Aperture Priority"
    case 4: return "Shutter Priority"
    case 5: return "Creative Program"
    case 6: return "Action Program"
    case 7: return "Portrait Mode"
    case 8: return "Landscape Mode"
    default: return "Unknown Program"
    }
}
func meteringModeDescription(_ value: Int) -> String {
    switch value {
    case 1: return "Average"
    case 2: return "Center-weighted"
    case 3: return "Spot"
    case 4: return "Multi-spot"
    case 5: return "Pattern"
    case 6: return "Partial"
    default: return "Unknown Mode"
    }
}
func formattedAperture(_ value: Any) -> String {
    if let d = value as? Double { return String(format: "%.2f", d) }
    if let n = value as? NSNumber { return String(format: "%.2f", n.doubleValue) }
    if let s = value as? String, let d = Double(s) { return String(format: "%.2f", d) }
    return "\(value)"
}
func extractAuthor(from properties: [CFString: Any]) -> String? {
    if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
       let artist = tiff[kCGImagePropertyTIFFArtist] as? String, !artist.isEmpty {
        return artist
    }
    if let iptc = properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any] {
        if let byline = iptc[kCGImagePropertyIPTCByline] as? String, !byline.isEmpty { return byline }
        if let arr = iptc[kCGImagePropertyIPTCByline] as? [String], let first = arr.first, !first.isEmpty { return first }
        if let writer = iptc[kCGImagePropertyIPTCWriterEditor] as? String, !writer.isEmpty { return writer }
    }
    return nil
}

func getEmbeddedJPEGPreviewSize(_ url: URL) -> CGSize? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let count = CGImageSourceGetCount(src)
    guard count > 1 else { return nil }
    var biggest: CGSize?
    for i in 1..<count {
        if let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any],
           let w = props[kCGImagePropertyPixelWidth] as? Int,
           let h = props[kCGImagePropertyPixelHeight] as? Int,
           w > 0, h > 0 {
            if let big = biggest {
                if w * h > Int(big.width * big.height) {
                    biggest = CGSize(width: w, height: h)
                }
            } else {
                biggest = CGSize(width: w, height: h)
            }
        }
    }
    return biggest
}

func displayBaseFilename(from url: URL) -> String {
    var filename = url.lastPathComponent
    // Loop to remove ALL leading "<uuid>-" prefixes
    while filename.count > 37, filename.prefix(36).allSatisfy({ $0.isHexDigit || $0 == "-" }) {
        let uuidCandidate = String(filename.prefix(36))
        if UUID(uuidString: uuidCandidate) != nil, filename.dropFirst(36).first == "-" {
            filename = String(filename.dropFirst(37))
        } else {
            break
        }
    }
    return filename
}


import SwiftUI

extension View {
    /// Apply `transform(self)` when `condition` is true, otherwise return `self`.
    @ViewBuilder
    func applyIf<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
