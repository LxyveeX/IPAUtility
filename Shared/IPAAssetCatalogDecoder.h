#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
// Resource-only lookup. The archive's executable is never extracted or loaded.
UIImage * _Nullable IPAAssetCatalogIcon(NSURL *url, NSArray<NSString *> *names);
NS_ASSUME_NONNULL_END
