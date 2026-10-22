import Observation
import QuartzCore
import RealityKit

/// Wires the press engine to the scene, haptics and audio, and owns the per-frame loop.
@MainActor
@Observable
final class PressDirector {
    let engine: PressEngine
    @ObservationIgnored let scene = PressScene()
    @ObservationIgnored let haptics = HapticsController()
    @ObservationIgnored let audio = AudioController()
    @ObservationIgnored let hingeLog = HingeLog()
    @ObservationIgnored var frameSubscription: EventSubscription?

    private(set) var currentKind: ObjectKind = .bubbleWrap
    private(set) var hingeAvailable = false
    /// Increments on every big failure; the UI flashes the top half of the screen.
    private(set) var failureFlashCount = 0
    private(set) var revealResult: PressResult?
    private(set) var completedPresses = 0

    @ObservationIgnored private var started = false

    init() {
        engine = PressEngine(config: .loadSaved())
        engine.onEvent = { [weak self] event in self?.handle(event) }
    }

    var isShowingCover: Bool { hingeAvailable && engine.isClosed }

    var canChooseObject: Bool {
        !isShowingCover && revealResult == nil
            && (engine.phase == .idle || engine.phase == .armed) && engine.measuredDepth < 0.01
    }

    func start() {
        guard !started else { return }
        started = true
        audio.start()
        haptics.start()
        engine.activate(at: CACurrentMediaTime())
        load(.bubbleWrap)
        if let demo = DemoScenario.current {
            runDemo(demo)
        }
    }

    /// Drives the touch fallback to a scripted state for screenshots (see DemoMode.swift).
    private func runDemo(_ demo: DemoScenario) {
        engine.config.ignoreInputAfterActivation = 0
        hingeUnavailable()
        if let kind = demo.object { load(kind) }
        let targetDepth: Double? = demo.has("reveal") ? 1 : demo.double("depth")
        guard let targetDepth else { return }
        let targetAngle = PressMapping.angle(forDepth: targetDepth, start: engine.config.armAngleMax, config: engine.config)
        Task { @MainActor in
            virtualPress(0)
            try? await Task.sleep(for: .milliseconds(300))
            let steps = 90
            for step in 1...steps {
                let angle = 180 + (targetAngle - 180) * Double(step) / Double(steps)
                virtualPress((180 - angle) / 180)
                try? await Task.sleep(for: .milliseconds(16))
            }
            // Keep feeding the held angle so the filter settles exactly on target.
            for _ in 0..<30 {
                virtualPress((180 - targetAngle) / 180)
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    func sceneBecameActive() {
        guard started else { return }
        engine.activate(at: CACurrentMediaTime())
        haptics.resume()
        audio.resume()
    }

    func choose(_ kind: ObjectKind) {
        guard canChooseObject, kind != currentKind else { return }
        load(kind)
    }

    /// Collect the revealed specimen and put the next object on the anvil.
    func next() {
        audio.collect()
        haptics.collect()
        engine.finishReveal()
        revealResult = nil
        let all = ObjectKind.allCases
        let index = all.firstIndex(of: currentKind) ?? 0
        load(all[(index + 1) % all.count])
    }

    // MARK: - Input

    func hingeUpdate(angle: Double, closed: Bool) {
        if !hingeAvailable {
            hingeAvailable = true
            engine.usesVirtualHinge = false
        }
        let now = CACurrentMediaTime()
        hingeLog.record(time: now, angle: angle, closed: closed)
        engine.ingest(angle: angle, closed: closed, at: now)
    }

    func hingeUnavailable() {
        hingeAvailable = false
        engine.usesVirtualHinge = true
    }

    /// Touch fallback: 0 = open, 1 = fully pressed.
    func virtualPress(_ fraction: Double) {
        engine.setVirtualAngle(180 - clamp(fraction, 0, 1) * 180, at: CACurrentMediaTime())
    }

    func virtualRelease() {
        engine.releaseVirtual()
    }

    // MARK: - Loop

    func frame(dt: TimeInterval) {
        let config = engine.config
        haptics.scale = Float(config.hapticsScale)
        audio.enabled = config.soundEnabled
        audio.volume = Float(config.soundVolume)

        engine.step(now: CACurrentMediaTime(), dt: dt)
        scene.update(engine: engine)
        haptics.update(engine: engine)
        audio.update(engine: engine)
    }

    private func load(_ kind: ObjectKind) {
        currentKind = kind
        let seed = UInt64.random(in: 1...UInt64.max)
        engine.load(kind, seed: seed, at: CACurrentMediaTime())
        scene.setObject(kind, seed: seed)
        audio.place(kind)
        haptics.place()
    }

    private func handle(_ event: PressEvent) {
        scene.handle(event)
        haptics.handle(event, kind: currentKind)
        audio.handle(event, kind: currentKind)
        switch event {
        case .fracture(_, true):
            failureFlashCount += 1
        case .reveal:
            revealResult = engine.lastResult
            completedPresses += 1
        default:
            break
        }
    }
}

/// Raw hinge samples for on-device tuning: update rate, quantisation, and the angles where the display switches.
@MainActor
final class HingeLog {
    struct Sample {
        let time: Double
        let angle: Double
        let closed: Bool
    }

    private(set) var samples: [Sample] = []
    private let capacity = 6000

    func record(time: Double, angle: Double, closed: Bool) {
        samples.append(Sample(time: time, angle: angle, closed: closed))
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }

    /// Updates per second over the most recent second of samples.
    var recentRate: Double {
        guard let last = samples.last else { return 0 }
        return Double(samples.reversed().prefix { last.time - $0.time <= 1 }.count)
    }

    func csv() -> String {
        guard let first = samples.first else { return "time,angle,closed\n" }
        var lines = ["time,angle,closed"]
        for sample in samples {
            lines.append(String(format: "%.4f,%.2f,%d", sample.time - first.time, sample.angle, sample.closed ? 1 : 0))
        }
        return lines.joined(separator: "\n")
    }

    func clear() {
        samples.removeAll()
    }
}
