#import "RTPreviewDecoder.h"
#import <UIKit/UIKit.h>
#import <libraw/libraw.h>
#import <rtprocess/librtprocess.h>

@implementation RTPreviewDecoder

+ (UIImage *)decodeRAWPreviewAtPath:(NSString *)rawPath withPP3Path:(NSString *)pp3Path {
    if (![[NSFileManager defaultManager] fileExistsAtPath:rawPath]) {
        NSLog(@"❌ RAW file not found: %@", rawPath);
        return nil;
    }

    // Default adjustments
    float exposureMult = 1.0f;
    float blackBoost = 0.0f;
    float shadowBoost = 0.0f;

    // Parse PP3 if available
    if (pp3Path && [[NSFileManager defaultManager] fileExistsAtPath:pp3Path]) {
        NSError *error = nil;
        NSString *pp3Contents = [NSString stringWithContentsOfFile:pp3Path encoding:NSUTF8StringEncoding error:&error];
        if (pp3Contents) {
            for (NSString *line in [pp3Contents componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
                if ([line hasPrefix:@"Compensation"]) {
                    float val = [[line componentsSeparatedByString:@"="].lastObject floatValue];
                    exposureMult = powf(2.0f, val);
                } else if ([line hasPrefix:@"Black"]) {
                    blackBoost = [[line componentsSeparatedByString:@"="].lastObject floatValue] / 255.0f;
                } else if ([line hasPrefix:@"Shadow"]) {
                    shadowBoost = [[line componentsSeparatedByString:@"="].lastObject floatValue] / 255.0f;
                }
            }
        } else {
            NSLog(@"⚠️ Failed to read PP3: %@", error);
        }
    }

    LibRaw *rawProcessor = new LibRaw();
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
    if (!image || image->colors != 3 || image->bits != 8 || image->type != LIBRAW_IMAGE_BITMAP) {
        NSLog(@"❌ Unsupported LibRaw output");
        if (image) LibRaw::dcraw_clear_mem(image);
        delete rawProcessor;
        return nil;
    }

    int width = image->width;
    int height = image->height;
    int pixels = width * height;
    uint8_t *rgba = (uint8_t *)malloc(pixels * 4);
    if (!rgba) {
        NSLog(@"❌ Memory allocation failed");
        LibRaw::dcraw_clear_mem(image);
        delete rawProcessor;
        return nil;
    }

    for (int i = 0; i < pixels; i++) {
        int r = image->data[i * 3 + 0];
        int g = image->data[i * 3 + 1];
        int b = image->data[i * 3 + 2];

        float rf = fmaxf(0, fminf((r / 255.0f - blackBoost + shadowBoost) * exposureMult, 1));
        float gf = fmaxf(0, fminf((g / 255.0f - blackBoost + shadowBoost) * exposureMult, 1));
        float bf = fmaxf(0, fminf((b / 255.0f - blackBoost + shadowBoost) * exposureMult, 1));

        rgba[i * 4 + 0] = rf * 255;
        rgba[i * 4 + 1] = gf * 255;
        rgba[i * 4 + 2] = bf * 255;
        rgba[i * 4 + 3] = 255;
    }

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(rgba, width, height, 8, width * 4, cs,
                                             kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGImageRef cgImage = CGBitmapContextCreateImage(ctx);
    UIImage *ui = [UIImage imageWithCGImage:cgImage scale:[UIScreen mainScreen].scale orientation:UIImageOrientationUp];

    CGImageRelease(cgImage);
    CGContextRelease(ctx);
    CGColorSpaceRelease(cs);
    free(rgba);
    LibRaw::dcraw_clear_mem(image);
    delete rawProcessor;

    return ui;
}

@end
