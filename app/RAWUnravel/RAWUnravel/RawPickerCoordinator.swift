/*
    RawUnravel - RawPicker.swift
    ----------------------------
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
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Coordinator
/// UIKit delegate to handle PHPicker results.
/// Copies selected RAW/image into app temp dir and notifies SwiftUI.
class RawPickerCoordinator: NSObject, PHPickerViewControllerDelegate {
    var onRAWSelected: (URL, String) -> Void

    init(onRAWSelected: @escaping (URL, String) -> Void) {
        self.onRAWSelected = onRAWSelected
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)

        // Only handle first selected item
        guard let itemProvider = results.first?.itemProvider else { return }

        // Accept multiple RAW/image UTI identifiers
        let utis = [
            "public.camera-raw-image",
            "public.jpeg",
            "public.png",
            "public.heic",
            "public.tiff",
            "public.image"
        ]

        for uti in utis where itemProvider.hasItemConformingToTypeIdentifier(uti) {
            itemProvider.loadFileRepresentation(forTypeIdentifier: uti) { url, _ in
                guard let sourceURL = url else { return }

                // Preserve extension if present, otherwise default to .img
                let ext = sourceURL.pathExtension.isEmpty ? "img" : sourceURL.pathExtension
                let originalName = sourceURL.lastPathComponent

                // Copy to temp directory to ensure safe, stable access
                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("RAWUnravelSelected", isDirectory: true)
                do {
                    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    let destURL = tempDir.appendingPathComponent("selected.\(ext)")

                    // Ensure clean overwrite
                    try? FileManager.default.removeItem(at: destURL)
                    try FileManager.default.copyItem(at: sourceURL, to: destURL)

                    DispatchQueue.main.async {
                        self.onRAWSelected(destURL, originalName)
                    }
                } catch {
                    // Silent failure; could log in debug builds
                }
            }
            break
        }
    }
}

// MARK: - SwiftUI Wrapper
/// SwiftUI-compatible PHPicker wrapper.
/// Presents the system image picker and delivers selection via closure.
struct RawPickerViewController: UIViewControllerRepresentable {
    var onRAWSelected: (URL, String) -> Void

    func makeCoordinator() -> RawPickerCoordinator {
        RawPickerCoordinator(onRAWSelected: onRAWSelected)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images              // Restrict to image/RAW types
        config.preferredAssetRepresentationMode = .current
        config.selectionLimit = 1            // Single selection only

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
}
