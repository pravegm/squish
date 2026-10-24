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
    /// harder into the limiter. With the recorded foley (24 Oct), 1.8 measured −17.8 LUFS with only 3.9 LU between
    /// bed and break; 2.0 with the quieter bed bus, the louder sample bus and the look-ahead limiter targets −16 with
    /// the break standing clear; it measured −17.7, so 2.4 (+1.6 dB). The climaxes ride the limiter for a few milliseconds: punch on a phone speaker.
    static let masterGain: Float = 2.4
    /// Extra gain on the synthesised continuous layers (strain, crush, hiss, motor, creak) before the master. They sat
    /// near −30 dBFS; +6.8 dB (2.2) brought them up but measured only 3.9 LU under the break, against SOUND-2's 10–12
    /// (`FeedbackTests` prints the contrast). At 1.2 it measured 8.3 LU; at 1.0 10.2 LU, then 14.7 once the beds followed the display-rate hinge
    /// (25 Oct); 1.6 (+4 dB) brings them back to ~11.
    static let bedBus: Float = 1.6
    /// Recorded samples arrive loudness-normalised per category (the manifest's `gainDb` is the trim on top); this
    /// sets them against the synth layers before the master, so a "hero" break peaks just into the limiter.
    static let sampleBus: Float = 0.8
    /// The recorded strain loops (normalised around −24 LUFS, then the manifest's −14 dB trim). This sits the held
    /// strain bed ~10–12 LU under the break (SOUND-2 §5.1 item 6).
    static let loopBus: Float = 2.1

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

// MARK: - Vibration strength

/// What each Vibration strength setting does to every haptic (founder, real Duo 1.0 (3): "vibrations need to be
/// stronger"). Strong and Max use the hardware's whole range without going mushy:
/// - major hits (a crack, pop or snap that matters) go to 1.0, and get a short low-sharpness (0.3) continuous burst
///   underneath (45 / 75 ms): low sharpness reads as a heavier, more physical thump;
/// - Max stacks a second heavy thump 12 ms later;
/// - every grain gets an echo 22 ms later at 70 %, so strain feels like grinding resistance, not occasional ticks;
/// - the strain bed rises from a clearly felt 0.45 (0.55 on Max) at contact to 1.0 at the break, and carries a
///   26–30 Hz rumble (alternating intensity curves on the bed player);
/// - no fatigue derating. Thermal derating stays, but only at serious/critical temperatures, never at nominal.
struct HapticProfile: Equatable, Sendable {
    /// `lift(x) = x^exponent`: lower is stronger.
    var liftExponent: Float
    /// Transients whose authored intensity is at least this play at 1.0 (above 1: none).
    var majorThreshold: Float
    var nonClimaxCap: Float
    var bedFloor: Float
    var bedCeiling: Float
    /// Seconds of continuous burst under each major transient (0: none), and its sharpness.
    var burst: Double
    var burstSharpness: Float = 0.3
    /// A second heavy transient right after each major one.
    var stack: Bool
    /// A second, quieter tap after every grain.
    var grainEcho: Bool
    /// Rumble on the strain and crush bed: modulation depth (0: none) and frequency.
    var rumbleDepth: Float
    var rumbleHz: Double
    /// The 60 s-in-5-min fatigue guard (bible §7).
    var fatigue: Bool

    /// 1.0 (2)'s tuning.
    static let normal = HapticProfile(liftExponent: HapticTuning.liftExponent, majorThreshold: 2, nonClimaxCap: 0.95,
                                      bedFloor: HapticTuning.loadedFloor, bedCeiling: HapticTuning.bedCeiling, burst: 0,
                                      stack: false, grainEcho: false, rumbleDepth: 0, rumbleHz: 30, fatigue: true)
    static let strong = HapticProfile(liftExponent: 0.45, majorThreshold: 0.5, nonClimaxCap: 1, bedFloor: 0.45,
                                      bedCeiling: 1, burst: 0.045, stack: false, grainEcho: true, rumbleDepth: 0.22,
                                      rumbleHz: 30, fatigue: false)
    static let maximum = HapticProfile(liftExponent: 0.35, majorThreshold: 0.35, nonClimaxCap: 1, bedFloor: 0.55,
                                   bedCeiling: 1, burst: 0.075, burstSharpness: 0.25, stack: true, grainEcho: true,
                                   rumbleDepth: 0.35, rumbleHz: 26, fatigue: false)

    static func of(_ strength: VibrationStrength) -> HapticProfile {
        switch strength {
        case .normal: .normal
        case .strong: .strong
        case .max: .maximum
        }
    }

    func lift(_ intensity: Float) -> Float {
        pow(min(max(intensity, 0), 1), liftExponent)
    }

    /// The strain bed before the failure under this profile. Normal keeps 1.0 (2)'s shape (`HapticTuning.strainBed`);
    /// Strong and Max run floor → ceiling with strain, nearly independent of speed, and hold while held.
    func strainBed(strain: Float, speed: Float, holding: Bool, materialGain: Float, recipeMax: Float) -> Float {
        guard bedFloor > HapticTuning.loadedFloor else {
            return HapticTuning.strainBed(strain: strain, speed: speed, holding: holding, materialGain: materialGain,
                                          recipeMax: recipeMax)
        }
        let s = min(max(strain, 0), 1)
        let motion: Float = holding ? 0.85 : 0.88 + 0.12 * min(max(speed, 0), 1)
        return bedFloor + (bedCeiling - bedFloor) * s * motion
    }

    /// The extra notes this profile adds around a cue's notes (bursts, stacks, grain echoes). Pure, for tests.
    func reinforced(_ notes: [HapticNote], isGrain: Bool) -> [HapticNote] {
        var out = notes
        var majors = 0
        for note in notes where note.kind == .transient {
            if note.intensity >= majorThreshold && majors < 4 {
                majors += 1
                if burst > 0 {
                    out.append(.buzz(1, burstSharpness, at: note.time + 0.002, duration: burst, decay: Float(burst * 0.8)))
                }
                if stack { out.append(.tap(1, 0.25, at: note.time + 0.012)) }
            }
        }
        if isGrain && grainEcho, let first = notes.first(where: { $0.kind == .transient }) {
            out.append(.tap(first.intensity * 0.7, first.sharpness, at: first.time + 0.022))
        }
        return out
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
