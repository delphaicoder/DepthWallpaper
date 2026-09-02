# DepthWallpaper 1.5.0 — Lock Screen attachment / notification layering fix

- The cutout is attached inside the Lock Screen clock branch instead of a high-level UIWindow.
- The overlay stays above the clock but below top-level notification/banner branches.
- Visibility during the initial lock transition no longer depends on `SBLockScreenManager isUILocked`; the Lock Screen controller hook is used as the display signal.
- The overlay host keeps a root-sized coordinate space so the editor position/scale is preserved.
- Retry/attach hooks remain enabled to handle SpringBoard rebuilding the Lock Screen hierarchy.
