# Squish: Visual Review 1 (CI run 4)

*Critic pass on the 57 run-4 PNGs (iPhone 18 Pro simulator, portrait, 1206×2622), compared with run 1 (score 2). Scored against `VISUAL-TARGET.md` §9. Written 22 Oct 2026.*

**Scope after the founder's Duo-first clarification.** Squish is iPhone Duo-first: on a Duo the two screen halves become the press plates (Fold Press, being specced in `design/FOLD-PRESS.md`). The P-48 machine view in these frames is now only the **fallback for non-folding iPhones**. So:
- Findings on object art, materials, lighting, the studio, UI chrome and the console apply everywhere.
- Fixes to P-48 framing and proportions are tagged **[fallback]** and drop in priority.
- §5 lists what must carry into Fold Press.

---

## 0. Verdict

**Overall set score: 4.6 / 10** (run 1: 2.0). This is real progress. The press is now a whole, designed toy machine with a working gauge, lamps, keycaps and gel walls, so the "debug render" read is gone. But the set doesn't yet pass a launch bar, for three reasons:

1. **Two thirds of the frames were captured before the studio finished loading.** They show a grey placeholder backdrop, or no IBL at all, or both (§1.1). The set therefore looks like three different apps.
2. **Where a press did run, the object is invisible under the platen.**
3. **A handful of artefacts read as cheap at thumbnail size:** the yellow glow box, the gummy seam, text ghost-shadows and the clipped stamp.

The best frames (studio fully loaded: 30, 36, 39, 58) are a solid **5.8**: "decent indie" and close to coherent. Fixing the load race alone would lift the set average by about one point.

### 0.1 What I could not evaluate (scenario timing bug)
- **Never executed:** approach (d10), strain (d50/0.6) and d95 for duck, can and egg; failure event frames; the reveal for 05, 26, 27 and 28; the shelf, shelf-squished and settings sheets (20, 21 and 23 show the idle press; 20 and 23 are byte-identical).
- **Did execute, partly or by accident:**
  - 32: bubble wrap at depth 1
  - 40, 41: crayon mid and done
  - 59: ball done (platen stopped high)
  - 71: glass d95
  - 35: duck reveal, but over an unsquished duck
  - 47: cake reveal, crushed, the best story frame
  - 22: card detail
  - 24, 25: cover and cover-sealed
  - 72: calibration

  Judgements on the press and reveal states rest on these few frames only.
- **Not measured:** T7 (banding). No visible banding in any wall crop.

---

## 1. Measurements and the three render states

### 1.1 The load race (the root cause of the inconsistent backdrops)
Every frame falls into one of three states:

| State | Frames (examples) | Backdrop samples | Columns / chrome | Mean L | L<20 |
|---|---|---|---|---|---|
| **A: nothing loaded** (~22 frames) | 05, 20, 21, 23, 28, 31, 42, 44, 45, 48, 50–53, 56, 57, 60, 61, 64, 68, 70 | **`#CECBC5` everywhere** (L203), the exact run-1 grey | upper column black (min L 6), lower a flat grey gradient (L38–112 at 50% height, no highlight) | 166–167 | 0.64% |
| **B: sweep loaded, no IBL** (~16) | 01, 02, 03, 26, 27, 33, 43, 46, 49, 54, 55, 63, 65, 69, 72 | gel correct: wall `#E2E3E7` (duck), floor `#F6F1E8` | same black-to-grey columns as A; crown `#F7BC2F` | 182 | 0.64% |
| **C: sweep + IBL** (~15) | 04, 30, 32, 34, 36–41, 58, 59, 62, 67, 71 | gel correct | chrome with streaks (upper column L44–255); crown `#E5A82B` (more amber); ball shows the studio | 184–186 | **0.00%** |

**Cause, from code:**
- `PressScene.buildSweep()` gives the sweep `SceneMaterials.unlit(Palette.backdrop)`. That helper builds `UnlitMaterial(color:)`, which **is tone-mapped**, so `#F3EEE6` renders as `#CECBC5` until `applyGel()`'s detached `Task` returns the texture.
- `loadStudioLight()` is a second async `Task`, and nothing waits for either.
- Frame 66 even caught the seam mid-swap: a cream floor and a grey wall, with a hard horizon at 80% height.

This is not only a CI problem. A user will see the grey flash and the IBL pop on every cold launch.

### 1.2 Key samples (sRGB, 9×9 patch means)

| Sample | State B | State C | Target | Note |
|---|---|---|---|---|
| Crown front lit | `#F7BC2F` 42° S0.81 V0.97 | `#E5A82B` 40° S0.81 V0.90 | hue 38–44, S≥0.75, V 0.85–0.98 | **T5 passes** (run 1 was lemon). Good. |
| Platen front | `#F4BC43` | `#DA9B1A` | | fine |
| Ram barrel (centre / left) | `#35373C` L55 / `#2D2F35` L47 | `#2E2E30` L46 / `#252527` **L37** | graphite lit L≥45 | the shadow side fails; reads as black |
| Hazard band, yellow stripe | `#B79635` (glow over it) | `#B09031` | `#FFB81C` | the glow washes it to mustard; without the glow (61) the dark stripe is `#282A2E` |
| Bed-top steel, right | **`#FFFFFF`** | **`#FFFFFF`** | no clipped blob > 0.3% | **T2 fails**: a clipped wedge at x 76–89%, y 80–84% |
| Grey card (72) | `#767574` **L117** | n/a | 150–175 | under-exposed; this was a state-B frame, so re-run once IBL is gated |
| White card (72) | `#EDEDEB` L237 | n/a | 225–245 | pass |
| Soda-can lime | `#679432` | n/a | `#8BD448` | olive, not lime |
| Can white band | `#C9C8C7` | n/a | white | reads as grey tape |
| Jelly | `#E34475` | n/a | `#E8336F` | good |

### 1.3 Geometry (display px ÷ 2000 or ÷ 920)
- **Crown top** at 8%, **bed feet** at 94.5%. Crown margin: 5.0% each side, which is right on the C3 limit.
- **Plate face (idle)** at 44% (C4 passes). **Contact line** at about 74–75% (C2 passes).
- **Object widths:**

  | Object | Width | Object | Width |
  |---|---|---|---|
  | duck | 31.5% | cake | 39% |
  | bubble wrap | 42% | can | 33% |
  | jelly | 35% | gummy | 33% |
  | crayon | 37% (but only ~4% tall) | glass | **50%** |
  | egg | 38% | ball | 32% |

- **Empty stage:** the plate face (44%) to the top of the object (about 62–65% for duck, egg, ball and gummy) leaves **18–21% of screen height** of empty cream between two dark masses.

---

## 2. Scores

### 2.1 Per frame type (rubric §9.2)

| Frame type | Comp. /2 | Light /3 | Colour /2 | UI /2 | Story /1 | **Score** | Notes |
|---|---|---|---|---|---|---|---|
| Idle, state C (30, 36, 39, 58) | 1.3 | 1.8 | 1.5 | 1.2 | 0.0 | **5.8** | the real current quality |
| Idle, state B (01, 02, 26, 54) | 1.3 | 1.2 | 1.3 | 1.2 | 0.0 | **5.0** | dead chrome, black columns |
| Idle, state A (05, 45, 48, 57) | 1.3 | 1.0 | 0.6 | 1.2 | 0.0 | **4.1** | run-1 grey; reads "viewport" |
| Press (32, 40, 41, 71) | 1.0 | 1.5 | 1.5 | 1.6 | 0.1 | **5.7 → capped at 3.5** | object fully hidden, so the frame tells no story; capped for S1 |
| Reveal (35, 47) | 1.0 | 1.2 | 1.3 | 1.0 | 0.4 | **4.9** | card, stamp and actions exist; the stamp is clipped; the render is a perspective crop; 35 shows an uncrushed duck |
| Card detail (22) | n/a | n/a | n/a | n/a | n/a | **5.0** | clean paper sheet; flat vector egg instead of a specimen render; disabled "Share Clip" label fails contrast |
| Cover (24, 25) | n/a | n/a | n/a | n/a | n/a | **4.5** | tidy but empty; clip-art mini gauge (no numerals); flat silhouette trophies; chip row clipped at the right edge |
| Console chrome (all) | n/a | n/a | n/a | n/a | n/a | **6.0** | the right keycap language; text ghost-shadow; layout shifts per object |

### 2.2 Per object (best available idle frame)

| Object | Best frame | Score | One-line read |
|---|---|---|---|
| Jelly | 36 (C) | **6.5** | translucency, flutes, inner core and fruit all read; the best object |
| Rubber Duck | 34 (C) | **6.0** | silhouette right, gloss right, eyes have highlights; too small (31%); no contact AO |
| Cake Slice | 46 (B) | **6.0** | strong silhouette and colour; flat layer faces; the flame is a yellow blob |
| Unsquishable | 58 (C) / 57 (A) | **6.5 / 4.0** | with IBL a lovely mini studio; without IBL a black hole with a hotspot |
| Egg | 42 (A) | **5.5** | clean form, but blank: no flecks, no grain, almost no shading separation from the cream wall |
| Bubble Wrap | 30 (C) | **5.0** | reads as an opaque white ice-cube tray; 24 domes (spec 36); no film transparency, no sheet edge |
| Glass Bottle | 54 (B) | **5.0** | glass reads, the inner shell works, the message scroll is visible (70); too wide (50%); overhangs the anvil's back-left |
| Soda Can | 49 (B) | **4.5** | the print stops at about 60% height, so the top third is bare chrome and looks unfinished; olive green; no wordmark; grey band |
| Crayon | 39 (C) | **4.5** | a thin striped pen; no WAXO wordmark; the tip cone is hard; it's the smallest object on screen |
| Gummy Bear | 51 (A) | **3.5** | **a red, then rainbow, seam line down the centre** (the split faces and cross-section discs show through); lumpy; weak translucency |
| Golden Gummy | 27 (B) | **4.5** | the gold material is great; the same seam artefact |

### 2.3 Overall (set)

| Dimension | Weight | Score (0–1) | Points |
|---|---|---|---|
| Composition | 2.0 | 0.60 | 1.20 |
| Light and material | 3.0 | 0.45 | 1.35 |
| Colour and tone | 2.0 | 0.50 | 1.00 |
| UI | 2.0 | 0.55 | 1.10 |
| Story and delight | 1.0 | 0.15 | 0.15 |
| **Total** | | | **4.8 → reported 4.6** (rounded down for the S3 artefact count) |

### 2.4 Acceptance checklist (§9.1)

| # | Check | Result | Evidence |
|---|---|---|---|
| C1 ✔ | Object size 30–48%, centred | **FAIL** | glass is 50%; duck, can, gummy and ball sit at 31–33%, which is technically in range but below the brief's 35–45% hero target; centring passes |
| C2 ✔ | Inside the stage band, contact at 72–76% | PASS | contact about 74–75% |
| C3 ✔ | Whole press with margins | PASS (marginal) | crown margin exactly 5.0% |
| C4 | Ram home at 38–46% | PASS | 44% |
| C5 ✔ | No slabs | PASS | |
| T1 ✔ | No black | **FAIL (A, B)** / PASS (C) | L<20 is 0.64% in A and B (upper columns, barrel) |
| T2 ✔ | No clipping | **FAIL** | bed-top steel is a connected `#FFFFFF` blob of about 0.5% |
| T3 | Mid-key | **FAIL (A)** / PASS (B, C) | mean L 166 in A; 182–186 in B and C |
| T4 ✔ | Sweep colour exact | **FAIL (A)** / PASS (B, C) | `#CECBC5` in A |
| T5 ✔ | Hydraulic yellow | PASS | 40–42°, S 0.81 |
| T6 | Hero saturation | PARTIAL | duck, jelly and cake pass; the can fails (olive) |
| T7 | No banding | not measured | no visible banding |
| L1 ✔ | Three tones | PARTIAL | platen top vs front ΔL 35+ passes; the barrel shadow side is L37 (< 45) |
| L2 ✔ | Metals read as metal | **FAIL** | lower columns L93–156 with no streak ≥ 235, even in C; A and B are black to grey |
| L3 ✔ | Grounded | **FAIL** | no visible darker band at any object's contact line (see the duck crop); the floor shadow under the bed is faint but present |
| L4 | Specular on hero | PASS | duck, jelly, can and ball |
| L5 | Silhouette separation | PARTIAL | egg and bubble wrap against cream are weak |
| L6 | Bevels | PASS | crown, platen and bed all catch light on their bevels |
| U1 ✔ | Sacred stage | PASS | no UI in 45–80% at idle (the glow box is scene geometry, but it reads as UI; see fix 2) |
| U2 | Bands | PARTIAL | the "NEW ON THE SHELF" tape pokes into the 0–6% band (35, 47) |
| U3 ✔ | Contrast | PARTIAL | the detail sheet's disabled "Share Clip" label is about 2:1; the ghost-shadows reduce mono legibility |
| U4 | One primary | PASS | |
| U5 | Type discipline | PASS | Rounded and Mono only |
| S1 ✔ | States differ | **FAIL** where testable, otherwise can't evaluate | in 40, 32 and 71 the object is hidden behind the platen |
| S2 ✔ | Reveal is a moment | PARTIAL | 47 has a card, stamp, lifted ram and visible mess; the stamp is clipped ("PRESSEL"); 35 shows an uncrushed duck |
| S3 ✔ | No artefacts | **FAIL** | glow rectangle; gummy seam; dashed seam across the platen (41); sweep horizon (66); the cake candle exits the frame (47) |
| S4 ✔ | Candy-tidy mess | can't evaluate (mostly) | the cake mess (47) is tidy-ish, but the candle escapes; the glass shards (71) are hidden |

**Hard checks failing: C1, T1, T2, T4, L2, L3, S1, S3.** An 8 needs all of them.

---

## 3. The 15 highest-impact fixes (ranked)

Each fix lists:
- **What:** what's wrong
- **Why:** why it matters
- **Fix:** the change, with numbers
- **Owner**

**[fallback]** = only matters for the P-48 view on non-folding iPhones.

### 1. Gate the first frame on the studio being ready (load race) — Scene + CI
- **What:** About 22 of 57 frames show the tone-mapped placeholder sweep `#CECBC5`. About 38 have no IBL, so their columns are black and the ball is a black hole. The look changes from frame to frame and from launch to launch. Frame 66 caught a half-swapped backdrop.
- **Why:** It fails T1, T3, T4 and L2 in one go, and makes the contact sheet look like three apps. Users will see a grey flash and a lighting pop on every cold launch.
- **Fix:**
  1. In `PressScene.buildSweep()`, replace `SceneMaterials.unlit(Palette.backdrop)` with `UnlitMaterial(color: <current gel's floorNear #F1E9DC>, applyPostProcessToneMap: false)`. Also give `SceneMaterials.unlit` an `applyPostProcessToneMap` parameter that defaults to `false` for decals and sprites.
  2. Pre-bake all 11 sweep textures at launch, inside one detached task (512² each, ≤ 15 ms each). Alternatively bake the first object's texture synchronously in `init`.
  3. Add `var isStudioReady: Bool { sweepTextures[gel] != nil && iblHolder != nil }`. Keep a SwiftUI rectangle in `Theme.gel(for:)` over the RealityView until it's true, then fade it out over 200 ms.
  4. `DemoMode` must await `isStudioReady` plus 3 rendered frames before applying the scenario and before every capture.
- **Owner:** Scene (CI wait: App/DemoMode).

### 2. Kill the translucent "teaching glow" box — Scene
- **What:** `PressRig.teachGlow` is a 0.17 × 0.03 m plane (corner radius 0.012) in unlit `Palette.lemon #FFE14D`, at opacity 0.12–0.42 (`PressScene.teachingPulse`: `0.12 + 0.3*wave`). In 01, 02, 26 and 27 it shows as a **hard-edged, highlighter-yellow rounded rectangle**. It spans x 17–83% and y 38.5–44%, washes the hazard stripes to mustard `#B79635`, and **hangs below the platen's lip over the steel plate**, where it's backed by nothing. It reads as a selection rectangle or a smear on the screen.
- **Why:** It's in every first-run frame, including the first frame a reviewer or App Store editor sees. S3 forbids hard-edged translucent rectangles.
- **Fix:**
  - Delete the plane.
  - Teach with the machine's own materials instead:
    - Pulse the hazard band's yellow-stripe emissive: give the hazard texture's yellow an `emissiveColor #FFB81C` and animate `emissiveIntensity` 0 → 0.5 → 0 on the existing 1.6 s wave.
    - Pulse the platen enamel's `emissiveIntensity` 0 → 0.12.
  - If a halo is still wanted, use a `StudioEnvironment.gaussianImage(sigma: 0.35)` sprite (0.22 × 0.06 m, alpha ≤ 0.20) placed **behind** the platen (z −0.06). Its edges are then soft and partly occluded.
- **Owner:** Scene (`Scene/Rig/PressRig.swift` `teachGlow` / `setTeachGlow`; `Scene/PressScene.swift` `teachingPulse`).

### 3. The object must stay visible while it's pressed (S1) — Scene
- **What:** In every executed press frame the object vanishes behind the platen: 40 (crayon, depth 0.6), 32 (bubble wrap) and 71 (glass shards, where only confetti specks peek out). The platen front (42 mm) plus the plate (12 mm) is a 54 mm wall, and the camera's 14° pitch puts it exactly in front of the anvil top. The ball (59) stops about 4 cm above the ball, so it reads as "press broke in mid-air", not "press lost".
- **Why:** The press is 80% of the experience and the frames users will hold. Right now the most satisfying moment is the least visible.
- **Fix:**
  - Thin the crosshead: platen height 0.042 → **0.030**, and plate 0.012 → 0.008.
  - Inset the plate 0.130 → **0.110** wide, so squashed objects and spreads (target Ø up to 0.15) bulge out visibly at both sides.
  - Raise the presetP pitch 14° → **20°** (re-solve the position so the anvil top stays at 74%), so the anvil deck is about 2× deeper on screen.
  - Add a strain-rule assertion in CI: in a `depth=0.5` frame, at least 40% of the object's idle bounding box must still be visible.
  - Ball: the platen must stop **1 mm above the apex** (§4.6), with the red lamps blinking.
- **Owner:** Scene (`PressRig.swift` platen and plate meshes, `SceneStyle.presetP`; object mapping of depth to contact). The principle carries into Fold Press (§5).

### 4. Ground everything: visible AO and a real key shadow (L3) — Scene
- **What:** None of the duck, egg, can, gummy or ball has a visible darker band at its contact line (see the duck crop: the anvil is uniform `#979693` right up to the body). Objects look pasted on, and the can in 68 looks like it's hovering.
- **Why:** Grounding is the cheapest premium cue, and it's a hard check.
- **Fix:**
  - `SceneStyle.aoAlpha` 0.55 → **0.75**. Shrink the AO decal from footprint × 1.15 to **× 1.05**, with gaussian σ 0.35 → **0.25** (tighter, darker ring).
  - `softShadowAlpha` 0.22 → **0.32**, offset (+0.012, −0.010).
  - In `buildLights()`, replace `Shadow(maximumDistance: 2.5, depthBias: 1)` with §3.5's `.fixed(zNear: 0.05, zFar: 3.0, orthographicScale: 0.55)` and depthBias **2.0**. That gives a crisp cast shadow down-right of each object. The current automatic cascades are too coarse at this scale, and the dashed seam across the platen in 41 looks like shadow acne.
  - Confirm the decals are unlit with `applyPostProcessToneMap: false` and lifted 0.3 mm.
- **Owner:** Scene (`SceneStyle.swift` decals; `PressScene.swift` `buildLights`, decal setup around line 571–606).

### 5. Remove the ghost drop-shadow from all UI text — UI
- **What:** Every label on a keycap, card or toast renders with a grey copy offset 2 pt below it: "RUBBER DUCK", "Shelf", "CRUSHED AT 79° · 63 TONS", "Your first pressed specimen." `KeycapFace` applies `.elevation(.e1)` to the whole view, label included, and the cards and toasts do the same with E3.
- **Why:** Mono text with a doubled shadow reads blurry and cheap at any size. It also hurts U3.
- **Fix:**
  - In `Theme.swift` `KeycapFace`, move the elevation onto the shapes: `.background(shape.fill(face).elevation(...))` and the lip shape. Don't elevate the content.
  - Do the same in `ToastView`, `RevealCardView`, `SpecimenCardView` and `CoverView`: put the shadow on the `RoundedRectangle` background only.
  - Add a snapshot test that crops a chip label and asserts there's no second glyph edge.
- **Owner:** UI (`UI/Theme.swift` line ~378, `ToastView` ~611; `RevealCardView.swift`).

### 6. Hero scale: every object at 37–42% of width — Scene
- **What:**
  - The duck (31.5%), can (33%), gummy (33%) and ball (32%) read as small toys on a big machine.
  - The crayon is 37% wide but only about 4% of screen height, a pencil line.
  - The glass is 50%, over the limit, and overhangs the anvil's back-left edge.
- **Why:** The object must be the hero, the brightest and most saturated thing in the frame (§2.1), and it's what makes the store thumbnail read as "squish a duck".
- **Fix:** Target a footprint of **0.112–0.125 m** at the 0.30 m visible width.

  | Object | Change |
  |---|---|
  | Duck | ×1.25 (`DuckView.footprint` 0.052 → 0.065, plus mesh scale) |
  | Gummy | ×1.2 |
  | Ball | Ø 0.090 → **0.110** |
  | Can | Ø 0.090 → 0.110, height 0.150 → 0.140 (see fix 9 for clearance) |
  | Crayon | Ø 0.022 → **0.032**, length 0.113 → 0.125 |
  | Glass | ×0.86 (length 0.140 → 0.120), recentred on the anvil |

  Grow the anvil 0.150 × 0.110 → **0.165 × 0.120** so everything still sits on steel.
- **Owner:** Scene (`Scene/Objects/*View.swift` sizes; `PressRig` anvil and `anvilHalf`).

### 7. The black ram barrel [fallback] — Scene
- **What:** The graphite barrel (Ø 0.060 × 0.060) is the largest dark mass in the upper frame. It renders L37–55 (`#252527`–`#35373C`), matte, with one dull vertical highlight, so it reads as a tin can or PVC pipe. The chrome rod at idle is a 10 mm sliver, so the "hydraulic" read is lost. The barrel also fails "no black" and L1 (shadow side L ≥ 45).
- **Why:** It sits dead centre, directly above the hero, and pulls the eye.
- **Fix:**
  - Shrink to **Ø 0.050 × 0.044**. Base colour `#34373D` → **`#4A4E56`**, clearcoat 0.35 → **0.7**, clearcoatRoughness 0.18 → **0.10**, so the key softbox lays a strip highlight on it.
  - Add two chrome machined rings (torus, major 0.0255, minor 0.0012) at 1/3 and 2/3 of its height.
  - Expose **18 mm** of chrome rod at idle (barrel bottom 0.270 → 0.262).
  - Target: lit side L ≥ 70, shadow side L ≥ 48.
- **Owner:** Scene (`PressRig.swift` barrel and lip; `Palette.enamelGraphite`, or a new `barrelGraphite`).

### 8. Make the chrome columns read as chrome (L2) — Scene
- **What:**
  - In states A and B the columns are black at the top (min L 6) and a flat grey gradient below (L38–112), like a gradient-filled plastic tube.
  - Even in state C, the lower 60% of each column is L93–156 with **no bright streak** and no dark flag, so they look like brushed grey PVC.
  - In 26 a hard horizontal step crosses the columns at y ≈ 61% (the sweep horizon reflected).
- **Why:** The columns are the tallest elements on screen, so their material sets the quality read.
- **Fix (after fix 1):** In the HDRI (`StudioEnvironment.shapes`):
  - Rim strips L/R: value 4.0 → **6.0**, width 10° → **14°**, height 55° → **80°**, elevation +25° → **+10°**, so they cover the columns' lower reflection.
  - Black flags at ±95° → **±70°**, so each column shows a dark core line.
  - Add a soft −10° → +10° vertical gradient to the back wall so the horizon doesn't step.

  Check: within the column width, max L ≥ 235 and min L ≤ 110 at 30%, 50% and 65% height.
- **Owner:** Scene (`Scene/Rig/StudioEnvironment.swift` shapes and gradient stops; `SceneStyle.iblExponent` stays 2.3 until the calibration is re-run).

### 9. P-48 proportions: shorten the daylight, kill the empty stage [fallback] — Scene
- **What:** The platen face sits at 44% and most objects' tops at 62–65%, so 18–21% of the screen height is empty cream framed by two long poles. The columns run 21–77% of the height, so the machine reads as a tall, narrow tower and the object as an afterthought at the bottom.
- **Why:** In the fallback view this hurts the "about to squish" tension. The ram should loom over the object.
- **Fix:**
  - `PressRig.homeFace` 0.205 → **0.180**. Columns 0.365 → **0.335**; move the crown and barrel down 0.030.
  - The can needs 0.140 + 0.035 clearance, so fix 6's can height is required.
  - Re-solve `SceneStyle.presetP` so the crown top sits at **10%**, the anvil at 74% and the plate face at 46–48%. The freed top band shows more gel wall.
  - The idle gap between the object top and the plate face becomes about 8–10% of screen height, which is tense, not empty.
- **Owner:** Scene (`PressRig.swift` constants, `SceneStyle.presetP`).

### 10. Clipped white bed top [fallback] — Scene
- **What:** The 0.214 × 0.144 brushed-steel bed-top plate catches the key and renders a large clipped `#FFFFFF` wedge (x 76–89%, y 80–84%), a T2 failure. Together with the steel anvil, the whole base reads as a white tray, not a graphite bed.
- **Fix:**
  - Make the bed-top plate **graphite enamel**, and keep a 2 mm chrome inset line only, as §4.1's "thin bright line".
  - Or keep it steel with roughness 0.30 → **0.48** and base `#BFC3C8` → **`#A4A9B0`**.
  - Check: no min(R,G,B) ≥ 250 blob > 0.3%.
- **Owner:** Scene (`PressRig.swift` line 79 material).

### 11. Object-art defects: gummy seam, can print, crayon — Scene
These carry into Fold Press.
- **Gummy (51, 52, 53, 27):** A jagged red, and in 52 rainbow, line runs down the bear's centre. The pre-split halves and the rainbow cross-section discs are visible through the shell at idle.
  - Fix: hide the split faces and discs (`isEnabled = false`) until the failure frame; at idle, render one welded SDF mesh.
  - Shell opacity 0.88 → **0.80**, emissive `#FF6B5A` 0.15 → **0.22**, so the core glows through.
- **Can (48, 49, 66–68):** The print covers only about 0.01–0.10 m of the 0.150 m body, so the shoulder and the top third are bare chrome and the can looks unfinished.
  - Extend the print to 0.126 m (the shoulder).
  - The lime renders `#679432`: raise the texture field to **`#96DB4E`** and drop metallic 0.55 → **0.35**. Make the white band `#FFFFFF` (it renders as grey `#C9C8C7`).
  - Add the **FIZZO** wordmark and 6–8 large bubbles (§5.7).
- **Crayon (39):** Add the WAXO wordmark band. Give the tip a 1.5 mm round at the cone base, so it reads as wax, not a pen cap. Wax sheen `#9DB3FF` so it reads matte-soft.
- **Bubble wrap (30):** Show 6 × 6 domes (currently 24). Film opacity 0.55 → **0.45** so the steel shows through. Curl two corners by 3 mm so the sheet edge reads.
- **Owner:** Scene (`Scene/Objects/GummyBearView.swift`, `SodaCanView.swift`, `CrayonView.swift`, `BubbleWrapView.swift`).

### 12. The specimen render is a placeholder — Scene + UI
These carry into Fold Press.
- **What:**
  - The reveal card (35, 47) shows a **perspective crop of the live scene**, columns and anvil included.
  - The detail sheet (22) shows a **flat vector egg** (the `ObjectSilhouette` shape with a gradient), not a specimen.
  - The card is 62% of the screen width.
- **Why:** The card is the collectible and the share image. A screenshot of the press inside a card reads as unfinished.
- **Fix:**
  - Render the specimen per §6.8: an `OrthographicCameraComponent` looking down −Y, scale = flattened footprint × 1.25, rig and sweep hidden, transparent background, the same IBL plus key, at 2× size.
  - Until that exists, render the flattened object alone at 3/4 on paper.
  - Card width: `min(0.84 × screen, 340 pt)`.
  - Move the "NEW ON THE SHELF" tape down 8 pt so it stays out of 0–6%.
- **Owner:** Scene (render), UI (`RevealCardView.swift`, `SpecimenCardView.swift`, `SpecimenImage`).

### 13. The stamp is clipped and collides with text — UI
- **What:**
  - On the cake (47) the stamp reads "PRESSEL": the P and D are clipped by a container.
  - The double border is misregistered, with the outer ring cut off at the left (35).
  - The stamp sits on top of the "k" of "Rubber Duck" and over the "№0001" serial.
  - On the detail sheet (22) the "P" is hidden under the render.
- **Why:** The stamp is the peak-end moment. A clipped stamp reads as a layout bug.
- **Fix:**
  - Position `PressedStamp` (Theme.swift ~476) in an overlay on the **render frame**, anchored bottom-trailing with a −20% offset. Put it at zIndex 2, above the render, with **no `.clipped()`** on any ancestor.
  - Keep ≥ 12 pt clearance from the name baseline. Move the serial into the label block's first row, right-aligned.
- **Owner:** UI.

### 14. The console jumps per object; tidy the keys — UI
- **What:** `IdleConsole` centres an HStack, so the Shelf key's x position changes with the chip's text. Measured on screen (of 920 px):

  | Chip | Shelf key x | Chip edge |
  |---|---|---|
  | EGG | 410–740 | |
  | GLASS BOTTLE | 490–825 | |
  | THE UNSQUISHABLE | 528–860 | the chip's left end nearly touches the bed edge |

  The "Shelf 0/10" count also shows before any card exists (P2-3 says hide it).
- **Why:** The console is the one persistent piece of chrome. If it shifts between objects, the build reads as hand-made.
- **Fix:**
  - Use a fixed two-slot grid, inset 16 pt from the bed's front face: the chip gets a **fixed 54%** of the console width (truncate to "UNSQUISHABLE"), and the Shelf key the remaining space minus 12 pt.
  - Hide the count at 0.
  - Raise the Shelf key's lip contrast: `consoleLip #1E2023` on the `#3A3D43` bed is invisible, so try `#141518` plus a 1 pt `#4A4E56` top highlight.
- **Owner:** UI (`UI/PressOverlays.swift` `IdleConsole`, `ObjectChipPicker`, `ShelfKey`).

### 15. Instrument panel, lamps and mess containment — Scene
- **Amber lamp renders lemon (32, 40, 71).** Use `glowing(lampAmber, intensity: 2)`, then emissive intensity 2 → **0.9**, with base `#FFA000`, so it reads amber `#FFB81C`, not `#FFE84A`.
- **The nameplate reads as an empty grey text field.** Use brushed steel with an engraved "P-48" (it currently renders flat `#6E7075` with grey text). Use `plateMaterial` (textured, metallic 0.8) on the plate box too; it's currently `steel`, so the texture plane looks pasted on.
- **The panel's middle third is empty graphite.** Move the lamps to x +0.010/+0.030 and the nameplate to +0.062, or add a small debossed "SQUISH" wordmark at x 0.
- **Mess escapes the anvil.** In 47 the flattened candle runs past the right column and off-frame over the toast. Clamp all mess and debris rest positions to `PressRig.anvilHalf` (and the new 0.0825 × 0.060). Lay the candle along the slice's long axis at ≤ 0.040 m.
- **Owner:** Scene (`PressRig.swift`, `Palette.swift`, `CakeSliceView.swift`).

**Also noted, below the cut:**
- Cover idle (24): flat vector trophies; the chip row clipped at the right with no fade; "Open to press" is bare yellow text rather than a keycap or breathing glyph.
- Cover sealed (25): the mini gauge has no numerals or ticks, so it reads as a clock icon. Use the §4.4 texture.
- Detail (22): the disabled "Share Clip" label is about 2:1. Use the disabled keycap rule (45% of the whole key, label stays graphite), not a tinted label.
- The Dynamic Island appears in only some captures (21, 22, 46, 57, 63, 64). Make CI consistent.
- Calibration cards (72) stand on the bed and intersect it. Move them to z +0.08 on the sweep floor.

---

## 4. What great looks like, per object (idle)

- **Bubble Wrap.** A square, almost-clear sheet (film `#E4F3FA` at 0.45 opacity) yawed 12°, with **36 crisp domes**. Each dome carries a tight key highlight top-left and a top-strip line. You can see the brushed steel and the bolt heads *through* the film. Two corners curl up 3 mm, catching a bright edge line. At 40% width it should read "bubble wrap" at thumbnail size from its highlights alone, never "white tray".
- **Rubber Duck.** The current mesh is close. Make it 40% wide and turn it a touch more 3/4 toward camera (yaw −30°). Duck yellow `#FFD23F` with a warm saturated shadow side (`#E0A626`, never olive). Both eyes need a white pin highlight. A long soft top-strip highlight should run along its head and back. Give it a dark, tight AO ring and a soft shadow falling down-right onto the steel. Its orange beak is the most saturated accent in the frame.
- **Jelly.** Already the best object. Make it slightly larger (40%). Push the "glows where thin" read: a brighter rim at the flutes, and the fruit cubes visibly suspended. Add a faint pink caustic tint on the anvil under it (an unlit decal `#E8336F` at alpha 0.12) as the lighting signature. Keep the idle wobble.
- **Crayon.** A **chunky toddler crayon** (Ø 32 mm) lying at 20°. Cobalt wax `#2F5BEA` with soft sheen and no hard highlight. A cream paper wrapper with a cobalt wave band and the **WAXO** wordmark. A worn, slightly rounded tip. It should feel like a fat soft object about to smear, not a ballpoint pen.
- **Egg.** A warm `#EFD3A0` egg on its side with a satin (not glossy) shell: roughness 0.6 and a broad soft highlight. A few sparse darker flecks. A clear lit, mid and core-shadow gradient so it separates from the cream wall. Consider a slightly cooler sky gel (`#D8E8F2`) so the shell pops. Fragile and heavy at once.
- **Cake Slice.** Keep the strong wedge. Add **sponge mottling** (±4% noise) to the layer faces, a 5-scallop frosting drip on the back arc, and a 2 mm chamfer catch-light on the cream top edge. The flame should be a teardrop with a soft glow sprite, not a ball. Sprinkles stay, and are the confetti of the mess later.
- **Soda Can.** A **fully printed** fat can: lime `#8BD448` field, a white wave band, the **FIZZO** wordmark and big sparse bubbles. Bare aluminium only on the lid and rim. A long vertical rim-strip highlight down each side. 38% wide, upright, unmistakably a can of pop.
- **Gummy Bear.** One welded, translucent coral bear (`#FF5A4E` shell over a `#C8203A` core) facing camera. The shape needs plump rounded limbs, clear ears and a sugar-haze sheen, and light glowing through the ears and arms. **No seams until it breaks.** It should look edible.
- **Glass Bottle.** A sea-glass bottle at 42% width, fully on the anvil. Two long, bright rim-strip lines run along its length. The inner shell gives darker teal edges, and the rolled message is visible inside. The label band (not in spec) helps the read: keep it, but make it paper `#F4ECDD` with a thin raspberry stripe rather than a solid band, so the glass still dominates.
- **The Unsquishable.** A 0.110 m mirror ball that shows the whole studio in miniature: a big key softbox top-left, a thin top strip, two dark flags, a cream lower third, and a reflection of the yellow crown and platen above. Frame 58 is almost there. It must never appear without the IBL (frame 57 is a black hole with a hotspot).

---

## 5. What must carry into Fold Press

The P-48 rig becomes fallback-only. These parts of the work are the product and carry over unchanged:

1. **The studio pipeline and its readiness gate (fix 1).** Fold Press needs the IBL to light the objects, the tone-map-free unlit backdrop for exact gel colours, and no grey first frame. On a Duo each half-screen is a plate, so a grey flash on either half breaks the illusion.
2. **Object art and materials (fixes 6, 11, §4).** Jelly, duck and cake are near launch quality. The gummy seam, can print and crayon fixes apply as-is. Hero scale needs re-solving for the plate view: the object should fill **40–50% of the lower plate's width** at rest.
3. **"The object stays visible under load" (fix 3).** This is even more critical when the screen halves *are* the plates. Design the camera so you see the object bulge out between the closing halves, with spread and mess escaping the seam. The CI strain-visibility assertion should carry over.
4. **Grounding (fix 4).** AO plus the soft shadow on whatever surface the object sits on. Add a darkening ramp near the closing edge (the ram-occlusion decal becomes a "plate-proximity" shadow as the halves approach).
5. **Instruments as feedback.** The gauge face (§4.4), the lamp colours (correct amber: fix 15) and the hazard band are good, ownable assets. Re-home them on the Duo's frame, the edge of the top plate, or the cover display. Don't lose the gauge.
6. **Teaching through the machine, never with a translucent box (fix 2).** On the Duo, the ghost arc on the hinge plus a pulsing emissive on the plate's hazard edge.
7. **UI chrome (fixes 5, 12, 13, 14).** The keycap language, the ghost-shadow fix, the stamp layout, the true specimen render and the fixed console grid are all presentation-independent. On the Duo the console belongs on the lower plate's front-edge band, in the same 86–95% zone measured on the lower half. Nothing interactive goes in the crease.
8. **The CI contract.** Run 4 shows that scenario timing *is* the visual risk. Every scenario must wait for `isStudioReady` plus 3 frames, and press states must assert that they moved. Add a Fold Press scenario set (`fold=0.1/0.5/0.95`) from day one.

What does **not** carry over: the P-48 proportions, column, barrel and bed fixes (7, 8, 9, 10) and the presetP re-solve. Spend fallback-view time on them only after the items above.
