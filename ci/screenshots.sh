#!/usr/bin/env bash
# Boots the simulator, installs the built app and captures one screenshot per demo scenario.
# Scenarios are listed in ci/scenarios.txt as `name|scenario[|delaySeconds[|caption]]` and interpreted by the app's
# DemoMode (DEBUG builds only). Set SCENARIO_FILTER to a regex to run a subset (matched against the name).
# Each run's app stdout/stderr goes to $OUT/logs/<name>.txt; a scenario with `exportclip` also
# copies the rendered share clip to $OUT/<name>.mp4, and one with `storeshot` copies the folded-device store
# shots the app wrote (Documents/storeshot-*.png, FoldStoreShot.swift) to $OUT/<name>-storeshot-*.png, after the
# app's "SQUISH-T storeshot done" line (`storeshot=112,fail` adds storeshot-hero.png and storeshot-pair.png).
#
# Env:
#  DEVICE        simulator name (default "iPhone 18 Pro"), or `auto:<suffix>` for the newest available iPhone whose
#                name ends with <suffix>, e.g. `auto:Pro Max` for the 6.9" class (iPhone 18 Pro Max, 1320 × 2868). If
#                none exists, one is created from the newest matching device type on the newest iOS runtime.
#  OUT           output folder (default ci-screens).
#  EXPECT_SIZE   e.g. 1320x2868: warn per frame, and exit 4 at the end, if a screenshot is another size.
#  STORE_FRAMES  1 = for every scenario with a caption column, also write $OUT/store/<name>.png: the raw screenshot
#                on the studio sweep under its App Store caption (ci/store-frame.swift, style framed).
#  STORE_ISLAND  pill (default) = store-frame draws the Dynamic Island on every captioned frame, because the simulator
#                captures it in some frames and not others (FOLD-REVIEW-6 N13); none = leave the capture as it is.
set -euo pipefail

DEVICE="${DEVICE:-iPhone 18 Pro}"
APP="build/Build/Products/Debug-iphonesimulator/Squish.app"
BUNDLE="com.pravegm.squish"
OUT="${OUT:-ci-screens}"
FILTER="${SCENARIO_FILTER:-.}"
EXPECT_SIZE="${EXPECT_SIZE:-}"
STORE_FRAMES="${STORE_FRAMES:-0}"
STORE_ISLAND="${STORE_ISLAND:-pill}"
mkdir -p "$OUT/logs"
# shellcheck source=ci/store-frame.sh
source "$(dirname "$0")/store-frame.sh"

echo "device types matching 'Pro Max' (for the 6.9-inch set):"
xcrun simctl list devicetypes | grep -i "pro max" || echo "  (none)"

# Prints "<udid><TAB><name>" for DEVICE, or "CREATE<TAB><type id><TAB><runtime id><TAB><name>" when an `auto:`
# device has to be created. Exits 1 when nothing matches.
RESOLVE_PY='
import json, re, subprocess, sys
want = sys.argv[1]
auto = want.startswith("auto:")
suffix = want[5:] if auto else ""
def model(name):
    m = re.search(r"iPhone (\d+)", name)
    return int(m.group(1)) if m else 0
def runtime_version(identifier):
    m = re.search(r"iOS-(\d+)-(\d+)", identifier)
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)
devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))["devices"]
found = []
for runtime, entries in devices.items():
    if "iOS" not in runtime:
        continue
    for d in entries:
        name = d["name"]
        if (auto and name.startswith("iPhone") and name.endswith(suffix)) or (not auto and name == want):
            found.append(((model(name), runtime_version(runtime)), d["udid"], name))
if found:
    found.sort(reverse=True)
    print(found[0][1] + "\t" + found[0][2])
    sys.exit(0)
if not auto:
    sys.exit(1)
listing = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "-j", "devicetypes", "runtimes"]))
types = sorted((t for t in listing["devicetypes"] if t["name"].startswith("iPhone") and t["name"].endswith(suffix)),
               key=lambda t: model(t["name"]), reverse=True)
runtimes = sorted((r for r in listing["runtimes"] if r.get("isAvailable") and "iOS" in r["identifier"]),
                  key=lambda r: runtime_version(r["identifier"]), reverse=True)
for t in types:
    for r in runtimes:
        supported = r.get("supportedDeviceTypes")
        if supported is None or any(s.get("identifier") == t["identifier"] for s in supported):
            print("CREATE\t" + t["identifier"] + "\t" + r["identifier"] + "\t" + t["name"])
            sys.exit(0)
sys.exit(1)
'
RESOLVED=$(python3 -I -c "$RESOLVE_PY" "$DEVICE") \
  || { echo "error: no simulator matches DEVICE='$DEVICE'"; xcrun simctl list devices available; exit 1; }

if [[ "$RESOLVED" == CREATE* ]]; then
  IFS=$'\t' read -r _ TYPE_ID RUNTIME_ID DEVICE_NAME <<< "$RESOLVED"
  echo "creating '$DEVICE_NAME' ($TYPE_ID, $RUNTIME_ID)"
  UDID=$(xcrun simctl create "$DEVICE_NAME" "$TYPE_ID" "$RUNTIME_ID")
else
  IFS=$'\t' read -r UDID DEVICE_NAME <<< "$RESOLVED"
fi
echo "simulator: $DEVICE_NAME ($UDID)"
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 || true
xcrun simctl install "$UDID" "$APP"

SIZE_MISMATCH=0
while IFS= read -r line; do
  [[ -z "$line" || "$line" == \#* ]] && continue
  IFS='|' read -r name scenario delay caption <<< "$line"
  [[ "$name" =~ $FILTER ]] || continue
  delay="${delay:-${SHOT_DELAY:-11}}"
  caption="${caption:-}"
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
  if [[ -n "$EXPECT_SIZE" ]]; then
    got=$(png_size "$OUT/$name.png")
    if [[ "${got%% *}" != "$EXPECT_SIZE" ]]; then
      echo "warning: $name is $got, expected $EXPECT_SIZE"
      SIZE_MISMATCH=1
    fi
  fi
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
  if [[ "$STORE_FRAMES" == 1 && -n "$caption" ]]; then
    mkdir -p "$OUT/store"
    island=()
    [[ "$STORE_ISLAND" == pill ]] && island=(--island pill)
    store_frame --in "$OUT/$name.png" --out "$OUT/store/$name.png" --style framed --caption "$caption" ${island[@]+"${island[@]}"} \
      || echo "warning: store frame failed for $name"
  fi
  echo "captured $name ($scenario)"
done < ci/scenarios.txt

xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true

if [[ -d "$OUT/store" ]]; then
  echo "store frames ($DEVICE_NAME):"
  for f in "$OUT"/store/*.png; do if [[ -e "$f" ]]; then echo "  $(basename "$f") $(png_size "$f")"; fi; done
fi

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

if (( SIZE_MISMATCH == 1 )); then
  echo "error: some screenshots are not $EXPECT_SIZE (is $DEVICE_NAME the right device class?)"
  exit 4
fi
