import Foundation

/// The moments a per-object recipe answers. Shared press sounds (hiss, motor, creak, gauge ticks, hush,
/// bottom-out, ka-chunk, sting, chime, fanfare) live in the controllers and `BrandCues`, not here.
enum RecipeMoment: Equatable, Sendable {
    /// The object landed on the anvil (bible §3.1 beat 0).
    case place
    case contact
    /// One grain of the compliance illusion. After the failure these are the crush grains.
    case grain(compression: Float)
    case preFailureTell
    /// One of the accelerating micro-cracks during the tell (index 0, 1, 2…).
    case microCrack(index: Int)
    case fracture(index: Int, isFailure: Bool)
    /// The user started opening while loaded (elastic unload).
    case released
    /// The material reveal flourish, under the fixed sting.
    case reveal

    init?(_ event: PressEvent) {
        switch event {
        case .contact: self = .contact
        case .grain(let compression): self = .grain(compression: Float(compression))
        case .preFailureTell: self = .preFailureTell
        case .fracture(let index, let isFailure): self = .fracture(index: index, isFailure: isFailure)
        case .released: self = .released
        case .reveal: self = .reveal
        case .armed, .hush, .bottomOut, .sealed, .kaChunk: return nil
        }
    }
}

/// Everything a recipe may read. `dice` is the only source of randomness, so a seeded press replays exactly.
struct RecipeInput {
    var context: FeedbackContext
    var dice: FeedbackDice
    /// The big failure already happened in this press (we're in the crush).
    var hasFailed: Bool
    /// Fractures fired before this moment.
    var fracturesFired: Int

    /// A fast slam fails with more debris (01 §7.3 notes: debris ×1.5).
    var debris: Float { context.closingSpeed > 120 ? 1.5 : 1 }
}

/// Per-object feedback: sounds and haptics for every moment, designed together.
protocol ObjectRecipe {
    var kind: ObjectKind { get }
    /// Continuous layers the controllers steer every frame.
    var beds: MaterialBeds { get }
    func cue(for moment: RecipeMoment, _ input: RecipeInput) -> FeedbackCue
}

extension ObjectRecipe {
    func slot(_ event: String, _ layer: String) -> SoundSlot {
        .object(kind, event, layer)
    }
}

/// The strain loop: filtered noise whose gain follows strain and speed (02 §7.2).
struct NoiseBed: Sendable, Equatable {
    var filter: NoiseFilter
    var cutoff: Float
    var q: Float
    var gain: Float
    var flutterRate: Float
    var flutterDepth: Float
    /// Cutoff multiplier gained at full strain (the bed tightens as pressure builds).
    var cutoffRise: Float
    var isWet: Bool

    init(_ filter: NoiseFilter, _ cutoff: Float, q: Float, gain: Float, flutter: Float, depth: Float,
         rise: Float = 0, wet: Bool = false) {
        self.filter = filter
        self.cutoff = cutoff
        self.q = q
        self.gain = gain
        flutterRate = flutter
        flutterDepth = depth
        cutoffRise = rise
        isWet = wet
    }
}

/// The post-failure granular crush/squelch bed: grain rate = base · speed · fresh (02 §7.2).
struct GrainBed: Sendable, Equatable {
    var rate: Float
    var low: Float
    var high: Float
    var q: Float
    var grainDecay: Float
    var gain: Float
    var isWet: Bool

    init(rate: Float, band: ClosedRange<Float>, q: Float, grain: Float, gain: Float, wet: Bool = false) {
        self.rate = rate
        low = band.lowerBound
        high = band.upperBound
        self.q = q
        grainDecay = grain
        self.gain = gain
        isWet = wet
    }
}

/// How the haptic strain bed rises towards the failure (01 §7.3 "strain curve").
enum StrainCurve: Sendable, Equatable {
    case linear
    /// Steep and late: brittle things give nothing away (crayon, glass, steel).
    case easeIn
    /// Gives early: gels.
    case easeOut
    /// Soda can: rises, drops 40 % after each buckle, recovers over the next Δc 0.1.
    case stepwise

    func level(_ progress: Float, sinceFracture: Float, fractures: Int) -> Float {
        let x = min(max(progress, 0), 1)
        switch self {
        case .linear:
            return x
        case .easeIn:
            return x * x
        case .easeOut:
            return 1 - (1 - x) * (1 - x)
        case .stepwise:
            guard fractures > 0 else { return x }
            return x * min(1, 0.6 + 0.4 * max(sinceFracture, 0) / 0.1)
        }
    }
}

/// The continuous layers of one material.
struct MaterialBeds: Sendable, Equatable {
    /// Audio strain loop while loaded and before the failure.
    var strain: NoiseBed
    /// Audio granular crush bed after the failure.
    var crush: GrainBed
    /// Press-frame creak tint (resonator pitch multiplier) and amount 0…1.
    var creakPitch: Float
    var creakAmount: Float
    /// Haptic strain curve and its ceiling (never above 0.7 before the failure, bible §7).
    var hapticCurve: StrainCurve
    var hapticMax: Float
    /// Crush-phase haptic bed (01 §6 step 7): intensity, and sharpness offset against the material bed.
    var crushHapticIntensity: Float
    var crushHapticSharpness: Float
}

enum Recipes {
    static func recipe(for kind: ObjectKind) -> any ObjectRecipe {
        switch kind {
        case .bubbleWrap: return BubbleWrapRecipe()
        case .rubberDuck: return RubberDuckRecipe()
        case .jelly: return JellyRecipe()
        case .crayon: return CrayonRecipe()
        case .egg: return EggRecipe()
        case .cakeSlice: return CakeSliceRecipe()
        case .sodaCan: return SodaCanRecipe()
        case .gummyBear: return GummyBearRecipe()
        case .glassBottle: return GlassBottleRecipe()
        case .unsquishable: return UnsquishableRecipe()
        }
    }

    /// Strain progress 0…1 towards the material's nominal failure, so every object's tension peaks at its break
    /// (an egg failing at c 0.24 still reaches full strain). Objects without a failure use c / 0.85.
    static func strainProgress(_ compression: Float, kind: ObjectKind) -> Float {
        let profile = kind.profile
        let failure: Double = profile.failureIndex.map { profile.fractures[$0] } ?? 0.85
        return min(max(compression / Float(max(failure, 0.15)), 0), 1)
    }
}
