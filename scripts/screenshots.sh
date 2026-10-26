#!/usr/bin/env bash
# Captures App Store screenshots from the demo catalog (see doc_agents/mode-demo-screenshots-spec.md).
#
# Usage: scripts/screenshots.sh [--platform iphone|ipad|duo|ios|tvos|mac|all] [--languages en,fr] [--delay 6]
#                               [--skip-build]
# `ios` covers the iPhone, the iPad and the iPhone Duo. Screenshots land in Screenshots/<device>/<language>/.
# This boots the simulators listed in AGENTS.md. `mac` runs the app on this Mac, which must stay unused meanwhile.

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
MAC_SHOTS=(
    "home=home"
    "library_recommended=library:movies"
    "details=detail:blade-runner-2049"
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
    [[ "$PLATFORM" == "$1" || "$PLATFORM" == "all" || ("$PLATFORM" == "ios" && "$1" =~ ^(iphone|ipad|duo)$) ]]
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

if wants mac; then
    MAC_APP="$DERIVED/Build/Products/Debug/Strimr.app"
    MAC_TOOLS="$REPO/build/screenshots"
    mkdir -p "$MAC_TOOLS"
    if [[ $SKIP_BUILD == 0 ]]; then
        # The sandboxed app may only read the demo catalog through this read-only exception, kept out of the project.
        python3 -I - "$REPO/Strimr-macOS/Strimr-macOS.entitlements" "$MAC_TOOLS/Strimr-macOS-demo.entitlements" \
            "$CONTENT/" <<'PYTHON'
import plistlib, sys
with open(sys.argv[1], "rb") as source:
    entitlements = plistlib.load(source)
entitlements["com.apple.security.temporary-exception.files.absolute-path.read-only"] = [sys.argv[3]]
with open(sys.argv[2], "wb") as target:
    plistlib.dump(entitlements, target)
PYTHON
        echo "Building Strimr-macOS"
        xcodebuild -project "$REPO/Strimr.xcodeproj" -scheme Strimr-macOS -configuration Debug \
            -derivedDataPath "$DERIVED" -clonedSourcePackagesDirPath "$PACKAGES" -destination "platform=macOS" \
            CODE_SIGN_ENTITLEMENTS="$MAC_TOOLS/Strimr-macOS-demo.entitlements" build -quiet
        cat > "$MAC_TOOLS/window-bounds.swift" <<'SWIFT'
import CoreGraphics
import Foundation

// Prints "x,y,width,height" of the frontmost window of the process, for screencapture -R.
let pid = Int32(CommandLine.arguments[1])!
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
    as? [[String: Any]] ?? []
for window in windows where (window[kCGWindowOwnerPID as String] as? Int32) == pid
    && (window[kCGWindowLayer as String] as? Int) == 0
{
    let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
    guard let height = bounds["Height"], height > 100 else { continue }
    print([bounds["X"], bounds["Y"], bounds["Width"], height].map { "\(Int($0 ?? 0))" }.joined(separator: ","))
    exit(0)
}
exit(1)
SWIFT
        swiftc -O "$MAC_TOOLS/window-bounds.swift" -o "$MAC_TOOLS/window-bounds"
    fi

    mac_binary="$MAC_APP/Contents/MacOS/Strimr"
    IFS=',' read -ra languages <<< "$LANGUAGES"
    for language in "${languages[@]}"; do
        output="$REPO/Screenshots/macos/$language"
        mkdir -p "$output"
        for shot in "${MAC_SHOTS[@]}"; do
            name="${shot%%=*}" route="${shot#*=}"
            echo "  macos $language $name ($route)"
            pkill -f "$mac_binary" 2>/dev/null || true
            sleep 1
            open -n --env STRIMR_DEMO_CONTENT="$CONTENT" "$MAC_APP" --args \
                -ScreenshotMode -ScreenshotRoute "$route" \
                -AppleLanguages "($language)" -AppleLocale "$(locale_for "$language")" \
                -ApplePersistenceIgnoreState YES -AppleShowScrollBars WhenScrolling \
                -strimr.diagnostics.errorReporting NO
            pid=""
            for _ in {1..20}; do
                pid="$(pgrep -n -f "$mac_binary" || true)"
                [[ -n "$pid" ]] && break
                sleep 0.5
            done
            sleep 2
            # Launched in the background, the app opens its window only once activated. Opening it again before it
            # runs would start a second instance without the arguments.
            open "$MAC_APP"
            sleep "$DELAY"
            bounds="$("$MAC_TOOLS/window-bounds" "$pid")"
            screencapture -x -R"$bounds" "$output/macos_$name.png"
        done
    done
    pkill -f "$mac_binary" 2>/dev/null || true
fi

echo "Done"
