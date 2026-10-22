import Foundation

/// Scripted states for CI screenshots and UI review, read from the `-squishDemo` launch argument.
/// Format: `key=value;key;key=value`, e.g. `object=rubberDuck;depth=0.6` or `object=bubbleWrap;reveal`.
/// Only active in DEBUG builds.
///
/// Store shots (FoldStoreShot.swift, written to Documents/storeshot-<angle>[-land|-eye].png, then
/// `SQUISH-T storeshot <angle> ok|failed` per shot and `SQUISH-T storeshot done` at the end):
/// - `foldsim=120,75;storeshot` shoots at every foldsim target once it is held; `storeshot=120` only at those listed.
/// - `duo;storeshot=120,75` (real Duo) shoots when the real hinge has settled within 3° of each listed angle.
/// - `storeshotsize=portrait|landscape|both` (default portrait), `storeshotfold=<deg>` models the device at a fixed
///   angle instead of the captured one.
struct DemoScenario {
    var name: String
    var values: [String: String]

    static let current: DemoScenario? = {
        #if DEBUG
        guard let raw = UserDefaults.standard.string(forKey: "squishDemo"), !raw.isEmpty else { return nil }
        var values: [String: String] = [:]
        for part in raw.split(separator: ";") {
            let pieces = part.split(separator: "=", maxSplits: 1).map(String.init)
            values[pieces[0]] = pieces.count > 1 ? pieces[1] : ""
        }
        return DemoScenario(name: raw, values: values)
        #else
        return nil
        #endif
    }()

    func has(_ key: String) -> Bool { values[key] != nil }
    func string(_ key: String) -> String? { values[key] }
    func double(_ key: String) -> Double? { values[key].flatMap(Double.init) }
    /// A comma-separated list, e.g. `storeshot=120,75` → [120, 75]; empty for a bare flag or a missing key.
    func doubles(_ key: String) -> [Double] {
        (values[key] ?? "").split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    }
    var object: ObjectKind? { values["object"].flatMap(ObjectKind.init(rawValue:)) }
}
