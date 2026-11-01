# External control

Strimr on tvOS can be driven by URL, for home automation that launches URLs on the Apple TV (for example Home
Assistant's `media_player.play_media` with `media_content_type: app`). tvOS apps cannot serve HTTP while suspended,
so a URL scheme is the way in. Everything below uses the existing `strimr://` scheme.

Playback options and track selection work in the built-in player. An external player chosen in the settings gets
only what it supports (the item, and the saved position unless `resume=0`).

## Play

```
strimr://play/<ratingKey>?type=<kind>&server=<server id>&provider=plex|jellyfin
```

`type` is a media kind (`movie`, `episode`, `series`, `season`, `collection`, ...; `show` is accepted for `series`).
`server` is required and must belong to the active profile; `provider` defaults to `plex`. These already existed.

Options, all optional:

| Parameter | Effect |
| --- | --- |
| `resume=0` / `1` | `0` starts from the beginning. Default `1`: resume from the saved position, as the Play button does. |
| `offset=<seconds>` | Start at this position. Wins over `resume`. Negative or malformed values are ignored. |
| `shuffle=1` | Queue the items of a collection, show or season in random order. Default off. |
| `audio=<code>` | Audio language, ISO 639-1 or 639-2 (`fr`, `fra` and `fre` all match French). |
| `subs=<code>` or `subs=off` | Subtitle language, or no subtitles. |

Examples:

```
strimr://play/12345?type=movie&server=abc&provider=plex&resume=0
strimr://play/12345?type=movie&server=abc&offset=1800&audio=ja&subs=en
strimr://play/678?type=collection&server=abc&shuffle=1
strimr://play/678?type=collection&server=abc&shuffle=0
```

Options apply to the first item only. Following episodes in the queue play as usual.

## Control

```
strimr://control/<action>
```

Only acts while the player is open; otherwise the link is dropped, nothing is queued for later.

| Link | Effect |
| --- | --- |
| `control/pause`, `control/resume`, `control/toggle` | Playback state. |
| `control/seek?to=<seconds>` | Absolute position. |
| `control/seek?by=<seconds>` | Relative, `+30` or `-15` (a literal `+` in a query may need to be `%2B` for some clients). `to` wins if both are given. |
| `control/skipIntro`, `control/skipCredits` | Like the on-screen Skip button: only while the playhead is inside that segment, otherwise ignored. |
| `control/next` | Next item of the queue. The current item is reported as stopped, not watched. Ignored in Live TV, SharePlay and when nothing follows. |
| `control/audio?lang=<code>` | Switch audio language. |
| `control/subs?lang=<code>` / `control/subs?lang=off` | Switch subtitle language, or turn subtitles off. |

Seeks are ignored in Live TV.

### Tracks and fallback

Tracks are chosen through the same path as the player's settings menu. The choice is therefore saved on the server and
remembered for the next episodes exactly as if picked by hand, so the "remember track selections" logic is unchanged.

If the file has no track in the requested language, nothing changes: the track the app picked on its own (remembered
choice, server preference or file default) keeps playing, and subtitles are not turned off. With several tracks in a
language, a regular one is preferred over commentary, hearing impaired and forced ones, then the file's default, then
file order. Languages are compared as ISO 639-1 after mapping three-letter codes.

## Collections

`type=collection` goes through `PlaybackLauncher` to the provider's queue builder. On Plex that is
`PlayQueueRepository.createQueue` with the collection URI and the `shuffle` flag, so the server holds the queue. On
Jellyfin the code path exists (`JellyfinCatalogService.playbackQueue` handles box sets and the queue is built on the
client, with no server-side play queue) but it has not been exercised through a link; see HANDOFF.md.

## Now Playing

The system Now Playing info now also carries:

| Key | Value |
| --- | --- |
| `MPNowPlayingInfoPropertyExternalContentIdentifier` | Item id (`ratingKey`) |
| `MPNowPlayingInfoPropertyPlaybackQueueIndex` / `Count` | Position in the play queue |
| `MPNowPlayingInfoPropertyChapterCount` / `ChapterNumber` | Chapters; the number follows the playhead (1-based) |
| `strimr.intro`, `strimr.credits` | `[start, end]` seconds |
| `strimr.nextTitle` | Title of the next queue item |

Only the `MPNowPlayingInfoProperty*` keys are documented by Apple. Whether tvOS, the Control Center remote or the
Companion protocol surface any of them is unverified, and arbitrary `strimr.*` keys are probably kept in the
dictionary without being shown or relayed to anything. Do not build on them; use the Notify URL for state.

## Notify URL

Settings, Playback, Notify URL (tvOS, iOS and macOS). Empty is off. Only `http` and `https` addresses are used.

On each event Strimr sends `POST` with `Content-Type: application/json`:

```json
{
  "event": "pause",
  "provider": "plex",
  "server": "abc",
  "ratingKey": "12345",
  "type": "episode",
  "title": "Pilot",
  "position": 61.5,
  "duration": 3600
}
```

`event` is `start`, `pause`, `resume`, `stop` (the player closed before the end) or `finish` (playback reached the
end, sent instead of `stop`). `position` and `duration` are seconds; `duration` is left out when unknown.

Delivery is fire and forget: 3 second timeout, nothing waits for it, failures are ignored, and a transport error is
retried once (an HTTP error status is not retried). The address is never logged.
