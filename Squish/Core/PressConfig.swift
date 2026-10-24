import Foundation

/// Every tunable number in the press. Defaults come from design/SQUISH-DESIGN-BIBLE.md (§6);
/// values marked [tune] there are adjusted live in the Tuning Lab and persisted here.
struct PressConfig: Codable, Equatable, Sendable {
    // Angle → press mapping (design/FOLD-PRESS.md §4.1; supersedes bible §6.2 on Duo).
    // Contact floats with the arm angle; the visual flat is absolute.
    //
    // ⚠️ PROVISIONAL FOLD VALUES (25 Oct 2026). `contactCeiling` ("contact angle": the squash starts) and `endAngle`
    // ("fully crushed angle") drive the iPhone Duo fold, linear in θ between them (θ = 100 − 50·c). Every big failure
    // lands at ~90–64° (worst-case jitter ≥ `PressFeel.failureFloorAngle`). The founder's first hinge log (25 Oct) gave
    // the report rate (25–30 Hz moving, 100–200 ms gaps) and the `.closed` posture (set at ~85°, cleared at ~21°), but
    // NOT the display-off angle: drag these in the Tuning Lab ("Contact angle", "Fully crushed angle", "Display-off
    // angle") on the device and send the values back. The crush should complete before the real display-off point.
    // The touch press (P-48) keeps its 1.0 mapping: `touchContactCeiling`, `touchEaseExponent`, `touchEndAngle`.
    var armAngleMax: Double = 168
    /// Arming at ≥ 130°: the failures no longer depend on the arm angle (contact ≤ θ0 − 12° stays at contactCeiling).
    var armAngleMin: Double = 130
    /// "Fully crushed angle" (fold). PROVISIONAL: 50°, just above the assumed ~55° display-off… tune on device.
    var endAngle: Double = 50
    /// Base contact point; recomputed per press by `armed(at:)` when `floatingContact` is on.
    var contactT: Double = 0.30
    /// 1 = compression linear in θ after contact (fold). The touch press keeps 1.7.
    var easeExponent: Double = 1.0
    var hysteresis: Double = 4
    var floatingContact: Bool = true
    /// "Contact angle" (fold): contact happens at min(contactCeiling, θ0 − contactLead). PROVISIONAL: 100°.
    var contactCeiling: Double = 100
    var contactLead: Double = 12

    // The hinge posture (founder's real-Duo log, 25 Oct 2026; FOLD-PRESS §9.8). `.closed` is a coarse posture with
    // big hysteresis (set at ~85° closing, cleared at ~21° opening), not "shut": these angles decide instead.
    /// Shut: at or below this angle the phone is really closed (the blind seal, the ka-chunk, the cover).
    var shutAngle: Double = 12
    /// A sealed press reveals once a reopen passes this angle (or the inner display is back).
    var revealOpenAngle: Double = 25
    /// The inner display goes dark below about this angle (the reveal beats wait for it). UNMEASURED on hardware.
    var displayOffAngle: Double = 55

    // State machine (bible §6.3)
    var sealDepth: Double = 0.98
    var sealHold: Double = 0.15
    var revealAngle: Double = 120
    /// Sealed but never closed: reveal after the hinge has been still this long (seconds).
    var sealedRestReveal: Double = 1.5
    var ignoreInputAfterActivation: Double = 1.5
    /// Break part 1, the hush (s), kept inside 50–80 ms (`BreakScore.of`). The burst follows hush + the material's
    /// hit stop after the crossing.
    var failureHushDelay: Double = 0.065

    // Hinge filtering and render smoothing (bible §6.1). Sync fix (25 Oct 2026): the drawn hinge is
    // `HingeTracker` (continuous between reports, ~0 lag at a steady speed); the One-Euro filter now only feeds the
    // events, retuned for low lag (0.5° behind at 20°/s, was 1.0–1.4°). The spring only smooths jumps.
    var oneEuroMinCutoff: Double = 2.0
    var oneEuroBeta: Double = 0.12
    var oneEuroDCutoff: Double = 1.5
    var springOmega: Double = 40
    var maxPredict: Double = 0.05
    var staleAfter: Double = 0.08

    // Feel (user-facing sound/haptics settings live in AppSettings)
    var slamSpeed: Double = 250
    var perfectMaxSpeed: Double = 100

    static let standard = PressConfig()

    /// The touch press (P-48) keeps the 1.0 mapping its store frames and CI expectations were made on: contact at
    /// min(132°, θ0 − 12°) on the virtual hinge, ease 1.7, flat at 48°.
    static let touchContactCeiling = 132.0
    static let touchEaseExponent = 1.7
    static let touchEndAngle = 48.0

    /// The mapping for one press, captured at arm: contact floats with the start angle, the bottom never moves
    /// (FOLD-PRESS.md §4.1). The engine keeps this copy for the whole press so contactT never changes mid-press.
    /// `hinge`: a real fold (the provisional fold values above); false (the default, as every caller before the
    /// provisional fold values assumed) is the touch press's 1.0 mapping.
    func armed(at theta0: Double, hinge: Bool = false) -> PressConfig {
        var config = self
        if !hinge {
            config.contactCeiling = Self.touchContactCeiling
            config.easeExponent = Self.touchEaseExponent
            config.endAngle = Self.touchEndAngle
        }
        guard floatingContact else { return config }
        let start = min(theta0, armAngleMax)
        let contact = min(config.contactCeiling, start - contactLead)
        let span = start - config.endAngle
        if span > 1 {
            config.contactT = clamp((start - contact) / span, 0.05, 0.6)
        }
        return config
    }

    /// v5 (25 Oct 2026): the sync fix and the real-Duo posture. A v4 tuning carried the old filter and mapping
    /// explicitly, which would have hidden the fix, so it is dropped once.
    private static let storageKey = "squish.pressConfig.v5"

    static func loadSaved() -> PressConfig {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return .standard }
        return decodeLeniently(data) ?? .standard
    }

    /// Decodes a saved tuning; keys it lacks (a field added after it was saved) take their defaults instead of the
    /// whole tuning silently resetting (the old CLAUDE.md gotcha). Unknown keys are ignored.
    static func decodeLeniently(_ data: Data) -> PressConfig? {
        try? JSONDecoder().decode(PressConfig.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    func prettyJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Lenient decoding everywhere (saved tunings and the configs inside saved press traces): a key the data lacks takes
/// its default, unknown keys are ignored. So adding a tunable never resets a tuning or loses a share clip. In an
/// extension, so the default `init()` stays.
extension PressConfig {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var d = PressConfig()
        func read<T: Decodable>(_ key: CodingKeys, _ value: inout T) {
            if let v = try? c.decodeIfPresent(T.self, forKey: key) { value = v }
        }
        read(.armAngleMax, &d.armAngleMax)
        read(.armAngleMin, &d.armAngleMin)
        read(.endAngle, &d.endAngle)
        read(.contactT, &d.contactT)
        read(.easeExponent, &d.easeExponent)
        read(.hysteresis, &d.hysteresis)
        read(.floatingContact, &d.floatingContact)
        read(.contactCeiling, &d.contactCeiling)
        read(.contactLead, &d.contactLead)
        read(.shutAngle, &d.shutAngle)
        read(.revealOpenAngle, &d.revealOpenAngle)
        read(.displayOffAngle, &d.displayOffAngle)
        read(.sealDepth, &d.sealDepth)
        read(.sealHold, &d.sealHold)
        read(.revealAngle, &d.revealAngle)
        read(.sealedRestReveal, &d.sealedRestReveal)
        read(.ignoreInputAfterActivation, &d.ignoreInputAfterActivation)
        read(.failureHushDelay, &d.failureHushDelay)
        read(.oneEuroMinCutoff, &d.oneEuroMinCutoff)
        read(.oneEuroBeta, &d.oneEuroBeta)
        read(.oneEuroDCutoff, &d.oneEuroDCutoff)
        read(.springOmega, &d.springOmega)
        read(.maxPredict, &d.maxPredict)
        read(.staleAfter, &d.staleAfter)
        read(.slamSpeed, &d.slamSpeed)
        read(.perfectMaxSpeed, &d.perfectMaxSpeed)
        self = d
    }
}
