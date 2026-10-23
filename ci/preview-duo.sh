#!/usr/bin/env bash
# The iPhone Duo App Preview: screen recordings of the real iPhone Duo simulator in tabletop pose (`orient=portrait`,
# the 669 × 951 pt inner canvas with a horizontal fold), the press driven by the REAL simulated hinge (the `hinge` CLI,
# as in ci/duo-screenshots.sh), cut with the app's own press sound.
#
# Segments (each its own launch, `seed=3;notoasts;orient=portrait`):
#  - duck: a hand-paced close (several `hinge sweep`s at falling speed, a hold, then on), shut to 0° (the cut goes to
#    the cover display's PRESS SEALED card when the cover recording worked), reopen to 155°: the reveal.
#  - glass: the same paced close to 70° (it fails at ~81°) and hold; then shut and reopen off camera so the app reaches
#    its reveal and renders the press audio.
#  - shelf: the seeded shelf sheet (`shelf;previewmarks`).
# Outputs in $OUT (preview-duo): preview-duo.mp4 at the inner display's native aspect (2007 × 2853 → 1350 × 1920), and
# preview-duo-886x1920.mp4, the size App Store Connect accepts for iPhone Duo previews (inner screen 886 × 1260 centred
# on #F3EEE6 bands, the preview-video.md §A layout, captions not burned in); frames/, raw/, seg/, logs/, REPORT.txt.
#
# Env: UDID (required, booted iPhone Duo), OUT, APP, BUNDLE, DUO_HINGE (duo-hinge fallback binary).
set -uo pipefail

UDID="${UDID:?set UDID to the booted iPhone Duo simulator}"
OUT="${OUT:-preview-duo}"
APP="${APP:-build/Build/Products/Debug-iphonesimulator/Squish.app}"
BUNDLE="${BUNDLE:-com.pravegm.squish}"
DUO_HINGE="${DUO_HINGE:-$HOME/duo-fold-control/tools/duo-hinge}"
mkdir -p "$OUT/raw" "$OUT/seg" "$OUT/logs" "$OUT/frames"
OUT_ABS="$(cd "$OUT" && pwd)"
REPORT="$OUT_ABS/REPORT.txt"
RUNLOG="$OUT_ABS/logs/run.txt"
: > "$REPORT"
# shellcheck source=ci/preview-lib.sh
source "$(dirname "$0")/preview-lib.sh"
say() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$REPORT" >&2; }

if command -v gtimeout >/dev/null 2>&1; then TO=gtimeout; else TO=""; fi
to() { local s="$1"; shift; if [[ -n "$TO" ]]; then "$TO" -k 5 "$s" "$@"; else perl -e 'alarm shift; exec @ARGV' "$s" "$@"; fi; }

# ---- hinge (the ci/duo-screenshots.sh drivers: hinge first, duo-hinge as the fallback) ------------------------------
DRIVER=none
drv_set() {
  case "$DRIVER" in
    hinge)     to 20 hinge -d "$UDID" -t 3 "$1" ;;
    duo-hinge) to 20 "$DUO_HINGE" -d "$UDID" "$1" ;;
    *) return 1 ;;
  esac
}
CUR=180
# sweep_to <deg> <seconds> [noconfirm]: one continuous move (hinge's 60 Hz sweep; duo-hinge steps 10°), then a
# confirmed set (skipped mid-gesture: a confirm waits for the simulator and would put a pause in the hand's motion).
sweep_to() {
  local target="$1" secs="$2" confirm="${3:-confirm}" a
  if [[ "$DRIVER" == hinge ]]; then
    to $(( ${secs%.*} + 20 )) hinge -d "$UDID" sweep "$CUR" "$target" "$secs" >>"$RUNLOG" 2>&1 || say "WARN sweep $CUR->$target"
  else
    a="$CUR"
    while (( (target < a && a - 10 > target) || (target > a && a + 10 < target) )); do
      (( target < a )) && a=$((a - 10)) || a=$((a + 10))
      drv_set "$a" >>"$RUNLOG" 2>&1 || true
    done
  fi
  CUR="$target"
  [[ "$confirm" == noconfirm && "$DRIVER" == hinge ]] && return 0
  local attempt
  for attempt in 1 2 3; do drv_set "$target" >>"$RUNLOG" 2>&1 && break; sleep 1; done
}
# A hand-paced close: (target seconds) pairs, slower as the object resists, with a hold.
paced_close() {   # paced_close <deg> <secs> [<deg> <secs> | hold <secs>]...
  while (( $# >= 2 )); do
    if [[ "$1" == hold ]]; then fsleep "$2"
    elif (( $# >= 4 )) && [[ "$3" != hold ]]; then sweep_to "$1" "$2" noconfirm
    else sweep_to "$1" "$2"; fi
    shift 2
  done
}

for d in hinge duo-hinge; do
  case "$d" in
    hinge) command -v hinge >/dev/null 2>&1 || continue ;;
    duo-hinge) [[ -x "$DUO_HINGE" ]] || continue ;;
  esac
  DRIVER="$d"
  if drv_set 150 >>"$RUNLOG" 2>&1 && drv_set 180 >>"$RUNLOG" 2>&1; then say "hinge driver: $d"; break; fi
  DRIVER=none
done
[[ "$DRIVER" == none ]] && { say "FAIL: no hinge driver works"; exit 3; }

# ---- displays: which --display names recordVideo takes for the inner and cover panels -------------------------------
probe_record() {   # probe_record <name>: 0 when a 2 s recording on that display produced a video
  local f="$OUT_ABS/raw/_probe-$1.mp4"
  rm -f "$f"
  start_recording "$UDID" "$f" "$OUT_ABS/logs/probe-$1.txt" "$1" >>"$RUNLOG" 2>&1 || return 1
  fsleep 2
  stop_recording >>"$RUNLOG" 2>&1
  [[ -s "$f" ]] && ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$f" >/dev/null 2>&1
}
INNER=""; COVER=""
for c in internal LCD-1 primary-1 3; do
  if probe_record "$c"; then INNER="$c"; say "inner display for recordVideo: '$c' ($(probe_video "$OUT_ABS/raw/_probe-$c.mp4"))"; break; fi
done
for c in external LCD primary 1; do
  [[ "$c" == "$INNER" ]] && continue
  if probe_record "$c"; then COVER="$c"; say "cover display for recordVideo: '$c' ($(probe_video "$OUT_ABS/raw/_probe-$c.mp4"))"; break; fi
done
rm -f "$OUT_ABS"/raw/_probe-*.mp4
if [[ -z "$INNER" ]]; then
  # Without --display recordVideo may still pick the main panel.
  if probe_record ""; then say "recordVideo works without --display ($(probe_video "$OUT_ABS/raw/_probe-.mp4"))"; INNER=" "
  else say "FAIL: recordVideo works on no display"; tail -20 "$RUNLOG"; exit 4; fi
fi
[[ "$INNER" == " " ]] && INNER=""

to 180 xcrun simctl install "$UDID" "$APP" >>"$RUNLOG" 2>&1 || { say "FAIL install"; exit 1; }
app_docs() { echo "$(to 30 xcrun simctl get_app_container "$UDID" "$BUNDLE" data 2>/dev/null)/Documents"; }

# launch_tabletop <name> <scenario>: hinge 180°, launch, wait for the first frames and the portrait (tabletop) layout.
launch_tabletop() {
  local name="$1" scen="$2" log="$OUT_ABS/logs/$1.txt" docs
  sweep_to 180 1; fsleep 2
  to 30 xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  docs="$(app_docs)"; mkdir -p "$docs"
  rm -f "$docs/preview-marks.txt" "$docs/press-audio.wav" "$docs/press-audio.txt"
  : > "$log"
  to 60 xcrun simctl launch --terminate-running-process --stdout="$log" --stderr="$log" \
    "$UDID" "$BUNDLE" -squishDemo "$scen" >>"$RUNLOG" 2>&1 || { say "launch failed: $name"; return 1; }
  wait_for_log "$log" "SQUISH-T frame 120" 60 || say "WARN $name: no 'frame 120' line"
  wait_for_log "$log" "SQUISH-T orient [a-z]+ ok" 45 || say "WARN $name: no 'orient ok' ($(grep 'SQUISH-T orient' "$log" | tail -1))"
  fsleep 2
}

# begin_recording <name>: inner (and cover, when it records) in the background.
begin_recording() {
  start_recording "$UDID" "$OUT_ABS/raw/$1.mp4" "$OUT_ABS/logs/$1.rec.txt" "$INNER" || return 1
  INNER_PID=$REC_PID; INNER_EPOCH=$REC_EPOCH
  COVER_PID=""; COVER_EPOCH=""
  if [[ -n "$COVER" && "${2:-}" == cover ]]; then
    if start_recording "$UDID" "$OUT_ABS/raw/$1-cover.mp4" "$OUT_ABS/logs/$1-cover.rec.txt" "$COVER"; then
      COVER_PID=$REC_PID; COVER_EPOCH=$REC_EPOCH
    else
      say "WARN $1: cover recording failed to start"
    fi
  fi
  fsleep 0.8
}
end_recording() {
  stop_recording "$INNER_PID"
  [[ -n "$COVER_PID" ]] && stop_recording "$COVER_PID"
  echo "rec_epoch=$INNER_EPOCH cover_epoch=${COVER_EPOCH:-none}" > "$OUT_ABS/raw/$1.timing"
}
collect() {   # collect <name>: marks, wav, audio info
  local name="$1" docs log="$OUT_ABS/logs/$1.txt"
  if grep -q pressaudio <<< "${2:-}"; then
    wait_for_log "$log" "SQUISH-T pressaudio (ok|failed)" 120 || say "WARN $name: no pressaudio line"
    grep -h "SQUISH-T pressaudio" "$log" | tee -a "$REPORT" >&2 || true
  fi
  docs="$(app_docs)"
  cp "$docs/preview-marks.txt" "$OUT_ABS/raw/$name.marks.txt" 2>/dev/null || say "WARN $name: no marks file"
  cp "$docs/press-audio.wav" "$OUT_ABS/raw/$name.wav" 2>/dev/null || true
  say "$name raw: $(probe_video "$OUT_ABS/raw/$name.mp4") | marks: $(tr '\n' ' ' < "$OUT_ABS/raw/$name.marks.txt" 2>/dev/null | cut -c1-500)"
  [[ -f "$OUT_ABS/raw/$name-cover.mp4" ]] && say "$name cover raw: $(probe_video "$OUT_ABS/raw/$name-cover.mp4")"
  to 30 xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
}

BASE="seed=3;notoasts;orient=portrait"
# Warm-up (first launch compiles shaders): never recorded.
launch_tabletop warmup "object=rubberDuck;duo;$BASE"
to 30 xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true

# duck: paced close, shut (cover card), reopen (reveal).
S="object=rubberDuck;duo;$BASE;pressaudio"
launch_tabletop duck "$S"
begin_recording duck cover
paced_close 150 0.8 118 1.6 104 1.8 hold 0.6 80 1.4 60 1.2 hold 0.5 0 1.2 hold 2.6 155 1.5 hold 5
end_recording duck
collect duck "$S"

# glass: paced close past the failure, hold; shut and reopen off camera so the reveal (and the audio) happen.
S="object=glassBottle;duo;$BASE;pressaudio"
launch_tabletop glass "$S"
begin_recording glass
paced_close 150 0.8 118 1.6 100 1.8 hold 0.5 84 1.4 70 1.2 hold 2.4
end_recording glass
paced_close 0 1.2 hold 2 155 1.5 hold 2
collect glass "$S"

# shelf
S="object=rubberDuck;duo;$BASE;shelf;previewmarks"
launch_tabletop shelf "$S"
begin_recording shelf
fsleep 6
end_recording shelf
collect shelf "$S"
sweep_to 180 1

# ---- cut ------------------------------------------------------------------------------------------------------------
rec_of() { sed -E "s/.*$2=([0-9.]+|none).*/\1/" "$OUT_ABS/raw/$1.timing"; }
# window <name> <start spec> <end spec>: A (video s), DUR, OFF (wav offset); 1 when a mark is missing.
window() {
  local m="$OUT_ABS/raw/$1.marks.txt" rec s e o
  rec=$(rec_of "$1" rec_epoch); s=$(spec_epoch "$m" "$2"); e=$(spec_epoch "$m" "$3"); o=$(mark_epoch "$m" origin)
  [[ -n "$s" && -n "$e" && -n "$o" ]] || { say "WARN $1: missing marks for '$2' / '$3'"; return 1; }
  A=$(calc "$s - $rec"); DUR=$(calc "$e - $s"); OFF=$(calc "$o - $rec")
  calc_ok "$A >= 0 && $DUR > 0.3" || { say "WARN $1: bad window A=$A DUR=$DUR"; return 1; }
}
# Native: 2007 × 2853 → 1350 × 1920 (cover 1398 × 2034 fits as 1320 × 1920 on graphite). Store: 886 × 1260 on bands.
VF_NATIVE="fps=30,scale=1350:1920:force_original_aspect_ratio=decrease:flags=lanczos,pad=1350:1920:(ow-iw)/2:(oh-ih)/2:color=0x2B2E30,setsar=1,format=yuv420p"
VF_STORE="fps=30,scale=886:1920:force_original_aspect_ratio=decrease:flags=lanczos,pad=886:1920:(ow-iw)/2:(oh-ih)/2:color=0xF3EEE6,setsar=1,format=yuv420p"

NATIVE=(); STORE=(); AT=0
add_cut() {   # add_cut <label> <raw.mp4> <wav|""> <A> <DUR> <OFF>
  cut_segment "$2" "$4" "$5" "$3" "$6" "$VF_NATIVE" "$OUT_ABS/seg/$1.mov" || { say "WARN cut $1 failed"; return 1; }
  cut_segment "$2" "$4" "$5" "$3" "$6" "$VF_STORE" "$OUT_ABS/seg/$1-886.mov" || { say "WARN cut $1 (886) failed"; return 1; }
  NATIVE+=("$OUT_ABS/seg/$1.mov"); STORE+=("$OUT_ABS/seg/$1-886.mov")
  say "cut $1: ${4}s +${5}s -> final ${AT}s"
  AT=$(calc "$AT + $5")
}

DUCK_WAV="$OUT_ABS/raw/duck.wav"; [[ -f "$DUCK_WAV" ]] || DUCK_WAV=""
DM="$OUT_ABS/raw/duck.marks.txt"
POSTER=""
if [[ -n "$(mark_epoch "$DM" closed)" && -f "$OUT_ABS/raw/duck-cover.mp4" ]]; then
  # press (inner) up to the close, the sealed card (cover), the reopen and reveal (inner)
  window duck "phase-pressing-0.5" "closed-0.15" && { P_AT=$AT; P_A=$A; add_cut duck-press "$OUT_ABS/raw/duck.mp4" "$DUCK_WAV" "$A" "$DUR" "$OFF"; }
  CREC=$(rec_of duck cover_epoch)
  s=$(spec_epoch "$DM" "closed-0.15"); e=$(spec_epoch "$DM" "opened+0.1,closed+2.6"); o=$(mark_epoch "$DM" origin)
  add_cut duck-cover "$OUT_ABS/raw/duck-cover.mp4" "$DUCK_WAV" "$(calc "$s - $CREC")" "$(calc "$e - $s")" "$(calc "$o - $CREC")"
  window duck "opened+0.1,closed+2.6" "reveal+2.8" && add_cut duck-reveal "$OUT_ABS/raw/duck.mp4" "$DUCK_WAV" "$A" "$DUR" "$OFF"
else
  window duck "phase-pressing-0.5" "reveal+2.8" && { P_AT=$AT; P_A=$A; add_cut duck "$OUT_ABS/raw/duck.mp4" "$DUCK_WAV" "$A" "$DUR" "$OFF"; }
fi
# Poster: mid-squash, in the hold at 104° (the sweeps reach it ≈ 4.2 s in; pressing starts ≈ 0.3 s in).
pe=$(spec_epoch "$DM" "phase-pressing+4.1")
[[ -n "$pe" && -n "${P_AT:-}" ]] && POSTER=$(calc "$pe - $(rec_of duck rec_epoch) - $P_A + $P_AT")

GLASS_WAV="$OUT_ABS/raw/glass.wav"; [[ -f "$GLASS_WAV" ]] || GLASS_WAV=""
window glass "phase-pressing-0.4" "failure+2.0,phase-pressing+8" && add_cut glass "$OUT_ABS/raw/glass.mp4" "$GLASS_WAV" "$A" "$DUR" "$OFF"
window shelf "origin+1.1" "origin+4.6" && {
  if calc_ok "$AT + $DUR <= 29.5"; then add_cut shelf "$OUT_ABS/raw/shelf.mp4" "" "$A" "$DUR" 0
  else say "NOTE shelf left out: the cut is already ${AT}s (Apple: 30 s at most)"; fi
}
say "total cut: ${AT}s"

(( ${#NATIVE[@]} > 0 )) || { say "FAIL: nothing to cut"; exit 6; }
finish_preview "$OUT_ABS/preview-duo.mp4" 5.0 "${NATIVE[@]}"
finish_preview "$OUT_ABS/preview-duo-886x1920.mp4" 4.0 "${STORE[@]}"
for f in preview-duo.mp4 preview-duo-886x1920.mp4; do report_media "$OUT_ABS/$f" | tee -a "$REPORT" >&2; done
TOTAL=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT_ABS/preview-duo.mp4")
calc_ok "$TOTAL >= 15 && $TOTAL <= 30" || say "WARN duration $TOTAL s is outside Apple's 15–30 s"
if [[ -n "$POSTER" ]]; then
  printf 'poster frame: %.2f s (duck mid-squash on the anvil half)\n' "$POSTER" | tee "$OUT_ABS/POSTER.txt" | tee -a "$REPORT" >&2
  ffmpeg -nostdin -y -v error -ss "$POSTER" -i "$OUT_ABS/preview-duo.mp4" -frames:v 1 "$OUT_ABS/poster-duo.png" || true
fi
STILLS=(0.5)
[[ -n "$POSTER" ]] && STILLS+=("$POSTER")
for t in 4 7 10 13 16 19 22; do calc_ok "$t < $TOTAL" && STILLS+=("$t"); done
frames "$OUT_ABS/preview-duo.mp4" "$OUT_ABS/frames" "${STILLS[@]}"
frames "$OUT_ABS/preview-duo-886x1920.mp4" "$OUT_ABS/frames" 3
ls -la "$OUT_ABS" | tee -a "$REPORT" >&2
exit 0
