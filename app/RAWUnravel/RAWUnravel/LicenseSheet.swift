//
//  LicenseSheet.swift
//  RawUnravel
//
//  Created by Richard Barber on 2025-08-03.
//
//  This file is part of RawUnravel.
//
//  RawUnravel is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  RawUnravel is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with RawUnravel.  If not, see <https://www.gnu.org/licenses/>.
//

import SwiftUI
import UIKit

struct LicenseSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollableHTMLTextView(htmlFileName: "gpl3") // no .html!
                .navigationTitle("GNU GPL v3")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
        }
    }
}

struct ScrollableHTMLTextView: UIViewRepresentable {
    let htmlFileName: String
    @Environment(\.colorScheme) private var colorScheme

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.backgroundColor = .clear
        textView.dataDetectorTypes = [.link]
        textView.textContainerInset = UIEdgeInsets(top: 20, left: 16, bottom: 20, right: 16)
        textView.attributedText = loadHTMLAttributedString()
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        textView.attributedText = loadHTMLAttributedString()
        // Also adjust background if you want:
        textView.backgroundColor = colorScheme == .dark ? .black : .white
    }

    private func loadHTMLAttributedString() -> NSAttributedString {
        guard
            let url = Bundle.main.url(forResource: htmlFileName, withExtension: "html"),
            var htmlString = try? String(contentsOf: url)
        else {
            return NSAttributedString(string: "License file missing.")
        }

        let css = """
        <style>
        body {
          color: \(colorScheme == .dark ? "#FFF" : "#111");
          background-color: \(colorScheme == .dark ? "#000" : "#FFF");
          font-family: -apple-system, 'Helvetica Neue', 'Arial', sans-serif;
          font-size: 14pt; /* Increased by 4pt */
        }
        a { color: #4477FF; }
        </style>
        """
        htmlString = css + htmlString

        let data = Data(htmlString.utf8)
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        return (try? NSAttributedString(data: data, options: options, documentAttributes: nil))
            ?? NSAttributedString(string: "Could not parse license file.")
    }
}

