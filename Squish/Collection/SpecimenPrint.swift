import CoreGraphics
import Foundation
import UIKit

/// The platen's monoprint of a finished Fold press, rebuilt from the specimen record alone: kind, seed, how far it was
/// pressed and how many fractures fired (FOLD-REVIEW-8 N2).
///
/// A print is deterministic from those (FoldStamps.swift: "everything is deterministic from the press seed and pure
/// CG"). So this composes the same public FoldStamps / FoldTextures draws that `FoldPrintStack` makes during a press,
/// in the order it makes them, and lays them out as `FoldPrintStack.renderPrint` does, at the state the platen holds at
/// the reveal:
/// - the ink at its final growth (`FoldPrintStack.update`),
/// - the failure splat at its spread,
/// - the can's rim ring, and every fired fracture's stamp in firing order.
///
/// It has two uses:
/// - **Demo seeding (DEBUG):** each seeded specimen gets the thumbnail a real press would have stored.
/// - **The pressed-tile fallback (`PressedTile`):** a real specimen whose thumbnail is missing still shows its print,
///   never the intact object.
///
/// Pure CoreGraphics, no actor isolation: safe off the main actor.
enum SpecimenPrint {
    // MARK: Press facts (from Core, as the engine derives them)

    /// The rendered rest height (scene metres) each object reports to the fold stage (`PressScene.foldObject`), which
    /// sets its `foldScale` (FoldPressController.updateObjectScale). Taken from the nonisolated Scene/Objects
    /// constants where they exist. The view classes' own constants (`DuckView.heroScale`, `GummyBearView.heroScale`,
    /// `GlassBottleView.heroScale`, `CrayonView.radius`) are main-actor isolated, so they are mirrored here;
    /// CollectionTests checks they stay in sync.
    static func restHeight(_ kind: ObjectKind, variant: PressVariant) -> Double {
        switch kind {
        case .bubbleWrap:
            let mega = variant.surprise == .megaBubble
            return Double(BubbleWrapGrid.film + BubbleWrapGrid.domeHeight * (mega ? BubbleWrapGrid.megaHeightScale : 1))
        case .rubberDuck: return 0.085 * 1.25        // DuckView: 0.085 × heroScale
        case .jelly: return 0.0765                   // JellyView
        case .crayon: return 2 * 0.016               // CrayonView: 2 × radius (0.011 × kR)
        case .egg: return 0.080                      // EggView
        case .cakeSlice: return Double(CakeSquash.restHeight)
        case .sodaCan: return Double(0.150 * ObjectMeshes.canY)
        case .gummyBear: return 0.107 * 1.2          // GummyBearView: 0.107 × heroScale
        case .glassBottle: return 0.060 * 0.76       // GlassBottleView: 0.060 × heroScale
        case .unsquishable: return Double(2 * ObjectMeshes.ballRadius)
        }
    }

    /// The fold scale the press draws this object (and so its print) at (§2.3).
    static func foldScale(_ kind: ObjectKind, variant: PressVariant) -> Double {
        FoldMetrics.foldScale(restHeight: restHeight(kind, variant: variant))
    }

    /// How many fractures a press to `maxCompression` fires: the engine's jittered thresholds it reached.
    static func fractureCount(_ kind: ObjectKind, seed: UInt64, maxCompression: Double) -> Int {
        kind.profile.jitteredFractures(seed: seed).filter { maxCompression >= $0 }.count
    }

    /// The hinge angle a real Fold press records for this object's failure, for a press opened flat and closed
    /// through it. The engine arms at `min(θ, armAngleMax)` (168° from flat), floats contact from there
    /// (`PressConfig.armed(at:)`) and records θ when the compression first reaches the seed's jittered failure
    /// threshold (PressEngine.advanceCompression). Here that threshold goes back through `PressMapping` to an angle.
    /// Nil for objects with no single failure (bubble wrap).
    static func failureAngle(_ kind: ObjectKind, seed: UInt64, config: PressConfig = .standard) -> Double? {
        let profile = kind.profile
        let thresholds = profile.jitteredFractures(seed: seed)
        guard let index = profile.failureIndex, index < thresholds.count else { return nil }
        let start = config.armAngleMax
        let armed = config.armed(at: start, hinge: true)   // a real fold (the provisional fold mapping)
        let depth = armed.contactT + thresholds[index] * (1 - armed.contactT)
        return PressMapping.angle(forDepth: depth, start: start, config: armed)
    }

    /// The first seed from `start` whose variant is plain: not golden, no surprise.
    static func plainSeed(for kind: ObjectKind, from start: UInt64 = 1) -> UInt64 {
        var seed = start
        for _ in 0..<10_000 {
            let variant = PressVariant(kind: kind, seed: seed)
            if !variant.isGolden && variant.surprise == nil { return seed }
            seed += 1
        }
        return start
    }

    // MARK: The print

    /// The ink layer's final state: its opacity and the growth-mask radii (`FoldPrintStack.update` at the reveal,
    /// contact long past and the tell over).
    static func inkState(_ stamp: FoldStamp, compression c: Double) -> (opacity: Double, radii: CGSize) {
        let r = stamp.growthRadii
        let fraction = FoldCurve.printFraction(compression: c)
        var rx = Double(r.width), ry = Double(r.height)
        let opacity: Double
        switch stamp.contact {
        case .point:
            rx = max(rx * fraction, 7)
            ry = max(ry * fraction, 7)
            opacity = 0.6 + 0.4 * min(1, fraction * 1.3)
        case .line:
            rx *= max(fraction, 0.85)
            ry = max(ry * fraction, 2.5)
            opacity = 0.6 + 0.4 * min(1, fraction * 1.3)
        case .uniform:
            opacity = 0.35 + 0.65 * min(1, c * 3)
        case .fixedRing:
            rx = Double(stamp.featureRadius) + 2
            ry = rx
            opacity = 0.7 + 0.3 * min(1, c * 2)
        }
        return (opacity, CGSize(width: rx * 1.08, height: ry * 1.08))
    }

    /// The failure splat's settled scale: it spreads with the compression after the failure (`FoldPrintStack.update`).
    static func splatScale(_ kind: ObjectKind, failureCompression: Double, compression c: Double) -> CGFloat {
        if kind == .glassBottle { return 1 }
        let spread = clamp((c - failureCompression) / max(1 - failureCompression, 0.05), 0, 1)
        return CGFloat(0.85 + 0.35 * spread)
    }

    /// The monoprint as it lies on the platen at the reveal, exactly framed as `FoldPlaten.printImage()`: on the steel
    /// strike plate, mirrored across the crease, cropped to the plate + 40 pt (`FoldPrintCanvas.rect`). Nil if the
    /// object was never touched.
    static func printImage(kind: ObjectKind, variant: PressVariant, maxCompression: Double, fractureCount: Int,
                           scale: CGFloat = 2) -> CGImage? {
        let c = clamp(maxCompression, 0, 1)
        let stamp = FoldStamps.stamp(for: kind, variant: variant, foldScale: foldScale(kind, variant: variant))
        let profile = kind.profile
        let thresholds = profile.jitteredFractures(seed: variant.seed)
        let fired = min(max(fractureCount, 0), thresholds.count)
        let failureIndex = profile.failureIndex.flatMap { $0 < fired ? $0 : nil }
        let touched = c > 0 || fired > 0
        guard touched else { return nil }

        let canvas = FoldPrintCanvas.rect
        let inkNow = Self.inkState(stamp, compression: c)
        let ink = inkNow.opacity > 0.01 ? FoldStamps.inkImage(stamp, scale: scale) : nil
        let splat = failureIndex != nil ? FoldStamps.splatImage(stamp, variant: variant, scale: scale) : nil
        let spread = failureIndex.map { splatScale(kind, failureCompression: thresholds[$0], compression: c) } ?? 0
        // The accumulating decal: the can's rim kiss first (`kissNow`), then each fracture in firing order.
        let decal: CGImage? = (kind == .sodaCan || fired > 0)
            ? FoldStamps.image(rect: canvas, scale: scale) { ctx in
                if kind == .sodaCan {
                    FoldStamps.ring(ctx, .zero, stamp.featureRadius, 2.0, stamp.inkEdge.withAlphaComponent(0.7))
                }
                for index in 0..<fired {
                    _ = FoldStamps.drawFracture(index: index, isFailure: index == failureIndex, stamp: stamp, into: ctx,
                                                compression: thresholds[index])
                }
            }
            : nil
        let plateSize = CGSize(width: FoldMetrics.plateLateral, height: FoldMetrics.plateDepth)
        let plate = scale == 2 ? plate2x
            : FoldTextures.strikePlate(size: plateSize, radius: CGFloat(FoldMetrics.plateRadius), streaksAlongX: true,
                                       scale: scale)

        // From here on, `FoldPrintStack.renderPrint`, step for step.
        return FoldStamps.image(rect: canvas, scale: scale) { ctx in
            /// CG draws images bottom-up; the context is y-down, so flip around the rect for each image.
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
            draw(plate, in: CGRect(x: -plateSize.width / 2, y: -plateSize.height / 2,
                                   width: plateSize.width, height: plateSize.height))
            // The platen's mirror (§3.4): print space y → −y.
            ctx.scaleBy(x: 1, y: -1)
            if inkNow.opacity > 0.01 {
                ctx.saveGState()
                ctx.translateBy(x: stamp.apex.x, y: stamp.apex.y)
                ctx.rotate(by: stamp.growthAngle)
                ctx.addEllipse(in: CGRect(x: -inkNow.radii.width, y: -inkNow.radii.height,
                                          width: 2 * inkNow.radii.width, height: 2 * inkNow.radii.height))
                ctx.rotate(by: -stamp.growthAngle)
                ctx.translateBy(x: -stamp.apex.x, y: -stamp.apex.y)
                ctx.clip()
                ctx.setAlpha(CGFloat(inkNow.opacity))
                ctx.setBlendMode(stamp.kind == .glassBottle ? .normal : .multiply)
                draw(ink, in: canvas)
                ctx.restoreGState()
            }
            if splat != nil {
                ctx.saveGState()
                ctx.scaleBy(x: spread, y: spread)
                draw(splat, in: canvas)
                ctx.restoreGState()
            }
            draw(decal, in: canvas)
        }
    }

    /// The bare strike plate at the platen's scale, drawn once.
    private static let plate2x = FoldTextures.strikePlate(
        size: CGSize(width: FoldMetrics.plateLateral, height: FoldMetrics.plateDepth),
        radius: CGFloat(FoldMetrics.plateRadius), streaksAlongX: true)

    // MARK: The card thumbnail

    /// The collection card a Fold press stores when it has only the print: `FoldPressController.specimenDiptych` with
    /// no specimen shot (a square of paper, 4 % margin, the print fitted in it), opaque, scale 1.
    static func cardImage(print: CGImage, side: CGFloat = 720) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: side, height: side)
        let margin = side * 0.04
        let printImage = UIImage(cgImage: print)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            Palette.paper.setFill()
            context.cgContext.fill(CGRect(origin: .zero, size: size))
            let box = CGRect(x: margin, y: margin, width: side - 2 * margin, height: side - 2 * margin)
            let w = max(printImage.size.width, 1), h = max(printImage.size.height, 1)
            let s = min(box.width / w, box.height / h)
            printImage.draw(in: CGRect(x: box.midX - w * s / 2, y: box.midY - h * s / 2, width: w * s, height: h * s))
        }
    }

    /// A specimen's print card (`cardImage` of `printImage`), cached by everything it depends on.
    static func card(for specimen: SpecimenRecord, side: CGFloat = 720) -> UIImage? {
        let key = cacheKey(specimen, side: side)
        if let cached = cache.object(forKey: key) { return cached }
        guard let print = printImage(kind: specimen.kind, variant: specimen.variant,
                                     maxCompression: specimen.maxCompression,
                                     fractureCount: specimen.fractureCount) else { return nil }
        let image = cardImage(print: print, side: side)
        cache.setObject(image, forKey: key)
        return image
    }

    /// The card if it has already been rendered (cheap; for a view's first frame).
    static func cachedCard(for specimen: SpecimenRecord, side: CGFloat = 720) -> UIImage? {
        cache.object(forKey: cacheKey(specimen, side: side))
    }

    /// NSCache is thread-safe. A 720² card is ~2 MB decoded, and cards are only rebuilt for missing thumbnails.
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 16
        return cache
    }()

    private static func cacheKey(_ specimen: SpecimenRecord, side: CGFloat) -> NSString {
        let c = Int((specimen.maxCompression * 1000).rounded())
        let v = specimen.variant
        return NSString(string: "\(specimen.kind.rawValue)-\(v.seed)-\(v.isGolden)-\(specimen.fractureCount)-\(c)-\(Int(side))")
    }
}
