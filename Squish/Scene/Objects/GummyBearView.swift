import Foundation
import RealityKit
import simd
import UIKit

/// Gummy Bear (bible §4 #8, VISUAL-TARGET §5.8): a sitting, faceless gummy bear built as two pre-split SDF halves
/// (smooth-union blobs clipped at the seam) that read as one glossy bear. Fake SSS: translucent shell over an opaque
/// darker core; it glows more where it's squashed thin.
/// It must never read as the jelly (EXPERIENCE-PLAN §7; OBJECT-STORYBOARDS §8): the jelly wobbles and splats, the gummy
/// is *chewy*. Before the break it stretches sideways (anisotropic, in steps you can see from above) while a pale
/// stress line creeps down its seam; at the failure (~0.36) it splits at the seam and the halves pull apart on chewy
/// strands that thin as the gap opens and snap one by one; at fracture 1 (~0.62) the halves slap down into two chewy
/// pads. No splat, no puddle.
@MainActor
final class GummyBearView: PressObjectView {
    let entity = Entity()
    /// Hero scale ×1.2 (VISUAL-REVIEW-1 fix 6), applied on `entity`.
    static let heroScale: Float = 1.2
    let restHeight: Float = 0.107 * GummyBearView.heroScale
    let footprint: Float = 0.045 * GummyBearView.heroScale
    private let minHeightRatio: Float = 0.14

    private let fx: SceneFX
    private let look: Look
    private var rng = SplitMix64(seed: 0)
    private let bear = Entity()
    private var halves: [Entity] = []
    /// One welded bear for idle and strain: no seam until it breaks (VISUAL-REVIEW-1 fix 11).
    private let welded = Entity()
    private var shells: [ModelEntity] = []
    private var split = false
    private var splitC: Float = 1
    private var slapped = false
    private var slapC: Float = 1
    private var gap = JiggleSpring(value: 0, velocity: 0, omega: 14, zeta: 0.5)
    private var glowStep = -1
    private var spread: Float = 1
    private let shellColour = UIColor(hex: 0xFF5A4E)
    private let rainbow: Bool
    private let life: ObjectLife
    private var story: StoryCursor
    /// The chewy stretch: target and eased anisotropy (x wider, z narrower), latched.
    private var stretchTarget: Float = 0
    private var stretch = JiggleSpring(value: 0, velocity: 0, omega: 9, zeta: 0.55)
    private var stretchFloor: Float = 0
    /// The pale stress line down the seam (shown in steps before the split).
    private var seamLine: [ModelEntity] = []
    private var seamLevel = 0
    /// The strands across the split: (model, height, depth, rest radius, snapped).
    private var strands: [(model: ModelEntity, y: Float, z: Float, radius: Float, snapped: Bool)] = []
    private var tilt: Float = 0
    private var pads: [ModelEntity] = []
    private let gooColors: [UIColor]
    /// The 3D-art round's layers: a sugar-dusted, slightly matte skin (colour, crystal normal, crystal roughness), a
    /// translucent glowing mid layer and a mottled glowing core, so light seems to soak into the gel.
    private var maps: SurfaceMaps?
    private var padMaps: SurfaceMaps?
    private var mids: [ModelEntity] = []
    private var cores: [ModelEntity] = []
    /// EXPERIENCE-REVIEW-1 #5 (the halves were flung off the plate as two tall sliced half-bears): how far (bear-local
    /// metres, before the hero scale) the crushed bear may reach from its centre and stay on the strike plate / anvil.
    private let reach: Float
    private var slapT: Float = 0
    private var lowestS: Float = 1
    private var gave = false

    var shadowSpread: Float { spread }

    static func blob(side: Float) -> SDFBlob {
        var blob = SDFBlob()
        blob.add([0, 0.034, 0], [0.034, 0.034, 0.026])
        blob.add([0, 0.030, 0.008], radius: 0.026)
        blob.add([0, 0.078, 0.002], radius: 0.025)
        blob.add([0, 0.072, 0.022], radius: 0.011)
        for s: Float in [-1, 1] {
            blob.add([s * 0.018, 0.098, 0], radius: 0.009)
            blob.add([s * 0.034, 0.045, 0.006], [0.011, 0.018, 0.011], k: 0.008,
                     rotation: simd_quatf(angle: s * 25 * .pi / 180, axis: [0, 0, 1]))
            blob.add([s * 0.020, 0.012, 0.020], [0.013, 0.012, 0.018])
        }
        blob.clipNormal = SIMD3(side, 0, 0)
        blob.clipPoint = .zero
        return blob
    }

    static func halfMesh(side: Float, coreScale: Float) -> MeshData {
        let centre = SIMD3<Float>(-side * 0.015, 0.046, 0.004)
        var mesh = blob(side: side).mesh(centre: centre, reach: 0.11, rings: 40, segments: 48)
        if coreScale != 1 {
            mesh.positions = mesh.positions.map { centre + ($0 - centre) * coreScale }
        }
        return mesh
    }

    init(variant: PressVariant, fx: SceneFX) {
        self.fx = fx
        let look = Look(variant)
        self.look = look
        rainbow = variant.surprise == .rainbowCore
        gooColors = look.golden ? [Palette.goldMessColor] : [UIColor(hex: 0xFF5A4E), UIColor(hex: 0xFF8A7F)]
        rng = SplitMix64(seed: variant.seed ^ 0x6B)
        // The Duo strike plate's half width (the long axis the chew stretches along); the P-48's smaller anvil is the
        // fallback machine, where objects already overhang it.
        let plate = GlassDebris.containment(restHeight: 0.107 * GummyBearView.heroScale, anvilHalf: SIMD2(repeating: 1), padding: 0)
        reach = plate.x * 0.85 / GummyBearView.heroScale
        life = ObjectLife(seed: variant.seed, idle: .breathe, amount: 0.012, rate: 0.5, pulseHz: 2.6, pulseDamping: 0.55)
        story = StoryCursor(.gummyBear, seed: variant.seed)
        build(seed: variant.seed)
        if !look.golden { loadSurface() }
    }

    /// The skin: translucent red gel under a dusting of sugar. With its maps the sugar is white, raised and matte (rough
    /// 0.38–0.95 × 0.7) while the gel between the grains stays glossy; without them, the plain enamel.
    private func shellMaterial(glow: Float) -> PhysicallyBasedMaterial {
        if look.golden { return SceneMaterials.gold }
        var m = SceneMaterials.enamel(shellColour, roughness: 0.30, clearcoat: 0.35, clearcoatRoughness: 0.42, opacity: 0.80)
        if let skin = maps?.colour { m.baseColor = .init(tint: .white, texture: SurfaceDetail.wrapped(skin)) }
        if let sugar = maps?.normal { m.normal = .init(texture: SurfaceDetail.wrapped(sugar)) }
        if let rough = maps?.rough { m.roughness = .init(scale: 0.7, texture: SurfaceDetail.wrapped(rough)) }
        m.emissiveColor = .init(color: UIColor(hex: 0xFF6B5A))
        m.emissiveIntensity = glow
        return m
    }

    /// The translucent mid layer: no gloss of its own, just a soft red glow seen through the skin.
    private func midMaterial() -> PhysicallyBasedMaterial {
        var m = SceneMaterials.pbr(UIColor(hex: 0xFF3A34), roughness: 0.6, opacity: 0.42)
        m.emissiveColor = .init(color: UIColor(hex: 0xFF4A3C))
        m.emissiveIntensity = 0.35
        return m
    }

    /// The opaque core: deep red, its mottle (light pooled inside) glowing faintly.
    private func coreMaterial() -> PhysicallyBasedMaterial {
        if look.golden { return SceneMaterials.gold }
        var m = SceneMaterials.pbr(UIColor(hex: 0xC8203A), roughness: 0.35)
        if let core = maps?.extra {
            m.baseColor = .init(tint: .white, texture: SurfaceDetail.wrapped(core))
            m.emissiveColor = .init(color: .white, texture: SurfaceDetail.wrapped(core))
            m.emissiveIntensity = 0.28
        }
        return m
    }

    private func loadSurface() {
        Task { @MainActor [weak self] in
            async let pads = SurfaceDetail.gummyPad()
            let maps = await SurfaceDetail.gummy()
            guard let self else { return }
            self.maps = maps
            self.glowStep = -1   // rebuild the skin at the next frame's glow step, now with its maps
            let core = self.coreMaterial()
            for model in self.cores { model.model?.materials = [core] }
            self.padMaps = await pads
            self.applyPads()
        }
    }

    private func padMaterial() -> PhysicallyBasedMaterial {
        if look.golden { return SceneMaterials.goldMess }
        var m = SceneMaterials.enamel(UIColor(hex: 0xFF5A4E), roughness: 0.22, clearcoat: 0.6, clearcoatRoughness: 0.3, opacity: 0.92)
        if let colour = padMaps?.colour { m.baseColor = .init(tint: .white, texture: SurfaceDetail.clamped(colour)) }
        if let normal = padMaps?.normal { m.normal = .init(texture: SurfaceDetail.clamped(normal)) }
        return m
    }

    private func applyPads() {
        guard !pads.isEmpty, padMaps != nil else { return }
        let material = padMaterial()
        for pad in pads { pad.model?.materials = [material] }
    }

    private func build(seed: UInt64) {
        let core = coreMaterial()
        let shell = shellMaterial(glow: 0.22)
        let mid = midMaterial()
        cores.append(Part.add(cached: "gummy.core.full", { ObjectMeshes.gummy(side: nil, coreScale: 0.82) }, core, to: welded))
        if !look.golden {
            let layer = Part.add(cached: "gummy.mid.full", { ObjectMeshes.gummy(side: nil, coreScale: ObjectMeshes.gummyMidScale) }, mid,
                                 to: welded)
            ShadowCasting.off(layer)
            mids.append(layer)
        }
        shells.append(Part.add(cached: "gummy.shell.full", { ObjectMeshes.gummy(side: nil, coreScale: 1) }, shell, to: welded))
        buildSeamLine()
        bear.addChild(welded)
        for side: Float in [1, -1] {
            // side = clip normal: +1 keeps x ≤ 0 (left half), −1 keeps x ≥ 0 (right half).
            let half = Entity()
            let key = side > 0 ? "L" : "R"
            cores.append(Part.add(cached: "gummy.core.\(key)", { ObjectMeshes.gummy(side: side, coreScale: 0.82) }, core, to: half))
            if !look.golden {
                let layer = Part.add(cached: "gummy.mid.\(key)", { ObjectMeshes.gummy(side: side, coreScale: ObjectMeshes.gummyMidScale) },
                                     mid, to: half)
                ShadowCasting.off(layer)
                mids.append(layer)
            }
            let shellModel = Part.add(cached: "gummy.shell.\(key)", { ObjectMeshes.gummy(side: side, coreScale: 1) }, shell, to: half)
            shells.append(shellModel)
            addCrossSection(to: half, side: side)
            half.isEnabled = false
            bear.addChild(half)
            halves.append(half)
        }
        buildStrands(seed: seed)
        life.node.addChild(bear)
        entity.addChild(life.node)
        entity.orientation = Part.yaw(10)
        entity.scale = SIMD3(repeating: Self.heroScale)
    }

    /// The stress line down the seam: short pale segments over the head and down the belly (`GummyChew.seamPath`).
    private func buildSeamLine() {
        let material = look.golden ? SceneMaterials.pbr(UIColor(hex: 0xFFF1C4), roughness: 0.3, metallic: 1)
            : SceneMaterials.enamel(UIColor(hex: GummyChew.seamTint), roughness: 0.3, clearcoat: 0.5, clearcoatRoughness: 0.2)
        let path = GummyChew.seamPath
        let blob = ObjectMeshes.gummyBlob(side: nil)
        guard path.count > 1 else { return }
        for i in 0..<(path.count - 1) {
            let a = path[i], b = path[i + 1]
            let d = b - a
            let length = simd_length(d)
            guard length > 1e-4 else { continue }
            let dir = d / length
            // Frame: x along the run, y the surface normal (the bear's SDF gradient), z across the seam.
            var normal = blob.gradient((a + b) / 2)
            normal -= simd_dot(normal, dir) * dir
            normal = simd_length(normal) > 1e-6 ? simd_normalize(normal) : SIMD3<Float>(0, 1, 0)
            let across = simd_cross(dir, normal)
            let segment = Part.add(cached: "gummy.seam", { MeshKit.roundedBox([1, 0.0008, 1], radius: 0.0003, bevel: 0.0002) },
                                   material, at: (a + b) / 2, to: welded)
            segment.orientation = simd_quatf(simd_float3x3(columns: (dir, normal, across)))
            segment.scale = SIMD3(length + 0.0008, 1, GummyChew.seamWidth(level: 0))
            segment.isEnabled = false
            ShadowCasting.off(segment)
            seamLine.append(segment)
        }
    }

    /// The chewy strands that bridge the split (hidden until it).
    private func buildStrands(seed: UInt64) {
        var strandRng = SplitMix64(seed: seed ^ 0x57A4D)
        let material = look.golden ? SceneMaterials.gold
            : SceneMaterials.enamel(UIColor(hex: 0xFF6E60), roughness: 0.22, clearcoat: 0.6, clearcoatRoughness: 0.25, opacity: 0.9)
        for spot in GummyChew.strandSpots(rng: &strandRng) {
            let strand = Part.add(cached: "gummy.strand", { GummyChew.strandMesh() }, material, at: [0, spot.y, spot.z], to: bear)
            strand.orientation = simd_quatf(angle: -.pi / 2, axis: [0, 0, 1])
            strand.isEnabled = false
            ShadowCasting.off(strand)
            strands.append((strand, spot.y, spot.z, spot.radius, false))
        }
    }

    /// The seam faces: core-coloured, or candy stripes for the rainbow surprise. Hidden inside until the split.
    private func addCrossSection(to half: Entity, side: Float) {
        let x = -side * 0.0005
        let sections: [(y: Float, halfHeight: Float, halfDepth: Float, z: Float)] = [(0.034, 0.030, 0.024, 0.004), (0.078, 0.021, 0.020, 0.004)]
        let stripes = look.golden ? [Palette.gold] : (rainbow
            ? [UIColor(hex: 0xFF5A4E), UIColor(hex: 0xFFB81C), UIColor(hex: 0x8BD448), UIColor(hex: 0x2F5BEA)]
            : [UIColor(hex: 0xD8283F)])
        for section in sections {
            let bands = stripes.count
            for b in 0..<bands {
                let y0 = section.y - section.halfHeight + 2 * section.halfHeight * Float(b) / Float(bands)
                let y1 = section.y - section.halfHeight + 2 * section.halfHeight * Float(b + 1) / Float(bands)
                let yc = (y0 + y1) / 2
                let u = (yc - section.y) / section.halfHeight
                let depth = 2 * section.halfDepth * max((1 - u * u), 0.05).squareRoot()
                // A rounded, glossy cut face (EXPERIENCE-REVIEW-1 #5: the flat boxes read as CG cut planes): a thin lens
                // that domes out of the cut, so its edge rolls into the gel.
                let material = SceneMaterials.enamel(stripes[b], roughness: 0.22, clearcoat: 0.9, clearcoatRoughness: 0.18)
                let radii = SIMD3<Float>(0.0016, (y1 - y0) * 0.55, depth * 0.48)
                Part.add(MeshKit.ellipsoid(radii: radii, segments: 24, rings: 12), material, at: [x, yc, section.z], to: half)
            }
        }
    }

    func surfaceHeight(compression c: Float) -> Float {
        HeightCurve.linear(c, rest: restHeight, minRatio: minHeightRatio)
    }

    func update(_ state: PressVisualState) {
        if life.update(state) {
            BeatFX.glint(fx, at: [-0.008, 0.098, 0.012], in: entity, count: 1, golden: look.golden, rng: &rng)
        }
        for beat in story.advance(to: state.compression) { onBeat(beat, state: state) }
        let h = surfaceHeight(compression: state.compression)
        // Once split it never re-inflates (EXPERIENCE-REVIEW-1 #5: at the reveal the plastic ratchet stood the halves
        // back up into two tall sliced half-bears): the pads stay as flat as the press left them.
        var s = max(h / restHeight, 0.05)
        if split {
            lowestS = min(lowestS, s)
            s = lowestS
        }
        // The chewy stretch: a continuous part plus the beat steps, eased by a heavy spring (it pulls, it doesn't wobble).
        // The fight (EXPERIENCE-REVIEW-1 #1): it chews harder against the plate as it resists, and the seam whitens.
        let strain = state.resistanceBulge
        stretchFloor = max(stretchFloor, GummyChew.stretch(compression: state.compression, steps: stretchTarget) + 0.12 * strain)
        if strain > 0.35 && seamLevel < 2 { whitenSeam() }
        if state.collapseLead > 0 && !gave {
            // The give: the halves lurch apart in the same frame as the burst.
            gave = true
            gap.kick(0.12 * max(fx.motionScale, 0.3))
        }
        stretch.step(toward: stretchFloor, dt: state.dt)
        var scale = GummyChew.scale(heightRatio: s, stretch: max(stretch.value, 0))
        // Never wider than the plate allows (the split gap included).
        scale.x = min(scale.x, GummyChew.maxWidthScale(reach: reach, gap: split ? max(gap.value, 0) : 0))
        bear.scale = scale
        spread = max(scale.x, scale.z)
        // Glows more where it's thin (stepped so materials change rarely).
        let step = Int(state.compression * 8)
        if step != glowStep {
            glowStep = step
            let material = shellMaterial(glow: 0.22 * (1 + 1.5 * state.compression))
            for shell in shells { shell.model?.materials = [material] }
        }
        if split {
            let t = clamp((state.compression - splitC) / max(1 - splitC, 0.05), 0, 1)
            gap.step(toward: GummyChew.gap(t), dt: state.dt)
            // The halves lean out a little as they part, then lie flat again once they've slapped down into pads.
            if slapped { slapT = max(slapT, clamp((state.compression - slapC) / 0.1, 0, 1)) }
            tilt = GummyChew.tilt(t) * (1 - slapT)
            for (i, half) in halves.enumerated() {
                let side: Float = i == 0 ? -1 : 1 // halves[0] is the left half (x ≤ 0)
                half.position = SIMD3(side * gap.value, 0, 0)
                half.orientation = simd_quatf(angle: -side * tilt, axis: [0, 0, 1])
            }
            for strand in strands where !strand.snapped {
                let length = GummyChew.strandLength(gap: max(gap.value, 0), height: strand.y, tilt: tilt)
                let r = GummyChew.strandRadius(rest: strand.radius, length: length)
                strand.model.position = [0, strand.y, strand.z]
                strand.model.scale = SIMD3(r, length, r)
            }
            spread = max(scale.x * (1 + 2 * gap.value / footprint), scale.z)
        }
        if slapped {
            let t = clamp((state.compression - slapC) / max(1 - slapC, 0.05), 0, 1)
            for (i, pad) in pads.enumerated() {
                let side: Float = i == 0 ? -1 : 1
                let r = GummyChew.padRadius(t)
                // Each pad lies under its half, held on the plate.
                let halfWidth = r * scale.x * 0.9
                let x = min((0.020 + gap.value) * scale.x, max(reach - halfWidth, 0.004))
                pad.position = SIMD3(side * x, 0.0002, 0.004 * scale.z)
                pad.scale = SIMD3(halfWidth, 0.003, r * scale.z)
            }
        }
    }

    func handle(_ event: PressEvent, state: PressVisualState) {
        if event == .preFailureTell { life.tremor(0.3, level: 0.7) }
    }

    /// The stress line shows a step brighter / wider.
    private func whitenSeam() {
        guard !split else { return }
        seamLevel = min(seamLevel + 1, 3)
        let width = GummyChew.seamWidth(level: seamLevel)
        for segment in seamLine {
            segment.isEnabled = true
            segment.scale.z = width
        }
    }

    private func snapStrand() {
        guard split, let i = strands.firstIndex(where: { !$0.snapped }) else {
            life.tremor(0.15, level: 0.5)
            return
        }
        strands[i].snapped = true
        let strand = strands[i]
        strand.model.isEnabled = false
        // The snapped ends spring back into beads on each half (stains on the plate below).
        for side: Float in [-1, 1] {
            let local = SIMD3<Float>(side * (gap.value + 0.002), strand.y, strand.z)
            let at = bear.convert(position: local, to: fx.root)
            // Beads drop onto the halves and the plate beside them, scattered (never flung to the plate's edge).
            let v = SIMD3<Float>(side * Float.random(in: 0...0.025, using: &rng), -0.06,
                                 Float.random(in: -0.025...0.025, using: &rng)) * max(fx.motionScale, 0.3)
            fx.particles.emit(.droplet, at: at, velocity: v, color: gooColors.pick(&rng),
                              size: Float.random(in: 0.002...0.003, using: &rng), rng: &rng)
        }
        life.kick(0.5)
    }

    /// One storyboard beat (OBJECT-STORYBOARDS §8).
    private func onBeat(_ beat: StoryBeat, state: PressVisualState) {
        let golden = look.golden
        switch beat.kind {
        case .kiss:
            life.kick(0.7)
        case .bulge:
            life.kick(0.6)
            BeatFX.glint(fx, at: [0.006, 0.05, 0.034], in: entity, count: 1, golden: golden, rng: &rng)
        case .stretch:
            stretchTarget += 1
            stretch.kick(0.6)
            if slapped { life.kick(0.4) }
        case .sheen:
            BeatFX.glint(fx, at: [-0.01, 0.09, 0.01], in: entity, count: 2, golden: golden, rng: &rng)
            BeatFX.glint(fx, at: [0.012, 0.04, 0.03], in: entity, count: 1, golden: golden, rng: &rng)
        case .strain:
            whitenSeam()
            life.tremor(0.12, level: 0.4)
        case .tell:
            whitenSeam()
            stretch.kick(0.4)
            life.tremor(0.3, level: 0.7)
        case .strand:
            snapStrand()
        case .settle:
            BeatFX.glint(fx, at: [0, 0.01, 0], in: entity, count: 2, golden: golden, rng: &rng)
        default:
            life.kick(0.4)
        }
    }

    func fracture(index: Int, isFailure: Bool, state: PressVisualState) {
        let m = max(fx.motionScale, 0.3)
        if index == 0 {
            // Swap the welded bear for the pre-split halves at the break; the strands bridge the gap.
            welded.isEnabled = false
            for half in halves { half.isEnabled = true }
            for strand in strands { strand.model.isEnabled = true }
            split = true
            splitC = state.compression
            gap.kick(0.25 * m)
            life.kick(1.0)
            let at = entity.convert(position: [0, min(state.ramFace * 0.5, 0.04), 0.02], to: fx.root)
            fx.particles.burst(.droplet, count: 3, at: at, speed: 0.05 * m, colors: gooColors, size: 0.0025...0.004,
                               spread: 0.01, upBias: 0.6, rng: &rng)
            if rainbow {
                fx.particles.burst(.confetti, count: 10, at: at, speed: 0.35 * m,
                                   colors: [Palette.tangerine, Palette.lime, Palette.cobalt, Palette.lemon],
                                   size: 0.003...0.005, upBias: 0.5, rng: &rng)
            }
        } else {
            // The slap: the halves come down flat into two chewy pads (sticky footprints, no puddle).
            slapped = true
            slapC = state.compression
            life.kick(1.2)
            let material = padMaterial()
            for k in 0..<2 {
                // A chewy torn pad: a ragged, notched rim (gummy tears, it doesn't splash), stretch streaks on its face.
                let pad = Part.add(cached: "gummy.pad.torn.\(k)", {
                    MeshKit.spreadDiscUV(seed: 0x6B_0000 &+ UInt64(k) &* 0x9E37, height: 1, segments: 128, wobble: 0.12, tear: 0.1)
                }, material, to: entity)
                pad.scale = SIMD3(repeating: 0.0001)
                ShadowCasting.off(pad)
                pads.append(pad)
            }
            snapStrand()
        }
    }
}

/// The gummy's chew (OBJECT-STORYBOARDS §8), pure so SquishTests can pin it.
enum GummyChew {
    /// The stress line's colour (stress-whitened gummy).
    static let seamTint: UInt32 = 0xFFD9D2
    static let strandCount = 5
    /// One beat step of stretch, and the continuous part up to the failure.
    static let stepStretch: Float = 0.09
    static let continuousStretch: Float = 0.12
    static let maxStretch: Float = 0.55

    /// The chewy anisotropy (x grows, z narrows) at compression `c` after `steps` stretch beats.
    static func stretch(compression c: Float, steps: Float) -> Float {
        min(continuousStretch * clamp(c / 0.36, 0, 1) + stepStretch * steps, maxStretch)
    }

    /// The bear's scale at height ratio `s` with chewy `stretch`: volume kept (xz = 1/s), x stretched, z narrowed;
    /// never narrower than rest.
    static func scale(heightRatio s: Float, stretch: Float) -> SIMD3<Float> {
        let k = min(1 / max(s, 0.05).squareRoot(), 1.5)
        let a = 1 + clamp(stretch, 0, maxStretch)
        return SIMD3(min(k * a, maxWidth), max(s, 0.05), max(k / a.squareRoot(), 1))
    }

    /// The widest the chewed bear gets (EXPERIENCE-REVIEW-1 #5: at 2.0 plus the gap the halves left the plate).
    static let maxWidth: Float = 1.6
    /// The bear's half width at rest (its arms), bear-local metres.
    static let halfWidth: Float = 0.046

    /// The x scale at which the bear (half width + the split gap) just reaches `reach` from its centre.
    static func maxWidthScale(reach: Float, gap: Float) -> Float {
        max(reach / max(halfWidth + gap, 1e-3), 1)
    }

    /// The halves' gap (bear-local metres) at progress `t` past the split: they part, they don't fly.
    static func gap(_ t: Float) -> Float {
        0.003 + 0.007 * clamp(t, 0, 1)
    }

    /// How far the halves lean out as they part (radians), before they slap flat.
    static func tilt(_ t: Float) -> Float {
        0.04 + 0.08 * clamp(t, 0, 1)
    }

    /// A strand's length across the gap at height `y`, the halves tilted out by `tilt`.
    static func strandLength(gap: Float, height y: Float, tilt: Float) -> Float {
        2 * (gap + max(y, 0) * sin(tilt)) + 0.003
    }

    /// Volume-preserving thinning: r ∝ 1/√length, never below 0.35 mm.
    static func strandRadius(rest: Float, length: Float) -> Float {
        max(rest * (0.008 / max(length, 0.001)).squareRoot(), 0.00035)
    }

    static func seamWidth(level: Int) -> Float {
        [0.001, 0.0011, 0.0016, 0.0022][clamp(level, 0, 3)]
    }

    static func padRadius(_ t: Float) -> Float {
        0.022 + 0.010 * clamp(t, 0, 1)
    }

    /// Seeded strand spots (y, z, rest radius) inside the cross-section: three in the body, two in the head.
    static func strandSpots(rng: inout SplitMix64) -> [(y: Float, z: Float, radius: Float)] {
        let rows: [(y: ClosedRange<Float>, z: ClosedRange<Float>)] = [
            (0.012...0.024, -0.010...0.016), (0.030...0.045, -0.012...0.020), (0.050...0.058, -0.008...0.012),
            (0.068...0.078, -0.008...0.014), (0.082...0.092, -0.006...0.010),
        ]
        return rows.prefix(strandCount).map { row in
            (Float.random(in: row.y, using: &rng), Float.random(in: row.z, using: &rng),
             Float.random(in: 0.0016...0.0024, using: &rng))
        }
    }

    /// A unit strand along +Y (0…1), necked in the middle like pulled candy.
    static func strandMesh() -> MeshData {
        let profile: [SIMD2<Float>] = [
            SIMD2(0, 0), SIMD2(1.0, 0.0), SIMD2(1.0, 0.06), SIMD2(0.78, 0.2), SIMD2(0.55, 0.38), SIMD2(0.5, 0.5),
            SIMD2(0.55, 0.62), SIMD2(0.78, 0.8), SIMD2(1.0, 0.94), SIMD2(1.0, 1.0), SIMD2(0, 1),
        ]
        // Centred on its middle, so the strand spans the gap symmetrically.
        return MeshKit.lathe(profile: MeshKit.smoothProfile(profile, perSpan: 2), segments: 16).translated([0, -0.5, 0])
    }

    /// The seam's path in the welded bear's space: over the head from the back of the ears to the snout, then down
    /// the belly, found by marching the bear's own SDF on the x = 0 plane (so it sits on the surface).
    static let seamPath: [SIMD3<Float>] = {
        let blob = ObjectMeshes.gummyBlob(side: nil)
        var points: [SIMD3<Float>] = []
        // Over the head: top surface at x = 0 for z from back to front.
        for k in 0...7 {
            let z = -0.018 + 0.040 * Float(k) / 7
            var y: Float = 0.125
            while y > 0.05 && blob.distance([0, y, z]) > 0 { y -= 0.0008 }
            if y > 0.05 { points.append([0, y + 0.0006, z]) }
        }
        // Down the belly: front surface at x = 0 for y from the chin to the feet.
        for k in 0...6 {
            let y = 0.058 - 0.046 * Float(k) / 6
            var z: Float = 0.07
            while z > 0 && blob.distance([0, y, z]) > 0 { z -= 0.0008 }
            if z > 0 { points.append([0, y, z + 0.0006]) }
        }
        return points
    }()
}
