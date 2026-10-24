import QuartzCore
import UIKit

/// What the 2D halves need each frame (built by `FoldPressController` from the engine).
struct FoldFrame {
    /// Real (filtered) hinge angle, degrees: drives only the sheen and the dimming (§3.3).
    var angle: Double
    /// 0…1 approach of the virtual plate before contact (§4.4).
    var approach: Double
    /// Compression the hand is asking for right now.
    var compression: Double
    /// Ratcheted compression of the print: ink is permanent (§6.3).
    var printCompression: Double
    var contacted: Bool
    var tell: Bool
    var failureCompression: Double?
    /// The object has landed on the anvil (the approach shadow appears with it).
    var objectPresent: Bool
    var tabletop: Bool
    var reduceMotion: Bool
    var time: Double
    var dt: Double
    /// Invitation sweep override (§7): 0 = far edge … 1 = crease; nil follows the real angle.
    var sweep: Double?
    /// The sweep is the fold invitation (not the reveal's peel shimmer): the grip pads pulse with it.
    var inviting = false
    /// The hinge angle the object failed at, once it has (the crown readout freezes on it, in red).
    var failureAngle: Double? = nil
    /// 0…1: the anvil's edges darken as the tension narrows attention onto the object (the tell, a held press, the
    /// hush; EXPERIENCE-2 §A3.1: 0 → 12 % edge darkening).
    var vignette: Double = 0
}

/// One object's print on the platen (§9.5 items 5–7), in print space: approach shadows, the growing ink (masked by a
/// soft ellipse), Newton's rings (masked by the silhouette), the failure splat, the accumulated fracture stamps and
/// the kiss highlight. Replaced (with a squeegee wipe) when the next object goes on.
@MainActor
final class FoldPrintStack {
    let stamp: FoldStamp
    let root = CALayer()
    private let shadows = [CALayer(), CALayer(), CALayer()]
    private let ink = CALayer()
    private let growth = CALayer()
    private let ringsHolder = CALayer()
    private let ringsMask = CALayer()
    private let rings = CALayer()
    private let splat = CALayer()
    private let decal = CALayer()
    private let kiss = CALayer()
    private let glint = CALayer()
    private let wipeMask = CAGradientLayer()
    private let squeegee = CALayer()
    private var decalContext: CGContext?
    /// The failure splat's scale about the footprint centre (it spreads with compression after the failure); the
    /// anvil's escaped droplets ride out with it.
    private(set) var splatScale: Double = 0
    /// The blurs the approach-shadow images were rendered at (`FoldStamps.shadowBlurs`).
    private let shadowStops: [Double]
    private var kissLevel: Double = 0
    private var pulse: Double = 0
    private var ripples: [(centre: CGPoint, radius: CGFloat, age: Double, layer: CAShapeLayer)] = []
    private(set) var wipeProgress: Double?
    private var contactAge: Double = 0
    private(set) var variant: PressVariant

    init(stamp: FoldStamp, variant: PressVariant, softDisc: CGImage?, rings ringImage: CGImage?) {
        self.stamp = stamp
        self.variant = variant
        shadowStops = FoldStamps.shadowBlurs(stamp.kind).map { Double($0) }
        let canvas = FoldPrintCanvas.rect
        root.bounds = canvas
        for layer in shadows + [ink, ringsHolder, splat, decal] {
            Self.place(layer, canvas)
            root.addSublayer(layer)
        }
        for layer in shadows { layer.opacity = 0 }
        ink.opacity = 0
        growth.contents = softDisc
        ink.mask = growth
        Self.place(ringsMask, canvas)
        ringsHolder.mask = ringsMask
        rings.contents = ringImage
        rings.opacity = 0
        ringsHolder.addSublayer(rings)
        splat.opacity = 0
        kiss.contents = FoldStamps.softDisc(size: 64, feather: 0.6)
        kiss.bounds = CGRect(x: 0, y: 0, width: 18, height: 18)
        kiss.position = stamp.apex
        kiss.opacity = 0
        root.addSublayer(kiss)
        // Ink, not clip-art (FOLD-REVIEW-1 #6): multiply onto the steel so its streaks show through. Glass frost is
        // white, which multiply would erase, so it stays normal.
        if stamp.kind != .glassBottle && stamp.kind != .unsquishable {
            ink.compositingFilter = "multiplyBlendMode"
        }
        // One specular glint on the wet core, from the kiss until c ≈ 0.3.
        glint.contents = FoldStamps.softDisc(size: 32, feather: 0.7)
        glint.bounds = CGRect(x: 0, y: 0, width: 7, height: 3.5)
        glint.position = CGPoint(x: stamp.apex.x - 5, y: stamp.apex.y - 4)
        glint.opacity = 0
        root.addSublayer(glint)
        decalContext = Self.makeContext(rect: canvas, scale: 2)
        // Squeegee (§6.3 step 6): a steel blade drawn across the plate while the print wipes off.
        squeegee.backgroundColor = Palette.plateSteel.cgColor
        squeegee.borderColor = UIColor(hex: 0x8A8F98).cgColor
        squeegee.borderWidth = 1
        squeegee.bounds = CGRect(x: 0, y: 0, width: FoldMetrics.plateLateral + 30, height: 7)
        squeegee.isHidden = true
        root.addSublayer(squeegee)
    }

    /// Fills in the object's images once they are rendered off the main actor.
    func setImages(ink inkImage: CGImage?, mask: CGImage?, shadows shadowImages: [CGImage?]) {
        inkCG = inkImage
        ink.contents = inkImage
        ringsMask.contents = mask
        for (layer, image) in zip(shadows, shadowImages) { layer.contents = image }
    }

    /// Bounds = rect, centred, so the layer's own coordinates are its parent's (print space).
    static func place(_ layer: CALayer, _ rect: CGRect) {
        layer.bounds = rect
        layer.position = CGPoint(x: rect.midX, y: rect.midY)
    }

    /// A persistent y-down drawing context in points whose origin is `rect.origin` (the fracture stamps accumulate).
    static func makeContext(rect: CGRect, scale: CGFloat) -> CGContext? {
        let w = max(1, Int((rect.width * scale).rounded(.up)))
        let h = max(1, Int((rect.height * scale).rounded(.up)))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.translateBy(x: -rect.minX, y: -rect.minY)
        return ctx
    }

    // MARK: Events

    func kissNow(reduceMotion: Bool) {
        kissLevel = reduceMotion ? 0.6 : 1
        contactAge = 0
        if stamp.kind == .sodaCan, let ctx = decalContext {
            // The can's rim meets the plate first: a ring stamp (§3.2).
            FoldStamps.ring(ctx, .zero, stamp.featureRadius, 2.0, stamp.inkEdge.withAlphaComponent(0.7))
            decal.contents = ctx.makeImage()
        }
    }

    func fracture(index: Int, isFailure: Bool, compression: Double, reduceMotion: Bool) -> FoldPrintEffect {
        var effect = FoldPrintEffect.none
        if let ctx = decalContext {
            effect = FoldStamps.drawFracture(index: index, isFailure: isFailure, stamp: stamp, into: ctx,
                                             compression: compression)
            decalCG = ctx.makeImage()
            decal.contents = decalCG
        }
        if isFailure {
            splatCG = FoldStamps.splatImage(stamp, variant: variant)
            splat.contents = splatCG
            splat.opacity = 1
            splatScale = reduceMotion ? 0.9 : 0.55
        }
        switch effect {
        case let .ripple(centre, radius):
            let ring = CAShapeLayer()
            ring.fillColor = nil
            ring.strokeColor = stamp.inkEdge.withAlphaComponent(0.7).cgColor
            ring.lineWidth = 2
            root.addSublayer(ring)
            ripples.append((centre, radius, 0, ring))
            _ = reduceMotion
        case .pulse:
            pulse = 1
        case .none, .platenBreaks:
            break
        }
        return effect
    }

    func beginWipe() {
        guard wipeProgress == nil else { return }
        wipeProgress = 0
        wipeMask.colors = [UIColor.clear.cgColor, UIColor.clear.cgColor, UIColor.black.cgColor, UIColor.black.cgColor]
        wipeMask.startPoint = CGPoint(x: 0.5, y: 0)
        wipeMask.endPoint = CGPoint(x: 0.5, y: 1)
        Self.place(wipeMask, FoldPrintCanvas.rect)
        root.mask = wipeMask
        squeegee.isHidden = false
    }

    // MARK: Per frame

    func update(_ f: FoldFrame) {
        let R = stamp.growthRadii
        contactAge += f.dt
        // 1. Approach shadow (§3.2 step 1, §4.4): sharpens and darkens as the virtual gap closes.
        let gap = f.contacted ? 0 : 1 - f.approach
        let shadow = FoldCurve.shadow(gap: gap)
        let sheet = stamp.kind == .bubbleWrap
        // Small objects vanish under a 40 pt blur (FOLD-REVIEW-2 #4: no shadow for duck/can at 180°): cap it at 28.
        // Sheets are the opposite (FOLD-REVIEW-3 N15): a film-sized shadow sharper than 28 pt reads as a box.
        let blur = sheet ? clamp(shadow.blur, 28, 40) : min(shadow.blur, 28)
        let weights = FoldStamps.shadowWeights(blur: blur, stops: shadowStops)
        let presence = f.objectPresent ? 1.0 : 0
        let under = f.contacted ? 0.22 : 1
        // Flat (gap 1) the spec's 0.08 is invisible on steel under a small object: start those at 0.14 so the plates
        // belong together at 180°. A sheet's shadow (its domes, `FoldStamps.shadowOutline`) barely grows with the gap
        // (at 1.25× it washed past the whole plate at 180° and read as no shadow at all) and was a 0.35 block at 150°.
        // FOLD-REVIEW-5 F8: and a flat sheet under an open lid casts nothing (its 0.08 start was the 180° "grey
        // ghost"); the domes' shadow only gathers as the lid comes down, to 0.22 at contact.
        let lift = clamp(1 - gap, 0, 1)
        let alpha = sheet ? 0.22 * lift * lift.squareRoot() : max(shadow.alpha, 0.14)
        let scale = CGFloat(sheet ? 1 + 0.06 * clamp(gap, 0, 1) : shadow.scale)
        for (layer, w) in zip(shadows, weights) {
            layer.opacity = Float(alpha * w * presence * under)
            layer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        }

        // 2–3. Kiss → print (§3.2): r = R·min(1, 1.1√c), soft edge, saturation with c; the edge trembles in the tell.
        let fraction = FoldCurve.printFraction(compression: f.printCompression)
        var rx = Double(R.width), ry = Double(R.height)
        var inkOpacity = 0.0
        if f.contacted {
            switch stamp.contact {
            case .point:
                rx = max(rx * fraction, 7)
                ry = max(ry * fraction, 7)
                inkOpacity = 0.6 + 0.4 * min(1, fraction * 1.3)
            case .line:
                rx *= max(fraction, 0.85 * min(1, contactAge / 0.08))
                ry = max(ry * fraction, 2.5)
                inkOpacity = 0.6 + 0.4 * min(1, fraction * 1.3)
            case .uniform:
                inkOpacity = 0.35 + 0.65 * min(1, f.printCompression * 3)
            case .fixedRing:
                rx = Double(stamp.featureRadius) + 2
                ry = rx
                inkOpacity = 0.7 + 0.3 * min(1, f.printCompression * 2)
            }
            if f.tell && !f.reduceMotion && stamp.contact != .fixedRing {
                let tremble = sin(f.time * 2 * .pi * 14)
                rx += tremble
                ry += tremble
            }
        }
        ink.opacity = Float(inkOpacity)
        lastInk = (inkOpacity, CGSize(width: rx * 1.08, height: ry * 1.08))
        growth.bounds = CGRect(x: 0, y: 0, width: 2 * rx * 1.08, height: 2 * ry * 1.08)
        growth.position = stamp.apex
        growth.setAffineTransform(CGAffineTransform(rotationAngle: stamp.growthAngle))

        // Newton's rings just outside the contact edge (alpha 0.06 + 0.10·c); the ball's ring is the bright one.
        if f.contacted {
            pulse *= pow(0.5, f.dt / 0.12)
            let ball = stamp.contact == .fixedRing
            // FOLD-REVIEW-1 #6: 0.10 + 0.15·c (they were invisible), fading once the print has filled.
            let alpha = ball ? 0.55 + 0.45 * min(1, f.printCompression * 2) + 0.4 * pulse
                : (0.10 + 0.15 * f.printCompression) * clamp((1.05 - fraction) / 0.25, 0, 1)
            rings.opacity = Float(min(alpha * (stamp.contact == .uniform ? 0 : 1), 1))
            let k = ball ? 1.25 + 0.5 * pulse : 1 / 0.82
            rings.bounds = CGRect(x: 0, y: 0, width: 2 * rx * k, height: 2 * ry * k)
            rings.position = stamp.apex
            rings.setAffineTransform(CGAffineTransform(rotationAngle: stamp.growthAngle))
        } else {
            rings.opacity = 0
        }

        // 4–5. Splat, then the monoprint spreads with the anvil's mess.
        if let failC = f.failureCompression, splat.opacity > 0 {
            let spread = clamp((f.printCompression - failC) / max(1 - failC, 0.05), 0, 1)
            // Glass frost is pressed into the plate; it doesn't spread (scaling it pushed it past the steel).
            let target = stamp.kind == .glassBottle ? 1 : 0.85 + 0.35 * spread
            splatScale += (target - splatScale) * (1 - pow(0.5, f.dt / 0.045))
            splat.setAffineTransform(CGAffineTransform(scaleX: CGFloat(splatScale), y: CGFloat(splatScale)))
        }

        // Kiss highlight: one bright wet dot, gone in a few frames.
        kiss.opacity = Float(kissLevel)
        let wetness = f.contacted ? clamp(1 - f.printCompression / 0.3, 0, 1) : 0
        glint.opacity = Float(0.5 * wetness) * (stamp.kind == .glassBottle ? 0 : 1)
        kissLevel *= pow(0.5, f.dt / 0.05)
        if kissLevel < 0.02 { kissLevel = 0 }

        for i in ripples.indices.reversed() {
            ripples[i].age += f.dt
            let t = ripples[i].age / 0.45
            if t >= 1 || f.reduceMotion {
                ripples[i].layer.removeFromSuperlayer()
                ripples.remove(at: i)
                continue
            }
            let r = ripples[i].radius * CGFloat(0.4 + 1.2 * t)
            let c = ripples[i].centre
            ripples[i].layer.path = CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r), transform: nil)
            ripples[i].layer.opacity = Float(1 - t)
        }

        // Squeegee wipe: crease → far edge (print-space y grows away from the hinge on both halves), 350 ms.
        if var w = wipeProgress {
            w += f.dt / 0.35
            wipeProgress = w
            if f.reduceMotion {
                root.opacity = Float(max(0, 1 - w))
                squeegee.isHidden = true
            } else {
                let edge = w * 1.1 - 0.05
                wipeMask.locations = [0, NSNumber(value: clamp(edge, 0, 1)), NSNumber(value: clamp(edge + 0.04, 0, 1)), 1]
                let canvas = FoldPrintCanvas.rect
                squeegee.position = CGPoint(x: 0, y: canvas.minY + canvas.height * CGFloat(clamp(edge, 0, 1)))
            }
        }
    }

    var isWiped: Bool { (wipeProgress ?? 0) >= 1 }

    // MARK: The monoprint as an image (FOLD-PRESS §6.3 diptych, FOLD-REVIEW-1 #12)

    private var inkCG: CGImage?
    private var decalCG: CGImage?
    private var splatCG: CGImage?
    private var lastInk: (opacity: Double, radii: CGSize) = (0, .zero)

    var hasPrint: Bool { lastInk.opacity > 0.01 || splatCG != nil || decalCG != nil }

    /// The print exactly as it lies on the platen (mirrored across the crease, crease side at the bottom), on the
    /// steel strike plate, cropped to the plate + 40 pt. No bezel.
    func renderPrint(scale: CGFloat = 2) -> CGImage? {
        guard hasPrint else { return nil }
        let canvas = FoldPrintCanvas.rect
        let plateSize = CGSize(width: FoldMetrics.plateLateral, height: FoldMetrics.plateDepth)
        let plate = FoldTextures.strikePlate(size: plateSize, radius: CGFloat(FoldMetrics.plateRadius), streaksAlongX: true)
        let stamp = self.stamp
        let ink = inkCG, decal = decalCG, splat = splatCG
        let inkState = lastInk, splatScale = CGFloat(self.splatScale)
        return FoldStamps.image(rect: canvas, scale: scale) { ctx in
            /// CG draws images bottom-up; our contexts are y-down, so flip around the rect for each image.
            func draw(_ image: CGImage?, in rect: CGRect) {
                guard let image else { return }
                ctx.saveGState()
                ctx.translateBy(x: 0, y: rect.minY + rect.maxY)
                ctx.scaleBy(x: 1, y: -1)
                ctx.draw(image, in: rect)
                ctx.restoreGState()
            }
            ctx.setFillColor(Palette.paper.cgColor)
            ctx.fill(canvas)
            draw(plate, in: CGRect(x: -plateSize.width / 2, y: -plateSize.height / 2, width: plateSize.width, height: plateSize.height))
            // The platen's mirror (§3.4): print space y → −y.
            ctx.scaleBy(x: 1, y: -1)
            if inkState.opacity > 0.01 {
                ctx.saveGState()
                ctx.translateBy(x: stamp.apex.x, y: stamp.apex.y)
                ctx.rotate(by: stamp.growthAngle)
                ctx.addEllipse(in: CGRect(x: -inkState.radii.width, y: -inkState.radii.height,
                                          width: 2 * inkState.radii.width, height: 2 * inkState.radii.height))
                ctx.rotate(by: -stamp.growthAngle)
                ctx.translateBy(x: -stamp.apex.x, y: -stamp.apex.y)
                ctx.clip()
                ctx.setAlpha(CGFloat(inkState.opacity))
                ctx.setBlendMode(stamp.kind == .glassBottle ? .normal : .multiply)
                draw(ink, in: canvas)
                ctx.restoreGState()
            }
            if splat != nil {
                ctx.saveGState()
                ctx.scaleBy(x: splatScale, y: splatScale)
                draw(splat, in: canvas)
                ctx.restoreGState()
            }
            draw(decal, in: canvas)
        }
    }
}

/// The top half (§3): the platen face as a 2D Core Animation stack. Zero-depth content only, so it stays true from
/// any eye at any angle. Enamel field, brushed-steel strike plate (mirror of the anvil's), bolts, guide pins, the
/// θ-driven sheen, the print stack, the Unsquishable's crack, the PRESSED stamp and the tabletop dimming.
@MainActor
final class FoldPlaten {
    let layer = CALayer()
    private let field = CALayer()
    private let fieldLight = CAGradientLayer()
    private let plate = CALayer()
    private let sheenHolder = CALayer()
    private let sheenMask = CALayer()
    private let sheen = CAGradientLayer()
    private var bolts: [CALayer] = []
    private var pins: [CALayer] = []
    private var pinRims: [CALayer] = []
    private var gripPads: [CALayer] = []
    private let crack = CAShapeLayer()
    private let crackLight = CAShapeLayer()
    private let printHolder = CALayer()
    private let pressed = CALayer()
    private let dim = CALayer()
    private var layout: FoldLayout?
    private(set) var stack: FoldPrintStack?
    private var outgoing: [FoldPrintStack] = []
    private var pressedAge: Double?
    /// The specimen's seed: the PRESSED stamp's offset and tilt follow it (FOLD-REVIEW-3 N12).
    private var pressedSeed: UInt64 = 0
    private var pressedAngle: CGFloat = -0.14
    /// The stamp in red ink, and in paper-white ink with a red keyline for prints too close to red to show it.
    private var pressedRed: CGImage?
    private var pressedPaper: CGImage?
    /// The stamp's word: how the press was closed (`CloseStyle`), PRESSED until the press seals.
    private var pressedText = CloseStyle.pressed.stampText
    private var poppedBolt: (layer: CALayer, age: Double, start: CGPoint)?
    private let softDisc = FoldStamps.softDisc()
    private let ringImage = FoldStamps.newtonRings()

    init() {
        layer.masksToBounds = true
        layer.addSublayer(field)
        layer.addSublayer(fieldLight)
        layer.addSublayer(plate)
        layer.addSublayer(sheenHolder)
        sheenHolder.mask = sheenMask
        sheenHolder.addSublayer(sheen)
        layer.addSublayer(crackLight)
        layer.addSublayer(crack)
        layer.addSublayer(printHolder)
        layer.addSublayer(pressed)
        layer.addSublayer(dim)
        dim.backgroundColor = UIColor.black.cgColor
        dim.opacity = 0
        pressed.opacity = 0
        crack.fillColor = nil
        crack.strokeColor = Palette.graphite.cgColor
        crack.lineWidth = 4
        crack.lineJoin = .round
        crack.lineCap = .round
        crackLight.fillColor = nil
        crackLight.strokeColor = UIColor(white: 1, alpha: 0.7).cgColor
        crackLight.lineWidth = 1.2
        crackLight.lineJoin = .round
        // FOLD-REVIEW-1 #13: a 44 pt band at ≈ 0.40 with a 6 pt core at 0.6, screen-blended so it reads on the steel.
        sheen.colors = [UIColor(white: 1, alpha: 0).cgColor, UIColor(white: 1, alpha: 0.66).cgColor,
                        UIColor(white: 1, alpha: 1).cgColor, UIColor(white: 1, alpha: 0.66).cgColor,
                        UIColor(white: 1, alpha: 0).cgColor]
        sheen.locations = [0, 0.38, 0.5, 0.62, 1]
        sheen.compositingFilter = "screenBlendMode"
        fieldLight.colors = [UIColor(white: 1, alpha: 0.10).cgColor, UIColor(white: 1, alpha: 0).cgColor,
                             UIColor(white: 0, alpha: 0.04).cgColor]
        fieldLight.locations = [0, 0.5, 1]
        fieldLight.startPoint = CGPoint(x: 0, y: 0)
        fieldLight.endPoint = CGPoint(x: 1, y: 1)
    }

    func build(layout: FoldLayout) {
        self.layout = layout
        let half = layout.platenHalf
        layer.frame = half
        layer.bounds = half   // children use canvas coordinates
        field.frame = half
        fieldLight.frame = half
        dim.frame = half

        let plateRect = layout.strikePlate(platen: true)
        plate.frame = plateRect
        plate.contents = FoldTextures.strikePlate(size: plateRect.size, radius: CGFloat(FoldMetrics.plateRadius),
                                                  streaksAlongX: !layout.isBook)
        sheenHolder.frame = plateRect
        sheenMask.frame = CGRect(origin: .zero, size: plateRect.size)
        sheenMask.contents = FoldTextures.plateMask(size: plateRect.size, radius: CGFloat(FoldMetrics.plateRadius))
        if layout.isBook {
            sheen.startPoint = CGPoint(x: 0, y: 0.5)
            sheen.endPoint = CGPoint(x: 1, y: 0.5)
        } else {
            sheen.startPoint = CGPoint(x: 0.5, y: 0)
            sheen.endPoint = CGPoint(x: 0.5, y: 1)
        }

        for l in bolts + pins + pinRims { l.removeFromSuperlayer() }
        bolts = []
        pins = []
        pinRims = []
        let boltImage = FoldTextures.bolt(diameter: CGFloat(FoldMetrics.boltDiameter))
        for p in layout.bolts(platen: true) {
            let b = CALayer()
            b.contents = boltImage
            b.bounds = CGRect(x: 0, y: 0, width: FoldMetrics.boltDiameter + 4, height: FoldMetrics.boltDiameter + 4)
            b.position = p
            layer.insertSublayer(b, above: sheenHolder)
            bolts.append(b)
        }
        // FOLD-REVIEW-2 #12: the same dark stud as the anvil's bushing; the bright rim only arrives after 150°.
        let pinImage = FoldTextures.pin(diameter: CGFloat(FoldMetrics.pinDiameter), ring: true)
        for p in layout.guidePins(platen: true) {
            let pin = CALayer()
            pin.contents = pinImage
            pin.bounds = CGRect(x: 0, y: 0, width: FoldMetrics.pinDiameter + 4, height: FoldMetrics.pinDiameter + 4)
            pin.position = p
            layer.insertSublayer(pin, above: sheenHolder)
            pins.append(pin)
            let rim = CALayer()
            rim.bounds = CGRect(x: 0, y: 0, width: FoldMetrics.pinDiameter + 3, height: FoldMetrics.pinDiameter + 3)
            rim.cornerRadius = CGFloat(FoldMetrics.pinDiameter + 3) / 2
            rim.borderColor = UIColor(white: 1, alpha: 1).cgColor
            rim.borderWidth = 2
            rim.shadowColor = UIColor.white.cgColor
            rim.shadowOpacity = 0.6
            rim.shadowRadius = 2
            rim.shadowOffset = .zero
            rim.shadowPath = CGPath(ellipseIn: rim.bounds, transform: nil)
            rim.position = p
            rim.opacity = 0
            layer.insertSublayer(rim, above: pin)
            pinRims.append(rim)
        }
        // Grip pads (§7.3, FOLD-REVIEW-2 #11): two soft amber pads at the platen's far corners, where you'd pick up
        // a lid; they pulse with the invitation sweep only.
        for pad in gripPads { pad.removeFromSuperlayer() }
        gripPads = []
        let padImage = FoldStamps.softDisc(size: 96, feather: 0.9, color: Palette.hydraulicYellow)
        let corners: [CGPoint]
        if layout.isBook {
            let d = -layout.platenReach + FoldMetrics.jaw + 26
            corners = [layout.point(lateral: layout.platenFieldLateral.lowerBound + 26, depth: d),
                       layout.point(lateral: layout.platenFieldLateral.upperBound - 26, depth: d)]
        } else {
            let d = layout.platenRailDepth.lowerBound + 26
            corners = [layout.point(lateral: FoldMetrics.rail + 26, depth: d),
                       layout.point(lateral: layout.lateralLength - FoldMetrics.rail - 26, depth: d)]
        }
        for c in corners {
            let pad = CALayer()
            pad.contents = padImage
            pad.bounds = CGRect(x: 0, y: 0, width: 64, height: 64)
            pad.position = c
            pad.opacity = 0
            layer.insertSublayer(pad, below: dim)
            gripPads.append(pad)
        }
        printHolder.frame = half
        printHolder.bounds = half
        for s in [stack].compactMap({ $0 }) + outgoing { position(s) }
        if pressedRed == nil {
            pressedRed = FoldTextures.pressedStamp(width: Self.pressedSize.width, text: pressedText)
            pressedPaper = FoldTextures.pressedStamp(width: Self.pressedSize.width, paperInk: true, text: pressedText)
        }
        pressed.bounds = CGRect(origin: .zero, size: Self.pressedSize)
        placePressed()
        crack.path = nil
        crackLight.path = nil
    }

    func setEnamel(_ color: UIColor) {
        field.backgroundColor = color.cgColor
    }

    private func position(_ s: FoldPrintStack) {
        guard let layout else { return }
        s.root.position = layout.printCentre
        s.root.setAffineTransform(layout.platenPrintTransform)
    }

    // MARK: Objects

    /// The next object's print: the old one wipes off with the squeegee (§6.3 step 6).
    func wipe() {
        if let old = stack {
            old.beginWipe()
            outgoing.append(old)
            stack = nil
        }
        pressedAge = nil
        pressed.opacity = 0
        crack.path = nil
        crackLight.path = nil
        for b in bolts { b.isHidden = false }
        poppedBolt?.layer.removeFromSuperlayer()
        poppedBolt = nil
    }

    func setStamp(_ stamp: FoldStamp, variant: PressVariant) {
        if stack != nil { wipe() }
        pressedSeed = variant.seed
        let s = FoldPrintStack(stamp: stamp, variant: variant, softDisc: softDisc, rings: ringImage)
        position(s)
        printHolder.addSublayer(s.root)
        stack = s
        placePressed()   // from this print's bounding box
        let box = FoldStampBox(stamp: stamp)
        Task { @MainActor [weak self, weak s] in
            let images = await Task.detached(priority: .userInitiated) { () -> FoldPrintImages in
                FoldPrintImages(ink: FoldStamps.inkImage(box.stamp), mask: FoldStamps.maskImage(box.stamp),
                                shadows: FoldStamps.shadowBlurs(box.stamp.kind).map { FoldStamps.shadowImage(box.stamp, blur: $0) })
            }.value
            guard self != nil, let s else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            s.setImages(ink: images.ink, mask: images.mask, shadows: images.shadows)
            CATransaction.commit()
        }
    }

    func kiss(reduceMotion: Bool) { stack?.kissNow(reduceMotion: reduceMotion) }

    func fracture(index: Int, isFailure: Bool, compression: Double, reduceMotion: Bool, seed: UInt64) -> FoldPrintEffect {
        guard let stack else { return .none }
        let effect = stack.fracture(index: index, isFailure: isFailure, compression: compression, reduceMotion: reduceMotion)
        if effect == .platenBreaks { breakPlate(seed: seed, reduceMotion: reduceMotion) }
        return effect
    }

    func reveal() {
        pressedAge = 0
        placePressed()
    }

    /// The close-style stamp (EXPERIENCE-2 §A6.1): PERFECT for a slow close, SLAMMED for a slam (no reward), PUMPED ×N
    /// for a pumped press, PRESSED otherwise. Same size and pose rules as PRESSED.
    func setPressedText(_ text: String) {
        guard text != pressedText else { return }
        pressedText = text
        guard layout != nil else { return }   // `build` renders it
        pressedRed = FoldTextures.pressedStamp(width: Self.pressedSize.width, text: text)
        pressedPaper = FoldTextures.pressedStamp(width: Self.pressedSize.width, paperInk: true, text: text)
        placePressed()
    }

    /// The PRESSED stamp's pose for one specimen (FOLD-REVIEW-3 N12, FOLD-REVIEW-4 F9, FOLD-REVIEW-5 N9).
    ///
    /// FOLD-REVIEW-5 found duck, glass and can still stamped over their prints. The R4 pose hung the stamp 30 % over
    /// the lower edge of the print's *silhouette* box, but what the reveal shows is the silhouette plus the failure
    /// splat at its spread (up to 1.2×) and its flicked droplets, which reach well past that box; and on the 230 pt
    /// plate the "below the print" slot was clamped back up onto the print. So the pose now comes from what is
    /// actually inked (`printCoverage`): with the seeded tilt (−8° ± 10°), every stamp position on the plate (4 pt in,
    /// 6 pt grid) is scored by how much of the landed stamp (+3 pt) lies on ink, plus a small pull toward the plate's
    /// edges, so it reads as a stamp in a free corner and never floats mid-plate; positions under the NEW BEST ribbon
    /// (`ribbonKeepOut`) are out. The seed then picks among the positions within 0.02 of the best, so it varies by
    /// object (each print leaves different corners free) and by seed. `plate` and the result are canvas offsets from
    /// the print centre, as `coverage` is.
    static func pressedPose(seed: UInt64, coverage: FoldPrintCoverage, plate: CGRect,
                            keepOut: CGRect? = nil) -> (offset: CGPoint, angle: CGFloat) {
        var rng = SplitMix64(seed: seed ^ 0x9E55ED)
        let angle = (-8 + CGFloat.random(in: -10...10, using: &rng)) * .pi / 180
        // The landed stamp's footprint, rotated: its half extents on screen.
        let w = pressedSize.width * pressedScale, h = pressedSize.height * pressedScale
        let c = abs(cos(angle)), s = abs(sin(angle))
        let hx = (w * c + h * s) / 2, hy = (w * s + h * c) / 2
        let inset: CGFloat = 4
        let lo = CGPoint(x: plate.minX + inset + hx, y: plate.minY + inset + hy)
        let hi = CGPoint(x: plate.maxX - inset - hx, y: plate.maxY - inset - hy)
        guard lo.x <= hi.x, lo.y <= hi.y else { return (CGPoint(x: plate.midX, y: plate.midY), angle) }
        let step: CGFloat = 6
        var candidates: [(point: CGPoint, score: CGFloat)] = []
        var best = CGFloat.greatestFiniteMagnitude
        var y = lo.y
        while y <= hi.y + 0.001 {
            var x = lo.x
            while x <= hi.x + 0.001 {
                let centre = CGPoint(x: x, y: y)
                let aabb = CGRect(x: x - hx, y: y - hy, width: 2 * hx, height: 2 * hy)
                if keepOut.map({ !$0.intersects(aabb) }) ?? true {
                    let edge = min(aabb.minX - plate.minX, plate.maxX - aabb.maxX, aabb.minY - plate.minY, plate.maxY - aabb.maxY)
                    let score = pressedInk(at: centre, angle: angle, coverage: coverage)
                        + 0.05 * min(max((edge - inset) / 40, 0), 1)
                    candidates.append((point: centre, score: score))
                    best = min(best, score)
                }
                x += step
            }
            y += step
        }
        let near = candidates.filter { $0.score <= best + 0.02 }
        guard !near.isEmpty else { return (CGPoint(x: (lo.x + hi.x) / 2, y: hi.y), angle) }
        let pick = Int(rng.next() % UInt64(near.count))
        return (near[pick].point, angle)
    }

    /// The fraction of the landed PRESSED stamp (rotated by `angle`, grown by 3 pt) that lies on ink, sampled on a
    /// 13 × 5 grid. `centre` is a canvas offset from the print centre, as `coverage` is.
    static func pressedInk(at centre: CGPoint, angle: CGFloat, coverage: FoldPrintCoverage) -> CGFloat {
        let w = pressedSize.width * pressedScale + 6, h = pressedSize.height * pressedScale + 6
        let ca = cos(angle), sa = sin(angle)
        let columns = 13, rows = 5
        var inked = 0
        for j in 0..<rows {
            let v = (CGFloat(j) / CGFloat(rows - 1) - 0.5) * h
            for i in 0..<columns {
                let u = (CGFloat(i) / CGFloat(columns - 1) - 0.5) * w
                let p = CGPoint(x: centre.x + u * ca - v * sa, y: centre.y + u * sa + v * ca)
                if coverage.isCovered(p) { inked += 1 }
            }
        }
        return CGFloat(inked) / CGFloat(columns * rows)
    }

    /// Where the reveal card's NEW BEST ribbon sits on the plate (RevealCardView: centred at the plate's maxX − 36,
    /// minY + 4), grown to its size and tilt: the stamp keeps out of it. Canvas offsets, as `plate`.
    static func ribbonKeepOut(plate: CGRect) -> CGRect {
        CGRect(x: plate.maxX - 36 - 54, y: plate.minY + 4 - 18, width: 108, height: 40)
    }

    /// What the print has actually inked, as the platen shows it (FOLD-REVIEW-5 N9): the silhouette, plus the
    /// failure splat (its blob, frost or ring and every flicked droplet) at `splatScale` when it has one (0 = not
    /// failed). Rendered once into a 2 pt grid of canvas offsets from the print centre; a cell is inked above 15 %
    /// alpha. Pure CG from the seeded draws, so it matches the platen exactly.
    static func printCoverage(_ stamp: FoldStamp, variant: PressVariant, layout: FoldLayout,
                              splatScale: Double) -> FoldPrintCoverage {
        let transform = layout.platenPrintTransform
        let bounds = FoldPrintCanvas.rect.applying(transform)
        let cell: CGFloat = 2
        let columns = max(1, Int((bounds.width / cell).rounded(.up)))
        let rows = max(1, Int((bounds.height / cell).rounded(.up)))
        guard let ctx = CGContext(data: nil, width: columns, height: rows, bitsPerComponent: 8, bytesPerRow: columns * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return FoldPrintCoverage(bounds: bounds, cell: cell, columns: 0, rows: 0, covered: [])
        }
        // y-down canvas offsets: bounds.minY lands on memory row 0.
        ctx.translateBy(x: 0, y: CGFloat(rows))
        ctx.scaleBy(x: 1 / cell, y: -1 / cell)
        ctx.translateBy(x: -bounds.minX, y: -bounds.minY)
        ctx.concatenate(transform)
        ctx.addPath(stamp.silhouette)
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fillPath()
        if splatScale > 0 {
            ctx.saveGState()
            ctx.scaleBy(x: CGFloat(splatScale), y: CGFloat(splatScale))
            FoldStamps.drawSplat(stamp, variant: variant, into: ctx)
            ctx.restoreGState()
        }
        var covered = [Bool](repeating: false, count: columns * rows)
        if let data = ctx.data {
            let bytes = data.assumingMemoryBound(to: UInt8.self)
            let rowBytes = ctx.bytesPerRow
            for r in 0..<rows {
                for c in 0..<columns where bytes[r * rowBytes + c * 4 + 3] > 38 {
                    covered[r * columns + c] = true
                }
            }
        }
        return FoldPrintCoverage(bounds: bounds, cell: cell, columns: columns, rows: rows, covered: covered)
    }

    /// The print's ink outline (its full-coverage silhouette) as the platen shows it: a canvas-space bounding box,
    /// offset from the print centre.
    static func printBounds(_ stamp: FoldStamp, layout: FoldLayout) -> CGRect {
        stamp.silhouette.boundingBoxOfPath.applying(layout.platenPrintTransform)
    }

    /// The stamp as drawn (`FoldTextures.pressedStamp`), and its size once landed: 85 % (it covered the print's
    /// lower third at 100 %).
    static let pressedSize = CGSize(width: 150, height: 57)
    static let pressedScale: CGFloat = 0.85

    /// Prints whose ink is within 30° of the stamp's red (jelly, the cherry can, the gummy bear) take the stamp in
    /// paper-white ink with a red keyline (FOLD-REVIEW-3 N12, FOLD-REVIEW-4 F14): red-on-magenta disappeared.
    static func pressedOnPaper(_ ink: UIColor) -> Bool {
        var h1: CGFloat = 0, s1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var h2: CGFloat = 0, s2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        guard ink.getHue(&h1, saturation: &s1, brightness: &b1, alpha: &a1),
              Palette.stampRed.getHue(&h2, saturation: &s2, brightness: &b2, alpha: &a2) else { return false }
        guard s1 >= 0.3 else { return false }   // pale or white prints (bubble, glass, egg) keep the red ink
        let d = abs(h1 - h2)
        return min(d, 1 - d) * 360 <= 30
    }

    private func placePressed() {
        guard let layout else { return }
        let centre = layout.printCentre
        let plate = layout.strikePlate(platen: true).offsetBy(dx: -centre.x, dy: -centre.y)
        // What is inked right now (at the reveal: the silhouette and the splat at its spread), FOLD-REVIEW-5 N9.
        let coverage = stack.map {
            Self.printCoverage($0.stamp, variant: $0.variant, layout: layout, splatScale: $0.splatScale)
        } ?? .empty
        let pose = Self.pressedPose(seed: pressedSeed, coverage: coverage, plate: plate,
                                    keepOut: Self.ribbonKeepOut(plate: plate))
        pressed.position = CGPoint(x: centre.x + pose.offset.x, y: centre.y + pose.offset.y)
        pressedAngle = pose.angle
        let paper = stack.map { Self.pressedOnPaper($0.stamp.ink) } ?? false
        pressed.contents = paper ? pressedPaper : pressedRed
    }

    /// The current monoprint (no bezel), for the collection card's diptych.
    func printImage() -> CGImage? { stack?.renderPrint() }

    /// The platen loses (§3.2, the Unsquishable): a chunky cartoon graphite crack across the steel, one bolt pops.
    private func breakPlate(seed: UInt64, reduceMotion: Bool) {
        guard let layout else { return }
        let r = layout.strikePlate(platen: true)
        var rng = SplitMix64(seed: seed ^ 0xC2AC)
        let path = CGMutablePath()
        let horizontal = !layout.isBook
        var p = horizontal ? CGPoint(x: r.minX + 10, y: r.midY + CGFloat.random(in: -20...20, using: &rng))
            : CGPoint(x: r.midX + CGFloat.random(in: -20...20, using: &rng), y: r.minY + 10)
        path.move(to: p)
        let steps = 9
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let zig = CGFloat(i % 2 == 0 ? 1 : -1) * CGFloat.random(in: 8...18, using: &rng)
            p = horizontal ? CGPoint(x: r.minX + 10 + (r.width - 20) * t, y: r.midY + zig)
                : CGPoint(x: r.midX + zig, y: r.minY + 10 + (r.height - 20) * t)
            path.addLine(to: p)
            if i == 4 || i == 7 {
                // Two short branches.
                let branch = horizontal ? CGPoint(x: p.x + 14, y: p.y + zig * 1.6) : CGPoint(x: p.x + zig * 1.6, y: p.y + 14)
                path.addLine(to: branch)
                path.move(to: p)
            }
        }
        crack.path = path
        var shift = CGAffineTransform(translationX: -1.2, y: -1.2)
        crackLight.path = path.copy(using: &shift)
        if let bolt = bolts.first(where: { !$0.isHidden }) {
            bolt.isHidden = true
            let flying = CALayer()
            flying.contents = bolt.contents
            flying.bounds = bolt.bounds
            flying.position = bolt.position
            layer.insertSublayer(flying, below: dim)
            poppedBolt = (flying, reduceMotion ? 10 : 0, bolt.position)
        }
    }

    // MARK: Per frame

    func update(_ f: FoldFrame) {
        guard let layout else { return }
        // Sheen (§3.3): slides far edge (180°) → crease (60°), peaking near 120°; the invitation sweep overrides it.
        let plateRect = layout.strikePlate(platen: true)
        let position = f.sweep ?? FoldCurve.sheenPosition(angle: f.angle)
        let intensity = f.sweep != nil ? 1 : FoldCurve.sheenIntensity(angle: f.angle)
        let band: CGFloat = 44
        if layout.isBook {
            // Platen = left page: far edge = left (minX), crease = right.
            let x = CGFloat(position) * plateRect.width
            sheen.frame = CGRect(x: x - band / 2, y: 0, width: band, height: plateRect.height)
        } else {
            let y = CGFloat(position) * plateRect.height
            sheen.frame = CGRect(x: 0, y: y - band / 2, width: plateRect.width, height: band)
        }
        sheen.opacity = Float(0.6 * intensity)

        // Guide pins: a brighter rim from 150° to contact (§3.5), and a glint as the invitation sweep passes.
        let approachRim = clamp((150 - f.angle) / 18, 0, 1)
        let glint = f.sweep.map { exp(-pow(($0 - 1) / 0.12, 2)) } ?? 0
        for rim in pinRims { rim.opacity = Float(min(1, max(approachRim * 1.3, glint))) }
        let grip = f.inviting ? (f.sweep.map { sin(.pi * clamp($0, 0, 1)) } ?? 0) : 0
        for pad in gripPads { pad.opacity = Float(0.35 * grip) }

        stack?.update(f)
        for s in outgoing { s.update(f) }
        outgoing.removeAll { s in
            if s.isWiped { s.root.removeFromSuperlayer() }
            return s.isWiped
        }

        // PRESSED stamp thunks onto the print at the reveal (§6.3 step 4).
        if let age = pressedAge {
            let t = age - 0.35
            pressedAge = age + f.dt
            if t > 0 {
                let k = f.reduceMotion ? 1 : min(1, t / 0.12)
                let s = CGFloat(1.5 - 0.5 * k) * Self.pressedScale
                pressed.opacity = Float(0.92 * k)
                pressed.setAffineTransform(CGAffineTransform(rotationAngle: pressedAngle).scaledBy(x: s, y: s))
            }
        }

        // The popped bolt bounces off toward the far edge and falls away.
        if var bolt = poppedBolt {
            bolt.age += f.dt
            poppedBolt = bolt
            let t = bolt.age
            if t < 0.9 {
                let away: CGPoint = layout.isBook ? CGPoint(x: -1, y: 0) : CGPoint(x: 0, y: -1)
                let side = CGPoint(x: away.y, y: away.x)
                let travel = CGFloat(180 * t), hop = CGFloat(60 * t)
                bolt.layer.position = CGPoint(x: bolt.start.x + away.x * travel + side.x * hop,
                                              y: bolt.start.y + away.y * travel + side.y * hop)
                bolt.layer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(t * 14)).scaledBy(x: CGFloat(1 + 0.6 * t), y: CGFloat(1 + 0.6 * t)))
                bolt.layer.opacity = Float(1 - t / 0.9)
            } else {
                bolt.layer.opacity = 0
            }
        }

        // Tabletop dimming below 75° (§3.3): the plate has entered the wedge's shade.
        dim.opacity = f.tabletop ? Float(1 - FoldCurve.platenDimming(angle: f.angle)) : 0
    }
}

/// Which 2 pt cells of a print are inked, in canvas offsets from the print centre (`FoldPlaten.printCoverage`).
struct FoldPrintCoverage: Sendable {
    let bounds: CGRect
    let cell: CGFloat
    let columns: Int
    let rows: Int
    let covered: [Bool]

    static let empty = FoldPrintCoverage(bounds: .zero, cell: 2, columns: 0, rows: 0, covered: [])

    func isCovered(_ p: CGPoint) -> Bool {
        guard columns > 0, rows > 0, p.x.isFinite, p.y.isFinite else { return false }
        let c = Int(((p.x - bounds.minX) / cell).rounded(.down))
        let r = Int(((p.y - bounds.minY) / cell).rounded(.down))
        guard c >= 0, r >= 0, c < columns, r < rows else { return false }
        return covered[r * columns + c]
    }

    /// The inked fraction of `rect` (sampled at the cell size).
    func fraction(in rect: CGRect) -> CGFloat {
        guard rect.width > 0, rect.height > 0 else { return 0 }
        var inked = 0, total = 0
        var y = rect.minY + cell / 2
        while y < rect.maxY {
            var x = rect.minX + cell / 2
            while x < rect.maxX {
                total += 1
                if isCovered(CGPoint(x: x, y: y)) { inked += 1 }
                x += cell
            }
            y += cell
        }
        return total > 0 ? CGFloat(inked) / CGFloat(total) : 0
    }
}

/// Off-main image rendering hand-offs (CG types are immutable once made).
struct FoldStampBox: @unchecked Sendable {
    let stamp: FoldStamp
}

struct FoldPrintImages: @unchecked Sendable {
    let ink: CGImage?
    let mask: CGImage?
    let shadows: [CGImage?]
}
