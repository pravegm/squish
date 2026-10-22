import Foundation

// MARK: - Replay

/// One deterministic re-run of a recorded press (bible §10): a private `PressEngine` fed the trace's samples at
/// their own timestamps, stepped by an explicit clock. Same samples + seed + step times ⇒ same events, so the
/// audio pass and the video pass of the share clip land every event on the same frame.
@MainActor
final class PressReplay {
    let trace: PressTrace
    let engine: PressEngine
    /// Source time (seconds since the object was placed) the engine has been stepped to.
    private(set) var clock: Double = 0
    /// Called for every engine event with the source time of the input that caused it.
    var onEvent: ((PressEvent, Double) -> Void)?

    private var nextSample = 0
    private var eventTime: Double = 0

    init(trace: PressTrace) {
        self.trace = trace
        engine = PressEngine(config: trace.config)
        engine.usesVirtualHinge = trace.usesVirtualHinge
        engine.onEvent = { [weak self] event in
            guard let self else { return }
            self.onEvent?(event, self.eventTime)
        }
    }

    /// The object lands on the anvil at source time 0 (trace times are relative to the director's `load`).
    func load() {
        eventTime = 0
        clock = 0
        nextSample = 0
        engine.load(trace.kind, seed: trace.variant.seed, at: 0)
    }

    var lastSampleTime: Double { trace.samples.last?.time ?? 0 }

    /// Feeds every sample stamped at or before `time` (as the director's hinge/touch handlers did),
    /// then steps the engine to `time` (one rendered frame).
    func advance(to time: Double) {
        let samples = trace.samples
        while nextSample < samples.count, samples[nextSample].time <= time {
            let sample = samples[nextSample]
            nextSample += 1
            eventTime = sample.time
            if trace.usesVirtualHinge {
                // Touch samples are never closed; a closed one marks the finger lifting (PressDirector.virtualRelease).
                if sample.closed {
                    engine.releaseVirtual()
                } else {
                    engine.setVirtualAngle(sample.angle, at: sample.time)
                }
            } else {
                engine.ingest(angle: sample.angle, closed: sample.closed, at: sample.time)
            }
        }
        let dt = max(time - clock, 0)
        eventTime = time
        engine.step(now: time, dt: dt)
        clock = max(clock, time)
    }

    /// Fast analysis pass at a fine fixed step: every event with its source time, plus the ram depth curve.
    static func analyse(_ trace: PressTrace, step: Double = 1.0 / 120) -> ReplayAnalysis {
        let replay = PressReplay(trace: trace)
        var marks: [ReplayAnalysis.Mark] = []
        replay.onEvent = { event, time in
            marks.append(ReplayAnalysis.Mark(time: time, event: event))
        }
        replay.load()
        var depths: [Double] = [replay.engine.renderDepth]
        // Seal hold + the touch press's 0.7 s auto-reveal fit well inside 4 s after the last sample.
        let limit = min(replay.lastSampleTime + 4, 900)
        var revealTime: Double?
        var index = 1
        while true {
            let time = Double(index) * step
            if time > limit { break }
            if let revealTime, time > revealTime + 2 { break }
            replay.advance(to: time)
            depths.append(replay.engine.renderDepth)
            if revealTime == nil, let reveal = marks.last(where: { $0.event == .reveal }) {
                revealTime = reveal.time
            }
            index += 1
        }
        return ReplayAnalysis(marks: marks, step: step, depths: depths, duration: Double(depths.count - 1) * step)
    }
}

/// What the analysis pass saw. Pure data, so the clip timeline can be unit-tested without an engine.
struct ReplayAnalysis: Sendable, Equatable {
    struct Mark: Sendable, Equatable {
        var time: Double
        var event: PressEvent
    }

    var marks: [Mark]
    /// Seconds between depth samples.
    var step: Double
    /// Spring-smoothed ram depth (0…1) at `index * step`.
    var depths: [Double]
    /// Last simulated source time.
    var duration: Double

    func depth(at time: Double) -> Double {
        guard !depths.isEmpty else { return 0 }
        let index = min(max(Int((time / step).rounded()), 0), depths.count - 1)
        return depths[index]
    }

    /// When the ram starts to move (or the first real event, for a trace that never moves).
    var pressStart: Double {
        if let index = depths.firstIndex(where: { $0 > 0.01 }) { return Double(index) * step }
        return marks.first(where: { $0.event != .armed })?.time ?? 0
    }

    var revealTime: Double? { marks.first(where: { $0.event == .reveal })?.time }

    var failureTime: Double? {
        marks.first(where: { if case .fracture(_, true) = $0.event { return true } else { return false } })?.time
    }

    /// The moment the clip slows down for: the big failure, else the last fracture, else the bottom-out.
    var climax: (time: Double, isFailure: Bool)? {
        if let failureTime { return (failureTime, true) }
        if let last = marks.last(where: { if case .fracture = $0.event { return true } else { return false } }) {
            return (last.time, false)
        }
        if let bottom = marks.first(where: { $0.event == .bottomOut }) { return (bottom.time, false) }
        return nil
    }

    /// Events that make a stretch worth watching at full speed (grains alone don't).
    var keyMarks: [Mark] {
        marks.filter { mark in
            switch mark.event {
            case .armed, .grain: false
            default: true
            }
        }
    }
}

// MARK: - Timeline

/// Maps clip time to press (source) time (bible §10): a 1 s title card, the press sped up where nothing happens,
/// the failure at 0.3×, then an end card. The total lands in 6–10 s.
///
/// The press segment is a monotone piecewise-linear map from source seconds to clip seconds, sampled on a
/// fine grid. Rates are "clip seconds per source second": 1 = real time, 0.25 = 4× fast, 3.33 = 0.3× slow motion.
struct ClipTimeline: Sendable, Equatable {
    static let fps = 30
    /// Bible §10: the failure plays at 0.3×.
    static let failureSlowMo = 0.3
    /// A climax that isn't a failure (bubble wrap's last pop) gets a gentler 0.5×.
    static let climaxSlowMo = 0.5

    var titleFrames: Int
    var pressFrames: Int
    var endFrames: Int
    /// Source window of the press segment.
    var sourceStart: Double
    var sourceEnd: Double
    /// Knots of the press map: source time → seconds since the press segment began.
    var knotSource: [Double]
    var knotOutput: [Double]

    var titleDuration: Double { Double(titleFrames) / Double(Self.fps) }
    var pressDuration: Double { knotOutput.last ?? 0 }
    var endStart: Double { Double(titleFrames + pressFrames) / Double(Self.fps) }
    var totalFrames: Int { titleFrames + pressFrames + endFrames }
    var totalDuration: Double { Double(totalFrames) / Double(Self.fps) }

    // MARK: Lookup

    /// Source time shown at `t` seconds into the press segment.
    func source(atPressTime t: Double) -> Double {
        guard knotOutput.count > 1 else { return sourceStart }
        if t <= 0 { return knotSource[0] }
        if t >= knotOutput[knotOutput.count - 1] { return knotSource[knotSource.count - 1] }
        let i = Self.segment(in: knotOutput, for: t)
        let span = knotOutput[i + 1] - knotOutput[i]
        let f = span > 0 ? (t - knotOutput[i]) / span : 0
        return knotSource[i] + (knotSource[i + 1] - knotSource[i]) * f
    }

    /// Seconds into the whole clip at which source time `s` plays, or nil outside the press window.
    func clipTime(atSource s: Double) -> Double? {
        guard knotSource.count > 1, s >= sourceStart - 1e-9, s <= sourceEnd + 1e-9 else { return nil }
        let i = Self.segment(in: knotSource, for: s)
        let span = knotSource[i + 1] - knotSource[i]
        let f = span > 0 ? min(max((s - knotSource[i]) / span, 0), 1) : 0
        return titleDuration + knotOutput[i] + (knotOutput[i + 1] - knotOutput[i]) * f
    }

    /// Playback speed at source time `s`: source seconds per clip second (0.3 in the failure slow motion).
    func playbackRate(atSource s: Double) -> Double {
        guard knotSource.count > 1 else { return 1 }
        let i = Self.segment(in: knotSource, for: min(max(s, sourceStart), sourceEnd))
        let output = knotOutput[i + 1] - knotOutput[i]
        return output > 0 ? (knotSource[i + 1] - knotSource[i]) / output : 1
    }

    /// Index `i` with `values[i] <= x < values[i + 1]` (clamped), for an ascending array.
    private static func segment(in values: [Double], for x: Double) -> Int {
        var low = 0
        var high = values.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if values[mid] <= x { low = mid } else { high = mid }
        }
        return min(low, values.count - 2)
    }

    // MARK: Drive schedule

    /// One engine + scene step of a render pass. `frame` is the press-segment frame to capture after it.
    struct DriveStep: Sendable, Equatable {
        var source: Double
        var frame: Int?
    }

    /// The exact step sequence both render passes use (so their events match): a coarse pre-roll from the
    /// placement to the window start, then ≤ 1/60 s source sub-steps up to each frame's source time.
    func driveSteps(preRollStep: Double = 1.0 / 20, maxStep: Double = 1.0 / 60) -> [DriveStep] {
        var steps: [DriveStep] = []
        var time = 0.0
        while time + preRollStep < sourceStart {
            time += preRollStep
            steps.append(DriveStep(source: time, frame: nil))
        }
        for frame in 0..<pressFrames {
            let target = max(source(atPressTime: Double(frame) / Double(Self.fps)), time)
            let gap = target - time
            let count = max(Int((gap / maxStep).rounded(.up)), 1)
            if count > 1 {
                for j in 1..<count {
                    steps.append(DriveStep(source: time + gap * Double(j) / Double(count), frame: nil))
                }
            }
            steps.append(DriveStep(source: target, frame: frame))
            time = target
        }
        return steps
    }

    // MARK: Building

    struct Shape: Equatable {
        var dullRate: Double
        var interestingScale: Double
    }

    /// Builds the retimed clip from an analysis pass.
    /// - Parameters:
    ///   - title: title card length (bible §10: 0–1 s).
    ///   - endCard: preferred end card length; it grows (to 3.5 s) only if the press is too short to reach 6 s.
    ///   - total: the clip length the result must land in (inside the bible's 6–10 s, with a margin).
    static func make(from analysis: ReplayAnalysis, title: Double = 1.0, endCard: Double = 2.0,
                     total: ClosedRange<Double> = 6.3...9.6) -> ClipTimeline {
        let start = max(0, analysis.pressStart - 0.45)
        var end: Double
        if let reveal = analysis.revealTime {
            end = reveal + 1.1 // the ram lifts clear of the flattened specimen
        } else {
            end = (analysis.keyMarks.last?.time ?? analysis.duration) + 0.8
        }
        end = min(end, max(analysis.duration, start + 0.5))
        end = max(end, start + 0.5)

        let h = 1.0 / 120
        let bins = max(Int(((end - start) / h).rounded(.up)), 1)
        let keyTimes = analysis.keyMarks.map(\.time)
        let grainTimes = analysis.marks.compactMap { mark -> Double? in
            if case .grain = mark.event { return mark.time }
            return nil
        }

        // Per-bin interest: 1 = must watch, 0 = dull.
        var interest = [Double](repeating: 0, count: bins)
        var keyCursor = 0
        var grainCursor = 0
        for i in 0..<bins {
            let t = start + (Double(i) + 0.5) * h
            while keyCursor < keyTimes.count, keyTimes[keyCursor] < t - 0.5 { keyCursor += 1 }
            while grainCursor < grainTimes.count, grainTimes[grainCursor] < t - 0.15 { grainCursor += 1 }
            var value = 0.0
            if keyCursor < keyTimes.count, keyTimes[keyCursor] <= t + 0.3 { value = 1 }
            if value < 0.7, grainCursor < grainTimes.count, grainTimes[grainCursor] <= t + 0.15 { value = 0.7 }
            let speed = abs(analysis.depth(at: t + h) - analysis.depth(at: t - h)) / (2 * h)
            if speed > 0.35 { value = max(value, 1) } else if speed > 0.12 { value = max(value, 0.6) }
            interest[i] = value
        }

        // Slow-motion window with short speed ramps (0.6 s of source around the climax, bible §10).
        var slowWeight = [Double](repeating: 0, count: bins)
        var slowRate = 1.0
        if let climax = analysis.climax {
            slowRate = 1 / (climax.isFailure ? failureSlowMo : climaxSlowMo)
            let low = climax.time - 0.2
            let high = climax.time + 0.4
            let ramp = 0.08
            for i in 0..<bins {
                let t = start + (Double(i) + 0.5) * h
                if t >= low && t <= high {
                    slowWeight[i] = 1
                } else if t < low && t > low - ramp {
                    slowWeight[i] = (t - (low - ramp)) / ramp
                } else if t > high && t < high + ramp {
                    slowWeight[i] = ((high + ramp) - t) / ramp
                }
            }
        }

        func rates(_ shape: Shape) -> [Double] {
            var base = interest.map { max($0 * shape.interestingScale, shape.dullRate) }
            // Smooth the speed changes over ±0.12 s so ramps read as intentional.
            let radius = 14
            var prefix = [Double](repeating: 0, count: bins + 1)
            for i in 0..<bins { prefix[i + 1] = prefix[i] + base[i] }
            for i in 0..<bins {
                let a = max(0, i - radius)
                let b = min(bins, i + radius + 1)
                base[i] = (prefix[b] - prefix[a]) / Double(b - a)
            }
            return zip(base, slowWeight).map { rate, w in rate + (slowRate - rate) * w }
        }

        func pressLength(_ shape: Shape) -> Double {
            rates(shape).reduce(0, +) * h
        }

        // Fit the press segment between the bounds by squeezing dull stretches first, then everything else;
        // or, for a very short press, by relaxing the speed-up.
        let minPress = total.lowerBound - title - endCard
        let maxPress = total.upperBound - title - endCard
        let natural = Shape(dullRate: 0.22, interestingScale: 1)
        var shape = natural
        let naturalLength = pressLength(natural)
        if naturalLength > maxPress {
            func squeezed(_ q: Double) -> Shape {
                let dull = 0.22 + (0.03 - 0.22) * min(q * 2, 1)
                let scale = 1 + (0.3 - 1) * max(q * 2 - 1, 0)
                return Shape(dullRate: dull, interestingScale: scale)
            }
            var low = 0.0
            var high = 1.0
            for _ in 0..<26 {
                let mid = (low + high) / 2
                if pressLength(squeezed(mid)) > maxPress { low = mid } else { high = mid }
            }
            shape = squeezed(high)
        } else if naturalLength < minPress {
            func relaxed(_ q: Double) -> Shape {
                Shape(dullRate: 0.22 + (0.8 - 0.22) * q, interestingScale: 1 + 0.35 * q)
            }
            if pressLength(relaxed(1)) <= minPress {
                shape = relaxed(1)
            } else {
                var low = 0.0
                var high = 1.0
                for _ in 0..<26 {
                    let mid = (low + high) / 2
                    if pressLength(relaxed(mid)) < minPress { low = mid } else { high = mid }
                }
                shape = relaxed(high)
            }
        }

        let finalRates = rates(shape)
        var knotSource = [start]
        var knotOutput = [0.0]
        knotSource.reserveCapacity(bins + 1)
        knotOutput.reserveCapacity(bins + 1)
        var output = 0.0
        for i in 0..<bins {
            output += finalRates[i] * h
            knotSource.append(i == bins - 1 ? end : start + Double(i + 1) * h)
            knotOutput.append(output)
        }

        let titleFrames = Int((title * Double(fps)).rounded())
        let pressFrames = max(Int((output * Double(fps)).rounded()), 1)
        var endFrames = Int((endCard * Double(fps)).rounded())
        let minimumFrames = Int((total.lowerBound * Double(fps)).rounded(.up))
        if titleFrames + pressFrames + endFrames < minimumFrames {
            endFrames = min(minimumFrames - titleFrames - pressFrames, Int(3.5 * Double(fps)))
        }
        return ClipTimeline(titleFrames: titleFrames, pressFrames: pressFrames, endFrames: endFrames,
                            sourceStart: start, sourceEnd: end, knotSource: knotSource, knotOutput: knotOutput)
    }
}
