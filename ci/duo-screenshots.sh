#!/usr/bin/env bash
# Squish on the iPhone Duo simulator: drive the REAL simulated hinge and screenshot the app at each angle.
#
# For each object: launch with `-squishDemo "object=<kind>;duo"` at 180°, wait for the first frames, then
# sweep the hinge down through ANGLES (slowly, at SWEEP_SECS_PER_30 seconds per 30°, so onHingeChange sees a
# continuous fold), let the display switch settle, and capture <object>-<angle>.png. Then close to 0°
# (<object>-closed.png, cover display) and reopen to 170° (<object>-reveal.png).
#
# ---------------------------------------------------------------------------------------------------------
# HINGE DRIVERS (HINGE_DRIVER=auto|hinge|duo-hinge|foldctl, default auto = first one that passes a probe)
#
#  1. hinge      (github.com/artemnovichkov/hinge, `brew install artemnovichkov/tap/hinge`)  PRIMARY
#     Compiles a tiny helper against the iOS Simulator SDK and runs it INSIDE the simulator with
#     `xcrun simctl spawn`; the helper posts Device Hub's vendor HID event (usage page 0xFF61, usage 0x5B)
#     through IOHIDEventSystem and confirms via CoreMotion's CMAngleManager. No Simulator.app, no Device
#     Hub, no host Accessibility/TCC prompt involved, so it should run headless. Only driver with a real
#     60 Hz `sweep`. Verified by its author on Xcode 27.1/27.2 + iOS 27.1 runtime (not by us in CI yet).
#
#  2. duo-hinge  (github.com/tosbaha/duo-fold-control, tools/duo-hinge.m)                  FALLBACK A
#     Host CLI: dlopens /Library/Developer/PrivateFrameworks/CoreSimulator.framework and sends Device Hub's
#     fold message over XPC. A completely different path from (1). README: passes on a headless simulator
#     booted with `simctl boot`, Device Hub closed. Set-only (no sweep) and ~1-1.5 s per call, so sweeps
#     are emulated in SWEEP_STEP-degree steps. The same tool powers that repo's XCUITest bridge
#     (DuoFold.set(degrees:)); see docs/DUO-CI.md for the UI-test variant if simctl screenshots fail.
#
#  3. foldctl    (github.com/tatsuz0u/foldctl, `brew install tatsuz0u/tap/foldctl`)          FALLBACK B
#     Host Swift tool on the private CoreDevice API (DeviceManager + sendBarrier). Set-only, waits for the
#     simulator to report the angle (gives up after 60 s). Also emulated sweeps.
#
#  Not implemented here (heavier, documented in docs/DUO-CI.md): Appium WebDriverAgent >= 16.14.0
#  `POST /wda/device/hingeAngle` / xcuitest-driver `mobile: setSimulatedHingeAngle` (same HID payload as 1,
#  sent from the WDA runner inside the simulator).
#
#  None of the drivers needs a GUI click, so nothing here can block on a permission dialog. If ALL probes
#  fail the script still captures the 180° state of every object and exits 3 (the workflow marks the run
#  failed but keeps the artifact, so the logs show which driver broke and why).
#
# DISPLAYS: the Duo has two (cover 1398x2034 px, inner 2007x2853 px) and `simctl io screenshot` without
# --display fails with "Invalid argument". Sources disagree on the names (hinge README: LCD / LCD-1 or ids
# 1 / 3; blakecrosley.com via `simctl io enumerate`: primary / primary-1), so the script probes the
# candidates once, captures BOTH displays for every shot into raw/, and names the lit (non-black) one
# <object>-<angle>.png. The panel that is off captures as all black.
# Never run `simctl io ... screenConfig` on the Duo: it crash-loops SpringBoard (needs shutdown + boot).
# ---------------------------------------------------------------------------------------------------------
#
# Env: UDID (required), OBJECTS, ANGLES, HINGE_DRIVER, SWEEP_SECS_PER_30 (1.5), SWEEP_STEP (10),
#      SETTLE (2.5), OUT (duo-screens), APP, BUNDLE, DUO_HINGE (path to the duo-hinge binary).
set -uo pipefail

UDID="${UDID:?set UDID to the iPhone Duo simulator}"
OBJECTS="${OBJECTS:-rubberDuck bubbleWrap glassBottle sodaCan}"
ANGLES="${ANGLES:-180 150 120 100 90 75 60 45}"
DRIVER="${HINGE_DRIVER:-auto}"
SECS_PER_30="${SWEEP_SECS_PER_30:-1.5}"
STEP="${SWEEP_STEP:-10}"
SETTLE="${SETTLE:-2.5}"
OUT="${OUT:-duo-screens}"
APP="${APP:-build/Build/Products/Debug-iphonesimulator/Squish.app}"
BUNDLE="${BUNDLE:-com.pravegm.squish}"
DUO_HINGE="${DUO_HINGE:-$HOME/duo-fold-control/tools/duo-hinge}"

mkdir -p "$OUT/logs" "$OUT/raw"
OUT_ABS="$(cd "$OUT" && pwd)"
RUNLOG="$OUT_ABS/logs/run.txt"
POSTURE_LOG="$OUT_ABS/logs/posture.txt"
FAILURES=0

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$RUNLOG" >&2; }

# ---- timeouts: every external call goes through `to <seconds> cmd...` -------------------------------
if command -v gtimeout >/dev/null 2>&1; then TIMEOUT_BIN=gtimeout
elif command -v timeout >/dev/null 2>&1; then TIMEOUT_BIN=timeout
else TIMEOUT_BIN=""; fi
to() {
  local secs="$1"; shift
  if [[ -n "$TIMEOUT_BIN" ]]; then "$TIMEOUT_BIN" -k 5 "$secs" "$@"
  else perl -e 'alarm shift; exec @ARGV or die "exec: $!"' "$secs" "$@"; fi
}

fsleep() { perl -e "select(undef,undef,undef,$1)"; }   # fractional sleep without GNU sleep
awk_calc() { awk "BEGIN { printf \"%.2f\", $1 }"; }

# ---- hinge drivers ----------------------------------------------------------------------------------
drv_set() {   # drv_set <driver> <deg>
  case "$1" in
    hinge)     to 20 hinge -d "$UDID" -t 3 "$2" ;;
    duo-hinge) to 20 "$DUO_HINGE" -d "$UDID" "$2" ;;
    foldctl)   to 75 foldctl "$UDID" --hinge "$2" ;;
  esac
}
drv_probe() {
  local d="$1"
  case "$d" in
    hinge)     command -v hinge >/dev/null 2>&1 || { log "probe hinge: not installed"; return 1; } ;;
    duo-hinge) [[ -x "$DUO_HINGE" ]] || { log "probe duo-hinge: $DUO_HINGE missing"; return 1; } ;;
    foldctl)   command -v foldctl >/dev/null 2>&1 || { log "probe foldctl: not installed"; return 1; } ;;
  esac
  # A real move (180 -> 150 -> 180) must succeed; tools exit non-zero when the sim ignores the event.
  if drv_set "$d" 150 >>"$RUNLOG" 2>&1 && drv_set "$d" 180 >>"$RUNLOG" 2>&1; then
    log "probe $d: OK"; return 0
  fi
  log "probe $d: FAILED (see output above)"; return 1
}

CUR=180
hinge_to() {   # hinge_to <deg>: continuous move from CUR to deg, then confirm the final angle
  local target="$1" span secs
  span=$(( target > CUR ? target - CUR : CUR - target ))
  if (( span == 0 )); then drv_set "$DRIVER" "$target" >>"$RUNLOG" 2>&1; return; fi
  secs=$(awk_calc "$span / 30 * $SECS_PER_30")
  log "hinge $CUR -> $target over ${secs}s ($DRIVER)"
  if [[ "$DRIVER" == hinge ]]; then
    to $(( ${secs%.*} + 20 )) hinge -d "$UDID" sweep "$CUR" "$target" "$secs" >>"$RUNLOG" 2>&1 \
      || log "WARN sweep exited non-zero"
  else
    # Set-only drivers: step SWEEP_STEP degrees at a time (each call already takes ~1 s).
    local a="$CUR" dir=$(( target > CUR ? STEP : -STEP ))
    while (( (dir > 0 && a + dir < target) || (dir < 0 && a + dir > target) )); do
      a=$(( a + dir ))
      drv_set "$DRIVER" "$a" >>"$RUNLOG" 2>&1 || log "WARN step to $a failed"
    done
  fi
  # Sweep doesn't confirm its last value; a confirmed set does (hinge -t 3 / foldctl waits).
  drv_set "$DRIVER" "$target" >>"$RUNLOG" 2>&1 || { log "WARN hinge did not confirm $target"; FAILURES=$((FAILURES+1)); }
  CUR="$target"
}

record_posture() {
  { echo "== $1 (set ${CUR}°)"
    if command -v hinge >/dev/null 2>&1; then to 20 hinge -d "$UDID" posture 2>&1; fi
    to 20 xcrun devicectl device info displays -d "$UDID" -q -j - 2>/dev/null \
      | plutil -convert json -o - - 2>/dev/null | head -c 2000; echo
  } >>"$POSTURE_LOG" 2>&1 || true
}

# ---- displays & screenshots -------------------------------------------------------------------------
INNER_DISPLAY=""; COVER_DISPLAY=""
probe_displays() {
  log "simctl io enumerate:"; to 30 xcrun simctl io "$UDID" enumerate >>"$RUNLOG" 2>&1 || log "(enumerate unsupported)"
  local c
  for c in LCD-1 primary-1 3 internal; do
    if to 30 xcrun simctl io "$UDID" screenshot --display="$c" "$OUT_ABS/raw/_probe.png" >/dev/null 2>>"$RUNLOG"; then
      INNER_DISPLAY="$c"; break; fi
  done
  for c in LCD primary 1 external; do
    [[ "$c" == "$INNER_DISPLAY" ]] && continue
    if to 30 xcrun simctl io "$UDID" screenshot --display="$c" "$OUT_ABS/raw/_probe.png" >/dev/null 2>>"$RUNLOG"; then
      COVER_DISPLAY="$c"; break; fi
  done
  rm -f "$OUT_ABS/raw/_probe.png"
  log "displays: inner='${INNER_DISPLAY:-?}' cover='${COVER_DISPLAY:-?}'"
}

# Mean brightness 0-255 of a PNG (sips downscales to a 16x16 BMP; python reads its pixels). -1 on error.
brightness() {
  local tmp="$OUT_ABS/raw/_b.bmp"
  to 20 sips -z 16 16 -s format bmp "$1" --out "$tmp" >/dev/null 2>&1 || { echo -1; return; }
  python3 -I - "$tmp" <<'PY' 2>/dev/null || echo -1
import struct, sys
b = open(sys.argv[1], "rb").read()
off = struct.unpack_from("<I", b, 10)[0]; w, h = struct.unpack_from("<ii", b, 18); bpp = struct.unpack_from("<H", b, 28)[0]
step = bpp // 8; row = (w * step + 3) & ~3; tot = n = 0
for y in range(abs(h)):
    for x in range(w):
        p = off + y * row + x * step; tot += b[p] + b[p + 1] + b[p + 2]; n += 3
print(int(tot / n))
PY
  rm -f "$tmp"
}

shoot() {   # shoot <name> <expected: inner|cover>
  local name="$1" expect="$2" ib=-1 cb=-1 pick=""
  if [[ -n "$INNER_DISPLAY" ]]; then
    to 30 xcrun simctl io "$UDID" screenshot --display="$INNER_DISPLAY" "$OUT_ABS/raw/$name-inner.png" >/dev/null 2>>"$RUNLOG" \
      && ib=$(brightness "$OUT_ABS/raw/$name-inner.png")
  fi
  if [[ -n "$COVER_DISPLAY" ]]; then
    to 30 xcrun simctl io "$UDID" screenshot --display="$COVER_DISPLAY" "$OUT_ABS/raw/$name-cover.png" >/dev/null 2>>"$RUNLOG" \
      && cb=$(brightness "$OUT_ABS/raw/$name-cover.png")
  fi
  if [[ -z "$INNER_DISPLAY$COVER_DISPLAY" ]]; then   # no --display name worked: last resort
    to 30 xcrun simctl io "$UDID" screenshot "$OUT_ABS/$name.png" >/dev/null 2>>"$RUNLOG" || log "WARN screenshot failed: $name"
    return
  fi
  # Lit panel wins; if both or neither are lit, take the one the angle should be on.
  if (( ib > 6 && cb <= 6 )); then pick=inner
  elif (( cb > 6 && ib <= 6 )); then pick=cover
  else pick="$expect"; fi
  [[ -f "$OUT_ABS/raw/$name-$pick.png" ]] && cp "$OUT_ABS/raw/$name-$pick.png" "$OUT_ABS/$name.png"
  [[ "$pick" != "$expect" ]] && log "NOTE $name: expected $expect display, lit one is $pick"
  (( ib <= 6 && cb <= 6 )) && { log "WARN $name: both displays black"; FAILURES=$((FAILURES+1)); }
  log "captured $name (inner=$ib cover=$cb -> $pick)"
  record_posture "$name"
}

# Wait for the app's "SQUISH-T frame 120" line (DemoMode stdout), at most $2 seconds.
wait_first_render() {
  local logf="$1" max="$2" t=0
  while (( t < max )); do
    grep -q "SQUISH-T frame 120" "$logf" 2>/dev/null && { log "first render after ~${t}s"; return 0; }
    sleep 1; t=$((t + 1))
  done
  log "WARN no 'frame 120' line after ${max}s; continuing"; return 1
}

# ---- main -------------------------------------------------------------------------------------------
log "UDID=$UDID driver=$DRIVER objects=[$OBJECTS] angles=[$ANGLES] timeout=${TIMEOUT_BIN:-perl-alarm}"
to 60 xcrun simctl bootstatus "$UDID" -b >>"$RUNLOG" 2>&1 || log "WARN bootstatus timed out"
to 180 xcrun simctl install "$UDID" "$APP" || { log "install failed"; exit 1; }

if [[ "$DRIVER" == auto ]]; then
  DRIVER=none
  for d in hinge duo-hinge foldctl; do drv_probe "$d" && { DRIVER="$d"; break; }; done
elif ! drv_probe "$DRIVER"; then
  DRIVER=none
fi
log "hinge driver: $DRIVER"
probe_displays

for obj in $OBJECTS; do
  log "=== $obj"
  [[ "$DRIVER" != none ]] && { drv_set "$DRIVER" 180 >>"$RUNLOG" 2>&1; CUR=180; fsleep "$SETTLE"; }
  applog="$OUT_ABS/logs/$obj.txt"; : >"$applog"
  to 30 xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  to 60 xcrun simctl launch --terminate-running-process --stdout="$applog" --stderr="$applog" \
    "$UDID" "$BUNDLE" -squishDemo "object=$obj;duo" >>"$RUNLOG" 2>&1 || { log "launch failed: $obj"; FAILURES=$((FAILURES+1)); continue; }
  wait_first_render "$applog" 45
  fsleep 1.5

  if [[ "$DRIVER" == none ]]; then shoot "$obj-180" inner; continue; fi

  for a in $ANGLES; do
    hinge_to "$a"
    fsleep "$SETTLE"
    shoot "$obj-$a" inner          # closing from flat, the inner panel stays lit down to ~20°
  done
  hinge_to 0;   fsleep "$SETTLE"; fsleep 1; shoot "$obj-closed" cover
  hinge_to 170; fsleep "$SETTLE"; fsleep 1.5; shoot "$obj-reveal" inner   # reopening past ~150° wakes the inner panel
  grep -c "SQUISH-H" "$applog" >/dev/null 2>&1 \
    && log "$obj: $(grep -c SQUISH-H "$applog") hinge lines in app log" \
    || log "NOTE $obj: no SQUISH-H lines in app log (app does not print hinge samples, or onHingeChange never fired)"
done

to 30 xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
ls -1 "$OUT_ABS" | tee -a "$RUNLOG"
if [[ "$DRIVER" == none ]]; then log "FAIL: no hinge driver worked; only 180° captured"; exit 3; fi
(( FAILURES > 0 )) && log "finished with $FAILURES warnings"
exit 0
