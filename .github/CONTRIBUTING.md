# Contributing to Strimr

Thanks for helping improve Strimr. New features, bug fixes, behavior improvements, and UX/UI polish are welcome.

Before starting work on a feature, open an issue so the implementation and any potential obstacles can be discussed. Before reporting a bug, check that an existing issue does not already cover it.

## Requirements

- Xcode with the SDKs required by the current deployment targets: iOS 18, macOS 26, and tvOS 26.
- [Homebrew](https://brew.sh/) and SwiftFormat.

Install SwiftFormat with:

```sh
brew install swiftformat
```

## Setup

1. Create the local app configuration:

   ```sh
   cp Config/Config-example.xcconfig Config/Config.xcconfig
   ```

   Set `DEVELOPMENT_TEAM` and `PRODUCT_BUNDLE_IDENTIFIER`. The Sentry DSN settings may remain empty for local development. Never commit credentials or DSNs.

2. When building the tvOS Top Shelf extension, also create `Config/Config-TopShelf.xcconfig` with `DEVELOPMENT_TEAM` and a distinct `PRODUCT_BUNDLE_IDENTIFIER` for the extension. This file is local and must not be committed.

3. Open `Strimr.xcodeproj` in Xcode. Swift package dependencies are resolved by Xcode.

## Architecture

Strimr is a native SwiftUI app for iOS, macOS, and tvOS. Platform-specific code and assets live in `Strimr-iOS/`, `Strimr-macOS/`, and `Strimr-tvOS/`; reusable models, networking, storage, features, and views live in `Shared/`. The tvOS Top Shelf extension lives in `StrimrTopShelf/`.

The UI follows an MVVM-style approach with SwiftUI views and Observation-based `@Observable` view models. Prefer shared implementations when behavior is the same across platforms, while keeping platform-specific interaction and presentation in the appropriate target.

## Design and localization

- Prefer clean, direct layouts and native platform patterns.
- Keep screens focused, with one primary action per view when possible.
- Use shared components instead of duplicating UI.
- Localize every user-facing string. Use keys such as `Text("home.title")` and `String(localized: "errors.selectServer")` instead of string literals.
- Put shared app strings in `Localizable.xcstrings`, platform Info.plist strings in the relevant `InfoPlist.xcstrings`, and Top Shelf extension strings in `StrimrTopShelf/Localizable.xcstrings`.
- Put platform-specific assets in the appropriate `Strimr-iOS/Assets.xcassets`, `Strimr-macOS/Assets.xcassets`, or `Strimr-tvOS/Assets.xcassets` catalog.

## Formatting and validation

Format Swift changes before submitting them:

```sh
swiftformat .
```

Verify formatting with the same check used in CI:

```sh
swiftformat --lint . --reporter github-actions-log
```

Build each affected app scheme in Xcode before opening a pull request. The shared schemes are `Strimr` for iOS, `Strimr-macOS`, and `Strimr-tvOS`. For tvOS command-line validation, use an arm64 simulator destination because LibDovi does not provide an x86_64 simulator slice:

```sh
xcodebuild -project Strimr.xcodeproj \
  -scheme Strimr-tvOS \
  -destination 'generic/platform=tvOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  build
```

## Submitting changes

- Keep pull requests focused and avoid mixing unrelated changes.
- Link the issue that the pull request addresses.
- Prefix a platform-specific pull request title with `(iOS)`, `(macOS)`, or `(tvOS)` when it helps clarify its scope.
- Add or update localization keys and assets as needed.
- Use a conventional branch name such as `feat/<short-description>`, `fix/<short-description>`, `ui/<short-description>`, `refactor/<short-description>`, or `chore/<short-description>`.
- Use Conventional Commits, for example `feat: add media filtering` or `fix: handle empty server names`. Scopes such as `ios`, `macos`, `tvos`, or `shared` are optional when they add useful context.
