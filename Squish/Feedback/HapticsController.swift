import AVFoundation
import CoreHaptics
import QuartzCore

/// Core Haptics, three layers on one engine (bible §7):
/// a looping strain bed steered live, per-degree grains, and event patterns.
@MainActor
final class HapticsController {
    /// User setting × device gain. Off = 0, Soft = 0.6, Full = 1.
    var scale: Float = 1

    private var engine: CHHapticEngine?
    private var bed: CHHapticAdvancedPatternPlayer?
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private var lastIntensity: Float = 0
    private var lastSharpness: Float = 0.5
    private var hushUntil: CFTimeInterval = 0
    private var tellUntil: CFTimeInterval = 0
    private var nextTransientTime: TimeInterval = 0
    private var rng = SystemRandomNumberGenerator()

    func start() {
        guard supportsHaptics, engine == nil else { return }
        do {
            let engine = try CHHapticEngine(audioSession: .sharedInstance())
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = false
            engine.stoppedHandler = { [weak self] _ in
                Task { @MainActor in self?.bed = nil }
            }
            engine.resetHandler = { [weak self] in
                Task { @MainActor in self?.restart() }
            }
            try engine.start()
            self.engine = engine
            try makeBed()
        } catch {
            engine = nil
        }
    }

    private func restart() {
        guard let engine else { return }
        bed = nil
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

    // MARK: - Per frame

    func update(engine press: PressEngine) {
        guard let bed, let material = press.material else { return }
        let now = CACurrentMediaTime()
        var intensity: Float = 0
        let c = Float(press.measuredCompression)
        if press.isLoaded && !press.isHolding && press.closingSpeed > 0 && now >= hushUntil {
            let speed = Float(clamp(press.closingSpeed / 60, 0, 1))
            intensity = min(0.7, (0.15 + 0.55 * c) * (0.35 + 0.65 * speed)) * material.bedGain
            if now < tellUntil {
                intensity *= 1 + 0.08 * sin(Float(2 * Double.pi * 14 * now))
            }
        }
        intensity = clamp(intensity * scale, 0, 1)
        var sharpness = material.bedSharpness - 0.5 + 0.25 * c
        if now < tellUntil { sharpness += 0.2 }
        sharpness = clamp(sharpness, -1, 1)

        guard abs(intensity - lastIntensity) > 0.02 || abs(sharpness - lastSharpness) > 0.02 else { return }
        // Ramp over 30 ms instead of stepping: raw steps at hinge rate feel like a zipper.
        let curve = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: lastIntensity),
                CHHapticParameterCurve.ControlPoint(relativeTime: 0.03, value: intensity),
            ],
            relativeTime: 0
        )
        try? bed.scheduleParameterCurve(curve, atTime: CHHapticTimeImmediate)
        try? bed.sendParameters([CHHapticDynamicParameter(parameterID: .hapticSharpnessControl, value: sharpness, relativeTime: 0)],
                                atTime: CHHapticTimeImmediate)
        lastIntensity = intensity
        lastSharpness = sharpness
    }

    // MARK: - Events

    func handle(_ event: PressEvent, kind: ObjectKind) {
        switch event {
        case .armed, .sealed:
            break
        case .contact:
            transient(0.40, 0.30)
        case .grain(let c):
            switch kind {
            case .bubbleWrap: transient(0.14 + 0.1 * Float(c), 0.8)
            case .rubberDuck: transient(0.16 + 0.12 * Float(c), 0.3)
            }
        case .preFailureTell:
            tellUntil = CACurrentMediaTime() + 0.35
        case .hush:
            hushUntil = CACurrentMediaTime() + 0.06
        case .fracture(let index, let isFailure):
            fracture(kind: kind, index: index, isFailure: isFailure)
        case .bottomOut:
            transient(0.75, 0.15)
        case .kaChunk:
            play([
                transientEvent(1.0, 0.15, at: 0),
                continuousEvent(0.8, 0.05, at: 0.005, duration: 0.12, decay: 0.10),
                transientEvent(0.35, 0.4, at: 1.5),
                transientEvent(0.35, 0.4, at: 1.62),
            ])
        case .released:
            break
        case .reveal:
            play([transientEvent(0.4, 0.5, at: 0), transientEvent(0.55, 0.5, at: 0.16)])
        }
    }

    func place() {
        transient(0.35, 0.4)
    }

    func collect() {
        play([transientEvent(0.6, 0.6, at: 0), transientEvent(0.9, 0.4, at: 0.09)])
    }

    private func fracture(kind: ObjectKind, index: Int, isFailure: Bool) {
        switch kind {
        case .bubbleWrap:
            transient(Float.random(in: 0.55...0.8, using: &rng), Float.random(in: 0.7...0.85, using: &rng))
        case .rubberDuck:
            if isFailure {
                // Pop: hard transient, then an air rush with fine grains.
                var events = [transientEvent(1.0, 0.5, at: 0),
                              continuousEvent(0.4, 0.6, at: 0.01, duration: 0.5, decay: 0.45)]
                for i in 0..<12 {
                    events.append(transientEvent(0.2, 0.9, at: 0.03 + Double(i) * 0.025))
                }
                play(events)
            } else {
                // Comic honk.
                play([transientEvent(0.5, 0.35, at: 0), continuousEvent(0.3, 0.3, at: 0.01, duration: 0.2, decay: 0.15)])
            }
        }
    }

    // MARK: - Helpers

    private func transient(_ intensity: Float, _ sharpness: Float) {
        play([transientEvent(intensity, sharpness, at: 0)], enforceGap: true)
    }

    private func jittered(_ value: Float) -> Float {
        clamp(value * Float.random(in: 0.9...1.1, using: &rng), 0, 1)
    }

    private func transientEvent(_ intensity: Float, _ sharpness: Float, at time: TimeInterval) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: clamp(jittered(intensity) * scale, 0, 1)),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: clamp(sharpness + Float.random(in: -0.05...0.05, using: &rng), 0, 1)),
            ],
            relativeTime: time
        )
    }

    private func continuousEvent(_ intensity: Float, _ sharpness: Float, at time: TimeInterval,
                                 duration: TimeInterval, decay: Float) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: clamp(jittered(intensity) * scale, 0, 1)),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
                CHHapticEventParameter(parameterID: .sustained, value: 0),
                CHHapticEventParameter(parameterID: .decayTime, value: decay),
            ],
            relativeTime: time,
            duration: duration
        )
    }

    /// Plays a one-shot pattern. With `enforceGap`, transients closer than 12 ms are pushed back (or dropped
    /// if the queue is already 100 ms ahead) so same-type events never blur together.
    private func play(_ events: [CHHapticEvent], enforceGap: Bool = false) {
        guard let engine, scale > 0 else { return }
        var startTime = CHHapticTimeImmediate
        if enforceGap {
            let now = engine.currentTime
            let earliest = max(now, nextTransientTime)
            guard earliest - now < 0.1 else { return }
            nextTransientTime = earliest + 0.012
            startTime = earliest > now ? earliest : CHHapticTimeImmediate
        }
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: startTime)
        } catch {
            // A dropped haptic is never worth surfacing to the user.
        }
    }
}
