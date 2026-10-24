import Testing
@testable import Squish
import Foundation

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

    // MARK: - The press, beat by beat (design/EXPERIENCE-PLAN.md; Core/PressFeel.swift)

    /// Events and beats with the time they arrived, for a hinge press fed at `rate` Hz.
    @MainActor
    final class Timeline {
        var now = 0.0
        var events: [(time: Double, event: PressEvent)] = []
        var beats: [(time: Double, beat: PressBeat)] = []
        func time(of event: PressEvent) -> Double? { events.first { $0.event == event }?.time }
        func count(_ predicate: (PressBeat) -> Bool) -> Int { beats.filter { predicate($0.beat) }.count }
    }

    private func timedEngine(_ kind: ObjectKind, _ timeline: Timeline) -> PressEngine {
        let engine = PressEngine()
        engine.onEvent = { timeline.events.append((time: timeline.now, event: $0)) }
        engine.onBeat = { timeline.beats.append((time: timeline.now, beat: $0)) }
        engine.ingest(angle: 180, closed: false, at: 0)
        engine.load(kind, seed: 42, at: 0)
        return engine
    }

    @discardableResult
    private func drive(_ engine: PressEngine, _ timeline: Timeline, from start: Double, to end: Double,
                       duration: Double, startTime: Double, closedAtEnd: Bool = false, closed: Bool = false) -> Double {
        let steps = max(Int(duration * rate), 1)
        var time = startTime
        for i in 1...steps {
            time = startTime + Double(i) / rate
            timeline.now = time
            engine.ingest(angle: start + (end - start) * Double(i) / Double(steps), closed: closed || (closedAtEnd && i == steps),
                          at: time)
            engine.step(now: time, dt: 1 / rate)
        }
        return time
    }

    /// The hinge angle (on this press's mapping) at hand compression `c`.
    private func angle(_ engine: PressEngine, compression c: Double) -> Double {
        let m = engine.mapping
        return PressMapping.angle(forDepth: m.contactT + (1 - m.contactT) * c, start: engine.startAngle, config: m)
    }

    private static func isHitStop(_ beat: PressBeat) -> Bool {
        if case .hitStop = beat { return true }
        return false
    }

    private static func isDebris(_ beat: PressBeat) -> Bool {
        if case .debris = beat { return true }
        return false
    }

    private static func isSettleTick(_ beat: PressBeat) -> Bool {
        if case .settleTick = beat { return true }
        return false
    }

    private static func isCreak(_ beat: PressBeat) -> Bool {
        if case .creak = beat { return true }
        return false
    }

    private static func detentAngle(_ beat: PressBeat, closing: Bool) -> Double? {
        if case let .detent(angle, isClosing, _) = beat, isClosing == closing { return angle }
        return nil
    }

    /// Lag, then give: near the failure the eye falls behind the hand while measured depth stays honest; at the
    /// burst the backlog is released within ~80 ms (plus the render spring).
    @Test func lagThenGiveIsRenderSideOnly() throws {
        let timeline = Timeline()
        let engine = timedEngine(.glassBottle, timeline)
        let failure = try #require(engine.failureThreshold)
        let target = failure - 0.02
        let held = angle(engine, compression: target)
        var time = drive(engine, timeline, from: 180, to: held, duration: 3, startTime: 0)
        time = drive(engine, timeline, from: held, to: held, duration: 0.6, startTime: time)
        #expect(engine.phase == .pressing)
        #expect(abs(engine.measuredCompression - target) < 0.01)   // the hand, exactly
        #expect(timeline.time(of: .hush) == nil)
        let backlog = engine.resistance.backlog(failure: failure)
        #expect(backlog > 0.05)
        #expect(engine.renderCompression < engine.measuredCompression - 0.05)
        #expect(abs(engine.eyeCompression(engine.measuredCompression) - engine.renderCompression) < 0.01)
        // Through the failure: hush, hit stop (frozen), burst, then the give catches up with the hand.
        let past = angle(engine, compression: failure + 0.05)
        time = drive(engine, timeline, from: held, to: past, duration: 0.2, startTime: time)
        time = drive(engine, timeline, from: past, to: past, duration: 0.6, startTime: time)
        let burst = try #require(timeline.time(of: .fracture(index: 1, isFailure: true)))
        #expect(time - burst > 0.25)
        #expect(abs(engine.renderCompression - engine.measuredCompression) < 0.01)
        // The material ordering of the lag: glass deepest, jelly almost none, bubble wrap none.
        #expect(PressResistance.of(.glassBottle).gain < PressResistance.of(.rubberDuck).gain)
        #expect(PressResistance.of(.rubberDuck).gain < PressResistance.of(.jelly).gain)
        #expect(!PressResistance.of(.bubbleWrap).lags)
    }

    @Test func resistanceMathIsContinuousMonotonicAndGives() {
        for kind in ObjectKind.allCases {
            let r = PressResistance.of(kind)
            let f = 0.5
            var previous = -1.0
            for i in 0...200 {
                let c = Double(i) / 200
                let v = r.lagged(c, failure: f)
                #expect(v <= c + 1e-12 && v >= previous - 1e-12, "\(kind) c=\(c)")
                previous = v
            }
            // Continuous at the window start; the give lands on the hand at `give`, ease-out (past halfway at half).
            #expect(abs(r.lagged(f - r.window, failure: f) - (f - r.window)) < 1e-12)
            #expect(r.released(from: 0.4, to: 0.6, after: r.give) == 0.6)
            #expect(r.released(from: 0.4, to: 0.6, after: r.give / 2) > 0.5)
        }
    }

    /// The break scored in five parts: hush 50–80 ms, hit stop 70–140 ms, burst, debris at 0.3× for 250–400 ms, a
    /// 1–2 s settle. The burst lands hush + hit stop after the crossing, and the beats come in order.
    @Test func breakIsScoredInFiveParts() throws {
        for kind in ObjectKind.allCases {
            let score = BreakScore.of(kind)
            #expect(BreakScore.hushRange.contains(score.hush))
            #expect(score.hitStop >= 0.07 && score.hitStop <= 0.14, "\(kind)")
            #expect(score.slowDebris >= 0.25 && score.slowDebris <= 0.4 && score.slowRate == 0.3, "\(kind)")
            #expect(score.settle >= 1 && score.settle <= 2, "\(kind)")
            #expect((3...6).contains(score.debrisGrains) && (4...8).contains(score.settleTicks), "\(kind)")
            let beats = score.beatsAfterBurst()
            #expect(zip(beats, beats.dropFirst()).allSatisfy { $0.time <= $1.time })
            #expect(score.phase(at: 0.01) == .hush && score.phase(at: score.hush + 0.01) == .hitStop)
            #expect(score.phase(at: score.burst + 0.01) == .slowDebris)
            #expect(score.phase(at: score.slowEnd + 0.01) == .settle)
            #expect(score.phase(at: score.end + 0.01) == .none)
        }
        #expect(BreakScore.of(.egg, hush: 0.2).hush == 0.08 && BreakScore.of(.egg, hush: 0).hush == 0.05)

        let timeline = Timeline()
        let engine = timedEngine(.rubberDuck, timeline)
        let score = engine.breakScore
        var time = drive(engine, timeline, from: 180, to: 60, duration: 5, startTime: 0)
        time = drive(engine, timeline, from: 60, to: 60, duration: 3, startTime: time)
        _ = time
        let hush = try #require(timeline.time(of: .hush))
        let burst = try #require(timeline.time(of: .fracture(index: 1, isFailure: true)))
        #expect(burst - hush >= score.burst - 1e-6 && burst - hush <= score.burst + 1 / rate + 1e-6)
        let hitStop = try #require(timeline.beats.first { Self.isHitStop($0.beat) })
        #expect(hitStop.time >= hush + score.hush - 1e-6 && hitStop.time <= burst + 1e-6)
        #expect(timeline.count(Self.isDebris) == score.debrisGrains)
        #expect(timeline.count(Self.isSettleTick) == score.settleTicks)
        #expect(timeline.count { $0 == .settle(duration: score.settle) } == 1)
        #expect(timeline.count { $0 == .settled } == 1)
        // The failure is where the lid is near and the display lit.
        let failureAngle = try #require(engine.failureAngle)
        #expect(failureAngle >= PressFeel.failureFloorAngle && failureAngle <= 100)
    }

    /// The tell lands ~150–300 ms before the break at a steady close (here 20°/s), and before the burst for a slam.
    @Test func tellLeadsTheBreak() throws {
        for kind: ObjectKind in [.glassBottle, .egg, .rubberDuck] {
            let timeline = Timeline()
            let engine = timedEngine(kind, timeline)
            drive(engine, timeline, from: 180, to: 50, duration: 6.5, startTime: 0)
            let tell = try #require(timeline.time(of: .preFailureTell), "\(kind)")
            let hush = try #require(timeline.time(of: .hush), "\(kind)")
            #expect(hush - tell >= 0.1 && hush - tell <= 0.35, "\(kind): \(hush - tell) s")
        }
        let timeline = Timeline()
        let engine = timedEngine(.glassBottle, timeline)
        drive(engine, timeline, from: 180, to: 50, duration: 0.4, startTime: 0)
        drive(engine, timeline, from: 50, to: 50, duration: 0.5, startTime: 0.4)
        let tell = try #require(timeline.time(of: .preFailureTell))
        let burst = try #require(timeline.time(of: .fracture(index: 1, isFailure: true)))
        #expect(burst - tell >= engine.breakScore.burst - 1e-6)
    }

    /// Tension you can hold: held still under load, the tension never decays, the press creaks every 0.6–1.2 s, and
    /// the strain-bed floor stays above 0.
    @Test func heldPressKeepsItsTension() throws {
        let timeline = Timeline()
        let engine = timedEngine(.rubberDuck, timeline)
        let failure = try #require(engine.failureThreshold)
        let held = angle(engine, compression: failure * 0.6)
        var time = drive(engine, timeline, from: 180, to: held, duration: 3, startTime: 0)
        time = drive(engine, timeline, from: held, to: held, duration: 1, startTime: time)
        let early = engine.tension
        let creaksBefore = timeline.count(Self.isCreak)
        time = drive(engine, timeline, from: held, to: held, duration: 5, startTime: time)
        #expect(engine.isHeldUnderLoad)
        #expect(early > 0.2 && engine.tension >= early - 1e-3)   // never decays on the hold
        #expect(engine.holdBedFloor > 0)
        let creaks = timeline.count(Self.isCreak) - creaksBefore
        #expect(creaks >= 4 && creaks <= 9, "\(creaks) creaks in 5 s")
        // Through the failure the cadence ends for good.
        time = drive(engine, timeline, from: held, to: 50, duration: 2, startTime: time)
        time = drive(engine, timeline, from: 50, to: 50, duration: 2, startTime: time)
        _ = time
        #expect(!engine.isHeldUnderLoad)
    }

    /// How you closed it becomes the stamp: SLAMMED (gently, a nudge) over PERFECT over PRESSED. Pumping earns nothing
    /// (App Review 2.4.2: no incentive for repeated hinge cycling).
    @Test func closeStyleComesFromTheResult() {
        var result = PressResult(kind: .egg, seed: 1, failureAngle: 80, fractureCount: 3, maxCompression: 1,
                                 duration: 3, wasSlammed: false, isPerfect: true, reversals: 0)
        #expect(result.closeStyle == .perfect && result.closeStyle.stampText == "PERFECT")
        result.isPerfect = false
        #expect(result.closeStyle == .pressed && result.closeStyle.stampText == "PRESSED")
        result.wasSlammed = true
        #expect(result.closeStyle == .slammed && result.closeStyle.stampText == "SLAMMED")
        #expect(result.closeStyle.isGentle && result.closeStyle.nudge != nil)
        result.wasSlammed = false
        result.reversals = 3
        #expect(result.closeStyle == .pressed && !result.closeStyle.isGentle)
    }

    /// The hinge as a living control: a detent every 6° both ways, and the machine powers down as the phone shuts and
    /// up again (the release) as it reopens.
    @Test func hingeDetentsAndPowerFollowTheLid() {
        #expect(HingeMotion.linesCrossed(from: 125, to: 113) == [120, 114])
        #expect(HingeMotion.linesCrossed(from: 113, to: 125) == [114, 120])
        #expect(HingeMotion.linesCrossed(from: 121, to: 122).isEmpty)
        #expect(HingeMotion.power(angle: 30, closed: false) == 0 && HingeMotion.power(angle: 150, closed: false) == 1)
        #expect(HingeMotion.power(angle: 150, closed: true) == 0)

        let timeline = Timeline()
        let engine = timedEngine(.rubberDuck, timeline)
        var time = drive(engine, timeline, from: 180, to: 120, duration: 3, startTime: 0)
        time = drive(engine, timeline, from: 120, to: 120, duration: 0.5, startTime: time)
        let closing = timeline.beats.compactMap { Self.detentAngle($0.beat, closing: true) }
        #expect((9...10).contains(closing.count), "\(closing)")
        #expect(closing.first == Double(174))
        time = drive(engine, timeline, from: 120, to: 175, duration: 2, startTime: time)
        let opening = timeline.beats.compactMap { Self.detentAngle($0.beat, closing: false) }
        #expect(opening.count >= 8)
        // Press, shut, reopen: power down on the shut, power up (the release) on the reopen.
        time = drive(engine, timeline, from: 175, to: 5, duration: 4, startTime: time, closedAtEnd: true)
        time = drive(engine, timeline, from: 5, to: 5, duration: 1, startTime: time, closed: true)   // lying shut
        #expect(engine.phase == .sealed)
        #expect(engine.hingePower < 0.1)
        time = drive(engine, timeline, from: 5, to: 170, duration: 1.5, startTime: time)
        time = drive(engine, timeline, from: 170, to: 170, duration: 1, startTime: time)
        _ = time
        #expect(engine.hingePower > 0.99)
        let down = timeline.beats.firstIndex { $0.beat == .powerDown }
        let up = timeline.beats.lastIndex { $0.beat == .powerUp }
        #expect(down != nil && up != nil && (down ?? 0) < (up ?? 0))
        #expect(engine.powerUpCount >= 1)
    }

    /// Touch on the object only while nothing is pressed; a flick during a press does nothing.
    @Test func inspectionOnlyWhileNothingIsPressed() {
        let timeline = Timeline()
        let engine = timedEngine(.jelly, timeline)
        #expect(engine.canInspect)
        engine.spun(turnsPerSecond: 1.5)
        engine.spun(turnsPerSecond: 0.05)   // not a spin
        #expect(timeline.count { $0 == .spin(speed: 1.5) } == 1)
        #expect(timeline.count { if case .spin = $0 { return true } else { return false } } == 1)
        drive(engine, timeline, from: 180, to: 95, duration: 2, startTime: 0)
        #expect(!engine.canInspect)
        engine.spun(turnsPerSecond: 2)
        #expect(timeline.count { $0 == .spin(speed: 2) } == 0)
    }

    /// Saved tunings missing a later field keep the rest (the CLAUDE.md gotcha), and unknown keys are ignored.
    @Test func savedTuningsDecodeLeniently() throws {
        let data = try JSONEncoder().encode(PressConfig.standard)
        let decoded = try JSONSerialization.jsonObject(with: data)
        var object = try #require(decoded as? [String: Any])
        object["contactCeiling"] = 111.0
        object.removeValue(forKey: "slamSpeed")
        object["someFutureKnob"] = 3
        let partial = try JSONSerialization.data(withJSONObject: object)
        let config = try #require(PressConfig.decodeLeniently(partial))
        #expect(config.contactCeiling == 111 && config.slamSpeed == PressConfig.standard.slamSpeed)
        #expect(PressConfig.decodeLeniently(Data("nope".utf8)) == nil)
    }

    // MARK: - APPLE-DUO-GUIDE: a nil hinge is not "no hinge"
    // (Mutating calls are hoisted out of #expect: the macro can't take them.)

    /// Before any hinge this launch, nil means a regular iPhone: fall back at once.
    @Test func nilBeforeAnyHingeFallsBackAtOnce() {
        var presence = HingePresence()
        let fallBack = presence.lost(at: 1)
        #expect(fallBack)
        #expect(!presence.available && !presence.seen && presence.deadline == nil)
    }

    /// Once a hinge has been seen, a transient nil holds the Duo stage; a reading ends the gap.
    @Test func transientNilHoldsTheFoldStage() {
        var presence = HingePresence()
        presence.reading(at: 0)
        let fallBack = presence.lost(at: 10)
        #expect(!fallBack && presence.available)
        let early = presence.shouldFallBack(at: 10 + HingePresence.grace / 2)
        #expect(!early && presence.available)
        presence.reading(at: 11)
        #expect(presence.available && presence.deadline == nil)
        let later = presence.shouldFallBack(at: 100)
        #expect(!later && presence.available)
    }

    /// A hinge missing for the whole grace, with no window or scene change, falls back; a scene change restarts it.
    @Test func sustainedLossFallsBackUnlessTheSceneChanged() {
        var presence = HingePresence()
        presence.reading(at: 0)
        let first = presence.lost(at: 10)
        let second = presence.lost(at: 11)   // a second nil doesn't restart the gap
        #expect(!first && !second && presence.deadline == 10 + HingePresence.grace)
        presence.sceneChanged(at: 13)
        #expect(presence.deadline == 13 + HingePresence.grace)
        let beforeRestartedGrace = presence.shouldFallBack(at: 10 + HingePresence.grace)
        #expect(!beforeRestartedGrace && presence.available)
        let afterGrace = presence.shouldFallBack(at: 13 + HingePresence.grace)
        #expect(afterGrace && !presence.available && presence.seen)
        // A hinge comes back: available again, and the next nil waits again.
        presence.reading(at: 30)
        let again = presence.lost(at: 31)
        #expect(presence.available && !again)
        // A scene change with no gap running does nothing.
        var steady = HingePresence()
        steady.reading(at: 0)
        steady.sceneChanged(at: 5)
        #expect(steady.deadline == nil && steady.available)
    }
}
