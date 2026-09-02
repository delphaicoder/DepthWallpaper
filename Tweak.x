/*
 * DepthWallpaper 1.5.0
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


static UIView *DW_FindClockBranch(UIView *clock, UIView *root) {
    if (!clock || !root) return nil;
    UIView *branch = clock;
    while (branch.superview && branch.superview != root) {
        branch = branch.superview;
    }
    return (branch.superview == root) ? branch : nil;
}

// Pick the smallest ancestor of the clock that can contain the whole lock-screen
// coordinate space. Keeping the overlay inside the clock's branch means top-level
// notification/banner branches stay above it.
static UIView *DW_FindOverlayContainer(UIView *clock, UIView *root) {
    if (!clock || !root) return nil;

    UIView *candidate = clock.superview;
    UIView *clockBranch = DW_FindClockBranch(clock, root);
    UIView *fallback = clockBranch ?: root;

    while (candidate && candidate != root) {
        CGRect rootInCandidate = [candidate convertRect:root.bounds fromView:root];
        CGRect expandedBounds = CGRectInset(candidate.bounds, -8.0, -8.0);
        if (CGRectContainsRect(expandedBounds, rootInCandidate)) {
            return candidate;
        }
        candidate = candidate.superview;
    }

    return fallback;
}

#pragma mark - Overlay manager

@interface DWManager : NSObject
@property (nonatomic, strong) UIView *hostView;
@property (nonatomic, strong) UIImageView *cutoutView;
@property (nonatomic, weak) UIView *lockRootView;
@property (nonatomic, weak) UIView *clockBranch;
@property (nonatomic) BOOL attachAttemptScheduled;
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
    self.hostView.opaque = NO;
    self.hostView.hidden = YES;

    self.cutoutView = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.cutoutView.backgroundColor = UIColor.clearColor;
    self.cutoutView.userInteractionEnabled = NO;
    self.cutoutView.clipsToBounds = NO;
    self.cutoutView.contentMode = UIViewContentModeScaleAspectFit;
    self.cutoutView.opaque = NO;
    [self.hostView addSubview:self.cutoutView];

    [self reloadImage];
    DW_Log(@"manager setup complete");
}

- (void)attachToLockScreenView:(UIView *)root {
    if (!root || !self.cutoutView) return;

    self.lockRootView = root;
    UIView *clock = DW_FindClockView(root);
    UIView *container = DW_FindOverlayContainer(clock, root);
    UIView *clockBranch = DW_FindClockBranch(clock, root);

    if (!clock || !container) {
        DW_Log([NSString stringWithFormat:@"attach failed: clock/container not found root=%@",
                NSStringFromClass(root.class)]);
        return;
    }

    // Keep the overlay INSIDE the same lock-screen/clock branch rather than on a
    // separate high-level UIWindow. This is the important z-order fix: notification
    // branches that SpringBoard owns outside the clock branch remain above the
    // cutout automatically.
    if (self.hostView.superview != container) {
        [self.hostView removeFromSuperview];
        [container addSubview:self.hostView];
    }

    CGRect rootRectInContainer = [container convertRect:root.bounds fromView:root];
    self.hostView.frame = rootRectInContainer;
    self.hostView.bounds = (CGRect){CGPointZero, root.bounds.size};
    self.hostView.autoresizingMask = UIViewAutoresizingNone;
    self.hostView.clipsToBounds = NO;

    // Put the host above the clock itself, but do not raise it above sibling
    // notification branches in the same Lock Screen hierarchy.
    NSInteger clockIndex = [container.subviews indexOfObject:clock];
    if (clockIndex != NSNotFound && clockIndex + 1 < (NSInteger)container.subviews.count) {
        [container insertSubview:self.hostView aboveSubview:clock];
    } else {
        [container bringSubviewToFront:self.hostView];
    }

    [self reloadImage];

    // Do not gate visibility on isUILocked here. During the lock transition
    // SpringBoard can report the old state for a short time; the controller hook
    // itself is our reliable indication that the Lock Screen is being displayed.
    self.hostView.hidden = (self.cutoutView.image == nil);

    DW_Log([NSString stringWithFormat:@"attached container=%@ clock=%@ branch=%@ frame=%@ subviews=%lu",
            NSStringFromClass(container.class), NSStringFromClass(clock.class),
            NSStringFromClass(clockBranch.class), NSStringFromCGRect(self.hostView.frame),
            (unsigned long)container.subviews.count]);
}

- (void)reloadImage {
    BOOL enabled = YES;
    CGPoint center = CGPointMake(0.5, 0.5);
    CGFloat scale = 1.0;
    DW_LoadMetadataValues(&enabled, &center, &scale);

    UIImage *image = DW_LoadCutoutImage();
    DW_Log([NSString stringWithFormat:@"reload enabled=%@ image=%@ center=(%.3f,%.3f) scale=%.3f",
            enabled ? @"YES" : @"NO", image ? @"YES" : @"NO", center.x, center.y, scale]);

    if (!self.cutoutView) return;
    self.cutoutView.image = enabled ? image : nil;

    UIView *root = self.lockRootView;
    if (!root) return;

    // hostView's bounds are a root-sized coordinate space even though the view
    // lives inside the lock-screen clock branch. This preserves the editor's
    // normalized position while allowing SpringBoard's higher-level notification
    // views to remain above us.
    self.cutoutView.bounds = (CGRect){CGPointZero, root.bounds.size};

    CGFloat w = CGRectGetWidth(root.bounds);
    CGFloat h = CGRectGetHeight(root.bounds);
    self.cutoutView.center = CGPointMake(w * center.x, h * center.y);
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
    if (self.attachAttemptScheduled) return;
    self.attachAttemptScheduled = YES;

    NSArray<NSNumber *> *delays = @[@0.0, @0.016, @0.04, @0.08, @0.12, @0.20, @0.40, @0.80];
    __weak typeof(self) weakSelf = self;
    for (NSNumber *delay in delays) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;

            Class cls = NSClassFromString(@"SBLockScreenViewController");
            UIView *candidate = nil;
            if (cls) {
                for (UIWindow *window in UIApplication.sharedApplication.windows) {
                    UIViewController *vc = window.rootViewController;
                    if ([vc isKindOfClass:cls]) {
                        candidate = vc.view;
                        break;
                    }
                }
            }
            if (!candidate) {
                for (UIWindow *window in UIApplication.sharedApplication.windows) {
                    UIView *rootView = window.rootViewController.view;
                    if (DW_FindClockView(rootView)) {
                        candidate = rootView;
                        break;
                    }
                }
            }
            if (candidate) {
                [self attachToLockScreenView:candidate];
            }

            if (delay == delays.lastObject) {
                self.attachAttemptScheduled = NO;
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
    UIViewController *lockVC = (UIViewController *)self;
    [[DWManager sharedInstance] attachToLockScreenView:lockVC.view];
    [[DWManager sharedInstance] scheduleAttachAttempts];
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    UIViewController *lockVC = (UIViewController *)self;
    [[DWManager sharedInstance] attachToLockScreenView:lockVC.view];
    [[DWManager sharedInstance] scheduleAttachAttempts];
}

- (void)viewWillLayoutSubviews {
    %orig;
    UIViewController *lockVC = (UIViewController *)self;
    [[DWManager sharedInstance] attachToLockScreenView:lockVC.view];
}

- (void)viewDidLayoutSubviews {
    %orig;
    UIViewController *lockVC = (UIViewController *)self;
    [[DWManager sharedInstance] attachToLockScreenView:lockVC.view];
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
