import RealityKit
import simd

/// A sheet of 6×4 bubbles. Unpopped bubbles squash under the plate; each pops at its own
/// (seeded) threshold and stays flat and crinkled.
@MainActor
final class BubbleWrapView: PressObjectView {
    private static let sheetHeight: Float = 0.0025
    private static let radius: Float = 0.0075
    private static let domeRatio: Float = 0.75

    let entity = Entity()
    let restHeight: Float = BubbleWrapView.sheetHeight + BubbleWrapView.radius * BubbleWrapView.domeRatio
    let minHeightRatio: Float = 0.3
    let footprint: Float = 0.085

    private var bubbles: [ModelEntity] = []
    private var popped: [Bool]
    private let popTilts: [simd_quatf]
    /// Fracture index → bubble index, so pops ripple across the sheet in a seeded order.
    private let popOrder: [Int]

    init(seed: UInt64) {
        var rng = SplitMix64(seed: seed ^ 0xB0BB1E)
        popOrder = Array(0..<BubbleWrapLayout.count).shuffled(using: &rng)
        popped = Array(repeating: false, count: BubbleWrapLayout.count)
        popTilts = (0..<BubbleWrapLayout.count).map { _ in
            let axis = simd_normalize(SIMD3<Float>(Float.random(in: -1...1, using: &rng), 0.2, Float.random(in: -1...1, using: &rng)))
            return simd_quatf(angle: Float.random(in: -0.25...0.25, using: &rng), axis: axis)
        }

        let sheetHeight = Self.sheetHeight
        let radius = Self.radius
        let sheetWidth: Float = 0.15
        let sheetDepth: Float = 0.10
        let plastic = SceneMaterials.pbr(Palette.bubbleBlue, roughness: 0.15, clearcoat: 1, opacity: 0.55)
        let sheet = ModelEntity(
            mesh: .generateBox(width: sheetWidth, height: sheetHeight, depth: sheetDepth, cornerRadius: 0.001),
            materials: [plastic]
        )
        sheet.position.y = sheetHeight / 2
        entity.addChild(sheet)

        let bubbleMesh = MeshResource.generateSphere(radius: radius)
        let bubbleMaterial = SceneMaterials.pbr(Palette.bubbleBlue, roughness: 0.05, clearcoat: 1, opacity: 0.45)
        let spacingX = sheetWidth / Float(BubbleWrapLayout.columns)
        let spacingZ = sheetDepth / Float(BubbleWrapLayout.rows)
        for row in 0..<BubbleWrapLayout.rows {
            for column in 0..<BubbleWrapLayout.columns {
                let bubble = ModelEntity(mesh: bubbleMesh, materials: [bubbleMaterial])
                bubble.position = [
                    -sheetWidth / 2 + spacingX * (Float(column) + 0.5),
                    sheetHeight,
                    -sheetDepth / 2 + spacingZ * (Float(row) + 0.5),
                ]
                bubble.scale = [1, Self.domeRatio, 1]
                entity.addChild(bubble)
                bubbles.append(bubble)
            }
        }
    }

    func apply(compression c: Float) {
        let domeHeight = max(height(atCompression: c) - Self.sheetHeight, 0.0004)
        let squashY = min(domeHeight / Self.radius, Self.domeRatio)
        // As a dome flattens it spreads a little.
        let spread = 1 + 0.45 * (1 - squashY / Self.domeRatio)
        for (index, bubble) in bubbles.enumerated() {
            if popped[index] {
                bubble.scale = [1.3, 0.06, 1.3]
                bubble.orientation = popTilts[index]
            } else {
                bubble.scale = [spread, squashY, spread]
            }
        }
    }

    func fracture(index: Int, isFailure: Bool) {
        popped[popOrder[index % popOrder.count]] = true
    }
}
