# DepthWallpaper 1.5.5

Fixes cutout disappearing after wake/boot and notification z-order by attaching from `SBFLockScreenDateView` and using the lowest common ancestor with notification views. No high-level UIWindow is used.

Diagnostics are written to `/var/mobile/Library/Logs/DepthWallpaperTweak.log`.
