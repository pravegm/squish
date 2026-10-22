import Foundation
import RealityKit
import simd
import UIKit

/// Soda Can (bible §4 #7, VISUAL-TARGET §5.7): a fat tallboy of painted aluminium (fictional "FIZZO" colourway:
/// candy field, white wave band, dark drop line; bare aluminium ends), one CPU-deformed `DeformableMesh`.
/// Thin-wall buckling: the can is rigid until each buckle fires, then one concertina ring collapses (top-down)
/// with alternating diamond lobes and the ram lurches down a step — five buckles in all.
/// Fracture 2 (failure) punctures it: a fizz geyser sprays from the fold for ~0.7 s, droplets land and a puddle spreads.
/// Fizz colour per seed (lime / orange / berry); `cherryFizz` surprise makes it cherry.
@MainActor
final class SodaCanView: PressObjectView {
    let entity = Entity()
    /// Ø 0.110 × 0.140 (VISUAL-REVIEW-1 fix 6).
    let restHeight: Float = 0.150 * ObjectMeshes.canY
    let footprint: Float = 0.045 * ObjectMeshes.canR
    private let minHeightRatio: Float = 0.13
    private static var labelTextures: [UInt64: TextureResource] = [:]

    private let fx: SceneFX
    private let look: Look
    private var rng = SplitMix64(seed: 0)
    private let can: DeformableMesh
    private let puddle: ModelEntity
    private var tab = ModelEntity()
    private var fired = 0
    private var phases: [Float] = []
    private var punctured = false
    private var punctureC: Float = 1
    private var sprayTime: Float = 0
    private var sprayAngle: Float = 0
    private var lastShort: Float = -1
    private var spread: Float = 1
    private let fizz: (drop: UIColor, puddle: UIColor)

    /// Straight body between the bottom and shoulder bevels, split into five fold bands (top-down).
    static let bodyBottom: Float = ObjectMeshes.canBodyBottom
    static let bodyTop: Float = ObjectMeshes.canBodyTop
    static let folds = 5
    static var foldWidth: Float { (bodyTop - bodyBottom) / Float(folds) }

    var shadowSpread: Float { spread }

    static func profile() -> [SIMD2<Float>] {
        var points: [SIMD2<Float>] = [
            SIMD2(0.000, 0.008), SIMD2(0.018, 0.0065), SIMD2(0.028, 0.002), SIMD2(0.030, 0.000), SIMD2(0.039, 0.0015),
            SIMD2(0.043, 0.005), SIMD2(0.045, 0.011),
        ]
        // Dense straight body so the folds have vertices to bend.
        let rings = 46
        for k in 1..<rings {
            points.append(SIMD2(0.045, bodyBottom + (bodyTop - bodyBottom) * Float(k) / Float(rings)))
        }
        points += [
            SIMD2(0.045, 0.126), SIMD2(0.043, 0.134), SIMD2(0.0385, 0.142), SIMD2(0.036, 0.146), SIMD2(0.0368, 0.148),
            SIMD2(0.036, 0.150), SIMD2(0.0345, 0.149), SIMD2(0.0335, 0.1455), SIMD2(0.000, 0.1455),
        ]
        return points
    }

    /// Material slot by profile band: 0 painted field, 1 white band, 2 drop line, 3 bare aluminium.
    static func slot(_ i: Int, _ profile: [SIMD2<Float>]) -> UInt8 {
        let y = (profile[i].y + profile[i + 1].y) / 2
        if y < bodyBottom || y > bodyTop { return 3 }
        if y > 0.060 && y < 0.082 { return 1 }
        if y > 0.0835 && y < 0.0875 { return 2 }
        return 0
    }

    init(variant: PressVariant, fx: SceneFX) {
        self.fx = fx
        let look = Look(variant)
        self.look = look
        var rng = SplitMix64(seed: variant.seed ^ 0x50DA)
        let palettes: [(UIColor, UIColor)] = [
            (UIColor(hex: 0xE9F7D9), UIColor(hex: 0xC9EFA0)), (UIColor(hex: 0xFFE0B8), UIColor(hex: 0xFFB347)),
            (UIColor(hex: 0xEBD7FF), UIColor(hex: 0xC77DFF)),
        ]
        if variant.surprise == .cherryFizz {
            fizz = (UIColor(hex: 0xFFC2D1), Palette.cherryFizz)
        } else {
            fizz = palettes[Int(rng.next() % UInt64(palettes.count))]
        }
        phases = (0..<Self.folds).map { _ in Float.random(in: 0...(2 * .pi), using: &rng) }
        sprayAngle = Float.random(in: 0.6...1.4, using: &rng) // toward the camera side (+Z)

        // Fully printed body (print up to the shoulder; brighter lime, less metallic: VISUAL-REVIEW-1 fix 11).
        let label: PhysicallyBasedMaterial
        if look.golden {
            label = SceneMaterials.gold
        } else if let texture = Self.labelTexture(seed: variant.seed % 4) {
            var m = SceneMaterials.textured(texture, roughness: 0.22, clearcoat: 1, metallic: 0.35)
            m.clearcoatRoughness = .init(floatLiteral: 0.06)
            label = m
        } else {
            label = SceneMaterials.enamel(UIColor(hex: 0x96DB4E), roughness: 0.22, clearcoat: 1, clearcoatRoughness: 0.06, metallic: 0.35)
        }
        let aluminium = SceneMaterials.pbr(UIColor(hex: 0xD7DBE0), roughness: 0.20, metallic: 1)
        let mesh = MeshCache.mesh("can.body") { ObjectMeshes.canBody() }
        can = DeformableMesh(mesh, materials: [label, aluminium], maxSpread: 1.6)
        puddle = ModelEntity(mesh: MeshKit.spreadDisc(seed: variant.seed &+ 9, height: 1, segments: 64, wobble: 0.13).resource()
                             ?? .generateSphere(radius: 0.01),
                             materials: [look.golden ? SceneMaterials.goldMess
                                         : SceneMaterials.enamel(fizz.puddle, roughness: 0.05, clearcoat: 1, clearcoatRoughness: 0.03,
                                                                 opacity: 0.6)])
        puddle.isEnabled = false
        self.rng = rng
        entity.addChild(can.entity)
        entity.addChild(puddle)
        // Ring-pull tab on the lid.
        tab = Part.add(cached: "can.tab", { MeshKit.roundedBox([0.022, 0.001, 0.012], radius: 0.004, bevel: 0.0004) },
                       aluminium, at: [0.008 * ObjectMeshes.canR, 0.1462 * ObjectMeshes.canY, 0], to: entity)
        entity.orientation = Part.yaw(-15)
    }

    /// The FIZZO print (one of 4 seeded bubble layouts), drawn once and cached.
    private static func labelTexture(seed: UInt64) -> TextureResource? {
        if let cached = labelTextures[seed] { return cached }
        let image = RigTextures.canLabel(field: UIColor(hex: 0x96DB4E), drop: UIColor(hex: 0x2F7A1E), seed: 0xF122 &+ seed)
        let texture = StudioEnvironment.texture(image, name: "can.label.\(seed)")
        labelTextures[seed] = texture
        return texture
    }

    func surfaceHeight(compression c: Float) -> Float {
        // Each fired buckle drops the can a step; between buckles it barely gives (thin-wall rigidity).
        let q = 0.12 * clamp(c, 0, 1) + 0.88 * Float(fired) / Float(Self.folds)
        return restHeight * (1 - (1 - minHeightRatio) * min(q, 1))
    }

    func update(_ state: PressVisualState) {
        let h = surfaceHeight(compression: state.compression)
        let shortening = restHeight - h
        tab.position.y = h - 0.0038 * ObjectMeshes.canY
        if abs(shortening - lastShort) > 0.00005 {
            lastShort = shortening
            deform(shortening: shortening, height: h)
        }
        // Puncture spray and puddle.
        if punctured {
            if sprayTime > 0 && state.dt > 0 {
                sprayTime -= state.dt
                let rate: Float = state.reduceMotion ? 20 : 60
                let count = max(1, Int((rate * state.dt * ParticleSystem.budget).rounded()))
                let foldY = min(h * 0.62, Self.bodyTop)
                let r: Float = 0.061
                let at = entity.convert(position: [cos(sprayAngle) * r, foldY, sin(sprayAngle) * r], to: fx.root)
                let dirLocal = SIMD3<Float>(cos(sprayAngle), 0.9, sin(sprayAngle))
                let dir = simd_normalize(entity.convert(direction: dirLocal, to: fx.root))
                for _ in 0..<count {
                    let jitter = SIMD3<Float>(Float.random(in: -0.3...0.3, using: &rng), Float.random(in: -0.2...0.3, using: &rng),
                                              Float.random(in: -0.3...0.3, using: &rng))
                    let v = simd_normalize(dir + jitter) * 0.75 * fx.motionScale.squareRoot() * Float.random(in: 0.6...1.2, using: &rng)
                    let kind: ParticleKind = rng.next() % 3 == 0 ? .droplet : .fizz
                    fx.particles.emit(kind, at: at, velocity: v, color: look.tint(fizz.drop),
                                      size: Float.random(in: 0.002...0.004, using: &rng), life: 0.7, rng: &rng)
                }
            }
            let t = clamp((state.compression - punctureC) / max(1 - punctureC, 0.05), 0, 1)
            let radius = 0.05 + 0.02 * t
            puddle.isEnabled = true
            puddle.scale = SIMD3(radius, 0.0015, radius * 0.9)
            spread = max(spread, radius / footprint)
        }
    }

    /// Distributes the shortening: a small uniform elastic part, the rest folded into the fired bands top-down.
    private func deform(shortening: Float, height: Float) {
        let w = Self.foldWidth
        let capacity = w * 0.8
        var remaining = max(shortening, 0)
        var collapse = [Float](repeating: 0, count: Self.folds)
        for k in 0..<min(fired, Self.folds) {
            let a = min(remaining, capacity)
            collapse[k] = a
            remaining -= a
        }
        let folded = collapse.reduce(0, +)
        let elasticScale = height / max(restHeight - folded, 1e-4)
        var maxBulge: Float = 0
        let phases = self.phases
        can.update { p in
            var y = p.y
            var radial: Float = 1
            let r = (p.x * p.x + p.z * p.z).squareRoot()
            let theta = atan2(p.z, p.x)
            var drop: Float = 0
            // Bands are numbered top-down; walk them bottom-up to accumulate the drop.
            for k in stride(from: Self.folds - 1, through: 0, by: -1) {
                let a = collapse[k]
                guard a > 0 else { continue }
                let bandTop = Self.bodyTop - w * Float(k)
                let bandBottom = bandTop - w
                if p.y >= bandTop {
                    drop += a
                } else if p.y > bandBottom {
                    let u = (p.y - bandBottom) / w
                    drop += a * u
                    let depth = 0.5 * (w * w - (w - a) * (w - a)).squareRoot() * 0.6
                    let lobes = 0.65 + 0.35 * cos(6 * theta + phases[k])
                    radial += depth * lobes * sin(.pi * u) / max(r, 0.01)
                }
            }
            y = (p.y - drop) * elasticScale
            maxBulge = max(maxBulge, radial)
            return SIMD3(p.x * radial, y, p.z * radial)
        }
        spread = max(spread, min(maxBulge, 1.4))
    }

    func fracture(index: Int, isFailure: Bool, state: PressVisualState) {
        fired = max(fired, index + 1)
        // A glint where the fold creases.
        let foldY = Self.bodyTop - Self.foldWidth * (Float(index) + 0.5)
        let at = entity.convert(position: [0, min(foldY, state.ramFace - 0.005), 0.057], to: fx.root)
        fx.particles.burst(.glint, count: 2, at: at, speed: 0.08, colors: [UIColor(hex: 0xFFFFFF)],
                           size: 0.002...0.003, upBias: 0.2, life: 0.25, rng: &rng)
        if isFailure {
            punctured = true
            punctureC = state.compression
            sprayTime = state.reduceMotion ? 0.35 : 0.7
            // The initial "pssht": a burst of foam.
            let spray = entity.convert(position: [cos(sprayAngle) * 0.058, min(foldY, 0.085), sin(sprayAngle) * 0.058], to: fx.root)
            fx.particles.burst(.fizz, count: 12, at: spray, speed: 0.5 * max(fx.motionScale, 0.4), colors: [look.tint(fizz.drop)],
                               size: 0.002...0.004, spread: 0.004, upBias: 0.3, life: 0.6, rng: &rng)
            fx.particles.burst(.crumb, count: 6, at: spray, speed: 0.25 * max(fx.motionScale, 0.4), colors: [UIColor(hex: 0xF8F8F8)],
                               size: 0.003...0.005, spread: 0.004, upBias: 0.3, rng: &rng)
        }
    }
}
