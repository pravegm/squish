import AVFoundation
import QuartzCore
import UIKit

/// Owns the audio session and engine and turns press events into synthesised sound (bible §8).
/// Shared press layers (hiss, motor, creak, gauge ticks, hush, bottom-out, ka-chunk, sting, chime, fanfare) live here
/// and in `BrandCues`; each object's material sounds come from its recipe through `CueBook`.
///
/// Gain staging (target ≈ −16 LUFS integrated, 02 §6): beds sit around −30 dBFS before the master, grains −30…−20,
/// fractures −12…−8, failures and the ka-chunk peak into the −1 dBFS limiter, about 6 LU above the strain bed.
/// The master gain (`AudioMix.masterGain`) brings the whole press up to the target on a phone speaker.
///
/// Session: `.playback` + `.mixWithOthers` unless the user turns off "Play sound when the phone is on silent"
/// (see `AudioSessionChoice` for why). The engine is self-healing: route changes, interruptions, media-services
/// resets, scene changes (the Duo's inner ↔ outer display) and a stopped engine noticed in `update` all restart it.
/// Nothing here depends on the inner render gate: the blind clock keeps calling `update` while the phone is shut.
@MainActor
final class AudioController {
    var enabled = true
    var style: SoundStyle = .workshop
    /// Extra trim for the Tuning Lab.
    var volume: Float = 1
    /// "Play sound when the phone is on silent" (Settings → Sound). Changing it re-applies the session category.
    var playsInSilentMode = true {
        didSet {
            guard oldValue != playsInSilentMode, isStarted else { return }
            configureSession()
            ensureRunning(reason: "silent-mode setting changed")
        }
    }
    /// The hinge outside the press (creak), set by the director every frame before `update` (`HingeFeel`).
    var hinge = HingeBed.still
    /// Sampled-layer seam (bible §15.1). Nil in v1: everything is synthesised.
    var sampleBank: (any SampleBank)?

    private var engine = AVAudioEngine()
    private var synth: Synth?
    private var sourceNode: AVAudioSourceNode?
    private var observers: [NSObjectProtocol] = []
    private var engineObserver: NSObjectProtocol?
    private var isStarted = false
    private var lastRecoveryAttempt: CFTimeInterval = 0
    // Diagnostics (Tuning Lab): Release builds have no console.
    private(set) var lastError: String?
    private(set) var lastEvent = "Not started"
    private(set) var engineStarts = 0
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

    /// Called once at launch, before the first press can happen (PressDirector.start, from RootView.onAppear), on
    /// every device and in Release: nothing here is DEBUG-only, and the P-48 and the Fold Press share it.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        configureSession()
        activateSession()
        buildGraph()
        startEngine(reason: "launch")

        let center = NotificationCenter.default
        // Calls, Siri and alarms interrupt the session; pick up again when they end. Mixable sessions are rarely
        // interrupted, but when they are, the engine stops.
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil,
                                            queue: .main) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let ended = raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .ended
            MainActor.assumeIsolated {
                guard let self else { return }
                if ended {
                    self.lastEvent = "Interruption ended"
                    self.resume()
                } else {
                    self.lastEvent = "Interrupted (call, Siri or alarm)"
                }
            }
        })
        // Headphones in or out, AirPods, AirPlay: the engine may stop; restart it.
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.ensureRunning(reason: "output route changed")
            }
        })
        // The audio server restarted: every audio object is dead. Rebuild from scratch.
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.rebuildAfterMediaReset()
            }
        })
    }

    /// Category and hints. Preferences are hints only (QA1631); the graph reads back the real rate.
    private func configureSession() {
        let choice = AudioSessionChoice.forSettings(playsInSilentMode: playsInSilentMode)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(choice.category, mode: choice.mode, options: choice.options)
        } catch {
            record("Couldn't set the audio category", error)
        }
        try? session.setPreferredSampleRate(48_000)
        try? session.setPreferredIOBufferDuration(0.005)
    }

    private func activateSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            record("Couldn't switch the audio session on", error)
        }
    }

    /// Source node → main mixer → output. The node renders mono Float32 at the session's (hardware) rate, 48 kHz on
    /// iPhone; the mixer converts if the route later runs at another rate (Bluetooth), so the graph never needs
    /// rewiring for a rate change.
    private func buildGraph() {
        let session = AVAudioSession.sharedInstance()
        let sampleRate = session.sampleRate > 0 ? session.sampleRate : 48_000
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            lastError = "Couldn't make a \(Int(sampleRate)) Hz audio format"
            return
        }
        let synth = Synth(sampleRate: Float(sampleRate))
        let node = AVAudioSourceNode(format: format, renderBlock: Self.renderBlock(for: synth))
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1
        engine.prepare()
        self.synth = synth
        sourceNode = node

        // A hardware change (rate, channels) stops the engine and posts this; the connections survive, so restart.
        if let engineObserver { NotificationCenter.default.removeObserver(engineObserver) }
        engineObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.ensureRunning(reason: "audio hardware changed")
            }
        }
    }

    private func startEngine(reason: String) {
        guard sourceNode != nil else { return }
        do {
            try engine.start()
            engineStarts += 1
            lastEvent = "Engine started (\(reason))"
        } catch {
            record("Couldn't start the audio engine (\(reason))", error)
        }
    }

    private func rebuildAfterMediaReset() {
        guard isStarted else { return }
        lastEvent = "Audio services reset: rebuilding"
        // The old engine is dead: don't touch it, just let it go.
        engine = AVAudioEngine()
        synth = nil
        sourceNode = nil
        configureSession()
        activateSession()
        buildGraph()
        startEngine(reason: "after audio services reset")
    }

    /// Restart the engine if anything stopped it. Cheap when it's running.
    private func ensureRunning(reason: String) {
        guard isStarted, synth != nil, !engine.isRunning else { return }
        activateSession()
        startEngine(reason: reason)
    }

    private func record(_ what: String, _ error: Error) {
        let nsError = error as NSError
        lastError = "\(what): \(nsError.localizedDescription) (code \(nsError.code))"
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

    /// The scene became active again (launch, unlock, back from another app, or the Duo moving between its displays).
    func resume() {
        guard isStarted else { return }
        activateSession()
        if synth != nil && !engine.isRunning { startEngine(reason: "app active again") }
    }

    // MARK: - Per frame

    func update(engine press: PressEngine, context: FeedbackContext) {
        let now = CACurrentMediaTime()
        let dt = lastUpdate == 0 ? 1.0 / 60 : min(max(now - lastUpdate, 0), 0.1)
        lastUpdate = now
        // Self-heal: a stopped engine is noticed within a second while the app is on screen (either display).
        if isStarted, synth != nil, !engine.isRunning, now - lastRecoveryAttempt > 1,
           UIApplication.shared.applicationState != .background {
            lastRecoveryAttempt = now
            ensureRunning(reason: "found stopped")
        }
        // Schedules run even without a synth so the shared cue sync stays aligned with haptics.
        advanceSchedules(press, context: context, dt: dt)
        guard let synth else { return }

        let beds = Recipes.recipe(for: context.kind).beds
        let memory = CueBook.shared.memory
        let soft = style == .soft
        var params = BedParams()
        params.master = enabled ? AudioMix.masterGain * volume : 0
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
        // The hinge creak when the press isn't loaded (under load the press creak owns the resonators).
        if !press.isLoaded && hinge.creakGain > 0 {
            params.creakRate = hinge.creakRate
            params.creakGain = hinge.creakGain
            params.creakPitch = hinge.creakPitch
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
        // The held press's settling creaks come from the engine (`PressBeat.creak`, played by the director).
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

    // MARK: - Diagnostics (Tuning Lab)

    /// "Test sound": the contact thock and the reveal sting, about 0.6 s. Restarts the engine first if it stopped.
    func playTestSound() {
        testCue(BrandCues.contact.adding(BrandCues.sting.delayed(by: 0.15)), name: "Test sound")
    }

    /// "Test full press feel": the sound half of `PressFeelDemo` (the haptics controller plays the touch half).
    func playPressFeel(_ cue: FeedbackCue) {
        testCue(cue, name: "Press feel test")
    }

    private func testCue(_ cue: FeedbackCue, name: String) {
        if !isStarted { start() }
        ensureRunning(reason: name.lowercased())
        guard enabled else {
            lastEvent = "\(name) not played: Sound is off in Settings"
            return
        }
        play(cue)
        lastEvent = engine.isRunning ? "\(name) played" : "\(name) not played: the engine isn't running"
    }

    func diagnosticRows() -> [DiagnosticRow] {
        let session = AVAudioSession.sharedInstance()
        let respects = session.category == .ambient || session.category == .soloAmbient
        let outputs = session.currentRoute.outputs
        let route = outputs.isEmpty ? "None" : outputs.map { "\(Self.describe($0.portType)) (\($0.portName))" }
            .joined(separator: ", ")
        let onReceiver = outputs.contains { $0.portType == .builtInReceiver }
        let stats = synth?.renderStats ?? Synth.RenderStats()
        let hardwareRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let synthRate = synth.map { Double($0.sampleRate) } ?? 0
        let running = engine.isRunning
        return [
            DiagnosticRow(title: "Sound setting", value: enabled ? "On" : "Off (Settings → Sound)", isWarning: !enabled),
            DiagnosticRow(title: "Play on silent setting", value: playsInSilentMode ? "On" : "Off"),
            DiagnosticRow(title: "Audio category", value: AudioSessionChoice.describe(session.category)),
            DiagnosticRow(title: "Category options", value: AudioSessionChoice.describe(session.categoryOptions)),
            DiagnosticRow(title: "Silent switch respected?",
                          value: respects ? "Yes: silent mode mutes Squish" : "No: Squish plays on silent",
                          isWarning: respects),
            DiagnosticRow(title: "Output route", value: route, isWarning: outputs.isEmpty || onReceiver),
            DiagnosticRow(title: "Output volume", value: "\(Int((session.outputVolume * 100).rounded())) %",
                          isWarning: session.outputVolume < 0.05),
            DiagnosticRow(title: "Other app playing audio", value: DiagnosticRow.yesNo(session.isOtherAudioPlaying)),
            DiagnosticRow(title: "Audio engine running", value: DiagnosticRow.yesNo(running), isWarning: !running),
            DiagnosticRow(title: "Engine starts", value: "\(engineStarts)"),
            DiagnosticRow(title: "Render callbacks", value: "\(stats.callbacks) (climbs while audio flows)",
                          isWarning: stats.callbacks == 0),
            DiagnosticRow(title: "Output level now", value: AudioMix.decibels(stats.recentPeak)),
            DiagnosticRow(title: "Loudest so far", value: AudioMix.decibels(stats.maxPeak)),
            DiagnosticRow(title: "Sample rate",
                          value: String(format: "session %.0f Hz · output %.0f Hz · synth %.0f Hz", session.sampleRate,
                                        hardwareRate, synthRate),
                          isWarning: synthRate == 0),
            DiagnosticRow(title: "Buffer and latency",
                          value: String(format: "%.1f ms buffer · %.1f ms output latency", session.ioBufferDuration * 1000,
                                        session.outputLatency * 1000)),
            DiagnosticRow(title: "Master gain", value: String(format: "%.2f × trim %.2f", AudioMix.masterGain, volume)),
            DiagnosticRow(title: "Last audio event", value: lastEvent),
            DiagnosticRow(title: "Last audio error", value: lastError ?? "None", isWarning: lastError != nil),
        ]
    }

    private static func describe(_ port: AVAudioSession.Port) -> String {
        switch port {
        case .builtInSpeaker: "iPhone speaker"
        case .builtInReceiver: "Earpiece (very quiet)"
        case .headphones: "Wired headphones"
        case .bluetoothA2DP: "Bluetooth"
        case .bluetoothLE: "Bluetooth LE"
        case .bluetoothHFP: "Bluetooth (call quality)"
        case .airPlay: "AirPlay"
        case .HDMI: "HDMI"
        case .usbAudio: "USB audio"
        case .carAudio: "CarPlay"
        case .lineOut: "Line out"
        default: port.rawValue
        }
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
            play(BrandCues.unlatch)
            play(BrandCues.releaseSigh)
            play(BrandCues.sting)
        }
        if playRecipe, let recipeCue {
            play(recipeCue)
        }
    }

    /// A cue built once by the director and handed to both controllers in the same frame (hinge moments, pokes).
    func playShared(_ cue: FeedbackCue) {
        play(cue)
    }

    /// Break part 2, the hit stop (`PressBeat.hitStop`): keep everything ducked until the burst, so the failure
    /// lands on silence (the `.hush` event's own duck is only 70 ms).
    func holdSilence(for seconds: Double) {
        tell.stop()
        if enabled { synth?.trigger(.hush(duration: Float(max(seconds, 0)))) }
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
