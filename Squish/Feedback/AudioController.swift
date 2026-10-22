import AVFoundation
import QuartzCore

/// Owns the audio session and engine and turns press events into synth sounds (bible §8).
/// Brand sounds (ticks, ka-chunk, sting, chime) are fixed and all sit on one C major pentatonic.
@MainActor
final class AudioController {
    var enabled = true
    var volume: Float = 1

    private let engine = AVAudioEngine()
    private var synth: Synth?
    private var sourceNode: AVAudioSourceNode?
    private var configObserver: NSObjectProtocol?
    private var lastTickAngle: Double?
    private var hushUntil: CFTimeInterval = 0
    private var rng = SystemRandomNumberGenerator()

    /// C major pentatonic from C5: the gauge ticks climb this as pressure builds.
    private static let pentatonic: [Float] = [523.25, 587.33, 659.25, 783.99, 880.0, 1046.5, 1174.66, 1318.51, 1567.98, 1760.0, 2093.0]

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
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList -> OSStatus in
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
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        try? engine.start()
        self.synth = synth
        sourceNode = node

        // Route changes (headphones in/out) can stop the engine; restart it.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.engine.isRunning else { return }
                try? self.engine.start()
            }
        }
    }

    func resume() {
        try? AVAudioSession.sharedInstance().setActive(true)
        if !engine.isRunning { try? engine.start() }
    }

    // MARK: - Per frame

    func update(engine press: PressEngine) {
        guard let synth else { return }
        var beds = BedParams()
        beds.master = enabled ? 0.9 * volume : 0
        let now = CACurrentMediaTime()
        let ducked: Float = now < hushUntil ? 0.25 : 1
        let speed = Float(clamp(press.closingSpeed / 120, 0, 1))
        switch press.phase {
        case .armed, .pressing:
            let c = Float(press.measuredCompression)
            beds.hissGain = press.closingSpeed > 2 ? speed * speed * (3 - 2 * speed) * 0.05 * ducked : 0
            beds.hissCenter = 1500 * pow(4, speed)
            beds.humGain = (press.phase == .pressing ? 0.02 + 0.04 * c : 0.012) * ducked
            beds.humPitch = 1 + 0.33 * c + 0.06 * speed
        case .sealed, .idle, .revealing:
            break
        }
        synth.setBeds(beds)
        updateGaugeTicks(press)
    }

    /// One tick per 5° of closing under load: the sensor's resolution turned into a feature.
    private func updateGaugeTicks(_ press: PressEngine) {
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
            let step = min(Int(press.measuredCompression * 10), Self.pentatonic.count - 1)
            tick(Self.pentatonic[step])
        }
    }

    // MARK: - Events

    func handle(_ event: PressEvent, kind: ObjectKind) {
        switch event {
        case .armed, .preFailureTell, .sealed:
            break
        case .contact:
            play(.tone(start: 160, end: 90, glide: 0.06, duration: 0.10, attack: 0.002, gain: 0.35,
                       harmonics: 2, vibratoRate: 0, vibratoDepth: 0, delay: 0))
            play(.noise(center: 700, q: 1, attack: 0.001, decay: 0.03, gain: 0.15, delay: 0))
        case .grain(let c):
            grain(kind: kind, compression: Float(c))
        case .hush:
            hushUntil = CACurrentMediaTime() + 0.06
        case .fracture(let index, let isFailure):
            fracture(kind: kind, index: index, isFailure: isFailure)
        case .bottomOut:
            play(.tone(start: 95, end: 45, glide: 0.12, duration: 0.18, attack: 0.002, gain: 0.45,
                       harmonics: 2, vibratoRate: 0, vibratoDepth: 0, delay: 0))
        case .kaChunk:
            // Fixed brand sound: low thock + latch click + short metallic body.
            play(.tone(start: 120, end: 38, glide: 0.15, duration: 0.30, attack: 0.001, gain: 0.8,
                       harmonics: 2, vibratoRate: 0, vibratoDepth: 0, delay: 0))
            play(.noise(center: 3200, q: 2, attack: 0.0005, decay: 0.006, gain: 0.4, delay: 0.02))
            play(.noise(center: 900, q: 3, attack: 0.001, decay: 0.07, gain: 0.3, delay: 0.03))
        case .released:
            play(.noise(center: 2500, q: 0.7, attack: 0.08, decay: 0.2, gain: 0.06, delay: 0))
            if kind == .rubberDuck {
                squeak(pitch: 700, gain: 0.08)
            }
        case .reveal:
            sting()
        }
    }

    func place(_ kind: ObjectKind) {
        play(.tone(start: 220, end: 120, glide: 0.06, duration: 0.09, attack: 0.002, gain: 0.3,
                   harmonics: 1, vibratoRate: 0, vibratoDepth: 0, delay: 0))
        play(.noise(center: kind == .bubbleWrap ? 3000 : 500, q: 1, attack: 0.001, decay: 0.04, gain: 0.12, delay: 0))
    }

    /// Fixed two-note answer to the reveal sting.
    func collect() {
        note(783.99, at: 0, gain: 0.16)
        note(1046.5, at: 0.12, gain: 0.18)
    }

    private func grain(kind: ObjectKind, compression c: Float) {
        switch kind {
        case .bubbleWrap:
            play(.noise(center: 6000 + Float.random(in: -800...800, using: &rng), q: 0.8,
                        attack: 0.0005, decay: 0.008, gain: 0.05, delay: 0))
        case .rubberDuck:
            squeak(pitch: 850 + 500 * c, gain: 0.12)
        }
    }

    private func fracture(kind: ObjectKind, index: Int, isFailure: Bool) {
        switch kind {
        case .bubbleWrap:
            // Transient snap + band-passed body + tiny low "tock": three layers, randomised every time.
            let center = 1300 * Float.random(in: 0.75...1.3, using: &rng)
            play(.noise(center: 5200, q: 1.2, attack: 0.0003, decay: 0.004, gain: 0.25, delay: 0))
            play(.noise(center: center, q: 1.5, attack: 0.0005, decay: 0.018, gain: 0.5, delay: 0.001))
            play(.tone(start: 220, end: 120, glide: 0.03, duration: 0.04, attack: 0.001, gain: 0.12,
                       harmonics: 1, vibratoRate: 0, vibratoDepth: 0, delay: 0.002))
        case .rubberDuck:
            if isFailure {
                // Seam pop, comic "bloop" and an air rush. Never a pained squeal.
                play(.noise(center: 900, q: 1.2, attack: 0.0005, decay: 0.05, gain: 0.5, delay: 0))
                play(.tone(start: 700, end: 140, glide: 0.12, duration: 0.14, attack: 0.002, gain: 0.25,
                           harmonics: 1, vibratoRate: 0, vibratoDepth: 0, delay: 0.01))
                play(.noise(center: 4000, q: 0.7, attack: 0.01, decay: 0.25, gain: 0.08, delay: 0.02))
            } else {
                // Comic honk.
                play(.tone(start: 330, end: 300, glide: 0.25, duration: 0.25, attack: 0.01, gain: 0.16,
                           harmonics: 6, vibratoRate: 6, vibratoDepth: 0.01, delay: 0))
            }
        }
    }

    private func squeak(pitch: Float, gain: Float) {
        let p = pitch * Float.random(in: 0.97...1.03, using: &rng)
        play(.tone(start: p, end: p * 1.25, glide: 0.12, duration: 0.16, attack: 0.01, gain: gain,
                   harmonics: 3, vibratoRate: 28, vibratoDepth: 0.02, delay: 0))
    }

    private func tick(_ frequency: Float) {
        play(.noise(center: 4000, q: 1.5, attack: 0.0003, decay: 0.002, gain: 0.08, delay: 0))
        play(.tone(start: frequency, end: frequency, glide: 0.01, duration: 0.06, attack: 0.001, gain: 0.07,
                   harmonics: 1, vibratoRate: 0, vibratoDepth: 0, delay: 0))
    }

    /// Fixed reveal sting: C5 E5 G5.
    private func sting() {
        note(523.25, at: 0, gain: 0.18)
        note(659.25, at: 0.16, gain: 0.18)
        note(783.99, at: 0.32, gain: 0.2)
    }

    /// Soft marimba-ish note: fundamental plus a quick 4× partial.
    private func note(_ frequency: Float, at delay: Float, gain: Float) {
        play(.tone(start: frequency, end: frequency, glide: 0.01, duration: 0.6, attack: 0.004, gain: gain,
                   harmonics: 2, vibratoRate: 0, vibratoDepth: 0, delay: delay))
        play(.tone(start: frequency * 4, end: frequency * 4, glide: 0.01, duration: 0.08, attack: 0.001, gain: gain * 0.2,
                   harmonics: 1, vibratoRate: 0, vibratoDepth: 0, delay: delay))
    }

    private func play(_ command: SynthCommand) {
        guard enabled, let synth else { return }
        synth.trigger(command)
    }
}
