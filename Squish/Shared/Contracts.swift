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
    }

    init(defaultCaptions: Bool = false) {
        showCaptions = defaultCaptions
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        soundEnabled = stored.soundEnabled
        soundStyle = stored.soundStyle
        hapticsLevel = stored.hapticsLevel
        showCaptions = stored.showCaptions
        pressWithoutFolding = stored.pressWithoutFolding
        hasSeenSafetyHint = stored.hasSeenSafetyHint
    }

    func save() {
        let stored = Stored(soundEnabled: soundEnabled, soundStyle: soundStyle, hapticsLevel: hapticsLevel,
                            showCaptions: showCaptions, pressWithoutFolding: pressWithoutFolding,
                            hasSeenSafetyHint: hasSeenSafetyHint)
        if let data = try? JSONEncoder().encode(stored) {
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
    /// File name (not path) of the specimen thumbnail PNG in the collection folder, once captured.
    var thumbnailFile: String?

    /// Fun, deterministic "tonnage" for the label.
    var tons: Int {
        if kind == .unsquishable { return 400 + Int(variant.seed % 97) }
        return 12 + Int(maxCompression * 50) + Int(variant.seed % 9)
    }

    var flavourLine: String {
        let lines = kind.flavourLines
        return lines[Int(variant.seed % UInt64(lines.count))]
    }
}

/// Achievements (bible §11). Raw values double as Game Center IDs after the prefix.
enum Achievement: String, Codable, CaseIterable, Sendable, Identifiable {
    case firstSquish, perfectionist, midas, whatsInside, patience, collector, theSecret, popStar, steadyHands, pumped

    var id: String { rawValue }
    var gameCenterID: String { "com.pravegm.squish.ach.\(rawValue)" }
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
