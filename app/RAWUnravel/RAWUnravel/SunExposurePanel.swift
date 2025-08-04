/*
    RawUnravel - SunExposurePanel.swift
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

// MARK: - ResetCircleIcon

/// Circle reset icon used for slider reset actions throughout UI panels.
struct ResetCircleIcon: View {
    let systemName: String
    let size: CGFloat
    let enabled: Bool
    let showLabel: Bool

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                // Faded background for default, pops when enabled
                Circle()
                    .fill(enabled ? Color.white : Color.gray.opacity(0.18))
                    .frame(width: enabled ? size + 10 : size + 2, height: enabled ? size + 10 : size + 2)
                    .shadow(color: .black.opacity(enabled ? 0.22 : 0.10), radius: enabled ? 2 : 1, x: 0, y: 1)
                    .overlay(
                        Circle()
                            .stroke(enabled ? Color.black : Color.gray.opacity(0.45), lineWidth: enabled ? 1.4 : 1.0)
                    )
                Image(systemName: systemName)
                    .font(.system(size: enabled ? size : size * 0.93, weight: .bold))
                    .foregroundColor(enabled ? .black : .gray.opacity(0.45))
                    .scaleEffect(enabled ? 1.05 : 0.92)
                    .opacity(enabled ? 1 : 0.45)
            }
            .animation(.easeInOut(duration: 0.16), value: enabled)
            .accessibilityLabel("Reset to default")
            if showLabel {
                Text("Reset")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.top, 0)
                    .shadow(color: .black, radius: 0.5, x: 0, y: 0.5)
            }
        }
    }
}

// MARK: - SunExposurePanel

/// Exposure, black point, and shadows control panel for RAW development.
struct SunExposurePanel: View {
    @Binding var exposure: Float
    @Binding var blackPoint: Float
    @Binding var shadows: Float
    var onApply: (String) -> Void

    // MARK: - Defaults
    let defaultExposure: Float = 0.0
    let defaultBlack: Float = 0.0
    let defaultShadows: Float = 0.0

    // MARK: - Generate PP3 String
    func currentPP3() -> String {
        """
        [Exposure]
        Compensation = \(String(format: "%.2f", exposure))
        Black = \(Int(blackPoint))
        Shadows = \(String(format: "%.2f", shadows))

        [RAW]
        """
    }

    // MARK: - Main Panel View
    var body: some View {
        VStack(spacing: 22) {
            // Exposure
            VStack(alignment: .leading) {
                ZStack {
                    Text("Exposure Compensation: \(String(format: "%.2f", exposure))")
                        .font(.body)
                        .shadow(color: .white, radius: 0.5, x: 0, y: 0.5)
                    Text("Exposure Compensation: \(String(format: "%.2f", exposure))")
                        .foregroundColor(.white)
                        .offset(x: 1, y: 0.5)
                }
                HStack {
                    Slider(value: $exposure, in: -5.0...5.0, step: 0.1)
                    Button(action: { exposure = defaultExposure }) {
                        ResetCircleIcon(
                            systemName: "arrow.uturn.backward.circle.fill",
                            size: 22,
                            enabled: exposure != defaultExposure,
                            showLabel: false
                        )
                    }
                    .padding(.leading, 4)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Reset Exposure Compensation")
                }
            }

            // Black Point
            VStack(alignment: .leading) {
                ZStack {
                    Text("Black Point: \(Int(blackPoint))")
                        .font(.body)
                        .shadow(color: .white, radius: 0.5, x: 0, y: 0.5)
                    Text("Black Point: \(Int(blackPoint))")
                        .foregroundColor(.white)
                        .offset(x: 1, y: 0.5)
                }
                HStack {
                    Slider(value: $blackPoint, in: -200.0...200.0, step: 1.0)
                    Button(action: { blackPoint = defaultBlack }) {
                        ResetCircleIcon(
                            systemName: "arrow.uturn.backward.circle.fill",
                            size: 22,
                            enabled: blackPoint != defaultBlack,
                            showLabel: false
                        )
                    }
                    .padding(.leading, 4)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Reset Black Point")
                }
            }

            // Shadows
            VStack(alignment: .leading) {
                ZStack {
                    Text("Shadows: \(String(format: "%.2f", shadows))")
                        .font(.body)
                        .shadow(color: .white, radius: 0.5, x: 0, y: 0.5)
                    Text("Shadows: \(String(format: "%.2f", shadows))")
                        .foregroundColor(.white)
                        .offset(x: 1, y: 0.5)
                }
                HStack {
                    Slider(value: $shadows, in: 0.0...100.0, step: 0.1)
                    Button(action: { shadows = defaultShadows }) {
                        ResetCircleIcon(
                            systemName: "arrow.uturn.backward.circle.fill",
                            size: 22,
                            enabled: shadows != defaultShadows,
                            showLabel: false
                        )
                    }
                    .padding(.leading, 4)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Reset Shadows")
                }
            }

            // MARK: - Apply Button
            Button("Apply Adjustments") {
                onApply(currentPP3())
                print("=== Current PP3 ===\n\(currentPP3())")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
