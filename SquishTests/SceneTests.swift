import Foundation
import simd
import Testing
@testable import Squish

/// Pure geometry and simulation helpers from Scene/Kit (no RealityKit rendering needed).
struct SceneTests {
    private func expectValid(_ mesh: MeshData, _ label: String) {
        #expect(mesh.isValid, "\(label) is not a valid mesh")
        #expect(mesh.indices.count % 3 == 0, "\(label) index count")
        #expect(mesh.normals.allSatisfy { abs(simd_length($0) - 1) < 0.01 }, "\(label) normals not unit length")
        #expect(mesh.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }, "\(label) non-finite")
    }

    @Test func buildersProduceValidMeshes() {
        expectValid(MeshKit.sphere(radius: 0.02), "sphere")
        expectValid(MeshKit.ellipsoid(radii: [0.03, 0.01, 0.02], segments: 24, rings: 12), "ellipsoid")
        expectValid(MeshKit.roundedBox([0.1, 0.02, 0.05], radius: 0.006, bevel: 0.002), "roundedBox")
        expectValid(MeshKit.roundedCylinder(radius: 0.02, height: 0.05, bevel: 0.004), "roundedCylinder")
        expectValid(MeshKit.capsule(radius: 0.003, length: 0.03), "capsule")
        expectValid(MeshKit.torus(major: 0.02, minor: 0.003), "torus")
        expectValid(MeshKit.spreadDisc(seed: 7), "spreadDisc")
        let hexagon: [SIMD2<Float>] = (0..<6).map { k in SIMD2(cos(Float(k) * .pi / 3), sin(Float(k) * .pi / 3)) * 0.005 }
        expectValid(MeshKit.roundedPrism(polygon: hexagon, height: 0.004, cornerRadius: 0.0009, bevel: 0.0008), "hex prism")
        expectValid(MeshKit.lathe(profile: MeshKit.smoothProfile([SIMD2(0, 0), SIMD2(0.02, 0.01), SIMD2(0.015, 0.04), SIMD2(0, 0.05)]),
                                  segments: 32), "smooth lathe")
    }

    @Test func latheIndexCountMatchesTopology() {
        // 2 poles + 2 rings of 16: 16 cap triangles at each pole + 2 × 16 side triangles.
        let mesh = MeshKit.lathe(profile: [SIMD2(0, 0), SIMD2(0.01, 0), SIMD2(0.01, 0.02), SIMD2(0, 0.02)], segments: 16)
        #expect(mesh.vertexCount == 2 + 2 * 16)
        #expect(mesh.triangleCount == 16 + 2 * 16 + 16)
    }

    @Test func windingFacesOutward() {
        // Every triangle's face normal should agree with the outward direction of a sphere.
        let mesh = MeshKit.sphere(radius: 1, segments: 16, rings: 8)
        var i = 0
        while i + 2 < mesh.indices.count {
            let a = mesh.positions[Int(mesh.indices[i])], b = mesh.positions[Int(mesh.indices[i + 1])]
            let c = mesh.positions[Int(mesh.indices[i + 2])]
            let face = simd_cross(b - a, c - a)
            if simd_length(face) > 1e-8 {
                #expect(simd_dot(face, (a + b + c) / 3) > 0)
            }
            i += 3
        }
    }

    @Test func multiMaterialSplitKeepsAllTriangles() {
        let profile: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(0.01, 0), SIMD2(0.01, 0.01), SIMD2(0.01, 0.02), SIMD2(0, 0.02)]
        let mesh = MeshKit.lathe(profile: profile, segments: 12, material: { UInt8($0 % 2) })
        let parts = mesh.splitByMaterial()
        #expect(parts.count == 2)
        #expect(parts.reduce(0) { $0 + $1.mesh.triangleCount } == mesh.triangleCount)
        for part in parts { #expect(part.mesh.isValid) }
    }

    @Test func lathePatchIsCentredAndValid() {
        let profile: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(0.02, 0.01), SIMD2(0.025, 0.03), SIMD2(0.02, 0.05), SIMD2(0, 0.06)]
        let patch = MeshKit.lathePatch(profile: profile, rings: 1...3, angles: 0...1.2, angularSteps: 6, thickness: 0.001)
        expectValid(patch.mesh, "patch")
        #expect(simd_length(patch.mesh.centroid) < 1e-4)
        #expect(simd_length(patch.centre) > 0.01)
    }

    @Test func sdfBlobMeshesAroundItsCentre() {
        var blob = SDFBlob()
        blob.add([0, 0.02, 0], radius: 0.02)
        let mesh = blob.mesh(centre: [0, 0.02, 0], reach: 0.05, rings: 12, segments: 16)
        expectValid(mesh, "sdf")
        // Every vertex sits on the sphere (or the flat base).
        for p in mesh.positions {
            let d = simd_length(p - SIMD3(0, 0.02, 0))
            #expect(d < 0.0205)
        }
    }

    @Test func debrisIsDeterministicAndSettlesOnTheAnvil() {
        func run() -> [SIMD3<Float>] {
            var world = DebrisWorld()
            var rng = SplitMix64(seed: 99)
            for _ in 0..<12 {
                world.bodies.append(DebrisBody(
                    position: [Float.random(in: -0.03...0.03, using: &rng), 0.05, Float.random(in: -0.03...0.03, using: &rng)],
                    velocity: Burst.unitDirection(rng: &rng) * 0.6, orientation: simd_quatf(angle: 0.3, axis: [1, 0, 0]),
                    angularVelocity: Burst.spin(10, rng: &rng), halfExtents: [0.006, 0.002, 0.005]))
            }
            for _ in 0..<600 { world.step(dt: 1.0 / 120.0) }
            return world.bodies.map(\.position)
        }
        let a = run(), b = run()
        #expect(a == b)
        for p in a {
            #expect(p.y >= 0 && p.y < 0.01)
            #expect(abs(p.x) <= 0.106 && abs(p.z) <= 0.076)
        }
    }

    @Test func ceilingFlattensPinnedPiecesAndNeverReinflates() {
        var world = DebrisWorld()
        world.bodies = [DebrisBody(position: [0, 0.004, 0], velocity: .zero, orientation: simd_quatf(angle: 0, axis: [0, 1, 0]),
                                   angularVelocity: .zero, halfExtents: [0.005, 0.004, 0.005])]
        world.ceiling = 0.004
        for _ in 0..<60 { world.step(dt: 1.0 / 120.0) }
        let flat = world.bodies[0].flat
        #expect(flat < 0.6)
        world.ceiling = 1
        for _ in 0..<60 { world.step(dt: 1.0 / 120.0) }
        #expect(world.bodies[0].flat == flat)
    }

    @Test func heightCurvesAreMonotonicAndBrittleObjectsLurch() {
        var previous: Float = .infinity
        for k in 0...100 {
            let h = HeightCurve.linear(Float(k) / 100, rest: 0.08, minRatio: 0.2)
            #expect(h <= previous)
            previous = h
        }
        let before = HeightCurve.brittle(0.3, rest: 0.08, failC: 0.3, failed: false, rigidSquash: 0.03, afterRatio: 0.4, minRatio: 0.1)
        let after = HeightCurve.brittle(0.3, rest: 0.08, failC: 0.3, failed: true, rigidSquash: 0.03, afterRatio: 0.4, minRatio: 0.1)
        #expect(before > 0.075)
        #expect(after < before * 0.5)
        #expect(abs(HeightCurve.brittle(1, rest: 0.08, failC: 0.3, failed: true, rigidSquash: 0.03,
                                        afterRatio: 0.4, minRatio: 0.1) - 0.008) < 1e-5)
    }

    @Test func studioHDRIHasAKeyBrighterThanTheFloor() {
        let key = StudioEnvironment.radiance(StudioEnvironment.direction(azimuth: -40 * .pi / 180, elevation: 45 * .pi / 180),
                                             baseAt: 45)
        let floor = StudioEnvironment.radiance(StudioEnvironment.direction(azimuth: 0, elevation: -80 * .pi / 180), baseAt: -80)
        #expect(key.x > 4 && floor.x < 0.6)
    }
}
