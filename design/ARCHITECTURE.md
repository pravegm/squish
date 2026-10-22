# Squish — Architecture & Module Contracts

*Owner: lead. Every module compiles against the contracts below. If you need a contract changed, write it in your final report instead of editing another module's files.*

## Ground rules (all engineers)

- **Platform:** iOS 18.0 minimum, built with **Xcode 27.1 / iOS 27.1 SDK**, Swift **5 language mode** (`SWIFT_VERSION 5.0`), iPhone only. The hinge API (`onHingeChange`) is iOS 27.1+ and is used **only** in `App/HingeReader.swift` behind `#available(iOS 27.1, *)`.
- **No third-party dependencies.** Apple frameworks only: SwiftUI, RealityKit, Core Haptics, AVFoundation, GameKit, StoreKit, Observation, os.
- **We can't run the app locally.** Code is compiled on a cloud Mac (GitHub Actions `xcode-27` image, Xcode 27.1) building for the **iOS 27.0 iPhone 18 Pro simulator**. So:
  - Only use APIs you are confident exist in the iOS 18 SDK, or gate anything newer with `if #available`.
  - Prefer well-established APIs (ARView, ModelEntity, MeshResource, LowLevelMesh (iOS 18), PhysicallyBasedMaterial, Core Haptics, AVAudioEngine) over brand-new ones.
  - Don't use `CustomMaterial` (no simulator support). Deform geometry on the CPU (`LowLevelMesh`) or with transforms.
  - Every `switch` over `ObjectKind` must be exhaustive (10 cases).
- **Concurrency:** UI, scene, feedback and model classes are `@MainActor`. The audio render thread touches only `Synth` (see `Feedback/Synth.swift`).
- **Observation:** use `@Observable` + `@ObservationIgnored` for per-frame internals. Don't rely on `didSet` on `@Observable` properties.
- **Style:** match the existing code: small focused types, doc comments on anything non-obvious, numbers that come from the bible cite the section.
- **Source of truth for UX:** `design/SQUISH-DESIGN-BIBLE.md`. The research behind it is in `research/`.

## Folder ownership

| Folder | Owner | Notes |
|---|---|---|
| `Squish/Core/` | Lead | Press engine, mapping, materials, object catalogue, variants. Pure logic, unit-tested |
| `Squish/Shared/Contracts.swift` | Lead | Cross-module types |
| `Squish/App/` | Lead | `PressDirector`, `HingeReader`, `DemoMode`, app entry |
| `Squish/Scene/` | Rendering engineer | ARView host, press rig, object views, geometry kit, debris |
| `Squish/Feedback/` | Audio-haptic designer | Synth, audio, haptics, per-object recipes, captions |
| `Squish/UI/`, `Squish/Collection/` | Product UI engineer | All SwiftUI screens, collection store, achievements, Game Center |
| `Squish/Share/` | Export engineer | Share image and clip rendering |
| `SquishTests/` | Everyone (own files) | Swift Testing; name files after your module |
| `docs/appstore/` | Marketing | App Store kit |

## The director (lead) — what it calls on you

`App/PressDirector.swift` owns one of each module and drives them. **Implement these signatures exactly.**

### Scene (`Squish/Scene/`)
```swift
@MainActor final class PressScene {
    init()
    func setObject(_ kind: ObjectKind, variant: PressVariant)          // new object on the anvil
    func update(engine: PressEngine, context: FeedbackContext, dt: Float) // every frame
    func handle(_ event: PressEvent, context: FeedbackContext)          // fractures, failure, reveal…
    func snapshot() async -> UIImage?                                   // current frame, for specimen thumbnails
}
struct PressSceneView: View {              // hosts the 3D view full-screen
    let director: PressDirector             // must call director.frame(dt:) once per rendered frame
}
```

### Fold Press (`Squish/Scene/Fold/`) — the iPhone Duo experience (design/FOLD-PRESS.md)
Squish is Duo-first: on a Duo the two screen halves ARE the press plates. The P-48 machine (`PressSceneView`) is the
fallback for non-folding iPhones and "press without folding".
```swift
@MainActor final class FoldPressController {     // owned by the director as `fold`
    init()
    func setObject(_ kind: ObjectKind, variant: PressVariant)
    func update(engine: PressEngine, context: FeedbackContext, dt: Float)   // only while director.usesFoldPress
    func handle(_ event: PressEvent, context: FeedbackContext)
}
struct FoldPressView: View { let director: PressDirector }   // RootView shows it when director.usesFoldPress
```

### Feedback (`Squish/Feedback/`)
```swift
@MainActor final class HapticsController {
    var level: HapticsLevel
    func start(); func resume()
    func update(engine: PressEngine, context: FeedbackContext)  // every frame: strain bed
    func handle(_ event: PressEvent, context: FeedbackContext)
    func place(context: FeedbackContext)                        // object landed on the anvil
    func collect()                                              // specimen collected
}
@MainActor final class AudioController {
    var enabled: Bool
    var style: SoundStyle
    func start(); func resume()
    func update(engine: PressEngine, context: FeedbackContext)  // every frame: beds, gauge ticks
    func handle(_ event: PressEvent, context: FeedbackContext)
    func place(context: FeedbackContext)
    func collect()
    func unlock()                                               // a new object was unlocked
}
enum Captions {
    /// Onomatopoeia for captions and VoiceOver ("POP!", "CRACK!", "KA-CHUNK"). `announce` = big moments only.
    static func caption(for event: PressEvent, context: FeedbackContext) -> (text: String, announce: Bool)?
}
```

### Collection (`Squish/Collection/`)
```swift
@MainActor @Observable final class CollectionStore {
    init()                                       // loads from Application Support
    var specimens: [SpecimenRecord] { get }      // newest first
    var totalPresses: Int { get }
    func isUnlocked(_ kind: ObjectKind) -> Bool
    func record(_ result: PressResult, variant: PressVariant) -> RecordOutcome  // unlocks + achievements
    func attachThumbnail(_ png: Data, to id: UUID)
    func thumbnailURL(for specimen: SpecimenRecord) -> URL?
    func best(for kind: ObjectKind) -> SpecimenRecord?    // Golden > Perfect > newest
    var earnedAchievements: Set<Achievement> { get }
}
@MainActor final class GameCenter {
    static let shared: GameCenter
    func authenticate()                          // silent; never blocks or nags
    func report(_ achievements: [Achievement])
}
```

### What the UI can rely on (director surface)
Read: `engine` (phase, depths, angles, `lastResult`), `settings: AppSettings`, `collection`, `currentKind`, `variant`, `hingeAvailable`, `isShowingCover`, `usesTouchPress`, `canChooseObject`, `completedPresses`, `failureFlashCount`, `revealed: RecordOutcome?`, `caption: CaptionEvent?`, `lastTrace: PressTrace?`, `hingeLog`.
Write: `reduceMotion`.
Call: `start()`, `sceneBecameActive()`, `choose(_:)`, `queue(_:)` (cover display only), `next()`, `again()`, `trace(for: SpecimenRecord) -> PressTrace?`, `virtualPress(_ fraction:)`, `virtualRelease()`, `hingeUpdate(angle:closed:)`, `hingeUnavailable()`.
Demo keys honoured by the director: `object=`, `depth=`, `reveal`, `seed=<UInt64>`, `golden`, `surprise=<Surprise>`. UI demo keys: `shelf[=squished]`, `settings`, `detail`, `cover[=sealed]`, `specimens=N`.

### Share (`Squish/Share/`)
```swift
@MainActor final class ClipExporter {
    /// Renders a 9:16 6–10 s clip of the press (bible §10). Progress 0…1.
    func export(trace: PressTrace, specimen: SpecimenRecord, progress: @escaping (Double) -> Void) async throws -> URL
}
enum ShareImageRenderer {
    @MainActor static func render(specimen: SpecimenRecord, thumbnail: UIImage?) -> UIImage?   // before/after card PNG
}
```

## Press events (from `Core/PressEngine.swift`)
`armed`, `contact`, `grain(compression:)`, `preFailureTell`, `hush` (fires 45 ms before the failure), `fracture(index:isFailure:)`, `bottomOut`, `sealed(blind:)`, `kaChunk`, `released`, `reveal`.
Per-object fracture meanings are documented on each `MaterialProfile` in `Core/MaterialProfile.swift`; fracture indices are **ascending compression order**.

## Demo scenarios (CI screenshots)
`-squishDemo "key=value;key"` launch argument (`App/DemoMode.swift`): `object=<kind>`, `depth=0…1`, `reveal`. UI may add keys: `shelf`, `settings`, `cover`, `detail`. Add new screenshot rows to `ci/scenarios.txt`.
