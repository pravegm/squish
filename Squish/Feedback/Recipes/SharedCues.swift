import Foundation

/// Cues shared across objects that still go through `CueBook` (so sound and haptic share their randomness):
/// the golden shimmer, the surprise flourishes and the settling creak.
enum SharedCues {
    /// Golden and surprise extras on top of the material reveal flourish and the fixed sting.
    static func reveal(_ context: FeedbackContext, dice: FeedbackDice) -> FeedbackCue {
        var cue = FeedbackCue()
        if context.variant.isGolden {
            cue.add(golden(dice))
        }
        if let surprise = context.variant.surprise {
            cue.add(self.surprise(surprise, dice: dice))
        }
        return cue
    }

    /// Golden variant: a sparkle at 6–12 kHz and a pentatonic shimmer (G6 C7 D7, all below the 2.5 kHz harsh band),
    /// landing just after the sting's last note.
    static func golden(_ dice: FeedbackDice) -> FeedbackCue {
        let slot = { (layer: String) in SoundSlot.press("golden", layer) }
        let start: Float = 0.45
        let sounds: [SoundLayer] = [
            .crunch(slot("sparkle"), 6000...12000, duration: 0.8, rate: 35, rateEnd: 8, q: 5, grain: 0.02,
                    gain: 0.06 * dice.level(), fade: 0.3, delay: start),
            .ring(slot("bell"), .bell, 1567.98, partials: 8, decay: 0.25, brightness: 0.5, gain: 0.05, delay: start,
                  seed: dice.seed32()),
            .tone(slot("g6"), 1567.98, duration: 0.3, attack: 0.002, decay: 0.08, gain: 0.045, delay: start),
            .tone(slot("c7"), 2093.0, duration: 0.3, attack: 0.002, decay: 0.08, gain: 0.045, delay: start + 0.07),
            .tone(slot("d7"), 2349.32, duration: 0.3, attack: 0.002, decay: 0.08, gain: 0.04, delay: start + 0.14),
        ]
        let haptics = dice.scatter(6, from: Double(start), over: 0.3, intensity: (0.2, 0.4), sharpness: 0.95...1.0)
        return FeedbackCue(sounds: sounds, haptics: haptics)
    }

    /// A tiny, distinct flourish per surprise, after the sting.
    static func surprise(_ surprise: Surprise, dice: FeedbackDice) -> FeedbackCue {
        let slot = { (layer: String) in SoundSlot("surprise.\(surprise.rawValue).\(layer)") }
        let t: Float = 0.6
        let th = Double(t)
        let p = dice.bodyPitch()
        switch surprise {
        case .megaBubble:
            // One fat, low pop.
            return FeedbackCue(sounds: [
                .noise(slot("snap"), .highPass, 6000, decay: 0.003, gain: 0.2, delay: t),
                .noise(slot("body"), .bandPass, 600 * p, q: 1.5, decay: 0.03, gain: 0.35, delay: t),
                .tone(slot("tock"), 170 * p, to: 90 * p, glide: 0.05, duration: 0.08, decay: 0.03, gain: 0.15, harmonics: 2, delay: t),
            ], haptics: [.tap(0.7, 0.5, at: th)])
        case .fruitPieces:
            // Three little ascending plips.
            return FeedbackCue(sounds: [
                .tone(slot("plip1"), 520 * p, to: 700 * p, glide: 0.03, duration: 0.05, decay: 0.02, gain: 0.07, delay: t),
                .tone(slot("plip2"), 660 * p, to: 880 * p, glide: 0.03, duration: 0.05, decay: 0.02, gain: 0.07, delay: t + 0.09),
                .tone(slot("plip3"), 780 * p, to: 1040 * p, glide: 0.03, duration: 0.05, decay: 0.02, gain: 0.07, delay: t + 0.18),
            ], haptics: [.tap(0.25, 0.3, at: th), .tap(0.25, 0.35, at: th + 0.09), .tap(0.3, 0.4, at: th + 0.18)])
        case .secondColourCore:
            // A woody two-tone "ta-ding".
            return FeedbackCue(sounds: [
                .ring(slot("ta"), .wood, 1046.5, partials: 4, decay: 0.08, gain: 0.09, delay: t, seed: dice.seed32()),
                .ring(slot("ding"), .wood, 1567.98, partials: 4, decay: 0.12, gain: 0.09, delay: t + 0.11, seed: dice.seed32()),
            ], haptics: [.tap(0.3, 0.6, at: th), .tap(0.4, 0.6, at: th + 0.11)])
        case .toyChick:
            // A squeaky-toy "cheep cheep" (a toy, not alive).
            return FeedbackCue(sounds: [
                .tone(slot("cheep1"), 1500 * p, to: 1900 * p, glide: 0.05, duration: 0.07, attack: 0.003, decay: 0.03,
                      gain: 0.06, harmonics: 2, delay: t),
                .tone(slot("cheep2"), 1550 * p, to: 1950 * p, glide: 0.05, duration: 0.07, attack: 0.003, decay: 0.03,
                      gain: 0.06, harmonics: 2, delay: t + 0.12),
            ], haptics: [.tap(0.3, 0.8, at: th), .tap(0.3, 0.8, at: th + 0.12)])
        case .doubleYolk:
            // Two soft bloops, the second answering the first.
            return FeedbackCue(sounds: [
                .tone(slot("bloop1"), 300 * p, to: 420 * p, glide: 0.06, duration: 0.09, decay: 0.03, gain: 0.08, delay: t),
                .tone(slot("bloop2"), 360 * p, to: 500 * p, glide: 0.06, duration: 0.09, decay: 0.03, gain: 0.08, delay: t + 0.14),
            ], haptics: [.tap(0.3, 0.1, at: th), .tap(0.3, 0.1, at: th + 0.14)])
        case .jamCentre:
            // A round, dry "blorp".
            return FeedbackCue(sounds: [
                .tone(slot("blorp"), 220 * p, to: 330 * p, glide: 0.08, duration: 0.14, decay: 0.05, gain: 0.1,
                      harmonics: 2, vibrato: 9, depth: 0.04, delay: t),
                .noise(slot("puff"), .lowPass, 700, attack: 0.004, decay: 0.03, gain: 0.06, delay: t),
            ], haptics: [.buzz(0.35, 0.1, at: th, duration: 0.14, attack: 0.03)])
        case .cherryFizz:
            // A bright fizz and a ding.
            return FeedbackCue(sounds: [
                .crunch(slot("fizz"), 5000...10000, duration: 0.5, rate: 300, rateEnd: 50, q: 1.5, grain: 0.001,
                        gain: 0.06, fade: 0.2, delay: t),
                .tone(slot("ding"), 1046.5, to: 1567.98, glide: 0.04, duration: 0.2, decay: 0.06, gain: 0.05, delay: t),
            ], haptics: dice.scatter(8, from: th, over: 0.4, intensity: (0.25, 0.08), sharpness: 0.9...1.0))
        case .rainbowCore:
            // A quick pentatonic glissando, C6 to C7.
            let run: [Float] = [1046.5, 1174.66, 1318.51, 1567.98, 1760.0, 2093.0]
            var sounds: [SoundLayer] = []
            for (index, frequency) in run.enumerated() {
                sounds.append(.tone(slot("run\(index)"), frequency, duration: 0.12, attack: 0.002, decay: 0.04,
                                    gain: 0.04, delay: t + Float(index) * 0.035))
            }
            return FeedbackCue(sounds: sounds,
                               haptics: [.tap(0.2, 0.7, at: th), .tap(0.25, 0.8, at: th + 0.07), .tap(0.3, 0.9, at: th + 0.14)])
        case .messageInABottle:
            // Cork pop, then a paper rustle.
            return FeedbackCue(sounds: [
                .tone(slot("cork"), 600 * p, to: 900 * p, glide: 0.02, duration: 0.04, decay: 0.012, gain: 0.1, delay: t),
                .noise(slot("corkpuff"), .bandPass, 1800, q: 1.2, decay: 0.008, gain: 0.12, delay: t),
                .crunch(slot("paper"), 2000...6000, duration: 0.3, rate: 90, rateEnd: 30, q: 1, grain: 0.003,
                        gain: 0.04, fade: 0.4, delay: t + 0.12),
            ], haptics: [.tap(0.4, 0.6, at: th), .buzz(0.15, 0.7, at: th + 0.12, duration: 0.3)])
        }
    }

    /// The settling creak while the press is held under load (bible §7 "Holding still").
    static func settle(_ beds: MaterialBeds, dice: FeedbackDice) -> FeedbackCue {
        let pitch = beds.creakPitch * dice.grainPitch()
        let amount = max(beds.creakAmount, 0.2)
        return FeedbackCue(sounds: [
            .tone(.press("settle", "creak"), 170 * pitch, to: 160 * pitch, glide: 0.08, duration: 0.09, attack: 0.004,
                  decay: 0.03, gain: 0.03 * amount * dice.level(), harmonics: 6),
            .noise(.press("settle", "grit"), .bandPass, 380 * pitch, q: 4, decay: 0.03, gain: 0.025 * amount),
        ], haptics: [.tap(0.15, 0.4)])
    }
}
