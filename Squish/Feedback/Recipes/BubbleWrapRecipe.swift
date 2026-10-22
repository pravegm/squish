import Foundation

/// Bubble Wrap: the most ASMR-like object (02 §7.3 "air pop"). Every bubble is its own crisp pop —
/// a 7 kHz snap, a band-passed air body whose pitch follows the bubble's size, and a tiny low "tock".
/// Between pops: dry plastic crinkle. No failure, no wet layers.
struct BubbleWrapRecipe: ObjectRecipe {
    let kind = ObjectKind.bubbleWrap

    var beds: MaterialBeds {
        MaterialBeds(
            strain: NoiseBed(.bandPass, 5200, q: 0.7, gain: 0.018, flutter: 9, depth: 0.6, rise: 0.2),
            crush: GrainBed(rate: 60, band: 4000...9000, q: 1, grain: 0.002, gain: 0.04),
            creakPitch: 1.1, creakAmount: 0.25,
            hapticCurve: .linear, hapticMax: 0.55,
            crushHapticIntensity: 0.2, crushHapticSharpness: -0.1
        )
    }

    /// Deterministic bubble size from the press seed and the bubble's index: 0.75 (small, high) … 1.35 (big, low).
    static func bubbleSize(index: Int, seed: UInt64) -> Float {
        var rng = SplitMix64(seed: seed ^ (UInt64(index + 1) &* 0xB0BB_1E5))
        return Float.random(in: 0.75...1.35, using: &rng)
    }

    func cue(for moment: RecipeMoment, _ input: RecipeInput) -> FeedbackCue {
        let d = input.dice
        switch moment {
        case .place:
            return FeedbackCue(sounds: [
                .crunch(slot("place", "crinkle"), 4000...9000, duration: 0.09, rate: 300, rateEnd: 80, q: 1, grain: 0.0015,
                        gain: 0.06 * d.level()),
                .tone(slot("place", "plop"), 260 * d.bodyPitch(), to: 150, glide: 0.05, duration: 0.07, decay: 0.02,
                      gain: 0.1, harmonics: 2),
            ], haptics: [.tap(0.3, 0.5)])

        case .contact:
            return FeedbackCue(sounds: [
                .noise(slot("contact", "crinkle"), .highPass, 6000 * d.grainPitch(), decay: 0.008, gain: 0.05 * d.level()),
            ], haptics: [.tap(0.35, 0.6)])

        case .grain(let c):
            // Plastic crinkle tick, sometimes doubled.
            var sounds: [SoundLayer] = [
                .noise(slot("grain", "crinkle"), .highPass, 5000 * d.grainPitch(), decay: 0.004, gain: 0.035 * d.level()),
            ]
            if d.chance(0.5) {
                sounds.append(.noise(slot("grain", "crinkle2"), .highPass, 6500 * d.grainPitch(), decay: 0.003,
                                     gain: 0.022 * d.level(), delay: d.range(0.004...0.009)))
            }
            return FeedbackCue(sounds: sounds, haptics: [.tap(0.12 + 0.1 * c, 0.75)])

        case .preFailureTell, .microCrack:
            return .silent

        case .fracture(let index, _):
            let size = Self.bubbleSize(index: index, seed: input.context.variant.seed)
            let pitch = d.grainPitch() / size
            let shape = d.pick(3, for: slot("pop", "body"))
            let q: Float = [1.6, 2.2, 1.2][shape]
            let decay: Float = [0.016, 0.012, 0.02][shape] * size
            return FeedbackCue(sounds: [
                .noise(slot("pop", "snap"), .highPass, 7000, attack: 0.0003, decay: 0.0025, gain: 0.22 * d.level()),
                .noise(slot("pop", "body"), .bandPass, 1300 * pitch, q: q, decay: decay, gain: 0.45 * d.level(),
                       delay: d.range(0...0.002)),
                .tone(slot("pop", "tock"), 240 * pitch, to: 130 * pitch, glide: 0.03, duration: 0.05, attack: 0.001,
                      decay: 0.015, gain: 0.12 * size, harmonics: 2, delay: 0.002),
            ], haptics: [.tap(min(0.5 + 0.22 * (size - 0.75), 0.8), 0.8)])

        case .released:
            return FeedbackCue(sounds: [
                .crunch(slot("release", "crinkle"), 5000...9000, duration: 0.15, rate: 120, rateEnd: 20, q: 1, grain: 0.0015,
                        gain: 0.03),
            ])

        case .reveal:
            return FeedbackCue(sounds: [
                .crunch(slot("reveal", "crinkle"), 4000...9000, duration: 0.25, rate: 160, rateEnd: 20, q: 1, grain: 0.0015,
                        gain: 0.04),
            ], haptics: [.tap(0.2, 0.7), .tap(0.15, 0.7, at: 0.08), .tap(0.1, 0.7, at: 0.17)])
        }
    }
}
