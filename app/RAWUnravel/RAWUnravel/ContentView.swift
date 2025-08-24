/*
    RawUnravel - ContentView.swift
    --------------------------------
    Copyright (C) 2025 Richard Barber
    GPL-3.0-or-later
*/

import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import Combine 
// MARK: - ContentView (App Start Screen)
enum RawSourceType {
    case none, files, photos
}

struct ContentView: View {
    // MARK: - UI State
    @EnvironmentObject private var router: RawUnravelRouter

    @State private var sourceSheetPresented = false
    @State private var sourceType: RawSourceType = .none
    @State private var isPickerPresented = false
    @State private var isPhotoPickerPresented = false

    // Use URL state (full URL) rather than path strings
    @State private var selectedFileURL: URL? = nil
    @State private var isFileViewPresented = false
    @State private var showHelpScreen = false
    @State private var showAboutScreen = false
    @State private var selectedFileDisplayName: String? = nil

    // New: local staging for router-driven (external) opens
    @State private var externalFileToOpen: (url: URL, displayName: String?)? = nil
    @State private var showExternalFile: Bool = false

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    Spacer(minLength: geo.size.height * 0.618 - 90) // Golden ratio anchor
                    RawUnravelLogo3D()

                    // MARK: - Main Control Row (About / Select / Help)
                    HStack {
                        // About Button & Label
                        VStack(spacing: 2) {
                            Button(action: { showAboutScreen = true }) {
                                Image("unravel-logo")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 64, height: 32)
                                    .overlay(Rectangle().stroke(Color.white, lineWidth: 1 / UIScreen.main.scale))
                            }
                            Text("About…")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)

                        Spacer()

                        // Select RAW File Button
                        Button("Select RAW File") {
                            sourceSheetPresented = true
                        }
                        .padding()
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)

                        Spacer()

                        // Help Button & Label
                        VStack(spacing: 2) {
                            Button(action: { showHelpScreen = true }) {
                                Image(systemName: "questionmark.circle").font(.title2)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Help")
                            Text("Help…")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)

                    Spacer()
                }
                .frame(width: geo.size.width, height: geo.size.height)
                // Help sheet
                .sheet(isPresented: $showHelpScreen) { HelpView() }
            }

            // MARK: - Navigation destination for picker-based selection
            .navigationDestination(isPresented: $isFileViewPresented) {
                if let url = selectedFileURL {
                    FileView(
                        fileURL: url,
                        displayName: selectedFileDisplayName ?? url.lastPathComponent,
                        showCancelButton: false
                    )
                }
            }

            // MARK: - Fullscreen Document Picker (Files.app)
            .fullScreenCover(isPresented: $isPickerPresented) {
                DocumentPicker { pickedURL in
                    // Copy provider file to our temp directory off the main thread,
                    // then present FileView only after the copy finishes.
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            let local = try RUImport.copyToTemp(pickedURL)
                            DispatchQueue.main.async {
                                selectedFileURL = local
                                selectedFileDisplayName = pickedURL.lastPathComponent
                                isPickerPresented = false
                                isFileViewPresented = true
                            }
                        } catch {
                            DispatchQueue.main.async {
                                isPickerPresented = false
                                isFileViewPresented = false
                                // optionally handle the error
                            }
                        }
                    }
                }
            }

            // MARK: - Photo picker sheet (copies inside callback)
            .sheet(isPresented: $isPhotoPickerPresented) {
                RawPickerViewController { pickedURL, originalName in
                    DispatchQueue.global(qos: .userInitiated).async {
                        let local = try? RUImport.copyToTemp(pickedURL)
                        DispatchQueue.main.async {
                            selectedFileURL = local
                            selectedFileDisplayName = originalName
                            isPhotoPickerPresented = false
                            isFileViewPresented = (local != nil)
                        }
                    }
                }
            }

            // MARK: - Source chooser (rounded panel)
            .sheet(isPresented: $sourceSheetPresented) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(Color(.systemBackground))
                        .frame(width: 346, height: 160)
                        .shadow(radius: 10, y: 2)
                        .overlay(
                            VStack(spacing: 0) {
                                Text("Import RAW From…")
                                    .font(.headline)
                                    .padding(.top, 16)
                                HStack(spacing: 64) {
                                    // Files
                                    Button(action: {
                                        sourceType = .files
                                        sourceSheetPresented = false
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { isPickerPresented = true }
                                    }) {
                                        VStack(spacing: 6) {
                                            Image(systemName: "folder")
                                                .resizable().scaledToFit().frame(width: 46, height: 46)
                                                .foregroundColor(.accentColor)
                                            Text("Files").font(.subheadline)
                                        }
                                        .padding(16)
                                        .contentShape(RoundedRectangle(cornerRadius: 14))
                                    }
                                    // Photos
                                    Button(action: {
                                        sourceType = .photos
                                        sourceSheetPresented = false
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { isPhotoPickerPresented = true }
                                    }) {
                                        VStack(spacing: 6) {
                                            Image(systemName: "photo.on.rectangle.angled")
                                                .resizable().scaledToFit().frame(width: 46, height: 46)
                                                .foregroundColor(Color(red: 1.0, green: 0.0, blue: 1.0))
                                            Text("Photos").font(.subheadline)
                                        }
                                        .padding(16)
                                        .contentShape(RoundedRectangle(cornerRadius: 14))
                                    }
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                Spacer(minLength: 0)
                            }
                        )
                }
                .frame(width: 288, height: 200)
                .presentationDetents([.height(220)])
                .background(Color.clear)
            }

            // (NOTE: previously you used fullScreenCover(item: $router.destination, ...). That is removed.)
        }
        // About presentation: iPhone sheet, iPad fullscreen
        .sheet(isPresented: Binding(get: { !isPad && showAboutScreen }, set: { if !$0 { showAboutScreen = false } })) {
            AboutView()
        }
        .fullScreenCover(isPresented: Binding(get: { isPad && showAboutScreen }, set: { if !$0 { showAboutScreen = false } })) {
            AboutView()
        }

        // ----------------------------
        // Router -> local capture -> boolean-driven presentation
        // ----------------------------

        .onReceive(router.$destination) { newDest in
            guard let dest = newDest else { return }
            switch dest {
            case .file(let url, let displayName):
                // capture locally and present via boolean-driven fullScreenCover
                externalFileToOpen = (url: url, displayName: displayName)
                showExternalFile = true
            }
        }
        
        .fullScreenCover(isPresented: $showExternalFile, onDismiss: {
            router.dismiss()
            externalFileToOpen = nil
        }) {
            if let ext = externalFileToOpen {
                FileOpenWrapper(sourceURL: ext.url, displayName: ext.displayName, showCancelButton: true)
                    .ignoresSafeArea()
            } else {
                EmptyView()
            }
        }
    }

    // MARK: - Wrapper that copies provider URL into app temp before presenting FileView
    struct FileOpenWrapper: View {
        let sourceURL: URL
        let displayName: String?
        let showCancelButton: Bool

        @State private var localURL: URL? = nil
        @State private var errorMessage: String? = nil
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            Group {
                if let local = localURL {
                    NavigationStack {
                        FileView(
                            fileURL: local,
                            displayName: displayName ?? sourceURL.lastPathComponent,
                            showCancelButton: showCancelButton
                        )
                    }
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Text("Could not open file")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                        HStack {
                            Button("Close") { dismiss() }.buttonStyle(.bordered)
                        }
                    }
                    .padding()
                } else {
                    VStack {
                        ProgressView("Preparing file…")
                            .progressViewStyle(CircularProgressViewStyle())
                            .padding()
                    }
                    .onAppear { performCopy() }
                }
            }
        }

        private func performCopy() {
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let local = try RUImport.copyToTemp(sourceURL)

                    // Extra safety: ensure the file is present & stable before presenting
                    let fm = FileManager.default
                    let deadline = Date().addingTimeInterval(6.0)
                    var ready = false
                    while Date() < deadline {
                        if fm.fileExists(atPath: local.path),
                           let attrs = try? fm.attributesOfItem(atPath: local.path),
                           let size = attrs[.size] as? NSNumber,
                           size.intValue > 0 {
                            // small delay to ensure filesystem has settled
                            Thread.sleep(forTimeInterval: 0.12)
                            // re-check size didn't drop to zero
                            if let attrs2 = try? fm.attributesOfItem(atPath: local.path),
                               let size2 = attrs2[.size] as? NSNumber, size2.intValue > 0 {
                                ready = true
                                break
                            }
                        }
                        Thread.sleep(forTimeInterval: 0.08)
                    }

                    DispatchQueue.main.async {
                        if ready {
                            self.localURL = local
                        } else {
                            self.errorMessage = "Imported file was not ready."
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    // MARK: - 3D Logo
    struct RawUnravelLogo3D: View {
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            ZStack {
                if colorScheme == .light {
                    Text("RAWUnravel")
                        .font(.custom("News Gothic Bold", size: 54))
                        .fontWeight(.bold)
                        .foregroundColor(.black.opacity(0.53))
                        .blur(radius: 9)
                        .offset(y: 2)
                        .allowsHitTesting(false)
                }
                Text("RAWUnravel")
                    .font(.custom("News Gothic Bold", size: 53))
                    .fontWeight(.bold)
                    .foregroundColor(Color.orange.opacity(0.9))
                    .blur(radius: 4)
                    .rotation3DEffect(.degrees(30), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.7)
                Text("RAWUnravel")
                    .font(.custom("News Gothic Bold", size: 53))
                    .fontWeight(.bold)
                    .foregroundColor(Color(.systemYellow))
                    .rotation3DEffect(.degrees(30), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.7)
            }
            .frame(height: 70)
            .padding(.bottom, 18)
            .accessibilityLabel("RAWUnravel logo")
        }
    }
}
