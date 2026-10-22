import CoreGraphics
import Foundation
import RealityKit
import simd
import UIKit

/// The studio (VISUAL-TARGET §3.3–3.6): a procedural HDRI for image-based light, the seamless cyclorama
/// with its per-object gel wall, and baked gaussian decals for contact shadows / AO.
///
/// LIVE HDRI PATH: 8-bit sRGB fallback (§3.3.1) — every radiance is divided by 5 (key = 1.0) and the IBL
/// `intensityExponent` is raised by +2.3 (see `SceneStyle.iblExponent`). Float CGImages are unverified in the simulator.
/// Carries a CGImage across the detached-task boundary (CGImage is immutable).
struct ImageBox: @unchecked Sendable {
    let image: CGImage?
}

enum StudioEnvironment {
    static let hdriWidth = 512
    static let hdriHeight = 256

    // MARK: - HDRI recipe (§3.3.3)

    private struct Shape {
        var azimuth: Float   // degrees
        var elevation: Float // degrees
        var width: Float     // degrees
        var height: Float    // degrees
        var value: Float
        var colour: SIMD3<Float>
        var replace: Bool
        var feather: Float = 4
    }

    private static let shapes: [Shape] = [
        Shape(azimuth: -40, elevation: 45, width: 55, height: 40, value: 5.0, colour: [1.00, 0.98, 0.95], replace: false), // key
        Shape(azimuth: 0, elevation: 75, width: 70, height: 12, value: 2.2, colour: [1, 1, 1], replace: false),            // top strip
        Shape(azimuth: 45, elevation: 25, width: 26, height: 45, value: 1.2, colour: [0.94, 0.97, 1.00], replace: false),  // fill card
        Shape(azimuth: -135, elevation: 10, width: 14, height: 80, value: 6.0, colour: [1.00, 0.98, 0.96], replace: false), // rim L
        Shape(azimuth: 135, elevation: 10, width: 14, height: 80, value: 6.0, colour: [1.00, 0.98, 0.96], replace: false),  // rim R
        Shape(azimuth: 15, elevation: 6, width: 35, height: 20, value: 1.0, colour: [1.00, 0.97, 0.93], replace: false),    // front card
        Shape(azimuth: 0, elevation: -25, width: 80, height: 25, value: 0.8, colour: [1.00, 0.92, 0.80], replace: false),   // floor bounce
        Shape(azimuth: -70, elevation: 10, width: 22, height: 50, value: 0.03, colour: [1, 1, 1], replace: true),           // flag L
        Shape(azimuth: 70, elevation: 10, width: 22, height: 50, value: 0.03, colour: [1, 1, 1], replace: true),            // flag R
        Shape(azimuth: 180, elevation: 20, width: 90, height: 40, value: 0.55, colour: [0.95, 0.94, 0.92], replace: true, feather: 20),  // back wall
    ]

    private static let gradientStops: [(phi: Float, value: Float, colour: SIMD3<Float>)] = [
        (-90, 0.30, [0.95, 0.86, 0.74]),
        (-5, 0.48, [0.98, 0.90, 0.78]),
        (5, 0.62, [0.98, 0.93, 0.86]),
        (35, 0.78, [1.00, 0.96, 0.90]),
        (90, 0.95, [1.00, 0.97, 0.92]),
    ]

    static func direction(azimuth λ: Float, elevation φ: Float) -> SIMD3<Float> {
        SIMD3(sin(λ) * cos(φ), sin(φ), cos(λ) * cos(φ))
    }

    /// Linear radiance for one direction (unit vector).
    static func radiance(_ d: SIMD3<Float>, baseAt phiDegrees: Float) -> SIMD3<Float> {
        var rad = baseGradient(phiDegrees)
        for frame in frames {
            let shape = frame.shape
            let mask = shapeMask(frame, d)
            guard mask > 0 else { continue }
            let light = shape.colour * shape.value
            rad = shape.replace ? rad + (light - rad) * mask : rad + light * mask
        }
        return rad
    }

    private static func baseGradient(_ phi: Float) -> SIMD3<Float> {
        let stops = gradientStops
        if phi <= stops[0].phi { return stops[0].colour * stops[0].value }
        for i in 0..<(stops.count - 1) where phi <= stops[i + 1].phi {
            let a = stops[i], b = stops[i + 1]
            var t = (phi - a.phi) / (b.phi - a.phi)
            t = t * t * (3 - 2 * t)
            let ca = a.colour * a.value, cb = b.colour * b.value
            return ca + (cb - ca) * t
        }
        let last = stops[stops.count - 1]
        return last.colour * last.value
    }

    /// A shape with its tangent frame precomputed (centre, east, north, angular cut-off).
    private struct Frame {
        var shape: Shape
        var centre: SIMD3<Float>
        var east: SIMD3<Float>
        var north: SIMD3<Float>
        var cosLimit: Float
    }

    private static let frames: [Frame] = shapes.map { s in
        let λ = s.azimuth * .pi / 180, φ = s.elevation * .pi / 180
        let c = direction(azimuth: λ, elevation: φ)
        let east = SIMD3<Float>(cos(λ), 0, -sin(λ))
        let halfDiag = (s.width * s.width + s.height * s.height).squareRoot() * 0.5 + max(6, s.feather)
        return Frame(shape: s, centre: c, east: east, north: simd_cross(c, east), cosLimit: cos(min(halfDiag, 89) * .pi / 180))
    }

    private static func shapeMask(_ f: Frame, _ d: SIMD3<Float>) -> Float {
        let s = f.shape
        let cosAngle = simd_dot(d, f.centre)
        guard cosAngle > f.cosLimit else { return 0 }
        let east = f.east, north = f.north
        let x = atan2(simd_dot(d, east), cosAngle) * 180 / .pi
        let y = atan2(simd_dot(d, north), cosAngle) * 180 / .pi
        // Rounded rectangle SDF in degrees, corner radius 6°, feather 4°.
        let r: Float = 6
        let qx = abs(x) - (s.width / 2 - r), qy = abs(y) - (s.height / 2 - r)
        let outside = SIMD2<Float>(max(qx, 0), max(qy, 0))
        let dist = simd_length(outside) + min(max(qx, qy), 0) - r
        let feather = s.feather
        let t = clamp((dist + feather / 2) / feather, 0, 1)
        return 1 - t * t * (3 - 2 * t)
    }

    /// Paints the equirectangular HDRI as 8-bit sRGB (radiance / 5). Pure; safe off the main thread.
    static func hdriImage(width: Int = hdriWidth, height: Int = hdriHeight, seed: UInt64 = 0x57D10) -> CGImage? {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        var rng = SplitMix64(seed: seed)
        for row in 0..<height {
            let v = (Float(row) + 0.5) / Float(height)
            let phi = (0.5 - v) * .pi
            let phiDegrees = phi * 180 / .pi
            for col in 0..<width {
                let u = (Float(col) + 0.5) / Float(width)
                let lambda = (u - 0.5) * 2 * .pi
                let d = direction(azimuth: lambda, elevation: phi)
                let rad = radiance(d, baseAt: phiDegrees) / 5
                let dither = (Float(rng.next() % 1024) / 1023 - 0.5) / 255
                let i = (row * width + col) * 4
                pixels[i] = encode(rad.x + dither)
                pixels[i + 1] = encode(rad.y + dither)
                pixels[i + 2] = encode(rad.z + dither)
            }
        }
        return makeImage(pixels, width: width, height: height)
    }

    /// Linear → 8-bit sRGB.
    static func encode(_ linear: Float) -> UInt8 {
        let x = clamp(linear, 0, 1)
        let s = x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055
        return UInt8(clamp(s * 255 + 0.5, 0, 255))
    }

    static func makeImage(_ pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// The same recipe painted with CoreGraphics (native speed, a few ms even in Debug builds): base gradient by
    /// elevation, then each shape as a blurred rounded rectangle in lat-long space (additive shapes in plus-lighter,
    /// flags/back wall replace). Widths are divided by cos(elevation) so high shapes keep their angular size.
    /// This is the runtime path; `hdriImage` is the exact per-pixel reference (tests).
    static func hdriImageFast(width: Int = hdriWidth, height: Int = hdriHeight) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let W = CGFloat(width), H = CGFloat(height)
        context.translateBy(x: 0, y: H)
        context.scaleBy(x: 1, y: -1) // y = 0 is the zenith row
        func cgColor(_ linear: SIMD3<Float>) -> CGColor {
            let c = linear / 5
            return CGColor(colorSpace: space, components: [CGFloat(encode(c.x)) / 255, CGFloat(encode(c.y)) / 255,
                                                           CGFloat(encode(c.z)) / 255, 1]) ?? CGColor(gray: 1, alpha: 1)
        }
        // Base gradient (stops top → bottom).
        let stops = gradientStops.reversed()
        let colors = stops.map { cgColor($0.colour * $0.value) } as CFArray
        let locations = stops.map { CGFloat(0.5 - $0.phi / 180) }
        if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: locations) {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: H), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        for s in shapes {
            let colour = cgColor(s.colour * s.value)
            let stretch = 1 / max(CGFloat(cos(s.elevation * .pi / 180)), 0.3)
            let w = min(W * CGFloat(s.width) / 360 * stretch, W)
            let h = H * CGFloat(s.height) / 180
            let cx = W * CGFloat(0.5 + s.azimuth / 360), cy = H * CGFloat(0.5 - s.elevation / 180)
            let corner = min(H * 6 / 180, w / 2, h / 2)
            let blur = H * CGFloat(s.feather) / 180
            context.saveGState()
            context.setBlendMode(s.replace ? .normal : .plusLighter)
            context.setFillColor(colour)
            context.setShadow(offset: .zero, blur: blur, color: colour)
            // Draw wrapped copies so shapes crossing the ±180° seam stay continuous.
            for shift in [-W, 0, W] {
                let rect = CGRect(x: cx + shift - w / 2 + blur / 2, y: cy - h / 2 + blur / 2,
                                  width: max(w - blur, 1), height: max(h - blur, 1))
                guard rect.maxX > -blur, rect.minX < W + blur else { continue }
                context.addPath(CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil))
                context.fillPath()
            }
            context.restoreGState()
        }
        return context.makeImage()
    }

    /// Builds the IBL entity (an `ImageBasedLightComponent` holder). The HDRI is painted off the main thread;
    /// the first frames render with the key and rim lights only.
    @MainActor
    static func makeLight(exponent: Float) async -> Entity? {
        let box = await Task.detached(priority: .userInitiated) { () -> ImageBox in
            ImageBox(image: SceneTrace.measure("hdri image") { hdriImageFast() })
        }.value
        guard let image = box.image else {
            SceneTrace.mark("hdri image FAILED")
            return nil
        }
        SceneTrace.mark("environment resource start")
        let environment: EnvironmentResource?
        if #available(iOS 27.0, *) {
            // Fast sampling and a small specular cube: the studio is soft, and this is on the startup path.
            environment = try? await EnvironmentResource(equirectangular: image,
                                                         options: .init(samplingQuality: .fast, specularCubeDimension: 128))
        } else {
            environment = try? await EnvironmentResource(equirectangular: image, withName: "squish.studio")
        }
        guard let environment else {
            SceneTrace.mark("environment resource FAILED")
            return nil
        }
        SceneTrace.mark("environment resource done")
        let holder = Entity()
        var ibl = ImageBasedLightComponent(source: .single(environment), intensityExponent: exponent)
        ibl.inheritsRotation = true
        holder.components.set(ibl)
        return holder
    }

    // MARK: - Cyclorama (§3.4)

    static let floorY: Float = -0.108
    static let floorFrontZ: Float = 0.50
    static let floorBackZ: Float = -0.30
    static let bendRadius: Float = 0.25
    static let wallTop: Float = 1.20
    static let halfWidth: Float = 0.90

    /// Profile point and arc length for a parameter along the sweep (front floor → bend → wall top).
    static func sweepPoint(arc s: Float) -> (y: Float, z: Float, normal: SIMD2<Float>) {
        let floorLength = floorFrontZ - floorBackZ
        let bendLength = Float.pi / 2 * bendRadius
        if s <= floorLength {
            return (floorY, floorFrontZ - s, SIMD2(1, 0))
        }
        if s <= floorLength + bendLength {
            let a = (s - floorLength) / bendRadius // 0 … π/2
            let cy = floorY + bendRadius, cz = floorBackZ
            let y = cy - bendRadius * cos(a)
            let z = cz - bendRadius * sin(a)
            // Normal points toward the bend centre (into the studio).
            return (y, z, simd_normalize(SIMD2(cy - y, cz - z)))
        }
        let up = s - floorLength - bendLength
        return (floorY + bendRadius + up, floorBackZ - bendRadius, SIMD2(0, 1))
    }

    static var sweepLength: Float {
        (floorFrontZ - floorBackZ) + .pi / 2 * bendRadius + (wallTop - (floorY + bendRadius))
    }

    @MainActor
    static func sweepMesh() -> MeshResource? {
        let along = 64, across = 4
        let total = sweepLength
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        // Non-uniform sampling: dense through the bend.
        let floorLength = floorFrontZ - floorBackZ
        let bendLength = Float.pi / 2 * bendRadius
        var arcs: [Float] = []
        for k in 0...20 { arcs.append(floorLength * Float(k) / 20) }
        for k in 1...24 { arcs.append(floorLength + bendLength * Float(k) / 24) }
        let remaining = along - arcs.count + 1
        let wallLength = total - floorLength - bendLength
        for k in 1...max(remaining, 1) { arcs.append(floorLength + bendLength + wallLength * Float(k) / Float(max(remaining, 1))) }
        for s in arcs {
            let p = sweepPoint(arc: s)
            for j in 0...across {
                let x = -halfWidth + 2 * halfWidth * Float(j) / Float(across)
                positions.append(SIMD3(x, p.y, p.z))
                // Profile normal (n.x = y component, n.y = z component in the YZ plane).
                normals.append(SIMD3(0, p.normal.x, p.normal.y))
                uvs.append(SIMD2((x + halfWidth) / (2 * halfWidth), s / total))
            }
        }
        let rowLength = across + 1
        for i in 0..<(arcs.count - 1) {
            for j in 0..<across {
                let a = UInt32(i * rowLength + j), b = a + 1
                let c = UInt32((i + 1) * rowLength + j), d = c + 1
                indices.append(contentsOf: [a, c, b, b, c, d])
            }
        }
        // Front faces toward the studio (CCW around the normal).
        var mesh = MeshData(positions: positions, normals: normals, indices: indices)
        mesh.orientToNormals()
        var descriptor = MeshDescriptor(name: "sweep")
        descriptor.positions = MeshBuffers.Positions(mesh.positions)
        descriptor.normals = MeshBuffers.Normals(mesh.normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(mesh.indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    /// The gel (wall-top) colour for an object (§3.4 table).
    static func gel(for kind: ObjectKind, golden: Bool) -> UInt32 {
        if golden { return 0xF3E6C4 }
        switch kind {
        case .bubbleWrap: return 0xF6E3D3
        case .rubberDuck: return 0xDDE3F3
        case .jelly: return 0xD9EEE4
        case .crayon: return 0xF7DFCF
        case .egg: return 0xD8E8F2
        case .cakeSlice: return 0xE1EDD6
        case .sodaCan: return 0xE8DDF0
        case .gummyBear: return 0xD5ECEC
        case .glassBottle: return 0xF4DDDA
        case .unsquishable: return 0xF5EACB
        }
    }

    static func rgb(_ hex: UInt32) -> SIMD3<Float> {
        SIMD3(Float((hex >> 16) & 0xFF), Float((hex >> 8) & 0xFF), Float(hex & 0xFF)) / 255
    }

    /// Bakes the sweep texture (sRGB values written directly: the material is unlit with no tone map).
    /// Row 0 is v = 1 (wall top) when `flipV` is false. Pure; safe off the main thread.
    /// Separable: every term is a row factor times a column factor, so the inner loop is a few multiply-adds
    /// (Debug builds run this at startup; it used to be the slowest per-pixel loop in the app).
    static func sweepImage(gel: UInt32, golden: Bool, width: Int = 256, height: Int = 256, flipV: Bool = false,
                           seed: UInt64 = 0x5EE9) -> CGImage? {
        let total = sweepLength
        let floorNear = rgb(0xF1E9DC), floorPool = rgb(0xF8F3EA), backFloor = rgb(0xEEE5D7)
        let bend = rgb(0xEAE0D0), wallBase = rgb(0xEDE5D8), wallTop = rgb(gel)
        let ink = rgb(0x3B2F25)
        // Column factors.
        var vignette = [Float](repeating: 1, count: width)
        var poolX = [Float](repeating: 0, count: width)
        var shadowX = [Float](repeating: 0, count: width)
        var glowX = [Float](repeating: 0, count: width)
        let sigma: Float = 0.12 / 0.15
        for col in 0..<width {
            let u = (Float(col) + 0.5) / Float(width)
            let x = -halfWidth + 2 * halfWidth * u
            let h = (u - 0.5) / 0.5
            vignette[col] = 1 - 0.06 * h * h
            poolX[col] = exp(-(x * x) / (2 * 0.16 * 0.16))
            let dx = (x - 0.10) / 0.15
            shadowX[col] = exp(-(dx * dx) / (2 * sigma * sigma))
            glowX[col] = exp(-(x * x) / (2 * 0.2 * 0.2))
        }
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        var rng = SplitMix64(seed: seed)
        pixels.withUnsafeMutableBufferPointer { buffer in
            for row in 0..<height {
                let vImage = (Float(row) + 0.5) / Float(height)
                let v = flipV ? vImage : 1 - vImage
                let p = sweepPoint(arc: v * total)
                // Row terms: c(col) = base + (target − base)·poolX·poolY, then darkened toward ink·shadowX·shadowY.
                var base: SIMD3<Float>
                var poolTarget = SIMD3<Float>.zero
                var poolY: Float = 0
                var shadowY: Float = 0
                var glowY: Float = 0
                if p.y <= floorY + 1e-4 {
                    let back = smooth(clamp((-p.z - 0.05) / 0.2, 0, 1))
                    let near = smooth(clamp((p.z - 0.12) / 0.3, 0, 1))
                    base = (floorNear + (backFloor - floorNear) * back) * (1 - 0.035 * near)
                    poolTarget = floorPool * (1 - 0.035 * near)
                    poolY = exp(-(p.z * p.z) / (2 * 0.14 * 0.14))
                } else if p.z > floorBackZ - bendRadius + 1e-4 && p.y < floorY + bendRadius {
                    let t = smooth(clamp((p.y - floorY) / bendRadius, 0, 1))
                    let c = backFloor + (bend - backFloor) * min(t * 2, 1)
                    base = c + (wallBase - c) * max(t * 2 - 1, 0)
                } else {
                    let t = smooth(clamp((p.y - (floorY + bendRadius) - 0.05) / 0.55, 0, 1))
                    base = wallBase + (wallTop - wallBase) * t
                    let dy = (p.y - 0.20) / 0.21
                    shadowY = 0.07 * exp(-(dy * dy) / (2 * sigma * sigma))
                    if golden { glowY = 0.05 * exp(-((p.y - 0.12) * (p.y - 0.12)) / (2 * 0.25 * 0.25)) }
                }
                let poolDelta = poolTarget - base
                let inkDelta = ink - base
                for col in 0..<width {
                    var c = base
                    if poolY > 0 { c += poolDelta * (poolX[col] * poolY) }
                    if glowY > 0 { c *= 1 + glowX[col] * glowY }
                    if shadowY > 0 { c += inkDelta * (shadowX[col] * shadowY) }
                    c *= vignette[col] * 255
                    let i = (row * width + col) * 4
                    let noise = rng.next()
                    buffer[i] = UInt8(clamp(c.x + Float(Int(noise % 3) - 1) + 0.5, 0, 255))
                    buffer[i + 1] = UInt8(clamp(c.y + Float(Int((noise >> 8) % 3) - 1) + 0.5, 0, 255))
                    buffer[i + 2] = UInt8(clamp(c.z + Float(Int((noise >> 16) % 3) - 1) + 0.5, 0, 255))
                }
            }
        }
        return makeImage(pixels, width: width, height: height)
    }

    private static func smooth(_ t: Float) -> Float { t * t * (3 - 2 * t) }

    // MARK: - Decals (§3.6)

    /// Radial gaussian in shadow ink, alpha in the texture. `sigma` is a fraction of the half-size.
    static func gaussianImage(sigma: Float, size: Int = 128) -> CGImage? {
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let ink = rgb(0x3B2F25)
        for row in 0..<size {
            for col in 0..<size {
                let x = (Float(col) + 0.5) / Float(size) * 2 - 1
                let y = (Float(row) + 0.5) / Float(size) * 2 - 1
                let r2 = x * x + y * y
                var a = exp(-r2 / (2 * sigma * sigma))
                a *= clamp((1 - r2.squareRoot()) / 0.15, 0, 1) // reach zero before the quad edge
                let i = (row * size + col) * 4
                // Premultiplied.
                pixels[i] = UInt8(clamp(ink.x * a * 255, 0, 255))
                pixels[i + 1] = UInt8(clamp(ink.y * a * 255, 0, 255))
                pixels[i + 2] = UInt8(clamp(ink.z * a * 255, 0, 255))
                pixels[i + 3] = UInt8(clamp(a * 255, 0, 255))
            }
        }
        return makeImage(pixels, width: size, height: size)
    }

    /// Async texture creation (iOS 18 `TextureResource(image:withName:options:) async throws`), so the upload never
    /// blocks the main actor — the sync initializer stalled main for ~4 s on CI while the IBL was being prefiltered.
    @MainActor
    static func textureAsync(_ image: CGImage?, name: String) async -> TextureResource? {
        guard let image else { return nil }
        return try? await TextureResource(image: image, withName: name, options: .init(semantic: .color))
    }

    @MainActor
    static func texture(_ image: CGImage?, name: String) -> TextureResource? {
        guard let image else { return nil }
        return try? TextureResource(image: image, withName: name, options: .init(semantic: .color))
    }
}
