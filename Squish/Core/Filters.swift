import Foundation

/// One-Euro filter (Casiez et al., CHI 2012): heavy smoothing when the input is slow,
/// low lag when it moves fast. Used on the raw hinge angle.
struct OneEuroFilter {
    var minCutoff: Double
    var beta: Double
    var dCutoff: Double

    private(set) var value: Double?
    /// Filtered derivative of the input, in units per second.
    private(set) var derivative: Double = 0
    private var lastTime: Double?

    init(minCutoff: Double, beta: Double, dCutoff: Double) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
    }

    mutating func reset() {
        value = nil
        derivative = 0
        lastTime = nil
    }

    mutating func filter(_ x: Double, at time: Double) -> Double {
        guard let previous = value, let previousTime = lastTime else {
            value = x
            lastTime = time
            derivative = 0
            return x
        }
        // Clamp dt like Accorduon does, so a jump after a pause still registers as movement.
        let dt = min(max(time - previousTime, 1.0 / 240.0), 0.2)
        let rawDerivative = (x - previous) / dt
        derivative = Self.lowpass(derivative, rawDerivative, Self.alpha(cutoff: dCutoff, dt: dt))
        let cutoff = minCutoff + beta * abs(derivative)
        let filtered = Self.lowpass(previous, x, Self.alpha(cutoff: cutoff, dt: dt))
        value = filtered
        lastTime = time
        return filtered
    }

    private static func alpha(cutoff: Double, dt: Double) -> Double {
        let r = 2 * Double.pi * cutoff * dt
        return r / (r + 1)
    }

    private static func lowpass(_ a: Double, _ b: Double, _ k: Double) -> Double {
        a + k * (b - a)
    }
}

/// Critically damped spring, integrated with the exact closed-form solution so it is stable at any frame time.
struct CriticalSpring {
    var value: Double = 0
    var velocity: Double = 0

    mutating func step(toward target: Double, omega: Double, dt: Double) {
        guard dt > 0 else { return }
        let x0 = value - target
        let decay = exp(-omega * dt)
        let newX = (x0 + (velocity + omega * x0) * dt) * decay
        velocity = (velocity - omega * (velocity + omega * x0) * dt) * decay
        value = target + newX
    }
}

/// Deterministic RNG so every press can be replayed from its seed (share clips, tests).
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
    min(max(value, lower), upper)
}
