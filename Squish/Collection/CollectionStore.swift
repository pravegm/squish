import Foundation
import Observation
import UIKit
import os

/// The player's collection (bible §5 Shelf, §11 progression): every finished press as a specimen,
/// unlocks, the best card per object and achievements. Persisted as JSON in Application Support
/// (`Squish/collection.json`) with one PNG thumbnail per specimen next to it.
///
/// Progress is never taken away: deleting a card removes the card only, never presses, unlocks or achievements.
@MainActor
@Observable
final class CollectionStore {
    /// Newest first, capped at `capacity`.
    private(set) var specimens: [SpecimenRecord] = []
    /// Lifetime presses. Also numbers the specimens (№0042).
    private(set) var totalPresses = 0
    private(set) var earnedAchievements: Set<Achievement> = []
    /// Lifetime stats behind unlocks and achievements (kept separately so the specimen cap never loses progress).
    private(set) var stats = Stats()

    /// Best card per object, kept even if the specimen itself falls off the end of `specimens`.
    @ObservationIgnored private var bests: [ObjectKind: SpecimenRecord] = [:]
    private var bestsVersion = 0
    private var unlocked: Set<ObjectKind> = []

    /// False in CI demo runs (unless the scenario says `patience`): Patience depends on wall-clock timing, which
    /// slow simulators and scripted hinge sweeps stretch, so it must never land in a screenshot (FOLD-REVIEW-3 N8).
    @ObservationIgnored private var awardsPatience = true

    let directory: URL
    @ObservationIgnored private var imageCache: [String: UIImage] = [:]
    private let log = Logger(subsystem: "com.pravegm.squish", category: "collection")

    /// Specimens kept on disk. The Squished tab shows the most recent 200 (bible §5).
    static let capacity = 500
    /// Thumbnails are cropped square around the anvil and stored at this size (px).
    static let thumbnailSize: CGFloat = 512

    struct Stats: Codable, Equatable, Sendable {
        var squishedKinds: Set<ObjectKind> = []
        var perfectKinds: Set<ObjectKind> = []
        var perfectCount = 0
        var goldenCount = 0
        var bubblesPopped = 0
        var surprisesFound: Set<Surprise> = []
        var longestPress: Double = 0
    }

    // MARK: - Init

    /// Loads from Application Support. Demo runs (CI screenshots) use a fresh temporary folder,
    /// optionally seeded with fake specimens, so screenshots are deterministic and real data is never touched.
    convenience init() {
        #if DEBUG
        if let demo = DemoScenario.current {
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("SquishDemo-\(UUID().uuidString)", isDirectory: true)
            self.init(directory: folder)
            awardsPatience = demo.has("patience")
            seedDemo(for: demo)
            return
        }
        #endif
        self.init(directory: Self.defaultDirectory)
    }

    /// Designated init; tests pass a temporary directory.
    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Squish", isDirectory: true)
    }

    private var fileURL: URL { directory.appendingPathComponent("collection.json") }

    // MARK: - Queries

    func isUnlocked(_ kind: ObjectKind) -> Bool {
        kind.unlockRule == .open || unlocked.contains(kind)
    }

    var unlockedCount: Int { ObjectKind.allCases.filter(isUnlocked).count }

    /// Objects pressed at least once ("7/10 pressed").
    var pressedKindsCount: Int { stats.squishedKinds.count }

    /// The shelf card for an object: Golden > Perfect > newest.
    func best(for kind: ObjectKind) -> SpecimenRecord? {
        _ = bestsVersion // register observation; `bests` itself is ignored to keep the dictionary cheap
        return bests[kind]
    }

    func specimen(withID id: UUID) -> SpecimenRecord? {
        specimens.first { $0.id == id } ?? bests.values.first { $0.id == id }
    }

    func thumbnailURL(for specimen: SpecimenRecord) -> URL? {
        guard let file = specimen.thumbnailFile else { return nil }
        let url = directory.appendingPathComponent(file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Decoded thumbnail, cached in memory.
    func thumbnail(for specimen: SpecimenRecord) -> UIImage? {
        guard let file = specimen.thumbnailFile else { return nil }
        if let cached = imageCache[file] { return cached }
        guard let url = thumbnailURL(for: specimen), let image = UIImage(contentsOfFile: url.path) else { return nil }
        imageCache[file] = image
        return image
    }

    // MARK: - Recording

    /// Records a finished press. Pass the press's input `trace` so the engaged time (Patience) can be measured;
    /// without one the specimen's `engagedDuration` is unknown (nil) and Patience can't be earned by it.
    ///
    /// `onHinge` says whether a real hinge drove the press (cards then show its failure angle in degrees). When nil it
    /// comes from the trace (`!usesVirtualHinge`); with neither, the press counts as a touch press (tonnage only).
    func record(_ result: PressResult, variant: PressVariant, trace: PressTrace? = nil, onHinge: Bool? = nil) -> RecordOutcome {
        totalPresses += 1
        let engaged = trace.map { PressEngagement.engagedDuration(of: $0, pressDuration: result.duration) }
        let madeOnHinge = onHinge ?? trace.map { !$0.usesVirtualHinge } ?? false
        let specimen = SpecimenRecord(
            id: UUID(),
            number: totalPresses,
            kind: result.kind,
            date: Date(),
            variant: variant,
            fractureCount: result.fractureCount,
            maxCompression: result.maxCompression,
            failureAngle: result.failureAngle,
            duration: result.duration,
            isPerfect: result.isPerfect,
            wasSlammed: result.wasSlammed,
            reversals: result.reversals,
            engagedDuration: engaged,
            thumbnailFile: nil,
            madeOnHinge: madeOnHinge
        )
        specimens.insert(specimen, at: 0)
        pruneIfNeeded()

        // Lifetime stats.
        stats.squishedKinds.insert(specimen.kind)
        if specimen.isPerfect {
            stats.perfectCount += 1
            stats.perfectKinds.insert(specimen.kind)
        }
        if variant.isGolden { stats.goldenCount += 1 }
        if specimen.kind == .bubbleWrap { stats.bubblesPopped += specimen.fractureCount }
        if let surprise = variant.surprise { stats.surprisesFound.insert(surprise) }
        stats.longestPress = max(stats.longestPress, specimen.duration)

        // Best card. Ties go to the newest so the shelf stays fresh, but only a rank upgrade
        // (or the first card of an object) counts as "new best".
        let previous = bests[specimen.kind]
        let isNewBest = previous.map { Self.tier($0) < Self.tier(specimen) } ?? true
        if previous.map({ Self.rank($0) <= Self.rank(specimen) }) ?? true {
            bests[specimen.kind] = specimen
            bestsVersion += 1
        }

        let newlyUnlocked = evaluateUnlocks()
        let newAchievements = evaluateAchievements(latest: specimen)
        save()
        return RecordOutcome(specimen: specimen, newlyUnlocked: newlyUnlocked,
                             newAchievements: newAchievements, isNewBest: isNewBest)
    }

    /// Stores the specimen photo. The full-screen snapshot is cropped square around the anvil and downscaled.
    func attachThumbnail(_ png: Data, to id: UUID) {
        guard let image = UIImage(data: png) else { return }
        let data = Self.specimenCrop(image)?.pngData() ?? png
        let file = "\(id.uuidString).png"
        do {
            try data.write(to: directory.appendingPathComponent(file), options: .atomic)
        } catch {
            log.error("Thumbnail write failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        imageCache[file] = nil
        if let index = specimens.firstIndex(where: { $0.id == id }) {
            specimens[index].thumbnailFile = file
        }
        for (kind, best) in bests where best.id == id {
            bests[kind]?.thumbnailFile = file
            bestsVersion += 1
        }
        save()
    }

    /// Removes one card. Presses, unlocks and achievements are kept.
    func delete(_ id: UUID) {
        guard let removed = specimen(withID: id) else { return }
        specimens.removeAll { $0.id == id }
        if bests[removed.kind]?.id == id {
            bests[removed.kind] = specimens
                .filter { $0.kind == removed.kind }
                .max { Self.rank($0) < Self.rank($1) }
            bestsVersion += 1
        }
        deleteThumbnailIfUnused(removed)
        save()
    }

    // MARK: - Rules

    /// Golden > Perfect > normal, then newest (specimen numbers only grow).
    static func rank(_ specimen: SpecimenRecord) -> (Int, Int) {
        (tier(specimen), specimen.number)
    }

    /// 2 = Golden, 1 = Perfect, 0 = normal.
    static func tier(_ specimen: SpecimenRecord) -> Int {
        specimen.variant.isGolden ? 2 : (specimen.isPerfect ? 1 : 0)
    }

    func ruleSatisfied(_ rule: UnlockRule, for kind: ObjectKind) -> Bool {
        switch rule {
        case .open:
            true
        case .squishDifferentKinds(let count):
            stats.squishedKinds.count >= count
        case .totalPresses(let count):
            totalPresses >= count
        case .perfectSquish:
            stats.perfectCount >= 1
        case .allOthers:
            ObjectKind.allCases.allSatisfy { $0 == kind || stats.squishedKinds.contains($0) }
        }
    }

    private func evaluateUnlocks() -> [ObjectKind] {
        var fresh: [ObjectKind] = []
        for kind in ObjectKind.allCases where !isUnlocked(kind) && ruleSatisfied(kind.unlockRule, for: kind) {
            unlocked.insert(kind)
            fresh.append(kind)
        }
        return fresh
    }

    /// Bible §11. All earned by ordinary play; slams never earn anything on their own.
    func isEarned(_ achievement: Achievement, latest: SpecimenRecord?) -> Bool {
        switch achievement {
        case .firstSquish: totalPresses >= 1
        case .perfectionist: stats.perfectKinds.count >= 5
        case .midas: stats.goldenCount >= 1
        case .whatsInside: stats.surprisesFound.count >= 2
        // One press with ≥ 30 s of engaged pressing; idle time and > 10 s stalls don't count (achievements.md #4).
        case .patience: awardsPatience && (latest?.engagedDuration ?? 0) >= PressEngagement.patienceSeconds
        case .collector: stats.squishedKinds.count == ObjectKind.allCases.count
        case .theSecret: stats.squishedKinds.contains(.unsquishable)
        case .popStar: stats.bubblesPopped >= 500
        case .steadyHands: stats.perfectCount >= 10
        case .pumped: (latest?.reversals ?? 0) >= 2
        }
    }

    private func evaluateAchievements(latest: SpecimenRecord) -> [Achievement] {
        var fresh: [Achievement] = []
        for achievement in Achievement.allCases
        where !earnedAchievements.contains(achievement) && isEarned(achievement, latest: latest) {
            earnedAchievements.insert(achievement)
            fresh.append(achievement)
        }
        return fresh
    }

    // MARK: - Persistence

    private struct Stored: Codable {
        var version = 1
        var specimens: [SpecimenRecord]
        /// Keyed by `ObjectKind.rawValue`.
        var bests: [String: SpecimenRecord]
        var totalPresses: Int
        var unlocked: [ObjectKind]
        var earned: [Achievement]
        var stats: Stats
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let stored = try JSONDecoder().decode(Stored.self, from: data)
            specimens = stored.specimens
            totalPresses = stored.totalPresses
            unlocked = Set(stored.unlocked)
            earnedAchievements = Set(stored.earned)
            stats = stored.stats
            var restored: [ObjectKind: SpecimenRecord] = [:]
            for (key, value) in stored.bests {
                if let kind = ObjectKind(rawValue: key) { restored[kind] = value }
            }
            bests = restored
            bestsVersion += 1
        } catch {
            // Keep the unreadable file for support instead of silently overwriting it.
            log.error("Collection unreadable, starting fresh: \(error.localizedDescription, privacy: .public)")
            let backup = directory.appendingPathComponent("collection.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
        }
    }

    private func save() {
        var storedBests: [String: SpecimenRecord] = [:]
        for (kind, specimen) in bests { storedBests[kind.rawValue] = specimen }
        let stored = Stored(
            specimens: specimens,
            bests: storedBests,
            totalPresses: totalPresses,
            unlocked: unlocked.sorted { $0.rawValue < $1.rawValue },
            earned: earnedAchievements.sorted { $0.rawValue < $1.rawValue },
            stats: stats
        )
        do {
            let data = try JSONEncoder().encode(stored)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            log.error("Collection save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func pruneIfNeeded() {
        guard specimens.count > Self.capacity else { return }
        let dropped = specimens[Self.capacity...]
        specimens.removeLast(specimens.count - Self.capacity)
        for specimen in dropped { deleteThumbnailIfUnused(specimen) }
    }

    private func deleteThumbnailIfUnused(_ specimen: SpecimenRecord) {
        guard let file = specimen.thumbnailFile else { return }
        let stillUsed = specimens.contains { $0.thumbnailFile == file } || bests.values.contains { $0.thumbnailFile == file }
        guard !stillUsed else { return }
        imageCache[file] = nil
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
    }

    /// Square crop around the anvil (the object sits ~62% down the screen in portrait), downscaled.
    static func specimenCrop(_ image: UIImage) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let width = CGFloat(cg.width), height = CGFloat(cg.height)
        let target = CGSize(width: thumbnailSize, height: thumbnailSize)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        // Already a card: the square top-down specimen shot (`PressScene.specimenSnapshot`) or the Fold diptych
        // (`FoldPressController.specimenDiptych`, `SpecimenPrint.cardImage`). Keep all of it, only downscaled. The
        // crop below is for full-screen live frames; on a square it took the landscape branch and kept a rotated
        // 58 % window right of centre (half the print, half the specimen).
        if abs(width - height) <= 1 {
            let whole = UIImage(cgImage: cg, scale: 1, orientation: .up)
            return UIGraphicsImageRenderer(size: target, format: format).image { _ in
                whole.draw(in: CGRect(origin: .zero, size: target))
            }
        }
        // Portrait: a tight square on the anvil (contact line ~74%, flattened object ~66–78%), inside the
        // columns at 20/80% width, so the card shows the specimen rather than the press (VISUAL-REVIEW-1 #12).
        // Interim until Scene provides a dedicated orthographic specimen render.
        // Book pose (landscape; the scene camera rolls −90° so the ram comes from the left): the same framing
        // turned on its side — anvil ~70% across — and the crop is rotated upright so the card never shows
        // a sideways press (Duo review).
        let portrait = height > width
        let side = portrait ? width * 0.58 : height * 0.58
        let centerX = portrait ? width * 0.5 : width * 0.70
        let centerY = portrait ? height * 0.70 : height * 0.5
        let originX = min(max(centerX - side / 2, 0), width - side)
        let originY = min(max(centerY - side / 2, 0), height - side)
        guard let cropped = cg.cropping(to: CGRect(x: originX, y: originY, width: side, height: side).integral) else { return nil }
        let upright = UIImage(cgImage: cropped, scale: 1, orientation: portrait ? .up : .right)
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            upright.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    // MARK: - Demo seeding (DEBUG only)

    #if DEBUG
    /// Seeds fake specimens for CI screenshots. `specimens=N` seeds the first N; any of `shelf`, `detail`,
    /// `cover`, `settings` seeds the standard set (7 objects pressed, one Golden, one surprise).
    func seedDemo(for demo: DemoScenario) {
        let count: Int
        if let raw = demo.string("specimens"), let n = Int(raw) {
            count = n
        } else if ["shelf", "detail", "cover", "settings"].contains(where: demo.has) {
            count = Self.demoPresses.count
        } else {
            return
        }
        // Seeded cards show hinge angles only on a real Duo run (`duo`); elsewhere they carry tonnage, like a real
        // touch press would (FOLD-REVIEW-5 N6: no "CRUSHED AT 104°" on a phone with no hinge).
        seedDemo(count: count, onHinge: demo.has("duo"))
    }

    /// (kind, perfect, golden, surprise, duration, days ago). Fractures and the failure angle aren't listed: they come
    /// from each seed exactly as a real press derives them (FOLD-REVIEW-8 N2: the old hand-typed 92–128° were 20–60°
    /// above anything the press produces).
    private static let demoPresses: [(ObjectKind, Bool, Bool, Bool, Double, Double)] = [
        (.bubbleWrap, true, false, false, 11.2, 3.1),
        (.rubberDuck, false, false, false, 6.4, 3.0),
        (.jelly, true, false, true, 9.8, 2.2),
        (.crayon, false, false, false, 4.1, 1.4),
        (.egg, false, true, false, 8.7, 1.1),
        (.cakeSlice, true, false, true, 13.5, 0.4),
        (.sodaCan, false, false, false, 7.2, 0.1),
    ]

    /// How far a seeded press went: a full, sealed press (the engine seals at depth 0.98, c ≈ 0.97).
    static let demoCompression = 0.96

    /// One seeded press, as the engine would have recorded it: its fractures are the seed's jittered thresholds a
    /// press to `demoCompression` reaches, and its failure angle is where a press opened flat meets the failure
    /// threshold (`SpecimenPrint.failureAngle`).
    static func demoResult(kind: ObjectKind, seed: UInt64, perfect: Bool, duration: Double) -> PressResult {
        PressResult(kind: kind, seed: seed, failureAngle: SpecimenPrint.failureAngle(kind, seed: seed),
                    fractureCount: SpecimenPrint.fractureCount(kind, seed: seed, maxCompression: demoCompression),
                    maxCompression: demoCompression, duration: duration, wasSlammed: false,
                    isPerfect: perfect, reversals: 0)
    }

    func seedDemo(count: Int, onHinge: Bool = false) {
        for (index, entry) in Self.demoPresses.prefix(max(0, count)).enumerated() {
            let (kind, perfect, golden, surprise, duration, daysAgo) = entry
            let seed = Self.demoSeed(for: kind, golden: golden, surprise: surprise, salt: UInt64(index))
            let variant = PressVariant(kind: kind, seed: seed)
            let result = Self.demoResult(kind: kind, seed: seed, perfect: perfect, duration: duration)
            let outcome = record(result, variant: variant, onHinge: onHinge)
            // The card a real Fold press stores: the platen's print of this very press (FOLD-REVIEW-8 N2), through the
            // same attach path, so the Shelf, the cover's recent tiles and the card detail all show a print.
            if let print = SpecimenPrint.printImage(kind: kind, variant: variant, maxCompression: result.maxCompression,
                                                    fractureCount: result.fractureCount),
               let png = SpecimenPrint.cardImage(print: print).pngData() {
                attachThumbnail(png, to: outcome.specimen.id)
            }
            if let i = specimens.firstIndex(where: { $0.id == outcome.specimen.id }) {
                specimens[i].date = Date().addingTimeInterval(-daysAgo * 86_400)
                if bests[kind]?.id == outcome.specimen.id { bests[kind] = specimens[i] }
            }
        }
        bestsVersion += 1
        save()
    }

    /// Finds a seed whose variant matches the wanted traits (golden is 1 in 50, so this is a short search).
    static func demoSeed(for kind: ObjectKind, golden: Bool, surprise: Bool, salt: UInt64) -> UInt64 {
        var seed = 1_000 + salt * 7_919
        for _ in 0..<20_000 {
            let variant = PressVariant(kind: kind, seed: seed)
            let surpriseOK = surprise ? variant.surprise != nil : variant.surprise == nil
            if variant.isGolden == golden && surpriseOK { return seed }
            seed += 1
        }
        return seed
    }
    #endif
}

// MARK: - Engagement (Patience)

/// How long a press was *actively* pressed, from its recorded hinge (or touch) trace. Patience
/// (docs/appstore/achievements.md #4) counts time from the start of the press to the seal **with continuous
/// engagement**: the depth must change at least once every 10 s. Holding still mid-press for longer than that
/// breaks the streak, so leaving the phone half-open (or armed and untouched) never counts.
enum PressEngagement {
    /// Seconds of engaged pressing Patience needs in one press.
    static let patienceSeconds: Double = 30
    /// A stall longer than this (no motion) breaks engagement.
    static let maxGap: Double = 10
    /// Angle change (degrees) from the last motion that counts as motion. Smaller changes are sensor jitter
    /// on a resting hinge; a genuinely slow press still moves this far every second or two.
    static let motionThreshold: Double = 1

    static func engagedDuration(of trace: PressTrace, pressDuration: Double) -> Double {
        engagedDuration(samples: trace.samples, pressDuration: pressDuration,
                        armAngleMax: trace.config.armAngleMax, hysteresis: trace.config.hysteresis)
    }

    /// The longest continuously engaged stretch of the press, in seconds, never more than `pressDuration`.
    ///
    /// - The press window starts where the engine starts it (the angle first drops `hysteresis` below the armed
    ///   start, itself capped at `armAngleMax`) and lasts `pressDuration` (the engine's arm-to-seal time), so idle
    ///   time before the press and the close / reopen after the seal are left out.
    /// - Motion events are samples whose angle moved ≥ `motionThreshold` from the previous motion, or whose
    ///   closed flag changed (a touch press marks the finger lifting that way). The seal closes the last stretch.
    /// - Consecutive events ≤ `maxGap` apart extend the current stretch; a longer gap ends it.
    static func engagedDuration(samples: [PressTrace.Sample], pressDuration: Double,
                                armAngleMax: Double = 168, hysteresis: Double = 4) -> Double {
        guard pressDuration > 0, let first = samples.first else { return 0 }

        // Where the press began (falls back to the first sample if the trace never crosses the hysteresis).
        var peak = min(first.angle, armAngleMax)
        var startIndex = 0
        for (index, sample) in samples.enumerated() {
            peak = max(peak, min(sample.angle, armAngleMax))
            if sample.angle <= peak - hysteresis {
                startIndex = index
                break
            }
        }
        let start = samples[startIndex].time
        let end = start + pressDuration

        // Motion events inside the press window.
        var events: [Double] = [start]
        var anchor = samples[startIndex]
        for sample in samples[(startIndex + 1)...] {
            if sample.time > end { break }
            if abs(sample.angle - anchor.angle) >= motionThreshold || sample.closed != anchor.closed {
                events.append(sample.time)
                anchor = sample
            }
        }
        events.append(end)

        // Longest run of events with no gap over `maxGap`.
        var longest = 0.0
        var run = 0.0
        for (earlier, later) in zip(events, events.dropFirst()) {
            let gap = later - earlier
            if gap > maxGap {
                run = 0
            } else {
                run += gap
                longest = max(longest, run)
            }
        }
        return min(longest, pressDuration)
    }
}
