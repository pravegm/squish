import Foundation
import os

// MARK: - Commands (main thread → audio thread)

/// Filter shape for noise layers. The state-variable filter gives all three from one structure.
enum NoiseFilter: Sendable, Equatable {
    case lowPass, bandPass, highPass
}

/// Partial tables for the modal resonator (02 §3.2 item 4: 8–12 modes give a coherent ring for almost no CPU).
enum RingMode: Sendable, Equatable {
    /// Thin aluminium shell (soda can): dense, slightly inharmonic.
    case metal
    /// Glass bottle: sparse, bright, quick.
    case glass
    /// Thick steel bar / press frame (free-free beam ratios).
    case steel
    /// Wax / wood block: short and woody.
    case wood
    /// Small bell (golden shimmer, brand flourishes).
    case bell
}

/// A one-shot filtered-noise burst: pops, snaps, cracks, puffs, hiss sweeps.
struct NoiseSpec: Sendable, Equatable {
    var filter: NoiseFilter
    /// Centre (band-pass) or corner (low/high-pass) frequency, Hz.
    var cutoff: Float
    /// Cutoff at the end of the sweep; equal to `cutoff` for no sweep.
    var cutoffEnd: Float
    var sweepTime: Float
    var q: Float
    var attack: Float
    /// Exponential decay time constant, seconds.
    var decay: Float
    var gain: Float
    var delay: Float
}

/// A pitched tone with a glide, vibrato and a 1/n harmonic stack: squeaks, honks, thumps, brand notes.
struct ToneSpec: Sendable, Equatable {
    var start: Float
    var end: Float
    var glide: Float
    var duration: Float
    var attack: Float
    /// Exponential decay time constant after the attack.
    var decay: Float
    var gain: Float
    var harmonics: Int
    var vibratoRate: Float
    var vibratoDepth: Float
    var delay: Float
}

/// A struck modal resonator: `partials` decaying sinusoids (1…12).
/// Partials landing in 2.5–4.5 kHz decay 4× faster, so no ring can become a sustained screech (02 §1.2).
struct RingSpec: Sendable, Equatable {
    var mode: RingMode
    var fundamental: Float
    var partials: Int
    /// Decay time constant of the fundamental; higher partials decay faster.
    var decay: Float
    /// Amplitude roll-off per partial, 0…1 (higher = brighter).
    var brightness: Float
    var gain: Float
    var delay: Float
    /// Seeds the ±2 % partial detune, so two rings of one material never sound identical.
    var seed: UInt32
}

/// A granular burst: dense micro noise-grains with random band-pass centres (crunch, crumble, shard scatter, fizz).
struct CrunchSpec: Sendable, Equatable {
    var duration: Float
    /// Grains per second at the start and the end of the burst.
    var rate: Float
    var rateEnd: Float
    /// Band-pass centre range, sampled log-uniformly per grain.
    var low: Float
    var high: Float
    var q: Float
    /// Decay time constant of each grain.
    var grainDecay: Float
    var gain: Float
    /// Gain multiplier reached at the end of the burst (falling density/level).
    var gainEnd: Float
    var delay: Float
}

/// Decoded mono Float32 PCM owned by `SampleLibrary` for the life of the app (never freed, never mutated after load),
/// so the audio thread can read it without ARC or locks.
struct SampleData: @unchecked Sendable, Equatable {
    let samples: UnsafePointer<Float>
    let count: Int
    let sampleRate: Float
}

/// One recorded sample, played as a synth voice (same master, limiter, hush and timing as everything else).
struct SampleSpec: Sendable, Equatable {
    var data: SampleData
    /// Playback rate: 1 = original pitch; 2^(st/12) for a pitch shift (varispeed, like tape).
    var rate: Float
    var gain: Float
    var delay: Float
}

enum SynthCommand: Sendable, Equatable {
    case noise(NoiseSpec)
    case tone(ToneSpec)
    case ring(RingSpec)
    case crunch(CrunchSpec)
    case sample(SampleSpec)
    /// Ducks everything already sounding (beds and voices) by −12 dB for `duration` (bible §3.1 beat 6).
    /// Voices started after the hush play at full level, so the failure lands on silence.
    case hush(duration: Float)

    /// Peak gain parameter (0 for `hush`). Used by tests and the sample-bank seam.
    var gain: Float {
        switch self {
        case .noise(let spec): spec.gain
        case .tone(let spec): spec.gain
        case .ring(let spec): spec.gain
        case .crunch(let spec): spec.gain
        case .sample(let spec): spec.gain
        case .hush: 0
        }
    }

    var delay: Float {
        switch self {
        case .noise(let spec): spec.delay
        case .tone(let spec): spec.delay
        case .ring(let spec): spec.delay
        case .crunch(let spec): spec.delay
        case .sample(let spec): spec.delay
        case .hush: 0
        }
    }

    /// The same command, starting `seconds` later (never before "now"). `hush` has no delay and is returned as is.
    func delayed(by seconds: Float) -> SynthCommand {
        switch self {
        case .noise(var spec): spec.delay = max(spec.delay + seconds, 0); return .noise(spec)
        case .tone(var spec): spec.delay = max(spec.delay + seconds, 0); return .tone(spec)
        case .ring(var spec): spec.delay = max(spec.delay + seconds, 0); return .ring(spec)
        case .crunch(var spec): spec.delay = max(spec.delay + seconds, 0); return .crunch(spec)
        case .sample(var spec): spec.delay = max(spec.delay + seconds, 0); return .sample(spec)
        case .hush: return self
        }
    }

    func scaled(_ factor: Float) -> SynthCommand {
        switch self {
        case .noise(var spec): spec.gain *= factor; return .noise(spec)
        case .tone(var spec): spec.gain *= factor; return .tone(spec)
        case .ring(var spec): spec.gain *= factor; return .ring(spec)
        case .crunch(var spec): spec.gain *= factor; return .crunch(spec)
        case .sample(var spec): spec.gain *= factor; return .sample(spec)
        case .hush: return self
        }
    }

    /// Soft style (bible §8, 02 §6): half grain density and a gentler, darker crunch.
    var softened: SynthCommand {
        switch self {
        case .crunch(var spec):
            spec.rate *= 0.5
            spec.rateEnd *= 0.5
            spec.gain *= 0.75
            spec.high = min(spec.high, 5000)
            spec.low = min(spec.low, spec.high)
            return .crunch(spec)
        case .noise, .tone, .ring, .sample, .hush:
            return self
        }
    }
}

/// Continuous layers, set from the main thread every frame and smoothed per sample on the audio thread.
struct BedParams: Sendable {
    // Press bed (02 §4): pneumatic hiss, two-partial motor hum, procedural stick-slip creak.
    var hissGain: Float = 0
    var hissCenter: Float = 1500
    var humGain: Float = 0
    var humPitch: Float = 1
    /// Stick-slip events per second; their resonance gives the creak its pitch.
    var creakRate: Float = 0
    var creakGain: Float = 0
    var creakPitch: Float = 1
    // Material bed: strain loop (filtered noise with flutter) and the post-failure granular crush/squelch.
    var strainGain: Float = 0
    var strainCutoff: Float = 800
    var strainQ: Float = 1
    var strainFilter: NoiseFilter = .bandPass
    var strainFlutterRate: Float = 4
    var strainFlutterDepth: Float = 0
    var crushRate: Float = 0
    var crushGain: Float = 0
    var crushLow: Float = 500
    var crushHigh: Float = 4000
    var crushQ: Float = 1.2
    var crushGrainDecay: Float = 0.004
    // Recorded strain or crush loop (SOUND-2 §5.1 item 3): nil = none. Its gain and rate follow the press.
    var loop: SampleData? = nil
    var loopGain: Float = 0
    var loopRate: Float = 1
    // Master.
    var master: Float = 0.8
    /// 1 on the built-in speaker: a low-mid lift and a protective high-pass (the Duo speaker is thin and quiet).
    var speakerEQ: Float = 0
    /// 0 = Workshop, 1 = Soft (master low-pass at 6 kHz, bible §8).
    var softAmount: Float = 0

    /// Per-sample one-pole smoothing towards `target` (no zipper noise).
    /// The strain loop falls slowly (150 ms, 02 §7.1 reversal) and rises fast (~25 ms).
    mutating func approach(_ target: BedParams, fast: Float, slow: Float) {
        hissGain += (target.hissGain - hissGain) * fast
        hissCenter += (target.hissCenter - hissCenter) * fast
        humGain += (target.humGain - humGain) * fast
        humPitch += (target.humPitch - humPitch) * fast
        creakRate += (target.creakRate - creakRate) * fast
        creakGain += (target.creakGain - creakGain) * fast
        creakPitch += (target.creakPitch - creakPitch) * slow
        strainGain += (target.strainGain - strainGain) * (target.strainGain < strainGain ? slow : fast)
        strainCutoff += (target.strainCutoff - strainCutoff) * fast
        strainQ = target.strainQ
        strainFilter = target.strainFilter
        strainFlutterRate = target.strainFlutterRate
        strainFlutterDepth += (target.strainFlutterDepth - strainFlutterDepth) * fast
        crushRate += (target.crushRate - crushRate) * fast
        crushGain += (target.crushGain - crushGain) * fast
        crushLow = target.crushLow
        crushHigh = target.crushHigh
        crushQ = target.crushQ
        crushGrainDecay = target.crushGrainDecay
        master += (target.master - master) * fast
        loop = target.loop
        loopGain += (target.loopGain - loopGain) * fast
        loopRate += (target.loopRate - loopRate) * slow
        speakerEQ += (target.speakerEQ - speakerEQ) * slow
        softAmount += (target.softAmount - softAmount) * slow
    }
}

// MARK: - DSP building blocks

/// Fixed-capacity command queue. Never allocates after init, so the audio thread can drain it safely.
private struct CommandRing {
    private var items: [SynthCommand]
    private var read = 0
    private var write = 0

    init(capacity: Int) {
        items = Array(repeating: .hush(duration: 0), count: capacity)
    }

    mutating func push(_ command: SynthCommand) {
        let next = (write + 1) % items.count
        guard next != read else { return } // full: drop rather than block
        items[write] = command
        write = next
    }

    mutating func pop() -> SynthCommand? {
        guard read != write else { return nil }
        let command = items[read]
        read = (read + 1) % items.count
        return command
    }
}

/// Topology-preserving state-variable filter (Zavalishin). Low-, band- and high-pass from one structure.
private struct SVF {
    var a1: Float = 0, a2: Float = 0, a3: Float = 0, k: Float = 1
    var ic1: Float = 0, ic2: Float = 0

    /// Retunes without clearing the state, so a sweep or a new grain never clicks.
    mutating func tune(cutoff: Float, q: Float, sampleRate: Float) {
        let f = min(max(cutoff, 20), sampleRate * 0.45)
        let g = tan(Float.pi * f / sampleRate)
        k = 1 / max(q, 0.1)
        a1 = 1 / (1 + g * (g + k))
        a2 = g * a1
        a3 = g * a2
    }

    mutating func reset() {
        ic1 = 0
        ic2 = 0
    }

    /// Band-pass is normalised to 0 dB at the centre, so a layer's `gain` reads the same at any Q.
    mutating func process(_ x: Float, _ mode: NoiseFilter) -> Float {
        let v3 = x - ic2
        let v1 = a1 * ic1 + a2 * v3
        let v2 = ic2 + a2 * ic1 + a3 * v3
        ic1 = 2 * v1 - ic1
        ic2 = 2 * v2 - ic2
        switch mode {
        case .lowPass: return v2
        case .bandPass: return v1 * k
        case .highPass: return x - k * v1 - v2
        }
    }

    /// Un-normalised band-pass (peak gain = Q): a ringing resonator for the creak bank.
    mutating func resonate(_ x: Float) -> Float {
        let v3 = x - ic2
        let v1 = a1 * ic1 + a2 * v3
        let v2 = ic2 + a2 * ic1 + a3 * v3
        ic1 = 2 * v1 - ic1
        ic2 = 2 * v2 - ic2
        return v1
    }
}

/// Transposed direct form II biquad (RBJ cookbook), for the speaker EQ.
private struct Biquad {
    var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
    var z1: Float = 0, z2: Float = 0

    static func peaking(_ frequency: Float, gainDb: Float, q: Float, sampleRate: Float) -> Biquad {
        let a = pow(10, gainDb / 40)
        let w = 2 * Float.pi * frequency / sampleRate
        let alpha = sin(w) / (2 * q)
        let a0 = 1 + alpha / a
        return Biquad(b0: (1 + alpha * a) / a0, b1: -2 * cos(w) / a0, b2: (1 - alpha * a) / a0,
                      a1: -2 * cos(w) / a0, a2: (1 - alpha / a) / a0)
    }

    static func highPass(_ frequency: Float, q: Float, sampleRate: Float) -> Biquad {
        let w = 2 * Float.pi * frequency / sampleRate
        let alpha = sin(w) / (2 * q)
        let a0 = 1 + alpha
        return Biquad(b0: (1 + cos(w)) / 2 / a0, b1: -(1 + cos(w)) / a0, b2: (1 + cos(w)) / 2 / a0,
                      a1: -2 * cos(w) / a0, a2: (1 - alpha) / a0)
    }

    mutating func process(_ x: Float) -> Float {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }
}

private struct Voice {
    enum Kind { case noise, tone, ring, crunch, sample }
    var active = false
    var kind: Kind = .noise
    var ducked = false
    var delay = 0
    var age = 0
    var attack = 1
    var length = 0
    var decayRate: Float = 1
    var level: Float = 1
    var gain: Float = 0
    // Noise and crunch.
    var filter = SVF()
    var mode: NoiseFilter = .bandPass
    var q: Float = 1
    var cutoff: Float = 1000
    var cutoffEnd: Float = 1000
    var sweepSamples = 0
    // Tone.
    var phase: Float = 0
    var startFreq: Float = 0
    var endFreq: Float = 0
    var glide = 1
    var harmonics = 1
    var vibratoPhase: Float = 0
    var vibratoRate: Float = 0
    var vibratoDepth: Float = 0
    // Ring (state lives in the partial bank at this voice's slot).
    var partialCount = 0
    // Crunch.
    var total = 1
    var rate: Float = 0
    var rateEnd: Float = 0
    var low: Float = 500
    var high: Float = 4000
    var gainEnd: Float = 1
    var grainCountdown = 0
    var grainLevel: Float = 0
    var grainDecay: Float = 0
    // Sample.
    var sampleData: SampleData?
    var samplePosition: Double = 0
    var sampleStep: Double = 1
}

// MARK: - Synth

/// Real-time synth rendered inside an AVAudioSourceNode. Main thread → `trigger`/`setBeds`;
/// audio thread → `render`. Shared state crosses through two short unfair locks; the render path never allocates.
final class Synth: @unchecked Sendable {
    let sampleRate: Float

    static let voiceCount = 48
    static let maxPartials = 12
    private static let partialStride = 5 // re, im, cos, sin, decay
    /// Limiter ceiling: −1 dBFS (02 §6 loudness: −1 dBTP).
    private static let ceiling: Float = 0.89

    private static let metalRatios: [Float] = [1.0, 1.51, 1.97, 2.53, 3.11, 3.62, 4.28, 4.93, 5.57, 6.34, 7.12, 7.95]
    private static let glassRatios: [Float] = [1.0, 2.32, 2.89, 4.25, 5.03, 6.63, 7.41, 9.38, 10.2, 12.1, 13.6, 15.2]
    private static let steelRatios: [Float] = [1.0, 2.756, 5.404, 8.933, 13.34, 18.64, 24.81, 31.87, 39.81, 48.6, 58.3, 68.9]
    private static let woodRatios: [Float] = [1.0, 2.6, 3.9, 5.4, 6.9, 8.6, 10.4, 12.3, 14.1, 16.2, 18.3, 20.5]
    private static let bellRatios: [Float] = [1.0, 0.5, 1.183, 1.506, 2.0, 2.514, 2.662, 3.011, 4.166, 5.433, 6.796, 8.215]

    /// What the audio thread has actually produced, for the Tuning Lab diagnostics (Release builds have no console).
    struct RenderStats: Sendable {
        /// Render callbacks so far: if this stops climbing, the engine isn't pulling audio.
        var callbacks = 0
        /// Loudest sample in the last ~0.5 s (a decaying peak hold), linear.
        var recentPeak: Float = 0
        /// Loudest sample since launch, linear.
        var maxPeak: Float = 0
    }

    private let commands = OSAllocatedUnfairLock(uncheckedState: CommandRing(capacity: 256))
    private let bedParams = OSAllocatedUnfairLock(initialState: BedParams())
    private let stats = OSAllocatedUnfairLock(initialState: RenderStats())

    var renderStats: RenderStats { stats.withLock { $0 } }

    // Audio-thread-only state below.
    private var voices = [Voice](repeating: Voice(), count: Synth.voiceCount)
    private let bank: UnsafeMutablePointer<Float>
    private var noiseState: UInt32 = 0x1234_5678
    private var beds = BedParams()
    private var retuneCounter = 0

    private var hiss = SVF()
    private var humPhase1: Float = 0
    private var humPhase2: Float = 0
    private var creak1 = SVF()
    private var creak2 = SVF()
    private var creak3 = SVF()
    private var creakTunedPitch: Float = 0
    private var creakTension: Float = 0
    private var creakExcite: Float = 0
    private var strain = SVF()
    private var strainPhase: Float = 0
    private var crush = SVF()
    private var crushCountdown = 0
    private var crushLevel: Float = 0
    private var crushDecay: Float = 0.99
    private var duckSamples = 0
    private var duck: Float = 1
    private var lowPass1: Float = 0
    private var lowPass2: Float = 0
    private var limiterEnvelope: Float = 0
    private var loopPosition: Double = 0
    private var speakerLowMid = Biquad()
    private var speakerHighPass = Biquad()

    private let smoothFast: Float
    private let smoothSlow: Float
    private let duckDown: Float
    private let duckUp: Float
    private let lowPassCoefficient: Float
    private let limiterRelease: Float
    private let creakExciteDecay: Float
    /// `AudioMix.bedBus`, read once here so the audio thread never runs a global initialiser.
    private let bedBus: Float

    init(sampleRate: Float) {
        self.sampleRate = sampleRate
        bedBus = AudioMix.bedBus
        // Speaker profile (02 §3.3, SOUND-2): +4 dB at 300 Hz for body the small speaker can carry, and a 90 Hz
        // high-pass so the lows it can't play don't eat its excursion and headroom.
        speakerLowMid = Biquad.peaking(300, gainDb: 4, q: 0.9, sampleRate: sampleRate)
        speakerHighPass = Biquad.highPass(90, q: 0.707, sampleRate: sampleRate)
        smoothFast = 1 - exp(-1 / (0.025 * sampleRate))
        smoothSlow = 1 - exp(-1 / (0.15 * sampleRate))
        duckDown = 1 - exp(-1 / (0.006 * sampleRate))
        duckUp = 1 - exp(-1 / (0.12 * sampleRate))
        // Two cascaded one-poles at 6 kHz (bible §8 Soft style).
        lowPassCoefficient = 1 - exp(-2 * Float.pi * 6000 / sampleRate)
        limiterRelease = exp(-1 / (0.08 * sampleRate))
        creakExciteDecay = exp(-1 / (0.0015 * sampleRate))
        let capacity = Synth.voiceCount * Synth.maxPartials * Synth.partialStride
        bank = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        bank.initialize(repeating: 0, count: capacity)
        hiss.tune(cutoff: 1500, q: 0.8, sampleRate: sampleRate)
        strain.tune(cutoff: 800, q: 1, sampleRate: sampleRate)
        crush.tune(cutoff: 1500, q: 1.2, sampleRate: sampleRate)
        // Touch the lazily initialised tables here so the audio thread never runs their initialiser.
        _ = Synth.metalRatios.count + Synth.glassRatios.count + Synth.steelRatios.count
            + Synth.woodRatios.count + Synth.bellRatios.count
        _ = Synth.ceiling
    }

    deinit {
        bank.deallocate()
    }

    func trigger(_ command: SynthCommand) {
        commands.withLockUnchecked { $0.push(command) }
    }

    func setBeds(_ params: BedParams) {
        bedParams.withLock { $0 = params }
    }

    // MARK: - Audio thread

    func render(frames: Int, into out: UnsafeMutablePointer<Float>) {
        for _ in 0..<32 {
            guard let command = commands.withLockUnchecked({ $0.pop() }) else { break }
            start(command)
        }
        let target = bedParams.withLock { $0 }
        if target.loop != beds.loop {
            // A new loop (or none): start it from the top, fading in from silence.
            loopPosition = 0
            beds.loopGain = 0
        }
        var blockPeak: Float = 0
        defer {
            let peak = blockPeak
            let hold = exp(-Float(frames) / (0.5 * sampleRate))
            stats.withLockUnchecked { s in
                s.callbacks &+= 1
                s.recentPeak = max(peak, s.recentPeak * hold)
                s.maxPeak = max(s.maxPeak, peak)
            }
        }

        for frame in 0..<frames {
            beds.approach(target, fast: smoothFast, slow: smoothSlow)
            retuneCounter += 1
            if retuneCounter >= 64 {
                retuneCounter = 0
                retuneBeds()
            }

            if duckSamples > 0 {
                duckSamples -= 1
                duck += (0.25 - duck) * duckDown
            } else {
                duck += (1 - duck) * duckUp
            }

            var bed: Float = 0
            if beds.hissGain > 0.00005 {
                bed += hiss.process(nextNoise(), .bandPass) * beds.hissGain
            }
            if beds.humGain > 0.00005 {
                // 220 + 330 Hz implies a 110 Hz fundamental the phone speaker can't play (02 §4).
                humPhase1 += 2 * .pi * 220 * beds.humPitch / sampleRate
                humPhase2 += 2 * .pi * 330 * beds.humPitch / sampleRate
                if humPhase1 > 2 * .pi { humPhase1 -= 2 * .pi }
                if humPhase2 > 2 * .pi { humPhase2 -= 2 * .pi }
                bed += (sin(humPhase1) * 0.6 + sin(humPhase2) * 0.4) * beds.humGain
            }
            if beds.creakGain > 0.00005 {
                bed += renderCreak() * beds.creakGain
            }
            if beds.strainGain > 0.00005 {
                strainPhase += 2 * .pi * beds.strainFlutterRate / sampleRate
                if strainPhase > 2 * .pi { strainPhase -= 2 * .pi }
                let flutter = 1 - beds.strainFlutterDepth * 0.5 * (1 + sin(strainPhase))
                bed += strain.process(nextNoise(), beds.strainFilter) * beds.strainGain * flutter
            }
            if beds.crushRate > 0.5 || crushLevel > 0.0005 {
                bed += renderCrushBed()
            }

            var loopValue: Float = 0
            if let loop = beds.loop, beds.loopGain > 0.00005, loop.count > 1 {
                let index = Int(loopPosition)
                let a = loop.samples[index % loop.count]
                let b = loop.samples[(index + 1) % loop.count]
                loopValue = (a + (b - a) * Float(loopPosition - Double(index))) * beds.loopGain
                loopPosition += Double(beds.loopRate) * Double(loop.sampleRate) / Double(sampleRate)
                if loopPosition >= Double(loop.count) { loopPosition -= Double(loop.count) }
            }
            var sample = (bed * bedBus + loopValue) * duck
            for index in 0..<voices.count where voices[index].active {
                let value = renderVoice(&voices[index], slot: index)
                sample += voices[index].ducked ? value * duck : value
            }
            sample *= beds.master

            // Speaker profile, crossfaded in on the built-in speaker (the filters always run, so they never click).
            let shaped = speakerHighPass.process(speakerLowMid.process(sample))
            sample += (shaped - sample) * beds.speakerEQ

            // Soft style: crossfade into a 12 dB/oct low-pass at 6 kHz.
            lowPass1 += lowPassCoefficient * (sample - lowPass1)
            lowPass2 += lowPassCoefficient * (lowPass1 - lowPass2)
            sample += (lowPass2 - sample) * beds.softAmount

            // Peak limiter: instant attack, 80 ms release, so stacked climaxes never clip.
            let magnitude = abs(sample)
            limiterEnvelope = magnitude > limiterEnvelope ? magnitude : magnitude + (limiterEnvelope - magnitude) * limiterRelease
            if limiterEnvelope > Synth.ceiling {
                sample *= Synth.ceiling / limiterEnvelope
            }
            blockPeak = max(blockPeak, abs(sample))
            out[frame] = sample
        }
    }

    private func retuneBeds() {
        hiss.tune(cutoff: beds.hissCenter, q: 0.8, sampleRate: sampleRate)
        strain.tune(cutoff: beds.strainCutoff, q: beds.strainQ, sampleRate: sampleRate)
        crushDecay = exp(-1 / max(beds.crushGrainDecay * sampleRate, 1))
        if abs(beds.creakPitch - creakTunedPitch) > 0.005 {
            creakTunedPitch = beds.creakPitch
            // A small resonator bank (Farnell's creaking door, 02 §3.2 item 3), tinted like a steel press frame.
            creak1.tune(cutoff: 155 * creakTunedPitch, q: 12, sampleRate: sampleRate)
            creak2.tune(cutoff: 340 * creakTunedPitch, q: 14, sampleRate: sampleRate)
            creak3.tune(cutoff: 730 * creakTunedPitch, q: 16, sampleRate: sampleRate)
        }
    }

    /// Stick-slip: tension builds at `creakRate`, slips irregularly, and each slip excites the resonator bank.
    private func renderCreak() -> Float {
        creakTension += beds.creakRate / sampleRate * (0.6 + 0.8 * unitNoise())
        if creakTension >= 1 {
            creakTension = 0.2 * unitNoise()
            creakExcite = 0.6 + 0.4 * unitNoise()
        }
        let excitation = nextNoise() * creakExcite
        creakExcite *= creakExciteDecay
        return creak1.resonate(excitation) * 0.5 + creak2.resonate(excitation) * 0.35 + creak3.resonate(excitation) * 0.2
    }

    /// Continuous granular crunch/squelch after the failure: density follows closing speed (02 §7.1 phase 5).
    private func renderCrushBed() -> Float {
        if beds.crushRate > 0.5 {
            crushCountdown -= 1
            if crushCountdown <= 0 {
                let low = max(beds.crushLow, 40)
                let high = max(beds.crushHigh, low)
                crushLevel = 0.35 + 0.65 * unitNoise()
                crush.tune(cutoff: low * pow(high / low, unitNoise()), q: beds.crushQ, sampleRate: sampleRate)
                crushCountdown = Int(sampleRate / max(beds.crushRate, 1) * (0.25 + 1.5 * unitNoise())) + 1
            }
        }
        crushLevel *= crushDecay
        return crush.process(nextNoise(), .bandPass) * crushLevel * beds.crushGain
    }

    private func nextNoise() -> Float {
        noiseState ^= noiseState << 13
        noiseState ^= noiseState >> 17
        noiseState ^= noiseState << 5
        return Float(Int32(bitPattern: noiseState)) / Float(Int32.max)
    }

    private func unitNoise() -> Float {
        (nextNoise() + 1) * 0.5
    }

    private func start(_ command: SynthCommand) {
        if case let .hush(duration) = command {
            duckSamples = Int(duration * sampleRate)
            for index in voices.indices where voices[index].active {
                voices[index].ducked = true
            }
            return
        }
        var slot = voices.firstIndex { !$0.active }
        if slot == nil {
            // Steal the oldest voice.
            slot = voices.indices.max { voices[$0].age < voices[$1].age }
        }
        guard let slot else { return }
        var voice = Voice()
        voice.active = true
        switch command {
        case .noise(let spec):
            voice.kind = .noise
            voice.delay = Int(spec.delay * sampleRate)
            voice.attack = max(Int(spec.attack * sampleRate), 1)
            voice.decayRate = exp(-1 / max(spec.decay * sampleRate, 1))
            voice.length = voice.attack + Int(spec.decay * sampleRate * 7)
            voice.gain = spec.gain
            voice.mode = spec.filter
            voice.q = spec.q
            voice.cutoff = spec.cutoff
            voice.cutoffEnd = spec.cutoffEnd
            voice.sweepSamples = abs(spec.cutoffEnd - spec.cutoff) > 1 ? max(Int(spec.sweepTime * sampleRate), 1) : 0
            voice.filter.tune(cutoff: spec.cutoff, q: spec.q, sampleRate: sampleRate)
        case .tone(let spec):
            voice.kind = .tone
            voice.delay = Int(spec.delay * sampleRate)
            voice.attack = max(Int(spec.attack * sampleRate), 1)
            voice.length = max(Int(spec.duration * sampleRate), voice.attack + 1)
            voice.decayRate = exp(-1 / max(spec.decay * sampleRate, 1))
            voice.gain = spec.gain
            voice.startFreq = spec.start
            voice.endFreq = spec.end
            voice.glide = max(Int(spec.glide * sampleRate), 1)
            voice.harmonics = min(max(spec.harmonics, 1), 12)
            voice.vibratoRate = spec.vibratoRate
            voice.vibratoDepth = spec.vibratoDepth
        case .ring(let spec):
            voice.kind = .ring
            voice.delay = Int(spec.delay * sampleRate)
            voice.attack = max(Int(0.0005 * sampleRate), 1)
            voice.decayRate = 1
            voice.length = min(Int(spec.decay * sampleRate * 7), Int(sampleRate * 4))
            voice.gain = 1
            configureRing(spec, slot: slot, voice: &voice)
        case .sample(let spec):
            guard spec.data.count > 1 else { return }
            voice.kind = .sample
            voice.delay = Int(spec.delay * sampleRate)
            voice.attack = 1
            voice.decayRate = 1
            voice.gain = spec.gain
            voice.sampleData = spec.data
            voice.samplePosition = 0
            // Varispeed: the file's own rate against the device's, times the pitch.
            voice.sampleStep = Double(max(spec.rate, 0.05)) * Double(spec.data.sampleRate) / Double(sampleRate)
            voice.length = Int(Double(spec.data.count) / voice.sampleStep) + 2
        case .crunch(let spec):
            voice.kind = .crunch
            voice.delay = Int(spec.delay * sampleRate)
            voice.attack = 1
            voice.decayRate = 1
            voice.total = max(Int(spec.duration * sampleRate), 1)
            voice.length = voice.total + Int(spec.grainDecay * sampleRate * 7)
            voice.gain = spec.gain
            voice.gainEnd = spec.gainEnd
            voice.rate = spec.rate
            voice.rateEnd = spec.rateEnd
            voice.low = max(spec.low, 40)
            voice.high = max(spec.high, voice.low)
            voice.q = spec.q
            voice.grainDecay = exp(-1 / max(spec.grainDecay * sampleRate, 1))
            voice.grainCountdown = 0
            voice.grainLevel = 0
        case .hush:
            return
        }
        voices[slot] = voice
    }

    private func configureRing(_ spec: RingSpec, slot: Int, voice: inout Voice) {
        let ratios: [Float]
        switch spec.mode {
        case .metal: ratios = Synth.metalRatios
        case .glass: ratios = Synth.glassRatios
        case .steel: ratios = Synth.steelRatios
        case .wood: ratios = Synth.woodRatios
        case .bell: ratios = Synth.bellRatios
        }
        let count = min(max(spec.partials, 1), Synth.maxPartials, ratios.count)
        voice.partialCount = count
        let brightness = min(max(spec.brightness, 0.05), 0.98)
        var total: Float = 0
        for n in 0..<count { total += pow(brightness, Float(n)) }
        var jitter = spec.seed | 1
        let base = slot * Synth.maxPartials * Synth.partialStride
        for n in 0..<count {
            jitter ^= jitter << 13
            jitter ^= jitter >> 17
            jitter ^= jitter << 5
            let detune: Float = n == 0 ? 1 : 1 + 0.02 * (Float(jitter % 2001) / 1000 - 1)
            let frequency = spec.fundamental * ratios[n] * detune
            let offset = base + n * Synth.partialStride
            guard frequency > 20, frequency < sampleRate * 0.45 else {
                bank[offset] = 0
                bank[offset + 1] = 0
                bank[offset + 2] = 1
                bank[offset + 3] = 0
                bank[offset + 4] = 0
                continue
            }
            var tau = spec.decay / (1 + 0.6 * Float(n))
            if frequency > 2500 && frequency < 4500 { tau *= 0.25 } // never a sustained screech (02 §1.2)
            let omega = 2 * Float.pi * frequency / sampleRate
            bank[offset] = spec.gain * pow(brightness, Float(n)) / total * 1.6
            bank[offset + 1] = 0
            bank[offset + 2] = cos(omega)
            bank[offset + 3] = sin(omega)
            bank[offset + 4] = exp(-1 / max(tau * sampleRate, 1))
        }
    }

    private func renderVoice(_ voice: inout Voice, slot: Int) -> Float {
        if voice.delay > 0 {
            voice.delay -= 1
            return 0
        }
        let age = voice.age
        voice.age += 1
        if age >= voice.length {
            voice.active = false
            return 0
        }
        // Linear attack, then exponential decay.
        let envelope: Float
        if age < voice.attack {
            envelope = Float(age) / Float(voice.attack)
        } else {
            voice.level *= voice.decayRate
            envelope = voice.level
        }
        if envelope < 0.0003 && age > voice.attack {
            voice.active = false
            return 0
        }

        switch voice.kind {
        case .noise:
            if voice.sweepSamples > 0 && age % 32 == 0 {
                let progress = min(Float(age) / Float(voice.sweepSamples), 1)
                let cutoff = voice.cutoff * pow(voice.cutoffEnd / max(voice.cutoff, 1), progress)
                voice.filter.tune(cutoff: cutoff, q: voice.q, sampleRate: sampleRate)
            }
            return voice.filter.process(nextNoise(), voice.mode) * envelope * voice.gain
        case .tone:
            let progress = min(Float(age) / Float(voice.glide), 1)
            var frequency = voice.startFreq + (voice.endFreq - voice.startFreq) * progress
            if voice.vibratoDepth > 0 {
                voice.vibratoPhase += 2 * .pi * voice.vibratoRate / sampleRate
                if voice.vibratoPhase > 2 * .pi { voice.vibratoPhase -= 2 * .pi }
                frequency *= 1 + voice.vibratoDepth * sin(voice.vibratoPhase)
            }
            voice.phase += 2 * .pi * frequency / sampleRate
            if voice.phase > 2 * .pi { voice.phase -= 2 * .pi }
            var value: Float = 0
            let nyquistGuard = sampleRate * 0.45
            for harmonic in 1...voice.harmonics where frequency * Float(harmonic) < nyquistGuard {
                value += sin(voice.phase * Float(harmonic)) / Float(harmonic)
            }
            return value * envelope * voice.gain
        case .ring:
            let base = slot * Synth.maxPartials * Synth.partialStride
            var sum: Float = 0
            for n in 0..<voice.partialCount {
                let o = base + n * Synth.partialStride
                let re = bank[o]
                let im = bank[o + 1]
                let c = bank[o + 2]
                let s = bank[o + 3]
                let d = bank[o + 4]
                let newIm = (re * s + im * c) * d
                bank[o] = (re * c - im * s) * d
                bank[o + 1] = newIm
                sum += newIm
            }
            return sum * envelope
        case .crunch:
            let progress = min(Float(age) / Float(voice.total), 1)
            if age < voice.total {
                voice.grainCountdown -= 1
                if voice.grainCountdown <= 0 {
                    let rate = voice.rate + (voice.rateEnd - voice.rate) * progress
                    voice.grainLevel = 0.35 + 0.65 * unitNoise()
                    let centre = voice.low * pow(voice.high / voice.low, unitNoise())
                    voice.filter.tune(cutoff: centre, q: voice.q, sampleRate: sampleRate)
                    voice.grainCountdown = Int(sampleRate / max(rate, 1) * (0.25 + 1.5 * unitNoise())) + 1
                }
            }
            voice.grainLevel *= voice.grainDecay
            let shape = 1 + (voice.gainEnd - 1) * progress
            return voice.filter.process(nextNoise(), .bandPass) * voice.grainLevel * voice.gain * shape
        case .sample:
            guard let data = voice.sampleData else {
                voice.active = false
                return 0
            }
            let index = Int(voice.samplePosition)
            guard index + 1 < data.count else {
                voice.active = false
                return 0
            }
            // Linear interpolation between neighbours (varispeed).
            let fraction = Float(voice.samplePosition - Double(index))
            let a = data.samples[index]
            let b = data.samples[index + 1]
            voice.samplePosition += voice.sampleStep
            return (a + (b - a) * fraction) * voice.gain
        }
    }
}
