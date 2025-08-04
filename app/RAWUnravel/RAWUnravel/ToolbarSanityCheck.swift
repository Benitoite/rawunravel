//
//  ToolbarSanityCheck.swift
//  RAWUnravel
//
//  Created by Richard Barber on 8/2/25.
//


import SwiftUI

struct ToolbarSanityCheck: View {
    var body: some View {
        NavigationView {
            Text("Hi")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {}
                    }
                }
        }
    }
}