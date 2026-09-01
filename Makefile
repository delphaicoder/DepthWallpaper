ARCHS = arm64
TARGET := iphone:clang:14.5:14.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

# ==== App chon anh + xu ly Vision framework ====
APPLICATION_NAME = DepthWallpaperApp
DepthWallpaperApp_FILES = DepthWallpaperApp/main.m DepthWallpaperApp/AppDelegate.m DepthWallpaperApp/SceneDelegate.m DepthWallpaperApp/ViewController.m
DepthWallpaperApp_FRAMEWORKS = UIKit Foundation Vision CoreImage CoreGraphics
DepthWallpaperApp_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
DepthWallpaperApp_INSTALL_PATH = /Applications
DepthWallpaperApp_BUNDLE_NAME = DepthWallpaper
DepthWallpaperApp_INFO_PLIST = DepthWallpaperApp/Resources/Info.plist
DepthWallpaperApp_RESOURCE_DIRS = DepthWallpaperApp/Resources
DepthWallpaperApp_LDFLAGS = -lc++abi

include $(THEOS_MAKE_PATH)/application.mk

# ==== Tweak SpringBoard hien overlay ====
TWEAK_NAME = DepthWallpaperTweak
DepthWallpaperTweak_FILES = Tweak.x
DepthWallpaperTweak_FRAMEWORKS = UIKit Foundation
DepthWallpaperTweak_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
DepthWallpaperTweak_LDFLAGS = -lc++abi

include $(THEOS_MAKE_PATH)/tweak.mk

# No automatic respring: install the package first, then respring manually if needed.
