import Foundation

/// The Unsquishable (secret steel ball): comedy subversion (bible §4). The ball never gives; the *press* does.
/// Slow steel groans from the frame (harmonic stacks on a 50–110 Hz root, so the speaker implies the weight),
/// the gauge redlines with a stutter of top-note dinks, then the press CRACKS — metallic crack, a long frame
/// ring and a bolt that boings off. Reveal: a two-note "womp womp".
struct UnsquishableRecipe: ObjectRecipe {
    let kind = ObjectKind.unsquishable

    var beds: MaterialBeds {
        MaterialBeds(
            strain: NoiseBed(.lowPass, 300, q: 1, gain: 0.03, flutter: 1.2, depth: 0.5, rise: 0.3),
            crush: GrainBed(rate: 20, band: 1500...6000, q: 1.5, grain: 0.003, gain: 0.02),
            creakPitch: 0.7, creakAmount: 1.0,
            hapticCurve: .easeIn, hapticMax: 0.7,
            crushHapticIntensity: 0.3, crushHapticSharpness: 0
        )
    }

    func cue(for moment: RecipeMoment, _ input: RecipeInput) -> FeedbackCue {
        let d = input.dice
        switch moment {
        case .place:
            // A heavy steel clonk and one small bounce.
            return FeedbackCue(sounds: [
                .ring(slot("place", "clonk"), .steel, 420 * d.bodyPitch(), partials: 8, decay: 0.25, brightness: 0.55,
                      gain: 0.15, seed: d.seed32()),
                .tone(slot("place", "weight"), 110, to: 70, glide: 0.08, duration: 0.12, attack: 0.001, decay: 0.04,
                      gain: 0.2, harmonics: 4),
                .ring(slot("place", "bounce"), .steel, 430 * d.bodyPitch(), partials: 6, decay: 0.12, brightness: 0.5,
                      gain: 0.05, delay: 0.11, seed: d.seed32()),
            ], haptics: [.tap(0.6, 0.6), .tap(0.2, 0.6, at: 0.11)])

        case .contact:
            return FeedbackCue(sounds: [
                .ring(slot("contact", "clink"), .steel, 1250 * d.bodyPitch(), partials: 8, decay: 0.15, brightness: 0.5,
                      gain: 0.1, seed: d.seed32()),
                .noise(slot("contact", "click"), .highPass, 5000, attack: 0.0002, decay: 0.002, gain: 0.1),
            ], haptics: [.tap(0.5, 0.95)])

        case .grain(let c):
            if input.hasFailed {
                return FeedbackCue(sounds: [
                    .crunch(slot("crush", "grit"), 1500...6000, duration: 0.04, rate: 200, q: 1.5, grain: 0.003, gain: 0.03),
                ], haptics: [.tap(0.25, 0.9)])
            }
            // A slow steel groan per grain.
            return FeedbackCue(sounds: [
                .tone(slot("grain", "groan"), d.range(90...110) * d.grainPitch(), to: 92, glide: 0.18, duration: 0.18,
                      attack: 0.02, decay: 0.08, gain: 0.06 * d.level(), harmonics: 8, vibrato: 3, depth: 0.01),
                .noise(slot("grain", "grit"), .bandPass, 300, q: 3, attack: 0.005, decay: 0.05, gain: 0.04),
            ], haptics: [.tap(0.25 + 0.2 * c, 0.9)])

        case .preFailureTell:
            // GAUGE REDLINE: the needle buzzes against the stop (top-note dinks) under a deep frame groan.
            var sounds: [SoundLayer] = [
                .tone(slot("tell", "groan"), 70, to: 55, glide: 0.6, duration: 0.6, attack: 0.05, decay: 0.25, gain: 0.12,
                      harmonics: 10, vibrato: 2, depth: 0.02),
            ]
            var haptics: [HapticNote] = []
            for i in 0..<8 {
                let t = Float(i) * 0.045
                sounds.append(.tone(slot("redline", "dink\(i)"), BrandCues.pentatonic[BrandCues.pentatonic.count - 1],
                                    duration: 0.04, attack: 0.001, decay: 0.012, gain: 0.05, delay: t))
                haptics.append(.tap(0.25, 0.9, at: Double(t)))
            }
            return FeedbackCue(sounds: sounds, haptics: haptics)

        case .microCrack(let index):
            let p = Float(min(index, 12)) / 12
            return FeedbackCue(sounds: [
                .ring(slot("tell", "tink"), .steel, d.range(700...1100), partials: 6, decay: 0.03, brightness: 0.5,
                      gain: 0.04, seed: d.seed32()),
                .noise(slot("tell", "tick"), .highPass, 6000, attack: 0.0002, decay: 0.0015, gain: 0.04),
            ], haptics: [.tap(0.3 + 0.3 * p, 0.95)])

        case .fracture(let index, false):
            // "CLANG… groan": the frame takes it, twice, a bit louder the second time.
            let s: Float = index == 0 ? 1 : 1.3
            return FeedbackCue(sounds: [
                .tone(slot("groan", "frame"), 60 * d.bodyPitch(), to: 48, glide: 0.5, duration: 0.7, attack: 0.03, decay: 0.3,
                      gain: 0.15 * s, harmonics: 12, vibrato: 1.5, depth: 0.02),
                .noise(slot("groan", "body"), .lowPass, 400, attack: 0.05, decay: 0.2, gain: 0.1 * s),
                .ring(slot("groan", "clang"), .steel, (index == 0 ? 180 : 240) * d.bodyPitch(), partials: 8, decay: 0.5,
                      brightness: 0.6, gain: 0.12 * s, seed: d.seed32()),
            ], haptics: [.tap(0.6 * s, 0.8), .buzz(0.45 * s, 0.7, at: 0.01, duration: 0.6, attack: 0.1, decay: 0.4)])

        case .fracture(_, true):
            // The press CRACKS: metallic crack, frame ring, and a bolt boings away. Comedy, not catastrophe.
            let p = d.bodyPitch()
            var haptics: [HapticNote] = [
                .tap(1.0, 1.0),
                .buzz(0.8, 0.6, at: 0.005, duration: 0.5, decay: 0.45),
            ]
            haptics += d.scatter(4, from: 0.05, over: 0.2, intensity: (0.5, 0.15), sharpness: 0.85...0.95)
            haptics.append(.tap(0.3, 0.5, at: 0.35))
            return FeedbackCue(sounds: [
                .noise(slot("failure", "transient"), .highPass, 6500, attack: 0.0002, decay: 0.003, gain: 0.6),
                .noise(slot("failure", "crack"), .bandPass, 1600 * p, decay: 0.02, gain: 0.45 * d.level()),
                .noise(slot("failure", "body"), .bandPass, 500 * p, q: 1.2, decay: 0.05, gain: 0.35),
                .ring(slot("failure", "frame"), .steel, 310 * p, partials: 12, decay: 0.9, brightness: 0.6, gain: 0.25,
                      seed: d.seed32()),
                .ring(slot("failure", "plate"), .steel, 1150 * p, partials: 10, decay: 0.4, brightness: 0.5, gain: 0.1,
                      delay: 0.004, seed: d.seed32()),
                .crunch(slot("failure", "bits"), 2000...8000, duration: 0.25, rate: 60 * input.debris, rateEnd: 10, q: 1.5,
                        grain: 0.004, gain: 0.08, delay: 0.05),
                .tone(slot("failure", "boing"), 400, to: 300, glide: 0.45, duration: 0.5, attack: 0.004, decay: 0.2,
                      gain: 0.08, harmonics: 3, vibrato: 18, depth: 0.08, delay: 0.35),
            ], haptics: haptics, isClimax: true)

        case .released:
            return FeedbackCue(sounds: [
                .ring(slot("release", "settle"), .steel, 400 * d.bodyPitch(), partials: 6, decay: 0.2, gain: 0.05,
                      seed: d.seed32()),
            ], haptics: [.tap(0.2, 0.8)])

        case .reveal:
            // "Womp womp" (G4 → F#4, F4 → E4): Press 0 – Ball 1.
            return FeedbackCue(sounds: [
                .tone(slot("reveal", "womp1"), 392.0, to: 370.0, glide: 0.25, duration: 0.28, attack: 0.01, decay: 0.12,
                      gain: 0.08, harmonics: 5, vibrato: 5, depth: 0.02),
                .tone(slot("reveal", "womp2"), 349.23, to: 329.63, glide: 0.4, duration: 0.45, attack: 0.01, decay: 0.2,
                      gain: 0.08, harmonics: 5, vibrato: 5, depth: 0.025, delay: 0.3),
            ], haptics: [.tap(0.4, 0.3), .tap(0.3, 0.3, at: 0.3)])
        }
    }
}
