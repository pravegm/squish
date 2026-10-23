import Foundation
import Observation
import QuartzCore
import UIKit

/// FOLD-REVIEW-7 N10: when the inner display can't be seen, the inner scene stops rendering.
///
/// The first rule that applies is the reason:
///  • `window`     the stage isn't in a window;
///  • `background` the scene is in the background;
///  • `closed`     the hinge reads closed (the `PressEngine.staleClosedAngle` rule: a `closed` flag above 90° is stale);
///  • `size`       the window isn't something to draw the stage in: zero size, the 466 × 678 cover display, or a stage
///                 that was never laid out;
///  • `inactive`   the scene has been inactive for `inactiveGrace` (Control Center, a call). Not when the hinge opened
///                 during that spell or just before it: on a Duo, folding can toggle scene activity
///                 (PressDirector.sceneBecameActive), and a reopen must render at once, not when the scene reactivates.
/// Pure, so the rules are unit-tested (FoldPressTests).
struct InnerDisplayPolicy {
    enum Activation: Equatable { case active, inactive, background }
    enum Reason: String { case visible, window, background, closed, size, inactive }

    struct Inputs: Equatable {
        var inWindow: Bool
        var canvasOK: Bool
        var shut: Bool
        var activation: Activation
    }

    /// An inactive spell shorter than this never pauses.
    static let inactiveGrace = 0.3
    /// A reopen this soon before an inactive spell (or during it) keeps the stage rendering through it.
    static let reopenWindow = 1.5

    private(set) var reason: Reason = .visible
    var rendering: Bool { reason == .visible }
    private var inactiveSince: Double?
    private var lastOpened: Double?
    private var wasShut = false

    @discardableResult
    mutating func evaluate(_ input: Inputs, now: Double) -> Reason {
        if wasShut && !input.shut { lastOpened = now }
        wasShut = input.shut
        if input.activation == .inactive {
            if inactiveSince == nil { inactiveSince = now }
        } else {
            inactiveSince = nil
        }
        if !input.inWindow {
            reason = .window
        } else if input.activation == .background {
            reason = .background
        } else if input.shut {
            reason = .closed
        } else if !input.canvasOK {
            reason = .size
        } else if let since = inactiveSince, now - since >= Self.inactiveGrace,
                  !(lastOpened.map { $0 >= since - Self.reopenWindow } ?? false) {
            reason = .inactive
        } else {
            reason = .visible
        }
        return reason
    }

    /// The Duo inner canvas (669 × 951 / 951 × 669 pt) and nothing smaller: the zero-size window and the 466 × 678 cover
    /// display fail. The same test as `FoldStageHostView.layoutSubviews`.
    static func isInnerCanvas(_ size: CGSize) -> Bool {
        min(size.width, size.height) >= 320 && max(size.width, size.height) >= 800
    }
}

/// Drives one inner ARView's frame loop through `InnerDisplayPolicy` (FOLD-REVIEW-7 N10).
///
/// - Visible: the ARView's `SceneEvents.Update` ticks drive `onFrame` (rendered = true), as before.
/// - Hidden: `onPausedChange(true)` lets the host take its ARView out of the window (RealityKit only renders a view
///   that is in a window), and a blind clock keeps `onFrame` (rendered = false) running, so the engine, haptics and
///   audio carry on: a slam-shut press still seals blind, the ka-chunk and its scheduled taps play on time, and a
///   queued object lands. 60 Hz while a press is live and for 1.5 s after one (cue schedules), then 20 Hz, then 10 Hz
///   after 5 s (dt stays ≤ 0.1 s, which every consumer clamps to).
/// - Resume: on the first open hinge sample (observed, not polled: `watch`), on a layout into the inner canvas, or on
///   scene activation. The ARView goes back in the window at once and one catch-up frame runs before it renders, so the
///   first frame on the relit display is already the current state. Log lines `SQUISH-F paused` / `SQUISH-F resumed`
///   (demo runs) let CI check it.
@MainActor
final class InnerRenderGate {
    /// For the logs: "fold" or "p48".
    let name: String
    private(set) var isPaused = false
    private(set) var reason: InnerDisplayPolicy.Reason = .visible

    /// The per-frame loop (`director.frame(dt:)`): `rendered` is false for blind-clock frames.
    var onFrame: ((_ dt: Double, _ rendered: Bool) -> Void)?
    /// true: take the ARView out of the window; false: put it back (called before the catch-up frame).
    var onPausedChange: ((Bool) -> Void)?
    /// The host's inputs; the scene activation is tracked here.
    var sample: (() -> (inWindow: Bool, canvasOK: Bool, shut: Bool))?
    /// True while a press is live (the blind clock stays at 60 Hz for the haptic bed and audio schedules).
    var busy: (() -> Bool)?
    /// Reads the observable inputs (the hinge's closed flag) under observation tracking, so a change re-evaluates on
    /// the next main-actor turn instead of at the next blind tick.
    var watch: (() -> Void)?

    private var policy = InnerDisplayPolicy()
    private var activation: InnerDisplayPolicy.Activation = .active
    private var observers: [NSObjectProtocol] = []
    private var blindTask: Task<Void, Never>?
    private var started = false
    private var pausedAt: Double = 0
    private var lastBlindTick: Double = 0
    private var lastBusy: Double = 0
    private var blindFrames = 0
    private var strayTicks = 0
    private var ticksSinceResume = 0

    init(name: String) {
        self.name = name
    }

    func start() {
        guard !started else { return }
        started = true
        activation = UIApplication.shared.applicationState == .background ? .background : .active
        let center = NotificationCenter.default
        let changes: [(Notification.Name, InnerDisplayPolicy.Activation)] = [
            (UIScene.didActivateNotification, .active),
            (UIScene.willDeactivateNotification, .inactive),
            (UIScene.willEnterForegroundNotification, .inactive),
            (UIScene.didEnterBackgroundNotification, .background),
        ]
        for (name, state) in changes {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let gate = self else { return }
                    gate.activation = state
                    gate.evaluate()
                }
            })
        }
        observe()
        evaluate()
    }

    func stop() {
        started = false
        blindTask?.cancel()
        blindTask = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        onFrame = nil
        onPausedChange = nil
        sample = nil
        busy = nil
        watch = nil
    }

    /// From the ARView's `SceneEvents.Update`.
    func renderTick(dt: Double) {
        evaluate()
        if isPaused {
            strayTicks += 1   // RealityKit still ticking a parked view: logged on resume
            return
        }
        ticksSinceResume += 1   // (a pending catch-up frame is skipped: this tick is the frame)
        onFrame?(dt, true)
    }

    /// Re-reads the inputs; pauses or resumes as needed. Cheap: call it on layout, window moves and notifications.
    func evaluate() {
        guard started else { return }
        let s = sample?() ?? (inWindow: true, canvasOK: true, shut: false)
        let input = InnerDisplayPolicy.Inputs(inWindow: s.inWindow, canvasOK: s.canvasOK, shut: s.shut,
                                              activation: activation)
        let now = CACurrentMediaTime()
        reason = policy.evaluate(input, now: now)
        if policy.rendering {
            if isPaused { resume(now: now) }
        } else if !isPaused {
            pause(now: now)
        }
    }

    // MARK: - Internals

    private func pause(now: Double) {
        isPaused = true
        pausedAt = now
        lastBlindTick = now
        lastBusy = now
        blindFrames = 0
        strayTicks = 0
        log("paused \(name) reason=\(reason.rawValue)")
        onPausedChange?(true)
        startBlindClock()
    }

    private func resume(now: Double) {
        isPaused = false
        blindTask?.cancel()
        blindTask = nil
        log(String(format: "resumed %@ after=%.2fs blind=%ld stray=%ld", name, now - pausedAt, blindFrames, strayTicks))
        onPausedChange?(false)
        // The catch-up frame: brings the stage up to date before the view's first render. On the next main-actor turn
        // (never inside a layout pass or a SwiftUI update), skipped if a render tick got there first.
        ticksSinceResume = 0
        let dt = min(max(now - lastBlindTick, 1.0 / 120), 0.1)
        Task { @MainActor [weak self] in
            guard let gate = self, !gate.isPaused, gate.ticksSinceResume == 0 else { return }
            gate.onFrame?(dt, false)
        }
    }

    private func startBlindClock() {
        blindTask?.cancel()
        blindTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let interval = self?.blindInterval ?? 0.1
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled, let gate = self else { return }
                gate.blindTick()
            }
        }
    }

    private var blindInterval: Double {
        let now = CACurrentMediaTime()
        if busy?() == true { lastBusy = now }
        let quiet = now - max(pausedAt, lastBusy)
        if quiet < 1.5 { return 1.0 / 60 }
        return now - pausedAt < 5 ? 1.0 / 20 : 1.0 / 10
    }

    private func blindTick() {
        guard isPaused else { return }
        let now = CACurrentMediaTime()
        evaluate()   // the stale-closed angle and the inactive grace are only seen by polling
        guard isPaused else { return }   // resumed: the catch-up frame and the render ticks take over
        let dt = min(max(now - lastBlindTick, 0), 0.1)
        lastBlindTick = now
        blindFrames += 1
        onFrame?(dt, false)
    }

    private func observe() {
        guard started, let watch else { return }
        withObservationTracking {
            watch()
        } onChange: { [weak self] in
            // onChange runs before the new value is stored: re-read on the next main-actor turn.
            let gate = self
            Task { @MainActor in
                guard let gate, gate.started else { return }
                gate.observe()
                gate.evaluate()
            }
        }
    }

    private func log(_ message: String) {
        guard DemoScenario.current != nil else { return }
        print(String(format: "SQUISH-F %@ at %.2fs", message, CACurrentMediaTime() - SceneTrace.origin))
    }
}

/// FOLD-REVIEW-7 N10, reveal on relight. The inner display is dark from ~55° down to ~20° (research/05 §1.2), and a
/// reveal from the closed phone fires on the first open sample (~20°), inside that window. The stage resumes on that
/// sample, so the static diptych (print, specimen, the frozen green gauge) is drawn before the panel lights; the
/// reveal's *beats* (peel shimmer, goo strands, the PRESSED thunk, the anvil glint) wait for the light so they play in
/// view (FOLD-PRESS §6.2: "event-gated, not angle-gated"; §6.3 "0 ms: both halves are visible at once").
struct FoldRevealLight {
    /// The worst-case display-on angle (FOLD-PRESS §4.6: "the worst-case display-off angle (55°)").
    static let litAngle = 55.0
    /// The hinge holding still this long also counts as lit: the panel can't change state without motion, and 55° is a
    /// worst case on a ±5° sensor. Moves within `stillDegrees` are noise.
    static let stillHold = 0.6
    static let stillDegrees = 2.0

    private var anchorAngle: Double?
    private var anchorClock: Double = 0

    static func isDark(angle: Double) -> Bool { angle < litAngle }

    /// Feed every frame (the latest raw hinge reading).
    mutating func track(angle: Double, clock: Double) {
        if let anchor = anchorAngle, abs(angle - anchor) <= Self.stillDegrees { return }
        anchorAngle = angle
        anchorClock = clock
    }

    func isLit(angle: Double, clock: Double) -> Bool {
        !Self.isDark(angle: angle) || (anchorAngle != nil && clock - anchorClock >= Self.stillHold)
    }
}
