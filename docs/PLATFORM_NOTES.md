# Platform notes and limitations

Nothing here has been tested on a device. `dart tool/setup.dart` applies the permission patches below automatically.

## All platforms
- Downloads run **only while the app is open**. There is no background service yet.
- HTTP and HTTPS only. FTP and SFTP are rejected with a clear message.

## Android
- Manifest needs `<uses-permission android:name="android.permission.INTERNET"/>` (the release manifest does not get it automatically).
- Default folder is the app-specific external directory, which needs no storage permission. Saving to the public Downloads folder needs Storage Access Framework or MediaStore work.
- Proper background downloading requires a foreground service with a persistent notification (`dataSync` type on Android 14+), the `POST_NOTIFICATIONS` permission on Android 13+, and network callbacks. Not implemented.
- Opening files uses `open_filex`, which depends on a FileProvider; it is configured by the package but test on real devices.

## iOS
- Files are saved in the app Documents folder. `setup.dart` adds `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` so they appear in the Files app.
- iOS suspends apps shortly after they leave the foreground. True background transfers need a background `URLSession` via a native plugin; ZapDL's Dart HTTP engine will pause when suspended. Not implemented.
- The clipboard auto-suggestion is disabled on iOS because reading the clipboard triggers a system paste prompt; use the Paste button in the Add dialog.
- Running iOS builds requires a Mac with Xcode.

## macOS
- The App Sandbox needs `com.apple.security.network.client` and file entitlements (`user-selected.read-write`, `downloads.read-write`). `setup.dart` adds them to Debug and Release entitlements. Building requires a Mac.

## Windows / Linux
- "Open containing folder" uses `explorer.exe /select`, and `xdg-open` on the parent folder for Linux.
- Linux needs the standard Flutter Linux build dependencies (GTK 3, clang, cmake, ninja, pkg-config).
- No tray icon, minimize-to-tray, autostart or drag-and-drop yet.

## Security notes
- File names from servers and users are sanitized to a single path component; Windows reserved names are avoided; existing files are never overwritten.
- TLS certificate errors fail the download; certificate checking is never disabled.
- No credentials are stored. When authenticated downloads are added, use `flutter_secure_storage`, not shared_preferences.
- Logs do not currently include URLs or headers.


## Background, share, tray and updates (added later; NOT tested on devices)

- **Android background:** foreground service (`dataSync`) + wake lock, installed by `dart tool/setup.dart` (Kotlin files from `tool/templates/android`). Android 15 limits `dataSync` services to about 6 hours per day; Android 12+ may refuse starting the service from the background. Battery optimizations by some vendors can still kill the app.
- **iOS:** no background downloading. On suspend, downloads are parked and resume with Range requests when the app returns. **Share sheet:** add a Share Extension target in Xcode following the `receive_sharing_intent` package README; the app side is already wired.
- **Desktop tray:** needs `libayatana-appindicator3` on Linux (GNOME may need an AppIndicator extension); `libsecret` for credentials; `libnotify` for notifications.
- **Secure storage:** Keychain / Keystore / DPAPI / libsecret via `flutter_secure_storage`. If unavailable, downloads still work but credentials are not persisted.
- **Proxy:** HTTP only (CONNECT for HTTPS). The proxy credentials format relies on `dart:io` behaviour that has not been tested here.
- **Updater install:** Android opens the APK in the system installer (signature must match; permission "install unknown apps"); Windows runs the Inno Setup installer silently; macOS opens the .dmg; Linux reveals the .tar.gz.
