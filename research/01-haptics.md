# Squish: Haptics Research and Spec v0

*Research date: 22 Oct 2026, the day before iPhone Duo launches. Author: haptics research workstream.*
*Caveat on method: the shared web-search budget ran out partway through this research. The Apple documentation, the Duo facts and the academic sections are sourced. A few industry examples (DualSense, HD Rumble) and some perceptual rules of thumb come from prior knowledge, and those are marked **[unverified]**.*

---

## Key takeaways

1. **Use three layers on one engine.** (a) A looping continuous **"strain bed"** on a `CHHapticAdvancedPatternPlayer`, modulated live with `sendParameters`. (b) A **"grain" layer** of fire-and-forget transients, emitted per degree of hinge travel. (c) Pre-authored **AHAP "event" patterns** for contact, crack, burst and bottom-out. Apple's own samples use these exact building blocks ([HapticPalette](https://developer.apple.com/documentation/corehaptics/updating-continuous-and-transient-haptic-parameters-in-real-time.md), [HapticSampler](https://developer.apple.com/documentation/corehaptics/playing-a-custom-haptic-pattern-from-a-file.md)).
2. **Emit grains per degree of closing, not per unit of time.** This is the well-established "grain-based compliance illusion": short bursts fired per increment of force or displacement make a rigid device feel like it gives. The spacing between grains sets the perceived stiffness, and **stopping the grains reads as "it won't move any further"** ([Kildal 2010](https://ixdf.org/literature/author/johan-kildal); [PseudoBend, UIST 2019](https://koasas.kaist.ac.kr/handle/10203/272259?mode=full); [CHI 2025](https://dl.acm.org/doi/10.1145/3706598.3714225)). The hinge angle is our displacement signal.
3. **Grains alone feel buzzy.** Research found that adding a smooth sinusoidal base under the grains is "significantly less bumpy, less buzzing". This comes from the paper "Finding a More Pleasant Compliance Illusion Method for a Hand-Held Device", seen only as a search snippet **[full text not read]**. That supports pairing the bed with the grains: keep the bed low-sharpness and the grains high-sharpness so they don't blur together. Apple notes that "playing two haptic events of the same type at the same time makes them hard to tell apart" ([HapticSampler](https://developer.apple.com/documentation/corehaptics/playing-a-custom-haptic-pattern-from-a-file.md)).
4. **Design the bed with headroom.** `HapticIntensityControl` only *multiplies* (0–1). `HapticSharpnessControl` *adds* (−1 to +1) and affects only continuous events ([AHAP spec](https://developer.apple.com/documentation/corehaptics/representing-haptic-patterns-in-ahap-files.md)). So author the bed at intensity 1.0 and sharpness 0.5, then steer it down and sideways at runtime.
5. **Dynamic parameters jump; curves ramp.** `sendParameters` changes values "immediately", while `CHHapticParameterCurve` interpolates linearly ([Apple](https://developer.apple.com/documentation/corehaptics/chhapticparametercurve.md)). For a noisy hinge signal, send a short 2-point curve each display frame (about 30 ms) rather than raw steps. Raw steps are the main source of the "zipper buzz" feel.
6. **Treat the hinge as a slow, noisy, rate-unknown sensor.** Apple says the update rate and precision are system policy and shouldn't be relied on, and that you should animate *between* values ([bleepingswift](https://bleepingswift.com/blog/onhingechange-hinge-angle-swiftui), [Apple forums](https://developer.apple.com/forums/thread/847644)). Run every reading through a One-Euro filter, then a spring interpolator. Use at least 8° of hysteresis (accuracy is about 5°), and predict threshold crossings about 30 ms ahead.
7. **Put the climax where people can see it.** The failure moment must happen between roughly **60° and 30°**, while the inner display is still visible. Below about 25°, the experience is felt and heard only: post-failure crunch, bottom-out thunk, then the magnetic "clap" the hardware already makes ([Gizmodo](https://gizmodo.com/iphone-duo-review-2000827502)) as the app moves to the outer display.
8. **Sell force through contrast, not loudness.** Keep the strain bed at or below 0.7 intensity. Add a rising "strain tremor" and accelerating micro-cracks as tells. Then cut to **near silence for 40–60 ms before the break**, and fire the only 1.0-intensity events (failure, bottom-out). This follows Apple's causality/harmony/utility principles and its ramp-then-silence-then-answer example ([WWDC19 223](https://developer.apple.com/videos/play/wwdc2019/223/)).
9. **Expect no Duo-specific haptics data.** No review we found measured the Taptic Engine on iPhone Duo. It weighs 254 g, has titanium, a "variable torque profile" free-stop hinge and magnets ([Gizmodo](https://gizmodo.com/iphone-duo-review-2000827502)), so plan an on-device calibration pass: two-handed grip, half-closed, closed. The hinge's own physical torque is the *real* resistance the user feels, so align our strain peak with it.
10. **Settings behaviour is undocumented, so ship our own controls.** We could not confirm whether Core Haptics obeys **System Haptics** or Low Power Mode. Sources conflict, and Apple's docs are silent. Following the HIG ("Make haptics optional"), ship an in-app Haptics Off/Soft/Full control, a Sound control, and a non-hinge fallback such as a press slider (as [bleepingswift](https://bleepingswift.com/blog/onhingechange-hinge-angle-swiftui) also recommends). Test the Settings toggles on the device.

---

## 1. Core Haptics deep dive (what matters for Squish)

### 1.1 Objects and lifecycle
- **`CHHapticEngine`** is "the connection to the haptic server". The OS "could still override the request with system services, like haptics from system notifications" ([Apple](https://developer.apple.com/documentation/corehaptics/chhapticengine.md)). It isn't a singleton, and Core Haptics is thread-safe ([Preparing your app](https://developer.apple.com/documentation/corehaptics/preparing-your-app-to-play-haptics.md)).
- **Starting and stopping is expensive; players are cheap.** Apple: "Creating haptic pattern players is inexpensive… starting the haptic engine is expensive, as is stopping it, so start and stop the engine sparingly" ([HapticPalette](https://developer.apple.com/documentation/corehaptics/updating-continuous-and-transient-haptic-parameters-in-real-time.md)). Its sample fires a fresh transient player per tick "without lag".
- **`isAutoShutdownEnabled`** (default false) shuts the engine down "after approximately two minutes of inactivity" ([Apple](https://developer.apple.com/documentation/corehaptics/chhapticengine/isautoshutdownenabled.md)).
- **`stoppedHandler` reasons** are `audioSessionInterrupt`, `applicationSuspended`, `idleTimeout`, `notifyWhenFinished`, `engineDestroyed`, `gameControllerDisconnect` and `systemError` ([Apple](https://developer.apple.com/documentation/corehaptics/chhapticengine/stoppedreason.md)). It isn't called for your own `stop()`.
- **`resetHandler`** runs after the haptic server recovers. You must restart the engine, **re-register audio resources and recreate every player** ([Apple](https://developer.apple.com/documentation/corehaptics/preparing-your-app-to-play-haptics.md); [Kodeco](https://www.kodeco.com/10608020-getting-started-with-core-haptics?page=4)).
- **Folding doesn't suspend the app.** Folding and unfolding are size-class and trait changes, and "the process keeps running" ([Apple forums summary](https://developer.apple.com/forums/thread/847644)). So closing the Duo shouldn't trigger `applicationSuspended`. **Verify on the device** that the inner-to-outer scene move doesn't interrupt the audio session.

**Squish policy.**
- Create the engine at launch with `CHHapticEngine(audioSession: .sharedInstance())`, as Apple's sampler does.
- Set the handlers before `start()`.
- Keep the engine running while the Press scene is visible (auto-shutdown off).
- In Collection and Menu screens, stop it or let auto-shutdown handle it.
- Always call `try? engine.start()` before a press begins. That call is cheap if the engine is already running.

### 1.2 Events and parameters
- **Types:** `HapticTransient`, `HapticContinuous`, `AudioContinuous`, `AudioCustom` ([AHAP spec](https://developer.apple.com/documentation/corehaptics/representing-haptic-patterns-in-ahap-files.md)).
- **Event parameters (0–1):** `HapticIntensity`, `HapticSharpness`, `AttackTime`, `DecayTime`, `ReleaseTime`, `Sustained`. The values are normalised to the device's minimum and maximum ("1 doesn't indicate 1 second"). Out-of-range values are clamped.
- **Sharpness** runs from "round… organic" at 0 to "crisp, precise… mechanical" at 1 ([WWDC19 520](https://developer.apple.com/videos/play/wwdc2019/520/)). In practice it abstracts the actuator drive frequency. **[unverified]** The Taptic Engine is an LRA with a narrow useful band, so low sharpness reads as "thud or rumble" and high reads as "tick or buzz". Don't expect audio-like frequency control.
- **Continuous events are capped at 30 s** ([Exyte](https://exyte.com/blog/creating-haptic-feedback-with-core-haptics)). A bed for a long press needs `loopEnabled` on an advanced player, or a planned re-arm before 30 s.
- **Layering is automatic.** Fire-and-forget patterns layer on top of each other ([HapticSampler](https://developer.apple.com/documentation/corehaptics/playing-a-custom-haptic-pattern-from-a-file.md)). Apple doesn't document a maximum number of simultaneous players. **Our own budget: at most 1 bed + 1 event pattern + a grain stream (one live transient at a time).**

### 1.3 Real-time control
- **`CHHapticAdvancedPatternPlayer`** adds `loopEnabled`, `loopEnd`, `playbackRate`, `seek`, `pause`/`resume` and a completion handler ([Apple](https://developer.apple.com/documentation/corehaptics/chhapticadvancedpatternplayer.md)). Apple's HapticPalette uses a single 100 s-duration continuous event and drives it with `sendParameters` ([Apple](https://developer.apple.com/documentation/corehaptics/updating-continuous-and-transient-haptic-parameters-in-real-time.md)). Kodeco's "swish" does the same with a 60 s event ([Kodeco p4](https://www.kodeco.com/10608020-getting-started-with-core-haptics?page=4)). Treat those long durations with care given the reported 30 s cap; looping is the safe path.
- **How the control parameters combine with event values:**
  - `hapticIntensityControl` multiplies by 0–1: "The factor only reduces the pattern's intensity".
  - `hapticSharpnessControl` adds −1 to +1.
  - Envelope-time controls add.
  - `audioVolumeControl` multiplies.

  Source: [Apple](https://developer.apple.com/documentation/corehaptics/updating-continuous-and-transient-haptic-parameters-in-real-time.md).
- **Parameter curves** interpolate linearly and **apply to every event in the pattern**. You can't target one event ([Apple](https://developer.apple.com/documentation/corehaptics/chhapticparametercurve.md)). That is one more reason to give the bed its own player.
- **Latency:** Apple only says "minimal latency" and calls the API "designed for low latency and real-time modulation", with UIKit generators sharing the same path ([WWDC19 520](https://developer.apple.com/videos/play/wwdc2019/520/)). **No published figures exist.** Build a measurement harness: film at 240 fps with a contact mic on the chassis, and log `engine.currentTime` against hinge timestamps.

### 1.4 Audio-haptic sync
- **Apple's path for tight sync** is an `AudioCustom` event inside the same AHAP or pattern ([WWDC21 10278](https://developer.apple.com/videos/play/wwdc2021/10278/)). It plays the file once, like a transient ([Exyte](https://exyte.com/blog/creating-haptic-feedback-with-core-haptics)). Register files with `registerAudioResource`, which has loop and volume-envelope options ([Apple](https://developer.apple.com/documentation/corehaptics/chhapticengine/registeraudioresource(_:options:).md)). WWDC21's shield example shows the method: keep the preferred haptic and swap the audio file until they "match".
- **Separate `AVAudioEngine` audio** is needed for anything granular or pitch-shifted that tracks the hinge, such as a creak whose pitch follows strain or the hydraulic hum. WWDC19 says Core Haptics can synchronise with AVAudioEngine through scheduled absolute times ([WWDC19 520](https://developer.apple.com/videos/play/wwdc2019/520/)).
- **Known crash:** a forum thread reports crashes when `AudioCustom` players are created after an engine restart alongside an AVAudioEngine session ([forum 763640](https://developer.apple.com/forums/thread/763640)).
- **Recommendation:**
  - **One-shot event sounds** (snap, pop, shatter, thunk) go **inside the AHAP** as `AudioCustom`, giving sample-accurate sync.
  - **Continuous, hinge-tracking beds** (creak, hum, squelch loop) go in **AVAudioEngine**, driven by the *same* filtered signal object.
  - Re-register resources in `resetHandler`.
  - **[unverified]** Rule of thumb: keep audio-haptic skew under about 20 ms for impacts. People tolerate more for textures.
- **Recording:** haptics are muted while recording from audio input unless `allowHapticsAndSystemSoundsDuringRecording` is set (default false) ([Apple](https://developer.apple.com/documentation/avfaudio/avaudiosession/allowhapticsandsystemsoundsduringrecording.md)). This matters if we add "record my squish" with the mic.

---

## 2. Designing haptics for materials and destruction

### 2.1 Physics to borrow
- **Okamura's decaying-sinusoid model:** contact vibration is `A·e^(−Bt)·sin(2πft)`, with amplitude proportional to impact velocity. Rubber has low frequency (about 18 Hz) and a slow decay. Aluminium is high frequency (about 1 kHz) with a fast decay ([Okamura et al. 2001, via patent citation](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/12159550)). A separate study puts realistic **wood decay at 100–150 s⁻¹ and rubber or gelatin at 50–100 s⁻¹** ([patent 11397467](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/11397467)). Hand-tuned pulses scaled by impact velocity "resemble those experienced during real impacts" ([Kuchenbecker 2006](https://www.ncbi.nlm.nih.gov/pubmed/16509381)).
- **Mapping to the Taptic Engine.** We can't render a 1 kHz ring, so we encode material in three things:
  - **Sharpness:** metal and glass about 0.85–1.0, wood or wax about 0.6–0.75, rubber or goo about 0–0.2.
  - **Decay:** a short tail of 1–3 follow-up transients for metal or glass, or a continuous tail of 150–400 ms for goo.
  - **Grain density:** sparse for stiff materials, dense for crumbly ones.
- **Texture by grain stream.** Apple's WWDC21 rolling texture is about **100 transients in 2 s (about 50/s)**, looped, with intensity scaled by speed every frame ([WWDC21 10278](https://developer.apple.com/videos/play/wwdc2021/10278/)). That is the template for crunch and crinkle.
- **Grain parameters drive perception.** For grains tied to displacement, amplitude sets the strength of the texture, while granularity and timbre create distinct experiences (roughness, sharpness, bumpiness, adhesiveness) ([Strohmeier & Hornbæk, CHI 2017](https://www.kasperhornbaek.dk/papers/CHI2017_HapticTextures.pdf)).

### 2.2 Vocabulary of recipes (building blocks; values are Core Haptics 0–1)

| Feel | Construction | Key numbers |
|---|---|---|
| **Snap** (crayon, stick) | 1 transient, then a second at +10–15 ms, then a short dull tail | T 1.0/1.0, T 0.7/0.6 @12 ms, C 0.5/0.3 for 60 ms with decay |
| **Crack** (shell, micro-fracture) | 1–3 sharp transients 15–25 ms apart, no tail | T 0.5–0.8 / 0.9–1.0 |
| **Crunch** (cereal, cake crust) | Burst of 6–15 transients over 80–200 ms, random intervals of 8–25 ms, falling intensity | I 0.7→0.2, S 0.5–0.8 random |
| **Grind** (wax, grit) | Displacement-locked grains about 40–60/s plus low continuous | grains I 0.2–0.35 S 0.6; bed I 0.2 S 0.3 |
| **Creak or strain** (wood, plastic) | Bed with slow sharpness drift and sparse irregular "stick-slip" grains | bed S 0.35→0.6; grains every 1.5–3° |
| **Metal crumple** (can) | Discrete *buckle* events (transient plus 2–3 ringing transients 6–10 ms apart, decaying) over a high-sharpness crinkle stream | buckle T 1.0/0.85, ring 0.5/0.3/0.15 @ S 0.9 |
| **Shatter** (glass, ice) | Strike, then 12–20 tinkles over 250 ms, exponential decay, random sharpness | T 1.0/1.0, then I 0.7→0.1, S 0.85–1.0, gaps 8–25 ms |
| **Squelch or gooey squish** | Low-sharpness continuous with slow attack and an intensity swell, plus a few soft bubble transients | C S 0.0–0.1, attack about 50 ms, curve 0→0.6→0.2 over 350 ms; T 0.3/0.1 ×6–8 |
| **Pop or burst** (duck seam, balloon) | One hard transient, then an air-rush continuous with fine grains | T 1.0/0.5; C 0.4/0.6 for 0.6 s decay; grains 40/s at 0.2/0.9 |
| **Bottom-out thunk** | Dull hard transient plus a short dull continuous | T 1.0/0.15 + C 0.8/0.05 for 120 ms decay |
| **Wobble** (jelly release) | 3–4 decaying soft transients at the visual wobble frequency (about 6–8 Hz) | 0.5, 0.3, 0.15 @ S 0.1, 130 ms apart |

These are anchored by public recipes. Kodeco's "nom-nom" crunch uses continuous 1.0/0.3 for 0.15 s and 0.4/0.1 for 0.3 s, with transients 1.0/1.0 at 0 and 1.0/0.3 at 0.3 s, matched to the jaw snaps ([Kodeco p2](https://www.kodeco.com/10608020-getting-started-with-core-haptics?page=2)). Its "slice" uses continuous 0.35/0.25 for 0.25 s plus a snip transient 1.0/1.0 at 80 ms ([Kodeco](https://www.kodeco.com/10608020-getting-started-with-core-haptics)). Its splash uses transient 1.0/0.1, then continuous 0.5/0.1 at 0.1 s for 0.6 s, with attack 0.1, release 0.2 and decay 0.3 ([Kodeco p3](https://www.kodeco.com/10608020-getting-started-with-core-haptics?page=3)). Apple's sampler includes "Gravel", "Rumble", "Inflate" and "Sparkle" AHAPs to dissect as references ([HapticSampler](https://developer.apple.com/documentation/corehaptics/playing-a-custom-haptic-pattern-from-a-file.md)).

**Rule: never play the same file twice in a row.** Every event pattern gets round-robin variants or procedural jitter: ±10% intensity, ±15% timing, ±0.05 sharpness. That is what keeps the 50th crunch satisfying. Apple's "imagine using it a hundred times" advice applies ([WWDC19 223](https://developer.apple.com/videos/play/wwdc2019/223/)).

### 2.3 Tools
- **Apple:** macOS Quick Look previews AHAP files by audio ([WWDC21](https://developer.apple.com/videos/play/wwdc2021/10278/)). Use the HapticPalette sample to calibrate intensity and sharpness on the actual Duo.
- **Meta Haptics Studio** (formerly Lofelt) authors amplitude and frequency envelopes plus "emphasis" transients and is audio-driven ([Meta](https://developers.meta.com/horizon/resources/haptics-design-guidelines/)). **[unverified]** It exports AHAP, so confirm that before building a pipeline on it.
- **Nice Vibrations** (Unity) imports AHAP and offers real-time intensity and sharpness on continuous haptics ([More Mountains](https://nice-vibrations.moremountains.com/)). It's only relevant if we go with Unity.
- **[unverified]** Haptrix and Captain AHAP (Mac and web AHAP editors) and Interhaptics Haptic Composer (material-oriented) are worth a quick evaluation.
- **Our main tool should be in-app.** Build a debug "Haptic Lab" screen with live sliders for every constant in §5, a hinge-angle scrub, and an "export current preset to JSON" button. Designers tune on the Duo itself.

---

## 3. Real-time mapping from the hinge

### 3.1 Signal chain (per hinge callback, then per display frame)

```
raw θ (deg; 180 open → 0 closed; UIKit reports radians, so convert)
  → One-Euro filter (minCutoff ≈ 1.0 Hz, β ≈ 0.02 per deg/s, dCutoff 1 Hz)   [tune]
  → θ_f, plus velocity ω = dθ_f/dt, low-passed at about 6 Hz (deg/s; negative = closing)
  → display-rate interpolator (critically damped spring, ω_n ≈ 25 rad/s) → θ_v for visuals
  → press progress p = clamp((θ_contact − θ_f)/(θ_contact − θ_bottom), 0, 1)
  → state machine (Approach → Contact → Load → PreFail → Fail → Crush → Bottom → Closed)
  → haptic mapper (bed params at ≤60 Hz, grain scheduler, event triggers)
```

- **Why One-Euro:** it is low-lag when moving and heavy smoothing when still. That's exactly what we need, because readings are reported at about 5° accuracy, possibly quantised and at an unknown rate. Apple: don't depend on frequency or precision ([forums](https://developer.apple.com/forums/thread/847644)). **[unverified]** Typical slow closing speed is 20–60°/s, so 180→0° takes 3–9 s. Measure this in a playtest.
- **Prediction:** fire event thresholds on *predicted* angle, θ_pred = θ_f + ω·0.03 s, to hide sensor, filter and actuator latency. Never predict more than 6°.
- **Hold detection:** |ω| < 3°/s for more than 250 ms means *holding*.

### 3.2 Bed mapping (the "strain")
- **Target intensity:** `I_bed = strain(p) · (0.35 + 0.65·v)`, where `v = clamp(|ω|/60, 0, 1)` and `strain(p)` is a material curve, typically an ease-in. Clamp to ≤ 0.7 before failure.
- **Target sharpness offset:** `ΔS = S_mat − 0.5 + 0.25·strain(p)`. As the strain builds, the bed gets crisper, which reads as "tighter".
- **Hold:** decay the bed to 0 over 300 ms when holding. While held under load, play an occasional **settling creak** grain every 0.8–2.0 s at random, to keep tension without a constant buzz.
- **Opening:** if ω > 0 (opening), the bed goes to 0 within 80 ms. Unloading must feel like relief.
- **Send rate:** send at most once per frame, and only if |Δ| > 0.02. Each send is a 2-point `CHHapticParameterCurve`, from the current to the target value over 30 ms.

### 3.3 Grain scheduler (the compliance illusion)
- **Emit a grain each time the filtered angle crosses another Δθ_g** (material-specific, 0.5–3°) *while closing*. This is the spatial grain approach from Kildal and PseudoBend.
- **Smooth out coarse hinge updates.** The hinge may update coarsely, so convert the angle crossings into a rate `r = |ω|/Δθ_g` and schedule grains ahead on `engine.currentTime` with ±30% jitter. This avoids clumps when one update jumps 4°.
- **Cap the rate at 60 grains/s,** about Apple's texture density, and keep a minimum 12 ms gap.
- **Stiffness knob:** larger Δθ_g plus higher grain intensity = stiffer. Smaller Δθ_g plus lower intensity = softer and crumblier. The CHI 2025 work shows the trigger threshold changes perceived stiffness ([ACM](https://dl.acm.org/doi/10.1145/3706598.3714225)).
- **Rigidity knob:** *stop emitting grains* to say "this isn't moving" (the resistance plateau just before failure). Grain feedback capped beyond a force threshold "restricts the sensation of further movement" ([ACM](https://dl.acm.org/doi/10.1145/3706598.3714225)).

### 3.4 Event thresholds and hysteresis
- **Contact:** fires once when θ_pred < θ_contact and ω < 0. It re-arms only after θ > θ_contact + 8°, which is more than the about 5° accuracy, so noise can't double-fire it.
- **Failure:** fires at p_fail, a per-object value randomised ±0.04 per run, so it is felt as a surprise rather than learned. A fast slam (|ω| > 120°/s) fails early with ×1.0 intensity. A slow press gets the full pre-fail tell.
- **Irreversibility:** destruction never re-arms in the same press. Reopening after failure plays the reveal, not "unbreak". Only pre-failure deformation is reversible, which also satisfies Apple's "keep hinge effects reversible" advice for the *non-destructive* part ([bleepingswift](https://bleepingswift.com/blog/onhingechange-hinge-angle-swiftui)).
- **Bottom-out:** fires at p = 1. Map θ_bottom to about 12–15°, so our thunk lands just before the physical magnetic clap ([Gizmodo](https://gizmodo.com/iphone-duo-review-2000827502)). **Open question:** at what angle does the status report `.closed` and the scene hop to the outer display?

### 3.5 Lessons from products with great haptics
- **Apple's own UI:** short, sharp and scarce. Its system vocabulary is light, medium, heavy, rigid, soft, selection and success ([HIG](https://developer.apple.com/design/human-interface-guidelines/playing-haptics.md)). Use `success` semantics only for "added to collection", per the HIG's "use system patterns according to their documented meanings".
- **Toastie** pulses "once per second of cooking" while closed ([TechRadar via search](https://www.techradar.com/phones/iphone/apple-iphone-duo-review); [FoldHunt](https://foldhunt.com/iphone-duo/)). That proves the closed-state "felt but not seen" channel works on Duo. Squish should use it for the post-failure crush and the settle.
- **DualSense** uses voice-coil actuators for texture, and trigger resistance stands in for bowstring tension ([Wikipedia](https://en.wikipedia.org/wiki/DualSense)). **[unverified]** Team Asobi's Astro's Playroom derived its haptics from sound design, one material per surface. The lesson is to design audio and haptics from the same source asset.
- **HD Rumble** was pitched on "individual ice cubes and water in a glass" ([Wikipedia](https://en.wikipedia.org/wiki/Joy-Con)). The lesson is that *discrete countable grains* read as physical objects, while a continuous buzz reads as a motor.

---

## 4. HIG guidance, settings and what not to do

**From the HIG** ([Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics.md)):
- Use haptics consistently, with a clear causal link.
- Complement other feedback: "match the intensity and sharpness of a haptic with the intensity and sharpness of the animation."
- **Avoid overusing haptics.**
- In apps, prefer short haptics. Long-running ones are acceptable "that accompany a gameplay flow", and Squish's press is exactly that, but only *during* the press.
- **Make haptics optional.**
- Beware interfering with camera, gyroscope and microphone.

The Duo HIG adds nothing on haptics. Its only relevant point is "Make your game playable in every device pose" ([Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo.md)).

**Settings (status: unresolved, so test it):**
- No Apple doc states whether Core Haptics obeys **Settings › Sounds & Haptics › System Haptics**. Third-party sources conflict: one claims a single switch "honoured beneath your code" with no change callback ([Newly](https://newly.app/how-to/add-haptics)), while other docs only describe `supportsHaptics`, which reports hardware support, not the user setting.
- **Accessibility › Touch › Vibration** is described as turning off *all* vibrations ([AbilityNet](https://mcmw.abilitynet.org.uk/how-to-disable-vibrations-in-ios-17-on-your-iphone)).
- **No source ties Low Power Mode to Core Haptics.**
- **Action:** add a test matrix on the Duo (System Haptics off; Vibration off; Low Power on; Silent mode; thermal "serious"). Mirror the results in onboarding copy, e.g. "Feel nothing? Check Settings › Accessibility › Touch › Vibration".

**Don'ts:**
- **Don't run the bed while the user isn't moving.** It's the #1 annoyance; see the hold rule in §3.2.
- **Don't let parameters step-change at hinge rate.** It causes zipper buzz; use curves (§3.2).
- **Don't use 1.0 intensity outside the failure and bottom-out moments.** It flattens contrast and tires the hand.
- **Don't fire overlapping same-type events.** They blur, per Apple's sampler note.
- **Don't vibrate in menus or the collection beyond single light taps.**
- **Don't rely on haptics for meaning.** Sound and visuals must carry the experience on their own.

**Battery and thermal.** A press lasts 3–10 s of activity. The engine stays up only while the Press scene is open, and auto-shutdown handles the rest. Check `ProcessInfo.thermalState`: at "serious", halve the grain rate and cap the bed at 0.5.

---

## 5. iPhone Duo specifics (what we know and don't know)

- **Hinge API:**
  - SwiftUI `onHingeChange(isEnabled:_:)` gives `DeviceHingeContext.hinge: DeviceHinge?` with `angle: Angle` and `status` (`.closed`, `.partiallyOpen`, `.fullyOpen`).
  - UIKit `UIHingeInteraction` reports the angle in **radians** and adds `.unknown`. Its handler fires once with the initial state.
  - Both are iOS 27.1+.
  - Use them for effects, not layout, and capture `self` weakly.

  Sources: [bleepingswift](https://bleepingswift.com/blog/onhingechange-hinge-angle-swiftui), [forums](https://developer.apple.com/forums/thread/847644), [dev.to](https://dev.to/arshtechpro/iphone-duo-for-ios-developers-what-actually-changes-in-your-swift-code-5gc5).
- **Hardware feel:** 254 g (heavier than the iPhone 18 Pro Max), titanium frame, 5.2 mm open. The hinge has a "variable torque profile", is "super-smooth", holds "nearly any angle" and opens to a true 180°. Magnets make a "gentle but pleasing-sounding clap" on close. Open, it's "a two-handed device" ([Gizmodo](https://gizmodo.com/iphone-duo-review-2000827502)). Android Authority calls the hinge "smooth yet solid", needing "a bit of intention" ([search summary](https://www.androidauthority.com/apple-iphone-duo-hands-on-impressions-android-user-3712800/)).
- **Taptic Engine:** **No source** gives its location, size or strength on the Duo. The best inference **[unverified]**:
  - The engine sits in one half, probably the thicker half with the battery or logic board.
  - Held two-handed and half-open, one hand will feel more than the other.
  - At 254 g, the same drive likely produces less felt acceleration than a ~170–200 g phone, so we may need roughly 10–20% more intensity for "medium" feel.
  - When closed, the halves are stacked and clamped by magnets, so coupling should be better (stronger felt) than at 90°.
- **Calibration plan:** play a reference ladder of transients at 0.2–1.0 and sharpness 0, 0.5 and 1 at hinge angles 180°, 120°, 60° and closed, in two-handed and one-handed grips. Have 5 or more people rate equal-loudness. Fit a per-angle **gain table g(θ)** and multiply all intensities by it.
- **Use the hardware's resistance.** The user's hand *does* feel real torque from the hinge. Measure (by feel, or a luggage-scale test) where the torque peaks. If a mid-angle detent or stiffening exists, place the "resist then fail" climax just past it, so the body's real effort and our pseudo-haptic failure coincide.

---

## 6. The hydraulic-press moment: anticipation, resistance, failure, release

**Problem.** Our actuator vibrates; it can't push back. The hand sets the displacement. So we must create *perceived* force through a few levers:
- **Pseudo-haptics:** vision dominates. Lécuyer's survey shows visual displacement and control/display manipulations alter perceived stiffness and mass ([Lécuyer 2009, Presence](https://doi.org/10.1162/pres.18.1.39)). In VR, C/D ratios between 0.7 and 3.5 went *undetected* while shifting perceived stiffness by up to 28% ([Weiss et al., CHI 2023](https://unpaywall.org/10.1145%2F3544548.3581223)).
- **Grain compliance illusions** (§3.3).
- **Audio-visual-haptic harmony**, per Apple ([WWDC19 223](https://developer.apple.com/videos/play/wwdc2019/223/)).

**Squish twist.** The press plate *is* the upper half of the phone, so we can't fake the plate's motion. We *can* fake the **object's** response. Our C/D lever is "object deformation vs hinge travel":
- **Resist (stiff):** the object deforms at a ratio of about 0.3 relative to plate travel, with visible bulging stress, a shake of 0.5–2 px rising with strain, and creak pitch rising. Grains get sparse, then stop.
- **Failure:** the object *catches up* in 60–120 ms (snap-through). Visuals, audio and haptics peak together.
- **Give (soft):** after failure, the deformation ratio goes above 1 (it collapses faster than the plate). Dense, soft crunch grains follow.
- **Optional overlay:** a "PSI" gauge needle that climbs nonlinearly and drops at failure. This is the hydraulic-press video trope, and a strong force proxy.

**Haptic dramaturgy (applies to every material):**
1. **Anticipation (Approach):** no haptics. Audio only: a low hydraulic hum, plus a faint servo whine whose pitch follows θ.
2. **Contact:** one soft "kiss" so the user knows the press has met the object.
3. **Load:** the bed swells; grains are tied to angle.
4. **Pre-fail tell (the final Δp of 0.08):**
   - The bed sharpness rises +0.2.
   - A **strain tremor** modulates `IntensityControl` by ±0.08 at 14 Hz (jittered).
   - Micro-cracks accelerate from 3 to 15 per second, at 0.3→0.6 intensity and 0.9 sharpness. This also exploits Apple's "primer" effect, where rapid taps "wake up" the skin ([WWDC19 223](https://developer.apple.com/videos/play/wwdc2019/223/)).
5. **Hush:** the bed goes to 0 and the grains stop for 40–60 ms. The audio ducks −12 dB.
6. **Failure:** the material's break pattern, at full 1.0.
7. **Crush:** dense, lower-energy debris grains, plus a softer bed (S −0.2). The user keeps closing and keeps getting rewarded.
8. **Bottom-out:** a thunk. The bed stops dead.
9. **Closed:** the hardware clap. On the outer display, show a "stamp" card and play a single 0.5/0.3 tap. Toastie-style, closed-state haptics are optional.
10. **Reveal (on reopen past 30°):** a material-specific reveal haptic (peel, crumbs or fizz) plus a collection "success".

---

## 7. Squish haptic spec v0

**Conventions.**
- T(I/S) = transient with intensity and sharpness. C(I/S, dur) = continuous.
- All intensities are pre-multiplied by the user setting (Soft = 0.6, Full = 1.0) and the device gain g(θ).
- Angles are degrees, with 180 = flat.

### 7.1 Global constants
| Constant | Value |
|---|---|
| Bed authoring | one `HapticContinuous` I=1.0, S=0.5, Duration 30 s, `loopEnabled=true` |
| Bed max pre-failure | 0.70 |
| Param send | ≤60 Hz, 2-point curve over 30 ms, deadband 0.02 |
| Grain cap | 60/s, min gap 12 ms, jitter ±30% |
| Hysteresis | 8° on all re-armable thresholds |
| Prediction | 30 ms lookahead, max 6° |
| Hold | \|ω\| < 3°/s for 250 ms: bed fades to 0 over 300 ms, settling creak every 0.8–2.0 s |
| Hush | 50 ms before failure (bed 0, grains off, audio −12 dB) |
| θ_bottom | 13° (tune against when the `.closed` status arrives) |
| Variation | ±10% I, ±15% timing, ±0.05 S on every event and grain; ≥3 round-robin variants per event AHAP |

### 7.2 Shared patterns (AHAP-like)

```json
// contact_kiss.ahap
{"Version":1,"Pattern":[
 {"Event":{"Time":0,"EventType":"HapticTransient","EventParameters":[
   {"ParameterID":"HapticIntensity","ParameterValue":0.40},
   {"ParameterID":"HapticSharpness","ParameterValue":0.30}]}},
 {"Event":{"Time":0,"EventType":"AudioCustom","EventWaveformPath":"sfx/contact_<mat>.caf",
   "EventParameters":[{"ParameterID":"AudioVolume","ParameterValue":0.6}]}}]}

// bottom_thunk.ahap
{"Version":1,"Pattern":[
 {"Event":{"Time":0,"EventType":"HapticTransient","EventParameters":[
   {"ParameterID":"HapticIntensity","ParameterValue":1.0},{"ParameterID":"HapticSharpness","ParameterValue":0.15}]}},
 {"Event":{"Time":0.005,"EventType":"HapticContinuous","EventDuration":0.12,"EventParameters":[
   {"ParameterID":"HapticIntensity","ParameterValue":0.8},{"ParameterID":"HapticSharpness","ParameterValue":0.05},
   {"ParameterID":"Sustained","ParameterValue":0},{"ParameterID":"DecayTime","ParameterValue":0.10}]}},
 {"Event":{"Time":0,"EventType":"AudioCustom","EventWaveformPath":"sfx/thunk.caf"}}]}

// prefail_tell (procedural): over the final Δp=0.08
//   bed ΔS += 0.20; IntensityControl *= (1 + 0.08*sin(2π·14Hz·t + jitter))
//   microcracks: rate 3→15 /s, T(0.3→0.6 / 0.9)

// collect_success.ahap: T(0.6/0.6) @0, T(0.9/0.4) @0.09
```

### 7.3 Per-material presets

| Material | θ_contact | p_fail | Bed S_mat / strain curve | Grains (Δθ_g, I, S) | Failure pattern | Post-failure (Crush) | Reveal |
|---|---|---|---|---|---|---|---|
| **Crayon** (wax, stiff, brittle) | 45° | 0.30 | 0.55 / ease-in², steep | 2.0°, 0.35, 0.70; **stop grains at p>0.22** (rigid plateau) | **Snap:** T1.0/1.0 @0; T0.7/0.6 @12 ms; C0.5/0.3 60 ms decay; debris T×5 over 150 ms, 0.5→0.15 / 0.7 | Grind: Δθ 0.8°, I 0.25, S 0.6; bed 0.25/0.35 | Crumbs: T×6 over 300 ms, 0.25 / 0.6 |
| **Egg** (brittle shell, liquid core) | 70° | 0.20 | 0.70 / linear, low max (0.45) | 3.0°, 0.20, 0.90 ("tick" of shell strain) | **Crack + squelch:** T0.8/0.95 @0, T0.6/0.95 @18 ms, T0.5/0.9 @40 ms; then C(0.6/0.05, 0.35 s, attack 0.05) with curve 0→0.6→0.2; bubbles T0.3/0.1 ×8 random over 300 ms | Goo: bed S 0.05, I 0.3·v; no grains | Peel: C(0.35/0.0, 0.4 s) curve 0.1→0.4→0 |
| **Jelly** (soft, no fracture) | 80° | 0.85 (*splat*) | 0.10 / ease-out (gives early) | 3.5°, 0.18, 0.10 (sparse, soft) | **Splat:** T0.9/0.1 + C(0.7/0.05, 0.25 s, decay) | Squish loop: bed 0.35/0.0 | Wobble: T0.5, 0.3, 0.15 @ S0.1, 130 ms apart |
| **Rubber duck** (elastic, then seam pop) | 110° | 0.70 | 0.35 / linear; **squeak chirps**: every 25° of travel, sweep SharpnessControl −0.2→+0.3 over 250 ms at I 0.5, synced to squeak audio | 2.5°, 0.15, 0.30 | **Pop:** T1.0/0.5; C(0.4/0.6, 0.6 s decay); air grains 40/s at 0.2/0.9 for 0.5 s | Rubber fold: bed 0.3/0.25 | Deflate wheeze: C(0.3/0.4, 0.5 s), curve 0.3→0 |
| **Cake** (soft, crumbly) | 75° | none (progressive) | 0.10 / linear, max 0.45 | **1.2°**, 0.15–0.30 random, 0.45 (crumb texture) | **Frosting squirt** at p 0.65: C(0.6/0.1, 0.3 s) + T0.4/0.2 | Crumbs continue, Δθ 1.0°, I×0.7 | Plop: T0.6/0.15 + crumbs |
| **Soda can** (metal, sequential buckling) | 95° | buckles at p = 0.30, 0.45, 0.58, 0.70, 0.80 | 0.80 / stepwise: strain rises, then drops 40% after each buckle | Crinkle: 0.6°, 0.30–0.50, 0.75; stops 0.05 before each buckle | **Buckle** (each): T1.0/0.85; ring T0.5/0.9 @8 ms, 0.3 @16, 0.15 @24 ms. **First buckle, unopened can:** fizz C(0.35/0.9, 1.2 s decay) + grains 60/s at 0.15/0.95 | Dense crinkle at Δθ 0.5° | Fizz settle: grains 30/s fading over 0.8 s |
| **Glass bauble** (stretch goal) | 60° | 0.15 | 0.90 / very steep; **no grains** (silent rigidity) | — | **Shatter:** T1.0/1.0; tinkles ×16 over 250 ms, I 0.7→0.1 exp, S 0.85–1.0, gaps 8–25 ms | Shard crunch: Δθ 0.5°, I 0.35, S 0.95 | Tinkle T×5, 0.2 / 1.0 |

Notes on the table:
- **θ_contact** is set by object height in the scene. Keep failure angles between about 60° and 30° (visible). For example, crayon contact is at 45° and fails at p 0.3, which is about 36°.
- **Stiffness ordering:** glass > can > crayon > egg > duck > cake > jelly. It is encoded by bed sharpness, grain spacing and the "stop grains" plateau.
- **Slam behaviour:** if |ω| > 120°/s at failure, skip the tell, scale the failure by ×1.0 and the debris count by ×1.5. A violent slam should be *more* rewarding, not punished.
- **Reverse before failure:** play grains in reverse at ×0.5 intensity (elastic recovery). Jelly and duck add a single wobble or squeak on release.

### 7.4 Implementation sketch (Swift-flavoured pseudocode)

```swift
final class PressHaptics {
  let engine: CHHapticEngine            // created at launch, audioSession: .sharedInstance()
  var bed: CHHapticAdvancedPatternPlayer // 30 s continuous I1.0 S0.5, loopEnabled
  var filter = OneEuro(minCutoff: 1.0, beta: 0.02)
  var lastSent = (i: Float(0), s: Float(0)); var nextGrainAngle: Double = .nan

  func onHinge(_ deg: Double, t: TimeInterval) {           // from onHingeChange
    let θ = filter.update(deg, t); let ω = filter.velocity  // ω < 0 = closing
    let θp = θ + max(-6, min(6, ω * 0.03))
    state.advance(θp: θp, ω: ω, mat: mat)                   // fires contact/fail/bottom AHAPs once
    scheduleGrains(θ: θ, ω: ω)                              // Δθ_g, cap 60/s, jitter, plateau rules
  }
  func onFrame() {                                          // CADisplayLink
    let (i, s) = bedTarget(state, mat)                      // §3.2 incl. hold fade, hush, tremor
    guard abs(i - lastSent.i) > 0.02 || abs(s - lastSent.s) > 0.02 else { return }
    try? bed.scheduleParameterCurve(.init(parameterID: .hapticIntensityControl,
        controlPoints: [.init(relativeTime: 0, value: lastSent.i), .init(relativeTime: 0.03, value: i)],
        relativeTime: 0), atTime: CHHapticTimeImmediate)
    try? bed.sendParameters([.init(parameterID: .hapticSharpnessControl, value: s, relativeTime: 0)],
        atTime: CHHapticTimeImmediate)
    lastSent = (i, s)
  }
}
```

Sharpness is sent as a step because a sharpness step is less audible than an intensity step. Switch it to a curve too if it zippers.

---

## 8. Risks and open questions

1. **Hinge update rate and resolution are unknown and may vary with system state** ([forums](https://developer.apple.com/forums/thread/847644)). If updates are slower than about 20 Hz or quantised to 5°, the spatial grain illusion degrades. The fallback is velocity-rate grains from the filtered signal, already in §3.3. **Measure on day one.**
2. **The `.closed` transition and scene hop.** At what angle does the status become `.closed`? Does the inner-to-outer move glitch the audio session or the haptic engine? Does the outer-display scene keep our `CHHapticEngine` alive, or does it trigger a `stoppedHandler`?
3. **System settings:** unclear whether Core Haptics obeys System Haptics, Vibration or Low Power Mode, and there is no change callback. Mitigate with in-app toggles and a test matrix.
4. **Taptic strength and location on Duo:** no data. Run the g(θ) calibration (§5). Risk: one hand feels everything, the other nothing.
5. **The 30 s continuous cap and loop seams.** Long holds need looping. Check for an audible or tactile seam at loop points (WWDC21 says looping can be seamless) ([WWDC21](https://developer.apple.com/videos/play/wwdc2021/10278/)).
6. **Mixing AudioCustom and AVAudioEngine after engine resets.** Crash reports exist ([forum 763640](https://developer.apple.com/forums/thread/763640)). Stress-test reset handling, for example by forcing an interruption with a phone call or Siri.
7. **Latency is unmeasured.** Build a 240 fps plus contact-mic harness. Target: failure audio, haptic and visual within ±20 ms of each other **[unverified threshold]**.
8. **Fatigue across a session.** Twenty presses in a row could numb the hand. Track cumulative haptic-on time and reduce the bed by 10% after 60 s of accumulated bed time in 5 minutes. Variation is mandatory.
9. **Ethics and comfort:** offer a "Gentle" mode (no slam scaling, peaks capped at 0.7) for sensitive users and for nighttime play.
10. **Platform policy:** hinge APIs are 27.1+ and Duo-only. Non-Duo fallback is a press slider with identical haptics (§3 runs on any θ source).

---

## Sources

**Apple documentation and HIG**
- [CHHapticEngine](https://developer.apple.com/documentation/corehaptics/chhapticengine.md) · [isAutoShutdownEnabled](https://developer.apple.com/documentation/corehaptics/chhapticengine/isautoshutdownenabled.md) · [StoppedReason](https://developer.apple.com/documentation/corehaptics/chhapticengine/stoppedreason.md) · [Preparing your app to play haptics](https://developer.apple.com/documentation/corehaptics/preparing-your-app-to-play-haptics.md)
- [CHHapticPatternPlayer](https://developer.apple.com/documentation/corehaptics/chhapticpatternplayer.md) · [CHHapticAdvancedPatternPlayer](https://developer.apple.com/documentation/corehaptics/chhapticadvancedpatternplayer.md) · [CHHapticParameterCurve](https://developer.apple.com/documentation/corehaptics/chhapticparametercurve.md) · [CHHapticDynamicParameter.ID](https://developer.apple.com/documentation/corehaptics/chhapticdynamicparameter/id.md) · [CHHapticEvent](https://developer.apple.com/documentation/corehaptics/chhapticevent.md)
- [Representing haptic patterns in AHAP files](https://developer.apple.com/documentation/corehaptics/representing-haptic-patterns-in-ahap-files.md) · [registerAudioResource](https://developer.apple.com/documentation/corehaptics/chhapticengine/registeraudioresource(_:options:).md)
- [Updating continuous and transient haptic parameters in real time (HapticPalette)](https://developer.apple.com/documentation/corehaptics/updating-continuous-and-transient-haptic-parameters-in-real-time.md) · [Playing a custom haptic pattern from a file (HapticSampler)](https://developer.apple.com/documentation/corehaptics/playing-a-custom-haptic-pattern-from-a-file.md) · [Playing collision-based haptic patterns (HapticBounce)](https://developer.apple.com/documentation/corehaptics/playing-collision-based-haptic-patterns.md) · [Delivering rich app experiences with haptics](https://developer.apple.com/documentation/corehaptics/delivering-rich-app-experiences-with-haptics.md)
- [AVAudioSession.allowHapticsAndSystemSoundsDuringRecording](https://developer.apple.com/documentation/avfaudio/avaudiosession/allowhapticsandsystemsoundsduringrecording.md) · [UIFeedbackGenerator](https://developer.apple.com/documentation/uikit/uifeedbackgenerator.md)
- [HIG: Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics.md) · [HIG: Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo.md)
- [WWDC19 520 Introducing Core Haptics](https://developer.apple.com/videos/play/wwdc2019/520/) · [WWDC19 223 Expanding the sensory experience](https://developer.apple.com/videos/play/wwdc2019/223/) · [WWDC21 10278 Practice audio haptic design](https://developer.apple.com/videos/play/wwdc2021/10278/)
- [Apple forums: iPhone Duo group summary](https://developer.apple.com/forums/thread/847644) · [Core Haptics forum tag](https://developer.apple.com/forums/tags/core-haptics) · [AudioCustom crash thread](https://developer.apple.com/forums/thread/763640) · [Prepare your app for iPhone Duo (tech talk)](https://developer.apple.com/videos/play/tech-talks/111461)

**iPhone Duo coverage**
- [Gizmodo review](https://gizmodo.com/iphone-duo-review-2000827502) · [TechRadar review](https://www.techradar.com/phones/iphone/apple-iphone-duo-review) · [Android Authority hands-on](https://www.androidauthority.com/apple-iphone-duo-hands-on-impressions-android-user-3712800/) · [FoldHunt Duo apps (Toastie)](https://foldhunt.com/iphone-duo/)
- [bleepingswift: onHingeChange](https://bleepingswift.com/blog/onhingechange-hinge-angle-swiftui) · [dev.to: iPhone Duo for iOS devs](https://dev.to/arshtechpro/iphone-duo-for-ios-developers-what-actually-changes-in-your-swift-code-5gc5)

**Tutorials and tools**
- [Kodeco: Getting started with Core Haptics p1](https://www.kodeco.com/10608020-getting-started-with-core-haptics) · [p2](https://www.kodeco.com/10608020-getting-started-with-core-haptics?page=2) · [p3](https://www.kodeco.com/10608020-getting-started-with-core-haptics?page=3) · [p4](https://www.kodeco.com/10608020-getting-started-with-core-haptics?page=4) · [Exyte: Core Haptics](https://exyte.com/blog/creating-haptic-feedback-with-core-haptics)
- [Meta haptics design guidelines](https://developers.meta.com/horizon/resources/haptics-design-guidelines/) · [Nice Vibrations](https://nice-vibrations.moremountains.com/) · [Newly: haptics settings](https://newly.app/how-to/add-haptics) · [AbilityNet: disable vibrations](https://mcmw.abilitynet.org.uk/how-to-disable-vibrations-in-ios-17-on-your-iphone)
- [Wikipedia: DualSense](https://en.wikipedia.org/wiki/DualSense) · [Wikipedia: Joy-Con (HD Rumble)](https://en.wikipedia.org/wiki/Joy-Con)

**Research**
- Kildal, "3D-Press: haptic illusion of compliance when pressing on a rigid surface", ICMI 2010 ([listing](https://ixdf.org/literature/author/johan-kildal))
- Heo, Lee, Wigdor, "PseudoBend", UIST 2019 ([KAIST](https://koasas.kaist.ac.kr/handle/10203/272259?mode=full))
- "Diversifying Grain-Based Compliance Illusion by Varying Base Compliance", CHI 2025 ([ACM](https://dl.acm.org/doi/10.1145/3706598.3714225))
- Heo & Lee, "Creating haptic illusion of compliance for tangential force input" ([ACM](https://dl.acm.org/doi/10.1145/3131785.3131804))
- Strohmeier & Hornbæk, "Generating haptic textures with a vibrotactile actuator", CHI 2017 ([PDF](https://www.kasperhornbaek.dk/papers/CHI2017_HapticTextures.pdf))
- Okamura et al. 2001, reality-based vibration models (via [US patent 12159550](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/12159550)) · [Patent 11397467 (decay constants)](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/11397467) · [Kuchenbecker et al. 2006](https://www.ncbi.nlm.nih.gov/pubmed/16509381)
- Lécuyer, "Simulating Haptic Feedback Using Vision", Presence 2009 ([DOI](https://doi.org/10.1162/pres.18.1.39)) · [Weiss et al., Pseudo-Stiffness in VR, CHI 2023](https://unpaywall.org/10.1145%2F3544548.3581223) · [Electrotactile compliance illusion, CHI 2024](https://hci.cs.uni-saarland.de/projects/electrotactile-compliance-illusion/)
