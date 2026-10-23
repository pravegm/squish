# Fold Review 5: the first Duo tabletop store shots

*Design critic pass 5, 23 Oct 2026. Inputs:*
- *Real iPhone Duo simulator run `r5b/duo-screens`, which now rotates to portrait for the store pass:*
  - *Tabletop store shots (2007 × 2853): `<obj>-storeshot-hero/-112/-pair` and their `-eye` composites, for rubberDuck, glassBottle and sodaCan (all 15 viewed).*
  - *Raw tabletop inner frames `<obj>-tabletop-150/112/90/75/62/45` (luminance measured on all 18, viewed 150/90/62/45).*
  - *Book-pose raw frames: all 4 reveals, all 4 closed covers, and 180/120/90/60 for every object.*
  - *`rubberDuck-book-storeshot-*` and `logs/`.*
- *`r5/ci` (iPhone 18 Pro, 1206 × 2622): 01, 05, 20, 25, 34, 55, 80, 85, 93, 95–99, 9D (hero, pair, 112), and the new `AppIcon-1024`.*

*Method: coordinates are px of the file as named. Luminance is Rec.709 L, sampled with `scratchpad/r5tools/lumtt.ps1` on the tabletop frames. Boxes: platen field x 60–500 / y 450–1150, anvil field x 60–500 / y 1700–2550, platen plate x 580–650 / y 380–1030, anvil plate x 580–650 and x 1360–1430 / y 1830–2480. "Clip" = L ≥ 250.*

---

## 1. Verdict

**Score: 7.6 / 10** (R1 4.2, R2 5.8, R3 6.3, R4 7.1). **Duo-ness: 1.85 / 2** (was 1.75). The Duo's own store shot is now a clamshell press on a table.

**In one line:** this is the first round where the Duo has a real App Store frame. The device fills 58 % of the frame, there's a proper caption and the before/after reads as a gesture. But the central claim, *the phone closes on the duck*, still doesn't come across. Every hero reads as **an open laptop with a squashed duck in it**, and the pair's numbers contradict each other.

**Would a stranger pay £2.99 from the best set we could assemble today? Not yet. Closer than ever, though, and the remaining blockers are cheap.**
- **Best image: `rubberDuck-storeshot-hero`.** A flattened duck with eyes on its pancake, the cracked yellow print on the lid, a red frozen "65°" and a clean caption. On its own it already sells "toy that squashes things".
- **Why it doesn't sell the Duo yet:**
  - The lid is modelled at 64° but looks 100–110° open (§3).
  - The anvil strike plate is a white-hot card (§4 N2), so the glass hero shows almost nothing.
  - All three heroes carry the same caption ("It creaks. Then it doesn't."), which is wrong for a rubber duck.
  - Three of the six Duo frames we need (reveal, shelf, variety) haven't been rendered.

| Dimension | Weight | R4 | **R5** | Why |
|---|---|---|---|---|
| Composition | 2.0 | 1.5 | **1.65** | **Done:** tabletop pose, 58 % device fill (y 1050–2700 of 2853), bottom anchor, caption band, Duo inner size, before/after pair with an arrow. **Still wrong:** the lid doesn't read as closing; a 17 % dead band between the sub-line and the lid (y ≈ 560–1050); the `-112` singles have no caption (fine as inputs, unusable as frames) |
| Light and material | 3.0 | 2.0 | **2.05** | **Book:** fields matched. **Tabletop anvil plate regressed:** L 223–248 against the platen plate's 196–198 (ΔL 27–51) in 18 of 18 frames, with the right-hand third clipping 46–53 % at 150°. It's the brightest thing in every hero and it swallows the teal glass pile |
| Colour and tone | 2.0 | 1.4 | **1.5** | Duck yellow/orange coherent; the can's fizz is seeded (purple on the tabletop run, orange on the book run), and both stories hold. The bubble is still white on pale blue |
| UI | 2.0 | 1.5 | **1.75** | Toast off the crown, "· AT 64°", 0/40/80 everywhere, centred cover with the print teaser, console chip + Shelf at rest, and the new icon. The P-48's non-Duo reveal still says "CRUSHED AT 65°" on a phone with no hinge |
| Story and delight | 1.0 | 0.7 | **0.75** | Duck head now flattens (book 60 and reveal, tabletop 62/45); the can's clock hands are gone; the glass pile fills the disc. But in the store frame the squeeze is invisible (§3) |

**Weighted:** 1.65 + 2.05 + 1.5 + 1.75 + 0.75 = **7.7**, rounded down to **7.6** because the hero's main promise doesn't land.

---

## 2. Status of every FOLD-REVIEW-4 item

| # | R4 item | Status | Evidence (R5) |
|---|---|---|---|
| F1 | Duo store shot is book pose | **Fixed** | `orient=portrait` (PressDirector.swift:582 `holdInterfaceOrientation`), pass 2 in ci/duo-screenshots.sh:306–345, log `content=tabletop pose=tabletop` ×3. Book shots are kept as `-book-storeshot-*` CI artefacts only. E2 passes on `rubberDuck-storeshot-112-eye` (the duck stands on the plate, glued by its shadow) |
| F2 | Framing wastes 37–45 % | **Fixed, one leftover** | Width fit with bleed, box (0.04, 0.21, 0.92, 0.76), bottom anchor, Duo sizes (FoldStoreShot.swift:96–131, 348–352, 381–412): the device is 58 % of the height. **Leftover:** the device is width-limited, so a ~17 % empty band sits between the sub-line and the lid. Raise `targetFill` 0.58 → 0.64 and bleed 0.05 → 0.08 (l.113–116), or drop the hero box top to 0.18 |
| F3 | No visible squish | **Partly; still the #1 problem** | ✓ Hero at the post-failure hold, the pair frame, captions. ✓ Live escaped droplets in FoldAnvil (FoldPressController.swift:236): visible on the can, barely on the duck. ✗ The lid reads as open, so nothing is "between the plates" (§3) |
| F4 | Toast lives on the crown | **Fixed (code)** | 3 s each, the last one leaves (RevealCardView.swift:359–395), slot `foldToastSlot` off the crown and plates (Theme.swift:239–245), `notoasts` for capture. **Not visually verified:** every CI run passes `notoasts`, so no frame shows a toast in the new slot. Add one Duo book reveal without `notoasts` |
| F5 | Glass "Post-its" round a hole | **Partly** | ✓ The disc is filled, with a bright edge and ~6 pink + cream scraps (`glassBottle-reveal`, `-60`). ✗ Still flat teal cards. A pale translucent "ghost" disc sits in the centre. On the tabletop white plate the pile almost disappears (`glassBottle-storeshot-hero`: teal at ~L 215 on a ~L 235 plate) |
| F6 | Duck head a ball on a pancake | **Mostly fixed** | Head blob CPU-deformed (DuckView.swift:11–36, 166, 280): flattened disc with eyes at book 60, reveal and tabletop 62/45. At 90 the head is still a full sphere, which is acceptable as a progression |
| F7 | Can creases = clock hands | **Fixed** | SodaCanView.swift:29, 401. `sodaCan-60/reveal` and `97`: tab only, crumpled green ring |
| F8 | Bubble wrap weakest | **Not (cosmetic only)** | Film base 6 % darker (BubbleWrapView.swift:83). But `bubbleWrap-180` still has the full-plate rectangular grey ghost on the platen; `-90/60/reveal` print is still 24 outline circles with a tick each (FoldStamps.swift:374); the reveal is white crinkles on pale blue |
| F9 | PRESSED in the same place | **Partly** | Pose from the print box (FoldPlaten.swift:607–646). Bubble now tilts −20° bottom-left. But duck, glass and can still land on the lower-third centre over the print. Jelly: paper-white with red keyline ✓ (`99`) |
| F10 | Cover and console | **Fixed** | `*-closed`: card centred both ways, print thumbnail as the "WHAT'S LEFT?" teaser, tonnage dial (CoverView.swift:53). The console has the object chip + Shelf at rest |
| F11 | Icon is stock | **Fixed, with caveats** | New `AppIcon-1024`: a dark clamshell biting down on magenta jelly, drips, hazard lips. The right idea. Caveats in §4 N8 |
| F12 | Two machines disagree | **Fixed** | 0/40/80 on the P-48 (`34`, `55`), the crown and the cover (RigTextures.swift:5, Contracts.swift:127). The "P-48" nameplate stays, which is fine |
| F13 | Bare angle in the caption | **Fixed** | "RUBBER DUCK · 1 HONK · 1 SEAM POP · AT 64°" (RevealCardView.swift:187–188) |
| F14 | Jelly leftovers | **Partly** | PRESSED legible ✓. `99` still spreads past the plate on both sides at the reveal, despite JellyView.swift:38 |
| §3.3 A | Tabletop CI pass | **Done** | As F1 |
| §3.3 B | Product framing, Duo sizes, sheen 0.04 | **Done** | Sheen 0.04 (FoldStoreShot.swift:710). Backdrop is still `.studio` by default; `.duoSweep` exists but no run used it |
| §3.3 C | Hero at failure, diptych, escaped splat | **Done, but it doesn't read** | See §3 |
| §3.3 D | Anamorphic strength 0.95–1.0 | **Unverified** | No A/B in this run |
| §3.3 E | Captions in the renderer | **Done** | SF Pro Rounded Heavy with a yellow word and an SF Mono sub-line (l.548–611). **But one caption is used for all objects** (PressDirector.swift:509–510) |
| §3.3 F | Device fidelity | **Not** | Still a generic 4.6 mm slab |
| R3 N9/N15 | Bubble print and approach shadow | **Not** | As F8 |
| R3 N16 | Empty console | **Fixed** | As F10 |
| CI seed | Achievements off | **Done** | `notoasts` |

---

## 3. The angle question: is the store-shot lid at the labelled angle?

**Yes. The geometry is right, and θ is the interior angle between the panels (180 = flat), not 180 − θ.** The problem is perception, not maths.

**In the code** (FoldStoreShot.swift, `StoreRig.init` l.1038–1076, `away` l.1099–1101, `normal` l.1106–1108):
- The anvil page runs along +u from the crease (tabletop: u = world +z, toward the viewer; v = up).
- The bend leaves along −u and turns by φ = π − θ (l.1063–1072). Its last tangent is heading θ.
- The platen page leaves the bend along (cos θ, sin θ) (l.1100). The angle between the anvil's (1, 0) and that is exactly θ.
- At θ = 64° the lid points (0.44, 0.90): it leans **26° past vertical toward the viewer**, over the anvil.
- Screen normal (sin θ, −cos θ) = (0.90, −0.44): into the wedge, facing the viewer and slightly down. ✓

**The plumbing:**
- `hingeAngle = clamp(storeshotfold ?? angle, 45, 180)` (PressDirector.swift:669), where `angle` is the last real hinge sample (l.547, 557). The log has `hinge=63.6 model=63.6` for all three heroes.
- The pair label is `Int(hingeAngle.rounded())` = "64°" (FoldStoreShot.swift:341–342).
- So the label, the model and the hinge agree. The heroes are the same rig at the same 63.6°.

**Checked in the pixels.** A lid leaning toward a 34°-elevation eye puts its free edge nearer the camera than the crease, so it must project **wider** than the crease edge:

| Frame | Lid free-edge width | Crease-edge width | Ratio | Predicted |
|---|---|---|---|---|
| `glassBottle-storeshot-pair`, large device (64°) | ≈ 1370 px | ≈ 1160 px | **1.18** | 1.17 (eye distance 353 vs 413 mm) |
| `rubberDuck-storeshot-112` (111°) | ≈ 1410 px | ≈ 1380 px | **1.02** | ≈ 1.01 |

The on-screen lid height also drops from 0.66 × its width at 111° to 0.42 at 64°, matching cos-foreshortening of 0.98 vs 0.50. **The renderer draws a 64° lid.**

**Why it looks ~100° open anyway:**
1. **No profile of the V.** At azimuth 14° the hinge axis is almost square to the line of sight. A lid tilted 26° toward you and one tilted ~20° away differ only by a 17 % keystone and some foreshortening. People default to "laptop lid leaning back", especially with its face fully visible.
2. **No occlusion.** The 64° lid can't hide any of the anvil from a 34° eye. That needs an elevation above 64° (the line through the free edge hits the table 68 mm *behind* the crease).
3. **No lid shadow on the anvil.** The only shadows are on the floor (FoldStoreShot.swift:420–441). A lid leaning over a lit page would darken the back third of it, and nothing does. In the app the anvil field stays at L 210 even at 45° (lumtt), which is correct for a screen but kills the cue in a still.
4. **The 4.6 mm body is invisible at this azimuth**, so the lid's edge thickness can't show its lean.
5. **The numbers fight.** In the same device the red crown readout shows the frozen failure angle, and the label shows the hold angle:
   - glassBottle **83° vs 64°**
   - sodaCan **71° vs 64°**
   - rubberDuck **65° vs 64°**

   The glass frame, where 83 sits right above "64°", is the one the founder caught.

**Fix (top fix #1, §5):**
- **(a) Make the numbers agree.** Preferred: label the large device with what its screen says. Set `afterLabel` to the frozen readout, written "AT 83°" like the reveal card (FoldStoreShot.swift:340–343, fed from the failure angle in `writeStorePair`, PressDirector.swift:761–777).
  - Alternatively, hold the hero within 2° of each object's failure angle: per-object `FAIL_HOLD` in ci/duo-screenshots.sh:94 (duck 63, can 70, glass 80), plus that angle in `TABLETOP_ANGLES` (l.93). The seeds are deterministic: failure is at 64/71/81 in both runs.
  - Never show a bare "64°" next to a red "83°".
- **(b) Add a lid cast shadow and wedge AO on the anvil page,** as a new draw between the anvil page texture and the lid in `deviceDraws` step 3 (l.474–493):
  - Project the lid's outline along `light` (l.416) onto the anvil plane, clip it to the anvil screen, blur σ = 0.02·devicePixels, alpha 0.10 + 0.25·(1 − (θ − 45)/135).
  - Add a linear AO gradient from the crease, 0.18 → 0 over 35 % of the anvil depth, scaled the same way.
  - This is device lighting, not app content, so it's truthful. At 111° it is faint; at 64° the back half of the anvil darkens and the lid reads as hanging over it.
- **(c) Add a side-profile glyph to each pair label:** two 2-stroke lines at the true θ with a small arc, ~6 % of the frame width, next to "111°" and "AT 83°" (`drawPairMarks`, l.622–668). That makes the V explicit without moving the camera.
- **(d) Optional:** render the pair's *small* device at azimuth 24° (`options.before.azimuthDegrees`, PressDirector.swift:771), where the hinge barrel and V profile start to show. Check E2 on its `-eye`. Shear is tolerable at 40 % scale.
- **Expected effect:** the lid reads as closing in 2 of 3 viewers without explanation. That's the difference between "a duck in a laptop" and "a phone that crushes a duck".

---

## 4. New issues, ranked by impact

### N1. The hero doesn't show the squeeze (lid reads open) — **M** — see §3
- **Frames:** all `-storeshot-hero`, all `-storeshot-pair`.
- **Fix:** §3 (a) to (d).

### N2. Tabletop anvil strike plate is a white-hot card — **S**
- **Frames:** all 18 `*-tabletop-*`, and every tabletop store shot.
- **Numbers:** anvil plate L 223–233 left / 238–248 right; clip 10–11 %, rising to 46–53 % at 150°. The platen plate is 196–198 (it drops to 161–167 at 62° with the lid dim).
  - That's ΔL +27 to +51. R4's book target was ≤ 17.
  - In the glass hero the teal shards (~L 215) disappear into it. In the duck hero the pale pancake edge merges with it.
- **Cause:** FoldAnvil.swift:184–195. The plate is lit metallic PBR (`#A9AEB5`, roughness 0.38, metallic 1). The tabletop design eye (40°, in front) catches the studio's key in the mirror direction. Book pose doesn't, so R4 never saw this.
- **Fix:**
  - Tabletop only: roughness 0.38 → 0.55 and base `#A9AEB5` → `#9EA3AA`.
  - Or rotate the IBL 40° about y for `!layout.isBook`, so the key isn't in the plate's mirror direction.
  - Target: anvil plate ≤ platen plate + 12 at 112°, clip 0 %. Add it to the lum CI check.

### N3. One caption for three objects, and the wrong one for the duck — **S**
- **Frames:** all three heroes.
- **Problem:** "It creaks. Then it *doesn't*." (PressDirector.swift:509) is the glass frame's line from screenshots.md §A frame 4. On a rubber duck it's a non-sequitur, and frame 1 should carry the product line.
- **Fix:** a per-object default in `heroCaption`:
  - duck: "Close your phone. Feel it *give*."
  - glass: "It creaks. Then it *doesn't*."
  - can: "Cans buckle *ring* by ring."
  - Pair caption: "Fold it shut. Open to *see*." (`pairCaption`, l.510), because "Close your phone" moves to the hero.

### N4. Half the Duo set doesn't exist yet — **M**
- **Missing:** a tabletop reveal, a Duo shelf, and a variety frame (egg, cake or bubble).
- **What exists:** the tabletop pass sweeps 150 → 45 and stops. It never reopens, so there's no tabletop reveal (every `*-reveal.png` is book pose, landscape 2853 × 2007), and `shelf` was never run on the Duo.
- **Fix:**
  - Add `reveal` to `STORESHOT_SHOTS` (ci/duo-screenshots.sh:92). The script reopens to 150° after the 45° hold; `watchStoreShots` (PressDirector.swift:526) writes `storeshot-reveal` once the reveal phase settles, with caption "Open up. File the *evidence*."
  - Add a Duo portrait `shelf` capture with `collection=7` (screenshots.md request 3).
  - Add `egg` and `cakeSlice` to `STORESHOT_OBJECTS` (l.91).

### N5. Glass still reads as paper — **M**
- **Frames:** `glassBottle-60/reveal`, `glassBottle-storeshot-hero`.
- **Fix** (after N2, which alone recovers half the contrast):
  - Darken shard tint 20 % → 35 % toward `#5FB8A8` and keep the bright rim (GlassBottleView.swift:121; MeshKit.swift:610 `rimInset`).
  - Drop the centre "ghost" disc to 50 % alpha or remove it (l.489 onward, the pile).
  - Scale the label scraps ×1.4 (l.43), so the pink/cream identity reads at thumbnail.

### N6. The 6.9" set is the wrong size and partly wrong content — **S**
- **Frames:** `r5/ci/*` are **1206 × 2622** (6.1"-class), not 1320 × 2868.
- **Problems:**
  - `05/80` print "CRUSHED AT 65°" on a phone with no hinge (AchievementInfo.swift:60).
  - No frame shows the Pinch Press ram handle that P1 requires (screenshots.md §C). `01` has a coach card and no visible handle.
  - `55-glass-mid` is unreadable: a few teal dots under the ram.
- **Fix:**
  - Add a 6.9" simulator (iPhone 17/18 Pro Max class) to ci/screenshots.sh. Keep the 1206 × 2622 set for the 6.1" slot (screenshots.md heads-up c).
  - On non-hinged devices, print "CRUSHED AT 53 TONS" instead of the angle (AchievementInfo.swift:56–60, when `failureAngle` came from the virtual mapping).
  - Re-shoot glass at depth 0.66.

### N7. 18 Pro store shots clip the caption — **S (CI hygiene)**
- **Frames:** `9D-…-storeshot-hero` (the top line "It creaks." is cut off).
- **Problem:** this predates 0ee3115 (caption shrink-to-fit), so it's probably fixed, but there's no frame proving it.
- **Fix:** re-run 9D. These shots never go in any set (Guideline 2.3: the 18 Pro doesn't fold).

### N8. Icon caveats — **S**
- **Frames:** `AppIcon-1024`, `85-icon`.
- **Problem:**
  - The magenta mass with a single specular streak reads first as **a tongue poking out of a mouth**, second as jelly.
  - At 60 px the hazard lips merge into the graphite and the drips become three dots.
  - The camera lens on the lid (AppIconArt.swift:261–270) is generic, but it is the only thing saying "phone". Keep it.
- **Fix:**
  - Swap the jelly for the duck's yellow splat (Palette.duckYellow), with one visible duck eye or the orange beak tip squeezing out. That reads as "squashed duck" at any size and matches the hero frame.
  - Or keep magenta but break the tongue silhouette into 3–4 lobes with two cube bits (like the `99` print).
  - Thicken the hazard lips ×1.5 for the small sizes.

### N9. PRESSED still sits over the print — **S**
- **Frames:** duck, glass and can reveals.
- **Fix:** in `pressedPose` (FoldPlaten.swift:607–646), choose the plate corner with the *least* print coverage, not "30 % over the print" (l.642). Allow tilt −8° ± 10°.

### N10. Bubble wrap — **S**
- **Frames:** `bubbleWrap-180` (box ghost), `-90/60/reveal`.
- **Fix:** unchanged from R4 F8, and it's the last unfixed object family. Bubble isn't in the proposed Duo set, so this is not launch-blocking for the screenshots, but it's object #1 in the picker (`01-launch`).

### N11. Jelly overflows the plate at the reveal — **S**
- **Frame:** `99`.
- **Fix:** clamp the reveal spread in JellyView.swift:264 (the containment helper) to plate + 16 pt. It's currently applied during the press but not after the latch.

---

## 5. App Store screenshot set (proposed)

Rule: **frames 1–3 must each sell alone.** No raw anamorphic frame goes in the inner set; it reads as "two flat trays" (R2–R4).

### A. iPhone Duo inner display (2007 × 2853), 6 frames

| # | Source | Caption (headline / sub-line) | Why | Ready? |
|---|---|---|---|---|
| **1** | `rubberDuck-storeshot-hero` **re-rendered** after N1 (b/c) and N2, with the caption changed (N3) | **Close your phone. Feel it *give*.** / *Squish turns the fold into a hydraulic press.* | The single strongest image: an unmistakable flattened duck, the cracked print on the lid and a red frozen angle | **Not as is.** Today's file has the wrong caption and a lid that reads open |
| **2** | `sodaCan-storeshot-pair` re-rendered with "AT 71°" as the after label (N1 a), the profile glyphs and the lid shadow | **Fold it shut. Open to *see*.** | The only frame that shows the gesture, and with a different object from frame 1 the search triplet shows variety | **Not as is.** The 71° vs 64° conflict misrepresents (§3) |
| **3** | `glassBottle-storeshot-hero` re-rendered after N2 + N5 | **It creaks. Then it *doesn't*.** | Spectacle. The cracked bottle print is the most graphic lid in the set | **Not as is.** The pile is invisible on the hot plate. **Flag:** if N2 doesn't land, use the can hero here and drop glass |
| **4** | **To render:** a tabletop reveal of the duck at ~150° (N4): flat duck on the anvil; PRESSED print, "AT 64°", READY green and the Again · Share · Next console on the lid | **Open up. File the *evidence*.** / *Every press becomes a specimen.* | The payoff. It also shows real UI chrome (buttons), so the set doesn't look like renders only | **No file** |
| **5** | **To render:** Duo portrait shelf with seeded `collection=7` and one Golden, as a raw inner frame (the shelf isn't anamorphic, so raw is honest) | **A shelf of pressed *specimens*.** / *No ads. No in-app purchases.* | The reason to come back, plus the purchase promise | **No file** (`ci/20-shelf` is 18 Pro and can't be used) |
| **6** | **To render:** an egg or cake-slice tabletop hero; or a 3-up of the duck, can and glass heroes at 40 % scale on one sweep (new `renderGrid` beside `renderPair`) | ***Ten* objects. Ten ways to give.** | Variety. Answers "is it just one duck?" | **No file** |

- **Optional 7:** settings sheet, raw: "Press without folding. Hear it *softer*."
- **Never use:** `*-eye` composites (E-check artefacts: front-on, the lid sides flare and it looks like a box), `*-book-storeshot-*` (wall-mounted duck), any raw `*-tabletop-*`, or the `-112` singles (no caption, nothing happening).

### B. iPhone Duo outer display (1398 × 2034), 2 frames

| # | Source | Caption | Notes |
|---|---|---|---|
| O1 | `rubberDuck-closed` (raw cover) with a caption band added | **Ka-chunk. Now *open* it.** | Ready apart from the caption: centred card, print teaser, 52 TONS. Needs the caption drawn over the empty graphite top 25 %. `FoldStoreShot.drawCaption` can be reused on a raw image |
| O2 | To capture: `cover;shelf` closed-launch picker | **Pick on the cover. Press *inside*.** | Not run this round |

### C. iPhone 6.9" (1320 × 2868), Pinch Press, 6 frames

| # | Source | Caption | Notes |
|---|---|---|---|
| P1 | Re-capture `34-duck-mid` on a 6.9" simulator, with the ram handle visible | **Drag it down. Feel it *give*.** / *A hydraulic press for every iPhone.* | `34` is 1206 × 2622 and has no handle. Composition is good: the duck bulging under the ram |
| P2 | Re-capture bubble at depth 0.40 | **Every bubble *pops* on its own.** | Not in r5 |
| P3 | Re-capture can at depth 0.55 | **Cans buckle *ring* by ring.** | Not in r5 |
| P4 | `05-reveal-duck`, re-captured at 6.9" after N6's label change | **Open up. File the *evidence*.** | **Flag:** "CRUSHED AT 65°" on a non-folding phone misleads. Fix N6 first |
| P5 | `20-shelf` re-captured at 6.9" | **Collect every pressed *specimen*.** | Good: 7/10, seeded |
| P6 | Settings | **No ads. No purchases. *Just* the press.** | Not in r5 |

**Flagged as misrepresenting, never upload:**
- `9A–9D` and `90–99` (an 18 Pro drawn folded, Guideline 2.3).
- Any pair whose label disagrees with its readout.
- A glass hero whose pile you can't see. That isn't a lie, but it shows nothing.
- `55-glass-mid`.

---

## 6. Top 5 fixes, in order

1. **Make the squeeze read, and make the numbers agree** (§3 a–d, N1).
   - FoldStoreShot.swift: `deviceDraws` l.474–493 (lid cast shadow + wedge AO on the anvil page), `drawPairMarks` l.622–668 (profile glyphs), `PairMarks` l.340–343 (after label = "AT <frozen readout>°").
   - PressDirector.swift:761–777 (pass the failure angle).
   - Optionally azimuth 24° for the pair's small device.
   - **M. +0.3, and the biggest effect on conversion:** it turns frame 1 from "duck in a laptop" into "phone crushing a duck".
2. **Tame the tabletop strike plate** (N2; FoldAnvil.swift:184–195; roughness 0.55, `#9EA3AA` or a tabletop IBL yaw; a CI lum assert ΔL ≤ 12). Unblocks the glass frame and cleans up every hero. **S, +0.2.**
3. **Render the missing frames, with per-object captions** (N3 + N4: `heroCaption`/`pairCaption` per object, PressDirector.swift:509–510; `reveal` in STORESHOT_SHOTS; Duo shelf; egg/cake; optional `renderGrid`). Without these there is no 6-frame set. **M, +0.15**, but it's what makes submission possible at all.
4. **Glass reads as glass** (N5; GlassBottleView.swift:43/121/489). **M, +0.15.**
5. **6.9" set at the right size and honest** (N6: 6.9" simulator, Pinch handle, "CRUSHED AT 53 TONS" on non-hinged devices via AchievementInfo.swift:56–60). Plus the icon tweak (N8: yellow duck splat in place of the magenta tongue). **S, +0.15.**

**Quick wins to batch (all S):** fill 0.64 / bleed 0.08 (F2 leftover), PRESSED corner (N9), jelly clamp (N11), one Duo reveal without `notoasts` to verify F4, and re-running 9D for caption proof.

**Honest projection:** top 5 + quick wins → **~8.3** (8.1 if §3 b/c only half-convince). Past 8.5 needs one of these:
- the bubble family rebuilt (N10);
- a real-device photo or video for frame 1 (§7);
- F-3D (R4 §3.3 D): a true side-on "into the fold" view, the only way to show plates *touching* something.

---

## 7. Ship-readiness: what only the founder or a real Duo can settle

1. **Does the illusion hold in a hand?** The store shots are honest only if a user, at about the 40°/380 mm design eye on a real tabletop Duo, sees the duck *standing* the way `-112` shows it. Check:
   - head movement of ±10 cm;
   - the ~5° hinge noise jittering the eye model;
   - whether book pose reads as a pop-up.

   If it doesn't hold, the 3/4 composites overstate the app, and frame 1 should become a real photo.
2. **Does closing feel like pressing?** Haptics, the ka-chunk at seal, the real hinge's stiffness against the strain curve, and reveal timing through the display-off window (55–20°) and the reopen hysteresis to ~150°.
3. **Tone on the OLED:** whether L 210 cream holds up in daylight, and whether the tabletop plate glare (N2) is as bad on hardware as in the simulator.
4. **Thermals at 120 Hz** during a slow 30 s press.
5. **App Store Connect:** whether the Duo inner and outer slots are selectable yet (screenshots.md heads-up a). If not, ship with the 6.9" and 6.1" sets and add the Duo set by metadata edit.
6. **Founder decisions:**
   - **(a) Rule change.** Allow one real tabletop-Duo photo (62° and 112°, on a `#F3EEE6` sweep, locked camera at ~35°) as frame 1. That contradicts screenshots.md's "no device photos" rule; the rule predates knowing that raw frames can't carry the idea, and a photo would beat any render.
   - **(b) Device likeness.** Accept the generic slab, or match the real Duo bezel and hinge from Apple Design Resources.
   - **(c) Captions.** Sign them off, per object (N3).
   - **(d) Icon.** Jelly or duck (N8).
   - **(e) App Preview.** Keep it out of the Duo slot, or use a 6.9" Pinch Press capture only (Guideline 2.3.4: screen captures only).
7. **App Review on a non-Duo device.** Confirm the reviewer path ("Press without folding" / Pinch Press) is called out in the review notes, because reviewers may not hold a Duo.
