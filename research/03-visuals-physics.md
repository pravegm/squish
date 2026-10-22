# Squish: Visuals, Game Feel & Deformation Tech (Research 03)

*Prepared 22 Oct 2026, the day before iPhone Duo launches. Scope: visual design language, juice, art direction, deformation and rendering tech, fold-as-camera, and results/collection presentation.*

**Founder constraints applied throughout:** there are no human artists. An AI developer writing code is the only designer and developer, with a small budget for asset packs. The target is to ship in about 4 weeks with about 10 launch objects, for an audience of 12+ with no gore. Each technique below is rated **"code-only realistic"** or not.

**Research caveat:** the web-search budget ran out near the end of research. Three items marked *(unverified)* below still need a hands-on check in Xcode 27.1: SSS material support on iOS, `RealityRenderer` availability on iOS, and RealityKit's 120 Hz behaviour.

---

## Key takeaways

1. **The bottom half is your hero screen, not the top.** In table ("laptop") posture, simple viewing geometry shows the top half turns away from the user below about 45–50°. The bottom half stays mostly visible down to about 20–25°. Put the object on the **bottom half (the anvil)** and use the **top half as the ram/gauge**. The real top half physically *is* the ram.
2. **Remap the hinge angle; don't map it linearly.** A per-object curve should place contact, strain and failure between about **120° and 50°**, where both screens are readable. Below about 35° comes the "seal": audio, haptics and the cover screen do the work, and reopening shows the result.
3. **The hinge is a coarse, irregular, unspecified sensor.** Apple says rate and granularity are "system policy" and not to depend on them ([Apple – UIHinge.angle](https://developer.apple.com/documentation/uikit/uihinge/angle.md)). The pipeline is: timestamped samples → **1€ filter** → per-object curve → **critically damped spring** at render rate → **ratchet** for plastic deformation. Discrete events fire on thresholds with hysteresis, and **failure bursts run on their own clock** once triggered.
4. **Art direction: stylized "vinyl-toy / candy-clay" 3D.** This is the only option that is satisfying, consistent and **producible by code alone**. Nearly every launch object is a surface of revolution, extrusion or SDF blob that can be generated procedurally in Swift. Photoreal needs artists and scans. 2D loses the volumetric "it's really in there" feeling the fold creates.
5. **Deformation: analytic, deterministic vertex deformation driven by one `press` scalar.** This is the backbone: volume-preserving squash, bulge, contact flattening, buckling folds and jiggle springs. Add **pre-fractured pieces** for brittle objects and **planar "spread" meshes** for ooze. Avoid runtime FEM/PBD soft bodies for v0.
6. **Stack: Swift + RealityKit (iOS 27.1) + Metal shaders.** Use `CustomMaterial` geometry modifiers (iOS 15+, proven) for deformation, `ShaderGraphMaterial` (iOS 18+) or `CustomMaterial` surface shaders for looks, and `PostProcessEffect` (iOS 26+) for bloom. The new iOS 27 `MeshDeformerComponent`/`MeshDeformer` GPU pipeline is the upgrade path. Avoid SceneKit, which has been soft-deprecated since WWDC25. Unity and Godot are poor fits for an AI coder that works in text and needs a native hinge API.
7. **Juice rules for a handheld that *is* the press:** **no full-screen shake.** Haptics are the screenshake. Use object-local micro-shake, a 40–100 ms hit-stop at contact and failure, and **slow motion only on secondary motion** (debris and particles), never on the ram, which the user's hand owns.
8. **Oddly-satisfying formula: predictable process + surprising material outcome.** This matches Cheung et al.'s low-uncertainty/high-surprise pleasure result. Use a slow, clear tension → release arc ([Vice interview](https://broadly.vice.com/en/article/889wez/the-hydraulic-press-channel-is-the-internet-sensation-of-our-time)), symmetry, a clean backdrop, and a tidy "complete" end state. Every object needs a **distinct material signature** and ideally a **hidden surprise core**.
9. **Share video should be re-rendered offline, not screen-recorded.** The crush is a deterministic function of the logged hinge timeline, so you can replay it into a 9:16 offscreen render with a cinematic camera, then encode with `AVAssetWriter`. That avoids the crease, ReplayKit prompts and bad framing.
10. **Results screen: a "pressed specimen" herbarium card in a sticker album.** Show an orthographic top-down render of the flattened object on paper with a monospaced specimen label (tonnage, angle at failure, fragments) and a red "PRESSED" stamp. The UI chrome is "tactile industrial-lite": hydraulic yellow, graphite, SF Pro Rounded and SF Mono, and SF Symbols. All of it is buildable without an illustrator.

---

## 1. Visual design language for "oddly satisfying"

### What the evidence actually says
Direct peer-reviewed research on #oddlysatisfying is thin. Live Science noted there were no direct studies, and most popular claims about "dopamine" are unsourced ([Live Science](https://www.livescience.com/62091-oddlysatisfying-videos-satisfying.html)). The usable threads are:

- **Visual tactility.** Nansen & Balanzategui treat oddly-satisfying videos as a sensory genre whose pleasure comes from *seeing* material qualities: texture, compliance, resistance ([Convergence, 2022](https://journals.sagepub.com/doi/abs/10.1177/13548565221105196)). The appeal is the **material behaving truthfully**.
- **Hyper-reality.** Evan Malone's account, cited on Wikipedia, says these videos make mundane processes look cinematic and "hyper-real" ([Wikipedia](https://en.wikipedia.org/wiki/Oddly_satisfying_videos)). The same article lists hydraulic presses, soap cutting, slime and shredders as canonical subjects, alongside symmetry, pattern and repetition.
- **Tension and release.** The Hydraulic Press Channel's creators compare their videos to pimple-popping: "anticipation, the tension, and... the release" ([Vice](https://broadly.vice.com/en/article/889wez/the-hydraulic-press-channel-is-the-internet-sensation-of-our-time); [Wikipedia](https://en.wikipedia.org/wiki/Hydraulic_Press_Channel)).
- **Predictability × surprise.** Cheung et al. (Current Biology 2019) found pleasure peaks when an event is **highly surprising in a low-uncertainty context**, or conforms in a high-uncertainty one ([Cambridge summary](https://cms.mus.cam.ac.uk/publications/cheung-uncertainty-surprise/); [MPI CBS](https://www.cbs.mpg.de/music-pleasure-in-pop-songs)). The study is about music, but it maps cleanly onto the press: the descent is utterly predictable, and *what the object does* should surprise.
- **Completion / "just right".** Interrupted-task discomfort research gets cited loosely ([Live Science](https://www.livescience.com/62091-oddlysatisfying-videos-satisfying.html)). Treat it as a design heuristic, not a law: **end in a tidy, complete state**.

### Visual rules for Squish
1. **One subject, dead centre, symmetric staging.** Centre the object on the anvil with a symmetric press frame and a radially spreading result. Keep asymmetry for the *failure* moment, where cracks or a burst on one side are the surprise.
2. **Material truth over spectacle.** Each object gets a signature only it has: wax crayon **shears and curls**, an egg **cracks then yolk spreads**, a can **concertinas**, jelly **wobbles and spreads**, glass **shatters into sharp-edged shards**, bubble wrap **pops in sequence**. If two objects fail the same way, cut one.
3. **Slow, legible, continuous change.** The user controls speed, so design every intermediate pose to look good when *held*. The Duo's hinge holds at nearly any angle ([Gizmodo](https://gizmodo.com/iphone-duo-review-2000827502)), so mid-press stills will be stared at. Keep idle life going: creaks, drips, a settling crumb.
4. **Surprise core.** Seed a hidden reveal inside predictable objects: rainbow layers in the gummy, a jam centre in the cake, confetti inside a "party egg", a fizz geyser from the can. Vary it with a deterministic seed per press, so each press is a small lottery.
5. **Hyper-real close-up, clean world.** Use a seamless studio backdrop, crisp specular highlights, shallow-DOF feel, and no clutter. Mess should be **candy-coloured and tidy**, never bodily. That suits 12+ and no gore.
6. **Sound and touch in lock-step.** The ASMR overlap is real in viewers' accounts ([Wikipedia](https://en.wikipedia.org/wiki/Oddly_satisfying_videos)). Every visual event gets a close-mic sound and a Core Haptics event in the same frame.
7. **A complete end state.** The flattened result is a clean silhouette on paper with a label: a finished artefact, not a mess.
8. **Avoid aversive patterns.** Don't use clustered small holes (a trypophobia trigger) on sponge or bubble textures. Don't put faces on anything that gets destroyed. A rubber duck that goes cartoon-flat and squeaks back is fine; a crying gummy is not.

---

## 2. Game feel / juice

### Sources and what to take from each
- **Steve Swink, *Game Feel* (2008):** feel lives in the real-time input → response loop, in simulated space, with polish emphasising the interactions ([summary via Game Developer](https://www.gamedeveloper.com/business/has-your-game-got-juice-more-)). **For Squish, the hinge-to-deformation latency *is* the game feel.** Keep the deformation within a frame or two of the filtered input and never let smoothing make the object feel floaty.
- **Jonasson & Purho, "Juice it or lose it" (2012):** a bare Breakout gains life through easing, squash & stretch, colour, sound, screenshake and flashes ([GMTK summary](https://amara.org/v/C3BGA); [Juicy Break demo](https://crcdng.itch.io/juicy-break)). The counterpoint, Folmer Kelly's "Don't juice it or lose it", warns that over-juicing reduces clarity ([Game Developer](https://gamedeveloper.com/design/video-indies-resist-the-urge-to-juice-it-or-lose-it-)). **In Squish the deformation is the content, so effects must frame the material, not bury it.**
- **Jan Willem Nijman, "The Art of Screenshake" (2013):** gives concrete numbers. One pistol shot in Nuclear Throne kicks the camera 6 px, adds 4 to shake with fast decay, pushes the enemy 3 px/frame, shows a white flash frame, and freezes 10–20 ms on hit. Permanent debris sells that something happened ([Infovore notes](https://infovore.org/?p=5275)). Steal the **decal/permanence** idea: crumbs, stains and scuffs stay on the anvil and in the result.
- **Masahiro Sakurai, "Stop for Big Moments!":** hit-stop (a brief freeze on impact) is "vital for really letting the player feel the impact", plus a bigger "boss stop" on finales ([Automaton](https://automaton-media.com/en/news/20220824-15208/); [SSBWiki](https://www.ssbwiki.com/Sakurai)).
- **Disney's 12 principles** ([Wikipedia](https://en.wikipedia.org/wiki/Twelve_basic_principles_of_animation)). The most relevant here are squash & stretch with constant volume, anticipation, slow-in/slow-out, follow-through and overlapping action, secondary action, exaggeration and appeal.

### Handheld-specific rules
| Technique | Rule for Squish |
|---|---|
| **Screenshake** | **No full-viewport shake.** The screen is the press plate, and shaking it breaks the illusion that the object sits *on* the glass. It also causes discomfort at the steep angles users view from. Shake **the object and ram locally** (1–3 px, exponential decay of about 60 ms halflife). Let **Core Haptics** carry the "shake". |
| **Hit-stop** | 40 ms at first contact and 80–120 ms at failure. Only the *object's response and particles* freeze. The ram stays tied to the hinge, so the user's hand is never ignored, and it reads as "the material resisted". |
| **Slow motion** | You can't slow the user's hand. Run **secondary systems** (debris, splashes, confetti, crack growth) at 0.3× for about 250 ms after failure, then ease back to 1×. The primary deformation stays real-time. In the offline share video you *can* slow everything. |
| **Anticipation** | Before contact: a subtle "nervous" pre-compression quiver as the ram nears (0.5 % scale jitter), a hydraulic hiss, a gauge needle twitch, and the contact shadow darkening as the ram approaches. A darkening shadow is the strongest cheap depth cue. |
| **Squash & stretch** | Preserve volume: scaling Y by *s* scales XZ by 1/√s. Add a barrel bulge that peaks at mid-height. Overshoot on release (rubber) uses an underdamped spring with ζ ≈ 0.4. |
| **Particles** | Each object gets its own material vocabulary: wax flakes (flat, tumbling), crumbs (round, bouncy, settle and stay), droplets (stretch along velocity, leave stain decals), shards (sharp, specular, short-lived glints), confetti (only for the surprise core), dust puffs (soft, low-alpha, stays near the anvil). |
| **Decals and stains** | Contact prints, ooze discs, crack lines, scuff rings. They persist into the result card. |
| **Flash** | One-frame highlight on contact. On failure, flash the **top screen** white for 2–3 frames: it physically lights the bottom screen, a real-world bounce light only a foldable can do. |
| **Easing** | Ram travel uses the spring (no fixed easing). UI uses spring animations; the reveal uses ease-out-back for the specimen pop-in. |
| **Haptics** | Use Core Haptics. A high-sharpness transient is the crack/pop; a low-sharpness continuous rumble is the strain body. Ramp continuous intensity with *p*. Play transients in a separate player so an active intensity curve doesn't scale them down ([Kodeco](https://www.kodeco.com/10608020-getting-started-with-core-haptics); [react-native-tickle note](https://docsearch.algolia.com/mcp/docs/repo/renegades-studio/react-native-tickle)). When closed, use Toastie-style gentle pulses ([TechRadar via search](https://www.techradar.com/phones/iphone/apple-iphone-duo-review)). |

---

## 3. Art direction options

| | (a) Stylized 3D toy/clay/candy | (b) Photoreal 3D | (c) 2D illustrated |
|---|---|---|---|
| **Satisfaction** | High: volume, specular, jiggle, real light from the fold. Exaggeration reads as intentional. | Highest ceiling, but the uncanny valley appears quickly when deformation isn't physically perfect, and crushed photoreal food can read as gross. | Medium: squash/stretch works, but there's no real volume or parallax across the fold. |
| **Code-only feasibility** | **Yes.** Lathes, extrusions, SDF→marching-cubes blobs, procedural noise materials, CoreGraphics labels, CC0 HDRIs. | **No.** Needs scanned assets, texture artists and sim baking. | Partly. An AI can't reliably draw consistent illustrations; vector-procedural 2D is possible but looks generic. |
| **Production cost** | Low–medium | High | Low (procedural) or high (illustrated) |
| **Consistency across 10 objects** | Easy: one shading model and palette, all generated by the same code. | Hard: mixed asset sources clash. | Hard without an illustrator. |
| **App Store screenshots** | Strong: bright, chunky, "toy" read at thumbnail size. Comparable to the clean look of Smash Hit and Townscaper. | Strong if done well (not feasible here). | OK |

**Recommendation: (a) stylized "vinyl-toy / candy-clay" 3D.** It is the only option that hits satisfaction, consistency *and* the no-artist constraint. Smash Hit is the instructive precedent: its clean, single-material art style is what made procedural destruction tractable, because "everything that breaks is made out of the same, solid glass material" ([Gustafsson, Game Developer](https://www.gamedeveloper.com/programming/cracking-destruction)). Pick a style that makes your code look intentional.

### Palette
- **World:** warm off-white seamless studio backdrop (#F3EEE6), graphite press frame (#2B2D31), hydraulic safety yellow ram/accents (#FFB81C), and a single hazard-stripe band. A mid-key, bright world also suits the Duo's matte nano-texture inner display ([Gizmodo](https://gizmodo.com/iphone-duo-review-2000827502); [Man of Many](https://manofmany.com/tech/smartphones/apple-iphone-duo-review)). Very dark scenes look milky on matte glass in daylight.
- **Objects:** saturated candy hues (gummy raspberry #E8336F, lime jelly #8BD448, duck #FFD23F, crayon cobalt #2F5BEA). Ooze and filling are *more* saturated than the shell, so the surprise core pops.
- **Accents:** stamp red (#D7263D) for the "PRESSED" stamp and failure flash tint.

### Lighting
Use a studio HDRI as IBL from Poly Haven (CC0). Add one directional key from top-left with soft shadows. WWDC26 RealityKit adds soft shadows via `lightSize` and `.medium`/`.high` quality, at a GPU cost ([WWDC26 – Explore advances in RealityKit](https://developer.apple.com/videos/play/wwdc2026/279/)). Add a cool rim from behind and a **blob contact-shadow decal** under the object that darkens and spreads with *p*. That decal is cheap and the single most important grounding cue.

### Materials (all procedural or parameterised)
| Object | Material approach |
|---|---|
| Jelly / gummy | Fake SSS: wrap diffuse plus a transmission tint, with brightness rising as local thickness falls (thickness comes from the deformation, so squashed areas glow). Clearcoat, low roughness, sugar-dust noise for gummies. Built-in SSS was mentioned at WWDC26 for characters *(unverified on iOS)*, so assume the fake. |
| Soda can | Metallic 1.0, roughness 0.25 with a brushed-noise roughness modulation, and a CoreGraphics-generated **fictional** brand label. No real trademarks. Bare aluminium shows at the folds. |
| Glass bottle | Transparent PBR with strong IBL reflection and fresnel rim. Fake refraction through an environment lookup. Shards get edge highlights. |
| Crayon | Wax: roughness 0.55 with a slight sheen, a paper wrapper with a generated label, and bright clean "fresh wax" colour on cut faces. |
| Egg | Matte shell (roughness 0.8) with micro-noise. Yolk is glossy and saturated with fake SSS. Albumen is a translucent, low-alpha spread disc. |
| Cake slice | Sponge uses procedural *non-clustered* pore noise. Glossy cream, saturated jam. |
| Rubber duck | Glossy vinyl (roughness 0.3) and a slight clearcoat. The only object with a face, because it survives. |
| Bubble wrap | Thin clear plastic dome grid with strong specular and normal "crinkle" after popping. |

---

## 4. Deformation tech on iOS

### Technique comparison
| Technique | Look | Determinism / scrubbable by hinge | Perf at 120 Hz | Code-only realistic? |
|---|---|---|---|---|
| **Analytic vertex deformation** from one `press` scalar (+ a few spring-driven secondary params) | Very good for soft, elastic and plastic objects; fully art-directable | Perfect: *f(p)* | Excellent (vertex shader / compute) | **Yes, the backbone** |
| **Pre-fractured pieces + scripted release** (Voronoi or plane slicing at build time; seeded impulses at failure) | Very good for brittle objects | Deterministic with a seed | Good up to ~300 pieces | **Yes.** Plane-slicing convex hulls is pure code, as in Smash Hit ([Gustafsson](https://www.gamedeveloper.com/programming/cracking-destruction)). Blender's Cell Fracture via headless Python is also an option. |
| **Blend shapes / morph targets** baked from offline sims (Blender cloth/softbody via headless Python → USDZ) | Excellent for one-off hero deformations | Perfect: weights = curve(*p*) | Good | **Partly.** The AI can script Blender, but tuning sims blind is slow. Use it for 1–2 hero objects at most. RealityKit supports `BlendShapeWeightsComponent` ([Apple](https://developer.apple.com/documentation/realitykit/blendshapeweightscomponent.md)). Blender's USD exporter writes evaluated meshes, but watch the USDZ off-main-thread bug ([Blender #114415](https://projects.blender.org/blender/blender/issues/114415)). |
| **Vertex Animation Textures** (Houdini Labs VAT 3.0) | Excellent: rigid-body destruction, fluids | Perfect: frame = *p*·N | Good on GPU; uncompressed textures cost memory ([SideFX](https://www.sidefx.com/docs/houdini/nodes/out/labs--vertex_animation_textures-3.0.html)) | **No for v0.** Needs Houdini (paid Indie licence), artist-style iteration, and a custom RealityKit shader to decode, with no RealityKit importer found. Possible later via purchased VAT packs. |
| **Runtime soft body (XPBD / FEM, tetrahedral embedding)** | Physically rich wobble | Non-deterministic-ish; unstable at extreme compression; hard to art-direct | Feasible on A20 Pro with a low-res tet cage ([Ten Minute Physics 10 & 12](https://matthias-research.github.io/pages/tenMinutePhysics/)) | **Not for v0.** Writing it is fine; *tuning it to look good blind in 4 weeks* is not. |
| **Runtime Voronoi fracture** | Novel every time | Seeded | Costly at runtime | Unnecessary. Pre-fracture at build or load time. |

### Engine and framework comparison
| Option | Status / fit |
|---|---|
| **RealityKit (iOS 27.1)** | **Recommended.** Native, all Swift (text-only, AI-friendly), PBR + IBL + shadows. **`CustomMaterial` geometry modifiers** run inside RealityKit's vertex shader and suit deformation; surface shaders handle looks (iOS 15+) ([Apple](https://developer.apple.com/documentation/realitykit/custommaterial.md); [WWDC21](https://developer.apple.com/videos/play/wwdc2021/10075/)). `ShaderGraphMaterial` on iOS 18+ ([Apple](https://developer.apple.com/documentation/realitykit/shadergraphmaterial.md)). **`LowLevelMesh`** updates vertex buffers with Metal compute ([Apple](https://developer.apple.com/documentation/realitykit/generating-interactive-geometry-with-realitykit.md)). **New in iOS 27:** `MeshDeformerComponent` with a `MeshDeformationStack` of `MeshDeformer`s, including custom GPU deformers that encode into an `MTLComputeCommandEncoder` and built-in skinning, blend-shape and subdivision deformers ([Apple – Mesh deformation](https://developer.apple.com/documentation/realitykit/scene-content-mesh-deformation.md); [MeshDeformer](https://developer.apple.com/documentation/realitykit/meshdeformer.md)). **`PostProcessEffect`** (iOS 26+) for bloom and vignette ([Apple](https://developer.apple.com/documentation/realitykit/postprocesseffect.md)). WWDC26 also adds cloth sim, soft shadows, LOD and thermal guidance ([WWDC26-279](https://developer.apple.com/videos/play/wwdc2026/279/)). |
| **SceneKit** | Soft-deprecated at WWDC25: maintenance mode, critical fixes only. Apple recommends RealityKit for new projects ([WWDC25-288](https://developer.apple.com/videos/play/wwdc2025/288/); [Apple migration guide](https://developer.apple.com/documentation/realitykit/bringing-your-scenekit-projects-to-realitykit.md)). Don't start here. |
| **SpriteKit** | Fine for 2D overlays, but no 3D deformation. Unneeded; SwiftUI covers UI. |
| **Raw Metal** | Maximum control and guaranteed 120 Hz, but you rebuild PBR, IBL, shadows and particles yourself. **Fallback** if RealityKit blocks something (e.g., dual-viewport rendering). |
| **Unity / Godot** | Hinge API needs a native bridge (`onHingeChange`/`UIHingeInteraction` are iOS 27.1 only). Scene and prefab workflows are editor-centric and awkward for a text-only AI developer. Adds app size. No upside for 10 procedural objects. |

**Recommended stack:** SwiftUI shell + `RealityView` + `CustomMaterial` (Metal geometry modifier + surface shader) as **v0**. Use the press scalar and spring params passed through the material's custom parameter vector or textures. Use `LowLevelMesh` + compute for spread/ooze meshes. Generate pre-fracture pieces procedurally in Swift at load. Use `PostProcessEffect` for a cheap half-res bloom. Treat `MeshDeformerComponent` as a v1 upgrade once proven on device: it is new and thinly documented. Core Haptics and AVAudioEngine handle haptics and audio.

**Gotchas:**
- Vertex-shader deformation doesn't update CPU bounds. Inflate entity bounds so squashed and spread meshes aren't culled.
- Recompute normals analytically (from the deformation Jacobian) or by finite differences in the shader.
- 120 Hz on iPhone requires `CADisableMinimumFrameDurationOnPhone`. Verify that RealityKit actually presents at 120 Hz on Duo hardware *(unverified)*.

### Analytic deformation recipe (the backbone)
Each object is authored in code as a mesh plus a "deformation profile". This is the code-only replacement for an artist.

1. **Contact flatten:** `y' = min(y, ramY(p))`, with excess height redistributed radially: `r' = r · sqrt(h0 / h(p))` near the contact band.
2. **Volume-preserving squash:** `s = h(p)/h0`; XZ scale `1/sqrt(s)`. Add a bulge term `b · s(1–s) · sin(π·y/h)`.
3. **Wrinkles and buckling:** for the can, use progressive axial folds. Displacement is `A(p) · sin(k·y + φ(θ))` with alternating lobes, so folds appear top-down as *p* crosses thresholds. That is a diamond/concertina read with no simulation.
4. **Jiggle:** two or three underdamped springs on `squashAxis`, `wobbleXZ` and `topOffset`, excited by input velocity and events.
5. **Plasticity:** `pPlastic = max(pPlastic, p)` for crushables; elastic objects use `p` directly with a spring rebound.
6. **Spread mesh:** a disc `LowLevelMesh` with a noisy rim (seeded) whose radius follows `p` past failure. Used for jam, yolk, soda puddle and jelly overflow.

### Hinge input: smoothing and prediction
The hinge is a slow, quantised sensor:
- Apple says rate and granularity are system policy ([Apple](https://developer.apple.com/documentation/uikit/uihinge/angle.md)) and recommends measuring relative to the angle when the fold starts, keeping effects reversible, and offering a non-fold alternative ([BleepingSwift](https://bleepingswift.com/blog/onhingechange-hinge-angle-swiftui)).
- On Android foldables, some sensors report only 90° stops or go quiet near 30°, and one shipping app runs a per-vsync ease to hide 1° steps ([duo-open](https://github.com/marcoazeem/duo-open)).

Pipeline:
1. Store `(timestamp, θ)` samples from `onHingeChange`.
2. **1€ filter** (Casiez et al., CHI '12): a speed-adaptive low-pass. Start with `min_cutoff ≈ 1 Hz` and tune `beta` for lag ([1€ filter](https://cristal.univ-lille.fr/~casiez/1euro)).
3. Map to target progress: `pTarget = curve_obj(θ_rel)`.
4. At render rate, drive `p` with a **critically damped spring** (halflife 40–70 ms). Use its closed-form extrapolation to predict up to one sample interval ahead, capped at about 6°, decaying to zero if no sample arrives within 150 ms ([Holden, Spring-It-On](https://theorangeduck.com/page/spring-roll-call)).
5. **Events:** contact, crack *n* and failure fire when `p` crosses thresholds, with ±0.02 hysteresis so jitter can't re-trigger them. **Failure is a committed, time-driven 400–600 ms burst** that plays even if the user stops moving.
6. **Fallback control:** press-and-hold or drag on the cover or inner screen. It's needed for accessibility, the Simulator (DeviceHub only offers closed, ~128° and flat ([FoldSafe](https://github.com/foldstatedev/FoldSafe))) and App Review.

---

## 5. The fold as camera

### Facts
- The inner display is 7.6″ at 1.4:1 with 120 Hz ProMotion and a matte nano-texture finish. The crease is barely visible but shows at some angles. The hinge holds at nearly any angle ([Gizmodo](https://gizmodo.com/iphone-duo-review-2000827502); [Man of Many](https://manofmany.com/tech/smartphones/apple-iphone-duo-review)).
- The fold is a **division reserved region**: active only when folded, zero width when flat, queried with `reservedRegions(kind: .division)` ([Apple Tech Talk 111463](https://developer.apple.com/videos/play/tech-talks/111463/)). Apple warns that content spanning the fold reads like a photo across a book spine.
- For tabletop posture, Apple suggests the top region for at-a-distance content and the bottom for touch. Android's equivalent is `FoldingFeature` `HALF_OPENED` + `HORIZONTAL` ([Android docs](https://developer.android.com/guide/topics/large-screens/make-apps-fold-aware)).
- I found no developer write-up on rendering a 3D scene re-projected across a fold for the viewer's perspective. The closest are shader toys that note a 2D composite "breaks down at an angle" because it isn't re-rendered for the viewer's perspective ([explainx](https://explainx.ai/blog/iphone-duo-fold-animation-android-recreation-guide-2026)). This is open territory.

### Visibility geometry (why the bottom is the hero)
Set the phone like a laptop: bottom half flat, top half of length L (~8 cm) at hinge angle θ, eye in front at about 35° elevation.
- **θ = 90°:** the top faces the user and the bottom is seen obliquely. Both are fine.
- **θ = 60°:** the top screen's normal points about 30° downward, so the viewing angle is about 65°: grazing. The bottom screen is still almost fully visible beneath the overhang.
- **θ = 30°:** the top screen is effectively back-facing to the eye. About 80 % of the bottom screen is still visible, the part away from the hinge.

So: **anything that must be seen at the climax lives on the bottom half, toward the front edge.** The top half carries early-phase information.

### Recommended layout ("Press posture", primary)
- **Bottom half = Stage/anvil.** It renders the press chamber with an **off-axis (anamorphic) projection** for an assumed eye at about 30 cm and 35° elevation, refined lightly with the hinge angle. The chamber reads as a box sunk into the glass, with the object standing up in it. Place the object about 60 % of the way toward the front edge, never within 1 cm of the crease. The virtual ram enters from the top of this view.
- **Top half = Ram head and instruments.** It shows the hydraulic cylinder extending in sync, a tonnage gauge, warning lamps, and the **contact print**: the object's patch spreading "against glass" as seen from the ram's face. It's important at 150°–70° and expendable below 50°. It's also the light source for the failure flash.
- **Crease = the anvil's back edge.** Debris that flies backward "falls off" behind the anvil rather than smearing across the fold.
- **Physically aligned ram tilt (optional):** tilt the virtual ram face slightly toward the physical top half's angle so the crush feels caused by the real closing screen. Stop parallel-press purists from noticing by capping the tilt at about 10°.
- **Below ~35° (seal):** the inner screen becomes hard to see and then goes dark at `.closed`. Play the final crunch, haptic pulses and a **cover-display card** ("62 TONS · OPEN TO SEE") using the Duo's multi-scene support.
- **Book posture (vertical fold, held):** detect it from the CoreMotion gravity vector. Rotate the scene so the lower or less-tilted half is the anvil, or present it as a **"flower press"**: two plates closing like a book.
- **Implementation tiers:**
  - **v0:** one `RealityView` across the inner display with a single camera, recomputed per frame from the hinge angle. Frame the press in the bottom half and render instruments in the top half as SwiftUI/2D overlays, which avoids two-camera complexity.
  - **v1:** two viewports, one per half, each with its own off-axis frustum. Use either two scenes with deterministic hand-off of debris, or a Metal/`RealityRenderer` second pass *(iOS availability unverified)*.

---

## 6. Results, collection, sharing, UI

### Presenting the flattened object
- **"Pressed specimen" card:** an orthographic top-down render of the final mesh on herbarium-style paper. It has a drop shadow, a **specimen label** in SF Mono (name, `CRUSHED AT 62°`, `48 TONS`, `112 FRAGMENTS`, `SPREAD Ø 7.4 CM`, date, serial №) and a slightly rotated, seeded red **PRESSED** stamp. Render it to texture at reveal and save it as PNG.
- **Collection = sticker album / herbarium.** There are 10 slots with embossed silhouettes for locked objects. Each new specimen "peels" into place. Show a completion bar ("7/10 pressed") to feed the completion drive.
- **Reveal choreography on reopen:** the ram lifts with a short "stick" (cheese-pull strands for gooey objects), then a 100 ms hold. The specimen pops in with ease-out-back and the stamp thunks in with a haptic transient.

### Video export
Use **offline deterministic re-render rather than ReplayKit.** ReplayKit records the folded, crease-split UI. Developers report permission prompts, restart failures and nil buffers ([Apple forums](https://developer.apple.com/forums/thread/689132); [Apple forums](https://developer.apple.com/forums/thread/651099)), and an Apple forum reply notes there's no first-party RealityKit-to-movie API on iOS, with ReplayKit the only system video path ([Apple forums](https://developer.apple.com/forums/thread/831633)).

Instead, log the hinge timeline and event seeds, then replay into an offscreen render:
- 1080×1920 (9:16), 60 fps, side-on hero camera.
- Real slow-motion at failure, plus a punch-in.
- Small "Squish" watermark.
- Audio re-triggered through AVAudioEngine offline rendering.
- Encoded with `AVAssetWriter` (HEVC/H.264).

Also export a still card and a 3-second loop. ReplayKit is the emergency fallback only.

### UI chrome
**"Tactile industrial-lite"**:
- Chunky rounded buttons with a pressed-in state.
- One gauge dial, hazard stripes used sparingly, stencil-feel numerals.
- Mostly the warm studio white, so the object stays the hero.
- **Typography:** SF Pro Rounded Heavy for display, SF Mono for readouts and labels. Both are system fonts, so no licensing, and both are code-native.
- **Icons:** SF Symbols only.

### App icon concepts (generated by rendering the app's own 3D scene to PNG, then layered in Icon Composer)
1. A yellow ram flattening a raspberry gummy bear into a pancake, on graphite. This is the clearest read at small size.
2. A half-open Duo silhouette with a flattened rubber duck squeezing out. Communicates "made for the fold".
3. A single candy-coloured "splat" with a steel plate edge and a red PRESSED stamp corner.

Pick 1 for clarity and test 2 in App Store A/B (product page optimization).

---

## Squish visual & tech spec v0

**Art direction:** stylized vinyl-toy/candy-clay 3D. Warm off-white studio, graphite and hydraulic-yellow press, saturated candy objects. One shading model (PBR + fake SSS option + clearcoat) with procedural noise. CC0 studio HDRI, one soft key, a rim light, and a blob contact shadow. Fictional brand labels drawn in CoreGraphics. Faces only on the survivor (duck).

**Asset strategy (code-only):** generate procedurally in Swift:
- lathe: can, bottle, egg, crayon body, jelly mould
- extrusion: cake slice, chocolate bar, cookie
- SDF + marching cubes: gummy bear, duck, marshmallow
- grid: bubble wrap

Buy or borrow only where procedural falls short, such as the duck: Kenney Food Kit is CC0 with 200+ models ([itch.io](https://kenney-assets.itch.io/food-kit)). AI text-to-3D (Tripo, Meshy) needs a paid tier for commercial use and remeshing. Use it as a last resort and subdivide for deformation density ([HackerNoon comparison](https://hackernoon.com/how-i-stress-tested-3-ai-3d-generators-on-the-same-inputs-what-the-numbers-actually-show?source=rss); [Tripo review](https://pasqualepillitteri.it/en/news/7811/tripo-ai-review-3d-model-generator)).

**Deformation technique per launch object:**
| Object | Primary | Failure / signature | Surprise core |
|---|---|---|---|
| Gummy bear | Analytic squash + bulge + jiggle springs, plastic | Splits at the seam into 2–3 lobes, then spreads | Rainbow layers revealed in the cross-section |
| Jelly | Analytic + strong wobble springs | Bursts at the sides into a spread disc | Fruit pieces inside |
| Rubber duck | Analytic elastic, cartoon pancake | No break. Squeak, flatten, spring back with overshoot on reopen | Squeak pitch rises with *p* |
| Crayon | Analytic bend → pre-fractured snap | Snaps into 3–5 pieces, wax smears as flattened slivers | Hidden second colour core |
| Egg | Pre-fractured shell (plane-sliced) | Crack decals grow, shell shatters, yolk + albumen spread meshes | Double yolk (rare seed) |
| Soda can | Analytic progressive concertina buckling | Puncture → droplet spray + puddle disc | Fizz geyser |
| Glass bottle | Pre-fractured shards (seeded) | Glint, then sharp shatter with short-lived shards | Message-in-a-bottle confetti |
| Bubble wrap | Per-bubble dome deformation | Seeded pop sequence (each bubble's own threshold), crinkle normals | Rare "mega bubble" |
| Cake slice | Analytic sponge squash | Cream and jam spread meshes from the layers | Sprinkles burst |
| Cookie / chocolate bar | Pre-fractured | Crumbs that settle and persist as decals | Gooey centre spread |

**Effects per press phase** (θ ranges are defaults; the per-object curve shifts them):
| Phase | θ | Visual | Audio / haptic |
|---|---|---|---|
| 0 Place | 180° | Object drops with squash-and-stretch landing, idle breathing, press lamps on | Soft thud, light transient |
| 1 Approach | 180→120° | Ram descends, contact shadow darkens, dust motes, pre-contact quiver | Hydraulic hiss, needle tick haptics |
| 2 Contact | ~120–100° | 1-frame highlight, 40 ms hit-stop, contact print starts on top screen | Sharp transient |
| 3 Strain | 100→70° | Bulge, crack decals grow, local 1–2 px micro-shake, creak, small flakes | Rising continuous rumble, creaks |
| 4 Failure | ~70–55° | 80–120 ms hit-stop, burst (pieces, particles, spray, shockwave ring decal), top-screen white flash, 0.3× secondary slow-mo for 250 ms | Layered crunch/pop, max-sharpness transient |
| 5 Flatten | 55→35° | Spread meshes grow, pieces flatten, crumbs settle and persist | Squelch, decaying rumble |
| 6 Seal | <35° / closed | Inner screen fades; cover display shows tonnage + "OPEN TO SEE" | Final thunk, Toastie-style settle pulses |
| 7 Reveal | reopen | Ram stick/strands, specimen pop, stamp | Stamp thunk, chime |

**Rendering stack:** SwiftUI + RealityKit `RealityView` (iOS 27.1 min) for rendering, with these pieces:
- **Deformation and looks:** `CustomMaterial` geometry modifier + surface shader (Metal). Upgrade path to `MeshDeformerComponent`.
- **Ooze meshes:** `LowLevelMesh` + compute.
- **Particles:** RealityKit particle emitters plus a custom GPU particle buffer.
- **Post:** `PostProcessEffect` half-res bloom.
- **Hinge input:** `onHingeChange` → 1€ → spring.
- **Feedback:** Core Haptics; AVAudioEngine (with offline mode for export).
- **Export:** offline re-render → AVAssetWriter.

**Performance budget (A20 Pro, 120 Hz = 8.33 ms):**
- **Frame:** GPU ≤ 5.5 ms, CPU main ≤ 2.5 ms, rest headroom.
- **Geometry:** hero object 20–60k verts (dense enough for smooth analytic deformation); fragments ≤ 300 total and ≤ 40k verts. Particles ≤ 3k GPU, with alpha particles kept small on screen to limit overdraw.
- **Lights and post:** ≤ 120 draw calls; 1 shadowed light (soft shadows `.medium` only if budget allows); bloom at ¼ res. No SSR, no real refraction.
- **Memory and size:** memory ≤ 350 MB; app ≤ 80 MB.
- **Thermal:** on `.serious`, drop to 60 Hz, hard shadows and half the particles (Apple's WWDC26 thermal guidance).
- **Frame rate:** enable >60 Hz with `CADisableMinimumFrameDurationOnPhone`, and verify on hardware.

**4-week plan sketch:**
- **Week 1:** hinge pipeline, fallback control, analytic deformer, gummy + duck end-to-end.
- **Week 2:** pre-fracture system, egg/crayon/bottle/cookie, spread meshes.
- **Week 3:** can buckling, bubble wrap, cake, jelly, haptics/audio, cover screen.
- **Week 4:** specimen cards, album, offline video export, icon, screenshots, device tuning.

---

## Risks and open questions

1. **Hinge on real hardware is untested.** Every public sample is simulator-only ([FoldSafe](https://github.com/foldstatedev/FoldSafe); [expo-foldables](https://github.com/azizbecha/expo-foldables)). Update rate, quantisation and behaviour near closed are unknown. *Mitigation:* day-one device test harness logging raw samples; tune the 1€ filter, spring and thresholds from the logs.
2. **Viewing-angle reality.** The visibility math assumes a laptop pose and a 35° eye. Users may hold the phone in the air or in book pose. *Mitigation:* the gravity-based posture switch, and a curve that puts the climax in the visible band.
3. **RealityKit unknowns:** 120 Hz presentation, `RealityRenderer` on iOS for offline export, built-in SSS on iOS, and maturity of the brand-new `MeshDeformer` API (all *unverified*). *Mitigation:* keep deformation in `CustomMaterial` geometry modifiers (stable since iOS 15). Keep a raw-Metal export renderer as Plan B.
4. **The anamorphic illusion only works from one eye position.** Keep the off-axis effect mild (a 60/40 blend toward a normal projection) so it degrades gracefully.
5. **Code-only quality ceiling.** Procedural models can look generic. *Mitigation:* strict style rules (rounded bevels everywhere, saturated palette, strong specular) and a screenshot review loop: render, inspect, iterate. Buy one hero asset if the duck fails.
6. **Over-juicing at steep angles** hurts legibility. Do a contrast/clarity pass at 60° specifically.
7. **Content and trademarks:** use only fictional brands on cans and bottles. Keep 12+ by avoiding faces on destroyed objects and anything bodily in the ooze colours.
8. **Competition:** FoldHunt's Duo directory, as checked, lists hinge "pressing" apps (Inkblotter, Paint & Fold, Foldink, Exactly Half) and Toastie, but no hydraulic-press/crush toy ([FoldHunt](https://foldhunt.com/iphone-duo/)). The window exists but is likely short.
9. **Open question:** should the cover display be part of the experience at closed (a live gauge and pulses), or is a static card enough?

---

## Sources

- [Apple – UIHinge.angle (rate and granularity are system policy)](https://developer.apple.com/documentation/uikit/uihinge/angle.md)
- [Apple – onHingeChange(isEnabled:_:)](https://developer.apple.com/documentation/swiftui/view/onhingechange(isenabled:_:).md)
- [Apple – UIHingeInteraction](https://developer.apple.com/documentation/uikit/uihingeinteraction.md)
- [BleepingSwift – Reading the iPhone Duo hinge angle with onHingeChange](https://bleepingswift.com/blog/onhingechange-hinge-angle-swiftui)
- [Apple Tech Talk 111463 – Arrangements and reserved regions on iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111463/)
- [FoldSafe (GitHub) – hinge game, simulator notes](https://github.com/foldstatedev/FoldSafe)
- [expo-foldables (GitHub)](https://github.com/azizbecha/expo-foldables)
- [FoldHunt – iPhone Duo apps directory](https://foldhunt.com/iphone-duo/)
- [TechRadar – iPhone Duo review (Toastie)](https://www.techradar.com/phones/iphone/apple-iphone-duo-review)
- [Gizmodo – iPhone Duo review](https://gizmodo.com/iphone-duo-review-2000827502)
- [Man of Many – iPhone Duo review](https://manofmany.com/tech/smartphones/apple-iphone-duo-review)
- [Computerworld – iPhone Duo reviews roundup](https://www.computerworld.com/article/4238507/the-iphone-duo-reviews-are-in-expensive-late-and-winning.html)
- [duo-open (GitHub) – Android hinge sensor quirks and smoothing](https://github.com/marcoazeem/duo-open)
- [explainx – iPhone Duo fold animation on Android](https://explainx.ai/blog/iphone-duo-fold-animation-android-recreation-guide-2026)
- [Android – Make your app fold aware](https://developer.android.com/guide/topics/large-screens/make-apps-fold-aware)
- [WWDC26 – Explore advances in RealityKit](https://developer.apple.com/videos/play/wwdc2026/279/)
- [Apple – RealityKit Mesh deformation collection](https://developer.apple.com/documentation/realitykit/scene-content-mesh-deformation.md)
- [Apple – MeshDeformer](https://developer.apple.com/documentation/realitykit/meshdeformer.md)
- [Apple – MeshDeformerComponent](https://developer.apple.com/documentation/realitykit/meshdeformercomponent.md)
- [Apple – BlendShapeWeightsComponent](https://developer.apple.com/documentation/realitykit/blendshapeweightscomponent.md)
- [Apple – Generating interactive geometry with RealityKit (LowLevelMesh)](https://developer.apple.com/documentation/realitykit/generating-interactive-geometry-with-realitykit.md)
- [Apple – CustomMaterial](https://developer.apple.com/documentation/realitykit/custommaterial.md)
- [WWDC21 – Explore advanced rendering with RealityKit 2](https://developer.apple.com/videos/play/wwdc2021/10075/)
- [Apple – ShaderGraphMaterial](https://developer.apple.com/documentation/realitykit/shadergraphmaterial.md)
- [Apple – PostProcessEffect](https://developer.apple.com/documentation/realitykit/postprocesseffect.md)
- [WWDC25 – Bring your SceneKit project to RealityKit](https://developer.apple.com/videos/play/wwdc2025/288/)
- [Apple – Bringing your SceneKit projects to RealityKit](https://developer.apple.com/documentation/realitykit/bringing-your-scenekit-projects-to-realitykit.md)
- [Apple Forums – First-party recording of the composited view](https://developer.apple.com/forums/thread/831633)
- [Apple Forums – ReplayKit restart issue](https://developer.apple.com/forums/thread/689132)
- [Apple Forums – Programmatic screen recording](https://developer.apple.com/forums/thread/651099)
- [SideFX – Labs Vertex Animation Textures 3.0](https://www.sidefx.com/docs/houdini/nodes/out/labs--vertex_animation_textures-3.0.html)
- [Blender issue #114415 – USDZ conversion off main thread](https://projects.blender.org/blender/blender/issues/114415)
- [Ten Minute Physics – Matthias Müller (soft bodies, tet skinning)](https://matthias-research.github.io/pages/tenMinutePhysics/)
- [Dennis Gustafsson – Cracking Destruction (Smash Hit)](https://www.gamedeveloper.com/programming/cracking-destruction)
- [Casiez et al. – 1€ Filter](https://cristal.univ-lille.fr/~casiez/1euro)
- [Daniel Holden – Spring-It-On: The Game Developer's Spring-Roll-Call](https://theorangeduck.com/page/spring-roll-call)
- [Infovore – Notes on Nijman's "Art of Screenshake"](https://infovore.org/?p=5275)
- [GMTK – Secrets of Game Feel and Juice](https://amara.org/v/C3BGA)
- [Juicy Break (Juice it or lose it recreation)](https://crcdng.itch.io/juicy-break)
- [Game Developer – Has your game got juice?](https://www.gamedeveloper.com/business/has-your-game-got-juice-more-)
- [Game Developer – Don't juice it or lose it](https://gamedeveloper.com/design/video-indies-resist-the-urge-to-juice-it-or-lose-it-)
- [Automaton – Sakurai's YouTube channel (hit-stop)](https://automaton-media.com/en/news/20220824-15208/)
- [SSBWiki – Masahiro Sakurai](https://www.ssbwiki.com/Sakurai)
- [Wikipedia – Twelve basic principles of animation](https://en.wikipedia.org/wiki/Twelve_basic_principles_of_animation)
- [Wikipedia – Oddly satisfying videos](https://en.wikipedia.org/wiki/Oddly_satisfying_videos)
- [Live Science – Why #OddlySatisfying videos are so satisfying](https://www.livescience.com/62091-oddlysatisfying-videos-satisfying.html)
- [Nansen & Balanzategui – Visual tactility (Convergence, 2022)](https://journals.sagepub.com/doi/abs/10.1177/13548565221105196)
- [Vice – The Hydraulic Press Channel](https://broadly.vice.com/en/article/889wez/the-hydraulic-press-channel-is-the-internet-sensation-of-our-time)
- [Wikipedia – Hydraulic Press Channel](https://en.wikipedia.org/wiki/Hydraulic_Press_Channel)
- [Cheung et al. 2019 – Uncertainty and surprise jointly predict musical pleasure](https://cms.mus.cam.ac.uk/publications/cheung-uncertainty-surprise/)
- [MPI CBS – Music pleasure in pop songs](https://www.cbs.mpg.de/music-pleasure-in-pop-songs)
- [Kodeco – Getting started with Core Haptics](https://www.kodeco.com/10608020-getting-started-with-core-haptics)
- [Kenney – Food Kit (CC0)](https://kenney-assets.itch.io/food-kit)
- [HackerNoon – AI 3D generators stress test](https://hackernoon.com/how-i-stress-tested-3-ai-3d-generators-on-the-same-inputs-what-the-numbers-actually-show?source=rss)
- [Tripo AI review (2026)](https://pasqualepillitteri.it/en/news/7811/tripo-ai-review-3d-model-generator)
