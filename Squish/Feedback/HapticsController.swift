import AVFoundation
import CoreHaptics
import QuartzCore

/// Core Haptics, three layers on one engine (bible §7):
/// a looping strain bed steered live, per-degree grains (delivered by the engine as `.grain` events),
/// and event patterns from each object's recipe and `BrandCues`.
///
/// Rules enforced here for every cue: user level (Off / Soft ×0.6 / Full), ±10 % intensity, ±0.05 sharpness,
/// ±15 % timing (at most ±15 ms), a 12 ms minimum gap between transients, and 1.0 intensity only for climaxes
/// (failure, ka-chunk); everything else is capped at 0.9.
@MainActor
final class HapticsController {
    var level: HapticsLevel = .full

    private var engine: CHHapticEngine?
    private var bed: CHHapticAdvancedPatternPlayer?
    private var tremor: (any CHHapticPatternPlayer)?
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private var lastIntensity: Float = 0
    private var lastSharpness: Float = 0
    private var lastSend: CFTimeInterval = 0
    private var lastUpdate: CFTimeInterval = 0
    private var hushUntil: CFTimeInterval = 0
    private var tellActive = false
    private var nextTransientTime: TimeInterval = 0
    private var grainCount = 0
    private var tell = PulseSchedule(kind: .tell)
    private var settle = PulseSchedule(kind: .settle)
    private var wasHoldingLoaded = false
    private var holdCount = 0
    private var fatigue = BedFatigue()
    private var rng = SystemRandomNumberGenerator()
    private let auditionDice = FeedbackDice(seed: 0xB0D1_7105)

    private static let nonClimaxCap: Float = 0.9

    func start() {
        guard supportsHaptics, engine == nil else { return }
        do {
            let engine = try CHHapticEngine(audioSession: .sharedInstance())
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = false
            // Both handlers arrive on an engine-internal queue: hop to the main actor with an immutable capture.
            engine.stoppedHandler = { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.bed = nil
                    self.tremor = nil
                }
            }
            engine.resetHandler = { [weak self] in
                guard let self else { return }
                Task { @MainActor in self.restart() }
            }
            try engine.start()
            self.engine = engine
            try makeBed()
        } catch {
            engine = nil
        }
    }

    /// After a reset the server forgets every player: rebuild them (bible §7).
    private func restart() {
        guard let engine else { return }
        bed = nil
        tremor = nil
        try? engine.start()
        try? makeBed()
    }

    /// Call when the scene becomes active again; the system stops the engine on suspension.
    func resume() {
        guard let engine else {
            start()
            return
        }
        try? engine.start()
        if bed == nil { try? makeBed() }
    }

    /// The strain bed: one continuous event at I 1.0 / S 0.5, looped, steered down and sideways at runtime.
    private func makeBed() throws {
        guard let engine else { return }
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5),
            ],
            relativeTime: 0,
            duration: 30
        )
        let pattern = try CHHapticPattern(events: [event], parameters: [])
        let player = try engine.makeAdvancedPlayer(with: pattern)
        player.loopEnabled = true
        try player.sendParameters([CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: 0, relativeTime: 0)],
                                  atTime: CHHapticTimeImmediate)
        try player.start(atTime: CHHapticTimeImmediate)
        bed = player
        lastIntensity = 0
    }

    private var isThermallyLimited: Bool {
        let state = ProcessInfo.processInfo.thermalState
        return state == .serious || state == .critical
    }

    // MARK: - Per frame

    func update(engine press: PressEngine, context: FeedbackContext) {
        let now = CACurrentMediaTime()
        let dt = lastUpdate == 0 ? 1.0 / 60 : min(max(now - lastUpdate, 0), 0.1)
        lastUpdate = now
        advanceSchedules(press, context: context, dt: dt)
        guard let bed else { return }

        let material = context.kind.profile
        let beds = Recipes.recipe(for: context.kind).beds
        let memory = CueBook.shared.memory
        let c = Float(press.measuredCompression)
        let speed = Float(clamp(press.closingSpeed / 60, 0, 1))
        var target: Float = 0
        var ramp: TimeInterval = 0.03
        var sharpness = material.bedSharpness - 0.5

        if now < hushUntil {
            ramp = 0.01 // hush: bed off (01 §6 step 5)
        } else if !press.isLoaded || press.closingSpeed < -2 {
            ramp = 0.06 // opening: relief within 80 ms
        } else if press.isHolding {
            ramp = 0.3 // holding still: fade over 300 ms
        } else if memory.hasFailed {
            // Crush: softer, speed-driven bed (01 §6 step 7).
            target = beds.crushHapticIntensity * (0.3 + 0.7 * speed)
            sharpness += beds.crushHapticSharpness
        } else {
            // I_bed = strain(p) · (0.35 + 0.65·v), clamped ≤ 0.7 (01 §3.2).
            let progress = Recipes.strainProgress(c, kind: context.kind)
            let strain = beds.hapticCurve.level(progress, sinceFracture: c - memory.lastFractureCompression,
                                                fractures: memory.fractures)
            target = min(beds.hapticMax, strain * (0.35 + 0.65 * speed)) * material.bedGain
            sharpness += 0.25 * progress
            if tellActive { sharpness += 0.2 }
        }

        if target > 0.01 { fatigue.record(dt, at: now) }
        target *= fatigue.factor(at: now) * level.scale
        target = clamp(target, 0, isThermallyLimited ? 0.5 : 0.7)
        sharpness = clamp(sharpness, -1, 1)

        let mustSilence = target == 0 && lastIntensity > 0
        guard mustSilence || abs(target - lastIntensity) > 0.02 || abs(sharpness - lastSharpness) > 0.02 else { return }
        // ≤ 60 Hz sends, except when the bed must go quiet now.
        guard mustSilence || now - lastSend >= 1.0 / 60 else { return }
        lastSend = now
        // Ramp with a 2-point curve instead of stepping: raw steps at hinge rate feel like a zipper.
        let curve = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: lastIntensity),
                CHHapticParameterCurve.ControlPoint(relativeTime: ramp, value: target),
            ],
            relativeTime: 0
        )
        try? bed.scheduleParameterCurve(curve, atTime: CHHapticTimeImmediate)
        try? bed.sendParameters([CHHapticDynamicParameter(parameterID: .hapticSharpnessControl, value: sharpness, relativeTime: 0)],
                                atTime: CHHapticTimeImmediate)
        lastIntensity = target
        lastSharpness = sharpness
    }

    /// Micro-cracks during the tell and settling creaks while held, in lockstep with the audio.
    private func advanceSchedules(_ press: PressEngine, context: FeedbackContext, dt: Double) {
        if tell.isRunning {
            if !press.isLoaded || press.closingSpeed < -5 {
                endTell()
            } else if let index = tell.advance(by: dt * (press.isHolding ? 0.35 : 1)) {
                play(CueBook.shared.cue(for: .recipe(.microCrack(index: index)), context: context, consumer: .haptics),
                     timing: .grain)
            }
        }
        let holdingLoaded = press.isLoaded && press.isHolding
        if holdingLoaded && !wasHoldingLoaded {
            holdCount += 1
            settle.start(seed: context.variant.seed &+ UInt64(holdCount))
        }
        if !holdingLoaded { settle.stop() }
        wasHoldingLoaded = holdingLoaded
        if let index = settle.advance(by: dt) {
            play(CueBook.shared.cue(for: .settle(index), context: context, consumer: .haptics), timing: .grain)
        }
    }

    // MARK: - Events

    func handle(_ event: PressEvent, context: FeedbackContext) {
        let recipeCue = RecipeMoment(event).map {
            CueBook.shared.cue(for: .recipe($0), context: context, consumer: .haptics)
        }
        switch event {
        case .preFailureTell:
            tellActive = true
            tell.start(seed: context.variant.seed)
            startTremor()
        case .hush:
            hushUntil = CACurrentMediaTime() + 0.06
            endTell()
        case .fracture(_, true), .released, .bottomOut, .kaChunk, .sealed:
            endTell()
        case .armed, .contact, .grain, .fracture, .reveal:
            break
        }
        perform(event, recipeCue: recipeCue)
    }

    func place(context: FeedbackContext) {
        endTell()
        settle.stop()
        grainCount = 0
        play(CueBook.shared.cue(for: .recipe(.place), context: context, consumer: .haptics))
    }

    func collect() {
        play(BrandCues.collect)
    }

    /// Tuning Lab: feel one moment of an object's recipe plus the shared layers, outside the live press.
    func audition(_ kind: ObjectKind, event: PressEvent, golden: Bool = false, surprise: Surprise? = nil) {
        let context = Audition.context(for: kind, event: event, golden: golden, surprise: surprise)
        let recipeCue = RecipeMoment(event).map { CueBook.preview($0, context: context, dice: auditionDice) }
        perform(event, recipeCue: recipeCue)
    }

    /// Tuning Lab: feel the object's placement tap.
    func auditionPlace(_ kind: ObjectKind) {
        let context = Audition.context(for: kind, event: .armed)
        play(CueBook.preview(.place, context: context, dice: auditionDice))
    }

    private func perform(_ event: PressEvent, recipeCue: FeedbackCue?) {
        switch event {
        case .armed, .sealed, .preFailureTell, .hush, .contact, .fracture, .released, .reveal:
            break
        case .grain:
            // Thermal guard: halve the grain rate (bible §7).
            grainCount += 1
            if isThermallyLimited && grainCount % 2 == 0 { return }
            if let recipeCue { play(recipeCue, timing: .grain) }
            return
        case .bottomOut:
            play(BrandCues.bottomOut)
        case .kaChunk:
            play(BrandCues.kaChunk)
        }
        if case .reveal = event {
            play(BrandCues.sting)
        }
        if let recipeCue { play(recipeCue) }
    }

    // MARK: - Tremor (01 §6 step 4)

    /// A 14 Hz intensity tremor (±0.08 around the bed) as its own player, stopped by the hush.
    private func startTremor() {
        guard let engine, level != .off else { return }
        tremor = nil
        var points: [CHHapticParameterCurve.ControlPoint] = []
        var time: TimeInterval = 0
        for index in 0..<16 { // Core Haptics allows 16 control points per curve.
            points.append(CHHapticParameterCurve.ControlPoint(relativeTime: time, value: index % 2 == 0 ? 1 : 0.2))
            time += (1.0 / 28) * Double.random(in: 0.9...1.1, using: &rng)
        }
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: min(0.16 * level.scale, 1)),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7),
            ],
            relativeTime: 0,
            duration: time
        )
        let curve = CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: points, relativeTime: 0)
        do {
            let pattern = try CHHapticPattern(events: [event], parameterCurves: [curve])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            tremor = player
        } catch {
            tremor = nil
        }
    }

    private func endTell() {
        tellActive = false
        tell.stop()
        if let tremor {
            try? tremor.stop(atTime: CHHapticTimeImmediate)
        }
        tremor = nil
    }

    // MARK: - Playback

    private enum Timing {
        /// Never blocks: a grain more than 100 ms behind the gap queue is dropped.
        case grain
        /// Always plays, delayed if needed to keep the 12 ms gap.
        case event
    }

    private func play(_ cue: FeedbackCue, timing: Timing = .event) {
        guard let engine, level != .off, !cue.haptics.isEmpty else { return }
        let scale = level.scale
        let cap = cue.isClimax ? 1 : Self.nonClimaxCap

        // ±15 % timing jitter (at most ±15 ms), then the 12 ms gap between transients.
        var notes = cue.haptics.map { note -> HapticNote in
            var jittered = note
            let shift = note.time * Double.random(in: -0.15...0.15, using: &rng)
            jittered.time = max(0, note.time + clamp(shift, -0.015, 0.015))
            return jittered
        }
        notes.sort { $0.time < $1.time }
        var lastTransient = -Double.infinity
        for index in notes.indices where notes[index].kind == .transient {
            if notes[index].time < lastTransient + 0.012 {
                notes[index].time = lastTransient + 0.012
            }
            lastTransient = notes[index].time
        }

        // Keep the gap against patterns already scheduled.
        let now = engine.currentTime
        var startTime = now
        if let firstTransient = notes.first(where: { $0.kind == .transient })?.time,
           now + firstTransient < nextTransientTime {
            let delay = nextTransientTime - (now + firstTransient)
            if timing == .grain && delay > 0.1 { return }
            startTime = now + delay
        }
        if lastTransient > -Double.infinity {
            nextTransientTime = max(nextTransientTime, startTime + lastTransient + 0.012)
        }

        let events = notes.map { event(for: $0, scale: scale, cap: cap) }
        var curves: [CHHapticParameterCurve] = []
        if let sweep = cue.sharpnessSweep {
            curves.append(CHHapticParameterCurve(
                parameterID: .hapticSharpnessControl,
                controlPoints: [
                    CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: sweep.from),
                    CHHapticParameterCurve.ControlPoint(relativeTime: sweep.duration, value: sweep.to),
                ],
                relativeTime: 0
            ))
        }
        do {
            let pattern = try CHHapticPattern(events: events, parameterCurves: curves)
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: startTime > now ? startTime : CHHapticTimeImmediate)
        } catch {
            // A dropped haptic is never worth surfacing to the user.
        }
    }

    private func event(for note: HapticNote, scale: Float, cap: Float) -> CHHapticEvent {
        let intensity = min(note.intensity * Float.random(in: 0.9...1.1, using: &rng), cap) * scale
        let sharpness = clamp(note.sharpness + Float.random(in: -0.05...0.05, using: &rng), 0, 1)
        switch note.kind {
        case .transient:
            return CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: clamp(intensity, 0, 1)),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
                ],
                relativeTime: note.time
            )
        case .continuous:
            return CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: clamp(intensity, 0, 1)),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
                    CHHapticEventParameter(parameterID: .attackTime, value: note.attack),
                    CHHapticEventParameter(parameterID: .decayTime, value: note.decay),
                    CHHapticEventParameter(parameterID: .releaseTime, value: note.release),
                    CHHapticEventParameter(parameterID: .sustained, value: note.sustained ? 1 : 0),
                ],
                relativeTime: note.time,
                duration: max(note.duration, 0.01)
            )
        }
    }
}

/// Fatigue guard (bible §7): after 60 s of bed time within 5 minutes, the bed drops 10 %.
private struct BedFatigue {
    private static let bucketSeconds: Double = 10
    private static let bucketCount = 30 // 30 × 10 s = 5 min
    private var seconds = [Double](repeating: 0, count: BedFatigue.bucketCount)
    private var ids = [Int](repeating: -1, count: BedFatigue.bucketCount)

    mutating func record(_ dt: Double, at time: Double) {
        let id = Int(time / Self.bucketSeconds)
        let slot = ((id % Self.bucketCount) + Self.bucketCount) % Self.bucketCount
        if ids[slot] != id {
            ids[slot] = id
            seconds[slot] = 0
        }
        seconds[slot] += dt
    }

    func factor(at time: Double) -> Float {
        let current = Int(time / Self.bucketSeconds)
        var total: Double = 0
        for index in 0..<Self.bucketCount where ids[index] > current - Self.bucketCount {
            total += seconds[index]
        }
        return total > 60 ? 0.9 : 1
    }
}
