import Foundation

/// Builds each recipe cue once and hands the same cue to both controllers, so the sound and the haptic
/// of one moment share every random choice (variant, pitch, timing jitter): Apple's "harmony".
///
/// The director calls `haptics.handle(e)` then `audio.handle(e)` for each event (and `audio.place` then
/// `haptics.place`). Whichever controller asks first generates the cue; the other one receives the same cue
/// if it asks for the same key before anyone asks for something new. Order doesn't matter, and a controller
/// that skips a moment never desynchronises the other.
@MainActor
final class CueBook {
    static let shared = CueBook()

    enum Consumer {
        case audio, haptics
    }

    /// Press sounds that carry a recording layered under the synth (SOUND-2 §3.3), so they go through the book too:
    /// both controllers then share the file pick and its haptic onsets.
    enum BrandMoment: Equatable {
        case kaChunk, contact, stamp
    }

    enum Key: Equatable {
        case recipe(RecipeMoment)
        /// The n-th settling creak of the current hold (shared, tinted by the material's creak).
        case settle(Int)
        case brand(BrandMoment)
    }

    /// What the recipes need to know about the press so far. Updated when a cue is generated.
    struct PressMemory: Equatable {
        var hasFailed = false
        var fractures = 0
        var lastFractureCompression: Float = 0
    }

    private struct Entry {
        var key: Key
        var kind: ObjectKind
        var cue: FeedbackCue
        var audioTaken: Bool
        var hapticsTaken: Bool

        func taken(by consumer: Consumer) -> Bool {
            switch consumer {
            case .audio: audioTaken
            case .haptics: hapticsTaken
            }
        }

        mutating func take(_ consumer: Consumer) {
            switch consumer {
            case .audio: audioTaken = true
            case .haptics: hapticsTaken = true
            }
        }
    }

    private(set) var memory = PressMemory()
    private let dice: FeedbackDice
    /// Sample picks have their own dice, reseeded per press, so whether the library has loaded yet never shifts the
    /// recipes' own random choices.
    private let sampleDice: FeedbackDice
    /// Recent cues, newest last: a consumer gets the newest entry for its key it hasn't taken yet. A short history
    /// (not just the latest) lets one event ask for two keys (a recipe moment and a brand layer) in any order.
    private var recent: [Entry] = []
    /// Where recordings come from: the live book plays them once loaded; an offline book loads them now.
    var library: () -> SampleLibrary? = { SampleLibrary.loaded }

    init(seed: UInt64 = 0x5157_1534) {
        dice = FeedbackDice(seed: seed)
        sampleDice = FeedbackDice(seed: seed ^ 0x5A3D_1E5A)
    }

    func cue(for key: Key, context: FeedbackContext, consumer: Consumer) -> FeedbackCue {
        if let index = recent.lastIndex(where: { $0.key == key && $0.kind == context.kind && !$0.taken(by: consumer) }) {
            recent[index].take(consumer)
            return recent[index].cue
        }
        if case .recipe(.place) = key {
            // A new press: replayable from its seed (share clips), with a fresh per-press tone.
            dice.reseed(context.variant.seed)
            sampleDice.reseed(context.variant.seed ^ 0x5A3D_1E5A)
            memory = PressMemory()
        }
        var cue = Self.compose(key, context: context, dice: dice, memory: memory)
        var explicit: [String]?
        if case .brand(.stamp) = key { explicit = ["press.stamp"] }
        cue = SampleVoicing.voice(cue, keys: explicit, style: context.soundStyle, speed: min(max(context.closingSpeed / 120, 0), 1),
                                  library: library(), dice: sampleDice)
        if case let .recipe(.fracture(_, isFailure)) = key {
            memory.fractures += 1
            memory.lastFractureCompression = context.compression
            if isFailure { memory.hasFailed = true }
        }
        var entry = Entry(key: key, kind: context.kind, cue: cue, audioTaken: false, hapticsTaken: false)
        entry.take(consumer)
        recent.append(entry)
        if recent.count > 8 { recent.removeFirst(recent.count - 8) }
        return cue
    }

    /// Recipe cue plus the shared extras: fracture gain follows speed (02 §7.2 "event gain 0.7 + 0.3·v"),
    /// and the reveal gets the golden shimmer and the surprise flourish.
    static func compose(_ key: Key, context: FeedbackContext, dice: FeedbackDice, memory: PressMemory) -> FeedbackCue {
        let recipe = Recipes.recipe(for: context.kind)
        switch key {
        case .brand(let moment):
            switch moment {
            case .kaChunk: return BrandCues.kaChunk
            case .contact: return BrandCues.contact
            case .stamp: return FeedbackCue()
            }
        case .settle:
            return SharedCues.settle(recipe.beds, dice: dice)
        case .recipe(let moment):
            let input = RecipeInput(context: context, dice: dice, hasFailed: memory.hasFailed, fracturesFired: memory.fractures)
            var cue = recipe.cue(for: moment, input)
            switch moment {
            case .fracture:
                let speed = min(max(context.closingSpeed / 120, 0), 1)
                cue = cue.scaledSounds(0.7 + 0.3 * speed)
            case .reveal:
                cue.add(SharedCues.reveal(context, dice: dice))
            case .place, .contact, .grain, .preFailureTell, .microCrack, .released:
                break
            }
            return cue
        }
    }

    /// A cue built outside the live press (Tuning Lab audition). Never touches the shared sync state.
    static func preview(_ moment: RecipeMoment, context: FeedbackContext, dice: FeedbackDice) -> FeedbackCue {
        var memory = PressMemory()
        if case let .fracture(index, isFailure) = moment {
            memory.fractures = index
            if !isFailure, let failure = context.kind.profile.failureIndex, index > failure {
                memory.hasFailed = true
            }
        }
        return compose(.recipe(moment), context: context, dice: dice, memory: memory)
    }
}

/// Builds plausible contexts for auditioning a moment in the Tuning Lab.
enum Audition {
    static func context(for kind: ObjectKind, event: PressEvent, golden: Bool = false, surprise: Surprise? = nil) -> FeedbackContext {
        var variant = PressVariant(kind: kind, seed: UInt64.random(in: 1...UInt64.max))
        variant.isGolden = golden
        variant.surprise = surprise
        let compression: Float
        switch event {
        case .grain(let c): compression = Float(c)
        case .fracture(let index, _):
            let fractures = kind.profile.fractures
            compression = Float(fractures[min(max(index, 0), fractures.count - 1)])
        case .preFailureTell: compression = 0.3
        case .bottomOut, .sealed, .kaChunk: compression = 1
        case .armed, .contact, .hush, .released, .reveal: compression = 0
        }
        return FeedbackContext(kind: kind, variant: variant, compression: compression, closingSpeed: 60,
                               soundStyle: .workshop, reduceMotion: false)
    }
}
