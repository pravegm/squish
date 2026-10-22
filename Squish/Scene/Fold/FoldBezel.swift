import QuartzCore
import UIKit

/// Instruments state for one frame (logic mirrors the P-48's gauge and lamps, VISUAL-TARGET §4.4–4.5).
struct FoldInstruments {
    /// Displayed needle tonnage (0–60 dial, > 60 pins into the red).
    var needle: Double
    /// 0 off, 1 green / amber, 2 red.
    var ready: Int
    var load: Int
}

/// "The phone becomes the press" (§5): the 40 pt graphite crease band, the anvil's back lips, the yellow rails
/// down both halves (aligned across the crease), the mirrored hazard jaws on both free edges, the crown strip with
/// the 2D gauge, READY/LOAD lamps and the live hinge-angle plate (FOLD-REVIEW-3 N7: on a Duo the phone is the press,
/// so the plate shows its angle, not the P-48's model number), the console band with its pilot lamp, and the reveal's
/// goo strands — the only thing ever allowed across the crease (§3.4.6).
@MainActor
final class FoldBezel {
    let layer = CALayer()
    private let crease = CALayer()
    private let creaseShade = CAGradientLayer()
    private var lips: [CALayer] = []
    private var rails: [CALayer] = []
    private let platenJaw = CALayer()
    private let anvilJaw = CALayer()
    private let crown = CALayer()
    private let console = CALayer()
    private let platenFoot = CALayer()
    private let plateShade = CALayer()
    private let creaseShadePlaten = CAGradientLayer()
    private var readyLabelImage: CGImage?
    private var loadLabelImage: CGImage?
    private let gaugeFace = CALayer()
    private let gaugeRing = CAShapeLayer()
    private let needle = CAShapeLayer()
    private let hub = CALayer()
    private let gaugeGlass = CAGradientLayer()
    private let gaugeCrack = CAShapeLayer()
    private let readyLamp = CALayer()
    private let loadLamp = CALayer()
    private let pilotLamp = CALayer()
    private let readyLabel = CALayer()
    private let loadLabel = CALayer()
    private let nameplate = CALayer()
    /// The engraved hinge-angle readout on the nameplate ("118°"), re-rendered only when the shown degree changes.
    private let readout = CALayer()
    private var readoutImages: [Int: CGImage] = [:]
    private var readoutKey: Int?
    private var strands: [CAShapeLayer] = []
    private var strandAge: Double?
    private var strandColor = UIColor.white
    private var layout: FoldLayout?
    private var lampImages: [Int: CGImage] = [:]
    private var pilotImages: [Int: CGImage] = [:]
    private var lampState = (-1, -1)

    init() {
        for l in [crease, creaseShade, platenJaw, anvilJaw, crown, console] as [CALayer] { layer.addSublayer(l) }
        crease.backgroundColor = Palette.graphite.cgColor
        crown.backgroundColor = Palette.graphite.cgColor
        console.backgroundColor = Palette.graphite.cgColor
        creaseShade.colors = [Palette.graphite.withAlphaComponent(0.22).cgColor, Palette.graphite.withAlphaComponent(0).cgColor]
        for l in [gaugeFace, gaugeRing, needle, hub, gaugeGlass, gaugeCrack, readyLamp, loadLamp, readyLabel, loadLabel,
                  nameplate, readout, pilotLamp] as [CALayer] {
            layer.addSublayer(l)
        }
        gaugeRing.fillColor = nil
        gaugeRing.strokeColor = Palette.chrome.cgColor
        gaugeRing.lineWidth = 3
        needle.fillColor = Palette.stampRed.cgColor
        hub.backgroundColor = Palette.chrome.cgColor
        hub.borderColor = UIColor(hex: 0x8A8F98).cgColor
        hub.borderWidth = 0.5
        gaugeGlass.type = .radial
        gaugeGlass.colors = [UIColor(white: 1, alpha: 0.35).cgColor, UIColor(white: 1, alpha: 0).cgColor]
        gaugeGlass.startPoint = CGPoint(x: 0.32, y: 0.28)
        gaugeGlass.endPoint = CGPoint(x: 0.85, y: 0.85)
        gaugeCrack.fillColor = nil
        gaugeCrack.strokeColor = UIColor(white: 1, alpha: 0.85).cgColor
        gaugeCrack.lineWidth = 1
        for (state, color) in [(0, Palette.lampOff), (1, Palette.lampGreen), (2, Palette.lampRed), (3, Palette.lampAmber)] {
            if let image = FoldTextures.lamp(color, lit: state != 0, diameter: 14) { lampImages[state] = image }
            if let image = FoldTextures.lamp(color, lit: state != 0, diameter: 10) { pilotImages[state] = image }
        }
        // FOLD-REVIEW-1 #15: 9 pt SF Mono Semibold at 0.8 (6.5 pt at 0.55 was unreadable).
        readyLabelImage = FoldTextures.label("READY", size: 9, color: UIColor(white: 1, alpha: 0.8))
        loadLabelImage = FoldTextures.label("LOAD", size: 9, color: UIColor(white: 1, alpha: 0.8))
        readyLabel.contents = readyLabelImage
        loadLabel.contents = loadLabelImage
        platenFoot.backgroundColor = Palette.graphite.cgColor
        layer.insertSublayer(platenFoot, above: console)
        layer.insertSublayer(plateShade, at: 0)
        creaseShadePlaten.colors = [Palette.graphite.withAlphaComponent(0).cgColor, Palette.graphite.withAlphaComponent(0.22).cgColor]
        layer.insertSublayer(creaseShadePlaten, above: creaseShade)
    }

    func build(layout: FoldLayout) {
        self.layout = layout
        layer.frame = CGRect(origin: .zero, size: layout.canvas)
        crease.frame = layout.creaseRect
        let c = FoldMetrics.creaseHalf
        let all = 0...layout.lateralLength

        // Back lips: the anvil's back edge (§2.1, 6 pt graphite + 1 pt steel chamfer), mirrored on the platen.
        for l in lips { l.removeFromSuperlayer() }
        lips = []
        for sign in [-1.0, 1.0] {
            let depth = sign < 0 ? (-c - FoldMetrics.backLip)...(-c) : c...(c + FoldMetrics.backLip)
            let lip = CALayer()
            lip.frame = layout.rect(lateral: all, depth: depth)
            lip.backgroundColor = Palette.enamelGraphite.cgColor
            let chamfer = CALayer()
            let edge = sign < 0 ? (-c - FoldMetrics.backLip)...(-c - FoldMetrics.backLip + 1) : (c + FoldMetrics.backLip - 1)...(c + FoldMetrics.backLip)
            let r = layout.rect(lateral: all, depth: edge)
            chamfer.frame = r.offsetBy(dx: -lip.frame.minX, dy: -lip.frame.minY)
            chamfer.backgroundColor = Palette.brushedSteel.withAlphaComponent(0.85).cgColor
            lip.addSublayer(chamfer)
            layer.insertSublayer(lip, above: crease)
            lips.append(lip)
        }
        // A soft occlusion ramp off the anvil's back lip: debris near the crease fades under it (§2.3).
        let shadeDepth = (c + FoldMetrics.backLip)...(c + FoldMetrics.backLip + 24)
        creaseShade.frame = layout.rect(lateral: all, depth: shadeDepth)
        // The same ramp mirrored on the platen, so both lips read alike (FOLD-REVIEW-1 #8).
        creaseShadePlaten.frame = layout.rect(lateral: all, depth: (-shadeDepth.upperBound)...(-shadeDepth.lowerBound))
        for shade in [creaseShade, creaseShadePlaten] {
            if layout.isBook {
                shade.startPoint = CGPoint(x: 0, y: 0.5)
                shade.endPoint = CGPoint(x: 1, y: 0.5)
            } else {
                shade.startPoint = CGPoint(x: 0.5, y: 0)
                shade.endPoint = CGPoint(x: 0.5, y: 1)
            }
        }

        // Rails (§5): yellow enamel with a 1 pt highlight on the inner edge.
        for r in rails { r.removeFromSuperlayer() }
        rails = []
        for (i, rect) in layout.rails.enumerated() {
            let rail = CALayer()
            rail.frame = rect
            rail.backgroundColor = Palette.enamelYellow.cgColor
            let highlight = CALayer()
            let inner = i < 2   // the first two rails are at lateral 0 (inner edge at the far side of the rail)
            if layout.isBook {
                highlight.frame = CGRect(x: 0, y: inner ? rect.height - 1 : 0, width: rect.width, height: 1)
            } else {
                highlight.frame = CGRect(x: inner ? rect.width - 1 : 0, y: 0, width: 1, height: rect.height)
            }
            highlight.backgroundColor = UIColor(hex: 0xFFD36B).cgColor
            rail.addSublayer(highlight)
            layer.insertSublayer(rail, above: creaseShade)
            rails.append(rail)
        }

        // Hazard jaws on the two free edges, mirrored so they mesh when closed.
        platenJaw.frame = layout.platenJaw
        anvilJaw.frame = layout.anvilJaw
        platenJaw.contents = FoldTextures.hazardJaw(size: layout.platenJaw.size, alongX: !layout.isBook, mirror: true)
        anvilJaw.contents = FoldTextures.hazardJaw(size: layout.anvilJaw.size, alongX: !layout.isBook, mirror: false)

        // Crown strip: gauge (left / outer corner), READY + LOAD lamps, the P-48 nameplate.
        let cr = layout.crownStrip
        crown.frame = cr
        console.frame = layout.consoleBand
        let gaugeCentre = CGPoint(x: cr.minX + 38, y: cr.midY)
        let gaugeSize: CGFloat = 60   // FOLD-REVIEW-1 #15: 56 → 60 pt (the 64 pt strip leaves a 2 pt margin)
        gaugeFace.contents = FoldTextures.gaugeFace(diameter: gaugeSize - 6)
        let gaugeRect = CGRect(x: gaugeCentre.x - gaugeSize / 2, y: gaugeCentre.y - gaugeSize / 2, width: gaugeSize, height: gaugeSize)
        gaugeFace.frame = gaugeRect.insetBy(dx: 3, dy: 3)
        gaugeFace.cornerRadius = (gaugeSize - 6) / 2
        gaugeFace.masksToBounds = true
        gaugeRing.frame = gaugeRect
        gaugeRing.path = CGPath(ellipseIn: CGRect(x: 1.5, y: 1.5, width: gaugeSize - 3, height: gaugeSize - 3), transform: nil)
        let tip: CGFloat = 24, tail: CGFloat = 5
        let needlePath = CGMutablePath()
        needlePath.move(to: CGPoint(x: -1.9, y: tail))
        needlePath.addLine(to: CGPoint(x: 1.9, y: tail))
        needlePath.addLine(to: CGPoint(x: 0.6, y: -tip))
        needlePath.addLine(to: CGPoint(x: -0.6, y: -tip))
        needlePath.closeSubpath()
        needle.path = needlePath
        needle.bounds = .zero
        needle.position = gaugeCentre
        hub.bounds = CGRect(x: 0, y: 0, width: 8, height: 8)
        hub.cornerRadius = 4
        hub.position = gaugeCentre
        gaugeGlass.frame = gaugeRect.insetBy(dx: 3, dy: 3)
        gaugeGlass.cornerRadius = (gaugeSize - 6) / 2
        gaugeCrack.frame = gaugeRect
        gaugeCrack.path = nil

        let lampY = cr.midY - 7
        let readyX = layout.isBook ? cr.minX + 106 : cr.maxX - 94
        let loadX = layout.isBook ? cr.minX + 150 : cr.maxX - 46
        for (lamp, x) in [(readyLamp, readyX), (loadLamp, loadX)] {
            lamp.bounds = CGRect(x: 0, y: 0, width: 20, height: 20)
            lamp.position = CGPoint(x: x, y: lampY)
        }
        for (label, x) in [(readyLabel, readyX), (loadLabel, loadX)] {
            let image = label === readyLabel ? readyLabelImage : loadLabelImage
            let w = CGFloat(image?.width ?? 60) / 3, h = CGFloat(image?.height ?? 33) / 3
            label.bounds = CGRect(x: 0, y: 0, width: w, height: h)
            label.position = CGPoint(x: x, y: lampY + 19)
        }
        let plateSize = CGSize(width: 92, height: 24)
        nameplate.contents = FoldTextures.nameplate(size: plateSize)
        nameplate.bounds = CGRect(origin: .zero, size: plateSize)
        // Narrow (non-Duo) canvases: keep the nameplate beside the gauge, clear of a centred camera cut-out.
        let narrow = !layout.isBook && layout.canvas.width < 500
        nameplate.position = CGPoint(x: layout.isBook ? cr.minX + 258 : (narrow ? cr.minX + 120 : cr.midX),
                                     y: narrow ? cr.maxY - 16 : cr.midY)
        readout.position = nameplate.position
        readoutKey = nil

        // Book: the platen page's empty foot band mirrors the anvil console (bands mesh when shut).
        if let foot = layout.platenFoot {
            platenFoot.frame = foot
            platenFoot.isHidden = false
        } else {
            platenFoot.isHidden = true
        }
        // The lid's shade on the anvil (§2.4, FOLD-REVIEW-2 #3): the platen plate's soft footprint, offset 12 pt toward
        // the crease, blur 28, kept inside the plate + 8 pt (rounded), so no rectangular halo on the enamel.
        let plate = layout.strikePlate(platen: false)
        let canvas = plate.insetBy(dx: -8, dy: -8)
        let towardCrease: CGPoint = layout.isBook ? CGPoint(x: -12, y: 0) : CGPoint(x: 0, y: -12)
        let shape = plate.insetBy(dx: 22, dy: 22).offsetBy(dx: towardCrease.x, dy: towardCrease.y)
        plateShade.contents = FoldTextures.plateShade(canvas: canvas.size,
                                                      shape: shape.offsetBy(dx: -canvas.minX, dy: -canvas.minY),
                                                      radius: CGFloat(FoldMetrics.plateRadius), blur: 28,
                                                      clipRadius: CGFloat(FoldMetrics.plateRadius) + 8)
        plateShade.frame = canvas
        plateShade.opacity = 0

        let cb = layout.consoleBand
        pilotLamp.bounds = CGRect(x: 0, y: 0, width: 16, height: 16)
        pilotLamp.position = CGPoint(x: cb.maxX - 26, y: cb.midY)
        lampState = (-1, -1)
    }

    // MARK: Per frame

    func update(_ instruments: FoldInstruments, frame f: FoldFrame) {
        // Dial angle α = 225° − 270°·t/60 (CCW from +x); the needle is drawn at 12 o'clock (90°), and
        // UIKit rotations are clockwise-positive on screen.
        let tons = min(max(instruments.needle, -1), Double(FoldTextures.gaugeMaxTons) + 3)
        needle.setAffineTransform(CGAffineTransform(rotationAngle: FoldTextures.needleRotation(tons: tons)))
        // Plate shade (FOLD-REVIEW-2 #3): driven by the virtual gap, never latched, so it lifts as the press opens
        // and is gone at the reveal; 0.18·a² peak.
        let a = clamp(f.approach, 0, 1)
        plateShade.opacity = Float(0.18 * a * a)
        if lampState != (instruments.ready, instruments.load) {
            readyLamp.contents = lampImages[instruments.ready == 1 ? 1 : (instruments.ready == 2 ? 2 : 0)]
            let load = instruments.load == 1 ? 3 : (instruments.load == 2 ? 2 : 0)
            loadLamp.contents = lampImages[load]
            pilotLamp.contents = pilotImages[load]
            lampState = (instruments.ready, instruments.load)
        }
        updateReadout(f)
        updateStrands(f)
    }

    /// The live hinge angle in whole degrees, ticking with θ; frozen in stamp red at the failure angle until the next
    /// object (FOLD-REVIEW-3 N7).
    private func updateReadout(_ f: FoldFrame) {
        let value = f.failureAngle ?? f.angle
        guard value.isFinite else { return }
        let degrees = Int(min(max(value, 0), 180).rounded())
        let red = f.failureAngle != nil
        let key = degrees * 2 + (red ? 1 : 0)
        guard key != readoutKey else { return }
        readoutKey = key
        if readoutImages[key] == nil {
            if readoutImages.count > 96 { readoutImages.removeAll() }
            readoutImages[key] = FoldTextures.engraved("\(degrees)°", fontSize: 16, red: red)
        }
        let image = readoutImages[key]
        readout.contents = image
        readout.bounds = CGRect(x: 0, y: 0, width: CGFloat(image?.width ?? 0) / 3, height: CGFloat(image?.height ?? 0) / 3)
    }

    /// The Unsquishable cracks the gauge glass (§5).
    func crackGauge(seed: UInt64) {
        var rng = SplitMix64(seed: seed ^ 0x6A6E)
        let path = CGMutablePath()
        let c = CGPoint(x: 30, y: 30)
        for k in 0..<3 {
            let a = CGFloat(k) * 2.1 + CGFloat.random(in: -0.3...0.3, using: &rng)
            path.move(to: CGPoint(x: c.x + cos(a) * 4, y: c.y + sin(a) * 4))
            path.addLine(to: CGPoint(x: c.x + cos(a + 0.2) * 14, y: c.y + sin(a + 0.2) * 14))
            path.addLine(to: CGPoint(x: c.x + cos(a - 0.1) * 24, y: c.y + sin(a - 0.1) * 24))
        }
        gaugeCrack.path = path
    }

    func repair() {
        gaugeCrack.path = nil
        endStrands()
    }

    // MARK: Goo strands (§6.3 step 2)

    func startStrands(count: Int, color: UIColor, seed: UInt64) {
        endStrands()
        guard count > 0 else { return }
        strandColor = color
        var rng = SplitMix64(seed: seed ^ 0x5742)
        for _ in 0..<(count * 2) {
            let s = CAShapeLayer()
            s.fillColor = color.withAlphaComponent(0.9).cgColor
            s.strokeColor = nil
            s.setValue(CGFloat.random(in: -70...70, using: &rng), forKey: "squishLateral")
            layer.addSublayer(s)
            strands.append(s)
        }
        strandAge = 0
    }

    private func endStrands() {
        for s in strands { s.removeFromSuperlayer() }
        strands = []
        strandAge = nil
    }

    private func updateStrands(_ f: FoldFrame) {
        guard let layout, var age = strandAge else { return }
        age += f.dt
        strandAge = age
        let duration = 0.6
        if age >= duration {
            endStrands()
            return
        }
        let snapAt = duration * 0.4
        for (i, s) in strands.enumerated() {
            let platen = i % 2 == 0
            let offset = (s.value(forKey: "squishLateral") as? CGFloat) ?? 0
            let lateral = layout.lateralCentre + Double(offset)
            let sign = platen ? -1.0 : 1.0
            let from = sign * (FoldMetrics.footprintDepth - 70)
            // Before the snap the strand reaches the crease midline (meeting its partner); after, it retracts.
            var reach = 1.0
            var width = 9.0 * (1 - 0.7 * age / snapAt)
            if age > snapAt {
                let t = (age - snapAt) / (duration - snapAt)
                reach = 1 - t
                width = 3.5 * (1 - t) + 1
            }
            if f.reduceMotion {
                reach = 1
                width = 5
                s.opacity = Float(1 - age / duration)
            }
            let to = from + (0 - from) * reach
            s.path = Self.taper(layout: layout, lateral: lateral, from: from, to: to, base: 12, tip: max(width, 1))
        }
    }

    /// A tapered, slightly bowed strand between two depths at one lateral position.
    private static func taper(layout: FoldLayout, lateral: Double, from: Double, to: Double, base: Double, tip: Double) -> CGPath {
        let bow = (to - from) * 0.08
        let path = CGMutablePath()
        let a0 = layout.point(lateral: lateral - base / 2, depth: from)
        let a1 = layout.point(lateral: lateral + base / 2, depth: from)
        let b0 = layout.point(lateral: lateral - tip / 2 + bow, depth: to)
        let b1 = layout.point(lateral: lateral + tip / 2 + bow, depth: to)
        let m0 = layout.point(lateral: lateral - tip / 2 + bow * 2, depth: (from + to) / 2)
        let m1 = layout.point(lateral: lateral + tip / 2 + bow * 2, depth: (from + to) / 2)
        path.move(to: a0)
        path.addQuadCurve(to: b0, control: m0)
        path.addLine(to: b1)
        path.addQuadCurve(to: a1, control: m1)
        path.closeSubpath()
        return path
    }
}
