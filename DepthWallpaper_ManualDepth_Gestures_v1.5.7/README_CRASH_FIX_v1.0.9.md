# DepthWallpaper v1.0.9 — input scaling fix

The selected photo is always normalized into a scale=1.0 UIKit bitmap using real CGImage pixel dimensions. The Vision input is capped at 512 px on the A8X path, uses CGImage directly, and requests ScaleFit. CIImage creation is delayed until after Vision setup.

This is intended to avoid “failed to scale the input image” on older devices and reduce peak memory.
