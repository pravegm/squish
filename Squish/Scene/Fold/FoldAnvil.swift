import Foundation
import RealityKit
import simd
import UIKit

/// How `PressScene` frames itself (FOLD-PRESS.md §9.1).
enum FramingMode: Equatable, Sendable {
    /// The P-48 machine (non-folding iPhones, Split View, "press without folding").
    case machine
    /// The iPhone Duo's anvil half: rig and cyclorama hidden, `FoldAnvil` shown, camera at the design eye.
    case foldAnvil
}

/// One frame of the anvil camera and its wedge-light cues, in scene units (written by `FoldPressController`).
struct FoldStage {
    var cameraPosition: SIMD3<Float>
    var cameraOrientation: simd_quatf
    var verticalFOV: Float
    var near: Float
    var far: Float
    /// Radians about +x: the object's top tips away from the hinge (§2.4 clamshell lean).
    var lean: Float
    /// The failure flash sits at the crease side, 30 mm up (§2.4).
    var flashPosition: SIMD3<Float>
    /// Multiplies the rim light: the real top screen lights the object as it closes (§2.4 wedge light).
    var rimGain: Float
}

/// The lower plate of the press (§2.1), coplanar with the glass: the enamel field (the whole half plus overscan),
/// the brushed-steel strike plate 0.4 mm proud with its chamfer, four chrome hex bolts and two dark-chrome guide-pin
/// bushings. Built in millimetres in the anvil frame; `root.scale` converts to scene metres for the current object.
@MainActor
final class FoldAnvil {
    let root = Entity()
    private let field = ModelEntity()
    private let fieldGroup = Entity()
    private var builtFor: FoldLayout?
    private var gel: UInt32?

    init() {
        root.addChild(fieldGroup)
        buildPlate()
    }

    /// Scene metres per millimetre (FoldMetrics.metresPerMM for the current object's fold scale).
    func setScale(_ metresPerMM: Double) {
        root.scale = SIMD3(repeating: Float(metresPerMM))
    }

    /// The enamel field and the bushings depend on the canvas; rebuilt once per layout.
    func build(layout: FoldLayout) {
        guard builtFor != layout else { return }
        builtFor = layout
        for child in Array(fieldGroup.children) { child.removeFromParent() }
        let corners = layout.anvilCorners.glass
        let xs = corners.map { Float($0.x) }, zs = corners.map { Float($0.z) }
        let minX = (xs.min() ?? -60) - 12, maxX = (xs.max() ?? 60) + 12
        let minZ = (zs.min() ?? -40) - 12, maxZ = (zs.max() ?? 40) + 12
        field.model = ModelComponent(mesh: .generatePlane(width: maxX - minX, depth: maxZ - minZ),
                                     materials: [fieldMaterial(gel ?? 0xF6E3D3, golden: false)])
        field.position = [(minX + maxX) / 2, -Float(FoldMetrics.plateProudMM), (minZ + maxZ) / 2]
        fieldGroup.addChild(field)

        let darkChrome = SceneMaterials.pbr(UIColor(hex: 0x6B6E75), roughness: 0.15, metallic: 1)
        let ring = MeshKit.torus(major: 0.70, minor: 0.17, segments: 32, sides: 10)
        let hole = MeshKit.roundedCylinder(radius: 0.5, height: 0.05, bevel: 0.02, segments: 24)
        let graphite = SceneMaterials.enamel(Palette.enamelGraphite, roughness: 0.5, clearcoat: 0.3, clearcoatRoughness: 0.2)
        for p in layout.guidePins(platen: false) {
            let a = layout.anvilMM(canvas: p)
            let base = SIMD3<Float>(Float(a.x), -Float(FoldMetrics.plateProudMM), Float(a.y))
            let model = MeshKit.model(ring, material: darkChrome)
            model.position = base + SIMD3(0, 0.05, 0)
            fieldGroup.addChild(model)
            let inner = MeshKit.model(hole, material: graphite)
            inner.position = base
            fieldGroup.addChild(inner)
        }
    }

    /// The gel wall colour tints the enamel (§2.1, "the gel becomes the appliance's colour").
    func setGel(_ gel: UInt32, golden: Bool) {
        let key = golden ? 0xF3E6C4 : gel
        guard self.gel != key else { return }
        self.gel = key
        field.model?.materials = [fieldMaterial(key, golden: golden)]
    }

    private func fieldMaterial(_ gel: UInt32, golden: Bool) -> PhysicallyBasedMaterial {
        SceneMaterials.enamel(FoldTextures.enamel(gel: gel, golden: golden), roughness: 0.40, clearcoat: 0.70,
                              clearcoatRoughness: 0.10)
    }

    private func buildPlate() {
        let ppm = FoldMetrics.pointsPerMM
        let w = Float(FoldMetrics.plateLateral / ppm), d = Float(FoldMetrics.plateDepth / ppm)
        let r = Float(FoldMetrics.plateRadius / ppm)
        let proud = Float(FoldMetrics.plateProudMM)
        let steel = SceneMaterials.pbr(Palette.brushedSteel, roughness: 0.30, metallic: 1)
        // Body: top 0.02 mm under the textured face, extending below the field (hidden), 0.4 mm chamfer.
        let thickness = proud + 0.8
        let body = MeshKit.model(MeshKit.roundedBox([w, thickness, d], radius: r, bevel: 0.4), material: steel)
        body.position = [0, -0.02 - thickness / 2, 0]
        root.addChild(body)
        // Face: brushed streaks parallel to the crease (anvil x on both layouts).
        var faceMaterial: PhysicallyBasedMaterial = steel
        if let texture = StudioEnvironment.texture(FoldTextures.brushedSteel(), name: "fold.plate") {
            faceMaterial = SceneMaterials.textured(texture, roughness: 0.30, metallic: 1)
        }
        let face = ModelEntity(mesh: .generatePlane(width: w - 0.8, depth: d - 0.8, cornerRadius: max(r - 0.4, 0.1)),
                               materials: [faceMaterial])
        face.position = [0, 0, 0]
        root.addChild(face)
        // Four hex bolts, inset 14 pt from the plate corners (§2.1).
        let chrome = SceneMaterials.pbr(Palette.chrome, roughness: 0.06, metallic: 1)
        let across = Float(FoldMetrics.boltDiameter / ppm)
        let hexagon: [SIMD2<Float>] = (0..<6).map { k in
            let a = Float(k) * .pi / 3
            return SIMD2(cos(a), sin(a)) * across / 2
        }
        let head = MeshKit.roundedPrism(polygon: hexagon, height: 0.45, cornerRadius: 0.08, bevel: 0.08,
                                        cornerSteps: 2, bevelSteps: 2)
        let dome = MeshKit.ellipsoid(radii: [across * 0.36, 0.45, across * 0.36], segments: 24, rings: 10)
        let dl = Float((FoldMetrics.plateLateral / 2 - FoldMetrics.boltInset) / ppm)
        let dd = Float((FoldMetrics.plateDepth / 2 - FoldMetrics.boltInset) / ppm)
        for sx: Float in [-1, 1] {
            for sz: Float in [-1, 1] {
                let bolt = MeshKit.model(head, material: chrome)
                bolt.position = [sx * dl, 0, sz * dd]
                root.addChild(bolt)
                let cap = MeshKit.model(dome, material: chrome)
                cap.position = [sx * dl, 0.42, sz * dd]
                root.addChild(cap)
            }
        }
    }
}
