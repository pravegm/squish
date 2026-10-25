import Foundation
import Testing
import UIKit
@testable import Squish

@MainActor
struct CollectionTests {
    // MARK: Helpers

    private func makeStore(at directory: URL? = nil) -> (CollectionStore, URL) {
        let folder = directory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("SquishCollectionTests-\(UUID().uuidString)", isDirectory: true)
        return (CollectionStore(directory: folder), folder)
    }

    /// A seed whose variant is plain (not golden, no surprise), or golden when asked.
    private func findSeed(for kind: ObjectKind, golden: Bool = false, surprise: Bool = false, from start: UInt64 = 1) -> UInt64 {
        var seed = start
        while seed < start + 100_000 {
            let variant = PressVariant(kind: kind, seed: seed)
            let surpriseMatches = surprise ? variant.surprise != nil : variant.surprise == nil
            if variant.isGolden == golden && surpriseMatches { return seed }
            seed += 1
        }
        Issue.record("No seed found for \(kind)")
        return start
    }

    @discardableResult
    private func press(_ store: CollectionStore, _ kind: ObjectKind, perfect: Bool = false, golden: Bool = false,
                       surprise: Bool = false, fractures: Int = 2, duration: Double = 6, reversals: Int = 0,
                       slammed: Bool = false, seedStart: UInt64 = 1,
                       samples: [PressTrace.Sample]? = nil, virtualHinge: Bool = false,
                       onHinge: Bool? = nil, failureAngle: Double? = 101) -> RecordOutcome {
        let seed = findSeed(for: kind, golden: golden, surprise: surprise, from: seedStart)
        let result = PressResult(kind: kind, seed: seed, failureAngle: failureAngle, fractureCount: fractures,
                                 maxCompression: 0.95, duration: duration, wasSlammed: slammed,
                                 isPerfect: perfect, reversals: reversals)
        let variant = PressVariant(kind: kind, seed: seed)
        let trace = samples.map {
            PressTrace(kind: kind, variant: variant, samples: $0, usesVirtualHinge: virtualHinge, config: .standard)
        }
        return store.record(result, variant: variant, trace: trace, onHinge: onHinge)
    }

    // MARK: Hinge trace builders (30 Hz, like a Duo hinge stream)

    private static let sampleRate = 30.0

    /// A steady close from `from` to `to` degrees over `seconds`, starting at `start`.
    private func sweep(from: Double, to: Double, over seconds: Double, at start: Double) -> [PressTrace.Sample] {
        let count = Int((seconds * Self.sampleRate).rounded())
        return (1...count).map { step in
            let t = Double(step) / Double(count)
            return PressTrace.Sample(time: start + t * seconds, angle: from + (to - from) * t, closed: false)
        }
    }

    /// The hinge held still: the same angle reported for `seconds` (a sensor that keeps streaming, the worst case).
    private func hold(_ angle: Double, for seconds: Double, at start: Double) -> [PressTrace.Sample] {
        let count = Int((seconds * Self.sampleRate).rounded())
        return (1...count).map { step in
            PressTrace.Sample(time: start + Double(step) / Self.sampleRate, angle: angle, closed: false)
        }
    }

    /// The engine's arm-to-seal time for a trace: from the first sample 4° below the 168° armed start to the end.
    private func pressDuration(_ samples: [PressTrace.Sample]) -> Double {
        let start = samples.first { $0.angle <= 164 }?.time ?? 0
        return (samples.last?.time ?? 0) - start
    }

    private func tinyPNG() -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 80), format: format).image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 80))
        }
        return image.pngData() ?? Data()
    }

    // MARK: Unlocks

    @Test func sixObjectsOpenAtStart() {
        let (store, _) = makeStore()
        let open: [ObjectKind] = [.bubbleWrap, .rubberDuck, .jelly, .crayon, .egg, .cakeSlice]
        for kind in ObjectKind.allCases {
            #expect(store.isUnlocked(kind) == open.contains(kind), "\(kind)")
        }
    }

    @Test func sodaCanUnlocksAfterThreeDifferentKinds() {
        let (store, _) = makeStore()
        press(store, .bubbleWrap)
        press(store, .bubbleWrap)
        press(store, .bubbleWrap)
        #expect(!store.isUnlocked(.sodaCan))
        press(store, .rubberDuck)
        let outcome = press(store, .jelly)
        #expect(outcome.newlyUnlocked == [.sodaCan])
        #expect(store.isUnlocked(.sodaCan))
    }

    @Test func gummyBearUnlocksAfterSixPresses() {
        let (store, _) = makeStore()
        for _ in 0..<5 { press(store, .egg) }
        #expect(!store.isUnlocked(.gummyBear))
        let outcome = press(store, .egg)
        #expect(outcome.newlyUnlocked.contains(.gummyBear))
        #expect(store.isUnlocked(.gummyBear))
    }

    @Test func glassBottleUnlocksAfterAPerfectSquish() {
        let (store, _) = makeStore()
        press(store, .crayon, slammed: true)
        #expect(!store.isUnlocked(.glassBottle))
        let outcome = press(store, .crayon, perfect: true)
        #expect(outcome.newlyUnlocked == [.glassBottle])
    }

    @Test func unsquishableNeedsAllNineOthersSquished() {
        let (store, _) = makeStore()
        let others = ObjectKind.allCases.filter { $0 != .unsquishable }
        var last: RecordOutcome?
        for (index, kind) in others.enumerated() {
            #expect(!store.isUnlocked(.unsquishable))
            last = press(store, kind, perfect: index == 0)
        }
        #expect(last?.newlyUnlocked.contains(.unsquishable) == true)
        #expect(store.isUnlocked(.unsquishable))
        #expect(store.unlockedCount == 10)
    }

    @Test func unlocksAreReportedOnce() {
        let (store, _) = makeStore()
        press(store, .bubbleWrap)
        press(store, .rubberDuck)
        #expect(press(store, .jelly).newlyUnlocked == [.sodaCan])
        #expect(press(store, .egg).newlyUnlocked.isEmpty)
    }

    // MARK: Best card

    @Test func bestCardPrefersGoldenThenPerfectThenNewest() {
        let (store, _) = makeStore()
        let first = press(store, .rubberDuck)
        #expect(first.isNewBest)
        #expect(store.best(for: .rubberDuck)?.id == first.specimen.id)

        // A newer normal card replaces an older normal one, but isn't a "new best".
        let second = press(store, .rubberDuck, seedStart: 500)
        #expect(!second.isNewBest)
        #expect(store.best(for: .rubberDuck)?.id == second.specimen.id)

        let perfect = press(store, .rubberDuck, perfect: true)
        #expect(perfect.isNewBest)
        press(store, .rubberDuck, seedStart: 900)
        #expect(store.best(for: .rubberDuck)?.id == perfect.specimen.id)

        let golden = press(store, .rubberDuck, golden: true)
        #expect(golden.isNewBest)
        press(store, .rubberDuck, perfect: true, seedStart: 2_000)
        #expect(store.best(for: .rubberDuck)?.id == golden.specimen.id)
    }

    @Test func deletingTheBestCardFallsBackWithoutLosingProgress() {
        let (store, _) = makeStore()
        let normal = press(store, .egg)
        let perfect = press(store, .egg, perfect: true)
        store.delete(perfect.specimen.id)
        #expect(store.best(for: .egg)?.id == normal.specimen.id)
        #expect(store.totalPresses == 2)
        #expect(store.isUnlocked(.glassBottle))
        #expect(store.earnedAchievements.contains(.firstSquish))
        store.delete(normal.specimen.id)
        #expect(store.best(for: .egg) == nil)
        #expect(store.pressedKindsCount == 1)
    }

    @Test func specimensAreNewestFirstAndNumbered() {
        let (store, _) = makeStore()
        press(store, .jelly)
        press(store, .crayon)
        let third = press(store, .egg)
        #expect(store.specimens.map(\.kind) == [.egg, .crayon, .jelly])
        #expect(third.specimen.number == 3)
        #expect(third.specimen.numberLabel == "№0003")
    }

    // MARK: Achievements

    @Test func firstSquishOnTheFirstPress() {
        let (store, _) = makeStore()
        #expect(press(store, .bubbleWrap).newAchievements.contains(.firstSquish))
        #expect(!press(store, .bubbleWrap).newAchievements.contains(.firstSquish))
    }

    @Test func perfectionistAndSteadyHands() {
        let (store, _) = makeStore()
        let kinds: [ObjectKind] = [.bubbleWrap, .rubberDuck, .jelly, .crayon]
        for kind in kinds { press(store, kind, perfect: true) }
        #expect(!store.earnedAchievements.contains(.perfectionist))
        #expect(press(store, .egg, perfect: true).newAchievements.contains(.perfectionist))
        for _ in 0..<4 { press(store, .egg, perfect: true) }
        #expect(!store.earnedAchievements.contains(.steadyHands))
        #expect(press(store, .egg, perfect: true).newAchievements.contains(.steadyHands))
    }

    @Test func perfectionistNeedsDifferentObjects() {
        let (store, _) = makeStore()
        for _ in 0..<6 { press(store, .jelly, perfect: true) }
        #expect(!store.earnedAchievements.contains(.perfectionist))
    }

    @Test func midasAndWhatsInside() {
        let (store, _) = makeStore()
        #expect(press(store, .cakeSlice, golden: true).newAchievements.contains(.midas))
        press(store, .jelly, surprise: true)
        #expect(!store.earnedAchievements.contains(.whatsInside))
        #expect(press(store, .cakeSlice, surprise: true).newAchievements.contains(.whatsInside))
    }

    // MARK: Patience (achievements.md #4: > 30 s of engaged pressing, depth changing at least every 10 s)

    @Test func patienceForAGenuinelySlowPress() {
        let (store, _) = makeStore()
        // Armed and still for 1 s, then one slow, steady 35 s close from 168° to 40°.
        let samples = hold(168, for: 1, at: 0) + sweep(from: 168, to: 40, over: 35, at: 1)
        let duration = pressDuration(samples)
        #expect(duration > 33)
        let outcome = press(store, .egg, duration: duration, samples: samples)
        #expect(outcome.newAchievements.contains(.patience))
        #expect((outcome.specimen.engagedDuration ?? 0) >= 30)
        #expect(store.earnedAchievements.contains(.patience))
    }

    @Test func patienceIgnoresIdleTimeMidPress() {
        let (store, _) = makeStore()
        // 35 s from press start to seal, but 25 s of it is the phone left half-open at 110°.
        let samples = hold(168, for: 2, at: 0)
            + sweep(from: 168, to: 110, over: 6, at: 2)
            + hold(110, for: 25, at: 8)
            + sweep(from: 110, to: 40, over: 5, at: 33)
        let duration = pressDuration(samples)
        #expect(duration > 30)   // the old rule (arm-to-seal > 30 s) would have fired here
        let outcome = press(store, .egg, duration: duration, samples: samples)
        #expect(!outcome.newAchievements.contains(.patience))
        #expect((outcome.specimen.engagedDuration ?? 99) < 10)
        #expect(!store.earnedAchievements.contains(.patience))
    }

    @Test func patienceBreaksOnStallsLongerThanTenSeconds() {
        let (store, _) = makeStore()
        // A staircase: a 15° nudge, then 12 s of nothing, six times (~73 s in all). Never engaged for long.
        var samples = hold(168, for: 1, at: 0)
        var angle = 168.0
        for step in 0..<6 {
            let start = 1 + Double(step) * 12
            samples += sweep(from: angle, to: angle - 15, over: 0.5, at: start)
            angle -= 15
            samples += hold(angle, for: 11.5, at: start + 0.5)
        }
        let outcome = press(store, .egg, duration: pressDuration(samples), samples: samples)
        #expect(!outcome.newAchievements.contains(.patience))
        #expect((outcome.specimen.engagedDuration ?? 99) < 2)
    }

    @Test func patienceToleratesShortPauses() {
        // Pauses of 8 s keep the press engaged (depth changes at least once every 10 s), so they count.
        let samples = hold(168, for: 1, at: 0)
            + sweep(from: 168, to: 120, over: 10, at: 1)
            + hold(120, for: 8, at: 11)
            + sweep(from: 120, to: 60, over: 10, at: 19)
            + hold(60, for: 8, at: 29)
            + sweep(from: 60, to: 40, over: 5, at: 37)
        let duration = pressDuration(samples)
        let engaged = PressEngagement.engagedDuration(samples: samples, pressDuration: duration)
        #expect(abs(engaged - duration) < 0.01)
        #expect(engaged >= PressEngagement.patienceSeconds)
    }

    @Test func patienceNeedsARecordedTrace() {
        let (store, _) = makeStore()
        // Without the input trace the engaged time is unknown, so a long press alone never earns it.
        let outcome = press(store, .egg, duration: 45)
        #expect(outcome.specimen.engagedDuration == nil)
        #expect(!outcome.newAchievements.contains(.patience))
    }

    @Test func engagedTimeExcludesIdleBeforeThePressAndAfterTheSeal() {
        // 20 s armed and untouched, a 5 s press, then 20 s more samples after the seal (closing and reopening).
        let samples = hold(168, for: 20, at: 0)
            + sweep(from: 168, to: 40, over: 5, at: 20)
            + sweep(from: 40, to: 160, over: 20, at: 25)
        let start = samples.first { $0.angle <= 164 }?.time ?? 0
        let engaged = PressEngagement.engagedDuration(samples: samples, pressDuration: 25 - start)
        #expect(engaged <= 25 - start + 0.001)
        #expect(engaged < 6)
    }

    @Test func specimenDecodesWithoutNewerFields() throws {
        let (store, _) = makeStore()
        let outcome = press(store, .egg, samples: sweep(from: 168, to: 40, over: 6, at: 0))
        #expect(outcome.specimen.engagedDuration != nil)
        // A v1.0 record: no `reversals`, no `engagedDuration`.
        let data = try JSONEncoder().encode(outcome.specimen)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["reversals"] = nil
        object["engagedDuration"] = nil
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(SpecimenRecord.self, from: legacy)
        #expect(decoded.id == outcome.specimen.id)
        #expect(decoded.reversals == 0)
        #expect(decoded.engagedDuration == nil)
        #expect(decoded.duration == outcome.specimen.duration)
    }

    @Test func popStarAfterFiveHundredBubbles() {
        let (store, _) = makeStore()
        for _ in 0..<20 { press(store, .bubbleWrap, fractures: 24) }   // 480
        #expect(!store.earnedAchievements.contains(.popStar))
        #expect(press(store, .bubbleWrap, fractures: 24).newAchievements.contains(.popStar))
        #expect(store.stats.bubblesPopped == 504)
    }

    /// Full Set (replaced 1.0's Pumped, App Review 2.4.2): variety, never easing off and pressing again.
    @Test func fullSetNeedsEveryObjectInOneWing() throws {
        let (store, _) = makeStore()
        // Pumping the press earns nothing any more.
        press(store, .jelly, reversals: 5)
        press(store, .jelly, reversals: 5)
        #expect(!store.earnedAchievements.contains(.fullSet))
        // One from each wing isn't a full wing either.
        press(store, .egg)
        press(store, .sodaCan)
        #expect(!store.earnedAchievements.contains(.fullSet))
        let soft = MuseumWing.soft.kinds.filter { $0 != .jelly }
        for kind in soft.dropLast() { press(store, kind) }
        #expect(!store.earnedAchievements.contains(.fullSet))
        let last = try #require(soft.last)
        #expect(press(store, last).newAchievements.contains(.fullSet))
        #expect(store.isWingComplete(.soft))
        #expect(store.pressedCount(in: .soft) == MuseumWing.soft.kinds.count)
    }

    @Test func museumCoversEveryObjectOnce() {
        let all = MuseumWing.allCases.flatMap(\.kinds)
        #expect(all.count == ObjectKind.allCases.count)
        #expect(Set(all) == Set(ObjectKind.allCases))
        #expect(Set(ObjectKind.tourOrder) == Set(ObjectKind.allCases))
        #expect(ObjectKind.tourOrder.first == .bubbleWrap)
        #expect(Achievement.allCases.count == 10)
        for kind in ObjectKind.allCases {
            #expect(!kind.verb.isEmpty && !kind.behaviour.isEmpty)
            #expect((1...5).contains(kind.stiffness))
        }
        for surprise in Surprise.allCases {
            #expect(surprise.kind.possibleSurprises.contains(surprise))
        }
    }

    /// A 1.0 collection that earned "pumped" still loads: the retired achievement is dropped, nothing else.
    @Test func retiredAchievementDoesNotCorruptTheCollection() throws {
        let (store, folder) = makeStore()
        press(store, .egg)
        store.flushSaves()
        let file = folder.appendingPathComponent("collection.json")
        let data = try Data(contentsOf: file)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["earned"] = ["firstSquish", "pumped"]
        try JSONSerialization.data(withJSONObject: object).write(to: file)
        let (reloaded, _) = makeStore(at: folder)
        #expect(reloaded.totalPresses == 1)
        #expect(reloaded.earnedAchievements == [.firstSquish])
    }

    @Test func goalsAndMeasurement() {
        let (store, _) = makeStore()
        press(store, .egg, perfect: true)
        let goals = store.goals(for: .egg)
        #expect(goals.pressed && goals.perfect)
        #expect(goals.golden == false)
        #expect(store.goals(for: .rubberDuck).surprise == nil)
        #expect(store.goals(for: .unsquishable).golden == nil)
        let egg = press(store, .egg).specimen
        let measure = egg.measurement
        #expect(measure.after < measure.before)
        #expect(measure.before > 0)
        let ball = press(store, .unsquishable, fractures: 0).specimen
        #expect(ball.measurement.after == ball.measurement.before)
    }

    @Test func slamsEarnNothingExtra() {
        let (store, _) = makeStore()
        press(store, .egg)
        let slam = press(store, .egg, duration: 0.4, slammed: true)
        #expect(slam.newAchievements.isEmpty)
    }

    @Test func collectorAndTheSecret() {
        let (store, _) = makeStore()
        let others = ObjectKind.allCases.filter { $0 != .unsquishable }
        for (index, kind) in others.enumerated() { press(store, kind, perfect: index == 0) }
        #expect(!store.earnedAchievements.contains(.collector))
        let outcome = press(store, .unsquishable, fractures: 0)
        #expect(outcome.newAchievements.contains(.collector))
        #expect(outcome.newAchievements.contains(.theSecret))
    }

    // MARK: Persistence

    @Test func persistenceRoundTrip() async throws {
        let (store, folder) = makeStore()
        press(store, .bubbleWrap, perfect: true, fractures: 24)
        press(store, .rubberDuck)
        let golden = press(store, .jelly, golden: true)
        await store.attachThumbnail(tinyPNG(), to: golden.specimen.id).value

        let (reloaded, _) = makeStore(at: folder)
        #expect(reloaded.specimens == store.specimens)
        #expect(reloaded.totalPresses == 3)
        #expect(reloaded.earnedAchievements == store.earnedAchievements)
        #expect(reloaded.isUnlocked(.sodaCan))
        #expect(reloaded.isUnlocked(.glassBottle))
        #expect(reloaded.stats == store.stats)
        let best = try #require(reloaded.best(for: .jelly))
        #expect(best.id == golden.specimen.id)
        let url = try #require(reloaded.thumbnailURL(for: best))
        #expect(FileManager.default.fileExists(atPath: url.path))
        let image = try #require(reloaded.loadThumbnail(for: best))
        #expect(image.size.width == CollectionStore.thumbnailSize)
        #expect(image.size.width == image.size.height)
    }

    @Test func corruptFileStartsFreshWithoutCrashing() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("SquishCollectionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: folder.appendingPathComponent("collection.json"))
        let store = CollectionStore(directory: folder)
        #expect(store.specimens.isEmpty)
        #expect(store.totalPresses == 0)
        press(store, .egg)
        let (reloaded, _) = makeStore(at: folder)
        #expect(reloaded.totalPresses == 1)
    }

    // MARK: Launch QA: forward-compatible files, background saves, pruning, traces

    /// A newer build's file (an extra field, an object, surprise and stat this build doesn't know) loads everything this
    /// build does know: it used to fail as a whole, get set aside as corrupt, and leave an empty collection.
    @Test func newerFileWithUnknownKindsStillLoads() throws {
        let (store, folder) = makeStore()
        press(store, .bubbleWrap, fractures: 12)
        press(store, .egg, perfect: true)
        store.flushSaves()
        let file = folder.appendingPathComponent("collection.json")
        var object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        object["futureField"] = ["anything": 1]
        var specimens = try #require(object["specimens"] as? [[String: Any]])
        var alien = try #require(specimens.first)
        alien["kind"] = "spaceship"
        alien["id"] = UUID().uuidString
        specimens.append(alien)
        object["specimens"] = specimens
        object["unlocked"] = ((object["unlocked"] as? [String]) ?? []) + ["spaceship"]
        var stats = try #require(object["stats"] as? [String: Any])
        stats["squishedKinds"] = ((stats["squishedKinds"] as? [String]) ?? []) + ["spaceship"]
        stats["surprisesFound"] = ["dragonEgg"]
        stats["warpCount"] = 7
        object["stats"] = stats
        try JSONSerialization.data(withJSONObject: object).write(to: file)

        let (reloaded, _) = makeStore(at: folder)
        #expect(reloaded.specimens.count == 2)
        #expect(reloaded.totalPresses == 2)
        #expect(reloaded.stats.squishedKinds == [.bubbleWrap, .egg])
        #expect(reloaded.stats.perfectCount == 1)
        #expect(reloaded.stats.bubblesPopped == 12)
        #expect(reloaded.stats.surprisesFound.isEmpty)
        #expect(reloaded.best(for: .egg) != nil)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(!leftovers.contains { $0.hasPrefix("collection.corrupt") })
    }

    /// Missing fields (an older or hand-trimmed file) take their defaults instead of failing.
    @Test func statsWithMissingFieldsTakeDefaults() throws {
        let data = Data(#"{"squishedKinds":["egg","sparkle"],"perfectCount":3}"#.utf8)
        let stats = try JSONDecoder().decode(CollectionStore.Stats.self, from: data)
        #expect(stats.squishedKinds == [.egg])
        #expect(stats.perfectCount == 3)
        #expect(stats.goldenCount == 0)
        #expect(stats.longestPress == 0)
    }

    /// Real seeds span the whole UInt64 range; one above Int64.max survives a save and a reload exactly.
    @Test func seedsAboveInt64MaxRoundTrip() {
        let (store, folder) = makeStore()
        let seeds: [UInt64] = [UInt64(Int64.max) + 1, UInt64.max, UInt64.max - 12_345]
        for seed in seeds {
            let result = PressResult(kind: .crayon, seed: seed, failureAngle: 90, fractureCount: 3, maxCompression: 0.9,
                                     duration: 5, wasSlammed: false, isPerfect: false, reversals: 0)
            _ = store.record(result, variant: PressVariant(kind: .crayon, seed: seed))
        }
        let (reloaded, _) = makeStore(at: folder)
        #expect(reloaded.specimens.map(\.variant.seed).sorted() == seeds.sorted())
    }

    /// At the 500-specimen cap the oldest cards go with their photos and traces, but a best card stays, photo and all.
    @Test func pruningAtTheCapDeletesPhotosAndTracesButKeepsBests() async throws {
        let (store, folder) = makeStore()
        // The oldest two: a Golden duck (the duck's best, forever) and a plain bubble wrap.
        let golden = press(store, .rubberDuck, golden: true)
        let plain = press(store, .bubbleWrap)
        await store.attachThumbnail(tinyPNG(), to: golden.specimen.id).value
        await store.attachThumbnail(tinyPNG(), to: plain.specimen.id).value
        let traces = store.traceDirectory
        try FileManager.default.createDirectory(at: traces, withIntermediateDirectories: true)
        for id in [golden.specimen.id, plain.specimen.id] {
            try Data("{}".utf8).write(to: traces.appendingPathComponent("\(id.uuidString).json"))
        }
        let goldenCard = try #require(store.specimen(withID: golden.specimen.id))
        let plainCard = try #require(store.specimen(withID: plain.specimen.id))
        let goldenPhoto = try #require(store.thumbnailURL(for: goldenCard))
        let plainPhoto = try #require(store.thumbnailURL(for: plainCard))
        // Fill the shelf past the cap with plain bubble wrap: both old cards fall off the end.
        for _ in 0..<CollectionStore.capacity {
            press(store, .bubbleWrap)
        }
        #expect(store.specimens.count == CollectionStore.capacity)
        #expect(!store.specimens.contains { $0.id == plain.specimen.id })
        #expect(!store.specimens.contains { $0.id == golden.specimen.id })
        // The plain card's photo and trace are gone; the Golden best keeps both.
        #expect(!FileManager.default.fileExists(atPath: plainPhoto.path))
        #expect(FileManager.default.fileExists(atPath: goldenPhoto.path))
        #expect(store.best(for: .rubberDuck)?.id == golden.specimen.id)
        let plainTrace = traces.appendingPathComponent("\(plain.specimen.id.uuidString).json")
        let goldenTrace = traces.appendingPathComponent("\(golden.specimen.id.uuidString).json")
        for _ in 0..<40 where FileManager.default.fileExists(atPath: plainTrace.path) {
            try await Task.sleep(for: .milliseconds(50))   // the trace delete runs off the main thread
        }
        #expect(!FileManager.default.fileExists(atPath: plainTrace.path))
        #expect(FileManager.default.fileExists(atPath: goldenTrace.path))
        // And the cap survives a reload (the save went to the background writer).
        let (reloaded, _) = makeStore(at: folder)
        #expect(reloaded.specimens.count == CollectionStore.capacity)
        #expect(reloaded.best(for: .rubberDuck)?.id == golden.specimen.id)
    }

    /// Deleting a card deletes its share-clip trace; progress stays.
    @Test func deletingACardDeletesItsTrace() async throws {
        let (store, _) = makeStore()
        press(store, .jelly)
        let second = press(store, .jelly)
        let traces = store.traceDirectory
        try FileManager.default.createDirectory(at: traces, withIntermediateDirectories: true)
        let trace = traces.appendingPathComponent("\(second.specimen.id.uuidString).json")
        try Data("{}".utf8).write(to: trace)
        // Delete the newest jelly (the best): the best falls back to the older card, and this card's trace goes.
        store.delete(second.specimen.id)
        for _ in 0..<40 where FileManager.default.fileExists(atPath: trace.path) {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(!FileManager.default.fileExists(atPath: trace.path))
        #expect(store.totalPresses == 2)
    }

    /// A photo attached to a card that was deleted meanwhile leaves no file behind.
    @Test func photoForADeletedCardLeavesNoFile() async throws {
        let (store, folder) = makeStore()
        let outcome = press(store, .egg)
        let task = store.attachThumbnail(tinyPNG(), to: outcome.specimen.id)
        store.delete(outcome.specimen.id)
        await task.value
        let file = folder.appendingPathComponent("\(outcome.specimen.id.uuidString).png")
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    /// Thumbnails decode off the main thread on demand, at the size asked for.
    @Test func rowThumbnailsAreSmallAndArriveAsync() async throws {
        let (store, folder) = makeStore()
        let outcome = press(store, .crayon)
        await store.attachThumbnail(tinyPNG(), to: outcome.specimen.id).value
        let (reloaded, _) = makeStore(at: folder)   // a cold cache
        let card = try #require(reloaded.specimen(withID: outcome.specimen.id))
        #expect(reloaded.rowThumbnail(for: card) == nil)   // a miss starts the decode and returns at once
        var row: UIImage?
        for _ in 0..<40 {
            row = reloaded.rowThumbnail(for: card)
            if row != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let image = try #require(row)
        #expect(image.size.width <= CollectionStore.rowThumbnailPixels)
    }

    // MARK: Copy

    @Test func cardTraitsAndSentence() {
        let (store, _) = makeStore()
        let outcome = press(store, .egg, perfect: true, golden: true, onHinge: true)
        let texts = outcome.specimen.traits.map(\.text)
        #expect(texts.first == "GOLDEN")
        #expect(texts.contains("PERFECT SQUISH"))
        #expect(outcome.specimen.accessibilitySentence.contains("Egg"))
        #expect(outcome.specimen.labelLines.first == "CRUSHED AT \(outcome.specimen.tons) TONS")
        #expect(outcome.specimen.labelLines.count == 2)
        #expect(outcome.specimen.gaveAtTag == "AT \(outcome.specimen.tons) TONS")
        for achievement in Achievement.allCases {
            #expect(!achievement.title.isEmpty && !achievement.detail.isEmpty)
        }
    }

    // MARK: Hinge angle only where a hinge made the press (FOLD-REVIEW-5 N6)

    @Test func touchPressCardsShowTonsNotDegrees() {
        let (store, _) = makeStore()
        let outcome = press(store, .rubberDuck, samples: sweep(from: 168, to: 40, over: 6, at: 0), virtualHinge: true)
        let specimen = outcome.specimen
        #expect(!specimen.madeOnHinge)
        #expect(specimen.hingeFailureAngle == nil)
        #expect(specimen.labelLines.first == "CRUSHED AT \(specimen.tons) TONS")
        #expect(specimen.gaveAtTag == "AT \(specimen.tons) TONS")
        #expect(!specimen.labelLines.joined().contains("°"))
        #expect(!specimen.accessibilitySentence.contains("degrees"))
        #expect(specimen.accessibilitySentence.contains("crushed at \(specimen.tons) tons"))
    }

    /// EXPERIENCE-REVIEW-1 #4: no user-facing hinge angle anywhere, even when a real hinge made the press.
    @Test func hingeTraceCardsShowTonsNotDegrees() {
        let (store, _) = makeStore()
        let outcome = press(store, .rubberDuck, samples: sweep(from: 168, to: 40, over: 6, at: 0), virtualHinge: false)
        #expect(outcome.specimen.madeOnHinge)
        #expect(outcome.specimen.hingeFailureAngle == Int(101))
        #expect(outcome.specimen.labelLines.first == "CRUSHED AT \(outcome.specimen.tons) TONS")
        #expect(!outcome.specimen.labelLines.joined().contains("°"))
        #expect(!outcome.specimen.accessibilitySentence.contains("degrees"))
    }

    /// EXPERIENCE-REVIEW-1 #6: the coach speaks before contact and after the break settles, never over the press.
    @Test func coachNeverTalksOverThePress() {
        func line(_ c: Double, depth: Double, broken: Bool = false, stalled: Bool = false, speed: Double = 20,
                  index: Int = 0, phase: PressPhase = .pressing) -> String? {
            CoachLine.line(phase: phase, compression: c, depth: depth, contactDepth: 0.3, broken: broken,
                           stalledAfterBreak: stalled, closingSpeed: speed, slamSpeed: 250, touch: false,
                           pressIndex: index)?.title
        }
        #expect(line(0, depth: 0.1) == "CLOSE IT SLOWLY")
        #expect(line(0, depth: 0.1, index: 2) == nil)            // presses 2–5 only react
        #expect(line(0, depth: 0.1, speed: 200, index: 3) == "EASY…")
        #expect(line(0.2, depth: 0.45) == nil)                    // contact and strain: silence
        #expect(line(0.6, depth: 0.7, broken: true) == nil)       // the break and its settle: silence
        #expect(line(0.6, depth: 0.7, broken: true, stalled: true) == "ALL THE WAY")
        #expect(line(0.2, depth: 0.45, speed: -40) == "EASED OFF")
        #expect(line(1, depth: 1, phase: .sealed) == "KA-CHUNK!")
        #expect(line(0, depth: 0.1, index: 5) == nil)            // after the first five, nothing
    }

    @Test func pressWithoutTraceOrFlagIsNotClaimedAsHinge() {
        let (store, _) = makeStore()
        let outcome = press(store, .egg)
        #expect(!outcome.specimen.madeOnHinge)
        #expect(outcome.specimen.labelLines.first?.hasPrefix("CRUSHED AT ") == true)
        #expect(outcome.specimen.labelLines.first?.contains("°") == false)
    }

    @Test func nothingGaveShowsPeakTons() {
        let (store, _) = makeStore()
        let hinge = press(store, .jelly, onHinge: true, failureAngle: nil)
        #expect(hinge.specimen.labelLines.first == "PEAK \(hinge.specimen.tons) TONS")
        #expect(hinge.specimen.gaveAtTag == nil)
        let ball = press(store, .unsquishable, fractures: 0, onHinge: true)
        #expect(ball.specimen.labelLines.first == "PEAK \(ball.specimen.tons) TONS")
        #expect(ball.specimen.gaveAtTag == nil)
    }

    @Test func hingeFlagRoundTripsAndDefaultsToFalse() throws {
        let (store, folder) = makeStore()
        let hinge = press(store, .egg, onHinge: true)
        let (reloaded, _) = makeStore(at: folder)
        #expect(reloaded.specimen(withID: hinge.specimen.id)?.madeOnHinge == true)

        // A record written before the flag existed: decodes as a touch press (never claims a hinge).
        let data = try JSONEncoder().encode(hinge.specimen)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["madeOnHinge"] = nil
        let legacy = try JSONDecoder().decode(SpecimenRecord.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(!legacy.madeOnHinge)
        #expect(legacy.failureAngle == 101)
    }

    // MARK: Fold Press toast slot (FOLD-REVIEW-4 F4)

    /// Duo book (951 × 669), Duo tabletop (669 × 951), and the simulated tabletop fold on an iPhone 18 Pro and Pro Max.
    @Test(arguments: [CGSize(width: 951, height: 669), CGSize(width: 669, height: 951),
                      CGSize(width: 402, height: 874), CGSize(width: 440, height: 956)])
    func toastSlotStaysOffTheCrownPlatesAndCrease(canvas: CGSize) {
        let layout = FoldLayout(canvas: canvas)
        let slot = layout.toastSlot
        #expect(CGRect(origin: .zero, size: canvas).contains(slot))
        #expect(slot.width >= 300)
        #expect(slot.height >= FoldLayout.toastHeight)
        // The crown strip holds the gauge, the lamps and the hinge-angle readout.
        #expect(!slot.intersects(layout.crownStrip))
        #expect(!slot.intersects(layout.strikePlate(platen: true)))
        #expect(!slot.intersects(layout.strikePlate(platen: false)))
        #expect(!slot.intersects(layout.creaseRect))
        #expect(!slot.intersects(layout.consoleBand))
        // Clear of the reveal's print label (centred 24 pt under the platen plate, up to two lines ≈ 46 pt).
        let plate = layout.strikePlate(platen: true)
        let field = layout.platenField
        let label = CGRect(x: field.minX + 24, y: plate.maxY + 24 - 23, width: field.width - 48, height: 46)
        #expect(!slot.intersects(label))
    }

    // MARK: Sheets on a foldable (FOLD-REVIEW-6 N4)

    /// Tabletop Duo: the Shelf at the 0.45 detent is 669 × ~430 pt, wider than tall, but the window is portrait, so
    /// the sheet keeps its full width (it was squeezed into the right 45 %).
    @Test func tabletopSheetKeepsFullWidthAtEveryDetent() {
        for sheet in [CGSize(width: 669, height: 428), CGSize(width: 669, height: 900)] {
            #expect(SheetCreaseLayout.layout(hasHinge: true, windowIsLandscape: false, sheet: sheet) == .full)
        }
    }

    /// Book pose: the trailing half, clear of the 40 pt crease.
    @Test func bookPoseSheetTakesTheTrailingHalf() {
        let layout = SheetCreaseLayout.layout(hasHinge: true, windowIsLandscape: true, sheet: CGSize(width: 951, height: 640))
        #expect(layout == .trailingHalf(width: 951 / 2 - ScreenBands.creaseHalf))
    }

    /// Regular iPhones never split, in either orientation.
    @Test func noHingeNeverSplits() {
        #expect(SheetCreaseLayout.layout(hasHinge: false, windowIsLandscape: true, sheet: CGSize(width: 874, height: 380)) == .full)
        #expect(SheetCreaseLayout.layout(hasHinge: false, windowIsLandscape: false, sheet: CGSize(width: 402, height: 430)) == .full)
    }

    // MARK: Settings copy (FOLD-REVIEW-6 N11)

    @Test func lastTwoWordsAreJoinedWithANoBreakSpace() {
        #expect("for each moment.".keepingLastWordsTogether == "for each\u{00A0}moment.")
        #expect("Squish".keepingLastWordsTogether == "Squish")
        #expect("".keepingLastWordsTogether == "")
        #expect("trailing ".keepingLastWordsTogether == "trailing ")
    }

    /// FOLD-REVIEW-7 N7: a last word that is long, or already an unbreakable path, is left alone, so the line
    /// breaks before it ("Follows your iPhone setting / (Settings › Accessibility › Motion).").
    @Test func longOrUnbreakableLastWordIsNotGlued() {
        let path = "(Settings\u{00A0}›\u{00A0}Accessibility\u{00A0}›\u{00A0}Motion)."
        let footnote = "Follows your iPhone setting \(path)"
        #expect(footnote.keepingLastWordsTogether == footnote)
        #expect("Tap for internationalisation".keepingLastWordsTogether == "Tap for internationalisation")
        // At the limit it still glues.
        let twelve = String(repeating: "a", count: String.orphanGlueLimit)
        #expect("one \(twelve)".keepingLastWordsTogether == "one\u{00A0}\(twelve)")
    }

    // MARK: Shelf meta lines (FOLD-REVIEW-7 N6)

    @Test func dotSeparatorsAreGluedOnBothSides() {
        #expect("SQUISH 3 DIFFERENT THINGS · 1/3".gluingDotSeparators == "SQUISH 3 DIFFERENT THINGS\u{00A0}·\u{00A0}1/3")
        #expect("NO SEPARATOR".gluingDotSeparators == "NO SEPARATOR")
    }

    /// The two-line meta never leaves a "·" at a line end: flags (glued) on line 1, the number on line 2.
    @Test func twoLineMetaPutsTheNumberOnItsOwnLine() {
        #expect(ShelfMetaLines.twoLines(["PERFECT", "№0001"]) == "PERFECT\n№0001")
        #expect(ShelfMetaLines.twoLines(["GOLDEN", "PERFECT", "№0042"]) == "GOLDEN\u{00A0}·\u{00A0}PERFECT\n№0042")
        #expect(ShelfMetaLines.twoLines(["№0007"]) == "№0007")
        #expect(ShelfMetaLines.twoLines([]) == "")
        for text in [ShelfMetaLines.twoLines(["PERFECT", "№0001"]), ShelfMetaLines.twoLines(["GOLDEN", "PERFECT", "№0042"])] {
            for line in text.split(separator: "\n") {
                #expect(!line.hasSuffix("·") && !line.hasSuffix("· "))
            }
        }
    }

    /// The secret slot's hint is short enough for two lines in the 5-column tabletop grid (it truncated as
    /// "SOME THINGS REFUSE TO BE S…").
    @Test func secretSlotHintIsShort() {
        let hint = CollectionStore.secretSlotHint.uppercased()
        #expect(hint.count <= 26)
        #expect(hint.split(separator: " ").allSatisfy { $0.count <= 13 })
    }

    // MARK: Tabletop Shelf split (FOLD-REVIEW-7 N5)

    /// The Duo's tabletop window is 669 × 951 pt; the crease's centre is ~455 pt above a ~20 pt safe bottom.
    @Test func tabletopLargeShelfSplitsAtTheCrease() {
        let sheet = CGSize(width: 669, height: 909)
        let line = ShelfTabletopLayout.creaseLine(sheet: sheet, creaseAboveSafeBottom: 455, accessibilitySize: false)
        #expect(line == CGFloat(909 - 455))   // typed: an untyped literal picked a non-numeric == (run 39911250350)
    }

    @Test func shelfDoesNotSplitOffTabletopLarge() {
        // The 0.45 detent: wider than tall.
        #expect(ShelfTabletopLayout.creaseLine(sheet: CGSize(width: 669, height: 428), creaseAboveSafeBottom: 455,
                                               accessibilitySize: false) == nil)
        // Regular iPhone and book pose: no crease is handed down.
        #expect(ShelfTabletopLayout.creaseLine(sheet: CGSize(width: 402, height: 800), creaseAboveSafeBottom: nil,
                                               accessibilitySize: false) == nil)
        // Book pose's trailing half is narrow even if a value leaked through.
        #expect(ShelfTabletopLayout.creaseLine(sheet: CGSize(width: 455, height: 640), creaseAboveSafeBottom: 300,
                                               accessibilitySize: false) == nil)
        // Accessibility sizes keep the one-column scrolling grid.
        #expect(ShelfTabletopLayout.creaseLine(sheet: CGSize(width: 669, height: 909), creaseAboveSafeBottom: 455,
                                               accessibilitySize: true) == nil)
        // A crease far from the middle (a stale value) is ignored.
        #expect(ShelfTabletopLayout.creaseLine(sheet: CGSize(width: 669, height: 909), creaseAboveSafeBottom: 100,
                                               accessibilitySize: false) == nil)
    }

    /// The 5 × 2 grid's cards shrink just enough for both rows to end above the crease band.
    @Test func tabletopGridFitsTheRamHalf() {
        let width: CGFloat = 669 - 48, height: CGFloat = 293
        let card = ShelfTabletopLayout.cardWidth(width: width, height: height, columns: 5, rows: 2, spacing: 16, rowSpacing: 12)
        #expect(card <= (width - 4 * 16) / 5)
        #expect(2 * (card / 0.75) + 12 <= height + 0.5)
        // Plenty of height: the columns' own width wins.
        let roomy = ShelfTabletopLayout.cardWidth(width: width, height: 2000, columns: 5, rows: 2, spacing: 16, rowSpacing: 12)
        #expect(abs(roomy - (width - 4 * 16) / 5) < 0.01)
    }

    /// The anvil half's prints fill the half without overflowing it, and the hero matches the 2 × 2's height.
    @Test func recentPrintsFillTheAnvilHalf() {
        let width: CGFloat = 621, height: CGFloat = 346, caption: CGFloat = 44, spacing: CGFloat = 12
        let fit = ShelfTabletopLayout.recent(width: width, height: height, caption: caption, spacing: spacing)
        #expect(fit.small > 100)
        #expect(fit.hero + spacing + 2 * fit.small + spacing <= width + 0.5)
        #expect(2 * (fit.small + caption) + spacing <= height + 0.5)
        #expect(abs((fit.hero + caption) - (2 * (fit.small + caption) + spacing)) < 0.01)
        // Over 80 % of the half's width is used.
        #expect(fit.hero + 2 * fit.small + 2 * spacing >= width * 0.8)
    }

    // MARK: Prints for specimens (FOLD-REVIEW-8 N2)

    /// RGBA of one pixel (x, y from the top left) of a decoded image.
    private func pixel(_ image: UIImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int)? {
        guard let cg = image.cgImage else { return nil }
        var data = [UInt8](repeating: 0, count: 4)
        let drawn: Bool = data.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            // Shift the image so that pixel (x, y) lands on the single bitmap pixel (CG's origin is bottom left).
            ctx.draw(cg, in: CGRect(x: -x, y: -(cg.height - 1 - y), width: cg.width, height: cg.height))
            return true
        }
        return drawn ? (Int(data[0]), Int(data[1]), Int(data[2])) : nil
    }

    /// A square card (the specimen shot, the Fold diptych) is stored whole, upright, only downscaled: the full-screen
    /// crop used to cut a rotated 58 % window out of it.
    @Test func squareCardsAreStoredWhole() async throws {
        let (store, _) = makeStore()
        let outcome = press(store, .rubberDuck)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let card = UIGraphicsImageRenderer(size: CGSize(width: 720, height: 720), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 720, height: 360))   // the print half
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 360, width: 720, height: 360))   // the specimen half
        }
        let png = try #require(card.pngData())
        await store.attachThumbnail(png, to: outcome.specimen.id).value
        let first = try #require(store.specimens.first)   // #require can't nest inside #require
        let stored = try #require(store.loadThumbnail(for: first))
        #expect(stored.size == CGSize(width: CollectionStore.thumbnailSize, height: CollectionStore.thumbnailSize))
        let top = try #require(pixel(stored, x: 8, y: 8))
        let bottom = try #require(pixel(stored, x: 8, y: 500))
        #expect(top.r > 200 && top.b < 60, "top-left should be the print half (red), got \(top)")
        #expect(bottom.b > 200 && bottom.r < 60, "bottom-left should be the specimen half (blue), got \(bottom)")
    }

    /// The mirrored rest heights match the object views' own constants (SpecimenPrint can't read the main-actor ones).
    @Test func printRestHeightsMatchTheObjects() {
        let plain = { (kind: ObjectKind) in PressVariant(kind: kind, seed: SpecimenPrint.plainSeed(for: kind)) }
        func near(_ a: Double, _ b: Float) -> Bool { abs(a - Double(b)) < 1e-5 }
        #expect(near(SpecimenPrint.restHeight(.rubberDuck, variant: plain(.rubberDuck)), 0.085 * DuckView.heroScale))
        #expect(near(SpecimenPrint.restHeight(.gummyBear, variant: plain(.gummyBear)), 0.107 * GummyBearView.heroScale))
        #expect(near(SpecimenPrint.restHeight(.glassBottle, variant: plain(.glassBottle)), 0.060 * GlassBottleView.heroScale))
        #expect(near(SpecimenPrint.restHeight(.crayon, variant: plain(.crayon)), 2 * CrayonView.radius))
    }

    /// Every pressable object has a print card, square, at the diptych's size.
    @Test func everyObjectHasAPrintCard() throws {
        for kind in ObjectKind.allCases {
            let seed = SpecimenPrint.plainSeed(for: kind)
            let fractures = SpecimenPrint.fractureCount(kind, seed: seed, maxCompression: 0.96)
            let specimen = SpecimenRecord(id: UUID(), number: 1, kind: kind, date: Date(),
                                          variant: PressVariant(kind: kind, seed: seed), fractureCount: fractures,
                                          maxCompression: 0.96, failureAngle: nil, duration: 5, isPerfect: false,
                                          wasSlammed: false)
            let card = try #require(SpecimenPrint.card(for: specimen), "\(kind)")
            #expect(card.size == CGSize(width: 720, height: 720), "\(kind)")
            #expect(SpecimenPrint.cachedCard(for: specimen) != nil, "\(kind)")
        }
        // Never touched: no print.
        #expect(SpecimenPrint.printImage(kind: .jelly, variant: PressVariant(kind: .jelly, seed: 3),
                                         maxCompression: 0, fractureCount: 0) == nil)
    }

    /// The derived failure angle is the one the engine itself records, for a press opened flat and closed steadily.
    @Test func derivedFailureAngleMatchesTheEngine() throws {
        for kind in ObjectKind.allCases where kind.profile.failureIndex != nil {
            let seed = SpecimenPrint.plainSeed(for: kind, from: 40)
            let engine = PressEngine()
            engine.activate(at: 0)
            engine.load(kind, seed: seed, at: 0)
            var t = 2.0
            for _ in 0..<30 {   // open flat, still
                engine.ingest(angle: 180, closed: false, at: t)
                t += 1 / Self.sampleRate
            }
            var angle = 180.0
            while angle > 50 {   // 10°/s
                angle -= 10 / Self.sampleRate
                engine.ingest(angle: angle, closed: false, at: t)
                engine.step(now: t, dt: 1 / Self.sampleRate)
                t += 1 / Self.sampleRate
            }
            let recorded = try #require(engine.failureAngle, "\(kind)")
            let derived = try #require(SpecimenPrint.failureAngle(kind, seed: seed), "\(kind)")
            #expect(abs(recorded - derived) < 1.0, "\(kind): engine \(recorded)° vs derived \(derived)°")
        }
        #expect(SpecimenPrint.failureAngle(.bubbleWrap, seed: 1) == nil)
    }

    #if DEBUG
    /// Seeded demo cards are pressed specimens: each carries its print thumbnail, real fracture counts, and a failure
    /// angle a real press gives (FOLD-REVIEW-8 N2: not intact icons, not "AT 128°").
    @Test func seededDemoSpecimensCarryPrintsAndRealAngles() throws {
        let (store, _) = makeStore()
        store.seedDemo(count: 7, onHinge: true)
        #expect(store.specimens.count == 7)
        for specimen in store.specimens {
            let image = try #require(store.loadThumbnail(for: specimen), "\(specimen.kind) has no thumbnail")
            #expect(image.size.width == CollectionStore.thumbnailSize && image.size.height == CollectionStore.thumbnailSize)
            #expect(store.best(for: specimen.kind)?.thumbnailFile != nil, "\(specimen.kind) best card")
            #expect(specimen.fractureCount == SpecimenPrint.fractureCount(specimen.kind, seed: specimen.variant.seed,
                                                                          maxCompression: specimen.maxCompression))
            #expect(specimen.failureAngle == SpecimenPrint.failureAngle(specimen.kind, seed: specimen.variant.seed))
            if specimen.kind == .bubbleWrap {
                #expect(specimen.failureAngle == nil)
            } else {
                let angle = try #require(specimen.failureAngle, "\(specimen.kind)")
                // Every failure lands between the display-off floor and the contact (the provisional fold mapping,
                // PressConfig: failures at ~94–64°, at least 10° of resistance after contact).
                #expect(angle >= PressFeel.failureFloorAngle && angle < PressConfig.standard.contactCeiling - 10,
                        "\(specimen.kind) AT \(angle)°")
            }
        }
        // Late failures (the duck's seam, jelly, cake, can) land in the 60–85° the store shots show.
        for kind: ObjectKind in [.rubberDuck, .jelly, .cakeSlice, .sodaCan] {
            let angle = try #require(store.specimens.first { $0.kind == kind }?.failureAngle)
            #expect((60...85).contains(angle), "\(kind) AT \(angle)°")
        }
    }

    /// The seeded can is the set's green FIZZO, not an orange or berry print (FOLD-REVIEW-9 N2): it is the Shelf's
    /// hero tile and the cover's first recent tile, so it must match the lime the store presses (`seed=3`) show.
    @Test func seededDemoCanIsTheGreenFizzo() throws {
        let (store, _) = makeStore()
        store.seedDemo(count: 7, onHinge: true)
        let can = try #require(store.specimens.first { $0.kind == .sodaCan })
        #expect(!can.variant.isGolden)
        #expect(can.variant.surprise == nil)
        #expect(CollectionStore.isGreenFizz(FoldStamps.canFizz(can.variant)))
        // The store presses' seed is the same green; since EXPERIENCE-REVIEW-1 #5 every plain can's fizz is its lime
        // flavour (the old seeded orange / berry fizz in a lime can is gone), so the old pick is green too.
        #expect(CollectionStore.isGreenFizz(FoldStamps.canFizz(PressVariant(kind: .sodaCan, seed: 3))))
        #expect(CollectionStore.isGreenFizz(FoldStamps.canFizz(PressVariant(kind: .sodaCan, seed: 48_514))))
        // Every salt finds a plain green can.
        for salt: UInt64 in 0..<8 {
            let seed = CollectionStore.demoSeed(for: .sodaCan, golden: false, surprise: false, salt: salt)
            let variant = PressVariant(kind: .sodaCan, seed: seed)
            #expect(!variant.isGolden && variant.surprise == nil, "salt \(salt)")
            #expect(CollectionStore.isGreenFizz(FoldStamps.canFizz(variant)), "salt \(salt) seed \(seed)")
        }
        // Other kinds keep their seeds: the filter is the can's alone.
        #expect(CollectionStore.demoSeed(for: .rubberDuck, golden: false, surprise: false, salt: 1)
                == SpecimenPrint.plainSeed(for: .rubberDuck, from: 1_000 + 7_919))
    }
    #endif

    // MARK: SLO-MO on request (founder, real Duo: the automatic replay read as "why is the object back?")

    /// No film starts without a tap: a reveal starts on the specimen with no takes, the finished ceremony has no
    /// replay step left, and the key is the only thing that shows before a film.
    @Test func sloMoNeverStartsWithoutATap() {
        let fresh = SloMoState()
        #expect(fresh.phase == .specimen)
        #expect(fresh.takes == 0)
        #expect(!fresh.isPlaying)
        #expect(fresh.take == nil)
        #expect(fresh.showsKey(replayAvailable: true))
        #expect(!fresh.showsKey(replayAvailable: false))
        // Nothing to play (no tape, cover display dark): a tap changes nothing.
        var empty = SloMoState()
        let none = empty.begin(duration: nil)
        #expect(none == nil)
        let zero = empty.begin(duration: 0)
        #expect(zero == nil)
        #expect(empty == SloMoState())
        // The reveal's settled flag is up as soon as the reveal lights when nobody asked for a replay.
        #expect(FoldPressController.specimenSettled(replaying: false, replayStarted: false, sinceReplayEnded: nil))
    }

    /// A tap starts a take; a tap on the film (or its end) hands back with a settle; the key comes back; and it plays
    /// again, any number of times. Late timers of a skipped take do nothing.
    @Test func sloMoTapPlaysSkipsAndReplays() {
        var slomo = SloMoState()
        let first = slomo.begin(duration: 9)
        #expect(first == Int(1))
        #expect(slomo.isPlaying)
        #expect(!slomo.showsKey(replayAvailable: true))
        // Capped, so a film never runs on.
        #expect(slomo.phase == .playing(take: 1, duration: RevealCeremony.replayCap))
        // A second tap on the (hidden) key during the film starts nothing.
        let duringFilm = slomo.begin(duration: 6)
        #expect(duringFilm == nil)
        #expect(slomo.takes == 1)
        // A tap on the film skips back: settling, then the specimen with the key.
        let skipped = slomo.endFilm(take: 1)
        #expect(skipped)
        #expect(slomo.phase == .settling(take: 1))
        #expect(!slomo.canPlay)
        // The film's own end timer, firing after the skip, does nothing.
        let lateTimer = slomo.endFilm(take: 1)
        #expect(!lateTimer)
        slomo.settled(take: 1)
        #expect(slomo.phase == .specimen)
        #expect(slomo.showsKey(replayAvailable: true))
        // Again, and again.
        for take in 2...4 {
            let started = slomo.begin(duration: 2)
            #expect(started == take)
            #expect(slomo.phase == .playing(take: take, duration: 2))
            let stale = slomo.endFilm(take: take - 1)
            #expect(!stale)
            let ended = slomo.endFilm(take: take)
            #expect(ended)
            slomo.settled(take: take - 1)   // a stale settle is ignored
            #expect(slomo.phase == .settling(take: take))
            slomo.settled(take: take)
            #expect(slomo.canPlay)
        }
        #expect(slomo.takes == 4)
    }

    /// The specimen afterwards: not settled while a replay plays, nor just after it hands back; settled
    /// `settleAfterReplay` seconds later (CI's reveal frames wait for this).
    @Test func specimenSettlesAfterARequestedReplay() {
        #expect(!FoldPressController.specimenSettled(replaying: true, replayStarted: true, sinceReplayEnded: nil))
        #expect(!FoldPressController.specimenSettled(replaying: true, replayStarted: false, sinceReplayEnded: nil))
        #expect(!FoldPressController.specimenSettled(replaying: false, replayStarted: true, sinceReplayEnded: 0.1))
        #expect(FoldPressController.specimenSettled(replaying: false, replayStarted: true,
                                                    sinceReplayEnded: FoldPressController.settleAfterReplay))
        #expect(FoldPressController.specimenSettled(replaying: false, replayStarted: true, sinceReplayEnded: 3))
        // The film's timecode creeps at the replay's speed (24 fps film time).
        #expect(SloMoCinema.timecode(0) == "00:00:00")
        #expect(SloMoCinema.timecode(1.5) == "00:01:12")
        #expect(SloMoCinema.timecode(61) == "01:01:00")
    }
}
