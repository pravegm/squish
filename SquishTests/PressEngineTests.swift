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
        // A real fold seals only when really shut (≤ shutAngle), never at an angle (the hinge log, 25 Oct 2026).
        var time = sweep(engine, from: 180, to: 40, duration: 6, startTime: 0)
        time = hold(engine, at: 40, seconds: 0.5, startTime: time)
        #expect(engine.phase == .pressing)
        time = sweep(engine, from: 40, to: 5, duration: 0.5, startTime: time)
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

    /// Fight, then give (EXPERIENCE-REVIEW-1 #1), without breaking sync: the render depth (ram, print, gauge) stays on
    /// the hand within 2°; the fight is the strain (bulge, push-back, tremor, lid shadow), rising over the window before
    /// the failure; at the burst the object collapses ahead of the hand for 60–80 ms, then locks back on.
    @Test func fightThenGiveStaysLockedToTheHand() throws {
        let timeline = Timeline()
        let engine = timedEngine(.glassBottle, timeline)
        let failure = try #require(engine.failureThreshold)
        let resistance = engine.resistance
        let target = failure - resistance.window / 2
        let held = angle(engine, compression: target)
        var time = drive(engine, timeline, from: 180, to: held, duration: 3, startTime: 0)
        time = drive(engine, timeline, from: held, to: held, duration: 0.6, startTime: time)
        #expect(engine.phase == .pressing && timeline.time(of: .hush) == nil)
        #expect(abs(engine.measuredCompression - target) < 0.01)   // the hand, exactly
        let span = PressConfig.standard.contactCeiling - PressConfig.standard.endAngle
        #expect(abs(engine.measuredCompression - engine.renderCompression) * span <= 2)
        #expect(abs(engine.objectCompression - engine.visualCompression) < 1e-9)   // the object too, before the break
        let strain = engine.resistanceStrain
        #expect(strain > 0.2 && strain < 0.8, "half-way into the window: \(strain)")
        // Through the failure, a frame at a time: held through the hush and hit stop, then ahead of the hand.
        let past = angle(engine, compression: failure + 0.08)
        var sawHold = false, sawLead = false, maxLead = 0.0
        for k in 1...60 {
            let now = time + Double(k) / rate
            timeline.now = now
            let a = held + (past - held) * min(Double(k) / 8, 1)
            engine.ingest(angle: a, closed: false, at: now)
            engine.step(now: now, dt: 1 / rate)
            if engine.breakPhase == .hitStop {
                sawHold = engine.objectCompression < engine.visualCompression - 0.01 || sawHold
                #expect(engine.resistanceStrain == 1)
            }
            if let since = engine.sinceBurst, since < resistance.give {
                maxLead = max(maxLead, engine.collapseLead)
                if engine.objectCompression > engine.visualCompression + 0.01 { sawLead = true }
            }
            #expect(abs(engine.measuredCompression - engine.renderCompression) * span <= 2.5)   // never trails
        }
        time += 60 / rate
        #expect(sawHold, "the object is held through the hit stop")
        #expect(sawLead, "the object collapses ahead of the hand at the give")
        #expect(maxLead > 0.5 * resistance.collapse && maxLead <= resistance.collapse + 1e-9)
        #expect(abs(engine.objectCompression - engine.visualCompression) < 1e-9)   // locked back on
        #expect(engine.resistanceStrain == 0 && engine.collapseLead == 0)
        _ = time
    }

    @Test func resistanceMathRampsAndGives() {
        for kind in ObjectKind.allCases {
            let r = PressResistance.of(kind)
            let f = 0.5
            var previous = -1.0
            for i in 0...200 {
                let c = Double(i) / 200
                let v = r.strain(c, failure: f)
                #expect(v >= previous - 1e-12 && v >= 0 && v <= 1, "\(kind) c=\(c)")
                previous = v
            }
            if r.fights {
                #expect(r.strain(f - r.window, failure: f) == 0 && r.strain(f, failure: f) == 1)
                #expect(r.give >= 0.06 && r.give <= 0.08)
            }
            #expect(r.lead(after: -0.01) == 0 && r.lead(after: r.give) == 0)
            #expect(r.released(from: 0.4, to: 0.6, after: r.give) == 0.6)
            #expect(r.released(from: 0.4, to: 0.6, after: r.give / 2) > 0.5)
        }
        // The stiff ones bulge and give the most; bubble wrap never fights; the ball fights and never gives.
        #expect(PressResistance.of(.glassBottle).collapse > PressResistance.of(.jelly).collapse)
        #expect(PressResistance.of(.sodaCan).bulge >= 0.15)
        #expect(!PressResistance.of(.bubbleWrap).fights)
        #expect(PressResistance.of(.unsquishable).collapse == 0)
    }

    /// Tons that mean something (EXPERIENCE-REVIEW-1 #4): per material and per press. The force climbs as the object
    /// fights, drops when it gives, and the card prints the peak.
    @Test func tonnageTellsTheObjectsStory() {
        func tons(_ kind: ObjectKind) -> Int { Tonnage.record(kind: kind, maxCompression: 1, seed: 5) }
        #expect(tons(.jelly) < tons(.bubbleWrap) && tons(.bubbleWrap) < tons(.egg))
        #expect(tons(.egg) < tons(.sodaCan) && tons(.sodaCan) < tons(.glassBottle))
        #expect(Double(tons(.glassBottle)) < PressGauge.redZoneTons)
        #expect(Double(tons(.unsquishable)) > PressGauge.maxTons)
        for kind in ObjectKind.allCases where kind != .unsquishable {
            for seed in UInt64(0)..<30 {
                let t = Double(Tonnage.record(kind: kind, maxCompression: 1, seed: seed))
                let r = Tonnage.rated(kind)
                #expect(t >= (r * 0.9).rounded(.down) && t <= (r * 1.1).rounded(.up), "\(kind) \(t) t")
                guard let f = Tonnage.failure(kind, seed: seed) else { continue }
                let before = Tonnage.live(kind: kind, compression: f - 0.001, seed: seed, failed: false)
                let after = Tonnage.live(kind: kind, compression: f + 0.001, seed: seed, failed: true)
                #expect(after < before * 0.6, "\(kind): the needle drops when it gives")
                #expect(Tonnage.live(kind: kind, compression: f * 0.5, seed: seed) < before * 0.5)
            }
        }
        // No two everyday objects read the same any more (was 54–59 t across the board).
        let distinct = Set([ObjectKind.bubbleWrap, .egg, .rubberDuck, .crayon, .sodaCan, .glassBottle].map(tons))
        #expect(distinct.count == 6)
    }

    /// The seal stroke (EXPERIENCE-REVIEW-1 #7): after full compression the crushed fold keeps reading as sealing:
    /// `sealProgress` ramps 0 → 1 toward the real shut, two latches click at ~40° and ~25°, then the ka-chunk. And the
    /// mapping holds with the fully crushed angle at 48° (a Tuning Lab slider): every break still lit.
    @Test func sealStrokeBuildsToTheKaChunk() {
        let timeline = Timeline()
        let engine = timedEngine(.rubberDuck, timeline)
        let latches = engine.latchAngles
        #expect(abs(latches[0] - 40) < 0.01 && abs(latches[1] - 25) < 0.01)
        var time = drive(engine, timeline, from: 180, to: 50, duration: 4, startTime: 0)
        time = drive(engine, timeline, from: 50, to: 50, duration: 0.3, startTime: time)
        #expect(engine.phase == .pressing && engine.sealProgress > 0 && engine.sealProgress < 0.2)
        time = drive(engine, timeline, from: 50, to: 30, duration: 1, startTime: time)
        let mid = engine.sealProgress
        #expect(mid > 0.4 && mid < 0.75)
        time = drive(engine, timeline, from: 30, to: 5, duration: 1, startTime: time, closedAtEnd: true)
        let fired = timeline.beats.compactMap { b -> Int? in
            if case let .latch(index, _) = b.beat { return index } else { return nil }
        }
        #expect(fired == [0, 1])
        let lastLatch = timeline.beats.last { if case .latch = $0.beat { return true } else { return false } }
        let kaChunk = timeline.time(of: .kaChunk)
        #expect(lastLatch != nil && kaChunk != nil && (lastLatch?.time ?? 99) <= (kaChunk ?? 0))
        #expect(engine.phase == .sealed && engine.sealProgress == 1)
        _ = time

        var config = PressConfig.standard
        config.endAngle = 48
        for kind in ObjectKind.allCases {
            guard let index = kind.profile.failureIndex else { continue }
            let worst = min(1, kind.profile.fractures[index] + kind.profile.thresholdJitter)
            let angle = FoldCurve.angle(forCompression: worst, config: config)
            #expect(angle >= config.displayOffAngle + 10, "\(kind) at end 48: fails at \(angle)°")
        }
    }

    /// Inspect the crushed specimen (EXPERIENCE-REVIEW-1 #8): touch works again once the reveal is up.
    @Test func crushedSpecimenCanBeInspectedOnTheReveal() {
        let timeline = Timeline()
        let engine = timedEngine(.jelly, timeline)
        var time = drive(engine, timeline, from: 180, to: 5, duration: 3, startTime: 0, closedAtEnd: true)
        time = drive(engine, timeline, from: 5, to: 5, duration: 0.3, startTime: time, closed: true)
        #expect(engine.phase == .sealed && !engine.canInspect)
        time = drive(engine, timeline, from: 5, to: 160, duration: 1, startTime: time)
        #expect(engine.phase == .revealing && engine.canInspect)
        engine.spun(turnsPerSecond: 1)
        #expect(timeline.count { $0 == .spin(speed: 1) } == 1)
        _ = time
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
        #expect(!presence.available && !presence.seen && presence.missingSince == nil)
    }

    /// Once a hinge has been seen this launch, a nil never falls back, however long (launch QA P1: the cover flipped to
    /// the P-48 after the old 4 s grace); a reading ends the gap.
    @Test func seenHingeNeverFallsBack() {
        var presence = HingePresence()
        presence.reading(at: 0)
        let first = presence.lost(at: 10)
        let second = presence.lost(at: 11)
        let muchLater = presence.lost(at: 10_000)
        #expect(!first && !second && !muchLater && presence.available && presence.seen)
        #expect(presence.missingSince == 10)
        presence.reading(at: 10_001)
        #expect(presence.available && presence.missingSince == nil)
    }
    // MARK: - Sync fix (founder, real Duo 1.0 (3)): the screen moves with the hand

    /// The founder's real-Duo hinge log (Tuning Lab CSV, 25 Oct 2026): a slow close, shut, then a reopen. Note `.closed`
    /// sets at 84° while closing and clears at ~21° on reopen: a posture, not "shut" (FOLD-PRESS §9.8).
    static let realLog: [(time: Double, angle: Double, closed: Bool)] = [
        (41.7843, 174.79, false), (42.0005, 160.28, false), (42.2269, 144.09, false), (42.4186, 124.91, false),
        (42.6672, 109.55, false), (42.8833, 91.12, false), (42.9671, 84.07, true), (43.2376, 64.44, true),
        (43.5363, 47.99, true), (43.8862, 35.36, true), (44.3613, 35.84, true), (44.7863, 21.74, true),
        (45.0988, 9.10, true), (45.2006, 0.00, true), (46.5703, 6.52, true), (46.6365, 19.71, true),
        (46.6990, 21.17, false), (46.8200, 51.82, false), (47.0948, 104.16, false), (47.4552, 180.00, false),
    ]

    /// Replays the real log at 60 Hz frames: no seal until the angle is really shut (≤ ~12°, never at the ~85° `.closed`
    /// posture), a reveal on the reopen once past ~25°, and a render depth that moves smoothly between the sparse reports.
    @Test func realHingeLogSealsOnlyWhenShutAndRevealsOnReopen() throws {
        let timeline = Timeline()
        let engine = PressEngine()
        engine.onEvent = { timeline.events.append((time: timeline.now, event: $0)) }
        engine.ingest(angle: 180, closed: false, at: 0)
        engine.load(.rubberDuck, seed: 42, at: 0)
        timeline.now = 41.70
        engine.step(now: 41.70, dt: 1.0 / 60)
        var next = 0
        var lastAngle = 180.0
        var sealedAt: Double?
        var revealedAt: Double?
        var maxStep = 0.0
        var previous = engine.renderDepth
        var frame = 0
        while true {
            let now = 41.70 + Double(frame) / 60
            if now > 48.5 { break }
            timeline.now = now
            while next < Self.realLog.count, Self.realLog[next].time <= now {
                let s = Self.realLog[next]
                engine.ingest(angle: s.angle, closed: s.closed, at: s.time)
                lastAngle = s.angle
                next += 1
            }
            engine.step(now: now, dt: 1.0 / 60)
            if sealedAt == nil, engine.phase == .sealed {
                sealedAt = now
                #expect(lastAngle <= PressConfig.standard.shutAngle, "sealed at \(lastAngle)°")
            }
            if revealedAt == nil, engine.phase == .revealing {
                revealedAt = now
                #expect(lastAngle >= PressConfig.standard.revealOpenAngle, "revealed at \(lastAngle)°")
            }
            if sealedAt == nil, engine.phase == .pressing || engine.phase == .armed {
                maxStep = max(maxStep, abs(engine.renderDepth - previous))
            }
            previous = engine.renderDepth
            frame += 1
        }
        let sealed = try #require(sealedAt)
        #expect(sealed >= 45.0988 - 1e-9)   // the 9.10° report, not the 84.07° `.closed` one
        #expect(timeline.events.firstIndex { $0.event == .kaChunk }.map { timeline.events[$0].time >= 45.0988 - 1e-9 } ?? false)
        let revealed = try #require(revealedAt)
        #expect(revealed >= 46.8200 - 1e-9 && revealed < 47.0)
        #expect(engine.phase == .revealing)
        // Continuous between reports 0.2 s apart: no frame jumps (a 1:1 track of the hand moves ~0.01 a frame here).
        #expect(maxStep <= 0.06, "max render-depth step \(maxStep) per frame")
        // The duck failed on the way down, while lit. (This excerpt jumps 84° → 64° in one report, so the failure is
        // recorded at that report: below the full-rate floor, still well above the ~45° display-off.)
        let failure = try #require(engine.failureAngle)
        #expect(failure > PressConfig.standard.displayOffAngle + 10 && failure <= PressConfig.standard.contactCeiling)
    }

    /// The `.closed` status alone is never shut: closing to 60° with `.closed` set neither seals nor ka-chunks.
    @Test func closedPostureAloneIsNotShut() {
        let log = EventLog()
        let engine = makeEngine(.egg, log: log)
        var time = sweep(engine, from: 180, to: 86, duration: 2, startTime: 0)
        time = sweep(engine, from: 86, to: 60, duration: 1, startTime: time, closed: true)
        time = hold(engine, at: 60, seconds: 2, startTime: time)
        #expect(engine.phase == .pressing && !engine.isClosed)
        #expect(log.count { $0 == .kaChunk || $0 == .sealed(blind: true) || $0 == .sealed(blind: false) } == 0)
        _ = time
    }

    /// The tracker at the rates the hinge really uses (25–30 Hz, gaps; the coordinator asks for 5–120 Hz): ~no lag at a
    /// steady speed, continuous at display rate, and a stop overshoots by at most about one report interval of travel.
    @Test func hingeTrackerFollowsTheHandBetweenReports() {
        for hz in [5.0, 10.0, 30.0, 60.0, 120.0] {
            for speed in [20.0, 60.0] {
                var tracker = HingeTracker()
                var nextSample = 0.0
                var worst = 0.0, step = 0.0
                var previous: Double?
                for frame in 0...168 {   // 2.8 s: the hinge stays above 0° at 60°/s
                    let now = Double(frame) / 60
                    while nextSample <= now + 1e-9 {
                        tracker.sample(180 - speed * nextSample, at: nextSample)
                        nextSample += 1 / hz
                    }
                    let shown = tracker.angle(at: now + 1.0 / 60)
                    let truth = 180 - speed * (now + 1.0 / 60)
                    if now > 1.5 {   // after the rate estimate has settled
                        worst = max(worst, abs(shown - truth))
                        if let previous { step = max(step, abs(shown - previous)) }
                    }
                    previous = shown
                }
                let truthStep = speed / 60
                #expect(worst <= (hz >= 10 ? 0.6 : 3.0), "\(hz) Hz \(speed)°/s: off by \(worst)°")
                #expect(step <= truthStep * (hz >= 10 ? 1.6 : 3.2), "\(hz) Hz \(speed)°/s: step \(step)° a frame")
            }
        }
        // A stop at 30 Hz: overshoot bounded, then it settles back on the report.
        var tracker = HingeTracker()
        var t = 0.0
        while t <= 1 {
            tracker.sample(180 - 40 * t, at: t)
            t += 1.0 / 30
        }
        let stop = 180 - 40 * (t - 1.0 / 30)
        var worst = 0.0
        var frame = 0.0
        while frame < 0.5 {
            worst = max(worst, abs(tracker.angle(at: t + frame) - stop))
            frame += 1.0 / 60
        }
        #expect(worst <= 40.0 / 30 * 2.5, "overshoot \(worst)°")
        // A slam between two reports (a 120° jump) snaps rather than swinging past.
        tracker.sample(10, at: t + 0.03)
        #expect(abs(tracker.angle(at: t + 0.03) - 10) < 1e-9)
    }

    // MARK: - P0: a held hinge is just held (CI run 40153721315: soft objects looked frozen before the break)

    /// The CI Duo capture's hinge (run 40153721315, gummyBear, book pass): sparse reports and ~10 s holds, as the
    /// simulator (or a Duo held still) sends them.
    static let ciLog: [(time: Double, angle: Double)] = [
        (34.21, 174.7), (36.38, 160.2), (36.67, 142.3), (37.81, 127.5), (38.94, 125.3), (39.26, 109.2), (40.20, 99.4),
        (41.32, 99.4), (52.22, 99.1), (52.49, 97.2), (53.63, 82.4), (54.63, 75.8), (65.12, 63.2), (66.27, 61.7),
        (74.44, 59.5), (75.68, 57.3), (76.81, 31.4), (77.10, 27.0), (77.45, 24.2), (77.77, 21.4), (78.05, 18.2),
        (78.30, 15.4), (78.62, 12.2), (78.87, 9.4),
    ]

    /// The founder's real-Duo close (`realLog`, down to the ~48° report), each report followed by 1.6 s of the hinge
    /// held still (no reports at all, as a still Duo sends none).
    static var founderHolds: [(time: Double, angle: Double)] {
        var t = 41.7843
        var log: [(time: Double, angle: Double)] = []
        for sample in realLog where sample.angle >= 47 && sample.time < 44 {
            log.append((t, sample.angle))
            t += 1.6
        }
        return log
    }

    /// Compression units to degrees of lid travel (the tests' 2° budget).
    private var degreesPerCompression: Double { PressConfig.standard.contactCeiling - PressConfig.standard.endAngle }

    /// A held-still press at the logs' angles (the CI capture's and the founder's): once the hinge has been still for a
    /// second, every object's own compression is the hand's (≤ 2°), and no hush or hit stop is holding it.
    @Test func heldStillHingeKeepsEveryObjectOnTheHand() {
        let span = degreesPerCompression
        for (name, log) in [("CI", Self.ciLog), ("founder", Self.founderHolds)] {
            let t0 = log[0].time - 1
            let end = log.last!.time + 1.5
            for kind in ObjectKind.allCases {
                let engine = PressEngine()
                engine.ingest(angle: 180, closed: false, at: t0)
                engine.load(kind, seed: 42, at: t0)
                var next = 0
                var lastReport = t0
                var worst = 0.0
                var heldFrames = 0
                var frozenFrames = 0
                var frame = 0
                while true {
                    let now = t0 + Double(frame) / 60
                    if now > end { break }
                    while next < log.count, log[next].time <= now {
                        engine.ingest(angle: log[next].angle, closed: false, at: log[next].time)
                        lastReport = log[next].time
                        next += 1
                    }
                    engine.step(now: now, dt: 1.0 / 60)
                    if engine.phase == .pressing, now - lastReport >= 1 {
                        heldFrames += 1
                        worst = max(worst, abs(engine.objectCompression - engine.measuredCompression) * span)
                        if engine.breakPhase == .hush || engine.breakPhase == .hitStop { frozenFrames += 1 }
                    }
                    frame += 1
                }
                #expect(heldFrames > 120, "\(name) \(kind): the press was held \(heldFrames) frames")
                #expect(worst <= 2, "\(name) \(kind): a held hinge shows the object \(worst)° off the hand")
                #expect(frozenFrames == 0, "\(name) \(kind): \(frozenFrames) held frames still in the hush / hit stop")
            }
        }
    }

    /// A sweep at 30 Hz with 1.5 s pauses (no reports) before the fight window, inside it, just past the failure (the
    /// break lands during the pause) and fully crushed: the object leaves the hand only in the hush and hit stop
    /// (≤ ~270 ms after the crossing) and the give's 60–80 ms; everywhere else, moving or held, it is on the hand.
    @Test func sweepWithPausesLeavesTheHandOnlyInTheBreak() throws {
        let span = degreesPerCompression
        for kind in ObjectKind.allCases {
            let timeline = Timeline()
            let engine = timedEngine(kind, timeline)
            let failure = engine.failureThreshold
            let window = engine.resistance.window
            let targets: [Double]
            if let failure {
                targets = [max(failure - window - 0.1, 0.03), max(failure - window / 2, 0.04), min(failure + 0.06, 0.99), 1]
            } else {
                targets = [0.3, 0.6, 1]
            }
            var now = 0.0
            var angleNow = 180.0
            var worstOutside = 0.0
            var holdFrames = 0
            var sampleDue = 0.0
            func frame(sampleAt angle: Double?) {
                now += 1.0 / 60
                timeline.now = now
                if let angle, now >= sampleDue - 1e-9 {
                    engine.ingest(angle: angle, closed: false, at: now)
                    sampleDue = now + 1.0 / 30
                }
                engine.step(now: now, dt: 1.0 / 60)
                let held = engine.breakPhase == .hush || engine.breakPhase == .hitStop
                let giving = engine.sinceBurst.map { $0 < engine.resistance.give + 1e-9 } ?? false
                if held { holdFrames += 1 }
                if !held && !giving && engine.phase == .pressing {
                    // The hand: the latest raw reading (the event filter's lag is not the hand).
                    let m = engine.mapping
                    let hand = PressMapping.compression(depth: PressMapping.depth(angle: engine.rawAngle,
                                                                                  start: engine.startAngle, config: m),
                                                        config: m)
                    worstOutside = max(worstOutside, abs(engine.objectCompression - hand) * span)
                }
            }
            for target in targets {
                let goal = target >= 1 ? PressConfig.standard.endAngle - 2 : angle(engine, compression: target)
                // 25°/s, reported at 30 Hz.
                let frames = max(Int(abs(angleNow - goal) / 25 * 60), 1)
                let from = angleNow
                for i in 1...frames { frame(sampleAt: from + (goal - from) * Double(i) / Double(frames)) }
                angleNow = goal
                for _ in 0..<90 { frame(sampleAt: nil) }   // held: the hinge sends nothing
            }
            #expect(worstOutside <= 2.5, "\(kind): off the hand by \(worstOutside)° outside the break")
            if failure != nil {
                #expect(timeline.time(of: .hush) != nil, "\(kind) broke")
                let score = BreakScore.of(kind, hush: PressConfig.standard.failureHushDelay)
                let budget = Int(((score.burst + PressEngine.burstGrace) * 60).rounded(.up)) + 2
                #expect(holdFrames <= budget, "\(kind): held \(holdFrames) frames (budget \(budget))")
            }
            #expect(engine.phase == .pressing)
            #expect(abs(engine.objectCompression - engine.measuredCompression) * span <= 2)
        }
    }

    /// Once the reports stop, the drawn hinge settles exactly on the last reading (no residue of the tracker's
    /// estimate or its coast), and its speed is 0.
    @Test func heldHingeSettlesOnTheLastReading() {
        for hz in [5.0, 30.0, 120.0] {
            var tracker = HingeTracker()
            var t = 0.0
            var last = 180.0
            while t <= 1 {
                // A close with a wobble on top, then the hand stops.
                last = 180 - 70 * t + 3 * sin(t * 40)
                tracker.sample(last, at: t)
                t += 1 / hz
            }
            let stopped = t - 1 / hz
            let settled = stopped + HingeTracker.restAfter(horizon: tracker.horizon, interval: tracker.interval) + 0.4
            #expect(abs(tracker.angle(at: settled) - last) < 0.01, "\(hz) Hz: \(tracker.angle(at: settled)) vs \(last)")
            #expect(tracker.closingSpeed(at: settled) == 0)
            // And it stays there.
            #expect(abs(tracker.angle(at: settled + 10) - last) < 1e-6)
        }
    }
}
