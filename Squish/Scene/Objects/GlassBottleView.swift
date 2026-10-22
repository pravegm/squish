import Foundation
import RealityKit
import simd
import UIKit

/// Glass Bottle (bible §4 #9, VISUAL-TARGET §5.9): a sea-glass bottle lying on its side, neck camera-right,
/// pre-fractured into ~30 chunky soft-edged shards (2.2 mm thick lathe patches) with a cream paper label band.
/// Silent rigidity until fracture 0 (~0.22): bright crack lines and a glint. Fracture 1 (failure, ~0.40) is the
/// biggest event in the app: every shard bursts out with seeded impulses (fade-and-slump under Reduce Motion),
/// glints sparkle, then the ram presses the shards flat. Fracture 2 (~0.62): the pile crunches into tidy,
/// soft "sea glass". Surprise `messageInABottle`: a rolled note inside that bursts into candy confetti.
@MainActor
final class GlassBottleView: PressObjectView {
    let entity = Entity()
    /// ×0.86 so it sits fully on the anvil at ~42% width (VISUAL-REVIEW-1 fix 6); authored at Ø 0.060.
    static let heroScale: Float = 0.86
    static let localHeight: Float = 0.060
    let restHeight: Float = 0.060 * GlassBottleView.heroScale
    let footprint: Float = 0.068 * GlassBottleView.heroScale

    private let fx: SceneFX
    private let look: Look
    private var rng = SplitMix64(seed: 0)
    private let bottle = Entity()
    private var shards: [ModelEntity] = []
    private var glassParts: [ModelEntity] = []
    private var cracks: [Entity] = []
    private var message: Entity?
    private let failC: Float
    private var failed = false
    private let seaGlass: PhysicallyBasedMaterial

    static let length: Float = 0.140
    static let profile: [SIMD2<Float>] = MeshKit.smoothProfile([
        SIMD2(0.000, 0.000), SIMD2(0.026, 0.0015), SIMD2(0.0295, 0.005), SIMD2(0.030, 0.010), SIMD2(0.030, 0.040),
        SIMD2(0.030, 0.075), SIMD2(0.0285, 0.088), SIMD2(0.023, 0.100), SIMD2(0.016, 0.110), SIMD2(0.0118, 0.118),
        SIMD2(0.0110, 0.130), SIMD2(0.0125, 0.133), SIMD2(0.0128, 0.138), SIMD2(0.0112, 0.1395), SIMD2(0.000, 0.1398),
    ], perSpan: 3)

    init(variant: PressVariant, fx: SceneFX) {
        self.fx = fx
        let look = Look(variant)
        self.look = look
        failC = PressObjectFactory.failureThreshold(.glassBottle, variant: variant) ?? 0.4
        seaGlass = look.golden ? SceneMaterials.gold
            : SceneMaterials.enamel(UIColor(hex: 0x5CC8B8), roughness: 0.25, clearcoat: 0.8, clearcoatRoughness: 0.2,
                                    specular: 1, opacity: 0.55)
        rng = SplitMix64(seed: variant.seed ^ 0x6A55)
        build(variant: variant)
    }

    private func build(variant: PressVariant) {
        let outer = look.golden ? SceneMaterials.gold
            : SceneMaterials.enamel(UIColor(hex: 0x5CC8B8), roughness: 0.04, clearcoat: 1, clearcoatRoughness: 0.02,
                                    specular: 1, opacity: 0.32)
        let inner = look.golden ? SceneMaterials.gold
            : SceneMaterials.enamel(UIColor(hex: 0x2E8F84), roughness: 0.05, clearcoat: 1, clearcoatRoughness: 0.02,
                                    specular: 1, opacity: 0.22)
        let label = look.golden ? SceneMaterials.pbr(UIColor(hex: 0x8A5A00), roughness: 0.5)
            : SceneMaterials.pbr(Palette.glassLabel, roughness: 0.7)
        let labelStripe = look.golden ? label : SceneMaterials.pbr(Palette.raspberry, roughness: 0.6)

        // Lying: lathe about local Y, rolled −90° about Z (neck → +X), centred on its length, resting on the anvil.
        bottle.orientation = simd_quatf(angle: -.pi / 2, axis: [0, 0, 1])
        bottle.position = [0, 0.030, 0]
        let axial = Entity()
        axial.position = [0, -Self.length / 2, 0]
        bottle.addChild(axial)

        let profile = Self.profile
        func ring(at y: Float) -> Int {
            profile.firstIndex { $0.y >= y } ?? profile.count - 1
        }
        let bandEdges = [0, ring(at: 0.006), ring(at: 0.035), ring(at: 0.060), ring(at: 0.085), ring(at: 0.112), profile.count - 1]
        let sectorCounts = [1, 6, 6, 6, 5, 3]
        for b in 0..<(bandEdges.count - 1) {
            let rings = bandEdges[b]...bandEdges[b + 1]
            let n = sectorCounts[b]
            let offset = Float.random(in: 0...(2 * .pi), using: &rng)
            var cuts: [Float] = (0..<n).map { k in
                offset + 2 * .pi * Float(k) / Float(n) + (n > 1 ? Float.random(in: -0.22...0.22, using: &rng) : 0)
            }
            cuts.append(cuts[0] + 2 * .pi)
            for k in 0..<n {
                let patch = MeshKit.lathePatch(profile: profile, rings: rings, angles: cuts[k]...cuts[k + 1],
                                               angularSteps: max(4, 48 / n), thickness: 0.0022)
                let shard = ModelEntity()
                let model = MeshKit.entity(patch.mesh, materials: [outer, inner], name: "glass.shard")
                shard.addChild(model)
                glassParts += Self.models(in: model)
                shard.position = patch.centre
                // The paper label wraps the middle bands.
                if b == 2 || b == 3 {
                    let labelPatch = MeshKit.lathePatch(
                        profile: profile.map { SIMD2($0.x + 0.0006, $0.y) }, rings: rings,
                        angles: (cuts[k] + 0.004)...(cuts[k + 1] - 0.004), angularSteps: max(4, 48 / n), thickness: 0.0005)
                    let labelEntity = MeshKit.entity(labelPatch.mesh, materials: [b == 2 ? label : labelStripe, label],
                                                     name: "glass.label")
                    labelEntity.position = labelPatch.centre - patch.centre
                    shard.addChild(labelEntity)
                }
                axial.addChild(shard)
                shards.append(shard)
            }
        }
        if variant.surprise == .messageInABottle {
            let note = Entity()
            Part.add(cached: "glass.note", { MeshKit.roundedCylinder(radius: 0.008, height: 0.06, bevel: 0.003, segments: 32) },
                     SceneMaterials.pbr(UIColor(hex: 0xF4ECDD), roughness: 0.7), at: [0, -0.03, 0], to: note)
            let thread = Part.add(cached: "glass.thread", { MeshKit.torus(major: 0.0083, minor: 0.0009, segments: 32, sides: 8) },
                                  SceneMaterials.pbr(Palette.stampRed, roughness: 0.5), at: .zero, to: note)
            _ = thread
            note.position = [0, 0.052, 0]
            axial.addChild(note)
            message = note
        }
        entity.addChild(bottle)
        entity.orientation = Part.yaw(-15)
        entity.scale = SIMD3(repeating: Self.heroScale)
    }

    static func models(in entity: Entity) -> [ModelEntity] {
        var result: [ModelEntity] = []
        if let model = entity as? ModelEntity, model.model != nil { result.append(model) }
        for child in entity.children { result += models(in: child) }
        return result
    }

    func surfaceHeight(compression c: Float) -> Float {
        HeightCurve.brittle(c, rest: restHeight, failC: failC, failed: failed, rigidSquash: 0.02,
                            afterRatio: 0.45, minRatio: 0.09)
    }

    func update(_ state: PressVisualState) {
        guard !failed else { return }
        let s = surfaceHeight(compression: state.compression) / restHeight
        // Bottle local X is world-vertical after the roll.
        bottle.scale = SIMD3(s, 1, 1 / s.squareRoot())
    }

    func fracture(index: Int, isFailure: Bool, state: PressVisualState) {
        switch index {
        case 0:
            // A long creak, then bright crack lines on top and a glint.
            let white = SceneMaterials.unlit(UIColor(hex: 0xF4FFFC), opacity: 0.85)
            var x: Float = -0.03
            var z: Float = Float.random(in: -0.004...0.004, using: &rng)
            for _ in 0..<7 {
                let length = Float.random(in: 0.006...0.011, using: &rng)
                let turn = Float.random(in: -0.7...0.7, using: &rng)
                let line = ModelEntity(mesh: .generateBox(width: length, height: 0.0004, depth: 0.0007), materials: [white])
                line.position = [x + length / 2 * cos(turn), Self.localHeight + 0.0003, z + length / 2 * sin(turn)]
                line.orientation = simd_quatf(angle: -turn, axis: [0, 1, 0])
                entity.addChild(line)
                cracks.append(line)
                x += length * cos(turn)
                z += length * sin(turn) * 0.5
            }
            fx.particles.burst(.glint, count: 3, at: entity.convert(position: [0, Self.localHeight, 0], to: fx.root), speed: 0.05,
                               colors: [UIColor(hex: 0xFFFFFF)], size: 0.003...0.005, upBias: 0.6, life: 0.25, rng: &rng)
        case 1:
            shatter(state: state)
        default:
            // Crunch: the pile settles into soft sea glass, with a few small bits.
            for part in glassParts { part.model?.materials = [seaGlass] }
            fx.particles.burst(.flake, count: 10, at: [0, 0.006, 0], speed: 0.2 * max(fx.motionScale, 0.3),
                               colors: look.golden ? [Palette.gold] : [UIColor(hex: 0x5CC8B8), UIColor(hex: 0x8FE0D3)],
                               size: 0.002...0.004, spread: 0.035, upBias: 0.3, rng: &rng)
            fx.particles.burst(.glint, count: 5, at: [0, 0.01, 0], speed: 0.1, colors: [UIColor(hex: 0xFFFFFF)],
                               size: 0.002...0.004, spread: 0.03, upBias: 0.5, life: 0.3, rng: &rng)
        }
    }

    /// The big one: chunky shards burst outward and up with seeded impulses, glints, and the message's confetti.
    private func shatter(state: PressVisualState) {
        failed = true
        bottle.scale = SIMD3(repeating: 1)
        for line in cracks { line.removeFromParent() }
        cracks.removeAll()
        let m = fx.motionScale
        let axisStart = bottle.convert(position: [0, -Self.length / 2, 0], to: fx.root)
        let axisEnd = bottle.convert(position: [0, Self.length / 2, 0], to: fx.root)
        let axis = simd_normalize(axisEnd - axisStart)
        for shard in shards {
            let p = shard.position(relativeTo: fx.root)
            // Radial direction away from the bottle's axis, plus a little along it.
            let along = simd_dot(p - axisStart, axis)
            let onAxis = axisStart + axis * along
            var radial = p - onAxis
            radial.y = max(radial.y, 0) + 0.004
            let dir = simd_normalize(radial)
            let speed = Float.random(in: 0.35...0.75, using: &rng)
            let v = (dir * speed + axis * Float.random(in: -0.12...0.12, using: &rng) + SIMD3(0, 0.45, 0)) * m
            fx.debris.adopt(shard, velocity: v, spin: Burst.spin(16 * m, rng: &rng), bounciness: 0.3, friction: 0.55)
        }
        let centre = entity.convert(position: [0, 0.03, 0], to: fx.root)
        fx.particles.burst(.glint, count: 14, at: centre, speed: 0.6 * max(m, 0.3), colors: [UIColor(hex: 0xFFFFFF), UIColor(hex: 0xD8FFF8)],
                           size: 0.003...0.006, spread: 0.03, upBias: 0.2, life: 0.35, rng: &rng)
        fx.particles.burst(.flake, count: 8, at: centre, speed: 0.5 * max(m, 0.3),
                           colors: look.golden ? [Palette.gold] : [UIColor(hex: 0x8FE0D3)], size: 0.002...0.004,
                           spread: 0.03, upBias: 0.3, rng: &rng)
        if let message {
            fx.particles.burst(.confetti, count: 24, at: centre + SIMD3(0, 0.01, 0), speed: 0.7 * max(m, 0.3),
                               colors: Palette.rainbow, size: 0.004...0.006, spread: 0.02, upBias: 0.5, rng: &rng)
            fx.debris.adopt(message, velocity: SIMD3(0, 0.3, 0.1) * m, spin: Burst.spin(4 * m, rng: &rng), bounciness: 0.2)
        }
    }
}
