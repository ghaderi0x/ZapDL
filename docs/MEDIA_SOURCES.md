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

## Supported platforms (1.0.0)

| Platform | How it is read | Depends on |
|---|---|---|
| YouTube (videos, Shorts) | `youtube_explode_dart` (25 s limit), then YouTube's player API as the Android VR app calls it (direct links, no signature) | YouTube; a working proxy/VPN where it is filtered |
| TikTok | `https://www.tikwm.com/api/` (HD / no watermark / with watermark / sound / photo slideshows) | the third-party service tikwm.com |
| X / Twitter | `https://api.fxtwitter.com/status/<id>` (videos, GIFs, photos) | the third-party FxTwitter API |
| SoundCloud (single tracks) | the web player's own public API: finds the page's client id, asks `api-v2 /resolve`, then the progressive (MP3) stream | public, fully playable tracks only; playlists/sets, 30-second previews and Go+ tracks are not supported; the client id lookup may break when SoundCloud changes |
| Instagram (reels, videos, photo posts) | the public embed page `/<p\|reel>/<code>/embed/captioned/` | public posts only; Instagram changes this often |
| Telegram | public channel embed page (`t.me/<channel>/<id>`) | public channels only |
| Reddit | the post's `.json` | Reddit |
| Anything else | Open Graph tags (video/image the page declares) | the page |

On desktop, if **yt-dlp** is installed (on PATH), it is tried first for every link: it supports far more sites and is updated by its own team.

Be aware:
- TikTok and X go through third-party services. If they are down, filtered or change their format, those links fail until ZapDL is updated.
- **Spotify is not supported, on purpose.** Its audio is encrypted (DRM); the only ways to save it are ripping tools that break Spotify's terms and that we won't ship. ZapDL says so instead of failing silently.
- Instagram private accounts, stories and anything that needs a login cannot be downloaded. A reel whose video can't be found reports "needs sign-in" instead of downloading just the cover picture.
- Every lookup has a time limit (about 100 s in total), so a stalled network ends in an error message rather than an endless spinner.

## Filtered sites (YouTube and others blocked by a government)

No downloader can unblock a site by itself. What ZapDL does:

- **Uses your proxy everywhere.** The YouTube lookup, every other media lookup and the file download all go through the same proxy (Settings → Network). This matters because YouTube stream links are tied to the IP address that asked for them: looking up through a proxy and downloading directly gives a 403.
- **Reads the Windows/macOS system proxy.** Tools such as v2rayN, Nekoray or Clash in "System proxy" mode set the OS proxy; dart:io alone ignores it, so ZapDL now reads it itself (re-read every 60 seconds). Leave the proxy mode on **System**.
- **Only HTTP proxies work.** If your tool offers a local HTTP port (for example `127.0.0.1:10809` in v2rayN, `127.0.0.1:7890` in Clash), choose **Manual** and enter it. A SOCKS-only port will not work, and a full-device VPN (TUN mode) works without any setting.
- **yt-dlp** (desktop, optional) is tried first for non-YouTube sites when installed; it has its own proxy handling, which ZapDL passes through when set to Manual.

What it cannot do: bypass filtering without a working proxy/VPN, or guarantee that YouTube extraction keeps working (YouTube changes often; update ZapDL).
