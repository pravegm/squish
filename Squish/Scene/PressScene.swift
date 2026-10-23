import Foundation
import RealityKit
import simd
import UIKit

/// The press scene (bible §9, VISUAL-TARGET §3–4): cyclorama with per-object gel wall, procedural studio IBL,
/// key + rim lights, baked contact-shadow decals, the P-48 press, the object on the anvil, and its persistent mess.
/// The object sits on the anvil in the lower half of the screen; the ram descends from the top half.
/// In book (vice) pose — view wider than tall — the camera rolls so the ram comes from the side.
@MainActor
final class PressScene {
    let root = Entity()
    var style = SceneStyle.standard
    /// Set by the director: true until the user has completed a press. While true (and the touch press is in use),
    /// the platen breathes downward with a soft glow to teach "drag down" wordlessly (VISUAL-TARGET §6.1).
    var isFirstPress = true
    /// Once the user drags, the teaching pulse stops forever (this session).
    private var taught = false

    /// The hosting ARView, for snapshots and framing (weak: the view owns the scene graph, not vice versa).
    weak var arView: ARView?

    private let rig = PressRig()
    private let objectSlot = Entity()
    private let fx = SceneFX()
    private let camera = PerspectiveCamera()
    private let flash = PointLight()
    private let sweep = ModelEntity()
    private var iblHolder: Entity?
    private var objectView: PressObjectView?
    private var kind: ObjectKind = .bubbleWrap
    private var variant = PressVariant(kind: .bubbleWrap, seed: 1)

    // Decals
    private var gaussian: [Int: TextureResource] = [:]
    private var aoDecal: Decal?
    private var staticDecals: [Decal] = []
    private var softDecal: Decal?
    private var ramDecal: Decal?
    private var sweepTextures: [UInt32: TextureResource] = [:]
    private var sweepRequest = 0

    // Ram
    private var ramFace: Float = PressRig.homeFace
    private var ramVelocity: Float = 0
    private var failureHold: Float = 0
    private var heldFace: Float = 0

    // Juice
    private var clock: Float = 0
    private var hitStop: Float = 0
    private var slowMo: Float = 0
    private var flashLevel: Float = 0
    private var kick: Float = 0
    private var lastState: PressVisualState?
    private var tell = false
    private var peakTons: Float = 0
    private var steamTimer: Float = 0
    /// Fold Press: the reveal's glint, held until the inner display lights (`foldRevealLit`).
    private var pendingRevealGlint = false

    // Placement, rest beat and power-on
    /// Holds the previous object while it slides off the anvil (the mess moves with `fx.root`).
    private let outgoing = Entity()
    private var outgoingActive = false
    private var sinceSet: Float = 0
    private var dropAt: Float = 0
    private var powerOn: Float?
    private var landedAt: Float = .infinity
    private var lastPhase: PressPhase = .idle
    private var teachWave: Float = 0
    private var fovScale: Float = 1
    private var fovTarget: Float = 1
    private var baseFieldOfView: Float = 49.6
    // Startup (studio readiness gate: VISUAL-REVIEW-1 fix 1)
    /// True once the IBL, the gel sweep and the current object are built. Until then the ARView is transparent
    /// (the SwiftUI backdrop shows through), so there is no grey flash and no lighting pop; it fades in at ready.
    private(set) var isStudioReady = false
    private var iblReady = false
    private var sweepReady = false
    /// Assets are in; now wait for a few smooth frames (first-draw shader compiles happen while still transparent).
    private var assetsReady = false
    private var smoothFrames = 0
    private var framesSinceAssets = 0
    private var iblRequested = false
    private var iblFade: Float = 1
    /// Fills the shadow side until the IBL arrives (then fades out).
    private let fallbackFill = PointLight()
    private let createdAt = CACurrentMediaTime()
    private var objectRequest = 0
    private var warmedKinds: Set<ObjectKind> = []
    private var specimenView: ARView?
    /// True while the camera is rolled for book (vice) pose — UI can move its edge cues to the moving half.
    private(set) var isBookPose = false
    private var dropHeight: Float = 0
    private var dropVelocity: Float = 0
    private var landingSquash = JiggleSpring(value: 0, velocity: 0, omega: 2 * .pi / 0.35, zeta: 0.45)

    // Framing
    private enum Pose { case tabletop, book }
    private var pose: Pose = .tabletop
    private var framedSize: CGSize = .zero
    private var framedPose: Pose?

    init() {
        SceneTrace.mark("init begin")
        root.addChild(sweep)
        root.addChild(rig.root)
        root.addChild(objectSlot)
        root.addChild(fx.root)
        root.addChild(outgoing)
        fx.debris.setBounds(min: -PressRig.anvilHalf, max: PressRig.anvilHalf)
        fx.particles.minXZ = -PressRig.anvilHalf
        fx.particles.maxXZ = PressRig.anvilHalf
        buildSweep()
        buildDecals()
        buildLights()
        root.addChild(camera)
        frame(size: CGSize(width: 402, height: 874))
        if DemoScenario.current?.has("calib") == true { buildCalibrationCards() }
        SceneTrace.mark("init end")
    }

    // MARK: - Contract

    func setObject(_ kind: ObjectKind, variant: PressVariant) {
        // Heavy procedural meshes (SDF blobs, dense lathes) are built off the main actor first (startup budget),
        // then the view is assembled here on main. The latest request wins.
        objectRequest += 1
        let request = objectRequest
        pendingRevealGlint = false
        if warmedKinds.contains(kind) || ObjectMeshes.jobs(for: kind).isEmpty {
            buildObject(kind, variant: variant)
            return
        }
        Task { @MainActor [weak self] in
            let results = await Task.detached(priority: .userInitiated) { () -> [(String, MeshData)] in
                SceneTrace.measure("meshes \(kind.rawValue) (off main)") { ObjectMeshes.build(kind) }
            }.value
            guard let self else { return }
            for (key, data) in results { MeshCache.store(key, data) }
            self.warmedKinds.insert(kind)
            if request == self.objectRequest { self.buildObject(kind, variant: variant) }
        }
    }

    private func buildObject(_ kind: ObjectKind, variant: PressVariant) {
        self.kind = kind
        self.variant = variant
        finishOutgoing()
        let firstObject = objectView == nil
        if let old = objectView?.entity {
            // Rest beat (bible §3.1 beat 12, UX-REVIEW P1-3): the crushed specimen and its mess stay a moment,
            // then slide back off the anvil and drop behind it; the press resets; then the next object drops.
            old.setParent(outgoing, preservingWorldTransform: true)
            outgoingActive = true
        } else {
            fx.clear()
            rig.repair()
        }
        let view = SceneTrace.measure("object view \(kind.rawValue) (main)") {
            PressObjectFactory.make(kind, variant: variant, fx: fx)
        }
        objectSlot.addChild(view.entity)
        ShadowCasting.offForTranslucent(in: view.entity)
        objectView = view
        sinceSet = 0
        // First launch: the power-on beat, then the drop at 0.8 s (P2-1). Next objects: after the rest beat.
        powerOn = firstObject ? 0 : nil
        dropAt = firstObject ? 0.8 : (fx.reduceMotion ? 0.5 : 1.1)
        view.entity.isEnabled = false
        fovScale = 1
        fovTarget = 1
        rig.hideSealTag()
        ramFace = PressRig.homeFace
        ramVelocity = 0
        hitStop = 0
        slowMo = 0
        failureHold = 0
        kick = 0
        tell = false
        peakTons = 0
        dropHeight = 0
        dropVelocity = 0
        landedAt = .infinity
        landingSquash = JiggleSpring(value: 0, velocity: 0, omega: 2 * .pi / 0.35, zeta: 0.45)
        let state = makeState(compression: 0, ramCompression: 0, approach: 0, dt: 0, loaded: false,
                              closingSpeed: 0, reduceMotion: fx.reduceMotion, phase: .idle)
        view.update(state)
        lastState = state
        applyGel()
        checkStudioReady()
    }

    func update(engine: PressEngine, context: FeedbackContext, dt: Float) {
        guard let view = objectView else { return }
        let dt = min(max(dt, 0), 1.0 / 20.0)
        if assetsReady && !isStudioReady {
            // A stalled frame clamps to 0.05 s, so "smooth" means comfortably under that.
            smoothFrames = dt < 0.045 ? smoothFrames + 1 : 0
            framesSinceAssets += 1
            // On a slow GPU (or the CI simulator) frames are never "smooth"; don't hold the scene hostage for it.
            if smoothFrames >= 4 || framesSinceAssets >= 8 { markStudioReady(timedOut: false) }
        }
        clock += dt
        updateLightFade(dt: dt)
        if !iblRequested && CACurrentMediaTime() - createdAt > 6 { loadStudioLight() }
        // The placement / power-on timeline starts once the studio is visible.
        if isStudioReady { sinceSet += dt }
        if !isStudioReady && CACurrentMediaTime() - createdAt > 4 { markStudioReady(timedOut: true) }
        fx.reduceMotion = context.reduceMotion
        updateFraming(engine: engine)
        updateRestBeat(engine: engine, context: context, dt: dt)
        updateSealTag(engine: engine, context: context, dt: dt)
        fovScale = Deform.approach(fovScale, fovTarget, halfLife: 0.15, dt: dt)
        camera.camera.fieldOfViewInDegrees = baseFieldOfView * fovScale

        let contactT = Float(engine.mapping.contactT)
        let renderDepth = Float(engine.renderDepth)
        let renderC = Float(engine.renderCompression)
        let visualC = Float(engine.visualCompression)
        let rest = view.restHeight
        let start = PressRig.homeFace
        let approach = clamp(renderDepth / max(contactT, 0.01), 0, 1)

        // Ram target: the free approach from home, then wherever the object's surface is at the hand's compression.
        var target: Float
        if renderDepth < contactT {
            target = start - (start - rest) * approach
        } else {
            target = view.surfaceHeight(compression: renderC)
        }
        if failureHold > 0 {
            failureHold -= dt
            target = max(target, heldFace)
        }
        // The hand owns the ram; a fast spring only smooths lurches (failure drops) so they read as "it gave".
        if ramFace - target > 0.002 {
            var spring = CriticalSpring(value: Double(ramFace), velocity: Double(ramVelocity))
            spring.step(toward: Double(target), omega: 55, dt: Double(dt))
            ramFace = max(Float(spring.value), target)
            ramVelocity = Float(spring.velocity)
        } else {
            ramFace = target
            ramVelocity = 0
        }

        // Hit-stop freezes the object's response and its debris; the ram stays with the hand.
        var objectDt = dt
        if hitStop > 0 {
            hitStop -= dt
            objectDt = 0
        }
        let state = makeState(compression: visualC, ramCompression: renderC, approach: approach, dt: objectDt,
                              loaded: engine.isLoaded, closingSpeed: Float(engine.closingSpeed),
                              reduceMotion: context.reduceMotion, phase: engine.phase)
        lastState = state
        if objectDt > 0 || state.compression == 0 {
            view.update(state)
        }

        // Secondary systems: 0.3× slow motion for 250 ms after failure (bible §9). Reduce Motion: none.
        var fxDt = objectDt
        if objectDt > 0 && slowMo > 0 {
            slowMo -= dt
            if !context.reduceMotion { fxDt *= style.slowMoRate }
        }
        // Fold Press: the whole top half is the platen, so its virtual face is a ceiling over the entire anvil
        // (FOLD-REVIEW-1 #2: shards must flatten to the platen height, not only under the P-48 plate).
        let ceilingExtent = framing == .foldAnvil ? SIMD2<Float>(repeating: 1) : rig.plateHalfExtent
        fx.step(dt: fxDt, ceiling: ramFace, plateHalfExtent: ceilingExtent)

        updateDrop(dt: dt)
        let jitter = updateShake(engine: engine, context: context, dt: dt, approach: approach)
        rig.setFace(ramFace - teachingPulse(engine: engine, context: context), jitter: jitter)
        updateDecals(view: view, approach: approach)
        updateFlash(dt: dt)
        updateInstruments(engine: engine, context: context, dt: dt, renderC: renderC, approach: approach)
    }

    func handle(_ event: PressEvent, context: FeedbackContext) {
        guard let view = objectView else { return }
        fx.reduceMotion = context.reduceMotion
        let state = lastState ?? makeState(compression: 0, ramCompression: 0, approach: 0, dt: 0, loaded: false,
                                           closingSpeed: 0, reduceMotion: context.reduceMotion, phase: .idle)
        switch event {
        case .contact:
            hitStop = max(hitStop, style.contactHitStop)
            flashLevel = max(flashLevel, style.contactFlashPeak)
            rig.kickGauge(2)
            view.handle(event, state: state)
        case .preFailureTell:
            tell = true
            view.handle(event, state: state)
        case .reveal:
            isFirstPress = false
            // A 4% push-in as the ram lifts (VISUAL-TARGET §3.2) and a glint over the specimen. The bible's 2 s slow-mo
            // replay isn't done live: the pieces are already settled and flattened, so a replay needs a second
            // deterministic re-simulation from the trace — that belongs to the offline clip renderer (Share).
            if !context.reduceMotion {
                fovTarget = 0.96
                // FOLD PRESS (FOLD-REVIEW-7 N10): a reopen from closed reveals in the dark (~20°); the glint waits for
                // FoldPressController to see the display lit (`foldRevealLit`), so its 0.4 s isn't spent unseen.
                if framing == .foldAnvil {
                    pendingRevealGlint = true
                } else {
                    burstRevealGlint()
                }
            }
            view.handle(event, state: state)
        case let .fracture(index, isFailure):
            view.fracture(index: index, isFailure: isFailure, state: state)
            // New spreads / lines may be translucent: keep them out of the shadow pass.
            ShadowCasting.offForTranslucent(in: view.entity)
            ShadowCasting.offForTranslucent(in: fx.root)
            if isFailure {
                tell = false
                hitStop = max(hitStop, style.failureHitStop)
                slowMo = style.failureSlowMo
                failureHold = style.failureHitStop
                heldFace = ramFace
                flashLevel = context.reduceMotion ? style.flashPeakReducedMotion : style.flashPeak
                kick = context.reduceMotion ? 0 : style.failureKick
                rig.flashRed()
                rig.kickGauge(5)
            } else {
                kick = max(kick, context.reduceMotion ? 0 : style.failureKick * 0.35)
            }
            if kind == .unsquishable {
                let level = isFailure ? 3 : min(index + 1, 2)
                rig.crack(level: level, fx: fx, seed: variant.seed)
            }
        default:
            view.handle(event, state: state)
        }
    }

    private func burstRevealGlint() {
        var rng = SplitMix64(seed: variant.seed &+ 0x2E7)
        fx.particles.burst(.glint, count: 3, at: [0, 0.012, 0.01], speed: 0.06, colors: [UIColor(hex: 0xFFFFFF)],
                           size: 0.003...0.005, spread: 0.03, upBias: 0.7, life: 0.4, rng: &rng)
    }

    /// FOLD PRESS: the inner display is lit for the reveal (FoldPressController, FOLD-REVIEW-7 N10): play its glint.
    func foldRevealLit() {
        guard pendingRevealGlint else { return }
        pendingRevealGlint = false
        burstRevealGlint()
    }

    /// FOLD-REVIEW-7 N10: the stage stopped (or restarted) rendering. Between shots the offscreen specimen ARView stays
    /// in the window, hidden; take it out too while paused, so nothing in the app renders for a dark inner display.
    /// `specimenSnapshot` puts it back (it re-adds whenever its superview isn't the stage). A shot in flight is left be.
    func setRenderPaused(_ paused: Bool) {
        guard paused, let view = specimenView, view.isHidden, view.superview != nil else { return }
        view.removeFromSuperview()
    }

    func snapshot() async -> UIImage? {
        guard let view = arView else { return nil }
        return await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            view.snapshot(saveToHDR: false) { image in
                continuation.resume(returning: image)
            }
        }
    }

    /// A clean top-down product shot of the flattened result and its mess, for specimen cards and share images
    /// (VISUAL-TARGET §6.8, VISUAL-REVIEW-1 fix 12, FOLD-PRESS §9.6 — never the live or warped view).
    /// Renders clones of the object, its debris/mess and grounding decals in a small offscreen `ARView` on paper
    /// (`Palette.gaugePaper`), lit by the same studio IBL and key, from straight above with a long lens (≈ orthographic).
    func specimenSnapshot(size: CGSize = CGSize(width: 360, height: 360)) async -> UIImage? {
        guard let host = arView, var container = host.superview, objectView != nil else { return nil }
        // FOLD PRESS: the Duo anvil ARView sits in a clipping, warped half; park the offscreen view on the stage host.
        if framing == .foldAnvil, let stage = container.superview { container = stage }
        let offscreen: ARView
        if let existing = specimenView {
            offscreen = existing
        } else {
            offscreen = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
            offscreen.renderOptions.insert(.disableMotionBlur)
            offscreen.renderOptions.insert(.disableCameraGrain)
            offscreen.renderOptions.insert(.disableDepthOfField)
            offscreen.renderOptions.insert(.disableGroundingShadows)
            offscreen.isUserInteractionEnabled = false
            specimenView = offscreen
        }
        // Must live in the window to render; parked just outside the visible bounds.
        offscreen.frame = CGRect(x: -size.width - 64, y: 0, width: size.width, height: size.height)
        if offscreen.superview !== container { container.addSubview(offscreen) }
        if framing == .foldAnvil {
            // FOLD PRESS: on screen (so it renders) but behind the opaque Duo stage layers.
            offscreen.frame = CGRect(origin: .zero, size: size)
            offscreen.alpha = 1
            container.sendSubviewToBack(offscreen)
        }
        offscreen.isHidden = false
        offscreen.environment.background = .color(Palette.gaugePaper)

        let anchor = AnchorEntity(world: .zero)
        let objectClone = objectSlot.clone(recursive: true)
        // FOLD PRESS: never the clamshell lean; keep the book-pose yaw so the shot matches the mess and the print.
        objectClone.orientation = simd_quatf(angle: framing == .foldAnvil ? foldYaw : 0, axis: [0, 1, 0])
        let fxClone = fx.root.clone(recursive: true)
        anchor.addChild(objectClone)
        anchor.addChild(fxClone)
        for decal in [aoDecal, softDecal] {
            if let entity = decal?.entity, entity.isEnabled { anchor.addChild(entity.clone(recursive: true)) }
        }
        if let holder = iblHolder {
            let light = holder.clone(recursive: true)
            if var ibl = light.components[ImageBasedLightComponent.self] { // FOLD PRESS: product-shot exposure
                ibl.intensityExponent = style.iblExponent
                light.components.set(ibl)
            }
            anchor.addChild(light)
            let receiver = ImageBasedLightReceiverComponent(imageBasedLight: light)
            objectClone.components.set(receiver)
            fxClone.components.set(receiver)
        }
        let key = DirectionalLight()
        key.light.intensity = style.keyIntensity
        key.light.color = style.keyColor
        key.look(at: .zero, from: simd_normalize(style.keyDirection), relativeTo: nil)
        anchor.addChild(key)

        // Frame the flattened footprint (+ settled mess) × 1.25 from 1 m above.
        var bounds = objectClone.visualBounds(relativeTo: nil, excludeInactive: true)
        let mess = fxClone.visualBounds(relativeTo: nil, excludeInactive: true)
        if !mess.isEmpty { bounds = bounds.union(mess) }
        let extentXZ = max(bounds.max.x - bounds.min.x, bounds.max.z - bounds.min.z)
        let extent = clamp(extentXZ * 1.25, 0.09, 0.22)
        let centre = SIMD3<Float>((bounds.min.x + bounds.max.x) / 2, 0, (bounds.min.z + bounds.max.z) / 2)
        let camera = PerspectiveCamera()
        let height: Float = 1.0
        camera.camera.fieldOfViewInDegrees = 2 * atan(extent / 2 / height) * 180 / .pi
        camera.camera.near = 0.3
        camera.camera.far = 2
        camera.look(at: centre, from: centre + SIMD3(0, height, 0), upVector: [0, 0, -1], relativeTo: nil)
        anchor.addChild(camera)
        offscreen.scene.addAnchor(anchor)

        try? await Task.sleep(for: .milliseconds(180))
        let image: UIImage? = await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            offscreen.snapshot(saveToHDR: false) { image in
                continuation.resume(returning: image)
            }
        }
        offscreen.scene.removeAnchor(anchor)
        offscreen.isHidden = true
        // FOLD PRESS: a blank (never-rendered) shot returns nil so the director / UI fall back.
        if let image, FoldSnapshot.isBlank(image) { return nil }
        return image
    }

    // MARK: - Hosting

    /// Called by PressSceneView once the ARView exists.
    func attach(to view: ARView) {
        if framing != .machine { setFraming(.machine) } // FOLD PRESS: the P-48 view takes the scene back
        arView = view
        framedSize = .zero
        view.environment.background = .color(UIColor(hex: StudioEnvironment.gel(for: kind, golden: variant.isGolden)))
        // Startup gate: invisible until the studio is lit (see `isStudioReady`).
        view.alpha = isStudioReady ? 1 : 0
    }

    /// The full studio IBL. Started only after the first sweep texture is up (its prefilter takes ~6 s on the CI
    /// simulator and serialises other texture uploads behind it). Until it lands, the key + rim + a fallback fill
    /// light the scene; then the IBL cross-fades in over 0.6 s while the fill fades out (no lighting pop).
    private func loadStudioLight() {
        guard !iblRequested else { return }
        iblRequested = true
        let turns = style.iblQuarterTurns
        Task { @MainActor [weak self] in
            // Start fully dimmed (2^-8); `updateLightFade` ramps it to `style.iblExponent`.
            guard let holder = await StudioEnvironment.makeLight(exponent: (self?.style.iblExponent ?? 0) - 8), let self else { return }
            holder.orientation = simd_quatf(angle: Float(turns) * .pi / 2, axis: [0, 1, 0])
            self.root.addChild(holder)
            self.iblHolder = holder
            let receiver = ImageBasedLightReceiverComponent(imageBasedLight: holder)
            for entity in [self.root, self.rig.root, self.objectSlot, self.fx.root, self.outgoing] {
                entity.components.set(receiver)
            }
            self.iblReady = true
            self.iblFade = 0
            SceneTrace.mark("ibl ready (cross-fading)")
        }
    }

    /// Cross-fades fallback fill → IBL: linear in intensity (the IBL exponent is log2).
    private func updateLightFade(dt: Float) {
        guard iblReady, iblFade < 1, let holder = iblHolder,
              var ibl = holder.components[ImageBasedLightComponent.self] else { return }
        iblFade = min(iblFade + dt / 0.6, 1)
        let k = iblFade * iblFade * (3 - 2 * iblFade)
        ibl.intensityExponent = style.iblExponent + log2(max(k, 1.0 / 256))
        holder.components.set(ibl)
        fallbackFill.light.intensity = style.fallbackFillIntensity * (1 - k)
        fallbackFill.isEnabled = k < 1
    }

    // MARK: - Startup readiness

    /// Ready = sweep + object (+ the always-present fallback light), then a few smooth frames. The IBL fades in later.
    private func checkStudioReady() {
        guard !isStudioReady, sweepReady, objectView != nil else { return }
        if !assetsReady { SceneTrace.mark("assets ready (waiting for smooth frames)") }
        assetsReady = true
    }

    /// Fades the scene in (the ARView was transparent) and starts background pre-baking for later objects.
    private func markStudioReady(timedOut: Bool) {
        guard !isStudioReady else { return }
        isStudioReady = true
        if DemoScenario.current != nil {
            let seconds = CACurrentMediaTime() - createdAt
            let pending = [sweepReady ? "" : "sweep", objectView == nil ? "object" : "",
                           assetsReady ? "smooth frames" : ""]
                .filter { !$0.isEmpty }.joined(separator: ", ")
            let note = timedOut ? " (timed out; pending: \(pending))" : ""
            print("SQUISH-T studio ready at \(String(format: "%.2f", seconds)) s\(note)")
            SceneTrace.mark("studio ready\(note)")
        }
        if let view = arView {
            UIView.animate(withDuration: fx.reduceMotion ? 0.1 : 0.25) { view.alpha = 1 }
        }
        // The IBL starts once the first frames are flowing (its prefilter is the heaviest startup job), and background
        // pre-baking waits longer still (CPU contention slowed early frames on CI).
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            self?.loadStudioLight()
            try? await Task.sleep(for: .seconds(4))
            self?.prebakeRemainingSweeps()
            self?.prewarmRemainingObjects()
        }
    }

    /// Every other gel wall, baked once in the background so object switches never wait.
    private func prebakeRemainingSweeps() {
        var gels: [UInt32] = ObjectKind.allCases.map { StudioEnvironment.gel(for: $0, golden: false) }
        gels.append(StudioEnvironment.gel(for: .bubbleWrap, golden: true))
        let missing = gels.filter { sweepTextures[$0] == nil }
        guard !missing.isEmpty else { return }
        let flip = style.sweepFlipV
        Task { @MainActor [weak self] in
            for gel in missing {
                let golden = gel == StudioEnvironment.gel(for: .bubbleWrap, golden: true)
                let box = await Task.detached(priority: .utility) { () -> ImageBox in
                    ImageBox(image: StudioEnvironment.sweepImage(gel: gel, golden: golden, flipV: flip))
                }.value
                guard let self else { return }
                if self.sweepTextures[gel] == nil, let texture = await StudioEnvironment.textureAsync(box.image, name: "sweep.\(gel)") {
                    self.sweepTextures[gel] = texture
                }
            }
        }
    }

    /// Heavy object meshes for every other object, built off the main actor at low priority.
    private func prewarmRemainingObjects() {
        let kinds = ObjectKind.allCases.filter { !warmedKinds.contains($0) && !ObjectMeshes.jobs(for: $0).isEmpty }
        guard !kinds.isEmpty else { return }
        Task { @MainActor [weak self] in
            for kind in kinds {
                let results = await Task.detached(priority: .utility) { () -> [(String, MeshData)] in
                    ObjectMeshes.build(kind)
                }.value
                guard let self else { return }
                for (key, data) in results { MeshCache.store(key, data) }
                self.warmedKinds.insert(kind)
            }
        }
    }

    // MARK: - Framing (§3.2)

    private func updateFraming(engine: PressEngine) {
        if framing == .foldAnvil { return } // FOLD PRESS: the camera is driven by FoldPressController
        guard let view = arView else { return }
        let size = view.bounds.size
        guard size.width > 1, size.height > 1 else { return }
        // Only switch pose between presses; mid-press rotation just relayouts (bible §6.4).
        let idle = (engine.phase == .idle || engine.phase == .armed) && engine.renderDepth < 0.01
        let wanted: Pose = (style.bookPoseRolls && size.width > size.height) ? .book : .tabletop
        if idle { pose = wanted }
        if size != framedSize || framedPose != pose {
            frame(size: size)
        }
    }

    private func frame(size: CGSize) {
        framedSize = size
        framedPose = pose
        let aspect = Float(size.width / max(size.height, 1))
        let rolled = pose == .book && aspect > 1
        let preset = style.preset(forAspect: rolled ? 1 / aspect : aspect)
        let pitch = preset.pitch * .pi / 180
        var fov = preset.fieldOfView
        if rolled {
            // The press axis now runs along the screen's long side: keep the preset's extent along it.
            let half = preset.fieldOfView * .pi / 360
            fov = 2 * atan(tan(half) / aspect) * 180 / .pi
        }
        baseFieldOfView = fov
        isBookPose = rolled
        camera.camera.fieldOfViewInDegrees = fov * fovScale
        camera.camera.near = style.nearPlane
        camera.camera.far = style.farPlane
        let forward = SIMD3<Float>(0, -sin(pitch), -cos(pitch))
        camera.look(at: preset.position + forward, from: preset.position, relativeTo: nil)
        if rolled {
            camera.orientation = camera.orientation * simd_quatf(angle: style.bookRoll * .pi / 180, axis: [0, 0, 1])
        }
    }

    // MARK: - Rest beat, power-on, sealed tag

    /// Outgoing specimen + mess: hold, slide back off the anvil and drop behind it (ease-in 0.35 s), reset the press,
    /// then drop the next object. Starting a press skips straight to the new object at rest.
    private func updateRestBeat(engine: PressEngine, context: FeedbackContext, dt: Float) {
        let pressing = engine.phase == .pressing || engine.measuredDepth > 0.01
        if outgoingActive {
            let hold: Float = context.reduceMotion ? 0.3 : 0.4
            let t = (sinceSet - hold) / 0.35
            if pressing || t >= 1 || (context.reduceMotion && sinceSet >= hold) {
                finishOutgoing()
            } else if t > 0 {
                let e = t * t
                let drop = max(e - 0.5, 0) / 0.5
                let offset = SIMD3<Float>(0, -0.3 * drop * drop, -0.2 * e)
                outgoing.position = offset
                fx.root.position = offset
            }
        }
        if let view = objectView, !view.entity.isEnabled, sinceSet >= dropAt || pressing {
            view.entity.isEnabled = true
            dropHeight = (context.reduceMotion || pressing) ? 0 : style.dropHeight
            dropVelocity = 0
            if dropHeight == 0 { landedAt = clock }
        }
        if let t = powerOn, isStudioReady {
            powerOn = t + dt > 0.8 ? nil : t + dt
        }
    }

    private func finishOutgoing() {
        guard outgoingActive else { return }
        for child in Array(outgoing.children) { child.removeFromParent() }
        outgoing.position = .zero
        fx.root.position = .zero
        fx.clear()
        rig.repair()
        outgoingActive = false
    }

    /// Touch presses never see the cover display, so give them a sealed beat: a paper tag swings from the crown.
    private func updateSealTag(engine: PressEngine, context: FeedbackContext, dt: Float) {
        if engine.phase == .sealed && lastPhase != .sealed && engine.usesVirtualHinge {
            // Exactly the tonnage the card will print (FOLD-REVIEW-4 F12: one scale, one mapping).
            let maxC = engine.lastResult?.maxCompression ?? engine.maxCompression
            let tons = PressGauge.recordTons(kind: kind, maxCompression: Double(maxC), seed: variant.seed)
            rig.showSealTag(tons: tons)
        } else if engine.phase == .revealing || engine.phase == .idle {
            rig.hideSealTag()
        }
        rig.updateSealTag(dt: dt, reduceMotion: context.reduceMotion)
        lastPhase = engine.phase
    }

    // MARK: - Juice

    private func makeState(compression: Float, ramCompression: Float, approach: Float, dt: Float, loaded: Bool,
                           closingSpeed: Float, reduceMotion: Bool, phase: PressPhase) -> PressVisualState {
        PressVisualState(compression: compression, ramCompression: ramCompression, ramFace: ramFace,
                         approach: approach, dt: dt, time: clock, closingSpeed: closingSpeed, loaded: loaded,
                         reduceMotion: reduceMotion, phase: phase)
    }

    private func updateDrop(dt: Float) {
        if dropHeight > 0 {
            dropVelocity -= style.dropGravity * dt
            dropHeight += dropVelocity * dt
            if dropHeight <= 0 {
                dropHeight = 0
                // Squash y 0.85 / xz 1.08 on contact, then spring back (response 0.35, damping 0.45).
                landingSquash.value = -0.15
                landingSquash.velocity = 0
                dropVelocity = 0
                landedAt = clock
            }
        }
        landingSquash.step(toward: 0, dt: dt)
    }

    /// Object-local micro-shake (never the screen) and the returned ±0.3 mm plate jitter.
    private func updateShake(engine: PressEngine, context: FeedbackContext, dt: Float, approach: Float) -> SIMD2<Float> {
        kick *= pow(0.5, dt / style.kickHalfLife)
        var offset = SIMD3<Float>(0, dropHeight, 0)
        let squash = clamp(landingSquash.value, -0.2, 0.2)
        // Anticipation stretch while falling (y 1.06), squash on landing.
        let stretch: Float = dropHeight > 0.004 ? 0.06 : 0
        var scale = SIMD3<Float>(1 - squash * 0.53, 1 + squash + stretch, 1 - squash * 0.53)
        var jitter = SIMD2<Float>.zero
        let resting = (engine.phase == .idle || engine.phase == .armed) && engine.renderDepth < 0.005 && dropHeight == 0
        if !context.reduceMotion {
            let c = Float(engine.measuredCompression)
            var amplitude = kick
            if engine.isLoaded && !engine.isHolding { amplitude += style.loadShake * (0.3 + c) }
            if amplitude > 1e-6 {
                offset.x += amplitude * sin(clock * 97) * cos(clock * 41)
                offset.z += amplitude * sin(clock * 73 + 1.3)
            }
            if engine.isLoaded {
                jitter = SIMD2(sin(clock * 131), cos(clock * 117)) * 0.0003 * min(c * 2, 1)
            }
            // Nervous pre-contact quiver as the ram closes in.
            if approach > 0.6 && approach < 1 && engine.phase == .pressing {
                let q = style.quiver * (approach - 0.6) / 0.4
                scale *= 1 + q * sin(clock * 120)
            }
            if resting {
                scale.y *= 1 + style.breathing * sin(clock * 2 * .pi * 0.35)
            }
        }
        objectSlot.position = offset
        objectSlot.scale = scale
        return jitter
    }

    /// First-run teaching: the platen dips a few mm every ~1.6 s (ease in-out) with a glow on the crosshead.
    /// Reduce Motion: glow only. Returns the downward offset of the ram face.
    private func teachingPulse(engine: PressEngine, context: FeedbackContext) -> Float {
        if engine.phase == .pressing || engine.measuredDepth > 0.01 { taught = true }
        // Touch press only (usesVirtualHinge — true until a hinge reports; Duo owners get the UI's ghost arc),
        // starting 1.2 s after the object has landed (bible §3.2 step 3), until the first drag.
        let teaching = isFirstPress && !taught && engine.phase == .armed && engine.usesVirtualHinge
            && engine.measuredDepth < 0.01 && dropHeight == 0 && !outgoingActive && clock - landedAt > 1.2
        guard teaching else {
            rig.setTeachGlow(0)
            teachWave = 0
            return 0
        }
        let phase = (clock - landedAt - 1.2).truncatingRemainder(dividingBy: 1.6) / 1.6
        let wave = 0.5 - 0.5 * cos(phase * 2 * .pi)
        teachWave = wave
        rig.setTeachGlow(0.12 + 0.3 * wave)
        return context.reduceMotion ? 0 : 0.004 * wave
    }

    private func updateFlash(dt: Float) {
        flashLevel *= pow(0.5, dt / style.flashHalfLife)
        if flashLevel < 50 { flashLevel = 0 }
        flash.isEnabled = flashLevel > 0
        flash.light.intensity = flashLevel
    }

    private func updateInstruments(engine: PressEngine, context: FeedbackContext, dt: Float, renderC: Float, approach: Float) {
        // Tonnage (FOLD-REVIEW-4 F12, the Fold crown's mapping on the same 0–80 t dial): approach twitch, then the
        // seed's base plus 44 t·c across the crush, sealing on exactly the record's tonnage; the Unsquishable pins it.
        let dialMax = Float(PressGauge.maxTons)
        var tons: Float = 0
        switch engine.phase {
        case .armed, .pressing:
            if engine.renderDepth < engine.mapping.contactT {
                tons = 0.6 * approach + min(abs(Float(engine.closingSpeed)) / 200, 1) * 0.25
            } else if kind == .unsquishable {
                tons = 10 + (dialMax - 10) * min(1, renderC * 1.6)
            } else {
                tons = Float(PressGauge.liveTons(compression: Double(renderC), seed: variant.seed))
            }
            peakTons = max(peakTons, tons)
        case .sealed:
            let maxC = engine.lastResult?.maxCompression ?? engine.maxCompression
            tons = kind == .unsquishable ? dialMax + 3
                : Float(PressGauge.recordTons(kind: kind, maxCompression: Double(maxC), seed: variant.seed))
        case .idle, .revealing:
            tons = 0
        }
        // Teaching: the needle twitches with the platen pulse (VISUAL-TARGET §6.1).
        tons += 1.5 * teachWave
        // Power-on beat (P2-1): the needle sweeps to full scale and back while the lamps flick on.
        if let t = powerOn, !context.reduceMotion { tons = t < 0.3 ? dialMax : 0 }
        // Slam warning (P0-5): a panicky needle and a red lamp while the press is slammed under load.
        let slamming = engine.isLoaded && engine.closingSpeed > engine.config.slamSpeed
        if slamming { rig.flashRed() }
        let buzz = kind == .unsquishable && engine.phase != .revealing && engine.phase != .idle && tons >= dialMax
        rig.updateGauge(tons: tons, dt: dt, tremor: tell && !context.reduceMotion, buzz: buzz && !context.reduceMotion,
                        panic: slamming && !context.reduceMotion, time: clock)
        let loaded = engine.isLoaded || engine.phase == .sealed
        let broken = kind == .unsquishable && rig.damage >= 3 && engine.phase != .revealing && engine.phase != .idle
        rig.updateLamps(dt: dt, loaded: loaded, broken: broken, powerOn: powerOn)

        // The Unsquishable: steam leaks from the barrel lip while the press strains.
        if kind == .unsquishable && engine.isLoaded && !context.reduceMotion {
            steamTimer -= dt
            if steamTimer <= 0 {
                steamTimer = 0.14
                var rng = SplitMix64(seed: UInt64(clock * 1000))
                fx.particles.emit(.dust, at: [Float.random(in: -0.02...0.02, using: &rng), PressRig.barrelBottom, 0.02],
                                  velocity: [0, 0.05, 0.01], color: Palette.cream, size: 0.012, life: 0.8, rng: &rng)
            }
        }
    }

    // MARK: - Decals (§3.6)

    /// A baked gaussian decal plane (unlit, no tone map, alpha in the texture).
    @MainActor
    private final class Decal {
        let entity: ModelEntity
        private let texture: TextureResource?
        private var alpha: Float = -1

        init(texture: TextureResource?, size: SIMD2<Float>, alpha: Float) {
            self.texture = texture
            entity = ModelEntity(mesh: .generatePlane(width: 1, depth: 1), materials: [])
            entity.scale = SIMD3(size.x, 1, size.y)
            ShadowCasting.off(entity)
            setAlpha(alpha)
        }

        func setAlpha(_ value: Float) {
            let a = clamp(value, 0, 1)
            guard abs(a - alpha) > 0.02 || (a == 0) != (alpha == 0) else { return }
            alpha = a
            entity.isEnabled = a > 0.005
            var material = UnlitMaterial(applyPostProcessToneMap: false)
            if let texture {
                material.color = .init(tint: .white, texture: .init(texture))
            } else {
                material.color = .init(tint: Palette.shadowInk)
            }
            material.blending = .transparent(opacity: .init(floatLiteral: a))
            entity.model?.materials = [material]
        }

        func size(_ s: SIMD2<Float>) {
            entity.scale = SIMD3(s.x, 1, s.y)
        }
    }

    private func gaussianTexture(sigma: Float) -> TextureResource? {
        let key = Int(sigma * 100)
        if let cached = gaussian[key] { return cached }
        let texture = StudioEnvironment.texture(StudioEnvironment.gaussianImage(sigma: sigma), name: "decal.\(key)")
        gaussian[key] = texture
        return texture
    }

    private func addDecal(sigma: Float, size: SIMD2<Float>, alpha: Float, at position: SIMD3<Float>) -> Decal {
        let decal = Decal(texture: gaussianTexture(sigma: sigma), size: size, alpha: alpha)
        decal.entity.position = position
        root.addChild(decal.entity)
        return decal
    }

    private func buildDecals() {
        // Static grounding.
        staticDecals.append(addDecal(sigma: 0.25, size: [0.18, 0.135], alpha: 0.45, at: [0, PressRig.bedTop + 0.0003, 0]))
        for side: Float in [-1, 1] {
            staticDecals.append(addDecal(sigma: 0.30, size: [0.04, 0.04], alpha: 0.40,
                         at: [side * PressRig.columnX, PressRig.bedTop + 0.0004, PressRig.columnZ]))
        }
        staticDecals.append(addDecal(sigma: 0.45, size: [0.36, 0.26], alpha: 0.35, at: [0.03, PressRig.floorY + 0.0003, -0.03]))
        staticDecals.append(addDecal(sigma: 0.40, size: [0.24, 0.016], alpha: 0.50, at: [0, PressRig.floorY + 0.0005, 0.075]))
        // Live: object AO, soft shadow, ram occlusion.
        aoDecal = addDecal(sigma: 0.25, size: [0.1, 0.1], alpha: style.aoAlpha, at: [0.003, 0.0003, -0.003])
        softDecal = addDecal(sigma: 0.50, size: [0.15, 0.15], alpha: style.softShadowAlpha, at: [0.012, 0.0004, -0.010])
        ramDecal = addDecal(sigma: 0.45, size: [0.13, 0.10], alpha: 0, at: [0.006, 0.0005, -0.004])
    }

    private func updateDecals(view: PressObjectView, approach: Float) {
        let footprint = view.footprint * 2 * view.shadowSpread
        aoDecal?.size([footprint * 1.05, footprint * 1.05 * 0.9])
        softDecal?.size([footprint * 1.8, footprint * 1.8 * 0.85])
        // Fade the object's grounding in with its drop (nothing on the anvil until it lands).
        let present: Float = view.entity.isEnabled ? clamp(1 - dropHeight / max(style.dropHeight, 0.001), 0, 1) : 0
        // Fold Press (FOLD-REVIEW-1 #9): no P-48 bed/floor decals; softer AO on the bright anvil field; the plate shade
        // covers the whole strike plate so the anvil visibly darkens as the lid closes.
        let fold = framing == .foldAnvil
        for decal in staticDecals where decal.entity.isEnabled == fold { decal.entity.isEnabled = !fold }
        let ao = fold ? style.foldAOAlpha : style.aoAlpha
        let soft = fold ? style.foldSoftShadowAlpha : style.softShadowAlpha
        aoDecal?.setAlpha(ao * present)
        softDecal?.setAlpha((soft + (style.softShadowCoveredAlpha - style.softShadowAlpha) * approach) * present)
        ramDecal?.size(fold ? [0.19, 0.15] : [0.13, 0.10])
        ramDecal?.setAlpha(style.ramOcclusionMax * approach * approach)
    }

    // MARK: - Studio

    private func buildSweep() {
        if let mesh = StudioEnvironment.sweepMesh() {
            // Placeholder until the baked sweep arrives: the floor colour, not tone-mapped (never the grey #CECBC5).
            sweep.model = ModelComponent(mesh: mesh, materials: [SceneMaterials.unlit(UIColor(hex: 0xF1E9DC))])
        }
        ShadowCasting.off(sweep)
    }

    /// Bakes (or reuses) the sweep texture for the current object's gel wall and swaps it in.
    private func applyGel() {
        let gel = StudioEnvironment.gel(for: kind, golden: variant.isGolden)
        arView?.environment.background = .color(UIColor(hex: gel))
        if let cached = sweepTextures[gel] {
            setSweep(cached)
            return
        }
        sweepRequest += 1
        let request = sweepRequest
        let golden = variant.isGolden
        let flip = style.sweepFlipV
        Task { @MainActor [weak self] in
            let box = await Task.detached(priority: .userInitiated) { () -> ImageBox in
                ImageBox(image: SceneTrace.measure("sweep image (off main)") {
                    StudioEnvironment.sweepImage(gel: gel, golden: golden, flipV: flip)
                })
            }.value
            guard let self else { return }
            SceneTrace.mark("sweep texture start (async)")
            guard let texture = await StudioEnvironment.textureAsync(box.image, name: "sweep.\(gel)") else {
                // Never block readiness on a missing texture: the tone-free floor-colour placeholder stays.
                SceneTrace.mark("sweep texture FAILED")
                self.sweepReady = true
                self.checkStudioReady()
                return
            }
            self.sweepTextures[gel] = texture
            if request == self.sweepRequest { self.setSweep(texture) }
        }
    }

    private func setSweep(_ texture: TextureResource) {
        var material = UnlitMaterial(applyPostProcessToneMap: false)
        material.color = .init(tint: .white, texture: .init(texture))
        sweep.model?.materials = [material]
        if !sweepReady { SceneTrace.mark("sweep applied") }
        sweepReady = true
        checkStudioReady()
    }

    private func buildLights() {
        let key = DirectionalLight()
        key.light.intensity = style.keyIntensity
        key.light.color = style.keyColor
        // Tighter shadow range = finer shadow map at product scale; more bias against acne (VISUAL-REVIEW-1 fix 4).
        key.shadow = DirectionalLightComponent.Shadow(maximumDistance: 1.2, depthBias: 2)
        key.look(at: [0, 0, 0], from: simd_normalize(style.keyDirection), relativeTo: nil)
        root.addChild(key)

        let rim = SpotLight()
        rim.light.intensity = style.rimIntensity
        rim.light.color = style.rimColor
        rim.light.innerAngleInDegrees = style.rimInner
        rim.light.outerAngleInDegrees = style.rimOuter
        rim.light.attenuationRadius = 2
        rim.look(at: [0, 0.05, 0], from: style.rimPosition, relativeTo: nil)
        root.addChild(rim)

        fallbackFill.light.intensity = style.fallbackFillIntensity
        fallbackFill.light.color = style.fillColor
        fallbackFill.light.attenuationRadius = 3
        fallbackFill.position = style.fallbackFillPosition
        root.addChild(fallbackFill)

        flash.light.intensity = 0
        flash.light.color = style.flashColor
        flash.light.attenuationRadius = 1.2
        flash.position = [0, 0.16, 0.22]
        flash.isEnabled = false
        root.addChild(flash)
    }

    /// `-squishDemo calib` (§3.5): grey and white cards on the sweep floor, angled 30° toward the key.
    private func buildCalibrationCards() {
        let grey = SceneMaterials.pbr(UIColor(hex: 0x767676), roughness: 1)
        let white = SceneMaterials.pbr(UIColor(hex: 0xF2F2F2), roughness: 1)
        for (x, material) in [(Float(-0.085), grey), (Float(0.085), white)] {
            let card = ModelEntity(mesh: .generateBox(width: 0.05, height: 0.07, depth: 0.002, cornerRadius: 0.001),
                                   materials: [material])
            card.position = [x, PressRig.floorY + 0.035, 0.10]
            card.orientation = simd_quatf(angle: -30 * .pi / 180, axis: [0, 1, 0])
            root.addChild(card)
        }
    }

    // MARK: - FOLD PRESS (design/FOLD-PRESS.md §2, §9.1): anvil-only framing for the iPhone Duo

    /// `.machine` is the P-48; `.foldAnvil` hides the rig and sweep, shows the Fold Press anvil plates and hands the
    /// camera to `FoldPressController` (which calls `setFoldStage` every frame, after `update`).
    private(set) var framing: FramingMode = .machine
    private var foldAnvil: Entity?

    func setFraming(_ mode: FramingMode, anvil: Entity? = nil) {
        let wasFold = framing == .foldAnvil
        framing = mode
        let fold = mode == .foldAnvil
        if wasFold && !fold {
            // Handing back to the P-48 ARView: re-add the camera so the new scene registers it as its camera.
            camera.removeFromParent()
            root.addChild(camera)
        }
        rig.root.isEnabled = !fold
        sweep.isEnabled = !fold
        // The Duo stage brings its own camera (a camera moved in from the P-48 ARView's scene isn't picked up).
        camera.isEnabled = !fold
        if foldAnvil !== anvil || !fold {
            foldAnvil?.removeFromParent()
            foldAnvil = fold ? anvil : nil
        }
        if let foldAnvil, foldAnvil.parent !== root { root.addChild(foldAnvil) }
        objectSlot.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
        if !fold {
            flash.position = [0, 0.16, 0.22]
            foldRimLight?.light.intensity = style.rimIntensity
            foldKeyLight?.light.intensity = style.keyIntensity
            setFoldIBLOffset(0)
            framedSize = .zero
        }
    }

    /// Fold-mode exposure (FOLD-REVIEW-1 #1): the IBL's EV relative to `style.iblExponent`.
    private var foldIBLOffset: Float = 0
    private var foldYaw: Float = 0
    private func setFoldIBLOffset(_ offset: Float) {
        guard abs(offset - foldIBLOffset) > 0.01, let holder = iblHolder,
              var ibl = holder.components[ImageBasedLightComponent.self] else { return }
        foldIBLOffset = offset
        ibl.intensityExponent = style.iblExponent + offset
        holder.components.set(ibl)
    }

    private var foldKeyLight: DirectionalLight? {
        root.children.first(where: { $0 is DirectionalLight }) as? DirectionalLight
    }

    /// The object on the anvil once it is built (meshes build asynchronously), for the fold scale and the print.
    var foldObject: (kind: ObjectKind, restHeight: Float)? {
        objectView.map { (kind, $0.restHeight) }
    }

    /// The flattened specimen's top-down extent in `frame`'s space (the Duo anvil's root, millimetres): the x/z centre
    /// and half extents of its visual bounds. The anvil's escaped droplets land clear of it (FOLD-REVIEW-5). Nil off
    /// the Duo stage, before the object lands, or if its bounds are empty.
    func foldSpecimenExtent(relativeTo frame: Entity) -> (centre: SIMD2<Float>, half: SIMD2<Float>)? {
        guard framing == .foldAnvil, let view = objectView, view.entity.isEnabled else { return nil }
        let bounds = view.entity.visualBounds(relativeTo: frame, excludeInactive: true)
        guard !bounds.isEmpty else { return nil }
        let centre = bounds.center, extents = bounds.extents
        guard centre.x.isFinite, centre.z.isFinite, extents.x.isFinite, extents.z.isFinite else { return nil }
        return (SIMD2(centre.x, centre.z), SIMD2(extents.x, extents.z) / 2)
    }

    /// The lean's pivot correction last added to `objectSlot.position`, and the position that produced, so a frame in
    /// which `update` did not rewrite the position never stacks a second correction (FOLD-REVIEW-3 N2).
    private var foldLeanShift: SIMD3<Float> = .zero
    private var foldLeanPosition: SIMD3<Float>?

    func setFoldStage(_ stage: FoldStage) {
        guard framing == .foldAnvil else { return }
        // Clamshell lean (§2.4, FOLD-REVIEW-3 N2): the squash tips the top away from the real hinge (+z), pivoting on
        // the base edge it tips toward, so the footprint stays put and no part of the base sinks into the plate. Book
        // pose also turns the object to the eye (yaw about the slot origin, applied first).
        objectSlot.orientation = simd_quatf(angle: stage.lean, axis: [1, 0, 0]) * simd_quatf(angle: stage.yaw, axis: [0, 1, 0])
        let current = objectSlot.position
        let unshifted = foldLeanPosition == current ? current - foldLeanShift : current
        let baseRadius = (objectView.map { $0.footprint * $0.shadowSpread } ?? 0) * objectSlot.scale.z
        foldLeanShift = FoldLean.pivotShift(lean: stage.lean, baseRadius: baseRadius)
        objectSlot.position = unshifted + foldLeanShift
        foldLeanPosition = objectSlot.position
        // Wedge shadow (FOLD-REVIEW-3 N13): the soft contact shadow (1.8× footprint) and the plate shade spilled past
        // the strike plate onto the enamel on the crease side. Runs after `updateDecals` each frame, which resets
        // their size, so this clamp never accumulates.
        if stage.plateHalfExtent.x > 0 && stage.plateHalfExtent.y > 0 {
            for decal in [softDecal, ramDecal].compactMap({ $0 }) {
                let p = decal.entity.position, s = decal.entity.scale
                let maxX = max(0, 2 * (stage.plateHalfExtent.x - abs(p.x)))
                let maxZ = max(0, 2 * (stage.plateHalfExtent.y - abs(p.z)))
                decal.size([min(s.x, maxX), min(s.z, maxZ)])
            }
        }
        foldYaw = stage.yaw
        flash.position = stage.flashPosition
        foldRimLight?.light.intensity = style.rimIntensity * stage.rimGain
        foldKeyLight?.light.intensity = style.keyIntensity * stage.keyGain
        setFoldIBLOffset(stage.iblOffset)
        if let foldAnvil, let iblHolder, !foldAnvil.components.has(ImageBasedLightReceiverComponent.self) {
            foldAnvil.components.set(ImageBasedLightReceiverComponent(imageBasedLight: iblHolder))
        }
    }

    private var foldRimLight: SpotLight? {
        root.children.first(where: { $0 is SpotLight }) as? SpotLight
    }
}
