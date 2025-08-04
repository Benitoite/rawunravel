/*
    RawUnravel - DevelopScreen.swift
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

// MARK: - ScreenshotItem

/// Stores all data needed for screenshot/export flow.
/// Crop rect is in preview image coordinate space (not raw px).
struct ScreenshotItem: Identifiable {
    let id = UUID()
    let cropRect: CGRect            // Crop in preview image px
    let previewFrame: CGSize        // GeometryReader frame at screenshot time
    let previewUIImageSize: CGSize  // Preview UIImage.size at screenshot time
}

// MARK: - DevelopScreen (Main RAW Processing UI)

struct DevelopScreen: View {
    // MARK: - Input
    let fileURL: URL
    let rawImageSize: CGSize?    // Populated from RAW metadata

    // MARK: - RAW Preview & Fullres State
    @State private var previewImage: UIImage?
    @State private var fullResImage: UIImage?

    // MARK: - Zoom/Pan State
    @State private var zoom: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    // MARK: - PP3 State
    @State private var currentPP3 = ""
    @State private var exposurePP3: String = ""
    @State private var colorPP3: String = ""

    // MARK: - Screenshot & Export Sheet State
    @State private var screenshotItem: ScreenshotItem? = nil
    @State private var showExportSheet = false

    @State private var isLoading = false

    @State private var showExportSuccess = false
    @State private var screenshotForExport: UIImage?
    @State private var showScreenshotExportSheet = false

    // MARK: - Exposure/Color Panels State
    @State private var showExposurePanel = false
    @State private var exposureCompensation: Float = 0.0
    @State private var blackPoint: Float = 0.0
    @State private var shadows: Float = 0.0

    @Environment(\.presentationMode) private var presentationMode

    @State private var showRainbowPanel = false
    @State private var chromaticity: Float = 0
    @State private var cChroma: Float = 0
    @State private var jContrast: Float = 0

    // MARK: - Helper: Combine PP3 Segments
    func combinePP3() -> String {
        "\(exposurePP3)\n\(colorPP3)"
    }

    // MARK: - Main View Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GeometryReader { geo in
                ZStack {
                    // MARK: - Image + Zoomable View
                    if let ui = previewImage {
                        ZoomableImageView(
                            image: ui,
                            zoomScale: $zoom,
                            minScale: minZoomScale(for: ui.size, in: geo.size),
                            maxScale: maxZoomScale(for: ui.size, in: geo.size),
                            offset: $offset,
                            lastOffset: $lastOffset
                        )
                        // Double tap = 1:1 pixel scale (animated)
                        .simultaneousGesture(
                            TapGesture(count: 2)
                                .onEnded {
                                    withAnimation(.easeInOut) {
                                        zoom = oneToOneScale(for: ui.size)
                                        offset = .zero
                                        lastOffset = .zero
                                    }
                                }
                        )
                        // Triple tap = 1:1 scale (via RAWUnravel static method, if you ever want it different)
                        .simultaneousGesture(
                            TapGesture(count: 3)
                                .onEnded {
                                    withAnimation(.easeInOut) {
                                        zoom = RAWUnravel.oneToOneScale(for: ui.size, in: geo.size)
                                        offset = .zero
                                        lastOffset = .zero
                                    }
                                }
                        )
                    }

                    // MARK: - Loading Spinner
                    if isLoading {
                        ZStack {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                .scaleEffect(5)
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .yellow))
                                .scaleEffect(5)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.01).ignoresSafeArea())
                    }

                    // MARK: - Top-Right: Sun/Exposure and Rainbow/Color Panels
                    VStack(spacing: 12) {
                        Button(action: { showExposurePanel.toggle() }) {
                            Text("☀️")
                                .font(.system(size: 32))
                                .padding(18)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())

                        Button(action: { showRainbowPanel.toggle() }) {
                            Text("🌈")
                                .font(.system(size: 28))
                                .padding(16)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())


                        if showExposurePanel {
                            SunExposurePanel(
                                exposure: $exposureCompensation,
                                blackPoint: $blackPoint,
                                shadows: $shadows
                            ) { newPP3 in
                                exposurePP3 = newPP3
                                currentPP3 = combinePP3()
                                processRAW(with: currentPP3, halfSize: true)
                                showExposurePanel = false
                            }
                            .padding()
                            .background(Color.black.opacity(0.05))
                            .cornerRadius(10)
                            .transition(.move(edge: .trailing))
                        }

                        if showRainbowPanel {
                            RainbowColorPanel(
                                chromaticity: $chromaticity,
                                cChroma: $cChroma,
                                jContrast: $jContrast
                            ) { newPP3 in
                                colorPP3 = newPP3
                                currentPP3 = combinePP3()
                                processRAW(with: currentPP3, halfSize: true)
                                showRainbowPanel = false
                            }
                            .padding()
                            .background(Color.black.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                            .shadow(radius: 10)
                            .padding()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

                    // MARK: - Bottom-Right: Screenshot & Export Buttons
                    VStack(spacing: 8) {
                        
                        Button(action: { takeScreenshot(in: geo) }) {
                            Text("📸")
                                .font(.system(size: 32))
                                .padding(18)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())

                        Button(action: { showExportSheet = true }) {
                            Text("📤")
                                .font(.system(size: 28))
                                .padding(16)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(10)
                    .zIndex(200)
                }
            }
        }
        // MARK: - Export Sheet for Screenshot (with crop)
        .sheet(item: $screenshotItem) { item in
            if let rawImageSize = rawImageSize {
                ExportJPGView(
                    rawFileURL: fileURL,
                    pp3String: currentPP3,
                    cropRectInPreview: item.cropRect,
                    previewFrame: item.previewFrame,
                    previewUIImageSize: item.previewUIImageSize,
                    previewUIImage: previewImage,
                    rawImageSize: rawImageSize,
                    onComplete: { screenshotItem = nil }
                )
            } else {
                Text("RAW size unknown. Export not available.")
                    .padding()
                    .foregroundColor(.red)
            }
        }
        // MARK: - Export Sheet for Full Export (no crop)
        .sheet(isPresented: $showExportSheet) {
            if let rawImageSize = rawImageSize {
                ExportJPGView(
                    rawFileURL: fileURL,
                    pp3String: currentPP3,
                    cropRectInPreview: nil,
                    previewFrame: nil,
                    previewUIImageSize: previewImage?.size,
                    previewUIImage: previewImage,
                    rawImageSize: rawImageSize
                ) {
                    showExportSheet = false
                }
            } else {
                Text("RAW size unknown. Export not available.")
                    .padding()
                    .foregroundColor(.red)
            }
        }
        // MARK: - On Appear: Initial RAW Load
        .onAppear { initialLoad() }
    }

    // MARK: - Screenshot Crop & Trigger Export

    /// Captures current visible region for screenshot export (in preview px)
    private func takeScreenshot(in geo: GeometryProxy) {
        guard let lowResImage = previewImage else { return }

        let cropInImagePixels = visibleCropRectInImagePixels(
            image: lowResImage,
            geoSize: geo.size,
            zoom: zoom,
            offset: offset
        )
        screenshotItem = ScreenshotItem(
            cropRect: cropInImagePixels,
            previewFrame: geo.size,
            previewUIImageSize: lowResImage.size
        )
    }

    // MARK: - Crop Rect Mapping

    /// Returns the visible crop rect in image pixel coordinates (for screenshot/export)
    private func visibleCropRectInImagePixels(image: UIImage, geoSize: CGSize, zoom: CGFloat, offset: CGSize) -> CGRect {
        let imgSize = image.size
        let imgAspect = imgSize.width / imgSize.height
        let geoAspect = geoSize.width / geoSize.height
        let fitScale: CGFloat = imgAspect > geoAspect
            ? geoSize.width / imgSize.width
            : geoSize.height / imgSize.height
        let shownSize = CGSize(width: imgSize.width * fitScale, height: imgSize.height * fitScale)
        let displaySize = CGSize(width: shownSize.width * zoom, height: shownSize.height * zoom)
        let geoCenter = CGPoint(x: geoSize.width / 2, y: geoSize.height / 2)
        let displayOrigin = CGPoint(
            x: geoCenter.x - displaySize.width / 2 + offset.width,
            y: geoCenter.y - displaySize.height / 2 + offset.height
        )
        let imageRectInGeo = CGRect(origin: displayOrigin, size: displaySize)
        let visibleRectInGeo = CGRect(origin: .zero, size: geoSize).intersection(imageRectInGeo)
        if visibleRectInGeo.isEmpty { return .zero }

        // Map geo visible rect to image pixel space
        let x = (visibleRectInGeo.origin.x - imageRectInGeo.origin.x) * (imgSize.width / displaySize.width)
        let y = (visibleRectInGeo.origin.y - imageRectInGeo.origin.y) * (imgSize.height / displaySize.height)
        let w = visibleRectInGeo.size.width * (imgSize.width / displaySize.width)
        let h = visibleRectInGeo.size.height * (imgSize.height / displaySize.height)
        let cropRect = CGRect(
            x: x.clamped(to: 0...imgSize.width),
            y: y.clamped(to: 0...imgSize.height),
            width: min(w, imgSize.width - x),
            height: min(h, imgSize.height - y)
        )
        return cropRect
    }
    
    // MARK: - Zoom & Scale Calculators

    /// Always returns 1.0, used for 1:1 preview (pixel mapping)
    private func oneToOneScale(for imageSize: CGSize) -> CGFloat { 1.0 }

    /// Returns the scale needed to fit the image to the screen (bounding box)
    private func fitScale(for imageSize: CGSize, in geoSize: CGSize) -> CGFloat {
        let imgAspect = imageSize.width / imageSize.height
        let geoAspect = geoSize.width / geoSize.height
        if imgAspect > geoAspect {
            return geoSize.width / imageSize.width
        } else {
            return geoSize.height / imageSize.height
        }
    }

    /// Returns the minimum allowed zoom-out scale (so image isn't too small)
    private func minZoomScale(for imageSize: CGSize, in geoSize: CGSize) -> CGFloat {
        let minDim = min(imageSize.width, imageSize.height)
        guard minDim > 0 else { return 0.01 }
        return 256.0 / minDim
    }

    /// Returns the maximum allowed zoom-in scale (can be arbitrarily large)
    private func maxZoomScale(for imageSize: CGSize, in geoSize: CGSize) -> CGFloat {
        let oneToOne = oneToOneScale(for: imageSize)
        return max(oneToOne * 256, fitScale(for: imageSize, in: geoSize) * 256)
    }

    /// Clamps pan/offset to keep image edges within frame bounds at current zoom
    private func clampOffset(for zoomScale: CGFloat, in geoSize: CGSize) -> CGSize {
        guard let ui = previewImage else { return .zero }
        let scale = max(ui.size.width / geoSize.width, ui.size.height / geoSize.height)
        let dispW = ui.size.width / scale * zoomScale
        let dispH = ui.size.height / scale * zoomScale
        let maxX = max((dispW - geoSize.width)/2, 0)
        let maxY = max((dispH - geoSize.height)/2, 0)
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }

    // MARK: - RAW Preview/FullRes Processing

    /// Kicks off RAW → preview (and optionally fullres) decode using RTPreviewDecoder.
    func processRAW(with pp3String: String, halfSize: Bool = true) {
        isLoading = true
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("temp.pp3")
        try? pp3String.write(to: tmp, atomically: true, encoding: .utf8)
        DispatchQueue.global(qos: .userInitiated).async {
            // Always decode preview for UI
            let lowRes = RTPreviewDecoder.decodeRAWPreview(
                atPath: fileURL.path,
                withPP3Path: tmp.path,
                halfSize: true
            )

            // Only decode fullres if requested
            var fullRes: UIImage? = nil
            if !halfSize {
                fullRes = RTPreviewDecoder.decodeRAWPreview(
                    atPath: fileURL.path,
                    withPP3Path: tmp.path,
                    halfSize: false
                )
            }

            DispatchQueue.main.async {
                previewImage = lowRes
                if !halfSize {
                    fullResImage = fullRes
                }
                isLoading = false
            }
        }
    }

    /// Loads preview on view appear (no pp3: default dev)
    func initialLoad() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let ui = RTPreviewDecoder.decodeRAWPreview(
                atPath: fileURL.path,
                withPP3Path: "",
                halfSize: true
            )
            DispatchQueue.main.async {
                self.previewImage = ui
                self.isLoading = false
            }
        }
    }
}

// MARK: - Comparable clamp extension

extension Comparable {
    /// Clamps value to closed range.
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

// MARK: - Crop Clamping Helper

/// Ensures crop rect fits within image bounds (used for safety).
func clampCropRect(_ crop: CGRect, imageSize: CGSize) -> CGRect {
    var x = crop.origin.x.clamped(to: 0...(imageSize.width - 1))
    var y = crop.origin.y.clamped(to: 0...(imageSize.height - 1))
    let maxW = imageSize.width - x
    let maxH = imageSize.height - y
    let w = max(1, min(crop.width, maxW))
    let h = max(1, min(crop.height, maxH))
    return CGRect(x: x, y: y, width: w, height: h)
}

// MARK: - Standalone 1:1 Scale Helper

/// Returns zoom needed for a 1:1 pixel preview given screen frame.
private func oneToOneScale(for imageSize: CGSize, in geoSize: CGSize) -> CGFloat {
    let scaleX = imageSize.width / geoSize.width
    let scaleY = imageSize.height / geoSize.height
    return max(scaleX, scaleY)
}
