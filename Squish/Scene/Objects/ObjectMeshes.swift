import Foundation
import simd

/// The heavy procedural meshes of the object views, as pure nonisolated builders so they can run off the main
/// actor (startup budget: VISUAL-REVIEW-1 / lead's perf note). `PressScene.setObject` builds them in a detached task,
/// stores them in `MeshCache`, then assembles the view on main. Keys must match the views' `MeshCache` keys.
enum ObjectMeshes {
    typealias Job = (key: String, build: () -> MeshData)

    /// The jobs for one object (empty = nothing heavy, build the view straight away).
    static func jobs(for kind: ObjectKind) -> [Job] {
        switch kind {
        case .rubberDuck:
            return [("duck.body", duckBody), ("duck.beak", duckBeak)]
        case .gummyBear:
            return [
                ("gummy.shell.full", { gummy(side: nil, coreScale: 1) }), ("gummy.core.full", { gummy(side: nil, coreScale: 0.82) }),
                ("gummy.shell.L", { gummy(side: 1, coreScale: 1) }), ("gummy.shell.R", { gummy(side: -1, coreScale: 1) }),
                ("gummy.core.L", { gummy(side: 1, coreScale: 0.82) }), ("gummy.core.R", { gummy(side: -1, coreScale: 0.82) }),
            ]
        case .jelly:
            return [("jelly.mould", { jellyMould(scale: 1) }), ("jelly.core", { jellyMould(scale: 0.8) })]
        case .sodaCan:
            return [("can.body", canBody)]
        case .unsquishable:
            return [("ball", { MeshKit.sphere(radius: ballRadius, segments: 64, rings: 48) })]
        case .bubbleWrap, .crayon, .egg, .cakeSlice, .glassBottle:
            return []
        }
    }

    static func build(_ kind: ObjectKind) -> [(String, MeshData)] {
        if kind == .gummyBear {
            // Three SDF meshings instead of six: each core is its shell scaled about the same centre.
            var results: [(String, MeshData)] = []
            for (name, side) in [("full", Float?.none), ("L", Float?.some(1)), ("R", Float?.some(-1))] {
                let shell = gummy(side: side, coreScale: 1)
                results.append(("gummy.shell.\(name)", shell))
                results.append(("gummy.core.\(name)", scaled(shell, about: gummyCentre(side), by: 0.82)))
            }
            return results
        }
        return jobs(for: kind).map { ($0.key, $0.build()) }
    }

    static func gummyCentre(_ side: Float?) -> SIMD3<Float> {
        SIMD3(-(side ?? 0) * 0.015, 0.046, 0.004)
    }

    static func scaled(_ mesh: MeshData, about centre: SIMD3<Float>, by k: Float) -> MeshData {
        var copy = mesh
        copy.positions = mesh.positions.map { centre + ($0 - centre) * k }
        return copy
    }

    // MARK: Duck (VISUAL-TARGET §5.2), unit scale; the view scales it ×1.25 (VISUAL-REVIEW-1 fix 6)

    static func duckBody() -> MeshData {
        var blob = SDFBlob()
        blob.add([0, 0.026, 0], [0.038, 0.026, 0.029])
        blob.add([0.019, 0.029, 0], radius: 0.021)
        blob.add([-0.032, 0.038, 0], [0.014, 0.017, 0.015], k: 0.008,
                 rotation: simd_quatf(angle: 35 * .pi / 180, axis: [0, 0, 1]))
        blob.add([0.020, 0.062, 0], radius: 0.023, k: 0.010)
        for side: Float in [-1, 1] {
            let rotation = simd_quatf(angle: side * 10 * .pi / 180, axis: [0, 1, 0])
                * simd_quatf(angle: -15 * .pi / 180, axis: [0, 0, 1])
            blob.add([-0.002, 0.030, 0.026 * side], [0.020, 0.011, 0.006], k: 0.004, rotation: rotation)
        }
        return blob.mesh(centre: [0.0, 0.036, 0], reach: 0.1, rings: 44, segments: 60)
    }

    static func duckBeak() -> MeshData {
        var blob = SDFBlob()
        blob.floor = nil
        blob.add([0.044, 0.058, 0], [0.012, 0.0042, 0.009])
        blob.add([0.041, 0.0525, 0], [0.009, 0.003, 0.0075], k: 0.003)
        return blob.mesh(centre: [0.043, 0.0555, 0], reach: 0.03, rings: 20, segments: 32)
    }

    // MARK: Gummy bear (§5.8): one welded blob for idle, two clipped halves for the split

    static func gummyBlob(side: Float?) -> SDFBlob {
        var blob = SDFBlob()
        blob.add([0, 0.034, 0], [0.034, 0.034, 0.026])
        blob.add([0, 0.030, 0.008], radius: 0.026)
        blob.add([0, 0.078, 0.002], radius: 0.025)
        blob.add([0, 0.072, 0.022], radius: 0.011)
        for s: Float in [-1, 1] {
            blob.add([s * 0.018, 0.098, 0], radius: 0.009)
            blob.add([s * 0.034, 0.045, 0.006], [0.011, 0.018, 0.011], k: 0.008,
                     rotation: simd_quatf(angle: s * 25 * .pi / 180, axis: [0, 0, 1]))
            blob.add([s * 0.020, 0.012, 0.020], [0.013, 0.012, 0.018])
        }
        if let side {
            blob.clipNormal = SIMD3(side, 0, 0)
            blob.clipPoint = .zero
        }
        return blob
    }

    /// side +1 keeps x ≤ 0 (left half), −1 keeps x ≥ 0 (right half), nil = the whole bear.
    static func gummy(side: Float?, coreScale: Float) -> MeshData {
        let centre = gummyCentre(side)
        var mesh = gummyBlob(side: side).mesh(centre: centre, reach: 0.11, rings: 40, segments: 52)
        if coreScale != 1 {
            mesh.positions = mesh.positions.map { centre + ($0 - centre) * coreScale }
        }
        return mesh
    }

    // MARK: Jelly (§5.3)

    static let jellyProfile: [SIMD2<Float>] = MeshKit.smoothProfile([
        SIMD2(0.000, 0.000), SIMD2(0.044, 0.000), SIMD2(0.048, 0.003), SIMD2(0.049, 0.008), SIMD2(0.047, 0.020),
        SIMD2(0.044, 0.035), SIMD2(0.041, 0.048), SIMD2(0.038, 0.058), SIMD2(0.033, 0.066), SIMD2(0.024, 0.072),
        SIMD2(0.012, 0.0755), SIMD2(0.000, 0.0765),
    ], perSpan: 3)

    /// Fluted mould: r(y, θ) = r₀(y)·(1 + 0.07·cos 8θ·f(y)), flutes fading out toward the apex.
    static func jellyMould(scale: Float) -> MeshData {
        var mesh = MeshKit.lathe(profile: jellyProfile, segments: 64)
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

    // MARK: Soda can (§5.7), Ø 0.110 × 0.140 (VISUAL-REVIEW-1 fix 6)

    static let canR: Float = 0.055 / 0.045
    static let canY: Float = 0.140 / 0.150
    static let canBodyBottom: Float = 0.011 * canY
    static let canBodyTop: Float = 0.126 * canY

    static func canProfile() -> [SIMD2<Float>] {
        var points: [SIMD2<Float>] = [
            SIMD2(0.000, 0.008), SIMD2(0.018, 0.0065), SIMD2(0.028, 0.002), SIMD2(0.030, 0.000), SIMD2(0.039, 0.0015),
            SIMD2(0.043, 0.005), SIMD2(0.045, 0.011),
        ]
        let rings = 46
        for k in 1..<rings {
            points.append(SIMD2(0.045, 0.011 + (0.126 - 0.011) * Float(k) / Float(rings)))
        }
        points += [
            SIMD2(0.045, 0.126), SIMD2(0.043, 0.134), SIMD2(0.0385, 0.142), SIMD2(0.036, 0.146), SIMD2(0.0368, 0.148),
            SIMD2(0.036, 0.150), SIMD2(0.0345, 0.149), SIMD2(0.0335, 0.1455), SIMD2(0.000, 0.1455),
        ]
        return points.map { SIMD2($0.x * canR, $0.y * canY) }
    }

    /// Slot 0: the printed body (textured, v over the straight body). Slot 1: bare aluminium ends.
    static func canBody() -> MeshData {
        let profile = canProfile()
        return MeshKit.latheUV(profile: profile, segments: 64, vRange: canBodyBottom...canBodyTop, material: { i in
            let y = (profile[i].y + profile[i + 1].y) / 2
            return (y < canBodyBottom || y > canBodyTop) ? 1 : 0
        })
    }

    // MARK: The Unsquishable, Ø 0.110 (VISUAL-REVIEW-1 fix 6)

    static let ballRadius: Float = 0.055
}
