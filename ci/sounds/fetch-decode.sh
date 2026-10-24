#!/usr/bin/env bash
# Fetch every source in ci/sounds/sources.tsv, check its sha256, and decode it to 48 kHz mono 16-bit WAV.
#   bash ci/sounds/fetch-decode.sh ci/sounds/sources.tsv <download-dir> <decoded-dir>
# Plain files decode to <decoded>/<key>.wav. Zips (Kenney packs) decode each .ogg/.wav member to
# <decoded>/<key>--<member-basename>.wav. Needs curl, unzip and ffmpeg (CI: ubuntu-latest + apt ffmpeg).
# Downloads are data: nothing inside them is ever executed.
set -euo pipefail

sources=${1:?sources.tsv}
dl=${2:?download dir}
out=${3:?decoded dir}
mkdir -p "$dl" "$out"

decode() { # in out
  ffmpeg -nostdin -hide_banner -loglevel error -y -i "$1" -ac 1 -ar 48000 -c:a pcm_s16le "$2"
}

failed=0
while IFS=$'\t' read -r key kind url sha _rest; do
  [[ "$key" == "key" || -z "$key" ]] && continue
  ext=${url##*.}
  file="$dl/$key.$ext"
  if [[ ! -s "$file" ]]; then
    if ! curl -fsSL --retry 3 -A "Mozilla/5.0 (Squish sound pipeline)" -o "$file" "$url"; then
      echo "FETCH-FAIL $key $url"; failed=$((failed + 1)); rm -f "$file"; continue
    fi
  fi
  got=$(sha256sum "$file" | cut -d' ' -f1)
  if [[ "$got" != "$sha" ]]; then
    echo "SHA-MISMATCH $key expected $sha got $got"; failed=$((failed + 1)); continue
  fi
  case "$kind" in
    file)
      decode "$file" "$out/$key.wav" || { echo "DECODE-FAIL $key"; failed=$((failed + 1)); }
      ;;
    zip)
      tmp="$dl/$key.unzipped"
      rm -rf "$tmp"; mkdir -p "$tmp"
      unzip -q -o "$file" -d "$tmp"
      while IFS= read -r -d '' member; do
        base=$(basename "${member%.*}")
        decode "$member" "$out/$key--$base.wav" || { echo "DECODE-FAIL $key/$base"; failed=$((failed + 1)); }
      done < <(find "$tmp" -type f \( -iname '*.ogg' -o -iname '*.wav' \) ! -iname 'preview*' -print0)
      ;;
    *)
      echo "UNKNOWN-KIND $key $kind"; failed=$((failed + 1))
      ;;
  esac
done < "$sources"

count=$(find "$out" -name '*.wav' | wc -l | tr -d ' ')
echo "decoded: $count  failed: $failed"
[[ $failed -eq 0 ]]
