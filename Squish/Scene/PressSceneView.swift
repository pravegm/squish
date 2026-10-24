import Combine
import RealityKit
import SwiftUI
import UIKit

/// Hosts the press scene in a non-AR `ARView` (so `PressScene.snapshot()` can use `ARView.snapshot`)
/// and drives the per-frame loop from RealityKit's update event: `director.frame(dt:)` once per rendered frame.
/// 120 Hz needs `CADisableMinimumFrameDurationOnPhone` (set in project.yml).
///
/// FOLD-REVIEW-7 N10 (P-48 render gate): the ARView sits in a `PressSceneHostView`, which pauses it through an
/// `InnerRenderGate` while the display can't be seen, wired exactly like `FoldStageHostView`. That happens on a Duo
/// in the P-48 ("Press without folding") when the hinge reads shut, the window goes, or the scene is inactive or in
/// the background. On a regular iPhone (no hinge) the gate is never started, and an unstarted gate passes every render
/// tick straight through. So the P-48 there never pauses: as before, it stops only where RealityKit stops rendering
/// (no window, background).
struct PressSceneView: UIViewRepresentable {
    let director: PressDirector

    func makeUIView(context: Context) -> PressSceneHostView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(Palette.backdrop)
        // Nothing camera-like: no motion blur, grain or depth of field; we draw our own contact shadows.
        view.renderOptions.insert(.disableMotionBlur)
        view.renderOptions.insert(.disableCameraGrain)
        view.renderOptions.insert(.disableDepthOfField)
        view.renderOptions.insert(.disableGroundingShadows)
        view.backgroundColor = Palette.backdrop
        view.isMultipleTouchEnabled = true

        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(director.scene.root)
        view.scene.addAnchor(anchor)
        director.scene.attach(to: view)

        let host = PressSceneHostView(arView: view, scene: director.scene)
        let director = self.director
        // Touch on the object: a tap is the director's poke (Feedback answers in the material); a flick is a beat.
        host.onPoke = { [weak director] _ in director?.poke() }
        host.onSpin = { [weak director] turns in director?.engine.spun(turnsPerSecond: turns) }
        // RootView's `@AppStorage("squish.hasHinge")`: a hinge has reported on this device before.
        let knownHinge = UserDefaults.standard.bool(forKey: "squish.hasHinge")
        host.onFrame = { [weak director] dt in director?.frame(dt: dt) }
        host.startRenderGate(
            // Only a device with a hinge can have a display that's out of sight while the app runs (the Duo's inner
            // display while shut). Until one has reported, the gate stays off: a plain pass-through. (Read per frame
            // until then: one Bool.)
            hasHinge: { [weak director] in knownHinge || director?.hingeAvailable == true },
            // Shut = what the engine calls closed: a `closed` flag above 90° is stale (the Duo simulator keeps it set
            // to ~150° on reopen), and the reopen must never wait for it. The same rule as FoldPressView.
            shut: { [weak director] in
                guard let director else { return false }
                return director.isShowingCover && director.engine.rawAngle <= PressEngine.staleClosedAngle
            },
            busy: { [weak director] in director?.engine.phase == .pressing },
            watch: { [weak director] in _ = director?.hingeClosed })
        return host
    }

    func updateUIView(_ uiView: PressSceneHostView, context: Context) {}

    static func dismantleUIView(_ uiView: PressSceneHostView, coordinator: ()) {
        uiView.teardown()
    }
}

/// The P-48's container: the ARView fills it (autoresizing), and leaves it (parked) while the render gate pauses.
@MainActor
final class PressSceneHostView: UIView {
    let arView: ARView
    private weak var scene: PressScene?
    private var updates: Cancellable?
    var onFrame: ((Double) -> Void)?
    /// FOLD-REVIEW-7 N10: pauses this ARView (out of the window) while the display can't be seen. Hinge devices only.
    private let gate = InnerRenderGate(name: "p48")
    /// The ARView is out of the window (paused).
    private(set) var isParked = false
    private var gateStarted = false
    private var hasHinge: (() -> Bool)?
    /// The hinge reads shut (set by `startRenderGate`).
    private var isShut: (() -> Bool)?
    private var pendingBusy: (() -> Bool)?
    private var pendingWatch: (() -> Void)?

    init(arView: ARView, scene: PressScene) {
        self.arView = arView
        self.scene = scene
        super.init(frame: .zero)
        backgroundColor = Palette.backdrop
        isMultipleTouchEnabled = true
        arView.frame = bounds
        arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(arView)

        updates = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            let dt = event.deltaTime
            MainActor.assumeIsolated {
                self?.renderTick(dt: dt)
            }
        }
        gate.onFrame = { [weak self] dt, _ in self?.onFrame?(dt) }
        gate.onPausedChange = { [weak self] paused in self?.setParked(paused) }
        gate.sample = { [weak self] in
            guard let self else { return (inWindow: false, canvasOK: false, shut: false) }
            return (inWindow: self.window != nil,
                    canvasOK: self.bounds.width > 1 && self.bounds.height > 1,
                    shut: self.isShut?() ?? false)
        }
        for recognizer in [spinPan, pokeTap, zoomPinch] as [UIGestureRecognizer] {
            recognizer.delegate = self
            recognizer.cancelsTouchesInView = false
            addGestureRecognizer(recognizer)
        }
        spinPan.maximumNumberOfTouches = 1
    }

    // MARK: - Touch on the object (founder, real Duo)
    // The P-48's vertical drag is the touch press (RootView), so a spin is a horizontal drag that starts on the
    // object; a tap pokes it; a pinch zooms a little. All only while nothing is pressed (`PressScene.canInspectObject`):
    // once the ram moves, the spin hands back and springs home, so touch never fights the press.

    var onPoke: ((Double) -> Void)?
    var onSpin: ((Double) -> Void)?

    /// UIView asks before any of its recognizers begins (and, as their delegate, for ours): only on the object.
    override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard recognizer === spinPan || recognizer === pokeTap || recognizer === zoomPinch else {
            return super.gestureRecognizerShouldBegin(recognizer)
        }
        let point = recognizer.location(in: self)
        guard touchIsOnObject(point) else { return false }
        if let pan = recognizer as? UIPanGestureRecognizer { return isHorizontal(pan) }
        return true
    }
    private lazy var spinPan = UIPanGestureRecognizer(target: self, action: #selector(handleSpin(_:)))
    private lazy var pokeTap = UITapGestureRecognizer(target: self, action: #selector(handlePoke(_:)))
    private lazy var zoomPinch = UIPinchGestureRecognizer(target: self, action: #selector(handleZoom(_:)))
    private var lastPan: CGPoint = .zero

    /// On the object's projected bounds (+24 pt), while it may be inspected.
    fileprivate func touchIsOnObject(_ point: CGPoint) -> Bool {
        guard let scene, scene.canInspectObject, let rect = scene.objectScreenRect() else { return false }
        return rect.insetBy(dx: -24, dy: -24).contains(arView.convert(point, from: self))
    }

    /// A spin is a horizontal drag (the vertical one presses).
    fileprivate func isHorizontal(_ pan: UIPanGestureRecognizer) -> Bool {
        let v = pan.velocity(in: self)
        return abs(v.x) > 1.5 * abs(v.y)
    }

    @objc private func handleSpin(_ pan: UIPanGestureRecognizer) {
        guard let scene else { return }
        let point = pan.location(in: self)
        switch pan.state {
        case .began:
            lastPan = point
            scene.inspectBegan()
        case .changed:
            // Only the horizontal component: a drift down is the touch press's, not a tilt.
            scene.inspectMoved(dx: Double(point.x - lastPan.x), dy: 0)
            lastPan = point
        case .ended, .cancelled, .failed:
            let turns = scene.inspectEnded(vx: pan.state == .ended ? Double(pan.velocity(in: self).x) : 0)
            onSpin?(turns)
        default:
            break
        }
    }

    @objc private func handlePoke(_ tap: UITapGestureRecognizer) {
        guard tap.state == .ended, let scene, scene.poke(strength: 0.7) else { return }
        onPoke?(0.7)
    }

    @objc private func handleZoom(_ pinch: UIPinchGestureRecognizer) {
        guard let scene else { return }
        switch pinch.state {
        case .began, .changed:
            scene.inspectPinch(scale: Double(pinch.scale), began: pinch.state == .began)
        default:
            scene.inspectPinchEnded()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// `hasHinge`: the gate only runs on a device with a hinge (checked until one reports); `shut`: the hinge reads
    /// closed; `busy`: a press is live; `watch`: reads the observable hinge state, so a reopen resumes at once.
    func startRenderGate(hasHinge: @escaping () -> Bool, shut: @escaping () -> Bool, busy: @escaping () -> Bool,
                         watch: @escaping () -> Void) {
        self.hasHinge = hasHinge
        isShut = shut
        pendingBusy = busy
        pendingWatch = watch
        startGateIfHinged()
    }

    /// Starts the gate the first time a hinge is known. Before that, ticks go straight to `onFrame`.
    private func startGateIfHinged() {
        guard !gateStarted, let hasHinge, hasHinge() else { return }
        gateStarted = true
        gate.busy = pendingBusy
        gate.watch = pendingWatch
        pendingBusy = nil
        pendingWatch = nil
        gate.start()
    }

    /// From the ARView's `SceneEvents.Update`. An unstarted gate passes the tick through (`onFrame(dt, true)`).
    private func renderTick(dt: Double) {
        if !gateStarted { startGateIfHinged() }
        gate.renderTick(dt: dt)
    }

    /// Pause = the ARView leaves the window (RealityKit renders only views in a window). On resume it takes the
    /// container's current bounds (it may have resized while out) and autoresizes from there.
    private func setParked(_ parked: Bool) {
        guard parked != isParked else { return }
        isParked = parked
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if parked {
            arView.removeFromSuperview()
        } else if arView.superview !== self {
            arView.frame = bounds
            addSubview(arView)
        }
        CATransaction.commit()
        scene?.setRenderPaused(parked)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        gate.evaluate()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gate.evaluate()
    }

    func teardown() {
        onPoke = nil
        onSpin = nil
        gate.stop()
        updates?.cancel()
        updates = nil
        onFrame = nil
        isShut = nil
        hasHinge = nil
        pendingBusy = nil
        pendingWatch = nil
    }
}

extension PressSceneHostView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // Alongside SwiftUI's touch-press drag (it only presses on a downward drag; the engine then ends the spin).
        true
    }
}
