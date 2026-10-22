import Foundation

/// Egg: two textures (02 §7.3). Shell first — tiny strain ticks, a hairline crack, then the CRACK (three sharp
/// transients 18–40 ms apart, 01 §7.3) — and then a soft yolk spread. The "wet" side is a slow low-passed swell and
/// a cartoon "glop", never a meaty squelch; it is tagged wet so Soft style keeps only the shell.
struct EggRecipe: ObjectRecipe {
    let kind = ObjectKind.egg

    var beds: MaterialBeds {
        MaterialBeds(
            strain: NoiseBed(.bandPass, 1200, q: 1.5, gain: 0.012, flutter: 13, depth: 0.8, rise: 0.3),
            crush: GrainBed(rate: 25, band: 250...700, q: 2, grain: 0.02, gain: 0.04, wet: true),
            creakPitch: 1.0, creakAmount: 0.3,
            hapticCurve: .linear, hapticMax: 0.45,
            crushHapticIntensity: 0.3, crushHapticSharpness: -0.6
        )
    }

    func cue(for moment: RecipeMoment, _ input: RecipeInput) -> FeedbackCue {
        let d = input.dice
        switch moment {
        case .place:
            return FeedbackCue(sounds: [
                .tone(slot("place", "tok"), 1400 * d.bodyPitch(), to: 1300, glide: 0.02, duration: 0.03, attack: 0.001,
                      decay: 0.008, gain: 0.08),
                .noise(slot("place", "shell"), .bandPass, 2200, q: 3, decay: 0.006, gain: 0.08),
            ], haptics: [.tap(0.3, 0.7)])

        case .contact:
            return FeedbackCue(sounds: [
                .noise(slot("contact", "tick"), .bandPass, 3200 * d.grainPitch(), q: 3, attack: 0.0002, decay: 0.003,
                       gain: 0.1 * d.level()),
            ], haptics: [.tap(0.4, 0.7)])

        case .grain(let c):
            if input.hasFailed {
                // Goo: soft, low, dry give with an occasional bubble (wet).
                return FeedbackCue(sounds: [
                    .noise(slot("crush", "give"), .lowPass, 600, attack: 0.002, decay: 0.015, gain: 0.03 * d.level()),
                    .tone(slot("crush", "bubble"), 450 * d.grainPitch(), to: 600, glide: 0.03, duration: 0.04, decay: 0.012,
                          gain: 0.03, wet: true),
                ], haptics: [.tap(0.12, 0.05)])
            }
            // Shell strain "tick" (01 §7.3: 3.0°, 0.20, 0.90).
            return FeedbackCue(sounds: [
                .noise(slot("grain", "tick"), .bandPass, d.range(2600...4000) * d.grainPitch(), q: 4, attack: 0.0002,
                       decay: 0.0018, gain: 0.04 * d.level()),
            ], haptics: [.tap(0.2 + 0.05 * c, 0.9)])

        case .preFailureTell:
            return FeedbackCue(sounds: [
                .noise(slot("tell", "tick1"), .highPass, 5000, attack: 0.0002, decay: 0.0012, gain: 0.04),
                .noise(slot("tell", "tick2"), .highPass, 5500, attack: 0.0002, decay: 0.0012, gain: 0.035, delay: 0.025),
                .noise(slot("tell", "tick3"), .highPass, 4800, attack: 0.0002, decay: 0.0012, gain: 0.03, delay: 0.055),
            ])

        case .microCrack(let index):
            let p = Float(min(index, 12)) / 12
            return FeedbackCue(sounds: [
                .noise(slot("tell", "micro"), .highPass, 4500 * d.grainPitch(), attack: 0.0002, decay: 0.0012, gain: 0.07),
                .noise(slot("tell", "microbody"), .bandPass, 1800, q: 5, decay: 0.004, gain: 0.03),
            ], haptics: [.tap(0.3 + 0.3 * p, 0.95)])

        case .fracture(let index, false) where index == 0:
            // Hairline crack: two ticks and a tiny tink.
            return FeedbackCue(sounds: [
                .noise(slot("hairline", "tick1"), .bandPass, 3500, q: 2, attack: 0.0002, decay: 0.003, gain: 0.2 * d.level()),
                .noise(slot("hairline", "tick2"), .bandPass, 3100, q: 2, attack: 0.0002, decay: 0.003, gain: 0.12, delay: 0.018),
                .ring(slot("hairline", "tink"), .glass, 2100 * d.bodyPitch(), partials: 3, decay: 0.02, brightness: 0.4,
                      gain: 0.05, seed: d.seed32()),
            ], haptics: [.tap(0.6, 0.95), .tap(0.45, 0.95, at: 0.018)])

        case .fracture(_, true):
            // CRACK + yolk: shell crack and crunch, then the soft spread.
            let p = d.bodyPitch()
            var haptics: [HapticNote] = [
                .tap(1.0, 0.95),
                .tap(0.6, 0.95, at: 0.018),
                .tap(0.5, 0.9, at: 0.04),
                .buzz(0.6, 0.05, at: 0.05, duration: 0.35, attack: 0.05, decay: 0.25),
            ]
            haptics += d.scatter(Int(8 * input.debris), from: 0.08, over: 0.3, intensity: (0.3, 0.2), sharpness: 0.05...0.15)
            return FeedbackCue(sounds: [
                .noise(slot("failure", "transient"), .highPass, 6500, attack: 0.0002, decay: 0.002, gain: 0.45),
                .noise(slot("failure", "crack"), .bandPass, 1800 * p, q: 1.4, decay: 0.012, gain: 0.5 * d.level()),
                .noise(slot("failure", "shell"), .bandPass, 700 * p, q: 1.5, decay: 0.03, gain: 0.35),
                .crunch(slot("failure", "crunch"), 1500...5000, duration: 0.12, rate: 150 * input.debris, rateEnd: 40, q: 1.3,
                        grain: 0.002, gain: 0.2, delay: 0.01),
                .tone(slot("failure", "glop"), 300 * p, to: 180 * p, glide: 0.06, duration: 0.1, attack: 0.003, decay: 0.04,
                      gain: 0.15, harmonics: 2, delay: 0.05),
                .noise(slot("failure", "yolk"), .lowPass, 700, attack: 0.03, decay: 0.12, gain: 0.2, delay: 0.05,
                       sweepTo: 350, sweepTime: 0.3, wet: true),
                .tone(slot("failure", "bubble"), 520 * p, to: 700 * p, glide: 0.03, duration: 0.05, decay: 0.015, gain: 0.05,
                      delay: 0.14, wet: true),
            ], haptics: haptics, isClimax: true)

        case .fracture(_, false):
            // The yolk spreads; a few shell bits crunch under it.
            return FeedbackCue(sounds: [
                .noise(slot("spread", "yolk"), .lowPass, 500, attack: 0.05, decay: 0.2, gain: 0.12, wet: true),
                .crunch(slot("spread", "shell"), 1200...4000, duration: 0.2, rate: 50, rateEnd: 10, q: 1.3, grain: 0.002,
                        gain: 0.08),
                .tone(slot("spread", "glop"), 260 * d.bodyPitch(), to: 200, glide: 0.08, duration: 0.1, decay: 0.04,
                      gain: 0.07, harmonics: 2),
            ], haptics: [.buzz(0.35, 0.05, duration: 0.3, attack: 0.05), .tap(0.3, 0.6, at: 0.04), .tap(0.2, 0.6, at: 0.1)])

        case .released:
            return .silent

        case .reveal:
            // Peel (01 §7.3: C 0.35/0.0, 0.4 s, 0.1 → 0.4 → 0) and a tiny shell tinkle.
            return FeedbackCue(sounds: [
                .noise(slot("reveal", "peel"), .bandPass, 1500, q: 0.8, attack: 0.1, decay: 0.12, gain: 0.04,
                       sweepTo: 2500, sweepTime: 0.3),
                .crunch(slot("reveal", "shell"), 2000...5000, duration: 0.2, rate: 25, rateEnd: 5, q: 2, grain: 0.003,
                        gain: 0.05, delay: 0.1),
            ], haptics: [.buzz(0.35, 0.0, duration: 0.4, attack: 0.15, decay: 0.25)])
        }
    }
}
