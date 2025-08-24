/*
    RawUnravel - LibrtprocessBridge.h
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

#pragma once
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

// MARK: - Orientation helpers
//
// Maps LibRaw’s sizes.flip → standard EXIF orientation codes (1..8).
// Provides helpers to bake orientation into UIImage or CGImage pixels.

// Apply LibRaw flip/EXIF orientation to a UIImage (returns new UIImage).
// Caller receives an autoreleased UIImage (orientation baked as .up).

// Apply EXIF orientation to a CGImageRef (bit depth preserved if possible).
// Returns a retained CGImageRef that caller must CGImageRelease.
//CGImageRef RUCreateCGImageApplyingEXIF(CGImageRef inCG, int exif);

NS_ASSUME_NONNULL_END

// MARK: - Demosaic bridges
//
// C-callable shims that dispatch into librtprocess demosaicers.
// These are resolved dynamically in LibrtprocessBridge.mm.

#ifdef __cplusplus
extern "C" {
#endif
UIImage *RUApplyFlipToUIImage(UIImage *src, int librawOrExifFlip);

/// Bayer (AMAZE) demosaic bridge.
/// - mono: single-channel Bayer mosaic (normalized floats)
/// - cf4: 2x2 CFA pattern (LibRaw colors: 0=R, 1=G, 2=B)
/// - R/G/B: output planes (linear floats, size W*H)
int bridge_amaze_demosaic(const float * _Nullable mono,
                          int W, int H,
                          const unsigned cf4[_Nullable 4],
                          float * _Nullable R,
                          float * _Nullable G,
                          float * _Nullable B);

/// X-Trans demosaic bridge.
/// - P0/P1/P2: input mosaiced planes (linear floats)
/// - xtrans: 6x6 X-Trans pattern
/// - R/G/B: output planes (linear floats, size W*H)
int bridge_xtrans_demosaic(const float * _Nullable P0,
                           const float * _Nullable P1,
                           const float * _Nullable P2,
                           int W, int H,
                           const unsigned xtrans[_Nullable 6][6],
                           float * _Nullable R,
                           float * _Nullable G,
                           float * _Nullable B);

#ifdef __cplusplus
} // extern "C"
#endif
#ifdef __cplusplus
extern "C" {
#endif

int RUMapLibRawFlipToEXIF(int librawFlip);

/// Apply LibRaw/EXIF orientation (1..8) to UIImage.
/// Returns a new UIImage with orientation baked as .up.
UIImage * _Nullable RUApplyFlipToUIImage(UIImage * _Nullable src, int librawOrExifFlip);

/// Apply EXIF orientation (1..8) explicitly to UIImage.
/// Returns a new UIImage with orientation baked as .up.
UIImage * _Nullable RUApplyEXIFToUIImage(UIImage * _Nullable src, int exif);

#ifdef __cplusplus
} // extern "C"
#endif
