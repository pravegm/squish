import SwiftUI

/// The App Store icon (bible §5 "App icon"): the yellow P-48 ram squashing a raspberry gummy bear on graphite.
/// The ram's hazard lip and the anvil's mirrored hazard band are the Fold Press jaws (FOLD-PRESS §5): the top half
/// of the picture is the platen, the bottom half the anvil, and the squish sits on the seam between them.
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

/// Draws the icon. Every coordinate below is in 1024 design units; `s` converts to points.
private struct AppIconPainter {
    let s: CGFloat

    init(side: CGFloat) {
        s = side / 1024
    }

    // MARK: - Palette (VISUAL-TARGET §6.2 plus the icon's candy ramp)

    private static let yellow: UInt32 = 0xFFB81C
    private static let yellowLip: UInt32 = 0xC98A00
    private static let graphite: UInt32 = 0x2B2D31
    private static let gummyRamp: [(UInt32, CGFloat, Double)] = [(0xFF6E9C, 0, 1), (0xF0407A, 0.35, 1), (0xE8336F, 0.6, 1), (0xB01450, 1, 1)]

    // MARK: - Paint order

    func paint(_ context: GraphicsContext) {
        background(context)
        anvil(context)
        goo(context)
        bear(context)
        splats(context)
        ram(context)
        // Key light from the upper left (VISUAL-TARGET §2.3).
        context.fill(rect(0, 0, 1024, 1024),
                     with: linear([(0xFFFFFF, 0, 0.06), (0xFFFFFF, 1, 0)], from: pt(0, 0), to: pt(700, 700)))
    }

    // MARK: - Background: graphite studio with a candy glow behind the squish

    private func background(_ ctx: GraphicsContext) {
        let full = rect(0, 0, 1024, 1024)
        ctx.fill(full, with: .color(Theme.rgb(0x26282C)))
        ctx.fill(full, with: radial([(0x464A52, 0, 1), (0x2F3237, 0.55, 1), (0x1E2023, 1, 1)],
                                    center: pt(430, 420), radius: 760))
        ctx.fill(full, with: radial([(0xE8336F, 0, 0.32), (0xE8336F, 0.5, 0.10), (0xE8336F, 1, 0)],
                                    center: pt(512, 590), radius: 430))
    }

    // MARK: - Anvil (bottom half): steel top face, hazard band, graphite bed bleeding off the bottom

    private func anvil(_ ctx: GraphicsContext) {
        let front = rounded(150, 712, 724, 352, 34)
        ctx.fill(front, with: linear([(0x50545C, 0, 1), (0x34373D, 1, 1)], from: pt(0, 712), to: pt(0, 1024)))

        var inside = ctx
        inside.clip(to: front)
        inside.fill(rect(150, 712, 724, 352),
                    with: linear([(0x000000, 0, 0.22), (0x000000, 0.14, 0), (0x000000, 0.86, 0), (0x000000, 1, 0.26)],
                                 from: pt(150, 0), to: pt(874, 0)))
        hazardBand(inside, x: 150, y: 720, w: 724, h: 70, mirror: true)
        inside.fill(rect(150, 790, 724, 6), with: .color(Theme.rgb(0x1E2023, opacity: 0.7)))

        bolt(ctx, x: 214, y: 872, r: 20)
        bolt(ctx, x: 810, y: 872, r: 20)

        let top = rounded(140, 676, 744, 44, 16)
        ctx.fill(top, with: linear([(0xF2F3F5, 0, 1), (0xC4C8CE, 0.6, 1), (0x9DA2A9, 1, 1)],
                                   from: pt(0, 676), to: pt(0, 720)))
    }

    /// The squeezed-out puddle on the anvil and two drips running over its front edge.
    private func goo(_ ctx: GraphicsContext) {
        let puddle = oval(512, 702, 720, 34)
            .union(rounded(600, 700, 24, 70, 12))
            .union(rounded(286, 700, 20, 46, 10))
        ctx.fill(puddle, with: linear([(0xD0205E, 0, 1), (0x9E1045, 1, 1)], from: pt(0, 690), to: pt(0, 770)))
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 14 * s))
            layer.fill(oval(512, 712, 760, 40), with: .color(Theme.rgb(0x3B0A1E, opacity: 0.55)))
        }
    }

    // MARK: - The gummy bear, mid-squish (no face, bible §4 / VISUAL-TARGET §5.8)

    private var bearShape: Path {
        let parts: [Path] = [
            oval(322, 474, 100, 92, -20), oval(702, 474, 100, 92, 20),     // ears, squeezed outward
            oval(512, 618, 620, 160),                                      // belly, bulging past the plate
            oval(236, 600, 160, 80, -28), oval(788, 600, 160, 80, 28),     // arms
            oval(336, 690, 200, 74, -6), oval(688, 690, 200, 74, 6)        // feet, splayed forward
        ]
        var shape = oval(512, 494, 372, 144)                               // head, flattened under the plate
        for part in parts {
            shape = shape.union(part)
        }
        return shape
    }

    private func bear(_ ctx: GraphicsContext) {
        let shape = bearShape
        ctx.fill(shape, with: gummy)

        var inside = ctx
        inside.clip(to: shape)
        // Translucent candy: a lit core and denser, darker edges.
        inside.fill(rect(0, 0, 1024, 1024),
                    with: radial([(0xFFA3C2, 0, 0.85), (0xFF6E9C, 0.45, 0.35), (0xFF6E9C, 1, 0)],
                                 center: pt(512, 600), radius: 330))
        inside.drawLayer { layer in
            layer.addFilter(.blur(radius: 16 * s))
            layer.stroke(shape, with: .color(Theme.rgb(0x7A0A33, opacity: 0.6)), lineWidth: 34 * s)
        }
        // The plate's shadow where it bites in, and warm bounce light off the steel anvil.
        inside.fill(rect(0, 430, 1024, 70),
                    with: linear([(0x5C0624, 0, 0.55), (0x5C0624, 1, 0)], from: pt(0, 442), to: pt(0, 500)))
        inside.drawLayer { layer in
            layer.addFilter(.blur(radius: 10 * s))
            layer.fill(oval(512, 706, 560, 24), with: .color(Theme.rgb(0xFFC2D6, opacity: 0.35)))
        }
        highlights(inside)
    }

    /// Glossy strip highlights (the softbox reflections of VISUAL-TARGET §2.1) plus one hard sparkle.
    private func highlights(_ ctx: GraphicsContext) {
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 2.5 * s))
            layer.fill(rounded(300, 574, 230, 20, 10), with: .color(.white.opacity(0.85)))
            let soft = rounded(556, 578, 64, 16, 8)
                .union(oval(214, 588, 52, 16, -28)).union(oval(810, 588, 52, 16, 28))
                .union(oval(306, 680, 70, 14, -6)).union(oval(658, 680, 70, 14, 6))
            layer.fill(soft, with: .color(.white.opacity(0.6)))
            let upper = rounded(400, 462, 140, 18, 9)
                .union(oval(300, 478, 30, 15, -20)).union(oval(724, 478, 30, 15, 20))
            layer.fill(upper, with: .color(.white.opacity(0.7)))
        }
        ctx.fill(oval(312, 584, 12, 12), with: .color(.white))
    }

    /// Droplets squirting out of the jaws on both sides.
    private func splats(_ ctx: GraphicsContext) {
        let drops = oval(112, 588, 58, 34, -18)
            .union(oval(74, 540, 32, 32)).union(oval(70, 634, 20, 20))
            .union(oval(912, 594, 58, 34, 18)).union(oval(952, 544, 30, 30))
            .union(oval(956, 640, 18, 18)).union(oval(890, 530, 12, 12))
        ctx.fill(drops, with: gummy)
        let glints = oval(102, 580, 16, 8, -18).union(oval(68, 534, 9, 9))
            .union(oval(902, 586, 16, 8, 18)).union(oval(947, 538, 8, 8))
        ctx.fill(glints, with: .color(.white.opacity(0.8)))
    }

    // MARK: - Ram (top half): chrome rod, yellow platen with its hazard lip, steel strike plate

    private func ram(_ ctx: GraphicsContext) {
        ctx.fill(rect(444, -20, 136, 230),
                 with: linear([(0x7E838B, 0, 1), (0xE9EBEE, 0.18, 1), (0xFFFFFF, 0.26, 1), (0xB4B9C0, 0.45, 1),
                               (0x5E636B, 0.66, 1), (0xC8CCD2, 0.86, 1), (0x8A8F98, 1, 1)],
                              from: pt(444, 0), to: pt(580, 0)))
        ctx.fill(rounded(392, 176, 240, 34, 14),
                 with: linear([(0xFFD35E, 0, 1), (0xD99200, 1, 1)], from: pt(0, 176), to: pt(0, 210)))

        let block = rounded(124, 196, 776, 228, 52)
        ctx.drawLayer { layer in
            layer.addFilter(.shadow(color: Theme.rgb(0x120A0E, opacity: 0.6), radius: 22 * s, x: 0, y: 16 * s))
            layer.fill(block, with: .color(Theme.rgb(Self.yellow)))
        }
        ctx.fill(block, with: linear([(0xFFD35E, 0, 1), (0xFFBE2A, 0.35, 1), (Self.yellow, 0.6, 1), (0xE59C00, 1, 1)],
                                     from: pt(0, 196), to: pt(0, 424)))
        platenDetail(ctx, block: block)

        bolt(ctx, x: 206, y: 276, r: 20)
        bolt(ctx, x: 818, y: 276, r: 20)

        ctx.fill(rounded(172, 420, 680, 26, 9),
                 with: linear([(0xE9EBEE, 0, 1), (0xA3A8AF, 1, 1)], from: pt(0, 420), to: pt(0, 446)))
    }

    private func platenDetail(_ ctx: GraphicsContext, block: Path) {
        var inside = ctx
        inside.clip(to: block)
        inside.fill(rect(124, 196, 776, 228),
                    with: linear([(0x8A5A00, 0, 0.30), (0x8A5A00, 0.14, 0), (0x8A5A00, 0.86, 0), (0x8A5A00, 1, 0.34)],
                                 from: pt(124, 0), to: pt(900, 0)))
        inside.drawLayer { layer in
            layer.addFilter(.blur(radius: 18 * s))
            layer.fill(oval(330, 222, 520, 70, -3), with: .color(.white.opacity(0.35)))
        }
        inside.drawLayer { layer in
            layer.addFilter(.blur(radius: 2 * s))
            layer.fill(rect(124, 199, 776, 7), with: .color(.white.opacity(0.55)))
        }
        hazardBand(inside, x: 124, y: 350, w: 776, h: 74, mirror: false)
        inside.fill(rect(124, 350, 776, 6), with: .color(Theme.rgb(Self.yellowLip)))
    }

    // MARK: - Parts

    /// 45° amber / graphite stripes (FOLD-PRESS §5). The ram's and the anvil's bands slant opposite ways so the
    /// jaws mesh; a stripe is centred on the midline so the icon stays symmetric.
    private func hazardBand(_ ctx: GraphicsContext, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, mirror: Bool) {
        let stripe: CGFloat = 36
        let dx = mirror ? -h : h
        let first = 512 - stripe / 2 - dx / 2
        let lowest = x - h - stripe * 2
        var a = first - (((first - lowest) / (stripe * 2)).rounded(.up)) * stripe * 2
        var stripes = Path()
        while a < x + w + h + stripe * 2 {
            stripes.move(to: CGPoint(x: a, y: y))
            stripes.addLine(to: CGPoint(x: a + stripe, y: y))
            stripes.addLine(to: CGPoint(x: a + stripe + dx, y: y + h))
            stripes.addLine(to: CGPoint(x: a + dx, y: y + h))
            stripes.closeSubpath()
            a += stripe * 2
        }
        ctx.fill(rect(x, y, w, h), with: .color(Theme.rgb(Self.graphite)))
        ctx.fill(scaled(stripes), with: .color(Theme.rgb(Self.yellow)))
        ctx.fill(rect(x, y, w, h), with: linear([(0x000000, 0, 0), (0x000000, 1, 0.24)], from: pt(0, y), to: pt(0, y + h)))
    }

    /// A chrome dome bolt with a soft drop shadow.
    private func bolt(_ ctx: GraphicsContext, x: CGFloat, y: CGFloat, r: CGFloat) {
        ctx.fill(oval(x, y + 3, 2 * r + 6, 2 * r + 6), with: .color(Theme.rgb(0x1E2023, opacity: 0.45)))
        ctx.fill(oval(x, y, 2 * r, 2 * r),
                 with: radial([(0xFFFFFF, 0, 1), (0xC9CDD3, 0.45, 1), (0x6C7179, 1, 1)],
                              center: pt(x - r * 0.35, y - r * 0.4), radius: r * 1.6))
    }

    private var gummy: GraphicsContext.Shading {
        linear(Self.gummyRamp, from: pt(0, 442), to: pt(0, 728))
    }

    // MARK: - Geometry helpers (design units in, points out)

    private func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x * s, y: y * s)
    }

    private func scaled(_ path: Path) -> Path {
        path.applying(CGAffineTransform(scaleX: s, y: s))
    }

    private func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
        scaled(Path(CGRect(x: x, y: y, width: w, height: h)))
    }

    private func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
        scaled(Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r, style: .continuous))
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
