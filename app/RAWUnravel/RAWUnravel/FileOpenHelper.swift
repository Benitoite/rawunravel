/*
    RawUnravel - FileOpenHelper.swift
    ---------------------------------
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

import Foundation
import UniformTypeIdentifiers

// MARK: - FileOpenHelper (actor)

/// Centralized helper that safely copies file-provider URLs (iCloud Drive, Files app, etc.)
/// into the app's own temporary directory.
/// Ensures stable access to RAW files without relying on provider sandbox lifetimes.
actor FileOpenHelper {
    /// Global singleton instance (actor = serialized for safety).
    static let shared = FileOpenHelper()

    // MARK: - Core Import Method

    /// Copy a provider URL into app temp storage.
    /// - Parameter providerURL: The security-scoped URL handed off by UIDocumentPicker / PHPicker.
    /// - Returns: A stable temp URL inside `RAWUnravel_Imported` or `nil` on failure.
    func copyProviderToTempIfNeeded(_ providerURL: URL) async -> URL? {
        // ---- Guard: Only handle RAW image formats (skip others) ----
        guard UTType(filenameExtension: providerURL.pathExtension.lowercased())?.conforms(to: .rawImage) == true else {
            return nil
        }

        // ---- Security scope (needed for external providers) ----
        var started = false
        if providerURL.startAccessingSecurityScopedResource() { started = true }
        defer { if started { providerURL.stopAccessingSecurityScopedResource() } }

        // ---- Destination: app temp folder ----
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("RAWUnravel_Imported", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

            // Build unique destination (UUID prevents races / overwrites)
            let dest = base.appendingPathComponent(UUID().uuidString + "-" + providerURL.lastPathComponent)

            // Clean up any previous copy
            if FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.removeItem(at: dest)
            }

            // ---- Actual copy ----
            try FileManager.default.copyItem(at: providerURL, to: dest)
            return dest
        } catch {
            // Any I/O error: fall back to nil
            return nil
        }
    }

    // MARK: - Back-compat alias

    /// Legacy alias — kept so older call sites still compile.
    func importRAW(from url: URL) async -> URL? {
        await copyProviderToTempIfNeeded(url)
    }
}
