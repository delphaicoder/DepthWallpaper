/*
 * DepthWallpaper — phan SpringBoard. Hien anh cutout (chu the da tach) DE LEN
 * TREN dong ho khoa may, tao ao giac "chieu sau" — khong can biet chinh xac vi
 * tri dong ho that (khong hook/doi cach ve dong ho), chi can xep lop dung cho
 * la du: bat ky phan dong ho nao bi cutout de len se tu nhien bi che di, dung
 * y het cach tinh nang that cua Apple hoat dong (ve ban chat cung la 1 trick
 * xep lop, khong phai "di chuyen" dong ho).
 *
 * ==== DIEM KHONG CHAC CHAN NHAT TRONG TWEAK NAY ====
 * Phat hien luc nao man hinh dang KHOA dung Darwin notification
 * "com.apple.springboard.lockstate" — day la ky thuat kha pho bien trong cong
 * dong jailbreak nhung VAN LA private, khong co tai lieu chinh thuc. Neu
 * notification nay khong bắn dung nhu mong doi tren ban iPadOS cu the cua ban,
 * overlay co the hien/an sai luc — KHONG nguy hiem (chi anh huong tham my),
 * nhung can luu y khi test.
 */

#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>
#import <objc/message.h>
#import "DWShared.h"

#pragma mark - Doc metadata + anh cutout

static UIImage *DW_LoadCutoutImage(void) {
    UIImage *image = [UIImage imageWithContentsOfFile:DWCutoutImagePath];
    return image;
}

static void DW_Log(NSString *message) {
    if (!message) return;
    NSString *path = @"/var/mobile/Library/Logs/DepthWallpaperTweak.log";
    NSString *line = [NSString stringWithFormat:@"%@\n", message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) {
        [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        handle = [NSFileHandle fileHandleForWritingAtPath:path];
    }
    [handle seekToEndOfFile];
    [handle writeData:data];
    [handle closeFile];
}

static NSDictionary *DW_ReadMetadataDictionary(void) {
    return [NSDictionary dictionaryWithContentsOfFile:DWMetadataPath] ?: @{};
}

static void DW_LoadMetadataValues(BOOL *outEnabled, CGPoint *outCenter, CGFloat *outScale) {
    NSDictionary *meta = DW_ReadMetadataDictionary();
    *outEnabled = meta[DWMetaKeyEnabled] ? [meta[DWMetaKeyEnabled] boolValue] : YES;
    CGFloat x = meta[DWMetaKeyCutoutCenterX] ? [meta[DWMetaKeyCutoutCenterX] doubleValue] : 0.5;
    CGFloat y = meta[DWMetaKeyCutoutCenterY] ? [meta[DWMetaKeyCutoutCenterY] doubleValue] : 0.5;
    CGFloat scale = meta[DWMetaKeyCutoutScale] ? [meta[DWMetaKeyCutoutScale] doubleValue] : 1.0;
    *outCenter = CGPointMake(MIN(1.5, MAX(-0.5, x)), MIN(1.5, MAX(-0.5, y)));
    *outScale = MIN(4.0, MAX(0.25, scale));
}

#pragma mark - DWOverlayWindow

@interface DWOverlayWindow : UIWindow
@end
@implementation DWOverlayWindow
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return NO; // trang tri thuan tuy, khong bao gio chan tuong tac mo khoa
}
@end

#pragma mark - DWManager

@interface DWManager : NSObject
@property (nonatomic, strong) DWOverlayWindow *window;
@property (nonatomic, strong) UIImageView *cutoutView;
+ (instancetype)sharedInstance;
- (void)setup;
- (void)reloadImage;
- (void)setLocked:(BOOL)locked;
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
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]]) { scene = (UIWindowScene *)s; break; }
    }
    DWOverlayWindow *win = scene
        ? [[DWOverlayWindow alloc] initWithWindowScene:scene]
        : [[DWOverlayWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];

    // Muc cua so cao hon lop dong ho khoa may thong thuong — day chinh la toan bo
    // "bi quyet" tao ao giac chieu sau, khong can gi khac.
    win.windowLevel = UIWindowLevelStatusBar + 1500;
    win.backgroundColor = [UIColor clearColor];
    win.rootViewController = [UIViewController new];
    win.rootViewController.view.backgroundColor = [UIColor clearColor];
    win.hidden = YES; // an mac dinh, chi hien khi khoa may (xem setLocked:)

    UIImageView *iv = [[UIImageView alloc] init];
    iv.contentMode = UIViewContentModeScaleAspectFill;
    iv.userInteractionEnabled = NO;
    [win.rootViewController.view addSubview:iv];

    self.window = win;
    self.cutoutView = iv;

    [self reloadImage];

    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(reloadImage)
        name:UIApplicationDidChangeStatusBarOrientationNotification object:nil];
}

- (void)reloadImage {
    BOOL enabled = YES;
    CGPoint centerRatio = CGPointMake(0.5, 0.5);
    CGFloat scale = 1.0;
    DW_LoadMetadataValues(&enabled, &centerRatio, &scale);
    UIImage *img = DW_LoadCutoutImage();
    DW_Log([NSString stringWithFormat:@"reloadImage enabled=%@ image=%@ path=%@", enabled ? @"YES" : @"NO", img ? @"YES" : @"NO", DWCutoutImagePath]);

    if (!img || !enabled || !self.window) {
        self.cutoutView.image = nil;
        return;
    }

    UIView *root = self.window.rootViewController.view;
    self.cutoutView.image = img;
    self.cutoutView.bounds = root.bounds;
    self.cutoutView.center = CGPointMake(CGRectGetWidth(root.bounds) * centerRatio.x,
                                         CGRectGetHeight(root.bounds) * centerRatio.y);
    self.cutoutView.transform = CGAffineTransformMakeScale(scale, scale);
    self.cutoutView.contentMode = UIViewContentModeScaleAspectFit;
    self.cutoutView.clipsToBounds = NO;
    self.cutoutView.autoresizingMask = UIViewAutoresizingNone;
}

- (void)setLocked:(BOOL)locked {
    DW_Log([NSString stringWithFormat:@"setLocked=%@", locked ? @"YES" : @"NO"]);
    if (!self.window) return;
    if (locked) {
        self.window.frame = UIScreen.mainScreen.bounds;
        [self.window.rootViewController.view setNeedsLayout];
        [self reloadImage];
        self.window.hidden = (self.cutoutView.image == nil);
    } else {
        self.window.hidden = YES;
    }
}

@end

#pragma mark - Phat hien khoa/mo khoa + nhan thong bao reload tu app

static void DW_SetLockedOnMainThread(BOOL locked) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[DWManager sharedInstance] setLocked:locked];
    });
}

static BOOL DW_IsUILocked(void) {
    Class cls = NSClassFromString(@"SBLockScreenManager");
    if (!cls) return NO;
    id manager = nil;
    SEL sharedSel = NSSelectorFromString(@"sharedInstance");
    SEL lockedSel = NSSelectorFromString(@"isUILocked");
    if ([cls respondsToSelector:sharedSel]) {
        id (*sendShared)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
        manager = sendShared(cls, sharedSel);
    }
    if (!manager || ![manager respondsToSelector:lockedSel]) return NO;
    BOOL (*sendLocked)(id, SEL) = (BOOL (*)(id, SEL))objc_msgSend;
    return sendLocked(manager, lockedSel);
}

static void DW_LockStateChanged(CFNotificationCenterRef c, void *o, CFStringRef name, const void *obj, CFDictionaryRef info) {
    // Fallback notification. Prefer SBLockScreenManager's isUILocked below.
    DW_SetLockedOnMainThread(DW_IsUILocked());
}

static void DW_ReloadRequested(CFNotificationCenterRef c, void *o, CFStringRef name, const void *obj, CFDictionaryRef info) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[DWManager sharedInstance] reloadImage];
    });
}

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

    // Lang nghe lock/unlock notification nhu fallback; lock state chinh duoc lay tu SBLockScreenManager.
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        DW_LockStateChanged, CFSTR("com.apple.springboard.lockstate"), NULL,
        CFNotificationSuspensionBehaviorCoalesce);

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        DW_ReloadRequested, DWReloadNotification, NULL,
        CFNotificationSuspensionBehaviorCoalesce);

    // Xac dinh trang thai KHOA/MO ban dau ngay luc khoi dong, phong khi
    // notification chua kip bắn lan nao.
    [[DWManager sharedInstance] setLocked:DW_IsUILocked()];
}
%end
