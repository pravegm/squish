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
    /// The torn, curled metal at the puncture (3D-art round), riding the deformed wall at `tearVertex`.
    private var tear: Entity?
    private var tearVertex = -1

    private let fx: SceneFX
    private let look: Look
    private var rng = SplitMix64(seed: 0)
    private let can: DeformableMesh
    private let puddle: ModelEntity
    private var tab = ModelEntity()
    /// Crumpled grey chevron folds on the shoulder, two per buckle ("5 BUCKLES" = 10 marks), so top-down it reads
    /// "crushed can" (FOLD-REVIEW-4 F7: the old straight black bars on the lid read as clock hands round the tab).
    /// They ride the shoulder as it drops, flattens, ovalises and shoves sideways.
    private let shoulderMarks = Entity()
    private var creases: [(mark: Entity, angle: Float)] = []
    private var creaseMaterial: PhysicallyBasedMaterial?
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
    /// The storyboard (OBJECT-STORYBOARDS §7): a still can with a rim glint, label wrinkles, a hiss, the fizz puddle
    /// squeezed out from under the crushed base.
    private let life: ObjectLife
    private var story: StoryCursor
    private let ooze: OozeRing
    private var gave = false

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
        // EXPERIENCE-REVIEW-1 #5: the fizz matches the can's flavour (it was a seeded lime / orange / berry in an always-
        // lime FIZZO can). The draw stays, so every other seeded choice of this press is unchanged.
        let chosen: (drop: UIColor, puddle: UIColor)
        _ = rng.next()
        if variant.surprise == .cherryFizz {
            chosen = (UIColor(hex: 0xFFC2D1), Palette.cherryFizz)
        } else {
            chosen = palettes[0]
        }
        fizz = chosen
        phases = (0..<Self.folds).map { _ in Float.random(in: 0...(2 * .pi), using: &rng) }
        sprayAngle = Float.random(in: 0.6...1.4, using: &rng) // toward the camera side (+Z)
        ovalAngle = Float.random(in: 0...(2 * .pi), using: &rng)
        shoveAngle = Float.random(in: 0...(2 * .pi), using: &rng)
        thresholds = PressObjectFactory.thresholds(.sodaCan, variant: variant)

        // Fully printed body (print up to the shoulder; brighter lime, less metallic: VISUAL-REVIEW-1 fix 11).
        // The print texture is created asynchronously (never block main); the plain field shows until it lands. The
        // 3D-art round's print carries fine detail (halftone, nutrition panel, barcode, small print).
        let labelSeed = variant.seed % 4
        let cachedLabel = look.golden ? nil : SurfaceDetail.cached("can.label.fine.\(labelSeed)")
        let label: PhysicallyBasedMaterial
        if look.golden {
            label = SceneMaterials.gold
        } else if let cachedLabel {
            label = Self.labelMaterial(cachedLabel)
        } else {
            label = SceneMaterials.enamel(UIColor(hex: 0x96DB4E), roughness: 0.22, clearcoat: 1, clearcoatRoughness: 0.06, metallic: 0.35)
        }
        let cachedLid = SurfaceDetail.cached("can.lid.colour")
        let aluminium = look.golden ? SceneMaterials.pbr(UIColor(hex: 0xD7DBE0), roughness: 0.20, metallic: 1)
            : Self.endMaterial(colour: cachedLid, normal: SurfaceDetail.cached("can.lid.normal"))
        let mesh = MeshCache.mesh("can.body") { ObjectMeshes.canBody() }
        can = DeformableMesh(mesh, materials: [label, aluminium], maxSpread: 1.6)
        puddle = ModelEntity(mesh: MeshKit.spreadDisc(seed: variant.seed &+ 9, height: 1, segments: 64, wobble: 0.13).resource()
                             ?? .generateSphere(radius: 0.01),
                             materials: [look.golden ? SceneMaterials.goldMess
                                         : SceneMaterials.enamel(fizz.puddle, roughness: 0.05, clearcoat: 1, clearcoatRoughness: 0.03,
                                                                 opacity: 0.6)])
        life = ObjectLife(seed: variant.seed, idle: .still, amount: 0, rate: 0.3, pulseHz: 7, pulseDamping: 0.5)
        story = StoryCursor(.sodaCan, seed: variant.seed)
        let plate = GlassDebris.containment(restHeight: 0.150 * ObjectMeshes.canY, anvilHalf: PressRig.anvilHalf, padding: 0)
        ooze = OozeRing(seed: variant.seed ^ 0x50DB, count: 5, radii: SIMD2(repeating: 0.057), reach: 0.010...0.024,
                        width: 0.014...0.024, thickness: 0.0016, maxRadius: min(plate.x, plate.y) * 0.95,
                        material: look.golden ? SceneMaterials.goldMess
                            : SceneMaterials.enamel(chosen.puddle, roughness: 0.05, clearcoat: 1, clearcoatRoughness: 0.03, opacity: 0.6),
                        y: 0.0002)
        puddle.isEnabled = false
        self.rng = rng
        life.node.addChild(can.entity)
        entity.addChild(life.node)
        entity.addChild(ooze.root)
        entity.addChild(puddle)
        // Ring-pull tab on the lid.
        tab = Part.add(cached: "can.tab", { MeshKit.roundedBox([0.022, 0.001, 0.012], radius: 0.004, bevel: 0.0004) },
                       aluminium, at: [0.008 * ObjectMeshes.canR, 0.1462 * ObjectMeshes.canY, 0], to: entity)
        entity.addChild(shoulderMarks)
        // The puncture's torn metal is built now (hidden), so the break costs no mesh work: buckle 3 (the failure)
        // folds band 2, at the spray's side.
        buildTear(foldY: Self.bodyTop - Self.foldWidth * 2.5)
        entity.orientation = Part.yaw(-15)
        if !look.golden && cachedLabel == nil {
            Task { @MainActor [weak self] in
                guard let texture = await SurfaceDetail.canLabel(seed: labelSeed), let self else { return }
                self.can.setMaterial(Self.labelMaterial(texture), forSlot: 0)
            }
        }
        if !look.golden && cachedLid == nil {
            Task { @MainActor [weak self] in
                let lid = await SurfaceDetail.canLid()
                guard let self else { return }
                self.can.setMaterial(Self.endMaterial(colour: lid.colour, normal: lid.normal), forSlot: 1)
            }
        }
    }

    private static func labelMaterial(_ texture: TextureResource) -> PhysicallyBasedMaterial {
        var m = SceneMaterials.textured(texture, roughness: 0.22, clearcoat: 1, metallic: 0.35)
        m.baseColor = .init(tint: .white, texture: SurfaceDetail.wrapped(texture))
        m.clearcoatRoughness = .init(floatLiteral: 0.06)
        return m
    }

    /// The bare aluminium ends: brushed, turned metal with the lid's countersink, scored opening and rivet (planar UVs).
    private static func endMaterial(colour: TextureResource?, normal: TextureResource?) -> PhysicallyBasedMaterial {
        var m = SceneMaterials.pbr(UIColor(hex: 0xD7DBE0), roughness: 0.24, metallic: 1)
        if let colour { m.baseColor = .init(tint: .white, texture: SurfaceDetail.clamped(colour)) }
        if let normal { m.normal = .init(texture: SurfaceDetail.clamped(normal)) }
        return m
    }

    func surfaceHeight(compression c: Float) -> Float {
        // Each fired buckle drops the can a step; between buckles it barely gives (thin-wall rigidity).
        let q = 0.12 * clamp(c, 0, 1) + 0.88 * Float(fired) / Float(Self.folds)
        return restHeight * (1 - (1 - minHeightRatio) * min(q, 1))
    }

    func update(_ state: PressVisualState) {
        if life.update(state) {
            BeatFX.glint(fx, at: [-0.03, Self.lidY + 0.003, -0.03], in: entity, golden: look.golden, rng: &rng)
        }
        for beat in story.advance(to: state.compression) { onBeat(beat, state: state) }
        ooze.update(compression: state.compression, spread: min(spread, 1.3))
        // Latched at the deepest crush, so the reveal is never less crushed than the sealed frame (FOLD-REVIEW-3 N6).
        lowest = min(lowest, surfaceHeight(compression: state.compression))
        let h = lowest
        let shortening = restHeight - h
        let strain = max(topStrain, CanCrush.topStrain(compression: state.compression))
        let previousPre = preBand == fired ? prePeak : -1
        var pre = preBuckle(compression: state.compression)
        // The fight (EXPERIENCE-REVIEW-1 #1): straining before the puncture the next band bows out further and the lid
        // tinks in; the give squirts the fizz puddle out from under the base in the burst's frame.
        if state.resistanceBulge > 0 && fired < Self.folds {
            prePeak = max(prePeak, state.resistanceBulge)
            pre = prePeak
            topStrain = max(topStrain, min(1, 0.5 + 0.5 * state.resistanceBulge))
        }
        if state.collapseLead > 0 && !gave {
            gave = true
            ooze.shove(0.3)
            life.kick(0.9)
        }
        if abs(shortening - lastShort) > 0.00005 || strain > topStrain + 0.01 || pre > previousPre + 0.01 {
            lastShort = shortening
            topStrain = max(topStrain, strain)
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
                        // Hinge fold: each half of the band swings out by √(w² − (w − a)²) / 2, along a sharp fold line
                        // (3D-art round: a pleat, not a smooth bulge), in diamond lobes with sharp ridges and crumples.
                        let depth = 0.5 * max(w * w - (w - a) * (w - a), 0).squareRoot()
                        let lobes = CanCrush.pleat(theta: theta, band: k, phase: phases[k])
                        let side = 0.8 + 0.4 * cos(theta - farSide)
                        // EXPERIENCE-REVIEW-1 #5: the folds splay well out past the lid, so from above the crushed can is a
                        // ring of crumpled label round the top, not a lid on a ring.
                        radial += depth * CanCrush.foldSpread * lobes * side * CanCrush.foldProfile(u) / max(r, 0.01)
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
                // The lid buckles in radial creases as the can folds under it (EXPERIENCE-REVIEW-1 #5).
                y -= CanCrush.lidCrease(theta: theta, rho: r / lidR, folded: foldedShare, phase: phases[0])
            }
            // The crushed top tilts: its far side is driven down (only ever down, so it stays under the plate).
            y -= blend * CanCrush.topTilt(theta: theta, rho: min(r / 0.055, 1), folded: foldedShare, toward: farSide)
            y = (y - drop) * elasticScale
            maxBulge = max(maxBulge, radial)
            return SIMD3(p.x * radial + shoveDir.x * shift, y, p.z * radial + shoveDir.y * shift)
        }
        let topShift = shoveDir * (shove * folded / capacity)
        spread = max(spread, min(maxBulge + simd_length(topShift) / footprint, 1.45))

        // The tab rides the lid: dropped, dented (tilted with the dent), ovalised and shoved.
        let lidTop = (lidY - folded) * elasticScale
        let slope = atan(dent * elasticScale / lidR)
        let tilt = simd_quatf(angle: slope, axis: [0, 0, 1])
        // The chevrons ride the shoulder exactly as its vertices do: everything above the bands drops by `folded`,
        // scales by `elasticScale` (which also flattens the shoulder's slope), ovalises and shoves with the top.
        let shoulder = CanCrush.shoulder(radius: CanCrush.chevronRadius)
        let pitch = atan(tan(shoulder.slope) * elasticScale)
        shoulderMarks.position = SIMD3(topShift.x, 0, topShift.y)
        for crease in creases {
            let rc = CanCrush.chevronRadius * (1 + oval * cos(2 * (crease.angle - ovalAngle)))
            let y = (shoulder.y - folded) * elasticScale
            crease.mark.position = SIMD3(cos(crease.angle) * rc, y, sin(crease.angle) * rc)
            // Local +X runs down the slope (outward), local +Y is the shoulder's normal.
            crease.mark.orientation = simd_quatf(angle: -crease.angle, axis: [0, 1, 0]) * simd_quatf(angle: -pitch, axis: [0, 0, 1])
        }
        let tabR = Self.tabRadius * (1 + oval * cos(2 * ovalAngle))
        let tabSink = dent * max(1 - Self.tabRadius / lidR, 0) * elasticScale
        tab.position = SIMD3(tabR + topShift.x, lidTop + 0.00065 - tabSink, topShift.y)
        tab.orientation = tilt
        placeTear()
    }

    /// The torn hole rides the deformed wall: at its vertex, along its normal (the fold may turn it toward the plate).
    private func placeTear() {
        guard let tear, tearVertex >= 0, tearVertex < can.current.positions.count else { return }
        let n = can.current.normals[tearVertex]
        let p = can.current.positions[tearVertex]
        let up = simd_length(n) > 1e-5 ? simd_normalize(n) : SIMD3<Float>(cos(sprayAngle), 0, sin(sprayAngle))
        let around = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), up) + SIMD3(1e-5, 0, 0))
        let forward = simd_cross(around, up)
        tear.orientation = simd_quatf(simd_float3x3(columns: (around, up, forward)))
        tear.position = p + up * 0.0002
    }

    /// The puncture (3D-art round): a jagged dark hole in the fold with torn, curled aluminium petals round it, curling
    /// out where the fizz burst through.
    private func buildTear(foldY: Float) {
        guard tear == nil else { return }
        // The rest vertex of the printed wall nearest the puncture point.
        var best = -1
        var bestD: Float = .infinity
        let target = SIMD3<Float>(cos(sprayAngle) * 0.055, foldY, sin(sprayAngle) * 0.055)
        for (i, p) in can.rest.positions.enumerated() where p.y > Self.bodyBottom && p.y < Self.bodyTop {
            let d = simd_distance(p, target)
            if d < bestD {
                bestD = d
                best = i
            }
        }
        guard best >= 0 else { return }
        tearVertex = best
        let root = Entity()
        let hole = Part.add(cached: "can.tear.hole", { MeshKit.spreadDisc(seed: 0x7EA4, height: 1, segments: 48, wobble: 0.3) },
                            SceneMaterials.unlit(UIColor(hex: 0x16181C)), to: root)
        hole.scale = SIMD3(0.0042, 0.0004, 0.0032)
        let metal = look.golden ? SceneMaterials.gold : SceneMaterials.pbr(UIColor(hex: 0xE4E7EB), roughness: 0.22, metallic: 1)
        let printed = look.golden ? SceneMaterials.gold
            : SceneMaterials.enamel(UIColor(hex: 0x96DB4E), roughness: 0.25, clearcoat: 1, clearcoatRoughness: 0.08, metallic: 0.35)
        for k in 0..<CanCrush.petals {
            let a = 2 * Float.pi * Float(k) / Float(CanCrush.petals) + Float.random(in: -0.3...0.3, using: &rng)
            let petal = SlotMeshes.entity("can.tear.petal.\(k % 3)", { CanCrush.petalMesh(seed: UInt64(k % 3)) },
                                          materials: [printed, metal])
            let reach = Float.random(in: 0.8...1.25, using: &rng)
            petal.orientation = simd_quatf(angle: -a, axis: [0, 1, 0])
            petal.position = SIMD3(cos(a) * 0.0034, 0.0002, sin(a) * 0.0026)
            petal.scale = SIMD3(reach, 1, Float.random(in: 0.8...1.2, using: &rng))
            root.addChild(petal)
        }
        root.isEnabled = false
        life.node.addChild(root)
        tear = root
    }

    /// One crumpled chevron fold: two short dark-grey (#5A5E66 at 0.6, not black) arms meeting in a shallow V, lengths
    /// and angles seeded. Local frame: +X down the shoulder's slope, +Z round the can, +Y the shoulder's normal.
    private func chevron() -> Entity {
        let material: PhysicallyBasedMaterial
        if let creaseMaterial {
            material = creaseMaterial
        } else {
            let made = SceneMaterials.pbr(UIColor(hex: 0x5A5E66), roughness: 0.5, metallic: 0.4, opacity: 0.6)
            creaseMaterial = made
            material = made
        }
        let arm = CanCrush.chevronArm
        let barMesh = MeshCache.resource("can.chevron.bar") { MeshKit.roundedBox([arm, 0.0008, 0.0016], radius: 0.0005, bevel: 0.0002) }
            ?? MeshResource.generateBox(size: 0.001)
        let mark = Entity()
        let apex = SIMD3<Float>(-arm * sin(CanCrush.chevronAngle) / 2, 0.0005, 0)
        for side: Float in [-1, 1] {
            let length = arm * Float.random(in: 0.85...1.1, using: &rng)
            let angle = CanCrush.chevronAngle + Float.random(in: -0.12...0.12, using: &rng)
            // The arm leaves the apex outward (down the slope) and sideways (round the can).
            let dir = SIMD3<Float>(sin(angle), 0, side * cos(angle))
            let bar = ModelEntity(mesh: barMesh, materials: [material])
            bar.scale = SIMD3(length / arm, 1, 1)
            bar.orientation = simd_quatf(angle: atan2(-dir.z, dir.x), axis: [0, 1, 0])
            bar.position = apex + dir * (length / 2)
            mark.addChild(bar)
        }
        return mark
    }

    /// One label wrinkle on the shoulder (a storyboard `.crease`), placed by the next `deform`.
    private func addChevron(angle: Float) {
        let mark = chevron()
        let rest = CanCrush.shoulder(radius: CanCrush.chevronRadius)
        mark.position = [cos(angle) * CanCrush.chevronRadius, rest.y, sin(angle) * CanCrush.chevronRadius]
        mark.orientation = simd_quatf(angle: -angle, axis: [0, 1, 0]) * simd_quatf(angle: -rest.slope, axis: [0, 0, 1])
        shoulderMarks.addChild(mark)
        creases.append((mark: mark, angle: angle))
        lastShort = -1
    }

    /// One storyboard beat (OBJECT-STORYBOARDS §7).
    private func onBeat(_ beat: StoryBeat, state: PressVisualState) {
        let golden = look.golden
        let top = min(Self.lidY, lowest.isFinite ? lowest : Self.lidY)
        switch beat.kind {
        case .kiss:
            // The rim ring kisses the plate: a glint runs round it.
            for k in 0..<3 {
                let a = ovalAngle + Float(k) * 2.1
                BeatFX.glint(fx, at: [cos(a) * 0.043, top + 0.002, sin(a) * 0.043], in: entity, count: 1, golden: golden, rng: &rng)
            }
            life.kick(0.25)
        case .strain:
            // The lid "tinks" in.
            topStrain = max(topStrain, 0.35)
            lastShort = -1
            life.kick(0.3)
            BeatFX.glint(fx, at: [0, top + 0.001, 0], in: entity, count: 1, golden: golden, rng: &rng)
        case .crease:
            addChevron(angle: phases[beat.ordinal % phases.count] + 2.4 + Float(beat.ordinal) * 1.7)
            life.kick(0.3)
        case .sheen:
            let a = sprayAngle + Float.random(in: -0.6...0.6, using: &rng)
            BeatFX.glint(fx, at: [cos(a) * 0.056, min(top * 0.6, 0.08), sin(a) * 0.056], in: entity, count: 2, golden: golden, rng: &rng)
        case .buckle:
            life.tremor(0.2, level: 0.6)
            prePeak = max(prePeak, 0.6)
            lastShort = -1
        case .hiss, .tell:
            // Fizz leaks round the tab before the wall gives (or keeps leaking after).
            let at = entity.convert(position: tab.position + SIMD3(0, 0.002, 0), to: fx.root)
            fx.particles.burst(.fizz, count: beat.kind == .tell ? 3 : 5, at: at, speed: 0.08, colors: [look.tint(fizz.drop)],
                               size: 0.003...0.005, spread: 0.004, upBias: 0.7, life: 0.5, rng: &rng)
            if beat.kind == .tell { life.tremor(0.3) }
        case .ooze:
            if punctured {
                if let tip = ooze.emit(at: state.compression) {
                    let d = simd_length(SIMD2(tip.x, tip.z)) > 1e-5 ? simd_normalize(SIMD2(tip.x, tip.z)) : SIMD2<Float>(1, 0)
                    BeatFX.fling(fx, at: tip, in: entity, direction: d, count: 1, colors: [look.tint(fizz.drop)], speed: 0.1, rng: &rng)
                }
            } else {
                let at = entity.convert(position: tab.position, to: fx.root)
                fx.particles.burst(.fizz, count: 4, at: at, speed: 0.08, colors: [look.tint(fizz.drop)], size: 0.003...0.005,
                                   upBias: 0.7, life: 0.5, rng: &rng)
            }
        case .fling:
            let foldY = min(top * 0.62, Self.bodyTop)
            let a = sprayAngle + Float.random(in: -0.8...0.8, using: &rng)
            BeatFX.fling(fx, at: [cos(a) * 0.06, foldY, sin(a) * 0.06], in: entity, direction: SIMD2(cos(a), sin(a)), count: 4,
                         colors: [look.tint(fizz.drop)], speed: 0.3, rng: &rng)
        case .settle:
            BeatFX.glint(fx, at: [0, top + 0.001, 0], in: entity, count: 2, golden: golden, rng: &rng)
            let at = entity.convert(position: [0, top, 0.05], to: fx.root)
            fx.particles.burst(.fizz, count: 2, at: at, speed: 0.04, colors: [look.tint(fizz.drop)], size: 0.003...0.004,
                               upBias: 0.8, life: 0.5, rng: &rng)
        default:
            life.kick(0.3)
        }
    }

    func handle(_ event: PressEvent, state: PressVisualState) {
        if event == .preFailureTell { life.tremor(0.25) }
    }

    func fracture(index: Int, isFailure: Bool, state: PressVisualState) {
        fired = max(fired, index + 1)
        life.kick(isFailure ? 0.9 : 0.6)
        // Two crumpled chevron folds per buckle on the shoulder, roughly opposite each other; placed on the flattened
        // shoulder by the next `deform`.
        let first = phases[index % phases.count] + Float(index) * 1.3
        for k in 0..<CanCrush.chevronsPerBuckle {
            let angle = first + Float(k) * (2 * .pi / Float(CanCrush.chevronsPerBuckle)) + Float.random(in: -0.35...0.35, using: &rng)
            let mark = chevron()
            let rest = CanCrush.shoulder(radius: CanCrush.chevronRadius)
            mark.position = [cos(angle) * CanCrush.chevronRadius, rest.y, sin(angle) * CanCrush.chevronRadius]
            mark.orientation = simd_quatf(angle: -angle, axis: [0, 1, 0]) * simd_quatf(angle: -rest.slope, axis: [0, 0, 1])
            shoulderMarks.addChild(mark)
            creases.append((mark: mark, angle: angle))
        }
        lastShort = -1
        // A glint where the fold creases.
        let foldY = Self.bodyTop - Self.foldWidth * (Float(index) + 0.5)
        let at = entity.convert(position: [0, min(foldY, state.ramFace - 0.005), 0.057], to: fx.root)
        fx.particles.burst(.glint, count: 2, at: at, speed: 0.08, colors: [UIColor(hex: 0xFFFFFF)],
                           size: 0.002...0.003, upBias: 0.2, life: 0.25, rng: &rng)
        if isFailure {
            punctured = true
            punctureC = state.compression
            tear?.isEnabled = true
            placeTear()
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
    /// The chevron folds sit on the sloped shoulder (between the rim bead at r ≈ 0.045 and the body at r 0.055), clear
    /// of the lid (r 0.041) and the tab, so they can't read as clock hands (FOLD-REVIEW-4 F7).
    static let chevronRadius: Float = 0.050
    static let chevronsPerBuckle = 2
    /// Each chevron is two ~6 mm arms meeting at ±35° to the can's circumference.
    static let chevronArm: Float = 0.006
    static let chevronAngle: Float = 35 * .pi / 180

    /// Height and slope (radians from horizontal) of the rest shoulder at `radius`, from the can's lathe profile
    /// (the segment between the body top and the rim bead).
    static func shoulder(radius r: Float) -> (y: Float, slope: Float) {
        let profile = ObjectMeshes.canProfile()
        let top = ObjectMeshes.canBodyTop
        for i in 0..<(profile.count - 1) where profile[i].y >= top - 1e-5 {
            let a = profile[i]
            let b = profile[i + 1]
            // Past the shoulder: the rim bead turns back outward.
            guard b.x < a.x else { break }
            if r <= a.x && r >= b.x {
                let t = (a.x - r) / max(a.x - b.x, 1e-6)
                return (a.y + (b.y - a.y) * t, atan2(b.y - a.y, a.x - b.x))
            }
        }
        return (top, 0)
    }

    /// The rim ovalises and the lid dents from first contact: 0 at c ≤ 0.04, 1 at c 0.30 (about the first buckle).
    static func topStrain(compression c: Float) -> Float {
        clamp((c - 0.04) / 0.26, 0, 1)
    }

    /// Lid dent depth at the centre: 3 mm from the top strain, plus 2.5 mm as the bands fold.
    static func lidDent(topStrain: Float, foldedShare: Float) -> Float {
        0.0030 * clamp(topStrain, 0, 1) + 0.0025 * clamp(foldedShare, 0, 1)
    }

    // MARK: Read from above (EXPERIENCE-REVIEW-1 #5)

    /// How far out a fired band's hinge folds splay, × the hinge's own depth (the folds of a crushed can stick out
    /// well past its lid: ~1.3–1.4× the can's radius at full crush).
    static let foldSpread: Float = 2.4
    /// The lid's radial creases: how deep (metres at the rim, full fold) and how many.
    static let lidCreaseDepth: Float = 0.0038
    static let lidCreases = 5
    /// How far the crushed top tilts down on its far side at full fold (metres).
    static let topTiltDepth: Float = 0.004

    /// How far (metres, down) a lid point at angle `theta` and radius share `rho` sinks into its creases once the bands
    /// have folded `folded` (0…1): a shallow dish plus `lidCreases` seeded radial grooves, deepest toward the rim.
    static func lidCrease(theta: Float, rho: Float, folded: Float, phase: Float) -> Float {
        let f = clamp(folded, 0, 1)
        guard f > 0 else { return 0 }
        var groove: Float = 0
        for k in 0..<lidCreases {
            let a = phase + 2 * .pi * Float(k) / Float(lidCreases) + 0.35 * sin(Float(k) * 2.3 + phase)
            var d = abs(theta - a).truncatingRemainder(dividingBy: 2 * .pi)
            d = min(d, 2 * .pi - d)
            groove = max(groove, exp(-(d / 0.16) * (d / 0.16)))
        }
        return lidCreaseDepth * f * pow(clamp(rho, 0, 1), 0.7) * (0.3 + 0.7 * groove)
    }

    /// How far (metres, down) the crushed top dips at angle `theta`, radius share `rho`, toward `toward` (its far side).
    static func topTilt(theta: Float, rho: Float, folded: Float, toward: Float) -> Float {
        topTiltDepth * clamp(folded, 0, 1) * clamp(rho, 0, 1) * 0.5 * (1 + cos(theta - toward))
    }

    // MARK: Sharp pleats and the torn puncture (3D-art round)

    /// How far round the can a fired band folds out at `theta` (0.25…1): six diamond lobes with *sharp* ridges (the
    /// cusp of 1 − |sin|), offset half a lobe band to band (the diamond pattern of a crushed can), and a finer crumple.
    static func pleat(theta: Float, band: Int, phase: Float) -> Float {
        let offset: Float = band % 2 == 0 ? 0 : .pi / 6
        let ridge = 1 - abs(sin(3 * (theta + offset) + phase))
        let crumple = abs(sin(11 * theta + 1.7 * phase))
        return clamp(0.3 + 0.7 * ridge - 0.12 * crumple + 0.06, 0.2, 1)
    }

    /// The fold's shape up a band (u 0…1): a sharp crease line at its middle (Λ), softened a little.
    static func foldProfile(_ u: Float) -> Float {
        let u = clamp(u, 0, 1)
        return 0.75 * (1 - abs(2 * u - 1)) + 0.25 * sin(.pi * u)
    }

    static let petals = 6

    /// One torn petal of the puncture: a jagged sliver of can wall (printed outside, slot 0; bare aluminium inside and
    /// on its torn edge, slot 1), ~5 mm long, curled outward like torn foil. Local +X runs out from the hole, +Y is out
    /// of the wall.
    static func petalMesh(seed: UInt64) -> MeshData {
        var rng = SplitMix64(seed: seed ^ 0x9E7A)
        let length = Float.random(in: 0.0042...0.0056, using: &rng)
        let width = Float.random(in: 0.0022...0.003, using: &rng)
        let outline: [SIMD2<Float>] = [
            SIMD2(0, -width / 2), SIMD2(length * 0.45, -width * Float.random(in: 0.28...0.4, using: &rng)),
            SIMD2(length, Float.random(in: -0.0004...0.0004, using: &rng)),
            SIMD2(length * 0.5, width * Float.random(in: 0.25...0.42, using: &rng)), SIMD2(0, width / 2),
        ]
        var slab = MeshKit.polygonSlab(outline, thickness: 0.00025, rimInset: 0.0003)
        // Slot 0 is the top face (the printed outside) and the bottom; the bottom shows the inside, so it goes bare too.
        for t in 0..<slab.triangleCount where t < slab.triangleMaterials.count {
            let a = slab.normals[Int(slab.indices[t * 3])]
            if a.y < -0.5 { slab.triangleMaterials[t] = 1 }
        }
        // Curl it outward (toward +y) about a radius of ~0.7 of its length.
        let rho = length * 0.7
        for i in slab.positions.indices {
            let p = slab.positions[i]
            let angle = p.x / rho
            slab.positions[i] = SIMD3((rho - p.y) * sin(angle), rho - (rho - p.y) * cos(angle), p.z)
        }
        slab.recomputeNormals()
        slab.orientToNormals()
        return slab
    }
}
