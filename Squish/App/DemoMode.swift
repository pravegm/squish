import Foundation

/// Scripted states for CI screenshots and UI review, read from the `-squishDemo` launch argument.
/// Format: `key=value;key;key=value`, e.g. `object=rubberDuck;depth=0.6` or `object=bubbleWrap;reveal`.
/// Only active in DEBUG builds.
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
    var object: ObjectKind? { values["object"].flatMap(ObjectKind.init(rawValue:)) }
}
