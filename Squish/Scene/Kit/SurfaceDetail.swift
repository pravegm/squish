import CoreGraphics
import CoreText
import Foundation
import RealityKit
import simd
import UIKit

/// Procedural surface detail (founder fidelity pass, 24 Oct 2026): small tileable colour, normal and roughness images
/// drawn once per session off the main actor, so a shell has speckles and pores, a crayon has wax streaks, a label has
/// print. Pure image builders here; `SurfaceDetail` caches the uploaded textures.
enum SurfaceImages {
    /// A CGColor from a hex RGB (no UIKit, so the builders stay plain Core Graphics).
    static func colour(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha)
    }

    /// Tileable value noise on a `period`-cell lattice, 0…1.
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

    /// Fractal (tileable) noise: `octaves` of value noise from `period` cells up.
    static func fbm(_ x: Float, _ y: Float, period: Int, octaves: Int, seed: UInt64) -> Float {
        var sum: Float = 0, amplitude: Float = 0.5, total: Float = 0, p = period
        for o in 0..<octaves {
            sum += amplitude * valueNoise(x, y, period: p, seed: seed &+ UInt64(o) &* 0x51)
            total += amplitude
            amplitude *= 0.5
            p *= 2
        }
        return sum / max(total, 1e-5)
    }

    /// A height field (row-major, `size`²) from `height(u, v)`, u and v in 0…1.
    static func field(size: Int, _ height: (Float, Float) -> Float) -> [Float] {
        var out = [Float](repeating: 0, count: size * size)
        for y in 0..<size {
            for x in 0..<size {
                out[y * size + x] = height(Float(x) / Float(size), Float(y) / Float(size))
            }
        }
        return out
    }

    /// A tangent-space normal map (RGB = n · 0.5 + 0.5) from a wrapping height field.
    static func normalMap(_ h: [Float], size: Int, strength: Float) -> CGImage? {
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let l = h[y * size + (x + size - 1) % size], r = h[y * size + (x + 1) % size]
                let u = h[((y + size - 1) % size) * size + x], d = h[((y + 1) % size) * size + x]
                let n = simd_normalize(SIMD3<Float>((l - r) * strength, (u - d) * strength, 1))
                let k = (y * size + x) * 4
                pixels[k] = UInt8(clamp((n.x * 0.5 + 0.5) * 255, 0, 255))
                pixels[k + 1] = UInt8(clamp((n.y * 0.5 + 0.5) * 255, 0, 255))
                pixels[k + 2] = UInt8(clamp((n.z * 0.5 + 0.5) * 255, 0, 255))
            }
        }
        return image(pixels, size: size)
    }

    /// A grey image (roughness) from a field mapped into `range`.
    static func grey(_ h: [Float], size: Int, range: ClosedRange<Float>) -> CGImage? {
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        for i in 0..<(size * size) {
            let g = UInt8(clamp((range.lowerBound + (range.upperBound - range.lowerBound) * h[i]) * 255, 0, 255))
            pixels[i * 4] = g
            pixels[i * 4 + 1] = g
            pixels[i * 4 + 2] = g
        }
        return image(pixels, size: size)
    }

    static func image(_ pixels: [UInt8], size: Int) -> CGImage? {
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Drawn with Core Graphics into a `size`² RGBA context.
    static func drawn(size: Int, _ draw: (CGContext) -> Void) -> CGImage? {
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        draw(context)
        return context.makeImage()
    }

    // MARK: Patterns

    /// Egg shell: tan with soft mottling, darker freckles and pale calcium specks.
    static func eggShell(size: Int = 256, seed: UInt64 = 0xE66_5EED) -> CGImage? {
        drawn(size: size) { cg in
            cg.setFillColor(colour(0xEFD3A0))
            cg.fill(CGRect(x: 0, y: 0, width: size, height: size))
            var rng = SplitMix64(seed: seed)
            let s = CGFloat(size)
            for _ in 0..<90 {
                let r = CGFloat(Float.random(in: 8...26, using: &rng)) * s / 256
                let x = CGFloat(Float.random(in: 0...1, using: &rng)) * s, y = CGFloat(Float.random(in: 0...1, using: &rng)) * s
                let light = rng.next() % 2 == 0
                cg.setFillColor(colour(light ? 0xF6E2BC : 0xE2C08A, 0.35))
                cg.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
            }
            for _ in 0..<420 {
                let r = CGFloat(Float.random(in: 0.6...1.8, using: &rng)) * s / 256
                let x = CGFloat(Float.random(in: 0...1, using: &rng)) * s, y = CGFloat(Float.random(in: 0...1, using: &rng)) * s
                let freckle = rng.next() % 3 != 0
                cg.setFillColor(freckle ? colour(0xA77744, 0.55) : colour(0xFFF8EA, 0.8))
                cg.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
            }
        }
    }

    /// Fine pores (egg shell, sponge): high-frequency bumps.
    static func pores(size: Int = 128, seed: UInt64 = 0x9025) -> [Float] {
        field(size: size) { u, v in
            let n = fbm(u, v, period: 16, octaves: 3, seed: seed)
            return pow(n, 2.2)
        }
    }

    /// Wax streaks running along a crayon (v along the length, u round it).
    static func wax(size: Int = 128, seed: UInt64 = 0x3A5) -> [Float] {
        field(size: size) { u, v in
            0.7 * fbm(u, v * 0.25, period: 24, octaves: 2, seed: seed) + 0.3 * fbm(u, v, period: 8, octaves: 2, seed: seed ^ 0x77)
        }
    }

    /// The bottle's printed label over the bottle's v (0 base … 1 neck; image top = v 1): a cream band and a raspberry
    /// band, a white wordmark on the raspberry and a wave rule on the cream (a fictional "SEA GLASS · No 9").
    static func bottleLabel(size: Int = 384) -> CGImage? {
        drawn(size: size) { cg in
            let s = CGFloat(size)
            func row(_ v: CGFloat) -> CGFloat { v * s } // CG's origin is bottom-left: v 0 is the image's bottom row
            cg.setFillColor(colour(0xF4ECDD))
            cg.fill(CGRect(x: 0, y: 0, width: s, height: s))
            // Cream band: v 0.25…0.43; raspberry band: v 0.43…0.61 (the label patches' profile bands).
            cg.setFillColor(colour(0xE8336F))
            cg.fill(CGRect(x: 0, y: row(0.43), width: s, height: row(0.61) - row(0.43)))
            cg.setFillColor(colour(0xB91F55))
            cg.fill(CGRect(x: 0, y: row(0.43), width: s, height: s * 0.008))
            cg.fill(CGRect(x: 0, y: row(0.61) - s * 0.008, width: s, height: s * 0.008))
            // A wave rule on the cream.
            cg.setStrokeColor(colour(0xE8336F, 0.8))
            cg.setLineWidth(s * 0.006)
            cg.move(to: CGPoint(x: 0, y: row(0.34)))
            for k in 0...64 {
                let x = s * CGFloat(k) / 64
                cg.addLine(to: CGPoint(x: x, y: row(0.34) + s * 0.012 * sin(CGFloat(k) / 64 * .pi * 16)))
            }
            cg.strokePath()
            // The wordmark, twice round, running along the bottle (Core Text, white on the raspberry).
            let font = CTFontCreateWithName("Helvetica-Bold" as CFString, s * 0.07, nil)
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): colour(0xFFFFFF),
            ]
            let text = NSAttributedString(string: "SEA GLASS", attributes: attributes)
            let line = CTLineCreateWithAttributedString(text as CFAttributedString)
            let width = CTLineGetTypographicBounds(line, nil, nil, nil)
            for k in 0..<2 {
                cg.saveGState()
                cg.translateBy(x: s * (0.25 + 0.5 * CGFloat(k)), y: row(0.52))
                cg.rotate(by: .pi / 2)
                cg.textPosition = CGPoint(x: -CGFloat(width) / 2, y: -s * 0.025)
                CTLineDraw(line, cg)
                cg.restoreGState()
            }
        }
    }
}

/// Uploads and caches the procedural textures (one of each per session).
@MainActor
enum SurfaceDetail {
    private static var cache: [String: TextureResource] = [:]

    /// Draws once (on the main actor: a few milliseconds, once per session) and uploads asynchronously.
    static func texture(_ key: String, semantic: TextureResource.Semantic, _ build: () -> CGImage?) async -> TextureResource? {
        if let cached = cache[key] { return cached }
        guard let image = build() else { return nil }
        guard let texture = try? await TextureResource(image: image, withName: key, options: .init(semantic: semantic)) else { return nil }
        cache[key] = texture
        return texture
    }

    static func eggShell() async -> (colour: TextureResource?, normal: TextureResource?) {
        let colour = await texture("detail.egg.colour", semantic: .color) { SurfaceImages.eggShell() }
        let normal = await texture("detail.egg.normal", semantic: .normal) {
            SurfaceImages.normalMap(SurfaceImages.pores(), size: 128, strength: 2.2)
        }
        return (colour, normal)
    }

    static func waxNormal() async -> TextureResource? {
        await texture("detail.wax.normal", semantic: .normal) { SurfaceImages.normalMap(SurfaceImages.wax(), size: 128, strength: 1.6) }
    }

    static func bottleLabel() async -> TextureResource? {
        await texture("detail.bottle.label", semantic: .color) { SurfaceImages.bottleLabel() }
    }
}
