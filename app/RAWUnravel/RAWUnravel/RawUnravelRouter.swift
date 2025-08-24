/*
    RawUnravel - RawUnravelRouter.swift
    -----------------------------------
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
import SwiftUI

// MARK: - RawUnravelRouter

/// Global navigation/router for RawUnravel.
///
/// This object handles high-level navigation flow from
/// file imports into the app’s working views. It ensures
/// that file-provider URLs (iCloud, Files app, AirDrop, etc.)
/// are safely copied into the app’s tmp directory via `RUImport`
/// before being opened by the RAW decoder.
///
/// Use `@EnvironmentObject var router: RawUnravelRouter`
/// in SwiftUI views to present or dismiss destinations.
final class RawUnravelRouter: ObservableObject {

    // MARK: - Destinations

    /// Destination enum used for navigation targets.
    /// Currently only supports `file`, but can be expanded
    /// for future panels/screens (e.g. Settings, Export, etc).
    enum Destination: Identifiable {
        case file(URL, String?)

        /// Unique ID for SwiftUI navigation.
        var id: String {
            switch self {
            case .file(let url, _): return url.absoluteString
            }
        }
    }

    // MARK: - Published State

    /// The currently active navigation target.
    @Published var destination: Destination?

    // MARK: - Actions

    /// Open a picked/imported file URL into the app.
    ///
    /// - Parameters:
    ///   - url: Original file-provider URL (security scoped).
    ///   - displayName: Optional override for display name; defaults to `lastPathComponent`.
    func open(url: URL, displayName: String? = nil) {
        // Always copy into tmp sandbox before decode (safe, stable path).
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let local = try RUImport.copyToTemp(url)
                DispatchQueue.main.async {
                    // Route to the file screen once safe copy is ready
                    self.destination = .file(local, displayName ?? url.lastPathComponent)
                }
            } catch {
                DispatchQueue.main.async {
                    // Fail silently for now; could be expanded to
                    // show an error toast or alert in the UI.
                    // print("❌ Router open failed:", error.localizedDescription)
                }
            }
        }
    }

    /// Dismiss the currently active destination.
    func dismiss() { destination = nil }
}
