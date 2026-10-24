import Testing
@testable import Squish

@MainActor
struct ObjectCatalogTests {
    private let rate = 30.0

    /// Slow press 180° → 40° over 6 s, then hold, stepping the engine like a real frame loop.
    private func slowPress(_ kind: ObjectKind, seed: UInt64) -> (PressEngine, EventLog) {
        let log = EventLog()
        let engine = PressEngine()
        engine.onEvent = { log.events.append($0) }
        engine.ingest(angle: 180, closed: false, at: 0)
        engine.load(kind, seed: seed, at: 0)
        var time = 0.0
        let steps = Int(6 * rate)
        for i in 1...steps {
            time = Double(i) / rate
            engine.ingest(angle: 180 - 140 * Double(i) / Double(steps), closed: false, at: time)
            engine.step(now: time, dt: 1 / rate)
        }
        for _ in 0..<Int(rate) {
            time += 1 / rate
            engine.ingest(angle: 40, closed: false, at: time)
            engine.step(now: time, dt: 1 / rate)
        }
        return (engine, log)
    }

    @Test(arguments: ObjectKind.allCases)
    func everyObjectFiresEachFractureOnceAndSeals(kind: ObjectKind) {
        let (engine, log) = slowPress(kind, seed: 7)
        #expect(engine.phase == .sealed)
        #expect(log.fractureIndices() == Array(0..<kind.profile.fractures.count))
        if let failure = kind.profile.failureIndex {
            #expect(log.events.contains(.fracture(index: failure, isFailure: true)))
            #expect(log.count { $0 == .hush } == 1)
        } else {
            #expect(log.count { $0 == .hush } == 0)
        }
    }

    @Test(arguments: ObjectKind.allCases)
    func profilesAreWellFormed(kind: ObjectKind) {
        let profile = kind.profile
        #expect(profile.fractures == profile.fractures.sorted())
        #expect(profile.fractures.allSatisfy { $0 > 0 && $0 < 1 })
        if let failure = profile.failureIndex {
            #expect(failure < profile.fractures.count)
            // The big moment must land while the inner screen is clearly visible (bible §2: c ≈ 0.3–0.6).
            #expect(profile.fractures[failure] <= 0.72)
        }
        #expect(profile.plasticity >= 0 && profile.plasticity <= 1)
        #expect(!kind.flavourLines.isEmpty)
        #expect(!kind.displayName.isEmpty)
    }

    @Test func jitteredFracturesStayOrderedAndDeterministic() {
        for kind in ObjectKind.allCases {
            let a = kind.profile.jitteredFractures(seed: 99)
            let b = kind.profile.jitteredFractures(seed: 99)
            #expect(a == b)
            #expect(a == a.sorted())
        }
    }

    @Test func variantsAreDeterministicAndRoughlyRare() {
        #expect(PressVariant(kind: .egg, seed: 1234) == PressVariant(kind: .egg, seed: 1234))
        var golden = 0
        for seed in UInt64(1)...5000 where PressVariant(kind: .jelly, seed: seed).isGolden {
            golden += 1
        }
        // 1 in 50 → ~100 of 5000.
        #expect(golden > 50 && golden < 170)
        #expect(!PressVariant(kind: .unsquishable, seed: 3).isGolden)
    }

    @Test func pumpingCountsReversals() {
        let log = EventLog()
        let engine = PressEngine()
        engine.onEvent = { log.events.append($0) }
        engine.ingest(angle: 180, closed: false, at: 0)
        engine.load(.sodaCan, seed: 5, at: 0)
        var time = 0.0
        func sweep(_ from: Double, _ to: Double, _ seconds: Double) {
            let steps = Int(seconds * rate)
            for i in 1...steps {
                time += 1 / rate
                engine.ingest(angle: from + (to - from) * Double(i) / Double(steps), closed: false, at: time)
                engine.step(now: time, dt: 1 / rate)
            }
        }
        // Every reversal happens loaded: past the provisional fold contact (106°, PressConfig).
        sweep(180, 95, 2)
        sweep(95, 104, 0.5)
        sweep(104, 85, 0.8)
        sweep(85, 98, 0.5)
        sweep(98, 40, 2)
        for _ in 0..<30 {
            time += 1 / rate
            engine.ingest(angle: 40, closed: false, at: time)
            engine.step(now: time, dt: 1 / rate)
        }
        #expect(engine.phase == .sealed)
        #expect((engine.lastResult?.reversals ?? 0) >= 2)
        #expect(engine.lastResult?.isPerfect == false)
    }

    @Test func angleForDepthInvertsTheMapping() {
        let config = PressConfig.standard
        for depth in stride(from: 0.0, through: 1.0, by: 0.1) {
            let angle = PressMapping.angle(forDepth: depth, start: 165, config: config)
            #expect(abs(PressMapping.depth(angle: angle, start: 165, config: config) - depth) < 1e-6)
        }
    }
}
