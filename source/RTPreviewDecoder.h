// RTPreviewDecoder.h
#import <UIKit/UIKit.h>
@interface RTPreviewDecoder : NSObject
+ (UIImage *)decodeRAWPreviewAtPath:(NSString *)rawPath withPP3Path:(NSString *)pp3Path;
@end
