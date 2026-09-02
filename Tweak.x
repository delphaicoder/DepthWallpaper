/*
 * DepthWallpaper 1.5.3
 * Manual PNG depth overlay for the iOS 15 dashboard/Lock Screen.
 *
 * Layering target:
 *   clock branch < CUTOUT < notification branch
 *
 * The overlay is inserted into the dashboard view hierarchy rather than a
 * separate high-level UIWindow. This avoids covering Lock Screen notifications.
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

static BOOL DW_IsClockView(UIView *view) {
    if (!view) return NO;
    NSString *name = NSStringFromClass(view.class);
    NSString *lower = name.lowercaseString;
    if ([name isEqualToString:@"SBFLockScreenDateView"] ||
        [name isEqualToString:@"SBUILockScreenDateView"] ||
        [name isEqualToString:@"SBFLockScreenDateSubtitleView"]) return YES;
    return ([lower containsString:@"lockscreen"] &&
            ([lower containsString:@"dateview"] || [lower containsString:@"clockview"] ||
             [lower containsString:@"date"]));
}

static BOOL DW_IsNotificationView(UIView *view) {
    if (!view) return NO;
    NSString *lower = NSStringFromClass(view.class).lowercaseString;
    return ([lower containsString:@"ncnotification"] ||
            [lower containsString:@"notificationlist"] ||
            [lower containsString:@"notificationcollection"] ||
            [lower containsString:@"notificationstack"] ||
            [lower containsString:@"bulletinlist"]);
}

static UIView *DW_FindFirstView(UIView *root, BOOL (*matcher)(UIView *)) {
    if (!root) return nil;
    if (matcher(root)) return root;
    for (UIView *sub in root.subviews) {
        UIView *found = DW_FindFirstView(sub, matcher);
        if (found) return found;
    }
    return nil;
}

static UIView *DW_FindClockView(UIView *root) {
    return DW_FindFirstView(root, DW_IsClockView);
}

static UIView *DW_FindNotificationView(UIView *root) {
    return DW_FindFirstView(root, DW_IsNotificationView);
}

// Return the direct child of root that contains descendant.
static UIView *DW_ImmediateChild(UIView *descendant, UIView *root) {
    if (!descendant || !root) return nil;
    UIView *v = descendant;
    while (v && v.superview && v.superview != root) {
        v = v.superview;
    }
    return (v && v.superview == root) ? v : nil;
}

@interface DWManager : NSObject
@property (nonatomic, strong) UIView *hostView;
@property (nonatomic, strong) UIImageView *cutoutView;
@property (nonatomic, weak) UIView *dashboardView;
@property (nonatomic) BOOL reattachScheduled;
+ (instancetype)sharedInstance;
- (void)setup;
- (void)reloadImage;
- (void)setLocked:(BOOL)locked;
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

- (void)updateGeometryForDashboard:(UIView *)dashboard {
    if (!dashboard || !self.hostView || !self.cutoutView) return;

    CGSize size = dashboard.bounds.size;
    if (size.width <= 1.0 || size.height <= 1.0) return;

    self.hostView.frame = dashboard.bounds;
    self.hostView.bounds = dashboard.bounds;
    self.hostView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    BOOL enabled = YES;
    CGPoint center = CGPointMake(0.5, 0.5);
    CGFloat scale = 1.0;
    DW_LoadMetadata(&enabled, &center, &scale);

    self.cutoutView.bounds = (CGRect){ CGPointZero, size };
    self.cutoutView.center = CGPointMake(size.width * center.x, size.height * center.y);
    self.cutoutView.transform = CGAffineTransformMakeScale(scale, scale);
}

// Keep notifications above the depth overlay while keeping the overlay above the clock.
// We attach to the dashboard root so the overlay is not clipped by the clock's own container.
- (void)reorderWithinDashboard:(UIView *)dashboard {
    if (!dashboard || !self.hostView) return;

    UIView *clock = DW_FindClockView(dashboard);
    UIView *notification = DW_FindNotificationView(dashboard);
    UIView *clockTop = DW_ImmediateChild(clock, dashboard);
    UIView *notificationTop = DW_ImmediateChild(notification, dashboard);

    if (self.hostView.superview != dashboard) {
        [self.hostView removeFromSuperview];
        [dashboard addSubview:self.hostView];
    }

    if (clockTop && notificationTop && clockTop != notificationTop) {
        // Put the overlay above the clock branch, then below the notification branch.
        NSInteger ci = [dashboard.subviews indexOfObject:clockTop];
        NSInteger ni = [dashboard.subviews indexOfObject:notificationTop];
        if (ci != NSNotFound && ni != NSNotFound) {
            [dashboard insertSubview:self.hostView aboveSubview:clockTop];
            // Re-evaluate after the first insert; now force it below notifications.
            [dashboard insertSubview:self.hostView belowSubview:notificationTop];
            return;
        }
    }

    if (notificationTop) {
        [dashboard insertSubview:self.hostView belowSubview:notificationTop];
        return;
    }

    if (clockTop) {
        [dashboard insertSubview:self.hostView aboveSubview:clockTop];
        return;
    }

    // Final fallback: show the overlay at the back of dashboard if private class names differ.
    // It is still visible rather than waiting forever for clock discovery.
    [dashboard insertSubview:self.hostView atIndex:0];
}

- (void)attachToDashboardView:(UIView *)dashboard {
    if (!dashboard) return;
    [self setup];
    self.dashboardView = dashboard;

    [self updateGeometryForDashboard:dashboard];
    [self reorderWithinDashboard:dashboard];

    UIImage *image = DW_LoadCutoutImage();
    BOOL enabled = YES;
    DW_LoadMetadata(&enabled, NULL, NULL);
    self.cutoutView.image = enabled ? image : nil;
    self.hostView.hidden = !(enabled && image && dashboard.window);

    UIView *clock = DW_FindClockView(dashboard);
    UIView *notification = DW_FindNotificationView(dashboard);
    DW_Log([NSString stringWithFormat:@"attach dashboard=%@ window=%@ image=%@ clock=%@ notification=%@ hostIndex=%ld", 
            NSStringFromClass(dashboard.class), dashboard.window ? @"YES" : @"NO",
            image ? @"YES" : @"NO",
            clock ? NSStringFromClass(clock.class) : @"<none>",
            notification ? NSStringFromClass(notification.class) : @"<none>",
            (long)[dashboard.subviews indexOfObject:self.hostView]]);
}

- (void)reloadImage {
    [self setup];
    BOOL enabled = YES;
    CGPoint center = CGPointMake(0.5, 0.5);
    CGFloat scale = 1.0;
    DW_LoadMetadata(&enabled, &center, &scale);
    UIImage *image = DW_LoadCutoutImage();
    self.cutoutView.image = enabled ? image : nil;

    UIView *dashboard = self.dashboardView;
    if (dashboard) {
        [self updateGeometryForDashboard:dashboard];
        [self reorderWithinDashboard:dashboard];
        self.hostView.hidden = !(enabled && image && dashboard.window);
    }
}

- (void)setLocked:(BOOL)locked {
    [self setup];
    if (!locked) {
        self.hostView.hidden = YES;
        DW_Log(@"setLocked=NO -> hide");
        return;
    }
    DW_Log(@"setLocked=YES -> attach retries without lock-state gate");
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

            UIView *dashboard = self.dashboardView;
            if (!dashboard || !dashboard.window) {
                Class dashboardClass = NSClassFromString(@"SBDashBoardViewController");
                Class dashboardViewClass = NSClassFromString(@"SBDashBoardView");
                Class legacyClass = NSClassFromString(@"SBLockScreenViewController");
                for (UIWindow *window in UIApplication.sharedApplication.windows) {
                    UIViewController *vc = window.rootViewController;
                    if (dashboardClass && [vc isKindOfClass:dashboardClass]) {
                        dashboard = vc.view;
                        break;
                    }
                    if (legacyClass && [vc isKindOfClass:legacyClass]) {
                        dashboard = vc.view;
                        break;
                    }
                    if (dashboardViewClass && [window isKindOfClass:dashboardViewClass]) {
                        dashboard = (UIView *)window;
                        break;
                    }
                }
            }

            if (dashboard && dashboard.window) {
                [self attachToDashboardView:dashboard];
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
        UIView *dashboard = self.dashboardView;
        if (dashboard && dashboard.window) {
            [self attachToDashboardView:dashboard];
        }
    });
}

@end

static void DW_SetLockedOnMainThread(BOOL locked) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[DWManager sharedInstance] setLocked:locked];
    });
}

static void DW_LockStateChanged(CFNotificationCenterRef center, void *observer,
                                CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    DW_Log(@"darwin lockstate notification");
    // The dashboard hooks are authoritative. This hint only schedules a retry.
    if (DW_IsUILocked()) DW_SetLockedOnMainThread(YES);
}

static void DW_ReloadRequested(CFNotificationCenterRef center, void *observer,
                               CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[DWManager sharedInstance] reloadImage];
        [[DWManager sharedInstance] scheduleAttachRetries];
    });
}

%hook SBDashBoardViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    UIViewController *vc = (UIViewController *)self;
    [[DWManager sharedInstance] attachToDashboardView:vc.view];
    [[DWManager sharedInstance] scheduleAttachRetries];
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    UIViewController *vc = (UIViewController *)self;
    [[DWManager sharedInstance] attachToDashboardView:vc.view];
    [[DWManager sharedInstance] scheduleAttachRetries];
}

%end

%hook SBDashBoardView

- (void)didMoveToWindow {
    %orig;
    UIView *dashboardView = (UIView *)self;
    if (dashboardView.window) {
        [[DWManager sharedInstance] attachToDashboardView:dashboardView];
        [[DWManager sharedInstance] scheduleAttachRetries];
    }
}

- (void)layoutSubviews {
    %orig;
    [[DWManager sharedInstance] scheduleReattach];
}

%end

%hook SBLockScreenViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    UIViewController *vc = (UIViewController *)self;
    [[DWManager sharedInstance] attachToDashboardView:vc.view];
    [[DWManager sharedInstance] scheduleAttachRetries];
}

%end

%hook NCNotificationListCollectionView

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
    Class dashboardClass = NSClassFromString(@"SBDashBoardViewController");
    Class legacyClass = NSClassFromString(@"SBLockScreenViewController");
    if ((dashboardClass && [newDisplay isKindOfClass:dashboardClass]) ||
        (legacyClass && [newDisplay isKindOfClass:legacyClass])) {
        UIViewController *vc = (UIViewController *)newDisplay;
        [[DWManager sharedInstance] attachToDashboardView:vc.view];
        [[DWManager sharedInstance] scheduleAttachRetries];
    }
}

%end
