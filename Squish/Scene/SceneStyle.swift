import Foundation
import simd
import UIKit

/// Every look constant of the press scene in one place (VISUAL-TARGET §3), so art-direction passes are one-file edits.
/// Distances in metres, angles in degrees. Values marked [tune] are confirmed in the CI screenshot loop.
struct SceneStyle {
    /// A camera preset (§3.2): position, downward pitch and vertical FOV, valid around an aspect ratio (w/h).
    struct CameraPreset {
        var position: SIMD3<Float>
        var pitch: Float
        var fieldOfView: Float
    }

    // MARK: Camera / composition (§3.2)
    /// P — phone portrait (a ≤ 0.56).
    var presetP = CameraPreset(position: [0, 0.3884, 0.6096], pitch: 20, fieldOfView: 49.6) // VISUAL-REVIEW-1 fix 3: anvil still at 74%
    /// D — Duo press posture, full inner display (0.66 … 0.80).
    var presetD = CameraPreset(position: [0, 0.3503, 0.7903], pitch: 14, fieldOfView: 40.0)
    /// L — landscape diorama (a ≥ 1.2), used only when `bookPoseRolls` is false.
    var presetL = CameraPreset(position: [0, 0.3781, 1.1157], pitch: 12, fieldOfView: 30.0)
    /// Book / vice pose (bible §6.4): when the view is wider than tall, roll the camera so the ram comes from the
    /// side and frame it like portrait at the inverse aspect. False = the §3.2 landscape diorama instead.
    var bookPoseRolls = true
    /// −90: world-up points to screen-left, so the ram comes from the left.
    var bookRoll: Float = -90
    var nearPlane: Float = 0.05
    var farPlane: Float = 5

    // MARK: Lights & exposure (§3.5)
    var keyIntensity: Float = 1200                       // lux [tune]
    var keyColor = UIColor(red: 1.00, green: 0.97, blue: 0.93, alpha: 1)
    var keyDirection = SIMD3<Float>(-0.455, 0.707, 0.542) // direction *to* the light
    var rimIntensity: Float = 5000                       // lumens [tune]
    var rimColor = UIColor(red: 1.00, green: 0.93, blue: 0.82, alpha: 1)
    var rimPosition = SIMD3<Float>(0.25, 0.45, -0.45)
    var rimInner: Float = 20
    var rimOuter: Float = 35
    /// IBL exponent (2^x). 8-bit HDRI path: 0 + 2.3 (§3.3.1) [tune].
    var iblExponent: Float = 2.3
    /// Rotation of the IBL holder about Y in quarter turns, if the chrome-ball check shows the key on the wrong side.
    var iblQuarterTurns: Int = 0
    /// Brief point-light spike at failure (the scene's own bounce; the UI flashes the top half separately).
    var flashPeak: Float = 30_000
    var flashPeakReducedMotion: Float = 8_000
    var contactFlashPeak: Float = 3_000
    var flashHalfLife: Float = 0.04
    var flashColor = UIColor(hex: 0xFFF8EE)

    // MARK: Sweep (§3.4)
    /// Flip if CI shows the wall colour on the floor (texture v-origin convention).
    var sweepFlipV = false
    var sweepTextureSize = 512

    // MARK: Decals (§3.6)
    var aoAlpha: Float = 0.75
    var softShadowAlpha: Float = 0.32
    var softShadowCoveredAlpha: Float = 0.12
    var ramOcclusionMax: Float = 0.30

    // MARK: Juice (bible §9)
    var contactHitStop: Float = 0.040
    var failureHitStop: Float = 0.100
    var failureSlowMo: Float = 0.25
    var slowMoRate: Float = 0.3
    /// Object-local micro-shake under load (metres; 1–3 px at our framing).
    var loadShake: Float = 0.0003
    var failureKick: Float = 0.0012
    var kickHalfLife: Float = 0.06
    /// Pre-contact quiver as the ram nears (0.5% scale jitter).
    var quiver: Float = 0.005
    /// Idle breathing (§6.12): y ±0.6% at 0.35 Hz.
    var breathing: Float = 0.006
    /// Landing (§6.12): drop from +0.06 m at 1.5 g.
    var dropHeight: Float = 0.06
    var dropGravity: Float = 9.8 * 1.5

    static let standard = SceneStyle()

    /// Linear blend of presets by aspect (§3.2).
    func preset(forAspect a: Float) -> CameraPreset {
        func mix(_ p: CameraPreset, _ q: CameraPreset, _ t: Float) -> CameraPreset {
            let t = clamp(t, 0, 1)
            return CameraPreset(position: p.position + (q.position - p.position) * t,
                                pitch: p.pitch + (q.pitch - p.pitch) * t,
                                fieldOfView: p.fieldOfView + (q.fieldOfView - p.fieldOfView) * t)
        }
        if a <= 0.56 { return presetP }
        if a < 0.66 { return mix(presetP, presetD, (a - 0.56) / 0.10) }
        if a <= 0.80 { return presetD }
        if a < 1.2 { return mix(presetD, presetL, (a - 0.80) / 0.40) }
        return presetL
    }
}
