#!/usr/bin/env bash
# Boots the simulator, installs the built app and captures one screenshot per demo scenario.
# Scenarios are listed in ci/scenarios.txt as `name|scenario[|delaySeconds]` and interpreted by the app's
# DemoMode (DEBUG builds only). Set SCENARIO_FILTER to a regex to run a subset (matched against the name).
# Each run's app stdout/stderr goes to ci-screens/logs/<name>.txt; a scenario with `exportclip` also
# copies the rendered share clip to ci-screens/<name>.mp4.
set -euo pipefail

DEVICE="${DEVICE:-iPhone 18 Pro}"
APP="build/Build/Products/Debug-iphonesimulator/Squish.app"
BUNDLE="com.pravegm.squish"
OUT="ci-screens"
FILTER="${SCENARIO_FILTER:-.}"
mkdir -p "$OUT/logs"

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
  IFS='|' read -r name scenario delay <<< "$line"
  [[ "$name" =~ $FILTER ]] || continue
  delay="${delay:-${SHOT_DELAY:-11}}"
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  xcrun simctl launch --terminate-running-process \
    --stdout="$PWD/$OUT/logs/$name.txt" --stderr="$PWD/$OUT/logs/$name.txt" \
    "$UDID" "$BUNDLE" -squishDemo "$scenario" >/dev/null
  sleep "$delay"
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >/dev/null
  if [[ "$scenario" == *exportclip* ]]; then
    DATA=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)
    cp "$DATA/Documents/clip.mp4" "$OUT/$name.mp4" 2>/dev/null || echo "no clip produced for $name"
    grep -h "SQUISH-CLIP" "$OUT/logs/$name.txt" || true
  fi
  echo "captured $name ($scenario)"
done < ci/scenarios.txt

xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
