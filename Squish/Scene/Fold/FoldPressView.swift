import Combine
import QuartzCore
import RealityKit
import SwiftUI
import UIKit

/// The iPhone Duo stage (design/FOLD-PRESS.md §9.1): the full inner canvas, ignoring the safe area.
///
///     FoldStageHostView
///     ├─ platen half   2D CALayer stack (FoldPlaten), the top / leading page
///     ├─ anvil half    clip view → ARView (PressScene in .foldAnvil framing), keystone-warped by H (§9.3 Tier B)
///     └─ bezel         crease band, lips, rails, jaws, crown strip gauge + lamps, console, pilot lamp (FoldBezel)
///
/// RootView keeps its console, captions, flash, hints and cards above this, in the bezel bands.
struct FoldPressView: View {
    let director: PressDirector

    var body: some View {
        FoldStageRepresentable(director: director)
            .ignoresSafeArea()
    }
}

private struct FoldStageRepresentable: UIViewRepresentable {
    let director: PressDirector

    func makeUIView(context: Context) -> FoldStageHostView {
        let host = FoldStageHostView(scene: director.scene, controller: director.fold)
        let director = self.director
        // Touch on the object: a tap is the director's poke (Feedback answers in the material); a flick is a beat.
        host.onPoke = { [weak director] _ in director?.poke() }
        host.onSpin = { [weak director] turns in director?.engine.spun(turnsPerSecond: turns) }
        host.onWindowChange = { [weak director] in director?.hingeContextChanged() }
        // The per-frame loop runs off this ARView's render updates (it replaces PressSceneView's on a Duo), and off
        // the render gate's blind clock while the inner display can't be seen (FOLD-REVIEW-7 N10).
        host.onFrame = { [weak director] dt in director?.frame(dt: dt) }
        host.startRenderGate(
            // Shut = what the engine calls closed: a `closed` flag above 90° is stale (the Duo simulator keeps it set
            // to ~150° on reopen), and the reopen must never wait for it.
            shut: { [weak director] in
                guard let director else { return false }
                return director.isShowingCover && director.engine.rawAngle <= PressEngine.staleClosedAngle
            },
            busy: { [weak director] in director?.engine.phase == .pressing },
            watch: { [weak director] in _ = director?.hingeClosed })
        return host
    }

    func updateUIView(_ uiView: FoldStageHostView, context: Context) {}

    static func dismantleUIView(_ uiView: FoldStageHostView, coordinator: ()) {
        uiView.teardown()
    }
}

@MainActor
final class FoldStageHostView: UIView {
    let arView: ARView
    private let platenView = UIView()
    private let anvilClip = UIView()
    private let bezelView = UIView()
    private weak var scene: PressScene?
    private weak var controller: FoldPressController?
    private var updates: Cancellable?
    private var laidOut: CGSize = .zero
    private let anchor = AnchorEntity(world: .zero)
    private let camera = PerspectiveCamera()
    private var frames = 0
    var onFrame: ((Double) -> Void)?
    /// FOLD-REVIEW-7 N10: pauses this ARView (out of the window) while the inner display can't be seen.
    private let gate = InnerRenderGate(name: "fold")
    /// The ARView is out of the window (paused).
    private(set) var isParked = false

    init(scene: PressScene, controller: FoldPressController) {
        self.scene = scene
        self.controller = controller
        arView = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        super.init(frame: .zero)
        backgroundColor = Palette.graphite
        for view in [platenView, anvilClip, bezelView] {
            view.isUserInteractionEnabled = false
            addSubview(view)
        }
        anvilClip.clipsToBounds = true
        anvilClip.backgroundColor = Palette.backdrop

        arView.environment.background = .color(Palette.backdrop)
        arView.renderOptions.insert(.disableMotionBlur)
        arView.renderOptions.insert(.disableCameraGrain)
        arView.renderOptions.insert(.disableDepthOfField)
        arView.renderOptions.insert(.disableGroundingShadows)
        arView.isUserInteractionEnabled = false
        arView.autoresizingMask = []
        anvilClip.addSubview(arView)
        // The warp maps ARView points straight to clip-view points: anchor at the origin, position at the origin.
        arView.layer.anchorPoint = .zero
        arView.layer.position = .zero

        platenView.layer.addSublayer(controller.platen.layer)
        bezelView.layer.addSublayer(controller.bezel.layer)

        // The Duo stage's own camera (the scene's P-48 camera is disabled in fold framing): a camera that was
        // rendered by another ARView's scene is not reliably picked up after the move.
        camera.camera.near = 0.05
        camera.camera.far = 5
        anchor.addChild(camera)
        arView.scene.addAnchor(anchor)
        claimScene()
        controller.attach(host: self, scene: scene)
        installInspectGestures()

        updates = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            let dt = event.deltaTime
            MainActor.assumeIsolated {
                self?.gate.renderTick(dt: dt)
            }
        }
        gate.onFrame = { [weak self] dt, rendered in self?.drive(dt: dt, rendered: rendered) }
        gate.onPausedChange = { [weak self] paused in self?.setParked(paused) }
        gate.sample = { [weak self] in
            guard let self else { return (inWindow: false, canvasOK: false, shut: false) }
            return (inWindow: self.window != nil,
                    canvasOK: self.laidOut != .zero && InnerDisplayPolicy.isInnerCanvas(self.bounds.size),
                    shut: self.isShut?() ?? false)
        }
    }

    /// The hinge reads shut (set by `startRenderGate`).
    private var isShut: (() -> Bool)?

    // MARK: - Touch on the object (founder, real Duo)
    // Drag on the object spins it on the plate (with a little tilt, inertia and a spring back), a pinch zooms a little,
    // a tap pokes it. The anamorphic camera never moves: the object itself turns, so the illusion holds. Only while
    // nothing is pressed (`PressScene.canInspectObject`); folding is the press on the Duo, so touch never fights it.

    var onPoke: ((Double) -> Void)?
    var onSpin: ((Double) -> Void)?

    /// UIView asks before any of its recognizers begins (and, as their delegate, for ours): only on the object.
    override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard recognizer === spinPan || recognizer === pokeTap || recognizer === zoomPinch else {
            return super.gestureRecognizerShouldBegin(recognizer)
        }
        return touchIsOnObject(recognizer.location(in: self))
    }
    private lazy var spinPan = UIPanGestureRecognizer(target: self, action: #selector(handleSpin(_:)))
    private lazy var pokeTap = UITapGestureRecognizer(target: self, action: #selector(handlePoke(_:)))
    private lazy var zoomPinch = UIPinchGestureRecognizer(target: self, action: #selector(handleZoom(_:)))
    private var lastPan: CGPoint = .zero
    /// The touch reaches this far from the footprint centre and still counts as on the object (points).
    static let inspectRadius: CGFloat = 150

    private func installInspectGestures() {
        for recognizer in [spinPan, pokeTap, zoomPinch] as [UIGestureRecognizer] {
            recognizer.delegate = self
            recognizer.cancelsTouchesInView = false
            addGestureRecognizer(recognizer)
        }
        spinPan.maximumNumberOfTouches = 1
    }

    /// A touch on the object (on the anvil half, near the footprint), while it may be inspected.
    fileprivate func touchIsOnObject(_ point: CGPoint) -> Bool {
        guard let scene, scene.canInspectObject, let layout = controller?.layout, layout.anvilHalf.contains(point)
        else { return false }
        let c = layout.footprintCentre
        return hypot(point.x - c.x, point.y - c.y) <= Self.inspectRadius
    }

    /// Book pose turns the plate's vertical axis toward the eye, so the spin follows the finger around the footprint;
    /// tabletop spins with a horizontal drag. Returns the equivalent horizontal drag in points.
    private func spinDrag(from a: CGPoint, to b: CGPoint) -> (dx: Double, dy: Double) {
        guard let layout = controller?.layout, layout.isBook else { return (Double(b.x - a.x), Double(b.y - a.y)) }
        let c = layout.footprintCentre
        var turn = Double(atan2(b.y - c.y, b.x - c.x) - atan2(a.y - c.y, a.x - c.x))
        if turn > .pi { turn -= 2 * .pi }
        if turn < -.pi { turn += 2 * .pi }
        return (turn / ObjectInspection.yawPerPoint, 0)
    }

    @objc private func handleSpin(_ pan: UIPanGestureRecognizer) {
        guard let scene else { return }
        let point = pan.location(in: self)
        switch pan.state {
        case .began:
            lastPan = point
            scene.inspectBegan()
        case .changed:
            let d = spinDrag(from: lastPan, to: point)
            lastPan = point
            scene.inspectMoved(dx: d.dx, dy: d.dy)
        case .ended, .cancelled, .failed:
            var vx = Double(pan.velocity(in: self).x)
            if let layout = controller?.layout, layout.isBook {
                // Tangential speed around the footprint → the equivalent horizontal flick.
                let v = pan.velocity(in: self), c = layout.footprintCentre
                let r = max(hypot(point.x - c.x, point.y - c.y), 30)
                let ω = Double((point.x - c.x) * v.y - (point.y - c.y) * v.x) / Double(r * r)
                vx = ω / ObjectInspection.yawPerPoint
            }
            let turns = scene.inspectEnded(vx: pan.state == .ended ? vx : 0)
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

    /// Starts pausing this stage while the inner display can't be seen (FOLD-REVIEW-7 N10). `shut`: the hinge reads
    /// closed; `busy`: a press is live; `watch`: reads the observable hinge state, so a reopen resumes at once.
    func startRenderGate(shut: @escaping () -> Bool, busy: @escaping () -> Bool, watch: @escaping () -> Void) {
        isShut = shut
        gate.busy = busy
        gate.watch = watch
        gate.start()
    }

    /// One frame of the loop. `rendered`: from this ARView's update (false: the gate's blind clock while paused, or
    /// its catch-up frame on resume).
    private func drive(dt: Double, rendered: Bool) {
        if rendered { frames &+= 1 }
        guard let scene else { return }
        // Another view (the P-48 PressSceneView) has attached the scene: it owns it now. Never take it back,
        // and stop driving the frame loop so a dying fold stage can't fight the machine view.
        guard scene.arView === arView else { return }
        // Self-heal: the root was moved without anyone attaching; re-anchor it before this frame renders.
        if scene.root.parent !== anchor {
            log("reclaim (root parent was \(scene.root.parent.map { String(describing: type(of: $0)) } ?? "nil"))")
            claimScene()
        }
        onFrame?(dt)
        if rendered && (frames == 3 || frames % 240 == 0) { logState() }
    }

    /// Pause = the ARView leaves the window (RealityKit renders only views in a window; a zero-size one in a window
    /// still ticked at 60 fps, FOLD-REVIEW-7 N10). Its layer keeps its anchor point, bounds and warp, so putting it back
    /// is one `addSubview`. The platen and bezel layers stay; the controller stops writing them while paused.
    private func setParked(_ parked: Bool) {
        guard parked != isParked else { return }
        isParked = parked
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if parked {
            arView.removeFromSuperview()
        } else if arView.superview !== anvilClip {
            anvilClip.addSubview(arView)
        }
        CATransaction.commit()
        controller?.setRenderPaused(parked)
        scene?.setRenderPaused(parked)
    }

    /// A window change (a nil hinge around it is expected: `HingePresence`).
    var onWindowChange: (() -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChange?()
        gate.evaluate()
    }

    /// An Entity lives in one scene only: detach the press scene's root (and its old anchor) from the P-48 view's
    /// scene completely, then anchor it here.
    private func claimScene() {
        guard let scene, let controller else { return }
        let root = scene.root
        if let old = root.parent, old !== anchor {
            if let oldAnchor = old as? AnchorEntity, let oldScene = oldAnchor.scene {
                oldScene.removeAnchor(oldAnchor)
            }
            root.removeFromParent()
        }
        // Fold framing first (disables the scene's own camera), so this view only ever sees the stage camera.
        scene.attach(to: arView)
        scene.setFraming(.foldAnvil, anvil: controller.anvil.root)
        if root.parent !== anchor { anchor.addChild(root) }
    }

    // MARK: - Camera (§9.3 Tier B: a symmetric camera at the eye; the warp does the rest)

    func setCamera(position: SIMD3<Float>, orientation: simd_quatf, verticalFOV: Float, near: Float, far: Float) {
        camera.position = position
        camera.orientation = orientation
        camera.camera.fieldOfViewInDegrees = verticalFOV
        camera.camera.near = near
        camera.camera.far = far
    }

    // MARK: - CI diagnostics (demo runs only)

    private func log(_ message: String) {
        guard DemoScenario.current != nil else { return }
        print("SQUISH-F \(message)")
    }

    private func logState() {
        guard DemoScenario.current != nil else { return }
        let t = arView.layer.transform
        let root = scene?.root
        let flags = "hidden=\(arView.isHidden ? 1 : 0) window=\(window != nil ? 1 : 0) rootInAnchor=\(root?.parent === anchor ? 1 : 0)"
            + " camEnabled=\(camera.isEnabled ? 1 : 0) framing=\(String(describing: scene?.framing ?? .machine))"
        log("frame \(frames) clip=\(NSCoder.string(for: anvilClip.frame)) ar.bounds=\(NSCoder.string(for: arView.bounds)) "
            + String(format: "alpha=%.2f ", Double(arView.alpha)) + flags
            + String(format: " cam=(%.4f,%.4f,%.4f) fov=%.2f near=%.3f far=%.2f",
                     Double(camera.position.x), Double(camera.position.y), Double(camera.position.z),
                     Double(camera.camera.fieldOfViewInDegrees), Double(camera.camera.near), Double(camera.camera.far))
            + String(format: " H=[%.3f %.3f %.6f | %.3f %.3f %.6f | %.1f %.1f %.3f]",
                     Double(t.m11), Double(t.m12), Double(t.m14), Double(t.m21), Double(t.m22), Double(t.m24),
                     Double(t.m41), Double(t.m42), Double(t.m44)))
        if let controller {
            log(controller.diagnostics)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // N10: a move to the cover display (466 × 678) or a zero-size window pauses; the inner canvas resumes.
        defer { gate.evaluate() }
        let size = bounds.size
        // Lay out once per canvas size (669 × 951 tabletop, 951 × 669 book). Ignore transient tiny sizes and the
        // cover display (466 × 678): while shut, the inner content stays frozen at the sealed state (§6.2).
        guard min(size.width, size.height) >= 320, max(size.width, size.height) >= 800, size != laidOut else { return }
        laidOut = size
        let layout = FoldLayout(canvas: size)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        platenView.frame = bounds
        bezelView.frame = bounds
        anvilClip.frame = layout.anvilHalf
        controller?.apply(layout: layout)
        CATransaction.commit()
    }

    /// The anvil ARView's render size (oversampled, at the glass's natural aspect, §9.3 step 2).
    func setAnvilViewSize(_ size: CGSize) {
        arView.layer.transform = CATransform3DIdentity
        arView.bounds = CGRect(origin: .zero, size: size)
        arView.layer.position = .zero
    }

    /// The keystone warp: the projected glass corners land exactly on the anvil half's corners.
    func setWarp(_ homography: FoldHomography) {
        arView.layer.transform = homography.transform3D
    }

    func setEnamel(_ color: UIColor) {
        anvilClip.backgroundColor = color
        arView.environment.background = .color(color)
    }

    func teardown() {
        gate.stop()
        updates?.cancel()
        updates = nil
        onFrame = nil
        isShut = nil
        controller?.detach(host: self)
        if let scene, scene.arView === arView, scene.framing == .foldAnvil {
            scene.setFraming(.machine)
        }
    }
}

extension FoldStageHostView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // Spin and pinch together; nothing else of ours competes.
        (recognizer is UIPanGestureRecognizer && other is UIPinchGestureRecognizer)
            || (recognizer is UIPinchGestureRecognizer && other is UIPanGestureRecognizer)
    }
}

extension FoldHomography {
    /// Core Animation's row-vector layout (§9.3 step 4).
    var transform3D: CATransform3D {
        let e = coreAnimationEntries.map { CGFloat($0) }
        return CATransform3D(m11: e[0], m12: e[1], m13: e[2], m14: e[3],
                             m21: e[4], m22: e[5], m23: e[6], m24: e[7],
                             m31: e[8], m32: e[9], m33: e[10], m34: e[11],
                             m41: e[12], m42: e[13], m43: e[14], m44: e[15])
    }
}
