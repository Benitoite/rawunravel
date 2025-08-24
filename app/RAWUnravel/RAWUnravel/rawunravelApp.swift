/*
    RawUnravel - RawUnravelApp.swift
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

// MARK: - Application Entry

/// The root entry point for RawUnravel.
///
/// - Instantiates the global `RawUnravelRouter` as a `@StateObject`
///   so it lives for the lifetime of the app.
/// - Injects the router into the SwiftUI environment so views can
///   observe and navigate.
/// - Handles `onOpenURL` for `.rawImage` UTTypes (drag & drop, share sheet,
///   Files app "Open in…", etc.) by copying provider URLs into the app’s
///   tmp directory before navigation.
@main
struct RawUnravelApp: App {
    @StateObject private var router = RawUnravelRouter()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(router)
                .onOpenURL { url in
                    // Only handle UTType-conforming RAW files
                    guard UTType(filenameExtension: url.pathExtension.lowercased())?
                            .conforms(to: .rawImage) == true else {
                        return
                    }

                    // Copy provider URL to tmp before navigating.
                    Task {
                        let temp = await copyProviderURLToAppTemp(url)
                        if let temp = temp {
                            // ✅ Safe in-app copy ready
                            router.destination = .file(temp, temp.lastPathComponent)
                        } else {
                            // ❌ Fallback: still try provider URL directly
                            router.destination = .file(url, url.lastPathComponent)
                        }
                    }
                }
        }
    }

    // MARK: - Provider File Copy

    /// Try to copy a provider-scoped URL into app tmp storage (async).
    ///
    /// - Returns: a tmp URL on success, or `nil` on failure.
    private func copyProviderURLToAppTemp(_ providerURL: URL) async -> URL? {
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                var didStart = false
                if providerURL.startAccessingSecurityScopedResource() {
                    didStart = true
                }
                defer {
                    if didStart { providerURL.stopAccessingSecurityScopedResource() }
                }

                // Ensure the extension really is a RAW image
                guard UTType(filenameExtension: providerURL.pathExtension.lowercased())?
                        .conforms(to: .rawImage) == true else {
                    cont.resume(returning: nil)
                    return
                }

                let tmpBase = FileManager.default.temporaryDirectory
                    .appendingPathComponent("RAWUnravel_Imported", isDirectory: true)
                do {
                    try FileManager.default.createDirectory(at: tmpBase, withIntermediateDirectories: true)
                    let dest = tmpBase.appendingPathComponent(UUID().uuidString + "-" + providerURL.lastPathComponent)

                    if FileManager.default.fileExists(atPath: dest.path) {
                        try? FileManager.default.removeItem(at: dest)
                    }

                    try FileManager.default.copyItem(at: providerURL, to: dest)
                    cont.resume(returning: dest)
                } catch {
                    cont.resume(returning: nil)
                }
            }
        }
    }
}
