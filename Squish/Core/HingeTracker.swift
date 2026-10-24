import Foundation

/// The hinge at display rate (founder, real Duo 1.0 (3): "the closing and opening feels like it is not sync with what is
/// happening on the screen", "jumpy and steppy"). Apple says the hinge's report rate is system policy and unpredictable,
/// so the picture must move continuously *between* reports and never hold still, then jump.
///
/// An alpha-beta tracker on the raw samples (angle + velocity, zero steady-state lag at a constant speed), read at any
/// time: between samples it extrapolates at the tracked velocity up to one expected sample interval, then eases to a
/// stop (so a hand that stops overshoots by at most ~one interval of travel, and settles back on the next report). Each
/// new sample's correction is blended in over ~40 ms instead of snapping. Robust from ~5 Hz to 120 Hz. A jump larger
/// than `snapDegrees` (a slam shut between two samples, a new input) snaps. Pure, with explicit times, so it is tested.
struct HingeTracker: Equatable {
    /// Gains: how much of a sample's surprise goes into the angle and into the velocity.
    static let alpha = 0.75
    static let beta = 0.35
    /// A fast real close runs 175° → 0° in ~0.37 s (~470°/s, the founder's log).
    static let maxSpeed = 900.0
    /// Extrapolate at full velocity for `coast` × the sample interval, then ease to a stop over `ease` × it.
    static let coast = 1.0
    static let ease = 0.3
    static let horizonRange = 0.03...0.2
    /// A surprise bigger than this snaps (no blending, velocity reset).
    static let snapDegrees = 90.0

    private(set) var estimate: Double?
    /// °/s, positive while the angle grows (opening).
    private(set) var velocity = 0.0
    private(set) var lastSampleTime = 0.0
    /// The smoothed time between samples (s).
    private(set) var interval = 1.0 / 30
    private var offset = 0.0
    private var offsetTime = 0.0

    mutating func reset() {
        estimate = nil
        velocity = 0
        offset = 0
    }

    mutating func sample(_ angle: Double, at time: Double) {
        guard estimate != nil else {
            estimate = angle
            velocity = 0
            lastSampleTime = time
            offset = 0
            return
        }
        let shown = self.angle(at: time)
        let dt = min(max(time - lastSampleTime, 1.0 / 240), 0.5)
        // The predict step uses the same eased coast the picture used (so a long gap doesn't overshoot), and the
        // velocity only fades once the gap passes twice the horizon (fading it sooner lags a slow, steady stream).
        let predicted = raw(at: time)
        let tau = max(0.03, Self.ease * interval)
        let prior = velocity * exp(-max(0, (time - lastSampleTime) - 2 * horizon) / tau)
        interval += (min(dt, 0.25) - interval) * 0.3
        let surprise = angle - predicted
        if abs(surprise) > Self.snapDegrees {
            estimate = angle
            velocity = 0
            lastSampleTime = time
            offset = 0
            return
        }
        estimate = predicted + Self.alpha * surprise
        velocity = clamp(prior + Self.beta / dt * surprise, -Self.maxSpeed, Self.maxSpeed)
        lastSampleTime = time
        // Continuity: whatever was on screen a moment ago blends into the corrected track.
        offset = shown - raw(at: time)
        offsetTime = time
    }

    /// How far past the last sample the model extrapolates at full velocity.
    var horizon: Double { clamp(Self.coast * interval, Self.horizonRange.lowerBound, Self.horizonRange.upperBound) }

    /// Seconds of extrapolation at `time` (eased past the horizon).
    private func extrapolation(at time: Double) -> Double {
        let age = max(time - lastSampleTime, 0)
        if age <= horizon { return age }
        let tau = max(0.03, Self.ease * interval)
        return horizon + tau * (1 - exp(-(age - horizon) / tau))
    }

    private func raw(at time: Double) -> Double {
        (estimate ?? 180) + velocity * extrapolation(at: time)
    }

    /// The angle to draw at `time` (degrees, 0…180).
    func angle(at time: Double) -> Double {
        guard estimate != nil else { return 180 }
        let blend = exp(-max(time - offsetTime, 0) / max(0.04, 0.35 * interval))
        return clamp(raw(at: time) + offset * blend, 0, 180)
    }

    /// °/s at `time`, positive while closing (the drawn angle's own speed: it eases to 0 once reports stop).
    func closingSpeed(at time: Double) -> Double {
        let age = max(time - lastSampleTime, 0)
        guard age > horizon else { return -velocity }
        let tau = max(0.03, Self.ease * interval)
        return -velocity * exp(-(age - horizon) / tau)
    }

    /// Reports per second, from the smoothed interval.
    var rate: Double { 1 / max(interval, 1e-3) }
}

/// The live pipeline lag, for the Tuning Lab's Sync readout (so the founder can screenshot it while folding).
struct PipelineStats: Equatable {
    /// Seconds since the last hinge report.
    var sampleAge = 0.0
    /// Hinge reports per second (smoothed).
    var hingeRate = 0.0
    /// Raw angle minus the event filter's angle (degrees; + = the filter is behind while closing… either sign).
    var filterLag = 0.0
    /// The drawn angle minus the raw angle (degrees): the prediction's lead, or lag.
    var drawnVsRaw = 0.0
    /// The angle the render depth corresponds to, minus the raw angle (degrees), while pressing.
    var renderVsRaw = 0.0
    /// Frames per second of the loop (the display refresh it gets).
    var displayRate = 0.0
}
