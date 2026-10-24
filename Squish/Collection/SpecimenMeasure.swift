import Foundation

/// The reveal's before → after line ("42 mm → 1.8 mm", design/EXPERIENCE-PLAN.md "Reveal ceremony"), measured honestly:
/// the object's modelled rest height (`SpecimenPrint.restHeight`, the scene's own constants, at the press's physical
/// scale `FoldMetrics.mmPerSceneMetre`) and how far this press really squashed it (`maxCompression`, down to the
/// object's own flattest shape, `ObjectKind.pressedFloorRatio`). Pure; no actor isolation.
extension SpecimenRecord {
    struct PressedSize: Equatable, Sendable {
        /// Millimetres tall before the press.
        var before: Double
        /// Millimetres tall after it.
        var after: Double

        /// "42 mm → 1.8 mm".
        var line: String { "\(Self.mm(before)) → \(Self.mm(after))" }

        /// Spoken: "42 millimetres to 1.8 millimetres".
        var spoken: String {
            "\(Self.number(before)) millimetres to \(Self.number(after)) millimetres"
        }

        /// Whole millimetres from 10 up, one decimal below.
        static func mm(_ value: Double) -> String { "\(number(value)) mm" }

        static func number(_ value: Double) -> String {
            value >= 10 ? String(format: "%.0f", value) : String(format: "%.1f", value)
        }
    }

    var measurement: PressedSize {
        let rest = SpecimenPrint.restHeight(kind, variant: variant) * FoldMetrics.mmPerSceneMetre
        let c = min(max(maxCompression, 0), 1)
        let after = rest * (1 - c * (1 - kind.pressedFloorRatio))
        return PressedSize(before: rest, after: min(rest, max(after, 0)))
    }
}
