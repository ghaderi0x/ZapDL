# Architecture

ZapDL is feature-first with a deliberately small number of layers. The brief asks for Clean Architecture; the engine is already behind interfaces, and the app layer is thin enough that separate use-case classes would only add indirection. If features grow (scheduling, media adapters), add `domain/` use cases per feature.

```
UI (pages/widgets)  ->  Cubits (DownloadsCubit, SettingsCubit)  ->  DownloadEngine  ->  DownloadStore
                                                                      |
                                                                 SegmentedRunner -> dart:io HttpClient
```

## Engine (`lib/engine`)

Pure Dart, no Flutter imports, so it can be tested with plain `flutter test` and reused by a CLI or background isolate.

| File | Responsibility |
|------|----------------|
| `models.dart` | `DownloadTask`, `Segment`, status/error enums, `EngineConfig` |
| `probe.dart` | URL validation, `Range: bytes=0-0` probe (size, range support, ETag, Last-Modified, file name), segment planning |
| `runner.dart` | Runs one download: segment download, resume, remote validation, merge, finalize |
| `engine.dart` | Queue, concurrency, pause/resume/cancel/remove, retry, persistence, speed ticker |
| `store.dart` | `DownloadStore` interface; atomic JSON implementation and in-memory test double |
| `errors.dart` | Exception to `DownloadErrorCode` mapping (no user-facing text in the engine) |
| `file_utils.dart` | File-name sanitizing, collision-free paths |
| `file_category.dart` | Extension-then-MIME categorization |
| `checksum.dart` | Streaming SHA-256 / MD5 |

### Key design decisions

- **Real range support only.** A server counts as range-capable only if it answered the probe with `206` and a `Content-Range` total. Otherwise one segment and one connection are used, so segments are never combined from servers that cannot serve them.
- **One part file per segment.** On every start the real part-file length is the source of truth for progress, so a crash cannot skip or duplicate bytes. Parts are streamed to disk and flushed about every 1 MiB, so memory stays bounded.
- **Resume validation.** Before resuming with existing data the engine re-probes and compares ETag, Last-Modified and length. A mismatch fails with `changed` and `needsRestart`; Retry then discards partial data and starts over. If a server answers `200` to a ranged resume, the same restart path is taken.
- **Safe finalize.** Parts are size-checked, merged into `<name>.zapdl-part`, the total size is verified, and the file is atomically renamed into a collision-free name. Completion is only set after that.
- **Retries.** Network errors, timeouts, 408/429/5xx and short bodies retry with exponential backoff, resuming from the bytes already on disk. Other errors fail immediately with a specific code.
- **Persistence.** The task list is saved on state changes and every ~2 s while downloading, via temp-file-plus-rename. Tasks saved as `downloading` load as `paused` after a restart.
- **Speed limit.** Applied per download in the runner (bytes per second across its segments).

## App layer

- `SettingsCubit` persists theme mode, accent (preset id or `custom:<argb>`), language, folder, concurrency, connections, speed limit and onboarding state, and pushes engine settings live.
- `DownloadsCubit` mirrors engine snapshots and holds filter/search state.
- `AdaptiveShell` picks navigation by width (<640 pill nav, 640-899 icon rail, >=900 sidebar), not by platform.
- Dependencies are wired in `core/di.dart` with `get_it`; cubits are provided to the tree with `flutter_bloc`.

## Theme

`AccentPalette` (presets + HSL-derived custom shades) feeds `ZapColors` (a `ThemeExtension` with layered surfaces, semantic colors and the progress gradient) and `AppTheme.build`. Widgets read colors through `context.zap`; there are no hardcoded colors in feature code.

## Extending

- **New protocol (FTP/SFTP):** introduce a transport interface used by `SegmentedRunner`, implement it per protocol, keep HTTP as the default.
- **Media site adapters:** add a `MediaSourceAdapter` that turns a page URL into a list of direct media URLs plus metadata, then hand the chosen URL to `DownloadEngine.add`. Keep each adapter separate and honor the site's terms.
- **SQLite:** implement `DownloadStore` with Drift and add a migration from the JSON file.
