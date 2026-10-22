import Foundation

/// Scripted states for CI screenshots and UI review, read from the `-squishDemo` launch argument.
/// Format: `key=value;key;key=value`, e.g. `object=rubberDuck;depth=0.6` or `object=bubbleWrap;reveal`.
/// Values can't contain `;` (the separator), and ci/scenarios.txt can't hold `|` (its column separator).
/// Only active in DEBUG builds.
///
/// UI:
/// - `notoasts` hides achievement toasts (read by the UI; passed by every store-shot and Duo CI scenario).
///
/// Orientation (iPhone Duo):
/// - `orient=portrait` asks the window scene for portrait (`requestGeometryUpdate`) and keeps asking if the system
///   rotates back, so the Duo simulator (book pose by default) runs the tabletop layout: 669 × 951 pt, horizontal
///   fold. Logs `SQUISH-T orient portrait ok|failed|lost`. `orient=landscape` asks for book pose.
///
/// Store shots (FoldStoreShot.swift, FOLD-REVIEW-4 #1/#2), written to Documents/storeshot-<label>[-land|-69|-eye].png,
/// then `SQUISH-T storeshot <label> ok|failed` per shot and `SQUISH-T storeshot done` at the end:
/// - `foldsim=120,75;storeshot` shoots at every foldsim target once it is held; `storeshot=120` only at those listed.
/// - `duo;storeshot=112,75` (real Duo) shoots when the real hinge has settled within 3° of each listed angle.
/// - `fail` in the list (`storeshot=112,fail`) also shoots the hero, label `hero`: the first hold after the object
///   failed at or below `storeshotfailangle` (default 62°), with the caption, then the
///   before/after frame, label `pair`, against the angle shot nearest `storepair` (default 112°). Logs
///   `SQUISH-T storeshot failure seen` when the failure happens.
/// - `storeshotsize=` comma list of portrait | landscape | both | all | 69 (default portrait). On a Duo portrait and
///   landscape are the inner display (2007 × 2853 / 2853 × 2007) and `69` adds a 1320 × 2868 copy; elsewhere they are
///   the 6.9" sizes (1320 × 2868 / 2868 × 1320).
/// - `storeshotfold=<deg>` models the device at a fixed angle instead of the captured one.
/// - `storeshotcaption=<headline> / <sub-line>` and `paircaption=…` override the captions (`*word*` = highlight).
/// - `storeshotsplat=overlay` adds the store-shot-only 2D splat overlay (off by default: FoldAnvil sprays the real
///   droplets on the device, so the capture already has them); `storeshotbackdrop=sweep` uses the cooler Duo sweep;
///   `storeshotmodel=asLaid` stands a book capture like a book instead of laying it down as a laptop.
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
        tokens(key).compactMap { Double($0) }
    }
    /// A comma-separated list of words, e.g. `storeshot=112,fail` → ["112", "fail"]; empty for a bare flag.
    func tokens(_ key: String) -> [String] {
        (values[key] ?? "").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
    var object: ObjectKind? { values["object"].flatMap(ObjectKind.init(rawValue:)) }
}
