/*
    RawUnravel - LibrtprocessBridge.mm
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

#import "LibrtprocessBridge.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <rtprocess/librtprocess.h>

// MARK: - Bridge Function Implementation

/// Bridge for demosaicing using librtprocess and returning a UIImage.
/// (Simulated implementation: replace width/height/buffers with real RAW data for production.)
UIImage *decodeRAWWithRTProcess(NSString *path, BOOL isXTrans, const unsigned xtrans[6][6], const unsigned cfarray[2][2]) {
    if (!path) return nil;

    // MARK: - Placeholder image dimensions (replace with LibRaw/Librtprocess for real decoding)
    int width = 4000;
    int height = 3000;

    // MARK: - Simulated RAW input buffer (normally extracted from RAW file)
    float **rawData = (float **)malloc(height * sizeof(float *));
    for (int y = 0; y < height; y++) {
        rawData[y] = (float *)malloc(width * sizeof(float));
        for (int x = 0; x < width; x++) {
            rawData[y][x] = 0.5f; // Simulated middle-gray value
        }
    }

    // MARK: - Output RGB planes for demosaiced result
    float **red   = (float **)malloc(height * sizeof(float *));
    float **green = (float **)malloc(height * sizeof(float *));
    float **blue  = (float **)malloc(height * sizeof(float *));
    for (int y = 0; y < height; y++) {
        red[y]   = (float *)malloc(width * sizeof(float));
        green[y] = (float *)malloc(width * sizeof(float));
        blue[y]  = (float *)malloc(width * sizeof(float));
    }

    // MARK: - Demosaic using librtprocess
    rpError err;
    if (isXTrans) {
        // X-Trans demosaic (Fuji etc.)
        xtransfast_demosaic(width, height, (const float * const *)rawData, red, green, blue, xtrans, [](double){ return false; });
    } else {
        // Bayer demosaic (Canon/Nikon/Sony etc.)
        err = bayerfast_demosaic(width, height, (const float * const *)rawData, red, green, blue, cfarray, [](double){ return false; }, 1.0);
    }

    // MARK: - Convert to 8-bit RGB buffer for CoreGraphics
    size_t totalPixels = width * height;
    uint8_t *rgbData = (uint8_t *)malloc(totalPixels * 3);
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            size_t idx = (y * width + x) * 3;
            rgbData[idx    ] = (uint8_t)(fmin(fmax(red[y][x],   0.0f), 1.0f) * 255);
            rgbData[idx + 1] = (uint8_t)(fmin(fmax(green[y][x], 0.0f), 1.0f) * 255);
            rgbData[idx + 2] = (uint8_t)(fmin(fmax(blue[y][x],  0.0f), 1.0f) * 255);
        }
    }

    // MARK: - Create UIImage from raw RGB buffer
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, rgbData, totalPixels * 3, NULL);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGImageRef cgImage = CGImageCreate(
        width, height,
        8, 24, 3 * width, colorSpace,
        kCGBitmapByteOrderDefault | kCGImageAlphaNone,
        provider, NULL, false, kCGRenderingIntentDefault
    );

    UIImage *finalImage = [UIImage imageWithCGImage:cgImage];

    // Cleanup CoreGraphics resources
    CGImageRelease(cgImage);
    CGColorSpaceRelease(colorSpace);
    CGDataProviderRelease(provider);

    // MARK: - Free all image buffers
    for (int y = 0; y < height; y++) {
        free(rawData[y]);
        free(red[y]);
        free(green[y]);
        free(blue[y]);
    }
    free(rawData);
    free(red);
    free(green);
    free(blue);
    free(rgbData);

    return finalImage;
}
