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
    /// Fold-to-collect for the reveal card currently up (FOLD-REVIEW-6 N2); nil when no card is up.
    @ObservationIgnored private var revealGate: RevealCollectGate?
    /// One-shot recheck at the gate's deadline: a shut Duo lying still sends no more hinge samples.
    @ObservationIgnored private var revealGateCheck: Task<Void, Never>?
    @ObservationIgnored private var revealGateCheckDeadline: Double?
    @ObservationIgnored private var consecutiveSlams = 0
    /// Demo store shots (CI only, see `writeStoreShot`): the halves of each angle shot, kept for the before/after frame.
    @ObservationIgnored private var storeShotHalves: [String: FoldStoreShot.Halves] = [:]
    /// Demo store shots (FOLD-REVIEW-5 §3 a): `engine.angle` as of the last Fold Press update, which is what the
    /// crown readout shows, and the value it froze on at this object's failure (FoldPressController takes the same
    /// `lastAngle`), so the pair labels quote the screen instead of the model angle.
    @ObservationIgnored private var storeShotReadoutAngle: Double = 180
    @ObservationIgnored private var storeShotFrozen: (seed: UInt64, angle: Double)?
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
        clearRevealGate()
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
        clearRevealGate()
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
        // CI (ci/duo-screenshots.sh) counts these to prove onHingeChange fired on the Duo simulator, and reads the
        // phase from them, so log after the engine has taken this sample (deferred), not before.
        defer {
            if DemoScenario.current != nil, CACurrentMediaTime() - lastHingeLogTime > 0.25 {
                lastHingeLogTime = CACurrentMediaTime()
                print(String(format: "SQUISH-H %.2f %.1f %d phase=%@ depth=%.3f c=%.3f virtual=%d", lastHingeLogTime - launchTime,
                             angle, closed ? 1 : 0, engine.phase.rawValue, engine.measuredDepth, engine.measuredCompression,
                             engine.usesVirtualHinge ? 1 : 0))
            }
        }

        // The reveal card is dismissed with the hinge too: closing the phone collects it, and folding ~20° from the
        // open position collects it and lets the next press begin in one motion. Only a deliberate close counts, never
        // a stray `closed` sample or a brief dip (FOLD-REVIEW-6 N2; the rules are in RevealCollectGate).
        let now = CACurrentMediaTime()
        if revealed != nil && !settings.pressWithoutFolding {
            var gate = revealGate ?? RevealCollectGate(start: now, angle: angle)
            let collect = gate.ingest(angle: angle, closed: closed, at: now)
            revealGate = gate
            if collect {
                next()
            } else {
                scheduleRevealGateCheck(at: gate.nextDeadline)
            }
        }

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
            #if DEBUG
            if DemoScenario.current != nil { storeShotReadoutAngle = engine.angle }   // demo store shots only
            #endif
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
        // The engine arms only on an observed hinge reading (FOLD-REVIEW-6 N3), and a Duo lying still sends none, so
        // start the trace with the reading this press armed on: the share-clip replay then arms exactly as it did.
        if usesFoldPress && engine.hasHingeSample {
            recordTrace(angle: engine.rawAngle, closed: engine.isClosed, at: traceStart)
        }
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
        #if DEBUG
        // Demo store shots only: the angle the crown readout freezes on (see `storeShotReadout`).
        if DemoScenario.current != nil, case .fracture(_, true) = event, usesFoldPress, foldVariantSeed == variant.seed,
           storeShotFrozen?.seed != variant.seed {
            storeShotFrozen = (seed: variant.seed, angle: engine.failureAngle ?? storeShotReadoutAngle)
        }
        #endif
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
        // Fold-to-collect starts from the hinge as the card comes up (the sample that revealed it, or the last one).
        clearRevealGate()
        revealGate = RevealCollectGate(start: CACurrentMediaTime(), angle: engine.rawAngle)
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

    private func clearRevealGate() {
        revealGate = nil
        revealGateCheck?.cancel()
        revealGateCheck = nil
        revealGateCheckDeadline = nil
    }

    /// Re-check the reveal gate at `deadline` (nil cancels): after a close the hinge may send nothing more.
    private func scheduleRevealGateCheck(at deadline: Double?) {
        if let deadline, deadline == revealGateCheckDeadline, revealGateCheck != nil { return }   // already pending
        revealGateCheck?.cancel()
        revealGateCheck = nil
        revealGateCheckDeadline = deadline
        guard let deadline else { return }
        let delay = max(deadline - CACurrentMediaTime(), 0) + 0.02
        revealGateCheck = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.revealGateCheck = nil
            self.revealGateCheckDeadline = nil
            guard self.revealed != nil, !self.settings.pressWithoutFolding,
                  let gate = self.revealGate, gate.shouldCollect(at: CACurrentMediaTime()) else { return }
            self.next()
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
        #if DEBUG
        applyDemoSettings(demo)
        if demo.has("orient") { holdInterfaceOrientation(demo) }
        #endif
        if demo.has("duo") {
            // Real iPhone Duo simulator: the CI script moves the actual hinge; we only place the object.
            if let kind = demo.object { load(kind) }
            #if DEBUG
            if demo.has("storeshot") { watchStoreShots(demo) }
            if demo.has("storegrid") { writeStoreGrid(demo) }
            if demo.has("pressaudio") || demo.has("previewmarks") { watchPreviewMarks() }
            if demo.has("hingescript") { Task { @MainActor [weak self] in await self?.runHingeScript(demo) } }
            if demo.has("pressaudio") {
                // The CI script drives the real hinge (press, close, reopen), so the reveal can take minutes.
                Task { @MainActor [weak self] in await self?.writeDemoPressAudio(waitingUpTo: 900) }
            }
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
                #if DEBUG
                let failuresAtStart = self.failureFlashCount
                var heroShot = false
                #endif
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
                    // `storeshot` alone: a store shot at every target; `storeshot=120,75`: only at those;
                    // `fail` in the list: the hero at the first held target after the object failed (and at or below
                    // `storeshotfailangle`, default 62°), then the before/after pair.
                    if demo.has("storeshot") {
                        let tokens = demo.tokens("storeshot")
                        let wanted = tokens.compactMap { Double($0) }
                        let wantsHero = tokens.contains("fail")
                        if (wanted.isEmpty && !wantsHero) || wanted.contains(where: { abs($0 - target) < 0.5 }) {
                            await self.writeStoreShot(demo, label: PressDirector.storeLabel(target), angle: target)
                        }
                        let failHold = demo.double("storeshotfailangle") ?? 62
                        if wantsHero, !heroShot, self.failureFlashCount > failuresAtStart, target <= failHold + 3 {
                            heroShot = true
                            print(String(format: "SQUISH-T storeshot failure seen at %.2fs hinge=%.1f",
                                         CACurrentMediaTime() - self.launchTime, target))
                            if let after = await self.writeStoreShot(demo, label: "hero", angle: target, hero: true) {
                                self.writeStorePair(demo, after: after)
                            }
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
        #if DEBUG
        // With `prewarm` the marks start after the warm-up press, at the recorded take's placement.
        let prewarm = demo.has("prewarm") && targetDepth != nil
        if (demo.has("pressaudio") || demo.has("previewmarks")) && !prewarm { watchPreviewMarks() }
        #endif
        guard let targetDepth else { return }
        // The touch press arms at armAngleMax, so map with the contact point captured there (floating contact).
        let start = engine.config.armAngleMax
        let targetAngle = PressMapping.angle(forDepth: targetDepth, start: start, config: engine.config.armed(at: start))
        Task { @MainActor in
            // Wait until the scene is actually rendering (first frames can be slow on CI simulators).
            while renderedFrames < 30 {
                try? await Task.sleep(for: .milliseconds(50))
            }
            #if DEBUG
            if prewarm {
                await prewarmDemoPress(targetAngle: targetAngle)
                if demo.has("pressaudio") || demo.has("previewmarks") { watchPreviewMarks() }
            }
            #endif
            print(String(format: "SQUISH-T demo press begins at %.2fs phase=%@ touch=%d", CACurrentMediaTime() - launchTime,
                         engine.phase.rawValue, usesTouchPress ? 1 : 0))
            virtualPress(0)
            try? await Task.sleep(for: .milliseconds(300))
            #if DEBUG
            let slow = demo.has("slowpress")
            #else
            let slow = false
            #endif
            if slow {
                #if DEBUG
                await slowDemoPress(demo, targetDepth: targetDepth, start: start)
                #endif
            } else {
                let steps = 90
                for step in 1...steps {
                    let angle = 180 + (targetAngle - 180) * Double(step) / Double(steps)
                    virtualPress((180 - angle) / 180)
                    try? await Task.sleep(for: .milliseconds(16))
                }
            }
            for _ in 0..<(slow ? 45 : 30) {
                virtualPress((180 - targetAngle) / 180)
                try? await Task.sleep(for: .milliseconds(16))
            }
            // FOLD-REVIEW-7 N2: ci/screenshots.sh checks the P-frames against this line (`expect=` in
            // ci/scenarios.txt): c = compression, fractures = thresholds crossed, failed = the failure fired.
            let failureIndex: Int = currentKind.profile.failureIndex ?? -1
            print(String(format: "SQUISH-T demo press done at %.2fs phase=%@ depth=%.3f c=%.3f fractures=%ld failed=%ld failureIndex=%ld kind=%@",
                         CACurrentMediaTime() - launchTime, engine.phase.rawValue, engine.measuredDepth,
                         engine.measuredCompression, engine.firedCount, engine.failureAngle == nil ? 0 : 1,
                         failureIndex, currentKind.rawValue))
            if demo.has("reveal") { logDemoReveal() }
            if demo.has("exportclip") {
                await exportDemoClip()
            }
            #if DEBUG
            if demo.has("pressaudio") { await writeDemoPressAudio(waitingUpTo: 20) }
            #endif
        }
    }

    /// CI hook (`reveal`, FOLD-REVIEW-7 N2): say when the reveal card is up, and for which press, so ci/screenshots.sh
    /// can wait for it and refuse a reveal frame (P2) captured without one. Runs beside `exportDemoClip`, never
    /// delaying it.
    private func logDemoReveal() {
        let started = CACurrentMediaTime()
        Task { @MainActor [weak self] in
            while CACurrentMediaTime() - started < 20 {
                guard let self else { return }
                if self.revealed != nil {
                    let surprise: String = self.variant.surprise?.rawValue ?? "none"
                    print(String(format: "SQUISH-T demo reveal up at %.2fs phase=%@ revealed=1 kind=%@ fractures=%ld failed=%ld golden=%ld surprise=%@",
                                 CACurrentMediaTime() - self.launchTime, self.engine.phase.rawValue,
                                 self.currentKind.rawValue, self.engine.firedCount,
                                 self.engine.failureAngle == nil ? 0 : 1, self.variant.isGolden ? 1 : 0, surprise))
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard let self else { return }
            print(String(format: "SQUISH-T demo reveal missing after 20s phase=%@ revealed=0 kind=%@",
                         self.engine.phase.rawValue, self.currentKind.rawValue))
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
    // MARK: Preview-video hooks (docs/appstore/preview-video.md, ci/preview.sh, ci/preview-duo.sh)

    /// `slowpress[=seconds]` (default 5; with `depth=` or `reveal`): the touch press as a hand would make it, for the
    /// App Preview. The linear 1.5 s scripted press reads as a robot on video. A 0.35 s lead-in eases the ram to
    /// the arm angle, then `slowPressDepth` takes over: ease down onto the object, a slow squeeze, a hold just short of
    /// most failures (depth 0.52–0.535: glass seed 3 fails at 0.588, the duck's seam at 0.572), then an ease through to
    /// the target. Paced on the wall clock, so a slow CI simulator keeps the timing, not the frame count. Logs
    /// `SQUISH-T demo slowpress <s>s begins at …`. Peak closing speed stays under `perfectMaxSpeed` (~50°/s).
    private func slowDemoPress(_ demo: DemoScenario, targetDepth: Double, start: Double) async {
        let duration = max(demo.double("slowpress") ?? 5, 1.5)
        let mapping = engine.config.armed(at: start)
        let leadIn = 0.35
        print(String(format: "SQUISH-T demo slowpress %.1fs begins at %.2fs target=%.2f", duration,
                     CACurrentMediaTime() - launchTime, targetDepth))
        let began = CACurrentMediaTime()
        while true {
            let t = CACurrentMediaTime() - began
            var done = false
            let angle: Double
            if t < leadIn {
                angle = 180 + (start - 180) * PressDirector.smooth(t / leadIn)
            } else {
                let curve = PressDirector.slowPressDepth(at: t - leadIn, duration: duration)
                done = curve >= targetDepth - 0.0005 || t - leadIn >= duration + 0.5
                angle = PressMapping.angle(forDepth: min(curve, targetDepth), start: start, config: mapping)
            }
            virtualPress((180 - angle) / 180)
            if done { break }
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    /// `prewarm` (touch press, with `depth=` or `reveal`): one quick press of the same object to its reveal, then Again,
    /// before the scripted press. On the CI simulator the first crack, burst or failure of an object in a process
    /// stalls rendering for 0.5–0.9 s (preview run 39973167568: every recorded take had one, at a fracture); doing it
    /// once off the record means the take the preview uses renders smoothly. The marks (`pressaudio` /
    /// `previewmarks`) start after it, so `origin` is the recorded take's placement. Logs `SQUISH-T demo prewarm done`.
    private func prewarmDemoPress(targetAngle: Double) async {
        let began = CACurrentMediaTime()
        virtualPress(0)
        try? await Task.sleep(for: .milliseconds(300))
        for step in 1...60 {
            let angle = 180 + (targetAngle - 180) * Double(step) / 60
            virtualPress((180 - angle) / 180)
            try? await Task.sleep(for: .milliseconds(16))
        }
        for _ in 0..<30 {
            virtualPress((180 - targetAngle) / 180)
            try? await Task.sleep(for: .milliseconds(16))
        }
        while revealed == nil, CACurrentMediaTime() - began < 20 {
            try? await Task.sleep(for: .milliseconds(50))
        }
        try? await Task.sleep(for: .seconds(1.5))   // the reveal card's own first-time work
        let hadReveal = revealed != nil
        again()
        try? await Task.sleep(for: .seconds(1.5))   // the object lands again
        print(String(format: "SQUISH-T demo prewarm done at %.2fs revealed=%d phase=%@", CACurrentMediaTime() - launchTime,
                     hadReveal ? 1 : 0, engine.phase.rawValue))
    }

    /// `hingescript[=seconds]` (with `duo`, default 7): the Duo preview's press, fed through `hingeUpdate` exactly as
    /// `onHingeChange` samples are, at 60 Hz, because the simulator's `hinge` CLI can't hold a steady sweep (preview run
    /// 39973167568: a 180° → 58° sweep stalled at 125°, then jumped to 60° reporting "closed"; each call costs 5–12 s).
    /// The real simulated Duo lies still at 180°, so it sends no samples of its own meanwhile. The script: wait for the
    /// tabletop layout, close 180° → 58° on the `slowPressDepth` pacing (ease in, squeeze, a hold near 115°, through),
    /// hold 0.6 s, on to 44° (below the ~55° where a real inner display is dark, so never used on camera) until the
    /// press seals, then reopen to 160° in 1.2 s: the reveal. Writes Documents/preview-script.txt (`script-<step>
    /// epoch=<unix s>`: begin, 58, sealed, reopen, 160) for ci/preview-duo.sh, and logs `SQUISH-T hingescript …`.
    private func runHingeScript(_ demo: DemoScenario) async {
        let close = max(demo.double("hingescript") ?? 7, 2)
        var lines: [String] = []
        let waitStart = CACurrentMediaTime()
        while CACurrentMediaTime() - waitStart < 60 {
            if renderedFrames >= 120, let layout = fold.layout, !layout.isBook { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? await Task.sleep(for: .seconds(2))
        scriptMark("begin", into: &lines)
        await scriptSweep(from: 180, to: 58, seconds: close, eased: false)
        scriptMark("58", into: &lines)
        await scriptHold(58, seconds: 0.6)
        await scriptSweep(from: 58, to: 44, seconds: 0.5, eased: true)
        let sealWait = CACurrentMediaTime()
        while engine.phase != .sealed, CACurrentMediaTime() - sealWait < 3 {
            hingeUpdate(angle: 44, closed: false)
            try? await Task.sleep(for: .milliseconds(16))
        }
        scriptMark("sealed", into: &lines)
        await scriptHold(44, seconds: 0.5)
        scriptMark("reopen", into: &lines)
        await scriptSweep(from: 44, to: 160, seconds: 1.2, eased: true)
        scriptMark("160", into: &lines)
        await scriptHold(160, seconds: 1)
    }

    private func scriptMark(_ name: String, into lines: inout [String]) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        lines.append(String(format: "script-%@ epoch=%.3f t=0", name, Date().timeIntervalSince1970))
        try? (lines.joined(separator: "\n") + "\n").write(to: documents.appendingPathComponent("preview-script.txt"),
                                                         atomically: true, encoding: .utf8)
        print(String(format: "SQUISH-T hingescript %@ at %.2fs angle=%.1f phase=%@", name,
                     CACurrentMediaTime() - launchTime, engine.angle, engine.phase.rawValue))
    }

    /// from → to over `seconds` at 60 Hz: `eased` = smoothstep; otherwise the `slowPressDepth` pacing.
    private func scriptSweep(from: Double, to: Double, seconds: Double, eased: Bool) async {
        let began = CACurrentMediaTime()
        while true {
            let t = min(CACurrentMediaTime() - began, seconds)
            let p = eased ? PressDirector.smooth(t / seconds) : PressDirector.slowPressDepth(at: t, duration: seconds)
            hingeUpdate(angle: from + (to - from) * p, closed: false)
            if t >= seconds { break }
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    private func scriptHold(_ angle: Double, seconds: Double) async {
        let began = CACurrentMediaTime()
        while CACurrentMediaTime() - began < seconds {
            hingeUpdate(angle: angle, closed: false)
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    /// The `slowpress` depth curve (0…1) at `t` seconds of a `duration`-second press. Monotonic (never reverses, so
    /// no `reversedWhileLoaded`): the pace wavers at 1.3 Hz by ±0.04 s, whose slope (0.33) is below 1.
    nonisolated static func slowPressDepth(at t: Double, duration: Double) -> Double {
        guard duration > 0 else { return 1 }
        let paced = t + 0.04 * sin(2 * Double.pi * 1.3 * t)
        let u = min(max(paced / duration, 0), 1)
        switch u {
        case ..<0.16: return 0.30 * smooth(u / 0.16)                       // down onto the object (contact ≈ 0.30)
        case ..<0.52: return 0.30 + 0.22 * smooth((u - 0.16) / 0.36)       // the slow squeeze
        case ..<0.66: return 0.52 + 0.015 * ((u - 0.52) / 0.14)            // the hold: it creaks
        default: return 0.535 + 0.465 * smooth((u - 0.66) / 0.34)          // through it, easing onto the bottom
        }
    }

    nonisolated private static func smooth(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return c * c * (3 - 2 * c)
    }

    /// Wall-clock seconds (Unix epoch) for a `CACurrentMediaTime()` value. The simulator shares the host's clock, so
    /// ci/preview.sh can line these up with the moment `simctl io recordVideo` started.
    nonisolated private static func epoch(_ mediaTime: Double) -> Double {
        Date().timeIntervalSince1970 - (CACurrentMediaTime() - mediaTime)
    }

    /// `pressaudio` (part 1): Documents/preview-marks.txt, rewritten at every mark, one line per moment the preview
    /// cut needs: `<name> epoch=<unix s> t=<s since the object was placed>`, starting with `origin` (the object's
    /// placement, which is t = 0 of the press trace and of press-audio.wav). Marks: `phase-<phase>` on every engine
    /// phase change, `fracture-<n>`, `failure`, `closed` / `opened` (hinge), `reveal`. Polled every 15 ms (so ±15 ms);
    /// stops 8 s after the reveal or after 15 min. Log lines arrive late in CI; the file carries exact times.
    private func watchPreviewMarks() {
        let origin = traceStart
        Task { @MainActor [weak self] in
            guard let self else { return }
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let file = documents.appendingPathComponent("preview-marks.txt")
            var lines: [String] = []
            func mark(_ name: String, at time: Double = CACurrentMediaTime()) {
                lines.append(String(format: "%@ epoch=%.3f t=%.3f", name, PressDirector.epoch(time), time - origin))
                try? (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
            }
            mark("origin", at: origin)
            print(String(format: "SQUISH-T preview marks origin epoch=%.3f", PressDirector.epoch(origin)))
            var phase = self.engine.phase
            var fractures = self.engine.firedCount
            var failures = self.failureFlashCount
            var closed = self.hingeClosed
            var revealAt: Double?
            let deadline = CACurrentMediaTime() + 900
            while CACurrentMediaTime() < deadline {
                if self.engine.phase != phase {
                    phase = self.engine.phase
                    mark("phase-\(phase.rawValue)")
                }
                if self.engine.firedCount > fractures {
                    fractures = self.engine.firedCount
                    mark("fracture-\(fractures)")
                }
                if self.failureFlashCount > failures {
                    failures = self.failureFlashCount
                    mark("failure")
                }
                if self.hingeClosed != closed {
                    closed = self.hingeClosed
                    mark(closed ? "closed" : "opened")
                }
                if revealAt == nil, self.revealed != nil {
                    revealAt = CACurrentMediaTime()
                    mark("reveal")
                }
                if let revealAt, CACurrentMediaTime() - revealAt > 8 { break }
                try? await Task.sleep(for: .milliseconds(15))
            }
            print("SQUISH-T preview marks done: \(lines.count) mark(s)")
        }
    }

    /// Seconds of sound kept after the last trace sample: the reveal sting and the room after it.
    private static let pressAudioTail: Double = 5
    /// Seconds the reveal is left alone before the sound is rendered (see `writeDemoPressAudio`).
    private static let pressAudioDelay: Double = 8

    /// `pressaudio` (part 2): once the reveal is up, re-render this press's sound offline from its trace, exactly as
    /// the share clip does (OfflineAudio, the live controller's twin) but in real time (rate 1, no retiming), and write
    /// Documents/press-audio.wav (48 kHz mono 16-bit) whose sample 0 is the `origin` mark, plus press-audio.txt
    /// (`origin=<epoch> seconds= rate=48000 kind= style=`). ci/preview.sh muxes it under the screen recording in sync.
    /// Logs `SQUISH-T pressaudio ok seconds= origin= bytes= kind=` or `SQUISH-T pressaudio failed: …`.
    private func writeDemoPressAudio(waitingUpTo timeout: Double) async {
        let origin = traceStart
        let started = CACurrentMediaTime()
        while revealed == nil, CACurrentMediaTime() - started < timeout {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard revealed != nil, let trace = lastTrace, let last = trace.samples.last else {
            print("SQUISH-T pressaudio failed: no reveal or no trace after \(Int(timeout))s")
            return
        }
        // Render only after the reveal has been on screen for a while: building the score runs on the main actor, and
        // the screen recording of the reveal card must not stall (ci/preview.sh stops recording ~4.5 s after it).
        try? await Task.sleep(for: .seconds(Self.pressAudioDelay))
        let seconds = last.time + Self.pressAudioTail
        let style = settings.soundStyle
        let score = Self.pressAudioScore(trace: trace, seconds: seconds, style: style)
        let frames = Int(seconds * OfflineAudio.sampleRate)
        let pcm = await Task.detached(priority: .userInitiated) {
            OfflineAudio.render(score, frames: frames)
        }.value
        let wav = Self.wavData(pcm, sampleRate: Int(OfflineAudio.sampleRate))
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let info = String(format: "origin=%.3f seconds=%.3f rate=%ld kind=%@ style=%@\n", Self.epoch(origin), seconds,
                          Int(OfflineAudio.sampleRate), trace.kind.rawValue, style.rawValue)
        do {
            try wav.write(to: documents.appendingPathComponent("press-audio.wav"), options: .atomic)
            try info.write(to: documents.appendingPathComponent("press-audio.txt"), atomically: true, encoding: .utf8)
            print(String(format: "SQUISH-T pressaudio ok seconds=%.2f origin=%.3f bytes=%ld kind=%@ notes=%ld",
                         seconds, Self.epoch(origin), wav.count, trace.kind.rawValue, score.notes.count))
        } catch {
            print("SQUISH-T pressaudio failed: \(error.localizedDescription)")
        }
    }

    /// The press replayed into the offline audio controller at a fixed 120 Hz step, clip time = source time.
    private static func pressAudioScore(trace: PressTrace, seconds: Double, style: SoundStyle) -> OfflineAudio.Score {
        let audio = OfflineAudio(style: style)
        let replay = PressReplay(trace: trace)
        let engine = replay.engine
        let context = { () -> FeedbackContext in
            FeedbackContext(kind: trace.kind, variant: trace.variant, compression: Float(engine.measuredCompression),
                            closingSpeed: Float(engine.closingSpeed), soundStyle: style, reduceMotion: false)
        }
        replay.onEvent = { event, time in
            audio.seek(to: time, rate: 1)
            audio.handle(event, context: context())
        }
        replay.load()
        audio.seek(to: 0, rate: 1)
        audio.place(context: context())
        let step = 1.0 / 120
        var index = 1
        while Double(index) * step <= seconds {
            let time = Double(index) * step
            let dt = max(time - replay.clock, 0)
            replay.advance(to: time)
            audio.seek(to: time, rate: 1)
            audio.update(engine: engine, context: context(), dt: dt)
            index += 1
        }
        return audio.score
    }

    /// 16-bit PCM mono WAV (little-endian, as on every Apple CPU).
    nonisolated static func wavData(_ samples: [Float], sampleRate: Int) -> Data {
        let pcm: [Int16] = samples.map { value in
            let clipped = value.isFinite ? max(-1, min(1, value)) : 0
            return Int16((clipped * 32767).rounded())
        }
        let bytes = pcm.count * 2
        var data = Data(capacity: 44 + bytes)
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8))
        append32(UInt32(36 + bytes))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append32(16)
        append16(1)                                // PCM
        append16(1)                                // mono
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate * 2))           // byte rate
        append16(2)                                // block align
        append16(16)                               // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append32(UInt32(bytes))
        pcm.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }
    #endif

    /// Store-frame captions (docs/appstore/screenshots.md, FOLD-REVIEW-5 N3 and §5); " / " starts the sub-line.
    /// Override with `storeshotcaption=` (hero), `paircaption=`, `revealcaption=` and `gridcaption=`.
    /// The hero's is per object: the duck carries the product line (frame 1), glass and can their own beats.
    private static func heroCaption(for kind: ObjectKind) -> String {
        switch kind {
        case .rubberDuck: return "Close your phone. Feel it *give*. / Squish turns the fold into a hydraulic press."
        case .glassBottle: return "It creaks. Then it *doesn't*."
        case .sodaCan: return "Cans buckle *ring* by ring."
        case .bubbleWrap: return "Every bubble *pops* on its own."
        default: return "*Ten* objects. Ten ways to give."
        }
    }
    /// FOLD-REVIEW-6 §3 A 02: the pair shows the gesture, not the opening, so it says what the hinge does.
    private static let pairCaption = "The hinge is the *lever*."
    private static let revealCaption = "Open up. File the *evidence*. / Every press becomes a specimen."
    private static let gridCaption = "*Ten* objects. Ten ways to give."
    /// FOLD-REVIEW-5 §3 d: the eye turn for frames whose object is already flat (the pair's large device, the grid),
    /// so the device's end shows the fold in profile; and for the pair's small device, whose object still stands
    /// (anamorphic lean grows with the turn). Override with `storeshotazimuth=` / `storepairazimuth=`.
    private static let squishAzimuth: Double = 32
    private static let standingAzimuth: Double = 24
    /// FOLD-REVIEW-6 #1: never model the hero below 58°. The real inner display goes dark from ~55° down, so a lit
    /// screen on a device drawn more closed would misrepresent the app.
    private static let heroMinimumAngle: Double = 58

    /// The hero camera per object (FOLD-REVIEW-6 #1, N7), each overridable with `storeshotazimuth=`,
    /// `storeshotelevation=` and `storeshotkeytilt=`:
    ///  • duck (frame 1): 22° elevation, 50° turn. The device's end then shows the wedge at ~96° on screen (34°/32°
    ///    showed ~133°, a laptop lid), and the fit still gives ~62 % fill (scratchpad r7tools/framing2.mjs);
    ///  • glass (frame 4): the other end of the device, −28°, at the default 34° elevation, so frames 1 and 4 are
    ///    no longer the same picture;
    ///  • the rest (fallback heroes only): the R5 32° turn.
    /// Every hero leans the key 18° toward the viewer, so the lid's shadow reaches ~55 mm from the crease at 64° and
    /// covers the object at the footprint centre (36.7 mm); under the overhead key it stopped at ~31 mm, short of it.
    ///
    /// FOLD-REVIEW-7 §3 A 04: the glass hero's bleed drops 0.10 → 0.04, so the hinge spine (the one "foldable phone"
    /// cue at that end) stays in frame: x 2.2–97.8 %, fill ≈ 62 % (framing3.mjs). The others keep the default 0.10.
    private static func heroCamera(for kind: ObjectKind)
        -> (azimuth: Double, elevation: Double?, keyTilt: Double, bleed: Double?) {
        switch kind {
        case .rubberDuck: return (azimuth: 50, elevation: 22, keyTilt: 18, bleed: nil)
        case .glassBottle: return (azimuth: -28, elevation: nil, keyTilt: 18, bleed: 0.04)
        default: return (azimuth: squishAzimuth, elevation: nil, keyTilt: 18, bleed: nil)
        }
    }
    /// FOLD-REVIEW-7 N4: the reveal's eye elevation (34° default for tabletop content); `revealelevation=` overrides.
    private static let revealElevation: Double = 42

    private static func storeLabel(_ angle: Double) -> String { String(Int(angle.rounded())) }

    private static func splitCaption(_ raw: String) -> (headline: String, subline: String?) {
        let parts = raw.components(separatedBy: " / ")
        let subline = parts.count > 1 ? parts.dropFirst().joined(separator: " / ") : nil
        return (headline: parts[0], subline: subline)
    }

    #if DEBUG
    /// CI hook (`duo;storeshot=112,fail`, real Duo): the CI script moves the real hinge and holds it at each angle, so
    /// shoot once the raw hinge has been still (±1.5°) for 0.8 s within 3° of a wanted angle, each angle once. `fail`
    /// shoots the hero (FOLD-REVIEW-4 #2) at the first such hold after the object failed and at or below
    /// `storeshotfailangle` (default 62°, so a glass bottle failing at 81° still waits for the 62° hold), then the
    /// before/after pair with the angle shot nearest `storepair` (default 112°). `reveal` (FOLD-REVIEW-5 N4) shoots
    /// the tabletop reveal once the reveal card is up (2.5 s, so its label and console keys have faded in) and the
    /// hinge has been still for 0.8 s at 120° or more: the script closes to 0° after the last hold and reopens.
    private func watchStoreShots(_ demo: DemoScenario) {
        Task { @MainActor [weak self] in
            let tokens = demo.tokens("storeshot")
            var pending = tokens.compactMap { Double($0) }
            var wantsHero = tokens.contains("fail")
            var wantsReveal = tokens.contains("reveal")
            if pending.isEmpty && !wantsHero && !wantsReveal { pending = [115] }
            let failHold = demo.double("storeshotfailangle") ?? 62
            let failuresAtStart = self?.failureFlashCount ?? 0
            var failureLogged = false
            var revealSeen: Double?
            var anchor = -1.0
            var since = CACurrentMediaTime()
            let deadline = CACurrentMediaTime() + 1200
            while (!pending.isEmpty || wantsHero || wantsReveal) && CACurrentMediaTime() < deadline {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                let failed = self.failureFlashCount > failuresAtStart
                if wantsHero, failed, !failureLogged {
                    failureLogged = true
                    print(String(format: "SQUISH-T storeshot failure seen at %.2fs hinge=%.1f readout=%ld",
                                 CACurrentMediaTime() - self.launchTime, self.hingeLog.samples.last?.angle ?? -1,
                                 self.storeShotReadout().degrees))
                }
                if wantsReveal, revealSeen == nil, self.revealed != nil {
                    revealSeen = CACurrentMediaTime()
                    print(String(format: "SQUISH-T storeshot reveal seen at %.2fs hinge=%.1f",
                                 CACurrentMediaTime() - self.launchTime, self.hingeLog.samples.last?.angle ?? -1))
                }
                guard let angle = self.hingeLog.samples.last?.angle else { continue }
                let now = CACurrentMediaTime()
                if abs(angle - anchor) > 1.5 {
                    anchor = angle
                    since = now
                    continue
                }
                guard now - since >= 0.8 else { continue }
                if wantsHero, failed, angle <= failHold + 3 {
                    wantsHero = false
                    if let after = await self.writeStoreShot(demo, label: "hero", angle: angle, hero: true) {
                        self.writeStorePair(demo, after: after)
                    }
                    since = CACurrentMediaTime()
                    continue
                }
                if wantsReveal, let seen = revealSeen, now - seen >= 2.5, self.revealed != nil, angle >= 120 {
                    wantsReveal = false
                    await self.writeStoreShot(demo, label: "reveal", angle: angle, reveal: true)
                    since = CACurrentMediaTime()
                    continue
                }
                guard let index = pending.firstIndex(where: { abs($0 - angle) <= 3 }) else { continue }
                let target = pending.remove(at: index)
                await self.writeStoreShot(demo, label: PressDirector.storeLabel(target), angle: angle)
                since = CACurrentMediaTime()
            }
            guard let self else { return }
            var missing = pending.map { PressDirector.storeLabel($0) }
            if wantsHero { missing.append("hero") }
            if wantsReveal { missing.append("reveal") }
            print(String(format: "SQUISH-T storeshot done at %.2fs missing=%@", CACurrentMediaTime() - self.launchTime,
                         missing.joined(separator: ",")))
        }
    }

    /// CI hook (`orient=portrait`, iPhone Duo): the Duo simulator runs in book pose (landscape inner display,
    /// vertical fold) and `simctl` cannot rotate a device, so ask the window scene for portrait instead. The inner
    /// canvas becomes 669 × 951 with a horizontal fold, the tabletop layout the store shot needs (FOLD-REVIEW-4 F1).
    /// The system may rotate back when the simulated device reports its own orientation again (a hinge move can), so
    /// the request is repeated (at most every 2 s) whenever the interface leaves the wanted orientation. Logs
    /// `SQUISH-T orient <value> ok|failed|lost` for ci/duo-screenshots.sh. `orient=landscape` asks for book pose.
    private func holdInterfaceOrientation(_ demo: DemoScenario) {
        let raw = demo.string("orient") ?? ""
        let mask: UIInterfaceOrientationMask
        switch raw {
        case "portrait", "tabletop":
            mask = .portrait
        case "landscape", "book":
            mask = .landscapeRight
        default:
            print("SQUISH-T orient \(raw) failed: unknown value (portrait|landscape)")
            return
        }
        let wantsPortrait = mask == .portrait
        Task { @MainActor [weak self] in
            let started = CACurrentMediaTime()
            var reported = false
            var failedLogged = false
            var lostLogged = false
            var shapeLogged = false
            var requests = 0
            var lastRequest = -10.0
            var matchedSince: Double?
            while CACurrentMediaTime() - started < 1500 {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                guard let windowScene = scenes.first else { continue }
                let now = CACurrentMediaTime()
                let current = windowScene.effectiveGeometry.interfaceOrientation
                let matches = wantsPortrait ? current.isPortrait : current.isLandscape
                if !matches {
                    matchedSince = nil
                    if reported && !lostLogged {
                        lostLogged = true
                        let shape = PressDirector.windowShape(windowScene, portrait: wantsPortrait)
                        print(String(format: "SQUISH-T orient %@ lost at %.2fs interface=%ld window=%@ screen=%@; re-requesting",
                                     raw, now - self.launchTime, current.rawValue, shape.window, shape.screen))
                    }
                    if now - lastRequest >= 2 {
                        lastRequest = now
                        requests += 1
                        windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
                            print("SQUISH-T orient request error: \(error.localizedDescription)")
                        }
                    }
                } else if !reported {
                    let since = matchedSince ?? now
                    matchedSince = since
                    // Done when the Fold Press canvas has followed (or, with no Fold Press stage, after 5 s matched).
                    if let layout = self.fold.layout {
                        if layout.isBook != wantsPortrait {
                            reported = true
                            let shape = PressDirector.windowShape(windowScene, portrait: wantsPortrait)
                            print(String(format: "SQUISH-T orient %@ ok at %.2fs canvas=%.0fx%.0f layout=%@ interface=%ld window=%@ screen=%@ requests=%ld",
                                         raw, now - self.launchTime, Double(layout.canvas.width),
                                         Double(layout.canvas.height), layout.isBook ? "book" : "tabletop",
                                         current.rawValue, shape.window, shape.screen, requests))
                        }
                    } else {
                        // FOLD-REVIEW-8 N1: with no Fold Press stage (`nofold`, the settings frame 07) the interface
                        // orientation alone said "portrait" while the capture was a 2853 × 2007 landscape screen with
                        // the app in its left half. So the window and the screen must have the wanted shape too
                        // (taller than wide for portrait), for the whole 5 s; until then keep asking.
                        let shape = PressDirector.windowShape(windowScene, portrait: wantsPortrait)
                        if !shape.matches {
                            matchedSince = nil
                            if !shapeLogged {
                                shapeLogged = true
                                print(String(format: "SQUISH-T orient %@ pending at %.2fs: interface=%ld but window=%@ screen=%@; re-requesting",
                                             raw, now - self.launchTime, current.rawValue, shape.window, shape.screen))
                            }
                            if now - lastRequest >= 2 {
                                lastRequest = now
                                requests += 1
                                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
                                    print("SQUISH-T orient request error: \(error.localizedDescription)")
                                }
                            }
                        } else if now - since > 5 {
                            reported = true
                            print(String(format: "SQUISH-T orient %@ ok at %.2fs layout=none interface=%ld window=%@ screen=%@ requests=%ld",
                                         raw, now - self.launchTime, current.rawValue, shape.window, shape.screen,
                                         requests))
                        }
                    }
                } else if self.fold.layout == nil, !lostLogged,
                          !PressDirector.windowShape(windowScene, portrait: wantsPortrait).matches {
                    // Reported, the interface still matches, but the window or screen no longer has the shape.
                    lostLogged = true
                    let shape = PressDirector.windowShape(windowScene, portrait: wantsPortrait)
                    print(String(format: "SQUISH-T orient %@ lost at %.2fs interface=%ld window=%@ screen=%@; re-requesting",
                                 raw, now - self.launchTime, current.rawValue, shape.window, shape.screen))
                    if now - lastRequest >= 2 {
                        lastRequest = now
                        requests += 1
                        windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
                            print("SQUISH-T orient request error: \(error.localizedDescription)")
                        }
                    }
                }
                if !reported, !failedLogged, now - started > 20 {
                    failedLogged = true
                    let shape = PressDirector.windowShape(windowScene, portrait: wantsPortrait)
                    print(String(format: "SQUISH-T orient %@ failed after 20s: interface=%ld layout=%@ window=%@ screen=%@ requests=%ld",
                                 raw, current.rawValue,
                                 self.fold.layout.map { $0.isBook ? "book" : "tabletop" } ?? "none",
                                 shape.window, shape.screen, requests))
                }
            }
        }
    }

    /// The key window's and the screen's bounds (points, as "WxH") and whether both have the wanted shape (taller
    /// than wide for portrait, wider than tall for landscape), for the `orient` hook's log and its no-Fold-Press check
    /// (FOLD-REVIEW-8 N1). No window yet matches neither.
    private static func windowShape(_ scene: UIWindowScene, portrait wantsPortrait: Bool)
        -> (window: String, screen: String, matches: Bool) {
        let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
        let w = window?.bounds.size ?? .zero
        let s = scene.screen.bounds.size
        // The inner display is 669 pt across its short side in either pose; store run 39971788282 logged "ok" for a
        // 469 × 669 window (not the inner display) and the settings frame came out landscape. Require the inner size.
        let innerSized = min(w.width, w.height) >= 600 && min(s.width, s.height) >= 600
        let matches = innerSized && (wantsPortrait ? (w.height > w.width && s.height > s.width)
                                                   : (w.width > w.height && s.width > s.height))
        return (window: String(format: "%.0fx%.0f", Double(w.width), Double(w.height)),
                screen: String(format: "%.0fx%.0f", Double(s.width), Double(s.height)),
                matches: matches)
    }

    /// CI hook (FOLD-REVIEW-6 N5): the settings a store frame shows, so its caption is true of it. `soundstyle=soft`
    /// (workshop | soft), `haptics=soft` (off | soft | full), `captions=on|off`, `nofold` (or `nofold=on|off`: Press
    /// without folding). Applied in memory only, never saved: SettingsView saves on a change it sees after it appears,
    /// and these are set before it exists, so the next CI launch starts from the stored settings again.
    private func applyDemoSettings(_ demo: DemoScenario) {
        var applied: [String] = []
        if let raw = demo.string("soundstyle"), let style = SoundStyle(rawValue: raw) {
            settings.soundStyle = style
            applied.append("soundstyle=\(raw)")
        }
        if let raw = demo.string("haptics"), let level = HapticsLevel(rawValue: raw) {
            settings.hapticsLevel = level
            applied.append("haptics=\(raw)")
        }
        if let raw = demo.string("captions"), raw == "on" || raw == "off" {
            settings.showCaptions = raw == "on"
            applied.append("captions=\(raw)")
        }
        if demo.has("nofold") {
            let on = demo.string("nofold") != "off"
            settings.pressWithoutFolding = on
            engine.usesVirtualHinge = on || !hingeAvailable
            applied.append("nofold=\(on ? "on" : "off")")
        }
        if !applied.isEmpty {
            print("SQUISH-T demo settings \(applied.joined(separator: " ")) (not saved)")
        }
    }

    /// Which store-shot sizes `storeshotsize` asks for: a comma list of portrait | landscape | both | all | 69
    /// (default portrait). Portrait and landscape are the Duo inner display (2007 × 2853 / 2853 × 2007) on a Duo and
    /// the 6.9" sizes (1320 × 2868 / 2868 × 1320) elsewhere; `69` (or `all`) adds a 1320 × 2868 copy of a Duo shot.
    private func storeShotSizes(_ demo: DemoScenario) -> (portrait: Bool, landscape: Bool, sixNine: Bool) {
        let tokens = demo.tokens("storeshotsize")
        func asks(_ names: [String]) -> Bool { names.contains { tokens.contains($0) } }
        let portrait = asks(["portrait", "both", "all"]) || !asks(["landscape", "69"])
        let landscape = asks(["landscape", "both", "all"])
        let sixNine = demo.has("duo") && asks(["69", "all"])
        return (portrait: portrait, landscape: landscape, sixNine: sixNine)
    }

    /// The shared store-shot options: Duo inner size on a Duo, tabletop model, the live eye model, the device at the
    /// captured hinge angle (`storeshotfold=<deg>` overrides it), `storeshotbackdrop=sweep`, `storeshotmodel=asLaid`.
    private func storeShotOptions(_ demo: DemoScenario, angle: Double) -> FoldStoreShot.Options {
        var options = FoldStoreShot.Options()
        options.size = demo.has("duo") ? FoldStoreShot.duoInner : FoldStoreShot.portrait
        options.hingeAngle = clamp(demo.double("storeshotfold") ?? angle, 45, 180)
        options.eyeModel = fold.eye
        if demo.string("storeshotbackdrop") == "sweep" { options.backdrop = .duoSweep }
        if let model = demo.string("storeshotmodel").flatMap(FoldStoreShot.Model.init(rawValue:)) {
            options.model = model
        }
        return options
    }

    /// The store-shot-only 2D splat overlay (FOLD-REVIEW-4 F3), opt-in with `storeshotsplat=overlay`. Off by default:
    /// FoldAnvil now sprays the escaping droplets on the device itself (3D decals at the failure fracture), so the
    /// capture already has them and the overlay would draw them twice.
    private func escapedSplat(_ demo: DemoScenario) -> FoldStoreShot.EscapedSplat? {
        guard demo.string("storeshotsplat") == "overlay", failureFlashCount > 0, let stamp = fold.platen.stack?.stamp,
              FoldStoreShot.EscapedSplat.supports(stamp.kind) else { return nil }
        return FoldStoreShot.EscapedSplat(stamp: stamp)
    }

    /// CI hook (`storeshot`): snapshot the live Fold Press stage and write the folded-device store shots
    /// (FoldStoreShot.swift, FOLD-REVIEW-4 #1/#2) to Documents for ci/screenshots.sh and ci/duo-screenshots.sh:
    ///  • storeshot-<label>.png       Duo inner 2007 × 2853 (1320 × 2868 off-Duo), tabletop model, 3/4 eye at 14°/34°
    ///  • storeshot-<label>-land.png  2853 × 2007 (2868 × 1320), with `storeshotsize=landscape|both|all`
    ///  • storeshot-<label>-69.png    1320 × 2868 copy of a Duo shot, with `storeshotsize=69|all`
    ///  • storeshot-<label>-eye.png   the exact design eye in the layout's own pose, no sheen, caption or splat (the
    ///                                §12 E1/E2 composite; a book capture stands like a book here)
    /// `hero` (label "hero"): the failure freeze with the caption (`storeshotcaption=`); the escaped splat is FoldAnvil's
    /// live spray in the capture (the 2D overlay only with `storeshotsplat=overlay`). Angle
    /// shots keep their halves for the before/after frame. Returns the halves, nil when nothing was captured.
    ///
    /// FOLD-REVIEW-5: the halves carry the crown readout (`storeShotReadout`) for the pair labels; the hero is seen
    /// from the 32° turn (`storeshotazimuth=`), captioned per object, and its halves are also saved for the variety
    /// grid (`saveGridHalves`, Duo only). `reveal` (label "reveal"): the window with its SwiftUI chrome (print label,
    /// Again · Share · Next), captioned "Open up. File the *evidence*." (`revealcaption=`), at the default 14° turn
    /// (`revealazimuth=`) and a 42° elevation (`revealelevation=`), width-fitted with no bleed and centred
    /// (FOLD-REVIEW-7 N4).
    @discardableResult
    private func writeStoreShot(_ demo: DemoScenario, label: String, angle: Double,
                                hero: Bool = false, reveal: Bool = false) async -> FoldStoreShot.Halves? {
        let started = CACurrentMediaTime()
        guard usesFoldPress,
              var halves = await FoldStoreShot.capture(scene: scene, fold: fold, overlays: reveal) else {
            print("SQUISH-T storeshot \(label) failed: no Fold Press stage on screen")
            return nil
        }
        halves.hingeAngle = angle
        halves.readout = storeShotReadout()
        var base = storeShotOptions(demo, angle: angle)
        let tabletopContent = !halves.layout.isBook
        if hero {
            let caption = PressDirector.splitCaption(demo.string("storeshotcaption")
                                                     ?? PressDirector.heroCaption(for: currentKind))
            base.caption = caption.headline
            base.subcaption = caption.subline
            base.escapedSplat = escapedSplat(demo)
            if base.hingeAngle < PressDirector.heroMinimumAngle {
                print(String(format: "SQUISH-T storeshot hero note: model %.1f° raised to %.0f° (inner display dark below ~55°)",
                             base.hingeAngle, PressDirector.heroMinimumAngle))
                base.hingeAngle = PressDirector.heroMinimumAngle
            }
            if tabletopContent {
                let camera = PressDirector.heroCamera(for: currentKind)
                base.azimuthDegrees = demo.double("storeshotazimuth") ?? camera.azimuth
                base.elevationDegrees = demo.double("storeshotelevation") ?? camera.elevation
                base.keyTiltDegrees = demo.double("storeshotkeytilt") ?? camera.keyTilt
                if let bleed = demo.double("storeshotbleed") ?? camera.bleed { base.fit = .width(bleed: bleed) }
                // FOLD-REVIEW-8 N5: the bleed stays 2 % inside the side edges (Options.edgeInset); a negative
                // `storeshotinset=` turns the clamp off to compare with R8.
                if let inset = demo.double("storeshotinset") { base.edgeInset = inset < 0 ? nil : inset }
                // FOLD-REVIEW-6 #1 b, N12: the readout label and V glyph on the hero, hung from the caption band.
                base.angleMark = halves.readout?.label ?? "\(Int(base.hingeAngle.rounded()))°"
                base.anchor = .top(0.03)
            }
            if demo.has("duo") { saveGridHalves(halves) }
            if let readout = halves.readout, readout.frozen, abs(Double(readout.degrees) - base.hingeAngle) > 2 {
                print(String(format: "SQUISH-T storeshot hero note: readout %@ on a %.1f° model; pair label follows the readout",
                             readout.label, base.hingeAngle))
            }
        } else if reveal {
            let caption = PressDirector.splitCaption(demo.string("revealcaption") ?? PressDirector.revealCaption)
            base.caption = caption.headline
            base.subcaption = caption.subline
            if tabletopContent {
                if let turn = demo.double("revealazimuth") { base.azimuthDegrees = turn }
                // FOLD-REVIEW-7 N4: at ~151° the device projects wide and short, so the R6 fit (bleed 0.10, hung from
                // the caption) cut both side edges and left a 16 % floor. Width fit with no bleed, centred in the box
                // under the caption, seen from 42° so the near-flat device projects taller: x 4–96 % (80 px clear each
                // side, hinge spine included), y ≈ 28–90 %, fill ≈ 61 % at 2007 × 2853 (r7tools/framing3.mjs reveal).
                base.fit = .width(bleed: 0)
                base.anchor = .centre
                base.elevationDegrees = demo.double("revealelevation") ?? PressDirector.revealElevation
            }
        }
        let sizes = storeShotSizes(demo)
        let stem = "storeshot-\(label)"
        var variants: [(file: String, options: FoldStoreShot.Options)] = []
        if sizes.portrait {
            variants.append((file: "\(stem).png", options: base))
        }
        if sizes.landscape {
            var landscape = base
            landscape.size = demo.has("duo") ? FoldStoreShot.duoInnerLandscape : FoldStoreShot.landscape
            variants.append((file: "\(stem)-land.png", options: landscape))
        }
        if sizes.sixNine {
            var sixNine = base
            sixNine.size = FoldStoreShot.portrait
            variants.append((file: "\(stem)-69.png", options: sixNine))
        }
        var eyeView = base
        eyeView.eye = .design
        eyeView.model = .asLaid
        eyeView.glassSheen = false
        eyeView.lidShading = false
        eyeView.caption = nil
        eyeView.subcaption = nil
        eyeView.escapedSplat = nil
        eyeView.angleMark = nil
        eyeView.keyTiltDegrees = 0
        eyeView.fit = .contain
        eyeView.targetFill = nil
        eyeView.anchor = .centre
        eyeView.heroBox = CGRect(x: 0.04, y: 0.08, width: 0.92, height: 0.84)
        variants.append((file: "\(stem)-eye.png", options: eyeView))

        var written: [String] = []
        // FOLD-REVIEW-8 N5: the first variant's (the store frame's) device bounds, so ci/store-set.sh can flag a frame
        // whose device leaves it (`inframe=0`), as the duck hero's base corner did at x 0 in R8.
        var deviceFrame = "-"
        var inFrame = 0
        for (index, variant) in variants.enumerated() {
            let image = FoldStoreShot.render(halves, options: variant.options)
            if index == 0 {
                deviceFrame = FoldStoreShot.lastDeviceFramesLabel
                inFrame = FoldStoreShot.lastDevicesInFrame ? 1 : 0
            }
            if writePNG(label: label, file: variant.file, image: image) {
                written.append(variant.file)
            }
        }
        if !hero && !reveal { storeShotHalves[label] = halves }
        let status = written.isEmpty ? "failed:" : "ok"
        // `golden=` / `surprise=` (FOLD-REVIEW-6 N6): ci/store-set.sh refuses a Golden or surprise variant as the
        // representative object; `el=` / `tilt=` record the hero camera.
        let readoutLabel: String = halves.readout?.label ?? "-"
        let azimuthLabel: String = base.azimuthDegrees.map { String(format: "%.0f", $0) } ?? "default"
        let elevationLabel: String = base.elevationDegrees.map { String(format: "%.0f", $0) } ?? "default"
        let surpriseLabel: String = variant.surprise?.rawValue ?? "none"
        let golden: Int = variant.isGolden ? 1 : 0
        let splat: Int = base.escapedSplat == nil ? 0 : 1
        // `frame=` / `inframe=` (FOLD-REVIEW-8 N5) are last, so older parsers of this line still read it.
        print(String(format: "SQUISH-T storeshot %@ %@ at %.2fs hinge=%.1f model=%.1f readout=%@ az=%@ el=%@ tilt=%.0f content=%@ pose=%@ anvil=%@ phase=%@ c=%.3f splat=%ld kind=%@ seed=%llu golden=%ld surprise=%@ files=%@ ms=%.0f frame=%@ inframe=%ld",
                     label, status, CACurrentMediaTime() - launchTime, angle, base.hingeAngle,
                     readoutLabel, azimuthLabel, elevationLabel, base.keyTiltDegrees,
                     halves.layout.isBook ? "book" : "tabletop", base.model.rawValue, halves.source,
                     engine.phase.rawValue, engine.measuredCompression, splat,
                     currentKind.rawValue, variant.seed, golden, surpriseLabel,
                     written.joined(separator: ","), (CACurrentMediaTime() - started) * 1000,
                     deviceFrame, inFrame))
        return written.isEmpty ? nil : halves
    }

    /// CI hook: the before/after frame (FOLD-REVIEW-4 §3.3 C frame 2), storeshot-pair[-land].png, from the angle shot
    /// nearest `storepair` (default 112°) and the hero's halves, captioned `paircaption=` (default "Close your phone.
    /// Feel it *give*.").
    private func writeStorePair(_ demo: DemoScenario, after: FoldStoreShot.Halves) {
        let started = CACurrentMediaTime()
        let wanted = demo.double("storepair") ?? 112
        guard let before = storeShotHalves.values.min(by: {
            abs(($0.hingeAngle ?? 0) - wanted) < abs(($1.hingeAngle ?? 0) - wanted)
        }) else {
            print("SQUISH-T storeshot pair failed: no angle shot to pair with (storeshot=\(Int(wanted)),fail)")
            return
        }
        var options = FoldStoreShot.PairOptions()
        options.before = storeShotOptions(demo, angle: before.hingeAngle ?? wanted)
        options.after = storeShotOptions(demo, angle: after.hingeAngle ?? 62)
        options.after.escapedSplat = escapedSplat(demo)
        if !before.layout.isBook {
            options.before.azimuthDegrees = demo.double("storepairazimuth") ?? PressDirector.standingAzimuth
        }
        if !after.layout.isBook {
            options.after.azimuthDegrees = demo.double("storeshotazimuth") ?? PressDirector.squishAzimuth
        }
        options.backdrop = options.after.backdrop
        let caption = PressDirector.splitCaption(demo.string("paircaption") ?? PressDirector.pairCaption)
        options.caption = caption.headline
        options.subcaption = caption.subline
        let sizes = storeShotSizes(demo)
        var variants: [(file: String, options: FoldStoreShot.PairOptions)] = []
        if sizes.portrait {
            var portrait = options
            portrait.size = demo.has("duo") ? FoldStoreShot.duoInner : FoldStoreShot.portrait
            variants.append((file: "storeshot-pair.png", options: portrait))
        }
        if sizes.landscape {
            var landscape = options
            landscape.size = demo.has("duo") ? FoldStoreShot.duoInnerLandscape : FoldStoreShot.landscape
            variants.append((file: "storeshot-pair-land.png", options: landscape))
        }
        var written: [String] = []
        var deviceFrame = "-"
        var inFrame = 0
        for (index, variant) in variants.enumerated() {
            let image = FoldStoreShot.renderPair(before: before, after: after, options: variant.options)
            if index == 0 {
                deviceFrame = FoldStoreShot.lastDeviceFramesLabel
                inFrame = FoldStoreShot.lastDevicesInFrame ? 1 : 0
            }
            if writePNG(label: "pair", file: variant.file, image: image) {
                written.append(variant.file)
            }
        }
        print(String(format: "SQUISH-T storeshot pair %@ at %.2fs before=%.1f after=%.1f labels=%@|%@ files=%@ ms=%.0f frame=%@ inframe=%ld",
                     written.isEmpty ? "failed:" : "ok", CACurrentMediaTime() - launchTime,
                     options.before.hingeAngle, options.after.hingeAngle,
                     before.readout?.label ?? "model", after.readout?.label ?? "model", written.joined(separator: ","),
                     (CACurrentMediaTime() - started) * 1000, deviceFrame, inFrame))
    }

    /// What the crown readout shows now (FoldBezel.updateReadout): whole degrees of the last Fold Press update's
    /// angle, or the angle it froze on at this object's failure.
    private func storeShotReadout() -> FoldStoreShot.Readout {
        func degrees(_ angle: Double) -> Int { Int(min(max(angle, 0), 180).rounded()) }
        if let frozen = storeShotFrozen, frozen.seed == variant.seed {
            return FoldStoreShot.Readout(degrees: degrees(frozen.angle), frozen: true)
        }
        return FoldStoreShot.Readout(degrees: degrees(storeShotReadoutAngle), frozen: false)
    }

    // MARK: Variety grid (FOLD-REVIEW-5 §5 A6)

    /// Each hero's halves, kept in Documents (`storehalves-<kind>-platen|anvil|crease.png` + `.json`) so a later
    /// launch can put several objects on one frame. ci/duo-screenshots.sh only clears `storeshot-*.png` between
    /// objects, so these survive until the grid launch.
    private func saveGridHalves(_ halves: FoldStoreShot.Halves) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let stem = "storehalves-\(currentKind.rawValue)"
        func save(_ image: CGImage?, _ part: String) {
            guard let image, let png = UIImage(cgImage: image).pngData() else { return }
            try? png.write(to: documents.appendingPathComponent("\(stem)-\(part).png"), options: .atomic)
        }
        save(halves.platen, "platen")
        save(halves.anvil, "anvil")
        save(halves.crease, "crease")
        let layout = halves.layout
        var meta: [String: Any] = [
            "kind": currentKind.rawValue,
            "canvasWidth": Double(layout.canvas.width),
            "canvasHeight": Double(layout.canvas.height),
            "axisPosition": layout.axisPosition,
            "hingeAngle": halves.hingeAngle ?? 62,
        ]
        if let readout = halves.readout {
            meta["readout"] = readout.degrees
            meta["frozen"] = readout.frozen
        }
        if let data = try? JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted]) {
            try? data.write(to: documents.appendingPathComponent("\(stem).json"), options: .atomic)
        }
    }

    private func loadGridHalves(_ kind: ObjectKind) -> FoldStoreShot.Halves? {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let stem = "storehalves-\(kind.rawValue)"
        func image(_ part: String) -> CGImage? {
            UIImage(contentsOfFile: documents.appendingPathComponent("\(stem)-\(part).png").path)?.cgImage
        }
        guard let data = try? Data(contentsOf: documents.appendingPathComponent("\(stem).json")),
              let meta = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let width = (meta["canvasWidth"] as? NSNumber)?.doubleValue,
              let height = (meta["canvasHeight"] as? NSNumber)?.doubleValue,
              let platen = image("platen"), let anvil = image("anvil") else { return nil }
        let axis = (meta["axisPosition"] as? NSNumber)?.doubleValue
        let layout = FoldLayout(canvas: CGSize(width: width, height: height), foldLine: axis)
        var halves = FoldStoreShot.Halves(platen: platen, crease: image("crease"), anvil: anvil, layout: layout,
                                          source: "saved")
        halves.hingeAngle = (meta["hingeAngle"] as? NSNumber)?.doubleValue
        if let degrees = (meta["readout"] as? NSNumber)?.intValue {
            halves.readout = FoldStoreShot.Readout(degrees: degrees, frozen: (meta["frozen"] as? NSNumber)?.boolValue ?? false)
        }
        return halves
    }

    /// CI hook (`duo;storegrid=rubberDuck,egg,cakeSlice,sodaCan`): the variety frame, storeshot-grid.png, from the
    /// heroes saved by earlier tabletop passes, each at its own hold angle from the 32° turn, labelled
    /// "EGG · AT 97°" (its frozen readout), captioned "*Ten* objects. Ten ways to give." (`gridcaption=`). Objects
    /// with no saved hero are skipped (logged as missing). Logs `SQUISH-T storeshot grid ok|failed` and `… done`.
    private func writeStoreGrid(_ demo: DemoScenario) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard let self else { return }
            let started = CACurrentMediaTime()
            var items: [FoldStoreShot.GridItem] = []
            var missing: [String] = []
            for token in demo.tokens("storegrid") {
                guard let kind = ObjectKind(rawValue: token), let halves = self.loadGridHalves(kind) else {
                    missing.append(token)
                    continue
                }
                var device = self.storeShotOptions(demo, angle: halves.hingeAngle ?? 62)
                if !halves.layout.isBook {
                    device.azimuthDegrees = demo.double("storeshotazimuth") ?? PressDirector.squishAzimuth
                }
                let name = kind.displayName.uppercased()
                let label = halves.readout.map { "\(name) · \($0.label)" } ?? name
                items.append(FoldStoreShot.GridItem(halves: halves, options: device, label: label))
            }
            var options = FoldStoreShot.GridOptions()
            options.size = FoldStoreShot.duoInner
            if demo.string("storeshotbackdrop") == "sweep" { options.backdrop = .duoSweep }
            let caption = PressDirector.splitCaption(demo.string("gridcaption") ?? PressDirector.gridCaption)
            options.caption = caption.headline
            options.subcaption = caption.subline
            let image = items.isEmpty ? nil : FoldStoreShot.renderGrid(items, options: options)
            let deviceFrame = items.isEmpty ? "-" : FoldStoreShot.lastDeviceFramesLabel
            let inFrame: Int = !items.isEmpty && FoldStoreShot.lastDevicesInFrame ? 1 : 0
            let ok = self.writePNG(label: "grid", file: "storeshot-grid.png", image: image)
            print(String(format: "SQUISH-T storeshot grid %@ at %.2fs objects=%ld missing=%@ ms=%.0f frame=%@ inframe=%ld",
                         ok ? "ok" : "failed:", CACurrentMediaTime() - self.launchTime, items.count,
                         missing.joined(separator: ","), (CACurrentMediaTime() - started) * 1000,
                         deviceFrame, inFrame))
            print(String(format: "SQUISH-T storeshot done at %.2fs missing=%@", CACurrentMediaTime() - self.launchTime,
                         ok ? "" : "grid"))
        }
    }

    /// Write one rendered store shot to Documents; false (and a log line) when it didn't render or write.
    private func writePNG(label: String, file: String, image: UIImage?) -> Bool {
        guard let image, let png = image.pngData() else {
            print("SQUISH-T storeshot \(label) render failed: \(file)")
            return false
        }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        do {
            try png.write(to: documents.appendingPathComponent(file), options: .atomic)
            return true
        } catch {
            print("SQUISH-T storeshot \(label) write failed: \(file) \(error.localizedDescription)")
            return false
        }
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
