ARCHS = arm64 arm64e
TARGET := iphone:clang:14.5:15.0

include $(THEOS)/makefiles/common.mk

# ==== App chon anh + xu ly Vision framework ====
APPLICATION_NAME = DepthWallpaperApp
DepthWallpaperApp_FILES = DepthWallpaperApp/main.m DepthWallpaperApp/AppDelegate.m DepthWallpaperApp/ViewController.m
DepthWallpaperApp_FRAMEWORKS = UIKit Foundation Vision CoreImage CoreGraphics
DepthWallpaperApp_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
DepthWallpaperApp_LDFLAGS = -lc++abi

include $(THEOS_MAKE_PATH)/application.mk

# ==== Tweak SpringBoard hien overlay ====
TWEAK_NAME = DepthWallpaperTweak
DepthWallpaperTweak_FILES = Tweak.x
DepthWallpaperTweak_FRAMEWORKS = UIKit Foundation
DepthWallpaperTweak_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
DepthWallpaperTweak_LDFLAGS = -lc++abi

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"
	install.exec "killall -9 DepthWallpaperApp || true"
