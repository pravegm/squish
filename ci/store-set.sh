#!/usr/bin/env bash
# Assemble the iPhone Duo App Store set (FOLD-REVIEW-6 §3 A ordering, N7) from a ci/duo-screenshots.sh output folder:
#
#   <DUO>/store/duo-inner/  2007 × 2853          <DUO>/store/duo-outer/  1398 × 2034
#     01-hero-duck          rubberDuck hero        O1-sealed         rubberDuck sealed cover, caption over its top
#     02-pair-can           sodaCan before/after   O2-cover-launch   closed-launch idle picker, framed
#     03-reveal-duck        rubberDuck tabletop reveal (the payoff, in the search-results triplet); if it is MISSING,
#                           03-reveal-can (the sodaCan reveal) as a FALLBACK the founder must sign off (see reveal_frame)
#     04-hero-glass         glassBottle hero (its own camera: the other end of the device)
#     05-variety            the grid: glass, can, cake, jelly (or the jelly hero if there is no grid)
#     06-shelf              Duo shelf (raw, framed under its caption)
#     07-settings           settings sheet (raw, framed): Soft sound + Press without folding on, as its caption says
#
# Frames the app already captioned (hero, pair, reveal, grid) are copied unchanged; raw UI frames are captioned here
# with ci/store-frame.swift. Each frame is checked for size and alpha AND against the run's logs (FOLD-REVIEW-6 N15):
#  - a store shot needs its "SQUISH-T storeshot <label> ok" line in <DUO>/logs/<object>-tabletop.txt;
#  - the reveal also needs "ok" in logs/reveal-checks.txt (ci/duo-screenshots.sh: phase=revealing at the ~150°
#    capture, FOLD-REVIEW-6 N2; no reveal-checks.txt = not checked = MISSING) and phase=revealing on the app's own
#    reveal line; otherwise it is MISSING, never a picture of the next object;
#  - the representative pair/hero objects must log golden=0 surprise=none (N6: the seed is pinned, but say so);
#  - O2 must not come from a launch whose log shows the engine leaving idle (N3 phantom seal).
#
# FOLD-REVIEW-8 N1/N5 ("flagged: 0" must be true): EVERY check that can fail is counted, and the MANIFEST's last line
# says how many ran. A check that fails is MISSING (no frame written) or FLAGGED (listed; the run is red):
#  - output size and alpha of every frame (`check`: R8 only printed a WARN, never counted);
#  - the SOURCE of every captioned frame must be its display's portrait size before it is framed: Duo inner 2007 × 2853,
#    Duo outer 1398 × 2034 (`caption_frame`). R8's 07 was framed from a 2853 × 2007 landscape capture with the app in its
#    left half and the right half black. A wrong-size source is FLAGGED and its frame is not written;
#  - the raw inner UI frames (06 shelf, 07 settings) need the app's "SQUISH-T orient portrait ok" line in their log;
#  - the app-rendered frames (01–05) need `inframe=1` on their store-shot line: every device inside the frame
#    (FOLD-REVIEW-8 N5, R8's 01 cut the duck's base corner at x 0);
#  - a log a check needs that is missing fails that check (R8's flag_if passed silently without its log);
#  - the grid pass ran (logs/grid.txt) but left no grid: 05 falls back to the jelly hero, FLAGGED.
# What no script can see (is the crack visible, is the shelf full, does the caption read) stays a manual sign-off:
# the MANIFEST lists those checks under "checks before upload". Never upload a frame nobody has looked at.
# Never uses an 18 Pro folded shot, an -eye composite, a book-pose store shot, a raw tabletop frame or anything in
# <DUO>/verify/ (pass 5 review frames).
#
# Usage: bash ci/store-set.sh [duo-screens]       Exit 1 when anything is missing or flagged, or when 03 is an
#                                                 unapproved fallback (duo.yml keeps going).
# Env: STORE_HERO (rubberDuck), STORE_PAIR (sodaCan), STORE_SPECTACLE (glassBottle), STORE_REVEAL (rubberDuck),
#      STORE_REVEAL_FALLBACK (sodaCan; empty = none), STORE_REVEAL_FALLBACK_APPROVED (0; 1 once the founder has signed
#      the fallback off), STORE_VARIETY_FALLBACK (jelly), STORE_ORIENT (portrait: the orient line 06/07 need).
set -uo pipefail

DUO="${1:-duo-screens}"
HERO="${STORE_HERO:-rubberDuck}"
PAIR="${STORE_PAIR:-sodaCan}"
SPECTACLE="${STORE_SPECTACLE:-glassBottle}"
REVEAL="${STORE_REVEAL:-rubberDuck}"
# FOLD-REVIEW-7 §3 A 03: the can reveal completes the can story from 02; empty = no fallback.
REVEAL_FALLBACK="${STORE_REVEAL_FALLBACK-sodaCan}"
FALLBACK_APPROVED="${STORE_REVEAL_FALLBACK_APPROVED:-0}"
VARIETY_FALLBACK="${STORE_VARIETY_FALLBACK:-jelly}"
ORIENT="${STORE_ORIENT:-portrait}"
INNER_SIZE=2007x2853
OUTER_SIZE=1398x2034
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
FALLBACK=0
CHECKS=0

note() { echo "$*" | tee -a "$MANIFEST"; }

# flag <dest> <why>: one failed check on a frame that was made (or deliberately not written); counted.
flag() {
  note "   FLAGGED $(basename "$1"): $2"
  FLAGGED=$((FLAGGED + 1))
}

# check <file> <WxH>: the output frame's size and alpha (App Store Connect rejects any other size, and alpha).
check() {
  local got
  CHECKS=$((CHECKS + 1))
  got=$(png_size "$1")
  if [[ "${got%% *}" != "$2" || "$got" != *"alpha=no"* ]]; then
    flag "$1" "is $got (want $2, no alpha)"
  fi
}

# source_ok <source> <WxH>: prints nothing when the source image is exactly WxH (a portrait capture of that display),
# else why not. Alpha doesn't matter here: store-frame flattens the frame.
source_ok() {
  local got
  got=$(png_size "$1")
  [[ "${got%% *}" == "$2" ]] && return 0
  echo "source $(basename "$1") is ${got%% *}, not $2 (a portrait capture of its display)"
}

# storeshot_line <object> <label>: the app's last "SQUISH-T storeshot <label> ok …" line for that object, or empty.
storeshot_line() {
  grep -E "SQUISH-T storeshot $2 ok" "$LOGS/$1-tabletop.txt" 2>/dev/null | tail -1
}

# bounds_check <dest> <app line>: FOLD-REVIEW-8 N5, every device inside the frame (`inframe=1` on the app's line).
bounds_check() {
  local dest="$1" line="$2" bounds
  CHECKS=$((CHECKS + 1))
  bounds=$(grep -oE ' frame=[^ ]+' <<<"$line" | tail -1)
  bounds="${bounds# }"
  if [[ "$line" == *"inframe=1"* ]]; then return 0; fi
  if [[ "$line" == *"inframe=0"* ]]; then
    flag "$dest" "a device leaves the frame (${bounds:-frame=?}, output px x0-x1/y0-y1)"
  else
    flag "$dest" "no inframe= on the app's store-shot line (build older than FOLD-REVIEW-8 N5?): device bounds unchecked"
  fi
}

# verify <dest name> <object> <label> [plain]: the log checks for a store shot; prints why it fails, nothing if fine.
# `plain` also requires golden=0 and surprise=none (the representative object of a frame).
verify() {
  local name="$1" obj="$2" label="$3" plain="${4:-}" line
  if [[ ! -f "$LOGS/$obj-tabletop.txt" ]]; then echo "no log $LOGS/$obj-tabletop.txt"; return; fi
  line=$(storeshot_line "$obj" "$label")
  if [[ -z "$line" ]]; then echo "no 'SQUISH-T storeshot $label ok' line in $obj-tabletop.txt"; return; fi
  if [[ "$label" == reveal ]]; then
    # R8 skipped this check when reveal-checks.txt was absent; an unchecked reveal is not a checked one.
    if [[ ! -f "$LOGS/reveal-checks.txt" ]]; then
      echo "no logs/reveal-checks.txt (ci/duo-screenshots.sh never checked the reveal was up at the capture)"
      return
    fi
    if ! grep -qE "^$obj ok" "$LOGS/reveal-checks.txt"; then
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
  CHECKS=$((CHECKS + 1))
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
      if [[ "$obj" != - ]]; then bounds_check "$dest" "$(storeshot_line "$obj" "$label")"; fi
      return 0
    fi
  done
  note "$(basename "$dest") MISSING (looked for: $*)"
  MISSING=$((MISSING + 1))
  return 1
}

# caption_frame <dest> <WxH> <style> <ink> <caption> <source>... : the first source that exists, framed under its
# caption. FOLD-REVIEW-8 N1: the source must already be WxH, the display's portrait size (inner 2007 × 2853, outer
# 1398 × 2034); any other source is FLAGGED and not framed, so a landscape capture can never be letterboxed into a
# store frame again.
caption_frame() {
  local dest="$1" size="$2" style="$3" ink="$4" caption="$5" src why
  shift 5
  rm -f "$dest"
  CHECKS=$((CHECKS + 1))
  for src in "$@"; do
    if [[ -f "$DUO/$src" ]]; then
      CHECKS=$((CHECKS + 1))
      why=$(source_ok "$DUO/$src" "$size")
      if [[ -n "$why" ]]; then
        note "$(basename "$dest") NOT WRITTEN from $src"
        flag "$dest" "$why"
        return 1
      fi
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

# flag_if <dest> <log> <regex> <why>: a frame that was made but whose source log shows a known-bad state. A frame
# without its log can't be checked, so that is FLAGGED too (R8 returned 0).
flag_if() {
  [[ -f "$1" ]] || return 0
  CHECKS=$((CHECKS + 1))
  if [[ ! -f "$2" ]]; then flag "$1" "no log $(basename "$2"), so this is unchecked: $4"; return 0; fi
  if grep -qE "$3" "$2" 2>/dev/null; then
    flag "$1" "$4 ($(grep -E "$3" "$2" | tail -1))"
  fi
}

# flag_unless <dest> <log> <regex> <why>: the frame's log must have a line matching regex (missing log = FLAGGED).
flag_unless() {
  [[ -f "$1" ]] || return 0
  CHECKS=$((CHECKS + 1))
  if ! grep -qE "$3" "$2" 2>/dev/null; then
    flag "$1" "$4 (no line matching '$3' in $(basename "$2")$([[ -f "$2" ]] || echo ': log missing'))"
  fi
}

# orient_check <dest> <log>: a raw inner UI frame must come from a launch that reached the wanted orientation
# (PressDirector's orient hook; with no Fold Press stage it also needs the window and screen bounds portrait).
orient_check() {
  flag_unless "$1" "$2" "SQUISH-T orient $ORIENT ok" "the app never confirmed $ORIENT (orient line: $(grep 'SQUISH-T orient' "$2" 2>/dev/null | tail -1 || true))"
}

# Frame 03, the payoff (FOLD-REVIEW-7 §3 A 03, top fix #1): the $REVEAL reveal. If it is MISSING (no frame, or it fails
# its log checks), and only then, the $REVEAL_FALLBACK reveal stands in, written under its own object's name
# (03-reveal-<object>.png, never 03-reveal-duck.png) after the same log checks (ok line, reveal still up at the
# capture, phase=revealing, plain variant), and listed as FALLBACK: the founder must sign it off. Until
# STORE_REVEAL_FALLBACK_APPROVED=1 says so, a fallback keeps the run red. A fallback that fails its checks too leaves
# 03 MISSING; no other object is ever tried.
reveal_name() {
  case "$1" in
    rubberDuck) echo duck ;;
    sodaCan) echo can ;;
    glassBottle) echo glass ;;
    cakeSlice) echo cake ;;
    *) echo "$1" ;;
  esac
}
reveal_frame() {
  local primary fallback missing_before="$MISSING" why
  primary="$INNER/03-reveal-$(reveal_name "$REVEAL").png"
  fallback="$INNER/03-reveal-$(reveal_name "$REVEAL_FALLBACK").png"
  rm -f "$INNER"/03-reveal-*.png
  copy_frame "$primary" "$INNER_SIZE" "$REVEAL" reveal plain "$REVEAL-storeshot-reveal.png" && return 0
  if [[ -z "$REVEAL_FALLBACK" || "$REVEAL_FALLBACK" == "$REVEAL" ]]; then return 1; fi
  if [[ ! -f "$DUO/$REVEAL_FALLBACK-storeshot-reveal.png" ]]; then
    note "   no fallback for 03: $REVEAL_FALLBACK-storeshot-reveal.png is not in this run either"
    return 1
  fi
  why=$(verify "$(basename "$fallback")" "$REVEAL_FALLBACK" reveal plain)
  if [[ -n "$why" ]]; then
    note "   no fallback for 03: $REVEAL_FALLBACK-storeshot-reveal.png fails its log check: $why"
    return 1
  fi
  cp "$DUO/$REVEAL_FALLBACK-storeshot-reveal.png" "$fallback"
  MISSING="$missing_before"
  FALLBACK=$((FALLBACK + 1))
  note "$(basename "$fallback") <- $REVEAL_FALLBACK-storeshot-reveal.png FALLBACK for 03: the $REVEAL reveal is MISSING (above)."
  if [[ "$FALLBACK_APPROVED" == 1 ]]; then
    note "   FALLBACK approved (STORE_REVEAL_FALLBACK_APPROVED=1): upload it as frame 03."
  else
    note "   FALLBACK NOT APPROVED: the founder must sign off the $REVEAL_FALLBACK reveal as frame 03 (FOLD-REVIEW-7 §6), then re-run with STORE_REVEAL_FALLBACK_APPROVED=1 or upload it by hand."
  fi
  check "$fallback" "$INNER_SIZE"
  bounds_check "$fallback" "$(storeshot_line "$REVEAL_FALLBACK" reveal)"
  return 0
}

# The grid's source objects: each needs a hero this run (the app logs the missing ones).
grid_missing=""
grid_line=""
if [[ -f "$LOGS/grid.txt" ]]; then
  grid_line=$(grep -E "SQUISH-T storeshot grid ok" "$LOGS/grid.txt" | tail -1)
  grid_missing=$(sed -n 's/.*SQUISH-T storeshot grid ok.* missing=\([^ ]*\).*/\1/p' "$LOGS/grid.txt" | tail -1)
fi

note "== iPhone Duo inner display ($INNER_SIZE)"
copy_frame "$INNER/01-hero-duck.png" "$INNER_SIZE" "$HERO" hero plain "$HERO-storeshot-hero.png"
copy_frame "$INNER/02-pair-can.png" "$INNER_SIZE" "$PAIR" pair plain "$PAIR-storeshot-pair.png"
reveal_frame
copy_frame "$INNER/04-hero-glass.png" "$INNER_SIZE" "$SPECTACLE" hero plain "$SPECTACLE-storeshot-hero.png"
if [[ -f "$DUO/duo-storeshot-grid.png" ]]; then
  if copy_frame "$INNER/05-variety.png" "$INNER_SIZE" - - - duo-storeshot-grid.png; then
    CHECKS=$((CHECKS + 1))
    if [[ -z "$grid_line" ]]; then
      flag "$INNER/05-variety.png" "no 'SQUISH-T storeshot grid ok' line in logs/grid.txt"
    else
      [[ -n "$grid_missing" ]] && flag "$INNER/05-variety.png" "the grid is missing objects: $grid_missing"
      bounds_check "$INNER/05-variety.png" "$grid_line"
    fi
  fi
else
  copy_frame "$INNER/05-variety.png" "$INNER_SIZE" "$VARIETY_FALLBACK" hero plain "$VARIETY_FALLBACK-storeshot-hero.png"
  if [[ -f "$INNER/05-variety.png" && -f "$LOGS/grid.txt" ]]; then
    CHECKS=$((CHECKS + 1))
    flag "$INNER/05-variety.png" "the grid pass ran (logs/grid.txt) but wrote no duo-storeshot-grid.png: the $VARIETY_FALLBACK hero stands in"
  fi
fi
caption_frame "$INNER/06-shelf.png" "$INNER_SIZE" framed dark \
  "A shelf of pressed *specimens*. / No ads. No in-app purchases." duo-shelf.png
orient_check "$INNER/06-shelf.png" "$LOGS/duo-shelf.txt"
caption_frame "$INNER/07-settings.png" "$INNER_SIZE" framed dark \
  "Press without folding. Hear it *softer*. / Accessibility built in." duo-settings.png
orient_check "$INNER/07-settings.png" "$LOGS/duo-settings.txt"
# FOLD-REVIEW-6 N5: the caption is only true if the demo state was applied.
flag_unless "$INNER/07-settings.png" "$LOGS/duo-settings.txt" "SQUISH-T demo settings .*soundstyle=soft.*nofold=on" \
  "the demo settings line is missing, so the caption may be false"

note "== iPhone Duo outer display ($OUTER_SIZE)"
caption_frame "$OUTER/O1-sealed.png" "$OUTER_SIZE" overlay light "Ka-chunk. Now *open* it." \
  "$HERO-tabletop-closed.png" "$HERO-closed.png"
caption_frame "$OUTER/O2-cover-launch.png" "$OUTER_SIZE" framed dark "Pick on the cover. Press *inside*." \
  duo-cover-launch.png
flag_if "$OUTER/O2-cover-launch.png" "$LOGS/duo-cover-launch.txt" "SQUISH-H .* phase=(armed|pressing|sealed|revealing)" \
  "the closed launch left idle, so the cover shows a press, not the picker (FOLD-REVIEW-6 N3)"

note "== checks before upload (manual: no script sees these; FOLD-REVIEW-6, -8)"
note "   - 01/04: the AT nn° mark sits on the sweep above the lid, clear of the caption; the duck is visible under the lid shadow; no device edge or corner touches the frame edge."
note "   - 02: both pair labels must match the readout on their device (the app logs labels=… per pair); the can is plain green."
note "   - 03: the reveal shows the flattened duck and its print (or, as a signed-off FALLBACK, the crushed can and its print), never an intact next object."
note "   - 06: the shelf fills the sheet (both halves of the grid, the Golden card visible); 'Recently squished' shows prints, not intact objects."
note "   - 07: the settings sheet fills the portrait frame (no black half, no letterbox)."
note "   - O2: the idle picker (chip grid, 'Open to press'), no PRESS SEALED card."
note "   - verify/ (if present) holds review frames only: never upload them."
unapproved=0
(( FALLBACK > 0 )) && [[ "$FALLBACK_APPROVED" != 1 ]] && unapproved=$FALLBACK
if (( FALLBACK > 0 )); then
  note "missing: $MISSING  flagged: $FLAGGED  fallback: $FALLBACK ($([[ "$FALLBACK_APPROVED" == 1 ]] && echo approved || echo "NOT approved: founder sign-off needed"))  checks: $CHECKS"
else
  note "missing: $MISSING  flagged: $FLAGGED  checks: $CHECKS"
fi
(( MISSING + FLAGGED + unapproved > 0 )) && exit 1
exit 0
