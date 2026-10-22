# Fold Review 4: Squish on iPhone Duo, after the round-3 fixes, plus the first store shots

*Design critic pass 4, 23 Oct 2026. Inputs:*
- *Real iPhone Duo simulator run `r4b/duo/duo-screens` (book pose, inner 2853 × 2007 px): bubble wrap, glass bottle, rubber duck and soda can at 180/150/120/100/90/75/60/45/closed/reveal (36 inner frames + 4 covers), and `logs/` (SQUISH-H/F/T).*
- *The new store-shot renders (`FoldStoreShot.swift`, 1320 × 2868): `rubberDuck-storeshot-120/-75` (3/4 view) and `-eye` (design eye) from the Duo run; `ci/9A–9C-*-storeshot-*` (110/120/90/60°, 3/4, eye and one landscape) from the iPhone 18 Pro simulated fold, whose halves are nearly square and fold horizontally (tabletop).*
- *A sample of `ci/` (01, 34, 93, 99, AppIcon-1024). Round-3 Duo frames (`r3/duo/duo-screens`) for comparison.*

*Method: same as rounds 2 and 3. Coordinates are **pt on the 951 × 669 book canvas** unless they are marked "px" (pixels of the file as named). Luminance is Rec.709 L, sampled with the round-3 boxes (`scratchpad/r4tools/lum.ps1`, a copy of `r3tools/lum.ps1`): platen field x 30–100, anvil field x 840–920 (y 90–300), platen plate x 130–160, anvil plate x 790–820 (y 200–450). "Clip" = L ≥ 250. The eye-view composite now exists, so the **E** checks are judged on the `-eye` renders.*

---

## 1. Verdict

**Score: 7.1 / 10** (R1 4.2, R2 5.8, R3 6.3). **Duo-ness: 1.75 / 2** (unchanged. The halves are the plates, but the Duo's own store shot doesn't show it.)

**One line:** the engineering round worked. Tone is fixed everywhere, the lean is right, glass is contained, the duck stays flat and the hinge readout is the best piece of chrome in the app. And for the first time there is an image that could sell: the tabletop eye composite at ~60° (`ci/9C-…-storeshot-60-eye`). But it comes from the **iPhone 18 Pro simulated fold**. The **Duo's** own store shot is book pose, and it shows a duck stuck to a wall.

**Would a stranger pay £2.99 from App Store screenshots made from the best of these? Not yet. But it's now a framing problem, not a rendering problem.**
- **Best image:** `9C-store-duck-sweep-storeshot-60-eye`. A clamshell with a flattened, splatted duck on the bottom plate and its cracked yellow print on the lid. It reads as "the phone squashed a duck" with no explanation, and it's the first image in four rounds I'd put in slot 1.
- **What's wrong with it:**
  - The device fills only 47 % of the frame height, with 37 % empty beige above it.
  - It's an 18 Pro, which doesn't fold, so it can't go in any screenshot set.
  - The Duo version of the same shot doesn't exist yet, because the Duo run is book pose only.
- **The Duo book-pose store shot (`rubberDuck-storeshot-120/75`):** the two pages stand vertically on the table like an open book. The duck projects out of a vertical wall like a mounted trophy, and the print is a decal on the facing wall. Nothing says "press". A stranger wouldn't pay from this.

| Dimension | Weight | R3 | **R4** | Why |
|---|---|---|---|---|
| Composition | 2.0 | 1.3 | **1.5** | **Better:** glass pile inside the plate; bottle fits the plate at rest (base 1010 px vs plate edge 1015 px); wedge shadow gone; bubble film whole at every angle. **Still wrong:** the achievement toast now sits on the crown strip in every reveal, over the lamps *and* the new hinge readout; the console is still ~18 % empty graphite; the cover is unchanged; the store shots are 34–47 % device and 37–43 % empty backdrop |
| Light and material | 3.0 | 1.6 | **2.0** | **Fixed:** the anvil field is 209–210 against the platen's 211–212 in **36 of 36** frames, 0 % clip (R3: up to 72 %). Reveal plates are within 10 L (duck 203/211, can 198/192, glass 204/194, bubble 198/212). **Still weak:** the glass shards are flat teal cards with white dots; the bubble film is near-white at 180 (anvil plate L 229 vs platen plate 192); the bubble 150° approach shadow is still a box (platen plate L 169) |
| Colour and tone | 2.0 | 1.2 | **1.4** | Fields finally one material. Can story is now orange print, peach puddle and green label: coherent enough. Bubble reveal is white on pale blue, with no contrast |
| UI | 2.0 | 1.5 | **1.5** | **Fixed:** live hinge readout ("118°", red "66°" frozen at failure), gauge 0/40/80 with TONS under the hub. **Regressed:** the "FIRST SQUISH" toast now covers the hinge readout too, and "the last one stays" (RevealCardView.swift:376), so it is in 4/4 Duo reveals and `ci/99`. Caption still ends in a bare "66°". Cover is unchanged |
| Story and delight | 1.0 | 0.7 | **0.7** | Duck reveal is now the flattest frame ✓, glass cracks grow on the print before failure ✓, can crumples into a green ring ✓. But the duck's head stays a perfect ball on top of the pancake, the can lid gets three black clock hands, and glass is still confetti |

**Weighted:** 1.5 + 2.0 + 1.4 + 1.5 + 0.7 = **7.1**.

---

## 2. Status of every FOLD-REVIEW-3 item

| # | R3 item | Status | Evidence (R4 frames) |
|---|---|---|---|
| N1 | Store shot / §9.6 eye-view render | **Partly** | `FoldStoreShot.swift` exists: 850 lines, deterministic, opaque PNG, 3/4 and design-eye variants, CI hooks for 9A–9C and the Duo. **The tabletop rig sells** (`ci/9B-…-120-eye`, `9C-…-60-eye`: the duck stands on the plate, E2 passes). **The book rig, the only one the Duo run used, doesn't** (`rubberDuck-storeshot-120/75`: the duck is wall-mounted). Framing is loose (§3) |
| N2 | Lean: 2.5°·c, base-edge pivot, none for sheets or debris | **Fixed (code)** | FoldPressController.swift:412–416 and FoldGeometry.swift:588–613 (`FoldLean`, eased to 0 at failure); PressScene.swift:1016–1025 (pivot shift). The bubble film cut is gone at 100/90/60/45. **Note:** the raw duck still drifts toward the crease, centre 723 → 680 → 666 pt (180 → 120 → 90). That is the anamorphic projection following the eye, not the lean: the log has the eye going from z −34 mm (over the crease) to +163 mm at 90°. R2 still passes (head ≥ 80 pt from the crease band). Change the proposed CI assert to measure the **contact-shadow centre**, not the silhouette |
| N3 | Unlit, gel-matched anvil field; drop the flat EV term | **Fixed** | Field L 209–210 vs 211–212 in all 36 frames, clip 0 %. Plates ΔL ≤ 17 on every press frame except bubble (150: 169/210, box shadow; 180: 192/229, white film). Reveal plates within 10 |
| N4 | Top-down strain cues from c 0.05 | **Partly** | ✓ Duck spread 1.7 (DuckView.swift:139–143); the footprint grows visibly 120 → 60. ✓ Glass: print crack at 90°, anvil neck crack at 90°. ✓ Can: rim ovalises, green crumple ring at 60. ✗ Duck head never squashes: the whole duck scales uniformly in XZ, so top-down the head is a perfect sphere at every angle, even in the reveal. ✗ No highlight dulling or wet ring |
| N5 | Glass: small flat shards, contained, frozen | **Partly** | ✓ `sectorCounts [1,10,14,14,8,4]`, skid 0.04–0.10, contained to plate + 16, frozen at seal (reveal pile ≈ 75° pile), dust 0.022 + 0.010·t. ✗ **The look is still "Post-its", just smaller:** ~50 translucent teal rectangles, each with a white dot (the sparkles, GlassBottleView.swift:370); a **ring with an empty middle** (placement starts at 0.33× footprint out, l.355/361); and only 3 label scraps (1 pink, 2 cream), so the bottle's identity is lost while the print still shows a whole bottle |
| N6 | Duck reveal stays squashed; ruler; strands | **Partly** | ✓ Latched, and the reveal is the widest footprint in the set (`rubberDuck-reveal` pancake ~ 1255–1790 px wide vs ~1230–1740 at 60). ✗ No ruler, no strands |
| N7 | Hinge-angle readout replaces "P-48" | **Fixed** | Every Duo frame: "180°… 118°… 90°", red "66°/81°/71°" frozen at failure. The most Duo-native thing in the app. ✗ The caption still says "· 66°" rather than "AT 66°". ✗ The P-48 (non-Duo, `ci/34`) still has a 0–60 gauge and the "P-48" plate, so the two sets disagree on tonnage scale |
| N8 | Defer toasts; Patience rule; seed CI | **Partly** | ✓ Patience needs 30 s of engaged pressing (CollectionStore). ✓ Toasts wait for the settled reveal. ✗ **"ACHIEVEMENT · FIRST SQUISH" is in 4/4 Duo reveals and `ci/99`**, now over the crown (x 190–940 px, y 40–145 px), covering the lamps and the hinge readout. It never leaves ("the last one stays", RevealCardView.swift:376). ✗ CI is not seeded to skip achievements |
| N9 | Bubble print reads as a wireframe | **Not** | `bubbleWrap-90/reveal`: still 24 identical blue outline circles in a stroked rounded rectangle; craters grey on grey; the reveal specimen is white crinkles on pale blue |
| N10 | Can is a steel bowl | **Partly** | ✓ `sodaCan-60/reveal`: a crumpled green label ring outside the lid reads "crushed can". ✗ The crease decals are three straight black bars on the lid at r 26 mm (SodaCanView.swift:323–331, `creaseRadius` l.361). With the tab they read as **clock hands**. ✗ The print is still a target (rim ring + disc + radial cracks) |
| N11 | Crown gauge legibility | **Fixed** | 0/40/80, TONS under the hub, no "TONS80" |
| N12 | PRESSED stamp carbon copy | **Partly** | Seeded (FoldPlaten.swift:598–605), but ±20 pt and −8° ± 6° around one base on the print's lower half, so all 4 reveals still look the same: duck (480, 865 px), bubble (440, 835), glass (475, 845), can (420, 820), all ≈ −14°, all over the print's lower third (bubble rows 5–6, the glass label band). Jelly (`ci/99`) still vanishes into magenta |
| N13 | Wedge shadow on the anvil field | **Fixed** | `rubberDuck-180…100`, `sodaCan-120`: clean. A faint pale triangle remains on the anvil plate's upper-crease corner at 180 (x 1270–1340, y 400–540 px), a reflection. Ignore it |
| N14 | Glass overhangs the plate at rest | **Fixed** | `glassBottle-180/90`: base inside the plate |
| N15 | Bubble approach shadow | **Not** | 180: none. 150: a hard rectangular block over the whole film (platen plate L 169) |
| N16 | Empty console and cover | **Not** | Console bands are still empty graphite apart from one lamp while pressing. Cover unchanged: card at y 645–1255 of 2000 px, shifted left (x 70–1055 of 1345 px: 70 px margin on the left, 290 on the right), teaser still an *intact* object (a jar icon for the soda can, a whole duck) next to "WHAT'S LEFT?" |
| N17 | App icon says "hydraulic press game" | **Not** | `AppIcon-1024` unchanged |
| N18 | Consistency roll-up | **Better** | See the table below |
| + | Eye-view composite for CI E1/E2 | **Done** | `*-eye.png`. E2 passes on the 18 Pro tabletop composite, fails on the Duo book composite (§3) |
| + | Seed CI so achievements don't fire | **Not** | — |

**Roll-up (R4):**

| Check | Duck | Bubble | Glass | Can |
|---|---|---|---|---|
| Approach shadow at 180 | ✓ | ✗ | ✓ (still spills onto the enamel above and below the plate, y 330 and 1060 px vs plate 390–1015) | ✓ |
| Kiss at 120 | ✓ | ✓ | ✓ | ✓ (target ring) |
| Visible progressive squash 120 → 75 | ~ (footprint ✓, head ✗) | ✓ | ✓ (cracks) | ✓ (oval, then crumple) |
| Failure matches print | ✓ | ✓ exact | ✗ (print: whole bottle; anvil: teal confetti ring) | ~ |
| Specimen flat at reveal | ~ (ball head) | ✓ | ✗ (confetti) | ✓ |
| Stays inside its plate (+40) | ✓ (+21 pt) | ✓ | ✓ | ✓ |

---

## 3. The store shot, judged hard

### 3.1 What exists

| Render | Device fill (height) | Empty above | Reads as |
|---|---|---|---|
| Duo `rubberDuck-storeshot-120` (book, 3/4) | 34 % (y 860–1530 of 2000) | **43 %** | An open hardback stood on its end with a duck sticker on the right page. The duck's "up" is the page normal, so in a third-person view it sticks **sideways out of a vertical wall** |
| Duo `-120-eye` | 30 % | 45 % | Same, front-on, smaller |
| Duo `-75` / `-75-eye` | 45 % / 40 % | 37 % / 40 % | A bigger, flatter duck still mounted on the wall; the print is a yellow blob on the facing wall. No sense that the walls are closing on it |
| 18 Pro `9B-…-120` (tabletop, 3/4) | 47 % | 37 % | **A laptop-shaped clamshell with a rubber duck standing on the bottom plate.** E2 passes: base glued by its shadow, verticals upright |
| 18 Pro `9C-…-60-eye` | 47 % | 37 % | **The best image in the project.** Flattened, split duck on the plate, cracked yellow print on the lid above it |
| 18 Pro `9B-…-120-land` | 79 % (landscape) | — | Tidy product shot, but the device is ~40 % of the frame width |

### 3.2 Does it sell "the phone *is* a press crushing a duck between its halves"?

**Book pose (Duo): no.** **Tabletop (18 Pro stand-in): halfway.** Concretely, five things stand in the way.

1. **Wrong pose for a third-person picture.** On the device, book pose works because the eye sits on the bisector and the duck pops out toward you, like a pop-up book. In a render seen from outside, gravity is down and the anvil is a wall. The anamorphic object can only look "standing" when its page is the floor.
   - The tabletop rig already proves it (`9B`, `9C`).
   - The Duo supports tabletop too: portrait inner display, fold horizontal. `FoldLayout` picks a horizontal axis for a 669 × 951 canvas (FoldGeometry.swift:83).
   - `docs/appstore/screenshots.md` §A is *written* for that pose ("the fold runs horizontally… anvil below").
   - Yet `ci/duo-screenshots.sh` only drives book pose (`posture.txt`: `currentDeviceOrientation: landscapeRight` on every inner frame).
2. **The picture is mostly backdrop.**
   - The hero box is `CGRect(0.07w, 0.32h, 0.86w, 0.56h)` (FoldStoreShot.swift:224–226), and the fit is `min(width, height)` (l.235).
   - A clamshell is wider than tall, so it's width-limited and lands at 34–47 % of the height, centred low.
   - The ~30 % caption band reserved above it is *also* empty, because no caption is drawn.
   - At thumbnail size (search results show three screenshots at ~1/4 width) the duck is ~90 px wide.
3. **No contact, so no squeeze.**
   - At 120° the print is a kiss on a lid that is visibly 5 cm above the duck.
   - At 60° the duck is a pancake and the print a splat, but the lid still visibly hovers. That's the §4.4 virtual gap, which is correct in use and lethal in a still.
   - The eye needs one of three things: (a) a sequence; (b) a frame where the lid is low and the mess is *escaping*; (c) a caption that tells it what it's seeing.
4. **The camera can't move far.** The anvil page is a flat *picture* warped for one eye. The renderer maps those pixels onto the page (l.313–315), so the object only stands up within roughly ±10–15° of the design eye.
   - 9B's 26° azimuth is already at the edge: the duck starts to shear.
   - A low "into the mouth of the fold" camera (elevation 10–20°) would flatten the duck back into a sticker.
   - So "look into the fold" is **not** available with the current pipeline. It needs a real 3D pass (§3.3 F-3D).
5. **It's a generic slab, not an iPhone Duo.** 4.6 mm halves, 44 pt corner radius, black glass bezel.
   - Next to Apple's own Duo imagery it will look like a knock-off.
   - Mocking up Apple hardware also brushes against Apple's marketing guidelines, which want Apple-provided device imagery.

### 3.3 What would make it sell (with numbers)

**A. Make the Duo store shot tabletop (biggest single change). M.**
- **CI:** add a portrait pass to `ci/duo-screenshots.sh`. Rotate the simulator to portrait so the inner canvas is 669 × 951 (fold horizontal), then drive the same angles with `storeshot=115,62` for duck, glass and can.
  - The app side needs nothing: `StoreRig.init` already builds the tabletop world when `!layout.isBook` (FoldStoreShot.swift:625–631), and `writeStoreShot` passes the live layout.
- **Book renders:** keep them, but only as CI E-check artefacts. Never use them for marketing.

**B. Frame it like a product shot. S.** New and changed `FoldStoreShot.Options`:

```swift
struct Options {
    var size = FoldStoreShot.duoInner            // NEW 2007 × 2853 (Duo inner slot); keep .portrait 1320 × 2868 for non-Duo only
    var hingeAngle: Double = 62                  // hero: post-failure splat; second frame 112
    var eye: Eye = .threeQuarter
    var azimuthDegrees: Double? = 14             // was tabletop +26 / book −22 (l.808); ≤ 15 keeps the anamorphic object upright
    var eyeModel: FoldEyeModel = .standard       // set .elevationDegrees = 34 (design 40): looks a little more into the mouth,
                                                 // still inside the ±8° window where the warped anvil reads as standing
    var fit: Fit = .width(bleed: 0.05)           // NEW: fit the device's projected width to the box, allow 5 % bleed past the side edges
    var heroBox: CGRect? = nil                   // NEW: portrait default (0.04, 0.21, 0.92, 0.76) of the frame, replacing (0.07, 0.32, 0.86, 0.56)
    var anchor: Anchor = .bottom(0.03)           // NEW: sit the contact line 3 % above the box bottom instead of centring (StoreFit, l.842–850)
    var caption: Caption? = nil                  // NEW: headline / highlight word / sub-line in the top 21 %, per screenshots.md (SF Pro Rounded Heavy,
                                                 // graphite on #F3EEE6, one word #FFB81C, cap height ≥ 4 % of the frame height)
    var glassSheen = true                        // keep, but alpha 0.07 → 0.04 (l.389): it greys the print on the lid
    var backdrop: Backdrop = .studio             // NEW: .studio (today) | .duoSweep (a cooler #E9E6E1 → #D9D5CE sweep; the beige-on-beige studio
                                                 // swallows the cream enamel)
}
nonisolated static let duoInner = CGSize(width: 2007, height: 2853)
nonisolated static let duoInnerLandscape = CGSize(width: 2853, height: 2007)
nonisolated static let duoOuter = CGSize(width: 1398, height: 2034)
```

- **Expected result:** on a Duo tabletop at 62°, the page is 669 pt ≈ 111 mm wide and ~76 mm deep.
  - At azimuth 14° and elevation 34° the device projects about 1.1 : 1 (w : h). Fitted to 0.92 × 2007 px it is ~1850 px wide and ~1650 px tall: **58 % of the frame height instead of 34 %**.
  - The strike plate spans ~45 % of the frame width, so the duck is ~400 px wide in the full frame and ~100 px at search-result size.
- **Portrait vs landscape:** portrait 2007 × 2853 is primary, because search results show the first three portrait shots side by side.
  - Landscape 2853 × 2007 fits the clamshell almost perfectly (device ≈ 85 % of the height) but shows one shot at a time in search.
  - Test landscape for frame 1 with Product Page Optimization once the Duo slot exists in App Store Connect (screenshots.md heads-up a).

**C. Pick the squish moment, and show the motion. S.**
- **Hero:** duck at the hinge's failure freeze (~62–66°, c ≥ 0.6, the `rubberDuck-60` state). The print is a splat with the seam crack and droplets; the anvil is a pancake.
  - Capture with `storeshot=62` after the failure event, not on a fixed angle (`watchStoreShots`, PressDirector.swift:487).
- **Frame 2 (the gesture):** a **diptych in one frame** at `storeshotfold=112` and `62`. Small device at top left (40 % scale), large device bottom right, a hand-drawn arrow between them. Caption: "Close your phone. Feel it *give*."
- **Frame 3:** reveal at 150° tabletop: the flattened specimen plus the PRESSED print on the lid, "Open up. File the *evidence*."
- **Splat that escapes the fold must be real**, because of the truthfulness rule in screenshots.md. Have the platen splat droplets also appear on the **anvil field just outside the strike plate** at failure: 6–10 sprites, seeded like the print's droplets, so they exist on the device too. The 60° frame then has mess on *both* pages, toward the viewer, and the press reads as having squeezed something out.

**D. Make the object stand up *more*. M.**
- **The anamorphic strength is 0.85** (`foldAnamorphicStrength`, §9.4). For the duck in tabletop, 0.95–1.0 makes it stand taller from the design eye (projected height ≤ 1.2× still holds at 40°).
  - Test it in the Tuning Lab on the 18 Pro composite first.
  - Don't let the object break the screen edge in the render. It can't on the device, and that would break the truthfulness rule.
- **F-3D (optional, L):** a true 3D object pass for marketing only. Render the object entity offscreen with a symmetric `PerspectiveCamera` at the store eye, composite it over a clean (object-less) anvil page capture, and keep the shadow from the live frame.
  - This frees the camera to go low, elevation 15–20°, looking into the mouth past the lid's free edge.
  - It's the only way to get "a duck being crushed between two plates" seen side-on.
  - Not needed for launch if A–C land.

**E. Captions as App Store frames. S.** Draw them in the renderer (option `caption`), not in Figma, so CI can regenerate every locale.
- Text from screenshots.md §A: "Close your phone. Feel it *give*." / "Every bubble *pops* on its own." / "It creaks. Then it *doesn't*." / "Open up. File the *evidence*."
- The caption band (top 21 %) must not overlap the lid's top edge. With the anchor at bottom 3 % and a 0.76-high box it doesn't.

**F. Device fidelity. S.** Before upload, replace the slab with Apple's iPhone Duo product bezel from Apple Design Resources, if one ships. Otherwise at least match the real corner radius and hinge from photos. Until then keep the device dark and matte, so its shape doesn't compete with the screens.

**Don't:** use the 18 Pro 9A–9C shots in any set. The 18 Pro doesn't fold, so showing it folded in the 6.9" set misrepresents the app (Guideline 2.3). The 6.9" set stays Pinch Press (screenshots.md §C).

---

## 4. New issues, ranked by impact on "worth paying for"

### F1. The Duo's store shot is book pose: the duck is wall-mounted — **M**
- **Frames:** `rubberDuck-storeshot-120`, `-120-eye`, `-75`, `-75-eye`.
- **Problem:** in a third-person view the anvil page is vertical, so the anamorphic duck (whose up is the page normal) points sideways out of a wall. E1 and E2 fail on the composite. The tabletop composites from the 18 Pro (`9B`, `9C`) pass E2.
- **Fix:**
  - Portrait (tabletop) pass in `ci/duo-screenshots.sh`: rotate to portrait before setting angles, with its own `STORESHOT_ANGLES="115 62"`.
  - Keep book as a CI artefact only.
  - No app change needed (`StoreRig.init`, FoldStoreShot.swift:618–631).
  - Then judge the Duo tabletop eye composite against §12 E1/E2 at 120/90/60.

### F2. Store-shot framing wastes 37–45 % of the frame — **S**
- **Frames:** all store shots.
- **Problem:** hero box `(0.07, 0.32, 0.86, 0.56)` plus `min` fit plus centring (FoldStoreShot.swift:224–236, `StoreFit` l.842–850). The device is 34–47 % of the height with empty beige above it. The size is 6.9" only (l.27), not the Duo slot.
- **Fix:** §3.3 B: `.width(bleed: 0.05)` fit, box `(0.04, 0.21, 0.92, 0.76)`, bottom anchor, `duoInner` / `duoInnerLandscape` / `duoOuter` sizes, caption band.

### F3. No visible squish in any store shot — **S/M**
- **Frames:** `9B-120` (kiss on a lid 5 cm away), `9C-60` (pancake under a hovering lid).
- **Problem:** the virtual gap reads as "nothing touching". Without a sequence or caption a buyer sees a duck in a box.
- **Fix:** §3.3 C: hero at the failure freeze, a diptych frame, captions, and real escaped-splat droplets on the anvil field.
  - Droplets: add a sprite set to the anvil side of the failure event. The platen's are in FoldStamps.swift:612 (`droplets(…)`); mirror their seeds onto anvil-field decals in `FoldAnvil`.

### F4. The achievement toast lives on the crown forever — **S**
- **Frames:** `*-reveal` ×4 (x 190–940 px, y 40–145 px), `ci/99`.
- **Problem:** it covers the READY lamp and the hinge readout, the two things that should go green and freeze at the reveal. It's in every reveal screenshot.
- **Fix:**
  - In fold layouts, auto-dismiss after 3.0 s (RevealCardView.swift:376–384: drop "the last one stays").
  - Move the slot from the crown (l.151–153) into the **empty graphite band at the foot of the platen page** (`layout.platenFoot`, FoldGeometry.swift:193–199, book only; in tabletop, use the console), which also fixes part of N16.
  - Add a `-squishDemo …;notoasts` flag for store capture.

### F5. Glass pile: teal rectangles with polka dots around a hole — **M**
- **Frames:** `glassBottle-75/60/45/reveal`.
- **Problem, in code (GlassBottleView.swift):**
  - Shards are lathe sectors, so they're rectangles.
  - Placement `centre + dir·reach·0.55` with `reach ≥ 0.6·footprint·(…)` (l.355, l.361) leaves the middle empty.
  - Every shard shows a static white sparkle (l.370).
  - Only 3 label scraps survive, so the pile has lost the bottle's pink/cream identity while the print shows the whole bottle.
- **Fix:**
  - Radius `footprint · 1.1 · √U(0,1)` (fills the disc).
  - Split each sector quad along a jittered diagonal into two irregular pieces (≈ 100 pieces, 3–9 mm).
  - Sparkles: 4 only, animated twinkle and then off by the reveal.
  - 8–10 label scraps (6 pink, 4 cream) at 70 % size, on top of the pile.
  - Tint shards 20 % toward `#8FE0D3` with a 1 px bright edge, so they read as glass, not paper.

### F6. The duck's head is a ball on a pancake — **S/M**
- **Frames:** `rubberDuck-90/60/45/reveal`, `ci/93`, `9C-60`.
- **Problem:** `squash.scale = SIMD3(spread, s·deflate, spread)` (DuckView.swift:141–143) scales the whole duck. Top-down, the head stays a perfect sphere, so the reveal reads as "melting duck wearing a ball", not "pressed flat".
- **Fix:** give the head its own transform under `squash`:
  - XZ × (1 + 0.6·c), Y × (1 − 0.75·c), slid 4 mm forward × c.
  - Beak flattens to an ellipse (Y × 0.5).
  - Clearcoat roughness 0.05 → 0.3 with c.
  - A darker wet ring (`#C99A00` at 0.35) on the steel at the skirt edge.

### F7. Can lid creases read as clock hands — **S**
- **Frames:** `sodaCan-60/45/reveal`.
- **Problem:** three straight 16 × 2.2 mm black bars at r 26 mm on the lid (SodaCanView.swift:323–331, `creaseRadius` l.361), plus the tab, make a clock face.
- **Fix:**
  - Move the creases to the shoulder/rim (r ≥ 0.036).
  - Draw them as short chevrons (two 6 mm bars at ±35°).
  - Use dark grey `#5A5E66` at 0.6, not black.
  - Make them 2 per buckle, so "5 BUCKLES" gives 10 marks.
  - Or drop them: the crumple ring already sells it.

### F8. Bubble wrap is still the weakest object — **S**
- **Frames:** `bubbleWrap-150` (box shadow), `-180` (no shadow; white film, plate L 229 vs 192), `-90/reveal` (diagram print, grey craters).
- **Fix:** the R3 N9 and N15 fixes, unchanged: FoldStamps.swift:142–151, `BubbleWrapView.pop`, and the platen shadow layer in FoldPlaten.swift. Also drop the film's base colour by 6 %, so it isn't the brightest thing at 180.

### F9. PRESSED stamp still covers the print in the same place — **S**
- **Frames:** all reveals.
- **Fix:** in `pressedPose` (FoldPlaten.swift:598–605), choose the base from the print's bounding box: the plate corner with the most free area, tilt −8° ± 10°, ±30 pt. Use paper-white ink with a red outline when the print hue is within 30° of stamp red (jelly).

### F10. Cover and console unchanged — **S**
- **Frames:** `*-closed`; every pressing frame.
- **Fix:** as R3 N16.
  - Centre the card horizontally in the free area (it is 220 px left of centre).
  - Scale it to 80 % width.
  - Use the print thumbnail as the teaser. The platen has it: `printImage()`, FoldPlaten.swift:618.

### F11. App icon is the category's stock look — **M**
- As R3 N17 (`UI/AppIconArt.swift`). The tabletop composite at 60° *is* the icon idea: a dark clamshell, yellow splat squeezing out of the mouth, hazard stripes on the free edges.

### F12. The two machines disagree — **S**
- **Frames:** `ci/34` (P-48 gauge 0–60, "P-48" plate) vs every Duo frame (0/40/80, live angle).
- **Fix:** one tonnage scale (0/40/80) in the P-48 gauge too. That machine lives in PressScene and the P-48 rig; the face can reuse `FoldTextures` gauge face.

### F13. Reveal caption ends in a bare angle — **S**
- **Fix:** "· 66°" → "· AT 66°" (RevealCardView `printLabel`). One word, and the number explains itself.

### F14. Jelly reveal leftovers — **S**
- **Frame:** `ci/99`. Still overflows the plate by ~60 px on both sides, still has the vertical shading seam (x ≈ 440 px), and PRESSED is lost in magenta. Fold this into F9 and the JellyView spread cap.

---

## 5. Top 5 fixes, in order

1. **Duo tabletop store shot** (F1 + F2; `ci/duo-screenshots.sh` portrait pass; `FoldStoreShot.Options` per §3.3 B: Duo sizes, width fit with 5 % bleed, box (0.04, 0.21, 0.92, 0.76), bottom anchor, azimuth 14°, elevation 34°, captions). This turns the one image that already works into a Duo image at 58 % frame fill. **M, +0.3 on the rubric, and by far the largest effect on whether anyone pays.**
2. **Hero = the squish moment, plus a diptych and real escaped splat** (F3; `watchStoreShots` capture at the failure freeze, anvil-field droplets mirrored from FoldStamps.swift:612). **S/M, +0.2.**
3. **Glass pile that reads as glass** (F5; GlassBottleView l.355/361/370, more label scraps, split sectors). It's the screenshot-4 object and the worst-looking family. **M, +0.25.**
4. **Hero-object tells: duck head squash and can creases** (F6 + F7; DuckView.swift:141–143, SodaCanView.swift:323–331/361). **S/M, +0.2.**
5. **Toast off the crown, plus the quick UI batch** (F4 + F9 + F13 + F10; RevealCardView.swift:151–153 and 376–384, FoldPlaten.swift:598–605, CoverView.swift:206–224, `notoasts` demo flag). **S, +0.2.**

**Quick wins to batch (all S):** bubble print and shadows (F8), one gauge scale (F12), jelly (F14), sheen alpha 0.04.

**Projection:** top 5 + quick wins → **~8.2–8.4**. The remaining gap to 9 is the icon (F11), F-3D if the founder wants a side-on "into the fold" hero, and the device checks below.

---

## 6. Only a real device, or a real photo or video, can settle these

1. **Does the pop-up illusion work in a hand?** Every E check so far is a render of our own model of the eye. On hardware:
   - Does the book-pose duck look like it stands out of the right page at 320 mm?
   - Does the tabletop duck stand at 380 mm / 40°?
   - How far off-axis (head movement ±10 cm) before it collapses?
   - With hinge accuracy at ~5°, does the eye model jitter visibly?
2. **Does closing feel like pressing?** The haptics, the ka-chunk at seal, and the stiffness of the real hinge against the strain curve. No render can show this, and it's the actual product.
3. **The display-off window (55–20°) and reopen hysteresis to ~150°.** Does the reveal land on the right frame on real hardware, and does the cover card appear before the user looks?
4. **Brightness and tone in daylight.** Whether 210 L cream on both halves holds up, or looks grey on a bright OLED, and how the crease band and real bezel look next to our 40 pt graphite.
5. **Thermals at 120 Hz** with the 1.15× oversampled anvil, during a slow 30 s press.
6. **What the real Duo looks like.** The store-shot slab is a guess: corner radius, hinge barrel, thickness, bezel.

**Should App Store marketing rely on a real hand-held Duo video from the founder? For everything off the product page, yes. On the product page, only partly.**
- **App Previews** (the autoplay video slot) must be **screen captures of the app** (App Review Guideline 2.3.4). A hand-held video can't go there.
  - A Duo App Preview would be the raw inner display, i.e. the "two flat trays" look. Keep previews out of the Duo set until a composite or device video is confirmed acceptable, or use only the 6.9" Pinch Press preview.
- **Screenshots:** one real photo of a Duo in tabletop pose, closing on the duck, with the real UI on screen, is allowed as long as it shows the app in use.
  - It would probably out-sell any render as frame 1.
  - It contradicts screenshots.md's "no hands, no device photos" rule. Revisit that rule: it was written before we knew the raw frames can't carry the idea.
  - Shoot it at 62° and 112°, on a neutral sweep matching `#F3EEE6`, with a locked-off camera at ~35° elevation (the store shot's eye).
- **Everywhere else** (TikTok/Reels/Shorts, the website, the press kit, the Apple featuring pitch, the launch tweet): the founder's 10-second real clip is the marketing. Show a hand closing the phone, a pause, opening it, and the specimen. That shot proves the hook in one view and no render can.
- **What the renders are still needed for:**
  - Exact-pixel screenshots for every required slot (Duo inner 2007 × 2853, Duo outer 1398 × 2034, 6.9" and 6.5"), regenerated per object and per locale in CI with captions.
  - The §12 E1/E2 regression checks on every build (the `-eye` composite).
  - The share card and clip (already non-anamorphic).
  - Stand-ins until hardware arrives.
  - Matching the photo's framing, so the set looks like one system.
