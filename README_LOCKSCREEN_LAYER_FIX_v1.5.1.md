# DepthWallpaper 1.5.1

This revision uses `SBDashBoardViewController` / `SBDashBoardView` as the primary iOS 15 Lock Screen path. It places the cutout in the lowest common ancestor of the clock and notification list, above the clock branch but below the notification branch. It no longer creates a high-level UIWindow for the cutout.

Attachment is retried during the first 800 ms of dashboard presentation and is refreshed by dashboard/notification layout hooks. The manual PNG workflow and normalized position/scale remain unchanged.
