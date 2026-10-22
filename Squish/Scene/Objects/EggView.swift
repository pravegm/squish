import Foundation
import RealityKit
import simd
import UIKit

/// Egg (bible §4 #5, VISUAL-TARGET §5.5): a lying egg, blunt end camera-left, built as 12 pre-sliced shell shards
/// (lathe patches with a 1.2 mm wall and a membrane-coloured inside) that read as one smooth egg until it gives.
/// Fracture 0 (~0.12): a hairline crack grows from the top. Fracture 1 (failure, ~0.24): the shell gives — shards
/// tumble and settle, albumen and a glossy yolk dome appear. Fracture 2 (~0.50): the yolk breaks and spreads.
/// Surprises: `toyChick` (a faceless yellow toy that pops out unharmed and squashes like the duck),
/// `doubleYolk`. Nothing bodily: candy yellows and cream.
@MainActor
final class EggView: PressObjectView {
    let entity = Entity()
    let restHeight: Float = 0.080
    let footprint: Float = 0.055

    private let fx: SceneFX
    private let look: Look
    private var rng = SplitMix64(seed: 0)
    private let shell = Entity()
    private var shards: [Entity] = []
    private var crack: [ModelEntity] = []
    private var crackFrom: Float = 1
    private let failC: Float
    private var failed = false
    private var yolkBroken = false
    private var yolkBreakC: Float = 1
    private var yolks: [ModelEntity] = []
    private let albumen: ModelEntity
    private var chick: Entity?
    private let hasChick: Bool
    private let surprise: Surprise?
    private var spread: Float = 1

    var shadowSpread: Float { spread }

    static let profile: [SIMD2<Float>] = MeshKit.smoothProfile([
        SIMD2(0.000, 0.000), SIMD2(0.017, 0.004), SIMD2(0.026, 0.010), SIMD2(0.034, 0.020), SIMD2(0.0385, 0.032),
        SIMD2(0.0400, 0.044), SIMD2(0.0395, 0.056), SIMD2(0.0370, 0.068), SIMD2(0.0320, 0.080), SIMD2(0.0255, 0.090),
        SIMD2(0.0180, 0.098), SIMD2(0.0105, 0.104), SIMD2(0.0045, 0.108), SIMD2(0.000, 0.110),
    ], perSpan: 3)

    init(variant: PressVariant, fx: SceneFX) {
        self.fx = fx
        let look = Look(variant)
        self.look = look
        var rng = SplitMix64(seed: variant.seed ^ 0xE66)
        failC = PressObjectFactory.failureThreshold(.egg, variant: variant) ?? 0.24
        hasChick = variant.surprise == .toyChick
        surprise = variant.surprise
        albumen = ModelEntity(mesh: MeshKit.spreadDisc(seed: variant.seed &+ 3, height: 1, segments: 64, wobble: 0.12).resource()
                              ?? .generateSphere(radius: 0.01),
                              materials: [look.golden ? SceneMaterials.goldMess
                                          : SceneMaterials.enamel(.white, roughness: 0.05, clearcoat: 1, clearcoatRoughness: 0.03,
                                                                  opacity: 0.45)])
        albumen.isEnabled = false

        let shellMaterial = look.body(UIColor(hex: 0xEFD3A0), roughness: 0.60, clearcoat: 0.15)
        let membrane = SceneMaterials.pbr(UIColor(hex: 0xFFF9EE), roughness: 0.7)

        // Lying egg: lathe about local Y, rolled −90° about Z (axis → +X), centred on its length.
        shell.orientation = simd_quatf(angle: 4 * .pi / 180, axis: [1, 0, 0]) * simd_quatf(angle: -.pi / 2, axis: [0, 0, 1])
        shell.position = [0, 0.040, 0]
        let axial = Entity()
        axial.position = [0, -0.055, 0]
        shell.addChild(axial)
        let rings = Self.profile.count
        let bands = [0...(rings / 3), (rings / 3)...(2 * rings / 3), (2 * rings / 3)...(rings - 1)]
        let sectors = [4, 4, 4]
        for (b, band) in bands.enumerated() {
            let offset = Float.random(in: 0...(2 * .pi), using: &rng)
            let n = sectors[b]
            var cuts: [Float] = (0..<n).map { k in
                offset + 2 * .pi * Float(k) / Float(n) + Float.random(in: -0.25...0.25, using: &rng)
            }
            cuts.append(cuts[0] + 2 * .pi)
            for k in 0..<n {
                let patch = MeshKit.lathePatch(profile: Self.profile, rings: band, angles: cuts[k]...cuts[k + 1],
                                               angularSteps: 10, thickness: 0.0012)
                let shard = MeshKit.entity(patch.mesh, materials: [shellMaterial, membrane], name: "egg.shard")
                shard.position = patch.centre
                axial.addChild(shard)
                shards.append(shard)
            }
        }
        // Hairline crack along the top (world up = lathe −X after the roll).
        var points: [(SIMD3<Float>, SIMD3<Float>)] = []
        var axialPos: Float = 0.036
        var theta: Float = .pi + Float.random(in: -0.15...0.15, using: &rng)
        for _ in 0..<11 {
            let r = Self.radius(at: axialPos) + 0.0002
            let p = SIMD3<Float>(r * cos(theta), axialPos, r * sin(theta))
            points.append((p, simd_normalize(SIMD3(cos(theta), 0, sin(theta)))))
            axialPos += Float.random(in: 0.0035...0.0055, using: &rng)
            theta += Float.random(in: -0.22...0.22, using: &rng)
        }
        let crackMaterial = SceneMaterials.pbr(UIColor(hex: 0x8A6A3E), roughness: 0.6)
        for i in 0..<(points.count - 1) {
            let (p0, n0) = points[i], (p1, _) = points[i + 1]
            let d = p1 - p0
            let length = simd_length(d)
            let dir = d / max(length, 1e-6)
            let up = simd_normalize(n0 - simd_dot(n0, dir) * dir)
            let side = simd_cross(dir, up)
            let line = MeshKit.model(MeshKit.roundedBox([length + 0.0006, 0.0005, 0.0008], radius: 0.0002, bevel: 0.0001),
                                     material: crackMaterial)
            line.position = (p0 + p1) / 2
            line.orientation = simd_quatf(simd_float3x3(columns: (dir, up, side)))
            line.isEnabled = false
            axial.addChild(line)
            crack.append(line)
        }
        self.rng = rng
        entity.addChild(shell)
        entity.addChild(albumen)
        entity.orientation = Part.yaw(-20)
    }

    static func radius(at y: Float) -> Float {
        for i in 0..<(profile.count - 1) where y <= profile[i + 1].y {
            let a = profile[i], b = profile[i + 1]
            return a.x + (b.x - a.x) * (y - a.y) / max(b.y - a.y, 1e-6)
        }
        return 0
    }

    func surfaceHeight(compression c: Float) -> Float {
        HeightCurve.brittle(c, rest: restHeight, failC: failC, failed: failed, rigidSquash: 0.03,
                            afterRatio: hasChick ? 0.42 : 0.30, minRatio: 0.07)
    }

    func update(_ state: PressVisualState) {
        let c = state.compression
        let h = surfaceHeight(compression: c)
        if !failed {
            let s = h / restHeight
            shell.scale = SIMD3(s, 1, 1 / s.squareRoot())
            // The crack grows toward the failure.
            if crackFrom < 1 {
                let t = clamp((c - crackFrom) / max(failC - crackFrom, 0.01), 0, 1)
                let visible = Int((0.3 + 0.7 * t) * Float(crack.count))
                for (i, line) in crack.enumerated() { line.isEnabled = i < visible }
            }
            return
        }
        let t = clamp((c - failC) / max(1 - failC, 0.05), 0, 1)
        // Albumen spreads to Ø 0.13, 2 mm.
        albumen.scale = SIMD3(0.045 + 0.02 * t, 0.002, (0.045 + 0.02 * t) * 0.9)
        spread = (0.045 + 0.02 * t) / footprint
        for (i, yolk) in yolks.enumerated() {
            let dome: Float = yolkBroken ? 0.006 : 0.011
            let height = min(dome, max(h - 0.001, 0.0015))
            var radius: Float = yolkBroken ? 0.022 + 0.012 * clamp((c - yolkBreakC) / max(1 - yolkBreakC, 0.05), 0, 1) : 0.018
            radius *= min((dome / height).squareRoot(), 1.6)
            yolk.scale = SIMD3(radius, height, radius)
            _ = i
        }
        if let chick {
            let s = min(1, max(h - 0.0005, 0.004) / 0.032)
            let k = min(1 / s.squareRoot(), 1.6)
            chick.scale = SIMD3(k, s, k)
        }
    }

    func fracture(index: Int, isFailure: Bool, state: PressVisualState) {
        switch index {
        case 0:
            crackFrom = state.compression
            for (i, line) in crack.enumerated() { line.isEnabled = i < 3 }
        case 1:
            failed = true
            shell.scale = SIMD3(repeating: 1)
            for line in crack { line.removeFromParent() }
            let centre = shell.convert(position: .zero, to: fx.root)
            for shard in shards {
                let p = shard.position(relativeTo: fx.root)
                var v = Burst.velocity(from: centre, to: p, speed: 0.22, up: 0.28, rng: &rng)
                if p.y < 0.02 { v *= 0.3 }
                fx.debris.adopt(shard, velocity: v * fx.motionScale, spin: Burst.spin(7 * fx.motionScale, rng: &rng),
                                bounciness: 0.2, friction: 0.7)
            }
            albumen.isEnabled = true
            albumen.scale = SIMD3(0.04, 0.002, 0.036)
            if hasChick {
                addChick()
            } else {
                let yolkMaterial: PhysicallyBasedMaterial
                if look.golden {
                    yolkMaterial = SceneMaterials.goldMess
                } else {
                    var m = SceneMaterials.enamel(Palette.yolk, roughness: 0.12, clearcoat: 1, clearcoatRoughness: 0.04)
                    m.emissiveColor = .init(color: UIColor(hex: 0xFFC233))
                    m.emissiveIntensity = 0.15
                    yolkMaterial = m
                }
                let positions: [Float] = !hasDoubleYolk ? [0] : [-0.017, 0.017]
                for x in positions {
                    let yolk = Part.add(cached: "egg.yolk", { MeshKit.sphere(radius: 1, segments: 48, rings: 24) },
                                        yolkMaterial, at: [x, 0, 0], to: entity)
                    yolk.scale = SIMD3(0.018, 0.011, 0.018)
                    yolks.append(yolk)
                }
            }
        default:
            // The yolk breaks and spreads.
            yolkBroken = true
            yolkBreakC = state.compression
            for yolk in yolks {
                let at = yolk.convert(position: [0, 0.5, 0], to: fx.root)
                fx.particles.burst(.droplet, count: 4, at: at, speed: 0.12 * max(fx.motionScale, 0.3),
                                   colors: look.golden ? [Palette.goldMessColor] : [Palette.yolk, UIColor(hex: 0xFFC233)],
                                   size: 0.003...0.005, upBias: 0.2, rng: &rng)
            }
        }
    }

    private var hasDoubleYolk: Bool { surprise == .doubleYolk }

    /// The toy chick: round yellow toy body and head, orange cone beak, no face.
    private func addChick() {
        let chick = Entity()
        let yellow = SceneMaterials.enamel(Palette.duckYellow, roughness: 0.28, clearcoat: 0.8, clearcoatRoughness: 0.1)
        Part.add(cached: "chick.body", { MeshKit.ellipsoid(radii: [0.014, 0.012, 0.013]) }, yellow, at: [0, 0.012, 0], to: chick)
        Part.add(cached: "chick.head", { MeshKit.sphere(radius: 0.0085, segments: 32, rings: 16) }, yellow,
                 at: [0.006, 0.026, 0], to: chick)
        let beak = Part.add(cached: "chick.beak", {
            MeshKit.lathe(profile: [SIMD2(0, 0), SIMD2(0.0032, 0), SIMD2(0.0028, 0.001), SIMD2(0, 0.0055)], segments: 24)
        }, SceneMaterials.enamel(Palette.beakOrange, roughness: 0.3, clearcoat: 0.8, clearcoatRoughness: 0.1),
           at: [0.0135, 0.026, 0], to: chick)
        beak.orientation = simd_quatf(angle: -.pi / 2, axis: [0, 0, 1])
        chick.orientation = Part.yaw(50)
        entity.addChild(chick)
        self.chick = chick
        fx.particles.burst(.confetti, count: 8, at: entity.convert(position: [0, 0.03, 0], to: fx.root), speed: 0.3,
                           colors: [Palette.lemon, Palette.bubblegum, Palette.aqua], size: 0.003...0.005, rng: &rng)
    }
}
