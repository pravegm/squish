import Foundation
import RealityKit
import simd

/// One rigid piece (shard, shell chip, crayon chunk) in the debris simulation. Pure value type, unit-testable.
struct DebrisBody {
    var position: SIMD3<Float>
    var velocity: SIMD3<Float>
    var orientation: simd_quatf
    var angularVelocity: SIMD3<Float>
    /// Half extents of the piece in its own (scaled) frame.
    var halfExtents: SIMD3<Float>
    var bounciness: Float = 0.25
    var friction: Float = 0.6
    /// Plastic flattening along `upAxis` (ratchet: only ever decreases).
    var flat: Float = 1
    var upAxis: Int = 1
    var settled = false
    /// True when the transform changed since the last sync.
    var dirty = true

    /// Scale multiplier (relative to the piece's base scale): flattened along the up axis, spread on the others.
    var scaleFactor: SIMD3<Float> {
        let spread = min(1 / max(flat, 0.05).squareRoot(), 1.8)
        var s = SIMD3<Float>(repeating: spread)
        s[upAxis] = flat
        return s
    }

    /// Vertical half-size of the rotated, flattened box (its support height above the floor).
    var support: Float {
        let m = simd_float3x3(orientation)
        let e = halfExtents * scaleFactor
        return abs(m.columns.0.y) * e.x + abs(m.columns.1.y) * e.y + abs(m.columns.2.y) * e.z
    }
}

/// Deterministic rigid-debris world (bible §9: pre-sliced pieces with seeded impulses, settle and persist).
/// Floor = anvil top (y = 0), invisible walls at the anvil edges (mess stays tidy), ceiling = the ram face,
/// which flattens settled pieces inside its footprint. Fixed 240 Hz steps, so the same seed and dt sequence
/// always gives the same result.
struct DebrisWorld {
    static let fixedStep: Float = 1.0 / 240.0
    /// Stylised gravity: a little floatier than 9.8 so centimetre pieces read at phone scale.
    var gravity: Float = -5.5
    var floorY: Float = 0
    var minXZ = SIMD2<Float>(-0.105, -0.072)
    var maxXZ = SIMD2<Float>(0.105, 0.075)
    var ceiling: Float = 10
    /// Half size (x, z) of the ram plate; the ceiling only exists over it.
    var ceilingHalfExtent = SIMD2<Float>(0.08, 0.057)
    var minFlat: Float = 0.12
    var bodies: [DebrisBody] = []
    private var accumulator: Float = 0

    mutating func step(dt: Float) {
        accumulator += min(max(dt, 0), 0.1)
        while accumulator >= Self.fixedStep {
            accumulator -= Self.fixedStep
            for i in bodies.indices {
                var body = bodies[i]
                integrate(&body, h: Self.fixedStep)
                bodies[i] = body
            }
        }
    }

    private func underCeiling(_ p: SIMD3<Float>) -> Bool {
        abs(p.x) <= ceilingHalfExtent.x && abs(p.z) <= ceilingHalfExtent.y
    }

    private func integrate(_ b: inout DebrisBody, h: Float) {
        let gap = ceiling - floorY
        let covered = underCeiling(b.position)

        // The ram is pressing this piece: pin it to the floor and flatten (ratchet).
        if covered && b.support * 2 > gap {
            if !b.settled { alignToRest(&b, rate: 1) }
            b.settled = true
            b.velocity = .zero
            b.angularVelocity = .zero
            let support = b.support
            if support > 1e-5 {
                let wanted = b.flat * (gap * 0.5) / support
                let newFlat = max(min(b.flat, wanted), minFlat)
                if newFlat < b.flat - 1e-5 {
                    b.flat = newFlat
                    b.dirty = true
                }
            }
            let y = floorY + b.support
            if abs(b.position.y - y) > 1e-6 {
                b.position.y = y
                b.dirty = true
            }
            return
        }

        if b.settled {
            // Ease into a face-down rest pose; otherwise nothing moves.
            if alignToRest(&b, rate: 0.08) { b.dirty = true }
            let y = floorY + b.support
            if abs(b.position.y - y) > 1e-6 {
                b.position.y = y
                b.dirty = true
            }
            return
        }

        b.velocity.y += gravity * h
        b.position += b.velocity * h
        let w = simd_length(b.angularVelocity)
        if w > 1e-5 {
            let dq = simd_quatf(angle: w * h, axis: b.angularVelocity / w)
            b.orientation = simd_normalize(dq * b.orientation)
        }
        b.dirty = true

        // Walls keep the mess on the anvil.
        for axis in 0..<2 {
            let index = axis == 0 ? 0 : 2
            let lo = minXZ[axis], hi = maxXZ[axis]
            if b.position[index] < lo {
                b.position[index] = lo
                b.velocity[index] = abs(b.velocity[index]) * 0.3
            } else if b.position[index] > hi {
                b.position[index] = hi
                b.velocity[index] = -abs(b.velocity[index]) * 0.3
            }
        }

        // Ceiling (ram face) for pieces flying up.
        let support = b.support
        if covered && b.position.y + support > ceiling {
            b.position.y = ceiling - support
            if b.velocity.y > 0 { b.velocity.y = -b.velocity.y * 0.3 }
        }

        // Floor.
        if b.position.y - support < floorY {
            b.position.y = floorY + support
            if b.velocity.y < 0 {
                b.velocity.y = -b.velocity.y * b.bounciness
                if b.velocity.y < 0.06 { b.velocity.y = 0 }
            }
            let grip = max(0, 1 - b.friction * 12 * h)
            b.velocity.x *= grip
            b.velocity.z *= grip
            b.angularVelocity *= max(0, 1 - 10 * h)
            alignToRest(&b, rate: 0.02)
            if simd_length(b.velocity) < 0.025 && simd_length(b.angularVelocity) < 0.8 {
                b.settled = true
                b.velocity = .zero
                b.angularVelocity = .zero
            }
        } else {
            // Light air drag.
            b.velocity *= max(0, 1 - 0.4 * h)
        }
    }

    /// Rotates the piece toward resting on its most-downward face. Returns true if it moved.
    @discardableResult
    private func alignToRest(_ b: inout DebrisBody, rate: Float) -> Bool {
        let m = simd_float3x3(b.orientation)
        let columns = [m.columns.0, m.columns.1, m.columns.2]
        // Prefer the thinnest axis when it is reasonably upright (shards lie flat).
        var best = 0
        var bestScore: Float = -1
        let e = b.halfExtents
        let thinness = SIMD3<Float>(1 / max(e.x, 1e-4), 1 / max(e.y, 1e-4), 1 / max(e.z, 1e-4))
        let maxThin = max(thinness.x, max(thinness.y, thinness.z))
        for k in 0..<3 {
            let score = abs(columns[k].y) * (0.6 + 0.4 * thinness[k] / maxThin)
            if score > bestScore {
                bestScore = score
                best = k
            }
        }
        if !b.settled { b.upAxis = best }
        let axis = columns[b.upAxis]
        let target = SIMD3<Float>(0, axis.y >= 0 ? 1 : -1, 0)
        let dot = simd_dot(simd_normalize(axis), target)
        if dot > 0.99999 { return false }
        let align = simd_quatf(from: simd_normalize(axis), to: target)
        let step = simd_slerp(simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)), align, min(rate, 1))
        b.orientation = simd_normalize(step * b.orientation)
        return true
    }
}

/// Seeded impulse helpers for bursts.
enum Burst {
    /// An outward-and-up velocity for a piece at `position` bursting from `centre`.
    static func velocity(from centre: SIMD3<Float>, to position: SIMD3<Float>, speed: Float, up: Float,
                         rng: inout SplitMix64) -> SIMD3<Float> {
        var dir = position - centre
        dir.y = 0
        if simd_length(dir) < 1e-5 {
            let a = Float.random(in: 0...(2 * .pi), using: &rng)
            dir = SIMD3(cos(a), 0, sin(a))
        }
        dir = simd_normalize(dir)
        let jitter = Float.random(in: 0.6...1.2, using: &rng)
        return dir * speed * jitter + SIMD3(0, up * Float.random(in: 0.5...1.1, using: &rng), 0)
    }

    static func spin(_ magnitude: Float, rng: inout SplitMix64) -> SIMD3<Float> {
        SIMD3(Float.random(in: -1...1, using: &rng), Float.random(in: -1...1, using: &rng),
              Float.random(in: -1...1, using: &rng)) * magnitude
    }

    static func unitDirection(rng: inout SplitMix64, upBias: Float = 0.5) -> SIMD3<Float> {
        let a = Float.random(in: 0...(2 * .pi), using: &rng)
        let y = Float.random(in: upBias...1, using: &rng)
        let r = (1 - y * y).squareRoot()
        return SIMD3(r * cos(a), y, r * sin(a))
    }
}

/// Maps `DebrisWorld` bodies onto entities. Pieces are reparented into `root` (anvil space, never shaken)
/// and persist until the next object is placed. Hard cap 64 pieces (bible §9 allows 300).
@MainActor
final class DebrisSystem {
    static let maxPieces = 64

    let root = Entity()
    private(set) var world = DebrisWorld()
    private var entities: [Entity] = []
    private var baseScales: [SIMD3<Float>] = []

    var count: Int { entities.count }

    /// Invisible walls (x, z) that keep the mess on the anvil.
    func setBounds(min lo: SIMD2<Float>, max hi: SIMD2<Float>) {
        world.minXZ = lo
        world.maxXZ = hi
    }

    /// Takes over an existing entity (keeps its world transform).
    func adopt(_ entity: Entity, velocity: SIMD3<Float>, spin: SIMD3<Float>,
               bounciness: Float = 0.25, friction: Float = 0.6) {
        guard entities.count < Self.maxPieces else { return }
        entity.setParent(root, preservingWorldTransform: true)
        let local = entity.visualBounds(relativeTo: entity)
        let extent = simd_max(simd_abs(local.min), simd_abs(local.max))
        let scale = entity.scale
        let body = DebrisBody(position: entity.position, velocity: velocity, orientation: entity.orientation,
                              angularVelocity: spin, halfExtents: simd_max(extent * scale, SIMD3(repeating: 0.0008)),
                              bounciness: bounciness, friction: friction)
        world.bodies.append(body)
        entities.append(entity)
        baseScales.append(scale)
    }

    /// Removes one adopted entity from the simulation (e.g. a chunk that splits again). Returns its body.
    @discardableResult
    func release(_ entity: Entity) -> DebrisBody? {
        guard let index = entities.firstIndex(where: { $0 === entity }) else { return nil }
        let body = world.bodies.remove(at: index)
        entities.remove(at: index)
        baseScales.remove(at: index)
        return body
    }

    func body(for entity: Entity) -> DebrisBody? {
        guard let index = entities.firstIndex(where: { $0 === entity }) else { return nil }
        return world.bodies[index]
    }

    func step(dt: Float, ceiling: Float, plateHalfExtent: SIMD2<Float>) {
        world.ceiling = ceiling
        world.ceilingHalfExtent = plateHalfExtent
        world.step(dt: dt)
        for i in world.bodies.indices where world.bodies[i].dirty {
            let body = world.bodies[i]
            entities[i].position = body.position
            entities[i].orientation = body.orientation
            entities[i].scale = baseScales[i] * body.scaleFactor
            world.bodies[i].dirty = false
        }
    }

    func clear() {
        for entity in entities { entity.removeFromParent() }
        entities.removeAll()
        baseScales.removeAll()
        world.bodies.removeAll()
    }
}
