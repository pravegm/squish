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
# PASS 1, BOOK POSE (the Duo simulator's own orientation: landscape inner display, vertical fold): every object in
# OBJECTS at every angle in ANGLES, launched with `object=<kind>;duo;notoasts`. These are the raw-frame review set.
# For objects in BOOK_STORESHOT_OBJECTS the app also writes book-pose store shots at STORESHOT_ANGLES (FOLD-REVIEW-3
# N1); they are copied as <object>-book-storeshot-<angle>[-eye].png and are CI E-check artefacts only, never marketing
# (FOLD-REVIEW-4 F1: a book page in a third-person view is a wall, and its UI text lies sideways on a tabletop model).
#
# PASS 2, TABLETOP STORE SHOTS (FOLD-REVIEW-4 #1/#2): for each object in STORESHOT_OBJECTS the app is launched with
# `object=<kind>;duo;notoasts;orient=portrait;storeshot=<STORESHOT_SHOTS>;storeshotfailangle=<FAIL_HOLD>`.
#  - Orientation: `simctl` has no rotate (`simctl io` only screenshots/records/enumerates, and `io … screenConfig`
#    crash-loops SpringBoard on the Duo). So the app itself asks its window scene for portrait
#    (UIWindowScene.requestGeometryUpdate, DEBUG demo key `orient`), which gives the 669 × 951 tabletop canvas with a
#    horizontal fold, and logs `SQUISH-T orient portrait ok`. The script waits for that line (ORIENT_WAIT). If it never
#    comes and ORIENT_FALLBACK=applescript, it opens the simulator app (SIM_APP, default Simulator) and sends Rotate Left
#    (⌘←) through System Events. That needs a GUI session and Accessibility (TCC) for osascript, so it is opt-in and
#    untested. If the interface stays book, the shots still render (book content laid down as a laptop, UI text
#    sideways) and the run logs a WARN.
#  - The hinge sweeps TABLETOP_ANGLES (raw inner frames <object>-tabletop-<angle>.png). At each numeric angle in
#    STORESHOT_SHOTS the app writes storeshot-<angle>.png once the hinge is still; `fail` makes it write the hero
#    (storeshot-hero.png: failure freeze, caption, escaped splat) at the first hold at or below FAIL_HOLD after the
#    object failed, then the before/after frame (storeshot-pair.png, the 112° shot beside the hero). The script waits
#    for each `SQUISH-T storeshot <label> ok|failed` line, then copies Documents/storeshot-*.png to
#    <object>-storeshot-*.png: rubberDuck-storeshot-hero.png, rubberDuck-storeshot-112.png, rubberDuck-storeshot-pair.png
#    (+ -eye E-check composites; -land / -69 with STORESHOT_SIZE=both|all).
#  - The pair labels quote each device's crown readout ("111°" → "AT 83°"), never the model angle (FOLD-REVIEW-5 §3 a),
#    so the hero is held at FAIL_HOLD (the deepest squeeze) whatever angle the object failed at.
#  - `reveal` in STORESHOT_SHOTS (FOLD-REVIEW-5 N4): after the last hold the hinge closes to 0° (<object>-tabletop-closed
#    .png, the cover's sealed card: the O1 source) and reopens to REVEAL_ANGLE (<object>-tabletop-reveal.png raw); the
#    app writes storeshot-reveal.png (the reveal on the tabletop model, with its print label and console keys).
#  - Every hero's halves are also kept in Documents (storehalves-<kind>-*) for pass 4.
#
#  - FOLD-REVIEW-6 N2 check: at the reopened capture the latest SQUISH-H line must say phase=revealing. If it doesn't,
#    the run logs a WARN and writes "<object> missing …" to logs/reveal-checks.txt, and ci/store-set.sh marks that
#    reveal frame MISSING in the MANIFEST, so a reveal can never be silently replaced by the next object.
#  - Every tabletop launch pins STORESHOT_SEED (default 3: not Golden, no surprise for any object, a lime can fizz;
#    FOLD-REVIEW-6 N6); the app logs kind=/seed=/golden=/surprise= on every store-shot line. Empty = random per launch.
#
# PASS 3, DUO UI FRAMES (DUO_UI, default "shelf cover settings"; empty = none): raw inner/cover frames for the store set,
# captioned later by ci/store-set.sh. shelf / settings: portrait launch at 180° with the seeded 7/10 collection
# (one Golden) and the sheet open → duo-shelf.png (the Duo opens the shelf at .large) / duo-settings.png. Settings shows
# what its caption says (FOLD-REVIEW-6 N5): Soft sound, Press without folding and Captions on (demo keys, in memory only),
# and `gamecenter=hidden` hides the Game Center row's "NOT AVAILABLE". It runs last anyway, so no other frame can
# inherit those settings. cover: launch with the hinge already shut and 7 seeded specimens → duo-cover-launch.png
# (outer display: the idle cover picker, O2). Nothing presses it; the run warns if the log shows the engine leaving idle.
#
# PASS 4, VARIETY GRID (STOREGRID_OBJECTS, default "glassBottle sodaCan cakeSlice jelly"; empty = none): one launch with
# `duo;storegrid=…` renders the saved heroes side by side → duo-storeshot-grid.png. Objects without a hero this run
# are skipped, so list only objects in STORESHOT_OBJECTS.
#
# Env: UDID (required), OBJECTS, ANGLES, HINGE_DRIVER, SWEEP_SECS_PER_30 (1.5), SWEEP_STEP (10),
#      SETTLE (2.5), OUT (duo-screens), APP, BUNDLE, DUO_HINGE (path to the duo-hinge binary),
#      BOOK_STORESHOT_OBJECTS (rubberDuck; empty = none), STORESHOT_ANGLES (120 75; book pass),
#      STORESHOT_OBJECTS (rubberDuck glassBottle sodaCan cakeSlice jelly; empty = no tabletop pass),
#      STORESHOT_SHOTS (112,fail,reveal), STORESHOT_SEED (3; empty = random),
#      TABLETOP_ANGLES (150 112 90 75 62 45), FAIL_HOLD (62), STORESHOT_SIZE (portrait), STORESHOT_WAIT (60 s per shot),
#      ORIENT (portrait), ORIENT_WAIT (40 s), ORIENT_FALLBACK (none|applescript), SIM_APP (Simulator),
#      REVEAL_ANGLE (155), DUO_UI (shelf cover settings), STOREGRID_OBJECTS (glassBottle sodaCan cakeSlice jelly).
#      OBJECTS, STORESHOT_OBJECTS, DUO_UI and STOREGRID_OBJECTS may be set empty to skip that pass.
set -uo pipefail

UDID="${UDID:?set UDID to the iPhone Duo simulator}"
OBJECTS="${OBJECTS-rubberDuck bubbleWrap glassBottle sodaCan}"
ANGLES="${ANGLES:-180 150 120 100 90 75 60 45}"
DRIVER="${HINGE_DRIVER:-auto}"
SECS_PER_30="${SWEEP_SECS_PER_30:-1.5}"
STEP="${SWEEP_STEP:-10}"
SETTLE="${SETTLE:-2.5}"
OUT="${OUT:-duo-screens}"
APP="${APP:-build/Build/Products/Debug-iphonesimulator/Squish.app}"
BUNDLE="${BUNDLE:-com.pravegm.squish}"
DUO_HINGE="${DUO_HINGE:-$HOME/duo-fold-control/tools/duo-hinge}"
BOOK_STORESHOT_OBJECTS="${BOOK_STORESHOT_OBJECTS-rubberDuck}"
STORESHOT_ANGLES="${STORESHOT_ANGLES-120 75}"
STORESHOT_OBJECTS="${STORESHOT_OBJECTS-rubberDuck glassBottle sodaCan cakeSlice jelly}"
STORESHOT_SHOTS="${STORESHOT_SHOTS-112,fail,reveal}"
STORESHOT_SEED="${STORESHOT_SEED-3}"
TABLETOP_ANGLES="${TABLETOP_ANGLES:-150 112 90 75 62 45}"
FAIL_HOLD="${FAIL_HOLD:-62}"
STORESHOT_SIZE="${STORESHOT_SIZE-portrait}"
STORESHOT_WAIT="${STORESHOT_WAIT:-60}"
ORIENT="${ORIENT:-portrait}"
ORIENT_WAIT="${ORIENT_WAIT:-40}"
ORIENT_FALLBACK="${ORIENT_FALLBACK:-none}"
SIM_APP="${SIM_APP:-Simulator}"
REVEAL_ANGLE="${REVEAL_ANGLE:-155}"
DUO_UI="${DUO_UI-shelf cover settings}"
STOREGRID_OBJECTS="${STOREGRID_OBJECTS-glassBottle sodaCan cakeSlice jelly}"

mkdir -p "$OUT/logs" "$OUT/raw"
OUT_ABS="$(cd "$OUT" && pwd)"
RUNLOG="$OUT_ABS/logs/run.txt"
POSTURE_LOG="$OUT_ABS/logs/posture.txt"
REVEAL_CHECKS="$OUT_ABS/logs/reveal-checks.txt"   # read by ci/store-set.sh: "<object> ok|missing <why>"
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
  # The hinge tool occasionally fails a whole move (store run 39902695582: the duck's reopen from 0° never happened).
  # Retry the confirmed set a few times before counting it as a failure.
  local attempt
  for attempt in 1 2 3; do
    drv_set "$DRIVER" "$target" >>"$RUNLOG" 2>&1 && break
    log "WARN hinge did not confirm $target (attempt $attempt)"
    if (( attempt == 3 )); then FAILURES=$((FAILURES+1)); else sleep 2; fi
  done
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

# Wait for the app's "SQUISH-T storeshot <label> ok|failed" line, at most $3 seconds (label: an angle, hero or pair).
wait_storeshot() {
  local logf="$1" a="$2" max="$3" t=0
  while (( t < max )); do
    if grep -qE "SQUISH-T storeshot $a (ok|failed)" "$logf" 2>/dev/null; then
      log "storeshot $a: $(grep -E "SQUISH-T storeshot $a (ok|failed)" "$logf" | tail -1)"; return 0
    fi
    sleep 1; t=$((t + 1))
  done
  log "WARN no 'SQUISH-T storeshot $a' line after ${max}s"; FAILURES=$((FAILURES+1)); return 1
}

# Wait for the app's "SQUISH-T orient <value> ok" line (DEBUG demo key `orient`), at most $2 seconds.
wait_orient() {
  local logf="$1" max="$2" t=0
  while (( t < max )); do
    if grep -qE "SQUISH-T orient [a-z]+ ok" "$logf" 2>/dev/null; then
      log "orient: $(grep -E 'SQUISH-T orient [a-z]+ ok' "$logf" | tail -1)"; return 0
    fi
    sleep 1; t=$((t + 1))
  done
  log "WARN orient: no 'ok' after ${max}s; last: $(grep 'SQUISH-T orient' "$logf" 2>/dev/null | tail -2 | tr '\n' ' ')"
  return 1
}

# Opt-in fallback (ORIENT_FALLBACK=applescript): rotate the device in the simulator app's window (⌘← = Rotate Left,
# landscapeRight → portrait). Needs a GUI login session and Accessibility permission for osascript; untested on the
# hosted runner. The simulator stays booted: the app only attaches a window to it.
rotate_with_sim_app() {
  log "orient fallback: open $SIM_APP and send Rotate Left"
  to 30 open -a "$SIM_APP" --args -CurrentDeviceUDID "$UDID" >>"$RUNLOG" 2>&1 || { log "WARN could not open $SIM_APP"; return 1; }
  fsleep 6
  to 20 osascript -e "tell application \"$SIM_APP\" to activate" -e 'delay 1' \
    -e 'tell application "System Events" to key code 123 using command down' >>"$RUNLOG" 2>&1 \
    || { log "WARN osascript rotate failed (Accessibility not granted?)"; return 1; }
  return 0
}

app_data() { to 30 xcrun simctl get_app_container "$UDID" "$BUNDLE" data 2>/dev/null || true; }

# Copy Documents/storeshot-*.png to $OUT/<prefix><file>; prints the count.
copy_store_shots() {
  local prefix="$1" data n=0 f
  data="$(app_data)"
  if [[ -n "$data" ]]; then
    for f in "$data"/Documents/storeshot-*.png; do
      [[ -e "$f" ]] || continue
      cp "$f" "$OUT_ABS/$prefix$(basename "$f")"; n=$((n + 1))
    done
  fi
  echo "$n"
}

clear_store_shots() {
  local data
  data="$(app_data)"
  [[ -n "$data" ]] && rm -f "$data"/Documents/storeshot-*.png
  return 0
}

# FOLD-REVIEW-6 N2: the reveal must still be up when it is captured at ~REVEAL_ANGLE. The latest SQUISH-H line (the app
# prints one per hinge sample, at most every 0.25 s) carries the engine phase; anything but phase=revealing means the
# card was collected (or never came up) and the next object is on the anvil. Logs the verdict, appends it to
# REVEAL_CHECKS for ci/store-set.sh (which then marks the reveal frame MISSING) and counts a failure.
check_reveal() {   # check_reveal <object> <app log>
  local obj="$1" logf="$2" last phase
  last=$(grep "SQUISH-H" "$logf" 2>/dev/null | tail -1)
  phase=""
  if [[ "$last" == *" phase="* ]]; then phase="${last##* phase=}"; phase="${phase%% *}"; fi
  if [[ "$phase" == revealing ]]; then
    log "$obj: reveal check ok (phase=revealing at the ${REVEAL_ANGLE}° capture)"
    echo "$obj ok" >>"$REVEAL_CHECKS"
    return 0
  fi
  log "WARN $obj: REVEAL NOT UP at the ${REVEAL_ANGLE}° capture: latest phase=${phase:-none} (${last:-no SQUISH-H line})."
  log "WARN $obj: the reveal frame is marked MISSING for ci/store-set.sh; it must not be replaced by the next object."
  echo "$obj missing phase=${phase:-none}" >>"$REVEAL_CHECKS"
  FAILURES=$((FAILURES+1))
  return 1
}

# Pass 2 for one object: tabletop (portrait) launch, sweep TABLETOP_ANGLES, wait for the angle shots, the hero and the
# pair, copy them out.
tabletop_pass() {
  local obj="$1" applog scen a n hero=0 wants_hero=0 wants_reveal=0 nums
  applog="$OUT_ABS/logs/$obj-tabletop.txt"; : >"$applog"
  log "=== $obj tabletop store shots (storeshot=$STORESHOT_SHOTS, angles [$TABLETOP_ANGLES])"
  drv_set "$DRIVER" 180 >>"$RUNLOG" 2>&1; CUR=180; fsleep "$SETTLE"
  to 30 xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  clear_store_shots
  scen="object=$obj;duo;notoasts;orient=$ORIENT;storeshot=$STORESHOT_SHOTS;storeshotfailangle=$FAIL_HOLD"
  [[ -n "$STORESHOT_SIZE" ]] && scen="$scen;storeshotsize=$STORESHOT_SIZE"
  [[ -n "$STORESHOT_SEED" ]] && scen="$scen;seed=$STORESHOT_SEED"
  to 60 xcrun simctl launch --terminate-running-process --stdout="$applog" --stderr="$applog" \
    "$UDID" "$BUNDLE" -squishDemo "$scen" >>"$RUNLOG" 2>&1 \
    || { log "launch failed: $obj (tabletop)"; FAILURES=$((FAILURES+1)); return; }
  wait_first_render "$applog" 45
  if ! wait_orient "$applog" "$ORIENT_WAIT"; then
    if [[ "$ORIENT_FALLBACK" == applescript ]] && rotate_with_sim_app && wait_orient "$applog" 20; then
      log "$obj: tabletop via $SIM_APP rotation"
    else
      log "WARN $obj: interface still book; store shots will show book content on the tabletop model (UI text sideways)"
      FAILURES=$((FAILURES+1))
    fi
  fi
  fsleep 1.5

  nums=" $(echo "$STORESHOT_SHOTS" | tr ',' ' ') "
  [[ "$nums" == *" fail "* ]] && wants_hero=1
  [[ "$nums" == *" reveal "* ]] && wants_reveal=1
  for a in $(echo "$STORESHOT_SHOTS" | tr ',' ' '); do
    [[ "$a" == fail || "$a" == reveal ]] && continue
    [[ " $TABLETOP_ANGLES " == *" $a "* ]] || log "WARN storeshot angle $a is not in TABLETOP_ANGLES; the hinge never stops there"
  done
  for a in $TABLETOP_ANGLES; do
    hinge_to "$a"
    fsleep "$SETTLE"
    shoot "$obj-tabletop-$a" inner
    # Hold the hinge until the app has written its store shot for this angle (it shoots ~0.8 s after the hinge stops).
    if [[ "$nums" == *" $a "* ]]; then wait_storeshot "$applog" "$a" "$STORESHOT_WAIT"; fi
    # The hero: only at holds at or below FAIL_HOLD, and only once the app has seen the failure.
    if (( wants_hero == 1 && hero == 0 && a <= FAIL_HOLD + 3 )) && grep -q "SQUISH-T storeshot failure seen" "$applog" 2>/dev/null; then
      wait_storeshot "$applog" hero "$STORESHOT_WAIT" && hero=1
    fi
  done
  if (( wants_hero == 1 )); then
    if (( hero == 0 )); then
      wait_storeshot "$applog" hero 15 && hero=1 \
        || log "WARN $obj: no failure-moment store shot ($(grep -c 'SQUISH-T storeshot failure seen' "$applog" 2>/dev/null) failure lines; did it fail by ${a}°?)"
    fi
    (( hero == 1 )) && wait_storeshot "$applog" pair "$STORESHOT_WAIT"
  fi
  if (( wants_reveal == 1 )); then
    # Seal (the cover shows the sealed card: the O1 source), then reopen past the inner panel's wake (~150°): the
    # engine reveals on the first open sample after a close, and the app shoots once the card is up and the hinge
    # has settled.
    hinge_to 0; fsleep "$SETTLE"; fsleep 1; shoot "$obj-tabletop-closed" cover
    hinge_to "$REVEAL_ANGLE"; fsleep "$SETTLE"; fsleep 1.5; shoot "$obj-tabletop-reveal" inner
    check_reveal "$obj" "$applog"
    wait_storeshot "$applog" reveal "$STORESHOT_WAIT"
  fi
  for _ in $(seq 1 10); do grep -q "SQUISH-T storeshot done" "$applog" 2>/dev/null && break; sleep 1; done
  log "$obj: $(grep -E 'SQUISH-T storeshot done' "$applog" 2>/dev/null | tail -1)"
  n=$(copy_store_shots "$obj-")
  log "$obj: copied $n tabletop store shot file(s)"
  (( n > 0 )) || FAILURES=$((FAILURES+1))
  to 30 xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
}

clear_store_halves() {
  local data
  data="$(app_data)"
  [[ -n "$data" ]] && rm -f "$data"/Documents/storehalves-*
  return 0
}

# Pass 3: one raw Duo UI frame. ui_frame <name> <hinge> <display: inner|cover> <scenario>
ui_frame() {
  local name="$1" deg="$2" display="$3" scen="$4" applog
  applog="$OUT_ABS/logs/$name.txt"; : >"$applog"
  log "=== UI frame $name (hinge ${deg}°, $display): $scen"
  to 30 xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  if [[ "$DRIVER" != none ]]; then hinge_to "$deg"; fsleep "$SETTLE"; fi
  to 60 xcrun simctl launch --terminate-running-process --stdout="$applog" --stderr="$applog" \
    "$UDID" "$BUNDLE" -squishDemo "$scen" >>"$RUNLOG" 2>&1 \
    || { log "launch failed: $name"; FAILURES=$((FAILURES+1)); return; }
  wait_first_render "$applog" 45
  [[ "$scen" == *orient=* ]] && { wait_orient "$applog" "$ORIENT_WAIT" || log "WARN $name: interface not $ORIENT"; }
  fsleep 4   # the demo sheet opens 1.2 s after launch, then animates in
  shoot "$name" "$display"
  to 30 xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
}

# Pass 4: the variety grid from the heroes saved in pass 2.
grid_pass() {
  local applog n csv
  applog="$OUT_ABS/logs/grid.txt"; : >"$applog"
  csv="$(echo $STOREGRID_OBJECTS | tr ' ' ',')"
  log "=== variety grid ($csv)"
  to 30 xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  if [[ "$DRIVER" != none ]]; then hinge_to 180; fsleep "$SETTLE"; fi
  clear_store_shots
  to 60 xcrun simctl launch --terminate-running-process --stdout="$applog" --stderr="$applog" \
    "$UDID" "$BUNDLE" -squishDemo "duo;notoasts;storegrid=$csv" >>"$RUNLOG" 2>&1 \
    || { log "launch failed: grid"; FAILURES=$((FAILURES+1)); return; }
  wait_storeshot "$applog" grid "$STORESHOT_WAIT"
  n=$(copy_store_shots "duo-")
  log "grid: copied $n file(s)"
  (( n > 0 )) || FAILURES=$((FAILURES+1))
  to 30 xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
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

# ---- pass 1: book pose ------------------------------------------------------------------------------
for obj in $OBJECTS; do
  log "=== $obj"
  [[ "$DRIVER" != none ]] && { drv_set "$DRIVER" 180 >>"$RUNLOG" 2>&1; CUR=180; fsleep "$SETTLE"; }
  applog="$OUT_ABS/logs/$obj.txt"; : >"$applog"
  to 30 xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  store=""
  if [[ "$DRIVER" != none && -n "$STORESHOT_ANGLES" && " $BOOK_STORESHOT_OBJECTS " == *" $obj "* ]]; then
    store=";storeshot=$(echo $STORESHOT_ANGLES | tr ' ' ',')"
    clear_store_shots
    for a in $STORESHOT_ANGLES; do
      [[ " $ANGLES " == *" $a "* ]] || log "WARN storeshot angle $a is not in ANGLES; the hinge never stops there"
    done
  fi
  to 60 xcrun simctl launch --terminate-running-process --stdout="$applog" --stderr="$applog" \
    "$UDID" "$BUNDLE" -squishDemo "object=$obj;duo;notoasts$store" >>"$RUNLOG" 2>&1 || { log "launch failed: $obj"; FAILURES=$((FAILURES+1)); continue; }
  wait_first_render "$applog" 45
  fsleep 1.5

  if [[ "$DRIVER" == none ]]; then shoot "$obj-180" inner; continue; fi

  for a in $ANGLES; do
    hinge_to "$a"
    fsleep "$SETTLE"
    shoot "$obj-$a" inner          # closing from flat, the inner panel stays lit down to ~20°
    # Hold the hinge until the app has written its store shot for this angle (it shoots ~0.8 s after the hinge stops).
    if [[ -n "$store" && " $STORESHOT_ANGLES " == *" $a "* ]]; then wait_storeshot "$applog" "$a" "$STORESHOT_WAIT"; fi
  done
  if [[ -n "$store" ]]; then
    n=$(copy_store_shots "$obj-book-")
    log "$obj: copied $n book-pose store shot file(s) (E-check artefacts)"
    (( n > 0 )) || FAILURES=$((FAILURES+1))
  fi
  hinge_to 0;   fsleep "$SETTLE"; fsleep 1; shoot "$obj-closed" cover
  hinge_to 170; fsleep "$SETTLE"; fsleep 1.5; shoot "$obj-reveal" inner   # reopening past ~150° wakes the inner panel
  grep -c "SQUISH-H" "$applog" >/dev/null 2>&1 \
    && log "$obj: $(grep -c SQUISH-H "$applog") hinge lines in app log" \
    || log "NOTE $obj: no SQUISH-H lines in app log (app does not print hinge samples, or onHingeChange never fired)"
done

# ---- pass 2: tabletop store shots -------------------------------------------------------------------
if [[ -n "$STORESHOT_OBJECTS" && -n "$STORESHOT_SHOTS" ]]; then
  if [[ "$DRIVER" == none ]]; then
    log "skip tabletop store shots: no hinge driver"
  else
    clear_store_halves
    : >"$REVEAL_CHECKS"
    for obj in $STORESHOT_OBJECTS; do tabletop_pass "$obj"; done
  fi
fi

# ---- pass 3: Duo UI frames (shelf, settings, closed-launch cover) -----------------------------------
for ui in $DUO_UI; do
  case "$ui" in
    shelf)    ui_frame duo-shelf 180 inner "object=rubberDuck;duo;notoasts;orient=$ORIENT;shelf" ;;
    settings)
      # FOLD-REVIEW-6 N5: the state its caption promises ("Press without folding. Hear it softer.").
      ui_frame duo-settings 180 inner "object=rubberDuck;duo;notoasts;orient=$ORIENT;settings;soundstyle=soft;nofold;captions=on;gamecenter=hidden" ;;
    cover)
      if [[ "$DRIVER" == none ]]; then log "skip cover launch: no hinge driver"; continue; fi
      # Launched with the hinge already at 0° (ui_frame moves it before the launch): the idle picker, no press.
      ui_frame duo-cover-launch 0 cover "object=rubberDuck;duo;notoasts;specimens=7"
      if grep -qE "SQUISH-H .* phase=(armed|pressing|sealed|revealing)" "$OUT_ABS/logs/duo-cover-launch.txt" 2>/dev/null; then
        log "WARN duo-cover-launch: the engine left idle on a closed launch ($(grep -E 'SQUISH-H' "$OUT_ABS/logs/duo-cover-launch.txt" | tail -1)); O2 may show a sealed card"
        FAILURES=$((FAILURES+1))
      fi ;;
    *) log "WARN unknown DUO_UI frame '$ui' (shelf|settings|cover)" ;;
  esac
done
[[ "$DRIVER" != none && -n "$DUO_UI" ]] && { hinge_to 180; fsleep "$SETTLE"; }

# ---- pass 4: variety grid ---------------------------------------------------------------------------
if [[ -n "$STOREGRID_OBJECTS" && -n "$STORESHOT_OBJECTS" && "$DRIVER" != none ]]; then
  grid_pass
fi

to 30 xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
ls -1 "$OUT_ABS" | tee -a "$RUNLOG"
if [[ "$DRIVER" == none ]]; then log "FAIL: no hinge driver worked; only 180° captured"; exit 3; fi
(( FAILURES > 0 )) && log "finished with $FAILURES warnings"
exit 0
