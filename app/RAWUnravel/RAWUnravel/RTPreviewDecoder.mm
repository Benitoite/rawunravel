/*
    RawUnravel - RTPreviewDecoder.mm
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

#import "RTPreviewDecoder.h"
#import <UIKit/UIKit.h>
#import <libraw/libraw.h>
#import <math.h>

// MARK: - Color Conversion Helpers (sRGB <-> CIE Lab via XYZ)
// These functions implement standard color science transforms used for perceptual image editing,
// matching the RawTherapee pipeline. All math is per-pixel, floats in the [0,1] range unless otherwise stated.

/**
 * Converts sRGB (gamma-corrected, nonlinear) to linear light.
 * sRGB uses a piecewise function for encoding: below 0.04045 use a simple slope, above use a power law.
 * Formula from IEC 61966-2-1:1999 (sRGB specification).
 *
 * @param c  sRGB channel (0.0–1.0, nonlinear)
 * @return   Linear channel (0.0–1.0, proportional to radiance)
 */
static float srgb_to_linear(float c) {
    if (c <= 0.04045f)      // Linear section (darkest tones)
        return c / 12.92f;
    else                    // Gamma-corrected section (main range)
        return powf((c + 0.055f) / 1.055f, 2.4f);
}

/**
 * Converts linear light (proportional to scene radiance) to sRGB nonlinear.
 * This is the inverse of srgb_to_linear, using the same piecewise curve.
 * Used when writing out to display or file formats.
 *
 * @param c  Linear channel (0.0–1.0)
 * @return   sRGB channel (0.0–1.0, nonlinear)
 */
static float linear_to_srgb(float c) {
    if (c <= 0.0031308f)    // Linear section
        return 12.92f * c;
    else                    // Gamma-corrected section
        return 1.055f * powf(c, 1.0f / 2.4f) - 0.055f;
}

/**
 * Converts sRGB to CIE XYZ tristimulus values.
 * 1. First applies the sRGB-to-linear transform.
 * 2. Then uses the sRGB-to-XYZ matrix (D65 white, 2° observer) from IEC 61966-2-1:1999.
 *    Matrix rows are for X, Y, and Z; columns are linear R, G, B.
 *
 * @param r,g,b  sRGB nonlinear (0–1)
 * @param X,Y,Z  Output: CIE XYZ (0–1, relative, D65)
 */
static void rgb2xyz(float r, float g, float b, float *X, float *Y, float *Z) {
    r = srgb_to_linear(r);
    g = srgb_to_linear(g);
    b = srgb_to_linear(b);
    // sRGB → XYZ (D65) standard matrix:
    // [X]   [0.4124564  0.3575761  0.1804375]   [R]
    // [Y] = [0.2126729  0.7151522  0.0721750] * [G]
    // [Z]   [0.0193339  0.1191920  0.9503041]   [B]
    *X = r * 0.4124564f + g * 0.3575761f + b * 0.1804375f;
    *Y = r * 0.2126729f + g * 0.7151522f + b * 0.0721750f;
    *Z = r * 0.0193339f + g * 0.1191920f + b * 0.9503041f;
}

/**
 * Converts CIE XYZ to CIE L*a*b* (CIELAB) color.
 * CIELAB is a perceptually uniform color space (for D65 white, 2° observer).
 * This is the standard 1976 Lab transformation (see CIE publications).
 *
 * @param X,Y,Z   CIE XYZ (0–1, relative, D65)
 * @param L,a,b   Output: CIELAB (L: 0–100, a/b: approx -128 to +128)
 */
static void xyz2lab(float X, float Y, float Z, float *L, float *a, float *b) {
    // Reference white point (D65), normalized for XYZ
    float Xr = 0.95047f, Yr = 1.0f, Zr = 1.08883f;
    // f(t) is the nonlinear transform, with linear fallback for low values
    auto f = [](float t) {
        return t > 0.008856f ? powf(t, 1.0f / 3.0f) : (7.787f * t + 16.0f / 116.0f);
    };
    float fx = f(X / Xr);
    float fy = f(Y / Yr);
    float fz = f(Z / Zr);
    // Standard Lab equations:
    // L* = 116 * f(Y/Yn) - 16
    // a* = 500 * (f(X/Xn) - f(Y/Yn))
    // b* = 200 * (f(Y/Yn) - f(Z/Zn))
    *L = 116.0f * fy - 16.0f;
    *a = 500.0f * (fx - fy);
    *b = 200.0f * (fy - fz);
}

/**
 * Converts CIE L*a*b* to CIE XYZ (inverse of xyz2lab).
 * Handles nonlinearity for low L* values.
 * Standard CIELAB inverse equations.
 *
 * @param L,a,b   CIELAB (L: 0–100, a/b: -128..128)
 * @param X,Y,Z   Output: CIE XYZ (D65, 0–1)
 */
static void lab2xyz(float L, float a, float b, float *X, float *Y, float *Z) {
    float Xr = 0.95047f, Yr = 1.0f, Zr = 1.08883f;
    float fy = (L + 16.0f) / 116.0f;
    float fx = fy + a / 500.0f;
    float fz = fy - b / 200.0f;
    // f3(t): inverse of f(t) from Lab
    auto f3 = [](float t) {
        return t > 0.206893f ? t * t * t : (t - 16.0f / 116.0f) / 7.787f;
    };
    *X = Xr * f3(fx);
    *Y = Yr * f3(fy);
    *Z = Zr * f3(fz);
}

/**
 * Converts CIE XYZ to sRGB (nonlinear, gamma-corrected).
 * Uses the official sRGB D65 XYZ-to-sRGB matrix (inverse of rgb2xyz), then encodes to sRGB gamma.
 *
 * @param X,Y,Z   CIE XYZ (0–1, relative, D65)
 * @param r,g,b   Output: sRGB nonlinear (0–1)
 */
static void xyz2rgb(float X, float Y, float Z, float *r, float *g, float *b) {
    // XYZ → linear RGB using official sRGB matrix (D65)
    float r_lin =  3.2404542f * X - 1.5371385f * Y - 0.4985314f * Z;
    float g_lin = -0.9692660f * X + 1.8760108f * Y + 0.0415560f * Z;
    float b_lin =  0.0556434f * X - 0.2040259f * Y + 1.0572252f * Z;
    // Convert from linear to nonlinear sRGB for display
    *r = linear_to_srgb(r_lin);
    *g = linear_to_srgb(g_lin);
    *b = linear_to_srgb(b_lin);
}// MARK: - Main Decoder Implementation

@implementation RTPreviewDecoder

/// Main preview decode method.
/// Applies exposure, black point, shadow, and RawTherapee-style color transforms (Lab, Chroma, Contrast).
+ (UIImage *)decodeRAWPreviewAtPath:(NSString *)rawPath
                        withPP3Path:(NSString *)pp3Path
                           halfSize:(BOOL)halfSize
{
    // MARK: - Parse .pp3/slider values
    float exposureMult = 1.0f;
    float blackBoost = 0.0f;
    float shadowBoost = 0.0f;
    float chromaticity = 0.0f;  BOOL chromaticityEnabled = NO;
    float cChroma = 0.0f;       BOOL cChromaEnabled = NO;
    float jContrast = 0.0f;     BOOL jContrastEnabled = NO;

    // ---- Parse the PP3 file for adjustments
    if (pp3Path && [[NSFileManager defaultManager] fileExistsAtPath:pp3Path]) {
        NSError *error = nil;
        NSString *pp3Contents = [NSString stringWithContentsOfFile:pp3Path encoding:NSUTF8StringEncoding error:&error];
        if (pp3Contents) {
            BOOL inLuminanceCurve = NO;
            BOOL inColorAppearance = NO;
            for (NSString *line in [pp3Contents componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
                NSString *trim = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if ([trim hasPrefix:@"[Luminance Curve]"]) {
                    inLuminanceCurve = YES; inColorAppearance = NO;
                } else if ([trim hasPrefix:@"[Color appearance]"]) {
                    inColorAppearance = YES; inLuminanceCurve = NO;
                } else if ([trim hasPrefix:@"["]) {
                    inLuminanceCurve = NO; inColorAppearance = NO;
                }

                // Parse Luminance Curve section
                if (inLuminanceCurve) {
                    if ([trim hasPrefix:@"Chromaticity="]) {
                        chromaticity = [[trim componentsSeparatedByString:@"="].lastObject floatValue];
                    } else if ([trim hasPrefix:@"Enabled="]) {
                        chromaticityEnabled = [[trim componentsSeparatedByString:@"="].lastObject boolValue];
                    }
                }
                // Parse Color Appearance section
                if (inColorAppearance) {
                    if ([trim hasPrefix:@"C-Chroma="]) {
                        cChroma = [[trim componentsSeparatedByString:@"="].lastObject floatValue];
                    } else if ([trim hasPrefix:@"C-ChromaEnabled="]) {
                        cChromaEnabled = [[trim componentsSeparatedByString:@"="].lastObject boolValue];
                    } else if ([trim hasPrefix:@"J-Contrast="]) {
                        jContrast = [[trim componentsSeparatedByString:@"="].lastObject floatValue];
                    } else if ([trim hasPrefix:@"J-ContrastEnabled="]) {
                        jContrastEnabled = [[trim componentsSeparatedByString:@"="].lastObject boolValue];
                    }
                }

                // Global exposure/shadow/black outside section
                if ([trim hasPrefix:@"Compensation"]) {
                    float val = [[trim componentsSeparatedByString:@"="].lastObject floatValue];
                    exposureMult = powf(2.0f, val);
                } else if ([trim hasPrefix:@"Black"]) {
                    blackBoost = [[trim componentsSeparatedByString:@"="].lastObject floatValue] / 255.0f;
                } else if ([trim hasPrefix:@"Shadows"]) {
                    shadowBoost = [[trim componentsSeparatedByString:@"="].lastObject floatValue];
                }
            }
        } else {
            NSLog(@"⚠️ Failed to read PP3: %@", error);
        }
    }

    // MARK: - Load RAW (LibRaw, half-size for fast preview)
    LibRaw *rawProcessor = new LibRaw();
    rawProcessor->imgdata.params.half_size = halfSize ? 1 : 0;
    rawProcessor->imgdata.params.use_auto_wb = 1;
    rawProcessor->imgdata.params.output_bps = 8;

    if (rawProcessor->open_file([rawPath UTF8String]) != LIBRAW_SUCCESS) {
        NSLog(@"❌ LibRaw failed to open RAW");
        delete rawProcessor;
        return nil;
    }
    if (rawProcessor->unpack() != LIBRAW_SUCCESS) {
        NSLog(@"❌ LibRaw failed to unpack");
        delete rawProcessor;
        return nil;
    }
    if (rawProcessor->dcraw_process() != LIBRAW_SUCCESS) {
        NSLog(@"❌ LibRaw failed to process");
        delete rawProcessor;
        return nil;
    }

    libraw_processed_image_t *image = rawProcessor->dcraw_make_mem_image();
    if (!image) {
        NSLog(@"LibRaw returned null image");
        delete rawProcessor;
        return nil;
    }

    NSLog(@"LibRaw: type=%d bits=%d colors=%d width=%d height=%d", image->type, image->bits, image->colors, image->width, image->height);

    if (image->type != LIBRAW_IMAGE_BITMAP || image->bits != 8 || image->colors != 3 || !image->data) {
        NSLog(@"LibRaw returned unsupported format or NULL data");
        LibRaw::dcraw_clear_mem(image);
        delete rawProcessor;
        return nil;
    }

    int width = image->width;
    int height = image->height;
    int pixels = width * height;

    if (width <= 0 || height <= 0 || pixels <= 0) {
        NSLog(@"❌ Invalid image dimensions: %d x %d", width, height);
        LibRaw::dcraw_clear_mem(image);
        delete rawProcessor;
        return nil;
    }

    // MARK: - Per-pixel processing and sRGB+Lab transforms
    uint8_t *src = (uint8_t *)image->data;
    uint8_t *rgba = (uint8_t *)malloc(pixels * 4);
    if (!rgba) {
        NSLog(@"❌ Memory allocation failed");
        LibRaw::dcraw_clear_mem(image);
        delete rawProcessor;
        return nil;
    }

    for (int i = 0; i < pixels; i++) {
        float r = src[i*3+0] / 255.0f;
        float g = src[i*3+1] / 255.0f;
        float b = src[i*3+2] / 255.0f;
        
        // Convert to linear for correct math
        float r_lin = srgb_to_linear(r);
        float g_lin = srgb_to_linear(g);
        float b_lin = srgb_to_linear(b);

        // Apply black point lift
        r_lin = fmaxf(0, r_lin - blackBoost);
        g_lin = fmaxf(0, g_lin - blackBoost);
        b_lin = fmaxf(0, b_lin - blackBoost);

        // Shadows adjustment: lift deep shadows by shadowBoost
        float Y_lin = 0.2126f * r_lin + 0.7152f * g_lin + 0.0722f * b_lin;
        float shadowGain = shadowBoost / 100.0f;
        float shadowLift = shadowGain * (1.0f - Y_lin) * Y_lin;
        r_lin += shadowLift; g_lin += shadowLift; b_lin += shadowLift;

        // Exposure adjustment (multiply linears by 2^n stops)
        r_lin *= exposureMult;
        g_lin *= exposureMult;
        b_lin *= exposureMult;

        // Clamp back to [0,1]
        r_lin = fminf(fmaxf(r_lin, 0), 1);
        g_lin = fminf(fmaxf(g_lin, 0), 1);
        b_lin = fminf(fmaxf(b_lin, 0), 1);

        // Convert back to sRGB for image/preview
        r = fminf(fmaxf(linear_to_srgb(r_lin), 0), 1);
        g = fminf(fmaxf(linear_to_srgb(g_lin), 0), 1);
        b = fminf(fmaxf(linear_to_srgb(b_lin), 0), 1);

        // --- Optional: Lab transforms for color and contrast adjustments
        BOOL applyLab = (chromaticityEnabled && fabsf(chromaticity) > 0.01f) ||
                        (cChromaEnabled && fabsf(cChroma) > 0.01f) ||
                        (jContrastEnabled && fabsf(jContrast) > 0.01f);

        if (applyLab) {
            float X, Y, Z, L, a, b2;
            rgb2xyz(r, g, b, &X, &Y, &Z);
            xyz2lab(X, Y, Z, &L, &a, &b2);

            if (chromaticityEnabled && fabsf(chromaticity) > 0.01f) {
                float chromaAmount = 1.0f + chromaticity / 100.0f;
                a *= chromaAmount;
                b2 *= chromaAmount;
            }
            if (cChromaEnabled && fabsf(cChroma) > 0.01f) {
                float cChromaAmount = 1.0f + cChroma / 100.0f;
                float chroma = sqrtf(a * a + b2 * b2);
                float angle = atan2f(b2, a);
                chroma *= cChromaAmount;
                a = chroma * cosf(angle);
                b2 = chroma * sinf(angle);
            }
            if (jContrastEnabled && fabsf(jContrast) > 0.01f) {
                float amount = 1.0f + jContrast / 100.0f;
                L = (L - 50.0f) * amount + 50.0f;
                if (L < 0) L = 0;
                if (L > 100) L = 100;
            }
            lab2xyz(L, a, b2, &X, &Y, &Z);
            xyz2rgb(X, Y, Z, &r, &g, &b);
            r = fmaxf(0, fminf(r, 1));
            g = fmaxf(0, fminf(g, 1));
            b = fmaxf(0, fminf(b, 1));
        }

        rgba[i * 4 + 0] = r * 255;
        rgba[i * 4 + 1] = g * 255;
        rgba[i * 4 + 2] = b * 255;
        rgba[i * 4 + 3] = 255;
    }
        
    // MARK: - Create UIImage from buffer
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(rgba, width, height, 8, width * 4, cs,
                                             kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    if (!ctx) {
        NSLog(@"❌ CGContextCreate failed");
        CGColorSpaceRelease(cs);
        free(rgba);
        LibRaw::dcraw_clear_mem(image);
        delete rawProcessor;
        return nil;
    }

    CGImageRef cgImage = CGBitmapContextCreateImage(ctx);
    if (!cgImage) {
        NSLog(@"❌ CGBitmapContextCreateImage failed");
        CGContextRelease(ctx);
        CGColorSpaceRelease(cs);
        free(rgba);
        LibRaw::dcraw_clear_mem(image);
        delete rawProcessor;
        return nil;
    }

    UIImage *ui = [UIImage imageWithCGImage:cgImage scale:[UIScreen mainScreen].scale orientation:UIImageOrientationUp];

    // MARK: - Cleanup and return
    CGImageRelease(cgImage);
    CGContextRelease(ctx);
    CGColorSpaceRelease(cs);
    free(rgba);
    LibRaw::dcraw_clear_mem(image);
    delete rawProcessor;

    return ui;
}

@end
