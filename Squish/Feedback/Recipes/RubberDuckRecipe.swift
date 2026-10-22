import Foundation

/// Rubber Duck: hollow rubber, comic and never pained (bible §8 12+ tone). A squeak whose pitch rises with
/// pressure, a nasal HONK at the first fracture, then the seam pop + cartoon "bloop" + deflating wheeze.
/// Squeaks stay ≤ 1.3 kHz with two harmonics, so nothing sustained lands in the 2.5–4.5 kHz harsh band.
struct RubberDuckRecipe: ObjectRecipe {
    let kind = ObjectKind.rubberDuck

    var beds: MaterialBeds {
        MaterialBeds(
            strain: NoiseBed(.bandPass, 700, q: 2, gain: 0.022, flutter: 5, depth: 0.5, rise: 0.6),
            crush: GrainBed(rate: 40, band: 800...2000, q: 0.8, grain: 0.012, gain: 0.03),
            creakPitch: 1.2, creakAmount: 0.35,
            hapticCurve: .linear, hapticMax: 0.6,
            crushHapticIntensity: 0.3, crushHapticSharpness: -0.25
        )
    }

    func cue(for moment: RecipeMoment, _ input: RecipeInput) -> FeedbackCue {
        let d = input.dice
        switch moment {
        case .place:
            // Rubbery "boing" landing with a little bounce.
            return FeedbackCue(sounds: [
                .tone(slot("place", "boing"), 300 * d.bodyPitch(), to: 420, glide: 0.06, duration: 0.12, decay: 0.04,
                      gain: 0.1, harmonics: 3, vibrato: 10, depth: 0.03),
                .noise(slot("place", "thud"), .lowPass, 600, decay: 0.02, gain: 0.08),
            ], haptics: [.tap(0.35, 0.3), .tap(0.15, 0.3, at: 0.09)])

        case .contact:
            return FeedbackCue(sounds: [
                squeak(d, pitch: 700, gain: 0.07, event: "contact"),
            ], haptics: [.tap(0.4, 0.3)])

        case .grain(let c):
            // The squeak climbs with pressure (bible §4) and the haptic chirps with it (01 §7.3 squeak chirps).
            return FeedbackCue(
                sounds: [squeak(d, pitch: 650 + 450 * min(c, 1), gain: 0.085 * d.level(), event: "grain")],
                haptics: [.buzz(0.22 + 0.15 * c, 0.3, duration: 0.12, attack: 0.01)],
                sharpnessSweep: HapticSweep(from: -0.2, to: 0.3, duration: 0.12)
            )

        case .preFailureTell:
            // Rubber at full stretch: a tight, wobbly squeak.
            return FeedbackCue(sounds: [
                .tone(slot("tell", "stretch"), 1150 * d.grainPitch(), to: 1300, glide: 0.2, duration: 0.25, attack: 0.02,
                      decay: 0.1, gain: 0.05, harmonics: 2, vibrato: 14, depth: 0.03),
            ])

        case .microCrack(let index):
            let p = Float(min(index, 12)) / 12
            return FeedbackCue(sounds: [
                .tone(slot("tell", "creak"), (900 + 300 * p) * d.grainPitch(), to: (1000 + 300 * p), glide: 0.03,
                      duration: 0.04, decay: 0.012, gain: 0.035, harmonics: 2),
            ], haptics: [.tap(0.3 + 0.3 * p, 0.35)])

        case .fracture(_, false):
            // The comic HONK: nasal harmonic stack plus a band-passed formant.
            let contour = d.pick(3, for: slot("honk", "body"))
            let base = 330 * d.bodyPitch()
            let end: Float = [base * 0.9, base * 1.08, base][contour]
            return FeedbackCue(sounds: [
                .tone(slot("honk", "body"), base, to: end, glide: 0.24, duration: 0.26, attack: 0.012, decay: 0.12,
                      gain: 0.15 * d.level(), harmonics: 6, vibrato: 6, depth: 0.012),
                .noise(slot("honk", "nasal"), .bandPass, 1100, q: 4, attack: 0.01, decay: 0.08, gain: 0.06),
            ], haptics: [.tap(0.55, 0.35), .buzz(0.35, 0.3, at: 0.01, duration: 0.22, decay: 0.15)])

        case .fracture(_, true):
            // Seam pop, cartoon "bloop", an air rush and a comic deflating wheeze.
            let p = d.bodyPitch()
            var haptics: [HapticNote] = [
                .tap(1.0, 0.5),
                .buzz(0.4, 0.6, at: 0.01, duration: 0.5, decay: 0.45),
            ]
            for i in 0..<Int(12 * input.debris) {
                haptics.append(.tap(0.2, 0.9, at: 0.03 + Double(i) * 0.025))
            }
            return FeedbackCue(sounds: [
                .noise(slot("failure", "snap"), .highPass, 6000, attack: 0.0003, decay: 0.003, gain: 0.35),
                .noise(slot("failure", "pop"), .bandPass, 900 * p, q: 1.2, decay: 0.045, gain: 0.55 * d.level()),
                .tone(slot("failure", "bloop"), 700 * p, to: 140 * p, glide: 0.12, duration: 0.16, attack: 0.002,
                      decay: 0.06, gain: 0.3, delay: 0.012),
                .noise(slot("failure", "air"), .bandPass, 2000, q: 0.6, attack: 0.01, decay: 0.18, gain: 0.08 * input.debris,
                       delay: 0.02, sweepTo: 900, sweepTime: 0.4),
                .tone(slot("failure", "wheeze"), 520 * p, to: 380 * p, glide: 0.35, duration: 0.4, attack: 0.03, decay: 0.15,
                      gain: 0.05, harmonics: 2, vibrato: 9, depth: 0.03, delay: 0.08),
            ], haptics: haptics, isClimax: true)

        case .released:
            // Re-inflating squeak as it springs back.
            return FeedbackCue(sounds: [
                .tone(slot("release", "reinflate"), 600 * d.grainPitch(), to: 900, glide: 0.15, duration: 0.18, attack: 0.01,
                      decay: 0.08, gain: 0.07, harmonics: 2, vibrato: 24, depth: 0.015),
            ], haptics: [.tap(0.2, 0.3), .buzz(0.18, 0.25, at: 0.02, duration: 0.12)])

        case .reveal:
            // Deflate wheeze "pffft" and a last tiny squeak: he'll be fine.
            return FeedbackCue(sounds: [
                .noise(slot("reveal", "wheeze"), .bandPass, 1600, q: 0.8, attack: 0.03, decay: 0.15, gain: 0.05,
                       sweepTo: 700, sweepTime: 0.45),
                squeak(d, pitch: 900, gain: 0.05, event: "reveal", delay: 0.35),
            ], haptics: [.buzz(0.3, 0.4, duration: 0.5, attack: 0.02, decay: 0.45)])
        }
    }

    /// Comic upward-bending squeak (02 §1.2: bends up, never a scream).
    private func squeak(_ d: FeedbackDice, pitch: Float, gain: Float, event: String, delay: Float = 0) -> SoundLayer {
        let p = pitch * d.grainPitch()
        return .tone(slot(event, "squeak"), p, to: p * 1.18, glide: 0.1, duration: 0.14, attack: 0.01, decay: 0.06,
                     gain: gain, harmonics: 2, vibrato: 26, depth: 0.015, delay: delay)
    }
}
