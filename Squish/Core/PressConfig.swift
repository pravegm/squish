import Foundation

/// Every tunable number in the press. Defaults come from design/SQUISH-DESIGN-BIBLE.md (§6);
/// values marked [tune] there are adjusted live in the Tuning Lab and persisted here.
struct PressConfig: Codable, Equatable, Sendable {
    // Angle → press mapping (bible §6.2)
    var armAngleMax: Double = 165
    var armAngleMin: Double = 100
    var endAngle: Double = 60
    var contactT: Double = 0.20
    var easeExponent: Double = 1.6
    var hysteresis: Double = 4

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

    private static let storageKey = "squish.pressConfig.v2"

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
