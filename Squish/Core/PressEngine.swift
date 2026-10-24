import Foundation
import Observation

enum PressPhase: String, Sendable {
    case idle, armed, pressing, sealed, revealing
}

enum PressEvent: Equatable, Sendable {
    case armed
    /// The ram meets the object.
    case contact
    /// One "grain" of the compliance illusion, emitted per `grainSpacing` degrees of fresh closing.
    case grain(compression: Double)
    /// The tell: the final stretch before the big failure (tremor, strain spike, accelerating micro-cracks), fired
    /// ~150–300 ms before the hand crosses the failure threshold (`PressTell`), or at the crossing for a slam.
    case preFailureTell
    /// Break part 1: the hand crossed the failure threshold. Beds and grains drop to silence. The hit stop follows after
    /// `breakScore.hush` (`PressBeat.hitStop`) and the burst, `.fracture(isFailure: true)`, after `breakScore.burst`.
    case hush
    case fracture(index: Int, isFailure: Bool)
    /// The press reached full depth.
    case bottomOut
    case sealed(blind: Bool)
    /// The magnet clap at `.closed` (or the end of a touch press). The brand sound.
    case kaChunk
    /// The user started opening while the object was loaded (elastic unload).
    case released
    case reveal
}

struct PressResult: Equatable, Sendable {
    var kind: ObjectKind
    var seed: UInt64
    var failureAngle: Double?
    var fractureCount: Int
    var maxCompression: Double
    var duration: Double
    var wasSlammed: Bool
    var isPerfect: Bool
    /// Times the user opened again mid-press while the object was loaded ("pumping" the press).
    var reversals: Int = 0
}

/// The heart of Squish: turns hinge samples into press depth, fires material events once,
/// and runs the state machine from bible §6.3. Pure logic with explicit timestamps, so it is unit-testable.
@MainActor
@Observable
final class PressEngine {
    var config: PressConfig

    /// The config used to map this press: `config` with the contact point captured at arm
    /// (FOLD-PRESS.md §4.1), so tuning applies live but contact never moves mid-press. A touch press keeps the
    /// P-48's own ease (`PressConfig.armed(at:hinge:)`).
    var mapping: PressConfig {
        guard let armedContactT else { return config }
        var mapped = config
        mapped.contactT = armedContactT
        if !armedOnHinge {
            mapped.easeExponent = PressConfig.touchEaseExponent
            mapped.endAngle = PressConfig.touchEndAngle
        }
        return mapped
    }
    @ObservationIgnored private var armedContactT: Double?
    /// The current arm was taken on a real hinge reading (the provisional fold mapping), not the touch press.
    @ObservationIgnored private var armedOnHinge = false

    private(set) var phase: PressPhase = .idle
    private(set) var kind: ObjectKind?
    private(set) var material: MaterialProfile?
    private(set) var seed: UInt64 = 0
    private(set) var thresholds: [Double] = []
    private(set) var firedCount = 0

    private(set) var rawAngle: Double = 180
    /// Filtered hinge angle in degrees (180 = flat).
    private(set) var angle: Double = 180
    /// Degrees per second, positive while closing.
    private(set) var closingSpeed: Double = 0
    private(set) var isClosed = false
    private(set) var isHolding = true
    private(set) var startAngle: Double

    /// Depth from the latest filtered sample. Drives every irreversible event. Always the hand, never the lag.
    private(set) var measuredDepth = 0.0
    /// Spring-smoothed depth at render rate. Drives the ram. Render side: it lags the hand near the failure and gives
    /// at the burst ("lag, then give", `PressResistance`), so it can sit behind `measuredDepth`.
    private(set) var renderDepth = 0.0
    /// The plastic part of the deformation as the eye sees it, ratcheted. The object never re-inflates past this.
    private(set) var plasticDepth = 0.0
    private(set) var maxCompression = 0.0
    private(set) var lastResult: PressResult?

    /// True when input comes from the touch fallback instead of a real hinge.
    var usesVirtualHinge = false

    var visualDepth: Double { max(plasticDepth, renderDepth) }
    var renderCompression: Double { PressMapping.compression(depth: renderDepth, config: mapping) }
    var visualCompression: Double { PressMapping.compression(depth: visualDepth, config: mapping) }
    var measuredCompression: Double { PressMapping.compression(depth: measuredDepth, config: mapping) }
    var isLoaded: Bool { phase == .pressing && measuredCompression > 0 }
    /// True when hinge samples arrive slower than ~10 Hz.
    var isLowRate: Bool { !usesVirtualHinge && sampleInterval > 0.1 }

    @ObservationIgnored var onEvent: ((PressEvent) -> Void)?
    /// The break score's beats and the held press's creaks (`PressBeat`), from `step(now:)`, in the frame they happen.
    @ObservationIgnored var onBeat: ((PressBeat) -> Void)?

    // MARK: Feel (design/EXPERIENCE-PLAN.md "The press, beat by beat"; Core/PressFeel.swift)

    /// "Lag, then give" for the object on the anvil (render side only).
    @ObservationIgnored private(set) var resistance = PressResistance.none
    /// The five-part break score for the object on the anvil.
    @ObservationIgnored private(set) var breakScore = BreakScore.of(.bubbleWrap)
    /// 0…1: how much tension the press holds right now. Rises toward the failure, holds while the hinge is still
    /// (never decays on a hold), 0 when unloaded. Feedback can hold its strain bed on `holdBedFloor`.
    @ObservationIgnored private(set) var tension = 0.0
    /// Loaded, before the failure, and the hinge held still: the creak cadence and the micro-tremor run.
    @ObservationIgnored private(set) var isHeldUnderLoad = false
    /// Counts every creak ever emitted (never reset), so views can catch each one without a callback.
    @ObservationIgnored private(set) var creakCount = 0
    /// The tell has fired and the failure hasn't been crossed yet.
    @ObservationIgnored private(set) var isTelling = false
    /// The strain-bed floor while held under load (`HoldTension.bedFloor`): ~0.4 in the tell, never 0 while loaded.
    var holdBedFloor: Double { isHeldUnderLoad ? HoldTension.bedFloor(level: tension, inTell: isTelling) : 0 }

    /// This press's failure threshold (compression), if the material has one.
    var failureThreshold: Double? {
        guard let index = material?.failureIndex, index < thresholds.count else { return nil }
        return thresholds[index]
    }

    /// Where the break score is, as of the last `step(now:)`.
    var breakPhase: BreakPhase {
        guard let crossedAt else { return .none }
        if let burstAt {
            let e = clockNow - burstAt
            if e < breakScore.slowDebris { return .slowDebris }
            if e < breakScore.slowDebris + breakScore.settle { return .settle }
            return .none
        }
        return clockNow - crossedAt < breakScore.hush ? .hush : .hitStop
    }

    /// Seconds since the burst (`.fracture(isFailure: true)`), nil before it.
    var sinceBurst: Double? { burstAt.map { clockNow - $0 } }

    // MARK: The hinge as a living control (any phase; Core/PressFeel.swift, HingeMotion)
    // Continuous signal: `angle` (filtered, °), `closingSpeed` (°/s, + closing), `hingePower`, `detentCount`.

    /// 0…1: how powered-up the machine looks. Rises as the phone opens (lamps light, the needle wakes) and falls as it
    /// closes outside a press; 1 throughout a press and on the touch press. Eased, ~0.25 s.
    @ObservationIgnored private(set) var hingePower = 1.0
    /// Counts every detent crossed (never reset), so views can catch each one without a callback.
    @ObservationIgnored private(set) var detentCount = 0
    /// Counts every power-up (never reset): the Fold bezel's wake-up sweep and the reveal's "release".
    @ObservationIgnored private(set) var powerUpCount = 0
    @ObservationIgnored private var detentAngle: Double?
    @ObservationIgnored private var powered: Bool?

    /// Touch on the object is allowed: nothing is pressed (open and resting, or idle). Never during a press, the
    /// seal or the reveal.
    var canInspect: Bool {
        (phase == .idle || phase == .armed) && measuredDepth < 0.01 && !isClosed
    }

    /// A flick set the object spinning (`turnsPerSecond`): emits `.spin` if inspection is allowed and it is a spin.
    func spun(turnsPerSecond: Double) {
        guard canInspect, turnsPerSecond > 0.15 else { return }
        onBeat?(.spin(speed: turnsPerSecond))
    }

    private func trackDetents(_ θ: Double) {
        guard let last = detentAngle else {
            detentAngle = θ
            return
        }
        let lines = HingeMotion.linesCrossed(from: last, to: θ)
        guard let final = lines.last, abs(θ - final) >= HingeMotion.detentHysteresis else { return }
        let closing = θ < last
        detentAngle = θ
        for line in lines.prefix(3) {
            detentCount &+= 1
            onBeat?(.detent(angle: line, closing: closing, speed: abs(displaySpeed)))
        }
    }

    private func updateHingePower(dt: Double) {
        let target: Double
        if lastSampleVirtual != false || phase == .pressing {
            target = 1
        } else {
            target = HingeMotion.power(angle: displayAngle, closed: isClosed)
        }
        hingePower += (target - hingePower) * (1 - pow(0.5, max(dt, 0) / 0.03))
        if abs(target - hingePower) < 1e-3 { hingePower = target }
        switch powered {
        case nil:
            powered = hingePower >= 0.5
        case true?:
            if hingePower < 0.1 {
                powered = false
                onBeat?(.powerDown)
            }
        case false?:
            if hingePower > 0.9 {
                powered = true
                powerUpCount &+= 1
                onBeat?(.powerUp)
            }
        }
    }

    @ObservationIgnored private var clockNow = 0.0
    /// The hinge at display rate (Core/HingeTracker.swift): every hinge-driven visual reads `displayAngle`.
    @ObservationIgnored private var tracker = HingeTracker()
    @ObservationIgnored private var frameInterval = 1.0 / 60
    /// The angle to draw this frame (degrees): the tracked hinge, one display frame ahead, continuous between
    /// reports. Events still use the filtered `angle` (honest, never predicted).
    @ObservationIgnored private(set) var displayAngle = 180.0
    /// °/s, positive while closing: the drawn angle's own speed (unbiased; eases to 0 when reports stop). Sound and
    /// haptics that follow the hinge should read this, with `displayAngle`.
    @ObservationIgnored private(set) var displaySpeed = 0.0
    /// The live pipeline lag, for the Tuning Lab.
    @ObservationIgnored private(set) var pipeline = PipelineStats()
    /// When the hinge last reported open after reading shut (at ≤ `config.shutAngle`), for the resume
    /// latency readout.
    @ObservationIgnored private(set) var openedAt: Double?
    @ObservationIgnored private var lastReadShut = false
    /// The phone was really shut since this press sealed (a reopen past `revealOpenAngle` then reveals).
    @ObservationIgnored private var shutSinceSeal = false
    /// °/s, + closing: the speed of the filtered angle itself (the tell's lead time).
    @ObservationIgnored private var filteredSpeed = 0.0
    @ObservationIgnored private var lastFilteredAngle: Double?
    /// When the hand crossed the failure threshold (`.hush`), and when the burst fired.
    @ObservationIgnored private var crossedAt: Double?
    @ObservationIgnored private var burstAt: Double?
    /// The eye's compression, frozen from the crossing to the burst (hush + hit stop); the give releases from it.
    @ObservationIgnored private var heldEyeCompression: Double?
    /// The hinge angle at which this press reaches its failure threshold (for the tell's lead).
    @ObservationIgnored private var failureThresholdAngle: Double?
    @ObservationIgnored private var pendingBeats: [(time: Double, beat: PressBeat)] = []
    @ObservationIgnored private var nextCreakAt: Double?
    @ObservationIgnored private var creakRNG = SplitMix64(seed: 1)

    @ObservationIgnored private var filter: OneEuroFilter
    @ObservationIgnored private var spring = CriticalSpring()
    @ObservationIgnored private var activationTime = -Double.infinity
    @ObservationIgnored private var lastSampleTime = -Double.infinity
    @ObservationIgnored private var sealHoldStart: Double?
    @ObservationIgnored private var sealedRestStart: Double?
    @ObservationIgnored private var pendingFailure: (index: Int, time: Double)?
    @ObservationIgnored private var nextGrainAngle: Double?
    @ObservationIgnored private var autoRevealTime: Double?
    @ObservationIgnored private var contactFired = false
    @ObservationIgnored private var tellFired = false
    @ObservationIgnored private var bottomFired = false
    @ObservationIgnored private var releaseFired = false
    @ObservationIgnored private var maxDepthReached = 0.0
    @ObservationIgnored private var pressStartTime: Double?
    /// The hinge angle at the moment the failure threshold was crossed (before the hush delay). The Fold readout
    /// freezes on this same value, so the crown and the specimen's "AT nn°" always agree.
    @ObservationIgnored private(set) var failureAngle: Double?
    @ObservationIgnored private var peakClosingSpeed = 0.0
    @ObservationIgnored private var reversedWhileLoaded = false
    @ObservationIgnored private var isReversing = false
    @ObservationIgnored private var reversals = 0
    /// Recent hinge sample intervals, for the low-rate mode (bible §6.1).
    @ObservationIgnored private var sampleInterval = 1.0 / 30.0
    @ObservationIgnored private var virtualAngle = 180.0
    @ObservationIgnored private var virtualReleasing = false
    /// Where the latest sample came from: nil before any sample, true for the touch press, false for a real hinge.
    /// Until a sample arrives, `angle` and `isClosed` are defaults, not readings (FOLD-REVIEW-6 N3).
    @ObservationIgnored private var lastSampleVirtual: Bool?
    /// True when the current arm rests on an observed open sample of the input driving the press. An arm taken before
    /// any sample (the touch press arms early so its teaching cue shows) is provisional: the next sample re-anchors it
    /// if it reads open ≥ `armAngleMin`, and drops it otherwise. A provisional arm never seals.
    @ObservationIgnored private var armObserved = false

    /// True once a real hinge sample has arrived (the director seeds share-clip traces with it).
    var hasHingeSample: Bool { lastSampleVirtual == false }

    init(config: PressConfig = .standard) {
        self.config = config
        self.startAngle = config.armAngleMax
        self.filter = OneEuroFilter(minCutoff: config.oneEuroMinCutoff, beta: config.oneEuroBeta, dCutoff: config.oneEuroDCutoff)
    }

    // MARK: - Lifecycle

    /// Call on launch and whenever the scene becomes active; hinge input is ignored briefly afterwards.
    func activate(at time: Double) {
        activationTime = time
    }

    /// Put a fresh object on the anvil.
    func load(_ kind: ObjectKind, seed: UInt64, at time: Double) {
        let material = kind.profile
        self.kind = kind
        self.material = material
        self.seed = seed
        thresholds = material.jitteredFractures(seed: seed)
        firedCount = 0
        measuredDepth = 0
        plasticDepth = 0
        maxCompression = 0
        renderDepth = 0
        spring = CriticalSpring()
        sealHoldStart = nil
        sealedRestStart = nil
        pendingFailure = nil
        nextGrainAngle = nil
        autoRevealTime = nil
        contactFired = false
        tellFired = false
        bottomFired = false
        releaseFired = false
        maxDepthReached = 0
        pressStartTime = nil
        failureAngle = nil
        peakClosingSpeed = 0
        reversedWhileLoaded = false
        isReversing = false
        reversals = 0
        lastResult = nil
        shutSinceSeal = false
        armedContactT = nil
        armedOnHinge = false
        armObserved = false
        resistance = PressResistance.of(kind)
        breakScore = BreakScore.of(kind, hush: config.failureHushDelay)
        tension = 0
        isHeldUnderLoad = false
        isTelling = false
        crossedAt = nil
        burstAt = nil
        heldEyeCompression = nil
        failureThresholdAngle = nil
        pendingBeats = []
        nextCreakAt = nil
        creakRNG = SplitMix64(seed: seed ^ 0xC4EA_C4EA)
        phase = .idle
        tryArm(at: time)
    }

    // MARK: - Input

    /// Feed one hinge sample (degrees, 180 = flat).
    func ingest(angle raw: Double, closed: Bool, at time: Double) {
        ingestSample(angle: raw, closed: closed, at: time, virtual: false)
    }

    private func ingestSample(angle raw: Double, closed reportedClosed: Bool, at time: Double, virtual: Bool) {
        // The real-Duo hinge log (25 Oct 2026, FOLD-PRESS §9.8): `.closed` is a coarse posture with big hysteresis. It sets
        // at ~85° while closing and clears at ~21° on reopen, so it is NOT "shut": treating it as shut sealed every press at
        // ~85°. Shut is the angle (≤ `shutAngle`, ~12°); the status is ignored (the director moves to the cover on the
        // outer display by window size, not by status).
        // The touch press is never shut (it seals at depth).
        _ = reportedClosed
        let closed = !virtual && raw <= config.shutAngle
        // The first sample from an input (at launch, or after switching between touch and hinge) is a state, not a
        // transition: launching with the phone shut is not "closing" it, and an earlier arm was taken on another
        // input's angle, so it must be re-anchored on this one (FOLD-REVIEW-6 N3).
        let newInput = lastSampleVirtual != virtual
        lastSampleVirtual = virtual
        if newInput {
            filter.reset()
            tracker.reset()
            if phase == .armed { armObserved = false }
        }
        rawAngle = raw
        // Read tunables every sample so Tuning Lab changes apply live.
        filter.minCutoff = config.oneEuroMinCutoff
        filter.beta = config.oneEuroBeta
        filter.dCutoff = config.oneEuroDCutoff
        let filtered = filter.filter(raw, at: time)
        tracker.sample(raw, at: time)
        let readShut = raw <= config.shutAngle
        if lastReadShut && !readShut { openedAt = time }
        lastReadShut = readShut
        // The tell's ETA needs the filtered angle's own speed: the One-Euro derivative is taken against the filtered
        // value, so at a steady close it reads ~2.5× the true speed (fine for its other uses, wrong for a lead time).
        if let last = lastFilteredAngle, lastSampleTime.isFinite, time - lastSampleTime > 1e-4, !newInput {
            let dt = min(time - lastSampleTime, 0.2)
            let k = dt / (0.08 + dt)
            filteredSpeed += ((last - filtered) / dt - filteredSpeed) * k
        } else {
            filteredSpeed = 0
        }
        lastFilteredAngle = filtered
        angle = filtered
        closingSpeed = -filter.derivative
        if lastSampleTime.isFinite {
            let interval = time - lastSampleTime
            if interval > 0 && interval < 1 {
                sampleInterval += (interval - sampleInterval) * 0.2
            }
        }
        lastSampleTime = time
        let wasClosed = newInput ? closed : isClosed
        isClosed = closed

        guard time - activationTime >= config.ignoreInputAfterActivation else { return }
        // The ratchet (tracked per frame on the drawn angle): the first reading from an input is a state, not motion.
        if newInput { detentAngle = nil }

        if closed && !wasClosed {
            handleClose(at: time)
        }

        switch phase {
        case .idle:
            tryArm(at: time)
        case .armed:
            if !armObserved {
                // A provisional arm meets its first reading. Shut, or not open enough to arm: nothing was pressed, so
                // drop the arm and re-arm only from a later open sample (FOLD-REVIEW-6 N3: a cold launch on the cover).
                guard !closed, filtered >= config.armAngleMin else {
                    disarm()
                    break
                }
                armObserved = true
                startAngle = min(filtered, config.armAngleMax)
                if pressStartTime == nil { captureMapping(hinge: !virtual) }
            }
            guard !closed else { break }
            if filtered > startAngle {
                startAngle = min(filtered, config.armAngleMax)
                if pressStartTime == nil { captureMapping(hinge: !virtual) }
            }
            if filtered <= startAngle - config.hysteresis {
                phase = .pressing
                if pressStartTime == nil { pressStartTime = time }
                updatePress(angle: filtered, at: time)
            }
        case .pressing:
            guard !closed else { break }
            updatePress(angle: filtered, at: time)
            if filtered >= startAngle + config.hysteresis && measuredDepth < 0.05 && !bottomFired {
                phase = .armed
                nextGrainAngle = nil
            }
        case .sealed:
            // Reveal once a reopen from shut passes `revealOpenAngle` (~25°; the real `.closed` clears at ~21°), or once
            // it's clearly open again.
            if closed { shutSinceSeal = true }
            if !closed && ((shutSinceSeal && raw >= config.revealOpenAngle) || filtered >= config.revealAngle) {
                beginReveal()
            }
        case .revealing:
            break
        }
    }

    /// Touch fallback (Pinch Press): set a virtual hinge angle.
    func setVirtualAngle(_ angle: Double, at time: Double) {
        virtualReleasing = false
        virtualAngle = clamp(angle, 0, 180)
        ingestSample(angle: virtualAngle, closed: false, at: time, virtual: true)
    }

    /// Touch fallback: the finger lifted, so the virtual press springs open.
    func releaseVirtual() {
        virtualReleasing = true
    }

    // MARK: - Per frame

    func step(now: Double, dt: Double) {
        clockNow = now
        if let pendingTime = pendingFailure?.time, now >= pendingTime {
            // On schedule: the hit stop's beat first, then the burst exactly hush + hit stop after the crossing,
            // whatever the frame rate.
            fireBeats(upTo: pendingTime)
            flushPendingFailure(at: pendingTime)
        }
        fireBeats(upTo: now)

        if phase == .pressing && lastSampleVirtual == false {
            // A real fold seals only when it is really shut (`handleClose`), never at an angle: full compression just
            // holds. Reopening a fully compressed press instead (never shut) seals and reveals it.
            if bottomFired && angle >= config.revealAngle {
                seal(blind: false, at: now)
                beginReveal()
            }
        } else if phase == .pressing {
            if measuredDepth >= config.sealDepth {
                if let start = sealHoldStart {
                    if now - start >= config.sealHold { seal(blind: false, at: now) }
                } else {
                    sealHoldStart = now
                }
            } else {
                sealHoldStart = nil
            }
        }

        if let revealTime = autoRevealTime, now >= revealTime {
            autoRevealTime = nil
            beginReveal()
        }

        // Arm without waiting for a fresh sample: a Duo lying still sends none, and the
        // first-press teaching cues only appear once the press is armed. `tryArm` still needs the last
        // reading to be open (or, for the touch press only, no reading yet).
        if phase == .idle {
            tryArm(at: now)
        }

        // Sealed on the inner display and then left alone (e.g. stopped at 58°): reveal after a beat.
        // Only when the phone is clearly open (≥ 100°): a press sealed at ~48° and left there is still mid-fold,
        // and the card would be unreadable. The user will close it (ka-chunk) or reopen it (reveal).
        if phase == .sealed && !isClosed && angle >= 100 && now - lastSampleTime > 0.25 {
            if let start = sealedRestStart {
                if now - start >= config.sealedRestReveal { beginReveal() }
            } else {
                sealedRestStart = now
            }
        } else {
            sealedRestStart = nil
        }

        if virtualReleasing {
            virtualAngle = min(180, virtualAngle + 300 * dt)
            ingestSample(angle: virtualAngle, closed: false, at: now, virtual: true)
            if virtualAngle >= 180 { virtualReleasing = false }
        }

        let age = now - lastSampleTime
        isHolding = age > 0.25 || abs(closingSpeed) < 3
        settleIfStale(now: now)
        // The drawn hinge (sync fix): the tracker read one display frame ahead of now, continuous between reports.
        if dt > 0 { frameInterval += (min(dt, 0.1) - frameInterval) * 0.2 }
        let drawLead = min(frameInterval, 1.0 / 30)
        if tracker.estimate != nil {
            displayAngle = tracker.angle(at: now + drawLead)
            displaySpeed = tracker.closingSpeed(at: now + drawLead)
        } else {
            displayAngle = angle
            displaySpeed = 0
        }
        if lastSampleVirtual != nil, now - activationTime >= config.ignoreInputAfterActivation {
            trackDetents(displayAngle)
        }
        updateTension(at: now)
        updateHingePower(dt: dt)

        // The render depth follows the drawn hinge directly: no spring on the hand's path (a spring is pure lag),
        // only on real jumps (arming, the seal, the reveal on the touch press). The give's 80 ms ramp is its own.
        let hinge = lastSampleVirtual == false
        let target: Double
        var follows = false
        switch phase {
        case .idle:
            target = 0
        case .revealing:
            // On the Duo the lid lifts with the hand: the release tracks the angle in real time.
            target = hinge && !isClosed ? PressMapping.depth(angle: displayAngle, start: startAngle, config: mapping) : 0
            follows = hinge
        case .armed, .pressing:
            target = eyeDepth(PressMapping.depth(angle: displayAngle, start: startAngle, config: mapping))
            follows = true
            if phase == .pressing, let material {
                // The give ratchets the plastic part with it (as the eye sees it).
                plasticDepth = max(plasticDepth, eyeDepth(measuredDepth) * material.plasticity)
            }
        case .sealed:
            // Sealed and opening again before the reveal: the lid still tracks the hand (the object stays as flat as
            // its plastic part).
            target = hinge && !isClosed ? PressMapping.depth(angle: displayAngle, start: startAngle, config: mapping) : 1
            follows = hinge
        }
        if follows && abs(target - renderDepth) < Self.followJump {
            spring.value = target
            spring.velocity = 0
        } else {
            var omega = config.springOmega
            if let since = sinceBurst, since < resistance.give + 0.06, resistance.lags { omega = max(omega, 70) }
            spring.step(toward: target, omega: omega, dt: dt)
        }
        renderDepth = clamp(spring.value, 0, 1)
        updatePipeline(now: now, dt: dt)
    }

    /// A render-depth change bigger than this in one frame is a jump (springs); smaller ones are the hand (snaps).
    static let followJump = 0.04

    /// The hinge stopped reporting (a still Duo sends nothing): the event filter would rest short of the real lid by
    /// its lag, so feed it the last raw reading at frame rate until it lands (no sample bookkeeping changes).
    private func settleIfStale(now: Double) {
        guard lastSampleVirtual == false, phase == .armed || phase == .pressing, !isClosed,
              now - lastSampleTime > max(0.06, 1.5 * sampleInterval), abs(rawAngle - angle) > 0.02,
              now - activationTime >= config.ignoreInputAfterActivation else { return }
        let settled = filter.filter(rawAngle, at: now)
        angle = settled
        closingSpeed = -filter.derivative
        if phase == .pressing { updatePress(angle: settled, at: now) }
    }

    private func updatePipeline(now: Double, dt: Double) {
        var stats = PipelineStats()
        stats.sampleAge = lastSampleTime.isFinite ? now - lastSampleTime : 0
        stats.hingeRate = lastSampleVirtual == nil ? 0 : 1 / max(sampleInterval, 1e-3)
        stats.filterLag = rawAngle - angle
        stats.drawnVsRaw = displayAngle - rawAngle
        if phase == .pressing || phase == .armed {
            stats.renderVsRaw = PressMapping.angle(forDepth: renderDepth, start: startAngle, config: mapping) - rawAngle
        }
        stats.displayRate = frameInterval > 0 ? 1 / frameInterval : 0
        pipeline = stats
    }

    // MARK: - Feel (Core/PressFeel.swift)

    /// The compression the eye sees for hand compression `c`: 1:1, then lagging inside the resistance window, frozen
    /// from the crossing through the hit stop, then released to the hand over `resistance.give` at the burst.
    func eyeCompression(_ c: Double) -> Double {
        guard resistance.lags, let failure = failureThreshold else { return c }
        if let since = sinceBurst {
            return resistance.released(from: heldEyeCompression ?? c, to: c, after: since)
        }
        let lagged = resistance.lagged(c, failure: failure)
        if let held = heldEyeCompression { return min(held, lagged) }
        return lagged
    }

    /// `eyeCompression` as a depth (the free approach before contact is untouched).
    private func eyeDepth(_ depth: Double) -> Double {
        let contact = mapping.contactT
        guard depth > contact, contact < 1 else { return depth }
        let c = (depth - contact) / (1 - contact)
        return contact + (1 - contact) * eyeCompression(min(c, 1))
    }

    /// Tension you can hold (EXPERIENCE-2 §A1.3): the level never decays on a hold, and a held, loaded press creaks
    /// every 0.6–1.2 s until it fails.
    private func updateTension(at now: Double) {
        let c = measuredCompression
        let loaded = phase == .pressing && c > 0
        let broken = crossedAt != nil
        isTelling = tellFired && !broken
        tension = loaded ? HoldTension.level(compression: c, failure: failureThreshold, failed: broken, inTell: isTelling) : 0
        isHeldUnderLoad = loaded && isHolding && !broken
        guard isHeldUnderLoad else {
            nextCreakAt = nil
            return
        }
        guard let due = nextCreakAt else {
            nextCreakAt = now + HoldTension.firstCreak
            return
        }
        if now >= due {
            creakCount &+= 1
            onBeat?(.creak(intensity: tension))
            let roll = Double.random(in: 0...1, using: &creakRNG)
            nextCreakAt = now + HoldTension.creakInterval(level: tension, roll: roll)
        }
    }

    private func fireBeats(upTo time: Double) {
        while let first = pendingBeats.first, first.time <= time {
            pendingBeats.removeFirst()
            onBeat?(first.beat)
        }
    }

    /// Captures this press's mapping at arm: the floating contact, and which input (touch or hinge) it maps.
    private func captureMapping(hinge: Bool) {
        armedOnHinge = hinge
        armedContactT = config.armed(at: startAngle, hinge: hinge).contactT
    }

    /// Called when the reveal is done; the director loads the next object.
    func finishReveal() {
        guard phase == .revealing else { return }
        phase = .idle
    }

    // MARK: - Internals

    private func emit(_ event: PressEvent) {
        onEvent?(event)
    }

    /// Arms on the latest reading. A hinge press needs an observed open sample ≥ `armAngleMin` (FOLD-REVIEW-6 N3):
    /// before any sample, `angle` is the 180° default, not the hinge. Only the touch press may arm without one (its
    /// first-press teaching cue needs `.armed`), and that arm is provisional (see `armObserved`).
    private func tryArm(at time: Double) {
        guard material != nil, lastSampleVirtual != nil || usesVirtualHinge, !isClosed, angle >= config.armAngleMin,
              time - activationTime >= config.ignoreInputAfterActivation else { return }
        armObserved = lastSampleVirtual != nil
        startAngle = min(angle, config.armAngleMax)
        // Before any sample the arm is the touch press's (provisional, re-anchored by the first reading).
        captureMapping(hinge: lastSampleVirtual == false)
        phase = .armed
        emit(.armed)
    }

    private func updatePress(angle θ: Double, at time: Double) {
        guard let material else { return }
        let depth = PressMapping.depth(angle: θ, start: startAngle, config: mapping)
        measuredDepth = depth
        maxDepthReached = max(maxDepthReached, depth)
        let c = PressMapping.compression(depth: depth, config: mapping)
        if failureThresholdAngle == nil, let failure = failureThreshold {
            let m = mapping
            failureThresholdAngle = PressMapping.angle(forDepth: m.contactT + (1 - m.contactT) * failure,
                                                       start: startAngle, config: m)
        }

        if !contactFired && depth >= mapping.contactT {
            contactFired = true
            emit(.contact)
        }

        let fresh = c >= maxCompression - 0.01
        if c > maxCompression {
            advanceCompression(to: c, angle: θ, at: time)
        }
        // The plastic ratchet follows the eye, so "lag, then give" isn't undone by it (honest depth: `measuredDepth`).
        plasticDepth = max(plasticDepth, eyeDepth(depth) * material.plasticity)

        if c > 0 {
            peakClosingSpeed = max(peakClosingSpeed, closingSpeed)
            if closingSpeed < -8 {
                reversedWhileLoaded = true
                if !isReversing {
                    isReversing = true
                    reversals += 1
                }
            }
        }
        if closingSpeed > 3 { isReversing = false }

        if closingSpeed > 0 && c > 0 && fresh && !inRigidPlateau(c, material: material) {
            releaseFired = false
            emitGrains(angle: θ, compression: c, spacing: material.grainSpacing)
        } else if closingSpeed < -10 {
            nextGrainAngle = nil
            if c > 0 && !releaseFired {
                releaseFired = true
                emit(.released)
            }
        }

        if !bottomFired && depth >= config.sealDepth {
            bottomFired = true
            emit(.bottomOut)
        }
    }

    private func inRigidPlateau(_ c: Double, material: MaterialProfile) -> Bool {
        guard let stop = material.grainStopC, let failure = material.failureIndex else { return false }
        return c >= stop && firedCount <= failure
    }

    private func emitGrains(angle θ: Double, compression c: Double, spacing: Double) {
        if nextGrainAngle == nil { nextGrainAngle = θ - spacing }
        var emitted = 0
        while let next = nextGrainAngle, θ <= next, emitted < 4 {
            emit(.grain(compression: c))
            nextGrainAngle = next - spacing
            emitted += 1
        }
        // After a big jump between samples, drop the backlog rather than machine-gunning grains.
        if let next = nextGrainAngle, θ <= next { nextGrainAngle = θ - spacing }
    }

    private func advanceCompression(to c: Double, angle θ: Double, at time: Double) {
        guard let material else { return }
        maxCompression = c
        // The tell: ~150–300 ms before the predicted crossing, or once very near it (a crawl or a hold), or at the
        // crossing itself for a slam (the hush + hit stop still leave ≥ 120 ms before the burst).
        if let failure = material.failureIndex, !tellFired, failure < thresholds.count, firedCount <= failure {
            let threshold = thresholds[failure]
            let fire = c >= threshold || PressTell.shouldFire(compression: c, failure: threshold, angle: θ,
                                                              failureAngle: failureThresholdAngle ?? θ,
                                                              closingSpeed: filteredSpeed)
            if fire {
                tellFired = true
                isTelling = true
                emit(.preFailureTell)
            }
        }
        while firedCount < thresholds.count && c >= thresholds[firedCount] {
            // Nothing fires inside the break's hush and hit stop: the break comes first, and any fractures the
            // press passes meanwhile queue until the burst (the Crayon Box's snaps are only 0.04 c apart).
            if pendingFailure != nil { break }
            let index = firedCount
            firedCount += 1
            if index == material.failureIndex {
                // Break part 1, the hush. The eye freezes at peak strain (lagged) until the burst gives.
                failureAngle = θ
                heldEyeCompression = resistance.lags ? resistance.lagged(c, failure: thresholds[index]) : nil
                crossedAt = time
                isTelling = false
                emit(.hush)
                // Part 2, the hit stop, then part 3, the burst.
                pendingBeats.append((time: time + breakScore.hush, beat: PressBeat.hitStop(duration: breakScore.hitStop)))
                pendingFailure = (index, time + breakScore.burst)
            } else {
                emit(.fracture(index: index, isFailure: false))
            }
        }
    }

    /// The burst (break part 3), at `time`: on schedule from `step`, or at once when the press is sealed or closed
    /// first. Schedules parts 4–5 (slow debris, settle) from it.
    private func flushPendingFailure(at time: Double) {
        guard let pending = pendingFailure else { return }
        pendingFailure = nil
        // A burst brought forward (sealed / closed mid-score) skips the rest of the hit stop.
        pendingBeats.removeAll { if case .hitStop = $0.beat { return true } else { return false } }
        if crossedAt == nil { crossedAt = time }
        burstAt = time
        pendingBeats += breakScore.beatsAfterBurst().map { (time: time + $0.time, beat: $0.beat) }
        pendingBeats.sort { $0.time < $1.time }
        emit(.fracture(index: pending.index, isFailure: true))
        // The fractures the press passed during the hush and hit stop, in order, right after the burst.
        while firedCount < thresholds.count && maxCompression >= thresholds[firedCount] {
            let index = firedCount
            firedCount += 1
            emit(.fracture(index: index, isFailure: false))
        }
    }

    private func handleClose(at time: Double) {
        switch phase {
        case .armed, .pressing:
            // Closed mid-press (the inner screen is dark by now): finish the crush blind. Only a press the user made:
            // it got somewhere, or an arm resting on an observed open sample was slammed shut between two samples.
            // A provisional arm (no reading yet, e.g. launched with the phone shut) never seals (FOLD-REVIEW-6 N3).
            guard maxDepthReached > 0.05 || (armObserved && rawAngle <= config.endAngle) else { return }
            fastForward(at: time)
            seal(blind: true, at: time)
            emit(.kaChunk)
        case .sealed:
            emit(.kaChunk)
        case .idle, .revealing:
            break
        }
    }

    /// Drop an arm that nothing was pressed on; `tryArm` re-arms from the next open reading.
    private func disarm() {
        phase = .idle
        armObserved = false
        armedContactT = nil
        armedOnHinge = false
        nextGrainAngle = nil
    }

    private func fastForward(at time: Double) {
        guard let material else { return }
        if !contactFired {
            contactFired = true
            emit(.contact)
        }
        measuredDepth = 1
        maxDepthReached = 1
        plasticDepth = max(plasticDepth, material.plasticity)
        if failureAngle == nil, let failure = material.failureIndex, firedCount <= failure {
            failureAngle = rawAngle
        }
        advanceCompression(to: 1, angle: rawAngle, at: time)
        flushPendingFailure(at: time)
        if !bottomFired {
            bottomFired = true
            emit(.bottomOut)
        }
    }

    private func seal(blind: Bool, at time: Double) {
        guard phase != .sealed, let kind else { return }
        flushPendingFailure(at: time)
        phase = .sealed
        shutSinceSeal = blind || isClosed
        sealHoldStart = nil
        let duration = pressStartTime.map { time - $0 } ?? 0
        let slammed = peakClosingSpeed > config.slamSpeed
        lastResult = PressResult(
            kind: kind,
            seed: seed,
            failureAngle: failureAngle,
            fractureCount: firedCount,
            maxCompression: maxCompression,
            duration: duration,
            wasSlammed: slammed,
            isPerfect: !slammed && !reversedWhileLoaded && peakClosingSpeed <= config.perfectMaxSpeed && duration >= 2,
            reversals: reversals
        )
        emit(.sealed(blind: blind))
        if usesVirtualHinge {
            emit(.kaChunk)
            autoRevealTime = time + 0.7
        }
    }

    private func beginReveal() {
        guard phase == .sealed else { return }
        phase = .revealing
        emit(.reveal)
    }
}
