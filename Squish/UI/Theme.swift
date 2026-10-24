import SwiftUI
import UIKit

/// The single place every screen gets its look from. Values follow design/VISUAL-TARGET.md §6
/// (bible §5 "tactile industrial-lite"). Screens never hard-code colour, type, depth or motion.
enum Theme {
    // MARK: - Colour tokens (§6.2)

    static let backdrop = rgb(0xF3EEE6)
    static let paper = rgb(0xFBF8F1)
    static let paperWarm = rgb(0xF4ECDD)
    static let paperShade = rgb(0xE5DCCB)
    static let paperEdge = rgb(0xD9CEBA)
    static let graphite = rgb(0x2B2D31)
    static let graphiteRaised = rgb(0x3A3D43)
    static let ink = rgb(0x2B2D31)
    /// Darkens under Increase Contrast (§6.13).
    static let inkSecondary = dynamic(normal: 0x5E6067, increased: 0x4A4C52)
    /// Glyphs and decoration only; never small text (fails 4.5:1 on paper).
    static let inkTertiary = rgb(0x85878D)
    static let yellow = rgb(0xFFB81C)
    static let yellowLip = rgb(0xC98A00)
    static let yellowSoft = rgb(0xFFE3A1)
    static let stamp = rgb(0xD7263D)
    static let gold = rgb(0xC8921A)
    static let goldSoft = rgb(0xF6E2A8)
    /// Every shadow, never black.
    static let shadowInk = rgb(0x3B2F25)
    static let console = rgb(0x3A3D43)
    static let consoleLip = rgb(0x141518)   // darker than VT #1E2023 so the lip reads on the graphite bed (VISUAL-REVIEW-1 #14)
    static let lampGreen = rgb(0x39D98A)
    static let lampRed = rgb(0xFF3B4E)
    static let floorNear = rgb(0xF1E9DC)
    static let floorPool = rgb(0xF8F3EA)
    static let wallBase = rgb(0xEDE5D8)
    static let steel = rgb(0x8A8F98)

    /// Hero tint per object (§3.4 table).
    static func tint(for kind: ObjectKind) -> Color {
        switch kind {
        case .bubbleWrap: rgb(0x8FCBE8)
        case .rubberDuck: rgb(0xFFD23F)
        case .jelly: rgb(0xE8336F)
        case .crayon: rgb(0x2F5BEA)
        case .egg: rgb(0xF2D9A6)
        case .cakeSlice: rgb(0xF59BB5)
        case .sodaCan: rgb(0x8BD448)
        case .gummyBear: rgb(0xFF5A4E)
        case .glassBottle: rgb(0x5CC8B8)
        case .unsquishable: rgb(0x8A8F98)
        }
    }

    /// Complementary pastel "gel wall" behind the press (§3.4). SwiftUI fills behind the RealityView with it.
    static func gel(for kind: ObjectKind, golden: Bool = false) -> Color {
        if golden { return rgb(0xF3E6C4) }
        switch kind {
        case .bubbleWrap: return rgb(0xF6E3D3)
        case .rubberDuck: return rgb(0xDDE3F3)
        case .jelly: return rgb(0xD9EEE4)
        case .crayon: return rgb(0xF7DFCF)
        case .egg: return rgb(0xD8E8F2)
        case .cakeSlice: return rgb(0xE1EDD6)
        case .sodaCan: return rgb(0xE8DDF0)
        case .gummyBear: return rgb(0xD5ECEC)
        case .glassBottle: return rgb(0xF4DDDA)
        case .unsquishable: return rgb(0xF5EACB)
        }
    }

    /// Caption fill: the object's tint; light objects use hydraulic yellow (§6.10).
    static func captionFill(for kind: ObjectKind) -> Color {
        switch kind {
        case .bubbleWrap, .egg, .glassBottle, .unsquishable, .rubberDuck: yellow
        case .jelly, .crayon, .cakeSlice, .sodaCan, .gummyBear: tint(for: kind)
        }
    }

    // MARK: - Grid (§6.1: 8 pt)

    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 24
    static let s6: CGFloat = 32
    static let s7: CGFloat = 48
    static let hit: CGFloat = 44
    static func margin(landscape: Bool) -> CGFloat { landscape ? 24 : 16 }

    // MARK: - Radii

    static let cardRadius: CGFloat = 22
    static let slotRadius: CGFloat = 18
    static let sectionRadius: CGFloat = 18
    static let stickerRadius: CGFloat = 14
    static let toastRadius: CGFloat = 14
    static let sheetRadius: CGFloat = 28
    static let chipRadius: CGFloat = 9

    // MARK: - Type scale (§6.3). Text styles whose default sizes match the scale, so Dynamic Type works.

    /// Card-detail name: Rounded Heavy 28.
    static var display: Font { .system(.title, design: .rounded, weight: .heavy) }
    /// Sheet titles: Rounded Heavy 22.
    static var sheetTitle: Font { .system(.title2, design: .rounded, weight: .heavy) }
    /// Compact card name, slot names: Rounded Heavy 20.
    static var headline: Font { .system(.title3, design: .rounded, weight: .heavy) }
    /// Keycap labels: Rounded Heavy 17.
    static var button: Font { .system(.body, design: .rounded, weight: .heavy) }
    /// Body: Rounded Semibold 17.
    static var body: Font { .system(.body, design: .rounded, weight: .semibold) }
    /// Secondary body / footnotes: Rounded Semibold 13.
    static var footnote: Font { .system(.footnote, design: .rounded, weight: .semibold) }
    /// Data labels and chips: SF Mono Medium 12, UPPER, tracking 0.6.
    static var label: Font { .system(.caption, design: .monospaced, weight: .medium) }
    /// Micro (serials, "TONS", hints): SF Mono Semibold ~10–11, UPPER, tracking 1.0.
    static var micro: Font { .system(.caption2, design: .monospaced, weight: .semibold) }
    /// Big numbers (cover tonnage): SF Mono Bold 28.
    static var bigNumber: Font { .system(.title, design: .monospaced, weight: .bold) }
    /// Comic captions: fixed-size Rounded Black (decorative; VoiceOver announces them).
    static func captionFont(size: CGFloat) -> Font { .system(size: size, weight: .black, design: .rounded) }

    static let labelTracking: CGFloat = 0.6
    static let microTracking: CGFloat = 1.0
    static let buttonTracking: CGFloat = 0.2

    // MARK: - Motion (§6.12). Reduce Motion turns movement into short crossfades.

    static let fade = Animation.easeInOut(duration: 0.22)
    static func pop(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? fade : .spring(response: 0.42, dampingFraction: 0.68)
    }
    static func settle(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? fade : .spring(response: 0.5, dampingFraction: 0.86)
    }
    static let keyDown = Animation.spring(response: 0.12, dampingFraction: 0.90)
    static let keyUp = Animation.spring(response: 0.30, dampingFraction: 0.55)
    static func cardDrop(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? fade : .spring(response: 0.50, dampingFraction: 0.62)
    }
    static func stampFall(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? fade : .spring(response: 0.22, dampingFraction: 0.50)
    }
    static func stickerPeel(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? fade : .spring(response: 0.40, dampingFraction: 0.60)
    }
    /// Sheet content: 40 ms per row.
    static func row(_ index: Int, _ reduceMotion: Bool) -> Animation {
        reduceMotion ? fade : .smooth(duration: 0.30).delay(Double(min(index, 12)) * 0.04)
    }
    static let hop = Animation.spring(response: 0.35, dampingFraction: 0.45)
    static let gelCrossfade = Animation.easeInOut(duration: 0.4)

    // MARK: - Helpers

    static func rgb(_ hex: UInt32, opacity: Double = 1) -> Color {
        Color(uiColor: uiColor(hex).withAlphaComponent(opacity))
    }

    static func uiColor(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
    }

    private static func dynamic(normal: UInt32, increased: UInt32) -> Color {
        let a = uiColor(normal), b = uiColor(increased)
        return Color(uiColor: UIColor { traits in traits.accessibilityContrast == .high ? b : a })
    }
}

// MARK: - Screen bands (§6.1)

/// Percent-of-screen layout helper. Bands are measured on the full screen; UI still respects safe areas.
struct ScreenBands {
    /// Local (safe-area) size and insets from a GeometryReader that respects the safe area.
    let size: CGSize
    let insets: EdgeInsets
    /// True on a foldable (a hinge has reported): nothing interactive may cross the crease.
    let hinge: Bool

    init(_ proxy: GeometryProxy, hinge: Bool = false) {
        size = proxy.size
        insets = proxy.safeAreaInsets
        self.hinge = hinge
    }

    /// Half-width of the no-go band around the fold (HIG: nothing interactive in the 40 pt crease).
    static let creaseHalf: CGFloat = 20

    /// The crease in local coordinates. Tabletop (portrait): the horizontal midline ±20 pt; book pose
    /// (landscape): the vertical midline ±20 pt. Assumed from the display geometry; the SwiftUI
    /// division-region API isn't used because we can't verify its iOS 27.1 shape in CI.
    var crease: CGRect? {
        guard hinge else { return nil }
        if isLandscape {
            return CGRect(x: x(0.5) - Self.creaseHalf, y: -insets.top, width: Self.creaseHalf * 2, height: fullHeight)
        }
        return CGRect(x: -insets.leading, y: y(0.5) - Self.creaseHalf, width: fullWidth, height: Self.creaseHalf * 2)
    }

    /// Tabletop only (portrait window, horizontal crease): how far the crease's centre line sits above the bottom of
    /// the safe area. A sheet shares the window's bottom edge and bottom inset, so inside a sheet the crease is at
    /// `sheetSafeHeight - this`, whatever the sheet's top offset or detent (FOLD-REVIEW-7 N5). Nil without a hinge
    /// and in book pose.
    var tabletopCreaseAboveSafeBottom: CGFloat? {
        guard let crease, !isLandscape else { return nil }
        return size.height - crease.midY
    }

    /// The Fold Press bezel for this canvas (crown strip, console band, plates), shared with Scene/Fold.
    var foldLayout: FoldLayout { FoldLayout(canvas: CGSize(width: fullWidth, height: fullHeight)) }

    /// A full-canvas rect (e.g. from `FoldLayout`) in this view's local, safe-area coordinates.
    func local(_ canvasRect: CGRect) -> CGRect {
        canvasRect.offsetBy(dx: -insets.leading, dy: -insets.top)
    }

    /// Fold Press: the one slot for single-line toasts and tips, in local coordinates (see `FoldLayout.toastSlot`).
    var foldToastSlot: CGRect { local(foldLayout.toastSlot) }

    /// Bottom of the top band for overlays (6–44%), kept clear of the crease.
    var topBandBottom: CGFloat {
        let bottom = y(0.44)
        guard let crease, !isLandscape else { return bottom }
        return min(bottom, crease.minY - Theme.s3)
    }

    var fullWidth: CGFloat { size.width + insets.leading + insets.trailing }
    var fullHeight: CGFloat { size.height + insets.top + insets.bottom }
    var isLandscape: Bool { fullWidth > fullHeight }
    var margin: CGFloat { Theme.margin(landscape: isLandscape) }

    /// Local y for a fraction of the full screen height.
    func y(_ fraction: CGFloat) -> CGFloat { fullHeight * fraction - insets.top }
    /// Local x for a fraction of the full screen width.
    func x(_ fraction: CGFloat) -> CGFloat { fullWidth * fraction - insets.leading }
    func height(_ from: CGFloat, _ to: CGFloat) -> CGFloat { fullHeight * (to - from) }
}

extension FoldLayout {
    /// The compact toast's height (`ToastView(compact: true)`).
    static let toastHeight: CGFloat = 48

    /// Fold Press: the one slot (canvas coordinates) for single-line toasts and tips, off the crown strip (gauge,
    /// lamps, hinge readout) and off both strike plates (FOLD-REVIEW-4 F4). Never narrower than 300 pt.
    /// - Book (Duo): the empty graphite foot band of the platen page (`platenFoot`), the console's mirror.
    /// - Tabletop (Duo portrait, and the simulated fold on other iPhones): the platen field between the reveal's
    ///   print label (centred 24 pt under the plate, at most ~46 pt tall) and the crease band.
    var toastSlot: CGRect {
        let height = Self.toastHeight
        if let foot = platenFoot {
            let width = min(max(300, foot.width - Theme.s2 * 2), 420)
            return CGRect(x: foot.midX - width / 2, y: foot.midY - height / 2, width: width, height: height)
        }
        let plate = strikePlate(platen: true)
        let field = platenField
        let top = plate.maxY + 24 + 23 + Theme.s1
        let bottom = creaseRect.minY - Theme.s1
        let centreY = bottom - top >= height ? (top + bottom) / 2 : bottom - height / 2
        let width = min(max(300, field.width - Theme.s2 * 2), 420)
        return CGRect(x: field.midX - width / 2, y: centreY - height / 2, width: width, height: height)
    }
}

// MARK: - UI feel (light taps on controls, respecting the Haptics setting)

@MainActor
enum UIFeel {
    /// Mirrors `AppSettings.hapticsLevel != .off`; set by RootView.
    static var enabled = true
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let notify = UINotificationFeedbackGenerator()

    static func press() { if enabled { rigid.impactOccurred(intensity: 0.55) } }
    static func tick() { if enabled { light.impactOccurred(intensity: 0.6) } }
    static func success() { if enabled { notify.notificationOccurred(.success) } }
}

// MARK: - Elevation (§6.4). All shadows in shadowInk.

enum Elevation { case e0, e1, e2, e3 }

private struct ElevationModifier: ViewModifier {
    let level: Elevation
    var pressed = false

    @ViewBuilder
    func body(content: Content) -> some View {
        switch level {
        case .e0:
            content
        case .e1:
            content
                .shadow(color: Theme.shadowInk.opacity(0.18), radius: 0, y: pressed ? 1 : 2)
                .shadow(color: Theme.shadowInk.opacity(0.10), radius: pressed ? 3 : 6, y: pressed ? 1.5 : 3)
        case .e2:
            content
                .shadow(color: Theme.shadowInk.opacity(0.10), radius: 1, y: 1)
                .shadow(color: Theme.shadowInk.opacity(0.16), radius: 14, y: 8)
        case .e3:
            content
                .shadow(color: Theme.shadowInk.opacity(0.18), radius: 0, y: 2)
                .shadow(color: Theme.shadowInk.opacity(0.10), radius: 6, y: 3)
                .shadow(color: Theme.shadowInk.opacity(0.22), radius: 24, y: 14)
        }
    }
}

extension View {
    func elevation(_ level: Elevation, pressed: Bool = false) -> some View {
        modifier(ElevationModifier(level: level, pressed: pressed))
    }

    /// The 1 pt top inner highlight on every raised surface (§6.4).
    func topHighlight(cornerRadius: CGFloat, opacity: Double = 0.65) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Color.white.opacity(opacity), .clear],
                                             startPoint: .top, endPoint: .center), lineWidth: 1)
        )
    }

    /// Caps Dynamic Type where a fixed composition (cards, stamps) would otherwise break.
    func cardTypeCap(_ limit: DynamicTypeSize = .accessibility1) -> some View {
        dynamicTypeSize(...limit)
    }

    /// Sheets support Dynamic Type up to AX3 (§6.3).
    func sheetTypeCap() -> some View {
        dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }
}

// MARK: - Paper (§6.5)

/// Procedural textures, generated once.
@MainActor
enum Textures {
    /// 256² luminance grain, near-white so `multiply` darkens by 0–6% (±3% around the mean at 0.5 opacity).
    static let paperGrain: UIImage = noise(seed: 0x6A1A, low: 239, high: 255, blotch: false)
    /// 256² ink mask for the stamp: alpha 0.75–1.0 with soft blotches, so the stamp reads printed.
    static let inkMask: UIImage = noise(seed: 0x57A3, low: 191, high: 255, blotch: true)

    private static func noise(seed: UInt64, low: Int, high: Int, blotch: Bool) -> UIImage {
        let side = 256
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let data = context.data else { return UIImage() }
        let buffer = data.bindMemory(to: UInt8.self, capacity: side * side)
        var rng = SplitMix64(seed: seed)
        // Coarse 16² blotch field, bilinearly sampled, for ink.
        var coarse = [Double](repeating: 1, count: 17 * 17)
        if blotch {
            for i in coarse.indices { coarse[i] = Double.random(in: 0...1, using: &rng) }
        }
        let range = Double(high - low)
        for y in 0..<side {
            for x in 0..<side {
                var value = Double.random(in: 0...1, using: &rng)
                if blotch {
                    let fx = Double(x) / 16, fy = Double(y) / 16
                    let ix = Int(fx), iy = Int(fy)
                    let tx = fx - Double(ix), ty = fy - Double(iy)
                    let a = coarse[iy * 17 + ix], b = coarse[iy * 17 + ix + 1]
                    let c = coarse[(iy + 1) * 17 + ix], d = coarse[(iy + 1) * 17 + ix + 1]
                    let field = (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty
                    value = 0.55 * field + 0.45 * value
                }
                buffer[y * side + x] = UInt8(clamping: low + Int(value * range))
            }
        }
        guard let image = context.makeImage() else { return UIImage() }
        return UIImage(cgImage: image, scale: 2, orientation: .up)
    }
}

/// Paper stock: a flat tone with tiled grain multiplied in (§6.5).
struct PaperBackground: View {
    var tone: Color = Theme.paper

    var body: some View {
        ZStack {
            tone
            Image(uiImage: Textures.paperGrain)
                .resizable(resizingMode: .tile)
                .blendMode(.multiply)
                .opacity(0.5)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Keycaps (§6.6): the one button language

struct KeycapStyle: ButtonStyle {
    enum Kind { case primary, secondary, console, chip, destructive }
    var kind: Kind = .primary
    var fullWidth = false
    /// A round 44 pt key for icon-only actions (close, settings).
    var round = false
    /// Chips only: the selected chip (tabs, segmented choices, the object on the anvil).
    var selected = false
    /// 44 pt keys for the Fold Press console band (62 pt), whatever the kind (FOLD-REVIEW-1 #5).
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        KeycapFace(configuration: configuration, kind: kind, fullWidth: fullWidth, round: round, selected: selected,
                   compact: compact)
    }
}

private struct KeycapFace: View {
    let configuration: ButtonStyleConfiguration
    let kind: KeycapStyle.Kind
    let fullWidth: Bool
    let round: Bool
    let selected: Bool
    let compact: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let pressed = configuration.isPressed && isEnabled
        let lipHeight = isEnabled ? lip : 0
        let travel = pressed ? lipHeight - 1 : 0
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        configuration.label
            .font(kind == .chip ? Theme.label : Theme.button)
            .tracking(kind == .chip ? Theme.labelTracking : Theme.buttonTracking)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(isEnabled ? labelColor : Theme.inkSecondary)
            .padding(.horizontal, round ? 0 : (kind == .chip ? Theme.s3 + 2 : Theme.s4 + 2))
            .frame(width: round ? height : nil)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height)
            // The label rides with the face; the lip stays put.
            .offset(y: travel)
            .scaleEffect(pressed ? 0.985 : 1)
            // Shadows live on the shapes only, never on the label (VISUAL-REVIEW-1 #5: no text ghost-shadow).
            .background {
                ZStack {
                    shape.fill(lipColor).offset(y: lipHeight)
                    shape.fill(isEnabled ? face : Theme.paperShade.opacity(0.7))
                        .overlay(
                            shape.strokeBorder(LinearGradient(colors: [highlight, .clear], startPoint: .top, endPoint: .center),
                                               lineWidth: 1)
                        )
                        .overlay {
                            if contrast == .increased {
                                shape.strokeBorder(Theme.graphite.opacity(0.4), lineWidth: 1)
                            }
                        }
                        .overlay {
                            // A selected chip is never told apart by colour alone: a graphite outline (well over 3:1
                            // against paper) marks it (Accessibility Nutrition Labels: Differentiate Without Color,
                            // Sufficient Contrast; docs/appstore/accessibility.md).
                            if kind == .chip && selected {
                                shape.strokeBorder(Theme.graphite, lineWidth: 2)
                            }
                        }
                        .offset(y: travel)
                        .scaleEffect(pressed ? 0.985 : 1)
                }
                .elevation(isEnabled ? .e1 : .e0, pressed: pressed)
            }
            .padding(.bottom, lipHeight)
            .padding(.vertical, kind == .chip ? 2.5 : 0) // 36 + 3 lip + 5 = 44 pt target
            .contentShape(Rectangle())
            .accessibilityAddTraits(kind == .chip && selected ? .isSelected : [])
            .animation(reduceMotion ? nil : (pressed ? Theme.keyDown : Theme.keyUp), value: pressed)
            .onChange(of: pressed) { _, isDown in
                if isDown { UIFeel.press() }
            }
    }

    private var height: CGFloat {
        if round { return Theme.hit }
        if compact && kind != .chip { return Theme.hit }
        switch kind {
        case .primary: return 52
        case .secondary, .destructive: return 48
        case .console: return 44
        case .chip: return 36
        }
    }
    private var radius: CGFloat {
        if round { return Theme.hit / 2 }
        if compact && kind != .chip { return 14 }
        switch kind {
        case .primary, .secondary, .destructive: return 16
        case .console: return 14
        case .chip: return 18
        }
    }
    private var lip: CGFloat { kind == .chip ? 3 : 4 }
    /// Top inner highlight: white on light keys; a 1 pt #4A4E56 line on dark console keys (VISUAL-REVIEW-1 #14).
    private var highlight: Color {
        kind == .console ? Theme.rgb(0x4A4E56) : Color.white.opacity(0.65)
    }
    private var face: Color {
        switch kind {
        case .primary: Theme.yellow
        case .chip: selected ? Theme.yellowSoft : Theme.paper
        case .secondary, .destructive: Theme.paper
        case .console: Theme.console
        }
    }
    private var lipColor: Color {
        switch kind {
        case .primary: Theme.yellowLip
        case .chip: selected ? Theme.yellowLip : Theme.paperEdge
        case .secondary, .destructive: Theme.paperEdge
        case .console: Theme.consoleLip
        }
    }
    private var labelColor: Color {
        switch kind {
        case .primary, .secondary, .chip: Theme.graphite
        case .console: Theme.paper
        case .destructive: Theme.stamp
        }
    }
}

/// Icon + title for keycaps: SF Symbol at semibold, ~0.9 × the label size. Actions only — never objects.
struct KeyLabel: View {
    let title: String
    let systemImage: String
    var iconTrailing = false

    var body: some View {
        HStack(spacing: Theme.s2) {
            if !iconTrailing { icon }
            Text(title)
            if iconTrailing { icon }
        }
    }

    private var icon: some View {
        Image(systemName: systemImage)
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
    }
}

/// Plain tap feedback for stickers and rows: sinks slightly, no chrome.
struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TileFace(configuration: configuration)
    }
}

private struct TileFace: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : (configuration.isPressed ? Theme.keyDown : Theme.keyUp), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isDown in
                if isDown { UIFeel.tick() }
            }
    }
}

// MARK: - Stamp, seal, sparkles (§6.8)

/// The red PRESSED stamp: double border (2.5 pt / 2 pt gap / 1 pt), Rounded Black 20 tracking 2, the date
/// in Mono 9 below, seeded −9…+9° rotation, 0.88 opacity, ink-textured.
struct PressedStamp: View {
    var seed: UInt64
    var text = "PRESSED"
    var date: Date?
    /// Fixed rotation (the Unsquishable's stamp sits at −4°).
    var fixedAngle: Double?

    var angle: Double { fixedAngle ?? (Double(seed % 19) - 9) }

    var body: some View {
        let outer = RoundedRectangle(cornerRadius: 7, style: .continuous)
        let inner = RoundedRectangle(cornerRadius: 4, style: .continuous)
        VStack(spacing: 1) {
            Text(text)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .tracking(2)
                .lineLimit(1)
                .fixedSize()
            if let date {
                Text(date.formatted(.dateTime.day(.twoDigits).month(.abbreviated).year()).uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1)
            }
        }
        .foregroundStyle(Theme.stamp)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .overlay(inner.strokeBorder(Theme.stamp, lineWidth: 1))
        .padding(2 + 2.5)
        .overlay(outer.strokeBorder(Theme.stamp, lineWidth: 2.5))
        // Ink texture: an untransformed tile, so it always covers the whole stamp. (A rotated mask left the
        // corners uncovered and clipped the letters — "PRESSEL", VISUAL-REVIEW-1 #13.)
        .mask {
            Image(uiImage: Textures.inkMask)
                .resizable(resizingMode: .tile)
                .luminanceToAlpha()
        }
        .padding(4) // room for the outer ring so no ancestor can shave it
        .opacity(0.88)
        .rotationEffect(.degrees(angle))
        .accessibilityHidden(true)
    }
}

/// The Perfect Squish seal: Ø 44 yellow with a yellowLip ring and "PERFECT" in Mono 8 around it.
struct PerfectSeal: View {
    private let letters = Array("PERFECT · SQUISH · ")

    var body: some View {
        ZStack {
            Circle().fill(Theme.yellow).elevation(.e1)
            Circle().strokeBorder(Theme.yellowLip, lineWidth: 2.5)
            ForEach(Array(letters.enumerated()), id: \.offset) { index, letter in
                Text(String(letter))
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.graphite)
                    .offset(y: -15.5)
                    .rotationEffect(.degrees(Double(index) * 360 / Double(letters.count)))
            }
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.graphite)
        }
        .frame(width: 44, height: 44)
        .rotationEffect(.degrees(-12))
        .accessibilityHidden(true)
    }
}

/// A four-point sparkle for golden cards.
struct Sparkle: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let k = r * 0.22
        var path = Path()
        path.move(to: CGPoint(x: c.x, y: c.y - r))
        path.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + k, y: c.y - k))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + k, y: c.y + k))
        path.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - k, y: c.y + k))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - k, y: c.y - k))
        path.closeSubpath()
        return path
    }
}

// MARK: - Chips and toasts

/// A trait chip (PERFECT SQUISH, GOLDEN, surprise, SLAM): Mono 12, upper case.
struct TraitChip: View {
    let text: String
    let systemImage: String
    var tone: SpecimenRecord.Trait.Tone = .neutral

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(.caption2, weight: .semibold))
            Text(text)
                .tracking(Theme.labelTracking)
        }
        .font(Theme.label)
        .foregroundStyle(foreground)
        .padding(.horizontal, Theme.s2 + 2)
        .padding(.vertical, 5)
        .background(background, in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous).strokeBorder(border, lineWidth: 1))
    }

    private var foreground: Color {
        switch tone {
        case .perfect, .surprise: Theme.ink
        case .golden: Theme.rgb(0x6B4A00)
        case .neutral: Theme.inkSecondary
        }
    }
    private var background: Color {
        switch tone {
        case .perfect: Theme.yellowSoft
        case .golden: Theme.goldSoft
        case .surprise: Theme.rgb(0xDCEBFA)
        case .neutral: Theme.paperWarm
        }
    }
    private var border: Color {
        switch tone {
        case .perfect: Theme.yellow.opacity(0.6)
        case .golden: Theme.gold.opacity(0.7)
        case .surprise: Theme.rgb(0x9CC2EA)
        case .neutral: Theme.paperEdge
        }
    }
}

/// Toasts (80–86% band, one at a time): paper card, accent rail, E3.
struct ToastView: View {
    enum Glyph {
        case symbol(String)
        case object(ObjectKind)
    }

    let title: String
    let detail: String
    let glyph: Glyph
    var accent: Color = Theme.yellow
    /// One line each for title and detail, ≤ 52 pt tall (the Fold Press toast slot, `FoldLayout.toastSlot`).
    var compact = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.toastRadius, style: .continuous)
        HStack(spacing: Theme.s3) {
            // A fixed-height rail: an unbounded Capsule grew the toast to ~411 pt in book pose (FOLD-REVIEW-1 #4).
            Capsule()
                .fill(accent)
                .frame(width: 4, height: 32)
            glyphView
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.micro)
                    .tracking(Theme.microTracking)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                Text(detail)
                    .font(compact ? Theme.footnote : Theme.body)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(compact ? 1 : 2)
            }
            .minimumScaleFactor(0.7)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.leading, Theme.s2)
        .padding(.trailing, Theme.s4)
        .padding(.vertical, Theme.s1 + 2)
        .frame(minWidth: 300, minHeight: compact ? 48 : 52)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .background { PaperBackground().clipShape(shape).elevation(.e3) }
        .topHighlight(cornerRadius: Theme.toastRadius)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var glyphView: some View {
        switch glyph {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.graphite)
                .frame(width: 32, height: 32)
                .background(accent.opacity(0.35), in: Circle())
        case .object(let kind):
            ObjectSilhouette(kind: kind)
                .fill(Theme.tint(for: kind))
                .padding(3)
                .background(Theme.gel(for: kind), in: Circle())
        }
    }
}

// MARK: - Objects (§6.6: objects never get an SF Symbol)

/// A 10 pt tint dot that stands for an object next to its name.
struct TintDot: View {
    let kind: ObjectKind
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(Theme.tint(for: kind))
            .overlay(Circle().strokeBorder(Theme.shadowInk.opacity(0.18), lineWidth: 1))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A simple, friendly silhouette per object, drawn in a unit square (used for embossed locked slots,
/// unpressed stickers and the "before" panel of share images).
struct ObjectSilhouette: Shape {
    let kind: ObjectKind

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + x * side, y: origin.y + y * side) }
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: origin.x + x * side, y: origin.y + y * side, width: w * side, height: h * side)
        }
        var path = Path()
        switch kind {
        case .bubbleWrap:
            path.addRoundedRect(in: r(0.12, 0.12, 0.76, 0.76), cornerSize: CGSize(width: side * 0.08, height: side * 0.08))
        case .rubberDuck:
            path.addEllipse(in: r(0.10, 0.46, 0.72, 0.42))
            path.addEllipse(in: r(0.44, 0.14, 0.38, 0.38))
            path.addEllipse(in: r(0.74, 0.30, 0.20, 0.11))
            path.move(to: p(0.08, 0.40))
            path.addQuadCurve(to: p(0.30, 0.56), control: p(0.10, 0.58))
            path.addLine(to: p(0.18, 0.62))
            path.closeSubpath()
        case .jelly:
            path.move(to: p(0.12, 0.86))
            path.addLine(to: p(0.88, 0.86))
            path.addQuadCurve(to: p(0.74, 0.30), control: p(0.86, 0.50))
            path.addQuadCurve(to: p(0.26, 0.30), control: p(0.50, 0.12))
            path.addQuadCurve(to: p(0.12, 0.86), control: p(0.14, 0.50))
            path.closeSubpath()
        case .crayon:
            // A crayon box: seven crayons standing in an open box, tips up at staggered heights.
            let tips: [CGFloat] = [0.22, 0.14, 0.19, 0.10, 0.17, 0.13, 0.21]
            for (index, top) in tips.enumerated() {
                let x = 0.19 + CGFloat(index) * 0.088
                path.addRect(r(x, top + 0.07, 0.07, 0.40 - top))
                path.move(to: p(x, top + 0.075))
                path.addLine(to: p(x + 0.035, top))
                path.addLine(to: p(x + 0.07, top + 0.075))
                path.closeSubpath()
            }
            path.addRoundedRect(in: r(0.14, 0.44, 0.72, 0.46), cornerSize: CGSize(width: side * 0.05, height: side * 0.05))
            // The box's front flap, cut lower in the middle.
            path.move(to: p(0.14, 0.44))
            path.addQuadCurve(to: p(0.86, 0.44), control: p(0.50, 0.58))
            path.addLine(to: p(0.86, 0.40))
            path.addLine(to: p(0.14, 0.40))
            path.closeSubpath()
        case .egg:
            path.move(to: p(0.50, 0.10))
            path.addCurve(to: p(0.80, 0.62), control1: p(0.70, 0.10), control2: p(0.80, 0.40))
            path.addCurve(to: p(0.50, 0.90), control1: p(0.80, 0.80), control2: p(0.66, 0.90))
            path.addCurve(to: p(0.20, 0.62), control1: p(0.34, 0.90), control2: p(0.20, 0.80))
            path.addCurve(to: p(0.50, 0.10), control1: p(0.20, 0.40), control2: p(0.30, 0.10))
            path.closeSubpath()
        case .cakeSlice:
            path.move(to: p(0.10, 0.62))
            path.addLine(to: p(0.88, 0.40))
            path.addLine(to: p(0.90, 0.86))
            path.addLine(to: p(0.12, 0.86))
            path.closeSubpath()
            path.addRoundedRect(in: r(0.60, 0.16, 0.06, 0.28), cornerSize: CGSize(width: side * 0.02, height: side * 0.02))
            path.addEllipse(in: r(0.585, 0.06, 0.09, 0.11))
        case .sodaCan:
            path.addRoundedRect(in: r(0.28, 0.14, 0.44, 0.74), cornerSize: CGSize(width: side * 0.09, height: side * 0.09))
            path.addRoundedRect(in: r(0.32, 0.10, 0.36, 0.08), cornerSize: CGSize(width: side * 0.03, height: side * 0.03))
        case .gummyBear:
            path.addEllipse(in: r(0.30, 0.12, 0.40, 0.34))
            path.addEllipse(in: r(0.26, 0.08, 0.14, 0.14))
            path.addEllipse(in: r(0.60, 0.08, 0.14, 0.14))
            path.addEllipse(in: r(0.26, 0.40, 0.48, 0.44))
            path.addEllipse(in: r(0.16, 0.46, 0.18, 0.14))
            path.addEllipse(in: r(0.66, 0.46, 0.18, 0.14))
            path.addEllipse(in: r(0.24, 0.76, 0.20, 0.14))
            path.addEllipse(in: r(0.56, 0.76, 0.20, 0.14))
        case .glassBottle:
            path.addRoundedRect(in: r(0.43, 0.08, 0.14, 0.12), cornerSize: CGSize(width: side * 0.02, height: side * 0.02))
            path.move(to: p(0.45, 0.18))
            path.addLine(to: p(0.55, 0.18))
            path.addLine(to: p(0.55, 0.34))
            path.addQuadCurve(to: p(0.70, 0.50), control: p(0.70, 0.38))
            path.addLine(to: p(0.70, 0.84))
            path.addQuadCurve(to: p(0.64, 0.90), control: p(0.70, 0.90))
            path.addLine(to: p(0.36, 0.90))
            path.addQuadCurve(to: p(0.30, 0.84), control: p(0.30, 0.90))
            path.addLine(to: p(0.30, 0.50))
            path.addQuadCurve(to: p(0.45, 0.34), control: p(0.30, 0.38))
            path.closeSubpath()
        case .unsquishable:
            path.addEllipse(in: r(0.16, 0.16, 0.68, 0.68))
        }
        return path
    }
}

/// The object as a candy tile (before a thumbnail exists): its silhouette in tint on its gel colour,
/// with a soft top-left highlight. No SF Symbols.
struct ObjectTile: View {
    let kind: ObjectKind
    var cornerRadius: CGFloat = Theme.stickerRadius
    var golden = false

    var body: some View {
        let fill = golden ? Theme.gold : Theme.tint(for: kind)
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.gel(for: kind, golden: golden))
            ObjectSilhouette(kind: kind)
                .fill(fill)
                .overlay {
                    ObjectSilhouette(kind: kind)
                        .fill(LinearGradient(colors: [Color.white.opacity(0.45), .clear, Theme.shadowInk.opacity(0.18)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                .padding(cornerRadius * 0.6)
                .shadow(color: Theme.shadowInk.opacity(0.18), radius: 3, y: 2)
            if kind == .bubbleWrap {
                BubbleDots()
                    .padding(cornerRadius * 0.6)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Domes on the bubble-wrap tile (big, evenly spaced; never a small-hole cluster).
private struct BubbleDots: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let step = side * 0.76 / 3
            ZStack {
                ForEach(0..<9, id: \.self) { index in
                    Circle()
                        .fill(Color.white.opacity(0.55))
                        .frame(width: step * 0.62, height: step * 0.62)
                        .position(x: (proxy.size.width - side) / 2 + side * 0.12 + step * (CGFloat(index % 3) + 0.5),
                                  y: (proxy.size.height - side) / 2 + side * 0.12 + step * (CGFloat(index / 3) + 0.5))
                }
            }
        }
    }
}

/// An embossed silhouette pressed into paper (locked slots, §6.9).
struct EmbossedSilhouette: View {
    let kind: ObjectKind

    var body: some View {
        ZStack {
            ObjectSilhouette(kind: kind).fill(Color.white.opacity(0.9)).offset(x: -0.5, y: -0.5)
            ObjectSilhouette(kind: kind).fill(Theme.shadowInk.opacity(0.15)).offset(x: 0.5, y: 0.5)
            ObjectSilhouette(kind: kind).fill(Theme.paperShade)
        }
        .accessibilityHidden(true)
    }
}

/// The specimen photo if one was captured, otherwise its pressed tile (never the intact object: a specimen has
/// been squished, FOLD-REVIEW-8 N2). Intact `ObjectTile`s are only for objects not pressed yet.
struct SpecimenImage: View {
    let specimen: SpecimenRecord
    let thumbnail: UIImage?
    var cornerRadius: CGFloat = Theme.stickerRadius

    var body: some View {
        Group {
            if let thumbnail {
                // Fill the proposed frame without overflowing it.
                Color.clear
                    .overlay {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .transition(.opacity)
            } else {
                PressedTile(specimen: specimen, cornerRadius: cornerRadius)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A specimen with no stored thumbnail (its write failed, or the reveal's capture hasn't landed yet): the print its
/// press left on the platen, rebuilt from the record (`SpecimenPrint`, the seeded demo cards' path), in the card's
/// own framing. Rendered off the main actor and cached; until it's ready, a bare strike plate on paper.
struct PressedTile: View {
    let specimen: SpecimenRecord
    var cornerRadius: CGFloat = Theme.stickerRadius
    @State private var rendered: UIImage?

    var body: some View {
        let image = rendered ?? SpecimenPrint.cachedCard(for: specimen)
        Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else {
                    blankPlate
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .task(id: specimen.id) {
                guard SpecimenPrint.cachedCard(for: specimen) == nil else { return }
                let record = specimen
                let card = await Task.detached(priority: .userInitiated) { SpecimenPrint.card(for: record) }.value
                rendered = card
            }
            .accessibilityHidden(true)
    }

    /// The strike plate before its print is drawn: paper, and the plate's steel in the print's proportions.
    private var blankPlate: some View {
        let canvas = FoldPrintCanvas.rect
        return ZStack {
            Color(uiColor: Palette.paper)
            GeometryReader { proxy in
                // As `SpecimenPrint.cardImage` fits the print canvas (plate + 40 pt) into the card, 4 % margin.
                let box = min(proxy.size.width, proxy.size.height) * 0.92
                let s = min(box / canvas.width, box / canvas.height)
                RoundedRectangle(cornerRadius: CGFloat(FoldMetrics.plateRadius) * s, style: .continuous)
                    .fill(Color(uiColor: FoldTextures.platenSteel))
                    .frame(width: CGFloat(FoldMetrics.plateLateral) * s, height: CGFloat(FoldMetrics.plateDepth) * s)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        }
    }
}

/// A die-cut sticker: 5 pt white border, radius 14, E1, seeded tilt ±2.5° (§6.9).
struct Sticker<Content: View>: View {
    var seed: UInt64 = 0
    var golden = false
    var tilted = true
    @ViewBuilder var content: Content

    var tilt: Double { tilted ? Double(Int(seed % 11) - 5) * 0.5 : 0 }

    var body: some View {
        let outer = RoundedRectangle(cornerRadius: Theme.stickerRadius + 5, style: .continuous)
        content
            .clipShape(RoundedRectangle(cornerRadius: Theme.stickerRadius, style: .continuous))
            .padding(5)
            .background(Color.white, in: outer)
            .overlay {
                if golden {
                    outer.strokeBorder(AngularGradient(colors: [Theme.goldSoft, Theme.gold, Theme.goldSoft, Theme.gold, Theme.goldSoft],
                                                       center: .center), lineWidth: 3)
                }
            }
            .elevation(.e1)
            .rotationEffect(.degrees(tilt))
    }
}

// MARK: - Crease safety for sheets

private struct WindowIsLandscapeKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    /// The window's orientation (RootView's full-screen bands), handed to sheets. A sheet can't tell the pose from its
    /// own size: a tabletop sheet at the 0.45 detent is 669 × ~430 pt, wider than tall, yet its crease is horizontal.
    /// Nil outside RootView (previews), where `CreaseSafe` falls back to the sheet's aspect.
    var windowIsLandscape: Bool? {
        get { self[WindowIsLandscapeKey.self] }
        set { self[WindowIsLandscapeKey.self] = newValue }
    }

    /// `ScreenBands.tabletopCreaseAboveSafeBottom`, handed to the Shelf sheet so it can split its content around the
    /// crease (FOLD-REVIEW-7 N5). Nil on regular iPhones, in book pose and outside RootView.
    var tabletopCreaseAboveSafeBottom: CGFloat? {
        get { self[TabletopCreaseKey.self] }
        set { self[TabletopCreaseKey.self] = newValue }
    }
}

private struct TabletopCreaseKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

/// Where a sheet's content goes on a foldable (FOLD-REVIEW-6 N4). Pure, so it's unit-tested (CollectionTests).
enum SheetCreaseLayout: Equatable {
    /// The whole sheet: no hinge, or tabletop (horizontal crease, which a scrolling sheet may cross).
    case full
    /// Book pose (landscape window, vertical crease): the trailing half, clear of the 40 pt crease.
    case trailingHalf(width: CGFloat)

    /// Decided on the window's orientation, the same rule as `ScreenBands.isLandscape` and `FoldLayout` (wider than
    /// tall = book), never on the sheet's own aspect.
    static func layout(hasHinge: Bool, windowIsLandscape: Bool?, sheet: CGSize) -> SheetCreaseLayout {
        guard hasHinge, windowIsLandscape ?? (sheet.width > sheet.height) else { return .full }
        return .trailingHalf(width: max(0, sheet.width / 2 - ScreenBands.creaseHalf))
    }
}

/// On a foldable in book pose (landscape window, vertical crease), keep a sheet's content on the right half so no
/// control sits on the 40 pt crease. Tabletop (portrait window, horizontal crease) gets the full sheet width at every
/// detent; before FOLD-REVIEW-6 N4 the 0.45-detent Shelf was wider than tall and got squeezed into the right half.
struct CreaseSafe: ViewModifier {
    @AppStorage("squish.hasHinge") private var hasHinge = false
    @Environment(\.windowIsLandscape) private var windowIsLandscape

    func body(content: Content) -> some View {
        GeometryReader { proxy in
            switch SheetCreaseLayout.layout(hasHinge: hasHinge, windowIsLandscape: windowIsLandscape, sheet: proxy.size) {
            case let .trailingHalf(width):
                content
                    .frame(width: width)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            case .full:
                content
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }
}

extension View {
    func creaseSafe() -> some View { modifier(CreaseSafe()) }
}
