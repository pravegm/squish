# Fold Review 6: the first complete App Store set

*Design critic pass 6, 23 Oct 2026. Inputs (all viewed):*
- *`r6/store-duo/duo-screens/store/`: inner `01`–`07` (2007 × 2853), outer `O1`, `O2` (1398 × 2034), `MANIFEST.txt`.*
- *`r6/store-69/store/P1–P6` (1320 × 2868) and `r6/store-61/store/P1–P6` (1206 × 2622), plus the raw `P1`/`P3` frames.*
- *Sources: `<obj>-storeshot-hero/-pair/-reveal` for duck, glass, can, egg, cake; raw `*-tabletop-62/-reveal`, `duo-shelf`, `duo-settings`, `duo-cover-launch`, `egg-tabletop-reveal`; `logs/run.txt` and the per-object logs.*
- *This run had no book pass, so there are no book-pose frames to judge (bubble wrap only appears in `P2`).*

*Coordinates are px of the file as named. The ≤ 1° crown-readout vs "AT nn°" mismatch is fixed after this run and is not counted.*

---

## 1. Verdict

| | Score | R5 |
|---|---|---|
| **Store set, as an App Store submission** | **7.0 / 10** | (7.6 was the app + best-available frames) |
| **App experience, as seen in the raw frames** | **7.8 / 10** | 7.6 |

**Would a stranger scrolling the App Store pay £2.99 on this set? Not on the Duo set as assembled. Probably yes on a trimmed 6.9" set.** This is the first round where a full set exists, the numbers agree, and the per-object captions are right. But:
- 4 of the 17 unique frames have to be cut or re-shot before upload (`05`, `O2`, `07`, `P2`).
- Frame 1 still sells "a duck in an open laptop", not "a phone closing on a duck".
- The run surfaced **two real app bugs** that would ship to customers: the reveal can be dismissed by a stray `closed` sample (it ate the glass and cake reveals), and launching the app with the phone shut seals a phantom press (that's what `O2` shows).

**The best image in the set is now `04-reveal-duck`, not the hero.** At ~151° the device reads instantly as a foldable phone. The flattened duck, the PRESSED print with "RUBBER DUCK · 1 HONK · 1 SEAM POP · AT 67°" and the Again · Share · Next console are the whole product in one picture. It belongs in the first three.

**The 6.9" set is the healthier of the two.** `P1` (duck bulging under the ram), `P4` (specimen card, "CRUSHED AT 56 TONS") and `P3` (green FIZZO can buckling) all sell a toy at thumbnail size. `P2` is an empty press.

### Store-set scoring (weights as R1–R5)

| Dimension | Weight | Score | Why |
|---|---|---|---|
| Composition | 2.0 | **1.5** | Pair, reveal and O1 are well built. But `01` and `03` are the same device in the same pose and framing, so 2 of the 3 search-result frames look like one picture. There's a 16–18 % dead band under the caption on every store shot, and `05` is half empty |
| Light and material | 3.0 | **2.3** | The strike plate is tamed: mid-grey, no flare, and the glass shards read on it. The lid shadow and wedge AO are present but only register as a faint darkening at the crease |
| Colour and tone | 2.0 | **1.45** | The duck's yellow carries frames 1 and 4. The can in `02` is a **Golden** variant, so it reads as amber liquid rather than a soda can. The egg is cream on cream |
| UI truthfulness | 2.0 | **1.1** | Readouts and labels agree (`02` "111°" → "AT 74°" matches its crown). But `O2` shows a phantom PRESS SEALED card under "Pick on the cover", `07` says "Press without folding. Hear it softer" over both toggles off and WORKSHOP selected, and two frames print "Game Center NOT AVAILABLE" |
| Story and delight | 1.0 | **0.65** | Gesture (`02`) plus payoff (`04`) plus collection exist for the first time. The grid repeats the duck a third time and shows an egg and a cake that don't look crushed |

Weighted: 1.5 + 2.3 + 1.45 + 1.1 + 0.65 = **7.0**.

**App experience (7.8):**
- **What lifted it:** the tabletop UI is clean; the reveal, prints, sealed cover card and P-48 reveal card are good; and the numbers are consistent everywhere.
- **What holds it back:**
  - the reveal-dismiss and closed-launch bugs (§4 N2, N3);
  - the tabletop Shelf rendering into the right half only (§4 N4);
  - the egg yolk hidden under its shell and the cake barely deformed at c = 0.705;
  - the glass pile reading as a confetti wreath around a hole.

---

## 2. Status of every FOLD-REVIEW-5 item

| # | R5 item | Status | Evidence (R6) |
|---|---|---|---|
| §3 a | Numbers agree | **Fixed** | Labels come from the frozen readout: log `storeshot hero note: readout AT 67° on a 63.6° model; pair label follows the readout`. `02` shows "111°" and "AT 74°" against crowns 111° and 74°. The grid prints "EGG · AT 95°" etc. |
| §3 b | Lid cast shadow + wedge AO | **Done in code, weak in pixels** | `drawWedgeShading` (FoldStoreShot.swift:1002–1048). In `01` and `03` it reads only as a darker strip near the crease (y ≈ 1740–1930). It reads as crease AO, not as a lid hanging over the duck. The light is straight down (l.1004), so a 64° lid only throws its shadow 0.44 × its length forward, which is short |
| §3 c | Profile glyphs | **Done on the pair only** | `02` (x ≈ 1200–1390 / 820–960 and 1650–1780 / 1100–1240) works: the V and the arrow make "closing" legible. **The hero has none**, and that's where it's needed most |
| §3 d | Eye turn | **Done** | `squishAzimuth = 32`, `standingAzimuth = 24` (PressDirector.swift:541–542). The hinge end is now visible on the right of `01`, but the device still reads as a laptop at ~100° |
| N1 | Squeeze doesn't read | **Partly; still #1** | See §3, frame 01 |
| N2 | Hot strike plate | **Fixed** | FoldAnvil.swift:262–286 (tabletop roughness 0.55, `#9EA3AA`). In `03` the teal shards and pink scraps read on a mid-grey plate |
| N3 | One caption for all | **Fixed** | `heroCaption(for:)` PressDirector.swift:526–534 |
| N4 | Missing frames | **Rendered, but 3 are wrong** | Reveal, shelf, grid, cover-launch and settings all exist. **But:** `glassBottle-tabletop-reveal` and `cakeSlice-tabletop-reveal` are both an *intact glass bottle at 151°* (the reveal was dismissed; §4 N2). The egg pair failed (`no angle shot to pair with`). `egg-tabletop-reveal` is a cover frame. `duo-shelf` is half empty (N4) and `duo-cover-launch` is a phantom seal (N3) |
| N5 | Glass reads as paper | **Partly** | Darker tint and no ghost disc (GlassBottleView.swift:83, 425). It now reads as **confetti in a ring around an empty centre** (`03` x ≈ 730–1270 / y ≈ 1960–2270). Still flat polygons |
| N6 | 6.9" set wrong size / angle on non-hinged phones | **Fixed** | 1320 × 2868 and 1206 × 2622 sets. `P4` says "CRUSHED AT 56 TONS". The Pinch handle exists at rest only (PressOverlays.swift:139–157), so `P1` (mid-press) doesn't show it. That's acceptable |
| N7 | Re-run 9D | **Not done; irrelevant** | Never uploaded |
| N8 | Icon reads as a tongue | **Changed in code, not reviewed** | AppIconArt.swift:5–6 now bites a yellow duck. No `AppIcon-1024` in r6, so check it next round at 60 px |
| N9 | PRESSED over the print | **Fixed** | Duck: below the print (`04` x ≈ 1070–1330 / y ≈ 1580–1660). Can: top-left |
| N10 | Bubble wrap | **Not**, and now it costs a frame | `P2`: the ram is fully down on an invisible sliver |
| N11 | Jelly overflow | **Unverified** | No jelly frame this run |
| F2 leftover | Dead band (fill 0.64, bleed 0.08) | **Not done** | FoldStoreShot.swift:121–124 still has `bleed: 0.05`, `targetFill: 0.58`. Dead band: `01` y ≈ 545–995 (16 %), `03` y ≈ 486–994 (18 %), `04` y ≈ 560–1060 (17.5 %) |
| F4 | Toast slot visually verified | **Still unverified** | Every run used `notoasts` |
| §5 | Assemble the set | **Done** | `ci/store-set.sh` and `MANIFEST.txt` ("missing or failed: 0"). The manifest checks size and alpha, not content: it passed `05`, `O2` and `07` |

---

## 3. Frame-by-frame

**Rules applied:**
- Guideline 2.3 accuracy: no effect the app doesn't render, and no folded render outside the Duo set.
- No prices (2.3.7).
- Headline legible at thumbnail size.
- Frames 1–3 must each sell alone.

**Guideline status:**
- No frame shows a price.
- No folded device appears outside the Duo set.
- The SF Mono sub-lines (~1.6 % cap height) are illegible at thumbnail size. That's acceptable for a secondary line, but they carry nothing that matters there.

### A. iPhone Duo inner (2007 × 2853)

| # | Frame | Verdict | Problem → fix | Caption |
|---|---|---|---|---|
| **01** | Duck hero | **FIX** (shippable as a fallback) | **(1)** The lid still reads as a laptop lid at ~100°. The label says 67° and the model is at 63.6°, but from a 34° elevation the lid face is fully exposed, it covers none of the anvil, and the shadow is too faint to say "overhang". **(2)** No V glyph on the frame that needs it most. **(3)** 16 % dead band. **Fix (§5 #1):** lower the eye, add the V glyph plus "AT 67°", raise the fill | "Close your phone. Feel it *give*." Good: 5 words, cap height ≈ 4.2 %, highlight on the verb. The sub-line wraps fine |
| **02** | Can pair | **FIX** | **(1)** The can is a **Golden** variant (`sodaCan-storeshot-reveal` says "GOLDEN · 1 IN 50"), so both devices show an amber puddle with a lid rather than a soda can. The same object is green FIZZO in `P3`. A 1-in-50 outcome as the representative can is misleading in spirit. **(2)** The small device's front-right corner kisses the large device's lid corner (x ≈ 670–770, y ≈ 1315–1360): an awkward tangency, so separate them by ≥ 60 px. **(3)** The caption's "Open to *see*" describes a moment this frame doesn't show. **Good:** the labels match their crowns, and the V glyphs plus arrow are the clearest "closing" read in the set | Change to "**The hinge is the *lever*.**" (5 words, and it matches the description copy) |
| **03** | Glass hero | **FIX + MOVE to 4** | **(1)** Identical device, pose and framing to `01`: in the search triplet it looks like the same picture twice. **(2)** The pile is a wreath with an empty middle. The cracked-glass lid print is the strongest lid in the set, though. **Fix:** a different azimuth for this hero (e.g. −28°, the other end of the device); fill the pile centre (N10) | "It creaks. Then it *doesn't*." Good |
| **04** | Duck reveal | **SHIP, and MOVE to 3** | The best frame. Minor: 17.5 % dead band; the reveal duck's pale halo spills past the plate on the right (x ≈ 1290–1310); the "NEW BEST" tag sits on a bolt | "Open up. File the *evidence*. / Every press becomes a specimen." Good |
| **05** | Shelf | **CUT until fixed** | The Shelf sheet renders its whole content into the **right 45 %** of the sheet (cards x ≈ 1115–1940; x ≈ 26–1115 is empty cream). Only 2 cards are readable, 2 are cut off, and no Golden card is visible. The top half is an empty platen with a blurred dark smudge. This is an app layout bug (§4 N4), not a capture problem | "A shelf of pressed *specimens*. / No ads. No in-app purchases." The caption is right; keep it |
| **06** | Variety grid | **FIX** | **(1)** The duck appears for the third time. **(2)** The egg reads as a pale tortilla (yolk hidden under the shell, N9). **(3)** The cake slice looks intact. **(4)** Glass, the most spectacular object, isn't in it. **(5)** At 4-up, each device is ~1000 px wide and the objects are ~15 % of the frame width: OK, not great. **Fix:** objects glassBottle, sodaCan (non-golden), cakeSlice (after N9) and jelly or gummy (add to `STORESHOT_OBJECTS`) | "*Ten* objects. Ten ways to give." Fine. Small wrinkle: the tenth object "does not squish" |
| **07** | Settings | **FIX or CUT** (optional slot) | **(1)** The caption promises "Press without folding. Hear it *softer*", but the frame has Press without folding **off** and Sound style **WORKSHOP**. A frame that contradicts its caption is exactly what 2.3 polices. **(2)** "Game Center · NOT AVAILABLE" looks broken to a buyer. **(3)** The gauge peeks out above the sheet at top-left | Keep the caption and change the state (`soft`, fold toggle on in the demo), or keep the state and change the caption to "Workshop or *Soft*. You choose." |

**Ordering:**
- **Today:** duck hero, can pair, glass hero. Two of the three are the same picture, and none shows a recognisable phone.
- **Proposed:** `01` duck hero → `02` pair (re-seeded can) → `03` **duck reveal** → `04` glass hero (new azimuth) → `05` grid → `06` shelf (fixed) → `07` settings (fixed).

That puts the gesture and the payoff in the search triplet and the device's phone-ness in frame 3.

### B. iPhone Duo outer (1398 × 2034)

| # | Frame | Verdict | Notes |
|---|---|---|---|
| **O1** | Sealed cover, overlay caption | **SHIP** | "Ka-chunk. Now *open* it." over empty graphite. The print teaser and 54 TONS read at thumbnail size |
| **O2** | "Closed-launch picker", framed | **CUT** | **It shows no picker.** It's a second PRESS SEALED · 54 TONS card with an outline duck, because the app sealed a press on launch (§4 N3; log `duo-cover-launch.txt`: `phase=sealed depth=1.000` at 5.52 s with no input). The caption "Pick on the cover" is false for this image, and it duplicates O1. The camera cut-out (black disc at x ≈ 1200–1310, y ≈ 520–600 in the framed file) is real hardware, so that part is fine. **Re-shoot after N3** so the idle cover with the chip grid and "Open to press" shows |

### C. iPhone 6.9" (1320 × 2868) and 6.1" (1206 × 2622): identical verdicts

| # | Frame | Verdict | Notes |
|---|---|---|---|
| **P1** | Duck mid-press | **SHIP after a text fix** | Strong toy image: the duck bulges under the ram and the gauge needle is at 40. **Fix:** the sub-line widows ("A hydraulic press for every / iPhone."). Shrink the sub-line to one line, or balance the break. The handle isn't visible (it hides during a press by design); the caption still makes sense |
| **P2** | Bubble ripple | **CUT** | The ram is fully down and the bubble wrap is an invisible sliver, so "Every bubble *pops* on its own" sits over nothing. Replace with glass at depth ≈ 0.66 ("It creaks. Then it *doesn't*.") or jelly |
| **P3** | Can buckle | **SHIP** | The green FIZZO can with its rim rolling under the plate reads well. Its raw frame has the Dynamic Island pill but P1, P2 and P5 don't; make it consistent (§4 N13) |
| **P4** | Duck reveal | **SHIP** | "CRUSHED AT 56 TONS", "He'll be fine. Probably." The 3-line headline is acceptable. **Move to P2** so the first three are press, payoff, can |
| **P5** | Shelf | **SHIP** | 7/10, ON THE ANVIL sticker. Minor: the Pinch handle "‖ ˅ ‖" shows on the crosshead behind the open sheet |
| **P6** | Settings | **FIX** | "Game Center · NOT AVAILABLE" again. The headline breaks into three lines with "the / press." orphaned; drop "the" or let the headline shrink to two lines |

**Never upload:** `*-eye`, `*-112`, raw `*-tabletop-*`, `*-book-storeshot-*`, `9A–9D`/`90–99`, any `*-storeshot-hero` other than duck/glass (the can hero's caption widows "ring."), and `O2`/`05` as rendered.

---

## 4. New issues, ranked

### N1. The hero still reads as an open laptop — **M**
- **Frames:** `01`, `03`, `06`, and every `*-storeshot-hero`.
- **Cause:** 34° elevation (FoldStoreShot.swift:1513/1519, `elevationDegrees ?? 34`) plus a 32° turn. A 64° lid tilted toward the eye shows its whole face and occludes nothing. The overhead-light shadow (l.1004–1042) only reaches 0.44 × the lid's length.
- **Fix:**
  - **(a)** Add a `storeshotelevation=` demo key beside `storeshotazimuth` (PressDirector.swift:771). Try 20–24° elevation at azimuth 45–55°. The lid then occludes the back of the anvil and its free edge projects clearly *in front of* the crease.
  - **(b)** Draw the pair's V glyph plus "AT 67°" on the hero too (reuse `drawPairMarks`).
  - **(c)** Tilt the studio key 25–30° toward the viewer for the hero, so the shadow lands on the duck.
  - **(d)** Re-check E2 on the `-eye` composite: the duck must still stand.
- **Constraint:** don't hold the hero below ~58°. The real inner display goes dark in the 55–20° window, so a lit screen at 45° would misrepresent.

### N2. The reveal is dismissed by a stray `closed` sample — **S**, ship-blocking
- **Frames:** `glassBottle-tabletop-reveal`, `cakeSlice-tabletop-reveal` (both an intact glass bottle at 151°, "Shelf 1/10").
- **Evidence:**
  - cake log l.228–232: `reveal seen hinge=20.1` → `24.8 1 phase=revealing` (closed = 1 at 24.8°) → `object view glassBottle` 1.3 s later;
  - the glass log l.319–323 is the same;
  - in both, the hinge stalled at ~25° when the sweep helper was killed (`signal 15`).
- **Cause:** PressDirector.swift:186–191. `if closed || angle < revealPeakAngle - 20 { next() }` fires on the first `closed` sample during the reopen. That's inside the display-off window, before the user has seen the card. The specimen is saved, the payoff is lost, and the next object loads.
- **Hardware risk:** a real hinge with ~5° noise and a posture-derived `closed` flag can flicker the same way on a hesitant open.
- **Fix:**
  - require the card to have been visible (`angle ≥ config.revealAngle`) for ≥ 1.2 s, and `revealPeakAngle ≥ 100`, before either dismiss rule applies;
  - debounce `closed` (≥ 0.3 s continuous);
  - add a CI assert: `phase=revealing` must reach the 150° capture.

### N3. Launching with the phone shut seals a phantom press — **S/M**, ship-blocking
- **Frames:** `O2` and `duo-cover-launch`.
- **Evidence:** launched at hinge 0 with `object=rubberDuck;duo;notoasts;specimens=7` (ci/duo-screenshots.sh:507). The log goes `SQUISH-H 4.73 0.0 1 phase=armed` and then `phase=sealed depth=1.000` at 5.52 s, and the cover shows PRESS SEALED · 54 TONS.
- **Cause:**
  - The engine is already *armed* before its first real sample: `tryArm` (PressEngine.swift:326–333) uses the default open angle.
  - The first sample is `closed`, and `wasClosed` starts false, so `handleClose` (l.426–433) fires. Its `|| rawAngle <= config.endAngle` clause fast-forwards and seals a press the user never made.
- **Effect on a customer:** open Squish from the cover (the flow `O2` advertises) and you get a fake "PRESS SEALED", then a reveal and a shelf entry for a duck you never pressed.
- **Fix:**
  - don't arm until a real hinge sample has arrived with `!closed`;
  - in `handleClose`, require `pressStartTime != nil` (or `maxDepthReached > 0.05`);
  - treat the first sample's `closed` as a state, not a transition.
- **Then:** re-shoot O2, so the idle cover shows the chip grid (CoverView.swift:481–501).

### N4. The tabletop Shelf renders into the right half only — **S**
- **Frames:** `05-shelf` and `duo-shelf`.
- **Cause:** `CreaseSafe` (Theme.swift:982–997) assumes book pose whenever `hasHinge && width > height`. In tabletop portrait the sheet sits at the 0.45 detent (RootView.swift:342) on the anvil half (669 × ~430 pt), so it's wider than tall and gets squeezed to the trailing half, even though the crease is horizontal.
- **Fix:**
  - decide on the window's orientation, or the fold posture (vertical crease = book), not the sheet's own aspect;
  - for the store frame, open the demo Shelf at `.large` so both halves show the grid (5 columns at `wide`, ShelfView.swift:44–56) and the seeded Golden card is visible.

### N5. The settings frames contradict their captions and show "NOT AVAILABLE" — **S**
- **Frames:** `07`, `P6`.
- **Fix:**
  - Demo args (ci/duo-screenshots.sh:504): select Soft and turn on Press without folding to match the caption, or rewrite the caption.
  - SettingsView.swift:171–174: when Game Center isn't authenticated and no sign-in is pending, hide the row or show "Achievements are saved on this iPhone." with no status word. "NOT AVAILABLE" reads as broken to a buyer and to a reviewer.

### N6. A Golden can stands in for the soda can — **S**
- **Frames:** `02`, `06`, `sodaCan-storeshot-reveal`.
- **Fix:** pin a non-golden `seed=` for sodaCan in the tabletop pass, and have the log print `golden=0`. Keep Golden for the shelf frame, where it's labelled.

### N7. Frames 01 and 03 are the same picture; the order hides the best frame — **S**
- **Fix:**
  - a per-object `storeshotazimuth` for glass (e.g. −28°);
  - reorder in ci/store-set.sh (duck hero, pair, duck reveal, glass hero, grid, shelf, settings);
  - for the 6.9" set, use P1, P4, P3 for the first three.

### N8. P2 shows nothing — **S**
- **Frame:** `P2`.
- **Fix:** ci/scenarios.txt:93. Replace with `object=glassBottle;depth=0.66;notoasts` (or jelly at ~0.6) and the glass caption. Bubble wrap is too thin to read in a side-on press.

### N9. Egg and cake don't look crushed at the hold — **M**
- **Frames:** `egg-tabletop-62`, `cakeSlice-tabletop-62`, `06`.
- **Egg:** the shell fragments lie over the yolk dome, so the anvil shows a cream disc with paper-white shards and no yolk. EggView.swift:133–212: after fracture 2, tumble the cap shards outward (or drop them below the albumen), and raise the broken yolk's height so the yellow shows at c ≥ 0.5.
- **Cake:** at c = 0.705 the slice is still an intact wedge, with a little frosting and pink blobs. CakeSliceView.swift:159 `update`: squash the sponge layers vertically, ≥ 50 % at c 0.7, and bulge the frosting out of the sides.

### N10. The glass pile is a ring with a hole — **S/M**
- **Frames:** `03`, `glassBottle-tabletop-62`.
- **Fix:** GlassBottleView.swift pile placement (~l.425–500). Seed 25–30 % of the shards inside r < 0.35, and stack 2–3 shards high in the centre so it reads as a crushed heap.

### N11. Caption breaks: widows and orphans — **S**
- **Frames:**
  - `P1` sub-line ("… every / iPhone.");
  - `sodaCan-storeshot-hero` ("Cans buckle ring by / ring.");
  - `P6` ("Just the / press.").
- **Fix:** in ci/store-frame.swift and `FoldStoreShot.captionString` (FoldStoreShot.swift:715–760):
  - prefer balanced line breaks, and never leave a single word alone on the last line;
  - shrink a sub-line to fit on one line before wrapping it.

### N12. Dead band under the caption — **S**
- **Frames:** `01`, `03`, `04`, `06` (16–18 % of the height).
- **Fix:** FoldStoreShot.swift:121–124: `targetFill` 0.58 → 0.66 and `bleed` 0.05 → 0.10, or a hero box top of 0.17. Re-check after N1, because a lower eye changes the device's aspect.

### N13. The Dynamic Island pill appears in some 6.9"/6.1" frames, not others — **S**
- **Frames:** `P3`, `P4` and `P6` have it; `P1`, `P2` and `P5` don't.
- **Fix:** ci/screenshots.sh:121. Capture with a fixed `--mask` policy (or crop the status bar band in store-frame) so all six match.

### N14. The Pinch handle shows behind the open Shelf sheet — **S**
- **Frame:** `P5`.
- **Fix:** PressOverlays.swift:154–157. Add "a sheet is presented" to `suppressed`/`atRest`.

### N15. CI flakiness hides failures — **S/M**
- **Evidence:** 14 warnings in run.txt, including `sweep exited non-zero`, `hinge did not confirm` ×9, the egg pair failing, and the egg reveal being captured on the cover. Even so, MANIFEST reported "missing or failed: 0", because it checks size and alpha only.
- **Fix:**
  - retry a sweep step that was killed;
  - fail `store-set.sh` when a source log lacks its `storeshot … ok` line, or when the reveal source is in `phase=armed`.

---

## 5. Top 5 fixes and honest projection

1. **Make frame 1 read as "closing"** (N1 + N12).
   - Add an elevation key (default 22° for the hero) at azimuth ~50°.
   - Put the V glyph and "AT 67°" on the hero.
   - Tilt the key light so the lid shadow falls on the duck.
   - Fill 0.66 / bleed 0.10.
   - E2-check the `-eye` composite.
   - **M. Set +0.4.** It's still the single biggest conversion lever.
2. **Fix the two app bugs the store run exposed** (N2 reveal debounce at PressDirector.swift:186–191; N3 phantom seal at PressEngine.swift:326–333 and 426–433). Then re-shoot O2 as the real idle cover picker.
   - **S/M. App +0.3, set +0.2** (O2 becomes a usable frame).
   - These ship to customers whatever the screenshots look like.
3. **Repair the support frames** (N4 CreaseSafe and the `.large` demo Shelf; N5 settings state and the Game Center row; N8 replace P2 with glass).
   - **S. Set +0.3.** It turns three cut frames into shippable ones.
4. **Re-cut and re-seed the set** (N6 non-golden can; N7 reorder so frame 3 is the duck reveal, glass gets its own azimuth; a new pair caption; grid = glass, can, cake, jelly; N11 caption breaks; N13 island consistency).
   - **S. Set +0.3.**
5. **Objects that read as crushed** (N9 egg yolk and cake squash; N10 glass heap).
   - **M. App +0.15, set +0.1.**

**Projection:**
- **Set:** 7.0 → **~8.2** after all five (≈ 7.8 if N1 only half lands).
- **App experience:** 7.8 → **~8.2**.

Past 8.5 still needs what R5 said:
- a real-Duo photo or video for frame 1, if the founder allows it;
- or a true side-on "into the fold" view;
- plus the bubble wrap family rebuilt.

---

## 6. Launch readiness checklist (1.0)

### Code and art (dev can close these)

- [ ] **N3** phantom seal on closed launch (PressEngine). *Blocker*
- [ ] **N2** reveal dismissal debounce (PressDirector). *Blocker*
- [ ] **N4** tabletop Shelf layout (Theme.CreaseSafe). *Blocker*: this is the real UI, not just a screenshot
- [ ] N5 Game Center row copy when unavailable; settings demo state
- [ ] N1 hero camera, glyph and shadow; N12 fill
- [ ] N6–N8, N11, N13 set hygiene; re-run `store.yml` and re-assemble
- [ ] N9 egg and cake deformation; N10 glass heap
- [ ] N14 Pinch handle suppressed under sheets
- [ ] N15: CI fails on a missing reveal or pair; MANIFEST checks the log lines
- [ ] Verify F4 (achievement toast slot) with one Duo reveal without `notoasts`, and N11/R5 (jelly reveal clamp) with a jelly frame
- [ ] Render `AppIcon-1024` and check the new duck icon at 60 px and 29 px (not seen this round)
- [ ] metadata.md accessibility claims checked against the build: "visual sound cues" = the Captions toggle (confirm it's on-by-choice and works with VoiceOver)

### Only the founder can do

- [ ] Sign off the per-frame captions, including the new pair line and the settings line
- [ ] Decide the device likeness (generic slab vs the real Duo outline) and accept the 3/4 renders as "app in use"; or allow one real-device photo for frame 1 (R5 §7 6a)
- [ ] Subtitle risk: "The £2,000 hydraulic press" vs the fallback (metadata.md §2)
- [ ] Fill the placeholders: `[domain]` (support, marketing, privacy URLs), `[Studio legal name]`, pre-order and release dates; enrol in the Small Business Program
- [ ] Create the 10 Game Center achievements in App Store Connect (otherwise "NOT AVAILABLE" is the shipped state)
- [ ] Accessibility Nutrition Labels: declare only what has been tested
- [ ] App Review notes: tell non-Duo reviewers about Pinch Press and "Press without folding"
- [ ] App Preview: none in the Duo slot, or a 6.9" Pinch Press screen capture only (2.3.4)

### Only real hardware can settle

- [ ] Does the anamorphic duck stand at the design eye on a real tabletop Duo (±10 cm head movement, 5° hinge noise)? If not, frames 01–04 overstate the app
- [ ] Does the real hinge's `closed` flag flicker on a slow reopen (N2), and does a cold launch on the cover seal a press (N3)? Test both on device after the fixes
- [ ] Display-off window (55–20°) and reveal timing; ka-chunk and haptics against the real hinge's stiffness
- [ ] OLED tone of the L ≈ 210 cream and the tamed plate in daylight; thermals at 120 Hz during a 30 s press
- [ ] App Store Connect: whether the Duo inner and outer slots are selectable yet. If not, ship the 6.9" and 6.1" sets and add the Duo set by metadata edit
