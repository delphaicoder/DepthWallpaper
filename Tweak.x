/*
 * DepthWallpaper 1.4.5
 *
 * Manual depth overlay for SpringBoard.
 * The cutout is inserted into the Lock Screen view hierarchy, positioned just
 * above the clock/date ancestor instead of using a very high UIWindow level.
 * This keeps notification UI above the cutout whenever SpringBoard places it
 * in a sibling/higher container.
 */

#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>
#import <objc/message.h>
#import "DWShared.h"

#pragma mark - Logging

static void DW_Log(NSString *message) {
    if (!message) return;
    NSString *dir = @"/var/mobile/Library/Logs";
    NSString *path = @"/var/mobile/Library/Logs/DepthWallpaperTweak.log";
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) {
        [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        handle = [NSFileHandle fileHandleForWritingAtPath:path];
    }
    if (handle) {
        @try {
            [handle seekToEndOfFile];
            [handle writeData:data];
            [handle closeFile];
        } @catch (__unused id e) {
        }
    }
}

#pragma mark - Metadata / image

static UIImage *DW_LoadCutoutImage(void) {
    return [UIImage imageWithContentsOfFile:DWCutoutImagePath];
}

static NSDictionary *DW_ReadMetadataDictionary(void) {
    return [NSDictionary dictionaryWithContentsOfFile:DWMetadataPath] ?: @{};
}

static void DW_LoadMetadataValues(BOOL *outEnabled, CGPoint *outCenter, CGFloat *outScale) {
    NSDictionary *meta = DW_ReadMetadataDictionary();
    BOOL enabled = meta[DWMetaKeyEnabled] ? [meta[DWMetaKeyEnabled] boolValue] : YES;
    CGFloat x = meta[DWMetaKeyCutoutCenterX] ? [meta[DWMetaKeyCutoutCenterX] doubleValue] : 0.5;
    CGFloat y = meta[DWMetaKeyCutoutCenterY] ? [meta[DWMetaKeyCutoutCenterY] doubleValue] : 0.5;
    CGFloat scale = meta[DWMetaKeyCutoutScale] ? [meta[DWMetaKeyCutoutScale] doubleValue] : 1.0;
    if (outEnabled) *outEnabled = enabled;
    if (outCenter) *outCenter = CGPointMake(MIN(1.5, MAX(-0.5, x)), MIN(1.5, MAX(-0.5, y)));
    if (outScale) *outScale = MIN(4.0, MAX(0.25, scale));
}

#pragma mark - Lock Screen view helpers

static BOOL DW_IsUILocked(void) {
    Class cls = NSClassFromString(@"SBLockScreenManager");
    if (!cls) return NO;
    SEL sharedSel = NSSelectorFromString(@"sharedInstance");
    SEL lockedSel = NSSelectorFromString(@"isUILocked");
    id manager = nil;
    if ([cls respondsToSelector:sharedSel]) {
        id (*sendShared)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
        manager = sendShared(cls, sharedSel);
    }
    if (!manager || ![manager respondsToSelector:lockedSel]) return NO;
    BOOL (*sendLocked)(id, SEL) = (BOOL (*)(id, SEL))objc_msgSend;
    return sendLocked(manager, lockedSel);
}

static BOOL DW_ClassNameLooksLikeClock(UIView *view) {
    NSString *name = NSStringFromClass(view.class);
    NSString *lower = name.lowercaseString;
    if ([lower containsString:@"lockscreen"] &&
        ([lower containsString:@"date"] || [lower containsString:@"clock"])) {
        return YES;
    }
    // Known iOS 15 family used by many SpringBoard builds.
    if ([name isEqualToString:@"SBFLockScreenDateView"] ||
        [name isEqualToString:@"SBFLockScreenDateSubtitleView"] ||
        [name isEqualToString:@"SBUILockScreenDateView"]) {
        return YES;
    }
    return NO;
}

static UIView *DW_FindClockView(UIView *root) {
    if (!root) return nil;
    if (DW_ClassNameLooksLikeClock(root)) return root;
    for (UIView *sub in root.subviews) {
        UIView *found = DW_FindClockView(sub);
        if (found) return found;
    }
    return nil;
}

static UIView *DW_TopChildUnderRoot(UIView *view, UIView *root) {
    UIView *current = view;
    while (current.superview && current.superview != root) {
        current = current.superview;
    }
    return (current.superview == root) ? current : nil;
}

#pragma mark - Overlay manager

@interface DWManager : NSObject
@property (nonatomic, strong) UIView *hostView;
@property (nonatomic, strong) UIImageView *cutoutView;
@property (nonatomic, weak) UIView *lockRootView;
@property (nonatomic, weak) UIView *clockAnchor;
+ (instancetype)sharedInstance;
- (void)setup;
- (void)attachToLockScreenView:(UIView *)root;
- (void)reloadImage;
- (void)setLocked:(BOOL)locked;
- (void)scheduleAttachAttempts;
@end

static DWManager *gDWManager = nil;
static dispatch_once_t gDWManagerOnceToken = 0;

@implementation DWManager

+ (instancetype)sharedInstance {
    dispatch_once(&gDWManagerOnceToken, ^{
        gDWManager = [DWManager new];
    });
    return gDWManager;
}

- (void)setup {
    if (self.cutoutView) return;

    self.hostView = [[UIView alloc] initWithFrame:CGRectZero];
    self.hostView.backgroundColor = UIColor.clearColor;
    self.hostView.userInteractionEnabled = NO;
    self.hostView.clipsToBounds = NO;
    self.hostView.hidden = YES;

    self.cutoutView = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.cutoutView.backgroundColor = UIColor.clearColor;
    self.cutoutView.userInteractionEnabled = NO;
    self.cutoutView.clipsToBounds = NO;
    self.cutoutView.contentMode = UIViewContentModeScaleAspectFit;
    [self.hostView addSubview:self.cutoutView];

    [self reloadImage];
    DW_Log(@"manager setup complete");
}

- (void)attachToLockScreenView:(UIView *)root {
    if (!root || !self.cutoutView) return;

    self.lockRootView = root;
    UIView *clock = DW_FindClockView(root);
    UIView *anchor = clock ? DW_TopChildUnderRoot(clock, root) : nil;

    if (!clock || !anchor) {
        DW_Log([NSString stringWithFormat:@"attach failed: clock not found root=%@", NSStringFromClass(root.class)]);
        return;
    }

    BOOL needsReattach = (self.hostView.superview != root || self.clockAnchor != anchor);
    self.hostView.frame = root.bounds;
    if (needsReattach) {
        [self.hostView removeFromSuperview];
        [root insertSubview:self.hostView aboveSubview:anchor];
        self.clockAnchor = anchor;
    }

    self.hostView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    DW_Log([NSString stringWithFormat:@"attached root=%@ clock=%@ anchor=%@ reattach=%@",
            NSStringFromClass(root.class), NSStringFromClass(clock.class), NSStringFromClass(anchor.class), needsReattach ? @"YES" : @"NO"]);

    [self reloadImage];

    if (DW_IsUILocked()) {
        self.hostView.hidden = (self.cutoutView.image == nil);
    }
}

- (void)reloadImage {
    BOOL enabled = YES;
    CGPoint center = CGPointMake(0.5, 0.5);
    CGFloat scale = 1.0;
    DW_LoadMetadataValues(&enabled, &center, &scale);

    UIImage *image = DW_LoadCutoutImage();
    DW_Log([NSString stringWithFormat:@"reload enabled=%@ image=%@",
            enabled ? @"YES" : @"NO", image ? @"YES" : @"NO"]);

    if (!self.cutoutView) return;
    if (!image || !enabled) {
        self.cutoutView.image = nil;
        if (!DW_IsUILocked()) self.hostView.hidden = YES;
        return;
    }

    self.cutoutView.image = image;

    UIView *root = self.lockRootView;
    if (!root) return;

    self.hostView.frame = root.bounds;
    self.cutoutView.bounds = root.bounds;
    self.cutoutView.center = CGPointMake(CGRectGetWidth(root.bounds) * center.x,
                                         CGRectGetHeight(root.bounds) * center.y);
    self.cutoutView.transform = CGAffineTransformMakeScale(scale, scale);
    self.cutoutView.contentMode = UIViewContentModeScaleAspectFit;
    self.cutoutView.autoresizingMask = UIViewAutoresizingNone;
}

- (void)setLocked:(BOOL)locked {
    [self setup];
    DW_Log([NSString stringWithFormat:@"setLocked=%@", locked ? @"YES" : @"NO"]);

    if (!locked) {
        self.hostView.hidden = YES;
        return;
    }

    [self reloadImage];
    self.hostView.hidden = (self.cutoutView.image == nil || self.lockRootView == nil);
    [self scheduleAttachAttempts];
}

- (void)scheduleAttachAttempts {
    [self setup];
    NSArray<NSNumber *> *delays = @[@0.0, @0.08, @0.20, @0.50, @1.0];
    __weak typeof(self) weakSelf = self;
    for (NSNumber *delay in delays) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || !DW_IsUILocked()) return;

            // Re-discover the lock-screen controller's visible view without assuming
            // one particular scene/window.
            Class cls = NSClassFromString(@"SBLockScreenViewController");
            if (cls) {
                for (UIWindow *window in UIApplication.sharedApplication.windows) {
                    UIViewController *vc = window.rootViewController;
                    if ([vc isKindOfClass:cls]) {
                        [self attachToLockScreenView:vc.view];
                        return;
                    }
                    if ([vc.view isDescendantOfView:window] && vc.view.window == window) {
                        UIView *candidate = vc.view;
                        // If this window is a SpringBoard lock-screen window, the
                        // clock heuristic below will find the right subtree.
                        if (DW_FindClockView(candidate)) {
                            [self attachToLockScreenView:candidate];
                            return;
                        }
                    }
                }
            }

            for (UIWindow *window in UIApplication.sharedApplication.windows) {
                if (DW_FindClockView(window.rootViewController.view)) {
                    [self attachToLockScreenView:window.rootViewController.view];
                    return;
                }
            }
        });
    }
}

@end

#pragma mark - Darwin notifications

static void DW_SetLockedOnMainThread(BOOL locked) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[DWManager sharedInstance] setLocked:locked];
    });
}

static void DW_LockStateChanged(CFNotificationCenterRef c, void *o, CFStringRef name, const void *obj, CFDictionaryRef info) {
    DW_Log(@"darwin lockstate notification");
    DW_SetLockedOnMainThread(DW_IsUILocked());
}

static void DW_ReloadRequested(CFNotificationCenterRef c, void *o, CFStringRef name, const void *obj, CFDictionaryRef info) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[DWManager sharedInstance] reloadImage];
        if (DW_IsUILocked()) [[DWManager sharedInstance] scheduleAttachAttempts];
    });
}

#pragma mark - SpringBoard / LockScreen hooks

%hook SBLockScreenViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (DW_IsUILocked()) {
            UIViewController *lockVC = (UIViewController *)self;
            [[DWManager sharedInstance] attachToLockScreenView:lockVC.view];
        }
    });
}

- (void)viewDidLayoutSubviews {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (DW_IsUILocked()) {
            UIViewController *lockVC = (UIViewController *)self;
            [[DWManager sharedInstance] attachToLockScreenView:lockVC.view];
        }
    });
}

%end

%hook SBLockScreenManager

- (void)lockUIFromSource:(int)source withOptions:(id)options {
    %orig;
    DW_SetLockedOnMainThread(YES);
}

- (void)unlockUIFromSource:(int)source withOptions:(id)options {
    %orig;
    DW_SetLockedOnMainThread(NO);
}

%end

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;

    [[DWManager sharedInstance] setup];

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        DW_LockStateChanged, CFSTR("com.apple.springboard.lockstate"), NULL,
        CFNotificationSuspensionBehaviorCoalesce);

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        DW_ReloadRequested, DWReloadNotification, NULL,
        CFNotificationSuspensionBehaviorCoalesce);

    if (DW_IsUILocked()) {
        [[DWManager sharedInstance] setLocked:YES];
    }
}

%end
