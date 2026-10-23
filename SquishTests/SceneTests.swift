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
        // FOLD-REVIEW-7 #5: fewer, larger shards (45–72° arcs on the body), the base ring and the neck kept whole, and the
        // whole bottle (plus a message) fits the 64-piece debris cap.
        #expect(GlassDebris.sectorCounts == [1, 6, 8, 8, 5, 1])
        #expect(GlassDebris.sectorCounts.reduce(0, +) + 1 <= 64)
        #expect(GlassDebris.intactBands == [0, GlassDebris.sectorCounts.count - 1])
        for band in GlassDebris.intactBands { #expect(GlassDebris.sectorCounts[band] == 1) }
        #expect(GlassDebris.skidSpeed.lowerBound >= 0.04 && GlassDebris.skidSpeed.upperBound <= 0.10)
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
            // FOLD-REVIEW-5 N5: a two-tone edge, the dark hairline (and walls) in their own slot; FOLD-REVIEW-7 N8: a
            // specular streak across each face, in a fourth.
            #expect(pair.materialSlots == 4 && GlassDebris.fragmentSlot(pair, slot: 2).isValid)
            #expect(GlassDebris.fragmentSlot(pair, slot: 3).isValid)
        }
        // The big single pieces: one polygon filling most of the unit square, the same four slots.
        for v in 0..<GlassDebris.singleVariants {
            let single = GlassDebris.fragmentSingle(seed: GlassDebris.singleSeed(v))
            expectValid(single, "single piece \(v)")
            let box = single.bounds()
            #expect(box.min.x >= -0.5 && box.max.x <= 0.5 && box.min.z >= -0.5 && box.max.z <= 0.5)
            #expect(box.max.x - box.min.x >= 0.6 && box.max.z - box.min.z >= 0.6)
            #expect(single.materialSlots == 4 && GlassDebris.fragmentSlot(single, slot: 3).isValid)
        }
        // A streak is a thin chord inside its polygon, a hair above the top face.
        for seed in UInt64(1)...40 {
            var rng = SplitMix64(seed: seed)
            let polygon = GlassDebris.shardPolygon(sides: 4 + Int(seed % 3), radii: [0.2, 0.4], rng: &rng)
            let streak = GlassDebris.streak(polygon, rng: &rng)
            if streak.positions.isEmpty { continue }   // a chord too short to draw is skipped, not drawn outside
            expectValid(streak, "streak \(seed)")
            for p in streak.positions {
                #expect(p.y > GlassDebris.fragmentThickness / 2)
                for i in polygon.indices {
                    let a = polygon[i], b = polygon[(i + 1) % polygon.count]
                    #expect((b.x - a.x) * (p.z - a.y) - (b.y - a.y) * (p.x - a.x) > -1e-5, "streak leaves its shard")
                }
            }
        }
        // A rimmed slab with an outline keeps every triangle: face + bevel + hairline/walls.
        let square: [SIMD2<Float>] = [[-0.2, -0.4], [0.2, -0.4], [0.2, 0.4], [-0.2, 0.4]]
        let twoTone = MeshKit.polygonSlab(square, thickness: 0.001, rimInset: 0.035, outlineInset: 0.03)
        expectValid(twoTone, "two-tone slab")
        #expect(twoTone.splitByMaterial().reduce(0) { $0 + $1.mesh.triangleCount } == twoTone.triangleCount)
        // The shards are darker than the steel (round 4's tint was lighter than #5CC8B8, and read as paper), and the
        // label scraps are ×1.4 of round 4's 0.7.
        func luma(_ hex: UInt32) -> Float {
            0.2126 * Float((hex >> 16) & 0xFF) + 0.7152 * Float((hex >> 8) & 0xFF) + 0.0722 * Float(hex & 0xFF)
        }
        #expect(luma(GlassDebris.shardTint) < luma(0x5CC8B8) - 15)
        #expect(luma(GlassDebris.shardTintDeep) < luma(GlassDebris.shardTint) - 10)
        #expect(luma(GlassDebris.seaGlassTint) < luma(0x5CC8B8))
        #expect(luma(GlassDebris.outlineTint) < 100)
        #expect(GlassDebris.shardOpacity >= 0.65 && abs(GlassDebris.scrapScale - 0.98) < 1e-6)
        for v in 0..<GlassDebris.scrapVariants {
            expectValid(GlassDebris.scrap(seed: GlassDebris.scrapSeed(v)), "scrap \(v)")
        }
        // FOLD-REVIEW-7 N8: a pair's piece is ~2.5–16 mm on the plate (×0.76 hero scale) and a single piece up to ~21 mm,
        // whatever the patch, so no piece is dust and none is a playing card.
        for width in stride(from: Float(0.004), through: 0.2, by: 0.004) {
            for height in [Float(0.006), 0.025, 0.03] {
                let size = GlassDebris.fragmentSize(width: width, height: height)
                for grow in [GlassDebris.pairScale.lowerBound, GlassDebris.pairScale.upperBound] {
                    let piece = GlassDebris.pieceSize(size * grow) * Float(0.76)
                    #expect(piece.x >= 0.0025 && piece.x <= 0.016 && piece.y >= 0.0025 && piece.y <= 0.016)
                }
                for grow in [GlassDebris.singleScale.lowerBound, GlassDebris.singleScale.upperBound] {
                    let piece = GlassDebris.singlePieceSize(size * grow) * Float(0.76)
                    #expect(piece.x >= 0.006 && piece.x <= 0.023 && piece.y >= 0.005 && piece.y <= 0.023)
                }
            }
        }
        // On the bottle's own patches (a 60° arc of the Ø 60 mm body, ~29 mm tall, and a 45° arc of the label, ~25 mm
        // tall) the biggest single piece is ≥ 3× the area of the smallest piece of a pair, and ≥ 19 mm across.
        let body = GlassDebris.fragmentSize(width: 0.030 * 2 * .pi / 6, height: 0.029)
        let label = GlassDebris.fragmentSize(width: 0.030 * 2 * .pi / 8, height: 0.025)
        let smallest = GlassDebris.pieceSize(label * GlassDebris.pairScale.lowerBound) * Float(0.76)
        let biggest = GlassDebris.singlePieceSize(body * GlassDebris.singleScale.upperBound) * Float(0.76)
        #expect(biggest.x * biggest.y >= 3 * smallest.x * smallest.y)
        #expect(max(biggest.x, biggest.y) >= 0.019)
        // One piece in three stays whole and lands in the middle; one in five is propped up, never on its edge.
        #expect(GlassDebris.singleShare == 3 && GlassDebris.singleInner <= 0.5)
        #expect(abs(GlassDebris.proppedShare - 0.2) < 1e-6)
        #expect(GlassDebris.proppedTilt.lowerBound > GlassDebris.heapMaxTilt && GlassDebris.proppedTilt.upperBound <= 0.65)
        // The intact base ring and neck land inside the pile, on opposite sides of it.
        let neckSpot = GlassDebris.intactSpot(neck: true, footprint: 0.068 * 0.76, containment: [0.079, 0.056])
        let baseSpot = GlassDebris.intactSpot(neck: false, footprint: 0.068 * 0.76, containment: [0.079, 0.056])
        #expect(neckSpot.x > 0 && baseSpot.x < 0)
        #expect(abs(neckSpot.x) < 0.079 * GlassDebris.pileRoom && abs(baseSpot.y) < 0.056 * GlassDebris.pileRoom)
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
        #expect(GlassDebris.sparkleCount == 6)
        #expect((8...10).contains(GlassDebris.labelScraps.pink + GlassDebris.labelScraps.cream))
        #expect(GlassDebris.labelScraps.pink == 6 && GlassDebris.labelScraps.cream == 4)
    }

    @Test func glassPileHeapsUpInTheMiddle() {
        // FOLD-REVIEW-6 N10: a ring with a hole. Now 25–30 % of the pieces land inside 0.35 of the pile's radius (a
        // uniform disc puts 12 % there), the pile is tighter, and the middle stacks 2–3 pieces deep.
        let share = pow(Float(0.35), 1 / GlassDebris.pileExponent)
        #expect(share >= 0.25 && share <= 0.32)
        var rng = SplitMix64(seed: 11)
        var count = 0
        let n = 2000
        for _ in 0..<n {
            let u = Float.random(in: 0...1, using: &rng)
            if GlassDebris.pileRadius(u: u) < 0.35 { count += 1 }
        }
        #expect(count > n / 4 && count < n * 32 / 100)
        #expect(GlassDebris.pileRadius(u: 0) == 0 && abs(GlassDebris.pileRadius(u: 1) - 1) < 1e-6)
        #expect(GlassDebris.pileFill <= 0.85 && GlassDebris.pileAspect < 1)
        // Lift: highest in the middle, none at the edge, monotonic; rendered ≈ 2 × lift × hero scale: 2–4 mm at most.
        #expect(GlassDebris.heapLift(rho: 1, jitter: 1) == 0)
        var previous = Float.infinity
        for k in 0...20 {
            let lift = GlassDebris.heapLift(rho: Float(k) / 20, jitter: 1)
            #expect(lift <= previous)
            previous = lift
        }
        let peak = 2 * GlassDebris.heapLift(rho: 0, jitter: 1) * 0.76
        #expect(peak >= 0.002 && peak <= 0.004)
        // Tilt: steepest in the middle, never more than the max, never zero; the edge skids, the middle stays.
        #expect(abs(GlassDebris.heapTilt(rho: 0, jitter: 1) - GlassDebris.heapMaxTilt) < 1e-6)
        #expect(GlassDebris.heapMaxTilt <= 0.4)
        #expect(GlassDebris.heapTilt(rho: 1, jitter: 0) > 0)
        #expect(GlassDebris.heapTilt(rho: 1, jitter: 1) < GlassDebris.heapTilt(rho: 0, jitter: 1))
        #expect(abs(GlassDebris.skidShare(rho: 1) - 1) < 1e-6 && GlassDebris.skidShare(rho: 0) < 0.3)
    }

    @Test func glassCrackStarsFaceTheCameraAndReadBeforeTheFailure() {
        // FOLD-REVIEW-8 N3: the crack was seven 0.4 × 0.7 mm near-white boxes along the top, under the ram and edge-on to
        // the P-48's eye. Now two stars of thick, dark-cored lines on bare glass on the camera side.
        func luma(_ hex: UInt32) -> Float {
            0.2126 * Float((hex >> 16) & 0xFF) + 0.7152 * Float((hex >> 8) & 0xFF) + 0.0722 * Float(hex & 0xFF)
        }
        #expect(GlassCrack.lineWidth >= 0.0012 && GlassCrack.lineWidth <= 0.0018)
        #expect(GlassCrack.coreWidth <= 0.5 * GlassCrack.lineWidth && GlassCrack.coreWidth >= 0.0005)
        #expect(luma(GlassCrack.coreTint) < 80 && luma(GlassCrack.edgeTint) > 230)
        #expect(GlassCrack.coreLift > 0 && GlassCrack.lift > GlassCrack.lineThickness / 2)
        // One impact faces the Duo's top-down eye (~47° up), one the P-48's (~21° up) low on the front flank, under the
        // ram's face; both on the bare glass between the base's heel and the label.
        #expect(GlassCrack.impacts.count >= 2)
        let duoEye = simd_normalize(SIMD3<Float>(0, sin(47 * .pi / 180), cos(47 * .pi / 180)))
        let frontEye = simd_normalize(SIMD3<Float>(0, sin(21 * .pi / 180), cos(21 * .pi / 180)))
        let normals = GlassCrack.impacts.map { GlassCrack.surface(x: $0.x, angle: $0.angle, squash: 1).normal }
        #expect(normals.contains { simd_dot($0, duoEye) >= 0.95 && $0.y >= 0.6 })
        #expect(normals.contains { simd_dot($0, frontEye) >= 0.95 && $0.z >= 0.9 })
        for impact in GlassCrack.impacts {
            #expect(GlassCrack.axialRange.contains(impact.x))
        }
        let front = GlassCrack.impacts.max { $0.angle < $1.angle }!
        #expect(GlassCrack.surface(x: front.x, angle: front.angle, squash: 1).point.y
                <= GlassCrack.centreY + 0.5 * GlassCrack.bodyRadius)
        // The surface and its normal follow the ovalised cross-section (squash 0.96: 4 % lower, 4 % wider).
        let side = GlassCrack.surface(x: -0.05, angle: .pi / 2, squash: 0.96)
        #expect(abs(side.point.z - 0.030 / 0.96) < 1e-6 && abs(side.normal.z - 1) < 1e-5)
        let top = GlassCrack.surface(x: -0.05, angle: 0, squash: 0.96)
        #expect(abs(top.point.y - (0.030 + 0.030 * 0.96)) < 1e-6 && abs(top.normal.y - 1) < 1e-5)
        // Growth: the first share at the first crack, all of it at the failure; ≈ 0.65 at P4 (c 0.31 of 0.22 → 0.40).
        #expect(abs(GlassCrack.grown(compression: 0.22, crackC: 0.22, failC: 0.40) - GlassCrack.firstShare) < 1e-6)
        #expect(abs(GlassCrack.grown(compression: 0.40, crackC: 0.22, failC: 0.40) - 1) < 1e-6)
        let p4 = GlassCrack.grown(compression: 0.31, crackC: 0.22, failC: 0.40)
        #expect(p4 > 0.55 && p4 < 0.75)
        var lastGrown: Float = 0
        for k in 0...20 {
            let g = GlassCrack.grown(compression: 0.2 + Float(k) * 0.012, crackC: 0.22, failC: 0.40)
            #expect(g >= lastGrown)
            lastGrown = g
        }
        #expect(GlassCrack.widthShare(along: 0) == 1 && abs(GlassCrack.widthShare(along: 1) - GlassCrack.tipTaper) < 1e-6)
        // Every star, seeded: its rays stay on the bare glass and on the camera's side, and at 55 % grown (P4) the star
        // already reaches ≥ 5 mm from its impact (≥ 13 px on the 6.9" frame; typically 8–12 mm) of its 16–24 mm rays.
        for seed in [UInt64(1), 7, 3_000, 0xC2AC_5747] {
            var rng = SplitMix64(seed: seed)
            for impact in GlassCrack.impacts {
                let rays = GlassCrack.star(x: impact.x, angle: impact.angle, rng: &rng)
                #expect(rays.count == GlassCrack.raysPerStar)
                let origin = GlassCrack.surface(x: impact.x, angle: impact.angle, squash: 1).point
                var reach: Float = 0
                for ray in rays {
                    #expect(ray.count == GlassCrack.segmentsPerRay + 1 && ray[0] == SIMD2(impact.x, impact.angle))
                    let lengths = (0..<(ray.count - 1)).map { GlassCrack.chord(ray[$0], ray[$0 + 1]) }
                    let total = lengths.reduce(0, +)
                    #expect(total <= GlassCrack.rayLength.upperBound * 1.01)
                    for p in ray {
                        #expect(GlassCrack.axialRange.contains(p.x))
                        #expect(GlassCrack.surface(x: p.x, angle: p.y, squash: 1).normal.z > -0.3)
                    }
                    // The point 55 % of the way along this ray.
                    var left = 0.55 * total
                    for i in lengths.indices {
                        let f = lengths[i] > 0 ? min(left / lengths[i], 1) : 0
                        let tip = ray[i] + (ray[i + 1] - ray[i]) * f
                        reach = max(reach, simd_distance(GlassCrack.surface(x: tip.x, angle: tip.y, squash: 1).point, origin))
                        left -= lengths[i]
                        if left <= 0 { break }
                    }
                }
                #expect(reach >= 0.005, "star at \(impact.angle) reaches \(reach) at 55 %")
            }
        }
        // A segment's line lies along its chord, out of the glass (never sunk into it at the chord's middle).
        let a = GlassCrack.surface(x: -0.05, angle: 1.0, squash: 1), b = GlassCrack.surface(x: -0.047, angle: 1.2, squash: 1)
        let pose = GlassCrack.segmentPose(from: a, to: b, lift: GlassCrack.lift)
        let dir = simd_normalize(b.point - a.point)
        #expect(simd_dot(pose.orientation.act(SIMD3(1, 0, 0)), dir) > 0.999)
        #expect(simd_dot(pose.orientation.act(SIMD3(0, 1, 0)), simd_normalize(a.normal + b.normal)) > 0.99)
        let middle = SIMD2<Float>(pose.position.y - GlassCrack.centreY, pose.position.z)
        #expect(simd_length(middle) >= GlassCrack.bodyRadius + GlassCrack.lift * 0.9)
        #expect(abs(pose.length - simd_distance(a.point, b.point)) < 0.001)
    }

    @Test func cakeCreamShadesInsteadOfClipping() {
        // FOLD-REVIEW-8 N4: #FFF3F7 with a clearcoat clipped to flat white under the key. The cream is darker and matte,
        // mottled a little either side of its tint, on planar UVs that cover the whole slice.
        func luma(_ hex: UInt32) -> Float {
            0.2126 * Float((hex >> 16) & 0xFF) + 0.7152 * Float((hex >> 8) & 0xFF) + 0.0722 * Float(hex & 0xFF)
        }
        #expect(luma(CakeSquash.creamTint) < luma(0xFFF3F7) - 10)
        #expect(luma(CakeSquash.creamTint) > 200)
        #expect(luma(CakeSquash.creamDark) < luma(CakeSquash.creamTint) && luma(CakeSquash.creamLight) > luma(CakeSquash.creamTint))
        #expect(luma(CakeSquash.creamTint) - luma(CakeSquash.creamDark) < 30)
        #expect(CakeSquash.creamRoughness >= 0.55)
        let mesh = CakeSquash.bodyMesh()
        #expect(mesh.uvs.count == mesh.positions.count && mesh.isValid)
        for uv in mesh.uvs {
            #expect(uv.x >= 0 && uv.x <= 1 && uv.y >= 0 && uv.y <= 1)
        }
    }

    @Test func eggShellLandsRoundTheYolkNotOnIt() {
        // FOLD-REVIEW-6 N9: the shards were pinned over the yolk. Now they land on a ring outside the widest yolk pool.
        for doubleYolk in [false, true] {
            let reach = EggShell.yolkReach(doubleYolk: doubleYolk)
            let yolkEdge = EggYolk.runRadius(1) + (doubleYolk ? EggYolk.doubleOffset : 0)
            #expect(reach > EggYolk.runRadius(1))
            #expect(reach + 0.006 > yolkEdge)
            for k in 0..<36 {
                for u in [Float(0), 0.5, 1] {
                    let p = EggShell.ringPoint(angle: Float(k) * .pi / 18, u: u, reach: reach)
                    // Outside the yolk's pool (an ellipse squashed in z by the ring's aspect at worst) …
                    let r = simd_length(SIMD2(p.x, p.y / EggShell.ringAspect))
                    #expect(r >= reach - 1e-5 && r <= reach + EggShell.ringWidth + 1e-5)
                    // … and the centre on the P-48's anvil.
                    #expect(abs(p.x) <= 0.079 && abs(p.y) <= 0.056)
                }
            }
        }
        // 24 smaller shards, a third inside up, all inside the 64-piece debris cap.
        #expect(EggShell.sectors.reduce(0, +) == 24 && EggShell.sectors.reduce(0, +) <= 64)
        #expect((0..<24).filter { EggShell.showsInside($0) }.count == 8)
        #expect(EggShell.shardScale < 0.7 && EggShell.slack <= 0.005)
        // The yolk always stands clear of the 2 mm white: the broken dome, its pool and the dome's floor.
        #expect(EggYolk.minHeight > EggYolk.runHeight && EggYolk.runHeight > EggYolk.albumenHeight)
        #expect(EggYolk.brokenDome >= EggYolk.minHeight)
        // It spreads as the press closes, the pool wider than the dome, and stays inside the white (Ø ≥ 0.10 m).
        #expect(EggYolk.runRadius(1) > EggYolk.runRadius(0) && EggYolk.brokenRadius(1) > EggYolk.brokenRadius(0))
        #expect(EggYolk.runRadius(1) > EggYolk.brokenRadius(1) * 1.16)
        #expect(EggYolk.runRadius(1) < 0.050)
        #expect(EggYolk.glow >= 0.25)
    }

    @Test func cakeSquashBulgesTheOutline() {
        // FOLD-REVIEW-6 N9: a uniformly scaled wedge kept its outline, so from above it looked intact.
        let mesh = CakeSquash.bodyMesh()
        expectValid(mesh, "cake body")
        #expect(mesh.materialSlots == 4)
        let cakeSlots = mesh.splitByMaterial().map { $0.slot }
        #expect(cakeSlots == [0, 1, 2, 3])
        let wedge = CakeSquash.wedge(inset: 0, sideSteps: CakeSquash.sideSteps)
        #expect(wedge.count == 1 + 9 + 2 * CakeSquash.sideSteps)
        #expect(CakeSquash.wedge().count == 10)
        // Every extra side point lies on its straight side (the outline stays convex at rest).
        for p in wedge.dropFirst().prefix(CakeSquash.sideSteps) {
            #expect(abs(atan2(p.y, p.x) + CakeSquash.halfAngle) < 1e-4)
        }
        let flat: (Float) -> Float = { _ in 0 }
        let lumpy = MeshKit.periodicNoise(seed: 9)
        let side = SIMD3<Float>(0.06, 0.026, -0.06 * tan(CakeSquash.halfAngle))   // the filling, on a long side
        // No squeeze at rest; the base stays on the plate (FOLD-REVIEW-8 N4: it spreads with the rest of the slice, in
        // the plane); a point on a side only ever moves outward, away from the centre line and from the centroid.
        #expect(CakeSquash.deform(side, progress: 0, noise: lumpy) == side)
        let base = SIMD3<Float>(0.06, 0, -0.06 * tan(CakeSquash.halfAngle))
        #expect(CakeSquash.deform(base, progress: 1, noise: lumpy).y == 0)
        let centroid = SIMD2<Float>(CakeSquash.centroidX, 0)
        var last: Float = 0
        var lastRadius: Float = 0
        var lastY = side.y
        for k in 0...10 {
            let q = CakeSquash.deform(side, progress: Float(k) / 10, noise: flat)
            // Outward, never back; the squeezed-out filling only ever sags (toward the plate, never through it).
            let radius = simd_distance(SIMD2(q.x, q.z), centroid)
            #expect(-q.z >= last - 1e-7 && radius >= lastRadius - 1e-7)
            #expect(q.y <= lastY + 1e-7 && q.y > 0)
            last = -q.z
            lastRadius = radius
            lastY = q.y
        }
        // The long side bows sideways by ≥ 1 cm at full squash, the filling further than the sponge above it, and the
        // cream top further than the sponge under it.
        let out = -CakeSquash.deform(side, progress: 1, noise: flat).z - (-side.z)
        #expect(out >= 0.010)
        let sponge = SIMD3<Float>(side.x, 0.045, side.z)
        #expect(-CakeSquash.deform(sponge, progress: 1, noise: flat).z < -CakeSquash.deform(side, progress: 1, noise: flat).z)
        #expect(CakeSquash.profile(0.9) > CakeSquash.profile(0.7))
        #expect(CakeSquash.profile(0) < 1e-6)
        // The point goes (FOLD-REVIEW-8 N4): the apex is drawn back toward the centroid by ≥ 8 mm (~10 mm); the
        // progress runs from s 0.9 (none) to s 0.3 (full), ≥ 0.8 at the c 0.7 hold.
        let apex = SIMD3<Float>(0.004, 0.03, 0)
        let apexMoved = CakeSquash.deform(apex, progress: 1, noise: flat) - apex
        #expect(apexMoved.x >= 0.008 && abs(apexMoved.z) < 1e-5)
        #expect(CakeSquash.progress(heightRatio: 1) == 0 && CakeSquash.progress(heightRatio: 0.3) > 0.999)
        #expect(CakeSquash.progress(heightRatio: 0.15) == 1)
        #expect(CakeSquash.progress(heightRatio: 0.385) > 0.8)
        // The tip blunts: near it the slice is drawn back (never into a longer point) and spreads sideways.
        let nearTip = SIMD3<Float>(0.015, 0.03, -0.015 * tan(CakeSquash.halfAngle))
        let moved = CakeSquash.deform(nearTip, progress: 1, noise: flat) - nearTip
        #expect(moved.x >= 0 && moved.z < -0.001)
        // The oval remap: the rest outline's distance from the centroid (arc 38 mm, apex 72 mm, across 26 mm), and a
        // map that only reaches the oval as the squash completes.
        #expect(abs(CakeSquash.restRadius(angle: 0) - (CakeSquash.radius - CakeSquash.centroidX)) < 1e-5)
        #expect(abs(CakeSquash.restRadius(angle: .pi) - CakeSquash.centroidX) < 1e-5)
        #expect(abs(CakeSquash.restRadius(angle: .pi / 2) - CakeSquash.centroidX * tan(CakeSquash.halfAngle)) < 1e-5)
        #expect(CakeSquash.blobOffset(SIMD2(0.004, 0), height: 0.5, progress: 0, noise: lumpy) == .zero)
        #expect(CakeSquash.roundness < 1 && CakeSquash.blobLong < CakeSquash.centroidX)
        #expect(CakeSquash.blobAcross > CakeSquash.centroidX * tan(CakeSquash.halfAngle) * 1.3)
    }

    @Test func cakeReadsCrushedFromAbove() {
        // FOLD-REVIEW-7 #5: from above the squashed slice must not be an intact wedge. Every vertex knows its layer.
        let mesh = CakeSquash.bodyMesh()
        let layers = CakeSquash.vertexLayers
        #expect(layers.count == mesh.vertexCount)
        #expect(Set(layers) == Set([0, 1, 2, 3, 4].map { UInt8($0) }))
        // The cream top's vertices are the cream slot's, the filling's the filling slot's.
        for part in mesh.splitByMaterial() where part.slot == Int(CakeSquash.fillingSlot) {
            #expect(part.sourceVertex.allSatisfy { layers[$0] == UInt8(CakeSquash.fillingLayer) })
        }
        let noise = MeshKit.periodicNoise(seed: 0xCA4E_B01 ^ 3, octaves: 3)
        let h = CakeSquash.surfaceHeight(compression: 1)
        let s = CakeSquash.heightRatio(ramFace: h, candleBent: true)
        let k = CakeSquash.uniformSpread(heightRatio: s)
        let t = CakeSquash.progress(heightRatio: s)
        #expect(t == 1 && k > 1.25)
        func footprint(_ points: [SIMD2<Float>]) -> Float {
            let hull = MeshKit.convexHull(points)
            var area: Float = 0
            for i in hull.indices {
                let a = hull[i], b = hull[(i + 1) % hull.count]
                area += a.x * b.y - b.x * a.y
            }
            return abs(area) / 2
        }
        var restTop: [SIMD2<Float>] = []
        var crushedTop: [SIMD2<Float>] = []
        var plateTop: [SIMD3<Float>] = []
        var reach: [Int: Float] = [:]
        let even: (Float) -> Float = { _ in 0 }
        for (i, p) in mesh.positions.enumerated() {
            let q = CakeSquash.deform(p, layer: Int(layers[i]), progress: t, noise: noise)
            let root = CakeSquash.toRoot(q, spread: k, heightRatio: s)
            restTop.append(SIMD2(p.x - CakeSquash.centroidX, p.z))
            crushedTop.append(SIMD2(root.x, root.z))
            plateTop.append(CakeSquash.rootToAnvil(root))
            // How far each layer's long lower side has pushed out (mid-slice, x 0.04…0.09), lumps aside.
            if p.x > 0.04 && p.x < 0.09 && p.z < -p.x * tan(CakeSquash.halfAngle) + 0.002 {
                let e = CakeSquash.deform(p, layer: Int(layers[i]), progress: t, noise: even)
                reach[Int(layers[i]), default: 0] = max(reach[Int(layers[i]), default: 0], -e.z + p.z)
            }
        }
        // A flattened, wider outline: the top-down footprint ≥ 1.9× the wedge's.
        #expect(footprint(crushedTop) >= 1.9 * footprint(restTop))
        // The filling squeezes out past the cream, the cream past the sponge under it (so pink frames the white).
        let filling = reach[CakeSquash.fillingLayer] ?? 0, cream = reach[CakeSquash.creamLayer] ?? 0
        let sponge = reach[CakeSquash.upperSpongeLayer] ?? 0
        #expect(filling > cream + 0.004 && cream > sponge)
        #expect(filling * k >= 0.02)
        // …and all of it stays on the strike plate (+16 pt), and on the plate floor.
        let plate = GlassDebris.containment(restHeight: CakeSquash.restHeight, anvilHalf: SIMD2<Float>(repeating: 1))
        for p in plateTop {
            #expect(abs(p.x) <= plate.x && abs(p.z) <= plate.y && p.y >= 0)
        }
        // FOLD-REVIEW-8 N4: from above the cream top is no longer a wedge. Its outline (the top ring and cap centre)
        // fills ≥ 60 % of the circle about the centroid that holds it (the wedge: 26 %), its reach toward the old apex
        // is ≤ 1.5× its half width (the wedge: 1.85×), and it is wider than the uniform spread alone would make it.
        func circleFill(_ points: [SIMD2<Float>]) -> Float {
            let far = points.map { simd_length($0) }.max() ?? 1
            return footprint(points) / (.pi * far * far)
        }
        var restCream: [SIMD2<Float>] = []
        var crushedCream: [SIMD2<Float>] = []
        for (i, p) in mesh.positions.enumerated() where Int(layers[i]) == CakeSquash.creamLayer && p.y > CakeSquash.cakeHeight - 1e-4 {
            restCream.append(SIMD2(p.x - CakeSquash.centroidX, p.z))
            let root = CakeSquash.toRoot(CakeSquash.deform(p, layer: CakeSquash.creamLayer, progress: t, noise: noise),
                                         spread: k, heightRatio: s)
            crushedCream.append(SIMD2(root.x, root.z))
        }
        #expect(restCream.count > 20)
        let restHalf = restCream.map { abs($0.y) }.max() ?? 0, crushedHalf = crushedCream.map { abs($0.y) }.max() ?? 0
        let restApex = -(restCream.map { $0.x }.min() ?? 0), crushedApex = -(crushedCream.map { $0.x }.min() ?? 0)
        #expect(circleFill(restCream) < 0.32 && restApex > 1.7 * restHalf)
        #expect(circleFill(crushedCream) >= 0.6, "cream top fill \(circleFill(crushedCream))")
        #expect(crushedApex <= 1.5 * crushedHalf, "apex \(crushedApex) vs half width \(crushedHalf)")
        #expect(crushedHalf >= 1.05 * k * restHalf)
        // With every lump at its peak (or trough) the whole slice still stays on the strike plate + 16 pt.
        for extreme: Float in [1, -1] {
            let worst: (Float) -> Float = { _ in extreme }
            for (i, p) in mesh.positions.enumerated() {
                let q = CakeSquash.rootToAnvil(CakeSquash.toRoot(CakeSquash.deform(p, layer: Int(layers[i]), progress: t, noise: worst),
                                                                 spread: k, heightRatio: s))
                #expect(abs(q.x) <= plate.x && abs(q.z) <= plate.y)
            }
        }
        // The ooze tongues leave the outline, pointing out of it.
        for k in 0...20 {
            let spot = CakeSquash.oozeSpot(fraction: Float(k) / 20)
            #expect(abs(simd_length(spot.normal) - 1) < 1e-4)
            let inward = spot.point - spot.normal * 0.002, outward = spot.point + spot.normal * 0.002
            #expect(simd_length(inward - SIMD2(0.07, 0)) < simd_length(outward - SIMD2(0.07, 0)) + 1e-6)
        }
    }

    @Test func cakeCandleKeepsItsTrueLengthWhateverTheSquash() {
        // FOLD-REVIEW-7 N3: the bent candle got the slice's 1/s counter-scale on its (now horizontal) length axis and
        // stretched into a needle up to ~6.7× past the plate. It is now a child of the unscaled root.
        let length = CakeSquash.candleLength, r = CakeSquash.candleRadius
        for bent in [false, true] {
            for step in 0...100 {
                let c = Float(step) / 100
                let pose = CakeSquash.candlePose(compression: c, bent: bent)
                let worldLength = simd_distance(pose.point(.zero), pose.point(SIMD3(0, length, 0)))
                #expect(abs(worldLength / length - 1) <= 0.15, "candle length ×\(worldLength / length) at c \(c)")
                // Its girth across the slice is its own too; only the ram may flatten it (never below 30 %).
                let across = simd_distance(pose.point(SIMD3(0, 0, -r)), pose.point(SIMD3(0, 0, r)))
                #expect(abs(across / (2 * r) - 1) <= 0.15)
                let girth = simd_distance(pose.point(SIMD3(-r, 0, 0)), pose.point(SIMD3(r, 0, 0)))
                #expect(girth / (2 * r) >= 0.3 - 1e-5 && girth / (2 * r) <= 1.15)
            }
        }
        // At c = 1 the bent candle lies on the slice: inside the strike plate's footprint, on the cream top, under the
        // ram face.
        let h = CakeSquash.surfaceHeight(compression: 1)
        let pose = CakeSquash.candlePose(compression: 1, bent: true)
        let plate = GlassDebris.containment(restHeight: CakeSquash.restHeight, anvilHalf: SIMD2<Float>(repeating: 1), padding: 0)
        let top = CakeSquash.heightRatio(ramFace: h, candleBent: true) * CakeSquash.cakeHeight
        for x in [-r, r] {
            for y in [Float(0), length + 0.0008] {
                for z in [-r, r] {
                    let p = CakeSquash.rootToAnvil(pose.point(SIMD3(x, y, z)))
                    #expect(abs(p.x) <= plate.x && abs(p.z) <= plate.y)
                    #expect(p.y >= top - 1e-5 && p.y <= h + 1e-5)
                }
            }
        }
        // It lies along the slice toward the apex and stays on it (the tip short of the wedge's apex).
        let tip = pose.point(SIMD3(0, length, 0))
        #expect(tip.x < pose.position.x - 0.9 * length)
        let k = CakeSquash.uniformSpread(heightRatio: top / CakeSquash.cakeHeight)
        #expect(tip.x > -CakeSquash.centroidX * k)
        // The old composition, for the record: the slice's (k, s, k) × the bend × a (1/k, 1/s, 1/k) counter-scale.
        let s = top / CakeSquash.cakeHeight
        let bend = simd_quatf(angle: 1.45, axis: [0, 0, 1])
        let old = SIMD3<Float>(k, s, k) * bend.act(SIMD3<Float>(1 / k, 1 / s, 1 / k) * SIMD3(0, length, 0))
        #expect(simd_length(old) > 3 * length)
    }

    @Test func jellyRelaxesIntoAPuddleOnThePlate() {
        // FOLD-REVIEW-7 N9: the reveal was a smooth dome. Relaxed, every mould vertex lies on a lobed puddle inside the
        // strike plate, with a flat middle and a raised rim, ≤ 35 % of the pressed height (0.0765 × 0.13).
        let plate = GlassDebris.containment(restHeight: 0.0765, anvilHalf: SIMD2<Float>(repeating: 1), padding: 0)
        let cap = GlassDebris.containment(restHeight: 0.0765, anvilHalf: SIMD2<Float>(repeating: 1),
                                          padding: JellySpread.platePadding)
        let half = plate * JellyPuddle.fill
        let pressed: Float = 0.0765 * 0.13
        let mould = ObjectMeshes.jellyMould(scale: 1)
        for seed in [UInt64(3), 77, 1234] {
            let rim = JellyPuddle.Rim(seed: seed)
            var maxY: Float = 0
            for p in mould.positions {
                let q = JellySpread.contain(JellyPuddle.shape(p, half: half, rim: rim), half: cap, lift: JellySpread.lift(heightRatio: 0.13))
                #expect(abs(q.x) <= plate.x && abs(q.z) <= plate.y, "puddle leaves the plate")
                #expect(q.y >= 0 && q.y <= 0.35 * pressed + 1e-6)
                maxY = max(maxY, q.y)
            }
            #expect(maxY >= JellyPuddle.rimHeight - 1e-4)
            // Lobed, not an ellipse: the outline's reach varies ≥ 1.2× round it.
            var reaches: [Float] = []
            for k in 0..<180 {
                let theta = Float(k) * 2 * .pi / 180
                reaches.append(JellySpread.norm(JellyPuddle.edge(theta: theta, half: half, rim: rim), half: half))
            }
            #expect(reaches.max()! / reaches.min()! >= 1.2)
            // The tear crosses the skin inside the rim, just above it.
            var rng = SplitMix64(seed: seed)
            let tear = JellyPuddle.tearPath(angle: 1, half: half, rim: rim, rng: &rng)
            #expect(tear.count >= 4)
            for p in tear {
                #expect(JellySpread.norm(SIMD2(p.x, p.z), half: half) <= 0.75 * JellyPuddle.Rim.maxScale)
                #expect(p.y > JellyPuddle.centreHeight && p.y < JellyPuddle.rimHeight + 0.001)
            }
            // The pooled core sits inside the flat middle and under its skin.
            let core = JellyPuddle.coreScale(half: half, rim: rim) * JellySpread.coreRestRadius
            #expect(core.x <= 0.7 * half.x * JellyPuddle.Rim.minScale && core.y <= 0.7 * half.y * JellyPuddle.Rim.minScale)
            #expect(JellySpread.coreTopRatio * 0.0765 * JellyPuddle.coreFlat < JellyPuddle.centreHeight)
        }
        // The profile: a flat middle, a raised rim, a low lip, continuous.
        #expect(abs(JellyPuddle.height(rho: 0) - JellyPuddle.centreHeight) < 1e-5)
        #expect(abs(JellyPuddle.height(rho: 0.4) - JellyPuddle.centreHeight) < 2e-4)
        #expect(JellyPuddle.height(rho: JellyPuddle.rimAt) >= JellyPuddle.centreHeight + 0.0015)
        #expect(abs(JellyPuddle.height(rho: 1) - JellyPuddle.lipHeight) < 1e-6)
        var previous = JellyPuddle.height(rho: 0)
        for k in 1...200 {
            let y = JellyPuddle.height(rho: Float(k) / 200)
            #expect(abs(y - previous) < 0.0004)
            previous = y
        }
        // The mould's apex is the middle, its widest ring the edge, its base stays on the plate.
        let rim = JellyPuddle.Rim(seed: 3)
        let apex = JellyPuddle.shape(SIMD3(0, 0.0765, 0), half: half, rim: rim)
        #expect(simd_length(SIMD2(apex.x, apex.z)) < 1e-6 && abs(apex.y - JellyPuddle.centreHeight) < 1e-6)
        // (At θ 0 the mould's flutes put its widest ring at 0.049 × 1.07.)
        let foot = JellyPuddle.shape(SIMD3(0.049 * 1.07, JellyPuddle.footY, 0), half: half, rim: rim)
        #expect(abs(JellySpread.norm(SIMD2(foot.x, foot.z), half: half) - rim.scale(0)) < 0.02)
        #expect(JellyPuddle.shape(SIMD3(0.02, 0, 0.01), half: half, rim: rim).y == 0)
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

    @Test func jellyStaysOnItsPlate() {
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
    }

    @Test func flattenedJellyStaysOnThePlateAsSeen() {
        // FOLD-REVIEW-5 N11: plate + 16 pt, and a point with height is held in by its anamorphic lean, so what the eye
        // sees stays on the plate too. A tall jelly at rest is not squeezed.
        #expect(JellySpread.platePadding == 16)
        let half = GlassDebris.containment(restHeight: 0.0765, anvilHalf: SIMD2<Float>(repeating: 1),
                                           padding: JellySpread.platePadding)
        #expect(JellySpread.lift(heightRatio: 1) == 0)
        let lift = JellySpread.lift(heightRatio: 0.2)
        #expect(lift >= JellySpread.projectionSlope - 1e-6)
        let atRest = SIMD3<Float>(0.03, 0.06, 0.02)
        #expect(JellySpread.contain(atRest, half: half, lift: JellySpread.lift(heightRatio: 1)) == atRest)
        for y in [Float(0), 0.004, 0.008, 0.012, 0.016] {
            for k in 1...60 {
                let a = Float(k) * 0.37
                let p = JellySpread.contain(SIMD3(cos(a) * 0.12, y, sin(a) * 0.12), half: half, lift: lift)
                let held = JellySpread.heldHalf(half, lift: lift, y: y)
                #expect(JellySpread.norm(SIMD2(p.x, p.z), half: held) < 1)
                #expect(p.y == y)
                // Leaned by its height in any direction, the point still lands inside plate + 16.
                #expect(abs(p.x) + lift * y <= half.x + 1e-5 && abs(p.z) + lift * y <= half.y + 1e-5)
            }
            // Monotonic along a ray at a fixed height.
            var last: Float = 0
            for k in 1...40 {
                let p = JellySpread.contain(SIMD3(0, y, Float(k) * 0.003), half: half, lift: lift)
                #expect(p.z > last)
                last = p.z
            }
        }
        // The round core fits inside the held shell at its top.
        let room = JellySpread.coreRoom(half: half, lift: lift, coreTop: 0.012)
        let held = JellySpread.heldHalf(half, lift: lift, y: 0.012)
        #expect(room.x * JellySpread.coreRestRadius <= held.x * JellySpread.knee + 1e-6)
        #expect(room.y * JellySpread.coreRestRadius <= held.y * JellySpread.knee + 1e-6)
    }

    @Test func bubbleWrapIsAHexSheetThatPopsFrontToBack() {
        // FOLD-REVIEW-5 N10: a regular hex grid of 24 domes on the film, inside its sealed margin.
        let n = BubbleWrapGrid.count
        #expect(n == BubbleWrapLayout.count)
        let centres = (0..<n).map { BubbleWrapGrid.centre($0) }
        var nearest = [Float](repeating: .infinity, count: n)
        for i in 0..<n {
            for j in 0..<n where j != i {
                nearest[i] = min(nearest[i], simd_distance(centres[i], centres[j]))
            }
        }
        for d in nearest { #expect(abs(d - BubbleWrapGrid.pitch) < 1e-5) }
        let half = BubbleWrapGrid.sheetSize / 2
        let foot = BubbleWrapGrid.radius * BubbleWrapGrid.creaseRadius
        for c in centres {
            #expect(abs(c.x) + foot <= half.x && abs(c.y) + foot <= half.y)
        }
        // Squashed neighbours never more than just meet.
        #expect(2 * BubbleWrapGrid.radius * BubbleWrapGrid.spread(squash: 0) <= BubbleWrapGrid.pitch * 1.01)
        // The mega bubble covers exactly its four cells' room.
        for i in 0..<n where !BubbleWrapGrid.megaCells.contains(i) {
            #expect(simd_length(centres[i]) >= (BubbleWrapGrid.megaScale + 1) * BubbleWrapGrid.radius)
        }
        // Pop order: a permutation, deterministic from the seed, front rows (+z) first, seeds differ.
        for seed in UInt64(1)...30 {
            let order = BubbleWrapGrid.popOrder(seed: seed)
            #expect(Set(order).count == n && order.count == n)
            #expect(order == BubbleWrapGrid.popOrder(seed: seed))
            let first = order.prefix(6).map { centres[$0].y }.reduce(0, +) / 6
            let last = order.suffix(6).map { centres[$0].y }.reduce(0, +) / 6
            #expect(first > last + 0.02)
            let ranks = BubbleWrapGrid.ranks(order)
            for (rank, cell) in order.enumerated() { #expect(ranks[cell] == rank) }
        }
        #expect(BubbleWrapGrid.popOrder(seed: 1) != BubbleWrapGrid.popOrder(seed: 2))
        // The first to pop is the tallest; the tallest is the rest height.
        #expect(BubbleWrapGrid.heightScale(rank: 0) == 1)
        for rank in 1..<n { #expect(BubbleWrapGrid.heightScale(rank: rank) < BubbleWrapGrid.heightScale(rank: rank - 1)) }
        #expect(BubbleWrapGrid.squash(available: 1, height: 0.007) == 1)
        #expect(abs(BubbleWrapGrid.squash(available: 0.0035, height: 0.007) - 0.5) < 1e-5)
        // Meshes: the dome (shell + crease foot), the flat seal/cut bands and three crinkled craters (film + creases).
        let dome = BubbleWrapGrid.domeMesh()
        expectValid(dome, "dome")
        // FOLD-REVIEW-6: crown (0), crease foot (1) and the dark lower wall (2), each a non-empty slot.
        #expect(dome.materialSlots == 3)
        let slots = dome.splitByMaterial().map { $0.slot }
        #expect(slots == [0, 1, 2])
        #expect(BubbleWrapGrid.domeSlot(band: 0) == 1 && BubbleWrapGrid.domeSlot(band: 1) == 1)
        #expect(BubbleWrapGrid.domeSlot(band: 2) == 2 && BubbleWrapGrid.domeSlot(band: 1 + BubbleWrapGrid.rimBands) == 2)
        #expect(BubbleWrapGrid.domeSlot(band: 2 + BubbleWrapGrid.rimBands) == 0)
        #expect(abs((dome.bounds().max.y) - BubbleWrapGrid.unitHeight) < 1e-4)
        #expect(abs(dome.bounds().max.x - BubbleWrapGrid.creaseRadius) < 1e-4)
        let ring = BubbleWrapGrid.ring(size: BubbleWrapGrid.sheetSize, corner: BubbleWrapGrid.sheetCorner,
                                       inset: BubbleWrapGrid.sealWidth)
        expectValid(ring, "seal")
        #expect(ring.normals.allSatisfy { $0.y > 0.99 })
        for k in 0..<BubbleWrapGrid.craterVariants {
            let crater = BubbleWrapGrid.craterMesh(seed: 0xC41 &+ UInt64(k) &* 977)
            expectValid(crater, "crater \(k)")
            #expect(crater.materialSlots == 2)
            let box = crater.bounds()
            // Flat: under 0.12 of the radius tall, and it never sinks into the film.
            #expect(box.min.y >= -1e-6 && box.max.y <= BubbleCrater.rise + 1e-6)
            #expect(box.max.x <= 1.2 && box.min.x >= -1.2)
        }
        let glint = BubbleWrapGrid.glint
        #expect(glint.position.x < 0 && glint.position.z < 0 && glint.position.y > 0.5 * BubbleWrapGrid.unitHeight)
        #expect(glint.size >= 0.24)
        // The bounce glint sits low on the far side, smaller than the key glint, and on the dome (not inside it).
        let bounce = BubbleWrapGrid.bounceGlint
        #expect(bounce.position.x > 0 && bounce.position.z > 0 && bounce.position.y < glint.position.y)
        #expect(bounce.size < glint.size && simd_length(SIMD2(bounce.position.x, bounce.position.z)) <= 1.05)
        #expect(BubbleCrater.snapScale(age: 0) > 1 && BubbleCrater.snapScale(age: BubbleCrater.snapDuration) == 1)
        #expect(BubbleCrater.radius > BubbleWrapGrid.creaseRadius)
    }

    @Test func bubbleWrapReadsOnABrightPlate() {
        // FOLD-REVIEW-6: the sheet was invisible on the P-48 (film 0.2, pale domes 0.36, nothing opaque but craters).
        typealias L = BubbleWrapLook
        let steel = L.luma(0xC9CDD3)   // the P-48's plate steel (Palette.plateSteel)
        // The film is tinted and dense enough to read as a sheet, but stays clear (R5 N10: 0.55 read as a white card).
        #expect(L.filmOpacity >= 0.3 && L.filmOpacity <= 0.45)
        #expect(L.sealOpacity > L.filmOpacity)
        // The cut edge and the crease rings are dark against the steel; the dome wall is darker than its crown.
        #expect(L.luma(L.cutTint) < steel - 80)
        #expect(L.luma(L.creaseTint) < steel - 70)
        #expect(L.luma(L.rimTint) < L.luma(L.crownTint) - 30)
        #expect(L.rimOpacity > L.crownOpacity && L.crownOpacity >= 0.4)
        // Popped craters stay stress-whitened, brighter than the crown.
        #expect(L.luma(L.craterTint) > L.luma(L.crownTint) && L.craterOpacity >= 0.75)
        #expect(BubbleWrapGrid.cutWidth >= 0.001)
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
