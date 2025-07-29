//
//  RawDecoder.mm
//  rawunravel
//
//  Created by Richard Barber on 7/27/25.
//

#import "RawDecoder.h"
#import <libraw/libraw.h>

@implementation RawDecoder

+ (nullable UIImage *)decodeRAWAtPath:(NSString *)path {
    LibRaw *processor = new LibRaw();

    if (processor->open_file([path UTF8String]) != LIBRAW_SUCCESS) {
        delete processor;
        return nil;
    }

    if (processor->unpack() != LIBRAW_SUCCESS) {
        processor->recycle();
        delete processor;
        return nil;
    }

    if (processor->dcraw_process() != LIBRAW_SUCCESS) {
        processor->recycle();
        delete processor;
        return nil;
    }

    libraw_processed_image_t *image = processor->dcraw_make_mem_image();
    if (!image || image->type != LIBRAW_IMAGE_BITMAP) {
        processor->recycle();
        delete processor;
        return nil;
    }

    // Copy buffer into owned memory
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

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGDataProviderRef provider = CGDataProviderCreateWithData(
        NULL,
        buffer,
        bufferSize,
        [](void *info, const void *data, size_t size) {
            free((void *)data);
        });

    // Use valid CGBitmapInfo without deprecated bitwise enums
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
