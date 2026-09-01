# DepthWallpaper 1.1.0

Fix for Vision error: `failed to scale the input image`.

Changes:
- Canonicalizes selected images to an 8-bit RGBA bitmap using `CGBitmapContext`.
- Feeds Vision a CGImage with explicit `kCGImagePropertyOrientationUp`.
- Resizes using pixel dimensions rather than UIImage points.
- Caps Vision input at 512 px on the existing A8X fallback path.
- Releases the temporary canonical CGImage after Vision/compositing.

This keeps the A8X path on saliency instead of person segmentation, avoiding the earlier CoreImage GL crash.
