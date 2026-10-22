# Squish — Design Bible v0.1

*The single source of truth for what Squish is, how it feels, and how it is built. Synthesised on 22 Oct 2026 from the six research reports in `research/` (01 haptics, 02 sound, 03 visuals/physics, 04 psychology/UX, 05 hinge UX, 06 market). Where the reports disagreed, this document makes the call and says why. Every number marked **[tune]** is a starting value to be confirmed on a real iPhone Duo in Week 0.*

---

## 0. The one-paragraph product

**Squish turns your £2,000 phone into a hydraulic press.** Pick a (virtual) object: bubble wrap, a rubber duck, an egg, a glass bottle. It sits on the lower half of the screen. Push the top half down slowly and watch, hear and *feel* it strain, crack and give way, all following your hand. Snap the phone shut with a heavy *ka-chunk*. Open it again to reveal the flattened result, stamped as a pressed specimen and added to your collection. No ads, no in-app purchases, no timers. It's a calm, ridiculous and deeply satisfying ritual.

**Pitch line:** *"Your £2,000 phone is now a hydraulic press. Put something inside, close it slowly, and feel it give."*

---

## 1. Design pillars (in priority order)

1. **The hinge is the hand of God.** The user's fold drives everything continuously. Never play a canned animation where the hand should be in control. Latency from hinge to response is the game feel. *(03 §2, 04 §1.1)*
2. **Tension → release → reveal.** Anticipation is half the pleasure. The strain build-up gets as much craft as the break, and the reveal is the moment people remember (peak-end rule). *(02 §1, 04 §1, 04 takeaway 7)*
3. **Sound, haptics and visuals land together.** Every visible event has a sound and a haptic in the same frame, and vice versa. Apple's three principles are causality, harmony and utility. *(01, 02 §2.3, 04 §1.3)*
4. **Material truth, stylised.** Each object fails in its own signature way. Stylised and reliable beats physically accurate (the Smash Hit lesson). *(03 §1, 04 §1.3)*
5. **Predictable physics, small surprises.** Mastery comes from consistent behaviour. Delight comes from per-press variation: crack patterns, surprise cores, rare golden variants. *(03 §1, 04 §1.2)*
6. **A toy, not a game.** No score on the main loop, no fail states, no timers, no currency, no streaks, no notifications, no ads, no IAP. *(04 §2–3, 06 §3)*
7. **Calm, not rage.** Position Squish as satisfying and calming, never as "anger therapy" (venting meta-analysis). The slow close is the product. *(04 §1.1)*

---

## 2. Decisions that resolve conflicts between reports

| Topic | Reports said | **Decision** | Why |
|---|---|---|---|
| Where the climax (failure) happens | 04: 25–45°. 01: 60–30°. 03: 70–55°. 05: finish all visible crush by 60° | **All visible action happens between 165° and 60°. Failure typically lands at ~120–80°.** Below 60° is the "sealed" phase: felt and heard, not seen | The inner screen may switch off anywhere from ~55° to ~20° (simulator reports conflict). Design for the worst case, then extend if hardware allows (§6.3). Viewing geometry also degrades below ~60° |
| Literal jaw vs virtual ram | 03: align the plates with the physical halves. 05: a literal jaw puts contact at 30–60° | **Virtual ram on screen, driven by a remapped angle.** The physical close is the *lever* and the screen shows the *press*. A subtle ram tilt (≤10°) toward the real top half is flavour only | Keeps the climax visible and lets every object use the same comfortable range |
| Object placement | 03: bottom half, ~60% toward the front edge. 05: lower half, near the fold | **Lower half, centred ~40% of the way from crease to front edge, never within 1 cm (~40 pt) of the crease** [tune] | Near enough to the fold to be seen from above at mid angles, far enough to stay visible as the top half closes |
| Bottom-out thunk | 01: at ~13°, just before the magnet clap. 05: depth 1.0 at 60° | **Two beats:** (a) the *visual* bottom-out at 60°, with the heaviest strain, and (b) the **ka-chunk** on `.closed` (the magnet clap) with a heavy haptic, the sound, and the cover display card. Between 60° and closed, soft post-crush grains keep the hand rewarded | Continuous reward through the full travel, and the hardware clap becomes part of our sound design |
| Fast slams | 01: make slams *more* rewarding. 05: no reward, coach slowness (Guideline 2.4.2) | **Slams work and still feel good** (failure fires early with full intensity, more debris), but **nothing rewards them**: no badge, no achievement. **Perfect Squish** quietly rewards slow, steady closes. One gentle hint ("slowly…") appears only on repeated slams | Satisfying for everyone, safe for App Review, and teaches slowness by consequence |
| Damage on reopen | 04/03: monotonic. 05: plastic + 10–15% elastic | **Plastic ratchet + elastic remainder + irreversible fractures.** Reopening mid-press lifts the ram. The object stays crushed to its maximum depth, with 10–15% (per material) springing back. Fractures fire once | Matches the press metaphor, hides sensor noise and enables "pumping" |
| Platform | 06/05: universal with a touch fallback. 04: fallback for accessibility | **Universal iPhone app.** The Duo is the hero. Other iPhones get **Pinch Press** (vertical pinch or drag on the ram handle) running the same engine | 100× addressable market, Apple discourages Duo-exclusive apps, and it covers accessibility and the simulator |
| Rendering | 03: RealityKit + CustomMaterial | **SwiftUI + RealityKit (`RealityView`) + Metal `CustomMaterial` geometry modifiers**, with `LowLevelMesh` for spread meshes and `PostProcessEffect` bloom. No Unity, no SceneKit | Text-only AI developer, native hinge API, proven deformation path since iOS 15 |
| Audio | 02: AVAudioEngine custom graph. 01: AHAP `AudioCustom` for one-shots | **AVAudioEngine for everything continuous**, plus **haptic AHAP/code events fired in the same code path** as each one-shot. `AudioCustom` stays only as a fallback if sync measures > 20 ms | 02 cites crash reports when mixing `AudioCustom` with AVAudioEngine. One clock, one mixer, one limiter |
| Art direction | 03: stylised vinyl-toy / candy-clay 3D | **Adopted** | The only option that is satisfying, consistent and buildable by code |

---

## 3. The experience, beat by beat

### 3.1 The press ritual (8–20 s per press)

| Beat | Hinge | What you see | What you hear | What you feel |
|---|---|---|---|---|
| **0. Place** | ≥165° (open) | Object drops onto the steel anvil, squash-and-stretch landing, settles. Press lamps glow | Weighty material-tinted *plop* | Light tap on landing |
| **1. Idle** | ≥165° | Faint ghost arc along the hinge (first run only); object "breathes" (jelly wobble, crumb settle) | Quiet workshop room tone (−40 dBFS) | Nothing |
| **2. Approach** | 165° → contact (t 0→0.20) | Ram descends from the top half; the contact shadow darkens and spreads; pre-contact quiver (0.5% scale jitter) | Pneumatic hiss opening with closing speed; motor hum | Nothing (anticipation) |
| **3. Contact** | t = 0.20 | One-frame highlight, 40 ms hit-stop (object only); the contact print starts on the top screen | Contact thud + material contact sound | Soft "kiss" transient (0.40/0.30) |
| **4. Strain** | deformation band | Bulge, squash (volume-preserving), crack decals grow, 1–2 px local micro-shake, flakes | **Gauge ticks every 5° climbing a pentatonic scale**; strain loop rising; procedural creak | Continuous strain bed swelling (≤0.7) + **grains per degree of travel** (the compliance illusion) |
| **5. Tell** | final Δc = 0.08 before failure | Stress whitening, tremor | Micro-cracks accelerate | Bed sharpness +0.2; 14 Hz tremor ±0.08; micro-cracks 3→15/s |
| **6. Hush** | 50 ms before failure | — | Audio ducks −12 dB | Bed and grains off |
| **7. Failure** | material threshold | 80–120 ms hit-stop on the object; burst (pieces, spray, confetti); **top screen flashes white 2–3 frames** (lights the bottom screen); debris at 0.3× for 250 ms | Layered event: transient + body + debris; ticks resolve to the tonic | The only 1.0-intensity moment besides the ka-chunk |
| **8. Crush** | after failure → 60° | Spread meshes grow (jam, yolk, fizz puddle), pieces flatten, crumbs settle and **persist** | Granular crunch/squelch bed, density ∝ speed | Dense, softer debris grains |
| **9. Seal** | 60° → closed | Visuals frozen at full depth (the screen may go dark) | Motor spins down; soft settling | Settling grains |
| **10. Ka-chunk** | `.closed` (magnet clap) | **Cover display:** "PRESS SEALED · 48 TONS · OPEN TO SEE" card with a gauge needle settling | **Ka-chunk** (fixed brand sound) | Heavy thunk (1.0/0.15 + 120 ms rumble), then two light "ready" taps after 1.5 s |
| **11. Reveal** | first inner-display layout after seal (event, not angle) | Ram lifts with stick or cheese-pull strands; 100 ms hold; 2 s slow-mo replay of the failure; the **pressed specimen card** pops in (ease-out-back) and the red PRESSED stamp thunks | Release sigh → **reveal sting** (fixed, 3 pentatonic notes) | Material reveal haptic (peel / crumbs / fizz) + stamp tap |
| **12. Collect** | — | Card shrinks into its shelf slot; 1.5 s quiet; the next object slides onto the anvil | **Collection chime** (fixed) | Light success tap |

### 3.2 First run, with zero text
*(From 04 §B, kept as the canonical script.)*
1. 0.0 s: black screen, a deep *hiss-clunk*, the steel plates fade in.
2. 0.8 s: **Bubble Wrap** drops onto the anvil.
3. 1.5 s: a ghost arc pulses on the hinge, and both outer edges glow to suggest a two-hand grip.
4. The user starts closing. At ~160° the first bubble **pops**. That's the "oh!" moment, and the ghost arc fades for good.
5. A ripple of pops follows. Slow closing gives distinct pops; fast closing gives a rattle.
6. Final volley, flatten, seal, ka-chunk, cover card. Reopen for a slow-mo replay and the card "BUBBLE WRAP · 48 pops".
7. Next up: **Rubber Duck**, with a rising squeak and a comic *bloop*. The second, different reaction teaches that every object is different.
8. After the second press the Shelf handle bounces once, and the user discovers the collection.

**The only first-run text** is a single cover-display hint, shown once: *"Squish is on-screen only. Never close your phone on real things."* (App Review 2.4.2 and real-world safety, 05/06.)

---

## 4. Launch objects (10) and the content model

Each object answers a different question: "what will *this* do?" Each has a distinct failure signature, a surprise, and is buildable procedurally.

| # | Object | Unlock | Behaviour | Signature moment | Surprise (seeded) | Build technique |
|---|---|---|---|---|---|---|
| 1 | **Bubble Wrap** | open (onboarding) | Discrete pops | A ripple of individual pops; each bubble has its own threshold | Rare "mega bubble" | Dome grid, per-cell deform, crinkle normals |
| 2 | **Rubber Duck** | open | Elastic → seam pop | A squeak whose pitch rises with pressure, a comic honk, a *bloop* flat; springs back with overshoot on reopen | Squeak pitch varies per duck | SDF blob mesh, analytic squash, elastic 40% |
| 3 | **Jelly** | open | Gel | Wobbles, spreads, splorts out the sides; jiggles on reopen | Fruit pieces inside | Lathe mould + strong wobble springs + spread disc |
| 4 | **Crayon** | open | Brittle-waxy | A clean SNAP (~0.35), a second snap, then a waxy smear | Hidden second-colour core | Lathe + pre-sliced pieces + smear decal |
| 5 | **Egg** | open | Shell + liquid | Hairline cracks spread, *crack*, yolk spreads | 1/8 tiny toy chick (toy, not alive); rare double yolk | Lathe, plane-sliced shell, yolk + albumen spread meshes |
| 6 | **Cake Slice** | open | Soft crumb | Frosting oozes, candle bends, sprinkles burst | Jam centre | Extrusion, analytic squash, crumb particles that persist |
| 7 | **Soda Can** | squish 3 different things | Thin metal | Concertina buckles (×5), then a fizz geyser | Fizz colour | Lathe + procedural buckling rings + spray + puddle |
| 8 | **Gummy Bear** | squish 6 times | Plastic gel | Splits at the seam into lobes and spreads; glows where thin | Rainbow layers in the cross-section | SDF + marching cubes, fake SSS |
| 9 | **Glass Bottle** | earn a Perfect Squish | Tension → shatter | A long creak (no screech), then the biggest event in the app: a stylised, chunky shatter | Message-in-a-bottle confetti | Lathe, seeded pre-fracture (≤300 shards), transparent PBR |
| 10 | **The Unsquishable** (secret steel ball bearing) | squish all 9 | Comedy subversion | The press strains, the gauge redlines and the **press** cracks instead; reopen to a dented plate and the card "PRESS 0 – BALL 1" | — | Sphere + cracked-ram decal; costs almost nothing |

**Content rules (12+ tone, 9+ rating target):**
- No living creatures. Animal *toys* are fine.
- No faces on anything that's destroyed; the duck survives.
- No body parts, and nothing bodily in ooze colours.
- No real brands; fictional labels are drawn in code.
- Glass is chunky and soft-edged.
- No trypophobic hole clusters.
- Edgy humour lives in **names and flavour text**, never in imagery: 3–5 flavour lines per object, e.g. Cake: *"It wasn't your birthday anyway."*

**Per-press variation:** each press gets a seed that sets:
- crack thresholds jittered ±0.04
- tone ±0.5 semitones
- crack pattern and debris
- the surprise roll
- **Golden** variant at 1/50, with the odds disclosed in Credits

**Backlog for free updates** (one new behaviour per drop):
- **Gooey:** Slime, Ketchup Sachet, Toothpaste Tube, Marshmallow
- **Brittle:** Ice Cube, Fortune Cookie, Chocolate Bar, Crisps Packet
- **Contents:** Piñata, Geode, Water Balloon, Capsule Egg
- **Tough:** Tennis Ball, Coil Spring, Diamond
- **Humour:** Alarm Clock, "Monday"
- **Seasonal:** Christmas Cracker, Bauble, Snowman (December In-App Event)
- **v1.2 headline:** **Stack mode** (two objects at once)

---

## 5. Screens and UI

**Four screens, kept tight.** During a press there is **zero UI**: the plates are the frame.

1. **Press** (≈90% of time): the plates and the object. Hosts the idle, press, reveal and replay states. A pull-up handle opens the Shelf.
2. **Shelf** (bottom sheet): a sticker-album / herbarium grid with 10 slots. Locked slots show embossed silhouettes plus a one-line hint. Tap to place. Tabs: *Objects* (best card per object: Golden > Perfect > normal) and *Squished* (the last 200). Quiet "7/10 pressed".
3. **Card detail** (sheet): the pressed specimen. It's an orthographic top-down render on paper with an SF Mono label: `CRUSHED AT 92° · 48 TONS · 112 FRAGMENTS · Ø 7.4 CM · №0042`, plus traits and a seeded rotated red **PRESSED** stamp. Actions: Replay, **Share clip**, Share image, Delete.
4. **Settings** (sheet via a cog on the Shelf):
   - Sound On/Off
   - Sound style: **Workshop / Soft** (Soft = the misophonia-safe mode: low-pass 6 kHz, half grain density, no wet layers)
   - Haptics: Off / Soft / Full
   - Reduce Motion (follows the system setting)
   - Visual onomatopoeia (off by default; on automatically when the system SDH setting is on)
   - Press without folding (Pinch Press)
   - Golden odds, credits

**Cover display (closed):**
- **After a press:** the sealed card (gauge peak, tonnage, teaser silhouette, "Open to see").
- **When launched closed:** a trophy shelf with an object picker. The picked object is queued onto the anvil, with a looping "open to press" glyph. Never block.

**Visual language, "tactile industrial-lite":**

| Element | Choice |
|---|---|
| Studio backdrop | Warm off-white `#F3EEE6` |
| Press frame | Graphite `#2B2D31` |
| Ram and accents | Hydraulic yellow `#FFB81C` |
| Stamp red | `#D7263D` |
| Objects | Saturated candy: raspberry `#E8336F`, lime `#8BD448`, duck `#FFD23F`, cobalt `#2F5BEA` |
| Hazard stripes | One band only |
| Typography | SF Pro Rounded Heavy (display), SF Mono (readouts) |
| Icons | SF Symbols only |
| Brightness | Mid-key, bright world: dark scenes look milky on the matte nano-texture display |

**App icon:** a yellow ram flattening a raspberry gummy bear into a pancake, on graphite. It's rendered from our own 3D scene. A/B test a second icon: a half-open Duo silhouette with a flattened duck squeezing out.

---

## 6. Hinge interaction spec

### 6.1 Input pipeline
```
onHingeChange (SwiftUI Angle) / UIHingeInteraction (radians → degrees)
  → ignore for 1.5 s after launch / scene activation
  → One-Euro filter (minCutoff 1.2 Hz, β 0.04, dCutoff 1.0) [tune]      → θ_f, ω (°/s, <0 closing)
  → depth mapping (§6.2)                                                → measuredDepth
  → plastic ratchet: damage = max(damage, measuredDepth × plasticity)   → fractures fire ONLY here
  → render loop (CADisplayLink, 120 Hz): critically damped spring ω≈22 rad/s toward
    depth(θ_f + ω·lead), lead ≤ 50 ms and only while the last sample is < 80 ms old;
    hold (no drift) when samples stop
  → visual deformation = max(damage, renderDepth)
```
- **No prediction ever crosses a fracture threshold.** Fractures come from measured data only.
- **Hysteresis:** ±4° on every state transition. Re-arming the contact event needs +8°.
- **Low-rate fallback:** if the sample interval is > 100 ms (thermal / Low Power), raise spring smoothing and disable prediction.

### 6.2 Angle → press mapping
```
θ0     = min(θ at arm, 165°)                 // relative start; never jump on arming
θ_end  = 60°                                 // [tune] → 45° if the inner display stays lit to ~20°
t      = clamp((θ0 − θ) / (θ0 − θ_end), 0, 1)
depth  = t < 0.20 ? t : 0.20 + 0.80 · ((t − 0.20)/0.80)^1.6    // ease-in: fine control near the bottom
c      = max(0, depth − 0.20) / 0.80          // compression, used by sound/haptics/material thresholds
```

| θ (θ0 = 165) | t | Phase |
|---|---|---|
| 180–165 | 0 | Dead zone |
| 165–144 | 0–0.20 | Approach (no load) |
| 144–74 | 0.20–0.90 | Deformation and failure (most failures land around c 0.3–0.6, i.e. θ ≈ 120–95°) |
| 74–60 | 0.90–1.00 | Final compaction |
| < 60 | 1.0 | Sealed: no visible change, post-crush grains only |

### 6.3 State machine
```
Fallback  : hinge == nil                         → Pinch Press drives the same depth
Idle      → Armed      object placed && on inner display && θ ≥ 100   (θ0 captured)
Armed     → Pressing   θ ≤ θ0 − 4
Pressing  → Armed*     θ ≥ θ0 + 4 && depth < 0.05     (*damage persists)
Pressing  → Sealed     depth ≥ 0.98 for 150 ms  ||  status == .closed
                       ||  app moved to outer display with depth ≥ 0.6 (auto-complete off-screen)
Pressing  → Paused     scene inactive || tent pose || Split View width < 600 pt
Sealed    → Revealing  first inner-display layout && θ ≥ 120 (event-gated by a model flag, not angle)
Revealing → Idle       after the animation or a tap
Moved to outer display with depth < 0.6 → "Press interrupted at 40%" card; resume on reopen
```
All state lives in one `@Observable` model **above** any size-class-dependent view branch, because the display switch rebuilds views.

### 6.4 Poses and edge cases (v1.0 scope)
- **Tabletop (hero):** lower half flat, push the top half down. Coach it with "Set it on a table. Push the top down slowly."
- **Book pose (vertical fold):** v1.0 rotates the press so the ram comes from one side. **Vice mode** with themed results is v1.1.
- **Tent:** pause, "Lay it flat to press."
- **Rotation mid-press:** lock the mode, relayout only.
- **Interruption:** freeze and persist.
- **Split View:** scaled press.
- **Reduce Motion:** shorter reveal, fragments fade rather than fly.

---

## 7. Haptics spec
*(Full numbers in `research/01-haptics.md` §7. These are the binding rules.)*

- **One `CHHapticEngine`** created at launch with `audioSession: .sharedInstance()`. Handlers are set before `start()`. The engine runs only while the Press scene is visible. `resetHandler` recreates all players.
- **Three layers:**
  1. **Strain bed:** a looping 30 s continuous event authored at I 1.0 / S 0.5 on an advanced player. Steered with 30 ms parameter *curves* at ≤ 60 Hz, deadband 0.02, never raw steps (no zipper buzz). **Max 0.7 before failure.**
  2. **Grains:** one transient per Δθ_g of closing (0.5–3.5° per material), scheduled ahead with ±30% jitter, capped at 60/s with a 12 ms minimum gap. **Stopping the grains = rigidity**, the plateau before failure.
  3. **Events** (code-built patterns with ≥ 3 variants each): contact kiss, cracks, failure, ka-chunk, reveal, collect.
- **Full intensity (1.0)** only at failure and the ka-chunk.
- **Holding still:** the bed fades to 0 over 300 ms, with an occasional settling creak every 0.8–2.0 s.
- **Opening:** the bed reaches 0 within 80 ms. Unloading must feel like relief.
- **Variation on every event:** ±10% intensity, ±15% timing, ±0.05 sharpness. The same pattern never plays twice in a row.
- **Stiffness ordering:** glass > can > crayon > egg > duck > cake > jelly. Encode it through bed sharpness, grain spacing and the grain-stop plateau.
- **Device gain table g(θ)** from the Week 0 calibration (the Taptic Engine position and strength on the Duo are unknown).
- **User setting:** Soft = ×0.6, Full = ×1.0. Fatigue guard: −10% bed after 60 s of bed time within 5 minutes.
- **Thermal `.serious`:** halve the grain rate and cap the bed at 0.5.

---

## 8. Sound spec
*(Full numbers in `research/02-sound.md` §7.)*

- **Session:** `.ambient` (respects the silent switch and mixes with the user's music). Haptics carry the experience when muted. A one-time tip: "Squish sounds best with sound on 🔊".
- **Buffers:** request a 5 ms IO buffer at 48 kHz and read back what you actually got.
- **Graph:**
  - PressBed `AVAudioSourceNode`: hiss, motor, procedural creak, gauge ticks
  - MaterialBed `AVAudioSourceNode`: strain loops, granular crunch
  - 10-voice one-shot pool
  - Route EQ (speaker vs headphones), low-band harmonic exciter, peak limiter
- **Never use `AVAudioUnitTimePitch`** (~90 ms latency). Pitch with our own resampling read pointer.
- **Layered failure events:** transient + body + debris, each from a round-robin pool. 4×4×3 gives 48 combinations per material.
- **Brand sounds are fixed and synthesised in code**, all in one **C major pentatonic** system:
  - gauge ticks (one per 5° under load, climbing the scale)
  - ka-chunk
  - reveal sting (3 notes)
  - collection chime (2 notes)
- **No music in the press scene.** ASMR evidence says music suppresses the response. A collection-screen loop is a v1.1 A/B test.
- **Spectral rules:**
  - Sparkle at 6–12 kHz on transients.
  - Notch sustained tonal energy at 2.5–4.5 kHz (no squeals, scrapes or glass screech).
  - Body at 150–600 Hz, plus harmonics so the phone speaker implies bass.
  - Real sub thump on headphones only.
- **12+ tone:** the duck sounds comic, never pained. No wet, mouth-like or meaty squelch.
- **Loudness:** −16 LUFS integrated ±2, −1 dBTP. Climaxes about 6 LU above the strain bed.
- **Sourcing (≈ $160–250):**

  | Pack | Price |
  |---|---|
  | Ultrasquish | $40 |
  | Veg/food crunch from the foley "gore" bundle, gore removed | $27–53 |
  | Glass Smash HD, or a budget alternative | $75 / $5 |
  | Ongelegen Aluminium Cans | free |
  | Metal Groans | ~$30 |
  | Squeaky Toys | $5–10 |
  | Household Source | ~$23 |
  | Sonniss GDC bundles + Freesound CC0 | free |

  Raw libraries stay out of git (`audio-source/` is ignored). Licences go in `licenses/`.
- **Because the AI developer can't listen:**
  - Scripted loudness, onset and 2.5–4.5 kHz harshness checks.
  - Spectrogram PNGs for every asset.
  - The **15-minute founder listening protocol** after each build. Results go in `audio-feedback.md`.

---

## 9. Visual & rendering spec
*(Full detail in `research/03-visuals-physics.md`.)*

- **Stack:** SwiftUI shell → `RealityView`; `CustomMaterial` (Metal geometry modifier + surface shader) driven by the press scalar and spring parameters; `LowLevelMesh` + compute for ooze and spread; `PostProcessEffect` ¼-resolution bloom. `MeshDeformerComponent` (iOS 27) is the v1.x upgrade path.
- **Lighting:** CC0 studio HDRI as IBL, one soft key light from the top-left, a rim light, and a **blob contact shadow** that darkens and spreads with pressure. It's the cheapest and strongest depth cue.
- **Deformation backbone** (analytic, deterministic f(press)):
  - contact flatten
  - volume-preserving squash: XZ scale ×1/√s, plus a mid-height bulge
  - buckling: sinusoidal folds appearing top-down
  - jiggle springs (ζ ≈ 0.4)
  - plastic ratchet
  - spread discs with seeded noisy rims
  - **brittle objects:** pre-sliced pieces with seeded impulses at failure
  - **no runtime soft-body physics** in v1
- **Juice rules:**
  - **No full-screen shake.** Haptics are the screenshake. Object-local micro-shake only, 1–3 px, ~60 ms half-life.
  - **Hit-stop:** 40 ms at contact, 80–120 ms at failure, applied to the object and particles only. **The ram stays tied to the hand.**
  - **Slow motion:** secondary systems only (debris, splashes) at 0.3× for 250 ms. The offline share clip can slow everything.
  - **Persistent mess:** crumbs, stains and scuff rings stay on the anvil and appear on the result card.
  - **Failure flash:** the top screen flashes white for 2–3 frames, staying under 3 Hz (photosensitivity).
- **Layout:**
  - The bottom half is the stage and anvil, with a mild off-axis projection so the chamber looks sunk into the glass (a 60/40 blend toward a normal projection).
  - The top half is the ram housing, a tonnage gauge, warning lamps and the "contact print" view.
  - Nothing interactive sits in the 40 pt crease.
- **Performance budget** (120 Hz = 8.33 ms):

  | Item | Budget |
  |---|---|
  | GPU | ≤ 5.5 ms |
  | CPU main thread | ≤ 2.5 ms |
  | Hero mesh | 20–60k verts |
  | Fragments | ≤ 300 |
  | Particles | ≤ 3k |
  | Draw calls | ≤ 120 |
  | Shadowed lights | 1 |
  | Memory | ≤ 350 MB |
  | App size | ≤ 80 MB |

  At thermal `.serious`, drop to 60 Hz, hard shadows and half the particles. Set `CADisableMinimumFrameDurationOnPhone`.
- **Asset strategy:**
  - Procedural Swift generators: lathe (can, bottle, egg, crayon, jelly mould), extrusion (cake), SDF + marching cubes (gummy, duck), grid (bubble wrap).
  - Fictional labels drawn with CoreGraphics.
  - Buy a model only if a procedural one fails the screenshot review loop (Kenney Food Kit is CC0).

---

## 10. Sharing
- **One-tap share clip:** 9:16, 1080×1920, 6–10 s with sound, under 8 MB. It's **re-rendered offline** from the stored hinge timeline plus seed (a few KB per result), not screen-recorded.
  - 0–1 s: title card "RUBBER DUCK vs SQUISH"
  - the press, sped up where nothing happens
  - the failure at 0.3×
  - an end card with the specimen and a small "Squish · iPhone Duo" watermark
  - encoded with `AVAssetWriter`; audio re-rendered through AVAudioEngine offline mode
- Also: a before/after PNG.
- System share sheet only. No SDKs, accounts or tracking, and never "share to unlock".
- The clips double as App Store preview footage and social teasers.
- **v1.1:** opt-in front-camera "real hands" picture-in-picture.

---

## 11. Progression & retention (ethical by construction)
- **Starting state:** 6 objects open, 3 unlock through natural play, plus 1 secret. A typical player unlocks everything in their first or second session. That's endowed progress, not grind.
- **Traits per press:** Perfect Squish (smooth close, no reversals, angular speed under a threshold), Golden (1/50), Surprise.
- **~10 Game Center achievements, all earned naturally:**
  - First Squish
  - Perfectionist (Perfect Squish on 5 objects)
  - Midas (find a Golden)
  - What's Inside?
  - Patience (a press over 30 s)
  - Collector (all 10)
  - The Secret
  - Pop Star (500 bubbles)
  - Steady Hands
  - Pumped (multi-stage press)
- **Review prompt:** `SKStoreReviewController` once only, after a reveal, after about 10 presses.
- **Retention comes from free object drops** every 3–4 weeks, each announced as an App Store **In-App Event**.
- **Never:** currency, energy, streaks, leaderboards, notifications or tip jars.

---

## 12. Market & positioning

| Item | Decision |
|---|---|
| **Brand** | **Squish** |
| App Store name | **"Squish: Fold-to-Crush Press"** (27 characters) |
| Subtitle | **"The £2,000 hydraulic press"** (localised) |
| Backup names | Hingepress, Ka-chunk |
| Avoid | "Pocket Press", Hydraulic Press Channel references, Squishmallows-like mascots |
| **Price** | **£2.99 / $2.99**, no IAP, no ads, Family Sharing on, Small Business Program (≈ £2.12 net per UK sale). No launch discount |
| First sale | £1.99 at the January drop |
| Price rise | £3.99–4.99 at 30+ objects |
| **Age rating** | Target **9+** in Apple's tiers (cartoon object crushing), with a teen/adult *tone* in the copy |
| **Competition** | **No press or crush app on iPhone Duo** (all ~900 FoldHunt entries read). Nearest are the close-to-print ink toys (Inkblotter, Paint & Fold, Foldink). Regular iOS crush games are ad farms last updated 2018–2020, so premium and ad-free is the gap. Expect a rival within weeks; the moat is feel, sound and update cadence |
| **Toastie** | $2.99, #10 US Top Paid Casual, almost no press, no preview video. We beat it with a preview video, captioned screenshots, a press push, and a collection that brings people back |
| **Install base** | ~5–6M Duos in 2026, with US backorders into late January. Many will be Christmas gifts, so a late-November launch catches the holiday and January waves |

---

## 13. Build plan (4 weeks to ~20–24 Nov)

| Week | Dates | Deliverables |
|---|---|---|
| **0: Hardware truth** | 23–26 Oct | **"Hinge Lab" debug app on the founder's Duo:** logs raw hinge samples to CSV (rate, latency, quantisation); finds the **angle where the inner display turns off** (closing and opening); checks whether updates continue on the outer display; runs the haptic ladder calibration → g(θ); speaker position vs fold; confirms `.ambient` audio survives the display switch. **Founder:** reserve the name in App Store Connect; post a teaser clip (Duo-Man got 2.1M views from a simulator demo) |
| **1: Core feel** | 27 Oct–2 Nov | Xcode project; HingePressDriver + state machine + unit tests on recorded traces; Pinch Press fallback; RealityKit scene (plates, ram, lighting, contact shadow); analytic deformer; audio engine + haptics engine; **Bubble Wrap + Rubber Duck end-to-end**; in-app **Tuning Lab** (live sliders for every constant in this doc, exportable JSON) |
| **2: Materials** | 3–9 Nov | Pre-fracture system; spread meshes; Egg, Crayon, Glass Bottle, Jelly, Cake; buy and process sound libraries; **submit for App Store pre-order + featuring nomination (~7 Nov)**; TestFlight to early Duo owners |
| **3: Product** | 10–16 Nov | Soda Can, Gummy Bear, The Unsquishable; cover display (sealed card, trophy shelf); Shelf + Card detail + Settings; unlocks, traits, Game Center; accessibility; first founder listening sessions |
| **4: Ship** | 17–23 Nov | Offline share-clip renderer; App Store screenshots (Duo inner 2007×2853, outer 1398×2034) + 15–30 s preview; loudness pass; 20-press repetition test per object; thermal, interruption and silent-mode tests; app icon; submit; release Tue/Wed before Thanksgiving |
| Dec | — | Holiday Object Drop (In-App Event) before ~10 Dec |

---

## 14. Top risks

| # | Risk | Mitigation |
|---|---|---|
| 1 | Display-off angle unknown (20–55° in sim) | Visible action ends at 60° by design; Week 0 measurement; θ_end is config |
| 2 | Hinge rate/latency on device unknown (~30 Hz in sim, may drop to ~10 Hz) | One-Euro + spring + hold; replay harness at 30/15/10 Hz; low-rate mode |
| 3 | The AI developer can't see or hear the result | Founder playtests each build (listening protocol, 5-minute feel checklist); scripted audio checks; screenshot review loop; Tuning Lab on device |
| 4 | Someone ships a press toy first | Public teaser now; pre-order page by ~7 Nov; out-craft them on feel |
| 5 | App Review 2.4.2 (device damage) | Copy is always virtual-only; no slam rewards; "slowly" coaching |
| 6 | RealityKit unknowns (120 Hz, offscreen export) | Prove in Week 1; raw Metal export renderer as Plan B |
| 7 | 10 objects feel thin | Depth per object, variants, surprises, secret, public drop calendar |
| 8 | Haptic engine or audio glitch on the display switch | Week 0 test; `resetHandler` rebuilds; state above view branches |

---

## 15. Open decisions for the founder
1. **Age rating:** target **9+** (wider reach, keeps the teen/adult tone in the copy), or deliberately **13+** for edgier humour?
2. **Platform:** **universal iPhone** with Pinch Press (recommended), or Duo-only?
3. **Name:** go with **Squish / "Squish: Fold-to-Crush Press"** and reserve it in App Store Connect now?
4. **Spend:** approve ~$160–250 of sound libraries? Optionally £150–300 for one freelance sound designer to review a TestFlight build in Week 3.
5. **Teaser:** post a teaser clip on X / r/iPhoneDuo this week to claim the idea (you post it; I prepare the clip and copy)?
