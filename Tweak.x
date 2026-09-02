/*
 * DepthWallpaper 1.4.7
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


static BOOL DW_ClassNameLooksLikeNotification(UIView *view) {
    if (!view) return NO;
    NSString *name = NSStringFromClass(view.class).lowercaseString;
    return [name containsString:@"notification"] ||
           [name containsString:@"bulletin"] ||
           [name containsString:@"ncnotification"] ||
           [name containsString:@"banner"]; 
}

static void DW_BringNotificationBranchesAboveHost(UIView *root, UIView *host) {
    if (!root || !host) return;
    NSMutableArray<UIView *> *matches = [NSMutableArray array];

    // Iterative traversal avoids a self-referencing block, which older
    // clang/toolchains can warn about (and this project treats warnings as errors).
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count > 0) {
        UIView *view = stack.lastObject;
        [stack removeLastObject];
        if (!view) continue;
        if (DW_ClassNameLooksLikeNotification(view)) {
            [matches addObject:view];
        }
        for (UIView *sub in view.subviews) {
            if (sub) [stack addObject:sub];
        }
    }

    for (UIView *match in matches) {
        UIView *branch = match;
        while (branch.superview && branch.superview != root) {
            branch = branch.superview;
        }
        if (branch.superview == root && branch != host && branch != host.superview) {
            [root bringSubviewToFront:branch];
        }

        // If the notification is a sibling of the host, move that sibling to
        // the front of the exact parent as well.
        UIView *parent = match.superview;
        if (parent && host.superview == parent) {
            [parent bringSubviewToFront:match];
        }
    }
}

#pragma mark - Overlay manager

@interface DWManager : NSObject
@property (nonatomic, strong) UIView *hostView;
@property (nonatomic, strong) UIImageView *cutoutView;
@property (nonatomic, weak) UIView *lockRootView;
@property (nonatomic, weak) UIView *hostParentView;
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
    UIView *clockParent = clock.superview;

    if (!clock || !clockParent) {
        DW_Log([NSString stringWithFormat:@"attach failed: clock/parent not found root=%@",
                NSStringFromClass(root.class)]);
        return;
    }

    // Keep the overlay physically inside the Lock Screen clock container.
    // This makes it follow the Lock Screen's own transforms/animations instead
    // of behaving like an independent high-level window. Notification views
    // that live above this container naturally occlude the cutout while they
    // slide in, so the cutout does not paint over notifications.
    BOOL needsReattach = (self.hostView.superview != clockParent ||
                          self.hostParentView != clockParent);

    if (needsReattach) {
        [self.hostView removeFromSuperview];
        [clockParent insertSubview:self.hostView aboveSubview:clock];
        self.hostParentView = clockParent;
        self.clockAnchor = clock;
    }

    self.hostView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.hostView.clipsToBounds = NO;

    CGRect rootBoundsInParent = [clockParent convertRect:root.bounds fromView:root];
    self.hostView.frame = clockParent.bounds;

    // Keep the cutout's coordinate system tied to the Lock Screen root while
    // the containing view follows the clock/lock-screen animation.
    self.cutoutView.bounds = rootBoundsInParent;
    self.cutoutView.contentMode = UIViewContentModeScaleAspectFit;
    self.cutoutView.autoresizingMask = UIViewAutoresizingNone;

    [self reloadImage];
    DW_BringNotificationBranchesAboveHost(root, self.hostView);

    if (DW_IsUILocked()) {
        self.hostView.hidden = (self.cutoutView.image == nil);
    }

    DW_Log([NSString stringWithFormat:@"attached to lockscreen parent=%@ clock=%@ root=%@ reattach=%@",
            NSStringFromClass(clockParent.class), NSStringFromClass(clock.class),
            NSStringFromClass(root.class), needsReattach ? @"YES" : @"NO"]);
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
    UIView *parent = self.hostParentView;
    if (!root || !parent) return;

    self.hostView.frame = parent.bounds;
    CGRect rootRectInParent = [parent convertRect:root.bounds fromView:root];
    self.cutoutView.bounds = rootRectInParent;

    CGPoint rootPoint = CGPointMake(CGRectGetWidth(root.bounds) * center.x,
                                    CGRectGetHeight(root.bounds) * center.y);
    CGPoint pointInParent = [parent convertPoint:rootPoint fromView:root];
    self.cutoutView.center = pointInParent;
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
    if (self.lockRootView) {
        [self attachToLockScreenView:self.lockRootView];
    }
    self.hostView.hidden = (self.cutoutView.image == nil || self.lockRootView == nil);
    [self scheduleAttachAttempts];
}

- (void)scheduleAttachAttempts {
    [self setup];
    NSArray<NSNumber *> *delays = @[@0.0, @0.016, @0.04, @0.08, @0.12, @0.20, @0.40];
    __weak typeof(self) weakSelf = self;
    for (NSNumber *delay in delays) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;

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

- (void)viewDidLoad {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *lockVC = (UIViewController *)self;
        [[DWManager sharedInstance] attachToLockScreenView:lockVC.view];
        [[DWManager sharedInstance] scheduleAttachAttempts];
    });
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *lockVC = (UIViewController *)self;
        [[DWManager sharedInstance] attachToLockScreenView:lockVC.view];
        [[DWManager sharedInstance] scheduleAttachAttempts];
    });
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *lockVC = (UIViewController *)self;
        [[DWManager sharedInstance] attachToLockScreenView:lockVC.view];
        [[DWManager sharedInstance] scheduleAttachAttempts];
    });
}

- (void)viewWillLayoutSubviews {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *lockVC = (UIViewController *)self;
        [[DWManager sharedInstance] attachToLockScreenView:lockVC.view];
    });
}

- (void)viewDidLayoutSubviews {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *lockVC = (UIViewController *)self;
        [[DWManager sharedInstance] attachToLockScreenView:lockVC.view];
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
