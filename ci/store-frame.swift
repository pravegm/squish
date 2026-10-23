// Squish App Store frame compositor (host side, macOS). Puts a store caption on a raw simulator screenshot, in the
// caption system of docs/appstore/screenshots.md and FoldStoreShot.drawCaption (same band, sizes and shrink rule).
//
//   store-frame --in raw.png --out frame.png --caption "A shelf of pressed *specimens*. / No ads. No in-app purchases."
//               [--size 2007x2853] [--style framed|overlay] [--ink dark|light]
//
//  • framed (default): studio sweep, caption in the top band, the screenshot (unaltered, scaled to fit) on a black
//    rounded screen card with a soft shadow below it. For frames whose top has content (Shelf, Settings, 6.9" Pinch).
//  • overlay: the screenshot full-bleed (aspect-fill), the caption drawn straight over its top band. For frames whose
//    top ~22 % is empty graphite (the Duo cover's sealed card, FOLD-REVIEW-5 §5 B O1): use `--ink light`.
// " / " starts the SF Mono sub-line; `*word*` is the hydraulic-yellow word. Output: opaque sRGB PNG, no alpha.
// --size defaults to the input's pixel size. Run compiled (`xcrun swiftc -O`) or as a script (`xcrun swift`).
import AppKit
import CoreGraphics
import Foundation
import ImageIO

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("store-frame: " + message + "\n").data(using: .utf8)!)
    exit(1)
}

var options: [String: String] = [:]
var argv = Array(CommandLine.arguments.dropFirst())
while !argv.isEmpty {
    let key = argv.removeFirst()
    guard key.hasPrefix("--"), !argv.isEmpty else { fail("bad argument \(key)") }
    options[String(key.dropFirst(2))] = argv.removeFirst()
}
guard let input = options["in"], let output = options["out"] else { fail("needs --in and --out") }
let style = options["style"] ?? "framed"
let lightInk = options["ink"] == "light"
let rawCaption = options["caption"] ?? ""

guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: input) as CFURL, nil),
      let shot = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("cannot read \(input)") }

var width = shot.width, height = shot.height
if let size = options["size"] {
    let parts = size.lowercased().split(separator: "x").compactMap { Int($0) }
    guard parts.count == 2, parts[0] > 64, parts[1] > 64 else { fail("bad --size \(size)") }
    width = parts[0]
    height = parts[1]
}
let W = CGFloat(width), H = CGFloat(height)

guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fail("no context") }
ctx.interpolationQuality = .high

func srgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// A top-left-origin rect → Core Graphics' bottom-left origin.
func cgRect(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: H - r.maxY, width: r.width, height: r.height) }

// MARK: Background and screenshot (Core Graphics coordinates, before the flip for text)

if style == "overlay" {
    // Aspect-fill the frame.
    let scale = max(W / CGFloat(shot.width), H / CGFloat(shot.height))
    let w = CGFloat(shot.width) * scale, h = CGFloat(shot.height) * scale
    ctx.setFillColor(srgb(0x2B2D31))
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    ctx.draw(shot, in: CGRect(x: (W - w) / 2, y: (H - h) / 2, width: w, height: h))
} else {
    // Studio sweep #EDE5D8 → #F3EEE6 → #F1E9DC, top to bottom (FoldStoreShot.drawBackdrop .studio).
    let sweep = [srgb(0xEDE5D8), srgb(0xF3EEE6), srgb(0xF1E9DC)] as CFArray
    if let gradient = CGGradient(colorsSpace: space, colors: sweep, locations: [0, 0.55, 1]) {
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])
    }
    // The screen card: fitted into the box under the caption band, bottom-weighted.
    let box = CGRect(x: W * 0.08, y: H * 0.215, width: W * 0.84, height: H * 0.755)
    let bezel = min(box.width, box.height) * 0.018
    let inner = box.insetBy(dx: bezel, dy: bezel)
    let scale = min(inner.width / CGFloat(shot.width), inner.height / CGFloat(shot.height))
    let w = CGFloat(shot.width) * scale, h = CGFloat(shot.height) * scale
    let screen = CGRect(x: inner.midX - w / 2, y: inner.maxY - h, width: w, height: h)   // top-left origin
    let card = screen.insetBy(dx: -bezel, dy: -bezel)
    let radius = card.width * 0.055
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -H * 0.008), blur: H * 0.025, color: srgb(0x3B2F25, 0.30))
    ctx.addPath(CGPath(roundedRect: cgRect(card), cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setFillColor(srgb(0x0D0E10))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    let screenRadius = max(radius - bezel, 1)
    ctx.addPath(CGPath(roundedRect: cgRect(screen), cornerWidth: screenRadius, cornerHeight: screenRadius, transform: nil))
    ctx.clip()
    ctx.draw(shot, in: cgRect(screen))
    ctx.restoreGState()
}

// MARK: Caption (flipped, top-left origin, so AppKit lays text out top-down)

let ink = lightInk ? NSColor(srgbRed: 0xF3 / 255.0, green: 0xEE / 255.0, blue: 0xE6 / 255.0, alpha: 1)
                   : NSColor(srgbRed: 0x2B / 255.0, green: 0x2D / 255.0, blue: 0x31 / 255.0, alpha: 1)
let highlight = NSColor(srgbRed: 0xFF / 255.0, green: 0xB8 / 255.0, blue: 0x1C / 255.0, alpha: 1)

func roundedFont(_ size: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: .heavy)
    if let descriptor = base.fontDescriptor.withDesign(.rounded), let font = NSFont(descriptor: descriptor, size: size) {
        return font
    }
    return base
}

func headline(_ text: String, size: CGFloat, breakSentences: Bool) -> NSAttributedString {
    var source = text
    if breakSentences, let range = source.range(of: ". ") { source.replaceSubrange(range, with: ".\n") }
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byWordWrapping
    paragraph.lineHeightMultiple = 0.92
    let font = roundedFont(size)
    let result = NSMutableAttributedString()
    for (index, piece) in source.components(separatedBy: "*").enumerated() where !piece.isEmpty {
        result.append(NSAttributedString(string: piece, attributes: [
            .font: font, .foregroundColor: index % 2 == 1 ? highlight : ink, .paragraphStyle: paragraph,
        ]))
    }
    return result
}

func subline(_ text: String, size: CGFloat) -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byWordWrapping
    return NSAttributedString(string: text.replacingOccurrences(of: "*", with: ""), attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: size * 0.40, weight: .semibold),
        .foregroundColor: ink.withAlphaComponent(0.72),
        .paragraphStyle: paragraph,
    ])
}

if !rawCaption.isEmpty {
    let parts = rawCaption.components(separatedBy: " / ")
    let head = parts[0]
    let sub: String? = parts.count > 1 ? parts.dropFirst().joined(separator: " / ") : nil
    let band = CGRect(x: W * 0.06, y: H * 0.03, width: W * 0.88, height: H * 0.165)
    func measure(_ string: NSAttributedString) -> CGSize {
        let r = string.boundingRect(with: CGSize(width: band.width, height: .greatestFiniteMagnitude),
                                    options: [.usesLineFragmentOrigin, .usesFontLeading])
        return CGSize(width: ceil(r.width), height: ceil(r.height))
    }
    let minimum = H * 0.036
    var fontSize = H * 0.064
    let breakSentences = headline(head, size: fontSize, breakSentences: false).size().width > band.width
    var title = headline(head, size: fontSize, breakSentences: breakSentences)
    var second = sub.map { subline($0, size: fontSize) }
    while fontSize > minimum {
        let total = measure(title).height + (second.map { measure($0).height + fontSize * 0.30 } ?? 0)
        if total <= band.height { break }
        fontSize = max(minimum, fontSize * 0.95)
        title = headline(head, size: fontSize, breakSentences: breakSentences)
        second = sub.map { subline($0, size: fontSize) }
    }
    let titleSize = measure(title)
    let secondSize = second.map { measure($0) } ?? .zero
    let gap = second == nil ? 0 : fontSize * 0.30

    ctx.saveGState()
    ctx.translateBy(x: 0, y: H)
    ctx.scaleBy(x: 1, y: -1)
    let graphics = NSGraphicsContext(cgContext: ctx, flipped: true)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    var y = max(band.minY, band.midY - (titleSize.height + gap + secondSize.height) / 2)
    title.draw(with: CGRect(x: band.minX, y: y, width: band.width, height: titleSize.height + 2),
               options: [.usesLineFragmentOrigin, .usesFontLeading])
    y += titleSize.height + gap
    second?.draw(with: CGRect(x: band.minX, y: y, width: band.width, height: secondSize.height + 2),
                 options: [.usesLineFragmentOrigin, .usesFontLeading])
    NSGraphicsContext.restoreGraphicsState()
    ctx.restoreGState()
}

guard let flat = ctx.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL, "public.png" as CFString,
                                                        1, nil) else { fail("cannot create \(output)") }
CGImageDestinationAddImage(destination, flat, nil)
guard CGImageDestinationFinalize(destination) else { fail("cannot write \(output)") }
print("store-frame: \(output) \(width)x\(height) style=\(style)\(rawCaption.isEmpty ? "" : " captioned")")
