import Foundation
import simd

/// Signed-distance blobs with smooth unions (duck, gummy bear; VISUAL-TARGET §5.2/§5.8), meshed by
/// sphere-tracing rays inward from a bounding sphere around a centre point (outermost surface along each ray).
/// That's exact for star-shaped blobs and skins over small concavities, which smooth unions (k ≈ 8 mm) avoid anyway.
/// Normals come from the SDF gradient, so silhouettes and highlights are perfectly smooth.
struct SDFBlob {
    struct Part {
        var centre: SIMD3<Float>
        var radii: SIMD3<Float>
        /// Rotation of the ellipsoid (applied to the part's local frame).
        var rotation = simd_quatf(angle: 0, axis: [0, 1, 0])
        /// Smooth-union radius with everything before it.
        var k: Float = 0.008
        var rotates = false
    }

    var parts: [Part] = []
    /// Flat base: intersect with y ≥ floor, rounded by `floorRound`.
    var floor: Float? = 0.002
    var floorRound: Float = 0.002
    /// Optional half-space clip: keep points with dot(p − clipPoint, clipNormal) ≤ 0 (cut faces for split halves).
    var clipNormal: SIMD3<Float>?
    var clipPoint = SIMD3<Float>.zero
    var clipRound: Float = 0.0015

    mutating func add(_ centre: SIMD3<Float>, _ radii: SIMD3<Float>, k: Float = 0.008,
                      rotation: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0])) {
        // Stored as the inverse (what `distance` needs), and only when it actually rotates.
        let inverse = rotation.inverse
        parts.append(Part(centre: centre, radii: radii, rotation: inverse, k: k,
                          rotates: abs(rotation.angle) > 1e-4))
    }

    mutating func add(_ centre: SIMD3<Float>, radius: Float, k: Float = 0.008) {
        add(centre, SIMD3(repeating: radius), k: k)
    }

    static func ellipsoid(_ p: SIMD3<Float>, _ r: SIMD3<Float>) -> Float {
        let k0 = simd_length(p / r)
        let k1 = simd_length(p / (r * r))
        guard k1 > 1e-9 else { return -min(r.x, min(r.y, r.z)) }
        return k0 * (k0 - 1) / k1
    }

    static func smin(_ a: Float, _ b: Float, _ k: Float) -> Float {
        guard k > 0 else { return min(a, b) }
        let h = max(k - abs(a - b), 0) / k
        return min(a, b) - h * h * k * 0.25
    }

    static func smax(_ a: Float, _ b: Float, _ k: Float) -> Float {
        -smin(-a, -b, k)
    }

    func distance(_ p: SIMD3<Float>) -> Float {
        var d: Float = 1
        // Indexed loop over the raw buffer: this is the hot path of SDF meshing (Debug builds run it at startup).
        parts.withUnsafeBufferPointer { buffer in
            for i in 0..<buffer.count {
                let part = buffer[i]
                let offset = p - part.centre
                let local = part.rotates ? part.rotation.act(offset) : offset
                let e = Self.ellipsoid(local, part.radii)
                d = i == 0 ? e : Self.smin(d, e, part.k)
            }
        }
        if let floor {
            d = Self.smax(d, floor - p.y, floorRound)
        }
        if let n = clipNormal {
            d = Self.smax(d, simd_dot(p - clipPoint, n), clipRound)
        }
        return d
    }

    func gradient(_ p: SIMD3<Float>) -> SIMD3<Float> {
        // Tetrahedral differences: 4 evaluations instead of 6.
        let e: Float = 0.0004
        let k0 = SIMD3<Float>(1, -1, -1), k1 = SIMD3<Float>(-1, -1, 1), k2 = SIMD3<Float>(-1, 1, -1), k3 = SIMD3<Float>(1, 1, 1)
        let g0: SIMD3<Float> = k0 * distance(p + k0 * e)
        let g1: SIMD3<Float> = k1 * distance(p + k1 * e)
        let g2: SIMD3<Float> = k2 * distance(p + k2 * e)
        let g3: SIMD3<Float> = k3 * distance(p + k3 * e)
        let g: SIMD3<Float> = (g0 + g1) + (g2 + g3)
        let length = simd_length(g)
        return length > 1e-9 ? g / length : SIMD3(0, 1, 0)
    }

    /// Meshes the blob as a lat-long sphere of rays from `centre` (which must be inside the blob).
    /// With `uvs`, the mesh carries spherical texture coordinates about `centre`: the seam column and the poles are
    /// duplicated (u 0…1 round from `seamAngle`, the ray angle about +Y measured from +X toward +Z; v 1 at the top pole,
    /// 0 at the bottom), so painted detail and micro-texture can be mapped onto the blob.
    func mesh(centre: SIMD3<Float>, reach: Float, rings: Int = 40, segments: Int = 56, uvs: Bool = false,
              seamAngle: Float = .pi) -> MeshData {
        if uvs { return uvMesh(centre: centre, reach: reach, rings: rings, segments: segments, seamAngle: seamAngle) }
        var mesh = MeshData()
        func surface(along dir: SIMD3<Float>) -> SIMD3<Float> {
            var t = reach
            var outside = reach
            var steps = 0
            while steps < 64 {
                let d = distance(centre + dir * t)
                if d < 0 { break }
                outside = t
                t -= max(d * 0.8, 0.0004)
                steps += 1
                if t <= 0 { t = 0; break }
            }
            // Bisect between the last outside point and the first inside point.
            var lo = t, hi = outside
            for _ in 0..<8 {
                let mid = (lo + hi) * 0.5
                if distance(centre + dir * mid) < 0 { lo = mid } else { hi = mid }
            }
            return centre + dir * ((lo + hi) * 0.5)
        }
        let top = surface(along: SIMD3(0, 1, 0))
        _ = mesh.addVertex(top, gradient(top))
        for i in 1..<rings {
            let phi = Float.pi * Float(i) / Float(rings) // from +Y down
            for j in 0..<segments {
                let theta = 2 * Float.pi * Float(j) / Float(segments)
                let dir = SIMD3<Float>(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
                let p = surface(along: dir)
                _ = mesh.addVertex(p, gradient(p))
            }
        }
        let bottom = surface(along: SIMD3(0, -1, 0))
        let bottomIndex = mesh.addVertex(bottom, gradient(bottom))
        func ring(_ i: Int, _ j: Int) -> Int { 1 + (i - 1) * segments + (j % segments) }
        for j in 0..<segments {
            mesh.addTriangle(0, ring(1, j), ring(1, j + 1))
        }
        if rings > 2 {
            for i in 1..<(rings - 1) {
                for j in 0..<segments {
                    mesh.addTriangle(ring(i, j), ring(i + 1, j), ring(i + 1, j + 1))
                    mesh.addTriangle(ring(i, j), ring(i + 1, j + 1), ring(i, j + 1))
                }
            }
        }
        for j in 0..<segments {
            mesh.addTriangle(bottomIndex, ring(rings - 1, j + 1), ring(rings - 1, j))
        }
        mesh.orientToNormals()
        return mesh
    }

    /// The outermost surface point along `dir` from `centre` (sphere tracing inward from `reach`, then bisection).
    func surfacePoint(centre: SIMD3<Float>, along dir: SIMD3<Float>, reach: Float) -> SIMD3<Float> {
        var t = reach
        var outside = reach
        var steps = 0
        while steps < 64 {
            let d = distance(centre + dir * t)
            if d < 0 { break }
            outside = t
            t -= max(d * 0.8, 0.0004)
            steps += 1
            if t <= 0 { t = 0; break }
        }
        var lo = t, hi = outside
        for _ in 0..<8 {
            let mid = (lo + hi) * 0.5
            if distance(centre + dir * mid) < 0 { lo = mid } else { hi = mid }
        }
        return centre + dir * ((lo + hi) * 0.5)
    }

    /// The spherical texture coordinate (u, v) of the ray direction `dir` (as `mesh(uvs: true)` lays them out).
    static func sphericalUV(_ dir: SIMD3<Float>, seamAngle: Float = .pi) -> SIMD2<Float> {
        let d = simd_normalize(dir)
        let phi = acos(clamp(d.y, -1, 1))
        var u = (atan2(d.z, d.x) - seamAngle) / (2 * .pi)
        u -= u.rounded(.down)
        return SIMD2(u, 1 - phi / .pi)
    }

    private func uvMesh(centre: SIMD3<Float>, reach: Float, rings: Int, segments: Int, seamAngle: Float) -> MeshData {
        var mesh = MeshData()
        let top = surfacePoint(centre: centre, along: SIMD3(0, 1, 0), reach: reach)
        let bottom = surfacePoint(centre: centre, along: SIMD3(0, -1, 0), reach: reach)
        let topNormal = gradient(top), bottomNormal = gradient(bottom)
        var grid: [[Int]] = []
        for i in 0...rings {
            let phi = Float.pi * Float(i) / Float(rings) // from +Y down
            var row: [Int] = []
            var ringPoints: [(SIMD3<Float>, SIMD3<Float>)] = []
            if i > 0 && i < rings {
                for j in 0..<segments {
                    let theta = seamAngle + 2 * Float.pi * Float(j) / Float(segments)
                    let dir = SIMD3<Float>(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
                    let p = surfacePoint(centre: centre, along: dir, reach: reach)
                    ringPoints.append((p, gradient(p)))
                }
            }
            for j in 0...segments {
                let point: (SIMD3<Float>, SIMD3<Float>)
                if i == 0 {
                    point = (top, topNormal)
                } else if i == rings {
                    point = (bottom, bottomNormal)
                } else {
                    point = ringPoints[j % segments]
                }
                row.append(mesh.addVertex(point.0, point.1))
                mesh.uvs.append(SIMD2(Float(j) / Float(segments), 1 - Float(i) / Float(rings)))
            }
            grid.append(row)
        }
        // Quad (a b c d) between rings i and i + 1; at the top pole a and d coincide, at the bottom b and c.
        for i in 0..<rings {
            for j in 0..<segments {
                let a = grid[i][j], b = grid[i + 1][j], c = grid[i + 1][j + 1], d = grid[i][j + 1]
                if i < rings - 1 { mesh.addTriangle(a, b, c) }
                if i > 0 { mesh.addTriangle(a, c, d) }
            }
        }
        mesh.orientToNormals()
        return mesh
    }
}
