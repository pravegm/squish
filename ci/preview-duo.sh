#!/usr/bin/env bash
# The iPhone Duo App Preview: screen recordings of the real iPhone Duo simulator in tabletop pose (`orient=portrait`,
# the 669 × 951 pt inner canvas with a horizontal fold), cut with the app's own press sound. The press is the app's
# Fold Press driven through its hinge input by the `hingescript` demo key (PressDirector), because the simulator's
# `hinge` CLI stalls mid-sweep and costs 5–12 s per call (runs 39965173658, 39973167568). The CLI only opens the device.
#
# Segments (each its own launch and recording, `seed=3;notoasts;orient=portrait`):
#  - duck: `hingescript=7`: a human-paced close 180° → 58°, then a hard cut (the script goes on to 44° and seals, out of
#    shot: a real inner display is dark below ~55°) to the reopen, from just before the reveal card to 3 s after.
#  - glass: the same close; it fails at ~80°; cut 1.8 s after the failure.
#  (No shelf beat: see the note at the takes.)
# There is no cover-display shot: only one recordVideo runs at a time, and the scripted hinge never really closes.
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
# Run 39965173658: each `hinge` call costs 5–12 s of start-up on a busy runner, and a confirmed set (`-t 3`) or the end
# of a sweep can hang until the timeout. So every on-camera motion is ONE `hinge sweep`, never a chain of short ones (a
# chain put 5–70 s holds into the press), and nothing waits for a confirm while recording.
DRIVER=none
drv_set() {
  case "$DRIVER" in
    hinge)     to 20 hinge -d "$UDID" -t 3 "$1" ;;
    duo-hinge) to 20 "$DUO_HINGE" -d "$UDID" "$1" ;;
    *) return 1 ;;
  esac
}
CUR=180
# sweep_to <deg> <seconds> [confirm]: one continuous move (hinge's 60 Hz sweep; duo-hinge steps 10°).
sweep_to() {
  local target="$1" secs="$2" a t0
  t0=$(now_epoch)
  if [[ "$DRIVER" == hinge ]]; then
    to $(( ${secs%.*} + 9 )) hinge -d "$UDID" sweep "$CUR" "$target" "$secs" >>"$RUNLOG" 2>&1 || say "NOTE sweep $CUR->$target exited non-zero (timeout?)"
  else
    a="$CUR"
    while (( (target < a && a - 10 > target) || (target > a && a + 10 < target) )); do
      (( target < a )) && a=$((a - 10)) || a=$((a + 10))
      drv_set "$a" >>"$RUNLOG" 2>&1 || true
    done
  fi
  [[ "${3:-}" == confirm || "$DRIVER" != hinge ]] && drv_set "$target" >>"$RUNLOG" 2>&1
  say "sweep $CUR->$target (${secs}s asked) took $(calc "$(now_epoch) - $t0")s"
  CUR="$target"
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

# ---- displays: which --display names recordVideo takes (run 39965173658: inner LCD-1, cover LCD). Only ONE recording
# can run at a time ("A recording is already in progress"), so the duck's cover shot is its own recording.
probe_record() {   # probe_record <name>: 0 when a 2 s recording on that display produced a video
  local f="$OUT_ABS/raw/_probe-$1.mp4"
  rm -f "$f"
  start_recording "$UDID" "$f" "$OUT_ABS/logs/probe-$1.txt" "$1" >>"$RUNLOG" 2>&1 || return 1
  fsleep 2
  stop_recording >>"$RUNLOG" 2>&1
  [[ -s "$f" ]] && ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$f" >/dev/null 2>&1
}
INNER=""; COVER=""
for c in LCD-1 primary-1 3 internal; do
  if probe_record "$c"; then INNER="$c"; say "inner display for recordVideo: '$c' ($(probe_video "$OUT_ABS/raw/_probe-$c.mp4"))"; break; fi
done
for c in LCD primary 1 external; do
  [[ "$c" == "$INNER" ]] && continue
  if probe_record "$c"; then COVER="$c"; say "cover display for recordVideo: '$c' ($(probe_video "$OUT_ABS/raw/_probe-$c.mp4"))"; break; fi
done
rm -f "$OUT_ABS"/raw/_probe-*.mp4
[[ -n "$INNER" ]] || { say "FAIL: recordVideo works on no inner display name"; tail -20 "$RUNLOG"; exit 4; }

to 180 xcrun simctl install "$UDID" "$APP" >>"$RUNLOG" 2>&1 || { say "FAIL install"; exit 1; }
app_docs() { echo "$(to 30 xcrun simctl get_app_container "$UDID" "$BUNDLE" data 2>/dev/null)/Documents"; }

# launch_tabletop <name> <scenario>: hinge 180°, launch, wait for the first frames and the portrait (tabletop) layout.
launch_tabletop() {
  local name="$1" scen="$2" log="$OUT_ABS/logs/$1.txt" docs
  [[ "$CUR" != 180 ]] && sweep_to 180 1 confirm
  fsleep 2
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

# rec_begin <recording> <inner|cover> / rec_end <recording>: one recording; its start epoch goes to raw/<rec>.timing.
rec_begin() {
  local display="$INNER"
  [[ "$2" == cover ]] && display="$COVER"
  [[ -n "$display" ]] || { say "WARN $1: no $2 display to record"; REC_PID=""; return 1; }
  start_recording "$UDID" "$OUT_ABS/raw/$1.mp4" "$OUT_ABS/logs/$1.rec.txt" "$display" || { REC_PID=""; return 1; }
  echo "rec_epoch=$REC_EPOCH" > "$OUT_ABS/raw/$1.timing"
  fsleep 0.5
}
rec_end() {
  [[ -n "${REC_PID:-}" ]] && stop_recording "$REC_PID"
  # Re-time (preview-lib.sh); without it the recording keeps a display matrix that turns the tabletop UI sideways and
  # ffmpeg's timeline drifts (run 39987522022's glass). Retry once; RETIMED says whether it worked.
  RETIMED=0
  if [[ -f "$OUT_ABS/raw/$1.mp4" ]]; then
    local r; r=$(retime "$OUT_ABS/raw/$1.mp4"); say "$1 $r"
    if [[ "$r" != *"retimed "* ]]; then sleep 3; r=$(retime "$OUT_ABS/raw/$1.mp4"); say "$1 (retry) $r"; fi
    [[ "$r" == *"retimed "* ]] && RETIMED=1
    say "$1 raw: $(probe_video "$OUT_ABS/raw/$1.mp4")"
  fi
  REC_PID=""
}
collect() {   # collect <press> <scenario>: marks and wav, once the app has rendered the sound
  local name="$1" docs log="$OUT_ABS/logs/$1.txt"
  if grep -q pressaudio <<< "${2:-}"; then
    wait_for_log "$log" "SQUISH-T pressaudio (ok|failed)" 120 || say "WARN $name: no pressaudio line"
    grep -h "SQUISH-T pressaudio" "$log" | tee -a "$REPORT" >&2 || true
  fi
  docs="$(app_docs)"
  cp "$docs/preview-marks.txt" "$OUT_ABS/raw/$name.marks.txt" 2>/dev/null || say "WARN $name: no marks file"
  cp "$docs/press-audio.wav" "$OUT_ABS/raw/$name.wav" 2>/dev/null || true
  cp "$docs/press-audio.txt" "$OUT_ABS/raw/$name.audio.txt" 2>/dev/null || true
  cat "$docs/preview-script.txt" >> "$OUT_ABS/raw/$name.marks.txt" 2>/dev/null || true   # hingescript steps
  say "$name marks: $(tr '\n' ' ' < "$OUT_ABS/raw/$name.marks.txt" 2>/dev/null | cut -c1-600)"
  grep -E "SQUISH-H" "$log" > "$OUT_ABS/logs/$name.hinge.txt" 2>/dev/null || true
  to 30 xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
}

BASE="seed=3;notoasts;orient=portrait"
# The presses are driven in the app by `hingescript` (PressDirector: samples fed through hingeUpdate at 60 Hz while
# the simulated Duo lies open at 180°): the `hinge` CLI stalled mid-sweep and costs 5–12 s per call (run 39973167568).
# The CLI only puts the device at 180° before each launch. Each recording starts before its launch and ends 3.5 s after
# the script's last step, so every cut point is inside it.
# press_take <name> <scenario>: record one hingescript press and collect its marks, script steps and sound.
press_take() {
  local name="$1" scen="$2" docs
  [[ "$CUR" != 180 ]] && sweep_to 180 1 confirm
  to 30 xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  docs="$(app_docs)"; mkdir -p "$docs"
  rm -f "$docs/preview-marks.txt" "$docs/press-audio.wav" "$docs/press-audio.txt" "$docs/preview-script.txt"
  : > "$OUT_ABS/logs/$name.txt"
  rec_begin "$name" inner || return 1
  to 60 xcrun simctl launch --terminate-running-process --stdout="$OUT_ABS/logs/$name.txt" --stderr="$OUT_ABS/logs/$name.txt" \
    "$UDID" "$BUNDLE" -squishDemo "$scen" >>"$RUNLOG" 2>&1 || say "launch failed: $name"
  if [[ "$scen" == *hingescript* ]]; then
    wait_for_mark "$docs/preview-script.txt" script-160 150 || say "WARN $name: the hinge script never reached its end"
    fsleep 5
  else
    wait_for_mark "$docs/preview-marks.txt" origin 120 || say "WARN $name: no origin mark"
    fsleep 6.5
  fi
  rec_end "$name"
  grep -h "SQUISH-T hingescript\|SQUISH-T orient" "$OUT_ABS/logs/$name.txt" | tee -a "$REPORT" >&2 || true
  collect "$name" "$scen"
}

# Warm-up (first launch compiles shaders; one scripted press warms the deformation path): never kept.
press_take warmup "object=rubberDuck;duo;$BASE;hingescript=4"
rm -f "$OUT_ABS/raw/warmup.mp4"

for take in duck:rubberDuck glass:glassBottle; do
  for attempt in 1 2; do
    press_take "${take%%:*}" "object=${take##*:};duo;$BASE;pressaudio;hingescript=7"
    (( RETIMED == 1 )) && break
    say "WARN ${take%%:*}: the recording could not be re-timed (attempt $attempt); recording it again"
  done
done
# No shelf beat on the Duo: launched straight into the shelf, the open-lying simulator stays in book layout behind
# the sheet (run 39983207065), and the duck and glass already make a 19 s cut. The 6.9" preview carries the shelf.

# ---- cut ------------------------------------------------------------------------------------------------------------
rec_of() { sed -E 's/.*rec_epoch=([0-9.]+).*/\1/' "$OUT_ABS/raw/$1.timing" 2>/dev/null; }
rec_len() { ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT_ABS/raw/$1.mp4" 2>/dev/null; }
# window <press> <recording> <start spec> <end spec>: A (s into the recording), DUR, OFF (wav offset, calibrated); the
# end is clamped to the recording. 1 when a mark or the recording is missing.
window() {
  local m="$OUT_ABS/raw/$1.marks.txt" rec s e o len cal="CAL_$1"
  rec=$(rec_of "$2"); len=$(rec_len "$2")
  [[ -n "$rec" && -n "$len" ]] || { say "WARN $2: no recording"; return 1; }
  s=$(spec_epoch "$m" "$3"); e=$(spec_epoch "$m" "$4")
  # The WAV's sample 0 is press-audio.txt's origin= (the trace start the app rendered from). The `origin` mark is the
  # object's placement, ~12 s earlier on the Duo (the trace's pre-roll trim moves its start up to the press): run
  # 40222962649's preview placed the sound by the mark, so both breaks were silent. The mark is only the fallback.
  o=$(sed -nE 's/.*origin=([0-9.]+).*/\1/p' "$OUT_ABS/raw/$1.audio.txt" 2>/dev/null | head -1)
  [[ -n "$o" ]] || o=$(mark_epoch "$m" origin)
  [[ -n "$s" && -n "$e" && -n "$o" ]] || { say "WARN $1/$2: missing marks for '$3' / '$4'"; return 1; }
  A=$(calc "$s - $rec"); OFF=$(calc "$o - $rec + ${!cal:-0}")
  calc_ok "$A < 0" && A=0
  e=$(calc "$e - $rec"); calc_ok "$e > $len - 0.05" && e=$(calc "$len - 0.05")
  DUR=$(calc "$e - $A")
  calc_ok "$DUR > 0.3" || { say "WARN $2: bad window A=$A end=$e"; return 1; }
}
# calibrate <press> <recording>: delay the sound by where the failure flash shows in the recording (as ci/preview.sh).
calibrate() {
  local m="$OUT_ABS/raw/$1.marks.txt" f rec fv ft d rise o w0 wt cal
  printf -v "CAL_$1" %s 0
  f=$(mark_epoch "$m" failure); rec=$(rec_of "$2")
  [[ -n "$f" && -n "$rec" ]] || { say "calibrate $1: no failure mark or recording"; return 0; }
  fv=$(calc "$f - $rec")
  ft=$(flash_time "$OUT_ABS/raw/$2.mp4" "$(calc "$fv - 0.1")" "$(calc "$fv + 0.8")")
  [[ -n "$ft" ]] || { say "calibrate $1: no flash found; sound by clock only"; return 0; }
  rise="${ft##* }"; ft="${ft%% *}"
  calc_ok "$rise >= 8" || { say "calibrate $1: flash too faint (dY $rise); sound by clock only"; return 0; }
  # Line the WAV's own break up with the flash. The offline render re-runs the press from its trace, and its failure can
  # land up to ~1 s from the live one (run 40350252050: glass +0.96 s), so the clock alone is not enough: find the
  # loudest onset in the WAV near where the clock puts the failure and move it onto the flash.
  o=$(sed -nE 's/.*origin=([0-9.]+).*/\1/p' "$OUT_ABS/raw/$1.audio.txt" 2>/dev/null | head -1)
  [[ -n "$o" ]] || o=$(mark_epoch "$m" origin)
  w0=$(calc "$f - $o")
  wt=$(wav_transient "$OUT_ABS/raw/$1.wav" "$(calc "$w0 - 0.4")" "$(calc "$w0 + 1.5")")
  if [[ -n "$wt" ]]; then
    cal=$(calc "$ft - $wt - ($o - $rec)")
    if calc_ok "$cal >= -2 && $cal <= 2"; then
      printf -v "CAL_$1" %s "$cal"
      say "calibrate $1: flash at ${ft}s (dY $rise), the WAV's break at ${wt}s (clock said ${w0}s): sound moved ${cal}s"
      return 0
    fi
    say "calibrate $1: the WAV's break at ${wt}s would move the sound ${cal}s; implausible"
  fi
  d=$(calc "$ft - $fv")
  calc_ok "$d >= -0.5 && $d <= 0.7" && { printf -v "CAL_$1" %s "$d"; say "calibrate $1: by the flash only: sound delayed ${d}s"; }
  return 0
}
# first_lit <recording> <from s>: the first time after <from> the recording's mean brightness passes 25 (the inner
# panel wakes ~150° into the reopen).
first_lit() {
  ffmpeg -nostdin -v error -i "$OUT_ABS/raw/$1.mp4" -vf "trim=start=$2:duration=6,setpts=PTS-STARTPTS,scale=120:-2,signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=-" -f null - 2>/dev/null \
    | awk -v base="$2" '/pts_time/ { split($0, p, "pts_time:"); t = p[2] + 0 } /YAVG/ { split($0, y, "="); if (y[2] + 0 > 25) { printf "%.3f", base + t; exit } }'
}

# Native: 2007 × 2853 → 1350 × 1920 (cover 1398 × 2034 fits as 1320 × 1920 on graphite). Store: 886 × 1260 on bands.
VF_NATIVE="fps=30,scale=1350:1920:force_original_aspect_ratio=decrease:flags=lanczos,pad=1350:1920:(ow-iw)/2:(oh-ih)/2:color=0x2B2E30,setsar=1,format=yuv420p"
VF_STORE="fps=30,scale=886:1920:force_original_aspect_ratio=decrease:flags=lanczos,pad=886:1920:(ow-iw)/2:(oh-ih)/2:color=0xF3EEE6,setsar=1,format=yuv420p"

NATIVE=(); STORE=(); AT=0
add_cut() {   # add_cut <label> <recording> <wav|""> <A> <DUR> <OFF>
  local raw="$OUT_ABS/raw/$2.mp4"
  cut_segment "$raw" "$4" "$5" "$3" "$6" "$VF_NATIVE" "$OUT_ABS/seg/$1.mov" || { say "WARN cut $1 failed"; return 1; }
  cut_segment "$raw" "$4" "$5" "$3" "$6" "$VF_STORE" "$OUT_ABS/seg/$1-886.mov" || { say "WARN cut $1 (886) failed"; return 1; }
  NATIVE+=("$OUT_ABS/seg/$1.mov"); STORE+=("$OUT_ABS/seg/$1-886.mov")
  say "cut $1: $2 ${4}s +${5}s -> final ${AT}s ($(frame_gaps "$raw" "$4" "$(calc "$4 + $5")"))"
  AT=$(calc "$AT + $5")
}

calibrate duck duck
calibrate glass glass
DUCK_WAV="$OUT_ABS/raw/duck.wav"; [[ -f "$DUCK_WAV" ]] || DUCK_WAV=""
POSTER=""
# duck: the close while a real inner display would still be lit (to 58° + 0.3 s), then a hard cut to the reopen, from
# just before the reveal card comes up (the engine reveals at 120° on the way open) to 3 s after it.
if window duck duck "phase-pressing-0.5" "script-58+0.3,phase-pressing+7"; then
  P_AT=$AT; P_A=$A
  add_cut duck-press duck "$DUCK_WAV" "$A" "$DUR" "$OFF"
  pe=$(spec_epoch "$OUT_ABS/raw/duck.marks.txt" "script-begin+3.6")   # the hold near 115°: mid-squash
  [[ -n "$pe" ]] && POSTER=$(calc "$pe - $(rec_of duck) - $P_A + $P_AT")
fi
window duck duck "reveal-0.25" "reveal+4.0" && add_cut duck-reveal duck "$DUCK_WAV" "$A" "$DUR" "$OFF"
DUCK_END_AT=$AT
GLASS_WAV="$OUT_ABS/raw/glass.wav"; [[ -f "$GLASS_WAV" ]] || GLASS_WAV=""
GLASS_AT=""; GLASS_DUR=""
if window glass glass "phase-pressing-0.4" "failure+1.8,script-58+0.3"; then
  GLASS_AT=$AT; GLASS_DUR=$DUR
  add_cut glass glass "$GLASS_WAV" "$A" "$DUR" "$OFF"
fi
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
for t in 2 4 6 8 10 12 14 16 18 20 22 24; do calc_ok "$t < $TOTAL" && STILLS+=("$t"); done
frames "$OUT_ABS/preview-duo.mp4" "$OUT_ABS/frames" "${STILLS[@]}"
frames "$OUT_ABS/preview-duo-886x1920.mp4" "$OUT_ABS/frames" 3

# Social clips (docs/press/), 1080 × 1920, from the finished native cut: the duck's last 9.5 s up to the end of its
# reveal (the squeeze, then the reopen and the specimen card), and the glass.
mkdir -p "$OUT_ABS/social"
if calc_ok "$DUCK_END_AT > 9.5"; then
  social_from_master "$OUT_ABS/preview-duo.mp4" "$(calc "$DUCK_END_AT - 9.5")" 9.5 "$OUT_ABS/social/duo-duck.mp4" \
    && say "social duo-duck.mp4: $(du -h "$OUT_ABS/social/duo-duck.mp4" | cut -f1)"
fi
if [[ -n "$GLASS_AT" ]]; then
  gd=$GLASS_DUR; calc_ok "$gd > 9" && gd=9
  social_from_master "$OUT_ABS/preview-duo.mp4" "$GLASS_AT" "$gd" "$OUT_ABS/social/duo-glass.mp4" \
    && say "social duo-glass.mp4: $(du -h "$OUT_ABS/social/duo-glass.mp4" | cut -f1)"
fi
for f in "$OUT_ABS"/social/*.mp4; do [[ -f "$f" ]] && { report_media "$f" | tee -a "$REPORT" >&2; frames "$f" "$OUT_ABS/frames" 1.5 4.5 7.5; }; done
# Raw recordings are large (2007 × 2853 at 60 fps); keep them out of the artifact once cut.
rm -f "$OUT_ABS"/raw/*.mp4
ls -la "$OUT_ABS" | tee -a "$REPORT" >&2
exit 0
