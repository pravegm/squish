import Foundation
import UIKit

#if DEBUG
/// CI verify frames that need exact timing (a toast is up for 3 s; the scripts see log lines late): the app writes
/// its own key window, SwiftUI overlays included, to Documents/<name>.png.
@MainActor enum DemoCapture {
    /// `nocapture` (ci/marketing.sh): no self-captures, whose `drawHierarchy` would hitch a screen recording.
    static let enabled: Bool = DemoScenario.current?.has("nocapture") != true

    /// Appends `<name> epoch=<unix s> t=0` to Documents/<file> (ci/marketing.sh reads it beside preview-marks.txt,
    /// on the same wall clock as `simctl io recordVideo`).
    static func mark(_ name: String, file: String) {
        guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = directory.appendingPathComponent(file)
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let line = String(format: "%@ epoch=%.3f t=0\n", name, Date().timeIntervalSince1970)
        try? (existing + line).write(to: url, atomically: true, encoding: .utf8)
        print("SQUISH-T mark \(name) (\(file))")
    }

    static func window(_ name: String) {
        guard enabled else { return }
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows).first(where: \.isKeyWindow) else {
            print("SQUISH-T capture \(name) failed: no key window")
            return
        }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        guard let data = image.pngData(),
              let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        do {
            try data.write(to: directory.appendingPathComponent("\(name).png"))
            print("SQUISH-T capture \(name) ok \(Int(window.bounds.width))x\(Int(window.bounds.height))")
        } catch {
            print("SQUISH-T capture \(name) failed: \(error.localizedDescription)")
        }
    }
}
#endif

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
///   `GameCenterRowDemo`; FOLD-REVIEW-6 N5). Passed by the Duo settings frame (07) and P5 (P6 until R8).
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
/// App Preview capture (PressDirector "Preview-video hooks"; ci/preview.sh and ci/preview-duo.sh, .github/workflows/
/// preview.yml; docs/appstore/preview-video.md):
/// - `slowpress[=seconds]` (default 5, with `depth=` or `reveal`, touch press only): a human-paced press instead of the
///   linear 1.5 s one: 0.35 s lead-in, ease onto the object, slow squeeze, a ~1 s hold at depth 0.52–0.535 (just short
///   of the glass and duck failures at seed 3), then an ease through to the target, held 0.75 s. Paced on the wall
///   clock, monotonic, under `perfectMaxSpeed`. Logs `SQUISH-T demo slowpress <s>s begins at …`.
/// - `pressaudio` (touch press, or `duo` with the CI script driving the hinge): writes Documents/preview-marks.txt
///   (`<name> epoch=<unix s> t=<s>` per line: `origin` = the object's placement, then `phase-<phase>`, `fracture-<n>`,
///   `failure`, `closed`/`opened`, `reveal`), and 8 s after the reveal is up (so the render never stalls a recorded
///   reveal) re-renders the press's own sound offline from its trace (OfflineAudio, as the share clip does, but at
///   rate 1) into Documents/press-audio.wav (48 kHz mono, sample 0 = `origin`) and press-audio.txt (`origin=<epoch>
///   seconds= rate= kind= style=`). The simulator shares the host clock, so the script lines the WAV up with
///   `simctl io recordVideo`. Logs `SQUISH-T preview marks origin epoch=…` and `SQUISH-T pressaudio ok|failed …`.
///   `previewmarks` writes the marks file only (the shelf segment: `origin` is ~when RootView's demo timer starts).
/// - `prewarm` (touch press, with `depth=` or `reveal`): a quick press of the same object to its reveal, then Again, before
///   the scripted press, so the first-use render stall of the object's cracks (0.5–0.9 s on the CI simulator) happens
///   off the record. The marks start after it (`origin` = the recorded take). Logs `SQUISH-T demo prewarm done …`.
/// - `hingescript[=seconds]` (with `duo`, default 7): the Duo preview's press, fed through the director's hinge input at
///   60 Hz while the simulated Duo lies open (the simulator's `hinge` CLI can't hold a steady sweep): once the tabletop
///   layout is up, close 180° → 58° on the `slowpress` pacing, hold, on to 44° until it seals (out of shot: a real inner
///   display is dark there), reopen to 160° (the reveal). Writes Documents/preview-script.txt (`script-begin|58|sealed|
///   reopen|160 epoch=…`) and logs `SQUISH-T hingescript <step> at …`.
/// - Marketing capture (ci/marketing.sh, .github/workflows/marketing.yml, docs/marketing/ASSETS.md):
///   - `nocoach` hides the first-run coach line (RootView `PressCoachSlot`) and the first presses' forced captions
///     (captions then follow the setting: pass `captions=off`), `nocapture` turns off the app's own
///     window captures (`DemoCapture.window`) so nothing hitches a recording.
///   - `slowcurve=steady` (touch `slowpress`) and `hingecurve=steady` (`hingescript`): one even squeeze with no
///     hold, for the bubble-wrap ASMR take. `hingescript` with `orient=landscape` presses in book pose.
///   - `slomo` also writes Documents/slomo-marks.txt (`slomo-key`, `slomo-begin`, `slomo-end`); `pressaudiodelay=<s>`
///     (default 8) waits longer before the offline sound render, so it never stalls the film.
///   - `shelffill[=seconds]` (with `shelf`): the shelf opens empty and the nine open objects are filed one by one (never
///     the secret ball), every `seconds` (default 0.8), writing Documents/shelffill-marks.txt (`shelffill-begin`, `shelffill-<n>`,
///     `shelffill-done`).
/// - Also used by the preview: `object=`, `reveal`, `seed=3`, `notoasts`, `shelf` (UI key, RootView: opens the shelf
///   1.2 s after launch with the seeded collection), `duo`, `orient=portrait`.
///
/// Orientation (iPhone Duo):
/// - `orient=portrait` asks the window scene for portrait (`requestGeometryUpdate`) and keeps asking if the system
///   rotates back, so the Duo simulator (book pose by default) runs the tabletop layout: 669 × 951 pt, horizontal
///   fold. Logs `SQUISH-T orient portrait ok|failed|lost`. `orient=landscape` asks for book pose.
/// - With a Fold Press stage, "ok" waits for its canvas to follow. With none (`nofold`, the settings frame;
///   FOLD-REVIEW-8 N1) the interface orientation is not enough: the key window's bounds and the screen's bounds must
///   also have the wanted shape (portrait: taller than wide) for 5 s, else it logs `orient portrait pending … window=
///   screen=` once and keeps asking. Every ok / failed / lost line carries `interface= window=<WxH> screen=<WxH>`
///   (points).
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
///   so its hinge spine stays in frame, FOLD-REVIEW-7 §3 A 04). Whatever the bleed, the device stays
///   `storeshotinset=<fraction>` of the frame width inside each side edge (default 0.02; negative = no clamp, the R8
///   fit), so the duck hero no longer loses its base corner at x 0 (FOLD-REVIEW-8 N5).
/// - Every store-shot line (angle shots, hero, reveal, pair, grid) ends `frame=<x0-x1/y0-y1>[;…] inframe=0|1`: the
///   projected device bounds in output pixels of the store frame, and whether every device lies inside it.
///   ci/store-set.sh FLAGS a Duo frame whose line says `inframe=0` (or has no `inframe=`).
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
        // CI redirects stdout to a file, which makes it fully buffered: the scripts then see SQUISH-T lines seconds
        // late (the R9 toast check shot 8 s after "reveal lit" instead of 2.5 s). Line-buffer it for demo runs.
        setvbuf(stdout, nil, _IOLBF, 0)
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
