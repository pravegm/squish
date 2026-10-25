import Foundation
import Testing
@testable import Squish

/// Launch QA round (press engineer): trace files, the pending sealed press, shut hysteresis, holding, slam / Perfect
/// across input rates, arming after a quick reopen, bad hinge samples, and hinge presence on the cover.
@MainActor
struct LaunchQATests {
    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("squish-qa-\(UUID().uuidString)",
                                                                                 isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func trace(_ kind: ObjectKind = .egg) -> PressTrace {
        PressTrace(kind: kind, variant: PressVariant(kind: kind, seed: 7),
                   samples: [.init(time: 0, angle: 180, closed: false), .init(time: 1, angle: 5, closed: true)],
                   usesVirtualHinge: false, config: .standard)
    }

    // MARK: 7. Trace files are deleted with their specimens

    @Test func traceStoreDeletesAndPrunes() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TraceStore(directory: dir)
        let keep = UUID(), drop = UUID(), stray = UUID()
        store.save(trace(), for: keep)
        store.save(trace(), for: drop)
        store.save(trace(), for: stray)
        try "x".write(to: dir.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        #expect(store.load(drop) != nil)
        TraceStore.delete(drop, in: dir)
        #expect(store.load(drop) == nil)
        TraceStore.delete(UUID(), in: dir)   // no file: a no-op
        #expect(TraceStore.prune(keeping: [keep], in: dir) == 1)
        #expect(store.load(keep) != nil && store.load(stray) == nil)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("notes.txt").path))
    }

    // MARK: Engine helpers

    /// An engine on a real hinge, flat at t = 0.
    private func hingeEngine(_ kind: ObjectKind = .egg, events: EventLog) -> PressEngine {
        let engine = PressEngine()
        engine.onEvent = { events.events.append($0) }
        engine.ingest(angle: 180, closed: false, at: 0)
        engine.load(kind, seed: 42, at: 0)
        return engine
    }

    /// Reports `angles` at `hz` from `start`, stepping the engine at 60 Hz between them; returns the time of the last frame.
    @discardableResult
    private func feed(_ engine: PressEngine, _ angles: [Double], hz: Double, from start: Double,
                      frame: ((Double) -> Void)? = nil) -> Double {
        var now = start
        var next = 0
        var due = start
        while next < angles.count {
            now += 1.0 / 60
            while next < angles.count, due <= now + 1e-9 {
                engine.ingest(angle: angles[next], closed: false, at: due)
                next += 1
                due += 1 / hz
            }
            engine.step(now: now, dt: 1.0 / 60)
            frame?(now)
        }
        return now
    }

    /// Frames with no reports (the hinge held still).
    @discardableResult
    private func hold(_ engine: PressEngine, seconds: Double, from start: Double, frame: ((Double) -> Void)? = nil) -> Double {
        var now = start
        for _ in 0..<Int(seconds * 60) {
            now += 1.0 / 60
            engine.step(now: now, dt: 1.0 / 60)
            frame?(now)
        }
        return now
    }

    private func ramp(_ from: Double, _ to: Double, seconds: Double, hz: Double) -> [Double] {
        let n = max(Int((seconds * hz).rounded()), 1)
        return (1...n).map { from + (to - from) * Double($0) / Double(n) }
    }

    // MARK: 4. Shut hysteresis: one ka-chunk per seal, no chatter

    @Test func shutHasHysteresis() {
        let config = PressConfig.standard
        #expect(config.isShut(10, wasShut: false) && !config.isShut(10.5, wasShut: false))
        #expect(config.isShut(14.9, wasShut: true) && !config.isShut(15, wasShut: true))
        #expect(config.shutReleaseAngle == config.shutAngle + 5)
    }

    @Test func shutNoiseNeverRepeatsTheKaChunk() {
        let events = EventLog()
        let engine = hingeEngine(events: events)
        var now = feed(engine, ramp(180, 5, seconds: 3, hz: 30), hz: 30, from: 0)
        #expect(engine.phase == .sealed && engine.isClosed)
        // A shut Duo's noise (0–6.5°, real logs) and a wobble up to 14°: still shut, no second ka-chunk.
        now = feed(engine, [6.5, 0, 12, 4, 14, 3, 9, 13.5, 2], hz: 10, from: now)
        #expect(engine.isClosed)
        #expect(events.count { $0 == .kaChunk } == 1)
        // 16° is open again; closing once more is the same seal: still one ka-chunk, and no reveal below 25°.
        now = feed(engine, [16], hz: 10, from: now)
        #expect(!engine.isClosed)
        now = feed(engine, [5, 3], hz: 10, from: now)
        #expect(engine.isClosed && engine.phase == .sealed)
        #expect(events.count { $0 == .kaChunk } == 1)
        _ = now
    }

    @Test func hingeFeelShutClacksOnceThroughNoise() {
        var feel = HingeFeel()
        feel.detectsDetentsAndPower = false
        var shuts = 0
        var t = 0.0
        for angle in [40.0, 20, 8, 12, 9, 14, 6, 11, 16, 30, 8] {
            let input = HingeMotionInput(available: true, angle: angle, speed: 20, moving: true, shut: false,
                                         phase: .idle, loaded: false, shutAngle: 10)
            shuts += feel.update(input, at: t).moments.filter { $0 == .shut }.count
            t += 0.1
        }
        #expect(shuts == 2, "two real shuts (8°, then 8° after opening to 30°), got \(shuts)")
    }

    // MARK: 5. Holding follows the hinge's own report rate

    @Test func slowCloseAtTheDuosReportGapsIsNotAHold() {
        let events = EventLog()
        let engine = hingeEngine(.cakeSlice, events: events)
        // A slow close (18°/s) reported every 0.4 s, as a real Duo does: never "held" between reports.
        var heldWhileClosing = 0
        let now = feed(engine, ramp(180, 70, seconds: 6, hz: 2.5), hz: 2.5, from: 0) { _ in
            if engine.phase == .pressing, engine.angle < 140, engine.isHolding { heldWhileClosing += 1 }
        }
        #expect(heldWhileClosing == 0, "\(heldWhileClosing) frames read as held during a steady close")
        #expect(PressEngine.holdAfter(sampleInterval: 0.4) == 1)
        #expect(PressEngine.holdAfter(sampleInterval: 1.0 / 30) == 0.25)
        // A real hold (no reports) does read as held.
        var heldAtEnd = false
        hold(engine, seconds: 1.5, from: now) { _ in heldAtEnd = engine.isHolding }
        #expect(heldAtEnd)
    }

    // MARK: 8. Slam and Perfect read the same at every input rate

    @Test func slamAndPerfectAgreeAcrossReportRates() {
        for hz in [5.0, 30.0, 120.0] {
            // A gentle 3.5 s close, then shut: Perfect, not a slam.
            let gentleEvents = EventLog()
            let gentle = hingeEngine(.egg, events: gentleEvents)
            let end = feed(gentle, ramp(180, 2, seconds: 3.5, hz: hz), hz: hz, from: 0)
            hold(gentle, seconds: 0.3, from: end)
            #expect(gentle.phase == .sealed, "\(hz) Hz gentle: \(gentle.phase)")
            #expect(gentle.lastResult?.wasSlammed == false, "\(hz) Hz gentle read as a slam")
            #expect(gentle.lastResult?.isPerfect == true, "\(hz) Hz gentle is not Perfect")
            // Slammed shut in 0.4 s (~445°/s).
            let slamEvents = EventLog()
            let slam = hingeEngine(.egg, events: slamEvents)
            let slamEnd = feed(slam, ramp(180, 2, seconds: 0.4, hz: hz), hz: hz, from: 0)
            hold(slam, seconds: 0.3, from: slamEnd)
            #expect(slam.phase == .sealed, "\(hz) Hz slam: \(slam.phase)")
            #expect(slam.lastResult?.wasSlammed == true, "\(hz) Hz slam not read as a slam")
            #expect(slam.lastResult?.isPerfect == false)
        }
        // A brisk but honest close (~110°/s) is neither Perfect nor a slam, at 30 and 120 Hz alike.
        for hz in [30.0, 120.0] {
            let events = EventLog()
            let engine = hingeEngine(.egg, events: events)
            let end = feed(engine, ramp(180, 2, seconds: 1.6, hz: hz), hz: hz, from: 0)
            hold(engine, seconds: 0.3, from: end)
            #expect(engine.lastResult?.wasSlammed == false, "\(hz) Hz brisk read as a slam")
        }
    }

    // MARK: 9. A quick reopen that stops at ~130–135° still arms

    @Test func quickReopenToTheArmThresholdArms() {
        let events = EventLog()
        let engine = PressEngine()
        engine.onEvent = { events.events.append($0) }
        engine.ingest(angle: 4, closed: true, at: 0)   // launched shut: idle
        engine.load(.egg, seed: 42, at: 0)
        var now = hold(engine, seconds: 0.5, from: 0)
        #expect(engine.phase == .idle)
        now = feed(engine, [5, 45, 95, 132], hz: 30, from: now)
        hold(engine, seconds: 1, from: now)
        #expect(engine.phase == .armed, "stopped at 132°, phase \(engine.phase), filtered \(engine.angle)")
    }

    // MARK: 10. A NaN or infinite reading is ignored

    @Test func nonFiniteReadingsAreIgnored() {
        let events = EventLog()
        let engine = hingeEngine(events: events)
        var now = feed(engine, ramp(180, 100, seconds: 1.5, hz: 30), hz: 30, from: 0)
        engine.ingest(angle: .nan, closed: false, at: now + 0.01)
        engine.ingest(angle: .infinity, closed: false, at: now + 0.02)
        engine.ingest(angle: 90, closed: false, at: .nan)
        #expect(engine.angle.isFinite && engine.displayAngle.isFinite && engine.measuredDepth.isFinite)
        now = feed(engine, ramp(100, 3, seconds: 2, hz: 30), hz: 30, from: now + 0.03)
        hold(engine, seconds: 0.3, from: now)
        #expect(engine.phase == .sealed)
        #expect(engine.renderDepth.isFinite && engine.angle.isFinite)
    }

    // MARK: 2. The inner canvas means open

    @Test func innerDisplayClearsAStaleShutAndReveals() {
        let events = EventLog()
        let engine = hingeEngine(events: events)
        let now = feed(engine, ramp(180, 3, seconds: 3, hz: 30), hz: 30, from: 0)
        #expect(engine.phase == .sealed && engine.isClosed)
        // Back with the phone already open and still: no hinge report, but the window is the inner canvas.
        engine.innerDisplayOpened(at: now + 5)
        #expect(!engine.isClosed)
        #expect(engine.phase == .revealing && events.count { $0 == .reveal } == 1)
        // Idempotent.
        engine.innerDisplayOpened(at: now + 6)
        #expect(events.count { $0 == .reveal } == 1)
    }

    // MARK: 6. The share-clip trace: a pre-roll window before the press, decimation past the cap

    @Test func tracePreRollKeepsTheArmAndRebases() {
        var samples: [PressTrace.Sample] = []
        var shift = 0.0
        // Ten minutes armed at 30 Hz of hinge noise around 170°.
        for i in 0..<(30 * 600) {
            let t = Double(i) / 30 - shift
            samples.append(.init(time: t, angle: 170 + sin(Double(i)) * 0.4, closed: false))
            shift += PressTrace.trimPreRoll(&samples, anchor: 168)
        }
        #expect(samples.count <= Int(PressTrace.preRoll * 30) + 3, "\(samples.count) samples kept")
        #expect(samples[0].angle == 168 && !samples[0].closed)   // the arm, summed up
        #expect(samples[0].time >= 0 && samples[0].time <= PressTrace.lead)
        #expect(samples.last!.time - samples[0].time <= PressTrace.preRoll + 0.1)
        #expect(zip(samples, samples.dropFirst()).allSatisfy { $0.time < $1.time })
        #expect(shift > 590)
    }

    @Test func traceDecimationKeepsEndsAndEdges() {
        var samples: [PressTrace.Sample] = (0..<1001).map { .init(time: Double($0) / 120, angle: 180 - Double($0) * 0.17,
                                                                  closed: false) }
        samples[777].closed = true
        samples[778].closed = true
        let thinned = PressTrace.decimated(samples)
        #expect(thinned.count < 560 && thinned.count > 480)
        #expect(thinned.first?.time == samples.first?.time && thinned.last?.time == samples.last?.time)
        #expect(thinned.contains { $0.time == samples[777].time && $0.closed })
    }

    // MARK: 1. A sealed press survives the app being ended before the reopen

    @Test func pendingPressRoundTrips() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PendingPressStore(url: dir.appendingPathComponent("pending-press.json"))
        #expect(store.load() == nil)
        let result = PressResult(kind: .egg, seed: 7, failureAngle: 82.5, fractureCount: 3, maxCompression: 1,
                                 duration: 3.2, wasSlammed: false, isPerfect: true, reversals: 1)
        store.save(PendingPress(result: result, variant: PressVariant(kind: .egg, seed: 7), trace: trace(),
                                sealedAt: Date(timeIntervalSince1970: 1_800_000_000)))
        let loaded = try #require(store.load())
        #expect(loaded.result == result)
        #expect(loaded.variant == PressVariant(kind: .egg, seed: 7))
        #expect(loaded.trace.samples.count == 2)
        store.clear()
        #expect(store.load() == nil)
    }

    @Test func sealedPressIsSavedAndClearedByItsReveal() throws {
        // The director's rule, on the engine's events: `.sealed` saves, `.reveal` clears.
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PendingPressStore(url: dir.appendingPathComponent("pending-press.json"))
        let events = EventLog()
        let engine = hingeEngine(events: events)
        engine.onEvent = { event in
            events.events.append(event)
            if case .sealed = event, let result = engine.lastResult {
                store.save(PendingPress(result: result, variant: PressVariant(kind: .egg, seed: 42),
                                        trace: self.trace(), sealedAt: Date()))
            }
            if event == .reveal { store.clear() }
        }
        let now = feed(engine, ramp(180, 3, seconds: 3, hz: 30), hz: 30, from: 0)
        let saved = try #require(store.load())
        #expect(saved.result == engine.lastResult)
        feed(engine, ramp(3, 60, seconds: 1, hz: 30), hz: 30, from: now)
        #expect(engine.phase == .revealing && store.load() == nil)
    }
}
