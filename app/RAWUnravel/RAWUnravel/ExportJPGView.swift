/*
    RawUnravel - ExportJPGView.swift
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

import SwiftUI
import UniformTypeIdentifiers
import UIKit
import ImageIO

// MARK: - Progress Notification Name

extension Notification.Name {
    static let rawUnravelProgress = Notification.Name("RawUnravelProgress")
}

// MARK: - UIImage helpers

extension UIImage {
    /// Returns a new UIImage cropped to the specified CGRect in pixel coordinates.
    func cropped(to rect: CGRect) -> UIImage {
        guard let cgImage = self.cgImage else { return self }
        let bounded = CGRect(
            x: max(0, rect.origin.x),
            y: max(0, rect.origin.y),
            width: min(rect.width,  CGFloat(cgImage.width)  - rect.origin.x),
            height: min(rect.height, CGFloat(cgImage.height) - rect.origin.y)
        ).integral
        guard bounded.width > 0, bounded.height > 0,
              let croppedCGImage = cgImage.cropping(to: bounded) else { return self }
        return UIImage(cgImage: croppedCGImage, scale: 1.0, orientation: self.imageOrientation)
    }
}

/// Get pixel size of a UIImage (falls back to size*scale when needed).
fileprivate func pixelSize(of image: UIImage) -> CGSize {
    if let cg = image.cgImage { return CGSize(width: cg.width, height: cg.height) }
    return CGSize(width: image.size.width * image.scale,
                  height: image.size.height * image.scale)
}

// MARK: - Preview Image Rendering Helper

func previewImageView(
    img: UIImage,
    proxy: GeometryProxy,
    cropRectInPreview: CGRect?,
    previewUIImageSize: CGSize?
) -> some View {
    let imgSize = img.size
    let boxW = proxy.size.width
    let boxH = proxy.size.height
    let imgAspect = imgSize.width / imgSize.height
    let boxAspect = boxW / boxH
    let drawRect: CGRect
    if imgAspect > boxAspect {
        let scale = boxW / imgSize.width
        let scaledH = imgSize.height * scale
        drawRect = CGRect(x: 0, y: (boxH - scaledH)/2, width: boxW, height: scaledH)
    } else {
        let scale = boxH / imgSize.height
        let scaledW = imgSize.width * scale
        drawRect = CGRect(x: (boxW - scaledW)/2, y: 0, width: scaledW, height: boxH)
    }
    return ZStack {
        Image(uiImage: img)
            .resizable()
            .scaledToFit()
            .frame(width: boxW, height: boxH)
        if let crop = cropRectInPreview, crop.width > 0, crop.height > 0 {
            let base = previewUIImageSize ?? img.size
            let scaleX = drawRect.width  / base.width
            let scaleY = drawRect.height / base.height
            let rect = CGRect(
                x: drawRect.origin.x + crop.origin.x * scaleX,
                y: drawRect.origin.y + crop.origin.y * scaleY,
                width:  crop.width  * scaleX,
                height: crop.height * scaleY
            )
            Path { $0.addRect(rect) }
                .stroke(Color.yellow, lineWidth: 2)
        }
    }
}

// MARK: - Generic Data Document (works for JPEG/PNG/TIFF)

struct DataDocument: FileDocument {
    static var readableContentTypes: [UTType] = [.data, .jpeg, .png, .tiff]
    static var writableContentTypes: [UTType] { [.data, .jpeg, .png, .tiff] }

    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - ExportOptionsSection

struct ExportOptionsSection: View {
    @Binding var basename: String
    @Binding var quality: Int
    @Binding var maxEdge: Int
    @Binding var useNativeSize: Bool
    @Binding var outputFormat: ExportJPGView.OutputFormat
    @Binding var pngCompression: Int
    var nativePixels: Int

    var body: some View {
        Section(header: Text("Export Options")) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Filename").font(.caption).foregroundColor(.secondary)
                TextField("Output filename (no ext)", text: $basename)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .padding(.horizontal, 4)
            }
            .padding(.vertical, 6)

            Picker("Format", selection: $outputFormat) {
                ForEach(ExportJPGView.OutputFormat.allCases) { format in
                    Text(format.rawValue).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .padding(.vertical, 4)

            if outputFormat == .jpeg {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("JPEG Quality").font(.caption).foregroundColor(.secondary)
                        TextField("", value: $quality, formatter: NumberFormatter())
                            .frame(width: 60)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                    }
                    Spacer(minLength: 16)
                    Stepper("", value: $quality, in: 10...100)
                        .frame(width: 120, alignment: .trailing)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
            } else if outputFormat == .png {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PNG Compression").font(.caption).foregroundColor(.secondary)
                        Picker("Compression", selection: $pngCompression) {
                            ForEach(0...9, id: \.self) { Text("\($0)").tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
            } else if outputFormat == .tiff {
                Text("TIFF will export as 16-bit lossless (no compression).")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 6)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Long Edge (px)").font(.caption).foregroundColor(.secondary)
                    if useNativeSize {
                        Text("Native")
                            .font(.body)
                            .foregroundColor(.primary)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                            .onTapGesture { useNativeSize = false }
                    } else {
                        TextField("", value: $maxEdge, formatter: NumberFormatter())
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                    }
                }
                Spacer(minLength: 16)
                Stepper("", value: $maxEdge, in: 256...32000, step: 64)
                    .frame(width: 120, alignment: .trailing)
                    .disabled(useNativeSize)
                    .contentShape(Rectangle())
                    .onTapGesture { if useNativeSize { useNativeSize = false } }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)

            HStack(spacing: 8) {
                Text("Native: \(nativePixels) px")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Button(action: { useNativeSize = true }) {
                    Text("Use Native")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .cornerRadius(6)
                }
                .disabled(useNativeSize)
                if useNativeSize {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                        .transition(.opacity)
                }
            }
            .padding(.top, 6)
            .padding(.leading, 2)
        }
        .padding(.horizontal, 12)
    }
}

// MARK: - PreviewSection

struct PreviewSection: View {
    let previewUIImage: UIImage?
    let cropRectInPreview: CGRect?
    let previewUIImageSize: CGSize?
    let exportImage: UIImage?

    var body: some View {
        Section(header: Text("Preview")) {
            ZStack {
                if let img = previewUIImage {
                    GeometryReader { proxy in
                        previewImageView(
                            img: img,
                            proxy: proxy,
                            cropRectInPreview: cropRectInPreview,
                            previewUIImageSize: previewUIImageSize
                        )
                    }
                    .frame(height: 140)
                }
            }
            if let exportImage = exportImage {
                let px = pixelSize(of: exportImage)
                Text("Exported size: \(Int(px.width)) x \(Int(px.height)) px")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - ExportJPGView (properties, init, UI, progress wiring)

struct ExportJPGView: View {
    let rawFileURL: URL
    let pp3String: String
    let cropRectInPreview: CGRect?
    let previewFrame: CGSize?
    let previewUIImageSize: CGSize?
    let previewUIImage: UIImage?
    let rawImageSize: CGSize
    let sourceBitmap: UIImage?          // if non-RAW export, pass the bitmap
    var onComplete: (() -> Void)? = nil

    // Decide mode once:
    private var isBitmapMode: Bool {
        if sourceBitmap != nil { return true }
        return !(UTType(filenameExtension: rawFileURL.pathExtension.lowercased())?
                    .conforms(to: .rawImage) ?? false)
    }

    // MARK: - State
    @State private var basename: String = ""
    @State private var quality = 85
    @State private var maxEdge = 2048

    @State private var exportImage: UIImage?
    @State private var exportDocument: DataDocument? = nil
    @State private var showExporter = false

    @State private var isProcessingExport = false
    @State private var finishedExport = false
    @State private var toastMessage: String = ""

    @State private var useNativeSize = false
    @State private var pngCompression: Int = 3
    @State private var outputFormat: OutputFormat = .jpeg
    @State private var stepText: String = ""
    @State private var substepText: String = ""
    @State private var livePreview: UIImage? = nil
    @State private var previewSeq: Int = 0   // last-wins guard
    @State private var exportJobID = UUID().uuidString  // unique per export
    
    private let kLastJPEGQualityKey = "RawUnravel_LastJPEGQuality"
  
    enum OutputFormat: String, CaseIterable, Identifiable {
        case jpeg = "JPEG"
        case png  = "PNG"
        case tiff = "TIFF"
        var id: String { rawValue }
    }

    // MARK: - Derived

    // Native pixels (long edge)
    private var nativePixels: Int {
        if isBitmapMode {
            if let src = sourceBitmap ?? previewUIImage {
                let px = pixelSize(of: src)
                return Int(max(px.width, px.height))
            }
            return 0
        } else {
            if let crop = cropRectInPreview, let prev = previewUIImageSize, prev.width > 0, prev.height > 0 {
                let w = crop.width  * (rawImageSize.width  / prev.width)
                let h = crop.height * (rawImageSize.height / prev.height)
                return Int(max(w.rounded(), h.rounded()))
            } else {
                return Int(max(rawImageSize.width, rawImageSize.height))
            }
        }
    }

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private var selectedUTType: UTType {
        switch outputFormat {
        case .jpeg: return .jpeg
        case .png:  return .png
        case .tiff: return .tiff
        }
    }
    private func cleanedBasename(from url: URL) -> String {
        // Remove extension first
        let name = url.deletingPathExtension().lastPathComponent
        // If matches UUID- prefix, strip it
        let pattern = #"^[0-9A-Fa-f\-]{36,}-(.+)$"#
        if let re = try? NSRegularExpression(pattern: pattern),
           let match = re.firstMatch(in: name, options: [], range: NSRange(location: 0, length: name.utf16.count)),
           let range = Range(match.range(at: 1), in: name) {
            return String(name[range])
        }
        return name
    }
    private var cleanBasename: String {
        // Remove leading UUID if present (36 chars + dash)
        let regex = try! NSRegularExpression(pattern: #"^[0-9a-fA-F\-]{36,}_?"#)
        let name = basename.isEmpty
            ? cleanedBasename(from: rawFileURL)
            : basename
        let range = NSRange(name.startIndex..., in: name)
        let clean = regex.stringByReplacingMatches(in: name, options: [], range: range, withTemplate: "")
        // Remove any illegal file system characters just in case
        return clean.replacingOccurrences(of: "/", with: "_")
    }

    private var defaultFileNameWithExt: String {
        let ext: String = {
            switch outputFormat {
            case .jpeg: return "jpg"
            case .png:  return "png"
            case .tiff: return "tiff"
            }
        }()
        return "\(cleanBasename).\(ext)"
    }

    private var bentoPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ExportOptionsSection(
                        basename: $basename,
                        quality: $quality,
                        maxEdge: $maxEdge,
                        useNativeSize: $useNativeSize,
                        outputFormat: $outputFormat,
                        pngCompression: $pngCompression,
                        nativePixels: nativePixels
                    )
                }
                .padding(.top, 18)
                .padding(.horizontal, 14)
            }
            Divider().padding(.vertical, 2)
            HStack(spacing: 16) {
                Button("Save to Photos") { doExport(toPhotos: true) }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(isProcessingExport || basename.isEmpty)
                Button("Export to File...") { doExport(toPhotos: false) }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    .disabled(isProcessingExport || basename.isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.thinMaterial)
            .cornerRadius(14)
        }
        .frame(maxWidth: isPad ? 750 : 420)
        .background(Color(UIColor.secondarySystemBackground))
    }

    private var previewPanel: some View {
        VStack {
            PreviewSection(
                previewUIImage: previewUIImage,
                cropRectInPreview: cropRectInPreview,
                previewUIImageSize: previewUIImageSize,
                exportImage: exportImage
            )
            .padding(.top, 16)
            .padding(.horizontal, 12)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
    }

    // MARK: - View

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            let useTwoColumns = isPad || isLandscape

            NavigationView {
                ZStack {
                    if isProcessingExport {
                        Color.black.opacity(0.4).ignoresSafeArea()
                            .zIndex(998)
                        VStack(spacing: 10) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .yellow))
                                .scaleEffect(2)
                            Text("Exporting…")
                                .font(.headline)
                                .foregroundColor(.white)
                            if !stepText.isEmpty {
                                Text(stepText)
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            if !substepText.isEmpty {
                                Text(substepText)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        .padding(.vertical, 22)
                        .padding(.horizontal, 28)
                        .background(Color.black.opacity(0.85))
                        .cornerRadius(16)
                        .shadow(radius: 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .zIndex(999)
                    }

                    if useTwoColumns {
                        HStack(spacing: 0) {
                            bentoPanel
                            Divider()
                            previewPanel
                        }
                    } else {
                        Form {
                            ExportOptionsSection(
                                basename: $basename,
                                quality: $quality,
                                maxEdge: $maxEdge,
                                useNativeSize: $useNativeSize,
                                outputFormat: $outputFormat,
                                pngCompression: $pngCompression,
                                nativePixels: nativePixels
                            )
                            PreviewSection(
                                previewUIImage: previewUIImage,
                                cropRectInPreview: cropRectInPreview,
                                previewUIImageSize: previewUIImageSize,
                                exportImage: exportImage
                            )
                            HStack(spacing: 14) {
                                Button("Save to Photos") { doExport(toPhotos: true) }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(isProcessingExport || basename.isEmpty)
                                Button("Export to File...") { doExport(toPhotos: false) }
                                    .buttonStyle(.bordered)
                                    .disabled(isProcessingExport || basename.isEmpty)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 10)
                            .background(.thinMaterial)
                            .cornerRadius(14)
                        }
                    }

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
                .navigationTitle("Export Image")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { onComplete?() }
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
            }
            .fileExporter(
                isPresented: $showExporter,
                document: exportDocument,
                contentType: selectedUTType,
                defaultFilename: defaultFileNameWithExt
            ) { result in
                exportDocument = nil
                switch result {
                case .success(let url):
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    toastMessage = "Export successful!\n\(url.lastPathComponent)"
                    finishedExport = true
                case .failure:
                    toastMessage = "Export failed!"
                    finishedExport = true
                }
            }
            .onAppear {
                if basename.isEmpty {
                    basename = cleanedBasename(from: rawFileURL)
                }
                if let savedQuality = UserDefaults.standard.object(forKey: kLastJPEGQualityKey) as? Int {
                    quality = savedQuality
                }
            }
        }
        .onChange(of: quality) {
            UserDefaults.standard.set(quality, forKey: kLastJPEGQualityKey)
        }
        .onReceive(NotificationCenter.default.publisher(for: .rawUnravelProgress)
            .receive(on: RunLoop.main)) { note in
            guard let u = note.userInfo as? [String: Any],
                  (u["job"] as? String) == exportJobID,
                  let phase = u["phase"] as? String
            else { return }

            let step  = (u["step"]  as? String) ?? ""
            let iter  = (u["iter"]  as? Int) ?? 0
            let total = (u["total"] as? Int) ?? 0

            switch phase {
            case "libraw":
                setStep([
                    "open":"Opening RAW…","identify":"Reading metadata…",
                    "unpack":"Unpacking sensor data…","demosaic":"Demosaicing…",
                    "convert_rgb":"Converting to RGB…","finish":"Finalizing decode…"
                ][step] ?? "Decoding RAW…")

            case "rld":
                if step == "iter" {
                    // show even when iter==0 (start) or total==0 (defensive)
                    let sub = total > 0 ? "RLD \(iter)/\(total)" : nil
                    setStep("Applying RLD sharpening…", sub: sub)
                } else if step == "skip" {
                    // no RLD -> still move on visually
                    setStep("Sharpening disabled")
                }

            default: break
            }
        }
    }

        // MARK: - Encoding (sRGB-tagged CGImageDestination path)

        private func encodeData(for image: UIImage,
                                outputFormat: OutputFormat,
                                quality: Int,
                                pngCompression: Int) -> Data? {
            guard let cg = image.cgImage else { return nil }

            // Ensure sRGB-tagged CGImage (UIImage can be DeviceRGB)
            let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
            let bitmapInfo: CGBitmapInfo = [
                CGBitmapInfo.byteOrder32Big,
                CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            ]
            let srgbCG: CGImage
            if cg.colorSpace?.name != cs.name {
                guard let ctx = CGContext(
                    data: nil,
                    width: cg.width,
                    height: cg.height,
                    bitsPerComponent: 8,
                    bytesPerRow: cg.width * 4,
                    space: cs,
                    bitmapInfo: bitmapInfo.rawValue
                ) else { return nil }
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
                guard let rebuilt = ctx.makeImage() else { return nil }
                srgbCG = rebuilt
            } else {
                srgbCG = cg
            }

            // Encode via CGImageDestination
            let data = NSMutableData()
            let ut: CFString
            switch outputFormat {
            case .jpeg: ut = UTType.jpeg.identifier as CFString
            case .png:  ut = UTType.png.identifier  as CFString
            case .tiff: ut = UTType.tiff.identifier as CFString
            }

            guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, ut, 1, nil) else {
                return nil
            }

            var props: [CFString: Any] = [:]
            props[kCGImagePropertyProfileName] = "sRGB IEC61966-2.1"

            switch outputFormat {
            case .jpeg:
                let q = max(10, min(100, quality))
                props[kCGImageDestinationLossyCompressionQuality] = CGFloat(q) / 100.0
            case .png:
                props[kCGImagePropertyPNGDictionary] = [
                    kCGImagePropertyPNGCompressionFilter as String: pngCompression
                ]
            case .tiff:
                // NOTE: This 8-bit TIFF path is used only for bitmap mode.
                // RAW→TIFF uses the dedicated 16-bit path below.
                props[kCGImagePropertyTIFFDictionary] = [
                    kCGImagePropertyTIFFCompression as String: 1 // None
                ]
            }

            CGImageDestinationAddImage(dest, srgbCG, props as CFDictionary)
            CGImageDestinationFinalize(dest)
            return data as Data
        }

        // MARK: - Export Pipeline

        private func setStep(_ main: String, sub: String? = nil) {
            DispatchQueue.main.async {
                self.stepText = main
                self.substepText = sub ?? ""
            }
        }

        func doExport(toPhotos: Bool) {
            exportJobID = UUID().uuidString
            isProcessingExport = true

            DispatchQueue.global(qos: .userInitiated).async {
                // ===== BITMAP MODE =====
                if self.isBitmapMode {
                    self.setStep("Preparing bitmap…")
                    guard var exportImg = self.sourceBitmap ?? self.previewUIImage else {
                        DispatchQueue.main.async {
                            self.toastMessage = "No image to export."
                            self.isProcessingExport = false
                        }
                        return
                    }
                    exportImg = bakeOrientationUp(exportImg)

                    // Crop (preview -> source pixels)
                    if let cropRect = self.cropRectInPreview,
                       let previewSz = self.previewUIImageSize,
                       previewSz.width > 0, previewSz.height > 0 {
                        self.setStep("Cropping…")
                        let fullPx = pixelSize(of: exportImg)
                        let scaleX = fullPx.width  / previewSz.width
                        let scaleY = fullPx.height / previewSz.height
                        let mapped = CGRect(
                            x: cropRect.origin.x * scaleX,
                            y: cropRect.origin.y * scaleY,
                            width:  cropRect.size.width  * scaleX,
                            height: cropRect.size.height * scaleY
                        ).integral
                        exportImg = exportImg.cropped(to: mapped.intersection(CGRect(origin: .zero, size: fullPx)))
                    }

                    // Resize
                    if !self.useNativeSize {
                        self.setStep("Resizing to \(self.maxEdge) px…")
                        exportImg = resizePixels(exportImg, longEdge: self.maxEdge)
                    }

                    // Encode (8-bit JPEG/PNG/TIFF)
                    self.setStep("Encoding \(self.outputFormat.rawValue)…")
                    guard let data = self.encodeData(for: exportImg,
                                                     outputFormat: self.outputFormat,
                                                     quality: self.quality,
                                                     pngCompression: self.pngCompression) else {
                        DispatchQueue.main.async {
                            self.isProcessingExport = false
                            self.toastMessage = "Encoding failed."
                            self.finishedExport = true
                        }
                        return
                    }

                    DispatchQueue.main.async {
                        if toPhotos {
                            self.setStep("Saving to Photos…")
                            UIImageWriteToSavedPhotosAlbum(exportImg, nil, nil, nil)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            self.toastMessage = "Saved to Photos!"
                            self.finishedExport = true
                            self.isProcessingExport = false
                        } else {
                            self.exportImage = exportImg
                            self.exportDocument = DataDocument(data: data)
                            self.showExporter = true
                            self.isProcessingExport = false
                        }
                    }
                    return
                }

                // ===== RAW MODE =====
                self.setStep("Writing settings (.pp3)…")
                let tempPP3 = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("temp-export-\(UUID().uuidString).pp3")
                do {
                    try self.pp3String.write(to: tempPP3, atomically: true, encoding: .utf8)
                } catch {
                    DispatchQueue.main.async {
                        self.toastMessage = "Failed to save .pp3 file!"
                        self.isProcessingExport = false
                    }
                    return
                }

                let rldIters = rldIterationsFromPP3(self.pp3String)
                self.setStep("Decoding RAW (full-res)…",
                        sub: rldIters != nil ? "RLD sharpening: \(rldIters!) iterations" : "")

                // --- TIFF 16-bit (no compression) path ---
                if self.outputFormat == .tiff {
                    // Create 16-bit CGImage via Obj-C bridge
                    guard let cg16 = RTPreviewDecoder.createCGImage16FromRAW(
                            atPath: self.rawFileURL.path,
                            jobID: self.exportJobID
                        ) else {
                        DispatchQueue.main.async {
                            self.toastMessage = "Failed to decode RAW (16-bit)."
                            self.isProcessingExport = false
                        }
                        return
                    }

                    var workCG: CGImage? = cg16

                    // Crop (preview -> full-res pixels) in 16-bit space
                    if let cropRect = self.cropRectInPreview,
                       let previewSz = self.previewUIImageSize,
                       previewSz.width > 0, previewSz.height > 0,
                       let cg0 = workCG {
                        self.setStep("Cropping…")
                        let fullPx = pixelSize(of: cg0)
                        let scaleX = fullPx.width  / previewSz.width
                        let scaleY = fullPx.height / previewSz.height
                        let mapped = CGRect(
                            x: cropRect.origin.x * scaleX,
                            y: cropRect.origin.y * scaleY,
                            width:  cropRect.size.width  * scaleX,
                            height: cropRect.size.height * scaleY
                        )
                        workCG = cropCGImage(cg0, to: mapped) ?? cg0
                    }

                    // Optional resize in 16-bit space
                    if !self.useNativeSize, let cg0 = workCG {
                        self.setStep("Resizing to \(self.maxEdge) px…")
                        workCG = resizeCGImage16(cg0, longEdge: self.maxEdge) ?? cg0
                    }

                    guard let finalCG = workCG,
                          let data = encodeTIFF16NoCompression(finalCG) else {
                        DispatchQueue.main.async {
                            self.isProcessingExport = false
                            self.toastMessage = "TIFF encoding failed."
                            self.finishedExport = true
                        }
                        return
                    }

                    DispatchQueue.main.async {
                        self.exportImage = UIImage(cgImage: finalCG) // for size label only
                        self.exportDocument = DataDocument(data: data)
                        self.showExporter = true
                        self.isProcessingExport = false
                    }
                    return
                }

                // --- JPEG/PNG (8-bit) path using UIImage decode ---
                guard var exportImg = RTPreviewDecoder.decodeRAWPreview(
                    atPath: self.rawFileURL.path,
                    withPP3Path: tempPP3.path,
                    halfSize: false,
                    jobID: self.exportJobID
                ) else {
                    DispatchQueue.main.async {
                        self.toastMessage = "Failed to decode RAW."
                        self.isProcessingExport = false
                    }
                    return
                }
                exportImg = bakeOrientationUp(exportImg)

                // Crop (preview -> full-res pixels)
                if let cropRect = self.cropRectInPreview,
                   let previewSz = self.previewUIImageSize,
                   previewSz.width > 0, previewSz.height > 0 {
                    self.setStep("Cropping…")
                    let fullPx = pixelSize(of: exportImg)
                    let scaleX = fullPx.width  / previewSz.width
                    let scaleY = fullPx.height / previewSz.height
                    let mapped = CGRect(
                        x: cropRect.origin.x * scaleX,
                        y: cropRect.origin.y * scaleY,
                        width:  cropRect.size.width  * scaleX,
                        height: cropRect.size.height * scaleY
                    ).integral
                    exportImg = exportImg.cropped(to: mapped.intersection(CGRect(origin: .zero, size: fullPx)))
                }

                // Resize
                if !self.useNativeSize {
                    self.setStep("Resizing to \(self.maxEdge) px…")
                    exportImg = resizePixels(exportImg, longEdge: self.maxEdge)
                }

                // Encode (8-bit)
                self.setStep("Encoding \(self.outputFormat.rawValue)…")
                guard let data = self.encodeData(for: exportImg,
                                                 outputFormat: self.outputFormat,
                                                 quality: self.quality,
                                                 pngCompression: self.pngCompression) else {
                    DispatchQueue.main.async {
                        self.isProcessingExport = false
                        self.toastMessage = "Encoding failed."
                        self.finishedExport = true
                    }
                    return
                }

                DispatchQueue.main.async {
                    if toPhotos {
                        self.setStep("Saving to Photos…")
                        UIImageWriteToSavedPhotosAlbum(exportImg, nil, nil, nil)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        self.toastMessage = "Saved to Photos!"
                        self.finishedExport = true
                        self.isProcessingExport = false
                    } else {
                        self.exportImage = exportImg
                        self.exportDocument = DataDocument(data: data)
                        self.showExporter = true
                        self.isProcessingExport = false
                    }
                }
            }
        }

        // MARK: - Labels (optional, not used directly in UI)
        private func labelFor(phase: String, step: String) -> String {
            switch (phase, step) {
            case ("libraw","open"):        return "Opening RAW…"
            case ("libraw","identify"):    return "Reading metadata…"
            case ("libraw","unpack"):      return "Unpacking sensor data…"
            case ("libraw","demosaic"):    return "Demosaicing…"
            case ("libraw","convert_rgb"): return "Converting to RGB…"
            case ("rld","iter"):           return "RLD sharpening…"
            default:                       return "Exporting…"
            }
        }
    }

// MARK: - Helpers

private func resizePixels(_ image: UIImage, longEdge: Int) -> UIImage {
    let srcPx = pixelSize(of: image)
    let srcLong = max(srcPx.width, srcPx.height)
    if Int(srcLong.rounded()) == longEdge { return image }
    let s = CGFloat(longEdge) / srcLong
    let newPx = CGSize(width: srcPx.width * s, height: srcPx.height * s)

    let format = UIGraphicsImageRendererFormat()
    format.scale = 1.0 // draw in pixel space
    let renderer = UIGraphicsImageRenderer(size: newPx, format: format)
    return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newPx)) }
}

// Parse "DeconvIterations" (and the legacy "RLDeconvIterations") from a .pp3
private func rldIterationsFromPP3(_ pp3: String) -> Int? {
    let patterns = [
        #"(?mi)^\s*DeconvIterations\s*=\s*(\d+)\s*$"#,
        #"(?mi)^\s*RLDeconvIterations\s*=\s*(\d+)\s*$"#
    ]
    for pat in patterns {
        if let re = try? NSRegularExpression(pattern: pat) {
            let range = NSRange(pp3.startIndex..<pp3.endIndex, in: pp3)
            if let m = re.firstMatch(in: pp3, options: [], range: range),
               let r = Range(m.range(at: 1), in: pp3) {
                return Int(pp3[r])
            }
        }
    }
    return nil
}

// Pixel size of a CGImage
fileprivate func pixelSize(of cg: CGImage) -> CGSize {
    CGSize(width: cg.width, height: cg.height)
}

// Crop a 16-bit CGImage (no depth loss)
fileprivate func cropCGImage(_ cg: CGImage, to rectPx: CGRect) -> CGImage? {
    let bounded = rectPx.integral.intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
    guard bounded.width > 0, bounded.height > 0 else { return nil }
    return cg.cropping(to: bounded)
}

// Resize a 16-bit CGImage in 16-bit space (sRGB)
fileprivate func resizeCGImage16(_ cg: CGImage, longEdge: Int) -> CGImage? {
    let srcW = cg.width, srcH = cg.height
    let srcLong = max(srcW, srcH)
    if srcLong == longEdge { return cg }

    let scale = CGFloat(longEdge) / CGFloat(srcLong)
    let dstW = Int(CGFloat(srcW) * scale)
    let dstH = Int(CGFloat(srcH) * scale)

    guard let cs = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
    let bitmapInfo: CGBitmapInfo = [
        CGBitmapInfo.byteOrder16Big,
        CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    ]
    guard let ctx = CGContext(
        data: nil,
        width: dstW,
        height: dstH,
        bitsPerComponent: 16,
        bytesPerRow: dstW * 8, // RGBA 16 = 8 bytes/px
        space: cs,
        bitmapInfo: bitmapInfo.rawValue
    ) else { return nil }

    ctx.interpolationQuality = .high
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: dstW, height: dstH))
    return ctx.makeImage()
}

// 16-bit TIFF encoder (no compression), sRGB profile
fileprivate func encodeTIFF16NoCompression(_ cg: CGImage) -> Data? {
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(
        data as CFMutableData,
        UTType.tiff.identifier as CFString,
        1, nil
    ) else { return nil }

    let props: [CFString: Any] = [
        kCGImagePropertyProfileName: "sRGB IEC61966-2.1",
        kCGImagePropertyTIFFDictionary: [
            // 1 = None (uncompressed)
            kCGImagePropertyTIFFCompression as String: 1
        ]
    ]

    CGImageDestinationAddImage(dest, cg, props as CFDictionary)
    CGImageDestinationFinalize(dest)
    return data as Data
}

// Flatten orientation into .up
private func bakeOrientationUp(_ image: UIImage) -> UIImage {
    if image.imageOrientation == .up { return image }
    let px = pixelSize(of: image)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1.0
    let r = UIGraphicsImageRenderer(size: px, format: format)
    return r.image { _ in image.draw(in: CGRect(origin: .zero, size: px)) }
}

// Convenience: get EXIF orientation directly from file
private func exifOrientationFromFile(_ url: URL) -> Int {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
          let n = props[kCGImagePropertyOrientation] as? NSNumber else { return 1 }
    return n.intValue
}
