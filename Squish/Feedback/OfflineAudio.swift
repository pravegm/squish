import Foundation

/// Offline twin of `AudioController` for the share clip (bible §10: audio re-rendered, not recorded).
///
/// The export replays the press and calls `place` / `update` / `handle` exactly where the director would call the
/// live controller. Instead of triggering a real-time synth, every command and every bed change is written into a
/// `Score`, stamped with its sample position in the clip. `render(_:frames:)` then plays the score through a
/// private `Synth` (a pure function of its commands), block by block, splitting blocks at every timestamp.
///
/// Sound design is reused, not copied: recipe cues come from a private `CueBook` (reseeded from the variant seed on
/// placement, so the clip gets the same per-press tone), shared layers from `BrandCues`. Only the bed-parameter
/// mapping of `AudioController.update` is mirrored here, because it is private to the live controller.
///
/// Retiming: callers `seek` to the clip time of each call along with the playback rate there. Slow motion
/// (rate < 1) plays like slowed tape: pitch drops a few semitones and envelopes stretch to match.
@MainActor
final class OfflineAudio {
    nonisolated static let sampleRate = 48_000.0
    /// The live mix's master, so the share clip sounds like the press.
    private static let masterGain: Float = AudioMix.masterGain

    /// Everything the synth needs, in clip order. Sendable so the render can run off the main actor.
    struct Score: Sendable {
        struct Note: Sendable {
            var sample: Int
            var command: SynthCommand
        }

        struct Bed: Sendable {
            var sample: Int
            var params: BedParams
        }

        var notes: [Note] = []
        var beds: [Bed] = []
    }

    let style: SoundStyle
    private(set) var score = Score()

    private let cueBook = CueBook()
    private var time: Double = -1
    private var rate: Double = 1

    // Mirrors AudioController's per-press state.
    private var lastTickAngle: Double?
    private var lastPhase: PressPhase = .idle
    private var spinDown: Double = 0
    private var grainCount = 0
    private var tell = PulseSchedule(kind: .tell)
    private var settle = PulseSchedule(kind: .settle)
    private var wasHoldingLoaded = false
    private var holdCount = 0

    init(style: SoundStyle) {
        self.style = style
        // The same recorded foley as the live press, loaded now if it isn't yet: a render must repeat exactly.
        cueBook.library = { SampleLibrary.loadNow() }
    }

    /// Where the next calls land in the clip (seconds; negative = before the clip, so silent) and the playback rate
    /// there (source seconds per clip second: 1 normal, 0.3 in the failure slow motion).
    func seek(to clipTime: Double, rate: Double) {
        time = clipTime
        self.rate = max(rate, 0.05)
    }

    /// Tape-style pitch for slow motion: 0.3× ≈ −3.7 st; fast-forward never pitches up.
    private var pitch: Float {
        Float(min(1, max(0.78, pow(rate, 0.18))))
    }

    private var isAudible: Bool { time >= 0 }
    private var sample: Int { Int((time * Self.sampleRate).rounded()) }

    // MARK: - The AudioController contract, offline

    func place(context: FeedbackContext) {
        tell.stop()
        settle.stop()
        lastTickAngle = nil
        grainCount = 0
        play(cueBook.cue(for: .recipe(.place), context: context, consumer: .audio))
    }

    /// Per frame: beds, gauge ticks, micro-crack and settle schedules. `dt` is source seconds since the last call.
    func update(engine press: PressEngine, context: FeedbackContext, dt: Double) {
        advanceSchedules(press, context: context, dt: dt)

        let beds = Recipes.recipe(for: context.kind).beds
        let memory = cueBook.memory
        let soft = style == .soft
        var params = BedParams()
        params.master = Self.masterGain
        params.softAmount = soft ? 1 : 0

        // The continuous layers follow the hinge at display rate (`renderCompression` from `displayAngle`,
        // `displaySpeed`), so they never step at the real Duo's 25–30 Hz reports (founder's hinge log).
        let c = Float(press.renderCompression)
        let speed = Float(clamp(press.displaySpeed / 120, 0, 1))
        if press.phase == .sealed && lastPhase != .sealed { spinDown = 0.4 }
        lastPhase = press.phase

        switch press.phase {
        case .armed, .pressing:
            if press.displaySpeed > 2 {
                params.hissGain = Self.smoothstep(0.05, 0.8, speed) * 0.045
            }
            params.hissCenter = 1500 * pow(4, speed)
            params.humGain = press.phase == .pressing ? 0.018 + 0.035 * c : 0.010
            params.humPitch = pow(2, (5 * c + speed) / 12)
            if press.isLoaded {
                let opening = press.displaySpeed < -5
                let progress = Recipes.strainProgress(c, kind: context.kind)
                params.creakPitch = beds.creakPitch * (1 + 0.25 * progress)
                params.creakRate = opening ? 0 : (press.isHolding ? 2.5 : 8 + 55 * progress * max(speed, 0.2))
                params.creakGain = beds.creakAmount * (0.012 + 0.03 * progress)
                let strain = beds.strain
                if !memory.hasFailed && !opening && !(soft && strain.isWet) {
                    params.strainGain = strain.gain * pow(progress, 1.5) * max(speed, press.isHolding ? 0.1 : 0.25)
                    params.strainCutoff = strain.cutoff * (1 + strain.cutoffRise * progress)
                    params.strainQ = strain.q
                    params.strainFilter = strain.filter
                    params.strainFlutterRate = strain.flutterRate
                    params.strainFlutterDepth = strain.flutterDepth
                }
                let crush = beds.crush
                if memory.hasFailed && press.displaySpeed > 2 && !(soft && crush.isWet) {
                    let fresh = press.measuredCompression >= press.maxCompression - 0.01
                    params.crushRate = crush.rate * (0.2 + 0.8 * speed) * (fresh ? 1 : 0.25) * (soft ? 0.5 : 1)
                    params.crushGain = crush.gain * (fresh ? 1 : 0.4) * (soft ? 0.7 : 1)
                    params.crushLow = crush.low
                    params.crushHigh = soft ? min(crush.high, 5000) : crush.high
                    params.crushQ = crush.q
                    params.crushGrainDecay = crush.grainDecay
                }
            }
        case .sealed:
            if spinDown > 0 {
                spinDown -= dt
                let fraction = Float(max(spinDown / 0.4, 0))
                params.humGain = 0.05 * fraction
                params.humPitch = 0.6 + 0.7 * fraction
            }
        case .idle, .revealing:
            break
        }

        // Recorded strain / crush loops where the library has one (they replace the noise strain bed).
        if press.isLoaded, let loop = SampleVoicing.loopBed(
            kind: context.kind, progress: Recipes.strainProgress(c, kind: context.kind), speed: speed,
            holding: press.isHolding, failed: memory.hasFailed, opening: press.displaySpeed < -5,
            closing: press.displaySpeed > 2, style: style, library: SampleLibrary.loadNow()
        ) {
            params.loop = loop.data
            params.loopGain = loop.gain
            params.loopRate = loop.rate
            if !memory.hasFailed { params.strainGain = 0 }
        }

        if isAudible {
            score.beds.append(Score.Bed(sample: sample, params: Self.retimed(params, pitch: pitch)))
        }
        updateGaugeTicks(press, failed: memory.hasFailed)
    }

    func handle(_ event: PressEvent, context: FeedbackContext) {
        let recipeCue = RecipeMoment(event).map {
            cueBook.cue(for: .recipe($0), context: context, consumer: .audio)
        }
        switch event {
        case .preFailureTell:
            tell.start(seed: context.variant.seed)
        case .hush, .fracture(_, true), .released, .bottomOut, .kaChunk, .sealed:
            tell.stop()
        case .contact:
            lastTickAngle = nil
        case .armed, .grain, .fracture, .reveal:
            break
        }

        var playRecipe = true
        switch event {
        case .armed, .sealed, .preFailureTell:
            break
        case .contact:
            play(cueBook.cue(for: .brand(.contact), context: context, consumer: .audio))
        case .grain:
            grainCount += 1
            if style == .soft && grainCount % 2 == 0 { playRecipe = false }
        case .hush:
            // The duck stretches with the slow motion, so the failure still lands on silence.
            emit(.hush(duration: Float(min(0.07 / rate, 0.3))))
        case .fracture(_, let isFailure):
            if isFailure { play(BrandCues.tonic) }
        case .bottomOut:
            play(BrandCues.bottomOut)
        case .kaChunk:
            play(cueBook.cue(for: .brand(.kaChunk), context: context, consumer: .audio))
        case .released:
            play(BrandCues.releaseSigh)
        case .reveal:
            play(BrandCues.unlatch)
            play(BrandCues.releaseSigh)
            play(BrandCues.sting)
            play(cueBook.cue(for: .brand(.stamp), context: context, consumer: .audio))
        }
        if playRecipe, let recipeCue {
            play(recipeCue)
        }
    }

    /// Plays a cue at the current clip time (title and end card stingers).
    func play(_ cue: FeedbackCue) {
        guard isAudible, !cue.sounds.isEmpty else { return }
        for layer in cue.styled(style).sounds {
            emit(layer.command)
        }
    }

    /// The two quiet "ready" tinks of the ka-chunk, without its 1.5 s wait: the title card's brand motif.
    static var readyTinks: FeedbackCue {
        let layers = BrandCues.kaChunk.sounds.filter { $0.slot.id.hasPrefix("press.kachunk.ready") }
        let first = layers.map(\.command.delay).min() ?? 0
        return FeedbackCue(sounds: layers.map { layer in
            var shifted = layer
            shifted.command = layer.command.offsettingDelay(by: -first)
            return shifted
        })
    }

    // MARK: - Internals (mirroring AudioController)

    private func emit(_ command: SynthCommand) {
        guard isAudible else { return }
        score.notes.append(Score.Note(sample: sample, command: Self.retimed(command, pitch: pitch)))
    }

    private func updateGaugeTicks(_ press: PressEngine, failed: Bool) {
        guard press.isLoaded, press.displaySpeed > 0 else {
            if press.displaySpeed < -5 || press.phase != .pressing { lastTickAngle = nil }
            return
        }
        guard let last = lastTickAngle else {
            lastTickAngle = press.angle
            return
        }
        if press.angle <= last - 5 {
            lastTickAngle = press.angle
            let scale = BrandCues.pentatonic
            let step = min(Int(press.measuredCompression * 10), scale.count - 1)
            play(BrandCues.tick(scale[step], gain: failed ? 0.6 : 1))
        }
    }

    private func advanceSchedules(_ press: PressEngine, context: FeedbackContext, dt: Double) {
        if tell.isRunning {
            if !press.isLoaded || press.displaySpeed < -5 {
                tell.stop()
            } else if let index = tell.advance(by: dt * (press.isHolding ? 0.35 : 1)) {
                play(cueBook.cue(for: .recipe(.microCrack(index: index)), context: context, consumer: .audio))
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
            play(cueBook.cue(for: .settle(index), context: context, consumer: .audio))
        }
    }

    private static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    // MARK: - Slow-motion retiming

    /// Slowed tape: frequencies × `pitch`, every time constant ÷ `pitch`.
    nonisolated static func retimed(_ command: SynthCommand, pitch p: Float) -> SynthCommand {
        guard p < 0.999 else { return command }
        switch command {
        case .noise(var spec):
            spec.cutoff *= p
            spec.cutoffEnd *= p
            spec.sweepTime /= p
            spec.attack /= p
            spec.decay /= p
            spec.delay /= p
            return .noise(spec)
        case .tone(var spec):
            spec.start *= p
            spec.end *= p
            spec.glide /= p
            spec.duration /= p
            spec.attack /= p
            spec.decay /= p
            spec.delay /= p
            spec.vibratoRate *= p
            return .tone(spec)
        case .ring(var spec):
            spec.fundamental *= p
            spec.decay /= p
            spec.delay /= p
            return .ring(spec)
        case .crunch(var spec):
            spec.duration /= p
            spec.rate *= p
            spec.rateEnd *= p
            spec.low *= p
            spec.high *= p
            spec.grainDecay /= p
            spec.delay /= p
            return .crunch(spec)
        case .sample(var spec):
            // Slowed tape: the recording plays slower and lower.
            spec.rate *= p
            spec.delay /= p
            return .sample(spec)
        case .hush:
            return command
        }
    }

    nonisolated static func retimed(_ params: BedParams, pitch p: Float) -> BedParams {
        guard p < 0.999 else { return params }
        var copy = params
        copy.hissCenter *= p
        copy.humPitch *= p
        copy.creakPitch *= p
        copy.strainCutoff *= p
        copy.strainFlutterRate *= p
        copy.crushRate *= p
        copy.crushLow *= p
        copy.crushHigh *= p
        copy.crushGrainDecay /= p
        copy.loopRate *= p
        return copy
    }

    // MARK: - Render

    /// Plays the score through a fresh synth into `frames` mono Float32 samples at 48 kHz.
    /// Pure and thread-agnostic: run it off the main actor. A short fade-out avoids a click at the cut.
    nonisolated static func render(_ score: Score, frames: Int, sampleRate: Double = OfflineAudio.sampleRate) -> [Float] {
        guard frames > 0 else { return [] }
        let synth = Synth(sampleRate: Float(sampleRate))
        // Stable order: by sample, then by the order the calls were made.
        let notes = score.notes.enumerated().sorted { ($0.element.sample, $0.offset) < ($1.element.sample, $1.offset) }
            .map(\.element)
        let beds = score.beds.enumerated().sorted { ($0.element.sample, $0.offset) < ($1.element.sample, $1.offset) }
            .map(\.element)
        var output = [Float](repeating: 0, count: frames)
        output.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            var cursor = 0
            var noteIndex = 0
            var bedIndex = 0
            while cursor < frames {
                while bedIndex < beds.count, beds[bedIndex].sample <= cursor {
                    synth.setBeds(beds[bedIndex].params)
                    bedIndex += 1
                }
                // The synth drains at most 32 commands per render call; leftovers start one sample later.
                var pushed = 0
                while noteIndex < notes.count, notes[noteIndex].sample <= cursor, pushed < 32 {
                    synth.trigger(notes[noteIndex].command)
                    noteIndex += 1
                    pushed += 1
                }
                var end = min(frames, cursor + 512)
                if noteIndex < notes.count { end = min(end, max(notes[noteIndex].sample, cursor + 1)) }
                if bedIndex < beds.count { end = min(end, max(beds[bedIndex].sample, cursor + 1)) }
                synth.render(frames: end - cursor, into: base + cursor)
                cursor = end
            }
            let fadeIn = min(Int(sampleRate * 0.005), frames)
            for i in 0..<fadeIn { base[i] *= Float(i) / Float(max(fadeIn, 1)) }
            let fadeOut = min(Int(sampleRate * 0.25), frames)
            for i in 0..<fadeOut {
                let index = frames - fadeOut + i
                base[index] *= 1 - Float(i) / Float(fadeOut)
            }
        }
        return output
    }
}

private extension SynthCommand {
    /// The same command, starting `offset` seconds later (never before "now").
    func offsettingDelay(by offset: Float) -> SynthCommand {
        switch self {
        case .noise(var spec): spec.delay = max(spec.delay + offset, 0); return .noise(spec)
        case .tone(var spec): spec.delay = max(spec.delay + offset, 0); return .tone(spec)
        case .ring(var spec): spec.delay = max(spec.delay + offset, 0); return .ring(spec)
        case .crunch(var spec): spec.delay = max(spec.delay + offset, 0); return .crunch(spec)
        case .sample(var spec): spec.delay = max(spec.delay + offset, 0); return .sample(spec)
        case .hush: return self
        }
    }
}
