import SwiftUI
import UIKit

/// The outer (cover) display while the phone is shut (VISUAL-TARGET §6.11, bible §3.1 beat 10, §5).
/// It's the outside of the machine: a graphite panel with four screws. After a press it shows the sealed
/// paper inset (mini gauge at the peak, tonnage, "OPEN TO SEE"); otherwise the three latest stickers and the
/// object chips, so the next object can be queued before opening.
struct CoverView: View {
    enum Content: Equatable {
        case sealed(kind: ObjectKind, tons: Int)
        case idle
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

    /// Outer display (466 × 678 pt): symmetric 84 pt side insets keep the clock column clear *and* the layout
    /// centred; 34 pt bottom inset. Elsewhere (CI demo on a slab iPhone) a normal 24 pt margin.
    private var sideInset: CGFloat { reservesClockColumn ? 84 : Theme.s5 }
    private var bottomInset: CGFloat { reservesClockColumn ? 34 : 0 }

    var body: some View {
        GeometryReader { proxy in
            let width = max(220, min(proxy.size.width - sideInset * 2, 340))
            ZStack {
                MachinePanel()
                ScrollView(.vertical) {
                    VStack(spacing: Theme.s4) {
                        switch content {
                        case let .sealed(kind, tons):
                            SealedInset(kind: kind, tons: tons)
                        case .idle:
                            IdleCover(recent: recent, currentKind: currentKind, thumbnail: thumbnail,
                                      unlockedKinds: unlockedKinds, onQueue: onQueue)
                        }
                        if showsSafetyLine {
                            Text("Squish is on-screen only. Never close your phone on real things.")
                                .font(Theme.footnote)
                                .foregroundStyle(Theme.paper.opacity(0.85))
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(width: width)
                    .padding(.vertical, Theme.s5)
                    .frame(minHeight: proxy.size.height - bottomInset)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
                .padding(.bottom, bottomInset)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
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

/// Graphite gradient panel, 1 pt top highlight, four chrome screws.
private struct MachinePanel: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.rgb(0x3A3D43), Theme.rgb(0x2B2D31)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                Spacer()
            }
            .ignoresSafeArea()
            GeometryReader { proxy in
                let inset: CGFloat = 14
                ForEach(0..<4, id: \.self) { index in
                    Screw()
                        .position(x: index % 2 == 0 ? inset : proxy.size.width - inset,
                                  y: index < 2 ? inset : proxy.size.height - inset)
                }
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

/// The sealed card: a paper inset with the mini gauge at the peak.
private struct SealedInset: View {
    let kind: ObjectKind
    let tons: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    var body: some View {
        VStack(spacing: Theme.s3) {
            Text("PRESS SEALED")
                .font(.system(.headline, design: .rounded, weight: .heavy))
                .foregroundStyle(Theme.graphite)
            HStack(spacing: Theme.s4) {
                MiniGauge(tons: tons)
                    .frame(width: 72, height: 72)
                // Teaser (P2-5): the object's silhouette, flattened, with a question.
                VStack(spacing: Theme.s1) {
                    Text("WHAT'S LEFT?")
                        .font(Theme.micro)
                        .tracking(Theme.microTracking)
                        .foregroundStyle(Theme.inkSecondary)
                    EmbossedSilhouette(kind: kind)
                        .frame(width: 56, height: 56)
                        .scaleEffect(x: 1.3, y: 0.35)
                        .frame(height: 24)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(tons)")
                    .font(Theme.bigNumber)
                    .monospacedDigit()
                    .foregroundStyle(Theme.graphite)
                Text("TONS")
                    .font(Theme.bigNumber)
                    .foregroundStyle(Theme.inkSecondary)
            }
            Text("OPEN TO SEE")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(Theme.microTracking)
                .foregroundStyle(Theme.graphite)
                .opacity(reduceMotion ? 1 : (breathe ? 1 : 0.6))
        }
        .padding(.horizontal, Theme.s5)
        .padding(.vertical, Theme.s4)
        .frame(minWidth: 220)
        .background { PaperBackground().clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)).elevation(.e2) }
        .topHighlight(cornerRadius: 16)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { breathe = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Press sealed. \(tons) tons. Open your iPhone to see the result.")
    }
}

/// The press gauge in miniature (VISUAL-TARGET §4.4): paper face, 270° sweep from 0 to 60 tons, red zone
/// 48–60, needle springing up to the peak (no overshoot under Reduce Motion).
struct MiniGauge: View {
    let tons: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0.0

    /// θ = 225° − 270°·(t/60), in maths degrees (counter-clockwise from +x).
    private static func angle(_ tons: Double) -> Double { 225 - 270 * tons / 60 }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = side / 2
            ZStack {
                Circle().fill(Theme.paper)
                Circle().strokeBorder(Theme.graphite, lineWidth: 3)
                arc(center: center, radius: radius - 7, from: 48, to: 60)
                    .stroke(Theme.stamp, style: StrokeStyle(lineWidth: 4, lineCap: .butt))
                ForEach(0...6, id: \.self) { step in
                    tick(center: center, radius: radius - 4, tons: Double(step * 10), length: 6)
                        .stroke(Theme.graphite, lineWidth: 1.5)
                }
                // Numerals so it reads as a gauge, not a clock (VISUAL-REVIEW-1, cover sealed).
                ForEach([0, 30, 60], id: \.self) { value in
                    Text("\(value)")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.inkSecondary)
                        .position(point(center, radius - 17, Self.angle(Double(value))))
                }
                Text("TONS")
                    .font(.system(size: 6, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.inkSecondary)
                    .position(x: center.x, y: center.y + radius * 0.42)
                GaugeNeedle(tons: shown, inset: 9)
                    .fill(Theme.stamp)
                Circle().fill(Theme.rgb(0xC9CCD2)).frame(width: 7, height: 7).position(center)
            }
        }
        .accessibilityHidden(true)
        .onAppear {
            let target = min(Double(tons), 62)
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
        let a = 225 - 270 * tons / 60
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
            trophyCard
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
            .accessibilityElement(children: .combine)

            if let onQueue, unlockedKinds.count > 1 {
                // Two fixed columns that wrap: every chip is fully readable, nothing clips (Duo review).
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.s2), GridItem(.flexible())], spacing: Theme.s1) {
                    ForEach(unlockedKinds) { kind in
                        let selected = kind == currentKind
                        Button {
                            onQueue(kind)
                        } label: {
                            HStack(spacing: 6) {
                                TintDot(kind: kind)
                                Text(kind.chipName)
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(KeycapStyle(kind: .chip, fullWidth: true, selected: selected))
                        .accessibilityLabel(kind.displayName)
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
