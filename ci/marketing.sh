#!/usr/bin/env bash
# The Instagram marketing kit (docs/marketing/ASSETS.md; brief: docs/marketing/PLAN.md §0). Entry point for
# .github/workflows/marketing.yml, and runnable by hand on any Mac (Intel is fine for everything but `record`).
#
#   bash ci/marketing.sh record                 record the takes on a booted simulator (ci/marketing-record.sh; env
#                                               DEVICE_KIND=p69|duo, GROUP, UDID for the Duo). Needs Xcode 27.1.
#   bash ci/marketing.sh assets <dir> [run]     the stills the kit builds on: the app icon (press-kit release) and the
#                                               uncaptioned App Store renders of store.yml run <run> (default 40222956174)
#   bash ci/marketing.sh font <dir>             Nunito (SIL OFL 1.1) from google/fonts at a pinned commit, hash-checked
#   bash ci/marketing.sh compose <clips> <assets> <out> [footage]
#                                               the videos (ci/marketing/compose.mjs), the stills (statics.mjs), the zip.
#                                               Needs ffmpeg, node ≥ 22, Google Chrome and NUNITO_FONT (see `font`).
#
# Real-hand footage (docs/marketing/SHOOT-GUIDE.md): put the founder's chosen takes in a folder as S1.mov … S12.mov (an
# optional S4.in holding the start second) and pass it as [footage]; segments marked `real:` in ci/marketing/cuts.mjs
# use them instead of the simulator. Keep that folder out of the repo (it is public).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
cmd="${1:-}"; shift || true

# Nunito at google/fonts 8b0a1d0 (12 Mar 2026). Git blob hashes from the GitHub contents API, checked with git hash-object.
NUNITO_COMMIT=8b0a1d0f5983c89bc2b93f1b5fb55f9e252744b5
NUNITO_TTF_BLOB=2ec1f4b0676c83ef33049db87b311171699e9192
NUNITO_OFL_BLOB=c8210f08ca3cece05b4f7baa428afe8e1abe3293

case "$cmd" in
  record)
    exec bash "$HERE/marketing-record.sh" ;;

  font)
    dir="${1:?font <dir>}"; mkdir -p "$dir"
    base="https://raw.githubusercontent.com/google/fonts/$NUNITO_COMMIT/ofl/nunito"
    curl -fsSL --retry 3 "$base/Nunito%5Bwght%5D.ttf" -o "$dir/Nunito[wght].ttf"
    curl -fsSL --retry 3 "$base/OFL.txt" -o "$dir/Nunito-OFL.txt"
    [[ "$(git hash-object "$dir/Nunito[wght].ttf")" == "$NUNITO_TTF_BLOB" ]] || { echo "Nunito hash mismatch"; exit 1; }
    [[ "$(git hash-object "$dir/Nunito-OFL.txt")" == "$NUNITO_OFL_BLOB" ]] || { echo "OFL.txt hash mismatch"; exit 1; }
    echo "Nunito ok: $dir/Nunito[wght].ttf (google/fonts@$NUNITO_COMMIT, SIL OFL 1.1)" ;;

  assets)
    dir="${1:?assets <dir> [store run]}"; run="${2:-40222956174}"
    mkdir -p "$dir/store" "$dir/_dl"
    gh release download press-kit -R pravegm/squish -p "squish-icon-1024.png" -D "$dir/_dl" --clobber
    cp "$dir/_dl/squish-icon-1024.png" "$dir/icon.png"
    # The uncaptioned FoldStoreShot renders (store-duo) are what the stills crop; a missing run is not fatal.
    if gh run download "$run" -R pravegm/squish -n store-duo -D "$dir/_dl/store-duo" 2>/dev/null; then
      for f in rubberDuck-storeshot-hero glassBottle-storeshot-hero sodaCan-storeshot-pair rubberDuck-storeshot-reveal \
               glassBottle-storeshot-112 duo-storeshot-grid duo-shelf; do
        src=$(find "$dir/_dl/store-duo" -name "$f.png" -not -path "*/verify/*" -not -path "*/raw/*" | head -1)
        [[ -n "$src" ]] && cp "$src" "$dir/store/$f.png" || echo "warning: store render $f.png not in run $run"
      done
    else
      echo "warning: could not download store-duo from run $run (expired?); the stills fall back to placeholders"
    fi
    rm -rf "$dir/_dl"
    ls -la "$dir" "$dir/store" ;;

  compose)
    clips="${1:?compose <clips> <assets> <out> [footage]}"; assets="${2:?}"; out="${3:?}"; footage="${4:-$HERE/marketing/footage}"
    mkdir -p "$out"
    node "$HERE/marketing/compose.mjs" --clips "$clips" --assets "$assets" --out "$out" --footage "$footage" ${ONLY:+--only "$ONLY"}
    node "$HERE/marketing/statics.mjs" --clips "$clips" --assets "$assets" --out "$out"
    [[ -f "${NUNITO_FONT%/*}/Nunito-OFL.txt" ]] && cp "${NUNITO_FONT%/*}/Nunito-OFL.txt" "$out/LICENSE-Nunito-OFL.txt" || true
    # The upload zip: every deliverable, none of the working files or QC frames.
    (cd "$out" && rm -f squish-marketing-kit.zip && zip -qr squish-marketing-kit.zip reels reels-week3+ stories feed profile \
       LICENSE-Nunito-OFL.txt REPORT.md -x '*/_work/*' 2>/dev/null || true)
    ls -la "$out" ;;

  *)
    sed -n 2,20p "$0"; exit 2 ;;
esac
