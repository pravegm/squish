import Foundation
import Metal
import RealityKit
import simd

/// A CPU-deformed mesh: keeps the rest positions, applies a per-vertex deform function, recomputes smooth normals
/// across the whole mesh (so material seams stay invisible) and uploads in place.
///
/// Upload path: `LowLevelMesh` (iOS 18) updated with `withUnsafeMutableBytes`. If the build sets the
/// `SQUISH_NO_LOWLEVELMESH` compilation condition, or a `LowLevelMesh` can't be created at runtime, it falls back to
/// regenerating a `MeshResource` from a `MeshDescriptor` (slower, still fine for one hero mesh).
/// Keep this to 1–2 live instances (bible §9 CPU budget); call `update` only when the deformation changed.
@MainActor
final class DeformableMesh {
    /// Parent of one ModelEntity per material slot.
    let entity = Entity()
    let rest: MeshData
    private(set) var current: MeshData

    private struct Group {
        let slot: Int
        let model: ModelEntity
        let sourceVertex: [Int]
        let indices: [UInt32]
        #if !SQUISH_NO_LOWLEVELMESH
        var lowLevel: LowLevelMesh?
        #endif
    }

    private var groups: [Group] = []
    /// Bounds padding so spread/squashed shapes aren't culled.
    private let boundsMin: SIMD3<Float>
    private let boundsMax: SIMD3<Float>

    init(_ data: MeshData, materials: [any Material], maxSpread: Float = 2.5) {
        rest = data
        current = data
        let b = data.bounds()
        let half = simd_max(simd_abs(b.min), simd_abs(b.max))
        let reach = max(half.x, half.z) * maxSpread + 0.01
        boundsMin = SIMD3(-reach, min(b.min.y, 0) - 0.01, -reach)
        boundsMax = SIMD3(reach, max(b.max.y, 0.01) + 0.01, reach)

        for part in data.splitByMaterial() {
            let material = materials[min(part.slot, materials.count - 1)]
            #if !SQUISH_NO_LOWLEVELMESH
            if let low = Self.makeLowLevel(part.mesh, boundsMin: boundsMin, boundsMax: boundsMax),
               let resource = try? MeshResource(from: low) {
                let model = ModelEntity(mesh: resource, materials: [material])
                entity.addChild(model)
                groups.append(Group(slot: part.slot, model: model, sourceVertex: part.sourceVertex,
                                    indices: part.mesh.indices, lowLevel: low))
                continue
            }
            #endif
            let resource = part.mesh.resource() ?? MeshResource.generateSphere(radius: 0.001)
            let model = ModelEntity(mesh: resource, materials: [material])
            entity.addChild(model)
            #if !SQUISH_NO_LOWLEVELMESH
            groups.append(Group(slot: part.slot, model: model, sourceVertex: part.sourceVertex,
                                indices: part.mesh.indices, lowLevel: nil))
            #else
            groups.append(Group(slot: part.slot, model: model, sourceVertex: part.sourceVertex,
                                indices: part.mesh.indices))
            #endif
        }
    }

    /// Deforms every rest vertex with `deform`, recomputes normals and uploads.
    func update(_ deform: (SIMD3<Float>) -> SIMD3<Float>) {
        for i in rest.positions.indices {
            current.positions[i] = deform(rest.positions[i])
        }
        MeshKit.computeNormals(positions: current.positions, indices: rest.indices, into: &current.normals)
        upload()
    }

    /// Resets to the rest shape.
    func reset() {
        current = rest
        upload()
    }

    private func upload() {
        for group in groups {
            #if !SQUISH_NO_LOWLEVELMESH
            if let low = group.lowLevel {
                let positions = current.positions
                let normals = current.normals
                let source = group.sourceVertex
                low.withUnsafeMutableBytes(bufferIndex: 0) { raw in
                    let vertices = raw.bindMemory(to: DeformVertex.self)
                    for (k, v) in source.enumerated() where k < vertices.count {
                        vertices[k] = DeformVertex(position: positions[v], normal: normals[v])
                    }
                }
                continue
            }
            #endif
            var sub = MeshData()
            sub.positions = group.sourceVertex.map { current.positions[$0] }
            sub.normals = group.sourceVertex.map { current.normals[$0] }
            sub.indices = group.indices
            if let resource = sub.resource() {
                group.model.model?.mesh = resource
            }
        }
    }

    #if !SQUISH_NO_LOWLEVELMESH
    private static func makeLowLevel(_ mesh: MeshData, boundsMin: SIMD3<Float>, boundsMax: SIMD3<Float>) -> LowLevelMesh? {
        guard mesh.isValid else { return nil }
        var descriptor = LowLevelMesh.Descriptor()
        descriptor.vertexAttributes = [
            LowLevelMesh.Attribute(semantic: .position, format: .float3, offset: 0),
            LowLevelMesh.Attribute(semantic: .normal, format: .float3, offset: MemoryLayout<SIMD3<Float>>.stride),
        ]
        descriptor.vertexLayouts = [
            LowLevelMesh.Layout(bufferIndex: 0, bufferStride: MemoryLayout<DeformVertex>.stride),
        ]
        descriptor.vertexCapacity = mesh.positions.count
        descriptor.indexCapacity = mesh.indices.count
        descriptor.indexType = .uint32
        guard let low = try? LowLevelMesh(descriptor: descriptor) else { return nil }
        let positions = mesh.positions
        let normals = mesh.normals
        low.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            let vertices = raw.bindMemory(to: DeformVertex.self)
            for i in positions.indices where i < vertices.count {
                vertices[i] = DeformVertex(position: positions[i], normal: normals[i])
            }
        }
        let indices = mesh.indices
        low.withUnsafeMutableIndices { raw in
            let buffer = raw.bindMemory(to: UInt32.self)
            for i in indices.indices where i < buffer.count {
                buffer[i] = indices[i]
            }
        }
        low.parts.replaceAll([
            LowLevelMesh.Part(indexCount: indices.count, topology: .triangle,
                              bounds: BoundingBox(min: boundsMin, max: boundsMax)),
        ])
        return low
    }
    #endif
}

/// Interleaved vertex for `LowLevelMesh`: position at offset 0, normal at offset 16 (SIMD3<Float> stride), stride 32.
struct DeformVertex {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
}

/// Shared analytic deformations (research 03 §4 "the backbone").
enum Deform {
    /// Volume-preserving squash to height ratio `s` (0…1] about the Y axis, with a mid-height barrel bulge
    /// and a soft spread cap. `restHeight` is the undeformed top.
    static func squash(_ p: SIMD3<Float>, s: Float, restHeight: Float, bulge: Float = 0.35, maxSpread: Float = 2.2,
                       shear: SIMD2<Float> = .zero) -> SIMD3<Float> {
        let ratio = max(s, 0.02)
        let spread = min(1 / ratio.squareRoot(), maxSpread)
        let u = clamp(p.y / max(restHeight, 1e-5), 0, 1)
        let barrel = 1 + bulge * (1 - ratio) * sin(.pi * u)
        let k = spread * barrel
        let y = p.y * ratio
        // Shear (wobble) grows with height.
        return SIMD3(p.x * k + shear.x * u, y, p.z * k + shear.y * u)
    }

    /// Exponential approach (frame-rate independent): moves `value` toward `target` with half-life `halfLife` seconds.
    static func approach(_ value: Float, _ target: Float, halfLife: Float, dt: Float) -> Float {
        guard halfLife > 0 else { return target }
        let k = 1 - pow(0.5, dt / halfLife)
        return value + (target - value) * k
    }
}

/// Damped spring (ζ < 1 overshoots) for jiggle and elastic rebound; semi-implicit Euler with sub-steps.
struct JiggleSpring {
    var value: Float = 0
    var velocity: Float = 0
    var omega: Float = 26
    var zeta: Float = 0.4

    mutating func step(toward target: Float, dt: Float) {
        guard dt > 0 else { return }
        let steps = max(1, Int((dt / (1.0 / 240.0)).rounded(.up)))
        let h = dt / Float(steps)
        for _ in 0..<steps {
            let accel = -2 * zeta * omega * velocity - omega * omega * (value - target)
            velocity += accel * h
            value += velocity * h
        }
    }

    mutating func kick(_ impulse: Float) {
        velocity += impulse
    }
}
