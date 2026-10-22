import Foundation
import RealityKit
import simd

/// CPU-side triangle mesh: positions, normals, CCW-from-outside triangles and an optional material id per triangle.
/// Every procedural builder in the kit returns one of these; `MeshData.resource()` turns it into a `MeshResource`.
struct MeshData {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var indices: [UInt32] = []
    /// Material slot per triangle (same count as `indices.count / 3`). Empty means slot 0 everywhere.
    var triangleMaterials: [UInt8] = []

    var vertexCount: Int { positions.count }
    var triangleCount: Int { indices.count / 3 }

    var isValid: Bool {
        guard positions.count == normals.count, indices.count % 3 == 0, !indices.isEmpty else { return false }
        guard triangleMaterials.isEmpty || triangleMaterials.count == triangleCount else { return false }
        let count = UInt32(positions.count)
        return indices.allSatisfy { $0 < count }
    }

    var materialSlots: Int {
        Int(triangleMaterials.max() ?? 0) + 1
    }

    mutating func addTriangle(_ a: Int, _ b: Int, _ c: Int, material: UInt8 = 0) {
        indices.append(UInt32(a))
        indices.append(UInt32(b))
        indices.append(UInt32(c))
        if !triangleMaterials.isEmpty || material != 0 {
            if triangleMaterials.count < triangleCount - 1 {
                triangleMaterials.append(contentsOf: [UInt8](repeating: 0, count: triangleCount - 1 - triangleMaterials.count))
            }
            triangleMaterials.append(material)
        }
    }

    mutating func addVertex(_ p: SIMD3<Float>, _ n: SIMD3<Float>) -> Int {
        positions.append(p)
        normals.append(n)
        return positions.count - 1
    }

    /// Appends another mesh (its material slots are offset by `materialOffset`).
    mutating func append(_ other: MeshData, materialOffset: UInt8 = 0) {
        let base = UInt32(positions.count)
        let ownTriangles = triangleCount
        positions.append(contentsOf: other.positions)
        normals.append(contentsOf: other.normals)
        indices.append(contentsOf: other.indices.map { $0 + base })
        if !other.triangleMaterials.isEmpty || materialOffset != 0 || !triangleMaterials.isEmpty {
            if triangleMaterials.count < ownTriangles {
                triangleMaterials.append(contentsOf: [UInt8](repeating: 0, count: ownTriangles - triangleMaterials.count))
            }
            if other.triangleMaterials.isEmpty {
                triangleMaterials.append(contentsOf: [UInt8](repeating: materialOffset, count: other.triangleCount))
            } else {
                triangleMaterials.append(contentsOf: other.triangleMaterials.map { $0 &+ materialOffset })
            }
        }
    }

    func transformed(_ m: simd_float4x4) -> MeshData {
        var copy = self
        let normalMatrix = simd_float3x3(SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z),
                                         SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z),
                                         SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z)).inverse.transpose
        copy.positions = positions.map { p in
            let v = m * SIMD4<Float>(p.x, p.y, p.z, 1)
            return SIMD3(v.x, v.y, v.z)
        }
        copy.normals = normals.map { simd_normalize(normalMatrix * $0) }
        if simd_determinant(m) < 0 { copy.flipWinding() }
        return copy
    }

    func translated(_ t: SIMD3<Float>) -> MeshData {
        var copy = self
        copy.positions = positions.map { $0 + t }
        return copy
    }

    mutating func flipWinding() {
        var i = 0
        while i + 2 < indices.count {
            indices.swapAt(i + 1, i + 2)
            i += 3
        }
    }

    /// Makes each triangle wind counter-clockwise around the average of its vertex normals
    /// (RealityKit front faces are CCW). Builders provide analytic normals, so this is the single source of winding truth.
    mutating func orientToNormals() {
        var i = 0
        while i + 2 < indices.count {
            let a = Int(indices[i]), b = Int(indices[i + 1]), c = Int(indices[i + 2])
            let face = simd_cross(positions[b] - positions[a], positions[c] - positions[a])
            let expected = normals[a] + normals[b] + normals[c]
            if simd_dot(face, expected) < 0 {
                indices.swapAt(i + 1, i + 2)
            }
            i += 3
        }
        if MeshKit.flipAllWinding { flipWinding() }
    }

    /// Area-weighted smooth normals from the triangles (used after CPU deformation).
    mutating func recomputeNormals() {
        MeshKit.computeNormals(positions: positions, indices: indices, into: &normals)
    }

    func bounds() -> (min: SIMD3<Float>, max: SIMD3<Float>) {
        guard var lo = positions.first else { return (.zero, .zero) }
        var hi = lo
        for p in positions {
            lo = simd_min(lo, p)
            hi = simd_max(hi, p)
        }
        return (lo, hi)
    }

    var centroid: SIMD3<Float> {
        guard !positions.isEmpty else { return .zero }
        return positions.reduce(SIMD3<Float>.zero, +) / Float(positions.count)
    }

    /// One sub-mesh per material slot (vertices shared by several slots are duplicated).
    func splitByMaterial() -> [(slot: Int, mesh: MeshData, sourceVertex: [Int])] {
        let slots = materialSlots
        if slots == 1 {
            return [(0, self, Array(0..<positions.count))]
        }
        var result: [(Int, MeshData, [Int])] = []
        for slot in 0..<slots {
            var remap = [Int](repeating: -1, count: positions.count)
            var sub = MeshData()
            var source: [Int] = []
            for t in 0..<triangleCount where Int(triangleMaterials[t]) == slot {
                for k in 0..<3 {
                    let v = Int(indices[t * 3 + k])
                    if remap[v] < 0 {
                        remap[v] = sub.positions.count
                        sub.positions.append(positions[v])
                        sub.normals.append(normals[v])
                        source.append(v)
                    }
                    sub.indices.append(UInt32(remap[v]))
                }
            }
            if !sub.indices.isEmpty {
                result.append((slot, sub, source))
            }
        }
        return result
    }

    /// A RealityKit mesh (single material slot; use `MeshKit.entity` for multi-material meshes).
    @MainActor
    func resource(name: String = "mesh") -> MeshResource? {
        guard isValid else { return nil }
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }
}

/// Procedural mesh builders (bible §9 asset strategy: lathe, extrusion, blobs, grid, spread discs).
enum MeshKit {
    /// Safety valve: if CI screenshots show inside-out meshes, flip this one constant.
    static let flipAllWinding = false

    /// Builds a ModelEntity (or a parent of one ModelEntity per material slot) from mesh data.
    @MainActor
    static func entity(_ data: MeshData, materials: [any Material], name: String = "mesh") -> Entity {
        let parts = data.splitByMaterial()
        if parts.count == 1, let mesh = parts[0].mesh.resource(name: name) {
            return ModelEntity(mesh: mesh, materials: [materials[min(parts[0].slot, materials.count - 1)]])
        }
        let parent = Entity()
        for part in parts {
            guard let mesh = part.mesh.resource(name: "\(name)-\(part.slot)") else { continue }
            parent.addChild(ModelEntity(mesh: mesh, materials: [materials[min(part.slot, materials.count - 1)]]))
        }
        return parent
    }

    @MainActor
    static func model(_ data: MeshData, material: any Material, name: String = "mesh") -> ModelEntity {
        if let mesh = data.resource(name: name) {
            return ModelEntity(mesh: mesh, materials: [material])
        }
        return ModelEntity(mesh: .generateSphere(radius: 0.001), materials: [material])
    }

    static func computeNormals(positions: [SIMD3<Float>], indices: [UInt32], into normals: inout [SIMD3<Float>]) {
        if normals.count != positions.count {
            normals = [SIMD3<Float>](repeating: .zero, count: positions.count)
        } else {
            for i in normals.indices { normals[i] = .zero }
        }
        var i = 0
        while i + 2 < indices.count {
            let a = Int(indices[i]), b = Int(indices[i + 1]), c = Int(indices[i + 2])
            let n = simd_cross(positions[b] - positions[a], positions[c] - positions[a])
            normals[a] += n
            normals[b] += n
            normals[c] += n
            i += 3
        }
        if flipAllWinding {
            for k in normals.indices { normals[k] = -normals[k] }
        }
        for k in normals.indices {
            let length = simd_length(normals[k])
            normals[k] = length > 1e-12 ? normals[k] / length : SIMD3(0, 1, 0)
        }
    }

    // MARK: - Lathe (surface of revolution)

    /// Revolves a profile of (radius, y) points, ordered bottom → top, around the Y axis.
    /// Points with radius ≈ 0 become single pole vertices. Seam-free (indices wrap), so CPU-recomputed normals stay smooth.
    /// - Parameters:
    ///   - rimScale: optional per-angle radius multiplier (seeded noisy rims); normals ignore it (keep it subtle).
    ///   - material: material slot for the band between profile points `i` and `i + 1`.
    static func lathe(profile: [SIMD2<Float>], segments: Int,
                      rimScale: ((Float) -> Float)? = nil,
                      material: ((Int) -> UInt8)? = nil) -> MeshData {
        var mesh = MeshData()
        let n = max(segments, 3)
        let profileNormals = profile2DNormals(profile)
        var rings: [[Int]] = []
        for (i, point) in profile.enumerated() {
            let n2 = profileNormals[i]
            if point.x < 1e-6 {
                let normal = SIMD3<Float>(0, n2.y >= 0 ? 1 : -1, 0)
                rings.append([mesh.addVertex(SIMD3(0, point.y, 0), normal)])
                continue
            }
            var ring: [Int] = []
            for j in 0..<n {
                let theta = Float(j) / Float(n) * 2 * .pi
                let scale = rimScale?(theta) ?? 1
                let c = cos(theta), s = sin(theta)
                let p = SIMD3<Float>(point.x * scale * c, point.y, point.x * scale * s)
                let normal = simd_normalize(SIMD3<Float>(n2.x * c, n2.y, n2.x * s))
                ring.append(mesh.addVertex(p, normal))
            }
            rings.append(ring)
        }
        for i in 0..<(rings.count - 1) {
            let lower = rings[i], upper = rings[i + 1]
            let slot = material?(i) ?? 0
            if lower.count == 1 && upper.count == 1 { continue }
            for j in 0..<n {
                let j1 = (j + 1) % n
                if lower.count == 1 {
                    mesh.addTriangle(lower[0], upper[j], upper[j1], material: slot)
                } else if upper.count == 1 {
                    mesh.addTriangle(lower[j], lower[j1], upper[0], material: slot)
                } else {
                    mesh.addTriangle(lower[j], upper[j], upper[j1], material: slot)
                    mesh.addTriangle(lower[j], upper[j1], lower[j1], material: slot)
                }
            }
        }
        mesh.orientToNormals()
        return mesh
    }

    /// Outward 2D normals of a (radius, y) profile, from central differences.
    static func profile2DNormals(_ profile: [SIMD2<Float>]) -> [SIMD2<Float>] {
        profile.indices.map { i in
            let prev = profile[max(i - 1, 0)]
            let next = profile[min(i + 1, profile.count - 1)]
            let t = next - prev
            let n = SIMD2<Float>(t.y, -t.x)
            let length = simd_length(n)
            return length > 1e-9 ? n / length : SIMD2(1, 0)
        }
    }

    /// One shell patch of a lathe surface (for pre-fractured eggs and bottles): the outer surface between
    /// profile points `rings` and angular range `angles` (radians), an inner surface `thickness` inside it,
    /// and flat side walls. Returned relative to its own centroid; `centre` is where to place it.
    static func lathePatch(profile: [SIMD2<Float>], rings: ClosedRange<Int>, angles: ClosedRange<Float>,
                           angularSteps: Int, thickness: Float) -> (mesh: MeshData, centre: SIMD3<Float>) {
        let normals2 = profile2DNormals(profile)
        let rows = Array(rings)
        let cols = max(angularSteps, 1)
        var outer: [[SIMD3<Float>]] = []
        var outerN: [[SIMD3<Float>]] = []
        for i in rows {
            var rowP: [SIMD3<Float>] = []
            var rowN: [SIMD3<Float>] = []
            for k in 0...cols {
                let theta = angles.lowerBound + (angles.upperBound - angles.lowerBound) * Float(k) / Float(cols)
                let c = cos(theta), s = sin(theta)
                let r = profile[i].x
                rowP.append(SIMD3(r * c, profile[i].y, r * s))
                let n2 = normals2[i]
                rowN.append(simd_normalize(SIMD3(n2.x * c, n2.y, n2.x * s)))
            }
            outer.append(rowP)
            outerN.append(rowN)
        }
        var mesh = MeshData()
        let rCount = rows.count
        // Outer and inner surfaces.
        for side in 0..<2 {
            var grid: [[Int]] = []
            for a in 0..<rCount {
                var row: [Int] = []
                for k in 0...cols {
                    let n = outerN[a][k]
                    let p = side == 0 ? outer[a][k] : outer[a][k] - n * thickness
                    row.append(mesh.addVertex(p, side == 0 ? n : -n))
                }
                grid.append(row)
            }
            for a in 0..<(rCount - 1) {
                for k in 0..<cols {
                    mesh.addTriangle(grid[a][k], grid[a + 1][k], grid[a + 1][k + 1], material: UInt8(side))
                    mesh.addTriangle(grid[a][k], grid[a + 1][k + 1], grid[a][k + 1], material: UInt8(side))
                }
            }
        }
        let centre = mesh.centroid
        // Side walls (flat shaded), facing away from the patch centre.
        func wall(_ edge: [(SIMD3<Float>, SIMD3<Float>)]) {
            guard edge.count >= 2 else { return }
            for e in 0..<(edge.count - 1) {
                let (p0, n0) = edge[e], (p1, n1) = edge[e + 1]
                let q0 = p0 - n0 * thickness, q1 = p1 - n1 * thickness
                var face = simd_cross(p1 - p0, q0 - p0)
                if simd_length(face) < 1e-12 { continue }
                let mid = (p0 + p1 + q0 + q1) / 4
                if simd_dot(face, mid - centre) < 0 { face = -face }
                let fn = simd_normalize(face)
                let a = mesh.addVertex(p0, fn), b = mesh.addVertex(p1, fn)
                let c = mesh.addVertex(q1, fn), d = mesh.addVertex(q0, fn)
                mesh.addTriangle(a, b, c, material: 1)
                mesh.addTriangle(a, c, d, material: 1)
            }
        }
        wall((0...cols).map { (outer[0][$0], outerN[0][$0]) })
        wall((0...cols).map { (outer[rCount - 1][$0], outerN[rCount - 1][$0]) })
        wall((0..<rCount).map { (outer[$0][0], outerN[$0][0]) })
        wall((0..<rCount).map { (outer[$0][cols], outerN[$0][cols]) })
        mesh.orientToNormals()
        return (mesh.translated(-centre), centre)
    }

    // MARK: - Spheres, ellipsoids, capsules

    static func ellipsoid(radii: SIMD3<Float>, segments: Int = 48, rings: Int = 24) -> MeshData {
        var profile: [SIMD2<Float>] = []
        for i in 0...rings {
            let phi = -Float.pi / 2 + Float.pi * Float(i) / Float(rings)
            profile.append(SIMD2(cos(phi), sin(phi)))
        }
        profile[0].x = 0
        profile[rings].x = 0
        var mesh = lathe(profile: profile, segments: segments)
        mesh.positions = mesh.positions.map { $0 * radii }
        let inv = SIMD3<Float>(1 / radii.x, 1 / radii.y, 1 / radii.z)
        mesh.normals = mesh.normals.map { simd_normalize($0 * inv) }
        return mesh
    }

    static func sphere(radius: Float, segments: Int = 48, rings: Int = 24) -> MeshData {
        ellipsoid(radii: SIMD3(repeating: radius), segments: segments, rings: rings)
    }

    /// Profile of an upright cylinder with rounded top and bottom rims, from the bottom pole to the top pole.
    static func roundedCylinderProfile(radius: Float, height: Float, bevel: Float, bevelSteps: Int = 5,
                                       bodyRings: Int = 1) -> [SIMD2<Float>] {
        let b = min(bevel, radius * 0.95, height * 0.5)
        var profile: [SIMD2<Float>] = [SIMD2(0, 0)]
        for k in 0...bevelSteps {
            let a = -Float.pi / 2 + Float.pi / 2 * Float(k) / Float(bevelSteps)
            profile.append(SIMD2(radius - b + b * cos(a), b + b * sin(a)))
        }
        if bodyRings > 1 {
            for k in 1..<bodyRings {
                profile.append(SIMD2(radius, b + (height - 2 * b) * Float(k) / Float(bodyRings)))
            }
        }
        for k in 0...bevelSteps {
            let a = Float.pi / 2 * Float(k) / Float(bevelSteps)
            profile.append(SIMD2(radius - b + b * cos(a), height - b + b * sin(a)))
        }
        profile.append(SIMD2(0, height))
        return profile
    }

    static func roundedCylinder(radius: Float, height: Float, bevel: Float, segments: Int = 64) -> MeshData {
        lathe(profile: roundedCylinderProfile(radius: radius, height: height, bevel: bevel), segments: segments)
    }

    /// A tube along +Y from y = 0 to `length` with hemispherical ends (candles, columns, piston rods).
    static func capsule(radius: Float, length: Float, segments: Int = 48) -> MeshData {
        roundedCylinder(radius: radius, height: length, bevel: radius * 0.98, segments: segments)
    }

    /// A torus around the Y axis (collars, bezels).
    static func torus(major: Float, minor: Float, segments: Int = 64, sides: Int = 16) -> MeshData {
        var mesh = MeshData()
        for j in 0..<segments {
            let theta = Float(j) / Float(segments) * 2 * .pi
            let c = cos(theta), s = sin(theta)
            for k in 0..<sides {
                let phi = Float(k) / Float(sides) * 2 * .pi
                let n = SIMD3<Float>(cos(phi) * c, sin(phi), cos(phi) * s)
                let p = SIMD3<Float>((major + minor * cos(phi)) * c, minor * sin(phi), (major + minor * cos(phi)) * s)
                _ = mesh.addVertex(p, n)
            }
        }
        for j in 0..<segments {
            for k in 0..<sides {
                let a = j * sides + k
                let b = ((j + 1) % segments) * sides + k
                let c = ((j + 1) % segments) * sides + (k + 1) % sides
                let d = j * sides + (k + 1) % sides
                mesh.addTriangle(a, b, c)
                mesh.addTriangle(a, c, d)
            }
        }
        mesh.orientToNormals()
        return mesh
    }

    // MARK: - Rounded prism (extrusion)

    /// Extrudes a convex polygon (XZ, any winding) to `height`, with vertical corners rounded by `cornerRadius`
    /// and top/bottom edges bevelled by `bevel` (≤ cornerRadius). Origin at the bottom face.
    /// - Parameter bandMaterial: optional material slot by height fraction (0 bottom … 1 top) for the side wall.
    static func roundedPrism(polygon: [SIMD2<Float>], height: Float, cornerRadius: Float, bevel: Float,
                             cornerSteps: Int = 6, bevelSteps: Int = 4,
                             bandMaterial: ((Float) -> UInt8)? = nil, capMaterial: UInt8 = 0) -> MeshData {
        // Normalise to counter-clockwise in (x, z) seen from +Y.
        var poly = polygon
        var area: Float = 0
        for i in poly.indices {
            let a = poly[i], b = poly[(i + 1) % poly.count]
            area += a.x * b.y - b.x * a.y
        }
        if area > 0 { poly.reverse() } // (x, z) with +Y up: positive area in x→z is clockwise seen from above
        let R = max(cornerRadius, bevel + 1e-4)
        let bev = min(bevel, R * 0.95, height * 0.5)
        // Inner polygon = corners offset inward by R; rounded outline = inner ⊕ disc(R − inset).
        let count = poly.count
        var edgeNormals: [SIMD2<Float>] = []
        for i in 0..<count {
            let a = poly[i], b = poly[(i + 1) % count]
            let d = simd_normalize(b - a)
            var n = SIMD2<Float>(d.y, -d.x)
            let mid = (a + b) / 2
            let centre = poly.reduce(SIMD2<Float>.zero, +) / Float(count)
            if simd_dot(n, mid - centre) < 0 { n = -n }
            edgeNormals.append(n)
        }
        var arcCentres: [SIMD2<Float>] = []
        var arcStart: [Float] = []
        var arcSweep: [Float] = []
        for i in 0..<count {
            let nPrev = edgeNormals[(i - 1 + count) % count]
            let nNext = edgeNormals[i]
            let bisector = simd_normalize(nPrev + nNext)
            let cosHalf = max(simd_dot(bisector, nNext), 0.2)
            arcCentres.append(poly[i] - bisector * (R / cosHalf))
            let a0 = atan2(nPrev.y, nPrev.x)
            var a1 = atan2(nNext.y, nNext.x)
            // Sweep the short way round, in the polygon's winding direction.
            var sweep = a1 - a0
            while sweep > .pi { sweep -= 2 * .pi }
            while sweep < -.pi { sweep += 2 * .pi }
            a1 = a0 + sweep
            arcStart.append(a0)
            arcSweep.append(sweep)
        }
        // Outline directions (unit normals) sampled around the rounded corners.
        var outlineCentres: [SIMD2<Float>] = []
        var outlineNormals: [SIMD2<Float>] = []
        for i in 0..<count {
            for k in 0...cornerSteps {
                let a = arcStart[i] + arcSweep[i] * Float(k) / Float(cornerSteps)
                outlineCentres.append(arcCentres[i])
                outlineNormals.append(SIMD2(cos(a), sin(a)))
            }
        }
        // Profile: (outward offset from the inner polygon, y, profile normal) bottom → top.
        var profile: [(off: Float, y: Float, n: SIMD2<Float>)] = []
        for k in 0...bevelSteps {
            let a = -Float.pi / 2 + Float.pi / 2 * Float(k) / Float(bevelSteps)
            profile.append((R - bev + bev * cos(a), bev + bev * sin(a), SIMD2(cos(a), sin(a))))
        }
        let wallBands = 6
        for k in 1..<wallBands {
            profile.append((R, bev + (height - 2 * bev) * Float(k) / Float(wallBands), SIMD2(1, 0)))
        }
        for k in 0...bevelSteps {
            let a = Float.pi / 2 * Float(k) / Float(bevelSteps)
            profile.append((R - bev + bev * cos(a), height - bev + bev * sin(a), SIMD2(cos(a), sin(a))))
        }
        var mesh = MeshData()
        let m = outlineCentres.count
        var rings: [[Int]] = []
        for row in profile {
            var ring: [Int] = []
            for j in 0..<m {
                let c = outlineCentres[j], n2 = outlineNormals[j]
                let xz = c + n2 * row.off
                let normal = SIMD3<Float>(n2.x * row.n.x, row.n.y, n2.y * row.n.x)
                ring.append(mesh.addVertex(SIMD3(xz.x, row.y, xz.y), simd_normalize(normal)))
            }
            rings.append(ring)
        }
        for r in 0..<(rings.count - 1) {
            let frac = (profile[r].y + profile[r + 1].y) / 2 / max(height, 1e-6)
            let slot = bandMaterial?(frac) ?? 0
            for j in 0..<m {
                let j1 = (j + 1) % m
                mesh.addTriangle(rings[r][j], rings[r + 1][j], rings[r + 1][j1], material: slot)
                mesh.addTriangle(rings[r][j], rings[r + 1][j1], rings[r][j1], material: slot)
            }
        }
        // Caps: fans from the centroid.
        let centre2 = poly.reduce(SIMD2<Float>.zero, +) / Float(count)
        let bottom = mesh.addVertex(SIMD3(centre2.x, 0, centre2.y), SIMD3(0, -1, 0))
        let top = mesh.addVertex(SIMD3(centre2.x, height, centre2.y), SIMD3(0, 1, 0))
        let first = rings[0], last = rings[rings.count - 1]
        for j in 0..<m {
            let j1 = (j + 1) % m
            mesh.addTriangle(bottom, first[j1], first[j], material: capMaterial)
            mesh.addTriangle(top, last[j], last[j1], material: capMaterial)
        }
        mesh.orientToNormals()
        return mesh
    }

    /// A rounded box (the kit's replacement for raw boxes). Origin at the centre.
    static func roundedBox(_ size: SIMD3<Float>, radius: Float, bevel: Float? = nil,
                           bandMaterial: ((Float) -> UInt8)? = nil) -> MeshData {
        let hx = size.x / 2, hz = size.z / 2
        let r = min(radius, hx * 0.95, hz * 0.95)
        let mesh = roundedPrism(polygon: [SIMD2(-hx, -hz), SIMD2(hx, -hz), SIMD2(hx, hz), SIMD2(-hx, hz)],
                                height: size.y, cornerRadius: r, bevel: min(bevel ?? r, size.y * 0.5),
                                bandMaterial: bandMaterial)
        return mesh.translated(SIMD3(0, -size.y / 2, 0))
    }

    // MARK: - Spread disc

    /// A low puddle/spread disc with a soft bevelled edge and a seeded noisy rim (jam, yolk, fizz, jelly overflow).
    /// Unit radius, `height` tall; scale XZ to grow it.
    static func spreadDisc(seed: UInt64, height: Float = 0.1, segments: Int = 64, wobble: Float = 0.14) -> MeshData {
        var rng = SplitMix64(seed: seed)
        let lobes: [(k: Float, amp: Float, phase: Float)] = (0..<4).map { i in
            (k: Float([3, 5, 7, 11][i]), amp: wobble * Float.random(in: 0.25...1, using: &rng) / Float(i + 1),
             phase: Float.random(in: 0...(2 * .pi), using: &rng))
        }
        let rim: (Float) -> Float = { theta in
            var r: Float = 1
            for lobe in lobes { r += lobe.amp * sin(lobe.k * theta + lobe.phase) }
            return max(r, 0.6)
        }
        let profile: [SIMD2<Float>] = [
            SIMD2(0, 0), SIMD2(0.97, 0), SIMD2(1.0, height * 0.35), SIMD2(0.96, height * 0.8),
            SIMD2(0.85, height * 0.97), SIMD2(0.5, height), SIMD2(0, height),
        ]
        return lathe(profile: profile, segments: segments, rimScale: rim)
    }

    /// Catmull-Rom resampling of a (radius, y) control profile into a smooth one with `perSpan` points per span.
    /// End points are kept exactly (poles stay on the axis).
    static func smoothProfile(_ points: [SIMD2<Float>], perSpan: Int = 4) -> [SIMD2<Float>] {
        guard points.count > 2 else { return points }
        var result: [SIMD2<Float>] = []
        for i in 0..<(points.count - 1) {
            let p0 = points[max(i - 1, 0)], p1 = points[i], p2 = points[i + 1], p3 = points[min(i + 2, points.count - 1)]
            for k in 0..<perSpan {
                let t = Float(k) / Float(perSpan)
                let t2 = t * t, t3 = t2 * t
                let a: SIMD2<Float> = p1 * 2
                let b: SIMD2<Float> = (p2 - p0) * t
                let c2: SIMD2<Float> = p0 * 2 - p1 * 5
                let c: SIMD2<Float> = (c2 + p2 * 4 - p3) * t2
                let d2: SIMD2<Float> = p1 * 3 - p0
                let d: SIMD2<Float> = (d2 - p2 * 3 + p3) * t3
                var q: SIMD2<Float> = (a + b + c + d) * 0.5
                q.x = max(q.x, 0)
                result.append(q)
            }
        }
        result.append(points[points.count - 1])
        result[0] = points[0]
        return result
    }

    // MARK: - Noise

    /// Smooth seeded 1D periodic noise in −1…1 (sum of sines).
    static func periodicNoise(seed: UInt64, octaves: Int = 3) -> (Float) -> Float {
        var rng = SplitMix64(seed: seed)
        let terms: [(Float, Float, Float)] = (0..<octaves).map { i in
            (Float(i * 2 + 2), Float.random(in: 0...(2 * .pi), using: &rng), 1 / Float(i + 1))
        }
        let norm = terms.reduce(0) { $0 + $1.2 }
        return { x in terms.reduce(0) { $0 + $1.2 * sin($1.0 * x + $1.1) } / norm }
    }
}
