import SwiftUI
import UIKit

/// The outer (cover) display while the phone is shut (VISUAL-TARGET §6.11, bible §3.1 beat 10, §5, UX-AUDIT-2 §4.3).
/// It's the outside of the machine: a graphite panel with four screws.
/// - C1 lobby: the three latest stickers, the object chips (queue the next object before opening), and the same doors
///   as inside: Shelf, Menu, Settings (HIG: the same functionality on both displays).
/// - C1a first run: "Open me to start".
/// - C2 sealing (a live gauge), sealed (KA-CHUNK!, then the tonnage and "What's left?", never the print: no spoiler),
///   releasing (the needle falls, the lamp turns green).
/// - C3 paused: closed mid-press without sealing.
struct CoverView: View {
    enum Content: Equatable {
        case idle
        case firstRun
        case sealing(tons: Int)
        case sealed(kind: ObjectKind, tons: Int)
        case releasing(tons: Int)
        case paused(tons: Int)
    }

    let content: Content
    let recent: [SpecimenRecord]
    let currentKind: ObjectKind
    let thumbnail: (SpecimenRecord) -> UIImage?
    /// The real outer display keeps a clock column on the trailing edge (research 05 §3.6).
    var reservesClockColumn = false
    /// Unlocked objects for the chip picker.
    var unlockedKinds: [ObjectKind] = []
    /// Queues an object onto the anvil (`PressDirector.queue(_:)`); nil hides the picker.
    var onQueue: ((ObjectKind) -> Void)?
    /// The one-time safety line (bible §3.2), when it's due.
    var showsSafetyLine = false
    /// "3/10" on the lobby's Shelf key.
    var pressedCount = 0
    /// The lobby's doors (C1); nil hides the row.
    var onShelf: (() -> Void)?
    var onMenu: (() -> Void)?
    var onSettings: (() -> Void)?
    /// The first-run sound line ("Sound plays even on Silent…").
    var soundLine = ""

    /// The outer display's safe area already excludes the clock column and the bottom inset (seen on the Duo
    /// simulator), so the idle content just takes a normal margin and centres in what's left, both ways.
    private var sideInset: CGFloat { Theme.s5 }
    private var bottomInset: CGFloat { 0 }

    private var holdsPressure: Bool {
        switch content {
        case .sealed, .sealing, .paused: return true
        case .idle, .firstRun, .releasing: return false
        }
    }

    var body: some View {
        ZStack {
            MachinePanel(holdingPressure: holdsPressure)
            switch content {
            case let .sealed(kind, tons):
                centred { SealedInset(kind: kind, tons: tons) }
            case let .sealing(tons):
                centred { PressureInset(state: .sealing, tons: tons) }
            case let .releasing(tons):
                centred { PressureInset(state: .releasing, tons: tons) }
            case let .paused(tons):
                centred { PressureInset(state: .paused, tons: tons) }
            case .firstRun:
                centred { FirstRunCover(soundLine: soundLine) }
            case .idle:
                idle
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    /// A card centred on the whole outer display (FOLD-REVIEW-3 N16, FOLD-REVIEW-4 F10), both ways, at ~80 % of its
    /// width. Centring in the safe area left of the clock column put it 220 px left of centre with 61 % of the panel
    /// empty. Its content is centred, so the column only ever meets the card's paper margin.
    private func centred<Card: View>(@ViewBuilder _ card: () -> Card) -> some View {
        let inset = card()
        return GeometryReader { proxy in
            let width = min(max(240, proxy.size.width * 0.8), 400)
            ScrollView(.vertical) {
                VStack(spacing: Theme.s4) {
                    inset
                    safetyLine
                }
                .frame(width: width)
                .padding(.vertical, Theme.s5)
                .frame(minHeight: proxy.size.height)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
        .ignoresSafeArea()
    }

    /// The idle picker (FOLD-REVIEW-9 N5): centred on the whole outer display, like `sealed`. Centred in the safe area
    /// it sat ~50 px from the hinge edge and ~210 px from the free edge. Its width is capped so that, centred, it still
    /// clears the clock column (the safe area's trailing inset) by `CoverLayout.clockClearance`.
    private var idle: some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            let width = CoverLayout.idleWidth(display: proxy.size.width, leading: insets.leading,
                                              trailing: insets.trailing, sideInset: sideInset)
            ScrollView(.vertical) {
                VStack(spacing: Theme.s4) {
                    IdleCover(recent: recent, currentKind: currentKind, thumbnail: thumbnail,
                              unlockedKinds: unlockedKinds, onQueue: onQueue)
                    doors
                    safetyLine
                }
                .frame(width: width)
                // Symmetric, so it stays centred on the display while clearing the top and bottom insets.
                .padding(.vertical, Theme.s5 + max(insets.top, insets.bottom))
                .frame(minHeight: proxy.size.height - bottomInset)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .padding(.bottom, bottomInset)
        }
        .ignoresSafeArea()
    }

    /// C1's doors: the same Shelf, Menu and Settings as the press room, so nothing is tied to one display.
    @ViewBuilder
    private var doors: some View {
        if onShelf != nil || onMenu != nil || onSettings != nil {
            HStack(spacing: Theme.s2) {
                if let onShelf {
                    ShelfKey(pressedCount: pressedCount, total: ObjectKind.allCases.count, hop: 0, bump: 0, onOpen: onShelf)
                }
                if let onMenu {
                    MenuKeycap(action: onMenu)
                }
                if let onSettings {
                    Button(action: onSettings) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(.subheadline, weight: .semibold))
                    }
                    .buttonStyle(KeycapStyle(kind: .console, round: true))
                    .accessibilityLabel("Settings")
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        }
    }

    @ViewBuilder
    private var safetyLine: some View {
        if showsSafetyLine {
            Text("Squish is on-screen only. Never close your phone on real things.")
                .font(Theme.footnote)
                .foregroundStyle(Theme.paper.opacity(0.85))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A side-view phone opening on a loop (P2-6): the top slab swings 0 → 160° over 1.4 s, holds, closes.
/// Static (open) under Reduce Motion.
private struct FoldGlyph: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let angle = reduceMotion ? 120 : Self.angle(at: context.date.timeIntervalSinceReferenceDate)
            ZStack(alignment: .bottomLeading) {
                Capsule().fill(Theme.paper.opacity(0.85)).frame(width: 30, height: 4)
                Capsule()
                    .fill(Theme.yellow)
                    .frame(width: 30, height: 4)
                    .rotationEffect(.degrees(-angle), anchor: .leading)
                    .offset(y: -4)
            }
            .frame(width: 34, height: 26, alignment: .bottomLeading)
        }
    }

    /// 1.4 s open (ease-in-out), 0.6 s hold, 1.0 s close, 0.4 s rest.
    nonisolated private static func angle(at time: Double) -> Double {
        let t = time.truncatingRemainder(dividingBy: 3.4)
        func ease(_ x: Double) -> Double { x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2 }
        switch t {
        case ..<1.4: return 160 * ease(t / 1.4)
        case ..<2.0: return 160
        case ..<3.0: return 160 * (1 - ease((t - 2.0) / 1.0))
        default: return 0
        }
    }
}

/// The press's outside (FOLD-PRESS §6.1): graphite panel, 1 pt top highlight, four chrome screws, 10 pt hazard
/// jaws on the free (trailing) edge, and — while sealed — a faint amber seam glow on the hinge (leading) edge.
private struct MachinePanel: View {
    var holdingPressure = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glow = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.rgb(0x3A3D43), Theme.rgb(0x2B2D31)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                Spacer()
            }
            .ignoresSafeArea()
            HStack(spacing: 0) {
                // Hinge edge: the seam holding pressure.
                // 6 pt amber seam glow at 0.5, breathing with "OPEN TO SEE" (FOLD-REVIEW-2 #10).
                Rectangle()
                    .fill(Theme.yellow.opacity(holdingPressure ? (glow ? 0.5 : 0.3) : 0))
                    .frame(width: 6)
                    .shadow(color: Theme.yellow.opacity(holdingPressure ? 0.5 : 0), radius: 6)
                Spacer(minLength: 0)
                HazardJaw()
                    .frame(width: 10)
            }
            .ignoresSafeArea()
            .onAppear {
                guard holdingPressure, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { glow = true }
            }
            // FOLD-REVIEW-9 N5: on the panel's own corners (full bounds), not the safe area's, where the trailing pair
            // floated ~190 px inside the edge. The trailing pair sits inside the hazard jaw.
            GeometryReader { proxy in
                ForEach(0..<4, id: \.self) { index in
                    Screw()
                        .position(CoverLayout.screw(index, in: proxy.size))
                }
            }
            .ignoresSafeArea()
        }
        .accessibilityHidden(true)
    }
}

/// Cover geometry (FOLD-REVIEW-9 N5), pure so tests can pin it.
enum CoverLayout {
    /// The idle picker's widest, narrowest, and its gap to the clock column.
    static let maxIdleWidth: CGFloat = 340
    static let minIdleWidth: CGFloat = 220
    static let clockClearance: CGFloat = 16
    /// Screw centres from the panel's edges: the corner rounding stays clear of them (≤ 60 pt radius at 18 pt),
    /// and the trailing pair sits the same distance inside the 10 pt hazard jaw.
    static let screwInset: CGFloat = 18
    static let jawWidth: CGFloat = 10

    /// The width of the idle column centred on a `display`-wide panel: ≤ `maxIdleWidth`, `sideInset` from the panel's
    /// edges, and clear of the leading and trailing safe-area insets (the clock column) by `clockClearance`.
    static func idleWidth(display: CGFloat, leading: CGFloat, trailing: CGFloat, sideInset: CGFloat) -> CGFloat {
        let edge = max(sideInset, max(leading, trailing) + clockClearance)
        return max(minIdleWidth, min(display - 2 * edge, maxIdleWidth))
    }

    /// Screw `index` (0 top-leading, 1 top-trailing, 2 bottom-leading, 3 bottom-trailing) on a panel of `size`.
    static func screw(_ index: Int, in size: CGSize) -> CGPoint {
        CGPoint(x: index % 2 == 0 ? screwInset : size.width - jawWidth - screwInset,
                y: index < 2 ? screwInset : size.height - screwInset)
    }
}

/// 45° yellow/graphite stripes, 8 pt stripe width (16 pt period), drawn vertically.
private struct HazardJaw: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.yellow))
            let period: CGFloat = 16
            var y: CGFloat = -size.width
            while y < size.height + size.width {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y + size.width))
                path.addLine(to: CGPoint(x: size.width, y: y + size.width + period / 2))
                path.addLine(to: CGPoint(x: 0, y: y + period / 2))
                path.closeSubpath()
                context.fill(path, with: .color(Theme.graphite))
                y += period
            }
        }
        .accessibilityHidden(true)
    }
}

private struct Screw: View {
    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [Theme.rgb(0xE6E8EC), Theme.rgb(0x8A8F98)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Rectangle().fill(Theme.rgb(0x5A5E66)).frame(width: 4, height: 1).rotationEffect(.degrees(35)))
            .frame(width: 6, height: 6)
            .shadow(color: .black.opacity(0.35), radius: 0.5, y: 0.5)
    }
}

/// The sealed card (C2b): KA-CHUNK! slams in, then the paper inset with the mini gauge at the peak, the tonnage and
/// "What's left? Open to see." It never shows the print (UX-AUDIT-2 §2.1 #12: the cover spoiled the reveal).
private struct SealedInset: View {
    let kind: ObjectKind
    let tons: Int
    var inkPrint: UIImage? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false
    @State private var slammed = false

    var body: some View {
        VStack(spacing: Theme.s3) {
            Text("KA-CHUNK!")
                .font(Theme.captionFont(size: 40))
                .foregroundStyle(Theme.yellow)
                .shadow(color: .black.opacity(0.4), radius: 0, x: 0, y: 3)
                .scaleEffect(slammed || reduceMotion ? 1 : 1.6)
                .rotationEffect(.degrees(slammed || reduceMotion ? -4 : -12))
                .opacity(slammed ? 1 : 0)
                .padding(.top, -Theme.s6)
                .accessibilityHidden(true)
            HStack(spacing: Theme.s2) {
                // LOAD lamp: amber while the press holds pressure.
                Circle()
                    .fill(Theme.yellow)
                    .overlay(Circle().strokeBorder(Theme.yellowLip, lineWidth: 1))
                    .frame(width: 10, height: 10)
                    .shadow(color: Theme.yellow.opacity(0.6), radius: 4)
                Text("PRESS SEALED")
                    .font(.system(.headline, design: .rounded, weight: .heavy))
                    .foregroundStyle(Theme.graphite)
            }
            if let inkPrint {
                printTeaser(inkPrint)
                HStack(spacing: Theme.s4) {
                    MiniGauge(tons: tons)
                        .frame(width: 64, height: 64)
                    tonnage
                }
            } else {
                HStack(spacing: Theme.s4) {
                    MiniGauge(tons: tons)
                        .frame(width: 72, height: 72)
                    silhouetteTeaser
                }
                tonnage
            }
            Text("OPEN TO SEE")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(Theme.microTracking)
                .foregroundStyle(Theme.graphite)
                .opacity(reduceMotion ? 1 : (breathe ? 1 : 0.6))
        }
        .padding(.horizontal, Theme.s5)
        .padding(.vertical, Theme.s4)
        .frame(maxWidth: .infinity)
        .background { PaperBackground().clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)).elevation(.e2) }
        .topHighlight(cornerRadius: 16)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.25, dampingFraction: 0.5)) {
                slammed = true
            }
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { breathe = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ka-chunk. Press sealed. \(tons) tons. What's left? Open your iPhone to see.")
    }

    private var tonnage: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(tons)")
                .font(Theme.bigNumber)
                .monospacedDigit()
                .foregroundStyle(Theme.graphite)
            Text("TONS")
                .font(Theme.bigNumber)
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    private var whatsLeft: some View {
        Text("WHAT'S LEFT?")
            .font(Theme.micro)
            .tracking(Theme.microTracking)
            .foregroundStyle(Theme.inkSecondary)
    }

    /// The monoprint as it lies on the platen (steel plate, ink, splat; no bezel), full card width, ≤ 150 pt tall.
    private func printTeaser(_ image: UIImage) -> some View {
        VStack(spacing: Theme.s1) {
            whatsLeft
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                // Clip and rim the image itself, then let the frame centre it in the card.
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.graphite.opacity(0.18), lineWidth: 1)
                }
                .frame(maxWidth: .infinity, maxHeight: 150)
                .accessibilityHidden(true)
        }
    }

    /// No print (P-48, demo cover): the object's silhouette, flattened, with a question (P2-5).
    private var silhouetteTeaser: some View {
        VStack(spacing: Theme.s1) {
            whatsLeft
            // The object's print in its own ink at 0.5 — a recognisable shape, not a squashed grey blob
            // (FOLD-REVIEW-2 #10). Bubble wrap shows its domes so it never reads as a plain bar.
            ZStack {
                ObjectSilhouette(kind: kind)
                    .fill(Theme.tint(for: kind).opacity(0.5))
                ObjectSilhouette(kind: kind)
                    .stroke(Theme.graphite.opacity(0.35), lineWidth: 1)
                if kind == .bubbleWrap {
                    ObjectTile(kind: kind, cornerRadius: 8)
                        .opacity(0.6)
                }
            }
            .frame(width: 48, height: 48)
        }
    }
}

/// The press gauge in miniature (VISUAL-TARGET §4.4): paper face, 270° sweep from 0 to the Fold Press dial's
/// maximum (`FoldTextures.gaugeMaxTons`, one scale everywhere), red zone in its top quarter, needle springing
/// up to the peak (no overshoot under Reduce Motion).
struct MiniGauge: View {
    let tons: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0.0

    /// One scale with the inner gauge (FOLD-REVIEW-2 #10).
    nonisolated static var maxTons: Double { Double(FoldTextures.gaugeMaxTons) }

    /// θ = 225° − 270°·(t/max), in maths degrees (counter-clockwise from +x).
    private static func angle(_ tons: Double) -> Double { 225 - 270 * tons / maxTons }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = side / 2
            ZStack {
                Circle().fill(Theme.paper)
                Circle().strokeBorder(Theme.graphite, lineWidth: 3)
                arc(center: center, radius: radius - 7, from: Self.maxTons * 0.75, to: Self.maxTons)
                    .stroke(Theme.stamp, style: StrokeStyle(lineWidth: 4, lineCap: .butt))
                ForEach(0...8, id: \.self) { step in
                    tick(center: center, radius: radius - 4, tons: Self.maxTons * Double(step) / 8,
                         length: step % 2 == 0 ? 6 : 4)
                        .stroke(Theme.graphite, lineWidth: step % 2 == 0 ? 1.5 : 1)
                }
                // Numerals on the same scale as the inner gauge (0 / 40 / 80). The "TONS" unit lives in the big
                // readout below the dial, so nothing crowds the top numeral (FOLD-REVIEW-2 #10).
                ForEach([0, Int(Self.maxTons / 2), Int(Self.maxTons)], id: \.self) { value in
                    Text("\(value)")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.inkSecondary)
                        .position(point(center, radius - 17, Self.angle(Double(value))))
                }
                GaugeNeedle(tons: shown, inset: 9)
                    .fill(Theme.stamp)
                Circle().fill(Theme.rgb(0xC9CCD2)).frame(width: 7, height: 7).position(center)
            }
        }
        .accessibilityHidden(true)
        // Live gauges (sealing climbs, releasing falls) follow the value.
        .onChange(of: tons) { _, value in
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.5, dampingFraction: 0.7)) {
                shown = min(Double(value), Self.maxTons + 2)
            }
        }
        .onAppear {
            let target = min(Double(tons), Self.maxTons + 2)
            let animation: Animation = reduceMotion
                ? .easeOut(duration: 0.15)
                : .spring(response: 0.6, dampingFraction: 0.55).delay(0.15)
            withAnimation(animation) {
                shown = target
            }
        }
    }

    private func point(_ center: CGPoint, _ radius: CGFloat, _ degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: center.x + CGFloat(cos(radians)) * radius, y: center.y - CGFloat(sin(radians)) * radius)
    }

    private func arc(center: CGPoint, radius: CGFloat, from: Double, to: Double) -> Path {
        var path = Path()
        let steps = 16
        for index in 0...steps {
            let t = from + (to - from) * Double(index) / Double(steps)
            let p = point(center, radius, Self.angle(t))
            if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }

    private func tick(center: CGPoint, radius: CGFloat, tons: Double, length: CGFloat) -> Path {
        var path = Path()
        let a = Self.angle(tons)
        path.move(to: point(center, radius, a))
        path.addLine(to: point(center, radius - length, a))
        return path
    }

}

/// The gauge needle as an animatable shape, so it swings (and settles) instead of jumping.
private struct GaugeNeedle: Shape {
    var tons: Double
    var inset: CGFloat

    var animatableData: Double {
        get { tons }
        set { tons = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let length = min(rect.width, rect.height) / 2 - inset
        let a = 225 - 270 * tons / Double(FoldTextures.gaugeMaxTons)
        func point(_ radius: CGFloat, _ degrees: Double) -> CGPoint {
            let radians = degrees * .pi / 180
            return CGPoint(x: center.x + CGFloat(cos(radians)) * radius, y: center.y - CGFloat(sin(radians)) * radius)
        }
        var path = Path()
        path.move(to: point(length, a))
        path.addLine(to: point(2.5, a + 90))
        path.addLine(to: point(6, a + 180))
        path.addLine(to: point(2.5, a - 90))
        path.closeSubpath()
        return path
    }
}

private struct IdleCover: View {
    let recent: [SpecimenRecord]
    let currentKind: ObjectKind
    let thumbnail: (SpecimenRecord) -> UIImage?
    let unlockedKinds: [ObjectKind]
    let onQueue: ((ObjectKind) -> Void)?

    var body: some View {
        VStack(spacing: Theme.s5) {
            Group {
                if recent.isEmpty {
                    // No empty tiles on a first run: one friendly line instead.
                    Text("Your pressed specimens land here.")
                        .font(Theme.footnote)
                        .foregroundStyle(Theme.paper.opacity(0.7))
                        .multilineTextAlignment(.center)
                } else {
                    trophyCard
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(shelfDescription)

            VStack(spacing: Theme.s1) {
                Text("ON THE ANVIL")
                    .font(Theme.micro)
                    .tracking(Theme.microTracking)
                    .foregroundStyle(Theme.paper.opacity(0.7))
                HStack(spacing: Theme.s2) {
                    TintDot(kind: currentKind, size: 12)
                    Text(currentKind.displayName)
                        .font(Theme.headline)
                        .foregroundStyle(Theme.paper)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.opacity)
                }
                .animation(Theme.fade, value: currentKind)
            }
            .accessibilityElement(children: .ignore)
            // The visible "Open to press" line is hidden from VoiceOver, so it is said here (launch QA #16).
            .accessibilityLabel("On the anvil: \(currentKind.displayName). Open your iPhone to press.")

            if let onQueue, unlockedKinds.count > 1 {
                // Two fixed columns that wrap: every chip is fully readable, nothing clips (Duo review).
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.s2), GridItem(.flexible())], spacing: Theme.s1) {
                    ForEach(unlockedKinds) { kind in
                        let selected = kind == currentKind
                        Button {
                            onQueue(kind)
                        } label: {
                            HStack(spacing: 6) {
                                ObjectArt(kind: kind, cornerRadius: 6)
                                    .frame(width: 28, height: 28)
                                // The name and its verb (EXPERIENCE-REVIEW-1 #10), the same two lines on every chip.
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(kind.coverName)
                                    Text(kind.verb.uppercased())
                                        .font(Theme.micro)
                                        .foregroundStyle(Theme.inkSecondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.leading, -6)
                        }
                        .buttonStyle(KeycapStyle(kind: .chip, fullWidth: true, selected: selected))
                        .accessibilityLabel("\(kind.displayName). \(kind.verb).")
                        .accessibilityAddTraits(selected ? [.isSelected] : [])
                        .accessibilityHint(selected ? "On the anvil." : "Puts it on the anvil for when you open.")
                    }
                }
            }

            HStack(spacing: Theme.s2) {
                FoldGlyph()
                    .frame(width: 34, height: 26)
                Text("Open to press")
                    .font(Theme.button)
                    .foregroundStyle(Theme.yellow)
            }
            .accessibilityHidden(true)
        }
    }

    /// The three latest stickers on a paper inset; empty slots are visible debossed wells.
    private var trophyCard: some View {
        HStack(spacing: Theme.s3) {
            ForEach(0..<3, id: \.self) { index in
                Group {
                    if index < recent.count {
                        let specimen = recent[index]
                        Sticker(seed: specimen.variant.seed, golden: specimen.variant.isGolden) {
                            SpecimenImage(specimen: specimen, thumbnail: thumbnail(specimen), cornerRadius: 10)
                        }
                    } else {
                        RoundedRectangle(cornerRadius: Theme.stickerRadius, style: .continuous)
                            .fill(Theme.paperShade.opacity(0.55))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.stickerRadius, style: .continuous)
                                    .strokeBorder(Theme.paperEdge, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                            )
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(Theme.s3)
        .frame(maxWidth: .infinity)
        .background { PaperBackground().clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)).elevation(.e2) }
        .topHighlight(cornerRadius: 16)
    }

    private var shelfDescription: String {
        let names = recent.prefix(3).map(\.kind.displayName)
        let shelf = names.isEmpty ? "Nothing pressed yet." : "Recently pressed: \(names.joined(separator: ", "))."
        return "Squish. \(shelf)"
    }
}

extension ObjectKind {
    /// The cover's chip grid shows the canonical name (launch QA #13: one name per object, never BALL or CRAYONS):
    /// the longest, UNSQUISHABLE and GLASS BOTTLE, fit a chip on the 466 pt outer display.
    var coverName: String { chipName }
}

/// C2a sealing, C2c releasing and C3 paused: the machine's outside under pressure, a live gauge and one line.
private struct PressureInset: View {
    enum Mode { case sealing, releasing, paused }
    let state: Mode
    let tons: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var falling = false

    var body: some View {
        VStack(spacing: Theme.s3) {
            HStack(spacing: Theme.s2) {
                Circle()
                    .fill(lamp)
                    .frame(width: 10, height: 10)
                    .shadow(color: lamp.opacity(0.6), radius: 4)
                Text(title)
                    .font(.system(.headline, design: .rounded, weight: .heavy))
                    .foregroundStyle(Theme.graphite)
            }
            HStack(spacing: Theme.s4) {
                MiniGauge(tons: state == .releasing && falling ? 0 : tons)
                    .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(tons)")
                            .font(Theme.bigNumber)
                            .monospacedDigit()
                            .foregroundStyle(Theme.graphite)
                            .contentTransition(.numericText(value: Double(tons)))
                        Text("TONS")
                            .font(Theme.bigNumber)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    Text(detail)
                        .font(Theme.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, Theme.s5)
        .padding(.vertical, Theme.s4)
        .frame(maxWidth: .infinity)
        .background { PaperBackground().clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)).elevation(.e2) }
        .topHighlight(cornerRadius: 16)
        .onAppear {
            guard state == .releasing else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                falling = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title.capitalized). \(tons) tons. \(detail)")
    }

    private var title: String {
        switch state {
        case .sealing: "SEALING…"
        case .releasing: "RELEASING…"
        case .paused: "PAUSED"
        }
    }

    private var detail: String {
        switch state {
        case .sealing: "All the way, now."
        case .releasing: "Open it the rest of the way."
        case .paused: "Open it to keep going."
        }
    }

    private var lamp: Color {
        switch state {
        case .sealing, .paused: Theme.yellow
        case .releasing: falling ? Theme.lampGreen : Theme.yellow
        }
    }
}

/// C1a: the very first launch with the phone shut. One job: get it open.
private struct FirstRunCover: View {
    let soundLine: String

    var body: some View {
        VStack(spacing: Theme.s4) {
            Text("SQUISH")
                .font(.system(size: 44, weight: .black, design: .rounded))
                .foregroundStyle(Theme.yellow)
                .shadow(color: .black.opacity(0.4), radius: 0, x: 0, y: 3)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: Theme.s3) {
                FoldGlyph()
                    .frame(width: 34, height: 26)
                    .accessibilityHidden(true)
                Text("Open me to start")
                    .font(Theme.headline)
                    .foregroundStyle(Theme.paper)
            }
            Text("Bubble wrap is waiting inside.")
                .font(Theme.footnote)
                .foregroundStyle(Theme.paper.opacity(0.75))
            if !soundLine.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: Theme.s2) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(Theme.yellow)
                    Text(soundLine.keepingLastWordsTogether)
                        .font(Theme.footnote)
                        .foregroundStyle(Theme.paper.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .contain)
    }
}
