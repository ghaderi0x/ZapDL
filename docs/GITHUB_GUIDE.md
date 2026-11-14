# From the zip to a GitHub release (Linux, step by step)

Nothing here has been run by the author of the zip. Follow the steps in order and fix what breaks; the first build is the first real test.

## 0. What you need

```bash
sudo apt install git curl unzip openjdk-17-jdk        # Debian/Ubuntu; use dnf/pacman equivalents
```

You do **not** have to install Flutter or the Android SDK to publish: GitHub Actions builds everything. You only need them if you want to run the app locally. Flutter: https://docs.flutter.dev/get-started/install/linux

## 1. Unpack

```bash
mkdir -p ~/dev && cd ~/dev
unzip ~/Downloads/zapdl.zip -d ZapDL
cd ZapDL
```

## 2. (Needs Flutter) generate platform folders

```bash
dart tool/setup.dart        # creates android/ ios/ windows/ linux/ macos/, icons, permissions
flutter analyze
flutter test
git status                  # the generated folders must be committed
```

If you skip this step the CI workflows cannot build, because the platform folders do not exist yet. Either run it locally, or tell me the errors and I will fix them.

## 3. Create the GitHub repository

1. On github.com create **ZapDL** under your account (`ghaderi0x`), empty (no README/license).
2. Create a personal access token: GitHub → Settings → Developer settings → Personal access tokens → **Fine-grained token**, repository `ZapDL`, permissions **Contents: Read and write** and **Workflows: Read and write**. Copy it once.
3. Push:

```bash
git init -b main
git config user.name "Your Name"
git config user.email "you@example.com"
git add .
git status                       # make sure no *.jks / key.properties is listed
git commit -m "Initial commit"
git remote add origin https://github.com/ghaderi0x/ZapDL.git
git push -u origin main          # username: ghaderi0x, password: the TOKEN
```

To avoid retyping the token: `git config --global credential.helper store` (saves it in plain text) or install the `gh` CLI and run `gh auth login`.

4. Repo settings: add a description, topics (`flutter`, `download-manager`), and upload `assets/branding/social-preview.png` under Settings → General → Social preview.

## 4. Create the Android signing key (once, forever)

```bash
keytool -genkeypair -v -keystore ~/zapdl-release.jks -alias zapdl \
  -keyalg RSA -keysize 2048 -validity 10000
```

- Back up `~/zapdl-release.jks` and its passwords somewhere offline (USB, password manager). **If you lose it you can never update installed copies.**
- Never put it in the repo (`.gitignore` blocks it).

Add four secrets: repo → Settings → Secrets and variables → Actions → New repository secret:

| Name | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | output of `base64 -w0 ~/zapdl-release.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | the keystore password |
| `ANDROID_KEY_ALIAS` | `zapdl` |
| `ANDROID_KEY_PASSWORD` | the key password |

## 5. Dry run, then release

1. Actions tab → **Release** → **Run workflow** (manual dry run, builds but publishes nothing). Fix any failure, then re-run.
2. Bump the version and tag:

```bash
dart tool/bump_version.dart 1.0.0      # edits pubspec, app_info, CHANGELOG
git add -A && git commit -m "Release 1.0.0"
git tag v1.0.0
git push origin main --tags
```

3. Watch Actions. When green, **Releases** shows `v1.0.0` with the APK, Windows installer/zip, Linux tar.gz, macOS dmg and `SHA256SUMS.txt`. Use a tag with a dash (`v0.1.1-beta.1`) for a pre-release.

## 6. Download and install

```bash
# Linux
tar -xzf ZapDL-1.0.0-linux-x64.tar.gz -C ~/zapdl && ~/zapdl/zapdl
sha256sum -c SHA256SUMS.txt --ignore-missing
# Android: copy the APK to the phone (or open the Releases page in its browser) and install.
```

Test the updater: install an older release, publish a newer one, open Settings → Updates.

## 7. Should the APK be signed before GitHub, Myket and Bazaar?

**Yes, always, with one permanent release key.** An unsigned APK does not install, and a debug-signed one is a bad idea. The important rule: Android only updates an app when the new APK has the *same signing key*. So use the same keystore for the GitHub APK and for what you upload to Myket and Bazaar; otherwise users who move between sources must uninstall first and lose data.

- GitHub: upload `ZapDL-X.Y.Z-android.apk` (updater on).
- Myket / Bazaar: upload `ZapDL-X.Y.Z-android-store.apk` (updater off, no install-packages permission). The release workflow attaches it to the GitHub release too (the in-app updater ignores it), so download it from there, or build locally with `KEYSTORE=... KEY_ALIAS=... KEYSTORE_PASSWORD=... KEY_PASSWORD=... tool/build_android.sh` (output in `dist/`).
- **Unverified:** I could not check Myket's and Bazaar's current rules (re-signing of uploads, policies on self-updating apps, required fields). Read their developer documentation before submitting.
