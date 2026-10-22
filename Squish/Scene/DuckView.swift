import RealityKit
import simd

/// A rubber duck built from primitives. It squashes as one cartoon pancake (volume-preserving),
/// honks, pops its seam, and is the only object with a face, because it survives.
@MainActor
final class DuckView: PressObjectView {
    let entity = Entity()
    let restHeight: Float = 0.069
    let minHeightRatio: Float = 0.16
    let footprint: Float = 0.045

    private let squash = Entity()
    private var deflated = false

    init() {
        entity.addChild(squash)
        entity.orientation = simd_quatf(angle: -.pi / 6, axis: [0, 1, 0])

        let vinyl = SceneMaterials.pbr(Palette.duckYellow, roughness: 0.3, clearcoat: 0.6)
        let beakMaterial = SceneMaterials.pbr(Palette.beakOrange, roughness: 0.35, clearcoat: 0.4)
        let eyeMaterial = SceneMaterials.pbr(.black, roughness: 0.2, clearcoat: 1)

        let body = ModelEntity(mesh: .generateSphere(radius: 0.028), materials: [vinyl])
        body.scale = [1.25, 0.85, 1.0]
        body.position = [0, 0.024, 0]

        let tail = ModelEntity(mesh: .generateSphere(radius: 0.012), materials: [vinyl])
        tail.position = [-0.031, 0.036, 0]

        let head = ModelEntity(mesh: .generateSphere(radius: 0.017), materials: [vinyl])
        head.position = [0.016, 0.052, 0]

        let beak = ModelEntity(mesh: .generateBox(width: 0.016, height: 0.006, depth: 0.012, cornerRadius: 0.003),
                               materials: [beakMaterial])
        beak.position = [0.034, 0.049, 0]

        for side: Float in [-1, 1] {
            let eye = ModelEntity(mesh: .generateSphere(radius: 0.0028), materials: [eyeMaterial])
            eye.position = [0.027, 0.058, 0.008 * side]
            squash.addChild(eye)
        }
        for part in [body, tail, head, beak] {
            squash.addChild(part)
        }
    }

    func apply(compression c: Float) {
        let squashY = height(atCompression: c) / restHeight
        // Keep volume roughly constant: XZ grows as 1/√y, capped so the pancake stays on the anvil.
        var spread = min(1 / squashY.squareRoot(), 2.1)
        if deflated { spread *= 0.94 }
        squash.scale = [spread, squashY, spread]
    }

    func fracture(index: Int, isFailure: Bool) {
        if isFailure { deflated = true }
    }
}
