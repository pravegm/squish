import Foundation
import RealityKit
import simd
import UIKit

/// Particle vocabulary (research 03 §2): each kind has its own motion and fate.
enum ParticleKind {
    /// Round, bouncy, settles and stays (cake, crayon wax bits).
    case crumb
    /// Flies, then lands as a flat stain that persists (jelly, jam, fizz drops, yolk).
    case droplet
    /// Flat squares that flutter down and stay (surprise cores only).
    case confetti
    /// Tiny bubbles that rise and pop (soda).
    case fizz
    /// Bright glints that vanish quickly (glass, steel).
    case glint
    /// Soft puffs that drift up and fade (bubble pops, steel dust).
    case dust
    /// Hot sparks (the Unsquishable breaking the press).
    case spark
    /// Flat wax / icing flakes that tumble and stay.
    case flake

    var usesBox: Bool {
        switch self {
        case .confetti, .flake, .glint: true
        case .crumb, .droplet, .fizz, .dust, .spark: false
        }
    }

    var persists: Bool {
        switch self {
        case .crumb, .droplet, .confetti, .flake: true
        case .fizz, .glint, .dust, .spark: false
        }
    }

    var unlit: Bool {
        switch self {
        case .glint, .spark: true
        default: false
        }
    }

    /// (gravity scale, air drag per second)
    var motion: (gravity: Float, drag: Float) {
        switch self {
        case .crumb: (1, 0.3)
        case .droplet: (1, 0.2)
        case .confetti: (0.35, 3.5)
        case .fizz: (-0.25, 2.5)
        case .glint: (0.6, 1)
        case .dust: (-0.15, 4)
        case .spark: (0.8, 0.6)
        case .flake: (0.6, 2.2)
        }
    }
}

private struct ParticleState {
    var kind: ParticleKind = .dust
    var position: SIMD3<Float> = .zero
    var velocity: SIMD3<Float> = .zero
    var size: SIMD3<Float> = SIMD3(repeating: 0.001)
    var age: Float = 0
    var life: Float = 1
    var spinAxis = SIMD3<Float>(0, 1, 0)
    var spinRate: Float = 0
    var angle: Float = 0
    var stuck = false
    var flat: Float = 1
    var active = false
    var birth: Int = 0
}

/// Pooled lightweight particles. Two pools (spheres, boxes) of ModelEntities, enabled on demand.
/// Hard caps far below bible §9's 3k: 60 spheres + 40 boxes; persistent stains keep their slot until
/// the next object (the oldest are recycled if the pool runs dry). Thermal `.serious` halves spawn counts.
@MainActor
final class ParticleSystem {
    static let sphereCap = 60
    static let boxCap = 40

    let root = Entity()
    private var spheres: [ModelEntity] = []
    private var boxes: [ModelEntity] = []
    private var sphereState: [ParticleState]
    private var boxState: [ParticleState]
    private var pbrCache: [UIColor: PhysicallyBasedMaterial] = [:]
    private var unlitCache: [UIColor: UnlitMaterial] = [:]
    private var births = 0
    var ceiling: Float = 10
    var plateHalfExtent = SIMD2<Float>(0.08, 0.057)
    var minXZ = SIMD2<Float>(-0.108, -0.075)
    var maxXZ = SIMD2<Float>(0.108, 0.078)

    init() {
        let sphereMesh = MeshResource.generateSphere(radius: 0.5)
        let boxMesh = MeshResource.generateBox(size: 1, cornerRadius: 0.2)
        let placeholder = SceneMaterials.pbr(.white, roughness: 0.5)
        sphereState = Array(repeating: ParticleState(), count: Self.sphereCap)
        boxState = Array(repeating: ParticleState(), count: Self.boxCap)
        for _ in 0..<Self.sphereCap {
            let e = ModelEntity(mesh: sphereMesh, materials: [placeholder])
            e.isEnabled = false
            ShadowCasting.off(e)
            root.addChild(e)
            spheres.append(e)
        }
        for _ in 0..<Self.boxCap {
            let e = ModelEntity(mesh: boxMesh, materials: [placeholder])
            e.isEnabled = false
            ShadowCasting.off(e)
            root.addChild(e)
            boxes.append(e)
        }
    }

    /// Spawn-count multiplier: halves under thermal pressure (bible §9).
    static var budget: Float {
        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical: 0.5
        default: 1
        }
    }

    static func scaled(_ count: Int) -> Int {
        max(1, Int((Float(count) * budget).rounded()))
    }

    func emit(_ kind: ParticleKind, at position: SIMD3<Float>, velocity: SIMD3<Float>, color: UIColor,
              size: Float, life: Float = 1.2, rng: inout SplitMix64) {
        births += 1
        var state = ParticleState()
        state.kind = kind
        state.position = position
        state.velocity = velocity
        state.active = true
        state.birth = births
        state.life = kind.persists ? 1e9 : life * Float.random(in: 0.75...1.25, using: &rng)
        switch kind {
        case .confetti: state.size = SIMD3(size, size * 0.12, size * 0.7)
        case .flake: state.size = SIMD3(size, size * 0.25, size * 0.8)
        case .glint: state.size = SIMD3(size, size * 0.2, size * 0.35)
        default: state.size = SIMD3(repeating: size)
        }
        state.spinAxis = simd_normalize(SIMD3(Float.random(in: -1...1, using: &rng), Float.random(in: 0.2...1, using: &rng),
                                              Float.random(in: -1...1, using: &rng)))
        state.spinRate = kind.usesBox ? Float.random(in: 6...16, using: &rng) : 0
        let material: any Material
        if kind.unlit {
            material = unlit(color)
        } else {
            material = pbr(color, kind: kind)
        }
        if kind.usesBox {
            let slot = freeSlot(in: boxState)
            boxState[slot] = state
            boxes[slot].model?.materials = [material]
            boxes[slot].isEnabled = true
            sync(boxes[slot], boxState[slot])
        } else {
            let slot = freeSlot(in: sphereState)
            sphereState[slot] = state
            spheres[slot].model?.materials = [material]
            spheres[slot].isEnabled = true
            sync(spheres[slot], sphereState[slot])
        }
    }

    /// A seeded burst around `position`: `count` particles in an upward cone.
    func burst(_ kind: ParticleKind, count: Int, at position: SIMD3<Float>, speed: Float, colors: [UIColor],
               size: ClosedRange<Float>, spread: Float = 0.006, upBias: Float = 0.35, life: Float = 1.2,
               rng: inout SplitMix64) {
        guard !colors.isEmpty else { return }
        for _ in 0..<Self.scaled(count) {
            let dir = Burst.unitDirection(rng: &rng, upBias: upBias)
            let offset = SIMD3<Float>(Float.random(in: -1...1, using: &rng), 0, Float.random(in: -1...1, using: &rng)) * spread
            emit(kind, at: position + offset, velocity: dir * speed * Float.random(in: 0.5...1.2, using: &rng),
                 color: colors.pick(&rng), size: Float.random(in: size, using: &rng), life: life, rng: &rng)
        }
    }

    func step(dt: Float) {
        guard dt > 0 else { return }
        let h = min(dt, 1.0 / 30.0)
        for i in sphereState.indices where sphereState[i].active {
            advance(&sphereState[i], h: h)
            if sphereState[i].active { sync(spheres[i], sphereState[i]) } else { spheres[i].isEnabled = false }
        }
        for i in boxState.indices where boxState[i].active {
            advance(&boxState[i], h: h)
            if boxState[i].active { sync(boxes[i], boxState[i]) } else { boxes[i].isEnabled = false }
        }
    }

    func clear() {
        for i in sphereState.indices {
            sphereState[i].active = false
            spheres[i].isEnabled = false
        }
        for i in boxState.indices {
            boxState[i].active = false
            boxes[i].isEnabled = false
        }
    }

    var activeCount: Int {
        sphereState.filter(\.active).count + boxState.filter(\.active).count
    }

    // MARK: - Internals

    private func freeSlot(in states: [ParticleState]) -> Int {
        if let free = states.firstIndex(where: { !$0.active }) { return free }
        // Recycle the oldest transient particle, else the oldest stain.
        var best = 0
        var bestBirth = Int.max
        for (i, s) in states.enumerated() where !s.kind.persists && s.birth < bestBirth {
            best = i
            bestBirth = s.birth
        }
        if bestBirth != Int.max { return best }
        for (i, s) in states.enumerated() where s.birth < bestBirth {
            best = i
            bestBirth = s.birth
        }
        return best
    }

    private func covered(_ p: SIMD3<Float>) -> Bool {
        abs(p.x) <= plateHalfExtent.x && abs(p.z) <= plateHalfExtent.y
    }

    private func advance(_ p: inout ParticleState, h: Float) {
        p.age += h
        let gap = ceiling
        if p.stuck {
            // Stains and crumbs under the descending ram flatten further (ratchet), never re-inflate.
            if covered(p.position) {
                let height = p.size.y * p.flat
                if height > gap {
                    p.flat = max(gap / p.size.y, 0.08)
                    p.position.y = p.size.y * p.flat * 0.5
                }
            }
            return
        }
        if p.age >= p.life {
            p.active = false
            return
        }
        let motion = p.kind.motion
        p.velocity.y += -5.5 * motion.gravity * h
        p.velocity *= max(0, 1 - motion.drag * h)
        if p.kind == .confetti || p.kind == .flake {
            // Flutter.
            p.velocity.x += sin(p.age * 17 + Float(p.birth)) * 0.25 * h
        }
        p.position += p.velocity * h
        p.angle += p.spinRate * h
        let radius = p.size.y * 0.5
        for axis in 0..<2 {
            let index = axis == 0 ? 0 : 2
            if p.position[index] < minXZ[axis] {
                p.position[index] = minXZ[axis]
                p.velocity[index] = abs(p.velocity[index]) * 0.3
            } else if p.position[index] > maxXZ[axis] {
                p.position[index] = maxXZ[axis]
                p.velocity[index] = -abs(p.velocity[index]) * 0.3
            }
        }
        if covered(p.position) && p.position.y + radius > ceiling {
            p.position.y = max(ceiling - radius, radius)
            if p.velocity.y > 0 { p.velocity.y = -p.velocity.y * 0.2 }
        }
        if p.position.y - radius < 0 {
            p.position.y = radius
            switch p.kind {
            case .crumb:
                if p.velocity.y < -0.12 {
                    p.velocity.y = -p.velocity.y * 0.35
                    p.velocity.x *= 0.6
                    p.velocity.z *= 0.6
                } else {
                    land(&p, flat: 0.75, spread: 1)
                }
            case .droplet:
                land(&p, flat: 0.22, spread: 1.7)
            case .confetti, .flake:
                land(&p, flat: 1, spread: 1)
            case .fizz, .dust:
                p.velocity.y = abs(p.velocity.y) * 0.2
            case .glint, .spark:
                p.velocity.y = abs(p.velocity.y) * 0.3
                p.velocity.x *= 0.5
                p.velocity.z *= 0.5
            }
        }
    }

    private func land(_ p: inout ParticleState, flat: Float, spread: Float) {
        p.stuck = true
        p.velocity = .zero
        p.spinRate = 0
        p.size = SIMD3(p.size.x * spread, p.size.y, p.size.z * spread)
        p.flat = flat
        p.position.y = p.size.y * flat * 0.5 + 0.0002
        // Lie flat on the anvil, keep a seeded yaw.
        p.spinAxis = SIMD3(0, 1, 0)
    }

    private func sync(_ entity: ModelEntity, _ p: ParticleState) {
        var scale = p.size
        scale.y *= p.flat
        if !p.kind.persists {
            // Grow in fast, shrink out over the last 35% of life (cheaper than fading opacity).
            let t = p.age / max(p.life, 1e-3)
            var k: Float = min(1, p.age / 0.04)
            if t > 0.65 { k *= max(0, 1 - (t - 0.65) / 0.35) }
            if p.kind == .dust { k *= 0.6 + 0.8 * min(t * 2, 1) }
            scale *= max(k, 0.001)
        }
        entity.position = p.position
        entity.scale = scale
        if p.kind.usesBox {
            entity.orientation = simd_quatf(angle: p.angle, axis: p.spinAxis)
        }
    }

    private func pbr(_ color: UIColor, kind: ParticleKind) -> PhysicallyBasedMaterial {
        if let cached = pbrCache[color] { return cached }
        let material = SceneMaterials.pbr(color, roughness: kind == .crumb ? 0.6 : 0.25,
                                          clearcoat: kind == .droplet ? 1 : 0.3)
        pbrCache[color] = material
        return material
    }

    private func unlit(_ color: UIColor) -> UnlitMaterial {
        if let cached = unlitCache[color] { return cached }
        let material = SceneMaterials.unlit(color)
        unlitCache[color] = material
        return material
    }
}

/// Everything an object view may spawn into: rigid debris and particles, both in anvil space.
@MainActor
final class SceneFX {
    let root = Entity()
    let debris = DebrisSystem()
    let particles = ParticleSystem()
    /// True when Reduce Motion is on: fragments slump and settle instead of flying.
    var reduceMotion = false

    init() {
        root.addChild(debris.root)
        root.addChild(particles.root)
    }

    /// Scales burst speeds for Reduce Motion.
    var motionScale: Float { reduceMotion ? 0.25 : 1 }

    /// The ceiling's half size (x, z) from the last step: the P-48 ram plate, or the whole anvil on the Duo.
    private(set) var ceilingHalfExtent = SIMD2<Float>(0.08, 0.057)
    /// True on the iPhone Duo's Fold Press, whose virtual platen covers the whole anvil (`PressScene` steps it with a
    /// 1 m half-size ceiling), so spreads may use the full Duo strike plate instead of the P-48's smaller anvil.
    var isFoldPress: Bool { ceilingHalfExtent.x >= 0.5 }

    /// The Duo strike plate's half extents (fx metres, no padding) for the object on the anvil, set by
    /// `PressObjectFactory`. On the Fold Press the debris and particle walls close in to it (LAUNCH-QA #1: drops and
    /// beads came to rest on the page background past the plate); on the P-48 they stay at the anvil's edges.
    var foldPlateHalf: SIMD2<Float>? {
        didSet { applyWalls() }
    }
    /// Share of `foldPlateHalf` a piece's or particle's centre may reach: its edge may spill onto the plate's rim.
    static let foldWallShare: Float = 0.94
    private var appliedWalls: SIMD2<Float>?

    /// The walls (half extents about the slot origin) the mess is held inside right now.
    var wallHalf: SIMD2<Float> {
        if isFoldPress, let foldPlateHalf { return foldPlateHalf * Self.foldWallShare }
        return PressRig.anvilHalf
    }

    private func applyWalls() {
        let half = wallHalf
        guard appliedWalls != half else { return }
        appliedWalls = half
        debris.setBounds(min: -half, max: half)
        particles.minXZ = -half
        particles.maxXZ = half
    }

    func step(dt: Float, ceiling: Float, plateHalfExtent: SIMD2<Float>) {
        ceilingHalfExtent = plateHalfExtent
        applyWalls()
        debris.step(dt: dt, ceiling: ceiling, plateHalfExtent: plateHalfExtent)
        particles.ceiling = ceiling
        particles.plateHalfExtent = plateHalfExtent
        particles.step(dt: dt)
    }

    /// Persistent mess decals/spreads in anvil space (smears, puddles); cleared with the next object.
    func addMess(_ entity: Entity) {
        root.addChild(entity)
        mess.append(entity)
    }

    private var mess: [Entity] = []

    func clear() {
        debris.clear()
        particles.clear()
        for entity in mess { entity.removeFromParent() }
        mess.removeAll()
    }
}
