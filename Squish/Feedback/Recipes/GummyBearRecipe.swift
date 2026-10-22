import Foundation

/// Gummy Bear: chewy plastic gel. Rubbery "eek" stretch grains, then the seam SPLITS — a rubbery tear, a low
/// thump and a comic boing as the lobes wobble — then it spreads. Chewy/squidgy layers are tagged wet
/// (chewing is the top misophonia trigger, 02 §6), so Soft style keeps only the dry rubber.
struct GummyBearRecipe: ObjectRecipe {
    let kind = ObjectKind.gummyBear

    var beds: MaterialBeds {
        MaterialBeds(
            strain: NoiseBed(.bandPass, 400, q: 2, gain: 0.025, flutter: 8, depth: 0.5, rise: 0.4),
            crush: GrainBed(rate: 35, band: 250...800, q: 2.5, grain: 0.015, gain: 0.045, wet: true),
            creakPitch: 1.1, creakAmount: 0.2,
            hapticCurve: .easeOut, hapticMax: 0.55,
            crushHapticIntensity: 0.32, crushHapticSharpness: -0.3
        )
    }

    func cue(for moment: RecipeMoment, _ input: RecipeInput) -> FeedbackCue {
        let d = input.dice
        switch moment {
        case .place:
            return FeedbackCue(sounds: [
                .tone(slot("place", "boing"), 200 * d.bodyPitch(), to: 280, glide: 0.05, duration: 0.1, attack: 0.003,
                      decay: 0.035, gain: 0.12, harmonics: 2, vibrato: 9, depth: 0.04),
            ], haptics: [.tap(0.32, 0.15), .tap(0.15, 0.15, at: 0.1)])

        case .contact:
            return FeedbackCue(sounds: [
                .noise(slot("contact", "dmp"), .lowPass, 800, attack: 0.002, decay: 0.02, gain: 0.1 * d.level()),
                .tone(slot("contact", "give"), 240 * d.bodyPitch(), duration: 0.05, attack: 0.003, decay: 0.015, gain: 0.06),
            ], haptics: [.tap(0.35, 0.15)])

        case .grain(let c):
            if input.hasFailed {
                return FeedbackCue(sounds: [
                    .noise(slot("crush", "give"), .lowPass, 700, attack: 0.002, decay: 0.015, gain: 0.03 * d.level()),
                    .tone(slot("crush", "squidge"), 260 * d.grainPitch(), to: 220, glide: 0.04, duration: 0.05, decay: 0.015,
                          gain: 0.025, harmonics: 2, wet: true),
                ], haptics: [.tap(0.14, 0.1)])
            }
            // Rubbery stretch "eek", pitched up with pressure.
            let pitch = (300 + 200 * min(c, 1)) * d.grainPitch()
            return FeedbackCue(sounds: [
                .tone(slot("grain", "eek"), pitch, to: pitch * 1.1, glide: 0.05, duration: 0.06, attack: 0.004, decay: 0.02,
                      gain: 0.035 * d.level(), harmonics: 3),
            ], haptics: [.tap(0.16 + 0.08 * c, 0.15)])

        case .preFailureTell:
            return FeedbackCue(sounds: [
                .tone(slot("tell", "stretch"), 500 * d.bodyPitch(), to: 700, glide: 0.2, duration: 0.22, attack: 0.02,
                      decay: 0.08, gain: 0.035, harmonics: 2, vibrato: 20, depth: 0.03),
            ])

        case .microCrack(let index):
            let p = Float(min(index, 12)) / 12
            return FeedbackCue(sounds: [
                .tone(slot("tell", "tick"), (700 + 30 * Float(min(index, 12))) * d.grainPitch(), duration: 0.03, attack: 0.002,
                      decay: 0.01, gain: 0.025, harmonics: 2),
            ], haptics: [.tap(0.25 + 0.25 * p, 0.2)])

        case .fracture(_, true):
            // The seam SPLITS: tear, thump, a boing as the lobes wobble.
            let p = d.bodyPitch()
            var haptics: [HapticNote] = [
                .tap(1.0, 0.2),
                .buzz(0.6, 0.1, at: 0.005, duration: 0.25, attack: 0.02, decay: 0.2),
            ]
            for i in 0..<4 {
                haptics.append(.tap(0.3 * Float(4 - i) / 4 + 0.05, 0.1, at: 0.12 + Double(i) * 0.14))
            }
            return FeedbackCue(sounds: [
                .noise(slot("failure", "transient"), .lowPass, 4000, attack: 0.0003, decay: 0.004, gain: 0.35),
                .noise(slot("failure", "tear"), .bandPass, 1500, q: 1.2, attack: 0.001, decay: 0.06, gain: 0.3 * d.level(),
                       sweepTo: 500, sweepTime: 0.1),
                .tone(slot("failure", "thump"), 180 * p, to: 110 * p, glide: 0.1, duration: 0.16, attack: 0.002, decay: 0.06,
                      gain: 0.35, harmonics: 3),
                .tone(slot("failure", "boing"), 320 * p, to: 240 * p, glide: 0.3, duration: 0.32, attack: 0.005, decay: 0.12,
                      gain: 0.1, harmonics: 2, vibrato: 7, depth: 0.06, delay: 0.04),
                .noise(slot("failure", "squidge"), .lowPass, 600, attack: 0.02, decay: 0.1, gain: 0.15, delay: 0.03, wet: true),
            ], haptics: haptics, isClimax: true)

        case .fracture(_, false):
            // It spreads.
            return FeedbackCue(sounds: [
                .noise(slot("spread", "press"), .lowPass, 500, attack: 0.04, decay: 0.15, gain: 0.15),
                .tone(slot("spread", "thump"), 150 * d.bodyPitch(), to: 120, glide: 0.1, duration: 0.15, decay: 0.05,
                      gain: 0.12, harmonics: 2),
                .noise(slot("spread", "squidge"), .lowPass, 450, attack: 0.03, decay: 0.12, gain: 0.08, wet: true),
            ], haptics: [.buzz(0.4, 0.1, duration: 0.3, attack: 0.03)])

        case .released:
            return FeedbackCue(sounds: [
                .tone(slot("release", "relax"), 260 * d.grainPitch(), to: 300, glide: 0.1, duration: 0.12, attack: 0.005,
                      decay: 0.04, gain: 0.05, harmonics: 2),
            ], haptics: [.tap(0.2, 0.15)])

        case .reveal:
            return FeedbackCue(sounds: [
                .tone(slot("reveal", "boing"), 240 * d.bodyPitch(), to: 300, glide: 0.08, duration: 0.3, attack: 0.004,
                      decay: 0.1, gain: 0.08, harmonics: 2, vibrato: 7, depth: 0.06),
            ], haptics: [.tap(0.45, 0.15), .tap(0.28, 0.15, at: 0.13), .tap(0.14, 0.15, at: 0.26)])
        }
    }
}
