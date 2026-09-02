# DepthWallpaper 1.5.6

Build fix for forward-declared SpringBoard view classes: cast `SBFLockScreenDateView` and `NCNotificationListCollectionView` to `UIView *` before accessing `window` or passing them to methods expecting UIView.
