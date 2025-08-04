/*
    RawUnravel - ContentView.swift
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
import ImageIO

// MARK: - ContentView (App Start Screen)

struct ContentView: View {
    // MARK: - UI State

    @State private var isPickerPresented = false
    @State private var selectedFilePath: String?
    @State private var isFileViewPresented = false
    @State private var showHelpScreen = false
    @State private var showAboutScreen = false

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                // Use VStack to control vertical placement
                VStack {
                    // MARK: - Top Spacer (Golden Ratio Placement)
                    // Push controls down to the golden ratio line
                    Spacer()
                        .frame(height: geo.size.height * 0.618)
                    RawUnravelLogo3D()
                    // MARK: - Main Control Row (About / Select / Help)
                    HStack {
                        // MARK: - About Button & Label
                        VStack(spacing: 2) {
                            Button(action: {
                                showAboutScreen = true
                            }) {
                                Image("unravel-logo")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 64, height: 32)
                                    .overlay(
                                        Rectangle()
                                            .stroke(Color.white, lineWidth: 1 / UIScreen.main.scale)
                                    )
                            }
                            Text("About…")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 8)

                        Spacer()

                        // MARK: - Select RAW File Button
                        Button("Select RAW File") {
                            isPickerPresented = true
                        }
                        .padding()
                        .buttonStyle(.borderedProminent)

                        Spacer()

                        // MARK: - Help Button & Label
                        VStack(spacing: 2) {
                            Button(action: {
                                showHelpScreen = true
                            }) {
                                Image(systemName: "questionmark.circle")
                                    .font(.title2)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Help")
                            Text("Help…")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                        .padding(.trailing, 8)
                    }
                    // Present Help or About sheets as needed
                    .sheet(isPresented: $showHelpScreen) {
                        HelpView()
                    }
                    .sheet(isPresented: $showAboutScreen) {
                        AboutView()
                    }

                    // MARK: - Bottom Spacer (fills rest of space)
                    Spacer()
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }

            // MARK: - File Picker Sheet
            .fullScreenCover(isPresented: $isPickerPresented) {
                DocumentPicker { url in
                    selectedFilePath = url.path
                    isPickerPresented = false
                    isFileViewPresented = true // Immediately show FileView
                }
            }

            // MARK: - Navigation to FileView (RAW Preview)
            .navigationDestination(isPresented: $isFileViewPresented) {
                if let selectedFilePath {
                    FileView(fileURL: URL(fileURLWithPath: selectedFilePath))
                }
            }
        }
    }
}

/// 3D, glowing, Star Wars-style RAWUnravel logo.
struct RawUnravelLogo3D: View {
    var body: some View {
        ZStack {
            // --- Orange Cinebloom Glow Layer ---
            Text("RAWUnravel")
                .font(.custom("News Gothic Bold", size: 48)) // Large size!
                .fontWeight(.bold)
                .foregroundColor(Color.orange.opacity(0.9))
                .blur(radius: 4)
                .rotation3DEffect(
                    .degrees(30), // Perspective tilt
                    axis: (x: 1, y: 0, z: 0),
                    anchor: .bottom,
                    perspective: 0.7
                )

            // --- Main Yellow Text Layer ---
            Text("RAWUnravel")
                .font(.custom("News Gothic Bold", size: 48))
                .fontWeight(.bold)
                .foregroundColor(Color(.systemYellow))
                .rotation3DEffect(
                    .degrees(30),
                    axis: (x: 1, y: 0, z: 0),
                    anchor: .bottom,
                    perspective: 0.7
                )
        }
        .frame(height: 70) // Adjust as needed!
        .padding(.bottom, 18)
        .accessibilityLabel("RAWUnravel logo")
    }
}
