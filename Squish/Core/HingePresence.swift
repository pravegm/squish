import Foundation

/// Whether this launch has a hinge, robust to nil contexts (design/research/APPLE-DUO-GUIDE.md: a nil hinge also means
/// "left a hierarchy that provides hinge updates", not only "no hinge").
///
/// Before any reading this launch, a nil means no hinge (a regular iPhone): fall back to the P-48 at once. Once a hinge
/// has been seen, a nil never falls back, however long it lasts (launch QA P1: after the old 4 s grace the cover could
/// flip to the P-48 while the phone sat shut on the outer display). A Duo stays a Duo for the launch; only "Press without
/// folding" switches to the P-48. Pure, with explicit times, so it is unit-tested.
struct HingePresence: Equatable {
    /// A hinge reported at least once this launch.
    private(set) var seen = false
    /// The Duo stage should show (a hinge is, or is held as, available).
    private(set) var available = false
    /// When the current gap began (a nil after a reading), if one is running. Diagnostics only: it never ends the stage.
    private(set) var missingSince: Double?

    /// A hinge reading.
    mutating func reading(at time: Double) {
        seen = true
        available = true
        missingSince = nil
    }

    /// A nil hinge context. Returns true when the caller should fall back now: only when no hinge was seen this launch.
    mutating func lost(at time: Double) -> Bool {
        guard seen else {
            available = false
            return true
        }
        if missingSince == nil { missingSince = time }
        return false
    }
}
