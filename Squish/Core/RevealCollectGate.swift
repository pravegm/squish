import Foundation

/// Fold-to-collect for the reveal card (FOLD-REVIEW-6 N2). Closing the phone, or folding ~20° from the open
/// position, collects the specimen and puts the next object on the anvil, but only when the close is deliberate.
///
/// The hinge's `closed` flag flickers on a hesitant reopen. In the R6 logs (cake l.228–232, glass l.319–323) the
/// reveal fires at `20.1° open`, then a `24.8° closed` sample arrives while the hinge is still opening, and the old
/// "any `closed` sample collects" rule ate the card before it was ever on screen. The flag then stayed `closed` up to
/// ~92° on the way open. So:
/// - nothing collects until `settle` after the reveal starts, nor before the card has been opened far enough to be
///   seen (`seenAngle`);
/// - a fold counts once the hinge has stayed `foldTravel` below the reveal's peak for `foldHold`;
/// - a close counts once `closed` has held for `closedHold`. A `closed` sample whose angle reads open
///   (> `closedMaxAngle`) is a misread and is treated as open.
///
/// A pure value type with explicit timestamps, so it is unit-testable. The director feeds it every hinge sample while
/// the card is up and also polls it at `nextDeadline`, because a shut Duo lying still sends no more samples.
struct RevealCollectGate: Equatable, Sendable {
    /// Seconds after the reveal starts during which nothing collects.
    static let settle = 0.8
    /// The card counts as seen once the hinge has been at least this open (the engine's "clearly open", §6.3).
    static let seenAngle = 100.0
    /// Degrees below the reveal's peak that count as folding it away…
    static let foldTravel = 20.0
    /// …held for this long (seconds).
    static let foldHold = 0.25
    /// `closed` must hold this long (seconds) to count.
    static let closedHold = 0.3
    /// A `closed` sample reading above this angle is a misread (the phone is open) and is ignored.
    static let closedMaxAngle = 90.0

    /// When the reveal started.
    let start: Double
    /// The highest hinge angle seen since the reveal started.
    private(set) var peak: Double
    /// When the hinge last went `foldTravel` below the peak (nil while it isn't).
    private var foldSince: Double?
    /// When a believable `closed` run started (nil while open).
    private var closedSince: Double?

    /// `angle` is the hinge as the reveal starts (the sample that triggered it, or the last one).
    init(start: Double, angle: Double) {
        self.start = start
        peak = angle
    }

    /// True once the card has been opened far enough to be seen; before that no rule collects.
    var hasBeenSeen: Bool { peak >= Self.seenAngle }

    /// Feed one hinge sample. Returns true when it completes a deliberate close.
    mutating func ingest(angle: Double, closed: Bool, at time: Double) -> Bool {
        peak = max(peak, angle)
        let shut = closed && angle <= Self.closedMaxAngle
        closedSince = shut ? (closedSince ?? time) : nil
        let folded = angle <= peak - Self.foldTravel
        foldSince = folded ? (foldSince ?? time) : nil
        return shouldCollect(at: time)
    }

    /// When the pending fold or close completes if nothing changes (nil when none is pending).
    var nextDeadline: Double? {
        guard hasBeenSeen else { return nil }
        let fold = foldSince.map { $0 + Self.foldHold }
        let close = closedSince.map { $0 + Self.closedHold }
        guard let due = [fold, close].compactMap({ $0 }).min() else { return nil }
        return max(due, start + Self.settle)
    }

    /// True when a deliberate close has completed by `time` (also valid between samples).
    func shouldCollect(at time: Double) -> Bool {
        guard let nextDeadline else { return false }
        return time >= nextDeadline
    }
}
