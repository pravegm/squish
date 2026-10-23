import Testing
@testable import Squish

@MainActor
final class EventLog {
    var events: [PressEvent] = []

    func count(where predicate: (PressEvent) -> Bool) -> Int {
        events.filter(predicate).count
    }

    func fractureIndices() -> [Int] {
        events.compactMap { event -> Int? in
            if case let .fracture(index, _) = event { return index }
            return nil
        }
    }
}

@MainActor
struct PressEngineTests {
    let rate = 30.0

    private func makeEngine(_ kind: ObjectKind, log: EventLog, config: PressConfig = .standard) -> PressEngine {
        let engine = PressEngine(config: config)
        engine.onEvent = { log.events.append($0) }
        engine.ingest(angle: 180, closed: false, at: 0)
        engine.load(kind, seed: 42, at: 0)
        return engine
    }

    /// Feeds hinge samples at `rate` Hz, stepping the engine between them, and returns the end time.
    @discardableResult
    private func sweep(_ engine: PressEngine, from start: Double, to end: Double, duration: Double,
                       startTime: Double, closedAtEnd: Bool = false, closed: Bool = false) -> Double {
        let steps = max(Int(duration * rate), 1)
        var time = startTime
        for i in 1...steps {
            time = startTime + Double(i) / rate
            let angle = start + (end - start) * Double(i) / Double(steps)
            engine.ingest(angle: angle, closed: closed || (closedAtEnd && i == steps), at: time)
            engine.step(now: time, dt: 1 / rate)
        }
        return time
    }

    private func hold(_ engine: PressEngine, at angle: Double, seconds: Double, startTime: Double) -> Double {
        sweep(engine, from: angle, to: angle, duration: seconds, startTime: startTime)
    }

    @Test func mappingIsMonotonicAndHitsContactAndBottom() {
        let config = PressConfig.standard
        #expect(PressMapping.depth(angle: 165, start: 165, config: config) == 0)
        #expect(abs(PressMapping.depth(travel: config.contactT, config: config) - config.contactT) < 1e-9)
        #expect(PressMapping.depth(angle: config.endAngle, start: 165, config: config) == 1)
        var previous = -1.0
        for angle in stride(from: 165.0, through: 40.0, by: -1) {
            let depth = PressMapping.depth(angle: angle, start: 165, config: config)
            #expect(depth >= previous)
            previous = depth
        }
    }

    @Test func doesNotArmDuringActivationWindow() {
        let log = EventLog()
        let engine = PressEngine()
        engine.onEvent = { log.events.append($0) }
        engine.activate(at: 0)
        engine.load(.bubbleWrap, seed: 1, at: 0)
        engine.ingest(angle: 180, closed: false, at: 0.5)
        #expect(engine.phase == .idle)
        engine.ingest(angle: 180, closed: false, at: 2.0)
        #expect(engine.phase == .armed)
    }

    @Test func slowBubbleWrapPressPopsEveryBubbleOnceAndSeals() {
        let log = EventLog()
        let engine = makeEngine(.bubbleWrap, log: log)
        #expect(engine.phase == .armed)
        var time = sweep(engine, from: 180, to: 40, duration: 6, startTime: 0)
        time = hold(engine, at: 40, seconds: 0.5, startTime: time)
        #expect(engine.phase == .sealed)
        let indices = log.fractureIndices()
        #expect(indices == Array(0..<BubbleWrapLayout.count))
        #expect(log.count { $0 == .contact } == 1)
        #expect(log.count { $0 == .bottomOut } == 1)
        #expect(engine.lastResult?.fractureCount == BubbleWrapLayout.count)
    }

    @Test func wobblingNeverRefiresAFracture() {
        let log = EventLog()
        let engine = makeEngine(.rubberDuck, log: log)
        // Find an angle just past the first duck fracture.
        let target = engine.thresholds[0] + 0.03
        var angle = 165.0
        while PressMapping.compression(depth: PressMapping.depth(angle: angle, start: engine.startAngle, config: engine.mapping),
                                       config: engine.mapping) < target {
            angle -= 0.5
        }
        var time = sweep(engine, from: 180, to: angle, duration: 3, startTime: 0)
        for _ in 0..<10 {
            time = sweep(engine, from: angle, to: angle + 8, duration: 0.3, startTime: time)
            time = sweep(engine, from: angle + 8, to: angle, duration: 0.3, startTime: time)
        }
        #expect(log.fractureIndices() == [0])
    }

    @Test func failureIsPrecededByHushAndDelayed() {
        let log = EventLog()
        let engine = makeEngine(.rubberDuck, log: log)
        var time = sweep(engine, from: 180, to: 62, duration: 5, startTime: 0)
        time = hold(engine, at: 62, seconds: 0.3, startTime: time)
        guard let hushIndex = log.events.firstIndex(of: .hush),
              let failureIndex = log.events.firstIndex(of: .fracture(index: 1, isFailure: true)) else {
            Issue.record("Expected a hush and a failure, got \(log.events)")
            return
        }
        #expect(hushIndex < failureIndex)
        #expect(log.count { $0 == .preFailureTell } == 1)
    }

    @Test func closingMidPressSealsBlindAndFinishesTheCrush() {
        let log = EventLog()
        let engine = makeEngine(.bubbleWrap, log: log)
        var time = sweep(engine, from: 180, to: 110, duration: 2, startTime: 0)
        #expect(engine.phase == .pressing)
        time = sweep(engine, from: 110, to: 5, duration: 0.2, startTime: time, closedAtEnd: true)
        #expect(engine.phase == .sealed)
        #expect(log.events.contains(.sealed(blind: true)) || log.events.contains(.sealed(blind: false)))
        #expect(log.count { $0 == .kaChunk } == 1)
        #expect(log.fractureIndices().count == BubbleWrapLayout.count)
        _ = time
    }

    /// Store run 39895066549: the Duo simulator kept reporting `.closed` all the way back open to 151°, so no sealed
    /// press ever revealed. A `.closed` status the angle contradicts (> 90°) is stale and must not block the reveal.
    @Test func staleClosedStatusOnReopenStillReveals() {
        let log = EventLog()
        let engine = makeEngine(.rubberDuck, log: log)
        var time = sweep(engine, from: 180, to: 5, duration: 4, startTime: 0, closedAtEnd: true)
        #expect(engine.phase == .sealed)
        time = sweep(engine, from: 0, to: 151, duration: 3, startTime: time, closed: true)
        time = sweep(engine, from: 151, to: 151, duration: 0.5, startTime: time, closed: true)   // never reports open
        _ = time
        #expect(engine.phase == .revealing)
        #expect(log.count { $0 == .reveal } == 1)
    }

    @Test func reopeningAfterSealReveals() {
        let log = EventLog()
        let engine = makeEngine(.rubberDuck, log: log)
        var time = sweep(engine, from: 180, to: 5, duration: 4, startTime: 0, closedAtEnd: true)
        #expect(engine.phase == .sealed)
        // Opening reports .closed until ~150° in the simulator; reveal waits for an open status.
        time = sweep(engine, from: 5, to: 150, duration: 1, startTime: time)
        time = sweep(engine, from: 150, to: 170, duration: 0.5, startTime: time)
        #expect(engine.phase == .revealing)
        #expect(log.count { $0 == .reveal } == 1)
    }

    @Test func plasticDamageSurvivesReopening() {
        let log = EventLog()
        let engine = makeEngine(.bubbleWrap, log: log)
        var time = sweep(engine, from: 180, to: 90, duration: 3, startTime: 0)
        let depthAtBottom = engine.measuredDepth
        time = sweep(engine, from: 90, to: 175, duration: 1, startTime: time)
        time = hold(engine, at: 175, seconds: 1, startTime: time)
        #expect(engine.visualDepth >= depthAtBottom * MaterialProfile.bubbleWrap.plasticity - 1e-9)
        #expect(engine.renderDepth < engine.visualDepth)
    }

    @Test func touchFallbackSealsKaChunksAndAutoReveals() {
        let log = EventLog()
        let engine = makeEngine(.rubberDuck, log: log)
        engine.usesVirtualHinge = true
        var time = 0.0
        for i in 0...150 {
            time = Double(i) / rate
            engine.setVirtualAngle(180 - Double(i) * 1.2, at: time)
            engine.step(now: time, dt: 1 / rate)
        }
        for i in 1...40 {
            time += 1 / rate
            engine.step(now: time, dt: 1 / rate)
            _ = i
        }
        #expect(log.count { $0 == .kaChunk } == 1)
        #expect(engine.phase == .revealing)
    }

    // MARK: - FOLD-REVIEW-6 N3: launching with the phone shut

    /// The director's cold launch on a Duo: the touch press is assumed until a hinge reports in, the object is placed
    /// and frames run, then the first hinge sample arrives (duo-cover-launch.txt: `SQUISH-H 4.73 0.0 1`, after
    /// `frame 1 at 1.01s phase=armed`). Returns the engine as of that first sample's time, not yet fed.
    private func coldLaunch(_ log: EventLog, ignoreInput: Double) -> PressEngine {
        var config = PressConfig.standard
        config.ignoreInputAfterActivation = ignoreInput
        let engine = PressEngine(config: config)
        engine.onEvent = { log.events.append($0) }
        engine.activate(at: 0)
        engine.usesVirtualHinge = true
        engine.load(.rubberDuck, seed: 42, at: 0)
        var time = 0.0
        for _ in 0..<282 {   // 4.7 s of frames at 60 Hz before any hinge sample
            time += 1.0 / 60
            engine.step(now: time, dt: 1.0 / 60)
        }
        engine.usesVirtualHinge = false   // hingeUpdate, on the first sample
        return engine
    }

    private func sealCount(_ log: EventLog) -> Int {
        log.count { $0 == .sealed(blind: true) || $0 == .sealed(blind: false) }
    }

    @Test func closedAtLaunchNeverArmsCompressesOrSeals() {
        for ignoreInput in [0.0, 1.5] {   // the CI demo zeroes the activation window; the app keeps 1.5 s
            let log = EventLog()
            let engine = coldLaunch(log, ignoreInput: ignoreInput)
            var time = 4.73
            engine.ingest(angle: 0, closed: true, at: time)
            #expect(engine.phase == .idle)
            // Lying shut: frames keep running and the odd repeat sample arrives.
            for i in 1...180 {
                time += 1.0 / 60
                if i % 30 == 0 { engine.ingest(angle: 0, closed: true, at: time) }
                engine.step(now: time, dt: 1.0 / 60)
            }
            #expect(engine.phase == .idle)
            #expect(engine.lastResult == nil)
            #expect(engine.measuredDepth == 0)
            #expect(engine.visualDepth == 0)
            #expect(sealCount(log) == 0)
            #expect(log.count { $0 == .kaChunk || $0 == .contact || $0 == .bottomOut } == 0)
            #expect(log.fractureIndices().isEmpty)
        }
    }

    /// The mirror case: open the phone after that launch. It must arm (from the open reading) and nothing else:
    /// no phantom seal, no reveal, no specimen. Then a real press still works.
    @Test func reopeningAfterAClosedLaunchArmsWithoutAPhantomSpecimen() {
        // The simulator keeps `.closed` until ~150° on the way open; a real hinge may clear it much earlier.
        for flagClearsAt in [150.0, 10.0] {
            let log = EventLog()
            let engine = coldLaunch(log, ignoreInput: 0)
            var time = 4.73
            engine.ingest(angle: 0, closed: true, at: time)
            time = sweep(engine, from: 0, to: flagClearsAt, duration: 1.2, startTime: time, closed: true)
            // A stale `.closed` above 90° counts as open, so a phone that is really open may already have armed.
            #expect(engine.phase == .idle || engine.phase == .armed)
            #expect(engine.measuredDepth == 0)
            time = sweep(engine, from: flagClearsAt, to: 170, duration: 0.8, startTime: time)
            time = hold(engine, at: 170, seconds: 1, startTime: time)
            #expect(engine.phase == .armed)
            #expect(engine.measuredDepth == 0)
            #expect(engine.lastResult == nil)
            #expect(sealCount(log) == 0)
            #expect(log.count { $0 == .reveal || $0 == .contact || $0 == .kaChunk } == 0)

            time = sweep(engine, from: 170, to: 5, duration: 4, startTime: time, closedAtEnd: true)
            #expect(engine.phase == .sealed)
            #expect(sealCount(log) == 1)
            time = sweep(engine, from: 5, to: 170, duration: 1, startTime: time)
            #expect(engine.phase == .revealing)
            #expect(log.count { $0 == .reveal } == 1)
        }
    }

    /// Launched half-folded (tabletop at 100°): the touch press's early arm must not turn into a deep phantom press.
    @Test func launchHalfOpenDropsTheProvisionalArm() {
        let log = EventLog()
        let engine = coldLaunch(log, ignoreInput: 0)
        let time = hold(engine, at: 100, seconds: 1, startTime: 4.73)
        #expect(engine.phase == .idle)
        #expect(engine.measuredDepth == 0)
        #expect(log.count { $0 == .contact } == 0)
        #expect(log.fractureIndices().isEmpty)
        _ = time
    }

    /// Still allowed: an arm on an observed open hinge, slammed shut between two samples, seals blind.
    @Test func slamShutBetweenTwoSamplesStillSeals() {
        let log = EventLog()
        let engine = makeEngine(.rubberDuck, log: log)
        var time = hold(engine, at: 170, seconds: 0.5, startTime: 0)
        #expect(engine.phase == .armed)
        time += 0.2
        engine.ingest(angle: 0, closed: true, at: time)
        #expect(engine.phase == .sealed)
        #expect(sealCount(log) == 1)
        #expect(log.count { $0 == .kaChunk } == 1)
    }

    // MARK: - FOLD-REVIEW-6 N2: fold-to-collect on the reveal card

    /// Feeds the gate its samples in time order, polling at 60 Hz in between (the director's deadline recheck),
    /// and returns the time of the first collect, or nil if nothing collects by `end`.
    private func firstCollect(_ gate: inout RevealCollectGate, _ samples: [(time: Double, angle: Double, closed: Bool)],
                              until end: Double) -> Double? {
        var index = 0
        var time = gate.start
        while time <= end {
            while index < samples.count, samples[index].time <= time {
                let sample = samples[index]
                index += 1
                if gate.ingest(angle: sample.angle, closed: sample.closed, at: sample.time) { return sample.time }
            }
            if gate.shouldCollect(at: time) { return time }
            time += 1.0 / 60
        }
        return nil
    }

    /// Samples at `hz` from `start` to `end` over [t0, t1].
    private func ramp(_ start: Double, _ end: Double, from t0: Double, to t1: Double, closed: Bool = false,
                      hz: Double = 30) -> [(time: Double, angle: Double, closed: Bool)] {
        let steps = max(Int((t1 - t0) * hz), 1)
        return (1...steps).map { i in
            let f = Double(i) / Double(steps)
            return (time: t0 + (t1 - t0) * f, angle: start + (end - start) * f, closed: closed)
        }
    }

    /// The R6 pattern (cakeSlice-tabletop.txt l.227–250, relative to the reveal at 339.81 s): revealed on `20.1 0`,
    /// then `24.8 1` while the hinge is still opening, and `closed` stays set up to ~92°. None of it may collect.
    @Test func strayClosedSampleDuringRevealDoesNotCollect() {
        var gate = RevealCollectGate(start: 0, angle: 20.1)
        var samples: [(time: Double, angle: Double, closed: Bool)] = [
            (time: 0.63, angle: 23.6, closed: false),
            (time: 1.23, angle: 24.5, closed: false),
            (time: 2.10, angle: 24.8, closed: true),
        ]
        samples += ramp(24.8, 92.5, from: 2.10, to: 10.21, closed: true, hz: 10)
        samples += ramp(92.5, 151, from: 10.21, to: 11.7)
        samples += ramp(151, 151, from: 11.7, to: 15)
        #expect(firstCollect(&gate, samples, until: 15) == nil)
        #expect(gate.hasBeenSeen)
    }

    @Test func isolatedClosedSampleOrBriefDipDoesNotCollect() {
        // Open at 151°: one `closed` sample that still reads 151° (a misread), then the hinge goes quiet.
        var gate = RevealCollectGate(start: 0, angle: 151)
        var samples = ramp(151, 151, from: 0, to: 2)
        samples.append((time: 2.03, angle: 151, closed: true))
        #expect(firstCollect(&gate, samples, until: 4) == nil)

        // A brief dip: 23° below the peak for 0.15 s, then back up.
        var dipped = RevealCollectGate(start: 0, angle: 151)
        var dip = ramp(151, 151, from: 0, to: 2)
        dip += ramp(128, 128, from: 2, to: 2.15)
        dip += ramp(151, 151, from: 2.15, to: 4)
        #expect(firstCollect(&dipped, dip, until: 4) == nil)
    }

    @Test func nothingCollectsInTheFirstMomentAfterTheReveal() {
        // Revealed at 160° (sealed and left open), folded away at once and held there.
        var gate = RevealCollectGate(start: 0, angle: 160)
        var samples = ramp(160, 120, from: 0, to: 0.1)
        samples += ramp(120, 120, from: 0.1, to: 2)
        let collected = firstCollect(&gate, samples, until: 2)
        #expect(collected != nil)
        #expect((collected ?? 0) >= RevealCollectGate.settle - 1e-9)
        #expect((collected ?? 9) < RevealCollectGate.settle + 0.05)
    }

    @Test func deliberateCloseCollects() {
        // Card up at 150° for 1.5 s, then the phone is closed over 0.4 s and lies shut (no more samples).
        var gate = RevealCollectGate(start: 0, angle: 150)
        var samples = ramp(150, 150, from: 0, to: 1.5)
        samples += ramp(150, 0, from: 1.5, to: 1.9)
        samples[samples.count - 1].closed = true
        let collected = firstCollect(&gate, samples, until: 4)
        let foldStart = 1.5 + 0.4 * RevealCollectGate.foldTravel / 150
        #expect(collected != nil)
        #expect((collected ?? 0) >= foldStart + RevealCollectGate.foldHold - 0.04)
        #expect((collected ?? 9) <= 1.9 + RevealCollectGate.closedHold + 0.02)
    }

    @Test func slamShutCollectsWithoutFurtherSamples() {
        // Two samples: still open, then shut. The Duo sends nothing more, so only the deadline recheck can collect.
        var gate = RevealCollectGate(start: 0, angle: 150)
        var samples = ramp(150, 150, from: 0, to: 2)
        samples.append((time: 2.0, angle: 140, closed: false))
        samples.append((time: 2.05, angle: 0, closed: true))
        let collected = firstCollect(&gate, samples, until: 4)
        #expect(collected != nil)
        #expect((collected ?? 0) >= 2.05 + RevealCollectGate.foldHold - 1e-9)
        #expect((collected ?? 9) <= 2.05 + RevealCollectGate.closedHold + 0.02)
    }

    @Test func closedHeldCollectsEvenWithoutMuchTravel() {
        // Card seen at 100°, then `closed` held at 85° (15° of travel, short of the fold rule): the close rule collects.
        var gate = RevealCollectGate(start: 0, angle: 100)
        var samples = ramp(100, 100, from: 0, to: 1)
        samples += ramp(85, 85, from: 1, to: 2, closed: true)
        let collected = firstCollect(&gate, samples, until: 2)
        #expect(collected != nil)
        #expect((collected ?? 0) >= 1 + RevealCollectGate.closedHold - 0.04)
        #expect((collected ?? 9) <= 1 + RevealCollectGate.closedHold + 0.1)
    }
}
