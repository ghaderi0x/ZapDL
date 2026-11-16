# Phase 0 report: inspection, architecture, risks, roadmap

Written to satisfy section 24 of the project brief. **Process note:** the brief asks for approval after Phase 0 before large-scale implementation. The project owner instead asked for the app to be built straight away, so Phases 0 to 3 and parts of 2 and 4 were done in one pass. This document records the Phase 0 findings and decisions retrospectively so they can still be reviewed.

## 1. Environment inspection

- Project directory: empty at start (no existing code to preserve).
- Authoring environment: Linux container **without Flutter or Dart SDK and with package installs blocked**. Consequently nothing has been compiled, analyzed, or executed. Every "implemented" item in this repo means "written", not "verified". `docs/CHECKLIST.md` tracks this per item.

## 2. Reference image analysis

Seven references were analyzed; the full result is `docs/DESIGN_SPEC.md` (tokens, layouts, components, RTL rules, what was deliberately not copied). The dominant direction is dark-first, rounded, layered surfaces with one accent color.

## 3. Architecture

```
Presentation  pages, widgets, cubits, theme, l10n         lib/features, lib/shared, lib/core/theme
Application   cubits mediating UI and engine               lib/features/*/ *_cubit.dart
Engine        pure Dart download subsystem                 lib/engine
Core          DI, formatting, platform, logging            lib/core
```

The brief's `Domain/Data` split with use-case classes was **deliberately collapsed**: the engine is already behind a `DownloadStore` interface and the cubits are thin, so per-feature use-case and repository classes would be pure indirection today (the brief itself warns against overengineering). The seams to re-introduce them are documented in `docs/ARCHITECTURE.md`.

## 4. Folder structure

See `README.md`. Feature-first under `lib/features`, engine isolated under `lib/engine`.

## 5. Download engine strategy

`dart:io` `HttpClient` directly (not `dio` or `http`) because the engine needs exact control over Range headers, redirects, abort-on-pause, and streaming with bounded memory. Details in `docs/ARCHITECTURE.md`. FTP/SFTP are designed as separate transport adapters but **not implemented**.

## 6. Package evaluation

Chosen (all common, actively used Flutter packages; confirm current versions, licenses and maintenance on pub.dev when upgrading): `flutter_bloc` (required BLoC/Cubit), `get_it` (DI), `shared_preferences` (settings), `path_provider`, `path`, `crypto` (checksums), `file_picker` (folder choice), `open_filex` (open files), `flutter_colorpicker` (custom accent), `equatable`.

Deliberately **not** added yet: `drift` (see risk R3), `dio` (not needed), notification and background packages (need native validation on devices).

Candidates for later phases, to be evaluated against the criteria in section 26 of the brief at adoption time:

| Need | Candidates |
|------|-----------|
| SFTP / FTP | `dartssh2`, `ftpconnect` (or a native plugin) |
| Notifications | `flutter_local_notifications` |
| Android/iOS background transfers | `background_downloader`, or custom native foreground service + background `URLSession` |
| Share-sheet intake | `receive_sharing_intent` |
| Desktop window, tray, drag and drop | `window_manager`, `tray_manager`, `desktop_drop` |
| Connectivity | `connectivity_plus` (Wi-Fi-only mode) |
| Database | `drift` + `sqlite3_flutter_libs` |
| Secure credentials | `flutter_secure_storage` |

## 7. Platform limitations

See `docs/PLATFORM_NOTES.md`. Headline: iOS and Android suspend or kill background Dart code, so true background downloading requires native services; desktop needs tray/lifecycle work. Not implemented.

## 8. Risks

| # | Risk | Mitigation |
|---|------|-----------|
| R1 | Code never compiled; hidden compile/runtime errors | First action for the next developer: `dart tool/setup.dart`, `flutter analyze`, `flutter test`; engine tests exercise real sockets |
| R2 | Background execution differs per OS and needs native code | Phase 5; do not claim parity |
| R3 | JSON store does not scale to very large histories and has no migrations beyond a version field | `DownloadStore` interface; move to Drift with migrations |
| R4 | Servers with unusual Range/redirect/encoding behavior | Strict 206 + Content-Range check; identity encoding; fallback to single connection; extend tests |
| R5 | Resume of a pre-signed/expiring URL fails | Reported as `accessDenied`/`notFound`; a "refresh link" flow is future work |
| R6 | Social-media extraction is legally and technically fragile | Phase 6 only; adapter architecture; honor ToS; no DRM circumvention; do not claim support before tested |
| R7 | Store policies (Google Play, Myket, Cafe Bazaar) about download-manager apps and permissions | Review each store's current policy before submission |
| R8 | Machine-written translations may contain mistakes | Native-speaker review before release |
| R9 | Accent preset contrast below WCAG AA for small text | Documented; use bold/large text on accent or adjust presets |

## 9. Phased roadmap (status as of this commit)

| Phase | Scope | Status |
|-------|-------|--------|
| 0 | Inspection and planning | This document |
| 1 | Foundation: structure, DI, theme, l10n, utilities, logging, tests | Written, unverified (no router package; navigation is the adaptive shell) |
| 2 | UI foundation | Written, never seen on screen |
| 3 | Core HTTP engine, persistence, queue, retry, recovery | Written, tests written, not run |
| 4 | Multi-connection, Range, speed limit, checksum | Segmenting, Range and per-download speed limit written; scheduling, network controls, proxy, custom headers, global limit, checksum UI not started |
| 5 | Native integrations: background, notifications, share sheet, filesystem | Not started (clipboard suggestion only) |
| 6 | Media-site adapters | Not started |
| 7 | Stabilization: device testing, profiling, security review | Not started |
| 8 | Release: builds, store assets, signing | Docs only (`docs/RELEASE.md`); nothing built or published |
