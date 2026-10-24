import CoreGraphics
import CoreText
import Foundation
import Metal
import RealityKit
import simd
import UIKit

// Procedural surface detail (founder fidelity pass, 24 Oct 2026; 3D-art round the same day): colour, normal and
// roughness images drawn once per session with Core Graphics and plain loops *off the main actor*, uploaded as
// mipmapped textures and cached (`SurfaceDetail`). Nothing here runs per frame: an object swaps a material when its
// maps land, and a crushed look is a one-off material swap at a beat.
//
// Conventions: every builder is nonisolated and pure (seeded), images are 8-bit sRGB-ish RGBA, row 0 is the image's
// top, which is texture v = 1 (MeshData's convention). Fields (`SurfaceField`) are row-major Float images in the same
// orientation; `normalImage` turns one into a tangent-space normal map (wrapping, so tileable fields stay seamless).

/// Tileable value noise on a `periodX × periodY` lattice (precomputed, so sampling is four reads and a smoothstep).
struct TileNoise: Sendable {
    let periodX: Int
    let periodY: Int
    private let lattice: [Float]

    init(periodX: Int, periodY: Int, seed: UInt64) {
        self.periodX = max(periodX, 1)
        self.periodY = max(periodY, 1)
        var rng = SplitMix64(seed: seed)
        lattice = (0..<(self.periodX * self.periodY)).map { _ in Float(rng.next() >> 40) / Float(1 << 24) }
    }

    init(period: Int, seed: UInt64) {
        self.init(periodX: period, periodY: period, seed: seed)
    }

    /// 0…1 at (u, v); u and v wrap every 1.
    func callAsFunction(_ u: Float, _ v: Float) -> Float {
        let fx = u * Float(periodX), fy = v * Float(periodY)
        let fx0 = fx.rounded(.down), fy0 = fy.rounded(.down)
        let tx = fx - fx0, ty = fy - fy0
        let ix = Int(fx0), iy = Int(fy0)
        let x0 = ((ix % periodX) + periodX) % periodX, y0 = ((iy % periodY) + periodY) % periodY
        let x1 = (x0 + 1) % periodX, y1 = (y0 + 1) % periodY
        let sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty)
        let a = lattice[y0 * periodX + x0], b = lattice[y0 * periodX + x1]
        let c = lattice[y1 * periodX + x0], d = lattice[y1 * periodX + x1]
        let top = a + (b - a) * sx
        let bottom = c + (d - c) * sx
        return top + (bottom - top) * sy
    }
}

/// Fractal tileable noise: `octaves` of `TileNoise`, each twice the frequency and `gain` the weight of the last. 0…1.
struct TileFBM: Sendable {
    private let layers: [TileNoise]
    private let weights: [Float]
    private let total: Float

    init(periodX: Int, periodY: Int, octaves: Int, seed: UInt64, gain: Float = 0.5) {
        var layers: [TileNoise] = []
        var weights: [Float] = []
        var w: Float = 1
        for o in 0..<max(octaves, 1) {
            let k = 1 << o
            layers.append(TileNoise(periodX: periodX * k, periodY: periodY * k, seed: seed &+ UInt64(o) &* 0x9E37_79B9))
            weights.append(w)
            w *= gain
        }
        self.layers = layers
        self.weights = weights
        total = weights.reduce(0, +)
    }

    init(period: Int, octaves: Int, seed: UInt64, gain: Float = 0.5) {
        self.init(periodX: period, periodY: period, octaves: octaves, seed: seed, gain: gain)
    }

    func callAsFunction(_ u: Float, _ v: Float) -> Float {
        var sum: Float = 0
        for i in layers.indices { sum += weights[i] * layers[i](u, v) }
        return sum / max(total, 1e-6)
    }
}

/// Tileable cellular (Worley) noise: one jittered point per lattice cell; returns the nearest two distances (f1, f2)
/// in cell units. Sponge pores, sugar crystals, caustics (f2 − f1), crinkled film.
struct TileCells: Sendable {
    let periodX: Int
    let periodY: Int
    private let points: [SIMD2<Float>]

    init(periodX: Int, periodY: Int, seed: UInt64, jitter: Float = 0.9) {
        self.periodX = max(periodX, 1)
        self.periodY = max(periodY, 1)
        var rng = SplitMix64(seed: seed)
        points = (0..<(self.periodX * self.periodY)).map { _ in
            let a = Float(rng.next() >> 40) / Float(1 << 24), b = Float(rng.next() >> 40) / Float(1 << 24)
            return SIMD2(0.5 + (a - 0.5) * jitter, 0.5 + (b - 0.5) * jitter)
        }
    }

    init(period: Int, seed: UInt64, jitter: Float = 0.9) {
        self.init(periodX: period, periodY: period, seed: seed, jitter: jitter)
    }

    func callAsFunction(_ u: Float, _ v: Float) -> SIMD2<Float> {
        let fx = u * Float(periodX), fy = v * Float(periodY)
        let cx = Int(fx.rounded(.down)), cy = Int(fy.rounded(.down))
        var f1: Float = 9, f2: Float = 9
        for dy in -1...1 {
            for dx in -1...1 {
                let gx = cx + dx, gy = cy + dy
                let wx = ((gx % periodX) + periodX) % periodX, wy = ((gy % periodY) + periodY) % periodY
                let p = points[wy * periodX + wx]
                let ox = Float(gx) + p.x - fx, oy = Float(gy) + p.y - fy
                let d = (ox * ox + oy * oy).squareRoot()
                if d < f1 {
                    f2 = f1
                    f1 = d
                } else if d < f2 {
                    f2 = d
                }
            }
        }
        return SIMD2(f1, f2)
    }
}

/// A row-major Float image (row 0 = the top = v 1).
struct SurfaceField: Sendable {
    let width: Int
    let height: Int
    var values: [Float]

    init(width: Int, height: Int, fill: Float = 0) {
        self.width = width
        self.height = height
        values = [Float](repeating: fill, count: width * height)
    }

    /// Fills from `f(u, v)` at pixel centres (u = (x + 0.5) / width, v = 1 − (y + 0.5) / height).
    init(width: Int, height: Int, _ f: (Float, Float) -> Float) {
        self.init(width: width, height: height)
        values.withUnsafeMutableBufferPointer { buffer in
            for y in 0..<height {
                let v = 1 - (Float(y) + 0.5) / Float(height)
                for x in 0..<width {
                    buffer[y * width + x] = f((Float(x) + 0.5) / Float(width), v)
                }
            }
        }
    }

    subscript(x: Int, y: Int) -> Float {
        values[((y % height + height) % height) * width + ((x % width + width) % width)]
    }

    /// Adds `other` (same size) × `scale`.
    mutating func add(_ other: SurfaceField, scale: Float = 1) {
        guard other.values.count == values.count else { return }
        for i in values.indices { values[i] += other.values[i] * scale }
    }

    /// Bilinear sample at (u, v), wrapping.
    func sample(_ u: Float, _ v: Float) -> Float {
        let fx = u * Float(width) - 0.5, fy = (1 - v) * Float(height) - 0.5
        let x0 = Int(fx.rounded(.down)), y0 = Int(fy.rounded(.down))
        let tx = fx - Float(x0), ty = fy - Float(y0)
        let a = self[x0, y0], b = self[x0 + 1, y0], c = self[x0, y0 + 1], d = self[x0 + 1, y0 + 1]
        return (a + (b - a) * tx) * (1 - ty) + (c + (d - c) * tx) * ty
    }
}

enum SurfaceImages {
    /// A CGColor from a hex RGB (no UIKit, so the builders stay plain Core Graphics).
    static func colour(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha)
    }

    /// A hex RGB as 0…1 floats.
    static func rgb(_ hex: UInt32) -> SIMD3<Float> {
        SIMD3(Float((hex >> 16) & 0xFF), Float((hex >> 8) & 0xFF), Float(hex & 0xFF)) / 255
    }

    static func smooth(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
        let t = clamp((x - e0) / max(e1 - e0, 1e-6), 0, 1)
        return t * t * (3 - 2 * t)
    }

    static func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        a + (b - a) * clamp(t, 0, 1)
    }

    // MARK: Legacy square helpers (kept for the shell and wax builders)

    /// Tileable value noise on a `period`-cell lattice, 0…1 (slow: hashes every lattice read; prefer `TileNoise`).
    static func valueNoise(_ x: Float, _ y: Float, period: Int, seed: UInt64) -> Float {
        func lattice(_ i: Int, _ j: Int) -> Float {
            let a = UInt64((i % period + period) % period), b = UInt64((j % period + period) % period)
            var rng = SplitMix64(seed: seed ^ (a &* 0x9E37_79B9) ^ (b &* 0xC2B2_AE3D_27D4_EB4F))
            return Float(rng.next() >> 40) / Float(1 << 24)
        }
        let fx = x * Float(period), fy = y * Float(period)
        let i = Int(fx.rounded(.down)), j = Int(fy.rounded(.down))
        let tx = fx - Float(i), ty = fy - Float(j)
        let sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty)
        let a = lattice(i, j), b = lattice(i + 1, j), c = lattice(i, j + 1), d = lattice(i + 1, j + 1)
        return (a + (b - a) * sx) + ((c + (d - c) * sx) - (a + (b - a) * sx)) * sy
    }

    /// A square height field (row-major, `size`²) from `height(u, v)`.
    static func field(size: Int, _ height: (Float, Float) -> Float) -> [Float] {
        SurfaceField(width: size, height: size, height).values
    }

    /// A square tangent-space normal map from a wrapping height field.
    static func normalMap(_ h: [Float], size: Int, strength: Float) -> CGImage? {
        var field = SurfaceField(width: size, height: size)
        field.values = h
        return normalImage(field, strength: strength)
    }

    // MARK: Images

    /// A tangent-space normal map (RGB = n · 0.5 + 0.5, +Y toward v 1) from a wrapping height field. `strength` is the
    /// slope per unit height step between neighbouring pixels.
    static func normalImage(_ h: SurfaceField, strength: Float) -> CGImage? {
        let w = h.width, ht = h.height
        var pixels = [UInt8](repeating: 255, count: w * ht * 4)
        h.values.withUnsafeBufferPointer { v in
            pixels.withUnsafeMutableBufferPointer { out in
                for y in 0..<ht {
                    let up = ((y + ht - 1) % ht) * w, down = ((y + 1) % ht) * w, row = y * w
                    for x in 0..<w {
                        let l = v[row + (x + w - 1) % w], r = v[row + (x + 1) % w]
                        let u = v[up + x], d = v[down + x]
                        let n = simd_normalize(SIMD3<Float>((l - r) * strength, (u - d) * strength, 1))
                        let k = (row + x) * 4
                        out[k] = UInt8(clamp((n.x * 0.5 + 0.5) * 255, 0, 255))
                        out[k + 1] = UInt8(clamp((n.y * 0.5 + 0.5) * 255, 0, 255))
                        out[k + 2] = UInt8(clamp((n.z * 0.5 + 0.5) * 255, 0, 255))
                    }
                }
            }
        }
        return image(pixels, width: w, height: ht)
    }

    /// A grey image (roughness, masks) from a field mapped into `range` (field values clamped to 0…1 first).
    static func greyImage(_ h: SurfaceField, range: ClosedRange<Float> = 0...1) -> CGImage? {
        var pixels = [UInt8](repeating: 255, count: h.width * h.height * 4)
        for i in 0..<(h.width * h.height) {
            let t = clamp(h.values[i], 0, 1)
            let g = UInt8(clamp((range.lowerBound + (range.upperBound - range.lowerBound) * t) * 255, 0, 255))
            pixels[i * 4] = g
            pixels[i * 4 + 1] = g
            pixels[i * 4 + 2] = g
        }
        return image(pixels, width: h.width, height: h.height)
    }

    /// A colour image from `f(x, y, u, v)` (0…1 RGB) at every pixel.
    static func colourImage(width: Int, height: Int, _ f: (Int, Int, Float, Float) -> SIMD3<Float>) -> CGImage? {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        pixels.withUnsafeMutableBufferPointer { out in
            for y in 0..<height {
                let v = 1 - (Float(y) + 0.5) / Float(height)
                for x in 0..<width {
                    let c = f(x, y, (Float(x) + 0.5) / Float(width), v)
                    let k = (y * width + x) * 4
                    out[k] = UInt8(clamp(c.x * 255, 0, 255))
                    out[k + 1] = UInt8(clamp(c.y * 255, 0, 255))
                    out[k + 2] = UInt8(clamp(c.z * 255, 0, 255))
                }
            }
        }
        return image(pixels, width: width, height: height)
    }

    static func image(_ pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    static func image(_ pixels: [UInt8], size: Int) -> CGImage? {
        image(pixels, width: size, height: size)
    }

    /// Drawn with Core Graphics into a `width × height` RGBA context (CG's origin is bottom-left: y = v · height).
    static func drawn(width: Int, height: Int, _ draw: (CGContext) -> Void) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        draw(context)
        return context.makeImage()
    }

    static func drawn(size: Int, _ draw: (CGContext) -> Void) -> CGImage? {
        drawn(width: size, height: size, draw)
    }

    /// Draws into an 8-bit grey context (black ground, draw in white) and reads it back as a field (0…1, row 0 top):
    /// soft lines, seams, creases and text emboss for height fields, all in native Core Graphics.
    static func greyCanvas(width: Int, height: Int, _ draw: (CGContext) -> Void) -> SurfaceField {
        var field = SurfaceField(width: width, height: height)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return field }
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(gray: 1, alpha: 1)
        context.setStrokeColor(gray: 1, alpha: 1)
        draw(context)
        guard let data = context.data else { return field }
        let bytes = data.bindMemory(to: UInt8.self, capacity: width * height)
        let stride = context.bytesPerRow
        for y in 0..<height {
            for x in 0..<width {
                field.values[y * width + x] = Float(bytes[y * stride + x]) / 255
            }
        }
        return field
    }

    /// Strokes `path` so it wraps across the image's edges (drawn at the 9 tile offsets): seamless lines in tiles.
    static func strokeWrapped(_ cg: CGContext, _ path: CGPath, width: CGFloat, height: CGFloat) {
        for dy in -1...1 {
            for dx in -1...1 {
                var t = CGAffineTransform(translationX: CGFloat(dx) * width, y: CGFloat(dy) * height)
                if let moved = path.copy(using: &t) {
                    cg.addPath(moved)
                    cg.strokePath()
                }
            }
        }
    }

    /// Fills an ellipse so it wraps across the image's edges.
    static func fillWrapped(_ cg: CGContext, _ rect: CGRect, width: CGFloat, height: CGFloat) {
        for dy in -1...1 {
            for dx in -1...1 {
                let r = rect.offsetBy(dx: CGFloat(dx) * width, dy: CGFloat(dy) * height)
                guard r.maxX >= 0, r.minX <= width, r.maxY >= 0, r.minY <= height else { continue }
                cg.fillEllipse(in: r)
            }
        }
    }

    /// Core Text, centred on `centre` (CG coordinates), rotated by `angle`.
    static func text(_ cg: CGContext, _ string: String, font name: String, size: CGFloat, colour: CGColor, centre: CGPoint,
                     angle: CGFloat = 0, kern: CGFloat = 0) {
        let font = CTFontCreateWithName(name as CFString, size, nil)
        var attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): colour,
        ]
        if kern != 0 { attributes[NSAttributedString.Key(kCTKernAttributeName as String)] = kern }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes) as CFAttributedString)
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        cg.saveGState()
        cg.translateBy(x: centre.x, y: centre.y)
        cg.rotate(by: angle)
        cg.textPosition = CGPoint(x: -width / 2, y: -(ascent - descent) / 2)
        CTLineDraw(line, cg)
        cg.restoreGState()
    }

    // MARK: Patterns kept from the fidelity pass

    /// Egg shell: tan with soft mottling, darker freckles and pale calcium specks (512², tileable).
    static func eggShell(size: Int = 512, seed: UInt64 = 0xE66_5EED) -> CGImage? {
        let s = CGFloat(size)
        return drawn(size: size) { cg in
            cg.setFillColor(colour(0xEFD3A0))
            cg.fill(CGRect(x: 0, y: 0, width: s, height: s))
            var rng = SplitMix64(seed: seed)
            for _ in 0..<110 {
                let r = CGFloat(Float.random(in: 8...26, using: &rng)) * s / 256
                let x = CGFloat(Float.random(in: 0...1, using: &rng)) * s, y = CGFloat(Float.random(in: 0...1, using: &rng)) * s
                let light = rng.next() % 2 == 0
                cg.setFillColor(colour(light ? 0xF6E2BC : 0xE2C08A, 0.3))
                fillWrapped(cg, CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r), width: s, height: s)
            }
            for _ in 0..<1500 {
                let r = CGFloat(Float.random(in: 0.5...1.6, using: &rng)) * s / 256
                let x = CGFloat(Float.random(in: 0...1, using: &rng)) * s, y = CGFloat(Float.random(in: 0...1, using: &rng)) * s
                let freckle = rng.next() % 3 != 0
                cg.setFillColor(freckle ? colour(0xA77744, CGFloat(Float.random(in: 0.3...0.6, using: &rng))) : colour(0xFFF8EA, 0.8))
                cg.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
            }
        }
    }

    /// Fine pores (egg shell): high-frequency bumps.
    static func pores(size: Int = 512, seed: UInt64 = 0x9025) -> SurfaceField {
        let fbm = TileFBM(period: 48, octaves: 3, seed: seed)
        let broad = TileFBM(period: 6, octaves: 2, seed: seed ^ 0x55)
        return SurfaceField(width: size, height: size) { u, v in
            pow(fbm(u, v), 2.2) + 0.35 * broad(u, v)
        }
    }

    /// Wax streaks running along a crayon (v along the length, u round it).
    static func wax(size: Int = 256, seed: UInt64 = 0x3A5) -> SurfaceField {
        let streaks = TileFBM(periodX: 24, periodY: 6, octaves: 2, seed: seed)
        let fine = TileFBM(period: 16, octaves: 2, seed: seed ^ 0x77)
        return SurfaceField(width: size, height: size) { u, v in
            0.7 * streaks(u, v) + 0.3 * fine(u, v)
        }
    }

    /// The bottle's printed label over the bottle's v (0 base … 1 neck; image top = v 1): a cream band and a raspberry
    /// band, a white wordmark on the raspberry and a wave rule on the cream (a fictional "SEA GLASS · No 9").
    static func bottleLabel(size: Int = 512) -> CGImage? {
        drawn(size: size) { cg in
            let s = CGFloat(size)
            func row(_ v: CGFloat) -> CGFloat { v * s } // CG's origin is bottom-left: v 0 is the image's bottom row
            cg.setFillColor(colour(0xF4ECDD))
            cg.fill(CGRect(x: 0, y: 0, width: s, height: s))
            // Paper tooth: faint fibres.
            var rng = SplitMix64(seed: 0x5EA6)
            for _ in 0..<900 {
                let x = CGFloat(Float.random(in: 0...1, using: &rng)) * s, y = CGFloat(Float.random(in: 0...1, using: &rng)) * s
                cg.setFillColor(colour(rng.next() % 2 == 0 ? 0xE6DCC8 : 0xFBF6EC, 0.5))
                cg.fill(CGRect(x: x, y: y, width: CGFloat(Float.random(in: 1...4, using: &rng)), height: 1))
            }
            // Cream band: v 0.25…0.43; raspberry band: v 0.43…0.61 (the label patches' profile bands).
            cg.setFillColor(colour(0xE8336F))
            cg.fill(CGRect(x: 0, y: row(0.43), width: s, height: row(0.61) - row(0.43)))
            cg.setFillColor(colour(0xB91F55))
            cg.fill(CGRect(x: 0, y: row(0.43), width: s, height: s * 0.008))
            cg.fill(CGRect(x: 0, y: row(0.61) - s * 0.008, width: s, height: s * 0.008))
            // A wave rule on the cream, and a fine double rule under it.
            cg.setStrokeColor(colour(0xE8336F, 0.8))
            cg.setLineWidth(s * 0.006)
            cg.move(to: CGPoint(x: 0, y: row(0.34)))
            for k in 0...64 {
                let x = s * CGFloat(k) / 64
                cg.addLine(to: CGPoint(x: x, y: row(0.34) + s * 0.012 * sin(CGFloat(k) / 64 * .pi * 16)))
            }
            cg.strokePath()
            cg.setLineWidth(1)
            cg.setStrokeColor(colour(0xB91F55, 0.7))
            for y in [row(0.295), row(0.302)] {
                cg.move(to: CGPoint(x: 0, y: y))
                cg.addLine(to: CGPoint(x: s, y: y))
                cg.strokePath()
            }
            // The wordmark, twice round, running along the bottle (white on the raspberry), and small print on the cream.
            for k in 0..<2 {
                let x = s * (0.25 + 0.5 * CGFloat(k))
                text(cg, "SEA GLASS", font: "Helvetica-Bold", size: s * 0.07, colour: colour(0xFFFFFF), centre: CGPoint(x: x, y: row(0.52)),
                     angle: .pi / 2)
                text(cg, "No 9 · MINERAL WATER · 330 ml", font: "Helvetica", size: s * 0.018, colour: colour(0x9A2E4E),
                     centre: CGPoint(x: x, y: row(0.38)), angle: .pi / 2)
            }
        }
    }
}

/// Uploads and caches the procedural textures (one of each per session). Images are drawn on a background task; the
/// upload is mipmapped. Concurrent asks for the same key share one build.
@MainActor
enum SurfaceDetail {
    private static var cache: [String: TextureResource] = [:]
    private static var pending: [String: Task<TextureResource?, Never>] = [:]

    /// A CGImage handed across the actor boundary (Core Graphics images are immutable once made).
    private struct ImageBox: @unchecked Sendable {
        let image: CGImage?
    }

    /// The texture for `key`, built once: `build` runs off the main actor, the upload is asynchronous and mipmapped.
    static func texture(_ key: String, semantic: TextureResource.Semantic,
                        _ build: @escaping @Sendable () -> CGImage?) async -> TextureResource? {
        if let cached = cache[key] { return cached }
        if let running = pending[key] { return await running.value }
        let task = Task { @MainActor () -> TextureResource? in
            let box = await Task.detached(priority: .userInitiated) { ImageBox(image: build()) }.value
            defer { pending[key] = nil }
            guard let image = box.image else { return nil }
            let options = TextureResource.CreateOptions(semantic: semantic, mipmapsMode: .allocateAndGenerateAll)
            guard let texture = try? await TextureResource(image: image, withName: key, options: options) else { return nil }
            cache[key] = texture
            return texture
        }
        pending[key] = task
        return await task.value
    }

    /// The cached texture for `key` if it has already landed (no build).
    static func cached(_ key: String) -> TextureResource? {
        cache[key]
    }

    /// A material texture that repeats (tiled detail) with trilinear, anisotropic filtering.
    static func tiled(_ texture: TextureResource) -> MaterialParameters.Texture {
        MaterialParameters.Texture(texture, sampler: sampler(repeating: true))
    }

    /// A material texture clamped at its edges (labels, painted maps) with trilinear, anisotropic filtering.
    static func clamped(_ texture: TextureResource) -> MaterialParameters.Texture {
        MaterialParameters.Texture(texture, sampler: sampler(repeating: false))
    }

    /// A material texture that wraps round (u) but clamps along v: lathe and spherical maps.
    static func wrapped(_ texture: TextureResource) -> MaterialParameters.Texture {
        MaterialParameters.Texture(texture, sampler: sampler(repeating: true, clampV: true))
    }

    private static func sampler(repeating: Bool, clampV: Bool = false) -> MaterialParameters.Texture.Sampler {
        let d = MTLSamplerDescriptor()
        d.sAddressMode = repeating ? .repeat : .clampToEdge
        d.tAddressMode = repeating && !clampV ? .repeat : .clampToEdge
        d.minFilter = .linear
        d.magFilter = .linear
        d.mipFilter = .linear
        d.maxAnisotropy = 8
        return MaterialParameters.Texture.Sampler(d)
    }

    // MARK: The fidelity pass's maps

    static func eggShell() async -> (colour: TextureResource?, normal: TextureResource?) {
        async let colour = texture("detail.egg.colour", semantic: .color) { SurfaceImages.eggShell() }
        async let normal = texture("detail.egg.normal", semantic: .normal) {
            SurfaceImages.normalImage(SurfaceImages.pores(), strength: 2.4)
        }
        return await (colour, normal)
    }

    static func waxNormal() async -> TextureResource? {
        await texture("detail.wax.normal", semantic: .normal) { SurfaceImages.normalImage(SurfaceImages.wax(), strength: 1.8) }
    }

    static func bottleLabel() async -> TextureResource? {
        await texture("detail.bottle.label", semantic: .color) { SurfaceImages.bottleLabel() }
    }
}
