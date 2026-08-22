#!/bin/bash
# Build, sign and upload PoolPlanner to TestFlight, entirely on this Mac.
#
# Prerequisites (one-time, GUI — see docs/ios-testflight-release.md):
#   - "Apple Distribution" certificate in the login keychain
#   - "PoolPlanner Distribution" App Store provisioning profile installed
#   - App Store Connect API key (.p8) saved outside the repo, with a
#     release.env exporting KEY_ID / ISSUER_ID / KEY_PATH
#
# The API key is per-team, so the one made for PlantAtlas Lube works here.
#
# Usage: scripts/release-testflight.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

PROVISIONING_PROFILE_SPECIFIER="PoolPlanner Distribution"
CODE_SIGN_IDENTITY="Apple Distribution"

# First match wins: a PoolPlanner-specific env, else the shared team key.
for candidate in "$HOME/.poolplanner/release.env" "$HOME/.plantatlas/lube-release.env"; do
  if [ -f "$candidate" ]; then
    # shellcheck source=/dev/null
    source "$candidate"
    echo "==> Using API credentials from $candidate"
    break
  fi
done

: "${APP_STORE_CONNECT_API_KEY_ID:?Set APP_STORE_CONNECT_API_KEY_ID — see docs/ios-testflight-release.md}"
: "${APP_STORE_CONNECT_API_KEY_ISSUER_ID:?Set APP_STORE_CONNECT_API_KEY_ISSUER_ID}"
: "${APP_STORE_CONNECT_API_KEY_PATH:?Set APP_STORE_CONNECT_API_KEY_PATH to your AuthKey_*.p8}"

if [ ! -f "$APP_STORE_CONNECT_API_KEY_PATH" ]; then
  echo "error: API key file not found at $APP_STORE_CONNECT_API_KEY_PATH" >&2; exit 1
fi
if ! security find-identity -v -p codesigning | grep -q "Apple Distribution"; then
  echo "error: no 'Apple Distribution' certificate in this Mac's keychain" >&2; exit 1
fi

PROFILE_DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
[ -d "$PROFILE_DIR" ] || PROFILE_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
if ! grep -rlq "$PROVISIONING_PROFILE_SPECIFIER" "$PROFILE_DIR" 2>/dev/null; then
  echo "error: no '$PROVISIONING_PROFILE_SPECIFIER' profile installed in $PROFILE_DIR" >&2
  echo "       Create an App Store profile for com.samir.PoolPlanner and double-click it." >&2
  exit 1
fi

# project.yml is the source of truth; regenerate so the archive cannot use a stale pbxproj.
if command -v xcodegen >/dev/null 2>&1; then
  echo "==> Regenerating the Xcode project from project.yml"
  (cd ios && xcodegen generate)
else
  echo "warning: xcodegen not installed — archiving whatever pbxproj is committed" >&2
fi

echo "==> Version being uploaded"
grep -E "MARKETING_VERSION|CURRENT_PROJECT_VERSION" ios/project.yml

# Pick whatever iPad simulator this Mac actually has. Hardcoding a name
# resolves to OS:latest, which fails whenever that model only exists on an
# older runtime.
SIM_UDID="$(xcrun simctl list devices available --json | python3 -c '
import json, sys
runtimes = json.load(sys.stdin)["devices"]
best = None
for runtime, devices in runtimes.items():
    if "iOS" not in runtime:
        continue
    for dev in devices:
        if dev.get("isAvailable") and "iPad" in dev["name"]:
            if best is None or runtime > best[0]:
                best = (runtime, dev["udid"], dev["name"])
print(best[1] if best else "")
')"
if [ -z "$SIM_UDID" ]; then
  echo "error: no available iPad simulator to run tests on" >&2; exit 1
fi

echo "==> Running tests before shipping (simulator $SIM_UDID)"
xcodebuild test -project ios/PoolPlanner.xcodeproj -scheme PoolPlanner \
  -destination "platform=iOS Simulator,arch=arm64,id=$SIM_UDID" \
  -quiet

ARCHIVE_PATH="$(mktemp -d)/PoolPlanner.xcarchive"
EXPORT_PATH="$(mktemp -d)/PoolPlannerExport"
TEAM_ID="$(/usr/libexec/PlistBuddy -c "Print :teamID" ios/ExportOptions.plist)"

echo "==> Archiving (slow step, several minutes)"
xcodebuild archive \
  -project ios/PoolPlanner.xcodeproj \
  -scheme PoolPlanner \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=iOS" \
  CODE_SIGN_STYLE=Manual \
  PROVISIONING_PROFILE_SPECIFIER="$PROVISIONING_PROFILE_SPECIFIER" \
  CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM_ID"

echo "==> Exporting + uploading to TestFlight"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist ios/ExportOptions.plist \
  -authenticationKeyPath "$APP_STORE_CONNECT_API_KEY_PATH" \
  -authenticationKeyID "$APP_STORE_CONNECT_API_KEY_ID" \
  -authenticationKeyIssuerID "$APP_STORE_CONNECT_API_KEY_ISSUER_ID"

echo "==> Done — uploaded. It appears under TestFlight once Apple finishes processing."
