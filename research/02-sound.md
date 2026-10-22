# Squish: Sound Design Research and Spec v0

*Research report 02. Prepared 22 Oct 2026, the day before iPhone Duo ships. Written for a team with no sound designer: an AI developer builds everything, there is a small budget for purchased libraries, the founder may record a little phone foley, it ships in about 4 weeks with about 10 launch objects, and it is rated 12+.*

---

## Key takeaways

1. **The satisfaction curve is tension, then release, then a reward.** People enjoy anticipation as well as the payoff. Salimpoor et al. (2011) found dopamine activity in the caudate during anticipation and in the nucleus accumbens at the peak ([Salimpoor 2011 via BRAMS](https://brams.org/2011/01/09/salimpoor/)). The Hydraulic Press Channel's creators describe their videos the same way: tension, then release ([Vice](https://broadly.vice.com/en/article/889wez/the-hydraulic-press-channel-is-the-internet-sensation-of-our-time)). So the strain build-up needs as much design work as the crack itself.
2. **Crisp means high-frequency energy, but harsh lives at 2–5 kHz. Treat them differently.** Boosting 2–20 kHz made potato chips seem crisper and fresher ([Zampini & Spence 2004](https://www.neuroscience.ox.ac.uk/publications/4405)). Sustained energy at 2–5 kHz drives amygdala-linked unpleasantness ([Newcastle/Kumar 2012](https://www.ncl.ac.uk/press/articles/archive/2012/10/nastynoiseswhydowerecoilatunpleasantsounds.html)), and removing 2–4 kHz makes chalkboard sounds bearable ([Oehler & Reuter, summarised by Smithsonian](https://www.smithsonianmag.com/science-nature/what-is-the-most-annoying-sound-in-the-world-75317235/)). The rule: let short broadband transients through, put the sparkle at 6–12 kHz, and notch any sustained tonal content at 2.5–4.5 kHz, such as squeals, scrapes and glass screech.
3. **Lower-pitched, complex, detailed sounds work best, and music gets in the way.** In ASMR surveys, "crisp sounds" triggered 64% of respondents and repetitive tasks 34% ([Barratt & Davis 2015](https://peerj.com/articles/851)). Lower-pitched complex sounds were the most effective triggers, and background music suppressed the response for many people ([Barratt, Spence & Davis 2017](https://peerj.com/articles/3846)). **No music while pressing.**
4. **Build on continuous, parameter-driven layers, not one-shots.** The hinge gives a continuous angle, so the core of the sound has to be loops and grains whose pitch, gain and density follow compression and closing speed. One-shots are reserved for discrete events: contact, crack, burst and bottom-out. Granular playback is the standard answer for "dynamic sounds that loops handle poorly... scraping, creaking" ([Audiokinetic](https://www.audiokinetic.com/engine-sound-modeling-from-sampling-to-granular-synthesis-in-wwise)).
5. **Make damage monotonic and filter the hinge signal.** The angle is accurate to about 5° and updates irregularly, and Apple-adjacent guidance says not to rely on a particular update rate or precision ([ecorpit SDK guide](https://ecorpit.com/iphone-duo-sdk-new-apis-xcode-27-1-developer-guide-2026/)). Smooth it with a spring or a One-Euro filter. Base crack thresholds on the *minimum angle ever reached*, with hysteresis, so wobbling the hinge never re-fires a crack.
6. **Use plain AVAudioEngine; skip FMOD and Wwise.** Both are free at this scale ([Wwise Indie under $250K budget](https://audiokinetic.com/pricing/for-games); FMOD's indie tier is free under roughly $200K revenue, so check fmod.com), but their value lies in GUI authoring tools built for human sound designers. An AI developer works best in code. Use `AVAudioSourceNode` for a custom grain and loop player, `AVAudioPlayerNode` pools for one-shots, and a master EQ and limiter.
7. **Do not use `AVAudioUnitTimePitch` for live pitch.** Developers report about 90 ms of latency, against negligible latency for Varispeed ([Apple forums](https://developer.apple.com/forums/thread/708168)). Do resampled-rate playback in your own source node or use Varispeed. Request a 5 ms IO buffer, which typically yields 256 frames, and read back what you actually got ([Apple forums](https://developer.apple.com/forums/thread/12432)).
8. **Use the `.ambient` session category and respect the silent switch.** Apple's HIG maps `.ambient` to non-essential sound that mixes with other audio and obeys the switch ([Apple HIG, Playing audio](https://developer-mdn.apple.com/design/human-interface-guidelines/patterns/playing-audio)). Haptics must make the toy satisfying when it is muted. Bind Core Haptics to the same session with `CHHapticEngine(audioSession:)` ([Apple forums](https://developer.apple.com/forums/thread/703326)).
9. **Design for the phone speaker first.** Phone speakers cannot reproduce low fundamentals. Imply weight with 2nd, 3rd and 4th harmonics, which is the missing-fundamental effect ([Production Expert](https://www.production-expert.com/production-expert-1/how-to-make-sure-bass-is-heard-on-small-speaker-devices), [diyAudio](https://www.diyaudio.com/community/goto/post?id=3693201)). Switch EQ by output route: speaker vs. headphones. Target about **−16 LUFS integrated, −1 dBTP** ([IESD mix reference](https://www.audiogang.org/wp-content/uploads/2015/04/IESD-Mix-Ref-Levels-v03.02.pdf)).
10. **Buy about $150–250 of libraries, mine the free Sonniss GDC bundles, and use AI-generated SFX only to fill gaps.** Specific packs are listed in §5. Ship a "Crunchy sounds: Full / Soft" option. Chewing and crunching are the top misophonia triggers, and studies put prevalence anywhere from 6% to 49% ([Ankara population study](https://resolve.cambridge.org/core/services/aop-cambridge-core/content/view/6ECEBA5E4EF135E099457CD7485C5F72/S2056472421009789a.pdf/the-prevalence-and-characteristics-of-misophonia-in-ankara-turkey-population-based-study.pdf), [ScienceAlert](https://www.sciencealert.com/misophonia-turns-out-to-be-way-more-common-than-we-thought)). **Biggest process risk: the AI developer cannot listen.** Build objective checks (loudness, spectral and onset scripts) and a 15-minute founder listening protocol into every build.

---

## 1. What makes crush sounds satisfying

### 1.1 Evidence

- **ASMR trigger surveys.** Barratt & Davis surveyed 475 people. The most common triggers were whispering (75%), personal attention (69%), crisp sounds (64%) and slow movements (53%). 34% were triggered by watching repetitive tasks ([PeerJ 2015](https://peerj.com/articles/851)). The 2017 follow-up with 130 experiencers found that "lower-pitched, complex sounds" were especially effective, as were "slow-paced, detail-focused videos". Background music inhibited the sensation for many ([PeerJ 2017](https://peerj.com/articles/3846)).
- **Acoustic features.** A 2025 preprint found that "smoothly spread and energy-dense cyclic patterns" triggered ASMR most effectively ([Cao et al., arXiv 2504.00621](https://arxiv.org/abs/2504.00621v2)). In practice this means many small, dense, evenly spaced micro-events, which is exactly what granular crunch produces. A single big bang is not the same thing.
- **Crunch and freshness.** Zampini & Spence (2004, Ig Nobel 2008) showed that raising overall level, or only the 2–20 kHz band, made chips seem crisper and fresher ([Oxford](https://www.neuroscience.ox.ac.uk/publications/4405), [FoodNavigator](https://www.foodnavigator.com/Article/2024/06/18/the-science-of-sound-what-is-it-about-the-crunch-that-keeps-snackers-dipping-in-for-more)). Earlier work found fresh chips were louder and had more high-frequency content than stale ones. **For Squish:** bright, dense crunch reads as fresh and satisfying, and dull crunch reads as soggy.
- **The unpleasant band.** In Kumar's 2012 fMRI study, sounds rated most unpleasant clustered at about 2–5 kHz. The amygdala modulated auditory cortex in proportion to rated unpleasantness ([Newcastle press release](https://www.ncl.ac.uk/press/articles/archive/2012/10/nastynoiseswhydowerecoilatunpleasantsounds.html), [Psych Central](https://psychcentral.com/news/2012/10/11/why-we-cringe-at-unpleasant-sounds)). Oehler & Reuter's chalkboard work narrowed this to about 2–4 kHz, where the ear canal resonates ([Smithsonian](https://www.smithsonianmag.com/science-nature/what-is-the-most-annoying-sound-in-the-world-75317235/)).
- **Tension and release.** Anticipation is rewarding in its own right ([Salimpoor 2011](https://brams.org/2011/01/09/salimpoor/)). The Vuohensiltas compare hydraulic press videos to pimple-popping: anticipation and tension, then release ([Vice](https://broadly.vice.com/en/article/889wez/the-hydraulic-press-channel-is-the-internet-sensation-of-our-time)). Kinetic-sand creators credit "shape, color, and sound" together, and commentators suggest audio is the main driver ([Vice](https://vice.com/en/article/9k9xm7/the-oddly-satisfying-strangely-soothing-world-of-sand-slicing-videos), [Inverse](https://inverse.com/article/48157-why-the-asmr-community-is-debating-those-slicing-sand-videos)). There are no peer-reviewed studies of "oddly satisfying" videos specifically ([Live Science](https://www.livescience.com/62091-oddlysatisfying-videos-satisfying.html)). Treat the rest of this section as practitioner consensus.

### 1.2 Design rules

| Pleasant (do) | Grating (avoid) |
|---|---|
| Dense, broadband micro-transients: crunch, crackle, popping bubbles | Sustained *tonal* energy at 2–5 kHz: squeal, screech, glass-on-glass scrape |
| Low-mid body at 150–600 Hz, the "thock" | Long, loud metal shrieks. Shorten them and low-pass them at about 3 kHz |
| Air and sparkle at 6–12 kHz on transients | Wet mouth sounds (chewing, slurping): the top misophonia triggers ([ScienceAlert](https://www.sciencealert.com/misophonia-turns-out-to-be-way-more-common-than-we-thought)) |
| Rhythm that follows the user's hand (causality) | Random sounds that don't line up with what the user is watching |
| Small variations every press | Identical repeated samples. "Machine-gun" repetition is the fastest way to make the toy feel cheap |
| A clear climax, then a short decay | Long reverb tails that blur the next event |

**12+ note:** keep the comedy. A rubber duck being crushed must never sound like an animal in pain. Use a squeak that bends upward, then a comic deflating wheeze, never a scream-like squeal. Many "squish" libraries are sold as gore. Use them, but strip anything that reads as flesh or bone, and avoid low, wet, meaty squelch on food objects.

---

## 2. Foley and game-audio technique

### 2.1 Layer anatomy

Practitioners build every impact from separate slots: **transient** (the snap), **body** (weight and character), **tail** (decay and space) and often **mechanical or debris** detail. "A weak sound usually has one slot missing or fighting another." Small offsets between transient and body change perceived size ([Violet Recording](https://violetrecording.com/how-to-make-impact-sounds/), [Lior Tega](https://www.liortega.com/post/first-person-shooter-gun-sound-design)). Keep tails short in interactive contexts to avoid mud.

For Squish, every **failure event** (crack, burst, pop) is assembled at runtime from three layers. Each is chosen independently from round-robin pools:

| Layer | Content | Timing | Spectral home |
|---|---|---|---|
| Transient | Snap, click or tick, 5–30 ms | t = 0 | 3–12 kHz, short, so the harsh band is fine for a few ms |
| Body | Material character: crunch, glug, crumple, thock, 80–400 ms | t = 0 to +8 ms jitter | 150 Hz–2 kHz, plus harmonics for the speaker |
| Debris or tail | Grains scattering, settling, liquid spatter, 200–800 ms | +20 to +80 ms | Broadband, ducked by 3–6 dB |

Combining layers at runtime multiplies variation: 4 transients × 4 bodies × 3 debris gives 48 combinations from 11 files.

### 2.2 Variation and fatigue

The standard recipe is multiple variations, random choice without immediate repeats, and small random pitch and volume offsets ([IRPR](https://sounddesign.irpr.agency/guides/why-is-my-game-audio-repetitive/), [Bugnet](https://bugnet.io/blog/how-to-implement-footstep-variation-to-avoid-repetition)). Some sounds *should not* vary, because recognition is part of the pleasure. Mario's coin is the classic example ([A Sound Effect](https://www.asoundeffect.com/game-audio-immersion/)). For Squish:

- **Vary:** all material sounds. Pitch ±1.5 semitones for grains and ±0.7 for bodies; gain ±2 dB; start offset 0–20 ms into longer files; "shuffle bag" random selection so the same file never plays twice in a row.
- **Never vary:** brand sounds, meaning the reveal sting, the collection chime and the press "ka-chunk". These are the logo.
- **Per-press seed:** at the start of each press, jitter that object's crack thresholds by ±0.04 compression and pick a per-press "tone" offset of ±0.5 st. Each press of the same object then feels new, but stays recognisable.

### 2.3 Juice and mickey-mousing

"Juice" is generous feedback on every action: sound, shake, particles, flash ([Jonasson & Purho, GDC Europe 2012, summarised by RPG Playground](https://rpgplayground.com/research-making-a-juicy-game/)). In Squish the visuals are already physical, so sound should follow them exactly, in strict causal sync. Apple's audio-haptic guidance stresses causality: haptic and sound should land on the visible moment ([WWDC21 "Practice audio haptic design"](https://developer.apple.com/videos/play/wwdc2021/10278)). Each visible crack in the mesh or shader gets a sound. Each sound gets a visible crack. Rising pitch under strain is a well-worn juice device and maps naturally onto rising pressure ([Brad Woods](https://garden.bradwoods.io/notes/design/juice)).

---

## 3. Real-time audio driven by hinge angle

### 3.1 Control signal

The SDK exposes `onHingeChange` in SwiftUI and `UIHingeInteraction` in UIKit. They report angle in radians and a status of closed, partiallyOpen or fullyOpen. The API is meant for effects, not layout, and update rate and precision are not guaranteed ([sunyazhou](https://www.sunyazhou.com/en/2026/09/adapting-apps-to-iphone-duo-in-ios-27/), [ecorpit](https://ecorpit.com/iphone-duo-sdk-new-apis-xcode-27-1-developer-guide-2026/), [daily.dev](https://daily.dev/posts/a-riff-on-new-hinge-apis-for-iphone-duo-1zcrpie9g)). Apple's own Tech Talk demo uses hinge angle as a guitar pitch bend, so audio is a sanctioned use.

Pipeline:

1. **Raw angle** θ_raw in degrees, irregular timestamps. Give each sample its arrival time.
2. **Filter:** a One-Euro filter (adaptive low-pass: smooth when slow, responsive when fast) or a critically damped spring at 120 Hz in a display-link loop. The output is θ (smoothed) and ω = −dθ/dt in °/s, positive when closing.
3. **Push to the audio thread** through a lock-free atomic or ring buffer. On the audio thread, **ramp every parameter over 20–40 ms** to prevent zipper noise. The audio thread never reads UI state directly.
4. **Derived state:**
   - `c = clamp((θ_contact − θ) / (θ_contact − θ_flat), 0, 1)` is compression. θ_contact depends on object height, and θ_flat is the closed or minimum angle.
   - `c_max = max(c_max, c)` gives monotonic damage. Cracks fire when `c_max` crosses a threshold, never on `c` alone.
   - `v = clamp(ω / 120, 0, 1)` is normalised closing speed. Calibrate on device; 120°/s is a guess for a "firm" close.
   - `fresh = (c ≥ c_max − 0.01)`, meaning "breaking new ground", versus re-pressing already-crushed material.
5. **Hysteresis:** a threshold fires once, and re-arming needs `c` to drop 0.1 below it. That only matters for elastic materials such as jelly and the duck, which can recover.

Because the sensor resolves about 5°, every 5° is an obvious **quantum**. Fire a pressure-gauge tick for each 5° step under load. This turns a sensor limitation into a feature: the ticks are honest about resolution, and the filtered continuous layers hide the steps.

### 3.2 Synthesis approaches, ranked for this team

1. **Parameter-driven sample layers (core).** Loops (hiss, motor, strain) whose rate and gain follow `c` and `v`, plus one-shot events at thresholds. This is the classic RPM-loop approach used for engines. It works well within about ±7 semitones and starts to sound like a lawnmower beyond that ([Audiokinetic](https://www.audiokinetic.com/engine-sound-modeling-from-sampling-to-granular-synthesis-in-wwise)). Keep pitch excursions within that range.
2. **Simple granular crunch (core).** Slice crunch recordings into 20–150 ms grains, then fire grains at a rate driven by closing speed and material state. Physics-coupled grain density is an established technique. One paper sets grains per second from fragment collisions in a rock-breaking simulation ([Audiokinetic / DAFx](https://www.audiokinetic.com/engine-sound-modeling-from-sampling-to-granular-synthesis-in-wwise)). Here grain rate ∝ `v × fresh × materialDensity`. This is the "energy-dense cyclic pattern" the ASMR preprint describes.
3. **Procedural creak and stick-slip (nice to have).** Farnell's creaking door excites a bank of band-pass "wood" resonators at about 62–790 Hz with stick-slip impulses ([MIT Press, Designing Sound practical 9](https://mitp-content-server.mit.edu/books/content/sectbyfn/books_pres_0/8375/designing_sound.zip/practical09.html)). Driving the impulse rate from `c` makes a strain creak that never loops. It is about 100 lines in an `AVAudioSourceNode`. Use it as the press frame creak, layered under the sampled material strain.
4. **Modal resonators for glass and can ring (nice to have).** Modal synthesis, a bank of decaying sinusoids excited by impacts, is the standard real-time rigid-body method ([O'Brien et al.](https://people.eecs.berkeley.edu/~job/Classes/CS184/Fall-2016-Slides/18-Simulation.pdf)). A full fracture simulation (Zheng & James' glass smash used 4,046 modes, [Cornell](https://research.cs.cornell.edu/FractureSound/files/fractureSound.pdf)) is far beyond scope. Eight to twelve modes struck by each grain give a coherent "ring" to the can or bottle for almost no CPU. Defer to v1.1 if time is short.
5. **Physical fracture models, ML impact synthesis** ([Deep-Modal](https://unpaywall.org/10.1145%2F3394171.3413572)): out of scope.

### 3.3 iOS tech stack

**Session**
- `AVAudioSession.Category.ambient`, no options. It mixes with the user's music or podcast, is silenced by the Ring/Silent switch and screen lock, and fits a toy ([Apple docs](https://developer.apple.com/tutorials/data/documentation/avfaudio/avaudiosession/category-swift.struct/soloambient.md), [HIG](https://developer-mdn.apple.com/design/human-interface-guidelines/patterns/playing-audio)).
  - **Do not use `.playback` to "force" sound.** Overriding the switch is bad etiquette, and many players press with the phone on silent.
  - Apple offers no public API to read the switch ([Stanford UQ](https://uq.stanford.edu/answer/51eacda4-1218-4e3b-be74-8a115d2bfd1d)). Instead, show a small speaker glyph and a first-run tip: "Squish sounds best with sound on 🔊." Haptics carry the experience when muted.
- `setPreferredIOBufferDuration(0.005)` and `setPreferredSampleRate(48000)` before activating, then read back `ioBufferDuration`. Preferences are hints ([Apple QA1631](https://developer.apple.com/library/ios/qa/qa1631/_index.html)), and iOS 18 had a bug that ignored them when Sound Recognition was on ([Apple forums](https://developer.apple.com/forums/thread/769245)).
- **Bluetooth:** AirPods report about 160 ms output latency ([Apple forums](https://origin-devforums.apple.com/forums/profile/brigittaforrai)). Read `outputLatency`. When it exceeds 50 ms, schedule haptics *later* by that amount so haptic and audio coincide, and accept that audio lags the visuals. It feels fine for continuous layers and slightly off for cracks.
- Handle `AVAudioEngineConfigurationChange` and interruptions by rebuilding the graph. The engine can reset nodes on route changes ([Apple forums](https://developer.apple.com/forums/thread/111968)).

**Graph**
```
[PressBed SourceNode]  hiss, motor, procedural creak, gauge ticks ─┐
[MaterialBed SourceNode] strain loops + granular crunch ──────────┼─> [Material bus]
[One-shot pool] 10 × AVAudioPlayerNode (events, brand sounds) ────┘        |
                                                          [AVAudioUnitEQ: route profile]
                                                          [Harmonic exciter: custom, low band]
                                                          [Peak limiter: AUPeakLimiter / AUDynamicsProcessor]
                                                          [mainMixer] -> output
```
- **`AVAudioSourceNode`** for anything continuous ([WWDC19 510](https://developer.apple.com/videos/play/wwdc2019/510/)). Write the grain scheduler and variable-rate loop reader in Swift with no allocation, locks or dispatch on the render thread. Pre-decode all PCM into `UnsafeMutablePointer<Float>` buffers when the object is selected.
- **Pitch:** use your own linear or cubic interpolated read pointer (rate = 2^(st/12)), or `AVAudioUnitVarispeed`. **Avoid `AVAudioUnitTimePitch`**, which has about 90 ms of latency ([Apple forums](https://developer.apple.com/forums/thread/708168)).
- **One-shots:** pre-attached `AVAudioPlayerNode` voices with `scheduleBuffer(..., at: nil)`. Voice-steal the oldest voice. Cap concurrent event voices at 10.
- **Formats:** ship CAF with AAC at 160 kbps for beds, and CAF with linear PCM 16-bit mono for short transients and grains, where AAC priming and padding would blur onsets. Most assets are mono; reserve stereo for hiss and room. Decode only the current object plus the press set, which is about 10–20 MB in RAM.

**Haptics.** Use `CHHapticEngine(audioSession: AVAudioSession.sharedInstance())` so haptic audio follows session policy ([Apple forums](https://developer.apple.com/forums/thread/703326)). Use a `CHHapticAdvancedPatternPlayer` with one continuous event whose intensity is driven by `c`, through `sendParameters` for dynamic intensity and sharpness, plus transient events fired in the same code path as each crack one-shot. Don't put audio inside AHAP files. Developers report crashes with audio-custom events ([Apple forums](https://developer.apple.com/forums/thread/763640)), and AVAudioEngine gives better control anyway. Haptics are generated in code, and audio goes through AVAudioEngine.

**Middleware verdict.**
- FMOD (free indie tier; check current thresholds on fmod.com) and Wwise (Indie is free under a $250K budget, with no asset limits since 2022: [Audiokinetic](https://www.audiokinetic.com/about/news/audiokinetic-announces-indie-focused-limited-commercial-license)) are excellent, but their strength is the GUI authoring tool. An AI developer can't use a GUI effectively, the SDKs add binary size and integration overhead, and the logic here is about a dozen parameters. **Not worth it.**
- AudioKit (MIT) is reasonable if you want ready-made oscillators and filters for the procedural creak ([AudioKit](https://audiokitpro.com/audiokit/)). Raw `AVAudioSourceNode` with biquad code is less dependency for the same result.
- Steam Audio (formerly Phonon) handles spatialisation, which is irrelevant here.

---

## 4. Sonic identity: "the Squish Press"

There is little published analysis of the reference games' audio, but the pattern is consistent:
- Townscaper's appeal is a soft "pop" on placement plus a quiet wind-and-waves bed ([Destructoid](https://vip-develop.destructoid.com/?p=298540), [Raw Fury press](https://gamespress.westeu-v2.propressroom.com/Oskar-Stalberg-Raw-Furys-Townscaper-Is-Now-Officially-Available-on-Nin)).
- Monument Valley turns mechanical actions into musical fragments, such as arpeggiated cogs ([The Sound Architect](https://thesoundarchitect.co.uk/tag/monument-valley)).
- Team Alto wanted sound effects with "a musical quality" so simple actions feel "a little magical" ([CGMagazine](https://www.cgmagonline.com/interviews/interview-with-the-team-behind-altos-odyssey)).
- Sonic-branding practice favours a very short, consistent signature that is never randomised ([Transform](https://transformmagazine.net/articles/2024/tiny-sounds-massive-impact-the-power-of-sonic-branding)).

**The identity.** A friendly workshop machine, not an industrial one. Picture a small, beautifully engineered brass and enamel press. It is **quieter and warmer than real hydraulics**, so the object's sounds remain the star.

| Element | Design | Varies? |
|---|---|---|
| **Pneumatic hiss** | Filtered pink noise, band-passed 1.5–6 kHz, opening with closing speed. Soft "tsss", never a steam-pipe blast | Yes, follows speed |
| **Motor hum** | A two-partial hum at 220 + 330 Hz (implying a 110 Hz fundamental the speaker can't play), rising about 5 st under load | Yes, follows load |
| **Pressure gauge ticks** (the signature) | A small mechanical tick plus a short tuned "tink", one per 5° under load, **climbing a pentatonic scale** as pressure builds. A failure resolves to the tonic chord. A tactile Shepard-like riser ([Titeux](https://www.nicolastiteux.com/en/blog/shepard-and-risset-audio-illusions/)) | Pitch follows c; timbre fixed |
| **Ka-chunk** | The bottom-out: a two-part mechanical latch, low thock plus high click | **Fixed** |
| **Release sigh** | On reopening, a gentle reversed-hiss exhale | Slight |
| **Reveal sting** | Three notes on the same pentatonic, about 0.6 s, with a soft bell or marimba. Plays when the flattened result is shown | **Fixed** (the logo) |
| **Collection chime** | A two-note answer to the sting | **Fixed** |

One key, C or D major pentatonic, for everything tuned. Ticks, sting and chime then form one musical system, as in Monument Valley. **Make the ticks and sting procedurally in code** (sine plus noise burst through an envelope, with a short modal "tink"). That avoids licensing anything for the brand and lets the AI developer tune it numerically.

**Music:** none in the press scene. ASMR evidence says music suppresses the response ([Barratt et al. 2017](https://peerj.com/articles/3846)), the `.ambient` session lets users bring their own, and an object-driven soundscape *is* the music. Optionally, one soft 60–90 s lo-fi loop on the collection screen only, at −8 LU relative to SFX, with its own toggle that defaults to on. Its absence is a far smaller risk than a bad loop. Defer it if the 4-week budget is tight.

**Room:** a faint workshop room tone at about −40 dBFS (clock-less, no voices). It makes silence feel intentional and gives reverb-less one-shots a shared space. A small convolution or `AVAudioUnitReverb` "small room" send at about 8% wet ties sample sources from different libraries together, which matters for consistency.

---

## 5. Sourcing (budget-first, no sound designer)

### 5.1 Licences in brief

- **A Sound Effect** marketplace: royalty-free, no attribution, with per-user pricing and multi-user discounts ([A Sound Effect](https://www.asoundeffect.com/)).
- **BOOM Library** EULA: one individual, commercial use in video games, no extra fees or attribution ([BOOM FAQ](https://www.boomlibrary.com/support/faq/what-am-i-allowed-to-do-with-your-sounds/)).
- **Soundly:** Pro library cleared for games, and stays cleared after you unsubscribe ([Soundly FAQ](https://getsoundly.com/faq/can-i-use-the-sounds-in-a-video-game), [EULA](https://getsoundly.com/assets/Soundly-EULA.pdf)). Roughly $10–15 a month, unverified.
- **Splice:** a royalty-free licence per download covering games, with no redistribution as samples ([Splice FAQ](https://intercom.help/splice-b7a2d5b83f2e/en/articles/8652642-splice-sounds-licensing-faq)).
- **Sonniss GDC bundles:** free, royalty-free, unlimited projects, no attribution. You can't resell them as sounds, and AI/ML training is prohibited. Shipping them in an app is fine ([Sonniss](https://sonniss.com/gameaudiogdc)). 2026 is about 7.5 GB from 17 vendors ([Rekkerd](https://rekkerd.org/sonniss-releases-gdc-2026-game-audio-bundle/)), and earlier years total more than 100 GB.
- **Freesound:** filter to **CC0 only**. CC-BY means keeping a credits file; CC-BY-NC is forbidden for a paid app ([Cinevva summary](https://app.cinevva.com/guides/game-asset-licenses.html)).
- **ElevenLabs SFX generation:** commercial use only on paid plans (about $5–6 a month), and the free tier needs attribution ([Dupple](https://dupple.com/learn/is-elevenlabs-free)). Read the current ToS before shipping.
- **Epidemic Sound:** a developer/API product whose game terms are unclear ([Epidemic](https://www.epidemicsound.com/business/developers/)). **Skip.**
- All of these forbid redistributing raw sounds, and shipping inside an app bundle counts as normal "use in a production". Keep the license PDFs and receipts in `/licenses` in the repo.

### 5.2 Shopping list (about $150–250)

| Need | Pack | Price (indexed; verify) | Covers |
|---|---|---|---|
| Wet squish, gel, goo, air squeeze | **Ultrasquish** (Studio Obsidian, A Sound Effect). About 40 min at 192 kHz, built for heavy pitch shifting ([ASE](https://www.asoundeffect.com/product-tag/goo)) | $40 | Jelly, egg contents, cake squish, duck air |
| Vegetable or food crunch, snap, splat | **Flesh, Bones & Gore** bundle (vegetables and foods in a foley suite). Use the veg crunch and snaps; drop the gore ([ASE](https://www.asoundeffect.com/?p=637210)) | $26.50–53 | Crayon snap body, cake crumble, egg crunch |
| Glass | **Glass Smash HD** (Soundopolis): 578 clips, 96k, bottles and panes ([Sonniss](https://sonniss.com/product/glass-smash-hd-sound-effects-library)), *or* budget **Glass Breaking SFX**: 104 files ([itch](https://sound-works-12.itch.io/glass-breaking-sfx)) | $75 / $5 | Bottle crack, shatter, debris grains |
| Thin metal | **Ongelegen Binaural 02 – Aluminum Cans**: about 250 can sounds, bending and crushing ([Rekkerd](https://rekkerd.org/ongelegen-releases-binaural-02-aluminum-cans-sample-pack/)) | Free | Soda can crumple, pop-tab, fizz (add from Sonniss) |
| Press frame groan | **Metal Groans and Slams** (Mattia Cellotto): 346 sounds ([ASE](https://www.asoundeffect.com/)) | about $30–37 | Press strain under the material, the ka-chunk low layer |
| Rubber squeak | **Squeaky Toys** (Sounds Like George): 170–190 files ([itch](https://soundslikegeorge.itch.io/squeaky-toys), [ASE](https://www.asoundeffect.com/sounddesigner/Sounds-Like-George)) | $5–10 | Duck |
| Household and food all-rounder | **Household Source** (Epic Stock Media): 2,500+ sounds, including food ([ASE](https://www.asoundeffect.com/sound-library/household-source)), and/or ESM **Cooking Game** (662 files) | about $23 on sale | Bubble wrap, packets, crayon, cake |
| Hydraulics | Cheap: **Robotics and Hydraulics** (MuseHub, about CHF 10) ([MuseHub](https://www.musehub.com/loops-and-audio/robotics-and-hydraulics-sound-effects)). Skip the $199 ASE Hydraulics & Pneumatics; hiss is better synthesised | about $10 | Reference and layer only |
| Gaps | Sonniss GDC 2015–2026 (free), Freesound CC0, ElevenLabs one month (about $6) | $0–6 | Bubble-wrap pops, crayon wax creak, odd one-offs |

**Total ≈ $160 (budget glass) to $250.** Optionally take one month of Soundly Pro to browse a large cleared catalogue quickly.

### 5.3 Founder phone foley (optional, high value)

This is cheap and specific, so record it if possible. Twenty minutes in a quiet carpeted room, phone 10–15 cm away, Voice Memos set to lossless, airplane mode on:
- Real bubble wrap: slow press and fast press.
- Snapping a crayon.
- Squeezing a jelly in its tub.
- Crushing an empty can underfoot.
- Cracking an egg into a bowl.

Phone mics roll off lows and apply processing, so these recordings will be bright and thin. That suits transients and grains, and the libraries supply the body. A piezo contact mic (about £10, [MAKE](https://makezine.com/projects/piezo-contact-mic)) gives intimate, noise-free crunch but needs an interface. Skip it for v1. Classic foley swaps that work: celery twist for snaps, lettuce for crunch, bell pepper for crisp pops ([Mental Floss](https://www.mentalfloss.com/food/how-foley-artists-use-food-make-sound-effects), [Sound Ideas](https://sound-ideas.com/blogs/sound-ideas/the-sonic-superpower-of-fruits-and-vegetables)).

### 5.4 Automated asset pipeline (because the developer can't listen)

Scripted in Python or ffmpeg and run on every asset:
1. **Select:** search library metadata and UCS filenames by keyword, for example `GLASSBrk`, `FOODCrsh`, `RUBRSqk`.
2. **Trim and normalise:** `ffmpeg -af silenceremove,loudnorm`. Normalise one-shots to peak −3 dBFS and beds to a fixed LUFS within their category.
3. **Auto-slice grains:** librosa onset detection on crunch files gives 20–150 ms slices with 2 ms fade-in and 10 ms fade-out. Reject slices whose spectral centroid falls outside the material's range.
4. **Harshness check:** compute the energy ratio in 2.5–4.5 kHz against the full band over sustained parts, excluding the first 30 ms. Flag anything above the threshold for an EQ dip or rejection.
5. **Generate spectrogram PNGs** so the AI developer can at least inspect them visually.
6. **Export:** mono 48 kHz, CAF (PCM16 for grains and transients, AAC 160 kbps for beds).
7. **Final mix check:** record the app output and measure integrated LUFS and true peak, using the `ebur128` filter.

---

## 6. Pitfalls

**Phone speakers.** Small phone speakers roll off steeply in the low hundreds of Hz, and published numbers for recent iPhones are unreliable. Measure on an iPhone Duo with a reference mic or a sweep app ([Sweep](https://apps.apple.com/app/id6784438195)). Assume nothing useful below about 250–300 Hz.
- *Speaker profile* (`currentRoute` output = `.builtInSpeaker`): high-pass at 150 Hz to save excursion and headroom. A **harmonic exciter on the low band**: split at 150 Hz, saturate the low copy to generate the 2nd, 3rd and 4th harmonics, and mix them back. The ear reconstructs the fundamental ([Production Expert](https://www.production-expert.com/production-expert-1/how-to-make-sure-bass-is-heard-on-small-speaker-devices), [FaderPro](https://blog.faderpro.com/mixing/mixing-bass-for-all-speaker-sizes/)). Dip 1.5–2 dB at 3 kHz, with a slight lift at 8–10 kHz.
- *Headphones profile:* full range, adding a real 50–80 Hz sub thump on contact and bottom-out. It feels luxurious on AirPods and costs nothing on speaker because it is filtered out there.
- **Weight comes from haptics.** The Taptic Engine supplies the low end the speaker can't. Pair every heavy audio event with a strong, low-sharpness transient haptic.

**Inner-screen speaker occlusion.** On a foldable that is partly closed, speaker placement relative to the fold, and the user's hands, may muffle or shift the sound as the angle changes. Verify on device; you may need gentle angle-dependent EQ compensation.

**Loudness.** Target **−16 LUFS integrated ±2, −1 dBTP**, with a loudness range of 10–15 LU. That is the IESD mobile reference ([IESD](https://www.audiogang.org/wp-content/uploads/2015/04/IESD-Mix-Ref-Levels-v03.02.pdf)); PlayStation's portable guidance is −18 ([Audiokinetic](https://audiokinetic.com/en/mastering-a-game-with-wwise-part1)). Audiokinetic's phone tests found −16 near maximum usable level ([Audiokinetic blog](https://audiokinetic.com/en/blog/loudness-and-frequency-response-on-popular-smart-phones)). Climaxes should peak about 6 LU above the strain bed; contrast matters more than absolute loudness. A master limiter prevents clipping when many grains coincide.

**Silent mode etiquette.** Obey the switch, never surprise anyone with sound, and don't nag. One first-run hint is enough. Audio stops automatically on screen lock in `.ambient`. When the phone is fully closed, the press is "done" and the sound decays naturally.

**Accessibility (12+, App Store Accessibility Nutrition Labels).**
- Apple's labels include Captions and Sufficient Contrast ([Can I Play That](https://caniplaythat.com/2025/05/13/apple-unveils-accessibility-tags-coming-to-the-app-store/), [Business Wire](https://www.businesswire.com/news/home/20250513425545/en)). With no dialogue, captions are mostly N/A. Still, offer **visual onomatopoeia** ("CRACK!", "SQUELCH", comic-style, toggleable and off by default, auto-on when the system "Closed Captions + SDH" setting is on). It works as an accessibility feature and as a shareable visual.
- Fully haptic feedback supports deaf and hard-of-hearing users.
- Respect Reduce Motion for screen shake.
- Settings: **Sound** (On/Off), **Crunch intensity** (Full/Soft: Soft low-passes at 6 kHz, halves grain density and removes wet layers, for misophonia), **Haptics** (On/Off), and **Ambient music** (if it ships).

**Repetition after 10 presses of the same object.** Mitigate with the per-press seed, layered event assembly, and grain randomisation. Test by pressing the same object 20 times in a row.

**AAC onset smear and loop clicks.** Use PCM for transients. Author loops with zero-crossing points or crossfade loops in code.

**CPU and battery.** Granular at 48 kHz with about 40 concurrent grains plus 3 loops is trivial on A-series chips. Keep the render path allocation-free, and stop the engine (`engine.pause()`) after 30 s idle.

---

## 7. Squish sound spec v0

### 7.1 Press phases

Angles are illustrative; measure θ_contact per object from its mesh height.

| Phase | Trigger | Press layers | Material layers | Haptics |
|---|---|---|---|---|
| **0. Idle (open)** | status fullyOpen, object placed | Room tone; placement "plop" (material-tinted) | Optional idle wobble for jelly or duck when touched | Light tap on place |
| **1. Approach** | θ decreasing, above θ_contact | Hiss (gain = v, cutoff 1.5→6 kHz with v); motor hum (gain 0.3 + 0.7v); no ticks yet | None | None, or faint continuous at 0.1 |
| **2. Contact** | θ crosses θ_contact | **Contact thud**: body thock plus tiny click. Hiss dips 4 dB, "taking the load" | Material contact (squeak, tap, ting, squelch) | Transient, intensity 0.6, sharpness by material |
| **3. Strain** | 0 < c < first threshold | Gauge ticks every 5°, pitch up the pentatonic; motor +0→5 st with c; procedural creak with impulse rate ∝ c | Strain loop (rate 0.85→1.35 with c, gain ∝ c^1.5 · max(v, 0.25)); occasional micro-cracks (Poisson, rate ∝ c · v) | Continuous: intensity = 0.2 + 0.6c, sharpness by material |
| **4. Failure events** | c_max crosses threshold_i (1–4 per material) | Ticks resolve to tonic on the final failure; hiss "burp" | **Layered event**: transient + body + debris, gain scaled 0.7 + 0.3v | Strong transient at 1.0 plus a 50 ms continuous "kick" |
| **5. Crush** | c beyond last threshold, closing | Motor at max, hiss tied to v | **Granular crunch or squelch bed**: rate = base · v · fresh (40–200 grains/s); re-press ("not fresh") at 25% rate and −8 dB | Continuous, intensity ∝ v |
| **6. Bottom-out** | status closed, or c ≥ 0.97 | **Ka-chunk** (fixed); motor spins down 400 ms; hiss stops | Final squish or settle one-shot; debris settle | Heavy transient plus a 150 ms decaying rumble (Toastie-like "pulse") |
| **7. Release** | θ increasing from closed | Release sigh, gain ∝ opening speed | Elastic materials (jelly, duck) give a "relax" sound; brittle ones give nothing or a faint debris trickle | Light |
| **8. Reveal** | fully open after a full press | **Reveal sting** (fixed), result-tinted "ta-da" | Short material flourish (glitter tinkle for glass, fizz for can) | Two soft taps in rhythm with the sting |
| **9. Collected** | result saved | **Collection chime** (fixed) | None | Light tap |

**Reversal mid-press:** when ω < 0 during phase 3 or 5, ramp the loops down over 150 ms, stop the ticks, and play an elastic "unload" sound if the material is elastic. Pressing forward again resumes. Cracks don't re-fire below c_max.

### 7.2 Parameter mappings

| Parameter | Formula | Range | Smoothing |
|---|---|---|---|
| Hiss gain | `smoothstep(0.05, 0.8, v)` × (phase ≤ 5) | −∞ to −14 dBFS bed | 40 ms |
| Hiss band-pass centre | `1500 · 4^v` Hz | 1.5–6 kHz | 40 ms |
| Motor pitch | `+5 st · c` (+1 st · v) | 0 to +6 st | 60 ms |
| Gauge tick | one per 5° of θ under load; note = pentatonic[floor(c · 10)] | 10 steps over ~1.5 octaves | none (event) |
| Strain loop rate | `0.85 + 0.5 · c` (±0.03 per-press seed) | ≈ −2.8 to +5.2 st | 30 ms |
| Strain loop gain | `c^1.5 · max(v, 0.25)` | 0–1 | 30 ms |
| Micro-crack rate | Poisson λ = `6 · c · v` /s, brittle materials only | 0–6/s | n/a |
| Failure threshold_i | material table ± 0.04 per-press jitter | c ∈ [0.15, 0.9] | hysteresis 0.1 |
| Event gain | `0.7 + 0.3 · v` and random −2..0 dB | | n/a |
| Grain rate | `R_mat · v · (fresh ? 1 : 0.25)` | 0–200/s | 20 ms |
| Grain pitch | `±1.5 st` random + `−2 st · c` (deeper as it flattens) | | per grain |
| Grain gain | random −6..0 dB, × (fresh ? 1 : 0.4) | | per grain |
| Haptic continuous intensity | `0.2 + 0.6 · c` (+0.2 · v during crush) | 0–1 | via sendParameters at 60 Hz |
| Haptic sharpness | material constant (glass 0.9, jelly 0.2) ± 0.1 · c | | n/a |
| Route EQ profile | `.builtInSpeaker` → speaker profile; else headphones | | switch with 200 ms crossfade |

### 7.3 Materials (10 launch objects → 8 archetypes)

| Object | Archetype | Strain bed | Failure events (thresholds c) | Crush bed | Release | Notes |
|---|---|---|---|---|---|---|
| Crayon | Brittle-waxy | Waxy creak (rubbed wax, pitched) | Snap @0.35, second snap @0.6 | Waxy crumble grains, dense and dry | None | Snap must be crisp and bright; keep the body at 400–900 Hz |
| Jelly | Gel | Wobble squish loop | Skin split @0.5 (wet "plap") | Squelch grains plus air bubbles | Elastic slurp-back | Keep it clean, not mouth-like |
| Rubber duck | Hollow rubber | Squeak, rising pitch with c (Squeaky Toys) | Comic "honk" @0.7, then seam pop @0.85 | Air-wheeze loop, rate ∝ v | Re-inflating squeak | **Comic, never distressed** |
| Cake | Soft crumb | Soft compress (foam or sponge) | Icing crack @0.3, layer collapse @0.6 | Soft crumb grains plus creamy squish | None | Lowest-intensity object, the "cosy" one |
| Soda can | Thin metal | Metal groan, pitched, plus fizz hiss | Ping-buckle @0.25, @0.45, @0.65 | Crumple grains plus modal ring (v1.1) | None | Fizz spray on the first buckle is a great reveal moment |
| Egg | Shell + wet | Shell tick micro-cracks | Shell crack @0.3 | Shell crunch plus yolk squelch | None | Two textures; crossfade crunch to wet at c > 0.6 |
| Glass bottle | Glass | Glass tick-strain (tiny ticks; no screech) | Crack @0.4, **shatter** @0.6 (biggest event in the app) | Glass grit grains | Tinkle trickle | Strictly no sustained 2–5 kHz; LPF debris at 9 kHz |
| Bubble wrap | Air pop | Plastic crinkle loop | Pops are the grains: each "bubble" in the visual sim fires one pop | Pop rain, rate ∝ v | Crinkle | Pop pitch varies by bubble size; the most ASMR-like object |
| Crisp packet *(suggested)* | Crisp | Foil crinkle | Bag pop @0.5 | Dense crisp crunch (Zampini & Spence in action) | Crinkle | Cheap to source, very satisfying |
| Grape or tomato *(suggested)* | Soft wet | Skin stretch | Skin burst @0.55 | Small juicy squish | None | Keep it light; avoid gore associations |

### 7.4 Asset list with counts

| Group | Item | Count |
|---|---|---|
| **Press (shared)** | Hiss loop (stereo; or fully synthesised) | 1 |
| | Hiss start / stop / burp one-shots | 3 + 3 + 3 |
| | Motor hum | 0 (synthesised) |
| | Procedural creak | 0 (code) |
| | Press frame groan one-shots (Metal Groans) | 4 |
| | Gauge tick | 0 (synthesised; 1 sampled click layer × 3 RR) |
| | Contact thud bodies | 4 |
| | Ka-chunk (fixed) | 1 (built from 2 layers) |
| | Release sigh | 3 |
| | Reveal sting, collection chime | 0 (synthesised, fixed) |
| | UI taps (menu, select, back) | 4 |
| | Room tone loop | 1 |
| **Per material** (×10 objects) | Placement plop | 2 |
| | Contact | 3 |
| | Strain loop | 1–2 |
| | Micro-crack or stress one-shots (brittle only) | 4–6 |
| | Failure events: transient / body / debris pools | 4 + 4 + 3 per threshold type (shared across thresholds where possible) |
| | Crush grains (auto-sliced from 2–4 source files) | 16–32 |
| | Settle or bottom-out flourish | 2 |
| | Release or relax (elastic only) | 2 |
| | Reveal flourish | 1 |
| **Totals** | Press set | about 35 files |
| | Per object | about 40–60 files (mostly grains) |
| | **App total** | **about 450–600 files**, about 4–7 MB compressed, from roughly 60–80 source recordings |

### 7.5 Four-week plan (audio track)

- **Week 1:** session, engine graph, hinge filter, parameter bus. Press shared set, partly synthesised. Grain player. Two objects: **bubble wrap** (simplest, best ASMR) and **glass bottle** (hardest, highest climax). Buy the libraries. Set up the asset pipeline scripts.
- **Week 2:** crayon, soda can, egg, jelly. Haptics integration. Route EQ profiles and exciter.
- **Week 3:** duck, cake, plus the two remaining objects. Brand sting and chime. Settings (Sound, Crunch intensity, Haptics, onomatopoeia). First founder listening sessions.
- **Week 4:** loudness pass to −16 LUFS, 20-press repetition test for every object, AirPods and Bluetooth latency test, silent-mode and interruption tests, licence folder audit.

### 7.6 Founder listening protocol (15 min per build, on device)

1. Speaker at 50% volume, then AirPods. Press each changed object three times: slowly, fast, and wobbling.
2. Rate each 1–5 on satisfying, harsh or annoying, and "sounds like what I see". Note any sound that made you wince; it is likely 2–5 kHz.
3. Press the same object 20 times. When does it get boring?
4. Silent switch on: is it still satisfying through haptics?
5. Put the results in `audio-feedback.md` with object, time and quote. The AI developer turns them into parameter changes.

---

## 8. Risks and open questions

1. **Nobody on the team is a trained listener.** This is the biggest risk. Mitigations: objective scripts, conservative EQ defaults, the founder protocol, and a few paid reviews. Consider £150–300 for one freelance sound designer to spend 2–3 hours reviewing a TestFlight build in week 3 and send back notes. That is high leverage for little money.
2. **Hinge latency and jitter are unknown until real devices arrive on 23 Oct.** If filtered latency exceeds about 60 ms, the cracks will feel late. Fallback: predict θ forward by the measured latency using velocity.
3. **Speaker position relative to the fold**, and whether audio muffles as the phone closes, is unknown. Measure on day one.
4. **What happens at fully closed.** Does the app keep running and playing audio with the inner display off? Toastie pulses haptically while closed, which suggests it does ([TechRadar](https://www.techradar.com/phones/iphone/apple-iphone-duo-review)). Confirm the lifecycle, and whether `.ambient` audio continues if the system treats closing as a screen lock.
5. **Licence details:** check the exact current terms for each pack at purchase, especially ElevenLabs output and any "no AI" clauses. Those restrict *training*, not use by an AI-assisted developer, but record your reading. Confirm FMOD and Wwise are not needed.
6. **Misophonia and 12+ tone:** test "Soft" mode with someone who dislikes eating sounds. Make sure nothing reads as gore or pain.
7. **Loudness consistency across purchased libraries.** Different vendors mean different noise floors and rooms. The shared small-room send and normalisation pipeline mitigate this but won't fix it completely.
8. **Open:** should the gauge-tick scale be the same for every object, for brand consistency, or keyed per object, for collectability? Recommendation: same scale, with a per-object timbre for the tick "tink".
9. **Open:** an ambient music loop on the collection screen. Ship without it, then A/B test it in v1.1.

---

## Sources

**Psychology and perception**
- [Barratt & Davis 2015, ASMR: a flow-like mental state (PeerJ)](https://peerj.com/articles/851)
- [Barratt, Spence & Davis 2017, Sensory determinants of ASMR (PeerJ)](https://peerj.com/articles/3846)
- [Cao et al. 2025, acoustic features of ASMR (arXiv preprint)](https://arxiv.org/abs/2504.00621v2)
- [ASMR University on Köhler's scratching-sound psychoacoustics](https://asmruniversity.com/2018/09/04/asmr-research-psychoacoustics-scratching-sounds/)
- [Newcastle University press release, Kumar et al. 2012](https://www.ncl.ac.uk/press/articles/archive/2012/10/nastynoiseswhydowerecoilatunpleasantsounds.html)
- [Psych Central on unpleasant sounds](https://psychcentral.com/news/2012/10/11/why-we-cringe-at-unpleasant-sounds)
- [Smithsonian, most annoying sound (Oehler & Reuter)](https://www.smithsonianmag.com/science-nature/what-is-the-most-annoying-sound-in-the-world-75317235/)
- [Zampini & Spence 2004, crispness and auditory cues (Oxford)](https://www.neuroscience.ox.ac.uk/publications/4405)
- [FoodNavigator, the science of crunch](https://www.foodnavigator.com/Article/2024/06/18/the-science-of-sound-what-is-it-about-the-crunch-that-keeps-snackers-dipping-in-for-more)
- [Salimpoor et al. 2011 abstract (BRAMS)](https://brams.org/2011/01/09/salimpoor/)
- [Live Science, oddly satisfying videos](https://www.livescience.com/62091-oddlysatisfying-videos-satisfying.html)
- [Vice, Hydraulic Press Channel](https://broadly.vice.com/en/article/889wez/the-hydraulic-press-channel-is-the-internet-sensation-of-our-time)
- [Vice, sand-slicing videos](https://vice.com/en/article/9k9xm7/the-oddly-satisfying-strangely-soothing-world-of-sand-slicing-videos)
- [Inverse, slicing-sand ASMR debate](https://inverse.com/article/48157-why-the-asmr-community-is-debating-those-slicing-sand-videos)
- [Misophonia prevalence, Ankara population study](https://resolve.cambridge.org/core/services/aop-cambridge-core/content/view/6ECEBA5E4EF135E099457CD7485C5F72/S2056472421009789a.pdf/the-prevalence-and-characteristics-of-misophonia-in-ankara-turkey-population-based-study.pdf)
- [ScienceAlert, misophonia more common than thought](https://www.sciencealert.com/misophonia-turns-out-to-be-way-more-common-than-we-thought)

**Game-audio technique**
- [Violet Recording, impact sounds](https://violetrecording.com/how-to-make-impact-sounds/)
- [Lior Tega, FPS gun sound design](https://www.liortega.com/post/first-person-shooter-gun-sound-design)
- [IRPR, why game audio is repetitive](https://sounddesign.irpr.agency/guides/why-is-my-game-audio-repetitive/)
- [Bugnet, footstep variation](https://bugnet.io/blog/how-to-implement-footstep-variation-to-avoid-repetition)
- [A Sound Effect, game audio immersion](https://www.asoundeffect.com/game-audio-immersion/)
- [RPG Playground, Juice it or lose it summary](https://rpgplayground.com/research-making-a-juicy-game/)
- [Brad Woods, juice notes](https://garden.bradwoods.io/notes/design/juice)
- [Audiokinetic, engine modelling and granular synthesis](https://www.audiokinetic.com/engine-sound-modeling-from-sampling-to-granular-synthesis-in-wwise)
- [Farnell, Designing Sound, creaking door patch (MIT Press)](https://mitp-content-server.mit.edu/books/content/sectbyfn/books_pres_0/8375/designing_sound.zip/practical09.html)
- [Zheng & James 2010, fracture sound (Cornell)](https://research.cs.cornell.edu/FractureSound/files/fractureSound.pdf)
- [O'Brien et al., sounds from rigid-body simulation (Berkeley slides)](https://people.eecs.berkeley.edu/~job/Classes/CS184/Fall-2016-Slides/18-Simulation.pdf)
- [Deep-Modal 2020](https://unpaywall.org/10.1145%2F3394171.3413572)
- [Titeux, Shepard and Risset illusions](https://www.nicolastiteux.com/en/blog/shepard-and-risset-audio-illusions/)

**iOS and platform**
- [iPhone Duo hinge APIs (sunyazhou)](https://www.sunyazhou.com/en/2026/09/adapting-apps-to-iphone-duo-in-ios-27/)
- [iPhone Duo SDK explained (ecorpit)](https://ecorpit.com/iphone-duo-sdk-new-apis-xcode-27-1-developer-guide-2026/)
- [daily.dev, hinge API riff](https://daily.dev/posts/a-riff-on-new-hinge-apis-for-iphone-duo-1zcrpie9g)
- [iPhone Duo by Examples (GitHub)](https://github.com/artemnovichkov/iPhone-Duo-by-Examples)
- [TechRadar iPhone Duo review (Toastie)](https://www.techradar.com/phones/iphone/apple-iphone-duo-review)
- [FoldHunt iPhone Duo apps](https://foldhunt.com/iphone-duo/)
- [Apple HIG, Playing audio](https://developer-mdn.apple.com/design/human-interface-guidelines/patterns/playing-audio)
- [Apple docs, soloAmbient](https://developer.apple.com/tutorials/data/documentation/avfaudio/avaudiosession/category-swift.struct/soloambient.md)
- [Apple Audio Session Programming Guide, categories](https://developer.apple.com/library/ios/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/AudioSessionCategoriesandModes/AudioSessionCategoriesandModes.html)
- [Apple QA1631, session preferences](https://developer.apple.com/library/ios/qa/qa1631/_index.html)
- [Apple forums, 5 ms buffer gives 256 frames](https://developer.apple.com/forums/thread/12432)
- [Apple forums, low-latency buffers](https://developer.apple.com/forums/thread/65675)
- [Apple forums, iOS 18 buffer-size bug](https://developer.apple.com/forums/thread/769245)
- [Apple forums, engine resets on configuration change](https://developer.apple.com/forums/thread/111968)
- [Apple forums, AirPods output latency](https://origin-devforums.apple.com/forums/profile/brigittaforrai)
- [Apple forums, TimePitch latency](https://developer.apple.com/forums/thread/708168)
- [WWDC19 510, AVAudioEngine and AVAudioSourceNode](https://developer.apple.com/videos/play/wwdc2019/510/)
- [Apple, Building a signal generator](https://developer.apple.com/documentation/avfaudio/building-a-signal-generator.md)
- [CHHapticEngine docs](https://developer.apple.com/documentation/corehaptics/chhapticengine.md)
- [Apple forums, haptic engine with an audio session](https://developer.apple.com/forums/thread/703326)
- [Apple forums, AHAP audio-custom crash](https://developer.apple.com/forums/thread/763640)
- [WWDC21 10278, Practice audio haptic design](https://developer.apple.com/videos/play/wwdc2021/10278)
- [Stanford UQ, no silent-switch API](https://uq.stanford.edu/answer/51eacda4-1218-4e3b-be74-8a115d2bfd1d)
- [Can I Play That, Accessibility Nutrition Labels](https://caniplaythat.com/2025/05/13/apple-unveils-accessibility-tags-coming-to-the-app-store/)
- [Business Wire, Apple accessibility announcement](https://www.businesswire.com/news/home/20250513425545/en)
- [Audiokinetic pricing for games](https://audiokinetic.com/pricing/for-games)
- [Audiokinetic, indie licence news](https://www.audiokinetic.com/about/news/audiokinetic-announces-indie-focused-limited-commercial-license)
- [Game Developer, FMOD free for small developers](https://www.gamedeveloper.com/audio/small-developers-and-creators-can-now-use-fmod-studio-for-free)
- [FMOD on Wikipedia](https://en.wikipedia.org/wiki/FMOD)
- [AudioKit](https://audiokitpro.com/audiokit/)

**Mixing and loudness**
- [IESD mix reference levels](https://www.audiogang.org/wp-content/uploads/2015/04/IESD-Mix-Ref-Levels-v03.02.pdf)
- [Audiokinetic, mastering a game with Wwise](https://audiokinetic.com/en/mastering-a-game-with-wwise-part1)
- [Audiokinetic, loudness on smartphones](https://audiokinetic.com/en/blog/loudness-and-frequency-response-on-popular-smart-phones)
- [Designing Sound, Garry Taylor on loudness](https://designingsound.org/2012/07/30/video-games-and-loudness-standards-interview-with-sonys-garry-taylor/)
- [Production Expert, bass on small speakers](https://www.production-expert.com/production-expert-1/how-to-make-sure-bass-is-heard-on-small-speaker-devices)
- [FaderPro, mixing bass for all speakers](https://blog.faderpro.com/mixing/mixing-bass-for-all-speaker-sizes/)
- [diyAudio, harmonic bass enhancement](https://www.diyaudio.com/community/goto/post?id=3693201)

**Reference games and branding**
- [Destructoid on Townscaper](https://vip-develop.destructoid.com/?p=298540)
- [Raw Fury Townscaper press release](https://gamespress.westeu-v2.propressroom.com/Oskar-Stalberg-Raw-Furys-Townscaper-Is-Now-Officially-Available-on-Nin)
- [The Sound Architect, Monument Valley](https://thesoundarchitect.co.uk/tag/monument-valley)
- [CGMagazine, Team Alto interview](https://www.cgmagonline.com/interviews/interview-with-the-team-behind-altos-odyssey)
- [Max Inferno press kit (A Little to the Left)](https://www.maxinferno.com/press)
- [Transform, sonic branding](https://transformmagazine.net/articles/2024/tiny-sounds-massive-impact-the-power-of-sonic-branding)

**Sourcing and licensing**
- [Sonniss GDC bundles and licence](https://sonniss.com/gameaudiogdc)
- [Rekkerd, Sonniss GDC 2026](https://rekkerd.org/sonniss-releases-gdc-2026-game-audio-bundle/)
- [BOOM Library FAQ](https://www.boomlibrary.com/support/faq/what-am-i-allowed-to-do-with-your-sounds/)
- [Soundly FAQ, games](https://getsoundly.com/faq/can-i-use-the-sounds-in-a-video-game)
- [Soundly EULA](https://getsoundly.com/assets/Soundly-EULA.pdf)
- [Splice licensing FAQ](https://intercom.help/splice-b7a2d5b83f2e/en/articles/8652642-splice-sounds-licensing-faq)
- [Epidemic Sound developers](https://www.epidemicsound.com/business/developers/)
- [Cinevva, game asset licences](https://app.cinevva.com/guides/game-asset-licenses.html)
- [Dupple, ElevenLabs plans](https://dupple.com/learn/is-elevenlabs-free)
- [A Sound Effect, goo and squish tag (Ultrasquish)](https://www.asoundeffect.com/product-tag/goo)
- [A Sound Effect, Flesh, Bones & Gore bundle](https://www.asoundeffect.com/?p=637210)
- [Glass Smash HD (Sonniss)](https://sonniss.com/product/glass-smash-hd-sound-effects-library)
- [Glass Breaking SFX (itch.io)](https://sound-works-12.itch.io/glass-breaking-sfx)
- [Ongelegen Aluminum Cans (Rekkerd)](https://rekkerd.org/ongelegen-releases-binaural-02-aluminum-cans-sample-pack/)
- [Squeaky Toys (itch.io)](https://soundslikegeorge.itch.io/squeaky-toys)
- [Sounds Like George (A Sound Effect)](https://asoundeffect.com/sounddesigner/Sounds-Like-George)
- [Household Source (A Sound Effect)](https://www.asoundeffect.com/sound-library/household-source)
- [MuseHub Robotics & Hydraulics](https://www.musehub.com/loops-and-audio/robotics-and-hydraulics-sound-effects)
- [A Sound Effect marketplace](https://www.asoundeffect.com/)
- [MAKE, piezo contact mic](https://makezine.com/projects/piezo-contact-mic)
- [Mental Floss, foley with food](https://www.mentalfloss.com/food/how-foley-artists-use-food-make-sound-effects)
- [Sound Ideas, fruits and vegetables](https://sound-ideas.com/blogs/sound-ideas/the-sonic-superpower-of-fruits-and-vegetables)
- [Sweep speaker-measurement app](https://apps.apple.com/app/id6784438195)
