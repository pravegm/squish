import Foundation

// The press, beat by beat (design/EXPERIENCE-PLAN.md "The press, beat by beat"; research/EXPERIENCE-2.md §A1, §A4,
// §A6 and top-15 items 2, 3, 9 and 11). Pure, nonisolated maths: the engine schedules from it, the scene and the Fold
// controller draw from it, and Feedback can read the same numbers so sound and haptics land on the same frame.

/// Engine beats that are not `PressEvent`s: the break score after the burst and the creaks of a held press.
/// Delivered by `PressEngine.onBeat`, from `step(now:)`, in the same frame the scene draws them.
enum PressBeat: Equatable, Sendable {
    /// Held still under load (before the failure): one creak of the cadence, 0.6–1.2 s apart (seeded, quicker as the
    /// tension rises). `intensity` 0…1 is `PressEngine.tension`.
    case creak(intensity: Double)
    /// Break part 2: the hush is over and the object freezes at peak strain for `duration` s (object-only hit stop).
    /// Silence: nothing plays until the burst, which is `.fracture(isFailure: true)` exactly `duration` later.
    case hitStop(duration: Double)
    /// Break part 4: one debris grain while the debris flies at 0.3× (`index` of `count`, decaying `intensity`).
    case debris(index: Int, count: Int, intensity: Double)
    /// Break part 5: the slow debris is over; bits land and tails decay for `duration` s.
    case settle(duration: Double)
    /// One light landing tick of the settle (`index` of `count`, decaying `intensity`), gaps widening like bounces.
    case settleTick(index: Int, count: Int, intensity: Double)
    /// The break score is over.
    case settled

    // The hinge as a living control (any phase, not only the press):
    /// The ratchet: the filtered hinge angle crossed a detent line (every `HingeMotion.detentSpacing`°), at `angle`.
    /// `speed` is |°/s|. A visual tick on the Fold stage lands with it (the hazard stripes step, the needle twitches).
    case detent(angle: Double, closing: Bool, speed: Double)
    /// The machine powered up as the phone opened (lamps light, the needle wakes): `PressEngine.hingePower` rose past
    /// 0.9. On a reopen after a press this is the "release".
    case powerUp
    /// The machine powered down as the phone closed (outside a press): `hingePower` fell below 0.1.
    case powerDown
    /// The seal stroke (EXPERIENCE-REVIEW-1 #7): the crushed press closes on toward the real shut and a latch clicks home
    /// (`index` 0 and 1, at a third and two thirds of the way from the fully crushed angle to the shut angle: ~40° and ~25°).
    /// The ka-chunk follows at the shut. `PressEngine.sealProgress` ramps 0 → 1 over the same stroke.
    case latch(index: Int, angle: Double)

    // Touch on the object (inspection, only while nothing is pressed). A tap is `PressDirector.poke()` (Feedback
    // plays the material's answer); the scene jiggles the object.
    /// A tap poked the object. Reserved: the views call `PressDirector.poke()` for the sound and haptic directly, so
    /// the engine does not emit this today (the director's beat switch already lists it).
    case poke(strength: Double)
    /// A flick set the object spinning on the plate. `speed` in turns per second.
    case spin(speed: Double)
}

/// The hinge as a living control (founder, real Duo: "as I open the flap of the phone and close it, there should be
/// animations based on the angle, and associated sounds and vibrations").
enum HingeMotion {
    /// Degrees between ratchet detents.
    static let detentSpacing = 6.0
    /// A detent line counts once the angle is this far past it (no chatter while resting on a line).
    static let detentHysteresis = 0.6
    /// Power ramps in from `powerFloor` (dark, the inner display is off) to `powerFull`.
    static let powerFloor = 50.0
    static let powerFull = 110.0

    /// 0…1: how "on" the machine looks at hinge angle `angle` outside a press (smoothstep).
    static func power(angle: Double, closed: Bool) -> Double {
        guard !closed else { return 0 }
        let x = clamp((angle - powerFloor) / (powerFull - powerFloor), 0, 1)
        return x * x * (3 - 2 * x)
    }

    /// The detent lines crossed going from `from` to `to` (degrees), in the order crossed. Pure, for tests.
    static func linesCrossed(from: Double, to: Double) -> [Double] {
        let s = detentSpacing
        // Strictly past `from` (leaving a line you rest on isn't crossing it), up to and including `to`.
        if to < from {
            let top = (from / s).rounded(.up) - 1, bottom = (to / s).rounded(.up)
            guard top >= bottom else { return [] }
            return stride(from: top, through: bottom, by: -1).map { $0 * s }
        } else {
            let bottom = (from / s).rounded(.down) + 1, top = (to / s).rounded(.down)
            guard top >= bottom else { return [] }
            return stride(from: bottom, through: top, by: 1).map { $0 * s }
        }
    }
}

/// Touch on the object (founder, real Duo: "on touch I should be able to move around and see it"): drag spins it on
/// the plate about the vertical axis with a little tilt, inertia and a spring back; a pinch zooms a little; a tap pokes
/// it. Pure state, stepped by the scene each frame. The Fold anvil's camera never moves (the illusion holds): the
/// object itself turns.
struct ObjectInspection: Equatable {
    /// Radians about +y (on top of the stage's own yaw) and about +x (the tilt).
    var yaw = 0.0
    var tilt = 0.0
    var zoom = 1.0
    var yawVelocity = 0.0
    var tiltVelocity = 0.0
    var zoomVelocity = 0.0
    var dragging = false
    private var tiltTarget = 0.0
    private var pinchBase = 1.0

    /// Radians per point of horizontal drag; tilt per point of vertical drag, and its limit.
    static let yawPerPoint = 0.012
    static let tiltPerPoint = 0.004
    static let maxTilt = 0.14
    static let maxZoom = 2.0
    /// Below this spin rate (rad/s), the inertia hands over to the spring back.
    static let settleSpeed = 0.6

    var isAtRest: Bool {
        !dragging && abs(yaw) < 1e-3 && abs(tilt) < 1e-3 && abs(zoom - 1) < 1e-3
            && abs(yawVelocity) < 1e-3 && abs(tiltVelocity) < 1e-3
    }

    mutating func beginDrag() {
        dragging = true
        yawVelocity = 0
    }

    /// `dx`, `dy`: this move's translation in points.
    mutating func drag(dx: Double, dy: Double) {
        yaw += dx * Self.yawPerPoint
        tiltTarget = clamp(tiltTarget + dy * Self.tiltPerPoint, -Self.maxTilt, Self.maxTilt)
    }

    /// `vx`: the release velocity in points per second. Returns the flick's spin in turns per second.
    @discardableResult
    mutating func endDrag(vx: Double) -> Double {
        dragging = false
        tiltTarget = 0
        yawVelocity = clamp(vx * Self.yawPerPoint, -25, 25)
        return abs(yawVelocity) / (2 * .pi)
    }

    mutating func pinch(scale: Double, began: Bool) {
        if began { pinchBase = zoom }
        zoom = clamp(pinchBase * scale, 1, Self.maxZoom)
        zoomVelocity = 0
    }

    mutating func endPinch() { pinchBase = 1 }

    /// One frame. `allowed` false (a press is under way): everything springs home quickly.
    mutating func step(dt: Double, allowed: Bool) {
        guard dt > 0 else { return }
        if !allowed { dragging = false; tiltTarget = 0 }
        let home = allowed ? 9.0 : 22.0   // spring stiffness (rad/s)
        if !dragging {
            if allowed && abs(yawVelocity) > Self.settleSpeed {
                // Inertia: friction, the spring not yet engaged.
                yaw += yawVelocity * dt
                yawVelocity *= pow(0.5, dt / 0.35)
            } else {
                // Spring back to the nearest whole turn (a full spin never unwinds).
                let turn = 2 * Double.pi
                let rest = (yaw / turn).rounded() * turn
                Self.spring(&yaw, &yawVelocity, toward: rest, omega: home, dt: dt)
                if abs(yaw - rest) < 1e-4 && abs(yawVelocity) < 1e-3 { yaw = 0; yawVelocity = 0 }
            }
            Self.spring(&zoom, &zoomVelocity, toward: 1, omega: home, dt: dt)
            if abs(zoom - 1) < 1e-4 && abs(zoomVelocity) < 1e-3 { zoom = 1; zoomVelocity = 0 }
        }
        Self.spring(&tilt, &tiltVelocity, toward: tiltTarget, omega: dragging ? 18 : home, dt: dt)
    }

    /// A critically damped spring step.
    private static func spring(_ x: inout Double, _ v: inout Double, toward target: Double, omega: Double, dt: Double) {
        let steps = max(1, Int((dt * 240).rounded(.up)))
        let h = dt / Double(steps)
        for _ in 0..<steps {
            let a = -2 * omega * v - omega * omega * (x - target)
            v += a * h
            x += v * h
        }
    }
}

/// Where in the break score the press is (`PressEngine.breakPhase`).
enum BreakPhase: Equatable, Sendable {
    case none
    /// 1. Silence; the tremor peaks, then freezes.
    case hush
    /// 2. Object-only hit stop: the object is frozen at peak strain.
    case hitStop
    /// 3–4. From the burst frame (`.fracture(isFailure: true)`): debris at `BreakScore.slowRate`.
    case slowDebris
    /// 5. The settle.
    case settle
}

enum PressFeel {
    /// Every big failure, worst-case jitter included, lands at or above this hinge angle. The inner display turns off
    /// below ~55°, and the hit stop, the burst and the slow debris need the next ~0.5 s of closing to still be lit.
    /// PROVISIONAL until the founder's Tuning Lab hinge log gives the real display-off angle.
    static let failureFloorAngle = 66.0
    /// The inner display is dark below about this angle (simulator and docs; unmeasured on hardware).
    static let displayOffAngle = 45.0
}

// MARK: - 2. Resistance: "fight, then give" (EXPERIENCE-REVIEW-1 #1)

/// The object fights the plate, then gives way, without ever trailing the hand (founder, real Duo: the screen must move
/// with the hand). The height stays locked to the hand; the fight is in the other axes and in time:
/// - **resist:** over the last `window` of compression before the failure, `strain` ramps 0 → 1. The scene and the
///   object views turn it into a side bulge (up to `bulge` of the width), the centre pushing back up against the lid,
///   a tremor you can see (2–4 px) and the lid's shadow tightening (`PressVisualState.resistanceBulge`);
/// - **give:** at the burst the object collapses *ahead* of the hand by `collapse` (compression) over `give` seconds
///   (60–80 ms), then locks back onto the hand (`PressVisualState.collapseLead`). It yields faster than the plate moves.
/// Render side only: the engine's measured depth and every event stay on the hand, and the render depth (the ram, the
/// print, the gauge) never lags it. Only the object's own deformation is held through the hush and hit stop.
struct PressResistance: Equatable, Sendable {
    /// The strain ramps in over this much compression before the failure.
    var window: Double
    /// The side bulge at full strain, as a share of the width.
    var bulge: Double
    /// The over-collapse at the give (compression ahead of the hand).
    var collapse: Double
    /// Seconds the give takes (the held object catching up and over-collapsing, then locking back on).
    var give: Double = 0.07

    static let none = PressResistance(window: 0, bulge: 0, collapse: 0)

    /// Stiffness order as in bible §7: glass fights hardest and gives most violently; jelly barely fights and oozes.
    /// The Unsquishable fights and never gives (the press does).
    static func of(_ kind: ObjectKind) -> PressResistance {
        switch kind {
        case .glassBottle: PressResistance(window: 0.12, bulge: 0.08, collapse: 0.10, give: 0.06)
        case .unsquishable: PressResistance(window: 0.15, bulge: 0, collapse: 0, give: 0.06)
        case .sodaCan: PressResistance(window: 0.12, bulge: 0.18, collapse: 0.08, give: 0.07)
        case .crayon: PressResistance(window: 0.12, bulge: 0.10, collapse: 0.08, give: 0.06)
        case .egg: PressResistance(window: 0.10, bulge: 0.12, collapse: 0.08, give: 0.07)
        case .rubberDuck: PressResistance(window: 0.12, bulge: 0.20, collapse: 0.06, give: 0.08)
        case .gummyBear: PressResistance(window: 0.12, bulge: 0.18, collapse: 0.06, give: 0.08)
        case .cakeSlice: PressResistance(window: 0.10, bulge: 0.16, collapse: 0.05, give: 0.08)
        case .jelly: PressResistance(window: 0.08, bulge: 0.15, collapse: 0.05, give: 0.08)
        case .bubbleWrap: .none
        }
    }

    var fights: Bool { window > 0 }

    /// 0…1: how hard the object is fighting at hand compression c, ahead of a failure at `failure` (smoothstep over
    /// the window; 1 at the threshold).
    func strain(_ c: Double, failure: Double) -> Double {
        guard fights else { return 0 }
        let x = clamp((c - (failure - window)) / window, 0, 1)
        return x * x * (3 - 2 * x)
    }

    /// The over-collapse t s after the burst: a half-sine of height `collapse` over `give`, 0 after.
    func lead(after t: Double) -> Double {
        guard collapse > 0, give > 0, t >= 0, t < give else { return 0 }
        return collapse * sin(.pi * t / give)
    }

    /// The give: t s after the burst, from the held compression to the hand's c (ease-out cubic, so the lurch lands
    /// early); exactly c from `give` on.
    func released(from held: Double, to c: Double, after t: Double) -> Double {
        guard give > 0, t < give else { return c }
        let x = clamp(t / give, 0, 1)
        let k = 1 - (1 - x) * (1 - x) * (1 - x)
        return held + (c - held) * k
    }
}

// MARK: - Tonnage (EXPERIENCE-REVIEW-1 #4): tons that mean something

/// The force on the gauge and the card, per material and per press, so the number tells the object's story: bubble
/// wrap is a few tons, a can is heavy, glass heavier, the steel ball is off the scale. Every needle (P-48, Fold crown,
/// cover) rests on `record`, and `SpecimenRecord.tons` is `record`. Pure, seeded.
enum Tonnage {
    /// The force the material takes at its break (or at full crush, for bubble wrap).
    static func rated(_ kind: ObjectKind) -> Double {
        switch kind {
        case .bubbleWrap: 3
        case .jelly: 2
        case .cakeSlice: 4
        case .egg: 6
        case .gummyBear: 8
        case .rubberDuck: 9
        case .crayon: 12
        case .sodaCan: 22
        case .glassBottle: 38
        case .unsquishable: 400
        }
    }

    /// ±10 % per press, seeded.
    static func variation(seed: UInt64) -> Double { 0.9 + 0.2 * Double(seed % 11) / 10 }

    /// This press's failure threshold, if the material has one.
    static func failure(_ kind: ObjectKind, seed: UInt64) -> Double? {
        guard let index = kind.profile.failureIndex else { return nil }
        let t = kind.profile.jitteredFractures(seed: seed)
        return index < t.count ? t[index] : nil
    }

    /// The live force at compression c. The fight: it climbs steeply as the object resists, to 95 % of the rated force at
    /// the break. The give: it drops to 40 % when the object yields, then climbs back to the rated force as the remains
    /// compact. Bubble wrap just stiffens. `failed`: nil works it out from c and the seed.
    static func live(kind: ObjectKind, compression c: Double, seed: UInt64, failed: Bool? = nil) -> Double {
        let r = rated(kind) * variation(seed: seed)
        let c = clamp(c, 0, 1)
        guard let f = failure(kind, seed: seed) else { return r * pow(c, 1.2) }
        if !(failed ?? (c >= f)) { return 0.95 * r * pow(min(c / max(f, 0.01), 1), 1.6) }
        let t = clamp((c - f) / max(1 - f, 0.05), 0, 1)
        return r * (0.4 + 0.6 * t)
    }

    /// The press's peak force, as the card prints it (whole tons, ≥ 1; the Unsquishable reads 400-odd).
    static func record(kind: ObjectKind, maxCompression c: Double, seed: UInt64) -> Int {
        if kind == .unsquishable { return 400 + Int(seed % 97) }
        let r = rated(kind) * variation(seed: seed)
        var peak = live(kind: kind, compression: c, seed: seed)
        if let f = failure(kind, seed: seed), c >= f { peak = max(peak, 0.95 * r) }
        return max(1, Int(peak.rounded()))
    }
}

// MARK: - 4–5. The tell and the break score

/// The tell (EXPERIENCE-2 §A1.2): `.preFailureTell` fires ~150–300 ms before the break.
enum PressTell {
    /// Fire when the hand is predicted to cross the failure within this many seconds.
    static let lead = 0.25
    /// Never earlier than this far (compression) before the failure.
    static let reach = 0.2
    /// A crawl or a hold gets the tell once this close (compression) to the failure, whatever the speed.
    static let near = 0.03

    /// `angle` and `failureAngle` in degrees, `closingSpeed` in °/s (positive closing).
    static func shouldFire(compression c: Double, failure: Double, angle: Double, failureAngle: Double,
                           closingSpeed: Double) -> Bool {
        if c >= failure - near { return true }
        guard c >= failure - reach, closingSpeed > 2 else { return false }
        return (angle - failureAngle) / closingSpeed <= lead
    }
}

/// The break, scored in five parts (EXPERIENCE-PLAN "Break"; EXPERIENCE-2 §A4). Times are seconds from the moment the
/// hand crosses the failure threshold, which is the `.hush` event:
///
///     hush ──── hitStop ──── burst ── slow debris (0.3×) ── settle ── settled
///     0         hush         burst    burst … slowEnd        … end
///
/// The burst is `.fracture(isFailure: true)`: one frame for the flash, the 1.0 haptic transient and the sound.
struct BreakScore: Equatable, Sendable {
    /// 1. Silence, 50–80 ms.
    var hush: Double
    /// 2. Object-only hit stop, 70–140 ms.
    var hitStop: Double
    /// 4. Debris at `slowRate` for this long after the burst, 250–400 ms.
    var slowDebris: Double
    var slowRate: Double = 0.3
    /// 5. The settle, 1–2 s.
    var settle: Double
    /// Debris grains in the slow window (3–6) and landing ticks in the settle (4–8), for Feedback.
    var debrisGrains: Int
    var settleTicks: Int

    static let hushRange = 0.05...0.08

    /// 3. The burst, from the crossing.
    var burst: Double { hush + hitStop }
    var slowEnd: Double { burst + slowDebris }
    var end: Double { slowEnd + settle }

    /// `hush` is `PressConfig.failureHushDelay` (Tuning Lab), kept inside 50–80 ms.
    static func of(_ kind: ObjectKind, hush: Double = 0.065) -> BreakScore {
        let h = clamp(hush, hushRange.lowerBound, hushRange.upperBound)
        switch kind {
        case .glassBottle:
            return BreakScore(hush: h, hitStop: 0.14, slowDebris: 0.40, settle: 1.8, debrisGrains: 6, settleTicks: 8)
        case .unsquishable:
            return BreakScore(hush: h, hitStop: 0.14, slowDebris: 0.40, settle: 1.6, debrisGrains: 4, settleTicks: 6)
        case .sodaCan:
            return BreakScore(hush: h, hitStop: 0.11, slowDebris: 0.32, settle: 1.4, debrisGrains: 5, settleTicks: 6)
        case .egg:
            return BreakScore(hush: h, hitStop: 0.11, slowDebris: 0.32, settle: 1.4, debrisGrains: 4, settleTicks: 6)
        case .crayon:
            return BreakScore(hush: h, hitStop: 0.09, slowDebris: 0.30, settle: 1.2, debrisGrains: 4, settleTicks: 5)
        case .cakeSlice:
            return BreakScore(hush: h, hitStop: 0.07, slowDebris: 0.28, settle: 1.2, debrisGrains: 3, settleTicks: 5)
        case .rubberDuck, .gummyBear, .jelly, .bubbleWrap:
            return BreakScore(hush: h, hitStop: 0.07, slowDebris: 0.25, settle: 1.0, debrisGrains: 3, settleTicks: 4)
        }
    }

    /// The phase `elapsed` s after the crossing, for a burst on schedule.
    func phase(at elapsed: Double) -> BreakPhase {
        if elapsed < 0 { return .none }
        if elapsed < hush { return .hush }
        if elapsed < burst { return .hitStop }
        if elapsed < slowEnd { return .slowDebris }
        if elapsed < end { return .settle }
        return .none
    }

    /// The post-burst beats, in time order, as (seconds after the burst, beat).
    func beatsAfterBurst() -> [(time: Double, beat: PressBeat)] {
        var beats: [(time: Double, beat: PressBeat)] = []
        let n = max(debrisGrains, 1)
        for i in 0..<n {
            // Front-loaded: most debris lands early in the slow window.
            let t = 0.03 + (slowDebris - 0.06) * pow(Double(i) / Double(n), 1.2)
            beats.append((time: t, beat: PressBeat.debris(index: i, count: n, intensity: 0.8 * pow(0.72, Double(i)))))
        }
        beats.append((time: slowDebris, beat: PressBeat.settle(duration: settle)))
        let m = max(settleTicks, 1)
        for j in 0..<m {
            // Gaps widen, like bits bouncing to rest.
            let t = slowDebris + settle * 0.9 * pow(Double(j + 1) / Double(m + 1), 1.5)
            beats.append((time: t, beat: PressBeat.settleTick(index: j, count: m, intensity: 0.5 * pow(0.8, Double(j)))))
        }
        beats.append((time: slowDebris + settle, beat: PressBeat.settled))
        return beats
    }
}

// MARK: - 3. Tension you can hold

/// Holding the hinge still under load keeps the tension alive (EXPERIENCE-2 §A1.3, top-15 #9): a micro-tremor, a creak
/// cadence and a strain bed that holds, never fading to dead.
enum HoldTension {
    /// 0…1. Depends only on where the press is, never on how long it has been held, so it never decays while held.
    static func level(compression c: Double, failure: Double?, failed: Bool, inTell: Bool) -> Double {
        guard c > 0 else { return 0 }
        if failed { return 0.3 }
        guard let f = failure, f > 0 else { return clamp(0.2 + 0.5 * c, 0, 1) }
        let p = clamp(c / f, 0, 1)
        let base = 0.2 + 0.8 * p * p
        return inTell ? max(base, 0.85) : base
    }

    /// Seconds to the next creak: 0.6–1.2 s, the top end falling to 0.8 s as the tension rises.
    static func creakInterval(level: Double, roll: Double) -> Double {
        let hi = 1.2 - 0.4 * clamp(level, 0, 1)
        return 0.6 + (hi - 0.6) * clamp(roll, 0, 1)
    }

    /// The first creak after the hand stops.
    static let firstCreak = 0.35

    /// The floor the strain bed should hold at while held under load: ~40 % in the tell window (EXPERIENCE-2 §A1.3),
    /// a quarter of the tension before it. Never 0 while loaded.
    static func bedFloor(level: Double, inTell: Bool) -> Double {
        guard level > 0 else { return 0 }
        return inTell ? 0.4 : 0.25 * level
    }
}

// MARK: - How you closed it (EXPERIENCE-2 §A6.1, top-15 #11; APPLE-DUO-GUIDE)

/// The stamp a press earns from how it was closed: a slow, steady close gives PERFECT; a slam gives SLAMMED, shown
/// gently as a "try it slower" nudge, never a reward. There is no stamp, reward or incentive for rapid or repeated hinge
/// cycling (App Review 2.4.2, device wear): a pumped press is just PRESSED.
enum CloseStyle: Equatable, Sendable {
    case pressed
    case perfect
    case slammed

    init(_ result: PressResult) {
        if result.wasSlammed {
            self = .slammed
        } else if result.isPerfect {
            self = .perfect
        } else {
            self = .pressed
        }
    }

    /// What the platen's stamp says.
    var stampText: String {
        switch self {
        case .pressed: "PRESSED"
        case .perfect: "PERFECT"
        case .slammed: "SLAMMED"
        }
    }

    /// SLAMMED is drawn gently (soft graphite, not the red ink): a nudge, not a trophy.
    var isGentle: Bool { self == .slammed }

    /// The nudge for the UI to show with a gentle stamp.
    var nudge: String? { self == .slammed ? "Try it slower for a Perfect." : nil }
}

extension PressResult {
    var closeStyle: CloseStyle { CloseStyle(self) }
}
