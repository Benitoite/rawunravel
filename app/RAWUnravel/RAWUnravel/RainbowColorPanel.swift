/*
    RawUnravel - RainbowColorPanel.swift
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

// MARK: - RainbowColorPanel (Color/Contrast Controls)

/// Color and contrast adjustments panel (JC Color Appearance model).
struct RainbowColorPanel: View {
    @Binding var chromaticity: Float      // [Luminance Curve]Chromaticity
    @Binding var cChroma: Float           // [Color appearance]C-Chroma
    @Binding var jContrast: Float         // [Color appearance]J-Contrast
    var onApply: (String) -> Void         // Callback with generated .pp3

    // MARK: - Defaults (RawTherapee-style)
    let defaultChromaticity: Float = 0.0
    let defaultCChroma: Float = 0.0
    let defaultJContrast: Float = 0.0

    // MARK: - Generates the PP3 snippet for these controls
    func currentPP3() -> String {
        """
        [Color appearance]
        Enabled=true
        Algorithm=JC
        C-Chroma=\(Int(cChroma))
        C-ChromaEnabled=true
        J-Contrast=\(Int(jContrast))
        J-ContrastEnabled=true

        [Luminance Curve]
        Enabled=true
        Chromaticity=\(Int(chromaticity))
        ChromaticityEnabled=true

        [RAW]
        """
    }

    // MARK: - Main Panel View

    var body: some View {
        VStack(spacing: 20) {
            // Chromaticity Slider
            VStack(alignment: .leading) {
                ZStack {
                    Text("Chromaticity: \(Int(chromaticity))")
                        .font(.body)
                        .shadow(color: .white, radius: 0.5, x: 0, y: 0.5)
                    Text("Chromaticity: \(Int(chromaticity))")
                        .foregroundColor(.white)
                        .offset(x: 1, y: 0.5)
                }
                HStack {
                    Slider(value: $chromaticity, in: -100...100, step: 1.0)
                    Button(action: { chromaticity = defaultChromaticity }) {
                        ResetCircleIcon(
                            systemName: "arrow.uturn.backward.circle.fill",
                            size: 22,
                            enabled: chromaticity != defaultChromaticity,
                            showLabel: false
                        )
                    }
                }
            }
            // C-Chroma Slider
            VStack(alignment: .leading) {
                ZStack {
                    Text("C-Chroma: \(Int(cChroma))")
                        .font(.body)
                        .shadow(color: .white, radius: 0.5, x: 0, y: 0.5)
                    Text("C-Chroma: \(Int(cChroma))")
                        .foregroundColor(.white)
                        .offset(x: 1, y: 0.5)
                }
                HStack {
                    Slider(value: $cChroma, in: -100...100, step: 1.0)
                    Button(action: { cChroma = defaultCChroma }) {
                        ResetCircleIcon(
                            systemName: "arrow.uturn.backward.circle.fill",
                            size: 22,
                            enabled: cChroma != defaultCChroma,
                            showLabel: false)
                    }
                }
            }
            // J-Contrast Slider
            VStack(alignment: .leading) {
                ZStack {
                    Text("J-Contrast: \(Int(jContrast))")
                        .font(.body)
                        .shadow(color: .white, radius: 0.5, x: 0, y: 0.5)
                    Text("J-Contrast: \(Int(jContrast))")
                        .foregroundColor(.white)
                        .offset(x: 1, y: 0.5)
                }
                HStack {
                    Slider(value: $jContrast, in: -100...100, step: 1.0)
                    Button(action: { jContrast = defaultJContrast }) {
                        ResetCircleIcon(
                            systemName: "arrow.uturn.backward.circle.fill",
                            size: 22,
                            enabled: jContrast != defaultJContrast,
                            showLabel: false)
                    }
                }
            }
            // MARK: - Apply Button
            Button("Apply Color Adjustments") {
                onApply(currentPP3())
                print("=== Current PP3 ===\n\(currentPP3())")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color.black.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(radius: 10)
    }
}
