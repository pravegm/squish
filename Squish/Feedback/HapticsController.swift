import AVFoundation
import CoreHaptics
import QuartzCore
import UIKit

/// Core Haptics, three layers on one engine (bible §7):
/// a looping strain bed steered live, per-degree grains (delivered by the engine as `.grain` events),
/// and event patterns from each object's recipe and `BrandCues`.
///
/// Rules enforced here for every cue: the perceptual lift (`HapticTuning.lift`), user level (Off / Soft ×0.6 / Full),
/// ±10 % intensity, ±0.05 sharpness, ±15 % timing (at most ±15 ms), a 12 ms minimum gap between transients, and 1.0
/// intensity only for climaxes (failure, ka-chunk); everything else is capped at `HapticTuning.nonClimaxCap`.
///
/// Engine: haptics only, on its own audio session (`CHHapticEngine()`, i.e. `audioSession: nil`). Apple: "You should
/// pass nil when you need the engine only for playing haptics." 1.0 (1) passed the app's shared session, which ties
/// the engine to that session's category changes and interruptions for no benefit (we play no haptic audio).
/// The engine is self-healing: whatever stops it (backgrounding, the Duo moving between displays, a server reset),
/// the next scene activation, the next frame (throttled) or the next cue starts it again and rebuilds the bed.
@MainActor
final class HapticsController {
    var level: HapticsLevel = .full

    private var engine: CHHapticEngine?
    private var bed: CHHapticAdvancedPatternPlayer?
    private var tremor: (any CHHapticPatternPlayer)?
    private var testBed: (any CHHapticPatternPlayer)?
    private let capabilities = CHHapticEngine.capabilitiesForHardware()
    private var supportsHaptics: Bool { capabilities.supportsHaptics }
    private var isRunning = false
    private var lastRecoveryAttempt: CFTimeInterval = 0
    // Diagnostics (Tuning Lab): Release builds have no console.
    private(set) var lastError: String?
    private(set) var lastStopReason: String?
    private(set) var engineStarts = 0
    private(set) var resets = 0
    private(set) var cuesPlayed = 0
    private var lastIntensity: Float = 0
    private var lastBedTarget: Float = 0
    private var lastSharpness: Float = 0
    private var lastSend: CFTimeInterval = 0
    private var lastUpdate: CFTimeInterval = 0
    private var hushUntil: CFTimeInterval = 0
    private var tellActive = false
    /// Engine times of transients already scheduled (pruned as they pass), for the 12 ms gap rule.
    private var scheduledTransients: [TimeInterval] = []
    /// The hinge outside the press (texture), set by the director every frame before `update` (`HingeFeel`).
    var hinge = HingeBed.still
    private var grainCount = 0
    private var tell = PulseSchedule(kind: .tell)
    private var settle = PulseSchedule(kind: .settle)
    private var wasHoldingLoaded = false
    private var holdCount = 0
    private var fatigue = BedFatigue()
    private var rng = SystemRandomNumberGenerator()
    private let auditionDice = FeedbackDice(seed: 0xB0D1_7105)

    /// Called once at launch (PressDirector.start), before the first press, on every device and in Release.
    func start() {
        guard supportsHaptics else {
            lastError = "This device has no haptic engine"
            return
        }
        guard engine == nil else { return }
        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            // Never let the engine idle itself off: the bed must answer the hinge instantly mid-press.
            engine.isAutoShutdownEnabled = false
            // Both handlers arrive on an engine-internal queue: hop to the main actor with an immutable capture.
            engine.stoppedHandler = { [weak self] reason in
                let why = Self.describe(reason)
                guard let self else { return }
                Task { @MainActor in
                    self.isRunning = false
                    self.bed = nil
                    self.tremor = nil
                    self.testBed = nil
                    self.lastStopReason = why
                }
            }
            engine.resetHandler = { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    self.resets += 1
                    self.isRunning = false
                    self.restart(reason: "after a haptic server reset")
                }
            }
            self.engine = engine
            restart(reason: "launch")
        } catch {
            record("Couldn't create the haptic engine", error)
            engine = nil
        }
    }

    /// Start the engine (if needed) and rebuild the players. After a stop or a reset the server forgets every
    /// player (bible §7), so the bed is always rebuilt here.
    private func restart(reason: String) {
        guard let engine else { return }
        do {
            try engine.start()
            isRunning = true
            engineStarts += 1
        } catch {
            isRunning = false
            record("Couldn't start the haptic engine (\(reason))", error)
            return
        }
        bed = nil
        tremor = nil
        do {
            try makeBed()
        } catch {
            record("Couldn't build the strain bed", error)
        }
    }

    /// Call when the scene becomes active again; the system stops the engine on suspension.
    func resume() {
        guard let engine else {
            start()
            return
        }
        if !isRunning || bed == nil {
            restart(reason: "app active again")
        } else {
            // Cheap and harmless on a running engine; covers a stop whose handler hasn't landed yet.
            try? engine.start()
        }
    }

    /// Lazily recover a stopped engine (throttled), e.g. right before a cue or from the frame loop.
    private func ensureRunning(force: Bool = false) {
        guard engine != nil, !isRunning || bed == nil else { return }
        let now = CACurrentMediaTime()
        guard force || now - lastRecoveryAttempt > 0.5 else { return }
        lastRecoveryAttempt = now
        guard UIApplication.shared.applicationState != .background else { return }
        restart(reason: "found stopped")
    }

    private func record(_ what: String, _ error: Error) {
        let nsError = error as NSError
        lastError = "\(what): \(nsError.localizedDescription) (code \(nsError.code))"
    }

    private nonisolated static func describe(_ reason: CHHapticEngine.StoppedReason) -> String {
        switch reason {
        case .audioSessionInterrupt: "audio session interrupted"
        case .applicationSuspended: "app suspended"
        case .idleTimeout: "idle timeout"
        case .notifyWhenFinished: "finished"
        case .engineDestroyed: "engine destroyed"
        case .gameControllerDisconnect: "game controller disconnected"
        case .systemError: "system error"
        @unknown default: "unknown (\(reason.rawValue))"
        }
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
        // Again once running: a parameter sent before `start` isn't guaranteed to stick, and the bed must start silent.
        try player.sendParameters([CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: 0, relativeTime: 0)],
                                  atTime: CHHapticTimeImmediate)
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
        if !isRunning || bed == nil { ensureRunning() }
        guard let bed else { return }

        let material = context.kind.profile
        let beds = Recipes.recipe(for: context.kind).beds
        let memory = CueBook.shared.memory
        let c = Float(press.measuredCompression)
        let speed = HapticTuning.speed(press.closingSpeed)
        var target: Float = 0
        var ramp: TimeInterval = 0.03
        var sharpness = material.bedSharpness - 0.5

        if now < hushUntil {
            ramp = 0.01 // hush: bed off (01 §6 step 5)
        } else if !press.isLoaded {
            // Not loaded: the hinge texture while it moves (quiet), nothing while still (HingeFeel).
            target = HapticTuning.lift(hinge.texture)
            sharpness = hinge.textureSharpness - 0.5
            ramp = 0.08
        } else if press.closingSpeed < -2 {
            ramp = 0.06 // opening under load: relief within 80 ms
        } else if memory.hasFailed {
            // Crush: softer, speed-driven bed (01 §6 step 7); a low hum while held.
            target = HapticTuning.crushBed(intensity: beds.crushHapticIntensity, speed: speed, holding: press.isHolding)
            sharpness += beds.crushHapticSharpness
            if press.isHolding { ramp = 0.3 }
        } else {
            // Strain under load: a floor as soon as the plates bite, rising to the ceiling at the break. Holding
            // still keeps 70 % of the tension (settling into it over 300 ms) instead of going slack (HapticTuning).
            let progress = Recipes.strainProgress(c, kind: context.kind)
            let strain = beds.hapticCurve.level(progress, sinceFracture: c - memory.lastFractureCompression,
                                                fractures: memory.fractures)
            target = HapticTuning.strainBed(strain: strain, speed: speed, holding: press.isHolding,
                                            materialGain: material.bedGain, recipeMax: beds.hapticMax)
            sharpness += 0.25 * progress
            if tellActive { sharpness += 0.2 }
            if press.isHolding { ramp = 0.3 }
        }

        if target > 0.01 && press.isLoaded { fatigue.record(dt, at: now) }
        target *= fatigue.factor(at: now) * level.scale
        target = clamp(target, 0, isThermallyLimited ? HapticTuning.thermalBedCeiling : HapticTuning.bedCeiling)
        lastBedTarget = target
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

    /// One pattern per event: the shared layers and the recipe's notes together, so the 12 ms gap rule interleaves
    /// them instead of queueing one behind the other (which put the reveal's recipe taps ~0.3 s behind their sound).
    private func perform(_ event: PressEvent, recipeCue: FeedbackCue?) {
        var cue = recipeCue ?? FeedbackCue()
        switch event {
        case .grain:
            // Thermal guard: halve the grain rate (bible §7).
            grainCount += 1
            if isThermallyLimited && grainCount % 2 == 0 { return }
            play(cue, timing: .grain)
            return
        case .fracture(_, true):
            // The failure: the recipe's break plus the heavy body (Duo test 1: "weak").
            cue.add(BrandCues.failureBody)
        case .bottomOut:
            cue.add(BrandCues.bottomOut)
        case .kaChunk:
            cue.add(BrandCues.kaChunk)
        case .reveal:
            cue.add(BrandCues.unlatch)
            cue.add(BrandCues.sting)
        case .armed, .sealed, .preFailureTell, .hush, .contact, .fracture, .released:
            break
        }
        play(cue)
    }

    /// A cue built once by the director and handed to both controllers in the same frame (hinge moments, pokes).
    /// `light`: frequent, droppable cues (detents) never delay and are skipped when they would collide.
    func playShared(_ cue: FeedbackCue, light: Bool = false) {
        play(cue, timing: light ? .grain : .event)
    }

    // MARK: - Diagnostics (Tuning Lab)

    /// "Test vibration": one heavy hit and a short rumble, at full strength whatever the Haptics setting.
    func playTestVibration() {
        let cue = FeedbackCue(haptics: [.tap(1.0, 0.4), .buzz(0.9, 0.2, at: 0.06, duration: 0.3, decay: 0.25),
                                        .tap(0.8, 0.8, at: 0.45)],
                              isClimax: true)
        play(cue, atFullStrength: true)
    }

    /// "Test full press feel": the strain ramp as its own continuous player, plus every transient of the cue
    /// (grains, cracks, failure, ka-chunk), started together. Full strength whatever the Haptics setting.
    func playPressFeel(_ cue: FeedbackCue) {
        if !isRunning { ensureRunning(force: true) }
        guard let engine, isRunning else { return }
        let ramp = PressFeelDemo.bedRamp
        let duration = PressFeelDemo.strainDuration
        let strain = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: PressFeelDemo.bedSharpness.from),
            ],
            relativeTime: 0,
            duration: duration
        )
        let intensity = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: ramp.map { CHHapticParameterCurve.ControlPoint(relativeTime: $0.time, value: $0.intensity) },
            relativeTime: 0
        )
        let sharpness = CHHapticParameterCurve(
            parameterID: .hapticSharpnessControl,
            controlPoints: [
                CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: 0),
                CHHapticParameterCurve.ControlPoint(relativeTime: duration,
                                                    value: PressFeelDemo.bedSharpness.to - PressFeelDemo.bedSharpness.from),
            ],
            relativeTime: 0
        )
        do {
            let pattern = try CHHapticPattern(events: [strain], parameterCurves: [intensity, sharpness])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            testBed = player
        } catch {
            record("Couldn't play the strain ramp", error)
        }
        play(cue, atFullStrength: true)
    }

    func diagnosticRows() -> [DiagnosticRow] {
        let thermal: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "Normal"
        case .fair: thermal = "Warm"
        case .serious: thermal = "Hot (haptics turned down)"
        case .critical: thermal = "Very hot (haptics turned down)"
        @unknown default: thermal = "Unknown"
        }
        return [
            DiagnosticRow(title: "Haptics setting", value: level.title, isWarning: level != .full),
            DiagnosticRow(title: "Hardware supports haptics", value: DiagnosticRow.yesNo(capabilities.supportsHaptics),
                          isWarning: !capabilities.supportsHaptics),
            DiagnosticRow(title: "Haptic engine created", value: DiagnosticRow.yesNo(engine != nil),
                          isWarning: engine == nil),
            DiagnosticRow(title: "Haptic engine running", value: DiagnosticRow.yesNo(isRunning), isWarning: !isRunning),
            DiagnosticRow(title: "Strain bed player", value: bed == nil ? "Missing" : "Ready", isWarning: bed == nil),
            DiagnosticRow(title: "Strain bed now", value: String(format: "%.2f (ceiling %.2f)", lastBedTarget,
                                                                 HapticTuning.bedCeiling)),
            DiagnosticRow(title: "Haptic engine starts", value: "\(engineStarts) · server resets \(resets)"),
            DiagnosticRow(title: "Haptic cues played", value: "\(cuesPlayed)"),
            DiagnosticRow(title: "Last haptic stop", value: lastStopReason ?? "None"),
            DiagnosticRow(title: "Phone temperature", value: thermal, isWarning: isThermallyLimited),
            DiagnosticRow(title: "Last haptic error", value: lastError ?? "None", isWarning: lastError != nil),
        ]
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
                CHHapticEventParameter(parameterID: .hapticIntensity, value: min(HapticTuning.lift(0.16) * level.scale, 1)),
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

    /// `atFullStrength`: the Tuning Lab tests, which ignore the user's level so the hardware itself is tested.
    private func play(_ cue: FeedbackCue, timing: Timing = .event, atFullStrength: Bool = false) {
        guard !cue.haptics.isEmpty, atFullStrength || level != .off else { return }
        if !isRunning { ensureRunning(force: timing == .event) }
        guard let engine, isRunning else { return }
        let scale = atFullStrength ? 1 : level.scale
        let cap = cue.isClimax ? 1 : HapticTuning.nonClimaxCap

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

        // Keep the gap against transients already scheduled, but never drift from the sound by more than 15 ms
        // (EXPERIENCE-PLAN: every haptic within ±15 ms of its sound). 1.0 (1) queued behind the *last* scheduled
        // transient, so the ka-chunk's "ready" taps 1.6 s out delayed every cue in between by up to 1.6 s.
        let now = engine.currentTime
        scheduledTransients.removeAll { $0 < now - 0.05 }
        var startTime = now
        if let firstTransient = notes.first(where: { $0.kind == .transient })?.time {
            let at = now + firstTransient
            if let clash = scheduledTransients.filter({ abs($0 - at) < 0.012 }).max() {
                let delay = clash + 0.012 - at
                if delay > 0.015 {
                    if timing == .grain { return }
                } else {
                    startTime = now + max(delay, 0)
                }
            }
        }
        for note in notes where note.kind == .transient {
            scheduledTransients.append(startTime + note.time)
        }
        if scheduledTransients.count > 256 { scheduledTransients.removeFirst(scheduledTransients.count - 256) }

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
            cuesPlayed &+= 1
        } catch {
            // Never surfaced to the user; the Tuning Lab diagnostics show it.
            record("Couldn't play a haptic", error)
        }
    }

    private func event(for note: HapticNote, scale: Float, cap: Float) -> CHHapticEvent {
        let intensity = min(HapticTuning.lift(note.intensity) * Float.random(in: 0.9...1.1, using: &rng), cap) * scale
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
