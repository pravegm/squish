import Foundation

/// Cake Slice: the cosy one, lowest intensity in the set (02 §7.3). Soft sponge compressions, dense dry crumbs
/// (1.2° grains, 01 §7.3), the icing cracking, a comic candle "bwoing", then a soft whump as the layers collapse
/// and the frosting squirts. Even the failure stays below the others' punch.
struct CakeSliceRecipe: ObjectRecipe {
    let kind = ObjectKind.cakeSlice

    var beds: MaterialBeds {
        MaterialBeds(
            strain: NoiseBed(.lowPass, 700, q: 0.7, gain: 0.02, flutter: 3, depth: 0.3, rise: 0.3),
            crush: GrainBed(rate: 90, band: 600...2500, q: 1.1, grain: 0.003, gain: 0.035),
            creakPitch: 0.95, creakAmount: 0.15,
            hapticCurve: .linear, hapticMax: 0.45,
            crushHapticIntensity: 0.22, crushHapticSharpness: -0.1
        )
    }

    func cue(for moment: RecipeMoment, _ input: RecipeInput) -> FeedbackCue {
        let d = input.dice
        switch moment {
        case .place:
            return FeedbackCue(sounds: [
                .noise(slot("place", "pff"), .lowPass, 600, attack: 0.004, decay: 0.04, gain: 0.14 * d.level()),
                .tone(slot("place", "thump"), 150 * d.bodyPitch(), to: 110, glide: 0.05, duration: 0.08, attack: 0.002,
                      decay: 0.025, gain: 0.1, harmonics: 3),
            ], haptics: [.tap(0.3, 0.15)])

        case .contact:
            return FeedbackCue(sounds: [
                .noise(slot("contact", "sponge"), .lowPass, 900, attack: 0.003, decay: 0.03, gain: 0.1 * d.level()),
            ], haptics: [.tap(0.3, 0.15)])

        case .grain(let c):
            // A crumb, sometimes two.
            var sounds: [SoundLayer] = [
                .noise(slot("grain", "crumb"), .bandPass, d.range(700...2200) * d.grainPitch(), q: 1.2, decay: 0.003,
                       gain: 0.025 * d.level()),
            ]
            if d.chance(0.4) {
                sounds.append(.noise(slot("grain", "crumb2"), .bandPass, d.range(900...2500), q: 1.2, decay: 0.002,
                                     gain: 0.018, delay: d.range(0.003...0.012)))
            }
            let scale: Float = input.hasFailed ? 0.7 : 1
            return FeedbackCue(sounds: sounds, haptics: [.tap(d.range(0.15...0.3) * scale * (0.9 + 0.2 * c), 0.45)])

        case .preFailureTell:
            return FeedbackCue(sounds: [
                .noise(slot("tell", "sigh"), .lowPass, 700, attack: 0.08, decay: 0.15, gain: 0.04),
            ])

        case .microCrack:
            return FeedbackCue(sounds: [
                .noise(slot("tell", "crumb"), .bandPass, 1800 * d.grainPitch(), q: 1.2, decay: 0.002, gain: 0.03),
            ], haptics: [.tap(0.25, 0.45)])

        case .fracture(let index, false) where index == 0:
            // The icing cracks.
            var haptics: [HapticNote] = [.tap(0.55, 0.5)]
            haptics += d.scatter(4, from: 0.02, over: 0.08, intensity: (0.35, 0.15), sharpness: 0.45...0.6)
            return FeedbackCue(sounds: [
                .crunch(slot("icing", "crack"), 1500...4500, duration: 0.08, rate: 200, rateEnd: 60, q: 1.2, grain: 0.002,
                        gain: 0.14 * d.level()),
                .noise(slot("icing", "body"), .bandPass, 1100 * d.bodyPitch(), q: 1.2, decay: 0.01, gain: 0.12),
            ], haptics: haptics)

        case .fracture(_, false):
            // The candle bends: a comic "bwoing" plus a little wax creak.
            return FeedbackCue(sounds: [
                .tone(slot("candle", "bwoing"), 260 * d.bodyPitch(), to: 200, glide: 0.22, duration: 0.26, attack: 0.005,
                      decay: 0.1, gain: 0.08, harmonics: 3, vibrato: 12, depth: 0.05),
                .noise(slot("candle", "creak"), .bandPass, 1300, q: 3, decay: 0.01, gain: 0.05),
            ], haptics: [.tap(0.4, 0.4), .buzz(0.3, 0.3, at: 0.01, duration: 0.2)])

        case .fracture(_, true):
            // Layer collapse + frosting squirt: a cosy whump, crumbs, sprinkles.
            let p = d.bodyPitch()
            var haptics: [HapticNote] = [
                .tap(0.85, 0.2),
                .buzz(0.6, 0.1, at: 0.005, duration: 0.3, decay: 0.25),
            ]
            haptics += d.scatter(Int(6 * input.debris), from: 0.04, over: 0.3, intensity: (0.3, 0.12), sharpness: 0.4...0.5)
            return FeedbackCue(sounds: [
                .noise(slot("failure", "whump"), .lowPass, 500, attack: 0.005, decay: 0.09, gain: 0.45 * d.level()),
                .tone(slot("failure", "thump"), 140 * p, to: 80 * p, glide: 0.1, duration: 0.18, attack: 0.003, decay: 0.06,
                      gain: 0.3, harmonics: 3),
                .crunch(slot("failure", "crumble"), 600...2500, duration: 0.35, rate: 120 * input.debris, rateEnd: 20, q: 1.1,
                        grain: 0.004, gain: 0.18, delay: 0.02),
                .noise(slot("failure", "squirt"), .bandPass, 1400, q: 0.9, attack: 0.01, decay: 0.12, gain: 0.12, delay: 0.03,
                       sweepTo: 500, sweepTime: 0.2, wet: true),
                .crunch(slot("failure", "sprinkles"), 5000...9000, duration: 0.2, rate: 40, rateEnd: 10, q: 2, grain: 0.0015,
                        gain: 0.06, delay: 0.04),
            ], haptics: haptics, isClimax: true)

        case .released:
            return .silent

        case .reveal:
            // Plop (01 §7.3: T 0.6/0.15 + crumbs).
            var haptics: [HapticNote] = [.tap(0.6, 0.15)]
            haptics += d.scatter(5, from: 0.05, over: 0.25, intensity: (0.25, 0.1), sharpness: 0.4...0.5)
            return FeedbackCue(sounds: [
                .noise(slot("reveal", "plop"), .lowPass, 700, attack: 0.003, decay: 0.035, gain: 0.1),
                .crunch(slot("reveal", "crumbs"), 700...2500, duration: 0.25, rate: 40, rateEnd: 8, q: 1.1, grain: 0.003,
                        gain: 0.06, delay: 0.04),
            ], haptics: haptics)
        }
    }
}
