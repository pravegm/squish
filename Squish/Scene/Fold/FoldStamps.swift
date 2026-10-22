import CoreGraphics
import Foundation
import UIKit

// The platen's prints (design/FOLD-PRESS.md §3.2): hand-authored top-down CoreGraphics outlines of every object,
// matched to its 3D build (sizes, yaw and apex from Scene/Objects/*), plus the per-object fracture and failure
// stamps. Everything is deterministic from the press seed and pure CG, so none of it needs the main actor.
//
// Print space: points, origin at the footprint centre, x = anvil x, y = anvil z (toward the anvil's front edge).
// The platen shows print space mirrored across the crease (`FoldLayout.platenPrintTransform`).

/// How the platen first meets the object.
enum FoldContact: Equatable, Sendable {
    /// A single apex (most objects): the print grows from there.
    case point
    /// Along the long axis (crayon, lying bottle): the kiss is a line.
    case line
    /// Everywhere at once (bubble wrap's domes): the print fills in density, not in radius.
    case uniform
    /// A tiny bright ring that never grows (the Unsquishable).
    case fixedRing
}

/// One object's print signature.
struct FoldStamp: @unchecked Sendable {
    let kind: ObjectKind
    /// Full top-down outline, print space.
    let silhouette: CGPath
    /// Interior lines drawn into the ink (bubble domes, the duck's wings).
    let details: CGPath?
    let apex: CGPoint
    /// Radii of the growth ellipse at full coverage, and its rotation (print space).
    let growthRadii: CGSize
    let growthAngle: CGFloat
    let contact: FoldContact
    let ink: UIColor
    let inkEdge: UIColor
    let inkAlpha: CGFloat
    /// Object-specific anchor points in print space (bubble cells in layout order, the duck's beak, seams, cuts).
    let features: [CGPoint]
    /// Feature size (bubble dome radius, can rim), points.
    let featureRadius: CGFloat
    /// Points per scene metre for this object (P-48 asset metres × 340 mm × foldScale × pt/mm).
    let pointsPerMetre: CGFloat
    let yawRadians: Double
    let seed: UInt64
    let golden: Bool
    /// The bubble wrap's pop order (fracture index → cell), mirrored from BubbleWrapView.
    let popOrder: [Int]

    /// The radius a full-coverage circular print needs, for sprite sizing.
    var fullRadius: CGFloat { max(growthRadii.width, growthRadii.height) }
}

/// What a fracture asks the platen to do besides stamping.
enum FoldPrintEffect: Equatable, Sendable {
    case none
    /// An expanding pressure ring (the duck's honk) from a print-space centre.
    case ripple(CGPoint, CGFloat)
    /// The Unsquishable's groan: the bright ring pulses.
    case pulse
    /// The press loses (§3.2): crack the platen's strike plate, pop a bolt, crack the gauge glass.
    case platenBreaks
}

/// A fixed canvas for every print-space image: the strike plate plus 40 pt (§2.3 spread clamp).
enum FoldPrintCanvas {
    static let rect = CGRect(x: -(FoldMetrics.plateLateral / 2 + 40), y: -(FoldMetrics.plateDepth / 2 + 40),
                             width: FoldMetrics.plateLateral + 80, height: FoldMetrics.plateDepth + 80)
}

enum FoldStamps {
    // MARK: Object outlines

    /// Object-local metres (x, z) → print points, applying the entity's yaw (rotation about +y).
    struct LocalMap {
        let k: Double
        let yaw: Double

        func callAsFunction(_ x: Double, _ z: Double) -> CGPoint {
            let c = cos(yaw), s = sin(yaw)
            return CGPoint(x: k * (x * c + z * s), y: k * (-x * s + z * c))
        }

        var transform: CGAffineTransform {
            let c = cos(yaw), s = sin(yaw)
            return CGAffineTransform(a: k * c, b: -k * s, c: k * s, d: k * c, tx: 0, ty: 0)
        }
    }

    /// The 3D object's entity yaw (degrees), from Scene/Objects.
    static func yawDegrees(_ kind: ObjectKind) -> Double {
        switch kind {
        case .bubbleWrap: 12
        case .rubberDuck: -30
        case .jelly: 0
        case .crayon: -20
        case .egg: -20
        case .cakeSlice: atan2(0.6, 0.8) * 180 / .pi
        case .sodaCan: -15
        case .gummyBear: 10
        case .glassBottle: -15
        case .unsquishable: 0
        }
    }

    /// `extraYaw` (degrees): the fold stage's own turn of the object (book pose faces objects at the eye).
    static func stamp(for kind: ObjectKind, variant: PressVariant, foldScale: Double, extraYaw: Double = 0) -> FoldStamp {
        let k = FoldMetrics.mmPerSceneMetre * foldScale * FoldMetrics.pointsPerMM
        let yaw = (yawDegrees(kind) + extraYaw) * .pi / 180
        let map = LocalMap(k: k, yaw: yaw)
        let t = map.transform
        let path = CGMutablePath()
        var details: CGMutablePath?
        var apex = CGPoint.zero
        var radii = (0.05, 0.05)
        var contact = FoldContact.point
        var features: [CGPoint] = []
        var featureRadius: CGFloat = 0
        var popOrder: [Int] = []

        func ellipse(_ x: Double, _ z: Double, _ rx: Double, _ rz: Double, into p: CGMutablePath) {
            p.addEllipse(in: CGRect(x: x - rx, y: z - rz, width: 2 * rx, height: 2 * rz), transform: t)
        }
        func polygon(_ points: [SIMD2<Double>], into p: CGMutablePath) {
            guard let first = points.first else { return }
            p.move(to: CGPoint(x: first.x, y: first.y), transform: t)
            for q in points.dropFirst() { p.addLine(to: CGPoint(x: q.x, y: q.y), transform: t) }
            p.closeSubpath()
        }
        /// A lying lathe (axis along local x, centred on its length) seen from above: its profile, mirrored.
        func lyingProfile(_ profile: [SIMD2<Double>], length: Double) -> [SIMD2<Double>] {
            let top = profile.map { SIMD2($0.y - length / 2, -$0.x) }
            let bottom = profile.reversed().map { SIMD2($0.y - length / 2, $0.x) }
            return top + bottom
        }

        switch kind {
        case .bubbleWrap:
            path.addRoundedRect(in: CGRect(x: -0.055, y: -0.045, width: 0.110, height: 0.090),
                                cornerWidth: 0.006, cornerHeight: 0.006, transform: t)
            let rings = CGMutablePath()
            for row in 0..<BubbleWrapLayout.rows {
                for column in 0..<BubbleWrapLayout.columns {
                    let x = 0.0175 * (Double(column) - Double(BubbleWrapLayout.columns - 1) / 2)
                    let z = 0.0195 * (Double(row) - Double(BubbleWrapLayout.rows - 1) / 2)
                    ellipse(x, z, 0.0075, 0.0075, into: rings)
                    features.append(map(x, z))
                }
            }
            details = rings
            featureRadius = CGFloat(0.0075 * k)
            radii = (0.074, 0.074)
            contact = .uniform
            // Mirrors BubbleWrapView: the pop order is the first use of SplitMix64(seed ^ 0xB0BB1E).
            var rng = SplitMix64(seed: variant.seed ^ 0xB0BB1E)
            popOrder = Array(0..<BubbleWrapLayout.count).shuffled(using: &rng)
        case .rubberDuck:
            ellipse(0, 0, 0.038, 0.029, into: path)
            ellipse(0.019, 0, 0.021, 0.021, into: path)
            ellipse(-0.032, 0, 0.014, 0.015, into: path)
            ellipse(0.020, 0, 0.023, 0.023, into: path)
            for side in [-1.0, 1.0] { ellipse(-0.002, 0.026 * side, 0.020, 0.006, into: path) }
            ellipse(0.044, 0, 0.012, 0.009, into: path)
            let wings = CGMutablePath()
            for side in [-1.0, 1.0] { ellipse(-0.004, 0.022 * side, 0.016, 0.004, into: wings) }
            details = wings
            apex = map(0.020, 0)
            radii = (0.068, 0.068)
            features = [map(0.050, 0), map(-0.045, 0), map(0.032, 0)]   // beak tip, seam ends
        case .jelly:
            var pts: [SIMD2<Double>] = []
            for i in 0..<120 {
                let a = Double(i) / 120 * 2 * .pi
                let r = 0.0475 + 0.0022 * cos(10 * a)
                pts.append(SIMD2(r * cos(a), r * sin(a)))
            }
            polygon(pts, into: path)
            radii = (0.050, 0.050)
            features = [map(0.008, -0.022), map(0.030, 0.020)]   // the skin split
        case .crayon:
            let profile: [SIMD2<Double>] = [
                SIMD2(0.000, 0.000), SIMD2(0.0095, 0.000), SIMD2(0.0110, 0.0015), SIMD2(0.0110, 0.0880),
                SIMD2(0.0045, 0.1050), SIMD2(0.0025, 0.1090), SIMD2(0.0010, 0.1120), SIMD2(0.000, 0.1130),
            ]
            polygon(lyingProfile(profile, length: 0.113), into: path)
            radii = (0.058, 0.0115)
            contact = .line
            // Mirrors CrayonView: the two cut planes are the first draws of SplitMix64(seed ^ 0xC4A7).
            var rng = SplitMix64(seed: variant.seed ^ 0xC4A7)
            let cut1 = Double(Float.random(in: 0.030...0.048, using: &rng))
            let cut2 = Double(Float.random(in: 0.062...0.080, using: &rng))
            features = [map(cut1 - 0.0565, 0), map(cut2 - 0.0565, 0), map(-0.0565, 0), map(0.0565, 0)]
            featureRadius = CGFloat(0.0115 * k)
        case .egg:
            let profile: [SIMD2<Double>] = [
                SIMD2(0.000, 0.000), SIMD2(0.017, 0.004), SIMD2(0.026, 0.010), SIMD2(0.034, 0.020), SIMD2(0.0385, 0.032),
                SIMD2(0.0400, 0.044), SIMD2(0.0395, 0.056), SIMD2(0.0370, 0.068), SIMD2(0.0320, 0.080), SIMD2(0.0255, 0.090),
                SIMD2(0.0180, 0.098), SIMD2(0.0105, 0.104), SIMD2(0.0045, 0.108), SIMD2(0.000, 0.110),
            ]
            polygon(lyingProfile(profile, length: 0.110), into: path)
            apex = map(-0.011, 0)
            radii = (0.064, 0.041)
            features = [map(-0.011, -0.030), map(0.020, 0.028)]   // hairline ends
        case .cakeSlice:
            var pts: [SIMD2<Double>] = [SIMD2(-0.072, 0)]
            let half = 20.0 * .pi / 180
            for i in 0...12 {
                let a = -half + 2 * half * Double(i) / 12
                pts.append(SIMD2(-0.072 + 0.110 * cos(a), 0.110 * sin(a)))
            }
            polygon(pts, into: path)
            apex = map(0.006, 0.004)   // the candle (CakeSliceView.candleBase − centroid shift)
            radii = (0.080, 0.080)
            features = [map(0.006, 0.004), map(-0.072, 0), map(0.038, 0)]
        case .sodaCan:
            ellipse(0, 0, 0.045, 0.045, into: path)
            radii = (0.046, 0.046)
            featureRadius = CGFloat(0.036 * k)   // the lid rim
        case .gummyBear:
            ellipse(0, 0, 0.034, 0.026, into: path)
            ellipse(0, 0.008, 0.026, 0.026, into: path)
            ellipse(0, 0.002, 0.025, 0.025, into: path)
            ellipse(0, 0.022, 0.011, 0.011, into: path)
            for s in [-1.0, 1.0] {
                ellipse(s * 0.018, 0, 0.009, 0.009, into: path)
                ellipse(s * 0.034, 0.006, 0.011, 0.011, into: path)
                ellipse(s * 0.020, 0.020, 0.013, 0.018, into: path)
            }
            apex = map(0, 0.002)
            radii = (0.050, 0.050)
            features = [map(0, -0.030), map(0, 0.040)]   // the seam
        case .glassBottle:
            let profile: [SIMD2<Double>] = [
                SIMD2(0.000, 0.000), SIMD2(0.026, 0.0015), SIMD2(0.0295, 0.005), SIMD2(0.030, 0.010), SIMD2(0.030, 0.040),
                SIMD2(0.030, 0.075), SIMD2(0.0285, 0.088), SIMD2(0.023, 0.100), SIMD2(0.016, 0.110), SIMD2(0.0118, 0.118),
                SIMD2(0.0110, 0.130), SIMD2(0.0125, 0.133), SIMD2(0.0128, 0.138), SIMD2(0.0112, 0.1395), SIMD2(0.000, 0.1398),
            ]
            polygon(lyingProfile(profile, length: 0.1398), into: path)
            apex = map(-0.020, 0)
            radii = (0.092, 0.031)
            contact = .line
        case .unsquishable:
            ellipse(0, 0, 0.045, 0.045, into: path)
            radii = (0.045, 0.045)
            contact = .fixedRing
            featureRadius = 5
        }

        // Growth ellipse: centred on the apex, along the object's local x axis (rotated by yaw).
        let growth = CGSize(width: radii.0 * k, height: radii.1 * k)
        let (ink, edge, alpha) = inks(kind, variant: variant)
        return FoldStamp(kind: kind, silhouette: path, details: details, apex: apex, growthRadii: growth,
                         growthAngle: CGFloat(-yaw), contact: contact, ink: ink, inkEdge: edge, inkAlpha: alpha,
                         features: features, featureRadius: featureRadius, pointsPerMetre: CGFloat(k),
                         yawRadians: yaw, seed: variant.seed, golden: variant.isGolden, popOrder: popOrder)
    }

    static func inks(_ kind: ObjectKind, variant: PressVariant) -> (UIColor, UIColor, CGFloat) {
        if variant.isGolden && kind != .glassBottle { return (Palette.gold, UIColor(hex: 0xB98A1E), 0.9) }
        switch kind {
        case .bubbleWrap: return (UIColor(hex: 0xCFE8F5), UIColor(hex: 0x6FAED0), 0.55)
        case .rubberDuck: return (Palette.duckYellow, UIColor(hex: 0xE0A800), 0.92)
        case .jelly: return (Palette.raspberry, UIColor(hex: 0xB81E52), 0.78)
        case .crayon: return (Palette.cobalt, UIColor(hex: 0x1D3BA8), 0.88)
        case .egg: return (UIColor(hex: 0xF3DFC0), UIColor(hex: 0xC9A877), 0.85)
        case .cakeSlice: return (UIColor(hex: 0xFF9BCB), UIColor(hex: 0xE05FA0), 0.88)
        case .sodaCan:
            // One colour story (FOLD-REVIEW-2 #9): the seed's fizz, exactly as SodaCanView picks it.
            let fizz = canFizz(variant)
            return (fizz, darken(fizz, 0.35), 0.82)
        case .gummyBear: return (UIColor(hex: 0xFF5A4E), UIColor(hex: 0xC8203A), 0.72)
        case .glassBottle: return (UIColor(white: 1, alpha: 1), UIColor(white: 1, alpha: 1), 0.38)
        case .unsquishable: return (UIColor(white: 1, alpha: 1), Palette.ballSteel, 1)
        }
    }

    /// Mirrors SodaCanView's seeded fizz palette (first draw of SplitMix64(seed ^ 0x50DA)); the puddle colour.
    static func canFizz(_ variant: PressVariant) -> UIColor {
        if variant.isGolden { return Palette.gold }
        if variant.surprise == .cherryFizz { return Palette.cherryFizz }
        var rng = SplitMix64(seed: variant.seed ^ 0x50DA)
        let puddles = [UIColor(hex: 0xC9EFA0), UIColor(hex: 0xFFB347), UIColor(hex: 0xC77DFF)]
        return puddles[Int(rng.next() % UInt64(puddles.count))]
    }

    static func darken(_ color: UIColor, _ amount: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: r * (1 - amount), green: g * (1 - amount), blue: b * (1 - amount), alpha: a)
    }

    // MARK: Images (print space, FoldPrintCanvas.rect)

    /// Renders into a premultiplied RGBA bitmap; `draw` gets a y-down context in points whose origin is `rect.origin`.
    static func image(rect: CGRect, scale: CGFloat, _ draw: (CGContext) -> Void) -> CGImage? {
        let w = max(1, Int((rect.width * scale).rounded(.up)))
        let h = max(1, Int((rect.height * scale).rounded(.up)))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.translateBy(x: -rect.minX, y: -rect.minY)
        draw(ctx)
        return ctx.makeImage()
    }

    /// The wet ink of a full print: one soft pressing of the union outline (never the construction ellipses), ink
    /// pooled a little darker just inside the edge, lighter and wetter at the apex.
    static func inkImage(_ stamp: FoldStamp, scale: CGFloat = 2) -> CGImage? {
        let outline = stamp.silhouette.normalized(using: .winding)
        return image(rect: FoldPrintCanvas.rect, scale: scale) { ctx in
            ctx.addPath(outline)
            ctx.saveGState()
            ctx.clip()
            ctx.setFillColor(stamp.ink.withAlphaComponent(stamp.inkAlpha).cgColor)
            ctx.fill(FoldPrintCanvas.rect)
            // Pooled rim: a wide, blurred stroke of the outline, clipped inside, so the edge reads soft but clean.
            ctx.setShadow(offset: .zero, blur: 5 * scale, color: stamp.inkEdge.withAlphaComponent(0.55).cgColor)
            ctx.addPath(outline)
            ctx.setStrokeColor(stamp.inkEdge.withAlphaComponent(stamp.kind == .glassBottle ? 0.55 : 0.30).cgColor)
            ctx.setLineWidth(stamp.kind == .glassBottle ? 3 : 4)
            ctx.strokePath()
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            // The wet rim (FOLD-REVIEW-1 #6): a crisp 1.5 pt line of pooled ink just inside the edge.
            ctx.addPath(outline)
            ctx.setStrokeColor(stamp.inkEdge.withAlphaComponent(stamp.kind == .glassBottle ? 0.7 : 0.55).cgColor)
            ctx.setLineWidth(3)   // half of it falls outside the clip: 1.5 pt visible
            ctx.strokePath()
            // Mottle: ±8 % alpha, so the ink takes the steel's tooth instead of reading as a vector fill.
            var mottle = SplitMix64(seed: stamp.seed ^ 0x307)
            let box = outline.boundingBoxOfPath
            if !box.isEmpty {
                ctx.setBlendMode(.destinationOut)
                for _ in 0..<Int(min(900, box.width * box.height / 30)) {
                    let p = CGPoint(x: CGFloat.random(in: box.minX...box.maxX, using: &mottle),
                                    y: CGFloat.random(in: box.minY...box.maxY, using: &mottle))
                    let s = CGFloat.random(in: 1.5...4.5, using: &mottle)
                    ctx.setFillColor(UIColor(white: 0, alpha: CGFloat.random(in: 0.04...0.16, using: &mottle)).cgColor)
                    ctx.fillEllipse(in: CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s))
                }
                ctx.setBlendMode(.normal)
            }
            let wet = [UIColor(white: 1, alpha: 0.24).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: wet, locations: [0, 1]) {
                ctx.drawRadialGradient(gradient, startCenter: stamp.apex, startRadius: 0, endCenter: stamp.apex,
                                       endRadius: stamp.fullRadius * 0.6, options: [])
            }
            // Only bubble wrap keeps interior marks: each dome really does touch the plate as its own circle.
            if stamp.kind == .bubbleWrap, let details = stamp.details {
                ctx.addPath(details)
                ctx.setStrokeColor(stamp.inkEdge.withAlphaComponent(0.30).cgColor)
                ctx.setLineWidth(1)
                ctx.strokePath()
            }
            ctx.restoreGState()
        }
    }

    /// The silhouette as a solid alpha mask (white).
    static func maskImage(_ stamp: FoldStamp, scale: CGFloat = 2) -> CGImage? {
        image(rect: FoldPrintCanvas.rect, scale: scale) { ctx in
            ctx.addPath(stamp.silhouette)
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fillPath()
        }
    }

    /// The approach shadow (§3.2 step 1): the outline in shadow ink, pre-blurred by `blur` points.
    static func shadowImage(_ stamp: FoldStamp, blur: CGFloat, scale: CGFloat = 1) -> CGImage? {
        let rect = FoldPrintCanvas.rect
        return image(rect: rect, scale: scale) { ctx in
            // Draw the shape off-canvas and keep only its shadow (CG shadow params are in device pixels).
            let shift = rect.width + 4 * blur
            ctx.setShadow(offset: CGSize(width: -shift * scale, height: 0), blur: blur * scale,
                          color: Palette.shadowInk.cgColor)
            ctx.translateBy(x: shift, y: 0)
            ctx.addPath(stamp.silhouette)
            ctx.setFillColor(Palette.shadowInk.cgColor)
            ctx.fillPath()
        }
    }

    /// A white disc with a soft edge (`feather` as a fraction of the radius), unit-agnostic: used as the growth mask.
    static func softDisc(size: Int = 256, feather: CGFloat = 0.10, color: UIColor = .white) -> CGImage? {
        let s = CGFloat(size)
        return image(rect: CGRect(x: 0, y: 0, width: s, height: s), scale: 1) { ctx in
            let c = CGPoint(x: s / 2, y: s / 2)
            let colors = [color.cgColor, color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1 - feather, 1]) {
                ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: s / 2, options: [])
            }
        }
    }

    /// Newton's rings (§3.2 step 3): faint iridescent bands just outside the unit radius (the sprite's 80 %).
    static func newtonRings(size: Int = 256) -> CGImage? {
        let s = CGFloat(size)
        return image(rect: CGRect(x: 0, y: 0, width: s, height: s), scale: 1) { ctx in
            let c = CGPoint(x: s / 2, y: s / 2)
            let bands: [(CGFloat, UIColor)] = [
                (0.80, UIColor(hex: 0xFFD27A)), (0.84, UIColor(hex: 0x8FD3FF)), (0.88, UIColor(hex: 0xF29BFF)),
                (0.92, UIColor(hex: 0xA6F0B0)), (0.96, UIColor(hex: 0xFFE7A6)),
            ]
            for (r, color) in bands {
                ctx.setStrokeColor(color.withAlphaComponent(0.9).cgColor)
                ctx.setLineWidth(s * 0.018)
                ctx.strokeEllipse(in: CGRect(x: c.x - r * s / 2, y: c.y - r * s / 2, width: r * s, height: r * s))
            }
        }
    }

    // MARK: Stamps

    /// Draws the stamp for one fracture into the accumulating print decal (print space) and returns any live effect.
    static func drawFracture(index: Int, isFailure: Bool, stamp: FoldStamp, into ctx: CGContext) -> FoldPrintEffect {
        var rng = SplitMix64(seed: stamp.seed &+ UInt64(index + 1) &* 0x9E37)
        let k = stamp.pointsPerMetre
        switch stamp.kind {
        case .bubbleWrap:
            guard !stamp.popOrder.isEmpty, !stamp.features.isEmpty else { return .none }
            let cell = stamp.popOrder[index % stamp.popOrder.count]
            guard cell < stamp.features.count else { return .none }
            let p = stamp.features[cell]
            let r = stamp.featureRadius
            fillDisc(ctx, p, r * 0.95, (stamp.golden ? Palette.gold : UIColor(hex: 0x9CCBE6)).withAlphaComponent(0.55))
            ring(ctx, p, r, 1.8, (stamp.golden ? UIColor(hex: 0xB98A1E) : UIColor(hex: 0x3E93C2)).withAlphaComponent(0.95))
            return .none
        case .rubberDuck:
            if isFailure {
                if stamp.features.count >= 3 {
                    crack(ctx, from: stamp.features[1], to: stamp.features[2], segments: 7, jitter: 3, width: 2.4,
                          color: UIColor(hex: 0x8A5A00).withAlphaComponent(0.8), rng: &rng)
                    // The beak spot: an inked blob, not a flat disc (FOLD-REVIEW-2 #12).
                    blob(ctx, stamp.features[0], 0.010 * k, lobes: 5,
                         (stamp.golden ? Palette.gold : Palette.beakOrange).withAlphaComponent(0.78), rng: &rng)
                }
                return .none
            }
            return .ripple(stamp.apex, stamp.fullRadius * 0.5)
        case .jelly:
            if !isFailure, stamp.features.count >= 2 {
                crack(ctx, from: stamp.features[0], to: stamp.features[1], segments: 6, jitter: 4, width: 2,
                      color: UIColor(hex: 0xFF9DBA).withAlphaComponent(0.9), rng: &rng)
            }
            return .none
        case .crayon:
            if index <= 1, stamp.features.count >= 2 {
                // A snap: a clean gap across the waxy strip.
                let p = stamp.features[index]
                let half = stamp.featureRadius * 1.25
                let n = CGPoint(x: -sin(CGFloat(-stamp.yawRadians)), y: cos(CGFloat(-stamp.yawRadians)))
                ctx.setStrokeColor(Palette.plateSteel.cgColor)
                ctx.setLineWidth(3.2)
                ctx.setLineCap(.round)
                ctx.move(to: CGPoint(x: p.x - n.x * half, y: p.y - n.y * half))
                ctx.addLine(to: CGPoint(x: p.x + n.x * half, y: p.y + n.y * half))
                ctx.strokePath()
            } else {
                crumbs(ctx, around: stamp.apex, spread: stamp.fullRadius * 0.9, count: 14,
                       colors: [Palette.cobalt, UIColor(hex: 0x6F8EF2)], size: 1.5...3.5, rng: &rng)
            }
            return .none
        case .egg:
            switch index {
            case 0:
                if stamp.features.count >= 2 {
                    crack(ctx, from: stamp.features[0], to: stamp.features[1], segments: 8, jitter: 3, width: 1.3,
                          color: UIColor(hex: 0x7E7A74).withAlphaComponent(0.85), rng: &rng)
                }
            case 1:
                shards(ctx, around: stamp.apex, radius: stamp.fullRadius * 0.75, count: 9,
                       color: UIColor(hex: 0xC9A877).withAlphaComponent(0.8), rng: &rng)
            default:
                sun(ctx, stamp.apex, 0.018 * k, rays: 9, Palette.yolk.withAlphaComponent(0.95), rng: &rng)
            }
            return .none
        case .cakeSlice:
            if index == 0 {
                for _ in 0..<3 {
                    let a = CGPoint(x: stamp.apex.x + CGFloat.random(in: -30...30, using: &rng),
                                    y: stamp.apex.y + CGFloat.random(in: -24...24, using: &rng))
                    let b = CGPoint(x: a.x + CGFloat.random(in: -26...26, using: &rng), y: a.y + CGFloat.random(in: -20...20, using: &rng))
                    crack(ctx, from: a, to: b, segments: 4, jitter: 2.5, width: 1.4,
                          color: UIColor(hex: 0xFFE4EF).withAlphaComponent(0.95), rng: &rng)
                }
            } else if index == 1, let candle = stamp.features.first {
                // The candle bends and lies flat: a striped stroke.
                let dir = CGPoint(x: cos(CGFloat(-stamp.yawRadians) + 0.9), y: sin(CGFloat(-stamp.yawRadians) + 0.9))
                ctx.setLineCap(.round)
                ctx.setStrokeColor(Palette.candle.withAlphaComponent(0.85).cgColor)
                ctx.setLineWidth(0.007 * k)
                ctx.move(to: candle)
                ctx.addLine(to: CGPoint(x: candle.x + dir.x * 0.036 * k, y: candle.y + dir.y * 0.036 * k))
                ctx.strokePath()
            }
            return .none
        case .sodaCan:
            // Each buckle stamps one radial crease (FOLD-REVIEW-2 #9: concentric rings read as a "power button").
            let a = CGFloat(index) / 5 * 2 * .pi + CGFloat.random(in: -0.25...0.25, using: &rng)
            let r0 = stamp.featureRadius * 0.3, r1 = stamp.featureRadius * 1.08
            crack(ctx, from: CGPoint(x: cos(a) * r0, y: sin(a) * r0), to: CGPoint(x: cos(a) * r1, y: sin(a) * r1),
                  segments: 4, jitter: 1.8, width: 1.6, color: stamp.inkEdge.withAlphaComponent(0.75), rng: &rng)
            return .none
        case .gummyBear:
            if !isFailure, index > 0 { return .none }
            if stamp.features.count >= 2 {
                crack(ctx, from: stamp.features[0], to: stamp.features[1], segments: 5, jitter: 2, width: 3,
                      color: Palette.plateSteel.withAlphaComponent(0.9), rng: &rng)
            }
            return .none
        case .glassBottle:
            let branches = isFailure ? 0 : (index == 0 ? 3 : 5)
            ctx.saveGState()
            clipToPlate(ctx)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            for _ in 0..<branches {
                let start = CGPoint(x: stamp.apex.x + CGFloat.random(in: -40...40, using: &rng),
                                    y: stamp.apex.y + CGFloat.random(in: -14...14, using: &rng))
                frost(ctx, from: start, heading: CGFloat.random(in: 0...(2 * .pi), using: &rng), length: 46, depth: 2, rng: &rng)
            }
            fadeInsidePlate(ctx)
            ctx.endTransparencyLayer()
            ctx.restoreGState()
            return .none
        case .unsquishable:
            return isFailure ? .platenBreaks : .pulse
        }
    }

    /// Failure splat (§3.2 step 4), drawn once into its own image so it can spread with compression afterwards.
    static func splatImage(_ stamp: FoldStamp, variant: PressVariant, scale: CGFloat = 2) -> CGImage? {
        var rng = SplitMix64(seed: stamp.seed ^ 0x5B1A7)
        let k = stamp.pointsPerMetre
        let r = stamp.fullRadius
        return image(rect: FoldPrintCanvas.rect, scale: scale) { ctx in
            let gold = stamp.golden
            switch stamp.kind {
            case .bubbleWrap, .unsquishable:
                break
            case .rubberDuck:
                let seam = stamp.features.count >= 3
                    ? CGPoint(x: (stamp.features[1].x + stamp.features[2].x) / 2, y: (stamp.features[1].y + stamp.features[2].y) / 2)
                    : stamp.apex
                blob(ctx, seam, r * 0.42, lobes: 9, (gold ? Palette.gold : Palette.duckYellow).withAlphaComponent(0.95), rng: &rng)
                droplets(ctx, around: seam, from: r * 0.45, to: r * 0.95, count: 10,
                         color: (gold ? Palette.gold : Palette.duckYellow).withAlphaComponent(0.9), rng: &rng)
            case .jelly:
                let ink = (gold ? Palette.goldMessColor : UIColor(hex: 0xD0164F)).withAlphaComponent(0.9)
                blob(ctx, .zero, r * 1.15, lobes: 11, ink, rng: &rng)
                droplets(ctx, around: .zero, from: r * 1.15, to: r * 1.7, count: 12, color: ink, rng: &rng)
                if variant.surprise == .fruitPieces || !gold {
                    // Square fruit-cube "holes" (§3.2): steel showing through the splat.
                    for _ in 0..<5 {
                        let p = CGPoint(x: CGFloat.random(in: -r * 0.7...r * 0.7, using: &rng),
                                        y: CGFloat.random(in: -r * 0.7...r * 0.7, using: &rng))
                        let s = CGFloat.random(in: 6...10, using: &rng)
                        ctx.saveGState()
                        ctx.translateBy(x: p.x, y: p.y)
                        ctx.rotate(by: CGFloat.random(in: 0...1.2, using: &rng))
                        ctx.setFillColor(Palette.plateSteel.withAlphaComponent(0.92).cgColor)
                        ctx.fill(CGRect(x: -s / 2, y: -s / 2, width: s, height: s))
                        ctx.restoreGState()
                    }
                }
                gloss(ctx, .zero, r * 0.9)
            case .crayon:
                let ink = (gold ? Palette.goldMessColor : Palette.cobalt).withAlphaComponent(0.85)
                ctx.saveGState()
                ctx.rotate(by: CGFloat(-stamp.yawRadians))
                let bar = CGRect(x: -stamp.growthRadii.width * 1.05, y: -stamp.growthRadii.height * 1.6,
                                 width: stamp.growthRadii.width * 2.1, height: stamp.growthRadii.height * 3.2)
                ctx.addPath(CGPath(roundedRect: bar, cornerWidth: bar.height / 2, cornerHeight: bar.height / 2, transform: nil))
                ctx.setFillColor(ink.cgColor)
                ctx.fillPath()
                ctx.restoreGState()
                crumbs(ctx, around: .zero, spread: r * 1.2, count: 22, colors: [ink, UIColor(hex: 0x6F8EF2)], size: 1.5...4, rng: &rng)
            case .egg:
                blob(ctx, stamp.apex, r * 0.95, lobes: 10, UIColor(hex: 0xFFFDF6).withAlphaComponent(0.95), rng: &rng)
                ring(ctx, stamp.apex, r * 0.95, 2, UIColor(hex: 0xE9E1D2).withAlphaComponent(0.9))
                if variant.surprise == .doubleYolk {
                    fillDisc(ctx, CGPoint(x: stamp.apex.x - 0.012 * k, y: stamp.apex.y), 0.011 * k, Palette.yolk.withAlphaComponent(0.6))
                    fillDisc(ctx, CGPoint(x: stamp.apex.x + 0.012 * k, y: stamp.apex.y), 0.011 * k, Palette.yolk.withAlphaComponent(0.6))
                } else {
                    fillDisc(ctx, stamp.apex, 0.013 * k, Palette.yolk.withAlphaComponent(0.55))
                }
            case .cakeSlice:
                let pink = (gold ? Palette.goldMessColor : UIColor(hex: 0xFF8FC8)).withAlphaComponent(0.9)
                blob(ctx, stamp.apex, r * 0.75, lobes: 8, pink, rng: &rng)
                if variant.surprise == .jamCentre {
                    blob(ctx, stamp.apex, r * 0.35, lobes: 6, Palette.jam.withAlphaComponent(0.85), rng: &rng)
                }
                for _ in 0..<16 {
                    let a = CGFloat.random(in: 0...(2 * .pi), using: &rng)
                    let d = CGFloat.random(in: 0...(r * 0.9), using: &rng)
                    let p = CGPoint(x: stamp.apex.x + cos(a) * d, y: stamp.apex.y + sin(a) * d)
                    ctx.saveGState()
                    ctx.translateBy(x: p.x, y: p.y)
                    ctx.rotate(by: CGFloat.random(in: 0...(2 * .pi), using: &rng))
                    ctx.setFillColor(Palette.rainbow.pick(&rng).cgColor)
                    ctx.addPath(CGPath(roundedRect: CGRect(x: -3, y: -1, width: 6, height: 2), cornerWidth: 1, cornerHeight: 1, transform: nil))
                    ctx.fillPath()
                    ctx.restoreGState()
                }
                fillDisc(ctx, stamp.apex, 2.2, Palette.graphite)   // the wick
            case .sodaCan:
                let fizz = canFizz(variant)
                ring(ctx, .zero, stamp.featureRadius, 2, UIColor(hex: 0x9AA0A8).withAlphaComponent(0.8))
                blob(ctx, CGPoint(x: stamp.featureRadius * 0.6, y: stamp.featureRadius * 0.4), stamp.featureRadius * 0.7,
                     lobes: 7, fizz.withAlphaComponent(0.6), rng: &rng)
                droplets(ctx, around: .zero, from: stamp.featureRadius * 1.25, to: stamp.featureRadius * 2.6, count: 26,
                         color: fizz.withAlphaComponent(0.85), rng: &rng)
            case .gummyBear:
                let ink = (gold ? Palette.goldMessColor : UIColor(hex: 0xFF8A7F)).withAlphaComponent(0.85)
                for s: CGFloat in [-1, 1] {
                    let c = CGPoint(x: stamp.apex.x + s * r * 0.35 * cos(CGFloat(-stamp.yawRadians)),
                                    y: stamp.apex.y + s * r * 0.35 * sin(CGFloat(-stamp.yawRadians)))
                    blob(ctx, c, r * 0.6, lobes: 7, ink, rng: &rng)
                }
                gloss(ctx, stamp.apex, r * 0.7)
            case .glassBottle:
                clipToPlate(ctx)
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)
                for i in 0..<9 {
                    let a = CGFloat(i) / 9 * 2 * .pi + CGFloat.random(in: -0.2...0.2, using: &rng)
                    frost(ctx, from: stamp.apex, heading: a, length: r * 1.05, depth: 3, rng: &rng)
                }
                fadeInsidePlate(ctx)
                ctx.endTransparencyLayer()
                if variant.surprise == .messageInABottle {
                    crumbs(ctx, around: stamp.apex, spread: r, count: 18, colors: Palette.rainbow, size: 2...3.5, rng: &rng)
                }
            }
        }
    }

    // MARK: Drawing helpers

    static func ring(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, _ width: CGFloat, _ color: UIColor) {
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(width)
        ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }

    static func fillDisc(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, _ color: UIColor) {
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }

    static func crack(_ ctx: CGContext, from a: CGPoint, to b: CGPoint, segments: Int, jitter: CGFloat, width: CGFloat,
                      color: UIColor, rng: inout SplitMix64) {
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.move(to: a)
        let n = max(segments, 1)
        for i in 1...n {
            let t = CGFloat(i) / CGFloat(n)
            let j = i == n ? 0 : jitter
            ctx.addLine(to: CGPoint(x: a.x + (b.x - a.x) * t + CGFloat.random(in: -j...j, using: &rng),
                                    y: a.y + (b.y - a.y) * t + CGFloat.random(in: -j...j, using: &rng)))
        }
        ctx.strokePath()
    }

    static func blob(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, lobes: Int, _ color: UIColor, rng: inout SplitMix64) {
        let n = max(lobes, 3) * 2
        var radii: [CGFloat] = []
        for i in 0..<n { radii.append(r * (i % 2 == 0 ? CGFloat.random(in: 0.85...1.15, using: &rng) : CGFloat.random(in: 0.62...0.85, using: &rng))) }
        let path = CGMutablePath()
        func point(_ i: Int) -> CGPoint {
            let a = CGFloat(i) / CGFloat(n) * 2 * .pi
            return CGPoint(x: c.x + cos(a) * radii[i % n], y: c.y + sin(a) * radii[i % n])
        }
        let start = CGPoint(x: (point(0).x + point(1).x) / 2, y: (point(0).y + point(1).y) / 2)
        path.move(to: start)
        for i in 1...n {
            let p = point(i)
            let q = point(i + 1)
            path.addQuadCurve(to: CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2), control: p)
        }
        path.closeSubpath()
        ctx.addPath(path)
        ctx.setFillColor(color.cgColor)
        ctx.fillPath()
    }

    static func droplets(_ ctx: CGContext, around c: CGPoint, from r0: CGFloat, to r1: CGFloat, count: Int, color: UIColor,
                         rng: inout SplitMix64) {
        for _ in 0..<count {
            let a = CGFloat.random(in: 0...(2 * .pi), using: &rng)
            let d = CGFloat.random(in: r0...max(r0 + 1, r1), using: &rng)
            fillDisc(ctx, CGPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d), CGFloat.random(in: 1.5...4.5, using: &rng), color)
        }
    }

    static func crumbs(_ ctx: CGContext, around c: CGPoint, spread: CGFloat, count: Int, colors: [UIColor],
                       size: ClosedRange<CGFloat>, rng: inout SplitMix64) {
        for _ in 0..<count {
            let p = CGPoint(x: c.x + CGFloat.random(in: -spread...spread, using: &rng),
                            y: c.y + CGFloat.random(in: -spread * 0.7...spread * 0.7, using: &rng))
            let s = CGFloat.random(in: size, using: &rng)
            ctx.setFillColor(colors.pick(&rng).withAlphaComponent(0.9).cgColor)
            ctx.fill(CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s * 0.8))
        }
    }

    static func shards(_ ctx: CGContext, around c: CGPoint, radius: CGFloat, count: Int, color: UIColor, rng: inout SplitMix64) {
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(1.2)
        ctx.setLineJoin(.round)
        for _ in 0..<count {
            let a = CGFloat.random(in: 0...(2 * .pi), using: &rng)
            let d = CGFloat.random(in: radius * 0.2...radius, using: &rng)
            let p = CGPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d)
            let s = CGFloat.random(in: 7...13, using: &rng)
            ctx.move(to: CGPoint(x: p.x - s / 2, y: p.y - s * 0.3))
            ctx.addLine(to: CGPoint(x: p.x + s * 0.4, y: p.y - s / 2))
            ctx.addLine(to: CGPoint(x: p.x + s / 2, y: p.y + s * 0.4))
            ctx.addLine(to: CGPoint(x: p.x - s * 0.3, y: p.y + s / 2))
            ctx.closePath()
            ctx.strokePath()
        }
    }

    static func sun(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, rays: Int, _ color: UIColor, rng: inout SplitMix64) {
        fillDisc(ctx, c, r, color)
        ctx.setStrokeColor(color.withAlphaComponent(0.7).cgColor)
        ctx.setLineCap(.round)
        ctx.setLineWidth(3)
        for i in 0..<rays {
            let a = CGFloat(i) / CGFloat(rays) * 2 * .pi + CGFloat.random(in: -0.15...0.15, using: &rng)
            let l = r * CGFloat.random(in: 1.25...1.7, using: &rng)
            ctx.move(to: CGPoint(x: c.x + cos(a) * r * 0.9, y: c.y + sin(a) * r * 0.9))
            ctx.addLine(to: CGPoint(x: c.x + cos(a) * l, y: c.y + sin(a) * l))
        }
        ctx.strokePath()
        fillDisc(ctx, CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.3), r * 0.25, UIColor(white: 1, alpha: 0.45))
    }

    /// Clips to the strike plate (print space): glass prints on the steel; frost never strays onto the enamel
    /// (FOLD-REVIEW-1 #7). Callers save / restore the graphics state.
    static func clipToPlate(_ ctx: CGContext) {
        let plate = CGRect(x: -FoldMetrics.plateLateral / 2, y: -FoldMetrics.plateDepth / 2,
                           width: FoldMetrics.plateLateral, height: FoldMetrics.plateDepth).insetBy(dx: 3, dy: 3)
        let r = CGFloat(FoldMetrics.plateRadius) - 3
        ctx.addPath(CGPath(roundedRect: plate, cornerWidth: r, cornerHeight: r, transform: nil))
        ctx.clip()
    }

    /// Fades whatever was drawn in the current transparency layer to nothing toward the strike plate's edge (an
    /// ellipse inscribed in the plate, opaque to 78 %), so frost never ends on a straight cut (FOLD-REVIEW-2 #7).
    static func fadeInsidePlate(_ ctx: CGContext) {
        ctx.saveGState()
        ctx.setBlendMode(.destinationIn)
        ctx.scaleBy(x: CGFloat(FoldMetrics.plateLateral / FoldMetrics.plateDepth), y: 1)
        let r = CGFloat(FoldMetrics.plateDepth / 2) - 4
        let colors = [UIColor.white.cgColor, UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.78, 1]) {
            ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: r,
                                   options: [.drawsAfterEndLocation])
        }
        ctx.restoreGState()
    }

    /// Glass prints as frost (§3.2): white branching lines over a faint warm underlay so they read on pale steel.
    static func frost(_ ctx: CGContext, from start: CGPoint, heading: CGFloat, length: CGFloat, depth: Int, rng: inout SplitMix64) {
        var p = start
        var h = heading
        let steps = 5
        let line = CGMutablePath()
        line.move(to: p)
        for _ in 0..<steps {
            h += CGFloat.random(in: -0.5...0.5, using: &rng)
            p = CGPoint(x: p.x + cos(h) * length / CGFloat(steps), y: p.y + sin(h) * length / CGFloat(steps))
            line.addLine(to: p)
        }
        let width = CGFloat(depth) * 0.6 + 0.6
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.saveGState()
        ctx.translateBy(x: 0.6, y: 0.6)
        ctx.addPath(line)
        ctx.setStrokeColor(Palette.shadowInk.withAlphaComponent(0.25).cgColor)
        ctx.setLineWidth(width + 1)
        ctx.strokePath()
        ctx.restoreGState()
        ctx.addPath(line)
        ctx.setStrokeColor(UIColor(white: 1, alpha: 0.92).cgColor)
        ctx.setLineWidth(width)
        ctx.strokePath()
        if depth > 1 {
            for _ in 0..<2 {
                let t = CGFloat.random(in: 0.3...0.8, using: &rng)
                let q = CGPoint(x: start.x + (p.x - start.x) * t, y: start.y + (p.y - start.y) * t)
                frost(ctx, from: q, heading: h + CGFloat.random(in: -1.2...1.2, using: &rng), length: length * 0.45,
                      depth: depth - 1, rng: &rng)
            }
        }
    }

    static func gloss(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat) {
        let colors = [UIColor(white: 1, alpha: 0.35).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            let h = CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.35)
            ctx.drawRadialGradient(g, startCenter: h, startRadius: 0, endCenter: h, endRadius: r * 0.6, options: [])
        }
    }
}
