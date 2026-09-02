# DepthWallpaper - black screen launch fix

This patch adds a normal iOS 13+ scene lifecycle (`SceneDelegate`) and a legacy AppDelegate fallback.
It also targets iOS 14.0+ and includes SceneManifest metadata so the app gets a real UIWindow on iOS 14-16.

Build:
  make clean
  make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
