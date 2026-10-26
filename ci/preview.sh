#!/usr/bin/env bash
# The 6.9-inch App Preview (docs/appstore/preview-video.md §C): real screen recordings of the app on the iPhone 18 Pro
# Max simulator (Pinch Press: no folded device is ever in the 6.9" set, Guideline 2.3), cut into one 886 × 1920,
# 30 fps H.264 file with the app's own press sound. Also cuts the social clips and loops from the same recordings.
#
# Per segment: start `simctl io recordVideo --codec=h264`, launch `-squishDemo "<scenario>"`, wait for the app's marks
# (Documents/preview-marks.txt: `pressaudio` / `previewmarks`, DemoMode.swift), stop, copy the raw recording, the marks
# and Documents/press-audio.wav (the press's sound rendered offline from its own trace, sample 0 = the `origin` mark).
# Then each segment is cut between two mark-relative points (SEGMENTS below), scaled to cover 886 × 1920 (1320 × 2868
# scales to 886 × 1925; 2–3 px of status bar and home indicator are cropped, never UI), with its audio placed by
# wall-clock epoch (ci/preview-lib.sh explains the timing), and the segments are joined with hard cuts.
#
# Env: DEVICE (auto:Pro Max: the newest "… Pro Max" simulator, created if missing; same pick as ci/screenshots.sh),
#      OUT (preview-69), APP, BUNDLE, SOCIAL (1 = also cut the social clips and loops into $OUT/social).
# Outputs in $OUT: preview-69.mp4, poster-69.png (+ POSTER.txt), frames/*.png (stills for review), raw/<seg>.mp4 + marks
# + wav + timing, seg/<seg>.mov, social/*.mp4|gif, logs/, REPORT.txt (ffprobe facts, sync check, durations).
set -euo pipefail

DEVICE="${DEVICE:-auto:Pro Max}"
OUT="${OUT:-preview-69}"
APP="${APP:-build/Build/Products/Debug-iphonesimulator/Squish.app}"
BUNDLE="${BUNDLE:-com.pravegm.squish}"
SOCIAL="${SOCIAL:-1}"
mkdir -p "$OUT/raw" "$OUT/seg" "$OUT/logs" "$OUT/frames" "$OUT/social"
OUT_ABS="$(cd "$OUT" && pwd)"
REPORT="$OUT_ABS/REPORT.txt"
: > "$REPORT"
# shellcheck source=ci/preview-lib.sh
source "$(dirname "$0")/preview-lib.sh"
say() { echo "$*" | tee -a "$REPORT"; }

# name|scenario|cut start|cut end. Cut points are "<mark>±<s>" with comma fallbacks (preview-lib.sh spec_epoch).
# The order is the cut order. Durations at slowpress 5 / 4.5: duck ≈ 9.5 s, can ≈ 6 s, glass ≈ 6 s, shelf 4 s.
SEGMENTS=(
  "duck|object=rubberDuck;reveal;seed=3;notoasts;prewarm;slowpress=5;pressaudio|phase-pressing-0.6|reveal+4.0"
  "can|object=sodaCan;reveal;seed=3;notoasts;prewarm;slowpress=4.5;pressaudio|phase-pressing-0.4|phase-sealed+0.9,reveal+0.2"
  "glass|object=glassBottle;reveal;seed=3;notoasts;prewarm;slowpress=5;pressaudio|phase-pressing-0.4|failure+2.2,phase-sealed+0.6"
  "shelf|object=rubberDuck;shelf;notoasts;previewmarks|origin+7.5|origin+11.5"
)
VF="fps=30,scale=886:1920:force_original_aspect_ratio=increase:flags=lanczos,crop=886:1920,setsar=1,format=yuv420p"

# ---- simulator (the ci/screenshots.sh pick) -------------------------------------------------------------------------
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
say "simulator: $DEVICE_NAME ($UDID)"
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiBars 3 || true
xcrun simctl install "$UDID" "$APP"
app_docs() { echo "$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)/Documents"; }

# Warm-up, never kept: a full scripted duck press to its reveal (the first press after install builds the deformation
# and shader state; in run 39965173658 the first recorded press stalled for its whole squash), under a throwaway
# recording so the encoder is warm too.
WARM_LOG="$OUT_ABS/logs/warmup.txt"; : > "$WARM_LOG"
start_recording "$UDID" "$OUT_ABS/raw/_warmup.mp4" "$OUT_ABS/logs/warmup.rec.txt" || true
xcrun simctl launch --terminate-running-process --stdout="$WARM_LOG" --stderr="$WARM_LOG" \
  "$UDID" "$BUNDLE" -squishDemo "object=rubberDuck;reveal;seed=3;notoasts" >/dev/null
wait_for_log "$WARM_LOG" "SQUISH-T demo reveal (up|missing)" 90 || say "warning: warm-up press never reached its reveal"
sleep 2
stop_recording
say "warm-up: $(probe_video "$OUT_ABS/raw/_warmup.mp4" 2>/dev/null)"
rm -f "$OUT_ABS/raw/_warmup.mp4"
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true

# ---- record every segment -------------------------------------------------------------------------------------------
record_segment() {
  local name="$1" scen="$2" docs log="$OUT_ABS/logs/$1.txt" launch
  say "=== record $name: $scen"
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  docs="$(app_docs)"
  mkdir -p "$docs"
  rm -f "$docs/preview-marks.txt" "$docs/press-audio.wav" "$docs/press-audio.txt"
  : > "$log"
  start_recording "$UDID" "$OUT_ABS/raw/$name.mp4" "$OUT_ABS/logs/$name.rec.txt"
  fsleep 0.8   # a still frame or two of the home screen first, so the app's first frame is never the file's first
  launch=$(now_epoch)
  xcrun simctl launch --terminate-running-process --stdout="$log" --stderr="$log" \
    "$UDID" "$BUNDLE" -squishDemo "$scen" >/dev/null
  if [[ "$scen" == *pressaudio* ]]; then
    if wait_for_mark "$docs/preview-marks.txt" reveal 120; then
      fsleep 6.0     # the reveal card on screen; the app renders the sound 8 s after the reveal, after this stop
    else
      say "warning: $name: no reveal mark after 120 s"
    fi
  else
    # The shelf: ~11–13 s from launch to the demo, then the scene and the sheet only appear ~5 s after that (run
    # 39983207065: a blank screen at origin + 1–5 s), so record to origin + 12.5 s and cut the settled sheet.
    wait_for_mark "$docs/preview-marks.txt" origin 90 || say "warning: $name: no origin mark after 90 s"
    sleep 12.5
  fi
  stop_recording
  # Re-time for ffmpeg (preview-lib.sh). Run 39987522022: AVFoundation said "Cannot Decode" twice right after a stop,
  # so retry once; a take that still can't be re-timed is marked so take_gap never picks it.
  rm -f "$OUT_ABS/raw/$name.retime-failed"
  if ! retime "$OUT_ABS/raw/$name.mp4" | tee -a "$REPORT" | grep -q "retimed "; then
    sleep 3
    retime "$OUT_ABS/raw/$name.mp4" | tee -a "$REPORT" | grep -q "retimed " || : > "$OUT_ABS/raw/$name.retime-failed"
  fi
  if [[ "$scen" == *pressaudio* ]]; then
    wait_for_log "$log" "SQUISH-T pressaudio (ok|failed)" 90 || say "warning: $name: no pressaudio line after 90 s"
    grep -h "SQUISH-T pressaudio" "$log" | tee -a "$REPORT" || true
  fi
  cp "$docs/preview-marks.txt" "$OUT_ABS/raw/$name.marks.txt" 2>/dev/null || say "warning: $name: no marks file"
  cp "$docs/press-audio.wav" "$OUT_ABS/raw/$name.wav" 2>/dev/null || true
  cp "$docs/press-audio.txt" "$OUT_ABS/raw/$name.audio.txt" 2>/dev/null || true
  echo "rec_epoch=$REC_EPOCH launch_epoch=$launch" > "$OUT_ABS/raw/$name.timing"
  say "   raw: $(probe_video "$OUT_ABS/raw/$name.mp4")"
  say "   rec_epoch=$REC_EPOCH launch=$launch marks: $(tr '\n' ' ' < "$OUT_ABS/raw/$name.marks.txt" 2>/dev/null | cut -c1-600)"
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
}

# take_gap <name> <from spec> <to spec>: the longest frame gap (s) inside the cut (a render stall), or 99 when the take
# is unusable (no marks, no sound).
take_gap() {
  local m="$OUT_ABS/raw/$1.marks.txt" rec s e g
  rec=$(sed -E 's/.*rec_epoch=([0-9.]+).*/\1/' "$OUT_ABS/raw/$1.timing" 2>/dev/null)
  s=$(spec_epoch "$m" "$2"); e=$(spec_epoch "$m" "$3")
  if [[ -z "$rec" || -z "$s" || -z "$e" || ! -f "$OUT_ABS/raw/$1.wav" || -f "$OUT_ABS/raw/$1.retime-failed" ]]; then
    echo 99; return 0
  fi
  local len; len=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT_ABS/raw/$1.mp4")
  if ! calc_ok "$e - $rec <= $len"; then say "   $1: the cut ends after the (re-timed) file" >&2; echo 99; return 0; fi
  g=$(frame_gaps "$OUT_ABS/raw/$1.mp4" "$(calc "$s - $rec")" "$(calc "$e - $rec")")
  say "   $1 cut window: $g" >&2
  g="${g#*maxgap=}"; echo "${g%% *}"
}
TAKE_FILES="mp4 marks.txt wav audio.txt timing"
keep_take() {   # keep_take <name> <attempt>: raw/<name>.* -> raw/<name>.take<attempt>.*
  local x; for x in $TAKE_FILES; do [[ -f "$OUT_ABS/raw/$1.$x" ]] && mv "$OUT_ABS/raw/$1.$x" "$OUT_ABS/raw/$1.take$2.$x"; done; return 0
}
use_take() {    # use_take <name> <attempt>: raw/<name>.take<attempt>.* -> raw/<name>.*
  local x; for x in $TAKE_FILES; do [[ -f "$OUT_ABS/raw/$1.take$2.$x" ]] && cp "$OUT_ABS/raw/$1.take$2.$x" "$OUT_ABS/raw/$1.$x"; done; return 0
}

# Up to three takes per press; the first with no frame gap over 0.25 s wins, otherwise the take with the smallest gap.
for seg in "${SEGMENTS[@]}"; do
  IFS='|' read -r name scen from to <<< "$seg"
  if [[ "$scen" != *pressaudio* ]]; then record_segment "$name" "$scen"; continue; fi
  best=""; best_gap=99
  for attempt in 1 2 3; do
    record_segment "$name" "$scen"
    gap=$(take_gap "$name" "$from" "$to")
    keep_take "$name" "$attempt"
    say "   $name take $attempt: longest frame gap in the cut ${gap}s"
    if calc_ok "$gap < $best_gap"; then best=$attempt; best_gap=$gap; fi
    calc_ok "$gap <= 0.25" && break
  done
  if [[ -z "$best" ]] || calc_ok "$best_gap >= 99"; then say "error: $name: no usable take"; exit 6; fi
  use_take "$name" "$best"
  say "$name: using take $best (longest frame gap ${best_gap}s)"
  calc_ok "$best_gap > 0.25" && say "warning: $name: every take has a render stall of ${best_gap}s inside the cut (a short freeze in the preview)"
done
rm -f "$OUT_ABS"/raw/*.take*.mp4

# Audio/picture calibration per press: the app's sound is placed by wall clock, but the simulator shows a frame some
# time after the engine event (render latency at ~15–20 fps). Every press here fails, and the failure whitens the top
# of the screen, so measure where that flash is in the recording and delay the sound by the same amount (0–0.5 s).
for seg in "${SEGMENTS[@]}"; do
  IFS='|' read -r name scen _ _ <<< "$seg"
  printf -v "CAL_$name" %s 0
  [[ "$scen" == *pressaudio* ]] || continue
  m="$OUT_ABS/raw/$name.marks.txt"; f=$(mark_epoch "$m" failure)
  [[ -n "$f" ]] || { say "calibrate $name: no failure mark; sound placed by clock only"; continue; }
  rec=$(sed -E 's/.*rec_epoch=([0-9.]+).*/\1/' "$OUT_ABS/raw/$name.timing")
  fv=$(calc "$f - $rec")
  ft=$(flash_time "$OUT_ABS/raw/$name.mp4" "$(calc "$fv - 0.3")" "$(calc "$fv + 0.8")")
  if [[ -n "$ft" ]]; then
    d=$(calc "${ft%% *} - $fv"); rise="${ft##* }"
    if calc_ok "$d >= -0.5 && $d <= 0.7 && $rise >= 8"; then
      printf -v "CAL_$name" %s "$d"
      say "calibrate $name: failure mark at ${fv}s, flash at ${ft%% *}s (dY $rise): sound delayed ${d}s"
      # Then line the WAV's own break up with that flash: the offline render re-runs the press from its trace and its
      # failure can land a little off the live one (glass in run 40222962649: the shatter ~0.1 s before the flash).
      om=$(mark_epoch "$m" origin)
      oa=$(sed -nE 's/.*origin=([0-9.]+).*/\1/p' "$OUT_ABS/raw/$name.audio.txt" 2>/dev/null | head -1)
      w0=$(calc "$f - ${oa:-$om}")
      wt=$(wav_transient "$OUT_ABS/raw/$name.wav" "$w0" 0)   # the P-48 replay is close: only a small correction
      if [[ -n "$wt" && -n "$om" ]]; then
        c2=$(calc "${ft%% *} - $wt - ($om - $rec)")
        if calc_ok "$c2 >= -2 && $c2 <= 2"; then
          printf -v "CAL_$name" %s "$c2"
          say "calibrate $name: the WAV's break at ${wt}s (clock said ${w0}s): sound moved ${c2}s instead"
        fi
      fi
    else
      say "calibrate $name: flash at ${ft%% *}s (dY $rise) vs mark ${fv}s is implausible; sound placed by clock only"
    fi
  else
    say "calibrate $name: no flash found; sound placed by clock only"
  fi
done

# ---- cut ------------------------------------------------------------------------------------------------------------
# seg_window <name> <start spec> <end spec>: sets A (video seconds), DUR, OFF (wav offset) for a segment.
seg_window() {
  local name="$1" marks="$OUT_ABS/raw/$1.marks.txt" rec s e origin
  rec=$(sed -E 's/.*rec_epoch=([0-9.]+).*/\1/' "$OUT_ABS/raw/$name.timing")
  s=$(spec_epoch "$marks" "$2"); e=$(spec_epoch "$marks" "$3")
  origin=$(mark_epoch "$marks" origin)
  if [[ -z "$s" || -z "$e" || -z "$origin" ]]; then
    say "error: $name: missing marks for '$2' / '$3' (origin=${origin:-none})"; return 1
  fi
  local cal="CAL_$name"
  A=$(calc "$s - $rec"); DUR=$(calc "$e - $s"); OFF=$(calc "$origin - $rec + ${!cal:-0}")
  calc_ok "$A >= 0" || { say "error: $name: cut starts before the recording (A=$A)"; return 1; }
  local len
  len=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT_ABS/raw/$name.mp4")
  calc_ok "$A + $DUR <= $len + 0.05" || { say "error: $name: cut ends at $(calc "$A + $DUR")s, after the recording ($len s)"; return 1; }
}

SEGS=()
FINAL_AT=0
for seg in "${SEGMENTS[@]}"; do
  IFS='|' read -r name scen from to <<< "$seg"
  seg_window "$name" "$from" "$to" || exit 6
  wav="$OUT_ABS/raw/$name.wav"; [[ -f "$wav" ]] || wav=""
  [[ "$scen" == *pressaudio* && -z "$wav" ]] && say "warning: $name has no press audio; its segment is silent"
  cut_segment "$OUT_ABS/raw/$name.mp4" "$A" "$DUR" "$wav" "$OFF" "$VF" "$OUT_ABS/seg/$name.mov"
  printf -v "SEG_AT_$name" %s "$FINAL_AT"; printf -v "SEG_A_$name" %s "$A"   # bash 3.2: no associative arrays
  say "cut $name: video ${A}s +${DUR}s (wav offset ${OFF}s) -> final ${FINAL_AT}s$( [[ -n "$wav" ]] && echo ' with sound' || echo ' silent')"
  FINAL_AT=$(calc "$FINAL_AT + $DUR")
  SEGS+=("$OUT_ABS/seg/$name.mov")
done
say "total cut: ${FINAL_AT}s"

finish_preview "$OUT_ABS/preview-69.mp4" 4.0 "${SEGS[@]}"
report_media "$OUT_ABS/preview-69.mp4" | tee -a "$REPORT"
TOTAL=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT_ABS/preview-69.mp4")
SIZE=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$OUT_ABS/preview-69.mp4")
RATE=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 "$OUT_ABS/preview-69.mp4")
FAILED=0
[[ "$SIZE" == "886x1920" ]] || { say "FAIL size $SIZE (want 886x1920)"; FAILED=1; }
[[ "$RATE" == "30/1" ]] || { say "FAIL frame rate $RATE (want 30/1)"; FAILED=1; }
calc_ok "$TOTAL >= 15 && $TOTAL <= 30" || { say "FAIL duration $TOTAL s (Apple: 15–30 s)"; FAILED=1; }
calc_ok "$TOTAL >= 20 && $TOTAL <= 28" || say "warning: duration $TOTAL s is outside the 20–28 s target"

# Poster: the duck mid-squash, in its hold (slowpress u ≈ 0.59 of 5 s after the lead-in, ≈ phase-pressing + 2.95 s).
DUCK_MARKS="$OUT_ABS/raw/duck.marks.txt"
DUCK_REC=$(sed -E 's/.*rec_epoch=([0-9.]+).*/\1/' "$OUT_ABS/raw/duck.timing")
POSTER=$(calc "$(spec_epoch "$DUCK_MARKS" "phase-pressing+2.95") - $DUCK_REC - ${SEG_A_duck} + ${SEG_AT_duck}")
ffmpeg -nostdin -y -v error -ss "$POSTER" -i "$OUT_ABS/preview-69.mp4" -frames:v 1 "$OUT_ABS/poster-69.png"
printf 'poster frame: %.2f s (duck mid-squash, in the hold before the seam)\n' "$POSTER" | tee "$OUT_ABS/POSTER.txt" | tee -a "$REPORT"

# Review stills: segment starts and ends, the poster, the duck reveal, the can buckle, the glass break, the shelf.
STILLS=(0.3 "$POSTER")
for name in duck can glass shelf; do
  at="SEG_AT_$name"; STILLS+=("$(calc "${!at} + 0.5")")
done
GLASS_FAIL=$(spec_epoch "$OUT_ABS/raw/glass.marks.txt" "failure+0.25")
GLASS_REC=$(sed -E 's/.*rec_epoch=([0-9.]+).*/\1/' "$OUT_ABS/raw/glass.timing")
[[ -n "$GLASS_FAIL" ]] && STILLS+=("$(calc "$GLASS_FAIL - $GLASS_REC - ${SEG_A_glass} + ${SEG_AT_glass}")")
DUCK_REVEAL=$(spec_epoch "$DUCK_MARKS" "reveal+3.3")
[[ -n "$DUCK_REVEAL" ]] && STILLS+=("$(calc "$DUCK_REVEAL - $DUCK_REC - ${SEG_A_duck} + ${SEG_AT_duck}")")
CAN_SEAL=$(spec_epoch "$OUT_ABS/raw/can.marks.txt" "phase-sealed-0.8")
CAN_REC=$(sed -E 's/.*rec_epoch=([0-9.]+).*/\1/' "$OUT_ABS/raw/can.timing")
[[ -n "$CAN_SEAL" ]] && STILLS+=("$(calc "$CAN_SEAL - $CAN_REC - ${SEG_A_can} + ${SEG_AT_can}")")
STILLS+=("$(calc "$TOTAL - 0.3")")
frames "$OUT_ABS/preview-69.mp4" "$OUT_ABS/frames" "${STILLS[@]}"
say "stills: ${STILLS[*]}"

# Sync check: the glass failure flashes the screen. Find the brightest frame jump in the glass segment of the final
# file and compare it with where the failure mark says it is (both in final seconds).
if [[ -n "$GLASS_FAIL" ]]; then
  want=$(calc "$(mark_epoch "$OUT_ABS/raw/glass.marks.txt" failure) - $GLASS_REC - ${SEG_A_glass} + ${SEG_AT_glass}")
  got=$(ffmpeg -nostdin -v error -ss "${SEG_AT_glass}" -t 5 -i "$OUT_ABS/preview-69.mp4" \
          -vf "signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=-" -f null - 2>/dev/null \
        | awk -v base="${SEG_AT_glass}" '/pts_time/ { split($0, p, "pts_time:"); t = p[2] + 0 }
                                         /YAVG/ { split($0, y, "="); v = y[2] + 0; if (have && v - last > best) { best = v - last; at = t }; last = v; have = 1 }
                                         END { if (have) printf "%.3f %.1f", base + at, best }')
  say "sync check (glass failure): mark at ${want}s, biggest brightness jump at ${got:-none} (s, ΔY)"
fi

# ---- social clips and loops (docs/press/) ---------------------------------------------------------------------------
if [[ "$SOCIAL" == 1 ]]; then
  # social_cut <out> <segment> <start spec> <end spec> [min seconds]
  social_cut() {
    local out="$1" name="$2" min="${5:-6}" wav="$OUT_ABS/raw/$2.wav"
    seg_window "$name" "$3" "$4" || return 0
    calc_ok "$DUR < $min" && DUR="$min"
    calc_ok "$DUR > 10" && DUR=10
    [[ -f "$wav" ]] || wav=""
    social_clip "$OUT_ABS/raw/$name.mp4" "$A" "$DUR" "$wav" "$OFF" "$OUT_ABS/social/$out"
    say "social $out: ${DUR}s, $(du -h "$OUT_ABS/social/$out" | cut -f1)"
  }
  social_cut x-duck.mp4 duck "phase-pressing-0.6" "reveal+3.6" 8
  social_cut bluesky-glass.mp4 glass "phase-pressing-0.5" "failure+2.6,phase-sealed+1.0" 7
  social_cut mastodon-can.mp4 can "phase-pressing-0.5" "reveal+3.2" 7
  # Loop: the glass going, 3.4 s, silent; MP4 (1080 × 1920) and a 360 px GIF, each kept under 5 MB.
  seg_window glass "failure-1.4,phase-sealed-1.6" "failure+2.0,phase-sealed+1.8" && {
    social_clip "$OUT_ABS/raw/glass.mp4" "$A" "$DUR" "" 0 "$OUT_ABS/social/loop-glass.mp4"
    for spec in "15 360" "12 320" "10 270"; do
      read -r fps width <<< "$spec"
      ffmpeg -nostdin -y -v error -i "$OUT_ABS/social/loop-glass.mp4" \
        -vf "fps=$fps,scale=$width:-2:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
        -loop 0 "$OUT_ABS/social/loop-glass.gif"
      bytes=$(stat -f %z "$OUT_ABS/social/loop-glass.gif")
      say "loop-glass.gif at ${fps} fps ${width} px: $bytes bytes"
      (( bytes < 5000000 )) && break
    done
  }
  for f in "$OUT_ABS"/social/*; do [[ -f "$f" ]] && report_media "$f" | tee -a "$REPORT"; done
  frames "$OUT_ABS/social/x-duck.mp4" "$OUT_ABS/frames" 1.0 4.0 || true
fi

say "files:"; ls -la "$OUT_ABS" "$OUT_ABS/social" | tee -a "$REPORT"
(( FAILED == 0 )) || { say "error: preview-69.mp4 does not meet the App Store spec (see above)"; exit 5; }
