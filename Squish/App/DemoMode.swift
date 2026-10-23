import Foundation

/// Scripted states for CI screenshots and UI review, read from the `-squishDemo` launch argument.
/// Format: `key=value;key;key=value`, e.g. `object=rubberDuck;depth=0.6` or `object=bubbleWrap;reveal`.
/// Values can't contain `;` (the separator), and ci/scenarios.txt can't hold `|` (its column separator).
/// Only active in DEBUG builds.
///
/// Scripted presses (`depth=<0…1>`, `reveal`) log `SQUISH-T demo press done … phase= depth= c= fractures= failed=
/// failureIndex= kind=` when the ram has reached the target, and with `reveal` also `SQUISH-T demo reveal up …
/// revealed=1 kind= fractures= failed= golden= surprise=` (or `… reveal missing after 20s … revealed=0`). ci/screenshots.sh
/// checks the P-frames against these fields (FOLD-REVIEW-7 N2, the 5th column of ci/scenarios.txt).
///
/// UI:
/// - `notoasts` hides achievement toasts (read by the UI; passed by every store-shot and Duo CI scenario).
/// - `gamecenter=hidden` hides the Game Center row's "NOT AVAILABLE" status in Settings (read by SettingsView,
///   `GameCenterRowDemo`; FOLD-REVIEW-6 N5). Passed by the Duo settings frame (07) and P6.
///
/// Settings state (PressDirector.applyDemoSettings, FOLD-REVIEW-6 N5; in memory only, never saved), so a settings
/// frame shows what its caption says:
/// - `soundstyle=workshop|soft`, `haptics=off|soft|full`, `captions=on|off`, `nofold` (= `nofold=on`, Press without
///   folding; `nofold=off`). Logs `SQUISH-T demo settings … (not saved)`.
///
/// Variant: `seed=<int>` pins the press seed (crack pattern, fracture jitter, Golden and surprise rolls). The store
/// passes use `seed=3`: plain (not Golden, no surprise) for every object, and the can sprays lime (scratchpad
/// r7tools/variant.mjs replicates PressVariant); `golden` / `surprise=<name>` force them.
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
///   The pair's labels quote each device's crown readout ("111°", then "AT 83°" once it froze at the failure), never
///   the model angle, and each gets a side-profile V glyph at the modelled angle (FOLD-REVIEW-5 §3 a, c).
/// - `reveal` in the list (`storeshot=112,fail,reveal`, Duo only) shoots the tabletop reveal, label `reveal`: once the
///   reveal card is up and the hinge is still at ≥ 120° (the script closes to 0° and reopens), with the window's
///   SwiftUI chrome (print label, Again · Share · Next) and the caption "Open up. File the *evidence*.".
/// - `storegrid=glassBottle,sodaCan,cakeSlice,jelly` (with `duo`) writes the variety frame storeshot-grid.png from the
///   heroes earlier tabletop passes saved to Documents (`storehalves-<kind>-*`); no hinge needed. Logs
///   `SQUISH-T storeshot grid ok|failed` and `SQUISH-T storeshot done`.
/// - `storeshotfold=<deg>` models the device at a fixed angle instead of the captured one.
/// - `storeshotazimuth=<deg>` turns the eye for the hero, the pair's large device and the grid (default per hero,
///   FOLD-REVIEW-6 #1/N7: duck 50°, glass −28°, others 32°; the pair and grid 32°); `storepairazimuth=` for the pair's
///   small device (default 24°); `revealazimuth=` for the reveal (default 14°). Angle shots keep 14°.
/// - `storeshotelevation=<deg>` the hero's eye elevation (default duck 22°, others 34°); `storeshotkeytilt=<deg>` the
///   hero's key-light tilt toward the viewer, so the lid's shadow lands on the object (default 18°). The hero is never
///   modelled below 58° (the inner display is dark from ~55°), carries the readout label and V glyph ("AT 67°"), and
///   hangs from the caption band. `storeshotbleed=<fraction>` the hero's width-fit bleed (default 0.10; glass 0.04
///   so its hinge spine stays in frame, FOLD-REVIEW-7 §3 A 04).
/// - `revealelevation=<deg>` the reveal's eye elevation (default 42°, FOLD-REVIEW-7 N4). The reveal is width-fitted
///   with no bleed and centred under the caption, so the whole near-flat device is in frame.
/// - `storeshotcaption=<headline> / <sub-line>` (hero; default per object, FOLD-REVIEW-5 N3), `paircaption=…`,
///   `revealcaption=…` and `gridcaption=…` override the captions (`*word*` = highlight).
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
