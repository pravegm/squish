import Foundation
import RealityKit
import simd
import UIKit

/// Jelly (bible §4 #3, VISUAL-TARGET §5.3): a fluted raspberry mould jelly. Fake SSS: a translucent shell
/// (CPU-deformed `DeformableMesh`) over an opaque darker core. Wobble springs (ζ 0.25) for idle life and impacts.
/// Fracture 0 (skin split, ~0.30): droplets squirt from a side and a small overflow spreads.
/// Fracture 1 (failure splat, ~0.55): the body splorts — a glossy spread disc grows to Ø 0.15 with 6–10 blobs out
/// at the sides, droplets land and stay. Surprise `fruitPieces`: candy cubes between core and shell; some pop out.
@MainActor
final class JellyView: PressObjectView {
    let entity = Entity()
    let restHeight: Float = 0.0765
    let footprint: Float = 0.049
    private let minHeightRatio: Float = 0.13

    private let fx: SceneFX
    private let look: Look
    private var rng = SplitMix64(seed: 0)
    private let shell: DeformableMesh
    private let core: ModelEntity
    private let spreadDisc: ModelEntity
    private var splorts: [(entity: ModelEntity, direction: SIMD2<Float>, size: Float)] = []
    private var fruit: [(entity: ModelEntity, rest: SIMD3<Float>)] = []
    private var wobbleX = JiggleSpring(value: 0, velocity: 0, omega: 2 * .pi * 1.8, zeta: 0.25)
    private var wobbleZ = JiggleSpring(value: 0, velocity: 0, omega: 2 * .pi * 1.6, zeta: 0.25)
    private var bounce = JiggleSpring(value: 0, velocity: 0, omega: 2 * .pi * 2.4, zeta: 0.3)
    private var split = false
    private var splat = false
    private var splatC: Float = 1
    private var lastKey = SIMD4<Float>(repeating: -1)
    private var spread: Float = 1
    private let dropColors: [UIColor]

    var shadowSpread: Float { spread }

    static let profile: [SIMD2<Float>] = MeshKit.smoothProfile([
        SIMD2(0.000, 0.000), SIMD2(0.044, 0.000), SIMD2(0.048, 0.003), SIMD2(0.049, 0.008), SIMD2(0.047, 0.020),
        SIMD2(0.044, 0.035), SIMD2(0.041, 0.048), SIMD2(0.038, 0.058), SIMD2(0.033, 0.066), SIMD2(0.024, 0.072),
        SIMD2(0.012, 0.0755), SIMD2(0.000, 0.0765),
    ], perSpan: 3)

    /// Fluted mould mesh: r(y, θ) = r₀(y)·(1 + 0.07·cos 8θ·f(y)), flutes fading out toward the apex.
    static func mould(scale: Float = 1) -> MeshData {
        var mesh = MeshKit.lathe(profile: profile, segments: 64)
        for i in mesh.positions.indices {
            let p = mesh.positions[i]
            let r = (p.x * p.x + p.z * p.z).squareRoot()
            guard r > 1e-6 else { continue }
            let theta = atan2(p.z, p.x)
            let f = clamp((0.070 - p.y) / 0.010, 0, 1)
            let k = 1 + 0.07 * cos(8 * theta) * f
            mesh.positions[i] = SIMD3(p.x * k, p.y, p.z * k) * scale
        }
        mesh.recomputeNormals()
        return mesh
    }

    init(variant: PressVariant, fx: SceneFX) {
        self.fx = fx
        let look = Look(variant)
        self.look = look
        rng = SplitMix64(seed: variant.seed ^ 0x7E11)
        var shellMaterial = look.golden ? SceneMaterials.gold
            : SceneMaterials.enamel(Palette.raspberry, roughness: 0.08, clearcoat: 1, clearcoatRoughness: 0.03, opacity: 0.86)
        if !look.golden {
            shellMaterial.emissiveColor = .init(color: UIColor(hex: 0xFF5A8A))
            shellMaterial.emissiveIntensity = 0.22
        }
        let coreMaterial = SceneMaterials.pbr(UIColor(hex: 0xB81E52), roughness: 0.3)
        dropColors = look.golden ? [Palette.goldMessColor] : [Palette.raspberry, UIColor(hex: 0xF0487A)]
        shell = DeformableMesh(MeshCache.mesh("jelly.mould") { Self.mould() }, materials: [shellMaterial], maxSpread: 2.2)
        core = ModelEntity(mesh: MeshCache.resource("jelly.core") { Self.mould(scale: 0.8) } ?? .generateSphere(radius: 0.03),
                           materials: [look.golden ? SceneMaterials.gold : coreMaterial])
        let discMaterial = look.golden ? SceneMaterials.goldMess
            : SceneMaterials.enamel(Palette.raspberry, roughness: 0.08, clearcoat: 1, clearcoatRoughness: 0.03, opacity: 0.92)
        spreadDisc = ModelEntity(mesh: MeshKit.spreadDisc(seed: variant.seed, height: 1, segments: 64, wobble: 0.12).resource()
                                 ?? .generateSphere(radius: 0.01), materials: [discMaterial])
        spreadDisc.isEnabled = false
        entity.addChild(core)
        entity.addChild(shell.entity)
        entity.addChild(spreadDisc)

        if variant.surprise == .fruitPieces {
            let colors = [Palette.hydraulicYellow, Palette.lime, Palette.tangerine]
            for k in 0..<5 {
                let a = Float(k) / 5 * 2 * .pi + Float.random(in: -0.3...0.3, using: &rng)
                let y = Float.random(in: 0.012...0.045, using: &rng)
                let r = Self.radius(at: y) * 0.86
                let rest = SIMD3<Float>(cos(a) * r, y, sin(a) * r)
                let cube = Part.add(cached: "jelly.fruit", { MeshKit.roundedBox([0.010, 0.010, 0.010], radius: 0.0025) },
                                    SceneMaterials.enamel(colors[k % colors.count], roughness: 0.25, clearcoat: 0.8,
                                                          clearcoatRoughness: 0.1),
                                    at: rest, to: entity)
                cube.orientation = simd_quatf(angle: Float.random(in: 0...3, using: &rng),
                                              axis: simd_normalize(SIMD3<Float>(1, Float.random(in: -1...1, using: &rng), 0.4)))
                fruit.append((cube, rest))
            }
        }
        wobbleX.kick(0.12)
    }

    static func radius(at y: Float) -> Float {
        for i in 0..<(profile.count - 1) where y <= profile[i + 1].y {
            let a = profile[i], b = profile[i + 1]
            let t = (y - a.y) / max(b.y - a.y, 1e-6)
            return a.x + (b.x - a.x) * t
        }
        return 0
    }

    func surfaceHeight(compression c: Float) -> Float {
        HeightCurve.linear(c, rest: restHeight, minRatio: minHeightRatio)
    }

    func update(_ state: PressVisualState) {
        let dt = state.dt
        // Idle life: a gentle top lean at ~1.8 Hz after landing; impacts excite it.
        wobbleX.step(toward: 0, dt: dt)
        wobbleZ.step(toward: 0, dt: dt)
        bounce.step(toward: 0, dt: dt)
        if state.loaded && !state.reduceMotion {
            wobbleX.kick(sin(state.time * 13) * 0.002 * state.compression)
        }
        let h = surfaceHeight(compression: state.compression)
        let s = clamp(h / restHeight * (1 + 0.04 * bounce.value), 0.05, 1.04)
        let lean = state.reduceMotion ? SIMD2<Float>.zero : SIMD2(wobbleX.value, wobbleZ.value) * 0.004 * s
        let bulge: Float = splat ? 0.55 : (split ? 0.42 : 0.32)
        let maxSpread: Float = splat ? 1.75 : 1.55
        let key = SIMD4<Float>(s, lean.x, lean.y, bulge)
        if simd_length(key - lastKey) > 0.0004 {
            lastKey = key
            shell.update { p in
                Deform.squash(p, s: s, restHeight: self.restHeight, bulge: bulge, maxSpread: maxSpread, shear: lean)
            }
        }
        spread = min(1 / s.squareRoot(), maxSpread) * (1 + bulge * (1 - s) * 0.5)
        let coreSpread = min(1 / s.squareRoot(), maxSpread) * 0.97
        core.scale = SIMD3(coreSpread, s, coreSpread)
        core.position = SIMD3(lean.x * 0.5, 0, lean.y * 0.5)
        for piece in fruit where piece.entity.parent === entity {
            piece.entity.position = SIMD3(piece.rest.x * coreSpread * 1.05 + lean.x * piece.rest.y / restHeight,
                                          piece.rest.y * s,
                                          piece.rest.z * coreSpread * 1.05 + lean.y * piece.rest.y / restHeight)
            piece.entity.scale = SIMD3(1, max(s, 0.35), 1)
        }

        // Spread (overflow → splat) grows with compression past the split, up to Ø 0.15.
        if split {
            let t = clamp((state.compression - splatC) / max(1 - splatC, 0.05), 0, 1)
            let radius: Float = splat ? 0.05 + 0.025 * t : 0.045
            let thickness: Float = 0.004 * (splat ? 1 : 0.6)
            spreadDisc.isEnabled = true
            spreadDisc.scale = SIMD3(radius, thickness, radius * 0.92)
            for blob in splorts {
                let d = 0.045 + 0.03 * t
                let flat = max(0.3, min(1, h / 0.02)) * 0.4
                blob.entity.position = SIMD3(blob.direction.x * d, blob.size * 0.5 * flat, blob.direction.y * d)
                blob.entity.scale = SIMD3(1 + t * 0.6, flat, 1 + t * 0.6) * (blob.size * 0.5)
            }
            spread = max(spread, radius / footprint)
        }
    }

    func fracture(index: Int, isFailure: Bool, state: PressVisualState) {
        let speed = 0.35 * fx.motionScale
        if !isFailure {
            // Skin split: a squirt from one side.
            split = true
            splatC = state.compression
            wobbleX.kick(2)
            let a = Float.random(in: 0...(2 * .pi), using: &rng)
            let at = entity.convert(position: [cos(a) * 0.045, 0.02, sin(a) * 0.045], to: fx.root)
            for _ in 0..<ParticleSystem.scaled(6) {
                let v = SIMD3<Float>(cos(a), 0.6, sin(a)) * speed * Float.random(in: 0.6...1.2, using: &rng)
                fx.particles.emit(.droplet, at: at, velocity: v, color: dropColors.pick(&rng),
                                  size: Float.random(in: 0.003...0.006, using: &rng), rng: &rng)
            }
        } else {
            // Splat: splorts out of the sides; the disc grows from here to full compression.
            split = true
            splat = true
            splatC = state.compression
            wobbleX.kick(4)
            wobbleZ.kick(-3)
            bounce.kick(-6)
            let blobMaterial = look.golden ? SceneMaterials.goldMess
                : SceneMaterials.enamel(Palette.raspberry, roughness: 0.08, clearcoat: 1, clearcoatRoughness: 0.03, opacity: 0.92)
            let count = 6 + Int(rng.next() % 5)
            for k in 0..<count {
                let a = Float(k) / Float(count) * 2 * .pi + Float.random(in: -0.25...0.25, using: &rng)
                let size = Float.random(in: 0.012...0.022, using: &rng)
                let blob = Part.add(cached: "jelly.splort", { MeshKit.sphere(radius: 1, segments: 24, rings: 12) },
                                    blobMaterial, to: entity)
                blob.scale = SIMD3(repeating: size * 0.5)
                splorts.append((blob, SIMD2(cos(a), sin(a)), size))
            }
            for _ in 0..<ParticleSystem.scaled(10) {
                let dir = Burst.unitDirection(rng: &rng, upBias: 0.15)
                let at = entity.convert(position: [dir.x * 0.04, 0.012, dir.z * 0.04], to: fx.root)
                fx.particles.emit(.droplet, at: at, velocity: SIMD3(dir.x, dir.y * 0.8, dir.z) * speed * 1.3,
                                  color: dropColors.pick(&rng), size: Float.random(in: 0.003...0.007, using: &rng), rng: &rng)
            }
            // Some fruit pops out onto the anvil.
            for (i, piece) in fruit.enumerated() where i % 2 == 0 {
                let dir = simd_normalize(SIMD3<Float>(piece.rest.x, 0, piece.rest.z) + SIMD3(0, 0.0001, 0))
                fx.debris.adopt(piece.entity, velocity: (dir * 0.25 + SIMD3(0, 0.35, 0)) * fx.motionScale,
                                spin: Burst.spin(8 * fx.motionScale, rng: &rng), bounciness: 0.2)
            }
        }
    }

    func handle(_ event: PressEvent, state: PressVisualState) {
        switch event {
        case .contact: bounce.kick(-3)
        case .released: wobbleX.kick(1.5); bounce.kick(2)
        default: break
        }
    }
}
