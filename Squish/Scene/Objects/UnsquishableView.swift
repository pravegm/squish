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

    init(variant: PressVariant, fx: SceneFX) {
        self.fx = fx
        rng = SplitMix64(seed: variant.seed ^ 0xBA11)
        ball = ModelEntity(mesh: MeshCache.resource("ball") { MeshKit.sphere(radius: ObjectMeshes.ballRadius, segments: 64, rings: 48) }
                           ?? .generateSphere(radius: ObjectMeshes.ballRadius),
                           materials: [SceneMaterials.pbr(UIColor(hex: 0xF2F3F5), roughness: 0.03, metallic: 1)])
        ball.position = [0, ObjectMeshes.ballRadius, 0]
        entity.addChild(ball)
    }

    func surfaceHeight(compression c: Float) -> Float {
        restHeight + 0.001
    }

    func update(_ state: PressVisualState) {}

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
