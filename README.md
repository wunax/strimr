<p align="center">
  <img src="Strimr-iOS/Assets.xcassets/Icon.imageset/logo_ios.png" alt="Strimr logo" width="160" />
</p>
<h1 align="center">Strimr</h1>

Strimr is a third-party Plex client built in Swift with a native interface for iPhone, iPad, and Apple TV.

## Key Features
- **HDR**, **HDR10+**, **HLG**, and **Dolby Vision** profiles 5, 8.1, 8.4, and 7 (profile 7 converted to 8.1 due to Apple platform limitations)
- **Dolby Atmos**, **TrueHD**, **DTS**, and **DTS-HD MA** (passthrough or conversion when required)<sup>[1]</sup>
- Server selection
- Profile selection (Plex Home)
- Seerr integration
- Customizable library visibility and navigation order
- Media browsing with hubs
- Search with filters for movies, shows, and episodes
- Rich media details
- Playback engines: MPV and external Infuse (limited)
- Watch together
- Audio/subtitle track selection
- Resume playback
- Downloads with offline mode
- Skip intro and credits

<small><sup>[1]</sup> Apple platforms do not support HDMI bitstream passthrough for Dolby TrueHD, DTS, DTS-HD MA, or DTS:X. These formats are decoded for playback and output either as **Dolby Digital Plus (compatibility mode, default)** or **lossless multichannel LPCM (lossless mode)**. Dolby Atmos (TrueHD) and DTS:X object metadata cannot be preserved due to tvOS limitations, while Dolby Atmos delivered as Dolby Digital Plus (E-AC3/JOC) is preserved via stream copy.</small>

## Platform Support
- iOS 18.0 or later
- tvOS 26.0 or later

## Playback Support

| Category | Supported formats |
| --- | --- |
| Containers | MKV, MP4, WebM, MPEG-TS, AVI, OGG, FLV |
| Video | H.264/AVC, HEVC/H.265, AV1, VP9, VP8, MPEG-4 Part 2, MPEG-2, VC-1 |
| HDR | HDR10, HDR10+, HLG, Dolby Vision profiles 5, 7 (as 8.1), 8.1, and 8.4 |
| Audio | AAC, HE-AAC, AC3, EAC3, FLAC, ALAC, TrueHD, MLP, DTS, DTS-HD MA, MP3, MP2, Opus, Vorbis, PCM |
| Subtitles | SRT, ASS/SSA (text only), WebVTT, mov_text, PGS, DVB, DVD bitmap, CEA-608 (CC1), teletext (text only) |

## Download
<p align="center">
  <a href="https://apps.apple.com/us/app/strimr/id6757491271">
    <img src=".github/assets/Download_on_the_App_Store_Badge_US-UK_RGB_blk_092917.svg" alt="Download on the App Store" width="200" />
  </a>
  <a href="https://apps.apple.com/us/app/strimr/id6757491271">
    <img src=".github/assets/Download_on_Apple_TV_Badge_US-UK_RGB_blk_092917.svg" alt="Download on Apple TV" width="200" />
  </a>
</p>

## Screenshots
<details>
  <summary>iPhone</summary>
  <p>
    <img src="Screenshots/iphone/iphone_home.jpg" alt="iPhone Home" width="240" />
    <img src="Screenshots/iphone/iphone_library_explore.jpg" alt="iPhone Library Explore" width="240" />
    <img src="Screenshots/iphone/iphone_library_recommended.jpg" alt="iPhone Library Recommended" width="240" />
    <img src="Screenshots/iphone/iphone_details_1.jpg" alt="iPhone Details 1" width="240" />
    <img src="Screenshots/iphone/iphone_details_2.jpg" alt="iPhone Details 2" width="240" />
    <img src="Screenshots/iphone/iphone_player.jpg" alt="iPhone Player" width="240" />
    <img src="Screenshots/iphone/iphone_search.jpg" alt="iPhone Search" width="240" />
  </p>
</details>

<details>
  <summary>iPad</summary>
  <p>
    <img src="Screenshots/ipad/ipad_home.jpg" alt="iPad Home" width="360" />
    <img src="Screenshots/ipad/ipad_library_explore.jpg" alt="iPad Library Explore" width="360" />
    <img src="Screenshots/ipad/ipad_library_recommended.jpg" alt="iPad Library Recommended" width="360" />
    <img src="Screenshots/ipad/ipad_details_1.jpg" alt="iPad Details 1" width="360" />
    <img src="Screenshots/ipad/ipad_details_2.jpg" alt="iPad Details 2" width="360" />
    <img src="Screenshots/ipad/ipad_player.jpg" alt="iPad Player" width="360" />
  </p>
</details>

<details>
  <summary>Apple TV</summary>
  <p>
    <img src="Screenshots/appletv/appletv_home.jpg" alt="Apple TV Home" width="360" />
    <img src="Screenshots/appletv/appletv_library_explore.jpg" alt="Apple TV Library Explore" width="360" />
    <img src="Screenshots/appletv/appletv_library_recommended.jpg" alt="Apple TV Library Recommended" width="360" />
    <img src="Screenshots/appletv/appletv_details.jpg" alt="Apple TV Details" width="360" />
    <img src="Screenshots/appletv/appletv_player.jpg" alt="Apple TV Player" width="360" />
  </p>
</details>
