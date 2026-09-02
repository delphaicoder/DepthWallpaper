/*
 * DepthWallpaper 1.5.5
 * Manual PNG depth overlay for iOS 15 Lock Screen.
 *
 * Strategy:
 * - Attach from SBFLockScreenDateView lifecycle (the actual clock view), so
 *   the cutout appears as soon as the Lock Screen clock exists.
 * - Use the lowest common ancestor between clock and notification views.
 * - Insert CUTOUT above the clock branch and below the notification branch.
 * - Never use a high-level UIWindow and never hide merely because a dashboard
 *   window is temporarily unavailable.
 */

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <objc/message.h>
#import "DWShared.h"

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
    if (!data) return;
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
        } @catch (__unused id e) {}
    }
}

static UIImage *DW_LoadCutoutImage(void) {
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:DWCutoutImagePath error:nil];
    NSNumber *fileSize = attributes[NSFileSize];
    DW_Log([NSString stringWithFormat:@"load cutout path=%@ exists=%@ bytes=%@",
            DWCutoutImagePath,
            attributes ? @"YES" : @"NO",
            fileSize ?: @0]);
    return [UIImage imageWithContentsOfFile:DWCutoutImagePath];
}

static void DW_LoadMetadata(BOOL *enabledOut, CGPoint *centerOut, CGFloat *scaleOut) {
    NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:DWMetadataPath] ?: @{};
    BOOL enabled = meta[DWMetaKeyEnabled] ? [meta[DWMetaKeyEnabled] boolValue] : YES;
    CGFloat x = meta[DWMetaKeyCutoutCenterX] ? [meta[DWMetaKeyCutoutCenterX] doubleValue] : 0.5;
    CGFloat y = meta[DWMetaKeyCutoutCenterY] ? [meta[DWMetaKeyCutoutCenterY] doubleValue] : 0.5;
    CGFloat scale = meta[DWMetaKeyCutoutScale] ? [meta[DWMetaKeyCutoutScale] doubleValue] : 1.0;
    if (enabledOut) *enabledOut = enabled;
    if (centerOut) *centerOut = CGPointMake(MIN(1.5, MAX(-0.5, x)), MIN(1.5, MAX(-0.5, y)));
    if (scaleOut) *scaleOut = MIN(4.0, MAX(0.25, scale));
}

static UIView *DW_FindFirstMatchingView(UIView *root, BOOL (^matcher)(UIView *)) {
    if (!root) return nil;
    if (matcher && matcher(root)) return root;
    NSArray *children = [root.subviews copy];
    for (UIView *sub in children) {
        UIView *found = DW_FindFirstMatchingView(sub, matcher);
        if (found) return found;
    }
    return nil;
}

static BOOL DW_IsClockClass(UIView *view) {
    if (!view) return NO;
    NSString *name = NSStringFromClass(view.class);
    return [name isEqualToString:@"SBFLockScreenDateView"] ||
           [name isEqualToString:@"SBUILockScreenDateView"] ||
           [name containsString:@"LockScreenDateView"];
}

static BOOL DW_IsNotificationClass(UIView *view) {
    if (!view) return NO;
    NSString *name = NSStringFromClass(view.class).lowercaseString;
    return [name containsString:@"ncnotification"] ||
           [name containsString:@"notificationlist"] ||
           [name containsString:@"notificationcollection"] ||
           [name containsString:@"notificationstack"] ||
           [name containsString:@"bulletinlist"] ||
           [name containsString:@"dashboardscombinedlist"] ||
           [name containsString:@"dashboardscombinedlist"];
}

static UIView *DW_FindDashboardRoot(UIView *view) {
    UIView *candidate = view;
    while (candidate) {
        NSString *name = NSStringFromClass(candidate.class);
        if ([name isEqualToString:@"SBDashBoardView"] ||
            [name isEqualToString:@"SBDashBoardTodayPageView"] ||
            [name containsString:@"DashBoardView"]) {
            return candidate;
        }
        candidate = candidate.superview;
    }
    return view.window.rootViewController.view ?: view.window ?: view;
}

static UIView *DW_DirectChildUnderRoot(UIView *descendant, UIView *root) {
    if (!descendant || !root) return nil;
    UIView *v = descendant;
    while (v.superview && v.superview != root) v = v.superview;
    return (v.superview == root) ? v : nil;
}

static UIView *DW_LowestCommonAncestor(UIView *a, UIView *b) {
    if (!a || !b) return nil;
    NSMutableSet *ancestors = [NSMutableSet set];
    UIView *v = a;
    while (v) {
        [ancestors addObject:v];
        v = v.superview;
    }
    v = b;
    while (v) {
        if ([ancestors containsObject:v]) return v;
        v = v.superview;
    }
    return nil;
}

static UIView *DW_FindSafeParent(UIView *clock, UIView *notification) {
    UIView *common = DW_LowestCommonAncestor(clock, notification);
    if (common) {
        // The common ancestor is preferred, because it lets us control both
        // branches in one z-order operation. If it clips, walk upward.
        UIView *p = common;
        while (p.superview && p.clipsToBounds) p = p.superview;
        return p;
    }

    UIView *p = clock.superview;
    while (p.superview && p.clipsToBounds) p = p.superview;
    return p ?: clock.superview ?: clock;
}

@interface DWManager : NSObject
@property (nonatomic, strong) UIView *hostView;
@property (nonatomic, strong) UIImageView *cutoutView;
@property (nonatomic, weak) UIView *clockView;
@property (nonatomic, weak) UIView *dashboardView;
@property (nonatomic) BOOL reattachScheduled;
+ (instancetype)sharedInstance;
- (void)setup;
- (void)reloadImage;
- (void)setLocked:(BOOL)locked;
- (void)attachToClockView:(UIView *)clockView;
- (void)attachToDashboardView:(UIView *)dashboard;
- (void)scheduleAttachRetries;
- (void)scheduleReattach;
@end

static DWManager *gDWManager = nil;
static dispatch_once_t gDWManagerOnce = 0;

@implementation DWManager

+ (instancetype)sharedInstance {
    dispatch_once(&gDWManagerOnce, ^{
        gDWManager = [DWManager new];
    });
    return gDWManager;
}

- (void)setup {
    if (self.cutoutView) return;

    self.hostView = [[UIView alloc] initWithFrame:CGRectZero];
    self.hostView.backgroundColor = UIColor.clearColor;
    self.hostView.opaque = NO;
    self.hostView.clipsToBounds = NO;
    self.hostView.userInteractionEnabled = NO;
    self.hostView.hidden = YES;

    self.cutoutView = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.cutoutView.backgroundColor = UIColor.clearColor;
    self.cutoutView.opaque = NO;
    self.cutoutView.clipsToBounds = NO;
    self.cutoutView.userInteractionEnabled = NO;
    self.cutoutView.contentMode = UIViewContentModeScaleAspectFit;
    [self.hostView addSubview:self.cutoutView];

    [self reloadImage];
}

- (void)updateGeometryForClock:(UIView *)clock inParent:(UIView *)parent dashboard:(UIView *)dashboard {
    if (!clock || !parent || !dashboard || !self.hostView || !self.cutoutView) return;

    CGRect dashboardRect = [dashboard convertRect:dashboard.bounds toView:parent];
    if (CGRectIsEmpty(dashboardRect) || dashboardRect.size.width <= 1.0 || dashboardRect.size.height <= 1.0) {
        return;
    }

    self.hostView.frame = dashboardRect;
    self.hostView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    CGSize size = dashboardRect.size;
    BOOL enabled = YES;
    CGPoint center = CGPointMake(0.5, 0.5);
    CGFloat scale = 1.0;
    DW_LoadMetadata(&enabled, &center, &scale);

    self.cutoutView.bounds = (CGRect){ CGPointZero, size };
    self.cutoutView.center = CGPointMake(size.width * center.x, size.height * center.y);
    self.cutoutView.transform = CGAffineTransformMakeScale(scale, scale);

    DW_Log([NSString stringWithFormat:@"geometry parent=%@ dashboard=%@ rect=%@ center=(%.3f,%.3f) scale=%.3f enabled=%@",
            NSStringFromClass(parent.class), NSStringFromClass(dashboard.class),
            NSStringFromCGRect(dashboardRect), center.x, center.y, scale,
            enabled ? @"YES" : @"NO"]);
}

- (void)reorderHostWithClock:(UIView *)clock notification:(UIView *)notification parent:(UIView *)parent {
    if (!parent || !self.hostView) return;

    UIView *clockBranch = DW_DirectChildUnderRoot(clock, parent);
    UIView *notificationBranch = DW_DirectChildUnderRoot(notification, parent);

    if (self.hostView.superview != parent) {
        [self.hostView removeFromSuperview];
        [parent addSubview:self.hostView];
    }

    // Notification branch must be above CUTOUT; clock branch must be below it.
    if (clockBranch && notificationBranch && clockBranch != notificationBranch) {
        [parent insertSubview:self.hostView aboveSubview:clockBranch];
        [parent insertSubview:self.hostView belowSubview:notificationBranch];
        return;
    }

    if (notificationBranch) {
        [parent insertSubview:self.hostView belowSubview:notificationBranch];
        return;
    }

    if (clockBranch) {
        [parent insertSubview:self.hostView aboveSubview:clockBranch];
        return;
    }

    // Last-resort placement: top of the parent so the cutout remains visible.
    // A later notification layout will reposition it below notifications.
    [parent bringSubviewToFront:self.hostView];
}

- (void)attachToClockView:(UIView *)clockView {
    if (!clockView) return;
    [self setup];
    self.clockView = clockView;
    self.dashboardView = DW_FindDashboardRoot(clockView);

    UIView *dashboard = self.dashboardView ?: clockView.window.rootViewController.view ?: clockView;
    UIView *notification = DW_FindFirstMatchingView(dashboard, ^BOOL(UIView *view) {
        return DW_IsNotificationClass(view);
    });
    UIView *parent = DW_FindSafeParent(clockView, notification);
    if (!parent) parent = dashboard;

    [self updateGeometryForClock:clockView inParent:parent dashboard:dashboard];

    UIImage *image = DW_LoadCutoutImage();
    BOOL enabled = YES;
    DW_LoadMetadata(&enabled, NULL, NULL);
    self.cutoutView.image = enabled ? image : nil;

    [self reorderHostWithClock:clockView notification:notification parent:parent];

    BOOL visible = enabled && image != nil && clockView.window != nil;
    self.hostView.hidden = !visible;

    DW_Log([NSString stringWithFormat:@"ATTACH CLOCK clock=%@ parent=%@ notification=%@ image=%@ visible=%@ hostSuperview=%@",
            NSStringFromClass(clockView.class),
            NSStringFromClass(parent.class),
            notification ? NSStringFromClass(notification.class) : @"<none>",
            image ? @"YES" : @"NO",
            visible ? @"YES" : @"NO",
            self.hostView.superview ? NSStringFromClass(self.hostView.superview.class) : @"<nil>"]);
}

- (void)attachToDashboardView:(UIView *)dashboard {
    if (!dashboard) return;
    [self setup];
    self.dashboardView = dashboard;

    UIView *clock = DW_FindFirstMatchingView(dashboard, ^BOOL(UIView *view) {
        return DW_IsClockClass(view);
    });
    if (clock) {
        [self attachToClockView:clock];
        return;
    }

    // No clock yet. Keep a lightweight fallback on the dashboard and retry.
    UIImage *image = DW_LoadCutoutImage();
    BOOL enabled = YES;
    DW_LoadMetadata(&enabled, NULL, NULL);
    self.cutoutView.image = enabled ? image : nil;
    self.hostView.frame = dashboard.bounds;
    self.cutoutView.frame = self.hostView.bounds;
    self.hostView.hidden = !(enabled && image && dashboard.window);
    if (self.hostView.superview != dashboard) {
        [self.hostView removeFromSuperview];
        [dashboard addSubview:self.hostView];
    }
    DW_Log([NSString stringWithFormat:@"FALLBACK DASHBOARD %@ clock=<none> image=%@ visible=%@",
            NSStringFromClass(dashboard.class), image ? @"YES" : @"NO", self.hostView.hidden ? @"NO" : @"YES"]);
}

- (void)reloadImage {
    [self setup];
    BOOL enabled = YES;
    DW_LoadMetadata(&enabled, NULL, NULL);
    UIImage *image = DW_LoadCutoutImage();
    self.cutoutView.image = enabled ? image : nil;

    UIView *clock = self.clockView;
    if (clock && clock.window) {
        [self attachToClockView:clock];
        return;
    }

    UIView *dashboard = self.dashboardView;
    if (dashboard && dashboard.window) {
        [self attachToDashboardView:dashboard];
    }
}

- (void)setLocked:(BOOL)locked {
    [self setup];
    if (!locked) {
        self.hostView.hidden = YES;
        DW_Log(@"setLocked=NO -> hide");
        return;
    }
    DW_Log(@"setLocked=YES -> schedule clock attach");
    [self scheduleAttachRetries];
}

- (void)scheduleAttachRetries {
    [self setup];
    NSArray<NSNumber *> *delays = @[@0.0, @0.016, @0.04, @0.08, @0.12, @0.20, @0.40, @0.80, @1.20];
    __weak typeof(self) weakSelf = self;
    for (NSNumber *delay in delays) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;

            UIView *clock = self.clockView;
            if (!clock || !clock.window) {
                Class clockClass = NSClassFromString(@"SBFLockScreenDateView");
                if (clockClass) {
                    for (UIWindow *window in UIApplication.sharedApplication.windows) {
                        UIView *root = window.rootViewController.view;
                        UIView *found = DW_FindFirstMatchingView(root, ^BOOL(UIView *view) {
                            return [view isKindOfClass:clockClass];
                        });
                        if (found) {
                            clock = found;
                            break;
                        }
                    }
                }
            }

            if (clock && clock.window) {
                [self attachToClockView:clock];
                return;
            }

            Class dashboardClass = NSClassFromString(@"SBDashBoardView");
            if (dashboardClass) {
                for (UIWindow *window in UIApplication.sharedApplication.windows) {
                    UIView *root = window.rootViewController.view;
                    UIView *dashboard = DW_FindFirstMatchingView(root, ^BOOL(UIView *view) {
                        return [view isKindOfClass:dashboardClass];
                    });
                    if (dashboard) {
                        [self attachToDashboardView:dashboard];
                        break;
                    }
                }
            }
        });
    }
}

- (void)scheduleReattach {
    if (self.reattachScheduled) return;
    self.reattachScheduled = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self.reattachScheduled = NO;

        UIView *clock = self.clockView;
        if (clock && clock.window) {
            [self attachToClockView:clock];
        }
    });
}

@end

static void DW_SetLockedOnMainThread(BOOL locked) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[DWManager sharedInstance] setLocked:locked];
    });
}

static BOOL DW_IsUILocked(void) {
    Class managerClass = NSClassFromString(@"SBLockScreenManager");
    if (!managerClass) return NO;
    SEL sharedSel = NSSelectorFromString(@"sharedInstance");
    SEL lockedSel = NSSelectorFromString(@"isUILocked");
    id manager = nil;
    if ([managerClass respondsToSelector:sharedSel]) {
        id (*sendShared)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
        manager = sendShared(managerClass, sharedSel);
    }
    if (!manager || ![manager respondsToSelector:lockedSel]) return NO;
    BOOL (*sendLocked)(id, SEL) = (BOOL (*)(id, SEL))objc_msgSend;
    return sendLocked(manager, lockedSel);
}

static void DW_LockStateChanged(CFNotificationCenterRef center, void *observer,
                                CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    DW_Log(@"darwin lockstate notification");
    if (DW_IsUILocked()) DW_SetLockedOnMainThread(YES);
}

static void DW_ReloadRequested(CFNotificationCenterRef center, void *observer,
                               CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[DWManager sharedInstance] reloadImage];
        [[DWManager sharedInstance] scheduleAttachRetries];
    });
}

%hook SBFLockScreenDateView

- (void)didMoveToWindow {
    %orig;
    UIView *clockView = (UIView *)self;
    if (clockView.window) {
        [[DWManager sharedInstance] attachToClockView:clockView];
        [[DWManager sharedInstance] scheduleAttachRetries];
    }
}

- (void)layoutSubviews {
    %orig;
    [[DWManager sharedInstance] scheduleReattach];
}

%end

%hook SBDashBoardViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    UIViewController *vc = (UIViewController *)self;
    [[DWManager sharedInstance] attachToDashboardView:vc.view];
    [[DWManager sharedInstance] scheduleAttachRetries];
}

- (void)viewDidLayoutSubviews {
    %orig;
    UIViewController *vc = (UIViewController *)self;
    [[DWManager sharedInstance] attachToDashboardView:vc.view];
}

%end

%hook SBDashBoardView

- (void)didMoveToWindow {
    %orig;
    UIView *view = (UIView *)self;
    if (view.window) {
        [[DWManager sharedInstance] attachToDashboardView:view];
        [[DWManager sharedInstance] scheduleAttachRetries];
    }
}

%end

%hook SBDashBoardCombinedListViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    UIViewController *vc = (UIViewController *)self;
    [[DWManager sharedInstance] scheduleReattach];
    [[DWManager sharedInstance] attachToDashboardView:vc.view.window.rootViewController.view ?: vc.view];
}

- (void)viewDidLayoutSubviews {
    %orig;
    [[DWManager sharedInstance] scheduleReattach];
}

%end

%hook NCNotificationListCollectionView

- (void)didMoveToWindow {
    %orig;
    UIView *notificationView = (UIView *)self;
    if (notificationView.window) [[DWManager sharedInstance] scheduleReattach];
}

- (void)layoutSubviews {
    %orig;
    [[DWManager sharedInstance] scheduleReattach];
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

    if (DW_IsUILocked()) [[DWManager sharedInstance] scheduleAttachRetries];
}

- (void)frontDisplayDidChange:(id)newDisplay {
    %orig;
    if ([newDisplay isKindOfClass:[UIViewController class]]) {
        UIViewController *vc = (UIViewController *)newDisplay;
        [[DWManager sharedInstance] attachToDashboardView:vc.view];
        [[DWManager sharedInstance] scheduleAttachRetries];
    }
}

%end
