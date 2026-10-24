import Foundation
import RealityKit
import simd
import UIKit

/// Egg (bible §4 #5, VISUAL-TARGET §5.5): a lying egg, blunt end camera-left, built as 24 pre-sliced shell shards
/// (lathe patches with a 1.2 mm wall and a membrane-coloured inside) that read as one smooth egg until it gives.
/// Fracture 0 (~0.12): a hairline crack grows from the top. Fracture 1 (failure, ~0.24): the shell gives — the shards
/// break smaller and land flat on a ring round the yolk (`EggShell`, FOLD-REVIEW-6 N9), the white and a bright, glossy
/// yolk dome appear. Fracture 2 (~0.50): the yolk breaks and its runny pool spreads over the white (`EggYolk`).
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
    /// The hairline (path 0) and its two branches (OBJECT-STORYBOARDS §5), each growing from its own start toward the
    /// failure; seeded per press.
    private var cracks: [[ModelEntity]] = []
    private var crackFrom: [Float] = [1, 1, 1]
    /// A pale stress patch on the top that grows through the strain and the tell.
    private let stress: ModelEntity
    private var stressLevel = 0
    private let life: ObjectLife
    private var story: StoryCursor
    private let whiteOoze: OozeRing
    private let yolkOoze: OozeRing
    private var yolkWobble = JiggleSpring(value: 0, velocity: 0, omega: 2 * .pi * 3, zeta: 0.25)
    private let failC: Float
    private var failed = false
    private var yolkBroken = false
    private var yolkBreakC: Float = 1
    private var yolkSpread: Float = 0
    private var yolks: [ModelEntity] = []
    /// The broken yolk's runny pool, one per yolk (FOLD-REVIEW-6 N9: bright yolk spreading over the white).
    private var yolkRuns: [ModelEntity] = []
    private let albumen: ModelEntity
    private var chick: Entity?
    private let hasChick: Bool
    private let surprise: Surprise?
    private var spread: Float = 1
    /// Torn shell membrane lying on the white round the broken shell (3D-art round), shown at the give.
    private var flaps: [ModelEntity] = []

    var shadowSpread: Float { spread }

    static let profile: [SIMD2<Float>] = MeshKit.smoothProfile([
        SIMD2(0.000, 0.000), SIMD2(0.017, 0.004), SIMD2(0.026, 0.010), SIMD2(0.034, 0.020), SIMD2(0.0385, 0.032),
        SIMD2(0.0400, 0.044), SIMD2(0.0395, 0.056), SIMD2(0.0370, 0.068), SIMD2(0.0320, 0.080), SIMD2(0.0255, 0.090),
        SIMD2(0.0180, 0.098), SIMD2(0.0105, 0.104), SIMD2(0.0045, 0.108), SIMD2(0.000, 0.110),
    ], perSpan: 4)

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
                                          : SceneMaterials.enamel(UIColor(hex: 0xFDFCF7), roughness: 0.05, clearcoat: 1,
                                                                  clearcoatRoughness: 0.03, specular: 1, opacity: 0.55)])
        life = ObjectLife(seed: variant.seed, idle: .rock, amount: 0.025, rate: 0.35, pulseHz: 6, pulseDamping: 0.45)
        story = StoryCursor(.egg, seed: variant.seed)
        let plate = GlassDebris.containment(restHeight: 0.080, anvilHalf: PressRig.anvilHalf, padding: 0)
        let maxRadius = min(plate.x, plate.y) * 0.95
        let whiteMess = look.golden ? SceneMaterials.goldMess
            : SceneMaterials.enamel(UIColor(hex: 0xFDFCF7), roughness: 0.05, clearcoat: 1, clearcoatRoughness: 0.03, specular: 1,
                                    opacity: 0.6)
        var yolkMess = SceneMaterials.enamel(Palette.yolk, roughness: 0.12, clearcoat: 1, clearcoatRoughness: 0.04)
        yolkMess.emissiveColor = .init(color: UIColor(hex: 0xFFC233))
        yolkMess.emissiveIntensity = EggYolk.glow
        // The white squeezes out from under the shell ring; the yolk floods out over the white.
        whiteOoze = OozeRing(seed: variant.seed ^ 0xE67, count: 5, radii: SIMD2(0.058, 0.052), reach: 0.008...0.018,
                             width: 0.016...0.026, thickness: 0.0022, maxRadius: maxRadius, material: whiteMess, y: 0.0002)
        yolkOoze = OozeRing(seed: variant.seed ^ 0xE68, count: 6, radii: SIMD2(0.030, 0.027), reach: 0.012...0.028,
                            width: 0.012...0.020, thickness: 0.0026, maxRadius: maxRadius,
                            material: look.golden ? SceneMaterials.goldMess : yolkMess, y: 0.0006)
        stress = ModelEntity(mesh: MeshCache.resource("egg.stress") { MeshKit.ellipsoid(radii: [0.0005, 0.012, 0.009], segments: 24, rings: 12) }
                             ?? .generateSphere(radius: 0.005),
                             materials: [SceneMaterials.pbr(UIColor(hex: 0xFFFBF2), roughness: 0.75, opacity: 0.6)])
        stress.isEnabled = false
        ShadowCasting.off(stress)
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
        let normals2 = MeshKit.profile2DNormals(Self.profile)
        for (b, band) in bands.enumerated() {
            let offset = Float.random(in: 0...(2 * .pi), using: &rng)
            let n = EggShell.sectors[b]
            let jitter: Float = 0.25 * 4 / Float(max(n, 4))
            var cuts: [Float] = (0..<n).map { k in
                offset + 2 * .pi * Float(k) / Float(n) + Float.random(in: -jitter...jitter, using: &rng)
            }
            cuts.append(cuts[0] + 2 * .pi)
            // 3D-art round: the cracks between the pieces are jagged (each cut zigzags ring by ring, shared by the two
            // pieces it separates, so the shell still closes), so the fragments break with real shell edges.
            let bandSeed = variant.seed ^ (0xE66_C0 &+ UInt64(b) &* 0x9E37)
            func cut(_ k: Int, _ ring: Int) -> Float {
                cuts[k] + EggShell.jag(seed: bandSeed, cut: k % n, ring: ring, sector: 2 * .pi / Float(n))
            }
            for k in 0..<n {
                let patch = MeshKit.lathePatch(profile: Self.profile, rings: band, lower: { cut(k, $0) }, upper: { cut(k + 1, $0) },
                                               angularSteps: 9, thickness: 0.0012)
                // Authored with its outward normal as local +Y (FOLD-REVIEW-6 N9), so the break can lay it flat and
                // convex side up with a yaw-only turn (the lying egg's patches used to be pinned by the platen at
                // whatever angle they had, right on top of the yolk).
                let theta = (cuts[k] + cuts[k + 1]) / 2
                let n2 = normals2[(band.lowerBound + band.upperBound) / 2]
                let normal = simd_normalize(SIMD3<Float>(n2.x * cos(theta), n2.y, n2.x * sin(theta)))
                let toLocal = simd_quatf(from: normal, to: [0, 1, 0])
                let shard = MeshKit.entity(patch.mesh.transformed(simd_float4x4(toLocal)), materials: [shellMaterial, membrane],
                                           name: "egg.shard")
                shard.position = patch.centre
                shard.orientation = toLocal.inverse
                axial.addChild(shard)
                shards.append(shard)
            }
        }
        // Hairline crack along the top (world up = lathe −X after the roll), then two seeded branches off it
        // (OBJECT-STORYBOARDS §5: the crack spreads before the shell splinters).
        let crackMaterial = SceneMaterials.pbr(UIColor(hex: 0x8A6A3E), roughness: 0.6)
        var crackRng = SplitMix64(seed: variant.seed ^ 0xC2AC)
        func path(axial start: Float, theta startTheta: Float, steps: Int, stride: ClosedRange<Float>, drift: Float,
                  rng: inout SplitMix64) -> [(SIMD3<Float>, SIMD3<Float>)] {
            var points: [(SIMD3<Float>, SIMD3<Float>)] = []
            var axialPos = start
            var theta = startTheta
            for _ in 0..<steps {
                let r = Self.radius(at: clamp(axialPos, 0.004, 0.106)) + 0.0002
                let p = SIMD3<Float>(r * cos(theta), axialPos, r * sin(theta))
                points.append((p, simd_normalize(SIMD3(cos(theta), 0, sin(theta)))))
                axialPos += Float.random(in: stride, using: &rng)
                theta += drift + Float.random(in: -0.22...0.22, using: &rng)
            }
            return points
        }
        let theta0: Float = .pi + Float.random(in: -0.15...0.15, using: &rng)
        let main = path(axial: 0.036, theta: theta0, steps: 11, stride: 0.0035...0.0055, drift: 0, rng: &rng)
        self.rng = rng
        var paths = [main]
        for (k, from) in [3, 7].enumerated() where from < main.count {
            let p = main[from].0
            let startTheta = atan2(p.z, p.x)
            let coin = crackRng.next() % 2 == 0
            let side: Float = coin ? 1 : -1
            // The first branch runs back toward the blunt end, the second on toward the tip.
            let stride: ClosedRange<Float> = k == 0 ? (-0.0045)...(-0.0025) : 0.0025...0.0045
            paths.append(path(axial: p.y, theta: startTheta, steps: 7, stride: stride, drift: side * 0.16, rng: &crackRng))
        }
        for points in paths {
            var segments: [ModelEntity] = []
            for i in 0..<(points.count - 1) {
                let (p0, n0) = points[i], (p1, _) = points[i + 1]
                let d = p1 - p0
                let length = simd_length(d)
                guard length > 1e-5 else { continue }
                let dir = d / length
                let up = simd_normalize(n0 - simd_dot(n0, dir) * dir)
                let side = simd_cross(dir, up)
                let line = MeshKit.model(MeshKit.roundedBox([length + 0.0006, 0.0005, 0.0008], radius: 0.0002, bevel: 0.0001),
                                         material: crackMaterial)
                line.position = (p0 + p1) / 2
                line.orientation = simd_quatf(simd_float3x3(columns: (dir, up, side)))
                line.isEnabled = false
                axial.addChild(line)
                segments.append(line)
            }
            cracks.append(segments)
        }
        // The stress patch on the top of the shell (lathe −X), over the middle of the hairline.
        stress.position = [-(Self.radius(at: 0.052) + 0.0003), 0.052, 0]
        axial.addChild(stress)
        life.node.addChild(shell)
        entity.addChild(life.node)
        if !look.golden {
            // Shell detail (fidelity pass): a speckled, mottled shell with fine pores, once the textures are up; the
            // 3D-art round adds a soft subsurface lift (the shell's own colour, faintly self-lit, so its shadow side
            // glows warm like lit eggshell) and the fibrous membrane on the inside.
            let pieces = shards
            Task { @MainActor in
                async let membraneMaps = SurfaceDetail.eggMembrane()
                let detail = await SurfaceDetail.eggShell()
                guard let colour = detail.colour else { return }
                var material = SceneMaterials.pbr(.white, roughness: 0.62, clearcoat: 0.12)
                material.baseColor = .init(tint: .white, texture: .init(colour))
                if let normal = detail.normal { material.normal = .init(texture: .init(normal)) }
                material.emissiveColor = .init(color: .white, texture: .init(colour))
                material.emissiveIntensity = EggShell.subsurface
                let membrane = await membraneMaps
                var inner = SceneMaterials.pbr(.white, roughness: 0.75)
                if let m = membrane.colour { inner.baseColor = .init(tint: .white, texture: SurfaceDetail.tiled(m)) }
                if let n = membrane.normal { inner.normal = .init(texture: SurfaceDetail.tiled(n)) }
                inner.emissiveColor = .init(color: UIColor(hex: 0xFFF6E4))
                inner.emissiveIntensity = 0.06
                for shard in pieces {
                    let models = GlassBottleView.models(in: shard)
                    models.first?.model?.materials = [material]
                    if models.count > 1 { models[1].model?.materials = [inner] }
                }
            }
        }
        buildMembraneFlaps(seed: variant.seed)
        entity.addChild(albumen)
        entity.addChild(whiteOoze.root)
        entity.addChild(yolkOoze.root)
        entity.orientation = Part.yaw(-20)
    }

    /// Translucent scraps of membrane torn off with the shell, lying on the white just inside the shard ring.
    private func buildMembraneFlaps(seed: UInt64) {
        var rng = SplitMix64(seed: seed ^ 0xE6F1)
        let material = look.golden ? SceneMaterials.goldMess
            : SceneMaterials.enamel(UIColor(hex: 0xFFFBF2), roughness: 0.3, clearcoat: 0.6, clearcoatRoughness: 0.2, opacity: 0.62)
        let reach = EggShell.yolkReach(doubleYolk: surprise == .doubleYolk)
        for k in 0..<EggShell.flaps {
            let a = Float(k) / Float(EggShell.flaps) * 2 * .pi + Float.random(in: -0.4...0.4, using: &rng)
            let flap = Part.add(cached: "egg.membrane.flap.\(k % 3)", { EggShell.flapMesh(seed: UInt64(k % 3)) }, material,
                                at: [cos(a) * (reach - 0.002), EggYolk.albumenHeight + 0.0003, sin(a) * (reach - 0.002) * EggShell.ringAspect],
                                to: entity)
            flap.orientation = Part.yaw(Float.random(in: 0...360, using: &rng))
            flap.isEnabled = false
            ShadowCasting.off(flap)
            flaps.append(flap)
        }
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
        if life.update(state) {
            BeatFX.glint(fx, at: [0.012, 0.079, -0.006], in: entity, golden: look.golden, rng: &rng)
        }
        for beat in story.advance(to: c) { onBeat(beat, state: state) }
        let h = surfaceHeight(compression: c)
        if !failed {
            let s = h / restHeight
            shell.scale = SIMD3(s, 1, 1 / s.squareRoot())
            // Each crack path grows from its start toward the failure.
            for (p, lines) in cracks.enumerated() where p < crackFrom.count && crackFrom[p] < 1 {
                let t = clamp((c - crackFrom[p]) / max(failC - crackFrom[p], 0.01), 0, 1)
                let visible = max(Int((0.3 + 0.7 * t) * Float(lines.count)), 2)
                for (i, line) in lines.enumerated() { line.isEnabled = i < visible }
            }
            return
        }
        whiteOoze.update(compression: c, spread: 1)
        yolkOoze.update(compression: c, spread: 1)
        yolkWobble.step(toward: 0, dt: state.dt)
        let t = clamp((c - failC) / max(1 - failC, 0.05), 0, 1)
        // Albumen spreads to Ø 0.13, 2 mm.
        albumen.scale = SIMD3(0.050 + 0.024 * t, EggYolk.albumenHeight, (0.050 + 0.024 * t) * 0.9)
        spread = (0.050 + 0.024 * t) / footprint
        // The yolk stands clear of the 2 mm white (FOLD-REVIEW-6 N9): a broken yolk keeps a ≥ 3.5 mm dome and its runny
        // pool spreads out over the white as the press closes (latched, so the reveal shows the widest).
        let breakT = yolkBroken ? clamp((c - yolkBreakC) / max(1 - yolkBreakC, 0.05), 0, 1) : 0
        yolkSpread = max(yolkSpread, breakT)
        for (i, yolk) in yolks.enumerated() {
            let dome = yolkBroken ? EggYolk.brokenDome : EggYolk.dome
            let height = min(dome, max(h - 0.001, EggYolk.minHeight))
            var radius = yolkBroken ? EggYolk.brokenRadius(yolkSpread) : EggYolk.radius
            radius *= min((dome / height).squareRoot(), 1.6)
            let wobble = 1 + 0.12 * clamp(yolkWobble.value, -1, 1)
            yolk.scale = SIMD3(radius * wobble, height * min(1, 1 / wobble), radius / wobble.squareRoot())
            if i < yolkRuns.count {
                let run = EggYolk.runRadius(yolkSpread)
                yolkRuns[i].isEnabled = yolkBroken
                yolkRuns[i].scale = SIMD3(run, EggYolk.runHeight, run * 0.9)
            }
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
            crackFrom[0] = min(crackFrom[0], state.compression)
            if let main = cracks.first {
                for (i, line) in main.enumerated() where i < 3 { line.isEnabled = true }
            }
            life.kick(0.6)
        case 1:
            failed = true
            shell.scale = SIMD3(repeating: 1)
            for line in cracks.joined() { line.removeFromParent() }
            stress.removeFromParent()
            life.kick(1.2)
            breakShell()
            for flap in flaps { flap.isEnabled = true }
            albumen.isEnabled = true
            albumen.scale = SIMD3(0.04, EggYolk.albumenHeight, 0.036)
            if hasChick {
                addChick()
            } else {
                let yolkMaterial: PhysicallyBasedMaterial
                if look.golden {
                    yolkMaterial = SceneMaterials.goldMess
                } else {
                    // Brighter (0.15 → 0.3 self-glow) so the yolk is the first thing you see on the cream white.
                    var m = SceneMaterials.enamel(Palette.yolk, roughness: 0.12, clearcoat: 1, clearcoatRoughness: 0.04)
                    m.emissiveColor = .init(color: UIColor(hex: 0xFFC233))
                    m.emissiveIntensity = EggYolk.glow
                    yolkMaterial = m
                }
                let positions: [Float] = !hasDoubleYolk ? [0] : [-EggYolk.doubleOffset, EggYolk.doubleOffset]
                for (k, x) in positions.enumerated() {
                    // The runny pool under the dome (hidden until the yolk breaks), then the dome itself.
                    let variant = Int((rng.next() >> 33) % 3)
                    let run = Part.add(cached: "egg.yolkRun.\(variant)", {
                        MeshKit.spreadDisc(seed: 0xE66_0000 &+ UInt64(variant) &* 0x9E37, height: 1, segments: 56, wobble: 0.24)
                    }, yolkMaterial, at: [x, 0.0001 * Float(k + 1), 0], to: entity)
                    run.orientation = Part.yaw(Float.random(in: 0...360, using: &rng))
                    run.scale = SIMD3(0.018, EggYolk.runHeight, 0.018)
                    run.isEnabled = false
                    yolkRuns.append(run)
                    let yolk = Part.add(cached: "egg.yolk", { MeshKit.sphere(radius: 1, segments: 48, rings: 24) },
                                        yolkMaterial, at: [x, 0, 0], to: entity)
                    yolk.scale = SIMD3(0.018, EggYolk.dome, 0.018)
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

    func handle(_ event: PressEvent, state: PressVisualState) {
        if event == .preFailureTell { life.tremor(0.25) }
    }

    /// The stress patch grows a step (it's the shell whitening before it splinters).
    private func whiten() {
        guard !failed else { return }
        stressLevel = min(stressLevel + 1, 3)
        stress.isEnabled = true
        let k = 0.55 + 0.25 * Float(stressLevel)
        stress.scale = SIMD3(1, k, k)
    }

    /// One storyboard beat (OBJECT-STORYBOARDS §5).
    private func onBeat(_ beat: StoryBeat, state: PressVisualState) {
        let c = state.compression
        let golden = look.golden
        switch beat.kind {
        case .kiss:
            life.kick(0.5)
            BeatFX.glint(fx, at: [0.012, 0.079, -0.006], in: entity, count: 3, golden: golden, rng: &rng)
        case .strain:
            if failed {
                // The yolk skin goes taut: a highlight runs over it and it trembles.
                yolkWobble.kick(1.5)
                if let yolk = yolks.first { BeatFX.glint(fx, at: [0, 1, 0], in: yolk, golden: golden, rng: &rng) }
            } else {
                whiten()
            }
        case .crack:
            if !failed { crackFrom[0] = min(crackFrom[0], c) }
            life.kick(0.4)
        case .branch:
            let p = min(beat.ordinal + 1, 2)
            if !failed { crackFrom[p] = min(crackFrom[p], c) }
            life.tremor(0.12, level: 0.6)
        case .tell:
            whiten()
            if !failed { crackFrom[2] = min(crackFrom[2], c) }
            life.tremor(0.3)
        case .chip:
            hopShards(2)
        case .ooze:
            oozeOut(beat: beat, compression: c)
        case .wobble:
            yolkWobble.kick(2.2)
            if let yolk = yolks.first { BeatFX.glint(fx, at: [0.3, 1, -0.2], in: yolk, golden: golden, rng: &rng) }
        case .fling:
            let a = Float.random(in: 0...(2 * .pi), using: &rng)
            let colors = golden ? [Palette.goldMessColor] : (yolkBroken ? [Palette.yolk, UIColor(hex: 0xFFC233)] : [UIColor(hex: 0xFDFCF7)])
            BeatFX.fling(fx, at: [cos(a) * 0.03, 0.004, sin(a) * 0.03], in: entity, direction: SIMD2(cos(a), sin(a)),
                         count: 3, colors: colors, speed: 0.18, rng: &rng)
        case .settle:
            if let yolk = yolks.first {
                BeatFX.glint(fx, at: [0, 1, 0], in: yolk, count: 2, golden: golden, rng: &rng)
            } else {
                BeatFX.glint(fx, at: [0, 0.01, 0], in: entity, count: 2, golden: golden, rng: &rng)
            }
        default:
            life.kick(0.4)
        }
    }

    /// The white squeezes out of the pinch line before the yolk goes; after it, the yolk floods out.
    private func oozeOut(beat: StoryBeat, compression c: Float) {
        guard failed else {
            // Not given yet (a late seed): the crack creeps instead.
            crackFrom[1] = min(crackFrom[1], c)
            return
        }
        let yolkTurn = yolkBroken && !yolks.isEmpty && yolkOoze.emitted < yolkOoze.capacity
        let ring = yolkTurn ? yolkOoze : whiteOoze
        if let tip = ring.emit(at: c), beat.ordinal % 2 == 1 {
            let d = simd_length(SIMD2(tip.x, tip.z)) > 1e-5 ? simd_normalize(SIMD2(tip.x, tip.z)) : SIMD2<Float>(1, 0)
            let colors = look.golden ? [Palette.goldMessColor] : (yolkTurn ? [Palette.yolk] : [UIColor(hex: 0xFDFCF7)])
            BeatFX.fling(fx, at: tip, in: entity, direction: d, count: 1, colors: colors, speed: 0.1, rng: &rng)
        }
        yolkWobble.kick(1)
    }

    /// A couple of landed shell pieces hop and settle again (the settle after the give).
    private func hopShards(_ count: Int) {
        guard failed else {
            BeatFX.puff(fx, at: [0, 0.07, 0], in: entity, count: 2, color: UIColor(hex: 0xEFD3A0), rng: &rng)
            return
        }
        let m = fx.motionScale
        for _ in 0..<count {
            guard !shards.isEmpty else { return }
            let shard = shards[Int(rng.next() % UInt64(shards.count))]
            guard let body = fx.debris.release(shard) else { continue }
            var bounds: (min: SIMD2<Float>, max: SIMD2<Float>)?
            if let lo = body.boundsMin, let hi = body.boundsMax { bounds = (min: lo, max: hi) }
            let v = SIMD3<Float>(Float.random(in: -0.03...0.03, using: &rng), 0.12, Float.random(in: -0.03...0.03, using: &rng)) * m
            fx.debris.adopt(shard, velocity: v, spin: SIMD3(0, Float.random(in: -4...4, using: &rng) * m, 0),
                            bounciness: 0.15, friction: 0.9, maxSpread: 1, bounds: bounds)
        }
    }

    private var hasDoubleYolk: Bool { surprise == .doubleYolk }

    /// The shell gives (FOLD-REVIEW-6 N9). The patches used to burst from the egg's centre and get pinned by the
    /// platen wherever they were mid-tumble, i.e. right over the yolk: a cream disc with paper-white shards and no
    /// yellow. Now each breaks smaller (`EggShell.shardScale`), drops flat on a ring round the yolk on its own side
    /// (`EggShell.ringPoint`), mostly tan side up with a few cream insides showing, hops a little and is boxed there,
    /// so the yolk always shows in the middle. A puff of shell flakes covers the change.
    private func breakShell() {
        let m = fx.motionScale
        let root = fx.debris.root
        let centre = entity.convert(position: .zero, to: root)
        let pieceScale = max(entity.scale(relativeTo: root).x, 0.01) * EggShell.shardScale
        let containment = GlassDebris.containment(restHeight: restHeight, anvilHalf: PressRig.anvilHalf, padding: 0)
        let reach = EggShell.yolkReach(doubleYolk: hasDoubleYolk)
        for (i, shard) in shards.enumerated() {
            let p = shard.position(relativeTo: root)
            var out = SIMD2<Float>(p.x - centre.x, p.z - centre.z)
            if simd_length(out) < 1e-4 {
                let a = Float.random(in: 0...(2 * .pi), using: &rng)
                out = SIMD2(cos(a), sin(a))
            }
            let angle = atan2(out.y, out.x) + Float.random(in: -0.3...0.3, using: &rng)
            let spot = EggShell.ringPoint(angle: angle, u: Float.random(in: 0...1, using: &rng), reach: reach)
            let target = SIMD2<Float>(centre.x, centre.z) + spot
            shard.setParent(root)
            let yaw = simd_quatf(angle: Float.random(in: 0...(2 * .pi), using: &rng), axis: [0, 1, 0])
            // Every third shard lands inside up (the membrane), the rest show the tan shell.
            let flip = EggShell.showsInside(i) ? simd_quatf(angle: .pi, axis: [1, 0, 0]) : Part.identity
            shard.orientation = yaw * flip
            shard.scale = SIMD3(repeating: pieceScale)
            shard.position = SIMD3(target.x, 0.004, target.y)
            let size = shard.visualBounds(relativeTo: root).extents
            let half = SIMD2<Float>(repeating: simd_length(SIMD2(size.x, size.z)) / 2)
            let plate = GlassDebris.centreBounds(containment: containment, pieceHalf: half)
            let slack = SIMD2<Float>(repeating: EggShell.slack)
            let bounds = (min: simd_max(target - slack, plate.min), max: simd_min(target + slack, plate.max))
            let dir = simd_normalize(spot + SIMD2(1e-6, 0))
            let v = SIMD3<Float>(dir.x * 0.05, 0.14, dir.y * 0.05) * m
            fx.debris.adopt(shard, velocity: v, spin: SIMD3(0, Float.random(in: -3...3, using: &rng) * m, 0),
                            bounciness: 0.15, friction: 0.9, maxSpread: 1, bounds: bounds)
        }
        let at = entity.convert(position: [0, 0.02, 0], to: fx.root)
        fx.particles.burst(.flake, count: 10, at: at, speed: 0.22 * max(m, 0.3),
                           colors: look.golden ? [Palette.gold] : [UIColor(hex: 0xEFD3A0), UIColor(hex: 0xFFF9EE)],
                           size: 0.003...0.005, spread: 0.02, upBias: 0.4, rng: &rng)
    }

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

/// How the shell breaks (FOLD-REVIEW-6 N9), pure so SquishTests can pin it: the shards land on a ring round the yolk,
/// never on it.
enum EggShell {
    /// Shards per profile band (blunt end, middle, tip): 24 (was 12 big patches).
    static let sectors = [8, 8, 8]
    /// A shard breaks to this share of its patch as it drops.
    static let shardScale: Float = 0.55
    /// How far (metres) a landed shard may hop or skid from its spot.
    static let slack: Float = 0.004
    /// Ring depth (z) as a share of its width (x), so even the double yolk's ring stays on the P-48 anvil (±0.056 m).
    static let ringAspect: Float = 0.8
    /// The ring is this wide (metres) outside its inner radius.
    static let ringWidth: Float = 0.010

    /// The ring's inner radius: just outside the yolk's widest pool, plus the second yolk's offset.
    static func yolkReach(doubleYolk: Bool) -> Float {
        EggYolk.runRadius(1) + 0.004 + (doubleYolk ? 0.012 : 0)
    }

    /// Where a shard at `angle` (from the egg's centre) lands, for a uniform `u`.
    static func ringPoint(angle: Float, u: Float, reach: Float) -> SIMD2<Float> {
        let r = reach + ringWidth * clamp(u, 0, 1)
        return SIMD2(cos(angle) * r, sin(angle) * r * ringAspect)
    }

    /// Every third shard lands inside up, so the pile reads as broken shell (tan outside, cream inside).
    static func showsInside(_ index: Int) -> Bool {
        index % 3 == 1
    }

    // MARK: Jagged breaks and membrane (3D-art round)

    /// How far (radians) cut `cut` of a band zigzags off its straight line at profile ring `ring`: seeded per cut and
    /// ring (so the two pieces either side agree), alternating in sign, up to `jagShare` of the sector.
    static let jagShare: Float = 0.16
    static func jag(seed: UInt64, cut: Int, ring: Int, sector: Float) -> Float {
        var rng = SplitMix64(seed: seed &+ UInt64(cut) &* 0x9E37_79B9 &+ UInt64(ring) &* 0x51ED_2701)
        let size = Float(rng.next() >> 40) / Float(1 << 24)
        let sign: Float = (ring / 2) % 2 == 0 ? 1 : -1
        return sign * (0.35 + 0.65 * size) * jagShare * sector
    }

    /// The shell's faint self-lit lift (fake subsurface scattering) once its maps are up.
    static let subsurface: Float = 0.1
    static let flaps = 6

    /// A torn scrap of membrane: a thin, ragged 7-gon about 6 mm across.
    static func flapMesh(seed: UInt64) -> MeshData {
        var rng = SplitMix64(seed: seed ^ 0xF1A9)
        let points: [SIMD2<Float>] = (0..<7).map { k in
            let a = Float(k) / 7 * 2 * .pi + Float.random(in: -0.25...0.25, using: &rng)
            let r = Float.random(in: 0.0018...0.0034, using: &rng)
            return SIMD2(cos(a) * r, sin(a) * r * 0.8)
        }
        return MeshKit.polygonSlab(points, thickness: 0.0003)
    }
}

/// The yolk's sizes (metres) and glow, pure so SquishTests can pin them against the 2 mm albumen.
enum EggYolk {
    static let radius: Float = 0.018
    static let dome: Float = 0.011
    /// A broken yolk is a lower dome that never sinks into the white (FOLD-REVIEW-6 N9: it was 1.5 mm, under the shell).
    static let brokenDome: Float = 0.006
    static let minHeight: Float = 0.0035
    /// The albumen's height (its spread disc is scaled to 2 mm).
    static let albumenHeight: Float = 0.002
    /// The runny pool's height: just over the white.
    static let runHeight: Float = 0.0026
    static let glow: Float = 0.3
    static let doubleOffset: Float = 0.017

    /// The broken dome's radius at break progress `t` (0…1).
    static func brokenRadius(_ t: Float) -> Float {
        0.024 + 0.010 * clamp(t, 0, 1)
    }

    /// The runny pool's radius at break progress `t`: it spreads out over the white as the press closes.
    static func runRadius(_ t: Float) -> Float {
        0.028 + 0.014 * clamp(t, 0, 1)
    }
}
