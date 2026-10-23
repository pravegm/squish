import Foundation
import RealityKit
import simd
import UIKit

/// Glass Bottle (bible §4 #9, VISUAL-TARGET §5.9): a sea-glass bottle lying on its side, neck camera-right,
/// pre-fractured into ~50 small thin shards (2.2 mm lathe patches, ≤ 26° arcs) under one intact paper label band.
/// Silent rigidity until fracture 0 (~0.22), apart from a slight ovalisation; then bright crack lines that lengthen
/// toward the failure. Fracture 1 (failure, ~0.40) is the biggest event in the app: the label tears away and each
/// curved patch breaks into two flat, irregular convex shards of bottle glass, darker than the steel, with a dark
/// hairline and a bright bevel on every edge (FOLD-REVIEW-4 F5, FOLD-REVIEW-5 N5: ~100 pieces, 3–9 mm) that heap up
/// in the middle of the plate (FOLD-REVIEW-6 N10; no pale dust disc under them), skid a little (fade-and-slump under
/// Reduce Motion) and stay on the
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
    /// The fragments' glass faces and bright edges (the crunch swaps both to frosted sea glass).
    private var fragmentFaces: [ModelEntity] = []
    private var fragmentEdges: [ModelEntity] = []
    /// Six glints on the pile that twinkle from the shatter until the seal (FOLD-REVIEW-4 F5: was a static white dot
    /// on every third shard).
    private var sparkles: [Entity] = []
    /// The intact paper label (one band, not split into shards); it tears away at the shatter.
    private let labelBand = Entity()
    /// Flat label scraps lying on top of shards, shown once the label has torn (FOLD-REVIEW-4 F5: 6 raspberry, 4 cream).
    private var labelScraps: [Entity] = []
    private var cracks: [Crack] = []
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

    /// One crack segment on top of the bottle; segments appear in order and lengthen with compression.
    private struct Crack {
        let model: ModelEntity
        /// Entity-local start (x, z); y follows the squashed surface.
        let start: SIMD2<Float>
        let angle: Float
        let length: Float
        /// The part of the whole run (0…1) this segment covers.
        let from: Float
        let to: Float
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
        build(variant: variant)
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
        let fragmentFace = look.golden ? SceneMaterials.gold
            : SceneMaterials.enamel(UIColor(hex: GlassDebris.shardTint), roughness: 0.04, clearcoat: 1, clearcoatRoughness: 0.02,
                                    specular: 1, opacity: GlassDebris.shardOpacity)
        let fragmentEdge: any Material
        let fragmentOutline: any Material
        if look.golden {
            fragmentEdge = SceneMaterials.gold
            fragmentOutline = SceneMaterials.pbr(UIColor(hex: 0x8A5A00), roughness: 0.3, metallic: 1)
        } else {
            fragmentEdge = SceneMaterials.unlit(UIColor(hex: 0xF2FFFC), opacity: 0.95)
            fragmentOutline = SceneMaterials.unlit(UIColor(hex: GlassDebris.outlineTint), opacity: 0.9)
        }
        var fragmentResources: [(face: MeshResource?, edge: MeshResource?, outline: MeshResource?)] = []
        for v in 0..<GlassDebris.fragmentVariants {
            let seed = GlassDebris.fragmentSeed(v)
            let face = MeshCache.resource("glass.frag.\(v).0") { GlassDebris.fragmentSlot(GlassDebris.fragmentPair(seed: seed), slot: 0) }
            let edge = MeshCache.resource("glass.frag.\(v).1") { GlassDebris.fragmentSlot(GlassDebris.fragmentPair(seed: seed), slot: 1) }
            let outline = MeshCache.resource("glass.frag.\(v).2") { GlassDebris.fragmentSlot(GlassDebris.fragmentPair(seed: seed), slot: 2) }
            fragmentResources.append((face, edge, outline))
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

                // The fragment pair (hidden until the shatter), sized to the patch, split along its long side, and
                // stacked a hair apart in height so overlapping pieces never z-fight.
                let width = profile[mid].x * (cuts[k + 1] - cuts[k])
                let size = GlassDebris.fragmentSize(width: width, height: along)
                let layer = GlassDebris.layerHeight(shards.count)
                let pose = Entity()
                shard.addChild(pose)
                poses.append(pose)
                let fragment = Entity()
                let variant = Int(rng.next() % UInt64(GlassDebris.fragmentVariants))
                let resources = fragmentResources[variant]
                if let face = resources.face {
                    let model = ModelEntity(mesh: face, materials: [fragmentFace])
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
                    let piece = GlassDebris.pieceSize(size)
                    let scrap = ModelEntity(mesh: scrapResources[Int(rng.next() % UInt64(scrapResources.count))],
                                            materials: [entry.material])
                    let side: Float = rng.next() % 2 == 0 ? -1 : 1
                    scrap.scale = SIMD3(piece.x * GlassDebris.scrapScale, 1, piece.y * GlassDebris.scrapScale)
                    scrap.position = [side * size.x * 0.25, layers[i] + GlassDebris.fragmentThickness / 2 + 0.00035, 0]
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
            // A long creak, then bright crack lines on top that lengthen as the press closes, and a glint.
            cracked = true
            crackC = state.compression
            buildCracks()
            growCracks(compression: state.compression)
            fx.particles.burst(.glint, count: 3, at: entity.convert(position: [0, Self.localHeight, 0], to: fx.root), speed: 0.05,
                               colors: [UIColor(hex: 0xFFFFFF)], size: 0.003...0.005, upBias: 0.6, life: 0.25, rng: &rng)
        case 1:
            shatter(state: state)
        default:
            // Crunch: the pile settles into soft sea glass (frosted faces, a duller edge), with a few small bits that
            // stay near the pile.
            for face in fragmentFaces { face.model?.materials = [seaGlass] }
            for edge in fragmentEdges { edge.model?.materials = [seaGlassEdge] }
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

    private func buildCracks() {
        let white = SceneMaterials.unlit(UIColor(hex: 0xF4FFFC), opacity: 0.85)
        // A run along the top of the straight body (entity x −0.050 … ≈ +0.004, where the radius is 0.030).
        var x: Float = -0.050
        var z: Float = Float.random(in: -0.004...0.004, using: &rng)
        var segments: [(start: SIMD2<Float>, angle: Float, length: Float)] = []
        for _ in 0..<7 {
            let length = Float.random(in: 0.006...0.011, using: &rng)
            let turn = Float.random(in: -0.7...0.7, using: &rng)
            segments.append((SIMD2(x, z), turn, length))
            x += length * cos(turn)
            z = clamp(z + length * sin(turn), -0.010, 0.010)
        }
        let total = max(segments.reduce(0) { $0 + $1.length }, 1e-4)
        var along: Float = 0
        for segment in segments {
            let line = ModelEntity(mesh: .generateBox(width: segment.length, height: 0.0004, depth: 0.0007), materials: [white])
            line.orientation = simd_quatf(angle: -segment.angle, axis: [0, 1, 0])
            line.isEnabled = false
            entity.addChild(line)
            cracks.append(Crack(model: line, start: segment.start, angle: segment.angle, length: segment.length,
                                from: along / total, to: (along + segment.length) / total))
            along += segment.length
        }
    }

    /// The run shows 30 % at the first crack and grows to its full length at the failure.
    private func growCracks(compression c: Float) {
        let p = clamp((c - crackC) / max(failC - crackC, 0.02), 0, 1)
        let grown = 0.3 + 0.7 * p
        let radius: Float = 0.030
        for crack in cracks {
            let f = clamp((grown - crack.from) / max(crack.to - crack.from, 1e-4), 0, 1)
            crack.model.isEnabled = f > 0.02
            guard f > 0.02 else { continue }
            let dir = SIMD2<Float>(cos(crack.angle), sin(crack.angle))
            let centre = crack.start + dir * (crack.length * f / 2)
            // On the squashed, ovalised cross-section (bottle centre line at y 0.030, local z widened by 1/squash).
            let across = centre.y * squash
            let top = 0.030 + max(radius * radius - across * across, 0).squareRoot() * squash + 0.0003
            crack.model.position = [centre.x, top, centre.y]
            crack.model.scale = [f, 1, 1]
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
        for crack in cracks { crack.model.removeFromParent() }
        cracks.removeAll()
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
            if i < patchModels.count { patchModels[i].removeFromParent() }
            if i < fragments.count { fragments[i].isEnabled = true }
            shard.setParent(fx.debris.root)
            let a = Float.random(in: 0...(2 * .pi), using: &rng)
            let u = Float.random(in: 0...1, using: &rng)
            let rho = GlassDebris.pileRadius(u: u)
            let spot = GlassDebris.pilePoint(angle: a, u: u, footprint: footprint, containment: containment)
            let dir = SIMD3<Float>(cos(a), 0, sin(a))
            if i < poses.count {
                let lift = GlassDebris.heapLift(rho: rho, jitter: Float.random(in: 0...1, using: &rng))
                let tilt = GlassDebris.heapTilt(rho: rho, jitter: Float.random(in: 0...1, using: &rng))
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

/// Pure glass-debris numbers (FOLD-REVIEW-3 N5), pinned in SquishTests/SceneTests.swift.
enum GlassDebris {
    /// Shards per profile band (base, low body, label low, label high, shoulder, neck): small and flat, ≤ 26° arcs on
    /// the body (was [1, 6, 6, 6, 5, 3]: 60° arcs that lay like playing cards).
    static let sectorCounts = [1, 10, 14, 14, 8, 4]
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
    static let fragmentThickness: Float = 0.0012
    static let layerStep: Float = 0.00015
    static let fragmentVariants = 8
    static let scrapVariants = 4

    /// Where shard `u` (0…1) at `angle` lands, relative to the bottle's centre: over an ellipse of `pileFill · footprint`
    /// (× `pileAspect` in z), weighted to the middle (`pileRadius`), shrunk to fit `pileRoom` of the containment box.
    static func pilePoint(angle: Float, u: Float, footprint: Float, containment: SIMD2<Float>) -> SIMD2<Float> {
        let half = simd_min(SIMD2<Float>(footprint * pileFill, footprint * pileFill * pileAspect), containment * pileRoom)
        let r = pileRadius(u: u)
        return SIMD2(cos(angle) * half.x, sin(angle) * half.y) * r
    }

    /// The fragment pair's (long, short) size (bottle-local metres) for a lathe patch `width` round × `height` along
    /// the profile: each of its two pieces is then ≈ 3–9 mm on the plate.
    static func fragmentSize(width: Float, height: Float) -> SIMD2<Float> {
        let long = clamp(max(width, height) * 0.92, 0.010, 0.022)
        let short = clamp(min(width, height) * 0.92, 0.006, 0.014)
        return SIMD2(long, min(short, long))
    }

    /// The size of one piece of a fragment pair of `size` (the pair splits along its long side).
    static func pieceSize(_ size: SIMD2<Float>) -> SIMD2<Float> {
        SIMD2(size.x * 0.42, size.y * 0.84)
    }

    static func layerHeight(_ index: Int) -> Float {
        Float(index % 5) * layerStep
    }

    static func fragmentSeed(_ variant: Int) -> UInt64 { 0x6A55_F7A6 &+ UInt64(variant) &* 0x9E37 }
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
    /// dark outer hairline and the walls.
    static func fragmentPair(seed: UInt64) -> MeshData {
        var rng = SplitMix64(seed: seed)
        var mesh = MeshData()
        for side: Float in [-1, 1] {
            let sides = 4 + Int(rng.next() % 3)
            let centre = SIMD2<Float>(side * 0.25 + Float.random(in: -0.015...0.015, using: &rng),
                                      Float.random(in: -0.04...0.04, using: &rng))
            let radii = SIMD2<Float>(Float.random(in: 0.18...0.21, using: &rng), Float.random(in: 0.38...0.46, using: &rng))
            let polygon = shardPolygon(sides: sides, radii: radii, centre: centre, rng: &rng)
            mesh.append(MeshKit.polygonSlab(polygon, thickness: fragmentThickness, rimInset: rimInset,
                                            outlineInset: outlineInset))
        }
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
