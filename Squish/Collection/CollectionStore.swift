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

    func record(_ result: PressResult, variant: PressVariant) -> RecordOutcome {
        totalPresses += 1
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
            thumbnailFile: nil
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
        case .patience: stats.longestPress > 30
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
        let side = min(width, height) * 0.92
        let centerY = height > width ? height * 0.62 : height * 0.55
        let originX = (width - side) / 2
        let originY = min(max(centerY - side / 2, 0), height - side)
        guard let cropped = cg.cropping(to: CGRect(x: originX, y: originY, width: side, height: side).integral) else { return nil }
        let target = CGSize(width: thumbnailSize, height: thumbnailSize)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            UIImage(cgImage: cropped).draw(in: CGRect(origin: .zero, size: target))
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
        seedDemo(count: count)
    }

    /// (kind, perfect, golden, surprise, fractures, duration, failure angle, days ago)
    private static let demoPresses: [(ObjectKind, Bool, Bool, Bool, Int, Double, Double?, Double)] = [
        (.bubbleWrap, true, false, false, 24, 11.2, nil, 3.1),
        (.rubberDuck, false, false, false, 2, 6.4, 104, 3.0),
        (.jelly, true, false, true, 2, 9.8, 112, 2.2),
        (.crayon, false, false, false, 3, 4.1, 128, 1.4),
        (.egg, false, true, false, 2, 8.7, 97, 1.1),
        (.cakeSlice, true, false, true, 3, 13.5, 118, 0.4),
        (.sodaCan, false, false, false, 5, 7.2, 92, 0.1),
    ]

    func seedDemo(count: Int) {
        for (index, entry) in Self.demoPresses.prefix(max(0, count)).enumerated() {
            let (kind, perfect, golden, surprise, fractures, duration, angle, daysAgo) = entry
            let seed = Self.demoSeed(for: kind, golden: golden, surprise: surprise, salt: UInt64(index))
            let result = PressResult(kind: kind, seed: seed, failureAngle: angle, fractureCount: fractures,
                                     maxCompression: 0.96, duration: duration, wasSlammed: false,
                                     isPerfect: perfect, reversals: 0)
            let outcome = record(result, variant: PressVariant(kind: kind, seed: seed))
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
