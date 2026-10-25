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
/// FOLD-REVIEW-8 N4 (it still read as an intact, blown-out white wedge at c = 1): the whole outline is also drawn toward
/// a lumpy oval about the centroid (`CakeSquash.blobOffset`: the point goes, the corners round, the sides swell), and the
/// cream is a darker, matte, mottled cream (`CakeSquash.creamTint`, `creamImage`) so the squash shades.
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
    /// The cream's mottle once it has loaded, and the albedo shade its material was last built at (−1: not yet).
    private var creamMottle: TextureResource?
    private var appliedCreamShade: Float = -1
    /// The 3D-art round's maps: the crumb, its smeared crushed version, the cream's strokes.
    private var spongeMaps: SurfaceMaps?
    private var smearedSponge: TextureResource?
    private var spongeSmearShown = false
    private var creamNormal: TextureResource?
    /// Crumbs left lying on the crushed cream top (they ride the squeeze).
    private var topCrumbs: [(model: ModelEntity, rest: SIMD3<Float>)] = []
    /// Candle base on the top, in wedge space (apex at the origin, arc toward +X).
    static let candleBase = CakeSquash.candleBase
    /// The storyboard (OBJECT-STORYBOARDS §6): a soft breath, sprinkle hops, cream cracks, crumbs, and the filling
    /// squeezed out of the pinch line long before the frosting goes.
    private let life: ObjectLife
    private var story: StoryCursor
    private let ooze: OozeRing
    private var lastSpread: Float = 1
    /// The fight's marks (crumbs and a cream crack once it strains hard) and the give's shove, each once.
    private var fought = false
    private var gave = false

    var shadowSpread: Float { spread }

    init(variant: PressVariant, fx: SceneFX) {
        self.fx = fx
        let look = Look(variant)
        self.look = look
        hasJam = variant.surprise == .jamCentre
        restHeight = CakeSquash.restHeight
        rng = SplitMix64(seed: variant.seed ^ 0xCA4E)
        bulgeNoise = MeshKit.periodicNoise(seed: variant.seed ^ 0xCA4E_B01, octaves: 3)
        life = ObjectLife(seed: variant.seed, idle: .breathe, amount: 0.008, rate: 0.3, pulseHz: 4, pulseDamping: 0.4)
        story = StoryCursor(.cakeSlice, seed: variant.seed)
        let filling = look.golden ? SceneMaterials.goldMess
            : (variant.surprise == .jamCentre
               ? SceneMaterials.enamel(UIColor(hex: 0xE0335A), roughness: 0.15, clearcoat: 0.8, clearcoatRoughness: 0.08)
               : SceneMaterials.enamel(UIColor(hex: 0xF9B9CB), roughness: 0.3, clearcoat: 0.4, clearcoatRoughness: 0.15))
        let plate = GlassDebris.containment(restHeight: CakeSquash.restHeight, anvilHalf: SIMD2<Float>(repeating: 1), padding: 0)
        ooze = OozeRing(seed: variant.seed ^ 0xCA4F, count: 6, centre: SIMD2(-0.012, 0), radii: SIMD2(0.058, 0.032),
                        reach: 0.010...0.022, width: 0.010...0.018, thickness: 0.003, maxRadius: min(plate.x, plate.y) * 0.9,
                        material: filling)
        build(variant: variant)
        life.adopt(childrenOf: entity)
        entity.addChild(ooze.root)
    }

    /// One more hairline in the cream (a storyboard `.crease`).
    private func addCreamCrack() {
        let lineMaterial = SceneMaterials.pbr(UIColor(hex: 0xE8C9D2), roughness: 0.5)
        let r = Float.random(in: 0.03...0.095, using: &rng)
        let a = Float.random(in: -0.22...0.22, using: &rng) * min(1, r / 0.05)
        let line = Part.add(MeshKit.roundedBox([0.0008, 0.0006, 0.010 + Float.random(in: 0...0.008, using: &rng)], radius: 0.0002,
                                               bevel: 0.0001),
                            lineMaterial, at: [cos(a) * r, Self.cakeHeight + 0.0002, sin(a) * r], to: cake)
        line.orientation = simd_quatf(angle: Float.random(in: -0.6...0.6, using: &rng), axis: [0, 1, 0])
        cracks.append(line)
    }

    /// A few crumbs trickle off the sponge's side (they stay on the plate).
    private func trickle(_ count: Int) {
        let crumbColors = look.golden ? [Palette.gold, Palette.goldMessColor] : [UIColor(hex: 0xE9C48A), UIColor(hex: 0xF4D9A8)]
        let a = Float.random(in: -0.35...0.35, using: &rng)
        let side: Float = rng.next() % 2 == 0 ? 1 : -1
        let at = entity.convert(position: [-0.01 + cos(a) * 0.03, 0.02, side * 0.03], to: fx.root)
        fx.particles.burst(.crumb, count: count, at: at, speed: 0.08 * max(fx.motionScale, 0.3), colors: crumbColors,
                           size: 0.0018...0.003, spread: 0.01, upBias: 0.3, rng: &rng)
    }

    /// One storyboard beat (OBJECT-STORYBOARDS §6).
    private func onBeat(_ beat: StoryBeat, state: PressVisualState) {
        switch beat.kind {
        case .kiss:
            life.kick(0.5)
            BeatFX.glint(fx, at: [0.0, Self.cakeHeight + 0.002, 0.004], in: entity, count: 2, golden: look.golden, rng: &rng)
        case .bulge:
            let m = max(fx.motionScale, 0.3)
            if let sprinkle = sprinkles.first(where: { $0.parent === cake }) {
                fx.debris.adopt(sprinkle, velocity: SIMD3(Float.random(in: -0.08...0.08, using: &rng), 0.22, 0.06) * m,
                                spin: Burst.spin(8 * m, rng: &rng), bounciness: 0.3)
            }
            life.kick(0.6)
        case .crease:
            addCreamCrack()
            life.kick(0.3)
        case .chip:
            trickle(3)
        case .ooze:
            if let tip = ooze.emit(at: state.compression), beat.ordinal % 2 == 1 {
                let d = simd_length(SIMD2(tip.x, tip.z)) > 1e-5 ? simd_normalize(SIMD2(tip.x + 0.012, tip.z)) : SIMD2<Float>(1, 0)
                let colors = look.golden ? [Palette.goldMessColor] : [hasJam ? UIColor(hex: 0xE0335A) : UIColor(hex: 0xF9B9CB)]
                BeatFX.fling(fx, at: tip, in: entity, direction: d, count: 1, colors: colors, speed: 0.1, rng: &rng)
            }
            life.kick(0.4)
        case .tell:
            life.tremor(0.3, level: 0.7)
            trickle(2)
        case .settle:
            BeatFX.glint(fx, at: [0.0, 0.01, 0.0], in: entity, count: 2, golden: look.golden, rng: &rng)
        default:
            life.kick(0.3)
        }
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
        // FOLD-REVIEW-8 N4: a darker, matte cream (was #FFF3F7 + 0.3 clearcoat, which clipped to flat white), mottled
        // once its texture arrives, so the squash shades.
        let cream = look.body(UIColor(hex: CakeSquash.creamTint), roughness: CakeSquash.creamRoughness, clearcoat: 0)
        let frosting = look.body(UIColor(hex: 0xF59BB5), roughness: 0.35, clearcoat: 0.3)
        // Sponge, filling, sponge, cream top and the back frosting: one deformable mesh (slots `CakeSquash.spongeSlot`…).
        let mesh = MeshCache.mesh("cake.body") { CakeSquash.bodyMesh() }
        let deformable = DeformableMesh(mesh, materials: [sponge, filling, cream, frosting], maxSpread: 1.8)
        cake.addChild(deformable.entity)
        body = deformable
        if !look.golden {
            Task { @MainActor [weak self] in
                guard let texture = await Self.creamTexture(), let self else { return }
                self.creamMottle = texture
                self.applyCreamShade()
            }
        }
        if !look.golden { loadSurface() }
        // A row of piped rosettes along the back of the cream top (they ride the squeeze like the drips).
        let piped = look.body(UIColor(hex: 0xF59BB5), roughness: 0.4, clearcoat: 0.25)
        for k in 0..<9 {
            let a = (-17 + Float(k) * 4.25) * .pi / 180
            let r = Self.radius - 0.0065
            let rest = SIMD3<Float>(cos(a) * r, Self.cakeHeight - 0.0004, sin(a) * r)
            let rosette = Part.add(cached: "cake.rosette", { CakeSquash.rosetteMesh() }, piped, at: rest, to: cake)
            rosette.orientation = Part.yaw(Float(k) * 37)
            drips.append((rosette, rest))
        }
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
        // Sprinkles on the cream top (24, seven colours).
        let colors: [UIColor] = [Palette.raspberry, Palette.lime, Palette.cobalt, Palette.duckYellow, UIColor(hex: 0xF8F8F8),
                                 Palette.tangerine, Palette.grape]
        for k in 0..<24 {
            let r = Float.random(in: 0.025...0.092, using: &rng)
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

    /// The cream top's textured material, its albedo stepped down as the squash completes (FOLD-REVIEW-9 N3). Only
    /// rebuilt when the shade has moved, which happens only while the bulge grows. Its spatula strokes (normal) once
    /// they land.
    private func applyCreamShade(force: Bool = false) {
        guard !look.golden, let texture = creamMottle else { return }
        let shade = CakeSquash.creamShade(progress: bulge)
        guard force || abs(shade - appliedCreamShade) > 0.004 else { return }
        appliedCreamShade = shade
        var material = SceneMaterials.textured(texture, roughness: CakeSquash.creamRoughness)
        material.baseColor = .init(tint: UIColor(white: CGFloat(shade), alpha: 1), texture: .init(texture))
        if let strokes = creamNormal { material.normal = .init(texture: SurfaceDetail.clamped(strokes)) }
        body?.setMaterial(material, forSlot: Int(CakeSquash.creamSlot))
    }

    /// The sponge's crumb (colour and pores, tiled on the box-projected sides), the frosting's piping and the cream's
    /// strokes, drawn off the main actor; the smeared crumb is fetched now so the crush swap is instant.
    private func loadSurface() {
        let filling: UInt32 = hasJam ? 0xE0335A : 0xF9B9CB
        Task { @MainActor [weak self] in
            async let piping = SurfaceDetail.pipedFrosting()
            async let strokes = SurfaceDetail.creamStrokes()
            let sponge = await SurfaceDetail.sponge()
            guard let self else { return }
            self.spongeMaps = sponge
            self.applySponge()
            if let piping = await piping {
                var m = SceneMaterials.pbr(UIColor(hex: 0xF59BB5), roughness: 0.35, clearcoat: 0.3)
                m.normal = .init(texture: SurfaceDetail.tiled(piping))
                self.body?.setMaterial(m, forSlot: Int(CakeSquash.frostingSlot))
            }
            self.creamNormal = await strokes
            self.applyCreamShade(force: true)
            self.smearedSponge = await SurfaceDetail.spongeSmeared(filling: filling)
            if self.bulge > CakeSquash.smearAt { self.applySponge() }
        }
    }

    /// The sponge layers' material: the crumb, or once the slice is crushed the crumb smeared with filling and cream.
    private func applySponge() {
        guard !look.golden, let maps = spongeMaps, let crumb = maps.colour else { return }
        let smeared = bulge > CakeSquash.smearAt ? smearedSponge : nil
        if smeared != nil { spongeSmearShown = true }
        var m = SceneMaterials.pbr(.white, roughness: 0.85)
        m.baseColor = .init(tint: .white, texture: SurfaceDetail.tiled(smeared ?? crumb))
        if let pores = maps.normal { m.normal = .init(texture: SurfaceDetail.tiled(pores)) }
        body?.setMaterial(m, forSlot: Int(CakeSquash.spongeSlot))
    }

    /// The cream's mottle (drawn once per session; FOLD-REVIEW-8 N4).
    private static var creamTextureCache: TextureResource?

    private static func creamTexture() async -> TextureResource? {
        if let cached = creamTextureCache { return cached }
        let texture = await StudioEnvironment.textureAsync(CakeSquash.creamImage(), name: "cake.cream")
        creamTextureCache = texture
        return texture
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
        if life.update(state) {
            BeatFX.glint(fx, at: [0.01, Self.cakeHeight + 0.002, -0.006], in: entity, count: 1, golden: look.golden, rng: &rng)
        }
        for beat in story.advance(to: state.compression) { onBeat(beat, state: state) }
        let h = surfaceHeight(compression: state.compression)
        let s = CakeSquash.heightRatio(ramFace: h, candleBent: candleBent)
        // Part of the spread is the bulge (the outline changes shape), so the uniform growth is capped lower. The slice
        // spreads about its centroid, which stays on the anvil centre.
        let k = CakeSquash.uniformSpread(heightRatio: s)
        lastSpread = max(lastSpread, k * (1 + 0.15 * bulge))
        // The fight (EXPERIENCE-REVIEW-1 #1): straining against the plate, the sponge sheds crumbs and the cream cracks;
        // at the give the filling squirts out of the pinch line in the burst's frame.
        if state.resistanceBulge > 0.6 && !fought {
            fought = true
            trickle(3)
            addCreamCrack()
            life.tremor(0.2, level: 0.6)
        }
        if state.collapseLead > 0 && !gave {
            gave = true
            ooze.shove(0.35)
            life.kick(0.8)
        }
        ooze.update(compression: state.compression, spread: lastSpread)
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
            for crumb in topCrumbs {
                crumb.model.position = CakeSquash.deform(crumb.rest, layer: CakeSquash.creamLayer, progress: amount, noise: noise)
            }
            applyCreamShade()
            if !spongeSmearShown && bulge > CakeSquash.smearAt && smearedSponge != nil { applySponge() }
        }
        if bulge > 0.55 && !crumbled {
            // Crumbs fall off the bulging sponge (they persist on the plate), and torn crumbs lie on the cream top.
            crumbled = true
            let crumbColors = look.golden ? [Palette.gold, Palette.goldMessColor] : [UIColor(hex: 0xE9C48A), UIColor(hex: 0xF4D9A8)]
            fx.particles.burst(.crumb, count: 8, at: entity.convert(position: [0, 0.01, 0], to: fx.root),
                               speed: 0.18 * max(fx.motionScale, 0.3), colors: crumbColors, size: 0.002...0.0035,
                               spread: 0.05, upBias: 0.25, rng: &rng)
            scatterTopCrumbs()
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
                // Out of the rounded outline, not the rest wedge's straight side (FOLD-REVIEW-8 N4).
                let n = CakeSquash.oozeNormal(spot.normal, at: SIMD2(edge.x, edge.z), progress: bulge)
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
            // The cream tongues in the matte cream (FOLD-REVIEW-8 N4: glossy #FFF3F7 read as blown-out white eggs).
            // FOLD-REVIEW-9 N3: at the crushed cream's shade, so the tongues don't read as brighter than the top.
            let whiteBlob = look.golden ? SceneMaterials.goldMess
                : SceneMaterials.pbr(CakeSquash.shaded(CakeSquash.creamTint, CakeSquash.creamShade(progress: max(bulge, 0.8))),
                                     roughness: CakeSquash.creamRoughness)
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
        if event == .preFailureTell { life.tremor(0.25, level: 0.7) }
    }

    /// Torn crumbs lying on the crushed cream top, in the sponge's colours (cake layers smeared with crumbs).
    private func scatterTopCrumbs() {
        let colours = look.golden ? [Palette.gold, Palette.goldMessColor] : [UIColor(hex: 0xE9C48A), UIColor(hex: 0xF4D9A8), UIColor(hex: 0xD9AE6E)]
        let materials = colours.map { SceneMaterials.pbr($0, roughness: 0.85) }
        for k in 0..<16 {
            let r = Float.random(in: 0.03...0.1, using: &rng)
            let a = Float.random(in: -0.3...0.3, using: &rng) * min(1, r / 0.05)
            let rest = SIMD3<Float>(cos(a) * r, Self.cakeHeight + 0.0006, sin(a) * r)
            let crumb = Part.add(cached: "cake.crumb", { CakeSquash.crumbMesh() }, materials[k % materials.count],
                                 at: CakeSquash.deform(rest, layer: CakeSquash.creamLayer, progress: bulge, noise: bulgeNoise), to: cake)
            crumb.orientation = simd_quatf(angle: Float.random(in: 0...(2 * .pi), using: &rng), axis: [0, 1, 0])
            crumb.scale = SIMD3(repeating: Float.random(in: 0.7...1.4, using: &rng))
            topCrumbs.append((crumb, rest))
        }
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
    /// How far the back frosting's upper part slumps (share of its height) at the full squeeze.
    static let frostingSlump: Float = 0.45
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

    /// Sponge, filling, sponge, cream top and the back frosting in one mesh (slots as `bodyParts`). Each part has its
    /// own texture coordinates (3D-art round): the sponge and filling are box-projected in `spongeTile` tiles (the crumb
    /// reads on the sides, which planar UVs smeared into stripes), the cream top keeps its planar top-down UVs
    /// (`planarUV`, 0…1 over the wedge, for its mottle and spatula strokes) and the back frosting keeps its lathe UVs,
    /// scaled to `frostingTile` tiles for the piping.
    static func bodyMesh() -> MeshData {
        var mesh = MeshData()
        for part in bodyParts() {
            var piece = part.mesh
            switch Int(part.layer) {
            case creamLayer:
                piece.uvs = piece.positions.map { planarUV($0) }
            case frostingLayer:
                let around = 2 * .pi * (radius + 0.004) / frostingTile, up = cakeHeight / frostingTile
                piece.uvs = piece.uvs.count == piece.positions.count
                    ? piece.uvs.map { SIMD2($0.x * around, $0.y * up) }
                    : piece.positions.map { planarUV($0) }
            default:
                piece.boxUV(tile: spongeTile)
            }
            mesh.append(piece, materialOffset: part.slot)
        }
        return mesh
    }

    /// Texture tiles (metres): the sponge's crumb and the back frosting's piping.
    static let spongeTile: Float = 0.03
    static let frostingTile: Float = 0.022

    /// The squeeze layer of every vertex that takes the planar 0…1 cream UVs (the cream top's).
    static func isCreamVertex(_ layer: UInt8) -> Bool { Int(layer) == creamLayer }

    /// A piped rosette (star nozzle, 8 ridges, a quarter twist), base at y 0, unit-ish size: radius 0.0045, 0.0055 tall.
    static func rosetteMesh() -> MeshData {
        var profile: [SIMD2<Float>] = []
        let steps = 9
        for k in 0...steps {
            let t = Float(k) / Float(steps)
            let r = 0.0045 * (1 - pow(t, 1.6)) * (0.85 + 0.15 * sin(.pi * t))
            profile.append(SIMD2(k == steps ? 0 : max(r, 0.0002), 0.0055 * t))
        }
        profile.insert(SIMD2(0, 0), at: 0)
        var mesh = MeshKit.lathe(profile: profile, segments: 48, rimScale: { theta in 1 + 0.16 * cos(8 * theta) })
        for i in mesh.positions.indices {
            let p = mesh.positions[i]
            let twist = 0.5 * .pi * p.y / 0.0055
            let c = cos(twist), s = sin(twist)
            mesh.positions[i] = SIMD3(p.x * c - p.z * s, p.y, p.x * s + p.z * c)
        }
        mesh.recomputeNormals()
        return mesh
    }

    /// A loose crumb: a lumpy little ellipsoid.
    static func crumbMesh() -> MeshData {
        var mesh = MeshKit.ellipsoid(radii: [0.0018, 0.0012, 0.0015], segments: 10, rings: 6)
        var rng = SplitMix64(seed: 0xC2B)
        for i in mesh.positions.indices { mesh.positions[i] *= Float.random(in: 0.8...1.2, using: &rng) }
        mesh.recomputeNormals()
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

    /// Squeeze progress past which the sponge shows its smeared, crumbed crush (3D-art round).
    static let smearAt: Float = 0.6

    /// Squeeze progress (0…1) for the slice's height ratio `s`: none above 0.9, full at 0.3.
    static func progress(heightRatio s: Float) -> Float {
        clamp((0.9 - s) / 0.6, 0, 1)
    }

    /// FOLD-REVIEW-9 N3: at c = 1 the cream top (push 0.75) spread over the barrelled sponge (≤ 0.5), so from above the
    /// sponge band vanished under a white disc. As the squash completes every sponge point is drawn toward this push
    /// (cream 0.75 < sponge < filling 1.25), so a tan ring shows past the cream's edge, with the pink filling past that.
    static let spongeRimPush: Float = 1.0
    /// The back frosting starts ~4 mm (0.25 push) outside the sponge, so it needs a little less to keep covering it.
    static let frostingRimInset: Float = 0.2
    /// How far toward `spongeRimPush` the sponge has gone at squeeze `progress` (none until 0.55, all of it at 1).
    static func rimWeight(progress: Float) -> Float {
        smooth(0.55, 1, clamp(progress, 0, 1))
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
    /// −1…1) makes the lumps. Points move out from the slice's centre line and toward the oval (`blobOffset`: the apex is
    /// drawn back), and only ever down; the base stays on the plate (y 0).
    static func deform(_ p: SIMD3<Float>, layer: Int? = nil, progress: Float, noise: (Float) -> Float) -> SIMD3<Float> {
        let t = clamp(progress, 0, 1)
        guard t > 0 else { return p }
        let u = clamp(p.y / cakeHeight, 0, 1)
        // FOLD-REVIEW-8 N4: the whole outline is drawn toward a lumpy oval about the centroid, so from above the point
        // and the straight sides go; the layers' own pushes below then frill it.
        let oval = blobOffset(SIMD2(p.x, p.z), height: u, progress: t, noise: noise)
        let axis = SIMD2<Float>(clamp(p.x, axisStart, axisEnd), 0)
        var d = SIMD2<Float>(p.x, p.z) - axis
        // Ahead of the axis the tip spreads mostly sideways, so it blunts instead of growing a longer point.
        if p.x < axisStart { d.x *= apexSideways }
        let r = simd_length(d)
        guard r > 1e-5 else { return SIMD3(p.x + oval.x, p.y, p.z + oval.y) }
        // The lumps vary round the slice and along its straight sides (where the push direction is constant).
        let phase = atan2(d.y, d.x) + alongSide * p.x
        let apex = clamp(p.x / apexReach, apexMin, 1)
        var y = p.y
        let push: Float
        // FOLD-REVIEW-9 N3: near full squash the sponge bulges out past the cream top's edge, so a band stays visible.
        let rim = rimWeight(progress: t)
        switch layer ?? inferredLayer(u) {
        case fillingLayer:
            push = fillingPush * (1 + fillingLumpiness * noise(phase * 1.3 + 2.1))
            // Squeezed out past the sponge, it sags toward the plate the further it has gone.
            y *= 1 - fillingDroop * smooth(0.3, 1.1, push * apex * t / fillingPush)
        case creamLayer:
            push = creamPush * (1 + lumpiness * noise(phase + 1.7 * u))
        case frostingLayer:
            // The back frosting rides out over the bulging sponge (it starts ~4 mm outside it), up to the cream.
            let base = profile(u)
            let cover = (spongeRimPush - frostingRimInset) * (1 - smooth(0.85, 1, u))
            push = (base + rim * max(cover - base, 0)) * (1 + lumpiness * noise(phase + 1.7 * u))
            // EXPERIENCE-REVIEW-1 #5 ("a concave dish"): the squeezed frosting slumps outward and down instead of
            // standing as a wall round the cream, so the cream reads heaped, not sunk in a dish.
            y *= 1 - frostingSlump * rim * smooth(0.5, 1, u)
        default:
            let base = spongeBarrel * sin(.pi * u)
            // The ring is what shows from above: the upper sponge's top edge. Below it the sponge keeps its plain barrel,
            // so the tip still blunts (the apex is drawn back; SceneTests.cakeSquashBulgesTheOutline).
            let ring = rim * smooth(0.55, 0.8, u)
            push = (base + ring * (spongeRimPush - base)) * (1 + lumpiness * noise(phase + 1.7 * u))
        }
        let out = d / r * (bulgeReach * t * push * apex)
        return SIMD3(p.x + out.x + oval.x, y, p.z + out.y + oval.y)
    }

    // MARK: The crush toward an oval (FOLD-REVIEW-8 N4)

    /// FOLD-REVIEW-8 N4: at c = 1 the slice kept its full wedge outline from above (the pushes are constant along a
    /// straight side, so the sides stayed straight and the point stayed a point). As it squashes, every point is now
    /// also moved along its ray from the centroid toward a lumpy oval (`blobLong` toward the apex/arc × `blobAcross`
    /// across, ± `blobLumpiness`), `roundness` of the way at full squash (a little less at the base, `baseRound`):
    /// the apex is drawn back ~10 mm, the arc's corners round off and the sides swell, so it reads as a squashed cake.
    /// A radial map about one point (the cap fans' centre), so every layer stays stacked and no wall folds over.
    static let blobLong: Float = 0.050
    static let blobAcross: Float = 0.040
    static let roundness: Float = 0.75
    static let blobLumpiness: Float = 0.06
    static let baseRound: Float = 0.85

    /// Distance from the centroid along `angle` (wedge space, 0 = toward the arc, π = toward the apex) to the rest
    /// wedge's outline: the nearest of the arc and the two straight sides.
    static func restRadius(angle: Float) -> Float {
        let d = SIMD2<Float>(cos(angle), sin(angle))
        let b = centroidX * d.x
        let c = centroidX * centroidX - radius * radius
        var best = -b + max(b * b - c, 0).squareRoot()
        for side: Float in [-1, 1] {
            // The side through the apex at ±halfAngle; its normal n, and the ray's crossing C + t d with n · p = 0.
            let n = SIMD2<Float>(-sin(side * halfAngle), cos(side * halfAngle))
            let den = simd_dot(d, n)
            guard abs(den) > 1e-6 else { continue }
            let t = -centroidX * n.x / den
            if t > 0 { best = min(best, t) }
        }
        return max(best, 1e-4)
    }

    /// The oval's radius along `angle` (before the lumps).
    static func blobRadius(angle: Float) -> Float {
        let x = cos(angle) / blobLong, z = sin(angle) / blobAcross
        return 1 / max((x * x + z * z).squareRoot(), 1e-3)
    }

    /// How far (wedge metres, x and z) the point `p` (x, z) at height share `u` is moved toward the oval at `progress`.
    static func blobOffset(_ p: SIMD2<Float>, height u: Float, progress: Float, noise: (Float) -> Float) -> SIMD2<Float> {
        let t = clamp(progress, 0, 1)
        let d = SIMD2<Float>(p.x - centroidX, p.y)
        guard t > 0, simd_length(d) > 1e-6 else { return .zero }
        let angle = atan2(d.y, d.x)
        let target = blobRadius(angle: angle) * (1 + blobLumpiness * noise(angle + 0.6))
        let w = roundness * smooth(0.05, 1, t) * (baseRound + (1 - baseRound) * clamp(u, 0, 1))
        return d * ((target / restRadius(angle: angle) - 1) * w)
    }

    /// The outward direction of an ooze tongue leaving the squeezed slice at wedge-space `point` (x, z): the rest
    /// outline's `normal`, turned toward the ray from the centroid as the outline rounds.
    static func oozeNormal(_ normal: SIMD2<Float>, at point: SIMD2<Float>, progress: Float) -> SIMD2<Float> {
        let d = SIMD2<Float>(point.x - centroidX, point.y)
        guard simd_length(d) > 1e-5 else { return normal }
        let w = roundness * smooth(0.05, 1, clamp(progress, 0, 1))
        let n = normal * (1 - w) + simd_normalize(d) * w
        return simd_length(n) > 1e-5 ? simd_normalize(n) : normal
    }

    // MARK: The cream top (FOLD-REVIEW-8 N4)

    /// The cream top: #FFF3F7 with a 0.3 clearcoat clipped to flat white under the key, so no squash could shade.
    /// Now a darker, matte cream (no clearcoat) with a faint mottle (`creamImage`) so the form shades.
    static let creamTint: UInt32 = 0xF4E3E7
    static let creamRoughness: Float = 0.62
    /// The mottle: soft blotches a little darker (warm pink-beige) and lighter than the tint.
    static let creamDark: UInt32 = 0xE6CDD3
    static let creamLight: UInt32 = 0xFAF1F3
    /// The fold shadow round the top's rim (FOLD-REVIEW-9 N3).
    static let creamFold: UInt32 = 0xD6B9C1
    /// Planar (top-down) UVs over the wedge: x 0…`uvSpan`, z ±`uvSpan`/2, so the mottle spreads with the cream.
    static let uvSpan: Float = 0.12

    static func planarUV(_ p: SIMD3<Float>) -> SIMD2<Float> {
        SIMD2(p.x / uvSpan, 0.5 + p.z / uvSpan)
    }

    /// FOLD-REVIEW-9 N3: flattened and facing the key head-on, the cream top still clipped to flat white at c = 1. Its
    /// albedo steps down as the squash completes (the textured material's tint, × the mottle), so it shades and the
    /// mottle and the rim's fold shadow stay visible.
    /// EXPERIENCE-REVIEW-1 #5 ("a grey concave dish"): 0.82 greyed the crushed cream; it stays cream now (the mottle
    /// and the spatula strokes carry the shading).
    static let crushedShade: Float = 0.93

    /// The cream's albedo multiplier at squeeze `progress`: 1 until 0.45, `crushedShade` at 1.
    static func creamShade(progress: Float) -> Float {
        1 - (1 - crushedShade) * smooth(0.45, 1, clamp(progress, 0, 1))
    }

    /// `hex` scaled by `shade` (the cream ooze tongues, which only appear once the slice is crushed).
    static func shaded(_ hex: UInt32, _ shade: Float) -> UIColor {
        let f = CGFloat(clamp(shade, 0, 1))
        return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255 * f, green: CGFloat((hex >> 8) & 0xFF) / 255 * f,
                       blue: CGFloat(hex & 0xFF) / 255 * f, alpha: 1)
    }

    /// The rest outline in the cream texture's pixel space (`planarUV`; the wedge is symmetric about v 0.5, so either
    /// texture-v convention maps it onto itself).
    static func uvOutline(side: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let points = wedge().map { CGPoint(x: CGFloat($0.x / uvSpan) * side, y: CGFloat(0.5 + $0.y / uvSpan) * side) }
        path.addLines(between: points)
        path.closeSubpath()
        return path
    }

    /// The cream's colour texture: the tint, mottled with ~70 soft seeded blotches (≈ 3–13 mm on the slice).
    @MainActor
    static func creamImage(size: Int = 128, seed: UInt64 = 0xC4EA_3007) -> CGImage? {
        let side = CGFloat(size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        var rng = SplitMix64(seed: seed)
        let image = renderer.image { context in
            let cg = context.cgContext
            cg.setFillColor(UIColor(hex: creamTint).cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: side, height: side))
            let space = CGColorSpaceCreateDeviceRGB()
            for k in 0..<70 {
                let dark = k % 3 != 0
                let colour = UIColor(hex: dark ? creamDark : creamLight)
                // FOLD-REVIEW-9 N3: the dark blotches a step stronger, so the mottle survives the flat top's key light.
                let alphas: ClosedRange<Float> = dark ? 0.35...0.65 : 0.35...0.7
                let alpha = CGFloat(Float.random(in: alphas, using: &rng))
                let colours = [colour.withAlphaComponent(alpha).cgColor, colour.withAlphaComponent(0).cgColor] as CFArray
                guard let gradient = CGGradient(colorsSpace: space, colors: colours, locations: [0, 1]) else { continue }
                let centre = CGPoint(x: CGFloat(Float.random(in: 0...1, using: &rng)) * side,
                                     y: CGFloat(Float.random(in: 0...1, using: &rng)) * side)
                let radius = CGFloat(Float.random(in: 0.025...0.11, using: &rng)) * side
                cg.drawRadialGradient(gradient, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: radius,
                                      options: [])
            }
            // EXPERIENCE-REVIEW-1 #5: the old fold shadow drawn just inside the *rest* outline became, once the top had
            // spread to an oval, a dark ring inside the cream: the walls of a dish. Only a faint shade on the outline
            // itself is left (the cream slab's walls map onto it), so the crushed top reads as heaped cream.
            let outline = uvOutline(side: side)
            cg.saveGState()
            cg.setLineJoin(.round)
            cg.setStrokeColor(UIColor(hex: creamFold).withAlphaComponent(0.12).cgColor)
            cg.setLineWidth(side * 0.015)
            cg.addPath(outline)
            cg.strokePath()
            cg.restoreGState()
        }
        return image.cgImage
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
