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
        // The pivot is the outer/inner surfaces' centroid; side-wall vertices shift the plain average slightly.
        #expect(simd_length(patch.mesh.centroid) < 0.004)
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

    @Test func perPieceBoundsKeepFastPiecesInsideTheirBox() {
        // FOLD-REVIEW-3 N5: a glass shard has its own walls inside the anvil's, and starts inside them when adopted.
        var world = DebrisWorld()
        let box = GlassDebris.centreBounds(containment: [0.05, 0.04], pieceHalf: [0.01, 0.01])
        var rng = SplitMix64(seed: 5)
        for _ in 0..<10 {
            let body = DebrisBody(position: [0.09, 0.004, -0.07], velocity: Burst.unitDirection(rng: &rng, upBias: 0) * 0.8,
                                  orientation: simd_quatf(angle: 0, axis: [0, 1, 0]), angularVelocity: .zero,
                                  halfExtents: [0.006, 0.001, 0.005], boundsMin: box.min, boundsMax: box.max)
            let start = world.contained(body)
            #expect(start.position.x <= box.max.x && start.position.z >= box.min.y)
            world.bodies.append(start)
        }
        for _ in 0..<600 { world.step(dt: 1.0 / 120.0) }
        for b in world.bodies {
            #expect(b.position.x >= box.min.x - 1e-6 && b.position.x <= box.max.x + 1e-6)
            #expect(b.position.z >= box.min.y - 1e-6 && b.position.z <= box.max.y + 1e-6)
        }
    }

    @Test func frozenPiecesNeverMoveFlattenOrSpread() {
        var world = DebrisWorld()
        world.bodies = [
            DebrisBody(position: [0, 0.02, 0], velocity: [0.3, 0, 0], orientation: simd_quatf(angle: 0, axis: [0, 1, 0]),
                       angularVelocity: [0, 3, 0], halfExtents: [0.005, 0.004, 0.005]),
            DebrisBody(position: [0, 0.004, 0], velocity: .zero, orientation: simd_quatf(angle: 0, axis: [0, 1, 0]),
                       angularVelocity: .zero, halfExtents: [0.005, 0.004, 0.005], maxSpread: 1),
        ]
        world.freeze(0)
        let frozen = world.bodies[0]
        #expect(frozen.settled && frozen.frozen && abs(frozen.position.y - frozen.support) < 1e-6)
        world.ceiling = 0.003
        for _ in 0..<120 { world.step(dt: 1.0 / 120.0) }
        #expect(world.bodies[0].position == frozen.position && world.bodies[0].flat == 1)
        // A piece with maxSpread 1 gets thinner under the ceiling but never wider (glass doesn't spread).
        #expect(world.bodies[1].flat < 1)
        #expect(world.bodies[1].scaleFactor.x == 1 && world.bodies[1].scaleFactor.z == 1)
    }

    @Test func glassDebrisStaysOnTheStrikePlate() {
        // Glass (rest 0.0456 m) is drawn at fold scale 1: plate 300 × 230 pt + 16 pt each side, in metres.
        let anvil = SIMD2<Float>(0.079, 0.056)
        let box = GlassDebris.containment(restHeight: 0.060 * 0.76, anvilHalf: SIMD2<Float>(1, 1))
        let metresPerPoint: Float = 1 / 340 / 6.02
        #expect(abs(box.x - (150 + 16) * metresPerPoint) < 1e-5)
        #expect(abs(box.y - (115 + 16) * metresPerPoint) < 1e-5)
        let clamped = GlassDebris.containment(restHeight: 0.060 * 0.76, anvilHalf: anvil)
        #expect(clamped.x <= anvil.x && clamped.y <= anvil.y)
        // Small shards: ≤ 26° arcs on the body, and the whole bottle (plus a message) fits the 64-piece debris cap.
        #expect(GlassDebris.sectorCounts == [1, 10, 14, 14, 8, 4])
        #expect(GlassDebris.sectorCounts.reduce(0, +) + 1 <= 64)
        #expect(GlassDebris.skidSpeed.lowerBound >= 0.04 && GlassDebris.skidSpeed.upperBound <= 0.10)
        #expect(GlassDebris.dustRadius(0) == 0.022 && abs(GlassDebris.dustRadius(1) - 0.032) < 1e-6)
        // A piece bigger than the box is pinned to its centre rather than given an inverted box.
        let tight = GlassDebris.centreBounds(containment: [0.01, 0.01], pieceHalf: [0.02, 0.005])
        #expect(tight.min.x == 0 && tight.max.x == 0 && abs(tight.max.y - 0.005) < 1e-7)
    }

    @Test func duckFootprintReadsFromAboveAndCapsOnThePlate() {
        // FOLD-REVIEW-3 N4: never below volume-preserving, ≥ +30 % by the 75° squash (s ≈ 0.65), 1.7× cap on the Duo.
        var previous: Float = 0
        for k in 0...100 {
            let s = 1 - Float(k) / 100 * 0.82
            let spread = DuckSquash.spread(heightRatio: s, cap: DuckSquash.foldCap)
            #expect(spread >= previous)
            #expect(spread >= min(1 / s.squareRoot(), DuckSquash.foldCap) - 1e-5)
            #expect(spread <= DuckSquash.foldCap)
            previous = spread
        }
        #expect(DuckSquash.spread(heightRatio: 0.65, cap: DuckSquash.foldCap) > 1.3)
        #expect(DuckSquash.spread(heightRatio: 0.18, cap: DuckSquash.foldCap) == 1.7)
        #expect(DuckSquash.spread(heightRatio: 0.18, cap: DuckSquash.machineCap) == 1.2)
        #expect(DuckSquash.spread(heightRatio: 1.05, cap: DuckSquash.foldCap) == 1)
        #expect(DuckSquash.skirtRadius(spread: 1.7, t: 1) > DuckSquash.skirtRadius(spread: 1.7, t: 0))
    }

    @Test func polygonSlabsAndHullsAreValid() {
        // The hull drops interior and collinear points and winds counter-clockwise.
        let points: [SIMD2<Float>] = [[0, 0], [1, 0], [1, 1], [0, 1], [0.5, 0.5], [0.5, 0]]
        let hull = MeshKit.convexHull(points)
        #expect(hull.count == 4)
        var area: Float = 0
        for i in hull.indices {
            let a = hull[i], b = hull[(i + 1) % hull.count]
            area += a.x * b.y - b.x * a.y
        }
        #expect(area > 0)
        let pentagon: [SIMD2<Float>] = (0..<5).map { k in SIMD2(cos(Float(k) * 2 * .pi / 5), sin(Float(k) * 2 * .pi / 5)) * 0.004 }
        let edged = MeshKit.polygonSlab(pentagon, thickness: 0.001, rimInset: 0.0004)
        expectValid(edged, "rimmed slab")
        #expect(edged.materialSlots == 2)
        let plain = MeshKit.polygonSlab(pentagon, thickness: 0.001)
        expectValid(plain, "plain slab")
        #expect(plain.materialSlots == 1)
        let bounds = plain.bounds()
        #expect(abs(bounds.min.y + 0.0005) < 1e-6 && abs(bounds.max.y - 0.0005) < 1e-6)
    }

    @Test func glassPileIsIrregularConvexShardsThatFillTheDisc() {
        // FOLD-REVIEW-4 F5: random convex 4–6-gons, deterministic from the seed.
        for seed in UInt64(1)...40 {
            var a = SplitMix64(seed: seed), b = SplitMix64(seed: seed)
            let sides = 4 + Int(seed % 3)
            let p = GlassDebris.shardPolygon(sides: sides, radii: [0.2, 0.4], rng: &a)
            let again = GlassDebris.shardPolygon(sides: sides, radii: [0.2, 0.4], rng: &b)
            #expect(p == again)
            #expect((4...6).contains(p.count))
            for i in p.indices {
                let o = p[i], q = p[(i + 1) % p.count], r = p[(i + 2) % p.count]
                #expect((q.x - o.x) * (r.y - o.y) - (q.y - o.y) * (r.x - o.x) > 0, "shard polygon must be convex")
            }
        }
        for v in 0..<GlassDebris.fragmentVariants {
            let pair = GlassDebris.fragmentPair(seed: GlassDebris.fragmentSeed(v))
            expectValid(pair, "fragment pair \(v)")
            let box = pair.bounds()
            #expect(box.min.x >= -0.5 && box.max.x <= 0.5 && box.min.z >= -0.5 && box.max.z <= 0.5)
            #expect(GlassDebris.fragmentSlot(pair, slot: 0).isValid && GlassDebris.fragmentSlot(pair, slot: 1).isValid)
        }
        for v in 0..<GlassDebris.scrapVariants {
            expectValid(GlassDebris.scrap(seed: GlassDebris.scrapSeed(v)), "scrap \(v)")
        }
        // Each piece is 3–9 mm on the plate (×0.76 hero scale), whatever the patch.
        for width in stride(from: Float(0.004), through: 0.2, by: 0.004) {
            for height in [Float(0.006), 0.025, 0.03] {
                let piece = GlassDebris.pieceSize(GlassDebris.fragmentSize(width: width, height: height)) * Float(0.76)
                #expect(piece.x >= 0.003 && piece.x <= 0.009 && piece.y >= 0.003 && piece.y <= 0.009)
            }
        }
        // The drop points fill the middle (≈ 1/π of them land in the central half-size box; a ring would put none
        // there) and stay inside the containment box.
        let footprint: Float = 0.068 * 0.76
        let box = SIMD2<Float>(0.079, 0.056)
        let centre = GlassDebris.pilePoint(angle: 1, u: 0, footprint: footprint, containment: box)
        #expect(simd_length(centre) < 1e-7)
        var rng = SplitMix64(seed: 7)
        var inner = 0
        let n = 400
        let full = GlassDebris.pilePoint(angle: 0, u: 1, footprint: footprint, containment: box).x
        for _ in 0..<n {
            let p = GlassDebris.pilePoint(angle: Float.random(in: 0...(2 * .pi), using: &rng), u: Float.random(in: 0...1, using: &rng),
                                          footprint: footprint, containment: box)
            #expect(abs(p.x) <= box.x * GlassDebris.pileRoom + 1e-6 && abs(p.y) <= box.y * GlassDebris.pileRoom + 1e-6)
            if abs(p.x) < full * 0.5 && abs(p.y) < box.y * GlassDebris.pileRoom * 0.5 { inner += 1 }
        }
        #expect(inner > n / 6)
        #expect(GlassDebris.sparkleCount == 4)
        #expect((8...10).contains(GlassDebris.labelScraps.pink + GlassDebris.labelScraps.cream))
        #expect(GlassDebris.labelScraps.pink == 6 && GlassDebris.labelScraps.cream == 4)
    }

    @Test func duckHeadFlattensIntoAnEllipseWithTheBody() {
        // FOLD-REVIEW-4 F6: no change at rest; the head (not the tail, wings or base) flattens and stretches.
        let top = SIMD3<Float>(0.020, 0.085, 0)
        #expect(DuckSquash.headDeform(top, c: 0) == top)
        let pressed = DuckSquash.headDeform(top, c: 1)
        #expect(pressed.y - DuckSquash.neckY <= 0.3 * (top.y - DuckSquash.neckY))
        for p in [SIMD3<Float>(-0.045, 0.05, 0), SIMD3<Float>(0.03, 0, 0), SIMD3<Float>(0, 0.005, 0.025)] {
            #expect(DuckSquash.headDeform(p, c: 1) == p)
        }
        // Top-down the head's equator is an ellipse along the body (≥ 1.15 : 1), never a round ball.
        var xs: [Float] = [], zs: [Float] = []
        for k in 0..<72 {
            let a = Float(k) / 72 * 2 * .pi
            let q = DuckSquash.headDeform(DuckSquash.headCentre + SIMD3(cos(a), 0, sin(a)) * 0.023, c: 1)
            xs.append(q.x)
            zs.append(q.z)
        }
        #expect((xs.max()! - xs.min()!) / (zs.max()! - zs.min()!) >= 1.15)
        // The beak barely moves forward (the duck stays on its plate) and flattens to half height.
        #expect(DuckSquash.headDeform(DuckSquash.beakCentre, c: 1).x - DuckSquash.beakCentre.x <= 0.006)
        #expect(DuckSquash.beakFlatten(1) == 0.5 && DuckSquash.beakFlatten(0) == 1)
        // The deform never folds the mesh: along lines through the head and neck, order is preserved on every axis.
        for y in [Float(0.03), 0.045, 0.05, 0.06, 0.075] {
            var previous = -Float.infinity
            for i in -80...80 {
                let x = DuckSquash.headDeform(SIMD3(Float(i) * 0.001, y, 0.01), c: 1).x
                #expect(x > previous)
                previous = x
            }
        }
        for x in [Float(-0.02), 0, 0.02, 0.04] {
            var previous = -Float.infinity
            for i in 0...100 {
                let y = DuckSquash.headDeform(SIMD3(x, Float(i) * 0.001, 0.005), c: 1).y
                #expect(y > previous)
                previous = y
            }
        }
        // Latching and the dull steps.
        #expect(DuckSquash.headProgress(heightRatio: 1.05, minRatio: 0.18) == 0)
        #expect(DuckSquash.headProgress(heightRatio: 0.18, minRatio: 0.18) == 1)
        #expect(DuckSquash.dullLevel(0) == 0 && DuckSquash.dullLevel(1) == DuckSquash.dullSteps)
        #expect(DuckSquash.wetRingRadius(spread: 1.7, t: 1) > DuckSquash.wetRingRadius(spread: 1.7, t: 0))
    }

    @Test func canChevronsSitOnTheShoulderNotTheLid() {
        // FOLD-REVIEW-4 F7: off the lid (r 0.041) and the tab, on the sloped shoulder, two per buckle.
        let lidRadius: Float = 0.0335 * ObjectMeshes.canR
        let lidY: Float = 0.1455 * ObjectMeshes.canY
        #expect(CanCrush.chevronRadius > lidRadius + 0.004)
        #expect(CanCrush.chevronRadius < 0.045 * ObjectMeshes.canR)
        let shoulder = CanCrush.shoulder(radius: CanCrush.chevronRadius)
        #expect(shoulder.y > ObjectMeshes.canBodyTop && shoulder.y < lidY)
        #expect(shoulder.slope > 0.6 && shoulder.slope < 1.2)
        #expect(CanCrush.chevronsPerBuckle * 5 == 10)
    }

    @Test func jellyStaysOnItsPlateAndBubbleCratersAreRimmed() {
        let half = SIMD2<Float>(0.092, 0.074)
        // Inside the knee nothing moves; far points are squeezed inside the edge, monotonically along a ray.
        let near = SIMD3<Float>(0.03, 0.01, 0.02)
        #expect(JellySpread.contain(near, half: half) == near)
        var previous: Float = 0
        for k in 1...40 {
            let p = JellySpread.contain(SIMD3(0, 0.005, Float(k) * 0.003), half: half)
            #expect(JellySpread.norm(SIMD2(p.x, p.z), half: half) < 1)
            #expect(p.z > previous && p.y == 0.005)
            previous = p.z
        }
        #expect(JellySpread.maxDiscRadius(half: half) * JellySpread.discRimReach <= half.x)
        #expect(JellySpread.maxDiscRadius(half: half) * JellySpread.discAspect * JellySpread.discRimReach <= half.y + 1e-6)
        #expect(abs(JellySpread.maxReach(direction: [0, 1], half: half) - half.y) < 1e-6)
        #expect(JellySpread.mattLevel(heightRatio: 1, splat: false) == 0)
        #expect(JellySpread.mattLevel(heightRatio: 0.13, splat: false) < JellySpread.mattSteps)
        #expect(JellySpread.mattLevel(heightRatio: 0.6, splat: true) == JellySpread.mattSteps)
        // Popped bubble: the rim sits inside the 1.25× crinkle, the pinhole glint is tiny.
        #expect(BubbleCrater.rimRadius < 1.25 && BubbleCrater.pinholeRadius <= 0.15)
    }

    @Test func canStrainStartsAtContactAndStaysBounded() {
        #expect(CanCrush.topStrain(compression: 0.04) == 0)
        #expect(CanCrush.topStrain(compression: 0.17) > 0.4)
        #expect(CanCrush.topStrain(compression: 0.31) == 1 && CanCrush.topStrain(compression: 0.9) == 1)
        #expect(CanCrush.lidDent(topStrain: 1, foldedShare: 1) <= 0.0056)
        #expect(CanCrush.lidDent(topStrain: 0, foldedShare: 0) == 0)
        // Five shoves stay a few millimetres: the top never leaves the can's own footprint (r 0.055).
        #expect(CanCrush.shovePerBand * 5 < 0.015)
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
