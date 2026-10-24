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
    /// Radians about +x: the object's top tips away from the hinge (§2.4 clamshell lean, `FoldLean`). The scene pivots
    /// it on the base edge it tips toward, never the slot origin (FOLD-REVIEW-3 N2).
    var lean: Float
    /// The failure flash sits at the crease side, 30 mm up (§2.4).
    var flashPosition: SIMD3<Float>
    /// Multiplies the rim light: the real top screen lights the object as it closes (§2.4 wedge light).
    var rimGain: Float
    /// Radians about +y applied to the object slot under the lean (book pose faces the object at the eye).
    var yaw: Float = 0
    /// Fold-mode exposure (FOLD-REVIEW-1 #1): studio IBL EV offset and key-light gain.
    var iblOffset: Float = -0.5
    var keyGain: Float = 1
    /// Half extents (scene metres; x along the hinge, z across it) of the strike plate + 8 pt, centred on the slot
    /// origin. The contact-shadow and plate-shade decals are kept inside it (FOLD-REVIEW-3 N13). Zero = no limit.
    var plateHalfExtent: SIMD2<Float> = .zero
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
    /// The field's colour: exactly the platen's enamel (set by the controller from the same value).
    private var enamel = FoldTextures.enamel(gel: 0xF6E3D3, golden: false, lit: FoldTextures.platenLit)
    /// The splat that escaped the fold (FOLD-REVIEW-4 F3): flat droplet decals lying on the plate and field.
    private let sprayGroup = Entity()
    private var sprayDrops: [SprayDrop] = []
    private var sprayAge: Double = 0
    private var dropletMesh: MeshResource?
    /// The flattened specimen's top-down extent (anvil frame, mm: centre and half extents), from the scene; the
    /// escaped droplets land clear of it (FOLD-REVIEW-5).
    private var specimen: (centre: SIMD2<Float>, half: SIMD2<Float>)?

    /// One escaped droplet: its print-space spot (mm), drawn size (mm), pop delay, and where it is now.
    private struct SprayDrop {
        let entity: Entity
        let tail: Entity
        let base: SIMD2<Float>
        let diameter: Float
        let delay: Double
        var position: SIMD2<Float>?
    }

    /// The strike plate's body (chamfer) and textured face, re-finished per pose (FOLD-REVIEW-5 N2).
    private var plateBody: ModelEntity?
    private var plateFace: ModelEntity?
    private var plateFinishTabletop: Bool?
    /// Book pose keeps the lit brushed steel (its eye moves with θ, and it matches the platen within ±12 L).
    private var litBody: (any Material)?
    private var litFace: (any Material)?

    init() {
        root.addChild(fieldGroup)
        root.addChild(sprayGroup)
        buildPlate()
    }

    /// The escaped mess hides while a break replay hasn't reached its burst yet.
    func setSprayVisible(_ visible: Bool) {
        if sprayGroup.isEnabled != visible { sprayGroup.isEnabled = visible }
    }

    var hasSpray: Bool { !sprayDrops.isEmpty }

    /// Scene metres per millimetre (FoldMetrics.metresPerMM for the current object's fold scale).
    func setScale(_ metresPerMM: Double) {
        root.scale = SIMD3(repeating: Float(metresPerMM))
    }

    /// The enamel field and the bushings depend on the canvas; rebuilt once per layout.
    func build(layout: FoldLayout) {
        guard builtFor != layout else { return }
        builtFor = layout
        applyPlateFinish(tabletop: !layout.isBook)
        for child in Array(fieldGroup.children) { child.removeFromParent() }
        let corners = layout.anvilCorners.glass
        let xs = corners.map { Float($0.x) }, zs = corners.map { Float($0.z) }
        let minX = (xs.min() ?? -60) - 12, maxX = (xs.max() ?? 60) + 12
        let minZ = (zs.min() ?? -40) - 12, maxZ = (zs.max() ?? 40) + 12
        field.model = ModelComponent(mesh: .generatePlane(width: maxX - minX, depth: maxZ - minZ),
                                     materials: [Self.fieldMaterial(enamel)])
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

    /// The gel-tinted enamel (§2.1, "the gel becomes the appliance's colour"): pass the platen field's colour, so the
    /// two pages are one material.
    func setEnamel(_ color: UIColor) {
        guard !color.isEqual(enamel) else { return }
        enamel = color
        field.model?.materials = [Self.fieldMaterial(color)]
    }

    // MARK: Escaped splat (FOLD-REVIEW-4 F3)

    /// At the failure: the splat's droplets that got out from between the plates, from the platen's
    /// (`FoldStamps.anvilSpray`, print space = this frame top-down in points). Each is a flat, unlit teardrop of the
    /// ink (a disc with a darker rim, a wet highlight and a short tail pointing back at the specimen), lying
    /// `dropletLift` over the plate (or the field, past the plate's edge). FOLD-REVIEW-5: the platen's droplets mostly lie inside the
    /// specimen's own footprint (the duck's ring r 0.45–0.95 R round its seam), so the flattened 3D specimen hid every
    /// one; they now land clear of its live top-down extent (`setSpecimen`, `FoldStamps.sprayLanding`), at 1.6× the
    /// platen's size. They pop in, staggered, ride out with the platen splat's spread, and are pushed ahead of the
    /// spreading mess (`updateSpray`).
    func spray(_ spray: FoldSpray?, reduceMotion: Bool) {
        clearSpray()
        guard let spray, !spray.droplets.isEmpty else { return }
        let mesh: MeshResource
        if let dropletMesh {
            mesh = dropletMesh
        } else {
            // A unit disc (a fully rounded unit square), scaled per droplet.
            mesh = .generatePlane(width: 1, depth: 1, cornerRadius: 0.48)
            dropletMesh = mesh
        }
        let ppm = Float(FoldMetrics.pointsPerMM)
        let rim = SceneMaterials.unlit(spray.edge)
        let body = SceneMaterials.unlit(spray.color)
        let wet = SceneMaterials.unlit(spray.highlight)
        for (i, d) in spray.droplets.enumerated() {
            let drop = Entity()
            let edge = ModelEntity(mesh: mesh, materials: [rim])
            let core = ModelEntity(mesh: mesh, materials: [body])
            core.scale = [0.70, 1, 0.70]
            core.position = [0.04, 0.02, 0.04]
            let glint = ModelEntity(mesh: mesh, materials: [wet])
            glint.scale = [0.24, 1, 0.24]
            glint.position = [-0.16, 0.03, -0.16]
            // The tail (drop-local units: one unit = the drop's diameter), turned toward the specimen each frame.
            let tail = Entity()
            let tailEdge = ModelEntity(mesh: mesh, materials: [rim])
            tailEdge.scale = [0.56, 1, 0.56]
            tailEdge.position = [0, -0.01, 0]
            let tailCore = ModelEntity(mesh: mesh, materials: [body])
            tailCore.scale = [0.40, 1, 0.40]
            tailCore.position = [0, 0.01, 0]
            tail.addChild(tailEdge)
            tail.addChild(tailCore)
            drop.addChild(tail)
            drop.addChild(edge)
            drop.addChild(core)
            drop.addChild(glint)
            drop.scale = [0.0001, 1, 0.0001]
            sprayGroup.addChild(drop)
            sprayDrops.append(SprayDrop(entity: drop, tail: tail,
                                        base: SIMD2<Float>(Float(d.centre.x) / ppm, Float(d.centre.y) / ppm),
                                        diameter: 2 * Float(d.radius) * Self.dropletScale / ppm,
                                        delay: reduceMotion ? 0 : Double(i) * 0.014, position: nil))
        }
        updateSpray(spread: 0.55, dt: 0, reduceMotion: reduceMotion)
    }

    /// The escaped droplets are drawn this much larger than the platen's (FOLD-REVIEW-5: 3–9 pt discs vanished at
    /// thumbnail size next to the specimen).
    static let dropletScale: Float = 1.6
    /// Millimetres over the plate (or field): above PressScene's AO / soft-shadow / plate-shade decals (0.3–0.5 mm
    /// scene ≈ 0.07–0.17 mm here), so the shade that darkens the plate as the lid closes doesn't grey the escaped
    /// ink out; still far too thin to show any parallax.
    static let dropletLift: Float = 0.18

    /// The flattened specimen's top-down extent in this frame (millimetres; from `PressScene.foldSpecimenExtent`), or
    /// nil if unknown. The escaped droplets keep clear of it.
    func setSpecimen(centre: SIMD2<Float>, half: SIMD2<Float>) {
        specimen = (centre, half)
    }

    /// Per frame: `spread` is the platen splat's scale about the footprint centre (it eases 0.55 → ~1 after the
    /// failure), capped at `FoldStamps.sprayMaxScale`, so the droplets squirt outward with it; each then lands clear of
    /// the specimen (`FoldStamps.sprayLanding`), easing there so a droplet the mess overtakes slides ahead of it. One
    /// with nowhere to land on the plate + `sprayEscapeMargin` stays where it was and is hidden under the specimen.
    func updateSpray(spread: Double, dt: Double, reduceMotion: Bool) {
        guard !sprayDrops.isEmpty else { return }
        sprayAge += dt
        let s = Float(clamp(spread, 0.5, Double(FoldStamps.sprayMaxScale)))
        let ppm = Float(FoldMetrics.pointsPerMM)
        let plateHalf = SIMD2<Float>(Float(FoldMetrics.plateLateral / 2) / ppm, Float(FoldMetrics.plateDepth / 2) / ppm)
        let proud = Float(FoldMetrics.plateProudMM)
        let ease: Float = reduceMotion || dt <= 0 ? 1 : Float(1 - pow(0.5, dt / 0.05))
        for i in sprayDrops.indices {
            let drop = sprayDrops[i]
            var target = drop.base * s
            if let specimen {
                let radiusPt = CGFloat(drop.diameter * ppm / 2)
                if let landed = FoldStamps.sprayLanding(
                    CGPoint(x: CGFloat(target.x * ppm), y: CGFloat(target.y * ppm)), radius: radiusPt,
                    specimenCentre: CGPoint(x: CGFloat(specimen.centre.x * ppm), y: CGFloat(specimen.centre.y * ppm)),
                    specimenHalf: CGSize(width: CGFloat(specimen.half.x * ppm), height: CGFloat(specimen.half.y * ppm))) {
                    target = SIMD2<Float>(Float(landed.x), Float(landed.y)) / ppm
                }
            }
            var p = drop.position.map { $0 + (target - $0) * ease } ?? target
            if !p.x.isFinite || !p.y.isFinite { p = target }
            sprayDrops[i].position = p
            let onPlate = abs(p.x) <= plateHalf.x && abs(p.y) <= plateHalf.y
            drop.entity.position = [p.x, (onPlate ? 0 : -proud) + Self.dropletLift, p.y]
            let pop = reduceMotion ? 1 : Float(clamp((sprayAge - drop.delay) / 0.09, 0, 1))
            let size = max(drop.diameter * pop, 0.0001)
            drop.entity.scale = [size, 1, size]
            // The tail trails back toward the specimen (or the footprint centre).
            let from = specimen?.centre ?? .zero
            let away = p - from
            let length = simd_length(away)
            let dir = length > 1e-4 ? away / length : SIMD2<Float>(0, 1)
            drop.tail.position = [-dir.x * 0.62, 0, -dir.y * 0.62]
        }
    }

    /// The next object goes on: the mess is wiped with the platen's print.
    func clearSpray() {
        for child in Array(sprayGroup.children) { child.removeFromParent() }
        sprayDrops = []
        sprayAge = 0
        specimen = nil
    }

    /// FOLD-REVIEW-3 N3: the field is unlit, not tone-mapped, in the platen's exact colour. A lit clearcoat mirrored
    /// the studio head-on at flat (72 % clip on bubble wrap at 180°) and read as a second lamp. Only the plate, bolts,
    /// pins and object take real light; the AO and soft-shadow decals still ground the object on it.
    private static func fieldMaterial(_ color: UIColor) -> UnlitMaterial {
        SceneMaterials.unlit(color)
    }

    /// FOLD-REVIEW-5 N2 (tabletop strike plate a white-hot card: L 223–248 against the platen plate's 196–198, up to
    /// 53 % clipped). The tabletop design eye sits in front of the phone, so the lit metallic face mirrors the studio's
    /// bright upper back sky and its right rim strip (az 135°, 6.0) straight into the camera; book pose's eye rides the
    /// wedge and never sees that. In tabletop the eye is fixed to the table, so a lit face has nothing to animate
    /// anyway: it shows the platen plate's own 2D steel, unlit and not tone-mapped (`FoldTextures.anvilFace`), so
    /// the two plates are one material by construction, as the fields are (FOLD-REVIEW-3 N3). The 0.4 mm chamfer stays
    /// lit (it is what reads as "proud") but goes rougher and darker (0.55, #9EA3AA) so it can't flare. Book pose
    /// keeps the lit brushed steel it has been matched with. The AO, soft-shadow and plate-shade decals still darken
    /// it as before.
    private func applyPlateFinish(tabletop: Bool) {
        guard plateFinishTabletop != tabletop, let plateBody, let plateFace else { return }
        plateFinishTabletop = tabletop
        if tabletop {
            plateBody.model?.materials = [SceneMaterials.pbr(Self.tabletopChamfer, roughness: 0.55, metallic: 1)]
            let size = CGSize(width: FoldMetrics.plateLateral, height: FoldMetrics.plateDepth)
            if tabletopFace == nil,
               let texture = StudioEnvironment.texture(FoldTextures.anvilFace(size: size), name: "fold.plate.tabletop") {
                var material = UnlitMaterial(applyPostProcessToneMap: false)
                material.color = .init(tint: .white, texture: .init(texture))
                tabletopFace = material
            }
            if let tabletopFace { plateFace.model?.materials = [tabletopFace] }
        } else {
            if let litBody { plateBody.model?.materials = [litBody] }
            if let litFace { plateFace.model?.materials = [litFace] }
        }
    }

    private var tabletopFace: UnlitMaterial?
    /// The tabletop chamfer's steel (FOLD-REVIEW-5 N2's suggested base).
    static let tabletopChamfer = UIColor(hex: 0x9EA3AA)

    private func buildPlate() {
        let ppm = FoldMetrics.pointsPerMM
        let w = Float(FoldMetrics.plateLateral / ppm), d = Float(FoldMetrics.plateDepth / ppm)
        let r = Float(FoldMetrics.plateRadius / ppm)
        let proud = Float(FoldMetrics.plateProudMM)
        let steelBase = UIColor(hex: 0xA9AEB5)   // FOLD-REVIEW-1 #1: was #BFC3C8 / 0.30, read as a white card
        let steel = SceneMaterials.pbr(steelBase, roughness: 0.38, metallic: 1)
        // Body: top 0.02 mm under the textured face, extending below the field (hidden), 0.4 mm chamfer.
        let thickness = proud + 0.8
        let body = MeshKit.model(MeshKit.roundedBox([w, thickness, d], radius: r, bevel: 0.4), material: steel)
        body.position = [0, -0.02 - thickness / 2, 0]
        root.addChild(body)
        // Face: brushed streaks parallel to the crease (anvil x on both layouts).
        var faceMaterial: PhysicallyBasedMaterial = steel
        if let texture = StudioEnvironment.texture(FoldTextures.brushedSteel(base: steelBase), name: "fold.plate") {
            faceMaterial = SceneMaterials.textured(texture, roughness: 0.38, metallic: 1)
        }
        let face = ModelEntity(mesh: .generatePlane(width: w - 0.8, depth: d - 0.8, cornerRadius: max(r - 0.4, 0.1)),
                               materials: [faceMaterial])
        face.position = [0, 0, 0]
        root.addChild(face)
        plateBody = body
        plateFace = face
        litBody = steel
        litFace = faceMaterial
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
