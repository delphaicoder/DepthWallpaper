# DepthWallpaper v1.0.8 — A8X crash fix

The crash log on iPad5,4 / iOS 15.8.8 shows SIGSEGV (EXC_BAD_ACCESS) inside CoreImage while Vision initializes VNPersonSegmentationGenerator.

This build skips VNGeneratePersonSegmentationRequest on iPad5,3 and iPad5,4 and falls back to saliency. Objective-C @try/@catch cannot safely catch this native SIGSEGV, so the risky request is not created on A8X at all.
