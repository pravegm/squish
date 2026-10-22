import Foundation

/// Every tunable number in the press. Defaults come from design/SQUISH-DESIGN-BIBLE.md (§6);
/// values marked [tune] there are adjusted live in the Tuning Lab and persisted here.
struct PressConfig: Codable, Equatable, Sendable {
    // Angle → press mapping (design/FOLD-PRESS.md §4.1; supersedes bible §6.2 on Duo).
    // Contact floats with the arm angle; the visual flat is absolute.
    var armAngleMax: Double = 168
    /// Arming at ≥ 130° guarantees every failure lands ≥ ~60°, while both halves are still visible.
    var armAngleMin: Double = 130
    var endAngle: Double = 48
    /// Base contact point; recomputed per press by `armed(at:)` when `floatingContact` is on.
    var contactT: Double = 0.30
    var easeExponent: Double = 1.7
    var hysteresis: Double = 4
    var floatingContact: Bool = true
    /// Contact happens at min(contactCeiling, θ0 − contactLead).
    var contactCeiling: Double = 132
    var contactLead: Double = 12

    // State machine (bible §6.3)
    var sealDepth: Double = 0.98
    var sealHold: Double = 0.15
    var revealAngle: Double = 120
    /// Sealed but never closed: reveal after the hinge has been still this long (seconds).
    var sealedRestReveal: Double = 1.5
    var ignoreInputAfterActivation: Double = 1.5
    var failureHushDelay: Double = 0.045

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

    /// The mapping for one press, captured at arm: contact floats with the start angle, the bottom never moves
    /// (FOLD-PRESS.md §4.1). The engine keeps this copy for the whole press so contactT never changes mid-press.
    func armed(at theta0: Double) -> PressConfig {
        guard floatingContact else { return self }
        var config = self
        let start = min(theta0, armAngleMax)
        let contact = min(contactCeiling, start - contactLead)
        let span = start - endAngle
        if span > 1 {
            config.contactT = clamp((start - contact) / span, 0.05, 0.6)
        }
        return config
    }

    private static let storageKey = "squish.pressConfig.v3"

    static func loadSaved() -> PressConfig {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let config = try? JSONDecoder().decode(PressConfig.self, from: data) else { return .standard }
        return config
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
