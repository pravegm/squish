import Foundation
import RealityKit
import simd
import UIKit

/// Soda Can (bible §4 #7, VISUAL-TARGET §5.7): a fat tallboy of painted aluminium (fictional "FIZZO" colourway:
/// candy field, white wave band, dark drop line; bare aluminium ends), one CPU-deformed `DeformableMesh`.
/// Thin-wall buckling: the can barely gives between buckles (but its rim ovalises, its lid dents and the next band
/// pre-buckles, so it reads from above), then one concertina ring collapses (top-down) with alternating diamond lobes
/// folding outward and the ram lurches down a step: five buckles in all, then a ridged flattened disc.
/// Fracture 2 (failure) punctures it: a fizz geyser sprays from the fold for ~0.7 s, droplets land and a puddle spreads.
/// Fizz colour per seed (lime / orange / berry); `cherryFizz` surprise makes it cherry.
@MainActor
final class SodaCanView: PressObjectView {
    let entity = Entity()
    /// Ø 0.110 × 0.140 (VISUAL-REVIEW-1 fix 6).
    let restHeight: Float = 0.150 * ObjectMeshes.canY
    let footprint: Float = 0.045 * ObjectMeshes.canR
    private let minHeightRatio: Float = 0.13
    private static var labelTextures: [UInt64: TextureResource] = [:]

    private let fx: SceneFX
    private let look: Look
    private var rng = SplitMix64(seed: 0)
    private let can: DeformableMesh
    private let puddle: ModelEntity
    private var tab = ModelEntity()
    /// Dark radial crease marks on the lid, one per buckle, so top-down it reads "crushed can" (FOLD-REVIEW-2 #9,
    /// FOLD-REVIEW-3 N10). They ride the lid as it drops, dents, ovalises and shoves sideways.
    private let lidMarks = Entity()
    private var creases: [(model: ModelEntity, angle: Float, radius: Float)] = []
    private var fired = 0
    private var phases: [Float] = []
    private var thresholds: [Float] = []
    private var punctured = false
    private var punctureC: Float = 1
    private var puddleT: Float = 0
    private var sprayTime: Float = 0
    private var sprayAngle: Float = 0
    /// Seeded directions: the rim ovalises along `ovalAngle`; the crushed top shoves along `shoveAngle`, so the wall
    /// on the far side folds out past the lid.
    private var ovalAngle: Float = 0
    private var shoveAngle: Float = 0
    /// Latched strain (FOLD-REVIEW-3 N4/N6): the lowest height, the lid dent / ovalisation, and the next band's
    /// pre-buckle, so the reveal is never less crushed than the sealed frame.
    private var lowest: Float = .infinity
    private var topStrain: Float = 0
    private var preBand = -1
    private var prePeak: Float = 0
    private var lastShort: Float = -1
    private var spread: Float = 1
    private let fizz: (drop: UIColor, puddle: UIColor)

    /// Straight body between the bottom and shoulder bevels, split into five fold bands (top-down).
    static let bodyBottom: Float = ObjectMeshes.canBodyBottom
    static let bodyTop: Float = ObjectMeshes.canBodyTop
    static let folds = 5
    static var foldWidth: Float { (bodyTop - bodyBottom) / Float(folds) }
    /// The flat lid (inside the rim) and the tab's radius on it.
    static let lidY: Float = 0.1455 * ObjectMeshes.canY
    static let lidRadius: Float = 0.0335 * ObjectMeshes.canR
    static let tabRadius: Float = 0.008 * ObjectMeshes.canR

    var shadowSpread: Float { spread }

    static func profile() -> [SIMD2<Float>] {
        var points: [SIMD2<Float>] = [
            SIMD2(0.000, 0.008), SIMD2(0.018, 0.0065), SIMD2(0.028, 0.002), SIMD2(0.030, 0.000), SIMD2(0.039, 0.0015),
            SIMD2(0.043, 0.005), SIMD2(0.045, 0.011),
        ]
        // Dense straight body so the folds have vertices to bend.
        let rings = 46
        for k in 1..<rings {
            points.append(SIMD2(0.045, bodyBottom + (bodyTop - bodyBottom) * Float(k) / Float(rings)))
        }
        points += [
            SIMD2(0.045, 0.126), SIMD2(0.043, 0.134), SIMD2(0.0385, 0.142), SIMD2(0.036, 0.146), SIMD2(0.0368, 0.148),
            SIMD2(0.036, 0.150), SIMD2(0.0345, 0.149), SIMD2(0.0335, 0.1455), SIMD2(0.000, 0.1455),
        ]
        return points
    }

    /// Material slot by profile band: 0 painted field, 1 white band, 2 drop line, 3 bare aluminium.
    static func slot(_ i: Int, _ profile: [SIMD2<Float>]) -> UInt8 {
        let y = (profile[i].y + profile[i + 1].y) / 2
        if y < bodyBottom || y > bodyTop { return 3 }
        if y > 0.060 && y < 0.082 { return 1 }
        if y > 0.0835 && y < 0.0875 { return 2 }
        return 0
    }

    init(variant: PressVariant, fx: SceneFX) {
        self.fx = fx
        let look = Look(variant)
        self.look = look
        var rng = SplitMix64(seed: variant.seed ^ 0x50DA)
        let palettes: [(UIColor, UIColor)] = [
            (UIColor(hex: 0xE9F7D9), UIColor(hex: 0xC9EFA0)), (UIColor(hex: 0xFFE0B8), UIColor(hex: 0xFFB347)),
            (UIColor(hex: 0xEBD7FF), UIColor(hex: 0xC77DFF)),
        ]
        if variant.surprise == .cherryFizz {
            fizz = (UIColor(hex: 0xFFC2D1), Palette.cherryFizz)
        } else {
            fizz = palettes[Int(rng.next() % UInt64(palettes.count))]
        }
        phases = (0..<Self.folds).map { _ in Float.random(in: 0...(2 * .pi), using: &rng) }
        sprayAngle = Float.random(in: 0.6...1.4, using: &rng) // toward the camera side (+Z)
        ovalAngle = Float.random(in: 0...(2 * .pi), using: &rng)
        shoveAngle = Float.random(in: 0...(2 * .pi), using: &rng)
        thresholds = PressObjectFactory.thresholds(.sodaCan, variant: variant)

        // Fully printed body (print up to the shoulder; brighter lime, less metallic: VISUAL-REVIEW-1 fix 11).
        // The print texture is created asynchronously (never block main); the plain field shows until it lands.
        let labelSeed = variant.seed % 4
        let cachedLabel = look.golden ? nil : Self.labelTextures[labelSeed]
        let label: PhysicallyBasedMaterial
        if look.golden {
            label = SceneMaterials.gold
        } else if let cachedLabel {
            label = Self.labelMaterial(cachedLabel)
        } else {
            label = SceneMaterials.enamel(UIColor(hex: 0x96DB4E), roughness: 0.22, clearcoat: 1, clearcoatRoughness: 0.06, metallic: 0.35)
        }
        let aluminium = SceneMaterials.pbr(UIColor(hex: 0xD7DBE0), roughness: 0.20, metallic: 1)
        let mesh = MeshCache.mesh("can.body") { ObjectMeshes.canBody() }
        can = DeformableMesh(mesh, materials: [label, aluminium], maxSpread: 1.6)
        puddle = ModelEntity(mesh: MeshKit.spreadDisc(seed: variant.seed &+ 9, height: 1, segments: 64, wobble: 0.13).resource()
                             ?? .generateSphere(radius: 0.01),
                             materials: [look.golden ? SceneMaterials.goldMess
                                         : SceneMaterials.enamel(fizz.puddle, roughness: 0.05, clearcoat: 1, clearcoatRoughness: 0.03,
                                                                 opacity: 0.6)])
        puddle.isEnabled = false
        self.rng = rng
        entity.addChild(can.entity)
        entity.addChild(puddle)
        // Ring-pull tab on the lid.
        tab = Part.add(cached: "can.tab", { MeshKit.roundedBox([0.022, 0.001, 0.012], radius: 0.004, bevel: 0.0004) },
                       aluminium, at: [0.008 * ObjectMeshes.canR, 0.1462 * ObjectMeshes.canY, 0], to: entity)
        entity.addChild(lidMarks)
        entity.orientation = Part.yaw(-15)
        if !look.golden && cachedLabel == nil {
            Task { @MainActor [weak self] in
                guard let texture = await Self.loadLabelTexture(seed: labelSeed), let self else { return }
                self.can.setMaterial(Self.labelMaterial(texture), forSlot: 0)
            }
        }
    }

    private static func labelMaterial(_ texture: TextureResource) -> PhysicallyBasedMaterial {
        var m = SceneMaterials.textured(texture, roughness: 0.22, clearcoat: 1, metallic: 0.35)
        m.clearcoatRoughness = .init(floatLiteral: 0.06)
        return m
    }

    /// The FIZZO print (one of 4 seeded bubble layouts), drawn once and uploaded asynchronously.
    private static func loadLabelTexture(seed: UInt64) async -> TextureResource? {
        if let cached = labelTextures[seed] { return cached }
        let image = RigTextures.canLabel(field: UIColor(hex: 0x96DB4E), drop: UIColor(hex: 0x2F7A1E), seed: 0xF122 &+ seed)
        let texture = await StudioEnvironment.textureAsync(image, name: "can.label.\(seed)")
        labelTextures[seed] = texture
        return texture
    }

    func surfaceHeight(compression c: Float) -> Float {
        // Each fired buckle drops the can a step; between buckles it barely gives (thin-wall rigidity).
        let q = 0.12 * clamp(c, 0, 1) + 0.88 * Float(fired) / Float(Self.folds)
        return restHeight * (1 - (1 - minHeightRatio) * min(q, 1))
    }

    func update(_ state: PressVisualState) {
        // Latched at the deepest crush, so the reveal is never less crushed than the sealed frame (FOLD-REVIEW-3 N6).
        lowest = min(lowest, surfaceHeight(compression: state.compression))
        let h = lowest
        let shortening = restHeight - h
        let strain = max(topStrain, CanCrush.topStrain(compression: state.compression))
        let previousPre = preBand == fired ? prePeak : -1
        let pre = preBuckle(compression: state.compression)
        if abs(shortening - lastShort) > 0.00005 || strain > topStrain + 0.01 || pre > previousPre + 0.01 {
            lastShort = shortening
            topStrain = strain
            deform(shortening: shortening, height: h)
        }
        // Puncture spray and puddle.
        if punctured {
            if sprayTime > 0 && state.dt > 0 {
                sprayTime -= state.dt
                let rate: Float = state.reduceMotion ? 20 : 60
                let count = max(1, Int((rate * state.dt * ParticleSystem.budget).rounded()))
                let foldY = min(h * 0.62, Self.bodyTop)
                let r: Float = 0.061
                let at = entity.convert(position: [cos(sprayAngle) * r, foldY, sin(sprayAngle) * r], to: fx.root)
                let dirLocal = SIMD3<Float>(cos(sprayAngle), 0.9, sin(sprayAngle))
                let dir = simd_normalize(entity.convert(direction: dirLocal, to: fx.root))
                for _ in 0..<count {
                    let jitter = SIMD3<Float>(Float.random(in: -0.3...0.3, using: &rng), Float.random(in: -0.2...0.3, using: &rng),
                                              Float.random(in: -0.3...0.3, using: &rng))
                    let v = simd_normalize(dir + jitter) * 0.75 * fx.motionScale.squareRoot() * Float.random(in: 0.6...1.2, using: &rng)
                    let kind: ParticleKind = rng.next() % 3 == 0 ? .droplet : .fizz
                    fx.particles.emit(kind, at: at, velocity: v, color: look.tint(fizz.drop),
                                      size: Float.random(in: 0.004...0.008, using: &rng), life: 0.7, rng: &rng)
                }
            }
            puddleT = max(puddleT, clamp((state.compression - punctureC) / max(1 - punctureC, 0.05), 0, 1))
            let radius = 0.06 + 0.022 * puddleT // ≥ 1.3× the can footprint at full press (FOLD-REVIEW-1 #2); latched
            puddle.isEnabled = true
            puddle.scale = SIMD3(radius, 0.0015, radius * 0.9)
            spread = max(spread, radius / footprint)
        }
    }

    /// Latched 0…1 progress from the last fired buckle toward the next one: that band pre-buckles before it fires.
    private func preBuckle(compression c: Float) -> Float {
        if preBand != fired {
            preBand = fired
            prePeak = 0
        }
        guard fired < Self.folds, fired < thresholds.count else { return 0 }
        let next = thresholds[fired]
        let previous = fired > 0 ? thresholds[fired - 1] : max(next - 0.24, 0.02)
        prePeak = max(prePeak, clamp((c - previous) / max(next - previous, 0.02), 0, 1))
        return prePeak
    }

    /// Distributes the shortening: a small uniform elastic part, the rest folded into the fired bands top-down.
    /// Progressive top-down cues (FOLD-REVIEW-3 N4/N10), so the can never jumps from intact to a "steel bowl":
    ///  • from first contact the rim ovalises and the lid dents (latched `topStrain`);
    ///  • the next band pre-buckles in shallow lobes as the press nears its threshold;
    ///  • a fired band folds outward like a hinge (six diamond lobes, deepest on the far side of the shove), and the
    ///    crushed top shoves sideways, so one wall folds out past the lid as a crumpled ring of label green;
    ///  • past the fifth buckle the stack flattens into a ridged disc (the uniform elastic part).
    private func deform(shortening: Float, height: Float) {
        let w = Self.foldWidth
        let capacity = w * 0.8
        var remaining = max(shortening, 0)
        var collapse = [Float](repeating: 0, count: Self.folds)
        for k in 0..<min(fired, Self.folds) {
            let a = min(remaining, capacity)
            collapse[k] = a
            remaining -= a
        }
        let folded = collapse.reduce(0, +)
        let elasticScale = height / max(restHeight - folded, 1e-4)
        let foldedShare = folded / (capacity * Float(Self.folds))
        let oval = CanCrush.ovalisation * topStrain
        let dent = CanCrush.lidDent(topStrain: topStrain, foldedShare: foldedShare)
        let nextBand = (preBand == fired && fired < Self.folds) ? fired : -1
        let pre: Float = nextBand >= 0 ? prePeak : 0
        let shove = CanCrush.shovePerBand
        let shoveDir = SIMD2<Float>(cos(shoveAngle), sin(shoveAngle))
        let farSide = shoveAngle + .pi
        let ovalAngle = self.ovalAngle
        let phases = self.phases
        let folds = Self.folds
        let bodyTop = Self.bodyTop
        let lidY = Self.lidY
        let lidR = Self.lidRadius
        var maxBulge: Float = 0
        can.update { p in
            let r = (p.x * p.x + p.z * p.z).squareRoot()
            let theta = atan2(p.z, p.x)
            var drop: Float = 0
            var shift: Float = 0
            var radial: Float = 1
            // Bands are numbered top-down; walk them bottom-up to accumulate the drop and the shove.
            for k in stride(from: folds - 1, through: 0, by: -1) {
                let bandTop = bodyTop - w * Float(k)
                let bandBottom = bandTop - w
                let a = collapse[k]
                if a > 0 {
                    let push = shove * a / capacity
                    if p.y >= bandTop {
                        drop += a
                        shift += push
                    } else if p.y > bandBottom {
                        let u = (p.y - bandBottom) / w
                        drop += a * u
                        shift += push * u * u * (3 - 2 * u)
                        // Hinge fold: each half of the band swings out by √(w² − (w − a)²) / 2.
                        let depth = 0.5 * max(w * w - (w - a) * (w - a), 0).squareRoot()
                        let lobes = 0.65 + 0.35 * cos(6 * theta + phases[k])
                        let side = 0.8 + 0.4 * cos(theta - farSide)
                        radial += depth * lobes * side * sin(.pi * u) / max(r, 0.01)
                    }
                } else if k == nextBand, p.y > bandBottom, p.y < bandTop {
                    let u = (p.y - bandBottom) / w
                    let lobes = 0.5 + 0.5 * cos(6 * theta + phases[k])
                    radial += CanCrush.preBuckleDepth * pre * pre * lobes * sin(.pi * u) / max(r, 0.01)
                }
            }
            // The top band, shoulder, rim and lid ovalise (cos 2θ: one axis out, the other in).
            let blend = clamp((p.y - (bodyTop - w)) / w, 0, 1)
            radial *= 1 + oval * blend * cos(2 * (theta - ovalAngle))
            var y = p.y
            if p.y > lidY - 0.0002 && r < lidR {
                y -= dent * (1 - r / lidR)
            }
            y = (y - drop) * elasticScale
            maxBulge = max(maxBulge, radial)
            return SIMD3(p.x * radial + shoveDir.x * shift, y, p.z * radial + shoveDir.y * shift)
        }
        let topShift = shoveDir * (shove * folded / capacity)
        spread = max(spread, min(maxBulge + simd_length(topShift) / footprint, 1.45))

        // The tab and the crease marks ride the lid: dropped, dented (tilted with the dent), ovalised and shoved.
        let lidTop = (lidY - folded) * elasticScale
        let slope = atan(dent * elasticScale / lidR)
        let tilt = simd_quatf(angle: slope, axis: [0, 0, 1])
        lidMarks.position = SIMD3(topShift.x, lidTop, topShift.y)
        for crease in creases {
            let rc = crease.radius * (1 + oval * cos(2 * (crease.angle - ovalAngle)))
            let sink = dent * max(1 - rc / lidR, 0) * elasticScale
            crease.model.position = SIMD3(cos(crease.angle) * rc, 0.0005 - sink, sin(crease.angle) * rc)
            crease.model.orientation = simd_quatf(angle: -crease.angle, axis: [0, 1, 0]) * tilt
        }
        let tabR = Self.tabRadius * (1 + oval * cos(2 * ovalAngle))
        let tabSink = dent * max(1 - Self.tabRadius / lidR, 0) * elasticScale
        tab.position = SIMD3(tabR + topShift.x, lidTop + 0.00065 - tabSink, topShift.y)
        tab.orientation = tilt
    }

    func fracture(index: Int, isFailure: Bool, state: PressVisualState) {
        fired = max(fired, index + 1)
        let creaseAngle = phases[index % phases.count] + Float(index) * 1.3
        // A dark radial crease on the lid, longer and darker than round 2's (it read as nothing from above); placed on the
        // dented lid by the next `deform`.
        let crease = MeshKit.model(MeshKit.roundedBox([0.016, 0.0009, 0.0022], radius: 0.0005, bevel: 0.0002),
                                   material: SceneMaterials.pbr(UIColor(hex: 0x3A3C42), roughness: 0.55, metallic: 0.4))
        crease.position = [cos(creaseAngle) * CanCrush.creaseRadius, 0.0005, sin(creaseAngle) * CanCrush.creaseRadius]
        crease.orientation = simd_quatf(angle: -creaseAngle, axis: [0, 1, 0])
        lidMarks.addChild(crease)
        creases.append((model: crease, angle: creaseAngle, radius: CanCrush.creaseRadius))
        lastShort = -1
        // A glint where the fold creases.
        let foldY = Self.bodyTop - Self.foldWidth * (Float(index) + 0.5)
        let at = entity.convert(position: [0, min(foldY, state.ramFace - 0.005), 0.057], to: fx.root)
        fx.particles.burst(.glint, count: 2, at: at, speed: 0.08, colors: [UIColor(hex: 0xFFFFFF)],
                           size: 0.002...0.003, upBias: 0.2, life: 0.25, rng: &rng)
        if isFailure {
            punctured = true
            punctureC = state.compression
            sprayTime = state.reduceMotion ? 0.35 : 0.7
            // The initial "pssht": a burst of foam.
            let spray = entity.convert(position: [cos(sprayAngle) * 0.058, min(foldY, 0.085), sin(sprayAngle) * 0.058], to: fx.root)
            fx.particles.burst(.fizz, count: 12, at: spray, speed: 0.5 * max(fx.motionScale, 0.4), colors: [look.tint(fizz.drop)],
                               size: 0.004...0.007, spread: 0.004, upBias: 0.3, life: 0.6, rng: &rng)
            fx.particles.burst(.crumb, count: 6, at: spray, speed: 0.25 * max(fx.motionScale, 0.4), colors: [UIColor(hex: 0xF8F8F8)],
                               size: 0.003...0.005, spread: 0.004, upBias: 0.3, rng: &rng)
        }
    }
}

/// The can's progressive crush numbers (FOLD-REVIEW-3 N4/N10), pure so SquishTests can pin them. Metres, can-local.
enum CanCrush {
    /// Rim / top-band ovalisation (cos 2θ amplitude) at full top strain.
    static let ovalisation: Float = 0.055
    /// Sideways shove of everything above one fully collapsed band; five bands ≈ 11 mm.
    static let shovePerBand: Float = 0.0022
    /// Depth of the next band's pre-buckle lobes as it reaches its threshold.
    static let preBuckleDepth: Float = 0.0022
    /// Where the lid creases sit (centre radius; the lid is r 0.041).
    static let creaseRadius: Float = 0.026

    /// The rim ovalises and the lid dents from first contact: 0 at c ≤ 0.04, 1 at c 0.30 (about the first buckle).
    static func topStrain(compression c: Float) -> Float {
        clamp((c - 0.04) / 0.26, 0, 1)
    }

    /// Lid dent depth at the centre: 3 mm from the top strain, plus 2.5 mm as the bands fold.
    static func lidDent(topStrain: Float, foldedShare: Float) -> Float {
        0.0030 * clamp(topStrain, 0, 1) + 0.0025 * clamp(foldedShare, 0, 1)
    }
}
