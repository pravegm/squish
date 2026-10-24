import Foundation
import RealityKit
import simd
import UIKit

/// Glass Bottle (bible §4 #9, VISUAL-TARGET §5.9): a sea-glass bottle lying on its side, neck camera-right,
/// pre-fractured into ~30 thin shards (2.2 mm lathe patches, 45–72° arcs) under one intact paper label band.
/// Silent rigidity until fracture 0 (~0.22), apart from a slight ovalisation; then two crack stars on the camera side
/// (`GlassCrack`, FOLD-REVIEW-8 N3: one on the upper flank for the Duo, one on the front flank for the P-48, whose ram
/// hides the top) of thick, dark-cored bright lines that grow from their impacts toward the failure. Fracture 1 (failure, ~0.40) is the biggest event in the app: the label tears away; the base
/// ring and the neck stay whole (curved bottle glass on the heap, FOLD-REVIEW-7 #5) and every other curved patch breaks
/// into two flat, irregular convex shards (or, one in three, stays one big piece) of bottle glass in two tints, darker
/// than the steel, with a dark hairline and a bright bevel on every edge and a specular streak across the face
/// (FOLD-REVIEW-4 F5, FOLD-REVIEW-5 N5, FOLD-REVIEW-7 N8: ~45 pieces, ~4–21 mm, ~3× in area) that heap up in the middle
/// of the plate, the big ones in the centre and one in five propped up on the others (FOLD-REVIEW-6 N10; no pale dust
/// disc under them), skid a little (fade-and-slump under Reduce Motion) and stay on the
/// strike plate (+16 pt); 10 label scraps (6 raspberry, 4 cream, ~a shard each) lie on top so the pile is still "a bottle",
/// and 6 glints twinkle until the seal. Fracture 2 (~0.62): the pile crunches into soft "sea glass". The pile freezes
/// at seal, so the reveal shows exactly the sealed pile (FOLD-REVIEW-3 N5). Surprise `messageInABottle`: a rolled
/// note that bursts into candy confetti.
@MainActor
final class GlassBottleView: PressObjectView {
    let entity = Entity()
    /// ×0.76 (FOLD-REVIEW-3 N14: ×0.88 of round 2's 0.86) so the bottle and its projected height stay on the Duo strike
    /// plate at rest (it overhung the plate's lateral edge by ~20 pt); authored at Ø 0.060.
    static let heroScale: Float = 0.76
    static let localHeight: Float = 0.060
    let restHeight: Float = 0.060 * GlassBottleView.heroScale
    let footprint: Float = 0.068 * GlassBottleView.heroScale

    private let fx: SceneFX
    private let look: Look
    private var rng = SplitMix64(seed: 0)
    private let bottle = Entity()
    /// One debris body per lathe patch: the curved patch (`patchModels`) until the shatter, then its flat fragment pair.
    private var shards: [ModelEntity] = []
    private var patchModels: [Entity] = []
    private var fragments: [Entity] = []
    /// Per shard: the parent of its fragment pair, label scrap and glint, which the shatter lifts and tilts so the pile
    /// heaps up in the middle (FOLD-REVIEW-6 N10). The debris body (the shard) itself stays yaw-only.
    private var poses: [Entity] = []
    /// The fragments' glass faces and bright edges (the crunch swaps both to frosted sea glass), and the specular streak
    /// across each face (the crunch frosts it away).
    private var fragmentFaces: [ModelEntity] = []
    private var fragmentEdges: [ModelEntity] = []
    private var fragmentStreaks: [ModelEntity] = []
    /// Per shard: kept whole at the shatter (the base ring and the neck: FOLD-REVIEW-7 #5, curved glass that says
    /// "bottle"), and for those the rotation that puts their mesh back in the bottle's lathe axes.
    private var intact: [Bool] = []
    private var intactNeck: [Bool] = []
    private var latheAxes: [simd_quatf] = []
    /// Per shard: one big piece rather than a split pair (they land in the middle of the heap).
    private var singles: [Bool] = []
    /// Six glints on the pile that twinkle from the shatter until the seal (FOLD-REVIEW-4 F5: was a static white dot
    /// on every third shard).
    private var sparkles: [Entity] = []
    /// The intact paper label (one band, not split into shards); it tears away at the shatter.
    private let labelBand = Entity()
    /// Flat label scraps lying on top of shards, shown once the label has torn (FOLD-REVIEW-4 F5: 6 raspberry, 4 cream).
    private var labelScraps: [Entity] = []
    /// The crack stars (FOLD-REVIEW-8 N3): every line, impact and their parent, which the shatter removes.
    private let crackRoot = Entity()
    private var crackLines: [CrackLine] = []
    private var crackImpacts: [(edge: ModelEntity, core: ModelEntity, at: SIMD2<Float>)] = []
    private let crackSeed: UInt64
    private var crackC: Float = 0
    private var cracked = false
    private var message: Entity?
    private let failC: Float
    private var failed = false
    private var sealed = false
    /// Latched pre-failure squash (vertical height ratio): never un-squash.
    private var squash: Float = 1
    /// Half extents (x, z) in fx metres the debris must stay inside: the strike plate + 16 pt.
    private let containment: SIMD2<Float>
    private let seaGlass: PhysicallyBasedMaterial
    private let seaGlassEdge: any Material
    /// The storyboard (OBJECT-STORYBOARDS §9): silent rigidity that still shows stress (a glow that builds, chips, an
    /// early crack that creeps), then a pile that tinkles as it settles. Beat effects draw from their own stream, so the
    /// shatter's pile for a seed doesn't depend on which beats fired.
    private let life: ObjectLife
    private var story: StoryCursor
    private var beatRng: SplitMix64
    private var glowLevel = 0

    /// One segment of a crack star's ray: a bright line with a dark core on top of it. Segments appear in order from
    /// the impact and lengthen with compression.
    private struct CrackLine {
        let edge: ModelEntity
        let core: ModelEntity
        /// The segment's ends on the body, as (entity x, angle round the body from the top toward the camera, +z).
        let start: SIMD2<Float>
        let end: SIMD2<Float>
        /// The part of its ray (0…1) this segment covers, and its width share (the rays taper toward their tips).
        let from: Float
        let to: Float
        let width: Float
    }

    static let length: Float = 0.140
    static let profile: [SIMD2<Float>] = MeshKit.smoothProfile([
        SIMD2(0.000, 0.000), SIMD2(0.026, 0.0015), SIMD2(0.0295, 0.005), SIMD2(0.030, 0.010), SIMD2(0.030, 0.040),
        SIMD2(0.030, 0.075), SIMD2(0.0285, 0.088), SIMD2(0.023, 0.100), SIMD2(0.016, 0.110), SIMD2(0.0118, 0.118),
        SIMD2(0.0110, 0.130), SIMD2(0.0125, 0.133), SIMD2(0.0128, 0.138), SIMD2(0.0112, 0.1395), SIMD2(0.000, 0.1398),
    ], perSpan: 3)

    init(variant: PressVariant, fx: SceneFX) {
        self.fx = fx
        let look = Look(variant)
        self.look = look
        failC = PressObjectFactory.failureThreshold(.glassBottle, variant: variant) ?? 0.4
        // The crunch frosts the faces but keeps the bottle-glass tint (FOLD-REVIEW-5 N5: the old pale #5CC8B8 at 0.55 was
        // the "paper" in every reveal, since most presses reach the crunch).
        seaGlass = look.golden ? SceneMaterials.gold
            : SceneMaterials.enamel(UIColor(hex: GlassDebris.seaGlassTint), roughness: 0.38, clearcoat: 0.7,
                                    clearcoatRoughness: 0.25, specular: 1, opacity: GlassDebris.seaGlassOpacity)
        if look.golden {
            seaGlassEdge = SceneMaterials.gold
        } else {
            seaGlassEdge = SceneMaterials.unlit(UIColor(hex: 0xC9EDE6), opacity: 0.8)
        }
        containment = GlassDebris.containment(restHeight: 0.060 * Self.heroScale, anvilHalf: PressRig.anvilHalf)
        rng = SplitMix64(seed: variant.seed ^ 0x6A55)
        crackSeed = variant.seed ^ 0xC2AC_5747
        life = ObjectLife(seed: variant.seed, idle: .still, amount: 0, rate: 0.3, pulseHz: 8, pulseDamping: 0.5)
        story = StoryCursor(.glassBottle, seed: variant.seed)
        beatRng = SplitMix64(seed: variant.seed ^ 0xB1A5_7)
        build(variant: variant)
        life.adopt(childrenOf: entity)
    }

    /// The bottle's outer glass with its stress glow step (`GlassStress`).
    private func stressedGlass(level: Int) -> PhysicallyBasedMaterial {
        var m = SceneMaterials.enamel(UIColor(hex: 0x5CC8B8), roughness: 0.04, clearcoat: 1, clearcoatRoughness: 0.02,
                                      specular: 1, opacity: 0.32 + 0.04 * Float(level))
        m.emissiveColor = .init(color: UIColor(hex: GlassStress.glowTint))
        m.emissiveIntensity = GlassStress.glow(level: level)
        return m
    }

    /// One stress-glow step on the intact bottle (the glass whitens under load).
    private func glowStep() {
        guard !failed, !look.golden, glowLevel < GlassStress.steps else { return }
        glowLevel += 1
        let material = stressedGlass(level: glowLevel)
        for patch in patchModels {
            Self.models(in: patch).first?.model?.materials = [material]
        }
    }

    /// One storyboard beat (OBJECT-STORYBOARDS §9).
    private func onBeat(_ beat: StoryBeat, state: PressVisualState) {
        let golden = look.golden
        switch beat.kind {
        case .kiss:
            for x: Float in [-0.05, 0.0, 0.05] {
                BeatFX.glint(fx, at: [x, 0.061, 0.004], in: entity, count: 1, golden: golden, rng: &beatRng)
            }
        case .glow:
            glowStep()
            BeatFX.glint(fx, at: [Float.random(in: -0.05...0.04, using: &beatRng), 0.058, 0.01], in: entity, count: 1,
                         golden: golden, rng: &beatRng)
        case .chip:
            if failed {
                fx.particles.burst(.flake, count: 3, at: entity.convert(position: [0, 0.006, 0], to: fx.root), speed: 0.06,
                                   colors: golden ? [Palette.gold] : [UIColor(hex: 0x8FE0D3)], size: 0.0015...0.003,
                                   spread: 0.03, upBias: 0.4, rng: &beatRng)
                BeatFX.glint(fx, at: [Float.random(in: -0.03...0.03, using: &beatRng), 0.008, 0], in: entity, count: 2,
                             golden: golden, rng: &beatRng)
            } else {
                // A fleck chips off the lip.
                let lip = entity.convert(position: [0.069, 0.030, 0.008], to: fx.root)
                fx.particles.burst(.flake, count: 2, at: lip, speed: 0.08, colors: golden ? [Palette.gold] : [UIColor(hex: 0x8FE0D3)],
                                   size: 0.0015...0.0025, upBias: 0.5, rng: &beatRng)
                BeatFX.glint(fx, at: [0.069, 0.031, 0.008], in: entity, count: 2, golden: golden, rng: &beatRng)
                life.kick(0.2)
            }
        case .crack:
            if !failed && !cracked {
                // The crack starts early and creeps (fracture 0 only makes it louder).
                cracked = true
                crackC = state.compression
                buildCracks()
                growCracks(compression: state.compression)
            }
            if !failed, let impact = GlassCrack.impacts.first {
                let spot = GlassCrack.surface(x: impact.x, angle: impact.angle, squash: squash)
                BeatFX.glint(fx, at: spot.point + spot.normal * 0.002, in: entity, count: 2, golden: golden, rng: &beatRng)
            }
            life.kick(0.2)
        case .strain, .tell:
            glowStep()
            life.tremor(beat.kind == .tell ? 0.3 : 0.18, level: 0.8)
        case .settle:
            if failed { tinkle(2) } else { glowStep() }
        case .sheen:
            BeatFX.glint(fx, at: [Float.random(in: -0.03...0.03, using: &beatRng), 0.01, Float.random(in: -0.02...0.02, using: &beatRng)],
                         in: entity, count: 3, golden: golden, rng: &beatRng)
        default:
            life.kick(0.2)
        }
    }

    /// A couple of shards on the pile hop and settle again (the tinkle), until the seal freezes it.
    private func tinkle(_ count: Int) {
        guard failed, !sealed else { return }
        let m = fx.motionScale
        let loose = shards.indices.filter { !(($0 < intact.count) && intact[$0]) }
        guard !loose.isEmpty else { return }
        for _ in 0..<count {
            let shard = shards[loose[Int(beatRng.next() % UInt64(loose.count))]]
            guard let body = fx.debris.release(shard) else { continue }
            var bounds: (min: SIMD2<Float>, max: SIMD2<Float>)?
            if let lo = body.boundsMin, let hi = body.boundsMax { bounds = (min: lo, max: hi) }
            let v = SIMD3<Float>(Float.random(in: -0.02...0.02, using: &beatRng), 0.08, Float.random(in: -0.02...0.02, using: &beatRng)) * m
            fx.debris.adopt(shard, velocity: v, spin: SIMD3(0, Float.random(in: -3...3, using: &beatRng) * m, 0),
                            bounciness: 0.1, friction: 0.8, maxSpread: 1, bounds: bounds)
            BeatFX.glint(fx, at: shard.position(relativeTo: entity) + SIMD3(0, 0.003, 0), in: entity, count: 1,
                         golden: look.golden, rng: &beatRng)
        }
    }

    private func build(variant: PressVariant) {
        let outer = look.golden ? SceneMaterials.gold
            : SceneMaterials.enamel(UIColor(hex: 0x5CC8B8), roughness: 0.04, clearcoat: 1, clearcoatRoughness: 0.02,
                                    specular: 1, opacity: 0.32)
        let inner = look.golden ? SceneMaterials.gold
            : SceneMaterials.enamel(UIColor(hex: 0x2E5E58), roughness: 0.05, clearcoat: 1, clearcoatRoughness: 0.02,
                                    specular: 1, opacity: 0.40) // dark refraction rim so the edges read on pale steel
        let label = look.golden ? SceneMaterials.pbr(UIColor(hex: 0x8A5A00), roughness: 0.5)
            : SceneMaterials.pbr(Palette.glassLabel, roughness: 0.7)
        let labelStripe = look.golden ? label : SceneMaterials.pbr(Palette.raspberry, roughness: 0.6)

        // Lying: lathe about local Y, rolled −90° about Z (neck → +X), centred on its length, resting on the anvil.
        bottle.orientation = simd_quatf(angle: -.pi / 2, axis: [0, 0, 1])
        bottle.position = [0, 0.030, 0]
        let axial = Entity()
        axial.position = [0, -Self.length / 2, 0]
        bottle.addChild(axial)

        let profile = Self.profile
        let labelProfile = profile.map { SIMD2($0.x + 0.0006, $0.y) }
        let normals2 = MeshKit.profile2DNormals(profile)
        func ring(at y: Float) -> Int {
            profile.firstIndex { $0.y >= y } ?? profile.count - 1
        }
        // The flat fragments every patch breaks into (FOLD-REVIEW-4 F5, FOLD-REVIEW-5 N5): bottle glass that is darker
        // than the steel it lies on (#5CC8B8 taken 35 % toward a deep #2F8F82, at 0.7) under a bright clearcoat, with a
        // clear two-tone edge: a dark hairline where the thick glass edge refracts, and a bright bevel just inside it
        // where it catches the light. So each shard reads on a white-hot plate, on the mid-grey platen and under the
        // P-48's key. A few seeded shapes are shared (cached for the session) and each patch scales and yaws its own.
        // Two bottle-glass tints, so neighbouring shards don't read as one flat sheet of the same paper (FOLD-REVIEW-7 #5).
        var fragmentFaceTints: [any Material] = []
        if look.golden {
            fragmentFaceTints.append(SceneMaterials.gold)
        } else {
            for tint in [GlassDebris.shardTint, GlassDebris.shardTintDeep] {
                fragmentFaceTints.append(SceneMaterials.enamel(UIColor(hex: tint), roughness: 0.04, clearcoat: 1,
                                                               clearcoatRoughness: 0.02, specular: 1,
                                                               opacity: GlassDebris.shardOpacity))
            }
        }
        let fragmentEdge: any Material
        let fragmentOutline: any Material
        let fragmentStreak: any Material
        if look.golden {
            fragmentEdge = SceneMaterials.gold
            fragmentOutline = SceneMaterials.pbr(UIColor(hex: 0x8A5A00), roughness: 0.3, metallic: 1)
            fragmentStreak = SceneMaterials.unlit(UIColor(hex: 0xFFF1C4), opacity: GlassDebris.streakOpacity)
        } else {
            fragmentEdge = SceneMaterials.unlit(UIColor(hex: 0xF2FFFC), opacity: 0.95)
            fragmentOutline = SceneMaterials.unlit(UIColor(hex: GlassDebris.outlineTint), opacity: 0.9)
            fragmentStreak = SceneMaterials.unlit(UIColor(hex: 0xFFFFFF), opacity: GlassDebris.streakOpacity)
        }
        typealias FragmentResources = (face: MeshResource?, edge: MeshResource?, outline: MeshResource?, streak: MeshResource?)
        var fragmentResources: [FragmentResources] = []
        for v in 0..<GlassDebris.fragmentVariants {
            let seed = GlassDebris.fragmentSeed(v)
            let face = MeshCache.resource("glass.frag.\(v).0") { GlassDebris.fragmentSlot(GlassDebris.fragmentPair(seed: seed), slot: 0) }
            let edge = MeshCache.resource("glass.frag.\(v).1") { GlassDebris.fragmentSlot(GlassDebris.fragmentPair(seed: seed), slot: 1) }
            let outline = MeshCache.resource("glass.frag.\(v).2") { GlassDebris.fragmentSlot(GlassDebris.fragmentPair(seed: seed), slot: 2) }
            let streak = MeshCache.resource("glass.frag.\(v).3") { GlassDebris.fragmentSlot(GlassDebris.fragmentPair(seed: seed), slot: 3) }
            fragmentResources.append((face, edge, outline, streak))
        }
        var singleResources: [FragmentResources] = []
        for v in 0..<GlassDebris.singleVariants {
            let seed = GlassDebris.singleSeed(v)
            let face = MeshCache.resource("glass.single.\(v).0") { GlassDebris.fragmentSlot(GlassDebris.fragmentSingle(seed: seed), slot: 0) }
            let edge = MeshCache.resource("glass.single.\(v).1") { GlassDebris.fragmentSlot(GlassDebris.fragmentSingle(seed: seed), slot: 1) }
            let outline = MeshCache.resource("glass.single.\(v).2") { GlassDebris.fragmentSlot(GlassDebris.fragmentSingle(seed: seed), slot: 2) }
            let streak = MeshCache.resource("glass.single.\(v).3") { GlassDebris.fragmentSlot(GlassDebris.fragmentSingle(seed: seed), slot: 3) }
            singleResources.append((face, edge, outline, streak))
        }
        var scrapResources: [MeshResource] = []
        for v in 0..<GlassDebris.scrapVariants {
            let seed = GlassDebris.scrapSeed(v)
            if let scrap = MeshCache.resource("glass.scrap.\(v)", { GlassDebris.scrap(seed: seed) }) {
                scrapResources.append(scrap)
            }
        }
        let sparkleMesh = MeshCache.resource("glass.sparkle") { MeshKit.ellipsoid(radii: [0.0016, 0.0005, 0.0016], segments: 12, rings: 6) }
            ?? .generateSphere(radius: 0.001)
        let sparkleMaterial = SceneMaterials.unlit(UIColor(hex: 0xFFFFFF))

        let bandEdges = [0, ring(at: 0.006), ring(at: 0.035), ring(at: 0.060), ring(at: 0.085), ring(at: 0.112), profile.count - 1]
        let sectorCounts = GlassDebris.sectorCounts
        var bandShards: [[Int]] = []
        var fragmentSizes: [SIMD2<Float>] = []
        var layers: [Float] = []
        for b in 0..<(bandEdges.count - 1) {
            let rings = bandEdges[b]...bandEdges[b + 1]
            let n = sectorCounts[b]
            let offset = Float.random(in: 0...(2 * .pi), using: &rng)
            // ±0.22 rad of jitter on 60° arcs was ±21 %; keep the same share on the narrower arcs.
            let jitter = n > 1 ? 0.22 * 6 / Float(max(n, 6)) : 0
            var cuts: [Float] = (0..<n).map { k in
                offset + 2 * .pi * Float(k) / Float(n) + (n > 1 ? Float.random(in: -jitter...jitter, using: &rng) : 0)
            }
            cuts.append(cuts[0] + 2 * .pi)
            // The patch's size along the profile (height) and round the bottle (arc width at its middle ring).
            var along: Float = 0
            for i in rings.lowerBound..<rings.upperBound { along += simd_length(profile[i + 1] - profile[i]) }
            let mid = (rings.lowerBound + rings.upperBound) / 2
            var indices: [Int] = []
            for k in 0..<n {
                let patch = MeshKit.lathePatch(profile: profile, rings: rings, angles: cuts[k]...cuts[k + 1],
                                               angularSteps: max(4, 48 / n), thickness: 0.0022)
                let theta = (cuts[k] + cuts[k + 1]) / 2
                let n2 = normals2[mid]
                let normal = simd_normalize(SIMD3<Float>(n2.x * cos(theta), n2.y, n2.x * sin(theta)))
                // Author each shard with its outward normal as local +Y (its thin axis): the fragments are drawn flat in
                // that local XZ plane, so turning the shard yaw-only at the shatter lays them flat on the plate.
                let toLocal = simd_quatf(from: normal, to: [0, 1, 0])
                let rotate = simd_float4x4(toLocal)
                let shard = ModelEntity()
                let model = MeshKit.entity(patch.mesh.transformed(rotate), materials: [outer, inner], name: "glass.shard")
                shard.addChild(model)
                patchModels.append(model)
                shard.position = patch.centre
                shard.orientation = toLocal.inverse

                // The base ring and the neck stay whole (curved glass on the pile: FOLD-REVIEW-7 #5). Every other patch
                // breaks into a fragment pair or, one in `singleShare`, stays one big piece (hidden until the shatter),
                // sized to the patch (× a seeded 0.75–1.08, so sizes vary ~3× in area), and stacked a hair apart in
                // height so overlapping pieces never z-fight.
                let keepWhole = n == 1 && GlassDebris.intactBands.contains(b)
                let single = !keepWhole && rng.next() % GlassDebris.singleShare == 0
                intact.append(keepWhole)
                intactNeck.append(keepWhole && b == bandEdges.count - 2)
                latheAxes.append(toLocal.inverse)
                singles.append(single)
                let width = profile[mid].x * (cuts[k + 1] - cuts[k])
                let grow = Float.random(in: single ? GlassDebris.singleScale : GlassDebris.pairScale, using: &rng)
                let size = GlassDebris.fragmentSize(width: width, height: along) * grow
                let layer = GlassDebris.layerHeight(shards.count)
                let pose = Entity()
                shard.addChild(pose)
                poses.append(pose)
                let fragment = Entity()
                if !keepWhole {
                    let variant = Int(rng.next() % UInt64(single ? GlassDebris.singleVariants : GlassDebris.fragmentVariants))
                    let resources = single ? singleResources[variant] : fragmentResources[variant]
                    let tint = fragmentFaceTints[Int(rng.next() % UInt64(fragmentFaceTints.count))]
                    if let face = resources.face {
                        let model = ModelEntity(mesh: face, materials: [tint])
                        fragment.addChild(model)
                        fragmentFaces.append(model)
                    }
                    if let edge = resources.edge {
                        let model = ModelEntity(mesh: edge, materials: [fragmentEdge])
                        fragment.addChild(model)
                        fragmentEdges.append(model)
                    }
                    if let outline = resources.outline {
                        fragment.addChild(ModelEntity(mesh: outline, materials: [fragmentOutline]))
                    }
                    if let streak = resources.streak {
                        let model = ModelEntity(mesh: streak, materials: [fragmentStreak])
                        fragment.addChild(model)
                        fragmentStreaks.append(model)
                    }
                }
                fragment.scale = SIMD3(size.x, 1, size.y)
                fragment.position = [0, layer, 0]
                fragment.isEnabled = false
                pose.addChild(fragment)
                fragments.append(fragment)
                fragmentSizes.append(size)
                layers.append(layer)

                indices.append(shards.count)
                axial.addChild(shard)
                shards.append(shard)
            }
            bandShards.append(indices)
        }

        // Label scraps at ~1 fragment piece (×1.4, FOLD-REVIEW-5 N5), lying on top of shards: 6 raspberry (stripe band),
        // 4 cream.
        if !scrapResources.isEmpty {
            let wanted = [(band: 3, count: GlassDebris.labelScraps.pink, material: labelStripe),
                          (band: 2, count: GlassDebris.labelScraps.cream, material: label)]
            for entry in wanted where entry.band < bandShards.count {
                let picks = bandShards[entry.band].shuffled(using: &rng).prefix(entry.count)
                for i in picks {
                    let size = fragmentSizes[i]
                    let piece = GlassDebris.scrapPiece(size, single: singles[i])
                    let scrap = ModelEntity(mesh: scrapResources[Int(rng.next() % UInt64(scrapResources.count))],
                                            materials: [entry.material])
                    let side: Float = rng.next() % 2 == 0 ? -1 : 1
                    scrap.scale = SIMD3(piece.x * GlassDebris.scrapScale, 1, piece.y * GlassDebris.scrapScale)
                    scrap.position = [side * size.x * (singles[i] ? 0.12 : 0.25),
                                      layers[i] + GlassDebris.fragmentThickness / 2 + 0.00035, 0]
                    scrap.orientation = simd_quatf(angle: Float.random(in: -0.5...0.5, using: &rng), axis: [0, 1, 0])
                    scrap.isEnabled = false
                    poses[i].addChild(scrap)
                    labelScraps.append(scrap)
                }
            }
        }
        // Six glints, on body shards (never the base or the neck), over one fragment piece each.
        let bodyShards = (1...4).flatMap { $0 < bandShards.count ? bandShards[$0] : [] }
        for i in bodyShards.shuffled(using: &rng).prefix(GlassDebris.sparkleCount) {
            let sparkle = ModelEntity(mesh: sparkleMesh, materials: [sparkleMaterial])
            let side: Float = rng.next() % 2 == 0 ? -1 : 1
            sparkle.position = [side * fragmentSizes[i].x * 0.25, layers[i] + GlassDebris.fragmentThickness / 2 + 0.0004, 0]
            sparkle.isEnabled = false
            poses[i].addChild(sparkle)
            sparkles.append(sparkle)
        }
        // The intact label: cream band, raspberry stripe band, wrapped all the way round (hidden at the shatter).
        for b in 2...3 {
            let rings = bandEdges[b]...bandEdges[b + 1]
            let band = MeshKit.lathePatch(profile: labelProfile, rings: rings, angles: 0...(2 * .pi), angularSteps: 48,
                                          thickness: 0.0005)
            let model = MeshKit.entity(band.mesh, materials: [b == 2 ? label : labelStripe, label], name: "glass.labelBand")
            model.position = band.centre
            labelBand.addChild(model)
        }
        axial.addChild(labelBand)
        if !look.golden {
            // The printed label (fidelity pass): cream and raspberry bands with a wordmark, once the print is up.
            let bands = labelBand.children.map { $0 }
            Task { @MainActor in
                guard let print = await SurfaceDetail.bottleLabel() else { return }
                let material = SceneMaterials.textured(print, roughness: 0.7)
                for band in bands { Self.models(in: band).first?.model?.materials = [material] }
            }
        }
        if variant.surprise == .messageInABottle {
            let note = Entity()
            Part.add(cached: "glass.note", { MeshKit.roundedCylinder(radius: 0.008, height: 0.06, bevel: 0.003, segments: 32) },
                     SceneMaterials.pbr(UIColor(hex: 0xF4ECDD), roughness: 0.7), at: [0, -0.03, 0], to: note)
            let thread = Part.add(cached: "glass.thread", { MeshKit.torus(major: 0.0083, minor: 0.0009, segments: 32, sides: 8) },
                                  SceneMaterials.pbr(Palette.stampRed, roughness: 0.5), at: .zero, to: note)
            _ = thread
            note.position = [0, 0.052, 0]
            axial.addChild(note)
            message = note
        }
        entity.addChild(bottle)
        entity.orientation = Part.yaw(-15)
        entity.scale = SIMD3(repeating: Self.heroScale)
    }

    static func models(in entity: Entity) -> [ModelEntity] {
        var result: [ModelEntity] = []
        if let model = entity as? ModelEntity, model.model != nil { result.append(model) }
        for child in entity.children { result += models(in: child) }
        return result
    }

    func surfaceHeight(compression c: Float) -> Float {
        // rigidSquash 0.04 (was 0.02): the ±4 % ovalisation before the failure (FOLD-REVIEW-3 N4).
        HeightCurve.brittle(c, rest: restHeight, failC: failC, failed: failed, rigidSquash: 0.04,
                            afterRatio: 0.30, minRatio: 0.09)
    }

    func update(_ state: PressVisualState) {
        if life.update(state) {
            BeatFX.glint(fx, at: [Float.random(in: -0.05...0.03, using: &beatRng), 0.061, 0.004], in: entity, count: 1,
                         golden: look.golden, rng: &beatRng)
        }
        for beat in story.advance(to: state.compression) { onBeat(beat, state: state) }
        if failed {
            twinkle(state)
            return
        }
        squash = min(squash, surfaceHeight(compression: state.compression) / restHeight)
        // Bottle local X is world-vertical after the roll: the cross-section ovalises (−4 % tall, +4 % wide) so the
        // strain shows from above before the glass gives.
        bottle.scale = SIMD3(squash, 1, 1 / squash)
        if cracked { growCracks(compression: state.compression) }
    }

    func fracture(index: Int, isFailure: Bool, state: PressVisualState) {
        switch index {
        case 0:
            // A long creak, then two crack stars on the camera side that grow as the press closes, and a glint at the
            // front star's impact (FOLD-REVIEW-8 N3: the old run lay on the top, under the ram).
            if !cracked {
                cracked = true
                crackC = state.compression
            }
            buildCracks()
            growCracks(compression: state.compression)
            life.kick(0.3)
            let impact = GlassCrack.impacts[GlassCrack.impacts.count - 1]
            let glint = GlassCrack.surface(x: impact.x, angle: impact.angle, squash: squash)
            fx.particles.burst(.glint, count: 3, at: entity.convert(position: glint.point + glint.normal * 0.002, to: fx.root),
                               speed: 0.05, colors: [UIColor(hex: 0xFFFFFF)], size: 0.003...0.005, upBias: 0.6, life: 0.25,
                               rng: &rng)
        case 1:
            shatter(state: state)
        default:
            // Crunch: the pile settles into soft sea glass (frosted faces, a duller edge), with a few small bits that
            // stay near the pile.
            for face in fragmentFaces { face.model?.materials = [seaGlass] }
            for edge in fragmentEdges { edge.model?.materials = [seaGlassEdge] }
            for streak in fragmentStreaks { streak.isEnabled = false }
            if !failed {
                for part in patchModels.flatMap({ Self.models(in: $0) }) { part.model?.materials = [seaGlass] }
            }
            fx.particles.burst(.flake, count: 10, at: [0, 0.006, 0], speed: 0.12 * max(fx.motionScale, 0.3),
                               colors: look.golden ? [Palette.gold] : [UIColor(hex: 0x5CC8B8), UIColor(hex: 0x8FE0D3)],
                               size: 0.002...0.004, spread: 0.03, upBias: 0.3, rng: &rng)
            fx.particles.burst(.glint, count: 5, at: [0, 0.01, 0], speed: 0.1, colors: [UIColor(hex: 0xFFFFFF)],
                               size: 0.002...0.004, spread: 0.03, upBias: 0.5, life: 0.3, rng: &rng)
        }
    }

    func handle(_ event: PressEvent, state: PressVisualState) {
        // Freeze the pile at seal (and at the reveal, if the press never sealed): no more skids, no more flattening,
        // so the reveal is never bigger than the last pressing frame (FOLD-REVIEW-3 N5).
        switch event {
        case .sealed, .reveal:
            freezePile()
        case .preFailureTell:
            life.tremor(0.25)
        default:
            break
        }
    }

    private func freezePile() {
        guard failed, !sealed else { return }
        sealed = true
        // The glints twinkle while the pile is pressed and are off by the reveal (FOLD-REVIEW-4 F5).
        for sparkle in sparkles { sparkle.isEnabled = false }
        var pieces: [Entity] = shards
        if let message { pieces.append(message) }
        fx.debris.freeze(pieces)
    }

    /// The pile's glints: short seeded twinkles (steady and dim under Reduce Motion) until the seal.
    private func twinkle(_ state: PressVisualState) {
        for (i, sparkle) in sparkles.enumerated() where sparkle.isEnabled {
            let k = Float(i)
            let phase = state.time * (4.3 + 1.1 * k) + k * 1.9
            let w: Float = state.reduceMotion ? 0.6 : pow(max(sin(phase), 0), 3)
            sparkle.scale = SIMD3(repeating: 0.25 + 0.95 * w)
        }
    }

    // MARK: - Cracks (fracture 0 → failure)

    /// FOLD-REVIEW-8 N3: the old run (seven 0.4 × 0.7 mm near-white boxes along the top) lay under the ram, edge-on
    /// to the P-48's eye, white on pale glass. Now two crack stars on bare body glass on the camera side
    /// (`GlassCrack.impacts`: one on the upper flank for the Duo's top-down eye, one on the front flank for the P-48's),
    /// each `GlassCrack.raysPerStar` rays of bright, dark-cored line (`lineWidth` / `coreWidth`), plus a bright impact
    /// spot with a dark centre.
    private func buildCracks() {
        guard crackLines.isEmpty else { return }
        // The old run's 15 draws, still taken from the press's stream, so the shatter's pile (frame 04) is unchanged.
        _ = Float.random(in: -0.004...0.004, using: &rng)
        for _ in 0..<7 {
            _ = Float.random(in: 0.006...0.011, using: &rng)
            _ = Float.random(in: -0.7...0.7, using: &rng)
        }
        var crackRng = SplitMix64(seed: crackSeed)
        let edgeMaterial = SceneMaterials.unlit(UIColor(hex: look.golden ? 0xFFF1C4 : GlassCrack.edgeTint))
        let coreMaterial = SceneMaterials.unlit(UIColor(hex: look.golden ? 0x6B4500 : GlassCrack.coreTint))
        let edgeMesh = MeshResource.generateBox(width: 1, height: GlassCrack.lineThickness, depth: GlassCrack.lineWidth)
        let coreMesh = MeshResource.generateBox(width: 1, height: GlassCrack.lineThickness, depth: GlassCrack.coreWidth)
        let impactEdge = MeshCache.resource("glass.crack.impact") {
            MeshKit.ellipsoid(radii: [GlassCrack.impactRadius, GlassCrack.lineThickness / 2, GlassCrack.impactRadius],
                              segments: 16, rings: 6)
        } ?? .generateSphere(radius: GlassCrack.impactRadius)
        let impactCore = MeshCache.resource("glass.crack.impactCore") {
            MeshKit.ellipsoid(radii: [GlassCrack.impactRadius * 0.5, GlassCrack.lineThickness / 2, GlassCrack.impactRadius * 0.5],
                              segments: 16, rings: 6)
        } ?? .generateSphere(radius: GlassCrack.impactRadius * 0.5)
        for impact in GlassCrack.impacts {
            for ray in GlassCrack.star(x: impact.x, angle: impact.angle, rng: &crackRng) {
                let lengths = (0..<(ray.count - 1)).map { GlassCrack.chord(ray[$0], ray[$0 + 1]) }
                let total = max(lengths.reduce(0, +), 1e-4)
                var along: Float = 0
                for i in lengths.indices {
                    defer { along += lengths[i] }
                    guard lengths[i] > GlassCrack.minSegment else { continue }
                    let edge = ModelEntity(mesh: edgeMesh, materials: [edgeMaterial])
                    let core = ModelEntity(mesh: coreMesh, materials: [coreMaterial])
                    for line in [edge, core] {
                        line.isEnabled = false
                        ShadowCasting.off(line)
                        crackRoot.addChild(line)
                    }
                    crackLines.append(CrackLine(edge: edge, core: core, start: ray[i], end: ray[i + 1],
                                                from: along / total, to: (along + lengths[i]) / total,
                                                width: GlassCrack.widthShare(along: along / total)))
                }
            }
            let edge = ModelEntity(mesh: impactEdge, materials: [edgeMaterial])
            let core = ModelEntity(mesh: impactCore, materials: [coreMaterial])
            for spot in [edge, core] {
                ShadowCasting.off(spot)
                crackRoot.addChild(spot)
            }
            crackImpacts.append((edge, core, SIMD2(impact.x, impact.angle)))
        }
        life.node.addChild(crackRoot)
    }

    /// The rays show `GlassCrack.firstShare` at the first crack and grow to their full length at the failure, on the
    /// squashed, ovalised body.
    private func growCracks(compression c: Float) {
        let grown = GlassCrack.grown(compression: c, crackC: crackC, failC: failC)
        for line in crackLines {
            let f = clamp((grown - line.from) / max(line.to - line.from, 1e-4), 0, 1)
            let on = f > 0.02
            line.edge.isEnabled = on
            line.core.isEnabled = on
            guard on else { continue }
            let a = GlassCrack.surface(x: line.start.x, angle: line.start.y, squash: squash)
            let tip = line.start + (line.end - line.start) * f
            let b = GlassCrack.surface(x: tip.x, angle: tip.y, squash: squash)
            for (model, lift) in [(line.edge, GlassCrack.lift), (line.core, GlassCrack.lift + GlassCrack.coreLift)] {
                let pose = GlassCrack.segmentPose(from: a, to: b, lift: lift)
                model.position = pose.position
                model.orientation = pose.orientation
                // A little longer than the chord (one line width), so the joints of a ray close up.
                model.scale = [pose.length + GlassCrack.lineWidth * line.width, 1, line.width]
            }
        }
        for impact in crackImpacts {
            let spot = GlassCrack.surface(x: impact.at.x, angle: impact.at.y, squash: squash)
            let up = simd_quatf(from: [0, 1, 0], to: spot.normal)
            impact.edge.position = spot.point + spot.normal * GlassCrack.lift
            impact.edge.orientation = up
            impact.core.position = spot.point + spot.normal * (GlassCrack.lift + GlassCrack.coreLift)
            impact.core.orientation = up
        }
    }

    // MARK: - Failure

    /// The big one: the label tears away, small thin shards drop flat, skid a little and stay on the plate.
    private func shatter(state: PressVisualState) {
        failed = true
        // No dust disc under the pile any more (FOLD-REVIEW-5 N5: the pale translucent "ghost" disc in the centre was
        // the first thing you saw); the crunch's flakes and the shards themselves carry the "powdered" read.
        // The label tears: the band goes, the flat scraps on top of the pile appear.
        labelBand.isEnabled = false
        for scrap in labelScraps { scrap.isEnabled = true }
        crackRoot.removeFromParent()
        crackLines.removeAll()
        crackImpacts.removeAll()
        let m = fx.motionScale
        // Each curved patch is swapped for its flat fragment pair (drawn in the shard's local XZ plane, so a yaw-only
        // orientation lays it flat), dropped in a heap (FOLD-REVIEW-6 N10: the uniform √U disc, plus a skid that was the
        // same for every piece, left a ring round a hole): a tighter disc weighted to the middle (`pileRadius`), the
        // middle pieces lifted 2–3 deep and tilted so they overlap and catch the light (`heapLift`, `heapTilt`), and
        // only the outer pieces skid (0.04–0.10 m/s × `skidShare`, outward, no up component); every centre is boxed so
        // all of it stays on the strike plate + 16 pt.
        let centre0 = entity.convert(position: [0, 0, 0], to: fx.debris.root)
        // World size of one bottle-local metre (the hero scale, times any slot scale), so fragments keep their size.
        let pieceScale = max(entity.scale(relativeTo: fx.debris.root).x, 0.01)
        for (i, shard) in shards.enumerated() {
            if i < intact.count && intact[i] {
                // The base ring and the neck stay whole: curved bottle glass on the heap (FOLD-REVIEW-7 #5). Their mesh
                // goes back into the bottle's lathe axes, so the base stands as a ring and the neck lies on its side.
                if i < patchModels.count, i < latheAxes.count { patchModels[i].orientation = latheAxes[i] }
                shard.setParent(fx.debris.root)
                let neck = i < intactNeck.count && intactNeck[i]
                let spot = GlassDebris.intactSpot(neck: neck, footprint: footprint, containment: containment)
                let yaw = Part.yaw(Float.random(in: -30...30, using: &rng))
                shard.orientation = neck ? yaw * simd_quatf(angle: -.pi / 2, axis: [0, 0, 1]) : yaw
                shard.scale = SIMD3(repeating: pieceScale)
                shard.position = SIMD3(centre0.x + spot.x, 0.004, centre0.z + spot.y)
                let size = shard.visualBounds(relativeTo: fx.debris.root).extents
                let half = SIMD2<Float>(repeating: simd_length(SIMD2(size.x, size.z)) / 2)
                let a = Float.random(in: 0...(2 * .pi), using: &rng)
                let v = SIMD3<Float>(cos(a), 0, sin(a)) * GlassDebris.skidSpeed.lowerBound * 0.5 * m
                fx.debris.adopt(shard, velocity: v, spin: .zero, bounciness: 0.1, friction: 0.9, maxSpread: 1,
                                bounds: GlassDebris.centreBounds(containment: containment, pieceHalf: half))
                continue
            }
            if i < patchModels.count { patchModels[i].removeFromParent() }
            if i < fragments.count { fragments[i].isEnabled = true }
            shard.setParent(fx.debris.root)
            let a = Float.random(in: 0...(2 * .pi), using: &rng)
            // The big single pieces land in the middle of the heap (FOLD-REVIEW-7 #5: a few 20 mm pieces in the centre).
            let single = i < singles.count && singles[i]
            let u = Float.random(in: 0...(single ? GlassDebris.singleInner : 1), using: &rng)
            let rho = GlassDebris.pileRadius(u: u)
            let spot = GlassDebris.pilePoint(angle: a, u: u, footprint: footprint, containment: containment)
            let dir = SIMD3<Float>(cos(a), 0, sin(a))
            if i < poses.count {
                let lift = GlassDebris.heapLift(rho: rho, jitter: Float.random(in: 0...1, using: &rng))
                // One piece in five is propped up on the others, so it catches the light at its own angle.
                let propped = Float.random(in: 0...1, using: &rng) < GlassDebris.proppedShare
                let tilt = propped ? Float.random(in: GlassDebris.proppedTilt, using: &rng)
                    : GlassDebris.heapTilt(rho: rho, jitter: Float.random(in: 0...1, using: &rng))
                let axis = Float.random(in: 0...(2 * .pi), using: &rng)
                poses[i].position = [0, lift, 0]
                poses[i].orientation = simd_quatf(angle: tilt, axis: SIMD3(cos(axis), 0, sin(axis)))
            }
            shard.orientation = simd_quatf(angle: Float.random(in: 0...(2 * .pi), using: &rng), axis: [0, 1, 0])
            shard.scale = SIMD3(repeating: pieceScale)
            shard.position = SIMD3(centre0.x + spot.x, 0.003, centre0.z + spot.y)
            let size = shard.visualBounds(relativeTo: fx.debris.root).extents
            // Circumscribed half size, so a little yaw while it skids can't swing a corner off the plate.
            let half = SIMD2<Float>(repeating: simd_length(SIMD2(size.x, size.z)) / 2)
            let v = dir * Float.random(in: GlassDebris.skidSpeed, using: &rng) * GlassDebris.skidShare(rho: rho) * m
            fx.debris.adopt(shard, velocity: v, spin: SIMD3(0, Float.random(in: -2...2, using: &rng) * m, 0),
                            bounciness: 0.1, friction: 0.8, maxSpread: 1,
                            bounds: GlassDebris.centreBounds(containment: containment, pieceHalf: half))
        }
        for sparkle in sparkles { sparkle.isEnabled = true }
        let centre = entity.convert(position: [0, 0.03, 0], to: fx.root)
        fx.particles.burst(.glint, count: 14, at: centre, speed: 0.6 * max(m, 0.3), colors: [UIColor(hex: 0xFFFFFF), UIColor(hex: 0xD8FFF8)],
                           size: 0.003...0.006, spread: 0.03, upBias: 0.2, life: 0.35, rng: &rng)
        fx.particles.burst(.flake, count: 8, at: centre, speed: 0.25 * max(m, 0.3),
                           colors: look.golden ? [Palette.gold] : [UIColor(hex: 0x8FE0D3)], size: 0.002...0.004,
                           spread: 0.03, upBias: 0.3, rng: &rng)
        if let message {
            fx.particles.burst(.confetti, count: 24, at: centre + SIMD3(0, 0.01, 0), speed: 0.7 * max(m, 0.3),
                               colors: Palette.rainbow, size: 0.004...0.006, spread: 0.02, upBias: 0.5, rng: &rng)
            let size = message.visualBounds(relativeTo: fx.root).extents
            let half = SIMD2<Float>(repeating: simd_length(SIMD2(size.x, size.z)) / 2)
            fx.debris.adopt(message, velocity: SIMD3(0, 0.2, 0.05) * m, spin: Burst.spin(4 * m, rng: &rng), bounciness: 0.2,
                            bounds: GlassDebris.centreBounds(containment: containment, pieceHalf: half))
        }
    }
}

/// The intact bottle's stress glow (OBJECT-STORYBOARDS §9): the glass whitens a step at each `.glow` / `.strain` /
/// `.tell` beat before it gives. Pure, so SquishTests can pin it.
enum GlassStress {
    static let steps = 5
    static let glowTint: UInt32 = 0xB8FFF4
    static func glow(level: Int) -> Float {
        0.06 * Float(clamp(level, 0, steps))
    }
}

/// The crack stars between fracture 0 and the failure (FOLD-REVIEW-8 N3), pinned in SquishTests/SceneTests.swift.
/// Body coordinates: entity x along the bottle (base −0.070 … neck +0.070, before the hero scale) and the angle round
/// the body from the top (0) toward the camera (+z, π/2); the cross-section is ovalised by the view's `squash`.
enum GlassCrack {
    /// The straight body's cross-section: its centre line's height and its radius (entity metres).
    static let centreY: Float = 0.030
    static let bodyRadius: Float = 0.030
    /// Bare body glass between the base's heel (full radius from x ≈ −0.060) and the label band (from x ≥ −0.035):
    /// the rays stay here, so no crack runs over the paper.
    static let axialRange: ClosedRange<Float> = -0.057 ... -0.037
    /// The impacts: one on the upper flank (35°; the Duo's top-down eye, ~47° up, sees it face-on) and one on the front
    /// flank (81°; the P-48's eye, ~21° up, sees it face-on under the ram, which hides the top).
    static let impacts: [(x: Float, angle: Float)] = [(-0.0475, 0.62), (-0.0465, 1.42)]
    static let raysPerStar = 6
    static let segmentsPerRay = 4
    /// Full ray length (along the surface) at the failure, and how much of a step goes along the bottle (the bare
    /// glass is only ~20 mm long, so the stars run mostly round it).
    static let rayLength: ClosedRange<Float> = 0.016...0.024
    static let axialShare: Float = 0.55
    /// Each step's heading wanders by up to this (radians), so the rays are jagged, not ruled.
    static let wander: Float = 0.3
    /// The line: a bright edge `lineWidth` wide (≈ 1.4 mm on the plate at the hero scale) with a dark core inside it,
    /// so it reads on pale glass (the core) and on steel or the dark label (the edge); tapering to `tipTaper` at the tip.
    static let lineWidth: Float = 0.0018
    static let coreWidth: Float = 0.0008
    static let tipTaper: Float = 0.6
    static let lineThickness: Float = 0.0003
    /// The bright line's centre above the glass, and the core's further lift (its top face stands clear of the edge's).
    static let lift: Float = 0.0004
    static let coreLift: Float = 0.00012
    static let impactRadius: Float = 0.0024
    static let edgeTint: UInt32 = 0xF4FFFC
    static let coreTint: UInt32 = 0x123C37
    /// Segments shorter than this (a ray pinned at the label's edge) are not drawn.
    static let minSegment: Float = 0.0003
    /// The share of every ray showing at the first crack; it grows linearly to all of it at the failure.
    static let firstShare: Float = 0.3

    static func grown(compression c: Float, crackC: Float, failC: Float) -> Float {
        let p = clamp((c - crackC) / max(failC - crackC, 0.02), 0, 1)
        return firstShare + (1 - firstShare) * p
    }

    /// The width share of a segment starting `along` (0…1) its ray: full at the impact, `tipTaper` at the tip.
    static func widthShare(along: Float) -> Float {
        1 - (1 - tipTaper) * clamp(along, 0, 1)
    }

    /// The body's surface at entity `x` and `angle`, and its outward normal, with the cross-section squashed to
    /// `squash` of its height and widened by 1/squash (as the view scales the bottle).
    static func surface(x: Float, angle: Float, squash: Float) -> (point: SIMD3<Float>, normal: SIMD3<Float>) {
        let s = max(squash, 0.05)
        let point = SIMD3<Float>(x, centreY + bodyRadius * cos(angle) * s, bodyRadius * sin(angle) / s)
        let normal = simd_normalize(SIMD3<Float>(0, cos(angle) / s, sin(angle) * s))
        return (point, normal)
    }

    /// The straight distance between two body points (unsquashed).
    static func chord(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        simd_distance(surface(x: a.x, angle: a.y, squash: 1).point, surface(x: b.x, angle: b.y, squash: 1).point)
    }

    /// One star's rays from the impact at (`x`, `angle`): `raysPerStar` seeded polylines of `segmentsPerRay + 1`
    /// body points (x, angle), spread round the impact, every point on the bare glass (`axialRange`).
    static func star(x: Float, angle: Float, rng: inout SplitMix64) -> [[SIMD2<Float>]] {
        let phase = Float.random(in: 0...(2 * .pi), using: &rng)
        var rays: [[SIMD2<Float>]] = []
        for k in 0..<raysPerStar {
            var heading = phase + 2 * .pi * Float(k) / Float(raysPerStar) + Float.random(in: -0.35...0.35, using: &rng)
            let step = Float.random(in: rayLength, using: &rng) / Float(segmentsPerRay)
            var u = x
            var v: Float = 0
            var ray = [SIMD2<Float>(x, angle)]
            for _ in 0..<segmentsPerRay {
                heading += Float.random(in: -wander...wander, using: &rng)
                u = clamp(u + step * cos(heading) * axialShare, axialRange.lowerBound, axialRange.upperBound)
                v += step * sin(heading)
                ray.append(SIMD2(u, angle + v / bodyRadius))
            }
            rays.append(ray)
        }
        return rays
    }

    /// A line between body points `a` and `b` (surface point and normal), `lift` out from the glass: its centre (the
    /// chord's middle, pushed out by the arc's sag so it never sinks in), its rotation (local x along the chord, local
    /// y out of the glass) and its length.
    static func segmentPose(from a: (point: SIMD3<Float>, normal: SIMD3<Float>),
                            to b: (point: SIMD3<Float>, normal: SIMD3<Float>),
                            lift: Float) -> (position: SIMD3<Float>, orientation: simd_quatf, length: Float) {
        let p0 = a.point + a.normal * lift, p1 = b.point + b.normal * lift
        let sum = a.normal + b.normal
        let n = simd_length(sum) > 1e-5 ? simd_normalize(sum) : SIMD3<Float>(0, 1, 0)
        let d = p1 - p0
        let length = simd_length(d)
        guard length > 1e-6 else { return ((p0 + p1) / 2, simd_quatf(from: [0, 1, 0], to: n), 0) }
        let dir = d / length
        let off = n - simd_dot(n, dir) * dir
        let up = simd_length(off) > 1e-5 ? simd_normalize(off) : SIMD3<Float>(0, 1, 0)
        let side = simd_cross(dir, up)
        let sag = length * length / (8 * bodyRadius)
        return ((p0 + p1) / 2 + up * sag, simd_quatf(simd_float3x3(columns: (dir, up, side))), length)
    }
}

/// Pure glass-debris numbers (FOLD-REVIEW-3 N5), pinned in SquishTests/SceneTests.swift.
enum GlassDebris {
    /// Shards per profile band (base, low body, label low, label high, shoulder, neck). FOLD-REVIEW-7 #5: ~100 same-size
    /// 3–9 mm pieces ([1, 10, 14, 14, 8, 4]) read as mint confetti; now fewer, larger pieces (45–60° arcs on the body,
    /// most split in two, a third kept as one big piece) plus the base ring and the neck kept whole.
    static let sectorCounts = [1, 6, 8, 8, 5, 1]
    /// Bands whose single patch stays whole at the shatter: the base ring and the neck.
    static let intactBands = [0, 5]
    /// One body patch in `singleShare` stays one big piece (≈ 0.9 of its patch) instead of a split pair.
    static let singleShare: UInt64 = 3
    static let singleFill: Float = 0.9
    static let singleVariants = 6
    /// Seeded size spread per patch (× the patch's own size): pairs a little smaller, singles a little bigger, so the
    /// pieces vary ~3× in area (FOLD-REVIEW-7 N8).
    static let pairScale: ClosedRange<Float> = 0.75...1.0
    static let singleScale: ClosedRange<Float> = 1.0...1.08
    /// The big pieces land in this inner share (`u`) of the heap.
    static let singleInner: Float = 0.45
    /// One piece in five is propped up on the others at a steeper angle (FOLD-REVIEW-7 N8: tilt ~20 % off the plate).
    static let proppedShare: Float = 0.2
    static let proppedTilt: ClosedRange<Float> = 0.42...0.6
    /// The specular streak across each piece's face: a thin bright chord, so the faces read as glass, not paper.
    static let streakOpacity: Float = 0.5
    static let streakWidth: Float = 0.055
    /// How far past the strike plate the pile may reach, in canvas points.
    static let platePadding: Double = 16
    /// Skid speed range (m/s) once a shard lies flat; there is no up component.
    static let skidSpeed: ClosedRange<Float> = 0.04...0.10

    // MARK: The pile (FOLD-REVIEW-4 F5)

    /// The pile's radius in footprints along the plate's x (FOLD-REVIEW-6 N10: 1.1 spread ~100 pieces so thin they read
    /// as confetti), and its depth (z) as a share of that.
    static let pileFill: Float = 0.82
    static let pileAspect: Float = 0.85
    /// Drop radius = `u^pileExponent` of the pile's (√u is uniform; 0.85 puts ~29 % of the pieces in the inner 0.35,
    /// where a uniform disc puts 12 %): a heap, densest in the middle.
    static let pileExponent: Float = 0.85
    /// Share of the containment box the drop points may use, leaving room for the skid.
    static let pileRoom: Float = 0.8
    /// The heap: a piece in the very middle is lifted up to this (bottle-local metres; the debris body rests on its
    /// symmetric bounds, so it renders ≈ 2× higher: ~3.2 mm on the plate, 2–3 pieces deep) and tilted up to `heapTilt`.
    static let heapHeight: Float = 0.0021
    static let heapMaxTilt: Float = 0.38
    /// Glints on the pile (was one static dot on every third shard, ~17; 4 until round 6).
    static let sparkleCount = 6

    /// The drop radius (0…1 of the pile's) for a uniform `u`.
    static func pileRadius(u: Float) -> Float {
        pow(clamp(u, 0, 1), pileExponent)
    }

    /// How high a piece dropped at pile radius `rho` (0…1) is lifted: highest in the middle, flat at the edge.
    static func heapLift(rho: Float, jitter: Float) -> Float {
        let inner = 1 - clamp(rho, 0, 1)
        return heapHeight * inner * inner.squareRoot() * (0.35 + 0.65 * clamp(jitter, 0, 1))
    }

    /// How far (radians) a piece at pile radius `rho` leans on the pieces under it: steepest in the middle.
    static func heapTilt(rho: Float, jitter: Float) -> Float {
        let inner = 1 - clamp(rho, 0, 1)
        return heapMaxTilt * (0.12 + 0.88 * inner) * (0.3 + 0.7 * clamp(jitter, 0, 1))
    }

    /// The share of the skid a piece at pile radius `rho` gets: the middle of the heap stays put, the edge skids.
    static func skidShare(rho: Float) -> Float {
        0.2 + 0.8 * clamp(rho, 0, 1)
    }
    /// Label scraps on top of the pile, so it keeps the bottle's raspberry/cream identity.
    static let labelScraps = (pink: 6, cream: 4)
    /// A scrap is ~1 fragment piece: ×1.4 of round 4's 0.7 (FOLD-REVIEW-5 N5), so the pink/cream reads at thumbnail.
    static let scrapScale: Float = 0.98
    /// Bottle glass, darker than the steel (FOLD-REVIEW-5 N5): #5CC8B8 taken ~45 % toward a deep #2F8F82 (round 4 took
    /// it 20 % *lighter*, toward #8FE0D3, and at 0.5 it read as pale paper on a L 235 plate).
    static let shardTint: UInt32 = 0x47AEA0
    /// A deeper bottle green for about half the pieces (one flat tint read as a sheet of confetti, FOLD-REVIEW-7 N8).
    static let shardTintDeep: UInt32 = 0x35948A
    static let shardOpacity: Float = 0.7
    /// The crunched "sea glass": frosted, a touch lighter than the clear shards, never paper-pale.
    static let seaGlassTint: UInt32 = 0x5BB3A6
    static let seaGlassOpacity: Float = 0.74
    /// The dark refraction hairline round each shard (outside the bright bevel).
    static let outlineTint: UInt32 = 0x1F5C54
    /// Edge bands of a fragment pair, in its unit square: the bright bevel and, outside it, the dark hairline.
    static let rimInset: Float = 0.035
    static let outlineInset: Float = 0.03
    /// Fragment slab thickness (bottle-local metres; ≈ 0.9 mm on the plate) and the per-shard height step that keeps
    /// overlapping pieces from z-fighting.
    /// 3D-art round: real bottle glass is 2–3 mm thick, so the pile is a chunky heap whose dark-green edges show their
    /// thickness from the front (was 1.2 mm, a sheet of confetti from the P-48's eye).
    static let fragmentThickness: Float = 0.0024
    static let layerStep: Float = 0.00015
    /// Edge chipping: each edge of a piece gets small conchoidal bites out of it (up to this share of the piece's size).
    static let chipDepth: ClosedRange<Float> = 0.015...0.05
    static let fragmentVariants = 8
    static let scrapVariants = 4

    /// Where shard `u` (0…1) at `angle` lands, relative to the bottle's centre: over an ellipse of `pileFill · footprint`
    /// (× `pileAspect` in z), weighted to the middle (`pileRadius`), shrunk to fit `pileRoom` of the containment box.
    static func pilePoint(angle: Float, u: Float, footprint: Float, containment: SIMD2<Float>) -> SIMD2<Float> {
        let half = simd_min(SIMD2<Float>(footprint * pileFill, footprint * pileFill * pileAspect), containment * pileRoom)
        let r = pileRadius(u: u)
        return SIMD2(cos(angle) * half.x, sin(angle) * half.y) * r
    }

    /// The fragment's (long, short) size (bottle-local metres) for a lathe patch `width` round × `height` along the
    /// profile (FOLD-REVIEW-7 #5: up to 30 × 24 mm, was 22 × 14): a pair's pieces are then ≈ 4–15 mm on the plate, a
    /// single piece up to ≈ 21 mm.
    static func fragmentSize(width: Float, height: Float) -> SIMD2<Float> {
        let long = clamp(max(width, height) * 0.92, 0.012, 0.030)
        let short = clamp(min(width, height) * 0.92, 0.008, 0.024)
        return SIMD2(long, min(short, long))
    }

    /// The size of one piece of a fragment pair of `size` (the pair splits along its long side).
    static func pieceSize(_ size: SIMD2<Float>) -> SIMD2<Float> {
        SIMD2(size.x * 0.42, size.y * 0.84)
    }

    /// The size of a single (unsplit) piece of `size`.
    static func singlePieceSize(_ size: SIMD2<Float>) -> SIMD2<Float> {
        size * singleFill
    }

    /// A label scrap lies on one piece: a pair's piece, or half a single piece.
    static func scrapPiece(_ size: SIMD2<Float>, single: Bool) -> SIMD2<Float> {
        single ? singlePieceSize(size) * SIMD2(0.5, 0.6) : pieceSize(size)
    }

    /// Where an intact piece lands, relative to the bottle's centre: the neck at the heap's +x side (where it was),
    /// the base ring at its −x side, both inside the pile.
    static func intactSpot(neck: Bool, footprint: Float, containment: SIMD2<Float>) -> SIMD2<Float> {
        let half = simd_min(SIMD2<Float>(footprint * pileFill, footprint * pileFill * pileAspect), containment * pileRoom)
        return neck ? SIMD2(half.x * 0.6, -half.y * 0.2) : SIMD2(-half.x * 0.7, half.y * 0.25)
    }

    static func layerHeight(_ index: Int) -> Float {
        Float(index % 5) * layerStep
    }

    static func fragmentSeed(_ variant: Int) -> UInt64 { 0x6A55_F7A6 &+ UInt64(variant) &* 0x9E37 }
    static func singleSeed(_ variant: Int) -> UInt64 { 0x6A55_5146 &+ UInt64(variant) &* 0x7F4B }
    static func scrapSeed(_ variant: Int) -> UInt64 { 0x5C7A_9000 &+ UInt64(variant) &* 0x51ED }

    /// An irregular convex polygon of 4–6 sides round an ellipse of half size `radii` at `centre`: corners jittered in
    /// angle and radius, then hulled; if the hull lost a corner below 4, the regular (unjittered) polygon is used.
    static func shardPolygon(sides: Int, radii: SIMD2<Float>, centre: SIMD2<Float> = .zero,
                             rng: inout SplitMix64) -> [SIMD2<Float>] {
        let n = min(max(sides, 4), 6)
        let phase = Float.random(in: 0...(2 * .pi), using: &rng)
        let step = 2 * Float.pi / Float(n)
        var points: [SIMD2<Float>] = []
        for k in 0..<n {
            let a = phase + step * (Float(k) + Float.random(in: -0.3...0.3, using: &rng))
            let r = Float.random(in: 0.78...1.0, using: &rng)
            points.append(centre + SIMD2(cos(a) * radii.x, sin(a) * radii.y) * r)
        }
        let hull = MeshKit.convexHull(points)
        if hull.count >= 4 { return hull }
        return (0..<n).map { k in
            let a = phase + step * Float(k)
            return centre + SIMD2(cos(a) * radii.x, sin(a) * radii.y)
        }
    }

    /// Two irregular flat pieces side by side in the unit square (x −0.5…0.5, z −0.5…0.5), split along x with a
    /// visible crack between them, `fragmentThickness` tall. Slot 0 glass faces, slot 1 the bright bevel, slot 2 the
    /// dark outer hairline and the walls, slot 3 the specular streak across each face.
    static func fragmentPair(seed: UInt64) -> MeshData {
        var rng = SplitMix64(seed: seed)
        var mesh = MeshData()
        for side: Float in [-1, 1] {
            let sides = 4 + Int(rng.next() % 3)
            let centre = SIMD2<Float>(side * 0.25 + Float.random(in: -0.015...0.015, using: &rng),
                                      Float.random(in: -0.04...0.04, using: &rng))
            let radii = SIMD2<Float>(Float.random(in: 0.18...0.21, using: &rng), Float.random(in: 0.38...0.46, using: &rng))
            let polygon = shardPolygon(sides: sides, radii: radii, centre: centre, rng: &rng)
            mesh.append(MeshKit.polygonSlab(chipped(polygon, rng: &rng), thickness: fragmentThickness, rimInset: rimInset,
                                            outlineInset: outlineInset))
            mesh.append(streak(polygon, rng: &rng), materialOffset: 3)
        }
        return mesh
    }

    /// The outline with chipped edges: every edge is split into 3–4 runs, and some of the new points are bitten inward
    /// (a conchoidal chip), so the bevel and the dark hairline follow a broken edge, not a ruled one. Only ever inside
    /// the convex outline, so the piece stays star-shaped about its centre (and inside its unit square).
    static func chipped(_ polygon: [SIMD2<Float>], rng: inout SplitMix64) -> [SIMD2<Float>] {
        let count = polygon.count
        guard count >= 3 else { return polygon }
        let centre = polygon.reduce(SIMD2<Float>.zero, +) / Float(count)
        var size: Float = 0
        for p in polygon { size = max(size, simd_length(p - centre)) }
        var out: [SIMD2<Float>] = []
        for i in 0..<count {
            let a = polygon[i], b = polygon[(i + 1) % count]
            out.append(a)
            let runs = 3 + Int(rng.next() % 2)
            for k in 1..<runs {
                let t = (Float(k) + Float.random(in: -0.25...0.25, using: &rng)) / Float(runs)
                var p = a + (b - a) * t
                if rng.next() % 3 != 0 {
                    let toCentre = centre - p
                    let d = simd_length(toCentre)
                    if d > 1e-5 { p += toCentre / d * min(size * Float.random(in: chipDepth, using: &rng), d * 0.3) }
                }
                out.append(p)
            }
        }
        return out
    }

    /// One big irregular piece filling ~0.9 of the unit square (FOLD-REVIEW-7 #5), slots as `fragmentPair`.
    static func fragmentSingle(seed: UInt64) -> MeshData {
        var rng = SplitMix64(seed: seed)
        let sides = 5 + Int(rng.next() % 2)
        let centre = SIMD2<Float>(Float.random(in: -0.02...0.02, using: &rng), Float.random(in: -0.02...0.02, using: &rng))
        let radii = SIMD2<Float>(Float.random(in: 0.42...0.47, using: &rng), Float.random(in: 0.42...0.47, using: &rng))
        let polygon = shardPolygon(sides: sides, radii: radii, centre: centre, rng: &rng)
        var mesh = MeshKit.polygonSlab(chipped(polygon, rng: &rng), thickness: fragmentThickness, rimInset: rimInset * 0.8,
                                       outlineInset: outlineInset * 0.8)
        mesh.append(streak(polygon, rng: &rng), materialOffset: 3)
        return mesh
    }

    /// A thin bright chord across a convex (counter-clockwise) polygon's top face, a hair above it: the reflection
    /// streak of a flat piece of glass. One slot (0); its ends stop short of the edges.
    static func streak(_ polygon: [SIMD2<Float>], rng: inout SplitMix64) -> MeshData {
        var mesh = MeshData()
        let count = polygon.count
        guard count >= 3 else { return mesh }
        let centre = polygon.reduce(SIMD2<Float>.zero, +) / Float(count)
        let tilt = Float.random(in: 0.5...1.1, using: &rng)
        let phi: Float = rng.next() % 2 == 0 ? tilt : -tilt
        let dir = SIMD2<Float>(cos(phi), sin(phi))
        let across = SIMD2<Float>(-dir.y, dir.x)
        var extent: Float = 0
        for p in polygon { extent = max(extent, simd_length(p - centre)) }
        let origin = centre + across * Float.random(in: -0.3...0.3, using: &rng) * extent
        let w = streakWidth * 0.5
        // Clip both long edges of the band (origin ± w·across + t·dir) to the polygon (Cyrus–Beck) and keep the range
        // both share, so all four corners are inside the (convex) shard.
        var t0 = -Float.infinity, t1 = Float.infinity
        for side: Float in [-1, 1] {
            let line = origin + across * (w * side)
            for i in 0..<count {
                let a = polygon[i], b = polygon[(i + 1) % count]
                let e = b - a
                let n = SIMD2<Float>(e.y, -e.x)   // outward for counter-clockwise
                let num = -simd_dot(n, line - a)
                let den = simd_dot(n, dir)
                if abs(den) < 1e-9 {
                    if num < 0 { return mesh }
                    continue
                }
                let t = num / den
                if den > 0 { t1 = min(t1, t) } else { t0 = max(t0, t) }
            }
        }
        guard t1 - t0 > 1e-3 else { return mesh }
        let inset = (t1 - t0) * 0.18
        let p0 = origin + dir * (t0 + inset), p1 = origin + dir * (t1 - inset)
        let y = fragmentThickness / 2 + 0.00004
        let up = SIMD3<Float>(0, 1, 0)
        let corners = [p0 - across * w, p1 - across * w, p1 + across * w, p0 + across * w]
        let v = corners.map { mesh.addVertex(SIMD3($0.x, y, $0.y), up) }
        mesh.addTriangle(v[0], v[1], v[2])
        mesh.addTriangle(v[0], v[2], v[3])
        mesh.orientToNormals()
        return mesh
    }

    /// One material slot of a fragment pair (empty if it has none).
    static func fragmentSlot(_ mesh: MeshData, slot: Int) -> MeshData {
        mesh.splitByMaterial().first { $0.slot == slot }?.mesh ?? MeshData()
    }

    /// A flat paper scrap: one irregular 4–6-gon in the unit square, 0.4 mm thick, one slot.
    static func scrap(seed: UInt64) -> MeshData {
        var rng = SplitMix64(seed: seed)
        let sides = 4 + Int(rng.next() % 3)
        let polygon = shardPolygon(sides: sides, radii: SIMD2(0.45, 0.45), rng: &rng)
        return MeshKit.polygonSlab(polygon, thickness: 0.0004)
    }

    /// Half extents (x, z), fx metres, of the Fold Press strike plate + `padding` points for an object of `restHeight`
    /// (the anvil's fold scale, as `FoldPressController` sets it), never wider than `anvilHalf`.
    static func containment(restHeight: Float, anvilHalf: SIMD2<Float>,
                            padding: Double = GlassDebris.platePadding) -> SIMD2<Float> {
        let foldScale = FoldMetrics.foldScale(restHeight: Double(restHeight))
        let metresPerPoint = FoldMetrics.metresPerMM(foldScale: foldScale) / FoldMetrics.pointsPerMM
        let plate = SIMD2<Float>(Float((FoldMetrics.plateLateral / 2 + padding) * metresPerPoint),
                                 Float((FoldMetrics.plateDepth / 2 + padding) * metresPerPoint))
        return simd_min(plate, anvilHalf)
    }

    /// The box a piece's centre may occupy so all of it (horizontal half size `pieceHalf`) stays inside `containment`.
    static func centreBounds(containment: SIMD2<Float>, pieceHalf: SIMD2<Float>) -> (min: SIMD2<Float>, max: SIMD2<Float>) {
        let room = simd_max(containment - pieceHalf, SIMD2<Float>(repeating: 0))
        return (-room, room)
    }
}
