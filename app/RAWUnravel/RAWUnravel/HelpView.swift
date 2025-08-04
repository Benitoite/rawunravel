/*
    RawUnravel - HelpView.swift
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

struct HelpRowItem: Identifiable {
    let id = UUID()
    let miniButton: AnyView?
    let systemName: String?
    let emoji: String?
    let title: String
    let description: String

    init(miniButton: AnyView, title: String, description: String) {
        self.miniButton = miniButton
        self.systemName = nil
        self.emoji = nil
        self.title = title
        self.description = description
    }
    init(systemName: String, title: String, description: String) {
        self.miniButton = nil
        self.systemName = systemName
        self.emoji = nil
        self.title = title
        self.description = description
    }
    init(emoji: String, title: String, description: String) {
        self.miniButton = nil
        self.systemName = nil
        self.emoji = emoji
        self.title = title
        self.description = description
    }
}

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showAbout = false

    // Edit this order if you add/rearrange tools!
    let toolRows: [HelpRowItem] = [
        // --- Tools ---
        .init(
            miniButton: AnyView(
                Button("Select RAW File") {}
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.vertical, 1)
                    .padding(.horizontal, 6)
                    .buttonStyle(.borderedProminent)
                    .allowsHitTesting(false)
                    .opacity(0.96)
            ),
            title: "Select",
            description: "Pick a RAW file"
        ),
        .init(emoji: "☀️", title: "Exposure", description: "Exposure, Black Point, Shadows sliders"),
        .init(emoji: "🌈", title: "Color", description: "Saturation, Vibrance, Temperature sliders"),
        .init(emoji: "✨", title: "Sharpen", description: "Coming soon! Sharpen details and clarity"),
        .init(emoji: "📸", title: "Screenshot", description: "Copy preview to clipboard"),
        .init(emoji: "📤", title: "Export", description: "Save to JPEG or Photos"),
        // --- Gestures ---
        .init(emoji: "🤏", title: "Pinch", description: "Zoom in/out"),
        .init(emoji: "☝️", title: "Double-tap", description: "1:1 zoom"),
        .init(emoji: "👆", title: "Drag", description: "Pan image"),
        .init(emoji: "☝️", title: "Fit", description: "Tap to fit"),
    ]

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let isLandscape = geo.size.width > geo.size.height

                ScrollView {
                    VStack(spacing: isLandscape ? 12 : 28) {
                        if isLandscape {
                            let numColumns = 2
                            let numRows = Int(ceil(Double(toolRows.count) / Double(numColumns)))
                            // Partition rows into columns (order preserved top to bottom, left to right)
                            let columns: [[HelpRowItem]] = stride(from: 0, to: toolRows.count, by: numRows).map { start in
                                Array(toolRows[start ..< min(start+numRows, toolRows.count)])
                            }
                            // Display as rows: [ [col0row0, col1row0], [col0row1, col1row1], ... ]
                            ForEach(0..<numRows, id: \.self) { row in
                                HStack(spacing: 12) {
                                    ForEach(0..<numColumns, id: \.self) { col in
                                        if columns.indices.contains(col), columns[col].indices.contains(row) {
                                            HelpRow(item: columns[col][row], compact: true)
                                        } else {
                                            Spacer()
                                        }
                                    }
                                }
                            }
                            // About button centered below
                            HStack {
                                Spacer()
                                Button(action: { showAbout = true }) {
                                    HStack(spacing: 12) {
                                        Image("unravel-logo")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 64, height: 32)
                                        Text("About RAWUnravel")
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                    }
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                                Spacer()
                            }
                            .padding(.top, 18)
                            .sheet(isPresented: $showAbout) { AboutView() }
                        } else {
                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(toolRows) { item in
                                    HelpRow(item: item)
                                }
                            }
                            Divider().padding(.vertical, 8)
                            // About button centered
                            HStack {
                                Spacer()
                                Button(action: { showAbout = true }) {
                                    HStack(spacing: 12) {
                                        Image("unravel-logo")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 64, height: 32)
                                        Text("About RAWUnravel")
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                    }
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                                Spacer()
                            }
                            .sheet(isPresented: $showAbout) { AboutView() }
                        }
                    }
                    .padding(.horizontal, isLandscape ? 8 : 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Help")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

struct HelpRow: View {
    let item: HelpRowItem
    var compact: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: compact ? 8 : 14) {
            if let miniButton = item.miniButton {
                miniButton
                    .frame(width: compact ? 76 : 88, height: compact ? 24 : 28)
            } else if let systemName = item.systemName {
                Image(systemName: systemName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: compact ? 26 : 34, height: compact ? 26 : 34)
                    .foregroundColor(.accentColor)
                    .accessibilityHidden(true)
            } else if let emoji = item.emoji {
                Text(emoji)
                    .font(.system(size: compact ? 24 : 30))
                    .frame(width: compact ? 26 : 34)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: compact ? 0 : 1) {
                Text(item.title)
                    .font(compact ? .body : .headline)
                Text(item.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
