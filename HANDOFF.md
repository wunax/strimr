# Handoff: external control links

Written on Linux with no Swift toolchain. **Nothing here has been compiled, linted or run.** Every API call was checked
against the surrounding source, but expect a few compile errors on the first build.

Docs for users and the PR description: `Documentation/external-control.md`.

## Commits (branch `external-control-links`)

1. Control actions and play options (`control/*`, `offset`, `resume`)
2. Audio and subtitle selection by language
3. `shuffle` on play links (collections)
4. Richer Now Playing info
5. Notify URL webhook

## Files changed

New:
- `Shared/Models/ExternalControl.swift` (parsing: `ExternalControlCommand`, `ExternalPlayOptions`, `ExternalSubtitleRequest`)
- `Shared/Features/Player/PlaybackWebhook.swift` (payload, URL check, sender, event tracker)
- Tests: `StrimrTests/Models/ExternalControlTests.swift`, `StrimrTests/Library/Player/PlayerTrackTests.swift`,
  `StrimrTests/Features/Player/PlaybackWebhookTests.swift`; additions to `NowPlayingItemTests` and `AppSettingsTests`

Edited:
- `Strimr-tvOS/TopShelfDeepLinkRouter.swift` (control handler, options in `Action`)
- `Strimr-tvOS/Features/Tab/MainTabView.swift` (passes options to `PlaybackLauncher`)
- `Strimr-tvOS/Features/Player/PlayerView.swift` (control handler, launch tracks, Now Playing chapter, webhook URL)
- `Strimr-iOS/Features/Player/PlayerView.swift`, `Strimr-macOS/Features/Player/PlayerView.swift` (webhook URL only)
- `Shared/Features/Player/PlaybackLauncher.swift`, `Shared/Domain/PlaybackModels.swift` (`PlaybackQueue.launchOptions`)
- `Shared/Features/Player/PlayerViewModel.swift` (offset, launch options, Now Playing details, webhook)
- `Shared/Library/Player/{NowPlayingItem,NowPlayingController,PlayerController,PlayerTrack}.swift`
- `Shared/Models/AppSettings.swift`, `Shared/Store/SettingsManager.swift`, `Shared/Features/Settings/SettingsViewModel.swift`,
  `Shared/Features/Settings/SettingsPlaybackView.swift`, `Strimr-tvOS/Features/Settings/SettingsPlaybackView.swift`,
  `Localizable.xcstrings` (English only: `settings.playback.notifyURL` and `.footer`)

New files rely on the project's synchronized folders; no `project.pbxproj` edit was made.

## Not built, not tested, not verified

- Everything compiles only in theory. Likely trouble spots: `MPNowPlayingInfoPropertyExternalContentIdentifier` may be
  unavailable on tvOS (wrap in `#if !os(tvOS)` if so); `switch` on an optional `String` in `ExternalPlayOptions`;
  Swift 6 isolation of the new `nonisolated` types.
- Control links exist on tvOS only (the router lives in `Strimr-tvOS`). iOS and macOS have no deep-link router, so they
  only got the Notify URL.
- Whether `Locale.Language("eng").languageCode?.identifier(.alpha2)` returns `en` on device (existing
  `SkipBackSubtitles.normalizedLanguage` is reused, and its own tests only cover the table and `en`, `eng`, `fra`).
- Which language codes the engine reports for tracks (`PlayerTrack.language`), and for transcoded streams.
- `control/next` calls `handleStop()` then swaps the view model; SharePlay and Live TV are excluded.
- A play `offset` with a Jellyfin transcode: `prepare(resume: false)` is requested, then the player seeks.
- Jellyfin collection links through `JellyfinCatalogService.playbackQueue` (read, never run). Jellyfin has no
  server-side play queue, so shuffle is client side.
- What tvOS, remote apps or Companion actually surface from the Now Playing keys. Assume `strimr.*` is not exposed.
- Chapter number base (documented as 1-based here; Apple does not say). `setNowPlayingChapter` republishes identity,
  which assumes `engine.setVideoNowPlayingInfo` merges with the engine's own playback keys (as the artwork path does).
- HTTP to a LAN address from the Notify URL relies on the existing `NSAllowsArbitraryLoads`.
- Cold launch by a control link: ignored by design (no player open).
- No translations besides English for the new strings.

## Mac checklist

```sh
xcodebuild -project Strimr.xcodeproj -scheme Strimr-tvOS -destination 'platform=tvOS Simulator,name=Apple TV' build
xcodebuild -project Strimr.xcodeproj -scheme Strimr-iOS -destination 'platform=iOS Simulator,name=iPhone 16' build
xcodebuild -project Strimr.xcodeproj -scheme Strimr-macOS build
xcodebuild -project Strimr.xcodeproj -scheme Strimr-iOS -destination 'platform=iOS Simulator,name=iPhone 16' test \
  -only-testing:StrimrTests/ExternalControlTests -only-testing:StrimrTests/PlayerTrackTests \
  -only-testing:StrimrTests/PlaybackWebhookTests -only-testing:StrimrTests/NowPlayingItemTests \
  -only-testing:StrimrTests/AppSettingsTests
swiftformat . --lint
```

(Check scheme and simulator names with `xcodebuild -list` and `xcrun simctl list devices`.)

Manual, tvOS simulator or device, via `xcrun simctl openurl booted '<url>'` (simulator) or Home Assistant `play_media`:

1. Play links: `resume=0` starts at 0 on a half-watched item; no `resume` resumes; `offset=600` starts at 10:00 and wins
   over `resume=0`; a negative `offset` is ignored.
2. Control: `pause`, `resume`, `toggle`, `seek?to=120`, `seek?by=-30`, `seek?by=%2B30`, with the player open; with no player
   open, nothing happens and nothing starts later when a player opens.
3. `skipIntro` inside and outside an intro, `skipCredits` likewise; `next` in a show (old item not marked watched) and at the
   last item (ignored).
4. Tracks: `audio=fr&subs=en` on a file with both; a language the file lacks (audio and subs unchanged, subs not turned
   off); `subs=off`; `control/audio?lang=` and `control/subs?lang=` mid-playback; confirm the choice is remembered on the next
   episode, and that without `audio`/`subs` the remembered behavior is unchanged. Try a transcoded session too.
5. Collections: `type=collection` with `shuffle=0` and `1` on Plex; on Jellyfin a box set.
6. Now Playing: print `MPNowPlayingInfoCenter.default().nowPlayingInfo` (or the engine's info) while playing; look at the
   Control Center remote and `pyatv`'s `atvremote playing` for what shows.
7. Notify URL: point it at `nc -l 8080` or a request bin; check start, pause, resume, stop (leave mid-episode), finish (let
   it end; no extra stop), an unreachable address (no hang, no UI effect), a `file://` or empty value (nothing sent).
   Settings field on tvOS, iOS and macOS.

## Open questions for the maintainer

- OK to add `PlaybackQueue.launchOptions` and `PlayerViewModel.launchOptions`, or prefer another way to carry link options?
- Should link-chosen tracks be remembered across episodes (current behavior, same as the menu), or applied for this item only?
- Do you want control links on iOS/macOS too (needs a deep-link router there)?
- Should the Notify URL live under Integrations instead of Playback, and should it include more fields?
