#!/usr/bin/env bash
# Regenerates ci/sounds/cuts.tsv: the sample shopping list turned into exact excerpts (design/SOUND-2.md §3, §5).
#   bash ci/sounds/make-cuts.sh <decoded-dir> > ci/sounds/cuts.tsv
# `p` asks propose.mjs to slice a dense source at its onsets (grains, pops); `r` writes a hand-picked excerpt
# (loops, events, heroes). cut.mjs auto-trims leading/trailing silence, so `r` windows can be generous.
# Files are renumbered per prefix at the end (glass_shatter_01, _02, ...), so rows can be added or dropped freely.
# Norm targets: heroes m-12, events m-16, quiet details m-20, grains p-6, beds i-24/-26, UI m-22 (all capped at -1 dBTP).
# EQ: pk3300:-5:1.4 notches the 2.5–4.5 kHz "grating" band on sustained tonal material (research 02 §1).
set -euo pipefail
D=${1:?decoded dir}
here=$(cd "$(dirname "$0")" && pwd)
p() { node "$here/propose.mjs" "$D" "$@"; }
r() { # path src start end fade norm hp lp loop eq note
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@"
}
NOTCH='pk3300:-5:1.4'

{
# ---------- Press (shared by every object) ----------
r press/press_hiss_loop.caf      fs861613 2.0 5.4 0,0 i-26 200 9000 400 - "pneumatic hiss bed; rate and gain follow closing speed"
r press/press_release.caf        fs275550 0.0 1.5 2,450 m-20 150 0 0 - "release sigh as the lid lifts"
r press/press_release.caf        fs416080 0.0 1.4 2,400 m-20 150 11000 0 - "release sigh as the lid lifts"
r press/press_release.caf        fs131934 0.0 1.4 2,400 m-20 150 11000 0 - "release sigh as the lid lifts"
r press/press_kachunk_latch.caf  fs460352 0.0 0.6 0,60 m-14L4 60 0 0 - "ka-chunk mechanical latch layer (under the synth ka-chunk)"
r press/press_kachunk_latch.caf  fs538379 0.0 0.86 0,80 m-14L4 60 0 0 - "ka-chunk mechanical latch layer"
for n in 000 001 002 003 004; do
  r press/press_kachunk_metal.caf "kenney-impact--impactMetal_heavy_$n" 0 2 0,80 m-14L4 60 0 0 - "ka-chunk metal body"
done
for n in 000 001 002 003 004; do
  r press/press_contact_soft.caf "kenney-impact--impactSoft_medium_$n" 0 1 0,60 m-18L4 80 0 0 - "contact thud under the material contact"
done
for n in 000 001 002; do
  r press/press_stamp.caf "kenney-impact--impactPlate_light_$n" 0 1 0,60 m-18L4 80 0 0 - "PRESSED stamp thunk on the reveal card"
done

# ---------- Bubble wrap: the pops are the grains ----------
p fs214675 bubblewrap/bubblewrap_pop --n 12 --max 0.35 --norm m-16L6 --note "pop, medium bubble"
p bsb0462 bubblewrap/bubblewrap_popbig --n 7 --max 0.5 --norm m-16L6 --note "pop, large bubble (also the duck seam pop)"
p fs875514 bubblewrap/bubblewrap_popsmall --n 10 --max 0.25 --norm m-18L6 --note "pop, small bubble"
r bubblewrap/bubblewrap_crinkle_loop.caf fs522200 7.4 10.2 0,0 i-24 120 0 150 - "plastic crinkle strain loop"
p fs151216 bubblewrap/bubblewrap_crinkle --n 4 --max 0.4 --range 12 --norm m-20 --hp 120 --whole 1 --note "crinkle one-shot (contact, release)"

# ---------- Rubber duck: comic, never pained ----------
p fs403507 duck/duck_squeak --to 6.3 --n 8 --max 0.7 --tail 45 --hp 150 --eq "$NOTCH" --whole 1 --note "squeeze squeak (bend pitch up with c at runtime)"
p fs403507 duck/duck_squeak --from 9.0 --n 2 --max 0.7 --tail 45 --hp 150 --eq "$NOTCH" --whole 1 --note "squeeze squeak"
r duck/duck_honk.caf          fs403507 6.35 8.70 2,120 m-14 150 0 0 "$NOTCH" "long squeal: the comic honk at c 0.7"
# EXPERIENCE-REVIEW-1 #9: the honk is the most-heard sound in the app; six more takes from the licensed toy sources.
r duck/duck_honk.caf          fs350917 4.595 5.861 2,120 m-14 150 0 0 "$NOTCH" "comic honk (rubber duck)"
r duck/duck_honk.caf          fs201285 5.109 6.189 2,120 m-14 150 0 0 "$NOTCH" "comic honk (duck toy)"
r duck/duck_honk.caf          fs454575 20.317 21.471 2,120 m-14 150 0 0 "$NOTCH" "comic honk (duck toy)"
r duck/duck_honk.caf          fs454575 17.522 18.229 2,100 m-14 150 0 0 "$NOTCH" "short honk (duck toy)"
r duck/duck_honk.caf          fs622335 4.090 4.885 2,100 m-14 150 0 0 "$NOTCH" "squeeze-toy honk"
r duck/duck_honk.caf          fs528421 1.849 2.667 2,100 m-14 150 0 0 "$NOTCH" "rubber squeal honk"
r duck/duck_squeaklow.caf     fs483922 0.0 1.25 1,60 m-16 120 0 0 - "low squeak (contact, release)"
r duck/duck_squeaklow.caf     fs240015 0.0 1.23 1,60 m-16 120 0 0 - "low squeak (contact, release)"
r duck/duck_wheeze.caf        fs217351 0.0 0.78 2,150 m-18 150 0 0 - "air wheeze after the seam pops"
r duck/duck_wheeze.caf        fs326756 0.0 1.5 2,300 m-18 150 0 0 - "long deflating wheeze (release)"
r duck/duck_wheeze_loop.caf   fs329946 1.0 3.8 0,0 i-24 200 9000 300 - "air-leak bed while crushing the popped duck"

# ---------- Jelly: wobble, ooze, splat ----------
r jelly/jelly_squelch_loop.caf fs575333 17.6 20.6 0,0 i-24 120 0 300 - "gel strain loop"
r jelly/jelly_squelch_loop.caf fs587848 50.0 53.0 0,0 i-24 120 0 300 - "gel strain loop (bubbly)"
p fs593990 jelly/jelly_squelch --n 10 --max 0.35 --tail 45 --hp 100 --note "squelch grain (crush bed)"
p fs412919 jelly/jelly_squelch --n 4 --max 0.4 --tail 45 --hp 100 --note "squelch grain (crush bed)"
r jelly/jelly_splat.caf  fs515621 0.0 0.46 1,80 m-14L8 80 0 0 - "skin split splat (failure body)"
r jelly/jelly_splat.caf  fs686363 0.0 0.48 1,80 m-14L8 80 0 0 - "skin split splat (failure body)"
p fs802616 jelly/jelly_splat --from 4 --to 30 --n 3 --max 0.6 --range 8 --gap 1.0 --norm m-14 --hp 100 --whole 1 --note "splat (failure body)"
r jelly/jelly_wobble.caf fs181918 0.0 0.9 2,250 m-20 100 0 0 - "wobble (contact, release)"
r jelly/jelly_wobble.caf fs181918 1.6 2.5 30,250 m-20 100 0 0 - "wobble (contact, release)"
r jelly/jelly_wobble.caf fs463590 0.0 0.77 1,150 m-20 100 0 0 - "jelly bounce (place)"
r jelly/jelly_slurp.caf  fs681950 0.0 1.6 2,250 m-18 100 0 0 - "elastic slurp-back (release)"
r jelly/jelly_slurp.caf  fs681950 3.0 4.6 20,250 m-18 100 0 0 - "elastic slurp-back (release)"

# ---------- Crayon (box): dry wax snaps ----------
r crayon/crayon_snap.caf fs476831 1.38 1.80 1,60 m-14L8 100 10000 0 - "wax snap (failure transient+body)"
r crayon/crayon_snap.caf fs486374 2.22 2.95 1,80 m-14L8 100 10000 0 - "wax snap"
r crayon/crayon_snap.caf fs215382 0.0 0.34 1,60 m-14L8 100 10000 0 - "wax snap"
r crayon/crayon_snap.caf fs322416 0.0 0.55 1,80 m-14L8 100 9000 0 - "wax snap (twig, dulled)"
r crayon/crayon_snap.caf fs251464 0.0 0.38 1,60 m-14L8 100 9000 0 - "wax snap (twig, dulled)"
r crayon/crayon_snap.caf fs452570 0.0 0.52 1,60 m-14L8 100 9000 0 - "wax snap (twig, dulled)"
# EXPERIENCE-REVIEW-1 #9: no CC0 wax-crayon snap exists, so the snap is layered: small popsicle-stick breaks,
# low-passed and given low-mid weight so they read dense and waxy, not woody (the body), under a dry chalk tap
# (crayon_chalk, layered at runtime by SampleMap).
r crayon/crayon_snap.caf fs460247 2.949 3.086 1,60 m-14L8 100 6500 0 "ls400:3;pk3300:-5:1.4" "wax snap (small stick, dulled and thickened)"
r crayon/crayon_snap.caf fs460247 3.542 3.713 1,60 m-14L8 100 6500 0 "ls400:3;pk3300:-5:1.4" "wax snap (small stick, dulled and thickened)"
r crayon/crayon_snap.caf fs460247 3.944 4.15 1,60 m-14L8 100 6500 0 "ls400:3;pk3300:-5:1.4" "wax snap (small stick, dulled and thickened)"
r crayon/crayon_snap.caf fs460246 0.262 0.459 1,60 m-14L8 100 6500 0 "ls400:3;pk3300:-5:1.4" "wax snap (small stick, dulled and thickened)"
r crayon/crayon_snap.caf fs460246 1.741 1.856 1,60 m-14L8 100 6500 0 "ls400:3;pk3300:-5:1.4" "wax snap (small stick, dulled and thickened)"
r crayon/crayon_snap.caf fs460246 3.542 3.75 1,60 m-14L8 100 6500 0 "ls400:3;pk3300:-5:1.4" "wax snap (small stick, dulled and thickened)"
r crayon/crayon_snap.caf fs460246 4.653 4.761 1,60 m-14L8 100 6500 0 "ls400:3;pk3300:-5:1.4" "wax snap (small stick, dulled and thickened)"
r crayon/crayon_chalk.caf fs258092 0.0 0.094 0,20 m-18L6 300 0 0 - "dry chalk tap: the crumbly top of a wax snap"
p fs486374 crayon/crayon_crumb --n 10 --max 0.12 --range 30 --gap 0.05 --lp 9000 --norm p-6 --note "waxy crumble grain"
p fs116595 crayon/crayon_crumb --n 6 --max 0.12 --range 18 --gap 0.5 --lp 8000 --norm p-6 --note "dry crumble grain (celery, dulled)"
r crayon/crayon_tap.caf  fs232900 0.0 0.65 1,120 m-20L6 100 0 0 - "crayon tap and roll (place, contact)"

# ---------- Egg: shell, then wet ----------
r egg/egg_crack.caf fs336613 0.0 0.9 1,120 m-14L8 100 0 0 - "shell crack (failure)"
r egg/egg_crack.caf fs336613 0.85 1.8 10,150 m-14L8 100 0 0 - "shell crack (failure)"
r egg/egg_crack.caf fs426307 2.95 3.45 1,100 m-14L8 100 0 0 - "shell crack (failure)"
r egg/egg_crack.caf fs426307 4.10 4.50 1,100 m-14L8 100 0 0 - "shell crack (failure)"
r egg/egg_crack.caf fs244739 0.0 0.82 1,100 m-14L8 100 0 0 - "shell crack (failure)"
r egg/egg_crack.caf fs137238 0.5 1.6 2,150 m-14L8 100 0 0 - "crack into pulp (failure)"
p fs244749 egg/egg_tick --n 4 --max 0.12 --range 24 --gap 0.06 --norm p-6 --note "shell micro-crack (strain, tell)"
p fs244743 egg/egg_tick --n 4 --max 0.12 --range 24 --gap 0.06 --norm p-6 --note "shell micro-crack (strain, tell)"
p fs757512 egg/egg_crunch --n 12 --max 0.18 --range 18 --gap 0.4 --norm p-6 --note "shell crunch grain (crush bed)"
r egg/egg_yolk.caf fs137238 5.4 6.3 20,200 m-18 100 0 0 - "yolk squelch (wet layer; dropped in Soft)"
r egg/egg_yolk.caf fs137238 33.4 34.4 20,200 m-18 100 0 0 - "yolk squelch (wet layer; dropped in Soft)"

# ---------- Cake slice: the cosy one ----------
r cake/cake_squish_loop.caf fs32921 4.0 6.6 0,0 i-24 100 0 300 - "creamy compress loop"
r cake/cake_squish_loop.caf fs190456 0.4 3.4 0,0 i-24 100 0 300 - "sponge compress loop"
p fs414310 cake/cake_crumb --n 12 --max 0.25 --range 18 --gap 0.3 --norm p-6 --note "crumb grain (crush bed)"
p fs414310 cake/cake_collapse --n 2 --max 0.6 --gap 3.0 --norm m-16 --whole 1 --note "layer collapse (fracture)"
r cake/cake_collapse.caf fs234872 7.392 7.992 1,100 m-16 100 0 0 - "layer collapse (sponge squeeze)"
r cake/cake_collapse.caf fs594753 6.069 6.669 1,100 m-16 100 0 0 - "layer collapse (sponge press)"
p fs593990 cake/cake_squirt --from 10 --n 2 --max 0.5 --range 6 --gap 3.0 --norm m-16 --hp 100 --whole 1 --note "frosting/jam squirt at c 0.65 (wet)"
# A pressed slice, layered: the cream squelching out of the sponge (wet: Soft drops it).
r cake/cake_creamsquelch.caf fs389517 0.281 0.781 2,80 m-16 100 0 0 - "cream squelch as the slice gives"
r cake/cake_creamsquelch.caf fs389517 1.222 1.722 2,80 m-16 100 0 0 - "cream squelch as the slice gives"
r cake/cake_creamsquelch.caf fs389517 5.114 5.317 2,80 m-16 100 0 0 - "cream squelch as the slice gives"
r cake/cake_creamsquelch.caf fs389517 10.546 10.952 2,80 m-16 100 0 0 - "cream squelch as the slice gives"
r cake/cake_creamsquelch.caf fs459552 3.966 4.16 2,80 m-16 100 0 0 - "cream squelch as the slice gives"
r cake/cake_creamsquelch.caf fs459552 52.338 52.552 2,80 m-16 100 0 0 - "cream squelch as the slice gives"
r cake/cake_icing.caf fs406336 0.0 0.6 1,100 m-18L6 100 0 0 - "icing crack (fracture at c 0.3)"
r cake/cake_icing.caf fs406336 0.9 1.5 5,100 m-18L6 100 0 0 - "icing crack (fracture at c 0.3)"

# ---------- Soda can: buckles and fizz ----------
r can/can_buckle.caf fs131323 0.0 0.55 1,100 m-14L8 80 0 0 - "buckle (fracture events)"
r can/can_buckle.caf fs445240 0.0 0.70 1,100 m-14L8 80 0 0 - "buckle"
r can/can_buckle.caf fs445240 1.05 1.40 1,100 m-14L8 80 0 0 - "buckle"
r can/can_buckle.caf fs445240 1.50 1.83 1,100 m-14L8 80 0 0 - "buckle"
r can/can_buckle.caf fs383450 0.60 1.28 1,100 m-14L8 80 0 0 - "buckle"
r can/can_buckle.caf fs383450 1.30 1.75 1,100 m-14L8 80 0 0 - "buckle"
r can/can_buckle.caf fs689774 0.50 1.20 1,100 m-14L8 80 0 0 - "buckle"
r can/can_buckle.caf fs521896 0.45 0.90 1,100 m-14L8 80 0 0 - "buckle"
r can/can_buckle.caf fs521896 4.45 5.00 1,100 m-14L8 80 0 0 - "buckle"
r can/can_buckle.caf fs521896 8.85 9.60 1,100 m-14L8 80 0 0 - "buckle"
r can/can_buckle.caf fs735890 1.00 1.60 1,100 m-14L8 80 0 0 - "buckle"
r can/can_crush.caf  bsb0118 0.55 1.30 1,150 m-12L4 80 0 0 - "full crush (final failure body)"
r can/can_crush.caf  bsb0118 5.25 6.10 1,150 m-12L4 80 0 0 - "full crush (final failure body)"
# EXPERIENCE-REVIEW-1 #9: heroes get >= 4 variants.
r can/can_crush.caf  fs758998 3.451 3.953 1,150 m-12L4 80 0 0 - "full crush (slow crush, the give)"
r can/can_crush.caf  fs735890 0.173 0.790 1,150 m-12L4 80 0 0 - "full crush (empty can)"
r can/can_strain_loop.caf fs758998 9.0 11.8 0,0 i-24 100 0 300 - "slow-crush crackle bed under load"
p fs758998 can/can_crumple --n 12 --max 0.22 --range 20 --gap 0.4 --norm p-6 --note "crumple grain (strain, crush bed)"
r can/can_open_fizz.caf fs689705 0.55 2.6 0,300 m-14 80 0 0 - "tab pop + fizz burst (first buckle, unopened can)"
r can/can_open_fizz.caf bsb0116 0.0 0.78 0,120 m-14 80 0 0 - "tab pop + fizz burst"
for n in 000 001 002 003 004; do
  r can/can_tink.caf "kenney-impact--impactTin_medium_$n" 0 1 0,60 m-18L4 100 0 0 - "can tink (place, contact, poke)"
done
r can/can_fizz_loop.caf fs256317 5.0 7.8 0,0 i-26 200 0 300 - "fizz bed and reveal fizz settle"

# ---------- Gummy bear: chewy stretch, seam split ----------
r gummy/gummy_stretch_loop.caf fs125160 10.0 12.8 0,0 i-24 120 0 300 - "chewy rubber stretch loop"
p fs399008 gummy/gummy_squish --n 8 --max 0.45 --range 18 --gap 0.3 --hp 100 --whole 1 --note "chewy squish grain"
p fs330249 gummy/gummy_split --n 2 --max 0.6 --gap 0.6 --norm m-14 --hp 100 --eq "$NOTCH" --whole 1 --note "seam split (failure)"
r gummy/gummy_split.caf fs686363 0.0 0.48 1,80 m-14 100 0 0 - "seam split (failure)"
# EXPERIENCE-REVIEW-1 #9: the gummy was 10 files. More splits, squishes and boings from the licensed rubber sources.
r gummy/gummy_split.caf fs125160 2.956 3.556 1,80 m-14 100 0 0 "$NOTCH" "seam split (rubbery tear)"
r gummy/gummy_split.caf fs125160 17.864 18.464 1,80 m-14 100 0 0 "$NOTCH" "seam split (rubbery tear)"
r gummy/gummy_split.caf fs125160 25.530 26.130 1,80 m-14 100 0 0 "$NOTCH" "seam split (rubbery tear)"
r gummy/gummy_squish.caf fs125160 46.605 47.205 1,60 m-18 100 0 0 - "chewy squish grain"
r gummy/gummy_squish.caf fs528419 0.911 1.511 1,60 m-18 100 0 0 "$NOTCH" "chewy squish grain"
r gummy/gummy_boing.caf fs542195 0.0 1.6 1,300 m-18 60 0 0 - "wobble boing (release)"
r gummy/gummy_boing.caf fs681950 3.311 4.836 1,300 m-18 60 0 0 - "floppy wobble boing"
r gummy/gummy_boing.caf fs681950 5.571 6.305 1,200 m-18 60 0 0 - "floppy wobble boing"
r gummy/gummy_boing.caf fs510496 3.997 5.285 2,300 m-18 60 0 0 - "spring boing (a third take, not the steel one)"

# ---------- Glass bottle: the finale ----------
r glass/glass_creak_loop.caf fs174754 4.0 7.0 0,0 i-26 200 9000 300 "$NOTCH;pk2800:-3:1.2" "glass strain creak loop (2.5-4.5 kHz notched)"
p fs342546 glass/glass_tick --n 8 --max 0.15 --range 24 --gap 0.2 --lp 12000 --norm p-6 --note "strain tick (tell micro-cracks)"
r glass/glass_crack.caf fs418194 0.0 0.65 1,100 m-14L8 120 0 0 - "first crack (hard)"
r glass/glass_crack.caf fs262635 0.0 0.32 1,60 m-14L8 120 0 0 - "first crack (ice-like tick)"
r glass/glass_crack.caf fs262635 0.50 1.00 1,60 m-14L8 120 0 0 - "first crack (ice-like tick)"
p fs342546 glass/glass_crack --n 3 --max 0.6 --range 6 --gap 1.0 --norm m-14L8 --hp 120 --whole 1 --note "first crack (ice crack)"
for n in 000 001 002; do
  r glass/glass_tink.caf "kenney-impact--impactGlass_medium_$n" 0 1 0,80 m-16L4 120 0 0 - "tonal tink under the first crack (glass ring)"
done
r glass/glass_shatter.caf fs221528 0.25 1.45 1,250 m-12L4 100 0 0 - "shatter (hero)"
r glass/glass_shatter.caf fs212698 0.35 1.70 1,250 m-12L4 100 0 0 - "shatter (hero)"
r glass/glass_shatter.caf fs233605 0.35 1.00 1,150 m-12L4 100 0 0 - "shatter (hero)"
r glass/glass_shatter.caf fs233607 0.05 1.00 1,150 m-12L4 100 0 0 - "shatter (hero)"
r glass/glass_shatter.caf fs465946 0.38 1.70 1,250 m-12L4 100 0 0 - "shatter (hero)"
r glass/glass_shatter.caf bsb1591 0.0 1.34 1,250 m-12L4 100 0 0 - "shatter (hero)"
r glass/glass_shatter.caf fs401619 0.0 1.25 1,250 m-12L4 100 0 0 - "bottle smash (hero)"
r glass/glass_shatter.caf fs401619 1.30 2.50 1,250 m-12L4 100 0 0 - "bottle smash (hero)"
r glass/glass_shatter.caf fs607910 0.0 2.0 1,300 m-12L4 100 0 0 - "bottle break (hero)"
r glass/glass_shatter.caf fs607910 2.80 4.70 1,300 m-12L4 100 0 0 - "bottle break (hero)"
r glass/glass_shatter.caf bsb1121 0.0 1.10 1,250 m-12L4 100 0 0 - "thin-glass burst (hero; golden variant)"
r glass/glass_debris.caf fs336425 1.0 2.9 30,300 m-20 150 12000 0 - "shard settle tail"
r glass/glass_debris.caf fs156579 0.0 1.71 2,200 m-20 150 12000 0 - "shard settle tail"
p fs610933 glass/glass_grit --from 20 --to 120 --n 14 --max 0.12 --range 20 --gap 2.0 --norm p-6 --lp 12000 --note "glass grit grain (crush bed)"
for n in 000 001 002; do
  r glass/glass_contact.caf "kenney-impact--impactGlass_light_$n" 0 1 0,60 m-20 120 0 0 - "glass tink (contact, place)"
done

# ---------- Steel ball: the press loses ----------
r steel/steel_groan_loop.caf fs172411 2.0 5.4 0,0 i-24 80 0 400 - "press-frame groan loop under impossible load"
r steel/steel_groan.caf fs496836 0.0 1.8 5,400 m-16 80 0 0 - "metallic groan swell (tell)"
r steel/steel_groan.caf fs453333 0.0 1.5 5,300 m-16 80 0 0 - "crank groan (tell)"
p fs535286 steel/steel_clink --n 5 --max 0.3 --range 12 --gap 1.0 --norm m-18L6 --whole 1 --note "ball clink (place, contact)"
r steel/steel_snap.caf  fs752070 0.0 1.0 0,150 m-12L4 60 0 0 - "spring snap: the press gives up (hero)"
# EXPERIENCE-REVIEW-1 #9: the vault's punchline was one file each. Kenney Impact (CC0) heavy metal and bell takes.
for n in 000 001 002 003 004; do
  r steel/steel_snap.caf "kenney-impact--impactMetal_medium_$n" 0 2 0,150 m-12L4 60 0 0 - "steel gives up (hero)"
  r steel/steel_ring.caf "kenney-impact--impactBell_heavy_$n" 0 2.5 2,500 m-18 80 0 0 - "long ring tail"
done
for n in 000 001 002; do
  r steel/steel_crash.caf "kenney-impact--impactPlate_heavy_$n" 0 1.6 0,300 m-12L4 60 0 0 - "metal plate crash (hero body)"
done
r steel/steel_crash.caf fs859154 0.0 1.6 0,350 m-12L4 60 0 0 - "metal chunk crash (hero body)"
r steel/steel_crash.caf fs562198 0.0 1.3 0,300 m-12L4 60 0 0 - "metal smash (hero body)"
r steel/steel_boing.caf fs510496 0.0 1.3 2,300 m-16 80 0 0 - "comic sproing after the snap"
r steel/steel_boing.caf fs510496 2.0 3.3 2,300 m-16 80 0 0 - "comic sproing after the snap"
r steel/steel_ring.caf  fs789214 0.25 2.0 2,500 m-18 80 0 0 - "long ring tail"

# ---------- UI (Kenney Interface Sounds, CC0) ----------
for f in click_001 click_004 select_001 select_002 toggle_001 toggle_002 back_001 open_001 close_001; do
  r "ui/ui_${f%_*}.caf" "kenney-interface--$f" 0 1 0,40 m-22 80 0 0 - "menu tap / select / navigate"
done
for f in confirmation_001 confirmation_002 maximize_006; do
  r ui/ui_unlock.caf "kenney-interface--$f" 0 2 0,80 m-20 80 0 0 - "unlock / achievement layer under the synth chime"
done
for f in drop_001 drop_002 drop_003; do
  r ui/ui_drop.caf "kenney-interface--$f" 0 1 0,40 m-20 80 0 0 - "object placed on the anvil (under the material plop)"
done
} | awk -F'\t' 'BEGIN { OFS = "\t"; print "path", "src", "start", "end", "fade", "norm", "hp", "lp", "loop", "eq", "note" }
  {
    # Renumber per prefix: strip any _NN and the extension, then append a running two-digit index.
    base = $1; sub(/\.caf$/, "", base); sub(/_[0-9][0-9]$/, "", base)
    n[base]++; $1 = sprintf("%s_%02d.caf", base, n[base]); print
  }'
