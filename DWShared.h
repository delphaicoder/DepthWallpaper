// Shared paths/settings for DepthWallpaper app + SpringBoard tweak.
#ifndef DWShared_h
#define DWShared_h

static NSString * const DWSharedDirectory = @"/var/mobile/Library/Application Support/DepthWallpaper";
static NSString * const DWWallpaperImagePath = @"/var/mobile/Library/Application Support/DepthWallpaper/wallpaper.original";
static NSString * const DWCutoutImagePath = @"/var/mobile/Library/Application Support/DepthWallpaper/cutout.png";
static NSString * const DWMetadataPath = @"/var/mobile/Library/Application Support/DepthWallpaper/meta.plist";
static CFStringRef const DWReloadNotification = CFSTR("com.yourname.depthwallpaper/reload");

static NSString * const DWMetaKeyEnabled = @"Enabled";
static NSString * const DWMetaKeyWallpaperWidth = @"WallpaperWidth";
static NSString * const DWMetaKeyWallpaperHeight = @"WallpaperHeight";
static NSString * const DWMetaKeyCutoutWidth = @"CutoutWidth";
static NSString * const DWMetaKeyCutoutHeight = @"CutoutHeight";
static NSString * const DWMetaKeyAspectMatch = @"AspectMatch";

#endif
