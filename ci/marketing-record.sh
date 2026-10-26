#!/usr/bin/env bash
# Records the marketing takes (ci/marketing/takes.txt) on one simulator and cuts each into a clip for
# ci/marketing/compose.mjs: clips/<name>.mov (30 fps, H.264 CRF 14, the app's own press sound as PCM, in sync) and
# clips/<name>.marks.txt (`<mark> <seconds into the clip>`, already shifted by the measured render latency, so a mark is
# where its picture is). docs/marketing/ASSETS.md explains the kit; ci/marketing.sh is the entry point.
#
# Reuses ci/preview-lib.sh (recordVideo start/stop, the AVFoundation re-time, mark specs, the flash calibration and the
# wall-clock audio placement) and the device handling of ci/preview.sh (P-48) and ci/preview-duo.sh (iPhone Duo).
#
# Env: DEVICE_KIND (p69|duo), GROUP (takes.txt group, default: all), ONLY (regex on take names, optional), OUT
#      (default marketing-raw), APP, BUNDLE; p69: DEVICE (auto:Pro Max); duo: UDID (booted iPhone Duo), DUO_HINGE.
# Outputs in $OUT: clips/, logs/, frames/ (a still per clip for review), REPORT.txt.
set -uo pipefail

DEVICE_KIND="${DEVICE_KIND:?set DEVICE_KIND to p69 or duo}"
GROUP="${GROUP:-}"
ONLY="${ONLY:-}"
OUT="${OUT:-marketing-raw}"
APP="${APP:-build/Build/Products/Debug-iphonesimulator/Squish.app}"
BUNDLE="${BUNDLE:-com.pravegm.squish}"
HERE="$(cd "$(dirname "$0")" && pwd)"
TAKES="${TAKES:-$HERE/marketing/takes.txt}"
mkdir -p "$OUT/raw" "$OUT/clips" "$OUT/logs" "$OUT/frames"
OUT_ABS="$(cd "$OUT" && pwd)"
REPORT="$OUT_ABS/REPORT-$DEVICE_KIND${GROUP:+-$GROUP}.txt"
RUNLOG="$OUT_ABS/logs/run-$DEVICE_KIND${GROUP:+-$GROUP}.txt"
: > "$REPORT"; : > "$RUNLOG"
# shellcheck source=ci/preview-lib.sh
source "$HERE/preview-lib.sh"
say() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$REPORT" >&2; }

if command -v gtimeout >/dev/null 2>&1; then TO=gtimeout; else TO=""; fi
to() { local s="$1"; shift; if [[ -n "$TO" ]]; then "$TO" -k 5 "$s" "$@"; else perl -e 'alarm shift; exec @ARGV' "$s" "$@"; fi; }

# ---- the takes for this job ----------------------------------------------------------------------------------------
BASE_P69=""; BASE_DUO=""
LINES=()
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" || "$line" == \#* ]] && continue
  case "$line" in
    @P69=*) BASE_P69="${line#@P69=}"; continue ;;
    @DUO=*) BASE_DUO="${line#@DUO=}"; continue ;;
  esac
  IFS='|' read -r dev grp name _ <<< "$line"
  [[ "$dev" == "$DEVICE_KIND" ]] || continue
  [[ -z "$GROUP" || "$grp" == "$GROUP" ]] || continue
  [[ -z "$ONLY" ]] || [[ "$name" =~ $ONLY ]] || continue
  LINES+=("$line")
done < "$TAKES"
(( ${#LINES[@]} > 0 )) || { say "no takes for device=$DEVICE_KIND group=${GROUP:-any} only=${ONLY:-any}"; exit 0; }
say "takes ($DEVICE_KIND${GROUP:+, group $GROUP}): $(for l in "${LINES[@]}"; do IFS='|' read -r _ _ n _ <<< "$l"; printf '%s ' "$n"; done)"
expand() { local s="$1"; s="${s//@P69/$BASE_P69}"; s="${s//@DUO/$BASE_DUO}"; echo "$s"; }

# ---- device ----------------------------------------------------------------------------------------------------------
INNER=""
if [[ "$DEVICE_KIND" == p69 ]]; then
  DEVICE="${DEVICE:-auto:Pro Max}"
  # The ci/preview.sh pick: the newest "… Pro Max" simulator on the newest runtime, created if missing.
  RESOLVE_PY='
import json, re, subprocess, sys
want = sys.argv[1]; auto = want.startswith("auto:"); suffix = want[5:] if auto else ""
def model(n):
    m = re.search(r"iPhone (\d+)", n); return int(m.group(1)) if m else 0
def rv(i):
    m = re.search(r"iOS-(\d+)-(\d+)", i); return (int(m.group(1)), int(m.group(2))) if m else (0, 0)
devs = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))["devices"]
found = [((model(d["name"]), rv(r)), d["udid"], d["name"]) for r, es in devs.items() if "iOS" in r for d in es
         if (auto and d["name"].startswith("iPhone") and d["name"].endswith(suffix)) or (not auto and d["name"] == want)]
if found:
    found.sort(reverse=True); print(found[0][1] + "\t" + found[0][2]); sys.exit(0)
if not auto: sys.exit(1)
lst = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "-j", "devicetypes", "runtimes"]))
types = sorted((t for t in lst["devicetypes"] if t["name"].startswith("iPhone") and t["name"].endswith(suffix)), key=lambda t: model(t["name"]), reverse=True)
rts = sorted((r for r in lst["runtimes"] if r.get("isAvailable") and "iOS" in r["identifier"]), key=lambda r: rv(r["identifier"]), reverse=True)
for t in types:
    for r in rts:
        sup = r.get("supportedDeviceTypes")
        if sup is None or any(s.get("identifier") == t["identifier"] for s in sup):
            print("CREATE\t" + t["identifier"] + "\t" + r["identifier"] + "\t" + t["name"]); sys.exit(0)
sys.exit(1)
'
  RESOLVED=$(python3 -I -c "$RESOLVE_PY" "$DEVICE") || { say "error: no simulator matches DEVICE='$DEVICE'"; exit 1; }
  if [[ "$RESOLVED" == CREATE* ]]; then
    IFS=$'\t' read -r _ TYPE_ID RUNTIME_ID DEVICE_NAME <<< "$RESOLVED"
    UDID=$(xcrun simctl create "$DEVICE_NAME" "$TYPE_ID" "$RUNTIME_ID")
  else
    IFS=$'\t' read -r UDID DEVICE_NAME <<< "$RESOLVED"
  fi
  say "simulator: $DEVICE_NAME ($UDID)"
  xcrun simctl boot "$UDID" 2>/dev/null || true
  xcrun simctl bootstatus "$UDID" -b >>"$RUNLOG" 2>&1
  xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 \
    --cellularMode active --cellularBars 4 --wifiBars 3 >>"$RUNLOG" 2>&1 || true
  xcrun simctl install "$UDID" "$APP" >>"$RUNLOG" 2>&1 || { say "FAIL install"; exit 1; }
else
  UDID="${UDID:?set UDID to the booted iPhone Duo simulator}"
  DUO_HINGE="${DUO_HINGE:-$HOME/duo-fold-control/tools/duo-hinge}"
  # The hinge CLI only lays the device open at 180° (the press itself is the app's hingescript). Optional here.
  HINGE_DRIVER=none
  if command -v hinge >/dev/null 2>&1 && to 30 hinge -d "$UDID" -t 3 180 >>"$RUNLOG" 2>&1; then HINGE_DRIVER=hinge
  elif [[ -x "$DUO_HINGE" ]] && to 30 "$DUO_HINGE" -d "$UDID" 180 >>"$RUNLOG" 2>&1; then HINGE_DRIVER=duo-hinge; fi
  say "hinge driver: $HINGE_DRIVER (only used to open the device to 180°)"
  probe_record() {   # probe_record <display name>: 0 when a 2 s recording on it produced a video
    local f="$OUT_ABS/raw/_probe-$1.mp4"; rm -f "$f"
    start_recording "$UDID" "$f" "$OUT_ABS/logs/probe-$1.txt" "$1" >>"$RUNLOG" 2>&1 || return 1
    fsleep 2; stop_recording >>"$RUNLOG" 2>&1
    [[ -s "$f" ]] && ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$f" >/dev/null 2>&1
  }
  for c in LCD-1 primary-1 3 internal; do
    if probe_record "$c"; then INNER="$c"; break; fi
  done
  rm -f "$OUT_ABS"/raw/_probe-*.mp4
  [[ -n "$INNER" ]] || { say "FAIL: recordVideo works on no inner display name"; exit 4; }
  say "inner display for recordVideo: $INNER"
  to 180 xcrun simctl install "$UDID" "$APP" >>"$RUNLOG" 2>&1 || { say "FAIL install"; exit 1; }
fi
app_docs() { echo "$(to 30 xcrun simctl get_app_container "$UDID" "$BUNDLE" data 2>/dev/null)/Documents"; }
open_flat() {
  case "${HINGE_DRIVER:-none}" in
    hinge) to 30 hinge -d "$UDID" -t 3 180 >>"$RUNLOG" 2>&1 || true ;;
    duo-hinge) to 30 "$DUO_HINGE" -d "$UDID" 180 >>"$RUNLOG" 2>&1 || true ;;
  esac
}
MARK_FILES="preview-marks.txt preview-script.txt slomo-marks.txt shelffill-marks.txt"
merged_marks() { local d="$1" f; for f in $MARK_FILES; do [[ -f "$d/$f" ]] && cat "$d/$f"; done; return 0; }

# ---- one recording ---------------------------------------------------------------------------------------------------
# record_take <name> <scenario> <stop spec>: raw/<name>.mp4 (re-timed), .marks.txt, .wav, .timing, logs/<name>.txt.
record_take() {
  local name="$1" scen="$2" stop="$3" docs log="$OUT_ABS/logs/$1.txt" display="" st alt f rot m t0
  to 30 xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  [[ "$DEVICE_KIND" == duo ]] && { open_flat; display="$INNER"; }
  docs="$(app_docs)"; mkdir -p "$docs"
  for f in $MARK_FILES press-audio.wav press-audio.txt; do rm -f "$docs/$f"; done
  : > "$log"
  start_recording "$UDID" "$OUT_ABS/raw/$name.mp4" "$OUT_ABS/logs/$name.rec.txt" "$display" >>"$RUNLOG" 2>&1 \
    || { say "WARN $name: recordVideo did not start"; return 1; }
  fsleep 0.8
  to 60 xcrun simctl launch --terminate-running-process --stdout="$log" --stderr="$log" \
    "$UDID" "$BUNDLE" -squishDemo "$scen" >>"$RUNLOG" 2>&1 || say "WARN $name: launch failed"
  # Stop: the first alternative whose mark appears (180 s cap), plus its seconds. No pipe into `grep -q` here: under
  # pipefail a reader that quits early, or a marks file not written yet, reads as "not found" (run 40292182261).
  st=""; t0=$SECONDS
  IFS=',' read -r -a alts <<< "$stop"
  while (( SECONDS - t0 < 180 )); do
    m=$'\n'"$(merged_marks "$docs")"
    for alt in "${alts[@]}"; do
      if [[ "$alt" =~ ^(.+)\+([0-9.]+)$ ]] && [[ "$m" == *$'\n'"${BASH_REMATCH[1]} "* ]]; then
        st="${BASH_REMATCH[2]}"; say "   $name: stop mark ${BASH_REMATCH[1]} seen after $((SECONDS - t0)) s; recording ${st} s more"; break 2
      fi
    done
    fsleep 0.25
  done
  [[ -n "$st" ]] && fsleep "$st" || say "WARN $name: no stop mark ($stop) after 180 s"
  stop_recording >>"$RUNLOG" 2>&1
  rot=$(ffprobe -v error -select_streams v:0 -show_entries stream_side_data=rotation -of csv=p=0 "$OUT_ABS/raw/$name.mp4" 2>/dev/null | head -1)
  echo "rec_epoch=$REC_EPOCH rotation=${rot:-0}" > "$OUT_ABS/raw/$name.timing"
  RETIMED=0
  local r; r=$(retime "$OUT_ABS/raw/$name.mp4"); say "   $name $r"
  if [[ "$r" != *"retimed "* ]]; then sleep 3; r=$(retime "$OUT_ABS/raw/$name.mp4"); say "   $name (retry) $r"; fi
  [[ "$r" == *"retimed "* ]] && RETIMED=1
  if [[ "$scen" == *pressaudio* ]]; then
    wait_for_log "$log" "SQUISH-T pressaudio (ok|failed)" 150 || say "WARN $name: no pressaudio line"
    grep -h "SQUISH-T pressaudio" "$log" | tee -a "$REPORT" >&2 || true
  fi
  merged_marks "$docs" > "$OUT_ABS/raw/$name.marks.txt"
  cp "$docs/press-audio.wav" "$OUT_ABS/raw/$name.wav" 2>/dev/null || true
  grep -h "SQUISH-T \(slomo\|hingescript\|orient\|mark\|demo\)" "$log" | cut -c1-200 | tee -a "$REPORT" >&2 || true
  say "   $name raw: $(probe_video "$OUT_ABS/raw/$name.mp4" 2>/dev/null) rotation=${rot:-0}; marks: $(awk '{print $1}' "$OUT_ABS/raw/$name.marks.txt" | tr '\n' ' ' | cut -c1-400)"
  to 30 xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  return 0
}

is_book() { [[ "$(grep -F "|$1|" "$TAKES")" == *orient=landscape* ]]; }
rec_of() { sed -E 's/.*rec_epoch=([0-9.]+).*/\1/' "$OUT_ABS/raw/$1.timing" 2>/dev/null; }
rot_of() { sed -E 's/.*rotation=(-?[0-9]+).*/\1/' "$OUT_ABS/raw/$1.timing" 2>/dev/null; }
len_of() { ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT_ABS/raw/$1.mp4" 2>/dev/null; }
# at <name> <spec|end>: seconds into raw/<name>.mp4, or nothing.
at() {
  local e rec len
  rec=$(rec_of "$1"); len=$(len_of "$1")
  [[ -n "$rec" && -n "$len" ]] || return 0
  if [[ "$2" == end ]]; then calc "$len - 0.1"; return 0; fi
  e=$(spec_epoch "$OUT_ABS/raw/$1.marks.txt" "$2")
  [[ -n "$e" ]] && calc "$e - $rec"
  return 0
}

# take_gap <name> <from spec> <to spec>: the longest frame gap in the action (from → the failure + 1 s, or the
# stop of the shown close, or the clip end), 99 when the take is unusable.
take_gap() {
  local a b g
  [[ -f "$OUT_ABS/raw/$1.mp4" && "$RETIMED" == 1 ]] || { echo 99; return 0; }
  a=$(at "$1" "$2"); b=$(at "$1" "failure+1.0,script-58+0.3,shelffill-done,$3")
  [[ -z "$b" && "$3" == end ]] && b=$(at "$1" end)
  [[ -n "$a" && -n "$b" ]] || { echo 99; return 0; }
  g=$(frame_gaps "$OUT_ABS/raw/$1.mp4" "$a" "$b")
  say "   $1 action window ${a}s → ${b}s: $g" >&2
  g="${g#*maxgap=}"; echo "${g%% *}"
}
TAKE_FILES="mp4 marks.txt wav timing"
keep_take() { local x; for x in $TAKE_FILES; do [[ -f "$OUT_ABS/raw/$1.$x" ]] && mv "$OUT_ABS/raw/$1.$x" "$OUT_ABS/raw/$1.take$2.$x"; done; return 0; }
use_take() { local x; for x in $TAKE_FILES; do rm -f "$OUT_ABS/raw/$1.$x"; [[ -f "$OUT_ABS/raw/$1.take$2.$x" ]] && mv "$OUT_ABS/raw/$1.take$2.$x" "$OUT_ABS/raw/$1.$x"; done; return 0; }

# calibrate <name>: seconds the picture lags the engine (the failure flash vs the failure mark), 0..0.7, else 0. The
# Fold Press and the P-48 both whiten the top of the screen on a failure; book pose (rotated in the raw file) measures
# the whole frame.
calibrate() {
  local name="$1" f rec fv from dur crop="crop=iw:ih/2:0:0" min=8 res
  f=$(mark_epoch "$OUT_ABS/raw/$name.marks.txt" failure); rec=$(rec_of "$name")
  [[ -n "$f" && -n "$rec" ]] || { echo 0; return 0; }
  is_book "$name" && { crop="crop=iw:ih:0:0"; min=4; }
  fv=$(calc "$f - $rec"); from=$(calc "$fv - 0.3"); dur=1.1
  res=$(ffmpeg -nostdin -v error -i "$OUT_ABS/raw/$name.mp4" \
      -vf "trim=start=$from:duration=$dur,setpts=PTS-STARTPTS,$crop,scale=180:-2,signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=-" -f null - 2>/dev/null \
    | awk -v base="$from" '/pts_time/ { split($0, p, "pts_time:"); t = p[2] + 0 }
        /YAVG/ { split($0, y, "="); v = y[2] + 0; if (have && v - last > best) { best = v - last; at = t }; last = v; have = 1 }
        END { if (have && best > 0) printf "%.3f %.1f", base + at, best }')
  if [[ -n "$res" ]]; then
    local d rise; d=$(calc "${res%% *} - $fv"); rise="${res##* }"
    if calc_ok "$d >= -0.1 && $d <= 0.7 && $rise >= $min"; then
      say "   calibrate $name: flash ${d}s after the failure mark (dY $rise)" >&2; echo "$d"; return 0
    fi
    say "   calibrate $name: flash at +${d}s (dY $rise) implausible; by clock only" >&2
  fi
  echo 0
}

# export_clip <name> <from spec> <to spec>: clips/<name>.mov + clips/<name>.marks.txt + clips/<name>.info
export_clip() {
  local name="$1" a b dur cal rec origin off vf rot wav="$OUT_ABS/raw/$1.wav" pose=flat
  a=$(at "$name" "$2"); b=$(at "$name" "$3")
  [[ -n "$a" ]] || { say "WARN $name: no clip start for '$2'"; return 1; }
  [[ -n "$b" ]] || { b=$(at "$name" end); say "WARN $name: no clip end for '$3'; to the end of the recording"; }
  calc_ok "$a < 0" && a=0
  local len; len=$(len_of "$name"); calc_ok "$b > $len - 0.05" && b=$(calc "$len - 0.05")
  dur=$(calc "$b - $a")
  calc_ok "$dur > 0.5" || { say "WARN $name: empty clip window ${a}s → ${b}s"; return 1; }
  cal=$(calibrate "$name"); rec=$(rec_of "$name")
  origin=$(mark_epoch "$OUT_ABS/raw/$name.marks.txt" origin)
  rot=$(rot_of "$name")
  if [[ "$DEVICE_KIND" == p69 ]]; then
    vf="fps=30,setsar=1,format=yuv420p"; pose=p69
  else
    # The inner display, re-timed (the re-time drops the display matrix): tabletop is upright as stored; book pose
    # (the landscape interface) lies on its side, so it is turned by the recording's own matrix (BOOK_TRANSPOSE
    # overrides it: clock | cclock).
    vf=""
    if is_book "$name"; then
      pose=book
      case "${BOOK_TRANSPOSE:-${rot:-0}}" in
        clock|-90|270) vf="transpose=clock," ;;
        180|-180) vf="hflip,vflip," ;;
        *) vf="transpose=cclock," ;;
      esac
      vf="${vf}scale=2048:-2:flags=lanczos,fps=30,setsar=1,format=yuv420p"
    else
      pose=tabletop; vf="${vf}scale=1440:-2:flags=lanczos,fps=30,setsar=1,format=yuv420p"
    fi
  fi
  [[ -f "$wav" && -n "$origin" ]] || wav=""
  off=$(calc "${origin:-$rec} - $rec + $cal")
  local tv="[0:v]trim=start=$a:duration=$dur,setpts=PTS-STARTPTS,$vf[v]"
  if [[ -n "$wav" ]]; then
    ffmpeg -nostdin -y -v error -i "$OUT_ABS/raw/$name.mp4" -i "$wav" \
      -filter_complex "$tv;[1:a]$(audio_chain "$(calc "$a - $off")" "$dur")[a]" \
      -map "[v]" -map "[a]" -t "$dur" -r 30 -c:v libx264 -preset medium -crf 14 -pix_fmt yuv420p -g 30 \
      -c:a pcm_s16le "$OUT_ABS/clips/$name.mov" || { say "WARN $name: clip encode failed"; return 1; }
  else
    ffmpeg -nostdin -y -v error -i "$OUT_ABS/raw/$name.mp4" -f lavfi -i "anullsrc=r=48000:cl=stereo" \
      -filter_complex "$tv" -map "[v]" -map 1:a -t "$dur" -r 30 -c:v libx264 -preset medium -crf 14 -pix_fmt yuv420p \
      -g 30 -c:a pcm_s16le "$OUT_ABS/clips/$name.mov" || { say "WARN $name: clip encode failed"; return 1; }
  fi
  # Marks in clip seconds, where the picture shows them (+ the calibrated render latency).
  awk -v rec="$rec" -v a="$a" -v cal="$cal" '{ e = $2; sub("epoch=", "", e); if (e + 0 > 0) printf "%s %.3f\n", $1, e - rec - a + cal }' \
    "$OUT_ABS/raw/$name.marks.txt" > "$OUT_ABS/clips/$name.marks.txt"
  local w h gap
  w=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$OUT_ABS/clips/$name.mov")
  h=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$OUT_ABS/clips/$name.mov")
  gap=$(frame_gaps "$OUT_ABS/raw/$name.mp4" "$a" "$b")
  printf 'name=%s\ndevice=%s\npose=%s\nwidth=%s\nheight=%s\nduration=%s\ncalibration=%s\nsound=%s\nrotation=%s\ngaps=%s\n' \
    "$name" "$DEVICE_KIND" "$pose" "$w" "$h" "$dur" "$cal" "$([[ -n "$wav" ]] && echo app || echo none)" "${rot:-0}" "$gap" \
    > "$OUT_ABS/clips/$name.info"
  say "clip $name: ${w}x${h} ${dur}s from ${a}s (sound $([[ -n "$wav" ]] && echo yes || echo NO), calibration ${cal}s; $gap)"
  ffmpeg -nostdin -y -v error -ss "$(calc "$dur / 2")" -i "$OUT_ABS/clips/$name.mov" -frames:v 1 -vf "scale=540:-2" \
    "$OUT_ABS/frames/$name-mid.png" || true
}

# ---- warm-up (never kept: the first launch compiles shaders and builds the deformation state) ------------------------
if [[ "$DEVICE_KIND" == p69 ]]; then
  record_take _warmup "object=rubberDuck;reveal;seed=3;notoasts;nocoach;previewmarks" "reveal+2" || true
else
  record_take _warmup "object=rubberDuck;hingescript=4;$BASE_DUO" "script-160+2" || true
fi
rm -f "$OUT_ABS"/raw/_warmup.*

# ---- the takes -------------------------------------------------------------------------------------------------------
FAILED=0
for line in "${LINES[@]}"; do
  IFS='|' read -r _ _ name scen stop from to takes <<< "$line"
  scen=$(expand "$scen")
  say "=== $name: $scen"
  best=""; best_gap=99
  for attempt in $(seq 1 "${takes:-1}"); do
    record_take "$name" "$scen" "$stop" || true
    gap=$(take_gap "$name" "$from" "$to")
    keep_take "$name" "$attempt"
    say "   $name take $attempt: longest frame gap ${gap}s"
    if calc_ok "$gap < $best_gap"; then best=$attempt; best_gap=$gap; fi
    calc_ok "$gap <= 0.25" && break
  done
  if [[ -z "$best" ]] || calc_ok "$best_gap >= 99"; then say "ERROR $name: no usable take"; FAILED=$((FAILED + 1)); continue; fi
  use_take "$name" "$best"
  rm -f "$OUT_ABS"/raw/"$name".take*.*
  calc_ok "$best_gap > 0.3" && say "WARN $name: best take still holds a frame for ${best_gap}s"
  RETIMED=1
  export_clip "$name" "$from" "$to" || FAILED=$((FAILED + 1))
  rm -f "$OUT_ABS/raw/$name.mp4"   # 2006 × 2852 at up to 60 fps: far too big to keep once cut
done
ls -la "$OUT_ABS/clips" | tee -a "$REPORT" >&2
say "done: ${#LINES[@]} take(s), $FAILED failed"
exit 0
