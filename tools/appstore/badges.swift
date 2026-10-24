// badges.swift: renders the 10 Game Center achievement images for Squish.
//
//   xcrun swift tools/appstore/badges.swift [--out <dir>]
//
// Output: <dir>/<vendorIdentifier>.png (1024 x 1024, opaque sRGB PNG, 72 ppi; Game Center's current requirement per
// App Store Connect Help > Game Center > Achievements: ".jpeg, .jpg, or .png ... 1024 x 1024 pixels, at least 72 ppi,
// and in the RGB color space"), plus <dir>/preview.png, a contact sheet of all ten.
// Default <dir> is tools/appstore/badges next to this script.
//
// Visual language (Squish/UI/Theme.swift): press yellow #FFB81C on graphite #2B2D31, a hazard-striped band like the
// P-48's ram guard, rivets, and one SF Symbol-like glyph per achievement (the same symbols AchievementInfo.swift uses
// for the in-app toasts), drawn as vector paths so no fonts or symbol assets are needed. Midas gets a gold plate and
// The Secret a steel one. Game Center shows achievement art in a circle, so everything that matters sits inside it.
//
// It also verifies the IDs: the ten vendor identifiers here must equal Achievement.gameCenterID in
// Squish/Shared/Contracts.swift (snake_case of each case, prefixed com.pravegm.squish.ach.), the IDs in
// docs/appstore/achievements.md, and, if it exists, docs/appstore/asc-metadata.json. Any mismatch exits 1.

import CoreGraphics
import Foundation
import ImageIO

// MARK: - Paths and arguments

let scriptURL = URL(fileURLWithPath: #filePath).standardizedFileURL
let scriptDir = scriptURL.deletingLastPathComponent()
let repoRoot: URL = {
    if let env = ProcessInfo.processInfo.environment["ASC_REPO_ROOT"], !env.isEmpty {
        return URL(fileURLWithPath: env)
    }
    let guess = scriptDir.deletingLastPathComponent().deletingLastPathComponent()
    if FileManager.default.fileExists(atPath: guess.appendingPathComponent("Squish/Shared/Contracts.swift").path) {
        return guess
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
}()

var outDir = scriptDir.appendingPathComponent("badges")
do {
    var args = Array(CommandLine.arguments.dropFirst())
    while !args.isEmpty {
        let a = args.removeFirst()
        switch a {
        case "--out":
            guard !args.isEmpty else { FileHandle.standardError.write("--out needs a directory\n".data(using: .utf8)!); exit(2) }
            outDir = URL(fileURLWithPath: args.removeFirst())
        case "-h", "--help":
            print("usage: xcrun swift tools/appstore/badges.swift [--out <dir>]")
            exit(0)
        default:
            FileHandle.standardError.write("unknown argument \(a)\n".data(using: .utf8)!)
            exit(2)
        }
    }
}

// MARK: - The ten achievements

enum Plate { case yellow, gold, steel }

struct Badge {
    let snake: String      // Achievement.gameCenterID suffix
    let title: String      // AchievementInfo.title
    let plate: Plate
    let draw: (CGContext) -> Void
    var vendorIdentifier: String { "com.pravegm.squish.ach.\(snake)" }
}

// MARK: - Colours (Theme.swift)

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let graphite = rgb(0x2B2D31)
let graphiteRaised = rgb(0x3A3D43)
let graphiteDeep = rgb(0x1B1C1F)
let consoleLip = rgb(0x141518)
let yellow = rgb(0xFFB81C)
let yellowLip = rgb(0xC98A00)
let yellowSoft = rgb(0xFFE3A1)
let gold = rgb(0xC8921A)
let goldSoft = rgb(0xF6E2A8)
let steel = rgb(0x8A8F98)
let steelLight = rgb(0xD5D9DF)
let steelDark = rgb(0x5D6168)
let paper = rgb(0xFBF8F1)
let stampRed = rgb(0xD7263D)
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: locations)!
}

// MARK: - Geometry helpers (glyph space: origin at the badge centre, y up, 1 unit = 1 px)

let size: CGFloat = 1024
let centre = CGPoint(x: 512, y: 512)
let ringOuter: CGFloat = 476
let ringInner: CGFloat = 392

func circle(_ c: CGPoint, _ r: CGFloat) -> CGRect { CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r) }

func roundedRect(_ ctx: CGContext, _ r: CGRect, _ radius: CGFloat) {
    let radius = min(radius, r.width / 2, r.height / 2)
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
}

/// A capsule from `a` to `b` with the given width (a rounded stroke, filled).
func capsule(_ ctx: CGContext, from a: CGPoint, to b: CGPoint, width: CGFloat) {
    let p = CGMutablePath()
    p.move(to: a)
    p.addLine(to: b)
    ctx.addPath(p.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10))
}

/// A four-point sparkle (SF "sparkles"): concave sides.
func sparkle(_ ctx: CGContext, at c: CGPoint, radius r: CGFloat) {
    let k = r * 0.16
    let p = CGMutablePath()
    p.move(to: CGPoint(x: c.x, y: c.y + r))
    p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + k, y: c.y + k))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x + k, y: c.y - k))
    p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - k, y: c.y - k))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x - k, y: c.y + k))
    p.closeSubpath()
    ctx.addPath(p)
}

/// Draws several fills as one shadowed group (so a shape and its rounding stroke never cancel or double-shadow).
func shadowedGroup(_ ctx: CGContext, _ body: () -> Void) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 22, color: rgb(0x000000, 0.38))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    body()
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

/// Fills `path` and a round-joined stroke of it, which rounds the corners the way SF Symbols are drawn.
func fillRounded(_ ctx: CGContext, _ path: CGPath, _ color: CGColor, radius: CGFloat) {
    ctx.setFillColor(color)
    ctx.addPath(path)
    ctx.fillPath()
    ctx.addPath(path.copy(strokingWithWidth: radius * 2, lineCap: .round, lineJoin: .round, miterLimit: 10))
    ctx.fillPath()
}

/// Fills the current path in `color`, with the soft drop shadow every glyph casts on its plate.
func fillGlyph(_ ctx: CGContext, _ color: CGColor, shadow: Bool = true, evenOdd: Bool = false) {
    ctx.saveGState()
    if shadow { ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 22, color: rgb(0x000000, 0.38)) }
    ctx.setFillColor(color)
    ctx.fillPath(using: evenOdd ? .evenOdd : .winding)
    ctx.restoreGState()
}

// MARK: - Glyphs (each draws in glyph space; the plate colour is the knock-out colour)

func plateColour(_ plate: Plate) -> CGColor {
    switch plate {
    case .yellow: return yellow
    case .gold: return goldSoft
    case .steel: return steel
    }
}

func glyphFirstSquish(_ ctx: CGContext) {
    // 1.circle.fill, squashed a touch: the first press.
    ctx.addEllipse(in: CGRect(x: -232, y: -212, width: 464, height: 424))
    fillGlyph(ctx, graphite)
    // The numeral 1 (stem and flag as one outline, then the foot), knocked out in yellow.
    let stem = CGMutablePath()
    stem.addLines(between: [CGPoint(x: -30, y: 132), CGPoint(x: 36, y: 132), CGPoint(x: 36, y: -124),
                            CGPoint(x: -30, y: -124), CGPoint(x: -30, y: 62), CGPoint(x: -100, y: 22),
                            CGPoint(x: -100, y: 82)])
    stem.closeSubpath()
    fillRounded(ctx, stem, yellow, radius: 9)
    let foot = CGPath(roundedRect: CGRect(x: -112, y: -150, width: 230, height: 62), cornerWidth: 16, cornerHeight: 16, transform: nil)
    fillRounded(ctx, foot, yellow, radius: 0.5)
}

func glyphPopStar(_ ctx: CGContext) {
    // circle.grid.3x3.fill as bubble wrap: eight bubbles and one popped.
    let step: CGFloat = 150
    for row in -1...1 {
        for col in -1...1 {
            let c = CGPoint(x: CGFloat(col) * step, y: CGFloat(row) * step)
            if row == 0 && col == 0 {
                // The pop: an eight-ray burst.
                let burst = CGMutablePath()
                for i in 0..<8 {
                    let a = CGFloat(i) * .pi / 4 + .pi / 8
                    let inner = CGPoint(x: c.x + cos(a) * 26, y: c.y + sin(a) * 26)
                    let outer = CGPoint(x: c.x + cos(a) * 70, y: c.y + sin(a) * 70)
                    burst.move(to: inner)
                    burst.addLine(to: outer)
                }
                ctx.addPath(burst.copy(strokingWithWidth: 20, lineCap: .round, lineJoin: .round, miterLimit: 10))
                fillGlyph(ctx, graphite)
            } else {
                ctx.addEllipse(in: circle(c, 60))
                fillGlyph(ctx, graphite)
                ctx.addEllipse(in: circle(CGPoint(x: c.x - 20, y: c.y + 22), 13))
                fillGlyph(ctx, rgb(0xFFFFFF, 0.55), shadow: false)
            }
        }
    }
}

func glyphWhatsInside(_ ctx: CGContext) {
    // gift.fill
    roundedRect(ctx, CGRect(x: -186, y: -214, width: 372, height: 250), 20)
    roundedRect(ctx, CGRect(x: -214, y: 48, width: 428, height: 96), 18)
    // Bow: two loops and a knot.
    let loops = CGMutablePath()
    loops.addEllipse(in: CGRect(x: -150, y: -42, width: 150, height: 84),
                     transform: CGAffineTransform(translationX: 0, y: 196).rotated(by: -0.42))
    loops.addEllipse(in: CGRect(x: 0, y: -42, width: 150, height: 84),
                     transform: CGAffineTransform(translationX: 0, y: 196).rotated(by: 0.42))
    ctx.addPath(loops)
    fillGlyph(ctx, graphite)
    // Loop holes and the ribbon gap, knocked out in the plate colour.
    let holes = CGMutablePath()
    holes.addEllipse(in: CGRect(x: -118, y: -18, width: 86, height: 36),
                     transform: CGAffineTransform(translationX: 0, y: 196).rotated(by: -0.42))
    holes.addEllipse(in: CGRect(x: 32, y: -18, width: 86, height: 36),
                     transform: CGAffineTransform(translationX: 0, y: 196).rotated(by: 0.42))
    holes.addRect(CGRect(x: -26, y: -214, width: 52, height: 358))
    ctx.addPath(holes)
    fillGlyph(ctx, yellow, shadow: false)
    ctx.addEllipse(in: circle(CGPoint(x: 0, y: 168), 34))
    fillGlyph(ctx, graphite, shadow: false)
}

func glyphPatience(_ ctx: CGContext) {
    // hourglass
    roundedRect(ctx, CGRect(x: -176, y: 196, width: 352, height: 48), 18)
    roundedRect(ctx, CGRect(x: -176, y: -244, width: 352, height: 48), 18)
    fillGlyph(ctx, graphite)
    let glass = CGMutablePath()
    glass.move(to: CGPoint(x: -134, y: 196))
    glass.addCurve(to: CGPoint(x: -22, y: 0), control1: CGPoint(x: -134, y: 92), control2: CGPoint(x: -22, y: 56))
    glass.addCurve(to: CGPoint(x: -134, y: -196), control1: CGPoint(x: -22, y: -56), control2: CGPoint(x: -134, y: -92))
    glass.move(to: CGPoint(x: 134, y: 196))
    glass.addCurve(to: CGPoint(x: 22, y: 0), control1: CGPoint(x: 134, y: 92), control2: CGPoint(x: 22, y: 56))
    glass.addCurve(to: CGPoint(x: 134, y: -196), control1: CGPoint(x: 22, y: -56), control2: CGPoint(x: 134, y: -92))
    ctx.addPath(glass.copy(strokingWithWidth: 30, lineCap: .round, lineJoin: .round, miterLimit: 10))
    fillGlyph(ctx, graphite)
    // Sand: a heap below, a little left above, and the falling stream.
    let sand = CGMutablePath()
    sand.move(to: CGPoint(x: -104, y: -186))
    sand.addLine(to: CGPoint(x: 104, y: -186))
    sand.addQuadCurve(to: CGPoint(x: 0, y: -70), control: CGPoint(x: 40, y: -96))
    sand.addQuadCurve(to: CGPoint(x: -104, y: -186), control: CGPoint(x: -40, y: -96))
    sand.closeSubpath()
    sand.move(to: CGPoint(x: -66, y: 104))
    sand.addLine(to: CGPoint(x: 66, y: 104))
    sand.addLine(to: CGPoint(x: 0, y: 34))
    sand.closeSubpath()
    ctx.addPath(sand)
    capsule(ctx, from: CGPoint(x: 0, y: 30), to: CGPoint(x: 0, y: -64), width: 12)
    fillGlyph(ctx, graphite, shadow: false)
}

func arrowPath(x: CGFloat, up: Bool) -> CGPath {
    let s: CGFloat = up ? 1 : -1
    let p = CGMutablePath()
    p.addLines(between: [
        CGPoint(x: x - 30, y: -190 * s), CGPoint(x: x + 30, y: -190 * s),
        CGPoint(x: x + 30, y: 70 * s), CGPoint(x: x + 98, y: 70 * s),
        CGPoint(x: x, y: 214 * s), CGPoint(x: x - 98, y: 70 * s), CGPoint(x: x - 30, y: 70 * s),
    ])
    p.closeSubpath()
    return p
}

func glyphFullSet(_ ctx: CGContext) {
    // building.columns.fill: the museum, one wing full. Pediment, architrave, four columns, two steps.
    let pediment = CGMutablePath()
    pediment.addLines(between: [CGPoint(x: -250, y: 128), CGPoint(x: 250, y: 128), CGPoint(x: 0, y: 252)])
    pediment.closeSubpath()
    shadowedGroup(ctx) {
        fillRounded(ctx, pediment, graphite, radius: 14)
        ctx.setFillColor(graphite)
        roundedRect(ctx, CGRect(x: -236, y: 70, width: 472, height: 46), 12)
        ctx.fillPath()
        for x: CGFloat in [-168, -56, 56, 168] {
            roundedRect(ctx, CGRect(x: x - 30, y: -136, width: 60, height: 196), 10)
            ctx.fillPath()
        }
        roundedRect(ctx, CGRect(x: -226, y: -176, width: 452, height: 32), 10)
        ctx.fillPath()
        roundedRect(ctx, CGRect(x: -258, y: -224, width: 516, height: 40), 12)
        ctx.fillPath()
    }
    // A round window in the pediment, knocked out in the plate colour, with a tiny pressed specimen in it.
    ctx.addEllipse(in: circle(CGPoint(x: 0, y: 168), 36))
    fillGlyph(ctx, yellow, shadow: false)
    ctx.addEllipse(in: CGRect(x: -22, y: 156, width: 44, height: 20))
    fillGlyph(ctx, graphite, shadow: false)
}

func glyphPerfectionist(_ ctx: CGContext) {
    // sparkles: the big one, the medium one, the small one.
    sparkle(ctx, at: CGPoint(x: -52, y: -40), radius: 214)
    sparkle(ctx, at: CGPoint(x: 150, y: 152), radius: 104)
    sparkle(ctx, at: CGPoint(x: -176, y: 178), radius: 60)
    fillGlyph(ctx, graphite)
}

func glyphSteadyHands(_ ctx: CGContext) {
    // hand.raised.fill
    let fingers: [(x: CGFloat, top: CGFloat)] = [(-114, 150), (-40, 214), (34, 200), (106, 134)]
    for f in fingers {
        capsule(ctx, from: CGPoint(x: f.x, y: -20), to: CGPoint(x: f.x, y: f.top), width: 64)
    }
    capsule(ctx, from: CGPoint(x: -140, y: -110), to: CGPoint(x: -228, y: 20), width: 66)
    roundedRect(ctx, CGRect(x: -152, y: -240, width: 292, height: 272), 104)
    fillGlyph(ctx, graphite)
    // Finger gaps above the palm.
    let gaps = CGMutablePath()
    for gx: CGFloat in [-77, -3, 70] {
        gaps.addRoundedRect(in: CGRect(x: gx - 5, y: 30, width: 10, height: 120), cornerWidth: 5, cornerHeight: 5)
    }
    ctx.addPath(gaps)
    fillGlyph(ctx, yellow, shadow: false)
}

func glyphMidas(_ ctx: CGContext) {
    // crown.fill on a gold plate.
    let body = CGMutablePath()
    body.addLines(between: [
        CGPoint(x: -196, y: -92), CGPoint(x: 196, y: -92), CGPoint(x: 232, y: 140),
        CGPoint(x: 104, y: 30), CGPoint(x: 0, y: 188), CGPoint(x: -104, y: 30), CGPoint(x: -232, y: 140),
    ])
    body.closeSubpath()
    shadowedGroup(ctx) {
        fillRounded(ctx, body, graphite, radius: 11)
        ctx.setFillColor(graphite)
        roundedRect(ctx, CGRect(x: -200, y: -186, width: 400, height: 70), 16)
        ctx.fillPath()
        for c in [CGPoint(x: -232, y: 160), CGPoint(x: 0, y: 212), CGPoint(x: 232, y: 160)] {
            ctx.addEllipse(in: circle(c, 28))
            ctx.fillPath()
        }
    }
    // Three gems in the band.
    for gx: CGFloat in [-110, 0, 110] {
        ctx.addEllipse(in: circle(CGPoint(x: gx, y: -151), 15))
    }
    fillGlyph(ctx, goldSoft, shadow: false)
}

func glyphCollector(_ ctx: CGContext) {
    // square.grid.3x3.fill: the full shelf.
    let cell: CGFloat = 124
    let step: CGFloat = 152
    for row in -1...1 {
        for col in -1...1 {
            let c = CGPoint(x: CGFloat(col) * step, y: CGFloat(row) * step)
            roundedRect(ctx, CGRect(x: c.x - cell / 2, y: c.y - cell / 2, width: cell, height: cell), 26)
        }
    }
    fillGlyph(ctx, graphite)
}

func glyphTheSecret(_ ctx: CGContext) {
    // The press plate, dented, and the thing that dented it. PRESS 0 – BALL 1.
    let plate = CGMutablePath()
    plate.move(to: CGPoint(x: -270, y: -230))
    plate.addLine(to: CGPoint(x: -270, y: -40))
    plate.addLine(to: CGPoint(x: -128, y: -40))
    plate.addCurve(to: CGPoint(x: 128, y: -40), control1: CGPoint(x: -110, y: -150), control2: CGPoint(x: 110, y: -150))
    plate.addLine(to: CGPoint(x: 270, y: -40))
    plate.addLine(to: CGPoint(x: 270, y: -230))
    plate.closeSubpath()
    ctx.saveGState()
    ctx.addEllipse(in: circle(.zero, ringInner - 6))
    ctx.clip()
    ctx.addPath(plate)
    fillGlyph(ctx, graphite)
    ctx.restoreGState()
    // Hairline cracks from the dent.
    let cracks = CGMutablePath()
    cracks.move(to: CGPoint(x: -96, y: -92)); cracks.addLine(to: CGPoint(x: -150, y: -128)); cracks.addLine(to: CGPoint(x: -196, y: -120))
    cracks.move(to: CGPoint(x: 92, y: -96)); cracks.addLine(to: CGPoint(x: 140, y: -150)); cracks.addLine(to: CGPoint(x: 200, y: -160))
    cracks.move(to: CGPoint(x: 0, y: -122)); cracks.addLine(to: CGPoint(x: -14, y: -176)); cracks.addLine(to: CGPoint(x: 16, y: -214))
    ctx.addPath(cracks.copy(strokingWithWidth: 8, lineCap: .round, lineJoin: .round, miterLimit: 10))
    fillGlyph(ctx, steel, shadow: false)
    // The ball, sitting in its dent.
    let ballCentre = CGPoint(x: 0, y: 30)
    let ballR: CGFloat = 150
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 28, color: rgb(0x000000, 0.45))
    ctx.addEllipse(in: circle(ballCentre, ballR))
    ctx.setFillColor(steelDark)
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addEllipse(in: circle(ballCentre, ballR))
    ctx.clip()
    ctx.drawRadialGradient(gradient([rgb(0xF4F6F8), steelLight, steel, steelDark, graphite], [0, 0.18, 0.5, 0.82, 1]),
                           startCenter: CGPoint(x: ballCentre.x - 52, y: ballCentre.y + 60), startRadius: 0,
                           endCenter: ballCentre, endRadius: ballR, options: [.drawsAfterEndLocation])
    ctx.restoreGState()
    ctx.addEllipse(in: CGRect(x: ballCentre.x - 82, y: ballCentre.y + 54, width: 54, height: 30))
    fillGlyph(ctx, rgb(0xFFFFFF, 0.7), shadow: false)
}

let badges: [Badge] = [
    Badge(snake: "first_squish", title: "First Squish", plate: .yellow, draw: glyphFirstSquish),
    Badge(snake: "pop_star", title: "Pop Star", plate: .yellow, draw: glyphPopStar),
    Badge(snake: "whats_inside", title: "What's Inside?", plate: .yellow, draw: glyphWhatsInside),
    Badge(snake: "patience", title: "Patience", plate: .yellow, draw: glyphPatience),
    Badge(snake: "full_set", title: "Full Set", plate: .yellow, draw: glyphFullSet),
    Badge(snake: "perfectionist", title: "Perfectionist", plate: .yellow, draw: glyphPerfectionist),
    Badge(snake: "steady_hands", title: "Steady Hands", plate: .yellow, draw: glyphSteadyHands),
    Badge(snake: "midas", title: "Midas", plate: .gold, draw: glyphMidas),
    Badge(snake: "collector", title: "Collector", plate: .yellow, draw: glyphCollector),
    Badge(snake: "the_secret", title: "The Secret", plate: .steel, draw: glyphTheSecret),
]

// MARK: - The badge frame

func drawBadge(_ badge: Badge, in ctx: CGContext) {
    // Graphite field, a little lighter in the middle.
    ctx.setFillColor(graphite)
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    ctx.drawRadialGradient(gradient([graphiteRaised, graphite, graphiteDeep], [0, 0.6, 1]),
                           startCenter: centre, startRadius: 0, endCenter: centre, endRadius: size * 0.72,
                           options: [.drawsAfterEndLocation])

    // Hazard band.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: rgb(0x000000, 0.5))
    ctx.addEllipse(in: circle(centre, ringOuter))
    ctx.setFillColor(consoleLip)
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    let band = CGMutablePath()
    band.addEllipse(in: circle(centre, ringOuter - 10))
    band.addEllipse(in: circle(centre, ringInner + 6))
    ctx.addPath(band)
    ctx.clip(using: .evenOdd)
    ctx.setFillColor(yellow)
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    ctx.translateBy(x: centre.x, y: centre.y)
    ctx.rotate(by: .pi / 4)
    ctx.setFillColor(graphite)
    var x: CGFloat = -800
    while x < 800 {
        ctx.fill(CGRect(x: x, y: -800, width: 38, height: 1600))
        x += 84
    }
    ctx.restoreGState()
    // Band edges.
    ctx.setStrokeColor(consoleLip)
    ctx.setLineWidth(10)
    ctx.strokeEllipse(in: circle(centre, ringOuter - 8))
    ctx.strokeEllipse(in: circle(centre, ringInner + 4))

    // Rivets on the band.
    for i in 0..<4 {
        let a = CGFloat(i) * .pi / 2 + .pi / 4
        let c = CGPoint(x: centre.x + cos(a) * (ringInner + ringOuter) / 2 - 1, y: centre.y + sin(a) * (ringInner + ringOuter) / 2)
        ctx.addEllipse(in: circle(c, 24))
        ctx.setFillColor(consoleLip)
        ctx.fillPath()
        ctx.saveGState()
        ctx.addEllipse(in: circle(c, 19))
        ctx.clip()
        ctx.drawRadialGradient(gradient([steelLight, steel, steelDark], [0, 0.55, 1]),
                               startCenter: CGPoint(x: c.x - 6, y: c.y + 7), startRadius: 0,
                               endCenter: c, endRadius: 19, options: [])
        ctx.restoreGState()
    }

    // The plate.
    let plateColours: [CGColor]
    switch badge.plate {
    case .yellow: plateColours = [yellowSoft, yellow, yellow, yellowLip]
    case .gold: plateColours = [rgb(0xFFF3CF), goldSoft, rgb(0xE3B84A), gold]
    case .steel: plateColours = [steelLight, rgb(0xAEB3BB), steel, steelDark]
    }
    ctx.saveGState()
    ctx.addEllipse(in: circle(centre, ringInner))
    ctx.clip()
    ctx.drawLinearGradient(gradient(plateColours, [0, 0.28, 0.7, 1]),
                           start: CGPoint(x: centre.x, y: centre.y + ringInner),
                           end: CGPoint(x: centre.x, y: centre.y - ringInner), options: [])
    // Machined rings.
    ctx.setStrokeColor(rgb(0x000000, 0.06))
    ctx.setLineWidth(3)
    var r: CGFloat = 60
    while r < ringInner {
        ctx.strokeEllipse(in: circle(centre, r))
        r += 46
    }
    ctx.restoreGState()
    // Bevel: light from above.
    ctx.saveGState()
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.35))
    ctx.setLineWidth(6)
    ctx.addArc(center: centre, radius: ringInner - 5, startAngle: .pi * 0.15, endAngle: .pi * 0.85, clockwise: false)
    ctx.strokePath()
    ctx.setStrokeColor(rgb(0x000000, 0.22))
    ctx.addArc(center: centre, radius: ringInner - 5, startAngle: .pi * 1.15, endAngle: .pi * 1.85, clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()

    // The glyph.
    ctx.saveGState()
    ctx.translateBy(x: centre.x, y: centre.y)
    badge.draw(ctx)
    ctx.restoreGState()
}

func makeContext(_ w: Int, _ h: Int) -> CGContext {
    // noneSkipLast: opaque RGB, no alpha channel in the written PNG.
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw NSError(domain: "badges", code: 1, userInfo: [NSLocalizedDescriptionKey: "cannot create \(url.path)"])
    }
    let props: [CFString: Any] = [kCGImagePropertyDPIWidth: 72, kCGImagePropertyDPIHeight: 72]
    CGImageDestinationAddImage(dest, image, props as CFDictionary)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "badges", code: 2, userInfo: [NSLocalizedDescriptionKey: "cannot write \(url.path)"])
    }
}

/// Reads back a PNG's IHDR: (width, height, colour type). Colour type 2 = RGB (no alpha), 6 = RGBA.
func pngHeader(_ url: URL) -> (Int, Int, UInt8)? {
    guard let data = try? Data(contentsOf: url), data.count > 26 else { return nil }
    let b = [UInt8](data.prefix(32))
    guard b[0] == 0x89, b[1] == 0x50, b[12] == 0x49, b[13] == 0x48, b[14] == 0x44, b[15] == 0x52 else { return nil }
    let w = Int(b[16]) << 24 | Int(b[17]) << 16 | Int(b[18]) << 8 | Int(b[19])
    let h = Int(b[20]) << 24 | Int(b[21]) << 16 | Int(b[22]) << 8 | Int(b[23])
    return (w, h, b[25])
}

// MARK: - ID verification

var problems: [String] = []

func snakeCase(_ camel: String) -> String {
    camel.reduce(into: "") { out, ch in
        if ch.isUppercase { out += "_" + ch.lowercased() } else { out.append(ch) }
    }
}

func contractIDs() -> [String]? {
    let url = repoRoot.appendingPathComponent("Squish/Shared/Contracts.swift")
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
    var inEnum = false
    for line in text.components(separatedBy: .newlines) {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("enum Achievement:") || t.hasPrefix("enum Achievement ") { inEnum = true; continue }
        if inEnum && t.hasPrefix("case ") {
            return t.dropFirst(5).split(separator: ",").map {
                "com.pravegm.squish.ach." + snakeCase($0.trimmingCharacters(in: .whitespaces))
            }
        }
    }
    return nil
}

func docIDs() -> [String]? {
    let url = repoRoot.appendingPathComponent("docs/appstore/achievements.md")
    guard var text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
    if let cut = text.range(of: "## Reserved") { text = String(text[..<cut.lowerBound]) }
    guard let re = try? NSRegularExpression(pattern: "com\\.pravegm\\.squish\\.ach\\.[a-z_]+") else { return nil }
    var seen: [String] = []
    for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
        if let r = Range(m.range, in: text) {
            let id = String(text[r])
            if !seen.contains(id) { seen.append(id) }
        }
    }
    return seen
}

func metadataIDs() -> [(id: String, image: String?)]? {
    let url = repoRoot.appendingPathComponent("docs/appstore/asc-metadata.json")
    guard let data = try? Data(contentsOf: url) else { return nil }
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let list = obj["achievements"] as? [[String: Any]] else {
        problems.append("docs/appstore/asc-metadata.json exists but its achievements array can't be read")
        return []
    }
    return list.map { ($0["vendorIdentifier"] as? String ?? "", $0["image"] as? String) }
}

func compare(_ name: String, _ ids: [String]?, required: Bool) {
    let mine = Set(badges.map { $0.vendorIdentifier })
    guard let ids = ids else {
        if required { problems.append("\(name): not found or unreadable") } else { print("  \(name): not present, skipped") }
        return
    }
    let theirs = Set(ids)
    let missing = mine.subtracting(theirs).sorted()
    let extra = theirs.subtracting(mine).sorted()
    if missing.isEmpty && extra.isEmpty && ids.count == theirs.count {
        print("  \(name): \(ids.count) IDs match")
    } else {
        if !missing.isEmpty { problems.append("\(name) lacks: \(missing.joined(separator: ", "))") }
        if !extra.isEmpty { problems.append("\(name) has unknown IDs: \(extra.joined(separator: ", "))") }
        if ids.count != theirs.count { problems.append("\(name) lists an ID twice") }
    }
}

print("Verifying achievement IDs (repo: \(repoRoot.path))")
compare("Squish/Shared/Contracts.swift (Achievement.gameCenterID)", contractIDs(), required: true)
compare("docs/appstore/achievements.md", docIDs(), required: true)
if let meta = metadataIDs() {
    compare("docs/appstore/asc-metadata.json", meta.map { $0.id }, required: false)
    for entry in meta {
        let expected = "tools/appstore/badges/\(entry.id).png"
        if let image = entry.image, image != expected {
            print("  note: asc-metadata.json image for \(entry.id) is \(image) (this script writes \(expected))")
        }
    }
} else {
    print("  docs/appstore/asc-metadata.json: not present yet, skipped")
}

// MARK: - Render

do {
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
} catch {
    problems.append("cannot create \(outDir.path): \(error.localizedDescription)")
}

var rendered: [(Badge, CGImage)] = []
for badge in badges {
    let ctx = makeContext(Int(size), Int(size))
    drawBadge(badge, in: ctx)
    guard let image = ctx.makeImage() else { problems.append("\(badge.snake): render failed"); continue }
    let url = outDir.appendingPathComponent("\(badge.vendorIdentifier).png")
    do {
        try writePNG(image, to: url)
        if let header = pngHeader(url) {
            let (w, h, colourType) = header
            let ok = w == 1024 && h == 1024 && colourType == 2
            print("  \(ok ? "ok " : "BAD") \(url.lastPathComponent)  \(w)x\(h)  colour type \(colourType)\(colourType == 2 ? " (RGB, opaque)" : "")")
            if !ok { problems.append("\(url.lastPathComponent): expected 1024x1024 RGB without alpha") }
        } else {
            problems.append("\(url.lastPathComponent): written but not a readable PNG")
        }
        rendered.append((badge, image))
    } catch {
        problems.append("\(badge.snake): \(error.localizedDescription)")
    }
}

// Contact sheet: 5 x 2 on studio paper.
if rendered.count == badges.count {
    let cell = 320, pad = 40
    let w = 5 * cell + 6 * pad, h = 2 * cell + 3 * pad
    let ctx = makeContext(w, h)
    ctx.setFillColor(paper)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.interpolationQuality = .high
    for (i, item) in rendered.enumerated() {
        let col = i % 5, row = i / 5
        let x = pad + col * (cell + pad)
        let y = h - (pad + (row + 1) * cell + row * pad)
        let rect = CGRect(x: x, y: y, width: cell, height: cell)
        // Game Center shows the art in a circle: preview it that way.
        ctx.saveGState()
        ctx.addEllipse(in: rect)
        ctx.clip()
        ctx.draw(item.1, in: rect)
        ctx.restoreGState()
    }
    if let sheet = ctx.makeImage() {
        let url = outDir.appendingPathComponent("preview.png")
        do { try writePNG(sheet, to: url); print("  preview: \(url.path)") } catch { problems.append("preview: \(error.localizedDescription)") }
    }
}

if problems.isEmpty {
    print("Done: \(rendered.count) badges in \(outDir.path)")
} else {
    for p in problems { FileHandle.standardError.write("error: \(p)\n".data(using: .utf8)!) }
    exit(1)
}
