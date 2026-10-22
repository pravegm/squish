import CoreImage
import CoreImage.CIFilterBuiltins
import RealityKit
import simd
import UIKit

/// The store shot (FOLD-REVIEW-3 N1, FOLD-PRESS §9.6 "eye-view composite"): the live Fold Press stage mapped onto a
/// folded, Duo-shaped device and seen from a 3/4 eye, because raw inner-display frames are anamorphic and read as two
/// flat trays.
///
///     capture(scene:fold:)   live stage → platen page, crease band, anvil page (canvas orientation, @screen scale)
///     render(_:options:)     → a 1320 × 2868 (or 2868 × 1320) opaque PNG-ready image
///
/// The model: the inner display is one panel bent round a thin hinge cylinder (the 40 pt crease band becomes the bend),
/// each page a rounded slab with a black glass bezel, on a warm studio sweep with a cast and a contact shadow.
/// Tabletop layouts (horizontal fold) stand like a laptop, the anvil on the table and the platen as the lid; book
/// layouts (vertical fold) stand on their lower edge like an open book. Geometry is in millimetres in the anvil frame
/// of FoldGeometry.swift (tabletop) or a book frame with the wedge bisector toward the viewer.
///
/// Rendering is 2D and deterministic: each screen is drawn flat (content, bezel, rounded free corners, glass sheen),
/// then warped onto its 4 projected corners with `CIPerspectiveTransform` (a plane under a pinhole camera is exactly
/// a homography); the bend is 10 warped strips; bodies are lambert-shaded polygons drawn back to front.
/// `layer.render(in:)` is never used for anything with a 3D transform.
@MainActor
enum FoldStoreShot {
    /// App Store 6.9" portrait (1320 × 2868) and the landscape option.
    nonisolated static let portrait = CGSize(width: 1320, height: 2868)
    nonisolated static let landscape = CGSize(width: 2868, height: 1320)

    enum Eye: String, Sendable {
        /// The design eye (§9.4) turned ~25° about the vertical: the marketing view.
        case threeQuarter
        /// Exactly the design eye the anvil was rendered for (tabletop 40°/380 mm, book bisector): for CI E1/E2 checks.
        case design
    }

    struct Options {
        var size = CGSize(width: 1320, height: 2868)
        /// Fold angle of the device model (180 = flat). Store art uses 110–120°; CI passes the captured hinge angle.
        var hingeAngle: Double = 115
        var eye: Eye = .threeQuarter
        /// Turn of the 3/4 eye about the vertical through the device, degrees (+ = toward world +x). Nil = pose default
        /// (tabletop +26°, book −22°, i.e. toward the platen so the anvil page is seen face on).
        var azimuthDegrees: Double?
        var eyeModel: FoldEyeModel = .standard
        /// A faint diagonal reflection on both screens. Off for measurement shots.
        var glassSheen = true
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
    }

    // MARK: - Capture

    /// Snapshot the Fold Press stage as it is on screen now (platen layers, warped anvil ARView, bezel; none of the
    /// SwiftUI overlays above it) and split it at the crease. Nil when no Fold Press stage is on screen.
    static func capture(scene: PressScene, fold: FoldPressController) async -> Halves? {
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
        var full = UIGraphicsImageRenderer(bounds: host.bounds, format: format).image { _ in
            _ = host.drawHierarchy(in: host.bounds, afterScreenUpdates: false)
        }

        // drawHierarchy normally includes the ARView's Metal layer; if it doesn't here (the ARView alone comes out
        // flat), rebuild the anvil half from the ARView's own snapshot, warped exactly as on screen.
        var source = "drawHierarchy"
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

    static func render(_ halves: Halves, options: Options = Options()) -> UIImage? {
        let size = options.size
        guard size.width >= 64, size.height >= 64 else { return nil }
        let rig = StoreRig(layout: halves.layout, angleDegrees: options.hingeAngle)
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
        let eye = rig.eye(model: options.eyeModel, threeQuarter: options.eye == .threeQuarter,
                          azimuthDegrees: options.azimuthDegrees, target: target)
        let camera = StoreCamera(eye: eye, target: target)

        // Fit the projected device into the hero box: portrait leaves the top ~30% for the caption band
        // (docs/appstore/screenshots.md), landscape centres it.
        let box: CGRect = size.height >= size.width
            ? CGRect(x: size.width * 0.07, y: size.height * 0.32, width: size.width * 0.86, height: size.height * 0.56)
            : CGRect(x: size.width * 0.17, y: size.height * 0.10, width: size.width * 0.66, height: size.height * 0.80)
        var qlo = SIMD2<Double>(repeating: .infinity)
        var qhi = SIMD2<Double>(repeating: -.infinity)
        for p in devicePoints {
            let q = camera.project(p)
            qlo = simd_min(qlo, q)
            qhi = simd_max(qhi, q)
        }
        let span = simd_max(qhi - qlo, SIMD2<Double>(repeating: 1e-6))
        let scale = min(Double(box.width) / span.x, Double(box.height) / span.y)
        let fit = StoreFit(scale: scale, centre: (qlo + qhi) / 2, box: box)
        func px(_ p: SIMD3<Double>) -> CGPoint { fit.point(camera.project(p)) }
        let devicePixels = span.x * scale

        let context = CIContext(options: [.cacheIntermediates: false])
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
            guard simd_dot(normal, eye - page.slab.frontCentroid) > 0,
                  case let (texture, textureRect)? = pageTexture(page.panel, image: page.image, rig: rig,
                                                                 sheen: options.glassSheen) else { continue }
            let quad = corners(of: textureRect).map { px(rig.world(canvas: $0, on: page.panel)) }
            if case let (image, rect)? = warp(texture, corners: quad, canvas: size, context: context) {
                draws.append(StoreDraw.image(image, rect))
            }
        }

        // 4. Flatten onto the studio sweep. Opaque, sRGB, 8-bit: App Store screenshots must have no alpha.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let pool = px(SIMD3(target.x, ground, target.z))
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let cg = renderer.cgContext
            drawBackdrop(cg, size: size, pool: pool)
            cg.setLineJoin(.round)
            for draw in draws {
                switch draw {
                case let .fill(points, color, seal):
                    guard points.count >= 3 else { continue }
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
        }
    }

    // MARK: - Textures

    private static let bezelColor = UIColor(hex: 0x0D0E10)
    private static let rimColor = UIColor(hex: 0x7A7E86, alpha: 0.9)
    private static let creaseGraphite = UIColor(hex: 0x2B2D31)

    /// One page drawn flat in canvas points: black glass bezel with rounded free corners, the screen content clipped
    /// to its rounded corners, a faint sheen and the rim. The rect includes a transparent margin so warped edges
    /// stay antialiased.
    private static func pageTexture(_ panel: StoreRig.Panel, image: CGImage, rig: StoreRig,
                                    sheen: Bool) -> (CGImage, CGRect)? {
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
            if sheen, let gradient = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                colors: [UIColor(red: 1, green: 1, blue: 1, alpha: 0).cgColor,
                         UIColor(red: 1, green: 1, blue: 1, alpha: 0.07).cgColor,
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

    /// A filled polygon, Gaussian-blurred, as a full-canvas layer.
    private static func blurred(_ points: [CGPoint], color: UIColor, sigma: Double, size: CGSize,
                                context: CIContext) -> StoreDraw? {
        guard points.count >= 3 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        let layer = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            renderer.cgContext.addPath(path(points, closed: true))
            renderer.cgContext.setFillColor(color.cgColor)
            renderer.cgContext.fillPath()
        }
        guard let pixels = layer.cgImage else { return nil }
        let bounds = CGRect(origin: .zero, size: size)
        let soft = CIImage(cgImage: pixels).clampedToExtent()
            .applyingGaussianBlur(sigma: max(sigma, 0.5))
            .cropped(to: bounds)
        guard let out = context.createCGImage(soft, from: bounds, format: .RGBA8,
                                              colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else { return nil }
        return .image(out, bounds)
    }

    /// Warm studio sweep (Theme wallBase → backdrop → floorNear), a light pool under the device and a soft vignette.
    private static func drawBackdrop(_ cg: CGContext, size: CGSize, pool: CGPoint) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)
        let sweep = [UIColor(hex: 0xEDE5D8), UIColor(hex: 0xF3EEE6), UIColor(hex: 0xF1E9DC)].map(\.cgColor)
        if let gradient = CGGradient(colorsSpace: space, colors: sweep as CFArray, locations: [0, 0.55, 1]) {
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
        let light = [UIColor(hex: 0xFBF8F1), UIColor(hex: 0xF8F3EA, alpha: 0)].map(\.cgColor)
        if let gradient = CGGradient(colorsSpace: space, colors: light as CFArray, locations: [0, 1]) {
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

    init(layout: FoldLayout, angleDegrees: Double) {
        self.layout = layout
        let angle = clamp(angleDegrees, 30, 180) * Double.pi / 180
        theta = angle
        let creaseZ = FoldMetrics.creaseHalf / FoldMetrics.pointsPerMM - FoldMetrics.footprintFromAxisMM
        anvilCreaseZ = creaseZ
        if layout.isBook {
            // Standing on its lower edge, the wedge bisector toward the viewer (+z), anvil page on the right.
            let rho = Double.pi / 2 - angle / 2
            u = SIMD3(cos(rho), 0, sin(rho))
            v = SIMD3(-sin(rho), 0, cos(rho))
            lateral = SIMD3(0, 1, 0)
            origin = SIMD3(0, 0, 0)
        } else {
            // Tabletop: the world IS the anvil frame (anvil on the table, platen as the lid behind it).
            u = SIMD3(0, 0, 1)
            v = SIMD3(0, 1, 0)
            lateral = SIMD3(1, 0, 0)
            origin = SIMD3(0, 0, creaseZ)
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

    /// The design eye (§9.4) for this pose and angle, moved into the world; for the 3/4 view turned about the
    /// vertical through the device.
    func eye(model: FoldEyeModel, threeQuarter: Bool, azimuthDegrees: Double?,
             target: SIMD3<Double>) -> SIMD3<Double> {
        let degrees = theta * 180 / Double.pi
        let pose: FoldPose = layout.isBook ? .book(hinge: degrees) : .tabletop
        let design = anvilFrameToWorld(model.designEye(pose))
        guard threeQuarter else { return design }
        let azimuth = (azimuthDegrees ?? (layout.isBook ? -22 : 26)) * Double.pi / 180
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

/// Image plane → output pixels (top-left origin), fitted into the hero box.
private struct StoreFit {
    let scale: Double
    let centre: SIMD2<Double>
    let box: CGRect

    func point(_ q: SIMD2<Double>) -> CGPoint {
        CGPoint(x: Double(box.midX) + (q.x - centre.x) * scale, y: Double(box.midY) - (q.y - centre.y) * scale)
    }
}
