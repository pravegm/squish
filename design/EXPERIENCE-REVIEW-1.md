# Experience Review 1: the rebuild, judged against the founder's bar

*Design critic, 25 Oct 2026. This is the first critique since the experience rebuild (EXPERIENCE-PLAN, UX-AUDIT-2, EXPERIENCE-2, APPLE-DUO-GUIDE, OBJECT-STORYBOARDS, SOUND-2, FOLD-PRESS §9.8.1). The last critique was FOLD-REVIEW-9, written before the founder held a Duo.*

**Inputs, all viewed:**
- **`art-after/`**: all 10 objects at 180/100/75/60, closed (cover) and reveal, in book pose. Tabletop sweeps for the duck, gummy and jelly. The duck's book-pose eye renders.
- **`duo2/`**: lesson, menu, tray (book and tabletop), settings (book and tabletop), achievements, help, shelf, cover launch; crayon and glass 180/60/closed/reveal; jelly tabletop; `verify/` toasts.
- **`duo1/`**: the earlier UI pass.

**Code read:**
- `Squish/Feedback/*`: `FeedbackTuning`, `HapticsController`, `AudioController`, `HingeFeel`, `CueBook`, `SampleVoicing`;
- `Core/PressFeel`, `PressConfig`, `MaterialProfile`, `PressEngine` (seal path);
- `UI/RevealCeremony`, `RevealCardView`, `FoldLesson` (coach lines);
- `Scene/PressSceneView` (touch), `Contracts.tons`;
- `sounds-manifest.json`, `SOUND-2.md`.

**Read this first: the frames are not all the current build.**
- **`art-after` ran at ~01:10 (+04:00) on 25 Oct.** That is *before*:
  - the sync fix (`6d9effc`);
  - the founder's display-off mapping (`ef7e476`: contact 104°, flat by 55°, shut 10°);
  - Strong-by-default haptics (`cb27e31`);
  - the console and ticket truncation fixes (`56f8c7d`, `71d30be`, `5ceb590`, `cd3a877`).

  So the "Me…", "RUBBER…", "NEW: GLASS BOT…" truncations and the crowded old ticket in those frames are already fixed. I mark them as such.
- **`duo2` ran at ~04:30**, at about `5ceb590`. That is the UI and ticket of record here.
- **Everything about feel is judged from code.** I can't hear or feel the app, and nobody on the team has heard the 274 samples either (SOUND-2, Status).
- **My scores are on the founder's scale, not FOLD-REVIEW-9's.** R9's 8.7 judged screenshots. These scores judge whether a person pressing the phone would call it "the best squishing app for the Duo". They are not comparable, and they are lower on purpose.

---

## 1. Verdict

| | Score | One line |
|---|---|---|
| **The press moment** | **6 / 10** | A thoroughly engineered press that still mostly *shows you the result* instead of making you *feel the fight*: the resistance was traded away for sync, the break is busy, and the climax shares the screen with a text toast. |
| **The overall experience** | **7 / 10** | The product finally has a front door, a menu, a museum and real foley. The squish itself is not yet the best thing in it. |

**Would this be "the best squishing app for the Duo"?**
- **On the Duo, probably yes by default.** Nothing else has a hinge-driven press with:
  - recorded foley and audio-derived haptics;
  - a five-part break score;
  - a reveal ceremony;
  - a cover display that tracks the seal.
- **Against the founder's own bar, no, not yet.** "Satisfaction in squishing" comes down to three things the frames and code can't yet promise:
  1. **The object visibly fights, then gives.**
  2. **The break owns the moment, alone.**
  3. **The crushed thing looks like that thing, crushed.**

  Today 1 is mostly gone (the lag is now a quarter of a degree), 2 is diluted (a coach toast, a 135–205 ms delay, a haptic bed already near 1.0), and 3 holds for about half the roster.

**What improved since R9 and UX-AUDIT-2 (real wins; keep them):**
- **Three labelled doors** on the console: MENU, Shelf and the gear (`duo2` lesson and menu frames). The founder's "couldn't find the menu" is fixed.
- **A taught first run.** The lesson card names the pose, explains Silent mode and gives the safety line in the footer, not the headline.
- **The Museum tray:** verbs, stiffness pips, three goal slots and plain unlock lines with progress. It's the best screen in the app.
- **Settings as a two-page spread:**
  - "Play when phone is on Silent", default on;
  - test sound and test vibration;
  - Vibration strength;
  - Replay intro;
  - Sound & vibration check.
- **Cover states: SEALING… / KA-CHUNK! / RELEASING….** The print spoiler is gone: the sealed card shows a silhouette under WHAT'S LEFT?.
- **The reveal ceremony exists:**
  - the lid lifts;
  - a slow-mo replay with push-in (`PressScene.replayFocus`);
  - the measured before → after;
  - tons count up;
  - the museum slot flashes and chimes;
  - FOLD TO KEEP appears only after 2.5 s.
- **The architecture of sound and touch is right:**
  - one cue for both controllers (`CueBook`), so they share every random choice;
  - haptics derived from the audio's real onsets;
  - beds driven at display rate from `HingeTracker`;
  - a held press that keeps its tension.

---

## 2. Beat by beat against the EXPERIENCE-PLAN table

| Beat | Mark | Evidence | What's wrong |
|---|---|---|---|
| **Anticipation** | **ok** | The platen's soft approach shadow is there at 180 (`a-*-180`: a blurred object-shaped shade on the lid plate). The hinge layer adds a creak by angular velocity, detents every 6° and power-up/down (`HingeFeel.swift`). | **Nothing on screen anticipates *in the object*.** Idle life is transform-only and fades out as the lid closes; a still frame can't show it. **The creak is "the quietest thing in the mix"** (≈ −40 dBFS before master, `HingeFeel` header). On a thin Duo speaker that may be inaudible, so anticipation is effectively a shadow. **The angle readout ("180°") is the most prominent moving thing on the lid.** |
| **Contact** | **ok** | At 100° every object shows the "kiss": the print's first dot on the lid, LOAD amber, the coach toast "FEEL IT PUSH BACK · It's touching. Keep going." (`a-*-100`). Contact is at 104°, with `BrandCues.contact` voiced by `press_contact_soft`. | **The words do the work the feel should do.** "It's touching" is the app admitting the contact isn't legible. **`press_contact_soft` is "~100 Hz and relies on the exciter"** (SOUND-2 §7 risks), so on the speaker contact may be felt but not heard. **At 100° the anvil object is visually unchanged for duck, can, egg and glass**; only the print says something happened. |
| **Resistance ("lag, then give")** | **weak** | The sync fix cut `PressResistance` to gain 0.85–0.95 over the last 0.03 c (`PressFeel.swift:207–220`): a maximum trail of ~0.0045 c, a quarter of a degree. In the frames, duck, can, egg and glass look nearly the same at 100 and 75 (`a-rubberDuck-75`, `a-sodaCan-75`, `a-egg-100`, `a-glassBottle-100`). Storyboard beats fire every ≤ 4.5° (good) but are tiny from the Duo's view: neck creases, label chevrons, a lip fleck. | **The plan's #2 lever is gone.** It went for a good reason (the founder said the screen must move with the hand), but nothing visual replaced it. The object follows the hand like a tracked mesh. It doesn't *fight*. The resistance is now carried only by sound and haptic beds nobody has felt yet. See Top-10 #1. |
| **Tell** | **ok (on paper)** | `PressTell` fires ~250 ms ahead. `BeatCues.story(.tell)` gives a 1.6× creak spike plus a 0.18 s haptic swell, the haptics run a 14 Hz tremor player, and micro-cracks run in lockstep in both controllers. | **Invisible in every frame**, which is expected for a 0.15–0.35 s event. But the visual tremor is 14 Hz at object-local, mm-scale amplitude: probably imperceptible at arm's length on a grazing anvil. On Strong the haptic swell (0.3) sits *under* a bed already at 0.8–1.0 (§5), so it may not read as a swell at all. |
| **Break** | **ok** | The five parts are implemented as specified (`BreakScore.of`): hush 65 ms → hit stop 70–140 ms → burst (flash, 1.0 haptic, sound in one cue) → 0.3× debris 250–400 ms → 1–2 s settle with ticks. The frames show real events: the glass heap and crack-web print (`a-glassBottle-75`), the egg's fried-egg flood at 92° (`a-egg-75`), the jelly splat (`a-jelly-60`), the gummy split with strands (`a-gummyBear-75`). | **(a) Late by design.** The burst lands 135–205 ms after the hand crosses the threshold. On a 40°/s close that's 5–8° of travel. After a sync fix the founder asked for, a break that trails the hand may read as lag, not drama (founder question 2). **(b) Not alone.** The coach toast switches to "ALL THE WAY · Shut it all the way to seal the press." the instant `failed` is true (`FoldLesson.swift:261`), so the break shares the screen with text. That's in every 75/60 frame for the first five presses. **(c) No give.** The backlog to release is a quarter of a degree, so the "lurch" is nil. |
| **Flatten and seal** | **ok** | Persistent mess shows: jelly lobes and stains, can fizz droplets, egg white, gummy beads (`a-*-60`, `-reveal`). The ka-chunk is strong: a synth latch and thock with the recorded `press_kachunk_latch` + `_metal` under it, on the cover as KA-CHUNK! / PRESS SEALED / nn TONS (`a-*-closed`, `u-glassBottle-closed`). | **The dead stroke.** The crush is flat by 55° (`PressConfig.endAngle`), the display goes dark at ~45°, and the ka-chunk waits for ≤ 10°. So ~45° of travel (1–2 s on the founder's 25–60°/s slow close) has no new event. Only the crush bed runs (and on Bubble Wrap the strain bed, pinned near maximum, since it never "fails"). The frozen screen from 55–45° then goes dark. The plan said "persistent splatter and ooze **from the pinch line**". In the frames, ooze and droplets come off the *outer* edge, and gummy halves leave the plate entirely (`a-gummyBear-60`, right half past x ≈ 1390). |
| **Reveal ceremony** | **ok** | Lid shade lift, slow-mo replay with push-in, ticket slide, before → after count-down ("36 mm → 6.5 mm"), stamp, tons count-up, badges one by one, museum slot flash + chime, FOLD TO KEEP after 2.5 s (`RevealCardView.runCeremony`, `u-crayon-reveal`, `u-glassBottle-reveal`, `u-jelly-tabletop-reveal`). The new ticket (`cd3a877`) is calm and readable. | **(a) The replay is silent.** `PressScene.applyReplayMark` re-runs the visuals only; no cue is fired. The peak–end moment is a mute film of the thing you just heard, so the reveal's best two seconds have no sound and no touch. **(b) Leftover instruments.** The crown nameplate still freezes the failure angle in red ("69°", "83°", "90°") while the needle sits at 0. UX-AUDIT-2 §5 said to remove it. **(c) Sticker pile-up on the print.** PERFECT stamp + NEW BEST ribbon + UNLOCKED ribbon. On №0001 "NEW BEST" is meaningless. **(d) Tons are constant:** 55–58 TONS for bubble wrap, jelly, egg, can and glass alike (§3). |
| **Next** | **ok / weak** | The "NEXT: SODA CAN · 0/3" pill on the press room, the museum strip filling, and the UNLOCKED ribbon (`u-duo-lesson-book`, `u-crayon-reveal`). | **No "Up next: Egg · cracks" moment** in the frames, and no reason line on the reveal ("1 in 8 eggs hide…", "try it slower" shows only on SLAMMED). **The reason to press again is a progress bar, not a promise.** And every captured reveal says PERFECT. If real slow closes also mostly score PERFECT (≤ 100°/s, ≥ 2 s, no reversal, which a 25–60°/s close easily meets), the stamp stops meaning anything (founder question 6). |

**The press, in one sentence:** every beat exists, and most are scored correctly in time. But two of the three that create *satisfaction* (resistance and the break owning the moment) are undercut, and the third (the payoff) is silent.

---

## 3. Per object

**The test applied:**
- From the Duo's view at 100, 75 and 60 and at the reveal, does it read as satisfying?
- Does the crushed state look like the real thing, crushed?

**The view:** the book-pose frames are top-down captures of the anvil page, and the real eye sees it at ~40–50° off-normal (`a-rubberDuck-book-storeshot-75-eye`). So vertical squash is under-read here. Footprint, mess and colour are what carry.

| Rank | Object | 100° | 75° | 60° | Reveal | Crushed = the real thing crushed? |
|---|---|---|---|---|---|---|
| **1** | **Jelly** | Dome spreads; kiss print | Skin taut, lobes squeezing out, a crack line on the print | Bubbly splat past the plate, droplets | Glossy raspberry puddle with fruit pieces, lobes and stains | **Yes.** The best object. Minor: the outer lobes float detached around the puddle like petals (`a-jelly-reveal`, `u-jelly-tabletop-reveal`) |
| **2** | **Egg** | One hairline; the egg rocks | **Breaks at 92°**: shell shards, white flood, yolk dome | Yolk lobes flooding | A yolk sun over a lobed white in a shell ring; the sunny-side print | **Mostly.** The shell shards read as **straw or hay tufts** (fibrous beige), not shell (`a-egg-reveal`). The egg is pointier than an egg at 180 |
| **3** | **Glass Bottle** | **No crack visible on the bottle** (storyboard says stars start at c 0.122 ≈ 98°) | Shattered at 83°: shard heap and a superb crack-web print | Same heap | A shard heap, label scraps, the crack-web print with PERFECT | **Mostly.** The print is the best image in the app. On the anvil: shards cluster top-left, and the **intact base disc reads as a coaster** (`a-glassBottle-reveal`). No sea-glass crunch is visible after 83° |
| **4** | **Crayon Box** | Box flexes; rainbow-edge print | Snapped at 91°: the box walls fold, crayons kink | Same | Flat slabs on a flattened box; **gorgeous rainbow smear print** | **Half.** Clearly flattened, but the slabs read as **paper cut-outs or fabric** (wrapper geometry with arrow-shaped kinks), not crushed wax. The rainbow smear under the slabs is hidden by the box (`a-crayon-reveal`) |
| **5** | **Bubble Wrap** | First pops: the white star craters | Half popped | Nearly all popped | 24 craters; a pale print | **Yes, stylised.** The craters look like peppermint swirls. The joy is the pop sequence, which a still can't show. "2.7 mm → 0.8 mm · 58 TONS" undercuts it (58 tons for bubble wrap) |
| **6** | **Soda Can** | Unchanged; ring print | **Still essentially unchanged** (a slight label wrinkle) | Puncture: orange fizz, green label rumpled | A silver lid on a green crumpled ring in an orange puddle | **Weak from above.** A vertically crushed can seen top-down is a lid on a ring, and the concertina is invisible. Fizz is **orange in a lime FIZZO can** (`a-sodaCan-reveal`). The "Star" object of EXPERIENCE-2 F2 under-delivers on the Duo's own view |
| **7** | **Rubber Duck** | Almost unchanged; lemon print | Body spreads; face still neat | Skirt squeezes out as a **sawtooth "pie crust"** | A pancake with the face intact, the seam scar, the crust frill | **Half.** It reads as "squashed duck toy", which is the joke. But the **jagged skirt** looks like a frilled pastry edge, not vinyl. The platen print reads as a **lemon or leaf** (`a-rubberDuck-reveal`). The plan's decision 4 ("the duck's face deforms too") shows only as squinting eyes |
| **8** | **Cake Slice** | Unchanged; pink print | **Good:** cream creases, sprinkles, sponge band | Spread, crumbs | A **grey-pink concave hexagonal dish** with a sponge rim | **No.** It reads as a crushed paper cup or a pie tin. The sponge layers and pink filling are gone, and the cream is a dull grey crater. R9's N3 ("squashed meringue") has become "empty dish". The 75° frame is its best moment, and it should be the reveal (`a-cakeSlice-75` vs `-reveal`) |
| **9** | **Gummy Bear** | From above the bear reads as a **starfish or blob** | Split at 83°: the halves part with strands (good beat) | **Halves flung off the plate**, beads in a line along the plate edge | Two tall half-bears with **hard flat red cut planes**, far apart | **No.** It looks *sliced*, not crushed. It never flattens to the spec'd "two chewy pads". The cut faces are CG-flat rectangles. The beads line up like a dotted rule (`a-gummyBear-60`, `-reveal`) |
| **Vault** | **The Unsquishable** | Glint | **The ball looks deformed**: an elongated bronze ellipsoid with two white blobs (`a-unsquishable-75`) | — | Round again with a copper tint; lightning-crack print; "PRESS 0 – BALL 1", 488 TONS | **The joke lands on the ticket**, but at 75° the one object that must never deform appears to. Check whether a beat pulse or the lean scales it. The anvil dent the storyboard promises isn't visible |

**Ranking, best to worst:**
1. Jelly
2. Egg
3. Glass Bottle
4. Crayon Box
5. Bubble Wrap
6. Soda Can
7. Rubber Duck
8. Cake Slice
9. Gummy Bear

The Unsquishable is a joke object, outside the ranking. Its bug is the one to fix.

**Across the roster:**
- **The prints on the lid are often better than the 3D specimens** (glass web, crayon rainbow, egg sun). That's a sign the anvil's crushed states need the same art direction the prints got.
- **Tonnage is one number for everything.** `SpecimenRecord.tons` is `10 + 44·c + seed % 6`, so a full press is 54–59 t for every real object (`Shared/Contracts.swift:171–176`). The gauge, the cover card and the ticket all promise "a sense of force" and then tell you jelly took the same force as a glass bottle.

---

## 4. UI and flow

| Surface | Clarity | Discoverability | Premium feel | Duo-native | Notes |
|---|---|---|---|---|---|
| **First run / lesson** (`u-duo-lesson-book`, `o-duo-lesson`) | **Good.** "Fold it a little, like a book. Either page can be the lid." / "Lift the top half a little." | Good: the lesson card points at MORE HELP | Good | **Good:** the card sits on the lid half, the object stays visible | The live hinge glyph is small (≈ 160 px wide in a 1500-wide frame). Make it the hero, twice the size. "Sound plays even on Silent" is honest and well placed |
| **Coach lines, first 5 presses** (`a-*-100/75/60`) | Clear words | n/a | **Weak** | Tabletop placement (lid, above the crease) is right | **There's a toast on screen through the entire press for five presses.** "ALL THE WAY" covers the climax. "KEEP GOING · Hold still to tease it" contradicts itself. "IT'S GIVING!" fires on the first fracture of *anything*, including the steel ball's groan. It's a narrator talking over the movie |
| **Press-room console** | **Good** (`duo2`): MENU, the object chip with verb, Shelf, gear | **Fixed:** three labelled doors | Good keycaps | Book: on the trailing page; tabletop: on the base | The `art-after` truncations ("Me…", "RUBBER…", "CAKE SL… SQUELCH…") are fixed in `duo2`. **Names drift across surfaces:** Bubble Wrap / BUBBLES; Rubber Duck / DUCK; Crayon Box / CRAYONS / "CRAYON BOX"; Soda Can / CAN. Pick one name per object |
| **Instruments** | **Weak** | — | The crown looks good | — | **Still engineering-first.** The 56 pt gauge sits in the corner and the live hinge angle ("180°") takes the centre nameplate. After the break the angle freezes red and stays red through the reveal while the needle reads 0. UX-AUDIT-2 #8 and §5 were not done |
| **Menu** (`u-duo-menu-book`, `o-duo-menu`) | **Good:** Resume, Objects, Shelf, How to press, Settings, About; "No ads · No tracking" | Good | **Good:** a press-styled panel with hazard trim | **Half.** In book pose it uses the trailing page only and dims an empty leading page. In tabletop it covers the object *and* overlaps the console (the MENU key and the NEXT pill peek out from under it) | Use the leading page for "On the anvil + Museum progress", the trailing page for the doors |
| **Tray / Museum** (`u-duo-tray-book`, `u-duo-tray`) | **Excellent:** wings, verbs, stiffness pips, Perfect/Surprise/Golden slots, locked-tile progress | Good | **Good layout, cheap art.** Every tile is **flat clip-art** (a pink dome for jelly, a 2D wedge for cake). The founder asked for "much more detailed objects", and the app already has beautiful 3D renders | **Good:** a two-page spread with "On the anvil" on the leading page | The duck's Surprise slot is a dash; say "No surprise · he's just a duck" |
| **Settings** (`u-duo-settings-book`, `u-duo-settings`) | **Excellent:** plain words, test buttons, the Silent explanation, Vibration strength | Good: one tap from home, the reveal and the cover | Good | **Good:** a spread, nothing on the crease | The best-executed fix of the rebuild |
| **Help** (`u-duo-help-book`) | OK | Good | **Weak** | Half | The leading-page cards wrap text into 1–2-word lines ("Like a / tiny / laptop"), while the trailing page is half empty. Rebalance: illustrations on the leading page, text on the trailing page, or wider cards |
| **Shelf / Achievements** (`u-duo-shelf-book`, `u-duo-achievements-book`) | Good: wings with counts, prints as tiles, an achievements list with hints | Good | Good | Good spread | Tiles show the **lid print** (2D), never the crushed 3D specimen, so the thing you made is missing from your museum |
| **Cover** (`u-duo-cover-launch`, `*-closed`, `u-crayon-60`) | **Good:** recent prints, ON THE ANVIL, chips, "Open to press", Shelf 7 · Menu · gear; SEALING… / KA-CHUNK! / RELEASING… | Good | OK: lots of empty graphite above and below the cards | **Better than R9** (Shelf and Menu reachable) | The chips are **names only**, with no picture or verb. The cover is still a lobby (APPLE-DUO-GUIDE O1: no thumb quick-press). The outer camera dot sits ~45 px from the top-right screw (`u-crayon-60`): fine, but check on hardware |
| **Reveal ticket** (`u-*-reveal`) | **Good:** three calm lines | — | Good | Fits between the print and the crease | Remove NEW BEST on №0001. Drop the red angle. Make the before → after glyph the size of a word, not 66 × 24 pt |

**First-run flow in one paragraph:**
- What works: the lesson tells you the pose, the console tells you where everything is, the toasts walk you through, and the cover narrates the seal. A new user will no longer be lost, which is a big fix.
- What's wrong: the first five presses are *over*-narrated. And the reveal of press 1 shouts PERFECT · NEW BEST · UNLOCKED · FIRST SQUISH all at once, so nothing feels earned.

---

## 5. Sound and haptics design, from the code

**Layering: strong in architecture, unproven in content.**
- Every moment is one `FeedbackCue` shared by both controllers (`CueBook`), with recorded voices layered under synth bodies (`SampleVoicing`). The haptic onsets come from the recording's own transients (manifest `haptics`), with roles: grain = one tick, hero = every hit, tail = 40 %.
- That is exactly the transient + body + debris + settle stack EXPERIENCE-2 A5 asked for.
- But density has no hierarchy under load. On a typical object these all run at once:
  - grains every 0.8–9° (`MaterialProfile.grainSpacing`; the can is 0.8°, far below the hinge's ~5° accuracy);
  - storyboard beats every ≤ 4.5°;
  - gauge ticks every 5°;
  - a recorded strain loop;
  - the synth stick-slip creak;
  - hiss and motor.

  That's 4–6 discrete tick sources plus 3 beds. On paper it builds. On a phone speaker it may blur into an even rattle, with the strain never feeling like it *rises*.

**Variety: good engine, thin pools in the wrong places.**
- Round-robin with no immediate repeat, ±1 semitone, ±2 dB, seeded per press.
- But these are single files:
  - `duck_honk` (the duck's signature);
  - `gummy_boing`;
  - `steel_snap` and `steel_ring` (the vault's punchline);
  - `crayon_tap`;
  - every loop (1–2 files each).
- The whole gummy is 10 files, and its sources are rubber, not gummy.
- The crayon snaps are pencils and twigs, and the cake is whipped cream and sponge (SOUND-2 §6 "gaps").
- The pools are deep where they matter most (glass shatter 11, can crumple 12, egg crunch 12). The honk is the most-heard sound in the app and it never changes.

**Sync: carefully done.**
- Haptics are delayed by the measured audio output latency (`HapticTuning.alignment`).
- Transients are spaced ≥ 12 ms, and drift from the sound is capped at ±15 ms.
- Beds follow `displayAngle`/`displaySpeed`, so they don't step at the real Duo's 25–30 Hz reports.
- **Two risks:**
  1. **Burst delay.** The break deliberately lands 135–205 ms after the crossing. That's correct as a hit stop, but risky after a founder complaint about sync.
  2. **Grain lumping.** Grains are emitted from the filtered event angle. A 25 Hz report that jumps 2° releases several grains in one frame, and `HapticsController.play` *drops* a grain that would need > 15 ms of shifting (`timing != .event → return`). So on hardware the "compliance" grain texture may arrive in clumps with holes.

**Loudness:**
- Measured at about −17.7 LUFS with master 2.4 into a −1 dBFS look-ahead limiter; bed ~11 LU under the break after the +4 dB bed bump (`AudioMix`). The *targets* are right.
- **But "the climaxes ride the limiter"** on a small, thin speaker. Pushed to the limiter, the glass shatter and the ka-chunk may come out squashed, the opposite of crisp.
- **Nobody has listened.** Treat every loudness claim as a hypothesis until the founder's 50 %-volume pass (SOUND-2 §7).

**Haptics: the biggest design regression of the rebuild.**
- **Strong is now the default** (`cb27e31`), with this profile (`HapticProfile.strong`):
  - lift exponent 0.45;
  - the bed rises from 0.45 at contact to **1.0** at the break, with a 30 Hz rumble;
  - every transient ≥ 0.5 plays at **1.0** with a 45 ms low-sharpness burst;
  - every grain gets an echo;
  - **the fatigue guard is off.**
- That answers "vibrations stronger" literally, but it breaks the plan's core haptic rule: "The strain bed is capped at about 0.55, so peaks stand out" (EXPERIENCE-PLAN, Haptics).
- Just before the break the phone is already buzzing at ~1.0. The break's 1.0 is distinguished only by the 135–205 ms of silence before it, and every crack and pop is *also* 1.0.
- **Strong should mean "everything clearly felt", not "everything maximum".** Bigger peaks need headroom (Top-10 #2).
- A full press is a continuous 0.45–1.0 vibration for 3–6 s. That's a battery and thermal cost, and a "buzzing phone" sensation rather than a "material" one.

**The hinge-motion layer** (`HingeFeel`, `PressBeat.detent / powerUp / powerDown`):
- **Concept: right.** It answers "everything should be together and make sense":
  - a creak whose rate, level and pitch follow speed;
  - a ratchet click and tick every 6°;
  - a power-up hum as the phone opens, a power-down as it closes;
  - a magnetic clack on an empty shut;
  - the unlatch on the reveal.

  All of it is quiet so the press stays loudest.
- **Two doubts:**
  1. **The causality of a fake ratchet on a smooth hinge.** The Duo's hinge is praised for being smooth and holding any angle. A click every 6° that your hand doesn't feel may read as "the app is ticking", not "the hinge has detents" (founder question 4).
  2. **The visual half is thin.** Per the comments, the hazard stripes step and the needle twitches on a detent, but in every idle frame the only angle-driven visual is the number on the nameplate. The founder asked for *animations* based on the angle; the code mostly gave sound and touch.

**Touch to inspect:**
- Spin, slight tilt, pinch to 1.25× and poke all exist, each with a material-specific sound and haptic (`TouchCues`).
- **But only before a press:** `PressEngine.canInspect` requires `.idle`/`.armed` and zero depth.
- **You can't inspect the crushed specimen**, which is the thing anyone actually wants to turn over and poke. The zoom limit is also too small to see "much more detailed objects".

---

## 6. Top 10 highest-impact improvements, ranked

| # | Improvement | Files | The fix | Effort |
|---|---|---|---|---|
| **1** | **Bring back "fight, then give", without breaking sync** | `Core/PressFeel.swift` (`PressResistance`), `Scene/Kit/ObjectLife.swift`, each `Scene/Objects/*View.swift` | Keep the *height* locked to the hand (sync), and put the fight in the other axes and in time. **Resist:** in the last 0.12 c before failure, ramp a lateral bulge to ≥ 15 % of width, a visible bow or shear, stress whitening and a tremor amplitude you can see (2–4 px on the anvil, not mm-scale). **Give:** at the burst the object *drops ahead of the hand*: a 0.05–0.10 c over-collapse in 60–80 ms, then it settles back to the hand's c. Squeeze-out jumps outward at the same moment. Physically right: the object yields faster than the plate moves. | M |
| **2** | **Haptic headroom on Strong and Max** | `Feedback/FeedbackTuning.swift` (`HapticProfile.strong/maximum`), `HapticsController.update` | Make the break *physically bigger* instead of everything louder. **Bed:** Strong ceiling 0.7 (Max 0.8), floor 0.35. **Rumble:** only inside the tell window. **Majors:** threshold 0.7, so pops and minor cracks stay under the break. **Break and ka-chunk:** a 1.0 transient + a 1.0 / 0.2-sharpness continuous 90–120 ms + a second 0.8 transient 25 ms later. Re-enable the fatigue guard on Strong. Test: a full press with sound off must still have a clear peak. | S |
| **3** | **Give the reveal replay sound and touch** | `Scene/PressScene.swift` (`applyReplayMark`), `App/PressDirector.swift`, `Feedback/CueBook.swift` | The replay's marks call back to the director. Re-fire the recorded press cues: strain bed, cracks, then the break at 0.35× (pitched down ~8–12 st via the sample rate in `Synth`, low-passed, −6 dB), with a softened haptic re-hit on the burst. Peak–end: the reveal's slow-mo should be the *best* sound of the press, not silence. | M |
| **4** | **Tons that mean something, and a hero gauge** | `Shared/Contracts.swift` (`tons`), `Scene/Rig/RigTextures.swift` (`PressGauge.liveTons/recordTons`), `Scene/Fold/FoldBezel.swift` | **Tons per material:** bubble wrap ~3 t, jelly ~2 t, cake ~4 t, egg ~6 t, duck ~9 t, crayon ~12 t, gummy ~8 t, can ~22 t, glass ~38 t, steel 400+. **Gauge:** make it the crown's hero (≥ 96 pt, centred), with the hinge angle a small engraved secondary or gone. **Reveal:** never show the frozen red angle; show peak tons. | S/M |
| **5** | **Fix the three worst crushed states** | `Scene/Objects/GummyBearView.swift`, `CakeSliceView.swift`, `SodaCanView.swift` (+ `DuckView` skirt) | **Gummy:** the halves slap flat into glossy pads ≤ 25 % of the original height, stay on the plate, rounded cut faces with the sugar-frost texture, strands sag onto the pads. **Cake:** keep a visible sponge band and pink filling at the rim at c = 1, cream stays cream (no grey concave dish), crumbs on top; the 75° look *is* the target. **Can:** show the crush from above (radial creases on the lid, the lid tilting and folding, crumpled label petals splaying out) and fizz in the can's colour. **Duck:** replace the sawtooth skirt with a smooth vinyl lip. | L |
| **6** | **Stop narrating the climax** | `UI/FoldLesson.swift` (`CoachLine.line`), `UI/RootView.swift` (coach slot) | Coach only *before* contact and *after* the settle. Press 1: "Close it slowly" → (silence through contact, strain and break) → "Ka-chunk! Now open it". Presses 2–5: reactive only (EASY… on a fast close, EASED OFF on a reopen). Never "ALL THE WAY" during the break; show it only if the user stalls past bottom-out for > 1.5 s. Delete "It's touching. Keep going." after press 1, and "IT'S GIVING!" on things that didn't give. | S |
| **7** | **Fill the 55° → 10° seal stroke** | `Core/PressConfig.swift` (`endAngle`), `Feedback/AudioController.swift` (`.pressing` after `bottomFired`), `Feedback/BrandCues.swift`, `HapticsController.update` | After bottom-out, the last ~45° of closing should *build to* the ka-chunk, not coast. Add a hydraulic whine rising with 1 − θ/55, latch-ratchet clicks every 9° in the dark (sound + 0.4 tap), and a haptic ramp 0.3 → 0.6 into the 1.0 ka-chunk. For bubble wrap, drop the pinned-max strain bed after the last pop. If the founder's display stays lit to ~45°, try `endAngle` 48 so the visible crush uses the whole lit range. | S/M |
| **8** | **Inspect the crushed specimen** | `Core/PressEngine.swift` (`canInspect`), `Scene/PressScene.swift`, `Core/PressFeel.swift` (`ObjectInspection.maxZoom`) | Allow spin, tilt and zoom in `.revealing` once the ceremony is done; zoom to 2.0×; poking the crushed object plays its *crushed* answer (a squelch for jelly, a crunch for glass, a wheeze for the duck). That's the "touch to inspect" the founder asked for, on the thing worth inspecting. | S/M |
| **9** | **Fill the thin sound pools, then a listening pass** | `ci/sounds/make-cuts.sh`, `Squish/Resources/Sounds/*`, `SampleVoicing` | Get ≥ 5 variants for `duck_honk`, `gummy_*`, `steel_snap/ring`, `crayon_snap` (real wax) and `cake_*` (a real pressed slice). The founder's 20-minute phone-foley list (research 02 §5.3) covers the crayon, gummy and cake. For any group still at one file, alternate it with a synth variant so the no-repeat rule really holds. Then run SOUND-2 §7 on hardware and re-cut from the report. | M |
| **10** | **Detailed objects everywhere you choose and collect** | `UI/Theme.swift` (object icon art), `UI/TrayView.swift`, `UI/CoverView.swift`, `UI/ShelfView.swift` | Pre-render each object's intact 3D look (and, once pressed, its crushed specimen snapshot) as tile art. Replace the flat clip-art in the Tray, the console chip and the cover chips; give the cover chips the verb ("Egg · cracks"). The Shelf shows the crushed 3D specimen beside the print. | M |

**Also worth doing (smaller):**
- **The Unsquishable's apparent deformation at 75°.** Find what scales it (a beat pulse or the lean) and exempt it.
- **No NEW BEST on №0001.** One sticker on the print at a time.
- **Gummy debris beads in a line** along the plate edge: scatter them.
- **Help sheet layout:** rebalance the two pages.
- **The menu should use both pages**, and never overlap the console in tabletop.
- **One display name per object.**
- **Grain spacing ≥ 2°** (the can's 0.8° is below the sensor's accuracy). Spread grains released by one report across the frame interval instead of dropping them.

**If only three ship before the next TestFlight:** #2 (S), #6 (S) and #4 (S/M) are a day's work and change how every single press feels. #1 and #3 are the next round.

---

## 7. Questions only the founder's hands and ears can answer

Ask these on the device, at 50 % volume, on a table (tabletop) and in the hand (book).

1. **Did it fight you?** Between "It's touching" and the break, did any object feel *harder* to close, by sound or vibration? Which objects, if any?
2. **Is the break late?** On a slow close, does the burst feel like it lands *on* your hand, or a beat after it (it's 135–205 ms by design)? Try glass, whose hit stop is the longest.
3. **Strong vs Normal, sound off.** Do a full glass press on each. On Strong, can you feel the break as a *bigger* event than the strain right before it, or is it all one buzz?
4. **The hinge ratchet.** Opening and closing with nothing pressed, do the clicks every 6° feel like the hinge, or like the app ticking at you? Keep, soften or remove?
5. **The dead stroke.** After the screen freezes at full crush (~55°), is the trip down to the ka-chunk exciting, empty or annoying? At what angle does the inner screen actually go dark?
6. **PERFECT.** In ten normal, unhurried presses, how many earn PERFECT? If it's most of them, it's not a reward.
7. **Words during the press.** On the first press, did you read the toasts while pressing? Did they help, or pull your eyes off the object?
8. **Which object made you say "oh"?** Which one made you press it again immediately, and which ones did nothing? (Compare with the ranking in §3.)
9. **The recorded sounds.** Any wince (harsh, squealy, or the same recording twice)? Is the duck's honk funny the fifth time? Does the shatter sound like a bottle *crushed* or a bottle *dropped*?
10. **The reveal.** Did you watch the slow-mo replay, or reach for Keep? Would you watch it if it had sound?
