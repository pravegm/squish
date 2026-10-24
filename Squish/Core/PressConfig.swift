import Foundation

/// Every tunable number in the press. Defaults come from design/SQUISH-DESIGN-BIBLE.md (§6);
/// values marked [tune] there are adjusted live in the Tuning Lab and persisted here.
struct PressConfig: Codable, Equatable, Sendable {
    // Angle → press mapping (design/FOLD-PRESS.md §4.1; supersedes bible §6.2 on Duo).
    // Contact floats with the arm angle; the visual flat is absolute.
    //
    // ⚠️ PROVISIONAL FOLD VALUES (24 Oct 2026, design/EXPERIENCE-PLAN.md decision 3). `contactCeiling` and
    // `easeExponent` below drive the iPhone Duo fold. They moved contact from 132° to 106° and made compression linear
    // in θ (θ = 106 − 58·c), so the squash starts where the real lid is visibly near the object and every big failure
    // lands at ~94–64° (worst-case jitter ≥ `PressFeel.failureFloorAngle` 62°), while the inner display is still lit (it
    // turns off below ~55°). The old 132° contact squashed the object with the lid still ~50° away.
    // NO REAL-DUO HINGE SAMPLES EXIST YET: these are guesses from the UX audit (UX-AUDIT-2 §3.3: contact ~110–100°,
    // failure ~80–65°). Re-tune contactCeiling, easeExponent and endAngle from the founder's Tuning Lab hinge log
    // (Settings → long-press Version): the real display-off angle, sample rate and latency.
    // The touch press (P-48) keeps its 1.0 mapping: `touchContactCeiling`, `touchEaseExponent`.
    var armAngleMax: Double = 168
    /// Arming at ≥ 130° guarantees every failure lands ≥ ~60°, while both halves are still visible. (With the
    /// provisional fold contact at 106° the failures no longer depend on the arm angle at all.)
    var armAngleMin: Double = 130
    var endAngle: Double = 48
    /// Base contact point; recomputed per press by `armed(at:)` when `floatingContact` is on.
    var contactT: Double = 0.30
    /// PROVISIONAL (fold): 1 = compression linear in θ after contact. Was 1.7; the "lag, then give" resistance
    /// (`PressResistance`) now does the shaping, render side.
    var easeExponent: Double = 1.0
    var hysteresis: Double = 4
    var floatingContact: Bool = true
    /// Contact happens at min(contactCeiling, θ0 − contactLead). PROVISIONAL (fold): 106°, was 132°.
    var contactCeiling: Double = 106
    var contactLead: Double = 12

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

    // Hinge filtering and render smoothing (bible §6.1)
    var oneEuroMinCutoff: Double = 1.2
    var oneEuroBeta: Double = 0.04
    var oneEuroDCutoff: Double = 1.0
    var springOmega: Double = 22
    var maxPredict: Double = 0.05
    var staleAfter: Double = 0.08

    // Feel (user-facing sound/haptics settings live in AppSettings)
    var slamSpeed: Double = 250
    var perfectMaxSpeed: Double = 100

    static let standard = PressConfig()

    /// The touch press (P-48) keeps the 1.0 mapping its store frames and CI expectations were made on: contact at
    /// min(132°, θ0 − 12°) on the virtual hinge, ease 1.7. Not Codable fields, so saved tunings keep decoding.
    static let touchContactCeiling = 132.0
    static let touchEaseExponent = 1.7

    /// The mapping for one press, captured at arm: contact floats with the start angle, the bottom never moves
    /// (FOLD-PRESS.md §4.1). The engine keeps this copy for the whole press so contactT never changes mid-press.
    /// `hinge`: a real fold (the provisional fold values above); false (the default, as every caller before the
    /// provisional fold values assumed) is the touch press's 1.0 mapping.
    func armed(at theta0: Double, hinge: Bool = false) -> PressConfig {
        var config = self
        if !hinge {
            config.contactCeiling = Self.touchContactCeiling
            config.easeExponent = Self.touchEaseExponent
        }
        guard floatingContact else { return config }
        let start = min(theta0, armAngleMax)
        let contact = min(config.contactCeiling, start - contactLead)
        let span = start - endAngle
        if span > 1 {
            config.contactT = clamp((start - contact) / span, 0.05, 0.6)
        }
        return config
    }

    /// v4 (24 Oct 2026): the provisional fold mapping. A v3 tuning carried the old 132° contact explicitly, which
    /// would have hidden the move, so it is dropped once.
    private static let storageKey = "squish.pressConfig.v4"

    static func loadSaved() -> PressConfig {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return .standard }
        return decodeLeniently(data) ?? .standard
    }

    /// Decodes a saved tuning; keys it lacks (a field added after it was saved) take their defaults instead of the
    /// whole tuning silently resetting (the old CLAUDE.md gotcha). Unknown keys are ignored.
    static func decodeLeniently(_ data: Data) -> PressConfig? {
        if let config = try? JSONDecoder().decode(PressConfig.self, from: data) { return config }
        guard let saved = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let base = try? JSONEncoder().encode(PressConfig.standard),
              var merged = (try? JSONSerialization.jsonObject(with: base)) as? [String: Any] else { return nil }
        for (key, value) in saved where merged[key] != nil {
            merged[key] = value
        }
        guard let data = try? JSONSerialization.data(withJSONObject: merged) else { return nil }
        return try? JSONDecoder().decode(PressConfig.self, from: data)
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
