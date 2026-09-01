ARCHS = arm64
TARGET := iphone:clang:14.5:15.0

# Rootless build for Sileo (iOS/iPadOS 15+).
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

# ==== Standalone app: picker + Vision processing ====
APPLICATION_NAME = DepthWallpaperApp
DepthWallpaperApp_FILES = DepthWallpaperApp/main.m DepthWallpaperApp/AppDelegate.m DepthWallpaperApp/ViewController.m
DepthWallpaperApp_FRAMEWORKS = UIKit Foundation Vision CoreImage CoreGraphics
DepthWallpaperApp_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
DepthWallpaperApp_LDFLAGS = -lc++abi
DepthWallpaperApp_INSTALL_PATH = /Applications/DepthWallpaper.app
DepthWallpaperApp_BUNDLE_RESOURCE_DIRS = DepthWallpaperApp/Resources

# ==== SpringBoard tweak ====
TWEAK_NAME = DepthWallpaperTweak
DepthWallpaperTweak_FILES = Tweak.x
DepthWallpaperTweak_FRAMEWORKS = UIKit Foundation
DepthWallpaperTweak_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
DepthWallpaperTweak_LDFLAGS = -lc++abi

include $(THEOS_MAKE_PATH)/application.mk
include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard || true"
