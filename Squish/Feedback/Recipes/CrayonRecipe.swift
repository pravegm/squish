import Foundation

/// The Crayon Box: brittle wax. A clean SNAP per crayon — bright double transient plus a 400–900 Hz body (02 §7.3) —
/// in a volley (fractures 0…6, 0 the failure), each a different seeded snap, rising a little in pitch as the box goes;
/// then a dry waxy crumble (the last fracture). The haptic is the textbook snap (01 §7.3): T1.0/1.0, T0.7/0.6 @12 ms,
/// a short dull tail and five debris taps. Grains stop at c 0.22 (the rigid plateau), so the snap surprises.
struct CrayonRecipe: ObjectRecipe {
    let kind = ObjectKind.crayon

    var beds: MaterialBeds {
        MaterialBeds(
            strain: NoiseBed(.bandPass, 1100, q: 2.5, gain: 0.02, flutter: 11, depth: 0.5, rise: 0.4),
            crush: GrainBed(rate: 120, band: 800...4000, q: 1.3, grain: 0.004, gain: 0.05),
            creakPitch: 1.0, creakAmount: 0.5,
            hapticCurve: .easeIn, hapticMax: 0.65,
            crushHapticIntensity: 0.25, crushHapticSharpness: -0.2
        )
    }

    func cue(for moment: RecipeMoment, _ input: RecipeInput) -> FeedbackCue {
        let d = input.dice
        switch moment {
        case .place:
            return FeedbackCue(sounds: [
                .tone(slot("place", "tock"), 700 * d.bodyPitch(), to: 600, glide: 0.03, duration: 0.05, attack: 0.001,
                      decay: 0.015, gain: 0.1, harmonics: 2),
                .noise(slot("place", "click"), .bandPass, 2500, q: 1.5, decay: 0.006, gain: 0.06),
            ], haptics: [.tap(0.35, 0.6)])

        case .contact:
            return FeedbackCue(sounds: [
                .noise(slot("contact", "tick"), .bandPass, 3000, q: 2, decay: 0.004, gain: 0.08 * d.level()),
                .tone(slot("contact", "wax"), 600 * d.bodyPitch(), duration: 0.04, attack: 0.001, decay: 0.012, gain: 0.06),
            ], haptics: [.tap(0.4, 0.55)])

        case .grain(let c):
            if input.hasFailed {
                // Waxy grind (01 §7.3 crush: I 0.25, S 0.6).
                return FeedbackCue(sounds: [
                    .crunch(slot("crush", "grind"), 700...3000, duration: 0.03, rate: 300, q: 1.4, grain: 0.003,
                            gain: 0.05 * d.level()),
                ], haptics: [.tap(0.25, 0.6)])
            }
            return FeedbackCue(sounds: [
                .noise(slot("grain", "creak"), .bandPass, d.range(900...1600) * d.grainPitch(), q: 3, decay: 0.006,
                       gain: 0.04 * d.level()),
            ], haptics: [.tap(0.3 + 0.1 * c, 0.7)])

        case .preFailureTell:
            return FeedbackCue(sounds: [
                .tone(slot("tell", "strain"), 420 * d.bodyPitch(), to: 480, glide: 0.2, duration: 0.22, attack: 0.02,
                      decay: 0.08, gain: 0.03, harmonics: 4, vibrato: 18, depth: 0.02),
            ])

        case .microCrack(let index):
            let p = Float(min(index, 12)) / 12
            return FeedbackCue(sounds: [
                .noise(slot("tell", "tick"), .highPass, 5000, attack: 0.0002, decay: 0.0015, gain: 0.06),
                .noise(slot("tell", "wax"), .bandPass, 1200 * d.grainPitch(), q: 4, decay: 0.005, gain: 0.04),
            ], haptics: [.tap(0.3 + 0.3 * p, 0.9)])

        case .fracture(let index, true):
            return snap(d, input: input, strength: 1, index: index)

        case .fracture(let index, false):
            if index < Self.crumbleIndex {
                // The rest of the volley: each crayon its own snap, a touch lighter than the first.
                return snap(d, input: input, strength: d.range(0.6...0.78), index: index)
            }
            // The waxy crumble.
            var haptics = d.scatter(Int(8 * input.debris), from: 0, over: 0.25, intensity: (0.45, 0.15), sharpness: 0.55...0.65)
            haptics.append(.buzz(0.25, 0.35, duration: 0.2))
            return FeedbackCue(sounds: [
                .crunch(slot("crumble", "grains"), 600...3000, duration: 0.3, rate: 80 * input.debris, rateEnd: 20, q: 1.5,
                        grain: 0.006, gain: 0.2 * d.level()),
                .noise(slot("crumble", "body"), .lowPass, 800, attack: 0.002, decay: 0.05, gain: 0.12),
            ], haptics: haptics)

        case .released:
            return .silent

        case .reveal:
            return FeedbackCue(sounds: [
                .crunch(slot("reveal", "crumbs"), 900...4000, duration: 0.3, rate: 50, rateEnd: 10, q: 1.3, grain: 0.004,
                        gain: 0.08),
            ], haptics: d.scatter(6, from: 0, over: 0.3, intensity: (0.25, 0.2), sharpness: 0.55...0.65))
        }
    }

    /// The last fracture is the crumble; every one before it is a crayon snapping.
    static var crumbleIndex: Int { max(ObjectKind.crayon.profile.fractures.count - 1, 1) }

    /// Snap n of the volley rises 0.6 st per crayon (about +3.6 st by the seventh): the box "plays a scale" as it goes.
    static func volleyPitch(_ index: Int) -> Float {
        pow(2, Float(min(max(index, 0), 12)) * 0.6 / 12)
    }

    /// Bright transient, an immediate second click (the "double" of a real snap) and a woody 400–900 Hz body.
    private func snap(_ d: FeedbackDice, input: RecipeInput, strength s: Float, index: Int) -> FeedbackCue {
        let bodies: [Float] = s >= 1 ? [450, 620, 820] : [560, 700, 860]
        let rise = Self.volleyPitch(index)
        let body = bodies[d.pick(3, for: slot("snap", "body"))] * d.bodyPitch() * rise
        let sounds: [SoundLayer] = [
            .noise(slot("snap", "transient"), .highPass, 7000, attack: 0.0002, decay: 0.002, gain: 0.5 * s * d.level()),
            .noise(slot("snap", "double"), .bandPass, 4500, q: 1, attack: 0.0002, decay: 0.0015, gain: 0.3 * s, delay: 0.012),
            .noise(slot("snap", "body"), .bandPass, body, q: 2.2, decay: 0.035, gain: 0.55 * s * d.level(), delay: 0.001),
            .ring(slot("snap", "wood"), .wood, body * 1.05, partials: 4, decay: 0.05, brightness: 0.5, gain: 0.15 * s,
                  seed: d.seed32()),
            .crunch(slot("snap", "debris"), 1500...6000, duration: 0.15, rate: 60 * input.debris, rateEnd: 15, q: 1.2,
                    grain: 0.003, gain: 0.1 * s, delay: 0.03),
        ]
        var haptics: [HapticNote] = [
            .tap(1.0 * s, 1.0),
            .tap(0.7 * s, 0.6, at: 0.012),
            .buzz(0.5 * s, 0.3, at: 0.015, duration: 0.06, decay: 0.05),
        ]
        haptics += d.scatter(Int(5 * input.debris), from: 0.03, over: 0.15, intensity: (0.5 * s, 0.15), sharpness: 0.65...0.75)
        var cue = FeedbackCue(sounds: sounds, haptics: haptics, isClimax: s >= 1)
        cue.samplePitch = rise // the recorded snap rises with the volley too
        return cue
    }
}
