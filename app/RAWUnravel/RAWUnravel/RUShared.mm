/*
    RawUnravel - RUShared.mm
    ------------------------
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

#import "RUShared.h"
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>

#pragma mark - Internal helpers (pure functions)

// MARK: EXIF orientation → whether width/height swap
// Returns 1 if a 90°-class transform is required (5..8), else 0.
static inline int ru_exif_swaps_wh(int exif) {
    return (exif == 5 || exif == 6 || exif == 7 || exif == 8);
}

// MARK: Concatenate EXIF transform into a CGContext
// The transform sequence is the canonical TIFF/EXIF mapping, with the draw
// rectangle always specified in *source* pixel coordinates after the CTM.
// Let S = (W,H) be the output canvas size chosen by RUSizeForOrientedDraw.
// Each case composes a translation/scale/rotation so that drawing the original
// (0,0,W_src,H_src) into the context yields the visually upright image.
static inline void RUConcatEXIFTransform(CGContextRef ctx, CGSize dstSize, int exif) {
    switch (exif) {
        case 1:
            // Identity: x' = x, y' = y
            break;

        case 2:
            // Mirror horizontal about vertical center line:
            // x' = W - x, y' = y  ⇒ T(W,0) • S(-1,1)
            CGContextTranslateCTM(ctx, dstSize.width, 0);
            CGContextScaleCTM(ctx, -1, 1);
            break;

        case 3:
            // Rotate 180° about image center:/Users/rb/Desktop/Simulator Screenshot - iPhone 16 Plus - 2025-08-09 at 13.05.15.png
            // x' = W - x, y' = H - y ⇒ T(W,H) • R(π)
            CGContextTranslateCTM(ctx, dstSize.width, dstSize.height);
            CGContextRotateCTM(ctx, (CGFloat)M_PI);
            break;

        case 4:
            // Mirror vertical about horizontal center line:
            // x' = x, y' = H - y ⇒ T(0,H) • S(1,-1)
            CGContextTranslateCTM(ctx, 0, dstSize.height);
            CGContextScaleCTM(ctx, 1, -1);
            break;

        case 5:
            // Mirror horizontal, then rotate 90° CW:
            // Canonical mapping ⇒ T(W,0)•S(-1,1) then T(W,0)•R(π/2)
            CGContextTranslateCTM(ctx, dstSize.width, 0);
            CGContextScaleCTM(ctx, -1, 1);
            CGContextTranslateCTM(ctx, dstSize.width, 0);
            CGContextRotateCTM(ctx, (CGFloat)M_PI_2);
            break;

 

        case 7:
            // Mirror horizontal, then rotate 90° CCW:
            // Canonical mapping ⇒ T(W,0)•S(-1,1) then T(0,H)•R(-π/2)
            CGContextTranslateCTM(ctx, dstSize.width, 0);
            CGContextScaleCTM(ctx, -1, 1);
            CGContextTranslateCTM(ctx, 0, dstSize.height);
            CGContextRotateCTM(ctx, (CGFloat)-M_PI_2);
            break;
        case 6: // 90 CW
            CGContextTranslateCTM(ctx, 0, dstSize.height);
            CGContextRotateCTM(ctx, (CGFloat)-M_PI_2); // ⬅️ flip
            break;

        case 8: // 90 CCW (fix for iOS)
            CGContextTranslateCTM(ctx, dstSize.width, 0);
            CGContextRotateCTM(ctx, (CGFloat)M_PI_2);
            break;
        default:
            break;
    }
}

#pragma mark - Public C symbols

#ifdef __cplusplus
extern "C" {
#endif

// MARK: RUExifOrientationFromLargestPreview
// Scans all subimages in the container at `path` (e.g. RAW with embedded JPEGs),
// chooses the largest raster by area, and returns its EXIF orientation (1..8).
// Returns 1 on failure or when missing.
int RUExifOrientationFromLargestPreview(NSString *path) {
    if (!path.length) return 1;

    NSURL *u = [NSURL fileURLWithPath:path];
    if (!u) return 1;

    CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)u,
                              (__bridge CFDictionaryRef)@{ (id)kCGImageSourceShouldCache : @NO });
    if (!src) return 1;

    size_t count = CGImageSourceGetCount(src);
    int bestIndex = -1;
    long bestArea = -1;

    for (size_t i = 0; i < count; ++i) {
        CFDictionaryRef props = CGImageSourceCopyPropertiesAtIndex(src, i, NULL);
        if (!props) continue;

        int w = 0, h = 0;
        CFNumberRef wN = (CFNumberRef)CFDictionaryGetValue(props, kCGImagePropertyPixelWidth);
        CFNumberRef hN = (CFNumberRef)CFDictionaryGetValue(props, kCGImagePropertyPixelHeight);
        if (wN && hN) {
            CFNumberGetValue(wN, kCFNumberIntType, &w);
            CFNumberGetValue(hN, kCFNumberIntType, &h);
        }
        CFRelease(props);

        long area = (long)w * (long)h;
        if (w > 0 && h > 0 && area > bestArea) {
            bestArea = area;
            bestIndex = (int)i;
        }
    }

    if (bestIndex < 0) { CFRelease(src); return 1; }

    int exif = 1;
    CFDictionaryRef props = CGImageSourceCopyPropertiesAtIndex(src, (size_t)bestIndex, NULL);
    if (props) {
        CFNumberRef n = (CFNumberRef)CFDictionaryGetValue(props, kCGImagePropertyOrientation);
        if (n) CFNumberGetValue(n, kCFNumberIntType, &exif);
        CFRelease(props);
    }

    CFRelease(src);
    return exif;
}

// MARK: PostProgress
// Posts a main-thread NSNotification with a progress payload:
//   userInfo = { job:String, phase:String, step:String, iter:Int, total:Int }.
void PostProgress(NSString *jobID, NSString *phase, NSString *step,
                  NSInteger iter, NSInteger total)
{
    NSDictionary *info = @{
        @"job"   : jobID  ?: @"",
        @"phase" : phase  ?: @"",
        @"step"  : step   ?: @"",
        @"iter"  : @(iter),
        @"total" : @(total)
    };

    void (^post)(void) = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"RawUnravelProgress"
                                                            object:nil
                                                          userInfo:info];
    };

    if ([NSThread isMainThread]) {
        post();
    } else {
        dispatch_async(dispatch_get_main_queue(), post);
    }
}

// MARK: RUMapLibRawFlipToEXIF
// Maps LibRaw sizes.flip (0..7) to EXIF orientation (1..8).
// LibRaw flip is a discrete symmetry group element; this table is the canonical
// dcraw/libraw mapping. Out-of-range inputs return 1 (identity).
inline int RUMapLibRawFlipToEXIF(int flip) {
    switch (flip) {
        case 0: return 1; // none
        case 1: return 2; // mirror H
        case 2: return 4; // mirror V
        case 3: return 3; // 180
        case 4: return 5; // mirror + 90 CW (transpose)
        case 5: return 6; // 90 CW   ← was 8
        case 6: return 8; // 90 CCW  ← was 6
        case 7: return 7; // mirror + 90 CCW (transverse)
        default:return 1;
    }
}
#ifdef __cplusplus
} // extern "C"
#endif
