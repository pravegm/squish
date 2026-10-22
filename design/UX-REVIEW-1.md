# Squish: UX Review 1 (pre-launch teardown)

*Principal product design review, 22 Oct 2026. The app wasn't run. I reviewed it by reading every SwiftUI view in `UI/` and `Collection/`, plus `PressDirector`, `PressEngine`, `PressConfig`, `ObjectCatalog`, `Contracts`, `Captions` and the scene's teaching and reveal paths, and traced each state transition by hand. I checked the result against the bible (§3.1, §3.2, §5, §6), VISUAL-TARGET §6/§9 and research 04/05. All file:line references are relative to `Squish/`. Owners: **UI** (SwiftUI shell), **Scene** (RealityKit), **Feedback** (audio/haptics), **Director** (PressDirector + PressEngine + config).*

---

## Executive verdict

1. The craft is real. The keycaps, the stamp choreography, the paper card, the cover machine panel, the flavour copy and the ethical progression already feel premium. Few £2.99 toys get this far.
2. **The first 10 seconds can be dead.** The engine only arms on an input sample, so the Duo ghost arc and the regular-iPhone platen pulse (the *only* teaching) usually never show. On a regular iPhone, the drag has to start high up on the screen or the press can't finish.
3. **The loop between presses is button-gated and abrupt.** The hinge does nothing while the reveal card is up. The cover chips are dead during the reveal. Below 120° the reveal never fires, leaving a screen with nothing to tap. Then the crushed mess vanishes and the next object drops with no rest beat.
4. Accessibility is thoughtful (an adjustable press, a one-sentence card, Reduce Motion variants). It breaks at large Dynamic Type on the console and in toasts, and VoiceOver focus doesn't follow the reveal.
5. **Score: 6.0 / 10 today.** The 5 P0s are about 2–3 engineer-days. With them fixed and the top P1s done, it's **8 / 10**, which is launchable and worth £2.99. Polish to 9 lives in the reveal → collect → rest beat (P2 delight).

---

## 1. Walkthroughs

### 1a. First-time iPhone Duo owner (tabletop, phone lying open and still)

| t | What happens (code) | Verdict |
|---|---|---|
| 0.0 s | `RootView.onAppear` → `director.start()` (`PressDirector.swift:76`). Audio and haptics start. **`GameCenter.authenticate()` (`:81`)** can drop the system "Welcome back" banner over the top of the screen in the first second. `engine.activate(now)` then `load(.bubbleWrap)`. | Game Center banner tramples the zero-text first run (P1-7) |
| 0.0 s | `load` → `engine.load` → `tryArm` fails, because it runs <1.5 s after activation (`PressEngine.swift:290-291`). Phase stays **`.idle`**. `scene.setObject` starts the drop immediately and `audio.place`/`haptics.place` fire, possibly before the ARView has rendered a frame (`PressDirector.swift:83, 219-223`). | The landing and plop may be missed (P1-9) |
| 0.0 s | Console visible at once (`canChooseObject` is true in `.idle`): `● BUBBLE WRAP ⌃⌄` and `▦ Shelf 0/10`. | "0/10" reads as a score on second one (P2) |
| 0.6 s | Safety toast slides into the 80–86% band: "ON-SCREEN ONLY / Never close your phone on real things." It auto-hides after 6 s and isn't announced to VoiceOver (`RootView.swift:304-311`). | Good copy; delivery gaps (P1-5) |
| 1.5 s+ | **Bible: ghost arc pulses.** Code: `PressHints.visible` needs `phase == .armed` (`PressOverlays.swift:22`). The phone is still, so no hinge samples arrive, nothing arms, and **no arc shows**. The user sees a static press with two keycaps. | **P0-1** |
| user lifts top half | Samples arrive → `.idle` → `tryArm` → `.armed` → the arc appears, then vanishes on the next sample once Pressing starts. Bubbles pop from contact (t 0.20 ≈ 144°), not ~160° as in §3.2. | Fine; the "oh!" lands about 15° later than scripted |
| closes | Strain, failure, "POP!" caption (if Captions are on), flash. At `.closed`: `handleClose` → fast-forward → `seal(blind:)` → `.kaChunk`. The cover shows the sealed inset: PRESS SEALED, mini gauge, "48 TONS", OPEN TO SEE. | Strong. Missing the teaser silhouette (P2) |
| reopens to ~110° (natural viewing angle) | Sealed waits for **filtered angle ≥ 120°** (`PressEngine.swift:205-207`, `PressConfig.swift:17`). If folding cycles `scenePhase`, `sceneBecameActive` also re-arms the 1.5 s input-ignore window (`RootView.swift:109-111`). Result: a crushed object, ram down, **no console, nothing to tap**, until the user happens to open past 120°. | **P0-3** |
| reveal | Ram lifts (spring ω 22). 800 ms later the card drops (`RootView.swift:232`). Stamp at +350 ms, actions at +500 ms, first toast at +800 ms ("ACHIEVEMENT · FIRST SQUISH"). The thumbnail is captured at +900 ms (`PressDirector.swift:277`), so the card lands showing the **generic silhouette tile and swaps to the real photo** about 0.1–0.4 s later. | Placeholder swap on the peak moment (P1-1) |
| user starts folding again | Phase `.revealing` ignores the hinge (`PressEngine.swift:209-210`). Nothing happens. If they close fully, the cover shows the **idle** trophy shelf with chips that do nothing (`queue` guards `revealed == nil`, `PressDirector.swift:118`) but still tick. | **P0-4** |
| taps Next | The card shrinks toward an anchor *where the Shelf key would be*, but the Shelf key **isn't on screen** during the reveal (the console is hidden). It shrinks and fades into nothing (`RevealCardView.swift:75, 116-119`). 450 ms later `fx.clear()` deletes the mess in one frame and the duck drops (`PressScene.swift:92-94`). | Collect metaphor lost; no rest beat (P1-2, P1-3) |
| after 2nd press | Shelf key hops once (`RootView.swift:258-262`). Under Reduce Motion: nothing. | P2 |

### 1b. First-time regular-iPhone user ("drag to press")

| t | What happens | Verdict |
|---|---|---|
| 0.0 s | Same launch. `onHingeChange` may never fire on a hingeless phone, so `hingeUnavailable()` is never called and **`engine.usesVirtualHinge` stays false** (`PressDirector.swift:154-158`, `HingeReader.swift:11-17`). | — |
| 0.6 s | Toast: "Never close your phone on real things." **This phone doesn't close**, so the line is nonsense here. | P1-5 |
| 1.5 s+ | **Bible / VISUAL-TARGET §6.1: the platen pulses (1.5% breathing plus a glow).** Code: `PressScene.swift:359` needs `phase == .armed && engine.usesVirtualHinge`. Both are false until the first touch, so **there's no teaching at all**. The "Drag down to press" text was (rightly) removed, so nothing replaced it. | **P0-1** |
| first touch < 1.5 s | Dropped by the activation guard (`PressEngine.swift:179`). That guard exists for stale *hinge* events, but it also eats touch input. | P1-8 |
| drags | `fraction = translation.height / (0.5 × fullHeight)` (`RootView.swift:159`). Seal needs depth ≥ 0.98, i.e. virtual angle ≤ ~61°, i.e. **a drag of 33% of the screen height**. A finger that starts **on the object** (the instinctive target, ~62–70% height) runs out of screen at 95–103%. The ram creeps down, the finger hits the bottom edge, the press springs back on release, and nothing seals. The user concludes it's broken. | **P0-2** |
| releases mid-way | The ram springs open at 300°/s. Damage persists, which is correct. With no affordance, users don't know they need to "go all the way". | P1 (covered by the P0-2 fix plus the teaching fix) |
| seals | `.kaChunk` plays at once (virtual), and the reveal comes 0.7 s later. **There's no cover beat at all:** the "PRESS SEALED · 48 TONS" moment, the bible's beat 10, is skipped on 100% of non-Duo phones. | P2-4 |

### 1c. VoiceOver user

- **Launch.** The placement announcement is good ("Bubble wrap. Twenty-four bubbles, each waiting to pop."). The safety hint isn't announced and disappears after 6 s (P1-5).
- **Stage.** It's one adjustable element. The label "Press. Bubble Wrap on the anvil." is good. On non-Duo the hint is "Swipe up to press down, swipe down to ease off." The value reads `accessiblePress` (10% steps), **not the real depth** (`RootView.swift:141`). The dead zone and ease mean swipes 1–2 do nothing audible, and swipe 7 ("70 percent pressed") actually seals. Users hear "70 percent" and then a ka-chunk (P1-11).
- **Press.** Failure, KA-CHUNK and reveal words are announced (`PressDirector.swift:245-247`). Rapid announcements interrupt each other: the failure is followed ~0.3 s later by the value change. Minor.
- **Reveal.** The full card sentence and toasts are announced at +700 ms. That's good, but **focus is not moved** to the card or Next (`RevealCardView.swift:213-220`). VoiceOver focus stays on the stage, whose adjustable action is now inert (`RootView.swift:146`). The user must hunt for Next (P1-10).
- **Shelf.** Strong. Slot sentences, "locked" with hint, a "View best card" action, `isSelected` on tabs.
- **Duo + VoiceOver.** The hint is "Fold your iPhone slowly to press." There's no spoken cue that the result needs reopening (P2 copy).

### 1d. Returning user, day 3

- **Always starts on Bubble Wrap** (`PressDirector.swift:194-196`). It's the least interesting object by day 3. It should start on the last object used, or better, the next *unpressed* unlocked object (P1-12).
- Nothing tells them anything changed. That's fine for v1, but the bible's "What's new shelf glow" for drops has no hook (P2).
- Shelf: locked hints don't show progress ("Squish 3 different things", but how many so far?). "Earn a Perfect Squish" is **never explained anywhere**. Glass Bottle and therefore The Unsquishable can be blocked indefinitely for someone who never stumbles into a Perfect (P1-13).
- Settings opens *by replacing* the Shelf sheet (`RootView.swift:206`). Closing Settings returns to the press, not the Shelf (P2).

### 1e. Edge cases

| Case | What the code does | Verdict |
|---|---|---|
| **Shuts the phone mid-press** | `handleClose` fast-forwards and seals blind with a ka-chunk at the clap; the cover shows the sealed card. The bible's "<0.6 depth → *Press interrupted at 40%*" card isn't implemented. Every close from Armed/Pressing completes the press. | **Keep the deviation** (a press should always finish; research 04 §1.1 "just right"). Document it in the bible. Closing the app to put the phone away will press the object; that's a charming side effect, not a bug |
| **Opens the app closed** | Cover idle: 3 dashed empty slots, "ON THE ANVIL / Bubble Wrap", chips, "Open to press". The safety line shows for 6.6 s. Chips queue objects with a plop you *hear inside the closed phone* (lovely). No looping fold glyph (bible §5) | P2-6 |
| **Rotates to book pose** | Scene rolls the camera between presses (good). UI goes landscape: console in the right 22% column, reveal card on the left. The first-run **ghost arc is hidden in landscape and the edge glows stay on the left/right edges of the top 44%**, which is meaningless when the moving half is the left or right half (`PressOverlays.swift:31-40, 72-96`). The failure flash still lights the *top* half (`PressOverlays.swift:214`) | P1-14 |
| **Rotation mid-press** | Pose locked, relayout only | ✓ |
| **Phone call mid-press** | No pause on `.inactive`. On return, `sceneBecameActive` → 1.5 s ignore. If they come back with the phone **closed**, the first sample after the window sees `closed && !wasClosed` → completes the press with a **surprise ka-chunk on return** (`PressEngine.swift:181-183`). If they come back open, the press resumes with its damage kept | P2-9: suppress the ka-chunk when the close happened while backgrounded; seal silently and show the sealed cover |
| **Half-folded launch (<100°)** | `tryArm` needs ≥100° (`PressConfig.swift:8`). The press never arms and there's no hint ("Open a bit more", research 05 §4) | P1-15 |
| **Tent pose / Split View** | No Paused state exists | P2 (v1.0 scope in bible §6.4; ship at least the tent copy) |
| **Sheet open during press** | Any 4° wobble starts Pressing and **slams the Shelf/Settings/Card sheet shut** (`RootView.swift:114-117`), even mid clip export | P2-10 |
| **Share sheet open, phone closed** | `onChange(isShowingCover)` only clears the root sheet. The Reveal's share sheet and confirmation dialog stay up over the cover | P2 |
| **Duo before its first hinge sample** | `hingeAvailable == false` → Settings says "This iPhone has no hinge" **on a Duo**, and the toggle is disabled (`SettingsView.swift:82-86`, `PressDirector.swift:142-144`) | P1-16 |

---

## 2. Deviations from bible §3.1 (beats) and §3.2 (first-run script)

| Bible | Spec | Implementation | Owner | Severity |
|---|---|---|---|---|
| §3.2.1 | 0.0 s black, *hiss-clunk*, plates fade in | No intro beat. Scene and console are visible at t=0 | Feedback + Scene | P2-1 |
| §3.2.2 / beat 0 | Bubble Wrap drops at 0.8 s | Drops at t≈0, possibly before the first rendered frame | Director | P1-9 |
| §3.2.3 / beat 1 | Ghost arc at 1.5 s plus two-hand edge glows | Only after a hinge sample (often never); missing in landscape | Director, UI | **P0-1**, P1-14 |
| §3.2.3 (VT §6.1) | Gauge needle twitch as teaching | Not found in the teaching path | Scene | P2 |
| §3.2.4 | Arc "fades for good" at the first pop | Reappears whenever the user returns to Armed before finishing press 1 | UI | P2 |
| §2 slams | "One gentle hint ('slowly…') on repeated slams" | **Not implemented** | UI + Director | **P0-5** |
| §6.4 | "Open a bit more" / "Lay it flat to press" | Not implemented | Director + UI | P1-15 |
| beat 10 | Cover: sealed card plus teaser silhouette | No silhouette; non-Duo has no sealed beat | UI | P2-4 |
| beat 11 | "first inner-display layout after seal (event, not angle)" | Angle-gated (≥120° filtered) plus a possible 1.5 s ignore | Director | **P0-3** |
| beat 11 | 100 ms hold, **2 s slow-mo replay of the failure** | Not implemented. The card drops 0.8 s after the ram lifts | Scene | P1-4 |
| beat 11 | Red PRESSED stamp thunks | ✓ (stamp spring + `UIFeel.press`) | — | — |
| beat 12 | "Card shrinks into its **shelf slot**" | Shrinks toward an off-screen anchor; the Shelf key is hidden | UI | P1-2 |
| beat 12 | "1.5 s quiet; the next object slides on" | 0.45 s, then the mess is deleted in one frame and the object drops | Scene + Director | P1-3 |
| §6.3 | "Revealing → Idle after the animation **or a tap**" | Only the Next/Again keycaps; the hinge is ignored | Director + UI | **P0-4** |
| §6.3 | depth < 0.6 at close → "Press interrupted" card | Auto-completes | — | Keep; update the bible |
| §5 | Shelf handle is a *pull-up handle* | A Shelf keycap that also accepts a swipe up (fine) | — | — |
| §5 cover | Launched closed: looping "open to press" glyph | Static text | UI | P2-6 |
| §8 | One-time "Squish sounds best with sound on 🔊" tip | Not implemented (`.ambient` honours the mute switch) | UI + Feedback | P1-6 |
| §10 | "**One-tap** share clip" | Share → a confirmation dialog → Share Clip (2 taps) | UI | P1-17 |
| §5 card detail | Actions: Replay, Share clip, Share image, Delete | No Replay | UI | P2 |
| §3.2 "only first-run text" | Just the safety hint | Plus the console labels, achievement toast and ribbon. Acceptable: they're post-press or chrome | — | — |

---

## 3. P0: must fix before launch

### P0-1. The engine never arms without an input sample, so first-run teaching never shows
- **Where:** `Core/PressEngine.swift:154` (load → `tryArm`), `:289-295` (`tryArm` needs ≥1.5 s since `activate`), `:228` (`step` never retries). `App/PressDirector.swift:76-87` (`start` loads immediately after `activate`). `UI/PressOverlays.swift:22` (arc needs `.armed`). `Scene/PressScene.swift:359` (pulse needs `.armed && usesVirtualHinge`). `App/HingeReader.swift:11-17` (a hingeless device may never call `onUnavailable`).
- **What's wrong:** On a still Duo there's no hinge sample, so no arming and no ghost arc. On every non-Duo iPhone there's no touch before the first press, so no arming, and `usesVirtualHinge` is still false, so no platen pulse. The app's only teaching device is dark exactly when it's needed. The same issue applies to any `load` within 1.5 s of `sceneBecameActive`.
- **Fix:**
  1. In `PressEngine.step(now:dt:)`, at the top, add `if phase == .idle && material != nil && now - activationTime >= config.ignoreInputAfterActivation { tryArm(at: now) }`. `tryArm` already checks `!isClosed` and `angle ≥ armAngleMin`.
  2. In `PressDirector.start()`, set `engine.usesVirtualHinge = !hingeAvailable` before `load`. In `HingeReader`, call `onUnavailable()` in `.onAppear` unless the first hinge context arrives within ~0.3 s. If `onHingeChange` has an `initial: true` form, use it.
  3. Add a unit test: load → step at +1.6 s with no ingest → `phase == .armed`.
- **Owner:** Director (engine + director), UI (HingeReader).

### P0-2. The touch press only completes if the drag starts high on the screen
- **Where:** `UI/RootView.swift:156-164`.
- **What's wrong:** `fraction = translation / (0.5 × screenHeight)` and the seal needs fraction ≈ 0.66, i.e. a 33%-of-height drag. Starting on the object (~62–70%), the natural target, can't reach it before the bottom edge. The press bounces back on release and reads as broken. This is the core mechanic for most of the paying audience.
- **Fix:** Normalise to the room available below the start point. In `onChanged`, capture `startY = value.startLocation.y` and use `let room = max(min(height * 0.5, height * 0.93 - startY), 140)` and `fraction = translation / room`. Better still, map through the ram so the ram face follows the finger 1:1: `fraction = clamp((value.location.y - ramHomeY) / (anvilY - ramHomeY))` when the drag starts above the anvil, and use the relative form otherwise. Also drop the 1.5 s activation guard for virtual input (P1-8).
- **Owner:** UI.

### P0-3. The reveal can fail to fire after reopening, leaving a screen with nothing to tap
- **Where:** `Core/PressEngine.swift:205-208` (Sealed → Revealing needs a *filtered* angle ≥ `revealAngle` 120°, `Core/PressConfig.swift:17`). `UI/RootView.swift:109-111` (`sceneBecameActive` re-opens the 1.5 s ignore window on any `.active` transition, possibly every fold).
- **What's wrong:** Reopening to a comfortable 90–119° shows the crushed object, ram down, no console, no Shelf and no hint. That's a stuck state on the hero device. The bible says the reveal is event-gated ("first inner-display layout after seal").
- **Fix:**
  1. Add `PressEngine.innerDisplayShown(at:)` and have the director call it from `RootView.onChange(of: director.isShowingCover)` when it becomes false while `phase == .sealed`. It calls `beginReveal()` immediately (or after ≤150 ms), regardless of angle. Keep the angle path as a fallback, lowered to `revealAngle = 90`.
  2. Apply `activate()` only on a true return from background (track `.background` → `.active`), not `.inactive` → `.active` from folding.
  3. Safety net: if `phase == .sealed && !isClosed` for > 1.2 s, auto-reveal.
- **Owner:** Director.

### P0-4. The reveal is a modal the hinge can't dismiss, and the cover shows dead chips
- **Where:** `Core/PressEngine.swift:209-210` (`.revealing: break`), `:398-399` (close ignored). `App/PressDirector.swift:116-121` (`queue` guard `revealed == nil`). `UI/RootView.swift:83-97` (cover shows `.idle` content with live-looking chips during the reveal). `UI/CoverView.swift:252-269`.
- **What's wrong:** In tabletop pose a Duo owner's hands are on the hinge. Folding again does nothing until they tap Next. Closing the phone during the reveal shows the trophy cover with object chips that tick but don't work. A dead end on the core loop.
- **Fix:**
  1. **Fold-to-continue:** while `.revealing`, if the filtered angle drops ≥ 10° below the angle at reveal (or below 150°), call `director.next()` through the same `collect` animation (expose `RootView.collect` as a director intent `requestCollect(.next)`, or move the 450 ms choreography into the director). The next object arms with θ0 = the current angle.
  2. **Close during reveal:** `handleClose` in `.revealing` → auto-collect (`next()` with a silent chime, or a soft chime if not muted), so the cover shows the idle shelf with the new sticker first and working chips.
  3. Make `queue` work in that state (it will, once collected).
- **Owner:** Director + UI.

### P0-5. No "slowly…" coaching on repeated slams (App Review 2.4.2 mitigation is missing)
- **Where:** Nothing implements it. `PressResult.wasSlammed` exists (`PressEngine.swift:429`) and shows only as a neutral SLAM chip.
- **What's wrong:** The bible §2 and Top risk #5 rely on gentle "slowly" coaching for 2.4.2 (device damage). With nothing reaching the user, reviewers will see a toy that rewards slamming a £2,000 hinge with full-intensity bursts.
- **Fix:**
  1. In `CollectionStore` (or the director), count consecutive `wasSlammed` presses.
  2. On the 2nd consecutive slam, after the reveal is collected and the next object lands, show one toast in the 80–86% band for 3.5 s (copy deck §6.3), hidden while Pressing.
  3. Cap it at 3 lifetime showings.
  4. In-scene, while `closingSpeed > slamSpeed` and loaded, the gauge needle should "panic" (Scene) as a non-text cue.
  5. Mention it in `docs/appstore/review-notes.md`.
- **Owner:** UI (toast) + Director (counter) + Scene (needle).

---

## 4. P1: should fix

| # | Where | What's wrong | Fix | Owner |
|---|---|---|---|---|
| P1-1 | `PressDirector.swift:274-280`, `RootView.swift:226-237`, `SpecimenCardView.swift:80` | The card lands showing the generic silhouette tile, then cross-fades to the real thumbnail about 100–400 ms later, at the peak moment. Reads as loading | Take the snapshot at reveal +500 ms (when the ram is ≥90% home) and **await it** in `stageReveal`: `revealVisible = true` when the thumbnail is attached or after 1,100 ms, whichever comes first. Drop the 0.5 s crossfade on first appearance | Director + UI |
| P1-2 | `RevealCardView.swift:75, 116-119`, `RootView.swift:55, 249-264` | "Collect into the Shelf" flies at an empty point. The Shelf key isn't rendered during the reveal | On collect: fade the reveal actions out (0.15 s), mount the Shelf key in the console (`IdleConsole` with `forceVisible`), then fly the card: `scaleEffect(0.16)` plus an offset to the key's centre via a shared `anchorPreference`, spring(0.38, 0.72), rotate to the sticker's seeded tilt. On arrival: the key does a keyDown/keyUp, its count rolls with `.contentTransition(.numericText())` on a `pressedCount` change, collection chime, `UIFeel.success()`. Total ≤ 0.6 s | UI |
| P1-3 | `PressDirector.swift:103-114`, `PressScene.swift:89-94` | No rest beat: the mess disappears in one frame (`fx.clear()`) and the next object drops 0.45 s after tapping. Bible: 1.5 s quiet; VT: debris slides off over 0.35 s | Add `scene.clearAnvil(duration:)`: the platen does a final "wipe" (ram rises with a hiss), debris and spread meshes slide off the anvil's front edge with ease-in over 0.35 s, lamps go amber → green, 0.6 s of room tone, then `setObject` drops. Director: `next()` awaits `clearAnvil` (≈1.1 s total; 0.3 s fade under Reduce Motion). Users can skip it by starting to press (input buffers the arm) | Scene + Director |
| P1-4 | bible beat 11 | No 2 s slow-mo replay of the failure, the peak-end moment | v1: replay only the *failure window* from the stored trace (`traceSamples`), from 0.4 s before the failure to 0.8 s after, at 0.4× in the live scene before the card drops. The machinery exists for the clip. If it's too costly, cut it and add a 0.25 s "debris re-settle" plus a camera micro-push instead (none under Reduce Motion) | Scene + Director |
| P1-5 | `RootView.swift:297-311`, `PressOverlays.swift:244-253`, `CoverView.swift:39-46` | Safety toast: (a) shown on non-Duo phones, where "close your phone" means nothing; (b) not announced to VoiceOver and gone after 6 s; (c) `hasSeenSafetyHint` is set before it was seen, so a launch straight onto the cover has it for only 6.6 s | Show it only when a hinge exists. Post `UIAccessibility.post(.announcement, …)` on show. Keep it up until the first contact event (not 6 s). Mark it seen only after it was on screen ≥ 3 s or the first press started. On the cover, keep the line until the phone is opened | UI |
| P1-6 | bible §8 | No sound tip. `.ambient` plus the mute switch means many first presses are silent, and half the product is missing | After the **first reveal**, if `AVAudioSession.outputVolume < 0.1` (or always, once), show a toast at +2.5 s (copy deck). Never mid-press; once only (`AppSettings.hasSeenSoundTip`) | UI + Feedback |
| P1-7 | `GameCenter.swift:88`, `PressDirector.swift:81` | System completion banners slide over the reveal card (6–44% band) on top of our own achievement toasts. The "Welcome back" banner can land in the first second of the zero-text first run | `gk.showsCompletionBanner = false`. Defer `authenticate()` until the first reveal has been collected (first run) or 3 s after launch (later runs), and set `GKAccessPoint.shared.isActive = false` | Director |
| P1-8 | `PressEngine.swift:179` | The 1.5 s input-ignore window (meant for stale hinge events) also eats touch input at launch and after every return to the app | Apply the guard only in `ingest` calls from the hinge: add a parameter `isVirtual` and skip the guard for `setVirtualAngle` | Director |
| P1-9 | `PressDirector.swift:83` | The first object loads and plays its plop before the scene renders, so the landing may be invisible | Defer the first `load` until `renderedFrames ≥ 10` plus 0.8 s (the bible §3.2 timing). Reuse the demo wait loop | Director |
| P1-10 | `RevealCardView.swift:213-220`, `RootView.swift:60-71` | VoiceOver focus doesn't move to the reveal | `@AccessibilityFocusState var focusNext` on the Next keycap. Set it to true 100 ms after the announcement, or post `.screenChanged` with the card as argument. On collect, post `.screenChanged` with the stage | UI |
| P1-11 | `RootView.swift:141, 166-179` | The VoiceOver value reports swipe count, not depth. Swipes 1–2 are dead, and "70 percent" seals | Value from `engine.measuredDepth`: "Approaching", "Touching", "N percent squished", "Sealed". Make the steps non-linear so each swipe is ~12% of *compression* after contact (precompute angles via `PressMapping.angle(forDepth:)`) | UI |
| P1-12 | `PressDirector.swift:194-196` | Every launch starts on Bubble Wrap | `firstObject()`: if `totalPresses == 0`, Bubble Wrap; otherwise the first unlocked object never pressed, else the last kind used (persist it in `AppSettings`) | Director |
| P1-13 | `ObjectCatalog.swift:109-118`, `ShelfView.swift:347-361` | Unlock hints have no progress, and "Earn a Perfect Squish" is never defined. That can block Glass Bottle and the secret | Show progress: `SQUISH 3 DIFFERENT THINGS · 1/3`, `SQUISH 6 TIMES · 4/6`. Rewrite the Perfect hint (copy deck). The first time any card is Perfect, add a toast "PERFECT SQUISH". Tapping a locked slot: a 2-cycle ±3° wiggle, a soft locked clunk, the hint text flashes `ink` for 0.6 s | UI + Collection |
| P1-14 | `PressOverlays.swift:31-40, 72-96, 204-218` | Book pose: the ghost arc is hidden and the edge glows sit on the wrong edges; the failure flash lights the wrong half | Make `PressHints` and `FailureFlash` pose-aware: in landscape, draw the arc as a vertical dotted curve beside the crease on the moving half (pointing toward the crease), glow the top and bottom edges of that half, and flash that half | UI |
| P1-15 | `PressConfig.swift:8`, `PressEngine.swift:290` | Below 100° nothing arms and nothing explains it. Tent pose has no pause | When the hinge is available and the phase is `.idle` for > 1 s because `angle < armAngleMin`, show a toast (copy deck "OPEN IT UP") until armed. Tent heuristic (research 05 §4): pause with "LAY IT FLAT" | Director + UI |
| P1-16 | `PressDirector.swift:142-144`, `SettingsView.swift:82-86` | On a Duo before the first hinge sample, Settings says "This iPhone has no hinge" and disables the toggle | Persist `hasHinge` once true (`AppSettings`), and use `UIDevice`/division-region detection at launch. Never show the non-Duo copy if a hinge has ever reported | Director + UI |
| P1-17 | `RevealCardView.swift:58-64, 170-176` | Share needs 2 taps plus a dialog (bible: one-tap clip) | Share = clip directly when a trace exists. Long-press / `contextMenu` on Share offers "Share Image". With no trace, share the image directly | UI |
| P1-18 | `RevealCardView.swift:144-156`, `Theme.swift:610-651`, `Theme.swift:358-362` (keycaps), `RootView.swift` (no root cap) | Dynamic Type: toasts are `lineLimit(1)` in a fixed 52 pt slot, and the console/reveal keycaps are uncapped. At AX sizes, labels truncate to "A…" and the console grows past the home indicator. "Pumped the press: opened and pushed again mid-press." truncates even at the default size | Cap the console, reveal actions and toast band with `.dynamicTypeSize(...DynamicTypeSize.xxxLarge)`. Toast: `lineLimit(2)`, `frame(minHeight: 52)`, no fixed height. At `dynamicTypeSize.isAccessibilitySize`, render reveal actions as a vertical stack in the 80–95% band, or as icon keycaps with labels exposed to VoiceOver. Shorten the achievement details (copy deck) | UI |
| P1-19 | `RootView.swift:207` (Shelf `.medium` detent) | On a Duo in tabletop pose the medium detent's top edge (grabber, Settings, Close keys) sits in the 40 pt crease, which the HIG forbids for interactive controls | Use the custom detent `.fraction(0.45)` on hinge devices (top edge clear of the crease) plus `.large`. Read the crease from `reservedRegions(kind: .division)` | UI |
| P1-20 | `PressDirector.swift:242-255`, `RootView.swift:51` | The "TA-DA!" / "GOLDEN!" / surprise reveal caption is set and then immediately unmounted (`revealed != nil`), so it's never seen | Either drop the reveal caption (VoiceOver only) or render it on the card as the ribbon text for Golden/surprise ("GOLDEN!" replaces "NEW BEST") | UI |

---

## 5. P2: polish and delight

### 5.1 Fixes

| # | Where | Fix | Owner |
|---|---|---|---|
| P2-1 | launch | Power-on beat: 0.0–0.6 s, the press lamps flick on one by one (tick, tick), the gauge needle sweeps 0 → 60 → 0 (spring 0.6/0.55), a *hiss-clunk*, then the object drops at 0.8 s. Under Reduce Motion: lamps fade on | Scene + Feedback |
| P2-2 | `PressOverlays.swift:56-69` | The ghost arc is a left→right rainbow with a rightward arrowhead, which reads "swipe right". Redo it as a *side-view hinge*: a dotted quarter-arc from the top edge curving down toward the crease, with the arrowhead pointing down at the crease. Animate a 0.6 s dash-phase march down the arc | UI |
| P2-3 | `PressOverlays.swift:325`, `ShelfView.swift:88` | Hide "0/10" until the first card ("Shelf" only). Endowed progress: count up the moment the first card lands | UI |
| P2-4 | non-Duo seal | Give touch users a sealed beat: on `.sealed` with no cover, hold 0.5 s with the gauge needle pinned, lamps red → amber, and a small paper tag "SEALED · 48 T" swinging from the crown (Scene decal, not SwiftUI, so the stage rule holds) | Scene |
| P2-5 | `CoverView.swift:89-131` | Sealed cover teaser: the object's `ObjectSilhouette` flattened (`scaleEffect(x: 1.3, y: 0.35)`) in `paperShade` with a "?" micro stamp. The needle twitches ±1 t every 3 s (static under Reduce Motion) | UI |
| P2-6 | `CoverView.swift:276-279` | Idle cover: a looping fold glyph next to "Open to press": two rounded rects hinged, the top one opening 0 → 160° over 1.4 s, ease-in-out, a 0.6 s pause (crossfade under Reduce Motion) | UI |
| P2-7 | `PressOverlays.swift:283` | The object chip menu lists only unlocked objects. Add a "Locked" section with disabled rows "Soda Can · squish 3 different things" (teaser) | UI |
| P2-8 | `PressOverlays.swift:337-338` | The Shelf hop has no Reduce Motion alternative. Use a 2-cycle yellow outline glow (opacity 0 → 0.8 → 0, 0.5 s each). Also set `shelfDiscovered = true` when the Shelf is opened by hand (`RootView.swift:186`) | UI |
| P2-9 | `PressEngine.swift:181-183` | Returning from background already closed: seal silently (no ka-chunk on resume); the cover shows the sealed card | Director |
| P2-10 | `RootView.swift:114-117` | Don't let a 4° wobble kill a sheet. While a sheet is presented, hold the engine in Armed (don't enter Pressing); close sheets only on contact (depth ≥ contactT). Cancel clip exports on `onDisappear` (`SpecimenSharing.swift`) | Director + UI |
| P2-11 | `RootView.swift:206` | Present Settings as a nested sheet from `ShelfView` (or push it in a `NavigationStack`), so closing it returns to the Shelf | UI |
| P2-12 | `SettingsView.swift:82-86` | On non-Duo show an `InfoRow` "Press by dragging · ALWAYS ON" instead of a disabled OFF toggle | UI |
| P2-13 | `CardDetailView.swift:95-122` | Add "Press another" (puts that kind on the anvil and dismisses) and "Replay" (plays the trace's failure window in a mini `RealityView`, or as v1.1) | UI |
| P2-14 | `RootView.swift:232`, `RevealCardView.swift:198-212` | Reduce Motion "shorter reveal" (bible §6.4): the card wait goes from 800 to 300 ms, actions show with the card | UI |
| P2-15 | `ShelfView.swift:342-346` | At AX3, "Glass Bottle" truncates in 2-column slots. Allow 2 lines for the name at accessibility sizes, or use a 1-column grid when `isAccessibilitySize` | UI |
| P2-16 | `CoverView.swift` | Cap the cover at `.accessibility2` (466×678 pt, minus the 84 pt clock column) | UI |
| P2-17 | `PressOverlays.swift:21-24` | The ghost arc should "fade for good" after the first contact event (persist `hasSeenArc`), not reappear on every return to Armed | UI |
| P2-18 | `RootView.swift:118-120` | On cover-up, also dismiss the reveal's share sheet and dialog (`share.item = nil`, `choosingShare = false`) | UI |

### 5.2 Delight audit: where it isn't premium yet, and the exact micro-interaction

1. **Collect (biggest miss).** Today the card fades into nothing. Proposed: actions sink into the console (offset +12, opacity 0, 0.15 s). The Shelf key rises from the console (spring 0.32/0.7). The card flies along a slight arc into the key: scale 1 → 0.16, rotation to the sticker's seeded tilt, spring(0.38, 0.72). On impact the key face drops 3 pt (keyDown) and springs back (keyUp), the count rolls `6/10 → 7/10` with `.numericText()`, and the collection chime and `UIFeel.success()` land in the same frame.
2. **Rest beat.** After the collect there's a 0.9 s ritual. The ram rises the last few mm with a *psst*. The mess slides off the anvil's front lip, scraped by the platen (ease-in 0.35 s). Lamps go amber → green with a click. 0.5 s of room tone. Then the object drops with the squash. This makes "one more" feel earned, not autoplayed.
3. **Numbers that count.** On the card, `48 TONS` counts up from 0 over 0.45 s (ease-out, `.numericText()`), with a gauge tick sound every 6 t on the C-pentatonic ladder. It lands one frame before the stamp. Static under Reduce Motion.
4. **Stamp weight.** At stamp contact: a 2 pt card drop and recover (spring 0.18/0.5), 6–10 ink-speck dots in `stamp` at 60% opacity seeded around the stamp, and a dry *thup*. Golden: the stamp leaves a gold-foil glint sweep (masked `LinearGradient` crossing the card over 0.8 s, once).
5. **Hold the card.** A long press on the reveal or detail card tilts it with the finger (`rotation3DEffect` ±8°, specular `LinearGradient` overlay following the drag) like a holographic trading card. A light tick fires at each edge. Turned off under Reduce Motion.
6. **New best.** In the Shelf, the old sticker peels up from a corner (rotation 0 → 20°, scale 1.05, fade) and the new one slaps down (existing `stickerPeel`), with a sticker *thwap*.
7. **Locked slots answer back.** Tap: the silhouette wiggles (2 × ±3°, 0.3 s), a muffled locked clunk plays, and the progress line brightens. The Unsquishable slot's "???" *briefly* shows the ball's silhouette bulging the paper, then flattens.
8. **10/10.** On the Collector unlock, every sticker on the Shelf does a staggered 40 ms hop, and the progress bar fills with a ripple. One-time.
9. **Cover is alive.** Sealed: the needle breathes ±1 t. Idle: the fold glyph loops. Queuing an object plays its plop *inside the closed phone* (this already happens; call it out in marketing).
10. **Perfect feels earned.** At seal, if the press qualifies as Perfect, the lamps do one slow green "wink" before the ka-chunk, a hint during the press itself. The seal on the card gets a 0.3 s spin-in (rotation −90 → −12°).
11. **First press of a new object.** The console chip's tint dot pops (scale 1.4 → 1) and the name crossfades. On first-ever placement of an object, the VoiceOver line *also* appears as a one-line paper tag on the chip for 2 s ("Squeaky, rubbery, surprisingly brave."). This is the cheapest personality boost in the app.
12. **Golden reveal.** The gel wall warms to `#F3E6C4` over 400 ms *before* the card drops, a golden sting plays, and the card's sparkles twinkle twice (scale 0.6 ↔ 1.0).

*Reference:* Apple's guidance is that people learn better by doing and that teaching should happen in context, near the UI it refers to ([HIG Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding.md); [Onboarding for Games](https://developer.apple.com/app-store/onboarding-for-games/)). P0-1 and P2-2 are about making the in-machine teaching actually appear and read correctly; the copy additions below are context-tied, one line, and shown once.

---

## 6. Copy deck

Tone rules: calm, not rage; dry and witty; 12+ only in words; Mono UPPER for labels, sentence case for details; no exclamation marks outside captions.

### 6.1 Strings to change

| Where | Current | New |
|---|---|---|
| `AchievementInfo.swift:23` firstSquish | Your first pressed specimen. | Specimen №0001. The first of many. |
| `:24` perfectionist | A Perfect Squish on 5 different objects. | Perfect Squishes on 5 different things. |
| `:25` midas | Found a golden variant. | Pressed a golden one. 1 in 50. |
| `:26` whatsInside | Found 2 different surprises inside. | Found two different surprises. |
| `:27` patience | One press that took over 30 seconds. | One press, over 30 seconds. Very zen. |
| `:28` collector | Squished all 10 objects. | All 10 pressed. Shelf complete. |
| `:29` theSecret | Met The Unsquishable. | Met The Unsquishable. It won. |
| `:30` popStar | Popped 500 bubbles. | 500 bubbles popped. Lifetime. |
| `:31` steadyHands | 10 Perfect Squishes. | Ten Perfect Squishes. Steady. |
| `:32` pumped | Pumped the press: opened and pushed again mid-press. | Eased off and pressed again. Twice. |
| `ObjectCatalog.swift:115` perfect hint | Earn a Perfect Squish | Press slowly. Never ease off. |
| `:113-114` hints | Squish 3 different things / Squish 6 times | Squish 3 different things · 1/3 / Squish 6 times · 4/6 (live progress) |
| `ObjectCatalog.swift:100` egg | Some eggs-ceptional pressure. | Over hard. Very hard. |
| `:102` soda | Freshly flattened. Do not recycle twice. | Finally fits in the recycling. |
| `:103` gummy | Chewed by four hundred tonnes. | Now a gummy rug. *("tonnes" also clashes with the card's TONS.)* |
| `:104` glass | Seven years' bad luck, minimum. | It was half empty anyway. *(The mirror joke doesn't fit a bottle.)* |
| `SettingsView.swift:63` | Soft is gentler: no crunchy or wet sounds, softer highs. | Soft is gentler: rounder highs, fewer crunches, nothing wet. |
| `SettingsView.swift:85` (non-Duo) | This iPhone has no hinge, so you always press by dragging down. On iPhone Duo this lets you press without folding. | Replace the disabled toggle with an InfoRow: "Press by dragging" · ALWAYS ON. Footnote: "On iPhone Duo you can choose between folding and dragging." |
| `SettingsView.swift:84` (Duo) | Drag down on the screen instead of folding your iPhone Duo. Handy one-handed, or when folding isn't comfortable. | Drag down on the screen instead of folding. Handy one-handed, or when folding isn't comfortable. |
| `ShelfView.swift:167-170` empty | Nothing pressed yet / Every press you finish lands here as a specimen card. | Nothing flat yet / Every press you finish lands here, numbered and stamped. |
| `SpecimenSharing.swift:29` | Couldn't draw the share image. Please try again. | The image smudged. Try again? |
| `RootView.swift:144` (Duo VO hint) | Fold your iPhone slowly to press. | Fold your iPhone closed, slowly, to press. Open it again to see what's left. |
| `RootView.swift:141` (VO value) | N percent pressed | Ready / Touching / N percent squished / Sealed (from real depth) |
| `RootView.swift:143` (touch VO hint) | Swipe up to press down, swipe down to ease off. | (keep) |
| `PressOverlays.swift:246-247` safety (Duo only) | ON-SCREEN ONLY / Never close your phone on real things. | (keep; show only on hinge devices; no safety toast on other iPhones) |
| `ShelfView.swift` / `PressOverlays.swift:324-325` key at zero | Shelf 0/10 | Shelf *(count appears from 1/10)* |
| `RevealCardView.swift:60-62` | Share Clip / Share Image (dialog) | One-tap "Share" (clip). Context menu: "Share Clip", "Share Still" |
| `Captions.swift:87` reveal | TA-DA! (never visible) | Remove from visuals; VoiceOver: "Done. Here's what's left." |

### 6.2 Strings to keep (they're good)
"NEW OBJECT UNLOCKED / Soda Can · up next" · "NEW BEST" / "NEW ON THE SHELF" · "PRESS SEALED / OPEN TO SEE" · "ON THE ANVIL" · "Open to press" · "SAVED AS YOU GO" · "Every press has the same odds. Nothing is for sale." · "No ads. No tracking. No in-app purchases." · "Thanks to everyone who closed their phone very, very slowly." · "Developing your clip / Re-pressing it frame by frame…" · "Something went sideways" · "Only the card goes. Your presses, unlocks and achievements stay." / "Keep It" · "Some things refuse to be squished…" · every VoiceOver object description · flavour lines not listed above ("It's in the grout now." and "He'll be fine. Probably." are the voice of the app).

### 6.3 New strings (toast band 80–86%, one at a time, never during a press)

| Trigger | Title (Mono micro) | Detail (Rounded semibold) | Glyph / accent |
|---|---|---|---|
| 2nd consecutive slam (P0-5), max 3 lifetime | SLOW IS SMOOTH | Close it slowly. Every crack gets its moment. | `tortoise.fill` / yellow |
| First reveal, sound probably off (P1-6), once | SOUND ON? | Squish is half sound. Unmute for the full crunch. | `speaker.wave.2.fill` / yellow |
| Hinge < 100° while idle (P1-15) | OPEN IT UP | Open your iPhone flat to start a press. | fold glyph / graphite |
| Tent pose (P1-15) | LAY IT FLAT | Set it on a table, then push the top down. | `rectangle.portrait.on.rectangle.portrait` |
| Sealed on the inner display, still < 90° after 1.2 s (P0-3 safety net, if not auto-revealing) | ALL DONE | Open it up to see what's left. | `arrow.up.and.down` |
| First Perfect Squish ever (P1-13) | PERFECT SQUISH | Slow, steady, no second thoughts. | seal / yellow |
| Non-Duo, 8 s idle with no touch on first run (fallback after the platen pulse) | DRAG DOWN | Pull the press down. Slower is nicer. | `hand.draw.fill` / yellow |
| Clip export cancelled by a sheet closing (P2-10) | CLIP PAUSED | The press moved. Tap Share again any time. | `film` |

Locked chip-menu rows (P2-7): "Soda Can · squish 3 different things", "Gummy Bear · squish 6 times", "Glass Bottle · press slowly, never ease off", "??? · some things refuse to be squished".

Cover sealed teaser (P2-5): keep "OPEN TO SEE"; add a micro line above the silhouette: "WHAT'S LEFT?"

---

## 7. Fix order (suggested)
1. **Day 1:** P0-1, P0-2, P1-8 (engine arming and the touch mapping), plus their unit tests.
2. **Day 2:** P0-3, P0-4 (reveal gating, fold-to-continue, close-during-reveal), P1-7 (Game Center banners).
3. **Day 3:** P0-5 (slam toast), P1-1 (thumbnail-gated reveal), P1-5 and P1-6 (safety and sound tips), P1-18 (Dynamic Type caps).
4. **Then:** P1-2 and P1-3 (collect flight plus the rest beat; the single biggest "premium" upgrade), P1-10 and P1-11 (VoiceOver), and the rest of P1.
5. **P2 delight** as time allows, in §5.2 order (collect → rest beat → counting numbers → stamp weight).
