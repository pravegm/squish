# Fold Review 9: the package tells the truth now

*Design critic pass 9, 23 Oct 2026. Inputs (all viewed):*
- *`r9/store-duo/duo-screens/store/`: inner `01–07` (2007 × 2853) and outer `O1, O2` (1398 × 2034), plus `MANIFEST.txt` (missing 0, flagged 0, 32 checks), `logs/ui-checks.txt` and `logs/reveal-checks.txt`.*
- *`r9/store-69/store/P1–P5` (1320 × 2868) and `r9/store-61/store/P2, P4, P5` (1206 × 2622), with both MANIFESTs (flagged 0, 15 checks each).*
- *Verify: `verify/egg-tabletop-reveal`, `-62`, `duo-reveal-toasts` and `VERIFY.txt`.*
- *Raw frames: `cakeSlice-tabletop-reveal`, `cakeSlice-tabletop-75`, `glassBottle-tabletop-90`.*
- *Logs: `run.txt`, `duo-settings.txt`, `duo-shelf.txt`, `verify-toasts.txt`.*
- *For comparison: R8 `store-61/P2`.*
- *Repo at `a3d41d5` (round 9 is `9716692`). The icon is unchanged since `b266414`.*

*Coordinates are display px at the downscale noted (inner frames 0.70×, so multiply by 1.43 for file px).*

**Not in the package:** the brief mentions "raw P/V4 frames", but there is no V4 (glass-crack check) file under `store-69` or `store-61`. So the P-48 crack is **unverified** (§4 N7).

---

## 1. Verdict

| | Score | R8 |
|---|---|---|
| **Store set, as an App Store submission** | **8.6 / 10** | 8.2 |
| **App experience, as seen in the frames and logs** | **8.7 / 10** | 8.5 |

**Store set, in one line:** both lying frames are fixed. `06` is a shelf of real prints at believable angles, and `07` is a full portrait sheet, so all 14 frames are now true. What's left is polish: one caption over-promises ("No purchases." on a £2.99 app), and the Shelf's hero can is orange when every other can in the set is green.

**App, in one line:** the R8 app gaps closed:
- a missing thumbnail now shows a print, never an intact object;
- a real square-thumbnail crop bug is gone;
- the glass shows dark crack stars as it loads;
- the cake ends as a splat, not a wedge;
- the egg finally reads: a fried egg in shell shards, failing early at 94°.

The cake still blows out to white at c = 1, and toasts are unseen for the ninth round.

**Would a stranger pay £2.99?**
- **A Duo owner: yes.** Frames 01 → 02 → 03 are the sale, and 06 now pays off "File the evidence" with an actual evidence shelf.
- **A regular-iPhone buyer: yes, on P1–P2.** The five-frame iPhone set has no dead frame left.
- The ceiling is where R8 said it was. Past ~8.7 needs a real device in a real hand for frame 1, and code can't buy that.

### Store-set scoring (weights as R1–R8)

| Dimension | Weight | Score | R8 | Why |
|---|---|---|---|---|
| Composition | 2.0 | **1.75** | 1.7 | **Up:** `07` fills its portrait device, `06` fills its sheet, and `01`'s base corner now clears x 0 (≈ 43 px inset). **Still weak:** the floors in `01` and `04` are ~15–18 %. `O2`'s content sits left of centre, with its right screws floating mid-panel (§4 N5). The P2 card photo has the duck low and clipped (§4 N4) |
| Light and material | 3.0 | **2.45** | 2.4 | **Up:** the cake is now a flattened round splat with filling blobs, not an intact wedge (`05`, raw `-reveal`). The egg is excellent. The glass shows dark crack stars mid-press (raw `-90`). **Still weak:** the cake's top still clips to flat white at c = 1, and its sponge band (visible at 76°) disappears |
| Colour and tone | 2.0 | **1.75** | 1.7 | The Shelf strip adds orange, pink, yellow, blue and magenta prints, and it reads as one family. **But** the biggest tile in `06` (and the first tile in O2) is an **orange** soda print, while `02`, `05` and P3 sell green FIZZO (§4 N2) |
| UI truthfulness | 2.0 | **1.75** | 1.55 | **Up:** prints, not icons. Seeded angles are 67–94°, which matches the press maths, and the 94° egg and 89° crayon are honestly early. `07` is the real sheet. **Down:** P5's headline says "No purchases." on a paid app; the app's own copy says "No in-app purchases" (§4 N1) |
| Story and delight | 1.0 | **0.9** | 0.85 | On the Duo: gesture → lever → payoff → peril → variety → collection → care. On the iPhone: P1 → P2 → P3 → P4 → P5, with no filler |

Weighted: 1.75 + 2.45 + 1.75 + 1.75 + 0.9 = **8.6**.

### App experience (8.7)

**Up:**
- **The pressed-tile fallback** (Theme.swift:935–991, `PressedTile` via `SpecimenPrint.card`). A specimen whose thumbnail write fails now shows its own print, rebuilt from the record. This protects real users, not just screenshots.
- **The square-thumbnail crop fix** (round-9 commit). The Shelf tiles in `06` and P4 show whole prints, unrotated.
- **The glass crack reads while it happens** (raw `glassBottle-tabletop-90`). There are two dark-cored stars on the camera-facing barrel, plus crack lines in the lid print. It is now a sequence: creak, star, shatter.
- **The cake squashes.** At 76° (raw `-75`) the slice shades properly, with sponge, cream band and sprinkles. At the reveal it is a round, spread disc with pink filling squeezed out, and the candle lies flat. The wedge's point is gone.
- **The egg, seen for the first time since R7.**
  - The anvil shows a fried egg: domed yolk, white puddle and real shell shards.
  - The lid print is a sunny-side-up stamp.
  - "EGG · SHELL BREACHED · AT 94°" is the right joke.
- **Orientation is now checked against the window and screen bounds:** `orient portrait ok … layout=none interface=1 window=669x951 screen=669x951` (`duo-settings.txt`). The settings frame launches before the cover pass (`run.txt:569–579`).

**Held back:**
- At c = 1 the cake's top is still a flat, clipped white with no form shading.
- Toasts are still unverified. The R9 shot fired after the toast had gone; per the brief this is a capture bug fixed in `a3d41d5`, not an app defect.

---

## 2. Status of FOLD-REVIEW-8 items

### The four launch blockers

| R8 blocker | Status | Evidence (R9) |
|---|---|---|
| **N1:** `07` portrait capture, with a source-size guard | **Fixed** | `07` is a full portrait sheet: Sound / Sound style SOFT / Haptics FULL / Captions / Press without folding ON / Reduce Motion / About. There is no black half. `ui-checks.txt`: `duo-settings ok 2007x2853`. The log shows window and screen bounds both 669 × 951. DUO_UI now runs shelf → settings → cover (`run.txt:558–579`) |
| **N2:** prints in "Recently squished"; pressed-tile fallback; plausible angles | **Fixed** | `06` strip: Soda Can AT 73°, Cake Slice AT 67°, Egg AT 94° (Golden frame), Crayon AT 89°, Jelly AT 75°, each with its own print. `seedDemo` attaches `SpecimenPrint.printImage` → `cardImage` (CollectionStore.swift:427–448), and the angles come from `SpecimenPrint.failureAngle`. O2's recent tiles are prints too |
| **A truly green store run, with 06 and 07 eyeballed** | **Fixed** | 62 checks, 0 missing, 0 flagged. I eyeballed `06` and `07`: both pass their own MANIFEST criteria ("prints, not intact objects"; "no black half, no letterbox") |
| **Upload the iPhone sets without the crack frame** | **Fixed** | Both sets are P1–P5 (duck mid, duck reveal, can buckle, shelf, settings). The crack frame moved to V4, and the MANIFEST says "Upload set: P1-P5 only" |

### Everything else

| # | R8 item | Status | Evidence (R9) |
|---|---|---|---|
| N3 | Glass crack invisible | **Fixed on the Duo; unverified on P-48** | The stars read clearly on the Duo barrel (raw `-90`, x ≈ 500–560, y ≈ 1290–1490). The V4 frame isn't in the package, so P4's crack frame stays out of 1.0 |
| N4 | Cake doesn't read as crushed | **Mostly fixed** | Outline spread, point lost, filling squeezed out. The cream still clips to white at c = 1, and the sponge band vanishes (§4 N3) |
| N5 | `01` corner clip | **Fixed** | The base's front-left corner is inset ≈ 30 display px |
| N6 | P-frame content check can't see pixels | **Fixed by the "accept and say so" option** | Both MANIFESTs say the check reads the log, not the picture, and require eyeballing every frame |
| N7 | Toasts never verified | **Still unverified (9 rounds)** | `verify/duo-reveal-toasts.png` has no toast. Known capture-timing bug, fixed in `a3d41d5` ("shoot on the app's 'toast shown' line"). **Not an app defect; still unseen** |
| N7 | Egg never seen | **Verified** | `verify/egg-tabletop-reveal`: yolk, white and shell shards on the anvil, and a sunny-side print on the lid. Good |
| N8 | Icon hash assert | **Not done** | ci/screenshots.sh:301–344 still only exports. Minor |
| N8 | Icon composition (top ~18 % dark) | **Unchanged, accepted** | Still reads as a duck in the fold at 60 px |
| N8 | Can tile reads as a jar | **Moot** | Pressed objects now show prints. The intact tile only appears for unpressed kinds, and the can isn't one in the demo |
| R8 §1 | 07 letterbox, hardware twin | **Open (hardware)** | `duo-shelf.txt` still logs `orient request error: … Supported: landscapeLeft` and `orient portrait lost at 12.55s … re-requesting`, with no second "ok" before the capture (§4 N6) |

### R8 top 5

| # | R8 top-5 | Status |
|---|---|---|
| 1 | Re-shoot `07` behind a real orientation check | **Done** |
| 2 | Prints, not icons, in "Recently squished" and on the cover | **Done** |
| 3 | Upload without P4; fix the crack for 1.0.1 | **Done** (cut). The crack is fixed on the Duo; P-48 is unverified |
| 4 | Crush the cake | **Mostly done** |
| 5 | Toast-on and egg frames; `01` corner | **Egg and corner done; toast still unseen** (capture fix landed after the run) |

---

## 3. Frame-by-frame verdict

**Rules applied:**
- Guideline 2.3: show only what the app renders.
- No prices.
- Headline legible at thumbnail size.
- Frames 1–3 must each sell alone.

**Guideline status:** no prices anywhere; no folded device outside the Duo set; every caption is legible at 25 %. One caption is inaccurate (P5, §4 N1).

### A. iPhone Duo inner (2007 × 2853)

| # | Frame | Verdict | Notes |
|---|---|---|---|
| **01** | Duck hero, "Close your phone. Feel it give." | **SHIP** | AT 65°, the lid print, the flattened duck. The corner now clears the frame. The floor is ~18 % (y ≈ 1640–2000); acceptable |
| **02** | Can pair, "The hinge is the lever." | **SHIP** | 111° → AT 72°, green FIZZO, a ring print with radial creases. Clean separation |
| **03** | Duck reveal, "Open up. File the evidence." | **SHIP** | Still the best image in the set. PRESSED, NEW BEST, "RUBBER DUCK · 1 HONK · 1 SEAM POP · AT 65°" |
| **04** | Glass hero, "It creaks. Then it doesn't." | **SHIP** | AT 82°, a cracked-glass lid print, a shard heap around the base ring. The headline is now backed by the app (the stars mid-press), even though this frame shows the after |
| **05** | Variety, "Ten objects. Ten ways to give." | **SHIP** | The cake cell finally reads as squashed (a round disc, a pink print). It's still the whitest cell. The labels match the readouts (82 / 72 / 67 / 70) |
| **06** | Shelf, "A shelf of pressed specimens." | **SHIP** (optional re-shoot, §4 N2) | Fixed. The grid is above the crease, the strip is below, and every tile is a print. The Golden egg is foil-framed and the ??? slot is there. **Nits:** the hero Soda Can print is orange/brass, not the set's green. "ON THE ANVIL" covers the Rubber Duck's grid thumbnail, the mascot's own tile (§4 N9) |
| **07** | Settings, "Press without folding. Hear it softer." | **SHIP** | Fixed. Full portrait, and the caption's three claims (Press without folding ON, SOFT, accessibility) are all visible. Ends at "Golden variants · 1 IN 50", which is fine as a scroll cut |

### B. iPhone Duo outer (1398 × 2034)

| # | Frame | Verdict | Notes |
|---|---|---|---|
| **O1** | Sealed, "Ka-chunk. Now open it." | **SHIP** | PRESS SEALED, the duck print, 55 TONS, OPEN TO SEE. The bottom ~25 % is empty graphite, as in R8 |
| **O2** | Idle cover picker, "Pick on the cover. Press inside." | **SHIP** (polish, §4 N5) | Recent tiles are prints now. The content column sits left of centre: ~50 display px left gutter vs ~210 right. The right-hand screws float inside the panel rather than at its edge. Acceptable for 1.0 |

### C. iPhone 6.9" and 6.1": identical verdicts

| # | Frame | Verdict | Notes |
|---|---|---|---|
| **P1** | Duck mid-press, "Drag it down. Feel it give." | **SHIP** | Unchanged; good |
| **P2** | Duck reveal, "Open up. File the evidence." | **SHIP** (polish, §4 N4) | "CRUSHED AT 56 TONS · He'll be fine. Probably." still lands. The card photo is the same as R8: the top ~35 % is empty backdrop, the duck is clipped at the right (its beak is lost on 6.1"), and the PRESSED stamp sits on its second eye. I missed this in R7 and R8 |
| **P3** | Can buckle, "Cans buckle ring by ring." | **SHIP** | Unchanged |
| **P4** | Shelf, "Collect every pressed specimen." | **SHIP** | Two large print cards (bubble wrap, duck) with the ON THE ANVIL sticker. Now truthful |
| **P5** | Settings, "No ads. No purchases. Just the press." | **FIX before upload (S)** | The sheet itself is fine: "Press by dragging · ALWAYS ON · On iPhone Duo you can also press by folding" and a clean Reduce Motion break. **But** "No purchases." is false for a £2.99 app; you purchase it. The app (SettingsView.swift:115), metadata.md:50 and `06` all say "No in-app purchases." Make P5 match (§4 N1). If the re-run can't happen, ship as is; it's unlikely to be rejected, but it is the one inaccurate line in the package |

**Never upload:**
- anything under `verify/`;
- V4, `*-eye`, `*-112` and raw `*-tabletop-*` frames;
- any `*-storeshot-hero` other than duck and glass.

---

## 4. New issues, ranked

### N1. P5 says "No purchases." on a paid app — **S**, fix before upload
- **File:** `ci/scenarios.txt:111` (and the copy in `docs/appstore/screenshots.md:88`; the wrap examples in `ci/store-frame.swift:128` and `FoldStoreShot.swift:1768` are comments).
- **Fix:** `No ads. No in-app purchases. / *Just* the press.` with the sub-line unchanged. If three lines don't fit at 6.1", use `No ads. No IAP.`, but the full words are better. Then re-run the iPhone store job (both sizes) and eyeball P5.
- **Why it matters:** every other surface already says "in-app". This is the one claim in the package a buyer could call untrue.

### N2. The Shelf's hero can is orange; the set's can is green — **S**, optional
- **Frames:** `06` (the big "Soda Can · №0007" tile, x ≈ 265–725 / y ≈ 1310–1770) and O2's first recent tile.
- **Cause:** `demoSeed` (CollectionStore.swift:451–460) only filters golden/surprise, so the seeded can got a non-green fizz (`FoldStamps.canFizz(variant)`, FoldStamps.swift:285–288). At shelf size the amber disc reads like a brass coin or an orange slice, not "the FIZZO can from frame 02".
- **Fix:** for `.sodaCan`, also require the seed's fizz to equal the green the hinge storeshots use (`02`'s seed). Then re-shoot `06` and O2. Truthful either way; this is about recognition.

### N3. Cake reveal still clips to white — **M**, 1.0.1
- **Frames:** `05` (cake cell), raw `cakeSlice-tabletop-reveal` (y ≈ 1250–1650).
- **Problem:**
  - At 76° the cake shades well, and the sponge and cream bands show (raw `-75`).
  - At c = 1 the spread top covers the whole disc in unshaded white, the sponge band disappears, and most sprinkles go.
  - It reads as "squashed meringue" more than "crushed cake".
- **Fix:**
  - In CakeSliceView.swift, keep a sponge band visible at the rim at full compression (let the side layers bulge outward past the top's edge).
  - Take the top's albedo down another step at high c.
  - Add a crease/AO term where the top folds.

### N4. P2 reveal-card photo is framed low and clipped — **S/M**, 1.0.1
- **Frames:** P2 at both sizes. Unchanged since R8, and I missed it there.
- **Problem:** the photo's top ~35 % is empty backdrop, the duck is cut at the right edge (6.1" loses the beak), and the stamp lands on an eye.
- **Cause:** in `.reveal` style, `SpecimenCardView.renderArea` (SpecimenCardView.swift:70–71) gives a wide frame, and `SpecimenImage` (Theme.swift:944–952) `scaledToFill`s the square snapshot into it, centred. But the specimen sits low and right in the P-48 snapshot.
- **Fix:** either aim the P-48 specimen snapshot at the object's projected bounds, or align the fill to the subject (e.g. `.overlay(alignment: .bottom)` plus a small y-offset for touch-press specimens). Then nudge the stamp's offset so it clears the face. This is what every non-Duo user sees after every press.

### N5. The cover's idle picker isn't centred — **S**, check on hardware first
- **Frame:** O2.
- **Cause:** `CoverView.idle` (CoverView.swift:75–92) centres in the safe area. `sealed` (l.53–73) was moved to the whole display in FOLD-REVIEW-3 N16 for this exact reason. The screws (l.172–178) also follow the safe area, so on the right they sit ~190 display px inside the panel edge.
- **Fix:** centre `idle` on the full width as `sealed` does, capping the width so the chip grid still clears the outer display's clock column, and lay the screws on full bounds.
- **Hardware:** confirm what actually occupies that right column on the real outer display before moving anything into it.

### N6. Orientation still churns during captures — **S**, process (hardware twin open)
- **Log:** `duo-shelf.txt`. First `orient request error: None of the requested orientations are supported … Supported: landscapeLeft`. Then `ok at 11.23s … requests=3`, then `orient portrait lost at 12.55s interface=4 window=951x669 … re-requesting`, with no later "ok". The capture still came out portrait and correct (the source-size check passed), so the frame is fine. But the run captured without a re-confirmed "ok".
- **Fix:** in `ci/duo-screenshots.sh`, after any `orient portrait lost`, wait for a fresh `ok` before capturing, or flag the frame.
- **App side:** log which view controller reported `landscapeLeft` only. If it's a presented sheet's host, that is the real-device letterbox risk from R8 N1.

### N7. V4 is missing from the package — **S**, process
- The P-48 crack fix (two stars "facing the Duo and P-48 cameras") can't be judged without it. P4's crack frame stays out of 1.0 anyway; include V4 in the next run's artefacts so it can come back in 1.0.1.

### N8. Toast slot still unseen — **S to verify**
- No change from R8 N7, except that the capture fix (`a3d41d5`) is now in. One Duo verify run closes it.
- Do this before pressing Submit; it is the most visible moment in the app, and its timing changed in R8.

### N9. Minor
- **`06`:** the ON THE ANVIL sticker covers the Rubber Duck's grid thumbnail, which is the mascot's own tile. Anchor it lower, over the label band (ShelfView.swift, the anvil sticker overlay), or pick another object as current in the demo.
- **Egg print:** the white spills past the strike plate's bottom edge, and a tan arc (shell ink) peeks out at its right (`verify/egg-tabletop-reveal`, x ≈ 850–900 / y ≈ 350–470 and y ≈ 730–760). Harmless; tidy if you're in FoldStamps.
- **Icon hash assert:** still missing (R7, R8).

---

## 5. Launch-readiness call

**Can the code/art side be submitted as 1.0 now? Yes.**

Every R8 blocker is closed and verified in the frames, not just the manifest. All 14 frames to upload are true to the app. The binary was already ready in R8, and round 9 only made it safer: the pressed-tile fallback and the thumbnail crop fix are real-user wins. Nothing below is a blocker.

### Do before you press Submit (hours, not days; not blockers)

- [ ] **N1:** change P5's caption to "No in-app purchases", re-run the iPhone store job, eyeball P5. If skipped, the set still ships, but this is the one inaccurate line.
- [ ] **N8:** one Duo verify run with the `a3d41d5` capture fix, then look at the toast frame. A toast on a dark panel, or no toast at all, would be a real bug.
- [ ] Upload exactly:
  - Duo inner **01–07**;
  - Duo outer **O1–O2**;
  - iPhone 6.9" and 6.1" **P1–P5**.

### 1.0.1 list

N2 (green hero can), N3 (cake reveal shading), N4 (P2 card framing), N5 (cover centring), N6 and N7 (capture hygiene, V4 in artefacts, then restore the crack frame), N9.

### Only the founder can do

- [ ] Sign off every caption and the final frame list above.
- [ ] Frame 1 likeness: accept the 3/4 render as "app in use", or shoot one real-device photo or video. This is still the only lever above ~8.7.
- [ ] Fill the placeholders:
  - metadata.md: `[Studio legal name]` and the support, marketing and privacy URLs;
  - privacy-policy.md, support.md and press-kit.md.
- [ ] Stand up the domain (`/privacy`, `/support`, `/press`).
- [ ] Pick the release date.
- [ ] Enrol in the Small Business Program.
- [ ] Create the 10 Game Center achievements in App Store Connect, with IDs matching `achievements.md` exactly.
- [ ] Subtitle choice: the £ joke (2.3.7 risk) or "The priciest hydraulic press".
- [ ] App Review notes: explain Pinch Press and "Press without folding" for non-Duo reviewers, and give θ_end as measured on hardware.
- [ ] Accessibility Nutrition Labels: declare only what's been tested.
- [ ] App Preview: none in the Duo slot, or a 6.9" drag-press capture only.
- [ ] Check whether App Store Connect offers the Duo inner and outer slots. If not, ship the iPhone sets and add the Duo sets by metadata edit.

### Only real hardware can settle

- [ ] Display-off angle versus `endAngle` 48°. The simulator lit at 55.7° (`reveal lit at 55.7° after 1.68s (dark at 18.5°)`). Confirm that the reveal card and the toast are up when the real panel lights.
- [ ] The `closed` flag sticking above 90° (`staleClosedAngle = 90`): test a slow reopen and a slam.
- [ ] Render pause: battery and thermals with the phone shut on the cover for 10 minutes. Also 120 Hz on the warped anvil during a 30 s press.
- [ ] Cold launch on the cover: idle picker, no seal. Check what sits in the outer display's right column before acting on N5.
- [ ] Settings and Shelf in book pose: never letterboxed (N6's `Supported: landscapeLeft` is the reason to look).
- [ ] Anamorphic duck at the design eye with ±10 cm of head movement; ka-chunk and haptics against real hinge stiffness; OLED tone of the cake's cream and the plate in daylight.
- [ ] Share clip render time and encoder on device.

---

## 6. What would raise it further, honestly

1. **A real Duo in a real hand for frame 1** (photo, or a 15 s App Preview of close → ka-chunk → open). It's the only thing left that moves the set meaningfully (≈ +0.3), because every render, however good, reads as a small laptop shape at search size. Founder only.
2. **N1 + N2:** one honest caption and one green can. They're cheap; **set +0.05–0.1**.
3. **N4, the P2 card framing.** That card is the payoff every iPhone user sees after every press, and right now it crops the duck's face. **App +0.05, set +0.05.**
4. **N3, the cake at c = 1.** A visible sponge band and shaded cream would finish the last weak object. **App +0.05.**
5. **Bring the crack frame back** once V4 shows the stars on the P-48: "It creaks. Then it doesn't." would then sell on the iPhone too (a sixth iPhone frame). **Set +0.05.**

**Projection:**
- **Set:** 8.6 → **~8.7** with 2–5, and **~9.0** only with a real-device frame 1.
- **App:** 8.7 → **~8.85** with 3–4 and a verified toast.

Above that is content (more objects, more surprises), not polish.
