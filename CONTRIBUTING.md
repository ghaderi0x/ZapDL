# Contributing to ZapDL

Thank you for helping. ZapDL values **download integrity and honesty** over feature count: a download must never be reported complete unless it is, and documentation must never describe planned features as finished.

## Setup

```bash
git clone <your fork>
cd zapdl
dart tool/setup.dart        # creates platform folders, patches permissions, pub get, gen-l10n
flutter analyze
flutter test
```

Requires Flutter 3.27 or newer.

## Project rules

1. **No hardcoded user-facing strings.** Add keys to `lib/l10n/app_en.arb` and the five other ARB files; then run `flutter gen-l10n`.
2. **No hardcoded colors.** Use `context.zap` (see `lib/core/theme/zap_colors.dart`) and the theme.
3. **RTL safe layouts.** Use `EdgeInsetsDirectional`, `AlignmentDirectional`, and `start`/`end`; never `left`/`right` for content. Check Persian or Arabic before submitting UI changes.
4. **Engine stays pure Dart.** `lib/engine` must not import Flutter. UI talks to it only through cubits.
5. **No business logic in widgets.**
6. **No fake functionality.** If a control is not functional, do not ship it. Progress, speed and status must come from real transfers.
7. **Test important logic.** Engine changes need a test against the local test server in `test/engine/engine_test.dart`; never depend on third-party websites in tests.
8. **Be explicit about platforms.** Only claim a platform works if you ran it there.

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org/): `feat(engine): ...`, `fix(ui): ...`, `docs: ...`, `test: ...`, `refactor: ...`, `chore: ...`.

## Pull requests

Fill in the PR template, including which tests you ran and on which platforms. Keep PRs focused; large changes should be discussed in an issue first.

## Reporting security issues

Please do not file public issues for vulnerabilities (for example path traversal or credential leaks). Contact the maintainers privately through the repository's security advisory feature.
