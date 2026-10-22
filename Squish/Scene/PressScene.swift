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

    // Placement drop
    private var dropHeight: Float = 0
    private var dropVelocity: Float = 0
    private var landingSquash = JiggleSpring(value: 0, velocity: 0, omega: 2 * .pi / 0.35, zeta: 0.45)

    // Framing
    private enum Pose { case tabletop, book }
    private var pose: Pose = .tabletop
    private var framedSize: CGSize = .zero
    private var framedPose: Pose?

    init() {
        root.addChild(sweep)
        root.addChild(rig.root)
        root.addChild(objectSlot)
        root.addChild(fx.root)
        fx.debris.setBounds(min: -PressRig.anvilHalf, max: PressRig.anvilHalf)
        fx.particles.minXZ = -PressRig.anvilHalf
        fx.particles.maxXZ = PressRig.anvilHalf
        buildSweep()
        buildDecals()
        buildLights()
        root.addChild(camera)
        frame(size: CGSize(width: 402, height: 874))
        if DemoScenario.current?.has("calib") == true { buildCalibrationCards() }
        loadStudioLight()
    }

    // MARK: - Contract

    func setObject(_ kind: ObjectKind, variant: PressVariant) {
        self.kind = kind
        self.variant = variant
        objectView?.entity.removeFromParent()
        fx.clear()
        rig.repair()
        let view = PressObjectFactory.make(kind, variant: variant, fx: fx)
        objectSlot.addChild(view.entity)
        objectView = view
        ramFace = PressRig.homeFace
        ramVelocity = 0
        hitStop = 0
        slowMo = 0
        failureHold = 0
        kick = 0
        tell = false
        peakTons = 0
        // Squash-and-stretch landing (bible §3.1 beat 0; §6.12). Reduce Motion: appears at rest.
        dropHeight = fx.reduceMotion ? 0 : style.dropHeight
        dropVelocity = 0
        landingSquash = JiggleSpring(value: 0, velocity: 0, omega: 2 * .pi / 0.35, zeta: 0.45)
        let state = makeState(compression: 0, ramCompression: 0, approach: 0, dt: 0, loaded: false,
                              closingSpeed: 0, reduceMotion: fx.reduceMotion, phase: .idle)
        view.update(state)
        lastState = state
        applyGel()
    }

    func update(engine: PressEngine, context: FeedbackContext, dt: Float) {
        guard let view = objectView else { return }
        let dt = min(max(dt, 0), 1.0 / 20.0)
        clock += dt
        fx.reduceMotion = context.reduceMotion
        updateFraming(engine: engine)

        let contactT = Float(engine.config.contactT)
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
        fx.step(dt: fxDt, ceiling: ramFace, plateHalfExtent: rig.plateHalfExtent)

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
            view.handle(event, state: state)
        case let .fracture(index, isFailure):
            view.fracture(index: index, isFailure: isFailure, state: state)
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

    func snapshot() async -> UIImage? {
        guard let view = arView else { return nil }
        return await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            view.snapshot(saveToHDR: false) { image in
                continuation.resume(returning: image)
            }
        }
    }

    // MARK: - Hosting

    /// Called by PressSceneView once the ARView exists.
    func attach(to view: ARView) {
        arView = view
        framedSize = .zero
        view.environment.background = .color(UIColor(hex: StudioEnvironment.gel(for: kind, golden: variant.isGolden)))
    }

    private func loadStudioLight() {
        let exponent = style.iblExponent
        let turns = style.iblQuarterTurns
        Task { @MainActor [weak self] in
            guard let holder = await StudioEnvironment.makeLight(exponent: exponent), let self else { return }
            holder.orientation = simd_quatf(angle: Float(turns) * .pi / 2, axis: [0, 1, 0])
            self.root.addChild(holder)
            self.iblHolder = holder
            let receiver = ImageBasedLightReceiverComponent(imageBasedLight: holder)
            for entity in [self.root, self.rig.root, self.objectSlot, self.fx.root] {
                entity.components.set(receiver)
            }
        }
    }

    // MARK: - Framing (§3.2)

    private func updateFraming(engine: PressEngine) {
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
        camera.camera.fieldOfViewInDegrees = fov
        camera.camera.near = style.nearPlane
        camera.camera.far = style.farPlane
        let forward = SIMD3<Float>(0, -sin(pitch), -cos(pitch))
        camera.look(at: preset.position + forward, from: preset.position, relativeTo: nil)
        if rolled {
            camera.orientation = camera.orientation * simd_quatf(angle: style.bookRoll * .pi / 180, axis: [0, 0, 1])
        }
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
        let teaching = isFirstPress && !taught && engine.phase == .armed && engine.usesVirtualHinge
            && engine.measuredDepth < 0.01 && dropHeight == 0
        guard teaching else {
            rig.setTeachGlow(0)
            return 0
        }
        let phase = clock.truncatingRemainder(dividingBy: 1.6) / 1.6
        let wave = 0.5 - 0.5 * cos(phase * 2 * .pi)
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
        // Tonnage: approach twitch, then 4 → 56 t across the crush; the Unsquishable pins it past 60.
        var tons: Float = 0
        switch engine.phase {
        case .armed, .pressing:
            if engine.renderDepth < engine.config.contactT {
                tons = 0.6 * approach + min(abs(Float(engine.closingSpeed)) / 200, 1) * 0.25
            } else if kind == .unsquishable {
                tons = 8 + 60 * renderC
            } else {
                tons = 4 + 52 * renderC
            }
            peakTons = max(peakTons, tons)
        case .sealed:
            tons = max(peakTons, kind == .unsquishable ? 64 : 50)
        case .idle, .revealing:
            tons = 0
        }
        let buzz = kind == .unsquishable && engine.phase != .revealing && engine.phase != .idle && tons >= 60
        rig.updateGauge(tons: tons, dt: dt, tremor: tell && !context.reduceMotion, buzz: buzz && !context.reduceMotion, time: clock)
        let loaded = engine.isLoaded || engine.phase == .sealed
        let broken = kind == .unsquishable && rig.damage >= 3 && engine.phase != .revealing && engine.phase != .idle
        rig.updateLamps(dt: dt, loaded: loaded, broken: broken)

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
        _ = addDecal(sigma: 0.25, size: [0.165, 0.125], alpha: 0.45, at: [0, PressRig.bedTop + 0.0003, 0])
        for side: Float in [-1, 1] {
            _ = addDecal(sigma: 0.30, size: [0.04, 0.04], alpha: 0.40,
                         at: [side * PressRig.columnX, PressRig.bedTop + 0.0004, PressRig.columnZ])
        }
        _ = addDecal(sigma: 0.45, size: [0.36, 0.26], alpha: 0.35, at: [0.03, PressRig.floorY + 0.0003, -0.03])
        _ = addDecal(sigma: 0.40, size: [0.24, 0.016], alpha: 0.50, at: [0, PressRig.floorY + 0.0005, 0.075])
        // Live: object AO, soft shadow, ram occlusion.
        aoDecal = addDecal(sigma: 0.35, size: [0.1, 0.1], alpha: style.aoAlpha, at: [0.003, 0.0003, -0.003])
        softDecal = addDecal(sigma: 0.50, size: [0.15, 0.15], alpha: style.softShadowAlpha, at: [0.012, 0.0004, -0.010])
        ramDecal = addDecal(sigma: 0.45, size: [0.16, 0.11], alpha: 0, at: [0.006, 0.0005, -0.004])
    }

    private func updateDecals(view: PressObjectView, approach: Float) {
        let footprint = view.footprint * 2 * view.shadowSpread
        aoDecal?.size([footprint * 1.15, footprint * 1.15 * 0.9])
        softDecal?.size([footprint * 1.8, footprint * 1.8 * 0.85])
        aoDecal?.setAlpha(style.aoAlpha)
        softDecal?.setAlpha(style.softShadowAlpha + (style.softShadowCoveredAlpha - style.softShadowAlpha) * approach)
        ramDecal?.setAlpha(style.ramOcclusionMax * approach * approach)
    }

    // MARK: - Studio

    private func buildSweep() {
        if let mesh = StudioEnvironment.sweepMesh() {
            sweep.model = ModelComponent(mesh: mesh, materials: [SceneMaterials.unlit(Palette.backdrop)])
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
        let size = style.sweepTextureSize
        let flip = style.sweepFlipV
        Task { @MainActor [weak self] in
            let box = await Task.detached(priority: .userInitiated) { () -> ImageBox in
                ImageBox(image: StudioEnvironment.sweepImage(gel: gel, golden: golden, size: size, flipV: flip))
            }.value
            guard let self, let texture = StudioEnvironment.texture(box.image, name: "sweep.\(gel)") else { return }
            self.sweepTextures[gel] = texture
            if request == self.sweepRequest { self.setSweep(texture) }
        }
    }

    private func setSweep(_ texture: TextureResource) {
        var material = UnlitMaterial(applyPostProcessToneMap: false)
        material.color = .init(tint: .white, texture: .init(texture))
        sweep.model?.materials = [material]
    }

    private func buildLights() {
        let key = DirectionalLight()
        key.light.intensity = style.keyIntensity
        key.light.color = style.keyColor
        key.shadow = DirectionalLightComponent.Shadow(maximumDistance: 2.5, depthBias: 1)
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

        flash.light.intensity = 0
        flash.light.color = style.flashColor
        flash.light.attenuationRadius = 1.2
        flash.position = [0, 0.16, 0.22]
        flash.isEnabled = false
        root.addChild(flash)
    }

    /// `-squishDemo calib` (§3.5): grey and white cards on the bed, angled 30° toward the key.
    private func buildCalibrationCards() {
        let grey = SceneMaterials.pbr(UIColor(hex: 0x767676), roughness: 1)
        let white = SceneMaterials.pbr(UIColor(hex: 0xF2F2F2), roughness: 1)
        for (x, material) in [(Float(-0.085), grey), (Float(0.085), white)] {
            let card = ModelEntity(mesh: .generateBox(width: 0.05, height: 0.07, depth: 0.002, cornerRadius: 0.001),
                                   materials: [material])
            card.position = [x, PressRig.bedTop + 0.035, 0.06]
            card.orientation = simd_quatf(angle: -30 * .pi / 180, axis: [0, 1, 0])
            root.addChild(card)
        }
    }
}
