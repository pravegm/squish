# Fold Press: Squish on iPhone Duo

*Art direction and interaction spec, 22 Oct 2026. This is not a mode. **On any device with a hinge, Fold Press is Squish.** The P-48 machine view is the fallback for iPhones that don't fold, for Split View, and for screen captures that can't be eye-corrected. Where this document conflicts with `SQUISH-DESIGN-BIBLE.md` §2, §3, §6 or `VISUAL-TARGET.md` §3.2 and §4 on a Duo, this document wins. §11 lists the amendments. Numbers marked **[tune]** are starting values for Week 0 on a real device.*

Inputs: Bible §2, §3, §6 and §9; VISUAL-TARGET §2–§6; research 03 §5 and 05 §1–§3; `PressScene.swift`, `SceneStyle.swift`, `PressRig.swift`, `PressMapping.swift`, `PressConfig.swift`, `MaterialProfile.swift`, the object views (rest heights and footprints); and targeted web research (sources at the end).

---

## 0. Why the current build is wrong on a Duo, in one paragraph

Today the Duo shows a picture of a press. Preset D frames the whole P-48 across the inner display: the crown, gauge and ram are drawn on the top half, and the anvil on the bottom half. As the user folds, the *real* top half tilts away, carrying a *picture* of a ram that's pointing at the user rather than at the object. The two halves tell different stories. The fold drives the press, but you don't see it **being** the press. Every successful Duo toy does the opposite and makes the physical halves the physical thing:
- **Toastie:** closing shuts the toaster lid.
- **Inkblotter, Paint & Fold, Foldink:** closing presses the ink onto the facing page.
- **Orisuji:** one page lies on the other and pins whoever is standing in the holes.

Squish has the strongest claim of all of these to "the phone becomes the appliance". We have to cash it.

---

## 1. The concept

### 1.1 In five sentences
1. **The two halves of the glass are the two plates of the press.** The lower half is the steel anvil, with the object standing on it. The upper half is the platen face that comes down onto it. The crease is the hinge pin, and the yellow rails, hazard jaws and instruments around the edges make the phone itself look like the machine.
2. **The bottom half is rendered anamorphically.** An eye-corrected, off-axis camera puts the anvil surface exactly in the plane of the glass, so the object appears to stand up *out of* the screen, like 3D pavement art. Its contact shadow is drawn on the glass itself.
3. **Nothing is ever drawn in the air between the halves, because that air is real.** The press is drawn on the two surfaces:
   - The object deforms on the anvil.
   - On the platen, the object's *shadow* sharpens as the plate nears, and then turns into an **ink contact print**. The print sits exactly where the object will meet the top glass (its mirror image across the crease), blooms with pressure, splats at failure and stays.
4. **The hinge angle is remapped, so the story fits the angles at which a Duo can actually be seen:**

   | Event | Hinge angle |
   |---|---|
   | Contact | ~132° |
   | Failure | 96–64° (soft objects 73–64°) |
   | Visual flat | 48° |
   | Final crush | the magnet clap, felt and heard as the halves meet, with the **ka-chunk** |

5. **Reopening is the reveal: a diptych.**
   - **Bottom half:** the flattened specimen on its anvil.
   - **Top half:** its monoprint on the platen.
   - **Across the crease:** strands of goo snapping in between.

   Together they make the pressed card you collect and share.

### 1.2 The one rule that makes it work
**Zero-depth content is truth; depth content is illusion.** Some things are drawn *in the plane of the glass*: contact shadows, the print, the steel, bolts, rails and gauges. These look right from any eye, at any hinge angle, despite the ±5° hinge error. Things drawn *off the glass*, meaning the object's height and debris, depend on an assumed eye. So we:
- keep the off-glass content short (object height ≤ 24 mm, §2.3);
- keep it on the bottom half only;
- anchor it to the glass with a crisp contact shadow.

The top half carries **only** zero-depth content. That's why it can stay readable as it tilts.

### 1.3 Why we don't map the geometry literally (the numbers)
Take a 24 mm object centred 40 mm from the hinge axis. The real top glass only reaches its top at **θ = atan(24/40) ≈ 31°**. That's inside the band where the inner display may already be off (55–20°, research 05 §1.3), and in tabletop the object is hidden under the overhang below ~35°. A literal clamshell would crush in the dark. So the plates are real but the gap is *perceptual*. Contact, strain and failure are driven by a remapped angle (§4), and every cue of the closing gap is drawn on the two surfaces, where it can't contradict the real air between them.

---

## 2. Bottom half: the anvil

### 2.1 What it is
The bottom half is **one plane, coplanar with the glass**, on which the press's lower plate is built.

| Layer | Look | Material (VISUAL-TARGET §4.3 values) |
|---|---|---|
| **Enamel field** (the whole half inside the bezels) | glossy, warm, cream enamel, tinted toward the object's `gel(kind)` (the gel wall colour becomes the appliance's colour) | clearcoated enamel: roughness 0.40, clearcoat 0.70 / 0.10, base = mix(`floorNear #F1E9DC`, gel, 0.35) [tune] |
| **Strike plate** (rounded rectangle 300 × 230 pt, r 18 pt, centred on the object; 0.4 mm proud, 0.4 mm chamfer catching a highlight line) | brushed steel; streaks run **parallel to the crease** | brushed steel `#BFC3C8`, metallic 1, roughness 0.30 |
| **4 hex bolts** (Ø 12 pt, 1.5 mm domes, inset 14 pt from the plate corners) | chrome | mirror chrome, roughness 0.06 |
| **2 guide-pin bushings** (Ø 10 pt rings, 28 pt in from each side, 60 pt from the crease edge) | dark chrome rings | they sit under the platen's guide pins (§3.5) when closed |
| **Back lip** at the crease edge (6 pt band) | graphite, with a 1 pt steel chamfer highlight. **This is the anvil's back edge** | graphite enamel |

The P-48's cyclorama, bed, columns, crown, platen, rod and barrel are **not rendered** on a Duo. The real world around the phone is the studio. Lighting stays as in VISUAL-TARGET §3.3–§3.5: IBL studio, a key from the upper left and front, a rim from behind, warm shadows. The key comes from in front of the user's left shoulder, so the cast shadow falls **back and to the right, toward the crease**. A shadow lying on the glass behind the object is the strongest single cue that the object stands up out of it.

### 2.2 Off-axis camera: the glass is the anvil
- **Scene units.** Keep the P-48 asset scale and set **1 physical mm = 0.00294 scene m** (1 scene m = 340 mm). This makes a typical footprint radius of 0.05 scene m equal **17 mm**. The glass half is 111.1 × 75.7 mm, which is 0.3267 × 0.2226 scene m. Perspective is scale-invariant, so nothing else needs rescaling.
- **Anvil frame.**
  - Origin: the object's footprint centre on the glass.
  - +y: the glass normal.
  - +z: toward the half's free (front) edge.
  - The hinge axis is at z = −40 mm, and the glass runs from z = −36.7 mm (crease edge) to +39 mm (front edge).
- **Design eye** (it's assumed, not tracked):

| Pose (how it's detected, §9.4) | Eye in the anvil frame | Updates |
|---|---|---|
| **Tabletop** (anvil half flat; gravity within 30° of the anvil normal) | distance **380 mm** from the origin, elevation **ε = 40°** over the front edge, lateral 0 | On layout only. The bottom render doesn't change with θ in tabletop: the eye is fixed relative to the table |
| **Handheld laptop** (horizontal fold, anvil pitched up toward the user by β) | as tabletop, with ε = 40° + β, clamped ≤ 75° | Per frame (cheap) |
| **Book** (vertical fold, held) | on the wedge bisector, **320 mm** from the hinge midpoint: E = H + 320·(0, sin θ/2, cos θ/2) | **Per frame with θ.** As the book closes the eye drops toward the anvil, and the object visibly "stands up" like a pop-up book. The effect comes free from the geometry |

- **Anamorphic strength s = 0.85 [tune].** Render with ε_render = ε + (1 − s)(90° − ε), which is **47.5°** for tabletop. A slightly steeper render eye makes objects read *a bit squat* when the real eye is lower than assumed, rather than stretched and leaning. Squat reads as "toy"; stretched reads as "glitch". In the Tuning Lab, s = 0 is straight down and s = 1 is the full design eye.
- **Result:** the strike plate is a perfect rounded rectangle at its exact pt position on the glass, the bolts sit where they are drawn, and the object rises out of the plate with correct parallax for the design eye. The off-axis technique is in §9.3.

### 2.3 Placement and the crease
Points to millimetres on the inner display: 951 pt along the long side ≈ 157.9 mm, so **6.02 pt/mm and 1 cm ≈ 60 pt**. The 40 pt crease band is ≈ 6.6 mm, not 1 cm. Verify with an on-screen 100 mm bar in Week 0.

| Rule | Value |
|---|---|
| Object footprint centre | **40 mm from the hinge axis** (≈ 55% of the anvil depth from the crease edge), centred laterally. *Supersedes the bible's 40% for hinge mode* |
| Footprint clearance from the crease band edge | **≥ 60 pt (1 cm)** |
| Projected silhouette clearance (at the design eye) | **≥ 24 pt** from the crease band edge. The image may lean toward the crease (that is what height looks like) but never enters it |
| Fold-mode height cap | rendered rest height ≤ **24 mm**. `foldScale = min(1, 0.0706 / restHeight)`: gummy 0.66, duck 0.83, egg 0.88, jelly 0.92, all others 1.0. Footprint radius ≤ 17 mm (lying objects may be up to 23 mm half-length laterally) |
| Debris | ceiling = the virtual platen (`fx.step(ceiling:)` as today). Anything projected within 24 pt of the crease fades out over 60 ms. It "falls off the back edge of the anvil". Front-edge debris slides under the console. Side debris slides under the rails |
| Spread meshes (jam, yolk, fizz) | clamped to the strike plate + 40 pt; never into the crease band |

**The crease is the back edge of the anvil.** The 40 pt band is filled solid graphite `#2B2D31` (decorative, no content, no gradients, because the glass curves there). It reads as the gap at the hinge between two plates.

### 2.4 What else the anvil does over the press
- **Contact shadow** (VISUAL-TARGET §3.6, both layers): a tight AO ring (alpha 0.55) plus a soft blob (0.22, falling to 0.12 when covered). It's crisp at the base, because it's the anchor of the whole illusion.
- **Plate shade:** the existing `ramDecal` becomes a soft rectangle of `shadowInk #3B2F25` on the anvil around the object, alpha = 0.30·a², where a is approach (0…1). It reads as the plate's shadow arriving.
- **Wedge light:** the real top screen really does light the object. Modulate the rim light by `rimGain = 0.6 + 0.4·clamp((150 − θ)/60, 0, 1)` [tune]. Place the failure `flash` point light at the crease side, 30 mm up, so the top half's white flash visibly lights the object's back.
- **Clamshell lean:** the platen comes down from the hinge side, so the deformation shears the object's top **away from the hinge** by up to **8°·c** (bible's ≤ 10° ram tilt, now with a physical reason). The squash visibly points at the real lid.
- **Pre-contact quiver** (0.5% scale jitter, a > 0.6), hit-stops, micro-shake and persistent mess all stay as in bible §9.

---

## 3. Top half: the platen face

### 3.1 Options considered
| Option | Verdict |
|---|---|
| **(a) The plate's underside seen from the object's POV** (a camera on the anvil looking up) | ✗ In tabletop the top glass faces the *user*, not the object, so this reads as a camera feed, not a surface. It needs a second 3D render. It also becomes unreadable exactly when it matters (below 75°) |
| **(b) The object's contact print spreading on the plate, like ink or pressure film on glass** | ✓ **Chosen** (below) |
| (c) The gauge | ✗ as hero. Information, not magic. It moves to the crown strip (§5) |
| (d) A mirror-steel reflection of the object | ✗ as hero. Real mirror geometry puts the reflection *at the crease* at 120° and *at the tip* by 60°, so it slides away from where the object meets the plate. It contradicts the print, and it needs an accurate eye |

### 3.2 The chosen treatment: "Shadow → Kiss → Print"
The platen face is the same cream enamel as the anvil, with a **brushed-steel strike plate** at the mirrored position, 4 bolts and 2 **guide pins**. On it, in sequence:

1. **Approach shadow** (θ0 → contact). The object's top-down silhouette appears as a soft `shadowInk` shadow on the steel, centred exactly on the **mirror of the footprint across the crease**.
   - As the virtual gap s closes it sharpens: blur 40 → 4 pt, alpha 0.08 → 0.35, scale 1.25 → 1.0.
   - This is how your hand's shadow behaves as it approaches a table. It's the one approach cue everyone has felt.
2. **Kiss** (contact). The shadow's core turns to **ink**: one bright, wet dot of the object's colour in the shape of its apex, with a single-frame highlight. It happens in the same frame as the contact thud and the object's own flatten on the anvil.
3. **Print** (strain).
   - The print grows as a mask of the silhouette with radius **r = R·min(1, 1.1·√c)** (contact area roughly proportional to compression). It has a soft 6 pt edge, and its saturation rises with c.
   - Around its edge, **Newton's rings**: faint iridescent bands (alpha 0.06 + 0.10·c) that expand with the edge. Real optics, and the exact look of a curved thing pressed on glass.
   - In the tell phase the print's edge trembles (±1 pt at 14 Hz) with the gauge.
   - Fractures stamp themselves into the print as they happen (table below).
4. **Splat** (failure). A radial burst in the material's ink, plus the half's **white flash** (2–3 frames, < 3 Hz; it also lights the bottom half). After that, debris that hits the virtual ceiling leaves droplets on the print at mirrored positions.
5. **Monoprint** (crush → reveal). The print spreads out to match the spread meshes on the anvil, then stays. It's the second half of the specimen (§6.3).

**Why this is the most magical option:**
- It **proves the top plate is the one pressing**: the stain appears on *that* glass, at the exact place the object will meet it when the phone shuts.
- It's **zero-depth**, so it's correct from any eye and any angle, and survives tilt better than anything 3D.
- It belongs to the Duo's native lineage (Inkblotter, Paint & Fold and Foldink all do "close to print"), so people understand it without being told.
- It **doubles the collectible**: every press yields a specimen *and* a print.
- It's 2D and cheap.

**Per-object print signatures:**

| Object | Kiss → strain | Fractures in the print | Failure splat → final print |
|---|---|---|---|
| Bubble Wrap | a grid of faint circles | **each pop stamps a crisp ring** at that bubble's mirrored position | a ring grid; popped bubbles saturated |
| Rubber Duck | yellow silhouette from the head down | the honk = a pressure ripple ring; the seam pop = a dark seam line | yellow splash at the seam, a beak-shaped orange spot |
| Jelly | translucent red blob | the skin split = a lighter crack line | glossy red splat with square fruit-cube "holes" |
| Crayon | a waxy strip along its length | snaps = gaps in the strip | a smeared wax bar with crumbs |
| Egg | white shell ring | hairline = grey line; shell gives = shard tiles | **yolk-yellow sun** in the centre, white ring |
| Cake Slice | pink frosting wedge | icing crack lines | frosting smear plus sprinkle dots and a candle-wick dot |
| Soda Can | red rim ring | buckles = concentric rings | puncture = a **fizz spray** of droplets beyond the ring |
| Gummy Bear | translucent green bear | the seam split = 2 lobes | glossy green spread |
| Glass Bottle | no ink, just a pale "frost" outline | cracks = **white frost lines** branching | frost star across the plate (glass prints as frost) |
| The Unsquishable | a tiny, perfect, bright ring that gets brighter and never grows | the groans = the ring pulses | **the platen loses:** a chunky, cartoon graphite crack runs across the *steel strike plate* (never a realistic glass-shatter look, so nobody thinks their phone cracked), one bolt sprite pops off, and the gauge glass cracks |

Stamp sources are **hand-authored CoreGraphics silhouette paths** (top-down outlines, 512² once per object, plus 3 pre-blurred copies for the shadow). They're deterministic, crisp and code-only. There's no offscreen 3D render.

### 3.3 How it changes with the angle
| θ | Top half (what's drawn) | Tabletop: how it's seen (eye 40°/380 mm) | Book: how it's seen (bisector) |
|---|---|---|---|
| 180 | clean plate, faint shadow, sheen sweep invite (§7) | coplanar, 56° off-normal | face-on |
| 150 | shadow sharpening | 28° off-normal | 15° |
| **120** | kiss → small print | **head-on (~0°): the best moment to see the plate** | 30° |
| 90 | print over half its radius, rings | 32° | 45° |
| 75 | tell / soft failures | 48° | 52° |
| 60 | splat or crush | 64°, grazing | 60° |
| 45 | final print (unseen) | 81°: effectively turned away | 67° |

**Sheen (the plate catching the light as it closes):** a soft white strip (CAGradientLayer, alpha ≤ 0.22) across the strike plate. Its position slides from the far edge (θ = 180) to the crease (θ = 60) linearly in θ, and its intensity peaks around 120°. It's the only top-half element that moves with the *real* angle rather than the press state, and it makes the real plate read as polished steel turning in a room.

**Dimming:** in tabletop only, below 75° the platen's field multiplies to 0.55 at 45° (it has entered the wedge's shade). This saves power and matches what the eye expects. The flash ignores the dimming.

### 3.4 Keeping the two halves one press
1. **One frame.** Yellow rails run along both side edges of *both* halves and line up across the crease (the P-48 columns, §5). Hazard jaws sit on the two free edges.
2. **Mirror registration.** The two strike plates, the bolts, and the guide pins and bushings are exact mirror images across the crease. Flat, the phone reads as an opened waffle iron, and the print lands on the footprint's mirror to within ±4 pt.
3. **One light.** The same key direction lights both halves. The platen's sheen follows θ, and the platen's emission lights the object (§2.4).
4. **One clock.** Every event lands on both halves *in the same frame*: contact (flatten + kiss + thud + kiss haptic), each fracture (crack on the object + stamp on the print + sound + haptic), and failure (burst + splat + flash + 1.0 haptic).
5. **One material language.** Both halves use the same enamel, steel, chrome and graphite, so nothing on either half looks like UI.
6. **Nothing crosses the crease**, except the reveal's goo strands (§6.3), the single sanctioned moment.

### 3.5 Guide pins: the tiny detail that sells the clamshell
There are two chrome guide pins on the platen (Ø 10 pt domes, at the mirrored bushing positions). From 150° → contact they get a 1 pt brighter rim. Flat, pin and bushing sit as a mirrored pair across the crease. It's the press's own "these meet when it shuts" diagram, and it costs nothing.

---

## 4. Mapping: hinge angle → gap, contact, strain, failure, flatten

### 4.1 The curve
The same `PressMapping` maths, with new numbers and one change: **the bottom is absolute, and contact floats with the arm angle.**

```
θ0     = min(θ at arm, 168°)            // arm only when θ ≥ 130° (see below)
θc     = min(132°, θ0 − 12°)            // contact angle
θ_end  = 48°                             // visual flat (absolute)
contactT     = (θ0 − θc) / (θ0 − θ_end)  // computed once at arm; 0.30 for θ0 = 168
easeExponent = 1.7
// unchanged PressMapping:
t = clamp((θ0 − θ)/(θ0 − θ_end), 0, 1);  depth = t < contactT ? t : contactT + (1 − contactT)·x^1.7
c = x^1.7,   x = (θc − θ)/(θc − θ_end)   // for θ0 = 168:  c = ((132 − θ)/84)^1.7
approach a = clamp((θ0 − θ)/(θ0 − θc), 0, 1)
```

```swift
extension PressConfig {
    /// Hinge (Fold Press) preset. Touch (P-48) uses the same curve on its virtual angle (§8).
    static let foldPress: PressConfig = {
        var c = PressConfig()
        c.armAngleMax = 168; c.armAngleMin = 130; c.endAngle = 48
        c.contactT = 0.30; c.easeExponent = 1.7; c.hysteresis = 4
        return c
    }()
    /// Capture at arm: contact floats with the start, the bottom never moves.
    func armed(at theta0: Double) -> PressConfig {
        var c = self
        let start = min(theta0, armAngleMax)
        let contact = min(132, start - 12)
        c.contactT = (start - contact) / (start - endAngle)
        return c
    }
}
```
`PressEngine` keeps the armed copy for the press (contactT must not change mid-press). `PressMapping.swift` needs no changes.

### 4.2 Compression by angle (θ0 = 168)
| θ | 168 | 150 | 132 | 120 | 105 | 90 | 75 | 60 | 55 | 48 |
|---|---|---|---|---|---|---|---|---|---|---|
| phase | arm | approach a = 0.5 | **contact** | strain | strain | strain | tell/failure | crush | crush | **visual flat** |
| c | 0 | 0 | 0 | 0.037 | 0.145 | 0.308 | 0.517 | 0.769 | 0.863 | 1.0 |

### 4.3 Where each object's events land (base thresholds, ±2–3° from jitter)
`θ = 132 − 84·c^(1/1.7)`

| Object | Fractures (c → θ) | **Failure** |
|---|---|---|
| Bubble Wrap | 24 pops spread 121° → 57° (the first pop is ~11° after contact) | none (every pop is an event; median pop ~81°) |
| Rubber Duck | honk 0.42 → 82° | **seam pop 0.66 → 66°** |
| Jelly | skin 0.30 → 91° | **splat 0.55 → 73°** |
| Soda Can | buckles 0.28 → 92°, 0.42 → 82°; later 0.68 → 65°, 0.80 → 58° | **puncture 0.55 → 73°** |
| Cake Slice | icing 0.22 → 98°, candle 0.42 → 82° | **squirt 0.62 → 69°** |
| The Unsquishable | groans 0.22 → 98°, 0.46 → 79° | **press cracks 0.70 → 64°** |
| Glass Bottle | crack 0.22 → 98°; 0.62 → 69° | **shatter 0.40 → 83°** |
| Gummy Bear | spread 0.62 → 69° | **seam split 0.36 → 86°** |
| Crayon | 0.52 → 75°, crumble 0.74 → 62° | **snap 0.30 → 91°** |
| Egg | hairline 0.12 → 108°, yolk 0.50 → 76° | **shell gives 0.24 → 96°** |

**Reading this:**
- The soft headliners (can, jelly, cake, duck, steel ball) fail in the **73–64° band** the founder asked for.
- Brittle things fail higher (83–96°). That's material truth (glass and eggshell give under little strain), and it lands where *both* halves are most legible, which suits the glass bottle, the "biggest event in the app".
- Every failure is **≥ 63° even with +0.04 jitter**, above the worst-case display-off angle (55°).
- Against the old mapping (c 0.55 failed at ~86°), the climax moves ~13° deeper into the fold, where the halves visibly converge.
- *Optional, not default:* if Week-0 testers find brittle failures early, raise glass to 0.48 (→ 77°) and egg to 0.32 (→ 89°) in `MaterialProfile`.

**Arming at ≥ 130° guarantees the ≥ 60° failure floor.** With θ0 = 130, θc = 118, so c 0.72 → 62°. Arming lower would compress the curve under 60°. A press must be opened to load it. If the object lands while θ < 130°, the platen plays the "open me" sheen (the §7 sweep in reverse) until θ ≥ 130°. Re-arming after a press needs ≥ 155° (Duogami pattern) or a sealed reveal.

### 4.4 The virtual gap (what "believable separation" means here)
- **Before contact:** s = s0·(1 − a), with s0 = one object rest height. s drives only on-surface cues:
  - the platen shadow: blur = 4 + 36·(s/s0) pt; alpha = 0.08 + 0.27·(1 − s/s0); scale = 1 + 0.25·(s/s0)
  - the anvil plate shade (0.30·a²)
  - quiver (a > 0.6)
  - hiss, scaled with closing speed

  It's linear in a, so **the plate moves exactly as fast as the hand** (pillar 1). It's never drawn as geometry, so it can never disagree with the real air gap.
- **After contact:** the gap *is* the object's compressed height (`surfaceHeight(c)`). The invisible virtual platen entity sits at that height and remains the debris ceiling.
- **Why it reads as the real lid:**
  - The mirrored shadow and print sit on the real lid.
  - The squash leans away from the real hinge.
  - The light on the object rises as the real lid closes over it.
  - The gauge ticks every 5° of real travel.
  - The final crush is the real magnet clap.

  The brain binds cause to the surface that changes in sync, the same misdirection pavement art relies on.

### 4.5 Below the visual flat (48° → closed)
- **Sealed** fires at depth ≥ 0.98 for 150 ms (≈ 49°), at `.closed`, or when the system moves the app to the outer display with depth ≥ 0.6. Depth 0.6 is c ≈ 0.43, about 81°. If the display dies at 55°, c ≈ 0.86, so the press auto-completes off-screen.
- **While the display is lit below 48°:** visuals hold, plus **squeeze-out**. If Week 0 measures display-off ≤ 35°, spread meshes creep a further +15% radius from 48° → 30°, so mess visibly oozes out of the jaws as the halves meet.
- **Felt and heard:** post-crush settling grains every 3° while hinge samples still arrive (on or off screen). Then at `.closed` (the magnet clap) the **final crunch is layered under the ka-chunk**, with a heavy haptic (1.0/0.15 + 120 ms rumble). The last thing you feel is the halves meeting.

---

## 5. What stays from the P-48: the phone becomes the press

| P-48 part (VISUAL-TARGET §4) | Fold Press home (tabletop, 669 × 951 pt upright) | Book (951 × 669 pt) |
|---|---|---|
| **Columns** (chrome, at 20%/80%) | **Yellow enamel rails**, 12 pt, down both side edges of both halves, continuous across the crease. One 1 pt highlight line on the inner edge | rails along the top and bottom edges of both pages |
| **Hazard band** (the platen's lower lip) | **Hazard jaws**: 10 pt, 45° stripes (`#FFB81C`/`#2B2D31`, 8 pt stripe width, so a 16 pt period) at the *top half's far edge* and the *bottom half's front edge*. The stripes are mirrored so they **mesh when closed**, the edges a real machine guards | on the two outer vertical edges |
| **Crown + instrument panel** | **Crown strip**: 64 pt graphite band under the top jaw (y 10–74). It holds the **gauge** (Ø 56 pt, the §4.4 dial texture reused as a 2D image, left), lamps **READY/LOAD** (Ø 14 pt, right), and the **P-48** nameplate. Apple's tabletop guidance puts glanceable, at-a-distance content in the top region | at the top of the platen (leading) page; gauge at the outer corner |
| **Bed + console** | **Console**: 62 pt graphite above the bottom jaw (y 879–941). It holds the keycaps (object chip, Shelf, and Again/Share/Next at reveal), which slide down 40 pt and fade while pressing. A **pilot lamp** (Ø 10 pt) at its right end mirrors LOAD, for low tabletop angles where the crown is turned away. Apple puts touch controls in the bottom region | at the bottom of the anvil (trailing) page, under the right thumb |
| **Anvil, bolts** | the anvil strike plate (§2.1) | the same |
| **Press plate, platen** | the platen strike plate (§3.2) | the same |
| **Gauge behaviour, lamp logic, Unsquishable damage, repair-patch sticker** | unchanged in logic. Damage now shows as: platen crack (top), **anvil dent** (a 3D dent decal under the ball, bottom), a popped bolt (a 3D bolt on the anvil bounces off the front edge under the console), gauge-glass crack. The repair patch is permanent, on the crown strip | the same |
| Cyclorama, gel wall | gone. The gel colour tints the enamel fields (§2.1) | the same |

**Bezel geometry (tabletop):**
- **Top half:** y 0–455.5. Platen field x 12–657, y 74–455.5. Strike plate centred (334.5, 234.7).
- **Crease band:** y 455.5–495.5.
- **Bottom half:** y 495.5–951. Anvil field y 495.5–879. Strike plate centred (334.5, 716.3).

The object (bottom) and the print (top) each sit 240.8 pt (40 mm) from the hinge axis at y = 475.5. Keep the gauge and lamps clear of `reservedRegions(kind: .occlusion)` (the inner FaceTime camera). If the occlusion region conflicts, swap the gauge and lamps left/right.

```
TABLETOP (upright 669×951)            BOOK (sideways 951×669; platen = leading page, anvil = trailing page)
┌──────── hazard jaw ────────┐  0     ┌─┬───── platen ──────┬crease┬────── anvil ──────┬─┐
│(GAUGE)   P-48      ● ●     │ 10     │h│[GAUGE ● ●  P-48]   │▓▓▓▓▓▓│                   │h│
├────────────────────────────┤ 74     │a│                    │▓▓▓▓▓▓│                   │a│
║   ┌──── steel plate ────┐  ║        │z│  ┌──────────────┐  │▓▓▓▓▓▓│ ┌──────────────┐  │z│
║   │ ° shadow→KISS→PRINT°│  ║ 234.7  │a│  │ PRINT (mirror)│  │▓▓▓▓▓▓│ │  OBJECT       │  │a│
║   └─────────────────────┘  ║        │r│  └──────────────┘  │▓▓▓▓▓▓│ └──────────────┘  │r│
╠▓▓▓▓▓▓▓ crease 40 pt ▓▓▓▓▓▓╣ 455–495 │d│                    │▓▓▓▓▓▓│ [keycaps console] │d│
║   ┌─────────────────────┐  ║        └─┴────────────────────┴──────┴───────────────────┴─┘
║   │   ° OBJECT (pops up)°│  ║ 716.3
║   └──── steel plate ────┘  ║
├────────────────────────────┤ 879
│ [chip] [shelf]        (o)  │ console
└──────── hazard jaw ────────┘ 941–951
 ║ = yellow rails (12 pt)   ° = bolts / guide pins (mirrored)
```

---

## 6. Closed: the cover display and the reopen reveal

### 6.1 Closing
| Moment | Inner | Cover (466 × 678 pt, 84 pt trailing clock column) | Sound / haptic |
|---|---|---|---|
| Display hands over (anywhere 55–20°) | system blur | **SEALING…** card: the press's *outside*. A yellow enamel field with hazard stripes on the free edge (the jaws, seen from outside), the gauge (72 pt) **still climbing** with θ if hinge samples arrive, amber LOAD lamp | settling grains continue |
| `.closed` (magnet clap) | — | card snaps to **PRESS SEALED · 48 TONS**. The needle overshoots 8% and settles on the peak; a red peak tick | **crunch + ka-chunk** in the same frame as the clap; heavy 1.0/0.15 + 120 ms rumble; two light "ready" taps after 1.5 s |
| Resting closed | — | "OPEN TO SEE" (Mono 11, breathing 0.6 ↔ 1.0 at 1.2 s; static under Reduce Motion), plus a faint amber seam glow along the hinge edge: the press holding pressure | silence |

The first-run safety line stays as the only text: *"Squish is on-screen only. Never close your phone on real things."*

### 6.2 Reopening (hysteresis: the cover stays lit to ~150°)
- **0 → ~150° (cover still lit):** the card becomes **RELEASING**. The needle falls with θ if samples arrive, the lamp goes amber → green, and a release hiss plays, scaled with opening speed. Gooey objects also get a slow sticky "peel" creak. No reveal content here: the cover is the machine's outside.
- **First inner-display layout after seal (event-gated, not angle-gated):** the reveal plays once. Until then the inner content is frozen at the sealed state, so the system blur hands over onto the sealed image, not an empty plate.

### 6.3 The reveal: a diptych
1. **0 ms:** both halves are visible at once.
   - **Bottom:** the flattened specimen on the anvil, with mess.
   - **Top:** its monoprint.
2. **0–600 ms:** **goo strands** for jelly, cake, gummy, egg yolk and duck seam.
   - 2–4 strands, drawn in 2D, each a pair of tapered curves meeting at the crease (one per half). The only sanctioned crossing.
   - They thin and snap at 40% of the animation, one light haptic tap per snap, plus the release sigh.
   - Dry objects get a crisp "peel" shimmer across the print instead.
3. **100 ms hold**, then the **2 s slow-mo replay** of the failure on the anvil. Re-running the engine timeline at 0.3× shows that the anamorphic object really did burst. Reduce Motion: a 0.5 s crossfade instead.
4. **Reveal sting** (3 pentatonic notes). The **red PRESSED stamp thunks onto the print** (top), and a ruler slides in beside the specimen (bottom) with its new height ("2.4 mm"), plus a stamp tap.
5. **Caption:**
   - **Top:** in a paper label on the platen, outside the stage band: "BUBBLE WRAP · 48 POPS".
   - **Bottom console:** Again / Share / Next.
6. **Collect:** both halves fold their content into one card (the print over the specimen, like a pressed-flower page with its tissue), which shrinks into the Shelf. Collection chime and a light tap. The next object drops onto a clean anvil while the platen's print wipes off with a steel squeegee sweep, crease → far edge (350 ms).

**Card and share asset = diptych:** the print on top, the specimen below, on paper. It's the same on every device (§8), and it's never anamorphic (§9.6).

**Reopening mid-press without closing:** the virtual plate lifts and the shadow returns, blurred. **The print stays.** It's ink (pressure film is permanent). The object keeps its ratcheted damage, minus 10–15% elastic rebound. Pumping works.

---

## 7. Flat (180°) before pressing: invite the fold without words

At flat, both plates face up side by side: an opened waffle iron. Everything wordless:
1. **The landing.** The object drops from +20 mm onto the anvil. Seen anamorphically, it falls *out of the air onto the glass*, with squash-and-stretch, the plop and a light tap. The approach shadow appears faintly at its mirror spot on the platen. The two plates now visibly *belong to each other*.
2. **The lid breathes.** Every 4 s (first run, and until the first fold):
   - The platen's **sheen sweeps from the far edge to the crease** (800 ms, ease-in-out), as if the lid were already swinging over.
   - The guide pins glint as the sweep passes them.
   - On the anvil, the plate shade flickers in for 200 ms just as the sweep reaches the crease.
   - The object does a 1% anticipatory squash ("it knows").
3. **The two-hand grip glow** (today's `PressHints` edge glows), moved onto the **platen's rails near the far corners**: where you'd pick up a lid.
4. The **ghost arc** (today's dotted side-view arc) stays as a first-run-only overlay *on the platen half*, from the far jaw curving to the crease. It retires after the first contact, as today.
5. **READY** lamp green. Gauge at 0 with the 0.3° idle wobble.
6. **Coach text only as a last resort:** after 8 s with no motion below 172°, one label in the console, "Set it on a table. Push the top down slowly." (bible §6.4). It never appears in the stage.

On the first-run script (bible §3.2), the first bubble now pops at ~121°, ~11° after contact. The "oh!" moment is unchanged, just deeper in the fold.

---

## 8. Non-Duo (touch): the P-48 stays, aligned with Fold Press

The P-48 machine view (VISUAL-TARGET §3.2 preset P/L, §4) remains for:
- iPhones without a hinge;
- a Duo in Split View or Slide Over (window < full inner canvas);
- iPad, if ever.

Changes for consistency:
1. **One feel curve.** The touch press drives a virtual θ over the same `PressConfig.foldPress` curve (θ0 168, contact 132, end 48, exponent 1.7). Each object then fails at the same fraction of the stroke on every device, and CI tunes thresholds once.
2. **Prints everywhere.** The same `PlatenPrint` renderer runs offscreen on P-48. The reveal and card are the diptych. At the P-48 reveal, after the platen lifts, it tilts 25° toward camera for 600 ms to flash its print, then settles.
3. **Same bezel vocabulary.** The P-48 console band adopts the Fold Press console (graphite keycaps, pilot lamp), and the hazard band uses the same stripe period.
4. **Object hero scale stays P-48** (VISUAL-TARGET §5). `foldScale` applies only on a Duo.
5. **A Duo in touch mode** (Settings: "drag instead of fold", accessibility) **keeps the Fold Press layout**. Dragging down on the platen half drives the virtual θ, and the platen's sheen sweeps with the virtual angle. A Duo never shows the P-48 full screen except in Split View. *(This replaces the current "Use the touch press even on iPhone Duo" path, which falls back to P-48.)*

---

## 9. Implementation notes (code-only RealityKit, `ARView` non-AR)

### 9.1 View architecture (recommended)
```
FoldPressView (SwiftUI, .ignoresSafeArea, shown when hinge != nil && full inner canvas)
├─ PlatenHalfView     UIViewRepresentable → CALayer stack (2D only, §9.5)
├─ CreaseBand         solid graphite, 40 pt
├─ AnvilHalfView      UIViewRepresentable → ClipView(clipsToBounds) → WarpView(layer.transform = H) → ARView
├─ BezelOverlay       SwiftUI: rails, jaws, crown strip (gauge/lamps as images), console keycaps, pilot lamp
└─ PressHints         first-run ghost arc + grip glows (platen half only)
```
- **One ARView, for the anvil half only.** The top half is 2D. There's no entity duplication, the pixel count halves, and no 3D content can cross the crease, which the design forbids anyway.
- **Rejected alternatives:**
  - Two ARViews, one per half: RealityKit entities can't be in two scenes, so you'd need cloned objects kept in sync and 2× deformation cost.
  - One full-screen ARView with a split render: ARView has one camera, and you'd need `RealityRenderer`/Metal. Revisit only if a v2 wants 3D on the platen.
- **`PressScene` gets `FramingMode`:**
  - `.machine` (today's P-48);
  - `.foldAnvil(eye:glassRect:)`: hides the rig meshes (crown, columns, platen, rod, barrel, bed, sweep), shows the `FoldAnvil` (enamel field, strike plate, bolts, bushings as meshes at y ≤ 0, covering the glass rect + 10% overscan), applies `foldScale`, and keeps the invisible virtual platen as `fx` ceiling and occlusion driver.
- The gauge, lamps and the seal tag move from 3D rig entities to 2D. Reuse the gauge-face CoreGraphics generator as a `CGImage`. Needle and lamp state come from the same engine fields.
- **One update path.** `PressDirector.frame(dt:)` calls `scene.update(...)`, then `platen.update(state)` and `bezel.update(state)` in the same frame, inside `CATransaction.setDisableActions(true)`. Events (`handle(_ event:)`) fan out to all three in the same call.

### 9.2 Detecting the fold, the axis and the halves
```swift
GeometryReader { proxy in
    let folds = proxy.reservedRegions(kind: .division, options: .includeInactive).map(\.frame)
    FoldPressLayout(canvas: proxy.size, fold: folds.first)   // compute ONCE per canvas size
}
```
- **Axis.** The fold frame's long side is the hinge line. When flat the region is *inactive with zero width*, but `.includeInactive` still returns its line. Wider than tall means a horizontal hinge: top/bottom halves, tabletop layout. Taller than wide means a vertical hinge: book layout.
- **Band.** Always 40 pt centred on the region's midline, whatever its current width. **Never relayout when the region activates.** Activation was seen anywhere from 98° to 173° and lags ~1 s; an active-region relayout mid-press would jump the plates.
- **Fallback** if no region is returned: from the canvas alone. 669 × 951 means a horizontal fold at y 475.5; 951 × 669 means a vertical fold at x 475.5.
- **Halves.** Tabletop: platen = top, anvil = bottom. Book: **anvil = trailing page** (the half the outer display sits behind; Apple moves alerts there "closer to where they'll appear when the device closes"), **platen = leading page**. This matches today's assumption that the moving half is the left one.
- **Hinge.** Use the existing `HingeReader` (`onHingeChange`, degrees, 180 = flat). Fold Press is active whenever `hinge != nil`, the scene is on the inner display, and the window is the full inner canvas.
- **Pose → eye.** `CMDeviceMotion.gravity` gives tabletop vs handheld (§2.2). **Week 0:** find which half the IMU lives in. If it's in the platen, gravity must be rotated by θ to get the anvil's attitude.
- **Physical scale:** 6.02 pt/mm [verify]. Inner canvas 951 × 669 / 669 × 951 pt; half = 455.5 pt deep; crease 40 pt ≈ 6.6 mm.

### 9.3 Off-axis projection: making the glass the anvil

**Tier B: guaranteed, no shaders. A symmetric camera plus a keystone warp of the view.**
1. Get the glass corners Gᵢ (anvil frame, scene units, §2.2) and the eye E.
2. Make a `PerspectiveCamera` at E with `look(at: glassCentre, from: E)` and `fieldOfViewOrientation = .vertical`. Project the Gᵢ with a pinhole model in code (camera-space x/−z, y/−z; don't use `ARView.project`, which lags a frame). Take U = max|u|, V = max|v|, and set the vFOV = 2·atan(V). Size the ARView to the aspect U:V, with its height ≈ 1.15 × the half's height in pt (oversample).
3. Solve the 3×3 homography **H** mapping the 4 projected corners (in ARView point coordinates) to the half's 4 screen corners: a standard 8×8 linear solve, ~2 µs.
4. Put the ARView in a `WarpView` with `layer.anchorPoint = .zero`, its position at the half's origin, and `layer.transform` = H as a `CATransform3D`. Core Animation uses row vectors, x′ = (m11·x + m21·y + m41)/(m14·x + m24·y + m44):
   ```
   m11=h11 m21=h12 m41=h13 | m12=h21 m22=h22 m42=h23 | m14=h31 m24=h32 m44=h33 | m33=1, rest 0
   ```
   The parent `ClipView` clips to the half (a rectangular clip, so it's cheap).
5. **When to recompute:** tabletop, on layout or pose change; book, every frame (θ moves the eye). The cost is negligible.

Notes:
- **Touches:** keep `ARView.isUserInteractionEnabled = false` and put gestures on overlays. To hit-test the object, invert H and use the camera unprojection.
- **Softness:** the far (crease) side is magnified ~1.2–1.4× by the warp. The 1.15× oversample covers it. Drop to 1.0 at thermal `.serious`.
- **Snapshots:** `ARView.snapshot` returns the *unwarped* image. Don't use it for user-facing images (§9.6).

**Tier A: try in a Week-0 spike, 2 h. A true off-axis projection matrix.**
- `ProjectiveTransformCameraComponent(projectionMatrix:)` (iOS 18+) takes a custom matrix, but its docs say the matrix must be "either of symmetric perspective or orthographic" and use reverse-Z. An *asymmetric* (off-axis) frustum is therefore unsupported. One developer reported a blank view with custom matrices (forum 788397).
- If it does render correctly with an `ARView` non-AR camera, it replaces the warp and its overdraw. The spike decides.
- **Method (Kooima, "Generalized Perspective Projection"):**
  - The screen corners pa, pb, pc give the axes vr, vu, vn.
  - va = pa − E, d = −vn·va.
  - l = (vr·va)·n/d, r = (vr·vb)·n/d, b = (vu·va)·n/d, t = (vu·vc)·n/d.
  - Place the camera entity at E with rotation columns (vr, vu, vn), so it looks along −vn.
  - Reverse-Z matrix rows:

    ```
    [2n/(r−l), 0, (r+l)/(r−l), 0]
    [0, 2n/(t−b), (t+b)/(t−b), 0]
    [0, 0, n/(f−n), n·f/(f−n)]
    [0, 0, −1, 0]
    ```

    `simd_float4x4` takes columns, so transpose when building it.

**Rejected: lens shift by oversized crop** (camera looking straight down the glass normal, symmetric FOV, crop the visible part). At ε = 40° the glass sits ~50° off-axis. Only ~11% of the frame would be visible, 8.8× the pixels, beyond sane texture sizes.

### 9.4 Eye model inputs per frame
`eye = EyeModel(pose: .tabletop | .handheld(β) | .book(θ), strength: 0.85)` → E in the anvil frame (§2.2). It's stored in `SceneStyle` as `foldEyeDistanceTabletop = 0.380 m`, `foldEyeElevation = 40°`, `foldEyeDistanceBook = 0.320 m` and `foldAnamorphicStrength = 0.85`, all [tune] and all exposed in the Tuning Lab.

### 9.5 The platen layer stack (2D, Core Animation)
Static images are generated once per object and gel:
1. Enamel field.
2. Steel strike plate (CG streak texture).
3. Bolts and guide pins.
4. **Sheen:** `CAGradientLayer` strip; position and opacity from θ (§3.3).
5. **Shadow:** 3 pre-blurred stamp images, crossfaded by s/s0, with scale and opacity.
6. **Print:** the stamp tinted with ink (`CALayer` contents) and masked by a radial `CAGradientLayer` (`type = .radial`), with radius r(c); plus a Newton-ring sprite scaled to r.
7. **Event decals:** rings, frost lines, cracks and splat sprites (pre-rendered per material, ≤ 24 sublayers, positions seeded from the press seed so the replay matches).
8. **Flash:** a white layer, opacity 1 for 2–3 frames.
9. **Dimming** multiplier (tabletop, < 75°).

The cost is a handful of layer property writes per frame, with no offscreen passes (no `masksToBounds` with corner radius on animated layers; use pre-rounded images).

### 9.6 Images that leave the device, and CI
An anamorphic frame looks *wrong* in a flat screenshot: it's stretched toward the crease.
- **Share card and clip:** render the specimen with the existing P-48-style 3/4 product camera (offscreen) next to the 2D print. It's never the warped view. The share clip keeps its cinematic camera.
- **CI produces two artefacts per angle:**
  1. **Raw capture:** a simulator screenshot of the inner display (the pixels).
  2. **Eye-view composite:** a small CI tool (a RealityKit or Python script) texture-maps the raw top and bottom halves onto a hinged two-plane Duo model at θ, adds the 40 pt crease, and renders it from the design eye, for both tabletop (40°/380 mm) and book (bisector, 320 mm). **Critics judge the illusion on the composite, and the layout on the raw capture.**

### 9.7 Performance (budget: bible §9)
- **Anvil ARView:** 669 × 455.5 pt @3× = 2.74 MP (1.15² oversample ≈ 3.6 MP), against today's full inner display at 5.7 MP. The rig's ~40 entities and the sweep are gone. Target 120 Hz while pressing (`CADisableMinimumFrameDurationOnPhone` is already set).
- **Platen:** 2D, ~15 layers, negligible.
- **At thermal `.serious`:** anvil `contentScaleFactor` 2.25 and oversample 1.0, Newton rings off, half the splat sprites, 60 Hz (bible).
- **Recompute H** at most once per frame; tabletop doesn't need it.
- **Power:** the platen dims below 75° in tabletop.

### 9.8 Week-0 device checks (before tuning anything else)
1. Display-off angle when closing, and the reopen hysteresis. These decide squeeze-out (§4.5).
2. Whether hinge samples arrive on the cover display.
3. pt/mm with an on-screen ruler.
4. Which half holds the IMU.
5. The Tier A projection spike.
6. Frame time of the warped ARView at 120 Hz.
7. Watch five people in tabletop: their real eye elevation and distance, used to tune ε and s.
8. The `.division` frame at flat versus folded, in both orientations.

---

## 10. Storyboard (θ0 = 168; tabletop eye 40°/380 mm; book on the bisector)

**180° — flat, invited**
- **Bottom:** the object has landed on the steel strike plate and breathes. Its contact shadow points back toward the crease.
- **Top:** a clean mirrored strike plate, the faint approach shadow at the mirror spot, the sheen sweep every 4 s, glinting guide pins, READY green, gauge at 0.
- **Tabletop sees:** an opened waffle iron lying on the table. The object stands up out of the lower glass (50° off-normal view, the anamorphic sweet spot). The upper half is the same plane, further away.
- **Book sees:** a top-down view: a pop-up lying flat on a page.
- **Sound / haptic:** landing plop + light tap; room tone; first run gets the hiss-clunk.

**150° — approach (a = 0.5)**
- **Bottom:** the plate shade arrives (alpha 0.075); the object is still.
- **Top:** the shadow at half sharpness (blur ~22 pt); the sheen has slid a quarter of the way down.
- **Tabletop sees:** the lid is lifting toward you. The top half is now 28° off-normal, easy to read. The shadow sharpening on it reads as "something is coming close to this".
- **Book sees:** both pages tilt 15° toward you, and the object starts to rise off its page.
- **Sound / haptic:** pneumatic hiss scaled with closing speed, motor hum, gauge twitch. No haptic: it's anticipation.

**132° — contact**
- **Bottom:** a one-frame highlight and a 40 ms hit-stop on the object; its top flattens a touch, LOAD amber.
- **Top:** **kiss**: the shadow's core turns into a wet ink dot.
- **Both halves:** the same frame.
- **Sound / haptic:** contact thud + material contact, and the "kiss" haptic (0.40/0.30).

**120° — strain begins (c 0.04)**
- **Bottom:** a slight bulge, and the lean away from the hinge begins.
- **Top:** a small print (r ≈ 0.21 R) with the first Newton ring. Bubble wrap's first ring is stamped here.
- **Tabletop sees:** **the top half is head-on.** The print and gauge are the clearest they'll ever be, and the object sits right below them across the crease: two halves of one event.
- **Book sees:** both halves at 30° off-normal; the object stands taller.
- **Sound / haptic:** the strain bed starts low; grains every Δθ_g; the gauge ticks every 5° up the pentatonic scale.

**90° — deep strain (c 0.31)**
- **Bottom:** the object's height is ~70% of rest, with a clear lateral bulge, cracks growing and a ~2.5° lean. The egg's shell has gone (96°), the crayon has snapped (91°), the gummy has split (86°).
- **Top:** the print at ~0.6 R, saturating, with rings, and fracture stamps arriving in sync.
- **Tabletop sees:** the lid is vertical, a wall facing you (32°). The print sits ~40 mm up it, exactly behind and above the object. The object's light has grown (wedge light).
- **Book sees:** a 90° open book, both plates at 45°: the most "press-like" view of all. Two faces converging on the object.
- **Sound / haptic:** the bed at ~0.45; grains; gauge mid-dial; creaks.

**75° — tell → soft failures (c 0.52)**
- **Bottom:** stress whitening and a 14 Hz tremor. The glass has shattered (83°); the can, jelly and egg yolk go at 73–76°: a 50 ms hush, then the burst, 80–120 ms hit-stop and 0.3× debris.
- **Top:** the print edge trembles, then **splats**, and the white flash lights the object from the crease side.
- **Tabletop sees:** the lid has passed vertical and leans over the object (48° off-normal, still readable). For the first time the phone physically looks like jaws closing.
- **Book sees:** a 52° wedge.
- **Sound / haptic:** hush → layered failure sound; the 1.0 failure haptic; the ticks resolve to the tonic.

**60° — crush (c 0.77)**
- **Bottom:** cake (69°), duck (66°) and the steel ball (64°, the press cracks) are done. Spread meshes are growing: jam, yolk and fizz puddles. Crumbs settle and persist.
- **Top:** the splat has spread to match the mess. The platen is dimmed (tabletop) and grazing at 64°, so it's seen mostly as a glow.
- **Tabletop sees:** the lid overhangs, but the whole object and its mess are still visible under it. The bottom half is the hero.
- **Book sees:** 60° each; both are still visible.
- **Sound / haptic:** the granular crunch/squelch bed, density scaled with speed; dense, softer debris grains.

**45° — visual flat / seal (c = 1 at 48°)**
- **Bottom:** frozen at full depth. Squeeze-out runs if the display stays lit (§4.5).
- **Top:** turned away (81°), dimmed.
- **Tabletop sees:** a narrow wedge. The specimen is visible under the lid down to ~35°.
- **Book sees:** 67°, glimpsed.
- **Sound / haptic:** the motor spins down; settling grains every 3° (also off-screen if samples arrive).
- *Display may switch off anywhere here: the cover shows SEALING….*

**Closed — the clap**
- **Cover:** PRESS SEALED · 48 TONS, the needle settling on the peak.
- **What you feel:** **the halves meeting is the crush.** The crunch, the ka-chunk and the magnet clap land in the same instant; heavy haptic + rumble; ready taps after 1.5 s.

**Reopen — the reveal**
- **Cover (to ~150°):** RELEASING. The needle falls, green lamp, release hiss.
- **Inner display:** wakes on the sealed image, then the diptych:
  - goo strands across the crease snap (taps);
  - slow-mo replay on the anvil;
  - the PRESSED stamp thunks onto the print;
  - a ruler beside the specimen;
  - the card folds and drops into the Shelf;
  - the squeegee wipes the platen.
- **Sound / haptic:** release sigh → reveal sting → stamp tap → collection chime.

---

## 11. Amendments to the bible and the visual target (on a Duo)
| Doc § | Was | Now |
|---|---|---|
| Bible §2, "Literal jaw vs virtual ram" | virtual ram on screen; the fold is the lever | **The halves are the plates.** Nothing is drawn between them. The press is drawn on both surfaces with a remapped angle (§4) |
| Bible §2, "Where the climax happens" | failure ~120–80°, all action 165–60° | contact 132°, failures 96–64° (soft 73–64°), visual flat 48°, crush felt at the clap |
| Bible §2, "Object placement" | 40% from the crease | 40 mm from the hinge axis (~55%); footprint ≥ 60 pt and image ≥ 24 pt clear of the crease band |
| Bible §2, "Bottom-out" | visual at 60° | visual at 48°; the crunch + ka-chunk at `.closed` |
| Bible §3.1 beats | P-48 visuals | §10 storyboard. Beat 3's "contact print on the top screen" is now the hero of the top half |
| Bible §6.2 | θ0 ≤ 165, end 60, contactT 0.20, exponent 1.6 | θ0 ≤ 168, **end 48, contact at min(132, θ0 − 12), exponent 1.7**, arm ≥ 130 |
| Bible §6.3 | arm at θ ≥ 100 | arm at θ ≥ 130 (hinge); re-arm at ≥ 155 |
| Bible §6.4 book pose | ram from the side, vice in v1.1 | book = pop-up press (anvil = trailing page) with a θ-driven eye. Vice mode is still v1.1 |
| Bible §9 layout | mild off-axis, 60/40 blend; ram housing on top | full anamorphic anvil (strength 0.85); 2D platen |
| VISUAL-TARGET §3.2 preset D | the whole P-48 across the inner display | retired on a Duo (P-48 only in Split View) |
| VISUAL-TARGET §4 | the P-48 is the hero | the P-48 is the non-Duo hero. Its parts map to the Fold Press bezel (§5) |
| VISUAL-TARGET §6.1 bands | portrait bands measured on the full inner display | Fold Press bands: jaws, crown strip, stage (both plates, no UI ever), console (§5) |

---

## 12. Acceptance checklist (Duo, at 180 / 120 / 90 / 60°)
Apply **R** checks to the raw capture and **E** checks to the eye-view composite (§9.6), tabletop and book. Any ✗ in a **bold** check fails the frame.

**Every angle**
- [ ] **R1 Crease:** the 40 pt band is solid graphite, with no pixel of the object, mess, text or control in it. Debris within 24 pt of it is fading.
- [ ] **R2 Clearance:** the footprint is ≥ 60 pt and the projected silhouette ≥ 24 pt from the crease band edge.
- [ ] **R3 Registration:** the print or shadow centre is the footprint centre mirrored across the crease midline, ±4 pt. Strike plates, bolts and pins are mirror-exact.
- [ ] R4 Frame: rails continuous across the crease (same x, ±1 pt); hazard jaws on both free edges with mirrored stripes; gauge and lamps clear of the occlusion region.
- [ ] R5 The object (or its mess) is the most saturated region; no pure black; shadows warm (`#3B2F25` family); bottom half mean luminance 175–215.
- [ ] R6 No UI in either stage field (only the console, the crown strip and the reveal captions).
- [ ] **E1 One press:** a viewer describes it as "the phone is a press / waffle iron", not "a picture of a press". There's no drawn ram, columns or crown anywhere.
- [ ] **E2 Stands up:** the object reads as standing *on* the lower glass. Its base is glued by the contact shadow, its verticals are within ±8° of the composite's vertical, and it isn't stretched (projected height ≤ 1.2× its real height at the design eye).

**180°**
- [ ] The landing has settled. The approach shadow is faint at the mirror spot, READY green, gauge at 0.
- [ ] In a 3-frame sequence, the sheen sweep travels far edge → crease. The grip glows sit on the platen rails. No text on stage.
- [ ] E: an opened clamshell. The two strike plates read as a mirrored pair.

**120°**
- [ ] Contact has happened: a **kiss/print** of radius 0.15–0.3 R on the top half, LOAD amber, the gauge needle off zero.
- [ ] Object c ≈ 0.04: a slight bulge, the lean just beginning. The plate shade is visible on the anvil.
- [ ] E (tabletop): the top half is near face-on, and the print, gauge and object are all legible at thumbnail size. The print sits visually "behind and above" the object.

**90°**
- [ ] **Object height ≤ 75% of rest**, with a clear bulge and a visible lean away from the hinge (2–3°). Fracture marks match on both halves (e.g. the egg's shell tiles plus the print's shard tiles).
- [ ] **Print radius ≥ 0.55 R**, saturated, with Newton rings.
- [ ] Gauge needle in the middle third.
- [ ] E (book): both plates face the object symmetrically, the most press-like frame in the set. E (tabletop): the lid is a wall, with the print directly behind the object.

**60°**
- [ ] **Every object except bubble wrap's last pops is past failure** (the steel ball cracked the platen). Mess is persistent, inside strike plate + 40 pt, and never in the crease.
- [ ] Print = final splat, matching the anvil mess's colour and footprint (raw).
- [ ] E (tabletop): ≥ 80% of the specimen is visible under the overhang, and the bottom half carries the frame. E (book): both halves still read.

**Set-level**
- [ ] The 4 composites in order read as one closing motion: shadow → kiss → print → splat on top, and stand → squash → burst → flat below.
- [ ] Scoring: VISUAL-TARGET §9.2 rubric, plus "Duo-ness" (0–2): 0 = could be any phone, 1 = uses both halves, 2 = the halves *are* the plates.

---

## Sources
**Apple**
- Tech Talk 111463, "Strike a pose with adaptive layouts on iPhone Duo": division vs occlusion regions; inactive with zero width when flat; `reservedRegions(kind:options: .includeInactive)`; tabletop top region for at-a-distance content and bottom region for controls; content across the fold "like a photo across a book's spine"; alerts move to the trailing side. https://developer.apple.com/videos/play/tech-talks/111463/
- Developer forums 847752 (pose detection → the Tech Talk and the HIG "Designing for iPhone Duo"): https://developer.apple.com/forums/thread/847752
- `ProjectiveTransformCameraComponent` (iOS 18+; "symmetric perspective or orthographic", reverse depth): https://developer.apple.com/documentation/realitykit/projectivetransformcameracomponent
- Forum 788397 (custom matrix gives a blank view; unresolved): https://developer.apple.com/forums/thread/788397

**FoldHunt** (Duo apps that treat the halves as physical surfaces; simulator recordings and developer claims, none tested on device)
- Toastie (closing shuts the toaster lid; peek by opening a little): https://foldhunt.com/games/toastie/
- Inkblotter (ink on one page; close; reopen to a mirrored blot): https://foldhunt.com/apps/inkblotter/
- Orisuji (one page lies on the other, pinning whoever is in the holes): https://foldhunt.com/games/orisuji/
- Listing (Paint & Fold, Foldink, Inkblot Duo, Hingami): https://foldhunt.com/iphone-duo/

**Off-axis and head-coupled projection** (Kooima's Generalized Perspective Projection, as used by Unity, PsychoPy and three.js implementations)
- https://medium.com/@michel.brisis/off-axis-projection-in-unity-1572d826541e
- https://psychopy-hoechenberger.readthedocs.io/en/latest/api/tools/viewtools.html
- https://en.wikipedia.org/wiki/Head-coupled_perspective

**Other**
- Axios on Duo novelty apps (Duo-Man, Accorduon): https://axios.com/2026/10/05/apple-iphone-duo-foldable-walkman-app (search summary; the page returned 403)
- Internal: research/05-hinge-ux.md (§1.2–1.3 hinge accuracy, display-off 55–20°, reopen hysteresis to ~150°, canvas and crease sizes; §1.4 Duogami, Crate, DuoBird patterns), research/03-visuals-physics.md §5 (viewing geometry; the fold as camera).
