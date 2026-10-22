#!/usr/bin/env bash
# Boots the simulator, installs the built app and captures one screenshot per demo scenario.
# Scenarios are listed in ci/scenarios.txt and interpreted by the app's DemoMode (DEBUG builds only).
set -euo pipefail

DEVICE="${DEVICE:-iPhone 18 Pro}"
APP="build/Build/Products/Debug-iphonesimulator/Squish.app"
BUNDLE="com.pravegm.squish"
OUT="ci-screens"
mkdir -p "$OUT"

UDID=$(xcrun simctl list devices available -j | python3 -c "
import json, sys
data = json.load(sys.stdin)
for runtime, devices in data['devices'].items():
    for d in devices:
        if d['name'] == '$DEVICE':
            print(d['udid']); sys.exit(0)
")
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 || true
xcrun simctl install "$UDID" "$APP"

while IFS= read -r line; do
  [[ -z "$line" || "$line" == \#* ]] && continue
  name="${line%%|*}"
  scenario="${line#*|}"
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE" -squishDemo "$scenario" >/dev/null
  sleep 7
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >/dev/null
  echo "captured $name ($scenario)"
done < ci/scenarios.txt

xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
