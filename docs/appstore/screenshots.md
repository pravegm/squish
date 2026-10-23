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

## A. iPhone Duo, inner display (2007 × 2853): 6 frames (+1 optional)

The set proposed in design/FOLD-REVIEW-5.md §5. Frames 1–4 and 6 are **store shots**: the live Fold Press halves, captured on the real Duo simulator in tabletop pose, mapped onto a folded Duo model seen from a 3/4 eye (`FoldStoreShot.swift`). A raw inner frame reads as "two flat trays", so it never goes in this set, except the Shelf and Settings, which aren't anamorphic.

| # | Frame | Caption (headline / sub-line) | Source (`duo-screens/…`) |
|---|---|---|---|
| **1** | Rubber Duck hero: the failure freeze at the 62° hold, 32° eye turn so the V of the fold shows, the lid's shadow over the flattened duck | **Close your phone. Feel it *give*.** / *Squish turns the fold into a hydraulic press.* | `rubberDuck-storeshot-hero.png` |
| **2** | Soda Can before/after: small device at 112°, large at the squish. Each label quotes its own crown readout ("111°" → "AT 71°") beside a side-profile V | **Fold it shut. Open to *see*.** | `sodaCan-storeshot-pair.png` |
| **3** | Glass Bottle hero. **If the pile doesn't read on the strike plate, use the can hero here** | **It creaks. Then it *doesn't*.** | `glassBottle-storeshot-hero.png` |
| **4** | Tabletop reveal, reopened to ~155°: flat duck on the anvil, the PRESSED print and its "AT 64°" label on the lid, Again · Share · Next in the console | **Open up. File the *evidence*.** / *Every press becomes a specimen.* | `rubberDuck-storeshot-reveal.png` |
| **5** | The Shelf, raw portrait inner frame (seeded 7/10, one Golden), framed under its caption | **A shelf of pressed *specimens*.** / *No ads. No in-app purchases.* | `duo-shelf.png` → `ci/store-set.sh` |
| **6** | Variety: the heroes of four objects on one sweep, each labelled with its object and frozen readout ("EGG · AT 97°") | ***Ten* objects. Ten ways to give.** | `duo-storeshot-grid.png` (fallback `egg-storeshot-hero.png`) |
| 7 *(optional)* | Settings sheet, raw, framed | **Press without folding. Hear it *softer*.** / *Accessibility built in.* | `duo-settings.png` → `ci/store-set.sh` |

Per-object hero captions (`heroCaption(for:)` in PressDirector.swift): duck as frame 1, glass as frame 3, can "Cans buckle *ring* by ring.", bubble "Every bubble *pops* on its own.", everything else the variety line.

**Never upload:** `*-eye` composites, `*-book-storeshot-*`, raw `*-tabletop-*` frames, the `-112` singles, and any `9A–9D` / `90–99` frame (an iPhone 18 Pro drawn folded, Guideline 2.3). A pair whose label disagrees with its readout can't be produced any more: both labels come from the readout.

## B. iPhone Duo, outer display (1398 × 2034): 2 frames

| # | Frame | Caption | Source |
|---|---|---|---|
| **O1** | The cover right after the press: PRESS SEALED card, print teaser, tonnage. Caption drawn in off-white over the empty graphite top band | **Ka-chunk. Now *open* it.** | `rubberDuck-tabletop-closed.png` (tabletop pass) or `rubberDuck-closed.png` (book pass) |
| **O2** | Launched with the phone shut (7 seeded specimens): the cover's picker, framed | **Pick on the cover. Press *inside*.** | `duo-cover-launch.png` |

## C. iPhone 6.9" (1320 × 2868) and 6.1" (1206 × 2622): 6 frames (Pinch Press)

Captured on the newest "… Pro Max" simulator (6.9") and on the iPhone 18 Pro (6.1" slot, heads-up c). Because there's no hinge, Pinch Press is on automatically. Scenarios `P1`–`P6` in ci/scenarios.txt; the 4th column is the caption.

| # | Scene | Caption | Demo argument |
|---|---|---|---|
| **P1** | Rubber Duck mid-squash, ram handle visible | **Drag it down. Feel it *give*.** / *A hydraulic press for every iPhone.* | `object=rubberDuck;depth=0.55;notoasts` |
| **P2** | Bubble Wrap ripple | **Every bubble *pops* on its own.** | `object=bubbleWrap;depth=0.40;notoasts` |
| **P3** | Soda Can buckling | **Cans buckle *ring* by ring.** | `object=sodaCan;depth=0.55;notoasts` |
| **P4** | Duck reveal. **Flag:** until AchievementInfo prints tons on non-hinged phones (FOLD-REVIEW-5 N6), the card says "CRUSHED AT 65°" on a phone with no hinge; don't upload it before that's fixed | **Open up. File the *evidence*.** | `object=rubberDuck;reveal;notoasts` |
| **P5** | The Shelf (seeded 7/10) | **Collect every pressed *specimen*.** | `shelf;notoasts` |
| **P6** | The Settings sheet | **No ads. No purchases. *Just* the press.** / *Sound styles, haptic levels, Reduce Motion.* | `settings;notoasts` |

Check P1 for the ram handle before upload (request 4 below). Never a folded device in these sets.

## Rendering the set (CI)

Run **Actions → App Store screenshots** (`.github/workflows/store.yml`, manual). It produces three artifacts:

- **store-69**: P1–P6 on the 6.9" simulator, raw (`P*.png`) and captioned (`store/P*.png`), each checked to be 1320 × 2868 (the job fails with exit 4 if the simulator is the wrong class). `DEVICE=auto:Pro Max` picks the newest available Pro Max and creates one if the image has none; the step log lists the device types found.
- **store-61**: the same on the iPhone 18 Pro (1206 × 2622).
- **store-duo**: duo.yml called with the store settings (no book pass; tabletop passes for duck, glass, can, egg, cake with `storeshot=112,fail,reveal`; the Shelf, Settings and closed-launch cover; the grid), assembled by `ci/store-set.sh` into `duo-screens/store/duo-inner/01…07` and `duo-outer/O1, O2`, with `MANIFEST.txt` (source and caption per frame, size and alpha checks).

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
