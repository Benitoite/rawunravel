/*
    RawUnravel - LibrtprocessBridge.mm (orientation + demosaic bridges)
    -------------------------------------------------------------------
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

// MARK: - Includes
#import "LibrtprocessBridge.h"
#import <UIKit/UIKit.h>
#import <libraw/libraw.h>
#import <algorithm>
#import <cmath>
#import <memory>
#import <dlfcn.h>
#include <cstddef>
#import "RTPreviewDecoder.h"
#import "RUShared.h"
#import <CoreGraphics/CoreGraphics.h>
extern "C" UIImage * _Nullable RUApplyEXIFToUIImage(UIImage * _Nullable src, int exif) {
    if (!src || exif == 1) return src;
    CGImageRef inCG = src.CGImage;
    if (!inCG) return src;

    CGImageRef outCG = RUCreateCGImageApplyingEXIF(inCG, exif); // must be implemented too
    if (!outCG) return src;

    UIImage *out = [UIImage imageWithCGImage:outCG
                                       scale:src.scale
                                 orientation:UIImageOrientationUp];
    CGImageRelease(outCG);
    return out;
}
extern "C" UIImage * _Nullable RUApplyFlipToUIImage(UIImage * _Nullable src, int librawOrExifFlip) {
    if (!src) return nil;
    // If caller gives LibRaw flip, map it; if already EXIF 1..8 it passes through
    int exif = RUMapLibRawFlipToEXIF(librawOrExifFlip);
    if (exif < 1 || exif > 8) exif = 1;

    // If they meant to pass EXIF directly (1..8), RUMapLibRawFlipToEXIF(1)=1, etc.
    // So we’re safe either way.

    if (exif == 1) return src;

    CGImageRef inCG = src.CGImage;
    if (!inCG) return src;

    // Use your existing pixel-rotate helper (must also have C linkage)
    CGImageRef outCG = RUCreateCGImageApplyingEXIF(inCG, exif); // +1
    if (!outCG) return src;

    UIImage *out = [UIImage imageWithCGImage:outCG
                                       scale:src.scale
                                 orientation:UIImageOrientationUp];
    CGImageRelease(outCG);
    return out;
}
// This file must be compiled as Objective-C++ (.mm)
// because it mixes ObjC/UIKit, C, and C++ features.

// MARK: - dlsym helpers (AMAZE / X-Trans)
//
// These dynamically resolve libRTProcess entry points for AMAZE and X-Trans
// demosaicers. We use dlsym() to avoid hard-linking against specific symbols
// (helps with iOS simulator/device mismatches).

using AmazeFn = int (*)(const float*, int, int, const unsigned[4], float*, float*, float*);
static AmazeFn loadAmaze() {
    static AmazeFn fn = nullptr;
    static bool tried = false;
    if (tried) return fn;
    tried = true;

    const char *cands[] = { "amaze_demosaic", "rp_demosaic_amaze" };
    for (const char *nm : cands) {
        if (void *p = dlsym(RTLD_DEFAULT, nm)) {
            fn = (AmazeFn)p;
            break;
        }
    }
    return fn;
}

using XTransFn = int (*)(const float*, const float*, const float*, int, int, const unsigned[6][6],
                         float*, float*, float*);
static XTransFn loadXTrans() {
    static XTransFn fn = nullptr;
    static bool tried = false;
    if (tried) return fn;
    tried = true;

    const char *cands[] = { "xtrans_demosaic", "rp_demosaic_xtrans" };
    for (const char *nm : cands) {
        if (void *p = dlsym(RTLD_DEFAULT, nm)) {
            fn = (XTransFn)p;
            break;
        }
    }
    return fn;
}

// Exported C-ABI bridge functions called from RTPreviewDecoder.mm
extern "C" int bridge_amaze_demosaic(const float *mono, int W, int H, const unsigned cf4[4],
                                     float *R, float *G, float *B) {
    AmazeFn fn = loadAmaze();
    return fn ? fn(mono, W, H, cf4, R, G, B) : -1;
}

extern "C" int bridge_xtrans_demosaic(const float *P0, const float *P1, const float *P2,
                                      int W, int H, const unsigned xtrans[6][6],
                                      float *R, float *G, float *B) {
    XTransFn fn = loadXTrans();
    return fn ? fn(P0, P1, P2, W, H, xtrans, R, G, B) : -1;
}

// MARK: - Orientation helpers
//
// LibRaw → EXIF orientation values. Matches EXIF 1..8 codes.

typedef NS_ENUM(int, RUFlipCode) {
    RUFlipEXIF_TopLeft        = 1, // identity
    RUFlipEXIF_TopRight       = 2, // mirror horizontal
    RUFlipEXIF_BottomRight    = 3, // rotate 180
    RUFlipEXIF_BottomLeft     = 4, // mirror vertical
    RUFlipEXIF_LeftTop        = 5, // mirror horizontal + 90 CW
    RUFlipEXIF_RightTop       = 6, // 90 CW
    RUFlipEXIF_RightBottom    = 7, // mirror horizontal + 270 CW
    RUFlipEXIF_LeftBottom     = 8  // 90 CCW
};
