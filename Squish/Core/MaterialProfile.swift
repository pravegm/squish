import Foundation

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

    /// Fracture thresholds for one press, jittered deterministically from the seed and kept ascending.
    func jitteredFractures(seed: UInt64) -> [Double] {
        var rng = SplitMix64(seed: seed)
        return fractures
            .map { clamp($0 + Double.random(in: -thresholdJitter...thresholdJitter, using: &rng), 0.01, 0.97) }
            .sorted()
    }
}

extension MaterialProfile {
    /// Discrete pops, no single failure; each bubble is its own event.
    static let bubbleWrap = MaterialProfile(
        plasticity: 0.92,
        fractures: (0..<BubbleWrapLayout.count).map { 0.03 + 0.80 * Double($0) / Double(BubbleWrapLayout.count - 1) },
        failureIndex: nil, thresholdJitter: 0.02,
        grainSpacing: 3.0, grainStopC: nil, bedSharpness: 0.65, bedGain: 0.55
    )

    /// Elastic: honk, then the seam pops. Mostly springs back.
    static let rubberDuck = MaterialProfile(
        plasticity: 0.35,
        fractures: [0.42, 0.66],
        failureIndex: 1, thresholdJitter: 0.04,
        grainSpacing: 9.0, grainStopC: 0.56, bedSharpness: 0.30, bedGain: 0.85
    )

    /// Gel: wobbles, the skin splits, then it splats out the sides.
    static let jelly = MaterialProfile(
        plasticity: 0.75,
        fractures: [0.30, 0.55],
        failureIndex: 1, thresholdJitter: 0.04,
        grainSpacing: 3.5, grainStopC: nil, bedSharpness: 0.10, bedGain: 0.70
    )

    /// Brittle-waxy, a box of seven: every crayon snaps on its own, the top row of three first (the first snap is the
    /// failure), then the bottom row of four, then a waxy crumble (OBJECT-STORYBOARDS §4). The snaps are ~0.045 c
    /// apart and jitter by at most 0.015, so they never swap order: fracture n is always snap n.
    static let crayon = MaterialProfile(
        plasticity: 0.95,
        fractures: [0.27, 0.31, 0.355, 0.40, 0.445, 0.49, 0.535, 0.74],
        failureIndex: 0, thresholdJitter: 0.015,
        grainSpacing: 2.0, grainStopC: 0.22, bedSharpness: 0.55, bedGain: 0.80
    )

    /// Shell + liquid: hairline crack, the shell gives, then the yolk spreads.
    static let egg = MaterialProfile(
        plasticity: 0.97,
        fractures: [0.12, 0.24, 0.50],
        failureIndex: 1, thresholdJitter: 0.03,
        grainSpacing: 3.0, grainStopC: 0.16, bedSharpness: 0.70, bedGain: 0.60
    )

    /// Soft crumb: icing cracks, the candle bends, frosting squirts.
    static let cakeSlice = MaterialProfile(
        plasticity: 0.90,
        fractures: [0.22, 0.42, 0.62],
        failureIndex: 2, thresholdJitter: 0.04,
        grainSpacing: 1.2, grainStopC: nil, bedSharpness: 0.12, bedGain: 0.55
    )

    /// Thin metal: five concertina buckles; the third punctures it and the fizz goes everywhere.
    static let sodaCan = MaterialProfile(
        plasticity: 0.96,
        fractures: [0.28, 0.42, 0.55, 0.68, 0.80],
        failureIndex: 2, thresholdJitter: 0.03,
        grainSpacing: 0.8, grainStopC: nil, bedSharpness: 0.80, bedGain: 0.80
    )

    /// Plastic gel: splits at the seam into lobes, then spreads.
    static let gummyBear = MaterialProfile(
        plasticity: 0.82,
        fractures: [0.36, 0.62],
        failureIndex: 0, thresholdJitter: 0.04,
        grainSpacing: 3.5, grainStopC: 0.28, bedSharpness: 0.15, bedGain: 0.75
    )

    /// Glass: silent rigidity, a crack, then the biggest event in the app.
    static let glassBottle = MaterialProfile(
        plasticity: 1.0,
        fractures: [0.22, 0.40, 0.62],
        failureIndex: 1, thresholdJitter: 0.03,
        grainSpacing: 4.0, grainStopC: 0.10, bedSharpness: 0.90, bedGain: 0.90
    )

    /// The secret steel ball: never deforms. The press groans twice, then the press itself cracks.
    static let unsquishable = MaterialProfile(
        plasticity: 0.0,
        fractures: [0.22, 0.46, 0.70],
        failureIndex: 2, thresholdJitter: 0.02,
        grainSpacing: 6.0, grainStopC: nil, bedSharpness: 0.95, bedGain: 1.0
    )
}

enum BubbleWrapLayout {
    static let columns = 6
    static let rows = 4
    static let count = columns * rows
}
