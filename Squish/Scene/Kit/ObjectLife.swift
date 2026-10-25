import Foundation
import RealityKit
import simd
import UIKit

/// Per-object life on one extra node under the view's entity (OBJECT-STORYBOARDS §0): an idle breath / wobble / rock
/// before contact (with a seeded, occasional highlight glint), a squash pulse on every storyboard beat and a 14 Hz
/// tremor in the tell. Transform only: it never touches a mesh, so it costs one transform write a frame while
/// anything moves and nothing once it has settled back to identity.
@MainActor
final class ObjectLife {
    enum Idle {
        /// Vertical breathing (soft things).
        case breathe
        /// A soft lean that wanders round (gels).
        case wobble
        /// A slow rock about the long axis (lying and floating things).
        case rock
        /// No motion, only the glint (rigid things).
        case still
    }

    let node = Entity()
    private let idle: Idle
    private let amount: Float
    private let rate: Float
    private let phase: Float
    private var rng: SplitMix64
    /// 1 while the object waits for the plate, 0 once it has been touched (latched).
    private var weight: Float = 1
    private var touched = false
    private var pulse: JiggleSpring
    private var tremorLeft: Float = 0
    private var tremorLevel: Float = 0
    private var nextSheen: Float
    private var moving = false
    private var reduceMotion = false

    /// - Parameters:
    ///   - amount: idle amplitude (breathe: scale share; wobble / rock: radians).
    ///   - rate: idle frequency (Hz), seeded ±15 %.
    ///   - pulseHz: the beat pulse's spring (soft things ring slower).
    init(seed: UInt64, idle: Idle, amount: Float, rate: Float, pulseHz: Float = 5, pulseDamping: Float = 0.35) {
        var rng = SplitMix64(seed: seed ^ 0x11FE)
        self.idle = idle
        self.amount = amount
        self.rate = rate * Float.random(in: 0.85...1.15, using: &rng)
        phase = Float.random(in: 0...(2 * .pi), using: &rng)
        nextSheen = Float.random(in: 0.8...2.2, using: &rng)
        self.rng = rng
        pulse = JiggleSpring(value: 0, velocity: 0, omega: 2 * .pi * pulseHz, zeta: pulseDamping)
    }

    /// Re-parents every current child of `entity` under the life node (call once, at the end of the view's init).
    func adopt(childrenOf entity: Entity) {
        for child in Array(entity.children) where child !== node {
            child.setParent(node, preservingWorldTransform: false)
        }
        entity.addChild(node)
    }

    /// A squash pulse: positive squashes (y down, xz out), negative springs up. Halved under Reduce Motion.
    func kick(_ amount: Float) {
        pulse.kick(reduceMotion ? amount * 0.4 : amount)
    }

    /// A 14 Hz tremor for `seconds` (off under Reduce Motion).
    func tremor(_ seconds: Float, level: Float = 1) {
        tremorLeft = max(tremorLeft, seconds)
        tremorLevel = max(tremorLevel, level)
    }

    /// True once the plate has touched (no more idle).
    var isTouched: Bool { touched }

    /// Steps the life and writes the node's transform. Returns true when the idle wants a highlight glint now.
    @discardableResult
    func update(_ state: PressVisualState) -> Bool {
        reduceMotion = state.reduceMotion
        if state.compression > 0.001 || state.phase == .sealed || state.phase == .revealing { touched = true }
        let dt = state.dt
        let target: Float = touched ? 0 : 1 - Self.smooth(0.75, 1.0, state.approach)
        weight = touched ? Deform.approach(weight, 0, halfLife: 0.08, dt: dt) : Deform.approach(weight, target, halfLife: 0.15, dt: dt)
        if weight < 0.002 && touched { weight = 0 }
        pulse.step(toward: 0, dt: dt)
        if tremorLeft > 0 { tremorLeft -= dt } else { tremorLevel = 0 }

        var wantsSheen = false
        if !touched && weight > 0.6 && !state.reduceMotion && state.time >= nextSheen && dt > 0 {
            nextSheen = state.time + Float.random(in: 2.2...4.2, using: &rng)
            wantsSheen = true
        }

        let active = !state.reduceMotion && (weight > 0 || abs(pulse.value) > 1e-4 || abs(pulse.velocity) > 1e-3 || tremorLeft > 0)
        guard active else {
            if moving {
                node.transform = Transform.identity
                moving = false
            }
            return wantsSheen
        }
        moving = true
        let t = state.time * rate * 2 * .pi + phase
        var scale = SIMD3<Float>(repeating: 1)
        var rotation = simd_quatf(angle: 0, axis: [0, 1, 0])
        let w = weight
        switch idle {
        case .breathe:
            let b = amount * w * sin(t)
            scale = SIMD3(1 - 0.5 * b, 1 + b, 1 - 0.5 * b)
        case .wobble:
            let ax = amount * w * sin(t), az = amount * w * 0.7 * sin(1.37 * t + 1.1)
            rotation = simd_quatf(angle: ax, axis: [1, 0, 0]) * simd_quatf(angle: az, axis: [0, 0, 1])
            let b = amount * 0.25 * w * sin(2 * t)
            scale = SIMD3(1 - 0.5 * b, 1 + b, 1 - 0.5 * b)
        case .rock:
            rotation = simd_quatf(angle: amount * w * sin(t), axis: [1, 0, 0])
        case .still:
            break
        }
        let p = clamp(pulse.value, -0.12, 0.12)
        scale *= SIMD3(1 + 0.5 * p, 1 - p, 1 + 0.5 * p)
        if tremorLeft > 0 {
            let k = 0.006 * tremorLevel * min(tremorLeft / 0.1, 1)
            let s = state.time * 2 * .pi * 14
            rotation = rotation * simd_quatf(angle: k * sin(s), axis: [0, 0, 1]) * simd_quatf(angle: k * 0.8 * cos(s * 1.13), axis: [1, 0, 0])
        }
        node.transform = Transform(scale: scale, rotation: rotation, translation: .zero)
        return wantsSheen
    }

    private static func smooth(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
        let t = clamp((x - e0) / max(e1 - e0, 1e-5), 0, 1)
        return t * t * (3 - 2 * t)
    }
}

/// Material squeezed out of the pinch line (OBJECT-STORYBOARDS §0, EXPERIENCE-2 A2 "ooze leaves from the pinch line"):
/// seeded lobes round the object's footprint ellipse that emerge one per `.ooze` beat, push out from under the edge as
/// the press closes and never pull back (latched), so the mess on the plate records the press. Each lobe is one cached
/// flat blob scaled in place (no mesh upload); one droplet may fly from its tip and stays as a stain.
@MainActor
final class OozeRing {
    let root = Entity()
    private struct Lobe {
        let model: ModelEntity
        let direction: SIMD2<Float>
        let edge: Float
        let width: Float
        let reach: Float
        var startC: Float = 1
        var grown: Float = 0
    }
    private var lobes: [Lobe] = []
    private var shown = 0
    private let thickness: Float
    private var lastC: Float = -1
    private var lastScale: Float = -1

    /// - Parameters:
    ///   - radii: the footprint ellipse (x, z) the lobes leave from, in the parent's local metres.
    ///   - reach: how far past the edge a lobe ends up, metres (seeded per lobe in this range).
    ///   - width: a lobe's width, metres.
    ///   - maxRadius: no lobe tip goes further than this from the centre (keeps the mess on the strike plate).
    init(seed: UInt64, count: Int, centre: SIMD2<Float> = .zero, radii: SIMD2<Float>, reach: ClosedRange<Float>,
         width: ClosedRange<Float>, thickness: Float, maxRadius: Float, material: any RealityKit.Material, y: Float = 0.0003) {
        var rng = SplitMix64(seed: seed ^ 0x0022E)
        self.thickness = thickness
        root.position = [centre.x, y, centre.y]
        let mesh = MeshCache.resource("ooze.lobe") { MeshKit.spreadDisc(seed: 0x0022E, height: 1, segments: 32, wobble: 0.16) }
            ?? MeshResource.generateSphere(radius: 0.5)
        let offset = Float.random(in: 0...(2 * .pi), using: &rng)
        // Lobes come out in a seeded order round the rim, not neighbour by neighbour.
        var angles: [Float] = (0..<max(count, 1)).map { k in
            offset + 2 * .pi * Float(k) / Float(max(count, 1)) + Float.random(in: -0.25...0.25, using: &rng)
        }
        angles.shuffle(using: &rng)
        for a in angles {
            let d = SIMD2<Float>(cos(a), sin(a))
            let edge = 1 / max((d.x * d.x / (radii.x * radii.x) + d.y * d.y / (radii.y * radii.y)).squareRoot(), 1e-4)
            let w = Float.random(in: width, using: &rng)
            let r = min(Float.random(in: reach, using: &rng), max(maxRadius - edge - w * 0.2, 0.002))
            let model = ModelEntity(mesh: mesh, materials: [material])
            model.isEnabled = false
            model.scale = SIMD3(repeating: 0.0001)
            ShadowCasting.off(model)
            // Local +X along the lobe (radially out), yawed into place.
            model.orientation = simd_quatf(angle: -a, axis: [0, 1, 0])
            root.addChild(model)
            lobes.append(Lobe(model: model, direction: d, edge: edge, width: w, reach: r))
        }
    }

    var emitted: Int { shown }
    var capacity: Int { lobes.count }

    /// Shows the next lobe; its growth starts at compression `c`. Returns its tip in the ring's parent space (for a
    /// droplet), or nil when every lobe is out.
    @discardableResult
    func emit(at c: Float) -> SIMD3<Float>? {
        guard shown < lobes.count else { return nil }
        lobes[shown].startC = c
        lobes[shown].grown = 0.2
        lobes[shown].model.isEnabled = true
        let lobe = lobes[shown]
        shown += 1
        lastC = -1
        let tip = lobe.direction * (lobe.edge + lobe.reach * 0.5)
        return root.position + SIMD3(tip.x, 0.004, tip.y)
    }

    /// The give (EXPERIENCE-REVIEW-1 #1): every lobe already out jumps outward by `amount` of its reach at once, in the
    /// same frame as the burst (latched, like the rest of the squeeze-out).
    func shove(_ amount: Float) {
        guard shown > 0 else { return }
        for i in 0..<shown { lobes[i].grown = min(lobes[i].grown + amount, 1) }
        lastC = -1
    }

    /// Grows the lobes with compression `c` (latched) and follows the footprint's growth `spread` (1 = rest).
    func update(compression c: Float, spread: Float = 1) {
        guard shown > 0, abs(c - lastC) > 0.002 || abs(spread - lastScale) > 0.005 else { return }
        lastC = c
        lastScale = spread
        for i in 0..<shown {
            let t = clamp((c - lobes[i].startC) / 0.22, 0, 1)
            lobes[i].grown = max(lobes[i].grown, 0.2 + 0.8 * (1 - (1 - t) * (1 - t)))
            let lobe = lobes[i]
            let length = max(lobe.reach * lobe.grown, 0.001)
            // The lobe's root stays tucked under the (spreading) edge; it pushes out past it.
            let edge = lobe.edge * min(spread, 1.6)
            let tuck = min(lobe.width * 0.3, edge * 0.5)
            let centre = lobe.direction * (edge - tuck + (length + tuck) * 0.5)
            lobe.model.position = SIMD3(centre.x, 0, centre.y)
            lobe.model.scale = SIMD3((length + tuck) * 0.5, thickness * (0.7 + 0.3 * lobe.grown), lobe.width * 0.5)
        }
    }
}

/// Small shared beat effects.
@MainActor
enum BeatFX {
    /// A highlight glint at `local` (in `entity`), the idle sheen and the `.sheen` / `.kiss` beats.
    static func glint(_ fx: SceneFX, at local: SIMD3<Float>, in entity: Entity, count: Int = 2, golden: Bool = false,
                      rng: inout SplitMix64) {
        let at = entity.convert(position: local, to: fx.root)
        fx.particles.burst(.glint, count: count, at: at, speed: 0.04, colors: [golden ? UIColor(hex: 0xFFF1C4) : UIColor(hex: 0xFFFFFF)],
                           size: 0.002...0.0035, spread: 0.004, upBias: 0.6, life: 0.3, rng: &rng)
    }

    /// A small puff of air or dust at `local`.
    static func puff(_ fx: SceneFX, at local: SIMD3<Float>, in entity: Entity, count: Int = 3, color: UIColor = UIColor(hex: 0xFFFDF6),
                     speed: Float = 0.05, rng: inout SplitMix64) {
        let at = entity.convert(position: local, to: fx.root)
        fx.particles.burst(.dust, count: count, at: at, speed: speed * max(fx.motionScale, 0.4), colors: [color],
                           size: 0.003...0.005, spread: 0.003, upBias: 0.3, life: 0.45, rng: &rng)
    }

    /// Droplets flung outward from `local` along `direction` (x, z); they land and stay.
    static func fling(_ fx: SceneFX, at local: SIMD3<Float>, in entity: Entity, direction: SIMD2<Float>, count: Int,
                      colors: [UIColor], size: ClosedRange<Float> = 0.0025...0.0045, speed: Float = 0.22, rng: inout SplitMix64) {
        let at = entity.convert(position: local, to: fx.root)
        let dir3 = entity.convert(direction: SIMD3(direction.x, 0, direction.y), to: fx.root)
        let flat = simd_length(SIMD2(dir3.x, dir3.z)) > 1e-5 ? simd_normalize(SIMD2(dir3.x, dir3.z)) : SIMD2<Float>(1, 0)
        for _ in 0..<ParticleSystem.scaled(count) {
            let spreadAngle = Float.random(in: -0.5...0.5, using: &rng)
            let d = SIMD2(flat.x * cos(spreadAngle) - flat.y * sin(spreadAngle), flat.x * sin(spreadAngle) + flat.y * cos(spreadAngle))
            let v = SIMD3<Float>(d.x, Float.random(in: 0.3...0.7, using: &rng), d.y) * speed * max(fx.motionScale, 0.3)
                * Float.random(in: 0.6...1.2, using: &rng)
            fx.particles.emit(.droplet, at: at, velocity: v, color: colors.pick(&rng), size: Float.random(in: size, using: &rng),
                              rng: &rng)
        }
    }
}
