# Implementation checklist

Legend: **Written** = code exists but has not been compiled or run. **Verified** = executed and confirmed. **Partial** = some sub-items only. **No** = not started.

**Verified by the maintainer (2026-11-14):** `flutter test` passes (121 tests before the 1.0.0 additions) and the Windows build runs and works. Everything else is still **Written**, including all Android, Linux, macOS and iOS behavior and everything added for 1.0.0 (themes, link groups, auto next part, deleted-file marking, system proxy, hover). The author has no Flutter SDK, so none of that has been compiled by them. Flip an item to Verified only after running it.

| Brief § | Item | Status | Notes |
|--------|------|--------|-------|
| 1 | Name, tagline, default accent `#3478F6` | Written | Tagline localized in the UI |
| 2 | Design spec from references | Written | `docs/DESIGN_SPEC.md`; implementation follows it |
| 3 | Android, iOS, Windows, Linux, macOS | Partial | One codebase; none run on any platform |
| 4 | Clean architecture, DI, BLoC | Partial | Engine/cubit/UI split; Domain/Data layers intentionally collapsed (see PHASE0_REPORT) |
| 4 | Routing | No | Single adaptive shell with dialogs/sheets; no router package |
| 5.1 | 4 preset accents | Written | Exact palettes from brief |
| 5.2 | Custom accent + persistence | Written | HSL-derived shades |
| 5.3 | Light / Dark / System | Written | Independent of accent |
| 5.4 | Semantic colors, central design system | Written | `ZapColors`; contrast caveat in README |
| 6 | 6 languages, RTL, plurals, date/number formats | Partial | Strings written, not native-reviewed; RTL via directional widgets, not visually tested |
| 7 | Splash | Written | Shown while startup completes; no artificial delay |
| 7 | Mobile onboarding (skippable, once) | Written | Covers management, speed, pause/resume, organization, multi-platform |
| 7 | Desktop first-launch experience | No | Goes straight to the app |
| 8 | Dashboard: counts, speed, filters, categories, search | Written | Storage info not shown |
| 8 | Download item info and actions | Written | Open containing folder is desktop-only |
| 9.1 | HTTP/HTTPS | Written | |
| 9.1 | FTP/SFTP | No | Rejected with a clear message |
| 9.2 | Multi-connection, Range, safe merge, fallback | Written | Tested against local server (not run) |
| 9.3 | Pause/resume, validators, restart recovery | Written | |
| 9.4 | Queue, concurrency, priorities, retry | Partial | Priority has no UI |
| 9.5 | Reliability / error handling | Partial | Disconnection handled by retry; no connectivity monitor, no auto-resume on reconnect |
| 9.6 | Streaming, bounded memory, cleanup | Written | ~1 MiB flush; temp cleanup tool |
| 10 | Background downloads (all platforms) | No | Downloads run only while the app is open |
| 11 | URL dialog, validation, name/size detection, destination, duplicates, history | Written | Clipboard suggestion (not on iOS) |
| 11 | Share-sheet intake | No | |
| 12 | Social/media adapters | No | |
| 13 | Categorization, folders, rename, open, delete | Partial | Storage management UI absent; rename only at add time |
| 14 | Scheduling | No | |
| 14 | Wi-Fi-only, mobile-data warning | No | |
| 14 | Per-download speed limit | Written | Global limit: No |
| 14 | Statistics | Partial | Totals and 7-day chart; no monthly stats or speed history |
| 14 | Proxy, headers, cookies, auth | No | |
| 14 | Checksums | Partial | Library + tests; no UI |
| 15 | Persistence | Partial | JSON store (atomic); settings in shared_preferences; no DB migrations, no export/import |
| 16 | Security | Partial | Safe names, TLS enforced, no secrets stored; no credential storage yet; logging redacts URLs |
| 17 | Settings | Partial | Only functional controls shown; Network, notifications, startup, confirmation prefs absent by design |
| 17 | About: version, license, third-party licenses | Written | GitHub link omitted until a repository URL exists |
| 18 | Notifications | No | In-app snackbars only |
| 19 | Tests: unit, widget, integration | Written | Not run. Integration tests are engine-over-loopback; no full-app integration_test |
| 20 | Accessibility | Partial | Tooltips/semantics on actions and progress; no audit; no desktop focus-order work |
| 21 | GitHub standards | Written | README, CONTRIBUTING, CODE_OF_CONDUCT, CHANGELOG, templates, CI; no screenshots yet |
| 22 | Release prep | No | `docs/RELEASE.md` is instructions only |


## Added in the latest round (all UNVERIFIED: nothing compiled or run)
- [ ] Fonts render correctly (Vazirmatn / Inter / Noto SC) and RTL follows language
- [ ] Headers, cookies, Basic auth, redirect credential stripping (tests written: test/engine/network_features_test.dart)
- [ ] Manual HTTP proxy incl. credentials against a real proxy
- [ ] Wi-Fi-only, offline gate, schedule window, scheduled start (engine tests written; real device check needed)
- [ ] Android foreground service survives screen-off; notification permission flow
- [ ] Tray, close-to-tray, notifications on Windows / Linux / macOS
- [ ] Share sheet (Android), iOS share extension (not created), drag-and-drop
- [ ] YouTube / Reddit / Telegram / Open Graph / yt-dlp against live sites
- [ ] Updater against a real GitHub release; each platform installer; release workflow
