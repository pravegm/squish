import Combine
import RealityKit
import SwiftUI
import UIKit

/// Hosts the press scene in a non-AR `ARView` (so `PressScene.snapshot()` can use `ARView.snapshot`)
/// and drives the per-frame loop from RealityKit's update event: `director.frame(dt:)` once per rendered frame.
/// 120 Hz needs `CADisableMinimumFrameDurationOnPhone` (set in project.yml).
struct PressSceneView: UIViewRepresentable {
    let director: PressDirector

    final class Coordinator {
        var updates: Cancellable?
        deinit { updates?.cancel() }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
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

        let director = self.director
        context.coordinator.updates = view.scene.subscribe(to: SceneEvents.Update.self) { event in
            let dt = event.deltaTime
            MainActor.assumeIsolated {
                director.frame(dt: dt)
            }
        }
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        coordinator.updates?.cancel()
        coordinator.updates = nil
    }
}
