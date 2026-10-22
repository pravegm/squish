import Foundation

/// Soda Can: thin metal, five concertina buckles (02 §7.3). Each buckle is a "ping-buckle": a bright click,
/// a crumple body and a short modal ring of 10 decaying partials, rising a little with every fold.
/// The third buckle punctures it: FSSSHT — a dense high fizz that keeps going (01 §7.3: C 0.35/0.9 1.2 s + 60/s grains).
struct SodaCanRecipe: ObjectRecipe {
    let kind = ObjectKind.sodaCan

    var beds: MaterialBeds {
        MaterialBeds(
            strain: NoiseBed(.bandPass, 450, q: 4, gain: 0.02, flutter: 2.5, depth: 0.6, rise: 0.5),
            crush: GrainBed(rate: 150, band: 1500...7000, q: 1.4, grain: 0.0015, gain: 0.04),
            creakPitch: 1.4, creakAmount: 0.5,
            hapticCurve: .stepwise, hapticMax: 0.65,
            crushHapticIntensity: 0.3, crushHapticSharpness: 0.1
        )
    }

    func cue(for moment: RecipeMoment, _ input: RecipeInput) -> FeedbackCue {
        let d = input.dice
        switch moment {
        case .place:
            return FeedbackCue(sounds: [
                .ring(slot("place", "tonk"), .metal, 520 * d.bodyPitch(), partials: 8, decay: 0.08, brightness: 0.6,
                      gain: 0.12, seed: d.seed32()),
                .noise(slot("place", "click"), .bandPass, 2000, q: 1.5, decay: 0.004, gain: 0.06),
            ], haptics: [.tap(0.35, 0.8)])

        case .contact:
            return FeedbackCue(sounds: [
                .ring(slot("contact", "ring"), .metal, 900 * d.bodyPitch(), partials: 8, decay: 0.04, brightness: 0.55,
                      gain: 0.08, seed: d.seed32()),
                .noise(slot("contact", "tick"), .highPass, 5000, decay: 0.0015, gain: 0.05),
            ], haptics: [.tap(0.4, 0.8)])

        case .grain(let c):
            // Crinkle (01 §7.3: 0.30–0.50 / 0.75), now and then a tiny ping.
            var sounds: [SoundLayer] = [
                .noise(slot("grain", "crinkle"), .highPass, 4500 * d.grainPitch(), attack: 0.0002, decay: 0.002,
                       gain: 0.03 * d.level()),
            ]
            if d.chance(0.3) {
                sounds.append(.ring(slot("grain", "ping"), .metal, 1500 * d.grainPitch(), partials: 8, decay: 0.015,
                                    brightness: 0.5, gain: 0.02, seed: d.seed32()))
            }
            if input.hasFailed && d.chance(0.5) {
                sounds.append(.crunch(slot("grain", "fizz"), 5000...10000, duration: 0.08, rate: 400, rateEnd: 200, q: 1.5,
                                      grain: 0.0008, gain: 0.03))
            }
            return FeedbackCue(sounds: sounds, haptics: [.tap(0.3 + 0.2 * c, 0.75)])

        case .preFailureTell:
            // A low metal groan; the harmonic stack stays under 1 kHz.
            return FeedbackCue(sounds: [
                .tone(slot("tell", "groan"), 140 * d.bodyPitch(), to: 120, glide: 0.3, duration: 0.35, attack: 0.03,
                      decay: 0.12, gain: 0.04, harmonics: 6, vibrato: 4, depth: 0.01),
            ])

        case .microCrack(let index):
            let p = Float(min(index, 12)) / 12
            return FeedbackCue(sounds: [
                .ring(slot("tell", "ping"), .metal, 1800 * d.grainPitch(), partials: 8, decay: 0.012, brightness: 0.5,
                      gain: 0.03, seed: d.seed32()),
                .noise(slot("tell", "crinkle"), .highPass, 5000, decay: 0.0015, gain: 0.03),
            ], haptics: [.tap(0.3 + 0.3 * p, 0.9)])

        case .fracture(let index, let isFailure):
            var cue = buckle(index: index, d, input: input, full: isFailure)
            if isFailure {
                cue.add(fizz(d, input: input))
                cue.isClimax = true
            }
            return cue

        case .released:
            return FeedbackCue(sounds: [
                .ring(slot("release", "tick"), .metal, 1200 * d.grainPitch(), partials: 6, decay: 0.02, gain: 0.03,
                      seed: d.seed32()),
            ])

        case .reveal:
            // Fizz settle: grains at 30/s fading over 0.8 s (01 §7.3).
            var haptics: [HapticNote] = []
            for i in 0..<24 {
                let t = Double(i) / 30
                haptics.append(.tap(0.2 * Float(1 - t / 0.8) + 0.03, 0.95, at: t))
            }
            return FeedbackCue(sounds: [
                .crunch(slot("reveal", "fizz"), 4000...10000, duration: 0.8, rate: 200, rateEnd: 20, q: 1.5, grain: 0.0008,
                        gain: 0.06, fade: 0.15),
            ], haptics: haptics)
        }
    }

    /// One ping-buckle: transient + crumple body + modal ring (01 §7.3 buckle T1.0/0.85, ring taps decaying).
    private func buckle(index: Int, _ d: FeedbackDice, input: RecipeInput, full: Bool) -> FeedbackCue {
        let roots: [Float] = [610, 740, 880]
        let root = roots[d.pick(3, for: slot("buckle", "ring"))] * d.bodyPitch() * (1 + 0.06 * Float(index))
        let sounds: [SoundLayer] = [
            .noise(slot("buckle", "click"), .highPass, 6000, attack: 0.0002, decay: 0.002, gain: 0.3 * d.level()),
            .noise(slot("buckle", "crumple"), .bandPass, 1200 * d.bodyPitch(), q: 1.2, decay: 0.02, gain: 0.35 * d.level()),
            .crunch(slot("buckle", "crinkle"), 1500...6000, duration: 0.06, rate: 300 * input.debris, rateEnd: 80, q: 1.4,
                    grain: 0.0015, gain: 0.12),
            .ring(slot("buckle", "ring"), .metal, root, partials: 10, decay: 0.12, brightness: 0.65, gain: 0.22,
                  delay: 0.001, seed: d.seed32()),
        ]
        // The ring taps are spaced at the 12 ms minimum gap rather than 8 ms.
        let haptics: [HapticNote] = [
            .tap(full ? 1.0 : 0.85, 0.85),
            .tap(0.5, 0.9, at: 0.012),
            .tap(0.3, 0.9, at: 0.024),
            .tap(0.15, 0.9, at: 0.036),
        ]
        return FeedbackCue(sounds: sounds, haptics: haptics)
    }

    /// Puncture: a "psst", the spray hiss and a long dense fizz of tiny bubbles above the harsh band.
    private func fizz(_ d: FeedbackDice, input: RecipeInput) -> FeedbackCue {
        var haptics: [HapticNote] = [.buzz(0.35, 0.9, at: 0.01, duration: 1.2, decay: 1.0)]
        let count = Int(30 * input.debris)
        for i in 0..<count {
            haptics.append(.tap(0.15, 0.95, at: 0.05 + Double(i) / 60))
        }
        return FeedbackCue(sounds: [
            .noise(slot("fizz", "psst"), .highPass, 5000, attack: 0.001, decay: 0.03, gain: 0.3),
            .noise(slot("fizz", "spray"), .bandPass, 7000, q: 0.8, attack: 0.005, decay: 0.35, gain: 0.1 * d.level(), delay: 0.01),
            .crunch(slot("fizz", "bubbles"), 4500...10000, duration: 1.2, rate: 900 * input.debris, rateEnd: 150, q: 1.5,
                    grain: 0.0008, gain: 0.16, fade: 0.2, delay: 0.01),
        ], haptics: haptics)
    }
}
