# DepthWallpaper 1.0.4 install fix

This build does NOT restart SpringBoard during dpkg setup.
The previous build called `sbreload` from `postinst`, which could respring the device while Sileo displayed Setting Up.

After installation, if the app icon does not appear immediately, manually run `uicache -p /var/jb/Applications/DepthWallpaper.app` or perform one respring after installation.
