import Foundation

// The hinge outside the press (founder, after the first real-Duo test: opening and closing the phone should always
// sound and feel like something; "everything should be together and it should make sense").
//
// - A hinge creak whose rate, level and pitch follow angular velocity, silent when still (audio bed).
// - A continuous haptic texture while the hinge moves (the haptic bed player, when the press isn't loaded).
// - A ratchet detent every 6° of travel: a click and a matching tick, softer while opening.
// - A power-up as the shut phone opens, and a soft clack as it shuts outside a press.
// - The reveal (reopen after a seal) gets the unlatch clunk + hiss (`BrandCues.unlatch`, in both controllers).
//
// Quiet by design: the hinge layer is the quietest thing in the mix (detents ≈ −30 dBFS, creak ≈ −40 dBFS before the
// master), so the press stays the loudest. Under load the press takes over: no detents (the gauge ticks and grains
// speak), no hinge creak (the press creak does).
//
// Sync: every discrete moment is one `FeedbackCue` handed to both controllers in the same frame, like CueBook cues.
//
// Inputs: the director builds `HingeMotionInput` from the engine every frame (the continuous bed and the shut clack),
// and maps the engine's beats (`PressBeat.detent / .powerUp / .powerDown`, Core/PressFeel.swift) to `HingeMoment`s,
// so the ratchet you hear and feel is the same detent the Fold stage draws.

/// What the hinge is doing this frame.
struct HingeMotionInput: Equatable {
    /// False when no real hinge drives the press (P-48 touch press, "Press without folding"): the layer is off.
    var available: Bool
    /// Filtered hinge angle, degrees (180 = flat).
    var angle: Double
    /// Degrees per second, positive while closing.
    var speed: Double
    /// False while the hinge holds still (no fresh sample, or below 3 °/s).
    var moving: Bool
    /// The phone is really shut: the engine's angle-based shut (`PressEngine.isClosed`), never the raw status.
    var shut: Bool
    var phase: PressPhase
    /// The plates are on the object: the press feedback owns the moment.
    var loaded: Bool
}

/// Continuous hinge layers for this frame.
struct HingeBed: Equatable {
    var creakRate: Float = 0
    var creakGain: Float = 0
    var creakPitch: Float = 1
    /// Haptic bed intensity (before the user level) and absolute sharpness.
    var texture: Float = 0
    var textureSharpness: Float = 0.35

    static let still = HingeBed()
}

enum HingeMoment: Equatable {
    case detent(closing: Bool)
    /// The machine powered up as the phone opened (`PressBeat.powerUp`, or detected here).
    case opened
    /// The machine powered down as the phone closed outside a press (`PressBeat.powerDown`).
    case powerDown
    /// The phone physically shut outside a press: the plates meet with nothing between them.
    case shut
}

/// Ratchet detents every `spacing` degrees, with hysteresis so sensor jitter (±5° class, but filtered) never chatters.
struct DetentTracker {
    static let spacing = 6.0
    static let hysteresis = 1.5
    /// A fast swing clicks at most this often (it would buzz otherwise).
    static let minGap = 0.045

    private var index: Int?
    private var lastClick = -Double.infinity

    mutating func reset() {
        index = nil
    }

    /// Returns the direction of a detent crossed at `angle` (true = closing), or nil.
    mutating func track(angle: Double, at time: Double) -> Bool? {
        let k = Int((angle / Self.spacing).rounded(.down))
        guard let current = index else {
            index = k
            return nil
        }
        let lower = Double(current) * Self.spacing - Self.hysteresis
        let upper = Double(current + 1) * Self.spacing + Self.hysteresis
        let closing: Bool
        if angle < lower {
            closing = true
        } else if angle > upper {
            closing = false
        } else {
            return nil
        }
        index = k
        guard time - lastClick >= Self.minGap else { return nil }
        lastClick = time
        return closing
    }
}

/// Turns hinge motion into the continuous bed and discrete moments. Pure apart from its own state; unit-tested.
struct HingeFeel {
    /// Opening past this from shut counts as "the phone opened" (the inner display is lit by ~55°).
    static let openedAngle = 55.0
    /// At or below this the phone counts as shut. Never the raw `.closed` status: on a real Duo it reads closed at
    /// ~85° while closing and clears at ~21° on reopen (founder's hinge log), so it would clack at 85°.
    static let shutAngle = 10.0
    /// Angular speed (°/s) that counts as a brisk swing for the creak and texture.
    static let briskSpeed = 90.0

    /// True: detents and the open power-up are detected here. The director sets it false because the engine delivers
    /// them as beats (`PressBeat.detent / .powerUp / .powerDown`, Core/PressFeel.swift) and maps each to a
    /// `HingeMoment`, so nothing doubles. The physical shut clack is always detected here (no beat for it).
    var detectsDetentsAndPower = true

    private var detents = DetentTracker()
    private var wasShut: Bool?
    private var openedArmed = false

    mutating func update(_ input: HingeMotionInput, at time: Double) -> (bed: HingeBed, moments: [HingeMoment]) {
        let result = track(input, at: time)
        let moments = detectsDetentsAndPower ? result.moments : result.moments.filter { $0 == .shut }
        return (result.bed, moments)
    }

    private mutating func track(_ input: HingeMotionInput, at time: Double) -> (bed: HingeBed, moments: [HingeMoment]) {
        guard input.available else {
            detents.reset()
            wasShut = nil
            return (.still, [])
        }
        var moments: [HingeMoment] = []
        let shut = input.shut || input.angle < Self.shutAngle
        if let wasShut {
            if shut && !wasShut {
                // A press's seal has its ka-chunk; any other shut gets the soft clack.
                if input.phase != .sealed && !input.loaded { moments.append(.shut) }
                openedArmed = true
            }
        } else {
            // The first reading is a state, not a transition (as in PressEngine.ingestSample).
            openedArmed = shut
        }
        wasShut = shut
        if openedArmed && !shut && input.angle >= Self.openedAngle {
            openedArmed = false
            // A reopen after a seal is the reveal, which has its own unlatch clunk.
            if input.phase != .sealed && input.phase != .revealing { moments.append(.opened) }
        }

        if shut || input.loaded {
            detents.reset()
        } else if let closing = detents.track(angle: input.angle, at: time) {
            moments.append(.detent(closing: closing))
        }

        var bed = HingeBed()
        if input.moving && !shut && !input.loaded {
            let v = Float(min(abs(input.speed) / Self.briskSpeed, 1))
            bed.creakRate = 5 + 35 * v
            bed.creakGain = 0.004 + 0.012 * v
            bed.creakPitch = 0.8 + 0.35 * v
            bed.texture = 0.03 + 0.1 * v   // before HapticTuning.lift: ≈ 0.12 … 0.3 felt
            bed.textureSharpness = 0.3 + 0.2 * v
        }
        return (bed, moments)
    }
}

/// EXPERIENCE-REVIEW-1 #7: the seal stroke. After bottom-out (~55°) the last ~45° to the real shut (≤ 10°) must *build to*
/// the ka-chunk, not coast: a rising hydraulic whine (the motor hum, pitched and swelled with progress), a latch
/// click and 0.4 tap every 9°, and a haptic ramp 0.3 → 0.6 into the 1.0 ka-chunk. Pure; driven by the display-rate angle.
struct SealStroke {
    static let latchSpacing = 9.0

    private(set) var from: Double?
    private var nextLatch = 0.0

    var isActive: Bool { from != nil }

    mutating func begin(at angle: Double) {
        from = angle
        nextLatch = angle - Self.latchSpacing
    }

    mutating func end() {
        from = nil
    }

    /// Progress 0…1 from bottom-out to the shut, and the latches crossed this frame (as their progress).
    mutating func update(angle: Double, shutAngle: Double) -> (progress: Float, latches: [Float]) {
        guard let from, from > shutAngle + 1 else { return (0, []) }
        let span = from - shutAngle
        let progress = Float(min(max((from - angle) / span, 0), 1))
        var latches: [Float] = []
        if angle <= nextLatch && nextLatch > shutAngle {
            latches.append(Float(min(max((from - nextLatch) / span, 0), 1)))
            // At most one per frame: a slam skips latches rather than machine-gunning them.
            while nextLatch >= angle { nextLatch -= Self.latchSpacing }
        }
        return (progress, latches)
    }

    /// The haptic ramp during the stroke (before the user's level).
    static func hapticRamp(_ progress: Float) -> Float { 0.3 + 0.3 * min(max(progress, 0), 1) }
}

/// Sound and touch for each hinge moment, designed together (one cue for both controllers).
enum HingeCues {
    static func cue(for moment: HingeMoment, speed: Double, dice: FeedbackDice) -> FeedbackCue {
        let slot = { (event: String, layer: String) in SoundSlot.press("hinge.\(event)", layer) }
        let v = Float(min(abs(speed) / HingeFeel.briskSpeed, 1))
        switch moment {
        case .detent(let closing):
            // A small ratchet: a dry click and a tiny woody tock; the tick under the thumb.
            let level = (closing ? 1 : 0.7) * (0.6 + 0.4 * v) * dice.level()
            return FeedbackCue(sounds: [
                .noise(slot("detent", "click"), .bandPass, 2600 * dice.grainPitch(), q: 3, attack: 0.0002, decay: 0.0018,
                       gain: 0.05 * level),
                .tone(slot("detent", "tock"), 820 * dice.grainPitch(), to: 700, glide: 0.01, duration: 0.025,
                      attack: 0.0005, decay: 0.006, gain: 0.018 * level),
            ], haptics: [.tap((closing ? 0.24 : 0.17) * (0.7 + 0.3 * v), 0.85)])
        case .opened:
            // Power-up: a soft rising hum and a small "ready" click as the press wakes.
            return FeedbackCue(sounds: [
                .tone(slot("open", "hum"), 150, to: 300, glide: 0.3, duration: 0.42, attack: 0.12, decay: 0.12,
                      gain: 0.05, harmonics: 3),
                .noise(slot("open", "click"), .bandPass, 2200, q: 2, attack: 0.0003, decay: 0.003, gain: 0.07, delay: 0.3),
                .tone(slot("open", "tink"), 1046.5, duration: 0.08, attack: 0.002, decay: 0.025, gain: 0.03, delay: 0.3),
            ], haptics: [
                .buzz(0.25, 0.3, duration: 0.3, attack: 0.25, decay: 0.05),
                .tap(0.4, 0.7, at: 0.3),
            ])
        case .powerDown:
            // Power-down: the hum falls away with a soft off click (the lamps dim with it).
            return FeedbackCue(sounds: [
                .tone(slot("powerdown", "hum"), 280, to: 130, glide: 0.3, duration: 0.36, attack: 0.01, decay: 0.12,
                      gain: 0.04, harmonics: 3),
                .noise(slot("powerdown", "click"), .bandPass, 1600, q: 2, attack: 0.0003, decay: 0.003, gain: 0.05),
            ], haptics: [.tap(0.3, 0.5), .buzz(0.18, 0.2, at: 0.01, duration: 0.25, decay: 0.2)])
        case .shut:
            // A soft magnetic clack: the two plates meeting with nothing between them.
            return FeedbackCue(sounds: [
                .tone(slot("shut", "thock"), 140, to: 80, glide: 0.04, duration: 0.09, attack: 0.001, decay: 0.025,
                      gain: 0.16, harmonics: 3),
                .noise(slot("shut", "clack"), .bandPass, 1800, q: 1.5, attack: 0.0003, decay: 0.004, gain: 0.08),
            ], haptics: [.tap(0.6, 0.35), .tap(0.25, 0.5, at: 0.05)])
        }
    }
}

/// Sound and touch for the engine's press beats (`PressBeat`, Core/PressFeel.swift) that aren't `PressEvent`s.
/// Material-aware where it matters: debris and settle ticks sit in the material's crush band.
enum BeatCues {
    /// One creak of a held press (0.6–1.2 s apart, quicker as the tension rises): the settling creak, scaled by tension.
    static func creak(_ kind: ObjectKind, intensity: Double, dice: FeedbackDice) -> FeedbackCue {
        let scale = Float(0.6 + 0.6 * min(max(intensity, 0), 1))
        var cue = SharedCues.settle(Recipes.recipe(for: kind).beds, dice: dice).scaledSounds(scale)
        cue.haptics = cue.haptics.map { note in
            var louder = note
            louder.intensity = min(note.intensity * (1 + Float(intensity)), 0.6)
            return louder
        }
        return cue
    }

    /// A storyboard beat (Scene/Kit/Storyboard.swift): the visible deformation event every ≤ 4.5° of closing. A quiet
    /// synthesised grain in the material's band, slot `<object>.beat-<kind>.grain`, which `SampleMap` voices with the
    /// matching recording; a light tick. Always smaller than the fractures, so the press builds.
    static func story(_ kind: ObjectKind, beat: BeatKind, speed: Float, dice: FeedbackDice) -> FeedbackCue? {
        let beds = Recipes.recipe(for: kind).beds
        let slot = SoundSlot.object(kind, "beat-\(beat.rawValue)", "grain")
        let v = min(max(speed, 0), 1)
        let sharpness = min(max(kind.profile.bedSharpness, 0.1), 0.95)
        switch beat {
        case .tell:
            // The tell's creak spike and a haptic swell (EXPERIENCE-PLAN "Tell").
            var cue = SharedCues.settle(beds, dice: dice).scaledSounds(1.6)
            cue.haptics = [.buzz(0.3, sharpness, duration: 0.18, attack: 0.12, decay: 0.05)]
            return cue
        case .sheen, .glow:
            // Light only: a faint glint for hard materials, otherwise nothing to hear.
            guard sharpness >= 0.7 else { return nil }
            return FeedbackCue(sounds: [
                .tone(slot, 2093 * dice.grainPitch(), duration: 0.06, attack: 0.001, decay: 0.015, gain: 0.012),
            ], haptics: [.tap(0.1, 0.9)])
        default:
            let low = max(beds.crush.low, 300)
            let centre = low * pow(max(beds.crush.high, low + 1) / low, dice.unit())
            return FeedbackCue(sounds: [
                .noise(slot, .bandPass, centre, q: 2, attack: 0.0004, decay: 0.006, gain: (0.03 + 0.02 * v) * dice.level()),
            ], haptics: [.tap(0.16 + 0.1 * v, sharpness)])
        }
    }

    /// Storyboard beats stay under the fractures in touch too (after voicing with a recording's own hits).
    static func softened(_ cue: FeedbackCue) -> FeedbackCue {
        var quiet = cue
        quiet.isClimax = false
        quiet.haptics = cue.haptics.map { note in
            var light = note
            light.intensity = min(note.intensity * 0.55, 0.4)
            return light
        }
        return quiet
    }

    /// One debris grain of the slow-motion break (quiet: the failure cue already carries its own debris).
    static func debris(_ kind: ObjectKind, intensity: Double, dice: FeedbackDice) -> FeedbackCue {
        let band = Recipes.recipe(for: kind).beds.crush
        let level = Float(min(max(intensity, 0), 1))
        let centre = band.low * pow(max(band.high, band.low + 1) / max(band.low, 40), dice.unit())
        return FeedbackCue(sounds: [
            .noise(.object(kind, "debris", "grain"), .bandPass, centre, q: 2.5, attack: 0.0003, decay: 0.004,
                   gain: 0.06 * level * dice.level()),
        ], haptics: [.tap(0.12 + 0.2 * level, 0.8)])
    }

    /// One landing tick of the settle, like bits coming to rest.
    static func settleTick(_ kind: ObjectKind, intensity: Double, dice: FeedbackDice) -> FeedbackCue {
        let band = Recipes.recipe(for: kind).beds.crush
        let level = Float(min(max(intensity, 0), 1))
        return FeedbackCue(sounds: [
            .noise(.object(kind, "settle", "tick"), .bandPass, max(band.low, 300) * dice.grainPitch(), q: 2,
                   attack: 0.0004, decay: 0.006, gain: 0.05 * level),
        ], haptics: [.tap(0.1 + 0.15 * level, 0.6)])
    }
}

extension BeatCues {
    /// One latch of the seal stroke: a steel ratchet click that climbs in pitch towards the shut, and a 0.4 tap.
    static func latch(progress: Float, dice: FeedbackDice) -> FeedbackCue {
        let p = min(max(progress, 0), 1)
        let slot = { (layer: String) in SoundSlot.press("seal", layer) }
        return FeedbackCue(sounds: [
            .noise(slot("click"), .bandPass, (2200 + 1200 * p) * dice.grainPitch(), q: 3, attack: 0.0002, decay: 0.003,
                   gain: 0.16 + 0.08 * p),
            .ring(slot("pawl"), .steel, 900 + 500 * p, partials: 5, decay: 0.05, brightness: 0.45, gain: 0.07,
                  delay: 0.002, seed: dice.seed32()),
            .tone(slot("thock"), 150, to: 110, glide: 0.02, duration: 0.05, attack: 0.001, decay: 0.012, gain: 0.08,
                  harmonics: 3),
        ], haptics: [.tap(0.4, 0.55)])
    }
}

/// A tap ("poke") on the object on the anvil: its material answers in sound and touch.
/// The touch-event work calls `PressDirector.poke()`; every object has its own answer.
enum TouchCues {
    /// A flick set the object spinning on the plate: a soft whoosh that follows the spin, and a light brush.
    static func spin(_ kind: ObjectKind, turnsPerSecond: Double, dice: FeedbackDice) -> FeedbackCue {
        let v = Float(min(max(turnsPerSecond / 2, 0), 1))
        return FeedbackCue(sounds: [
            .noise(.object(kind, "spin", "whoosh"), .bandPass, 700 + 900 * v, q: 0.9, attack: 0.04, decay: 0.12,
                   gain: (0.025 + 0.035 * v) * dice.level(), sweepTo: 500, sweepTime: 0.3),
        ], haptics: [.buzz(0.12 + 0.12 * v, 0.6, duration: 0.18, attack: 0.03)])
    }

    static func poke(_ kind: ObjectKind, dice: FeedbackDice) -> FeedbackCue {
        let slot = { (layer: String) in SoundSlot.object(kind, "poke", layer) }
        let p = dice.bodyPitch()
        switch kind {
        case .bubbleWrap:
            // A plastic rustle and a tiny squeeze.
            return FeedbackCue(sounds: [
                .crunch(slot("rustle"), 4000...9000, duration: 0.12, rate: 260, rateEnd: 60, q: 1, grain: 0.0015,
                        gain: 0.07 * dice.level()),
            ], haptics: dice.scatter(4, from: 0, over: 0.1, intensity: (0.3, 0.12), sharpness: 0.75...0.85))
        case .rubberDuck:
            // The squeak: a short rising honk with vibrato.
            return FeedbackCue(sounds: [
                .tone(slot("squeak"), 820 * p, to: 1150 * p, glide: 0.08, duration: 0.14, attack: 0.008, decay: 0.05,
                      gain: 0.11, harmonics: 4, vibrato: 22, depth: 0.03),
                .noise(slot("air"), .bandPass, 1400, q: 1.5, attack: 0.01, decay: 0.04, gain: 0.03),
            ], haptics: [.buzz(0.4, 0.5, duration: 0.14, attack: 0.03)], sharpnessSweep: HapticSweep(from: 0.3, to: 0.7, duration: 0.12))
        case .jelly:
            // The wobble: a low tone at a 7 Hz wobble, and three decaying soft taps in time with it.
            return FeedbackCue(sounds: [
                .tone(slot("wobble"), 150 * p, to: 130 * p, glide: 0.4, duration: 0.45, attack: 0.01, decay: 0.15,
                      gain: 0.09, harmonics: 3, vibrato: 7, depth: 0.12, wet: true),
                .noise(slot("slap"), .lowPass, 600, attack: 0.002, decay: 0.02, gain: 0.06),
            ], haptics: [.tap(0.45, 0.15), .tap(0.3, 0.15, at: 0.14), .tap(0.18, 0.15, at: 0.28)])
        case .crayon:
            // A waxy tap.
            return FeedbackCue(sounds: [
                .ring(slot("tap"), .wood, 1300 * p, partials: 5, decay: 0.03, brightness: 0.5, gain: 0.09, seed: dice.seed32()),
            ], haptics: [.tap(0.35, 0.65)])
        case .egg:
            // A shell tap: thin and hollow.
            return FeedbackCue(sounds: [
                .noise(slot("tap"), .bandPass, 2100 * p, q: 3, attack: 0.0003, decay: 0.006, gain: 0.12),
                .tone(slot("hollow"), 600 * p, duration: 0.05, attack: 0.001, decay: 0.012, gain: 0.04),
            ], haptics: [.tap(0.32, 0.9)])
        case .cakeSlice:
            // A soft sponge press.
            return FeedbackCue(sounds: [
                .noise(slot("squish"), .lowPass, 900, attack: 0.01, decay: 0.05, gain: 0.08),
                .crunch(slot("crumb"), 1500...4000, duration: 0.08, rate: 90, rateEnd: 20, q: 1.2, grain: 0.003, gain: 0.03),
            ], haptics: [.buzz(0.3, 0.1, duration: 0.1, attack: 0.02)])
        case .sodaCan:
            // The tink.
            return FeedbackCue(sounds: [
                .ring(slot("tink"), .metal, 1750 * p, partials: 8, decay: 0.12, brightness: 0.55, gain: 0.1,
                      seed: dice.seed32()),
            ], haptics: [.tap(0.45, 0.9)])
        case .gummyBear:
            // A rubbery squidge.
            return FeedbackCue(sounds: [
                .tone(slot("squidge"), 320 * p, to: 230 * p, glide: 0.1, duration: 0.14, attack: 0.006, decay: 0.05,
                      gain: 0.07, harmonics: 2, vibrato: 12, depth: 0.05),
                .noise(slot("stick"), .bandPass, 900, q: 1, attack: 0.004, decay: 0.03, gain: 0.03),
            ], haptics: [.buzz(0.35, 0.2, duration: 0.12, attack: 0.02)])
        case .glassBottle:
            // The clink.
            return FeedbackCue(sounds: [
                .ring(slot("clink"), .glass, 2100 * p, partials: 8, decay: 0.2, brightness: 0.6, gain: 0.09,
                      seed: dice.seed32()),
            ], haptics: [.tap(0.4, 1.0)])
        case .unsquishable:
            // A solid steel clank: it isn't going anywhere.
            return FeedbackCue(sounds: [
                .ring(slot("clank"), .steel, 520 * p, partials: 8, decay: 0.3, brightness: 0.45, gain: 0.12,
                      seed: dice.seed32()),
                .tone(slot("thock"), 130, to: 90, glide: 0.04, duration: 0.08, attack: 0.001, decay: 0.02, gain: 0.12,
                      harmonics: 3),
            ], haptics: [.tap(0.7, 0.5), .buzz(0.3, 0.4, at: 0.01, duration: 0.2, decay: 0.15)])
        }
    }
}
