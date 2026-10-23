import Foundation
import RealityKit
import simd
import UIKit

/// Cake Slice (bible §4 #6, VISUAL-TARGET §5.6): a layered 40° wedge (sponge, filling, sponge, cream top, pink
/// back frosting with drips), 14 sprinkles and one striped candle with a flickering flame, apex toward camera-left-front.
/// Contact: the ram meets the flame — it goes out with a puff and the candle starts to lean.
/// Fracture 0 (~0.22): icing cracks, sprinkles hop. Fracture 1 (~0.42): the candle bends and lies flat.
/// Fracture 2 (failure, ~0.62): cream and frosting ooze out as blobs, crumbs and sprinkles burst and stay.
/// Throughout the squash the slice bulges (`CakeSquash`, FOLD-REVIEW-6 N9): the sides barrel out, the filling and the
/// cream top squeeze out past the sponge in lumps, and crumbs fall off it, so it reads as crushed from above too.
/// Surprise `jamCentre`: the filling is glossy jam (otherwise pink cream) and a jam spread appears.
@MainActor
final class CakeSliceView: PressObjectView {
    let entity = Entity()
    let restHeight: Float
    let footprint: Float = 0.052

    private let fx: SceneFX
    private let look: Look
    private var rng = SplitMix64(seed: 0)
    private let cake = Entity()
    private let candlePivot = Entity()
    private let flame = Entity()
    private var sprinkles: [ModelEntity] = []
    private var cracks: [ModelEntity] = []
    private var blobs: [(entity: ModelEntity, direction: SIMD2<Float>, size: Float)] = []
    private var jamDisc: ModelEntity?
    private var flameOut = false
    private var candleBent = false
    private var oozeC: Float = 1
    private var oozing = false
    private var spread: Float = 1
    private let hasJam: Bool

    static let cakeHeight: Float = CakeSquash.cakeHeight
    static let candleLength: Float = 0.038
    static let radius: Float = CakeSquash.radius
    /// The layers, back frosting and squeeze-out as one CPU-deformed mesh (FOLD-REVIEW-6 N9: uniformly scaled layers
    /// kept the wedge's outline, so from above a squashed slice looked intact).
    private var body: DeformableMesh?
    /// The bulge applied so far (latched: the cake never un-squeezes) and the one the mesh was last uploaded at.
    private var bulge: Float = 0
    private var shapedBulge: Float = 0
    private let bulgeNoise: (Float) -> Float
    private var drips: [(model: ModelEntity, rest: SIMD3<Float>)] = []
    private var crumbled = false
    /// Candle base on the top, in wedge space (apex at the origin, arc toward +X).
    static let candleBase = SIMD2<Float>(0.078, 0.004)
    private static let candleLean: Float = 12 * .pi / 180

    var shadowSpread: Float { spread }

    init(variant: PressVariant, fx: SceneFX) {
        self.fx = fx
        let look = Look(variant)
        self.look = look
        hasJam = variant.surprise == .jamCentre
        restHeight = Self.cakeHeight + Self.candleLength * cos(Self.candleLean) + 0.008
        rng = SplitMix64(seed: variant.seed ^ 0xCA4E)
        bulgeNoise = MeshKit.periodicNoise(seed: variant.seed ^ 0xCA4E_B01, octaves: 3)
        build(variant: variant)
    }

    /// The 40° sector outline (apex at the origin), corners rounded by the prism builder.
    static func wedge(inset: Float = 0) -> [SIMD2<Float>] {
        CakeSquash.wedge(inset: inset)
    }

    private func build(variant: PressVariant) {
        let sponge = look.body(UIColor(hex: 0xF4D9A8), roughness: 0.85, clearcoat: 0)
        let filling = look.golden ? SceneMaterials.gold
            : (hasJam ? SceneMaterials.enamel(UIColor(hex: 0xE0335A), roughness: 0.15, clearcoat: 0.8, clearcoatRoughness: 0.08)
               : SceneMaterials.enamel(UIColor(hex: 0xF9B9CB), roughness: 0.3, clearcoat: 0.4, clearcoatRoughness: 0.15))
        let cream = look.body(UIColor(hex: 0xFFF3F7), roughness: 0.35, clearcoat: 0.3)
        let frosting = look.body(UIColor(hex: 0xF59BB5), roughness: 0.35, clearcoat: 0.3)
        // Sponge, filling, sponge, cream top and the back frosting: one deformable mesh (slots `CakeSquash.spongeSlot`…).
        let mesh = MeshCache.mesh("cake.body") { CakeSquash.bodyMesh() }
        let deformable = DeformableMesh(mesh, materials: [sponge, filling, cream, frosting], maxSpread: 1.8)
        cake.addChild(deformable.entity)
        body = deformable
        // Five drips along the back frosting's top edge (they ride the bulge).
        for k in 0..<5 {
            let a = (-16 + Float(k) * 8) * .pi / 180
            let rest = SIMD3<Float>(cos(a) * (Self.radius + 0.002), Self.cakeHeight - 0.006 - Float(k % 2) * 0.003,
                                    sin(a) * (Self.radius + 0.002))
            let drip = Part.add(cached: "cake.drip", { MeshKit.ellipsoid(radii: [0.0035, 0.007, 0.0045], segments: 24, rings: 12) },
                                frosting, at: rest, to: cake)
            drip.orientation = simd_quatf(angle: -a, axis: [0, 1, 0])
            drips.append((drip, rest))
        }
        // Sprinkles on the cream top.
        let colors: [UIColor] = [Palette.raspberry, Palette.lime, Palette.cobalt, Palette.duckYellow, UIColor(hex: 0xF8F8F8)]
        for k in 0..<14 {
            let r = Float.random(in: 0.025...0.098, using: &rng)
            let a = Float.random(in: -0.28...0.28, using: &rng) * min(1, r / 0.05)
            let sprinkle = Part.add(cached: "cake.sprinkle", { MeshKit.capsule(radius: 0.0009, length: 0.007, segments: 12) },
                                    SceneMaterials.enamel(colors[k % colors.count], roughness: 0.25, clearcoat: 0.8,
                                                          clearcoatRoughness: 0.1),
                                    at: [cos(a) * r, Self.cakeHeight + 0.0009, sin(a) * r], to: cake)
            sprinkle.orientation = simd_quatf(angle: Float.random(in: 0...(2 * .pi), using: &rng), axis: [0, 1, 0])
                * simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
            sprinkle.position.x += 0.0035
            sprinkles.append(sprinkle)
        }
        // Candle: pink/white striped lathe, dark wick, unlit teardrop flame.
        let pink = SceneMaterials.enamel(Palette.bubblegum, roughness: 0.4, clearcoat: 0.5, clearcoatRoughness: 0.15)
        let white = SceneMaterials.enamel(UIColor(hex: 0xF8F8F8), roughness: 0.4, clearcoat: 0.5, clearcoatRoughness: 0.15)
        let candle = MeshKit.entity(MeshKit.lathe(profile: Self.candleProfile(), segments: 24, material: { i in UInt8((i / 2) % 2) }),
                                    materials: [pink, white], name: "candle")
        candlePivot.addChild(candle)
        Part.add(cached: "cake.wick", { MeshKit.capsule(radius: 0.0006, length: 0.004, segments: 8) },
                 SceneMaterials.pbr(Palette.enamelGraphite, roughness: 0.6), at: [0, Self.candleLength, 0], to: candlePivot)
        let flameModel = ModelEntity(mesh: MeshCache.resource("cake.flame") { MeshKit.ellipsoid(radii: [0.004, 0.008, 0.004], segments: 16, rings: 10) }
                                     ?? .generateSphere(radius: 0.004),
                                     materials: [UnlitMaterial(color: UIColor(hex: 0xFFC94A), applyPostProcessToneMap: false)])
        flameModel.position = [0, 0.007, 0]
        flame.addChild(flameModel)
        flame.position = [0, Self.candleLength + 0.002, 0]
        candlePivot.addChild(flame)
        candlePivot.position = [Self.candleBase.x, Self.cakeHeight, Self.candleBase.y]
        candlePivot.orientation = simd_quatf(angle: Self.candleLean, axis: [0, 0, 1])
        cake.addChild(candlePivot)

        // Centroid (0.072 from the apex) at the anvil centre; apex toward world (−0.8, 0, +0.6).
        cake.position = [-0.072, 0, 0]
        entity.addChild(cake)
        entity.orientation = simd_quatf(angle: atan2(0.6, 0.8), axis: [0, 1, 0])
    }

    static func candleProfile() -> [SIMD2<Float>] {
        var profile: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(0.0035, 0)]
        let bands = 10
        for k in 0..<bands {
            let y0 = candleLength * Float(k) / Float(bands)
            let y1 = candleLength * Float(k + 1) / Float(bands)
            profile.append(SIMD2(0.0035, y0 + 0.0001))
            profile.append(SIMD2(0.0035, y1))
        }
        profile.append(SIMD2(0.0028, candleLength + 0.0006))
        profile.append(SIMD2(0, candleLength + 0.0008))
        return profile
    }

    func surfaceHeight(compression c: Float) -> Float {
        // The candle tips over first (c 0 → 0.12), then the cake itself squashes to ~12 mm.
        let c = clamp(c, 0, 1)
        if c < 0.12 {
            return restHeight + (Self.cakeHeight + 0.007 - restHeight) * (c / 0.12)
        }
        let t = (c - 0.12) / 0.88
        return (Self.cakeHeight + 0.007) + (0.012 - (Self.cakeHeight + 0.007)) * t
    }

    func update(_ state: PressVisualState) {
        let h = surfaceHeight(compression: state.compression)
        let cakeTop = min(Self.cakeHeight, h - (candleBent ? 0.007 : 0))
        let s = max(cakeTop / Self.cakeHeight, 0.15)
        // Part of the spread is now the bulge (the outline changes shape), so the uniform growth is capped lower.
        let k = min(1 / s.squareRoot(), CakeSquash.maxUniformSpread)
        cake.scale = SIMD3(k, s, k)
        spread = k * (1 + CakeSquash.bulgeReach / footprint * bulge * 0.5)
        // The squeeze (FOLD-REVIEW-6 N9): the sides barrel out, the filling and the cream top squeeze out past the
        // sponge in lumps, latched at the deepest squash; re-uploaded only when it has grown.
        bulge = max(bulge, CakeSquash.progress(heightRatio: s))
        if bulge > shapedBulge + 0.01 || (bulge >= 1 && shapedBulge < 1) {
            shapedBulge = bulge
            let amount = bulge, noise = bulgeNoise
            body?.update { CakeSquash.deform($0, progress: amount, noise: noise) }
            for drip in drips {
                drip.model.position = CakeSquash.deform(drip.rest, progress: amount, noise: noise)
            }
        }
        if bulge > 0.55 && !crumbled {
            // Crumbs fall off the bulging sponge (they persist on the plate).
            crumbled = true
            let crumbColors = look.golden ? [Palette.gold, Palette.goldMessColor] : [UIColor(hex: 0xE9C48A), UIColor(hex: 0xF4D9A8)]
            fx.particles.burst(.crumb, count: 8, at: entity.convert(position: [0, 0.01, 0], to: fx.root),
                               speed: 0.18 * max(fx.motionScale, 0.3), colors: crumbColors, size: 0.002...0.0035,
                               spread: 0.05, upBias: 0.25, rng: &rng)
        }
        // Candle: lean just enough to stay under the ram face, until it bends flat.
        if candleBent {
            candlePivot.orientation = simd_quatf(angle: 1.45, axis: [0, 0, 1])
            let thickness = max(min(1, (h - cakeTop) / 0.007), 0.3)
            // Lying along the slice toward the apex (≤ 0.04 m, stays on the cake: VISUAL-REVIEW-1 fix 15);
            // rotated ~83° about Z, its local X is now nearly vertical, so flatten along X.
            candlePivot.scale = SIMD3(1 / k, 1 / s, 1 / k) * SIMD3(thickness, 1, 1)
        } else {
            let room = max(h - cakeTop, 0.001)
            let lean = acos(clamp(room / (Self.candleLength + 0.01), 0, 1))
            candlePivot.orientation = simd_quatf(angle: max(Self.candleLean, min(lean, 1.45)), axis: [0, 0, 1])
            candlePivot.scale = SIMD3(1 / k, 1 / s, 1 / k)
        }
        if !flameOut && !state.reduceMotion {
            let flicker = 1 + 0.06 * sin(state.time * 2 * .pi * 7) * sin(state.time * 5.3)
            flame.scale = SIMD3(1, flicker, 1)
        }
        if oozing {
            let t = clamp((state.compression - oozeC) / max(1 - oozeC, 0.05), 0, 1)
            for blob in blobs {
                let d = 0.04 + 0.03 * t
                let flat = max(0.25, min(1, h / 0.02)) * 0.45
                blob.entity.position = SIMD3(blob.direction.x * d, blob.size * 0.5 * flat, blob.direction.y * d)
                blob.entity.scale = SIMD3(1 + t, flat, 1 + t) * (blob.size * 0.5)
            }
            if let jamDisc {
                jamDisc.scale = SIMD3(0.04 + 0.025 * t, 0.0015, 0.035 + 0.02 * t)
            }
            spread = max(spread, (0.06 + 0.03 * t) / footprint)
        }
    }

    func fracture(index: Int, isFailure: Bool, state: PressVisualState) {
        let m = max(fx.motionScale, 0.3)
        switch index {
        case 0:
            // Icing cracks and a sprinkle hop.
            let lineMaterial = SceneMaterials.pbr(UIColor(hex: 0xE8C9D2), roughness: 0.5)
            for k in 0..<4 {
                let r = 0.035 + Float(k) * 0.016
                let line = Part.add(MeshKit.roundedBox([0.0008, 0.0006, 0.012 + Float(k) * 0.003], radius: 0.0002, bevel: 0.0001),
                                    lineMaterial, at: [r, Self.cakeHeight + 0.0002, Float.random(in: -0.01...0.01, using: &rng)],
                                    to: cake)
                line.orientation = simd_quatf(angle: Float.random(in: -0.5...0.5, using: &rng), axis: [0, 1, 0])
                cracks.append(line)
            }
            for sprinkle in sprinkles.prefix(4) where sprinkle.parent === cake {
                fx.debris.adopt(sprinkle, velocity: SIMD3(Float.random(in: -0.1...0.1, using: &rng), 0.3, 0.08) * m,
                                spin: Burst.spin(10 * m, rng: &rng), bounciness: 0.3)
            }
        case 1:
            candleBent = true
            if !flameOut { snuff() }
        default:
            // Frosting squirts: 5–7 pink and white ooze blobs at the sides; crumbs and sprinkles burst and stay.
            oozing = true
            oozeC = state.compression
            let pinkBlob = look.golden ? SceneMaterials.goldMess
                : SceneMaterials.enamel(UIColor(hex: 0xF59BB5), roughness: 0.3, clearcoat: 0.5, clearcoatRoughness: 0.12)
            let whiteBlob = look.golden ? SceneMaterials.goldMess
                : SceneMaterials.enamel(UIColor(hex: 0xFFF3F7), roughness: 0.3, clearcoat: 0.5, clearcoatRoughness: 0.12)
            let count = 5 + Int(rng.next() % 3)
            for k in 0..<count {
                let a = Float(k) / Float(count) * 2 * .pi + Float.random(in: -0.3...0.3, using: &rng)
                let size = Float.random(in: 0.012...0.02, using: &rng)
                let blob = Part.add(cached: "cake.blob", { MeshKit.sphere(radius: 1, segments: 24, rings: 12) },
                                    k % 2 == 0 ? pinkBlob : whiteBlob, to: entity)
                blob.scale = SIMD3(repeating: size * 0.5)
                blobs.append((blob, SIMD2(cos(a), sin(a)), size))
            }
            if hasJam {
                let disc = ModelEntity(mesh: MeshCache.resource("cake.jam") {
                    MeshKit.spreadDisc(seed: 0x7A4, height: 1, segments: 48, wobble: 0.16)
                } ?? .generateSphere(radius: 0.01),
                    materials: [look.golden ? SceneMaterials.goldMess
                                : SceneMaterials.enamel(UIColor(hex: 0xE0335A), roughness: 0.12, clearcoat: 0.9, clearcoatRoughness: 0.06)])
                disc.position = [0.004, 0.0002, 0.004]
                disc.scale = SIMD3(0.04, 0.0015, 0.035)
                entity.addChild(disc)
                jamDisc = disc
            }
            for sprinkle in sprinkles where sprinkle.parent === cake {
                fx.debris.adopt(sprinkle, velocity: Burst.velocity(from: .zero, to: sprinkle.position(relativeTo: fx.root),
                                                                   speed: 0.25, up: 0.35, rng: &rng) * m,
                                spin: Burst.spin(12 * m, rng: &rng), bounciness: 0.25)
            }
            let crumbColors = look.golden ? [Palette.gold, Palette.goldMessColor] : [UIColor(hex: 0xE9C48A), UIColor(hex: 0xF4D9A8)]
            fx.particles.burst(.crumb, count: 16, at: [0, 0.012, 0], speed: 0.3 * m, colors: crumbColors,
                               size: 0.002...0.004, spread: 0.045, upBias: 0.3, rng: &rng)
        }
    }

    func handle(_ event: PressEvent, state: PressVisualState) {
        if event == .contact && !flameOut { snuff() }
    }

    /// The flame goes out with a little smoke puff.
    private func snuff() {
        flameOut = true
        let at = flame.convert(position: [0, 0.006, 0], to: fx.root)
        flame.isEnabled = false
        fx.particles.burst(.dust, count: 4, at: at, speed: 0.03, colors: [UIColor(hex: 0xFFFFFF)],
                           size: 0.004...0.007, spread: 0.002, upBias: 0.8, life: 0.7, rng: &rng)
    }
}

/// The slice's body and its squeeze (FOLD-REVIEW-6 N9: a uniformly scaled wedge kept its outline, so from above a cake
/// at c 0.7 still looked intact). Pure, so SquishTests can pin it. Wedge space: apex at the origin, the arc toward +x.
/// As the press closes the sides barrel out, the filling and the cream top squeeze out past the sponge in seeded lumps,
/// and the base stays put on the plate; `CakeSliceView` uploads it through one `DeformableMesh`.
enum CakeSquash {
    static let cakeHeight: Float = 0.065
    static let radius: Float = 0.110
    static let halfAngle: Float = 20 * .pi / 180
    /// Extra outline points on each straight side, so the sides can bow (a prism's straight edge has none).
    static let sideSteps = 5
    /// Material slots of `bodyMesh()`: sponge, filling, cream top, back frosting.
    static let spongeSlot: UInt8 = 0
    static let fillingSlot: UInt8 = 1
    static let creamSlot: UInt8 = 2
    static let frostingSlot: UInt8 = 3
    /// (height, inset, slot) bottom → top: sponge, filling, sponge, cream.
    static let layers: [(height: Float, inset: Float, slot: UInt8)] = [
        (0.024, 0, spongeSlot), (0.005, 0.0015, fillingSlot), (0.024, 0, spongeSlot), (0.012, 0, creamSlot),
    ]
    /// The uniform sideways growth is capped here (was 1.4); the bulge does the rest.
    static let maxUniformSpread: Float = 1.3
    /// How far (wedge metres, before the uniform spread) the most squeezed layer gets pushed out at full squash.
    static let bulgeReach: Float = 0.014
    /// How lumpy the squeeze-out is round the slice (share of the reach).
    static let lumpiness: Float = 0.35
    /// The bulge pushes away from this stretch of the wedge's centre line, so the long sides bow sideways rather than
    /// toward the apex; the thin apex itself only moves 30 %.
    static let axisStart: Float = 0.03
    static let axisEnd: Float = 0.08
    static let apexReach: Float = 0.045

    /// The 40° sector outline (apex at the origin, counter-clockwise from the apex), with `sideSteps` extra points on
    /// each straight side.
    static func wedge(inset: Float = 0, sideSteps: Int = 0) -> [SIMD2<Float>] {
        let apex = SIMD2<Float>(inset * 2.5, 0)
        let r = radius - inset
        let start = SIMD2<Float>(cos(-halfAngle), sin(-halfAngle)) * r
        let end = SIMD2<Float>(cos(halfAngle), sin(halfAngle)) * r
        let steps = max(sideSteps, 0)
        var points: [SIMD2<Float>] = [apex]
        for k in 0..<steps {
            points.append(apex + (start - apex) * (Float(k + 1) / Float(steps + 1)))
        }
        for k in 0...8 {
            let a = -halfAngle + 2 * halfAngle * Float(k) / 8
            points.append(SIMD2(cos(a), sin(a)) * r)
        }
        for k in stride(from: steps, to: 0, by: -1) {
            points.append(apex + (end - apex) * (Float(k) / Float(steps + 1)))
        }
        return points
    }

    /// Sponge, filling, sponge, cream top (rounded prisms on the dense wedge) and the back frosting (a 7-ring lathe
    /// patch, so it can bow too), in one mesh.
    static func bodyMesh() -> MeshData {
        var mesh = MeshData()
        var y: Float = 0
        for layer in layers {
            let slab = MeshKit.roundedPrism(polygon: wedge(inset: layer.inset, sideSteps: sideSteps), height: layer.height,
                                            cornerRadius: 0.003, bevel: min(0.002, layer.height * 0.3), cornerSteps: 3)
            mesh.append(slab.translated(SIMD3(0, y, 0)), materialOffset: layer.slot)
            y += layer.height
        }
        let rings = 6
        let profile: [SIMD2<Float>] = (0...rings).map { k in
            SIMD2(radius + 0.004, 0.0008 + (cakeHeight - 0.0013) * Float(k) / Float(rings))
        }
        let back = MeshKit.lathePatch(profile: profile, rings: 0...rings, angles: (-halfAngle + 0.01)...(halfAngle - 0.01),
                                      angularSteps: 16, thickness: 0.0055)
        var frosting = back.mesh.translated(back.centre)
        frosting.triangleMaterials = []
        mesh.append(frosting, materialOffset: frostingSlot)
        return mesh
    }

    /// Squeeze progress (0…1) for the slice's height ratio `s`: none above 0.9, full at 0.3.
    static func progress(heightRatio s: Float) -> Float {
        clamp((0.9 - s) / 0.6, 0, 1)
    }

    /// How much a point at height share `u` (0 base … 1 top) is pushed out: a barrel, plus the filling and the cream
    /// top squeezing out past the sponge. Zero at the base (it sits on the plate).
    static func profile(_ u: Float) -> Float {
        let u = clamp(u, 0, 1)
        let barrel = 0.35 * sin(.pi * u)
        let filling = 0.8 * exp(-pow((u - 0.41) / 0.07, 2))
        let cream = 0.6 * exp(-pow((u - 0.9) / 0.09, 2))
        return barrel + filling + cream
    }

    /// Wedge-space point `p` squeezed by `progress`; `noise` (periodic, −1…1) makes the lumps.
    static func deform(_ p: SIMD3<Float>, progress: Float, noise: (Float) -> Float) -> SIMD3<Float> {
        let t = clamp(progress, 0, 1)
        guard t > 0 else { return p }
        let axis = SIMD2<Float>(clamp(p.x, axisStart, axisEnd), 0)
        let d = SIMD2<Float>(p.x, p.z) - axis
        let r = simd_length(d)
        guard r > 1e-5 else { return p }
        let u = clamp(p.y / cakeHeight, 0, 1)
        let lump = 1 + lumpiness * noise(atan2(d.y, d.x) + 1.7 * u)
        let apex = clamp(p.x / apexReach, 0.3, 1)
        let out = d / r * (bulgeReach * t * profile(u) * lump * apex)
        return SIMD3(p.x + out.x, p.y, p.z + out.y)
    }
}
