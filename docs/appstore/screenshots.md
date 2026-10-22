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

## A. iPhone Duo, inner display (2007 × 2853): 6 frames

| # | Scene | Caption (headline / sub-line) | Demo argument |
|---|---|---|---|
| **1 (hero)** | Rubber Duck mid-squash on the anvil. The yellow ram is pressing down from the top half, the contact shadow is dark and wide, the duck bulges sideways, and the gauge needle in the ram housing is climbing. This is the poster frame for the whole product | **Close your phone. Feel it *give*.** / *Squish turns the fold into a hydraulic press.* | `object=rubberDuck;depth=0.55` |
| **2** | Bubble Wrap partway through the ripple: the front rows are popped flat with a few bubbles mid-pop, and the back rows are still domed | **Every bubble *pops* on its own.** / *Close slowly for a ripple. Fast for a rattle.* | `object=bubbleWrap;depth=0.40` |
| **3** | Egg at the crack. Hairline cracks have spread, the shell is splitting and the yolk is starting to spread. It's the clearest "what will *this* do?" frame | ***Ten* objects. Ten ways to give.** | `object=egg;depth=0.50` |
| **4** | Glass Bottle at failure: chunky, soft-edged shards mid-burst, with the top-screen white flash visible as a glow on the anvil. **No sharp slivers, and no shot of the glass flying "out" toward the viewer** | **It creaks. Then it *doesn't*.** | `object=glassBottle;depth=0.62` |
| **5** | The reveal. The ram is lifted with cheese-pull frosting strands, and the Cake Slice is pressed flat on its specimen card with the label `CRUSHED AT 92° · 48 TONS · 112 FRAGMENTS · №0042`, a Perfect Squish mark and the red PRESSED stamp | **Open up. File the *evidence*.** / *Every press becomes a specimen card.* | `object=cakeSlice;reveal` |
| **6** | The Shelf sheet: a herbarium grid with 7 of 10 slots filled by pressed cards (one Golden). The Glass Bottle slot shows an embossed silhouette and hint. The **secret slot is a "?" silhouette only**. Quiet "7/10 pressed" | **A shelf of pressed *specimens*.** / *No ads. No in-app purchases. No timers.* | `shelf` *(dev: seed a 7/10 collection with one Golden card; see requests below)* |
| 7 *(optional)* | Settings sheet: Sound style Workshop/Soft, Haptics Off/Soft/Full, **Press without folding** switched on, Reduce Motion | **Press without folding. Hear it softer.** / *Accessibility built in.* | `settings` |

Order rationale: feel (1), then rhythm (2), variety (3), spectacle (4), payoff (5) and the reason to come back plus the purchase promise (6). The "no ads" promise sits on frame 6 because the description and price already carry it above the fold.

## B. iPhone Duo, outer display (1398 × 2034): 2 frames

| # | Scene | Caption | Demo argument |
|---|---|---|---|
| **O1** | The cover display right after a press: the "PRESS SEALED · 48 TONS · OPEN TO SEE" card, gauge needle settling, and a teaser silhouette of the flattened duck | **Ka-chunk. Now *open* it.** | `object=rubberDuck;depth=1;cover` |
| **O2** | The cover display launched closed: a trophy shelf with an object picker and the looping "open to press" glyph | **Pick on the cover. Press *inside*.** | `cover;shelf` *(dev: confirm this combination shows the closed-launch trophy shelf)* |

## C. iPhone 6.9" (1320 × 2868): 6 frames (Pinch Press)

Capture on an iPhone 17 Pro Max-class device or Simulator. Because there's no hinge, Pinch Press is on automatically. The **ram handle must be visible** in frame 1 so the gesture is obvious.

| # | Scene | Caption | Demo argument |
|---|---|---|---|
| **P1** | Rubber Duck mid-squash with the Pinch Press ram handle and a subtle drag hint | **Drag it down. Feel it *give*.** / *A hydraulic press for every iPhone.* | `object=rubberDuck;depth=0.55` |
| **P2** | Bubble Wrap ripple | **Every bubble *pops* on its own.** | `object=bubbleWrap;depth=0.40` |
| **P3** | Soda Can buckling: two concertina rings folded, the third starting, and a hint of fizz at the seam | **Cans buckle *ring* by ring.** | `object=sodaCan;depth=0.55` |
| **P4** | Gummy Bear reveal: split into lobes, rainbow layers in the cross-section, with the specimen card and PRESSED stamp | **Open up. File the *evidence*.** | `object=gummyBear;reveal` |
| **P5** | The Shelf (same seeded 7/10 state as frame 6) | **Collect every pressed *specimen*.** | `shelf` |
| **P6** | The Settings sheet | **No ads. No purchases. *Just* the press.** / *Sound styles, haptic levels, Reduce Motion.* | `settings` |

**6.5" set:** re-capture P1–P6 on a 6.5"-class Simulator (1284 × 2778) and re-lay out the captions. Don't stretch the 6.9" files.

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

1. **Freeze the seed:** add `seed=<int>` to `-squishDemo`. Without it, the crack pattern and failure threshold change between captures, so depth=0.62 might land before the glass breaks.
2. **Freeze a moment in time:** add `t=<seconds since failure>` (or a `freeze` flag) so debris can be caught mid-air for frames 3 and 4. `depth` alone defines the static deformation but not where the particles are.
3. **Seeded collection:** add `collection=7` (or a demo fixture) so `shelf` shows 7/10 filled with one Golden card.
4. **Pinch Press handle:** confirm the handle is visible in a frozen `depth` state on non-Duo devices.
5. **Combined flags:** confirm that `cover;shelf` gives the closed-launch trophy shelf and that `object=…;depth=1;cover` gives the sealed card.

---

## Sources

- App Store Connect Help, *Screenshot specifications* (iPhone Duo outer 1398 × 2034 and inner 2007 × 2853; 6.9" 1320 × 2868 / 1290 × 2796 / 1260 × 2736; 6.5" 1284 × 2778 / 1242 × 2688; 1–10 per size; no alpha; Duo screenshots required from April 2027 for iOS 27.1 SDK builds): https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications
- Apple Developer Forums, "How do I upload iPhone Duo screenshots in App Store Connect?" (Duo not yet selectable in the App Store Connect device selector or API): https://developer.apple.com/forums/thread/845505
- Blake Crosley, "iPhone Duo, Day Two" (Duo rows added to the specifications on keynote day; don't confuse preview and screenshot resolutions): https://blakecrosley.com/blog/iphone-duo-day-two
- App Review Guideline 2.3.7 (no prices in screenshots or previews): https://developer.apple.com/app-store/review/guidelines/
