import Foundation
import RealityKit
import simd
import UIKit

/// The Unsquishable (bible §4 #10, VISUAL-TARGET §5.10): a mirror-polished steel ball bearing, Ø 0.110 (VISUAL-REVIEW-1 fix 6).
/// It never deforms; the platen stops 1 mm above its apex. The press groans (fractures 0, 1: hairline cracks in the
/// plate, scraping sparks at the contact) and at the failure the *press* loses — the scene cracks and bends the platen
/// and pops a bolt (`PressRig.crack`); the ball leaves a dent in the anvil. Also the IBL showcase / calibration object.
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
    /// sweeping over it, the steel warming in steps, grit and sparks squeezed out at the contact.
    private let life: ObjectLife
    private var story: StoryCursor
    private var heat = 0

    init(variant: PressVariant, fx: SceneFX) {
        self.fx = fx
        rng = SplitMix64(seed: variant.seed ^ 0xBA11)
        ball = ModelEntity(mesh: MeshCache.resource("ball") { MeshKit.sphereUV(radius: ObjectMeshes.ballRadius, segments: 96, rings: 64) }
                           ?? .generateSphere(radius: ObjectMeshes.ballRadius),
                           materials: [Self.steel(heat: 0, maps: nil)])
        life = ObjectLife(seed: variant.seed, idle: .still, amount: 0, rate: 0.3, pulseHz: 10, pulseDamping: 0.6)
        story = StoryCursor(.unsquishable, seed: variant.seed)
        ball.position = [0, ObjectMeshes.ballRadius, 0]
        life.node.addChild(ball)
        entity.addChild(life.node)
        Task { @MainActor [weak self] in
            let maps = await SurfaceDetail.steel()
            guard let self else { return }
            self.maps = maps
            self.ball.model?.materials = [Self.steel(heat: self.heat, maps: maps)]
        }
    }

    /// Machined bearing steel (3D-art round): fine turning rings and micro-scratches in the normal, and a specular
    /// breakup (faint smudges, the scratches a touch rougher) over a near-mirror; `heat` warms it a step at a time.
    private static func steel(heat: Int, maps: SurfaceMaps?) -> PhysicallyBasedMaterial {
        let roughness = 0.03 + 0.01 * Float(heat)
        var material = SceneMaterials.pbr(UIColor(hex: 0xF2F3F5), roughness: roughness, metallic: 1)
        if let normal = maps?.normal { material.normal = .init(texture: SurfaceDetail.wrapped(normal)) }
        if let breakup = maps?.rough { material.roughness = .init(scale: roughness + 0.07, texture: SurfaceDetail.wrapped(breakup)) }
        if heat > 0 {
            material.emissiveColor = .init(color: UIColor(hex: 0xFF7A2E))
            material.emissiveIntensity = 0.05 * Float(heat)
        }
        return material
    }

    private var maps: SurfaceMaps?

    /// The steel warms a step (a faint ember tint at the contact, never a deformation).
    private func warm() {
        heat = min(heat + 1, 4)
        ball.model?.materials = [Self.steel(heat: heat, maps: maps)]
    }

    /// One storyboard beat (OBJECT-STORYBOARDS §10).
    private func onBeat(_ beat: StoryBeat, state: PressVisualState) {
        let r = ObjectMeshes.ballRadius
        switch beat.kind {
        case .kiss, .sheen:
            let a = Float.random(in: 0...(2 * .pi), using: &rng)
            BeatFX.glint(fx, at: [cos(a) * r * 0.5, r * 1.85, sin(a) * r * 0.5], in: entity, count: 2, rng: &rng)
        case .glow:
            warm()
        case .chip:
            // Grit and sparks squeezed out where the plate grinds on the ball.
            let top = entity.convert(position: [0, restHeight, 0], to: fx.root)
            fx.particles.burst(beat.ordinal % 2 == 0 ? .dust : .spark, count: 3, at: top, speed: 0.25 * max(fx.motionScale, 0.4),
                               colors: beat.ordinal % 2 == 0 ? [UIColor(hex: 0xC9CDD3)] : [Palette.spark],
                               size: 0.001...0.002, upBias: 0.05, life: 0.35, rng: &rng)
        case .tell:
            life.tremor(0.35)
            warm()
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
        let top = entity.convert(position: [0, restHeight, 0], to: fx.root)
        fx.particles.burst(.spark, count: isFailure ? 6 : 4, at: top, speed: 0.4 * max(fx.motionScale, 0.4),
                           colors: [Palette.spark, UIColor(hex: 0xFFE7A0)], size: 0.001...0.002, upBias: 0.05,
                           life: 0.35, rng: &rng)
        if isFailure { addDent() }
    }

    /// The anvil dent under the ball: a darker ring with a bright inner rim (PBR, so it catches the light).
    private func addDent() {
        guard dent == nil else { return }
        let dent = Entity()
        let ring = MeshKit.model(MeshKit.torus(major: 0.026, minor: 0.0032, segments: 64, sides: 12),
                                 material: SceneMaterials.pbr(UIColor(hex: 0x7E838B), roughness: 0.45, metallic: 1))
        ring.scale = [1, 0.18, 1]
        dent.addChild(ring)
        let rim = MeshKit.model(MeshKit.torus(major: 0.022, minor: 0.0014, segments: 64, sides: 8),
                                material: SceneMaterials.pbr(UIColor(hex: 0xE9ECF0), roughness: 0.15, metallic: 1))
        rim.scale = [1, 0.25, 1]
        dent.addChild(rim)
        dent.position = [0, 0.0002, 0]
        ShadowCasting.off(dent)
        fx.addMess(dent)
        self.dent = dent
    }
}
