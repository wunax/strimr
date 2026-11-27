# Links

Strimr opens `strimr://` links on iPhone, iPad, Mac and Apple TV. They can be written on an NFC tag, opened by a
shortcut, or launched by a home automation (for example Home Assistant's `media_player.play_media` on an Apple TV).

The easiest way to get a link is **Copy Link** in the menu of a movie, show, season, episode or Live TV channel
(iPhone, iPad and Mac). It contains the server and item ids, or the catalog ids of a movie or show, and the active
profile.

Links only open and play what the profile can already see. They never mark anything as watched, delete or change
anything, and a profile protected by a PIN still asks for it.

## Destinations

```text
strimr://open
strimr://media/<itemID>?provider=<plex|jellyfin>&server=<serverID>
strimr://media?type=<movie|show>&tmdb=<id>|tvdb=<id>|imdb=tt<id>[&title=<title>][&year=<yyyy>]
strimr://play/<itemID>?provider=<plex|jellyfin>&server=<serverID>[&type=<kind>]
strimr://play?type=<movie|show>&tmdb=<id>|tvdb=<id>|imdb=tt<id>[&title=<title>][&year=<yyyy>]
strimr://live/<channel>[?provider=<plex|jellyfin>&server=<serverID>]
strimr://library/<libraryID>?provider=<plex|jellyfin>&server=<serverID>
strimr://search[?q=<text>]
strimr://tab/<home|search|downloads|libraries|liveTV|explore|favorites>
```

| Link | Effect |
| --- | --- |
| `open` | Opens the app, switching profile if the link names one. |
| `media` | Opens the page of a movie, show, season or episode. |
| `play` | Plays an item. A show or season plays its next episode. |
| `live` | Tunes a Live TV channel. |
| `library` | Opens a library. |
| `search` | Opens the search, filled with `q`. |
| `tab` | Opens a tab. A tab the device lacks (downloads on Apple TV) opens the home page. |

- `provider` defaults to `plex`.
- `type` is optional on `play/<itemID>`: without it, the item is loaded to find its kind.
- Catalog links (`tmdb`, `tvdb` or `imdb`) find the movie or show on any server of the profile. Only the ids decide
  what matches. `title` and `year` help find it: without a title, only Plex servers can be searched.
- `live/<channel>` matches the channel id, then its number (`live/2` finds `002`), then its call sign, then its name,
  ignoring case: `strimr://live/TF1` works. Without `server`, every Live TV server of the profile is searched.

## Playing

`play` links take these options:

| Parameter | Effect |
| --- | --- |
| `mode=resume` | Default: resumes from the saved position, like the Play button. |
| `mode=restart` | Plays from the beginning. |
| `mode=shuffle` | Plays a show or season in random order. |
| `offset=<seconds>` | Starts at this position. Wins over `mode=resume` and `mode=restart`. |
| `audio=<language>` | Audio language. |
| `subs=<language>` or `subs=off` | Subtitle language, or no subtitles. |

Languages are ISO 639 codes: `fr`, `fra` and `fre` all mean French. With several tracks in that language, a regular
track is preferred over forced and hearing impaired ones. If the file has no track in that language, the track the app
would pick anyway plays.

Options apply to the first item only: the next episodes play as usual. A track chosen in the player replaces the one
the link asked for. A downloaded copy, played when the server cannot be reached, and an external player chosen in the
settings ignore `offset`, `audio` and `subs`.

```text
strimr://play/12345?provider=plex&server=abc&mode=restart
strimr://play/12345?provider=plex&server=abc&offset=1800&audio=ja&subs=en
strimr://play?type=movie&tmdb=278&title=The%20Shawshank%20Redemption&year=1994&subs=off
```

## Profile

Every link accepts `profile=<id or name>`. The profile is matched by id, then by name ignoring case. Without it, the
link opens on the active profile. A link that names an unknown profile shows a message and does nothing.

## Now Playing

While something plays, the system Now Playing info carries a link to it in
`MPNowPlayingInfoPropertyExternalContentIdentifier`: a `play` link for a movie or episode, a `live` link for a
channel. A home automation reading it can store it and open it again later.

## Compatibility

Links written on tags and in automations keep working: parameters may be added in later versions, never renamed or
removed.
