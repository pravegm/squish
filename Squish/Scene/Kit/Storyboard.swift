import Foundation

/// The deformation storyboards (design/OBJECT-STORYBOARDS.md, EXPERIENCE-PLAN "a deformation event at least every 8°"):
/// a visible event on a fixed compression grid for every object, plus two "tell" beats just before its failure. The
/// grid is dense where the angle → compression mapping is steep (contact) and every ≤ 0.07 c after, so with the
/// FOLD-PRESS mapping (contact ≤ 132°, flat 48°, ease exponent 1…1.7) no 8° of closing passes without a new event.
/// The engine's own fractures (`MaterialProfile`) land between these beats and are events too.
/// Pure and nonisolated, so SquishTests can count the gaps.
enum BeatKind: String, Sendable, CaseIterable {
    /// The plate's first kiss: a squash pulse and a highlight ping.
    case kiss
    /// A volume-preserving bulge step you can see from above.
    case bulge
    /// A face or body squash step (the duck's eyes, the bear's belly).
    case squash
    /// A squeak: the duck's beak pops and a little air puffs out.
    case squeak
    /// A moving highlight: a glint runs over the surface.
    case sheen
    /// The body wobbles (jelly, yolk).
    case wobble
    /// Gel, white, yolk, filling or fizz squeezes out of the pinch line as a new lobe on the plate.
    case ooze
    /// A crease or fold line appears (vinyl, cardboard, label, cream).
    case crease
    /// A crack starts or creeps.
    case crack
    /// A crack branches.
    case branch
    /// A metal band pre-buckles.
    case buckle
    /// Gas escapes (fizz from the tab).
    case hiss
    /// Stress whitening: a seam or crack goes pale, the surface goes taut.
    case strain
    /// The tell before the break: a tremor plus the material's stress mark.
    case tell
    /// A chewy strand stretches thin and snaps.
    case strand
    /// A smear spreads on the plate.
    case smear
    /// Droplets are flung out and stay.
    case fling
    /// A piece chips off, or grit puffs.
    case chip
    /// A stress glow step (glass, steel).
    case glow
    /// A beam bends (a crayon bows).
    case bend
    /// A cardboard wall folds flat.
    case fold
    /// A chewy stretch step (the gummy bear).
    case stretch
    /// Neighbouring bubbles jiggle as the pops ripple across the sheet.
    case ripple
    /// Bits settle: a tinkle, a last puff.
    case settle
}

struct StoryBeat: Equatable, Sendable {
    let c: Float
    let kind: BeatKind
    /// Ordinal of this kind within the press (the 2nd ooze, the 3rd strand…).
    let ordinal: Int
}

enum ObjectStoryboard {
    /// The compression grid (16 beats). Worst gaps with worst-case jitter: 6.7° on the P-48 mapping (132°, ease 1.7),
    /// 4.5° on the provisional fold mapping (106°, linear).
    static let grid: [Float] = [0.01, 0.036, 0.075, 0.122, 0.178, 0.242, 0.312, 0.382, 0.452, 0.522, 0.592, 0.662, 0.732, 0.802,
                                0.872, 0.942]
    /// The two tell beats sit this far (c) before the seeded failure threshold.
    static let tellLeads: [Float] = [0.09, 0.03]
    /// Seeded jitter on every grid beat (never enough to reorder them), scaled down near contact where the mapping is
    /// steepest.
    static let jitter: Float = 0.004
    /// The design rule.
    static let gapLimitDegrees: Double = 8

    /// What happens at each grid slot, per object (16 each). See design/OBJECT-STORYBOARDS.md.
    static func gridKinds(_ kind: ObjectKind) -> [BeatKind] {
        switch kind {
        case .bubbleWrap:
            return [.kiss, .ripple, .ripple, .ripple, .ripple, .ripple, .ripple, .ripple, .ripple, .ripple, .ripple, .ripple,
                    .ripple, .crease, .settle, .sheen]
        case .rubberDuck:
            return [.kiss, .bulge, .squeak, .squash, .crease, .wobble, .squash, .sheen, .strain, .crease, .strain, .ooze,
                    .squash, .squeak, .bulge, .settle]
        case .jelly:
            return [.kiss, .wobble, .bulge, .ooze, .ooze, .strain, .ooze, .wobble, .ooze, .fling, .ooze, .wobble, .ooze,
                    .fling, .ooze, .settle]
        case .crayon:
            return [.kiss, .squash, .bend, .crease, .bend, .bend, .fold, .bend, .fold, .chip, .smear, .fold, .smear, .smear,
                    .smear, .settle]
        case .egg:
            return [.kiss, .strain, .crack, .branch, .branch, .chip, .ooze, .wobble, .strain, .ooze, .ooze, .ooze, .ooze,
                    .fling, .ooze, .settle]
        case .cakeSlice:
            return [.kiss, .bulge, .crease, .chip, .bulge, .ooze, .crease, .chip, .ooze, .crease, .ooze, .chip, .ooze,
                    .chip, .ooze, .settle]
        case .sodaCan:
            return [.kiss, .strain, .crease, .sheen, .buckle, .sheen, .crease, .sheen, .hiss, .ooze, .fling, .ooze, .crease,
                    .fling, .ooze, .settle]
        case .gummyBear:
            return [.kiss, .bulge, .stretch, .sheen, .strain, .stretch, .strain, .strand, .strand, .strand, .strand,
                    .stretch, .strand, .sheen, .stretch, .settle]
        case .glassBottle:
            return [.kiss, .glow, .chip, .crack, .glow, .crack, .strain, .settle, .sheen, .settle, .chip, .settle, .chip,
                    .sheen, .chip, .settle]
        case .unsquishable:
            return [.kiss, .sheen, .glow, .sheen, .chip, .glow, .chip, .sheen, .glow, .chip, .glow, .chip, .sheen, .chip,
                    .sheen, .settle]
        }
    }

    /// The beats for one press: the jittered grid plus the two tells before this seed's failure (if any), ascending.
    static func beats(_ kind: ObjectKind, seed: UInt64) -> [StoryBeat] {
        var rng = SplitMix64(seed: seed ^ 0x5709_B0A2)
        let kinds = gridKinds(kind)
        var raw: [(c: Float, kind: BeatKind)] = []
        for (i, c) in grid.enumerated() where i < kinds.count {
            let j = jitter * min(1, c / 0.25)
            let wiggle = i == 0 ? 0 : Float.random(in: -j...j, using: &rng)
            raw.append((clamp(c + wiggle, 0.005, 0.99), kinds[i]))
        }
        if let failure = failureThreshold(kind, seed: seed) {
            for lead in tellLeads where failure - lead > 0.02 {
                raw.append((failure - lead, .tell))
            }
        }
        raw.sort { $0.c < $1.c }
        var counts: [BeatKind: Int] = [:]
        return raw.map { entry in
            let n = counts[entry.kind, default: 0]
            counts[entry.kind] = n + 1
            return StoryBeat(c: entry.c, kind: entry.kind, ordinal: n)
        }
    }

    /// The engine's jittered failure threshold for this seed (same as `PressObjectFactory.failureThreshold`).
    static func failureThreshold(_ kind: ObjectKind, seed: UInt64) -> Float? {
        guard let index = kind.profile.failureIndex else { return nil }
        let t = kind.profile.jitteredFractures(seed: seed)
        return index < t.count ? Float(t[index]) : nil
    }

    /// Every visible event of one press in compression: contact (0), the beats and the engine's fractures, ascending.
    static func events(_ kind: ObjectKind, seed: UInt64) -> [Float] {
        let fractures = kind.profile.jitteredFractures(seed: seed).map { Float($0) }
        return ([0] + beats(kind, seed: seed).map(\.c) + fractures).sorted()
    }

    /// A press mapping, as `PressMapping` applies it once armed: compression `c` at hinge angle
    /// θ = contact − (contact − flat)·c^(1/exponent).
    struct Mapping: Sendable {
        var contact: Double
        var flat: Double = 48
        var exponent: Double
        /// The P-48 / old fold mapping (contact 132°, ease 1.7).
        static let touch = Mapping(contact: 132, exponent: 1.7)
        /// The provisional Duo fold mapping (contact 106°, linear).
        static let fold = Mapping(contact: 106, exponent: 1.0)
    }

    /// The hinge angle (degrees) at compression `c` under `mapping`.
    static func angle(compression c: Float, mapping: Mapping) -> Double {
        let x = pow(Double(clamp(c, 0, 1)), 1 / max(mapping.exponent, 0.1))
        return mapping.contact - (mapping.contact - mapping.flat) * x
    }

    /// The widest stretch of closing (degrees) with no new event between contact and `upTo` (c).
    static func maxGapDegrees(_ kind: ObjectKind, seed: UInt64, upTo end: Float = 0.97, mapping: Mapping) -> Double {
        let events = self.events(kind, seed: seed).filter { $0 <= end } + [end]
        var widest = 0.0
        for i in 1..<events.count {
            let gap = angle(compression: events[i - 1], mapping: mapping) - angle(compression: events[i], mapping: mapping)
            widest = max(widest, gap)
        }
        return widest
    }
}

/// Fires each beat once as the visual compression passes it (the plastic ratchet never un-fires one).
struct StoryCursor {
    let beats: [StoryBeat]
    private(set) var next = 0

    init(_ beats: [StoryBeat]) {
        self.beats = beats
    }

    init(_ kind: ObjectKind, seed: UInt64) {
        self.init(ObjectStoryboard.beats(kind, seed: seed))
    }

    /// The beats newly crossed at compression `c` (ascending). Nothing before contact (c = 0).
    mutating func advance(to c: Float) -> [StoryBeat] {
        guard c > 0, next < beats.count, beats[next].c <= c else { return [] }
        var crossed: [StoryBeat] = []
        while next < beats.count && beats[next].c <= c {
            crossed.append(beats[next])
            next += 1
        }
        return crossed
    }

    var fired: Int { next }
}
