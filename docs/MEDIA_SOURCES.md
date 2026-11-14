# Media sources and third-party services

**Status: parsers are unit-tested against hand-written samples only. None of the live services below has been contacted from ZapDL, so every adapter may need fixes on first real use.**

| Source | How it works | Known limits |
|---|---|---|
| YouTube | `youtube_explode_dart` package (stream manifest) | Only muxed streams (video+audio, usually up to 720p) and audio-only; no video+audio merging (needs ffmpeg). Throttling and breakage on YouTube changes are common; update the package. Respect YouTube's Terms of Service. |
| Reddit | `<post>.json` | Reddit serves video and sound separately; both are offered, not merged. May require login or be rate limited. |
| Telegram | Public embed page `t.me/<channel>/<id>?embed=1` | Public channels only. |
| Generic pages | Open Graph / Twitter card / `<video>` tags | Only sites that expose direct file URLs. |
| yt-dlp (desktop) | Runs a `yt-dlp` executable if installed (`--dump-single-json`) | Only direct HTTP formats; HLS/DASH manifests are skipped. ZapDL does not bundle or install yt-dlp. |
| GitHub Releases | `api.github.com/repos/ghaderi0x/ZapDL/releases` | Unauthenticated rate limit (60/h); ETag caching used. |

ZapDL does not bypass DRM, paywalls or login walls. You are responsible for respecting each site's terms and copyright.

## Filtered sites (YouTube and others blocked by a government)

No downloader can unblock a site by itself. What ZapDL does:

- **Uses your proxy everywhere.** The YouTube lookup, every other media lookup and the file download all go through the same proxy (Settings → Network). This matters because YouTube stream links are tied to the IP address that asked for them: looking up through a proxy and downloading directly gives a 403.
- **Reads the Windows/macOS system proxy.** Tools such as v2rayN, Nekoray or Clash in "System proxy" mode set the OS proxy; dart:io alone ignores it, so ZapDL now reads it itself (re-read every 60 seconds). Leave the proxy mode on **System**.
- **Only HTTP proxies work.** If your tool offers a local HTTP port (for example `127.0.0.1:10809` in v2rayN, `127.0.0.1:7890` in Clash), choose **Manual** and enter it. A SOCKS-only port will not work, and a full-device VPN (TUN mode) works without any setting.
- **yt-dlp** (desktop, optional) is tried first for non-YouTube sites when installed; it has its own proxy handling, which ZapDL passes through when set to Manual.

What it cannot do: bypass filtering without a working proxy/VPN, or guarantee that YouTube extraction keeps working (YouTube changes often; update ZapDL).
