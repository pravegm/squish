import Foundation

enum ObjectKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case bubbleWrap
    case rubberDuck

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bubbleWrap: "Bubble Wrap"
        case .rubberDuck: "Rubber Duck"
        }
    }

    var symbolName: String {
        switch self {
        case .bubbleWrap: "circle.grid.3x3.fill"
        case .rubberDuck: "bird.fill"
        }
    }

    var profile: MaterialProfile {
        switch self {
        case .bubbleWrap: .bubbleWrap
        case .rubberDuck: .rubberDuck
        }
    }

    /// Flavour lines shown on the specimen card (12+ tone lives here, never in the imagery).
    var flavourLines: [String] {
        switch self {
        case .bubbleWrap: ["Every single one. You monster.", "Shipping department's worst nightmare.", "Popped with professional care."]
        case .rubberDuck: ["He'll be fine. Probably.", "Bath time is cancelled.", "Quack, but flatter."]
        }
    }
}

/// How an object responds to the press. Compression values (`c`) run 0 at contact → 1 fully flat.
struct MaterialProfile: Sendable {
    /// 1 − elastic rebound when the ram lifts.
    var plasticity: Double
    /// Compression thresholds for irreversible events, ascending. Jittered per press by `thresholdJitter`.
    var fractures: [Double]
    /// Index into `fractures` of the single big failure (gets the hush + full-intensity event), if any.
    var failureIndex: Int?
    var thresholdJitter: Double
    /// Degrees of closing per haptic/audio grain while loaded (the compliance illusion).
    var grainSpacing: Double
    /// Rigid plateau: stop grains from this compression until the failure fires.
    var grainStopC: Double?
    /// Strain-bed sharpness (glass ≈ 0.9, jelly ≈ 0.1).
    var bedSharpness: Float
    /// Strain-bed intensity multiplier.
    var bedGain: Float

    static let bubbleWrap = MaterialProfile(
        plasticity: 0.92,
        fractures: (0..<BubbleWrapLayout.count).map { 0.03 + 0.80 * Double($0) / Double(BubbleWrapLayout.count - 1) },
        failureIndex: nil,
        thresholdJitter: 0.02,
        grainSpacing: 3.0,
        grainStopC: nil,
        bedSharpness: 0.65,
        bedGain: 0.55
    )

    static let rubberDuck = MaterialProfile(
        plasticity: 0.35,
        fractures: [0.42, 0.66],
        failureIndex: 1,
        thresholdJitter: 0.04,
        grainSpacing: 9.0,
        grainStopC: 0.56,
        bedSharpness: 0.30,
        bedGain: 0.85
    )

    /// Fracture thresholds for one press, jittered deterministically from the seed and kept ascending.
    func jitteredFractures(seed: UInt64) -> [Double] {
        var rng = SplitMix64(seed: seed)
        return fractures
            .map { clamp($0 + Double.random(in: -thresholdJitter...thresholdJitter, using: &rng), 0.01, 0.97) }
            .sorted()
    }
}

enum BubbleWrapLayout {
    static let columns = 6
    static let rows = 4
    static let count = columns * rows
}
