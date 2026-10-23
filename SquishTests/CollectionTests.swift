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

    @Test func pumpedNeedsTwoReversals() {
        let (store, _) = makeStore()
        press(store, .jelly, reversals: 1)
        #expect(!store.earnedAchievements.contains(.pumped))
        #expect(press(store, .jelly, reversals: 2).newAchievements.contains(.pumped))
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

    @Test func persistenceRoundTrip() throws {
        let (store, folder) = makeStore()
        press(store, .bubbleWrap, perfect: true, fractures: 24)
        press(store, .rubberDuck)
        let golden = press(store, .jelly, golden: true)
        store.attachThumbnail(tinyPNG(), to: golden.specimen.id)

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
        let image = try #require(reloaded.thumbnail(for: best))
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

    // MARK: Copy

    @Test func cardTraitsAndSentence() {
        let (store, _) = makeStore()
        let outcome = press(store, .egg, perfect: true, golden: true, onHinge: true)
        let texts = outcome.specimen.traits.map(\.text)
        #expect(texts.first == "GOLDEN")
        #expect(texts.contains("PERFECT SQUISH"))
        #expect(outcome.specimen.accessibilitySentence.contains("Egg"))
        #expect(outcome.specimen.labelLines.first?.hasPrefix("CRUSHED AT 101° · ") == true)
        #expect(outcome.specimen.labelLines.count == 2)
        #expect(outcome.specimen.gaveAtTag == "AT 101°")
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

    @Test func hingeTraceCardsShowDegrees() {
        let (store, _) = makeStore()
        let outcome = press(store, .rubberDuck, samples: sweep(from: 168, to: 40, over: 6, at: 0), virtualHinge: false)
        #expect(outcome.specimen.madeOnHinge)
        #expect(outcome.specimen.labelLines.first == "CRUSHED AT 101° · \(outcome.specimen.tons) TONS")
        #expect(outcome.specimen.accessibilitySentence.contains("crushed at 101 degrees"))
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
}
