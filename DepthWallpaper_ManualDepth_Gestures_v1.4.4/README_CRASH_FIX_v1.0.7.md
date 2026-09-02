# DepthWallpaper 1.0.7 - photo processing crash fix

- Uses a smaller 768px processing image to reduce peak memory on A8X.
- Person segmentation is optional and wrapped in `@try/@catch` so unsupported Vision runtime paths fall back instead of terminating the app.
- Uses Vision's FAST quality level for lower CPU/RAM use.
- Adds an autorelease pool around background image processing.
- Existing portrait/landscape UI and rootless packaging are preserved.


## v1.0.8
A8X/iPad5,3-5,4 now skips person segmentation entirely because native EXC_BAD_ACCESS cannot be caught with @try/@catch.
