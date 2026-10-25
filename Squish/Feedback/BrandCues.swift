import Foundation

/// Shared press sounds and the fixed brand set (bible §8, 02 §4). Brand cues are never randomised: they are the logo.
/// Everything tuned sits on one C major pentatonic, so ticks, sting, chime and fanfare form one musical system.
enum BrandCues {
    /// C major pentatonic from C5: the gauge ticks climb it as pressure builds (02 §7.2: note = pentatonic[floor(c·10)]).
    static let pentatonic: [Float] = [523.25, 587.33, 659.25, 783.99, 880.0, 1046.5, 1174.66, 1318.51, 1567.98, 1760.0, 2093.0]

    // Pitches used by the brand set.
    private static let c5: Float = 523.25
    private static let d5: Float = 587.33
    private static let e5: Float = 659.25
    private static let g5: Float = 783.99
    private static let c6: Float = 1046.5
    private static let e6: Float = 1318.51
    private static let g6: Float = 1567.98

    /// One gauge tick: a small mechanical click plus a short tuned "tink".
    static func tick(_ frequency: Float, gain: Float = 1) -> FeedbackCue {
        FeedbackCue(sounds: [
            .noise(.press("tick", "click"), .bandPass, 4000, q: 1.5, attack: 0.0003, decay: 0.002, gain: 0.07 * gain),
            .tone(.press("tick", "tink"), frequency, duration: 0.06, attack: 0.001, decay: 0.015, gain: 0.06 * gain),
        ])
    }

    /// Contact thud shared by every object (the material contact comes from the recipe).
    static let contact = FeedbackCue(sounds: [
        .tone(.press("contact", "thock"), 160, to: 90, glide: 0.06, duration: 0.1, decay: 0.03, gain: 0.26, harmonics: 3),
        .noise(.press("contact", "click"), .bandPass, 2500, decay: 0.003, gain: 0.07),
    ])

    /// Visual bottom-out at 60° (bible §2 "two beats", beat a). Heavy but below the ka-chunk.
    static let bottomOut = FeedbackCue(
        sounds: [
            .tone(.press("bottom", "thump"), 95, to: 45, glide: 0.12, duration: 0.2, attack: 0.002, decay: 0.06, gain: 0.38, harmonics: 3),
            .noise(.press("bottom", "body"), .lowPass, 400, decay: 0.05, gain: 0.18),
        ],
        haptics: [
            .tap(0.9, 0.15),
            .buzz(0.75, 0.05, at: 0.005, duration: 0.14, decay: 0.11),
        ]
    )

    /// The unlatch on the reopen after a seal (the reveal): a latch click and a low clunk, under the release sigh.
    static let unlatch = FeedbackCue(
        sounds: [
            .noise(.press("unlatch", "click"), .highPass, 3200, attack: 0.0002, decay: 0.0025, gain: 0.16),
            .tone(.press("unlatch", "clunk"), 110, to: 70, glide: 0.05, duration: 0.14, attack: 0.001, decay: 0.035,
                  gain: 0.3, harmonics: 3, delay: 0.015),
            .noise(.press("unlatch", "body"), .lowPass, 700, decay: 0.025, gain: 0.14, delay: 0.015),
        ],
        haptics: [.tap(0.45, 0.8), .tap(0.75, 0.25, at: 0.015)]
    )

    /// Haptic weight under every failure (Duo test 1: "weak"): the recipe's break is mostly sharp transients, which
    /// read as a click. This adds the body: a full-strength low-sharpness hit, a 220 ms heavy rumble, and an aftershock.
    /// Played in the same pattern as the recipe's failure, so the 12 ms gap rule interleaves them instead of queueing.
    static let failureBody = FeedbackCue(
        haptics: [
            // EXPERIENCE-REVIEW-1 #2: contrast from a bigger peak. A full, low hit; a stacked second hit 25 ms later; a
            // long heavy body (110 ms at full, decaying over ~0.3 s); and the aftershock.
            .tap(1.0, 0.3),
            .tap(0.85, 0.22, at: 0.025),
            .buzz(1.0, 0.15, at: 0.004, duration: 0.3, decay: 0.19),
            .tap(0.7, 0.45, at: 0.12),
        ],
        isClimax: true
    )

    /// The ka-chunk (bible §3.1 beat 10): latch click, low thock, short steel body,
    /// then two quiet "ready" tinks with the two ready taps 1.5 s later.
    static let kaChunk = FeedbackCue(
        sounds: [
            .noise(.press("kachunk", "latch"), .highPass, 3800, attack: 0.0002, decay: 0.003, gain: 0.35),
            .noise(.press("kachunk", "latchbody"), .bandPass, 2200, q: 2, decay: 0.006, gain: 0.18),
            .tone(.press("kachunk", "thock"), 120, to: 38, glide: 0.15, duration: 0.32, attack: 0.001, decay: 0.08,
                  gain: 0.75, harmonics: 3, delay: 0.028),
            .noise(.press("kachunk", "body"), .lowPass, 900, decay: 0.035, gain: 0.35, delay: 0.028),
            .ring(.press("kachunk", "steel"), .steel, 260, partials: 8, decay: 0.1, brightness: 0.4, gain: 0.12, delay: 0.03, seed: 7),
            .tone(.press("kachunk", "ready1"), c6, duration: 0.09, attack: 0.002, decay: 0.03, gain: 0.04, delay: 1.5),
            .tone(.press("kachunk", "ready2"), g6, duration: 0.09, attack: 0.002, decay: 0.03, gain: 0.04, delay: 1.62),
        ],
        haptics: [
            // "Ka": the latch, crisp. "Chunk": the full-weight thock with a solid low body (Duo test 1: make it solid).
            .tap(0.6, 0.85, at: 0),
            .tap(1.0, 0.2, at: 0.028),
            .tap(0.85, 0.2, at: 0.053),
            .buzz(1.0, 0.05, at: 0.033, duration: 0.22, decay: 0.17),
            .tap(0.35, 0.4, at: 1.5),
            .tap(0.35, 0.4, at: 1.62),
        ],
        isClimax: true
    )

    /// Fixed reveal sting: C5 E5 G5, with three soft taps in rhythm (02 §7.1 phase 8).
    static let sting = FeedbackCue(
        sounds: note(c5, at: 0, gain: 0.18, "sting", "c5") + note(e5, at: 0.16, gain: 0.18, "sting", "e5")
            + note(g5, at: 0.32, gain: 0.2, "sting", "g5"),
        haptics: [.tap(0.3, 0.5, at: 0), .tap(0.35, 0.5, at: 0.16), .tap(0.5, 0.5, at: 0.32)]
    )

    /// Fixed two-note answer to the sting, with the "success" double tap (01 §7.2).
    static let collect = FeedbackCue(
        sounds: note(g5, at: 0, gain: 0.16, "collect", "g5") + note(c6, at: 0.12, gain: 0.18, "collect", "c6"),
        haptics: [.tap(0.6, 0.6, at: 0), .tap(0.9, 0.4, at: 0.09)]
    )

    /// Fixed unlock fanfare: a quick pentatonic run up to C6, landing on a C6 + E6 dyad. About 1 s.
    static let unlock = FeedbackCue(sounds:
        note(c5, at: 0, gain: 0.12, "unlock", "c5", length: 0.25)
            + note(e5, at: 0.07, gain: 0.12, "unlock", "e5", length: 0.25)
            + note(g5, at: 0.14, gain: 0.13, "unlock", "g5", length: 0.25)
            + note(c6, at: 0.21, gain: 0.13, "unlock", "c6", length: 0.3)
            + note(c6, at: 0.32, gain: 0.12, "unlock", "dyad1", length: 0.8)
            + note(e6, at: 0.32, gain: 0.09, "unlock", "dyad2", length: 0.8)
    )

    /// The ticks resolve to the tonic on the failure (02 §4).
    static let tonic = FeedbackCue(sounds: [
        .tone(.press("tonic", "c5"), c5, duration: 0.5, attack: 0.003, decay: 0.15, gain: 0.06, harmonics: 2, delay: 0.02),
        .tone(.press("tonic", "c6"), c6, duration: 0.3, attack: 0.002, decay: 0.08, gain: 0.045, delay: 0.02),
    ])

    /// Release sigh: a gentle reversed-hiss exhale when the ram lifts (02 §4).
    static let releaseSigh = FeedbackCue(sounds: [
        .noise(.press("release", "sigh"), .bandPass, 2400, q: 0.7, attack: 0.06, decay: 0.15, gain: 0.045,
               sweepTo: 1400, sweepTime: 0.3),
    ])

    /// Soft marimba-ish note: fundamental plus a quick 4× partial.
    private static func note(_ frequency: Float, at delay: Float, gain: Float, _ event: String, _ layer: String,
                             length: Float = 0.6) -> [SoundLayer] {
        [
            .tone(.press(event, layer), frequency, duration: length, attack: 0.004, decay: length * 0.25, gain: gain,
                  harmonics: 2, delay: delay),
            .tone(.press(event, layer + ".tine"), frequency * 4, duration: 0.08, attack: 0.001, decay: 0.02,
                  gain: gain * 0.2, delay: delay),
        ]
    }
}
