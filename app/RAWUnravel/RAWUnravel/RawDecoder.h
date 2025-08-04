//
//  RawDecoder.h
//  rawunravel
//
//  Created by Richard Barber on 7/27/25.
//


#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RawDecoder : NSObject

+ (nullable UIImage *)decodeRAWAtPath:(NSString *)path;

@end

NS_ASSUME_NONNULL_END