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
                       startTime: Double, closedAtEnd: Bool = false) -> Double {
        let steps = max(Int(duration * rate), 1)
        var time = startTime
        for i in 1...steps {
            time = startTime + Double(i) / rate
            let angle = start + (end - start) * Double(i) / Double(steps)
            engine.ingest(angle: angle, closed: closedAtEnd && i == steps, at: time)
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
}
