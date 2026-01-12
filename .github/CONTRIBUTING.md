# Contributing to Strimr

Thanks for helping improve Strimr. New features are welcome, and so are bug fixes, behavior improvements, and UX/UI polish.

Before starting a feature request, please open an issue first so we can discuss the implementation, any obstacles, and help other users understand what is planned.
Before reporting a bug, please check that it does not already exist.

## Setup

1. Install dependencies:

   ```sh
   brew install carthage swiftformat
   ```

2. Download the Carthage binaries:

   ```sh
   carthage bootstrap --use-xcframeworks --platform iOS,tvOS
   ```

3. Create your local config file in `Config/`:

   ```sh
   cp Config/Config-example.xcconfig Config/Config.xcconfig
   ```

   Update `DEVELOPMENT_TEAM` and `PRODUCT_BUNDLE_IDENTIFIER`.

4. Open `Strimr.xcworkspace` in Xcode.

## Architecture

Strimr is a native iOS and tvOS SwiftUI app with shared code between targets. The app is split into feature areas and shared modules.

The UI follows a simple MVVM-style approach with SwiftUI views and `@Observable` view models.

## Design

- Prefer clean, direct layouts and native platform patterns.
- Keep screens focused: one primary action per view when possible.
- Use shared components instead of duplicating UI.
- Localization is required for all user-facing strings. Use keys like `Text("home.title")` and add entries to `Localizable.xcstrings`.

## Formatting

Use `swiftformat` to format the code.

## Submitting changes

- Keep PRs focused and avoid mixing unrelated changes.
- Add or update localization keys as needed.
- If you add new assets, keep them in the correct target catalog: `Strimr-iOS/Assets.xcassets` or `Strimr-tvOS/Assets.xcassets`.
- Use Conventional Commits with the scope `ios` or `tvos`.
