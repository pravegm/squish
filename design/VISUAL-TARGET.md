# Squish: Visual Target v1.0

*Art direction for the two code-only engineers (Scene and UI). Written 22 Oct 2026 after the founder's review of CI run 1. It covers what the app must look like, with numbers. Where it disagrees with `SQUISH-DESIGN-BIBLE.md` §5/§9 or `research/03`, this document wins on visuals and the bible wins on behaviour. Every value marked **[tune]** is a starting point to confirm in the CI screenshot loop (§9). Every RealityKit API named here was checked against Apple's documentation JSON on 22 Oct 2026 (§3.1, with links).*

The constraints don't change:
- iOS 18 minimum, built with the iOS 27.1 SDK.
- No `CustomMaterial` and no shaders.
- Everything is procedural: CoreGraphics textures, generated meshes, `PhysicallyBasedMaterial` / `UnlitMaterial`.
- The only feedback loop is the CI simulator screenshot.

---

## 0. TL;DR: the twelve fixes that matter most, in order

1. **Fix the camera.** RealityKit's `fieldOfViewInDegrees` is **vertical by default** (`fieldOfViewOrientation = .vertical`). Our 30° vertical FOV on a 0.46-aspect portrait screen gives a **14° horizontal FOV**, so at 0.43 m the camera sees only 0.106 m of width. That's why the 0.13 m ram housing is a full-bleed yellow slab. Use the presets in §3.2.
2. **Stop the backdrop being tone-mapped.** `#F3EEE6` renders as `#CECBC5` (measured) because the unlit backdrop goes through RealityKit's filmic tone map. Use `UnlitMaterial(color:applyPostProcessToneMap: false)` with a baked gradient texture on a real cyclorama mesh (§3.4).
3. **Give the scene a designed environment.** Build a procedural studio HDRI → `EnvironmentResource(equirectangular:withName:)` → `ImageBasedLightComponent` + `ImageBasedLightReceiverComponent` (§3.3). Chrome reflecting the default environment is why the piston looks like black PVC pipe.
4. **Calibrate exposure** with a grey card and a white card in a `calib` demo scenario (§3.5). The yellow `#FFB81C` currently renders as lemon `#FFE242`–`#FFF65C` and the floor clips to pure `#FFFFFF`.
5. **Redesign the press as a complete toy H-frame machine** that fits inside the frame with margins (§4). No part of it may be full-bleed.
6. **Hero-scale the objects** to a 0.09–0.12 m footprint, so each fills 30–48% of the frame width and sits *on* the anvil, uncropped (§5).
7. **Use baked contact shadows and AO decals** under everything that touches anything (§3.6). These are the cheapest premium cue we have.
8. **Bevel every edge.** No primitive keeps its default sharp or uniform look (§4.3, §5).
9. **Put zero UI in the 45–80% height band.** Remove the "Drag down to press" hint and the top-right puck. All idle chrome lives on the press's console band (§6.1).
10. **Use one button language:** tactile keycaps (§6.6). Delete the translucent-white pills.
11. **Make the reveal a moment.** The ram lifts, the card drops into the top half, and the stamp thunks (§6.8). In run 1 the "reveal" frame showed no card at all.
12. **Fix the CI depth scenario.** The `depth=` frames are pixel-identical to idle (02 = 03, 01 = 04), so we can't judge the press state at all (§9.3).

---

## 1. Teardown of CI run 1 (honest)

Measured on the 1206×2622 PNGs, sampling every 6th pixel.

| Frame | Mean L | Pixels L<40 | Key samples |
|---|---|---|---|
| 01-launch | 186 | 5.3% | backdrop `#CECBC5`, ram housing `#FFF65C`/`#FFE242`, floor band `#FFFFFF` (clipped) |
| 02-duck-idle | 189 | 0.7% | backdrop `#CECBC5`, housing `#FFF456`, anvil `#48494C` |
| 03-duck-mid | 189 | 0.7% | **identical to 02**: the depth scenario didn't move the ram |
| 04-bubble-mid | 186 | 5.3% | **identical to 01** |
| 05-reveal-duck | 192 | 3.5% | translucent milky panel `#EFEEEB` over the top 44%, ram bottom `#0A0A0D` |

### 1.1 What's wrong, and why it reads cheap

**Camera and composition (the root cause)**
- **The camera is effectively a telephoto pointed at a wall of slabs.** A vertical 30° FOV on a 0.46-wide screen leaves a ~14° horizontal FOV. Every press part is wider than the view, so we see **cropped, full-bleed horizontal bands** instead of a machine: black pipe, yellow slab, grey bar, grey void, white stripe, blue tray. A frame made of stripes reads as a flag or a loading screen, not an object. Premium toy renders show **a whole object with air around it**.
- **There's no focal hierarchy.** The hero object is cut off by the bottom edge (01, 04: only the first row of bubbles shows) or is 63% of the frame width and bigger than the ram (02). The press and the object have no consistent scale relationship, so neither reads as real.
- **The anvil is invisible.** In 01/04 it's off-screen, and in 02 it's a dark band under the duck. The object doesn't sit *on* anything, so there's no story ("thing on anvil under ram").
- **Near-orthographic flatness.** A 14° horizontal FOV removes perspective. The press faces are dead flat with no vanishing, no top faces and no 3/4 read, which is exactly what makes primitives look like primitives.

**Light and colour**
- **The backdrop is cold grey `#CECBC5`, not warm `#F3EEE6`.** An unlit material is still tone-mapped. The world reads as "default grey viewport", not "warm studio".
- **A clipped white floor stripe (77–86% height) with hard horizontal edges.** It looks like a rendering bug. It comes from a lit PBR floor at roughness 0.9 under a 4,500 lux key plus a point fill plus the default IBL: overexposed.
- **Yellow shifts to lemon.** `#FFB81C` (amber hydraulic enamel) renders as `#FFE242`–`#FFF65C`. Overexposed saturated colours lose hue through the tone curve. Lemon reads as cheap plastic; amber reads as machinery.
- **Chrome with nothing to reflect.** At roughness 0.15 on the default environment, the piston is black with grey vertical stripes, like PVC pipe. Metals are only as good as the environment they reflect, and we haven't designed one.
- **No grounding.** There are no contact shadows, no AO and no shadow on any floor. Objects float. The one blob shadow (`opacity 0.15 black`) is hidden under the camera crop.
- **No gradients anywhere.** Flat backdrop, flat floor and flat slabs mean no depth, no atmosphere, no light pool.
- **Pure-black areas.** 5.3% of pixels have L<40 (the piston), and 05 has `#0A0A0D` regions. On the Duo's matte nano-texture display, crushed blacks look milky and dead.

**Modelling**
- **Default primitives everywhere.** The boxes all share one 2–6 mm corner radius at every scale, and the cylinders have hard rims. There are no part breaks, no bolts, no collars, no secondary forms. Nothing says "machine".
- **The duck is a stack of spheres.** Body, head and tail are separate balls with hard intersections (no smooth union). The beak is a capsule, so it reads as a sausage. One eye lacks a highlight. The duck is in profile, the least appealing view. Its colour is lemon, not duck-yellow.
- **The bubble wrap reads as a blue ice-cube tray.** The domes are uniform and the film is opaque blue-grey. There's no sheet edge and no transparency cue.
- **The squashed duck (05)** is two flat yellow ellipses and an orange sliver. There's no bulge, no rim and no highlight, so it reads as a bug, not a pancake.

**UI**
- **UI sits on the stage.** "Drag down to press" plus the hand glyph sits at 50–56% height, in the middle of the stage, grey on grey (~2:1 contrast). It breaks the bible's "zero UI during a press".
- **The object picker pills cover the object** (88–94% band, over the bubble wrap and the duck's belly).
- **The two pill styles don't match.** One is solid yellow and the other is translucent white with grey text. The duck icon is a generic bird glyph (a hummingbird) that doesn't match a rubber duck. The settings glyph is a thin grey outline floating over a yellow slab.
- **The reveal (05) has no card, no stamp and no label.** A translucent rectangle with a hard edge at 44% cuts the ram in half, and the ram is still down. The peak-end moment is a glitch frame.

**Process**
- **Mid-press screenshots equal idle screenshots,** so CI can't judge strain, contact or failure. We are flying blind on the 80% of the experience that matters.

**Net read:** "RealityKit primitives in a grey void, with debug UI." Nothing in the frame shows intent, and nobody pays £2.99 for that. The fix isn't polish. It's **composition, environment, exposure, and real forms**, in that order.

---

## 2. North star

### 2.1 In five sentences
1. Squish looks like **a premium vinyl toy photographed in a warm, seamless studio**: one chunky, lovingly bevelled hydraulic press, one candy-bright object on its anvil, and nothing else.
2. Light does the selling. The light is a **soft key from the upper left, long strip highlights on everything glossy, a warm floor bounce, crisp-soft contact shadows, and no black anywhere.**
3. Every frame, including every mid-press frame the user might hold for ten seconds, must work as **an App Store screenshot**: centred, symmetric, legible at thumbnail size, with the object as the brightest and most saturated thing in it.
4. The press is a **character with instruments**: a gauge that strains, lamps that glow, a chrome rod that extends and a hazard band that descends, so tension is *visible* before anything breaks.
5. Mess is **candy-tidy and permanent**: glossy spreads, chunky shards and bright crumbs that end in a clean, collectible specimen card on paper.

### 2.2 Six references and what we steal from each

| # | Reference | What we steal (concrete) |
|---|---|---|
| 1 | **Apple product hero renders** (e.g. [HomePod mini colours](https://www.apple.com/homepod-mini/), [iPhone](https://www.apple.com/iphone/)) | Seamless sweep with a gentle light pool behind the product. **Tinted backdrops that complement the product colour** (our per-object "gel wall", §3.4). Long strip-softbox reflections on glossy and metal parts. Soft but defined contact shadows. One hero, dead centre, with generous margins. |
| 2 | **(Not Boring) apps**, Andy Allen ([notbor.ing](https://notbor.ing/), [Behind the Design: Habits](https://developer.apple.com/news/?id=9ab1g4r3)) | Real-time 3D objects *are* the UI, built "like a game, runs like an app". The rule "you have to put in what's taken away": **stack 6–7 feedback layers per interaction** (motion, light, sound, haptic, particle, number, glow). Chunky physical controls, with skins as "materials". |
| 3 | **Monument Valley**, ustwo / Ken Wong ([GDC: Designing Monument Valley](https://www.gdcvault.com/play/1020878/), [Creative Bloq making-of](https://www.creativebloq.com/computer-arts/making-monument-valley-71412213)) | "Every screen could be framed and hung on a wall." Every form shows **three tones (lit / mid / shadow)**. **Avoid heavily saturated dark hues.** Print every screen and review them as a **colour script on a wall**: our CI contact sheet (§9.4). |
| 4 | **Townscaper**, Oskar Stålberg ([Steam](https://store.steampowered.com/app/1291340/Townscaper/)) | Soft, rounded bevels on every edge at every scale. A pastel world with saturated accents. Toy scale. Satisfying, squishy placement animation (our object landing). |
| 5 | **Halide**, Lux ([Behind the Design: Halide Mark II](https://developer.apple.com/news/?id=x6bv1a36)) | Instruments modelled on real camera dials, with haptic detents and **etched-metal-style typography**. That's the gauge face and the SF Mono specimen labels. Delight with zero intimidation. |
| 6 | **Smash Hit**, Mediocre ([Gustafsson, "Cracking destruction"](https://www.gamedeveloper.com/programming/cracking-destruction)) | **One consistent material language** made procedural destruction look intentional. Chunky, soft-edged shards. A bright, clean world in which breakage reads instantly. |

Also borrowed:
- **A Little to the Left** ([Game Developer](https://www.gamedeveloper.com/design/the-methodical-catharsis-of-tidying-in-a-little-to-the-left)): a **~10-colour palette** and tidy end states.
- **Alto's Odyssey** ([Game Developer, Road to the IGF](https://www.gamedeveloper.com/business/road-to-the-igf-team-alto-s-i-alto-s-odyssey-i-)): confident gradients and per-scene colour moods.
- **Flighty** ([Behind the Design](https://developer.apple.com/news/?id=970ncww4)): chrome should feel "almost boringly obvious".

What the genre does wrong, from the App Store "squishy / ASMR" apps (e.g. [Squishy Magic](https://apps.apple.com/us/app/squishy-magic-asmr-toy-maker/id1490398089), [ASMR Squishy](https://apps.apple.com/us/app/asmr-squishy-antistress-toy/id1483419666)):
- dark rooms
- unlit gradients
- default physics
- ad chrome
- "rise too slowly to feel satisfying"

That's the bar we clear.

### 2.3 Extracted rules (apply everywhere)

| Area | Rule |
|---|---|
| Palette ratio | **70% warm neutral** (sweep, paper), **20% machine** (yellow + graphite + steel), **10% hero candy** (the object and its mess). The object is always the most saturated region. |
| Values | Mid-key: frame mean luminance 175–215. Darkest large area is graphite (L ≥ 45). Brightest is specular only. |
| Tones | Every form shows lit, mid and core shadow. Lit vs shadow ΔL ≥ 30; shadow side L ≥ 45. |
| Light | One key (upper left, 45° elevation), a strip/top highlight, a cool soft fill (right), two rim strips behind, a warm floor bounce, and black flags so metals have contrast. Key:fill ≈ 2.5:1. |
| Camera | Elevated 3/4 product view: 14° downward pitch, ~25–27° from the camera to the anvil. Gentle perspective (24° horizontal FOV in portrait). Never orthographic in the live scene. |
| Bevels | Bevel radius ≈ 6–10% of the part's smallest dimension. Never below 1.5 mm. Never zero. |
| Roughness | Clearcoated enamels 0.30–0.45 base with clearcoat roughness 0.08–0.15. Candy and vinyl 0.15–0.30. Wax and sponge 0.5–0.85. Chrome 0.04–0.10. Brushed steel 0.28–0.35. |
| Shadows | Shadows are always warm-tinted (`#3B2F25`), never black. Two layers: a tight AO ring plus a soft offset blob. |
| Motion | The hand owns the ram, with no easing on it. Everything else springs. Nothing linear except fades. |
| Type | SF Pro Rounded Heavy/Black for voice, SF Mono for data. Nothing else. |

---

## 3. Scene spec (with numbers)

World units are metres. Origin = **anvil top-face centre**. +X right, +Y up, +Z toward the camera.

### 3.1 Verified RealityKit APIs (iOS 18 unless stated)

Checked against `developer.apple.com/tutorials/data/documentation/realitykit/...` JSON on 22 Oct 2026.

**Image-based lighting from code: it exists on iOS 18.**

```swift
// iOS 18.0+ (deprecated in 27.2 with message "Use init(equirectangular:options:)"; we build on 27.1, so no warning)
@MainActor convenience init(equirectangular cgImage: CGImage, withName resourceName: String? = nil) throws
@MainActor convenience init(equirectangular cgImage: CGImage, withName resourceName: String? = nil) async throws
// iOS 27.0+
@MainActor convenience init(equirectangular cgImage: CGImage, options: EnvironmentResource.CreateOptions) async throws
@MainActor convenience init(equirectangular cgImage: CGImage, options: EnvironmentResource.CreateOptions) throws
// EnvironmentResource.CreateOptions (iOS 18.0+):
init(samplingQuality: EnvironmentResource.CreateOptions.SamplingQuality = .fast,
     specularCubeDimension: Int? = nil,
     compression: EnvironmentResource.Compression = .default)   // SamplingQuality: .fast .normal .high .veryHigh
```

Links:
- [init(equirectangular:withName:)](https://developer.apple.com/documentation/realitykit/environmentresource/init(equirectangular:withname:))
- [init(equirectangular:options:)](https://developer.apple.com/documentation/realitykit/environmentresource/init(equirectangular:options:))
- [CreateOptions](https://developer.apple.com/documentation/realitykit/environmentresource/createoptions)

Notes:
- `EnvironmentResource.generate(fromEquirectangular:)` is **visionOS-only and deprecated**. Don't use it.
- Apple's parameter doc says "to preserve all details use an image where the width is half the height". The standard lat-long layout is **width = 2 × height**, and that's what we use (1024×512). If the CI chrome-ball check (§3.3.4) shows a squashed reflection, swap to 512×1024 and record it here.

**Light components**

```swift
struct ImageBasedLightComponent            // iOS 18.0+
init(source: ImageBasedLightComponent.Source, intensityExponent: Float = 0)
enum Source { case none; case single(EnvironmentResource); case blend(EnvironmentResource, EnvironmentResource, Float) }
var inheritsRotation: Bool                // IBL follows the holder entity's rotation
var intensityExponent: Float              // multiplier = 2^intensityExponent

struct ImageBasedLightReceiverComponent    // iOS 18.0+
init(imageBasedLight: Entity)             // applies to the entity and its descendants (per Kassioui; add to every root anyway)

struct EnvironmentLightingConfigurationComponent   // iOS 18.0+; also affects descendants
init(environmentLightingWeight: Float)
```

Links:
- [ImageBasedLightComponent](https://developer.apple.com/documentation/realitykit/imagebasedlightcomponent)
- [ImageBasedLightReceiverComponent](https://developer.apple.com/documentation/realitykit/imagebasedlightreceivercomponent)
- [EnvironmentLightingConfigurationComponent](https://developer.apple.com/documentation/realitykit/environmentlightingconfigurationcomponent)
- [Kassioui, Light & Shadow in RealityKit](https://www.achrafkassioui.com/blog/light-and-shadow-in-realitykit/)

**RealityView environment and rendering effects (our host)**

```swift
// RealityViewCameraContent (iOS 18.0+)
var environment: RealityViewEnvironment          // .default  |  .skybox(EnvironmentResource)
var renderingEffects: RealityViewRenderingEffects // antialiasing, cameraGrain, depthOfField, dynamicRange (.default/.standard), motionBlur
                                                  // customPostProcessing is iOS 26.0+ (avoid in v1)
```

Links:
- [RealityViewCameraContent](https://developer.apple.com/documentation/realitykit/realityviewcameracontent)
- [RealityViewEnvironment](https://developer.apple.com/documentation/realitykit/realityviewenvironment)
- [RealityViewRenderingEffects](https://developer.apple.com/documentation/realitykit/realityviewrenderingeffects)

Don't use `.skybox(...)`: it sets the background *and* the lighting together, and the background can't catch our shadows ([forum thread 761982](https://developer.apple.com/forums/thread/761982), whose accepted fix splits them exactly as we do). Keep `.default`, render our own sweep mesh, and light with an IBL component. Keep `dynamicRange = .default`: RealityKit applies HDR plus tone mapping as a cheap post step, and we want its highlight roll-off on lit materials.

**ARView, only if we ever switch hosts**

```swift
ARView(frame:cameraMode: .nonAR, automaticallyConfigureSession: false)
arView.environment.lighting.resource = env               // EnvironmentResource?   (iOS 13+)
arView.environment.lighting.intensityExponent = 0        // log2 scale             (iOS 13+)
arView.renderOptions.insert(.disableGroundingShadows)    // also .disableHDR, .disableAutomaticLighting, .disableDepthOfField, .disableMotionBlur, .disableCameraGrain
```

Links:
- [ARView.Environment](https://developer.apple.com/documentation/realitykit/arview/environment-swift.struct)
- [RenderOptions](https://developer.apple.com/documentation/realitykit/arview/renderoptions-swift.struct)

**Unlit and tone mapping (needed for exact backdrop colours)**

```swift
UnlitMaterial(color: UIColor, applyPostProcessToneMap: Bool)   // iOS 18.0+
UnlitMaterial(applyPostProcessToneMap: Bool)                   // iOS 18.0+, then set .color = .init(tint:, texture:)
```

Link: [UnlitMaterial](https://developer.apple.com/documentation/realitykit/unlitmaterial)

**Shadows**

```swift
// Directional light shadow (iOS 18.0+ init)
DirectionalLightComponent.Shadow(shadowProjection: .fixed(zNear: 0.01, zFar: 10, orthographicScale: 1), depthBias: Float, cullMode: ...? = nil)
//   or .automatic(maximumDistance:)
// iOS 27.0+: DirectionalLightComponent.Shadow.cascades
// iOS 27.0+: SpotLightComponent.Shadow.lightSize: Float (emitter radius in metres → penumbra)
//            SpotLightComponent.Shadow.quality: .low / .medium / .high
GroundingShadowComponent(castsShadow: Bool)                       // iOS 18.0+
GroundingShadowComponent(castsShadow: Bool, receivesShadow: Bool) // iOS 18.0+
DynamicLightShadowComponent(castsShadow: Bool)                    // iOS 18.0+
```

Links:
- [DirectionalLightComponent.Shadow](https://developer.apple.com/documentation/realitykit/directionallightcomponent/shadow)
- [SpotLightComponent.Shadow.lightSize](https://developer.apple.com/documentation/realitykit/spotlightcomponent/shadow/lightsize)
- [GroundingShadowComponent](https://developer.apple.com/documentation/realitykit/groundingshadowcomponent)

`GroundingShadowComponent` is "a light source directly above" that ignores scene lights, doesn't apply to hierarchies (add it per entity), and is **unverified in a non-AR RealityView**. One forum report says it only appears on ARKit-detected planes. So **our own baked decals (§3.6) are the primary contact shadow.** `GroundingShadowComponent(castsShadow: true)` on the object is an optional extra that's kept only if the CI frame shows it.

**Camera**

```swift
PerspectiveCameraComponent(near: 0.01, far: .infinity, fieldOfViewInDegrees: 60, fieldOfViewOrientation: .vertical)  // defaults shown; iOS 18.0+
OrthographicCameraComponent   // iOS 18.0+ (scale, scaleDirection) — for specimen thumbnails
```

Links:
- [PerspectiveCameraComponent](https://developer.apple.com/documentation/realitykit/perspectivecameracomponent)
- [OrthographicCameraComponent](https://developer.apple.com/documentation/realitykit/orthographiccameracomponent)

**Geometry and textures**

```swift
MeshResource(extruding: Path, extrusionOptions: MeshResource.ShapeExtrusionOptions) async throws   // iOS 18.0+
//  options: extrusionMethod = .linear(depth:), chamferRadius: Float, chamferMode: .front/.back/.both,
//           chamferProfile: Path?, materialAssignment: .init(front:back:extrusion:frontChamfer:backChamfer:)
MeshResource.generateBox(width:height:depth:cornerRadius:splitFaces:)   // iOS 13
MeshResource.generateCylinder(height:radius:), .generateCone(height:radius:) // iOS 18
TextureResource(image: CGImage, withName: String? = nil, options: TextureResource.CreateOptions) throws // iOS 18
```

Links:
- [init(extruding:extrusionOptions:)](https://developer.apple.com/documentation/realitykit/meshresource/init(extruding:extrusionoptions:))
- [ShapeExtrusionOptions](https://developer.apple.com/documentation/realitykit/meshresource/shapeextrusionoptions)

**Materials**

`PhysicallyBasedMaterial` (iOS 15) has:
- `baseColor`, `roughness`, `metallic`, `specular`
- `clearcoat`, `clearcoatRoughness`
- `sheen`
- `emissiveColor`, `emissiveIntensity`
- `ambientOcclusion`, `normal`
- `anisotropyLevel`/`anisotropyAngle`
- `blending`, `opacityThreshold`, `faceCulling`

The `subsurface*` properties are **iOS 27.0+**: gate them with `#available(iOS 27.0, *)` and keep the fake-SSS fallback (§5) as the iOS 18 path.

### 3.2 Camera

**The rule: in portrait, the vertical composition is locked and the width floats.** In landscape, the whole press is framed as a diorama.

| Preset | When | Camera position | Pitch | FOV | Result at the anvil plane |
|---|---|---|---|---|---|
| **P — phone portrait** | aspect *a* = w/h ≤ 0.56 (CI: 1206×2622, a = 0.46) | `(0, 0.3225, 0.6468)` | look down 14° (yaw 0) | **49.6° vertical** (`.vertical`) | visible height 0.652 m, width 0.652·*a* (0.30 m at a = 0.46). Anvil top at **74%** height, ram home at **43%**, crown top at **9%**, gauge centre **14%**, bed bottom **95%** |
| **D — Duo press posture**, full inner display | 0.66 ≤ *a* ≤ 0.80 (Duo ≈ 0.71) | `(0, 0.3503, 0.7903)` | 14° down | **40.0° vertical** | visible height 0.62 m, width 0.44 m. Anvil top at 74% (bottom half, ~48% from crease to front edge). Ram home at 41% (top half). Crown top 6% |
| **L — landscape diorama** | *a* ≥ 1.2 | `(0, 0.3781, 1.1157)` | 12° down | **30.0° vertical** | visible height 0.627 m. Anvil top at 72%, crown top 6.5%, bed bottom 93%. Object ≈ 12–18% of width; UI uses the side columns |

- Between presets (0.56–0.66 and 0.80–1.2), lerp position, pitch and FOV linearly on *a*.
- Build the camera as `PerspectiveCamera()` with `camera.fieldOfViewInDegrees = fov`, then `look(at: target, from: pos, relativeTo: nil)`, where `target = pos + forward`, `forward = (0, −sin(pitch), −cos(pitch))`.
- Set **`fieldOfViewOrientation = .vertical` explicitly**.
- Set **near 0.05**, far 5.

**Derivation, so it can be re-solved for any new target.** For a world point P at depth plane z ≈ 0:
- α = atan((C.y − P.y) / (C.z − P.z)) is the angle below horizontal.
- Screen y fraction from top: s = 0.5 + 0.5 · tan(α − pitch) / tan(vFOV/2).

Preset P is solved for:
- s(anvil top) = 0.74
- visible width 0.30 m at a = 0.46
- pitch 14°

These give a camera-to-anvil distance of 0.7228 m on a line 26.5° below horizontal.

**Where the object sits:**
- Horizontally centred: x = 0, centre within 50% ± 2% of width.
- Its contact line is at 74% (P/D) or 72% (L).
- Its top is at ~58–62%, so the whole object lies inside the stage band (45–80%).
- Never let the hero object move off the anvil, except debris.

**No camera motion during a press.** The hand owns the scene. Two exceptions:
1. The reveal may push in 4% (FOV ×0.96 over 0.6 s, spring response 0.6, damping 1.0).
2. The offline share clip has its own cinematic camera.

Reduce Motion turns off the push-in.

### 3.3 The studio: a procedural HDRI recipe

**Generate it once per launch**, asynchronously before the first frame shows. A 1024×512 equirect takes ~30–80 ms on the CPU. Build the `EnvironmentResource` from it and keep it for the session. Don't regenerate it per object; gel tints live on the sweep, not in the IBL.

#### 3.3.1 Format
- **Preferred:** 1024×512 **linear, float32 RGBA** `CGImage`, so the softboxes can exceed 1.0.
  - `CGColorSpace(name: CGColorSpace.extendedLinearSRGB)`
  - `bitsPerComponent: 32`, `bytesPerRow: w*16`
  - `bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue`
  - Write the Float32 pixels into `ctx.data`, then call `ctx.makeImage()`.
- **Fallback** if the simulator rejects float CGImages or the result looks clipped: 8-bit sRGB.
  - Divide every radiance below by 5.0 (so the key = 1.0).
  - Raise `intensityExponent` by +2.3.
  - Accept that highlights will be less punchy.
- Record which path is live in `PressScene` with a comment.

#### 3.3.2 Direction convention
For pixel (u, v) in [0,1]²:
- λ = (u − 0.5)·2π, φ = (0.5 − v)·π
- d = (sin λ·cos φ, sin φ, cos λ·cos φ)

So u = 0.5 is **+Z (toward the camera, behind the viewer)**, and v = 0 is straight up. Because RealityKit's internal convention is unverified, put the IBL on its own entity with `inheritsRotation = true`. If the calibration ball (§3.3.4) shows the wrong azimuth, fix it by **rotating that entity about Y** (`ibl.orientation = simd_quatf(angle: k·π/2, axis: [0,1,0])`). Never edit the recipe to fix orientation.

#### 3.3.3 Recipe

Linear radiance; colours are linear RGB multipliers.

**Base gradient** (smooth Hermite between stops, by elevation φ):

| φ | Radiance | Colour | Meaning |
|---|---|---|---|
| +90° | 0.95 | (1.00, 0.97, 0.92) | warm ceiling |
| +35° | 0.78 | (1.00, 0.96, 0.90) | |
| +5° | 0.62 | (0.98, 0.93, 0.86) | cream studio walls |
| −5° | 0.48 | (0.98, 0.90, 0.78) | cream floor |
| −90° | 0.30 | (0.95, 0.86, 0.74) | warm floor bounce |

**Shapes.** Each is a rounded rectangle in the light's own tangent frame. Its angular size is (width × height) in degrees, with corner radius 6° and a smoothstep feather of 4° at the edge.
- *Add* mode: `rad += colour·value·mask`.
- *Replace* mode: `rad = mix(rad, colour·value, mask)`.

| Shape | Azimuth λ | Elevation φ | Size (w×h) | Value | Colour | Mode | Purpose |
|---|---|---|---|---|---|---|---|
| **Key softbox** | −40° (camera-left) | +45° | 55° × 40° | **5.0** | (1.00, 0.98, 0.95) | add | Main modelling light; big soft highlight top-left on everything glossy |
| **Top strip** | 0° | +75° | 70° × 12° | 2.2 | (1.00, 1.00, 1.00) | add | Clean horizontal highlight line on rounded tops (duck head, egg, can lid, crown bevel) |
| **Fill card** | +65° | +20° | 30° × 45° | 1.2 | (0.94, 0.97, 1.00) | add | Cool soft fill, right side (key:fill ≈ 2.5:1) |
| **Rim strip L** | −135° | +25° | 10° × 55° | 4.0 | (1.00, 0.98, 0.96) | add | Vertical edge line on glass, chrome columns, can |
| **Rim strip R** | +135° | +25° | 10° × 55° | 4.0 | (1.00, 0.98, 0.96) | add | ditto, other side |
| **Front card** | +15° | +6° | 35° × 20° | 1.0 | (1.00, 0.97, 0.93) | add | What the camera-facing centre of chrome reflects; stops "black hole" centres |
| **Floor bounce** | 0° | −25° | 80° × 25° | 0.8 | (1.00, 0.92, 0.80) | add | Warm underside fill (duck belly, can bottom) |
| **Black flag L** | −95° | +10° | 22° × 50° | 0.03 | (1,1,1) | replace | Gives chrome and enamel a dark reflection band → contrast |
| **Black flag R** | +95° | +10° | 22° × 50° | 0.03 | (1,1,1) | replace | ditto |
| **Back wall** | ±180° | 0…+40° | 90° × 40° | 0.55 | gel-neutral (0.95, 0.94, 0.92) | replace | Behind the press; keeps the rims readable |

Add a **dither of ±0.002** to every pixel (prevents banding in the specular mips).

**Creation:**

```swift
@MainActor
func makeStudioIBL() async throws -> Entity {
    let cg = StudioHDRI.render(width: 1024, height: 512)          // §3.3.3
    let env: EnvironmentResource
    if #available(iOS 27.0, *) {
        env = try await EnvironmentResource(equirectangular: cg,
                  options: .init(samplingQuality: .high, specularCubeDimension: 256))
    } else {
        env = try await EnvironmentResource(equirectangular: cg, withName: "squish.studio")
    }
    let holder = Entity()
    var ibl = ImageBasedLightComponent(source: .single(env), intensityExponent: 0.0)  // [tune] via §3.5
    ibl.inheritsRotation = true
    holder.components.set(ibl)
    return holder
}
// Every lit root (press, object slot, debris root, card-render root):
root.components.set(ImageBasedLightReceiverComponent(imageBasedLight: iblHolder))
```

#### 3.3.4 Orientation check (CI scenario `object=unsquishable;calib`)
On the chrome ball, you must see:
- (a) a **large bright rounded rectangle in the upper-left quadrant** (the key)
- (b) a **thin horizontal bright bar near the top** (the top strip)
- (c) **two dark vertical bands left and right** (the flags)
- (d) a **soft bright patch slightly right of centre** (the front card)
- (e) a **warm cream lower third** (the floor)

If (a) appears upper-right, rotate the IBL holder 90° about Y, and keep rotating until it's correct.

### 3.4 The cyclorama (seamless sweep) and background colour

**Geometry.** One mesh, generated with `MeshDescriptor`. The profile in the YZ plane:
- Floor at y = −0.108, from z = +0.50 back to z = −0.30.
- A quarter-circle **bend of radius 0.25 m** up to the wall at z = −0.55.
- Wall from y = 0.142 to y = 1.20.

Mesh layout:
- Width x ∈ [−0.90, +0.90].
- 64 segments along the profile (16 in the bend) and 4 across.
- UV: u = (x + 0.9)/1.8; v = arc length / total length (v = 0 at the front floor edge).

**Material.** `UnlitMaterial(applyPostProcessToneMap: false)` with `color = .init(tint: .white, texture: .init(sweepTexture))`. Because it's unlit with no tone map, the pixels on screen equal the texture pixels. That gives deterministic colours that SwiftUI can match exactly.

**Sweep texture:** 1024 × 1024 sRGB, regenerated in `setObject` (≤ 15 ms) or crossfaded (below).

| Region (v, as ~% of the profile) | Colour | Notes |
|---|---|---|
| Front floor (v 0–0.18) | `#F1E9DC` | slightly darker toward the screen bottom = a natural foreground vignette |
| Light pool under press (v 0.18–0.40, u 0.35–0.65) | `#F8F3EA` centre → `#F1E9DC` edge, radial | the "lit tabletop" |
| Back floor (v 0.40–0.50) | `#EEE5D7` | |
| Bend (v 0.50–0.64) | `#EAE0D0` → wall-bottom colour | a cyc bend reads slightly darker; this sells the sweep |
| Wall bottom (v 0.64) | `#EDE5D8` | |
| Wall top (v 1.0) | **gel colour** for the current object (table below) | blend over v 0.64 → 0.90 with smoothstep |

Texture rules:
- **Horizontal vignette:** multiply luminance by 1 − 0.06·((u − 0.5)/0.5)².
- **Baked press shadow on the wall:**
  - A soft ellipse, 0.30 m wide × 0.42 m tall.
  - Centred on the wall at x = +0.10, y = 0.20, offset right because the key is from the left.
  - Colour `#3B2F25`, alpha 0.07, gaussian σ = 0.12 m.
- **Dither:** add uniform noise ±1/255 per channel. **Mandatory**: 8-bit gradients band visibly otherwise.

**Gel wall colours** (complementary pastel per object; OKLCH L 0.89–0.93, C 0.03–0.05):

| Object | Hero tint | Gel wall top |
|---|---|---|
| Bubble Wrap | `#8FCBE8` | apricot `#F6E3D3` |
| Rubber Duck | `#FFD23F` | periwinkle `#DDE3F3` |
| Jelly | `#E8336F` | mint `#D9EEE4` |
| Crayon | `#2F5BEA` | peach `#F7DFCF` |
| Egg | `#F2D9A6` | sky `#D8E8F2` |
| Cake Slice | `#F59BB5` | pistachio `#E1EDD6` |
| Soda Can | `#8BD448` | lilac `#E8DDF0` |
| Gummy Bear | `#FF5A4E` | aqua `#D5ECEC` |
| Glass Bottle | `#5CC8B8` | blush `#F4DDDA` |
| The Unsquishable | steel | butter `#F5EACB` |
| *Golden variant (any)* | gold | cream `#F3E6C4` plus a radial brightening behind the object (+5%) |

**Gel changes.** When the object changes, crossfade over 400 ms using a second wall-only overlay mesh:
- It sits 2 mm in front of the wall section of the sweep and covers v 0.55–1.0.
- `UnlitMaterial(applyPostProcessToneMap: false)` with alpha `.transparent(opacity:)`, ramped per frame.
- After the fade, re-bake the base texture and drop the overlay.
- Reduce Motion: cut directly.

**SwiftUI behind the RealityView:** fill with the current gel wall-top colour, so rotation and launch flashes match the scene. Keep `content.environment = .default`.

**Depth cues, all cheap:**
1. Contact shadows and AO (§3.6).
2. Gentle perspective (49.6° vertical FOV).
3. The light pool behind the object.
4. The bend darkening.
5. Warm floor vs cool-tinted wall (aerial perspective).
6. The baked press shadow on the wall.
7. Rim highlights on silhouettes.
8. Overlap: the columns stand in front of the wall.

No real depth of field in v1. The sweep has no detail to blur, so DOF is unnecessary.

### 3.5 Lights, exposure and calibration

| Light | Type | From (direction to the light) | Intensity | Colour | Shadow |
|---|---|---|---|---|---|
| **Key** | `DirectionalLight` | (−0.455, 0.707, 0.542), matching the key softbox | **1,200 lux** [tune] (Apple's table: "photography studio 1,000–2,000 lux") | (1.00, 0.97, 0.93) | yes: `Shadow(shadowProjection: .fixed(zNear: 0.05, zFar: 3.0, orthographicScale: 0.55), depthBias: 1.0)` |
| **Key, iOS 27+ alternative** | `SpotLight` at distance 1.2 m along the key direction, aimed at (0, 0.05, 0) | inner 30°, outer 50°, attenuationRadius 4 | tune to match the directional's grey-card value | same | `lightSize 0.12`, `quality .high` (soft penumbra). Gate with `#available(iOS 27.0, *)`; if it costs > 0.8 ms GPU, drop to `.medium` |
| **Rim** | `SpotLight` at (0.25, 0.45, −0.45), aimed at (0, 0.05, 0) | inner 20°, outer 35°, attenuationRadius 2.0 | [tune] until the duck's top-back edge reads `#FFF4E0` ±10 | (1.00, 0.93, 0.82) | none |
| Fill | none (IBL fill card) | | | | |

- **Delete** the current `PointLight` fill and rim.
- **Max 2 dynamic lights**, 1 shadowed.
- Emissive lamps aren't lights.

**Exposure controls we actually have:**
- `ImageBasedLightComponent.intensityExponent`, the primary exposure knob: 2^x on all IBL.
- The key's lux.
- Base colours.

There is no camera exposure or EV API on iOS 18 RealityKit.

**Calibration scenario `-squishDemo "calib"`.** Place two 0.05 × 0.07 cards standing on the anvil, angled 30° toward the key:
- grey: PBR `#767676`, roughness 1.0
- white: `#F2F2F2`, roughness 1.0

Pass (sRGB, measured on the lit face centre):
- grey card **150–175**
- white card **225–245**, never ≥ 250
- unlit sweep sample = texture value ±2

Procedure:
1. Set the key to 0 and adjust `intensityExponent` until the grey card reads ~120 from IBL alone.
2. Raise the key lux until the grey card reads 160.
3. Check the white card.
4. Check that the yellow crown front reads hue 38–44°, S ≥ 0.75, V 0.85–0.98.
5. If the yellow still drifts lemon, lower the yellow base colour value (below) before touching the lights.

### 3.6 Shadows, AO and grounding (baked decals)

All decals are unlit planes:
- `UnlitMaterial(applyPostProcessToneMap: false)`
- texture = radial gaussian alpha, 256² `CGImage`
- tint `#3B2F25`
- `blending = .transparent(opacity: 1)`, with alpha in the texture
- lifted **0.3 mm** above the receiving surface
- `faceCulling = .back`
- **opacity animated per frame** by updating the material only when it changes by > 0.02 (as today)

| Decal | Receiver | Size | Offset | Alpha | σ (of half-size) | Behaviour |
|---|---|---|---|---|---|---|
| **Object AO ring** | anvil top | footprint × 1.15 | (+0.003, 0, −0.003) | 0.55 | 0.35 | Follows the object's current footprint (spread radius after contact) |
| **Object soft shadow** | anvil top | footprint × 1.8 | (+0.012, 0, −0.010) | 0.22 | 0.50 | Fades to 0.12 as the ram covers the object (the ram occludes the key) |
| **Ram occlusion** | anvil top and object top | 0.16 × 0.11 | (+0.006, 0, −0.004) | 0 → **0.30** as gap → 0 | 0.45 | The bible's "contact shadow darkens as the ram approaches" |
| **Anvil-on-bed AO** | bed top | 0.165 × 0.125 | 0 | 0.45 | 0.25 | static |
| **Column-foot AO** | bed top | Ø 0.04 each | 0 | 0.40 | 0.30 | static |
| **Press on floor** | sweep floor | 0.36 × 0.26 | (+0.03, 0, −0.03) | 0.35 | 0.45 | static |
| **Bed-edge AO strip** | sweep floor | 0.24 × 0.016 along the bed's bottom front edge | 0 | 0.50 | 0.40 | static |
| **Mess AO** | anvil top | per spread disc × 1.08 | 0 | 0.30 | 0.30 | Under every spread mesh and large shard |

The key light's real shadow map draws the object's cast shadow on the anvil and the platen's cast shadow on the object. The decals guarantee grounding even if the shadow map is coarse.

Set `DynamicLightShadowComponent(castsShadow: false)` on:
- the sweep
- decals
- glow sprites
- gauge glass

### 3.7 "Post-like" effects without shaders

| Effect | How |
|---|---|
| Vignette | Baked into the sweep texture (§3.4). No full-screen overlay. |
| Bloom on lamps and glints | `UnlitMaterial(applyPostProcessToneMap: false)` billboard quads (always face the camera; update orientation per frame) with a radial alpha texture: Ø 0.04 m for lamps, alpha 0.35; Ø 0.02 m for glints. |
| Failure flash | SwiftUI white rectangle over the **top 50% of the screen only**: 85% opacity for 2 frames, then a 120 ms fade, ≤ 3 Hz (bible). |
| Specular sparkle (golden, glass) | 4-point star sprite, 0.012 m, scale-pulses 0 → 1 → 0 over 300 ms, max 3 at once. |
| Heat/strain | Tint the platen's `emissiveColor` toward `#FF6A00` at intensity 0 → 0.15 in the last 8% before failure (the "it's working hard" read). |
| Colour grading | Done in the HDRI (warm key, cool fill), the sweep texture and the palette. Nothing at runtime. |

---

## 4. The press redesign ("Squish P-48")

A chunky **benchtop H-frame hydraulic press** with vinyl-toy proportions. It acts as a proscenium around the object: the columns at ~20%/80% of the frame width, the crown above and the bed below frame the stage like a picture frame.

### 4.1 Parts and dimensions (metres; y is the top or bottom of each part)

| Part | Shape | Size (w × h × d) | Position | Bevel radius | Material |
|---|---|---|---|---|---|
| **Feet** ×4 | cylinder | Ø 0.020 × 0.008 | x ±0.090, z ±0.055, y −0.108…−0.100 | 0.002 | rubber |
| **Bed** | rounded box | 0.220 × 0.065 × 0.150 | y −0.100…−0.035, z 0 | **0.012** | graphite enamel |
| Bed top inset line | box | 0.214 × 0.002 × 0.144 | y −0.0355 | 0.001 | steel (a thin bright line where the bed meets the bolster seat) |
| **Anvil (bolster)** | rounded box | **0.150 × 0.035 × 0.110** | y −0.035…0.000, z 0 | 0.004 (top edges get a 1.5 mm chamfer) | brushed steel |
| Anvil bolts ×4 | hex prism (extruded hexagon path, chamfer 0.0008) | Ø 0.010 × 0.004 | on the anvil's corners, inset 0.012 | 0.0008 | chrome |
| **Columns** ×2 | cylinder | Ø **0.022** | x ±0.093, z −0.020, y −0.035…0.330 | ends hidden in collars | mirror chrome |
| Column collars ×4 | cylinder | Ø 0.034 × 0.014 | at the bed (y −0.035…−0.021) and crown (y 0.316…0.330) | 0.004 | yellow enamel |
| **Crown** | rounded box | **0.220 × 0.070 × 0.120** | y 0.330…0.400, z −0.010 | **0.012** | yellow enamel |
| Crown front panel | rounded box | 0.190 × 0.052 × 0.004 | proud of the crown front face (z = +0.052), centred y 0.365 | 0.003 | graphite enamel (the instrument panel) |
| **Gauge** | see §4.4 | Ø 0.052 bezel | x −0.052, y 0.365, on the panel | | |
| Lamps ×2 | hemisphere | Ø 0.014 | x +0.040 and +0.066, y 0.373 | | lamp glass |
| Nameplate | rounded box | 0.048 × 0.012 × 0.002 | x +0.053, y 0.354 | 0.001 | brushed steel + engraved texture "P-48" (SF Mono Bold) |
| **Cylinder barrel** | cylinder | Ø 0.060 × 0.060 | y 0.270…0.330, z −0.010 | rim 0.004 (a 2 mm torus lip at the bottom) | graphite enamel |
| **Rod** | cylinder | Ø **0.030** | from the barrel bottom (0.270) to the platen top; length = 0.270 − platenTop | | mirror chrome |
| **Platen (moving crosshead)** | rounded box | **0.210 × 0.042 × 0.095** | home: bottom face of the plate at y **0.205** | **0.010** | yellow enamel |
| Platen collars ×2 | cylinder (visually wraps the columns) | Ø 0.036 × 0.046 | x ±0.093, centred on the platen | 0.005 | yellow enamel |
| **Hazard band** (the only one) | decal plane on the platen front | 0.150 × 0.010 | lower lip of the platen front face, 0.3 mm proud | — | hazard texture |
| **Press plate** | rounded box | **0.130 × 0.012 × 0.090** | under the platen; its bottom face is the press face | 0.003 | brushed steel |

**Kinematics.** `platenFace(y) = home (0.205) → object contact height → final crush height` (engine-driven).
- The platen, plate, collars and hazard band move together.
- The rod's length and position are recomputed each frame (scale.y of a unit cylinder, with the pivot at the top).
- The columns, crown, barrel and bed never move.

### 4.2 Silhouettes

```
FRONT (camera view, preset P)                        SIDE (from +X)

  9% ┌──────────────────────────────────┐ y .400        ┌──────────┐ crown
     │ ┌──────────────────────────────┐ │               │          │ (panel proud at front)
     │ │ ( GAUGE )    ● ●  [P-48]     │ │ crown         │         ▐│
 22% └─┴──┬───────────┬─────┬─────┬───┴─┘ y .330        └──┬────┬──┘
          ║          ┌┴─────┴┐    ║        barrel Ø60     ║  ┌─┴─┐ barrel
          ║          └──┬─┬──┘    ║        y .270         ║  └┬─┬┘
          ║             │ │  rod Ø30 chrome (extends)     ║   │ │ rod
 34% ┌────╫─────────────┴─┴─────────╫────┐ platen top    ║ ┌─┴─┴─┐ platen
     │   (O)      yellow enamel      (O)  │ .259           ║ │     │
     │    ////////////////////////////    │ hazard band    ║ │    ▐│ hazard (front lip)
 43% └────╫─[======= steel plate =====]─╫─┘ face .205     ║ └[===]┘ plate
          ║                             ║                 ║
          ║          .-"""-.            ║                 ║   ( obj )
  60%     ║         ( OBJECT )          ║  stage          ║  _(_____)_ anvil
  74%     ║   ┌─────────────────────┐   ║ anvil top .000  ║ |_________|
          ║   │ ═ brushed steel ═   │   ║                 ║ |         |
 86% ┌────╨───┴─────────────────────┴───╨────┐ bed top   ┌─┴─────────┴─┐ bed
     │      [ keycap UI console band ]       │          │             │
 95% └───▄▄──────────────────────────────▄▄──┘ feet      └─▄▄───────▄▄─┘
     ~~~~~~~~~~~~~ cream sweep floor + soft shadow ~~~~~~~~~~~~~~~~~~~~
  ↑ cream margin ≥ 5% each side at crown and bed rows; columns at ~20% / 80% of width
```

### 4.3 Materials (exact `PhysicallyBasedMaterial` values)

| Material | baseColor (sRGB) | metallic | roughness | clearcoat | clearcoatRoughness | specular | Other |
|---|---|---|---|---|---|---|---|
| **Yellow enamel** | `#F5A915` [tune → render ≈ `#FFB81C` lit] | 0 | 0.40 | **0.70** | 0.10 | 0.5 | Strain tint via emissive (§3.7) |
| **Graphite enamel** | `#34373D` | 0 | 0.45 | 0.35 | 0.18 | 0.5 | Must render ≥ L 45 on lit faces |
| **Mirror chrome** (columns, rod, bolts, bezel) | `#EDEEF0` | 1 | **0.06** | 0 | — | — | Shows the HDRI strips as crisp vertical lines |
| **Brushed steel** (anvil, plate, nameplate) | `#BFC3C8` | 1 | **0.30** | 0 | — | — | Optional 512² roughness texture: horizontal streak noise (±0.06) |
| **Rubber** (feet) | `#25262A` | 0 | 0.85 | 0 | — | 0.3 | |
| **Lamp glass, off** | `#6B6E75` | 0 | 0.15 | 1.0 | 0.05 | 0.6 | |
| **Lamp on** | green `#39D98A` / amber `#FFB81C` / red `#FF3B4E` | 0 | 0.15 | 1.0 | 0.05 | | `emissiveColor` = same colour, `emissiveIntensity` 2.0, plus a glow sprite |
| **Gauge glass** | `#FFFFFF` | 0 | 0.02 | 1.0 | 0.0 | 1.0 | `blending .transparent(opacity: 0.10)` plus an unlit highlight crescent decal (white, alpha 0.55) at the top-left |
| **Hazard band** | texture: 45° stripes, 8 mm stripe width, `#FFB81C` / `#2B2D31`, 1024×64 | 0 | 0.45 | 0.6 | 0.12 | | |

No base colour may be pure black or pure white. The darkest allowed is `#25262A`; the brightest is `#F8F8F8` (metals excepted).

### 4.4 The gauge dial (the press's face)

- **Bezel:** a chrome torus (lathe ring), outer Ø 0.052, tube Ø 0.005, 0.008 proud.
- **Face:** disc Ø 0.044, 512² CoreGraphics texture.
  - Paper `#FBF8F1` with a faint radial vignette (edge −4%).
  - Outer ring: graphite, 6 px.
  - **Sweep of 270°**, from 225° (lower-left, 0 TONS) clockwise to 315° (lower-right, 60 TONS).
  - Major ticks every 10 t: 18 px × 5 px graphite.
  - Minor ticks every 2 t: 9 px × 2 px, `#5E6067`.
  - **Red zone 48–60 t:** a 14 px arc in stamp red `#D7263D`.
  - Numerals 0, 10, …, 60: SF Pro Rounded Heavy 40 px graphite, placed at radius 0.70.
  - "TONS": SF Mono Semibold 22 px `#5E6067`, centred at 0.35 below the hub.
  - "SQUISH": SF Pro Rounded Black 18 px `#85878D`, above the hub.
- **Needle:** a tapered extruded path, 0.021 m tip and 0.006 m tail, stamp red PBR (roughness 0.3, clearcoat 1).
  - Hub: a chrome dome, Ø 0.007.
  - Angle: θ = 225° − 270°·(tons/60).
  - Driven by a spring (response 0.18 s, damping 0.55) toward the engine's current tonnage.
  - **Tremor ±0.8° at 14 Hz** during the tell phase.
  - At failure it overshoots 8% and settles.
  - The Unsquishable pins it into the red zone and buzzes.
- **Glass:** a sphere cap (radius 0.05, cap height 0.004) over the face, with the highlight crescent.

### 4.5 Lamps
- **Left lamp:** green "READY", on when idle.
- **Right lamp:** amber "LOAD", on from contact.
- The right lamp turns **red** for 600 ms at failure, then goes back to amber.
- For The Unsquishable, red blinks at 2 Hz (≤ 3 Hz) until the reveal.
- On/off transitions take 80 ms.

### 4.6 States

| State | Platen and rod | Gauge | Lamps | Decals and other |
|---|---|---|---|---|
| **Rest / idle** | Face at 0.205 (≈ 43% height); rod shows as a 10 mm chrome ring | Needle at 0, with a 0.3° idle breathing wobble (0.4 Hz) | green on | Object AO and soft shadow at full; ram occlusion 0 |
| **Approach** | Descends with the hand; chrome rod lengthens (the progress cue); hazard band enters the stage | Twitches ±1° with speed | green | Ram occlusion decal alpha ramps toward 0.30 |
| **Contact** | Face on the object top | +2 t kick | amber on, green off | One-frame object highlight (+15% emissive, 1 frame); 40 ms object hit-stop |
| **Strain** | Hand-driven; ±0.3 mm local jitter on the plate only (never the frame) | Climbs, ticking every 5° (bible §3.1) | amber | Object bulges; platen strain tint ramps in the last 8% |
| **Failure** | Continues with the hand (never frozen) | Overshoot, then settles | red 600 ms | Top-half white flash; debris at 0.3× for 250 ms |
| **Crushed / sealed** | At the final depth | Holds the peak, with an orange "peak" tick mark left at the max | amber | Spread meshes plus mess AO |
| **Reveal** | Lifts to home: spring (response 0.45, damping 0.80) after a 100 ms "stick" (gooey objects stretch 2–4 cheese-pull strands: cylinders Ø 2 mm, the object's colour, thinning and snapping at 40% of the lift) | Falls to 0 with a spring | green | Card drops into the top band (§6.8) |
| **Next object** | Home | 0 | green | Mess clears: debris slides back off the anvil (+Z → −Z, 0.35 s ease-in) and drops behind it; the next object drops in from 0.06 m above with squash (§6.9) |

**The Unsquishable: the press loses.** The ball never deforms.
- **Strain:** the platen stops 1 mm above the ball's apex plus its contact. The gauge goes past 60, the needle buzzes at the pin, both lamps go red and blink, and a white steam puff (6 soft sprites, alpha 0.4, rising 0.04 m over 0.8 s) leaks from the barrel's bottom lip.
- **The break (at failure):**
  1. The **press plate cracks.** A jagged crack-line decal (`#25262A`, 1.5 mm wide, 3 branches, seeded) appears on the plate's front edge.
  2. The **anvil gets a dent decal.** It's PBR, not unlit: a radial normal-like shading texture, darker ring plus a bright inner rim, Ø 0.05, under the ball.
  3. The platen tilts 2.5° about Z, staying bent until Next.
  4. One hex bolt pops off as rigid debris, bounces twice and rolls off.
  5. A **crack decal on the gauge glass** (3 white lines, alpha 0.7).
- **On reopen:** a pristine, shiny ball sits in a dented anvil, and the card reads "PRESS 0 – BALL 1".
- **Persistence:** after the first Unsquishable, a small **yellow repair patch sticker** (rounded rectangle 0.03 × 0.015, rotated 12°, with a white "X" stitch texture) appears on the crown's right side and stays forever. It's a collectible scar.
- The dent and crack reset on Next.

---

## 5. Object art bible

**Shared rules**
- **Hero scale:** every object's on-screen footprint is **0.09–0.12 m**, i.e. 30–48% of the frame width in preset P. Real-world scale is ignored.
- The object sits centred on the 0.150 × 0.110 anvil, with yaw as listed.
- **Every mesh has ≥ 1.5 mm of rounding on every edge.**
- Smooth unions for SDF blobs: k = 4–12 mm.
- **No faces except the duck.**
- **Mess** is always in the object's colour family and *more* saturated than the shell.
- Forbidden: dark reds (hue 345–15° with L < 45%), browns other than egg-shell flecks, and clustered small holes.
- **Fake SSS (iOS 18 path) for translucent candy.** A two-layer build:
  - an outer shell with `blending .transparent(opacity: 0.82–0.90)`, roughness 0.08–0.18, clearcoat 0.6–1.0
  - plus an **opaque inner core** (the same mesh scaled 0.82, darker colour)
  - plus `emissiveColor` = the light tint at intensity 0.15–0.25
  - "glows where thin": raise emissive intensity ×(1 + 1.5·compression)
- On iOS 27, `subsurfaceWeight`/`subsurfaceColor` may replace the core, behind `#available` (verify in CI first).
- Transparent sorting: give the shell and core separate entities. The core renders first; if the shells sort wrongly in CI, use `ModelSortGroupComponent` (not verified for iOS here; check `#available` before relying on it).

**Gold variant (1/50, any object):**
- PBR baseColor `#F2C250`, metallic **1.0**, roughness **0.16**, clearcoat 1.0, clearcoatRoughness 0.04.
- Applies to the main body. Eyes, wick and label print keep their colours; the label print becomes `#8A5A00`.
- Gold mess: spreads use `#F7D36B` (metallic 0.6, roughness 0.2), and debris gets 12% gold-glitter quads (0.003 m, emissive 0.4).
- Idle: 1 sparkle every 1.2–2.0 s (seeded), plus the gel wall becomes cream `#F3E6C4`.
- On the card: a gold foil border.

**Lathe convention:** profile points are (r, y) in metres, revolved about Y with 64 radial segments, normals from finite differences, and the first and last points closed with caps. "Lying" objects are lathed about their local axis and then rolled 90° about Z.

### 5.1 Bubble Wrap (onboarding hero)
- **Silhouette:** a square sheet with a 6 × 6 grid of domes and softly curled corners.
- **Size:** sheet 0.110 × 0.110 × 0.0008 film, corner radius 0.006. Domes: base radius 0.0075, height 0.0070, pitch 0.0175, grid inset 0.011. Yaw **12°**. Two seeded corners lift 2–4 mm (sheet displacement = smoothstep from the corner). Whole sheet wave: amplitude 0.0012, wavelength 0.08.
- **Colours and material:**
  - Film: `#E4F3FA`, transparent opacity 0.55, roughness 0.10, clearcoat 1.0, clearcoatRoughness 0.04, specular 0.7.
  - Domes: `#D8EEF8` at opacity 0.42, same gloss; the HDRI gives each dome a crisp key and top-strip highlight (the read).
  - Inner dome rim: a thin unlit ring decal `#FFFFFF` at alpha 0.25 (fakes thickness).
- **Build:**
  - Sheet: a 64 × 64 grid mesh.
  - Domes: one shared scaled-hemisphere mesh (24 × 12) instanced 36× as child entities.
  - The rare mega bubble: one dome at 2.2× radius replacing 4 cells.
- **Flattened:**
  - Each popped dome becomes a crinkled disc: scale y 0.08, 8 seeded vertex jitters ±0.6 mm, and opacity rises to 0.70 (stress-whitening) with base `#F0F7FB`.
  - The sheet ends flat with soft creases.
  - Never draw holes.
- **Mess:** none. Per pop, a white ring decal grows from r to 1.6r over 120 ms (alpha 0.35 → 0) plus 2 film flecks (0.003 m triangles, alpha 0.5).

### 5.2 Rubber Duck (the only face)
- **Silhouette:** the classic bath duck, seen 3/4, beak toward camera-right. **Yaw −30°** (+X is forward).
- **Size:** 0.102 L × 0.064 W × 0.085 H. On-screen width ≈ 0.12 m (40%).
- **SDF build** (smooth union, k = 0.008 unless noted; flat base: intersect with y ≥ 0.002, with a 2 mm round):

| Part | Centre | Radii / r |
|---|---|---|
| Body ellipsoid | (0, 0.026, 0) | (0.038, 0.026, 0.029) |
| Chest sphere | (0.019, 0.029, 0) | 0.021 |
| Tail ellipsoid (pitched +35°) | (−0.032, 0.038, 0) | (0.014, 0.017, 0.015) |
| Head sphere (k 0.010 into body = neck) | (0.020, 0.062, 0) | 0.023 |
| Wings ×2 (yaw ±10°, pitch −15°, k 0.004) | (−0.002, 0.030, ±0.026) | (0.020, 0.011, 0.006) |

  Marching cubes at 1.5 mm voxels (~8–12k tris), then 1 pass of Laplacian smoothing.
- **Beak:** a separate mesh. Upper ellipsoid at (0.044, 0.058, 0), radii (0.012, 0.0042, 0.009); lower at (0.041, 0.0525, 0), radii (0.009, 0.003, 0.0075); smooth union k 0.003. Colour `#FF8A1F`, roughness 0.30, clearcoat 0.8.
- **Eyes:** spheres r 0.0034 at (0.035, 0.068, ±0.012), sunk 30% into the head. Colour `#1E1B24`, roughness **0.04**, clearcoat 1.0. Both must show a white IBL highlight (check this).
- **Body material:** `#FFD23F`, roughness 0.28, clearcoat 0.8, clearcoatRoughness 0.10, specular 0.5. Faint warm emissive `#FFB000` at 0.04, so the shadow side stays saturated (target shadow side ≈ `#E0A626`, never olive).
- **Flattened:** a cartoon pancake.
  - y scale → 0.18, XZ × 1/√0.18 (clamped to Ø 0.15); features stretch (eyes become ovals); a rim bulge of +4 mm.
  - Springs back with overshoot on reopen (bible).
  - Never torn.
- **Mess:** none. A squeak "air puff" ring decal (white, alpha 0.3) at the beak.

### 5.3 Jelly
- **Silhouette:** a fluted mould jelly, upright.
- **Size:** Ø 0.098 × 0.0765 H.
- **Lathe profile r₀(y):**
  `(0.000,0.000) (0.044,0.000) (0.048,0.003) (0.049,0.008) (0.047,0.020) (0.044,0.035) (0.041,0.048) (0.038,0.058) (0.033,0.066) (0.024,0.072) (0.012,0.0755) (0.000,0.0765)`
  **Flutes:** r(y, θ) = r₀(y)·(1 + 0.07·cos 8θ · f(y)), with f = 1 below y 0.060, fading to 0 at the apex.
- **Material:**
  - Shell: `#E8336F`, opacity 0.86, roughness 0.08, clearcoat 1.0, clearcoatRoughness 0.03; emissive `#FF5A8A` at 0.22.
  - Core (scale 0.82): `#B81E52`, opaque, roughness 0.3.
  - Surprise fruit: 3–5 rounded cubes, 0.010 m, `#FFB81C` / `#8BD448`, between the core and shell.
- **Idle:** wobble springs (ζ 0.25), top lean ±1.5° at 1.8 Hz after landing.
- **Flattened:** a glossy spread disc (LowLevelMesh) up to Ø 0.150, 4 mm thick, with a seeded noisy rim (8 harmonics, ±12%) plus 6–10 "splort" blobs (flattened spheres, Ø 0.012–0.022) out at the sides. Material as the shell at opacity 0.92. Mess AO underneath.
- **Mess colours:** `#E8336F`, `#F0487A` (droplets); fruit stays its colour.

### 5.4 Crayon
- **Silhouette:** a chunky toddler crayon lying on its side, tip toward the front-right. **Yaw 20°**.
- **Size:** 0.113 L × Ø 0.022.
- **Lathe profile** (along the local axis, then rolled 90°):
  `(0.000,0.000) (0.0095,0.000) (0.0110,0.0015) (0.0110,0.0880) (0.0045,0.1050) (0.0025,0.1090) (0.0010,0.1120) (0.000,0.1130)`
  (Points are (r, axial position).)
- **Wrapper:** an open tube, r 0.0114, from 0.008 to 0.078 along the axis. `faceCulling .none`, paper `#F4ECDD`, roughness 0.75. Its CoreGraphics texture has a cobalt wave band, two thin stripes and a fictional wordmark "WAXO" (SF Pro Rounded Black, white on cobalt).
- **Wax:** `#2F5BEA`, roughness 0.52, `sheen` `#9DB3FF`, clearcoat 0.
- **Surprise core:** a cross-section disc at each snap plane in raspberry `#E8336F` (r 0.005).
- **Build:** pre-sliced at 2 seeded planes into 3 pieces (each a separate lathe segment with capped ends).
- **Flattened:** pieces flatten into waxy smears. Each is an extruded rounded-blob path (`MeshResource(extruding:)`, depth 0.002, chamfer 0.0008) 1.6× the piece's length, with streak texture lighter toward the edges (`#6F8EF2`). The wrapper becomes a crinkled paper strip.
- **Mess:** wax flakes (flat chips 2–4 mm) in `#2F5BEA` / `#6F8EF2`, which persist.

### 5.5 Egg
- **Silhouette:** an egg lying on its side, blunt end camera-left. **Yaw 20°**, roll 4°.
- **Size:** 0.110 L × Ø 0.080.
- **Lathe profile** (r, axial position from the blunt end):
  `(0.000,0.000) (0.017,0.004) (0.026,0.010) (0.034,0.020) (0.0385,0.032) (0.0400,0.044) (0.0395,0.056) (0.0370,0.068) (0.0320,0.080) (0.0255,0.090) (0.0180,0.098) (0.0105,0.104) (0.0045,0.108) (0.000,0.110)`
- **Shell:** `#EFD3A0`, roughness 0.60, clearcoat 0.15, specular 0.5. Optional 8–12 *sparse* flecks (`#D8B47C`, ≥ 6 mm apart, Ø 1–2 mm).
- **Inner membrane:** `#FFF9EE`.
- **Crack decals:** jagged lines `#8A6A3E`, 0.8 mm, growing from the contact point.
- **Build:** plane-slice into 10–14 shell shards (seeded convex cuts, each with a thickness of 1.2 mm and the inner face in membrane colour).
- **Flattened:**
  - Yolk: a domed spread, `#FFB000`, roughness 0.12, clearcoat 1, emissive `#FFC233` at 0.15, Ø 0.05, dome 6 mm.
  - Albumen: `#FFFFFF`, opacity 0.45, roughness 0.05, Ø up to 0.13, noisy rim, 2 mm.
  - Shards rest on top.
- **Surprise:** 1/8 a toy chick (sphere r 0.012 `#FFD23F`, cone beak `#FF8A1F`, no eyes) pops out unharmed; a rare double yolk.
- **Mess colours:** `#FFB000`, `#FFC233`, shell `#EFD3A0` / `#FFF9EE`.

### 5.6 Cake Slice
- **Silhouette:** a layered wedge, apex pointing camera-left-front, with one candle.
- **Size:** wedge angle 40°, radius 0.110, height 0.065. Centroid (0.072 from the apex) at the anvil centre; yaw so the apex points along world direction (−0.80, 0, +0.60), i.e. toward camera-left-front. On-screen width ≈ 0.10 m.
- **Build:** a stack of `MeshResource(extruding: wedgePath, extrusionOptions:)`. The path is a 40° sector with 3 mm corner rounds, extruded vertically (rotate the result −90° about X), `chamferRadius` 0.002, `chamferMode .both`.

| Layer | Thickness | Colour | Material |
|---|---|---|---|
| Sponge (bottom) | 0.022 | `#F4D9A8` | roughness 0.85 + soft mottling texture (low-contrast, non-clustered value noise ±4%) |
| Jam | 0.005 | `#E0335A` | roughness 0.15, clearcoat 0.8 |
| Sponge | 0.022 | `#F4D9A8` | as above |
| Cream top | 0.008 | `#FFF3F7` | roughness 0.35, clearcoat 0.3 |
| Back frosting (on the arc face, 0.004 proud, full height) | 0.004 | `#F59BB5` | roughness 0.35, clearcoat 0.3; with a 5-scallop drip edge at the top |

- **Candle:** cylinder r 0.0035 × h 0.038, pink/white spiral-stripe texture; wick 0.004 `#34373D`.
  - Flame: a teardrop (sphere scaled 0.004 × 0.008), `UnlitMaterial` `#FFC94A`, plus a glow sprite Ø 0.03 at alpha 0.3.
  - Flicker: scale ±6% at 7 Hz noise.
- **Sprinkles:** 14 rounded capsules (0.007 × 0.0018 × 0.0018) on the cream top, seeded yaw, colours `#E8336F #8BD448 #2F5BEA #FFD23F #FFFFFF`.
- **Flattened:**
  - Layers squash analytically.
  - Cream and frosting ooze out as 5–7 pink and white spread blobs at the sides.
  - Jam spreads as a thin disc segment.
  - Sprinkles burst (rigid, seeded), land and **stay**.
  - The candle bends 60° and then lies flat; the flame goes out with a 4-sprite smoke puff (`#FFFFFF` alpha 0.25).
- **Mess:** crumbs (rounded cubes 2–4 mm, `#E9C48A` / `#F4D9A8`) that persist.

### 5.7 Soda Can
- **Silhouette:** a fat upright "tallboy", fictional brand.
- **Size:** Ø 0.090 × 0.150 H.
- **Lathe profile:**
  `(0.000,0.008) (0.018,0.0065) (0.028,0.002) (0.030,0.000) (0.039,0.0015) (0.043,0.005) (0.045,0.011) (0.045,0.126) (0.043,0.134) (0.0385,0.142) (0.036,0.146) (0.0368,0.148) (0.036,0.150) (0.0345,0.149) (0.0335,0.1455) (0.000,0.1455)`
- **Materials:**
  - Body: painted aluminium. Metallic 0.55, roughness 0.22, clearcoat 1.0, clearcoatRoughness 0.06, baseColor texture 1024 × 512:
    - lime `#8BD448` field
    - a white wave band
    - a fictional wordmark **"FIZZO"** (SF Pro Rounded Black, white, 2-colour drop line `#2F7A1E`)
    - 6–8 *large, sparse* white bubbles (Ø 4–9 mm, never clustered)
  - Lid, bottom and rim: bare aluminium, `#D7DBE0`, metallic 1, roughness 0.20.
  - Tab: a rounded extruded plate, 0.022 × 0.012 × 0.001, same aluminium.
- **Flattened:**
  - Five concertina buckle rings appear top-down (bible), with radial lobes alternating (diamond read).
  - Final puck: Ø ≤ 0.12, h 0.018, ridged.
  - Bare aluminium shows in the fold valleys (lerp the body texture to aluminium where the fold depth exceeds 60%).
- **Surprise:** a fizz geyser at puncture: 40–80 droplet sprites (stretched along velocity, `#E9F7D9`) plus 6 foam blobs (`#FFFFFF`, roughness 0.6), then a puddle disc `#C9EFA0` at opacity 0.6, roughness 0.05, Ø 0.14.
- **Fizz colour per seed:** lime / orange `#FFB347` / berry `#C77DFF`.

### 5.8 Gummy Bear (no face)
- **Silhouette:** a sitting bear, facing the camera. Yaw 10°.
- **Size:** 0.090 W × 0.107 H × 0.057 D.
- **SDF** (smooth union, k 0.008; flat base at y ≥ 0.002):

| Part | Centre | Radii / r |
|---|---|---|
| Body ellipsoid | (0, 0.034, 0) | (0.034, 0.034, 0.026) |
| Belly sphere | (0, 0.030, 0.008) | 0.026 |
| Head sphere | (0, 0.078, 0.002) | 0.025 |
| Ears ×2 | (±0.018, 0.098, 0) | 0.009 |
| Muzzle bump (no features) | (0, 0.072, 0.022) | 0.011 |
| Arms ×2 (roll ±25°) | (±0.034, 0.045, 0.006) | (0.011, 0.018, 0.011) |
| Legs ×2 | (±0.020, 0.012, 0.020) | (0.013, 0.012, 0.018) |

- **Material:**
  - Shell: `#FF5A4E`, opacity 0.88, roughness 0.20, clearcoat 0.6, clearcoatRoughness 0.28 (sugar haze), `sheen` `#FFD6CF`, emissive `#FF6B5A` at 0.15.
  - Core (scale 0.82): `#C8203A`, opaque.
- **Flattened:**
  - Splits at the seam into 2–3 lobes (pre-split SDF halves) that spread.
  - Thin areas glow (emissive up to 0.5).
  - Surprise rainbow cross-section: flat discs in `#FF5A4E` / `#FFB81C` / `#8BD448` / `#2F5BEA` stripes visible on the split faces.
- **Mess colours:** `#FF5A4E`, `#FF8A7F`.

### 5.9 Glass Bottle
- **Silhouette:** a sea-glass bottle lying on its side, neck camera-right. **Yaw 15°**.
- **Size:** 0.140 L × Ø 0.060.
- **Lathe profile** (r, axial position from the base):
  `(0.000,0.000) (0.026,0.0015) (0.0295,0.005) (0.030,0.010) (0.030,0.075) (0.0285,0.088) (0.023,0.100) (0.016,0.110) (0.0118,0.118) (0.0110,0.130) (0.0125,0.133) (0.0128,0.138) (0.0112,0.140) (0.0085,0.140)`
- **Material:**
  - Outer: `#5CC8B8`, opacity 0.32, roughness 0.04, clearcoat 1.0, specular 1.0.
  - Inner shell (the same mesh scaled 0.94, `faceCulling .front`): `#2E8F84` at opacity 0.22. This fakes thickness, so edges read darker teal.
  - The HDRI's two **rim strips** must read as two long bright lines along the bottle's length (check this).
- **Surprise:** a rolled message inside (cylinder r 0.008, length 0.06, `#F4ECDD`, tied with a red `#D7263D` thread).
- **Failure:** the biggest event.
  - ≤ 60 chunky shards (convex plane slices, chamfered, 1.5–3 mm thick) plus ≤ 200 small shards.
  - Glint sprites on 6 shards for 3–5 frames.
  - The message unrolls into confetti (40 paper quads in candy colours).
- **Settled shards:** shift to roughness 0.25 ("sea glass": soft, safe), forming a tidy pile on the anvil.
- **Mess colours:** `#5CC8B8`, `#8FE0D3`, confetti candy set.

### 5.10 The Unsquishable (steel ball bearing)
- **Size:** sphere Ø **0.090** (64 × 48 segments).
- **Material:** baseColor `#F2F3F5`, metallic 1.0, roughness **0.03**, no clearcoat.
- **Why it matters:** this is the **IBL showcase and the CI calibration object.** It must show the key softbox, the top strip, two dark flags, the front card and the cream floor as a crisp miniature studio.
- **Behaviour and visuals:** see §4.6. It never changes shape.
- **Its card:** "PRESS 0 – BALL 1", with the dented anvil in the top-down render.

---

## 6. UI visual language

### 6.1 Layout grid and bands (portrait preset P; % of screen height)

| Band | Allowed content | Notes |
|---|---|---|
| 0–6% | nothing (Dynamic Island / status area, hidden status bar) | |
| 6–44% | **Scene** (crown, gauge, platen). Overlays allowed **only** for the reveal card (§6.8), captions (22–42%, §6.10) and the failure flash (0–50%) | No buttons here except on the reveal card |
| **45–80%** | **STAGE: nothing. Ever.** No hints, no captions, no toasts, no buttons, no translucent panels | VoiceOver focus rings are the only exception |
| 80–86% | toasts (reveal only), one at a time | |
| 86–95% | **Console:** the object chip, Shelf handle, and reveal actions (Again / Share / Next) | Sits over the bed's front face, graphite, so keycaps read |
| 95–100% | home indicator; floor | |

- **Grid:** 8 pt (`Theme.s1…s7`). Side margins 16 pt (portrait), 24 pt (Duo / landscape).
- **Safe areas:** respected for all UI. The scene ignores them.
- **Landscape (preset L):** the console moves to the right 22% column (vertical stack, bottom-aligned), and the reveal card moves to the left 30% column.
- **Duo (preset D):** the bands are the same, measured on the full inner display. Nothing interactive goes in the 40 pt crease (`reservedRegions(kind: .division)`).
- **Remove:**
  - the top-right settings puck (Settings opens from the Shelf, per bible §5)
  - the "Drag down to press" hint and hand glyph
- **First-run teaching:** the bible's ghost arc on the hinge plus the gauge needle twitching. For Pinch Press (non-Duo), the platen itself pulses: 1.5% scale breathing plus a soft yellow glow sprite on the hazard band. **Teach through the machine, never with text in the stage.**

### 6.2 Colour tokens

Keep the existing `Theme` names and add the new ones.

| Token | Hex | Use |
|---|---|---|
| `backdrop` | `#F3EEE6` | sheet base and fallback |
| `paper` / `paperWarm` / `paperShade` / `paperEdge` | `#FBF8F1` / `#F4ECDD` / `#E5DCCB` / `#D9CEBA` | cards, album |
| `graphite` / `graphiteRaised` / `ink` | `#2B2D31` / `#3A3D43` / `#2B2D31` | text, dark keycaps |
| `inkSecondary` / `inkTertiary` | `#5E6067` / `#85878D` | |
| `yellow` / `yellowLip` / `yellowSoft` | `#FFB81C` / `#C98A00` / `#FFE3A1` | primary action, accents |
| `stamp` | `#D7263D` | stamp, red zone, needle |
| `gold` / `goldSoft` | `#C8921A` / `#F6E2A8` | golden variant |
| **new** `shadowInk` | `#3B2F25` | every shadow, in SwiftUI and the scene |
| **new** `console` / `consoleLip` | `#3A3D43` / `#1E2023` | dark keycaps on the console |
| **new** `lampGreen` / `lampRed` | `#39D98A` / `#FF3B4E` | |
| **new** `floorNear` / `floorPool` / `wallBase` | `#F1E9DC` / `#F8F3EA` / `#EDE5D8` | must equal the sweep texture |
| **new** `gel(kind)` | §3.4 table | the background behind the RealityView, the toast accent rail |

### 6.3 Typography scale (at the default Dynamic Type size)

| Role | Font | Size / line | Tracking | Case |
|---|---|---|---|---|
| Caption onomatopoeia | SF Pro Rounded **Black** | 40–64 (by event size) | −0.5 | UPPER |
| Display (card detail name) | SF Pro Rounded Heavy | 28 / 32 | 0 | Title |
| Headline (card compact name, sheet titles) | SF Pro Rounded Heavy | 20 / 24 | 0 | Title |
| Button | SF Pro Rounded Heavy | 17 | 0.2 | Title |
| Body | SF Pro Rounded Semibold | 17 / 22 | 0 | Sentence |
| Label (specimen data, chips) | SF Mono Medium | 12 / 16 | 0.6 | UPPER |
| Micro (stamp date, serial, gauge "TONS") | SF Mono Semibold | 10 / 12 | 1.0 | UPPER |
| Big number (cover "48 TONS") | SF Mono Bold | 28 | 0 | UPPER |

- Sheets support Dynamic Type up to AX3.
- Captions and stamp text are fixed-size and decorative; VoiceOver announces them.
- **No other fonts and no regular SF Pro.**

### 6.4 Elevation and shadow recipes (SwiftUI)

All shadows use `shadowInk`, never black.

| Level | Use | Recipe |
|---|---|---|
| E0 | inline | none |
| E1 | chips, keycaps at rest, stickers | `.shadow(color: shadowInk.opacity(0.18), radius: 0, y: 2)` + `.shadow(color: shadowInk.opacity(0.10), radius: 6, y: 3)` |
| E2 | cards in sheets | `.shadow(color: shadowInk.opacity(0.10), radius: 1, y: 1)` + `.shadow(color: shadowInk.opacity(0.16), radius: 14, y: 8)` |
| E3 | reveal card over the scene, toasts | `.shadow(color: shadowInk.opacity(0.22), radius: 24, y: 14)` + E1 |

**Top inner highlight** on every raised surface:
`.overlay(RoundedRectangle(...).strokeBorder(LinearGradient([.white.opacity(0.65), .clear], startPoint: .top, endPoint: .center), lineWidth: 1))`

Don't use `.ultraThinMaterial` or blur materials anywhere. They caused the milky panel in frame 05, and they read as generic.

### 6.5 Material language for surfaces
- **Paper:** `paper` fill plus a 256² CoreGraphics grain texture (luminance noise ±3%, tiled, `.opacity(0.5)`, `.blendMode(.multiply)`). Corners 22 (card) or 18 (slot).
- **Enamel keycaps:** solid fills with a lip (below). No gradients except the 1 pt highlight.
- **Graphite console:** the scene's bed shows through; UI adds nothing behind the keycaps.

### 6.6 Buttons: tactile keycaps

| Kind | Face | Lip (offset below) | Label | Height | Radius |
|---|---|---|---|---|---|
| Primary | `yellow` | `yellowLip`, 4 pt | `graphite`, Rounded Heavy 17 | 52 | 16 continuous |
| Secondary (light) | `paper` | `paperEdge`, 4 pt | `graphite` | 48 | 16 |
| Console (dark) | `console` | `consoleLip`, 4 pt | `paper` | 44 | 14 |
| Chip (object picker) | `paper` | `paperEdge`, 3 pt | Mono 12 + the object's tint dot (10 pt) | 36 | 18 (capsule) |

- **Construction:** `ZStack { lipShape.offset(y: lip); faceShape.offset(y: pressed ? lip - 1 : 0) }`. The label rides with the face.
- **Pressed state:**
  - The face drops lip − 1 pt and scales 0.985.
  - The E1 shadow radius halves.
  - Animate down with `.spring(response: 0.12, dampingFraction: 0.90)` and up with `.spring(response: 0.30, dampingFraction: 0.55)`.
  - `UIFeel.press()` on touch-down.
- **Disabled:** 45% opacity, no lip, no shadow.
- **Hit targets:** ≥ 44 pt.
- **Icons:** SF Symbols at `.semibold`, 0.9 × the label size, for *actions only* (arrow.counterclockwise, square.and.arrow.up, arrow.right, gearshape.fill). **Objects never get an SF Symbol.** No symbol depicts a rubber duck or bubble wrap, and a wrong glyph (run 1's bird) reads cheap. Objects are shown as a 10 pt tint dot plus the name, or as their real sticker thumbnail.

### 6.7 Sheets (Shelf, Settings, Card detail)
- `.presentationBackground(Theme.paper)` with the grain, `.presentationCornerRadius(28)`, visible drag indicator.
- **Header:** Rounded Heavy 22 title + Mono 12 subtitle ("7/10 PRESSED"), 20 pt top padding.
- **Sections:** `paperWarm` cards, E1, radius 18, 16 pt padding.
- **Detents:** Shelf `[.medium, .large]`; Settings `[.large]`; Detail `[.large]`.
- **Sheets never open during a press** (as today).

### 6.8 The specimen card (reveal and detail)
- **Format:** a 3:4 card, `paper` plus grain, radius 22, E3 over the scene.
- **Reveal size:** width = min(84% of the screen width, 340 pt), placed in the **6–44% band**.
- **Top (62% of the card height): the specimen render.**
  - A top-down **orthographic** render (`OrthographicCameraComponent`, looking −Y, `scale` = flattened footprint × 1.25) of the flattened object and its mess only.
  - Anvil and sweep hidden; transparent background; lit by the same IBL plus key.
  - Composited onto the paper with a soft drop shadow (`shadowInk` 0.18, radius 6, y 3).
  - Rendered at 2× the display size, saved as PNG.
- **Label block:**
  - Name: Rounded Heavy 20.
  - Data lines: Mono 12 `inkSecondary`. `CRUSHED AT 92° · 48 TONS` / `112 FRAGMENTS · Ø 7.4 CM`.
  - Serial: `№0042` Mono 10 right-aligned.
  - A 1 pt `paperEdge` hairline separates the render from the label.
- **PRESSED stamp:**
  - A double rounded-rect border (outer 2.5 pt, inner 1 pt, gap 2 pt) in `stamp`, with "PRESSED" in Rounded Black 20, tracking 2, and the date below in Mono 9.
  - Rotation seeded −9…+9°. Overall opacity 0.88.
  - **Ink texture:** mask with a 256² noise (alpha 0.75–1.0) so it reads printed, not vector.
  - Overlaps the render's lower-right corner by 20%.
- **Variants:**
  - **Golden:** border `AngularGradient(goldSoft → gold → goldSoft)` 3 pt, plus 2 sparkles.
  - **Perfect Squish:** a round seal (Ø 44, `yellow` with `yellowLip` ring, "PERFECT" Mono 8 around it).
  - **Unsquishable:** the stamp reads "PRESS 0 – BALL 1" in red, rotated −4°.
- **Choreography:**
  1. The ram lifts.
  2. After 100 ms the card drops from −60 pt with rotation −3° → 0, `.spring(response: 0.50, dampingFraction: 0.62)` (as today).
  3. At +350 ms the stamp falls: scale 1.6 → 1.0, `.spring(response: 0.22, dampingFraction: 0.50)`, with a haptic on contact.
  4. At +500 ms the actions rise 24 pt.
- **Collect:** the card shrinks into the Shelf handle (scale 0.3, anchor at the handle) over 0.45 s.

### 6.9 Shelf (sticker album)
- **Page:** `paper` with a faint 8 pt dot grid (`paperShade` at 40%, 1 pt dots).
- **Grid:** 2 columns (phone portrait), 5 (Duo / landscape). Slot aspect 3:4, gap 16.
- **Empty or locked slot:**
  - A recessed well: `paperShade` at 55%, plus an inner-shadow fake (a top 1.5 pt `shadowInk` 0.12 stroke gradient fading to clear by 30%), radius 18.
  - An **embossed silhouette** of the object: a filled shape in `paperShade` with a 1 pt white highlight offset (−0.5, −0.5) and a 1 pt `shadowInk` 0.15 offset (+0.5, +0.5).
  - A one-line hint in Mono 10 `inkTertiary`.
- **Filled slot:**
  - A **sticker**: the card thumbnail clipped to a rounded rect (14), with a 5 pt white die-cut border, E1 shadow and seeded rotation ±2.5°.
  - Newly placed stickers "peel" in: scale 1.15 → 1, rotation +8° → seeded, `.spring(response: 0.40, dampingFraction: 0.60)`, plus a tick haptic.
  - Golden stickers get the foil border.
- **Progress:** "7/10 PRESSED" Mono 12, plus a 6 pt rounded bar (`paperShade` track, `yellow` fill with `yellowLip` 1 pt bottom).
- **Tabs:** a segmented control styled as two chips (§6.6), not the system segmented control.

### 6.10 Captions (comic onomatopoeia)
- **Text:** Rounded Black, 40–64 pt (small pop 40, crack 52, failure 64).
- **Fill:** the object's tint (light objects use `yellow`).
- **Stroke:** **4 pt `graphite`**, made from 8 offset copies at 45° steps under the fill.
- **Hard shadow:** (0, 4) `graphite` 30%.
- **Placement:** rotation seeded −7…+7°; x seeded 25–75% of the width; y **22–42%** only.
- **Animation:**
  - In: scale 0.5 → 1.1 → 1.0, `.spring(response: 0.28, dampingFraction: 0.50)`.
  - Hold: 400 ms.
  - Out: 180 ms fade plus a 10 pt rise.
- **Limits:** max 2 on screen. Off by default; on automatically when the system SDH setting is on (bible).

### 6.11 Cover display (closed)
- **Background:** the graphite machine panel. A `LinearGradient` from `#3A3D43` (top) to `#2B2D31`, with a 1 pt top highlight (white 0.08) and 4 corner "screw" dots (chrome, 6 pt).
- **Sealed card:** a paper inset (radius 16) holding:
  - "PRESS SEALED" in Rounded Heavy 17 `graphite`
  - a mini gauge (72 pt, the same texture as §4.4, needle at the peak)
  - "48 TONS" in Mono Bold 28 `graphite`, with "TONS" in `inkSecondary`
  - "OPEN TO SEE" in Mono 11, breathing opacity 0.6 ↔ 1.0 at 1.2 s (static under Reduce Motion)
- **Idle cover:** a trophy row of the 3 latest stickers on paper, plus the object chip picker.

### 6.12 Motion specs (one table)

| Motion | Spec |
|---|---|
| Ram, platen, rod | hand-tied to `engine.renderDepth`; **no easing**; the spring is in the engine |
| Object landing | drop from +0.06 m, gravity 9.8 × 1.5; on contact squash y 0.85 / xz 1.08, then `spring(response 0.35, damping 0.45)`; 2 frames of anticipation stretch (y 1.06) before contact |
| Idle breathing | y ±0.6% at 0.35 Hz (jelly ±2% wobble, ζ 0.25) |
| Gauge needle | spring response 0.18, damping 0.55; tremor 14 Hz ±0.8° in the tell |
| Hit-stop | 40 ms at contact, 80–120 ms at failure (object and particles only) |
| Debris slow-mo | 0.3× for 250 ms after failure |
| Reveal ram lift | 100 ms stick, then spring response 0.45, damping 0.80 |
| Card pop | spring 0.50 / 0.62; stamp 0.22 / 0.50 |
| Keycap | down 0.12 / 0.90, up 0.30 / 0.55 |
| Sheet content stagger | 40 ms per row, `.smooth(duration: 0.30)` |
| Shelf handle hop | offset −10 pt, spring 0.35 / 0.45, once |
| Gel crossfade | 400 ms ease-in-out |
| Next object | debris slides off (0.35 s ease-in), then the object drops (as above) |

**Reduce Motion variants:**
- Every scale, rotation and offset animation becomes an opacity crossfade (0.20–0.25 s).
- No micro-shake, no needle tremor (the needle moves with a 0.15 s ease-out), no slow-mo, no camera push-in, no hop.
- The failure flash becomes a 35% white for 150 ms.
- The landing becomes a fade-in at rest.
- Captions fade only.
- The cover breathing is static.

### 6.13 Dark mode policy: **stay bright, always**
- The studio is a place, not a theme.
- The matte nano-texture display makes dark scenes milky.
- Screenshots and brand must be consistent.

Implementation:
- Set `UIUserInterfaceStyle = Light` in Info.plist and `.preferredColorScheme(.light)` at the root.
- *Smart Invert:* mark the scene view `.accessibilityIgnoresInvertColors(true)`.
- *Increase Contrast:* `inkSecondary` → `#4A4C52`, keycaps gain a 1 pt `graphite` 0.4 outline, and the sweep floor darkens 3% to lift object edges.
- The cover display is graphite by design (it's the outside of the machine), not because of dark mode.

---

## 7. Content checks per frame (what a critic looks for, by state)

| State | The frame must show |
|---|---|
| Idle | The whole press with margins; the object centred on the anvil with AO; green lamp; needle at 0; gel wall matching the object; console keycaps only |
| Approach (depth 0.10) | Platen in the 46–55% band; rod visibly longer than idle; ram occlusion darkening on the anvil |
| Strain (depth 0.5) | Object visibly squashed (≥ 15% height loss), with a bulge; amber lamp; needle ≥ 20 t; contact shadow under the plate |
| Failure (event frame) | Debris in the air; top-half flash (or its fade); needle overshoot; red lamp |
| Crushed | Spread mesh plus mess AO; platen at the final depth; peak tick on the gauge |
| Reveal | Ram ≥ 50% lifted; card fully in 6–44%; stamp; flattened object visible below; Next / Again / Share on the console |
| Unsquishable after | Pristine ball, dented anvil, cracked plate, bent platen, both lamps red / blinking |

---

## 8. Build order for the engineers (to reach 8/10 fastest)

1. Camera presets (§3.2) and the `calib` scenario (§3.5). **Fix the CI `depth=` scenario first** (§9.3).
2. Sweep mesh plus texture, unlit with no tone map (§3.4).
3. HDRI → `EnvironmentResource` → IBL component and receivers (§3.3). Pass the chrome-ball check.
4. Exposure calibration (grey and white cards), key and rim lights, shadow projection (§3.5).
5. The press rebuild (§4), with the gauge and lamps.
6. Decals and AO (§3.6).
7. Objects in this order: Duck, Bubble Wrap, Unsquishable, Jelly, Can, then the rest (§5).
8. UI: bands, keycaps, card, stamp (§6). Remove the stage hint and the puck.
9. The screenshot checklist runs on every CI build (§9).

---

## 9. Screenshot acceptance checklist

Measure on the raw CI PNG (preset P, 1206×2622) with a small script:
- Luminance L = 0.2126R + 0.7152G + 0.0722B on 0–255 sRGB.
- Sample every 4th pixel unless the check says otherwise.
- "Hard" checks must all pass to score ≥ 8.

### 9.1 Checks

| # | Check | Pass criterion | Hard? |
|---|---|---|---|
| **C1** | Object size | Object bounding box width = **30–48%** of the frame width; centre x within 50% ± 2% (except debris) | ✔ |
| **C2** | Object placement | Object fully inside the frame and the 45–80% band; contact line at **72–76%** height | ✔ |
| **C3** | Whole press visible | Crown top ≥ 4% from the top; bed bottom ≤ 97%; cream margin ≥ 5% of the width at both the crown row and the bed row | ✔ |
| **C4** | Ram home | Idle frames: platen face at 38–46% height | |
| **C5** | No slabs | No single-hue region (ΔE < 4) spans ≥ 98% of the width for > 3% of the height, sweep gradient excepted | ✔ |
| **T1** | No black | Pixels with L < 20: ≤ 0.5%. Pixels with L < 40: ≤ 2.0% | ✔ |
| **T2** | No clipping | Pixels with min(R,G,B) ≥ 250: ≤ 1.0%, and no clipped connected blob > 0.3% of the frame (speculars only) | ✔ |
| **T3** | Mid-key | Frame mean L 175–215; sweep samples at (4%, 30%), (4%, 60%), (50%, 98.5%) have L 210–248 | |
| **T4** | Sweep colour exact | The three sweep samples are within ΔE(OKLab) ≤ 3 of the §3.4 texture values for this object's gel | ✔ |
| **T5** | Hydraulic yellow | Crown front face (lit centre): HSV hue 38–44°, S ≥ 0.75, V 0.85–0.98 (amber, not lemon) | ✔ |
| **T6** | Hero saturation | The object's median saturation (HSV) ≥ the median of the rest of the frame + 0.20 (exempt: Bubble Wrap, Egg, Glass, Unsquishable, which must instead have the frame's highest local contrast) | |
| **T7** | No banding | In a 200 × 600 px wall crop, no visible stepped bands: row-mean luminance second differences stay below 1.0 over runs > 30 px | |
| **L1** | Three tones | Object lit side vs shadow side ΔL ≥ 30; shadow side L ≥ 45; crown, platen and bed each show top face ≠ front face (ΔL ≥ 12) | ✔ |
| **L2** | Metals read as metal | Each chrome column and the rod: within its width, max L ≥ 235 **and** min L ≤ 110 (a highlight streak plus a dark flag reflection). The anvil top shows a soft gradient ≥ 25 L across its depth | ✔ |
| **L3** | Grounded | A darker band under the object's contact line, ≥ 25 L darker than the anvil 10 px away, plus a soft shadow on the key-opposite (right/back) side; the bed shows a floor shadow | ✔ |
| **L4** | Specular on the hero | Glossy objects: ≥ 1 highlight with L ≥ 240, area 0.05–1.5% of the object. Matte objects (crayon wax, cake sponge): no highlight > 230 on those materials | |
| **L5** | Silhouette separation | Along ≥ 70% of the object outline, contrast vs the background behind is ≥ 1.5:1, or a rim highlight is present on the top-back edge | |
| **L6** | Bevels | Every visible press box edge shows a 1–4 px highlight line (bevel catch-light); no 1 px razor edges | |
| **U1** | Sacred stage | No UI layer pixel in the 45–80% band in idle, press, crushed or reveal frames (verify via a scene-only render diff or the view hierarchy dump) | ✔ |
| **U2** | Bands | Console UI within 86–95% (toasts 80–86%); reveal card within 6–44%; no UI at 0–6% | |
| **U3** | Contrast | Text ≥ 4.5:1 against the actual pixels behind it (≥ 3:1 for ≥ 18 pt bold or rounded heavy) | ✔ |
| **U4** | One primary | ≤ 1 yellow primary keycap per frame; all buttons are keycaps (§6.6); no translucent pills or blur materials | |
| **U5** | Type discipline | Only SF Pro Rounded (Semibold/Heavy/Black) and SF Mono; mono labels uppercase with tracking ≥ 0.5 | |
| **S1** | States differ | idle vs `depth=0.5` frames of the same object differ in ≥ 8% of the stage-band pixels; the platen in the depth-0.5 frame sits at 50–72% height | ✔ |
| **S2** | Reveal is a moment | Card fully visible; stamp present and within ΔE ≤ 6 of `#D7263D`; ram ≥ 50% lifted; flattened object visible below the card | ✔ |
| **S3** | No artefacts | No z-fighting stripes, no hard-edged translucent rectangles, no magenta or black missing textures, no seams or gaps between parts, no floating objects (≥ 1 px air gap at contact) | ✔ |
| **S4** | Candy-tidy mess | Debris pixels within ΔE ≤ 15 of the object's palette; no dark-red areas (hue 345–15° with L < 45%) > 0.2%; no clustered small-hole patterns | ✔ |

### 9.2 Scoring rubric (critic, per frame and per set)

Score = weighted sum, rounded to one decimal place:

| Dimension | Weight | 0 | 1 (full) |
|---|---|---|---|
| Composition (C1–C5) | 2.0 | cropped slabs, object not the hero | whole toy press, centred hero, breathing room, every hold-frame hangable |
| Light and material (L1–L6, T5) | 3.0 | default lighting, flat, black chrome | studio light: soft key, strip highlights, three tones, grounded, metals sparkle |
| Colour and tone (T1–T4, T6–T7) | 2.0 | grey or clipped, lemon yellow | warm mid-key, exact sweep, amber yellow, hero most saturated, no banding |
| UI (U1–U5) | 2.0 | hints on the stage, mixed button styles | invisible during the press; tactile keycaps; type discipline |
| Story and delight (S1–S4, §7) | 1.0 | states indistinguishable | each state readable at thumbnail size; the reveal feels like a reward |

| Score | Meaning |
|---|---|
| 1–2 | Debug render (run 1 scored **2**: composition 0.1, light 0.2, colour 0.3, UI 0.3, story 0.1) |
| 3–4 | Correct framing but flat or default lighting; reads "tech demo" |
| 5–6 | Coherent scene, but materials or exposure are off, or UI is inconsistent; reads "decent indie" |
| 7 | Good; one dimension clearly weaker; not yet feature-worthy |
| **8** | **Launchable.** All hard checks pass and ≥ 80% of the others do. A stranger shown the frame at thumbnail size can say "a toy press about to squish a duck". It could sit in an App Store "Fun with your new iPhone" story |
| 9 | Feature-worthy. Every state frame works as a store screenshot; materials are delightful in close-up |
| 10 | Apple-ad quality; no notes |

### 9.3 CI scenarios required each build
- `object=<each of 10>` (idle)
- `object=<k>;depth=0.10`, `depth=0.50`, `depth=0.95` for Duck, Bubble Wrap, Can and Glass
- `object=<k>;reveal` for Duck, Egg and Unsquishable
- `object=unsquishable;calib`
- `shelf`, `detail`, `cover=sealed`

**Bug to fix first:** run 1's `depth` frames equal the idle frames. `DemoMode` must drive `engine.renderDepth` / `visualCompression` and wait ≥ 3 frames before the capture.

### 9.4 Contact sheet ("colour script wall", the Monument Valley practice)

CI also emits `contact-sheet.png`: all frames at 25% scale in a grid, labelled. The critic scores the set for consistency:
- the same press pose at home
- the same light
- different gel walls
- a recognisable silhouette for each object

A set average ≥ 8.0 with no frame < 7 is the launch gate.

---

## Sources
- Apple RealityKit docs, read as `developer.apple.com/tutorials/data/documentation/realitykit/*.json` on 22 Oct 2026:
  - [EnvironmentResource](https://developer.apple.com/documentation/realitykit/environmentresource), [init(equirectangular:withName:)](https://developer.apple.com/documentation/realitykit/environmentresource/init(equirectangular:withname:)), [init(equirectangular:options:)](https://developer.apple.com/documentation/realitykit/environmentresource/init(equirectangular:options:)), [CreateOptions](https://developer.apple.com/documentation/realitykit/environmentresource/createoptions)
  - [ImageBasedLightComponent](https://developer.apple.com/documentation/realitykit/imagebasedlightcomponent), [ImageBasedLightReceiverComponent](https://developer.apple.com/documentation/realitykit/imagebasedlightreceivercomponent), [EnvironmentLightingConfigurationComponent](https://developer.apple.com/documentation/realitykit/environmentlightingconfigurationcomponent)
  - [RealityViewCameraContent](https://developer.apple.com/documentation/realitykit/realityviewcameracontent), [RealityViewEnvironment](https://developer.apple.com/documentation/realitykit/realityviewenvironment), [RealityViewRenderingEffects](https://developer.apple.com/documentation/realitykit/realityviewrenderingeffects)
  - [ARView.Environment](https://developer.apple.com/documentation/realitykit/arview/environment-swift.struct), [ARView.RenderOptions](https://developer.apple.com/documentation/realitykit/arview/renderoptions-swift.struct)
  - [GroundingShadowComponent](https://developer.apple.com/documentation/realitykit/groundingshadowcomponent), [DirectionalLightComponent.Shadow](https://developer.apple.com/documentation/realitykit/directionallightcomponent/shadow), [SpotLightComponent.Shadow.lightSize](https://developer.apple.com/documentation/realitykit/spotlightcomponent/shadow/lightsize), [DirectionalLightComponent.intensity](https://developer.apple.com/documentation/realitykit/directionallightcomponent/intensity)
  - [PerspectiveCameraComponent](https://developer.apple.com/documentation/realitykit/perspectivecameracomponent), [OrthographicCameraComponent](https://developer.apple.com/documentation/realitykit/orthographiccameracomponent)
  - [UnlitMaterial](https://developer.apple.com/documentation/realitykit/unlitmaterial), [PhysicallyBasedMaterial](https://developer.apple.com/documentation/realitykit/physicallybasedmaterial)
  - [MeshResource.init(extruding:extrusionOptions:)](https://developer.apple.com/documentation/realitykit/meshresource/init(extruding:extrusionoptions:)), [ShapeExtrusionOptions](https://developer.apple.com/documentation/realitykit/meshresource/shapeextrusionoptions)
- [Apple Developer Forums 761982: RealityView skybox vs lighting (split background and IBL)](https://developer.apple.com/forums/thread/761982)
- [Achraf Kassioui, Light & Shadow in RealityKit](https://www.achrafkassioui.com/blog/light-and-shadow-in-realitykit/)
- [Apple, Behind the Design: (Not Boring) Habits](https://developer.apple.com/news/?id=9ab1g4r3); [notbor.ing](https://notbor.ing/)
- [Apple, Behind the Design: Halide Mark II](https://developer.apple.com/news/?id=x6bv1a36); [Apple, Behind the Design: Flighty](https://developer.apple.com/news/?id=970ncww4)
- [GDC Vault, Designing Monument Valley](https://www.gdcvault.com/play/1020878/); [Creative Bloq, The making of Monument Valley](https://www.creativebloq.com/computer-arts/making-monument-valley-71412213)
- [Townscaper (Steam)](https://store.steampowered.com/app/1291340/Townscaper/)
- [Gustafsson, Cracking destruction (Smash Hit)](https://www.gamedeveloper.com/programming/cracking-destruction)
- [Game Developer, The methodical catharsis of tidying in A Little to the Left](https://www.gamedeveloper.com/design/the-methodical-catharsis-of-tidying-in-a-little-to-the-left)
- [Game Developer, Road to the IGF: Alto's Odyssey](https://www.gamedeveloper.com/business/road-to-the-igf-team-alto-s-i-alto-s-odyssey-i-)
- Product lighting practice (key:fill 2:1–4:1, key at 45° above product height, rim from behind, sweep backdrop): [Tov Studio guide](https://tovstudiophoto.com/product-photography-lighting-setup-guide/), [Points 3D, studio lighting for product renders](https://www.pointsbrighton.co.uk/how-to-set-up-studio-lighting-for-3d-product-renders-in-blender/), [Lightmap HDR Light Studio bottle tutorial](https://www.lightmap.co.uk/learning/blender-tutorial-01/)
- [WWDC23, Animate with springs (notes)](https://wwdcnotes.com/documentation/wwdc23-10158-animate-with-springs/)
- Genre comparables: [Squishy Magic](https://apps.apple.com/us/app/squishy-magic-asmr-toy-maker/id1490398089), [ASMR Squishy](https://apps.apple.com/us/app/asmr-squishy-antistress-toy/id1483419666)
