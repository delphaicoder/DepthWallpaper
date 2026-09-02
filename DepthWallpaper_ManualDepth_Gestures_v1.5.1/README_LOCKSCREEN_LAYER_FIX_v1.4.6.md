# DepthWallpaper v1.4.7 — persistent Lock Screen attachment

- The cutout host is inserted into the Lock Screen clock's own parent container instead of a standalone high-level window.
- Because the cutout lives in the Lock Screen hierarchy, it follows the same Lock Screen presentation/layout instead of appearing only after notification interaction.
- Notification/banner branches are raised above the cutout when identifiable by class name, so the cutout does not sit above notification content.
- When a notification panel slides over the clock, its own view hierarchy can naturally occlude/reveal the cutout progressively rather than the cutout drawing on top of it.
- Attach is attempted early at viewDidLoad/viewWillAppear/viewDidAppear and during layout, plus retries at 0, 16, 40, 80, 120, 200 and 400 ms.
- Scheduling no longer aborts just because isUILocked is briefly false during the lock transition.
- Existing manual PNG, drag, pinch zoom and logging behavior is preserved.
