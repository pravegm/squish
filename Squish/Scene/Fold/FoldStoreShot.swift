import CoreImage
import CoreImage.CIFilterBuiltins
import RealityKit
import simd
import UIKit

/// The store shot (FOLD-REVIEW-3 N1, FOLD-REVIEW-4 #1/#2, FOLD-PRESS §9.6 "eye-view composite"): the live Fold Press
/// stage mapped onto a folded, Duo-shaped device and seen from a 3/4 eye, because raw inner-display frames are
/// anamorphic and read as two flat trays.
///
///     capture(scene:fold:)              live stage → platen page, crease band, anvil page (canvas orientation, @screen scale)
///     render(_:options:)                → one device, framed for the App Store (Duo inner 2007 × 2853 by default)
///     renderPair(before:after:options:) → the before/after frame: a small open device (112°) above a large one at the squish
///     renderGrid(_:options:)            → the variety frame: several objects' heroes on one sweep (FOLD-REVIEW-5 §5 A6)
///
/// FOLD-REVIEW-5 #1 (make the squeeze read): the screens get device lighting (the lid's shadow from an overhead
/// softbox and wedge occlusion at the crease, `drawWedgeShading`); the squish frames are seen from a 32° turn so the
/// device's end shows the V; the pair labels quote each device's crown readout (`Halves.readout`) next to a
/// side-profile glyph of the modelled angle, so no label can contradict the number on the screen.
///
/// FOLD-REVIEW-6 #1 (frame 1 must read as a phone closing on a duck): the hero takes its own camera (the duck at a
/// 22° elevation and 50° turn, glass at −28°), the key light leans toward the viewer so the lid's shadow lands on the
/// object (`Options.keyTiltDegrees`), the readout label and V glyph sit on the hero too (`Options.angleMark`), and the
/// hero hangs from the caption band (`Anchor.top`, fill 0.66 / bleed 0.10) so no dead band opens under it. The
/// reveal (FOLD-REVIEW-7 N4: ~151°, wide and short) is width-fitted with no bleed, centred, from a 42° eye, so the
/// whole device including the hinge spine is in frame (PressDirector.writeStoreShot).
/// Captions break by `CaptionWrap` (balanced lines, no orphans).
///
/// The model: the inner display is one panel bent round a thin hinge cylinder (the 40 pt crease band becomes the bend),
/// each page a rounded slab with a black glass bezel, on a warm studio sweep with a cast and a contact shadow.
///
/// Pose (FOLD-REVIEW-4 F1): store shots model the device in **tabletop / laptop pose** whatever the layout, the anvil
/// page on the table and the platen page as the lid, because an anamorphic object only reads as standing when its page
/// is the floor. A tabletop capture (portrait inner display, horizontal fold) is correct in every respect. A book capture
/// (landscape, vertical fold) laid on the table is the page turned 90° clockwise: the anvil's 3D content was rendered
/// for the book eye, which in the anvil frame sits above the page's top edge (azimuth ≈ +17° at 62°, +39° at 112°,
/// toward the viewer's right), so the 3/4 eye is kept on that direction and the object still stands, but the book
/// chrome (crown readout, gauge numerals, nameplate, console) reads rotated 90° clockwise. No rotation of the halves
/// fixes that: both pages are hinged along their long edge and the text runs along it. So book content is a fallback
/// (logged `content=book`); the real hero needs the portrait pass in ci/duo-screenshots.sh. `Model.asLaid` keeps the
/// old book stand (pages upright like an open book) for the §12 E-check composites.
///
/// Geometry is in millimetres in the anvil frame of FoldGeometry.swift (tabletop) or a book frame with the wedge
/// bisector toward the viewer (standing book). Rendering is 2D and deterministic: each screen is drawn flat (content,
/// bezel, rounded free corners, glass sheen), then warped onto its 4 projected corners with `CIPerspectiveTransform`
/// (a plane under a pinhole camera is exactly a homography); the bend is 10 warped strips; bodies are lambert-shaded
/// polygons drawn back to front. `layer.render(in:)` is never used for anything with a 3D transform.
@MainActor
enum FoldStoreShot {
    /// iPhone Duo inner display (docs/appstore/screenshots.md §A, the hero set) and its landscape option.
    nonisolated static let duoInner = CGSize(width: 2007, height: 2853)
    nonisolated static let duoInnerLandscape = CGSize(width: 2853, height: 2007)
    /// iPhone Duo outer display (cover frames).
    nonisolated static let duoOuter = CGSize(width: 1398, height: 2034)
    /// App Store 6.9" portrait (1320 × 2868) and landscape. A folded device never goes in the 6.9" set (Guideline 2.3,
    /// FOLD-REVIEW-4 §3.3): these are for non-Duo CI runs and comparison only.
    nonisolated static let portrait = CGSize(width: 1320, height: 2868)
    nonisolated static let landscape = CGSize(width: 2868, height: 1320)

    enum Eye: String, Sendable {
        /// The marketing view: the content's design eye turned about the vertical (see `Options.azimuthDegrees`).
        case threeQuarter
        /// Exactly the design eye the anvil was rendered for (tabletop 40°/380 mm, book bisector): for CI E1/E2 checks.
        case design
    }

    enum Model: String, Sendable {
        /// Laptop pose whatever the layout: anvil page on the table, platen page as the lid.
        case tabletop
        /// The layout's own pose: tabletop layouts as a laptop, book layouts standing on their edge (E-check artefacts).
        case asLaid
    }

    enum Fit: Equatable, Sendable {
        /// The whole device inside the hero box.
        case contain
        /// The device's projected width fills the box; it may grow up to `bleed` (fraction) wider to reach
        /// `Options.targetFill`, never taller than the box.
        case width(bleed: Double)
    }

    enum Anchor: Equatable, Sendable {
        case centre
        /// The device's lowest projected point sits this fraction of the box height above the box bottom.
        case bottom(Double)
        /// The device's highest projected point sits this fraction of the box height below the box top
        /// (FOLD-REVIEW-6 N12: the hero and reveal hang from the caption band, so no dead band opens under it).
        case top(Double)
    }

    enum Backdrop: String, Sendable {
        /// Warm studio sweep (#EDE5D8 → #F3EEE6 → #F1E9DC), matching the caption ground of screenshots.md.
        case studio
        /// A cooler sweep (#E9E6E1 → #D9D5CE) that separates the cream enamel from the backdrop (FOLD-REVIEW-4 §3.3 B).
        case duoSweep
    }

    /// The failure splat escaping the fold (FOLD-REVIEW-4 F3): droplets on the anvil field just outside the strike
    /// plate, seeded from the platen print's splat seed, in the print's ink. A 2D overlay on the anvil page of the store
    /// shot only, and off by default (`Options.escapedSplat` nil; the demo key is `storeshotsplat=overlay`): FoldAnvil
    /// now sprays the real droplets on the device, so they are already in the captured anvil half. Kept for
    /// comparison and for captures made before the live spray.
    struct EscapedSplat {
        var stamp: FoldStamp
        var count = 10

        /// Only objects whose platen splat throws droplets (FoldStamps.splatImage): the duck, jelly and the can.
        static func supports(_ kind: ObjectKind) -> Bool {
            kind == .rubberDuck || kind == .jelly || kind == .sodaCan
        }
    }

    struct Options {
        var size = CGSize(width: 2007, height: 2853)
        /// Fold angle of the device model (180 = flat). The hero is the failure freeze (~62°); CI passes the captured
        /// hinge angle.
        var hingeAngle: Double = 62
        var eye: Eye = .threeQuarter
        var model: Model = .tabletop
        /// Turn of the 3/4 eye about the vertical through the device, degrees (+ = toward world +x), relative to the
        /// content's design eye. Nil = 14° for tabletop content (FOLD-REVIEW-4 §3.3 B: ≤ 15° keeps the anamorphic
        /// object upright), 0° for book content on the tabletop model (its design eye is already +17–39° round),
        /// −22° for a standing book. The squish frames (hero, the pair's large device, the grid) pass 32°
        /// (FOLD-REVIEW-5 §3 d): there the object is flat, so the anamorphic lean doesn't show, and the device's +x end
        /// shows the V of the fold in profile. The pair's small device (object still standing) uses 24°.
        var azimuthDegrees: Double?
        /// Elevation of the 3/4 eye above the anvil page (degrees, from the footprint centre). Nil = 34° for tabletop
        /// content (design 40°), the book design eye clamped to 34–60° for book content on the tabletop model, and the
        /// design eye's own for a standing book. The duck hero passes 22° (FOLD-REVIEW-6 #1): with its 50° turn the
        /// device's end then shows the wedge at ~96° on screen instead of ~133°, so the lid reads as closing on the
        /// duck rather than as a laptop lid (scratchpad r7tools/framing2.mjs).
        var elevationDegrees: Double?
        var eyeModel: FoldEyeModel = .standard
        /// FOLD-REVIEW-6 N12: bleed 0.05 → 0.10, fill 0.58 → 0.66. The width fit still limits it: ~62 % at the
        /// 22°/50° hero, ~66 % at 34°.
        var fit: Fit = .width(bleed: 0.10)
        /// Wanted device height as a fraction of the frame height; only ever grows the width fit by up to its bleed.
        var targetFill: Double? = 0.66
        /// Largest device height as a fraction of the frame height, for the width fit (FOLD-REVIEW-5 #1 capped it at
        /// 0.60; R6 N12 wants 0.66, so the cap now sits above the target). Nil = no cap.
        var maxFill: Double? = 0.70
        /// Device lighting on the screens (FOLD-REVIEW-5 §3 b): the lid's cast shadow from the studio key and the
        /// wedge occlusion near the crease on the anvil page, a fainter wedge on the lid. Tabletop model only; off for
        /// the E-check composites.
        var lidShading = true
        /// Tilt of the studio key toward the viewer, degrees from straight down (FOLD-REVIEW-6 #1 c). 0 = overhead
        /// softbox: a 64° lid's shadow reaches ~31 mm, short of the duck (footprint centre 36.7 mm from the crease).
        /// The heroes pass 18°: ~55 mm, so the duck's back half is in full shadow and its front in the penumbra.
        var keyTiltDegrees: Double = 0
        /// A readout label ("AT 67°") with the side-profile V glyph at the modelled angle, drawn on the sweep above
        /// the lid's lower free corner (FOLD-REVIEW-6 #1 b: the pair's marks on the hero). Nil = none.
        var angleMark: String?
        /// The box the device is fitted into, in unit coordinates of the frame. Nil = (0.04, 0.21, 0.92, 0.76) portrait
        /// (the top 21 % is the caption band), (0.06, 0.22, 0.88, 0.75) landscape with a caption, (0.10, 0.07, 0.80,
        /// 0.88) landscape without.
        var heroBox: CGRect?
        var anchor: Anchor = .bottom(0.03)
        /// Headline in the top 21 % (SF Pro Rounded Heavy, graphite, the one `*word*` in hydraulic yellow), as in
        /// docs/appstore/screenshots.md. Nil = no caption band drawn.
        var caption: String?
        /// Optional small second line (SF Mono, 40 % of the headline size).
        var subcaption: String?
        /// A faint diagonal reflection on both screens. Off for measurement shots.
        var glassSheen = true
        var backdrop: Backdrop = .studio
        var escapedSplat: EscapedSplat?
    }

    /// The before/after frame (FOLD-REVIEW-4 §3.3 C, frame 2): `before` small at the top left, `after` large at the
    /// bottom right, a hand-drawn arrow and the two angles between them. Per-device `size`, `heroBox`, `fit`,
    /// `anchor` and captions are ignored; the frame's own come from here.
    struct PairOptions {
        var size = CGSize(width: 2007, height: 2853)
        var before = Options()
        var after = Options()
        var caption: String?
        var subcaption: String?
        var angleLabels = true
        var backdrop: Backdrop = .studio
    }

    /// The live stage split at the crease, each image in canvas orientation covering exactly
    /// `layout.platenHalf`, `layout.creaseRect` and `layout.anvilHalf`.
    struct Halves {
        var platen: CGImage
        var crease: CGImage?
        var anvil: CGImage
        var layout: FoldLayout
        /// How the anvil pixels were obtained ("drawHierarchy" or "arView.snapshot"), for CI logs.
        var source: String
        /// The hinge angle the halves were captured at (book content's design eye depends on it). Nil = the model's.
        var hingeAngle: Double? = nil
        /// What the crown readout on the platen showed at capture (FOLD-REVIEW-5 §3 a): the pair labels are written
        /// from this, never from the model angle, so a label can't disagree with the screen it sits next to. Nil =
        /// label with the model angle.
        var readout: Readout? = nil
    }

    /// The crown readout's value: whole degrees, frozen (red) once the object has failed (FoldBezel.updateReadout).
    struct Readout: Equatable {
        var degrees: Int
        var frozen: Bool

        /// "111°" while live; "AT 83°" once frozen, worded like the reveal label (RevealCardView `foldLabelText`).
        var label: String { frozen ? "AT \(degrees)°" : "\(degrees)°" }
    }

    /// One device of the variety frame (`renderGrid`): its halves, its device options (size, captions and fit are
    /// ignored) and a small mono label under it ("EGG · AT 97°").
    struct GridItem {
        var halves: Halves
        var options: Options
        var label: String?
    }

    struct GridOptions {
        var size = CGSize(width: 2007, height: 2853)
        var caption: String?
        var subcaption: String?
        var backdrop: Backdrop = .studio
    }

    // MARK: - Capture

    /// Snapshot the Fold Press stage as it is on screen now (platen layers, warped anvil ARView, bezel; none of the
    /// SwiftUI overlays above it) and split it at the crease. Nil when no Fold Press stage is on screen.
    ///
    /// `overlays: true` (the reveal frame, FOLD-REVIEW-5 §5 A4) draws the whole window over the stage's bounds
    /// instead, so the SwiftUI chrome on the plates comes too: the print label under the platen plate and Again ·
    /// Share · Next in the console. If the ARView has to be rebuilt from its snapshot, the anvil half loses those
    /// overlays (the source is logged as "arView.snapshot").
    static func capture(scene: PressScene, fold: FoldPressController, overlays: Bool = false) async -> Halves? {
        guard let arView = scene.arView,
              let host = arView.superview?.superview as? FoldStageHostView,
              host.arView === arView, host.window != nil,
              host.bounds.width >= 100, host.bounds.height >= 100 else { return nil }
        let layout: FoldLayout
        if let live = fold.layout, live.canvas == host.bounds.size {
            layout = live
        } else {
            layout = FoldLayout(canvas: host.bounds.size)
        }
        let displayScale = host.traitCollection.displayScale
        let scale = displayScale > 0 ? displayScale : 3

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        format.preferredRange = .standard
        let window = overlays ? host.window : nil
        var full = UIGraphicsImageRenderer(bounds: host.bounds, format: format).image { _ in
            if let window {
                // The window drawn so that the host's bounds land on this image's bounds.
                let origin = host.convert(host.bounds.origin, to: window)
                _ = window.drawHierarchy(in: CGRect(x: host.bounds.minX - origin.x, y: host.bounds.minY - origin.y,
                                                    width: window.bounds.width, height: window.bounds.height),
                                         afterScreenUpdates: false)
            } else {
                _ = host.drawHierarchy(in: host.bounds, afterScreenUpdates: false)
            }
        }

        // drawHierarchy normally includes the ARView's Metal layer; if it doesn't here (the ARView alone comes out
        // flat), rebuild the anvil half from the ARView's own snapshot, warped exactly as on screen.
        var source = window == nil ? "drawHierarchy" : "window.drawHierarchy"
        let probeFormat = UIGraphicsImageRendererFormat()
        probeFormat.scale = 1
        probeFormat.opaque = false
        probeFormat.preferredRange = .standard
        let probe = UIGraphicsImageRenderer(bounds: arView.bounds, format: probeFormat).image { _ in
            _ = arView.drawHierarchy(in: arView.bounds, afterScreenUpdates: false)
        }
        if isFlat(probe.cgImage) {
            if let rebuilt = await rebuildAnvil(over: full, host: host, bezel: fold.bezel.layer, layout: layout,
                                                scale: scale) {
                full = rebuilt
                source = "arView.snapshot"
            } else {
                source = "drawHierarchy (ARView not captured)"
            }
        }

        guard let pixels = full.cgImage else { return nil }
        func crop(_ rect: CGRect) -> CGImage? {
            let r = CGRect(x: rect.minX * scale, y: rect.minY * scale,
                           width: rect.width * scale, height: rect.height * scale).integral
            return pixels.cropping(to: r)
        }
        guard let platen = crop(layout.platenHalf), let anvil = crop(layout.anvilHalf) else { return nil }
        return Halves(platen: platen, crease: crop(layout.creaseRect), anvil: anvil, layout: layout, source: source)
    }

    /// The anvil half from `ARView.snapshot` (unwarped) put through the on-screen keystone warp, the bezel on top.
    private static func rebuildAnvil(over full: UIImage, host: FoldStageHostView, bezel: CALayer, layout: FoldLayout,
                                     scale: CGFloat) async -> UIImage? {
        let arView = host.arView
        guard let shot = await snapshot(arView), let shotPixels = shot.cgImage else { return nil }
        // Core Animation row-vector layout (FoldPressView `transform3D`, FOLD-PRESS §9.3 step 4); the ARView layer
        // sits at the clip view's origin with anchorPoint .zero, and the clip view's frame is `layout.anvilHalf`.
        let t = arView.layer.transform
        let origin = layout.anvilHalf.origin
        func onCanvas(_ p: CGPoint) -> CGPoint {
            let w = t.m14 * p.x + t.m24 * p.y + t.m44
            let safe = abs(w) > 1e-9 ? w : 1
            let x = (t.m11 * p.x + t.m21 * p.y + t.m41) / safe + origin.x
            let y = (t.m12 * p.x + t.m22 * p.y + t.m42) / safe + origin.y
            return CGPoint(x: x * scale, y: y * scale)
        }
        let b = arView.bounds
        let corners = [CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.minY),
                       CGPoint(x: b.maxX, y: b.maxY), CGPoint(x: b.minX, y: b.maxY)].map(onCanvas)
        let pixelSize = CGSize(width: host.bounds.width * scale, height: host.bounds.height * scale)
        let context = CIContext(options: [.cacheIntermediates: false])
        guard case let (warped, pixelRect)? = warp(shotPixels, corners: corners, canvas: pixelSize, context: context) else {
            return nil
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(bounds: host.bounds, format: format).image { renderer in
            let cg = renderer.cgContext
            full.draw(in: host.bounds)
            cg.saveGState()
            cg.clip(to: layout.anvilHalf)
            UIImage(cgImage: warped).draw(in: CGRect(x: pixelRect.minX / scale, y: pixelRect.minY / scale,
                                                     width: pixelRect.width / scale, height: pixelRect.height / scale))
            cg.translateBy(x: bezel.frame.minX, y: bezel.frame.minY)
            bezel.render(in: cg)   // 2D layers only: rails, jaws, console, plate shade
            cg.restoreGState()
        }
    }

    private static func snapshot(_ view: ARView) async -> UIImage? {
        await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            view.snapshot(saveToHDR: false) { image in
                continuation.resume(returning: image)
            }
        }
    }

    /// True when a 16 × 16 downsample has (almost) no variation, i.e. nothing but a background was drawn.
    private static func isFlat(_ image: CGImage?, tolerance: Int = 6) -> Bool {
        guard let image else { return true }
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return true }
        for channel in 0..<4 {
            var lo = 255, hi = 0
            for i in stride(from: channel, to: pixels.count, by: 4) {
                lo = min(lo, Int(pixels[i]))
                hi = max(hi, Int(pixels[i]))
            }
            if hi - lo > tolerance { return false }
        }
        return true
    }

    // MARK: - Render

    /// Compose the store shot from two page images (platen = top/leading page, anvil = bottom/trailing page, each in
    /// canvas orientation, split at the crease). The crease band image is optional (graphite otherwise).
    static func render(platen: UIImage, anvil: UIImage, crease: UIImage? = nil, layout: FoldLayout,
                       options: Options = Options()) -> UIImage? {
        guard let p = platen.cgImage, let a = anvil.cgImage else { return nil }
        return render(Halves(platen: p, crease: crease?.cgImage, anvil: a, layout: layout, source: "images"),
                      options: options)
    }

    /// One device, framed: width fit with bleed into the hero box, bottom-anchored, caption in the top band.
    static func render(_ halves: Halves, options: Options = Options()) -> UIImage? {
        let size = options.size
        guard size.width >= 64, size.height >= 64 else { return nil }
        let context = CIContext(options: [.cacheIntermediates: false])
        let unit = options.heroBox ?? defaultHeroBox(size, captioned: options.caption != nil)
        guard let shot = deviceDraws(halves, options: options, box: frameRect(unit, in: size), canvas: size,
                                     context: context) else { return nil }
        var heroMark: HeroMark?
        if let label = options.angleMark, !label.isEmpty, shot.lidCorners.count == 2 {
            heroMark = HeroMark(label: label, angle: options.hingeAngle, lid: shot.lidCorners,
                                captioned: options.caption != nil)
        }
        return flatten(size: size, backdrop: options.backdrop, devices: [shot], caption: options.caption,
                       subcaption: options.subcaption, marks: nil, heroMark: heroMark)
    }

    /// The before/after frame: `before` (e.g. 112°) small, `after` (the squish, ~62°) large, an arrow between them.
    static func renderPair(before: Halves, after: Halves, options: PairOptions = PairOptions()) -> UIImage? {
        let size = options.size
        guard size.width >= 64, size.height >= 64 else { return nil }
        let context = CIContext(options: [.cacheIntermediates: false])
        let portrait = size.height >= size.width
        // FOLD-REVIEW-6 §3 A 02, FOLD-REVIEW-7 §3 A 02: the small device's front corner kissed the large lid's corner
        // (R7 measured 15–25 px clear at 0.25 / 0.47). The small box 0.25 → 0.23 tall lifts and shrinks the 111°
        // device (its front edge ~57 px higher); the large box 0.47 → 0.48 drops the lid ~29 px, keeping a ~100 px
        // floor under it. r7tools/framing3.mjs pair (sharp-cornered hulls, so conservative: it reads the R7 layout as
        // touching) gives 65 px clear at 2007 × 2853; the rounded corners add more.
        let beforeUnit = portrait ? CGRect(x: 0.04, y: 0.215, width: 0.46, height: 0.23)
                                  : CGRect(x: 0.04, y: 0.30, width: 0.38, height: 0.50)
        let afterUnit = portrait ? CGRect(x: 0.20, y: 0.48, width: 0.76, height: 0.50)
                                 : CGRect(x: 0.45, y: 0.22, width: 0.51, height: 0.75)
        var small = options.before
        small.size = size
        small.fit = .contain
        small.targetFill = nil
        small.anchor = .bottom(0)
        small.caption = nil
        small.subcaption = nil
        var large = options.after
        large.size = size
        large.fit = .width(bleed: 0)
        large.targetFill = nil
        large.anchor = .bottom(0.03)
        large.caption = nil
        large.subcaption = nil
        guard let first = deviceDraws(before, options: small, box: frameRect(beforeUnit, in: size), canvas: size,
                                      context: context),
              let second = deviceDraws(after, options: large, box: frameRect(afterUnit, in: size), canvas: size,
                                       context: context) else { return nil }
        // FOLD-REVIEW-5 §3 a: each label says what that device's crown readout says ("111°", then "AT 83°" once it
        // froze at the failure), so a label never contradicts the red number above it. The profile glyph beside it
        // draws the modelled pose.
        let marks = PairMarks(before: first.frame, after: second.frame,
                              beforeLabel: pairLabel(before.readout, model: small.hingeAngle),
                              afterLabel: pairLabel(after.readout, model: large.hingeAngle),
                              beforeAngle: small.hingeAngle, afterAngle: large.hingeAngle,
                              labels: options.angleLabels)
        return flatten(size: size, backdrop: options.backdrop, devices: [first, second], caption: options.caption,
                       subcaption: options.subcaption, marks: marks)
    }

    private static func pairLabel(_ readout: Readout?, model: Double) -> String {
        readout?.label ?? "\(Int(model.rounded()))°"
    }

    /// The variety frame (FOLD-REVIEW-5 §5 A6): several devices on one sweep under one caption, each with a small
    /// mono label. 1 device: the hero box; 2: stacked; 3: two above, one larger below; 4+: rows of two.
    static func renderGrid(_ items: [GridItem], options: GridOptions = GridOptions()) -> UIImage? {
        let size = options.size
        guard !items.isEmpty, size.width >= 64, size.height >= 64 else { return nil }
        let context = CIContext(options: [.cacheIntermediates: false])
        let cells = gridCells(count: items.count, portrait: size.height >= size.width)
        // Room under each device for its label.
        let labelBand: CGFloat = items.contains { $0.label != nil } ? 0.035 : 0
        var devices: [StoreDevice] = []
        var labels: [(text: String, frame: CGRect)] = []
        for (item, cell) in zip(items, cells) {
            var device = item.options
            device.size = size
            device.fit = .contain
            device.targetFill = nil
            device.maxFill = nil
            device.anchor = .bottom(0)
            device.caption = nil
            device.subcaption = nil
            let unit = CGRect(x: cell.minX, y: cell.minY, width: cell.width, height: max(cell.height - labelBand, 0.05))
            guard let drawn = deviceDraws(item.halves, options: device, box: frameRect(unit, in: size), canvas: size,
                                          context: context) else { continue }
            devices.append(drawn)
            if let label = item.label { labels.append((text: label, frame: drawn.frame)) }
        }
        guard !devices.isEmpty else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let pool = CGPoint(x: size.width / 2, y: size.height * 0.62)
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let cg = renderer.cgContext
            drawBackdrop(cg, size: size, pool: pool, style: options.backdrop)
            cg.setLineJoin(.round)
            for device in devices {
                for draw in device.draws { paint(draw, in: cg) }
            }
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: size.height * 0.0145, weight: .semibold),
                .foregroundColor: captionInk.withAlphaComponent(0.78),
                .kern: size.height * 0.0012,
                .paragraphStyle: paragraph,
            ]
            for label in labels {
                let text = NSAttributedString(string: label.text, attributes: attributes)
                let height = ceil(text.size().height)
                let width = min(size.width * 0.9, max(label.frame.width, text.size().width + 8))
                text.draw(in: CGRect(x: label.frame.midX - width / 2, y: label.frame.maxY + size.height * 0.008,
                                     width: width, height: height + 2))
            }
            if let caption = options.caption, !caption.isEmpty {
                drawCaption(caption, subline: options.subcaption, size: size)
            }
        }
    }

    /// Unit cells for `renderGrid`, back row first (so nearer devices are drawn over farther ones' shadows).
    private static func gridCells(count: Int, portrait: Bool) -> [CGRect] {
        let top = 0.215, bottom = 0.975
        let height = bottom - top
        switch count {
        case ...1:
            return [portrait ? CGRect(x: 0.04, y: 0.21, width: 0.92, height: 0.76)
                             : CGRect(x: 0.06, y: 0.22, width: 0.88, height: 0.75)]
        case 2:
            if !portrait {
                return [CGRect(x: 0.04, y: top, width: 0.45, height: height),
                        CGRect(x: 0.51, y: top, width: 0.45, height: height)]
            }
            return [CGRect(x: 0.10, y: top, width: 0.80, height: height / 2 - 0.01),
                    CGRect(x: 0.10, y: top + height / 2 + 0.01, width: 0.80, height: height / 2 - 0.01)]
        case 3 where portrait:
            let upper = height * 0.44
            return [CGRect(x: 0.03, y: top, width: 0.46, height: upper),
                    CGRect(x: 0.51, y: top, width: 0.46, height: upper),
                    CGRect(x: 0.14, y: top + upper + 0.015, width: 0.72, height: height - upper - 0.015)]
        default:
            let columns = portrait ? 2 : min(count, 4)
            let rows = Int((Double(count) / Double(columns)).rounded(.up))
            let gap = 0.015
            let cellWidth = (0.94 - gap * Double(columns - 1)) / Double(columns)
            let cellHeight = (height - gap * Double(rows - 1)) / Double(rows)
            return (0..<count).map { i in
                let row = i / columns, column = i % columns
                // The last row, if short, is centred.
                let inRow = row == rows - 1 ? count - row * columns : columns
                let rowWidth = cellWidth * Double(inRow) + gap * Double(inRow - 1)
                let x = 0.03 + (0.94 - rowWidth) / 2 + Double(column) * (cellWidth + gap)
                return CGRect(x: x, y: top + Double(row) * (cellHeight + gap), width: cellWidth, height: cellHeight)
            }
        }
    }

    private static func defaultHeroBox(_ size: CGSize, captioned: Bool) -> CGRect {
        if size.height >= size.width { return CGRect(x: 0.04, y: 0.21, width: 0.92, height: 0.76) }
        return captioned ? CGRect(x: 0.06, y: 0.22, width: 0.88, height: 0.75)
                         : CGRect(x: 0.10, y: 0.07, width: 0.80, height: 0.88)
    }

    private static func frameRect(_ unit: CGRect, in size: CGSize) -> CGRect {
        CGRect(x: unit.minX * size.width, y: unit.minY * size.height,
               width: unit.width * size.width, height: unit.height * size.height)
    }

    /// The device's draw list in output pixels: floor shadows, hinge, then both pages back to front.
    private static func deviceDraws(_ halves: Halves, options: Options, box: CGRect, canvas size: CGSize,
                                    context: CIContext) -> StoreDevice? {
        let tabletop = options.model == .tabletop || !halves.layout.isBook
        let rig = StoreRig(layout: halves.layout, angleDegrees: options.hingeAngle, tabletop: tabletop)
        let platenSlab = rig.slab(.platen)
        let anvilSlab = rig.slab(.anvil)
        let hinge = rig.hinge()
        let devicePoints = platenSlab.points + anvilSlab.points + hinge.points
        guard !devicePoints.isEmpty else { return nil }
        var lo = SIMD3<Double>(repeating: .infinity)
        var hi = SIMD3<Double>(repeating: -.infinity)
        for p in devicePoints {
            lo = simd_min(lo, p)
            hi = simd_max(hi, p)
        }
        let target = (lo + hi) / 2
        let eye = rig.eye(model: options.eyeModel, contentAngle: halves.hingeAngle ?? options.hingeAngle,
                          threeQuarter: options.eye == .threeQuarter, azimuthDegrees: options.azimuthDegrees,
                          elevationDegrees: options.elevationDegrees, target: target)
        let camera = StoreCamera(eye: eye, target: target)

        // Fit the projected device into the hero box (FOLD-REVIEW-4 F2): width fit with bleed toward the target fill,
        // never taller than the box; sit it on the box floor so the empty space goes to the caption band.
        var qlo = SIMD2<Double>(repeating: .infinity)
        var qhi = SIMD2<Double>(repeating: -.infinity)
        for p in devicePoints {
            let q = camera.project(p)
            qlo = simd_min(qlo, q)
            qhi = simd_max(qhi, q)
        }
        let span = simd_max(qhi - qlo, SIMD2<Double>(repeating: 1e-6))
        let widthScale = Double(box.width) / span.x
        let heightScale = Double(box.height) / span.y
        var scale: Double
        switch options.fit {
        case .contain:
            scale = min(widthScale, heightScale)
        case let .width(bleed):
            scale = widthScale
            if let fill = options.targetFill, fill > 0 {
                let wanted = fill * Double(size.height) / span.y
                scale = max(scale, min(wanted, widthScale * (1 + max(bleed, 0))))
            }
            if let cap = options.maxFill, cap > 0 {
                scale = min(scale, cap * Double(size.height) / span.y)
            }
            scale = min(scale, heightScale)
        }
        let fit: StoreFit
        switch options.anchor {
        case .centre:
            fit = StoreFit(scale: scale, reference: (qlo + qhi) / 2, pixel: CGPoint(x: box.midX, y: box.midY))
        case let .bottom(lift):
            fit = StoreFit(scale: scale, reference: SIMD2<Double>((qlo.x + qhi.x) / 2, qlo.y),
                           pixel: CGPoint(x: box.midX, y: box.maxY - CGFloat(lift) * box.height))
        case let .top(drop):
            // Image-plane y is up, so the highest point is qhi.y.
            fit = StoreFit(scale: scale, reference: SIMD2<Double>((qlo.x + qhi.x) / 2, qhi.y),
                           pixel: CGPoint(x: box.midX, y: box.minY + CGFloat(drop) * box.height))
        }
        func px(_ p: SIMD3<Double>) -> CGPoint { fit.point(camera.project(p)) }
        let devicePixels = span.x * scale

        let light = simd_normalize(SIMD3<Double>(-0.35, 0.85, 0.40))
        func visible(_ face: StoreRig.Face) -> Bool { simd_dot(face.normal, eye - face.centroid) > 0 }
        var draws: [StoreDraw] = []

        // 1. Shadows on the floor (y = lowest point): a broad occlusion skirt, the key light's cast shadow, and a
        //    tight contact line where the device touches.
        let ground = lo.y
        let shadowInk = UIColor(hex: 0x3B2F25)
        let skirt = devicePoints.map { px(SIMD3($0.x, ground, $0.z)) }
        if let d = blurred(hull(skirt), color: shadowInk.withAlphaComponent(0.16), sigma: 0.06 * devicePixels,
                           size: size, context: context) {
            draws.append(d)
        }
        let cast = devicePoints.map { p -> CGPoint in
            let t = (p.y - ground) / light.y
            return px(p - t * light)
        }
        if let d = blurred(hull(cast), color: shadowInk.withAlphaComponent(0.22), sigma: 0.025 * devicePixels,
                           size: size, context: context) {
            draws.append(d)
        }
        let contact = devicePoints.filter { $0.y - ground < 1.0 }.map { px($0) }
        if let d = blurred(hull(contact), color: shadowInk.withAlphaComponent(0.55), sigma: 0.006 * devicePixels,
                           size: size, context: context) {
            draws.append(d)
        }

        // 2. The hinge: barrel faces, then the bend strip (the crease band texture in 10 warped slices, shaded as a
        //    cylinder). Sorted far to near among themselves; drawn before both pages (it is the back of the wedge).
        var hingeDraws: [(distance: Double, draw: StoreDraw)] = []
        let barrel = SIMD3<Double>(0x4A, 0x4D, 0x54) / 255
        for face in hinge.body where visible(face) {
            let colour = shaded(barrel, normal: face.normal, light: light)
            hingeDraws.append((distance: simd_length(face.centroid - eye),
                               draw: StoreDraw.fill(face.points.map { px($0) }, colour, true)))
        }
        if case let (texture, textureRect, textureScale)? = creaseTexture(halves.crease, rig: rig) {
            for (k, inner) in hinge.inner.enumerated() where visible(inner) {
                let distance = simd_length(inner.centroid - eye)
                let slice = rig.creaseSliceRect(k)
                let pixelRect = CGRect(x: (slice.minX - textureRect.minX) * textureScale,
                                       y: (slice.minY - textureRect.minY) * textureScale,
                                       width: slice.width * textureScale, height: slice.height * textureScale).integral
                if let piece = texture.cropping(to: pixelRect) {
                    let quad = corners(of: slice).map { px(rig.bendWorld(canvas: $0)) }
                    if case let (image, rect)? = warp(piece, corners: quad, canvas: size, context: context) {
                        hingeDraws.append((distance: distance, draw: StoreDraw.image(image, rect)))
                    }
                }
                let lambert = max(0, simd_dot(inner.normal, light))
                let shade = UIColor(white: 0, alpha: CGFloat(0.05 + 0.40 * (1 - lambert)))
                hingeDraws.append((distance: distance - 1e-3,
                                   draw: StoreDraw.fill(inner.points.map { px($0) }, shade, false)))
            }
        }
        hingeDraws.sort { $0.distance > $1.distance }
        draws += hingeDraws.map { $0.draw }

        // 3. The pages, far one first: lit body sides and back, then the screen (warped texture) if it faces the eye.
        let body = SIMD3<Double>(0x3A, 0x3D, 0x43) / 255
        let pages = [StorePage(panel: .platen, slab: platenSlab, image: halves.platen),
                     StorePage(panel: .anvil, slab: anvilSlab, image: halves.anvil)]
            .sorted { simd_length($0.slab.frontCentroid - eye) > simd_length($1.slab.frontCentroid - eye) }
        for page in pages {
            for face in page.slab.faces where visible(face) {
                let colour = shaded(body, normal: face.normal, light: light)
                draws.append(StoreDraw.fill(face.points.map { px($0) }, colour, true))
            }
            let normal = rig.normal(page.panel)
            let splat = page.panel == .anvil ? options.escapedSplat : nil
            guard simd_dot(normal, eye - page.slab.frontCentroid) > 0,
                  case let (texture, textureRect)? = pageTexture(page.panel, image: page.image, rig: rig,
                                                                 sheen: options.glassSheen, splat: splat,
                                                                 shade: options.lidShading && rig.tabletop,
                                                                 keyTilt: options.keyTiltDegrees) else { continue }
            let quad = corners(of: textureRect).map { px(rig.world(canvas: $0, on: page.panel)) }
            if case let (image, rect)? = warp(texture, corners: quad, canvas: size, context: context) {
                draws.append(StoreDraw.image(image, rect))
            }
        }

        let a = fit.point(qlo), b = fit.point(qhi)
        let frame = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
        // The lid's two free corners (bezel included, square) for the hero's angle mark: per lateral end, whichever of
        // the screen-side and back-side corner projects higher, so the mark also clears the lid's top edge thickness.
        let lidTop = rig.reach(.platen) + StoreRig.bezelPt
        let lidBack = StoreRig.thicknessMM * rig.normal(.platen)
        let lidCorners: [CGPoint] = [-StoreRig.bezelPt, Double(halves.layout.lateralLength) + StoreRig.bezelPt].map { l in
            let front = rig.world(canvas: rig.canvas(a: lidTop, l: l, on: .platen), on: .platen)
            let screenSide = px(front), backSide = px(front - lidBack)
            return screenSide.y <= backSide.y ? screenSide : backSide
        }
        return StoreDevice(draws: draws, pool: px(SIMD3(target.x, ground, target.z)), frame: frame,
                           lidCorners: lidCorners)
    }

    /// Flatten onto the sweep. Opaque, sRGB, 8-bit: App Store screenshots must have no alpha.
    private static func flatten(size: CGSize, backdrop: Backdrop, devices: [StoreDevice], caption: String?,
                                subcaption: String?, marks: PairMarks?, heroMark: HeroMark? = nil) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let pool = devices.last?.pool ?? CGPoint(x: size.width / 2, y: size.height * 0.7)
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let cg = renderer.cgContext
            drawBackdrop(cg, size: size, pool: pool, style: backdrop)
            cg.setLineJoin(.round)
            for device in devices {
                for draw in device.draws {
                    paint(draw, in: cg)
                }
            }
            if let marks { drawPairMarks(cg, marks, size: size) }
            if let heroMark { drawHeroMark(cg, heroMark, size: size) }
            if let caption, !caption.isEmpty { drawCaption(caption, subline: subcaption, size: size) }
        }
    }

    private static func paint(_ draw: StoreDraw, in cg: CGContext) {
        switch draw {
        case let .fill(points, color, seal):
            guard points.count >= 3 else { return }
            let shape = path(points, closed: true)
            cg.addPath(shape)
            cg.setFillColor(color.cgColor)
            cg.fillPath()
            if seal {   // hides antialiasing seams between adjacent body polygons
                cg.addPath(shape)
                cg.setStrokeColor(color.cgColor)
                cg.setLineWidth(0.8)
                cg.strokePath()
            }
        case let .image(image, rect):
            UIImage(cgImage: image).draw(in: rect)
        }
    }

    // MARK: - Captions (docs/appstore/screenshots.md "Visual system for captions")

    private static let captionInk = UIColor(hex: 0x2B2D31)
    private static let captionHighlight = UIColor(hex: 0xFFB81C)

    /// The headline centred in the top 21 % of the frame (never over the hero box), cap height ≥ 4 % of the frame
    /// height. Line breaks follow `CaptionWrap` (FOLD-REVIEW-6 N11): a headline too wide for one line breaks at its
    /// most balanced sentence boundary, every wrapped paragraph is balanced (no orphaned last word), and the
    /// sub-line shrinks (to 0.30 of the headline size at the least) to stay on one line before it wraps.
    private static func drawCaption(_ text: String, subline: String?, size: CGSize) {
        let band = CGRect(x: size.width * 0.06, y: size.height * 0.03,
                          width: size.width * 0.88, height: size.height * 0.165)
        // Shrink until the caption fits the band (two-line headlines need ~0.045 at 1320 wide); fitting beats the
        // 4 % cap-height target, which a 0.058 floor kept but at the cost of clipping the first line off the frame.
        let minimum = size.height * 0.036
        var fontSize = size.height * 0.064
        func measure(_ string: NSAttributedString) -> CGSize {
            let r = string.boundingRect(with: CGSize(width: band.width, height: .greatestFiniteMagnitude),
                                        options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            return CGSize(width: ceil(r.width), height: ceil(r.height))
        }
        /// The headline at size `s`, and whether a paragraph of it still ends on one lone word.
        func headlineString(_ s: CGFloat) -> (text: NSAttributedString, orphan: Bool) {
            let font = roundedFont(s, weight: .heavy)
            let paragraphs = CaptionWrap.balancedLines(text, width: band.width, sentenceBreak: true) { plain in
                NSAttributedString(string: plain, attributes: [.font: font]).size().width
            }
            return (text: captionString(CaptionWrap.joined(paragraphs), size: s),
                    orphan: CaptionWrap.hasOrphan(paragraphs))
        }
        func sublineAttributed(_ s: CGFloat) -> NSAttributedString? {
            guard let subline else { return nil }
            let plain = subline.replacingOccurrences(of: "*", with: "")
            func width(_ string: String, _ points: CGFloat) -> CGFloat {
                NSAttributedString(string: string, attributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: points, weight: .semibold),
                ]).size().width
            }
            let natural = s * CaptionWrap.sublineScale
            if let points = CaptionWrap.oneLineSublineSize(natural: natural, naturalWidth: width(plain, natural),
                                                           width: band.width) {
                return sublineString(plain, pointSize: points)
            }
            let wrapped = CaptionWrap.balanced(plain, width: band.width, sentenceBreak: false) { width($0, natural) }
            return sublineString(wrapped, pointSize: natural)
        }
        var headline = headlineString(fontSize)
        var sub = sublineAttributed(fontSize)
        // Shrink while it doesn't fit, or while a paragraph ends on one lone word ("File the / *evidence*."): a size
        // step usually pulls that word back onto the line. At the minimum, the balanced break stands.
        while fontSize > minimum {
            let height = measure(headline.text).height + (sub.map { measure($0).height + fontSize * 0.30 } ?? 0)
            if height <= band.height && !headline.orphan { break }
            fontSize = max(minimum, fontSize * 0.95)
            headline = headlineString(fontSize)
            sub = sublineAttributed(fontSize)
        }
        let headSize = measure(headline.text)
        let subSize = sub.map { measure($0) } ?? .zero
        let gap = sub == nil ? 0 : fontSize * 0.30
        var y = max(band.minY, band.midY - (headSize.height + gap + subSize.height) / 2)
        headline.text.draw(with: CGRect(x: band.minX, y: y, width: band.width, height: headSize.height + 2),
                      options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        y += headSize.height + gap
        sub?.draw(with: CGRect(x: band.minX, y: y, width: band.width, height: subSize.height + 2),
                  options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
    }

    /// `*word*` marks the highlighted word, as in screenshots.md. `text` already carries its line breaks.
    private static func captionString(_ text: String, size: CGFloat) -> NSAttributedString {
        let source = text
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineHeightMultiple = 0.92
        let font = roundedFont(size, weight: .heavy)
        let result = NSMutableAttributedString()
        for (index, piece) in source.components(separatedBy: "*").enumerated() where !piece.isEmpty {
            let color = index % 2 == 1 ? captionHighlight : captionInk
            result.append(NSAttributedString(string: piece, attributes: [
                .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
            ]))
        }
        return result
    }

    private static func sublineString(_ text: String, pointSize: CGFloat) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: text.replacingOccurrences(of: "*", with: ""), attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: pointSize, weight: .semibold),
            .foregroundColor: captionInk.withAlphaComponent(0.72),
            .paragraphStyle: paragraph,
        ])
    }

    private static func roundedFont(_ size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    // MARK: - Pair marks

    /// A hand-drawn graphite arrow from the small device toward the large one, and the two hinge angles.
    private static func drawPairMarks(_ cg: CGContext, _ marks: PairMarks, size: CGSize) {
        let unit = min(size.width, size.height)
        let start: CGPoint, end: CGPoint, control: CGPoint
        if size.height >= size.width {
            start = CGPoint(x: marks.before.maxX + unit * 0.03, y: marks.before.midY)
            end = CGPoint(x: marks.after.midX + marks.after.width * 0.05, y: marks.after.minY - unit * 0.03)
            control = CGPoint(x: end.x + unit * 0.02, y: start.y)
        } else {
            start = CGPoint(x: marks.before.maxX + unit * 0.02, y: marks.before.minY + marks.before.height * 0.35)
            end = CGPoint(x: marks.after.minX - unit * 0.01, y: marks.after.minY + marks.after.height * 0.30)
            control = CGPoint(x: (start.x + end.x) / 2, y: min(start.y, end.y) - unit * 0.06)
        }
        let ink = captionInk.withAlphaComponent(0.85)
        cg.saveGState()
        cg.setStrokeColor(ink.cgColor)
        cg.setLineCap(.round)
        cg.setLineJoin(.round)
        cg.setLineWidth(unit * 0.010)
        // Two passes a hair apart read as a marker stroke rather than a vector line.
        for offset in [CGFloat(0), unit * 0.0015] {
            cg.move(to: CGPoint(x: start.x, y: start.y + offset))
            cg.addQuadCurve(to: CGPoint(x: end.x + offset, y: end.y),
                            control: CGPoint(x: control.x + offset, y: control.y - offset))
            cg.strokePath()
        }
        let dx = end.x - control.x, dy = end.y - control.y
        let length = max(hypot(dx, dy), 1e-3)
        let back = CGPoint(x: -dx / length, y: -dy / length)
        let head = unit * 0.038
        for turn in [CGFloat(0.50), CGFloat(-0.50)] {
            let c = cos(turn), s = sin(turn)
            let dir = CGPoint(x: back.x * c - back.y * s, y: back.x * s + back.y * c)
            cg.move(to: end)
            cg.addLine(to: CGPoint(x: end.x + dir.x * head, y: end.y + dir.y * head))
            cg.strokePath()
        }
        cg.restoreGState()
        guard marks.labels else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: roundedFont(unit * 0.045, weight: .heavy),
            .foregroundColor: captionInk.withAlphaComponent(0.80),
        ]
        let first = NSAttributedString(string: marks.beforeLabel, attributes: attributes)
        let second = NSAttributedString(string: marks.afterLabel, attributes: attributes)
        let firstOrigin = CGPoint(x: start.x, y: start.y - unit * 0.075)
        let secondOrigin = CGPoint(x: end.x + unit * 0.05, y: end.y - unit * 0.065)
        first.draw(at: firstOrigin)
        second.draw(at: secondOrigin)
        // FOLD-REVIEW-5 §3 c: the V in side profile next to each label, at the modelled angle.
        let fontSize = unit * 0.045
        for (origin, text, angle) in [(firstOrigin, first, marks.beforeAngle), (secondOrigin, second, marks.afterAngle)] {
            drawProfileGlyph(cg, angle: angle, label: CGRect(origin: origin, size: text.size()),
                             fontSize: fontSize, size: size)
        }
    }

    /// The hero's angle mark (FOLD-REVIEW-6 #1 b): the readout label ("AT 67°", the pair's type) and the profile V
    /// glyph at the modelled angle, as one group on the empty sweep above the lid's lower free corner. At the 22°/50°
    /// hero that corner is the right one, ~9 % of the frame lower than the left, so the group fits between the lid's
    /// edge and the caption band. Never above the caption band's floor (21 %), never past a 3 % side margin.
    private static func drawHeroMark(_ cg: CGContext, _ mark: HeroMark, size: CGSize) {
        guard mark.lid.count == 2 else { return }
        let unit = min(size.width, size.height)
        let fontSize = unit * 0.045
        let text = NSAttributedString(string: mark.label, attributes: [
            .font: roundedFont(fontSize, weight: .heavy),
            .foregroundColor: captionInk.withAlphaComponent(0.80),
        ])
        let textSize = text.size()
        // drawProfileGlyph's geometry: a stroke of 6 % of the width, hinge on the label's baseline, 0.35 em gap.
        let glyphLength = size.width * 0.06
        let gap = fontSize * 0.35
        let groupWidth = textSize.width + gap + glyphLength
        let theta = CGFloat(clamp(mark.angle, 0, 180) * Double.pi / 180)
        let hingeDrop = fontSize * 0.98
        let rise = max(0, sin(theta) * glyphLength - hingeDrop)   // how far the lid stroke pokes above the label
        let groupHeight = rise + max(textSize.height, hingeDrop + fontSize * 0.13)
        let a = mark.lid[0], b = mark.lid[1]
        let low = a.y >= b.y ? a : b, high = a.y >= b.y ? b : a
        let margin = size.width * 0.03
        var minX = low.x >= high.x ? min(low.x + groupWidth * 0.25, size.width - margin) - groupWidth
                                   : max(low.x - groupWidth * 0.25, margin)
        minX = min(max(minX, margin), size.width - margin - groupWidth)
        // The lid's free edge (a straight line between the corners) under the group: clear its higher end.
        func edgeY(_ x: CGFloat) -> CGFloat {
            let dx = b.x - a.x
            guard abs(dx) > 1 else { return min(a.y, b.y) }
            let t = min(max((x - a.x) / dx, 0), 1)
            return a.y + (b.y - a.y) * t
        }
        let clearance = min(edgeY(minX), edgeY(minX + groupWidth)) - fontSize * 0.30
        let bandFloor = mark.captioned ? size.height * 0.21 : size.height * 0.03
        let top = max(bandFloor, clearance - groupHeight)
        let label = CGRect(x: minX, y: top + rise, width: textSize.width, height: textSize.height)
        text.draw(at: label.origin)
        drawProfileGlyph(cg, angle: mark.angle, label: label, fontSize: fontSize, size: size)
    }

    /// A hinge in side profile: the table page as a horizontal stroke to the right of the hinge, the lid a stroke at
    /// `angle` from it (leaning right, over the page, below 90°), a small yellow arc between them and a hinge dot.
    /// About 6 % of the frame width, sitting on the label's baseline to its right (or its left if there's no room).
    private static func drawProfileGlyph(_ cg: CGContext, angle: Double, label: CGRect, fontSize: CGFloat,
                                         size: CGSize) {
        let length = size.width * 0.06
        let theta = CGFloat(clamp(angle, 0, 180) * Double.pi / 180)
        let lid = CGPoint(x: cos(theta) * length, y: -sin(theta) * length)   // relative to the hinge, y down
        let left = min(0, lid.x), right = length
        let gap = fontSize * 0.35
        var hingeX = label.maxX + gap - left
        if hingeX + right > size.width - size.width * 0.03 {
            hingeX = label.minX - gap - right
        }
        let hinge = CGPoint(x: hingeX, y: label.minY + fontSize * 0.98)
        let weight = max(2, fontSize * 0.13)
        cg.saveGState()
        cg.setLineCap(.round)
        cg.setLineJoin(.round)
        // The arc first, under the strokes: from the page (0) round to the lid (θ), counter-clockwise on screen.
        cg.setStrokeColor(captionHighlight.cgColor)
        cg.setLineWidth(weight * 0.8)
        cg.addArc(center: hinge, radius: length * 0.42, startAngle: 0, endAngle: -theta, clockwise: true)
        cg.strokePath()
        cg.setStrokeColor(captionInk.withAlphaComponent(0.85).cgColor)
        cg.setLineWidth(weight)
        cg.move(to: CGPoint(x: hinge.x + length, y: hinge.y))
        cg.addLine(to: hinge)
        cg.addLine(to: CGPoint(x: hinge.x + lid.x, y: hinge.y + lid.y))
        cg.strokePath()
        cg.setFillColor(captionInk.cgColor)
        cg.fillEllipse(in: CGRect(x: hinge.x - weight, y: hinge.y - weight, width: 2 * weight, height: 2 * weight))
        cg.restoreGState()
    }

    // MARK: - Textures

    private static let bezelColor = UIColor(hex: 0x0D0E10)
    private static let rimColor = UIColor(hex: 0x7A7E86, alpha: 0.9)
    private static let creaseGraphite = UIColor(hex: 0x2B2D31)

    /// One page drawn flat in canvas points: black glass bezel with rounded free corners, the screen content clipped
    /// to its rounded corners (plus the escaped splat on the anvil), a faint sheen and the rim. The rect includes a
    /// transparent margin so warped edges stay antialiased.
    private static func pageTexture(_ panel: StoreRig.Panel, image: CGImage, rig: StoreRig, sheen: Bool,
                                    splat: EscapedSplat?, shade: Bool, keyTilt: Double = 0) -> (CGImage, CGRect)? {
        let layout = rig.layout
        let b = StoreRig.bezelPt, m = StoreRig.marginPt, c = rig.c
        let reach = rig.reach(panel)
        let depth: ClosedRange<Double> = panel == .anvil
            ? (c - m)...(c + reach + b + m)
            : (-(c + reach + b + m))...(-(c - m))
        let rect = layout.rect(lateral: (-b - m)...(layout.lateralLength + b + m), depth: depth)
        let half = rig.half(panel)
        guard half.width > 1, rect.width > 1, rect.height > 1 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = min(max(CGFloat(image.width) / half.width, 1), 3)
        format.opaque = false
        format.preferredRange = .standard
        let bodyOutline = rig.outline(panel, expand: b, radius: StoreRig.bodyRadiusPt)
        let screenOutline = rig.outline(panel, expand: 0, radius: StoreRig.screenRadiusPt)
        let texture = UIGraphicsImageRenderer(size: rect.size, format: format).image { renderer in
            let cg = renderer.cgContext
            cg.translateBy(x: -rect.minX, y: -rect.minY)
            cg.addPath(path(bodyOutline, closed: true))
            cg.setFillColor(bezelColor.cgColor)
            cg.fillPath()
            cg.saveGState()
            cg.addPath(path(screenOutline, closed: true))
            cg.clip()
            UIImage(cgImage: image).draw(in: half)
            if let splat { drawEscapedSplat(cg, splat, layout: layout) }
            if shade { drawWedgeShading(cg, panel: panel, rig: rig, keyTilt: keyTilt) }
            if sheen, let gradient = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                colors: [UIColor(red: 1, green: 1, blue: 1, alpha: 0).cgColor,
                         UIColor(red: 1, green: 1, blue: 1, alpha: 0.04).cgColor,
                         UIColor(red: 1, green: 1, blue: 1, alpha: 0).cgColor] as CFArray,
                locations: [0.30, 0.46, 0.62]) {
                cg.drawLinearGradient(gradient, start: CGPoint(x: half.minX, y: half.minY),
                                      end: CGPoint(x: half.maxX, y: half.maxY), options: [])
            }
            cg.restoreGState()
            // The rim: free edge and sides only (the crease side continues into the bend).
            cg.addPath(path(bodyOutline, closed: false))
            cg.setStrokeColor(rimColor.cgColor)
            cg.setLineWidth(1.2)
            cg.strokePath()
        }
        guard let pixels = texture.cgImage else { return nil }
        return (pixels, rect)
    }

    /// The splat that got out (FOLD-REVIEW-4 F3): droplets run out from under the strike plate onto the anvil field,
    /// each a short smear from the plate edge, a wet drop and sometimes a satellite. Print space (origin footprint
    /// centre, x = anvil x, y = anvil z, points) is the anvil frame seen top-down, so these sit exactly where the
    /// platen's splat meets the field when the phone shuts. Drawn in canvas points onto the anvil page, clipped to the
    /// anvil field.
    private static func drawEscapedSplat(_ cg: CGContext, _ splat: EscapedSplat, layout: FoldLayout) {
        let stamp = splat.stamp
        guard EscapedSplat.supports(stamp.kind), splat.count > 0 else { return }
        // The splat's centre, as FoldStamps.splatImage places it: the duck's seam, the footprint centre otherwise.
        let centre: CGPoint
        if stamp.kind == .rubberDuck, stamp.features.count >= 3 {
            centre = CGPoint(x: (stamp.features[1].x + stamp.features[2].x) / 2,
                             y: (stamp.features[1].y + stamp.features[2].y) / 2)
        } else {
            centre = .zero
        }
        let ink = stamp.ink
        let edge = FoldStamps.darken(ink, 0.25)
        var rng = SplitMix64(seed: stamp.seed ^ 0x5B1A7 ^ 0xE5CA9E)
        let hx = FoldMetrics.plateLateral / 2, hy = FoldMetrics.plateDepth / 2
        let ppm = FoldMetrics.pointsPerMM
        let field = layout.anvilField.insetBy(dx: 8, dy: 8)
        func canvas(_ x: Double, _ y: Double) -> CGPoint { layout.canvasPoint(anvilMM: SIMD2<Double>(x / ppm, y / ppm)) }
        let cx = Double(centre.x), cy = Double(centre.y)
        cg.saveGState()
        cg.clip(to: layout.anvilField)
        cg.setLineCap(.round)
        for i in 0..<splat.count {
            let angle = Double.random(in: 0..<(2 * Double.pi), using: &rng)
            let dx = cos(angle), dy = sin(angle)
            // Distance from the splat centre to the strike plate's edge along this direction.
            var exit = Double.infinity
            if abs(dx) > 1e-6 { exit = min(exit, ((dx > 0 ? hx : -hx) - cx) / dx) }
            if abs(dy) > 1e-6 { exit = min(exit, ((dy > 0 ? hy : -hy) - cy) / dy) }
            let run = (exit.isFinite ? max(exit, 0) : 0) + Double.random(in: 10...52, using: &rng)
            let radius = Double.random(in: 2.4...5.6, using: &rng) * (i < 3 ? 1.35 : 1)
            let satellite = Double.random(in: 0...1, using: &rng) < 0.5
            let satelliteGap = Double.random(in: 2...8, using: &rng)
            let drop = canvas(cx + dx * run, cy + dy * run)
            guard field.contains(drop) else { continue }
            let tail = canvas(cx + dx * (run - radius * 3.2), cy + dy * (run - radius * 3.2))
            cg.setStrokeColor(ink.withAlphaComponent(0.55).cgColor)
            cg.setLineWidth(CGFloat(radius * 1.1))
            cg.move(to: tail)
            cg.addLine(to: drop)
            cg.strokePath()
            let r = CGFloat(radius)
            cg.setFillColor(edge.withAlphaComponent(0.9).cgColor)
            cg.fillEllipse(in: CGRect(x: drop.x - r, y: drop.y - r, width: 2 * r, height: 2 * r))
            cg.setFillColor(ink.withAlphaComponent(0.95).cgColor)
            cg.fillEllipse(in: CGRect(x: drop.x - r * 0.82, y: drop.y - r * 0.82, width: 1.64 * r, height: 1.64 * r))
            cg.setFillColor(UIColor(white: 1, alpha: 0.45).cgColor)
            cg.fillEllipse(in: CGRect(x: drop.x - r * 0.55, y: drop.y - r * 0.55, width: 0.6 * r, height: 0.6 * r))
            if satellite {
                let far = run + radius * 2.6 + satelliteGap
                let p = canvas(cx + dx * far, cy + dy * far)
                let s = r * 0.45
                cg.setFillColor(ink.withAlphaComponent(0.9).cgColor)
                cg.fillEllipse(in: CGRect(x: p.x - s, y: p.y - s, width: 2 * s, height: 2 * s))
            }
        }
        cg.restoreGState()
    }

    /// Device lighting on one screen (FOLD-REVIEW-5 §3 b), drawn in canvas points inside the screen clip, so it is
    /// warped with the page:
    ///  • anvil: the lid's shadow from the studio's overhead softbox (light straight down, so the shadow is the lid's
    ///    vertical projection: from the crease to under the lid's free edge, with a penumbra that grows with the lid's
    ///    height), alpha 0.10 + 0.25·k; plus a wedge occlusion 0.18·k at the crease fading to 0 over 35 % of the page;
    ///  • lid: a fainter wedge occlusion, 0.12·k over its first 25 %.
    /// k = 1 − (θ − 45)/135, clamped: 0 flat, 0.86 at 64°. A lid at or past 90° leans behind the crease and casts
    /// nothing on the anvil, so the 112° frame only gets the faint wedge and the reveal (150°+) almost nothing.
    /// `keyTilt` (FOLD-REVIEW-6 #1 c, `Options.keyTiltDegrees`) leans the key toward the viewer: the shadow of the
    /// lid's free edge moves forward by its height × tan(tilt), onto the duck.
    private static func drawWedgeShading(_ cg: CGContext, panel: StoreRig.Panel, rig: StoreRig, keyTilt: Double = 0) {
        let thetaDegrees = rig.theta * 180 / Double.pi
        let k = clamp(1 - (thetaDegrees - 45) / 135, 0, 1)
        guard k > 0.01 else { return }
        let ink = UIColor(hex: 0x1E1812)
        let l = rig.layout.lateralCentre
        let space = CGColorSpace(name: CGColorSpace.sRGB)
        /// A gradient across the page (constant along the hinge) from `a` = 0 at the crease edge, in points.
        func band(_ stops: [(a: Double, alpha: Double)]) {
            guard let last = stops.last, last.a > 0.5 else { return }
            var colours: [CGColor] = []
            var locations: [CGFloat] = []
            for stop in stops {
                let location = CGFloat(clamp(stop.a / last.a, 0, 1))
                if let previous = locations.last, location <= previous { continue }
                colours.append(ink.withAlphaComponent(CGFloat(clamp(stop.alpha, 0, 1))).cgColor)
                locations.append(location)
            }
            guard colours.count >= 2,
                  let gradient = CGGradient(colorsSpace: space, colors: colours as CFArray, locations: locations) else { return }
            cg.drawLinearGradient(gradient, start: rig.canvas(a: 0, l: l, on: panel),
                                  end: rig.canvas(a: last.a, l: l, on: panel), options: [])
        }
        switch panel {
        case .anvil:
            let depth = rig.reach(.anvil)
            if let shadow = rig.lidShadowOnAnvil(keyTiltDegrees: keyTilt) {
                let ppm = FoldMetrics.pointsPerMM
                let reach = shadow.reachMM * ppm
                let penumbra = max(0.03 * depth, 0.18 * shadow.heightMM * ppm)
                // A lid only just past vertical overhangs a sliver: scale the shadow down rather than spread it.
                let alpha = (0.10 + 0.25 * k) * clamp(reach / penumbra, 0, 1)
                band([(a: 0, alpha: alpha), (a: max(0, reach - penumbra), alpha: alpha), (a: reach + penumbra, alpha: 0)])
            }
            band([(a: 0, alpha: 0.18 * k), (a: 0.35 * depth, alpha: 0)])
        case .platen:
            band([(a: 0, alpha: 0.12 * k), (a: 0.25 * rig.reach(.platen), alpha: 0)])
        }
    }

    /// The crease band (or plain graphite) with bezel black past both lateral ends, in canvas points.
    private static func creaseTexture(_ image: CGImage?, rig: StoreRig) -> (CGImage, CGRect, CGFloat)? {
        let layout = rig.layout
        let b = StoreRig.bezelPt, m = StoreRig.marginPt, c = rig.c
        let rect = layout.rect(lateral: (-b - m)...(layout.lateralLength + b + m), depth: (-c)...c)
        let band = layout.creaseRect
        guard rect.width > 1, rect.height > 1 else { return nil }
        var scale: CGFloat = 3
        if let image, band.height > 1, band.width > 1 {
            scale = min(max(CGFloat(image.width) / band.width, 1), 3)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        format.preferredRange = .standard
        let bezelBand = layout.rect(lateral: (-b)...(layout.lateralLength + b), depth: (-c)...c)
        let texture = UIGraphicsImageRenderer(size: rect.size, format: format).image { renderer in
            let cg = renderer.cgContext
            cg.translateBy(x: -rect.minX, y: -rect.minY)
            cg.setFillColor(bezelColor.cgColor)
            cg.fill(bezelBand)
            if let image {
                UIImage(cgImage: image).draw(in: band)
            } else {
                cg.setFillColor(creaseGraphite.cgColor)
                cg.fill(band)
            }
        }
        guard let pixels = texture.cgImage else { return nil }
        return (pixels, rect, scale)
    }

    // MARK: - Drawing helpers

    /// Warp an image onto a quad (top-left, top-right, bottom-right, bottom-left in top-left-origin pixels of a canvas
    /// of `canvas` size). Returns the warped pixels and where to draw them (top-left-origin rect).
    private static func warp(_ image: CGImage, corners: [CGPoint], canvas: CGSize,
                             context: CIContext) -> (CGImage, CGRect)? {
        guard corners.count == 4 else { return nil }
        func ci(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: canvas.height - p.y) }   // Core Image is bottom-left
        let filter = CIFilter.perspectiveTransform()
        filter.inputImage = CIImage(cgImage: image)
        filter.topLeft = ci(corners[0])
        filter.topRight = ci(corners[1])
        filter.bottomRight = ci(corners[2])
        filter.bottomLeft = ci(corners[3])
        guard let output = filter.outputImage else { return nil }
        let extent = output.extent.intersection(CGRect(origin: .zero, size: canvas)).integral
        guard !extent.isNull, !extent.isInfinite, extent.width >= 1, extent.height >= 1,
              let pixels = context.createCGImage(output, from: extent, format: .RGBA8,
                                                 colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else { return nil }
        return (pixels, CGRect(x: extent.minX, y: canvas.height - extent.maxY, width: extent.width, height: extent.height))
    }

    /// A filled polygon, Gaussian-blurred, as a layer covering only the polygon's bounds plus 3σ (not the whole frame:
    /// a 2007 × 2853 RGBA layer is 23 MB, and a pair frame has six).
    private static func blurred(_ points: [CGPoint], color: UIColor, sigma: Double, size: CGSize,
                                context: CIContext) -> StoreDraw? {
        guard points.count >= 3 else { return nil }
        let sigma = max(sigma, 0.5)
        var minX = CGFloat.infinity, minY = CGFloat.infinity, maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        for p in points {
            minX = min(minX, p.x)
            minY = min(minY, p.y)
            maxX = max(maxX, p.x)
            maxY = max(maxY, p.y)
        }
        guard minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite else { return nil }
        let pad = CGFloat(3 * sigma + 2)
        let region = CGRect(x: minX - pad, y: minY - pad, width: maxX - minX + 2 * pad, height: maxY - minY + 2 * pad)
            .intersection(CGRect(origin: .zero, size: size)).integral
        guard !region.isNull, region.width >= 1, region.height >= 1 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        let layer = UIGraphicsImageRenderer(size: region.size, format: format).image { renderer in
            renderer.cgContext.translateBy(x: -region.minX, y: -region.minY)
            renderer.cgContext.addPath(path(points, closed: true))
            renderer.cgContext.setFillColor(color.cgColor)
            renderer.cgContext.fillPath()
        }
        guard let pixels = layer.cgImage else { return nil }
        let local = CGRect(origin: .zero, size: region.size)
        let soft = CIImage(cgImage: pixels).clampedToExtent()
            .applyingGaussianBlur(sigma: sigma)
            .cropped(to: local)
        guard let out = context.createCGImage(soft, from: local, format: .RGBA8,
                                              colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else { return nil }
        return .image(out, region)
    }

    /// Studio sweep (Theme wallBase → backdrop → floorNear, or the cooler Duo sweep), a light pool under the device and
    /// a soft vignette.
    private static func drawBackdrop(_ cg: CGContext, size: CGSize, pool: CGPoint, style: Backdrop) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)
        let sweep: [CGColor]
        let poolColors: [CGColor]
        switch style {
        case .studio:
            sweep = [UIColor(hex: 0xEDE5D8), UIColor(hex: 0xF3EEE6), UIColor(hex: 0xF1E9DC)].map(\.cgColor)
            poolColors = [UIColor(hex: 0xFBF8F1), UIColor(hex: 0xF8F3EA, alpha: 0)].map(\.cgColor)
        case .duoSweep:
            sweep = [UIColor(hex: 0xE9E6E1), UIColor(hex: 0xE2DED8), UIColor(hex: 0xD9D5CE)].map(\.cgColor)
            poolColors = [UIColor(hex: 0xF2EFEA), UIColor(hex: 0xEEEBE6, alpha: 0)].map(\.cgColor)
        }
        if let gradient = CGGradient(colorsSpace: space, colors: sweep as CFArray, locations: [0, 0.55, 1]) {
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
        if let gradient = CGGradient(colorsSpace: space, colors: poolColors as CFArray, locations: [0, 1]) {
            cg.drawRadialGradient(gradient, startCenter: pool, startRadius: 0, endCenter: pool,
                                  endRadius: max(size.width, size.height) * 0.5, options: [])
        }
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let vignette = [UIColor(hex: 0x3B2F25, alpha: 0), UIColor(hex: 0x3B2F25, alpha: 0.08)].map(\.cgColor)
        if let gradient = CGGradient(colorsSpace: space, colors: vignette as CFArray, locations: [0.55, 1]) {
            cg.drawRadialGradient(gradient, startCenter: centre, startRadius: 0, endCenter: centre,
                                  endRadius: hypot(size.width, size.height) / 2, options: [.drawsAfterEndLocation])
        }
    }

    private static func shaded(_ base: SIMD3<Double>, normal: SIMD3<Double>, light: SIMD3<Double>) -> UIColor {
        let k = 0.45 + 0.75 * max(0, simd_dot(normal, light))
        let c = simd_min(base * k, SIMD3<Double>(repeating: 1))
        return UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
    }

    private static func path(_ points: [CGPoint], closed: Bool) -> CGPath {
        let shape = CGMutablePath()
        guard let first = points.first else { return shape }
        shape.move(to: first)
        for point in points.dropFirst() { shape.addLine(to: point) }
        if closed { shape.closeSubpath() }
        return shape
    }

    /// Top-left, top-right, bottom-right, bottom-left (top-left-origin), matching `warp`.
    private static func corners(of rect: CGRect) -> [CGPoint] {
        [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
         CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
    }

    /// Convex hull (monotone chain).
    private static func hull(_ points: [CGPoint]) -> [CGPoint] {
        let sorted = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        guard sorted.count >= 3 else { return sorted }
        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        var lower: [CGPoint] = []
        for p in sorted {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 { lower.removeLast() }
            lower.append(p)
        }
        var upper: [CGPoint] = []
        for p in sorted.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 { upper.removeLast() }
            upper.append(p)
        }
        lower.removeLast()
        upper.removeLast()
        return lower + upper
    }
}

// MARK: - Model

private enum StoreDraw {
    /// A polygon in output pixels; `seal` strokes it in its own colour to hide seams between neighbours.
    case fill([CGPoint], UIColor, Bool)
    case image(CGImage, CGRect)
}

/// One device's draw list, the floor point under its centre (for the backdrop's light pool) and its projected bounds.
private struct StoreDevice {
    let draws: [StoreDraw]
    let pool: CGPoint
    let frame: CGRect
    /// The lid's (platen page's) two free corners in output pixels, lateral start first.
    let lidCorners: [CGPoint]
}

/// The hero's angle mark (FOLD-REVIEW-6 #1 b): the readout label and the profile glyph at the modelled angle.
private struct HeroMark {
    let label: String
    let angle: Double
    let lid: [CGPoint]
    /// Keep the mark under the caption band.
    let captioned: Bool
}

private struct PairMarks {
    let before: CGRect
    let after: CGRect
    let beforeLabel: String
    let afterLabel: String
    /// Modelled hinge angles (degrees) for the side-profile glyphs.
    let beforeAngle: Double
    let afterAngle: Double
    let labels: Bool
}

private struct StorePage {
    let panel: StoreRig.Panel
    let slab: StoreRig.PageSlab
    let image: CGImage
}

/// The folded device in millimetres. Cross-section coordinates (u, v): the anvil page lies along +u from its crease
/// edge at the origin with its screen facing +v; the bend leaves along −u and turns by π − θ into the platen page.
/// World = origin + u·U + v·V + x·lateral, where x is the anvil-frame x of the canvas lateral coordinate.
private struct StoreRig {
    enum Panel { case platen, anvil }

    struct Face {
        var points: [SIMD3<Double>]
        /// Outward (away from the solid it bounds).
        var normal: SIMD3<Double>
        var centroid: SIMD3<Double>
    }

    struct PageSlab {
        var faces: [Face]
        var points: [SIMD3<Double>]
        var frontCentroid: SIMD3<Double>
    }

    struct Hinge {
        var body: [Face]
        /// The screen side of each bend segment (anvil edge first).
        var inner: [Face]
        var points: [SIMD3<Double>]
    }

    /// Black glass border round the inner display, pt (≈ 2.3 mm).
    static let bezelPt: Double = 14
    static let screenRadiusPt: Double = 30
    static let bodyRadiusPt: Double = 44
    /// Transparent margin round each texture, so warped edges antialias.
    static let marginPt: Double = 6
    /// One half of the device body (the folded Duo is two of these).
    static let thicknessMM: Double = 4.6
    static let bendSegments = 10

    let layout: FoldLayout
    /// Laptop pose (the world is the anvil frame). False only for a book layout modelled as a standing book.
    let tabletop: Bool
    let theta: Double
    let origin: SIMD3<Double>
    let u: SIMD3<Double>
    let v: SIMD3<Double>
    let lateral: SIMD3<Double>
    /// Anvil-frame z of the anvil page's crease edge (the axis is at z = −40 mm, FoldGeometry.swift).
    let anvilCreaseZ: Double
    /// Bend nodes (u, v), anvil crease edge → platen crease edge, and the screen-side normal at each node.
    let arc: [SIMD2<Double>]
    let arcNormals: [SIMD2<Double>]

    var ppm: Double { FoldMetrics.pointsPerMM }
    var c: Double { FoldMetrics.creaseHalf }

    init(layout: FoldLayout, angleDegrees: Double, tabletop: Bool) {
        self.layout = layout
        self.tabletop = tabletop
        let angle = clamp(angleDegrees, 30, 180) * Double.pi / 180
        theta = angle
        let creaseZ = FoldMetrics.creaseHalf / FoldMetrics.pointsPerMM - FoldMetrics.footprintFromAxisMM
        anvilCreaseZ = creaseZ
        if tabletop {
            // The world IS the anvil frame (anvil on the table, platen as the lid behind it). For a book layout this
            // lays the page down turned 90° clockwise: canvas +x (away from the crease) → world +z (toward the viewer),
            // canvas +y → world −x, so the page's top edge points to the viewer's right.
            u = SIMD3(0, 0, 1)
            v = SIMD3(0, 1, 0)
            lateral = SIMD3(1, 0, 0)
            origin = SIMD3(0, 0, creaseZ)
        } else {
            // Standing on its lower edge, the wedge bisector toward the viewer (+z), anvil page on the right.
            let rho = Double.pi / 2 - angle / 2
            u = SIMD3(cos(rho), 0, sin(rho))
            v = SIMD3(-sin(rho), 0, cos(rho))
            lateral = SIMD3(0, 1, 0)
            origin = SIMD3(0, 0, 0)
        }
        let n = StoreRig.bendSegments
        let length = 2 * FoldMetrics.creaseHalf / FoldMetrics.pointsPerMM
        let phi = Double.pi - angle
        var points = [SIMD2<Double>(0, 0)]
        var normals = [SIMD2<Double>(0, 1)]
        var p = SIMD2<Double>(0, 0)
        for k in 0..<n {
            let heading = Double.pi - phi * (Double(k) + 0.5) / Double(n)
            p += (length / Double(n)) * SIMD2<Double>(cos(heading), sin(heading))
            points.append(p)
            let end = Double.pi - phi * Double(k + 1) / Double(n)
            normals.append(SIMD2<Double>(sin(end), -cos(end)))
        }
        arc = points
        arcNormals = normals
    }

    // MARK: Frames

    func world(_ cs: SIMD2<Double>, x: Double) -> SIMD3<Double> {
        origin + cs.x * u + cs.y * v + x * lateral
    }

    func direction(_ cs: SIMD2<Double>) -> SIMD3<Double> { cs.x * u + cs.y * v }

    /// Anvil-frame x (mm) of a canvas lateral coordinate (FoldLayout.anvilMM).
    func lateralMM(_ l: Double) -> Double {
        layout.isBook ? (layout.lateralCentre - l) / ppm : (l - layout.lateralCentre) / ppm
    }

    func anvilFrameToWorld(_ p: SIMD3<Double>) -> SIMD3<Double> {
        origin + (p.z - anvilCreaseZ) * u + p.y * v + p.x * lateral
    }

    private func creaseEdge(_ panel: Panel) -> SIMD2<Double> {
        panel == .anvil ? SIMD2<Double>(0, 0) : arc[arc.count - 1]
    }

    private func away(_ panel: Panel) -> SIMD2<Double> {
        panel == .anvil ? SIMD2<Double>(1, 0) : SIMD2<Double>(cos(theta), sin(theta))
    }

    private func sign(_ panel: Panel) -> Double { panel == .anvil ? 1 : -1 }

    /// The screen's facing direction (into the wedge).
    func normal(_ panel: Panel) -> SIMD3<Double> {
        direction(panel == .anvil ? SIMD2<Double>(0, 1) : SIMD2<Double>(sin(theta), -cos(theta)))
    }

    /// The lid's shadow on the anvil page under a light straight above (tabletop: the anvil page is horizontal, so
    /// "above" is +v): how far from the anvil's crease edge the shadow of the lid's free edge (bezel included) falls
    /// and how high that edge is, mm. Nil when the shadow falls behind the crease (overhead key: θ ≥ ~90°).
    /// `keyTiltDegrees` leans the light toward the viewer (+u): the shadow reach grows by height × tan(tilt).
    func lidShadowOnAnvil(keyTiltDegrees: Double = 0) -> (reachMM: Double, heightMM: Double)? {
        guard tabletop, let crease = arc.last else { return nil }
        let length = (reach(.platen) + StoreRig.bezelPt) / ppm
        let free = crease + length * away(.platen)
        guard free.y > 0 else { return nil }
        let reachMM = free.x + free.y * tan(clamp(keyTiltDegrees, 0, 60) * Double.pi / 180)
        guard reachMM > 0.5 else { return nil }
        return (reachMM: reachMM, heightMM: free.y)
    }

    /// Crease edge → free edge, pt.
    func reach(_ panel: Panel) -> Double { (panel == .anvil ? layout.anvilReach : layout.platenReach) - c }

    func half(_ panel: Panel) -> CGRect { panel == .anvil ? layout.anvilHalf : layout.platenHalf }

    /// A canvas point on (or past the edges of) one page, on that page's plane.
    func world(canvas p: CGPoint, on panel: Panel) -> SIMD3<Double> {
        let f = layout.foldCoordinates(of: p)
        let a = (sign(panel) * f.depth - c) / ppm
        return world(creaseEdge(panel) + a * away(panel), x: lateralMM(f.lateral))
    }

    /// A canvas point in the crease band, on the bend (snapped to the nearest bend node across the band).
    func bendWorld(canvas p: CGPoint) -> SIMD3<Double> {
        let f = layout.foldCoordinates(of: p)
        let n = StoreRig.bendSegments
        let k = clamp(Int(((c - f.depth) / (2 * c) * Double(n)).rounded()), 0, n)
        return world(arc[k], x: lateralMM(f.lateral))
    }

    /// Canvas rect of bend slice k (anvil side first), across the whole crease texture width.
    func creaseSliceRect(_ k: Int) -> CGRect {
        let n = Double(StoreRig.bendSegments)
        let dHi = c - 2 * c * Double(k) / n
        let dLo = c - 2 * c * Double(k + 1) / n
        let b = StoreRig.bezelPt, m = StoreRig.marginPt
        return layout.rect(lateral: (-b - m)...(layout.lateralLength + b + m), depth: dLo...dHi)
    }

    func canvas(a: Double, l: Double, on panel: Panel) -> CGPoint {
        layout.point(lateral: l, depth: sign(panel) * (c + a))
    }

    /// Open outline of a page in canvas points, from the crease edge round the free edge and back to the crease edge
    /// (`expand` pt outside the screen on the free and lateral sides, free corners rounded).
    func outline(_ panel: Panel, expand e: Double, radius: Double, arcSteps: Int = 8) -> [CGPoint] {
        let top = reach(panel) + e
        let l0 = -e, l1 = layout.lateralLength + e
        let r = max(0, min(radius, top, (l1 - l0) / 2))
        var pts: [SIMD2<Double>] = [SIMD2(0, l0), SIMD2(top - r, l0)]
        for i in 1...arcSteps {
            let t = -Double.pi / 2 + Double.pi / 2 * Double(i) / Double(arcSteps)
            pts.append(SIMD2(top - r + r * cos(t), l0 + r + r * sin(t)))
        }
        pts.append(SIMD2(top, l1 - r))
        for i in 1...arcSteps {
            let t = Double.pi / 2 * Double(i) / Double(arcSteps)
            pts.append(SIMD2(top - r + r * cos(t), l1 - r + r * sin(t)))
        }
        pts.append(SIMD2(0, l1))
        return pts.map { canvas(a: $0.x, l: $0.y, on: panel) }
    }

    // MARK: Solids

    static func face(_ points: [SIMD3<Double>], solidCentre: SIMD3<Double>) -> Face? {
        guard points.count >= 3 else { return nil }
        let centroid = points.reduce(SIMD3<Double>(repeating: 0), +) / Double(points.count)
        var n = SIMD3<Double>(repeating: 0)   // Newell's normal: robust to slightly non-planar quads
        for i in 0..<points.count {
            let a = points[i], b = points[(i + 1) % points.count]
            n.x += (a.y - b.y) * (a.z + b.z)
            n.y += (a.z - b.z) * (a.x + b.x)
            n.z += (a.x - b.x) * (a.y + b.y)
        }
        let length = simd_length(n)
        guard length > 1e-9 else { return nil }
        n /= length
        if simd_dot(n, centroid - solidCentre) < 0 { n = -n }
        return Face(points: points, normal: n, centroid: centroid)
    }

    /// The page body: screen-plane outline extruded backward by the thickness (convex, so culling is enough).
    func slab(_ panel: Panel) -> PageSlab {
        let outlineCanvas = outline(panel, expand: StoreRig.bezelPt, radius: StoreRig.bodyRadiusPt)
        let n = normal(panel)
        let front = outlineCanvas.map { world(canvas: $0, on: panel) }
        let back = front.map { $0 - StoreRig.thicknessMM * n }
        let all = front + back
        let centre = all.reduce(SIMD3<Double>(repeating: 0), +) / Double(max(all.count, 1))
        var faces: [Face] = []
        if front.count >= 2 {
            for i in 0..<(front.count - 1) {
                if let side = StoreRig.face([front[i], front[i + 1], back[i + 1], back[i]], solidCentre: centre) {
                    faces.append(side)
                }
            }
        }
        if let rear = StoreRig.face(back, solidCentre: centre) { faces.append(rear) }
        let frontCentroid = front.reduce(SIMD3<Double>(repeating: 0), +) / Double(max(front.count, 1))
        return PageSlab(faces: faces, points: all, frontCentroid: frontCentroid)
    }

    /// The hinge: the bend's thickness as a short barrel (outer skin + end caps per segment) and its screen side.
    func hinge() -> Hinge {
        let b = StoreRig.bezelPt
        let x0 = lateralMM(-b), x1 = lateralMM(layout.lateralLength + b)
        let t = StoreRig.thicknessMM
        var body: [Face] = [], inner: [Face] = [], points: [SIMD3<Double>] = []
        for k in 0..<StoreRig.bendSegments {
            let i0 = arc[k], i1 = arc[k + 1]
            let o0 = i0 - t * arcNormals[k], o1 = i1 - t * arcNormals[k + 1]
            let ia0 = world(i0, x: x0), ia1 = world(i1, x: x0), ib0 = world(i0, x: x1), ib1 = world(i1, x: x1)
            let oa0 = world(o0, x: x0), oa1 = world(o1, x: x0), ob0 = world(o0, x: x1), ob1 = world(o1, x: x1)
            let segment = [ia0, ia1, ib0, ib1, oa0, oa1, ob0, ob1]
            points += segment
            let centre = segment.reduce(SIMD3<Double>(repeating: 0), +) / Double(segment.count)
            for quad in [[oa0, oa1, ob1, ob0], [ia0, ia1, oa1, oa0], [ib0, ib1, ob1, ob0]] {
                if let f = StoreRig.face(quad, solidCentre: centre) { body.append(f) }
            }
            if let f = StoreRig.face([ia0, ia1, ib1, ib0], solidCentre: centre) {
                inner.append(f)
            }
        }
        return Hinge(body: body, inner: inner, points: points)
    }

    // MARK: Eye

    /// The content's design eye (§9.4) moved into the world; for the 3/4 view re-aimed (elevation above the anvil page,
    /// from the footprint centre) and then turned about the vertical through the device.
    ///
    /// The anvil's 3D content was rendered for the design eye of the *layout's* pose, at the *captured* angle
    /// (`contentAngle`), so that is where the object stands up: tabletop 40° straight in front; book on the wedge
    /// bisector tilted toward the page top, i.e. (anvil frame) azimuth ≈ +17° / elevation 31° at 62°, +39° / 53° at 112°.
    func eye(model: FoldEyeModel, contentAngle: Double, threeQuarter: Bool, azimuthDegrees: Double?,
             elevationDegrees: Double?, target: SIMD3<Double>) -> SIMD3<Double> {
        let pose: FoldPose = layout.isBook ? .book(hinge: clamp(contentAngle, 20, 180)) : .tabletop
        var eyeModel = model
        if threeQuarter, !layout.isBook {
            eyeModel.elevationDegrees = elevationDegrees ?? 34   // FOLD-REVIEW-4 §3.3 B: design 40°, store 34°
        }
        var anvilEye = eyeModel.designEye(pose)
        if threeQuarter, layout.isBook {
            let distance = max(simd_length(anvilEye), 1)
            let designElevation = asin(clamp(anvilEye.y / distance, -1, 1)) * 180 / Double.pi
            let wanted = elevationDegrees ?? (tabletop ? clamp(designElevation, 34, 60) : designElevation)
            let e = clamp(wanted, 5, 85) * Double.pi / 180
            let a = atan2(anvilEye.x, anvilEye.z)
            anvilEye = distance * SIMD3(cos(e) * sin(a), sin(e), cos(e) * cos(a))
        }
        let design = anvilFrameToWorld(anvilEye)
        guard threeQuarter else { return design }
        let turn: Double
        if !layout.isBook {
            turn = azimuthDegrees ?? 14
        } else if tabletop {
            turn = azimuthDegrees ?? 0
        } else {
            turn = azimuthDegrees ?? -22
        }
        let azimuth = turn * Double.pi / 180
        let rel = design - target
        return target + SIMD3(rel.x * cos(azimuth) + rel.z * sin(azimuth), rel.y,
                              -rel.x * sin(azimuth) + rel.z * cos(azimuth))
    }
}

/// A pinhole camera at the eye looking at the device centre, world up = +y.
private struct StoreCamera {
    let eye: SIMD3<Double>
    let forward: SIMD3<Double>
    let right: SIMD3<Double>
    let up: SIMD3<Double>

    init(eye: SIMD3<Double>, target: SIMD3<Double>) {
        self.eye = eye
        let f = simd_normalize(target - eye)
        var r = simd_cross(f, SIMD3<Double>(0, 1, 0))
        if simd_length(r) < 1e-6 { r = SIMD3<Double>(1, 0, 0) }
        r = simd_normalize(r)
        forward = f
        right = r
        up = simd_cross(r, f)
    }

    /// Image-plane coordinates (x right, y up), unit focal length.
    func project(_ p: SIMD3<Double>) -> SIMD2<Double> {
        let d = p - eye
        let z = max(simd_dot(d, forward), 1e-3)
        return SIMD2<Double>(simd_dot(d, right) / z, simd_dot(d, up) / z)
    }
}

/// Image plane → output pixels (top-left origin): the image-plane point `reference` lands on `pixel`.
private struct StoreFit {
    let scale: Double
    let reference: SIMD2<Double>
    let pixel: CGPoint

    func point(_ q: SIMD2<Double>) -> CGPoint {
        CGPoint(x: Double(pixel.x) + (q.x - reference.x) * scale, y: Double(pixel.y) - (q.y - reference.y) * scale)
    }
}

// MARK: - Caption line breaks

/// Caption line breaking for the store frames (FOLD-REVIEW-6 N11). The same rule is in ci/store-frame.swift (the
/// host-side compositor for raw frames); keep the two in step.
///  • A headline too wide for one line breaks at the sentence boundary ("`. `") that balances the two parts best:
///    "No ads. No purchases. / Just the press.", not "No ads. / No purchases. Just the / press.".
///  • Every paragraph that still wraps is balanced: as many lines as a greedy wrap needs, at the narrowest width that
///    keeps that count, so lines come out even and none ends on one orphaned word ("… every / iPhone.").
///  • A sub-line shrinks (to `sublineMinimumScale` of the headline size at the least) to stay on one line; only past
///    that does it wrap, balanced, at its natural size.
/// `*` highlight markers stay in place and are never measured. `measure` is the one-line width of a plain string.
enum CaptionWrap {
    /// Sub-line size as a fraction of the headline size (screenshots.md: SF Mono at 40 %), and its shrink floor.
    static let sublineScale: CGFloat = 0.40
    static let sublineMinimumScale: CGFloat = 0.30
    /// Slack for the layout engine's own kerning and rounding, so a measured line never re-wraps when drawn.
    static let slack: CGFloat = 0.97

    /// `text` with "\n" inserted at the chosen breaks.
    static func balanced(_ text: String, width: CGFloat, sentenceBreak: Bool, measure: (String) -> CGFloat) -> String {
        joined(balancedLines(text, width: width, sentenceBreak: sentenceBreak, measure: measure))
    }

    /// The chosen lines, per paragraph (a paragraph is a sentence part or an explicit "\n" in `text`).
    static func balancedLines(_ text: String, width: CGFloat, sentenceBreak: Bool,
                              measure: (String) -> CGFloat) -> [[String]] {
        let fit = width * slack
        func plainWidth(_ s: String) -> CGFloat { measure(s.replacingOccurrences(of: "*", with: "")) }
        var source = text
        if sentenceBreak, !source.contains("\n"), plainWidth(source) > fit,
           let split = splitAtBestSentence(source, measure: plainWidth) {
            source = split
        }
        return source.components(separatedBy: "\n").map { balancedParagraph($0, width: fit, measure: plainWidth) }
    }

    static func joined(_ paragraphs: [[String]]) -> String {
        paragraphs.map { $0.joined(separator: "\n") }.joined(separator: "\n")
    }

    /// True when a wrapped paragraph's last line is a single word (the renderers shrink a step and try again).
    static func hasOrphan(_ paragraphs: [[String]]) -> Bool {
        paragraphs.contains { lines in lines.count > 1 && !(lines.last ?? " ").contains(" ") }
    }

    /// The sub-line point size that keeps it on one line, between the shrink floor and its natural size; nil when
    /// even the floor is too wide (then it wraps at `natural`). Monospaced widths scale linearly with the size.
    static func oneLineSublineSize(natural: CGFloat, naturalWidth: CGFloat, width: CGFloat) -> CGFloat? {
        let fit = width * slack
        guard naturalWidth > fit else { return natural }
        let floorSize = natural * sublineMinimumScale / sublineScale
        let wanted = natural * fit / max(naturalWidth, 1)
        return wanted >= floorSize ? wanted : nil
    }

    static func splitAtBestSentence(_ text: String, measure: (String) -> CGFloat) -> String? {
        var best: (score: CGFloat, result: String)?
        var search = text.startIndex..<text.endIndex
        while let range = text.range(of: ". ", range: search) {
            let left = String(text[..<range.lowerBound]) + "."
            let right = String(text[range.upperBound...])
            let score = max(measure(left), measure(right))
            if best.map({ score < $0.score }) ?? true { best = (score: score, result: left + "\n" + right) }
            search = range.upperBound..<text.endIndex
        }
        return best?.result
    }

    /// One paragraph's lines.
    static func balancedParagraph(_ paragraph: String, width: CGFloat, measure: (String) -> CGFloat) -> [String] {
        let words = paragraph.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard words.count > 1, measure(paragraph) > width else { return [paragraph] }
        func greedy(_ limit: CGFloat) -> [[String]] {
            var lines: [[String]] = []
            var current: [String] = []
            for word in words {
                if current.isEmpty || measure((current + [word]).joined(separator: " ")) <= limit {
                    current.append(word)
                } else {
                    lines.append(current)
                    current = [word]
                }
            }
            if !current.isEmpty { lines.append(current) }
            return lines
        }
        let count = greedy(width).count
        var lo: CGFloat = 0
        var hi = width
        for _ in 0..<20 {
            let mid = (lo + hi) / 2
            if greedy(mid).count <= count { hi = mid } else { lo = mid }
        }
        var lines = greedy(hi)
        // One long word can still leave a lone last word: pull one more word down if the line still fits.
        let n = lines.count
        if n >= 2, lines[n - 1].count == 1, lines[n - 2].count >= 3, let moved = lines[n - 2].last {
            let candidate = [moved] + lines[n - 1]
            if measure(candidate.joined(separator: " ")) <= width {
                lines[n - 2].removeLast()
                lines[n - 1] = candidate
            }
        }
        return lines.map { $0.joined(separator: " ") }
    }
}
