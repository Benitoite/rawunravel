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

// MARK: - Imports

import SwiftUI
import UniformTypeIdentifiers

// MARK: - JPEGDocument (for SwiftUI file export)

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

// MARK: - ExportJPGView (Export dialog for processed RAW output)

struct ExportJPGView: View {
    // MARK: Props (input)
    let rawFileURL: URL                        // Source RAW file path
    let pp3String: String                      // RT settings string (.pp3)
    let cropRectInPreview: CGRect?             // Crop area in preview space (UI)
    let previewFrame: CGSize?                  // Geometry frame size at crop time (UI)
    let previewUIImageSize: CGSize?            // Preview UIImage dimensions (px)
    let previewUIImage: UIImage?               // UI overlay: low-res preview
    let rawImageSize: CGSize                   // True RAW file dimensions (metadata)
    var onComplete: (() -> Void)? = nil        // Callback after export or cancel

    // MARK: - State
    @State private var basename: String = ""   // Output file basename
    @State private var quality = 85            // JPEG quality 1–100
    @State private var maxEdge = 2048          // Output long edge px

    @State private var exportImage: UIImage?   // Exported output image
    @State private var exportDocument: JPEGDocument? = nil
    @State private var showExporter = false    // Present .jpg file exporter

    @State private var isProcessingExport = false
    @State private var finishedExport = false
    @State private var toastMessage: String = ""

    // MARK: - Main View

    var body: some View {
        NavigationView {
            ZStack {
                // MARK: - Export Progress Overlay
                if isProcessingExport {
                    Color.black.opacity(0.4).ignoresSafeArea()
                        .zIndex(998)
                    VStack(spacing: 18) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .yellow))
                            .scaleEffect(2)
                        Text("Exporting…")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding(.vertical, 28)
                    .padding(.horizontal, 40)
                    .background(Color.black.opacity(0.85))
                    .cornerRadius(20)
                    .shadow(radius: 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(999)
                }
                // MARK: - Export Form
                Form {
                    exportOptionsSection
                    previewSection
                    exportButtonsSection
                }
                // MARK: - Toast Message Overlay
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
        }
        // MARK: - File Exporter Sheet
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .jpeg,
            defaultFilename: basename
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
        // MARK: - Set Default Basename
        .onAppear {
            if basename.isEmpty {
                basename = rawFileURL.deletingPathExtension().lastPathComponent
            }
        }
    }

    // MARK: - Export Form UI Sections

    private var exportOptionsSection: some View {
        Section(header: Text("Export Options")) {
            filenameInput
            jpegQualityInput
            longEdgeInput
        }
    }

    // MARK: Filename Input Field
    private var filenameInput: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Filename")
                .font(.caption)
                .foregroundColor(.secondary)
            TextField("Output filename (no .jpg)", text: $basename)
                .textFieldStyle(.roundedBorder)
        }
        .padding(.vertical, 2)
    }

    // MARK: JPEG Quality Selection
    private var jpegQualityInput: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("JPEG Quality")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack {
                TextField("", value: $quality, formatter: NumberFormatter())
                    .frame(width: 50)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                Stepper("", value: $quality, in: 10...100)
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: Output Size (Long Edge) Field
    private var longEdgeInput: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Long Edge (px)")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack {
                TextField("", value: $maxEdge, formatter: NumberFormatter())
                    .frame(width: 80)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                Stepper("", value: $maxEdge, in: 256...32000, step: 64)
            }
            let nativeLong = Int(max(rawImageSize.width, rawImageSize.height))
            Text("Native: \(nativeLong) px")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Preview Section (with crop overlay)
    private var previewSection: some View {
        Section(header: Text("Preview")) {
            ZStack {
                if let img = previewUIImage {
                    GeometryReader { proxy in
                        let view = previewImageView(
                            img: img,
                            proxy: proxy,
                            cropRectInPreview: cropRectInPreview,
                            previewUIImageSize: previewUIImageSize
                        )
                        view
                    }
                    .frame(height: 140)
                } else {
                    EmptyView()
                }
            }
            if let exportImage = exportImage {
                Text("Exported size: \(Int(exportImage.size.width)) x \(Int(exportImage.size.height)) px")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                EmptyView()
            }
        }
    }

    // MARK: - Export Buttons (Photos / File)
    private var exportButtonsSection: some View {
        Section(header: Text("Export")) {
            Button("Save to Photos") {
                doExport(toPhotos: true)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isProcessingExport || basename.isEmpty)

            Button("Export to File...") {
                doExport(toPhotos: false)
            }
            .buttonStyle(.bordered)
            .disabled(isProcessingExport || basename.isEmpty)
        }
    }

    // MARK: - Export Pipeline: RAW → RT → Crop → Resize → JPEG

    /// Runs the full pipeline: decodes, crops, scales, and exports the JPEG.
    func doExport(toPhotos: Bool) {
        isProcessingExport = true
        DispatchQueue.global(qos: .userInitiated).async {
            // --- Step 0: Write PP3 string to temp file ---
            let tempPP3 = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("temp-export.pp3")
            do {
                try pp3String.write(to: tempPP3, atomically: true, encoding: .utf8)
            } catch {
                DispatchQueue.main.async {
                    toastMessage = "Failed to save .pp3 file!"
                    isProcessingExport = false
                }
                return
            }
            // Step 1: Decode full-res RAW with current PP3 settings
            guard let fullRes = RTPreviewDecoder.decodeRAWPreview(
                atPath: rawFileURL.path,
                withPP3Path: tempPP3.path,
                halfSize: false
            ) else {
                DispatchQueue.main.async {
                    toastMessage = "Failed to decode RAW."
                    isProcessingExport = false
                }
                return
            }
            var exportImg = fullRes
            // Step 2: Crop if a region was selected (mapping UI crop to RAW px)
            if let cropRect = cropRectInPreview, let previewSz = previewUIImageSize {
                let scaleX = rawImageSize.width / previewSz.width
                let scaleY = rawImageSize.height / previewSz.height
                let intCrop = CGRect(
                    x: cropRect.origin.x * scaleX,
                    y: cropRect.origin.y * scaleY,
                    width: cropRect.size.width * scaleX,
                    height: cropRect.size.height * scaleY
                ).integral
                let finalCrop = intCrop.intersection(CGRect(origin: .zero, size: rawImageSize))
                exportImg = fullRes.cropped(to: finalCrop)
            }

            // Step 3: Resize output to requested long edge (up/down)
            let w = exportImg.size.width, h = exportImg.size.height
            let longEdge = max(w, h)
            if longEdge != CGFloat(maxEdge) {
                let scale = CGFloat(maxEdge) / longEdge
                let newSize = CGSize(width: w * scale, height: h * scale)
                UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
                exportImg.draw(in: CGRect(origin: .zero, size: newSize))
                let result = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()
                exportImg = result ?? exportImg
            }

            // Step 4: Save to Photos or present .jpg export sheet (main thread)
            DispatchQueue.main.async {
                if toPhotos {
                    UIImageWriteToSavedPhotosAlbum(exportImg, nil, nil, nil)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    toastMessage = "Saved to Photos!"
                    finishedExport = true
                    isProcessingExport = false
                } else {
                    self.exportImage = exportImg
                    if let jpegData = exportImg.jpegData(compressionQuality: CGFloat(quality) / 100.0) {
                        self.exportDocument = JPEGDocument(data: jpegData)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            self.isProcessingExport = false
                            self.showExporter = true
                        }
                    } else {
                        isProcessingExport = false
                        toastMessage = "Export failed!"
                        finishedExport = true
                    }
                }
            }
        }
    }
}

// MARK: - UIImage Cropping Helper

extension UIImage {
    /// Crops image to a CGRect (used for mapping UI crop to export)
    func cropped(to rect: CGRect) -> UIImage {
        guard let cgImage = self.cgImage,
              let cropped = cgImage.cropping(to: rect) else {
            return self
        }
        return UIImage(cgImage: cropped, scale: self.scale, orientation: self.imageOrientation)
    }
}

// MARK: - Crop Mapping Helper

/// Map a crop rect from UI/preview coordinates to full RAW pixel space.
/// Used if a future pipeline step needs more complex crop logic.
fileprivate func mappedCropRectForExport(
    cropRectInPreviewFrame: CGRect,
    previewFrame: CGSize,
    previewImageSize: CGSize,
    fullImageSize: CGSize
) -> CGRect {
    let scaleW = previewFrame.width / previewImageSize.width
    let scaleH = previewFrame.height / previewImageSize.height
    let contentScale = min(scaleW, scaleH)
    let contentSize = CGSize(width: previewImageSize.width * contentScale, height: previewImageSize.height * contentScale)
    let contentOrigin = CGPoint(
        x: (previewFrame.width - contentSize.width) / 2,
        y: (previewFrame.height - contentSize.height) / 2
    )
    let cropInContentX = cropRectInPreviewFrame.origin.x - contentOrigin.x
    let cropInContentY = cropRectInPreviewFrame.origin.y - contentOrigin.y
    let scaleToImageX = previewImageSize.width / contentSize.width
    let scaleToImageY = previewImageSize.height / contentSize.height
    let cropInImage = CGRect(
        x: cropInContentX * scaleToImageX,
        y: cropInContentY * scaleToImageY,
        width: cropRectInPreviewFrame.width * scaleToImageX,
        height: cropRectInPreviewFrame.height * scaleToImageY
    )
    let scaleX = fullImageSize.width / previewImageSize.width
    let scaleY = fullImageSize.height / previewImageSize.height
    let fullCrop = CGRect(
        x: cropInImage.origin.x * scaleX,
        y: cropInImage.origin.y * scaleY,
        width: cropInImage.width * scaleX,
        height: cropInImage.height * scaleY
    )
    return fullCrop
}

// MARK: - Preview Image Rendering Helper

/// Renders the preview image and draws the crop rectangle overlay if present.
private func previewImageView(
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
            let scaleX = drawRect.width / (previewUIImageSize?.width ?? imgSize.width)
            let scaleY = drawRect.height / (previewUIImageSize?.height ?? imgSize.height)
            let rect = CGRect(
                x: drawRect.origin.x + crop.origin.x * scaleX,
                y: drawRect.origin.y + crop.origin.y * scaleY,
                width: crop.width * scaleX,
                height: crop.height * scaleY
            )
            Path { path in
                path.addRect(rect)
            }
            .stroke(Color.yellow, lineWidth: 2)
        }
    }
}

// MARK: - Utility: Intersect crop with image bounds

func intersectCropRect(_ crop: CGRect, imageSize: CGSize) -> CGRect {
    let imageRect = CGRect(origin: .zero, size: imageSize)
    return crop.intersection(imageRect)
}
