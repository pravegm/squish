import CoreGraphics
import Foundation
import UIKit

/// CoreGraphics art for the Fold Press bezel and plates (FOLD-PRESS.md §2.1, §3.2, §5): brushed steel with streaks
/// parallel to the crease, chrome bolts and pins, lamps, hazard jaws. Pure functions, generated once per layout.
enum FoldTextures {
    /// 2D platen field brightness relative to the base enamel (≈ L 210 for the duck's gel) [tune against CI].
    static let platenLit: Float = 0.90

    /// The enamel field colour (§2.1): mix(floorNear #F1E9DC, gel, 0.35).
    /// `lit` multiplies the result. Both fields use `platenLit`: the 2D platen and, since FOLD-REVIEW-3 N3, the 3D
    /// anvil's unlit field, so the two pages are the same colour by construction (target L 195–215) [tune].
    static func enamel(gel: UInt32, golden: Bool, lit: Float = 1) -> UIColor {
        let a = StudioEnvironment.rgb(0xF1E9DC)
        let b = StudioEnvironment.rgb(golden ? 0xF3E6C4 : gel)
        // Gel strength 0.18 on both halves (FOLD-REVIEW-2 #12: the flat 2D platen showed the gel far more strongly
        // than the lit anvil did at 0.35, so the pages read as two materials).
        let c = (a + (b - a) * 0.18) * lit
        return UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
    }

    /// Brushed steel, streaks along the image's x axis (parallel to the crease once placed).
    static func brushedSteel(width: Int = 512, height: Int = 512, seed: UInt64 = 0x57EE1,
                             base: UIColor = Palette.brushedSteel) -> CGImage? {
        FoldStamps.image(rect: CGRect(x: 0, y: 0, width: width, height: height), scale: 1) { ctx in
            ctx.setFillColor(base.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            var rng = SplitMix64(seed: seed)
            var y: CGFloat = 0
            while y < CGFloat(height) {
                let shade = CGFloat(Int(rng.next() % 17) - 8) / 255
                let h = CGFloat(1 + Int(rng.next() % 2))
                ctx.setFillColor(UIColor(white: 0.76 + shade, alpha: 0.35).cgColor)
                ctx.fill(CGRect(x: 0, y: y, width: CGFloat(width), height: h))
                y += h
            }
        }
    }

    /// The platen's strike plate as a 2D image: brushed steel, rounded, a 1 pt chamfer highlight, a soft key-light
    /// gradient from the upper left. `streaksAlongX`: true when the crease is horizontal on screen.
    /// Base #B8BCC2: a touch darker than the P-48's #BFC3C8, to sit within ±12 L of the rendered anvil plate.
    static let platenSteel = UIColor(hex: 0xB8BCC2)

    static func strikePlate(size: CGSize, radius: CGFloat, streaksAlongX: Bool, scale: CGFloat = 2) -> CGImage? {
        let rect = CGRect(origin: .zero, size: size)
        return FoldStamps.image(rect: rect, scale: scale) { ctx in
            let shape = CGPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerWidth: radius, cornerHeight: radius, transform: nil)
            ctx.addPath(shape)
            ctx.saveGState()
            ctx.clip()
            ctx.setFillColor(platenSteel.cgColor)
            ctx.fill(rect)
            var rng = SplitMix64(seed: 0x57EE2)
            var t: CGFloat = 0
            let length = streaksAlongX ? size.height : size.width
            while t < length {
                let shade = CGFloat(Int(rng.next() % 17) - 8) / 255
                let h = CGFloat(1 + Int(rng.next() % 2)) * 0.5
                ctx.setFillColor(UIColor(white: 0.76 + shade, alpha: 0.4).cgColor)
                ctx.fill(streaksAlongX ? CGRect(x: 0, y: t, width: size.width, height: h)
                                       : CGRect(x: t, y: 0, width: h, height: size.height))
                t += h
            }
            let light = [UIColor(white: 1, alpha: 0.16).cgColor, UIColor(white: 1, alpha: 0).cgColor,
                         UIColor(white: 0, alpha: 0.06).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: light, locations: [0, 0.55, 1]) {
                ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
            ctx.restoreGState()
            // Chamfer: a bright line just inside the edge, a darker one on the edge.
            ctx.addPath(shape)
            ctx.setStrokeColor(UIColor(hex: 0x8A8F98).cgColor)
            ctx.setLineWidth(1)
            ctx.strokePath()
            ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 1.6, dy: 1.6), cornerWidth: radius - 1.2, cornerHeight: radius - 1.2,
                               transform: nil))
            ctx.setStrokeColor(UIColor(white: 1, alpha: 0.75).cgColor)
            ctx.setLineWidth(1)
            ctx.strokePath()
        }
    }

    /// The plate outline as an alpha mask (for clipping the sheen).
    static func plateMask(size: CGSize, radius: CGFloat) -> CGImage? {
        let rect = CGRect(origin: .zero, size: size)
        return FoldStamps.image(rect: rect, scale: 1) { ctx in
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fillPath()
        }
    }

    /// A chrome hex bolt head seen from above.
    static func bolt(diameter: CGFloat, scale: CGFloat = 3) -> CGImage? {
        let s = diameter + 4
        return FoldStamps.image(rect: CGRect(x: -s / 2, y: -s / 2, width: s, height: s), scale: scale) { ctx in
            let hex = CGMutablePath()
            for i in 0..<6 {
                let a = CGFloat(i) * .pi / 3 + .pi / 6
                let p = CGPoint(x: cos(a) * diameter / 2, y: sin(a) * diameter / 2)
                if i == 0 { hex.move(to: p) } else { hex.addLine(to: p) }
            }
            hex.closeSubpath()
            ctx.setShadow(offset: CGSize(width: 0.6 * scale, height: -0.8 * scale), blur: 1.2 * scale,
                          color: Palette.shadowInk.withAlphaComponent(0.45).cgColor)
            ctx.addPath(hex)
            ctx.setFillColor(UIColor(hex: 0x9AA0A8).cgColor)
            ctx.fillPath()
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            ctx.saveGState()
            ctx.addPath(hex)
            ctx.clip()
            // Flat-topped hex head like the anvil's 3D bolts: faceted shading, not a white dome (FOLD-REVIEW-1 #8).
            let colors = [UIColor(hex: 0xE4E6EA).cgColor, UIColor(hex: 0xB9BEC6).cgColor, UIColor(hex: 0x7A7F88).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: -diameter / 2, y: -diameter / 2),
                                       end: CGPoint(x: diameter / 2, y: diameter / 2), options: [])
            }
            ctx.restoreGState()
            ctx.addPath(hex)
            ctx.setStrokeColor(UIColor(hex: 0x5E6067).cgColor)
            ctx.setLineWidth(0.7)
            ctx.strokePath()
            let inner = CGRect(x: -diameter * 0.2, y: -diameter * 0.2, width: diameter * 0.4, height: diameter * 0.4)
            ctx.setStrokeColor(UIColor(white: 1, alpha: 0.55).cgColor)
            ctx.setLineWidth(0.5)
            ctx.strokeEllipse(in: inner)
        }
    }

    /// A chrome dome (guide pin) or a dark chrome ring (bushing).
    static func pin(diameter: CGFloat, ring: Bool, scale: CGFloat = 3) -> CGImage? {
        let s = diameter + 4
        return FoldStamps.image(rect: CGRect(x: -s / 2, y: -s / 2, width: s, height: s), scale: scale) { ctx in
            let r = diameter / 2
            let disc = CGRect(x: -r, y: -r, width: diameter, height: diameter)
            if !ring {
                ctx.setShadow(offset: CGSize(width: 0.6 * scale, height: -0.8 * scale), blur: 1.4 * scale,
                              color: Palette.shadowInk.withAlphaComponent(0.4).cgColor)
            }
            ctx.setFillColor((ring ? UIColor(hex: 0x6B6E75) : Palette.chrome).cgColor)
            ctx.fillEllipse(in: disc)
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            if ring {
                ctx.setFillColor(UIColor(hex: 0x34373D).cgColor)
                ctx.fillEllipse(in: disc.insetBy(dx: r * 0.4, dy: r * 0.4))
                ctx.setStrokeColor(UIColor(white: 1, alpha: 0.45).cgColor)
                ctx.setLineWidth(0.6)
                ctx.strokeEllipse(in: disc.insetBy(dx: 0.4, dy: 0.4))
            } else {
                // The guide pin: the bushing's dark ring with a chrome dome in it, so pin and bushing read as a pair.
                ctx.setFillColor(UIColor(hex: 0x6B6E75).cgColor)
                ctx.fillEllipse(in: disc)
                let dome = disc.insetBy(dx: r * 0.28, dy: r * 0.28)
                ctx.addEllipse(in: dome)
                ctx.clip()
                let colors = [UIColor.white.cgColor, Palette.chrome.cgColor, UIColor(hex: 0x7A7F88).cgColor] as CFArray
                if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.4, 1]) {
                    ctx.drawRadialGradient(g, startCenter: CGPoint(x: -r * 0.25, y: -r * 0.3), startRadius: 0,
                                           endCenter: .zero, endRadius: r * 0.8, options: [])
                }
            }
        }
    }

    /// A panel lamp: an enamel dome, lit (with a hot core) or off.
    static func lamp(_ color: UIColor, lit: Bool, diameter: CGFloat, scale: CGFloat = 3) -> CGImage? {
        let s = diameter + 6
        return FoldStamps.image(rect: CGRect(x: -s / 2, y: -s / 2, width: s, height: s), scale: scale) { ctx in
            let r = diameter / 2
            let disc = CGRect(x: -r, y: -r, width: diameter, height: diameter)
            if lit {
                ctx.setShadow(offset: .zero, blur: 3 * scale, color: color.withAlphaComponent(0.8).cgColor)
            }
            ctx.setFillColor((lit ? color : Palette.lampOff).cgColor)
            ctx.fillEllipse(in: disc)
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            ctx.addEllipse(in: disc)
            ctx.clip()
            let core = lit ? UIColor(white: 1, alpha: 0.65) : UIColor(white: 1, alpha: 0.25)
            let colors = [core.cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.drawRadialGradient(g, startCenter: CGPoint(x: -r * 0.3, y: -r * 0.35), startRadius: 0,
                                       endCenter: CGPoint(x: -r * 0.3, y: -r * 0.35), endRadius: r * 0.8, options: [])
            }
        }
    }

    /// A hazard jaw (§5): 45° stripes, 8 pt wide (16 pt period), amber / graphite. `along` runs parallel to the
    /// crease; `mirror` flips the stripe slant (the platen's jaw is the anvil's mirror, half a period out, so the two
    /// mesh when the phone shuts).
    static func hazardJaw(size: CGSize, alongX: Bool, mirror: Bool, scale: CGFloat = 2) -> CGImage? {
        let rect = CGRect(origin: .zero, size: size)
        return FoldStamps.image(rect: rect, scale: scale) { ctx in
            ctx.setFillColor(Palette.graphite.cgColor)
            ctx.fill(rect)
            ctx.setFillColor(Palette.hydraulicYellow.cgColor)
            let along = alongX ? size.width : size.height
            let across = alongX ? size.height : size.width
            let stripe: CGFloat = 8
            let phase: CGFloat = mirror ? stripe : 0
            let slant: CGFloat = mirror ? -1 : 1
            var s = -across - 2 * stripe + phase
            while s < along + across {
                // Parallelogram between lines along = s + slant·across and s + stripe + slant·across.
                func p(_ a: CGFloat, _ c: CGFloat) -> CGPoint { alongX ? CGPoint(x: a, y: c) : CGPoint(x: c, y: a) }
                let c0: CGFloat = 0, c1 = across
                let a0 = s + (slant > 0 ? 0 : across)
                ctx.move(to: p(a0 + slant * c0, c0))
                ctx.addLine(to: p(a0 + stripe + slant * c0, c0))
                ctx.addLine(to: p(a0 + stripe + slant * c1, c1))
                ctx.addLine(to: p(a0 + slant * c1, c1))
                ctx.closePath()
                ctx.fillPath()
                s += stripe * 2
            }
        }
    }

    /// Engraved panel labels ("READY", "LOAD") as an image, in SF Mono.
    @MainActor
    static func label(_ text: String, size: CGFloat, color: UIColor) -> CGImage? {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: size, weight: .semibold), .foregroundColor: color, .kern: 1.2,
        ]
        let string = text as NSString
        let bounds = string.size(withAttributes: attributes)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: ceil(bounds.width), height: ceil(bounds.height)), format: format)
        return renderer.image { _ in
            string.draw(at: .zero, withAttributes: attributes)
        }.cgImage
    }

    /// The Fold Press dial (FOLD-REVIEW-1 #11, #15): 0–80 t, red zone 60–80, numerals 0 / 40 / 80 (as on the cover,
    /// FOLD-REVIEW-3 N11), "TONS" centred under the hub. One scale with the P-48 (`PressGauge`, FOLD-REVIEW-4 F12).
    static let gaugeMaxTons = CGFloat(PressGauge.maxTons)

    @MainActor
    static func gaugeFace(diameter: CGFloat) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        let size = CGSize(width: diameter, height: diameter)
        let maxTons = gaugeMaxTons
        let font = RigTextures.roundedFont(diameter * 0.15, .heavy)
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            let cg = context.cgContext
            let c = CGPoint(x: diameter / 2, y: diameter / 2)
            let R = diameter / 2
            cg.setFillColor(Palette.gaugePaper.cgColor)
            cg.fillEllipse(in: CGRect(origin: .zero, size: size))
            // Angle in UIKit screen space (y down) for a tonnage: 225° → −45° counter-clockwise in math terms.
            let angle: (CGFloat) -> CGFloat = { t in (225 - 270 * t / maxTons) * .pi / 180 }
            let point: (CGFloat, CGFloat) -> CGPoint = { t, r in
                CGPoint(x: c.x + cos(angle(t)) * r, y: c.y - sin(angle(t)) * r)
            }
            cg.setStrokeColor(Palette.stampRed.cgColor)
            cg.setLineWidth(diameter * 0.055)
            cg.addArc(center: c, radius: R * 0.84, startAngle: -angle(CGFloat(PressGauge.redZoneTons)), endAngle: -angle(maxTons),
                      clockwise: false)
            cg.strokePath()
            cg.setLineCap(.round)
            for t in stride(from: 0, through: Int(maxTons), by: 5) {
                let major = t % 20 == 0
                cg.setStrokeColor((major ? Palette.graphite : Palette.inkSecondary).cgColor)
                cg.setLineWidth(major ? diameter * 0.022 : diameter * 0.01)
                let outer = R * 0.93
                cg.move(to: point(CGFloat(t), outer - (major ? R * 0.13 : R * 0.07)))
                cg.addLine(to: point(CGFloat(t), outer))
                cg.strokePath()
            }
            // FOLD-REVIEW-3 N11: numerals 0 / 40 / 80 only (five crowded a 60 pt dial). The end numerals sit 5.5 t inside
            // their ticks, so the resting needle no longer covers the "0" and the "80" clears "TONS".
            for t in stride(from: 0, through: Int(maxTons), by: 40) {
                let text = "\(t)" as NSString
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Palette.graphite]
                let s = text.size(withAttributes: attributes)
                let nudge: CGFloat = t == 0 ? 5.5 : (CGFloat(t) == maxTons ? -5.5 : 0)
                let p = point(CGFloat(t) + nudge, R * 0.56)
                text.draw(at: CGPoint(x: p.x - s.width / 2, y: p.y - s.height / 2), withAttributes: attributes)
            }
            // "TONS" centred just under the hub, narrow enough to stay clear of the 0 and 80.
            let tons = "TONS" as NSString
            let tonsAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: diameter * 0.075, weight: .semibold),
                .foregroundColor: Palette.inkSecondary, .kern: 0.5,
            ]
            let ts = tons.size(withAttributes: tonsAttributes)
            tons.draw(at: CGPoint(x: c.x - ts.width / 2, y: c.y + R * 0.22), withAttributes: tonsAttributes)
        }.cgImage
    }

    /// Dial angle (radians, UIKit rotation from 12 o'clock, clockwise-positive) for a needle tonnage.
    static func needleRotation(tons: Double) -> CGFloat {
        let alpha = 225 - 270 * tons / Double(gaugeMaxTons)
        return CGFloat((90 - alpha) * .pi / 180)
    }

    /// The crown nameplate (FOLD-REVIEW-1 #15): brushed steel, a 1 pt top highlight, two rivets. Blank since
    /// FOLD-REVIEW-3 N7: the bezel lays the live hinge-angle readout (`engraved`) over it instead of "P-48".
    @MainActor
    static func nameplate(size: CGSize) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let steel = brushedSteel(width: Int(size.width * 3), height: Int(size.height * 3), seed: 0x48, base: UIColor(hex: 0xC4C8CE))
        return renderer.image { context in
            let cg = context.cgContext
            let rect = CGRect(origin: .zero, size: size)
            let shape = UIBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 3)
            shape.addClip()
            if let steel { UIImage(cgImage: steel).draw(in: rect) }
            cg.setFillColor(UIColor(white: 1, alpha: 0.7).cgColor)
            cg.fill(CGRect(x: 0, y: 0.5, width: size.width, height: 1))
            cg.setFillColor(UIColor(white: 0, alpha: 0.18).cgColor)
            cg.fill(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1))
            for x in [CGFloat(7), size.width - 7] {
                let rivet = CGRect(x: x - 2.2, y: size.height / 2 - 2.2, width: 4.4, height: 4.4)
                cg.setFillColor(UIColor(hex: 0x7A7F88).cgColor)
                cg.fillEllipse(in: rivet)
                cg.setFillColor(UIColor(white: 1, alpha: 0.8).cgColor)
                cg.fillEllipse(in: rivet.insetBy(dx: 1.3, dy: 1.3).offsetBy(dx: -0.5, dy: -0.5))
            }
        }.cgImage
    }

    /// Engraved plate text, for the hinge-angle readout on the nameplate (FOLD-REVIEW-3 N7): Mono Bold, graphite ink
    /// over a 0.8 pt white lower highlight, or stamp red once it has frozen at the failure angle. Image at 3×,
    /// tight to the text.
    @MainActor
    static func engraved(_ text: String, fontSize: CGFloat, red: Bool) -> CGImage? {
        let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
        let ink: UIColor = red ? Palette.stampRed : Palette.enamelGraphite
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink, .kern: 1.5]
        let highlight: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: UIColor(white: 1, alpha: 0.6), .kern: 1.5,
        ]
        let string = text as NSString
        let bounds = string.size(withAttributes: attributes)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        let canvas = CGSize(width: max(1, ceil(bounds.width)), height: max(1, ceil(bounds.height + 0.8)))
        return UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
            string.draw(at: CGPoint(x: 0, y: 0.8), withAttributes: highlight)
            string.draw(at: .zero, withAttributes: attributes)
        }.cgImage
    }

    /// The plate shade (§2.4): `shape` (canvas-local) blurred by `blur`, in shadow ink, clipped to the canvas as a
    /// rounded rectangle so it never ends on a straight edge.
    static func plateShade(canvas: CGSize, shape: CGRect, radius: CGFloat, blur: CGFloat, clipRadius: CGFloat) -> CGImage? {
        let rect = CGRect(origin: .zero, size: canvas)
        return FoldStamps.image(rect: rect, scale: 1) { ctx in
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: clipRadius, cornerHeight: clipRadius, transform: nil))
            ctx.clip()
            let shift = rect.width + 4 * blur
            ctx.setShadow(offset: CGSize(width: -shift, height: 0), blur: blur, color: Palette.shadowInk.cgColor)
            ctx.translateBy(x: shift, y: 0)
            ctx.addPath(CGPath(roundedRect: shape, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.setFillColor(Palette.shadowInk.cgColor)
            ctx.fillPath()
        }
    }

    /// The red PRESSED stamp (§6.3 step 4), drawn upright (it never mirrors with the print). `paperInk`: paper-white
    /// ink over a red keyline, for prints too close to red to show red ink (FOLD-REVIEW-3 N12: jelly).
    @MainActor
    static func pressedStamp(width: CGFloat = 150, paperInk: Bool = false) -> CGImage? {
        let height = width * 0.38
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        return renderer.image { context in
            let cg = context.cgContext
            let red = Palette.stampRed.withAlphaComponent(0.88)
            let ink = paperInk ? Palette.paper.withAlphaComponent(0.95) : red
            let outer = CGPath(roundedRect: CGRect(x: 3, y: 3, width: width - 6, height: height - 6), cornerWidth: 7,
                               cornerHeight: 7, transform: nil)
            let inner = CGPath(roundedRect: CGRect(x: 8, y: 8, width: width - 16, height: height - 16), cornerWidth: 4,
                               cornerHeight: 4, transform: nil)
            let font = UIFont.monospacedSystemFont(ofSize: height * 0.42, weight: .heavy)
            let text = "PRESSED" as NSString
            let size = text.size(withAttributes: [.font: font, .kern: 3])
            let origin = CGPoint(x: (width - size.width) / 2, y: (height - size.height) / 2)
            if paperInk {
                // The red keyline: the same marks, wider, under the white ink.
                cg.setStrokeColor(red.cgColor)
                cg.setLineWidth(5.5)
                cg.addPath(outer)
                cg.strokePath()
                cg.setLineWidth(3)
                cg.addPath(inner)
                cg.strokePath()
                let keyline: [NSAttributedString.Key: Any] = [
                    .font: font, .kern: 3, .foregroundColor: red, .strokeColor: red, .strokeWidth: -14,
                ]
                text.draw(at: origin, withAttributes: keyline)
            }
            cg.setStrokeColor(ink.cgColor)
            cg.setLineWidth(3.5)
            cg.addPath(outer)
            cg.strokePath()
            cg.setLineWidth(1.2)
            cg.addPath(inner)
            cg.strokePath()
            text.draw(at: origin, withAttributes: [.font: font, .foregroundColor: ink, .kern: 3])
        }.cgImage
    }
}
