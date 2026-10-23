import simd
import SwiftUI

/// The App Store icon (FOLD-REVIEW-3 N17, FOLD-REVIEW-4 F11): the phone *is* the press. A graphite foldable, seen
/// 3/4 from the front and above, bites down at ~24° on a yellow rubber duck (FOLD-REVIEW-5 N8: the old magenta jelly
/// read as a tongue). The duck's body is flattened into a lobed splat between the halves, its squashed head flops out
/// over the front edge with one big eye and the orange beak poking out, and yellow drips run off the edge. The head,
/// eye and beak are sized to survive at 40 px. The hazard jaws (FOLD-PRESS §5) run along both free edges. It replaces
/// the P-48 ram, the category's stock "hydraulic press" look, so the icon itself says "fold your phone".
///
/// The slab is deliberately generic (one lens, no Apple camera layout, no Dynamic Island): HIG asks icons not to
/// replicate Apple hardware. The clamshell is drawn with a tiny pinhole camera (`IconCamera`), so every face, jaw
/// and drip is a projected 3D polygon and stays consistent if the angles are tuned.
///
/// Pure vector (paths, gradients, blurs; no images, no symbols), drawn in a 1024-unit design space and scaled to
/// any square. Full-bleed, opaque and square-cornered, because the system applies the icon mask and glass.
/// CI renders it with `-squishDemo icon` (ci/scenarios.txt `85-icon`) and ci/screenshots.sh crops it to 1024².
struct AppIconArt: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            AppIconCanvas()
                .frame(width: side, height: side)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

private struct AppIconCanvas: View {
    var body: some View {
        Canvas(opaque: true, rendersAsynchronously: false) { context, size in
            AppIconPainter(side: min(size.width, size.height)).paint(context)
        }
    }
}

/// A pinhole camera looking at `target` from `azimuth` (about +y, from +z) and `elevation` degrees.
/// World: x along the hinge, y up (the base half's glass normal), z toward the viewer (the base's free edge).
private struct IconCamera {
    let position: SIMD3<Double>
    let right: SIMD3<Double>
    let up: SIMD3<Double>
    let forward: SIMD3<Double>

    init(azimuth: Double, elevation: Double, distance: Double, target: SIMD3<Double>) {
        let a = azimuth * .pi / 180
        let e = elevation * .pi / 180
        let toEye = SIMD3<Double>(sin(a) * cos(e), sin(e), cos(a) * cos(e))
        let eye = target + toEye * distance
        let ahead = simd_normalize(target - eye)
        let side = simd_normalize(simd_cross(ahead, SIMD3<Double>(0, 1, 0)))
        position = eye
        forward = ahead
        right = side
        up = simd_cross(side, ahead)
    }

    /// Image-plane coordinates (y up), before fitting.
    func project(_ p: SIMD3<Double>) -> SIMD2<Double> {
        let q = p - position
        let z = max(simd_dot(q, forward), 1e-6)
        return SIMD2<Double>(simd_dot(q, right) / z, simd_dot(q, up) / z)
    }
}

/// Draws the icon. 2D coordinates are 1024 design units (`pt` converts to points); 3D coordinates are the device's
/// own units (one inner-display point per unit), placed on the base half (`base`) or the lid half (`lid`).
private struct AppIconPainter {
    let s: CGFloat
    private let camera: IconCamera
    private let fitMinX: Double
    private let fitMidY: Double
    private let fitScale: Double

    // MARK: - Device (a Duo half is 669 × 475 pt in tabletop; the thickness is exaggerated so the edges read)

    private static let width = 669.0
    private static let depth = 475.0
    private static let thickness = 30.0
    private static let corner = 44.0
    private static let bezel = 14.0
    private static let jaw = 40.0
    /// Degrees between the halves: shut enough to be squeezing, open enough to see into the mouth.
    private static let opening = 24.0
    /// The duck's centre, measured from the hinge across the base (toward the mouth, so it bulges out of it).
    private static let footprint = 300.0
    /// The squashed head's centre on the base: just past the free edge, flopped over it (x, along, h).
    private static let headCentre = SIMD3<Double>(10, 505, 26)
    /// Head disc radius (design units), its squash (height / width) and tilt.
    private static let headRadius: CGFloat = 140
    private static let headSquash: CGFloat = 0.64
    private static let headTilt: CGFloat = -10
    /// Where the clamshell's projection lands in design units: its width spans fitX, centred on fitCentreY.
    private static let fitX: ClosedRange<Double> = 60...984
    private static let fitCentreY = 515.0

    private static let outline: [SIMD2<Double>] = roundedRect(x0: -width / 2, s0: 0, x1: width / 2, s1: depth, radius: corner)

    // MARK: - Palette (VISUAL-TARGET §6.2 plus the duck's vinyl, Palette.duckYellow / Palette.beakOrange)

    private static let yellow: UInt32 = 0xFFB81C
    private static let graphite: UInt32 = 0x2B2D31
    /// Lit lemon top to a deep ochre underside: lighter than the hazard yellow, so the duck never merges with the jaws.
    private static let duckRamp: [(UInt32, CGFloat, Double)] = [(0xFFF08A, 0, 1), (0xFFDC4A, 0.35, 1), (0xFFC81E, 0.7, 1), (0xD99A00, 1, 1)]
    private static let duckRim: UInt32 = 0xB07800
    private static let drip: UInt32 = 0xE0A200
    private static let beak: UInt32 = 0xFF8A1F
    private static let beakShade: UInt32 = 0xE0600A

    init(side: CGFloat) {
        s = side / 1024
        let camera = IconCamera(azimuth: 30, elevation: 44, distance: 1800, target: SIMD3<Double>(0, 120, 220))
        self.camera = camera
        var minX = Double.infinity, maxX = -Double.infinity, minY = Double.infinity, maxY = -Double.infinity
        for corner in Self.outline {
            for h in [0, -Self.thickness] {
                for p in [Self.base(corner.x, corner.y, h), Self.lid(corner.x, corner.y, h)] {
                    let q = camera.project(p)
                    minX = min(minX, q.x); maxX = max(maxX, q.x)
                    minY = min(minY, q.y); maxY = max(maxY, q.y)
                }
            }
        }
        fitMinX = minX
        fitMidY = (minY + maxY) / 2
        fitScale = (Self.fitX.upperBound - Self.fitX.lowerBound) / max(maxX - minX, 1e-9)
    }

    // MARK: - Paint order

    func paint(_ context: GraphicsContext) {
        background(context)
        baseHalf(context)
        duckBody(context)
        lidHalf(context)
        drips(context)
        duckHead(context)
        rims(context)
        // Key light from the upper left (VISUAL-TARGET §2.3).
        context.fill(rect(0, 0, 1024, 1024),
                     with: linear([(0xFFFFFF, 0, 0.06), (0xFFFFFF, 1, 0)], from: pt(0, 0), to: pt(700, 700)))
    }

    // MARK: - Background: graphite studio with a warm yellow glow behind the mouth, and the device's floor shadow

    private func background(_ ctx: GraphicsContext) {
        let full = rect(0, 0, 1024, 1024)
        ctx.fill(full, with: .color(Theme.rgb(0x26282C)))
        ctx.fill(full, with: radial([(0x4D515A, 0, 1), (0x2F3237, 0.55, 1), (0x1B1D20, 1, 1)],
                                    center: pt(470, 380), radius: 820))
        ctx.fill(full, with: radial([(0xFFC21A, 0, 0.34), (0xFFC21A, 0.5, 0.09), (0xFFC21A, 1, 0)],
                                    center: screen(Self.base(0, 380, 40)), radius: 480))
        let w = Self.width, d = Self.depth
        let floor = Self.roundedRect(x0: -w / 2 + 10, s0: 20, x1: w / 2 + 24, s1: d + 34, radius: Self.corner)
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 26 * s))
            layer.fill(polygon(floor.map { Self.base($0.x, $0.y, -Self.thickness) }), with: .color(.black.opacity(0.6)))
        }
    }

    // MARK: - Base half (the anvil): graphite slab, cream glass, hazard jaw on the free edge, steel strike plate

    private func baseHalf(_ ctx: GraphicsContext) {
        let w = Self.width, d = Self.depth, b = Self.bezel
        sides(ctx, half: Self.base, color: 0x3B3E44)
        ctx.fill(polygon(Self.outline.map { Self.base($0.x, $0.y, 0) }), with: .color(Theme.rgb(0x1F2124)))
        let glass = Self.roundedRect(x0: -w / 2 + b, s0: b, x1: w / 2 - b, s1: d - b, radius: Self.corner - b)
        ctx.fill(polygon(glass.map { Self.base($0.x, $0.y, 0) }),
                 with: linear([(0xB9B0A3, 0, 1), (0xF4EDE1, 1, 1)],
                              from: screen(Self.base(0, 0, 0)), to: screen(Self.base(0, d, 0))))
        hazardJaw(ctx)
        let plate = Self.roundedRect(x0: -150, s0: 125, x1: 150, s1: 355, radius: 18)
        ctx.fill(polygon(plate.map { Self.base($0.x, $0.y, 0) }),
                 with: linear([(0xC3C7CD, 0, 1), (0xE9EBEE, 0.5, 1), (0xB4B9C0, 1, 1)],
                              from: screen(Self.base(-150, 125, 0)), to: screen(Self.base(150, 355, 0))))
    }

    /// The base's 40 pt hazard jaw along its free edge, inside the bezel (FOLD-PRESS §5).
    private func hazardJaw(_ ctx: GraphicsContext) {
        let w = Self.width, d = Self.depth, b = Self.bezel
        let s0 = d - b - Self.jaw, s1 = d - b, x0 = -w / 2 + b, x1 = w / 2 - b
        let band = polygon([Self.base(x0, s0, 0), Self.base(x1, s0, 0), Self.base(x1, s1, 0), Self.base(x0, s1, 0)])
        var inside = ctx
        inside.clip(to: band)
        inside.fill(band, with: .color(Theme.rgb(Self.graphite)))
        let stripe = 34.0
        var a = x0 - stripe * 4
        while a < x1 + stripe * 4 {
            inside.fill(polygon([Self.base(a, s1, 0), Self.base(a + stripe, s1, 0),
                                 Self.base(a + stripe + Self.jaw, s0, 0), Self.base(a + Self.jaw, s0, 0)]),
                        with: .color(Theme.rgb(Self.yellow)))
            a += stripe * 2
        }
    }

    // MARK: - The duck's body: a yellow splat pinched between the halves, squeezed out across the glass

    private func duckBody(_ ctx: GraphicsContext) {
        let d = Self.depth, f = Self.footprint
        let tanOpening = tan(Self.opening * .pi / 180)
        let gap = f * tanOpening

        // Contact shadow on the glass.
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 12 * s))
            layer.fill(polygon(Self.blob(cx: 0, cs: f + 40, rx: 230, rs: 150).map { Self.base($0.x, $0.y, 0) }),
                       with: .color(Theme.rgb(0x5A3A00, opacity: 0.5)))
        }
        // The spill: flattened duck already squeezed out, a five-lobed splat running to the free edge.
        let spill = Self.splat(cx: 0, cs: f + 60, rx: 250, rs: 175, lobes: 5, amplitude: 0.22, phase: 0.6)
            .map { SIMD2<Double>($0.x, min($0.y, d + 2)) }
        let spillPath = polygon(spill.map { Self.base($0.x, $0.y, 1) })
        ctx.fill(spillPath, with: linear([(0xFFCF2E, 0, 1), (0xF0B000, 1, 1)],
                                         from: screen(Self.base(0, f, 0)), to: screen(Self.base(0, d, 0))))
        ctx.stroke(spillPath, with: .color(Theme.rgb(0xA86E00, opacity: 0.55)), lineWidth: 4 * s)

        // The body: 18 stacked slices from the glass up to the lid's inner face, widest at mid-height.
        let sliceCount = 18
        var slices: [Path] = []
        for index in 0..<sliceCount {
            let t = Double(index) / Double(sliceCount - 1)
            let bulge = sin(t * .pi)
            let outline = Self.splat(cx: 0, cs: f + 10, rx: 215 * (1 + 0.18 * bulge), rs: 120 * (1 + 0.22 * bulge),
                                     lobes: 4, amplitude: 0.12, phase: 1.1)
            slices.append(polygon(outline.map { Self.base($0.x, $0.y, $0.y * tanOpening * t) }))
        }
        let body = linear(Self.duckRamp, from: screen(Self.base(0, f, gap)), to: screen(Self.base(0, f, 0)))
        for slice in slices {
            ctx.fill(slice, with: body)
        }
        // Glossy vinyl: a lit core.
        var core = ctx
        core.clip(to: slices[sliceCount / 2])
        core.fill(rect(0, 0, 1024, 1024),
                  with: radial([(0xFFF7C0, 0, 0.7), (0xFFE680, 0.5, 0.25), (0xFFE680, 1, 0)],
                               center: screen(Self.base(0, f + 60, gap * 0.4)), radius: 200))
    }

    // MARK: - The duck's head: a squashed disc flopped over the front edge, one big eye, the orange beak poking out

    /// Drawn after the lid and drips, in the head's own 2D frame (design units, x right, y down, rotated by
    /// `headTilt`) around the projected head centre, because it pops out toward the viewer.
    private func duckHead(_ ctx: GraphicsContext) {
        let r = Self.headRadius
        let ry = r * Self.headSquash
        let tilt = Self.headTilt * .pi / 180
        let centre = screen(Self.base(Self.headCentre.x, Self.headCentre.y, Self.headCentre.z))
        let cosT = cos(tilt), sinT = sin(tilt)
        /// A point in the head frame, in points.
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: centre.x + (x * cosT - y * sinT) * s, y: centre.y + (x * sinT + y * cosT) * s)
        }
        /// An ellipse in the head frame (sizes in design units, extra rotation in degrees).
        func blot(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ degrees: CGFloat = 0) -> Path {
            ellipse(center: at(x, y), rx: rx * s, ry: ry * s, radians: tilt + degrees * .pi / 180)
        }

        // The beak first, so the head's rim overlaps its root: two flattened lobes pointing left.
        let bx = -r * 0.88, by = r * 0.18, bl: CGFloat = 165, bw: CGFloat = 70
        ctx.fill(blot(bx - bl * 0.42, by - bw * 0.18, bl * 0.62, bw * 0.62, 8), with: .color(Theme.rgb(Self.beak)))
        ctx.fill(blot(bx - bl * 0.30, by + bw * 0.34, bl * 0.48, bw * 0.42, 14), with: .color(Theme.rgb(Self.beakShade)))
        var mouth = Path()
        mouth.move(to: at(bx - bl * 0.95, by + bw * 0.12))
        mouth.addQuadCurve(to: at(bx + 10, by + bw * 0.05), control: at(bx - bl * 0.4, by + bw * 0.2))
        ctx.stroke(mouth, with: .color(Theme.rgb(0x9A3E00, opacity: 0.8)),
                   style: StrokeStyle(lineWidth: 5 * s, lineCap: .round))
        ctx.fill(blot(bx - bl * 0.55, by - bw * 0.42, bl * 0.22, bw * 0.12, 6), with: .color(Theme.rgb(0xFFF0D2, opacity: 0.7)))

        // Contact shadow, ochre rim, then the disc with a lit top.
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 6 * s))
            layer.fill(blot(6, 14, r + 8, ry + 10), with: .color(Theme.rgb(0x3A2600, opacity: 0.45)))
        }
        ctx.fill(blot(0, 0, r + 5, ry + 5), with: .color(Theme.rgb(Self.duckRim)))
        ctx.fill(blot(0, 0, r, ry), with: linear([(0xFFF08A, 0, 1), (0xFFD23F, 0.45, 1), (0xE9A800, 1, 1)],
                                                 from: at(0, -ry), to: at(0, ry)))

        // The eye: big, black, white-ringed, with a glint. It is what says "duck" at 40 px.
        let ex = -r * 0.30, ey = -ry * 0.22, er: CGFloat = 33
        ctx.fill(blot(ex, ey, er + 7, er * 1.12 + 7), with: .color(.white))
        ctx.fill(blot(ex - 3, ey + 2, er, er * 1.12), with: .color(Theme.rgb(0x141518)))
        ctx.fill(blot(ex - 11, ey - 10, er * 0.32, er * 0.32), with: .color(.white.opacity(0.95)))

        // Softbox highlight on the vinyl.
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 3 * s))
            layer.fill(blot(r * 0.28, -ry * 0.55, r * 0.34, r * 0.09, -8), with: .color(.white.opacity(0.8)))
        }
    }

    // MARK: - Lid half (the platen), seen from behind: graphite back, one lens, hazard stripes on its free edge

    private func lidHalf(_ ctx: GraphicsContext) {
        let w = Self.width, d = Self.depth, t = Self.thickness, r = Self.corner
        sides(ctx, half: Self.lid, color: 0x3F4248)

        // The free edge's end face carries the platen's hazard jaw.
        let end = polygon([Self.lid(-w / 2 + r, d, 0), Self.lid(w / 2 - r, d, 0),
                           Self.lid(w / 2 - r, d, -t), Self.lid(-w / 2 + r, d, -t)])
        var face = ctx
        face.clip(to: end)
        face.fill(end, with: .color(Theme.rgb(Self.graphite)))
        var a = -w / 2 - 80
        while a < w / 2 + 80 {
            face.fill(polygon([Self.lid(a, d, 0), Self.lid(a + 30, d, 0), Self.lid(a + 30 + t, d, -t), Self.lid(a + t, d, -t)]),
                      with: .color(Theme.rgb(Self.yellow)))
            a += 60
        }

        ctx.fill(polygon(Self.outline.map { Self.lid($0.x, $0.y, -t) }),
                 with: linear([(0x2A2C30, 0, 1), (0x3C3F45, 1, 1)],
                              from: screen(Self.lid(0, 0, -t)), to: screen(Self.lid(0, d, -t))))

        // A generic camera island by the hinge: one lens and its glint (not an Apple layout).
        let island = Self.roundedRect(x0: -w / 2 + 44, s0: 44, x1: -w / 2 + 164, s1: 164, radius: 36)
        let islandPath = polygon(island.map { Self.lid($0.x, $0.y, -t - 8) })
        ctx.fill(islandPath, with: .color(Theme.rgb(0x232529)))
        ctx.stroke(islandPath, with: .color(.white.opacity(0.14)), lineWidth: 2 * s)
        let lens = SIMD2<Double>(-w / 2 + 104, 104)
        ctx.fill(polygon(Self.circle(lens, 36).map { Self.lid($0.x, $0.y, -t - 9) }), with: .color(Theme.rgb(0x0E0F11)))
        ctx.fill(polygon(Self.circle(lens, 20).map { Self.lid($0.x, $0.y, -t - 9) }), with: .color(Theme.rgb(0x1C2433)))
        ctx.fill(polygon(Self.circle(lens - SIMD2(8, 8), 7).map { Self.lid($0.x, $0.y, -t - 9) }),
                 with: .color(Theme.rgb(0xAAC3EB, opacity: 0.7)))
    }

    // MARK: - Yellow drips over the base's front edge, flung droplets, rim light

    private func drips(_ ctx: GraphicsContext) {
        let d = Self.depth
        let ink = GraphicsContext.Shading.color(Theme.rgb(Self.drip))
        for (x, length, half) in [(-170.0, 70.0, 17.0), (70.0, 130.0, 22.0), (160.0, 58.0, 15.0)] {
            ctx.fill(polygon([Self.base(x - half, d, 0), Self.base(x + half, d, 0),
                              Self.base(x + half * 0.8, d + 3, -length), Self.base(x - half * 0.8, d + 3, -length)]),
                     with: ink)
            let centre = screen(Self.base(x, d + 4, -length))
            let edge = screen(Self.base(x + half, d + 4, -length))
            let radius = hypot(edge.x - centre.x, edge.y - centre.y)
            ctx.fill(ellipse(center: centre, rx: radius * 0.98, ry: radius * 1.12, radians: 0), with: ink)
            // A glint on each bead, so the drips read as glossy goo rather than dots.
            ctx.fill(ellipse(center: CGPoint(x: centre.x - radius * 0.35, y: centre.y - radius * 0.35),
                             rx: radius * 0.28, ry: radius * 0.2, radians: -0.4),
                     with: .color(Theme.rgb(0xFFFAE0, opacity: 0.7)))
        }
        let drops = oval(80, 700, 44, 44).union(oval(46, 650, 24, 24))
            .union(oval(950, 720, 36, 36)).union(oval(978, 770, 20, 20))
        ctx.fill(drops, with: .color(Theme.rgb(0xFFC81E)))
        let glints = oval(73, 693, 12, 8, -20).union(oval(944, 714, 10, 7, -20))
        ctx.fill(glints, with: .color(.white.opacity(0.75)))
    }

    private func rims(_ ctx: GraphicsContext) {
        let w = Self.width, d = Self.depth, r = Self.corner
        var lines = Path()
        lines.move(to: screen(Self.lid(-w / 2 + r, d, -Self.thickness)))
        lines.addLine(to: screen(Self.lid(w / 2 - r, d, -Self.thickness)))
        lines.move(to: screen(Self.base(-w / 2 + r, d, 0)))
        lines.addLine(to: screen(Self.base(w / 2 - r, d, 0)))
        ctx.stroke(lines, with: .color(.white.opacity(0.22)), lineWidth: 3 * s)
    }

    // MARK: - Slabs

    /// The slab's edge: one quad per outline segment from the face (h 0) to the other face (h −thickness), in the
    /// side colour. The faces drawn on top hide the segments facing away, so no back-face test is needed. Each quad
    /// is filled on its own: one combined path would cancel where front- and back-facing quads overlap (non-zero).
    private func sides(_ ctx: GraphicsContext, half: (Double, Double, Double) -> SIMD3<Double>, color: UInt32) {
        let t = Self.thickness
        let outline = Self.outline
        let shading = GraphicsContext.Shading.color(Theme.rgb(color))
        for index in outline.indices {
            let a = outline[index], b = outline[(index + 1) % outline.count]
            let quad = polygon([half(a.x, a.y, 0), half(b.x, b.y, 0), half(b.x, b.y, -t), half(a.x, a.y, -t)])
            ctx.fill(quad, with: shading)
            // A hairline in the same colour closes the anti-aliasing seams between neighbouring quads.
            ctx.stroke(quad, with: shading, lineWidth: 1 * s)
        }
    }

    // MARK: - 3D placement (device units)

    /// A point on the base half: `x` along the hinge, `along` from the hinge toward the free edge, `h` off the glass
    /// (positive into the mouth, negative into the slab).
    private static func base(_ x: Double, _ along: Double, _ h: Double) -> SIMD3<Double> {
        SIMD3<Double>(x, h, along)
    }

    /// The same on the lid half, which is turned `opening` degrees up about the hinge (its glass faces the base).
    private static func lid(_ x: Double, _ along: Double, _ h: Double) -> SIMD3<Double> {
        let a = opening * .pi / 180
        return SIMD3<Double>(x, sin(a) * along - cos(a) * h, cos(a) * along + sin(a) * h)
    }

    /// A rounded rectangle in plane coordinates (x, along), counter-clockwise, 9 points per corner.
    private static func roundedRect(x0: Double, s0: Double, x1: Double, s1: Double, radius: Double) -> [SIMD2<Double>] {
        let corners: [(Double, Double, Double)] = [(x1 - radius, s1 - radius, 0), (x0 + radius, s1 - radius, 90),
                                                   (x0 + radius, s0 + radius, 180), (x1 - radius, s0 + radius, 270)]
        var points: [SIMD2<Double>] = []
        for (cx, cy, start) in corners {
            for step in 0...8 {
                let angle = (start + 90 * Double(step) / 8) * .pi / 180
                points.append(SIMD2<Double>(cx + cos(angle) * radius, cy + sin(angle) * radius))
            }
        }
        return points
    }

    /// A lumpy ellipse (soft contact shadows), 72 points.
    private static func blob(cx: Double, cs: Double, rx: Double, rs: Double) -> [SIMD2<Double>] {
        (0..<72).map { index in
            let t = Double(index) / 72 * 2 * .pi
            let wobble = 1 + 0.09 * cos(3 * t) + 0.05 * sin(5 * t + 1)
            return SIMD2<Double>(cx + cos(t) * rx * wobble, cs + sin(t) * rs * wobble)
        }
    }

    /// A splat: an ellipse with `lobes` rounded bumps (the flattened duck's tail, wings and spill), 96 points.
    /// `amplitude` is the bump height as a fraction of the radius; the base is pulled in by a quarter of it.
    private static func splat(cx: Double, cs: Double, rx: Double, rs: Double,
                              lobes: Double, amplitude: Double, phase: Double) -> [SIMD2<Double>] {
        (0..<96).map { index in
            let t = Double(index) / 96 * 2 * .pi
            let bump = pow(max(0, cos(lobes * t + phase)), 3)
            let wobble = 1 + amplitude * bump - amplitude * 0.25 + 0.04 * sin(7 * t + 2)
            return SIMD2<Double>(cx + cos(t) * rx * wobble, cs + sin(t) * rs * wobble)
        }
    }

    private static func circle(_ centre: SIMD2<Double>, _ radius: Double) -> [SIMD2<Double>] {
        (0..<40).map { index in
            let t = Double(index) / 40 * 2 * .pi
            return SIMD2<Double>(centre.x + cos(t) * radius, centre.y + sin(t) * radius)
        }
    }

    // MARK: - Projection helpers (3D in, points out)

    private func screen(_ p: SIMD3<Double>) -> CGPoint {
        let q = camera.project(p)
        let x = Self.fitX.lowerBound + (q.x - fitMinX) * fitScale
        let y = Self.fitCentreY - (q.y - fitMidY) * fitScale
        return CGPoint(x: CGFloat(x) * s, y: CGFloat(y) * s)
    }

    private func polygon(_ points: [SIMD3<Double>]) -> Path {
        var path = Path()
        for (index, p) in points.enumerated() {
            if index == 0 {
                path.move(to: screen(p))
            } else {
                path.addLine(to: screen(p))
            }
        }
        path.closeSubpath()
        return path
    }

    /// An ellipse in points, rotated about its centre.
    private func ellipse(center: CGPoint, rx: CGFloat, ry: CGFloat, radians: CGFloat) -> Path {
        let transform = CGAffineTransform(rotationAngle: radians)
            .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
        return Path(ellipseIn: CGRect(x: -rx, y: -ry, width: 2 * rx, height: 2 * ry)).applying(transform)
    }

    // MARK: - 2D helpers (design units in, points out)

    private func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x * s, y: y * s)
    }

    private func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
        Path(CGRect(x: x * s, y: y * s, width: w * s, height: h * s))
    }

    /// An ellipse centred on (cx, cy), rotated by `degrees`.
    private func oval(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat, _ degrees: CGFloat = 0) -> Path {
        let transform = CGAffineTransform(rotationAngle: degrees * .pi / 180)
            .concatenating(CGAffineTransform(translationX: cx, y: cy))
            .concatenating(CGAffineTransform(scaleX: s, y: s))
        return Path(ellipseIn: CGRect(x: -w / 2, y: -h / 2, width: w, height: h)).applying(transform)
    }

    private func stops(_ list: [(UInt32, CGFloat, Double)]) -> Gradient {
        Gradient(stops: list.map { Gradient.Stop(color: Theme.rgb($0.0, opacity: $0.2), location: $0.1) })
    }

    private func linear(_ list: [(UInt32, CGFloat, Double)], from: CGPoint, to: CGPoint) -> GraphicsContext.Shading {
        .linearGradient(stops(list), startPoint: from, endPoint: to)
    }

    /// `center` in points, `radius` in design units.
    private func radial(_ list: [(UInt32, CGFloat, Double)], center: CGPoint, radius: CGFloat) -> GraphicsContext.Shading {
        .radialGradient(stops(list), center: center, startRadius: 0, endRadius: radius * s)
    }
}

#if DEBUG
#Preview("App icon") {
    AppIconArt()
        .frame(width: 402, height: 402)
        .background(Color.black)
}
#endif
