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

    var body: some View {
        ZStack {
            MachinePanel()
            VStack(spacing: Theme.s4) {
                Spacer(minLength: Theme.s4)
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
                        .padding(.horizontal, Theme.s4)
                }
                Spacer(minLength: Theme.s4)
            }
            .padding(.horizontal, Theme.s5)
            .padding(.trailing, reservesClockColumn ? 84 : 0)
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
        .background { PaperBackground().clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)) }
        .topHighlight(cornerRadius: 16)
        .elevation(.e2)
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
        VStack(spacing: Theme.s4) {
            trophyRow
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(shelfDescription)
            VStack(spacing: Theme.s1) {
                Text("ON THE ANVIL")
                    .font(Theme.micro)
                    .tracking(Theme.microTracking)
                    .foregroundStyle(Theme.paper.opacity(0.7))
                Text(currentKind.displayName)
                    .font(.system(.headline, design: .rounded, weight: .heavy))
                    .foregroundStyle(Theme.paper)
                    .contentTransition(.opacity)
                    .animation(Theme.fade, value: currentKind)
            }
            .accessibilityElement(children: .combine)
            if let onQueue, unlockedKinds.count > 1 {
                ScrollView(.horizontal) {
                    HStack(spacing: Theme.s2) {
                        ForEach(unlockedKinds) { kind in
                            let selected = kind == currentKind
                            Button {
                                onQueue(kind)
                            } label: {
                                HStack(spacing: 6) {
                                    TintDot(kind: kind)
                                    Text(kind.displayName.uppercased())
                                }
                            }
                            .buttonStyle(KeycapStyle(kind: .chip, selected: selected))
                            .accessibilityLabel(kind.displayName)
                            .accessibilityAddTraits(selected ? [.isSelected] : [])
                            .accessibilityHint(selected ? "On the anvil." : "Puts it on the anvil for when you open.")
                        }
                    }
                    .padding(.horizontal, Theme.s1)
                    .padding(.vertical, Theme.s1)
                }
                .scrollIndicators(.hidden)
            }
            HStack(spacing: Theme.s2) {
                FoldGlyph()
                    .frame(width: 34, height: 26)
                Text("Open to press")
                    .font(.system(.subheadline, design: .rounded, weight: .heavy))
                    .foregroundStyle(Theme.yellow)
            }
            .accessibilityHidden(true)
        }
    }

    private var trophyRow: some View {
        HStack(spacing: Theme.s3) {
            ForEach(0..<3, id: \.self) { index in
                if index < recent.count {
                    let specimen = recent[index]
                    Sticker(seed: specimen.variant.seed, golden: specimen.variant.isGolden) {
                        SpecimenImage(specimen: specimen, thumbnail: thumbnail(specimen), cornerRadius: 10)
                    }
                    .frame(width: 70, height: 70)
                } else {
                    RoundedRectangle(cornerRadius: Theme.stickerRadius, style: .continuous)
                        .strokeBorder(Theme.paper.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .frame(width: 70, height: 70)
                }
            }
        }
        .padding(Theme.s3)
        .background { PaperBackground().clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)) }
        .topHighlight(cornerRadius: 16)
        .elevation(.e2)
    }

    private var shelfDescription: String {
        let names = recent.prefix(3).map(\.kind.displayName)
        let shelf = names.isEmpty ? "Nothing pressed yet." : "Recently pressed: \(names.joined(separator: ", "))."
        return "Squish. \(shelf)"
    }
}
