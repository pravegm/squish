# Fold Review 3: Squish on iPhone Duo (book pose), after the round-2 fixes

*Design critic pass 3, 22 Oct 2026. Inputs:*
- *Real iPhone Duo simulator run `r3/duo/duo-screens` (iOS 27.1): book pose, inner 2853 × 2007 px, hinge driven 180 → 150 → 120 → 100 → 90 → 75 → 60 → 45 → closed → reopen, for bubble wrap, glass bottle, rubber duck and soda can (40 inner frames + 4 covers), plus `logs/` (SQUISH-H).*
- *Regular-iPhone frames `r3/ci/01–99` (P-48 touch press and the simulated fold on an 18 Pro) and `AppIcon-1024.png`.*

*Method: same as round 2. Coordinates are **pt on the 951 × 669 book canvas** (platen = left page, anvil = right page, crease band x 455.5–495.5); cover coordinates are pt on 466 × 678. Luminance is Rec.709 L sampled every 4th pt by a PowerShell sampler (`scratchpad/r3tools/lum.ps1`) in four fixed boxes: platen field x 30–100, anvil field x 845–920 (both y 90–300), platen plate x 130–160 and anvil plate x 790–820 (both y 200–450). "Clip" = L ≥ 250. There is still no §9.6 eye-view composite, so every **E** check is judgement.*

---

## 1. Verdict

**Score: 6.3 / 10** (R1 4.2, R2 5.8). **Duo-ness: 1.75 / 2** (unchanged).

**One line:** the round-2 bookkeeping fixes landed (P-48 renders again, captions fit, one gauge scale, unlatched shade), but the pictures a buyer judges by didn't get better. The flat frame is more blown out than before, objects slide toward the crease as you close, the glass still explodes into Post-it notes, and the duck reveal looks less squashed than the frame before it.

**Would a stranger pay £2.99 from App Store screenshots made from these frames? No.** Seen flat, the raw frames show:
- a cream tray with a yellow blob on it (duck);
- a toppled can;
- a bottle lying on its side;
- an ice-cube tray (bubble wrap).

There is no sense that "the phone *is* the press", because that only works from the design eye. Paid-tier screenshots need the eye-view or device-mockup render (N1), not these frames.

| Dimension | Weight | R2 | **R3** | Why |
|---|---|---|---|---|
| Composition | 2.0 | 1.3 | **1.3** | **Better:** captions fit and the NEW BEST tag is a sticker. **Worse:** duck, can and bottle slide ~50 pt toward the crease between 180 and 90 (N2); the duck's head overhangs the plate's crease edge by ~17 pt at 75; the bottle overhangs the plate bottom by ~20 pt at 180–90; glass debris overruns the plate by 34–53 pt |
| Light and material | 3.0 | 1.5 | **1.6** | **Better:** during the press, plate ΔL ≤ 12 for all four objects (for example duck 194/202, glass 195/188); no box halo outside the plate. **Worse:** the flat 180° frame regressed: anvil field clips **72 %** (bubble, R2 56 %), **40 %** (glass, R2 15 %), 12 % (duck), 0 % (can). Field L is 243–250 against the platen's 211–212. The reveal anvil plate is still 21–28 L darker than the platen (duck 175/203, can 176/202, glass 183/204) |
| Colour and tone | 2.0 | 1.1 | **1.2** | Can story unified (lilac print, lilac puddle). Fields still differ: platen grey-beige 212, anvil cream 214–250 |
| UI | 2.0 | 1.3 | **1.5** | **Fixed:** captions, cover gauge 0/40/80, seam glow, teaser in colour. **Still wrong:** "P-48" nameplate on a machine that isn't the P-48; the PATIENCE toast on **4 of 4** reveals, covering the lamps and nameplate; crown gauge "0" under the needle and "TONS80" run together; ~18 % of every frame is empty console graphite |
| Story and delight | 1.0 | 0.6 | **0.7** | Duck print and glass frost are now good, and bubble registration is exact. But deformation isn't visible top-down between 120 and 75. The can jumps from intact can to steel bowl in one step. Glass is still a confetti explosion, and the duck reveal un-squashes (N6) |

**Weighted:** 1.3 + 1.6 + 1.2 + 1.5 + 0.7 = **6.3**.

---

## 2. Status of every FOLD-REVIEW-2 item

| # | R2 fix | Status | Evidence (R3 frames) |
|---|---|---|---|
| 1 | P-48 regression (empty bed) | **Fixed** | `ci/34-duck-mid`: the duck is under a lowered ram. `ci/05`: squashed duck card. *Left over:* the P-48 gauge is still 0–60 (`34`), and `ci/01-launch` was captured mid-fade (ghosted machine, empty bed), so it's a capture-timing problem, not a render bug |
| 2 | Rebuild glass failure | **Partly (code), not (look)** | Necks no longer stand ✓. But `glassBottle-75/60/45/reveal` still read as **12 big pink and cream rectangles plus translucent teal cards** thrown 34–53 pt past the plate (x 563–870, y 150–537 pt; plate x 601–831, y 184–484), with a ghost bottle (the dust disc) in the middle. The pile is *larger* at the reveal than at 45°. Causes in N5 |
| 3 | Unlatch and reshape the plate shade | **Mostly** | Gap-driven (`FoldBezel.swift:243–246`), no outer halo, plate ΔL ≤ 12 from 150 to 45° ✓. **Reveal still fails:** the anvil plate is 21–28 L darker than the platen for duck, can and glass (bubble passes, 199/202). The likely cause is the flat-pose term in `FoldCurve.exposure` (−0.3 EV, −8 % key at θ ≥ 160, so 170° gets it) |
| 4 | Fix exposure at flat (store frame) | **Not fixed; regressed** | 180°: anvil field 250 / 249 / 246 / 243 with clip 72 / 40 / 12 / 0 % (bubble / glass / duck / can) against the platen at 212. `bubbleWrap-180` is the worst: the anvil half is near-white. The −0.3 EV flat term (FoldGeometry.swift:566–570) is not enough. See N3 for the structural fix |
| 5 | Reveal: sealed specimen, ruler, strands | **Partly** | Height rebound is capped (DuckView.swift:120–124) ✓. **But the puddle shrinks on reopen:** the skirt radius follows *live* compression (DuckView.swift:141–143). The `rubberDuck-reveal` footprint is ~152 × 176 pt against ~185 × 233 pt at `-45` (≈ 60 % of the area), so the specimen looks less pressed than the frame before. No ruler and no goo strands in any reveal |
| 6 | Caption truncation | **Fixed** | "RUBBER DUCK · 1 HONK · 1 SEAM POP · 67°", "BUBBLE WRAP · 24 POPS", "GLASS BOTTLE · SHATTERED · 83°", "SODA CAN · 5 BUCKLES · 69°": all whole. The ribbon is a tilted sticker on the plate corner ✓ |
| 7 | Contain mess and frost | **Partly** | Glass frost stays inside the plate and fades ✓ (best print in the set). Jelly (`ci/99`) still overflows its plate by ~60–70 pt on both sides, still has a vertical shading seam, and the PRESSED stamp still disappears on magenta. Glass debris on the anvil isn't contained (see 2) |
| 8 | Bubble film hard cut and floating dome | **Not fixed: wrong root cause** | The 0.6 mm lift went in (BubbleWrapView.swift:71–72), but the cut is still there and *moves*: x ≈ 780 pt at 100°, 756 at 90°, 744 at 60°, 737 at 45°. Intact domes float past it (770, 352 pt at 60°). At the reveal (lean 0) the film is whole again. **Real cause:** the 8°·c clamshell lean tips the whole slot about the plate centre, so the far half of the 0.8 mm film sinks under the strike-plate face (N2). Craters are still grey on grey |
| 9 | Can: one colour story, visible buckles | **Partly** | Colour ✓ (lilac print, lilac puddle). The print still reads as a target (rim ring + glowing disc), even with the 5 radial creases. The anvil can still turns into a **steel bowl** with a green rim (`sodaCan-60/45/reveal`): no creases, no folded wall |
| 10 | Cover: one gauge scale, real teasers | **Mostly** | Dial 0/40/80, red 60–80 ✓. A ~5 pt gold hinge-edge glow is now visible ✓. Teasers are coloured but show *intact* objects: bubble is an app-icon tile, soda reads as a jar or battery, glass is clip-art. The card sits at y 219–425 of 678 pt, so 61 % of the cover is empty graphite |
| 11 | Wordless invitation at 180; remove the wedge | **Not** | No grip pads visible in any 180 frame (code exists, FoldPlaten.swift:492, but isn't visible in captures). The wedge shadow is still on the anvil field at the crease side: `rubberDuck-180/150/120/100` x 573–601, y 190–266 pt; `sodaCan-120` x 563–601, y 200–309 pt |
| 12 | One material across both halves | **Partly** | Pins now match at rest (dark studs on both) and only the platen's light up on contact ✓. The fields still don't match (platen grey-beige, anvil cream with a warm light pool around the plate's crease side). The duck print's beak is still a flat orange disc |
| + | §9.6 eye-view composite | **Not started** | No composite or eye-view code anywhere in the repo |
| + | Seed CI so PATIENCE doesn't fire | **Not** | Fires on 4 of 4 Duo reveals |

---

## 3. New issues, ranked by impact on "worth paying for"

### N1. The store screenshots can't be raw frames, and nothing else exists yet — **L**
- **Frames:** every Duo frame, especially `sodaCan-90/75` (a can lying on its side, end-on), `glassBottle-180` (bottle on its side), `rubberDuck-*` (top-down yellow blob), `bubbleWrap-180` (ice-cube tray).
- **What's wrong:** the anvil is anamorphic by design (§2.2). It only stands up from the design eye. Shown flat, which is how the App Store shows it, the "two halves are the press" idea doesn't come across, and the objects look like flat icons on a cream tray. A buyer sees a matching pair of trays, not a press.
- **Fix:**
  - Build the §9.6 eye-view render as a **store-shot mode**: re-render the anvil with a standard perspective camera at the design eye, and texture the platen page onto a hinged quad at the real θ. The output is a Duo-shaped device mock-up at 110–120°, seen from 3/4 front, with the crease visible.
  - The same pipeline gives CI the E1/E2 and 90°-height checks it still can't measure.
  - **Where:** a new `Squish/Scene/Fold/FoldStoreShot.swift` driven from `FoldPressController` (reuse the `FoldStage` camera and `FoldLayout`). The share card already avoids the anamorphic view (ClipStudio.swift:99), so follow that pattern.
  - Until it exists, take the store screenshots as photos or renders of a physical Duo in book pose at ~110°.

### N2. The clamshell lean is 3× spec, pivots at the plate centre, and drags everything toward the crease — **S**
- **Frames:**
  - Duck centre x 727 → 675 pt (180 → 90); bottle 723 → 675; can 725 → 673.
  - `rubberDuck-75/90`: head 17 pt over the plate's crease edge, onto the enamel.
  - `bubbleWrap-100/90/60/45`: the film sinks (N/R2-8).
- **What's wrong:**
  - The code is `lean = 8° · renderCompression` (FoldPressController.swift:402), applied to the whole `objectSlot` about +x at its origin (PressScene.swift:1012). §12 asks for a 2–3° lean *away* from the hinge. Here it reaches 7.8° at seal.
  - On screen the tops move *toward* the crease, so check the sign as well.
  - A flat sheet rotated about its centre buries its far half in the plate.
- **Fix:**
  - `lean = 2.5° · c`, sign checked against the eye.
  - Pivot at the footprint's crease-side base edge, not the slot origin.
  - `lean = 0` for sheet-like objects (`bubbleWrap`) and once `failed`, so debris lies on the plate.
  - Add a CI assert: projected footprint centre within ±6 pt of its 180° position at every angle.

### N3. Flat-pose exposure got worse, and the fields still don't match (the 180° store frame) — **S**
- **Frames:** `bubbleWrap-180` (field 250, clip 72 %), `glassBottle-180` (249, 40 %), `rubberDuck-180` (246, 12 %), `sodaCan-180` (243). Platen field is 211–212 in every frame of every object.
- **What's wrong:** the anvil field is a lit PBR enamel (FoldAnvil.swift:93–98, `lit: 0.94`, clearcoat 0.35). It mirrors the studio head-on at flat, and no EV term fixes that for every object's gel. The two halves look lit by two different lamps, and that is the first frame a buyer sees.
- **Fix (structural):**
  - Make the anvil **field** unlit: `SceneMaterials.unlit` with the *same* `FoldTextures.enamel(gel:)` colour the platen uses, plus the existing AO decal for grounding.
  - Only the plate, bolts, pins and object need real light.
  - Then drop the flat term from `FoldCurve.exposure` (FoldGeometry.swift:566–570). It is also the likely reason the reveal plate is 21–28 L darker.
- **CI:** |L(anvil field) − L(platen field)| ≤ 6 and |ΔL plates| ≤ 12 at 180, 120, 90, 60 and the reveal.

### N4. Deformation isn't legible top-down between 120° and 75° — **M**
- **Frames:**
  - `rubberDuck-120 → -75`: the log says c 0.04 → 0.43, but the footprint grows only ~8 % and the head dome stays a perfect sphere.
  - `sodaCan-90` vs `-75`: identical, then a sudden bowl at `-60`.
  - `glassBottle-180 → -90`: no change at all until the shatter.
- **What's wrong:**
  - From above, height is invisible. The only cue is footprint spread, and the duck's is clamped at 1.2× (`DuckView.swift:135`, `min(1/√s, 1.2)`).
  - The fold feels like nothing happens for half its travel, then it pops.
- **Fix: give each object top-down strain cues that ramp with c from 0.05.**
  - **Duck:** spread clamp 1.2 → 1.7. Head squashes to an ellipse (scale the head SDF separately). Highlights widen and dull (clearcoat roughness 0.05 → 0.3 with c). A growing contact rim, a darker wet ring on the steel at the footprint edge. Eyes slide outward.
  - **Can** (`SodaCanView.swift:185–222`): the rim ovalises and the lid dents from c 0.1. Fire the buckle bands one at a time *visibly* from the top, as dark crease decals on the shoulder. No single-frame jump to a bowl.
  - **Bottle:** crack lines lengthen with c before failure (fracture 0 already spawns 7). Add slight ovalisation, ±4 %.
  - **Bubble:** fine as is. Domes visibly squash and spread.

### N5. Glass failure: concrete causes of the Post-it look — **M**
- **Frames:** `glassBottle-75/60/45/reveal`.
- **What's wrong, in code (`Squish/Scene/Objects/GlassBottleView.swift`):**
  1. `sectorCounts = [1, 6, 6, 6, 5, 3]` (l.81). The two label bands are 6 shards each, each ≈ 31 × 25–29 mm, so 12 big rectangles of flat pink and cream.
  2. The shards are 60° lathe arcs. Laid "flat", they still curl like cards.
  3. The skid velocity `0.18…0.4` m/s + 0.12 up (l.241) flings them past the plate.
  4. `bottle.scale = SIMD3(repeating: 1)` is still at l.217, so shards are adopted at rest size.
  5. The dust is still radius 0.040–0.055 m ≈ the footprint (l.164), which reads as a translucent bottle-shaped bag.
  6. The reveal pile is larger than at 45°, so the replay or debris settling keeps moving it.
- **Fix:**
  - `sectorCounts = [1, 10, 14, 14, 8, 4]` with 25° arcs (flatter), and shrink the label patches to 70 %.
  - Velocity 0.04–0.10 m/s, no up component in `.foldAnvil`.
  - Clamp the final positions inside plate + 16 pt.
  - Remove l.217.
  - Dust radius `0.022 + 0.010·t`, opacity 0.18.
  - Freeze debris at seal (no re-burst in the reveal replay).
  - **CI:** debris bounding box ⊂ plate + 24 pt at 60°, 45° and the reveal; reveal box ≤ 45° box.

### N6. Duck reveal "un-squashes"; no ruler, no strands — **S**
- **Frames:** `rubberDuck-45` vs `-reveal`.
- **Fix:**
  - In `DuckView.update` (l.139–145), latch `t` at its maximum (like `deepest`), so the skirt never shrinks on unloading.
  - Make the reveal capture wait for the 0.3× replay to end on the sealed pose.
  - Add the §6.3 ruler ("2.4 mm") beside the anvil plate (x 840–900 pt) and the 2–4 strands. They live in `FoldPressController` reveal step and `RevealCardView.diptych`.

### N7. "P-48" nameplate on the Duo — **S**
- **Frames:** every Duo frame, crown x 222–313, y 33–55 pt.
- **What's wrong:** the P-48 is the *other* machine (the non-Duo H-frame). On the Duo the phone is the press. A model number from a machine that isn't on screen reads as a leftover. It also takes the one prime crown slot.
- **Fix:**
  - Replace it with a **live hinge-angle readout** on the same brushed plate: "118°", Mono Bold, engraved, ticking with θ and freezing red at the failure angle.
  - This is the most Duo-native piece of chrome the app could have. It also explains the bare "67°" in the reveal caption, which should become "AT 67°".
  - **Where:** `FoldTextures.nameplate` (FoldTextures.swift:300–330, the hard-coded `"P-48"` at l.325), refreshed from `FoldBezel.update` (FoldBezel.swift:203).

### N8. Achievement toast on every reveal; Patience is mis-specified for a fold — **S**
- **Frames:** all four `*-reveal` (x 90–447, y 20–68 pt), plus `ci/05` and `ci/99`.
- **What's wrong:**
  - The toast covers the lamps and nameplate at the one moment the press should go green and READY.
  - It lands in every reveal screenshot.
  - `CollectionStore.swift:242` is `stats.longestPress > 30`, without the "depth changes at least every 10 s" clause in `docs/appstore/achievements.md:26`. On a Duo a slow, careful fold *is* the gesture, so most first presses will earn "Very zen".
- **Fix:**
  - Queue achievement toasts until the reveal settles (≥ 2.6 s) or the first console tap. Lives in `TipCenter.swift` / `PressOverlays.swift`.
  - Implement the 10 s engagement rule.
  - Seed CI to skip achievements.

### N9. Bubble wrap reads as a wireframe, not a squish — **S**
- **Frames:** `bubbleWrap-120…reveal`.
- **What's wrong:**
  - The print is 24 identical blue outline circles inside a stroked rounded rectangle: a UI diagram.
  - Popped craters are grey on grey.
  - The reveal specimen is white crinkles on grey steel, with no colour or contrast.
- **Fix:**
  - **Print** (FoldStamps.swift:142–151): make the film edge a faint dashed impress, not a 2 pt stroke. Vary ring weight and alpha by how hard each pop was. Add the ink mottle used on the duck print.
  - **Craters** (`BubbleWrapView.pop`, l.179–183): a 1 pt `#6FAED0` rim at 0.6, centre −15 L, and a tiny bright pinhole highlight.

### N10. Can is a steel bowl — **M**
- **Frames:** `sodaCan-60/45/reveal`.
- **Fix** (`SodaCanView.swift`):
  - In fold mode, crush with a 2–3 mm lateral offset so one side wall folds *outward* past the lid, visible from above as a crumpled ring of label green.
  - Add 5 dark crease decals matching "5 BUCKLES".
  - The print (`FoldStamps` soda contact, l.607–609) drops the full rim ring for a broken, buckled outline.

### N11. Crown gauge legibility — **S**
- **Frames:** every Duo frame, dial ≈ 59 pt at (20–79, 15–74) pt.
- **What's wrong:** five numerals on a 59 pt dial. The "0" sits under the needle at rest, and "TONS" runs into "80" ("TONS80").
- **Fix:** numerals 0/40/80 only (as on the cover), "TONS" centred under the hub. `FoldTextures` gauge face, FoldTextures.swift:268–284 (`by: 20` → `by: 40`).

### N12. PRESSED stamp is a carbon copy — **S**
- **Frames:** all reveals. Same spot, same −8°, covering the print's lower third (bubble rows 5–6, the can's ring).
- **Fix:** seeded ±6° and ±20 pt offset, biased to the plate's lower-far corner, 85 % scale. On prints whose hue is within 30° of stamp red, use paper-white ink with a red outline (the jelly case). FoldPlaten.swift:661–670.

### N13. Wedge shadow on the anvil field (still) — **S**
- **Frames:** `rubberDuck-180/150/120/100`, `sodaCan-120` (x 563–601 pt, on the enamel just past the plate's crease edge, cut straight by the plate).
- **Fix:** clip the soft decal to plate + 8 (`PressScene.updateDecals`, l.843: `softDecal` at 1.8 × footprint) and check whether the fold key light's real-time shadow is falling off-plate. If so, disable shadow casting onto `FoldAnvil.field`.

### N14. Glass bottle overhangs the plate at rest — **S**
- **Frames:** `glassBottle-180/150/120/100/90`. The base reaches y ≈ 504 pt against the plate bottom at 484.
- **Fix:** in `.foldAnvil`, scale ×0.90 or yaw −30° so the 140 mm bottle fits the plate diagonal (`GlassBottleView.heroScale`, l.16; `entity.orientation` l.143).

### N15. Bubble wrap has no approach shadow at 180°, and its 150° shadow is a box — **S**
- **Frames:** `bubbleWrap-180` (platen plate clean), `-150` (a rectangular dark block, platen plate L 169).
- **Fix:** for sheet objects, start the approach shadow at 0.08 alpha at 180°, and use a soft-cornered footprint (radius ≥ 24 pt, blur ≥ 28). Lives in the platen shadow layer in `FoldPlaten.swift` (driven by `FoldCurve.shadow`, FoldGeometry.swift:576).

### N16. Empty console and cover — **S**
- **Frames:** every pressing frame. The console bands (y 595–657 pt) are empty graphite apart from one lamp, about 18 % of the screen. `*-closed`: 61 % of the cover is empty.
- **Fix:**
  - During the press, keep the object chip in the anvil console, dimmed to 40 % and non-interactive, so screenshots say what's being pressed.
  - On the cover, centre the card vertically in the free area and scale it to ~80 % width.
  - Teaser: show the actual print thumbnail (the platen already has it) instead of an intact-object icon. "WHAT'S LEFT?" next to an intact bottle contradicts itself. `CoverView.swift:206–224`.

### N17. App icon says "hydraulic press game", not "fold your phone" — **M**
- **Frame:** `ci/AppIcon-1024`. A front-on yellow ram squashing pink jelly.
- **What's wrong:** well executed, but it's the P-48 and the category's stock look (dozens of free "hydraulic press" toys use it). Nothing hints at the Duo, the paid hook.
- **Fix:** a half-open book-pose phone in graphite, seen from 3/4 front, as the jaws, with the pink splat squeezing out of the hinge and the hazard stripes on the free edges. `UI/AppIconArt.swift`.

### N18. Consistency roll-up (one-liners)

| Check | Duck | Bubble | Glass | Can |
|---|---|---|---|---|
| Approach shadow at 180 | ✓ | ✗ | ✓ (spills onto the enamel, top and bottom) | ✓ |
| Kiss at 120 | ✓ | ✓ | ✓ | ✓ (target ring) |
| Visible progressive squash 120 → 75 | ✗ weak | ✓ | ✗ | ✗ |
| Failure matches print | ~ (seam 20 pt vs crack 110 pt) | ✓ exact | ✗ (print ✓, anvil ✗) | ~ (colour ✓, shape ✗) |
| Specimen flat at reveal | ✗ (shrinks back) | ✓ | ✗ (explosion) | ✗ (bowl) |
| Stays inside its plate | ✗ (17 pt over at 75) | ✓ | ✗ (34–53 pt) | ✓ |

---

## 4. §12 checklist delta (R2 → R3)

| Check | R2 | R3 |
|---|---|---|
| R1 Crease / R2 Clearance / R4 Frame | PASS | **PASS** |
| R3 Registration | PASS (positions) | **PASS.** Bubble pops mirror cell-for-cell at 100, 90 and 60° (e.g. 60°: platen intact (row 4, far col) ↔ anvil intact (row 4, crease-far col)). Duck beak and print bump mirror |
| R5 Tone | PARTIAL | **PARTIAL.** Press frames ✓ (plates within 12). 180 ✗ (clip up to 72 %). Reveal ✗ (plates 21–28 apart) |
| R6 No UI on stage | PASS | **PASS** |
| **E1 One press** | PARTIAL | **PARTIAL.** Raw frames read as two trays (N1) |
| **E2 Stands up** | PARTIAL | **FAIL (raw).** The can reads toppled at 180, 150, 120, 90 and 75 |
| **90: height ≤ 75 %** | FAIL | **FAIL (not legible).** The log has c = 0.30 at 90°, but nothing shows it top-down (N4) |
| **60: every object past failure, mess inside plate + 40** | PARTIAL | **PARTIAL.** Glass debris out to plate + 53 |
| 180: grip glows, sheen | PARTIAL | **PARTIAL.** Sheen ✓ (150–100); grip pads not visible |

---

## 5. Top 5 fixes that would move the score most

1. **Unlit, gel-matched anvil field + remove the flat EV term** (N3; `FoldAnvil.fieldMaterial`, `FoldCurve.exposure`). Fixes the 180° store frame and the reveal plate tone, and ends the "two lamps" look in every frame. **S, +0.5.**
2. **Fix the lean** (N2; `FoldPressController.swift:402`, `PressScene.swift:1012`): 2.5°·c, base-edge pivot, zero for sheets and debris. Stops objects sliding toward the crease and the duck spilling off the plate, and makes the bubble-film cut go away for free. **S, +0.4.**
3. **Glass: small flat shards, contained, frozen at seal** (N5; `GlassBottleView` l.81, l.164, l.217, l.241). It's the most "broken-looking" frame family and the one a buyer will screenshot. **M, +0.4.**
4. **Top-down strain cues + a reveal that stays squashed** (N4 + N6; `DuckView` spread clamp l.135 and skirt latch l.141, `SodaCanView` progressive buckles). The fold has to *visibly do something* every 10°, and the reveal must be the flattest frame, not a rebound. **M, +0.4.**
5. **Store-shot (eye-view) render mode** (N1; new `FoldStoreShot.swift`). Without it, no screenshot sells the Duo idea, and CI still can't run E1, E2 or the 90°-height check. **L, +0.3 on score, but the largest effect on whether anyone pays.**

**Quick wins to batch with these (all S):** hinge-angle readout instead of "P-48" (N7); defer achievement toasts and fix the Patience rule (N8); crown gauge numerals 0/40/80 (N11); varied PRESSED stamp (N12); wedge shadow clip (N13); glass overhang (N14).

**Projection:** Top 5 + quick wins → **~7.6–7.9**. To reach a defensible 8+, it then needs N9, N10 and N17 and a device check of the anamorphic eye on real hardware.
