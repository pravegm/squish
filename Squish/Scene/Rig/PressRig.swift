import Foundation
import RealityKit
import simd
import UIKit

/// "Squish P-48" (VISUAL-TARGET §4): a chunky benchtop H-frame hydraulic press with vinyl-toy proportions.
/// Rubber feet, graphite bed, brushed-steel anvil with chrome bolts, two mirror-chrome columns with yellow collars,
/// a yellow crown carrying the instrument panel (gauge, two lamps, nameplate), a graphite cylinder barrel,
/// a chrome rod that lengthens as the yellow platen descends, the one hazard band, and the steel press plate.
/// World origin = anvil top-face centre. The ram's origin is the press face (bottom of the plate).
@MainActor
final class PressRig {
    let root = Entity()
    /// The moving crosshead: platen, collars, hazard band and plate. Origin = press face.
    let ram = Entity()
    /// Child of `ram` so the Unsquishable can bend it without moving the face.
    private let platenGroup = Entity()
    private var rod = ModelEntity()
    private let needlePivot = Entity()
    private var readyLamp = ModelEntity()
    private var loadLamp = ModelEntity()
    private var bolts: [ModelEntity] = []
    private var boltRest: [Transform] = []
    private var damageMarks: [Entity] = []
    private let gaugeGlass = Entity()
    private var hazardBand: ModelEntity?
    private var hazardMaterial: PhysicallyBasedMaterial?
    private var platenModel = ModelEntity()
    private var platenMaterial = PhysicallyBasedMaterial()
    private let sealTag = Entity()
    private let sealTagCard = ModelEntity()
    private var tagSwing = JiggleSpring()
    private var glowAlpha: Float = -1
    private let lampOffMaterial = SceneMaterials.enamel(Palette.lampOff, roughness: 0.15, clearcoat: 1, clearcoatRoughness: 0.05, specular: 0.6)
    private let greenOn = SceneMaterials.glowing(Palette.lampGreen, intensity: 2)
    private let amberOn = SceneMaterials.glowing(Palette.lampAmber, intensity: 0.9)
    private let redOn = SceneMaterials.glowing(Palette.lampRed, intensity: 2)

    // Instruments
    private var needleTons: Float = 0
    private var needleVelocity: Float = 0
    private var redTimer: Float = 0
    private var blink: Float = 0
    private var lampState: (ready: Int, load: Int) = (-1, -1)
    private(set) var damage = 0

    static let homeFace: Float = 0.205
    static let barrelBottom: Float = 0.262
    static let columnX: Float = 0.093
    static let columnZ: Float = -0.020
    static let floorY: Float = -0.108
    static let bedTop: Float = -0.035
    /// Half size (x, z) of the press plate (debris ceilings).
    let plateHalfExtent = SIMD2<Float>(0.055, 0.045)
    /// Anvil top bounds for tidy mess (x, z).
    static let anvilHalf = SIMD2<Float>(0.079, 0.056)
    private let platenZ: Float = -0.005
    private let platenTopLocal: Float = 0.008 + 0.030

    init() {
        let yellow = SceneMaterials.enamel(Palette.enamelYellow, roughness: 0.40, clearcoat: 0.7, clearcoatRoughness: 0.10)
        let graphite = SceneMaterials.enamel(Palette.enamelGraphite, roughness: 0.45, clearcoat: 0.35, clearcoatRoughness: 0.18)
        let chrome = SceneMaterials.pbr(Palette.chrome, roughness: 0.06, metallic: 1)
        let steel = SceneMaterials.pbr(Palette.brushedSteel, roughness: 0.30, metallic: 1)
        let rubber = SceneMaterials.enamel(Palette.rubber, roughness: 0.85, clearcoat: 0, clearcoatRoughness: 0.5, specular: 0.3)

        func add(_ mesh: MeshData, _ material: any Material, at position: SIMD3<Float>, to parent: Entity? = nil) -> ModelEntity {
            let model = MeshKit.model(mesh, material: material)
            model.position = position
            (parent ?? root).addChild(model)
            return model
        }

        // Feet, bed, bed-top line.
        for x: Float in [-0.09, 0.09] {
            for z: Float in [-0.055, 0.055] {
                _ = add(MeshKit.roundedCylinder(radius: 0.010, height: 0.008, bevel: 0.002, segments: 32), rubber,
                        at: [x, Self.floorY, z])
            }
        }
        _ = add(MeshKit.roundedBox([0.220, 0.065, 0.150], radius: 0.012, bevel: 0.012), graphite, at: [0, -0.0675, 0])
        _ = add(MeshKit.roundedBox([0.214, 0.002, 0.144], radius: 0.010, bevel: 0.0008), graphite, at: [0, -0.0345, 0])

        // Anvil (bolster) with four chrome hex bolts.
        _ = add(MeshKit.roundedBox([0.165, 0.035, 0.120], radius: 0.004, bevel: 0.0015), steel, at: [0, -0.0175, 0])
        let hexagon: [SIMD2<Float>] = (0..<6).map { k in
            let a = Float(k) * .pi / 3
            return SIMD2(cos(a) * 0.005, sin(a) * 0.005)
        }
        for x: Float in [-0.0705, 0.0705] {
            for z: Float in [-0.048, 0.048] {
                let bolt = add(MeshKit.roundedPrism(polygon: hexagon, height: 0.004, cornerRadius: 0.0009, bevel: 0.0008,
                                                    cornerSteps: 2, bevelSteps: 2), chrome, at: [x, 0, z])
                bolts.append(bolt)
                boltRest.append(bolt.transform)
            }
        }

        // Columns and collars.
        for side: Float in [-1, 1] {
            let x = side * Self.columnX
            _ = add(MeshKit.lathe(profile: [SIMD2(0, 0), SIMD2(0.011, 0), SIMD2(0.011, 0.365), SIMD2(0, 0.365)], segments: 48),
                    chrome, at: [x, -0.035, Self.columnZ])
            _ = add(MeshKit.roundedCylinder(radius: 0.017, height: 0.014, bevel: 0.004, segments: 48), yellow,
                    at: [x, -0.035, Self.columnZ])
            _ = add(MeshKit.roundedCylinder(radius: 0.017, height: 0.014, bevel: 0.004, segments: 48), yellow,
                    at: [x, 0.316, Self.columnZ])
        }

        // Crown + instrument panel.
        _ = add(MeshKit.roundedBox([0.220, 0.070, 0.120], radius: 0.012, bevel: 0.012), yellow, at: [0, 0.365, -0.010])
        let panel = add(MeshKit.roundedBox([0.190, 0.052, 0.004], radius: 0.003, bevel: 0.0015), graphite, at: [0, 0.365, 0.052])
        _ = panel

        // Gauge (§4.4).
        let gauge = Entity()
        gauge.position = [-0.052, 0.365, 0.0545]
        root.addChild(gauge)
        let bezel = MeshKit.model(MeshKit.torus(major: 0.0235, minor: 0.0025, segments: 64, sides: 16), material: chrome)
        bezel.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        bezel.position = [0, 0, 0.003]
        gauge.addChild(bezel)
        let faceMaterial: any Material
        if let texture = StudioEnvironment.texture(RigTextures.gaugeFace(), name: "gauge.face") {
            faceMaterial = SceneMaterials.textured(texture, roughness: 0.5)
        } else {
            faceMaterial = SceneMaterials.pbr(Palette.gaugePaper, roughness: 0.5)
        }
        let face = ModelEntity(mesh: .generatePlane(width: 0.044, height: 0.044, cornerRadius: 0.022), materials: [faceMaterial])
        face.position = [0, 0, 0.0012]
        gauge.addChild(face)
        let needleShape: [SIMD2<Float>] = [SIMD2(-0.0016, 0.006), SIMD2(0.0016, 0.006), SIMD2(0.0005, -0.021), SIMD2(-0.0005, -0.021)]
        let needle = MeshKit.model(MeshKit.roundedPrism(polygon: needleShape, height: 0.0012, cornerRadius: 0.0004, bevel: 0.0003,
                                                        cornerSteps: 2, bevelSteps: 1),
                                   material: SceneMaterials.enamel(Palette.stampRed, roughness: 0.3, clearcoat: 1, clearcoatRoughness: 0.05))
        // Extrusion along +Y → faces +Z; polygon −Z (the tip) → +Y (12 o'clock).
        needle.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        needlePivot.addChild(needle)
        let hub = MeshKit.model(MeshKit.ellipsoid(radii: [0.0035, 0.0035, 0.002], segments: 24, rings: 12), material: chrome)
        hub.position = [0, 0, 0.0016]
        needlePivot.addChild(hub)
        needlePivot.position = [0, 0, 0.0022]
        gauge.addChild(needlePivot)
        let glass = MeshKit.model(MeshKit.ellipsoid(radii: [0.022, 0.022, 0.004], segments: 48, rings: 12),
                                  material: SceneMaterials.enamel(.white, roughness: 0.02, clearcoat: 1, clearcoatRoughness: 0,
                                                                  specular: 1, opacity: 0.10))
        glass.position = [0, 0, 0.002]
        ShadowCasting.off(glass)
        gaugeGlass.addChild(glass)
        let crescent = ModelEntity(mesh: MeshKit.ellipsoid(radii: [0.007, 0.0028, 0.0008], segments: 24, rings: 8).resource()
                                   ?? .generateSphere(radius: 0.002),
                                   materials: [SceneMaterials.unlit(.white, opacity: 0.55)])
        crescent.position = [-0.009, 0.011, 0.0058]
        crescent.orientation = simd_quatf(angle: 0.6, axis: [0, 0, 1])
        gaugeGlass.addChild(crescent)
        gauge.addChild(gaugeGlass)

        // Lamps (hemispheres on the panel) and nameplate.
        let lampMesh = MeshKit.ellipsoid(radii: [0.007, 0.007, 0.0045], segments: 32, rings: 12)
        readyLamp = add(lampMesh, lampOffMaterial, at: [0.010, 0.373, 0.054])
        loadLamp = add(lampMesh, lampOffMaterial, at: [0.030, 0.373, 0.054])
        let plateMaterial: any Material
        if let texture = StudioEnvironment.texture(RigTextures.nameplate(), name: "nameplate") {
            plateMaterial = SceneMaterials.textured(texture, roughness: 0.3, metallic: 0.8)
        } else {
            plateMaterial = steel
        }
        _ = add(MeshKit.roundedBox([0.048, 0.012, 0.002], radius: 0.001, bevel: 0.0006), plateMaterial, at: [0.062, 0.365, 0.0545])
        let nameplate = ModelEntity(mesh: .generatePlane(width: 0.046, height: 0.0112), materials: [plateMaterial])
        nameplate.position = [0.062, 0.365, 0.0557]
        root.addChild(nameplate)

        // Barrel with its lip.
        // Lighter, glossier graphite so the key lays a strip highlight on it (VISUAL-REVIEW-1 fix 7), two machined rings.
        let barrelGraphite = SceneMaterials.enamel(UIColor(hex: 0x4A4E56), roughness: 0.4, clearcoat: 0.7, clearcoatRoughness: 0.10)
        let barrelHeight: Float = 0.330 - Self.barrelBottom
        _ = add(MeshKit.roundedCylinder(radius: 0.025, height: barrelHeight, bevel: 0.004, segments: 64), barrelGraphite,
                at: [0, Self.barrelBottom, -0.010])
        _ = add(MeshKit.torus(major: 0.025, minor: 0.002, segments: 64, sides: 12), barrelGraphite,
                at: [0, Self.barrelBottom + 0.002, -0.010])
        for k in 1...2 {
            _ = add(MeshKit.torus(major: 0.0255, minor: 0.0012, segments: 64, sides: 10), chrome,
                    at: [0, Self.barrelBottom + barrelHeight * Float(k) / 3, -0.010])
        }

        // Rod: a unit-height chrome cylinder hanging from the barrel (pivot at the top); length set per frame.
        rod = MeshKit.model(MeshKit.lathe(profile: [SIMD2(0, -1), SIMD2(0.015, -1), SIMD2(0.015, 0), SIMD2(0, 0)], segments: 48),
                            material: chrome)
        rod.position = [0, Self.barrelBottom + 0.004, platenZ]
        root.addChild(rod)

        // The moving crosshead.
        ram.addChild(platenGroup)
        // Thin crosshead (30 mm platen + 8 mm plate) so the object stays visible under load (VISUAL-REVIEW-1 fix 3).
        platenMaterial = yellow
        platenModel = MeshKit.model(MeshKit.roundedBox([0.210, 0.030, 0.095], radius: 0.010, bevel: 0.008), material: yellow)
        platenModel.position = [0, 0.008 + 0.015, platenZ]
        platenGroup.addChild(platenModel)
        for side: Float in [-1, 1] {
            let collar = MeshKit.model(MeshKit.roundedCylinder(radius: 0.018, height: 0.034, bevel: 0.005, segments: 48), material: yellow)
            collar.position = [side * Self.columnX, 0.006, Self.columnZ]
            platenGroup.addChild(collar)
        }
        if let texture = StudioEnvironment.texture(RigTextures.hazard(), name: "hazard") {
            var material = SceneMaterials.textured(texture, roughness: 0.45, clearcoat: 0.6)
            material.clearcoatRoughness = .init(floatLiteral: 0.12)
            // Teaching glows the band itself: the stripes' own colours, emissive 0 until `setTeachGlow`.
            material.emissiveColor = .init(color: Palette.hydraulicYellow, texture: .init(texture))
            material.emissiveIntensity = 0
            let band = ModelEntity(mesh: .generatePlane(width: 0.150, height: 0.010, cornerRadius: 0.002), materials: [material])
            band.position = [0, 0.008 + 0.006, platenZ + 0.0475 + 0.0003]
            platenGroup.addChild(band)
            hazardBand = band
            hazardMaterial = material
        }
        let plate = MeshKit.model(MeshKit.roundedBox([0.110, 0.008, 0.090], radius: 0.003, bevel: 0.0025), material: steel)
        plate.position = [0, 0.004, 0]
        platenGroup.addChild(plate)
        root.addChild(ram)

        buildSealTag()
        setFace(Self.homeFace)
        setNeedle(0)
        setLamps(ready: 1, load: 0)
        ShadowCasting.offForTranslucent(in: root)
    }

    // MARK: - Per frame

    /// Moves the crosshead (face height above the anvil) and stretches the rod to meet it.
    func setFace(_ y: Float, jitter: SIMD2<Float> = .zero) {
        ram.position = SIMD3(jitter.x, y, jitter.y)
        let platenTop = y + platenTopLocal
        let length = max(Self.barrelBottom + 0.004 - platenTop + 0.004, 0.004)
        rod.scale = SIMD3(1, length, 1)
    }

    /// Tonnage needle (0–60 t dial; > 60 pins into the red), spring response ≈ 0.18 s, damping 0.55.
    /// `panic`: slam warning (UX-REVIEW P0-5) — a wide, fast needle shiver, the non-text "slowly…" cue.
    func updateGauge(tons target: Float, dt: Float, tremor: Bool, buzz: Bool, panic: Bool = false, time: Float) {
        guard dt > 0 else { return }
        let omega: Float = 2 * .pi / 0.18, zeta: Float = 0.55
        let steps = max(1, Int((dt * 480).rounded(.up)))
        let h = dt / Float(steps)
        for _ in 0..<steps {
            let accel = -2 * zeta * omega * needleVelocity - omega * omega * (needleTons - target)
            needleVelocity += accel * h
            needleTons += needleVelocity * h
        }
        var shown = min(needleTons, 63)
        if tremor { shown += 0.8 / 4.5 * sin(time * 2 * .pi * 14) }      // ±0.8° at 14 Hz
        if panic { shown += 3.5 * sin(time * 2 * .pi * 19) * sin(time * 2 * .pi * 3.1) }
        if buzz { shown = 62 + 0.6 * sin(time * 2 * .pi * 23) }          // pinned and buzzing
        if !tremor && !buzz && target < 0.01 { shown += 0.3 / 4.5 * sin(time * 2 * .pi * 0.4) } // idle breathing
        setNeedle(shown)
    }

    /// Kick the needle (contact +2 t, failure overshoot).
    func kickGauge(_ tons: Float) {
        needleVelocity += tons * 18
    }

    private func setNeedle(_ tons: Float) {
        // Dial angle θ = 225° − 270°·t/60 (CCW from +x); the needle model points to 12 o'clock (90°).
        let theta = (225 - 270 * clamp(tons, -1, 63) / 60) * Float.pi / 180
        needlePivot.orientation = simd_quatf(angle: theta - .pi / 2, axis: [0, 0, 1])
    }

    /// 0 = off, 1 = green/amber, 2 = red.
    private func setLamps(ready: Int, load: Int) {
        if lampState.ready != ready {
            readyLamp.model?.materials = [ready == 1 ? greenOn : (ready == 2 ? redOn : lampOffMaterial)]
        }
        if lampState.load != load {
            loadLamp.model?.materials = [load == 1 ? amberOn : (load == 2 ? redOn : lampOffMaterial)]
        }
        lampState = (ready, load)
    }

    /// §4.5: green READY when idle, amber LOAD from contact, red 600 ms at failure; the Unsquishable blinks both red at 2 Hz.
    /// `powerOn`: seconds into the launch power-on beat (UX-REVIEW P2-1), lamps flick on one by one; nil = normal.
    func updateLamps(dt: Float, loaded: Bool, broken: Bool, powerOn: Float? = nil) {
        redTimer = max(redTimer - dt, 0)
        if let t = powerOn {
            if t < 0.15 {
                setLamps(ready: 0, load: 0)
            } else if t < 0.3 {
                setLamps(ready: 1, load: 0)
            } else if t < 0.45 {
                setLamps(ready: 1, load: 1)
            } else {
                setLamps(ready: 1, load: 0)
            }
            return
        }
        if broken {
            blink += dt
            let on = Int(blink * 4) % 2 == 0
            setLamps(ready: on ? 2 : 0, load: on ? 2 : 0)
            return
        }
        if redTimer > 0 {
            setLamps(ready: 0, load: 2)
        } else if loaded {
            setLamps(ready: 0, load: 1)
        } else {
            setLamps(ready: 1, load: 0)
        }
    }

    func flashRed() {
        redTimer = 0.6
    }

    /// Soft yellow glow on the crosshead (first-run teaching). 0 hides it.
    func setTeachGlow(_ level: Float) {
        let a = clamp(level, 0, 1)
        guard abs(a - glowAlpha) > 0.03 || (a == 0 && glowAlpha != 0) else { return }
        glowAlpha = a
        // No overlay geometry: the hazard band's own stripes glow (emissive 0 → 0.5) and the platen enamel warms (0 → 0.12).
        if let band = hazardBand, var material = hazardMaterial {
            material.emissiveIntensity = 0.5 * a
            band.model?.materials = [material]
        }
        var platen = platenMaterial
        platen.emissiveColor = .init(color: Palette.hydraulicYellow)
        platen.emissiveIntensity = 0.12 * a
        platenModel.model?.materials = [platen]
    }

    // MARK: - Sealed tag (touch presses have no cover display: UX-REVIEW P2-4)

    /// A paper tag "SEALED · 48 T" that swings from the crown's front lip.
    func showSealTag(tons: Int) {
        let material: any Material
        if let texture = StudioEnvironment.texture(RigTextures.sealTag(tons: tons), name: "seal.tag.\(tons)") {
            material = SceneMaterials.textured(texture, roughness: 0.7)
        } else {
            material = SceneMaterials.pbr(Palette.paper, roughness: 0.7)
        }
        sealTagCard.model?.materials = [material]
        sealTag.isEnabled = true
        tagSwing = JiggleSpring(value: 0, velocity: 3.2, omega: 7.5, zeta: 0.18)
    }

    func hideSealTag() {
        sealTag.isEnabled = false
    }

    func updateSealTag(dt: Float, reduceMotion: Bool) {
        guard sealTag.isEnabled else { return }
        tagSwing.step(toward: 0, dt: dt)
        let angle = reduceMotion ? 0 : clamp(tagSwing.value, -0.5, 0.5)
        sealTag.orientation = simd_quatf(angle: angle, axis: [0, 0, 1])
    }

    private func buildSealTag() {
        // Pivot under the crown's front lip, right of centre; string + card hang below.
        sealTag.position = [0.035, 0.330, 0.054]
        let string = MeshKit.model(MeshKit.capsule(radius: 0.0006, length: 0.016, segments: 8),
                                   material: SceneMaterials.pbr(Palette.enamelGraphite, roughness: 0.6))
        string.position = [0, -0.016, 0]
        sealTag.addChild(string)
        sealTagCard.model = ModelComponent(mesh: .generatePlane(width: 0.052, height: 0.022, cornerRadius: 0.004),
                                           materials: [SceneMaterials.pbr(Palette.paper, roughness: 0.7)])
        sealTagCard.position = [0, -0.016 - 0.011, 0.0004]
        sealTag.addChild(sealTagCard)
        sealTag.isEnabled = false
        root.addChild(sealTag)
    }

    // MARK: - The Unsquishable breaks the press (§4.6)

    /// 1, 2: the plate starts to crack; 3: crack branches, the platen bends 2.5°, a bolt pops off, the gauge glass cracks.
    func crack(level: Int, fx: SceneFX, seed: UInt64) {
        guard level > damage else { return }
        var rng = SplitMix64(seed: seed &+ UInt64(level) &* 7919)
        let ink = SceneMaterials.pbr(Palette.rubber, roughness: 0.7)
        func crackBranch(from start: SIMD2<Float>, segments: Int, heading: Float) {
            var p = start
            var h = heading
            for _ in 0..<segments {
                let length = Float.random(in: 0.005...0.010, using: &rng)
                h += Float.random(in: -0.8...0.8, using: &rng)
                let d = SIMD2<Float>(cos(h), sin(h) * 0.3)
                let mid = p + d * length / 2
                let line = MeshKit.model(MeshKit.roundedBox([length, 0.0015, 0.0008], radius: 0.0003, bevel: 0.0002), material: ink)
                // Plate front face is at z = +0.045, plate spans y 0…0.012 (ram local).
                line.position = [mid.x, clamp(0.004 + mid.y, 0.0008, 0.0072), 0.0452]
                line.orientation = simd_quatf(angle: atan2(d.y, d.x), axis: [0, 0, 1])
                platenGroup.addChild(line)
                damageMarks.append(line)
                p += d * length
            }
        }
        for l in (damage + 1)...level {
            switch l {
            case 1:
                crackBranch(from: SIMD2(-0.004, 0), segments: 3, heading: Float.pi)
            case 2:
                crackBranch(from: SIMD2(0.004, 0), segments: 3, heading: 0)
                fx.particles.burst(.dust, count: 3, at: [0, 0.29, 0.02], speed: 0.03,
                                   colors: [Palette.cream], size: 0.006...0.01, upBias: 0.6, life: 0.8, rng: &rng)
            default:
                crackBranch(from: SIMD2(-0.016, -0.001), segments: 4, heading: Float.pi + 0.3)
                crackBranch(from: SIMD2(0.014, 0.001), segments: 4, heading: -0.2)
                crackBranch(from: SIMD2(0, 0), segments: 3, heading: 1.3)
                platenGroup.orientation = simd_quatf(angle: 2.5 * .pi / 180, axis: [0, 0, 1])
                // One hex bolt pops off as rigid debris.
                let bolt = bolts[Int(rng.next() % UInt64(bolts.count))]
                fx.debris.adopt(bolt, velocity: SIMD3(Float.random(in: -0.2...0.2, using: &rng), 0.45, 0.25) * max(fx.motionScale, 0.3),
                                spin: Burst.spin(14 * fx.motionScale, rng: &rng), bounciness: 0.45, friction: 0.3)
                // Gauge glass cracks: three white lines.
                let white = SceneMaterials.unlit(.white, opacity: 0.7)
                for k in 0..<3 {
                    let a = Float(k) * 2.1 + Float.random(in: -0.3...0.3, using: &rng)
                    let line = ModelEntity(mesh: .generateBox(width: 0.016, height: 0.0006, depth: 0.0004), materials: [white])
                    line.position = [cos(a) * 0.007, sin(a) * 0.007, 0.0062]
                    line.orientation = simd_quatf(angle: a, axis: [0, 0, 1])
                    gaugeGlass.addChild(line)
                    damageMarks.append(line)
                }
                fx.particles.burst(.spark, count: 14, at: [0, 0.001, 0.03], speed: 0.6 * max(fx.motionScale, 0.4),
                                   colors: [Palette.spark, UIColor(hex: 0xFFE7A0)], size: 0.0012...0.0022,
                                   upBias: 0.1, life: 0.45, rng: &rng)
                fx.particles.burst(.dust, count: 6, at: [0, 0.29, 0.02], speed: 0.04,
                                   colors: [Palette.cream], size: 0.008...0.014, upBias: 0.7, life: 0.9, rng: &rng)
                blink = 0
            }
        }
        damage = level
        ShadowCasting.offForTranslucent(in: root)
    }

    /// A fresh press for the next object.
    func repair() {
        for mark in damageMarks { mark.removeFromParent() }
        damageMarks.removeAll()
        for (i, bolt) in bolts.enumerated() {
            if bolt.parent !== root { root.addChild(bolt) }
            bolt.transform = boltRest[i]
        }
        platenGroup.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
        damage = 0
        redTimer = 0
        hideSealTag()
    }
}
