import Foundation
import RealityKit
import simd
import UIKit

/// Glass Bottle (bible §4 #9, VISUAL-TARGET §5.9): a sea-glass bottle lying on its side, neck camera-right,
/// pre-fractured into ~50 small thin shards (2.2 mm lathe patches, ≤ 26° arcs) under one intact paper label band.
/// Silent rigidity until fracture 0 (~0.22), apart from a slight ovalisation; then bright crack lines that lengthen
/// toward the failure. Fracture 1 (failure, ~0.40) is the biggest event in the app: the label tears away, the shards
/// drop flat and skid a little (fade-and-slump under Reduce Motion), glints sparkle, and the pile stays on the strike
/// plate (+16 pt). Fracture 2 (~0.62): the pile crunches into soft "sea glass". The pile freezes at seal, so the
/// reveal shows exactly the sealed pile (FOLD-REVIEW-3 N5). Surprise `messageInABottle`: a rolled note that bursts
/// into candy confetti.
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
    private var shards: [ModelEntity] = []
    private var glassParts: [ModelEntity] = []
    private var glassDust: ModelEntity?
    /// Bottle-local outward normal of each shard (to lay it flat, outer face up, on shatter).
    private var shardNormals: [SIMD3<Float>] = []
    private var sparkles: [Entity] = []
    /// The intact paper label (one band, not split into shards); it tears away at the shatter.
    private let labelBand = Entity()
    /// A few small label scraps riding on shards, shown once the label has torn (FOLD-REVIEW-3 N5).
    private var labelScraps: [Entity] = []
    private var cracks: [Crack] = []
    private var crackC: Float = 0
    private var cracked = false
    private var message: Entity?
    private let failC: Float
    private var failed = false
    private var sealed = false
    /// Latched pre-failure squash (vertical height ratio) and post-failure dust progress: never un-squash.
    private var squash: Float = 1
    private var dustT: Float = 0
    /// Half extents (x, z) in fx metres the debris must stay inside: the strike plate + 16 pt.
    private let containment: SIMD2<Float>
    private let seaGlass: PhysicallyBasedMaterial

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
        seaGlass = look.golden ? SceneMaterials.gold
            : SceneMaterials.enamel(UIColor(hex: 0x5CC8B8), roughness: 0.25, clearcoat: 0.8, clearcoatRoughness: 0.2,
                                    specular: 1, opacity: 0.55)
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
        let sparkleMaterial = SceneMaterials.unlit(UIColor(hex: 0xFFFFFF))
        func ring(at y: Float) -> Int {
            profile.firstIndex { $0.y >= y } ?? profile.count - 1
        }
        let bandEdges = [0, ring(at: 0.006), ring(at: 0.035), ring(at: 0.060), ring(at: 0.085), ring(at: 0.112), profile.count - 1]
        let sectorCounts = GlassDebris.sectorCounts
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
            // The label bands keep only a few small paper scraps: two on the cream band, one on the stripe.
            var scrapShards = Set<Int>()
            if b == 2 || b == 3 {
                let wanted = b == 2 ? 2 : 1
                while scrapShards.count < min(wanted, n) {
                    scrapShards.insert(Int(rng.next() % UInt64(n)))
                }
            }
            for k in 0..<n {
                let patch = MeshKit.lathePatch(profile: profile, rings: rings, angles: cuts[k]...cuts[k + 1],
                                               angularSteps: max(4, 48 / n), thickness: 0.0022)
                let mid = (rings.lowerBound + rings.upperBound) / 2
                let theta = (cuts[k] + cuts[k + 1]) / 2
                let n2 = normals2[mid]
                let normal = simd_normalize(SIMD3<Float>(n2.x * cos(theta), n2.y, n2.x * sin(theta)))
                // Author each shard with its outward normal as local +Y (its thin axis), so once it lies flat the debris
                // settling keeps it flat instead of tipping it onto an edge.
                let toLocal = simd_quatf(from: normal, to: [0, 1, 0])
                let rotate = simd_float4x4(toLocal)
                let shard = ModelEntity()
                let model = MeshKit.entity(patch.mesh.transformed(rotate), materials: [outer, inner], name: "glass.shard")
                shard.addChild(model)
                glassParts += Self.models(in: model)
                shard.position = patch.centre
                shard.orientation = toLocal.inverse
                shardNormals.append([0, 1, 0])
                // A static specular sparkle on some shards, shown once the pile lies flat (reads as glass, not paper).
                if (b + k) % 3 == 0 {
                    let sparkle = ModelEntity(mesh: MeshCache.resource("glass.sparkle") { MeshKit.ellipsoid(radii: [0.0016, 0.0005, 0.0016], segments: 12, rings: 6) }
                                              ?? .generateSphere(radius: 0.001), materials: [sparkleMaterial])
                    sparkle.position = [0, 0.0016, 0]
                    sparkle.isEnabled = false
                    shard.addChild(sparkle)
                    sparkles.append(sparkle)
                }
                if scrapShards.contains(k) {
                    // A torn scrap: the middle half of the shard's arc and about half the band's height (≈ 5 × 9 mm).
                    let span = cuts[k + 1] - cuts[k]
                    let rows = rings.upperBound - rings.lowerBound
                    let r0 = rings.lowerBound + (rows >= 3 ? 1 : 0)
                    let r1 = min(r0 + max(rows / 2, 1), rings.upperBound)
                    let scrapPatch = MeshKit.lathePatch(profile: labelProfile, rings: r0...r1,
                                                        angles: (cuts[k] + span * 0.25)...(cuts[k + 1] - span * 0.25),
                                                        angularSteps: 3, thickness: 0.0005)
                    let scrap = MeshKit.entity(scrapPatch.mesh.transformed(rotate), materials: [b == 2 ? label : labelStripe, label],
                                               name: "glass.label")
                    scrap.position = toLocal.act(scrapPatch.centre - patch.centre)
                    scrap.isEnabled = false
                    shard.addChild(scrap)
                    labelScraps.append(scrap)
                }
                axial.addChild(shard)
                shards.append(shard)
            }
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
            // The sea-glass dust under the pile: small and faint, latched at its widest, frozen at seal.
            guard !sealed, let dust = glassDust else { return }
            let t = clamp((state.compression - failC) / max(1 - failC, 0.05), 0, 1)
            dustT = max(dustT, t)
            let radius = GlassDebris.dustRadius(dustT) / Self.heroScale
            dust.scale = SIMD3(radius, 0.0008, radius * 0.75)
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
            // Crunch: the pile settles into soft sea glass, with a few small bits that stay near the pile.
            for part in glassParts { part.model?.materials = [seaGlass] }
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
        var pieces: [Entity] = shards
        if let message { pieces.append(message) }
        fx.debris.freeze(pieces)
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
        let dustMaterial = look.golden ? SceneMaterials.goldMess
            : SceneMaterials.enamel(UIColor(hex: 0x8FE0D3), roughness: 0.3, clearcoat: 0.4, clearcoatRoughness: 0.3, opacity: 0.18)
        let dust = ModelEntity(mesh: MeshCache.resource("glass.dust") { MeshKit.spreadDisc(seed: 0x6D, height: 1, segments: 48, wobble: 0.08) }
                               ?? .generateSphere(radius: 0.01), materials: [dustMaterial])
        let dustRadius = GlassDebris.dustRadius(0) / Self.heroScale
        dust.scale = SIMD3(dustRadius, 0.0008, dustRadius * 0.75)
        dust.position = [0, 0.0002, 0]
        entity.addChild(dust)
        glassDust = dust
        // The shards keep the squashed bottle's scale (no reset to rest size, FOLD-REVIEW-3 N5).
        labelBand.isEnabled = false
        for scrap in labelScraps { scrap.isEnabled = true }
        for crack in cracks { crack.model.removeFromParent() }
        cracks.removeAll()
        let m = fx.motionScale
        // Each shard is turned outer-face-up with a seeded yaw, made thinner (half the lathe curl, so it lies like a
        // flake of glass, not a card), dropped to plate height 0.33–0.7× the footprint out, then skids 0.04–0.10 m/s
        // outward with no up component; its centre is boxed so all of it stays on the strike plate + 16 pt.
        let centre0 = entity.convert(position: [0, 0, 0], to: fx.root)
        let footprintWorld = footprint
        for (i, shard) in shards.enumerated() {
            let worldNormal = simd_normalize(shard.convert(direction: shardNormals[i], to: fx.root))
            let p = shard.position(relativeTo: fx.root)
            var radial = SIMD3<Float>(p.x - centre0.x, 0, p.z - centre0.z)
            if simd_length(radial) < 1e-4 {
                let a = Float.random(in: 0...(2 * .pi), using: &rng)
                radial = SIMD3(cos(a), 0, sin(a)) * 0.01
            }
            let dir = simd_normalize(radial)
            let reach = footprintWorld * Float.random(in: 0.6...1.3, using: &rng) * min(simd_length(radial) / 0.03 + 0.4, 1)
            shard.setParent(fx.debris.root, preservingWorldTransform: true)
            let flat = simd_quatf(from: worldNormal, to: [0, 1, 0])
            let yaw = simd_quatf(angle: Float.random(in: -0.6...0.6, using: &rng), axis: [0, 1, 0])
            shard.orientation = simd_normalize(yaw * flat * shard.orientation)
            shard.scale *= SIMD3<Float>(1, 0.55, 1)
            shard.position = SIMD3(centre0.x, 0.003, centre0.z) + dir * reach * 0.55
            let size = shard.visualBounds(relativeTo: fx.debris.root).extents
            // Circumscribed half size, so a little yaw while it skids can't swing a corner off the plate.
            let half = SIMD2<Float>(repeating: simd_length(SIMD2(size.x, size.z)) / 2)
            let v = dir * Float.random(in: GlassDebris.skidSpeed, using: &rng) * m
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

    /// Half extents (x, z), fx metres, of the Fold Press strike plate + `platePadding` for an object of `restHeight`
    /// (the anvil's fold scale, as `FoldPressController` sets it), never wider than the P-48 anvil (`anvilHalf`).
    static func containment(restHeight: Float, anvilHalf: SIMD2<Float>) -> SIMD2<Float> {
        let foldScale = FoldMetrics.foldScale(restHeight: Double(restHeight))
        let metresPerPoint = FoldMetrics.metresPerMM(foldScale: foldScale) / FoldMetrics.pointsPerMM
        let plate = SIMD2<Float>(Float((FoldMetrics.plateLateral / 2 + platePadding) * metresPerPoint),
                                 Float((FoldMetrics.plateDepth / 2 + platePadding) * metresPerPoint))
        return simd_min(plate, anvilHalf)
    }

    /// The box a piece's centre may occupy so all of it (horizontal half size `pieceHalf`) stays inside `containment`.
    static func centreBounds(containment: SIMD2<Float>, pieceHalf: SIMD2<Float>) -> (min: SIMD2<Float>, max: SIMD2<Float>) {
        let room = simd_max(containment - pieceHalf, SIMD2<Float>(repeating: 0))
        return (-room, room)
    }

    /// Dust disc radius (world metres) at post-failure progress `t`: small and faint, not a bottle-sized bag.
    static func dustRadius(_ t: Float) -> Float {
        0.022 + 0.010 * clamp(t, 0, 1)
    }
}
