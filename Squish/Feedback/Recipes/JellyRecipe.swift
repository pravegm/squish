import Foundation

/// Jelly: gel that wobbles, splits its skin, then splats. Kept clean and cartoony, never mouth-like (02 §7.3):
/// short pitched bubble "blips" (Minnaert-style upward glides) over dry, low-passed thumps. Liquid layers are
/// tagged wet so Soft style drops them; the dry layers carry the gesture on their own.
struct JellyRecipe: ObjectRecipe {
    let kind = ObjectKind.jelly

    var beds: MaterialBeds {
        MaterialBeds(
            strain: NoiseBed(.lowPass, 500, q: 0.7, gain: 0.03, flutter: 6.5, depth: 0.7, rise: 0.3),
            crush: GrainBed(rate: 30, band: 300...900, q: 2, grain: 0.02, gain: 0.05, wet: true),
            creakPitch: 0.9, creakAmount: 0.12,
            hapticCurve: .easeOut, hapticMax: 0.5,
            crushHapticIntensity: 0.35, crushHapticSharpness: -0.3
        )
    }

    func cue(for moment: RecipeMoment, _ input: RecipeInput) -> FeedbackCue {
        let d = input.dice
        switch moment {
        case .place:
            // Wobbly plop, felt as the 6–8 Hz wobble (01 §2.2).
            return FeedbackCue(sounds: [
                .tone(slot("place", "wobble"), 180 * d.bodyPitch(), to: 240, glide: 0.05, duration: 0.14, attack: 0.004,
                      decay: 0.06, gain: 0.13, harmonics: 2, vibrato: 7, depth: 0.06),
                .noise(slot("place", "plap"), .lowPass, 1000, attack: 0.002, decay: 0.02, gain: 0.08),
            ], haptics: wobble(0.35))

        case .contact:
            return FeedbackCue(sounds: [
                .noise(slot("contact", "plap"), .lowPass, 1200, attack: 0.001, decay: 0.02, gain: 0.12 * d.level()),
                .tone(slot("contact", "give"), 220 * d.bodyPitch(), to: 260, glide: 0.04, duration: 0.06, decay: 0.02,
                      gain: 0.07),
            ], haptics: [.tap(0.3, 0.1)])

        case .grain(let c):
            let blip = (500 + 300 * d.unit()) * d.grainPitch()
            return FeedbackCue(sounds: [
                .tone(slot("grain", "blip"), blip, to: blip * 1.3, glide: 0.03, duration: 0.04, attack: 0.002, decay: 0.012,
                      gain: 0.045 * d.level(), wet: true),
                .noise(slot("grain", "give"), .lowPass, 900, attack: 0.001, decay: 0.012, gain: 0.03 * d.level()),
            ], haptics: [.tap(0.14 + 0.06 * c, 0.1)])

        case .preFailureTell:
            // The skin stretching tight.
            return FeedbackCue(sounds: [
                .noise(slot("tell", "stretch"), .bandPass, 600, q: 3, attack: 0.05, decay: 0.12, gain: 0.04),
            ])

        case .microCrack(let index):
            let p = Float(min(index, 12)) / 12
            return FeedbackCue(sounds: [
                .tone(slot("tell", "bubble"), (700 + 200 * p) * d.grainPitch(), to: 950, glide: 0.025, duration: 0.03,
                      decay: 0.01, gain: 0.03, wet: true),
                .noise(slot("tell", "tick"), .lowPass, 1500, decay: 0.004, gain: 0.025),
            ], haptics: [.tap(0.25 + 0.25 * p, 0.15)])

        case .fracture(_, false):
            // The skin splits: a quick tearing swish and one bubble.
            return FeedbackCue(sounds: [
                .noise(slot("split", "tear"), .bandPass, 1800, q: 1.4, attack: 0.002, decay: 0.05, gain: 0.25 * d.level(),
                       sweepTo: 700, sweepTime: 0.08),
                .tone(slot("split", "blip"), 400 * d.bodyPitch(), to: 700, glide: 0.05, duration: 0.06, decay: 0.02,
                      gain: 0.12, wet: true),
            ], haptics: [.tap(0.6, 0.2), .buzz(0.4, 0.05, at: 0.01, duration: 0.15, attack: 0.03, decay: 0.12)])

        case .fracture(_, true):
            // SPLAT: dry thwack + low thump, then splorts out the sides and a cluster of bubbles.
            let p = d.bodyPitch()
            var sounds: [SoundLayer] = [
                .noise(slot("failure", "thwack"), .lowPass, 3000, attack: 0.0005, decay: 0.006, gain: 0.4),
                .tone(slot("failure", "thump"), 160 * p, to: 90 * p, glide: 0.08, duration: 0.14, attack: 0.002, decay: 0.05,
                      gain: 0.4 * d.level(), harmonics: 3),
                .noise(slot("failure", "body"), .lowPass, 900, attack: 0.002, decay: 0.06, gain: 0.35),
                .crunch(slot("failure", "splorts"), 300...1200, duration: 0.3, rate: 40 * input.debris, rateEnd: 10, q: 1.5,
                        grain: 0.015, gain: 0.18, fade: 0.2, delay: 0.02, wet: true),
            ]
            for i in 0..<3 {
                let blip = d.range(600...1100) * p
                sounds.append(.tone(slot("failure", "bubble\(i)"), blip, to: blip * 1.35, glide: 0.03, duration: 0.05,
                                    decay: 0.015, gain: 0.06, delay: d.range(0.05...0.2), wet: true))
            }
            var haptics: [HapticNote] = [
                .tap(1.0, 0.1),
                .buzz(0.7, 0.05, at: 0.005, duration: 0.25, decay: 0.2),
            ]
            haptics += d.scatter(5, from: 0.06, over: 0.25, intensity: (0.3, 0.15), sharpness: 0.05...0.15)
            return FeedbackCue(sounds: sounds, haptics: haptics, isClimax: true)

        case .released:
            // Elastic jiggle as it slurps back into shape (dry, pitched wobble).
            return FeedbackCue(sounds: [
                .tone(slot("release", "jiggle"), 220 * d.bodyPitch(), to: 200, glide: 0.25, duration: 0.3, attack: 0.01,
                      decay: 0.12, gain: 0.07, harmonics: 2, vibrato: 7, depth: 0.08),
            ], haptics: wobble(0.3))

        case .reveal:
            return FeedbackCue(sounds: [
                .tone(slot("reveal", "wobble"), 200 * d.bodyPitch(), to: 190, glide: 0.3, duration: 0.4, attack: 0.01,
                      decay: 0.15, gain: 0.08, harmonics: 2, vibrato: 7, depth: 0.07),
            ], haptics: wobble(0.5))
        }
    }

    /// 3 decaying soft transients at the visual wobble frequency (01 §2.2: 0.5, 0.3, 0.15 @ S 0.1, 130 ms apart).
    private func wobble(_ intensity: Float) -> [HapticNote] {
        [.tap(intensity, 0.1), .tap(intensity * 0.6, 0.1, at: 0.13), .tap(intensity * 0.3, 0.1, at: 0.26)]
    }
}
