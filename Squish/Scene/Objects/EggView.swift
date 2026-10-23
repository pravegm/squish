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
    private var crack: [ModelEntity] = []
    private var crackFrom: Float = 1
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
                                          : SceneMaterials.enamel(UIColor(hex: 0xFDFCF7), roughness: 0.05, clearcoat: 1,
                                                                  clearcoatRoughness: 0.03, specular: 1, opacity: 0.55)])
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
            for k in 0..<n {
                let patch = MeshKit.lathePatch(profile: Self.profile, rings: band, angles: cuts[k]...cuts[k + 1],
                                               angularSteps: 7, thickness: 0.0012)
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
            yolk.scale = SIMD3(radius, height, radius)
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
            crackFrom = state.compression
            for (i, line) in crack.enumerated() { line.isEnabled = i < 3 }
        case 1:
            failed = true
            shell.scale = SIMD3(repeating: 1)
            for line in crack { line.removeFromParent() }
            breakShell()
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
