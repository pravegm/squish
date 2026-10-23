#!/usr/bin/env bash
# Assemble the iPhone Duo App Store set (FOLD-REVIEW-6 §3 A ordering, N7) from a ci/duo-screenshots.sh output folder:
#
#   <DUO>/store/duo-inner/  2007 × 2853          <DUO>/store/duo-outer/  1398 × 2034
#     01-hero-duck          rubberDuck hero        O1-sealed         rubberDuck sealed cover, caption over its top
#     02-pair-can           sodaCan before/after   O2-cover-launch   closed-launch idle picker, framed
#     03-reveal-duck        rubberDuck tabletop reveal (the payoff, in the search-results triplet)
#     04-hero-glass         glassBottle hero (its own camera: the other end of the device)
#     05-variety            the grid: glass, can, cake, jelly (or the jelly hero if there is no grid)
#     06-shelf              Duo shelf (raw, framed under its caption)
#     07-settings           settings sheet (raw, framed): Soft sound + Press without folding on, as its caption says
#
# Frames the app already captioned (hero, pair, reveal, grid) are copied unchanged; raw UI frames are captioned here
# with ci/store-frame.swift. Each frame is checked for size and alpha AND against the run's logs (FOLD-REVIEW-6 N15):
#  - a store shot needs its "SQUISH-T storeshot <label> ok" line in <DUO>/logs/<object>-tabletop.txt;
#  - the reveal also needs "ok" in logs/reveal-checks.txt (ci/duo-screenshots.sh: phase=revealing at the ~150°
#    capture, FOLD-REVIEW-6 N2) and phase=revealing on the app's own reveal line; otherwise it is MISSING, never a
#    picture of the next object;
#  - the representative pair/hero objects must log golden=0 surprise=none (N6: the seed is pinned, but say so);
#  - O2 must not come from a launch whose log shows the engine leaving idle (N3 phantom seal).
# A frame that fails a check is not copied (any old copy is removed) and is listed as MISSING or FLAGGED.
# Never uses an 18 Pro folded shot, an -eye composite, a book-pose store shot or a raw tabletop frame.
#
# Usage: bash ci/store-set.sh [duo-screens]       Exit 1 when anything is missing or flagged (duo.yml keeps going).
# Env: STORE_HERO (rubberDuck), STORE_PAIR (sodaCan), STORE_SPECTACLE (glassBottle), STORE_REVEAL (rubberDuck),
#      STORE_VARIETY_FALLBACK (jelly).
set -uo pipefail

DUO="${1:-duo-screens}"
HERO="${STORE_HERO:-rubberDuck}"
PAIR="${STORE_PAIR:-sodaCan}"
SPECTACLE="${STORE_SPECTACLE:-glassBottle}"
REVEAL="${STORE_REVEAL:-rubberDuck}"
VARIETY_FALLBACK="${STORE_VARIETY_FALLBACK:-jelly}"
INNER="$DUO/store/duo-inner"
OUTER="$DUO/store/duo-outer"
MANIFEST="$DUO/store/MANIFEST.txt"
LOGS="$DUO/logs"
mkdir -p "$INNER" "$OUTER"
# shellcheck source=ci/store-frame.sh
source "$(dirname "$0")/store-frame.sh"
: >"$MANIFEST"
MISSING=0
FLAGGED=0

note() { echo "$*" | tee -a "$MANIFEST"; }

# check <file> <WxH>
check() {
  local got
  got=$(png_size "$1")
  if [[ "${got%% *}" != "$2" || "$got" != *"alpha=no"* ]]; then
    note "   WARN $(basename "$1") is $got (want $2, no alpha)"
  fi
}

# storeshot_line <object> <label>: the app's last "SQUISH-T storeshot <label> ok …" line for that object, or empty.
storeshot_line() {
  grep -E "SQUISH-T storeshot $2 ok" "$LOGS/$1-tabletop.txt" 2>/dev/null | tail -1
}

# verify <dest name> <object> <label> [plain]: the log checks for a store shot; prints why it fails, nothing if fine.
# `plain` also requires golden=0 and surprise=none (the representative object of a frame).
verify() {
  local name="$1" obj="$2" label="$3" plain="${4:-}" line
  if [[ ! -f "$LOGS/$obj-tabletop.txt" ]]; then echo "no log $LOGS/$obj-tabletop.txt"; return; fi
  line=$(storeshot_line "$obj" "$label")
  if [[ -z "$line" ]]; then echo "no 'SQUISH-T storeshot $label ok' line in $obj-tabletop.txt"; return; fi
  if [[ "$label" == reveal ]]; then
    if [[ -f "$LOGS/reveal-checks.txt" ]] && ! grep -qE "^$obj ok" "$LOGS/reveal-checks.txt"; then
      echo "reveal check: $(grep -E "^$obj " "$LOGS/reveal-checks.txt" | tail -1 || true) (the reveal was not up at the capture)"
      return
    fi
    [[ "$line" == *"phase=revealing"* ]] || { echo "the app's reveal line is not phase=revealing: $line"; return; }
  fi
  if [[ "$plain" == plain ]]; then
    # The variant fields are on the single-shot lines (hero, reveal, angles; logged since R7), not on the pair's, so
    # the pair is judged by its object's hero line. A line without golden= (an older build) passes.
    local variant="$line"
    [[ "$variant" == *"golden="* ]] || variant=$(storeshot_line "$obj" hero)
    if [[ "$variant" == *"golden=1"* ]]; then echo "a Golden variant ($variant)"; return; fi
    if [[ "$variant" == *"surprise="* && "$variant" != *"surprise=none"* ]]; then
      echo "a surprise variant ($variant)"; return
    fi
  fi
}

# copy_frame <dest> <WxH> <object|-> <label|-> <plain|-> <source>... : the first source that exists, after the log checks.
copy_frame() {
  local dest="$1" size="$2" obj="$3" label="$4" plain="$5" src why
  shift 5
  rm -f "$dest"
  for src in "$@"; do
    if [[ -f "$DUO/$src" ]]; then
      why=""
      if [[ "$obj" != - ]]; then why=$(verify "$(basename "$dest")" "$obj" "$label" "$plain"); fi
      if [[ -n "$why" ]]; then
        note "$(basename "$dest") MISSING: $src fails its log check: $why"
        MISSING=$((MISSING + 1))
        return 1
      fi
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
  rm -f "$dest"
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

# flag_if <dest> <log> <regex> <why>: a frame that was made but whose source log shows a known-bad state.
flag_if() {
  [[ -f "$1" && -f "$2" ]] || return 0
  if grep -qE "$3" "$2" 2>/dev/null; then
    note "   FLAGGED $(basename "$1"): $4 ($(grep -E "$3" "$2" | tail -1))"
    FLAGGED=$((FLAGGED + 1))
  fi
}

# The grid's source objects: each needs a hero this run (the app logs the missing ones).
grid_missing=""
[[ -f "$LOGS/grid.txt" ]] && grid_missing=$(sed -n 's/.*SQUISH-T storeshot grid ok.* missing=\([^ ]*\).*/\1/p' "$LOGS/grid.txt" | tail -1)

note "== iPhone Duo inner display (2007x2853)"
copy_frame "$INNER/01-hero-duck.png" 2007x2853 "$HERO" hero plain "$HERO-storeshot-hero.png"
copy_frame "$INNER/02-pair-can.png" 2007x2853 "$PAIR" pair plain "$PAIR-storeshot-pair.png"
copy_frame "$INNER/03-reveal-duck.png" 2007x2853 "$REVEAL" reveal plain "$REVEAL-storeshot-reveal.png"
copy_frame "$INNER/04-hero-glass.png" 2007x2853 "$SPECTACLE" hero plain "$SPECTACLE-storeshot-hero.png"
if [[ -f "$DUO/duo-storeshot-grid.png" ]]; then
  copy_frame "$INNER/05-variety.png" 2007x2853 - - - duo-storeshot-grid.png
  if [[ -n "$grid_missing" ]]; then
    note "   FLAGGED 05-variety.png: the grid is missing objects: $grid_missing"
    FLAGGED=$((FLAGGED + 1))
  fi
else
  copy_frame "$INNER/05-variety.png" 2007x2853 "$VARIETY_FALLBACK" hero plain "$VARIETY_FALLBACK-storeshot-hero.png"
fi
caption_frame "$INNER/06-shelf.png" 2007x2853 framed dark \
  "A shelf of pressed *specimens*. / No ads. No in-app purchases." duo-shelf.png
caption_frame "$INNER/07-settings.png" 2007x2853 framed dark \
  "Press without folding. Hear it *softer*. / Accessibility built in." duo-settings.png
# FOLD-REVIEW-6 N5: the caption is only true if the demo state was applied.
if [[ -f "$INNER/07-settings.png" ]] && ! grep -qE "SQUISH-T demo settings .*soundstyle=soft.*nofold=on" "$LOGS/duo-settings.txt" 2>/dev/null; then
  note "   FLAGGED 07-settings.png: no 'demo settings soundstyle=soft … nofold=on' line in duo-settings.txt (caption may be false)"
  FLAGGED=$((FLAGGED + 1))
fi

note "== iPhone Duo outer display (1398x2034)"
caption_frame "$OUTER/O1-sealed.png" 1398x2034 overlay light "Ka-chunk. Now *open* it." \
  "$HERO-tabletop-closed.png" "$HERO-closed.png"
caption_frame "$OUTER/O2-cover-launch.png" 1398x2034 framed dark "Pick on the cover. Press *inside*." \
  duo-cover-launch.png
flag_if "$OUTER/O2-cover-launch.png" "$LOGS/duo-cover-launch.txt" "SQUISH-H .* phase=(armed|pressing|sealed|revealing)" \
  "the closed launch left idle, so the cover shows a press, not the picker (FOLD-REVIEW-6 N3)"

note "== checks before upload (FOLD-REVIEW-6)"
note "   - 01/04: the AT nn° mark sits on the sweep above the lid, clear of the caption; the duck is visible under the lid shadow."
note "   - 02: both pair labels must match the readout on their device (the app logs labels=… per pair); the can is plain green."
note "   - 03: the reveal shows the flattened duck and its print, never an intact next object."
note "   - 06: the shelf fills the sheet (both halves of the grid, the Golden card visible)."
note "   - O2: the idle picker (chip grid, 'Open to press'), no PRESS SEALED card."
note "missing: $MISSING  flagged: $FLAGGED"
(( MISSING + FLAGGED > 0 )) && exit 1
exit 0
