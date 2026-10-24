import CoreGraphics
import Foundation
import simd

// The 3D-art round's surface patterns (design/OBJECT-STORYBOARDS.md "Follow-up for a 3D-art round"): one pure, seeded,
// nonisolated builder per map, run off the main actor by `SurfaceDetail.texture`. Sizes stay 256–1024 (the 120 Hz
// budget: every map is mipmapped and built once per session).

/// Where the duck's paint goes on its body texture (spherical UVs about the body blob's centre).
struct DuckPaint: Sendable {
    /// Each eye's UV centre and its painted white's half size (u, v).
    var eyes: [SIMD2<Float>]
    var eyeHalf: SIMD2<Float>
}

extension SurfaceImages {
    /// Wrapped distance in u (0…1 wraps).
    static func wrapDelta(_ a: Float, _ b: Float) -> Float {
        var d = a - b
        d -= d.rounded()
        return d
    }

    // MARK: - Rubber duck (spherical UV 2:1, seam at the tail)

    /// Long, soft vinyl folds across the back and the head (the crushed duck), 0…1.
    static func duckCreaseField(width: Int, height: Int, seed: UInt64 = 0xD0C_C2EA) -> SurfaceField {
        var rng = SplitMix64(seed: seed)
        let w = CGFloat(width), h = CGFloat(height)
        return greyCanvas(width: width, height: height) { cg in
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            for _ in 0..<16 {
                let path = CGMutablePath()
                var p = CGPoint(x: CGFloat(Float.random(in: 0...1, using: &rng)) * w,
                                y: CGFloat(Float.random(in: 0.42...0.95, using: &rng)) * h)
                var heading = CGFloat(Float.random(in: 0...(2 * .pi), using: &rng))
                let length = CGFloat(Float.random(in: 0.1...0.28, using: &rng)) * w
                path.move(to: p)
                for _ in 0..<7 {
                    heading += CGFloat(Float.random(in: -0.35...0.35, using: &rng))
                    p = CGPoint(x: p.x + cos(heading) * length / 7, y: p.y + sin(heading) * length / 7 * 0.6)
                    path.addLine(to: p)
                }
                // A soft fold: wide and faint, then the sharp crease line in it.
                for (width, alpha) in [(CGFloat(9), CGFloat(0.12)), (5, 0.22), (2.4, 0.5), (1.1, 0.9)] {
                    cg.setLineWidth(width)
                    cg.setStrokeColor(gray: 1, alpha: alpha)
                    strokeWrapped(cg, path, width: w, height: h)
                }
            }
        }
    }

    /// The duck's body colour: yellow vinyl, a touch deeper underneath, a faint pale mould-seam flash front and back,
    /// and painted eye whites with a fine dark outline (the glossy pupils ride on top in 3D). `creased` adds the crushed
    /// duck's stress-whitened fold lines.
    static func duckVinyl(_ paint: DuckPaint, creased: Bool, width: Int = 1024, height: Int = 512) -> CGImage? {
        let mottle = TileFBM(periodX: 8, periodY: 4, octaves: 3, seed: 0xD0C1)
        let folds = creased ? duckCreaseField(width: width, height: height) : nil
        let base = rgb(0xFFD23F), deep = rgb(0xF2B21E), flash = rgb(0xFFE88C)
        let white = rgb(0xFFF8E6), shade = rgb(0xEFE2BE), outline = rgb(0x3B2A12), stress = rgb(0xFFF1B8)
        let px = Float(width)
        return colourImage(width: width, height: height) { x, y, u, v in
            var c = mix(base, deep, 0.45 * smooth(0.42, 0.05, v) + 0.35 * (mottle(u, v) - 0.5))
            // The mould seam runs over the duck in its x–y plane: u 0.5 (the chest and face) and u 0 (the tail).
            let du = min(abs(u - 0.5), min(u, 1 - u)) * px
            c = mix(c, flash, 0.55 * exp(-du * du / 1.4))
            for e in paint.eyes {
                let q = SIMD2(wrapDelta(u, e.x) / paint.eyeHalf.x, (v - e.y) / paint.eyeHalf.y)
                let d = simd_length(q)
                guard d < 1.3 else { continue }
                if d < 1 { c = mix(white, shade, d * d * 0.6 + 0.25 * max(-q.y, 0)) }
                c = mix(c, outline, 0.85 * exp(-pow((d - 1) / 0.08, 2)))
            }
            if let folds { c = mix(c, stress, 0.65 * folds.values[y * width + x]) }
            return c
        }
    }

    /// The duck's height field: vinyl orange-peel, the mould seam's ridge, the eye paint's raised edge and, crushed,
    /// the fold creases as grooves.
    static func duckVinylHeight(_ paint: DuckPaint, creased: Bool, width: Int = 1024, height: Int = 512) -> SurfaceField {
        let peel = TileFBM(periodX: 150, periodY: 75, octaves: 2, seed: 0xD0C2)
        let ripple = TileFBM(periodX: 12, periodY: 6, octaves: 2, seed: 0xD0C3)
        let folds = creased ? duckCreaseField(width: width, height: height) : nil
        let px = Float(width)
        var field = SurfaceField(width: width, height: height) { u, v in
            var h = 0.35 * peel(u, v) + 0.6 * ripple(u, v)
            let du = min(abs(u - 0.5), min(u, 1 - u)) * px
            h += 0.9 * exp(-du * du / 1.6)
            for e in paint.eyes {
                let d = simd_length(SIMD2(wrapDelta(u, e.x) / paint.eyeHalf.x, (v - e.y) / paint.eyeHalf.y))
                h += 0.3 * smooth(1.06, 0.94, d)
            }
            return h
        }
        if let folds { field.add(folds, scale: -1.6) }
        return field
    }

    /// Clearcoat / roughness breakup on the vinyl: mostly glossy, with soft, worn, fingered patches. 0.55…1.
    static func duckCoat(width: Int = 512, height: Int = 256) -> CGImage? {
        let smudge = TileFBM(periodX: 6, periodY: 3, octaves: 4, seed: 0xD0C4)
        let fine = TileFBM(periodX: 48, periodY: 24, octaves: 2, seed: 0xD0C5)
        let field = SurfaceField(width: width, height: height) { u, v in
            0.15 + 0.55 * smooth(0.5, 0.75, smudge(u, v)) + 0.2 * fine(u, v)
        }
        return greyImage(field, range: 0.55...1)
    }

    /// The painted beak (spherical UV about the beak's centre, seam at the back where it meets the head): orange paint,
    /// lighter on top, a darker mouth line between the two lobes and two nostril dots.
    static func duckBeak(width: Int = 256, height: Int = 128) -> CGImage? {
        let mottle = TileFBM(periodX: 6, periodY: 3, octaves: 2, seed: 0xBEA4)
        let orange = rgb(0xFF8A1F), light = rgb(0xFFAE4A), deep = rgb(0xD9620C), mouth = rgb(0x9C3F06)
        let nostrils = [SDFBlob.sphericalUV(SIMD3(0.55, 0.8, 0.25)), SDFBlob.sphericalUV(SIMD3(0.55, 0.8, -0.25))]
        return colourImage(width: width, height: height) { _, _, u, v in
            var c = mix(orange, light, smooth(0.55, 0.85, v) * 0.7 + 0.25 * (mottle(u, v) - 0.5))
            // Toward the head (u near 0 / 1) the paint is a little deeper.
            c = mix(c, deep, 0.4 * smooth(0.22, 0.02, min(u, 1 - u)))
            let front = smooth(0.32, 0.15, abs(u - 0.5))
            c = mix(c, mouth, 0.85 * front * exp(-pow((v - 0.47) / 0.018, 2)))
            for n in nostrils {
                let d = simd_length(SIMD2(wrapDelta(u, n.x) / 0.018, (v - n.y) / 0.03))
                c = mix(c, mouth, 0.8 * smooth(1, 0.6, d))
            }
            return c
        }
    }

    /// Fine vinyl orange-peel as a tileable height field (the squeezed-out skirt and other flat vinyl).
    static func vinylTile(size: Int = 256, seed: UInt64 = 0x71A1) -> SurfaceField {
        let a = TileFBM(period: 24, octaves: 2, seed: seed), b = TileNoise(period: 64, seed: seed ^ 0x9)
        return SurfaceField(width: size, height: size) { u, v in 0.6 * a(u, v) + 0.3 * b(u, v) }
    }

    // MARK: - Gummy bear (spherical UV 2:1): sugar-dusted gel

    /// Seeded sugar grains (u, v, radius px, alpha), uniform over the sphere (no pile-up at the poles).
    static func sugarGrains(count: Int, seed: UInt64) -> [SIMD4<Float>] {
        var rng = SplitMix64(seed: seed)
        return (0..<count).map { _ in
            let z = Float.random(in: -1...1, using: &rng)
            let v = 1 - acos(z) / .pi
            return SIMD4(Float.random(in: 0...1, using: &rng), v, Float.random(in: 0.6...1.8, using: &rng),
                         Float.random(in: 0.45...1, using: &rng))
        }
    }

    /// Draws the grains as round-on-the-surface dots (wider in u away from the equator), wrapping in u.
    static func drawGrains(_ cg: CGContext, _ grains: [SIMD4<Float>], width: Int, height: Int, gray: Bool, hex: UInt32 = 0xFFEFEA) {
        let w = CGFloat(width), h = CGFloat(height)
        for g in grains {
            let sinPhi = max(sin(Float.pi * (1 - g.y)), 0.18)
            let ry = CGFloat(g.z), rx = CGFloat(g.z / sinPhi)
            let rect = CGRect(x: CGFloat(g.x) * w - rx, y: CGFloat(g.y) * h - ry, width: 2 * rx, height: 2 * ry)
            if gray { cg.setFillColor(gray: 1, alpha: CGFloat(g.w)) } else { cg.setFillColor(colour(hex, CGFloat(g.w) * 0.85)) }
            fillWrapped(cg, rect, width: w, height: h)
        }
    }

    static let gummyGrainCount = 2600
    static let gummyGrainSeed: UInt64 = 0x5A6A_6E

    /// The gummy's skin colour: red gel with soft deeper and brighter blotches under a dusting of sugar.
    static func gummySkin(width: Int = 512, height: Int = 256) -> CGImage? {
        let w = CGFloat(width), h = CGFloat(height)
        let grains = sugarGrains(count: gummyGrainCount, seed: gummyGrainSeed)
        return drawn(width: width, height: height) { cg in
            cg.setFillColor(colour(0xFF5A4E))
            cg.fill(CGRect(x: 0, y: 0, width: w, height: h))
            var rng = SplitMix64(seed: 0x6B_0B1)
            for _ in 0..<40 {
                let r = CGFloat(Float.random(in: 10...36, using: &rng))
                let x = CGFloat(Float.random(in: 0...1, using: &rng)) * w, y = CGFloat(Float.random(in: 0.1...0.9, using: &rng)) * h
                cg.setFillColor(colour(rng.next() % 2 == 0 ? 0xE8443A : 0xFF7A68, 0.22))
                fillWrapped(cg, CGRect(x: x - r, y: y - r * 0.6, width: 2 * r, height: 1.2 * r), width: w, height: h)
            }
            drawGrains(cg, grains, width: width, height: height, gray: false)
        }
    }

    /// The sugar's height (crystals stand proud) and its roughness mask (crystals matte, gel between them glossy).
    static func gummySugar(width: Int = 512, height: Int = 256) -> SurfaceField {
        let grains = sugarGrains(count: gummyGrainCount, seed: gummyGrainSeed)
        let gel = TileFBM(periodX: 10, periodY: 5, octaves: 2, seed: 0x6B_0B2)
        var field = greyCanvas(width: width, height: height) { cg in drawGrains(cg, grains, width: width, height: height, gray: true) }
        let soft = SurfaceField(width: width, height: height) { u, v in gel(u, v) }
        field.add(soft, scale: 0.5)
        return field
    }

    static func gummyRough(width: Int = 512, height: Int = 256) -> CGImage? {
        let grains = sugarGrains(count: gummyGrainCount, seed: gummyGrainSeed)
        let field = greyCanvas(width: width, height: height) { cg in drawGrains(cg, grains, width: width, height: height, gray: true) }
        return greyImage(field, range: 0.38...0.95)
    }

    /// The gummy's core: deep red with soft brighter pools (light scattered inside), also its glow.
    static func gummyCore(width: Int = 256, height: Int = 128) -> CGImage? {
        let pools = TileFBM(periodX: 4, periodY: 2, octaves: 3, seed: 0x6B_C0)
        let deep = rgb(0xB0162C), bright = rgb(0xF2404C)
        return colourImage(width: width, height: height) { _, _, u, v in
            mix(deep, bright, smooth(0.42, 0.78, pools(u, v)))
        }
    }

    /// The chewed pad (planar over its unit radius, uv radius 0.4): thick gel in the middle, stretch streaks radiating
    /// out, a stress-whitened torn rim and a few sugar grains left.
    static func gummyPad(size: Int = 512) -> CGImage? {
        let s = CGFloat(size)
        return drawn(size: size) { cg in
            let c = CGPoint(x: s / 2, y: s / 2)
            let space = CGColorSpaceCreateDeviceRGB()
            cg.setFillColor(colour(0xFF7466))
            cg.fill(CGRect(x: 0, y: 0, width: s, height: s))
            if let g = CGGradient(colorsSpace: space, colors: [colour(0xD8302A), colour(0xF2483E), colour(0xFF8A7C)] as CFArray,
                                  locations: [0, 0.55, 1]) {
                cg.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: s * 0.42, options: [.drawsAfterEndLocation])
            }
            var rng = SplitMix64(seed: 0x6B_9AD)
            cg.setLineCap(.round)
            for _ in 0..<70 {
                let a = CGFloat(Float.random(in: 0...(2 * .pi), using: &rng))
                let r0 = s * CGFloat(Float.random(in: 0.05...0.25, using: &rng)), r1 = s * CGFloat(Float.random(in: 0.3...0.42, using: &rng))
                cg.setStrokeColor(colour(0xFFB4A8, CGFloat(Float.random(in: 0.15...0.4, using: &rng))))
                cg.setLineWidth(CGFloat(Float.random(in: 0.8...2.4, using: &rng)))
                cg.move(to: CGPoint(x: c.x + cos(a) * r0, y: c.y + sin(a) * r0))
                cg.addLine(to: CGPoint(x: c.x + cos(a + 0.04) * r1, y: c.y + sin(a + 0.04) * r1))
                cg.strokePath()
            }
            // The torn rim: a pale stress band just inside the edge.
            cg.setStrokeColor(colour(0xFFD0C8, 0.55))
            cg.setLineWidth(s * 0.03)
            cg.strokeEllipse(in: CGRect(x: c.x - s * 0.37, y: c.y - s * 0.37, width: s * 0.74, height: s * 0.74))
            for _ in 0..<300 {
                let x = CGFloat(Float.random(in: 0.1...0.9, using: &rng)) * s, y = CGFloat(Float.random(in: 0.1...0.9, using: &rng)) * s
                let r = CGFloat(Float.random(in: 0.8...2.2, using: &rng))
                cg.setFillColor(colour(0xFFF0EC, CGFloat(Float.random(in: 0.4...0.9, using: &rng))))
                cg.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
            }
        }
    }

    static func gummyPadHeight(size: Int = 512) -> SurfaceField {
        let streaks = TileFBM(periodX: 2, periodY: 40, octaves: 2, seed: 0x6B_9AE)
        return SurfaceField(width: size, height: size) { u, v in
            let d = SIMD2(u - 0.5, v - 0.5)
            let r = simd_length(d)
            let a = atan2(d.y, d.x) / (2 * .pi) + 0.5
            // Stretch streaks run radially (noise stretched along r); the middle is thicker.
            return 0.8 * streaks(r * 2, a) + 1.5 * smooth(0.42, 0.0, r)
        }
    }

    // MARK: - Jelly (lathe UV: u round, v up)

    /// The jelly's skin: very faint ripples and mould growth lines, for specular breakup on a mirror gloss.
    static func jellySkin(width: Int = 512, height: Int = 256) -> SurfaceField {
        let ripple = TileFBM(periodX: 14, periodY: 7, octaves: 3, seed: 0x7E1)
        return SurfaceField(width: width, height: height) { u, v in
            0.9 * ripple(u, v) + 0.25 * pow(sin(.pi * v * 22), 2)
        }
    }

    /// The jelly's core as seen through the gel: deep raspberry with a bright caustic network (light focused by the
    /// wobbling dome), used as its colour and its glow.
    static func jellyCaustics(width: Int = 512, height: Int = 256) -> CGImage? {
        let cells = TileCells(periodX: 18, periodY: 9, seed: 0x7E2)
        let fine = TileCells(periodX: 40, periodY: 20, seed: 0x7E3)
        let pools = TileFBM(periodX: 4, periodY: 2, octaves: 3, seed: 0x7E4)
        let deep = rgb(0x8E1240), mid = rgb(0xC21E58), bright = rgb(0xFF7CA6)
        return colourImage(width: width, height: height) { _, _, u, v in
            let a = cells(u, v), b = fine(u, v)
            let network = smooth(0.16, 0.0, a.y - a.x) * 0.8 + smooth(0.1, 0.0, b.y - b.x) * 0.35
            var c = mix(deep, mid, smooth(0.35, 0.75, pools(u, v)))
            c = mix(c, bright, network * (0.55 + 0.45 * v))
            return c
        }
    }

    // MARK: - Cake

    /// The sponge's crumb (tileable): a warm tan crumb with pores of many sizes, a few big air holes and bright crumbs.
    static func spongeCrumb(size: Int = 512) -> CGImage? {
        let pores = TileCells(period: 22, seed: 0xCA4E1)
        let holes = TileCells(period: 7, seed: 0xCA4E2)
        let tone = TileFBM(period: 5, octaves: 3, seed: 0xCA4E3)
        let speck = TileNoise(period: 96, seed: 0xCA4E4)
        let crumb = rgb(0xF2D3A0), toast = rgb(0xE2B878), pore = rgb(0xB8894E), bright = rgb(0xFCEBC8)
        return colourImage(width: size, height: size) { _, _, u, v in
            var c = mix(crumb, toast, 0.5 * tone(u, v))
            let p = pores(u, v).x, hole = holes(u, v).x
            c = mix(c, pore, 0.75 * smooth(0.34, 0.12, p) + 0.9 * smooth(0.2, 0.08, hole))
            c = mix(c, bright, 0.6 * smooth(0.78, 0.92, speck(u, v)) * smooth(0.25, 0.4, p))
            return c
        }
    }

    static func spongeHeight(size: Int = 512) -> SurfaceField {
        let pores = TileCells(period: 22, seed: 0xCA4E1)
        let holes = TileCells(period: 7, seed: 0xCA4E2)
        let tone = TileFBM(period: 12, octaves: 2, seed: 0xCA4E5)
        return SurfaceField(width: size, height: size) { u, v in
            0.5 * tone(u, v) - 1.1 * smooth(0.34, 0.1, pores(u, v).x) - 1.6 * smooth(0.2, 0.06, holes(u, v).x)
        }
    }

    /// The crushed sponge: the crumb smeared with pink filling and cream, crumbs torn loose (tileable).
    static func spongeSmeared(size: Int = 512, filling: UInt32 = 0xF9B9CB) -> CGImage? {
        let crumb = spongeCrumb(size: size)
        let s = CGFloat(size)
        return drawn(size: size) { cg in
            if let crumb { cg.draw(crumb, in: CGRect(x: 0, y: 0, width: s, height: s)) }
            var rng = SplitMix64(seed: 0xCA4E6)
            cg.setLineCap(.round)
            for k in 0..<18 {
                let path = CGMutablePath()
                var p = CGPoint(x: CGFloat(Float.random(in: 0...1, using: &rng)) * s, y: CGFloat(Float.random(in: 0...1, using: &rng)) * s)
                let heading = CGFloat(Float.random(in: -0.5...0.5, using: &rng))
                path.move(to: p)
                for _ in 0..<5 {
                    p = CGPoint(x: p.x + cos(heading) * s * 0.06, y: p.y + sin(heading) * s * 0.06 + CGFloat(Float.random(in: -4...4, using: &rng)))
                    path.addLine(to: p)
                }
                let hex: UInt32 = k % 3 == 0 ? 0xF4E3E7 : filling
                for (width, alpha) in [(CGFloat(28), CGFloat(0.16)), (16, 0.3), (7, 0.55)] {
                    cg.setLineWidth(width * CGFloat(Float.random(in: 0.6...1.1, using: &rng)))
                    cg.setStrokeColor(colour(hex, alpha))
                    strokeWrapped(cg, path, width: s, height: s)
                }
            }
            for _ in 0..<160 {
                let x = CGFloat(Float.random(in: 0...1, using: &rng)) * s, y = CGFloat(Float.random(in: 0...1, using: &rng)) * s
                let r = CGFloat(Float.random(in: 1.5...4, using: &rng))
                cg.setFillColor(colour(rng.next() % 2 == 0 ? 0xC99A5C : 0xFBE7C2, 0.85))
                cg.fillEllipse(in: CGRect(x: x - r, y: y - r * 0.8, width: 2 * r, height: 1.6 * r))
            }
        }
    }

    /// Piped frosting (tileable): rounded ridges running round the slice, gently wavering, with nozzle grooves.
    static func pipedFrosting(size: Int = 256) -> SurfaceField {
        let waver = TileFBM(period: 3, octaves: 2, seed: 0xF7057)
        let grain = TileFBM(period: 24, octaves: 2, seed: 0xF7058)
        return SurfaceField(width: size, height: size) { u, v in
            let t = v * 5 + 0.12 * sin(2 * .pi * u * 2) + 0.18 * (waver(u, v) - 0.5)
            let ridge = pow(abs(sin(.pi * t)), 0.6)
            let grooves = 0.12 * pow(abs(sin(.pi * (t * 6))), 2)
            return 1.4 * ridge - grooves + 0.15 * grain(u, v)
        }
    }

    /// The cream top's spatula strokes and soft swirls (planar over the wedge).
    static func creamStrokes(size: Int = 512) -> SurfaceField {
        var rng = SplitMix64(seed: 0xC4EA_57)
        let s = CGFloat(size)
        var field = greyCanvas(width: size, height: size) { cg in
            cg.setLineCap(.round)
            for _ in 0..<34 {
                let c = CGPoint(x: CGFloat(Float.random(in: -0.2...1.2, using: &rng)) * s, y: CGFloat(Float.random(in: -0.2...1.2, using: &rng)) * s)
                let r = CGFloat(Float.random(in: 0.12...0.45, using: &rng)) * s
                let a0 = CGFloat(Float.random(in: 0...(2 * .pi), using: &rng))
                let sweep = CGFloat(Float.random(in: 0.5...1.4, using: &rng))
                let width = CGFloat(Float.random(in: 8...20, using: &rng))
                for (k, alpha) in [(CGFloat(1.6), CGFloat(0.08)), (1.0, 0.16), (0.5, 0.25)] {
                    cg.setLineWidth(width * k)
                    cg.setStrokeColor(gray: 1, alpha: alpha)
                    cg.addArc(center: c, radius: r, startAngle: a0, endAngle: a0 + sweep, clockwise: false)
                    cg.strokePath()
                }
            }
        }
        let soft = TileFBM(period: 10, octaves: 3, seed: 0xC4EA_58)
        field.add(SurfaceField(width: size, height: size) { u, v in soft(u, v) }, scale: 0.6)
        return field
    }

    // MARK: - Soda can

    /// The FIZZO print with fine detail (lathe UV over the straight body; image top = the shoulder): the candy field
    /// with a faint printed halftone, the white wave band, the wordmark twice round, sparse big bubbles and small
    /// clusters, a nutrition panel, a barcode, a recycling mark and small print.
    static func canLabel(seed: UInt64, width: Int = 1024, height: Int = 512) -> CGImage? {
        let w = CGFloat(width), h = CGFloat(height)
        // CG y is up; the design's rows are measured from the top, so `top(f)` is the CG y of a row f of the way down.
        func top(_ f: CGFloat) -> CGFloat { h * (1 - f) }
        return drawn(width: width, height: height) { cg in
            cg.setFillColor(colour(0x96DB4E))
            cg.fill(CGRect(x: 0, y: 0, width: w, height: h))
            // Printed halftone: fine darker dots in a grid, so the ink isn't a vector fill.
            cg.setFillColor(colour(0x7FC63A, 0.35))
            var y: CGFloat = 2
            var row = 0
            while y < h {
                var x: CGFloat = row % 2 == 0 ? 2 : 5
                while x < w {
                    cg.fillEllipse(in: CGRect(x: x, y: y, width: 1.6, height: 1.6))
                    x += 6
                }
                y += 5
                row += 1
            }
            // Fine border rules top and bottom.
            cg.setFillColor(colour(0x2F7A1E))
            cg.fill(CGRect(x: 0, y: top(0.02), width: w, height: 3))
            cg.fill(CGRect(x: 0, y: top(0.985), width: w, height: 3))
            // The white wave band (periodic so the seam matches), with a thin dark drop line under it.
            let band = CGMutablePath()
            let a = h * 0.035
            band.move(to: CGPoint(x: 0, y: top(0.56)))
            for k in 0...64 {
                let x = w * CGFloat(k) / 64
                band.addLine(to: CGPoint(x: x, y: top(0.56) - a * sin(CGFloat(k) / 64 * 4 * .pi)))
            }
            for k in stride(from: 64, through: 0, by: -1) {
                let x = w * CGFloat(k) / 64
                band.addLine(to: CGPoint(x: x, y: top(0.74) - a * sin(CGFloat(k) / 64 * 4 * .pi + 0.8)))
            }
            band.closeSubpath()
            cg.setFillColor(colour(0xFFFFFF))
            cg.addPath(band)
            cg.fillPath()
            cg.setStrokeColor(colour(0x2F7A1E, 0.9))
            cg.setLineWidth(2)
            cg.move(to: CGPoint(x: 0, y: top(0.755)))
            for k in 0...64 {
                let x = w * CGFloat(k) / 64
                cg.addLine(to: CGPoint(x: x, y: top(0.755) - a * sin(CGFloat(k) / 64 * 4 * .pi + 0.8)))
            }
            cg.strokePath()
            // Bubbles: big sparse rings, and little clusters rising beside them.
            var rng = SplitMix64(seed: seed)
            for k in 0..<7 {
                let r = CGFloat(Int(rng.next() % 20) + 14)
                let x = w * (CGFloat(k) + 0.5) / 7 + CGFloat(Int(rng.next() % 40) - 20)
                let yy = top(k % 2 == 0 ? 0.16 : 0.86) + CGFloat(Int(rng.next() % 30) - 15)
                cg.setStrokeColor(colour(0xFFFFFF, 0.85))
                cg.setLineWidth(5)
                cg.strokeEllipse(in: CGRect(x: x - r, y: yy - r, width: 2 * r, height: 2 * r))
                cg.setFillColor(colour(0xFFFFFF, 0.85))
                cg.fillEllipse(in: CGRect(x: x - r * 0.45, y: yy + r * 0.2, width: r * 0.35, height: r * 0.35))
                for j in 0..<5 {
                    let rr = CGFloat(Float.random(in: 2...6, using: &rng))
                    let bx = x + r + CGFloat(Float.random(in: 4...20, using: &rng))
                    let by = yy + CGFloat(j) * 10 - 20
                    cg.setStrokeColor(colour(0xFFFFFF, 0.7))
                    cg.setLineWidth(1.5)
                    cg.strokeEllipse(in: CGRect(x: bx - rr, y: by - rr, width: 2 * rr, height: 2 * rr))
                }
            }
            // The wordmark twice round, with a dark drop shadow and a fine white keyline.
            for k in 0..<2 {
                let cx = w * (0.25 + 0.5 * CGFloat(k))
                text(cg, "FIZZO", font: "AvenirNext-Heavy", size: h * 0.24, colour: colour(0x2F7A1E), centre: CGPoint(x: cx + 6, y: top(0.30) - 7),
                     kern: 4)
                text(cg, "FIZZO", font: "AvenirNext-Heavy", size: h * 0.24, colour: colour(0xFFFFFF), centre: CGPoint(x: cx, y: top(0.30)),
                     kern: 4)
                text(cg, "SPARKLING LIME SODA", font: "AvenirNext-DemiBold", size: h * 0.04, colour: colour(0x2F7A1E),
                     centre: CGPoint(x: cx, y: top(0.47)), kern: 3)
                text(cg, "330 ml", font: "AvenirNext-Bold", size: h * 0.035, colour: colour(0x2F7A1E), centre: CGPoint(x: cx, y: top(0.82)))
            }
            // The nutrition panel at the back (u 0.0…0.12) and the barcode in the white band.
            let panel = CGRect(x: w * 0.015, y: top(0.53), width: w * 0.1, height: h * 0.3)
            cg.setFillColor(colour(0xFFFFFF, 0.92))
            cg.fill(panel)
            cg.setStrokeColor(colour(0x1F3A12))
            cg.setLineWidth(1.5)
            cg.stroke(panel)
            text(cg, "NUTRITION", font: "Helvetica-Bold", size: 9, colour: colour(0x1F3A12),
                 centre: CGPoint(x: panel.midX, y: panel.maxY - 9))
            let lines = ["per 100 ml", "Energy 180 kJ", "Fat 0 g", "Carbs 10.6 g", "Sugars 10.6 g", "Protein 0 g", "Salt 0.01 g"]
            for (i, line) in lines.enumerated() {
                let ly = panel.maxY - 22 - CGFloat(i) * 15
                text(cg, line, font: "Helvetica", size: 8, colour: colour(0x1F3A12), centre: CGPoint(x: panel.midX, y: ly))
                cg.setFillColor(colour(0x1F3A12, 0.5))
                cg.fill(CGRect(x: panel.minX + 4, y: ly - 7, width: panel.width - 8, height: 0.8))
            }
            let code = CGRect(x: w * 0.53, y: top(0.72), width: w * 0.07, height: h * 0.1)
            cg.setFillColor(colour(0x111111))
            var bx = code.minX
            var bars = SplitMix64(seed: 0xBA2C0DE)
            while bx < code.maxX {
                let bw = CGFloat(1 + Int(bars.next() % 3))
                cg.fill(CGRect(x: bx, y: code.minY + 10, width: bw, height: code.height - 10))
                bx += bw + CGFloat(1 + Int(bars.next() % 3))
            }
            text(cg, "5 012345 678900", font: "Helvetica", size: 8, colour: colour(0x111111), centre: CGPoint(x: code.midX, y: code.minY + 4))
            // The recycling mark and small print.
            let ring = CGRect(x: w * 0.66, y: top(0.66), width: 30, height: 30)
            cg.setStrokeColor(colour(0x2F7A1E))
            cg.setLineWidth(2)
            cg.strokeEllipse(in: ring)
            text(cg, "ALU", font: "Helvetica-Bold", size: 9, colour: colour(0x2F7A1E), centre: CGPoint(x: ring.midX, y: ring.midY))
            text(cg, "PLEASE RECYCLE · BEST BEFORE END: SEE BASE · FIZZO DRINKS CO.", font: "Helvetica", size: 7,
                 colour: colour(0x1F3A12), centre: CGPoint(x: w * 0.5, y: top(0.95)), kern: 1)
            text(cg, "INGREDIENTS: CARBONATED WATER, SUGAR, LIME JUICE, NATURAL FLAVOURINGS", font: "Helvetica", size: 7,
                 colour: colour(0x1F3A12), centre: CGPoint(x: w * 0.5, y: top(0.9)), kern: 0.5)
        }
    }

    /// The can's ends seen from above (planar UV over the can's Ø): brushed aluminium in fine concentric turning marks,
    /// the rim bead, the countersink, the scored opening and the rivet, with tiny embossed lettering.
    static func canLidColour(size: Int = 512) -> CGImage? {
        let ring = TileNoise(periodX: 1, periodY: 200, seed: 0xA1D1)
        let fine = TileFBM(period: 40, octaves: 2, seed: 0xA1D2)
        let base = rgb(0xD5D9DE), dark = rgb(0xA9AFB7), bright = rgb(0xF1F3F5)
        let lid = Float(SodaLid.lidRadiusUV)
        let image = colourImage(width: size, height: size) { _, _, u, v in
            let d = SIMD2(u - 0.5, v - 0.5)
            let r = simd_length(d)
            let a = atan2(d.y, d.x)
            // Concentric turning marks, brighter in a broad band across the key direction (anisotropic sheen).
            var c = mix(base, bright, 0.25 * ring(0, r * 1.3) + 0.25 * pow(max(cos(a + 2.3), 0), 2))
            c = mix(c, dark, 0.1 * fine(u, v))
            // The countersink groove round the lid and the rim bead outside it.
            c = mix(c, dark, 0.8 * exp(-pow((r - lid) / 0.006, 2)))
            c = mix(c, bright, 0.6 * exp(-pow((r - lid - 0.022) / 0.01, 2)))
            c = mix(c, dark, 0.4 * exp(-pow((r - lid - 0.04) / 0.008, 2)))
            return c
        }
        let s = CGFloat(size)
        return drawn(size: size) { cg in
            if let image { cg.draw(image, in: CGRect(x: 0, y: 0, width: s, height: s)) }
            let c = CGPoint(x: s / 2, y: s / 2)
            // The scored opening: a rounded teardrop on the −x side (the tab's nose sits over it).
            let opening = SodaLid.openingPath(size: s)
            cg.addPath(opening)
            cg.setStrokeColor(colour(0x8A9099))
            cg.setLineWidth(2.2)
            cg.strokePath()
            cg.addPath(opening)
            cg.setStrokeColor(colour(0xF4F6F8, 0.8))
            cg.setLineWidth(0.8)
            cg.strokePath()
            // The rivet.
            let rivet = CGPoint(x: c.x + s * CGFloat(SodaLid.rivetUV), y: c.y)
            cg.setFillColor(colour(0xBFC5CC))
            cg.fillEllipse(in: CGRect(x: rivet.x - 9, y: rivet.y - 9, width: 18, height: 18))
            cg.setStrokeColor(colour(0x8A9099))
            cg.setLineWidth(1.5)
            cg.strokeEllipse(in: CGRect(x: rivet.x - 9, y: rivet.y - 9, width: 18, height: 18))
            // Embossed lettering near the rim on the +x side.
            text(cg, "RECYCLE · 330 ml", font: "Helvetica-Bold", size: 10, colour: colour(0x9AA1AA),
                 centre: CGPoint(x: c.x + s * 0.2, y: c.y - s * 0.22), angle: 0.5)
        }
    }

    /// The can ends' height: turning marks, the countersink groove, the bead, the scored opening and the rivet.
    static func canLidHeight(size: Int = 512) -> SurfaceField {
        let ring = TileNoise(periodX: 1, periodY: 200, seed: 0xA1D1)
        let lid = Float(SodaLid.lidRadiusUV)
        var field = SurfaceField(width: size, height: size) { u, v in
            let r = simd_length(SIMD2(u - 0.5, v - 0.5))
            var h = 0.3 * ring(0, r * 1.3)
            h -= 1.6 * exp(-pow((r - lid) / 0.005, 2))
            h += 1.2 * exp(-pow((r - lid - 0.022) / 0.012, 2))
            return h
        }
        let s = CGFloat(size)
        let marks = greyCanvas(width: size, height: size) { cg in
            cg.addPath(SodaLid.openingPath(size: s))
            cg.setLineWidth(2.2)
            cg.strokePath()
        }
        field.add(marks, scale: -1.2)
        let rivet = greyCanvas(width: size, height: size) { cg in
            let p = CGPoint(x: s / 2 + s * CGFloat(SodaLid.rivetUV), y: s / 2)
            cg.fillEllipse(in: CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16))
        }
        field.add(rivet, scale: 1.4)
        return field
    }

    // MARK: - Egg

    /// The shell's inside: the white membrane, fibrous and a little wrinkled (tileable).
    static func eggMembrane(size: Int = 256) -> CGImage? {
        let fibres = eggFibres(size: size)
        let tone = TileFBM(period: 4, octaves: 3, seed: 0xE6E1)
        let base = rgb(0xFFF8EC), fibre = rgb(0xEEE2CC), glow = rgb(0xFFFDF6)
        return colourImage(width: size, height: size) { x, y, u, v in
            let c = mix(base, glow, 0.5 * tone(u, v))
            return mix(c, fibre, 0.7 * fibres.values[y * size + x])
        }
    }

    static func eggFibres(size: Int = 256) -> SurfaceField {
        var rng = SplitMix64(seed: 0xE6E2)
        let s = CGFloat(size)
        return greyCanvas(width: size, height: size) { cg in
            cg.setLineCap(.round)
            for _ in 0..<140 {
                let path = CGMutablePath()
                var p = CGPoint(x: CGFloat(Float.random(in: 0...1, using: &rng)) * s, y: CGFloat(Float.random(in: 0...1, using: &rng)) * s)
                var heading = CGFloat(Float.random(in: 0...(2 * .pi), using: &rng))
                path.move(to: p)
                for _ in 0..<4 {
                    heading += CGFloat(Float.random(in: -0.6...0.6, using: &rng))
                    p = CGPoint(x: p.x + cos(heading) * 8, y: p.y + sin(heading) * 8)
                    path.addLine(to: p)
                }
                cg.setLineWidth(CGFloat(Float.random(in: 0.6...1.6, using: &rng)))
                cg.setStrokeColor(gray: 1, alpha: CGFloat(Float.random(in: 0.25...0.7, using: &rng)))
                strokeWrapped(cg, path, width: s, height: s)
            }
        }
    }

    // MARK: - Bubble wrap

    /// The film's long soft creases and fine handling marks (planar over the sheet).
    static func filmCreases(size: Int = 512) -> SurfaceField {
        var rng = SplitMix64(seed: 0xB0BB_F11)
        let s = CGFloat(size)
        var field = greyCanvas(width: size, height: size) { cg in
            cg.setLineCap(.round)
            for _ in 0..<12 {
                let p0 = CGPoint(x: CGFloat(Float.random(in: -0.1...1.1, using: &rng)) * s, y: CGFloat(Float.random(in: -0.1...1.1, using: &rng)) * s)
                let a = CGFloat(Float.random(in: 0...(2 * .pi), using: &rng))
                let l = CGFloat(Float.random(in: 0.3...0.9, using: &rng)) * s
                let bend = CGFloat(Float.random(in: -0.2...0.2, using: &rng)) * l
                let p1 = CGPoint(x: p0.x + cos(a) * l, y: p0.y + sin(a) * l)
                let mid = CGPoint(x: (p0.x + p1.x) / 2 - sin(a) * bend, y: (p0.y + p1.y) / 2 + cos(a) * bend)
                for (width, alpha) in [(CGFloat(16), CGFloat(0.08)), (7, 0.18), (2, 0.5)] {
                    cg.setLineWidth(width)
                    cg.setStrokeColor(gray: 1, alpha: alpha)
                    cg.move(to: p0)
                    cg.addQuadCurve(to: p1, control: mid)
                    cg.strokePath()
                }
            }
        }
        let fine = TileFBM(period: 32, octaves: 2, seed: 0xB0BB_F12)
        field.add(SurfaceField(width: size, height: size) { u, v in fine(u, v) }, scale: 0.25)
        return field
    }

    /// The popped crater's crinkle: sharp cellular folds (planar, unit radius → uv radius 0.42).
    static func craterCrinkle(size: Int = 256) -> SurfaceField {
        let cells = TileCells(period: 9, seed: 0xC41C)
        let fine = TileCells(period: 21, seed: 0xC41D)
        return SurfaceField(width: size, height: size) { u, v in
            let a = cells(u, v), b = fine(u, v)
            return 1.2 * (a.y - a.x) + 0.5 * (b.y - b.x)
        }
    }

    /// The air cushion's light: a soft bright ring high on the crown and a faint one at the foot (dome v 0 foot … 1 top),
    /// used as the dome's glow so the domes read as pillows of air even when the translucent layers sort badly.
    static func domeLight(height: Int = 128) -> CGImage? {
        colourImage(width: 4, height: height) { _, _, _, v in
            let crown = exp(-pow((v - 0.62) / 0.09, 2))
            let foot = 0.35 * exp(-pow((v - 0.12) / 0.06, 2))
            return SIMD3(repeating: crown + foot)
        }
    }

    // MARK: - Crayon box

    /// Plain cardboard fibre (tileable): the tray's floor and the walls' inside.
    static func kraft(size: Int = 256, hex: UInt32 = 0xEDB84A) -> CGImage? {
        let fibre = TileFBM(periodX: 4, periodY: 64, octaves: 2, seed: 0x6A4F)
        let tone = TileFBM(period: 5, octaves: 3, seed: 0x6A50)
        let speck = TileNoise(period: 128, seed: 0x6A51)
        let base = rgb(hex)
        return colourImage(width: size, height: size) { _, _, u, v in
            var c = base * (0.92 + 0.12 * tone(u, v) + 0.06 * (fibre(u, v) - 0.5))
            if speck(u, v) > 0.86 { c *= 0.85 }
            return c
        }
    }

    /// The box's long wall print (u along the wall, v up it; image top = the wall's top edge): printed yellow board with
    /// a rainbow of crayon tips along the top, the green band with the WAXO wordmark, "7 WAX CRAYONS", small print, and
    /// wear on the edges.
    static func crayonBoxFront(width: Int = 1024, height: Int = 256) -> CGImage? {
        let w = CGFloat(width), h = CGFloat(height)
        let rainbow: [UInt32] = [0xE8336F, 0xFF8A1F, 0xFFE14D, 0x8BD448, 0x37C9C0, 0x2F5BEA, 0x8E5CF0]
        let board = kraft(size: 256, hex: 0xFFC83A)
        return drawn(width: width, height: height) { cg in
            if let board {
                for k in 0..<4 { cg.draw(board, in: CGRect(x: CGFloat(k) * h, y: 0, width: h, height: h)) }
            }
            // Crayon tips along the top edge, in rainbow order.
            let tips = 14
            for k in 0..<tips {
                let x0 = w * CGFloat(k) / CGFloat(tips), x1 = w * CGFloat(k + 1) / CGFloat(tips)
                let path = CGMutablePath()
                path.move(to: CGPoint(x: x0 + 3, y: h * 0.72))
                path.addLine(to: CGPoint(x: x0 + 3, y: h * 0.84))
                path.addLine(to: CGPoint(x: (x0 + x1) / 2, y: h * 0.97))
                path.addLine(to: CGPoint(x: x1 - 3, y: h * 0.84))
                path.addLine(to: CGPoint(x: x1 - 3, y: h * 0.72))
                path.closeSubpath()
                cg.setFillColor(colour(rainbow[k % rainbow.count]))
                cg.addPath(path)
                cg.fillPath()
                cg.setStrokeColor(colour(0x5A3A08, 0.6))
                cg.setLineWidth(1.5)
                cg.addPath(path)
                cg.strokePath()
            }
            // The green band with its keylines.
            cg.setFillColor(colour(0x2E8B45))
            cg.fill(CGRect(x: 0, y: h * 0.28, width: w, height: h * 0.34))
            cg.setFillColor(colour(0xFFF4DC))
            cg.fill(CGRect(x: 0, y: h * 0.62, width: w, height: 3))
            cg.fill(CGRect(x: 0, y: h * 0.28 - 3, width: w, height: 3))
            for k in 0..<2 {
                let cx = w * (0.25 + 0.5 * CGFloat(k))
                text(cg, "WAXO", font: "AvenirNext-Heavy", size: h * 0.3, colour: colour(0x15542A), centre: CGPoint(x: cx + 3, y: h * 0.45 - 3),
                     kern: 6)
                text(cg, "WAXO", font: "AvenirNext-Heavy", size: h * 0.3, colour: colour(0xFFFFFF), centre: CGPoint(x: cx, y: h * 0.45), kern: 6)
                text(cg, "7 WAX CRAYONS", font: "AvenirNext-Bold", size: h * 0.1, colour: colour(0x2E5A12), centre: CGPoint(x: cx, y: h * 0.16),
                     kern: 2)
            }
            text(cg, "NON-TOXIC · AGES 3+ · MADE FOR PRESSING", font: "Helvetica", size: h * 0.045, colour: colour(0x5A3A08),
                 centre: CGPoint(x: w * 0.5, y: h * 0.06), kern: 1)
            // Wear: pale scuffs along the top and bottom edges and at the corners.
            var rng = SplitMix64(seed: 0xC4A7_5C)
            for _ in 0..<60 {
                let x = CGFloat(Float.random(in: 0...1, using: &rng)) * w
                let atTop = rng.next() % 2 == 0
                let y = atTop ? h - CGFloat(Float.random(in: 0...8, using: &rng)) : CGFloat(Float.random(in: 0...8, using: &rng))
                cg.setFillColor(colour(0xFFF0C8, CGFloat(Float.random(in: 0.3...0.7, using: &rng))))
                cg.fill(CGRect(x: x, y: y, width: CGFloat(Float.random(in: 3...16, using: &rng)), height: 2))
            }
        }
    }

    /// The box's end-wall print: a big 7 in a rainbow ring and the wordmark (u across the end, v up it).
    static func crayonBoxEnd(width: Int = 512, height: Int = 256) -> CGImage? {
        let w = CGFloat(width), h = CGFloat(height)
        let rainbow: [UInt32] = [0xE8336F, 0xFF8A1F, 0xFFE14D, 0x8BD448, 0x37C9C0, 0x2F5BEA, 0x8E5CF0]
        let board = kraft(size: 256, hex: 0xFFC83A)
        return drawn(width: width, height: height) { cg in
            if let board {
                cg.draw(board, in: CGRect(x: 0, y: 0, width: h, height: h))
                cg.draw(board, in: CGRect(x: h, y: 0, width: h, height: h))
            }
            let c = CGPoint(x: w * 0.5, y: h * 0.5)
            for (k, hex) in rainbow.enumerated() {
                let a0 = CGFloat(k) / 7 * 2 * .pi, a1 = CGFloat(k + 1) / 7 * 2 * .pi
                cg.setStrokeColor(colour(hex))
                cg.setLineWidth(h * 0.08)
                cg.addArc(center: c, radius: h * 0.34, startAngle: a0, endAngle: a1, clockwise: false)
                cg.strokePath()
            }
            cg.setFillColor(colour(0x2E8B45))
            cg.fillEllipse(in: CGRect(x: c.x - h * 0.29, y: c.y - h * 0.29, width: h * 0.58, height: h * 0.58))
            text(cg, "7", font: "AvenirNext-Heavy", size: h * 0.45, colour: colour(0xFFFFFF), centre: c)
            text(cg, "WAXO", font: "AvenirNext-Heavy", size: h * 0.12, colour: colour(0x2E8B45), centre: CGPoint(x: w * 0.15, y: h * 0.5),
                 angle: .pi / 2)
            text(cg, "WAXO", font: "AvenirNext-Heavy", size: h * 0.12, colour: colour(0x2E8B45), centre: CGPoint(x: w * 0.85, y: h * 0.5),
                 angle: -.pi / 2)
        }
    }

    /// One crayon's paper wrap (u round the crayon, v along it; image top = the tip end): cream paper with fibres, the
    /// colour band with black keylines, the WAXO wordmark and the colour's name along the crayon, two thin end stripes,
    /// and the glued overlap seam.
    static func crayonWrap(band: UInt32, name: String, width: Int = 256, height: Int = 512) -> CGImage? {
        let w = CGFloat(width), h = CGFloat(height)
        let paper = kraft(size: 256, hex: 0xF4ECDD)
        return drawn(width: width, height: height) { cg in
            if let paper {
                cg.draw(paper, in: CGRect(x: 0, y: 0, width: w, height: w))
                cg.draw(paper, in: CGRect(x: 0, y: w, width: w, height: w))
            }
            cg.setFillColor(colour(band))
            cg.fill(CGRect(x: 0, y: h * 0.06, width: w, height: h * 0.035))
            cg.fill(CGRect(x: 0, y: h * 0.905, width: w, height: h * 0.035))
            cg.fill(CGRect(x: 0, y: h * 0.24, width: w, height: h * 0.52))
            cg.setFillColor(colour(0x1A1A1A))
            cg.fill(CGRect(x: 0, y: h * 0.24 - 2, width: w, height: 2))
            cg.fill(CGRect(x: 0, y: h * 0.76, width: w, height: 2))
            // A fine zigzag rule on the band's edges.
            cg.setStrokeColor(colour(0xFFFFFF, 0.8))
            cg.setLineWidth(1.5)
            for y0 in [h * 0.27, h * 0.73] {
                cg.move(to: CGPoint(x: 0, y: y0))
                var x: CGFloat = 0
                var up = true
                while x < w {
                    x += 6
                    cg.addLine(to: CGPoint(x: x, y: y0 + (up ? 4 : -4)))
                    up.toggle()
                }
                cg.strokePath()
            }
            for k in 0..<2 {
                let cx = w * (0.25 + 0.5 * CGFloat(k))
                text(cg, "WAXO", font: "AvenirNext-Heavy", size: w * 0.2, colour: colour(0xFFFFFF), centre: CGPoint(x: cx, y: h * 0.56),
                     angle: .pi / 2, kern: 4)
                text(cg, name, font: "AvenirNext-Bold", size: w * 0.07, colour: colour(0x1A1A1A), centre: CGPoint(x: cx, y: h * 0.17),
                     angle: .pi / 2, kern: 1)
            }
            // The glued overlap seam at u 0.
            cg.setFillColor(colour(0x000000, 0.12))
            cg.fill(CGRect(x: 0, y: 0, width: 3, height: h))
            cg.setFillColor(colour(0xFFFFFF, 0.25))
            cg.fill(CGRect(x: 3, y: 0, width: 1.5, height: h))
        }
    }

    /// The wax's sheen breakup (lathe UV, v along the crayon): streaky, slightly worn. 0.6…1.
    static func waxSheen(size: Int = 256) -> CGImage? {
        let streaks = TileFBM(periodX: 16, periodY: 3, octaves: 3, seed: 0x3A6)
        let field = SurfaceField(width: size, height: size) { u, v in streaks(u, v) }
        return greyImage(field, range: 0.6...1)
    }

    /// A pressed wax smear (planar, the smear's long axis along u): drag streaks, ridged edges and scrape marks. Grey
    /// (tinted by the crayon's colour); its height is `waxSmearHeight`.
    static func waxSmear(size: Int = 512) -> CGImage? {
        let drag = TileFBM(periodX: 2, periodY: 56, octaves: 3, seed: 0x5EA1)
        let blot = TileFBM(period: 6, octaves: 2, seed: 0x5EA2)
        return colourImage(width: size, height: size) { _, _, u, v in
            let r = simd_length(SIMD2(u - 0.5, v - 0.5)) / 0.4
            let ridge = smooth(0.72, 0.95, r) * smooth(1.1, 0.95, r)
            let k = 0.72 + 0.22 * drag(u, v) + 0.12 * blot(u, v) + 0.2 * ridge
            return SIMD3(repeating: min(k, 1))
        }
    }

    static func waxSmearHeight(size: Int = 512) -> SurfaceField {
        let drag = TileFBM(periodX: 2, periodY: 56, octaves: 3, seed: 0x5EA1)
        return SurfaceField(width: size, height: size) { u, v in
            let r = simd_length(SIMD2(u - 0.5, v - 0.5)) / 0.4
            return 1.2 * drag(u, v) + 1.5 * smooth(0.7, 0.95, r) * smooth(1.1, 0.95, r)
        }
    }

    // MARK: - The Unsquishable (sphere UV: u round, v pole to pole)

    /// Machined steel: fine turning rings round the ball and a few micro-scratches (height).
    static func machinedSteel(width: Int = 1024, height: Int = 512) -> SurfaceField {
        let wobble = TileFBM(periodX: 6, periodY: 3, octaves: 2, seed: 0xBA11_1)
        var field = SurfaceField(width: width, height: height) { u, v in
            0.25 * sin(2 * .pi * (v * 110 + 0.6 * wobble(u, v)))
        }
        var rng = SplitMix64(seed: 0xBA11_2)
        let w = CGFloat(width), h = CGFloat(height)
        let scratches = greyCanvas(width: width, height: height) { cg in
            cg.setLineCap(.round)
            for _ in 0..<70 {
                let p = CGPoint(x: CGFloat(Float.random(in: 0...1, using: &rng)) * w, y: CGFloat(Float.random(in: 0.1...0.9, using: &rng)) * h)
                let a = CGFloat(Float.random(in: 0...(2 * .pi), using: &rng))
                let l = CGFloat(Float.random(in: 6...40, using: &rng))
                cg.setLineWidth(CGFloat(Float.random(in: 0.6...1.2, using: &rng)))
                cg.setStrokeColor(gray: 1, alpha: CGFloat(Float.random(in: 0.3...0.8, using: &rng)))
                cg.move(to: p)
                cg.addLine(to: CGPoint(x: p.x + cos(a) * l, y: p.y + sin(a) * l * 0.5))
                cg.strokePath()
            }
        }
        field.add(scratches, scale: -0.6)
        return field
    }

    /// The steel's specular breakup: a near-mirror with faint smudges and the scratches a little rougher. 0.2…1.
    static func steelBreakup(width: Int = 512, height: Int = 256) -> CGImage? {
        let smudge = TileFBM(periodX: 8, periodY: 4, octaves: 4, seed: 0xBA11_3)
        let field = SurfaceField(width: width, height: height) { u, v in
            0.1 + 0.9 * smooth(0.55, 0.8, smudge(u, v))
        }
        return greyImage(field, range: 0.2...1)
    }
}

/// The can lid's layout in its planar UV (the can's ends map x, z over ±`ObjectMeshes.canR` · 0.045).
enum SodaLid {
    /// The can's outer radius (the planar map's half size), metres.
    static let mapRadius: Float = 0.045 * ObjectMeshes.canR
    /// The lid's flat radius in UV units (0.5 = the can's outer radius).
    static let lidRadiusUV: Float = 0.5 * 0.0335 / 0.045
    /// The rivet's UV offset along +x (the tab sits over it).
    static let rivetUV: Float = 0.5 * 0.003 / 0.045

    /// The scored opening (a rounded teardrop on the −x side), in a `size`² CG context.
    static func openingPath(size s: CGFloat) -> CGPath {
        let c = CGPoint(x: s / 2, y: s / 2)
        let path = CGMutablePath()
        let near = c.x - s * 0.02, far = c.x - s * 0.24
        path.move(to: CGPoint(x: near, y: c.y + s * 0.05))
        path.addQuadCurve(to: CGPoint(x: far, y: c.y + s * 0.07), control: CGPoint(x: c.x - s * 0.13, y: c.y + s * 0.1))
        path.addQuadCurve(to: CGPoint(x: far, y: c.y - s * 0.07), control: CGPoint(x: far - s * 0.06, y: c.y))
        path.addQuadCurve(to: CGPoint(x: near, y: c.y - s * 0.05), control: CGPoint(x: c.x - s * 0.13, y: c.y - s * 0.1))
        path.closeSubpath()
        return path
    }
}
