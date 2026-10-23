import Foundation
import RealityKit
import simd
import UIKit

/// Cake Slice (bible §4 #6, VISUAL-TARGET §5.6): a layered 40° wedge (sponge, filling, sponge, cream top, pink
/// back frosting with drips), 14 sprinkles and one striped candle with a flickering flame, apex toward camera-left-front.
/// Contact: the ram meets the flame — it goes out with a puff and the candle starts to lean.
/// Fracture 0 (~0.22): icing cracks, sprinkles hop. Fracture 1 (~0.42): the candle bends and lies flat.
/// Fracture 2 (failure, ~0.62): cream and frosting ooze out of the sides in flat tongues, crumbs and sprinkles burst
/// and stay.
/// Throughout the squash the slice is crushed (`CakeSquash`, FOLD-REVIEW-6 N9 / FOLD-REVIEW-7 #5): it spreads about its
/// own centre, the sides barrel out, the tip blunts, the cream top's outline goes lumpy and the filling squeezes out
/// past it in pink tongues that droop to the plate, so from above it reads as a crushed slice, not an intact wedge.
/// The candle (FOLD-REVIEW-7 N3) is a child of the unscaled root, not of the squashed slice: it keeps its true length
/// and thickness whatever the slice's (k, s, k) scale, and only the ram flattens it (`CakeSquash.candlePose`).
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
    /// Child of `entity` (unscaled), never of `cake` (FOLD-REVIEW-7 N3: a counter-scale under the squashed, rotated
    /// parent stretched the bent candle ~6.7× into a needle past the plate).
    private let candlePivot = Entity()
    private let flame = Entity()
    private var sprinkles: [ModelEntity] = []
    private var cracks: [ModelEntity] = []
    /// Ooze tongues: where they leave the slice's outline (0…1 round it) and their size.
    private var blobs: [(entity: ModelEntity, fraction: Float, size: Float)] = []
    private var jamDisc: ModelEntity?
    private var flameOut = false
    private var candleBent = false
    private var oozeC: Float = 1
    private var oozing = false
    private var spread: Float = 1
    private let hasJam: Bool
    /// The Duo strike plate + 16 pt (fx metres), which the ooze tongues stay inside.
    private let plateHalf = GlassDebris.containment(restHeight: CakeSquash.restHeight, anvilHalf: SIMD2<Float>(repeating: 1))

    static let cakeHeight: Float = CakeSquash.cakeHeight
    static let candleLength: Float = CakeSquash.candleLength
    static let radius: Float = CakeSquash.radius
    /// The layers, back frosting and squeeze-out as one CPU-deformed mesh (FOLD-REVIEW-6 N9: uniformly scaled layers
    /// kept the wedge's outline, so from above a squashed slice looked intact).
    private var body: DeformableMesh?
    /// Which `CakeSquash` layer each of the body's vertices belongs to (the filling squeezes out past the sponge).
    private let vertexLayers = CakeSquash.vertexLayers
    /// The bulge applied so far (latched: the cake never un-squeezes) and the one the mesh was last uploaded at.
    private var bulge: Float = 0
    private var shapedBulge: Float = 0
    private let bulgeNoise: (Float) -> Float
    private var drips: [(model: ModelEntity, rest: SIMD3<Float>)] = []
    private var crumbled = false
    /// Candle base on the top, in wedge space (apex at the origin, arc toward +X).
    static let candleBase = CakeSquash.candleBase

    var shadowSpread: Float { spread }

    init(variant: PressVariant, fx: SceneFX) {
        self.fx = fx
        let look = Look(variant)
        self.look = look
        hasJam = variant.surprise == .jamCentre
        restHeight = CakeSquash.restHeight
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

        // Centroid (0.072 from the apex) at the anvil centre, and the slice spreads about it; apex toward world
        // (−0.8, 0, +0.6).
        cake.position = [-CakeSquash.centroidX, 0, 0]
        entity.addChild(cake)
        entity.addChild(candlePivot)
        applyCandle(CakeSquash.candlePose(ramFace: restHeight, bent: false))
        entity.orientation = simd_quatf(angle: CakeSquash.yaw, axis: [0, 1, 0])
    }

    static func candleProfile() -> [SIMD2<Float>] {
        let r = CakeSquash.candleRadius
        var profile: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(r, 0)]
        let bands = 10
        for k in 0..<bands {
            let y0 = candleLength * Float(k) / Float(bands)
            let y1 = candleLength * Float(k + 1) / Float(bands)
            profile.append(SIMD2(r, y0 + 0.0001))
            profile.append(SIMD2(r, y1))
        }
        profile.append(SIMD2(0.0028, candleLength + 0.0006))
        profile.append(SIMD2(0, candleLength + 0.0008))
        return profile
    }

    func surfaceHeight(compression c: Float) -> Float {
        // The candle tips over first (c 0 → 0.12), then the cake itself squashes to ~12 mm.
        CakeSquash.surfaceHeight(compression: c)
    }

    private func applyCandle(_ pose: CakeCandlePose) {
        candlePivot.position = pose.position
        candlePivot.orientation = pose.orientation
        candlePivot.scale = pose.scale
    }

    func update(_ state: PressVisualState) {
        let h = surfaceHeight(compression: state.compression)
        let s = CakeSquash.heightRatio(ramFace: h, candleBent: candleBent)
        // Part of the spread is the bulge (the outline changes shape), so the uniform growth is capped lower. The slice
        // spreads about its centroid, which stays on the anvil centre.
        let k = CakeSquash.uniformSpread(heightRatio: s)
        cake.scale = SIMD3(k, s, k)
        cake.position = [-CakeSquash.centroidX * k, 0, 0]
        spread = k * (1 + CakeSquash.bulgeReach * CakeSquash.fillingPush / footprint * bulge * 0.5)
        // The squeeze (FOLD-REVIEW-6 N9, FOLD-REVIEW-7 #5): the sides barrel out, the tip blunts, the cream top goes
        // lumpy and the filling squeezes out past it, latched at the deepest squash; re-uploaded only when it has grown.
        bulge = max(bulge, CakeSquash.progress(heightRatio: s))
        if bulge > shapedBulge + 0.01 || (bulge >= 1 && shapedBulge < 1) {
            shapedBulge = bulge
            let amount = bulge, noise = bulgeNoise, layers = vertexLayers
            body?.updateIndexed { i, p in
                CakeSquash.deform(p, layer: i < layers.count ? Int(layers[i]) : nil, progress: amount, noise: noise)
            }
            for drip in drips {
                drip.model.position = CakeSquash.deform(drip.rest, layer: CakeSquash.frostingLayer, progress: amount, noise: noise)
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
        // Candle: lean just enough to stay under the ram face, until it bends flat (unscaled: FOLD-REVIEW-7 N3).
        applyCandle(CakeSquash.candlePose(ramFace: h, bent: candleBent))
        if !flameOut && !state.reduceMotion {
            let flicker = 1 + 0.06 * sin(state.time * 2 * .pi * 7) * sin(state.time * 5.3)
            flame.scale = SIMD3(1, flicker, 1)
        }
        if oozing {
            // Flat tongues of cream and frosting leaving the slice's (squeezed) outline, lengthening as it closes.
            let t = clamp((state.compression - oozeC) / max(1 - oozeC, 0.05), 0, 1)
            let flat = max(0.25, min(1, h / 0.02)) * 0.4
            for blob in blobs {
                let spot = CakeSquash.oozeSpot(fraction: blob.fraction)
                let edge = CakeSquash.deform(SIMD3(spot.point.x, CakeSquash.fillingMidY, spot.point.y),
                                             layer: CakeSquash.fillingLayer, progress: bulge, noise: bulgeNoise)
                let root = CakeSquash.toRoot(edge, spread: k, heightRatio: s)
                let radial = blob.size * 0.5 * (1.3 + 0.7 * t)
                let along = blob.size * 0.5 * (0.85 + 0.35 * t)
                let height = blob.size * 0.5 * flat
                let n = spot.normal
                var centre = SIMD3(root.x + n.x * radial * 0.35, height, root.z + n.y * radial * 0.35)
                if fx.isFoldPress {
                    // On the Duo the tongue stays on the strike plate + 16 pt, like the rest of the mess.
                    var onAnvil = CakeSquash.rootToAnvil(centre)
                    let room = simd_max(plateHalf - SIMD2(repeating: radial), SIMD2(repeating: 0))
                    onAnvil.x = clamp(onAnvil.x, -room.x, room.x)
                    onAnvil.z = clamp(onAnvil.z, -room.y, room.y)
                    centre = CakeSquash.anvilToRoot(onAnvil)
                }
                blob.entity.position = centre
                blob.entity.orientation = simd_quatf(angle: atan2(-n.y, n.x), axis: [0, 1, 0])
                blob.entity.scale = SIMD3(radial, height, along)
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
            // Frosting squirts: 5–7 pink and white ooze tongues out of the sides; crumbs and sprinkles burst and stay.
            oozing = true
            oozeC = state.compression
            let pinkBlob = look.golden ? SceneMaterials.goldMess
                : SceneMaterials.enamel(UIColor(hex: 0xF59BB5), roughness: 0.3, clearcoat: 0.5, clearcoatRoughness: 0.12)
            let whiteBlob = look.golden ? SceneMaterials.goldMess
                : SceneMaterials.enamel(UIColor(hex: 0xFFF3F7), roughness: 0.3, clearcoat: 0.5, clearcoatRoughness: 0.12)
            let count = 5 + Int(rng.next() % 3)
            for k in 0..<count {
                let fraction = (Float(k) + 0.5 + Float.random(in: -0.3...0.3, using: &rng)) / Float(count)
                let size = Float.random(in: 0.012...0.02, using: &rng)
                let blob = Part.add(cached: "cake.blob", { MeshKit.sphere(radius: 1, segments: 24, rings: 12) },
                                    k % 2 == 0 ? pinkBlob : whiteBlob, to: entity)
                blob.scale = SIMD3(repeating: 0.0001)
                blobs.append((blob, fraction, size))
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

/// The candle's transform in the slice's root frame (`CakeSliceView.entity`: unscaled; only yawed by `CakeSquash.yaw`
/// into the anvil). A pure value, so SquishTests can pin its world-space size (FOLD-REVIEW-7 N3).
struct CakeCandlePose: Equatable {
    var position: SIMD3<Float>
    /// Rotation about +Z: 0 is upright; +π/2 lies along −X (toward the apex).
    var angle: Float
    var scale: SIMD3<Float>

    var orientation: simd_quatf { simd_quatf(angle: angle, axis: [0, 0, 1]) }

    /// A candle-local point (the foot at the origin, the wick at +Y `candleLength`) in the root frame: T · R · S.
    func point(_ local: SIMD3<Float>) -> SIMD3<Float> {
        position + orientation.act(local * scale)
    }
}

/// The slice's body and its squeeze (FOLD-REVIEW-6 N9: a uniformly scaled wedge kept its outline, so from above a cake
/// at c 0.7 still looked intact; FOLD-REVIEW-7 #5: with lumps it still read as an intact wedge). Pure, so SquishTests
/// can pin it. Wedge space: apex at the origin, the arc toward +x.
/// As the press closes the slice spreads about its centroid; the sponge barrels out, the tip blunts, the cream top
/// pushes out past the sponge in seeded lumps, and the filling squeezes out furthest, in tongues out of phase with
/// the cream's lumps that droop toward the plate; the base stays put on the plate. `CakeSliceView` uploads it through
/// one `DeformableMesh`, with each vertex's layer from `vertexLayers`.
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
    /// Squeeze layers (the body's parts in build order; not material slots): bottom sponge, filling, top sponge, cream
    /// top, back frosting.
    static let lowerSpongeLayer = 0
    static let fillingLayer = 1
    static let upperSpongeLayer = 2
    static let creamLayer = 3
    static let frostingLayer = 4
    /// The filling's mid-height (wedge space).
    static let fillingMidY: Float = 0.0265

    /// The slice's centroid along its axis (it spreads about this point, which sits on the anvil centre) and its yaw
    /// on the anvil (apex toward world (−0.8, 0, +0.6)).
    static let centroidX: Float = 0.072
    static let yaw: Float = atan2(0.6, 0.8)

    /// The uniform sideways growth is capped here (was 1.4); the bulge does the rest.
    static let maxUniformSpread: Float = 1.3
    /// How far (wedge metres, before the uniform spread) a layer with push 1 is pushed out at full squash.
    static let bulgeReach: Float = 0.016
    /// Pushes per layer (× `bulgeReach`): the sponge barrels (× sin πu), the cream top spreads past it, the filling
    /// squeezes out furthest (FOLD-REVIEW-7 #5: a pink frill round a lumpy white top reads as crushed from above).
    static let spongeBarrel: Float = 0.5
    static let creamPush: Float = 0.75
    static let fillingPush: Float = 1.25
    /// The back frosting's bow where the filling meets it (it lets the filling through rather than ballooning: at
    /// 1.3 the arc's corner left the plate).
    static let frostingFilling: Float = 0.65
    /// How lumpy the squeeze-out is round the slice (share of the push); the filling's tongues are lumpier. With every
    /// lump at its peak the slice still stays on the strike plate + 16 pt (SceneTests).
    static let lumpiness: Float = 0.35
    static let fillingLumpiness: Float = 0.4
    /// Lump phase per wedge metre along the slice (≈ 2.5 rad over a long side).
    static let alongSide: Float = 30
    /// How far the squeezed-out filling sinks toward the plate (share of its height) at its full reach.
    static let fillingDroop: Float = 0.6
    /// The bulge pushes away from this stretch of the wedge's centre line, so the long sides bow sideways rather than
    /// toward the apex. The tip moves `apexMin` (was 0.3) and mostly sideways (`apexSideways`), so it blunts.
    static let axisStart: Float = 0.03
    static let axisEnd: Float = 0.08
    static let apexReach: Float = 0.045
    static let apexMin: Float = 0.55
    static let apexSideways: Float = 0.45

    /// The candle: a striped lathe on the cream top, leaning `candleLean` at rest.
    static let candleLength: Float = 0.038
    static let candleRadius: Float = 0.0035
    static let candleLean: Float = 12 * .pi / 180
    /// Candle base on the top, in wedge space.
    static let candleBase = SIMD2<Float>(0.078, 0.004)
    static var restHeight: Float { cakeHeight + candleLength * cos(candleLean) + 0.008 }

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

    /// The body's parts in build order: sponge, filling, sponge, cream top (rounded prisms on the dense wedge) and the
    /// back frosting (a 7-ring lathe patch, so it can bow too), with each one's material slot and squeeze layer.
    static func bodyParts() -> [(mesh: MeshData, slot: UInt8, layer: UInt8)] {
        var parts: [(mesh: MeshData, slot: UInt8, layer: UInt8)] = []
        var y: Float = 0
        for (index, layer) in layers.enumerated() {
            let slab = MeshKit.roundedPrism(polygon: wedge(inset: layer.inset, sideSteps: sideSteps), height: layer.height,
                                            cornerRadius: 0.003, bevel: min(0.002, layer.height * 0.3), cornerSteps: 3)
            parts.append((slab.translated(SIMD3(0, y, 0)), layer.slot, UInt8(index)))
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
        parts.append((frosting, frostingSlot, UInt8(frostingLayer)))
        return parts
    }

    /// Sponge, filling, sponge, cream top and the back frosting in one mesh (slots as `bodyParts`).
    static func bodyMesh() -> MeshData {
        var mesh = MeshData()
        for part in bodyParts() {
            mesh.append(part.mesh, materialOffset: part.slot)
        }
        return mesh
    }

    /// The squeeze layer of every vertex of `bodyMesh()`, in order (appending never reorders vertices).
    static let vertexLayers: [UInt8] = bodyParts().flatMap { [UInt8](repeating: $0.layer, count: $0.mesh.vertexCount) }

    // MARK: Height and spread (shared by the view and the tests)

    /// Where the ram meets the slice: the candle tips over first (c 0 → 0.12), then the cake squashes to ~12 mm.
    static func surfaceHeight(compression c: Float) -> Float {
        let c = clamp(c, 0, 1)
        let rest = restHeight
        if c < 0.12 {
            return rest + (cakeHeight + 0.007 - rest) * (c / 0.12)
        }
        let t = (c - 0.12) / 0.88
        return (cakeHeight + 0.007) + (0.012 - (cakeHeight + 0.007)) * t
    }

    /// The slice's height ratio under a ram face at `h` (once the candle is bent it lies on top, 7 mm under the ram).
    static func heightRatio(ramFace h: Float, candleBent: Bool) -> Float {
        let top = min(cakeHeight, h - (candleBent ? 0.007 : 0))
        return max(top / cakeHeight, 0.15)
    }

    /// The uniform sideways spread at height ratio `s`.
    static func uniformSpread(heightRatio s: Float) -> Float {
        min(1 / max(s, 0.01).squareRoot(), maxUniformSpread)
    }

    /// A (deformed) wedge-space point in the slice's root frame: spread `k` about the centroid, squashed `s`.
    static func toRoot(_ w: SIMD3<Float>, spread k: Float, heightRatio s: Float) -> SIMD3<Float> {
        SIMD3(k * (w.x - centroidX), s * w.y, k * w.z)
    }

    /// A root-frame point on the anvil (the root's yaw), and back.
    static func rootToAnvil(_ p: SIMD3<Float>) -> SIMD3<Float> {
        simd_quatf(angle: yaw, axis: [0, 1, 0]).act(p)
    }

    static func anvilToRoot(_ p: SIMD3<Float>) -> SIMD3<Float> {
        simd_quatf(angle: -yaw, axis: [0, 1, 0]).act(p)
    }

    /// The candle under a ram face at `h` (FOLD-REVIEW-7 N3). It is parented to the unscaled root, so its length and
    /// girth are its own whatever the slice's (k, s, k): upright, it leans just enough to stay under the ram face;
    /// bent, it lies flat along the top toward the apex, resting on the cream, and only the ram flattens its girth
    /// (to 30 % at most), never its length.
    static func candlePose(ramFace h: Float, bent: Bool) -> CakeCandlePose {
        let s = heightRatio(ramFace: h, candleBent: bent)
        let k = uniformSpread(heightRatio: s)
        let top = s * cakeHeight
        let foot = toRoot(SIMD3(candleBase.x, cakeHeight, candleBase.y), spread: k, heightRatio: s)
        if bent {
            let thickness = clamp((h - top) / (2 * candleRadius), 0.3, 1)
            return CakeCandlePose(position: foot + SIMD3(0, candleRadius * thickness, 0), angle: .pi / 2,
                                  scale: SIMD3(thickness, 1, 1))
        }
        let room = max(h - top, 0.001)
        let lean = acos(clamp(room / (candleLength + 0.01), 0, 1))
        return CakeCandlePose(position: foot, angle: max(candleLean, min(lean, 1.45)), scale: SIMD3(repeating: 1))
    }

    static func candlePose(compression c: Float, bent: Bool) -> CakeCandlePose {
        candlePose(ramFace: surfaceHeight(compression: c), bent: bent)
    }

    // MARK: The squeeze

    /// Squeeze progress (0…1) for the slice's height ratio `s`: none above 0.9, full at 0.3.
    static func progress(heightRatio s: Float) -> Float {
        clamp((0.9 - s) / 0.6, 0, 1)
    }

    /// How much the back frosting (a single band up the whole height) is pushed out at height share `u` (0 base … 1
    /// top): the sponge's barrel plus the filling and the cream top squeezing past it. Zero at the base.
    static func profile(_ u: Float) -> Float {
        let u = clamp(u, 0, 1)
        let barrel = spongeBarrel * sin(.pi * u)
        let filling = frostingFilling * exp(-pow((u - 0.41) / 0.07, 2))
        let cream = creamPush * exp(-pow((u - 0.9) / 0.09, 2))
        return barrel + filling + cream
    }

    /// The layer a point at height share `u` belongs to, for points that don't say (the slabs' stacking).
    static func inferredLayer(_ u: Float) -> Int {
        if u < 0.024 / cakeHeight { return lowerSpongeLayer }
        if u < 0.029 / cakeHeight { return fillingLayer }
        if u < 0.053 / cakeHeight { return upperSpongeLayer }
        return creamLayer
    }

    private static func smooth(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
        let t = clamp((x - e0) / (e1 - e0), 0, 1)
        return t * t * (3 - 2 * t)
    }

    /// Wedge-space point `p` of `layer` (inferred from its height if nil) squeezed by `progress`; `noise` (periodic,
    /// −1…1) makes the lumps. Points only ever move outward and down; the base never moves.
    static func deform(_ p: SIMD3<Float>, layer: Int? = nil, progress: Float, noise: (Float) -> Float) -> SIMD3<Float> {
        let t = clamp(progress, 0, 1)
        guard t > 0 else { return p }
        let axis = SIMD2<Float>(clamp(p.x, axisStart, axisEnd), 0)
        var d = SIMD2<Float>(p.x, p.z) - axis
        // Ahead of the axis the tip spreads mostly sideways, so it blunts instead of growing a longer point.
        if p.x < axisStart { d.x *= apexSideways }
        let r = simd_length(d)
        guard r > 1e-5 else { return p }
        let u = clamp(p.y / cakeHeight, 0, 1)
        // The lumps vary round the slice and along its straight sides (where the push direction is constant).
        let phase = atan2(d.y, d.x) + alongSide * p.x
        let apex = clamp(p.x / apexReach, apexMin, 1)
        var y = p.y
        let push: Float
        switch layer ?? inferredLayer(u) {
        case fillingLayer:
            push = fillingPush * (1 + fillingLumpiness * noise(phase * 1.3 + 2.1))
            // Squeezed out past the sponge, it sags toward the plate the further it has gone.
            y *= 1 - fillingDroop * smooth(0.3, 1.1, push * apex * t / fillingPush)
        case creamLayer:
            push = creamPush * (1 + lumpiness * noise(phase + 1.7 * u))
        case frostingLayer:
            push = profile(u) * (1 + lumpiness * noise(phase + 1.7 * u))
        default:
            push = spongeBarrel * sin(.pi * u) * (1 + lumpiness * noise(phase + 1.7 * u))
        }
        let out = d / r * (bulgeReach * t * push * apex)
        return SIMD3(p.x + out.x, y, p.z + out.y)
    }

    /// A point on the rest outline (wedge space, `fraction` 0…1 of the way round from the apex, counter-clockwise) and
    /// its outward normal: where an ooze tongue leaves the slice.
    static func oozeSpot(fraction: Float) -> (point: SIMD2<Float>, normal: SIMD2<Float>) {
        let outline = wedge()
        var lengths: [Float] = []
        for i in outline.indices {
            lengths.append(simd_distance(outline[i], outline[(i + 1) % outline.count]))
        }
        let total = lengths.reduce(0, +)
        var target = (fraction - fraction.rounded(.down)) * total
        for i in outline.indices {
            let a = outline[i], b = outline[(i + 1) % outline.count]
            if target <= lengths[i] || i == outline.count - 1 {
                let e = b - a
                let length = max(simd_length(e), 1e-6)
                let point = a + e * clamp(target / length, 0, 1)
                // Counter-clockwise in (x, z): the outward normal is the edge turned clockwise.
                return (point, SIMD2(e.y, -e.x) / length)
            }
            target -= lengths[i]
        }
        return (outline[0], SIMD2(-1, 0))
    }
}
