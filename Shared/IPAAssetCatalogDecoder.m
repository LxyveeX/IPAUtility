#import "IPAAssetCatalogDecoder.h"

// CoreUI is already loaded by UIKit. These optional selectors are resolved at
// runtime because UIImage(named:) cannot retrieve every app-icon rendition.
@interface NSObject (IPAResourceCatalog)
- (instancetype)initWithURL:(NSURL *)url error:(NSError **)error;
- (NSArray *)imagesWithName:(NSString *)name;
- (id)iconImageWithName:(NSString *)name scaleFactor:(double)scale
          displayGamut:(NSUInteger)gamut layoutDirection:(NSInteger)direction
           desiredSize:(CGSize)size;
@end

@protocol IPACatalogRendition <NSObject>
- (CGImageRef)image;
- (CGImageRef)unslicedImage;
@end

static UIImage *IPARenditionImage(id rendition) {
    if ([rendition isKindOfClass:UIImage.class]) { return rendition; }
    CGImageRef image = NULL;
    id<IPACatalogRendition> bitmap = rendition;
    if ([bitmap respondsToSelector:@selector(image)]) { image = [bitmap image]; }
    if (!image && [rendition respondsToSelector:@selector(unslicedImage)]) {
        image = [bitmap unslicedImage];
    }
    if (!image || CGImageGetWidth(image) > 4096 || CGImageGetHeight(image) > 4096) { return nil; }
    return [UIImage imageWithCGImage:image];
}

UIImage *IPAAssetCatalogIcon(NSURL *url, NSArray<NSString *> *names) {
    @autoreleasepool {
        @try {
            Class catalogClass = NSClassFromString(@"CUICatalog");
            if (![catalogClass instancesRespondToSelector:@selector(initWithURL:error:)]) { return nil; }
            NSError *error = nil;
            id catalog = [[catalogClass alloc] initWithURL:url error:&error];
            if (!catalog || error) { return nil; }
            for (NSString *name in names) {
                UIImage *best = nil;
                if ([catalog respondsToSelector:@selector(iconImageWithName:scaleFactor:displayGamut:layoutDirection:desiredSize:)]) {
                    best = IPARenditionImage([catalog iconImageWithName:name scaleFactor:1
                                                         displayGamut:1 layoutDirection:0
                                                          desiredSize:CGSizeMake(256, 256)]);
                }
                if (!best && [catalog respondsToSelector:@selector(imagesWithName:)]) {
                    id images = [catalog imagesWithName:name];
                    if ([images isKindOfClass:NSArray.class]) {
                        NSUInteger count = 0;
                        for (id rendition in images) {
                            if (++count > 64) { break; }
                            UIImage *image = IPARenditionImage(rendition);
                            if (image.size.width > best.size.width) { best = image; }
                        }
                    }
                }
                if (best) {
                    // Materialize pixels before deleting the temporary catalog.
                    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
                    format.scale = 1;
                    format.opaque = NO;
                    CGFloat ratio = MIN(1, 256 / MAX(best.size.width, best.size.height));
                    CGSize size = CGSizeMake(MAX(1, best.size.width * ratio), MAX(1, best.size.height * ratio));
                    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
                    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
                        [best drawInRect:(CGRect){CGPointZero, size}];
                    }];
                }
            }
        } @catch (NSException *exception) {
            // An unsupported catalog must leave a readable IPA with no icon.
            return nil;
        }
    }
    return nil;
}
