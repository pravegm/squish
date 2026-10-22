import Foundation
import RealityKit
import simd
import UIKit

/// Cake Slice (bible §4 #6, VISUAL-TARGET §5.6): a layered 40° wedge (sponge, filling, sponge, cream top, pink
/// back frosting with drips), 14 sprinkles and one striped candle with a flickering flame, apex toward camera-left-front.
/// Contact: the ram meets the flame — it goes out with a puff and the candle starts to lean.
/// Fracture 0 (~0.22): icing cracks, sprinkles hop. Fracture 1 (~0.42): the candle bends and lies flat.
/// Fracture 2 (failure, ~0.62): cream and frosting ooze out as blobs, crumbs and sprinkles burst and stay.
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

    static let cakeHeight: Float = 0.065
    static let candleLength: Float = 0.038
    static let radius: Float = 0.110
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
        build(variant: variant)
    }

    /// The 40° sector outline (apex at the origin), corners rounded by the prism builder.
    static func wedge(inset: Float = 0) -> [SIMD2<Float>] {
        var points: [SIMD2<Float>] = [SIMD2(inset * 2.5, 0)]
        let half: Float = 20 * .pi / 180
        for k in 0...8 {
            let a = -half + 2 * half * Float(k) / 8
            points.append(SIMD2(cos(a), sin(a)) * (radius - inset))
        }
        return points
    }

    private func build(variant: PressVariant) {
        let sponge = look.body(UIColor(hex: 0xF4D9A8), roughness: 0.85, clearcoat: 0)
        let filling = look.golden ? SceneMaterials.gold
            : (hasJam ? SceneMaterials.enamel(UIColor(hex: 0xE0335A), roughness: 0.15, clearcoat: 0.8, clearcoatRoughness: 0.08)
               : SceneMaterials.enamel(UIColor(hex: 0xF9B9CB), roughness: 0.3, clearcoat: 0.4, clearcoatRoughness: 0.15))
        let cream = look.body(UIColor(hex: 0xFFF3F7), roughness: 0.35, clearcoat: 0.3)
        let frosting = look.body(UIColor(hex: 0xF59BB5), roughness: 0.35, clearcoat: 0.3)
        var y: Float = 0
        let layers: [(Float, PhysicallyBasedMaterial, Float)] = [(0.024, sponge, 0), (0.005, filling, 0.0015),
                                                                 (0.024, sponge, 0), (0.012, cream, 0)]
        for (i, layer) in layers.enumerated() {
            Part.add(cached: "cake.layer.\(i)", {
                MeshKit.roundedPrism(polygon: Self.wedge(inset: layer.2), height: layer.0, cornerRadius: 0.003,
                                     bevel: min(0.002, layer.0 * 0.3))
            }, layer.1, at: [0, y, 0], to: cake)
            y += layer.0
        }
        // Back frosting on the arc face, full height, with five drips along the top edge.
        let half: Float = 20 * .pi / 180
        let back = MeshKit.lathePatch(profile: [SIMD2(Self.radius + 0.004, 0.0008), SIMD2(Self.radius + 0.004, Self.cakeHeight - 0.0005)],
                                      rings: 0...1, angles: (-half + 0.01)...(half - 0.01), angularSteps: 16, thickness: 0.0055)
        let backEntity = MeshKit.entity(back.mesh, materials: [frosting, frosting], name: "cake.back")
        backEntity.position = back.centre
        cake.addChild(backEntity)
        for k in 0..<5 {
            let a = (-16 + Float(k) * 8) * .pi / 180
            let drip = Part.add(cached: "cake.drip", { MeshKit.ellipsoid(radii: [0.0035, 0.007, 0.0045], segments: 24, rings: 12) },
                                frosting, at: [cos(a) * (Self.radius + 0.002), Self.cakeHeight - 0.006 - Float(k % 2) * 0.003,
                                                sin(a) * (Self.radius + 0.002)], to: cake)
            drip.orientation = simd_quatf(angle: -a, axis: [0, 1, 0])
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
        candlePivot.orientation = simd_quatf(angle: Self.candleLean, axis: [1, 0, 0])
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
        let k = min(1 / s.squareRoot(), 1.4)
        cake.scale = SIMD3(k, s, k)
        spread = k
        // Candle: lean just enough to stay under the ram face, until it bends flat.
        if candleBent {
            candlePivot.orientation = simd_quatf(angle: 1.45, axis: [1, 0, 0])
            let thickness = max(min(1, (h - cakeTop) / 0.007), 0.3)
            // Lying (rotated ~83° about X): its local Z is now nearly vertical, so flatten along Z.
            candlePivot.scale = SIMD3(1 / k, 1 / s, 1 / k) * SIMD3(1, 1, thickness)
        } else {
            let room = max(h - cakeTop, 0.001)
            let lean = acos(clamp(room / (Self.candleLength + 0.01), 0, 1))
            candlePivot.orientation = simd_quatf(angle: max(Self.candleLean, min(lean, 1.45)), axis: [1, 0, 0])
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
            fx.particles.burst(.crumb, count: 10, at: [0, 0.012, 0], speed: 0.3 * m, colors: crumbColors,
                               size: 0.002...0.004, spread: 0.03, upBias: 0.3, rng: &rng)
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
