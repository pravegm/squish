import CoreGraphics
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
        #expect(GlassDebris.sectorCounts == [3, 6, 8, 8, 5, 1])   // EXPERIENCE-REVIEW-1 #5: the base breaks too (no coaster)
        #expect(GlassDebris.sectorCounts.reduce(0, +) + 1 <= 64)
        #expect(GlassDebris.intactBands == [GlassDebris.sectorCounts.count - 1])
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
        // The cream top's planar UVs cover the slice 0…1 (the sponge and frosting tile their crumb and piping instead).
        let layers = CakeSquash.vertexLayers
        #expect(layers.count == mesh.uvs.count)
        for (i, uv) in mesh.uvs.enumerated() where i < layers.count && CakeSquash.isCreamVertex(layers[i]) {
            #expect(uv.x >= 0 && uv.x <= 1 && uv.y >= 0 && uv.y <= 1)
        }
        // The sponge's sides get real texture coordinates (3D-art round): box-projected, not a planar smear down them.
        var sideSpan: Float = 0
        for (i, uv) in mesh.uvs.enumerated() where i < layers.count && Int(layers[i]) == CakeSquash.lowerSpongeLayer
            && abs(mesh.normals[i].y) < 0.3 {
            sideSpan = max(sideSpan, abs(uv.y))
        }
        #expect(sideSpan > 0.5, "the sponge's side v spans \(sideSpan) tiles")
    }

    @Test func crushedCakeShadesAndKeepsItsSpongeBand() {
        // FOLD-REVIEW-9 N3: at c = 1 the cream top clipped to flat white and covered the sponge. Its albedo now steps
        // down as the squash completes, and the sponge's top ring pokes out past the cream's base all round.
        func luma(_ hex: UInt32) -> Float {
            0.2126 * Float((hex >> 16) & 0xFF) + 0.7152 * Float((hex >> 8) & 0xFF) + 0.0722 * Float(hex & 0xFF)
        }
        #expect(CakeSquash.creamShade(progress: 0) == Float(1))
        #expect(CakeSquash.creamShade(progress: 0.4) == Float(1))
        #expect(abs(CakeSquash.creamShade(progress: 1) - CakeSquash.crushedShade) < Float(1e-5))
        // EXPERIENCE-REVIEW-1 #5: shaded a little, never greyed into a dish (was 0.82 → ~190).
        #expect(luma(CakeSquash.creamTint) * CakeSquash.creamShade(progress: 1) < 225)
        #expect(luma(CakeSquash.creamTint) * CakeSquash.creamShade(progress: 1) > 205)
        var lastShade: Float = 1
        for k in 0...20 {
            let shade = CakeSquash.creamShade(progress: Float(k) / 20)
            #expect(shade <= lastShade + 1e-6)
            lastShade = shade
        }
        #expect(luma(CakeSquash.creamFold) < luma(CakeSquash.creamDark))
        // The rim only comes in late (the 76° hold keeps its look) and the pushes stay ordered cream < sponge < filling.
        #expect(CakeSquash.rimWeight(progress: 0.5) == Float(0) && CakeSquash.rimWeight(progress: 1) == Float(1))
        #expect(CakeSquash.creamPush < CakeSquash.spongeRimPush && CakeSquash.spongeRimPush < CakeSquash.fillingPush)
        let topOfSponge: Float = 0.053   // the upper sponge's top = the cream's base
        let centroid = SIMD2<Float>(CakeSquash.centroidX, 0)
        for extreme: Float in [0, 1, -1] {
            let noise: (Float) -> Float = { _ in extreme }
            for q in CakeSquash.wedge(inset: 0, sideSteps: CakeSquash.sideSteps) {
                let p = SIMD3<Float>(q.x, topOfSponge, q.y)
                let sponge = CakeSquash.deform(p, layer: CakeSquash.upperSpongeLayer, progress: 1, noise: noise)
                let cream = CakeSquash.deform(p, layer: CakeSquash.creamLayer, progress: 1, noise: noise)
                let gap = simd_distance(SIMD2(sponge.x, sponge.z), centroid) - simd_distance(SIMD2(cream.x, cream.z), centroid)
                #expect(gap > 0.0004, "sponge ring \(gap) m at \(q), noise \(extreme)")
            }
            // On the back arc the frosting still covers the bulging sponge.
            for j in 1..<16 {
                let a = -CakeSquash.halfAngle + 0.01 + (2 * CakeSquash.halfAngle - 0.02) * Float(j) / 16
                for (y, layer) in [(Float(0.012), CakeSquash.lowerSpongeLayer), (Float(0.04), CakeSquash.upperSpongeLayer)] {
                    let dir = SIMD2<Float>(cos(a), sin(a))
                    let s = CakeSquash.deform(SIMD3(dir.x * CakeSquash.radius, y, dir.y * CakeSquash.radius), layer: layer,
                                              progress: 1, noise: noise)
                    let r = CakeSquash.radius + 0.004
                    let f = CakeSquash.deform(SIMD3(dir.x * r, y, dir.y * r), layer: CakeSquash.frostingLayer, progress: 1,
                                              noise: noise)
                    #expect(simd_length(SIMD2(f.x, f.z)) > simd_length(SIMD2(s.x, s.z)), "frosting at \(a), y \(y)")
                }
            }
        }
    }

    @Test func specimenPhotoIsAimedAtTheSpecimen() throws {
        // FOLD-REVIEW-9 N4: the P-48 card photo was a fixed crop of the live frame (58 % wide at 70 % down), so the duck
        // sat low with empty backdrop above it and lost its beak at the right on 6.1". The crop now follows the subject.
        let image = CGSize(width: 1206, height: 2622)
        let duck = CGRect(x: 380, y: 1850, width: 560, height: 300)   // low and right of centre, as on 6.1"
        let crop = try #require(SpecimenFraming.crop(subject: duck, mess: nil, image: image))
        #expect(abs(crop.width - crop.height) <= CGFloat(1))
        #expect(crop.contains(duck), "the whole specimen, beak included")
        #expect(crop.width >= duck.width * 1.3 && crop.width <= duck.width * 1.4)
        // Centred across; lifted a little above centre (the stamp sits low on the trailing corner).
        #expect(abs(crop.midX - duck.midX) <= CGFloat(1))
        #expect(duck.midY < crop.midY && duck.midY > crop.midY - crop.height * 0.1)
        // Near the frame's edge it stays inside the image.
        let edge = CGRect(x: 1000, y: 2500, width: 200, height: 100)
        let inside = try #require(SpecimenFraming.crop(subject: edge, mess: nil, image: image))
        #expect(CGRect(origin: .zero, size: image).contains(inside))
        // Mess near the specimen widens the frame, but only so far: a stray crumb across the screen can't shrink it.
        let near = CGRect(x: 300, y: 1900, width: 760, height: 260)
        let withMess = try #require(SpecimenFraming.crop(subject: duck, mess: near, image: image))
        #expect(withMess.width > crop.width && withMess.contains(near))
        let everywhere = try #require(SpecimenFraming.crop(subject: duck, mess: CGRect(origin: .zero, size: image), image: image))
        #expect(everywhere.width <= duck.width * (1 + 2 * SpecimenFraming.messReach) * SpecimenFraming.margin + 1)
        #expect(SpecimenFraming.crop(subject: .zero, mess: nil, image: image) == nil)
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
        // The filling squeezes out furthest, and (FOLD-REVIEW-9 N3) the sponge now bulges past the cream top's edge, so
        // from above it reads cream, a tan sponge ring, then the pink filling (it used to be cream over everything).
        let filling = reach[CakeSquash.fillingLayer] ?? 0, cream = reach[CakeSquash.creamLayer] ?? 0
        let sponge = reach[CakeSquash.upperSpongeLayer] ?? 0
        #expect(filling > cream + 0.004)
        #expect(filling > sponge + 0.002, "filling \(filling) vs sponge \(sponge)")
        #expect(sponge > cream + 0.002, "sponge \(sponge) vs cream \(cream)")
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

    // MARK: Object storyboards (design/OBJECT-STORYBOARDS.md)

    /// EXPERIENCE-PLAN: "a deformation event at least every 8°" between contact and flat, on the provisional Duo fold
    /// mapping and on the P-48 / old fold mapping, for many seeds (the grid and the fractures are both jittered).
    @Test func storyboardsNeverLeaveEightDegreesWithoutAnEvent() {
        let mappings: [ObjectStoryboard.Mapping] = [.fold, .touch, ObjectStoryboard.Mapping(contact: 120, exponent: 1.4)]
        for kind in ObjectKind.allCases {
            for k in 0..<40 {
                let seed = UInt64(k) &* 0x9E37_79B9_7F4A_7C15 &+ 17
                for mapping in mappings {
                    let gap = ObjectStoryboard.maxGapDegrees(kind, seed: seed, mapping: mapping)
                    #expect(gap <= ObjectStoryboard.gapLimitDegrees, "\(kind) seed \(seed) contact \(mapping.contact): \(gap)°")
                }
            }
        }
    }

    @Test func storyboardsAreCompleteAscendingAndFireOnce() {
        for kind in ObjectKind.allCases {
            #expect(ObjectStoryboard.gridKinds(kind).count == ObjectStoryboard.grid.count, "\(kind)")
            let beats = ObjectStoryboard.beats(kind, seed: 42)
            #expect(beats.count >= ObjectStoryboard.grid.count)
            #expect(zip(beats, beats.dropFirst()).allSatisfy { $0.c <= $1.c })
            #expect(beats.allSatisfy { $0.c > 0 && $0.c < 1 })
            // Several different kinds of visible event per object, not one effect repeated.
            #expect(Set(beats.map(\.kind)).count >= 4, "\(kind) storyboard is too repetitive")
            if kind.profile.failureIndex != nil {
                #expect(beats.filter { $0.kind == .tell }.count == 2, "\(kind) needs its two tells")
            }
            var cursor = StoryCursor(beats)
            #expect(cursor.advance(to: 0).isEmpty)
            var fired = 0
            for step in 1...200 { fired += cursor.advance(to: Float(step) / 200).count }
            #expect(fired == beats.count)
            #expect(cursor.advance(to: 1).isEmpty)
        }
        // Seeded variety: two seeds never place every beat identically.
        let a = ObjectStoryboard.beats(.egg, seed: 1).map(\.c)
        let b = ObjectStoryboard.beats(.egg, seed: 2).map(\.c)
        #expect(a != b)
    }

    @Test func duckFaceSquashesStepByStepAndSurvives() {
        var previousHeight: Float = 2
        for level in 1..<DuckFace.levels {
            let s = DuckFace.scale(level: level)
            if level >= 2 { #expect(s.y < previousHeight) }
            previousHeight = s.y
            // Cartoon squash: the eyes never vanish.
            #expect(s.y >= 0.3 && s.x > 0.9 && s.z > 0.9)
        }
        #expect(DuckFace.creaseRests.count == 3)
    }

    @Test func gummyChewsInsteadOfSplatting() {
        // The stretch is anisotropic and roughly keeps the volume.
        let rest = GummyChew.scale(heightRatio: 1, stretch: 0)
        #expect(abs(rest.x - 1) < 1e-5 && abs(rest.z - 1) < 1e-5)
        let chewed = GummyChew.scale(heightRatio: 0.6, stretch: 0.3)
        #expect(chewed.x > chewed.z * 1.3)
        #expect(abs(chewed.x * chewed.y * chewed.z - 1) < 0.35)
        #expect(GummyChew.stretch(compression: 0.3, steps: 2) > GummyChew.stretch(compression: 0.3, steps: 0))
        #expect(GummyChew.stretch(compression: 1, steps: 20) <= GummyChew.maxStretch)
        // Strands thin as they pull.
        let short = GummyChew.strandRadius(rest: 0.002, length: 0.01)
        let long = GummyChew.strandRadius(rest: 0.002, length: 0.04)
        #expect(long < short && long >= 0.00035)
        #expect(GummyChew.strandLength(gap: 0.01, height: 0.05, tilt: 0.2) > GummyChew.strandLength(gap: 0.01, height: 0, tilt: 0.2))
        var rng = SplitMix64(seed: 9)
        #expect(GummyChew.strandSpots(rng: &rng).count == GummyChew.strandCount)
        #expect(GummyChew.seamPath.count >= 8)
        #expect(GummyChew.strandMesh().isValid)
    }

    @Test func crayonBoxFillsItsRestHeightAndEndsFlat() {
        // Seven nested crayons: the top row's top is the box's rest height (SpecimenPrint mirrors 2 × 0.016).
        #expect(abs(CrayonBox.stackTop(sb: 1, st: 1) - 0.032) < 1e-5)
        #expect(CrayonBox.colours.count == 7)
        let flat = CrayonBox.rows(compression: 1, f1: 0.3, f2: 0.52, failedTop: true, failedBottom: true)
        #expect(CrayonBox.stackTop(sb: flat.sb, st: flat.st) < 0.032 * 0.4)   // EXPERIENCE-REVIEW-1 #5: thicker, waxier slabs (≈ 35 %)
        // Founder P0: a crushed crayon must not look intact from above. It is a wide, thin slab.
        let slab = CrayonBox.slabScale(flatten: flat.st)
        #expect(slab.y <= 0.31 && slab.z >= 1.8)
        let intact = CrayonBox.rows(compression: 0.29, f1: 0.3, f2: 0.52, failedTop: false, failedBottom: false)
        #expect(intact.sb == 1 && intact.st == 1)
        for cut in CrayonBox.cuts {
            #expect(CrayonBox.pieceMesh(0...(cut * CrayonBox.length)).isValid)
            #expect(CrayonBox.pieceMesh((cut * CrayonBox.length)...CrayonBox.length).isValid)
        }
        #expect(CrayonBox.smearSize(1, crumbled: true).x > CrayonBox.smearSize(1, crumbled: false).x)
    }

    @Test func glassStressGlowBuildsInSteps() {
        #expect(GlassStress.glow(level: 0) == 0)
        for level in 1...GlassStress.steps { #expect(GlassStress.glow(level: level) > GlassStress.glow(level: level - 1)) }
        #expect(GlassStress.glow(level: 99) == GlassStress.glow(level: GlassStress.steps))
    }

    /// Founder P0 (the crayon still looked intact after the press): every object, driven through a full press the way
    /// PressScene drives it (beats, fractures, the debris under the plate), ends clearly crushed: much lower than at
    /// rest and, except the bubble-wrap sheet, with a wider footprint.
    @MainActor
    @Test func everyObjectEndsVisiblyCrushed() {
        for kind in ObjectKind.allCases where kind != .unsquishable {
            let variant = PressVariant(kind: kind, seed: SpecimenPrint.plainSeed(for: kind))
            let fx = SceneFX()
            let view = PressObjectFactory.make(kind, variant: variant, fx: fx)
            ObjectCrush.rest(view)
            let rest = Self.footprint(of: view, fx: fx)
            // The same full press (and seal and reveal) the thumbnails render.
            ObjectCrush.press(view, fx: fx, kind: kind, variant: variant)
            let crushed = Self.footprint(of: view, fx: fx)
            if kind == .gummyBear {
                // EXPERIENCE-REVIEW-1 #5: the pads stay on the plate (the halves used to be flung off it).
                let plate = GlassDebris.containment(restHeight: view.restHeight, anvilHalf: SIMD2(repeating: 1), padding: 0)
                #expect(crushed.reach <= plate.x * 1.05, "gummy reaches \(crushed.reach) m")
            }
            #expect(crushed.height < rest.height * 0.45, "\(kind): crushed \(crushed.height) m vs rest \(rest.height) m")
            switch kind {
            case .bubbleWrap:
                // The sheet keeps its outline; the domes are what flatten (the height check above).
                break
            case .glassBottle:
                // A shatter heaps up in the middle of the plate (a tighter box than the lying bottle): the crushed
                // state is the pile itself.
                #expect(fx.debris.count >= 20, "glassBottle: only \(fx.debris.count) pieces on the plate")
            default:
                #expect(crushed.area > rest.area * 1.1, "\(kind): crushed footprint \(crushed.area) vs rest \(rest.area)")
            }
        }
    }

    // MARK: 3D-art round (texture coordinates, surface maps, crushed detail)

    @Test func artRoundMeshesCarryTextureCoordinates() {
        let duck = ObjectMeshes.duckBody()
        expectValid(duck, "duck body")
        #expect(duck.uvs.count == duck.positions.count)
        let beak = ObjectMeshes.duckBeak()
        expectValid(beak, "duck beak")
        #expect(beak.uvs.count == beak.positions.count)
        let gummy = ObjectMeshes.gummy(side: 1, coreScale: 1)
        expectValid(gummy, "gummy half")
        #expect(gummy.uvs.count == gummy.positions.count)
        let jelly = ObjectMeshes.jellyMould(scale: 1)
        expectValid(jelly, "jelly mould")
        #expect(jelly.uvs.count == jelly.positions.count)
        let can = ObjectMeshes.canBody()
        expectValid(can, "can body")
        #expect(can.materialSlots == 2 && can.uvs.count == can.positions.count)
        // The can's ends map top-down (the lid's planar UVs stay on the image).
        for part in can.splitByMaterial() where part.slot == 1 {
            #expect(part.mesh.uvs.allSatisfy { $0.x >= -1e-4 && $0.x <= 1.0001 && $0.y >= -1e-4 && $0.y <= 1.0001 })
        }
        let ball = MeshKit.sphereUV(radius: 0.05, segments: 24, rings: 12)
        expectValid(ball, "UV sphere")
        for (p, n) in zip(ball.positions, ball.normals) { #expect(simd_dot(simd_normalize(p), n) > 0.999) }
        #expect(ball.uvs.allSatisfy { $0.x >= 0 && $0.x <= 1 && $0.y >= 0 && $0.y <= 1 })
        let disc = MeshKit.spreadDiscUV(seed: 3, height: 1, tear: 0.1)
        expectValid(disc, "torn disc")
        #expect(disc.uvs.count == disc.positions.count)
        // The duck's eyes are painted on its face (round the front, above the equator).
        let paint = ObjectMeshes.duckPaint()
        #expect(paint.eyes.count == 2)
        for eye in paint.eyes { #expect(abs(eye.x - 0.5) < 0.12 && eye.y > 0.55 && eye.y < 0.95) }
        #expect(paint.eyeHalf.x > 0.005 && paint.eyeHalf.y > 0.01)
        let wall = CrayonBox.wallMesh(length: 0.1, height: 0.018, thickness: 0.0012)
        expectValid(wall, "crayon box wall")
        #expect(wall.materialSlots == 2 && wall.uvs.count == wall.positions.count)
        expectValid(CakeSquash.rosetteMesh(), "rosette")
        expectValid(CakeSquash.crumbMesh(), "crumb")
        expectValid(JellyInclusions.raspberryMesh(), "raspberry")
    }

    /// Every map builder runs (small sizes) and gives an image of the asked size: a crash in one would take the app down
    /// from its background task.
    @Test func everySurfaceMapBuilds() {
        typealias S = SurfaceImages
        let paint = DuckPaint(eyes: [SIMD2(0.45, 0.73), SIMD2(0.55, 0.73)], eyeHalf: SIMD2(0.02, 0.03))
        let images: [(String, CGImage?, Int)] = [
            ("duck colour", S.duckVinyl(paint, creased: true, width: 64, height: 32), 64),
            ("duck normal", S.normalImage(S.duckVinylHeight(paint, creased: true, width: 64, height: 32), strength: 1), 64),
            ("duck coat", S.duckCoat(width: 32, height: 16), 32),
            ("duck beak", S.duckBeak(width: 32, height: 16), 32),
            ("gummy skin", S.gummySkin(width: 64, height: 32), 64),
            ("gummy sugar", S.normalImage(S.gummySugar(width: 64, height: 32), strength: 1), 64),
            ("gummy rough", S.gummyRough(width: 64, height: 32), 64),
            ("gummy core", S.gummyCore(width: 32, height: 16), 32),
            ("gummy pad", S.gummyPad(size: 64), 64),
            ("gummy pad height", S.normalImage(S.gummyPadHeight(size: 64), strength: 1), 64),
            ("jelly skin", S.normalImage(S.jellySkin(width: 64, height: 32), strength: 1), 64),
            ("jelly caustics", S.jellyCaustics(width: 64, height: 32), 64),
            ("sponge", S.spongeCrumb(size: 64), 64),
            ("sponge height", S.normalImage(S.spongeHeight(size: 64), strength: 1), 64),
            ("sponge smeared", S.spongeSmeared(size: 64), 64),
            ("piping", S.normalImage(S.pipedFrosting(size: 64), strength: 1), 64),
            ("cream strokes", S.normalImage(S.creamStrokes(size: 64), strength: 1), 64),
            ("can label", S.canLabel(seed: 3, width: 256, height: 128), 256),
            ("can lid", S.canLidColour(size: 64), 64),
            ("can lid height", S.normalImage(S.canLidHeight(size: 64), strength: 1), 64),
            ("egg shell", S.eggShell(size: 64), 64),
            ("egg membrane", S.eggMembrane(size: 64), 64),
            ("film", S.normalImage(S.filmCreases(size: 64), strength: 1), 64),
            ("crater", S.normalImage(S.craterCrinkle(size: 64), strength: 1), 64),
            ("dome light", S.domeLight(height: 32), 4),
            ("kraft", S.kraft(size: 64), 64),
            ("box front", S.crayonBoxFront(width: 256, height: 64), 256),
            ("box end", S.crayonBoxEnd(width: 128, height: 64), 128),
            ("wrap", S.crayonWrap(band: 0xE8336F, name: "RASPBERRY", width: 64, height: 128), 64),
            ("wax sheen", S.waxSheen(size: 64), 64),
            ("wax smear", S.waxSmear(size: 64), 64),
            ("wax smear height", S.normalImage(S.waxSmearHeight(size: 64), strength: 1), 64),
            ("steel", S.normalImage(S.machinedSteel(width: 64, height: 32), strength: 1), 64),
            ("steel breakup", S.steelBreakup(width: 64, height: 32), 64),
            ("bottle label", S.bottleLabel(size: 64), 64),
        ]
        for (name, image, width) in images {
            #expect(image?.width == width, "\(name)")
        }
        // Tileable noise wraps: the value at u 0 is the value at u 1.
        let noise = TileFBM(periodX: 5, periodY: 3, octaves: 3, seed: 9)
        #expect(abs(noise(0, 0.3) - noise(1, 0.3)) < 1e-5 && abs(noise(0.2, 0) - noise(0.2, 1)) < 1e-5)
        let cells = TileCells(period: 6, seed: 2)
        let a = cells(0.01, 0.5), b = cells(1.01, 0.5)
        #expect(abs(a.x - b.x) < 1e-4 && a.x <= a.y)
    }

    @Test func glassShardsAreChunkyWithChippedEdges() {
        #expect(GlassDebris.fragmentThickness >= 0.002)
        for seed in UInt64(1)...30 {
            var rng = SplitMix64(seed: seed)
            let polygon = GlassDebris.shardPolygon(sides: 4 + Int(seed % 3), radii: [0.2, 0.4], rng: &rng)
            let chipped = GlassDebris.chipped(polygon, rng: &rng)
            #expect(chipped.count > polygon.count)
            for p in chipped {
                for i in polygon.indices {
                    let a = polygon[i], b = polygon[(i + 1) % polygon.count]
                    #expect((b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x) > -1e-5, "a chip leaves its shard")
                }
            }
            expectValid(MeshKit.polygonSlab(chipped, thickness: GlassDebris.fragmentThickness, rimInset: 0.035, outlineInset: 0.03),
                        "chipped shard \(seed)")
        }
    }

    @Test func crayonBoxSnapsEachCrayonOverItsOwnBreak() {
        for seed in UInt64(1)...20 {
            let order = CrayonBox.snapOrder(seed: seed)
            #expect(order.count == CrayonBox.snaps && Set(order) == Set(0..<7))
            #expect(Set(order.prefix(CrayonBox.topCount)) == Set([1, 3, 5]))
            let layout = CrayonBox.layout(seed: seed)
            #expect(layout.count == 7 && layout.allSatisfy { $0.cutIndex >= 0 && $0.cutIndex < CrayonBox.cuts.count })
        }
        #expect(CrayonBox.bottomRowStart([0.27, 0.31, 0.355, 0.4, 0.445]) == Float(0.4))
        // The platen prints the box: one snap feature per crayon (in snap order), then the seven lanes.
        let stamp = FoldStamps.stamp(for: .crayon, variant: PressVariant(kind: .crayon, seed: 5), foldScale: 1)
        #expect(stamp.features.count == 14)
        let box = stamp.silhouette.boundingBoxOfPath
        #expect(box.width > box.height)
        #expect(FoldStamps.crayonInks(stamp).count == 7)
    }

    @Test func canFoldsArePleatsAndThePunctureTears() {
        for band in 0..<5 {
            for k in 0..<360 {
                let p = CanCrush.pleat(theta: Float(k) * .pi / 180, band: band, phase: 0.7)
                #expect(p >= 0.2 && p <= 1)
            }
        }
        #expect(abs(CanCrush.foldProfile(0)) < 1e-5 && abs(CanCrush.foldProfile(1)) < 1e-5)
        #expect(abs(CanCrush.foldProfile(0.5) - 1) < 1e-5)
        for seed in 0..<3 {
            let petal = CanCrush.petalMesh(seed: UInt64(seed))
            expectValid(petal, "petal \(seed)")
            #expect(petal.materialSlots == 2)
            // It curls out of the wall (+y).
            #expect(petal.bounds().max.y > 0.001)
        }
        for seed in UInt64(1)...10 {
            let a = FoldStamps.canSprayAngle(PressVariant(kind: .sodaCan, seed: seed))
            #expect(a >= 0.6 && a <= 1.4)
        }
    }

    @Test func eggCracksZigzagAndJellyHoldsItsInclusions() {
        let a = EggShell.jag(seed: 7, cut: 3, ring: 10, sector: 0.785)
        #expect(a == EggShell.jag(seed: 7, cut: 3, ring: 10, sector: 0.785))
        #expect(abs(a) > 0 && abs(a) <= EggShell.jagShare * 0.785 + 1e-6)
        var signs = Set<Bool>()
        for ring in 0..<8 { signs.insert(EggShell.jag(seed: 7, cut: 1, ring: ring, sector: 0.785) > 0) }
        #expect(signs.count == 2)
        let profile: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(0.02, 0.01), SIMD2(0.03, 0.03), SIMD2(0.025, 0.05), SIMD2(0.012, 0.06), SIMD2(0, 0.065)]
        let patch = MeshKit.lathePatch(profile: profile, rings: 1...4, lower: { 0.1 + 0.05 * Float($0 % 2) },
                                       upper: { 0.9 - 0.05 * Float($0 % 2) }, angularSteps: 6, thickness: 0.0012)
        expectValid(patch.mesh, "jagged patch")
        expectValid(EggShell.flapMesh(seed: 1), "membrane flap")
        var rng = SplitMix64(seed: 4)
        for k in 0..<40 {
            let top = k % 2 == 0
            let p = JellyInclusions.spot(top: top, rng: &rng)
            #expect(simd_length(SIMD2(p.x, p.z)) <= JellyInclusions.radius(at: p.y) * 0.93 + 1e-6)
            if top { #expect(p.y > JellySpread.coreTopRatio * 0.0765) }
        }
    }

    /// LAUNCH-QA #5 (the anvil seemed to lag the print and the coach): every object's failure visual lands on the very
    /// frame the engine's failure event reaches it (`PressScene.handle(.fracture(…, isFailure: true))` calls
    /// `fracture`, then that frame's `update`), not frames later. Held at the failure compression, the frame with the
    /// failure must change what is drawn far more than a quiet frame just before it does.
    @MainActor
    @Test func everyFailureVisualLandsOnTheFailureFrame() {
        for kind in ObjectKind.allCases {
            guard let failure = kind.profile.failureIndex else { continue }
            let variant = PressVariant(kind: kind, seed: SpecimenPrint.plainSeed(for: kind))
            let thresholds = PressObjectFactory.thresholds(kind, variant: variant)
            guard failure < thresholds.count else { continue }
            let fx = SceneFX()
            let view = PressObjectFactory.make(kind, variant: variant, fx: fx)
            ObjectCrush.rest(view)
            view.handle(.contact, state: ObjectCrush.state(view, c: 0, dt: 0, time: 0, phase: .pressing))
            // Up to the failure compression, the earlier fractures firing as they are crossed.
            let cf = thresholds[failure]
            var time: Float = 0
            var fired = 0
            let steps = 90
            for step in 0...steps {
                let c = cf * Float(step) / Float(steps)
                time += 1.0 / 60
                let s = ObjectCrush.state(view, c: c, dt: 1.0 / 60, time: time, phase: .pressing)
                while fired < failure && c >= thresholds[fired] {
                    view.fracture(index: fired, isFailure: false, state: s)
                    fired += 1
                }
                view.update(s)
                fx.step(dt: 1.0 / 60, ceiling: view.surfaceHeight(compression: c), plateHalfExtent: SIMD2(repeating: 1))
            }
            func frame(failing: Bool) {
                time += 1.0 / 60
                let s = ObjectCrush.state(view, c: cf, dt: 1.0 / 60, time: time, phase: .pressing)
                if failing { view.fracture(index: failure, isFailure: true, state: s) }
                view.update(s)
                fx.step(dt: 1.0 / 60, ceiling: view.surfaceHeight(compression: cf), plateHalfExtent: SIMD2(repeating: 1))
            }
            // A quiet frame at the failure compression (only idle life and tremor move), then the failure frame.
            frame(failing: false)
            let before = Self.drawn(view, fx: fx)
            frame(failing: false)
            let quiet = Self.drawn(view, fx: fx)
            frame(failing: true)
            let failed = Self.drawn(view, fx: fx)
            let quietChange = Self.change(before, quiet)
            let failChange = Self.change(quiet, failed)
            let landed = failed.models != quiet.models || failed.debris > quiet.debris || failed.particles > quiet.particles
                || failChange > max(4 * quietChange, 0.0008)
            #expect(landed, "\(kind): the failure frame changed \(failChange) m (quiet \(quietChange) m), models \(quiet.models) → \(failed.models), debris \(quiet.debris) → \(failed.debris), particles \(quiet.particles) → \(failed.particles)")
        }
    }

    /// Launch QA: the object pictures ship in the bundle (no ARView renders them at run time), so every kind and look is
    /// there synchronously, square, at the shipped size.
    @MainActor
    @Test func everyObjectPictureShipsAndLoadsSynchronously() {
        for look in ObjectThumbnails.Look.allCases {
            for kind in ObjectKind.allCases {
                let image = ObjectThumbnails.cached(kind, look: look, size: CGSize(width: 160, height: 160))
                #expect(image != nil, "\(kind) \(look): no shipped picture")
                if let image {
                    let w = image.size.width * image.scale, h = image.size.height * image.scale
                    #expect(w == ObjectThumbnails.pixelSize && h == ObjectThumbnails.pixelSize, "\(kind) \(look): \(w)×\(h)")
                }
            }
        }
    }

    /// LAUNCH-QA (duo-reveal-slomo-after): after a requested slow-mo replay the duck came back in the replay tape's
    /// puffier, rebounded shape. The replay must play on a copy and hand back the very specimen the reveal showed: the
    /// same entity, drawn exactly as before.
    @MainActor
    @Test func aReplayHandsBackTheRevealedSpecimenUnchanged() async throws {
        let scene = PressScene()
        let variant = PressVariant(kind: .rubberDuck, seed: 42)
        scene.setObject(.rubberDuck, variant: variant)
        var waited = 0
        while scene.foldObject == nil && waited < 600 {
            try await Task.sleep(nanoseconds: 50_000_000)
            waited += 1
        }
        try #require(scene.foldObject != nil)
        let anvil = FoldAnvil()
        anvil.setScale(0.004427)
        scene.setFraming(.foldAnvil, anvil: anvil.root)
        let engine = PressEngine()
        let context = FeedbackContext(kind: .rubberDuck, variant: variant, compression: 0, closingSpeed: 0,
                                      soundStyle: .workshop, reduceMotion: false)
        engine.onEvent = { scene.handle($0, context: context) }
        engine.ingest(angle: 180, closed: false, at: 0)
        engine.load(.rubberDuck, seed: 42, at: 0)
        var now = 0.0
        func frames(_ seconds: Double, angle: ((Double) -> Double)? = nil) {
            for _ in 0..<Int(seconds * 60) {
                now += 1.0 / 60
                if let angle { engine.ingest(angle: angle(now), closed: false, at: now) }
                engine.step(now: now, dt: 1.0 / 60)
                scene.update(engine: engine, context: context, dt: 1.0 / 60)
            }
        }
        frames(2)
        let start = now
        frames(3) { t in max(180 - 60 * (t - start), 3) }
        let reopen = now
        frames(2) { t in min(3 + 120 * (t - reopen), 170) }
        #expect(engine.phase == .revealing)
        frames(2)
        let id = try #require(scene.objectEntityID)
        let before = scene.specimenCorners
        #expect(!before.isEmpty)
        let duration = try #require(scene.playBreakReplay(speed: 1), "no replay recorded")
        frames(0.3)
        #expect(scene.isReplaying)
        #expect(scene.objectEntityID != id, "the replay plays on a copy")
        frames(duration + 0.5)
        #expect(!scene.isReplaying)
        #expect(scene.objectEntityID == id, "the hand-back kept the replay's copy")
        let after = scene.specimenCorners
        #expect(after.count == before.count, "models \(before.count / 2) → \(after.count / 2)")
        if after.count == before.count {
            let worst = zip(before, after).map { simd_length($0 - $1) }.max() ?? 0
            #expect(worst < 0.001, "the specimen moved \(worst) m across the replay")
        }
    }

    /// LAUNCH-QA #1: drops, beads and print splats lay on the page background past the strike plate. On the Duo the
    /// mess's walls close in to this object's plate; every print splat (and its droplets) stays on the platen's plate at
    /// the splat's widest spread.
    @MainActor
    @Test func theMessStaysOnTheStrikePlate() throws {
        let fx = SceneFX()
        let plate = GlassDebris.containment(restHeight: 0.0765, anvilHalf: SIMD2(repeating: 1), padding: 0)
        fx.foldPlateHalf = plate
        fx.step(dt: 0, ceiling: 10, plateHalfExtent: SIMD2(repeating: 1))   // the Duo's whole-anvil ceiling
        let wall = plate * SceneFX.foldWallShare
        #expect(fx.particles.maxXZ == wall && fx.particles.minXZ == -wall)
        #expect(fx.debris.world.maxXZ == wall && fx.debris.world.minXZ == -wall)
        fx.step(dt: 0, ceiling: 10, plateHalfExtent: SIMD2(0.08, 0.057))   // the P-48's ram plate: its anvil edges
        #expect(fx.particles.maxXZ == PressRig.anvilHalf && fx.debris.world.maxXZ == PressRig.anvilHalf)

        let canvas = FoldPrintCanvas.rect
        let spread = FoldStamps.splatMaxSpread
        let hx = CGFloat(FoldMetrics.plateLateral / 2 - 3) / spread + 1
        let hy = CGFloat(FoldMetrics.plateDepth / 2 - 3) / spread + 1
        for kind in [ObjectKind.rubberDuck, .jelly, .sodaCan, .cakeSlice, .gummyBear, .egg] {
            for seed in UInt64(1)...4 {
                let variant = PressVariant(kind: kind, seed: seed)
                let stamp = FoldStamps.stamp(for: kind, variant: variant, foldScale: SpecimenPrint.foldScale(kind, variant: variant),
                                             extraYaw: 0)
                for d in FoldStamps.platenSplatDroplets(stamp, variant: variant) {
                    #expect(FoldStamps.dropletOnPlate(d), "\(kind) seed \(seed): droplet at \(d.centre) r \(d.radius) off the plate")
                }
                let scale: CGFloat = 1
                let image = try #require(FoldStamps.splatImage(stamp, variant: variant, scale: scale))
                let data = try #require(image.dataProvider?.data)
                guard let bytes = CFDataGetBytePtr(data) else { continue }
                var stray = 0
                for py in 0..<image.height {
                    for px in 0..<image.width {
                        let x = canvas.minX + (CGFloat(px) + 0.5) / scale
                        let y = canvas.minY + (CGFloat(py) + 0.5) / scale
                        guard abs(x) > hx || abs(y) > hy else { continue }
                        if bytes[py * image.bytesPerRow + px * 4 + 3] > 0 { stray += 1 }
                    }
                }
                #expect(stray == 0, "\(kind) seed \(seed): \(stray) px of splat off the plate at full spread")
            }
        }
    }

    /// What is drawn: every enabled model's (or deformed mesh's) world placement and bounds, the model count, and the
    /// mess's piece and particle counts.
    @MainActor
    private static func drawn(_ view: PressObjectView, fx: SceneFX) -> (values: [Float], models: Int, debris: Int, particles: Int) {
        let corners = VisibleBounds.corners(of: view.entity) + VisibleBounds.corners(of: fx.root)
        let values = corners.flatMap { [$0.x, $0.y, $0.z] }
        return (values, corners.count / 2, fx.debris.count, fx.particles.activeCount)
    }

    /// The largest move (metres) of any drawn corner between two `drawn` samples (infinite if the models changed).
    private static func change(_ a: (values: [Float], models: Int, debris: Int, particles: Int),
                               _ b: (values: [Float], models: Int, debris: Int, particles: Int)) -> Float {
        guard a.values.count == b.values.count else { return .infinity }
        var worst: Float = 0
        for i in a.values.indices { worst = max(worst, abs(a.values[i] - b.values[i])) }
        return worst
    }

    /// Coordinator, Duo run 40174301077: every pop fired (sound and haptics) while the domes still looked whole. A bubble
    /// must burst on the very frame its fracture fires (dome gone, crinkled crater down), stay burst, and the bubbles not
    /// yet popped must keep flattening under the plate.
    @MainActor
    @Test func aBubbleBurstsOnTheFrameItsFractureFiresAndStaysBurst() {
        let variant = PressVariant(kind: .bubbleWrap, seed: SpecimenPrint.plainSeed(for: .bubbleWrap))
        let view = BubbleWrapView(variant: variant, fx: SceneFX())
        ObjectCrush.rest(view)
        let order = BubbleWrapGrid.popOrder(seed: variant.seed)
        let first = order[0], last = order[order.count - 1]
        // The dome at rest, before any ripple jiggles it.
        let lastAtRest = view.domeHeightScale(last)
        var s = ObjectCrush.state(view, c: 0.1, dt: 1.0 / 60, time: 1, phase: .pressing)
        view.update(s)
        #expect(view.domeVisible(first) && !view.isBurst(first) && view.craterCount == 0)
        // The fracture alone bursts it: no further update is needed for the dome to go and the crater to land.
        view.fracture(index: 0, isFailure: false, state: s)
        #expect(view.isBurst(first) && !view.domeVisible(first))
        #expect(view.craterCount == 1)
        // It stays burst while the press goes on (and through a hit stop, dt 0), and the others flatten progressively.
        for k in 1...40 {
            let c = 0.1 + Float(k) * 0.015
            s = ObjectCrush.state(view, c: c, dt: k % 5 == 0 ? 0 : 1.0 / 60, time: 1 + Float(k) / 60, phase: .pressing)
            view.update(s)
            #expect(!view.domeVisible(first), "the burst dome came back at c \(c)")
            // The ripple only ever squashes a dome further, never up through the plate.
            #expect(view.domeHeightScale(last) <= lastAtRest + 1e-6, "an unpopped dome rose at c \(c)")
        }
        #expect(view.domeHeightScale(last) < lastAtRest * 0.8, "the unpopped domes didn't flatten")
        // Every fracture bursts exactly one more bubble.
        for index in 1..<order.count { view.fracture(index: index, isFailure: false, state: s) }
        #expect(view.craterCount == order.count)
        #expect(order.allSatisfy { view.isBurst($0) && !view.domeVisible($0) })
    }

    /// Height (top above the anvil) and top-down footprint area of an object view and its debris, visible parts only.
    @MainActor
    /// `reach`: how far it extends along x (the long axis of the plate) from the centre.
    private static func footprint(of view: PressObjectView, fx: SceneFX) -> (height: Float, area: Float, reach: Float) {
        // Mesh bounds walked by hand: `visualBounds` is empty for entities that aren't in a scene.
        let parts = [VisibleBounds.of(view.entity), VisibleBounds.of(fx.debris.root)].compactMap { $0 }
        guard let first = parts.first else { return (0, 0, 0) }
        var lo = first.min, hi = first.max
        for part in parts.dropFirst() {
            lo = simd_min(lo, part.min)
            hi = simd_max(hi, part.max)
        }
        let size = hi - lo
        let reach = max(abs(lo.x), abs(hi.x))
        return (hi.y, max(size.x, 0) * max(size.z, 0), reach)
    }
}
