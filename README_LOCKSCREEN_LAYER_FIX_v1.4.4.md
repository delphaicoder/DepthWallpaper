# DepthWallpaper 1.4.4

## Lock Screen layer fix

- The cutout is no longer shown in a separate ultra-high `UIWindow`.
- The tweak attaches the cutout to the Lock Screen view hierarchy and places it immediately above the clock/date ancestor when that view can be found.
- Notification UI can therefore remain above the cutout instead of being covered by a `UIWindowLevelStatusBar + 1500` overlay.
- The tweak retries attachment after lock, with short delayed attempts, because the Lock Screen hierarchy may not exist yet immediately after boot.
- `SBLockScreenViewController` hooks `viewDidAppear:` and `viewDidLayoutSubviews` to attach/re-attach after the hierarchy is ready.
- Debug output remains in `/var/mobile/Library/Logs/DepthWallpaperTweak.log`.


## v1.4.9
The cutout host is kept as a sibling of the entire clock-containing Lock Screen branch and reinserted immediately above that branch after layout. This avoids clipping from the small clock container and avoids the high-level UIWindow that previously covered notifications. No notification branch reordering is performed.
