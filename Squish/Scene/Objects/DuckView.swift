import Foundation
import RealityKit
import simd
import UIKit

/// Rubber Duck (bible §4 #2, VISUAL-TARGET §5.2): the classic bath duck as one smooth SDF blob (body, chest, tail,
/// head, wings), a two-lobe beak, glossy eyes. The only object with a face, because it survives.
/// Squashes into a cartoon pancake (volume-preserving), honks (beak pops), the seam "bloops" (a 6% deflate and
/// an air puff), and springs back with overshoot when the ram lifts (elastic 35% plasticity in Core).
@MainActor
final class DuckView: PressObjectView {
    let entity = Entity()
    /// Hero scale ×1.25 (VISUAL-REVIEW-1 fix 6): the model is authored at 0.085 m and scaled on `entity`.
    static let heroScale: Float = 1.25
    let restHeight: Float = 0.085 * DuckView.heroScale
    let footprint: Float = 0.052 * DuckView.heroScale
    private let minHeightRatio: Float = 0.18

    private let squash = Entity()
    private let beak: ModelEntity
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
    private var popC: Float = 1

    var shadowSpread: Float { spread }

    init(variant: PressVariant, fx: SceneFX) {
        self.fx = fx
        let look = Look(variant)
        self.look = look
        rng = SplitMix64(seed: variant.seed ^ 0xD0C)
        var body = look.golden ? SceneMaterials.gold
            : SceneMaterials.enamel(Palette.duckYellow, roughness: 0.28, clearcoat: 0.8, clearcoatRoughness: 0.10)
        if !look.golden {
            body.emissiveColor = .init(color: UIColor(hex: 0xFFB000))
            body.emissiveIntensity = 0.04
        }
        let beakMaterial = SceneMaterials.enamel(Palette.beakOrange, roughness: 0.30, clearcoat: 0.8, clearcoatRoughness: 0.1)
        let eyeMaterial = SceneMaterials.enamel(UIColor(hex: 0x1E1B24), roughness: 0.04, clearcoat: 1, clearcoatRoughness: 0.02)

        let bodyResource = MeshCache.resource("duck.body") { ObjectMeshes.duckBody() }
        let beakResource = MeshCache.resource("duck.beak") { ObjectMeshes.duckBeak() }
        beak = ModelEntity(mesh: beakResource ?? .generateSphere(radius: 0.01), materials: [beakMaterial])
        let bodyModel = ModelEntity(mesh: bodyResource ?? .generateSphere(radius: 0.03), materials: [body])
        squash.addChild(bodyModel)
        squash.addChild(beak)
        for side: Float in [-1, 1] {
            Part.add(cached: "duck.eye", { MeshKit.sphere(radius: 0.0034, segments: 24, rings: 12) }, eyeMaterial,
                     at: [0.035, 0.068, 0.012 * side], to: squash)
        }
        // Seam: short dark segments following the top of the back, hidden until the seam pops.
        let seamMaterial = SceneMaterials.pbr(UIColor(hex: 0x9A7414), roughness: 0.5)
        var previous: SIMD3<Float>?
        for k in 0...7 {
            let x = -0.034 + 0.040 * Float(k) / 7
            let top = 0.026 + 0.026 * max(1 - (x / 0.038) * (x / 0.038), 0).squareRoot() + 0.0006
            let point = SIMD3<Float>(x, top, (k % 2 == 0 ? 0.0012 : -0.0012))
            if let previous {
                let d = point - previous
                let length = simd_length(d)
                let segment = MeshKit.model(MeshKit.roundedBox([length + 0.0008, 0.0014, 0.0016], radius: 0.0005, bevel: 0.0003),
                                            material: seamMaterial)
                segment.position = (point + previous) / 2
                segment.orientation = simd_quatf(from: [1, 0, 0], to: d / max(length, 1e-6))
                seam.addChild(segment)
            }
            previous = point
        }
        seam.isEnabled = false
        squash.addChild(seam)
        skirt = ModelEntity(mesh: MeshCache.resource("duck.skirt") { MeshKit.spreadDisc(seed: 0xD5C, height: 1, segments: 48, wobble: 0.08) }
                            ?? .generateSphere(radius: 0.01), materials: [body])
        skirt.isEnabled = false
        entity.addChild(skirt)
        entity.addChild(squash)
        // 3/4 view, beak toward camera-right (+X forward, yaw −30°).
        entity.orientation = Part.yaw(-30)
        entity.scale = SIMD3(repeating: Self.heroScale)
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
        let target = surfaceHeight(compression: state.compression) / restHeight
        // The hand owns the squash; on unloading the vinyl springs back with overshoot (ζ 0.4).
        if target < height.value {
            height.value = target
            height.velocity = 0
        } else {
            height.step(toward: target, dt: state.dt)
        }
        beakPop.step(toward: 0, dt: state.dt)
        let s = max(min(height.value, 1.05), 0.05)
        // Volume-preserving: XZ × 1/√s, clamped so the pancake stays ≤ Ø 0.15.
        spread = min(1 / s.squareRoot(), 1.2) * deflate
        squash.scale = SIMD3(spread, s * deflate, spread)
        let pop = 1 + max(beakPop.value, -0.3)
        beak.scale = SIMD3(pop, 1, pop)
        if seamPopped {
            // The skirt squeezes out from under the pancake with compression past the pop (local units, ×heroScale).
            let t = clamp((state.compression - popC) / max(1 - popC, 0.05), 0, 1)
            let radius = 0.040 * spread * (1.1 + 0.45 * t)
            skirt.scale = SIMD3(radius, 0.003, radius * 0.8)
            spread = max(spread, radius / 0.040 * 0.9)
        }
    }

    func fracture(index: Int, isFailure: Bool, state: PressVisualState) {
        if isFailure {
            // Seam pop: a comic "bloop" — slight permanent deflate and a puff of air from the tail.
            deflate = 0.94
            height.kick(-1.5)
            seamPopped = true
            popC = state.compression
            seam.isEnabled = true
            skirt.isEnabled = true
            let at = entity.convert(position: [-0.04, 0.03, 0], to: fx.root)
            fx.particles.burst(.dust, count: 5, at: at, speed: 0.08 * max(fx.motionScale, 0.4),
                               colors: [UIColor(hex: 0xFFFDF6)], size: 0.004...0.008, upBias: 0.3, life: 0.5, rng: &rng)
        } else {
            // Honk: the beak pops and a little air ring leaves it.
            beakPop.kick(3)
            let at = entity.convert(position: [0.055, 0.055, 0], to: fx.root)
            fx.particles.burst(.dust, count: 3, at: at, speed: 0.05, colors: [UIColor(hex: 0xFFFDF6)],
                               size: 0.003...0.005, upBias: 0.1, life: 0.35, rng: &rng)
        }
    }

    func handle(_ event: PressEvent, state: PressVisualState) {
        if event == .contact { beakPop.kick(1) }
    }
}
