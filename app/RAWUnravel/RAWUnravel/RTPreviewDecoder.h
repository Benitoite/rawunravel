
// RTPreviewDecoder.h

#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@interface RTPreviewDecoder : NSObject

/// Half/Full preview entry (UIImage).
+ (nullable UIImage *)decodeRAWPreviewAtPath:(NSString *)rawPath
                                 withPP3Path:(nullable NSString *)pp3Path
                                    halfSize:(BOOL)halfSize
                                       jobID:(nullable NSString *)jobID
NS_SWIFT_NAME(decodeRAWPreview(atPath:withPP3Path:halfSize:jobID:));

/// Convenience: half-size superpixel/fast preview (UIImage).
+ (nullable UIImage *)previewSuperpixelAtPath:(NSString *)rawPath
                                        jobID:(nullable NSString *)jobID
NS_SWIFT_NAME(previewSuperpixel(atPath:jobID:));

/// Full-res AMAZE (UIImage, 8bpc sRGB, orientation baked).
+ (nullable UIImage *)fullResAMAZEAtPath:(NSString *)rawPath
                                   jobID:(nullable NSString *)jobID
NS_SWIFT_NAME(fullResAMAZE(atPath:jobID:));

/// 16-bit final demosaic to CGImage (caller must CFRelease).
+ (nullable CGImageRef)createCGImage16FromRAWAtPath:(NSString *)rawPath
                                              jobID:(nullable NSString *)jobID
CF_RETURNS_RETAINED
NS_SWIFT_NAME(createCGImage16FromRAW(atPath:jobID:));

/// Read active RAW size quickly.
+ (CGSize)rawActiveSizeAtPath:(NSString *)rawPath
NS_SWIFT_NAME(rawActiveSize(atPath:));



@end

NS_ASSUME_NONNULL_END
#import <CoreGraphics/CoreGraphics.h>

#ifdef __cplusplus
extern "C" {
#endif

CGImageRef _Nullable RUCreateCGImageApplyingEXIF(CGImageRef _Nullable inCG, int exif);
int RUExifOrientationFromFileC(const char * _Nullable   pathC);
int RUExifOrientationFromLargestPreviewC(const char * _Nullable pathC);

#ifdef __cplusplus
}
#endif
