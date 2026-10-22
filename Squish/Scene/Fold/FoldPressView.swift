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
        // The per-frame loop runs off this ARView's render updates (it replaces PressSceneView's on a Duo).
        host.onFrame = { [weak director] dt in director?.frame(dt: dt) }
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

        updates = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            let dt = event.deltaTime
            MainActor.assumeIsolated {
                guard let self else { return }
                self.frames &+= 1
                guard let scene = self.scene else { return }
                // Another view (the P-48 PressSceneView) has attached the scene: it owns it now. Never take it back,
                // and stop driving the frame loop so a dying fold stage can't fight the machine view.
                guard scene.arView === self.arView else { return }
                // Self-heal: the root was moved without anyone attaching; re-anchor it before this frame renders.
                if scene.root.parent !== self.anchor {
                    self.log("reclaim (root parent was \(scene.root.parent.map { String(describing: type(of: $0)) } ?? "nil"))")
                    self.claimScene()
                }
                self.onFrame?(dt)
                if self.frames == 3 || self.frames % 240 == 0 { self.logState() }
            }
        }
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
        updates?.cancel()
        updates = nil
        onFrame = nil
        controller?.detach(host: self)
        if let scene, scene.arView === arView, scene.framing == .foldAnvil {
            scene.setFraming(.machine)
        }
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
