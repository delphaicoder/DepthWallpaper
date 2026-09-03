# DepthWallpaper v1.5.7 Feature Update Plan

## Preserved core behavior

The existing manual depth cutout rendering pipeline is unchanged. The cutout overlay system, positioning logic, scaling behavior, and SpringBoard layer handling are intentionally not modified in this update.

## New features

### Saved Depth Presets

Users can save up to 20 wallpaper configurations.

Each preset stores:
- Original lock screen wallpaper reference
- Cutout PNG
- Cutout position
- Cutout scale
- Preview settings

This allows users to switch depth effects without repeating alignment work.

### Options Panel

A new Options section is planned to contain:
- Enable/disable depth overlay
- Export diagnostic logs
- Clear cached previews
- View current active preset
- Debug information

### Improved Logging

DepthWallpaper diagnostic logs are accessible from the Options panel.

The app can export:
- App processing logs
- Tweak attachment logs
- Lock screen state logs

Export format:
`DepthWallpaper_Log.txt`

### Lock Screen Widgets (Experimental)

An experimental widget layer is planned, inspired by modern iOS Lock Screen widgets.

Possible customizable widgets:
- Battery percentage
- Weather information
- Custom text
- System status information

Widgets will have:
- Enable/disable switch
- Position adjustment
- Style customization

The widget layer is designed as a separate component and does not modify the depth cutout renderer.

## Development notes

This version focuses on adding usability features while keeping the stable v1.5.6 depth engine untouched.