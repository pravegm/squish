#!/usr/bin/env bash
# Assemble the iPhone Duo App Store set (FOLD-REVIEW-5 §5 A and B) from a ci/duo-screenshots.sh output folder:
#
#   <DUO>/store/duo-inner/  2007 × 2853          <DUO>/store/duo-outer/  1398 × 2034
#     01-hero-duck          rubberDuck hero        O1-sealed         rubberDuck sealed cover, caption over its top
#     02-pair-can           sodaCan before/after   O2-cover-launch   closed-launch picker, framed
#     03-hero-glass         glassBottle hero
#     04-reveal-duck        rubberDuck tabletop reveal
#     05-shelf              Duo shelf (raw, framed under its caption)
#     06-variety            the grid (or the egg hero if there is no grid)
#     07-settings           optional: settings sheet (raw, framed)
#
# Frames the app already captioned (hero, pair, reveal, grid) are copied unchanged; raw UI frames are captioned here
# with ci/store-frame.swift. Each frame is checked for size and alpha; a MANIFEST.txt lists sources and captions.
# Never uses an 18 Pro folded shot, an -eye composite, a book-pose store shot or a raw tabletop frame.
#
# Usage: bash ci/store-set.sh [duo-screens]
# Env: STORE_HERO (rubberDuck), STORE_PAIR (sodaCan), STORE_SPECTACLE (glassBottle), STORE_REVEAL (rubberDuck),
#      STORE_VARIETY_FALLBACK (egg).
set -uo pipefail

DUO="${1:-duo-screens}"
HERO="${STORE_HERO:-rubberDuck}"
PAIR="${STORE_PAIR:-sodaCan}"
SPECTACLE="${STORE_SPECTACLE:-glassBottle}"
REVEAL="${STORE_REVEAL:-rubberDuck}"
VARIETY_FALLBACK="${STORE_VARIETY_FALLBACK:-egg}"
INNER="$DUO/store/duo-inner"
OUTER="$DUO/store/duo-outer"
MANIFEST="$DUO/store/MANIFEST.txt"
mkdir -p "$INNER" "$OUTER"
# shellcheck source=ci/store-frame.sh
source "$(dirname "$0")/store-frame.sh"
: >"$MANIFEST"
MISSING=0

note() { echo "$*" | tee -a "$MANIFEST"; }

# check <file> <WxH>
check() {
  local got
  got=$(png_size "$1")
  if [[ "${got%% *}" != "$2" || "$got" != *"alpha=no"* ]]; then
    note "   WARN $(basename "$1") is $got (want $2, no alpha)"
  fi
}

# copy_frame <dest name> <WxH> <source>... : the first source that exists.
copy_frame() {
  local dest="$1" size="$2" src
  shift 2
  for src in "$@"; do
    if [[ -f "$DUO/$src" ]]; then
      cp "$DUO/$src" "$dest"
      note "$(basename "$dest") <- $src"
      check "$dest" "$size"
      return 0
    fi
  done
  note "$(basename "$dest") MISSING (looked for: $*)"
  MISSING=$((MISSING + 1))
  return 1
}

# caption_frame <dest> <WxH> <style> <ink> <caption> <source>...
caption_frame() {
  local dest="$1" size="$2" style="$3" ink="$4" caption="$5" src
  shift 5
  for src in "$@"; do
    if [[ -f "$DUO/$src" ]]; then
      if store_frame --in "$DUO/$src" --out "$dest" --size "$size" --style "$style" --ink "$ink" --caption "$caption"; then
        note "$(basename "$dest") <- $src ($style) \"$caption\""
        check "$dest" "$size"
      else
        note "$(basename "$dest") FAILED to caption $src"
        MISSING=$((MISSING + 1))
      fi
      return 0
    fi
  done
  note "$(basename "$dest") MISSING (looked for: $*)"
  MISSING=$((MISSING + 1))
  return 1
}

note "== iPhone Duo inner display (2007x2853)"
copy_frame "$INNER/01-hero-duck.png" 2007x2853 "$HERO-storeshot-hero.png"
copy_frame "$INNER/02-pair-can.png" 2007x2853 "$PAIR-storeshot-pair.png"
copy_frame "$INNER/03-hero-glass.png" 2007x2853 "$SPECTACLE-storeshot-hero.png"
copy_frame "$INNER/04-reveal-duck.png" 2007x2853 "$REVEAL-storeshot-reveal.png"
caption_frame "$INNER/05-shelf.png" 2007x2853 framed dark \
  "A shelf of pressed *specimens*. / No ads. No in-app purchases." duo-shelf.png
copy_frame "$INNER/06-variety.png" 2007x2853 duo-storeshot-grid.png "$VARIETY_FALLBACK-storeshot-hero.png"
caption_frame "$INNER/07-settings.png" 2007x2853 framed dark \
  "Press without folding. Hear it *softer*. / Accessibility built in." duo-settings.png

note "== iPhone Duo outer display (1398x2034)"
caption_frame "$OUTER/O1-sealed.png" 1398x2034 overlay light "Ka-chunk. Now *open* it." \
  "$HERO-tabletop-closed.png" "$HERO-closed.png"
caption_frame "$OUTER/O2-cover-launch.png" 1398x2034 framed dark "Pick on the cover. Press *inside*." \
  duo-cover-launch.png

note "== checks before upload (FOLD-REVIEW-5 §5)"
note "   - 02: both pair labels must match the red/live readout on their device (the app logs labels=… per pair)."
note "   - 03: if the glass pile is invisible on the strike plate (N2), use the can hero here instead."
note "   - O1/O2: the cover frames come from the real cover display; check the caption sits on empty graphite."
note "missing or failed: $MISSING"
exit 0
