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
    private let wipeMask = CAGradientLayer()
    private let squeegee = CALayer()
    private var decalContext: CGContext?
    private var splatScale: Double = 0
    private var kissLevel: Double = 0
    private var pulse: Double = 0
    private var ripples: [(centre: CGPoint, radius: CGFloat, age: Double, layer: CAShapeLayer)] = []
    private(set) var wipeProgress: Double?
    private var contactAge: Double = 0
    private var variant: PressVariant

    init(stamp: FoldStamp, variant: PressVariant, softDisc: CGImage?, rings ringImage: CGImage?) {
        self.stamp = stamp
        self.variant = variant
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
            FoldStamps.ring(ctx, .zero, stamp.featureRadius, 2.4, Palette.lime.withAlphaComponent(0.85))
            decal.contents = ctx.makeImage()
        }
    }

    func fracture(index: Int, isFailure: Bool, compression: Double, reduceMotion: Bool) -> FoldPrintEffect {
        var effect = FoldPrintEffect.none
        if let ctx = decalContext {
            effect = FoldStamps.drawFracture(index: index, isFailure: isFailure, stamp: stamp, into: ctx)
            decal.contents = ctx.makeImage()
        }
        if isFailure {
            splat.contents = FoldStamps.splatImage(stamp, variant: variant)
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
        let weights: [Double]
        if shadow.blur <= 16 {
            let t = (shadow.blur - 4) / 12
            weights = [1 - t, t, 0]
        } else {
            let t = (shadow.blur - 16) / 24
            weights = [0, 1 - t, t]
        }
        let presence = f.objectPresent ? 1.0 : 0
        let under = f.contacted ? 0.55 : 1
        for (layer, w) in zip(shadows, weights) {
            layer.opacity = Float(shadow.alpha * w * presence * under)
            layer.setAffineTransform(CGAffineTransform(scaleX: CGFloat(shadow.scale), y: CGFloat(shadow.scale)))
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
        growth.bounds = CGRect(x: 0, y: 0, width: 2 * rx * 1.08, height: 2 * ry * 1.08)
        growth.position = stamp.apex
        growth.setAffineTransform(CGAffineTransform(rotationAngle: stamp.growthAngle))

        // Newton's rings just outside the contact edge (alpha 0.06 + 0.10·c); the ball's ring is the bright one.
        if f.contacted {
            pulse *= pow(0.5, f.dt / 0.12)
            let ball = stamp.contact == .fixedRing
            let alpha = ball ? 0.55 + 0.45 * min(1, f.printCompression * 2) + 0.4 * pulse
                : (fraction < 1 ? 0.06 + 0.10 * f.printCompression : 0.04)
            rings.opacity = Float(min(alpha * (stamp.contact == .uniform ? 0.5 : 1), 1))
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
            let target = 0.85 + 0.35 * spread
            splatScale += (target - splatScale) * (1 - pow(0.5, f.dt / 0.045))
            splat.setAffineTransform(CGAffineTransform(scaleX: CGFloat(splatScale), y: CGFloat(splatScale)))
        }

        // Kiss highlight: one bright wet dot, gone in a few frames.
        kiss.opacity = Float(kissLevel)
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
    private let crack = CAShapeLayer()
    private let crackLight = CAShapeLayer()
    private let printHolder = CALayer()
    private let pressed = CALayer()
    private let dim = CALayer()
    private var layout: FoldLayout?
    private(set) var stack: FoldPrintStack?
    private var outgoing: [FoldPrintStack] = []
    private var pressedAge: Double?
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
        sheen.colors = [UIColor(white: 1, alpha: 0).cgColor, UIColor(white: 1, alpha: 1).cgColor, UIColor(white: 1, alpha: 0).cgColor]
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
        let pinImage = FoldTextures.pin(diameter: CGFloat(FoldMetrics.pinDiameter), ring: false)
        for p in layout.guidePins(platen: true) {
            let pin = CALayer()
            pin.contents = pinImage
            pin.bounds = CGRect(x: 0, y: 0, width: FoldMetrics.pinDiameter + 4, height: FoldMetrics.pinDiameter + 4)
            pin.position = p
            layer.insertSublayer(pin, above: sheenHolder)
            pins.append(pin)
            let rim = CALayer()
            rim.bounds = CGRect(x: 0, y: 0, width: FoldMetrics.pinDiameter + 1, height: FoldMetrics.pinDiameter + 1)
            rim.cornerRadius = CGFloat(FoldMetrics.pinDiameter + 1) / 2
            rim.borderColor = UIColor(white: 1, alpha: 0.95).cgColor
            rim.borderWidth = 1
            rim.position = p
            rim.opacity = 0
            layer.insertSublayer(rim, above: pin)
            pinRims.append(rim)
        }
        printHolder.frame = half
        printHolder.bounds = half
        for s in [stack].compactMap({ $0 }) + outgoing { position(s) }
        pressed.contents = FoldTextures.pressedStamp()
        pressed.bounds = CGRect(x: 0, y: 0, width: 150, height: 57)
        pressed.position = CGPoint(x: layout.printCentre.x + (layout.isBook ? 0 : 60), y: layout.printCentre.y + (layout.isBook ? 70 : 24))
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
        let s = FoldPrintStack(stamp: stamp, variant: variant, softDisc: softDisc, rings: ringImage)
        position(s)
        printHolder.addSublayer(s.root)
        stack = s
        let box = FoldStampBox(stamp: stamp)
        Task { @MainActor [weak self, weak s] in
            let images = await Task.detached(priority: .userInitiated) { () -> FoldPrintImages in
                FoldPrintImages(ink: FoldStamps.inkImage(box.stamp), mask: FoldStamps.maskImage(box.stamp),
                                shadows: [4, 16, 40].map { FoldStamps.shadowImage(box.stamp, blur: $0) })
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
    }

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
        let band: CGFloat = 70
        if layout.isBook {
            // Platen = left page: far edge = left (minX), crease = right.
            let x = CGFloat(position) * plateRect.width
            sheen.frame = CGRect(x: x - band / 2, y: 0, width: band, height: plateRect.height)
        } else {
            let y = CGFloat(position) * plateRect.height
            sheen.frame = CGRect(x: 0, y: y - band / 2, width: plateRect.width, height: band)
        }
        sheen.opacity = Float(0.22 * intensity)

        // Guide pins: a brighter rim from 150° to contact (§3.5), and a glint as the invitation sweep passes.
        let approachRim = clamp((150 - f.angle) / 18, 0, 1)
        let glint = f.sweep.map { exp(-pow(($0 - 1) / 0.12, 2)) } ?? 0
        for rim in pinRims { rim.opacity = Float(max(approachRim, glint)) }

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
                let s = 1.5 - 0.5 * k
                pressed.opacity = Float(0.92 * k)
                pressed.setAffineTransform(CGAffineTransform(rotationAngle: -0.14).scaledBy(x: s, y: s))
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

/// Off-main image rendering hand-offs (CG types are immutable once made).
struct FoldStampBox: @unchecked Sendable {
    let stamp: FoldStamp
}

struct FoldPrintImages: @unchecked Sendable {
    let ink: CGImage?
    let mask: CGImage?
    let shadows: [CGImage?]
}
