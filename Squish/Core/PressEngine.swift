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
    /// The final stretch before the big failure: tremor and accelerating micro-cracks.
    case preFailureTell
    /// Emitted `failureHushDelay` before the failure: beds and grains drop to silence.
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

    /// Depth from the latest filtered sample. Drives every irreversible event.
    private(set) var measuredDepth = 0.0
    /// Spring-smoothed depth at render rate. Drives the ram.
    private(set) var renderDepth = 0.0
    /// The plastic part of the deformation, ratcheted. The object never re-inflates past this.
    private(set) var plasticDepth = 0.0
    private(set) var maxCompression = 0.0
    private(set) var lastResult: PressResult?

    /// True when input comes from the touch fallback instead of a real hinge.
    var usesVirtualHinge = false

    var visualDepth: Double { max(plasticDepth, renderDepth) }
    var renderCompression: Double { PressMapping.compression(depth: renderDepth, config: config) }
    var visualCompression: Double { PressMapping.compression(depth: visualDepth, config: config) }
    var measuredCompression: Double { PressMapping.compression(depth: measuredDepth, config: config) }
    var isLoaded: Bool { phase == .pressing && measuredCompression > 0 }
    /// True when hinge samples arrive slower than ~10 Hz.
    var isLowRate: Bool { !usesVirtualHinge && sampleInterval > 0.1 }

    @ObservationIgnored var onEvent: ((PressEvent) -> Void)?

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
    @ObservationIgnored private var failureAngle: Double?
    @ObservationIgnored private var peakClosingSpeed = 0.0
    @ObservationIgnored private var reversedWhileLoaded = false
    @ObservationIgnored private var isReversing = false
    @ObservationIgnored private var reversals = 0
    /// Recent hinge sample intervals, for the low-rate mode (bible §6.1).
    @ObservationIgnored private var sampleInterval = 1.0 / 30.0
    @ObservationIgnored private var virtualAngle = 180.0
    @ObservationIgnored private var virtualReleasing = false

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
        phase = .idle
        tryArm(at: time)
    }

    // MARK: - Input

    /// Feed one hinge sample (degrees, 180 = flat).
    func ingest(angle raw: Double, closed: Bool, at time: Double) {
        rawAngle = raw
        // Read tunables every sample so Tuning Lab changes apply live.
        filter.minCutoff = config.oneEuroMinCutoff
        filter.beta = config.oneEuroBeta
        filter.dCutoff = config.oneEuroDCutoff
        let filtered = filter.filter(raw, at: time)
        angle = filtered
        closingSpeed = -filter.derivative
        if lastSampleTime.isFinite {
            let interval = time - lastSampleTime
            if interval > 0 && interval < 1 {
                sampleInterval += (interval - sampleInterval) * 0.2
            }
        }
        lastSampleTime = time
        let wasClosed = isClosed
        isClosed = closed

        guard time - activationTime >= config.ignoreInputAfterActivation else { return }

        if closed && !wasClosed {
            handleClose(at: time)
        }

        switch phase {
        case .idle:
            tryArm(at: time)
        case .armed:
            guard !closed else { break }
            if filtered > startAngle {
                startAngle = min(filtered, config.armAngleMax)
            }
            if filtered <= startAngle - config.hysteresis {
                phase = .pressing
                if pressStartTime == nil { pressStartTime = time }
                updatePress(angle: filtered, at: time)
            }
        case .pressing:
            guard !closed else { break }
            updatePress(angle: filtered, at: time)
            if filtered >= startAngle + config.hysteresis && measuredDepth < 0.05 {
                phase = .armed
                nextGrainAngle = nil
            }
        case .sealed:
            // Reveal as soon as the phone is opened (the system switches displays at that moment),
            // or once it's clearly open again.
            if !closed && (wasClosed || filtered >= config.revealAngle) {
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
        ingest(angle: virtualAngle, closed: false, at: time)
    }

    /// Touch fallback: the finger lifted, so the virtual press springs open.
    func releaseVirtual() {
        virtualReleasing = true
    }

    // MARK: - Per frame

    func step(now: Double, dt: Double) {
        if let pendingTime = pendingFailure?.time, now >= pendingTime {
            flushPendingFailure()
        }

        if phase == .pressing {
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

        // Arm without waiting for an input sample: a Duo lying still sends none, and the
        // first-press teaching cues only appear once the press is armed.
        if phase == .idle {
            tryArm(at: now)
        }

        // Sealed on the inner display and then left alone (e.g. stopped at 58°): reveal after a beat.
        if phase == .sealed && !isClosed && now - lastSampleTime > 0.25 {
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
            ingest(angle: virtualAngle, closed: false, at: now)
            if virtualAngle >= 180 { virtualReleasing = false }
        }

        let age = now - lastSampleTime
        isHolding = age > 0.25 || abs(closingSpeed) < 3

        let target: Double
        switch phase {
        case .idle, .revealing:
            target = 0
        case .armed, .pressing:
            // Predict a little ahead while samples are fresh; hold still when they stop.
            // Low-rate mode: when samples arrive slower than ~10 Hz (thermal, Low Power), don't predict.
            let fresh = age < max(config.staleAfter, sampleInterval * 1.5)
            let lead = fresh && !isLowRate ? min(age + 1.0 / 60.0, config.maxPredict) : 0
            target = PressMapping.depth(angle: angle - closingSpeed * lead, start: startAngle, config: config)
        case .sealed:
            target = 1
        }
        let omega = isLowRate ? config.springOmega * 0.6 : config.springOmega
        spring.step(toward: target, omega: omega, dt: dt)
        renderDepth = clamp(spring.value, 0, 1)
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

    private func tryArm(at time: Double) {
        guard material != nil, !isClosed, angle >= config.armAngleMin,
              time - activationTime >= config.ignoreInputAfterActivation else { return }
        startAngle = min(angle, config.armAngleMax)
        phase = .armed
        emit(.armed)
    }

    private func updatePress(angle θ: Double, at time: Double) {
        guard let material else { return }
        let depth = PressMapping.depth(angle: θ, start: startAngle, config: config)
        measuredDepth = depth
        maxDepthReached = max(maxDepthReached, depth)
        plasticDepth = max(plasticDepth, depth * material.plasticity)
        let c = PressMapping.compression(depth: depth, config: config)

        if !contactFired && depth >= config.contactT {
            contactFired = true
            emit(.contact)
        }

        let fresh = c >= maxCompression - 0.01
        if c > maxCompression {
            advanceCompression(to: c, angle: θ, at: time)
        }

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
        if let failure = material.failureIndex, !tellFired, failure < thresholds.count,
           firedCount <= failure, c >= thresholds[failure] - 0.08 {
            tellFired = true
            emit(.preFailureTell)
        }
        while firedCount < thresholds.count && c >= thresholds[firedCount] {
            let index = firedCount
            firedCount += 1
            if index == material.failureIndex {
                failureAngle = θ
                emit(.hush)
                pendingFailure = (index, time + config.failureHushDelay)
            } else {
                emit(.fracture(index: index, isFailure: false))
            }
        }
    }

    private func flushPendingFailure() {
        guard let pending = pendingFailure else { return }
        pendingFailure = nil
        emit(.fracture(index: pending.index, isFailure: true))
    }

    private func handleClose(at time: Double) {
        switch phase {
        case .armed, .pressing:
            // Closed mid-press (the inner screen is dark by now): finish the crush blind.
            guard maxDepthReached > 0.05 || rawAngle <= config.endAngle else { return }
            fastForward(at: time)
            seal(blind: true, at: time)
            emit(.kaChunk)
        case .sealed:
            emit(.kaChunk)
        case .idle, .revealing:
            break
        }
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
        flushPendingFailure()
        if !bottomFired {
            bottomFired = true
            emit(.bottomOut)
        }
    }

    private func seal(blind: Bool, at time: Double) {
        guard phase != .sealed, let kind else { return }
        flushPendingFailure()
        phase = .sealed
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
