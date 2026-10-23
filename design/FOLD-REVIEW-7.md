# Fold Review 7: the set that's nearly there

*Design critic pass 7, 23 Oct 2026. Inputs (all viewed):*
- *`r7b/store-duo/duo-screens/store/`: inner `01, 02, 04–07` (2007 × 2853), outer `O1, O2` (1398 × 2034), `MANIFEST.txt`. `03-reveal-duck` is MISSING: the CI hinge tool failed the duck's reopen. A retry is in and a re-run is under way.*
- *`r7b/store-69/store/P1–P6` (1320 × 2868) and `r7b/store-61/store/P1–P6` (1206 × 2622), plus their logs.*
- *Reveal stand-ins: `glassBottle-`, `sodaCan-`, `cakeSlice-`, `jelly-storeshot-reveal.png`.*
- *Raw frames: `*-tabletop-62`, `*-tabletop-reveal`, `rubberDuck-tabletop-closed`, `duo-cover-launch`.*
- *Logs: `logs/run.txt` (3 warnings), `reveal-checks.txt`, the per-object tabletop logs and `duo-cover-launch.txt`.*
- *Repo at `8e27847`. The shipped `AppIcon-1024.png` was also rendered at 256, 60 and 29 px.*

*Coordinates are px of the file as named.*

---

## 1. Verdict

| | Score | R6 |
|---|---|---|
| **Store set, as an App Store submission** | **7.9 / 10** (≈ 8.1 once `03` lands as well as R6's duck reveal did) | 7.0 |
| **App experience, as seen in the frames and logs** | **8.2 / 10** | 7.8 |

**Store set, in one line:** the first set where every frame that exists tells the truth. It's let down by one empty frame (`P4`), one missing frame (`03`), and a shelf that's 55 % blank paper.

**App, in one line:** both ship-blocking bugs are gone and the UI is honest. What's left is object art that doesn't read as crushed (cake, jelly, glass), one visible rendering glitch (the cake candle), and an app icon that's two rounds stale.

**Would a stranger pay £2.99?**
- **A Duo owner, on the Duo set with `03` in place: yes.** Frames 1–3 then show the gesture (`01` "Close your phone", `02` "The hinge is the lever", with 111° → AT 72° glyphs) and the payoff (the reveal with its PRESSED print). That's a product nobody else has.
- **A regular-iPhone buyer, on the 6.9" set: probably yes after P4 is fixed.** `P1`, `P2` and `P3` are three clean, readable toy frames. P4 currently sells nothing.
- **Not on the Duo set as delivered today.** Without `03`, the search triplet becomes duck hero, can pair, glass hero: two "phone open on a press" pictures and no payoff.

The honest ceiling hasn't moved: the hero still reads as a small open laptop. That's mostly the hardware's fault. A Duo in tabletop pose *is* a small laptop shape. Code can't fix that; a real-device photo or a hand-in-frame shot can (founder, §6).

### Store-set scoring (weights as R1–R6)

| Dimension | Weight | Score | Why |
|---|---|---|---|
| Composition | 2.0 | **1.6** | `01` now hangs from the caption and fills ~61 % of the height. `04` is a genuinely different picture (the other end of the device). `05` is the right four objects. But: `02` still has a near-tangency; `04` clips the hinge spine on the left edge; the reveal shots crop both sides and leave a 16 % floor band; `06` is 55 % empty sheet |
| Light and material | 3.0 | **2.35** | Plate, steel and prints are good. The 18° key tilt doesn't put a visible lid shadow on the duck. Glass is still mint confetti (now with a filled centre) |
| Colour and tone | 2.0 | **1.65** | Green FIZZO everywhere (golden=0 in the logs). Jelly's magenta adds the missing hot accent. The cake is still white-on-cream |
| UI truthfulness | 2.0 | **1.6** | Settings match their captions; no "NOT AVAILABLE"; O2 is the real idle picker; every label matches its crown. **But** `P4` puts "It creaks. Then it *doesn't*." over a closed press with a 3 px sliver of shards. The shelf's meta lines end on a dangling "·" |
| Story and delight | 1.0 | **0.7** | Gesture → payoff → collection exists in the 6.9" set (P1 → P2 → P5). The Duo set lost its payoff frame this run |

Weighted: 1.6 + 2.35 + 1.65 + 1.6 + 0.7 = **7.9**.

### App experience (8.2)

**Up:**
- Closed launch is idle: `duo-cover-launch.txt` shows `phase=idle` from 6.37 s to 15.89 s with the picker on the cover.
- All four reveals that reached the reopen held to 151.4°: `storeshot reveal ok … hinge=151.4` in the glass, can, cake and jelly logs. None was replaced by the next object.
- The tabletop Shelf uses the full width.
- Settings is clean.

**Held back:**
- The cake candle stretches into a long striped needle past the plate (§4 N3).
- The cake still reads as an intact wedge with cream blobs.
- The jelly reveal is an unsquashed pink dome under a "SKIN SPLIT · SPLAT" label.
- Glass is a confetti scatter.
- On the Duo the Shelf leaves its lower half empty.
- The committed app icon is still the magenta "tongue" press (§4 N1).

---

## 2. Status of every FOLD-REVIEW-6 item

| # | R6 item | Status | Evidence (R7) |
|---|---|---|---|
| **N1** | Hero reads as an open laptop | **Partly: as far as code can take it** | The log has `az=50 el=22 tilt=18 readout=AT 65°`, the V glyph and "AT 65°" are on the sweep (x ≈ 1360–1810, y ≈ 680–800), and the fill is up. On screen the lid–base angle measures ~84° against a 64° model, so it is more closed than R6's ~100°. **But** the tilted key leaves no readable shadow on the duck, and the silhouette is still "mini laptop". The remainder is a founder decision (real-device photo), not code |
| **N2** | Reveal dismissed by a stray `closed` | **Fixed** | `RevealCollectGate.swift` plus `PressEngine.staleClosedAngle = 90` (PressEngine.swift:190–196). Four of four completed reopens held the reveal at 151.4°. The duck's failure is the CI tool: run.txt:307–316, `sweep exited non-zero`, last sample `7.2 1 phase=sealed`, so the hinge never reopened. CI marked it MISSING instead of substituting: correct |
| **N3** | Closed launch seals a phantom press | **Fixed** | `duo-cover-launch.txt`: `phase=idle depth=0.000` throughout. `O2` shows the chip grid and "Open to press" |
| **N4** | Tabletop Shelf in the right half only | **Fixed, but exposed a new problem** | The grid spans the sheet (5 columns, x ≈ 340–1670) and the sheet opens full height. **Now the grid ends at y ≈ 1690 and y ≈ 1690–2740 is empty cream** (§4 N5) |
| **N5** | Settings contradict caption; "NOT AVAILABLE" | **Fixed** | `07`: Soft on, Press without folding on, Captions on. Game Center row hidden in the demo; the Release copy is neutral (SettingsView.swift:164–167). `P6` has no status word |
| **N6** | Golden can | **Fixed** | `golden=0` in the logs; green FIZZO in `02`, `05` and `P3` |
| **N7** | 01/03 identical; order | **Fixed in code; the frame is missing in this run** | Glass has its own camera: `04` shows the opposite end. `MANIFEST.txt` order: hero, pair, reveal, glass, grid, shelf, settings |
| **N8** | P2 shows nothing | **Not fixed: moved to P4** | Bubble wrap was replaced by glass at `depth=0.66` (ci/scenarios.txt:97). At that depth the bottle has failed and flattened, so `P4` is the same empty-press picture (§4 N2) |
| **N9** | Egg and cake not crushed | **Egg unverified; cake partly** | Egg isn't in this run. Cake: cream lumps and crumbs now bulge out (CakeSquash), but from above it's still a full wedge outline. A new candle glitch appeared (§4 N3) |
| **N10** | Glass ring with a hole | **Partly** | The centre is filled now (`04`, x ≈ 760–1270 / y ≈ 1760–2010). It still reads as flat mint confetti, not a heap |
| **N11** | Widows and orphans | **Fixed in captions; regressed in-app** | `P1` sub-line is one line; `P6` headline breaks at sentences. The in-app orphan guard (`keepingLastWordsTogether`, SettingsView.swift:316) now produces "Follows your iPhone / setting (Settings › Accessibility › Motion)." in `P6` (y ≈ 2345–2390) (§4 N7) |
| **N12** | Dead band under the caption | **Moved, not removed** | The band under the caption is gone. The device is width-limited, though, so the empty space is now a floor: `01` y ≈ 2430–2853 (15 %), `04` ≈ 11 %, reveal shots ≈ 16 %. A floor reads better than a gap; acceptable for `01` and `04` |
| **N13** | Island pill inconsistent | **Fixed** | All twelve P-frames have the pill |
| **N14** | Pinch handle behind the Shelf | **Fixed** | `P5`: no handle on the crosshead |
| **N15** | CI hides failures | **Fixed for the Duo set; open for the P-sets** | `store-set.sh` printed `03 … MISSING`, `missing: 1`, and refused to substitute. Nothing checks P-frame content, which is why `P4` sailed through (§4 N2) |
| F4 | Toast slot verified | **Still unverified** | Every run used `notoasts` |
| N8 (R5) | Icon reads as a tongue | **Not done: stale asset** | AppIconArt.swift:5–7 draws a duck, but `Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` was last committed in `bd67039` and is still the magenta jelly in a classic press. At 60 px it reads as a pink mouth (§4 N1) |
| R5 N11 | Jelly overflow | **Acceptable** | The jelly spills past the strike plate but stays well inside the screen (`05`, raw `jelly-tabletop-62`) |
| Frame `01` | | **Ship** | §3 |
| Frame `02` | | **Fix (S)** | The tangency is still there (§3) |
| Frame `03`/`04` (old) | | **Glass done; duck reveal pending re-run** | |
| Frame `05` (old shelf) | | **Fix** | It's now `06`: full width, half empty |
| Frame `06` (old grid) | | **Ship** | It's now `05` |
| Frame `07` | | **Ship** | |
| `O2` | | **Ship** | |
| `P2` (old) / `P4` (new) | | **Cut until fixed** | |
| `P6` | | **Ship after S fix** | |

---

## 3. Frame-by-frame verdict

**Rules applied:**
- Guideline 2.3: show only what the app renders.
- No prices.
- Headline legible at thumbnail size.
- Frames 1–3 must each sell alone.

**Guideline status:**
- No prices anywhere.
- No folded device outside the Duo set.
- All captions are legible at 25 %.

### A. iPhone Duo inner (2007 × 2853)

| # | Frame | Verdict | Problem → fix |
|---|---|---|---|
| **01** | Duck hero | **SHIP** | Best version yet. The V glyph plus "AT 65°" make the angle explicit, the flattened duck and its lid print are both visible, and the caption is strong. **Optional:** the base's front-left corner is clipped by the left edge (x 0, y ≈ 1700–1850); the 18° key tilt leaves no visible shadow on the duck. Leave both unless re-rendering anyway |
| **02** | Can pair | **FIX (S), then ship** | The small device's front-right corner still meets the large device's lid corner at x ≈ 660–730, y ≈ 1295–1340, with **~15–25 px clear**. The comment claims ~60 px. The boxes themselves are only 14 px apart: `beforeUnit` ends at y 0.465 (1327 px), `afterUnit` starts at 0.47 (1341 px). **Fix:** FoldStoreShot.swift:401–403, `beforeUnit.height` 0.25 → 0.23, or `afterUnit.y` 0.47 → 0.50. Labels, glyphs, arrow and the green can are all right |
| **03** | Duck reveal | **MISSING → re-run** | No frame. CI did the right thing. **If the re-run fails again,** use `sodaCan-storeshot-reveal.png`: the best of the four stand-ins (a crushed lid in green fizz, "SODA CAN · 5 BUCKLES · AT 72°"), and it completes the can story from `02`. **Either way, apply §4 N4 first:** every reveal shot crops the device off both side edges and leaves a 16 % floor (y ≈ 2390–2853) |
| **04** | Glass hero | **SHIP** (fix the clip if re-rendering) | A different picture now, with the cracked-glass lid print, "AT 81°", and the other end of the device. **Problem:** the hinge spine, the one "this is a foldable phone" cue at this end, is cut by the left edge (x 0, y ≈ 1450–1950). **Fix:** per-object `bleed` 0.10 → 0.04 for the glass camera, or a 3 % x-inset clamp in `deviceDraws` so the hinge end never leaves the frame (FoldStoreShot.swift:585–590). The pile is better but still confetti (§4 N8) |
| **05** | Variety grid | **SHIP** | Glass, can, cake and jelly, each labelled with its readout. The jelly's magenta print is the most graphic image in the set. The cake is the weak cell: an intact white wedge with the stretched candle visible as a hairline at x ≈ 380–430, y ≈ 2370 (§4 N3). It improves for free when N3 lands |
| **06** | Shelf | **FIX (S/M)** | **(1)** The grid occupies y ≈ 1000–1690, and **y ≈ 1690–2740 is empty cream**: 37 % of the frame, 55 % of the sheet. In a "shelf of specimens" frame that reads as "not much here". **(2)** Meta lines wrap as "PERFECT · / №0001", leaving a "·" dangling at the line end, on 4 cards. **(3)** The secret slot truncates: "SOME THINGS REFUSE TO BE S…". **(4)** Names sit at different heights (the Rubber Duck name drops for its sticker). **Fix in the app** (§4 N5, N6), not by cropping |
| **07** | Settings | **SHIP** | The state matches the caption. Optional: the second sheet edge peeking above (y ≈ 660–700) is a stacked-sheet artefact; harmless |

### B. iPhone Duo outer (1398 × 2034)

| # | Frame | Verdict | Notes |
|---|---|---|---|
| **O1** | Sealed, overlay | **SHIP** | "57 TONS", the print teaser and "OPEN TO SEE" read at thumbnail size |
| **O2** | Idle cover picker | **SHIP** | A truthful frame now: recent strip, ON THE ANVIL, chip grid, "Open to press". The column sits ~115 px left of centre because it centres in the safe area left of the clock column (CoverView.swift:30–32). On hardware the clock fills that column, so this is honest. The camera disc is real hardware |

### C. iPhone 6.9" and 6.1": identical verdicts

| # | Frame | Verdict | Notes |
|---|---|---|---|
| **P1** | Duck mid-press | **SHIP** | The sub-line is one line now. Gauge needle ~25 |
| **P2** | Duck reveal | **SHIP** | "CRUSHED AT 56 TONS", "He'll be fine. Probably." The best non-Duo frame |
| **P3** | Can buckle | **SHIP** | Green FIZZO, with the rim rolling over under the ram |
| **P4** | Glass crack | **CUT until fixed** | The ram is down on the plate and the bottle is a 3 px sliver of shards (6.9": y ≈ 2240–2260). The log shows `depth=0.660`, past the ~0.40 compression failure (GlassBottleView.swift:9, 86). This is R6's P2 problem again. **Fix:** `depth=0.50` (tune ±0.02 so the crack lines show on an upright bottle, between fracture 0 at ~0.22 and failure at ~0.40 compression), ci/scenarios.txt:97. **Until then, ship 5 frames:** P1, P2, P3, P5, P6 |
| **P5** | Shelf | **SHIP** | Two large cards plus the ON THE ANVIL sticker; no handle. It shows only 2 of 10 objects, which is fine for a compact phone |
| **P6** | Settings | **SHIP after S fix** | Balanced headline. Fix the "Follows your iPhone / setting (…)" break (§4 N7) |

**Never upload:**
- `*-eye`, `*-112` and raw `*-tabletop-*` frames;
- `*-storeshot-hero` other than duck and glass;
- `P4` as rendered;
- `03` from any object other than the duck or the agreed can fallback.

---

## 4. New issues, ranked

### N1. The shipped app icon is two rounds stale — **S**, launch blocker
- **File:** `Squish/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`, last committed in `bd67039`.
- **Problem:** it's the old magenta jelly in a classic press. AppIconArt.swift:5–7 describes, and draws, a folded device biting a yellow duck. At 60 px and 29 px the committed icon is a pink mouth between yellow jaws, and it has no fold or Duo cue at all. The icon is the one asset in every search result.
- **Fix:**
  - re-run the CI icon render (the `82ff51c` path) and commit the 1024 master;
  - then review it at 60 and 29 px against the Duo hero, so the yellow duck doesn't merge with the hazard yellow at small size (the `duckRamp` comment at AppIconArt.swift:105 says it shouldn't; check it).
  - Add a CI assert that the committed PNG's hash matches a fresh render.

### N2. P4 shows an empty press, and nothing checks P-frame content — **S**
- **Files:**
  - ci/scenarios.txt:97 (`object=glassBottle;depth=0.66`);
  - `ci/screenshots.sh` has no content check.
- **Fix:**
  - `depth=0.50`; tune until the log shows fracture 0 but not the failure.
  - Have the P-frame scenarios log the object's phase or fracture index, and fail the frame when a "crack" scenario has already failed. That's the same idea as the Duo set's `REVEAL NOT UP` refusal.

### N3. The cake candle stretches into a long needle after it bends — **S**, visible in the real app
- **Frames:**
  - raw `cakeSlice-tabletop-62` and `-reveal`: a pink-and-white striped spike from the wedge to past the plate edge, toward the bottom-left;
  - visible as a hairline in `05`.
- **Cause:** CakeSliceView.swift:184–189.
  - Once bent, the candle is rotated ~83° about Z (l.185), so its length axis is now nearly horizontal.
  - It still gets `1 / s` on its local Y (l.189) to undo the parent's vertical squash.
  - The parent `cake` is scaled `(k, s, k)` (l.162), so the counter-scale now multiplies the candle's *length* by up to 1/0.15 ≈ 6.7×, and the non-uniform parent scale shears it.
- **Fix:** on bend, re-parent `candlePivot` from `cake` to the unscaled `entity`. Position it at `cakeTop` and scale only its thickness. Or drop the `1/s` term once bent. Add a SceneTests check: the candle's world AABB stays inside the plate footprint at c = 1.

### N4. Reveal shots crop the device at both sides and leave a 16 % floor — **S**
- **Frames:** all four `*-storeshot-reveal.png`, and `03` when it lands.
- **Cause:** FoldStoreShot.swift:585–594.
  - At ~151° from a 34° eye, the open device projects wide and short.
  - `.width(bleed: 0.10)` plus `targetFill 0.66` pushes the width 10 % past the frame, so the lid's free corner and the base's front corner are cut.
  - The height still only reaches ~44 %.
- **Fix:** for the reveal pose, use `bleed: 0`. Anchor `.centre` in the box below the caption, or raise its elevation to ~40–44° so the near-flat device projects taller. Don't chase `targetFill` on a wide pose.

### N5. The Duo Shelf leaves its lower half empty — **S/M**
- **Frames:** `06` and `duo-shelf`.
- **Cause:** ShelfView.swift:46–58. `wide` means 5 fixed columns, so 10 objects make 2 rows of small cards, whatever the sheet height. At `.large` on the Duo the sheet is ~1.4× taller than wide.
- **Fix (one of):**
  - **(a)** When `wide` and the height ≥ 1.2 × the width, use 4 columns and size the cards to fill the height (3 rows, so the "???" sits in row 3); or
  - **(b)** Keep the 5×2 grid on the ram half and put a "Recently squished" strip of the last 4 prints (the same thumbnails the cover uses) on the anvil half.
  - (b) is more Duo-native: the collection sits above, the evidence below the crease.

### N6. Shelf card meta wraps badly — **S**
- **Frames:** `06` (cards 1, 3, 5, 6).
- **File:** ShelfView.swift:404–420 (`bestLine`, `.lineLimit(2)`).
- **Problems:**
  - " · " joins the parts, so a two-line wrap ends line 1 on "·";
  - the hint for the secret slot truncates at 2 lines.
- **Fix:**
  - in the 5-column layout, join with "\n" (GOLDEN / PERFECT on line 1, the № on line 2), or apply `keepingLastWordsTogether` to the separator;
  - hint `.lineLimit(3)`, or a shorter hint ("REFUSES TO SQUISH").

### N7. The in-app orphan guard creates a worse break — **S**
- **Frame:** `P6` (6.9" y ≈ 2345–2390; 6.1" the same).
- **Cause:** SettingsView.swift:316–319. `keepingLastWordsTogether` replaces the last space with a no-break space. Line 99's footnote already ends in a no-break path (`settingsPath`, l.197–198), so "setting (Settings › Accessibility › Motion)." becomes one unbreakable 40-character unit, and "setting" falls to line 2.
- **Fix:** skip the join when the last word is longer than ~12 characters or already contains U+00A0. Or write that footnote as two lines on purpose: "Follows your iPhone setting:" / path.

### N8. Glass still reads as confetti — **M**
- **Frames:** `04`, `05`, `glassBottle-tabletop-62` and `-reveal`.
- **File:** GlassBottleView.swift, pile and shard placement (~l.170–210, 559–580).
- **Problem:** the centre is filled now, but every shard is a same-size, same-tint, flat, matte polygon.
- **Fix:**
  - vary the shard size 3× (a few 20–22 mm pieces near the centre);
  - add a thin bright rim or specular edge so they read as glass rather than paper;
  - tilt 20 % of them up off the plate.

### N9. The jelly reveal reads unsquashed — **M**
- **Frames:** `jelly-tabletop-reveal`, `jelly-storeshot-reveal`.
- **Problem:** "SKIN SPLIT · SPLAT" sits over a smooth pink dome, the same silhouette as the 62° hold.
- **Fix:** after the split, let the dome relax to ≤ 35 % of its height and spread into a lobed puddle that matches the lid print's outline. Add one visible tear in the skin.

### N10. The inner fold scene keeps ticking while the phone is shut — **S to verify**
- **Evidence:** `duo-cover-launch.txt`. `SQUISH-F frame 240/480/720 … fold: no layout/solution (viewSize (0.0, 0.0))` and `frame 600 at 15.89s`: the inner pipeline runs at ~60 fps on a zero-size window while closed.
- **Files:** FoldPressView.swift and FoldPressController.swift:492.
- **Fix:** pause the inner scene's updates (or drop them to a low rate) while the inner window has zero size or the hinge is closed. Keep hinge sampling alive. Check battery and thermals on hardware either way.

### N11. Minor
- **Hero corner clip:** `01` and `04` (§3), plus the pair tangency (§3 `02`).
- **Shelf name baselines:** the Rubber Duck's name drops for its sticker (ShelfView caption layout). Reserve the sticker's height on every card.

---

## 5. Top 5 fixes and honest projection

1. **Land `03`.** Re-run the duck, and apply N4 (reveal fit: bleed 0, centred, elevation ~42°) before it does. If the duck fails again, ship the can reveal as `03`.
   - **S. Set +0.25.** It restores the payoff to the Duo search triplet.
2. **Fix or drop `P4`** (N2): depth 0.50 plus a P-frame content check. Until it's right, ship five frames.
   - **S. Set +0.15** (6.9"/6.1").
3. **Render and commit the real app icon** (N1), and review it at 60 and 29 px.
   - **S. Launch blocker.** Conversion matters more than any single screenshot.
4. **Shelf and copy hygiene:**
   - N5: fill the Duo Shelf, preferably with the "recently squished" strip on the anvil half;
   - N6: meta wrap and hint;
   - N7: the Settings footnote;
   - the pair separation (FoldStoreShot.swift:401–403).
   - **S/M. Set +0.15, app +0.1.**
5. **Objects that read as crushed:**
   - N3 candle (S, do it first);
   - cake height and outline: the wedge must visibly widen and flatten from above, not just sprout blobs;
   - N9 jelly puddle;
   - N8 glass.
   - **M. App +0.2, set +0.1.**

**Projection:**
- **Set:** 7.9 → **~8.4** after all five, ~8.2 if only 1–3 land.
- **App:** 8.2 → **~8.5**.

Past 8.5 needs what R5 and R6 said: a real-Duo photo or video for frame 1 (scale and hands-free context, so it stops reading as a laptop), or a true side-on "into the fold" view. Code can't buy that.

---

## 6. Is the code/art side launch-ready for 1.0?

**Not quite. It's close: four small items, about a day of work plus one CI run.** The two ship-blocking bugs from R6 are fixed and verified in the logs. What's left is narrow.

### Blocks a 1.0 submission (code and art: dev closes these)

- [ ] **N1:** commit a freshly rendered `AppIcon-1024.png` from AppIconArt and eyeball it at 60 and 29 px. The current asset is the art the founder already rejected.
- [ ] **N3:** the cake candle stretch. It's a visible rendering bug on every cake press in the shipping app.
- [ ] **A complete 6.9"/6.1" set:** fix `P4` (N2) or upload P1, P2, P3, P5, P6 only. Five frames is allowed; an empty-press frame is not acceptable.
- [ ] **A green store run:** `store-set.sh` exits 0 with `03` present (or the can fallback, signed off), and `MANIFEST.txt` shows `missing: 0 flagged: 0`.

### Should fix before 1.0, but won't block review

- [ ] N4 reveal fit; N5 Duo Shelf fill; N6 shelf meta wrap; N7 the Settings footnote; the `02` separation; the `04` hinge clip.
- [ ] N10: confirm the closed-phone render loop isn't burning battery (or pause it).
- [ ] F4: one Duo reveal **with** toasts, to see the achievement toast slot (never verified across 7 rounds).
- [ ] Egg: render one egg tabletop frame to confirm the R7 yolk change (not seen this round).
- [ ] N8 and N9 glass and jelly: art polish; fine for a 1.1.

### Only the founder can do

- [ ] Sign off every caption, and decide the `03` fallback (the can reveal) if the duck re-run fails.
- [ ] Decide the frame-1 likeness question: accept 3/4 renders as "app in use", or shoot one real-device photo or video.
- [ ] Fill the placeholders: metadata.md:188–191 (`[Studio legal name]`, `[domain]` support, marketing and privacy URLs), privacy-policy.md:3 and :35, support.md:3 and :58–59, press-kit.md. Pick the release date. Enrol in the Small Business Program.
- [ ] Create the 10 Game Center achievements in App Store Connect.
- [ ] Accessibility Nutrition Labels: declare only what's tested.
- [ ] App Review notes: explain Pinch Press and "Press without folding" for non-Duo reviewers.
- [ ] Subtitle choice ("The £2,000 hydraulic press" vs the fallback).
- [ ] App Preview: none in the Duo slot, or a 6.9" Pinch Press capture only.

### Only real hardware can settle

- [ ] Does the real Duo's `closed` flag ever stay set above 90° (the simulator does)? `staleClosedAngle = 90` (PressEngine.swift:193) assumes the angle is right when they disagree. Test a slow reopen and a fast slam.
- [ ] Cold launch on the cover: idle picker, no seal (fixed in the simulator; confirm on device).
- [ ] Display-off window (55–20°) against the reveal timing: the reveal starts at 20.1° in every log, inside the dark window. Confirm the card is up by the time the screen lights.
- [ ] Anamorphic duck at the design eye with ±10 cm head movement; ka-chunk and haptics against real hinge stiffness; 120 Hz thermals during a 30 s press; OLED tone of the cream and the plate in daylight.
- [ ] App Store Connect: whether the Duo inner and outer slots are selectable. If not, ship 6.9"/6.1" first and add the Duo set by metadata edit.
