import Foundation
import RealityKit
import simd
import UIKit

/// Gummy Bear (bible §4 #8, VISUAL-TARGET §5.8): a sitting, faceless gummy bear built as two pre-split SDF halves
/// (smooth-union blobs clipped at the seam) that read as one glossy bear. Fake SSS: translucent shell over an opaque
/// darker core; it glows more where it's squashed thin.
/// Fracture 0 (failure, ~0.36): it splits at the seam into two lobes that splay apart, showing the cross-section
/// (the `rainbowCore` surprise shows candy stripes). Fracture 1 (~0.62): the lobes spread into a glossy goo pancake.
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
    private let goo: ModelEntity
    private var split = false
    private var splitC: Float = 1
    private var spreading = false
    private var spreadC: Float = 1
    private var gap = JiggleSpring(value: 0, velocity: 0, omega: 18, zeta: 0.45)
    private var glowStep = -1
    private var spread: Float = 1
    private let shellColour = UIColor(hex: 0xFF5A4E)
    private let rainbow: Bool

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
        goo = ModelEntity(mesh: MeshKit.spreadDisc(seed: variant.seed &+ 21, height: 1, segments: 64, wobble: 0.15).resource()
                          ?? .generateSphere(radius: 0.01),
                          materials: [look.golden ? SceneMaterials.goldMess
                                      : SceneMaterials.enamel(UIColor(hex: 0xFF5A4E), roughness: 0.18, clearcoat: 0.8,
                                                              clearcoatRoughness: 0.2, opacity: 0.9)])
        goo.isEnabled = false
        rng = SplitMix64(seed: variant.seed ^ 0x6B)
        build()
    }

    private func shellMaterial(glow: Float) -> PhysicallyBasedMaterial {
        if look.golden { return SceneMaterials.gold }
        var m = SceneMaterials.enamel(shellColour, roughness: 0.20, clearcoat: 0.6, clearcoatRoughness: 0.28, opacity: 0.80)
        m.emissiveColor = .init(color: UIColor(hex: 0xFF6B5A))
        m.emissiveIntensity = glow
        return m
    }

    private func build() {
        let core = look.golden ? SceneMaterials.gold : SceneMaterials.pbr(UIColor(hex: 0xC8203A), roughness: 0.3)
        let shell = shellMaterial(glow: 0.22)
        Part.add(cached: "gummy.full.core", { ObjectMeshes.gummy(side: nil, coreScale: 0.82) }, core, to: welded)
        shells.append(Part.add(cached: "gummy.full.shell", { ObjectMeshes.gummy(side: nil, coreScale: 1) }, shell, to: welded))
        bear.addChild(welded)
        for side: Float in [1, -1] {
            // side = clip normal: +1 keeps x ≤ 0 (left half), −1 keeps x ≥ 0 (right half).
            let half = Entity()
            let key = side > 0 ? "L" : "R"
            Part.add(cached: "gummy.core.\(key)", { ObjectMeshes.gummy(side: side, coreScale: 0.82) }, core, to: half)
            let shellModel = Part.add(cached: "gummy.shell.\(key)", { ObjectMeshes.gummy(side: side, coreScale: 1) }, shell, to: half)
            shells.append(shellModel)
            addCrossSection(to: half, side: side)
            half.isEnabled = false
            bear.addChild(half)
            halves.append(half)
        }
        entity.addChild(bear)
        entity.addChild(goo)
        entity.orientation = Part.yaw(10)
        entity.scale = SIMD3(repeating: Self.heroScale)
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
                let material = SceneMaterials.enamel(stripes[b], roughness: 0.25, clearcoat: 0.8, clearcoatRoughness: 0.15)
                Part.add(MeshKit.roundedBox([0.0008, (y1 - y0) * 0.98, depth], radius: min(0.003, (y1 - y0) * 0.45),
                                            bevel: 0.0003),
                         material, at: [x, yc, section.z], to: half)
            }
        }
    }

    func surfaceHeight(compression c: Float) -> Float {
        HeightCurve.linear(c, rest: restHeight, minRatio: minHeightRatio)
    }

    func update(_ state: PressVisualState) {
        let h = surfaceHeight(compression: state.compression)
        let s = max(h / restHeight, 0.05)
        let k = min(1 / s.squareRoot(), 1.5)
        bear.scale = SIMD3(k, s, k)
        spread = k
        // Glows more where it's thin (stepped so materials change rarely).
        let step = Int(state.compression * 8)
        if step != glowStep {
            glowStep = step
            let material = shellMaterial(glow: 0.22 * (1 + 1.5 * state.compression))
            for shell in shells { shell.model?.materials = [material] }
        }
        if split {
            let t = clamp((state.compression - splitC) / max(1 - splitC, 0.05), 0, 1)
            gap.step(toward: 0.004 + 0.014 * t, dt: state.dt)
            for (i, half) in halves.enumerated() {
                let side: Float = i == 0 ? -1 : 1 // halves[0] is the left half (x ≤ 0)
                half.position = SIMD3(side * gap.value, 0, 0)
                half.orientation = simd_quatf(angle: -side * (0.08 + 0.3 * t), axis: [0, 0, 1])
            }
            spread = k * (1 + gap.value / footprint)
        }
        if spreading {
            let t = clamp((state.compression - spreadC) / max(1 - spreadC, 0.05), 0, 1)
            goo.isEnabled = true
            let radius = 0.035 + 0.03 * t
            goo.scale = SIMD3(radius, 0.004, radius * 0.85)
            spread = max(spread, radius / footprint)
        }
    }

    func fracture(index: Int, isFailure: Bool, state: PressVisualState) {
        let m = max(fx.motionScale, 0.3)
        let colors = look.golden ? [Palette.goldMessColor] : [UIColor(hex: 0xFF5A4E), UIColor(hex: 0xFF8A7F)]
        if index == 0 {
            // Swap the welded bear for the pre-split halves at the break.
            welded.isEnabled = false
            for half in halves { half.isEnabled = true }
            split = true
            splitC = state.compression
            gap.kick(0.4 * m)
            let at = entity.convert(position: [0, min(state.ramFace * 0.5, 0.04), 0.02], to: fx.root)
            fx.particles.burst(.droplet, count: 6, at: at, speed: 0.25 * m, colors: colors, size: 0.003...0.005,
                               spread: 0.01, upBias: 0.3, rng: &rng)
            if rainbow {
                fx.particles.burst(.confetti, count: 10, at: at, speed: 0.35 * m,
                                   colors: [Palette.tangerine, Palette.lime, Palette.cobalt, Palette.lemon],
                                   size: 0.003...0.005, upBias: 0.5, rng: &rng)
            }
        } else {
            spreading = true
            spreadC = state.compression
            fx.particles.burst(.droplet, count: 8, at: [0, 0.008, 0], speed: 0.3 * m, colors: colors, size: 0.003...0.006,
                               spread: 0.03, upBias: 0.15, rng: &rng)
        }
    }
}
