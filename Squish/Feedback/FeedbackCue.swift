import Foundation

// MARK: - Slots (bible §15.1)

/// Names a sound by its role, never by a file: `glass.failure.body`, `press.kachunk.thock`.
/// v1 synthesises every slot; `audio/manifest.json` will later map slots to sampled files.
struct SoundSlot: Hashable, Sendable, CustomStringConvertible {
    let id: String

    init(_ id: String) {
        self.id = id
    }

    var description: String { id }

    static func object(_ kind: ObjectKind, _ event: String, _ layer: String) -> SoundSlot {
        SoundSlot("\(kind.slotPrefix).\(event).\(layer)")
    }

    static func press(_ event: String, _ layer: String) -> SoundSlot {
        SoundSlot("press.\(event).\(layer)")
    }
}

extension ObjectKind {
    /// Short, stable slot prefix. Never rename one: the sample manifest keys off it.
    var slotPrefix: String {
        switch self {
        case .bubbleWrap: "bubblewrap"
        case .rubberDuck: "duck"
        case .jelly: "jelly"
        case .crayon: "crayon"
        case .egg: "egg"
        case .cakeSlice: "cake"
        case .sodaCan: "can"
        case .gummyBear: "gummy"
        case .glassBottle: "glass"
        case .unsquishable: "unsquishable"
        }
    }
}

// Recorded foley (bible §15.1's sampled layers) arrives as `.sample` synth commands that the CueBook adds
// (`SampleVoicing`); the old per-layer `SampleBank` seam is retired (SOUND-2 §5.1 item 4).

// MARK: - Cue

/// One synthesised layer of a sound, tagged with its slot.
struct SoundLayer: Equatable, Sendable {
    var slot: SoundSlot
    var command: SynthCommand
    /// Liquid/goo layers. Soft style drops them (misophonia, 02 §6).
    var isWet = false
}

/// One haptic event, in Core Haptics units (0…1). Converted to `CHHapticEvent` by `HapticsController`,
/// which applies the user level, jitter, the 12 ms transient gap and the intensity cap.
struct HapticNote: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case transient, continuous }

    var kind: Kind
    var time: Double
    var intensity: Float
    var sharpness: Float
    var duration: Double = 0
    var attack: Float = 0
    var decay: Float = 0
    var release: Float = 0
    var sustained = false

    static func tap(_ intensity: Float, _ sharpness: Float, at time: Double = 0) -> HapticNote {
        HapticNote(kind: .transient, time: time, intensity: intensity, sharpness: sharpness)
    }

    /// A continuous event that decays (unsustained) over `decay`, defaulting to 80 % of its duration.
    static func buzz(_ intensity: Float, _ sharpness: Float, at time: Double = 0, duration: Double,
                     attack: Float = 0, decay: Float? = nil, release: Float = 0) -> HapticNote {
        HapticNote(kind: .continuous, time: time, intensity: intensity, sharpness: sharpness, duration: duration,
                   attack: attack, decay: decay ?? Float(duration * 0.8), release: release, sustained: false)
    }
}

/// A sharpness-control sweep over a whole cue (the duck squeak chirp, 01 §7.3).
struct HapticSweep: Equatable, Sendable {
    var from: Float
    var to: Float
    var duration: Double
}

/// What a recipe returns for one moment: sound layers and haptic notes designed together
/// (Apple's causality/harmony/utility, bible §1 pillar 3).
struct FeedbackCue: Equatable, Sendable {
    var sounds: [SoundLayer] = []
    var haptics: [HapticNote] = []
    var sharpnessSweep: HapticSweep?
    /// Only failure and the ka-chunk may reach haptic intensity 1.0 (bible §7). Everything else is capped at 0.85.
    var isClimax = false

    static let silent = FeedbackCue()

    var isEmpty: Bool { sounds.isEmpty && haptics.isEmpty }

    mutating func add(_ other: FeedbackCue) {
        sounds += other.sounds
        haptics += other.haptics
        if sharpnessSweep == nil { sharpnessSweep = other.sharpnessSweep }
        isClimax = isClimax || other.isClimax
    }

    /// Soft style (bible §8): no wet layers and a gentler, half-density crunch. The 6 kHz low-pass is in the synth master.
    func styled(_ style: SoundStyle) -> FeedbackCue {
        switch style {
        case .workshop:
            return self
        case .soft:
            var copy = self
            copy.sounds = sounds.compactMap { layer -> SoundLayer? in
                guard !layer.isWet else { return nil }
                var softened = layer
                softened.command = layer.command.softened
                return softened
            }
            return copy
        }
    }

    func adding(_ other: FeedbackCue) -> FeedbackCue {
        var copy = self
        copy.add(other)
        return copy
    }

    /// The whole cue, sound and touch together, starting `seconds` later.
    func delayed(by seconds: Double) -> FeedbackCue {
        var copy = self
        copy.sounds = sounds.map { layer -> SoundLayer in
            var shifted = layer
            shifted.command = layer.command.delayed(by: Float(seconds))
            return shifted
        }
        copy.haptics = haptics.map { note -> HapticNote in
            var shifted = note
            shifted.time = max(note.time + seconds, 0)
            return shifted
        }
        return copy
    }

    func scaledSounds(_ factor: Float) -> FeedbackCue {
        var copy = self
        copy.sounds = sounds.map { layer -> SoundLayer in
            var scaled = layer
            scaled.command = layer.command.scaled(factor)
            return scaled
        }
        return copy
    }
}

// MARK: - Sound builders

extension SoundLayer {
    static func noise(_ slot: SoundSlot, _ filter: NoiseFilter, _ cutoff: Float, q: Float = 1, attack: Float = 0.0005,
                      decay: Float, gain: Float, delay: Float = 0, sweepTo: Float? = nil, sweepTime: Float? = nil,
                      wet: Bool = false) -> SoundLayer {
        let spec = NoiseSpec(filter: filter, cutoff: cutoff, cutoffEnd: sweepTo ?? cutoff, sweepTime: sweepTime ?? decay * 3,
                             q: q, attack: attack, decay: decay, gain: gain, delay: max(delay, 0))
        return SoundLayer(slot: slot, command: .noise(spec), isWet: wet)
    }

    static func tone(_ slot: SoundSlot, _ start: Float, to end: Float? = nil, glide: Float? = nil, duration: Float,
                     attack: Float = 0.002, decay: Float? = nil, gain: Float, harmonics: Int = 1, vibrato: Float = 0,
                     depth: Float = 0, delay: Float = 0, wet: Bool = false) -> SoundLayer {
        let spec = ToneSpec(start: start, end: end ?? start, glide: glide ?? duration * 0.8, duration: duration,
                            attack: attack, decay: decay ?? duration * 0.25, gain: gain, harmonics: harmonics,
                            vibratoRate: vibrato, vibratoDepth: depth, delay: max(delay, 0))
        return SoundLayer(slot: slot, command: .tone(spec), isWet: wet)
    }

    static func ring(_ slot: SoundSlot, _ mode: RingMode, _ fundamental: Float, partials: Int = 8, decay: Float,
                     brightness: Float = 0.6, gain: Float, delay: Float = 0, seed: UInt32 = 1,
                     wet: Bool = false) -> SoundLayer {
        let spec = RingSpec(mode: mode, fundamental: fundamental, partials: partials, decay: decay,
                            brightness: brightness, gain: gain, delay: max(delay, 0), seed: seed)
        return SoundLayer(slot: slot, command: .ring(spec), isWet: wet)
    }

    static func crunch(_ slot: SoundSlot, _ band: ClosedRange<Float>, duration: Float, rate: Float, rateEnd: Float? = nil,
                       q: Float = 1.2, grain: Float = 0.004, gain: Float, fade: Float = 0.25, delay: Float = 0,
                       wet: Bool = false) -> SoundLayer {
        let spec = CrunchSpec(duration: duration, rate: rate, rateEnd: rateEnd ?? rate * 0.3, low: band.lowerBound,
                              high: band.upperBound, q: q, grainDecay: grain, gain: gain, gainEnd: fade, delay: max(delay, 0))
        return SoundLayer(slot: slot, command: .crunch(spec), isWet: wet)
    }
}

// MARK: - Dice

/// Seeded randomness for recipes. Pitches follow 02 §2.2: grains ±1.5 st, bodies ±0.7 st, gain ±2 dB,
/// a per-press tone offset of ±0.5 st, and round-robin picks that never repeat back to back.
/// Brand sounds never touch the dice.
final class FeedbackDice {
    private var rng: SplitMix64
    private var lastPicks: [SoundSlot: Int] = [:]
    /// Per-press tone offset (bible §4), set from the variant seed on every placement.
    private(set) var tone: Float = 1

    init(seed: UInt64) {
        rng = SplitMix64(seed: seed)
    }

    /// Restart the sequence for a new press. The no-repeat memory survives on purpose.
    func reseed(_ seed: UInt64) {
        rng = SplitMix64(seed: seed)
        tone = 1
        tone = semitones(0.5)
    }

    func unit() -> Float {
        Float.random(in: 0..<1, using: &rng)
    }

    func range(_ bounds: ClosedRange<Float>) -> Float {
        Float.random(in: bounds, using: &rng)
    }

    func time(_ bounds: ClosedRange<Double>) -> Double {
        Double.random(in: bounds, using: &rng)
    }

    func chance(_ probability: Float) -> Bool {
        unit() < probability
    }

    func semitones(_ spread: Float) -> Float {
        pow(2, range(-abs(spread)...abs(spread)) / 12)
    }

    func decibels(_ spread: Float) -> Float {
        pow(10, range(-abs(spread)...abs(spread)) / 20)
    }

    /// Grain pitch multiplier: ±1.5 st, times the press tone.
    func grainPitch() -> Float { semitones(1.5) * tone }

    /// Body pitch multiplier: ±0.7 st, times the press tone.
    func bodyPitch() -> Float { semitones(0.7) * tone }

    /// Gain multiplier: ±2 dB.
    func level() -> Float { decibels(2) }

    func seed32() -> UInt32 {
        UInt32(truncatingIfNeeded: rng.next())
    }

    /// Round-robin variant index in `0..<count` that never repeats the previous pick for `slot`.
    func pick(_ count: Int, for slot: SoundSlot) -> Int {
        guard count > 1 else { return 0 }
        let choice: Int
        if let last = lastPicks[slot] {
            let raw = Int.random(in: 0..<(count - 1), using: &rng)
            choice = raw >= last ? raw + 1 : raw
        } else {
            choice = Int.random(in: 0..<count, using: &rng)
        }
        lastPicks[slot] = choice
        return choice
    }

    /// A burst of transients with exponentially falling intensity and random 0.6–1.4× gaps
    /// (crunch, shatter tinkles, crumbs; 01 §2.2).
    func scatter(_ count: Int, from start: Double, over span: Double, intensity: (Float, Float),
                 sharpness: ClosedRange<Float>) -> [HapticNote] {
        guard count > 0 else { return [] }
        let first = max(intensity.0, 0.01)
        let last = max(intensity.1, 0.01)
        let mean = span / Double(count)
        var notes: [HapticNote] = []
        notes.reserveCapacity(count)
        var time = start
        for index in 0..<count {
            let progress = count > 1 ? Float(index) / Float(count - 1) : 0
            notes.append(.tap(first * pow(last / first, progress), range(sharpness), at: time))
            time += mean * self.time(0.6...1.4)
        }
        return notes
    }
}

// MARK: - Deterministic pulse trains

/// A pulse train both controllers advance identically from the same engine state, so audio and haptic
/// micro-events (pre-failure micro-cracks, settling creaks) land together without the controllers talking.
struct PulseSchedule {
    enum Kind {
        /// Micro-cracks accelerating from 3 to 15 per second over the tell (01 §6 step 4).
        case tell
        /// A settling creak every 0.8–2.0 s while held under load (bible §7).
        case settle
    }

    let kind: Kind
    private(set) var isRunning = false
    private var clock: Double = 0
    private var nextTime: Double = 0
    private var index = 0
    private var seed: UInt64 = 0

    init(kind: Kind) {
        self.kind = kind
    }

    mutating func start(seed: UInt64) {
        self.seed = seed
        isRunning = true
        clock = 0
        index = 0
        nextTime = interval(0)
    }

    mutating func stop() {
        isRunning = false
    }

    /// Advances the clock and returns the index of a pulse that became due (at most one per frame).
    mutating func advance(by dt: Double) -> Int? {
        guard isRunning else { return nil }
        clock += dt
        if kind == .tell && clock > 3 {
            isRunning = false
            return nil
        }
        guard clock >= nextTime else { return nil }
        let fired = index
        index += 1
        nextTime += interval(index)
        return fired
    }

    func interval(_ k: Int) -> Double {
        var rng = SplitMix64(seed: seed &+ UInt64(k + 1) &* 0x9E37_79B9_7F4A_7C15)
        let u = Double.random(in: 0...1, using: &rng)
        switch kind {
        case .tell:
            return max(1.0 / 15, (1.0 / 3) * pow(0.8, Double(k))) * (0.85 + 0.3 * u)
        case .settle:
            return 0.8 + 1.2 * u
        }
    }
}
