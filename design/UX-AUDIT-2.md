# Squish: UX Audit 2 (after the first real-Duo test)

*24 Oct 2026. Product-design audit before the experience redesign. Inputs: `CLAUDE.md`, bible §3 and §5, `FOLD-PRESS.md` §5–§8, `UX-REVIEW-1.md`, the UI code (`Squish/UI/*`), the parts of `PressDirector`, `FoldPressController`, `AudioController` and `PressScene` that decide what a user sees and hears, and the r14 Duo frames (`store-duo/duo-screens/*`, the `raw/` inner and cover captures, and `verify/`). This is a first draft for the lead to merge with the research.*

> **The founder, on a Release TestFlight build on a real iPhone Duo:** "the app works but… there is no menu, there is no sound… no proper menu items, no settings, no introduction, nothing at all… the things also need to make sense… the user experience really needs to be refined drastically."
>
> **In priority order:** (1) "satisfaction in squishing is really the biggest thing that needs to be achieved"; the press felt flat. (2) They didn't know what to do, because there was no intro. (3) They couldn't find the menu.

**Verdict:** the founder is right on every count, and each complaint has a direct cause in the code.

- **The press loop is engineered well.** The engine, the mapping, the print, the cover card and the fold-to-collect gate are all careful work.
- **The product around the loop was designed for screenshots, not for a person holding the phone for the first time.**
  - The design rule "zero UI, teach without words" (bible §3.2, FOLD-PRESS §7) was applied so strictly that the Duo build has no words that teach, no visible menu, no settings entry on the press screen, no help, and no pause.
  - The one first-run sentence is a safety warning.
  - The only on-device teaching cue, the lid's sheen sweep, plays only when the phone lies within 8° of flat.
- **The crush itself is also undersold.** It is built mostly from zero-depth 2D cues that play while the user's eye is at a grazing angle. The climax happens in the dark, and the one big payoff (the ka-chunk card) is a text card on the cover.

Every score in `FOLD-REVIEW-1…9` was given to simulator frames. Those frames are flat captures with no person in them, so none of the reviews could see these problems.

---

## 0. Evidence: what the frames are, and what they are not

| Frame set | What it is | Can a user see this? |
|---|---|---|
| `duo-screens/<obj>-tabletop-{150,112,90,75,62,45,closed,reveal}.png` (= `raw/*-inner.png`, `raw/*-cover.png`) | Flat captures of the inner/cover display during a scripted `hinge` sweep. Tabletop layout. The hinge stops at each angle | Yes, the pixels are real. But a real user sees the top half **tilted toward them** and the anvil **at a grazing angle**, never flat-on like this |
| `*-storeshot-*-eye.png`, `*-pair.png`, `*-hero.png` | `FoldStoreShot` marketing renders of a modelled folded Duo | No. They are composites |
| `duo-shelf.png`, `duo-settings.png`, `duo-cover-launch.png` | DEBUG demo states (`-squishDemo shelf/settings/cover`) with a **seeded collection** (7/10 pressed, Golden egg, 9 unlocked) | No. On first launch the Shelf is empty, the cover shows "Your pressed specimens land here." and 6 chips, and Settings shows the defaults (Workshop, Full, Captions off, Press without folding **off**). The `07-settings` frame shows Soft + Captions on + Press without folding **on**, which no new user ever sees |
| `verify/duo-reveal-toast-app.png` | The app's own window, 0.6 s after the first reveal toast, on a fresh install | Yes. It's the closest thing we have to a first-run frame |

There is **no frame of the first launch, the idle press room, the object menu open, or the Shelf/Settings path**, on any device. Section 1 reconstructs them from the code.

---

## 1. What a first-time Duo user sees and can do, second by second

### 1.1 First launch, phone open in the hand (≈150–175°, book or tabletop)

| t | What happens | Source |
|---|---|---|
| 0.0 s | Full-bleed, with no status bar or home indicator. The background is the gel colour. **No splash, title, wordmark or sound.** | `RootView.body` (`.statusBarHidden`, `.persistentSystemOverlays(.hidden)`) |
| 0.0 s | **Until the first `onHingeChange` callback, the app thinks it is a non-folding phone:** `hingeAvailable = false`, so it renders the **P-48** machine and arms the touch press. On a Duo that P-48 has **no drag handle** (`PinchHandle` shows only at aspect ≤ 0.58; the Duo inner display is 0.70). If the system doesn't deliver an initial hinge context on appear, a Duo lying still stays on the P-48 until the hinge moves. **Unverified on hardware. Check the Tuning Lab log.** | `PressDirector.start`, `HingeReader`, `PinchHandle.maxAspect` |
| ~0.0 s (hinge known) | Fold Press stage: platen half (steel plate, empty), crease band, anvil half (steel plate), yellow rails, hazard jaws. **Crown strip:** a 56 pt gauge at 0, a nameplate showing the **live hinge angle** ("157°"), READY green / LOAD grey. **Console:** `[● BUBBLE WRAP ⌃⌄]` chip and `[▦ Shelf]` key (no count yet), and a pilot lamp | `rubberDuck-tabletop-150.png` (same chrome) |
| ~0.0 s | **Toast: "ON-SCREEN ONLY · Never close your phone on real things."** (red hand icon) in the fold toast slot. It stays until the first press starts, and counts as seen after 3 s. **These are the first and only words the app says to a new user.** | `RootView.hingeArrived`, `TipCenter.safety` |
| 0.9 s | Bubble Wrap drops onto the anvil, with the landing squash, a plop and a light tap (if sound is audible, see §3) | `FoldPressController.update` (`objectPresent` after 0.9 s) |
| 0.9 s → | **If the hinge reads ≥ 172°:** the platen sheen sweeps far edge → crease every 4 s ("the lid breathes"). **If 130–172° (how most people hold an open foldable):** nothing animates except a 0.3 t gauge wobble. **If < 130°:** after 1 s, "OPEN IT UP · Open your iPhone flat to start a press." plus a reversed sweep | `FoldPressController.sweep` (`angle >= 172`), `RootView.scheduleOpenUp` |
| 8 s → ∞ | **Nothing else, ever.** The spec'd last-resort coach "Set it on a table. Push the top down slowly." (FOLD-PRESS §7.6, bible §6.4) **is not implemented**. The ghost arc and two-hand grip glows (`PressHints`) **never render on any device** (§2.1 #9). There is no idle sound: the room tone in bible §3.1 beat 1 isn't in `AudioController` (idle → no beds) | grep: no "Set it on a table" string; `AudioController.update` `.idle: break` |

**What the user can do at this point:**
- fold the phone (not suggested anywhere, except by the safety warning's word "close");
- tap the chip (a system pull-down menu of object names);
- tap `Shelf`;
- swipe up on the Shelf key (undocumented).

### 1.2 Choosing an object

- **Inner display:** the only picker is `ObjectChipPicker`, a SwiftUI `Menu` that drops down from the console chip.
  - It lists **names only**: Bubble Wrap, Rubber Duck, Jelly, Crayon, Egg, Cake Slice (6 open at start).
  - Then a "Locked" section of greyed rows: "Soda Can · squish 3 different things", "Gummy Bear · squish 6 times", "Glass Bottle · press slowly, never ease off", "??? · some things won't squish".
  - There is no picture, no hint of what an object does, and no reason to choose one over another.
  - The chip is a 12 pt mono label on a beige keycap at the bottom edge. In tabletop pose it lies flat on the table edge, facing the ceiling.
- **Second picker:** the Shelf's Objects grid. Tap a sticker to place it, or use its context menu ("Put on the Anvil", "View Best Card").
- **Third picker, on the cover (phone closed):** a two-column chip grid. It's the **best picker in the app**, and it's on the screen you use least (`duo-cover-launch.png`).
- **After every collect,** `next()` auto-advances to the next unlocked object, so most users never choose at all. Bubble Wrap → Duck → Jelly → … in catalogue order.

### 1.3 Pressing (tabletop; book is the same, rotated)

| Hinge | What the user sees, hears and feels | Evidence |
|---|---|---|
| θ0 (open) → first closing sample | The safety toast disappears, the chip dims to 40% and goes inert, and **the Shelf key vanishes**. **Nothing on screen can now be tapped.** There's no pause and no menu | `IdleConsole(chipOnly:)`, `rubberDuck-tabletop-150.png` |
| θ0 → contact (min(132°, θ0 − 12°)) | A soft shadow of the object appears on the platen. The hinge nameplate counts down. Pneumatic hiss with closing speed, a quiet motor hum. **No haptic (by design: "anticipation").** The object doesn't change | `*-tabletop-150.png` |
| contact (~132°) | The platen "kiss" (the shadow sharpens to a print), a soft haptic transient, a contact thud, a 2 t needle kick, LOAD amber. **The real lid is still ~50° away from the object**: it squashes under nothing | `*-tabletop-112.png`: a yellow disc on the platen, the duck essentially undeformed |
| 132° → failure | Squash and bulge on the anvil (analytic). Gauge ticks every 5°, climbing a pentatonic scale. Strain bed haptic ≤ 0.7, grains per degree, a creak. Platen print grows | `rubberDuck-tabletop-75.png`: duck ~50% squashed, gauge ~37 t; `sodaCan-tabletop-75.png`: the can barely buckled |
| failure (96–64°; soft objects 73–64°) | Hit-stop, a fracture event, the object-local shake, the **top half flashes white for ~34 ms**, the platen splat and droplets. The **readout freezes in red at the failure angle**, failure haptic 1.0 | `rubberDuck-tabletop-45.png` (frozen "65°"), `glassBottle-tabletop-62.png` (frozen "82°", shards) |
| failure → 48° (visual flat) | The crush bed, spread meshes. The platen darkens as the "lid shade" comes in | `jelly-tabletop-62.png` |
| ~55–20° | **The inner display goes dark** (system), and rendering pauses (`FoldRenderGate`). Audio and haptics run blind | FOLD-REVIEW-7 N10 |
| `.closed` | Cover display: **PRESS SEALED · 55 TONS · "WHAT'S LEFT?" + the platen print · OPEN TO SEE**, with the ka-chunk sound and haptic | `rubberDuck-tabletop-closed.png` |

Captions (POP!, CRACK!) are **off by default**. Coaching appears only after **two slams in a row**: "SLOW IS SMOOTH · Close it slowly… it's more satisfying." It shows after the reveal, at most 3 times ever.

### 1.4 The reveal

1. **The reveal fires the instant the phone starts to reopen** (~20°), with the display still dark.
2. **When the display lights at ~55°, the finished diptych is already there.** The print is on the platen with a red PRESSED stamp and a "NEW BEST" ribbon. The flattened object is on the anvil. A paper label reads `RUBBER DUCK · 1 HONK · 1 SEAM POP · AT 65°`. `Again · Share · Next` sit in the console. All of it appears with **no animation by design** (FOLD-REVIEW-7 N10).
3. **Then the reveal beats run:**
   - the stamp thunk;
   - goo strands or the peel shimmer;
   - the anvil glint;
   - the reveal sting.
4. **1.5 s later,** toasts appear one at a time, 3 s each: PERFECT SQUISH, NEW OBJECT UNLOCKED, ACHIEVEMENT · FIRST SQUISH (`verify/duo-reveal-toast-app.png`).
5. **The crown keeps showing "65°" in red while the needle sits at 0** (`rubberDuck-tabletop-reveal.png`). The tonnage the cover just announced (55 TONS) **appears nowhere on the inner reveal**.

**Ways out of the reveal:**
- **Next** (yellow): collects the card and loads the next object.
- **Again:** collects the card and reloads the same object.
- **Share:** a tap shares the clip; a long-press offers the still.
- **Fold-to-collect (silent):** happens 0.8 s after the reveal, once the hinge has been ≥ 100° and then **folds 20° below its peak for 0.25 s**, or closes. Someone who opens to 170° and settles back into tabletop at 110° **collects without knowing it**. The diptych vanishes and a new object drops in. There's no "kept" moment, only a 0.4 s card flight into a Shelf key that appears for the flight (`RevealCollectGate`, `RootView.collect`).
- **Review prompt:** asked once, after a reveal, after 10 presses.

### 1.5 Getting to the Shelf and Settings

- **Shelf:** Press room (idle only) → tap `Shelf`, or swipe up on it → Shelf sheet at `.large`.
  - In tabletop the Objects grid sits on the lid half and "Recently squished" on the anvil half.
  - Tabs: OBJECTS / SQUISHED. Header: "7/10 PRESSED · 7 SQUISHES" and a progress bar.
  - The **gear** and **X** buttons are top right (`duo-shelf.png`).
- **Settings:** Shelf → tap the **gear** → a Settings sheet stacked on the Shelf sheet.
  - Sound: on/off, Workshop/Soft. Feel: Haptics Off/Soft/Full, Captions, Press without folding, Reduce Motion (info only). Game Center. About: Version, Golden odds, a credits line.
  - **Settings is two taps deep, behind a key labelled "Shelf".** Only VoiceOver users hear the hint "Opens your collection and settings".
  - It can't be reached during a press, from the reveal, or from the cover.
- **Tuning Lab:** Settings → **long-press the Version row for 0.8 s**. This is present in Release, not DEBUG-only. Nothing points to it, which is right for a debug tool. But the founder needs it for the hinge log and had to be told where it is.
- **Card detail:** Shelf → tap a sticker → "Specimen" sheet with Share Clip, Share Still, Press Another, Delete.
- **Achievements:** no in-app list. They show only as one-off reveal toasts and in Game Center.

### 1.6 The outer display (phone closed)

| State | What the cover shows | Can do |
|---|---|---|
| Launched closed, first run | Graphite panel with screws and a hazard jaw. "Your pressed specimens land here." · ON THE ANVIL **Bubble Wrap** · 6 object chips · animated fold glyph "Open to press" · the safety line, if still due | Queue an object. **No Shelf, Settings, help or sound check** |
| Launched closed, with a collection | The 3 latest stickers instead of the empty line (`duo-cover-launch.png`, a seeded demo) | Same |
| Sealing (55–20°, before `closed`) | **Nothing new.** The spec'd "SEALING…" card with a live gauge (FOLD-PRESS §6.1) isn't built; the cover shows only once `closed` reads true | — |
| Sealed | PRESS SEALED · gauge · **the print itself** under "WHAT'S LEFT?" · nn TONS · OPEN TO SEE, and an amber seam glow | Nothing (the chips are hidden while a reveal is pending) |
| Reopening (0 → ~150°) | The spec'd "RELEASING" state (amber → green lamp, falling needle, release hiss) isn't built | — |

### 1.7 Tips: the complete list

| Tip | Text | When | Build |
|---|---|---|---|
| `safety` | ON-SCREEN ONLY · Never close your phone on real things. | Duo, first launch, until the first press starts (seen after 3 s up) | Release |
| `openUp` | OPEN IT UP · Open your iPhone flat to start a press. | Duo, idle below 130°, after 1 s, until opened | Release |
| `coach` | SLOW IS SMOOTH · Close it slowly… it's more satisfying. | After 2 slams in a row, ≤ 3 times ever, 2.5 s | Release |
| `sound` | SOUND ON? · Squish is half sound. Unmute for the full crunch. (or "Sound is off in Settings…") | Once ever, ~0.9 s after the **first collect**, 4 s | Release |
| `dragDown` | DRAG DOWN · Pull the press down. Slower is nicer. | Touch press, **never on a Duo** (`!hasHinge`), 20 s untouched | Release |
| Reveal toasts | PERFECT SQUISH / NEW OBJECT UNLOCKED / ACHIEVEMENT · … | At reveals that earn them | Release (`notoasts` hides them in DEBUG demo runs) |
| Cover safety line | Squish is on-screen only. Never close your phone on real things. | While the safety tip is current | Release |
| PinchHandle "DRAG DOWN TO PRESS" | On the P-48 crosshead, first 3 presses | Phones with aspect ≤ 0.58 only, never a Duo | Release |
| `PressHints` ghost arc + grip glows | — | **Never** (§2.1 #9) | Dead code |

DEBUG-only (`#if DEBUG`, absent from TestFlight Release): `DemoScenario` and every `-squishDemo` key, the `icon` overlay, `RevealToastDemo` (`notoasts`), `GameCenterRowDemo` (`gamecenter=hidden`), `DemoCapture`, and the `SQUISH-*` logs. **Nothing that teaches is DEBUG-only. There simply isn't any.**

---

## 2. The audit

### 2.1 Findings, ranked (P0 = the founder will hit it in the first minute)

| # | Sev | Finding | Where |
|---|---|---|---|
| 1 | P0 | **No onboarding.** A new Duo user gets one safety warning and an object. Nothing says "close the phone slowly to crush it", shows the pose, or explains the reopen. The wordless invitation only plays at ≥ 172°. The spec'd 8 s coach was never built. Bible §3.2 ("first run with zero text") was a hypothesis, and the device test falsified it | `RootView.hingeArrived`, `FoldPressController.sweep`, FOLD-PRESS §7.6 |
| 2 | P0 | **No menu.** The idle press room has exactly two controls: a name dropdown and a "Shelf" key. During a press, the reveal and the cover there are zero navigation controls. There's no home, pause, help, about or settings icon anywhere on the press screen (§2.3) | `IdleConsole`, `RootView.console` |
| 3 | P0 | **"No sound" is probably the silent switch.** The session is `.ambient`, which is muted by Silent mode. The app can't detect that and never says so. The only sound tip arrives **after** the first press, says "Unmute", and can't tell whether you're muted. Gain staging is quiet (beds ≈ −30 dBFS), there's no idle room tone, and on a Duo in tabletop the speaker may sit in the closing gap. The result is a first press in near or total silence. Haptics alone can't carry "satisfying" | `AudioController.start` (`.ambient`), `RootView.showPendingTips` |
| 4 | P0 | **The press feels flat** (detail in §3): the crush happens under an absent lid, the failure is a 34 ms flash and a 2D splat, the climax is in the dark, and the payoff is a text card on the cover | §3 |
| 5 | P0 | **Settings is hidden:** two taps deep behind a key named "Shelf", and unreachable from the press, the reveal or the cover. The Tuning Lab is a hidden 0.8 s long-press on "Version" | `ShelfView.header`, `SettingsView.versionRow` |
| 6 | P1 | **Silent fold-to-collect eats the reveal.** Settling from 170° into tabletop (≥ 20° drop) collects the specimen and loads the next object with no confirmation. The peak-end moment can last under a second, and the user doesn't know where it went | `RevealCollectGate.foldTravel = 20` |
| 7 | P1 | **Objects have no meaning before you press them.** The chip menu is names; the locked rows are rules ("squish 6 times"). There's no picture, no behaviour ("pops", "shatters", "won't squish"), no per-object secrets or goals, and no reason to pick the egg over the cake. The flavour lines exist (`ObjectKind.flavourLines`) but show only on cards after the press | `ObjectChipPicker`, `ObjectCatalog.flavourLines` |
| 8 | P1 | **The instruments speak engineering.** The crown nameplate shows the raw hinge angle ("147°") and then freezes the failure angle in red through the reveal, while the needle reads 0. The label says "AT 65°". The cover says "55 TONS", the inner reveal never does. Users don't care about degrees; they care about "how hard did I press it". Two numbers, two places | `FoldBezel`, `RevealCardView.foldLabelText`, `CoverView.SealedInset` |
| 9 | P1 | **`PressHints` (ghost arc, grip glows) is dead code.** It's mounted only when `!usesFoldPress` and visible only when `!usesTouchPress`. Those can't both hold (`usesFoldPress = hinge && !noFold`, `usesTouchPress = !hinge \|\| noFold`), so it never renders on any device | `RootView` l.59–61, `PressHints.visible` |
| 10 | P1 | **A Duo with "Press without folding" gets the P-48 with no affordance.** FOLD-PRESS §8.5 says a Duo in touch mode keeps the Fold layout. The code shows the P-48. The PinchHandle doesn't fit the Duo's aspect, and the DRAG DOWN tip is suppressed on any device that ever had a hinge. So the accessibility path is the least taught mode in the app | `PressDirector.usesFoldPress`, `PinchHandle.maxAspect`, `scheduleDragHint` |
| 11 | P1 | **The reveal has no entrance.** By design (N10) the diptych is fully drawn before the panel lights, so the key moment of the app *appears*, rather than *happening*. The bible's 2 s slow-mo replay was dropped (`PressScene.handle(.reveal)` comment). The PRESSED stamp, peel and glint are small and fast | `RootView.stageReveal`, `PressScene` l.297 |
| 12 | P1 | **The cover spoils the reveal.** The sealed card shows the platen print under "WHAT'S LEFT?", then says OPEN TO SEE. On opening, the user sees the same print plus the anvil | `CoverView.SealedInset.printTeaser` |
| 13 | P1 | **The chrome disappears mid-press and nothing replaces it.** The Shelf key vanishes and the chip dims to 40%. If the user wants to stop, restart or get help, the only move is to unfold. There's no pause, and no "ease off to cancel" teaching | `IdleConsole(chipOnly:)` |
| 14 | P1 | **No cover states for sealing or releasing.** The spec'd SEALING… (live gauge) and RELEASING cards are missing, so the cover is blank theatre until `closed`, and static on the way open | `CoverView.Content` has `.sealed` and `.idle` only |
| 15 | P1 | **The first-run order wastes the "oh!".** Bubble Wrap is a good first object, but the second press auto-advances to the Duck, which "survives" by design (no faces destroyed). It's the least satisfying failure in the set (`rubberDuck-tabletop-45/reveal`: a yellow pancake with both eyes intact, "1 SEAM POP"). The bible intended the contrast; in practice it reads as a dud | `PressDirector.next()`, catalogue order |
| 16 | P2 | **Progression is invisible on the press screen.** The Shelf key's count is hidden until the first card. Unlock rules surface only in the greyed menu rows and the Shelf wells ("SOME THINGS WON'T SQUISH…"). There's no "next unlock" anywhere you look while playing | `ShelfKey`, `AchievementInfo.menuHint` |
| 17 | P2 | **No in-app achievements view.** Ten achievements exist; you see each one once, as a 3 s toast | `UI/*` |
| 18 | P2 | **Captions are off by default.** The comic POP!/CRACK! layer would add visible punch to a press that mostly reads as 2D, and it's hidden in Settings | `AppSettings.showCaptions = false` |
| 19 | P2 | **Three different pickers in three visual languages:** a system pull-down (inner), a sticker grid (Shelf) and a chip grid (cover). Only the cover's is glanceable | §1.2 |
| 20 | P2 | **Settings is a generic iOS list on a foldable.** It's a full-height sheet over the crease. There's no sound test, no haptic test, no "replay intro", no "how to press", no "restore purchases" (none needed, but buyers look for it), no contact or support link. The `07-settings` store frame shows a non-default state | `SettingsView` |
| 21 | P2 | **The Shelf's on-anvil badge is a bare download glyph** (`arrow.down.to.line`) on the current object's sticker. It's unexplained | `ShelfView.ShelfSlot` |
| 22 | P2 | **Launch has no brand moment.** The bible's 0.0 s "hiss-clunk, steel plates fade in" isn't there. The app opens straight into a busy machine | bible §3.2 step 1 |

### 2.2 Duo Fold Press vs P-48: inconsistencies

| Aspect | Duo Fold Press | P-48 (other iPhones) | Problem |
|---|---|---|---|
| Teaching | Safety toast; sheen at ≥ 172° only; OPEN IT UP below 130° | A "DRAG DOWN TO PRESS" plate on the crosshead (first 3 presses) and a DRAG DOWN toast at 20 s | **The cheaper fallback is taught better than the hero** |
| Ghost arc / grip glows | Never (dead code) | Never | Spec'd for the Duo, built, unreachable |
| Reveal | Instant diptych, no entrance, a print label, toasts after the light | The card drops in with a spring; keycaps rise | The P-48 reveal has *more* ceremony |
| Card on reveal | Shown only during the collect flight | A full specimen card | Different mental model of "what I got" |
| Result number | "AT 65°" (hinge angle) | "AT 48 TONS" | Same product, different unit |
| Cover teaser | The actual print (a spoiler) | An object silhouette with "WHAT'S LEFT?" | Inconsistent, and the Duo one spoils |
| Console during the press | The chip dims to 40% and stays | Zero chrome | — |
| Shelf detent | `.large`, split at the crease | `.medium` | Fine, but the entry points are the same hidden key |
| Touch mode on a Duo | Falls back to the P-48 with no handle and no tip | n/a | Contradicts FOLD-PRESS §8.5 |
| Coach copy | "Close it slowly…" | "Slowly…" | Fine |
| Prints | Live platen print | Offscreen print for the card only; the spec'd platen "flash its print" tilt at the P-48 reveal (§8.2) isn't seen in frames | Unverified |

### 2.3 What "no menu" means concretely in this build

| Moment | Tappable controls on the inner display |
|---|---|
| Idle (open, nothing pressed) | `[object name ⌃⌄]` dropdown · `[Shelf]` key. **That's the whole app surface.** |
| Pressing (any angle below θ0) | **None** (the chip is inert at 40%) |
| Sealed / dark | None (display off) |
| Reveal | `Again` · `Share` (long-press for the still) · `Next` |
| Collect flight (0.4 s) | None |
| Cover, idle | Object chips |
| Cover, sealed | **None** |

To reach Settings you must:
1. know that "Shelf" also means "menu";
2. be idle, not mid-press and not on the reveal;
3. tap the key;
4. find a 44 pt gear on the top right of a sticker album.

Nothing on any screen is labelled Menu, Settings, Help, How to play, About, Pause or Home.

---

## 3. The press moment, as rendered on the Duo

**Why it feels flat, in one paragraph:**
- **The press is made of correct but quiet cues, spread over the wrong angles.** The object starts squashing at ~132° under a lid that is still ~50° away, so the user's hand and the object never feel connected.
- **Most of the drama is 2D, zero-depth paint on the lid:** shadow, print, splat. In tabletop the user sees the lid face-on but sees the 3D object at a grazing angle under it.
- **The failure, the one moment that should stop time, is a 34 ms half-screen flash** and a decal change. It lands at 96–64°, where the object is partly under the overhang.
- **The best part (the final crush and the ka-chunk) happens with the inner display off.** It's rewarded with a text card on the other screen.
- **If the phone is in Silent mode, all of it is silent.**

### 3.1 What deforms, and when (θ0 = 168)

| Object | Contact → failure (what changes on the anvil) | Failure | After the failure | Frame evidence |
|---|---|---|---|---|
| Rubber Duck | Uniform volume-preserving squash; the base spreads; a shadow puddle | "Seam pop": a small brown tab decal, a honk sound | A flat pancake **with both eyes and the beak intact** (content rule: faces survive) | `rubberDuck-tabletop-112` (nearly undeformed), `-75` (~50%), `-45` (flat), `-reveal` |
| Glass Bottle | Crack decals: **black hand-drawn asterisks painted on the glass**, plus a white crack web on the platen | Shatter into ~flat shards on the plate; the base disc remains as a translucent circle | Shards lie flat with no bounce or scatter; the platen shows a crack web | `glassBottle-tabletop-90`, `-62` |
| Soda Can | Barely buckled at 76°, a top-down green disc on the platen | Concertina + fizz (per the spec) | Green puddle, droplets | `sodaCan-tabletop-75` |
| Jelly | Wobble, spread; it fills the plate | A splat on the platen with droplets past the plate edge | A big pink dome | `jelly-tabletop-62` (the most satisfying frame in the set) |
| Cake, Egg, Crayon, Gummy, Bubble Wrap | Same pipeline; see the `cakeSlice-*` and `verify/egg-*` frames | | | |

### 3.2 Feedback at each beat (what exists in code)

| Beat | Visual | Sound | Haptic | Gap |
|---|---|---|---|---|
| Approach | Shadow on the platen; the angle readout counts | Hiss with speed, hum | none | The user's main cue is a **number in degrees** |
| Contact | The print "kiss"; needle +2 t; LOAD amber; 1-frame highlight; object hit-stop | Contact thud | Soft kiss transient | The lid is visibly nowhere near the object, so the "contact" is unexplained |
| Strain | Squash, crack decals, 0.3 mm jitter, quiver; the print grows; the needle climbs | Pentatonic gauge ticks every 5°, strain loop, creak | Strain bed ≤ 0.7, grains per degree | Good on paper. Deformation is small until ~90°, and the gauge is 56 pt in a corner |
| Tell | Needle tremor at 14 Hz | Micro-cracks accelerate | Tremor ±0.08 | Invisible at arm's length |
| Hush | — | −12 dB duck | Bed off | Fine |
| Failure | **Top-half white flash for 34 ms**, splat, droplets, the readout freezes red, debris at 0.3× for 250 ms | Layered failure event | 1.0 transient | No screen-spanning event on the anvil, no camera punch, no stop-time beat a human can perceive, no caption (off by default) |
| Crush | Spread meshes; the lid shade darkens the platen | Granular crunch ∝ speed | Debris grains | The phone is at 64–48°, overhang and dark window approaching |
| Seal | Display dark | Motor spin-down | Settling grains | **No visual.** The SEALING… cover card isn't built |
| Ka-chunk | Cover: PRESS SEALED card | Ka-chunk | 1.0 + rumble, 2 "ready" taps | The payoff is **text** |
| Reveal | Instant diptych, stamp, glint | Reveal sting | Material reveal | No entrance, no replay, and the angle number is red |

### 3.3 What's missing compared with a satisfying crush

Hydraulic-press videos, Smash Hit and ASMR crush clips all give you:
1. **The plate visibly arrives on the object.** Today contact is perceptual: nothing drawn crosses the air, by design, so the object squashes under empty space. On the Duo the honest equivalent is to make the *lid half itself* read as the descending plate, then delay the visible squash until the real lid is close (contact ~110–100°, failure ~80–65°). The other option is a stronger cue on the anvil that "the plate is touching now": a pressure ring, a plate-shaped shade that lands, hit-stop plus a crunch.
2. **Resistance you can see before the give.** Bulging out of the sides, creak and strain lines, the object fighting back. Our deformation is mostly a smooth uniform squash.
3. **A real stop-time failure.** 120–200 ms of hit-stop on the whole stage, a burst that leaves the plate's footprint (pieces flying *off* the anvil, onto the crease, out to the rails), a big sound, a 1.0 haptic. Then slow motion.
4. **Loud, close sound by default.** Most of the satisfaction is audio. Today it's muted by Silent mode with no warning.
5. **A visible payoff after the dark.** The ka-chunk deserves a moment on the screen you can see. The reveal should *happen* (lid lift, slow-mo replay of the failure, the stamp slam, numbers counting up), not just be there.
6. **A sense of force.** Tons on the dial, large and central, climbing with your hand. The hinge angle should be a secondary readout at most.
7. **Variety per press you can feel:** surprise cores, Golden. These exist (1/50 Golden, seeded surprises), but nothing on screen says "this one's special" until the card.

---

## 4. Proposed information architecture (first draft)

**Principles:**
1. **Obvious beats wordless.** One short line of copy per state is fine. Silence is not.
2. **The menu is always one tap away, except mid-stroke.** Mid-stroke, easing off is the pause.
3. **The fold is the primary verb; taps are secondary.** Every screen says which fold does what.
4. **Each pose has one job per half.**
   - **Tabletop:** the lid (upright) is for watching (instruments, captions, coaching); the base (flat) is for touching (controls, picker, keys).
   - **Book:** the leading page is for watching, the trailing page for touching.
5. **Premium means fewer, bigger, slower:** one hero element per state, generous type, real motion on the peak moments.

### 4.1 Map

```
                 ┌──────────────┐
  first launch → │ S1 Welcome & │──(practice press done)──┐
                 │ Fold Lesson  │                         │
                 └──────────────┘                         ▼
 ┌─────────────┐  open   ┌──────────────────────────────────────┐  ☰   ┌────────────┐
 │ C1 Cover    │ ──────► │ S2 PRESS ROOM (home)                  │ ───► │ S8 Menu    │
 │ home/queue  │ ◄────── │  idle ─ fold ─► S4 Pressing ─ close ─┐│      │ Resume     │
 └─────────────┘  close  │  ▲                                    ││      │ Objects→S3 │
 ┌─────────────┐         │  └──── S6 Collect ◄── S5 Reveal ◄─open┘│      │ Shelf →S7  │
 │ C2 Sealing/ │◄─close──│                                       │      │ How to →S10│
 │ Sealed/     │──open──►│  tray ▸ S3 Object Picker              │      │ Settings→S9│
 │ Releasing   │         └──────────────────────────────────────┘      │ About      │
 └─────────────┘                                                         └────────────┘
```

### 4.2 Screens

**S0 Launch (0–1.2 s, every cold launch)**
- **Purpose:** a brand beat, and time for the hinge to report.
- **Contents:** graphite. The plates slam together with a *hiss-clunk* and a 1.0 haptic, then part to reveal the press room. The Squish wordmark is on the lid. This plays even in Silent mode (haptic plus visual).
- **Entry:** cold launch.
- **Exit:** S1 on a first run, otherwise S2. On a Duo, wait for the first hinge context before choosing Fold or P-48, so the P-48 is never drawn on a Duo.

**S1 Welcome & Fold Lesson (first run only, < 10 s, replayable from S10)**
- **Purpose:** teach "close slowly → crush → open to see", by doing it once.
- **Contents, three beats, all live:**
  1. **Pose card (0–3 s).** One line on the lid: "Stand it up like a tiny laptop." A live side-view phone glyph mirrors the real hinge angle, with a target band at 90–120°.
     - **Book pose:** "Hold it like a book."
     - **Flat:** the lid sheen sweeps.
     - The glyph turns green when the pose is right.
  2. **Sound check (in parallel).** A soft synth plop plays.
     - Line: "Hear that? If not, flip Silent off. Squish is half sound." with a speaker icon.
     - Dismisses itself on the first press. Never blocks.
  3. **Practice press (Bubble Wrap).** One line: "Close it slowly." An arrow arcs along the lid edge toward the crease. Pops start early (~150°) so the "oh!" comes within a second of moving.
     - At failure: a caption (POP POP POP), even with captions off, first run only.
     - On the cover at seal: "Ka-chunk! Now open it."
     - On reopen, the reveal plays with its full entrance.
- **The safety line moves** to a footer on the pose card: "It's all on-screen. Never close your phone on real things." It's no longer the headline.
- **Entry:** first launch, or Menu → How to press → Replay intro.
- **Exit:** after the first reveal → S6 Collect → S2, with the tray pulsing once.
- **Duo pose:** tabletop and book as above. Closed at launch → C1 shows "Open me to start" and the fold glyph.
- **Touch (P-48 or Duo drag mode):** the same three beats with "Drag down slowly", and a grab plate drawn on the lid half (the Duo keeps the Fold layout).

**S2 Press Room (home)**
- **Purpose:** where 90% of the time is spent. Show what's on the anvil, why it's worth pressing, and where everything else is.
- **Contents, tabletop (Duo):**
  - **Lid (upright):**
    - crown with a **large tonnage gauge** (≥ 96 pt, centred) and READY/LOAD lamps; the hinge angle becomes a small engraved secondary readout, or is dropped;
    - **☰ Menu keycap** top-left of the crown, the only chrome on the lid at idle;
    - one coaching line slot under the plate: "Close slowly to press", fading after the first 3 presses.
  - **Base (flat):**
    - the anvil and the object;
    - the console: **Object tray** (the current object as a large chip with its picture, name and a one-line behaviour like "pops one by one"; tap opens S3);
    - **Shelf key** with a count (always shown, "0/10" included);
    - a "Next unlock" micro-line: "Soda Can unlocks after 3 different things · 1/3".
- **Book pose:** the leading page holds the crown, gauge, ☰ and the coach line; the trailing page holds the anvil and the console under the right thumb.
- **Flat 180°:** the lid sheen invitation plus the coach line.
- **Tent / face-down / < 130° at idle:** a "Lay it like a laptop to press" card on whichever half faces the user.
- **States:** idle → pressing (S4) → sealed (cover) → reveal (S5) → collect (S6) → idle.
- **Entry:** S0, S1, Menu → Resume, or the cover opening.
- **Exit:** fold → S4; tray → S3; ☰ → S8; Shelf → S7.

**S3 Object Picker ("The Tray")**
- **Purpose:** choosing is part of the fun. Give each object a promise and a reason.
- **Contents:**
  - **Tiles** (2×5, or a horizontal carousel on the base half). Each tile has:
    - a live or pre-rendered 3D thumbnail;
    - the name;
    - a **behaviour verb** (Pops · Squeaks · Wobbles · Snaps · Cracks · Oozes · Buckles · Splits · Shatters · ???);
    - a **stiffness pip bar** (the bible's stiffness order);
    - its personal goals as three small slots: **Perfect ◇ · Surprise ◇ · Golden ◇**, filled when found. That's the reason to press it again.
  - **Locked tiles:** an embossed silhouette with a progress line ("Squish 6 times · 4/6").
  - **The secret tile:** "Some things won't squish…"
  - One flavour line under the selected tile ("It wasn't your birthday anyway.").
- **Entry:** the S2 tray, the Shelf object page ("Press another"), or Menu → Objects.
- **Exit:** tap a tile → it drops onto the anvil with a plop, and the picker closes. Swipe down or fold to close.
- **Duo pose:**
  - **Tabletop:** the tray rises on the base half only; the lid shows the selected object large, with its verb and flavour line.
  - **Book:** the trailing page.
  - **Cover:** C1 is a compact version (see below).

**S4 Pressing (an S2 state)**
- **Purpose:** zero navigation, maximum feedback.
- **Contents:**
  - the large gauge;
  - a stage caption layer: POP!/CRACK! **on by default for the first 5 presses**, then follows the setting;
  - the "Keep going… slower is better" coach line during the first press only, driven by speed;
  - ☰ fades out.
  - **Pausing is easing off:** opening past θ0 again returns to idle, with the object keeping its damage. The first time it happens, the coach line says "Eased off. Close again to keep going."
- **Entry:** the first closing sample.
- **Exit:** close → cover C2; reopen fully → S2 idle with damage kept.
- **Duo pose:** coaching on the lid (tabletop) or the leading page (book). Nothing on the base.

**S5 Reveal**
- **Purpose:** the peak-end moment. It has to *happen*.
- **Contents, choreographed after the display lights:**
  1. the lid shade lifts off (300 ms);
  2. a **1.5–2 s slow-mo replay of the failure** on the anvil (the clip renderer already re-simulates from the trace; reuse it here);
  3. the PRESSED stamp slams with a haptic;
  4. stats count up on the lid: **TONS**, Perfect/Golden/Surprise badges, "№0012";
  5. an unlock ceremony if earned (the new tile flips in the tray);
  6. the keys: **Keep** (primary), **Again**, **Share**.
- **The cover's sealed card no longer shows the print.** It shows only the gauge and "What's left? Open to see."
- **Entry:** reopen after seal.
- **Exit:**
  - **Keep** → S6.
  - **Again** → S6, then the same object.
  - **Fold-to-keep** is allowed only after the stats have finished (~2.5 s), and shows the hint "Fold to keep" with a glyph. A deliberate 30° fold, or a close, counts.
- **Duo pose:** the diptych stays (print on the lid, specimen on the base), the stats on the lid, the keys on the base.

**S6 Collect → Next**
- **Purpose:** close the loop and point at the next reason to press.
- **Contents:**
  - the diptych folds into a card and flies into the Shelf key, with the chime;
  - then a 1 s "Up next" moment: the next object's tile slides in with its verb ("Up next: Egg · cracks").
  - If an unlock happened: "New: Soda Can · buckles", and it's put on the anvil.
- **Entry:** Keep, Again or fold-to-keep.
- **Exit:** S2 idle with the next object. No auto-advance to an object the user didn't see announced.

**S7 Collection (Shelf)**
- **Purpose:** the album, and the reason to come back.
- **Contents:**
  - tabs **Objects · Squished · Achievements** (new: the 10 achievements, earned and unearned, with hints);
  - the Objects tab opens **object pages**: best card, count, per-object goals (Perfect/Surprise/Golden), "Press another";
  - Card detail is as today.
  - **Remove the gear from here.** Settings lives in the Menu.
- **Entry:** the S2 Shelf key, or Menu → Shelf.
- **Exit:** close → S2, or "Press another" → S2 with that object.
- **Duo pose:** tabletop split as today (grid on the lid, recent on the base). Book: the grid on the leading page, the detail on the trailing page.

**S8 Menu (always reachable)**
- **Purpose:** the menu the founder looked for.
- **Contents:** a press-styled panel (graphite with yellow keycaps) holding:
  - **Resume**
  - **Objects** (S3)
  - **Shelf** (S7)
  - **How to press** (S10)
  - **Settings** (S9)
  - **About** (credits, Golden odds, privacy, support/contact, version; the Tuning Lab stays a long-press here)
- **Entry:**
  - ☰ on S2 (idle or reveal);
  - the cover's "More" chip (C1);
  - swiping down from the crown.
  - Not available mid-stroke; easing off brings ☰ back.
- **Exit:** Resume or a fold. Any fold closes the menu and returns to the press.
- **Duo pose:**
  - **Tabletop:** the panel drops down over the lid. The base keeps the object visible, so the menu feels like a lid-mounted control panel.
  - **Book:** the leading page.

**S9 Settings**
- **Purpose:** trustworthy and testable.
- **Contents:**
  - **Sound:**
    - On/Off;
    - Workshop/Soft;
    - **"Play test crunch"**;
    - a line that explains Silent mode;
    - optionally **"Play sound in Silent mode"**: switches the session to `.playback` + `.mixWithOthers`. This is the founder's call, since it changes the `.ambient` decision.
  - **Feel:**
    - Haptics Off/Soft/Full, with **"Test"**;
    - Captions;
    - Press mode **Fold / Drag** (Drag keeps the Fold layout on a Duo);
    - Reduce Motion (info).
  - **Help:** Replay intro, How to press.
  - **Game Center.**
  - **About.**
- **Entry:** Menu → Settings, C1 → More → Settings.
- **Exit:** close → back to where it was opened from.
- **Duo pose:** tabletop: section list on the lid, controls on the base. Never a sheet straddling the crease.

**S10 Pause & Help ("How to press")**
- **Purpose:** recover anyone who is lost, at any time.
- **Contents:** three looping illustrated cards:
  - tabletop ("Stand it up, push the top down slowly");
  - book ("Hold it like a book, close it slowly");
  - drag ("Or drag down on the lid").
- Plus "Open to see what's left", "Ease off any time", and "Replay intro".
- **Automatic pause:** when the app is backgrounded mid-press, or the phone sits half-closed with no motion for 20 s, the press freezes. On return, one line: "Paused. Close to keep going, or open to start over."
- **Entry:** Menu → How to press; automatic as above; a 15 s idle with no fold on the first 3 sessions (an inline nudge, not a modal).
- **Exit:** Got it → S2.

### 4.3 Outer display (cover) states

| ID | State | Contents | Actions |
|---|---|---|---|
| C1 | **Cover home** (launched or idling closed, no press pending) | Squish wordmark · ON THE ANVIL: picture + name + verb · a compact tray (6–10 tiles) · the latest 3 stickers · "Open to press" glyph · **More** (Shelf count, Settings, How to press) | Queue an object, open More |
| C1a | First run, closed | "Open me to start", the fold glyph, a sound-check line | — |
| C2a | **Sealing** (display handover → `closed`) | Machine outside: yellow field, live gauge climbing if samples arrive, amber LOAD | — |
| C2b | **Sealed** | KA-CHUNK! (animated) → PRESS SEALED · big TONS · "What's left? Open to see" (**no print**) · seam glow | — |
| C2c | **Releasing** (0 → ~150°) | Needle falls, lamp amber → green, release hiss | — |
| C3 | Closed mid-press without sealing (paused) | "Paused at 38 tons · open to keep going" | — |

### 4.4 Progression (minimal, ethical, visible)

- **Keep:** 6 open, 3 unlock through play, 1 secret, no currency, streaks or timers.
- **Add three visible per-object goals,** filled in the tray, on the object page and on the card: Perfect, Surprise found, Golden. That gives every object a reason to be pressed again without grind. The data already exists (`variant.surprise`, `isPerfect`, `isGolden`).
- **Surface "Next unlock"** on S2 and in S6.
- **Add an in-app Achievements tab** (S7).
- **Sequence the first session** for contrast: Bubble Wrap (pops) → Egg or Jelly (gooey payoff) → Crayon (snap). Not the Duck second.

---

## 5. Hand-off notes for the lead

- **Biggest levers:**
  1. **Feel and sound:** see §3.3. The contact timing, the failure stop-time and the sound in Silent mode need founder decisions.
  2. **S1 onboarding.**
  3. **The S2 ☰ menu + S8 + S9.**
  4. **The S5 reveal entrance.**

  The rest is polish.
- **Decisions needed:**
  - `.ambient` vs `.playback` (sound in Silent mode).
  - Whether to break the "zero text" pillar for 3–4 coaching lines.
  - Where contact and failure land.
  - Whether faces may deform further on the Duck (the content rule).
- **Verify on hardware first (Tuning Lab hinge log):**
  - whether `onHingeChange` delivers an initial context while the phone is still (§1.1, the P-48 flash);
  - the display-off angle;
  - speaker audibility in tabletop at 60–90°.
- **Remove or rewire:**
  - `PressHints` (dead);
  - the Duo touch-mode P-48 fallback;
  - the print teaser on the sealed cover;
  - the red frozen hinge angle on the reveal.
- **Re-shoot store frames** after the redesign. `07-settings` currently shows a non-default state, and no frame shows a menu, so the founder's complaint is invisible in the listing too.
