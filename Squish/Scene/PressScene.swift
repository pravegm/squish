import RealityKit
import simd
import UIKit

/// The press rig: studio backdrop, steel anvil, hydraulic ram, lights and camera (bible §9).
/// The object sits on the anvil in the lower half of the screen; the ram descends from the top half.
@MainActor
final class PressScene {
    let root = Entity()

    private let objectSlot = Entity()
    private let ram = Entity()
    private let shadow: ModelEntity
    private var objectView: PressObjectView?
    private var lastShadowOpacity: Float = -1
    /// How far above the object the ram rests before a press.
    private let ramGap: Float = 0.075

    init() {
        shadow = ModelEntity(mesh: .generatePlane(width: 0.1, depth: 0.1, cornerRadius: 0.05),
                             materials: [SceneMaterials.unlit(.black, opacity: 0.15)])
        buildStudio()
        buildAnvil()
        buildRam()
        buildLightsAndCamera()
        root.addChild(objectSlot)
        shadow.position.y = 0.0005
        root.addChild(shadow)
    }

    func setObject(_ kind: ObjectKind, seed: UInt64) {
        objectView?.entity.removeFromParent()
        let view = PressObjectFactory.make(kind, seed: seed)
        objectSlot.addChild(view.entity)
        objectView = view
        view.apply(compression: 0)
        let size = view.footprint * 2.4
        shadow.scale = [size / 0.1, 1, size / 0.1 * 0.8]
        lastShadowOpacity = -1
    }

    func update(engine: PressEngine) {
        guard let view = objectView else { return }
        let contactT = Float(engine.config.contactT)
        let renderDepth = Float(engine.renderDepth)
        let rest = view.restHeight

        // The ram follows the hand (render depth); the object shows max(plastic, render) so it never re-inflates.
        let ramFace: Float
        if renderDepth < contactT {
            let start = rest + ramGap
            ramFace = start - (start - rest) * (renderDepth / contactT)
        } else {
            ramFace = view.height(atCompression: Float(engine.renderCompression))
        }
        ram.position.y = ramFace

        let objectCompression = Float(engine.visualCompression)
        view.apply(compression: objectCompression)

        // Object-local micro-shake under load; never shake the whole screen (haptics are the screenshake).
        if engine.isLoaded && !engine.isHolding {
            let amplitude: Float = 0.0004 * Float(engine.measuredCompression)
            objectSlot.position = [Float.random(in: -amplitude...amplitude), 0, Float.random(in: -amplitude...amplitude)]
        } else {
            objectSlot.position = .zero
        }

        // The contact shadow darkens as the ram approaches: the strongest cheap depth cue.
        let opacity = 0.12 + 0.45 * min(renderDepth / max(contactT, 0.01), 1)
        if abs(opacity - lastShadowOpacity) > 0.02 {
            lastShadowOpacity = opacity
            shadow.model?.materials = [SceneMaterials.unlit(.black, opacity: opacity)]
        }
    }

    func handle(_ event: PressEvent) {
        if case let .fracture(index, isFailure) = event {
            objectView?.fracture(index: index, isFailure: isFailure)
        }
    }

    // MARK: - Build

    private func buildStudio() {
        let backdrop = ModelEntity(mesh: .generateBox(width: 3, height: 2, depth: 0.01),
                                   materials: [SceneMaterials.unlit(Palette.backdrop)])
        backdrop.position = [0, 0.4, -0.35]
        root.addChild(backdrop)

        let floor = ModelEntity(mesh: .generatePlane(width: 3, depth: 2),
                                materials: [SceneMaterials.pbr(Palette.backdrop, roughness: 0.9)])
        floor.position = [0, -0.031, 0]
        root.addChild(floor)
    }

    private func buildAnvil() {
        let steel = SceneMaterials.pbr(Palette.graphite, roughness: 0.35, metallic: 0.8)
        let anvil = ModelEntity(mesh: .generateBox(width: 0.22, height: 0.03, depth: 0.14, cornerRadius: 0.004),
                                materials: [steel])
        anvil.position = [0, -0.015, 0]
        root.addChild(anvil)

        // Two frame posts so the press reads as a machine.
        for side: Float in [-1, 1] {
            let post = ModelEntity(mesh: .generateBox(width: 0.018, height: 0.36, depth: 0.03, cornerRadius: 0.004),
                                   materials: [steel])
            post.position = [0.12 * side, 0.15, -0.045]
            root.addChild(post)
        }

        let stripe = ModelEntity(mesh: .generateBox(width: 0.222, height: 0.006, depth: 0.142),
                                 materials: [SceneMaterials.pbr(Palette.hydraulicYellow, roughness: 0.5)])
        stripe.position = [0, -0.027, 0]
        root.addChild(stripe)
    }

    private func buildRam() {
        let yellow = SceneMaterials.pbr(Palette.hydraulicYellow, roughness: 0.4, clearcoat: 0.3)
        let chrome = SceneMaterials.pbr(Palette.steel, roughness: 0.15, metallic: 1)

        // Ram origin = its pressing face.
        let plate = ModelEntity(mesh: .generateBox(width: 0.16, height: 0.012, depth: 0.11, cornerRadius: 0.002),
                                materials: [SceneMaterials.pbr(Palette.steel, roughness: 0.3, metallic: 0.9)])
        plate.position.y = 0.006
        ram.addChild(plate)

        let housing = ModelEntity(mesh: .generateBox(width: 0.13, height: 0.04, depth: 0.09, cornerRadius: 0.006),
                                  materials: [yellow])
        housing.position.y = 0.012 + 0.02
        ram.addChild(housing)

        let piston = ModelEntity(mesh: .generateCylinder(height: 0.4, radius: 0.018), materials: [chrome])
        piston.position.y = 0.052 + 0.2
        ram.addChild(piston)

        root.addChild(ram)
    }

    private func buildLightsAndCamera() {
        let key = DirectionalLight()
        key.light.intensity = 4500
        key.shadow = DirectionalLightComponent.Shadow(maximumDistance: 1.5, depthBias: 2)
        key.look(at: [0, 0, 0], from: [-0.35, 0.6, 0.45], relativeTo: nil)
        root.addChild(key)

        let fill = PointLight()
        fill.light.intensity = 2500
        fill.light.attenuationRadius = 2
        fill.position = [0.3, 0.25, 0.4]
        root.addChild(fill)

        let rim = PointLight()
        rim.light.intensity = 1800
        rim.light.attenuationRadius = 1.5
        rim.position = [0, 0.2, -0.25]
        root.addChild(rim)

        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 30
        camera.look(at: [0, 0.1, 0], from: [0, 0.12, 0.43], relativeTo: nil)
        root.addChild(camera)
    }
}
