/*
    RawUnravel - RawDecoder.mm
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

#import "RawDecoder.h"
#import <libraw/libraw.h>

// MARK: - RawDecoder Implementation

@implementation RawDecoder

/// Decodes a RAW image using LibRaw and returns a UIImage.
/// On error, returns nil.
+ (nullable UIImage *)decodeRAWAtPath:(NSString *)path {
    // MARK: - Initialize LibRaw processor
    LibRaw *processor = new LibRaw();

    // MARK: - Open RAW file
    if (processor->open_file([path UTF8String]) != LIBRAW_SUCCESS) {
        delete processor;
        return nil;
    }

    // MARK: - Unpack RAW data
    if (processor->unpack() != LIBRAW_SUCCESS) {
        processor->recycle();
        delete processor;
        return nil;
    }

    // MARK: - Process image to RGB (default pipeline)
    if (processor->dcraw_process() != LIBRAW_SUCCESS) {
        processor->recycle();
        delete processor;
        return nil;
    }

    // MARK: - Get processed image as memory buffer (24-bit RGB)
    libraw_processed_image_t *image = processor->dcraw_make_mem_image();
    if (!image || image->type != LIBRAW_IMAGE_BITMAP) {
        processor->recycle();
        delete processor;
        return nil;
    }

    // MARK: - Copy buffer to owned memory for CoreGraphics
    size_t bytesPerRow = image->width * 3;
    size_t bufferSize = image->height * bytesPerRow;
    void *buffer = malloc(bufferSize);
    if (!buffer) {
        LibRaw::dcraw_clear_mem(image);
        processor->recycle();
        delete processor;
        return nil;
    }
    memcpy(buffer, image->data, bufferSize);

    // MARK: - Create CGImage (no alpha, 8 bits/channel, 24-bit RGB)
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGDataProviderRef provider = CGDataProviderCreateWithData(
        NULL,
        buffer,
        bufferSize,
        [](void *info, const void *data, size_t size) {
            free((void *)data);
        });

    CGBitmapInfo bitmapInfo = (CGBitmapInfo)kCGImageAlphaNone;

    CGImageRef cgImage = CGImageCreate(
        image->width,
        image->height,
        8,
        24,
        bytesPerRow,
        colorSpace,
        bitmapInfo,
        provider,
        NULL,
        false,
        kCGRenderingIntentDefault);

    // MARK: - Wrap as UIImage and cleanup
    UIImage *result = nil;
    if (cgImage) {
        result = [UIImage imageWithCGImage:cgImage];
        CGImageRelease(cgImage);
    }

    CGColorSpaceRelease(colorSpace);
    CGDataProviderRelease(provider);
    LibRaw::dcraw_clear_mem(image);
    processor->recycle();
    delete processor;

    return result;
}

@end
