import Foundation
import RealityKit
import simd
import UIKit

/// Rubber Duck (bible §4 #2, VISUAL-TARGET §5.2): the classic bath duck as one smooth SDF blob (body, chest, tail,
/// head, wings), a two-lobe beak, glossy eyes. The only object with a face, because it survives.
/// Squashes into a cartoon pancake (spreading faster than volume-preserving, so it reads from above), honks (beak
/// pops), the seam "bloops" (a 6% deflate and an air puff), and springs back a little with overshoot when the ram lifts
/// (elastic 35% plasticity in Core; height rebound capped at 15%, footprint latched at its widest).
/// Top-down tells (FOLD-REVIEW-4 F6): the head squashes on its own (CPU-deformed body blob) into an ellipse that
/// merges with the body, the beak and eyes ride it, the vinyl's highlight widens and dulls, and a darker wet ring
/// creeps out on the steel round the pancake.
@MainActor
final class DuckView: PressObjectView {
    let entity = Entity()
    /// Hero scale ×1.25 (VISUAL-REVIEW-1 fix 6): the model is authored at 0.085 m and scaled on `entity`.
    static let heroScale: Float = 1.25
    let restHeight: Float = 0.085 * DuckView.heroScale
    let footprint: Float = 0.052 * DuckView.heroScale
    private let minHeightRatio: Float = 0.18

    private let squash = Entity()
    /// The body blob, CPU-deformed so the head flattens on its own (FOLD-REVIEW-4 F6): without it the whole duck
    /// scaled uniformly in XZ and, top-down, the head stayed a perfect ball on the pancake.
    private let body: DeformableMesh
    private let beak: ModelEntity
    private var eyes: [(model: ModelEntity, rest: SIMD3<Float>)] = []
    private var seamRest: [(model: ModelEntity, rest: SIMD3<Float>)] = []
    /// Latched head squash progress (0 rest … 1 fully pressed) and the last value the mesh was deformed for.
    private var headC: Float = 0
    private var shapedC: Float = -1
    /// Highlight dulling level (quantised so the material is rebuilt a handful of times per press, never per frame).
    private var dullLevel = 0
    private let golden: Bool
    /// A darker wet ring on the steel just outside the pancake's edge (FOLD-REVIEW-4 F6), latched.
    private let wetRing: ModelEntity
    private var ringT: Float = 0
    private let fx: SceneFX
    private let look: Look
    private var rng = SplitMix64(seed: 0)
    private var deflate: Float = 1
    private var height = JiggleSpring(value: 1, velocity: 0, omega: 20, zeta: 0.4)
    private var beakPop = JiggleSpring(value: 0, velocity: 0, omega: 30, zeta: 0.3)
    private var spread: Float = 1
    /// Failure reads top-down too (FOLD-REVIEW-1 #2): a dark seam line along the back, and a vinyl skirt that
    /// squeezes out around the base so the footprint grows ≥ 1.3× ("flattened", not "bigger").
    private let seam = Entity()
    private var skirt = ModelEntity()
    private var seamPopped = false
    private var deepest: Float = 1
    private var popC: Float = 1
    /// The widest footprint so far and the furthest the skirt has squeezed out: both latched, so the duck never looks
    /// less pressed on unloading or at the reveal (FOLD-REVIEW-3 N6).
    private var widest: Float = 1
    private var skirtT: Float = 0
    /// The storyboard (OBJECT-STORYBOARDS §2): idle bob, beats, the face's squash steps, vinyl creases, seam strain.
    private let life: ObjectLife
    private var story: StoryCursor
    /// The face: 0 rest, 1 surprised (wide), 2 squint, 3 stretched ovals, 4 pancake (`DuckFace`). The eyes ease to it.
    private var faceLevel = 0
    private var faceScale = SIMD3<Float>(repeating: 1)
    private var creases: [ModelEntity] = []
    private var shownCreases = 0
    private var seamStrain = 0
    private var gave = false
    private let seamMaterials: [PhysicallyBasedMaterial]
    /// The vinyl's maps (3D-art round): painted eyes, the mould seam, orange-peel and a clearcoat breakup, and the
    /// crushed duck's creased, stress-whitened version, swapped in once (never per frame) when the head is mostly flat.
    private var bodyMaps: SurfaceMaps?
    private var creasedMaps: SurfaceMaps?
    private var creased = false
    /// The torn seam's pale, stress-whitened lips either side of the dark split (shown when the seam pops).
    private var seamLips: [(model: ModelEntity, rest: SIMD3<Float>)] = []
    private var skirtMaterial: PhysicallyBasedMaterial
    /// The painted-eye layout on the body texture (spherical UVs about the body blob's centre).
    private static let paint = ObjectMeshes.duckPaint()

    var shadowSpread: Float { spread }

    init(variant: PressVariant, fx: SceneFX) {
        self.fx = fx
        let look = Look(variant)
        self.look = look
        life = ObjectLife(seed: variant.seed, idle: .rock, amount: 0.035, rate: 0.45, pulseHz: 4, pulseDamping: 0.3)
        story = StoryCursor(.rubberDuck, seed: variant.seed)
        seamMaterials = [SceneMaterials.pbr(UIColor(hex: 0xFFF4C2), roughness: 0.5),
                         SceneMaterials.pbr(UIColor(hex: 0xD9B23A), roughness: 0.5),
                         SceneMaterials.pbr(UIColor(hex: 0x9A7414), roughness: 0.5)]
        rng = SplitMix64(seed: variant.seed ^ 0xD0C)
        golden = look.golden
        let bodyMaterial = Self.bodyMaterial(golden: look.golden, dull: 0, maps: nil)
        skirtMaterial = look.golden ? SceneMaterials.gold
            : SceneMaterials.enamel(Palette.duckYellow, roughness: 0.32, clearcoat: 0.7, clearcoatRoughness: 0.16)
        let beakMaterial = SceneMaterials.enamel(Palette.beakOrange, roughness: 0.30, clearcoat: 0.8, clearcoatRoughness: 0.1)
        let eyeMaterial = SceneMaterials.enamel(UIColor(hex: 0x1E1B24), roughness: 0.04, clearcoat: 1, clearcoatRoughness: 0.02)

        body = DeformableMesh(MeshCache.mesh("duck.body") { ObjectMeshes.duckBody() }, materials: [bodyMaterial], maxSpread: 1.6)
        let beakResource = MeshCache.resource("duck.beak") { ObjectMeshes.duckBeak() }
        beak = ModelEntity(mesh: beakResource ?? .generateSphere(radius: 0.01), materials: [beakMaterial])
        let wetMaterial = look.golden ? SceneMaterials.goldMess
            : SceneMaterials.enamel(UIColor(hex: 0xC99A00), roughness: 0.12, clearcoat: 1, clearcoatRoughness: 0.05, opacity: 0.35)
        wetRing = ModelEntity(mesh: MeshCache.resource("duck.skirt") { MeshKit.spreadDisc(seed: 0xD5C, height: 1, segments: 48, wobble: 0.08) }
                              ?? .generateSphere(radius: 0.01), materials: [wetMaterial])
        wetRing.position = [0, 0.00005, 0]
        wetRing.isEnabled = false
        squash.addChild(body.entity)
        squash.addChild(beak)
        for side: Float in [-1, 1] {
            let rest = SIMD3<Float>(0.035, 0.068, 0.012 * side)
            let eye = Part.add(cached: "duck.eye", { MeshKit.sphere(radius: 0.0034, segments: 24, rings: 12) }, eyeMaterial,
                               at: rest, to: squash)
            // A cartoon catchlight up toward the key (fidelity pass): it rides the eye, so it squashes with the face.
            let catchlight = Part.add(cached: "duck.catchlight", { MeshKit.sphere(radius: 0.0011, segments: 12, rings: 6) },
                                      SceneMaterials.unlit(UIColor(hex: 0xFFFFFF)), at: [0.0009, 0.0019, side * 0.0024], to: eye)
            ShadowCasting.off(catchlight)
            eyes.append((eye, rest))
        }
        // Seam: short dark segments following the top of the back, hidden until the seam pops.
        let seamMaterial = SceneMaterials.pbr(UIColor(hex: 0x9A7414), roughness: 0.5)
        let lipMaterial = look.golden ? SceneMaterials.pbr(UIColor(hex: 0xFFF1C4), roughness: 0.3, metallic: 1)
            : SceneMaterials.enamel(UIColor(hex: 0xFFF2B8), roughness: 0.45, clearcoat: 0.3, clearcoatRoughness: 0.3)
        var previous: SIMD3<Float>?
        for k in 0...10 {
            let x = -0.042 + 0.064 * Float(k) / 10
            let top = 0.026 + 0.026 * max(1 - (x / 0.038) * (x / 0.038), 0).squareRoot() + 0.0006
            // A ragged zigzag, not a ruled line: the torn split wanders either side of the mould seam.
            let point = SIMD3<Float>(x, top, (k % 2 == 0 ? 0.0014 : -0.0014) * (k % 3 == 0 ? 0.5 : 1))
            if let previous {
                let d = point - previous
                let length = simd_length(d)
                let along = simd_quatf(from: [1, 0, 0], to: d / max(length, 1e-6))
                let segment = MeshKit.model(MeshKit.roundedBox([length + 0.0008, 0.0016, 0.0024], radius: 0.0006, bevel: 0.0003),
                                            material: seamMaterial)
                segment.position = (point + previous) / 2
                segment.orientation = along
                seam.addChild(segment)
                seamRest.append((segment, segment.position))
                // The torn lips: pale, stretched vinyl a little wider and lower than the dark split.
                let lip = Part.add(cached: "duck.seam.lip", { MeshKit.roundedBox([1, 0.0011, 0.0046], radius: 0.0004, bevel: 0.0002) },
                                   lipMaterial, at: (point + previous) / 2 - SIMD3(0, 0.0003, 0), to: squash)
                lip.orientation = along
                lip.scale = SIMD3(length + 0.0012, 1, 1)
                lip.isEnabled = false
                seamLips.append((lip, lip.position))
            }
            previous = point
        }
        seam.isEnabled = false
        squash.addChild(seam)
        // The squeezed-out vinyl: a smooth, rolled lip with a soft organic wobble, orange-peel on its face
        // (EXPERIENCE-REVIEW-1 #5: the torn, notched rim read as a sawtooth pie crust; vinyl squeezes, it doesn't tear).
        skirt = ModelEntity(mesh: MeshCache.resource("duck.skirt.lip") {
            var disc = MeshKit.spreadDiscUV(seed: 0xD5C, height: 1, segments: 128, wobble: 0.11, tear: 0)
            disc.uvs = disc.uvs.map { $0 * 7 }
            return disc
        } ?? .generateSphere(radius: 0.01), materials: [skirtMaterial])
        skirt.isEnabled = false
        // Vinyl creases (hidden until their `.crease` beats): a pair at the neck, then one down the chest.
        let creaseMaterial = look.golden ? SceneMaterials.pbr(UIColor(hex: 0x9A7414), roughness: 0.4, metallic: 1)
            : SceneMaterials.pbr(UIColor(hex: 0xC99A1A), roughness: 0.45)
        for rest in DuckFace.creaseRests {
            let crease = Part.add(cached: "duck.crease", { MeshKit.roundedBox([0.012, 0.0012, 0.0016], radius: 0.0005, bevel: 0.0002) },
                                  creaseMaterial, at: rest.position, to: squash)
            crease.orientation = rest.orientation
            crease.isEnabled = false
            creases.append(crease)
        }
        entity.addChild(wetRing)
        entity.addChild(skirt)
        life.node.addChild(squash)
        entity.addChild(life.node)
        // 3/4 view, beak toward camera-right (+X forward, yaw −30°).
        entity.orientation = Part.yaw(-30)
        entity.scale = SIMD3(repeating: Self.heroScale)
        if !look.golden { loadSurface(beak: beak) }
    }

    /// The vinyl's maps land asynchronously (drawn off the main actor once per session); until then the plain enamel
    /// shows. The crushed set is fetched too, so the swap at the squash is instant.
    private func loadSurface(beak: ModelEntity) {
        let paint = Self.paint
        Task { @MainActor [weak self] in
            async let beakColour = SurfaceDetail.duckBeak()
            async let skirtNormal = SurfaceDetail.vinylTile()
            let maps = await SurfaceDetail.duckBody(paint)
            guard let self else { return }
            self.bodyMaps = maps
            self.applyBody()
            if let colour = await beakColour {
                var m = SceneMaterials.enamel(Palette.beakOrange, roughness: 0.30, clearcoat: 0.8, clearcoatRoughness: 0.1)
                m.baseColor = .init(tint: .white, texture: SurfaceDetail.wrapped(colour))
                beak.model?.materials = [m]
            }
            if let normal = await skirtNormal {
                self.skirtMaterial.normal = .init(texture: SurfaceDetail.tiled(normal))
                self.skirt.model?.materials = [self.skirtMaterial]
            }
            self.creasedMaps = await SurfaceDetail.duckCreased(paint)
            if self.headC > DuckSquash.creaseAt { self.applyBody() }
        }
    }

    /// Rebuilds the body's material at the current dulling step with whichever maps have landed (the creased set once
    /// the head is mostly flat). Called a handful of times per press, never per frame.
    private func applyBody() {
        guard !golden else { return }
        var maps = bodyMaps
        if headC > DuckSquash.creaseAt, let crushed = creasedMaps, crushed.colour != nil {
            creased = true
            let normal = crushed.normal ?? maps?.normal
            maps?.colour = crushed.colour
            maps?.normal = normal
        }
        let material = Self.bodyMaterial(golden: golden, dull: Float(dullLevel) / Float(DuckSquash.dullSteps), maps: maps)
        body.setMaterial(material, forSlot: 0)
    }

    static func bodyBlob() -> SDFBlob {
        var blob = SDFBlob()
        blob.add([0, 0.026, 0], [0.038, 0.026, 0.029])
        blob.add([0.019, 0.029, 0], radius: 0.021)
        blob.add([-0.032, 0.038, 0], [0.014, 0.017, 0.015], k: 0.008,
                 rotation: simd_quatf(angle: 35 * .pi / 180, axis: [0, 0, 1]))
        blob.add([0.020, 0.062, 0], radius: 0.023, k: 0.010)
        for side: Float in [-1, 1] {
            let rotation = simd_quatf(angle: side * 10 * .pi / 180, axis: [0, 1, 0])
                * simd_quatf(angle: -15 * .pi / 180, axis: [0, 0, 1])
            blob.add([-0.002, 0.030, 0.026 * side], [0.020, 0.011, 0.006], k: 0.004, rotation: rotation)
        }
        return blob
    }

    static func beakBlob() -> SDFBlob {
        var blob = SDFBlob()
        blob.floor = nil
        blob.add([0.044, 0.058, 0], [0.012, 0.0042, 0.009])
        blob.add([0.041, 0.0525, 0], [0.009, 0.003, 0.0075], k: 0.003)
        return blob
    }

    func surfaceHeight(compression c: Float) -> Float {
        HeightCurve.linear(c, rest: restHeight, minRatio: minHeightRatio)
    }

    func update(_ state: PressVisualState) {
        if life.update(state) {
            BeatFX.glint(fx, at: [0.022, 0.084, -0.008], in: entity, golden: golden, rng: &rng)
        }
        for beat in story.advance(to: state.compression) { onBeat(beat, state: state) }
        // The face eases to its current squash step (cheap: two transforms).
        // The fight (EXPERIENCE-REVIEW-1 #1): straining against the plate the eyes bulge and the seam whitens; at the
        // give the vinyl skirt squeezes out in the burst's frame.
        let strain = state.resistanceBulge
        if strain > 0.5 && seamStrain < 2 && !seamPopped { strainSeam() }
        if state.collapseLead > 0 && !gave {
            gave = true
            skirtT = min(skirtT + 0.3, 1)
            beakPop.kick(2)
        }
        let wanted = DuckFace.scale(level: faceLevel) * (1 + 0.3 * strain)
        if simd_length(wanted - faceScale) > 0.002 {
            faceScale = state.reduceMotion ? wanted : faceScale + (wanted - faceScale) * min(1, state.dt * 14)
            applyEyes()
        }
        // Elastic rebound is capped at 15% of the deepest squash (FOLD-PRESS §6.2, FOLD-REVIEW-2 #5): the reveal shows
        // the pressed specimen, not a duck that has re-inflated.
        var target = surfaceHeight(compression: state.compression) / restHeight
        deepest = min(deepest, target)
        target = min(target, deepest + 0.15 * (1 - deepest))
        // The hand owns the squash; on unloading the vinyl springs back with overshoot (ζ 0.4).
        if target < height.value {
            height.value = target
            height.velocity = 0
        } else {
            height.step(toward: target, dt: state.dt)
        }
        beakPop.step(toward: 0, dt: state.dt)
        let s = max(min(height.value, 1.05), 0.05)
        // Top-down the only squash cue is the footprint (FOLD-REVIEW-3 N4), so it spreads faster than volume-preserving
        // (XZ × s^−0.7) up to 1.7× on the Duo's strike plate (the P-48 anvil keeps 1.2×), latched at its widest.
        widest = max(widest, DuckSquash.spread(heightRatio: s, cap: fx.isFoldPress ? DuckSquash.foldCap : DuckSquash.machineCap))
        spread = widest * deflate
        squash.scale = SIMD3(spread, s * deflate, spread)
        // The head flattens on its own into an ellipse that merges with the body (FOLD-REVIEW-4 F6), latched like the
        // footprint so the reveal never shows a re-inflated ball.
        headC = max(headC, DuckSquash.headProgress(heightRatio: s, minRatio: minHeightRatio))
        if headC > shapedC + 0.004 {
            shapedC = headC
            let c = headC
            body.update { DuckSquash.headDeform($0, c: c) }
            applyEyes()
            for segment in seamRest {
                segment.model.position = DuckSquash.headDeform(segment.rest, c: c)
            }
            for lip in seamLips {
                lip.model.position = DuckSquash.headDeform(lip.rest, c: c)
            }
            for (i, crease) in creases.enumerated() where i < DuckFace.creaseRests.count {
                crease.position = DuckSquash.headDeform(DuckFace.creaseRests[i].position, c: c)
            }
            // Clearcoat 0.10 → 0.30 and base roughness 0.28 → 0.40: the highlight widens and dulls as it flattens; past
            // `creaseAt` the vinyl swaps to its creased, stress-whitened maps (once).
            let level = DuckSquash.dullLevel(c)
            let creaseNow = !creased && c > DuckSquash.creaseAt && creasedMaps?.colour != nil
            if (level > dullLevel || creaseNow) && !golden {
                dullLevel = max(dullLevel, level)
                applyBody()
            }
        }
        // The beak rides the head: its centre follows the deformed head, it flattens to an ellipse (Y × 0.5 at full
        // press), and the honk still pops it forward.
        let pop = 1 + max(beakPop.value, -0.3)
        let beakCentre = DuckSquash.beakCentre
        let beakScale = SIMD3<Float>(pop, DuckSquash.beakFlatten(headC), pop)
        beak.scale = beakScale
        beak.position = DuckSquash.headDeform(beakCentre, c: headC) - beakScale * beakCentre
            + SIMD3(beakCentre.x * (pop - 1), 0, 0)
        // The wet ring emerges from under the pancake's edge with the squash (local units, ×heroScale), latched.
        ringT = max(ringT, clamp((state.compression - 0.05) / 0.4, 0, 1))
        if ringT > 0 {
            wetRing.isEnabled = true
            let ring = DuckSquash.wetRingRadius(spread: spread, t: ringT)
            wetRing.scale = SIMD3(ring, 0.0004, ring * 0.8)
        }
        if seamPopped {
            // The skirt squeezes out from under the pancake with compression past the pop (local units, ×heroScale);
            // latched, so it never shrinks back when the phone reopens.
            skirtT = max(skirtT, clamp((state.compression - popC) / max(1 - popC, 0.05), 0, 1))
            let radius = DuckSquash.skirtRadius(spread: spread, t: skirtT)
            skirt.scale = SIMD3(radius, 0.0042, radius * 0.8)
            // The wet ring stays just outside the skirt.
            let ring = max(DuckSquash.wetRingRadius(spread: spread, t: ringT), radius * 1.08)
            wetRing.isEnabled = true
            wetRing.scale = SIMD3(ring, 0.0004, ring * 0.8)
            spread = max(spread, radius / 0.040 * 0.9)
        }
    }

    /// The vinyl: glossy yellow at rest; `dull` 0…1 widens and dulls the highlight (clearcoat roughness 0.10 → 0.30,
    /// base roughness 0.28 → 0.40) as the duck is pressed flat. With its maps: the painted colour, the orange-peel and
    /// seam normal, and the coat breakup modulating both roughnesses (its mean is ~0.7, so the scales keep the levels).
    private static func bodyMaterial(golden: Bool, dull: Float, maps: SurfaceMaps?) -> PhysicallyBasedMaterial {
        if golden { return SceneMaterials.gold }
        let d = clamp(dull, 0, 1)
        var material = SceneMaterials.enamel(Palette.duckYellow, roughness: 0.28 + 0.12 * d, clearcoat: 0.8,
                                             clearcoatRoughness: 0.10 + 0.20 * d)
        if let colour = maps?.colour { material.baseColor = .init(tint: .white, texture: SurfaceDetail.wrapped(colour)) }
        if let normal = maps?.normal { material.normal = .init(texture: SurfaceDetail.wrapped(normal)) }
        if let coat = maps?.rough {
            material.roughness = .init(scale: (0.28 + 0.12 * d) / 0.7, texture: SurfaceDetail.wrapped(coat))
            material.clearcoatRoughness = .init(scale: (0.10 + 0.20 * d) / 0.7, texture: SurfaceDetail.wrapped(coat))
        }
        material.emissiveColor = .init(color: UIColor(hex: 0xFFB000))
        material.emissiveIntensity = 0.04
        return material
    }

    func fracture(index: Int, isFailure: Bool, state: PressVisualState) {
        if isFailure {
            // Seam pop: a comic "bloop" — slight permanent deflate and a puff of air from the tail.
            deflate = 0.94
            height.kick(-1.5)
            seamPopped = true
            popC = state.compression
            seam.isEnabled = true
            for segment in seamRest { segment.model.model?.materials = [seamMaterials[2]] }
            for lip in seamLips { lip.model.isEnabled = true }
            faceLevel = max(faceLevel, 3)
            life.kick(1.2)
            skirt.isEnabled = true
            let at = entity.convert(position: [-0.04, 0.03, 0], to: fx.root)
            fx.particles.burst(.dust, count: 5, at: at, speed: 0.08 * max(fx.motionScale, 0.4),
                               colors: [UIColor(hex: 0xFFFDF6)], size: 0.004...0.008, upBias: 0.3, life: 0.5, rng: &rng)
        } else {
            // Honk: the beak pops and a little air ring leaves it; the face goes wide again for a beat.
            beakPop.kick(3)
            life.kick(0.9)
            let at = entity.convert(position: [0.055, 0.055, 0], to: fx.root)
            fx.particles.burst(.dust, count: 3, at: at, speed: 0.05, colors: [UIColor(hex: 0xFFFDF6)],
                               size: 0.003...0.005, upBias: 0.1, life: 0.35, rng: &rng)
        }
    }

    func handle(_ event: PressEvent, state: PressVisualState) {
        switch event {
        case .contact:
            beakPop.kick(1)
        case .preFailureTell:
            life.tremor(0.3)
        default:
            break
        }
    }

    private func applyEyes() {
        for eye in eyes {
            eye.model.position = DuckSquash.eyePosition(rest: eye.rest, c: headC)
            eye.model.scale = SIMD3(1, DuckSquash.eyeFlatten(headC), 1) * faceScale
        }
    }

    /// The seam shows before it pops: pale, then darker (stress whitening on vinyl), then the popped seam.
    private func strainSeam() {
        guard !seamPopped else { return }
        seamStrain = min(seamStrain + 1, 2)
        seam.isEnabled = true
        let material = seamMaterials[seamStrain - 1]
        for segment in seamRest { segment.model.model?.materials = [material] }
    }

    /// One storyboard beat (OBJECT-STORYBOARDS §2).
    private func onBeat(_ beat: StoryBeat, state: PressVisualState) {
        switch beat.kind {
        case .kiss:
            beakPop.kick(1.5)
            life.kick(0.8)
            BeatFX.glint(fx, at: [0.022, 0.084, -0.008], in: entity, golden: golden, rng: &rng)
        case .bulge:
            life.kick(1.0)
            faceLevel = max(faceLevel, 1)
            if beat.ordinal > 0 { BeatFX.puff(fx, at: [-0.045, 0.012, 0], in: entity, count: 3, rng: &rng) }
        case .squeak:
            beakPop.kick(2.5)
            let at: SIMD3<Float> = beat.ordinal == 0 ? [0.058, 0.054, 0] : [-0.048, 0.034, 0]
            BeatFX.puff(fx, at: at, in: entity, count: 3, rng: &rng)
        case .squash:
            faceLevel = max(faceLevel, min(2 + beat.ordinal, DuckFace.levels - 1))
            life.kick(0.6)
        case .crease:
            let upTo = beat.ordinal == 0 ? 2 : creases.count
            for i in shownCreases..<max(upTo, shownCreases) where i < creases.count { creases[i].isEnabled = true }
            shownCreases = max(shownCreases, min(upTo, creases.count))
            life.kick(0.5)
        case .wobble:
            life.tremor(0.25, level: 0.7)
            beakPop.kick(1)
        case .sheen:
            BeatFX.glint(fx, at: [-0.01, 0.05, 0.012], in: entity, golden: golden, rng: &rng)
            BeatFX.glint(fx, at: [0.02, 0.07, -0.012], in: entity, count: 1, golden: golden, rng: &rng)
        case .strain:
            strainSeam()
            life.tremor(0.15, level: 0.5)
        case .tell:
            strainSeam()
            life.tremor(0.3)
            if beat.ordinal > 0 { BeatFX.puff(fx, at: [-0.02, 0.05, 0], in: entity, count: 2, rng: &rng) }
        case .ooze:
            BeatFX.puff(fx, at: [-0.03, 0.035, 0], in: entity, count: 5, speed: 0.07, rng: &rng)
            life.kick(0.6)
        case .settle:
            BeatFX.puff(fx, at: [-0.045, 0.01, 0], in: entity, count: 2, rng: &rng)
            BeatFX.glint(fx, at: [0.0, 0.02, 0.0], in: entity, count: 1, golden: golden, rng: &rng)
        default:
            life.kick(0.5)
        }
    }
}

/// The duck's cartoon face steps and its vinyl creases (OBJECT-STORYBOARDS §2), pure so SquishTests can pin them.
/// The eyes squash with the head; nothing is ever damaged (bible content rule: faces survive).
enum DuckFace {
    static let levels = 5

    /// Eye scale multipliers (x along the body, y up, z sideways): rest, surprised, squint, stretched ovals, pancake.
    static func scale(level: Int) -> SIMD3<Float> {
        switch clamp(level, 0, levels - 1) {
        case 1: return SIMD3(1.2, 1.2, 1.2)
        case 2: return SIMD3(1.15, 0.55, 1.25)
        case 3: return SIMD3(1.3, 0.45, 1.45)
        case 4: return SIMD3(1.45, 0.35, 1.6)
        default: return SIMD3(repeating: 1)
        }
    }

    /// Crease rest poses (duck-local, before the hero scale): two at the neck, one down the chest.
    static let creaseRests: [(position: SIMD3<Float>, orientation: simd_quatf)] = [
        (SIMD3(0.014, 0.047, 0.0195), simd_quatf(angle: 0.35, axis: [0, 1, 0]) * simd_quatf(angle: -0.5, axis: [1, 0, 0])),
        (SIMD3(0.014, 0.047, -0.0195), simd_quatf(angle: -0.35, axis: [0, 1, 0]) * simd_quatf(angle: 0.5, axis: [1, 0, 0])),
        (SIMD3(0.0385, 0.026, 0.0), simd_quatf(angle: .pi / 2, axis: [0, 1, 0]) * simd_quatf(angle: -1.2, axis: [0, 0, 1])),
    ]
}

/// The duck's top-down squash numbers (FOLD-REVIEW-3 N4/N6), pure so SquishTests can pin them.
enum DuckSquash {
    /// Footprint cap on the Duo's strike plate (was 1.2): at 1.7 the pancake and its skirt still fit the plate.
    static let foldCap: Float = 1.7
    /// Footprint cap on the P-48 anvil, whose bed is ~30 % smaller relative to the duck.
    static let machineCap: Float = 1.2
    /// Cartoon spread: faster than volume-preserving (1/√s) so 120° → 75° reads from above (≈ +35 % at s 0.65).
    static let exponent: Float = 0.7

    /// XZ scale for the height ratio `s` (1 = rest), never below 1, clamped at `cap`.
    static func spread(heightRatio s: Float, cap: Float) -> Float {
        min(max(pow(max(s, 0.05), -exponent), 1), cap)
    }

    /// The vinyl skirt's radius (duck-local metres) for the body's `spread` and the post-pop progress `t`.
    static func skirtRadius(spread: Float, t: Float) -> Float {
        0.040 * spread * (1.05 + 0.25 * clamp(t, 0, 1))
    }

    /// The darker wet ring on the steel (duck-local metres): hidden under the body's edge at `t` 0, ~6 mm proud at 1.
    static func wetRingRadius(spread: Float, t: Float) -> Float {
        0.040 * spread * (0.95 + 0.15 * clamp(t, 0, 1))
    }

    // MARK: Head squash (FOLD-REVIEW-4 F6), duck-local authoring units (before the ×1.25 hero scale)

    /// The head sphere of the body blob, and the neck height it flattens down onto.
    static let headCentre = SIMD3<Float>(0.020, 0.062, 0)
    static let neckY: Float = 0.045
    /// The head stretches about a point near its front (where the beak sits), so it spreads back over the body and
    /// the beak barely moves: the duck stays on its plate (+40 pt).
    static let stretchAnchorX: Float = 0.034
    static let headSlide: Float = 0.0015
    /// Full weight inside the head, fading to 0 over 26 mm (wide enough that the stretch never folds the mesh).
    static let weightInner: Float = 0.024
    static let weightOuter: Float = 0.050
    static let dullSteps = 5
    /// Head progress past which the vinyl shows its creased, stress-whitened maps (3D-art round).
    static let creaseAt: Float = 0.6
    /// The beak blob's centre (`ObjectMeshes.duckBeak`).
    static let beakCentre = SIMD3<Float>(0.043, 0.0555, 0)

    /// 0 at rest … 1 at the minimum height ratio.
    static func headProgress(heightRatio s: Float, minRatio: Float) -> Float {
        clamp((1 - s) / max(1 - minRatio, 0.05), 0, 1)
    }

    /// Head scale at progress `c`: X (along the body) × (1 + 0.35c), Y × (1 − 0.75c), Z × (1 + 0.10c), so top-down it
    /// is an ellipse elongated along the body, never a round ball.
    static func headScale(_ c: Float) -> SIMD3<Float> {
        let c = clamp(c, 0, 1)
        return SIMD3(1 + 0.35 * c, 1 - 0.75 * c, 1 + 0.10 * c)
    }

    static func headWeight(_ p: SIMD3<Float>) -> Float {
        let d = simd_length(p - headCentre)
        let t = clamp((d - weightInner) / (weightOuter - weightInner), 0, 1)
        return 1 - t * t * (3 - 2 * t)
    }

    /// Moves a rest point of the body (or anything riding the head) for head progress `c`: the head flattens down
    /// onto the neck (a C¹ ramp, so no crease at the neck line), stretches into an ellipse and slides forward a little.
    static func headDeform(_ p: SIMD3<Float>, c: Float) -> SIMD3<Float> {
        let c = clamp(c, 0, 1)
        guard c > 0 else { return p }
        let w = headWeight(p)
        guard w > 0 else { return p }
        let k = headScale(c)
        let e: Float = 0.004
        let q = p.y - neckY
        let ramp: Float = q <= -e ? 0 : (q >= e ? q : (q + e) * (q + e) / (4 * e))
        let x = p.x + w * ((p.x - stretchAnchorX) * (k.x - 1) + headSlide * c)
        let y = p.y - w * (1 - k.y) * ramp
        let z = p.z + w * p.z * (k.z - 1)
        return SIMD3(x, y, z)
    }

    /// An eye's centre: pushed out from the head by up to 1.5 mm before the deform, so it stays proud of the
    /// flattened head instead of sinking into it.
    static func eyePosition(rest: SIMD3<Float>, c: Float) -> SIMD3<Float> {
        let out = rest - headCentre
        let length = simd_length(out)
        let push = length > 1e-6 ? out / length * (0.0015 * clamp(c, 0, 1)) : .zero
        return headDeform(rest + push, c: c)
    }

    static func eyeFlatten(_ c: Float) -> Float { 1 - 0.3 * clamp(c, 0, 1) }
    /// The beak flattens to an ellipse: Y × 0.5 at full press.
    static func beakFlatten(_ c: Float) -> Float { 1 - 0.5 * clamp(c, 0, 1) }

    /// Highlight dulling level 0…`dullSteps` for head progress `c`.
    static func dullLevel(_ c: Float) -> Int {
        Int((clamp(c, 0, 1) * Float(dullSteps)).rounded(.down))
    }
}
