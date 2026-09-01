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
#import "DWShared.h"

#pragma mark - Doc metadata + anh cutout

static UIImage *DW_LoadCutoutImage(void) {
    return [UIImage imageWithContentsOfFile:DWCutoutImagePath];
}

static void DW_LoadMetadata(BOOL *outEnabled) {
    NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:DWMetadataPath];
    *outEnabled = meta[DWMetaKeyEnabled] ? [meta[DWMetaKeyEnabled] boolValue] : YES;
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

@implementation DWManager

+ (instancetype)sharedInstance {
    static DWManager *inst = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        inst = [DWManager new];
    });
    return inst;
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
    DW_LoadMetadata(&enabled);
    UIImage *img = DW_LoadCutoutImage();

    if (!img || !enabled || !self.window) {
        self.cutoutView.image = nil;
        return;
    }

    // Manual-depth mode: the PNG already has the exact intended position.
    // Do not apply independent Y offset or scale. Keep one full-screen frame.
    self.cutoutView.image = img;
    self.cutoutView.frame = self.window.bounds;
    self.cutoutView.contentMode = UIViewContentModeScaleAspectFill;
    self.cutoutView.clipsToBounds = YES;
    self.cutoutView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
}

- (void)setLocked:(BOOL)locked {
    self.window.hidden = !locked;
    if (locked) [self reloadImage]; // dam bao luon dung ban moi nhat khi hien ra
}

@end

#pragma mark - Phat hien khoa/mo khoa + nhan thong bao reload tu app

static void DW_LockStateChanged(CFNotificationCenterRef c, void *o, CFStringRef name, const void *obj, CFDictionaryRef info) {
    // Cach don gian, it rui ro de biet may dang khoa hay khong: du lieu duoc bao
    // ve (Protected Data) CHI san sang khi may dang o trang thai MO KHOA. Day la
    // API CONG KHAI (khong phai private), dang tin cay hon nhieu so voi viec doan
    // noi dung cua Darwin notification.
    BOOL locked = !UIApplication.sharedApplication.isProtectedDataAvailable;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[DWManager sharedInstance] setLocked:locked];
    });
}

static void DW_ReloadRequested(CFNotificationCenterRef c, void *o, CFStringRef name, const void *obj, CFDictionaryRef info) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[DWManager sharedInstance] reloadImage];
    });
}

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    [[DWManager sharedInstance] setup];

    // Lang nghe ca 2 su kien lien quan bao ve du lieu (khoa/mo khoa deu di qua day).
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        DW_LockStateChanged, CFSTR("com.apple.springboard.lockstate"), NULL,
        CFNotificationSuspensionBehaviorCoalesce);

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        DW_ReloadRequested, DWReloadNotification, NULL,
        CFNotificationSuspensionBehaviorCoalesce);

    // Xac dinh trang thai KHOA/MO ban dau ngay luc khoi dong, phong khi
    // notification chua kip bắn lan nao.
    [[DWManager sharedInstance] setLocked:!UIApplication.sharedApplication.isProtectedDataAvailable];
}
%end
