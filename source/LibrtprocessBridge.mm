#import "LibrtprocessBridge.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <rtprocess/librtprocess.h>

UIImage *decodeRAWWithRTProcess(NSString *path, BOOL isXTrans, const unsigned xtrans[6][6], const unsigned cfarray[2][2]) {
    if (!path) return nil;

    // Placeholder for image dimensions and raw buffer
    int width = 4000;
    int height = 3000;

    // Simulated input buffer with constant values
    float **rawData = (float **)malloc(height * sizeof(float *));
    for (int y = 0; y < height; y++) {
        rawData[y] = (float *)malloc(width * sizeof(float));
        for (int x = 0; x < width; x++) {
            rawData[y][x] = 0.5f; // Simulated middle-gray value
        }
    }

    // Allocate output RGB planes
    float **red = (float **)malloc(height * sizeof(float *));
    float **green = (float **)malloc(height * sizeof(float *));
    float **blue = (float **)malloc(height * sizeof(float *));
    for (int y = 0; y < height; y++) {
        red[y] = (float *)malloc(width * sizeof(float));
        green[y] = (float *)malloc(width * sizeof(float));
        blue[y] = (float *)malloc(width * sizeof(float));
    }

    // Process the raw data
    rpError err;
    if (isXTrans) {
        xtransfast_demosaic(width, height, (const float * const *)rawData, red, green, blue, xtrans, [](double){ return false; });
    } else {
        err = bayerfast_demosaic(width, height, (const float * const *)rawData, red, green, blue, cfarray, [](double){ return false; }, 1.0);
    }

    // Convert to 8-bit RGB data
    size_t totalPixels = width * height;
    uint8_t *rgbData = (uint8_t *)malloc(totalPixels * 3);
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            size_t idx = (y * width + x) * 3;
            rgbData[idx] = (uint8_t)(fmin(fmax(red[y][x], 0.0f), 1.0f) * 255);
            rgbData[idx + 1] = (uint8_t)(fmin(fmax(green[y][x], 0.0f), 1.0f) * 255);
            rgbData[idx + 2] = (uint8_t)(fmin(fmax(blue[y][x], 0.0f), 1.0f) * 255);
        }
    }

    // Create UIImage
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, rgbData, totalPixels * 3, NULL);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGImageRef cgImage = CGImageCreate(width, height, 8, 24, 3 * width, colorSpace,
                                       kCGBitmapByteOrderDefault | kCGImageAlphaNone,
                                       provider, NULL, false, kCGRenderingIntentDefault);

    UIImage *finalImage = [UIImage imageWithCGImage:cgImage];

    CGImageRelease(cgImage);
    CGColorSpaceRelease(colorSpace);
    CGDataProviderRelease(provider);

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
