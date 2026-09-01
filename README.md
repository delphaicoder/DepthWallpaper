# DepthWallpaper 1.2.2

Landscape-first, full-resolution manual depth wallpaper workflow for iOS/iPadOS 14-16 rootless arm64.

## Workflow
1. Select the original wallpaper.
2. Select a transparent PNG cutout prepared by the user.
3. Both images must have the exact same pixel width/height.
4. The app stores the original wallpaper data and cutout PNG without resizing the cutout.
5. SpringBoard displays the cutout as a full-screen transparent overlay only while the device is locked.

## Performance
- No Vision.
- No person segmentation.
- No saliency.
- No Metal shaders.
- No render loop.
- Static UIImageView overlay.
- Reload happens only on lock/unlock, orientation changes, or the app's explicit Darwin notification.

## Build
Theos rootless, arm64, minimum iOS 14.0.
