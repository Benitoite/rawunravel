//
//  UIImage+PixelSize.swift
//  RAWUnravel
//
//  Created by Richard Barber on 8/8/25.
//


// UIImage+PixelSize.swift
import UIKit

 
extension UIImage {
    /// Actual pixel dimensions of the bitmap.
    var pixelSize: CGSize {
        if let cg = self.cgImage {
            return CGSize(width: cg.width, height: cg.height)
        }
        // Fallback if there's no CGImage backing
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}
