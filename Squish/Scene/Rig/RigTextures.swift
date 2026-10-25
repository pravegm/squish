import CoreGraphics
import Foundation
import UIKit

/// One tonnage scale for both machines (FOLD-REVIEW-4 F12). The P-48 dial, the Fold Press crown dial and the cover's
/// mini gauge all read 0 / 40 / 80 t on the same 270° sweep (0 t at 225°, 80 t at −45°, CCW from +x) with the red
/// zone in the top quarter, and every needle comes to rest on the tonnage the specimen record prints
/// (`SpecimenRecord.tons`, which this mirrors exactly; FoldPressTests checks the two never drift apart).
enum PressGauge {
    /// Full scale of every tonnage dial.
    static let maxTons: Double = 80
    /// The red zone runs from here to full scale. Real objects top out at ~42 t (glass), so only The Unsquishable
    /// reaches it.
    static let redZoneTons: Double = 60

    /// The record's tonnage (`SpecimenRecord.tons`): the press's peak force, per material and per press (`Tonnage`,
    /// EXPERIENCE-REVIEW-1 #4: bubble wrap ~3 t, can ~22 t, glass ~38 t); the Unsquishable reads 400-odd and pins.
    static func recordTons(kind: ObjectKind, maxCompression: Double, seed: UInt64) -> Int {
        Tonnage.record(kind: kind, maxCompression: maxCompression, seed: seed)
    }

    /// The live needle target for compression `c`: the force (`Tonnage.live`). It climbs as the object fights, drops
    /// when it gives (`failed`), and arrives on `recordTons` at full crush.
    static func liveTons(kind: ObjectKind, compression c: Double, seed: UInt64, failed: Bool? = nil) -> Double {
        Tonnage.live(kind: kind, compression: c, seed: seed, failed: failed)
    }

    /// Dial angle in degrees (CCW from +x, y up) for a tonnage.
    static func dialDegrees(tons: Double) -> Double { 225 - 270 * tons / maxTons }
}

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

    /// Gauge angle (radians, CCW from +x, y up) for a tonnage on the 0–80 t dial (`PressGauge`).
    nonisolated static func gaugeAngle(tons: CGFloat) -> CGFloat {
        CGFloat(PressGauge.dialDegrees(tons: Double(tons))) * .pi / 180
    }

    /// The dial face: paper, graphite ring, 270° sweep, ticks, red zone 60–80 t, numerals 0 / 40 / 80 (the Fold
    /// crown's and the cover's scale, FOLD-REVIEW-4 F12), "TONS", "SQUISH".
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
            // Red zone: the top quarter, 60–80 t.
            let maxTons = CGFloat(PressGauge.maxTons)
            cg.setStrokeColor(Palette.stampRed.cgColor)
            cg.setLineWidth(14)
            cg.addArc(center: c, radius: R * 0.86, startAngle: -gaugeAngle(tons: CGFloat(PressGauge.redZoneTons)),
                      endAngle: -gaugeAngle(tons: maxTons), clockwise: false)
            cg.strokePath()
            // Ticks every 2.5 t: bold every 20 t (the numerals and the two between), medium every 10 t.
            cg.setLineCap(.round)
            let tickCount = Int((maxTons / 2.5).rounded())
            for i in 0...tickCount {
                let t = CGFloat(i) * 2.5
                let major = i % 8 == 0
                let medium = !major && i % 4 == 0
                cg.setStrokeColor(major || medium ? Palette.graphite.cgColor : Palette.inkSecondary.cgColor)
                cg.setLineWidth(major ? 5 : (medium ? 3.5 : 2))
                let outer = R * 0.92
                let inner = outer - (major ? 18 : (medium ? 13 : 9)) * size / 512
                cg.move(to: point(t, inner))
                cg.addLine(to: point(t, outer))
                cg.strokePath()
            }
            // Numerals 0 / 40 / 80 only. As on the Fold crown, the end numerals sit 5.5 t inside their ticks, so the
            // resting needle doesn't cover the "0".
            let numeralFont = roundedFont(40 * size / 512, .heavy)
            for t in [CGFloat(0), maxTons / 2, maxTons] {
                let text = "\(Int(t))" as NSString
                let attributes: [NSAttributedString.Key: Any] = [.font: numeralFont, .foregroundColor: Palette.graphite]
                let textSize = text.size(withAttributes: attributes)
                let nudge: CGFloat = t == 0 ? 5.5 : (t == maxTons ? -5.5 : 0)
                let p = point(t + nudge, R * 0.70)
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

    /// The paper tag for touch presses: "SEALED · 48 T" in SF Mono on paper with a punched hole.
    static func sealTag(tons: Int, width: CGFloat = 416, height: CGFloat = 176) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        let image = renderer.image { context in
            let cg = context.cgContext
            cg.setFillColor(Palette.paper.cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
            cg.setStrokeColor(Palette.stampRed.cgColor)
            cg.setLineWidth(6)
            cg.stroke(CGRect(x: 12, y: 12, width: width - 24, height: height - 24))
            cg.setFillColor(UIColor(hex: 0xE5DCCB).cgColor)
            cg.fillEllipse(in: CGRect(x: width / 2 - 9, y: 22, width: 18, height: 18))
            let text = "SEALED · \(tons) T" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 48, weight: .bold), .foregroundColor: Palette.graphite, .kern: 2,
            ]
            let size = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: (width - size.width) / 2, y: (height - size.height) / 2 + 14), withAttributes: attributes)
        }
        return image.cgImage
    }

    /// The FIZZO can print (VISUAL-TARGET §5.7): candy field, white wave band, the wordmark with a dark drop line,
    /// and a few large, sparse bubbles (never clustered). Wraps the can body once: x = around, y = up (row 0 = top).
    static func canLabel(field: UIColor, drop: UIColor, seed: UInt64, width: CGFloat = 1024, height: CGFloat = 512) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let font = roundedFont(height * 0.24, .black)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        let image = renderer.image { context in
            let cg = context.cgContext
            cg.setFillColor(field.cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
            // White wave band through the lower-middle (periodic so the seam matches).
            let path = UIBezierPath()
            let top = height * 0.56, bottom = height * 0.74, amp = height * 0.035
            path.move(to: CGPoint(x: 0, y: top))
            for k in 0...64 {
                let x = width * CGFloat(k) / 64
                path.addLine(to: CGPoint(x: x, y: top + amp * sin(CGFloat(k) / 64 * 4 * .pi)))
            }
            for k in stride(from: 64, through: 0, by: -1) {
                let x = width * CGFloat(k) / 64
                path.addLine(to: CGPoint(x: x, y: bottom + amp * sin(CGFloat(k) / 64 * 4 * .pi + 0.8)))
            }
            path.close()
            cg.setFillColor(UIColor(hex: 0xFFFFFF).cgColor)
            cg.addPath(path.cgPath)
            cg.fillPath()
            // Large sparse bubbles.
            var rng = SplitMix64(seed: seed)
            for k in 0..<7 {
                let r = CGFloat(Int(rng.next() % 20) + 14)
                let x = width * (CGFloat(k) + 0.5) / 7 + CGFloat(Int(rng.next() % 40) - 20)
                let y = height * (k % 2 == 0 ? 0.16 : 0.86) + CGFloat(Int(rng.next() % 30) - 15)
                cg.setStrokeColor(UIColor(white: 1, alpha: 0.85).cgColor)
                cg.setLineWidth(5)
                cg.strokeEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                cg.setFillColor(UIColor(white: 1, alpha: 0.85).cgColor)
                cg.fillEllipse(in: CGRect(x: x - r * 0.45, y: y - r * 0.55, width: r * 0.35, height: r * 0.35))
            }
            // Wordmark twice around the can, so one is always facing the camera.
            for k in 0..<2 {
                let text = "FIZZO" as NSString
                let size = text.size(withAttributes: [.font: font, .kern: 4])
                let origin = CGPoint(x: width * (0.25 + 0.5 * CGFloat(k)) - size.width / 2, y: height * 0.30 - size.height / 2)
                text.draw(at: CGPoint(x: origin.x + 6, y: origin.y + 7), withAttributes: [.font: font, .foregroundColor: drop, .kern: 4])
                text.draw(at: origin, withAttributes: [.font: font, .foregroundColor: UIColor(hex: 0xFFFFFF), .kern: 4])
            }
        }
        return image.cgImage
    }

    /// The crayon wrapper (VISUAL-TARGET §5.4): cream paper, a cobalt wave band with the "WAXO" wordmark, two thin
    /// stripes. x = around the crayon (u), y = along its axis (v, row 0 = the tip end); text runs along the axis.
    static func crayonWrapper(band: UIColor, width: CGFloat = 512, height: CGFloat = 512) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let font = roundedFont(width * 0.13, .black)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        let image = renderer.image { context in
            let cg = context.cgContext
            cg.setFillColor(UIColor(hex: 0xF4ECDD).cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
            cg.setFillColor(band.cgColor)
            // Thin stripes near both ends, the wide band in the middle.
            cg.fill(CGRect(x: 0, y: height * 0.06, width: width, height: height * 0.035))
            cg.fill(CGRect(x: 0, y: height * 0.90, width: width, height: height * 0.035))
            cg.fill(CGRect(x: 0, y: height * 0.24, width: width, height: height * 0.52))
            // Wordmark on the band, twice around, running along the axis (rotated 90° CCW).
            for k in 0..<2 {
                cg.saveGState()
                cg.translateBy(x: width * (0.25 + 0.5 * CGFloat(k)), y: height * 0.5)
                cg.rotate(by: -.pi / 2)
                let text = "WAXO" as NSString
                let size = text.size(withAttributes: [.font: font, .kern: 6])
                text.draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2),
                          withAttributes: [.font: font, .foregroundColor: UIColor(hex: 0xFFFFFF), .kern: 6])
                cg.restoreGState()
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
