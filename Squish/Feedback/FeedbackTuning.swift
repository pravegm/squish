import AVFoundation
import Foundation

// Pure tuning shared by the live controllers, the offline renderer and the tests (nonisolated on purpose).
// Born from the first real-iPhone Duo test (TestFlight 1.0 (1)): no sound with the phone on silent, and haptics that
// felt "a little, weak".

// MARK: - Audio session

/// Which `AVAudioSession` category Squish runs in.
///
/// **Decision: `.playback` + `.mixWithOthers` by default ("Play sound when the phone is on silent", ON).**
/// - `.ambient` (what 1.0 (1) shipped) is muted by the Ring/Silent switch and the Action button's silent mode. Many
///   people keep their phone on silent all day, so their first press was silent and half the product was missing
///   (the founder's own first device test).
/// - Apple's category guide: `.playback` is "for playing recorded music or other sounds that are central to the
///   successful use of your app", and "your app audio continues with the Silent switch set to silent". Here the sound
///   *is* the product: it is synthesised live from the hinge, the way a music instrument app's notes are.
/// - `.mixWithOthers` keeps the etiquette that made `.ambient` attractive: the user's music or podcast keeps playing
///   under the press instead of being stopped. No `UIBackgroundModes` audio, so Squish never plays from the background.
/// - Fidget, ASMR and instrument toys commonly play on silent for the same reason; most games respect the switch
///   because their sound is decoration. Squish is the former, but people who want the switch respected can turn the
///   setting off, which returns to `.ambient`.
struct AudioSessionChoice: Equatable {
    var category: AVAudioSession.Category
    var options: AVAudioSession.CategoryOptions
    var mode: AVAudioSession.Mode = .default

    /// True when the Ring/Silent switch (or the Action button's silent mode) mutes Squish.
    var respectsSilentSwitch: Bool { category == .ambient || category == .soloAmbient }

    static func forSettings(playsInSilentMode: Bool) -> AudioSessionChoice {
        playsInSilentMode
            ? AudioSessionChoice(category: .playback, options: [.mixWithOthers])
            : AudioSessionChoice(category: .ambient, options: [])
    }

    /// Plain words for the Tuning Lab diagnostics.
    static func describe(_ category: AVAudioSession.Category) -> String {
        switch category {
        case .ambient: "Ambient (muted by silent mode)"
        case .soloAmbient: "Solo ambient (muted by silent mode)"
        case .playback: "Playback (plays on silent)"
        case .playAndRecord: "Play and record"
        case .record: "Record only"
        case .multiRoute: "Multi-route"
        default: category.rawValue
        }
    }

    static func describe(_ options: AVAudioSession.CategoryOptions) -> String {
        var names: [String] = []
        if options.contains(.mixWithOthers) { names.append("mixes with other apps") }
        if options.contains(.duckOthers) { names.append("ducks other apps") }
        if options.contains(.interruptSpokenAudioAndMixWithOthers) { names.append("interrupts spoken audio") }
        if options.contains(.defaultToSpeaker) { names.append("defaults to speaker") }
        return names.isEmpty ? "none" : names.joined(separator: ", ")
    }
}

// MARK: - Mix

/// Output gain staging shared by the live controller and the offline renderer (share clip), so both sound the same.
enum AudioMix {
    /// Master gain into the synth's −1 dBFS peak limiter.
    ///
    /// 1.0 (1) ran 0.8: measured (BS.1770, `FeedbackTests.pressMixLandsNearTheLoudnessTarget`, every object's press)
    /// at about −26 LUFS, 10 dB under the −16 LUFS target (02 §6). At 1.6 the mean was −20.3 LUFS with every peak
    /// already at the −1 dBFS limiter, so the rest comes from the beds (`bedBus`), not from pushing the climaxes
    /// harder into the limiter. The climaxes ride the limiter for a few milliseconds, which on a phone speaker reads
    /// as punch.
    static let masterGain: Float = 1.8
    /// Extra gain on the continuous layers (strain, crush, hiss, motor, creak) before the master. They sat near
    /// −30 dBFS, which a phone speaker in a hand can't carry; +6.8 dB brings the press bed up where the strain is heard.
    static let bedBus: Float = 2.2
    /// Recorded samples arrive loudness-normalised per category (the manifest's `gainDb` is the trim on top); this
    /// sets them against the synth layers before the master, so a "hero" break peaks just into the limiter.
    static let sampleBus: Float = 0.5
    /// The recorded strain loops (normalised around −24 LUFS, then the manifest's −14 dB trim). This sits the held
    /// strain bed ~10–12 LU under the break (SOUND-2 §5.1 item 6).
    static let loopBus: Float = 2.5

    /// Linear → dBFS, for the diagnostics.
    static func decibels(_ linear: Float) -> String {
        guard linear > 0.00001 else { return "silent" }
        return String(format: "%.1f dBFS", 20 * log10(linear))
    }
}

// MARK: - Haptics

/// How hard things feel. The founder's first Duo test: haptics were felt "a little, weak". Causes, all fixed here:
/// - Every value was a literal Core Haptics intensity, and below ~0.4 a transient barely registers in a hand-held
///   phone (most grains were 0.12–0.3). `lift` is a perceptual curve applied to every note.
/// - The strain bed was `strain · (0.35 + 0.65·v) · bedGain`, capped at 0.7, with v = speed / 60 °/s. A real Duo is
///   closed slowly (10–30 °/s), so v was small, and the bed faded to zero whenever the press was "holding"
///   (no hinge sample for 0.25 s, which a slow close on a ~1 Hz-ish sensor hits constantly). In practice the bed
///   peaked around 0.15–0.3 and kept dropping out. Now it has a floor as soon as the plates bite, rises with strain,
///   depends only a little on speed, and keeps a held tension instead of going slack.
enum HapticTuning {
    /// `lift(x) = x^0.6`: 0.12 → 0.28, 0.3 → 0.49, 0.5 → 0.66, 0.8 → 0.87, 1 → 1.
    static let liftExponent: Float = 0.6
    /// Non-climax notes stop here; failures and the ka-chunk may hit 1.0 (bible §7, raised from 0.9).
    static let nonClimaxCap: Float = 0.95
    /// The strain bed's ceiling before the failure (raised from 0.7) and while the phone is hot.
    static let bedCeiling: Float = 0.9
    static let thermalBedCeiling: Float = 0.6
    /// The bed as soon as the plates touch the object: contact pressure you can feel.
    static let loadedFloor: Float = 0.14
    /// Closing speed (°/s) that counts as "fully moving" for the bed. A deliberate Duo close is 10–40 °/s.
    static let speedReference: Double = 40

    /// The haptic engine's own latency, assumed (SOUND-2 §4.3: the net offset is ≈ 0 on the built-in speaker).
    static let engineLatency = 0.012

    /// How much later a haptic pattern starts than its sound is triggered, so both reach the user together.
    static func alignment(audioDelay: Double) -> Double {
        min(max(audioDelay - engineLatency, 0), 0.25)
    }

    static func lift(_ intensity: Float) -> Float {
        pow(min(max(intensity, 0), 1), liftExponent)
    }

    /// Closing speed → 0…1 for the haptic bed.
    static func speed(_ degreesPerSecond: Double) -> Float {
        Float(min(max(degreesPerSecond / speedReference, 0), 1))
    }

    /// The strain bed before the failure: rises from the floor to the ceiling with strain.
    /// - strain: the material's strain curve 0…1 (1 at the break).
    /// - recipeMax: the recipe's old ceiling (0.5–0.7), kept as relative character between materials.
    static func strainBed(strain: Float, speed: Float, holding: Bool, materialGain: Float, recipeMax: Float) -> Float {
        let ceiling = bedCeiling * min(max(recipeMax / 0.7, 0.75), 1)
        let motion: Float = holding ? 0.7 : 0.75 + 0.25 * min(max(speed, 0), 1)
        let material: Float = 0.75 + 0.25 * min(max(materialGain, 0), 1)
        let s = min(max(strain, 0), 1)
        return loadedFloor + (ceiling - loadedFloor) * s * motion * material
    }

    /// The crush bed after the failure (01 §6 step 7): softer, speed-driven, a low hum while held.
    static func crushBed(intensity: Float, speed: Float, holding: Bool) -> Float {
        let base = lift(intensity)
        return holding ? base * 0.35 : base * (0.5 + 0.5 * min(max(speed, 0), 1))
    }
}

// MARK: - Test full press feel

/// The Tuning Lab's "Test full press feel": a scripted 3-second press, independent of the hinge, so the founder can
/// feel and hear the whole arc on the device: strain ramp → cracks → failure → ka-chunk. Sound and touch come from
/// one cue (one set of random choices), like a live press.
@MainActor
enum PressFeelDemo {
    struct BedPoint: Equatable, Sendable {
        var time: Double
        var intensity: Float
    }

    /// The strain ramp (as its own continuous haptic, so its intensity curve never scales the transients).
    static let strainDuration = 2.6
    static let failureTime = 2.65
    static let kaChunkTime = 3.4
    static let crackTimes: [Double] = [1.15, 1.8, 2.3]

    /// At most 16 points (Core Haptics' limit per curve).
    static let bedRamp: [BedPoint] = [
        BedPoint(time: 0, intensity: 0.14),
        BedPoint(time: 0.5, intensity: 0.26),
        BedPoint(time: 1.0, intensity: 0.4),
        BedPoint(time: 1.5, intensity: 0.55),
        BedPoint(time: 2.0, intensity: 0.7),
        BedPoint(time: 2.35, intensity: 0.84),
        BedPoint(time: 2.55, intensity: 0.92),
        BedPoint(time: 2.6, intensity: 0),
    ]
    static let bedSharpness: (from: Float, to: Float) = (0.25, 0.6)

    /// The object whose failure the demo uses: the current one if it has a failure, else the glass bottle.
    static func failureKind(for kind: ObjectKind) -> ObjectKind {
        kind.profile.failureIndex == nil ? .glassBottle : kind
    }

    static func cue(kind: ObjectKind, dice: FeedbackDice) -> FeedbackCue {
        var cue = FeedbackCue()
        cue.isClimax = true
        let slot = { (layer: String) in SoundSlot.press("feeltest", layer) }

        // Strain: the motor rises (an attack-only envelope is a 2.4 s linear swell), and a creak bed thickens.
        cue.sounds += [
            .tone(slot("motor"), 210, to: 320, glide: Float(strainDuration), duration: Float(strainDuration),
                  attack: 2.4, decay: 0.05, gain: 0.06, harmonics: 3),
            .crunch(slot("creak"), 500...2200, duration: Float(strainDuration), rate: 10, rateEnd: 70, q: 4, grain: 0.012,
                    gain: 0.05, fade: 3),
        ]

        // Grains: accelerating crisp ticks, in sound and touch.
        var t = 0.2
        while t < strainDuration - 0.1 {
            let p = Float(t / strainDuration)
            cue.haptics.append(.tap(0.2 + 0.35 * p, 0.7, at: t))
            cue.sounds.append(.noise(slot("grain"), .highPass, 4500 * dice.grainPitch(), decay: 0.003,
                                     gain: 0.05 + 0.08 * p, delay: Float(t)))
            t += 0.24 - 0.16 * Double(p)
        }

        // Cracks: a sharp double tap and a bright snap each, getting bigger.
        for (index, time) in crackTimes.enumerated() {
            let k = Float(index)
            cue.haptics += [.tap(0.65 + 0.1 * k, 0.9, at: time), .tap(0.4, 0.9, at: time + 0.014)]
            cue.sounds += [
                .noise(slot("crack.snap"), .highPass, 3800, attack: 0.0003, decay: 0.003, gain: 0.3 + 0.05 * k,
                       delay: Float(time)),
                .noise(slot("crack.body"), .bandPass, 1700 * dice.bodyPitch(), q: 2.5, decay: 0.012, gain: 0.3,
                       delay: Float(time)),
            ]
        }

        // The failure: the real recipe failure of a breakable object, the tonic, and the heavy failure body.
        let breakable = failureKind(for: kind)
        if let failure = breakable.profile.failureIndex {
            let event = PressEvent.fracture(index: failure, isFailure: true)
            let context = Audition.context(for: breakable, event: event)
            var climax = CueBook.preview(.fracture(index: failure, isFailure: true), context: context, dice: dice)
            climax.add(BrandCues.tonic)
            climax.add(BrandCues.failureBody)
            cue.add(climax.delayed(by: failureTime))
        }

        // The ka-chunk, without its "ready" tinks 1.5 s later.
        var kaChunk = BrandCues.kaChunk
        kaChunk.sounds = kaChunk.sounds.filter { !$0.slot.id.hasPrefix("press.kachunk.ready") }
        kaChunk.haptics = kaChunk.haptics.filter { $0.time < 1 }
        cue.add(kaChunk.delayed(by: kaChunkTime))
        return cue
    }
}

// MARK: - Diagnostics

/// One plain-words line of the Tuning Lab's Diagnostics section.
struct DiagnosticRow: Identifiable, Equatable {
    var title: String
    var value: String
    /// Something that would explain "no sound" or "no vibration".
    var isWarning = false

    var id: String { title }

    static func yesNo(_ value: Bool) -> String { value ? "Yes" : "No" }
}
