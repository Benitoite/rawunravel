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

import SwiftUI
import UIKit

// MARK: - ZoomableImageView
// Renders an image with precise, predictable zoom/pan behavior driven by a UIKit overlay.
// Coordinate Systems:
//   • Box/view space: points in the GeometryReader frame.
//   • Fitted space: aspect-fit rectangle of the image inside the box at unit zoom.
//   • Display space: fitted space scaled by `zoomScale` and translated by `offset`.
// Gestures:
//   • Pinch: multiplicative scaling about the pinch centroid, preserving the visual anchor.
//   • Pan: one- and two-finger pans translate in display space with clamping.
//   • Double tap: snap to aspect-fit (zoom = 1), centered.
//   • Triple tap: snap to 1:1 pixels (zoom = 1/s_fit), anchored at tap location.

struct ZoomableImageView: View {
    // MARK: Inputs
    let image: UIImage
    @Binding var zoomScale: CGFloat           // display scale relative to aspect-fit
    let minScale: CGFloat                     // inclusive lower bound for zoomScale
    let maxScale: CGFloat                     // inclusive upper bound for zoomScale
    @Binding var offset: CGSize               // display translation in box space
    @Binding var lastOffset: CGSize           // last committed offset (for gesture inertia, etc.)

    // MARK: Internal State
    @State private var imageKey: Int = 0      // identity derived from pixel dimensions

    // MARK: Pixel Geometry

    /// Returns pixel size (w, h) of `img` in pixels (not points).
    private func pixelSize(of img: UIImage) -> CGSize {
        if let cg = img.cgImage { return CGSize(width: cg.width, height: cg.height) }
        if let ci = img.ciImage { return ci.extent.size }
        return CGSize(width: img.size.width * img.scale, height: img.size.height * img.scale)
    }

    /// Returns the aspect-fit size of `img` inside a rectangular box `box` at unit zoom.
    /// s_fit = min(box.w / px.w, box.h / px.h); fit = s_fit * (px.w, px.h)
    private func fittedSize(for img: UIImage, in box: CGSize) -> CGSize {
        let px = pixelSize(of: img)
        guard px.width > 0, px.height > 0, box.width > 0, box.height > 0 else { return .zero }
        let s = min(box.width / px.width, box.height / px.height)
        return CGSize(width: px.width * s, height: px.height * s)
    }

    /// Returns the aspect-fit rectangle centered in the box at unit zoom.
    /// fitRect = centered box of size `fittedSize`.
    private func fittedRect(for img: UIImage, in box: CGSize) -> CGRect {
        let fit = fittedSize(for: img, in: box)
        return CGRect(x: (box.width - fit.width)/2,
                      y: (box.height - fit.height)/2,
                      width: fit.width, height: fit.height)
    }

    // MARK: Viewport Conversion (Center <-> Offset)

    /// Computes the normalized center (u, v) ∈ [0,1]^2 of the current viewport in fitted space.
    /// Derivation:
    ///   Display origin O = (fit.midXY - (fit.size/2)*z) + offset
    ///   View center C_view = box.size/2
    ///   Center in display D = C_view - O
    ///   Center in fitted F  = D / z
    ///   Normalized: u = F.x / fit.w, v = F.y / fit.h
    private func normalizedCenter(zoom: CGFloat, offset: CGSize, in box: CGSize, img: UIImage) -> CGPoint {
        let fit = fittedRect(for: img, in: box)
        let viewCenter = CGPoint(x: box.width/2, y: box.height/2)
        let origin = CGPoint(
            x: fit.midX - (fit.width/2) * zoom + offset.width,
            y: fit.midY - (fit.height/2) * zoom + offset.height
        )
        let centerInDisplay = CGPoint(x: viewCenter.x - origin.x, y: viewCenter.y - origin.y)
        let z = max(zoom, 0.0001)
        let centerInFitted = CGPoint(x: centerInDisplay.x / z, y: centerInDisplay.y / z)
        let nx = fit.width  > 0 ? centerInFitted.x / fit.width  : 0.5
        let ny = fit.height > 0 ? centerInFitted.y / fit.height : 0.5
        return CGPoint(x: min(max(nx, 0), 1), y: min(max(ny, 0), 1))
    }

    /// Converts a normalized fitted-space center (u, v) back to an `offset` for a target zoom.
    /// Given normalized F = (u*fit.w, v*fit.h), display center equals the box center:
    ///   C_view = (fit.midXY - (fit.size/2)*z) + F*z + offset
    /// Solving for offset yields:
    ///   offset = C_view - [fit.midXY - (fit.size/2)*z + F*z]
    private func offsetForNormalizedCenter(_ norm: CGPoint, zoom: CGFloat, in box: CGSize, img: UIImage) -> CGSize {
        let fit = fittedRect(for: img, in: box)
        let cx = fit.width * norm.x
        let cy = fit.height * norm.y
        let centerInView = CGPoint(
            x: (fit.midX - (fit.width/2) * zoom) + cx * zoom,
            y: (fit.midY - (fit.height/2) * zoom) + cy * zoom
        )
        let viewCenter = CGPoint(x: box.width/2, y: box.height/2)
        return CGSize(width: viewCenter.x - centerInView.x, height: viewCenter.y - centerInView.y)
    }

    // MARK: Panning Bounds

    /// Clamps a proposed `raw` offset so the displayed image stays within the box at zoom z.
    /// Display size V = z * fittedSize. Max excursion along each axis is E = max((V - box)/2, 0).
    private func clampedOffset(for raw: CGSize, img: UIImage, box: CGSize, zoom: CGFloat) -> CGSize {
        let fit = fittedSize(for: img, in: box)
        let vw = fit.width * zoom
        let vh = fit.height * zoom
        let maxX = max((vw - box.width)/2, 0)
        let maxY = max((vh - box.height)/2, 0)
        return CGSize(width: min(max(raw.width, -maxX), maxX),
                      height: min(max(raw.height, -maxY), maxY))
    }

    // MARK: Identity Key

    /// Compact identity derived from pixel width/height. Changes when the raster size changes.
    private func makeImageKey(_ img: UIImage) -> Int {
        let px = pixelSize(of: img)
        return Int(px.width.rounded()) << 16 ^ Int(px.height.rounded())
    }

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            let box = geo.size

            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(zoomScale, anchor: .center)
                    .offset(offset)
                    .frame(width: box.width, height: box.height)
                    .contentShape(Rectangle())
                    .overlay(
                        PinchPanOverlay(
                            onChanged: { scaleDelta, centroid, panDelta in
                                // Multiplicative zoom update: z' = clamp(z * Δ, [z_min, z_max])
                                let current = zoomScale
                                let newZoom = (current * scaleDelta).clamped(to: minScale...maxScale)

                                // Anchor-preserving zoom about `centroid`.
                                // Let A be the anchor in pre-zoom fitted space:
                                //   A = (centroid - box/2 - offset) / z
                                // After scaling to z', we require centroid to map to the same screen point:
                                //   offset' = centroid - box/2 - A * z'
                                let zSafe = max(current, 0.0001)
                                let anchorX = (centroid.x - box.width/2 - offset.width) / zSafe
                                let anchorY = (centroid.y - box.height/2 - offset.height) / zSafe
                                let baseOffsetX = centroid.x - box.width/2 - anchorX * newZoom
                                let baseOffsetY = centroid.y - box.height/2 - anchorY * newZoom

                                // Apply pan delta in display space, then clamp.
                                let newOffset = CGSize(width: baseOffsetX + panDelta.x,
                                                       height: baseOffsetY + panDelta.y)

                                offset = clampedOffset(for: newOffset, img: image, box: box, zoom: newZoom)
                                zoomScale = newZoom
                            },
                            onEnded: {
                                // If nearly at minimum, snap translation to zero for cleanliness.
                                if zoomScale <= (minScale + 0.01) { offset = .zero; lastOffset = .zero }
                                else { lastOffset = offset }
                            },
                            onDoubleTap: { _ in
                                // DOUBLE-TAP → ASPECT-FIT:
                                // By construction, `zoomScale = 1` corresponds to the aspect-fit framing.
                                zoomScale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            },
                            onTripleTap: { point in
                                // TRIPLE-TAP → 1:1 PIXELS:
                                // Base fit scale s_fit = min(box.w / px.w, box.h / px.h).
                                // One-to-one requires display scale = 1 / s_fit relative to the fit.
                                let px = pixelSize(of: image)
                                let sFit = min(box.width / max(px.width,  0.0001),
                                               box.height / max(px.height, 0.0001))
                                let target = (1.0 / sFit).clamped(to: minScale...maxScale)

                                // Anchor at tap point (same derivation as pinch anchor).
                                let zSafe = max(zoomScale, 0.0001)
                                let ax = (point.x - box.width/2 - offset.width) / zSafe
                                let ay = (point.y - box.height/2 - offset.height) / zSafe
                                let ox = point.x - box.width/2 - ax * target
                                let oy = point.y - box.height/2 - ay * target
                                let newOffset = clampedOffset(for: CGSize(width: ox, height: oy),
                                                              img: image, box: box, zoom: target)

                                zoomScale  = target
                                offset     = newOffset
                                lastOffset = newOffset
                            }
                        )
                        .allowsHitTesting(true)
                    )
            }
            // Propagate identity changes when underlying raster size changes (e.g., after RLD)
            .task(id: image) {
                let key = makeImageKey(image)
                if key != imageKey { imageKey = key }
            }
            // Preserve previous normalized center across raster-size changes at fixed zoom.
            .task(id: imageKey) {
                let prevCenter = normalizedCenter(zoom: zoomScale, offset: offset, in: box, img: image)
                let newOffset = offsetForNormalizedCenter(prevCenter, zoom: zoomScale, in: box, img: image)
                offset = clampedOffset(for: newOffset, img: image, box: box, zoom: zoomScale)
                lastOffset = offset
            }
            // Preserve center across parent layout changes (e.g., rotation, split view resizing).
            .task(id: box) {
                let prevCenter = normalizedCenter(zoom: zoomScale, offset: offset, in: box, img: image)
                let newOffset = offsetForNormalizedCenter(prevCenter, zoom: zoomScale, in: box, img: image)
                offset = clampedOffset(for: newOffset, img: image, box: box, zoom: zoomScale)
                lastOffset = offset
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - PinchPanOverlay (UIKit)
// A thin UIView wrapper that:
//   • Emits pinch scale deltas and their centroid.
//   • Emits one- and two-finger pan deltas.
//   • Emits double- and triple-tap events with locations.
// Gesture arbitration:
//   • tripleTap is required by doubleTap to fail; triple has precedence.
//   • Simultaneous recognition is allowed for pinch + pans.

private struct PinchPanOverlay: UIViewRepresentable {
    // MARK: Callbacks
    var onChanged: (_ scaleDelta: CGFloat, _ centroid: CGPoint, _ panDelta: CGPoint) -> Void
    var onEnded: () -> Void
    var onDoubleTap: (_ point: CGPoint) -> Void
    var onTripleTap: (_ point: CGPoint) -> Void

    final class View: UIView, UIGestureRecognizerDelegate {
        // MARK: Callback storage
        var onChanged: ((CGFloat, CGPoint, CGPoint) -> Void)?
        var onEnded: (() -> Void)?
        var onDoubleTap: ((CGPoint) -> Void)?
        var onTripleTap: ((CGPoint) -> Void)?

        // MARK: Recognizers
        private let pinch = UIPinchGestureRecognizer()
        private let pan1  = UIPanGestureRecognizer()
        private let pan2  = UIPanGestureRecognizer()
        private let doubleTap = UITapGestureRecognizer()
        private let tripleTap = UITapGestureRecognizer()

        // MARK: Gesture State
        private var lastScale: CGFloat = 1.0
        private var lastPan1: CGPoint = .zero
        private var lastPan2: CGPoint = .zero

        // MARK: Init
        override init(frame: CGRect) {
            super.init(frame: frame)

            // Pinch
            pinch.addTarget(self, action: #selector(handlePinch(_:)))
            pinch.delegate = self
            addGestureRecognizer(pinch)

            // One-finger pan
            pan1.minimumNumberOfTouches = 1
            pan1.maximumNumberOfTouches = 1
            pan1.addTarget(self, action: #selector(handlePan1(_:)))
            pan1.delegate = self
            addGestureRecognizer(pan1)

            // Two-finger pan
            pan2.minimumNumberOfTouches = 2
            pan2.maximumNumberOfTouches = 2
            pan2.addTarget(self, action: #selector(handlePan2(_:)))
            pan2.delegate = self
            addGestureRecognizer(pan2)

            // Triple tap (must take precedence over double tap)
            tripleTap.numberOfTapsRequired = 3
            tripleTap.addTarget(self, action: #selector(handleTripleTap(_:)))
            addGestureRecognizer(tripleTap)

            // Double tap; require triple to fail so 3 taps do not trigger 2-tap semantics
            doubleTap.numberOfTapsRequired = 2
            doubleTap.require(toFail: tripleTap)
            doubleTap.addTarget(self, action: #selector(handleDoubleTap(_:)))
            addGestureRecognizer(doubleTap)

            isMultipleTouchEnabled = true
            isUserInteractionEnabled = true
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) { fatalError() }

        // MARK: Pinch Handler
        @objc private func handlePinch(_ gr: UIPinchGestureRecognizer) {
            switch gr.state {
            case .began:
                lastScale = 1.0
            case .changed:
                // Scale delta is relative to the last callback, not the gesture’s origin.
                let delta = gr.scale / max(lastScale, 0.0001)
                lastScale = gr.scale
                let c = gr.location(in: self)
                onChanged?(delta, c, .zero)
            case .ended, .cancelled, .failed:
                onEnded?()
                lastScale = 1.0
            default:
                break
            }
        }

        // MARK: One-Finger Pan Handler
        @objc private func handlePan1(_ gr: UIPanGestureRecognizer) {
            switch gr.state {
            case .began:
                lastPan1 = .zero
            case .changed:
                let t = gr.translation(in: self)
                let d = CGPoint(x: t.x - lastPan1.x, y: t.y - lastPan1.y)
                lastPan1 = t
                onChanged?(1.0, gr.location(in: self), d)
            case .ended, .cancelled, .failed:
                onEnded?()
                lastPan1 = .zero
            default:
                break
            }
        }

        // MARK: Two-Finger Pan Handler
        @objc private func handlePan2(_ gr: UIPanGestureRecognizer) {
            switch gr.state {
            case .began:
                lastPan2 = .zero
            case .changed:
                let t = gr.translation(in: self)
                let d = CGPoint(x: t.x - lastPan2.x, y: t.y - lastPan2.y)
                lastPan2 = t
                // Use pinch centroid to emulate a “common” pan anchor for two fingers.
                onChanged?(1.0, pinch.location(in: self), d)
            case .ended, .cancelled, .failed:
                onEnded?()
                lastPan2 = .zero
            default:
                break
            }
        }

        // MARK: Tap Handlers
        @objc private func handleDoubleTap(_ gr: UITapGestureRecognizer) {
            onDoubleTap?(gr.location(in: self))
        }

        @objc private func handleTripleTap(_ gr: UITapGestureRecognizer) {
            onTripleTap?(gr.location(in: self))
        }

        // MARK: Simultaneous Recognition
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }
    }

    // MARK: UIViewRepresentable
    func makeUIView(context: Context) -> View {
        let v = View()
        v.onChanged = onChanged
        v.onEnded = onEnded
        v.onDoubleTap = onDoubleTap
        v.onTripleTap = onTripleTap
        return v
    }

    func updateUIView(_ uiView: View, context: Context) {}
}

// MARK: - Utils

extension Comparable {
    /// Clamps `self` into the closed range `r`.
    @inlinable func clamped(to r: ClosedRange<Self>) -> Self { min(max(self, r.lowerBound), r.upperBound) }
}
