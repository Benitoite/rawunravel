//
//  test.swift
//  RAWUnravel
//
//  Created by Richard Barber on 8/3/25.
//


if let ui = UIImage(named: "star")?.cgImage {
    print("Loaded STAR image!")
    // continue with Metal loader...
} else {
    print("Image not found!")
}