/*
    RawUnravel - RUImport.swift
    ---------------------------
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

import Foundation
import UniformTypeIdentifiers

// MARK: - RUImport
// Provides safe import of RAW files from security-scoped file providers
// into a local temporary directory, suitable for LibRaw/librtprocess.
// Ensures files are copied (not linked) and validated, and cleans up old imports.

enum RUImport {

    // MARK: Copy to Temp
    
    /// Copy a (possibly security-scoped) file-provider URL into app's tmp dir.
    /// Always call from a background queue to avoid blocking the main thread.
    /// - Parameter url: Security-scoped URL returned from a file importer.
    /// - Returns: Local tmp URL safe for decoding.
    static func copyToTemp(_ url: URL) throws -> URL {
        if Thread.isMainThread {
            // Not fatal, but strongly recommend calling off-main.
        }

        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent("RAWUnravel_Imported", isDirectory: true)
        try? fm.createDirectory(at: baseDir, withIntermediateDirectories: true)

        let destURL = baseDir.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")

        let didStartOriginal = url.startAccessingSecurityScopedResource()
        defer { if didStartOriginal { url.stopAccessingSecurityScopedResource() } }

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordError: NSError?
        var lastError: Error?

        coordinator.coordinate(readingItemAt: url, options: [.forUploading], error: &coordError) { readingURL in
            let didStartReadingURL = readingURL.startAccessingSecurityScopedResource()
            defer { if didStartReadingURL { readingURL.stopAccessingSecurityScopedResource() } }

            let maxAttempts = 6
            for attempt in 0..<maxAttempts {
                do {
                    try? fm.removeItem(at: destURL)
                    try fm.copyItem(at: readingURL, to: destURL)

                    if let attrs = try? fm.attributesOfItem(atPath: destURL.path),
                       let size = attrs[.size] as? NSNumber, size.intValue > 0 {
                        lastError = nil
                        break
                    } else {
                        try? fm.removeItem(at: destURL)
                        lastError = NSError(domain: "RUImport", code: -2,
                                            userInfo: [NSLocalizedDescriptionKey: "Copied file has zero size."])
                    }
                } catch {
                    lastError = error
                    do {
                        let data = try Data(contentsOf: readingURL, options: [.mappedIfSafe])
                        try data.write(to: destURL, options: [.atomic])
                        if let attrs = try? fm.attributesOfItem(atPath: destURL.path),
                           let size = attrs[.size] as? NSNumber, size.intValue > 0 {
                            lastError = nil
                            break
                        } else {
                            try? fm.removeItem(at: destURL)
                            lastError = NSError(domain: "RUImport", code: -3,
                                                userInfo: [NSLocalizedDescriptionKey: "Written file has zero size."])
                        }
                    } catch {
                        lastError = error
                        try? fm.removeItem(at: destURL)
                    }
                }
                if attempt < maxAttempts - 1 {
                    Thread.sleep(forTimeInterval: 0.12 + Double(attempt) * 0.05)
                }
            }
        }

        if let ce = coordError { throw ce }
        guard fm.fileExists(atPath: destURL.path) else {
            throw lastError ?? NSError(domain: "RUImport", code: -1,
                                       userInfo: [NSLocalizedDescriptionKey: "Provider did not vend a local file."])
        }

        let attrs = try fm.attributesOfItem(atPath: destURL.path)
        if let size = attrs[.size] as? NSNumber, size.intValue > 0 {
            return destURL
        } else {
            try? fm.removeItem(at: destURL)
            throw lastError ?? NSError(domain: "RUImport", code: -4,
                                       userInfo: [NSLocalizedDescriptionKey: "Imported file appears empty."])
        }
    }

    // MARK: Prune Old Imports
    
    /// Delete imported temporary files older than `days` (default: 3).
    /// Safe to call at app launch to keep tmp directory clean.
    static func pruneOldTempImports(olderThan days: Int = 3) {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent("RAWUnravel_Imported", isDirectory: true)
        guard let urls = try? fm.contentsOfDirectory(at: baseDir,
                                                     includingPropertiesForKeys: [.contentModificationDateKey],
                                                     options: [.skipsHiddenFiles]) else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        for u in urls {
            let rv = try? u.resourceValues(forKeys: [.contentModificationDateKey])
            if (rv?.contentModificationDate ?? .distantPast) < cutoff {
                try? fm.removeItem(at: u)
            }
        }
    }
}
