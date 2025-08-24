/*
    RawUnravel - StarsDetailsPanel.swift
    ------------------------------------
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

// MARK: - StarsDetailsPanel
// Panel with four sliders controlling Richardson–Lucy Deconvolution (RLD) sharpening.
// Parameters:
//   • Iterations: number of RL iterations (1…30).
//   • Amount: sharpening strength in percent (0…200).
//   • Damping: stabilizing factor (0…100).
//   • Radius: effective blur radius in full-resolution pixels (0.05…5.0).
// Each slider has a reset button restoring the RawTherapee-style default.

struct StarsDetailsPanel: View {
    // MARK: Bindings
    @Binding var deconvIterations: Int     // 1…30 iterations
    @Binding var deconvAmount: Float       // 0…200 (%)
    @Binding var deconvDamping: Float      // 0…100
    @Binding var deconvRadius: Double      // 0.05…5.0 pixels at full-res

    // MARK: Action
    var onApply: () -> Void                // Called when user presses "Apply Adjustments"

    // MARK: Defaults (mirror DevelopScreen defaults)
    let defaultIterations: Int = 10
    let defaultAmount: Float = 100
    let defaultDamping: Float = 0
    let defaultRadius: Double = 0.8

    // MARK: Body
    var body: some View {
        VStack(spacing: 22) {
            // MARK: Iterations
            VStack(alignment: .leading) {
                label("RLD Sharpening Iterations: \(deconvIterations)")
                HStack {
                    Slider(
                        value: Binding(
                            get: { Double(deconvIterations) },
                            set: { deconvIterations = Int($0.rounded()) }
                        ),
                        in: 1...30,
                        step: 1
                    )
                    resetButton(enabled: deconvIterations != defaultIterations) {
                        deconvIterations = defaultIterations
                    }
                    .accessibilityLabel("Reset RLD Iterations")
                }
            }

            // MARK: Amount
            VStack(alignment: .leading) {
                label("RLD Sharpening Amount: \(String(format: "%.0f%%", deconvAmount))")
                HStack {
                    Slider(value: $deconvAmount, in: 0...200, step: 1)
                    resetButton(enabled: deconvAmount != defaultAmount) {
                        deconvAmount = defaultAmount
                    }
                    .accessibilityLabel("Reset RLD Amount")
                }
            }

            // MARK: Damping
            VStack(alignment: .leading) {
                label("RLD Sharpening Damping: \(String(format: "%.0f", deconvDamping))")
                HStack {
                    Slider(value: $deconvDamping, in: 0...100, step: 1)
                    resetButton(enabled: deconvDamping != defaultDamping) {
                        deconvDamping = defaultDamping
                    }
                    .accessibilityLabel("Reset RLD Damping")
                }
            }

            // MARK: Radius
            VStack(alignment: .leading) {
                label("RLD Sharpening Radius: \(String(format: "%.2f px", deconvRadius))")
                HStack {
                    Slider(value: $deconvRadius, in: 0.05...5.0, step: 0.05)
                    resetButton(enabled: abs(deconvRadius - defaultRadius) > .ulpOfOne) {
                        deconvRadius = defaultRadius
                    }
                    .accessibilityLabel("Reset RLD Radius")
                }
            }

            // MARK: Apply Button
            Button("Apply Adjustments") {
                onApply()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - UI Helpers

    /// Styled label with subtle shadow + white outline for legibility.
    private func label(_ text: String) -> some View {
        ZStack {
            Text(text).font(.body)
                .shadow(color: .white, radius: 0.5, x: 0, y: 0.5)
            Text(text)
                .foregroundColor(.white)
                .offset(x: 1, y: 0.5)
        }
    }

    /// Reset button with arrow icon, disabled when already at default.
    private func resetButton(enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.system(size: 22))
                .opacity(enabled ? 1.0 : 0.3)
        }
        .padding(.leading, 4)
        .buttonStyle(.plain)
    }
}
