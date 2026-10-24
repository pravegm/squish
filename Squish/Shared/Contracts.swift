import Foundation
import Observation

// Shared types that cross module boundaries. Owned by the lead; see design/ARCHITECTURE.md.
// Change a signature here only with a note in ARCHITECTURE.md, because every module compiles against it.

enum HapticsLevel: String, Codable, CaseIterable, Sendable, Identifiable {
    case off, soft, full

    var id: String { rawValue }
    var scale: Float {
        switch self {
        case .off: 0
        case .soft: 0.6
        case .full: 1
        }
    }
    var title: String {
        switch self {
        case .off: "Off"
        case .soft: "Soft"
        case .full: "Full"
        }
    }
}

/// Bible §5/§8: Workshop is the full mix; Soft is the misophonia-safe mode
/// (low-passed at 6 kHz, half grain density, no wet layers).
enum SoundStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case workshop, soft

    var id: String { rawValue }
    var title: String {
        switch self {
        case .workshop: "Workshop"
        case .soft: "Soft"
        }
    }
}

/// Everything a feedback recipe needs to know about the current press.
struct FeedbackContext: Sendable {
    var kind: ObjectKind
    var variant: PressVariant
    /// Measured compression 0…1.
    var compression: Float
    /// Degrees per second, positive while closing.
    var closingSpeed: Float
    var soundStyle: SoundStyle
    var reduceMotion: Bool
}

/// User-facing settings (bible §5 Settings sheet). Persisted in UserDefaults; call `save()` after edits.
@MainActor
@Observable
final class AppSettings {
    var soundEnabled = true
    var soundStyle: SoundStyle = .workshop
    /// "Play sound when the phone is on silent": `.playback` (on) or `.ambient` (off) audio session
    /// (`AudioSessionChoice`). On by default: the sound is half the product. Saved settings from 1.0 (1) predate it
    /// and decode as on.
    var playSoundInSilentMode = true
    var hapticsLevel: HapticsLevel = .full
    /// Visual onomatopoeia captions ("POP!", "CRACK!"). Defaults on when the system prefers captions.
    var showCaptions = false
    /// Use the touch press even on iPhone Duo (accessibility).
    var pressWithoutFolding = false
    var hasSeenSafetyHint = false

    private static let key = "squish.settings.v1"

    private struct Stored: Codable {
        var soundEnabled: Bool
        var soundStyle: SoundStyle
        var hapticsLevel: HapticsLevel
        var showCaptions: Bool
        var pressWithoutFolding: Bool
        var hasSeenSafetyHint: Bool
        /// Added after 1.0 (1): optional, so older saved settings still decode (missing → on).
        var playSoundInSilentMode: Bool?
    }

    init(defaultCaptions: Bool = false) {
        showCaptions = defaultCaptions
        guard let data = UserDefaults.standard.data(forKey: Self.key) else { return }
        load(from: data)
    }

    /// Applies saved settings; false (and nothing changed) when the data doesn't decode.
    @discardableResult
    func load(from data: Data) -> Bool {
        guard let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return false }
        soundEnabled = stored.soundEnabled
        soundStyle = stored.soundStyle
        playSoundInSilentMode = stored.playSoundInSilentMode ?? true
        hapticsLevel = stored.hapticsLevel
        showCaptions = stored.showCaptions
        pressWithoutFolding = stored.pressWithoutFolding
        hasSeenSafetyHint = stored.hasSeenSafetyHint
        return true
    }

    /// The saved form of these settings.
    func encoded() -> Data? {
        let stored = Stored(soundEnabled: soundEnabled, soundStyle: soundStyle, hapticsLevel: hapticsLevel,
                            showCaptions: showCaptions, pressWithoutFolding: pressWithoutFolding,
                            hasSeenSafetyHint: hasSeenSafetyHint, playSoundInSilentMode: playSoundInSilentMode)
        return try? JSONEncoder().encode(stored)
    }

    func save() {
        if let data = encoded() {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

/// One finished press, as stored in the collection.
struct SpecimenRecord: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var number: Int
    var kind: ObjectKind
    var date: Date
    var variant: PressVariant
    var fractureCount: Int
    var maxCompression: Double
    var failureAngle: Double?
    var duration: Double
    var isPerfect: Bool
    var wasSlammed: Bool
    var reversals: Int = 0
    /// Seconds of *engaged* pressing: the longest stretch of this press in which the hinge (or finger) moved at
    /// least every 10 s (docs/appstore/achievements.md #4, Patience). nil when unknown (older records, or a press
    /// recorded without its input trace), which never earns Patience.
    var engagedDuration: Double? = nil
    /// File name (not path) of the specimen thumbnail PNG in the collection folder, once captured.
    var thumbnailFile: String?
    /// True when a real hinge drove this press (Fold Press on iPhone Duo), so `failureAngle` is a hinge angle worth
    /// showing in degrees. False for the touch press (P-48, "Press without folding"), whose angle is only the engine's
    /// virtual θ: cards then show tonnage instead (FOLD-REVIEW-5 N6). Older records decode as false, so a card never
    /// claims a hinge it can't prove.
    var madeOnHinge: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, number, kind, date, variant, fractureCount, maxCompression, failureAngle, duration
        case isPerfect, wasSlammed, reversals, engagedDuration, thumbnailFile, madeOnHinge
    }

    /// Fun, deterministic "tonnage" for the label.
    var tons: Int {
        // Every gauge (P-48, Fold crown, cover) reads 0–80 t (`PressGauge`, FOLD-REVIEW-4 F12), and every needle seals on
        // this number, so real objects stay on the dial (≤ 59 t, under the 60 t red zone); only The Unsquishable pins it.
        if kind == .unsquishable { return 400 + Int(variant.seed % 97) }
        return min(80, 10 + Int(maxCompression * 44) + Int(variant.seed % 6))
    }

    var flavourLine: String {
        let lines = kind.flavourLines
        return lines[Int(variant.seed % UInt64(lines.count))]
    }
}

extension SpecimenRecord {
    /// Backward-compatible decoding: fields added after v1.0 (`reversals`, `engagedDuration`, `madeOnHinge`) may be missing from
    /// older collection.json files. Declared in an extension so the memberwise initializer is kept.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        number = try container.decode(Int.self, forKey: .number)
        kind = try container.decode(ObjectKind.self, forKey: .kind)
        date = try container.decode(Date.self, forKey: .date)
        variant = try container.decode(PressVariant.self, forKey: .variant)
        fractureCount = try container.decode(Int.self, forKey: .fractureCount)
        maxCompression = try container.decode(Double.self, forKey: .maxCompression)
        failureAngle = try container.decodeIfPresent(Double.self, forKey: .failureAngle)
        duration = try container.decode(Double.self, forKey: .duration)
        isPerfect = try container.decode(Bool.self, forKey: .isPerfect)
        wasSlammed = try container.decodeIfPresent(Bool.self, forKey: .wasSlammed) ?? false
        reversals = try container.decodeIfPresent(Int.self, forKey: .reversals) ?? 0
        engagedDuration = try container.decodeIfPresent(Double.self, forKey: .engagedDuration)
        thumbnailFile = try container.decodeIfPresent(String.self, forKey: .thumbnailFile)
        madeOnHinge = try container.decodeIfPresent(Bool.self, forKey: .madeOnHinge) ?? false
    }
}

/// Achievements (bible §11). Raw values double as Game Center IDs after the prefix.
enum Achievement: String, Codable, CaseIterable, Sendable, Identifiable {
    case firstSquish, perfectionist, midas, whatsInside, patience, collector, theSecret, popStar, steadyHands, pumped

    var id: String { rawValue }
    /// Matches docs/appstore/achievements.md (snake_case IDs registered in App Store Connect).
    var gameCenterID: String {
        let snake = rawValue.reduce(into: "") { result, character in
            if character.isUppercase {
                result += "_" + character.lowercased()
            } else {
                result.append(character)
            }
        }
        return "com.pravegm.squish.ach.\(snake)"
    }
}

/// What the collection reports back after recording a press.
struct RecordOutcome: Equatable, Sendable {
    var specimen: SpecimenRecord
    var newlyUnlocked: [ObjectKind]
    var newAchievements: [Achievement]
    /// True when this specimen replaced the shelf's best card for its object (Golden > Perfect > normal).
    var isNewBest: Bool
}

/// A short on-screen word for a press event, for captions and VoiceOver announcements.
struct CaptionEvent: Equatable, Sendable {
    var id: Int
    var text: String
    /// Announced to VoiceOver as well as shown (big moments only).
    var announce: Bool
}
