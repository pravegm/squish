# 05 — Hinge UX research: driving Squish from the iPhone Duo hinge

*Research date: 22 Oct 2026, the day before the iPhone Duo goes on sale. There are no public real-device measurements yet. Almost everything numeric about hinge behaviour comes from the Xcode 27.1 simulator or from Apple's own wording.*

**Confidence tags used throughout**
- **[V] Verified**: Apple documentation, Apple Tech Talk code, or source code I read directly.
- **[R] Reported**: a review, a third-party developer measurement (mostly simulator), or a secondary write-up.
- **[G] Guess**: my own inference or design proposal. Validate it on hardware.

---

## Key takeaways

1. **The API is small and simple. [V]** SwiftUI has `onHingeChange(isEnabled:_:)`, which passes `(DeviceHingeContext, DeviceHingeContext)`. `context.hinge` is a `DeviceHinge?` with `angle: Angle` and `status: DeviceHinge.Status` (`.closed`, `.partiallyOpen`, `.fullyOpen`). UIKit has `UIHingeInteraction(updateHandler:)`, which delivers a `UIHinge` with `angle: CGFloat` **in radians** and a status. `hinge == nil` means no hinge, or the view has left a hierarchy that provides hinge updates. ([SwiftUI doc](https://developer.apple.com/documentation/swiftui/view/onhingechange(isenabled:_:)), [UIKit doc](https://developer.apple.com/documentation/uikit/uihingeinteraction))
2. **The input is coarse and only arrives while the hinge moves.** Federighi gives about **5° accuracy**, and the stream is already smoothed by the system. [R] ([9to5Mac](https://9to5mac.com/2026/09/29/craig-federighi-on-how-apple-helps-developers-make-the-most-of-the-iphone-duo-video/), [MacDailyNews](https://macdailynews.com/2026/09/29/iphone-duo-was-designed-as-a-window-not-a-folded-iphone-craig-federighi-says/)) The simulator delivers about **30 updates/s** during a fold. [R] ([RN issue](https://github.com/thiagobrez/react-native-arrangement-view/issues/27)) Apple says the rate and granularity are "system policy" and can change. [V] Events stop when the hinge stops ("hinge events only arrive while it moves"). [R] ([Crate source](https://github.com/odoisveryverygood/crate-duo)) Squish therefore has to **interpolate to 120 Hz itself** and **hold state when the input goes quiet**.
3. **The inner display probably turns off well before 0°. This is the biggest design constraint.** Simulator reports disagree. One says the inner display stays lit down to about 20° when closing [R] ([skill](https://github.com/WhitenWhiten/iphone-duo-simulator-skill)). Another says it goes off and moves the app to the outer display below about 55° [R] (Crate's `HingeFX.swift`). The switch is path-dependent and takes 1–2.5 s [R] ([hinge CLI](https://github.com/artemnovichkov/hinge)). **Design the whole visible crush to finish by about 60°.** Treat 60°→0° as a "sealed press" phase you can't show reliably.
4. **There is strong hysteresis on opening.** In the simulator, opening from shut keeps the cover display lit and reports `.closed` up to about **150°**. [R] On reopen, the reveal therefore happens late and arrives as a display switch, not a smooth ramp. Make the reveal a discrete event.
5. **The app is resized, not relaunched. [V]** Closing is a size-class/trait change and "your process keeps running." The app moves to the outer display and keeps running. ([Apple forum summary](https://developer.apple.com/forums/thread/847644), [Group Lab notes](https://antongubarenko.substack.com/p/iphone-duo-group-lab-2-q-and-a)) Keep crush state in a model above any `if` branch that changes with size class, or it will be destroyed. ([Group Lab gist](https://gist.github.com/frankschlegel/6356a059426b2393528691822edfdae6))
6. **Literal hinge geometry is a poor fit for a press.** The upper half only covers the lower half below 90°. Real contact with an on-screen object would happen at 30–60°, exactly where the display may switch off. **Use a virtual ram mapped over a comfortable range (proposal: 165°→60°).** Don't simulate the jaw literally. [G]
7. **The hardware suits slow crushing.** The hinge "bends and stays put at pretty much any angle" with a variable torque profile ([Gizmodo](https://gizmodo.com/iphone-duo-review-2000827502)). Marques Brownlee calls it "probably the best foldable at just being partially open" ([MacStories roundup](https://www.macstories.net/roundups/iphone-duo-review-roundup-great-hinge-messy-apps-and-everybody-misses-face-id/)). The magnet gives a "clap" at close. [R] The phone weighs 254 g and opening is "very much a two-handed operation" ([9to5Mac review](https://9to5mac.com/2026/10/21/iphone-duo-review/)). **Recommend tabletop as the hero pose:** lower half flat on the table, push the top half down.
8. **Damage should be irreversible, with a small elastic rebound.** Track a monotonic "max penetration" ratchet for plastic deformation. Let roughly 10–15% spring back when the user reopens. This fixes the hysteresis/noise problem and matches the press metaphor. [G]
9. **Don't build a Duo-only app.** No hinge `UIRequiredDeviceCapabilities` key exists that I could find. Apple's answer to "can an app require Duo capabilities" was that apps "don't need to require specific device capabilities or isolate themselves" [V] ([forum](https://developer.apple.com/forums/thread/847644)). Apple staff in the labs "strongly discouraged" Duo-exclusive apps [R]. **Ship on all iPhones** with a touch-driven "pinch press" fallback, and make the Duo the hero.
10. **Review risk is Guideline 2.4.2, not hinge wear.** 2.4.2 says apps must be "used in a way that does not risk damage to the device" [V]. **Squish must never suggest putting a real object between the halves**, and should coach slow closing, not slamming. Apple publishes no fold-cycle rating. Joanna Stern's 32,640 machine folds left the hinge only "a little bit stiffer" [R] ([Cult of Mac](https://www.cultofmac.com/news/hingey-iphone-duo-hinge-fold-test)).

---

## 1. Hinge API: what is known

### 1.1 Signatures [V]

```swift
// SwiftUI (iOS 27.1+)
nonisolated func onHingeChange(
    isEnabled: Bool = true,
    _ action: @escaping (DeviceHingeContext, DeviceHingeContext) -> Void   // (old, new)
) -> some View

struct DeviceHingeContext: Equatable, Sendable { var hinge: DeviceHinge? }
struct DeviceHinge: Equatable, Hashable, Sendable {
    var angle: Angle                 // 180° when flat
    var status: DeviceHinge.Status   // struct with static members, NOT an enum
}
// DeviceHinge.Status: .closed ("The hinge is closed."), .partiallyOpen,
// .fullyOpen ("The hinge is open as far as the device allows.")

// UIKit
@MainActor class UIHingeInteraction: NSObject, UIInteraction {
    init(updateHandler: (UIHingeInteraction, UIHingeInteraction.Update) -> Void)
    var isEnabled: Bool
}
// Update.hinge: UIHinge?  (nil when the interaction leaves a hierarchy that provides hinge updates)
@MainActor class UIHinge { var angle: CGFloat /* radians */; var status: UIHinge.Status }
```

Sources: [onHingeChange](https://developer.apple.com/documentation/swiftui/view/onhingechange(isenabled:_:)), [DeviceHinge](https://developer.apple.com/documentation/swiftui/devicehinge), [DeviceHinge.Status](https://developer.apple.com/documentation/swiftui/devicehinge/status-swift.struct), [UIHingeInteraction](https://developer.apple.com/documentation/uikit/uihingeinteraction), [UIHinge](https://developer.apple.com/documentation/uikit/uihinge).

Practical notes:
- **The units differ between frameworks.** SwiftUI gives an `Angle`. UIKit gives a `CGFloat` in radians. Normalise both to degrees in one adapter. [V]
- **`Status` is a struct, so a `switch` needs a `default:` case.** SandValley does this. A blog also reports a `.unknown` status on the UIKit side [R] ([BleepingSwift](https://bleepingswift.com/blog/onhingechange-hinge-angle-swiftui)). Expo's wrapper exposes `unknown` as well. ([Expo](https://docs.expo.dev/versions/latest/sdk/hinge/))
- **The handler fires once with the initial state** and then on each change. It also fires when the interaction moves between hierarchies, which matters when a display switch rebuilds views. [V]
- **`isEnabled: false` pauses delivery.** Use it when the press scene isn't on screen. [V] ([Examples repo](https://github.com/artemnovichkov/iPhone-Duo-by-Examples))
- **Status is "determined by the system based on the current angle and device orientation."** [V] It is therefore not a pure angle threshold.
- **There is no system pose value.** Infer pose from status, angle, orientation and size class. [V] ([forum](https://developer.apple.com/forums/thread/847644)) Federighi talks about "book pose, on-table pose, tent pose" being communicated through frameworks, but in practice that means layout behaviour, not an enum. [R]
- **Apple's own sample pattern** (Tech Talk 111464, guitar pitch bend) only uses the angle while `status == .partiallyOpen` and resets to 0 otherwise. [V] ([Tech Talk 111464](https://developer.apple.com/videos/play/tech-talks/111464/)) This is a good template, with one caveat: Squish should **not** reset damage when the status leaves `.partiallyOpen`. See the state machine.

### 1.2 Update rate, latency, precision

| Property | Value | Confidence |
|---|---|---|
| Accuracy | "about five degrees", smoothed by the system | [R], Federighi via 9to5Mac/MacDailyNews |
| Rate (simulator) | ~30 updates/s during a fold; a component re-rendered ~33 times per open→book→open fold | [R], one developer |
| Rate (device) | **unknown**; "system policy… can change based on system state" | [V] that it's undefined |
| Rate when stationary | no events; they arrive only while moving | [R], Crate comment |
| Latency | **unknown**; no figures anywhere | — |
| Underlying source | CoreMotion private `CMAngleManager`, the same source UIKit's `UIHinge` uses | [R], [hinge CLI](https://github.com/artemnovichkov/hinge) |
| Android comparison | `SENSOR_DELAY_NORMAL` ≈ 5 Hz, "too coarse for an animation" | [R], [RN issue](https://github.com/thiagobrez/react-native-arrangement-view/issues/27) |

What this means:
- With ±5° accuracy over a 105° working range, only about **20 distinct trustworthy steps** exist. Resolution may be finer than accuracy, which helps smoothness but not absolute position. [G]
- The system already smooths the stream, so adding heavy filtering on top **adds latency twice**. Use a light, adaptive filter (One-Euro) plus a render-side spring. Avoid a big moving average. [G]
- "System state" could include Low Power Mode or thermal throttling. The Duo reportedly "gets very hot under sustained load" ([Notebookcheck](https://www.notebookcheck.net/Apple-iPhone-Duo-reviews-are-in-Plenty-of-criticism-but-positive-hinge-stress-test.1430224.0.html)). Assume the rate can drop to about 10 Hz and test for it. [G]

### 1.3 Behaviour near 0°, 180°, and at display switches

Every number below comes from the simulator, and the reports conflict:

- **Opening from 0°:** the cover display stays lit and the hinge reports `.closed` up to about **150°**. [R] ([WhitenWhiten skill](https://raw.githubusercontent.com/WhitenWhiten/iphone-duo-simulator-skill/main/SKILL.md))
- **Closing from 180°:** the inner display stays lit down to about **20°** [R] (same source). Crate's code comment says instead: "below ~55° the Duo turns the inner screen off and moves the app to the outer display" [R]. On a real device this may also depend on the proximity/ambient sensors.
- **The switch is path-dependent.** "A jump from 0° to 90° switches to the inner display, while 5° steps stay on the cover." The switch takes **1–2.5 s** after the angle changes. The simulator sometimes "stops following the hinge while still reporting every new angle." [R] ([hinge CLI](https://github.com/artemnovichkov/hinge))
- **The system covers the handover** with a blurred snapshot [R], and Apple's own open/close animation turns the screen "translucent, a window to what's below" (Federighi) [R]. Gizmodo says the blur animation "gets old fast" [R]. **You can't fully choreograph the close moment.** The system owns roughly the last second.
- **Fold "division" region activation** varied across sweeps: 98°, 132.5°, 132.5° and 172.6° [R] ([FoldHunt guide](https://foldhunt.com/guides/iphone-duo-fold/)). The crease turns active about 1 s after the hinge stops [R]. This confirms that layout-side signals are laggy and noisy, so don't use them for crush timing.
- **Presets in the simulator:** half = 130° (`PartiallyOpen`), book ≈ 128°, laptop ≈ 110°. [R]
- **Fully open:** `.fullyOpen` means "open as far as the device allows" [V]. One teardown claim of 15–165° free-stop range could not be traced to a source and is unverified. Assume real flat reads about 178–180° and may jitter. [G]
- **Do updates continue while the inner display is off and the app is on the outer display?** **Unknown.** The UIKit doc says `hinge` goes nil only when the interaction leaves a hierarchy that provides updates [V]. Because the app is resized in place rather than torn down, I expect updates to continue [G]. Crate deliberately resets FX on `released()` when closed, so it doesn't rely on this. **Test on device on day one.**

### 1.4 Code patterns in the wild

- **Accorduon** (Artem Novichkov, MIT) uses hinge speed with a clamped dt. Speed is computed in either direction. dt is clamped between 1/120 s and 0.2 s "so a sudden jump after a pause still counts as a push." Speed is converted to air with `pump(speed/120)`, and the air leaks on its own. The visual uses `withAnimation(.interactiveSpring) { stretch = degrees / 180 }`. The fallback is a `DragGesture` velocity. [V] ([AccordionView.swift](https://github.com/artemnovichkov/Accorduon/blob/main/Accorduon/App/AccordionView.swift)) *Lesson: velocity from raw samples works if you clamp dt. The interactive spring covers coarse updates.*
- **Duogami** (origami) uses a four-phase gesture: `needsOpen → ready → folding → needsReopen`. It arms at **≥155°**, computes progress as `(155 − angle)/75` (full at 80°), shows "folding" below 145°, and **commits at ≤80°**. It then requires a reopen to ≥155° before the next fold, and resets on scene-inactive or when a sheet is shown. The README says: "There's no need to close the phone all the way." [V] ([source](https://github.com/artemnovichkov/Duogami)) *Lesson: the closest existing analogue to Squish. The commit happens well above 0° and there's an explicit re-arm.*
- **DuoBird** uses a `FlapDetector` that tracks the minimum angle since the last flap. A flap fires when the angle rises **10°** above that minimum, and the detector re-arms after a **5° fold-back**. [V] ([FlapDetector.swift](https://github.com/artemnovichkov/DuoBird)) *Lesson: 5–10° hysteresis bands match the ~5° accuracy.*
- **Crate** (sampler, hackathon winner) treats rest as ≥110° and full FX at 65°: `p = (110 − angle)/(110 − 65)`. A 4% dead zone handles "resting jitter around 110°". A DROP fires when the hinge snaps open (p > 0.6 to p < 0.1 within 0.45 s). It is suppressed for 2 s after launch because "the simulator can start folded". Closing must never mute the beat. [V] ([HingeFX.swift](https://github.com/odoisveryverygood/crate-duo)) *Lesson: ignore hinge events right after launch, and use a dead zone at rest.*
- **SandValley** derives slope from `(180 − angle)/2` per half. Nothing happens until about 15° of tilt, and the sand pile persists after unfold. [V] *Lesson: persistent results feel good.*
- **FoldFling** ("bend the phone to charge a paper catapult, then open to launch"), **Hingami**, **Marbles Unhinged**, **Toastie**, **FoldAhhh** and **Fold Crack** appear only as directory listings. I found no public code. [R] ([FoldHunt](https://foldhunt.com/iphone-duo/)) I found **no existing press, crush or squish app** in FoldHunt's listing, which I read in full. Toastie (closing shuts the toaster lid) is the nearest metaphor. [R]

---

## 2. Physical specs that matter

| Spec | Value | Source |
|---|---|---|
| Inner display | 7.6" (7.58" rect), ProMotion up to 120 Hz, nano-texture matte, 3000 nits outdoor | [V] [Apple newsroom](https://www.apple.com/in/newsroom/2026/09/apple-unveils-iphone-duo/) |
| Inner resolution | Panel 1878×2670 at 430 ppi [R] ([MacObserver](https://www.macobserver.com/tips/round-ups/iphone-duo-displays-explained-7-6-inch-inner-5-4-inch-outer-120hz-3000-nits/)). App canvas **951×669 pt @3x** (2853×2007 px) open sideways, 669×951 upright [R] ([duo-fold-control](https://github.com/tosbaha/duo-fold-control), skill). The two figures differ, so the panel is probably downsampled. |
| Outer display | 5.4", 1398×2034 px, 460 ppi; app window **466×678 pt**; trailing inset 84 pt (clock column), bottom 34 | [R] |
| Crease | Division region **40 pt wide** in the middle of the glass (x 455.5–495.5 open sideways). Visible mainly in bright light; "you can definitely feel it" (Verge) | [R] |
| Weight / thickness | 254 g; 11.3 mm closed, 5.2 mm open | [R] 9to5Mac |
| Hinge | >100 components, variable torque, magnet array holds it closed; holds "at pretty much any angle"; resistance "changes with the angle" | [V] Apple / [R] reviews |
| Durability | **No Apple fold-cycle rating.** 32,640 machine folds: slightly stiffer, no failure. Samsung rates the Z Fold 8 at 500k | [R] |
| Haptics | Taptic Engine behaviour on Duo not documented; nothing about haptic differences when folded | unknown |
| Biometrics | Touch ID in the side button | [V] |
| Price (UK) | From **£1,999** (256 GB); £2,199 / £2,599 / £3,199. On sale 23 Oct; US delivery estimates slipped to Jan 2027 | [R] [StudentBeans](https://www.studentbeans.com/blog/uk/uk-iphone-duo-launch), [Gadget Scout](https://www.gadgetscout.co.uk/articles/apple-s-1-999-iphone-duo-delivery-estimates-slip-into-2027.html) |

**Viewing the inner display while it closes [G]**
- **180→120°:** fully readable.
- **120→90°:** laptop/book poses. Apple designs for these (laptop ≈ 110°, book ≈ 128°).
- **90→60°:** the halves start to face each other, and the user looks into a wedge. Content near the fold on the lower half stays visible to a user positioned above. Content on the upper half foreshortens badly.
- **Below ~45°:** effectively unviewable. It's also the likely display-off zone.
- **Conclusion:** the "money shot" must be on the **lower half near the fold**, between about 110° and 60°.

**How people hold it while closing [R/G]**
- Opening needs two hands [R]. Closing slowly against variable torque, with the magnet snapping in at the end, works best in one of two ways:
  - **Tabletop:** lower half on the table, one finger or palm pressing the top half down. This is like operating a real press lever, which is great.
  - **Two-handed book grip:** squeeze like a book.
- One-handed closing is possible but jerky [G]. Gizmodo says the closed device is easy one-handed, but the open device is two-handed for most people [R].
- **Recommend the onboarding copy:** "Set it on a table. Push the top down slowly."

---

## 3. Interaction design for an angle-driven press

### 3.1 Why not map geometry literally
Put the lower half flat and let θ be the hinge angle. The upper half is vertical at 90° and only overhangs the lower half when θ < 90°. Above a point x mm from the hinge, the plate height is h = x·tan θ. For a 40 mm-tall virtual object 30 mm from the hinge, contact happens at θ ≈ 53°. That is right at the suspected display-off boundary. **A literal jaw puts the climax where the screen may be dark.** [G]

**Recommendation:** render a **virtual hydraulic ram on screen** with travel driven by a remapped angle. The physical close is the *lever*, and the screen shows the *press*. Use the real geometry only as flavour, such as a subtle perspective tilt of the ram housing.

### 3.2 Choosing the pose and axis
- The inner display "doesn't honor your supported interface orientations" [V], so Squish must handle both fold axes:
  - **Horizontal fold (upright, tabletop):** the ram comes down from the top half towards an anvil on the bottom half, with the object sitting just below the crease. This is the hero mode.
  - **Vertical fold (book):** turn it into **vice mode**, with jaws closing from the left and right. Same engine, rotated 90°. Tag every result with which mode made it, for fun and collectibility.
- **Detect the axis** from `reservedRegions(kind: .division, options: .includeInactive)`: the frame is wider than tall for a horizontal hinge. This is the same trick Duogami uses. [V]
- **Keep interactive controls out of the 40 pt crease** [V], following the HIG and the "Strike a pose" talk. ([HIG](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo), [Tech Talk 111463](https://developer.apple.com/videos/play/tech-talks/111463/))

### 3.3 Mapping, dead zones, hysteresis [G]
- **Dead zone at the top (≥165°):** flat-ish jitter shouldn't move the ram. Crate uses a 4% dead zone at rest and Duogami arms at ≥155°.
- **Use a relative start.** If the user starts already folded, capture θ₀ = current angle when they tap **Press** and map from min(θ₀, 165°). Never let the ram jump down on arming.
- **Use the contact phase to build anticipation.** The ram descends freely to touch the object over the first ~20% of travel. There's no deformation yet, just hydraulic hiss and a tick at contact.
- **The deformation phase is eased, not linear.** People close faster at the start and slow down as resistance and their attention build. An ease-in on depth gives fine control at the end, where it matters most.
- **Bottom-out at 60°.** Depth reaches 1.0 at θ_end = 60°. Below that the press is "sealed": no more visible change on the inner screen.
- **Hysteresis.** Fire state transitions (contact, crack, flatten, commit) with **±4°** bands, matching the ~5° accuracy and DuoBird's 5° re-arm. Continuous depth itself needs no hysteresis, because damage is ratcheted.

### 3.4 Reverse motion and persistence
Options:
- **(a) Fully elastic:** everything springs back. This feels like rubber and kills the "result".
- **(b) Fully plastic:** nothing springs back. This is truthful but feels dead mid-crush.
- **(c) Recommended: plastic + elastic + fracture.**
  - Deformation = `ratchet(maxDepth)` × material plasticity.
  - The elastic part (10–15%, depending on material) follows the ram back up when the user reopens.
  - Fractures are **irreversible events**: crack sounds, debris particles, liquid. Fire each one once, when depth crosses its threshold on the way down.
- **Reopening mid-crush lifts the ram.** The object stays crushed to its max-depth so far, so the user can "pump" the press for multi-stage crushes. Pumping is itself fun, like Accorduon's bellows.
- **Optional pump bonus:** compute pump energy from |dθ/dt| as Accorduon does. Repeated pumps add heat or extra fracture chances, but cap them so the device-wear optics stay sane.

### 3.5 Interpolation for 120 Hz visuals
- Inputs arrive at about 30 Hz, may be 10 Hz, and stop when the hinge stops. Drive rendering from a `CADisplayLink` or `TimelineView(.animation)` that **chases** a target. Don't render directly in the hinge callback.
- Use a **One-Euro filter** on the raw angle: low jitter when slow, low lag when fast. Feed it into a **critically damped spring**, with ζ = 1 and a natural frequency of about 18–25 rad/s.
- **Limit extrapolation.** Predict forward from the filtered velocity for at most ~1.5 sample intervals (≤50 ms), and only while the newest sample is fresh (< 80 ms old). When samples stop, **hold, don't drift.** The hinge is free-stop, so silence means the user paused.
- **Never let prediction cross a fracture threshold.** Fractures fire only from measured (filtered) depth, so a false prediction can't cause an irreversible event.

### 3.6 Full close, outer display, reopen reveal
- **At full close (`.closed`, or the trait change to compact width on the outer display):** the system blur covers the handover [R]. Accept that, and show a **"press sealed" result card** on the outer display, 466×678 pt with an 84 pt trailing clock column:
  - pressure gauge peak
  - "crush score" / flatness percentage
  - a teaser silhouette, not the full result
  - a CTA: "Open to reveal"

  Use a `.success`/heavy haptic plus a hydraulic "chunk" sound on the magnet clap. Keep the result card in the same scene/model, not a new window. New windows can't be created on the outer display. [V]
- **Reopen reveal:** because of opening hysteresis (still `.closed` until ~150° in the simulator [R]), the inner display appears suddenly. Play a **reveal animation once on the first inner-display layout after a sealed press**:
  - the ram lifts
  - dust clears
  - the flattened object is shown with a ruler showing its height

  Gate it on a model flag, not on angle.
- **The outer display is a natural "trophy shelf"** (gallery of flattened objects) when the user launches closed. See §4.

### 3.7 Lessons from Android foldables
From memory, not re-verified this session, because the search budget ran out:
- Jetpack WindowManager `FoldingFeature` exposes only `state` (`FLAT`/`HALF_OPENED`), `orientation`, `occlusionType` and `isSeparating`, **with no angle**. Continuous angle needs `Sensor.TYPE_HINGE_ANGLE` (Android 11/API 30). ([FoldingFeature](https://developer.android.com/reference/androidx/window/layout/FoldingFeature), [Sensor](https://developer.android.com/reference/android/hardware/Sensor#TYPE_HINGE_ANGLE))
- Expo notes that Android never reports `closed`. It reports `unknown` when the window doesn't span the fold, and "device makers define their own ranges." [V] ([Expo](https://docs.expo.dev/versions/latest/sdk/hinge/))
- Samsung "Flex Mode" is posture-driven (half-folded UI), not continuous. Continuous-angle Android apps are mostly protractors and toys. Ports of the Duo fold effect to Android (e.g. [duo-open](https://github.com/marcoazeem/duo-open)) are driven by the hinge sensor.

Takeaways:
- Every platform treats continuous angle as low-rate and approximate.
- The successful patterns are **thresholded gestures with hysteresis** (DuoBird, Duogami) and **velocity-driven effects with decay** (Accorduon).
- Absolute-angle precision mechanics, like "match 47°", fight the sensor. Squish's mapping deliberately avoids needing precision.

---

## 4. App lifecycle edge cases

- **Launched while closed (outer display):**
  - **Don't block.** Show a trophy shelf (gallery of crushed objects), an object picker, and a gentle "Open to press" animation that uses a looping fold glyph.
  - Picking an object while closed queues it, so it's sitting on the anvil when the user opens.
  - Don't say "this app requires opening". Apple wants functionality in every pose [V] ([HIG](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)).
- **Started half-folded:**
  - Use the relative start (θ₀).
  - If θ₀ < 100°, nudge with "Open a bit more for full travel", but allow a short-travel press.
- **Tent pose:** the device stands on its edges with the halves facing outward. The angle is mid-range, but orientation makes the inner display hard to see. Status is orientation-aware [V], so detect tent as a large partial angle plus a device orientation where the fold is the topmost edge [G]. Pause the press and show "Lay it flat to press." Only camera and AlarmKit scene accessories can light the outer display in tent pose [V], so Squish can't.
- **Split View on the inner display:** "all apps participate in multitasking" [V]. In half-width (475×669 pt [R]), the hinge still reports, but the crease is at the window edge. Keep pressing enabled with a scaled scene, or show "Go full screen for the big press". `UIRequiresFullScreen` is honoured but still resizes on fold [V], and it costs multitasking goodwill. Prefer the adaptive approach.
- **Rotation:** the inner display ignores orientation locks [V]. Recompute the fold axis from the division region on every layout and switch between press mode and vice mode only when **no press is active**. Mid-press rotation keeps the mode locked.
- **Backgrounded mid-press** (phone call, Control Center): freeze the ram, save the state, and resume on return. This follows Duogami, which resets input on scenePhase changes.
- **Non-Duo iPhones:** `hinge == nil`. Fall back to **Pinch Press**:
  - two-finger vertical pinch drives depth
  - or press-and-drag on the ram handle
  - same engine, same ratchet

  Accorduon and Duogami both ship a fallback. Apple's examples show `ContentUnavailableView("Hinge Unavailable")` [V].

---

## 5. Apple guidance, App Review, featuring, durability

- **HIG "Designing for iPhone Duo"** [V] ([HIG](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)):
  - Supports book, surface and standing poses.
  - "Provide access to the same controls and content regardless of how someone holds or views the device."
  - Games should be "playable in every device pose".
  - Prefer changing aspect ratio over letterboxing.
  - There is **no guidance on playful hinge interactions, haptics, or people who can't fold.** That makes a fallback input both an accessibility feature and a review-risk reducer.
- **Apple positioning [V]:** hinge data is "ideal for driving interactions or effects." The Tech Talk ends: "use the Hinge API to build impressive interactions and effects." Federighi: "for creative experiences… developers can get closer to the raw information… we're excited to see what developers do with it." [R] Squish is exactly the kind of app Apple invited.
- **App Review:**
  - **2.4.2 (device damage)** is the relevant guideline [V] ([guidelines](https://developer.apple.com/app-store/review/guidelines/)). Never imply that physical objects go between the halves, and don't reward slamming. A "too fast!" penalty is safer and also better for tracking.
  - **4.2 (minimum functionality / lasting entertainment)** argues for content depth: many objects, materials and a collection. [V]
  - **2.4.1** encourages running on all devices. [V]
  - Nothing found specific to hinge wear or repeated folding. **Unverified:** whether review will query a "fold repeatedly" mechanic.
- **Duo-only distribution:**
  - There's no hinge capability key that I could find [G].
  - Apple's forum answer discourages requiring Duo capabilities [V]. Lab notes say Apple "strongly discouraged" exclusives and gave no eligibility answer [R].
  - Apple's Q&A QA1623 notes that capability restrictions can't be added after release [R], so the choice is one-way.
- **Featuring:** Apple opened Duo submissions on 5 Oct ([MacRumors](https://www.macrumors.com/2026/10/05/apple-opens-iphone-duo-app-submissions/)). From April 2027, every submission needs Duo screenshots: 1398×2034 outer and 2007×2853 inner [R] ([Blake Crosley](https://blakecrosley.com/blog/iphone-duo-for-developers)). Press is already writing "Made for iPhone Duo" roundups of quirky hinge apps ([Notebookcheck](https://www.notebookcheck.net/Made-for-iPhone-Duo-These-apps-show-what-Apple-s-foldable-can-do.1416967.0.html), [Digital Trends](https://www.digitaltrends.com/phones/the-iphone-duo-has-developers-going-wild-and-im-loving-their-creations/), [Axios](https://www.axios.com/2026/10/05/apple-iphone-duo-foldable-walkman-app)). FoldHunt tiers apps by verification ("Launch partner / Simulator verified / Developer claimed"), so submit there too. **I found no formal Apple "Made for iPhone Duo" editorial programme** [unverified]. Pitch via the App Store Connect featuring nominations form [G].
- **Durability numbers:** Apple has published none [R] ([Foldify](https://www.foldifycase.com/blogs/news/iphone-duo-hinge-durability-what-apple-did-not-publish-2026)). At 20 presses a day, a heavy user adds about 7k cycles a year. That's insignificant against a hinge that passed 32k folds with no failure, and in Samsung's range (500k) [G]. Still, avoid incentivising dozens of rapid pumps per session.

---

## 6. Testing

- **Xcode 27.1 (27A9275, shipped 15 Oct) adds an iPhone Duo simulator in Device Hub** with open/close/rotate/fold buttons. **Hold ⌥ to reveal a continuous hinge slider.** [R] ([Nil Coalescing](https://nilcoalescing.com/blog/AdjustingTheHingeAngleInTheIPhoneDuoSimulator/), [SwiftLee](https://www.avanderlee.com/swiftui/iphone-duo-simulator/)) Beta notes say the first launch can take minutes. [R]
- **There's no official simctl/devicectl command to set the angle.** Community tools:
  - [`artemnovichkov/hinge`](https://github.com/artemnovichkov/hinge): `brew install artemnovichkov/tap/hinge`, with `hinge sweep 180 0 2` for a 2 s sweep. It works by injecting the private HID event Device Hub uses.
  - [`tosbaha/duo-fold-control`](https://github.com/tosbaha/duo-fold-control): an XCTest bridge, `DuoFold.set(degrees:)`. Each call takes about 1–1.5 s.
  - [`foldctl`](https://github.com/tatsuz0u/foldctl).
  - Appium WDA PR [#1287](https://github.com/appium/WebDriverAgent/pull/1287): `setSimulatedHingeAngle`.

  All are simulator-only and private-protocol, so they may break. [R]
- **Simulator limits:** you can't test haptics, real latency, weight/reach, thermal behaviour, or real display-off angles [R]. Apple also says simulator-fine interactions "can feel awkward on physical hardware due to reachability… and physical weight distribution" [V] ([forum](https://developer.apple.com/forums/thread/847644)).
- **Squish test plan [G]:**
  1. Script sweeps at 0.5, 1, 3 and 8 s, plus pauses, reversals and pumps, using `hinge sweep` / `path`.
  2. Record callback timestamps to a CSV ring buffer in a debug overlay, like the Examples repo's "Angle History".
  3. Unit-test the filter and state machine on recorded traces. Duogami ships unit tests for `HingeGesture`, which is a good model.
  4. Build a replay harness that feeds traces at 30, 15 and 10 Hz.
- **Real hardware:**
  - **£1,999** in the UK. Ships 23 Oct, but stock is tight and US estimates slipped to Jan 2027 [R].
  - Apple runs iPhone Duo developer workshops ("device availability is not guaranteed") via Meet with Apple [V].
  - TestFlight on Duo should behave as on any iPhone, since it's the same phone idiom. **No Duo-specific TestFlight information was found** [unverified].
  - A web Device Posture API reportedly tells whether a device has a fold [R], which could support a web-based recruitment screener for beta testers.

---

## Squish hinge interaction spec v0

### A. State machine

```
States: Idle, Armed, Pressing, Sealed, Revealing, Paused, Fallback

Inputs: angle θ (deg, filtered), status, displayRole (inner/outer from size class),
        sceneActive, hingeAvailable, userTap(Press), fold axis

Fallback   : hingeAvailable == false            -> touch-driven depth, same engine
Idle       : no object on the anvil, or a result shown.
  -> Armed      when object placed && displayRole == inner && θ ≥ 100
                (θ0 := min(θ, 165))
Armed      : ram up, "Push the top down slowly".
  -> Pressing   when θ ≤ θ0 − 4          (4° hysteresis vs ~5° accuracy)
  -> Idle       when object removed
Pressing   : depth = map(θ); damage = ratchet(depth); fractures fire on downward crossings.
  -> Armed*     when θ ≥ θ0 + 4 and depth < 0.05     (*damage persists; same object)
  -> Sealed     when depth ≥ 0.98 for ≥ 150 ms, OR status == .closed,
                OR displayRole becomes outer while depth ≥ 0.6
  -> Paused     when !sceneActive, or tent pose detected, or Split View width < 600 pt
  (reopening above contact in Pressing just lifts the ram; elastic part rebounds)
Sealed     : finalize result (flatness, score); haptic + sound on commit.
             If on outer display: show the "Press sealed — open to reveal" card.
  -> Revealing  on first inner-display layout && θ ≥ 120
                (or immediately if Sealed while still on inner, e.g. stopped at 58°)
Revealing  : ram lifts, dust clears, ruler measurement; save to collection.
  -> Idle       after animation or tap
Paused     : freeze ram, save model.
  -> previous state when the condition clears (re-capture θ0 relative to the current angle)
```

Rules:
1. Ignore hinge input for 1.5 s after launch or scene activation, as Crate does.
2. Store all state in an `@Observable` model above display-dependent view branches.
3. Never reset damage on a status change.

### B. Angle → press mapping (numbers to tune on device)

| Hinge θ | Normalised travel t | Phase | What the user sees/feels |
|---|---|---|---|
| 180→165 (or θ0) | 0 | Dead zone | Ram idle, faint hydraulic hum |
| 165→145 | 0→0.20 | Approach | Ram descends, no load; light tick at contact (t = 0.20) |
| 145→75 | 0.20→0.90 | Deformation | Object deforms; fractures at material-specific depths; rising continuous haptic |
| 75→60 | 0.90→1.00 | Bottom-out | Final compaction, highest "stress", strongest haptic and creak |
| <60 | 1.00 (clamped) | Sealed zone | No further visible change (the display may switch off); commit |

```
t(θ)   = clamp((θ0 − θ) / (θ0 − 60), 0, 1)     // θ0 defaults to 165
depth  = t < 0.20 ? t                            // linear approach
       : 0.20 + 0.80 * easeInCubicish((t − 0.20) / 0.80)
// easeIn with exponent ~1.6: fine control near bottom-out
easeIn(x) = pow(x, 1.6)
contactDepth = 0.20;  objectStrain = max(0, depth − contactDepth) / 0.80
```

Notes:
- The working range is 105°, which gives about 21 trusted steps at 5° accuracy. That is enough, because the visuals are spring-interpolated and the meaningful events are coarse.
- If device testing shows the inner display stays on to ~20°, move θ_end down to 45° for more travel. Keep the commit at ≥45°, because people can't see inside the wedge below that.

### C. Smoothing / prediction sketch

```swift
@Observable final class HingePressDriver {
    // Tunables
    var minCutoff = 1.2, beta = 0.04, dCutoff = 1.0      // One-Euro, in degrees
    let maxPredict: TimeInterval = 0.05, staleAfter: TimeInterval = 0.08

    private var fθ: Double?, fV = 0.0, lastT: TimeInterval = 0
    private(set) var measuredDepth = 0.0    // from the filtered angle only
    private(set) var renderDepth = 0.0      // spring output, 120 Hz
    private var springVel = 0.0
    private(set) var damage = 0.0           // plastic ratchet
    var plasticity = 0.88                   // per material; 1 − elastic rebound

    // Called from onHingeChange / UIHingeInteraction (normalise UIKit radians → degrees first)
    func ingest(degrees raw: Double, at t: TimeInterval = CACurrentMediaTime()) {
        guard let prev = fθ else { fθ = raw; lastT = t; return }
        let dt = min(max(t - lastT, 1.0/240), 0.2)      // clamp like Accorduon
        let rawV = (raw - prev) / dt
        fV = lowpass(fV, rawV, alpha(dCutoff, dt))
        let cutoff = minCutoff + beta * abs(fV)         // adapt: smooth when slow, fast when moving
        fθ = lowpass(prev, raw, alpha(cutoff, dt))
        lastT = t
        measuredDepth = depth(forAngle: fθ!)
        let plastic = measuredDepth * plasticity
        if plastic > damage {                           // fractures only from measured data
            fireFractures(crossing: damage...plastic)
            damage = plastic
        }
    }

    // Called every frame (CADisplayLink / TimelineView)
    func step(now: TimeInterval, frameDt: Double) {
        guard let θ = fθ else { return }
        let age = now - lastT
        let lead = age < staleAfter ? min(age + 1.0/60, maxPredict) : 0   // hold when quiet
        let target = depth(forAngle: θ + fV * lead)
        // Critically damped spring, ω ≈ 22 rad/s
        let ω = 22.0, x = renderDepth - target
        let a = -ω*ω*x - 2*ω*springVel
        springVel += a * frameDt
        renderDepth += springVel * frameDt
        renderDepth = max(renderDepth, 0)
        // Visual deformation = max(damage, renderDepth) so the plastic part never rebounds
        // and the elastic part follows the ram.
    }

    private func alpha(_ fc: Double, _ dt: Double) -> Double { let r = 2 * .pi * fc * dt; return r / (r + 1) }
    private func lowpass(_ a: Double, _ b: Double, _ k: Double) -> Double { a + k * (b - a) }
}
```

Implementation notes:
- Haptics: use one `CHHapticAdvancedPatternPlayer` continuous event, updating intensity and sharpness with `sendParameters` from `objectStrain`. Add transient events on fractures and at Sealed. The Duo's Taptic behaviour is undocumented, so test it on device.
- Speed guard: if |fV| > 250°/s during Pressing, show "Slowly…" and cap strain gain. This is better for the sensor and for 2.4.2 optics.

### D. Edge-case table

| Case | Detection | Behaviour |
|---|---|---|
| Launch closed (outer) | compact width, status `.closed` | Trophy shelf, object picker, "Open to press" loop; queue the object |
| Launch/arm half-folded | θ < 165 at arm | θ0 = current angle; if θ0 < 100, offer "open more" but allow a short press |
| Opens while Sealed result pending | first inner layout after Sealed | Revealing animation (event-based, not angle-based) |
| Reopen mid-press | θ rising in Pressing | Ram lifts; elastic rebound; damage stays; can re-press (pump) |
| User pauses mid-press | no hinge events | Hold the exact state; no drift, no timeout |
| Inner display turns off before depth 1 | displayRole → outer with depth ≥ 0.6 | Auto-complete to Sealed (fast-forward the remaining crush off-screen); result card on outer |
| Same, but depth < 0.6 | displayRole → outer, depth < 0.6 | "Partial press" card: "Press interrupted at 40%". Resume from that damage on reopen |
| Very fast slam | fV beyond threshold, or jump of >40° between samples | Treat as a press with a "Slam!" badge and no extra reward; gentle copy about going slowly |
| Tent pose | partial angle + fold-on-top orientation (heuristic) | Paused, "Lay it flat to press" |
| Book pose (vertical fold) | division frame taller than wide | Vice mode (jaws left/right); mode locked during a press |
| Rotation mid-press | trait change | Keep mode and state; relayout only |
| Split View | width < ~600 pt on inner | Scaled press, or prompt to go full screen; hinge still works |
| Interruption / background | scenePhase ≠ active | Paused; persist the model |
| Hinge nil (non-Duo or detached) | `hinge == nil` | Fallback Pinch Press; same engine |
| Reduce Motion | accessibility setting | Shorter reveal, no camera shake; same mechanics |
| Thermal / low update rate | sample interval > 100 ms | Increase the spring's smoothing; disable prediction |
| Launch with a stale hinge event | <1.5 s since activation | Ignore input (Crate pattern) |

### E. Platform and distribution recommendation
- **Ship a universal iPhone app.** Make the Duo the headline experience and keep Pinch Press on other iPhones as a fully playable mode. Don't set restrictive `UIRequiredDeviceCapabilities` keys. They can't be relaxed sensibly later, no hinge key exists, and Apple discourages exclusivity.
- **Pricing [G]:** one paid price everywhere, so you don't have to explain why non-Duo users paid less. The Duo's ~£2k installed base will be small at first, and the touch version widens the market. Lead the marketing with Duo video.
- **Positioning [G]:**
  - Submit Duo screenshots now (outer 1398×2034, inner 2007×2853).
  - Nominate for featuring around launch week.
  - Submit to FoldHunt with a "Simulator verified", then on-device, tier.
  - Pitch the "Made for iPhone Duo" roundups.
- **Build with the iOS 27.1 SDK / Xcode 27.1** for full edge-to-edge and the hinge APIs, gated with `#available(iOS 27.1, *)`.

---

## Risks and open questions (validate on device first)

1. **[Unverified, critical] The real angle at which the inner display turns off when closing.** Simulator reports range from 20° to 55°, and the transition is path-dependent. The mapping's 60° end point depends on this.
2. **[Unverified] Whether hinge updates continue after the app moves to the outer display** (needed for "finish the crush blind" and for detecting reopen early).
3. **[Unverified] Real-device update rate and latency.** The only figure is ~30 Hz in the simulator. Prediction/spring tuning is a guess until then.
4. **[Reported] Opening hysteresis** (still `.closed` until ~150°). If it holds on hardware, the reveal can't be gradual.
5. **[Unverified] Taptic Engine strength and location on the Duo,** and whether haptics feel different when folded.
6. **[Unverified] The system close animation** (blur/translucent) duration, and whether the app can draw anything during it.
7. **[Unverified] App Review stance** on mechanics that encourage repeated folding. Mitigate with "slowly" copy and no rapid-pump rewards.
8. **[Unverified] Whether any featuring programme exists** beyond standard nominations.
9. **[Guess] Tent-pose detection heuristic,** and whether the status already flips to something useful in tent.
10. **[Risk] Hardware access.** Stock is tight, at £1,999. Budget for one device or a workshop slot before submission.
11. **[Risk] Copycats.** Hinge-toy apps are proliferating (accordions, catapults, toasters). A press is obvious enough that someone else may ship one. Speed matters, and so does depth of content.
12. **[Risk] Physical-object confusion.** "Place an object" must clearly mean a *virtual* object in all copy and in App Store screenshots.

Search note: the agents' shared web-search quota for this session ran out near the end of this research. Android API details in §3.7 come from prior knowledge and were not re-fetched. Some planned follow-up searches were not run: Verge/MKBHD full reviews, real-device hinge latency, and FoldFling/Hingami developer pages.

---

## Sources

**Apple (primary)**
- [onHingeChange(isEnabled:_:)](https://developer.apple.com/documentation/swiftui/view/onhingechange(isenabled:_:))
- [DeviceHinge](https://developer.apple.com/documentation/swiftui/devicehinge) · [DeviceHinge.Status](https://developer.apple.com/documentation/swiftui/devicehinge/status-swift.struct) · [DeviceHingeContext](https://developer.apple.com/documentation/swiftui/devicehingecontext)
- [UIHingeInteraction](https://developer.apple.com/documentation/uikit/uihingeinteraction) · [UIHinge](https://developer.apple.com/documentation/uikit/uihinge)
- [Developer Forums: iPhone Duo Group Lab summary (thread 847644)](https://developer.apple.com/forums/thread/847644)
- [Tech Talk 111461: Prepare your app for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111461/)
- [Tech Talk 111464: Leverage multiple displays and scenes](https://developer.apple.com/videos/play/tech-talks/111464/)
- [Tech Talk 111463: Strike a pose with adaptive layouts](https://developer.apple.com/videos/play/tech-talks/111463/)
- [Tech Talk 111466: Design for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111466/)
- [HIG: Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)
- [Preparing your app for iPhone Duo](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Apple newsroom: Apple unveils iPhone Duo](https://www.apple.com/in/newsroom/2026/09/apple-unveils-iphone-duo/)

**Code and tools**
- [Accorduon](https://github.com/artemnovichkov/Accorduon) · [iPhone-Duo-by-Examples](https://github.com/artemnovichkov/iPhone-Duo-by-Examples) · [Duogami](https://github.com/artemnovichkov/Duogami) · [DuoBird](https://github.com/artemnovichkov/DuoBird) · [SandValley](https://github.com/artemnovichkov/SandValley)
- [Crate (crate-duo)](https://github.com/odoisveryverygood/crate-duo) · [Crate on Devpost](https://devpost.com/software/crate-iphone-duo-mpc)
- [hinge CLI](https://github.com/artemnovichkov/hinge) · [duo-fold-control](https://github.com/tosbaha/duo-fold-control) · [foldctl](https://github.com/tatsuz0u/foldctl) · [iphone-duo-simulator-skill / SKILL.md](https://github.com/WhitenWhiten/iphone-duo-simulator-skill) · [Appium WDA PR #1287](https://github.com/appium/WebDriverAgent/pull/1287)
- [react-native-arrangement-view issue #27 (30 Hz measurement)](https://github.com/thiagobrez/react-native-arrangement-view/issues/27) · [Expo Hinge docs](https://docs.expo.dev/versions/latest/sdk/hinge/)

**Developer write-ups**
- [dev.to: iPhone Duo for iOS developers](https://dev.to/arshtechpro/iphone-duo-for-ios-developers-what-actually-changes-in-your-swift-code-5gc5)
- [Blake Crosley: iPhone Duo for developers](https://blakecrosley.com/blog/iphone-duo-for-developers)
- [Group Lab consolidated Q&A (gist)](https://gist.github.com/frankschlegel/6356a059426b2393528691822edfdae6) · [Group Lab 2 Q&A (Anton Gubarenko)](https://antongubarenko.substack.com/p/iphone-duo-group-lab-2-q-and-a)
- [BleepingSwift: onHingeChange](https://bleepingswift.com/blog/onhingechange-hinge-angle-swiftui) · [Nil Coalescing: hinge slider](https://nilcoalescing.com/blog/AdjustingTheHingeAngleInTheIPhoneDuoSimulator/) · [SwiftLee: iPhone Duo simulator](https://www.avanderlee.com/swiftui/iphone-duo-simulator/)
- [FoldHunt directory](https://foldhunt.com/iphone-duo/) · [FoldHunt fold guide](https://foldhunt.com/guides/iphone-duo-fold/) · [Sarunw: Tech Talks guide](https://sarunw.com/posts/iphone-duo-tech-talks/)

**Reviews and news**
- [9to5Mac review](https://9to5mac.com/2026/10/21/iphone-duo-review/) · [9to5Mac: Federighi on developers](https://9to5mac.com/2026/09/29/craig-federighi-on-how-apple-helps-developers-make-the-most-of-the-iphone-duo-video/) · [MacDailyNews: Federighi](https://macdailynews.com/2026/09/29/iphone-duo-was-designed-as-a-window-not-a-folded-iphone-craig-federighi-says/)
- [MacStories review roundup](https://www.macstories.net/roundups/iphone-duo-review-roundup-great-hinge-messy-apps-and-everybody-misses-face-id/) · [Gizmodo review](https://gizmodo.com/iphone-duo-review-2000827502) · [Notebookcheck review roundup](https://www.notebookcheck.net/Apple-iPhone-Duo-reviews-are-in-Plenty-of-criticism-but-positive-hinge-stress-test.1430224.0.html)
- [Cult of Mac: 32,000-fold test](https://www.cultofmac.com/news/hingey-iphone-duo-hinge-fold-test) · [Foldify: unpublished durability](https://www.foldifycase.com/blogs/news/iphone-duo-hinge-durability-what-apple-did-not-publish-2026)
- [MacObserver: displays explained](https://www.macobserver.com/tips/round-ups/iphone-duo-displays-explained-7-6-inch-inner-5-4-inch-outer-120hz-3000-nits/)
- [StudentBeans: UK price](https://www.studentbeans.com/blog/uk/uk-iphone-duo-launch) · [Gadget Scout: delivery slips](https://www.gadgetscout.co.uk/articles/apple-s-1-999-iphone-duo-delivery-estimates-slip-into-2027.html)
- [MacRumors: Duo submissions open](https://www.macrumors.com/2026/10/05/apple-opens-iphone-duo-app-submissions/) · [Notebookcheck: Made for iPhone Duo apps](https://www.notebookcheck.net/Made-for-iPhone-Duo-These-apps-show-what-Apple-s-foldable-can-do.1416967.0.html) · [Digital Trends: developer creations](https://www.digitaltrends.com/phones/the-iphone-duo-has-developers-going-wild-and-im-loving-their-creations/) · [Axios: Walkman app](https://www.axios.com/2026/10/05/apple-iphone-duo-foldable-walkman-app)

**Android (from prior knowledge, not re-fetched)**
- [Jetpack WindowManager FoldingFeature](https://developer.android.com/reference/androidx/window/layout/FoldingFeature) · [Sensor.TYPE_HINGE_ANGLE](https://developer.android.com/reference/android/hardware/Sensor#TYPE_HINGE_ANGLE)
