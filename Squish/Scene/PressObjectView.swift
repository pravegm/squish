import RealityKit

/// A pressable object in the scene. The entity's origin sits on the anvil surface.
@MainActor
protocol PressObjectView: AnyObject {
    var entity: Entity { get }
    /// Height before any compression, in metres.
    var restHeight: Float { get }
    /// Fully-flattened height as a fraction of `restHeight`.
    var minHeightRatio: Float { get }
    /// Footprint radius, for the contact shadow.
    var footprint: Float { get }

    /// Apply the current visual compression (0 at contact, 1 flat).
    func apply(compression: Float)
    func fracture(index: Int, isFailure: Bool)
}

extension PressObjectView {
    func height(atCompression c: Float) -> Float {
        restHeight * (1 - c * (1 - minHeightRatio))
    }
}

@MainActor
enum PressObjectFactory {
    static func make(_ kind: ObjectKind, seed: UInt64) -> PressObjectView {
        switch kind {
        case .bubbleWrap: BubbleWrapView(seed: seed)
        case .rubberDuck: DuckView()
        }
    }
}
