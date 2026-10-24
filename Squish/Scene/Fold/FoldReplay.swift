import Foundation

/// The last ~2 s of a press as the anvil drew it, for the reveal ceremony's slow-mo replay of the break
/// (design/EXPERIENCE-PLAN.md "Reveal ceremony"; EXPERIENCE-2 §A3.2, §A7.2). `PressScene` records it every frame on the
/// Duo stage and re-runs a fresh copy of the object through it (`FoldPressController.playBreakReplay(speed:)`).
/// The object views are seeded, so the same states and events give the same cracks and pieces.
struct PressTape {
    /// One drawn frame of the object: what `PressVisualState` was built from.
    struct Frame: Equatable {
        var time: Double
        var compression: Float
        var ramCompression: Float
        var approach: Float
        var closingSpeed: Float
        var loaded: Bool
        /// The object was frozen this frame (a hit stop).
        var frozen: Bool
        var phase: PressPhase
    }

    /// An event as the scene received it, on the scene clock.
    struct Mark {
        var time: Double
        var event: PressEvent
    }

    var frames: [Frame]
    /// Every object event of the press (not only those inside the frames): the ones before the first frame are
    /// applied at once when a replay starts, so earlier cracks are already there.
    var marks: [Mark]
    /// The burst (`.fracture(isFailure: true)`), if the press had one.
    var breakTime: Double?

    var start: Double { frames.first?.time ?? 0 }
    var end: Double { frames.last?.time ?? 0 }
    var duration: Double { max(end - start, 0) }

    /// The frame at tape time `t` (clamped): floats interpolated, flags from the frame at or before `t`.
    func frame(at t: Double) -> Frame? {
        guard let first = frames.first, let last = frames.last else { return nil }
        if t <= first.time { return first }
        if t >= last.time { return last }
        // Binary search for the last frame at or before t.
        var lo = 0, hi = frames.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if frames[mid].time <= t { lo = mid } else { hi = mid }
        }
        let a = frames[lo], b = frames[hi]
        let span = b.time - a.time
        let k = Float(span > 1e-9 ? (t - a.time) / span : 0)
        var f = a
        f.time = t
        f.compression = a.compression + (b.compression - a.compression) * k
        f.ramCompression = a.ramCompression + (b.ramCompression - a.ramCompression) * k
        f.approach = a.approach + (b.approach - a.approach) * k
        f.closingSpeed = a.closingSpeed + (b.closingSpeed - a.closingSpeed) * k
        return f
    }

    /// The push-in, 0 (wide) … 1 (in close on the break) at tape time `t`: eases in over the `lead` s before the
    /// break, holds `hold` s, then eases back out by the end of the tape (Peggle grammar, EXPERIENCE-2 §A3.2).
    /// No break, no push.
    func focus(at t: Double, lead: Double = 0.8, hold: Double = 0.35) -> Double {
        guard let b = breakTime else { return 0 }
        func smooth(_ x: Double) -> Double {
            let x = min(max(x, 0), 1)
            return x * x * (3 - 2 * x)
        }
        if t < b { return smooth((t - (b - lead)) / lead) }
        if t <= b + hold { return 1 }
        let out = max(end - (b + hold), 0.05)
        return 1 - smooth((t - (b + hold)) / out)
    }
}

/// Records the tape while a press runs: a rolling window, centred on the break once there is one.
struct PressTapeRecorder {
    /// Without a break, keep this much of the most recent press.
    static let window = 2.0
    /// With a break: this much before it, and this much after.
    static let beforeBreak = 1.2
    static let afterBreak = 0.8

    private(set) var frames: [PressTape.Frame] = []
    private(set) var marks: [PressTape.Mark] = []
    private(set) var breakTime: Double?
    private(set) var isFinished = false

    mutating func reset() {
        frames.removeAll(keepingCapacity: true)
        marks.removeAll(keepingCapacity: true)
        breakTime = nil
        isFinished = false
    }

    mutating func record(_ frame: PressTape.Frame) {
        guard !isFinished else { return }
        if let b = breakTime, frame.time > b + Self.afterBreak {
            isFinished = true
            return
        }
        frames.append(frame)
        let floor = breakTime.map { $0 - Self.beforeBreak } ?? (frame.time - Self.window)
        if let keep = frames.firstIndex(where: { $0.time >= floor }), keep > 0 {
            frames.removeFirst(keep)
        }
    }

    mutating func mark(_ event: PressEvent, at time: Double) {
        guard !isFinished else { return }
        marks.append(PressTape.Mark(time: time, event: event))
        if case .fracture(_, true) = event, breakTime == nil { breakTime = time }
    }

    /// Nothing more of this press goes on the tape (the reveal has started).
    mutating func finish() { isFinished = true }

    var tape: PressTape? {
        guard frames.count >= 2 else { return nil }
        return PressTape(frames: frames, marks: marks, breakTime: breakTime)
    }
}
