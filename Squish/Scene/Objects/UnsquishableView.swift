import Foundation
import RealityKit
import simd
import UIKit

/// The Unsquishable (bible §4 #10, VISUAL-TARGET §5.10): a mirror-polished steel ball bearing, Ø 0.110 (VISUAL-REVIEW-1 fix 6).
/// It never deforms; the platen stops 1 mm above its apex. The press groans (fractures 0, 1: hairline cracks in the
/// plate, scraping sparks at the contact) and at the failure the *press* loses — the scene cracks and bends the platen
/// and pops a bolt (`PressRig.crack`); the ball leaves a dent in the anvil. Also the IBL showcase / calibration object.
///
/// EXPERIENCE-REVIEW-1 ("at 75° the ball looks deformed: an elongated bronze ellipsoid with two white blobs"): nothing
/// on the ball ever changes its shape, size or colour now. What the 75° capture showed was three things together:
///  • the Fold anvil's anamorphic eye (rendered from ≥ 47.5° elevation so it reads true from the viewer's eye) draws
///    every 24 mm-tall object up to ~1.36× long toward the crease in a flat capture; on a sphere that reads as an egg;
///  • the storyboard's old "warming" steps tinted the steel bronze (ember emission on a mirror);
///  • grey grit puffs from the `.chip` beats sat on its top as white blobs.
/// The tint is gone (the steel only ever glints), the grit is short-lived unlit sparks, the life node never pulses it,
/// and the scene's side bulge is zero for it (`PressResistance.of(.unsquishable)`).
@MainActor
final class UnsquishableView: PressObjectView {
    let entity = Entity()
    let restHeight: Float = 2 * ObjectMeshes.ballRadius
    let footprint: Float = 0.048
    let isRigid = true

    private let fx: SceneFX
    private var rng = SplitMix64(seed: 0)
    private let ball: ModelEntity
    private var dent: Entity?
    /// The storyboard (OBJECT-STORYBOARDS §10): the ball never gives, so the events are the press losing: reflections
    /// sweeping over it and sparks squeezed out at the contact.
    private let life: ObjectLife
    private var story: StoryCursor
    private var maps: SurfaceMaps?

    init(variant: PressVariant, fx: SceneFX) {
        self.fx = fx
        rng = SplitMix64(seed: variant.seed ^ 0xBA11)
        ball = ModelEntity(mesh: MeshCache.resource("ball") { MeshKit.sphereUV(radius: ObjectMeshes.ballRadius, segments: 96, rings: 64) }
                           ?? .generateSphere(radius: ObjectMeshes.ballRadius),
                           materials: [Self.steel(maps: nil)])
        life = ObjectLife(seed: variant.seed, idle: .still, amount: 0, rate: 0.3, pulseHz: 10, pulseDamping: 0.6)
        story = StoryCursor(.unsquishable, seed: variant.seed)
        ball.position = [0, ObjectMeshes.ballRadius, 0]
        life.node.addChild(ball)
        entity.addChild(life.node)
        Task { @MainActor [weak self] in
            let maps = await SurfaceDetail.steel()
            guard let self else { return }
            self.maps = maps
            self.ball.model?.materials = [Self.steel(maps: maps)]
        }
    }

    /// Machined bearing steel (3D-art round): fine turning rings and micro-scratches in the normal, and a specular
    /// breakup (faint smudges, the scratches a touch rougher) over a near-mirror. Never tinted.
    private static func steel(maps: SurfaceMaps?) -> PhysicallyBasedMaterial {
        let roughness: Float = 0.03
        var material = SceneMaterials.pbr(UIColor(hex: 0xF2F3F5), roughness: roughness, metallic: 1)
        if let normal = maps?.normal { material.normal = .init(texture: SurfaceDetail.wrapped(normal)) }
        if let breakup = maps?.rough { material.roughness = .init(scale: roughness + 0.07, texture: SurfaceDetail.wrapped(breakup)) }
        return material
    }

    /// Sparks squeezed out where the plate grinds on the ball: short-lived and unlit, so nothing settles on it.
    private func sparks(_ count: Int, speed: Float) {
        let top = entity.convert(position: [0, restHeight, 0], to: fx.root)
        fx.particles.burst(.spark, count: count, at: top, speed: speed * max(fx.motionScale, 0.4),
                           colors: [Palette.spark, UIColor(hex: 0xFFE7A0)], size: 0.001...0.002, upBias: 0.05,
                           life: 0.3, rng: &rng)
    }

    /// One storyboard beat (OBJECT-STORYBOARDS §10).
    private func onBeat(_ beat: StoryBeat, state: PressVisualState) {
        let r = ObjectMeshes.ballRadius
        switch beat.kind {
        case .kiss, .sheen:
            let a = Float.random(in: 0...(2 * .pi), using: &rng)
            BeatFX.glint(fx, at: [cos(a) * r * 0.5, r * 1.85, sin(a) * r * 0.5], in: entity, count: 2, rng: &rng)
        case .glow:
            // A reflection sweeps round the steel.
            for k in 0..<3 {
                let a = Float(beat.ordinal) * 1.3 + Float(k) * 0.5
                BeatFX.glint(fx, at: [cos(a) * r * 0.75, r * 1.6, sin(a) * r * 0.75], in: entity, count: 1, rng: &rng)
            }
        case .chip:
            sparks(3, speed: 0.3)
        case .tell:
            life.tremor(0.35)
        default:
            life.tremor(0.1, level: 0.5)
        }
    }

    func surfaceHeight(compression c: Float) -> Float {
        restHeight + 0.001
    }

    func update(_ state: PressVisualState) {
        if life.update(state) {
            let a = Float.random(in: 0...(2 * .pi), using: &rng)
            BeatFX.glint(fx, at: [cos(a) * 0.02, 0.1, sin(a) * 0.02], in: entity, count: 1, rng: &rng)
        }
        for beat in story.advance(to: state.compression) { onBeat(beat, state: state) }
    }

    func fracture(index: Int, isFailure: Bool, state: PressVisualState) {
        sparks(isFailure ? 6 : 4, speed: 0.4)
        if isFailure { addDent() }
    }

    /// The anvil gives instead of the ball: a dished crater rim just outside the ball's silhouette (so it reads from
    /// above; EXPERIENCE-REVIEW-1: the old 26 mm dent sat hidden under the ball) and seeded radial cracks in the plate.
    private func addDent() {
        guard dent == nil else { return }
        let dent = Entity()
        let ring = MeshKit.model(MeshKit.torus(major: UnsquishableDent.rimRadius, minor: 0.0034, segments: 96, sides: 12),
                                 material: SceneMaterials.pbr(UIColor(hex: 0x7E838B), roughness: 0.45, metallic: 1))
        ring.scale = [1, 0.18, 1]
        dent.addChild(ring)
        let rim = MeshKit.model(MeshKit.torus(major: UnsquishableDent.rimRadius + 0.004, minor: 0.0014, segments: 96, sides: 8),
                                material: SceneMaterials.pbr(UIColor(hex: 0xE9ECF0), roughness: 0.15, metallic: 1))
        rim.scale = [1, 0.25, 1]
        dent.addChild(rim)
        let crackMaterial = SceneMaterials.pbr(UIColor(hex: 0x3A3D43), roughness: 0.6, metallic: 0.6)
        for k in 0..<UnsquishableDent.cracks {
            let a = Float(k) / Float(UnsquishableDent.cracks) * 2 * .pi + Float.random(in: -0.3...0.3, using: &rng)
            // Short, so they stay on the P-48's anvil (±72 mm deep) as well as the Duo's plate.
            let length = Float.random(in: 0.004...0.008, using: &rng)
            let start = UnsquishableDent.rimRadius + 0.003
            let crack = MeshKit.model(MeshKit.roundedBox([length, 0.0004, 0.0009], radius: 0.0002, bevel: 0.0001),
                                      material: crackMaterial)
            crack.position = [cos(a) * (start + length / 2), 0.0002, sin(a) * (start + length / 2)]
            crack.orientation = simd_quatf(angle: -a + Float.random(in: -0.15...0.15, using: &rng), axis: [0, 1, 0])
            dent.addChild(crack)
        }
        dent.position = [0, 0.0002, 0]
        ShadowCasting.off(dent)
        fx.addMess(dent)
        self.dent = dent
    }
}

/// The dent the steel ball leaves in the anvil, just outside its own silhouette (r 55 mm), so it reads from above.
enum UnsquishableDent {
    static let rimRadius: Float = 0.060
    static let cracks = 6
}
