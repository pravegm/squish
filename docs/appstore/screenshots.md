# Squish: App Store screenshot storyboard

*Owner: dev captures, founder approves. Every frame is real in-app footage captured with the demo launch argument. Captions are overlaid afterwards. No hands, no device photos, no real objects and no prices (Guideline 2.3.7 bars prices in screenshots).*

## Specs used

| Set | Pixel size (portrait) | Frames | Notes |
|---|---|---|---|
| **iPhone Duo, inner display** | **2007 × 2853** | 6 (+1 optional) | The hero set. The fold runs horizontally through the middle, with the anvil below and the ram housing above |
| **iPhone Duo, outer display** | **1398 × 2034** | 2 | Cover-display moments |
| **iPhone 6.9"** (Dynamic Island, large) | **1320 × 2868** (1290 × 2796 and 1260 × 2736 are also accepted) | 6 | Pinch Press on a regular iPhone |
| iPhone 6.5" (Face ID, large) | 1284 × 2778 | 6 (re-capture of the 6.9" set) | Required only if no 6.9" set is supplied. Capture it anyway: it takes 10 minutes with the demo args |

Rules: 1–10 screenshots per size, `.png` or `.jpg`, **no alpha channel**. The first 3 frames of each set appear in search results, so **frames 1–3 must each sell the app on their own**.

> **Heads-up for upload day:**
> - (a) Apple's spec page lists the iPhone Duo sizes, but a developer forum thread reports that the App Store Connect device selector and the API don't list iPhone Duo yet. If it's still missing at submission, upload the 6.9" set and add the Duo sets as soon as the slot appears. A metadata edit like this doesn't need a new build.
> - (b) Apple's page says Duo screenshots become **required from April 2027** for apps built with the iOS 27.1 SDK, and that providing them adds the Duo badge to the product page.
> - (c) The spec page currently marks the 6.1"-class (Dynamic Island, medium; 1206 × 2622) as required. If App Store Connect refuses to scale down from 6.9", re-capture this set at 1206 × 2622.

## Visual system for captions

- **Placement:**
  - On inner frames, the caption sits in the **top half**, over the ram housing. The anvil and object below stay clean, and the caption must never cross the crease band (the middle ~6% of the image).
  - On outer and 6.9" frames, the caption sits in a top band about 22% of the height.
- **Type:** SF Pro Rounded Heavy, graphite `#2B2D31` on studio off-white `#F3EEE6`, with **one word** highlighted in hydraulic yellow `#FFB81C`. Optional small second line in SF Mono at 40% size.
- **Size:** headline cap height ≥ 4% of the image height, so it's legible as a search-results thumbnail. **Seven words maximum** per headline.
- **Brand:** no logo on frames 2–6. The product page already shows the icon and name.
- **Truthfulness:** never show an effect the frame's demo state doesn't actually render.

## Demo launch argument

Format: `-squishDemo "key=value;key=value;flag"`

| Key | Values |
|---|---|
| `object` | bubbleWrap, rubberDuck, jelly, crayon, egg, cakeSlice, sodaCan, gummyBear, glassBottle, unsquishable |
| `depth` | 0…1 |
| Flags | reveal, shelf, settings, cover |

The depth values below are **starting points [tune]**. Failure usually lands at compression c ≈ 0.3–0.6, which is depth ≈ 0.44–0.68 (bible §6.2). Step ±0.02 until the frame catches the signature moment.

---

## A. iPhone Duo, inner display (2007 × 2853): 7 frames

The set as re-cut in design/FOLD-REVIEW-6.md §3 A (order N7: gesture and payoff in the search-results triplet, the device's phone-ness by frame 3). Frames 1–5 are **store shots**: the live Fold Press halves, captured on the real Duo simulator in tabletop pose, mapped onto a folded Duo model seen from a 3/4 eye (`FoldStoreShot.swift`). A raw inner frame reads as "two flat trays", so it never goes in this set, except the Shelf and Settings, which aren't anamorphic.

| # | Frame | Caption (headline / sub-line) | Source (`duo-screens/…`) |
|---|---|---|---|
| **1** | Rubber Duck hero: the failure freeze at the 62° hold (never modelled below 58°: the real screen is dark from 55°), seen from a **22° elevation and 50° turn** so the device's end shows the wedge closing (~96° on screen, was ~133°). The readout label and V glyph ("AT 67°") sit on the sweep above the lid; the key light leans 18° toward the viewer so the lid's shadow falls across the duck. The device hangs from the caption band (fill 0.66 / bleed 0.10), so there's no dead band | **Close your phone. Feel it *give*.** / *Squish turns the fold into a hydraulic press.* | `rubberDuck-storeshot-hero.png` |
| **2** | Soda Can before/after (seed 3: the plain green FIZZO can, never Golden): small device at 112°, large at the squish. Each label quotes its own crown readout ("111°" → "AT 74°") beside a side-profile V. FOLD-REVIEW-7: the small box is 0.23 tall and the large one starts at y 0.48, so the small device's front corner clears the large lid by ≥ 60 px (it was 15–25 px) | **The hinge is the *lever*.** | `sodaCan-storeshot-pair.png` |
| **3** | Tabletop reveal, reopened to ~151°: flat duck on the anvil, the PRESSED print and its "AT 67°" label on the lid, Again · Share · Next in the console. FOLD-REVIEW-7 N4: seen from a **42° elevation**, width-fitted with **no bleed** and **centred** under the caption, so the whole device is in frame (80 px clear at each side, hinge spine included; ≈ 61 % of the height, a ~10 % floor). The R6 fit (bleed 0.10, hung from the caption) cut both sides and left a 16 % floor. CI asserts the reveal is still up at the capture; if not, the frame is MISSING, never the next object. **If the duck reveal is MISSING**, `ci/store-set.sh` uses the can reveal as `03-reveal-can.png`, listed as a **FALLBACK** that the founder must sign off (`STORE_REVEAL_FALLBACK_APPROVED=1`); until then the run stays red. No other object is ever substituted | **Open up. File the *evidence*.** / *Every press becomes a specimen.* | `rubberDuck-storeshot-reveal.png` (fallback `sodaCan-storeshot-reveal.png`) |
| **4** | Glass Bottle hero from **its own camera** (−28°, the other end of the device, 34° elevation), with its AT nn° mark. Bleed 0.04 (FOLD-REVIEW-7 §3 A 04), so the hinge spine at the left end stays in frame | **It creaks. Then it *doesn't*.** | `glassBottle-storeshot-hero.png` |
| **5** | Variety: glass, can, cake and jelly on one sweep (not the duck again), each labelled with its object and frozen readout ("JELLY · AT 88°") | ***Ten* objects. Ten ways to give.** | `duo-storeshot-grid.png` (fallback `jelly-storeshot-hero.png`) |
| **6** | The Shelf, raw portrait inner frame at full height (the Duo opens it at `.large`; seeded 7/10, one Golden), framed under its caption | **A shelf of pressed *specimens*.** / *No ads. No in-app purchases.* | `duo-shelf.png` → `ci/store-set.sh` |
| **7** | Settings sheet, raw, framed. Demo state matches the caption: Sound style **Soft**, **Press without folding** on, Captions on, Game Center status hidden (`soundstyle=soft;nofold;captions=on;gamecenter=hidden`) | **Press without folding. Hear it *softer*.** / *Accessibility built in.* | `duo-settings.png` → `ci/store-set.sh` |

Per-object hero captions (`heroCaption(for:)` in PressDirector.swift): duck as frame 1, glass as frame 4, can "Cans buckle *ring* by ring.", bubble "Every bubble *pops* on its own.", everything else the variety line. Per-object hero cameras: `heroCamera(for:)` (overrides `storeshotazimuth=`, `storeshotelevation=`, `storeshotkeytilt=`, `storeshotbleed=`). The reveal's elevation: `revealelevation=` (default 42°). Framing is checked offline with `r7tools/framing3.mjs` (`reveal` and `pair` modes; a replica of the StoreRig, camera and fit).

**Line breaks** (both renderers, FOLD-REVIEW-6 N11): a headline too wide for one line breaks at its most balanced sentence boundary; each wrapped paragraph is balanced (no lone last word); a paragraph still ending on one word shrinks the headline a step; the sub-line shrinks (to 0.30 of the headline size at the least) to stay on one line before it wraps.

**Never upload:** `*-eye` composites, `*-book-storeshot-*`, raw `*-tabletop-*` frames, the `-112` singles, and any `9A–9D` / `90–99` frame (an iPhone 18 Pro drawn folded, Guideline 2.3). A pair whose label disagrees with its readout can't be produced any more: both labels come from the readout.

## B. iPhone Duo, outer display (1398 × 2034): 2 frames

| # | Frame | Caption | Source |
|---|---|---|---|
| **O1** | The cover right after the press: PRESS SEALED card, print teaser, tonnage. Caption drawn in off-white over the empty graphite top band | **Ka-chunk. Now *open* it.** | `rubberDuck-tabletop-closed.png` (tabletop pass) or `rubberDuck-closed.png` (book pass) |
| **O2** | Launched with the phone already shut (7 seeded specimens, nothing pressed): the cover's idle picker (chip grid, "Open to press"), framed. A closed launch no longer arms or seals (FOLD-REVIEW-6 N3); `ci/store-set.sh` flags O2 if the launch log shows the engine leaving idle | **Pick on the cover. Press *inside*.** | `duo-cover-launch.png` |

## C. iPhone 6.9" (1320 × 2868) and 6.1" (1206 × 2622): 6 frames (Pinch Press)

Captured on the newest "… Pro Max" simulator (6.9") and on the iPhone 18 Pro (6.1" slot, heads-up c). Because there's no hinge, Pinch Press is on automatically. Scenarios `P1`–`P6` in ci/scenarios.txt; the 4th column is the caption and the 5th the **content check** (FOLD-REVIEW-7 N2): fields the app's `SQUISH-T demo press done … c= fractures= failed= kind=` and `SQUISH-T demo reveal up … revealed=1 golden= surprise=` lines must show at the moment of the screenshot. A frame that fails is FLAGGED in `store/MANIFEST.txt`, gets no captioned copy, and `ci/screenshots.sh` exits 5 after the whole set is captured.

| # | Scene | Caption | Demo argument | Content check |
|---|---|---|---|---|
| **P1** | Rubber Duck mid-squash (the handle hides during a press, by design) | **Drag it down. Feel it *give*.** / *A hydraulic press for every iPhone.* (the sub-line shrinks to one line) | `object=rubberDuck;depth=0.55;seed=3;notoasts` | `kind=rubberDuck,phase=pressing,failed=0` |
| **P2** | Duck reveal ("CRUSHED AT 56 TONS") | **Open up. File the *evidence*.** | `object=rubberDuck;reveal;seed=3;notoasts` | `kind=rubberDuck,revealed=1,golden=0,surprise=none` |
| **P3** | Soda Can buckling (green FIZZO) | **Cans buckle *ring* by ring.** | `object=sodaCan;depth=0.55;seed=3;notoasts` | `kind=sodaCan,phase=pressing,fractures>=1` |
| **P4** | Glass Bottle cracking under the ram, still standing. FOLD-REVIEW-7 N2: depth 0.66 (c 0.51) was past the seed-3 failure (c 0.412), an empty press; **depth 0.52** is c 0.314, cracked (crack at c 0.197) with the crack lines ~55 % grown and 0.07 of depth short of the failure | **It creaks. Then it *doesn't*.** | `object=glassBottle;depth=0.52;seed=3;notoasts` | `kind=glassBottle,phase=pressing,fractures>=1,failed=0` |
| **P5** | The Shelf (seeded 7/10) | **Collect every pressed *specimen*.** | `shelf;notoasts` | the demo started (no app-side sheet line yet) |
| **P6** | The Settings sheet, Game Center status hidden | **No ads. No purchases. *Just* the press.** / *Sound styles, haptic levels, Reduce Motion.* | `settings;gamecenter=hidden;notoasts` | the demo started (no app-side sheet line yet) |

Every captioned frame gets the same Dynamic Island: `ci/store-frame.swift --island pill` draws it on the screen card (the simulator captured it in some frames and not others, FOLD-REVIEW-6 N13; `STORE_ISLAND=none` turns it off).

Check P1 for the ram handle before upload (request 4 below). Never a folded device in these sets.

## Rendering the set (CI)

Run **Actions → App Store screenshots** (`.github/workflows/store.yml`, manual). It produces three artifacts:

- **store-69**: P1–P6 on the 6.9" simulator, raw (`P*.png`) and captioned (`store/P*.png`), with `store/MANIFEST.txt` (each frame's logged state, or why it is FLAGGED) and `logs/P*.at-capture.txt` (the log as it stood at the screenshot). Each frame is checked to be 1320 × 2868 (the job fails with exit 4 if the simulator is the wrong class) and against its content check (exit 5; the 6.1" step still runs). `DEVICE=auto:Pro Max` picks the newest available Pro Max and creates one if the image has none; the step log lists the device types found.
- **store-61**: the same on the iPhone 18 Pro (1206 × 2622).
- **store-duo**: duo.yml called with the store settings (no book pass; tabletop passes for duck, glass, can, cake, jelly with `storeshot=112,fail,reveal` and `seed=3`; the Shelf, closed-launch cover and Settings; the grid), assembled by `ci/store-set.sh` into `duo-screens/store/duo-inner/01…07` and `duo-outer/O1, O2`, with `MANIFEST.txt` (source and caption per frame, size and alpha checks, and log checks: each store shot's `ok` line, the reveal still up at its capture, `golden=0` for the representative objects, the settings demo state applied, O2 from an idle launch). `store-set.sh` exits 1 when a frame is MISSING or FLAGGED, or when 03 is the can FALLBACK and `STORE_REVEAL_FALLBACK_APPROVED=1` isn't set.

Captions on raw frames are drawn on the Mac runner by `ci/store-frame.swift` (`framed`: studio sweep, caption band, the unaltered screenshot on a black screen card; `overlay`: caption straight over the frame's top band). Store shots are captioned in the app by `FoldStoreShot`. Both use the same band and shrink rule.

Locally, with a booted simulator: `DEVICE="auto:Pro Max" OUT=store-69 SCENARIO_FILTER='^P[0-9]-' EXPECT_SIZE=1320x2868 STORE_FRAMES=1 bash ci/screenshots.sh`, and `bash ci/store-set.sh duo-screens` after a Duo run.

---

## Content checklist (founder sign-off per frame)

- [ ] No real hands, people or physical objects anywhere. Nothing suggests putting anything between the halves.
- [ ] No prices (the "£2,000" joke lives in the subtitle only).
- [ ] No Hydraulic Press Channel look: no workshop with a red hydraulic press and no characters. We use the studio off-white and graphite world.
- [ ] No creatures or faces on destroyed objects. The duck has no pained expression.
- [ ] Glass is chunky and soft-edged. No trypophobic hole clusters in the bubble wrap close-up.
- [ ] The secret object never appears. Its slot shows "?" only.
- [ ] The Golden card in the Shelf is a real seeded Golden result, not a mock-up.
- [ ] Captions are readable at thumbnail size (view at 25%).
- [ ] Files are PNG with no alpha (flatten on export).

## Requests for dev (open questions)

1. **Freeze the seed:** *(done: `seed=<int>`)* add `seed=<int>` to `-squishDemo`. Without it, the crack pattern and failure threshold change between captures, so depth=0.62 might land before the glass breaks.
2. **Freeze a moment in time:** add `t=<seconds since failure>` (or a `freeze` flag) so debris can be caught mid-air for frames 3 and 4. `depth` alone defines the static deformation but not where the particles are.
3. **Seeded collection:** *(done: `shelf`, `settings`, `detail` and `cover` seed 7/10 with one Golden; `specimens=N` seeds N without opening a sheet)* add `collection=7` (or a demo fixture) so `shelf` shows 7/10 filled with one Golden card.
4. **Pinch Press handle:** confirm the handle is visible in a frozen `depth` state on non-Duo devices.
5. **Combined flags:** confirm that `cover;shelf` gives the closed-launch trophy shelf and that `object=…;depth=1;cover` gives the sealed card.

---

## Sources

- App Store Connect Help, *Screenshot specifications* (iPhone Duo outer 1398 × 2034 and inner 2007 × 2853; 6.9" 1320 × 2868 / 1290 × 2796 / 1260 × 2736; 6.5" 1284 × 2778 / 1242 × 2688; 1–10 per size; no alpha; Duo screenshots required from April 2027 for iOS 27.1 SDK builds): https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications
- Apple Developer Forums, "How do I upload iPhone Duo screenshots in App Store Connect?" (Duo not yet selectable in the App Store Connect device selector or API): https://developer.apple.com/forums/thread/845505
- Blake Crosley, "iPhone Duo, Day Two" (Duo rows added to the specifications on keynote day; don't confuse preview and screenshot resolutions): https://blakecrosley.com/blog/iphone-duo-day-two
- App Review Guideline 2.3.7 (no prices in screenshots or previews): https://developer.apple.com/app-store/review/guidelines/
