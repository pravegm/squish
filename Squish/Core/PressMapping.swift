import Foundation

/// Hinge angle → press depth (bible §6.2).
///
///     t      = clamp((θ0 − θ) / (θ0 − θ_end), 0, 1)
///     depth  = t < contactT ? t : contactT + (1 − contactT) · ((t − contactT)/(1 − contactT))^easeExponent
///     c      = max(0, depth − contactT) / (1 − contactT)
///
/// `depth` 0…contactT is the ram's free approach; `c` is the object's compression (0 at contact, 1 flat).
enum PressMapping {
    static func travel(angle: Double, start: Double, config: PressConfig) -> Double {
        let span = start - config.endAngle
        guard span > 1 else { return angle <= config.endAngle ? 1 : 0 }
        return clamp((start - angle) / span, 0, 1)
    }

    static func depth(travel t: Double, config: PressConfig) -> Double {
        let contact = config.contactT
        guard t >= contact else { return max(t, 0) }
        let x = (t - contact) / (1 - contact)
        return contact + (1 - contact) * pow(min(x, 1), config.easeExponent)
    }

    static func depth(angle: Double, start: Double, config: PressConfig) -> Double {
        depth(travel: travel(angle: angle, start: start, config: config), config: config)
    }

    static func compression(depth: Double, config: PressConfig) -> Double {
        clamp((depth - config.contactT) / (1 - config.contactT), 0, 1)
    }
}
