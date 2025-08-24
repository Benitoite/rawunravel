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
import UIKit
import AVFoundation


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
    @State private var detailsPP3: String = ""
    
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
    
    // MARK: - Details (RLD) Panel State
    @State private var showDetailsPanel = false
    @State private var rldIterations: Int = 10
    @State private var rldAmount: Float = 100      // 0…200 (percent)
    @State private var rldDamping: Float = 0       // 0…100
    @State private var rldRadius: Double = 0.8     // px at full-res
    @State private var isAdjustingRLD = false
    
    // Optional extras
    @State private var noiseReduction: Float = 0.0
    @State private var dcpDehaze: Float = 0.0
    
    @State private var cameraPlayer: AVAudioPlayer?
    @State private var showHelpSheet = false
    
    @State private var devJobID = UUID().uuidString
    
    @State private var progressPhase = ""
    @State private var progressStep  = ""
    @State private var progressIter  = 0
    @State private var progressTotal = 0
    @State private var previewJobID = UUID().uuidString
    
    @State private var vp = ViewportState(zoom: 1, offset: .zero, lastOffset: .zero, savedCenterFrac: nil, savedZoom: nil)
    
    @State private var pPhase = ""
    @State private var pStep  = ""
    @State private var pIter  = 0
    @State private var pTotal = 0
    
    @State private var lastGeoSize: CGSize = .zero
    @State private var savedCenterFrac: CGPoint? = nil  // center in image space as fraction [0,1]
    @State private var savedZoom: CGFloat? = nil
    
    private func captureViewport(for image: UIImage, in geoSize: CGSize) {
        let imgSize = image.size
        guard imgSize.width > 0, imgSize.height > 0, geoSize.width > 0, geoSize.height > 0 else { return }
        
        let imgAspect = imgSize.width / imgSize.height
        let geoAspect = geoSize.width / geoSize.height
        let fitScale: CGFloat = (imgAspect > geoAspect) ? geoSize.width / imgSize.width
        : geoSize.height / imgSize.height
        
        let shownSize   = CGSize(width: imgSize.width * fitScale, height: imgSize.height * fitScale)
        let displaySize = CGSize(width: shownSize.width * zoom, height: shownSize.height * zoom)
        let geoCenter   = CGPoint(x: geoSize.width / 2, y: geoSize.height / 2)
        let displayOrigin = CGPoint(
            x: geoCenter.x - displaySize.width / 2  + offset.width,
            y: geoCenter.y - displaySize.height / 2 + offset.height
        )
        
        let u = (geoCenter.x - displayOrigin.x) / displaySize.width
        let v = (geoCenter.y - displayOrigin.y) / displaySize.height
        
        savedCenterFrac = CGPoint(x: u.clamped(to: 0...1), y: v.clamped(to: 0...1))
        savedZoom = zoom
    }
    
    private func restoreViewport(for image: UIImage, in geoSize: CGSize) {
        guard let savedCenterFrac, let targetZoom = savedZoom else { return }
        
        let imgSize = image.size
        guard imgSize.width > 0, imgSize.height > 0, geoSize.width > 0, geoSize.height > 0 else { return }
        
        let imgAspect = imgSize.width / imgSize.height
        let geoAspect = geoSize.width / geoSize.height
        let fitScale: CGFloat = (imgAspect > geoAspect) ? geoSize.width / imgSize.width
        : geoSize.height / imgSize.height
        
        let shownSize   = CGSize(width: imgSize.width * fitScale, height: imgSize.height * fitScale)
        let displaySize = CGSize(width: shownSize.width * targetZoom, height: shownSize.height * targetZoom)
        
        let newOffset = CGSize(
            width:  displaySize.width  * (0.5 - savedCenterFrac.x),
            height: displaySize.height * (0.5 - savedCenterFrac.y)
        )
        
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            zoom       = targetZoom
            offset     = newOffset
            lastOffset = newOffset
        }
    }
    
    private let previewProgressPublisher =
    NotificationCenter.default.publisher(for: .rawUnravelProgress)
        .receive(on: RunLoop.main)
        .debounce(for: .milliseconds(16), scheduler: RunLoop.main)
    private func labelFor(phase: String, step: String) -> String {
        switch (phase, step) {
        case ("libraw","open"):        return "Opening RAW…"
        case ("libraw","identify"):    return "Reading metadata…"
        case ("libraw","unpack"):      return "Unpacking sensor data…"
        case ("libraw","demosaic"):    return "Demosaicing…"
        case ("libraw","convert_rgb"): return "Converting to RGB…"
        case ("rld","iter"):           return "Applying RLD sharpening…"
        default:                       return "Processing…"
        }
    }
    
    
    func initialLoad() {
        isLoading = true
        devJobID = UUID().uuidString

        let p = fileURL.path
        guard FileManager.default.fileExists(atPath: p) else {
            print("[DevelopScreen] file does not exist: \(p)")
            isLoading = false
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let ui = RTPreviewDecoder.decodeRAWPreview(
                atPath: p,
                withPP3Path: "",
                halfSize: true,
                jobID: previewJobID
            )
            DispatchQueue.main.async {
                self.previewImage = ui
                self.isLoading = false
            }
        }
    }
    
    // Plays the screenshot sound
    func playCameraClick() {
        guard let url = Bundle.main.url(forResource: "clix", withExtension: "wav") else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 0.33 // 33% volume
            player.prepareToPlay()
            player.play()
            cameraPlayer = player // Keep alive
        } catch {
            //print("Failed to play camera sound:", error)
        }
    }
    
    // MARK: - Helper: Combine PP3 Segments
    func combinePP3() -> String {
        [exposurePP3, colorPP3, detailsPP3]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
    
    // MARK: - Panel management
    enum PanelType { case exposure, rainbow, details }
    
    func togglePanel(panel: PanelType) {
        withAnimation {
            switch panel {
            case .exposure:
                if showRainbowPanel || showDetailsPanel {
                    showRainbowPanel = false
                    showDetailsPanel = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                        withAnimation { showExposurePanel.toggle() }
                    }
                } else {
                    showExposurePanel.toggle()
                }
            case .rainbow:
                if showExposurePanel || showDetailsPanel {
                    showExposurePanel = false
                    showDetailsPanel = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                        withAnimation { showRainbowPanel.toggle() }
                    }
                } else {
                    showRainbowPanel.toggle()
                }
            case .details:
                if showExposurePanel || showRainbowPanel {
                    showExposurePanel = false
                    showRainbowPanel = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                        withAnimation { showDetailsPanel.toggle() }
                    }
                } else {
                    showDetailsPanel.toggle()
                }
            }
        }
    }
    
    // MARK: - Details helpers (RLD -> PP3)
    
    /// Compute preview pixel scale vs. full-res (so DeconvRadius looks consistent).
    /// Falls back to 0.5 when we’re running half-size previews and sizes aren’t known yet.
    private func currentPreviewScale() -> Double {
        // Prefer actual pixel sizes if available
        if let raw = rawImageSize,
           let prev = previewImage?.pixelSize {
            let sx = Double(prev.width / raw.width)
            let sy = Double(prev.height / raw.height)
            // Use min to be safe; clamp to [0.01, 1]
            return max(0.01, min(1.0, min(sx, sy)))
        }
        // We render half-size previews in this screen
        return 0.5
    }
    
    /// Build the Sharpening block, scaled for the preview size.
    private func makeSharpeningPP3(previewScale: Double) -> String {
        // Clamp UI values to safe ranges
        let amt   = Int(rldAmount.rounded()).clamped(to: 0...200)   // percent
        let iter  = rldIterations.clamped(to: 1...30)
        let damp  = Int(rldDamping.rounded()).clamped(to: 0...100)
        // Scale radius so the half-size preview resembles full-res output
        let scaledRadius = (rldRadius * previewScale).clamped(to: 0.05...5.0)
        let radStr = String(format: "%.3f", scaledRadius)
        
        return """
        [Sharpening]
        Enabled=true
        Method=deconv
        DeconvAmount=\(amt)
        DeconvIterations=\(iter)
        DeconvDamping=\(damp)
        DeconvRadius=\(radStr)
        """
    }
    
    // Optional other details block (kept for compatibility if you still use it)
    func generateDetailsPP3(rldIterations: Int, noiseReduction: Float, dcpDehaze: Float) -> String {
        """
        [Details]
        RLDeconvIterations = \(rldIterations)
        NoiseReduction = \(noiseReduction)
        DCPDehaze = \(dcpDehaze)
        """
    }
    
    // MARK: - View
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GeometryReader { geo in
                
                let isPad = UIDevice.current.userInterfaceIdiom == .pad
                let isLandscape = geo.size.width > geo.size.height
                let useFullWidthPanel = !isPad && !isLandscape
                ZStack {
                    
                    // MARK: - Image + Zoomable View
                    if let ui = previewImage {
                        if let ui = previewImage {
                            ZoomableImageView(
                                image: ui,
                                zoomScale: $vp.zoom,
                                minScale: minZoomScale(for: ui.size, in: geo.size),
                                maxScale: maxZoomScale(for: ui.size, in: geo.size),
                                offset: $vp.offset,
                                lastOffset: $vp.lastOffset
                            )
                            .contentShape(Rectangle())
                            
                            // 👇 Consume taps here so inner recognizers don't see them
                            .gesture(
                                ExclusiveGesture(
                                    TapGesture(count: 3),
                                    TapGesture(count: 2)
                                )
                                .onEnded { result in
                                    var txn = Transaction()
                                    txn.disablesAnimations = false
                                    withTransaction(txn) {
                                        switch result {
                                        case .first: // TRIPLE → 1:1 pixels
                                            let oneToOne = oneToOneScale(for: ui.size, in: geo.size)
                                            vp.zoom = oneToOne
                                            let clamped = clampOffset(for: vp.zoom, in: geo.size)
                                            vp.offset = clamped
                                            vp.lastOffset = clamped
                                            
                                        case .second: // DOUBLE → FIT
                                            vp.zoom = 1.0
                                            vp.offset = .zero
                                            vp.lastOffset = .zero
                                            let clamped = clampOffset(for: 1.0, in: geo.size)
                                            vp.offset = clamped
                                            vp.lastOffset = clamped
                                        }
                                    }
                                },
                                including: .all     // <- important: swallow the gesture here
                            )}}
                    // MARK: - Loading Spinner
                    if isLoading {
                        VStack(spacing: 8) {
                            ProgressView().scaleEffect(2)
                            Text(progressTitle(phase: pPhase, step: pStep))
                                .font(.headline)
                            let sub = progressSubtitle(phase: pPhase, step: pStep, iter: pIter, total: pTotal)
                            if !sub.isEmpty {
                                Text(sub).font(.subheadline).foregroundColor(.secondary)
                            }
                        }
                        .padding(20)
                        .background(.ultraThinMaterial)
                        .cornerRadius(14)
                    }
                    
                    
                    
                    
                    
                    // --- TOP-RIGHT BUTTONS ---
                    VStack(spacing: 4) {
                        Button(action: { togglePanel(panel: .exposure) }) {
                            Text("☀️")
                                .font(.system(size: 28))
                                .padding(8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Button(action: { togglePanel(panel: .rainbow) }) {
                            Text("🌈")
                                .font(.system(size: 24))
                                .padding(8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Button(action: { togglePanel(panel: .details) }) {
                            Text("✨")
                                .font(.system(size: 24))
                                .padding(8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 10)
                    .padding(.trailing, 12)
                    .zIndex(10)
                    
                    // --- PANELS (Overlay) ---
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
                        .frame(minWidth: 0, maxWidth: useFullWidthPanel ? .infinity : 550, alignment: .center)
                        .background(Color.black.opacity(0.05))
                        .cornerRadius(10)
                        .transition(.move(edge: .trailing))
                        .zIndex(20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.top, 16)
                        .padding(.trailing, 88)
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
                        .frame(minWidth: 0, maxWidth: useFullWidthPanel ? .infinity : 550, alignment: .center)
                        .background(Color.black.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .shadow(radius: 10)
                        .transition(.move(edge: .trailing))
                        .zIndex(20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.top, 16)
                        .padding(.trailing, 88)
                    }
                    
                    if showDetailsPanel {
                        // NOTE: Update StarsDetailsPanel to add a 4th slider bound to `deconvRadius`
                        // and (optionally) rename the labels to "RLD Sharpening …".
                        StarsDetailsPanel(
                            deconvIterations: $rldIterations,
                            deconvAmount: $rldAmount,
                            deconvDamping: $rldDamping,
                            deconvRadius: $rldRadius
                        ) {
                            // Build sharpening PP3 using scaled radius for half-size preview
                            let scale = currentPreviewScale()
                            let sharpenPP3 = makeSharpeningPP3(previewScale: scale)
                            
                            // Merge with the rest and reprocess preview
                            detailsPP3 = sharpenPP3
                            currentPP3 = combinePP3()
                            //print("=== Current PP3 ===\n\(currentPP3)")
                            
                            processRAW(with: currentPP3, halfSize: true)
                            showDetailsPanel = false
                        }
                        .frame(minWidth: 0, maxWidth: useFullWidthPanel ? .infinity : 550, alignment: .center)
                        .background(Color.black.opacity(0.05))
                        .cornerRadius(10)
                        .transition(.move(edge: .trailing))
                        .zIndex(20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.top, 16)
                        .padding(.trailing, 88)
                    }
                    
                    // MARK: - Bottom-Right: Screenshot & Export Buttons
                    VStack(spacing: 6) {
                        Button(action: {
                            playCameraClick()
                            takeScreenshot(in: geo)
                        }) {
                            Text("📸")
                                .font(.system(size: 28))
                                .padding(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Button(action: { showExportSheet = true }) {
                            Text("📤")
                                .font(.system(size: 24))
                                .padding(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.bottom, 14)
                    .padding(.trailing, 12)
                    .zIndex(200)
                }
                
                
                .onChange(of: geo.size) { old, new in
                    lastGeoSize = new
                    let clamped = clampOffset(for: zoom, in: new)
                    offset = clamped
                    lastOffset = clamped
                }
                
                
                .onAppear {
                    lastGeoSize = geo.size
                }
            }
            // Help FAB
            VStack {
                Spacer()
                HStack {
                    Button(action: { showHelpSheet = true }) {
                        Label("Help", systemImage: "questionmark.circle")
                            .labelStyle(IconOnlyLabelStyle())
                            .font(.system(size: 32))
                            .foregroundColor(.accentColor)
                            .padding(14)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Help")
                    Spacer()
                }
                .padding([.leading, .bottom], 18)
            }
            .zIndex(1000)
        }
        // MARK: - Export Sheet for Screenshot (with crop)
        .sheet(item: $screenshotItem) { item in
            if let rawImageSize = rawImageSize {
                // Screenshot export (with crop)
                ExportJPGView(
                    rawFileURL: fileURL,
                    pp3String: currentPP3,
                    cropRectInPreview: item.cropRect,
                    previewFrame: item.previewFrame,
                    previewUIImageSize: item.previewUIImageSize,
                    previewUIImage: previewImage,
                    rawImageSize: rawImageSize,
                    sourceBitmap: nil,                      // ← here
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
                    rawImageSize: rawImageSize, sourceBitmap: nil
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
        .sheet(isPresented: $showHelpSheet) {
            HelpView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .rawUnravelProgress)) { note in
            guard
                let info = note.userInfo as? [String: Any],
                (info["job"] as? String) == previewJobID  // only ours
            else { return }
            pPhase = info["phase"] as? String ?? ""
            pStep  = info["step"]  as? String ?? ""
            pIter  = (info["iter"] as? NSNumber)?.intValue ?? 0
            pTotal = (info["total"] as? NSNumber)?.intValue ?? 0
        }
    }
    
    // MARK: - Screenshot Crop & Trigger Export
    
    /// Captures current visible region for screenshot export (in preview px)
    private func takeScreenshot(in geo: GeometryProxy) {
        guard let lowResImage = previewImage else { return }
        
        let cropInImagePixels = visibleCropRectInImagePixels(
            image: lowResImage,
            geoSize: geo.size,
            zoom: vp.zoom,           // <- use viewport zoom
            offset: vp.offset        // <- use viewport offset
        )
        
        screenshotItem = ScreenshotItem(
            cropRect: cropInImagePixels,
            previewFrame: geo.size,
            previewUIImageSize: lowResImage.pixelSize
        )
    }
    
    
    // MARK: - Crop Rect Mapping
    
    /// Returns the visible crop rect in image pixel coordinates (for screenshot/export)
    private func visibleCropRectInImagePixels(image: UIImage,
                                              geoSize: CGSize,
                                              zoom: CGFloat,
                                              offset: CGSize) -> CGRect
    {
        // Current math (uses image.size which is in POINTS) – keep as is:
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
        
        // Map to IMAGE SPACE (still in POINTS here):
        let scaleX = imgSize.width  / displaySize.width
        let scaleY = imgSize.height / displaySize.height
        var x = (visibleRectInGeo.origin.x - imageRectInGeo.origin.x) * scaleX
        var y = (visibleRectInGeo.origin.y - imageRectInGeo.origin.y) * scaleY
        var w = visibleRectInGeo.size.width  * scaleX
        var h = visibleRectInGeo.size.height * scaleY
        
        // Convert POINTS -> PIXELS
        let s = image.scale
        x *= s; y *= s; w *= s; h *= s
        
        // Clamp to pixel bounds
        let px = image.pixelSize
        let clamped = CGRect(
            x: max(0, min(x, px.width)),
            y: max(0, min(y, px.height)),
            width: min(w, px.width - x),
            height: min(h, px.height - y)
        ).integral
        
        return clamped
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
    func processRAW(with pp3String: String, halfSize: Bool = true) {
        isLoading = true
        pPhase = ""; pStep = ""; pIter = 0; pTotal = 0
        previewJobID = UUID().uuidString
        
        // 1) CAPTURE the current viewport before we change the image
        if let ui = previewImage {
            captureViewport(for: ui, in: lastGeoSize)
        }
        
        // Write temp PP3
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("temp.pp3")
        try? pp3String.write(to: tmp, atomically: true, encoding: .utf8)
        
        // 2) Decode on a background queue
        DispatchQueue.global(qos: .userInitiated).async {
            let lowRes = RTPreviewDecoder.decodeRAWPreview(
                atPath: fileURL.path,
                withPP3Path: tmp.path,
                halfSize: true,
                jobID: previewJobID
            )
            
            // 3) On main thread: assign and RESTORE viewport
            DispatchQueue.main.async {
                previewImage = lowRes
                DispatchQueue.main.async {
                    previewImage = lowRes
                    if let p = lowRes {
                        print("preview UIImage orientation = \(p.imageOrientation.rawValue)")
                    }
                    
                    if let lowRes {
                        restoreViewport(for: lowRes, in: lastGeoSize)
                        
                        // ⬇️ make sure the restored offset is valid for the current zoom/geo
                        let clamped = clampOffset(for: zoom, in: lastGeoSize)
                        offset = clamped
                        lastOffset = clamped
                    }
                    
                    isLoading = false
                    pPhase = ""; pStep = ""; pIter = 0; pTotal = 0
                }
                
            }
        }
        
        
        /// Loads preview on view appear (no pp3: default dev)
        
    }
    
    // MARK: - Comparable clamp extension
    
    //extension Comparable {
    //    /// Clamps value to closed range.
    //    func clamped(to limits: ClosedRange<Self>) -> Self {
    //        min(max(self, limits.lowerBound), limits.upperBound)
    //    }
    //}
    
    // MARK: - Crop Clamping Helper
    
    /// Ensures crop rect fits within image bounds (used for safety).
    func clampCropRect(_ crop: CGRect, imageSize: CGSize) -> CGRect {
        let x = crop.origin.x.clamped(to: 0...(imageSize.width - 1))
        let y = crop.origin.y.clamped(to: 0...(imageSize.height - 1))
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
    
    private func progressTitle(phase: String, step: String) -> String {
        switch (phase, step) {
        case ("libraw","open"):        return "Opening RAW…"
        case ("libraw","identify"):    return "Reading metadata…"
        case ("libraw","unpack"):      return "Unpacking sensor data…"
        case ("libraw","demosaic"):    return "Demosaicing…"
        case ("libraw","convert_rgb"): return "Converting to RGB…"
        case ("libraw","finish"):      return "Finalizing…"
        case ("rld","iter"):           return "Applying RLD sharpening…"
        default:                       return "Processing…"
        }
    }
    
    private func progressSubtitle(phase: String, step: String, iter: Int, total: Int) -> String {
        guard total > 0, iter > 0 else { return "" }
        switch (phase, step) {
        case ("rld", "iter"):              return "RLD \(iter)/\(total)"
        case ("libraw", "unpack"):         return "Unpack \(iter)/\(total)"
        case ("libraw", "demosaic"):       return "Demosaic \(iter)/\(total)"
        case ("libraw", "convert_rgb"):    return "RGB \(iter)/\(total)"
        case ("libraw", "open"):           return "Opening (\(iter)/\(total))"
        case ("libraw", "identify"):       return "Identifying (\(iter)/\(total))"
        case ("libraw", "readraw"):        return "Read RAW \(iter)/\(total)"
        case ("libraw", "finish"):         return "Finishing (\(iter)/\(total))"
            // Add any other known steps you care to label
        default:
            return "" // For all unknown steps, display nothing
        }
    }
    
    
    
    // Keep the same center/zoom across reprocesses
    struct ViewportState {
        var zoom: CGFloat
        var offset: CGSize
        var lastOffset: CGSize
        var savedCenterFrac: CGPoint?
        var savedZoom: CGFloat?
    }
    
    func captureViewport(for image: UIImage, geoSize: CGSize, state: inout ViewportState) {
        let imgSize = image.size
        guard imgSize.width > 0, imgSize.height > 0, geoSize.width > 0, geoSize.height > 0 else { return }
        
        let imgAspect = imgSize.width / imgSize.height
        let geoAspect = geoSize.width / geoSize.height
        let fitScale: CGFloat = (imgAspect > geoAspect) ? geoSize.width / imgSize.width
        : geoSize.height / imgSize.height
        
        let shownSize   = CGSize(width: imgSize.width * fitScale, height: imgSize.height * fitScale)
        let displaySize = CGSize(width: shownSize.width * state.zoom, height: shownSize.height * state.zoom)
        let geoCenter   = CGPoint(x: geoSize.width / 2, y: geoSize.height / 2)
        let displayOrigin = CGPoint(
            x: geoCenter.x - displaySize.width / 2  + state.offset.width,
            y: geoCenter.y - displaySize.height / 2 + state.offset.height
        )
        
        let u = (geoCenter.x - displayOrigin.x) / displaySize.width
        let v = (geoCenter.y - displayOrigin.y) / displaySize.height
        
        state.savedCenterFrac = CGPoint(x: u.clamped(to: 0...1), y: v.clamped(to: 0...1))
        state.savedZoom = state.zoom
    }
    
    func restoreViewport(for image: UIImage, geoSize: CGSize, state: inout ViewportState) {
        guard let saved = state.savedCenterFrac, let targetZoom = state.savedZoom else { return }
        
        let imgSize = image.size
        guard imgSize.width > 0, imgSize.height > 0, geoSize.width > 0, geoSize.height > 0 else { return }
        
        let imgAspect = imgSize.width / imgSize.height
        let geoAspect = geoSize.width / geoSize.height
        let fitScale: CGFloat = (imgAspect > geoAspect) ? geoSize.width / imgSize.width
        : geoSize.height / imgSize.height
        
        let shownSize   = CGSize(width: imgSize.width * fitScale, height: imgSize.height * fitScale)
        let displaySize = CGSize(width: shownSize.width * targetZoom, height: shownSize.height * targetZoom)
        
        let newOffset = CGSize(
            width:  displaySize.width  * (0.5 - saved.x),
            height: displaySize.height * (0.5 - saved.y)
        )
        
        state.zoom       = targetZoom
        state.offset     = newOffset
        state.lastOffset = newOffset
    }
}
