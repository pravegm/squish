# Experience 2: making Squish the most satisfying squish on the Duo

*Lead UX research, 24 Oct 2026, the day after the founder's first real-device test. Inputs: `CLAUDE.md`, `design/SQUISH-DESIGN-BIBLE.md`, `design/FOLD-PRESS.md`, `research/04–06`, the current UI and feedback code, and a fresh web pass (sources at the end).*

**Evidence tags**
- **[S]** a study or paper.
- **[R]** a review, store listing or press report.
- **[D]** a developer or practitioner talking about their own work.
- **[I]** my inference. Validate it on the Duo.

---

## 0. What the founder told us, and what it means

The founder had two rounds of feedback.

**Round 1:** "The app works but… there is no menu, there is no sound… sound effect, vibration, everything is really key… no proper menu items, no settings, no introduction, nothing at all… the things also need to make sense… I need this to be the best squishing app for the Duo."

**Round 2:** "Satisfaction in squishing is really the biggest thing that needs to be achieved in this app." After that come three more problems: "didn't know what to do" (no intro), "couldn't find menu" and "press felt flat". The silence turned out to be the phone being on Silent (the session is `.ambient`), and that is being fixed separately.

This document is weighted the way the founder weighted it. **About 60% is about the squish itself, moment by moment (Part A).** The rest covers benchmarks, the fold, onboarding, menus and the object roster.

### 0.1 Why the press probably felt flat: a diagnosis from the code and the research

| Symptom | Likely causes in today's build | Confidence |
|---|---|---|
| **Flat press** | 1. **The sound was off.** Sound is half of "satisfying" (Part A5), and the phone was on Silent. | High (confirmed) |
| | 2. **Every sound is synthesised in code**, with no recordings. Settings even says so (`SettingsView.swift:118`). The products people praise for sound record real material: Deck-Man recorded a real Walkman's clicks, and Unpacking recorded 14,000 foley files ([TechCrunch]; [Game Developer]). Synthesised crunch tends to lack the dense 2–20 kHz detail that makes things sound crisp ([Zampini & Spence]). | High [I] |
| | 3. **The Duo's speakers are reportedly thinner and quieter** than the iPhone 18 Pro's ([9to5Mac]), so a mix tuned in the simulator will under-deliver. | Medium [R] |
| | 4. **Resistance is not legible.** Depth follows the hinge 1:1 with an ease-in curve, so the object never visibly *resists* and then *gives*. Pseudo-haptics research shows perceived stiffness comes from the ratio of visual change to hand travel ([NTT]; [Weiss et al. CHI 2023]). | Medium [I] |
| | 5. **Haptics are capped low.** The strain bed is capped at 0.7, and only failure and the ka-chunk reach 1.0 (bible §7). On an uncalibrated Duo Taptic Engine, the bed may be barely felt. | Medium [I] |
| | 6. **There's no camera response.** Fold Press rightly forbids full-screen shake, but nothing replaces it at the break: no punch-in, no lighting change, no hold. Hit stop, sound coherence and camera control are the three features most tied to good "impact feel" ([Lin et al. 2022]). | Medium [S] |
| | 7. **Hinge sample rate and latency on hardware are unknown** (≈30 Hz in the simulator). Steppy input feels dead. **Pull the Tuning Lab hinge log first.** | Unknown |
| **"Didn't know what to do"** | The first run is deliberately zero-text: a ghost arc that only shows once armed, plus a coach line after 8 s (FOLD-PRESS §7). On device, that failed. Supersonic saw the same: leaving players alone for about a minute caused confusion and churn ([Supersonic]). | High |
| **"Couldn't find menu"** | Settings is **two levels deep**: the pull-up Shelf handle, then a gear icon (`ShelfView.swift:133`). Object choice is a small chip. Hidden navigation measurably cuts discoverability, by roughly 20% in NN/g's study ([Smart Insights summary of NN/g 2016]). | High |
| **"Things need to make sense"** | Ten objects with no frame and no story. Unlock rules read as arbitrary ("earn a Perfect Squish" opens the glass bottle, but nothing teaches what a Perfect Squish is). | High |

---

## Part A: The squish, moment by moment (the priority)

One press has eight beats. Each subsection gives what the research says, then concrete, buildable changes. Angles are the current FOLD-PRESS mapping: contact ~132°, failures 96–64°, visual flat 48°, ka-chunk at the clap.

```
ARM ── APPROACH ── CONTACT ── STRAIN ── TELL ── HUSH ── BREAK ── CRUSH ── SEAL/CLAP ── REVEAL ── NEXT
168°    168→132     132°      132→~100   last 8°   60 ms   96–64°   →48°    clap         reopen
```

### A1. Anticipation and resistance: the build-up is half the pleasure

**Evidence**
- **Anticipation sets up the action.** In animation it is a principle in its own right: a preparatory move that tells you something is coming, often in several stages ([Disney's 12 principles, Linearity summary]).
- **Uncertainty is rewarding.** Uncertainty while waiting for an outcome ramps up dopamine-linked anticipation, and fully predicted rewards don't ([Fiorillo commentary]). The press is a natural "when will it go?" machine.
- **Resistance can be felt without force feedback.** A rigid surface can be made to feel compliant with tiny vibrotactile "grains" timed to pressure changes. This is Kildal's 3D-Press ([Kildal 2010 via IxDF]; [Kim ISS tutorial]). Squish's grains-per-degree layer already uses this idea.
- **Lag reads as resistance.** When the screen moves less than the hand (a lower control/display ratio), people feel more resistance and heaviness. One VR study found objects felt up to 28% softer or 9% stiffer from that ratio alone ([NTT]; [Weiss et al. CHI 2023]). **This is the single most useful lever we aren't using.**

**Build this**
1. **A resistance curve per material: "lag, then give".**
   - As compression c approaches the material's failure threshold, drop the *visual* compression gain from 1.0 to about 0.35 over the last Δc = 0.12. The object visibly falls behind your hand, so it resists.
   - At failure, release the backlog over **80 ms**. The object catches up with your hand in one lurch, and that lurch is the "give".
   - This needs no new input data. It is a remap of `renderDepth` ahead of failure, and it must never cross a fracture threshold by prediction. The engine already forbids that.
   - Stiffness ordering stays as in bible §7: glass, can, crayon, egg, duck, cake, jelly. Glass gets the deepest lag and the most violent give; jelly gets almost none, it just oozes.
2. **The tell: three escalating signs in the last ~8° before a break.**
   - *Visual:* stress whitening, plus a crack line or seam that **creeps** across the surface, with a 14 Hz micro-tremor.
   - *Audio:* the creak's pitch rises and its grain density goes from about 3/s to 15/s.
   - *Haptic:* grain spacing widens and then **stops** (the rigidity plateau), and the bed sharpens.

   This is the "it's going to go…" moment, and it is the beat Hydraulic Press Channel viewers wait for.
3. **Hold-to-tease.** If the user stops within the tell window, keep the tension alive:
   - occasional creaks every 0.6–1.2 s;
   - the tremor stays on;
   - the gauge needle quivers on the red line.

   The bible currently fades the bed to 0 on hold, which kills the tension at exactly the moment the user is savouring it. **Keep the bed at about 40% while held inside the tell window.**
4. **A pre-contact "breath".** In the last 10° before contact, the object does a tiny anticipatory squash, and the platen shadow sharpens with a soft low whoomp that rises with closing speed. The bible has this; make the sound audible, at about −20 LUFS-short-term, not room-tone quiet.

### A2. Deformation quality: something new every 5–10° of travel

**Evidence**
- **Textures and consistencies are the core** of "oddly satisfying" content, along with contrasting textures and precise fits ([Int. J. Cultural Studies 2026 via metatoc]; [Wikipedia]).
- **Object crushing is one of the most-watched satisfying genres.** In a 2,000-person US poll it tied second at 27%, with pressure washing, behind pimple popping at 33% ([Talker Research via Watauga Democrat]).
- **People value immediate, visible change.** PowerWash's designers say "satisfying" is the word players use most, and they tie it to instant, visible results ([Kotaku]).
- **Dead travel is boredom.** Today the soft headliners fail at 73–64°. That leaves roughly 60° between contact and failure where only a slow bulge happens [I].

**Build this: a deformation storyboard per object, with at least five distinct visual states between contact and flat.**

| Stage (c) | What must be visible | Example: Jelly | Example: Soda Can | Example: Egg |
|---|---|---|---|---|
| Contact (0) | contact flatten, highlight ping, the print's first kiss | top dimples; gloss highlight jumps | rim ring kisses the print | apex flattens a hair |
| Early strain (0.05–0.2) | **volume-preserving bulge** you can see at thumbnail size; surface sheen stretches | sides bulge 15%, wobble rings travel down | first buckle ring dents in, with a crisp "tink" | hairline crack starts at the apex |
| Mid strain (0.2–0.4) | secondary motion, plus the material's signature beginning | fruit pieces shift inside the gel | buckle 2, label wrinkles | hairline branches into 3 |
| Tell (last 0.08) | §A1 tell | skin goes taut, translucency rises | concertina locks, then a hiss of fizz | shell whitening, tremor |
| Break | burst, flash and debris (A4) | the skin splits and gel **extrudes from the contact edges** | puncture **geyser** of droplets that hit the platen | the shell gives and the **yolk** floods out |
| Crush (to 48°) | spread meshes grow; debris settles and **persists** | the gel sheet spreads to the plate edge | the can flattens into a disc, fizz puddle | the yolk sun spreads; shell tiles embed |

Rules:
- **Ooze leaves from the pinch line.** Real squeezed material extrudes where the gap is smallest. Spawn spread meshes and droplets from the contact edge, not the object's centre [I].
- **Mess persists and records the history.** Crumbs, stains and droplets stay through the reveal, and they appear on the card (bible §9 already says this; check it on device).
- **Contrast of states.** A crisp crust over a gooey core (cake, egg, crème-filled) is what makes a texture satisfying, so prioritise objects that have two textures.
- **Never more than 8° of travel without a new visual event**, meaning a crack, buckle, pop, droplet or ring. Count these per object in CI from the `SQUISH-H` log.

### A3. Camera and screen response on a device that *is* the camera

**Evidence**
- **Camera control is one of the top three impact features**, alongside hit stop and sound coherence. Dropping any one of the three weakens impact feel ([Lin et al. 2022]).
- **Keep shake small.** Classic juice talks add shake, flash and particles ([Juice it or lose it]; [The art of screenshake]), but large shake nauseates ([eastondev]), and on a Duo the screen is the press plate.
- **A slow, zoomed finale works.** Peggle's final-peg moment is a drum roll, a zoom and slow motion. In playtests the simpler version tested better than the louder pachinko-style one ([Wikipedia: Peggle]).

**Build this**
1. **"Camera" without moving the plates:**
   - Object-local micro-shake (1–3 px, as now).
   - A **lighting punch** at the break: the key light +30% for 60 ms, then a warm afterglow on the anvil that decays over 400 ms.
   - The platen's white flash (as now).
   - A **vignette tightening** on the anvil during the tell (0 → 12% edge darkening), so attention narrows onto the object.
2. **Real camera moves only where the plates aren't the frame:** in the reveal replay, the share clip and the P-48.
   - The reveal replay starts wide, **pushes in about 1.4×** on the break with a 0.3× slow-mo, then pulls back (the Peggle grammar).
3. **The top half reacts too.** At each fracture, stamp a mark on the print in the same frame, which is already specified. Add a small **gauge needle kick** (overshoot 6%, settle in 150 ms) at every crack. That is the "screen response" on the half you look at in tabletop.

### A4. Timing and slow motion at the break

**Evidence**
- **Hit stop has measured sweet spots.** A subjective study of action-game hit stop found the best values were about **0.1–0.2 s for big hits** and **0.2–0.4 s for slow motion**. Practitioner values are 40–80 ms for light hits and 100–180 ms for heavy hits ([hit-stop survey via bugnet/Godot tutorial]; [SciTePress 2024]).
- **Freeze only the target.** Freezing the whole game also freezes audio and UI, which feels wrong ([bugnet]). The bible's object-only rule is right.
- **Destruction needs a settle.** A crash continues for seconds as pieces tumble and come to rest. Without that settle, a sound reads as a hit rather than as destruction ([Morphic: layering]; [Sonilo]).

**Build this: the break as a fixed five-part score** (per material; the numbers are starting values to tune):

| Step | Duration | Visual | Audio | Haptic |
|---|---|---|---|---|
| 1. Hush | 50–80 ms | tremor peaks, then freezes | duck everything −12 dB; tiny inhale or creak stop | bed and grains off (silence before the hit) |
| 2. Hit stop | glass 140 ms, can/egg 110 ms, soft 70 ms | object frozen at peak strain; the platen keeps tracking the hand | — | — |
| 3. Burst | 1 frame | pieces/spray launch, flash, print splat | transient + body (A5) | **1.0 / sharpness by material**, same frame |
| 4. Slow debris | 250–400 ms at 0.3× → ramp to 1× | debris and droplets only; the object's main body stays tied to the hand | debris layer time-stretched (pre-rendered, not real-time pitch) | 3–6 decaying debris grains |
| 5. Settle | 0.8–2 s | bits roll, wobble and land; a crumb "tick" lands on the print | 4–8 tinkle/patter tails, panned, spaced, decaying | light ticks timed to visible landings |

- **Different strengths for different materials.** Bubble wrap has no single break, so each pop gets a 30 ms micro-stop on that cell. Every 6th pop gets a bigger one, which gives rhythm. The steel ball's "press cracks" break gets the longest hold of all (180 ms), because it's the joke.
- **Visual and sound land together.** The visual burst and the transient must be in the same frame (see the A5 sync budget).

### A5. Sound and haptic layering: anticipation, creak, break, release

**Evidence**
- **Sound changes how a material feels.** Making a crunch louder, or boosting only its 2–20 kHz band, made the same chip seem crisper and fresher ([Zampini & Spence 2004]).
- **Layer every impact.** Game audio practice builds each impact from a transient, a body (the mid-range part that says what the material is) and a tail (space, settle), with the transients aligned to the same frame ([Morphic]).
- **Unpacking's rules:**
  - keep sounds short, because slow ones feel laggy;
  - make them speed-dependent, so a fling sounds different from a slow move;
  - make about 10 variants per event;
  - let the softer material win when two meet;
  - give hero objects unique sounds;
  - record the real objects ([Game Developer]).
- **(Not Boring) uses a dozen slightly different versions of one click** to make software feel alive ([Launched podcast listing]). Andy Allen's view is that phones take touch away, so the app has to put it back in ([Apple: Behind the Design]).
- **Haptics carry the experience.** Vibrotactile embellishments raised enjoyment and immersion in a CHI 2021 study ([Singhal & Schneider]), and vibration matters most when the sound is off ([KoreaScience]).
- **Apple's design principles:** causality, harmony, utility. A haptic needs an obvious cause, and it has to agree with the sound and the picture ([WWDC19 810]).
- **The sync budget for active touch:** people judged audio-first offsets up to about 100–180 ms as synchronous, but haptic lag is far less tolerated. The guidance is to keep haptic delay under about 40 ms ([Lille / IEEE ToH 2023]). Passive-touch studies put synchrony at about −24 to +50 ms ([Altinsoy 2003]).
- **Small speakers can imply bass.** Adding the 2nd–4th harmonics makes the ear supply a missing fundamental ([virtual bass, UPC thesis]).
- **Loudness:** −16 LUFS is the common target for mobile and standalone devices ([Audiokinetic]; [Meta]).
- **Misophonia:** eating and chewing sounds are among the most common triggers. In one sample they were endorsed by 71% of people with misophonia and 43% of all respondents ([BJPsych Open]).

**Build this: a five-stage audio-haptic score, recorded rather than synthesised**

| Stage | Audio layers (recorded, round-robin) | Haptic layer | Notes |
|---|---|---|---|
| **Approach** | pneumatic hiss scaled with closing speed; a low hum | none (anticipation) | the hiss *is* speed feedback, as in Unpacking's velocity rule |
| **Contact** | contact thud + material contact (rubber squeak, glass tick, can tink) | kiss transient 0.4/0.3 | the first proof that the lid is "on" the object |
| **Strain** | per-material strain loop (rubber stretch, wax creak, can groan, glass creak with the 2.5–4.5 kHz squeal notched out) + **gauge ticks every 5° up the pentatonic scale** + granular crackle density ∝ speed | bed (continuous) + **grains per Δθ** (the compliance illusion) | grains stop just before the break = rigidity |
| **Break** | **transient** (snap/crack/pop) + **body** (material mass: glass ring, can crumple, egg crunch-squelch) + **debris** (shards, droplets, crumbs) + a **sub thump** written as harmonics for the speaker | 1.0 transient + 120 ms rumble | the only 1.0 event besides the clap |
| **Release / settle** | debris tails; for gooey objects a slow wet peel; a pressure-release sigh as the hinge opens | decaying light ticks | gives the destruction its ending |
| **Clap (`.closed`)** | final crunch layered under the **ka-chunk** brand sound | heavy thunk + rumble; two "ready" taps after 1.5 s | the hardware magnet clap becomes part of the sound |
| **Reveal** | peel or sigh → 3-note sting → stamp thunk | peel/crumb texture → stamp tap | peak–end: the last sound must be the best one |

**Production rules**
1. **Record or license real foley for every material** and keep code synthesis for the brand sounds (ticks, ka-chunk, sting, chime). The bible's free-first pipeline already names Sonniss GDC bundles and Freesound CC0, with slot IDs, so this is a content task, not an engine task (bible §15.1).
   - The highest-value recordings, in order: **bubble wrap pops**, **glass**, **can crumple**, **egg crack**, **squelch/goo**, **rubber squeak**.
2. **Ten variants per one-shot, and never the same one twice in a row.** Add ±1 semitone and ±2 dB jitter on top.
3. **Mix for the Duo speaker:**
   - put a lift on transients at 3–8 kHz (crispness);
   - write harmonics for anything under 150 Hz;
   - run a gentle bus compressor so the strain bed stays audible.

   Then **A/B on the real device at 50% volume**, which is how most people will hear it. If the Duo's speakers really are quieter ([9to5Mac]), raise the strain bed's short-term loudness by 3 LU on the Duo only.
4. **Loudness map:**
   - integrated −16 LUFS;
   - strain bed 10–12 LU below the break;
   - the break about 6 LU over the ka-chunk;
   - true peak −1 dBTP.

   The *contrast* between strain and break is what makes the break feel big. A loud bed flattens it.
5. **Sync budget:** haptic within ±15 ms of its sound (well inside the ~40 ms guidance). Fire both from the same code path in the same frame, as the bible already says. Measure it on device with the Tuning Lab: a high-speed phone video of the screen and a contact mic.
6. **Haptic contrast.** Lower the bed's cap to 0.55 so the break and the clap feel *bigger*. Grains are the main strain sensation; the bed is the floor. In Silent mode the haptics must tell the whole story on their own, so test a full press with the sound off.
7. **Soft mode (misophonia-safe):**
   - no wet or mouthy squelch;
   - crunch low-passed at 6 kHz;
   - half the grain density.

   Name it "Soft" in Settings, with a one-line explanation.

### A6. Variety: so press 30 still surprises

**Evidence**
- **Small, honest surprises keep a mostly predictable toy interesting.** Better-than-expected outcomes drive the reward response; exact repeats don't ([PMC review]).
- **"Each object breaks differently"** is the core promise of the crush genre, and variety of items is what Hydraulic Press Pocket players praise ([App Store: You Crush!]; [App Store: HPP]).
- **Limits:** PowerWash's core action never changes, so its variety comes from content ([Push Square]).

**Build this**
1. **The way you close changes the outcome, and the card says so.**
   - *Slow* (no reversals, under the speed threshold) gives a clean ripple of pops, an orderly crack pattern and a **Perfect Squish** stamp.
   - *Fast* gives an explosive spray with more debris and a "SLAMMED" stamp. That stamp rewards nothing extra, which keeps it safe for App Review.
   - *Pumped* (reopen mid-press and press again) gives layered rings on the print and a "PUMPED ×3" stamp.

   These are three recipes per object from one engine, and players discover them.
2. **Seeded variation that you can see:** crack paths, where the yolk lands, fizz colour, the bubble-wrap mega-bubble, the egg's toy chick.
   - Show rarity on the card, e.g. "1 in 8 eggs hide a toy chick".
   - The Golden variant stays at 1/50 with the odds disclosed.
3. **No-repeat rule everywhere:** sounds, haptic patterns, flavour lines and crack seeds. Never the same twice in a row.
4. **Stack mode (v1.2)** stays the big variety multiplier (bible §4). Pull a cheap version forward: **"Doubles"**, two of the same object side by side, which costs mostly layout work.

### A7. The payoff: make the end the best part

**Evidence**
- **People remember the peak and the end** (peak–end rule, research 04).
- **A completion flash and chime** at each finished segment gives a natural stopping point, or a nudge to go on ([egmnow via search: PowerWash]).
- **Toastie's reveal** is opening the lid; its 1.1.1 update specifically added "clearer feedback while the toastie is on the grill" ([App Store: Toastie]).

**Build this: the reveal ceremony (about 4 s, skippable by tapping)**
1. **0 ms:** the plates part on the sealed image, with goo strands snapping across the crease (as specified).
2. **300 ms:** a **slow-mo replay of the break** with a push-in (A3).
3. **2.3 s:** a **before → after** strip: the object's rest silhouette ghosted over the flattened specimen, plus a measured line, "**42 mm → 1.8 mm**", and the traits ("48 pops · Perfect").
4. **3.0 s:** the **PRESSED stamp** thunks onto the print with a sting.
5. **3.4 s:** the card files into the collection with a flash and a chime, and the **collection slot visibly fills**: a PowerWash-style completion moment.
6. **One button row:** *Again* · *Next* · *Share*. The share clip is the brag, so make it one tap.

### A8. Replay pull: "one more" without dark patterns

Build this:
- **The next object is already waiting** on a clean anvil after the reveal, like Toastie's next order, but the user still has to close the phone to press it. Changing the object is one tap.
- **Gaps are visible.** The collection shows empty, embossed slots with a *plain-English* way to fill each one (Part F).
- **Open loops on the card:** "Try it slowly for a Perfect Squish", or "1 in 8 eggs hide something…". One line, only when it's true.
- **No streaks, timers, notifications or currency.** This is unchanged from the bible.

---

## Part B: Best-in-class benchmarks, and what makes the first 60 seconds feel premium

| Product | Home / menu | Onboarding | Object selection | Progression | Reward loop | Sound / haptics | Pacing of one action |
|---|---|---|---|---|---|---|---|
| **Toastie** (Duo, $2.99) [R] | a recipe/order card; a clear "grill" step | the 15 s build per order *is* the tutorial; the fold closes the lid | 3 breads, 14 ingredients, 10 recipes | 4★ unlocks the next recipe; 5★ earns gold; a gold share card for all ten | score card per sandwich, a skill curve (TechRadar needed several tries) | the phone pulses once per second while closed; 1.1.1 added clearer grill feedback | build ~15 s, toast in real time, open to check |
| **Hydraulic Press Pocket** (HPC licence) [R] | item grid | none | 200+ items | press upgrades, IAP slots | mock comments at the end of each round (loved; also called insensitive) | — | short press, comment card |
| **You Crush! / Press Smash / Crush into Ball** [R] | level or item lists | tap and hold | dozens of items, "each breaks differently" | coins → more power; ads | coins, upgrades | ASMR claims; ads interrupt | 3–10 s |
| **Antistress – Relaxing games** (4.8★, ~98k ratings) [R] | **a big grid of 50 toys, one tap each** | none; each toy is self-explanatory | everything open | new toys every update | the variety itself | calming sounds; ad glitches that mute audio are a top complaint | toy-specific |
| **ASMR Slicing / Slice It All** [R] | level select | a hand-pointer tap demo | kinetic sand and colourful solids | coins → blades; challenge tasks (cut exactly half) | every cut shows a deformable result | "smooth ASMR sound" is the selling point | 1–3 s per cut |
| **(Not Boring) Habits** (ADA 2022) [D] | the main screen *is* the toy | none needed | — | — | one checkbox turned into a ritual: 3D, custom sound, haptics | "put back in what the screen takes away" | under 1 s, with thousands of iterations on that second |
| **Deck-Man** (Duo) [R] | browse tapes on the inner display; **close = the Walkman** | the hardware metaphor teaches itself | tapes = albums | — | — | **recorded real Walkman clicks** | the open/close *is* play/stop |
| **Orisuji** (Duo, $4.99) [R] | world map, 69 levels | levels introduce one element at a time | — | stamps for par | — | music per world | turn-based, no timers; tap/pinch fallback off-Duo |

**What the premium ones share in the first 60 seconds**
1. **The first touch does the thing.** No splash, no menu wall. The toy responds within a second (Antistress, Habits, Slice).
2. **One obvious next step,** visibly shown. A pointer hand or an order card (Slice, Toastie).
3. **A real-world metaphor,** so the controls explain themselves. Facebook's Instant Games guidance asks whether a player would know what to do within 5 seconds without reading ([Meta Instant Games best practices]). Deck-Man's lid and Toastie's toaster pass that test.
4. **Sound and touch from real material,** varied and short (Deck-Man, Unpacking, Not Boring).
5. **A visible "next" and a visible record:** the next order, the next toy, a collection slot.
6. **No ads, no asks.** Ads and their loudness are the top complaint across the free crush and antistress apps ([marlvel via search]; [Antistress listing]). Our premium model already wins here.

---

## Part C: Foldable-specific UX

### C1. What the Duo reviews teach
- **The hinge is the star.** It holds "pretty much any angle", and reviewers call opening and closing "remarkably satisfying" ([MacStories roundup]). Slow closing is natively pleasant on this hardware. **Our job is to reward the hand, not fight it.**
- **Opening is a two-handed operation** ([9to5Mac]). Coach a tabletop or two-hand book grip; never expect one-handed closing.
- **The outer display is small** (5.4") and best for quick, task-oriented use ([MacStories roundup]). It's ideal for a *lobby*, not for the press.
- **The crease can be felt.** One reviewer likes the "soothing bump" ([MacStories]). Keep the 40 pt band graphite and free of anything interactive, as FOLD-PRESS already does.
- **Continuity is expected.** Apple's guidance says the app should behave predictably and consistently inside and out, and not limit functionality to one pose ([Apple Tech Talk 111466]). Netflix's "scroll clips on the cover, open to continue" got praise for being seamless ([TechCrunch]).

### C2. Prior art on other foldables
- **Samsung Flex Mode's rule is "viewing on top, control on the bottom"**, with interactive elements kept away from the crease. Camera and YouTube are the canonical examples ([Samsung Flex Mode guide]; [Samsung designing for foldable]).
  - That matches the Duo's tabletop guidance: media on top, tappable controls on a stable base at the bottom ([Tech Talk 111466]).
  - **For Squish:** the console (bottom half, front edge) holds every control. The platen (top) carries only zero-depth feedback.
- **Android exposes posture, not a smooth angle,** through `FoldingFeature`. Continuous hinge-angle toys there are rare (research 05 §3.7). The Duo's angle API is a genuine first, and Apple invited "impressive interactions and effects" (research 05 §5).

### C3. Design implications for both postures
| Posture | The press | The UI |
|---|---|---|
| **Tabletop** (hero) | anvil on the bottom half, platen on top, as now | **all keycaps on the bottom console**; the gauge and lamps glanceable in the crown strip |
| **Book** | anvil on the trailing page, pop-up eye | keycaps on the trailing page's bottom edge, under the right thumb |
| **Closed (cover)** | sealed card after a press | **the lobby** (Part E): pick an object, see the collection, "Open to press" |

---

## Part D: Onboarding a physical gesture in under 10 seconds

### D1. What the evidence says
- **Teach by playing**, as fast as possible. Successful FTUEs get players playing quickly and teach mostly through play ([Liquid & Grit]).
- **But not with zero guidance.** Supersonic's *Trash Tycoon* gave players up to a minute without instructions, and that caused confusion and churn. The fix was a short linear tutorial with a clear goal ([Supersonic]). Squish's zero-text first run failed for the founder in exactly this way.
- **Show the gesture.** Hyper-casual games use an animated finger or arrow for the one gesture and add UI as each new mechanic arrives ([Supersonic]).
- **Text gets skipped.** Chains of instruction pop-ups overwhelm players ([PocketGamer.biz]). Clear's 7-page tutorial is the cautionary tale (research 04).

### D2. The 10-second first run (replacing bible §3.2)

| t | Inner display (phone open, any pose) | Sound / haptic |
|---|---|---|
| 0.0 s | The plates fade in. **Bubble wrap drops** onto the anvil, squashes and settles | hiss-clunk; landing tap |
| 0.8 s | **A ghost demo plays:** a large animated **folding-Duo glyph** (an SF-Symbol-style phone, 64 pt, in the console) closes slowly over 1.6 s. In sync, the platen's sheen sweeps far edge → crease and its approach shadow sharpens. The wrap's front bubbles *preview-pop* as the glyph passes "half closed". Then the glyph reopens | three soft preview pops (quiet, −24 LUFS) |
| 2.4 s | **Three words** in the console, big and rounded: **"Close it slowly"**, with a curved arrow glyph on the platen rail. A safety micro-line under it: "Nothing real goes inside." | — |
| until contact | The ghost demo repeats every 4 s *only until the hinge moves below 160°*. If the phone is fully flat on a table, add the hint "Lift the top half" | — |
| first movement | The ghost and the words fade out at once (the user is doing it) | — |
| ~121° | **The first real pop.** This is the wow moment: a big recorded pop, a crisp transient, a ring stamped on the print | 0.6 transient |
| close | A ripple of pops, the ka-chunk, the sealed cover card | as A5 |
| reopen | The reveal ceremony (A7) with "48 POPS · PERFECT" or "· SLAMMED" | sting |
| after reveal | **One** coach line on the card: "Every object breaks its own way. Tap ▦ to choose." The Objects keycap pulses once | chime |

**Rules**
- **One concept per moment:** close slowly, then "objects differ", then "your collection". There are never two hints on screen.
- **The ghost demo is a picture of the phone, not a picture of a hand,** because a hand on screen can read as "put your hand (or a real thing) here". It is a glyph in the console plus zero-depth cues on the real platen (sheen, shadow), so nothing is drawn in the air between the halves, which keeps the FOLD-PRESS bar [I].
- **Launched closed:** the cover shows the bubble wrap waiting, with a looping "open" glyph and the line "Open to press". Never block.
- **Replay it any time:** Settings → "Show me how again".

### D3. When to ask for nothing
- **Before the first reveal, ask for nothing.** That means no Game Center sign-in banner (UX-REVIEW-1 already flagged it trampling the first second), no Photos access, no notifications (never), no review prompt and no achievement toast.
- **Game Center:** authenticate silently after the third press.
- **Photos:** ask at the first "Save" tap, never at launch.
- **Review prompt:** once, after a reveal, after about 10 presses (bible §11).
- Toastie collects no data and asks for nothing ([App Store: Toastie]). That's the bar.

---

## Part E: Menus and settings: minimal, but obvious

### E1. Evidence
- **Hidden navigation measurably reduces discoverability** (about 20% in NN/g's 2016 study, per secondary summaries) and slows tasks ([Smart Insights]).
- **Xbox's guidelines:** settings must be reachable from first launch; accessibility settings ideally before any menu or cinematic ([Xbox Accessibility Guideline 112]).
- **Game Accessibility Guidelines:** let people start without navigating through multiple menu levels ([GAG]).
- **Toca Boca:** keep the UI language-light and make the characters the interface ([GamesBeat]; [MacStories]). Icons with one-word labels work across ages and languages.
- **Antistress:** a big grid of one-tap toys is the genre's home screen, and it works ([App Store]).

### E2. The structure: one home, three doors

**The press room is home.** There is no separate menu screen to wade through, but the doors are *always visible* whenever no press is under way.

```
INNER DISPLAY, idle (tabletop)                     COVER DISPLAY, closed ("the lobby")
┌──────── hazard jaw ────────┐                     ┌───────────────────────┐
│(GAUGE)   SQUISH     ● ●    │  crown strip        │  SQUISH               │
│  ┌─ platen ─┐              │                     │  ┌─────────────────┐  │
│  │  print   │              │                     │  │  [next object]  │  │
│  └──────────┘              │                     │  │   BUBBLE WRAP   │  │
╠▓▓▓▓▓▓▓▓ crease ▓▓▓▓▓▓▓▓▓▓▓╣                     │  └─────────────────┘  │
│        OBJECT on anvil     │                     │  ◀ swipe objects ▶    │
├────────────────────────────┤                     │  ▦ Collection 4/10    │
│[▦ OBJECTS][◫ COLLECTION][⚙]│  console            │  ⟲ Open to press      │
└──────── hazard jaw ────────┘                     └───────────────────────┘
```

1. **Console keycaps, with labels:** **Objects** · **Collection** · **⚙ Settings**. Text labels plus SF Symbols, always shown when idle or revealing, sliding away only while pressing (as now).
   - The gear moves *out* of the Shelf to the top level.
   - **Settings is one tap from home.** This directly fixes "couldn't find settings".
2. **Objects (the picker):** a sheet with a **big grid of large 3D thumbnails**, each with name + "breaks by…" (e.g. *Soda Can: buckles, then fizzes*).
   - Locked objects show an embossed silhouette and **a plain unlock line with progress** ("Press 3 soft things · 2/3").
   - Tapping one drops it onto the anvil and closes the sheet.
3. **Collection ("the museum"):** the specimen cabinet in wings (Part F), plus best card per object and recent presses, with share and replay. A quiet "7/10 pressed", which is not a score.
4. **Settings: one standard iOS list, plain words, one screen:**
   - **Sound**: On/Off, with a **Test** button that plays a pop. Under it: "Squish plays sound even in Silent mode" or "Follow Silent switch", per whatever the separate fix decides.
   - **Sound style**: Workshop / Soft (misophonia-safe).
   - **Haptics**: Off / Soft / Full, with a **Test** button.
   - **Press without folding**: drag instead of fold (accessibility).
   - **Show me how again**: replays D2.
   - **Reduce Motion** (follows the system), **Captions**.
   - **About**: credits, Golden odds, "No ads. No tracking."
   - Tuning Lab stays behind the long-press on Version, so it can't be found by accident.
5. **Cover lobby:** swipe between objects, tap Collection, and "Open to press". This makes the Duo's two states into "lobby → press room", the pattern Deck-Man and Netflix get praised for.

---

## Part F: "Things need to make sense": the objects, and a reason to press

### F1. What makes an object satisfying to crush
1. **Familiar,** so you can predict roughly what it will do and enjoy the details (HPC's "what will *this* do?"; research 04).
2. **Two textures or more**, like a crisp shell over a soft core. Texture and consistency are the heart of satisfying content ([Int. J. Cultural Studies 2026]).
3. **A distinct sound,** especially crisp crackle, crinkle or pop, a classic ASMR trigger ([Barratt & Davis 2015, PeerJ]).
4. **Something inside:** surprise contents drive the better-than-expected response (research 04).
5. **Visible resistance, then a give** (A1). Glass, eggs and cans deliver this; jelly doesn't (it oozes instead, which is a different pleasure).
6. **Safe for 9+:** no creatures, no faces destroyed, nothing bodily (bible §4).

### F2. Scoring today's ten

| Object | Familiar | Textures | Sound | Inside | Resist/give | Verdict |
|---|---|---|---|---|---|---|
| Bubble Wrap | ★★★ | ★ | ★★★ pops | — | ★★ per bubble | **Perfect onboarding object.** Keep it first |
| Rubber Duck | ★★★ | ★ | ★★★ squeak | — | elastic | **Keep, as the comic one** (it survives, squeaks, springs back). It teaches that not everything breaks |
| Jelly | ★★ | ★★ gel + fruit | ★★ | fruit | ooze, no give | Keep; the hero "ooze" |
| Crayon | ★★★ | ★ | ★ (thin snap) | colour core | ★★ | **Weakest.** A small object with a small payoff. Upgrade to a **Crayon Box**: 6 crayons snap in sequence and smear into a rainbow |
| Egg | ★★★ | ★★★ shell + yolk | ★★★ crack | chick / double yolk | ★★★ | **Star.** Keep |
| Cake Slice | ★★★ | ★★★ crumb + frosting + jam | ★★ | jam | ★ | Keep; make the jam squirt from the pinch line |
| Soda Can | ★★★ | ★★ | ★★★ crumple + fizz | fizz | ★★★ buckles | **Star.** Keep |
| Gummy Bear | ★★★ | ★ | ★ | rainbow layers | ★★ | **Overlaps jelly** (both gels). Differentiate it as a **Gummy Bear Stack** (3 colours that split and blend) or swap for a **Stress Ball** in v1.1 |
| Glass Bottle | ★★★ | ★ | ★★★ | message | ★★★ biggest give | **Star finale.** Keep the longest creak and biggest break |
| Steel Ball (secret) | ★★ | — | ★★ groans | — | the press loses | **Keep; the joke ending.** Frame it as the boss (below) |

**Do they make sense together?** As a material ladder, yes: pop, rubber, gel, wax, shell, crumb, thin metal, gel, glass, steel. As a *story*, no. Players see a random list of food, toys and recycling. The fix is framing, not a new roster.

### F3. A theme and a progression that tells a story

**Recommended frame: "The Museum of Pressed Things".** Squish is a press that makes *specimens*. The app already stamps PRESSED, numbers each card (№0042), prints it on paper and calls the collection a herbarium. Lean into that:
- **You're the curator.** Every press adds a specimen to the museum.
- The collection is the **museum cabinet**, in three wings plus a vault.
- The flavour line is the museum label ("*Rubber Duck. Survived. Squeaks under protest.*").

| Wing | Objects | Teaches | Opens |
|---|---|---|---|
| **1. Soft Things** | Bubble Wrap, Rubber Duck, Jelly, Cake Slice | squish, pop, ooze; "close slowly" | open from the start |
| **2. Crunchy & Cracking** | Egg, Crayon Box, Gummy Stack | crack, snap, surprise insides | open from the start (endowed progress, research 04) |
| **3. Tough Stuff** | Soda Can, Glass Bottle | resistance, then the big give | "Press 3 different things" → Can; "Press anything *slowly*" → Glass. The card says what slow means, and the gauge shows "SLOW ✓" live |
| **The Vault** | The Unsquishable (steel ball) | the press can lose | "Fill every wing" |

- **The escalation tells the story:** soft → crunchy → tough → impossible. It's the HPC arc ("how strong is it?") in four steps, and it ends on a joke.
- **Every unlock line is plain English with live progress.**
- **Future drops fill new wings,** each a new *behaviour* (bible §4), announced as In-App Events. Prioritise them by the satisfaction research:
  1. **Soap Bar** (soap cutting is a satisfying staple; [Wikipedia]);
  2. **Slime/Putty** (texture; [Wired via Wikipedia]);
  3. **Crisps Packet** (pop, then crunch, the crispness study);
  4. **Water Balloon**;
  5. **Piñata** (contents);
  6. **Marshmallow** (slow rise on reopen);
  7. **Ice Cube** (crack, then melt).

---

## Part G: Ranked: the 15 highest-impact changes

Ranked by expected impact on "satisfaction in squishing" first (the founder's top issue), then by intro, menu and sense-making. Each change lists its evidence and the scope to build it.

| # | Change | Evidence | Build scope |
|---|---|---|---|
| **1** | **Replace synthesised material sounds with recorded, layered foley**: transient + body + debris + settle, ~10 variants per event, mixed for the Duo speaker (3–8 kHz crispness lift, harmonic bass). Keep code synthesis only for brand sounds. | Louder or brighter crunch makes things seem crisper ([Zampini & Spence]); Unpacking's recorded foley and variant rules ([Game Developer]); Deck-Man's recorded clicks ([TechCrunch]); sound coherence is a top-3 impact feature ([Lin et al.]); thinner Duo speakers ([9to5Mac]) | Content + mixing; the slot manifest exists (bible §15.1). Feedback owner |
| **2** | **"Lag, then give" resistance:** visual compression gain drops to ~0.35 in the last Δc 0.12 before failure, then the backlog releases in 80 ms at the break. Grains widen, then stop. | Control/display ratio changes perceived stiffness by up to 28% ([Weiss et al. CHI 2023]; [NTT]); compliance from vibrotactile grains ([Kildal 2010]); anticipation ([Disney principles]) | A remap in `PressDirector`/the scene before render; no input change. Core + Scene |
| **3** | **Choreograph the break as a 5-part score:** hush 50–80 ms → object-only hit stop 70–140 ms → same-frame burst + flash + 1.0 haptic → debris 0.3× for 250–400 ms → 1–2 s settle of tumbling bits and tails. | Hit stop 0.1–0.2 s and slow-mo 0.2–0.4 s are optimal ([SciTePress 2024]; [bugnet]); hit stop is a top-3 impact feature ([Lin et al.]); destruction needs a settle ([Morphic]) | Scene fx + Feedback cue timing |
| **4** | **A deformation storyboard per object, with a new visible event at least every 8° of travel**: bulge, stretched sheen, creeping cracks, ooze extruding *from the pinch line*, splatter that sticks to the print, persistent mess. | Textures and consistencies are the core of satisfying content ([Int. J. Cultural Studies 2026]); instant visible change drives "satisfying" ([Kotaku: PowerWash]); crushing ties 2nd among satisfying genres ([Talker Research]) | Objects + Kit; a CI check counting events per 8° from `SQUISH-H` |
| **5** | **A 10-second taught first run:** the bubble wrap drops, a folding-Duo glyph demo with a synced platen sweep and preview pops, three words ("Close it slowly"), repeated until the hinge moves; the first real pop by ~121°. Replay from Settings. | Founder: "didn't know what to do"; no-guidance openings cause confusion and churn ([Supersonic]); the 5-second test ([Meta Instant Games]); teach through play ([Liquid & Grit]) | UI + PressHints; small |
| **6** | **Always-visible labelled doors:** Objects · Collection · ⚙ Settings on the console whenever idle; Settings one tap from home; sound and haptics Test buttons; "Show me how again". | Founder couldn't find settings; hidden navigation cuts discoverability by ~20% ([NN/g via Smart Insights]); settings reachable from first launch ([Xbox XAG 112]); no multi-level menus ([GAG]) | UI; small |
| **7** | **Recalibrate haptics for the Duo and raise contrast:** bed cap 0.55, grains as the main strain sensation, the break and the clap at 1.0. Haptic within ±15 ms of its sound. Do a full press with the sound off: it must still satisfy. | Haptics raise enjoyment ([Singhal & Schneider CHI 2021]); they matter most when muted ([KoreaScience]); haptic lag tolerance is ~40 ms ([IEEE ToH 2023]); causality and harmony ([WWDC19 810]) | Feedback + a Tuning Lab ladder on device |
| **8** | **The reveal ceremony:** a slow-mo replay that pushes in on the break, then before → after with a measurement ("42 mm → 1.8 mm"), the stamp + sting, and a collection slot that visibly fills with a flash and a chime. One row: Again · Next · Share. | The peak–end rule (research 04); Peggle's zoom + slow-mo finale, kept simple ([Wikipedia: Peggle]); PowerWash's completion flash and ding ([egmnow/Kotaku]) | UI reveal + Scene replay camera |
| **9** | **Tension you can hold:** a tell window (stress whitening, a creeping crack, a 14 Hz tremor, the creak rising, the gauge on the red line), and **the tension stays alive while the hinge is held still** (bed ~40%, creaks every 0.6–1.2 s) instead of fading out. | Anticipation ([Disney]); uncertainty drives anticipation ([Fiorillo]); bible §7 currently fades the bed on hold, which kills the savour [I] | Feedback + Scene; small |
| **10** | **Frame the roster as "The Museum of Pressed Things":** three wings that escalate (soft → crunchy → tough) plus a vault (the steel ball), unlock lines in plain words with live progress, and museum-label flavour lines. | "What will *this* do?" curiosity (HPC, research 04); variety is what HPP players praise ([App Store: HPP]); endowed progress (research 04); founder: "things need to make sense" | Collection + UI copy; small |
| **11** | **How you close changes the result, and the card says so:** Slow gives a clean ripple and a Perfect stamp; Fast gives a spray and a SLAMMED stamp (no reward); Pumped gives layered rings and a PUMPED ×N stamp. | Speed-dependent sound and outcome ([Unpacking]); Toastie's timing skill axis ([App Store: Toastie]); agency in the wreck ([Burnout 3]) | Core traits + Scene recipes |
| **12** | **The variety engine:** seeded crack paths and debris, a visible rarity line ("1 in 8 eggs hide a toy chick"), Golden 1/50 disclosed, and a no-repeat rule for every sound, haptic and flavour line. | Better-than-expected rewards ([PMC review]); about 10 variants per event ([Unpacking]); a dozen versions of one click ([Not Boring/Launched]) | Core variants + Feedback round-robin |
| **13** | **The cover display as the lobby:** pick the next object, see collection progress, "Open to press"; a sealed card after a press; a release card on reopen. | Cover browse → open to continue is praised ([TechCrunch: Netflix, Deck-Man]); Apple: predictable and consistent inside and out ([Tech Talk 111466]); Toastie's cover is the lid with its lamp ([FoldHunt]) | UI CoverView; medium |
| **14** | **Ask for nothing before the first reveal:** no Game Center banner (authenticate after press 3), no Photos prompt until the first Save, no review prompt before about 10 presses, no achievement toast in the first press. | Toastie collects no data ([App Store]); FTUE: get people playing first ([Liquid & Grit]); UX-REVIEW-1 P1-7 (the Game Center banner over the first run) | App/UI; tiny |
| **15** | **Roster fixes and loudness comfort:** Crayon → Crayon Box (a rainbow smear); differentiate the gummy from the jelly (a Gummy Stack); next drops in research order (soap, putty, crisps, water balloon, piñata). Loudness at −16 LUFS integrated, the strain bed 10–12 LU under the break; a Soft mode with no mouthy crunch. | Crisp-crinkle ASMR triggers ([Barratt & Davis]); texture research; the −16 LUFS mobile target ([Audiokinetic]; [Meta]); chewing is a top misophonia trigger, up to 71% ([BJPsych Open]) | Objects + Feedback mix |

**Do first, before tuning anything:** pull the **Tuning Lab hinge log** from the founder's Duo (Settings → long-press Version). Check the sample rate, latency and display-off angle. If samples arrive at about 10 Hz, items 2–4 will feel steppy whatever we do, and the One-Euro and spring settings need retuning first (research 05 §3.5).

**Suggested next round:** items 1, 2, 3, 5 and 6 in parallel, with disjoint owners:
- Feedback owns 1 and 7.
- Core and Scene own 2, 3 and 9.
- UI owns 5, 6 and 14.
- Objects own 4, one object at a time, starting with Egg, Soda Can and Bubble Wrap.

Then a founder device session with the **15-minute listening and feel protocol** (bible §8). Use three questions:
1. "Did it resist?"
2. "Did the break land?"
3. "Did you want another?"

---

## Sources

**Duo, Toastie and Duo apps**
- [App Store: Toastie (PL listing; ratings, version notes)](https://apps.apple.com/pl/app/toastie/id6813841355)
- [TechCrunch: These clever apps show off the iPhone Duo's potential (24 Oct 2026)](https://techcrunch.com/2026/10/24/these-clever-apps-show-off-the-iphone-duos-potential/)
- [TechCrunch: Duo-Man / Deck-Man virtual Walkman](https://techcrunch.com/2026/09/28/the-iphone-duo-may-already-have-its-first-killer-app-a-virtual-walkman/)
- [Gulf News: Walkman app and recorded sounds](https://gulfnews.com/technology/media/viral-app-turns-apples-foldable-iphone-into-a-walkman-and-2-million-people-watched-1.500693709)
- [App Store story: Great Apps and Games on iPhone Duo](https://apps.apple.com/us/iphone/story/id6820639500)
- [FoldHunt: Toastie](https://foldhunt.com/games/toastie/)
- [PocketGamer: Orisuji](https://pocketgamer.com/orisuji/announcement)
- [TechRadar: iPhone Duo review](https://www.techradar.com/phones/iphone/apple-iphone-duo-review)
- [9to5Mac: iPhone Duo review](https://9to5mac.com/2026/10/21/iphone-duo-review/)
- [MacStories: iPhone Duo review roundup](https://www.macstories.net/roundups/iphone-duo-review-roundup-great-hinge-messy-apps-and-everybody-misses-face-id/)
- [Gizmodo: iPhone Duo review](https://gizmodo.com/iphone-duo-review-2000827502)
- [Apple Tech Talk 111466: Design for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111466/)
- [PhoneArena: best iPhone Duo apps and games](https://www.phonearena.com/news/the-best-iphone-duo-apps-games_id184282)
- [Stuff: a week with the iPhone Duo](https://www.stuff.tv/features/ive-spent-a-week-with-the-apple-iphone-duo-heres-what-i-have-learned-and-the-two-things-id-change/)

**Other foldables**
- [Samsung: Foldable exclusive – Flex Mode](https://developer.samsung.com/one-ui/foldable-and-largescreen/foldable-excl-flex.html)
- [Samsung: Designing for foldable](https://developer.samsung.com/one-ui/largescreen-and-foldable/designing_for_foldable.html)
- [Samsung: Adapt your app for Galaxy Flex Mode](https://developer.samsung.com/sdp/blog/en/2021/01/11/adapt-your-app-for-galaxy-flex-mode)

**Crush, satisfying and fidget apps**
- [App Store: Hydraulic Press Pocket](https://apps.apple.com/us/app/hydraulic-press-pocket/id1224226281)
- [App Store: You Crush!](https://apps.apple.com/app/id1504850272)
- [App Store: Press Smash](https://apps.apple.com/app/id1436985369)
- [App Store: Crush into ball](https://apps.apple.com/app/id1580960059)
- [App Store: Antistress – Relaxing games](https://apps.apple.com/app/id1207565651)
- [Justuseapp: Antistress reviews](https://justuseapp.com/en/app/1438709018/antistress-anxiety-relief-game/reviews)
- [marlvel: Fidget Pro review audit](https://marlvel.ai/api/llm/apps/productivity/fidget-pro-relaxing-games)
- [App Store: ASMR Slicing](https://apps.apple.com/us/app/-/id6752538148)
- [Nintendo: ASMR Slicing](https://www.nintendo.com/store/products/asmr-slicing-complete-edition-switch)
- [App Store: Slice It All](https://apps.apple.com/app/1556238786)
- [App Store: Fidget Toys 3D](https://apps.apple.com/app/id6443625107)

**Design-award and craft references**
- [Apple: Behind the Design, (Not Boring) Habits](https://developer.apple.com/news/?id=9ab1g4r3)
- [Launched podcast (Andy Allen, sound and haptics)](https://podcastaddict.com/launched/episode/227394462)
- [TechCrunch: 2025 Apple Design Awards](https://techcrunch.com/2025/06/04/apple-names-2025-design-awards-winners)
- [Kotaku: PowerWash Simulator devs](https://kotaku.com/powerwash-sim-devs-on-making-cleaning-fun-advanced-cro-1847319502)
- [egmnow: PowerWash Simulator](https://egmnow.com/powerwash-simulator-feels-perfectly-numbingly-mindless/)
- [Push Square: PowerWash Simulator review](https://www.pushsquare.com/reviews/ps5/powerwash-simulator)
- [Wikipedia: Peggle (Extreme Fever design history)](https://en.wikipedia.org/wiki/Peggle)
- [GamesRadar: Peggle review](https://www.gamesradar.com/peggle-10/)
- [Wikipedia: Burnout 3](https://en.wikipedia.org/wiki/Burnout_3:_Takedown)
- [GamesBeat: Toca Boca](https://gamesbeat.com/how-toca-boca-got-100m-mobile-downloads-by-putting-kids-first/)
- [MacStories: Characters as an interface](https://www.macstories.net/linked/characters-as-an-interface/)

**Game feel, impact and timing**
- [Lin et al. 2022: What Features Influence Impact Feel? (arXiv)](https://arxiv.org/abs/2208.06155)
- [SciTePress 2024: Dynamic hit stop using eye gaze](https://scitepress.org/PublishedPapers/2024/124614)
- [bugnet: fixing hitstop](https://bugnet.io/blog/how-to-fix-hitstop-or-freeze-frame-feeling-off)
- [Godot forum: hit-stop and screen-shake tutorial](https://forum.godotengine.org/t/tutorial-hit-stop-and-screen-shake-in-godot-4-autoload-trauma-camera-mit/145240)
- [eastondev: Where does game feel come from](https://eastondev.com/blog/en/posts/dev/20260521-game-feedback-feel/)
- [Juice it or lose it (Jonasson & Purho, GDC 2012), via Wayline](https://www.wayline.io/learn/game-feel/1)
- [The art of screenshake (Nijman), recreation devlog](https://dkliao.itch.io/the-art-of-screenshake-recreation/devlog)
- [Linearity: Disney's 12 principles of animation](https://linearity.io/blog/12-principles-of-animation)

**Sound, haptics and perception**
- [Zampini & Spence 2004: auditory cues and chip crispness (Oxford)](https://www.neuroscience.ox.ac.uk/publications/4405)
- [Game Developer: Auditory tales from the making of Unpacking](https://www.gamedeveloper.com/marketing/auditory-tales-from-the-making-of-zen-puzzler-unpacking)
- [NME: Unpacking's 14,000 sound files](https://www.nme.com/news/unpacking-features-over-14000-sound-effect-files-3087521)
- [Morphic: How to layer sound effects](https://morphic.com/resources/how-to/how-to-layer-sound-effects)
- [Sonilo: explosion/impact sound guide](https://sonilo.com/ai-music/explosion-sound-effect-guide)
- [Apple WWDC19 810: Designing Audio-Haptic Experiences](https://developer.apple.com/videos/play/wwdc2019/810)
- [Apple WWDC21 10278: Practice audio haptic design](https://developer.apple.com/videos/play/wwdc2021/10278)
- [Singhal & Schneider, CHI 2021: Juicy haptic design](https://uwaterloo.ca/haptic-experience-lab/projects/juicy-haptic-design-vibrotactile-embellishments-can-improve)
- [KoreaScience: vibration and hedonic satisfaction](https://koreascience.or.kr/article/JAKO201326952132747.pdf)
- [Kildal 2010: 3D-Press (IxDF author page)](https://ixdf.org/literature/author/johan-kildal)
- [Kim et al.: Surface haptics ISS tutorial (Aalto)](https://acris.aalto.fi/ws/portalfiles/portal/39632842/ELEC_Kim_Surface_haptics_ISS.pdf)
- [Weiss et al. CHI 2023: pseudo-stiffness (LMU)](https://www.medien.ifi.lmu.de/pubdb/publications/pub/weiss2023usingpseudostiffness/weiss2023usingpseudostiffness.pdf)
- [NTT: pseudo-haptics and perceived resistance](https://www.rd.ntt/e/research/JN202101_9679.html)
- [Lille / IEEE ToH 2023: audio-tactile delay thresholds (Zenodo)](https://zenodo.org/record/7554917)
- [Lille thesis 2024: audio-tactile delays](https://pepite-depot.univ-lille.fr/LIBRE/EDENGSYS/2024/2024ULILN002.pdf)
- [Altinsoy 2003: auditory-tactile asynchrony](https://tu-dresden.de/ing/elektrotechnik/ias/aha/ressourcen/dateien/professur/publikationen/Altinsoy2003_-_Perceptual_aspects_of_auditory-tactile_asynchrony.pdf)
- [UPC: virtual bass systems for small loudspeakers](https://upcommons.upc.edu/entities/publication/53beaf2b-6dbb-4628-b2f4-e8549f05184f)
- [Audiokinetic: loudness on popular smartphones](https://audiokinetic.com/en/blog/loudness-and-frequency-response-on-popular-smart-phones)
- [Meta: audio loudness meter (−16 LUFS standalone)](https://developers.meta.com/horizon/documentation/unity/audio-loudness-meter-overview/)
- [BJPsych Open: misophonic sounds table](https://pmc.ncbi.nlm.nih.gov/articles/PMC8358974/table/tab02)
- [Barratt & Davis 2015: ASMR (PeerJ, MMU repository)](https://e-space.mmu.ac.uk/617640)
- [PMC: reward prediction error review](https://pmc.ncbi.nlm.nih.gov/articles/PMC10116860/)
- [Nature Reviews Neuroscience: Fiorillo et al. commentary](https://www.nature.com/articles/nrn1127)

**Satisfying content**
- [Wikipedia: Oddly satisfying videos](https://en.wikipedia.org/wiki/Oddly_satisfying_videos)
- [Int. J. Cultural Studies 2026: Scroll, watch, feel (metatoc)](https://metatoc.com/papers/140997-scroll-watch-feel-the-sensory-politics-of-embodied-spectatorship-in-oddly-satisfying-content)
- [Talker Research poll via Watauga Democrat: genre ranking](https://www.wataugademocrat.com/lifestyles/health/americans-spend-156-hours-watching-these-oddly-satisfying-clips/article_b3ecac6d-9e20-5ea5-9f9f-a3f4c7ef890f.html)
- [Wikipedia: Hydraulic Press Channel](https://en.wikipedia.org/wiki/Hydraulic_Press_Channel)

**Onboarding, menus and accessibility**
- [Supersonic: optimizing FTUE (Trash Tycoon)](https://supersonic.com/learn/blog/optimizing-ftue/)
- [Liquid & Grit: FTUE toolkit](https://liquidandgrit.com/first-time-user-experience-ftue-toolkit)
- [Meta: Instant Games best practices (5-second test)](https://developers.facebook.com/documentation/games/overview/best-practices)
- [PocketGamer.biz: enhancing the first-time user experience](https://www.pocketgamer.biz/pgc-digital-how-to-enhance-the-first-time-user-experience)
- [Smart Insights: NN/g hidden-navigation study summary](https://www.smartinsights.com/digital-marketing-strategy/are-hamburger-menus-hidden-navigation-good-for-ux/)
- [Xbox Accessibility Guideline 112](https://devdocs.xbox.com/gaming/accessibility/xbox-accessibility-guidelines/112)
- [Game Accessibility Guidelines](https://gameaccessibilityguidelines.com/?p=21)

**Internal:** `research/04-psychology-ux.md`, `05-hinge-ux.md`, `06-market.md`; `design/SQUISH-DESIGN-BIBLE.md` §3, §4, §7, §8, §11, §15.1; `design/FOLD-PRESS.md` §4, §6, §7; `design/UX-REVIEW-1.md`; `Squish/UI/SettingsView.swift:118`; `Squish/UI/ShelfView.swift:133`; `Squish/Feedback/AudioController.swift:40`.
