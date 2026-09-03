# DepthWallpaper 1.5.3 — Lock Screen attachment/layering fix

- Root-level dashboard overlay prevents clipping/disappearing inside clock container.
- Overlay is inserted above the detected clock branch but below the detected notification branch.
- Attachment no longer waits for clock discovery; it has a visible fallback even if private class names differ.
- Multiple attach retries run after Lock Screen presentation.
- Notification layout triggers a reattach.
- No render loop or Metal/Vision processing is added.
