/*
    RawUnravel - ZoomableImageView.swift
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

// MARK: - ZoomableImageView

/// A zoomable & pannable image view with centroid-aware pinch zoom.
/// Maintains original commenting and debug output style.
struct ZoomableImageView: View {
    let image: UIImage
    @Binding var zoomScale: CGFloat
    let minScale: CGFloat
    let maxScale: CGFloat
    @Binding var offset: CGSize
    @Binding var lastOffset: CGSize

    @State private var lastScale: CGFloat = 1.0
    @State private var gestureAnchor: CGPoint = .zero    // Where was the pinch centroid in view coords?

    // MARK: - Offset Clamping

    private func clampedOffset(for offset: CGSize, imageSize: CGSize, geoSize: CGSize, zoom: CGFloat) -> CGSize {
        let scale = max(imageSize.width / geoSize.width, imageSize.height / geoSize.height)
        let scaledWidth = imageSize.width / scale * zoom
        let scaledHeight = imageSize.height / scale * zoom

        let maxX = max((scaledWidth - geoSize.width) / 2, 0)
        let maxY = max((scaledHeight - geoSize.height) / 2, 0)

        let clampedX = min(max(offset.width, -maxX), maxX)
        let clampedY = min(max(offset.height, -maxY), maxY)
        return CGSize(width: clampedX, height: clampedY)
    }

    // MARK: - Main View

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(zoomScale)
                    .offset(offset)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .background(TrackCentroidView(centroidHandler: { point in
                        // This invisible overlay keeps track of the current centroid location.
                        gestureAnchor = point
                    }))
                    .gesture(
                        SimultaneousGesture(
                            // --- Pinch-to-Zoom with centroid-aware offset ---
                            MagnificationGesture()
                                .onChanged { val in
                                    let delta = val / lastScale
                                    lastScale = val

                                    // ----- Core logic: Adjust offset so centroid point stays fixed -----
                                    let anchor = gestureAnchor
                                    let currentZoom = zoomScale
                                    let newZoom = (zoomScale * delta).clamped(to: minScale...maxScale)

                                    // Figure out the offset delta so the anchor stays stationary.
                                    // 1. Where is anchor in the image, in image coords?
                                    let anchorX = (anchor.x - geo.size.width / 2 - offset.width) / currentZoom
                                    let anchorY = (anchor.y - geo.size.height / 2 - offset.height) / currentZoom

                                    // 2. Where would that image point be after the zoom?
                                    let newOffsetX = anchor.x - geo.size.width / 2 - anchorX * newZoom
                                    let newOffsetY = anchor.y - geo.size.height / 2 - anchorY * newZoom
                                    let newOffset = CGSize(width: newOffsetX, height: newOffsetY)
                                    let clamped = clampedOffset(for: newOffset, imageSize: image.size, geoSize: geo.size, zoom: newZoom)
                                    print("[MAG] centroid:(\(anchor.x),\(anchor.y)) delta:\(delta) → newZoom:\(newZoom) offset:\(offset) → newOffset:\(newOffset) clamped:\(clamped)")

                                    zoomScale = newZoom
                                    offset = clamped
                                }
                                .onEnded { _ in
                                    lastScale = 1.0
                                    print("[MAG] onEnded zoomScale:\(zoomScale)")
                                    if zoomScale <= 1.01 {
                                        offset = .zero
                                        lastOffset = .zero
                                    }
                                },

                            // --- Drag-to-Pan (unchanged) ---
                            DragGesture()
                                .onChanged { value in
                                    if zoomScale > 1.01 {
                                        let rawOffset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                        let clamped = clampedOffset(for: rawOffset, imageSize: image.size, geoSize: geo.size, zoom: zoomScale)
                                        print("[DRAG] onChanged translation:\(value.translation) lastOffset:\(lastOffset) → rawOffset:\(rawOffset) → clamped:\(clamped)")
                                        offset = clamped
                                    }
                                }
                                .onEnded { _ in
                                    print("[DRAG] onEnded offset:\(offset)")
                                    if zoomScale > 1.01 {
                                        lastOffset = offset
                                    } else {
                                        offset = .zero
                                        lastOffset = .zero
                                    }
                                }
                        )
                    )
            }
        }
        .ignoresSafeArea()
        .onChange(of: offset) { newValue in
            print("[OFFSET] Changed to: \(newValue)")
        }
        .onChange(of: zoomScale) { newValue in
            print("[ZOOM] Changed to: \(newValue)")
        }
    }
}

// MARK: - TrackCentroidView (Helper)
// This invisible overlay keeps track of the most recent touch location (centroid).
struct TrackCentroidView: UIViewRepresentable {
    var centroidHandler: (CGPoint) -> Void

    func makeUIView(context: Context) -> UIView {
        let v = TouchCentroidTrackerView()
        v.centroidHandler = centroidHandler
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

class TouchCentroidTrackerView: UIView {
    var centroidHandler: ((CGPoint) -> Void)?
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        updateCentroid(touches)
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        updateCentroid(touches)
    }
    private func updateCentroid(_ touches: Set<UITouch>) {
        guard touches.count >= 2 else { return }
        let points = touches.map { $0.location(in: self) }
        // Compute average location of all touches (the centroid)
        let centroid = CGPoint(
            x: points.map { $0.x }.reduce(0, +) / CGFloat(points.count),
            y: points.map { $0.y }.reduce(0, +) / CGFloat(points.count)
        )
        centroidHandler?(centroid)
    }
}
