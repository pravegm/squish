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

        // An Entity lives in one scene only: move the press scene's root here from the P-48 view.
        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(scene.root)
        arView.scene.addAnchor(anchor)
        scene.attach(to: arView)
        scene.setFraming(.foldAnvil, anvil: controller.anvil.root)
        controller.attach(host: self, scene: scene)

        updates = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            let dt = event.deltaTime
            MainActor.assumeIsolated {
                self?.onFrame?(dt)
            }
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
