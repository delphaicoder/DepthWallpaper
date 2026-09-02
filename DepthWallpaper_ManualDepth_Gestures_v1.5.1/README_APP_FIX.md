# DepthWallpaper app visibility / black-screen fix v1.0.2

- Rootless package scheme is enabled in Makefile.
- App architecture is arm64 only.
- iOS/iPadOS target: 14.0+.
- App install path is explicitly /Applications for Theos packaging (rootless maps it under /var/jb).
- Scene manifest uses Objective-C class name `SceneDelegate` instead of a Swift-style module-qualified name.
- Package includes a rootless `postinst` that calls `uicache -p` on the installed app, with fallback to `uicache -a`, then refreshes SpringBoard.

Build:
```sh
make clean
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
```
