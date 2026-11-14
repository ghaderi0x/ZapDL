# Changelog

All notable changes are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/); versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.0] - 2026-11-14

### Added
- Theme picker with four named themes (Forest, Sunset, Ocean, Glacier), each with Auto / Light / Dark mode.
- Link groups: add several links at once and download them one after another in order; optional "auto-detect next part" (part1 -> part2 ...).
- Files deleted from disk are marked as deleted in the list.
- Hover highlights on desktop.
- System proxy support (Windows/macOS); YouTube lookups now use the same proxy as downloads.

### Fixed
- Download list not refreshing live; snackbar colors and the add button being hidden behind it.
- Linux build failing on compiler deprecation warnings (-Werror).
- Android release job: clear handling when signing secrets are missing.
- Windows "Programs" entry now shows just "ZapDL".
- Store writes were not serialized (could fail with "cannot rename .tmp").
- Cards swallowed ListTile ink effects.

## [0.1.0] - 2026-11-13 (pre-alpha)

### Added
- HTTP/HTTPS download engine: Range probe, multi-connection segments with safe merge, single-connection fallback, pause/resume with ETag / Last-Modified / length validation, recovery after restart, queue with concurrency limit and priorities, retry with backoff, per-download speed limit, temp-file cleanup.
- Adaptive Flutter UI (phone, tablet, desktop) based on the project's design references; download details view; context menu; search, status filters and category filters; statistics.
- Theme system: four preset accents, custom accent picker, light/dark/system, instant switching, persistence.
- Localization: English, Persian, Arabic, Spanish, Chinese, Russian, with RTL layouts.
- Add-download flow with probe, file-name and size detection, duplicate warning, link history and clipboard suggestion.
- Mobile onboarding (skippable, shown once).
- SHA-256 / MD5 checksum library.
- Automated tests (engine over a local HTTP server, utilities, theme, widgets) and CI workflow.

- Fonts: Vazirmatn (Persian, Arabic), Inter (English, Spanish, Russian), Noto Sans SC subset (Chinese); text direction follows the language (RTL for Persian/Arabic).
- Request options: custom headers, Referer, cookies (cookies.txt or raw), user:password URLs; credentials kept out of the JSON store and never sent to another origin after a redirect.
- HTTP proxy (system / none / manual with credentials in secure storage).
- Scheduling: start-later per download and a daily allowed-hours window (overnight supported).
- Wi-Fi-only mode and offline handling: downloads wait and resume automatically.
- Background downloads: Android foreground service; desktop tray with close-to-tray; iOS parks downloads on suspend and resumes them on return.
- Notifications for finished/failed downloads and available updates.
- Share sheet (Android), drag-and-drop of links / .txt / .url / .webloc files (desktop), bulk add.
- Media extraction: YouTube, Reddit, Telegram, generic Open Graph pages, and yt-dlp when installed (desktop).
- Updater reading GitHub Releases of ghaderi0x/ZapDL: ETag-cached daily checks, notification and banner, skip version, beta channel, resumable download with SHA-256 verification, install per platform, install from a local file; release workflow and Windows installer script.

### Known limitations (0.1.0)
- Not yet compiled or run: expect first-build fixes. See `docs/CHECKLIST.md`.
- iOS cannot download in the background; the iOS share extension must be added in Xcode.
- YouTube: only combined (muxed) streams up to what YouTube offers that way (often 720p) plus audio-only; no merging of separate video+audio. Third-party site formats change without notice.
- SOCKS proxies are not supported; no FTP/SFTP.
- Android updates require every release to be signed with the same key.
