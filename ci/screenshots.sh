#!/usr/bin/env bash
# Boots the simulator, installs the built app and captures one screenshot per demo scenario.
# Scenarios are listed in ci/scenarios.txt as `name|scenario[|delaySeconds]` and interpreted by the app's
# DemoMode (DEBUG builds only). Set SCENARIO_FILTER to a regex to run a subset (matched against the name).
# Each run's app stdout/stderr goes to ci-screens/logs/<name>.txt; a scenario with `exportclip` also
# copies the rendered share clip to ci-screens/<name>.mp4, and one with `storeshot` copies the folded-device store
# shots the app wrote (Documents/storeshot-*.png, FoldStoreShot.swift) to ci-screens/<name>-storeshot-*.png.
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
  if [[ "$scenario" == *storeshot* ]]; then
    # Never upload a stale store shot from an earlier scenario.
    DATA=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data 2>/dev/null || true)
    if [[ -n "$DATA" ]]; then rm -f "$DATA"/Documents/storeshot-*.png; fi
  fi
  xcrun simctl launch --terminate-running-process \
    --stdout="$PWD/$OUT/logs/$name.txt" --stderr="$PWD/$OUT/logs/$name.txt" \
    "$UDID" "$BUNDLE" -squishDemo "$scenario" >/dev/null
  # Scripted presses: wait for the app to report the scripted state is reached (the CI simulator renders slowly),
  # then let animations settle. Everything else: a fixed delay.
  log="$OUT/logs/$name.txt"
  marker=""
  [[ "$scenario" == *depth=* || "$scenario" == *reveal* ]] && marker="SQUISH-T demo press done"
  [[ "$scenario" == *foldsim=* ]] && marker="SQUISH-T foldsim done"
  [[ "$scenario" == *exportclip* ]] && marker="SQUISH-CLIP (ok|failed)"
  [[ "$scenario" == *storeshot* ]] && marker="SQUISH-T storeshot done"
  if [[ -n "$marker" ]]; then
    for _ in $(seq 1 "$(( delay > 120 ? delay : 120 ))"); do grep -qE "$marker" "$log" 2>/dev/null && break; sleep 1; done
    [[ "$scenario" == *reveal* ]] && sleep 6 || sleep 3
  else
    sleep "$delay"
  fi
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >/dev/null
  if [[ "$scenario" == *exportclip* ]]; then
    DATA=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)
    cp "$DATA/Documents/clip.mp4" "$OUT/$name.mp4" 2>/dev/null || echo "no clip produced for $name"
    grep -h "SQUISH-CLIP" "$OUT/logs/$name.txt" || true
  fi
  if [[ "$scenario" == *storeshot* ]]; then
    DATA=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data 2>/dev/null || true)
    found=0
    if [[ -n "$DATA" ]]; then
      for f in "$DATA"/Documents/storeshot-*.png; do
        [[ -e "$f" ]] || continue
        cp "$f" "$OUT/$name-$(basename "$f")"
        found=$((found + 1))
      done
    fi
    echo "store shots for $name: $found"
    grep -h "SQUISH-T storeshot" "$OUT/logs/$name.txt" || true
  fi
  echo "captured $name ($scenario)"
done < ci/scenarios.txt

xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true

# App Store icon master: 85-icon shows AppIconArt as a full-width square centred on the screen
# (iPhone 18 Pro: 1206×2622 px, so a 1206² square at y = (2622 − 1206) / 2 = 708). Crop it, scale it to 1024²,
# then flatten it onto opaque sRGB with no alpha channel (App Store Connect rejects icons with alpha, ITMS-90717).
# sips argument order: --cropToHeightWidth <height> <width>, --cropOffset <offsetY> <offsetX>.
ICON_SRC="$OUT/85-icon.png"
if [[ -f "$ICON_SRC" ]]; then
  W=$(sips -g pixelWidth "$ICON_SRC" | awk '/pixelWidth/ {print $2}')
  H=$(sips -g pixelHeight "$ICON_SRC" | awk '/pixelHeight/ {print $2}')
  Y=$(( (H - W) / 2 ))
  sips --cropToHeightWidth "$W" "$W" --cropOffset "$Y" 0 "$ICON_SRC" --out "$OUT/AppIcon-square.png" >/dev/null
  sips --resampleHeightWidth 1024 1024 "$OUT/AppIcon-square.png" --out "$OUT/AppIcon-1024.png" >/dev/null
  rm -f "$OUT/AppIcon-square.png"
  FLATTEN="$(mktemp -d)/flatten-icon.swift"
  cat > "$FLATTEN" <<'SWIFT'
import CoreGraphics
import Foundation
import ImageIO
// Redraws a PNG onto an opaque sRGB canvas (no alpha channel) in place, and checks the crop landed on the art.
let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let space = CGColorSpace(name: CGColorSpace.sRGB),
      let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                          space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { exit(1) }
let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
ctx.setFillColor(CGColor(srgbRed: 0.17, green: 0.18, blue: 0.19, alpha: 1))
ctx.fill(rect)
ctx.draw(image, in: rect)
guard let flat = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(dest, flat, nil)
guard CGImageDestinationFinalize(dest) else { exit(1) }
// The art's corners are graphite, never the demo's pure black margin: black corners mean the crop missed.
if let data = ctx.data?.assumingMemoryBound(to: UInt8.self) {
  let row = ctx.bytesPerRow, last = (image.height - 1) * row + (image.width - 1) * 4
  if (data[0] < 8 && data[1] < 8 && data[2] < 8) || (data[last] < 8 && data[last + 1] < 8 && data[last + 2] < 8) {
    print("warning: AppIcon-1024.png has black corners; check the 85-icon crop")
  }
}
SWIFT
  xcrun swift "$FLATTEN" "$OUT/AppIcon-1024.png" || echo "warning: could not flatten AppIcon-1024.png (alpha may remain)"
  rm -f "$FLATTEN"
  sips -g pixelWidth -g pixelHeight -g hasAlpha "$OUT/AppIcon-1024.png"
  echo "exported $OUT/AppIcon-1024.png"
fi
