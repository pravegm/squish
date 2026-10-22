# Fold Review 1: Squish on iPhone Duo (book pose)

*Design critic pass, 22 Oct 2026. Inputs: the real iPhone Duo simulator run `duo3/duo-screens` (book pose, inner 2853 × 2007 px, real hinge swept 180 → 45 → closed → reopen, 4 objects), its engine logs, and the iPhone 18 Pro simulated-hinge tabletop run `run10/90–99`. All coordinates are in **pt on the 951 × 669 book canvas**, converted from the captures (display px × 0.477). The leading (left) page is the platen and the trailing (right) page is the anvil. The crease band sits at x 455.5–495.5.*

*Caveats:*
- *The hinge driver steps in ~9.5°, so the "-150 / -75 / -60 / -45" frames were actually logged at about 146.7° / 75.8° / 61.7° / 47.5° (sealed). `c` from the logs: 118° → 0.04, 90° → 0.30, 75.8° → 0.50, 61.7° → 0.73. That matches FOLD-PRESS §4.2.*
- *No eye-view composites were produced (§9.6), so every **E** check below is my judgement from the raw frames and the eye model, not a measurement. Building that CI step is part of fix 15.*
- *Luminance figures come from a PowerShell sampler run on the raw PNGs (every 10th pixel).*

---

## 1. Verdict

**Score: 4.2 / 10** on the VISUAL-TARGET §9.2 rubric. **Duo-ness: 1.5 / 2.**

| Dimension | Weight | Score | Why |
|---|---|---|---|
| Composition | 2.0 | 0.60 → 1.2 | The plate layout, crease, rails and mirrored strike plates are right, and it does read as an opened waffle iron. Against that: the object is seen top-down as a sticker at 180–120°, and the reveal covers both heroes with UI |
| Light and material | 3.0 | 0.30 → 0.9 | **The anvil blows out as the phone closes.** Anvil field clipping goes 28% → 56% (duck) and 77% (bubble). The anvil strike plate's luminance goes 200 → 251 while the platen plate stays at 194–200. No contact shadow reads, and glass and bubble wrap go invisible, white on white |
| Colour and tone | 2.0 | 0.40 → 0.8 | The two halves don't match (platen is grey/gel-tinted cream at 234,231,228; anvil is pure white at 255,255,250). The hero is most saturated for duck and can, but bubble and glass have no local contrast at all |
| UI | 2.0 | 0.35 → 0.7 | Chip and Shelf sit on the anvil stage at idle. At the reveal: a 411 pt-tall achievement toast is truncated ("Ve…", "The fir…"), the keycaps are stacked vertically over the anvil, and the card covers the monoprint |
| Story and delight | 1.0 | 0.55 → 0.55 | **The top half's shadow → kiss → print → splat is the best thing in the build and reads at thumbnail size.** The bottom half never shows the burst: the duck is intact at 61.7° and the glass is still a standing bottle of shards |

**In one line:** the Duo *architecture* is right, and the platen is already genuinely good. But the anvil, which should be the hero, is an over-exposed white card with a top-down 3D sticker on it, and the reveal is a UI pile-up. Fix the anvil exposure, make the failure land on the anvil, and rebuild the book-pose reveal. That's three fixes between this and a ~7.

---

## 2. §12 acceptance checklist

| Check | Result | Evidence |
|---|---|---|
| **R1 Crease** | **PASS** | Every inner frame: the band measures 40.5 pt of solid graphite, and no object, mess, text or control pixel is in it. Debris fade: can't evaluate (no debris came near the crease) |
| **R2 Clearance** | **PASS** | The footprint is ~119 pt from the band edge (plate centre 221 pt from the edge). The closest projected silhouette is the glass shards at `glassBottle-75` (≈ 88 pt). The leaning can at `sodaCan-90` is ≈ 88 pt |
| **R3 Registration** | **PASS (positions)**, ✗ looks | Plates mirror exactly (platen x 121–351 ↔ anvil x 604–834), and so do the bolts (135/337 ↔ 617/821) and the pins/bushings (397 ↔ 557). The shadow centre is within ~2 pt of the mirrored footprint (`rubberDuck-150`). Glass frost and the bottle mirror correctly (`glassBottle-90`, `run10/96`). The kiss dot sits on the mirrored *apex* (head), 13/23 pt off the centre, which is acceptable by design. **But** the platen bolts and pins are white 2D domes while the anvil has 3D hex bolts and dark rings, so they don't read as one pair |
| R4 Frame | PASS / can't evaluate | Rails line up at the same y across the crease, and the hazard jaws are on both outer edges. The occlusion-region clearance for the gauge can't be evaluated from the captures |
| R5 Tone | **FAIL** | Anvil field mean L is 230–251 (target 175–215), with 28–77% clipped (T2 allows ≤ 1%): `rubberDuck-60`, `bubbleWrap-60`, `glassBottle-90`. The approach shadow is neutral grey, not `#3B2F25`-warm (`rubberDuck-150`). Bubble and glass aren't the highest-contrast region |
| R6 No UI on stage | **FAIL** | `*-180`: the RUBBER DUCK chip (y 522–556) and the Shelf keycap (y 572–620) sit on the anvil field, which ends at y 596. `*-reveal`: Again/Share sit on the anvil field, a toast covers the anvil plate (x 720–930, y 14–425), and the card covers 72% of the platen plate |
| **E1 One press** | PARTIAL (judgement) | No ram, columns or crown are drawn, and the platen reads as the lid. But the anvil reads as "a 3D toy on a white card", because it doesn't match the platen's steel and enamel (fix 1, fix 8) |
| **E2 Stands up** | likely **FAIL** (judgement) | Book eye at 180–146° is ≈ normal (log: eye = (0, 320.7, −34) mm), so the duck is a top-down blob. No grounding: no ≥ 25 L dark band under any object on the raw frames (`rubberDuck-90`, `sodaCan-90`) |
| 180: landing settled, faint approach shadow, READY, gauge 0 | PARTIAL | READY is green and the gauge is at 0 ✓. **No approach shadow** on the platen at 180 (`rubberDuck-180`, `glassBottle-180`, `sodaCan-180`); it first appears at 146.7° (`rubberDuck-150`) |
| 180: sheen sweep, grip glows on the rails, no text on stage | **FAIL** | The sheen isn't visible in any frame. The grip glow shows as an orange bleed along the whole platen rail (`rubberDuck-180`, y 12–24 and 640–657). Chip and Shelf are on stage |
| 180 E: opened clamshell, mirrored pair | PASS (raw) | `*-180`: the pair reads at flat. It degrades below 150° as the anvil steel turns white |
| 120: kiss/print 0.15–0.3 R, LOAD amber, needle off zero | **PASS** | `rubberDuck-120`: dot ≈ 0.25 R, LOAD amber, needle ≈ 8 t. `run10/91` matches |
| 120: c ≈ 0.04 bulge, lean, plate shade visible | **FAIL** | No plate shade: the anvil gets *brighter* (plate L 200 → 239). Bulge and lean can't be seen (`rubberDuck-120`) |
| 120 E (tabletop) | PASS (18 Pro only) | `run10/91`: print, gauge and duck are legible at thumbnail size, and the print sits behind and above the duck |
| **90: height ≤ 75%, bulge, lean; fractures match** | **FAIL** / ✓ match | `rubberDuck-90`: top-down, no height cue, and the silhouette grows ~20% wider, so it reads as *bigger*. Fracture match passes: `glassBottle-90` label cracks ↔ print frost lines |
| **90: print ≥ 0.55 R, saturated, Newton rings** | PARTIAL | Radius ✓ (≈ 0.8 R, `rubberDuck-90`). Newton rings aren't visible in any frame |
| 90: gauge in the middle third | borderline PASS | Needle ≈ 20–22 of 60 (`rubberDuck-90`, `sodaCan-90`) |
| 90 E (book) | can't evaluate | No composite |
| **60: every object past failure; mess persistent, inside plate + 40, not in crease** | **FAIL** (legibility) | The logs say failure happened, but the anvil doesn't show it. `rubberDuck-60`: the duck is intact (the seam split appears only on the print). `glassBottle-60`: shards still stand as a full-height bottle. `bubbleWrap-60`: the sheet is invisible. `sodaCan-60` is the only one that reads (shorter can, crumpled rim; fizz barely visible) |
| 60: print = final splat matching the anvil mess | PARTIAL | Prints are good (`sodaCan-60` ring + droplets, `rubberDuck-60` seam + beak spot). But the glass frost overruns the plate and is cut by a hard rectangle (`glassBottle-60`, `-75`), and the anvil has no matching mess |
| 60 E (tabletop) | PASS (18 Pro only) | `run10/93`: the duck is squashed and fully visible; the platen is dimmed |
| Set-level: one closing motion | top ✓, bottom ✗ | Platen: shadow → kiss → print → splat reads perfectly across `rubberDuck-150/120/90/60`. Anvil: stand → squash → burst → flat doesn't read |
| Scoring | 4.2 / 10, Duo-ness 1.5 | above |

---

## 3. Does it read as "the phone is a press closing on the object"?

**Half of it does.** The platen page is the first thing in Squish that feels like it *belongs to the hinge*:
- A soft duck shadow sharpens as you close.
- A yellow kiss lands at the mirrored spot.
- It grows into a print, and the seam split and droplets stamp into it.

That is the "this glass is the lid" proof, and it works. The anvil page undercuts it at every angle:

| Angle (logged) | What breaks the illusion |
|---|---|
| **180** | The book eye is straight down the normal, so the duck is a top-down yellow blob lying diagonally (≈ 35° yaw). It reads as a sticker, not a toy standing on steel. The platen has no approach shadow yet, so the two plates don't "belong" to each other until 146°. A dotted debug-looking arc crosses the platen plate and ends on the crease. The chip and Shelf keycap sit on the anvil. |
| **146 (150)** | Good on top: the shadow arrives. Below: nothing changes. No plate shade. |
| **118 (120)** | The kiss lands, but it's a flat matte disc. No wet highlight, no single-frame flash, so it doesn't feel like ink. The anvil steel starts going white (plate L 239) just as the platen should be shading it. The light is going the wrong way: the lid closing should make the anvil *darker under the plate* and only rim-light the object. |
| **90** | The print is great. On the anvil, top-down squash reads as the object *growing*. The steel plate is now a white card with a grey outline (19% clipped). The glass bottle loses its edges entirely. |
| **75.8 (75)** | The glass shatters, as jumbled label rectangles and near-invisible shards on white. The platen's frost star overruns the strike plate and is cut by a straight vertical and horizontal edge, so it looks like a sprite bug. Duck: no visible tell or tremor. |
| **61.7 (60)** | The print shows the duck's seam pop and splash; **the duck on the anvil is intact.** That single contradiction is the biggest story break in the build. Bubble wrap: 24 blue rings on the platen, nothing visible on the anvil. Can: the best anvil frame (shortened can, crumpled rim). |
| **47.5 (45) → closed** | Sealed. The cover is a small paper card on a black-graphite slab, with no hazard jaws, no amber seam glow and no lamp. "66 / 68 / 69 / 70 TONS" are printed beside a 0–60 dial whose needle sits at ~52. |
| **Reveal** | This is where the press should pay off as a diptych, but: the 3:4 card sits on top of the monoprint, a second PRESSED stamp peeks out from behind it, a 411 pt-tall half-empty achievement toast covers the specimen, and the card shows the *intact* object as flat clip-art. The press's two best images (print + flattened specimen) are both hidden. |

**Tabletop (18 Pro, `run10`)** reads better, because the 40° eye gives the duck real 3/4 volume (`91-fold-duck-120`, `93-fold-duck-60`), and the platen dimming at 60° sells "the lid has come over". The anvil-whiteness and reveal problems are identical there. `99-fold-jelly-reveal` has the toast covering ~60% of the screen and running off the bottom edge.

---

## 4. Top 15 fixes, ranked by impact

| # | Fix | Where (screen region, likely file) | Concrete change | Owner |
|---|---|---|---|---|
| **1** | **Stop the anvil blowing out as the phone closes** | The whole anvil page. `FoldAnvil.fieldMaterial` (FoldAnvil.swift:88), `FoldAnvil.buildPlate` steel (l.98), `FoldCurve.rimGain` (FoldGeometry.swift:542), `PressScene.setFoldStage` (PressScene.swift:972) | Measured: anvil field clip 28% → 56% → 77%; plate L 200 → 251; platen plate 194–200 throughout. **Field material:** clearcoat 0.70 → 0.35, clearcoat roughness 0.10 → 0.25, base = mix(`#F1E9DC`, gel, 0.35) then ×0.94. **Steel:** 3D strike-plate steel base → `#A9AEB5`, roughness 0.30 → 0.38. **Light:** cap rimGain at 0.6 + 0.2·clamp(…) (max 0.8); apply it to the rim light only; drop the fold-framing IBL by −0.5 EV. **CI targets:** anvil clip ≤ 1%; anvil field L 195–215; \|L(anvil plate) − L(platen plate)\| ≤ 12 at every angle | Scene |
| **2** | **Make the failure land on the anvil, same frame as the print** | Anvil object at c ≥ failure. Object views + `fx.step(ceiling:)` in fold framing; `FoldPressController` (virtual platen height) | `rubberDuck-60` intact while the print shows the seam split; `glassBottle-60` shards still bottle-height at c 0.73. **Shards:** must respect the virtual platen ceiling = `surfaceHeight(c)`; check it's actually applied in `.foldAnvil` (it looks unclamped). **Duck:** seam pop = a visible 3 pt dark seam decal plus a yellow splash mesh spreading on the plate. **Can:** fizz droplets at 2× the current size and alpha 0.9. **All:** every failure adds a spread-mesh footprint ≥ 1.3× the rest footprint, so top-down reads as "flattened, oozing", not "bigger" | Scene |
| **3** | **Book eye: give the object a 3/4 face** | Anvil 3D only. `FoldEyeModel.designEye(.book)` (FoldGeometry.swift ~l.318) | Today the eye is on the bisector, which is ≈ the glass normal at 180–146°. Add `bookTiltTowardTopDegrees = 25` [tune], rotating E about the anvil frame's z axis toward the top (crown) edge, because a held book is seen from above its top edge. Then yaw each object in book pose so its hero face points at that tilt (duck beak toward the top edge, can label facing it), with long axes parallel to the hinge. Today's diagonal ~35° duck yaw reads as random | Fold |
| **4** | **Rebuild the book-pose reveal as the diptych** | Both pages at reveal. `RevealCardView.landscape` (RevealCardView.swift), `ToastView` (Theme.swift:650), `FoldPlaten.reveal()` | **Toast bug:** `Capsule().frame(width: 4)` has unbounded height, so in the landscape VStack the toast stretches to ~411 pt. Add `.frame(height: 32)` to the rail and `.fixedSize(horizontal: false, vertical: true)` to the HStack. **Width:** never < 300 pt; truncation is banned. **Hinge book reveal:** no 3:4 card. The monoprint *is* the card, so: the PRESSED stamp thunks onto the print (already exists, 150 × 57); a paper label "RUBBER DUCK · 1 SEAM POP · 63°" in Mono 12 sits under the platen plate; the flattened specimen plus the ruler go on the anvil; one toast in the crown strip (52 pt tall, single line). The card appears only in the collect fold-and-fly | UI (+Fold) |
| **5** | **Get the keycaps off the anvil stage** | Anvil page, y 522–620 at idle; Again/Share/Next stacked at x 820–930. RootView console + `ScreenBands(hinge:)` | All controls go in the 62 pt anvil console (y 595–657), laid out horizontally. **Idle:** chip (36 pt capsule) left, Shelf (44 pt console keycap) centre-right, pilot lamp far right. **Reveal:** Again · Share · Next as 44 pt console keycaps in one row (≤ 455 pt total), with Next the only yellow. **CI:** zero UI pixels inside either plate field | UI |
| **6** | **Make the print read as ink, not vector clip-art** | Platen print. `FoldStamps` ink draw (FoldStamps.swift:298–315), `FoldPrintStack` rings (FoldPlaten.swift:220) | Today the soda can's concentric green rings look like a record button, and the kiss is a flat pale disc. **Blend:** ink layer `compositingFilter = "multiplyBlendMode"` at 0.85, so the steel streaks show through. **Edge:** wet rim inkEdge alpha 0.30 → 0.55 at 1.5 pt. **Texture:** ±8% alpha mottle. **Highlight:** one specular glint (white 0.5, 6 × 3 pt) on the wet core from kiss until c 0.3. **Newton rings:** alpha 0.06 + 0.10·c → 0.10 + 0.15·c (invisible now). **Kiss:** add the single-frame white highlight (spec §3.2.2) | Fold |
| **7** | **Fix the clipped glass frost** | Platen at failure (`glassBottle-60`, `-75`: cracks end on straight lines ~50 pt outside the plate). `FoldStamps.rect` (FoldStamps.swift:68) | Mask frost to the strike plate with `plateMask` feathered 12 pt. Glass prints on the steel; frost doesn't stray onto enamel. Or: extend the rect to plate + 80 and multiply by a radial falloff (1.0 at the plate edge → 0 at +40 pt). Add a 1 pt `shadowInk` 0.25 underlay so white frost reads on pale enamel. Remove the stray vertical line at x ≈ 376, y 243–277 | Fold |
| **8** | **One material language across both pages** | Both fields, bolts, pins. `FoldTextures.enamel`, `FoldPlaten.build` bolts/pins (FoldPlaten.swift:374–390), `FoldAnvil.setGel` | The platen is gel-tinted (glass: 241,229,219) and the anvil isn't (255,255,254). After fix 1, sample the rendered anvil field and calibrate the 2D platen field to it (ΔE ≤ 3). Draw the platen bolts from the hex top-view image (FoldTextures l.84), not white domes, so the mirror pair matches. The lips are asymmetric too: a light 6 pt strip on the platen's crease edge vs a graphite lip on the anvil. Make both graphite with the 1 pt steel highlight | Fold |
| **9** | **Ground the object and darken under the lid** | Anvil, under the object. `PressScene.buildDecals` / `updateDecals` (PressScene.swift:813–837), `SceneStyle` fold values | There's no ≥ 25 L contact band on any frame. Fold-mode values: aoAlpha → 0.55, softShadowAlpha 0.22 → 0.30, soft decal offset toward the crease by 0.25 × footprint. Plate shade (`ramDecal`) = 0.30·a² in `shadowInk`, sized to the strike plate + 20 pt, so the anvil visibly *darkens* from 150° to contact. Verify the P-48 static grounding decals (bed, columns, floor) are disabled in `.foldAnvil` | Scene |
| **10** | **Clear and white objects need edges** | Anvil, `bubbleWrap-*`, `glassBottle-*`. Object materials (VISUAL-TARGET §5.1, §5.9) | Bubble wrap is invisible at 61.7° (76.8% clipped). After fix 1: a Fresnel edge tint of `shadowInk` 0.25 on bubbles and glass; bubble sheet base `#DDEFF8` at 0.55 opacity with a 1 pt `#6FAED0` edge; popped bubbles darken by 15 L. Glass gets a dark refraction rim (`#2E5E58`, 0.4). Remove the white UV-seam lines on the bottle label (`glassBottle-180`, S3) | Scene |
| **11** | **Cover display: one tonnage, and look like the press's outside** | `rubberDuck-closed`, `bubbleWrap-closed`. CoverView.swift:150–171; gauge text in `FoldBezel` (l.204) | "66 / 68 / 69 / 70 TONS" beside a 0–60 dial with the needle at ~52, and the card and reveal agree with neither the dial nor spec's 48. **Gauge:** one source of truth; either relabel the dial 0–80 or clamp the displayed peak to the dial; same number on the cover, the card and the needle. **Labels:** move "TONS" 14 pt below the hub (it collides with "60" and the needle). **Teaser:** "WHAT'S LEFT?" is a beige blob or rectangle at ~1.2:1 contrast; use the print silhouette in graphite at 0.35. **Missing per §6.1:** add a 6 pt amber `#FFB81C` 0.5 seam glow on the hinge edge, the LOAD/green lamp, and 10 pt hazard jaws on the free edge. The card is 33% of the display; take it to 80% width. Also check the black disc at top-right of `bubbleWrap-closed` (likely the camera cutout) against the layout | UI |
| **12** | **The card must show what was pressed** | Reveal card art. `SpecimenCardView` | Duck, bottle, can and jelly are all drawn as *intact* flat silhouettes under "PRESSED". Until the 3/4 specimen snapshot lands (~1 s), show the monoprint; then the diptych (print over specimen, §6.3). Kill the duplicate PRESSED stamp peeking out behind the card. Every card says №0001: confirm that's only fresh CI installs | UI |
| **13** | **Make the sheen and guide pins actually visible** | Platen strike plate. `FoldPlaten.update` (FoldPlaten.swift:512–523), pin rims (l.388) | The sheen isn't detectable in any frame (0.22 × intensity, 70 pt band, on L ≈ 197 steel). Peak 0.22 → 0.40, `compositingFilter = "screenBlendMode"`, band 70 → 44 pt with a 6 pt core at 0.6. Pin rim +1 pt and +0.3 alpha from 150° → contact (§3.5). This is the only element tied to the *real* angle, and right now nobody can see it | Fold |
| **14** | **Replace the debug-looking ghost arc and the grip-glow bleed** | Platen, `rubberDuck-180`. `PressHints` (platen half) | The dotted grey arc crosses the plate's top-right bolt and ends on the crease edge. Make it a 3 pt tapered `#FFB81C` 0.45 stroke with a travelling glint, kept ≥ 24 pt off the plate and the crease, or drop it in favour of the sheen sweep. The orange grip glow smears along the entire top and bottom platen rails; confine it to 60 pt at the two far corners (§7.3) | Fold |
| **15** | **Crown strip and nameplate polish, plus the CI composite** | Platen crown strip y 0–64 (x 12–455). `FoldBezel` (FoldBezel.swift:63–77, 148) | The "P-48" nameplate is a flat grey `#C4C7CC` box, the most placeholder-looking object in the build. Give it a brushed-steel texture, a 1 pt top highlight, 2 rivets and Mono Bold 17. READY/LOAD labels are 6.5 pt at 55% white (unreadable, U3); make them 9 pt SF Mono Semibold at 0.8. Gauge numerals ~6 pt; take the dial 56 → 64 pt with 8 pt numerals. **CI:** build the §9.6 eye-view composite (book bisector + tabletop) so E1/E2 can be measured, not guessed | Fold / UI |

---

## 5. Specific checks

**Does the platen print mirror the anvil footprint across the crease?**
- **Yes, geometrically.** Strike plates, bolts and pins are mirror-exact to ~1 pt (the crease midline is x 475.5).
- The approach shadow centres within ~2 pt of the mirrored footprint (`rubberDuck-150`).
- The print's orientation is mirrored correctly: `glassBottle-90` neck/base, `run10/96`, `run10/93` beak spot ≈ the mirrored beak.
- The kiss lands on the mirrored *apex* (head), 13/23 pt off the footprint centre. That's correct for a duck.
- What fails is the *material* mirror. The anvil plate turns white as the platen stays steel (fix 1, fix 8).

**Does the object visibly flatten by 75° / 60°?**
- **No, except the can.**
  - Duck: top-down squash reads as growth; at 61.7° it's intact.
  - Glass: shards remain a full-height bottle at 61.7°.
  - Bubble wrap: invisible.
  - Can (`sodaCan-60`): ~20% shorter with a crumpled rim. That's the only legible flatten.
- In tabletop (`run10/93`) the duck does read as squashed. Book needs fixes 2 and 3.

**Are failures legible?**

| Object | Platen (print) | Anvil (object) |
|---|---|---|
| Glass shatter | ✓ frost star, but clipped (fix 7) | ✗ label scraps on white, no sparkle |
| Can puncture | ✓ ring + droplets | ✗ fizz barely visible |
| Bubble pops | ✓ ring stamps, very clear | ✗ nothing visible |
| Duck seam | ✓ seam line + beak spot | ✗ intact |

No failure flash was captured. Can't evaluate the timing, but add a CI frame at failure + 1 frame.

**Crown, gauge and console placement for book pose:**
- Crown on the platen page's top-left outer corner (gauge at the outer corner) and console at the bottom of the anvil page match §5.
- But the diagonal (graphite band top-left, graphite band bottom-right) makes the canvas look lopsided.
- And the console is under-used while the chip and Shelf sit *above* it on the stage.
- Recommendation: keep the crown top-leading, put *all* controls in the anvil console (fix 5), and add a mirrored empty 62 pt graphite band at the bottom of the platen page so the bands mesh when closed.

**Reveal diptych:**
- Not delivered. Card over the print, toast over the specimen, intact clip-art, truncated text, a duplicate stamp.
- No goo strands, ruler or squeegee were seen (they may fall outside the capture moment; add a reveal + 300 ms frame).

**Closed cover screen:** fix 11. Inconsistent tonnage, label collisions, a weak teaser, and none of the §6.1 "press's outside" language (yellow field or hazard edge, seam glow, lamp).

**Unfinished, debug-like or cheap:**
- The grey P-48 nameplate box.
- The dotted ghost arc.
- The frost sprite's hard rectangular clip.
- Truncated toasts ("Ve…", "The fir…") and a toast ghost overlapping Share/Next (`glassBottle-reveal`).
- The second PRESSED stamp behind the card.
- White UV seams on the bottle label.
- Green concentric print rings that look like a UI button (`sodaCan-90`).
- The flat pale kiss disc.
- 6.5 pt lamp labels.
- The asymmetric light/dark lips at the crease.
- "70 TONS" on a 60-ton dial.

---

## 6. What to keep

- The platen's shadow → kiss → print → splat sequence and the per-object print signatures, especially the bubble-wrap ring grid and the duck's seam + beak.
- Mirror registration.
- The clean 40 pt crease.
- Rails and jaws.
- The armed-at-130 / contact-132 / failures-at-73–64° mapping, which the logs show is working exactly to spec.
- The tabletop platen dimming.
- Copy lines on the cards ("Bath time is cancelled.", "Fizz has left the building.").
