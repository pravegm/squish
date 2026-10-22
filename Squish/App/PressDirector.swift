import Observation
import QuartzCore
import UIKit

/// Wires the press engine to the scene, haptics, audio and collection, and owns the per-frame loop.
/// The only object the UI talks to. Its public surface is the contract in design/ARCHITECTURE.md.
@MainActor
@Observable
final class PressDirector {
    let engine: PressEngine
    let settings: AppSettings
    let collection: CollectionStore
    @ObservationIgnored let scene = PressScene()
    @ObservationIgnored let haptics = HapticsController()
    @ObservationIgnored let audio = AudioController()
    @ObservationIgnored let hingeLog = HingeLog()
    /// The iPhone Duo presentation: the two screen halves are the plates (FOLD-PRESS.md). Drives the 2D platen
    /// half and the bezel; the 3D anvil half is `scene` in fold framing.
    @ObservationIgnored let fold = FoldPressController()

    private(set) var currentKind: ObjectKind = .bubbleWrap
    private(set) var variant = PressVariant(kind: .bubbleWrap, seed: 1)
    private(set) var hingeAvailable = false
    /// Latest raw hinge "closed" status, tracked even when pressing without folding.
    private(set) var hingeClosed = false
    /// Increments on every big failure; the UI flashes the top half of the screen.
    private(set) var failureFlashCount = 0
    /// The specimen being revealed (non-nil while the reveal card is up).
    private(set) var revealed: RecordOutcome?
    /// The latest onomatopoeia caption ("POP!"), for captions and VoiceOver.
    private(set) var caption: CaptionEvent?
    /// Hinge (or touch) samples of the last finished press, for the share-clip renderer.
    private(set) var lastTrace: PressTrace?
    /// A gentle one-line coaching hint ("Slowly… it's more satisfying."), shown as a toast by the UI.
    private(set) var coachHint: CaptionEvent?
    /// Set by the UI from the environment.
    var reduceMotion = false

    @ObservationIgnored private let traceStore = TraceStore()
    @ObservationIgnored private var lastSpecimenID: UUID?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var renderedFrames = 0
    @ObservationIgnored private let launchTime = CACurrentMediaTime()
    @ObservationIgnored private var lastHingeLogTime: Double = 0
    @ObservationIgnored private var foldSimulated = false
    /// Seed of the object last handed to Fold Press (nil = not loaded there yet).
    @ObservationIgnored private var foldVariantSeed: UInt64?
    @ObservationIgnored private var captionCounter = 0
    @ObservationIgnored private var traceSamples: [PressTrace.Sample] = []
    @ObservationIgnored private var traceStart: Double = 0
    @ObservationIgnored private var revealPeakAngle: Double = 0
    @ObservationIgnored private var consecutiveSlams = 0
    private static let lastObjectKey = "squish.lastObject"
    private static let slamHintsKey = "squish.slamHintsShown"

    init() {
        engine = PressEngine(config: .loadSaved())
        settings = AppSettings(defaultCaptions: UIAccessibility.isClosedCaptioningEnabled)
        collection = CollectionStore()
        engine.onEvent = { [weak self] event in self?.handle(event) }
    }

    // MARK: - Derived state for the UI

    var isShowingCover: Bool { hingeAvailable && hingeClosed }

    /// True when the touch press drives the engine (no hinge, or the user chose to press without folding).
    var usesTouchPress: Bool { !hingeAvailable || settings.pressWithoutFolding }

    /// True on iPhone Duo when folding drives the press: the screen halves become the plates. This is Squish.
    var usesFoldPress: Bool { hingeAvailable && !settings.pressWithoutFolding }

    var canChooseObject: Bool {
        !isShowingCover && revealed == nil
            && (engine.phase == .idle || engine.phase == .armed) && engine.measuredDepth < 0.01
    }

    var completedPresses: Int { collection.totalPresses }

    var feedbackContext: FeedbackContext {
        FeedbackContext(
            kind: currentKind,
            variant: variant,
            compression: Float(engine.measuredCompression),
            closingSpeed: Float(engine.closingSpeed),
            soundStyle: settings.soundStyle,
            reduceMotion: reduceMotion
        )
    }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true
        audio.start()
        haptics.start()
        GameCenter.shared.authenticate()
        engine.activate(at: CACurrentMediaTime())
        if DemoScenario.current != nil {
            setvbuf(stdout, nil, _IOLBF, 0) // CI captures stdout to a file; flush line by line.
        }
        // Until a hinge reports in, assume the touch press (so the teaching cue can show on any iPhone).
        engine.usesVirtualHinge = true
        load(firstObject())
        if let demo = DemoScenario.current {
            runDemo(demo)
        }
    }

    func sceneBecameActive() {
        guard started else { return }
        // Don't restart the input-ignore window here: on Duo, folding can toggle scene activity,
        // and ignoring the reopen would swallow the reveal. It only guards stale events at launch.
        haptics.resume()
        audio.resume()
    }

    func choose(_ kind: ObjectKind) {
        guard canChooseObject, kind != currentKind, collection.isUnlocked(kind) else { return }
        load(kind)
    }

    /// Collect the revealed specimen and put the next object on the anvil.
    /// A freshly unlocked object goes on next, so the unlock is felt immediately.
    func next() {
        guard let outcome = revealed else { return }
        audio.collect()
        haptics.collect()
        engine.finishReveal()
        revealed = nil
        if let unlocked = outcome.newlyUnlocked.first {
            load(unlocked)
        } else {
            load(nextUnlocked(after: currentKind))
        }
    }

    /// Pick the next object from the cover display while the phone is shut; it's waiting on the anvil on open.
    func queue(_ kind: ObjectKind) {
        guard isShowingCover, revealed == nil, collection.isUnlocked(kind), kind != currentKind,
              engine.phase == .idle || engine.phase == .armed, engine.measuredDepth < 0.01 else { return }
        load(kind)
    }

    /// The recorded input of a past press, so any card in the collection can share a clip.
    func trace(for specimen: SpecimenRecord) -> PressTrace? {
        if let lastTrace, lastSpecimenID == specimen.id { return lastTrace }
        return traceStore.load(specimen.id)
    }

    /// Press the same object again (from the reveal card).
    func again() {
        guard revealed != nil else { return }
        audio.collect()
        haptics.collect()
        engine.finishReveal()
        revealed = nil
        load(currentKind)
    }

    // MARK: - Input

    func hingeUpdate(angle: Double, closed: Bool) {
        if !hingeAvailable {
            hingeAvailable = true
        }
        hingeClosed = closed
        // CI (ci/duo-screenshots.sh) counts these to prove onHingeChange fired on the Duo simulator.
        if DemoScenario.current != nil, CACurrentMediaTime() - lastHingeLogTime > 0.25 {
            lastHingeLogTime = CACurrentMediaTime()
            print(String(format: "SQUISH-H %.2f %.1f %d phase=%@ depth=%.3f c=%.3f virtual=%d", lastHingeLogTime - launchTime,
                         angle, closed ? 1 : 0, engine.phase.rawValue, engine.measuredDepth, engine.measuredCompression,
                         engine.usesVirtualHinge ? 1 : 0))
        }

        // The reveal card is dismissed with the hinge too: closing the phone collects it, and
        // folding ~20° from the open position collects it and lets the next press begin in one motion.
        if revealed != nil && !settings.pressWithoutFolding {
            revealPeakAngle = max(revealPeakAngle, angle)
            if closed || angle < revealPeakAngle - 20 {
                revealPeakAngle = 0
                next()
            }
        } else {
            revealPeakAngle = 0
        }

        let now = CACurrentMediaTime()
        hingeLog.record(time: now, angle: angle, closed: closed)
        engine.usesVirtualHinge = settings.pressWithoutFolding
        guard !settings.pressWithoutFolding else { return }
        recordTrace(angle: angle, closed: closed, at: now)
        engine.ingest(angle: angle, closed: closed, at: now)
    }

    func hingeUnavailable() {
        guard !foldSimulated else { return }
        hingeAvailable = false
        hingeClosed = false
        engine.usesVirtualHinge = true
    }

    /// Touch press: 0 = open, 1 = fully pressed.
    func virtualPress(_ fraction: Double) {
        guard usesTouchPress else { return }
        engine.usesVirtualHinge = true
        let angle = 180 - clamp(fraction, 0, 1) * 180
        let now = CACurrentMediaTime()
        recordTrace(angle: angle, closed: false, at: now)
        engine.setVirtualAngle(angle, at: now)
    }

    func virtualRelease() {
        guard usesTouchPress else { return }
        // Touch traces never close, so `closed` marks the finger lifting: the clip replay springs the press open too.
        recordTrace(angle: engine.angle, closed: true, at: CACurrentMediaTime())
        engine.releaseVirtual()
    }

    // MARK: - Loop

    func frame(dt: TimeInterval) {
        renderedFrames &+= 1
        if DemoScenario.current != nil, [1, 30, 120, 600].contains(renderedFrames) {
            print(String(format: "SQUISH-T frame %ld at %.2fs phase=%@ depth=%.3f", renderedFrames,
                         CACurrentMediaTime() - launchTime, engine.phase.rawValue, engine.measuredDepth))
        }
        haptics.level = settings.hapticsLevel
        audio.enabled = settings.soundEnabled
        audio.style = settings.soundStyle
        // The scene's first-run "drag down" teaching pulse stops once a press has been completed.
        scene.isFirstPress = completedPresses == 0

        engine.step(now: CACurrentMediaTime(), dt: dt)
        let context = feedbackContext
        scene.update(engine: engine, context: context, dt: Float(dt))
        if usesFoldPress {
            // Fold Press only exists while it is showing: (re)load it lazily so non-Duo iPhones never touch it.
            if foldVariantSeed != variant.seed {
                foldVariantSeed = variant.seed
                fold.setObject(currentKind, variant: variant)
            }
            fold.update(engine: engine, context: context, dt: Float(dt))
        }
        haptics.update(engine: engine, context: context)
        audio.update(engine: engine, context: context)
    }

    // MARK: - Internals

    /// Bubble Wrap teaches the gesture on the very first launch; afterwards we pick up where you left off.
    private func firstObject() -> ObjectKind {
        guard collection.totalPresses > 0,
              let raw = UserDefaults.standard.string(forKey: Self.lastObjectKey),
              let kind = ObjectKind(rawValue: raw), collection.isUnlocked(kind) else { return .bubbleWrap }
        return kind
    }

    private func nextUnlocked(after kind: ObjectKind) -> ObjectKind {
        let all = ObjectKind.allCases
        let start = all.firstIndex(of: kind) ?? 0
        for offset in 1...all.count {
            let candidate = all[(start + offset) % all.count]
            if collection.isUnlocked(candidate) { return candidate }
        }
        return kind
    }

    private func load(_ kind: ObjectKind) {
        currentKind = kind
        if DemoScenario.current == nil {
            UserDefaults.standard.set(kind.rawValue, forKey: Self.lastObjectKey)
        }
        var seed = UInt64.random(in: 1...UInt64.max)
        if let demo = DemoScenario.current, let forced = demo.string("seed").flatMap(UInt64.init) {
            seed = forced
        }
        variant = PressVariant(kind: kind, seed: seed)
        if let demo = DemoScenario.current {
            if demo.has("golden") { variant.isGolden = kind != .unsquishable }
            if let raw = demo.string("surprise"), let surprise = Surprise(rawValue: raw) { variant.surprise = surprise }
        }
        engine.load(kind, seed: seed, at: CACurrentMediaTime())
        scene.setObject(kind, variant: variant)
        foldVariantSeed = nil
        let context = feedbackContext
        audio.place(context: context)
        haptics.place(context: context)
        traceSamples.removeAll(keepingCapacity: true)
        traceStart = CACurrentMediaTime()
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: kind.accessibilityDescription)
        }
    }

    private func recordTrace(angle: Double, closed: Bool, at time: Double) {
        guard engine.phase != .revealing, traceSamples.count < 20_000 else { return }
        traceSamples.append(PressTrace.Sample(time: time - traceStart, angle: angle, closed: closed))
    }

    private func handle(_ event: PressEvent) {
        let context = feedbackContext
        scene.handle(event, context: context)
        if usesFoldPress && foldVariantSeed == variant.seed { fold.handle(event, context: context) }
        haptics.handle(event, context: context)
        audio.handle(event, context: context)

        if let line = Captions.caption(for: event, context: context) {
            captionCounter += 1
            caption = CaptionEvent(id: captionCounter, text: line.text, announce: line.announce)
            if line.announce && UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .announcement, argument: line.text)
            }
        }

        switch event {
        case .fracture(_, true):
            failureFlashCount += 1
        case .reveal:
            reveal()
        default:
            break
        }
    }

    private func reveal() {
        guard let result = engine.lastResult else { return }
        lastTrace = PressTrace(kind: currentKind, variant: variant, samples: traceSamples,
                               usesVirtualHinge: engine.usesVirtualHinge, config: engine.config)
        let outcome = collection.record(result, variant: variant, trace: lastTrace)
        revealed = outcome
        coachIfSlamming(result)
        lastSpecimenID = outcome.specimen.id
        if let lastTrace {
            traceStore.save(lastTrace, for: outcome.specimen.id)
        }
        if !outcome.newlyUnlocked.isEmpty {
            audio.unlock()
        }
        GameCenter.shared.report(outcome.newAchievements)
        // Capture the specimen thumbnail once the ram has lifted clear of the flattened object.
        let specimenID = outcome.specimen.id
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            // The clean top-down specimen shot; fall back to the live frame (never the warped Duo anvil view).
            guard let self else { return }
            var image = await self.scene.specimenSnapshot()
            if self.usesFoldPress, let diptych = self.fold.specimenDiptych(specimen: image) {
                image = diptych   // Fold Press cards: the platen's print above the flattened specimen (FOLD-PRESS §6.3)
            }
            if image == nil, !self.usesFoldPress { image = await self.scene.snapshot() }
            guard let image, let png = image.pngData() else { return }
            self.collection.attachThumbnail(png, to: specimenID)
        }
    }

    /// After two slams in a row, one gentle hint (at most three times ever). Slams are never rewarded;
    /// slow presses are richer. Also keeps us clear of App Review 2.4.2 (bible §2).
    private func coachIfSlamming(_ result: PressResult) {
        consecutiveSlams = result.wasSlammed ? consecutiveSlams + 1 : 0
        let shown = UserDefaults.standard.integer(forKey: Self.slamHintsKey)
        guard consecutiveSlams >= 2, shown < 3 else { return }
        consecutiveSlams = 0
        UserDefaults.standard.set(shown + 1, forKey: Self.slamHintsKey)
        captionCounter += 1
        let line = usesTouchPress ? "Slowly… it's more satisfying." : "Close it slowly… it's more satisfying."
        coachHint = CaptionEvent(id: captionCounter, text: line, announce: true)
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: line)
        }
    }

    // MARK: - Demo (CI screenshots)

    /// Drives the touch press to a scripted state (see DemoMode.swift).
    private func runDemo(_ demo: DemoScenario) {
        print(String(format: "SQUISH-T demo '%@' starts at %.2fs", demo.name, CACurrentMediaTime() - launchTime))
        engine.config.ignoreInputAfterActivation = 0
        if demo.has("duo") {
            // Real iPhone Duo simulator: the CI script moves the actual hinge; we only place the object.
            if let kind = demo.object { load(kind) }
            #if DEBUG
            if demo.has("storeshot") { watchStoreShots(demo) }
            #endif
            return
        }
        if let raw = demo.string("foldsim") {
            // Fold Press on a regular simulator: fake a hinge and sweep it through the listed angles.
            foldSimulated = true
            if let kind = demo.object { load(kind) }
            let targets = raw.split(separator: ",").compactMap { Double($0) }
            hingeUpdate(angle: 180, closed: false)
            Task { @MainActor in
                while renderedFrames < 30 { try? await Task.sleep(for: .milliseconds(50)) }
                var angle = 180.0
                for target in targets {
                    while abs(angle - target) > 0.5 {
                        angle += max(-0.5, min(0.5, target - angle))
                        hingeUpdate(angle: angle, closed: false)
                        try? await Task.sleep(for: .milliseconds(16))
                    }
                    for _ in 0..<60 {
                        hingeUpdate(angle: target, closed: false)
                        try? await Task.sleep(for: .milliseconds(16))
                    }
                    #if DEBUG
                    // `storeshot` alone: a store shot at every target; `storeshot=120,75`: only at those.
                    if demo.has("storeshot") {
                        let wanted = demo.doubles("storeshot")
                        if wanted.isEmpty || wanted.contains(where: { abs($0 - target) < 0.5 }) {
                            await self.writeStoreShot(demo, label: Int(target.rounded()), angle: target)
                        }
                    }
                    #endif
                }
                print(String(format: "SQUISH-T foldsim done at %.2fs phase=%@ c=%.3f", CACurrentMediaTime() - self.launchTime,
                             self.engine.phase.rawValue, self.engine.measuredCompression))
                #if DEBUG
                if demo.has("storeshot") {
                    print(String(format: "SQUISH-T storeshot done at %.2fs", CACurrentMediaTime() - self.launchTime))
                }
                #endif
            }
            return
        }
        hingeUnavailable()
        if let kind = demo.object { load(kind) }
        let targetDepth: Double? = demo.has("reveal") ? 1 : demo.double("depth")
        guard let targetDepth else { return }
        // The touch press arms at armAngleMax, so map with the contact point captured there (floating contact).
        let start = engine.config.armAngleMax
        let targetAngle = PressMapping.angle(forDepth: targetDepth, start: start, config: engine.config.armed(at: start))
        Task { @MainActor in
            // Wait until the scene is actually rendering (first frames can be slow on CI simulators).
            while renderedFrames < 30 {
                try? await Task.sleep(for: .milliseconds(50))
            }
            print(String(format: "SQUISH-T demo press begins at %.2fs phase=%@ touch=%d", CACurrentMediaTime() - launchTime,
                         engine.phase.rawValue, usesTouchPress ? 1 : 0))
            virtualPress(0)
            try? await Task.sleep(for: .milliseconds(300))
            let steps = 90
            for step in 1...steps {
                let angle = 180 + (targetAngle - 180) * Double(step) / Double(steps)
                virtualPress((180 - angle) / 180)
                try? await Task.sleep(for: .milliseconds(16))
            }
            for _ in 0..<30 {
                virtualPress((180 - targetAngle) / 180)
                try? await Task.sleep(for: .milliseconds(16))
            }
            print(String(format: "SQUISH-T demo press done at %.2fs phase=%@ depth=%.3f", CACurrentMediaTime() - launchTime,
                         engine.phase.rawValue, engine.measuredDepth))
            if demo.has("exportclip") {
                await exportDemoClip()
            }
        }
    }

    /// CI hook: render the share clip of the demo press into Documents/clip.mp4 so CI can upload it.
    private func exportDemoClip() async {
        for _ in 0..<200 where revealed == nil {
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard let outcome = revealed, let trace = lastTrace else {
            print("SQUISH-CLIP failed: no reveal")
            return
        }
        try? await Task.sleep(for: .milliseconds(800))
        let started = CACurrentMediaTime()
        do {
            let url = try await ClipExporter().export(trace: trace, specimen: outcome.specimen) { _ in }
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destination = documents.appendingPathComponent("clip.mp4")
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: url, to: destination)
            let bytes = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int) ?? 0
            print(String(format: "SQUISH-CLIP ok bytes=%ld seconds=%.1f", bytes, CACurrentMediaTime() - started))
        } catch {
            print("SQUISH-CLIP failed: \(error.localizedDescription)")
        }
    }

    #if DEBUG
    /// CI hook (`duo;storeshot=120,75`, real Duo): the CI script moves the real hinge and holds it at each angle, so
    /// shoot once the raw hinge has been still (±1.5°) for 0.8 s within 3° of a wanted angle. Each angle once.
    private func watchStoreShots(_ demo: DemoScenario) {
        Task { @MainActor [weak self] in
            var pending = demo.doubles("storeshot")
            if pending.isEmpty { pending = [115] }
            var anchor = -1.0
            var since = CACurrentMediaTime()
            let deadline = CACurrentMediaTime() + 1200
            while !pending.isEmpty && CACurrentMediaTime() < deadline {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                guard let angle = self.hingeLog.samples.last?.angle else { continue }
                let now = CACurrentMediaTime()
                if abs(angle - anchor) > 1.5 {
                    anchor = angle
                    since = now
                    continue
                }
                guard now - since >= 0.8, let index = pending.firstIndex(where: { abs($0 - angle) <= 3 }) else { continue }
                let target = pending.remove(at: index)
                await self.writeStoreShot(demo, label: Int(target.rounded()), angle: angle)
                since = CACurrentMediaTime()
            }
            guard let self else { return }
            print(String(format: "SQUISH-T storeshot done at %.2fs missing=%@", CACurrentMediaTime() - self.launchTime,
                         pending.map { String(Int($0.rounded())) }.joined(separator: ",")))
        }
    }

    /// CI hook (`storeshot`): snapshot the live Fold Press stage and write the folded-device store shot
    /// (FoldStoreShot.swift, FOLD-REVIEW-3 N1) to Documents for ci/screenshots.sh and ci/duo-screenshots.sh to collect:
    ///  • storeshot-<label>.png       1320 × 2868, 3/4 eye (the App Store frame)
    ///  • storeshot-<label>-land.png  2868 × 1320, with `storeshotsize=landscape|both`
    ///  • storeshot-<label>-eye.png   1320 × 2868 from the exact design eye, no sheen (the §12 E1/E2 composite)
    /// The device is modelled at the captured hinge angle (`storeshotfold=<deg>` overrides it, e.g. 115 for art).
    private func writeStoreShot(_ demo: DemoScenario, label: Int, angle: Double) async {
        let started = CACurrentMediaTime()
        guard usesFoldPress, let halves = await FoldStoreShot.capture(scene: scene, fold: fold) else {
            print(String(format: "SQUISH-T storeshot %ld failed: no Fold Press stage on screen", label))
            return
        }
        var base = FoldStoreShot.Options()
        base.hingeAngle = clamp(demo.double("storeshotfold") ?? angle, 45, 180)
        base.eyeModel = fold.eye
        let sizes = demo.string("storeshotsize") ?? "portrait"
        var variants: [(file: String, options: FoldStoreShot.Options)] = []
        if sizes != "landscape" {
            variants.append((file: "storeshot-\(label).png", options: base))
        }
        if sizes == "landscape" || sizes == "both" {
            var landscape = base
            landscape.size = FoldStoreShot.landscape
            variants.append((file: "storeshot-\(label)-land.png", options: landscape))
        }
        var eyeView = base
        eyeView.eye = .design
        eyeView.glassSheen = false
        variants.append((file: "storeshot-\(label)-eye.png", options: eyeView))

        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var written: [String] = []
        for variant in variants {
            guard let image = FoldStoreShot.render(halves, options: variant.options), let png = image.pngData() else {
                print("SQUISH-T storeshot \(label) render failed: \(variant.file)")
                continue
            }
            do {
                try png.write(to: documents.appendingPathComponent(variant.file), options: .atomic)
                written.append(variant.file)
            } catch {
                print("SQUISH-T storeshot \(label) write failed: \(variant.file) \(error.localizedDescription)")
            }
        }
        let status = written.isEmpty ? "failed:" : "ok"
        print(String(format: "SQUISH-T storeshot %ld %@ at %.2fs hinge=%.1f model=%.1f %@ anvil=%@ phase=%@ c=%.3f files=%@ ms=%.0f",
                     label, status, CACurrentMediaTime() - launchTime, angle, base.hingeAngle,
                     halves.layout.isBook ? "book" : "tabletop", halves.source, engine.phase.rawValue,
                     engine.measuredCompression, written.joined(separator: ","), (CACurrentMediaTime() - started) * 1000))
    }
    #endif
}

/// The input of one press, kept so the share clip can replay it deterministically.
struct PressTrace: Codable, Sendable {
    struct Sample: Codable, Sendable {
        var time: Double
        var angle: Double
        var closed: Bool
    }

    var kind: ObjectKind
    var variant: PressVariant
    var samples: [Sample]
    var usesVirtualHinge: Bool
    var config: PressConfig
}

/// One small JSON file per specimen in Application Support/Squish/traces (a few KB each).
@MainActor
final class TraceStore {
    private let directory: URL?

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        directory = base?.appendingPathComponent("Squish/traces", isDirectory: true)
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    func save(_ trace: PressTrace, for id: UUID) {
        guard let url = url(for: id), let data = try? JSONEncoder().encode(trace) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func load(_ id: UUID) -> PressTrace? {
        guard let url = url(for: id), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PressTrace.self, from: data)
    }

    private func url(for id: UUID) -> URL? {
        directory?.appendingPathComponent("\(id.uuidString).json")
    }
}

/// Raw hinge samples for on-device tuning: update rate, quantisation, and the angles where the display switches.
@MainActor
final class HingeLog {
    struct Sample {
        let time: Double
        let angle: Double
        let closed: Bool
    }

    private(set) var samples: [Sample] = []
    private let capacity = 6000

    func record(time: Double, angle: Double, closed: Bool) {
        samples.append(Sample(time: time, angle: angle, closed: closed))
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }

    /// Updates per second over the most recent second of samples.
    var recentRate: Double {
        guard let last = samples.last else { return 0 }
        return Double(samples.reversed().prefix { last.time - $0.time <= 1 }.count)
    }

    func csv() -> String {
        guard let first = samples.first else { return "time,angle,closed\n" }
        var lines = ["time,angle,closed"]
        for sample in samples {
            lines.append(String(format: "%.4f,%.2f,%d", sample.time - first.time, sample.angle, sample.closed ? 1 : 0))
        }
        return lines.joined(separator: "\n")
    }

    func clear() {
        samples.removeAll()
    }
}
