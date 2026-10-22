import CoreGraphics
import Foundation
import UIKit

/// CoreGraphics-drawn textures for the press (VISUAL-TARGET §4.3–4.4). Drawn once at launch (a few ms each).
@MainActor
enum RigTextures {
    static func roundedFont(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        if let descriptor = base.fontDescriptor.withDesign(.rounded) {
            return UIFont(descriptor: descriptor, size: size)
        }
        return base
    }

    /// Gauge angle (radians, CCW from +x, y up) for a tonnage on the 0–60 t dial.
    nonisolated static func gaugeAngle(tons: CGFloat) -> CGFloat {
        (225 - 270 * tons / 60) * .pi / 180
    }

    /// The dial face: paper, graphite ring, 270° sweep, ticks, red zone 48–60 t, numerals, "TONS", "SQUISH".
    static func gaugeFace(size: CGFloat = 512) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)
        let image = renderer.image { context in
            let cg = context.cgContext
            let c = CGPoint(x: size / 2, y: size / 2)
            let R = size / 2
            // Paper with a faint radial vignette (edge −4%).
            let colors = [Palette.gaugePaper.cgColor, UIColor(hex: 0xF1EDE4).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.6, 1]) {
                cg.addEllipse(in: CGRect(x: 0, y: 0, width: size, height: size))
                cg.clip()
                cg.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: R, options: [])
                cg.resetClip()
            }
            func point(_ tons: CGFloat, _ radius: CGFloat) -> CGPoint {
                let a = gaugeAngle(tons: tons)
                return CGPoint(x: c.x + cos(a) * radius, y: c.y - sin(a) * radius)
            }
            // Outer graphite ring.
            cg.setStrokeColor(Palette.graphite.cgColor)
            cg.setLineWidth(6)
            cg.strokeEllipse(in: CGRect(x: 3, y: 3, width: size - 6, height: size - 6))
            // Red zone 48–60 t.
            cg.setStrokeColor(Palette.stampRed.cgColor)
            cg.setLineWidth(14)
            cg.addArc(center: c, radius: R * 0.86, startAngle: -gaugeAngle(tons: 48), endAngle: -gaugeAngle(tons: 60),
                      clockwise: false)
            cg.strokePath()
            // Ticks.
            cg.setLineCap(.round)
            for t in stride(from: 0, through: 60, by: 2) {
                let major = t % 10 == 0
                cg.setStrokeColor(major ? Palette.graphite.cgColor : Palette.inkSecondary.cgColor)
                cg.setLineWidth(major ? 5 : 2)
                let outer = R * 0.92
                let inner = outer - (major ? 18 : 9) * size / 512
                cg.move(to: point(CGFloat(t), inner))
                cg.addLine(to: point(CGFloat(t), outer))
                cg.strokePath()
            }
            // Numerals.
            let numeralFont = roundedFont(40 * size / 512, .heavy)
            for t in stride(from: 0, through: 60, by: 10) {
                let text = "\(t)" as NSString
                let attributes: [NSAttributedString.Key: Any] = [.font: numeralFont, .foregroundColor: Palette.graphite]
                let textSize = text.size(withAttributes: attributes)
                let p = point(CGFloat(t), R * 0.70)
                text.draw(at: CGPoint(x: p.x - textSize.width / 2, y: p.y - textSize.height / 2), withAttributes: attributes)
            }
            let tons = "TONS" as NSString
            let tonsAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 22 * size / 512, weight: .semibold),
                .foregroundColor: Palette.inkSecondary, .kern: 2,
            ]
            let tonsSize = tons.size(withAttributes: tonsAttributes)
            tons.draw(at: CGPoint(x: c.x - tonsSize.width / 2, y: c.y + R * 0.35 - tonsSize.height / 2), withAttributes: tonsAttributes)
            let brand = "SQUISH" as NSString
            let brandAttributes: [NSAttributedString.Key: Any] = [
                .font: roundedFont(18 * size / 512, .black), .foregroundColor: Palette.inkTertiary, .kern: 1.5,
            ]
            let brandSize = brand.size(withAttributes: brandAttributes)
            brand.draw(at: CGPoint(x: c.x - brandSize.width / 2, y: c.y - R * 0.32 - brandSize.height / 2), withAttributes: brandAttributes)
        }
        return image.cgImage
    }

    /// The single hazard band: 45° stripes, 8 mm wide on a 0.15 m band, amber / graphite.
    static func hazard(width: CGFloat = 1024, height: CGFloat = 64, bandLength: CGFloat = 0.15) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        let image = renderer.image { context in
            let cg = context.cgContext
            cg.setFillColor(Palette.graphite.cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let stripe = width * 0.008 / bandLength
            cg.setFillColor(Palette.hydraulicYellow.cgColor)
            var x: CGFloat = -height
            while x < width + height {
                cg.move(to: CGPoint(x: x, y: height))
                cg.addLine(to: CGPoint(x: x + stripe, y: height))
                cg.addLine(to: CGPoint(x: x + stripe + height, y: 0))
                cg.addLine(to: CGPoint(x: x + height, y: 0))
                cg.closePath()
                cg.fillPath()
                x += stripe * 2
            }
        }
        return image.cgImage
    }

    /// Brushed-steel nameplate with an engraved-look "P-48".
    static func nameplate(width: CGFloat = 384, height: CGFloat = 96) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        let image = renderer.image { context in
            let cg = context.cgContext
            cg.setFillColor(Palette.brushedSteel.cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
            var rng = SplitMix64(seed: 48)
            for row in stride(from: 0, to: Int(height), by: 2) {
                let shade = CGFloat(Int(rng.next() % 9) - 4) / 255
                cg.setFillColor(UIColor(white: 0.75 + shade, alpha: 0.25).cgColor)
                cg.fill(CGRect(x: 0, y: CGFloat(row), width: width, height: 1))
            }
            let text = "P-48" as NSString
            let font = UIFont.monospacedSystemFont(ofSize: height * 0.62, weight: .bold)
            let size = text.size(withAttributes: [.font: font])
            let origin = CGPoint(x: (width - size.width) / 2, y: (height - size.height) / 2)
            text.draw(at: CGPoint(x: origin.x, y: origin.y + 2),
                      withAttributes: [.font: font, .foregroundColor: UIColor(white: 1, alpha: 0.6), .kern: 4])
            text.draw(at: origin, withAttributes: [.font: font, .foregroundColor: Palette.enamelGraphite, .kern: 4])
        }
        return image.cgImage
    }
}
