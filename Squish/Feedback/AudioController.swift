import AVFoundation
import QuartzCore

/// Owns the audio session and engine and turns press events into synthesised sound (bible §8).
/// Shared press layers (hiss, motor, creak, gauge ticks, hush, bottom-out, ka-chunk, sting, chime, fanfare) live here
/// and in `BrandCues`; each object's material sounds come from its recipe through `CueBook`.
///
/// Gain staging (target ≈ −16 LUFS integrated, 02 §6): beds sit around −30 dBFS, grains −30…−20, fractures −12…−8,
/// failures and the ka-chunk peak into the −1 dBFS limiter, about 6 LU above the strain bed.
@MainActor
final class AudioController {
    var enabled = true
    var style: SoundStyle = .workshop
    /// Extra trim for the Tuning Lab.
    var volume: Float = 1
    /// Sampled-layer seam (bible §15.1). Nil in v1: everything is synthesised.
    var sampleBank: (any SampleBank)?

    private static let masterGain: Float = 0.8

    private let engine = AVAudioEngine()
    private var synth: Synth?
    private var sourceNode: AVAudioSourceNode?
    private var observers: [NSObjectProtocol] = []
    private var lastTickAngle: Double?
    private var lastUpdate: CFTimeInterval = 0
    private var lastPhase: PressPhase = .idle
    private var spinDown: Double = 0
    private var grainCount = 0
    private var tell = PulseSchedule(kind: .tell)
    private var settle = PulseSchedule(kind: .settle)
    private var wasHoldingLoaded = false
    private var holdCount = 0
    private let auditionDice = FeedbackDice(seed: 0xA0D1_7105)

    func start() {
        guard synth == nil else { return }
        let session = AVAudioSession.sharedInstance()
        // .ambient respects the silent switch and mixes with the user's own music.
        try? session.setCategory(.ambient, mode: .default, options: [])
        try? session.setPreferredSampleRate(48_000)
        try? session.setPreferredIOBufferDuration(0.005)
        try? session.setActive(true)

        let sampleRate = session.sampleRate > 0 ? session.sampleRate : 48_000
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }
        let synth = Synth(sampleRate: Float(sampleRate))
        let node = AVAudioSourceNode(format: format, renderBlock: Self.renderBlock(for: synth))
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        try? engine.start()
        self.synth = synth
        sourceNode = node

        // Route changes (headphones in/out) can stop the engine; restart it.
        observers.append(NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.engine.isRunning else { return }
                try? self.engine.start()
            }
        })
        // Calls and Siri interrupt the session; pick up again when they end (not when they begin).
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .ended else { return }
            MainActor.assumeIsolated {
                self?.resume()
            }
        })
    }

    /// Built outside the main actor on purpose: the block runs on the real-time audio thread, so it must not
    /// inherit main-actor isolation (which would add a runtime isolation check). It touches only `Synth`.
    private nonisolated static func renderBlock(for synth: Synth) -> AVAudioSourceNodeRenderBlock {
        { _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard let first = buffers.first, let data = first.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            synth.render(frames: Int(frameCount), into: data)
            if buffers.count > 1 {
                for index in 1..<buffers.count {
                    buffers[index].mData?.copyMemory(from: data, byteCount: Int(first.mDataByteSize))
                }
            }
            return noErr
        }
    }

    func resume() {
        try? AVAudioSession.sharedInstance().setActive(true)
        if synth != nil && !engine.isRunning { try? engine.start() }
    }

    // MARK: - Per frame

    func update(engine press: PressEngine, context: FeedbackContext) {
        let now = CACurrentMediaTime()
        let dt = lastUpdate == 0 ? 1.0 / 60 : min(max(now - lastUpdate, 0), 0.1)
        lastUpdate = now
        // Schedules run even without a synth so the shared cue sync stays aligned with haptics.
        advanceSchedules(press, context: context, dt: dt)
        guard let synth else { return }

        let beds = Recipes.recipe(for: context.kind).beds
        let memory = CueBook.shared.memory
        let soft = style == .soft
        var params = BedParams()
        params.master = enabled ? Self.masterGain * volume : 0
        params.softAmount = soft ? 1 : 0

        let c = Float(press.measuredCompression)
        let speed = Float(clamp(press.closingSpeed / 120, 0, 1))
        if press.phase == .sealed && lastPhase != .sealed { spinDown = 0.4 }
        lastPhase = press.phase

        switch press.phase {
        case .armed, .pressing:
            // Hiss opens with closing speed; motor rises ~5 st under load (02 §7.2).
            if press.closingSpeed > 2 {
                params.hissGain = Self.smoothstep(0.05, 0.8, speed) * 0.045
            }
            params.hissCenter = 1500 * pow(4, speed)
            params.humGain = press.phase == .pressing ? 0.018 + 0.035 * c : 0.010
            params.humPitch = pow(2, (5 * c + speed) / 12)
            if press.isLoaded {
                let opening = press.closingSpeed < -5
                let progress = Recipes.strainProgress(c, kind: context.kind)
                // Procedural stick-slip creak: slips speed up with strain; sparse settling slips while held.
                params.creakPitch = beds.creakPitch * (1 + 0.25 * progress)
                params.creakRate = opening ? 0 : (press.isHolding ? 2.5 : 8 + 55 * progress * max(speed, 0.2))
                params.creakGain = beds.creakAmount * (0.012 + 0.03 * progress)
                // Material strain loop until the failure: gain = strain^1.5 · max(v, 0.25) (02 §7.2).
                let strain = beds.strain
                if !memory.hasFailed && !opening && !(soft && strain.isWet) {
                    params.strainGain = strain.gain * pow(progress, 1.5) * max(speed, press.isHolding ? 0.1 : 0.25)
                    params.strainCutoff = strain.cutoff * (1 + strain.cutoffRise * progress)
                    params.strainQ = strain.q
                    params.strainFilter = strain.filter
                    params.strainFlutterRate = strain.flutterRate
                    params.strainFlutterDepth = strain.flutterDepth
                }
                // Granular crush after the failure: rate = base · v · (fresh ? 1 : 0.25) (02 §7.2).
                let crush = beds.crush
                if memory.hasFailed && press.closingSpeed > 2 && !(soft && crush.isWet) {
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
            // Motor spins down over 400 ms after the seal (02 §7.1 phase 6).
            if spinDown > 0 {
                spinDown -= dt
                let fraction = Float(max(spinDown / 0.4, 0))
                params.humGain = 0.05 * fraction
                params.humPitch = 0.6 + 0.7 * fraction
            }
        case .idle, .revealing:
            break
        }
        synth.setBeds(params)
        updateGaugeTicks(press, failed: memory.hasFailed)
    }

    /// One tick per 5° of closing under load: the sensor's resolution turned into a feature (02 §3.1).
    private func updateGaugeTicks(_ press: PressEngine, failed: Bool) {
        guard press.isLoaded, press.closingSpeed > 0 else {
            if press.closingSpeed < -5 || press.phase != .pressing { lastTickAngle = nil }
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
            // After the failure the needle has dropped: the ticks continue, quieter, so the climax keeps its contrast.
            play(BrandCues.tick(scale[step], gain: failed ? 0.6 : 1))
        }
    }

    /// Micro-cracks during the tell and settling creaks while held, in lockstep with the haptics.
    private func advanceSchedules(_ press: PressEngine, context: FeedbackContext, dt: Double) {
        if tell.isRunning {
            if !press.isLoaded || press.closingSpeed < -5 {
                tell.stop()
            } else if let index = tell.advance(by: dt * (press.isHolding ? 0.35 : 1)) {
                play(CueBook.shared.cue(for: .recipe(.microCrack(index: index)), context: context, consumer: .audio))
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
            play(CueBook.shared.cue(for: .settle(index), context: context, consumer: .audio))
        }
    }

    // MARK: - Events

    func handle(_ event: PressEvent, context: FeedbackContext) {
        let recipeCue = RecipeMoment(event).map {
            CueBook.shared.cue(for: .recipe($0), context: context, consumer: .audio)
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
        perform(event, recipeCue: recipeCue)
    }

    func place(context: FeedbackContext) {
        tell.stop()
        settle.stop()
        lastTickAngle = nil
        grainCount = 0
        play(CueBook.shared.cue(for: .recipe(.place), context: context, consumer: .audio))
    }

    func collect() {
        play(BrandCues.collect)
    }

    func unlock() {
        play(BrandCues.unlock)
    }

    /// Tuning Lab: plays one moment of an object's recipe plus the shared layers, outside the live press.
    /// `golden`/`surprise` only matter for `.reveal`.
    func audition(_ kind: ObjectKind, event: PressEvent, golden: Bool = false, surprise: Surprise? = nil) {
        let context = Audition.context(for: kind, event: event, golden: golden, surprise: surprise)
        let recipeCue = RecipeMoment(event).map { CueBook.preview($0, context: context, dice: auditionDice) }
        perform(event, recipeCue: recipeCue)
    }

    /// Tuning Lab: audition the object's placement plop.
    func auditionPlace(_ kind: ObjectKind) {
        let context = Audition.context(for: kind, event: .armed)
        play(CueBook.preview(.place, context: context, dice: auditionDice))
    }

    private func perform(_ event: PressEvent, recipeCue: FeedbackCue?) {
        var playRecipe = true
        switch event {
        case .armed, .sealed, .preFailureTell:
            break
        case .contact:
            play(BrandCues.contact)
        case .grain:
            // Soft style: half grain density (bible §8).
            grainCount += 1
            if style == .soft && grainCount % 2 == 0 { playRecipe = false }
        case .hush:
            if enabled { synth?.trigger(.hush(duration: 0.07)) }
        case .fracture(_, let isFailure):
            if isFailure { play(BrandCues.tonic) }
        case .bottomOut:
            play(BrandCues.bottomOut)
        case .kaChunk:
            play(BrandCues.kaChunk)
        case .released:
            play(BrandCues.releaseSigh)
        case .reveal:
            play(BrandCues.releaseSigh)
            play(BrandCues.sting)
        }
        if playRecipe, let recipeCue {
            play(recipeCue)
        }
    }

    private func play(_ cue: FeedbackCue) {
        guard enabled, let synth, !cue.sounds.isEmpty else { return }
        for layer in cue.styled(style).sounds {
            if let bank = sampleBank, bank.play(layer) { continue }
            synth.trigger(layer.command)
        }
    }

    private static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
