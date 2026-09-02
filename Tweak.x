/*
 * DepthWallpaper 1.5.1
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

static UIView *DW_FindCommonAncestor(UIView *a, UIView *b, UIView *root) {
    if (!a || !b) return root;
    NSMutableSet *ancestors = [NSMutableSet set];
    for (UIView *v = a; v; v = v.superview) {
        [ancestors addObject:v];
        if (v == root) break;
    }
    for (UIView *v = b; v; v = v.superview) {
        if ([ancestors containsObject:v]) return v;
        if (v == root) break;
    }
    return root;
}

static UIView *DW_ImmediateChild(UIView *descendant, UIView *ancestor) {
    if (!descendant || !ancestor) return nil;
    UIView *v = descendant;
    while (v.superview && v.superview != ancestor) v = v.superview;
    return (v.superview == ancestor) ? v : nil;
}

@interface DWManager : NSObject
@property (nonatomic, strong) UIView *hostView;
@property (nonatomic, strong) UIImageView *cutoutView;
@property (nonatomic, weak) UIView *dashboardView;
@property (nonatomic, weak) UIView *layoutContainer;
@property (nonatomic) BOOL attachRetryScheduled;
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

- (void)placeHost:(UIView *)container clock:(UIView *)clock notification:(UIView *)notification {
    UIView *clockChild = DW_ImmediateChild(clock, container);
    UIView *notificationChild = DW_ImmediateChild(notification, container);

    if (self.hostView.superview != container) {
        [self.hostView removeFromSuperview];
        [container addSubview:self.hostView];
    }

    NSInteger clockIndex = clockChild ? [container.subviews indexOfObject:clockChild] : NSNotFound;
    NSInteger notificationIndex = notificationChild ? [container.subviews indexOfObject:notificationChild] : NSNotFound;

    if (clockChild && notificationChild && clockChild != notificationChild) {
        if (clockIndex != NSNotFound && notificationIndex != NSNotFound && clockIndex < notificationIndex) {
            [container insertSubview:self.hostView aboveSubview:clockChild];
            return;
        }
        if (notificationIndex != NSNotFound) {
            [container insertSubview:self.hostView belowSubview:notificationChild];
            return;
        }
    }

    if (clockChild) [container insertSubview:self.hostView aboveSubview:clockChild];
    else [container addSubview:self.hostView];
}

- (void)attachToDashboardView:(UIView *)dashboard {
    if (!dashboard) return;
    [self setup];
    self.dashboardView = dashboard;

    UIView *clock = DW_FindClockView(dashboard);
    UIView *notification = DW_FindNotificationView(dashboard);
    if (!clock) {
        DW_Log([NSString stringWithFormat:@"attach deferred: clock not found dashboard=%@", NSStringFromClass(dashboard.class)]);
        return;
    }

    UIView *container = notification ? DW_FindCommonAncestor(clock, notification, dashboard) : dashboard;
    if (!container) container = dashboard;
    self.layoutContainer = container;

    [self placeHost:container clock:clock notification:notification];

    CGRect dashboardFrame = [container convertRect:dashboard.bounds fromView:dashboard];
    self.hostView.frame = dashboardFrame;
    self.hostView.bounds = (CGRect){CGPointZero, dashboard.bounds.size};
    self.hostView.autoresizingMask = UIViewAutoresizingNone;
    self.hostView.clipsToBounds = NO;

    [self reloadImage];
    self.hostView.hidden = (self.cutoutView.image == nil);

    UIView *clockChild = DW_ImmediateChild(clock, container);
    UIView *notificationChild = DW_ImmediateChild(notification, container);
    NSInteger hostIndex = [container.subviews indexOfObject:self.hostView];
    NSInteger clockIndex = clockChild ? [container.subviews indexOfObject:clockChild] : NSNotFound;
    NSInteger notificationIndex = notificationChild ? [container.subviews indexOfObject:notificationChild] : NSNotFound;
    DW_Log([NSString stringWithFormat:@"attached dashboard=%@ container=%@ clock=%@ notification=%@ idx(host=%ld clock=%ld notification=%ld)",
            NSStringFromClass(dashboard.class), NSStringFromClass(container.class),
            NSStringFromClass(clock.class), notification ? NSStringFromClass(notification.class) : @"<none>",
            (long)hostIndex, (long)clockIndex, (long)notificationIndex]);
}

- (void)reloadImage {
    BOOL enabled = YES;
    CGPoint center = CGPointMake(0.5, 0.5);
    CGFloat scale = 1.0;
    DW_LoadMetadata(&enabled, &center, &scale);
    UIImage *image = DW_LoadCutoutImage();
    self.cutoutView.image = enabled ? image : nil;

    UIView *dashboard = self.dashboardView;
    if (!dashboard || !self.hostView) return;

    CGSize size = dashboard.bounds.size;
    self.cutoutView.bounds = (CGRect){CGPointZero, size};
    self.cutoutView.center = CGPointMake(size.width * center.x, size.height * center.y);
    self.cutoutView.transform = CGAffineTransformMakeScale(scale, scale);
    self.cutoutView.contentMode = UIViewContentModeScaleAspectFit;
}

- (void)setLocked:(BOOL)locked {
    [self setup];
    if (!locked) {
        self.hostView.hidden = YES;
        DW_Log(@"setLocked=NO -> hide");
        return;
    }
    self.hostView.hidden = YES;
    DW_Log(@"setLocked=YES -> attach retries");
    [self scheduleAttachRetries];
}

- (void)scheduleAttachRetries {
    [self setup];
    if (self.attachRetryScheduled) return;
    self.attachRetryScheduled = YES;

    NSArray<NSNumber *> *delays = @[@0.0, @0.016, @0.04, @0.08, @0.12, @0.20, @0.40, @0.80];
    __weak typeof(self) weakSelf = self;
    for (NSNumber *delay in delays) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;

            UIView *dashboard = self.dashboardView;
            if (!dashboard) {
                Class dashboardClass = NSClassFromString(@"SBDashBoardViewController");
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
                }
            }
            if (dashboard) [self attachToDashboardView:dashboard];
            if (delay == delays.lastObject) self.attachRetryScheduled = NO;
        });
    }
}

- (void)scheduleReattach {
    [self setup];
    if (self.reattachScheduled) return;
    self.reattachScheduled = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self.reattachScheduled = NO;
        UIView *dashboard = self.dashboardView;
        if (dashboard) [self attachToDashboardView:dashboard];
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
    if (self.window) {
        [[DWManager sharedInstance] attachToDashboardView:self];
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
