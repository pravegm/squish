# Apple's iPhone Duo guidance, and how Squish measures up

*Platform research, 24 Oct 2026. The founder asked to "read up Apple's official developer documentation for the Duo to learn how to make Duo optimized apps." This is what Apple publishes (Part 1), where Squish stands against it (Part 2), and the ten changes that would make Squish most Duo-native by Apple's own standards (Part 3).*

**How this was gathered.** I read Apple's pages directly: the DocC JSON behind developer.apple.com/documentation and the HIG, the six iPhone Duo Tech Talk transcripts and code, the WWDC26 "Modernize your UIKit app" transcript, the developer.apple.com/iphone-duo hub and its Prepare page, App Store Connect Help, the App Review Guidelines, the Xcode 27.1 and iOS 27.2 RC release notes, Apple Support's iPhone User Guide, the iPhone Duo tech specs, and two Apple Newsroom posts. Forum answers are cited only when an Apple engineer or evangelist wrote them, or when they come from the Group Lab highlights thread that developer.apple.com/iphone-duo links to.

**Tags used**
- **[Doc]**: Apple documentation, HIG or Help page.
- **[Talk]**: Apple Tech Talk or WWDC transcript.
- **[Apple Q&A]**: an Apple staff answer in the Developer Forums or Apple's Group Lab highlights.
- **[Not found]**: I looked and Apple publishes nothing official on it.
- **[Inference]**: my reading, not Apple's words.

Squish file references are `path:line` at commit `0dd5ec2`.

---

## Part 1: What Apple officially says

### 1.1 The device and its poses

- **Poses, in Apple's words** [Doc] ([Pose iPhone Duo](https://support.apple.com/en-au/guide/iphone/iphv3p93k1bm/ios)). Apple names three partially folded poses:
  - **book:** "the inner display faces you in landscape";
  - **tent:** "the outer display faces you in landscape";
  - **seated position:** "the inner display faces you in portrait".

  Squish's "tabletop" is Apple's **seated** pose. The HIG says the same thing more briefly: people hold the device "partially folded like a book, placed down on a surface, or standing on its edges" ([HIG](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)).
- **Displays** [Doc] ([tech specs](https://www.apple.com/iphone-duo/specs/)):

  | Display | Size | Pixels | Density |
  |---|---|---|---|
  | Inner | 7.6" | 1878 × 2670 | 430 ppi |
  | Outer | 5.4" | 1398 × 2034 | 460 ppi |

  Both have ProMotion up to 120 Hz, Always-On and "Dynamic Island", which the specs list under "Both displays".
- **Points** [Inference from [Doc]]. The App Store screenshot sizes imply canvases at @3x:
  - inner 2007 × 2853 px, so **669 × 951 pt**;
  - outer 1398 × 2034 px, so **466 × 678 pt**.

  Spreading 669 pt across the panel's 1878 px at 430 ppi (110.9 mm) gives **6.03 pt/mm**. That matches `FoldMetrics.pointsPerMM = 6.02` (`Squish/Scene/Fold/FoldGeometry.swift:17`). Apple adds that "actual viewable area is less" because of the rounded corners.
- **Aspect ratios** [Doc] ([Newsroom, Oct 2026](https://www.apple.com/newsroom/2026/10/developers-bring-incredible-new-app-experiences-to-iphone-duo/)): "both displays share the same aspect ratio, apps transition smoothly… and scale proportionally."

### 1.2 The hinge API

**SwiftUI** [Doc]. All of these are iOS 27.1+.
- [`onHingeChange(isEnabled:_:)`](https://developer.apple.com/documentation/swiftui/view/onhingechange(isenabled:_:)):
  ```swift
  nonisolated func onHingeChange(isEnabled: Bool = true,
      _ action: @escaping (DeviceHingeContext, DeviceHingeContext) -> Void) -> some View
  ```
- [`DeviceHingeContext.hinge`](https://developer.apple.com/documentation/swiftui/devicehingecontext/hinge): `var hinge: DeviceHinge?`
- [`DeviceHinge`](https://developer.apple.com/documentation/swiftui/devicehinge):
  - `var angle: Angle`
  - `var status: DeviceHinge.Status`
  - The status is "determined by the system based on the current angle and device orientation".
- [`DeviceHinge.Status`](https://developer.apple.com/documentation/swiftui/devicehinge/status-swift.struct):
  - It is a **struct** with `.closed`, `.partiallyOpen` and `.fullyOpen` ("open as far as the device allows").
  - Because it is a struct, a `switch` over it needs a `default:` case.

**UIKit** [Doc].
- [`UIHingeInteraction`](https://developer.apple.com/documentation/uikit/uihingeinteraction):
  - It is `@MainActor`, created with `init(updateHandler:)`.
  - Its handler runs "when the hinge state changes, or when the interaction moves between hierarchies".
  - When it moves out of a hierarchy that provides hinge updates, "the update's `hinge` is nil".
- [`UIHinge.angle`](https://developer.apple.com/documentation/uikit/uihinge/angle) is `CGFloat` **in radians**.
- [`UIHinge.Status`](https://developer.apple.com/documentation/uikit/uihinge/status-swift.enum) is an enum that also has `.unknown`.
- [`isEnabled`](https://developer.apple.com/documentation/uikit/uihingeinteraction/isenabled): while disabled, "updates that occur are not queued". On re-enable, the handler gets the current state.

**Rate and precision** [Doc] ([UIHinge.angle](https://developer.apple.com/documentation/uikit/uihinge/angle)):
> "The rate and granularity of angle updates are system policy and can change based on system state, so don't depend on a particular update frequency or precision. If you only need to know whether the hinge is closed, partially open, or fully open, prefer `status` over the angle."

The Group Lab highlights repeat this [Apple Q&A]. **No figure for Hz, latency or degrees of accuracy is published anywhere official** [Not found]. The "~5°" figure comes from press coverage of Federighi, not from documentation.

**What it is for** [Talk] ([Leverage multiple displays and scenes, 111464](https://developer.apple.com/videos/play/tech-talks/111464/)):
- "Hinge data is observed live, and is ideal for driving interactions or effects. For layout, use the arrangement and region APIs."
- The closing line: "use the Hinge API to build impressive interactions and effects."

**Apple's own sample pattern** (the guitar whammy bar, 111464):
- It treats a nil hinge as "the device doesn't have one".
- It reads the angle only while `hinge.status == .partiallyOpen`.
- It resets the effect in the `else` branch.

**Sample code.** I found no Apple sample-code project for iPhone Duo [Not found]. The Tech Talk code snippets (111463, 111464) are the only official code.

### 1.3 Posture detection

- **There is no pose API** [Apple Q&A] ([Group Lab highlights, thread 847644](https://developer.apple.com/forums/thread/847644)): "There's no single system-provided pose value." Combine:
  - the discrete status;
  - the angle;
  - orientation;
  - size class.
- **There is no "is this a Duo" API** [Apple Q&A] ([thread 847775](https://developer.apple.com/forums/thread/847775), Apple Technology Evangelist):
  - "There is no API to detect whether your app is running on iPhone Duo."
  - The recommendation is "to not introduce behavior that is specific to the device".
- **CoreMotion is display-relative on iOS 27** [Doc] ([`deviceMotionBody`](https://developer.apple.com/documentation/coremotion/cmmotionmanager/devicemotionbody), [`CMBodyIdentifiable`](https://developer.apple.com/documentation/coremotion/cmbodyidentifiable)):
  - `var deviceMotionBody: (any CMBodyIdentifiable)?`, and `UIView` conforms.
  - Attitude, rotation rate, gravity and user acceleration are then transformed "to match the current orientation of that view".
  - "On iPhone Duo, setting this property also identifies which display your app occupies… and detect which face is up."
  - [Talk] WWDC26 278: "UIView also conforms to the new Body protocols from CoreMotion and CoreLocation."
  - [Apple Q&A]: the values are body-corrected "whenever your app is full screen on the display hosting your UI".
- **Whether gravity is reported for a particular half of the inner display** (the anvil half or the platen half) is **not documented** [Not found]. FOLD-PRESS §9.8 check 4 ("which half holds the IMU") still needs a device test.

### 1.4 Reserved regions: the fold, the cameras, the Dynamic Island

Signatures [Doc]:
```swift
// SwiftUI, on GeometryProxy (iOS 27.1+)
func reservedRegions(kind: ReservedRegion.Kind, options: ReservedRegion.QueryOptions = [],
                     layoutDirectionBehavior: LayoutDirectionBehavior = .mirrors) -> [ReservedRegion]
// UIKit, on UIView
func reservedRegions(kind: UIView.ReservedRegion.Kind,
                     options: UIView.ReservedRegion.QueryOptions = []) -> [UIView.ReservedRegion]
```
Sources: [ReservedRegion](https://developer.apple.com/documentation/swiftui/reservedregion), [GeometryProxy.reservedRegions](https://developer.apple.com/documentation/swiftui/geometryproxy/reservedregions(kind:options:layoutdirectionbehavior:)), [UIView.ReservedRegion](https://developer.apple.com/documentation/uikit/uiview/reservedregion).

**The two kinds**
- `.division`: "an area… that splits your view. Place your content on both sides of the region instead of across it."
- `.occlusion`: "the Dynamic Island, a camera, or window controls". "Place important views and controls outside this area."
  - The inner camera is active only while in use.
  - "The outer camera is always active."
  - The outer camera region "expands into the Dynamic Island for Live Activities" ([HIG](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)).

**Frame and margins**
- `frame` is in the view's own coordinates.
- It "already includes the region's margins", the extra space "that keeps interactive content clear of it".

**Active and inactive**
- A division "is active only when the device is partially open or closed".
- Fully open, the default query "returns no division regions".
- With `.includeInactive`, "An inactive region still has a frame, so you can leave room for it. This keeps your layout from jumping."
- [Talk] (111463) adds: "When flat, it's inactive and has a width of zero."

**Change tracking.** UIKit "tracks the regions you read in `updateConstraints()` and runs it again when the regions change".

**Design rules** [Doc, Talk]:
- "keep each view entirely on one side of the division";
- "move only what's necessary… favor small adjustments over rearrangement";
- for grids, "use an even number of columns";
- continuous scrolling content "don't displace".

**Placement by pose** [Talk] (111463, 111466):
- **Book:** alerts go to the trailing side, "closer to where they'll appear as the device closes".
- **Seated:** "The top region works well for content that benefits from visibility at a distance… The bottom region works well for interactive controls."
- 111466: a seated-specific layout is optional, but "be sure it has all the same controls and general hierarchy as other poses. You don't want to tie functionality to a specific pose."

**Built-in fold avoidance** [Talk] (111466). "nudges interactive elements aside whenever iPhone Duo is partially folded". It covers sheets, alerts, menus and toolbar buttons. "Scrollable content doesn't need to avoid this region."

**Arrangement views** (`ArrangementView`, `UIArrangementViewController`, split or overlay) are Apple's container for two related panes [Doc, Talk]. They are a poor fit for Squish's custom two-plate stage, and Apple says to keep them out of navigation and scroll containers.

### 1.5 Scenes, windows and continuity when folding

- **Folding resizes the app; it does not relaunch it** [Apple Q&A] (847644):
  - "Treat display transitions as size-class and trait changes, not a scene disconnect or app termination; your process stays alive."
  - "Apps adapt in place as the device opens and closes rather than backgrounding."
- **Scene phase** [Apple Q&A] ([thread 847838](https://developer.apple.com/forums/thread/847838), Apple DTS):
  - Full screen on the inner display, "the scene is unaffected by the hinge state change—the system scales and adjusts your window scene."
  - With two windows, the secondary scene goes inactive, then into the background, when the device closes.
- **State preservation** [Apple Q&A] (847644):
  - Text input, scroll position and video position are preserved automatically.
  - For a true disconnect, implement `stateRestorationActivity(for:)`.
  - "Both UserDefaults and AppStorage are app-wide, not per-window, stores."
  - Multiple scenes are "not required universally".
- **Size classes** [Talk] ([Prepare your app, 111461](https://developer.apple.com/videos/play/tech-talks/111461/)):

  | Display | Orientation | Horizontal | Vertical |
  |---|---|---|---|
  | Outer | portrait | compact | regular |
  | Outer | landscape | compact | compact |
  | Inner | any | regular | regular |

  The HIG: "A compact width layout for the outer display and a regular width layout for the inner display give you the fundamentals for every pose."
- **Orientation** [Talk] (111461):
  - "The inner display doesn't honor your supported interface orientations."
  - The outer display behaves like any iPhone.
  - [Doc] ([Prepare page](https://developer.apple.com/iphone-duo/prepare/)) lists properties to stop using for layout, including `windowScene.effectiveGeometry.interfaceOrientation`. To decide whether you are wider than tall, "compare the width and height of the space you have."
- **`UIRequiresFullScreen`**:
  - [Talk] (111461): "iPhone Duo will continue to honor the UIRequiresFullScreen key, but your app will still resize when someone opens or closes."
  - [Talk] (WWDC26 278, [Modernize your UIKit app](https://developer.apple.com/videos/play/wwdc2026/278/)): it now "enables discrete resizing that honors your supported interface orientations".
  - [Apple Q&A] (847644): "As soon as possible, you should remove UIRequiresFullScreen and adopt size-class-driven resizing."
- **Required lifecycle and screen APIs** [Doc, Talk]:
  - "Starting in iOS 27, apps built with the latest SDK must use the scene-based life cycle or they fail to launch" ([Updates](https://developer.apple.com/documentation/updates)).
  - `UIScreen.main` is "ambiguous and will be deprecated".
  - Use the window scene's screen, `traitCollection.displayScale`, or view/scene bounds.
  - Re-read sizes in `layoutSubviews` and similar, because "a fold can resize your app in the middle of a session" ([Prepare page](https://developer.apple.com/iphone-duo/prepare/)).
  - "Remove checks for specific device sizes."
- **Multitasking** [Talk] (111464):
  - "All apps participate in multitasking on iPhone Duo."
  - New windows can be created only on the inner display.

### 1.6 The outer display while open: scene accessories, Live Activities, PiP

- **Scene accessories are the only route** [Apple Q&A] (847644). Non-camera apps can show content on the outer display while unfolded "only via the system-controlled scene accessory mechanism — not by drawing on the outer display directly."
- **The API** [Doc]: [`sceneAccessory(content:)`](https://developer.apple.com/documentation/swiftui/view/sceneaccessory(content:)) (iOS 27). "the system decides when and where to present it… the app must remain fully functional without them."
- **Only two accessory types exist** [Doc]:
  - [`CameraCaptureAccessory`](https://developer.apple.com/documentation/swiftui/cameracaptureaccessory) (iOS 27.1). It may be presented "while the app is in the foreground and has an active camera capture session". [Talk]: "available when your app is full screen on the inner display, and your app has an active camera session."
  - [`ExternalNonInteractiveAccessory`](https://developer.apple.com/documentation/swiftui/externalnoninteractiveaccessory). Only for "an external display" or AirPlay.
- **Availability** [Apple Q&A]:
  - In tent pose, the outer display is available "for apps displaying camera previews or apps adopting AlarmKit".
  - Accessory content "can be withdrawn at any time".
- **PiP** [Apple Q&A]: it moves to the outer display "only when the device is closed and the system controls its transition".
- **Live Activities** [Apple Q&A]: every Live Activity must implement all Dynamic Island presentations plus the Lock Screen.
- **Audio** [Apple Q&A]: audio can't be pinned to the outer screen. Playback is "associated with the most recent app which began the playback session".
- **Simulator caveat** [Doc] ([Xcode 27.1 notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27_1-release-notes)): "In the iPhone Duo simulator, an app using `CameraCaptureAccessory` can use both displays at the same time without an active camera capture session." On device it can't.

**For Squish** [Inference]: there is no sanctioned way to draw on the cover while the phone is open. Squish has no camera session and no external display. Any "both displays at once" moment would be fiction in a store frame.

### 1.7 HIG layout guidance

All of this is [Doc], from the [HIG: Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo) unless marked.

- **Consistency across displays and poses:**
  - "Create a consistent experience across displays. Keep functionality and the state of elements the same between displays."
  - "Provide access to the same controls and content regardless of how someone holds or views the device."
- **Games:**
  - "Make your game playable in every device pose." You may lock orientation, "but be sure to fill the screen as the device pose changes".
  - "keep text and control sizes as consistent as possible."
  - "Prefer changing the aspect ratio over letterboxing or pillarboxing… add artwork to the padding area."
- **Full width:** "Consider using the full display width for interfaces where bars aren't necessary… as long as nothing conflicts with the Dynamic Island or the status bar."
- **Insets and margins:** "Account for asymmetry in your layouts." [Talk] (111461) adds: "avoid assuming that insets on opposite sides are equal."
- **Folding:** "Avoid extreme layout changes as people fold the device."
- **Corners** [Talk] (111461): match the screen corners with `ConcentricRectangle` (SwiftUI) or `UICornerConfiguration` (UIKit), "updated to work with the screen shapes on iPhone Duo".

### 1.8 Display-off angle, sleep, haptics and audio

- **Display-off angle and the inner/outer hand-off angle**: **[Not found].**
  - Apple publishes no angle at which the inner display turns off or the app moves to the outer display.
  - Nothing official says whether hinge events keep arriving while the app is on the outer display.
  - The only related facts:
    - both displays are Always-On [Doc];
    - StandBy runs in a partially open pose, and you "can choose which positions turn on StandBy" ([What's new with iPhone Duo](https://support.apple.com/en-gb/guide/iphone/iphge85m9f19/ios));
    - "StandBy is unavailable in the iPhone Duo Simulator runtime" [Doc].
- **Idle timer and auto-lock during hinge-only interaction**: **[Not found].**
- **Haptics on the Duo**: **[Not found]**, beyond the general [HIG Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics):
  - "Make haptics optional."
  - "Avoid overusing haptics."
  - "Ensure that haptic vibrations don't disrupt experiences involving device features like the camera, gyroscope, or microphone."
- **Audio on the Duo**: **[Not found]**, beyond the general [HIG Playing audio](https://developer.apple.com/design/human-interface-guidelines/playing-audio):
  - On silent, people "want to silence nonessential sounds, such as… sound effects, game soundtracks". The device "plays only the audio that people explicitly initiate".
  - The category table describes `.playback` as "Sound is essential" and says it "doesn't respond to the silence switch".

### 1.9 Testing

- **Device Hub, the only official hinge control** [Doc] ([Interacting with your app in Device Hub](https://developer.apple.com/documentation/xcode/interacting-with-your-app-in-device-hub)):
  - Buttons for Closed, Partially Open and Open.
  - "To fold the device to any angle, hold the Option key while dragging the slider that appears below the bezel."
- **No command-line hinge control**:
  - Apple documents none ([devicectl page](https://developer.apple.com/documentation/xcode/interacting-with-devices-using-the-command-line)) [Not found].
  - The forum request for one ([thread 847883](https://developer.apple.com/forums/thread/847883)) has no Apple answer.
  - Squish's CI uses the community `hinge` CLI, which works through a private interface.
- **Known simulator issues** [Doc] (Xcode 27.1 notes):
  - first launch "can take several minutes";
  - StandBy is unavailable;
  - most app extensions can't run;
  - the `CameraCaptureAccessory` caveat in §1.6.

  Xcode 27.1 Previews also gained "a Display group for previewing content on a device's alternative display".
- **Apple's advice** [Apple Q&A, Doc]:
  - "Always validate button targets, vertical bar positioning, and navigation flows on physical iPhone Duo devices."
  - "The iPhone Duo simulator is the best way to test the full native experience" ([Prepare page](https://developer.apple.com/iphone-duo/prepare/)).
  - The Xcode skill **App Resizability** ("get my app ready for iPhone Duo"; export it with `xcrun agent skills export`).

### 1.10 App Store: screenshots, previews, the badge, featuring, review

- **Screenshots** [Doc] ([Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)):

  | Display | Portrait | Landscape |
  |---|---|---|
  | Outer | 1398 × 2034 px | 2034 × 1398 px |
  | Inner | 2007 × 2853 px | 2853 × 2007 px |

- **When they become required.** The two official pages word it differently:
  - spec page: "Starting in April 2027, screenshots will be required for any app using the iOS 27.1 SDK or later."
  - [developer news, 5 Oct 2026](https://developer.apple.com/news/?id=kkphp5qo): "Starting April 2027, any apps or games submitted will need to include screenshots for iPhone Duo."
- **The badge** [Doc]:
  - "When you submit iPhone Duo screenshots in App Store Connect, your App Store product page will display a badge to let people know your app is optimized for iPhone Duo."
  - The Newsroom calls it the **"Made for iPhone Duo badge"**.
  - The "Designed for iPhone Duo" wording in the brief doesn't appear in Apple's material [Not found].
  - Screenshots are the only published trigger.
- **App previews** [Doc] ([App preview specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications)):
  - The Duo row lists the device resolutions with accepted uploads of **886 × 1920 / 1920 × 886**. That is the same as the 6.9" class, and the row is labelled "(19.5:9 aspect ratio)", which looks copied from the row above.
  - The usual rules apply: 15–30 s, ≤ 30 fps.
  - **Treat the Duo size as published but suspicious. Verify it in App Store Connect's uploader.**
  - App Store Connect has "the new preview tool… to see how your assets… look on iPhone Duo."
- **Featuring** [Doc]:
  - [Prepare page](https://developer.apple.com/iphone-duo/prepare/): "Submit a featuring nomination… In the Helpful Details section, you can specify that your app is optimized for iPhone Duo, including support for all device poses."
  - [Nomination help](https://developer.apple.com/help/app-store-connect/manage-featuring-nominations/nominate-your-app-for-featuring/): "a minimum lead time of 3 weeks".
  - The Newsroom announced "New editorial collections for iPhone Duo apps and games". It named one toy in the Squish genre: "Independent developers are also finding playful ways to make the fold part of the fun. Deck-Man…"
- **App Review** [Doc] ([guidelines](https://developer.apple.com/app-store/review/guidelines/)). **No guideline mentions the Duo, the fold or the hinge.** The relevant ones:
  - **2.4.2:** apps must be "used in a way that does not risk damage to the device", and must not "generate excessive heat".
  - **1.4.5:** apps must not urge people to "use their devices in a way that risks physical harm".
  - **2.3.3 / 2.3.4:** screenshots show "the app in use", and previews "may only use video screen captures of the app itself" (overlays allowed).
  - **2.5.9:** don't "alter or disable the functions of standard switches".
  - [Apple Q&A]: "iPhone Duo apps don't need to require specific device capabilities."

### 1.11 WWDC 2026 and fall 2026 sessions

- **There was no WWDC26 session on the Duo.** The device was announced in September, and the HIG page dates from 9 Sep 2026.
- The relevant WWDC26 session is **[Modernize your UIKit app (278)](https://developer.apple.com/videos/play/wwdc2026/278/)**. It covers:
  - the scene lifecycle requirement;
  - no `UIScreen.main`;
  - no idiom or orientation checks;
  - `UIRequiresFullScreen` as discrete resizing;
  - Body protocols for CoreMotion.
- [Get the most out of Device Hub (260)](https://developer.apple.com/videos/play/wwdc2026/260/) exists. I didn't read it.
- **Fall 2026 Duo material**, all on the [iPhone Duo hub](https://developer.apple.com/iphone-duo/):
  - Tech Talks:
    - [111466](https://developer.apple.com/videos/play/tech-talks/111466/) *Design for iPhone Duo*;
    - [111461](https://developer.apple.com/videos/play/tech-talks/111461/) *Prepare your app*;
    - [111462](https://developer.apple.com/videos/play/tech-talks/111462/) *Raise the bar* (vertical bars);
    - [111463](https://developer.apple.com/videos/play/tech-talks/111463/) *Strike a pose*;
    - [111464](https://developer.apple.com/videos/play/tech-talks/111464/) *Leverage multiple displays and scenes*;
    - [111465](https://developer.apple.com/videos/play/tech-talks/111465/) *Build a great camera experience*.
  - Three one-hour Group Labs (Meet with Apple 285–287). They have no published transcripts, so the highlights thread (847644) stands in for them.

### 1.12 Not confirmable from official sources

- The inner display-off angle.
- The reopen hysteresis.
- Whether hinge samples arrive on the outer display.
- The hinge update rate, latency and accuracy.
- Taptic Engine behaviour on the Duo.
- Auto-lock during hinge-only use.
- Which half of the inner display the motion sensors report for.
- A programmatic simulator hinge.
- Any eligibility rule for the badge beyond submitting Duo screenshots.
- The correct Duo app-preview upload size.
- Whether `UIRequiresFullScreen` keeps an app out of Split View on the Duo.
- Whether the inner display's Dynamic Island shows over a full-screen app with the status bar hidden.

---

## Part 2: Gap analysis, Squish against Apple's guidance

**Files read:**
- `Squish/App/HingeReader.swift`
- `Squish/App/PressDirector.swift` (`hingeUpdate` and its surroundings)
- `Squish/Scene/Fold/*` (Geometry, PressView, PressController, RenderGate)
- `Squish/UI/RootView.swift`
- `Squish/UI/CoverView.swift`
- `Squish/UI/Theme.swift` (`ScreenBands`, `CreaseSafe`)
- `Squish/Core/PressEngine.swift`
- the audio settings
- `project.yml`

**Status codes:** ✅ compliant · ❌ not compliant · ⚠️ partly compliant, or a risk · ❓ unknown (needs a device or isn't documented).

### 2.1 Hinge input

**H1. Use `onHingeChange` / `UIHingeInteraction` (§1.2).** ✅
- **Where:** `HingeReader.swift:11`, behind `#available(iOS 27.1, *)`.
- **Fix:** None.

**H2. A nil `hinge` means no hinge *or* that the view left a hierarchy that provides updates (§1.2).** ⚠️
- **Where:**
  - `HingeReader.swift:14-16` calls `onUnavailable()` on any nil.
  - That reaches `PressDirector.hingeUnavailable()` at `PressDirector.swift:277`, which clears `hingeAvailable`.
  - As a result, `usesFoldPress` (`:86`) goes false and `RootView.swift:204-208` tears down `FoldPressView` and shows the P-48.
- **Risk:** One transient nil during a display hand-off would flip a Duo into the touch machine mid-session.
- **Fix:**
  - Latch "hinge seen" for the life of the process.
  - After that, treat a nil as *paused* (hold state, no teardown) unless it lasts more than ~2 s *and* no `.division` region exists (see L1).
  - Keep `hingeUnavailable()` for the "never reported" case.

**H3. Use `status` for discrete states, and remember it is orientation-aware (§1.2).** ⚠️
- **Where:**
  - Only `status == .closed` is passed on (`HingeReader.swift:13`).
  - `.fullyOpen` and `.partiallyOpen` are dropped.
  - Arming and re-arming use angles only (`PressEngine.swift:379`, `:589`).
- **Fix:**
  - Pass the status through as a small enum, with `default:` for the struct.
  - Use `.fullyOpen` as the "flat" signal for re-arm and the idle sheen invite.
  - Keep the empirical "closed above 90° is stale" rule (`PressEngine.swift:332-335`), since status is the system's judgement and lags.

**H4. Don't depend on update rate or precision (§1.2).** ✅
- **Where:**
  - The One-Euro filter and spring.
  - A low-rate mode that stops predicting below ~10 Hz (`PressEngine.swift:493`).
  - A blind clock while shut (`FoldRenderGate.swift:73-82`).
- **Fix:** None. Keep the hinge log in the Tuning Lab for real device rates.

**H5. `isEnabled` drops updates instead of queueing them (§1.2).** ✅
- **Where:** Never disabled, which is right for a press and the reveal gate.
- **Fix:** If it is ever added (for example while the Shelf is open), re-read the state on re-enable. Never disable it during `.armed`, `.pressing` or a reveal.

**H6. Hinge for effects; regions and size for layout (§1.2).** ✅
- **Where:**
  - The layout comes from the canvas size (`FoldGeometry.swift:85-92`).
  - The hinge only drives the press, sheen, light and book eye (`FoldPressController.swift:501-511`).
- **Fix:** None.

### 2.2 Layout around the fold, cameras and Dynamic Island

**L1. Read the fold from `reservedRegions(kind: .division, options: .includeInactive)` (§1.4).** ❌
- **Where:**
  - No `reservedRegions` call exists anywhere in `Squish/`.
  - The crease is a hard-coded 40 pt band centred on the canvas: `FoldMetrics.creaseBand` (`FoldGeometry.swift:18-19`) and `ScreenBands.creaseHalf` (`Theme.swift:190-191`).
  - `FoldLayout(canvas:foldLine:)` (`FoldGeometry.swift:85`) already accepts a fold line, but every caller passes the canvas only (`FoldPressView.swift:243`, `Theme.swift:214`).
  - FOLD-PRESS §9.2 specified the region API; it was never built.
  - Apple's frame includes the margins, so the real no-go band may be wider than 40 pt.
- **Fix:**
  - In `FoldStageHostView.layoutSubviews`, read `reservedRegions(kind: .division, options: .includeInactive)`. UIKit re-runs it when regions change.
  - Do the same in RootView's `GeometryReader` for `ScreenBands`.
  - Take the midline as `foldLine`.
  - Take the band as `max(40, widest active frame seen)`, cached, because the region is zero-width when flat.
  - Keep "lay out once per canvas size". Apple's inactive frame exists precisely so layouts don't jump.

**L2. Keep custom controls clear of `.occlusion` regions on both displays (§1.4).** ❌
- **Where:**
  - Nothing queries occlusion.
  - The stage ignores the safe area (`FoldPressView.swift:20`, `RootView.swift:213`).
  - The crown gauge and lamps, console keycaps and toast slot sit at fixed coordinates (`FoldGeometry.swift:142-163`, `RootView.swift:313-325`).
  - The specs list a Dynamic Island on **both** displays. The inner camera region appears whenever the camera is active.
  - On the cover, the four screws sit on the panel corners (`CoverView.swift:181-186`, `CoverLayout.screw` at `:212-215`), and the outer camera "is in the corner and is always visible". The top-trailing screw is probably under it.
- **Fix:**
  - Query `.occlusion` where each element is placed.
  - Nudge keycaps and toasts out of the way, and use FOLD-PRESS §5's "swap gauge and lamps" rule for the crown.
  - Drop or offset any screw that intersects a region.
  - Check the cover frame O1 and an inner frame with a Live Activity running.

**L3. Keep interactive elements out of the fold (§1.4, §1.7).** ✅
- **Where:** The crease band is solid graphite with nothing interactive in it (FOLD-PRESS §12 R1), and the console is on the anvil's free edge.
- **Fix:** None.

**L4. Seated pose: distance content at the top, controls at the bottom (§1.4).** ✅
- **Where:** The crown strip and gauge are on top and the console is at the bottom (`FoldGeometry.swift:141-163`). That matches Apple's pattern exactly.
- **Fix:** None.

**L5. In book pose, put things on the trailing side so they are near where the device closes (§1.4).** ✅
- **Where:** Anvil and console are on the trailing page (FOLD-PRESS §9.2), and tips go to the right half (`RootView.swift:296-305`).
- **Fix:** None.

**L6. System sheets already slide out of the fold (§1.4).** ❓
- **Where:** The custom `CreaseSafe` squeezes the Shelf onto the trailing half in book pose (`Theme.swift:1091-1111`, applied at `RootView.swift:377`).
- **Risk:** On top of the system's own nudge, it could squeeze the sheet twice.
- **Fix:** Check on a device in book pose. If the system already places the sheet off the fold, limit `CreaseSafe` to cases the system doesn't handle.

**L7. Grids should have an even number of columns (§1.4).** ✅
- **Where:**
  - The Shelf grid has 5 columns when wide (`ShelfView.swift:69`).
  - In the seated pose the fold is horizontal, so no column straddles it. In book pose `CreaseSafe` confines the grid to one page.
- **Fix:** Optional: use 4 or 6 columns when a division exists.

**L8. Fill the screen; prefer aspect change over letterboxing (§1.7).** ✅
- **Where:** The Fold canvas fills the whole inner display in both axes (`FoldGeometry.swift:134-136`), and the cover fills the outer display.
- **Fix:** None. Book-pose letterboxing is still on CLAUDE.md's device checklist; confirm there is none.

**L9. Fit the screen corners with concentricity APIs (§1.7).** ❓
- **Where:** Hazard jaws and rails are drawn square to the canvas edges (`FoldGeometry.swift:138-185`), and the Duo's corners are rounded.
- **Fix:** Inspect the corners in a raw capture. If the stripes are clipped, inset the jaw ends by the corner radius, or mask the bezel with `ConcentricRectangle`.

**L10. Use size classes, not pixel sizes (§1.5).** ⚠️
- **Where:**
  - No size class is read anywhere.
  - "Is this the inner canvas" is a size heuristic (`FoldRenderGate.swift:68-70`, `FoldPressView.swift:241`, minimum side ≥ 320 and maximum ≥ 800).
  - Comments hard-code 466 × 678.
  - Aspect for the fold axis is fine: Apple says "compare the width and height".
- **Fix:** Decide inner versus outer from `horizontalSizeClass` plus a division region present with `.includeInactive` (see S2). Keep the aspect test for the axis.

### 2.3 Scenes, displays and continuity

**S1. Keep the scene lifecycle; don't use `UIScreen.main`, idiom or orientation for layout (§1.5).** ✅
- **Where:**
  - It is a SwiftUI `App` / `WindowGroup` (`SquishApp.swift:3-9`).
  - There is no `UIScreen.main` and no idiom check.
  - `effectiveGeometry.interfaceOrientation` is used only in the CI rotation hook (`PressDirector.swift:1157`, inside `#if DEBUG` from `:1050` to `:1646`).
- **Fix:** None for shipping.

**S2. Treat a display change as a size-class and trait change (§1.5).** ⚠️
- **Where:**
  - "On the cover" is `hingeAvailable && hingeClosed` (`PressDirector.swift:80`).
  - The status is the system's angle-and-orientation call, and the simulator holds `.closed` to ~150° while reopening (CLAUDE.md gotchas).
  - If the app reaches the outer display before `.closed` arrives (tent, or a fast close), the frozen 669 × 951 fold stage would sit in a 466 × 678 window with no cover on top of it.
- **Fix:**
  - Add `onOuterDisplay`: compact horizontal size class, or no `.division` region even with `.includeInactive` [Inference].
  - Show `CoverView` on `onOuterDisplay || closed`.
  - Keep `.closed` for the clap and seal.

**S3. Keep state through the fold (§1.5).** ✅
- **Where:**
  - `PressDirector` lives above every display-dependent branch (`RootView.swift:10`).
  - The blind clock keeps the engine running while shut.
  - `sceneBecameActive` deliberately doesn't reset input on fold (`PressDirector.swift:128`). That matches DTS: full screen, "the scene is unaffected".
- **Fix:** None.

**S4. Multitasking: all apps take part, and `UIRequiresFullScreen` should go "as soon as possible" (§1.5).** ⚠️
- **Where:**
  - `UIRequiresFullScreen: true` (`project.yml:33`) is kept for the CI rotation request.
  - `usesFoldPress` (`PressDirector.swift:86`) doesn't check the window, though FOLD-PRESS §8 says Split View gets the P-48.
  - If Squish ever lands in a half-width window (~475 × 669), `FoldStageHostView.layoutSubviews` refuses to lay out (the ≥ 800 guard at `FoldPressView.swift:241`) and the stage stays blank. Whether full-screen apps can enter Split View on the Duo is ❓.
- **Fix:**
  - Gate `usesFoldPress` on "a division region crosses this window's middle" (L1). Otherwise show the P-48.
  - For 1.1, drive CI rotation another way and remove `UIRequiresFullScreen`.
  - This is not an App Review issue.

**S5. Supported orientations (§1.5).** ✅
- **Where:** Portrait and both landscapes (`project.yml:27-31`). The inner display ignores them anyway, and the outer display honours them, which covers the tent pose.
- **Fix:** Optional: add portrait upside-down ("best practice to support all interface orientations").

### 2.4 Posture

**P1. There is no pose API: combine status, angle, orientation and size class, and use CoreMotion `deviceMotionBody` for display-relative gravity and "which face is up" (§1.3).** ❌
- **Where:**
  - The pose is inferred from canvas aspect alone: wide means book, tall means tabletop (`FoldPressController.swift:501-511`, `:195`).
  - `FoldPose.handheld(pitch:)` is modelled and tested but never used (`FoldGeometry.swift:324`).
  - There is no CoreMotion anywhere.
  - So a phone held in the hands with a horizontal hinge gets the table eye.
  - Tent isn't detected.
- **Fix:**
  - Add a `CMMotionManager` with `deviceMotionBody = FoldStageHostView`.
  - From gravity, classify:
    - **seated:** the anvil within ~30° of level;
    - **handheld:** pitch β, fed to `.handheld(pitch:)`;
    - **tent:** the outer display facing the user, so show the cover's "lay it open" prompt.
  - Smooth it, and ignore gravity during strong haptics (the HIG warns that haptics disturb the gyroscope).
  - Use Apple's word **seated** in docs. User copy can stay "on a table".

### 2.5 The outer display

**O1. "Keep functionality and the state of elements the same between displays." "Make your game playable in every device pose." The featuring form asks about "support for all device poses" (§1.7, §1.10).** ❌
- **Where:**
  - The cover is a lobby only: an idle picker and the sealed card (`CoverView.swift:40-49`).
  - It has no Shelf, no Settings or Menu, and no way to press.
  - `RootView.swift:148-150` closes any open sheet when the cover comes up.
  - EXPERIENCE-PLAN §8 already promises "Settings is one tap from home, the reveal and the cover".
- **Fix:** On the outer display, offer:
  1. **Shelf**: view specimen cards and prints in a compact layout.
  2. **Menu / Settings**.
  3. A **thumb quick-press**: the P-48 touch press, sized for 466 × 678.

  Keep "Open for the real press" as the hero call to action. Pressing on the cover never replaces the fold.

**O2. Scene accessories are the only way to use the cover while open (§1.6).** ✅ (does not apply)
- **Where:** Not used, correctly. Squish has no capture session and no external display.
- **Fix:** Never show a "both screens lit" frame (rule 3, truthful store frames). Optionally, later: an `ExternalNonInteractiveAccessory` for an AirPlay or streaming view of the press.

**O3. Live Activities and the Dynamic Island (§1.6).** ✅ (does not apply)
- **Where:** None. A press lasts seconds, and Live Activities are for tracking an ongoing activity.
- **Fix:** Don't add one. Do handle someone else's Live Activity occluding Squish (L2).

**O4. Cover layout uses safe areas, with background art allowed past them (§1.7).** ✅
- **Where:** Idle content uses the insets (`CoverView.swift:80-91`). The panel art ignores them, which Apple allows for backgrounds.
- **Fix:** None, apart from the screws in L2.

### 2.6 Feedback, power and safety

**F1. Silent mode should silence sound effects and game soundtracks (HIG Playing audio, §1.8).** ❌ (HIG; not an App Review rule)
- **Where:** Default `.playback` + `.mixWithOthers`, so Squish plays on silent (`Contracts.swift:62`, `FeedbackTuning.swift:32-35`). This is a deliberate EXPERIENCE-PLAN decision.
- **2.5.9 is not breached:** Squish doesn't change what the switch does.
- **Fix:** Founder's call. HIG-aligned options:
  - default to `.ambient` and ask once in the S1 sound check ("Your phone is on Silent. Hear the squish?");
  - or keep it on, but make the S1 sound check show the setting clearly.

  The setting itself is good either way.

**F2. Haptics: optional, not overused, no Duo specifics (§1.8).** ✅
- **Where:** There is a haptics level with Off (`RootView.swift:140`), and the strain bed is capped at about 0.55 (EXPERIENCE-PLAN).
- **Fix:** If CoreMotion is added (P1), keep it from reading during strong haptic events.

**F3. 2.4.2: no excessive heat or battery drain (§1.10).** ✅
- **Where:**
  - Rendering stops while the inner display can't be seen (`FoldRenderGate.swift`).
  - Under thermal pressure there is less oversampling and fewer particles (`FoldPressController.swift:197-198`), and haptics are capped.
- **Fix:** ❓ Check that the audio engine idles after a long time shut on the cover. That is a device battery check.

**F4. 2.4.2 / 1.4.5: never encourage use that risks the device (§1.10).** ⚠️
- **Where:**
  - The safety line ("Never close your phone on real things") is on the cover (`CoverView.swift:105`).
  - A slam earns a SLAMMED stamp with no reward.
  - EXPERIENCE-PLAN adds a "PUMPED ×N" stamp.
- **Fix:** Make sure PUMPED never rewards rapid repeated folding. Cap it, or reward slow pumps only, so App Review can't read it as a fold-cycling incentive.

**F5. Auto-lock during hinge-only interaction (§1.8).** ❓
- **Where:** `isIdleTimerDisabled` is never set. Nothing official says whether hinge motion counts as user activity.
- **Fix:** Set `isIdleTimerDisabled` only while armed, pressing or revealing on the inner display, and restore it otherwise.

**F6. Display-off angle (§1.8).** ❓
- **Where:** `FoldRevealLight.litAngle = 55` (`FoldRenderGate.swift:272`), with failures kept at ≥ 63° (FOLD-PRESS §4.3).
- **Fix:** There is no official number. Tune from the founder's Tuning Lab hinge log.

### 2.7 Store, review and testing

**A1. Duo screenshots, inner and outer, give the badge (§1.10).** ✅
- **Where:** `docs/appstore/DECISIONS.md:49-50`. `store.yml` builds inner 01–07 and outer O1–O2.
- **Fix:** None. Re-check after O1 if the cover gains features.

**A2. Duo app preview (§1.10).** ⚠️
- **Where:** "No Duo preview in 1.0" (`DECISIONS.md:18`). The 886 × 1920 master is ready (`preview-video.md`).
- **Fix:** Ship it in 1.0.1, after checking the accepted size in App Store Connect's uploader.

**A3. Featuring nomination: "optimized for iPhone Duo, including support for all device poses", at least 3 weeks ahead (§1.10).** ⚠️
- **Where:** `docs/appstore/featuring-nomination.md` exists.
- **Fix:** Claim "all poses" only once O1 and P1 are true (2.3.1 accuracy). Name the seated pose, book pose and the cover.

**A4. Don't detect the device; don't require capabilities (§1.3, §1.10).** ✅
- **Where:**
  - Squish keys on hinge presence (`RootView.swift:35`, `hasHinge`), the same as Apple's own sample.
  - `TARGETED_DEVICE_FAMILY: "1"` with no required capabilities (`project.yml:49`).
- **Fix:** None.

**A5. Test in Device Hub and validate on hardware (§1.9).** ✅
- **Where:** `duo.yml` and `store.yml` drive the real Duo simulator with the community `hinge` CLI. The founder now has a device.
- **Fix:** Keep a manual Device Hub pass (Option-drag slider) for each release, because the CLI is unofficial and could break.

**App Review summary.** No hard rejection risk was found.
- The soft spots:
  - **F4:** fold-cycling incentives under 2.4.2 and 1.4.5.
  - **A3 and O1:** claiming "all poses" in metadata or a nomination before it is true (2.3.1).
- The store frames are already held to rule 3. Device-frame renders with real app content are fine under 2.3.3.

---

## Part 3: Top 10 changes to make Squish feel most "Duo-native" by Apple's standards

Ranked by how directly each change answers Apple's own wording, weighted by how much of the Squish experience it touches.

1. **Make the outer display a full Squish, not just a lobby** (O1).
   - Add the Shelf, Menu/Settings and a thumb quick-press on the 466 × 678 cover. Keep "Open for the real press" as the hero.
   - This is the HIG's core message: "a continuous experience as the device opens and closes", "the same functionality across device poses", and games "playable in every device pose".
   - It is also the honest basis for an "all poses" featuring claim.
   - Files: `CoverView.swift`, `RootView.swift:148-150` (stop dismissing sheets on cover; present a cover-sized Shelf instead).

2. **Read the fold from `.division` reserved regions** (L1).
   - Get the fold line and band width from `reservedRegions(kind: .division, options: .includeInactive)`, cached per canvas, and feed `FoldLayout(canvas:foldLine:)`.
   - Today the crease is a hard-coded 40 pt guess, and Apple's frame includes interactive margins.
   - This is Apple's single most repeated custom-layout instruction.

3. **Decide inner versus outer by traits and regions, not by `.closed`** (S2, L10, S4).
   - Use compact width, or no division region, to mean the cover. Use a region crossing the window to mean the fold stage. Everything else gets the P-48.
   - This replaces the pixel-size heuristics and the status-based cover, and it covers Split View.
   - Apple: "Treat display transitions as size-class and trait changes."

4. **Detect posture with CoreMotion `deviceMotionBody`** (P1).
   - Tell seated from handheld from tent, and feed the already-written `.handheld(pitch:)` eye. In tent, show "lay it open".
   - Apple says there is no pose value and to combine signals. `deviceMotionBody` is the new iOS 27 API that makes motion display-relative on the Duo and tells you "which face is up".

5. **Use `DeviceHinge.Status` fully** (H3).
   - `.fullyOpen` for re-arm and the flat invite, `.partiallyOpen` for the active press, `.closed` for the clap.
   - Keep the 90° stale-closed guard.
   - Apple: prefer status for discrete states. Its own sample gates on `.partiallyOpen`.

6. **Make nil-hinge handling robust** (H2).
   - Never tear down the fold stage on a transient nil. Hold state, and only fall back to touch if the hinge never reported, or stays nil with no division region.
   - Apple documents nil for "left a hierarchy", not only for "no hinge". A Duo that flips to the P-48 mid-fold would be the least native moment possible.

7. **Keep controls clear of occlusion regions** (L2).
   - Query `.occlusion` for the console keycaps, toast slot and crown gauge on the inner display (the Dynamic Island, and the inner camera when active), and for the cover's screws (the outer camera is always active).
   - Apple: "Place important views and controls outside this area."

8. **Ship the Duo App Preview and the featuring nomination** (A2, A3).
   - After (1) and (4), nominate with "optimized for iPhone Duo, including support for all device poses", at least 3 weeks ahead.
   - Add the Duo preview after verifying the accepted size in App Store Connect.
   - Apple is building "editorial collections for iPhone Duo apps", and it name-checked a fold toy (Deck-Man).

9. **Plan to remove `UIRequiresFullScreen`** (S4).
   - Move the CI portrait request off it, then drop the key in 1.1, once the fold stage guards itself (3).
   - Apple: "As soon as possible, you should remove UIRequiresFullScreen."

10. **Small polish in Apple's vocabulary** (L9, F5, F1).
    - Fit the bezel ends to the rounded corners (`ConcentricRectangle`) if raw frames show clipping.
    - Hold off auto-lock only during a live press.
    - Revisit the silent-mode default with the founder against the HIG's "silence… sound effects".
    - Call the hero pose "seated" in docs, Apple's word for it.

---

## Sources

**Apple developer documentation**
- [Preparing your app for iPhone Duo](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo)
- Hinge, SwiftUI:
  - [onHingeChange(isEnabled:_:)](https://developer.apple.com/documentation/swiftui/view/onhingechange(isenabled:_:))
  - [DeviceHinge](https://developer.apple.com/documentation/swiftui/devicehinge)
  - [DeviceHinge.Status](https://developer.apple.com/documentation/swiftui/devicehinge/status-swift.struct)
  - [DeviceHingeContext](https://developer.apple.com/documentation/swiftui/devicehingecontext)
- Hinge, UIKit:
  - [UIHingeInteraction](https://developer.apple.com/documentation/uikit/uihingeinteraction)
  - [isEnabled](https://developer.apple.com/documentation/uikit/uihingeinteraction/isenabled)
  - [UIHinge](https://developer.apple.com/documentation/uikit/uihinge)
  - [UIHinge.angle](https://developer.apple.com/documentation/uikit/uihinge/angle)
  - [UIHinge.Status](https://developer.apple.com/documentation/uikit/uihinge/status-swift.enum)
- Reserved regions:
  - [ReservedRegion](https://developer.apple.com/documentation/swiftui/reservedregion)
  - [GeometryProxy.reservedRegions](https://developer.apple.com/documentation/swiftui/geometryproxy/reservedregions(kind:options:layoutdirectionbehavior:))
  - [UIView.ReservedRegion](https://developer.apple.com/documentation/uikit/uiview/reservedregion)
  - [UIView.reservedRegions](https://developer.apple.com/documentation/uikit/uiview/reservedregions(kind:options:))
- Scene accessories:
  - [sceneAccessory(content:)](https://developer.apple.com/documentation/swiftui/view/sceneaccessory(content:))
  - [CameraCaptureAccessory](https://developer.apple.com/documentation/swiftui/cameracaptureaccessory)
  - [ExternalNonInteractiveAccessory](https://developer.apple.com/documentation/swiftui/externalnoninteractiveaccessory)
- CoreMotion:
  - [CMMotionManager.deviceMotionBody](https://developer.apple.com/documentation/coremotion/cmmotionmanager/devicemotionbody)
  - [CMBodyIdentifiable](https://developer.apple.com/documentation/coremotion/cmbodyidentifiable)
- Device Hub:
  - [Device Hub](https://developer.apple.com/documentation/xcode/device-hub)
  - [Interacting with your app in Device Hub](https://developer.apple.com/documentation/xcode/interacting-with-your-app-in-device-hub)
  - [Interacting with devices using the command line](https://developer.apple.com/documentation/xcode/interacting-with-devices-using-the-command-line)
- Release notes and updates:
  - [Xcode 27.1 Release Notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27_1-release-notes)
  - [iOS & iPadOS 27.2 RC Release Notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27_2-release-notes)
  - [Updates (27 releases)](https://developer.apple.com/documentation/updates)

**Human Interface Guidelines**
- [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)
- [Layout](https://developer.apple.com/design/human-interface-guidelines/layout)
- [Playing audio](https://developer.apple.com/design/human-interface-guidelines/playing-audio)
- [Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)

**Videos**
- Tech Talks:
  - [111461 Prepare your app for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111461/)
  - [111462 Raise the bar](https://developer.apple.com/videos/play/tech-talks/111462/)
  - [111463 Strike a pose with adaptive layouts](https://developer.apple.com/videos/play/tech-talks/111463/)
  - [111464 Leverage multiple displays and scenes](https://developer.apple.com/videos/play/tech-talks/111464/)
  - [111465 Build a great camera experience](https://developer.apple.com/videos/play/tech-talks/111465/)
  - [111466 Design for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111466/)
- WWDC26:
  - [278 Modernize your UIKit app](https://developer.apple.com/videos/play/wwdc2026/278/)
  - [260 Get the most out of Device Hub](https://developer.apple.com/videos/play/wwdc2026/260/) (not read)
- Group Labs (no transcripts):
  - [Meet with Apple 285](https://developer.apple.com/videos/play/meet-with-apple/285/)
  - [286](https://developer.apple.com/videos/play/meet-with-apple/286/)
  - [287](https://developer.apple.com/videos/play/meet-with-apple/287/)

**Programme pages, App Store and review**
- [Get ready for iPhone Duo (hub)](https://developer.apple.com/iphone-duo/)
- [Three steps to make your app shine on iPhone Duo](https://developer.apple.com/iphone-duo/prepare/)
- [Prepare and submit your apps for iPhone Duo (news, 5 Oct 2026)](https://developer.apple.com/news/?id=kkphp5qo)
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
- [App preview specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications)
- [Nominate your app for featuring](https://developer.apple.com/help/app-store-connect/manage-featuring-nominations/nominate-your-app-for-featuring/)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

**Apple Q&A (Developer Forums)**
- [847644 Group Lab highlights](https://developer.apple.com/forums/thread/847644) (linked as "Group Lab highlights" from the hub)
- [847775 detecting iPhone Duo](https://developer.apple.com/forums/thread/847775) (Apple Technology Evangelist)
- [847838 ScenePhase on fold](https://developer.apple.com/forums/thread/847838) (Apple DTS)
- [847888 fold posture](https://developer.apple.com/forums/thread/847888) (Apple DTS)
- [847883 programmatic simulator unfold](https://developer.apple.com/forums/thread/847883) (no Apple answer)

**Apple consumer pages**
- [Pose iPhone Duo](https://support.apple.com/en-au/guide/iphone/iphv3p93k1bm/ios)
- [What's new with iPhone Duo](https://support.apple.com/en-gb/guide/iphone/iphge85m9f19/ios)
- [iPhone Duo tech specs](https://www.apple.com/iphone-duo/specs/)
- [Newsroom: Developers bring incredible new app experiences to iPhone Duo](https://www.apple.com/newsroom/2026/10/developers-bring-incredible-new-app-experiences-to-iphone-duo/)
