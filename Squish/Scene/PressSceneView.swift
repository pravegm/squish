import RealityKit
import SwiftUI

/// Hosts the RealityKit press scene and drives the per-frame loop from RealityKit's update event.
struct PressSceneView: View {
    let director: PressDirector

    var body: some View {
        RealityView { content in
            content.camera = .virtual
            content.add(director.scene.root)
            director.frameSubscription = content.subscribe(to: SceneEvents.Update.self) { event in
                let dt = event.deltaTime
                MainActor.assumeIsolated {
                    director.frame(dt: dt)
                }
            }
        }
    }
}
