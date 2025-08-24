/*
    RawUnravel - RUShared.h
    -----------------------
    Public C/Obj-C interfaces used across the app. These declarations map
    1:1 to the implementations in RUShared.mm.

    Conventions:
    - EXIF orientation ∈ {1…8} (TIFF/EXIF standard numbering).
    - All UI-related posting (progress) is marshalled to the main thread.
*/

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

// MARK: - EXIF orientation helpers

/// Returns the EXIF orientation (1…8) of the *largest* raster subimage embedded
/// in the file container at `path`. On failure or if not present, returns 1
/// (identity / “Up”).
int RUExifOrientationFromLargestPreview(NSString *path);

// MARK: - Progress notifications

/// Posts a NSNotification named "RawUnravelProgress" with payload:
/// { job:String, phase:String, step:String, iter:Int, total:Int }.
/// Ensures delivery on the main thread.
void PostProgress(NSString *jobID,
                  NSString *phase,
                  NSString *step,
                  NSInteger iter,
                  NSInteger total);

// MARK: - LibRaw flip → EXIF

/// Maps LibRaw sizes.flip (0…7) to EXIF orientation (1…8).
/// Out-of-range inputs map to 1 (identity).
int RUMapLibRawFlipToEXIF(int flip);

#ifdef __cplusplus
} // extern "C"
#endif
