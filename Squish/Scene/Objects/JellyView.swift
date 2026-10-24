import Foundation
import RealityKit
import simd
import UIKit

/// Jelly (bible §4 #3, VISUAL-TARGET §5.3): a fluted raspberry mould jelly. Fake SSS: a translucent shell
/// (CPU-deformed `DeformableMesh`) over an opaque darker core. Wobble springs (ζ 0.25) for idle life and impacts.
/// Fracture 0 (skin split, ~0.30): droplets squirt from a side and a small overflow spreads.
/// Fracture 1 (failure splat, ~0.55): the body splorts — a glossy spread disc grows to Ø 0.15 with 6–10 blobs out
/// at the sides, droplets land and stay. Surprise `fruitPieces`: candy cubes between core and shell; some pop out.
/// On the Duo the shell's bulge, the disc and the splorts stay inside the strike plate + 16 pt *as seen* (FOLD-REVIEW-5
/// N11: the anamorphic eye throws everything with height toward the crease, so a squashed shell that was contained
/// on the glass still drew ~70 pt past the plate once it re-inflated to the plastic ratchet at the reveal). Once it
/// has splatted the jelly never re-gels (the height is latched), and the gloss mattes in steps as it flattens (F14).
/// Once the plates part after the splat (released, or the reveal) the pressed slab relaxes into a puddle
/// (`JellyPuddle`, FOLD-REVIEW-7 N9): a glossy, lobed, flat pool ≤ 35 % of the pressed height with a raised rim, held
/// inside the strike plate, the core flattened inside it, the splorts reduced to beads on its rim and one dark tear
/// across its skin.
@MainActor
final class JellyView: PressObjectView {
    let entity = Entity()
    let restHeight: Float = 0.0765
    let footprint: Float = 0.049
    private let minHeightRatio: Float = 0.13

    private let fx: SceneFX
    private let look: Look
    private var rng = SplitMix64(seed: 0)
    private let shell: DeformableMesh
    private let core: ModelEntity
    private let spreadDisc: ModelEntity
    private var splorts: [(entity: ModelEntity, direction: SIMD2<Float>, size: Float)] = []
    private var fruit: [(entity: ModelEntity, rest: SIMD3<Float>)] = []
    private var wobbleX = JiggleSpring(value: 0, velocity: 0, omega: 2 * .pi * 1.8, zeta: 0.25)
    private var wobbleZ = JiggleSpring(value: 0, velocity: 0, omega: 2 * .pi * 1.6, zeta: 0.25)
    private var bounce = JiggleSpring(value: 0, velocity: 0, omega: 2 * .pi * 2.4, zeta: 0.3)
    private var split = false
    private var splat = false
    private var splatC: Float = 1
    private var lastKey = SIMD4<Float>(repeating: -1)
    private var spread: Float = 1
    /// The lowest height ratio reached since the splat (1 until then): a splatted jelly stays splatted.
    private var latchedS: Float = 1
    /// The spread's progress past the split/splat, latched at its widest.
    private var spreadT: Float = 0
    private let dropColors: [UIColor]
    /// The Duo strike plate + 16 pt (fx metres): on the Fold Press the shell, the splat disc and the splorts are
    /// softly contained inside it (FOLD-REVIEW-4 F14, FOLD-REVIEW-5 N11).
    private let containment: SIMD2<Float>
    /// Gloss level 0…`JellySpread.mattSteps`: the flattened top and the splat lose their mirror finish as the jelly
    /// spreads, so a hard studio-light edge can't read as a straight "shading seam" across the blob (F14).
    private var mattLevel = 0
    private let golden: Bool
    /// The puddle (FOLD-REVIEW-7 N9): 0 = the pressed slab … 1 = relaxed into a puddle. Starts once the plates part
    /// after the splat and never goes back.
    private var relaxing = false
    private var relax: Float = 0
    private var lastRelax: Float = -1
    private var glossed = false
    private let rim: JellyPuddle.Rim
    /// The strike plate (no padding) on the Duo: the puddle stays inside it.
    private let plateHalf: SIMD2<Float>
    /// The tear across the puddle's skin (shown once it has relaxed).
    private var tear: [ModelEntity] = []
    /// The storyboard (OBJECT-STORYBOARDS §3): idle wobble, beats, gel squeezed from the pinch line, taut skin.
    private let life: ObjectLife
    private var story: StoryCursor
    private let ooze: OozeRing
    /// Skin tautness 0…`JellySpread.tautSteps` (the gloss and glow rise before it splits).
    private var taut = 0

    var shadowSpread: Float { spread }

    static var profile: [SIMD2<Float>] { ObjectMeshes.jellyProfile }

    /// Fluted mould mesh: r(y, θ) = r₀(y)·(1 + 0.07·cos 8θ·f(y)), flutes fading out toward the apex.
    static func mould(scale: Float = 1) -> MeshData {
        var mesh = MeshKit.lathe(profile: profile, segments: 64)
        for i in mesh.positions.indices {
            let p = mesh.positions[i]
            let r = (p.x * p.x + p.z * p.z).squareRoot()
            guard r > 1e-6 else { continue }
            let theta = atan2(p.z, p.x)
            let f = clamp((0.070 - p.y) / 0.010, 0, 1)
            let k = 1 + 0.07 * cos(8 * theta) * f
            mesh.positions[i] = SIMD3(p.x * k, p.y, p.z * k) * scale
        }
        mesh.recomputeNormals()
        return mesh
    }

    init(variant: PressVariant, fx: SceneFX) {
        self.fx = fx
        let look = Look(variant)
        self.look = look
        rng = SplitMix64(seed: variant.seed ^ 0x7E11)
        golden = look.golden
        containment = GlassDebris.containment(restHeight: 0.0765, anvilHalf: SIMD2<Float>(repeating: 1),
                                              padding: JellySpread.platePadding)
        plateHalf = GlassDebris.containment(restHeight: 0.0765, anvilHalf: SIMD2<Float>(repeating: 1), padding: 0)
        rim = JellyPuddle.Rim(seed: variant.seed ^ 0x9D11)
        life = ObjectLife(seed: variant.seed, idle: .wobble, amount: 0.03, rate: 1.1, pulseHz: 3.2, pulseDamping: 0.22)
        story = StoryCursor(.jelly, seed: variant.seed)
        ooze = OozeRing(seed: variant.seed ^ 0x7E12, count: 8, radii: SIMD2(0.047, 0.047), reach: 0.012...0.026,
                        width: 0.012...0.020, thickness: 0.0032,
                        maxRadius: Self.oozeMaxRadius,
                        material: Self.messMaterial(golden: look.golden, matt: 0.3))
        let shellMaterial = Self.shellMaterial(golden: look.golden, matt: 0)
        let coreMaterial = SceneMaterials.pbr(UIColor(hex: 0xB81E52), roughness: 0.3)
        dropColors = look.golden ? [Palette.goldMessColor] : [Palette.raspberry, UIColor(hex: 0xF0487A)]
        shell = DeformableMesh(MeshCache.mesh("jelly.mould") { ObjectMeshes.jellyMould(scale: 1) }, materials: [shellMaterial], maxSpread: 2.2)
        core = ModelEntity(mesh: MeshCache.resource("jelly.core") { ObjectMeshes.jellyMould(scale: 0.8) } ?? .generateSphere(radius: 0.03),
                           materials: [look.golden ? SceneMaterials.gold : coreMaterial])
        let discMaterial = Self.messMaterial(golden: look.golden, matt: 0)
        spreadDisc = ModelEntity(mesh: MeshKit.spreadDisc(seed: variant.seed, height: 1, segments: 64, wobble: 0.12).resource()
                                 ?? .generateSphere(radius: 0.01), materials: [discMaterial])
        spreadDisc.isEnabled = false
        life.node.addChild(core)
        life.node.addChild(shell.entity)
        entity.addChild(life.node)
        entity.addChild(spreadDisc)
        entity.addChild(ooze.root)

        if variant.surprise == .fruitPieces {
            let colors = [Palette.hydraulicYellow, Palette.lime, Palette.tangerine]
            for k in 0..<5 {
                let a = Float(k) / 5 * 2 * .pi + Float.random(in: -0.3...0.3, using: &rng)
                let y = Float.random(in: 0.012...0.045, using: &rng)
                let r = Self.radius(at: y) * 0.86
                let rest = SIMD3<Float>(cos(a) * r, y, sin(a) * r)
                let cube = Part.add(cached: "jelly.fruit", { MeshKit.roundedBox([0.010, 0.010, 0.010], radius: 0.0025) },
                                    SceneMaterials.enamel(colors[k % colors.count], roughness: 0.25, clearcoat: 0.8,
                                                          clearcoatRoughness: 0.1),
                                    at: rest, to: life.node)
                cube.orientation = simd_quatf(angle: Float.random(in: 0...3, using: &rng),
                                              axis: simd_normalize(SIMD3<Float>(1, Float.random(in: -1...1, using: &rng), 0.4)))
                fruit.append((cube, rest))
            }
        }
        wobbleX.kick(0.12)
    }

    static func radius(at y: Float) -> Float {
        for i in 0..<(profile.count - 1) where y <= profile[i + 1].y {
            let a = profile[i], b = profile[i + 1]
            let t = (y - a.y) / max(b.y - a.y, 1e-6)
            return a.x + (b.x - a.x) * t
        }
        return 0
    }

    func surfaceHeight(compression c: Float) -> Float {
        HeightCurve.linear(c, rest: restHeight, minRatio: minHeightRatio)
    }

    func update(_ state: PressVisualState) {
        let dt = state.dt
        if life.update(state) {
            BeatFX.glint(fx, at: [-0.012, 0.074, -0.01], in: entity, golden: golden, rng: &rng)
        }
        for beat in story.advance(to: state.compression) { onBeat(beat, state: state) }
        defer { ooze.update(compression: state.compression, spread: min(spread, 1.6)) }
        // Idle life: a gentle top lean at ~1.8 Hz after landing; impacts excite it.
        wobbleX.step(toward: 0, dt: dt)
        wobbleZ.step(toward: 0, dt: dt)
        bounce.step(toward: 0, dt: dt)
        if state.loaded && !state.reduceMotion {
            wobbleX.kick(sin(state.time * 13) * 0.002 * state.compression)
        }
        // After the splat the height never comes back up (the plastic ratchet re-inflated the shell at the reveal,
        // FOLD-REVIEW-5 N11); before it the gel still springs back.
        var h = surfaceHeight(compression: state.compression)
        if splat {
            latchedS = min(latchedS, h / restHeight)
            h = min(h, latchedS * restHeight)
        }
        let s = clamp(h / restHeight * (1 + 0.04 * bounce.value), 0.05, 1.04)
        let lean = state.reduceMotion ? SIMD2<Float>.zero : SIMD2(wobbleX.value, wobbleZ.value) * 0.004 * s
        let bulge: Float = splat ? 0.55 : (split ? 0.42 : 0.32)
        let maxSpread: Float = splat ? 1.75 : 1.55
        let key = SIMD4<Float>(s, lean.x, lean.y, bulge)
        // On the Duo the barrel bulge (up to ~0.11 m at full press) is softly held inside the strike plate + 16 pt as
        // seen from the eye: the higher a point, the further in it is held, once the jelly is flattening.
        let cap: SIMD2<Float>? = fx.isFoldPress ? containment : nil
        let lift = JellySpread.lift(heightRatio: s)
        // The puddle (FOLD-REVIEW-7 N9): once the plates part after the splat, the slab slumps into a puddle.
        if splat && state.phase == .revealing { relaxing = true }
        if relaxing && relax < 1 {
            relax = state.reduceMotion ? 1 : Deform.approach(relax, 1, halfLife: JellyPuddle.relaxHalfLife, dt: dt)
            if relax > 0.995 { relax = 1 }
        }
        let puddleHalf = cap != nil ? plateHalf * JellyPuddle.fill : JellyPuddle.machineHalf
        if simd_length(key - lastKey) > 0.0004 || abs(relax - lastRelax) > 0.002 {
            lastKey = key
            lastRelax = relax
            let rest = restHeight
            let w = relax
            let puddleRim = rim
            shell.update { p in
                var q = Deform.squash(p, s: s, restHeight: rest, bulge: bulge, maxSpread: maxSpread, shear: lean)
                if let cap { q = JellySpread.contain(q, half: cap, lift: lift) }
                guard w > 0 else { return q }
                var pool = JellyPuddle.shape(p, half: puddleHalf, rim: puddleRim)
                if let cap { pool = JellySpread.contain(pool, half: cap, lift: lift) }
                return q + (pool - q) * w
            }
        }
        if relax > 0.5 && !glossed {
            // A puddle is wet: its gloss comes back (the raised rim gives the highlight a ring, not a seam).
            glossed = true
            if !golden {
                shell.setMaterial(Self.shellMaterial(golden: golden, matt: JellyPuddle.gloss), forSlot: 0)
                let mess = Self.messMaterial(golden: golden, matt: JellyPuddle.gloss)
                spreadDisc.model?.materials = [mess]
                for blob in splorts { blob.entity.model?.materials = [mess] }
            }
            for line in tear { line.isEnabled = true }
        }
        // Matt the gloss in steps as it flattens (and once more at the splat).
        let level = JellySpread.mattLevel(heightRatio: s, splat: splat)
        if level > mattLevel && !golden && !glossed {
            mattLevel = level
            let matt = Float(level) / Float(JellySpread.mattSteps)
            shell.setMaterial(Self.shellMaterial(golden: golden, matt: matt, taut: taut), forSlot: 0)
            let mess = Self.messMaterial(golden: golden, matt: matt)
            spreadDisc.model?.materials = [mess]
            for blob in splorts { blob.entity.model?.materials = [mess] }
        }
        spread = min(1 / s.squareRoot(), maxSpread) * (1 + bulge * (1 - s) * 0.5)
        let coreSpread = min(1 / s.squareRoot(), maxSpread) * 0.97
        if let cap {
            // The opaque core never pokes through the contained shell (it is round; the shell is held to an ellipse).
            let room = JellySpread.coreRoom(half: cap, lift: lift, coreTop: JellySpread.coreTopRatio * restHeight * s)
            core.scale = SIMD3(min(coreSpread, room.x), s, min(coreSpread, room.y))
        } else {
            core.scale = SIMD3(coreSpread, s, coreSpread)
        }
        if relax > 0 {
            // Flattened inside the puddle's flat middle, so it darkens the pool without poking through its skin.
            let pooled = JellyPuddle.coreScale(half: puddleHalf, rim: rim)
            let target = SIMD3<Float>(min(core.scale.x, pooled.x), JellyPuddle.coreFlat, min(core.scale.z, pooled.y))
            core.scale += (target - core.scale) * relax
        }
        core.position = SIMD3(lean.x * 0.5, 0, lean.y * 0.5) * (1 - relax)
        for piece in fruit where piece.entity.parent === life.node {
            piece.entity.position = SIMD3(piece.rest.x * core.scale.x * 1.05 + lean.x * piece.rest.y / restHeight,
                                          piece.rest.y * s * (1 - relax) + JellyPuddle.centreHeight * 0.5 * relax,
                                          piece.rest.z * core.scale.z * 1.05 + lean.y * piece.rest.y / restHeight)
            piece.entity.scale = SIMD3(1, max(s, 0.35), 1)
        }

        // Spread (overflow → splat) grows with compression past the split, up to Ø 0.15.
        if split {
            // Latched too: the spread never shrinks back as the plates part.
            spreadT = max(spreadT, clamp((state.compression - splatC) / max(1 - splatC, 0.05), 0, 1))
            let t = spreadT
            var radius: Float = splat ? 0.05 + 0.015 * t : 0.045 // capped near plate + 40 pt (FOLD-REVIEW-2 #7)
            // Relaxed, the disc is the puddle's thin wet margin, just reaching past its lobes.
            radius += (puddleHalf.x * JellyPuddle.wetMargin - radius) * relax
            if let cap { radius = min(radius, JellySpread.maxDiscRadius(half: cap)) }
            var thickness: Float = 0.004 * (splat ? 1 : 0.6)
            thickness += (JellyPuddle.filmHeight - thickness) * relax
            spreadDisc.isEnabled = true
            spreadDisc.scale = SIMD3(radius, thickness, radius * JellySpread.discAspect)
            for blob in splorts {
                // Relaxed, the splorts are beads on the puddle's rim.
                let grow = (1 + t * 0.6) * (1 - relax) + JellyPuddle.beadScale * relax
                let blobRadius = grow * blob.size * 0.5
                var d = 0.045 + 0.02 * t
                if relax > 0 {
                    let edge = JellyPuddle.edge(theta: atan2(blob.direction.y, blob.direction.x), half: puddleHalf, rim: rim)
                    d += (simd_length(edge) * 0.97 - d) * relax
                }
                if let cap { d = max(min(d, JellySpread.maxReach(direction: blob.direction, half: cap) - blobRadius), 0.02) }
                let flat = max(0.3, min(1, h / 0.02)) * 0.4
                let height = blob.size * 0.5 * flat * (1 - relax) + JellyPuddle.beadHeight * relax
                blob.entity.position = SIMD3(blob.direction.x * d, height, blob.direction.y * d)
                blob.entity.scale = SIMD3(grow * blob.size * 0.5, height, grow * blob.size * 0.5)
            }
            spread = max(spread, radius / footprint)
        }
        if let cap { spread = min(spread, cap.x / footprint) }
    }

    /// The translucent raspberry shell; `matt` 0…1 takes it from a mirror (roughness 0.08, clearcoat 0.03) to a
    /// soft gloss (0.20, 0.14) as it flattens.
    private static func shellMaterial(golden: Bool, matt: Float, taut: Int = 0) -> PhysicallyBasedMaterial {
        if golden { return SceneMaterials.gold }
        let m = clamp(matt, 0, 1)
        // Taut skin (storyboard `.strain` / `.tell`): thinner, so it glows brighter and lets more light through.
        let k = Float(clamp(taut, 0, JellySpread.tautSteps))
        var material = SceneMaterials.enamel(Palette.raspberry, roughness: 0.08 + 0.12 * m, clearcoat: 1,
                                             clearcoatRoughness: 0.03 + 0.11 * m, opacity: 0.86 - 0.05 * k)
        material.emissiveColor = .init(color: UIColor(hex: 0xFF5A8A))
        material.emissiveIntensity = 0.22 + 0.07 * k
        return material
    }

    /// The ooze stays on the Duo strike plate (no padding).
    private static var oozeMaxRadius: Float {
        let half = GlassDebris.containment(restHeight: 0.0765, anvilHalf: SIMD2<Float>(repeating: 1), padding: 0)
        return min(half.x, half.y) * 0.95
    }

    private func tighten() {
        guard taut < JellySpread.tautSteps, !golden else { return }
        taut += 1
        if !glossed {
            shell.setMaterial(Self.shellMaterial(golden: golden, matt: Float(mattLevel) / Float(JellySpread.mattSteps), taut: taut),
                              forSlot: 0)
        }
    }

    /// One storyboard beat (OBJECT-STORYBOARDS §3): wobble and ooze, never a give.
    private func onBeat(_ beat: StoryBeat, state: PressVisualState) {
        let golden = self.golden
        switch beat.kind {
        case .kiss:
            bounce.kick(-2)
            BeatFX.glint(fx, at: [0, 0.077, 0], in: entity, count: 3, golden: golden, rng: &rng)
        case .wobble:
            let sign: Float = beat.ordinal % 2 == 0 ? 1 : -1
            wobbleX.kick(1.6 * sign)
            wobbleZ.kick(-1.1 * sign)
            if splat {
                let a = Float.random(in: 0...(2 * .pi), using: &rng)
                BeatFX.fling(fx, at: [cos(a) * 0.05, 0.006, sin(a) * 0.05], in: entity, direction: SIMD2(cos(a), sin(a)),
                             count: 2, colors: dropColors, rng: &rng)
            }
        case .bulge:
            life.kick(0.8)
            wobbleZ.kick(0.8)
        case .ooze:
            if let tip = ooze.emit(at: state.compression), beat.ordinal % 2 == 1 {
                let d = simd_length(SIMD2(tip.x, tip.z)) > 1e-5 ? simd_normalize(SIMD2(tip.x, tip.z)) : SIMD2<Float>(1, 0)
                BeatFX.fling(fx, at: tip, in: entity, direction: d, count: 1, colors: dropColors, speed: 0.12, rng: &rng)
            }
            bounce.kick(-1)
        case .strain, .tell:
            tighten()
            life.tremor(beat.kind == .tell ? 0.3 : 0.15, level: 0.6)
            if beat.kind == .tell && beat.ordinal > 0 {
                let a = Float.random(in: 0...(2 * .pi), using: &rng)
                BeatFX.fling(fx, at: [cos(a) * 0.045, 0.01, sin(a) * 0.045], in: entity, direction: SIMD2(cos(a), sin(a)),
                             count: 1, colors: dropColors, speed: 0.1, rng: &rng)
            }
        case .fling:
            let a = Float.random(in: 0...(2 * .pi), using: &rng)
            BeatFX.fling(fx, at: [cos(a) * 0.055, 0.006, sin(a) * 0.055], in: entity, direction: SIMD2(cos(a), sin(a)),
                         count: 3, colors: dropColors, rng: &rng)
            wobbleX.kick(0.8)
        case .settle:
            BeatFX.glint(fx, at: [0.01, 0.006, 0.01], in: entity, count: 2, golden: golden, rng: &rng)
        default:
            bounce.kick(-1)
        }
    }

    /// The splat disc and splorts: flat, so they get matted harder than the shell (roughness up to 0.24).
    private static func messMaterial(golden: Bool, matt: Float) -> PhysicallyBasedMaterial {
        if golden { return SceneMaterials.goldMess }
        let m = clamp(matt, 0, 1)
        return SceneMaterials.enamel(Palette.raspberry, roughness: 0.08 + 0.16 * m, clearcoat: 1,
                                     clearcoatRoughness: 0.03 + 0.15 * m, opacity: 0.92)
    }

    func fracture(index: Int, isFailure: Bool, state: PressVisualState) {
        let speed = 0.35 * fx.motionScale
        if !isFailure {
            // Skin split: a squirt from one side.
            split = true
            splatC = state.compression
            wobbleX.kick(2)
            let a = Float.random(in: 0...(2 * .pi), using: &rng)
            let at = entity.convert(position: [cos(a) * 0.045, 0.02, sin(a) * 0.045], to: fx.root)
            for _ in 0..<ParticleSystem.scaled(6) {
                let v = SIMD3<Float>(cos(a), 0.6, sin(a)) * speed * Float.random(in: 0.6...1.2, using: &rng)
                fx.particles.emit(.droplet, at: at, velocity: v, color: dropColors.pick(&rng),
                                  size: Float.random(in: 0.003...0.006, using: &rng), rng: &rng)
            }
        } else {
            // Splat: splorts out of the sides; the disc grows from here to full compression.
            split = true
            splat = true
            splatC = state.compression
            spreadT = 0
            wobbleX.kick(4)
            wobbleZ.kick(-3)
            bounce.kick(-6)
            let blobMaterial = Self.messMaterial(golden: look.golden, matt: Float(mattLevel) / Float(JellySpread.mattSteps))
            let count = 6 + Int(rng.next() % 5)
            for k in 0..<count {
                let a = Float(k) / Float(count) * 2 * .pi + Float.random(in: -0.25...0.25, using: &rng)
                let size = Float.random(in: 0.012...0.022, using: &rng)
                let blob = Part.add(cached: "jelly.splort", { MeshKit.sphere(radius: 1, segments: 24, rings: 12) },
                                    blobMaterial, to: entity)
                blob.scale = SIMD3(repeating: size * 0.5)
                splorts.append((blob, SIMD2(cos(a), sin(a)), size))
            }
            for _ in 0..<ParticleSystem.scaled(10) {
                let dir = Burst.unitDirection(rng: &rng, upBias: 0.15)
                let at = entity.convert(position: [dir.x * 0.04, 0.012, dir.z * 0.04], to: fx.root)
                fx.particles.emit(.droplet, at: at, velocity: SIMD3(dir.x, dir.y * 0.8, dir.z) * speed * 1.3,
                                  color: dropColors.pick(&rng), size: Float.random(in: 0.003...0.007, using: &rng), rng: &rng)
            }
            // Some fruit pops out onto the anvil.
            for (i, piece) in fruit.enumerated() where i % 2 == 0 {
                let dir = simd_normalize(SIMD3<Float>(piece.rest.x, 0, piece.rest.z) + SIMD3(0, 0.0001, 0))
                fx.debris.adopt(piece.entity, velocity: (dir * 0.25 + SIMD3(0, 0.35, 0)) * fx.motionScale,
                                spin: Burst.spin(8 * fx.motionScale, rng: &rng), bounciness: 0.2)
            }
            buildTear()
        }
    }

    /// One jagged tear across the puddle's skin (FOLD-REVIEW-7 N9), the dark core showing through; hidden until the
    /// puddle has relaxed.
    private func buildTear() {
        guard tear.isEmpty else { return }
        let material = golden ? SceneMaterials.pbr(UIColor(hex: 0x8A5A00), roughness: 0.3, metallic: 1)
            : SceneMaterials.enamel(UIColor(hex: JellyPuddle.tearTint), roughness: 0.3, clearcoat: 0.6, clearcoatRoughness: 0.2)
        let half = fx.isFoldPress ? plateHalf * JellyPuddle.fill : JellyPuddle.machineHalf
        let path = JellyPuddle.tearPath(angle: Float.random(in: 0...(2 * .pi), using: &rng), half: half, rim: rim, rng: &rng)
        for k in 0..<(path.count - 1) {
            let a = path[k], b = path[k + 1]
            let run = SIMD2<Float>(b.x - a.x, b.z - a.z)
            let length = simd_length(run)
            guard length > 1e-4 else { continue }
            let width = JellyPuddle.tearWidth * (1 - 0.5 * abs(Float(k) / Float(max(path.count - 2, 1)) * 2 - 1))
            let line = Part.add(MeshKit.roundedBox([length + width, 0.0004, width], radius: width * 0.45, bevel: 0.00015),
                                material, at: (a + b) / 2, to: entity)
            line.orientation = simd_quatf(angle: -atan2(run.y, run.x), axis: [0, 1, 0])
            line.isEnabled = false
            tear.append(line)
        }
    }

    func handle(_ event: PressEvent, state: PressVisualState) {
        switch event {
        case .contact: bounce.kick(-3)
        case .released:
            wobbleX.kick(1.5)
            bounce.kick(2)
            if splat { relaxing = true }
        case .reveal:
            if splat { relaxing = true }
        default: break
        }
    }
}

/// The jelly's plate containment and gloss steps (FOLD-REVIEW-4 F14, FOLD-REVIEW-5 N11), pure so SquishTests can pin
/// them.
enum JellySpread {
    /// How far past the Duo strike plate the jelly may reach, in canvas points (FOLD-REVIEW-5 N11: plate + 16, as the
    /// glass pile; was 24).
    static let platePadding: Double = 16
    /// The anamorphic lean of height (FOLD-REVIEW-5 N11). The Fold eye is rendered at ≥ 47.5° elevation
    /// (`FoldEyeModel.minRenderElevationDegrees`), so a point `y` above the glass is drawn up to y·cot 47.5° ≈ 0.92 y
    /// further out on the glass; 0.95 covers the finite eye distance. The direction depends on the pose (tabletop:
    /// toward the crease; book: toward the page's top), so the hold is applied all round.
    static let projectionSlope: Float = 0.95
    /// Only a flattening jelly is held by its projection: a tall jelly at rest legitimately leans past the plate
    /// (§2.3, like every tall object), and squeezing it there would dent its mould.
    static func lift(heightRatio s: Float) -> Float {
        projectionSlope * clamp((1 - s) / 0.55, 0, 1)
    }

    /// The containment half extents for a point at height `y`: the plate + padding, pulled in by its projected lean,
    /// never below 55 % of the plate (so the squeeze stays smooth and monotonic).
    static func heldHalf(_ half: SIMD2<Float>, lift: Float, y: Float) -> SIMD2<Float> {
        simd_max(half - SIMD2<Float>(repeating: lift * max(y, 0)), half * 0.55)
    }

    /// The opaque core (`ObjectMeshes.jellyMould(scale: 0.8)`) is this tall and this wide, relative to the shell.
    static let coreTopRatio: Float = 0.8
    static let coreRestRadius: Float = 0.049 * 0.8 * 1.07

    /// The largest core spread (x, z) that keeps the round core inside the shell's held ellipse at the core's top.
    static func coreRoom(half: SIMD2<Float>, lift: Float, coreTop: Float) -> SIMD2<Float> {
        heldHalf(half, lift: lift, y: coreTop) * (knee / coreRestRadius)
    }

    /// Inside this share of the containment ellipse nothing moves; beyond it the reach is squeezed (tanh) so it
    /// approaches the edge but never crosses it.
    static let knee: Float = 0.78
    /// The splat disc is drawn 0.92× as deep as it is wide, and its seeded rim reaches ~1.2× its radius.
    static let discAspect: Float = 0.92
    static let discRimReach: Float = 1.2
    static let mattSteps = 4
    /// Skin tautness steps before the split (storyboard `.strain` / `.tell` beats).
    static let tautSteps = 3

    /// Elliptical norm of a horizontal point against the half extents `half` (1 = on the edge).
    static func norm(_ xz: SIMD2<Float>, half: SIMD2<Float>) -> Float {
        let u = xz / simd_max(half, SIMD2<Float>(repeating: 1e-4))
        return (u.x * u.x + u.y * u.y).squareRoot()
    }

    /// Softly pulls a deformed point inside the ellipse of half extents `half` (height untouched), pulled in further the
    /// higher the point by `lift` (`heldHalf`), so its projection stays on the plate too. Monotonic and continuous, so
    /// the surface stays smooth; points inside `knee` are unchanged.
    static func contain(_ p: SIMD3<Float>, half: SIMD2<Float>, lift: Float = 0) -> SIMD3<Float> {
        let held = lift > 0 ? heldHalf(half, lift: lift, y: p.y) : half
        let e = norm(SIMD2(p.x, p.z), half: held)
        guard e > knee else { return p }
        let span = 1 - knee
        let squeezed = knee + span * tanh((e - knee) / span)
        let k = squeezed / e
        return SIMD3(p.x * k, p.y, p.z * k)
    }

    /// The largest splat disc radius whose wobbly rim stays inside `half`.
    static func maxDiscRadius(half: SIMD2<Float>) -> Float {
        min(half.x, half.y / discAspect) / discRimReach
    }

    /// Distance from the centre to the ellipse edge along the unit `direction` (x, z).
    static func maxReach(direction: SIMD2<Float>, half: SIMD2<Float>) -> Float {
        let n = norm(direction, half: half)
        return n > 1e-6 ? 1 / n : 0
    }

    /// Gloss step for height ratio `s`: 0 at rest … `mattSteps − 1` fully squashed, `mattSteps` once it has splatted.
    static func mattLevel(heightRatio s: Float, splat: Bool) -> Int {
        if splat { return mattSteps }
        let flat = clamp((1 - s) / 0.87, 0, 1)
        return min(Int((flat * Float(mattSteps - 1)).rounded(.down)), mattSteps - 1)
    }
}

/// The relaxed jelly (FOLD-REVIEW-7 N9: the reveal was a smooth pink dome under "SKIN SPLIT · SPLAT"). Once the plates
/// part after the splat, every vertex of the mould maps onto a puddle: a lobed outline held inside the strike plate, a
/// flat glossy middle, a raised rim just inside the edge and a low rounded lip, all ≤ 35 % of the pressed height.
/// Pure, so SquishTests can pin it. Heights are anvil metres; the mould's rest vertices come in.
enum JellyPuddle {
    /// The flat middle, the rim's crest and the outer lip (the pressed slab is 0.0765 × 0.13 ≈ 10 mm tall).
    static let centreHeight: Float = 0.0017
    static let rimHeight: Float = 0.0034
    static let lipHeight: Float = 0.0009
    /// Where the crest sits (share of the way out) and how wide its inner slope is.
    static let rimAt: Float = 0.84
    static let rimInnerWidth: Float = 0.13
    /// The puddle's reach: this share of the strike plate's half extents (no padding) on the Duo; on the P-48, a fixed
    /// ellipse a little inside the anvil.
    static let fill: Float = 0.9
    static let machineHalf = SIMD2<Float>(0.08, 0.07)
    /// The mould (`ObjectMeshes.jellyProfile`): widest radius, at the top of its rounded foot.
    static let mouldRadius: Float = 0.049
    static let footY: Float = 0.008
    /// How fast it slumps (half-life, s), and the gloss it gets back (`shellMaterial` matt 0…1).
    static let relaxHalfLife: Float = 0.16
    static let gloss: Float = 0.2
    /// The core's height scale once pooled (its top stays under the middle's skin) and its share of the pool's width.
    static let coreFlat: Float = 0.02
    static let coreShare: Float = 0.65
    /// The splat disc becomes the pool's wet margin; the splorts become beads on its rim.
    static let wetMargin: Float = 0.98
    static let filmHeight: Float = 0.0008
    static let beadScale: Float = 0.55
    static let beadHeight: Float = 0.0012
    /// The tear: the core's colour, a little darker, ~1.2 mm wide at its middle.
    static let tearTint: UInt32 = 0x9A1546
    static let tearWidth: Float = 0.0012

    /// The seeded lobes of the outline (5, 7 and 9 round), 0.825…1.095 of the base ellipse.
    struct Rim: Sendable {
        static let amplitudes: [Float] = [0.07, 0.04, 0.025]
        static let lobes: [Float] = [5, 7, 9]
        static let base: Float = 0.96
        static var minScale: Float { base - amplitudes.reduce(0, +) }
        static var maxScale: Float { base + amplitudes.reduce(0, +) }
        let phases: [Float]

        init(seed: UInt64) {
            var rng = SplitMix64(seed: seed)
            phases = Self.lobes.map { _ in Float.random(in: 0...(2 * .pi), using: &rng) }
        }

        func scale(_ theta: Float) -> Float {
            var r = Self.base
            for i in phases.indices { r += Self.amplitudes[i] * sin(Self.lobes[i] * theta + phases[i]) }
            return r
        }
    }

    /// The top surface's height `rho` (0 middle … 1 edge) of the way out: flat, then the raised rim, then the lip.
    static func height(rho: Float) -> Float {
        let rho = clamp(rho, 0, 1)
        if rho <= rimAt {
            let x = (rho - rimAt) / rimInnerWidth
            return centreHeight + (rimHeight - centreHeight) * exp(-x * x)
        }
        let c = cos((rho - rimAt) / (1 - rimAt) * .pi / 2)
        return lipHeight + (rimHeight - lipHeight) * c * c
    }

    /// The outline point (x, z) at angle `theta`.
    static func edge(theta: Float, half: SIMD2<Float>, rim: Rim) -> SIMD2<Float> {
        SIMD2(cos(theta) * half.x, sin(theta) * half.y) * rim.scale(theta)
    }

    /// Rest mould vertex `p` on the puddle. The mould's upper surface (above its widest ring) becomes the top, its apex
    /// the middle; the rounded foot becomes the lip; the base stays on the plate.
    static func shape(_ p: SIMD3<Float>, half: SIMD2<Float>, rim: Rim) -> SIMD3<Float> {
        let r = (p.x * p.x + p.z * p.z).squareRoot()
        let theta: Float = r > 1e-6 ? atan2(p.z, p.x) : 0
        // Undo the mould's flutes (ObjectMeshes.jellyMould), so they don't ripple the rim.
        let f = clamp((0.070 - p.y) / 0.010, 0, 1)
        let r0 = r / (1 + 0.07 * cos(8 * theta) * f)
        let rho = clamp(r0 / mouldRadius, 0, 1)
        let y = p.y <= footY ? lipHeight * clamp(p.y / footY, 0, 1) : height(rho: rho)
        let e = edge(theta: theta, half: half, rim: rim)
        return SIMD3(e.x * rho, y, e.y * rho)
    }

    /// The core's (x, z) scale once pooled: its rest radius fits `coreShare` of the pool's narrowest reach.
    static func coreScale(half: SIMD2<Float>, rim: Rim) -> SIMD2<Float> {
        half * (Rim.minScale * coreShare / JellySpread.coreRestRadius)
    }

    /// The tear's jagged path across the skin, from near the middle most of the way to the rim, just above the surface.
    static func tearPath(angle: Float, half: SIMD2<Float>, rim: Rim, rng: inout SplitMix64) -> [SIMD3<Float>] {
        let steps = 6
        return (0..<steps).map { i in
            let rho = 0.12 + 0.58 * Float(i) / Float(steps - 1)
            let theta = angle + Float.random(in: -0.16...0.16, using: &rng)
            let e = edge(theta: theta, half: half, rim: rim) * rho
            return SIMD3(e.x, height(rho: rho) + 0.0002, e.y)
        }
    }
}
