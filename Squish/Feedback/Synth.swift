import Foundation
import os

/// A one-shot sound for the synth. Everything in v1 is synthesised (free-first, bible §15.1);
/// sampled material layers slot in later via the audio manifest.
enum SynthCommand: Sendable {
    /// Band-passed noise burst: pops, cracks, crunch grains, hiss puffs.
    case noise(center: Float, q: Float, attack: Float, decay: Float, gain: Float, delay: Float)
    /// Pitched tone with a glide and optional vibrato: ticks, squeaks, honks, thumps, the sting.
    case tone(start: Float, end: Float, glide: Float, duration: Float, attack: Float, gain: Float,
              harmonics: Int, vibratoRate: Float, vibratoDepth: Float, delay: Float)
}

/// Continuous layers, set from the main thread every frame and smoothed per sample on the audio thread.
struct BedParams: Sendable {
    var hissGain: Float = 0
    var hissCenter: Float = 1500
    var humGain: Float = 0
    var humPitch: Float = 1
    var master: Float = 0.9
}

/// Fixed-capacity command queue. Never allocates after init, so the audio thread can drain it safely.
private struct CommandRing {
    private var items: [SynthCommand]
    private var read = 0
    private var write = 0

    init(capacity: Int) {
        items = Array(repeating: .noise(center: 0, q: 1, attack: 0, decay: 0, gain: 0, delay: 0), count: capacity)
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

/// Topology-preserving state-variable filter (Zavalishin), band-pass output.
private struct BandPass {
    var a1: Float = 0, a2: Float = 0, a3: Float = 0
    var ic1: Float = 0, ic2: Float = 0

    mutating func configure(center: Float, q: Float, sampleRate: Float) {
        let g = tan(Float.pi * min(center, sampleRate * 0.45) / sampleRate)
        let k = 1 / max(q, 0.1)
        a1 = 1 / (1 + g * (g + k))
        a2 = g * a1
        a3 = g * a2
        ic1 = 0
        ic2 = 0
    }

    mutating func process(_ x: Float) -> Float {
        let v3 = x - ic2
        let v1 = a1 * ic1 + a2 * v3
        let v2 = ic2 + a2 * ic1 + a3 * v3
        ic1 = 2 * v1 - ic1
        ic2 = 2 * v2 - ic2
        return v1
    }
}

private struct Voice {
    enum Kind { case noise, tone }
    var active = false
    var kind: Kind = .noise
    var delay = 0
    var age = 0
    var attack = 1
    var length = 0
    var decayRate: Float = 0
    var level: Float = 1
    var gain: Float = 0
    var filter = BandPass()
    var phase: Float = 0
    var startFreq: Float = 0
    var endFreq: Float = 0
    var glide = 1
    var harmonics = 1
    var vibratoPhase: Float = 0
    var vibratoRate: Float = 0
    var vibratoDepth: Float = 0
}

/// Real-time synth rendered inside an AVAudioSourceNode. Main thread → `trigger`/`setBeds`;
/// audio thread → `render`. Shared state crosses through two short unfair locks.
final class Synth: @unchecked Sendable {
    let sampleRate: Float

    private let commands = OSAllocatedUnfairLock(uncheckedState: CommandRing(capacity: 256))
    private let bedParams = OSAllocatedUnfairLock(initialState: BedParams())

    // Audio-thread-only state below.
    private var voices = [Voice](repeating: Voice(), count: 32)
    private var noiseState: UInt32 = 0x1234_5678
    private var hiss = BandPass()
    private var hissGain: Float = 0
    private var hissCenter: Float = 1500
    private var hissRetuneCounter = 0
    private var humGain: Float = 0
    private var humPitch: Float = 1
    private var humPhase1: Float = 0
    private var humPhase2: Float = 0
    private var master: Float = 0.9

    init(sampleRate: Float) {
        self.sampleRate = sampleRate
        hiss.configure(center: 1500, q: 0.8, sampleRate: sampleRate)
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
        let smoothing: Float = 1 - exp(-1 / (0.025 * sampleRate)) // ~25 ms parameter ramps (no zipper noise)

        for frame in 0..<frames {
            hissGain += (target.hissGain - hissGain) * smoothing
            hissCenter += (target.hissCenter - hissCenter) * smoothing
            humGain += (target.humGain - humGain) * smoothing
            humPitch += (target.humPitch - humPitch) * smoothing
            master += (target.master - master) * smoothing

            hissRetuneCounter += 1
            if hissRetuneCounter >= 64 {
                hissRetuneCounter = 0
                let (ic1, ic2) = (hiss.ic1, hiss.ic2)
                hiss.configure(center: hissCenter, q: 0.8, sampleRate: sampleRate)
                hiss.ic1 = ic1
                hiss.ic2 = ic2
            }

            var sample: Float = 0
            if hissGain > 0.0001 {
                sample += hiss.process(nextNoise()) * hissGain
            }
            if humGain > 0.0001 {
                // 220 + 330 Hz implies a 110 Hz fundamental the phone speaker can't play.
                humPhase1 += 2 * .pi * 220 * humPitch / sampleRate
                humPhase2 += 2 * .pi * 330 * humPitch / sampleRate
                if humPhase1 > 2 * .pi { humPhase1 -= 2 * .pi }
                if humPhase2 > 2 * .pi { humPhase2 -= 2 * .pi }
                sample += (sin(humPhase1) * 0.6 + sin(humPhase2) * 0.4) * humGain
            }

            for index in voices.indices where voices[index].active {
                sample += renderVoice(&voices[index])
            }

            // Soft limiter so stacked pops never clip.
            let driven = sample * master
            out[frame] = driven / (1 + abs(driven))
        }
    }

    private func nextNoise() -> Float {
        noiseState ^= noiseState << 13
        noiseState ^= noiseState >> 17
        noiseState ^= noiseState << 5
        return Float(Int32(bitPattern: noiseState)) / Float(Int32.max)
    }

    private func start(_ command: SynthCommand) {
        var slot = voices.firstIndex { !$0.active }
        if slot == nil {
            // Steal the oldest voice.
            slot = voices.indices.max { voices[$0].age < voices[$1].age }
        }
        guard let slot else { return }
        var voice = Voice()
        voice.active = true
        switch command {
        case let .noise(center, q, attack, decay, gain, delay):
            voice.kind = .noise
            voice.delay = Int(delay * sampleRate)
            voice.attack = max(Int(attack * sampleRate), 1)
            voice.decayRate = exp(-1 / max(decay * sampleRate, 1))
            voice.length = voice.attack + Int(decay * sampleRate * 7)
            voice.gain = gain
            voice.filter.configure(center: center, q: q, sampleRate: sampleRate)
        case let .tone(startFreq, endFreq, glide, duration, attack, gain, harmonics, vibratoRate, vibratoDepth, delay):
            voice.kind = .tone
            voice.delay = Int(delay * sampleRate)
            voice.attack = max(Int(attack * sampleRate), 1)
            voice.length = max(Int(duration * sampleRate), voice.attack + 1)
            voice.decayRate = exp(-1 / max(duration * 0.25 * sampleRate, 1))
            voice.gain = gain
            voice.startFreq = startFreq
            voice.endFreq = endFreq
            voice.glide = max(Int(glide * sampleRate), 1)
            voice.harmonics = max(harmonics, 1)
            voice.vibratoRate = vibratoRate
            voice.vibratoDepth = vibratoDepth
        }
        voices[slot] = voice
    }

    private func renderVoice(_ voice: inout Voice) -> Float {
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
            return voice.filter.process(nextNoise()) * envelope * voice.gain
        case .tone:
            let progress = min(Float(age) / Float(voice.glide), 1)
            var frequency = voice.startFreq + (voice.endFreq - voice.startFreq) * progress
            if voice.vibratoDepth > 0 {
                voice.vibratoPhase += 2 * .pi * voice.vibratoRate / sampleRate
                frequency *= 1 + voice.vibratoDepth * sin(voice.vibratoPhase)
            }
            voice.phase += 2 * .pi * frequency / sampleRate
            if voice.phase > 2 * .pi { voice.phase -= 2 * .pi }
            var value: Float = 0
            for harmonic in 1...voice.harmonics {
                value += sin(voice.phase * Float(harmonic)) / Float(harmonic)
            }
            return value * envelope * voice.gain
        }
    }
}
