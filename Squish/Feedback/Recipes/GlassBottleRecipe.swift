import Foundation

/// Glass Bottle: tension, then the biggest event in the app (bible §4). Silent rigidity broken only by tiny
/// tick-strain clicks (no screech: nothing sustained in 2–5 kHz), a crack, then the SHATTER — a hard strike,
/// a speaker-friendly bottle thump, clustered glass rings and two waves of shard debris band-limited to 9 kHz
/// (02 §7.3). Haptic shatter per 01 §7.3: strike, then ~16 tinkles over 250 ms.
struct GlassBottleRecipe: ObjectRecipe {
    let kind = ObjectKind.glassBottle

    var beds: MaterialBeds {
        MaterialBeds(
            strain: NoiseBed(.bandPass, 900, q: 2, gain: 0.006, flutter: 0.8, depth: 0.3),
            crush: GrainBed(rate: 200, band: 2000...9000, q: 1.5, grain: 0.0015, gain: 0.05),
            creakPitch: 0.9, creakAmount: 0.35,
            hapticCurve: .easeIn, hapticMax: 0.7,
            crushHapticIntensity: 0.35, crushHapticSharpness: 0.05
        )
    }

    func cue(for moment: RecipeMoment, _ input: RecipeInput) -> FeedbackCue {
        let d = input.dice
        switch moment {
        case .place:
            return FeedbackCue(sounds: [
                .ring(slot("place", "tunk"), .glass, 820 * d.bodyPitch(), partials: 8, decay: 0.12, brightness: 0.5,
                      gain: 0.12, seed: d.seed32()),
                .tone(slot("place", "body"), 200 * d.bodyPitch(), to: 150, glide: 0.04, duration: 0.06, attack: 0.002,
                      decay: 0.02, gain: 0.08, harmonics: 2),
            ], haptics: [.tap(0.4, 0.85)])

        case .contact:
            return FeedbackCue(sounds: [
                .ring(slot("contact", "tick"), .glass, 1500 * d.bodyPitch(), partials: 6, decay: 0.03, brightness: 0.5,
                      gain: 0.07, seed: d.seed32()),
                .noise(slot("contact", "click"), .highPass, 6000, attack: 0.0002, decay: 0.0015, gain: 0.06),
            ], haptics: [.tap(0.4, 0.9)])

        case .grain(let c):
            if input.hasFailed {
                // Shard crunch (01 §7.3: Δθ 0.5°, I 0.35, S 0.95), low-passed at 9 kHz.
                return FeedbackCue(sounds: [
                    .crunch(slot("crush", "grit"), 2000...9000, duration: 0.03, rate: 400, q: 1.5, grain: 0.0012,
                            gain: 0.05 * d.level()),
                    .ring(slot("crush", "tink"), .glass, d.range(5000...8000), partials: 3, decay: 0.02, brightness: 0.4,
                          gain: 0.02, seed: d.seed32()),
                ], haptics: [.tap(0.35, 0.95)])
            }
            // Tick-strain before the crack.
            return FeedbackCue(sounds: [
                .noise(slot("grain", "tick"), .highPass, 6000 * d.grainPitch(), attack: 0.0002, decay: 0.0012,
                       gain: 0.03 * d.level()),
                .ring(slot("grain", "tink"), .glass, 5200 * d.grainPitch(), partials: 3, decay: 0.01, brightness: 0.4,
                      gain: 0.02, seed: d.seed32()),
            ], haptics: [.tap(0.25 + 0.1 * c, 0.95)])

        case .preFailureTell:
            return FeedbackCue(sounds: [
                .noise(slot("tell", "tick1"), .highPass, 7000, attack: 0.0002, decay: 0.001, gain: 0.05),
                .noise(slot("tell", "tick2"), .highPass, 7500, attack: 0.0002, decay: 0.001, gain: 0.04, delay: 0.03),
                .noise(slot("tell", "tick3"), .highPass, 6800, attack: 0.0002, decay: 0.001, gain: 0.045, delay: 0.07),
            ])

        case .microCrack(let index):
            let p = Float(min(index, 12)) / 12
            return FeedbackCue(sounds: [
                .noise(slot("tell", "micro"), .highPass, 6500 * d.grainPitch(), attack: 0.0002, decay: 0.001, gain: 0.05),
                .ring(slot("tell", "tink"), .glass, d.range(5000...7000), partials: 3, decay: 0.008, brightness: 0.4,
                      gain: 0.03, seed: d.seed32()),
            ], haptics: [.tap(0.3 + 0.3 * p, 0.95)])

        case .fracture(let index, false) where index == 0:
            // The crack: strike, short body, one glass ring.
            return FeedbackCue(sounds: [
                .noise(slot("crack", "transient"), .highPass, 7000, attack: 0.0002, decay: 0.0015, gain: 0.4 * d.level()),
                .noise(slot("crack", "snap"), .bandPass, 2200, q: 1.2, decay: 0.006, gain: 0.3),
                .noise(slot("crack", "body"), .bandPass, 900 * d.bodyPitch(), q: 1.5, decay: 0.02, gain: 0.2),
                .ring(slot("crack", "ring"), .glass, 1100 * d.bodyPitch(), partials: 8, decay: 0.06, brightness: 0.5,
                      gain: 0.12, seed: d.seed32()),
            ], haptics: [.tap(0.8, 1.0), .tap(0.55, 0.95, at: 0.02), .tap(0.4, 0.9, at: 0.042)])

        case .fracture(_, true):
            return shatter(d, input: input)

        case .fracture(_, false):
            // Further crush of the shards.
            return FeedbackCue(sounds: [
                .crunch(slot("crunch", "shards"), 1500...9000, duration: 0.3, rate: 250 * input.debris, rateEnd: 30, q: 1.3,
                        grain: 0.002, gain: 0.2 * d.level()),
                .ring(slot("crunch", "tink"), .glass, d.range(1200...1800), partials: 6, decay: 0.05, brightness: 0.45,
                      gain: 0.06, seed: d.seed32()),
            ], haptics: d.scatter(Int(8 * input.debris), from: 0, over: 0.2, intensity: (0.6, 0.1), sharpness: 0.9...1.0))

        case .released:
            guard input.hasFailed else { return .silent }
            // A tinkle trickle as the shards settle.
            return FeedbackCue(sounds: [
                .crunch(slot("release", "tinkle"), 4000...9000, duration: 0.4, rate: 15, rateEnd: 4, q: 5, grain: 0.01,
                        gain: 0.04),
            ], haptics: [.tap(0.15, 1.0), .tap(0.12, 1.0, at: 0.13), .tap(0.1, 1.0, at: 0.29)])

        case .reveal:
            // Glitter tinkle (02 §7.1 phase 8).
            return FeedbackCue(sounds: [
                .crunch(slot("reveal", "glitter"), 5000...9000, duration: 0.6, rate: 20, rateEnd: 4, q: 6, grain: 0.015,
                        gain: 0.07),
            ], haptics: d.scatter(5, from: 0, over: 0.4, intensity: (0.2, 0.15), sharpness: 0.95...1.0))
        }
    }

    /// The biggest event in the app. Slams scatter 1.5× more debris.
    private func shatter(_ d: FeedbackDice, input: RecipeInput) -> FeedbackCue {
        let p = d.bodyPitch()
        let debris = input.debris
        var sounds: [SoundLayer] = [
            .noise(slot("failure", "transient"), .highPass, 7500, attack: 0.0002, decay: 0.0025, gain: 0.6),
            .tone(slot("failure", "thump"), 180 * p, to: 90 * p, glide: 0.08, duration: 0.15, attack: 0.001, decay: 0.05,
                  gain: 0.45 * d.level(), harmonics: 4),
            .noise(slot("failure", "body"), .bandPass, 1200 * p, decay: 0.04, gain: 0.5 * d.level()),
            .crunch(slot("failure", "debris"), 1500...9000, duration: 0.6, rate: 350 * debris, rateEnd: 30, q: 1.2,
                    grain: 0.003, gain: 0.28 * min(debris, 1.25), fade: 0.15, delay: 0.015),
            .crunch(slot("failure", "tinkles"), 5000...9000, duration: 0.7, rate: 40 * debris, rateEnd: 6, q: 6,
                    grain: 0.012, gain: 0.1, fade: 0.3, delay: 0.08),
            .crunch(slot("failure", "settle"), 1000...6000, duration: 0.4, rate: 120, rateEnd: 10, q: 1.2, grain: 0.0025,
                    gain: 0.12, fade: 0.2, delay: 0.25),
        ]
        let ringDelays: [Float] = [0, 0.01, 0.025]
        for (i, delay) in ringDelays.enumerated() {
            sounds.append(.ring(slot("failure", "ring\(i)"), .glass, d.range(900...1600) * p, partials: 8, decay: 0.15,
                                brightness: 0.45, gain: 0.12, delay: delay, seed: d.seed32()))
        }
        var haptics: [HapticNote] = [.tap(1.0, 1.0)]
        haptics += d.scatter(Int(16 * debris), from: 0.012, over: 0.25, intensity: (0.7, 0.1), sharpness: 0.85...1.0)
        return FeedbackCue(sounds: sounds, haptics: haptics, isClimax: true)
    }
}
