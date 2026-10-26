#!/usr/bin/env bash
# Captures App Store screenshots from the demo catalog (see doc_agents/mode-demo-screenshots-spec.md).
#
# Usage: scripts/screenshots.sh [--platform iphone|ipad|duo|ios|tvos|all] [--languages en,fr] [--delay 6] [--skip-build]
# `ios` covers the iPhone, the iPad and the iPhone Duo. Screenshots land in Screenshots/<device>/<language>/.
# This boots the simulators listed in AGENTS.md.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CONTENT="$REPO/Screenshots/DemoContent"
DERIVED="$REPO/build/DerivedData"
PACKAGES="$HOME/Library/Caches/Strimr/SourcePackages"

PLATFORM="all"
DUO_UDID="823A013B-550E-481C-B099-F499EA778CF4"
LANGUAGES="en"
DELAY=6
SKIP_BUILD=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --platform) PLATFORM="$2"; shift 2 ;;
        --languages) LANGUAGES="$2"; shift 2 ;;
        --delay) DELAY="$2"; shift 2 ;;
        --skip-build) SKIP_BUILD=1; shift ;;
        *) echo "Unknown option $1" >&2; exit 1 ;;
    esac
done

if [[ ! -f "$CONTENT/catalog.json" ]]; then
    echo "Missing $CONTENT/catalog.json: run scripts/demo-catalog/fetch_tmdb.py first" >&2
    exit 1
fi

# <file name>=<route>
IOS_SHOTS=(
    "home=home"
    "library_recommended=library:movies"
    "details_1=detail:blade-runner-2049"
    "details_2=detail:slow-horses"
    "player=player"
)
IPAD_SHOTS=(
    "home=home"
    "library_recommended=library:movies"
    "details_1=detail:blade-runner-2049"
    "player=player"
)
TVOS_SHOTS=(
    "home=home"
    "library_recommended=library:movies"
    "details=detail:blade-runner-2049"
    "player=player"
)

simulator_udid() {
    xcrun simctl list devices available -j | python3 -I -c '
import json, sys
name, runtime = sys.argv[1], sys.argv[2]
for key, devices in json.load(sys.stdin)["devices"].items():
    if key.endswith(runtime):
        for device in devices:
            if device["name"] == name:
                print(device["udid"])
                sys.exit()
sys.exit(f"Simulator {name} ({runtime}) not found")
' "$1" "$2"
}

locale_for() {
    case "$1" in
        en) echo "en_US" ;;
        fr) echo "fr_FR" ;;
        de) echo "de_DE" ;;
        es) echo "es_ES" ;;
        it) echo "it_IT" ;;
        *) echo "$1" ;;
    esac
}

build() {
    local scheme="$1" destination="$2"
    shift 2
    [[ $SKIP_BUILD == 1 ]] && return
    echo "Building $scheme"
    xcodebuild -project "$REPO/Strimr.xcodeproj" -scheme "$scheme" -configuration Debug \
        -derivedDataPath "$DERIVED" -clonedSourcePackagesDirPath "$PACKAGES" \
        -destination "$destination" CODE_SIGNING_ALLOWED=NO "$@" build -quiet
}

capture() {
    local device_dir="$1" prefix="$2" udid="$3" app="$4"
    shift 4
    local shots=("$@")
    local bundle_id
    bundle_id="$(defaults read "$app/Info.plist" CFBundleIdentifier)"

    xcrun simctl boot "$udid" 2>/dev/null || true
    xcrun simctl bootstatus "$udid" -b >/dev/null
    xcrun simctl install "$udid" "$app"
    if [[ "$device_dir" != "appletv" ]]; then
        xcrun simctl status_bar "$udid" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
            --cellularMode active --cellularBars 4 --batteryState discharging --batteryLevel 100
    fi

    IFS=',' read -ra languages <<< "$LANGUAGES"
    for language in "${languages[@]}"; do
        local output="$REPO/Screenshots/$device_dir/$language"
        mkdir -p "$output"
        for shot in "${shots[@]}"; do
            local name="${shot%%=*}" route="${shot#*=}"
            echo "  $prefix $language $name ($route)"
            # tvOS sends an app relaunched right after a forced quit back to the home screen.
            if [[ "$device_dir" == "appletv" ]]; then
                xcrun simctl terminate "$udid" "$bundle_id" 2>/dev/null || true
                sleep 2
            fi
            SIMCTL_CHILD_STRIMR_DEMO_CONTENT="$CONTENT" xcrun simctl launch --terminate-running-process \
                "$udid" "$bundle_id" \
                -ScreenshotMode -ScreenshotRoute "$route" \
                -AppleLanguages "($language)" -AppleLocale "$(locale_for "$language")" \
                -strimr.diagnostics.errorReporting NO >/dev/null
            sleep "$DELAY"
            xcrun simctl io "$udid" screenshot --type=png "$output/${prefix}_${name}.png" >/dev/null 2>&1
        done
    done
    xcrun simctl terminate "$udid" "$bundle_id" 2>/dev/null || true
}

wants() {
    [[ "$PLATFORM" == "$1" || "$PLATFORM" == "all" || ("$PLATFORM" == "ios" && "$1" != "tvos") ]]
}

IOS_APP="$DERIVED/Build/Products/Debug-iphonesimulator/Strimr-iOS.app"
if wants iphone || wants ipad || wants duo; then
    build Strimr "generic/platform=iOS Simulator"
fi
if wants iphone; then
    capture iphone iphone "$(simulator_udid "iPhone 18 Pro Max" "iOS-27-0")" "$IOS_APP" "${IOS_SHOTS[@]}"
fi
if wants ipad; then
    capture ipad ipad "$(simulator_udid "iPad Pro 13-inch (M5)" "iOS-27-0")" "$IOS_APP" "${IPAD_SHOTS[@]}"
fi
if wants duo; then
    # Two simulators are named iPhone Duo: AGENTS.md pins this one by id.
    capture iphone-duo iphone_duo "$DUO_UDID" "$IOS_APP" "${IOS_SHOTS[@]}"
fi

if wants tvos; then
    build Strimr-tvOS "generic/platform=tvOS Simulator" ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
    capture appletv appletv "$(simulator_udid "Apple TV 4K (3rd generation)" "tvOS-27-0")" \
        "$DERIVED/Build/Products/Debug-appletvsimulator/Strimr-tvOS.app" "${TVOS_SHOTS[@]}"
fi

echo "Done"
