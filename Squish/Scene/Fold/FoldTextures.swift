import CoreGraphics
import Foundation
import UIKit

/// CoreGraphics art for the Fold Press bezel and plates (FOLD-PRESS.md §2.1, §3.2, §5): brushed steel with streaks
/// parallel to the crease, chrome bolts and pins, lamps, hazard jaws. Pure functions, generated once per layout.
enum FoldTextures {
    /// The enamel field colour (§2.1): mix(floorNear #F1E9DC, gel, 0.35).
    static func enamel(gel: UInt32, golden: Bool) -> UIColor {
        let a = StudioEnvironment.rgb(0xF1E9DC)
        let b = StudioEnvironment.rgb(golden ? 0xF3E6C4 : gel)
        let c = a + (b - a) * 0.35
        return UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
    }

    /// Brushed steel, streaks along the image's x axis (parallel to the crease once placed).
    static func brushedSteel(width: Int = 512, height: Int = 512, seed: UInt64 = 0x57EE1) -> CGImage? {
        FoldStamps.image(rect: CGRect(x: 0, y: 0, width: width, height: height), scale: 1) { ctx in
            ctx.setFillColor(Palette.brushedSteel.cgColor)
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
    static func strikePlate(size: CGSize, radius: CGFloat, streaksAlongX: Bool, scale: CGFloat = 2) -> CGImage? {
        let rect = CGRect(origin: .zero, size: size)
        return FoldStamps.image(rect: rect, scale: scale) { ctx in
            let shape = CGPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerWidth: radius, cornerHeight: radius, transform: nil)
            ctx.addPath(shape)
            ctx.saveGState()
            ctx.clip()
            ctx.setFillColor(Palette.brushedSteel.cgColor)
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
            ctx.setFillColor(UIColor(hex: 0xB9BEC6).cgColor)
            ctx.fillPath()
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            ctx.addPath(hex)
            ctx.clip()
            let colors = [UIColor.white.cgColor, Palette.chrome.cgColor, UIColor(hex: 0x8A8F98).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.45, 1]) {
                let c = CGPoint(x: -diameter * 0.18, y: -diameter * 0.2)
                ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: .zero, endRadius: diameter * 0.6, options: [])
            }
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
                ctx.addEllipse(in: disc)
                ctx.clip()
                let colors = [UIColor.white.cgColor, Palette.chrome.cgColor, UIColor(hex: 0x7A7F88).cgColor] as CFArray
                if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.4, 1]) {
                    ctx.drawRadialGradient(g, startCenter: CGPoint(x: -r * 0.35, y: -r * 0.4), startRadius: 0,
                                           endCenter: .zero, endRadius: r * 1.1, options: [])
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

    /// The red PRESSED stamp (§6.3 step 4), drawn upright (it never mirrors with the print).
    @MainActor
    static func pressedStamp(width: CGFloat = 150) -> CGImage? {
        let height = width * 0.38
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        return renderer.image { context in
            let cg = context.cgContext
            let red = Palette.stampRed.withAlphaComponent(0.88)
            cg.setStrokeColor(red.cgColor)
            cg.setLineWidth(3.5)
            cg.addPath(CGPath(roundedRect: CGRect(x: 3, y: 3, width: width - 6, height: height - 6), cornerWidth: 7, cornerHeight: 7,
                              transform: nil))
            cg.strokePath()
            cg.setLineWidth(1.2)
            cg.addPath(CGPath(roundedRect: CGRect(x: 8, y: 8, width: width - 16, height: height - 16), cornerWidth: 4, cornerHeight: 4,
                              transform: nil))
            cg.strokePath()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: height * 0.42, weight: .heavy), .foregroundColor: red, .kern: 3,
            ]
            let text = "PRESSED" as NSString
            let size = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: (width - size.width) / 2, y: (height - size.height) / 2), withAttributes: attributes)
        }.cgImage
    }
}
