# Fold Review 8: the payoff lands, and two frames lie

*Design critic pass 8, 23 Oct 2026. Inputs (all viewed):*
- *`r8/store-duo/duo-screens/store/`: inner `01–07` (2007 × 2853), outer `O1, O2` (1398 × 2034), `MANIFEST.txt` (missing 0, flagged 0).*
- *`r8/store-69/store/P1–P6` (1320 × 2868) and `r8/store-61/store/P1–P6` (1206 × 2622), their MANIFESTs and `logs/P*.at-capture.txt`.*
- *Raw frames: `duo-settings.png` (**2853 × 2007**), `duo-shelf.png`, `cakeSlice-tabletop-62` and `-reveal`, `jelly-tabletop-reveal`, `glassBottle-tabletop-reveal`.*
- *Logs: `run.txt`, `reveal-checks.txt`, `rubberDuck-tabletop.txt` (the new `SQUISH-F paused/resumed` and `reveal dark/lit` lines), `duo-cover-launch.txt`, `duo-settings.txt`, `duo-shelf.txt`.*
- *Repo at `1a0da50` (round 8 is `35575f1`, icon `b266414`). `AppIcon-1024.png` was also drawn at 256, 120, 60 and 29 px on dark and light grounds.*

*Coordinates are px of the file as named.*

---

## 1. Verdict

| | Score | R7 |
|---|---|---|
| **Store set, as an App Store submission** | **8.2 / 10** (≈ 8.5 once `07` is re-shot and the Shelf strip shows prints) | 7.9 |
| **App experience, as seen in the frames and logs** | **8.5 / 10** | 8.2 |

**Store set, in one line:** the Duo search triplet is finally the right one: gesture, lever, payoff. But the manifest's "flagged: 0" is false. `07` is a half-black landscape capture floating under a 35 % void. `06` sells "pressed specimens" with a strip of *intact* objects.

**App, in one line:** every R7 rendering bug is gone and the closed-phone render loop is parked (verified in the log). The icon is finally the duck in the fold. What's left is one object (the cake) that still doesn't read as crushed, and a glass crack nobody can see.

**Would a stranger pay £2.99?**
- **A Duo owner: yes.** `01` "Close your phone", `02` "The hinge is the lever" and `03` "Open up. File the evidence." each sell alone, and together they're a product nobody else has. The icon now says "fold + duck" at search-result size.
- **A regular-iPhone buyer: probably yes**, on P1–P3. P4 still sells nothing (a bottle lying under the ram, with no crack you can see), so ship five frames.
- The ceiling hasn't moved. The Duo in tabletop pose is still a small laptop shape, so past ~8.6 needs a real-device photo or video (founder, §6).

### Store-set scoring (weights as R1–R7)

| Dimension | Weight | Score | Why |
|---|---|---|---|
| Composition | 2.0 | **1.7** | `02` separation is fixed (~70 px clear). `03` shows the whole device, hinge spine included. `04` keeps its hinge in frame. `06` now fills its sheet. **But** `07` is a landscape card at y ≈ 1565–2770, with y ≈ 570–1560 empty (35 %) and the right half black. `01` still clips the base corner at x 0 |
| Light and material | 3.0 | **2.4** | The jelly is now a rimmed puddle with a tear. Glass is bigger, streaked shards around an intact base ring. The duck reveal is the best image in the set. The cake is still a blown-out white wedge (`05`, raw `-reveal`) |
| Colour and tone | 2.0 | **1.7** | Green FIZZO, magenta jelly, yellow duck. The set reads as one family. The cake is the one flat, white cell |
| UI truthfulness | 2.0 | **1.55** | Labels match readouts everywhere, P-frames are content-checked, and O2 is the real idle picker. **But** `06`'s "Recently squished" shows intact icons; the seeded cards read "AT 128°", "AT 118°" when every real failure in the set is 64–80°; `07` shows the app letterboxed into half a screen; and P4's caption promises a break the frame doesn't show |
| Story and delight | 1.0 | **0.85** | Gesture → lever → payoff → variety → collection now runs in order on the Duo, and P1 → P2 → P5 on the iPhone |

Weighted: 1.7 + 2.4 + 1.7 + 1.55 + 0.85 = **8.2**.

### App experience (8.5)

**Up:**
- **The render pause works.** `rubberDuck-tabletop.txt:214–229`: `paused fold reason=closed at 289.85s` → `resumed fold after=22.93s blind=270 stray=0`. All 270 hinge samples were handled blind, and none were stray.
- **The reveal waits for the light.** Line 228: `reveal dark at 19.8° (paused=1): beats wait for the light`. Line 238: `reveal lit at 56.6° after 1.04s`. That is the R7 display-off worry, handled in code.
- **The cover launch stays idle,** and the p48 and fold stages park (`duo-cover-launch.txt`).
- **The candle is fixed:** it lies on the wedge at its true length (raw `cakeSlice-tabletop-62`, x ≈ 900–1050 / y ≈ 2030–2140).
- **The jelly reads as SPLAT.** Glass reads as broken bottle glass, not confetti.
- **The Shelf is Duo-native now:** the object grid on the ram half, prints on the anvil half.
- **The icon** is the duck in the fold (`b266414`).

**Held back:**
- The cake reveal at c = 1.000 is still a tall, intact, over-exposed wedge with pink lumps (raw `cakeSlice-tabletop-reveal`, y ≈ 1740–2420).
- In the P-48 press the glass crack is invisible (§4 N3).
- The demo collection has no prints (§4 N2). That's demo-only, but nothing covers a real specimen whose thumbnail fails to write.

---

## 2. Status of FOLD-REVIEW-7 items

### The four launch blockers

| R7 blocker | Status | Evidence (R8) |
|---|---|---|
| **N1:** commit a freshly rendered icon | **Fixed** | `b266414` commits the CI render; it is 1024², 24-bit, no alpha. It reads as a folded device biting a yellow duck, with hazard stripes and a camera bump. At 60 px the duck's eye and beak survive; at 29 px it's a dark tile with a yellow bite, which is acceptable. No hash assert was added (ci/screenshots.sh:278–311 only exports). Minor, §4 N8 |
| **N3:** cake candle stretch | **Fixed** | The candle keeps its length on top of the wedge in `-62`, `-reveal` and `05` (x ≈ 270–350 / y ≈ 1660–1720 in the cell). No needle |
| **A complete 6.9"/6.1" set** | **Fixed as a pipeline, not as a frame** | P4 is at `depth=0.52`, and the log shows `c=0.314 fractures=1 failed=0` (scenarios.txt:104; both MANIFESTs). The frame is no longer empty, but the crack can't be seen (§4 N3). **Ship P1, P2, P3, P5, P6** |
| **A green store run** | **Green on paper; not actually green** | `missing: 0  flagged: 0`, and `03` is the real duck (`reveal-checks.txt`: all five ok). But `07` is built from a 2853 × 2007 landscape source that no check looks at (§4 N1) |

### Everything else

| # | R7 item | Status | Evidence (R8) |
|---|---|---|---|
| N2 | P4 empty press; no P-frame content check | **Check fixed; frame still weak** | `ci/screenshots.sh` content checks are in, and the MANIFEST quotes the `demo press done` line per frame. P4 is now a bottle under the ram with no visible crack |
| N4 | Reveal crops both sides; 16 % floor | **Fixed** | `03`: the whole device is in frame, the hinge spine is visible at left, and the floor is ~10 % (y ≈ 2570–2853). The log has `el=42` |
| N5 | Duo Shelf half empty | **Fixed, but exposed a new problem** | The grid is on the ram half and a "Recently squished" strip is on the anvil half (ShelfView.swift:676–760). The strip shows **intact object tiles** (§4 N2) |
| N6 | Meta wrap / secret hint truncation | **Fixed** | "PERFECT / №0001" with no dangling "·". The hint is now the copy "Some things won't squish…" (AchievementInfo.swift:161); the ellipsis is intended. Name baselines are aligned |
| N7 | Settings footnote break | **Fixed** | P6 (both sizes): "Follows your iPhone setting / (Settings › Accessibility › Motion)." |
| N8 | Glass confetti | **Mostly fixed** | ~45 shards, size varied, bright edges, label scraps, and the neck and base ring whole (`04`, raw `-reveal`). The base ring reads as a pale disc/lens (`04` x ≈ 880–1150 / y ≈ 1800–1930). Acceptable |
| N9 | Jelly unsquashed | **Fixed** | Raw `jelly-tabletop-reveal`: a lobed, rimmed puddle with a visible tear that matches its print |
| N10 | Inner scene ticking while shut | **Fixed (simulator)** | `paused fold reason=closed` / `resumed … blind=270`. Thermals are still for hardware |
| N11 | `01` corner clip; `02` tangency; name baselines | **`02` and baselines fixed; `01` not** | `01` still cuts the base's front-left corner at x 0, y ≈ 1800–1870 |
| R7 §3 `02` | Pair separation | **Fixed** | The small device ends at y ≈ 1270 and the large lid starts at y ≈ 1340 |
| R7 §3 `04` | Hinge clip | **Fixed** | The hinge spine is in frame at x ≈ 40–140 |
| R7 §5 #5 | Cake reads crushed | **Not fixed** | The candle is fixed, but the wedge outline is intact from above at c = 1.0. The cream top (`0xFFF3F7` + clearcoat, CakeSliceView.swift:86) clips to white |
| F4 | Toast slot verified | **Still unverified** (8 rounds) | Every run used `notoasts`. The round-8 change "toasts wait for the display to light" makes this more urgent, not less |
| Egg | R7 yolk change | **Still unseen** | No egg in any run |
| `07` (R7: ship) | Settings | **Regressed → re-shoot** | §4 N1 |

---

## 3. Frame-by-frame verdict

**Rules applied:**
- Guideline 2.3: show only what the app renders.
- No prices.
- Headline legible at thumbnail size.
- Frames 1–3 must each sell alone.

**Guideline status:** no prices anywhere; no folded device outside the Duo set; every caption is legible at 25 %.

### A. iPhone Duo inner (2007 × 2853)

| # | Frame | Verdict | Notes |
|---|---|---|---|
| **01** | Duck hero | **SHIP** | "AT 64°" with the V glyph, the lid print and the flattened duck are all clear. The caption is the strongest line in the set. Optional: the base corner is clipped at x 0 (y ≈ 1800–1870); a 2 % x-inset would fix it |
| **02** | Can pair | **SHIP** | The separation is fixed. "111°" → arrow → "AT 66°", with green FIZZO and a crushed can with its ring print. Clean |
| **03** | Duck reveal | **SHIP** | The frame the set was missing, and the best one in it. PRESSED stamp, NEW BEST, "RUBBER DUCK · 1 HONK · 1 SEAM POP · AT 64°", the console row, and the whole device. The flat duck is unmistakably a duck and unmistakably flat |
| **04** | Glass hero | **SHIP** | Hinge in frame, cracked-glass lid print, a real shard heap. Floor ~15 % (y ≈ 2430–2853); acceptable |
| **05** | Variety | **SHIP** | Glass, can, cake and jelly, each labelled from its readout. The jelly print is the most graphic thumbnail in the set. The cake cell (bottom left) is the weak one: a white wedge (§4 N4) |
| **06** | Shelf | **FIX (S): blocker** | The layout is right: grid above the crease, strip below, Golden egg, "???" slot. **But** the strip (y ≈ 1790–2620) is five *unpressed* object tiles under "RECENTLY SQUISHED". The biggest one is a 650 × 650 px green can-shaped jar (x ≈ 380–1035, y ≈ 1880–2530). And the meta lines read "AT 92° / 118° / 97° / 128° / 112°", while every real failure in this set is 64–80°. Fix in §4 N2, then re-run |
| **07** | Settings | **CUT until re-shot: blocker** | The source is a **2853 × 2007 landscape** capture with the app letterboxed into the left ~1410 px and the right half black. Framed as a small landscape card at the bottom, it leaves a 35 % void under the caption. In R7 this frame was a ship. §4 N1. **If it can't be re-shot in time, upload 01–06** |

### B. iPhone Duo outer (1398 × 2034)

| # | Frame | Verdict | Notes |
|---|---|---|---|
| **O1** | Sealed, overlay | **SHIP** | "PRESS SEALED", the duck print teaser, "55 TONS", "OPEN TO SEE". Reads at thumbnail size |
| **O2** | Idle cover picker | **SHIP** (improves for free with N2) | Truthful idle picker. Its three recent tiles are the same intact fallback icons (can, cake, Golden egg). This is less damaging here because nothing says "squished", but the N2 fix lands here too |

### C. iPhone 6.9" and 6.1": identical verdicts

| # | Frame | Verdict | Notes |
|---|---|---|---|
| **P1** | Duck mid-press | **SHIP** | Unchanged from R7; good |
| **P2** | Duck reveal | **SHIP** | "CRUSHED AT 56 TONS · He'll be fine. Probably." The best non-Duo frame |
| **P3** | Can buckle | **SHIP** | The rim rolls over under the ram. "Ring by ring" is generous, but true enough |
| **P4** | Glass crack | **CUT** | The content check is honest (`fractures=1 failed=0`), but the picture isn't. The bottle lies on its side under the ram (6.9": x ≈ 470–830, y ≈ 2150–2230), and the crack lines are invisible (§4 N3). "Then it *doesn't*." over an intact-looking bottle sells nothing. **Upload P1, P2, P3, P5, P6** |
| **P5** | Shelf | **SHIP** | Two big cards with the ON THE ANVIL sticker |
| **P6** | Settings | **SHIP** | The footnote breaks cleanly. On 6.1", "for / each moment." is a fine break |

**Never upload:**
- `07` as rendered; `P4` as rendered;
- `*-eye`, `*-112` and raw `*-tabletop-*` frames;
- any `*-storeshot-hero` other than duck and glass.

---

## 4. New issues, ranked

### N1. `07` is a landscape capture, and CI called it green — **S**, blocker
- **Evidence:**
  - `duo-settings.png` is 2853 × 2007, with the app drawn upright in a ~1410 × 2007 column on the left and black to the right.
  - `duo-settings.txt`: `orient portrait ok at 19.76s layout=none requests=5`. Five geometry requests mean the interface kept losing portrait.
  - `run.txt:570–583`: the settings frame launches straight after the cover-launch pass (hinge 0° → 180°), because DUO_UI defaults to `shelf cover settings` (ci/duo-screenshots.sh:130).
- **Causes:**
  - **PressDirector.swift:788–791:** with `nofold` there is no Fold Press layout, so "ok" is declared after 5 s of `interfaceOrientation.isPortrait` alone. That doesn't prove the captured screen is portrait.
  - **ci/store-set.sh:121–140:** `caption_frame` checks only the *output* size (`check "$dest"`, l.129), never the source's. The frame-07 check (l.218) greps the settings state, not the geometry.
- **Fix:**
  1. In `caption_frame`, require the source to be 2007 × 2853 for `06` and `07`, or FLAG the frame.
  2. In the `layout=none` branch, also require `window.bounds.height > width` and `windowScene.screen.bounds` to be portrait before logging ok.
  3. Order DUO_UI `shelf settings cover`, or settle the hinge at 180° with an extra `SETTLE` before the settings launch.
  4. Re-run.
- **Hardware check, since it could be real:** on the Duo in book pose, with Press without folding on, open Settings and confirm it isn't letterboxed.

### N2. "Recently squished" shows intact objects, and the seeded angles are impossible — **S**, blocker for `06`
- **Cause:**
  - `SpecimenImage` falls back to `ObjectTile`, the *unpressed* object icon, when a specimen has no thumbnail (Theme.swift:953–955).
  - `seedDemo` (CollectionStore.swift:402–417) records results but never writes print thumbnails, so every seeded card hits the fallback.
  - The same fallback feeds the cover's recent tiles (CoverView.swift:519–523).
  - The seeded failure angles (CollectionStore.swift:393–399: 104, 112, 128, 97, 118, 92) are 20–60° above anything the press produces in this set (64–80° in the store-shot logs).
- **Fix:**
  - **(a)** In `seedDemo`, render each seeded specimen's ink print through the same path the real reveal uses (`FoldStamps.stamp(for:variant:foldScale:)` → the platen's `renderPrint`), and save it as that specimen's thumbnail.
  - **(b)** For real users, replace the fallback with a *pressed* tile: the kind's stamp on steel, not the intact icon. A specimen should never look unsquished.
  - **(c)** Re-seed the angles at each kind's real failure angle (read it from a seed-3 press, or pick plausible values in 60–85°).
  - Then re-run the shelf and cover frames.

### N3. The glass crack is invisible in the P-48 press — **S/M**
- **Frame:** P4 (both sizes), and every real touch-press of the glass bottle.
- **Cause:** GlassBottleView.swift:434–477. The crack run is seven boxes 0.4 mm tall × 0.7 mm wide, unlit near-white (`0xF4FFFC`, opacity 0.85), laid along the *top* of a pale sea-glass body. At c = 0.31 the ram face is on that top, and the P-48 camera sees it edge-on. That's white on pale green, under a steel plate, at a grazing angle.
- **Fix:**
  - Put a second run on the camera-facing flank, as a star from one impact point, ~2 mm wide, with a dark hairline beside a bright core so it reads against both glass and steel.
  - Add visible ovalisation (≥ 8 % bulge) after fracture 0, and a glint at the crack origin.
  - Then re-shoot P4 at whatever depth shows ~80 % crack growth while still `failed=0`. Keep the content check.
  - If that doesn't land in time, P4 stays cut. Five frames is fine.

### N4. The cake still doesn't read as crushed — **M**
- **Frames:** `05` (cake cell), raw `cakeSlice-tabletop-62` and `-reveal`.
- **Problem:** at c = 1.0 the wedge keeps its full outline and height from above. The new "filling tongues" read as pink lumps around an intact slice. The cream top (CakeSliceView.swift:86, `0xFFF3F7`, clearcoat 0.3) clips to flat white under the key light, so there's no shading to show a squash even where there is one.
- **Fix:**
  - In `update` (l.168), drive the top's outline outward with c (the wedge should widen ~30 % and lose its point), not just its height down.
  - Drop the cream to ~`0xF6E6EA` with roughness 0.6 and no clearcoat, so the form shades.
  - Let one sponge layer show at the split edge.

### N5. `01` corner clip — **S**, optional
- **File:** FoldStoreShot.swift (the hero fit's `deviceDraws` clamp).
- **Problem:** the base's front-left corner leaves the frame at x 0.
- **Fix:** a 2 % x-inset clamp, the same one that fixed `04`.

### N6. P-frame content check doesn't see the frame — **S**, process
- The P4 check passed because `fractures>=1` is true. It can't know the crack is invisible.
- **Fix:** keep the log check, and add one cheap image assert per frame. For P4, the pixel variance inside the ram–plate gap must exceed a floor. Or accept that P4's visual sign-off is manual and say so in the MANIFEST.

### N7. Toasts never verified — **S to verify**
- Eight rounds, every run `notoasts`. Round 8 made toasts wait for the display to light (`35575f1`), which is new timing on the most visible moment in the app.
- **Fix:** one Duo duck reveal without `notoasts`, then screenshot the reveal with the "NEW BEST" / achievement toast up.

### N8. Minor
- No CI assert that the committed `AppIcon-1024.png` matches a fresh render (R7 asked for one). Add a hash compare in `ci/screenshots.sh` after l.311.
- Icon composition: the subject sits low-right, leaving the top ~18 % dark. Scaling the art ~10 % about the duck would read better at 60 px. Optional.
- The soda-can object tile reads as a jar: a rounded green slab with no rim. It shows large in `06` and O2 until N2 lands, after which it stops mattering.

---

## 5. Top 5 fixes and honest projection

1. **Re-shoot `07` behind a real orientation check** (N1).
   - Source-size guard in `store-set.sh`, window-bounds check in PressDirector.swift:788, settings before cover in DUO_UI, then re-run.
   - **S. Set +0.15.** Fallback: ship Duo 01–06.
2. **Prints, not icons, in "Recently squished" and on the cover** (N2).
   - Seed real print thumbnails, use a pressed-tile fallback, and plausible seeded angles.
   - **S. Set +0.15, app +0.05.** It makes `06` true, and it protects real users from an unpressed "specimen".
3. **Upload P4 cut, and fix the crack for 1.0.1** (N3).
   - Front-flank crack star, thicker dark-cored lines, ovalisation.
   - **S/M. +0.1 to the iPhone sets once it's back in.** Zero risk while it's cut.
4. **Crush the cake** (N4): outline spread, de-whitened cream.
   - **M. App +0.1, set +0.05** (`05`).
5. **Verify what's never been seen** (N7): one toast-on reveal and one egg tabletop frame. Fix `01`'s corner (N5) while re-rendering.
   - **S. Mostly risk removal.**

**Projection:**
- **Set:** 8.2 → **~8.5** after 1–2, **~8.6** after all five.
- **App:** 8.5 → **~8.7**.

Above that still takes what R5–R7 said: a real Duo, in a real hand, for frame 1. Code can't buy it.

---

## 6. Launch-readiness call

**Is the code/art side ready to submit 1.0 now? No, but the binary is.** Nothing left is in the press engine, the reveal or the icon. What blocks is the screenshot package. Two of the uploaded frames are wrong, and the CI that should have caught one of them didn't. That's about half a day of work plus one store run.

### Blocks a 1.0 submission (dev closes these)

- [ ] **N1:** make `07` a portrait capture. Add the source-size guard to `ci/store-set.sh` `caption_frame`, the window-bounds check to PressDirector.swift:788–791, and the DUO_UI order fix. **Or** decide to upload the Duo inner set as 01–06.
- [ ] **N2:** demo specimens get real print thumbnails (CollectionStore.swift:402–417), with a pressed-tile fallback (Theme.swift:953–955) and plausible seeded angles (CollectionStore.swift:393–399). Re-shoot `06` (and O2).
- [ ] **A truly green store run:** `store-set.sh` exits 0 with the new guard in place. Eyeball `06` and `07` before upload. "flagged: 0" alone is not enough this round.
- [ ] **Upload the iPhone sets as P1, P2, P3, P5, P6** (6.9" and 6.1"). No code needed; P4 stays out until N3 lands.

### Should fix before 1.0, but won't block review

- [ ] N3 glass crack visibility (then restore P4).
- [ ] N4 cake crush.
- [ ] N5 `01` corner.
- [ ] N7: one toast-on Duo reveal; one egg frame.
- [ ] N8: icon hash assert.

### Only the founder can do

- [ ] Sign off every caption and the final frame list (Duo inner 01–07, or 01–06; outer O1–O2; iPhone P1–P3, P5–P6).
- [ ] Frame 1 likeness: accept the 3/4 render as "app in use", or shoot one real-device photo or video. This is the only lever left above ~8.6.
- [ ] Fill the placeholders: metadata.md (`[Studio legal name]`, support, marketing and privacy URLs), privacy-policy.md, support.md and press-kit.md. Stand up the domain (`/privacy`, `/support`, `/press`). Pick the release date. Enrol in the Small Business Program.
- [ ] Create the 10 Game Center achievements in App Store Connect, with IDs matching `achievements.md` exactly.
- [ ] Subtitle choice: the £ joke (2.3.7 risk) or "The priciest hydraulic press".
- [ ] App Review notes: explain Pinch Press and "Press without folding" for non-Duo reviewers, and give θ_end as measured on hardware.
- [ ] Accessibility Nutrition Labels: declare only what's been tested.
- [ ] App Preview: none in the Duo slot, or a 6.9" Pinch Press capture only.
- [ ] Check whether App Store Connect offers the Duo inner and outer slots. If not, ship the iPhone sets and add the Duo sets by metadata edit.

### Only real hardware can settle

- [ ] Display-off angle versus `endAngle` 48°. The simulator lit the inner display at 56.6° on reopen (`reveal lit at 56.6°`); confirm that the real panel's dark window matches and that the reveal card is up when it lights.
- [ ] Does the real `closed` flag ever stick above 90° (`staleClosedAngle = 90`)? Test a slow reopen and a slam.
- [ ] Render pause: battery and thermals with the phone shut on the cover for 10 minutes. Also 120 Hz on the warped anvil during a 30 s press.
- [ ] Cold launch on the cover: idle picker, no seal.
- [ ] Settings with Press without folding on, in book pose: not letterboxed (N1's hardware twin).
- [ ] Anamorphic duck at the design eye with ±10 cm of head movement; ka-chunk and haptics against real hinge stiffness; OLED tone of the cream and the plate in daylight.
- [ ] Share clip render time and encoder on device.
