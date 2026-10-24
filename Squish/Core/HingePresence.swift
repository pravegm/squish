import Foundation

/// Whether this launch has a hinge, robust to transient nil contexts (design/research/APPLE-DUO-GUIDE.md: a nil hinge
/// also means "left a hierarchy that provides hinge updates", not only "no hinge").
///
/// Before any reading this launch, a nil means no hinge (a regular iPhone): fall back at once. Once a hinge has been
/// seen, a nil holds the last known state, and only a hinge missing for `grace` seconds, with no window or scene change
/// in between, falls back to the P-48. A reading cancels it. Pure, with explicit times, so it is unit-tested.
struct HingePresence: Equatable {
    /// Seconds a seen hinge may be missing before the Duo stage gives way to the P-48.
    static let grace = 4.0

    /// A hinge reported at least once this launch.
    private(set) var seen = false
    /// The Duo stage should show (a hinge is, or is held as, available).
    private(set) var available = false
    /// When the current gap began (a nil after a reading), if one is running.
    private(set) var missingSince: Double?

    /// A hinge reading.
    mutating func reading(at time: Double) {
        seen = true
        available = true
        missingSince = nil
    }

    /// A nil hinge context. Returns true when the caller should fall back now (no hinge seen this launch).
    mutating func lost(at time: Double) -> Bool {
        guard seen else {
            available = false
            return true
        }
        if missingSince == nil { missingSince = time }
        return false
    }

    /// A window or scene change: nil contexts around it are expected, so the grace starts again.
    mutating func sceneChanged(at time: Double) {
        if missingSince != nil { missingSince = time }
    }

    /// When the running gap would fall back, if one is running.
    var deadline: Double? { missingSince.map { $0 + Self.grace } }

    /// Polled at (or after) `deadline`: true when the seen hinge has now been missing for the whole grace, and the
    /// caller should fall back to the P-48. `seen` stays true, so the next nil waits again.
    mutating func shouldFallBack(at time: Double) -> Bool {
        guard let since = missingSince, time - since >= Self.grace - 1e-9 else { return false }
        missingSince = nil
        available = false
        return true
    }
}
