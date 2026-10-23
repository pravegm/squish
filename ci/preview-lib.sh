#!/usr/bin/env bash
# Shared helpers for ci/preview.sh (6.9-inch App Preview) and ci/preview-duo.sh (iPhone Duo App Preview).
# Sourced, never run. Needs ffmpeg/ffprobe (brew install ffmpeg), perl and awk.
#
# Timing model (docs/appstore/preview-video.md, "How it's made"):
#  - `simctl io recordVideo` prints "Recording started" when its first frame is taken; the script notes the host's
#    wall clock then (REC_EPOCH). Video time v = epoch - REC_EPOCH.
#  - The app (`-squishDemo …;pressaudio` / `previewmarks`, DEBUG) writes Documents/preview-marks.txt with the wall-clock
#    epoch of each moment (origin = object placed, phase-pressing, fracture-n, failure, phase-sealed, reveal, closed,
#    opened). The simulator shares the host clock, so marks and REC_EPOCH are on one timeline.
#  - press-audio.wav (sample 0 = origin) is the press's own sound, rendered offline by the app from the same trace, so
#    the audio for video time v is at wav time v - (ORIGIN - REC_EPOCH).

now_epoch() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time'; }
fsleep() { perl -e "select(undef,undef,undef,$1)"; }
calc() { awk "BEGIN { printf \"%.3f\", $1 }"; }
# calc_ok "<awk condition>": exit status of an awk boolean.
calc_ok() { awk "BEGIN { exit !($1) }"; }

# mark_epoch <marks file> <name>: the epoch of the first mark called <name>, or nothing.
mark_epoch() {
  [[ -f "$1" ]] || return 0
  awk -v n="$2" '$1 == n { sub("epoch=", "", $2); print $2; exit }' "$1"
}

# spec_epoch <marks file> <spec>: a spec is "<mark>[+|-]<seconds>", alternatives separated by commas (the first whose
# mark exists wins), e.g. "failure+2.2,phase-sealed+0.6". Prints the epoch, or nothing when no alternative matched.
spec_epoch() {
  local marks="$1" spec="$2" alt name sign secs e re='^(.+)([+-])([0-9.]+)$'
  local -a alts=()
  IFS=',' read -r -a alts <<< "$spec"
  for alt in "${alts[@]}"; do
    if [[ "$alt" =~ $re ]]; then name="${BASH_REMATCH[1]}"; sign="${BASH_REMATCH[2]}"; secs="${BASH_REMATCH[3]}"
    else name="$alt"; sign="+"; secs=0; fi
    e=$(mark_epoch "$marks" "$name")
    if [[ -n "$e" ]]; then calc "$e $sign $secs"; return 0; fi
  done
  return 0
}

# wait_for_mark <marks file> <name> <seconds>: 0 once the mark is in the file.
wait_for_mark() {
  local t=0 max=$(( $3 * 10 ))
  while (( t < max )); do
    [[ -n "$(mark_epoch "$1" "$2")" ]] && return 0
    fsleep 0.1; t=$((t + 1))
  done
  return 1
}

# wait_for_log <log> <ERE> <seconds>
wait_for_log() {
  local t=0
  while (( t < $3 )); do grep -qE "$2" "$1" 2>/dev/null && return 0; sleep 1; t=$((t + 1)); done
  return 1
}

# start_recording <udid> <out.mp4> <stderr file> [display]: starts `simctl io recordVideo` in the background and waits
# for "Recording started". Sets REC_PID and REC_EPOCH (the wall clock when it said so; spawn + 1 s if it never did).
start_recording() {
  local udid="$1" out="$2" err="$3" display="${4:-}" t=0 spawned
  local -a args=(--codec=h264 --force)
  [[ -n "$display" ]] && args+=("--display=$display")
  : > "$err"
  spawned=$(now_epoch)
  xcrun simctl io "$udid" recordVideo "${args[@]}" "$out" 2>"$err" >/dev/null &
  REC_PID=$!
  REC_EPOCH=""
  while (( t < 150 )); do
    if grep -q "Recording started" "$err" 2>/dev/null; then REC_EPOCH=$(now_epoch); break; fi
    kill -0 "$REC_PID" 2>/dev/null || break
    fsleep 0.1; t=$((t + 1))
  done
  if [[ -z "$REC_EPOCH" ]]; then
    REC_EPOCH=$(calc "$spawned + 1.0")
    echo "warning: recordVideo never said 'Recording started' ($(tr '\n' ' ' < "$err" | cut -c1-200)); assuming spawn + 1 s"
  fi
  kill -0 "$REC_PID" 2>/dev/null || { echo "error: recordVideo exited: $(cat "$err")"; return 1; }
  return 0
}

# stop_recording [pid]: SIGINT (recordVideo finalises the file on SIGINT), then wait.
stop_recording() {
  local pid="${1:-$REC_PID}" t=0
  kill -INT "$pid" 2>/dev/null || true
  while kill -0 "$pid" 2>/dev/null && (( t < 300 )); do fsleep 0.1; t=$((t + 1)); done
  kill -0 "$pid" 2>/dev/null && { echo "warning: recordVideo $pid did not stop; killing"; kill -9 "$pid" 2>/dev/null || true; }
  wait "$pid" 2>/dev/null || true
}

# retime <file.mp4>: re-time a recordVideo file in place with ci/preview-retime.swift (built once with swiftc): frames
# in presentation order at their true times, no reordering, so ffmpeg reads the same timeline the app's marks use.
# Prints one line; returns 1 (file untouched) when it can't.
RETIME_BIN=""
retime() {
  local f="$1" tmp="${1%.mp4}.retimed.mp4" out src
  if [[ -z "$RETIME_BIN" ]]; then
    RETIME_BIN="${TMPDIR:-/tmp}/squish-preview-retime"
    src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/preview-retime.swift"
    if ! out=$(xcrun swiftc -O "$src" -o "$RETIME_BIN" 2>&1); then
      echo "warning: could not build preview-retime: $(echo "$out" | grep -m3 error)"; RETIME_BIN=none
    fi
  fi
  [[ "$RETIME_BIN" == none ]] && return 1
  if out=$("$RETIME_BIN" "$f" "$tmp" 2>&1); then mv "$tmp" "$f"; echo "   $out"; return 0; fi
  echo "warning: $out"; rm -f "$tmp"; return 1
}

# probe_video <file>: one line "WxH fps=<r_frame_rate> avg=<avg_frame_rate> frames=<n> dur=<s> start=<s>".
probe_video() {
  local w h r a n d s
  w=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$1")
  h=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$1")
  r=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 "$1")
  a=$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of csv=p=0 "$1")
  n=$(ffprobe -v error -select_streams v:0 -count_packets -show_entries stream=nb_read_packets -of csv=p=0 "$1")
  d=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$1")
  s=$(ffprobe -v error -select_streams v:0 -show_entries stream=start_time -of csv=p=0 "$1")
  echo "${w}x${h} fps=$r avg=$a frames=$n dur=$d start=$s"
}

# frame_gaps <video> <from s> <to s>: "frames=<n> maxgap=<s> at=<s>" for the frames whose time is in [from, to].
# recordVideo writes a frame only when the screen changes, so a render stall shows up as one long gap (the duck press
# of run 39965173658: the whole squash missing, the unpressed frame then the reveal).
frame_gaps() {
  ffprobe -v error -select_streams v:0 -show_entries packet=pts_time -of csv=p=0 "$1" 2>/dev/null \
    | sort -g | awk -v a="$2" -v b="$3" '$1 + 0 >= a && $1 + 0 <= b { t = $1 + 0; n++; if (have && t - last > gap) { gap = t - last; at = last }; last = t; have = 1 }
        END { printf "frames=%d maxgap=%.3f at=%.3f", n, gap, at }'
}

# flash_time <video> <from s> <to s>: the time (s, in the file) of the biggest frame-to-frame rise in the mean brightness
# of the top half of the picture, and the rise: "<t> <dY>". The failure flash (RootView FailureFlash) whitens the top
# half, so this finds when a failure became visible.
flash_time() {
  local from="$2" dur
  dur=$(calc "$3 - $2")
  ffmpeg -nostdin -v error -i "$1" \
      -vf "trim=start=$from:duration=$dur,setpts=PTS-STARTPTS,crop=iw:ih/2:0:0,scale=180:-2,signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=-" -f null - 2>/dev/null \
    | awk -v base="$from" '/pts_time/ { split($0, p, "pts_time:"); t = p[2] + 0 }
        /YAVG/ { split($0, y, "="); v = y[2] + 0; if (have && v - last > best) { best = v - last; at = t }; last = v; have = 1 }
        END { if (have && best > 0) printf "%.3f %.1f", base + at, best }'
}

# audio_chain <wav start seconds (may be negative)> <duration>: an ffmpeg audio filter chain (after the input label)
# that takes [start, start + duration) of the WAV, padding silence before 0 and after its end, with 30 ms fades at the
# cut points so a hard cut never clicks, as 48 kHz stereo.
audio_chain() {
  local s="$1" dur="$2" lead=0 chain
  if calc_ok "$s < 0"; then lead=$(calc "-($s) * 1000"); s=0; fi
  chain="atrim=start=$s,asetpts=PTS-STARTPTS"
  calc_ok "$lead > 0" && chain="$chain,adelay=delays=${lead%.*}:all=1"
  chain="$chain,apad,atrim=0:$dur,asetpts=PTS-STARTPTS,aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo"
  chain="$chain,afade=t=in:d=0.03,afade=t=out:st=$(calc "$dur - 0.04"):d=0.04"
  echo "$chain"
}

# cut_segment <raw.mp4> <video start s> <duration s> <wav|""> <wav offset s> <video filter> <out.mov>
# A lossless-enough intermediate (x264 CRF 12, PCM audio), exactly <duration> at 30 fps. The wav offset is
# ORIGIN - REC_EPOCH: wav time = video time - offset. No WAV: a silent stereo track.
cut_segment() {
  local raw="$1" a="$2" dur="$3" wav="$4" off="$5" vf="$6" out="$7" ws
  # Never `-ss` before `-i` on a recordVideo file: on these variable-frame-rate recordings (1/600 time base) the input
  # seek landed seconds away from the asked time (run 39965173658: the duck cut showed the reveal 3.5 s in, while the
  # raw file, checked frame by frame, matched the marks exactly). Decode from the start and `trim` by timestamp.
  local tv="[0:v]trim=start=$a:duration=$dur,setpts=PTS-STARTPTS,$vf[v]"
  if [[ -n "$wav" && -f "$wav" ]]; then
    ws=$(calc "$a - $off")
    ffmpeg -nostdin -y -v error -i "$raw" -i "$wav" \
      -filter_complex "$tv;[1:a]$(audio_chain "$ws" "$dur")[a]" \
      -map "[v]" -map "[a]" -t "$dur" -r 30 -c:v libx264 -preset medium -crf 12 -pix_fmt yuv420p \
      -c:a pcm_s16le "$out"
  else
    ffmpeg -nostdin -y -v error -i "$raw" -f lavfi -i "anullsrc=r=48000:cl=stereo" \
      -filter_complex "$tv" -map "[v]" -map 1:a -t "$dur" -r 30 \
      -c:v libx264 -preset medium -crf 12 -pix_fmt yuv420p -c:a pcm_s16le "$out"
  fi
}

# finish_preview <out.mp4> <level> <segment.mov>...: hard cuts, one encode at App Store settings (H.264 High, 30 fps
# CFR, 11 Mbit/s target / 12 max, keyframe every second; stereo AAC 256 kbit/s 48 kHz, −16 LUFS / −1.5 dBTP).
finish_preview() {
  local out="$1" level="$2" list
  shift 2
  list="$(dirname "$out")/concat-$(basename "$out").txt"
  : > "$list"
  for s in "$@"; do echo "file '$(cd "$(dirname "$s")" && pwd)/$(basename "$s")'" >> "$list"; done
  ffmpeg -nostdin -y -v error -f concat -safe 0 -i "$list" \
    -af "loudnorm=I=-16:TP=-1.5:LRA=11,aresample=48000" \
    -c:v libx264 -profile:v high -level:v "$level" -pix_fmt yuv420p -r 30 -g 30 \
    -b:v 11M -maxrate 12M -bufsize 22M -c:a aac -b:a 256k -ac 2 -ar 48000 -movflags +faststart "$out"
}

# report_media <file>: the ffprobe facts an App Store upload is judged on.
report_media() {
  echo "== $(basename "$1"): $(du -h "$1" | cut -f1)"
  ffprobe -v error -show_entries format=duration,size,bit_rate:stream=codec_name,profile,level,width,height,r_frame_rate,avg_frame_rate,pix_fmt,sample_rate,channels,bit_rate \
    -of default=noprint_wrappers=1 "$1" | sed 's/^/   /'
  echo "   loudness: $(ffmpeg -nostdin -v info -i "$1" -af ebur128=peak=true -f null - 2>&1 | grep -E '^\s+(I:|Peak:)' | tr -s ' ' | tr '\n' ' ')"
}

# frames <video> <dir> <t>...: PNG stills at the given times (seconds), named <basename>-<t>s.png.
frames() {
  local v="$1" dir="$2" t
  shift 2
  mkdir -p "$dir"
  for t in "$@"; do
    ffmpeg -nostdin -y -v error -ss "$t" -i "$v" -frames:v 1 "$dir/$(basename "${v%.*}")-${t}s.png" || true
  done
}

# social_from_master <preview.mp4> <start> <dur> <out.mp4>: a social_clip cut from a finished preview (its own sound).
social_from_master() {
  ffmpeg -nostdin -y -v error -ss "$2" -t "$3" -i "$1" \
    -filter_complex "[0:v]split[bg][fg];[bg]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=40:3,eq=brightness=-0.12[b];[fg]scale=1080:1920:force_original_aspect_ratio=decrease[f];[b][f]overlay=(W-w)/2:(H-h)/2,setsar=1,format=yuv420p[v];[0:a]afade=t=in:d=0.03,afade=t=out:st=$(calc "$3 - 0.05"):d=0.05,loudnorm=I=-14:TP=-1.5:LRA=11,aresample=48000[a]" \
    -map "[v]" -map "[a]" -t "$3" -r 30 -c:v libx264 -profile:v high -level:v 4.2 -preset slow \
    -b:v 4500k -maxrate 6M -bufsize 9M -g 30 -c:a aac -b:a 160k -ac 2 -movflags +faststart "$4"
}

# social_clip <raw> <a> <dur> <wav|""> <off> <out.mp4>: 1080 × 1920 9:16 for X / Bluesky / Mastodon. The phone screen
# (taller than 9:16) is fitted to the height and centred over a blurred, darkened copy of itself, so no UI is cropped.
# H.264 High 4.2, 4.5 Mbit/s, AAC 160 kbit/s stereo at −14 LUFS (social norm). Silent when there is no WAV.
social_clip() {
  local raw="$1" a="$2" dur="$3" wav="$4" off="$5" out="$6" ws
  local vf="[0:v]fps=30,split[bg][fg];[bg]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=40:3,eq=brightness=-0.12[b];[fg]scale=-2:1920[f];[b][f]overlay=(W-w)/2:0,setsar=1,format=yuv420p[v]"
  vf="[0:v]trim=start=$a:duration=$dur,setpts=PTS-STARTPTS,${vf#\[0:v\]}"   # trim, never input -ss (cut_segment)
  if [[ -n "$wav" && -f "$wav" ]]; then
    ws=$(calc "$a - $off")
    ffmpeg -nostdin -y -v error -i "$raw" -i "$wav" \
      -filter_complex "$vf;[1:a]$(audio_chain "$ws" "$dur"),loudnorm=I=-14:TP=-1.5:LRA=11,aresample=48000[a]" \
      -map "[v]" -map "[a]" -t "$dur" -r 30 -c:v libx264 -profile:v high -level:v 4.2 -preset slow \
      -b:v 4500k -maxrate 6M -bufsize 9M -g 30 -c:a aac -b:a 160k -ac 2 -movflags +faststart "$out"
  else
    ffmpeg -nostdin -y -v error -i "$raw" -filter_complex "$vf" -map "[v]" -t "$dur" -r 30 \
      -c:v libx264 -profile:v high -level:v 4.2 -preset slow -b:v 4500k -maxrate 6M -bufsize 9M -g 30 \
      -movflags +faststart "$out"
  fi
}
