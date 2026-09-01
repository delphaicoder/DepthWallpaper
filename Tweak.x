#import <UIKit/UIKit.h>
#import "DWShared.h"

@interface DWOverlayWindow : UIWindow
@end
@implementation DWOverlayWindow
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event { return NO; }
@end

@interface DWManager : NSObject
@property (nonatomic, strong) DWOverlayWindow *window;
@property (nonatomic, strong) UIImageView *cutoutView;
- (void)setup;
- (void)reloadImage;
- (void)setLocked:(BOOL)locked;
@end

@implementation DWManager

- (void)setup {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.window) return;

        UIWindowScene *scene = nil;
        for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
            if ([candidate isKindOfClass:[UIWindowScene class]]) {
                scene = (UIWindowScene *)candidate;
                if (candidate.activationState == UISceneActivationStateForegroundActive) break;
            }
        }

        DWOverlayWindow *window = scene ? [[DWOverlayWindow alloc] initWithWindowScene:scene]
                                        : [[DWOverlayWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        window.backgroundColor = UIColor.clearColor;
        window.windowLevel = UIWindowLevelStatusBar + 1500.0;
        window.rootViewController = [UIViewController new];
        window.rootViewController.view.backgroundColor = UIColor.clearColor;
        window.hidden = YES;

        UIImageView *imageView = [[UIImageView alloc] initWithFrame:window.bounds];
        imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        imageView.contentMode = UIViewContentModeScaleToFill;
        imageView.userInteractionEnabled = NO;
        imageView.backgroundColor = UIColor.clearColor;
        [window.rootViewController.view addSubview:imageView];

        self.window = window;
        self.cutoutView = imageView;
        [self reloadImage];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadImage)
                                                     name:UIApplicationDidChangeStatusBarOrientationNotification object:nil];
    });
}

- (void)reloadImage {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.window || !self.cutoutView) return;

        NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:DWMetadataPath];
        BOOL enabled = meta[DWMetaKeyEnabled] ? [meta[DWMetaKeyEnabled] boolValue] : YES;
        BOOL pairMatch = meta[DWMetaKeyAspectMatch] ? [meta[DWMetaKeyAspectMatch] boolValue] : YES;
        UIImage *image = [UIImage imageWithContentsOfFile:DWCutoutImagePath];

        if (!enabled || !pairMatch || !image) {
            self.cutoutView.image = nil;
            return;
        }

        self.cutoutView.image = image;
        self.cutoutView.frame = self.window.bounds;
    });
}

- (void)setLocked:(BOOL)locked {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.window) return;
        if (locked) {
            [self reloadImage];
            self.window.hidden = NO;
        } else {
            self.window.hidden = YES;
        }
    });
}

@end


static DWManager *gDWManager = nil;
static dispatch_once_t gDWManagerOnceToken = 0;

static DWManager *DWManagerInstance(void) {
    dispatch_once(&gDWManagerOnceToken, ^{
        gDWManager = [DWManager new];
    });
    return gDWManager;
}

static void DW_LockStateChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    BOOL locked = !UIApplication.sharedApplication.isProtectedDataAvailable;
    dispatch_async(dispatch_get_main_queue(), ^{
        [DWManagerInstance() setLocked:locked];
    });
}

static void DW_ReloadRequested(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    [DWManagerInstance() reloadImage];
}

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    [DWManagerInstance() setup];

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        DW_LockStateChanged, CFSTR("com.apple.springboard.lockstate"), NULL,
        CFNotificationSuspensionBehaviorCoalesce);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        DW_ReloadRequested, DWReloadNotification, NULL,
        CFNotificationSuspensionBehaviorCoalesce);

    BOOL locked = !UIApplication.sharedApplication.isProtectedDataAvailable;
    [DWManagerInstance() setLocked:locked];
}
%end
