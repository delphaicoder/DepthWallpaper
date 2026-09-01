// DWShared.h — dung chung giua DepthWallpaperApp va Tweak.x, giu 2 ben khop nhau.
#ifndef DWShared_h
#define DWShared_h

// Thu muc dung chung (app ghi, tweak doc) — nam trong sandbox container cua app
// se KHONG doc duoc tu SpringBoard (khac sandbox), nen phai dung 1 thu muc chung
// ben ngoai sandbox ma ca 2 ben deu doc/ghi duoc.
static NSString * const DWSharedDirectory = @"/var/mobile/Library/Application Support/DepthWallpaper";
static NSString * const DWCutoutImagePath = @"/var/mobile/Library/Application Support/DepthWallpaper/cutout.png";
static NSString * const DWMetadataPath    = @"/var/mobile/Library/Application Support/DepthWallpaper/meta.plist";

// Darwin notification — app ban ra sau khi luu xong, bao tweak nap lai anh moi.
static CFStringRef const DWReloadNotification = CFSTR("com.yourname.depthwallpaper/reload");

// Key trong file meta.plist
static NSString * const DWMetaKeyYOffsetRatio = @"YOffsetRatio"; // 0.0-1.0, ti le theo chieu cao man hinh
static NSString * const DWMetaKeyScale        = @"Scale";         // ty le phong to/thu nho overlay
static NSString * const DWMetaKeyEnabled      = @"Enabled";
static NSString * const DWMetaKeyAspectMatch  = @"AspectMatch";
static NSString * const DWMetaKeyManualFullResolution = @"ManualFullResolution";

static NSString * const DWWallpaperImagePath = @"/var/mobile/Library/Application Support/DepthWallpaper/wallpaper.png";
static NSString * const DWMetaKeyWallpaperWidth  = @"WallpaperWidth";
static NSString * const DWMetaKeyWallpaperHeight = @"WallpaperHeight";
static NSString * const DWMetaKeyCutoutWidth    = @"CutoutWidth";
static NSString * const DWMetaKeyCutoutHeight   = @"CutoutHeight";

#endif
