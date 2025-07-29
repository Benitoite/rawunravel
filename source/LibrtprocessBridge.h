
// LibrtprocessBridge.h
// rawunravel

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Decodes a RAW image at the given file path using librtprocess.
/// Supports both Bayer and X-Trans sensors.
///
/// @param path The path to the RAW file.
/// @return A UIImage containing the processed preview, or nil on failure.
UIImage *decodeRAWWithRTProcess(NSString *path);

NS_ASSUME_NONNULL_END
