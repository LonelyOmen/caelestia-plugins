# Better Lyrics

Desktop lyrics for the Caelestia shell, sourced from [Better Lyrics](https://api.betterlyrics.org)
instead of LRCLIB/NetEase.

The shell's `Lyrics` service is compiled C++ with a fixed backend enum and no plugin hook, so a
plugin cannot add a backend to it. This plugin therefore does the fetching and parsing itself:

- `GET https://api.betterlyrics.org/getLyrics` (TTML) is tried first.
- `GET https://api.betterlyrics.org/qq/getLyrics` (QRC) is the fallback.
- If neither has a match, the overlay falls back to the shell's own LRCLIB/NetEase lyrics.

Both endpoints are keyless for cache hits. Set `BETTER_LYRICS_API_KEY` in the shell environment,
or fill in the optional **API key** setting, to unlock uncached queries.

> **Note:** Better Lyrics is not currently issuing new API keys. Uncached tracks therefore return
> `401` and the overlay falls back to the shell's LRCLIB/NetEase lyrics. To make a track available
> without a key, play it once with the [Better Lyrics browser extension](https://better-lyrics.boidu.dev/)
> or upload lyrics at [unison.boidu.dev](https://unison.boidu.dev/).

## What is shared with the shell

The overlay still drives the shell's `Lyrics` singleton for the fallback, so the dashboard's
lyrics tab keeps working normally. The dashboard tab itself stays on LRCLIB/NetEase — a plugin
cannot change that without patching the C++ service.

## Settings

- **Use Better Lyrics** — turn the plugin's own provider on or off.
- **Fall back to shell lyrics** — use LRCLIB/NetEase when Better Lyrics has no match.
- **API key (optional)** — overrides `BETTER_LYRICS_API_KEY`.
- The existing General/Appearance/Background/Shadow options from the desktop-lyrics plugin are
  unchanged.

## Install

Place this directory under `~/.local/share/caelestia/plugins/better-lyrics`, then enable
`xlonely/betterlyrics` from Nexus → Plugins (or add it to `~/.config/caelestia/plugins.json`).
Disable `deeadly137/desktoplyrics` first: both draw a desktop lyric surface.

## License

GPL-3.0, inherited from the desktop-lyrics plugin this surface is forked from.
