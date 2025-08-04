/*
    RawUnravel - AboutView.swift
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
import UIKit

// MARK: - ClippedMultilineText

struct ClippedMultilineText: UIViewRepresentable {
    let text: String
    let font: UIFont
    let textColor: UIColor
    let labelWidth: CGFloat

    // Returns the rendered height of the label for the text and width
    static func requiredHeight(for text: String, font: UIFont, width: CGFloat) -> CGFloat {
        let constraintSize = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        let boundingRect = text.boundingRect(
            with: constraintSize,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return ceil(boundingRect.height)
    }

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byClipping
        label.textAlignment = .center
        label.backgroundColor = .clear
        label.adjustsFontSizeToFitWidth = false
        label.textColor = textColor
        label.font = font

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        label.attributedText = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ])
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.text = text
        label.font = font
        label.textColor = textColor

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        label.attributedText = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ])
    }
}

// MARK: - StarWarsScrollText

struct StarWarsScrollText: View {
    @State private var offsetY: CGFloat = 0

    let crawlText = """
    RawUnravel is an open
    source RAW image
    processor, allowing
    you to preview, develop,
    and export RAW files.

    ©2025 Richard E. Barber

    Special thanks:

    Authors of RawTherapee
    Librtprocess
    LibRaw
    Beta testers

    Licensed GPLv3+

    RawUnravel is free software:
    you can redistribute it and/
    or modify it under the terms
    of the Gnu General Public
    License as published by the
    Free Software Foundation,
    either version 3 of the
    License, or (at your option)
    any later version.

    RawUnravel is distributed in
    the hope that it will be
    useful, but without any
    warranty; without even the
    implied warranty of
    merchantability or fitness
    for a particular purpose.
    The Gnu General Public
    License has more details.

    You should have received a
    copy of the Gnu General
    Public License along with
    RawUnravel. If not, see
    <https://www.gnu.org/
    licenses/>.
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    """
    var body: some View {
        GeometryReader { geo in
            let crawlWidth = geo.size.width * 2.5
            let font = UIFont(name: "News Gothic Bold", size: 30) ?? UIFont.systemFont(ofSize: 30, weight: .bold)
            let labelHeight = ClippedMultilineText.requiredHeight(for: crawlText, font: font, width: crawlWidth)

            VStack {
                Spacer()
                ZStack {
                    // --- Orange Glow (Cinebloom) Layer ---
                    ClippedMultilineText(
                        text: crawlText,
                        font: font,
                        textColor: UIColor.orange.withAlphaComponent(0.97),
                        labelWidth: crawlWidth
                    )
                    .frame(width: geo.size.width, height: labelHeight)
                    .position(
                        x: geo.size.width / 2 - 8,
                        y: offsetY + labelHeight / 2
                    )
                    .rotation3DEffect(
                        .degrees(46),
                        axis: (x: 1, y: 0, z: 0),
                        anchor: .bottom,
                        perspective: 0.77
                    )
                    .blur(radius: 3.5)

                    // --- Main Text Layer ---
                    ClippedMultilineText(
                        text: crawlText,
                        font: font,
                        textColor: UIColor.yellow,
                        labelWidth: crawlWidth
                    )
                    .frame(width: geo.size.width, height: labelHeight)
                    .position(
                        x: geo.size.width / 2 - 8,
                        y: offsetY + labelHeight / 2
                    )
                    .rotation3DEffect(
                        .degrees(46),
                        axis: (x: 1, y: 0, z: 0),
                        anchor: .bottom,
                        perspective: 0.77
                    )

                }
                .frame(width: geo.size.width, height: 300)
                .clipped()
                Spacer()
            }
            .background(Color.black)
            .onAppear {
                offsetY = 287
                withAnimation(.easeIn(duration: 80).repeatForever(autoreverses: false)) {
                    offsetY = -labelHeight
                }
            }
        }
        .frame(height: 300)
    }

}

// MARK: - AboutView

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var showLicenseSheet = false

    private func openURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let isLandscape = geo.size.width > geo.size.height
                Group {
                    if isLandscape {
                        AboutLandscapeView(
                            colorScheme: colorScheme,
                            openURL: openURL
                        )
                    } else {
                        AboutPortraitView(
                            colorScheme: colorScheme,
                            openURL: openURL
                        )
                    }
                }
                .background(Color.black)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("License") { showLicenseSheet = true }
                }
            }
            .sheet(isPresented: $showLicenseSheet) {
                LicenseSheet()
            }
        }
        .background(Color.black)
    }
}

// MARK: - Portrait Subview

struct AboutPortraitView: View {
    let colorScheme: ColorScheme
    let openURL: (String) -> Void

    var body: some View {
        VStack(spacing: 20) {
            AboutLogoTitle()
            StarWarsScrollText()
                .padding()
            Spacer()
            AboutButtonTrio(colorScheme: colorScheme, openURL: openURL)
                .padding(.bottom, 40)
        }
        .padding()
        .background(Color.black)
    }
}

// MARK: - Landscape Subview

struct AboutLandscapeView: View {
    let colorScheme: ColorScheme
    let openURL: (String) -> Void

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                VStack {
                    Spacer()
                    VStack(spacing: 24) {
                        AboutLogoTitle()
                        AboutButtonTrio(colorScheme: colorScheme, openURL: openURL)
                            .padding(.top, 8)
                    }
                    Spacer()
                }
                .frame(width: geo.size.width * 0.45, height: geo.size.height)
                .background(Color.black)

                VStack {
                    Spacer()
                    StarWarsScrollText()
                        .frame(width: geo.size.width * 0.55, height: 300)
                        .background(Color.black)
                        .padding(.top, 24)
                    Spacer()
                }
            }
            .background(Color.black)
        }
    }
}

// MARK: - Logo+Title

struct AboutLogoTitle: View {
    var body: some View {
        VStack(spacing: 10) {
            Image("unravel-logo")
                .resizable()
                .scaledToFit()
                .frame(width: 128, height: 64)
                .overlay(
                    Rectangle()
                        .stroke(Color.white, lineWidth: 1 / UIScreen.main.scale)
                )
            Text("RAWUnravel")
                .font(.largeTitle)
                .bold()
        }
    }
}

// MARK: - Button Trio

struct AboutButtonTrio: View {
    let colorScheme: ColorScheme
    let openURL: (String) -> Void

    var body: some View {
        HStack(spacing: 40) {
            VStack {
                Button {
                    openURL("https://github.com/Benitoite/rawunravel")
                } label: {
                    Image(colorScheme == .dark ? "github-mark-white" : "github-mark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .accessibilityLabel("GitHub Repository")
                }
                Text("Repo")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.secondary)
            }
            VStack {
                Button {
                    openURL("https://www.paypal.com/paypalme/reb42")
                } label: {
                    Image("paypal")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 128, height: 52)
                        .accessibilityLabel("PayPal Support")
                }
                Text("Donate")
                    .font(.title3.weight(.bold))
                    .foregroundColor(Color(red: 0.0, green: 0.5, blue: 0.0))
            }
            VStack {
                Button {
                    openURL("https://discuss.pixls.us")
                } label: {
                    Image("px-logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .accessibilityLabel("Pixls.us Forum")
                }
                Text("Forum")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.secondary)
            }
        }
    }
}
