/*
    RawUnravel - DocumentPicker.swift
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
import UniformTypeIdentifiers

// MARK: - DocumentPicker

/// Presents a document picker for image and RAW files, remembers last open directory.
struct DocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void
    @AppStorage("LastOpenDirectory") private var lastDirectoryPath: String?

    // MARK: - Coordinator (UIDocumentPickerDelegate)

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, lastDirectoryPath: $lastDirectoryPath)
    }

    // MARK: - UIViewControllerRepresentable

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Supported file types: TIFF, JPEG, PNG, and major RAW formats
        let supportedTypes: [UTType] = [
            UTType.tiff,
            UTType.jpeg,
            UTType.png
        ] + [
            "com.adobe.raw-image",
            "public.camera-raw-image",
            "com.canon.cr2-raw-image",
            "com.nikon.nef-raw-image",
            "com.sony.arw-raw-image"
        ].compactMap { UTType($0) }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes, asCopy: true)
        print("Restoring picker to:", lastDirectoryPath ?? "<none>")
        // Restore last used directory if possible (iOS 16+)
        if let lastDir = lastDirectoryPath {
            picker.directoryURL = URL(fileURLWithPath: lastDir)
        }
        picker.delegate = context.coordinator
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    // MARK: - Coordinator

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onPick: (URL) -> Void
        @Binding var lastDirectoryPath: String?

        init(onPick: @escaping (URL) -> Void, lastDirectoryPath: Binding<String?>) {
            self.onPick = onPick
            self._lastDirectoryPath = lastDirectoryPath
        }

        /// Copies the picked RAW file to the app's Documents directory for stable access.
        func persistPickedRAW(url: URL) -> URL? {
            let fileManager = FileManager.default
            let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            let destURL = docs.appendingPathComponent(url.lastPathComponent)
            do {
                if fileManager.fileExists(atPath: destURL.path) {
                    try fileManager.removeItem(at: destURL)
                }
                try fileManager.copyItem(at: url, to: destURL)
                return destURL
            } catch {
                print("Failed to copy file to Documents: \(error)")
                return nil
            }
        }

        // MARK: - UIDocumentPickerDelegate

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let firstURL = urls.first, let stableURL = persistPickedRAW(url: firstURL) {
                let dir = firstURL.deletingLastPathComponent()
                print("Saving last directory:", dir.path)
                lastDirectoryPath = dir.path
                onPick(stableURL)
            } else {
                print("Failed to persist picked file.")
            }
        }
    }
}
