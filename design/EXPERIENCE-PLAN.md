# Experience plan: making the squish great (24 Oct 2026)

This is the lead's synthesis of `design/UX-AUDIT-2.md` and `design/research/EXPERIENCE-2.md`, written after the founder's first real-Duo test. Where they conflict with older docs (the bible, FOLD-PRESS), **this plan wins**.

**The founder's priority, in order:**
1. **Satisfaction in the squish itself.**
2. Knowing what to do (no intro existed).
3. Finding the menu.
4. Objects that make sense.

Sound was missing entirely: the phone was on Silent and the app used `.ambient`. Vibration was weak.

## Decisions (lead, with the founder's delegation)

1. **Sound plays in Silent mode.** The session is `.playback` + `.mixWithOthers`. Settings → Sound has "Play when phone is on Silent", **default ON**.
2. **Words are allowed where they prevent confusion.** The old "zero text" pillar yields:
   - a 10-second taught first run;
   - coaching lines for the first 5 presses;
   - verbs on objects.

   Keep the text short, warm and funny.
3. **The squash happens where the eye sees the lid arrive.** Move contact and failure to angles where the lid is visibly close to the object. Until the real-Duo hinge log arrives, use provisional values and keep them in `PressConfig`.
4. **Objects deform all the way, including the duck's face.** Cartoon, no gore, still 9+.
5. **Recorded foley is the core of the sound,** CC0 or free-for-commercial only, with every file's licence logged. Code synthesis stays for the continuous strain bed that follows the hinge, and for brand UI sounds.
6. **Ask for nothing before the first reveal:** no Game Center, no review prompt, no toasts.
7. **The roster is framed as "The Museum of Pressed Things":**
   - three wings escalating soft → crunchy → tough;
   - a vault for the steel ball;
   - each object shows a verb (Pops / Cracks / Shatters / Oozes / Buckles…) and a plain unlock line with live progress.

   Crayon becomes a **Crayon Box** with a rainbow smear. The gummy must clearly differ from the jelly: chewy stretch and a seam split, against wobble and splat.
8. **There is always a way out and a way in:**
   - a ☰ Menu key is always visible on the console;
   - Settings is one tap from home, the reveal and the cover;
   - the Tuning Lab stays hidden but its Diagnostics are mirrored into Settings → About → "Sound & vibration check".

## The press, beat by beat (the build target)

| Beat | What happens |
|---|---|
| **Anticipation** | Idle object life (a breathing sheen, a little wobble). The lid shadow grows as the hinge closes. A soft creak starts before contact. |
| **Contact** | A visible kiss plus a short "tick" haptic and sound, at an angle where the lid really is near. |
| **Resistance ("lag, then give")** | Visual compression lags the hand (gain about 0.35) as the object resists, with the strain bed rising in sound and continuous haptic. A deformation event at least every 8°: bulge, creak, first crack, ooze. **Holding still keeps the tension alive**: the bed holds, never fades to silence. |
| **Tell** | 150–300 ms before the break: a creak spike, a tremor, a haptic swell. |
| **Break (scored in 5 parts)** | 1. hush 50–80 ms; 2. object-only hit stop 70–140 ms; 3. burst with flash, a 1.0 haptic transient and the sound in the same frame; 4. debris at 0.3× speed for 250–400 ms; 5. a 1–2 s settle. The backlog of compression releases in about 80 ms. |
| **Flatten and seal** | Persistent splatter and ooze from the pinch line. A big ka-chunk on close, both haptic and sound. |
| **Reveal ceremony** | The lid lifts; a slow-mo replay pushes in on the break; then before → after with a measurement ("42 mm → 1.8 mm"), the stamp, stats counting up (tons, badges), and the collection slot filling with a flash and chime. Fold-to-keep works only after 2.5 s, with a hint. |
| **Next** | "Up next: Egg · cracks". A reason to press again: an unlock line, a rarity line, or "try it slower for a Perfect". |

**How you close changes the result:** slow earns a Perfect stamp, fast a SLAMMED stamp (no reward), pumping a PUMPED ×N stamp.

**Variety engine:** seeded variation; no sound, haptic or flavour line repeats twice in a row.

## Screens (from UX-AUDIT-2 §4, adopted)

| Screen | Contents |
|---|---|
| S0 | Launch: a 1.2 s plates-slam brand beat; waits for the first hinge reading |
| S1 | Welcome and fold lesson: under 10 s, replayable; a live pose card, a sound check with a Silent line, a practice Bubble Wrap |
| S2 | Press Room (home): gauge, ☰ Menu, coach line; object tray with picture and verb; Shelf with count; next-unlock line |
| S3 | The Tray (object picker as Museum wings) |
| S4 | Pressing |
| S5 | Reveal ceremony |
| S6 | Collect → Next |
| S7 | Collection: Objects / Squished / Achievements |
| S8 | Menu: Resume, Objects, Shelf, How to press, Settings, About |
| S9 | Settings: test buttons, the Silent explanation, Fold/Drag, Replay intro |
| S10 | Pause and Help |
| Cover C1–C3 | Lobby on the outer display; first-run "Open me to start"; Sealing / Sealed (no print spoiler) / Releasing; Paused |

## Haptics (Duo)

- The strain bed is capped at about 0.55, so peaks stand out; grains are the main strain sensation.
- Every haptic lands within ±15 ms of its sound.
- **A full press must still satisfy with sound off.**
- Tune against the founder's device. The Diagnostics "Test full press feel" button is the reference.

## Process

Each round runs as follows:
1. Parallel engineers with disjoint file ownership.
2. CI green.
3. The store run plus a design critique.
4. **A TestFlight build** for the founder.
5. Three device questions for the founder: Did it resist? Did the break land? Did you want another?

The lead keeps iterating until the critique and the founder's feel answers are both strong.
