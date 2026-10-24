# SOUND-2: recorded foley for the squish (24 Oct 2026)

*Sound designer's plan after the founder's first real-Duo test: "sound effect, vibration, everything is really key", and "satisfaction in squishing is really the biggest thing that needs to be achieved in this app". It builds on `research/02-sound.md`, `research/01-haptics.md`, bible §8 and §15, `design/EXPERIENCE-PLAN.md` decision 5 and `design/research/EXPERIENCE-2.md` A5. Where they conflict, this document wins for sound content; the EXPERIENCE-PLAN still wins for the press beats.*

**Status:**
- 274 recorded samples are already cut, checked and committed: `Squish/Resources/Sounds/`, 11.3 MB, all CC0.
- The provenance file `Squish/Resources/Sounds/LICENSES.md` and a group manifest `sounds-manifest.json` are generated from the pipeline in `ci/sounds/`.
- **Nothing is wired into the app yet.** §5 is the engineer's plan.
- Nobody has listened to these files. The developer can't, so every choice was made from spectrograms, onset and loudness analysis, and source descriptions. **The founder's ears are the acceptance test** (§7).

---

## 0. Decisions

1. **Hybrid, recorded-first.** Every *event* is recorded foley: contact, crack, snap, pop, buckle, splat, shatter, fizz, debris and crush grains. The *continuous* layers that must follow the hinge are recorded loops played at a variable rate, with the existing code synthesis kept underneath:
   - the stick-slip press creak;
   - hiss and motor;
   - gauge ticks;
   - modal rings;
   - sub "thump" harmonics for the phone speaker.

   Brand sounds stay synthesised and fixed: ticks, ka-chunk, sting, chime. Recorded layers sit *under* the ka-chunk and the stamp.
2. **Licences that pass, for a paid app in a public repository:**
   - CC0 only: Freesound CC0, Kenney, and BigSoundBank (also CC0; found in this research).
   - Sonniss GDC passes for the *app* but **cannot be committed to this public repo** (§2.2). Sonniss is phase 2, through a private asset store.
   - Pixabay, ZapSplat and BBC are out for v1.
3. **The shopping list** (§6):
   - 140 candidates were fetched and checked. 88 are used: 81 Freesound CC0 recordings, 5 BigSoundBank CC0 recordings, and 2 Kenney CC0 packs.
   - They were cut into **274 files in 67 round-robin groups**: 12 object and system sets, 123 s of audio, 11.3 MB.
   - The size is under the 15 MB budget. Decoded as Int16 it is 11.3 MB of RAM if everything is resident.
4. **Format:** CAF, 48 kHz, mono, 16-bit little-endian PCM, for everything.
   - The size is affordable, so AAC is not worth its priming smear on onsets or its loop-seam problems.
   - Basenames are globally unique (`glass_shatter_07.caf`), because XcodeGen flattens `Squish/` groups into the bundle root.
5. **Audio-derived haptics.** The pipeline detects the transients in every sample and writes them into the manifest as `[time, intensity, sharpness]`. A glass shatter's haptic tinkles land on the audio's actual shard hits instead of on a generic pattern (§4).
6. **Samples become Synth voices**, not a separate player. A `.sample` `SynthCommand` plus sample-loop bed parameters means `OfflineAudio` (the share clip) renders samples with no new code path, and seeded presses replay exactly (§5).

---

## 1. Synthesis vs recorded foley vs hybrid

### 1.1 What the products people praise actually do

| Product | Approach | Source |
|---|---|---|
| **Unpacking** | ~14,000 recorded foley files: every object × surface, speed-dependent | [NME](https://www.nme.com/news/unpacking-features-over-14000-sound-effect-files-3087521) (EXPERIENCE-2) |
| **Deck-Man** (Duo Walkman toy) | Recorded a real Walkman's clicks | [Gulf News](https://gulfnews.com/technology/media/viral-app-turns-apples-foldable-iphone-into-a-walkman-and-2-million-people-watched-1.500693709) (EXPERIENCE-2) |
| **(Not Boring) Habits** | A dozen custom-recorded versions of one click, plus haptics | [Launched podcast](https://podcastaddict.com/launched/episode/227394462) (EXPERIENCE-2) |
| **ASMR Slicing / Slice It All** | Sample-based "smooth ASMR sound" is the selling point | App Store listings (EXPERIENCE-2 §E) |
| **Smash Hit** | The composer did the glass and ball sound design alongside the music; no source says it was procedural | [Game Developer](https://www.gamedeveloper.com/audio/writing-the-music-for-smash-hit) |
| Hydraulic Press Channel (the reference video genre) | Real recordings; tension then release | [Vice](https://broadly.vice.com/en/article/889wez/the-hydraulic-press-channel-is-the-internet-sensation-of-our-time) |

The pattern is consistent. **Satisfying products record real material.** Synthesis wins only where the sound must follow a continuous control (engines, creaks, scrapes), and even there the standard practice is *recorded loops or grains, driven by a parameter*, rather than pure synthesis ([Audiokinetic](https://www.audiokinetic.com/engine-sound-modeling-from-sampling-to-granular-synthesis-in-wwise)). Our current synth crunch is filtered-noise grains. It lacks the dense, irregular 2–20 kHz micro-structure that makes crunch read as "fresh" ([Zampini & Spence 2004](https://www.neuroscience.ox.ac.uk/publications/4405)). That is the main reason the press sounds flat.

### 1.2 Decision per sound class

| Class | v1 source | Driven by | Why |
|---|---|---|---|
| **Crush / crunch** (egg shell, crumbs, wax, can crumple, glass grit) | Recorded **grains**: 10–14 per material, 30–250 ms | Grain rate ∝ closing speed × "fresh"; pitch ±1.5 st | Granular playback of real crunch is the only way to get the irregular density |
| **Crack / snap / buckle** | Recorded one-shots: 6–12 per material | Fracture thresholds | Transient detail can't be faked convincingly |
| **Pop** (bubble wrap, duck seam) | Recorded single pops in 3 sizes (29 files) | One per visual bubble | The most ASMR-like object; pops *are* the content |
| **Squelch / splat** (jelly, yolk, squirt, gummy) | Recorded grains and bodies | Compression and speed | Wet detail; tagged `wet` and dropped in Soft style |
| **Fizz** (can) | Recorded tab-pop and fizz burst, plus a fizz loop | First buckle; reveal | Real fizz is noise with bubbles; synth fizz sounds like hiss |
| **Glass** | Recorded crack, tink, 11 hero shatters, debris tails, grit grains | Thresholds; crush | The app's biggest climax |
| **Metal strain** (steel ball, can) | **Hybrid:** recorded groan loop (rate 0.85→1.25 with c) + existing synth stick-slip creak + recorded groan swells on the tell | Hinge angle, continuously | The loop gives realism; the synth creak never repeats and follows angle precisely |
| **Material strain beds** (crinkle, gel, cream, rubber stretch, glass creak, slow-crush crackle) | Recorded seamless loops, 2.5–4.8 s | Gain = strain^1.5 · max(v, 0.25); rate ±10 % with c | Replaces the filtered-noise `NoiseBed` |
| **Press machine** (hiss, ka-chunk, release, contact thud, stamp) | **Hybrid:** recorded hiss loop and release sighs; recorded latch and metal layers *under* the synth ka-chunk | Closing speed; `.closed` | The ka-chunk stays the brand; the recording gives it mass |
| **Brand** (gauge ticks, sting, chime, fanfare) | Synth, fixed | — | The logo; never randomised (bible §8) |
| **UI** (taps, toggles, unlocks, drop) | Recorded Kenney UI clicks, with the synth chime kept for unlocks | Taps | Cheap, clean, consistent |

**What stays synthesised and why:** the procedural creak, gauge ticks, hiss *shaping* (the filter sweep on the recorded hiss), motor hum, modal ring for can and bottle, sub-thump harmonics, hush, sting and chime. All of these follow a parameter continuously or are brand. Cost: zero assets.

---

## 2. Sourcing that is legally safe

### 2.1 Free sources, checked 24 Oct 2026

| Source | Licence as published | Paid app? | Attribution | Redistribution | **Verdict** |
|---|---|---|---|---|---|
| **Freesound, CC0 filter** | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) per sound (each page verified by the fetch script) | Yes | None | Allowed (public domain) | **Pass.** Used for 81 sources. Originals need a free login (OAuth for API downloads); the HQ previews are public ([API docs](https://freesound.org/docs/api/overview.html)). v1 uses the HQ OGG previews (~200 kbps) |
| **Kenney** audio packs | CC0 ("free to use in personal, educational and commercial projects… crediting… not mandatory", `License.txt` in each zip) | Yes | Optional | Allowed | **Pass.** Impact Sounds, Interface Sounds and UI Audio were downloaded |
| **BigSoundBank** (Joseph Sardin) | CC0 on every sound page ("CC0 (public domain): Free and royalty-free") | Yes | Optional | Allowed | **Pass.** Studio-recorded, 48 kHz. The WAV links are hotlink-protected, so v1 uses the 320 kbps MP3 |
| **Sonniss GDC bundles** 2015–2024, 2026 | "Royalty free and commercially usable… no attribution… unlimited projects"; may **not** be redistributed "as sound effects", including "edited or re-designed versions"; **AI/ML training prohibited** ([sonniss.com/gameaudiogdc](https://sonniss.com/gameaudiogdc)) | Yes, inside the app | None | **No.** A public GitHub repo is redistribution | **Pass for the app, fail for this repo.** See §2.2. 9–48 GB per year, in multi-part zips |
| **Pixabay** sound effects | [Content License](https://pixabay.com/service/license-summary/): free, no attribution; no selling or distributing content "on a standalone basis" (substantially unchanged) | Yes, when combined into a product | None | No standalone | **Not for v1.** It would fail in this public repo, the same way Sonniss does. Pixabay audio is user-uploaded, so provenance is weaker than a curated library. Gap-filler only, with uploader and page recorded |
| **ZapSplat** | [Standard licence](https://www.zapsplat.com/license-type/standard-license/): free tier **requires credit** "wherever reasonably possible"; Premium has no attribution; no redistribution; and "the sounds cannot be the main value of the product" | Grey | Free tier: yes | No | **Exclude.** For a toy whose value *is* its sound, the "main value" clause is a real risk |
| **BBC Sound Effects** (RemArc) | Personal, educational and research use only; commercial use needs a separate paid licence | **No** | — | — | **Exclude** |

**Licence hygiene in place:**
- `ci/sounds/sources.tsv` pins each source by URL **and sha256**. The fetch fails if a file changes upstream.
- Before downloading, the fetch tooling read every Freesound page and refused any sound whose page did not carry the CC0 deed. All 129 Freesound candidates passed. The BigSoundBank pages and the Kenney `License.txt` files were checked by hand.
- `LICENSES.md` is generated from `sources.tsv` and `cuts.tsv`, so no file can ship without a row.
- Courtesy credits are listed even though CC0 does not require them. An About-screen credit line is optional and kind.

### 2.2 The public-repo constraint (important)

The repo is public (the founder's choice, for free CI). Any file committed here can be downloaded on its own by anyone. That is exactly the "standalone redistribution" that Sonniss, Pixabay, ZapSplat and every paid library forbid. **Only CC0 material may be committed.** For phase 2 (Sonniss and paid packs):

1. Keep the raw and cut files in a **private** GitHub repo, e.g. `pravegm/squish-sounds-private`.
2. Add a `SOUNDS_PRIVATE_TOKEN` secret to this repo.
3. In `ci.yml`, `testflight.yml` and `store.yml`, a step clones the private repo into `Squish/Resources/SoundsPrivate/` before `xcodegen generate`. The folder is git-ignored here.
4. That folder's `LICENSES.md` lives in the private repo. The app's About screen can still show one combined credits page.
5. The `sounds-manifest.json` format already supports more groups. A private group with the same name *overrides* the CC0 group, so an upgrade is a drop-in with no code change (bible §15.1).

### 2.3 Paid upgrade path (later; prices indexed, verify at purchase)

| Vendor | Licence fit for a paid iOS app | Price | What to buy first |
|---|---|---|---|
| **A Sound Effect** (marketplace) | Royalty-free, no attribution, per user (research 02 §5.1) | Per pack | **Ultrasquish** (goo, ~$40); **Glass Smash HD** (Soundopolis, ~$75); **Squeaky Toys** (Sounds Like George, $5–10); **Metal Groans and Slams** (~$30). Total ≈ $150 |
| **Soundsnap** | "Creative Works" explicitly include video games, applications and software; **no attribution**; licence **perpetual for sounds downloaded** while subscribed ([licence](https://www.soundsnap.com/licence)) | ~$149–$299 a year (unverified 2026 tiers) | One month or one year to cherry-pick the heroes: glass bottle smash, can crush, egg crack, gummy squish |
| **BOOM Library** | Commercial use, no attribution, single user ([FAQ](https://www.boomlibrary.com/support/faq/what-am-i-allowed-to-do-with-your-sounds/)); check the EULA for interactive use | Per library (check) | Only if a specific library (e.g. a glass or metal-destruction pack) beats the A Sound Effect options |
| **Pro Sound Effects** | Pro bundles for studios | CORE 6 lifetime $1,499 / $3,999 / $11,999 (one source, limited-time) | **Not worth it** for one app |
| **Epidemic Sound** | Creator plans cover videos; in-app use needs a developer/partner commercial agreement ([developers](https://developers.epidemicsound.com/)) | Custom | **Skip** |
| **Soundly Pro** | Cleared for games; stays cleared after unsubscribing (research 02) | ~$10–15 a month (unverified) | A cheap one-month browse of a large catalogue |

**Upgrade order if the founder's listening says a layer is weak:**
1. glass shatter;
2. jelly and egg squelch;
3. duck squeaks;
4. can crush;
5. steel groan.

This follows bible §15.1, adjusted for this set. Each upgrade is: put the files in the private store, add rows to a private `cuts.tsv`, re-run the cut.

---

## 3. Per-object sound brief

### 3.1 How to read this

- **Layers** follow the press beats in EXPERIENCE-PLAN: approach → contact → strain (angle-driven) → tell → break → crush → seal → release → reveal. Group names are the file prefixes in `Squish/Resources/Sounds/<object>/`.
- **Shared layers on every object:**
  - approach: `press_hiss_loop`, with gain and band-pass driven by closing speed, plus the synth hum;
  - contact: `press_contact_soft` under the material contact;
  - seal: synth ka-chunk + `press_kachunk_latch` + `press_kachunk_metal`;
  - release: `press_release`;
  - reveal: synth sting, then `press_stamp`;
  - and the synth gauge ticks and creak throughout.
- **File loudness** (set by the cutter, measured in `ci/sounds/report.tsv`; true peak ≤ −1 dBTP on every file):

  | Role | Target |
  |---|---|
  | Heroes | −12 LUFS momentary-max |
  | Bodies | −14 |
  | Details | −16 to −20 |
  | Grains | sample peak −6 dBFS |
  | Loops | −24 to −26 LUFS integrated |
  | UI | −22 |

  Peaky transients (snaps, pops, cracks) get up to 4–8 dB of 1.5 ms look-ahead limiting (`m-14L8`), so they reach the target without losing the click.
- **Mix targets** (the runtime bus, measured on device by the Diagnostics loudness test):
  - a whole press about **−16 LUFS integrated, −1 dBTP**;
  - strain bed **10–12 LU below** the break;
  - break about **6 LU above** the ka-chunk.

  The starting bus trims are in `sounds-manifest.json` (`gainDb`): hero 0, body −2, pops −4, tail and detail −8, grains −12, loops −14, UI −14.
- **Variation on every play** (except brand):
  - shuffle-bag pick with no immediate repeat (`FeedbackDice.pick` already does this);
  - pitch ± the group's `pitch` semitones (grains 1.5, bodies 0.7, heroes 0.5);
  - gain ±2 dB;
  - the per-press tone offset of ±0.5 st;
  - grains also get a random 0–15 ms start offset into the file.

  With 6–14 files per group, a 20-press session never hears the same event twice in a row.

### 3.2 The ten objects

**Bubble wrap: the onboarding object, pops are the content**

| Layer | Groups (files) | Behaviour |
|---|---|---|
| Place / contact | `bubblewrap_crinkle` (2) | Crinkle, −8 dB |
| Strain (angle) | `bubblewrap_crinkle_loop` (1, 2.7 s) | Gain ∝ strain; rate 0.9→1.15 |
| Grains = pops | `bubblewrap_pop` (12), `bubblewrap_popsmall` (10), `bubblewrap_popbig` (7) | **One pop per visual bubble that bursts.** Pick the size by the bubble's radius; pitch ±1.5 st, plus −2 st × c (deeper as it flattens). Pop rain while crushing, rate ∝ v |
| Release / reveal | crinkle | — |

- **Upgrade search:** "bubble wrap pop single", "bubble wrap slow". Candidates: Freesound [323684](https://freesound.org/people/Dwums96/sounds/323684/) and [164473](https://freesound.org/people/deleted_user_2104797/sounds/164473/) (already fetched, not yet cut).
- **Loudness:** pops reach about −29 LUFS-M at −1 dBTP. That is expected for 50–130 ms sounds on a 400 ms meter. Judge them by peak and by ear.

**Rubber duck: comic, never pained**

| Layer | Groups | Behaviour |
|---|---|---|
| Place / contact | `duck_squeaklow` (2) | Low squeak |
| Strain chirps | `duck_squeak` (6) | One squeeze squeak every ~25° of travel, pitched **up** with c (+0→+4 st). The source bends down, so the upward offset keeps it comic |
| Break 1 (c 0.7) | `duck_honk` (1) | Long squeal, 2.5–4.5 kHz notched −5 dB |
| Break 2 (seam, c 0.85) | `bubblewrap_popbig` at −5 st + `duck_wheeze` | Seam pop, then the wheeze |
| Crush bed | `duck_wheeze_loop` (1) | Air leak, rate ∝ v |
| Release / reveal | `duck_wheeze` (2) | Re-inflating wheeze |

- **Upgrade search:** "rubber duck squeeze", "squeaky toy". Candidates: [350917](https://freesound.org/people/csaszi/sounds/350917/) (very tonal at 3 kHz; avoid unless notched); Sounds Like George **Squeaky Toys** (paid).

**Jelly: wobble and ooze**

| Layer | Groups | Behaviour |
|---|---|---|
| Place | `jelly_wobble` (3) | The bounce file for the landing |
| Contact | `jelly_wobble` | — |
| Strain | `jelly_squelch_loop` (2: gel between hands; bubbly slime) | Wet; Soft style falls back to the synth bed |
| Grains | `jelly_squelch` (14) | Crush bed |
| Break (skin split, c 0.85) | `jelly_splat` (5) + 2 squelch grains at +30 and +70 ms | — |
| Release | `jelly_slurp` (2) | Elastic slurp-back |
| Reveal | `jelly_wobble` | — |

Keep it clean, not mouth-like: no slurps louder than −8 dB.

**Crayon box: dry, bright wax**

| Layer | Groups | Behaviour |
|---|---|---|
| Place / contact | `crayon_tap` (1) | Real crayon tap |
| Strain | Synth wax creak (kept) + `crayon_crumb` micro-grains during the tell | — |
| Breaks | `crayon_snap` (6) | One per crayon of the Box; ±0.7 st plus a per-crayon pitch step, so the 6 snaps read as a run |
| Crush | `crayon_crumb` (11) | Crumble grains |
| Reveal | crumbs | — |

The sources are pencil, twig and celery snaps, low-passed at 9–10 kHz so they read as wax, not wood. **Upgrade:** record a real crayon snap (phone foley, research 02 §5.3). It is the single highest-value 30 seconds of recording.

**Egg: shell, then wet**

| Layer | Groups | Behaviour |
|---|---|---|
| Contact | `egg_tick` (8) | — |
| Strain / tell | `egg_tick` micro-cracks, accelerating 3→15/s (`PulseSchedule.tell`) | — |
| Break (c 0.24) | `egg_crack` (6) + `egg_yolk` (2) at +40 ms | Yolk is wet |
| Crush | `egg_crunch` (12) | Crossfades to `jelly_squelch` at −6 dB above c 0.6 (shell to yolk) |
| Reveal | crunch | — |

**Upgrade search:** "egg crack bowl", "egg shell crush".

**Cake slice: the cosy one**

| Layer | Groups | Behaviour |
|---|---|---|
| Strain | `cake_squish_loop` (2: whipped cream, sponge) | — |
| Fracture c 0.3 | `cake_icing` (2) | — |
| Squirt c 0.65 | `cake_squirt` (2) | Wet |
| Collapse | `cake_collapse` (2) | — |
| Crush | `cake_crumb` (10) | Graham-cracker crumbs |
| Reveal | crumbs | — |

Lowest intensity object: bus −2 dB overall.

**Soda can: buckles and fizz**

| Layer | Groups | Behaviour |
|---|---|---|
| Place / contact | `can_tink` (5) | — |
| Strain | `can_strain_loop` (1: slow-crush crackle) + `can_crumple` grains + synth modal ring | — |
| Buckles (p 0.30, 0.45, 0.58, 0.70) | `can_buckle` (11) | — |
| First buckle on an unopened can | `can_open_fizz` (2) | — |
| Final (0.80) | `can_crush` (2, hero) | — |
| Crush | `can_crumple` (12) | — |
| Reveal | `can_fizz_loop` | Fades out over 1.2 s |

**Gummy bear: chewy stretch, then a seam split (must differ from jelly)**

| Layer | Groups | Behaviour |
|---|---|---|
| Place | `gummy_boing` (1) | — |
| Strain | `gummy_stretch_loop` (1: rubbery crumple) | Rate rises with c |
| Grains | `gummy_squish` (5) | — |
| Break | `gummy_split` (3) | — |
| Release | `gummy_boing` | — |

No wet layers: that is what separates it from jelly.

**Glass bottle: the finale, the biggest break**

| Layer | Groups | Behaviour |
|---|---|---|
| Contact | `glass_contact` (3, tonal tink) | — |
| Strain | `glass_creak_loop` (1; 2.5–4.5 kHz notched −5 dB, 2.8 kHz −3 dB, low-passed 9 kHz) + `glass_tick` (8) | Ticks accelerate into the tell, with no screech |
| First crack (c 0.4) | `glass_crack` (6) + `glass_tink` (3) | — |
| **Shatter** (c 0.6) | `glass_shatter` (11 heroes) + `glass_debris` (2) at +80 ms, low-passed 12 kHz | `bsb1121`, the thinnest, suits the Golden variant |
| Crush | `glass_grit` (14) | — |
| Release | debris tinkle | — |
| Reveal | `glass_contact` glitter | — |

Strictly no sustained 2–5 kHz.

**Steel ball: the press loses (the joke ending)**

| Layer | Groups | Behaviour |
|---|---|---|
| Place / contact | `steel_clink` (5) | — |
| Strain | `steel_groan_loop` (1, 4.8 s) at rate 0.85→1.25 + the synth creak at maximum | Ticks run into the red line (`redline` cue) |
| Tell | `steel_groan` (2 swells) | — |
| Failure (the press gives up) | `steel_snap` (hero) → `steel_crash` (2) at +60 ms → `steel_boing` (2) at +350 ms → `steel_ring` tail | — |
| Release / reveal | boing | — |

The ball itself never breaks, so there are no material crush grains.

### 3.3 Press, reveal and UI sounds

| Moment | Layers |
|---|---|
| Approach | `press_hiss_loop` (recorded compressed-air loop, low-passed 9 kHz). The synth band-pass sweep 1.5→6 kHz shapes it. Gain = smoothstep(v) |
| Seal (`.closed`, magnet clap) | Synth ka-chunk (brand) + `press_kachunk_latch` (2: hole-punch, mortice lock) at 0 ms + `press_kachunk_metal` (5) at +8 ms, −4 dB |
| Release (lid lifts) | `press_release` (3 air sighs), gain ∝ opening speed |
| Reveal | Synth sting (fixed, the logo), then `press_stamp` (3) on the PRESSED stamp frame, then the material flourish |
| Unlock / achievement | Synth chime (fixed) + `ui_unlock` (3) at −6 dB under it |
| Menu tap, select, toggle, back, open, close | `ui_click`, `ui_select`, `ui_toggle`, `ui_back`, `ui_open`, `ui_close` (Kenney). Pitch ±0.3 st, −14 dB bus. One light haptic tap (`.selection` semantics) |
| Object placed | Material plop + `ui_drop` (3) at −8 dB |
| HingeFeel (new) and pokes | Keep the synth creak and ratchet (they follow velocity). Pokes should use each object's `contact`/`place` group (duck squeak, can tink, glass clink, crinkle) instead of synth |

### 3.4 Processing already applied (pipeline) vs at runtime

**Pipeline** (`ci/sounds/cut.mjs`):
- decode to 48 kHz mono;
- 2nd-order Butterworth high-pass ×2 (60–200 Hz by role), and low-pass where noted;
- notch EQ on sustained tonal material;
- auto-trim of the lead-in and tail;
- cosine fades;
- equal-power seamless loops (150–400 ms crossfade);
- BS.1770-4 loudness normalisation;
- 4× oversampled true-peak ceiling of −1 dBTP;
- optional look-ahead limiting;
- fixed-seed TPDF dither, so re-runs are byte-identical.

**Runtime:**
- round-robin;
- pitch and gain jitter;
- loop rate and gain from c and v;
- speaker/headphone route EQ and the low-band harmonic exciter (research 02 §6);
- master limiter;
- Soft style (drop `wet` groups, low-pass at 6 kHz, halve grain density).

---

## 4. Haptics paired with each layer

### 4.1 Principle: the sample is the score

Every non-loop file carries `haptics: [[t, intensity, sharpness], …]` in `sounds-manifest.json`:
- **time:** the audio attack, measured;
- **intensity:** 0.15–1.0 from the onset's level against the file peak, on a 30 dB range;
- **sharpness:** 0.05–0.95, on a log scale of the onset's spectral centroid from 200 Hz to 8 kHz.

So a soft thud is 1.0/0.05, a glass shard 0.3/0.95 and a bubble pop 1.0/0.9. The `HapticsController` turns these into `CHHapticEvent` transients. It applies:
- the user level;
- the Duo gain g(θ);
- the 12 ms gap rule;
- the 0.85 cap for non-climax events;
- the EXPERIENCE-PLAN bed cap of 0.55.

It adds one continuous "body" event per class (below). **The haptic and the audio then share one shape automatically, including for files added later.** Recipes may still override with hand-authored notes where a moment needs a specific feel.

### 4.2 Per-layer pairing

| Layer | Haptic | Notes |
|---|---|---|
| Approach (hiss) | None | Anticipation (01 §6) |
| Contact | The file's first manifest event × 0.6, capped at 0.5 | The "kiss" |
| Strain loop | **Continuous bed** on the advanced player: intensity = 0.2 + 0.35·strain (cap 0.55), sharpness = material (glass 0.9, can 0.8, crayon 0.6, gummy 0.3, jelly 0.1), sent as 30 ms curves | Holding keeps the bed (EXPERIENCE-PLAN) |
| Grains (crunch, crumb, grit, pops) | **One transient per grain sample** at its first manifest event: intensity × (0.35 + 0.65·v), no tail. Grain rate is capped at 60/s with a 12 ms minimum gap | The compliance illusion: grains are the main strain sensation |
| Tell | Bed sharpness +0.2, a 14 Hz tremor ±0.08, and micro-crack grains from `*_tick`/`crumb` | 01 §6 step 4 |
| Hush | Bed to 0, grains off for 50–80 ms | — |
| Break body (crack, snap, buckle, splat, split) | All manifest events of the chosen file, plus a continuous tail: crack 0.5/0.3 for 60 ms; splat 0.6/0.05 for 250 ms; buckle rings 0.5/0.3/0.15 at +8/16/24 ms | 1.0 is allowed (climax) |
| Hero (shatter, can crush, steel snap and crash) | All manifest events (up to 24), first event forced to 1.0/1.0 (shatter) or 1.0/0.5 (crush), plus a 120 ms rumble 0.8/0.05 | The only 1.0 moments besides the clap |
| Debris tail | Manifest events × 0.4, sharpness kept | The settle |
| Seal (ka-chunk) | The existing bottom thunk (T 1.0/0.15 + C 0.8/0.05 for 120 ms) + latch events × 0.7 | Lands on the magnet clap |
| Release / wheeze / slurp | Continuous 0.3/0.4 for the file duration, decaying | Relief |
| Reveal | The stamp file's events + the existing two sting taps | Peak–end |
| UI | `UISelectionFeedbackGenerator` or one transient 0.4/0.6 | HIG: sparing |

### 4.3 AHAP vs code, and the sync method

- **Keep haptics in code** (the existing `HapticNote` path, built by `CueBook` in the same call that picks the sample). One shared random choice drives both: Apple's "harmony".
- **Ship AHAP files only as authoring references** for the heroes, so the founder can preview them in macOS Quick Look (WWDC21). The pipeline can emit `<name>.ahap` from the manifest; that is a later task. Example for `glass_shatter_01`, straight from its manifest entry:

```json
{"Version":1,"Pattern":[
 {"Event":{"Time":0.004,"EventType":"HapticTransient","EventParameters":[{"ParameterID":"HapticIntensity","ParameterValue":1.0},{"ParameterID":"HapticSharpness","ParameterValue":0.94}]}},
 {"Event":{"Time":0.004,"EventType":"HapticContinuous","EventDuration":0.12,"EventParameters":[{"ParameterID":"HapticIntensity","ParameterValue":0.8},{"ParameterID":"HapticSharpness","ParameterValue":0.05},{"ParameterID":"Sustained","ParameterValue":0},{"ParameterID":"DecayTime","ParameterValue":0.1}]}},
 {"Event":{"Time":0.059,"EventType":"HapticTransient","EventParameters":[{"ParameterID":"HapticIntensity","ParameterValue":0.57},{"ParameterID":"HapticSharpness","ParameterValue":0.92}]}},
 {"Event":{"Time":0.097,"EventType":"HapticTransient","EventParameters":[{"ParameterID":"HapticIntensity","ParameterValue":0.40},{"ParameterID":"HapticSharpness","ParameterValue":0.95}]}},
 {"Event":{"Time":0.178,"EventType":"HapticTransient","EventParameters":[{"ParameterID":"HapticIntensity","ParameterValue":0.29},{"ParameterID":"HapticSharpness","ParameterValue":0.95}]}},
 {"Event":{"Time":0.270,"EventType":"HapticTransient","EventParameters":[{"ParameterID":"HapticIntensity","ParameterValue":0.52},{"ParameterID":"HapticSharpness","ParameterValue":0.95}]}},
 {"Event":{"Time":0.362,"EventType":"HapticTransient","EventParameters":[{"ParameterID":"HapticIntensity","ParameterValue":0.24},{"ParameterID":"HapticSharpness","ParameterValue":0.95}]}}]}
```

- **Do not use `CHHapticAudioResource` / `AudioCustom` for the app's sound.** It would give sample-accurate sync, but the audio would then bypass our mix, limiter, route EQ, Soft style and `OfflineAudio` (share clips would lose those sounds). There are also crash reports when it is mixed with AVAudioEngine after resets ([forum 763640](https://developer.apple.com/forums/thread/763640)). Keep it as a diagnostic only: a Tuning Lab button that plays a hero through `AudioCustom` and through our path, to A/B the measured skew.
- **Shared timeline:**
  1. Fire both from the same main-thread call.
  2. Audio: the `.sample` command carries `delay = Δ` (default 0).
  3. Haptics: `player.start(atTime: hapticEngine.currentTime + Δ + L)`, where L = `session.outputLatency + session.ioBufferDuration` minus the haptic engine's own latency (≈0 on the built-in speaker; it grows on Bluetooth, research 02 §3.3).
  4. Measure with the existing 240 fps video and contact-mic method, against the ±15 ms budget (EXPERIENCE-PLAN).

  Because the haptic pattern comes from the same file's onsets, a fixed offset is the only error left. That is easy to calibrate once, in `FeedbackTuning`.

---

## 5. Implementation plan (for the engineer)

### 5.1 Architecture: samples as Synth voices (recommended)

**Why not an `AVAudioPlayerNode` pool or `AVAudioUnitSampler`?** Both live outside `Synth`. `OfflineAudio` renders the share clip by replaying `SynthCommand`s through a private `Synth`, so a player pool would need a second offline path: `AVAudioEngine` manual rendering, plus re-timing for slow motion. Pitch per voice would also need a varispeed unit on every node (`AVAudioUnitTimePitch` is banned: ~90 ms latency, research 02). A resampling voice inside the existing render loop is about 60 lines, allocation-free, and makes the share clip correct for free.

**1. `SampleStore` (new, `Squish/Feedback/SampleStore.swift`)**
- At launch, off the main thread, read `sounds-manifest.json` and load every CAF with `AVAudioFile` into **Int16** buffers: 11.3 MB resident, converted to Float in the voice. Keep `[groupName: [SampleID]]`, durations and the haptic onsets.
- After loading, the store is immutable and read-only from the audio thread (`final class`, `@unchecked Sendable`, buffers as `UnsafeBufferPointer<Int16>` allocated once and never freed).
- Optional lazy mode if RAM ever matters: shared groups at launch, the current object on `place`. Not needed at 11 MB.

**2. `SynthCommand.sample(SampleSpec)`**
- `SampleSpec { id: Int32, rate: Float, gain: Float, delay: Float, offset: Float, lowpass: Float }`.
- `Equatable`/`Sendable` stays trivial because it carries an id, not a buffer.
- `Synth.trigger` assigns a voice. `renderVoice` reads with linear interpolation (cubic if it measures better) at `rate` = 2^(st/12) × per-press tone, and applies gain, a 2 ms de-click fade-in when `offset > 0`, and an end-of-buffer stop.
- Raise `Synth.voiceCount` to 32. Steal the oldest *sample* voice first, then synth voices.

**3. Sample-loop beds in `BedParams`**
- Add `strainSample: Int32` (−1 = none), `strainRate` and `strainGain`, plus the same trio for a second bed (`crushSample`: wheeze, fizz, crackle).
- `Synth.renderBeds` reads the seamless loop with a wrapping, interpolating pointer. Gains ramp over 20–40 ms like the existing beds.
- Keep the noise `NoiseBed` as the fallback when a material has no loop, and for Soft style when the loop is `wet`.

**4. `SampleBank` seam → retire it.** The current seam (`AudioController.play` asks the bank per synth layer) can't express layering or timing. Instead:
- Recipes emit `.sample` `SoundLayer`s directly, picking with `input.dice.pick(count, for: slot)`. That keeps share clips replayable and harmony with haptics.
- Add a helper: `SoundLayer.sample(_ slot: SoundSlot, group: String, dice:, pitch:, gainDb:, delay:)`. It resolves the group through `SampleStore` and returns the layer **plus** the haptic notes from the manifest, so a recipe writes one line per layer.
- Keep each recipe's synth layers that do not compete: thumps, sub harmonics and modal rings. Delete the synth layers the samples replace: noise crunch bodies, synth pops, synth squeaks.

**5. `OfflineAudio`**
- `retimed(.sample)` multiplies `rate` by `pitch` (slowed tape) and divides `delay` by `pitch`.
- `retimed(BedParams)` multiplies the loop rates by `pitch`.
- `OfflineAudio.render` must make a `Synth` that sees the same `SampleStore` (pass `SampleStore.shared` into `Synth.init`).
- Nothing else changes: the score already records every command and bed.

**6. Mix**
- The new bus trims come from the manifest's `gainDb`, then from a per-object trim table in `FeedbackTuning`. Re-run the Diagnostics loudness test, which must stay at −16 ±3 LUFS.
- Re-balance the recent "+6.8 dB bed bus" (commit 593f4fb): recorded loops are already normalised to −24/−26 LUFS-I.

**7. Soft style:** skip groups with `wet: true`. Halve the grain rate (already done). The master 6 kHz low-pass already applies.

### 5.2 Bundle layout and project.yml

```
Squish/Resources/Sounds/
  LICENSES.md                 generated provenance (every file: source, author, licence, URL, excerpt)
  sounds-manifest.json        generated groups: files, dur, class, gainDb, pitch, wet, haptics
  press/  bubblewrap/  duck/  jelly/  crayon/  egg/  cake/  can/  gummy/  glass/  steel/  ui/
    <object>_<layer>_<NN>.caf  48 kHz mono 16-bit LE PCM
```

- **project.yml needs no change.** `sources: - path: Squish` already contains `Squish/Resources`. XcodeGen puts non-source files (`.caf`, `.json`, `.md`) into Copy Bundle Resources, and the `Resources/Sounds/*` folders become groups. They are flattened into the bundle root, so look files up by name: `Bundle.main.url(forResource: "glass_shatter_07", withExtension: "caf")`.
- The cutter rejects duplicate basenames, so the flattening is safe.
- If a folder structure in the bundle is ever wanted, add `- path: Squish/Resources/Sounds` with `type: folder` and exclude it from the main source path. That is not needed now.
- **CI check to add** (`ci.yml`, after the build): every `*.caf` in the built app appears in `LICENSES.md`, and the count matches `sounds-manifest.json`. Mirror the existing privacy-manifest check.

### 5.3 Memory, CPU and size budget

| Item | Budget |
|---|---|
| Bundle | 11.3 MB now; ceiling 15 MB. Phase-2 private packs must replace files, not add to them, or the ceiling moves deliberately |
| RAM | 11.3 MB Int16 resident (all groups). A 32-voice resampler at 48 kHz is well under 1 % of one core |
| Launch | Decoding 274 small PCM files ≈ 50–100 ms on a background task. The press stays usable with synth fallbacks until `SampleStore.isReady` |

### 5.4 The pipeline (already built, `ci/sounds/`)

| File | What it does |
|---|---|
| `sources.tsv` | 140 pinned sources: URL, sha256, author, title, page, licence |
| `fetch-decode.sh` | Fetch, verify sha256, decode to 48 kHz mono WAV (ffmpeg; Kenney zips member by member) |
| `make-cuts.sh` | The shopping list as code. Writes `cuts.tsv` (274 rows; `p` = onset slicing, `r` = hand-picked windows) |
| `propose.mjs` | Onset-based slicer for dense sources (grains, pops) |
| `cut.mjs` + `dsp.mjs` | Cut, filter, EQ, loops, normalise, limit, CAF writer; `report.tsv`, `LICENSES.md`, `sounds-manifest.json` |
| `.github/workflows/sounds.yml` | Manual: fetch → decode → cut → ffmpeg EBU R128 cross-check (run 40118031889 read all 269 CAFs of that run) |

To re-cut on any machine:

```
gh workflow run sounds.yml -f cut=true
# then download the sound-decoded artifact and run:
node ci/sounds/cut.mjs <decoded> ci/sounds/cuts.tsv Squish/Resources/Sounds
```

**To swap in Freesound originals** (better than the previews):
1. The founder logs in and downloads the IDs listed in `LICENSES.md`.
2. Put them in a local folder and point `sources.tsv` at them (or decode them locally).
3. Re-run the cut. The time windows match, because previews keep the timeline.

---

## 6. The shopping list (what was sourced)

All entries are CC0. Every file's exact excerpt is in `Squish/Resources/Sounds/LICENSES.md`.

| Object / layer | Group (files) | Source(s) | Why |
|---|---|---|---|
| Press hiss bed | `press_hiss_loop` (1) | [Compressed Air Pressure Release Valve Loop, kkenny101](https://freesound.org/people/kkenny101/sounds/861613/) | A designed loop; steady pneumatic air |
| Press release sigh | `press_release` (3) | [Soft Swish Air Release, mbezzola](https://freesound.org/people/mbezzola/sounds/275550/); [Air release, davidlay1](https://freesound.org/people/davidlay1/sounds/416080/); [Slips air release, mcpable](https://freesound.org/people/mcpable/sounds/131934/) | Gentle exhales, high SNR |
| Ka-chunk latch | `press_kachunk_latch` (2) | [Office hole puncher, Tycoh](https://freesound.org/people/Tycoh/sounds/460352/); [Mortice lock, Woodstokk](https://freesound.org/people/Woodstokk/sounds/538379/) | Mechanical "chunk" with mass |
| Ka-chunk metal | `press_kachunk_metal` (5) | [Kenney Impact Sounds](https://kenney.nl/assets/impact-sounds), impactMetal_heavy | Metal body |
| Contact thud | `press_contact_soft` (5) | Kenney impactSoft_medium | Soft low thud (centroid ~100 Hz; the exciter makes it audible on speaker) |
| Reveal stamp | `press_stamp` (3) | Kenney impactPlate_light | Stamp thunk |
| Bubble wrap pops | `bubblewrap_pop` (12), `_popsmall` (10), `_popbig` (7) | [Bubble wrap, Macif](https://freesound.org/people/Macif/sounds/214675/); [Bubble Wrap Pops Small, loganzsound](https://freesound.org/people/loganzsound/sounds/875514/); [BigSoundBank Bubble wrap: Breakouts](https://bigsoundbank.com/s0462.html) | Isolated, clean pops in three sizes |
| Bubble wrap crinkle | `bubblewrap_crinkle_loop` (1), `_crinkle` (2) | [HeavyPlasticCrinkle, fthrll](https://freesound.org/people/fthrll/sounds/522200/); [Crumpling Plastic, OwlStorm](https://freesound.org/people/OwlStorm/sounds/151216/) | Strain bed and contact |
| Duck squeaks and honk | `duck_squeak` (6), `duck_honk` (1) | [Rubber-Duck_Squeezes, LamaMakesMusic](https://freesound.org/people/LamaMakesMusic/sounds/403507/) (96 kHz) | A real duck; clean comic squeaks; one long squeal for the honk |
| Duck low squeaks | `duck_squeaklow` (2) | [Squeaky Toy #4, Breviceps](https://freesound.org/people/Breviceps/sounds/483922/); [Squeeze Toy, survivalzombie](https://freesound.org/people/survivalzombie/sounds/240015/) | Lower pitch, less harsh |
| Duck wheeze | `duck_wheeze` (2), `_wheeze_loop` (1) | [Deflating Balloon, VKProduktion](https://freesound.org/people/VKProduktion/sounds/217351/); [balloon deflate, hareball101](https://freesound.org/people/hareball101/sounds/326756/); [Balloon Expels Air, Terry93D](https://freesound.org/people/Terry93D/sounds/329946/) | Comic deflation after the seam pop |
| Jelly strain | `jelly_squelch_loop` (2) | [squishing gel between hands, breadparticles](https://freesound.org/people/breadparticles/sounds/575333/); [slime kneading, breiti](https://freesound.org/people/breiti/sounds/587848/) | Wet gel, continuous |
| Jelly grains | `jelly_squelch` (14) | [Gel Squelches, mincedbeats](https://freesound.org/people/mincedbeats/sounds/593990/); [squishes, Cheddrock](https://freesound.org/people/Cheddrock/sounds/412919/) | Many distinct squelches |
| Jelly splat | `jelly_splat` (5) | [Splat/Squish 4, mrickey13](https://freesound.org/people/mrickey13/sounds/515621/); [squished, FairCashew](https://freesound.org/people/FairCashew/sounds/686363/); [Squishes, JelloApocalypse](https://freesound.org/people/JelloApocalypse/sounds/802616/) | Skin-split body. The last source is titled "mud, fruit and blood"; only neutral squishes were cut |
| Jelly wobble and slurp | `jelly_wobble` (3), `jelly_slurp` (2) | [Jelly Wobbling on Plate, lolamadeus](https://freesound.org/people/lolamadeus/sounds/181918/); [jellybounce, Mixtos](https://freesound.org/people/Mixtos/sounds/463590/); [Floppy Jelly Goo, SnowFightStudios](https://freesound.org/people/SnowFightStudios/sounds/681950/) | Elastic life |
| Crayon snaps | `crayon_snap` (6) | [pencil snap, richwise](https://freesound.org/people/richwise/sounds/476831/); [breaking a pencil, an_na_ba_na_na](https://freesound.org/people/an_na_ba_na_na/sounds/486374/); [pencilsnap, Reitanna](https://freesound.org/people/Reitanna/sounds/215382/); [Twig Snap 05, Glitchedtones](https://freesound.org/people/Glitchedtones/sounds/322416/); [twig snap classic, martian](https://freesound.org/people/martian/sounds/251464/); [twig snap, kyles](https://freesound.org/people/kyles/sounds/452570/) | Crisp snaps, low-passed to read as wax |
| Crayon crumbs and tap | `crayon_crumb` (11), `crayon_tap` (1) | 486374 above; [Celery breaking, mrmccormack](https://freesound.org/people/mrmccormack/sounds/116595/); [crayon falling, Ottomaani138](https://freesound.org/people/Ottomaani138/sounds/232900/) | Dry crumble; a real crayon tap |
| Egg cracks | `egg_crack` (6) | [egg crack 01, Anthousai](https://freesound.org/people/Anthousai/sounds/336613/) (96 kHz); [Cracking Egg, MTJohnson](https://freesound.org/people/MTJohnson/sounds/426307/); [egg crack8, Reitanna](https://freesound.org/people/Reitanna/sounds/244739/); [Egg crack and pulp, xenognosis](https://freesound.org/people/xenognosis/sounds/137238/) | Real shells |
| Egg ticks, crunch and yolk | `egg_tick` (8), `egg_crunch` (12), `egg_yolk` (2) | [egg crack22](https://freesound.org/people/Reitanna/sounds/244749/) and [egg crack20](https://freesound.org/people/Reitanna/sounds/244743/), Reitanna; [Egg shell crunching, greenlinker](https://freesound.org/people/greenlinker/sounds/757512/); 137238 above | Micro-cracks; crush grains; the wet layer |
| Cake | `cake_squish_loop` (2), `cake_crumb` (10), `cake_collapse` (2), `cake_squirt` (2), `cake_icing` (2) | [whipped cream, ToddBradley](https://freesound.org/people/ToddBradley/sounds/32921/); [sponge, sangtao](https://freesound.org/people/sangtao/sounds/190456/); [Graham Cracker Steps, newagesoup](https://freesound.org/people/newagesoup/sounds/414310/); 593990 above; [crunch crispy breadbun, Slowmote](https://freesound.org/people/Slowmote/sounds/406336/) | Soft, creamy, crumbly; no eating sounds |
| Can buckles | `can_buckle` (11) | [nahmandub 131323](https://freesound.org/people/nahmandub/sounds/131323/); [DMDoom 445240](https://freesound.org/people/DMDoom/sounds/445240/); [383450](https://freesound.org/people/deleted_user_7146007/sounds/383450/); [MutilatorBCB 689774](https://freesound.org/people/MutilatorBCB/sounds/689774/); [MrFossy 521896](https://freesound.org/people/MrFossy/sounds/521896/); [Kraftaggregat 735890](https://freesound.org/people/Kraftaggregat/sounds/735890/) | Six different cans: real variety |
| Can crush, strain, crumple | `can_crush` (2), `can_strain_loop` (1), `can_crumple` (12) | [BigSoundBank Can that are crushed](https://bigsoundbank.com/s0118.html); [Soda can slow crush, Valerie-Vivegnis](https://freesound.org/people/Valerie-Vivegnis/sounds/758998/) | Hero crush; a slow crush gives a true strain bed |
| Can fizz and tink | `can_open_fizz` (2), `can_fizz_loop` (1), `can_tink` (5) | [Opening can with fizz, MutilatorBCB](https://freesound.org/people/MutilatorBCB/sounds/689705/); [BigSoundBank can opening](https://bigsoundbank.com/s0116.html); [Opening soda can, Kodack](https://freesound.org/people/Kodack/sounds/256317/); Kenney impactTin_medium | The fizz reveal moment |
| Gummy | `gummy_stretch_loop` (1), `gummy_squish` (5), `gummy_split` (3), `gummy_boing` (1) | [rubbery-crumple, alienistcog](https://freesound.org/people/alienistcog/sounds/125160/); [rubber.wav, Anthousai](https://freesound.org/people/Anthousai/sounds/399008/); [Rubber squeeze 6](https://freesound.org/people/deleted_user_2104797/sounds/330249/); 686363 above; [Cartoon Wobble, Breviceps](https://freesound.org/people/Breviceps/sounds/542195/) | Chewy and rubbery, deliberately not wet |
| Glass strain | `glass_creak_loop` (1), `glass_tick` (8) | [glass creaking, sgarrison2127](https://freesound.org/people/sgarrison2127/sounds/174754/) (notched); [Ice cracking, timbreknight](https://freesound.org/people/timbreknight/sounds/342546/) | Tension without screech |
| Glass crack and tink | `glass_crack` (6), `glass_tink` (3), `glass_contact` (3) | [Hard Glass Impact](https://freesound.org/people/deleted_user_3656686/sounds/418194/); [Ice Crack 1, j_p_higgins](https://freesound.org/people/j_p_higgins/sounds/262635/); 342546; Kenney impactGlass_medium and _light | First crack plus a glass ring |
| **Glass shatter (hero)** | `glass_shatter` (11) | [Glass Break, unfa](https://freesound.org/people/unfa/sounds/221528/) (34k downloads); [Breaking a glass bottle, dasebr](https://freesound.org/people/dasebr/sounds/212698/); [abstraktgeneriert #1](https://freesound.org/people/abstraktgeneriert/sounds/233607/) and [#3](https://freesound.org/people/abstraktgeneriert/sounds/233605/); [Glass Breaking, AlterKartoffelsack](https://freesound.org/people/AlterKartoffelsack/sounds/465946/); [BigSoundBank champagne glass](https://bigsoundbank.com/s1591.html); [Bottle Smash, Roxis_Boy](https://freesound.org/people/Roxis_Boy/sounds/401619/) ×2; [Glass Bottle Breaking, IENBA](https://freesound.org/people/IENBA/sounds/607910/) ×2; [BigSoundBank Christmas ball](https://bigsoundbank.com/s1121.html) | The biggest climax gets the deepest pool |
| Glass debris and grit | `glass_debris` (2), `glass_grit` (14) | [Glass Shattering and Falling, 221Beimesche](https://freesound.org/people/221Beimesche/sounds/336425/); [shattered frame shards, SpliceSound](https://freesound.org/people/SpliceSound/sounds/156579/); [Screen protector cracking, unfa](https://freesound.org/people/unfa/sounds/610933/) | The settle; fine crush grit |
| Steel strain | `steel_groan_loop` (1), `steel_groan` (2) | [Creaking Metal – Slow, EagleStealthTeam](https://freesound.org/people/EagleStealthTeam/sounds/172411/); [Metallic Groan, hinchinbrook](https://freesound.org/people/hinchinbrook/sounds/496836/); [metal crank groan, kyles](https://freesound.org/people/kyles/sounds/453333/) | Deep, low (centroid ~600 Hz), no squeal |
| Steel failure | `steel_snap` (1), `steel_crash` (2), `steel_boing` (2), `steel_ring` (1) | [Trap Springing Shut, qubodup](https://freesound.org/people/qubodup/sounds/752070/); [Metal Chunk crash, qubodup](https://freesound.org/people/qubodup/sounds/859154/); [metal smash, gristi](https://freesound.org/people/gristi/sounds/562198/); [SpringBoing, Slanted](https://freesound.org/people/Slanted/sounds/510496/); [Metal impact – Long, Vrymaa](https://freesound.org/people/Vrymaa/sounds/789214/) | The press loses, comically |
| Steel clink | `steel_clink` (5) | [Steel balls into a box, Ted_Erski](https://freesound.org/people/Ted_Erski/sounds/535286/) | A real ball bearing |
| UI | `ui_click` (2), `ui_select` (2), `ui_toggle` (2), `ui_back`, `ui_open`, `ui_close`, `ui_unlock` (3), `ui_drop` (3) | [Kenney Interface Sounds](https://kenney.nl/assets/interface-sounds) | Clean, consistent, CC0 |

**Fetched but not cut** (available in `sources.tsv` for re-cuts): 48 more Freesound candidates (more bubble wrap, squeaky toys, slime, sponges, can opens, rubber squeaks, metal creaks), 3 BigSoundBank glass recordings, and Kenney UI Audio. The decoded set is the `sound-decoded` artifact of the `sounds.yml` runs.

**Gaps a recording or a paid pack would fill best:**
- a real crayon snap;
- a real gummy bear squash;
- a slice of cake pressed;
- a full glass *bottle* crush under a press, rather than dropped or smashed.

The founder phone-foley list in research 02 §5.3 covers the first three in about 20 minutes.

---

## 7. Acceptance: the founder's ears

1. **Speaker at 50 %, then AirPods.** Press each object three times: slowly, fast, and wobbling.
2. **For each object, answer three questions:**
   - Did the strain build?
   - Did the break land with the vibration?
   - Any wince, i.e. a harsh or squealy sound?
3. **Press glass and egg 20 times each.** Does anything sound like the same recording twice?
4. **Silent switch on** (sound still plays, by default). Turn sound off in Settings: does the haptic-only press still satisfy?

Report findings by object and layer name (e.g. "glass_shatter too thin"). Each finding maps to a row in `ci/sounds/make-cuts.sh`: swap the source or the window, re-run the cut, done.

**Known risks:**
- The previews are lossy (~200 kbps OGG). This is inaudible on the phone speaker but may show on AirPods; the fix is the Freesound originals.
- The ice-crack ticks may read as "ice" rather than "glass".
- The duck honk is the most tonal file; it is notched, but check it for harshness first.
- `press_contact_soft` is very low (~100 Hz) and relies on the exciter to be heard on the speaker.
