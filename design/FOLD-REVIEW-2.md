# Fold Review 2: Squish on iPhone Duo (book pose), after the round-1 fixes

*Design critic pass 2, 22 Oct 2026. Inputs:*
- *The real iPhone Duo simulator run `duo4/duo-screens`: book pose, inner 2853 × 2007 px, hinge driven by `foldctl` 180 → 150 → 120 → 100 → 90 → 75 → 60 → 45 → closed → reopen to 170, 4 objects. The engine logs still quantise to ~9.5° steps (e.g. 47.5°, 38.1°).*
- *The iPhone 18 Pro simulated-fold tabletop run `run12/90–99`, the P-48 fallback frames `run12/01, 05, 20, 25, 34, 55`, and the share-clip keyframe `80-clip-duck.png`. I couldn't view the `.mp4`.*
- *Round-1 frames `duo3/duo-screens` for side-by-side comparison.*

*Method:*
- *Coordinates are **pt on the 951 × 669 book canvas**, using the same convention as round 1: the leading page is the platen, the trailing page is the anvil, and the crease band is x 455.5–495.5. Cover coordinates are pt on 466 × 678.*
- *Luminance comes from a PowerShell sampler run on the raw PNGs: Rec.709 L on every 10th pixel, with "clip" meaning L ≥ 250.*
- *There is still no §9.6 eye-view composite, so every **E** check is my judgement, not a measurement.*

---

## 1. Verdict

**Score: 5.8 / 10** (round 1: 4.2). **Duo-ness: 1.75 / 2** (round 1: 1.5).

| Dimension | Weight | R1 | **R2** | Why |
|---|---|---|---|---|
| Composition | 2.0 | 1.2 | **1.3** | **Better:** the stage is clean during the press, the console is one row, the platen now has a foot band that mirrors the anvil console, and the reveal is structurally a diptych. **Still weak:** at 180–120° the book eye is better but still mostly top-down, so the duck is a yellow blob seen from above. The glass bottle overhangs the strike plate at every angle. The jelly (18 Pro) spills ~70 pt past its plate |
| Light and material | 3.0 | 0.9 | **1.5** | **The closing blow-out is fixed:** anvil field clip is 0% from 150° down (round 1: 28–77%), and the steel reads as steel. Plate shade, sheen and Newton rings are now visible. **New problems:** (a) the *flat* 180° state is now the over-exposed one, with field clip at 56% (bubble), 15% (glass) and 9% (duck); (b) the plate shade is a rectangular "box-shadow" halo and it **stays on at the reveal**, so the anvil plate falls to L 149–156 against the platen's 193–198; (c) the glass shards are translucent stacked cards |
| Colour and tone | 2.0 | 0.8 | **1.1** | Anvil field mean during the press is 194–210 (target 175–215 ✓). But the bubble and glass anvil fields still run 232–235. The two plates differ by 25–48 L at every angle. The platen field is gel-tinted (pinkish for glass) and the anvil field is cream. The hero is the most saturated region for duck, can and jelly, but not for glass (where the teal dust polygon wins) or for bubble at 180 |
| UI | 2.0 | 0.7 | **1.3** | **Big jump:** no UI on stage while pressing; chip + Shelf + lamp in the console; Again · Share · Next as one console row with one yellow primary; one single-line toast in the crown; a real nameplate; readable lamp labels. **Still wrong:** the caption label truncates on **4 of 4** book reveals; the cover dial is 0–60 while the inner gauge is 0–80; and the P-48 shows the old flat nameplate and a 0–60 gauge |
| Story and delight | 1.0 | 0.55 | **0.6** | Duck, can and bubble now fail *on the anvil* in the same frames as the print. Glass still does not: it shows bottle-height shards at 60/45°. The reveal specimen for the duck has **re-inflated** to roughly its 90° shape. Can mess colour (lilac) ≠ print colour (green). The P-48 fallback frames show an **empty bed** |

**Weighted:** 1.3 + 1.5 + 1.1 + 1.3 + 0.6 = **5.8**. That is "decent indie": a coherent scene whose exposure and materials are still off.

**In one line:** round 1's three headline fixes landed. The anvil is no longer a white card, three of four objects fail on the anvil, and the reveal is a diptych. What's left is *tonal consistency between the two halves*, *glass*, and a long tail of debug-looking edges (box-shadow halo, frost cut-offs, film seams, truncated captions, a grey-bar teaser). On top of that is a possible **P-48 regression** that has to be ruled out before anything ships.

---

## 2. What improved vs round 1 (verified in frames)

| Round-1 fix | Status | Evidence |
|---|---|---|
| 1 Anvil blow-out while closing | **Fixed (closing) / regressed at flat** | Anvil field clip 0% at 150 → 45 for all 4 objects (was 28–77%). Anvil plate L goes 209 → 160. But at 180: bubble field L 250 with 56% clip, glass 249 with 15% |
| 2 Failure lands on the anvil | **3 of 4** | `rubberDuck-60/45`: seam decal + yellow spread ≥ 1.3× footprint. `sodaCan-60`: squat crumple + fizz puffs. `bubbleWrap-60/90`: popped craters vs intact domes, mirrored on the print. **Glass ✗** (see §4) |
| 3 Book eye 3/4 tilt | **Partly** | The log eye moved (0, 320.7, −34) → (116.1, 298.9, −34.3) mm, about 21° toward the top edge. The duck's face and beak now point up the page. Still reads mostly top-down at 180–120. At 90° the can looks *lying on its side* in the raw frame |
| 4 Book reveal diptych | **Mostly** | Print + PRESSED stamp on the platen; specimen on the anvil; single-line toast in the crown (x 90–447, y 20–68); no 3:4 card over the print. **But** the caption truncates, there's no ruler, no goo strands are visible, and the specimen has rebounded (fix 5 below) |
| 5 Keycaps off the stage | **Fixed** | Idle: chip (x 507–709) + Shelf (x 721–893) + lamp, all in the console y 595–657. Reveal: Again · Share · Next in one row, with Next the only yellow |
| 6 Print reads as ink | **Partly** | Kiss now has a glint. Duck print has a wet rim, mottle and a rainbow fringe. Soda print is still a glowing green "power button" (concentric rings + outer halo) |
| 7 Clipped glass frost | **Not fixed, moved** | The frost now overruns the plate by 20–28 pt and still ends on **straight lines** at x ≈ 100 and x ≈ 369 pt (`glassBottle-45`, `-reveal`) |
| 8 One material language | **Partly** | Platen bolts are now hex, matching the anvil. Platen guide pins are still white rings with a glow, while the anvil's are dark studs. The tints differ (platen field gel-tinted; anvil cream) |
| 9 Ground + plate shade | **Overdone / latched** | The shade is visible from 150° (good), but it's a 48 pt rectangular halo around the anvil plate, it never lifts on reopen, and it leaves the anvil plate 40+ L darker than the platen |
| 10 Clear/white objects need edges | **Fixed at rest** | `bubbleWrap-180`: blue film edge, readable domes. `glassBottle-180`: teal glass with edges. The label UV seams are gone |
| 11 Cover display | **Partly** | One number per seal (56 / 54 / 58 / 48 t). Hazard jaw on the free edge. Amber lamp. "TONS" moved off the needle. **But** the dial is 0–60 vs the inner 0–80, the seam glow is ~1 pt and barely visible, and the teasers are grey blobs (bubble wrap's is a plain grey bar) |
| 12 Card shows what was pressed | **n/a on book**; P-48 clip ✓ | `80-clip-duck`: the card shows the 3/4 squashed specimen + puddle + stamp. It is not the print-over-specimen diptych of §6.3 |
| 13 Sheen + pins visible | **Fixed** | A sheen band is visible on the platen plate (`rubberDuck-150/120/90`, `glassBottle-180`). Pin rims brighten after contact |
| 14 Ghost arc / grip-glow bleed | **Removed** (not restyled) | Neither the arc nor the glow is visible anywhere, so the 180° state now has no grip invitation at all (§7.3) |
| 15 Nameplate, lamps, CI composite | **2 of 3** | Brushed nameplate with rivets and Mono Bold. Lamp labels ~9 pt and legible. The gauge is 0–80 with readable numerals. **No eye-view composite yet** |

---

## 3. §12 acceptance checklist (updated)

| Check | R1 | **R2** | Evidence |
|---|---|---|---|
| **R1 Crease** | PASS | **PASS** | The 40 pt band is solid graphite in all 36 inner frames. Nothing crosses it, including the jelly splat on the 18 Pro |
| **R2 Clearance** | PASS | **PASS** | Closest is the glass dust polygon at `glassBottle-reveal`, x ≈ 566 pt, which is 70 pt from the band edge |
| **R3 Registration** | PASS / ✗ looks | **PASS (positions)**, ✗ looks | Bubble wrap: intact anvil domes at (733, 281), (692, 390), (647, 428) pt mirror the faint print rings within ~4 pt ✓. Plates and bolts mirror. **Looks:** pins differ (white glow vs dark stud), and plate L differs by 25–48 |
| R4 Frame | PASS | **PASS** | Rails line up; hazard jaws are on both outer edges; the platen foot band now mirrors the console |
| R5 Tone | FAIL | **PARTIAL** | ✓ Closing frames: anvil mean 194–210, 0% clip, warm-brown shade. ✗ At 180: anvil field 240–250, clip 9–56%. ✗ \|L(anvil plate) − L(platen plate)\| is 25–48 (target ≤ 12). ✗ Glass: the dust polygon is more saturated than the shards |
| R6 No UI on stage | FAIL | **PASS** | All idle controls are in the console. The reveal caption and NEW BEST tag sit under the platen plate (sanctioned); the toast is in the crown |
| **E1 One press** | PARTIAL | **PARTIAL** (judgement) | Duck, can and bubble now read as "the lid came down on it". Glass reads as "a bottle wrapped in torn paper inside a teal bag". At 150° and below, the box-shadow halo makes the anvil plate look like a floating card |
| **E2 Stands up** | likely FAIL | **PARTIAL** (judgement) | The 21° tilt gives the duck a face. The can at 90° looks toppled. No composite, so this can't be measured |
| 180: landing, approach shadow, READY, gauge 0 | PARTIAL | **PARTIAL** | READY green and gauge at 0 ✓. A faint approach shadow appears for glass only. **None for duck or can.** A *detached grey wedge* sits on the anvil field outside the plate (x 575–637, y 190–266 pt, `rubberDuck-180/150`) |
| 180: sheen sweep, grip glows, no text | FAIL | **PARTIAL** | Sheen band visible ✓ (can't verify the sweep from stills). **Grip glows removed** rather than moved to the platen far corners ✗. No text on stage ✓ |
| 180 E: opened clamshell | PASS raw | **PASS raw, weaker light** | The pair reads, but the anvil is the brightest thing on screen at flat. This is the store-screenshot frame |
| 120: kiss/print 0.15–0.3 R, LOAD amber, needle off zero | PASS | **PASS** | `rubberDuck-120`: kiss ≈ 0.2 R with a glint; LOAD amber; needle ≈ 6 t |
| 120: bulge, lean, plate shade | FAIL | **PARTIAL** | Plate shade ✓ (from 150°). Bulge and lean can't be seen top-down |
| 120 E (tabletop) | PASS | **not re-checked** | `run12/91` not reviewed. `93` and `96` suggest no regression |
| **90: height ≤ 75%, bulge, lean; fractures match** | FAIL / ✓ | **FAIL** / mixed | Top-down, the duck and glass get *bigger* (no height cue). Fracture match: bubble ✓, duck ✓. **Glass ✗:** the anvil crack is on the label's crease-side edge (≈ 632 pt) and the print crack is at plate centre-right (≈ 257 pt). Mirrored, the print crack should be at ≈ 319 pt |
| **90: print ≥ 0.55 R, saturated, Newton rings** | PARTIAL | **PASS** | Newton-ring rainbow fringe is visible on `glassBottle-90`, `rubberDuck-90` and `run12/96` |
| 90: gauge in the middle third | borderline | **PASS** | Needle ≈ 35–40 of 80 |
| **60: every object past failure; mess persistent, inside plate + 40, not in crease** | FAIL | **PARTIAL** | Duck ✓, can ✓, bubble ✓. **Glass ✗:** shards stand bottle-height at 60/45/reveal. The dust peak reaches y 131 pt (plate + 40 = 145). Jelly on the 18 Pro overruns its plate by ~70 pt (`99`) |
| 60: print = final splat, matching the anvil mess | PARTIAL | **PARTIAL** | Duck: colour ✓, but the anvil seam is a 20 pt tick (x 692–711, y 354–376) while the print crack runs ~110 pt corner to corner. Bubble ✓. Glass: print ✓, anvil ✗. **Can: colour ✗** (lilac berry puddle on the anvil, green rings on the print) |
| 60 E (tabletop) | PASS | **PASS** | `run12/93`: the squashed duck with its seam is fully visible under the dimmed platen |
| Set-level: one closing motion | top ✓, bottom ✗ | **top ✓, bottom 3 of 4** | Duck stand → squash → seam → ooze reads. Glass doesn't |
| Scoring | 4.2, Duo 1.5 | **5.8, Duo 1.75** | §1 |

**Hard (bold) checks:** R1 ✓, R2 ✓, R3 ✓ (positions), E1 partial, E2 partial, 90-height ✗, 90-print ✓, 60-failure ✗ (glass). **The set still fails the 90 and 60 bold checks.**

---

## 4. The specific questions

### 4.1 Glass shards on the anvil: do they look like stacked rectangles?

**Yes. This is the single worst frame family in the build** (`glassBottle-75`, `-60`, `-45`, `-reveal`).
- **Three bottle necks** stand side by side at full height. The neck shards were never flattened.
- The label has broken into **flat cream and pink rectangles standing on edge**, like a fanned deck of cards (x 625–790, y 300–410 pt).
- A **hard-edged translucent teal polygon** (the "sea-glass dust" spread disc) pokes past the plate top and left (x 566–839, y 131–504 pt), with a pointed peak at the top.
- Small teal chips float off the plate's crease-far edge (≈ (830, 207) and (840, 280) pt).

**Root cause, in code:**
1. `GlassBottleView.shatter()` sets `bottle.scale = SIMD3(repeating: 1)` (GlassBottleView.swift:192). That un-squashes the bottle at the moment of failure, so the shards are adopted by debris at *rest height*.
2. `update()` then early-returns once `failed` (l.142), so nothing re-flattens them.
3. The dust disc grows to radius 0.097 at opacity 0.45 (l.139, l.185) with `wobble: 0.2`, which is why it reads as a hard plastic bag.

### 4.2 Failure legibility per object, on the anvil and the platen

| Object | Platen (print) | Anvil (object) |
|---|---|---|
| Rubber duck | ✓ Strong: wet yellow splat, seam crack, droplets, beak spot. The beak spot is a flat pure-orange disc (clip-art) | ✓ **New:** visible flatten + ooze at 60/45 + seam decal. ✗ The seam is a 20 pt tick, not the print's long crack. ✗ The reveal specimen has rebounded to roughly its 90° shape (`rubberDuck-reveal` vs `-45`) |
| Bubble wrap | ✓ Very clear: popped = strong blue rings, intact = faint rings | ✓ Popped craters vs domes read. ✗ **The film is cut**: a hard vertical edge at x ≈ 727 pt (`-90`, `-60`), with the film missing on the far ~40% and one intact dome floating loose at (768, 245) pt. ✗ Craters are grey on grey |
| Glass bottle | ✓ Frost star + Newton rings (the best print in the set). ✗ Overruns and is clipped by straight edges | ✗ See 4.1 |
| Soda can | ~ Green droplets read. The centre is still a glowing ring target ("record/power button") | ✓ Squat crumpled can + fizz puffs. ✗ Top-down it reads as a steel bowl (no buckle creases). ✗ Its mess is lilac while the print is green |
| Jelly (18 Pro, `99`) | ✓ Bold splat. ✗ The pink PRESSED stamp is nearly invisible on magenta | ✓ Splat reads. ✗ It overflows the plate by ~70 pt on three sides. ✗ A hard vertical shading seam runs through the blob (x ≈ 188 pt on the 18 Pro) |

### 4.3 Label truncation

**Every book reveal truncates the caption:**
- "RUBBER DUCK · 1 HON…"
- "BUBBLE WRAP · 24 PO…"
- "GLASS BOTTLE · SHAT…"
- "SODA CAN · 5 BUCKLE…"

The label sits at x 121–262, y 494–519 pt.

**Cause:** in `RevealCardView.printLabel` (RevealCardView.swift:154–174), the label and the NEW BEST ribbon share an `HStack`. That stack is framed to `maxWidth: plate.width` (≈ 230 pt, l.142), so the ribbon eats ~80 pt, and `minimumScaleFactor(0.7)` isn't enough.

On the 18 Pro the plate is wider, and "JELLY · SKIN SPLIT · SPLAT · 75°" fits, which is why this was missed. The toast itself no longer truncates ✓.

### 4.4 Reveal diptych

- **Structurally right:** print + stamp on top, specimen below, caption, crown toast, console row.
- **What breaks it:**
  - **The plate shade is still on.** The anvil plate is L 149–156, the darkest it gets in the whole run, while the lid is open at 170°.
  - The duck specimen has re-inflated.
  - No ruler and no goo strands are visible. The capture is at 170° about 1 s after reopen. If the 2 s slow-mo replay is still running there, the capture must wait until it ends.
  - The toast covers the READY/LOAD lamps and the P-48 nameplate. That's acceptable for 3 s, but it also means the reveal has no green "ready" moment.
- **Copy:** "ACHIEVEMENT · PATIENCE / One press, over 30 seconds. Very zen." fires on 3 of 4 CI runs. That's a harness artefact, but don't let it become the store screenshot.

### 4.5 Cover display

`*-closed`, `run12/25`.

**Better:** one tonnage per seal, a hazard jaw on the free edge, an amber lamp, "OPEN TO SEE", and the card at ~72% width.

**Remaining:**
1. **The dial is 0–60 with a red zone 48–60** (CoverView.swift:255, 265, 272, 289, 338). The inner gauge is 0–80 with its red zone at 60–80 (`FoldTextures.gaugeMaxTons = 80`), and the P-48 rig gauge is also 0–60. That's three gauges in two scales.
2. "TONS 60" still crowds the 60 numeral at (129–155, 317).
3. **Teasers look like placeholders:**
   - bubble wrap: a plain grey rounded bar;
   - glass: a grey kettlebell;
   - duck: a grey cigar.
4. The seam glow on the hinge edge is ~1 pt, not the 6 pt amber glow of §6.1.
5. The field is graphite, not the yellow enamel "outside of the press" in §6.1. That's a design call, but it's the least toy-like screen in the app.
6. A black disc appears at the top-right (≈ (418, 48) pt) on some captures and not others (glass in R2; bubble, glass and can in R1). It's almost certainly the simulator's camera mask. Confirm on device; the layout already clears it.

### 4.6 The 180° invitation state

This frame is now the **weakest-lit** in the set and the one most likely to become the App Store screenshot:
- The anvil field is clipped (bubble 56%, glass 15%), while the platen sits at L 211. Each half looks like it has its own lighting.
- Duck and can have **no approach shadow** on the platen at 180, so the plates don't "belong to each other" until 150°.
- **Nothing on screen invites the fold.** The grip glow was deleted rather than moved to the platen's far corners, the ghost arc is gone, and the sheen is the only cue.
- A detached grey wedge shadow sits on the anvil field outside the plate (x 575–637, y 190–266 pt), like a smudge on the glass.

### 4.7 Consistency between halves

| Element | Platen | Anvil | Target |
|---|---|---|---|
| Field L (press) | 210–212 | 208–235 | ΔE ≤ 3 |
| Field tint | gel-tinted: pink for glass, grey-mauve for can | cream / ivory | same gel at the same strength |
| Plate L | 187–198 | 149–171 (press/reveal), 203–218 (180) | \|Δ\| ≤ 12 |
| Guide pins | white ring + glow | dark grey stud | one design |
| Bolts | flat hex outline | 3D hex | close enough ✓ |
| Crease lips | graphite | graphite | ✓ |

### 4.8 Anything debug-looking (ranked by how cheap it looks)

1. The glass "stacked cards + three necks + plastic bag" (4.1).
2. **The rectangular plate-shade halo**, which reads as a CSS box-shadow, around the anvil plate at every angle ≤ 150° and at the reveal (x 580–851, y 162–504 pt).
3. The bubble-film hard vertical cut and the floating dome.
4. The frost lines ending on straight vertical edges outside the plate.
5. Truncated captions.
6. The grey-bar bubble-wrap teaser on the cover.
7. The soda print's glowing ring target.
8. The detached wedge shadow at 180°.
9. Jelly's vertical shading seam and its plate overflow.
10. The P-48 nameplate: brushed in `05/34/55` but still the old flat grey box in `01-launch`. The P-48 gauge is still 0–60.

---

## 5. Top 12 remaining fixes, ranked by launch impact

| # | Fix | Screen region | Likely file / constants | Concrete change | Owner |
|---|---|---|---|---|---|
| **1** | **Rule out the P-48 regression: empty bed, ram never moves** | 18 Pro P-48 stage, bed plate x 82–319, y 606–735 pt (`run12/05`, `34`, `55`) | `PressScene` framing / object attach for `.press` (not `.foldAnvil`); `PressScene.swift` ~l.228 + l.265–268; the `DemoMode` depth/reveal harness | The logs say `depth=0.344/0.366 pressing` and `phase=sealed` for `05`. The frames show **no object, ram at rest, gauge at 0, and no reveal card**. `01-launch` (bubble wrap) renders fine. Either the hero entity isn't parented or rendered outside fold framing, or captures are taken from a stale frame. **First check:** run `object=rubberDuck;depth=0.6` on a device and look. If it's real, it's a ship blocker for every non-Duo buyer. **CI:** fail the build if stage pixels in the bed rect equal the empty-bed reference | Scene |
| **2** | **Rebuild glass failure on the anvil** | Anvil plate x 601–830, y 185–484 pt, at 75° → reveal | `GlassBottleView.swift`: l.192 `bottle.scale = 1` on shatter; l.139 dust radius `0.062 + 0.035·t`; l.185 dust opacity 0.45; `spreadDisc wobble 0.2`; l.142 early return | **Shatter:** keep the squash. Use `bottle.scale.x = surfaceHeight(c)/restHeight` at shatter, and in `.foldAnvil` lay each shard flat: pitch −90°, random yaw, y ≤ 1.5 mm, radial spread 0.6–1.3× footprint. **Necks and base:** split them into ≥ 3 chunks, or hide them under the pile, so no neck stands. **Label patches:** shrink to 60% and lie flat as confetti. **Dust:** radius `0.040 + 0.015·t`, opacity 0.22, wobble 0.08, plus a 6 pt feathered alpha edge, clamped inside plate + 24 pt. **Glints:** add 6–10 static specular sparkles on the pile so it reads as glass, not paper. **CI:** projected pile height ≤ 15% of rest at c ≥ 0.75 | Scene |
| **3** | **Unlatch and reshape the plate shade** | Whole anvil plate + 48 pt halo, 150° → reveal | `FoldBezel.swift:238` `let a = f.contacted ? 1 : f.approach`; l.218–222 (plate + 20, radius 28, blur 14); `FoldTextures.plateShade` | **Drive it by the virtual gap, not the contact latch:** `a = f.approach` (or `1 − gap/gapAtθ0`), so it lifts on reopen and is 0 at the reveal. **Peak:** 0.30·a² → 0.18·a². **Shape:** the platen's projected footprint offset 12 pt toward the crease, blur 28, clipped to plate + 8, so no rectangular halo on the enamel. **CI:** \|L(anvil plate) − L(platen plate)\| ≤ 12 at 180/120/90/60/reveal (today 25–48) | Fold |
| **4** | **Fix exposure at flat (180–160°), the store-screenshot state** | Anvil field, all of x 496–939 pt at 180° | `FoldAnvil.fieldMaterial`; `FoldCurve.rimGain` (FoldGeometry.swift); `PressScene.setFoldStage` IBL | Anvil field at 180: L 240–250 with 9–56% clip, while the platen is at 211. Apply a flat-pose term: field base × 0.92 and IBL −0.3 EV for θ ≥ 160°, faded out by 140°. **Target:** anvil field 205 ± 8, clip ≤ 1% at every angle. Add an approach shadow at 180 for duck and can: 0.08 alpha, blur 40, at the mirror spot (glass already has one) | Scene (+Fold) |
| **5** | **Reveal: show the sealed specimen, plus ruler and strands** | Anvil at reveal; plate area | `DuckView.swift:114–119` (`surfaceHeight`, rebound); the reveal replay in `FoldPressController`; `RevealCardView.diptych` | The duck reverts from a puddle (`-45`) to roughly its 90° shape (`-reveal`). Cap elastic rebound at 15% of the sealed squash (§6.2), and make the 0.3× replay *end* on the sealed pose before the caption appears. Add the ruler with the new height ("2.4 mm") beside the anvil plate (x 840–900 pt) and 2–4 goo strands for duck and jelly. **CI:** capture at reveal + 300 ms and + 2.6 s | Scene (+Fold) |
| **6** | **Stop truncating the reveal caption** | Platen field under the plate, x 121–360, y 494–519 pt | `RevealCardView.swift:141–168` (`printLabel` HStack with `ribbon`, `.frame(maxWidth: plate.width)`, `minimumScaleFactor(0.7)`); `ObjectKind.breaksLine` | Take the ribbon out of the HStack. Put it as a −6° tag on the plate's top-right corner (it overlaps the steel the way a sticker would), or stack it above the label. Frame the label to `platenField.width − 48` (≈ 407 pt book). Never truncate: if it still doesn't fit, wrap to 2 lines. Shorten `breaksLine` ("24 POPS", "SHATTERED", "5 BUCKLES", "1 HONK · SEAM POP"). **CI:** OCR or string-measure assert there's no "…" | UI |
| **7** | **Contain mess and frost to plate + 24/40 with soft edges** | Platen frost x 100–369, y 157–511 pt (`glassBottle-45`, `-reveal`); jelly anvil (`run12/99`) | `FoldStamps.rect` (FoldStamps.swift ~l.68) + plate mask; `JellyView` spread disc | **Frost:** multiply by a radial falloff 1 → 0 over the last 24 pt past the plate edge, so no straight cut-off; add a 1 pt `shadowInk` 0.25 underlay so white cracks read on pale steel. **Jelly:** cap the spread radius at plate + 40 and remove the vertical shading seam (a normals or UV split in the spread mesh). **PRESSED stamp on red/pink prints:** switch to paper-white ink with a red outline when the print hue is within 30° of `#D7263D` | Fold / Scene |
| **8** | **Bubble film: kill the hard cut and the floating dome** | Anvil, film x 618–807, y 223–447 pt, cut at x ≈ 727 (`bubbleWrap-90`, `-60`) | `BubbleWrapView.swift:13` `film = 0.0008`, l.77–79 sheet at `film/2`; edge parts l.86–89; fold near-plane (`near=0.143` in log) | Likely a z-fight or transparency-sort between the 0.8 mm film and the strike-plate top under fold framing. Lift the sheet origin +0.6 mm, give the film material a depth bias or render-after-plate, and keep popped craters parented to the film. **Craters:** 1 pt `#6FAED0` rim at 0.6 and −15 L inside, so pops read on grey steel | Scene |
| **9** | **Can: one colour story and visible buckles** | Platen print centre (234, 334) pt; anvil can (`sodaCan-60`, `-reveal`) | `FoldStamps` soda signature; `SodaCanView.swift:77–83` (seeded `fizz` palette: lime / orange / berry); can crush mesh | **Colour:** the print must use the seed's `fizz.drop` / `fizz.puddle`, not the label green. Today the berry seed gives a lilac anvil puddle and green print rings. **Print shape:** drop the outer glow ring; use multiply blend at 0.85; add 5 radial buckle creases matching the "5 BUCKLES" count. **Anvil:** 5 dark crease decals on the rim and a side wall folded outward, so top-down it reads "crushed can", not "steel bowl" | Fold / Scene |
| **10** | **Cover: one gauge scale and real teasers** | Cover card, dial (99–171, 262–334) pt, teaser (185–275, 290–315) pt | `CoverView.swift:247–338` (`MiniGauge`: `/ 60` in l.255 and l.338, red arc 48–60 l.265, numerals [0, 30, 60] l.272, clamp 62 l.289); `FoldTextures.gaugeMaxTons`; P-48 rig gauge texture | **Scale:** read `gaugeMaxTons` everywhere: numerals 0/40/80, red zone 60–80. Do the same on the P-48 dial (§8.3 same bezel vocabulary). **Teaser:** draw the actual monoprint silhouette in the object's ink at 0.5 (not a grey bar or blob). **Seam glow:** 6 pt `#FFB81C` at 0.5 on the hinge edge, breathing with "OPEN TO SEE" | UI |
| **11** | **Bring back a wordless invitation at 180° and remove the stray wedge** | Platen rails near the far corners (x 12–72 / y 12–64 and y 595–657 pt); anvil field x 575–637, y 190–266 pt | `PressHints` (platen half); `FoldPressController.swift:275` invite clock; `PressScene.buildDecals` soft-shadow offset | Grip glow: two 60 pt amber `#FFB81C` 0.35 pads at the platen's far corners only, pulsing with the 4 s sheen sweep (§7.2–7.3). Plate-shade flicker on the anvil (200 ms) as the sweep reaches the crease. **Wedge:** the round-1 soft-decal offset toward the crease (0.25 × footprint) now lands outside the plate. Cut it to 0.08 × and clip it to plate + 8 | Fold / Scene |
| **12** | **One material across both halves** | Platen pins (397, 102 / 565 pt); both fields | `FoldPlaten.build` pins (FoldPlaten.swift ~l.388); `FoldAnvil.setGel`; `FoldTextures.enamel` | Platen pins become the same dark bushing as the anvil (the glow can stay as the post-contact rim). Apply the object gel to the anvil field at the same strength as the platen (or remove it from both). **CI:** field ΔE ≤ 3 across the crease at 180 and 90. Replace the flat pure-orange beak disc in the duck print with an ink-mottled shape | Fold |

**Also worth doing:**
- Build the §9.6 eye-view composite step. E1, E2 and the 90° height check still can't be measured, and they are the bold checks the set fails.
- Seed the CI run so the PATIENCE achievement doesn't fire on every capture.

---

## 6. Is this launchable?

**No, not yet: 5.8 against a launch bar of 8.**

The Duo architecture is now proven. The platen tells the story, three of four anvil failures land in the same frame as their print, and the UI finally stays off the stage. But a stranger shown the four store-worthy frames would still see:
- an over-exposed anvil at flat;
- a press that goes *darker* when you open it;
- a glass bottle that turns into torn paper in a plastic bag;
- a caption with "…" in it.

The P-48 fallback frames show an empty bed, and that has to be ruled out before anything else, because it is the experience for most buyers. Fixes 1–6 are about one sprint and should land around **7.0**. Fixes 7–12 plus the eye-view CI composite are what get it to a defensible **~8**.

**The single change that would most raise the score:** make the anvil's tone *stable across the whole hinge range*.
- Drive the plate shade from the virtual gap instead of the contact latch (FoldBezel.swift:238), so it lifts on reopen.
- Reshape it from a rectangular halo into the platen's soft footprint.
- Clamp the flat-pose exposure.
- Enforce \|ΔL\| ≤ 12 between the plates in CI.

That fixes the 180° store frame, the reveal and the "two different lights" feeling in every frame of every object. It's worth about **+0.7** (Light and material 1.5 → ~2.1, Colour 1.1 → ~1.3).
