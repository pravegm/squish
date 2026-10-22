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
                       slammed: Bool = false, seedStart: UInt64 = 1) -> RecordOutcome {
        let seed = findSeed(for: kind, golden: golden, surprise: surprise, from: seedStart)
        let result = PressResult(kind: kind, seed: seed, failureAngle: 101, fractureCount: fractures,
                                 maxCompression: 0.95, duration: duration, wasSlammed: slammed,
                                 isPerfect: perfect, reversals: reversals)
        return store.record(result, variant: PressVariant(kind: kind, seed: seed))
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

    @Test func midasWhatsInsideAndPatience() {
        let (store, _) = makeStore()
        #expect(press(store, .cakeSlice, golden: true).newAchievements.contains(.midas))
        press(store, .jelly, surprise: true)
        #expect(!store.earnedAchievements.contains(.whatsInside))
        #expect(press(store, .cakeSlice, surprise: true).newAchievements.contains(.whatsInside))
        press(store, .egg, duration: 30)
        #expect(!store.earnedAchievements.contains(.patience))
        #expect(press(store, .egg, duration: 31).newAchievements.contains(.patience))
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
        let outcome = press(store, .egg, perfect: true, golden: true)
        let texts = outcome.specimen.traits.map(\.text)
        #expect(texts.first == "GOLDEN")
        #expect(texts.contains("PERFECT SQUISH"))
        #expect(outcome.specimen.accessibilitySentence.contains("Egg"))
        #expect(outcome.specimen.labelLines.first?.hasPrefix("CRUSHED AT 101° · ") == true)
        #expect(outcome.specimen.labelLines.count == 2)
        for achievement in Achievement.allCases {
            #expect(!achievement.title.isEmpty && !achievement.detail.isEmpty)
        }
    }
}
