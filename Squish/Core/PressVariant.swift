import Foundation

/// Honest per-press variation (bible §4): everything is derived from the press seed, nothing is bought.
struct PressVariant: Codable, Equatable, Sendable {
    var seed: UInt64
    /// 1 in 50. Odds are disclosed in Settings › About.
    var isGolden: Bool
    var surprise: Surprise?

    static let goldenOdds = 50

    init(kind: ObjectKind, seed: UInt64) {
        self.seed = seed
        var rng = SplitMix64(seed: seed ^ 0x5EED_CAFE)
        isGolden = kind != .unsquishable && Int.random(in: 0..<Self.goldenOdds, using: &rng) == 0
        surprise = Surprise.roll(for: kind, rng: &rng)
    }
}

/// A hidden extra inside some objects. Names are used on the specimen card.
enum Surprise: String, Codable, Sendable, CaseIterable {
    case megaBubble
    case fruitPieces
    case secondColourCore
    case toyChick
    case doubleYolk
    case jamCentre
    case cherryFizz
    case rainbowCore
    case messageInABottle

    var title: String {
        switch self {
        case .megaBubble: "MEGA BUBBLE"
        case .fruitPieces: "FRUIT INSIDE"
        case .secondColourCore: "SECRET COLOUR CORE"
        case .toyChick: "TINY TOY CHICK"
        case .doubleYolk: "DOUBLE YOLK"
        case .jamCentre: "JAM CENTRE"
        case .cherryFizz: "CHERRY FIZZ"
        case .rainbowCore: "RAINBOW CORE"
        case .messageInABottle: "MESSAGE IN A BOTTLE"
        }
    }

    static func roll<R: RandomNumberGenerator>(for kind: ObjectKind, rng: inout R) -> Surprise? {
        let candidates: [(Surprise, Int)] // (surprise, 1-in-N odds)
        switch kind {
        case .bubbleWrap: candidates = [(.megaBubble, 12)]
        case .jelly: candidates = [(.fruitPieces, 4)]
        case .crayon: candidates = [(.secondColourCore, 5)]
        case .egg: candidates = [(.toyChick, 8), (.doubleYolk, 15)]
        case .cakeSlice: candidates = [(.jamCentre, 3)]
        case .sodaCan: candidates = [(.cherryFizz, 6)]
        case .gummyBear: candidates = [(.rainbowCore, 6)]
        case .glassBottle: candidates = [(.messageInABottle, 10)]
        case .rubberDuck, .unsquishable: candidates = []
        }
        for (surprise, odds) in candidates where Int.random(in: 0..<odds, using: &rng) == 0 {
            return surprise
        }
        return nil
    }
}
