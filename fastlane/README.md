fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios prepare_match

```sh
[bundle exec] fastlane ios prepare_match
```

Create or update Match profiles for iOS, tvOS, and Top Shelf

### ios verify_app_store_connect

```sh
[bundle exec] fastlane ios verify_app_store_connect
```

Verify App Store Connect API access for iOS and tvOS

### ios build_ios_testflight

```sh
[bundle exec] fastlane ios build_ios_testflight
```

Build a signed iOS TestFlight IPA without uploading it

### ios build_tvos_testflight

```sh
[bundle exec] fastlane ios build_tvos_testflight
```

Build a signed tvOS TestFlight IPA without uploading it

### ios build_testflight

```sh
[bundle exec] fastlane ios build_testflight
```

Build signed iOS and tvOS TestFlight IPAs without uploading them

### ios ios_beta

```sh
[bundle exec] fastlane ios ios_beta
```

Build and upload the iOS app to TestFlight

### ios tvos_beta

```sh
[bundle exec] fastlane ios tvos_beta
```

Build and upload the tvOS app to TestFlight

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build and upload the iOS and tvOS apps to TestFlight

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
