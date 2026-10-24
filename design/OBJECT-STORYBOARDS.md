# Object storyboards (24 Oct 2026)

The deformation storyboard for every object: what you see, beat by beat, from the plate's first kiss to the flattened specimen. It implements `design/EXPERIENCE-PLAN.md` ("a deformation event at least every 8°") and `design/research/EXPERIENCE-2.md` items 4, 10, 12 and 15. Where it conflicts with older docs, the experience plan wins.

The code is the source of truth:
- the beat grid and each object's beat kinds: `Squish/Scene/Kit/Storyboard.swift` (`ObjectStoryboard`);
- idle life, beat pulses, tremor, pinch-line ooze and the shared beat effects: `Squish/Scene/Kit/ObjectLife.swift`;
- procedural surface detail (shell speckle and pores, wax streaks, the bottle label): `Squish/Scene/Kit/SurfaceDetail.swift`;
- each object's beats: the `onBeat` function in its view under `Squish/Scene/Objects/`.

## 0. The rules every object follows

### The beat grid

Every object gets 16 beats on one compression grid, plus two "tell" beats placed relative to its own seeded failure. The engine's fractures (`MaterialProfile`) are extra events between them.

| c | Fold (provisional, 106° → 48°, linear) | P-48 (132°, ease 1.7) |
|---|---|---|
| 0.01 | 105° | 126° |
| 0.036 | 104° | 120° |
| 0.075 | 102° | 114° |
| 0.122 | 99° | 108° |
| 0.178 | 96° | 102° |
| 0.242 | 92° | 96° |
| 0.312 | 88° | 90° |
| 0.382 | 84° | 84° |
| 0.452 | 80° | 79° |
| 0.522 | 76° | 75° |
| 0.592 | 72° | 70° |
| 0.662 | 68° | 66° |
| 0.732 | 64° | 62° |
| 0.802 | 59° | 58° |
| 0.872 | 55° | 55° |
| 0.942 | 51° | 51° |

- **Tells:** at failure − 0.09 and failure − 0.03 (c). With the press-feel "lag, then give" (visual gain 0.35 over the last 0.12), the first tell still lands about 2° of hand travel before the break.
- **Jitter:** every beat after the first is seeded by up to ±0.004 c (less near contact, where the mapping is steep). Two presses never place their beats identically.
- **The worst gap:** about 4.5° on the fold mapping and 6.7° on the P-48 mapping, with worst-case jitter. `SceneTests.storyboardsNeverLeaveEightDegreesWithoutAnEvent` checks 40 seeds × 3 mappings × 10 objects against the 8° rule.

### Shared mechanics (`ObjectLife`, `OozeRing`, `BeatFX`)

- **Idle life before contact:** a seeded breath (soft things), wobble (jelly), rock (duck, egg) or stillness (rigid things), plus a highlight glint every 2.2–4.2 s. It fades out as the lid closes in (approach 0.75 → 1) and never comes back once the plate has touched. It is transform-only, with no mesh work.
- **Beat pulse:** a small squash-and-spring on the object's life node. Soft objects ring slowly; rigid ones barely move.
- **Tremor:** 14 Hz for 0.15–0.35 s on `.tell`, `.strain` and the engine's `preFailureTell`.
- **Pinch-line ooze:** seeded lobes leave the object's footprint ellipse one per `.ooze` beat, push out from under the edge as the press closes, and never pull back. Every other lobe flings one droplet that lands as a stain.
  - The lobes are children of the object, so they persist through the reveal and leave with the object on the next press.
  - They are capped inside the Duo strike plate.
- **Splatter:** `.fling` beats throw droplets that land as stains and stay.

### Performance (120 Hz budget)

- Beats are discrete. A beat changes a transform, enables a model, or swaps a material.
- The only mesh uploads are the existing `DeformableMesh` ones (duck head, jelly shell, can, cake), still gated on progress changing.
- New effects are scaled entities with cached meshes: ooze lobes, strands, creases, rings, smears.
- Procedural textures are drawn once per session and uploaded asynchronously.

## 1. Bubble Wrap: pops ripple across the sheet

- **Idle:** the light catches one dome's crown at a time.
- **0.01 kiss:** every dome jiggles once and the first dome to go glints.
- **0.03–0.83:** 24 engine pops, one every ~0.035 c, in the seeded pressure-map order. Each pop:
  - snaps a crinkled, stress-whitened crater flat;
  - puffs a little air;
  - **jiggles its neighbours** (within 1.35 pitches, the nearest hardest), so the pops visibly ripple across the sheet.
- **Ripple beats on the grid:** between pops, the domes round the last pop jiggle and a random dome glints.
- **0.802 crease / 0.872 settle / 0.942 sheen:** the popped film crinkles, and glints run over three craters.
- **Flattened:** a flat sheet of craters (mega-bubble surprise unchanged).

## 2. Rubber Duck: squeaks, bulges, the face squashes, the seam pops

- **Idle:** a slow bob-and-rock (about 2° at 0.45 Hz).
- **Beats:**

  | c | Beat | What you see |
  |---|---|---|
  | 0.01 | kiss | Squeak: the beak pops and a highlight pings |
  | 0.036 | bulge | The body bulges and the face goes **wide-eyed** (eyes ×1.2) |
  | 0.075 | squeak | The beak pops, with an air puff from the beak |
  | 0.122 | squash | The face **squints** (eyes y × 0.55) |
  | 0.178 | crease | Two vinyl creases appear at the neck |
  | 0.242 | wobble | A tail-flick tremor |
  | 0.312 | squash | The eyes stretch into **ovals** as the head flattens |
  | ~0.42 | (honk) | Engine honk: the beak pops big and the duck pulses |
  | 0.382 | sheen | The vinyl highlight runs along the back |
  | 0.452 | strain | The **seam shows**, pale (stress-whitened vinyl) |
  | 0.522 | crease | A crease runs down the chest |
  | tell ×2 | tell | The seam darkens, the duck trembles, and air hisses from the seam |
  | 0.592 | strain | The seam darkens further |

- **Break (~0.66, seam pop):** a dark seam, a 6% deflate, an air puff, and the face pinned at ovals. The vinyl skirt squeezes out.
- **After the break:**
  - 0.662 (ooze): an air ring leaves the seam;
  - 0.732 (squash): a **pancake face**, eyes at y × 0.312, xz × 1.5, beak flat;
  - 0.802: a wheeze from the tail;
  - 0.872: the skirt pulses;
  - 0.942: a last puff.
- **Flattened:** a 1.7× yellow pancake. The face is squashed but always intact (cartoon, no gore). Creases, the seam, a wet ring and catchlights on the eyes remain.

## 3. Jelly: wobbles, then oozes out of the pinch line

- **Idle:** a wandering wobble-lean (about 1.7°).
- **Before the split:**
  - 0.01 kiss: a dimple bounce and a gloss ping on the top.
  - 0.036 and 0.382 wobble: big wobble kicks.
  - 0.075 bulge.
  - 0.122, 0.178, 0.312, 0.452, 0.592, 0.732 and 0.872 ooze: a new raspberry lobe **squeezes out from under the base** each time, with every other one flinging a bead.
  - 0.242 strain and both tells: the skin goes **taut**, thinner and brighter in three steps, with a tremor; the second tell squeezes out a bead.
- **Skin split (~0.30, engine):** a squirt from one side.
- **Splat (~0.55, engine):** splorts and droplets. The disc grows to Ø 0.15.
- **After the splat:**
  - 0.522 and 0.802 fling: droplets land and stay;
  - 0.662 wobble: an aftershock wobble plus a fling;
  - 0.942 settle: a glint on the puddle.
- **Flattened:** the existing puddle (relaxes at the reveal), ringed by up to 8 persistent ooze lobes and stains.

## 4. Crayon Box: seven colours, snap snap, rainbow smear

The single crayon is replaced by a **Crayon Box**: an open yellow tray with a green band, holding seven wax crayons in rainbow order. Four lie on the bottom and three nest in the grooves on top. Each crayon is pre-split at a seeded point and has a printed WAXO wrap in its own colour, wax-streak detail and fresh-wax core discs. The display name is now "Crayon Box".

> **Founder P0 (the crayon still looked intact after the press).** The cause was in the old `CrayonView`. After the snap, the crayon was three rigid debris pieces lying end to end, and its height curve stopped at 25% of a 32 mm crayon. The debris world flattened each piece to about half its thickness and widened it by about 1.4×. From above, a lying cylinder squashed vertically is still a crayon of the same outline, so the reveal looked intact. It was the same on the Fold Press and the P-48.
>
> **The fix:** no debris. The pieces are posed analytically (`CrayonBox.rows`, `slabScale`) into slabs ≤ 22% of the box's height and up to 2.4× wider. Seven colour smears spread under them, and the walls fold flat. `SceneTests.everyObjectEndsVisiblyCrushed` now drives every object through a full press and fails if any ends less than 55% lower or, except the bubble-wrap sheet, without a wider footprint.

| c | Beat | What you see |
|---|---|---|
| 0.01 | kiss | The box flexes |
| 0.036 | squash | The walls lean out |
| 0.075 | bend | A top crayon **bows sideways** (it shows from above) |
| 0.122 | crease | The walls crease and lean further |
| 0.178 | bend | A second top crayon bows |
| ~0.21, ~0.27 | tells | **Stress rings whiten** at the bends; the bows deepen; tremor |
| 0.242 | bend | The third top crayon bows |
| ~0.30 | SNAP (engine failure) | All three top crayons snap: halves kink apart with a gap, rainbow flakes, and the plate lurches down onto the bottom row |
| 0.312 | fold | The front wall folds flat |
| 0.382 | bend | Two bottom crayons bow |
| 0.452 | fold | The end walls fold flat |
| ~0.52 | SNAP (engine) | The bottom row snaps; every wall goes flat |
| 0.522 | chip | Flakes off a break |
| 0.592 | smear | Seven colour lanes appear under the crayons |
| 0.662 | fold | The back wall flattens |
| ~0.74 | crumble (engine) | Rainbow flakes; the lanes run on out of the box |
| 0.732, 0.802, 0.872 | smear | The lanes widen until they meet, making a **rainbow smear** |
| 0.942 | settle | A glint |

**Flattened:** seven thin, wide wax slabs in rainbow order, kinked at their breaks, on a rainbow smear, in a flattened box. The `secondColourCore` surprise shows raspberry cores at every break.

## 5. Egg: a hairline spreads, the shell splinters, the yolk floods

- **Idle:** a slow rock. The shell is speckled and mottled with fine pores (procedural colour and normal maps; the shell patches now carry UVs).
- **Before the give:**
  - 0.01 kiss: the apex flattens a hair and glints.
  - 0.036 strain: a pale **stress patch** appears on the top.
  - 0.075 crack: the **hairline starts**.
  - ~0.12 (engine crack): it grows on.
  - 0.122 branch: a **second hairline branches** back toward the blunt end.
  - 0.178 branch, then the tells: a **third branch** runs toward the tip, the stress patch grows twice, and the shell trembles.
- **Break (~0.24, the shell gives):** 24 shards drop flat on a ring round the yolk, with a puff of shell flakes. The white and the yolk dome appear.
- **After the give:**
  - 0.242 chip: two shards hop and settle.
  - 0.312 and 0.662 ooze: the **white squeezes out** past the shell ring.
  - 0.382 wobble: the yolk dome wobbles and glints.
  - 0.452 strain: the yolk skin goes taut.
  - ~0.50 (engine): the yolk breaks.
  - 0.522, 0.592, 0.732 and 0.872 ooze: **yolk lobes flood out** over the white.
  - 0.802 fling: droplets.
  - 0.942: a glint on the yolk.
- **Flattened:** a yolk sun with runny lobes over a lobed white, shell tiles round it, and persistent stains. Chick and double-yolk surprises are unchanged.

## 6. Cake Slice: crumbs, cracks, the filling squeezes out

- **Idle:** a soft breath.
- **Beats:**
  - 0.01 kiss: candle wobble (the flame goes out at contact, as before).
  - 0.036 and 0.178 bulge: a sprinkle hops.
  - 0.075, 0.312 and 0.522 crease: a new **hairline cracks the cream** each time.
  - 0.122, 0.382 and 0.662 chip: **crumbs trickle** off the sponge.
  - ~0.22 (engine): the icing cracks.
  - 0.242, 0.452, 0.592, 0.732 and 0.872 ooze: the **filling squeezes out of the pinch line** in pink lobes, or jam for the surprise.
  - ~0.42 (engine): the candle bends flat.
  - Tells: tremor and crumbs.
- **Break (~0.62):** frosting tongues, crumbs and sprinkles burst (unchanged).
- **Flattened:** the squashed slice with filling lobes, tongues, crumbs and sprinkles all persisting.

## 7. Soda Can: the rim strains, rings buckle one by one, then fizz

- **Idle:** still, with a glint off the rim.
- **Beats:**
  - 0.01 kiss: glints run round the rim ring.
  - 0.036 strain: the lid **tinks** in.
  - 0.075, 0.312 and 0.732 crease: **label wrinkles** (chevrons) on the shoulder.
  - 0.122, 0.242 and 0.382 sheen: a glint runs down the side.
  - 0.178 buckle: the next band **pre-buckles** and the can trembles.
  - ~0.28 and ~0.42: engine buckles 1 and 2, one concertina ring each.
  - 0.452 hiss and the tells: **fizz leaks round the tab**.
- **Break (~0.55, buckle 3 punctures it):** a fizz geyser for 0.7 s, plus a puddle.
- **After the puncture:**
  - 0.522, 0.662 and 0.872 ooze: **fizz lobes** squeeze out from under the base;
  - 0.592 and 0.802 fling: spurts from the fold;
  - ~0.68 and ~0.80: engine buckles 4 and 5;
  - 0.942: a glint and a few last bubbles.
- **Flattened:** a ridged disc with ten or more wrinkles, a fizz puddle and its lobes.

## 8. Gummy Bear: a chewy stretch and a seam split (never a splat)

The gummy must read nothing like the jelly. The jelly wobbles and splats. The gummy **chews**: it stretches, necks, splits, and strings.

- **Idle:** a slow, heavy breath, with sugar glints.
- **Before the split:**
  - 0.01 kiss: a heavy, slow bounce (2.6 Hz, well damped).
  - 0.036 bulge: the belly bulges and glints.
  - 0.075 stretch: the first **chewy stretch** step. The bear widens in x and narrows in z, keeping its volume.
  - 0.122 sheen: the surface goes taut.
  - 0.178 strain: a **pale stress line** appears down the seam, over the head and down the belly.
  - 0.242 stretch: the second stretch step.
  - 0.312 strain and the tells: the stress line widens and brightens; the stretch kicks; tremor.
- **Break (~0.36, seam split):** the halves part at the seam with five **chewy strands** bridging the gap.
- **After the split:**
  - The strands **thin as the gap opens** (r ∝ 1/√length).
  - 0.382, 0.452, 0.522, 0.592 and 0.732 strand: one strand **snaps** each time, its ends beading onto the plate.
  - ~0.62 (engine): the **slap**. The halves come down flat into two chewy pads, which are sticky footprints, not a puddle.
  - 0.662 and 0.872 stretch: the pads pull.
  - 0.802: glints.
- **Flattened:** two flat, glossy halves, the rainbow cross-section showing for that surprise, two pads, and beads where the strands snapped.

## 9. Glass Bottle: silent stress, the crack webs, then the shatter

- **Idle:** still, with a glint running along the glass.
- **Before the shatter:**
  - 0.01 kiss: glints along the top.
  - 0.036 and 0.178 glow: **stress glow** (the glass whitens a step, five steps in all).
  - 0.075 chip: a **fleck chips off the lip**.
  - 0.122 crack: the **crack stars start early** and creep. The engine crack at ~0.22 only makes them louder.
  - 0.242 crack: a glint at the impact.
  - 0.312 strain and the tells: more glow, tremor.
- The label now carries a printed **SEA GLASS** wordmark and a wave rule (procedural texture).
- **Break (~0.40):** the shatter, unchanged and still the app's biggest event. Beat effects draw from their own random stream, so the pile for a seed is the same whichever beats fired.
- **After the shatter:**
  - 0.382, 0.522, 0.662 and 0.942 settle: two shards **tinkle** (hop and settle) until the seal freezes the pile;
  - 0.452 and 0.802 sheen: glints on the pile;
  - 0.592, 0.732 and 0.872 chip: grit puffs.
  - ~0.62 (engine): the crunch into sea glass.
- **Flattened:** the frozen heap of sea glass with its label scraps.

## 10. The Unsquishable: the press loses

- **Idle:** still, with the reflection sweeping.
- **Beats:**
  - kiss and sheen: glints sweep over the ball.
  - 0.075, 0.242, 0.452 and 0.592 glow: the steel **warms** a step at a time (a faint ember tint).
  - 0.178, 0.312, 0.522, 0.662 and 0.802 chip: grit and sparks squeeze out at the contact.
  - The tells: a tremor and a warm step.
- The engine's groans (0.22, 0.46) and the press cracking (0.70) are unchanged.
- **Flattened:** the ball is untouched and the anvil is dented.

## New press events needed (for the press-feel and audio engineers)

1. **Crayon Box snaps:** seven crayons now snap in two volleys (top row of 3 at the failure, bottom row of 4 at fracture 1), but `MaterialProfile.crayon` still has three fractures. The best feel would give each crayon its own snap: about seven fractures between 0.26 and 0.522, with the failure on the first top-row snap, and the crumble at about 0.74. The view would then snap one crayon per fracture.
2. **Strand snaps (gummy) and shard tinkles (glass)** are visual-only beats. If audio wants them, the storyboard beats could be exposed as a `PressEvent.beat(kind:ordinal:)`. They are seeded and deterministic (`ObjectStoryboard.beats(kind, seed:)`), so Feedback can also compute them itself from the compression.

## Follow-up for a 3D-art round (not done here)

- Cake: sponge-crumb texture and sponge normal (the cake body needs side UVs; the planar UVs only suit the cream).
- Duck and gummy: vinyl orange-peel and sugar-frost normals. Their SDF meshes have no UVs, so they need triplanar UVs or a shader.
- Jelly: inner air bubbles and specular breakup.
- Can: brushed-aluminium lid normal; real torn-metal edges at the puncture.
- Glass: per-shard edge chipping.
- Duck: a real seam bead mesh.
- The Fold platen print (`FoldStamps`, not Objects-owned) still draws the crayon as one cobalt crayon. It should draw a rainbow smear for the Crayon Box. The cover's "CRAYON" label (`CoverView.swift:590`) and the shelf icon art (`Theme.swift:823`) should also follow the rename.
