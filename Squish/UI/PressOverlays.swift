import SwiftUI

// Everything drawn over the stage on the Press screen (VISUAL-TARGET §6.1):
//   0–6%   nothing
//   6–44%  scene; overlays only for the reveal card, captions (22–42%) and the failure flash (0–50%)
//   45–80% STAGE: nothing, ever
//   80–86% toasts, one at a time
//   86–95% console: object chip, Shelf key, reveal actions
// Landscape: console in the right 22% column, reveal card in the left 30% column.

// MARK: - First-run teaching (§6.1: through the machine, never text on the stage)

/// Duo only: a dotted ghost arc hugging the crease from above (kept above the 45% line) and soft glows on
/// both outer edges of the top half, suggesting a two-hand grip. Pinch Press teaches through the platen pulse
/// in the scene, so nothing is drawn here for it.
struct PressHints: View {
    let director: PressDirector
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private var visible: Bool {
        director.completedPresses == 0 && !director.usesTouchPress && director.engine.phase == .armed
            && director.engine.measuredDepth < 0.01 && !director.isShowingCover && director.revealed == nil
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let landscape = size.width > size.height
            ZStack {
                if visible {
                    if !landscape {
                        GhostArc()
                            .stroke(Theme.graphite.opacity(pulse ? 0.5 : 0.16),
                                    style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 9]))
                            .shadow(color: .white.opacity(0.8), radius: 2)
                            .frame(width: size.width, height: size.height)
                    }
                    EdgeGlow(pulse: pulse, landscape: landscape)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(Theme.fade, value: visible)
        .onAppear {
            guard !reduceMotion else { pulse = true; return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

/// A dotted arc above the crease (34–44% height) with an arrowhead: "fold the top down".
struct GhostArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let y = rect.height * 0.44
        let start = CGPoint(x: rect.width * 0.16, y: y)
        let end = CGPoint(x: rect.width * 0.84, y: y)
        path.move(to: start)
        path.addQuadCurve(to: end, control: CGPoint(x: rect.midX, y: rect.height * 0.30))
        path.move(to: CGPoint(x: end.x - 14, y: end.y - 9))
        path.addLine(to: end)
        path.addLine(to: CGPoint(x: end.x - 3, y: end.y - 16))
        return path
    }
}

/// Soft yellow glow on both outer edges of the top half.
private struct EdgeGlow: View {
    let pulse: Bool
    let landscape: Bool

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height * 0.44
            HStack(spacing: 0) {
                glowBar(startPoint: .leading, endPoint: .trailing)
                    .frame(width: 30, height: height)
                Spacer(minLength: 0)
                glowBar(startPoint: .trailing, endPoint: .leading)
                    .frame(width: 30, height: height)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
    }

    private func glowBar(startPoint: UnitPoint, endPoint: UnitPoint) -> some View {
        Rectangle()
            .fill(LinearGradient(colors: [Theme.yellow.opacity(pulse ? 0.6 : 0.15), .clear],
                                 startPoint: startPoint, endPoint: endPoint))
            .blur(radius: 6)
    }
}

// MARK: - Captions (§6.10)

/// Comic onomatopoeia when Captions are on: Rounded Black 40/52/64 in the object's tint with a 4 pt graphite
/// outline and a hard shadow, seeded within x 25–75% and y 22–42%. At most two on screen.
/// Hidden from VoiceOver: the director already announces them.
struct CaptionOverlay: View {
    let caption: CaptionEvent?
    let kind: ObjectKind
    @State private var live: [CaptionEvent] = []

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(live, id: \.id) { item in
                    let x = proxy.size.width * (0.25 + 0.5 * Self.unit(item.id, salt: 3))
                    let y = proxy.size.height * (0.27 + 0.11 * Self.unit(item.id, salt: 11)) // glyphs stay inside 22–42%
                    let room = 2 * min(x, proxy.size.width - x) - 16
                    CaptionBurst(caption: item, fill: Theme.captionFill(for: kind), maxWidth: room) {
                        live.removeAll { $0.id == item.id }
                    }
                    .position(x: x, y: y)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: caption) { _, new in
            guard let new else { return }
            live.append(new)
            if live.count > 2 { live.removeFirst(live.count - 2) }
        }
    }

    /// Deterministic 0…1 from the caption id.
    static func unit(_ id: Int, salt: Int) -> CGFloat {
        CGFloat(((id &* 2_654_435_761) ^ (salt &* 40_503)) & 0xFFFF) / CGFloat(0xFFFF)
    }
}

private struct CaptionBurst: View {
    let caption: CaptionEvent
    let fill: Color
    let maxWidth: CGFloat
    let onDone: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0
    @State private var rise: CGFloat = 0

    private var size: CGFloat {
        if caption.announce { return 64 }
        let text = caption.text.uppercased()
        if text.contains("CRACK") || text.contains("SNAP") || text.contains("CRUNCH") || text.contains("HONK") { return 52 }
        return 40
    }

    private var rotation: Double { Double(CaptionOverlay.unit(caption.id, salt: 29)) * 14 - 7 }

    var body: some View {
        let text = caption.text.uppercased()
        ZStack {
            // 4 pt outline from eight offset copies at 45° steps.
            ForEach(0..<8, id: \.self) { index in
                let angle = Double(index) * .pi / 4
                Text(text)
                    .foregroundStyle(Theme.graphite)
                    .offset(x: CGFloat(cos(angle)) * 4, y: CGFloat(sin(angle)) * 4)
            }
            Text(text)
                .foregroundStyle(fill)
        }
        .font(Theme.captionFont(size: size))
        .tracking(-0.5)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .frame(maxWidth: max(maxWidth, 80))
        .shadow(color: Theme.graphite.opacity(0.3), radius: 0, x: 0, y: 4)
        .rotationEffect(.degrees(reduceMotion ? 0 : rotation))
        .scaleEffect(reduceMotion ? 1 : scale)
        .offset(y: -rise)
        .opacity(opacity)
        .task {
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.2)) { opacity = 1 }
            } else {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.50)) {
                    scale = 1
                    opacity = 1
                }
            }
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 600 : 680))
            withAnimation(.easeIn(duration: 0.18)) {
                opacity = 0
                if !reduceMotion { rise = 10 }
            }
            try? await Task.sleep(for: .milliseconds(200))
            onDone()
        }
    }
}

// MARK: - Failure flash

/// The top half flashes white for 2–3 frames at a big failure (bible §3.1 beat 7), under 3 Hz.
/// Reduce Motion: 35% white for 150 ms (§6.12).
struct FailureFlash: View {
    let count: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var opacity = 0.0
    @State private var lastFlash = Date.distantPast

    var body: some View {
        GeometryReader { proxy in
            Color.white
                .opacity(opacity)
                .frame(width: proxy.size.width, height: proxy.size.height / 2)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: count) { _, _ in
            let now = Date()
            guard now.timeIntervalSince(lastFlash) > 0.34 else { return } // photosensitivity: < 3 Hz
            lastFlash = now
            if reduceMotion {
                opacity = 0.35
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(150))
                    withAnimation(.easeOut(duration: 0.1)) { opacity = 0 }
                }
            } else {
                // Hold the white for ~2 frames before fading; setting and animating back in the same
                // transaction would coalesce to "no change" and never show the flash.
                opacity = 0.85
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(34))
                    withAnimation(.easeOut(duration: 0.05)) { opacity = 0 }
                }
            }
        }
    }
}

// MARK: - Safety line (bible §3.2: the only first-run text), shown once in the toast band

struct SafetyHint: View {
    var body: some View {
        ToastView(title: "ON-SCREEN ONLY",
                  detail: "Never close your phone on real things.",
                  glyph: .symbol("hand.raised.fill"),
                  accent: Theme.stamp)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Squish is on-screen only. Never close your phone on real things.")
    }
}

// MARK: - Console (86–95%)

/// Idle console: the object chip (a quick picker of unlocked objects) and the Shelf key.
struct IdleConsole: View {
    let director: PressDirector
    let landscape: Bool
    /// Increment to make the Shelf key hop once (first discovery).
    let hop: Int
    let onShelf: () -> Void

    var body: some View {
        let layout = landscape ? AnyLayout(VStackLayout(alignment: .trailing, spacing: Theme.s3))
                               : AnyLayout(HStackLayout(spacing: Theme.s3))
        layout {
            ObjectChipPicker(director: director)
            ShelfKey(pressedCount: director.collection.pressedKindsCount,
                     total: ObjectKind.allCases.count, hop: hop, onOpen: onShelf)
        }
    }
}

/// The object chip: tint dot + name (Mono 12) on a paper chip keycap; opens a menu of unlocked objects.
struct ObjectChipPicker: View {
    let director: PressDirector

    var body: some View {
        let collection = director.collection
        Menu {
            ForEach(ObjectKind.allCases.filter { collection.isUnlocked($0) }) { kind in
                Button {
                    UIFeel.tick()
                    director.choose(kind)
                } label: {
                    if kind == director.currentKind {
                        Label(kind.displayName, systemImage: "checkmark")
                    } else {
                        Text(kind.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: Theme.s2) {
                TintDot(kind: director.currentKind)
                Text(director.currentKind.displayName.uppercased())
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(.caption2, weight: .semibold))
            }
        }
        .buttonStyle(KeycapStyle(kind: .chip))
        .menuStyle(.button)
        .accessibilityLabel("Object: \(director.currentKind.displayName)")
        .accessibilityHint("Choose what goes on the anvil.")
    }
}

/// The Shelf key on the console: dark keycap with the quiet count. Swipe up also opens the Shelf.
struct ShelfKey: View {
    let pressedCount: Int
    let total: Int
    let hop: Int
    let onOpen: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lifted = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: Theme.s2) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Text("Shelf")
                Text("\(pressedCount)/\(total)")
                    .font(Theme.label)
                    .foregroundStyle(Theme.paper.opacity(0.75))
            }
        }
        .buttonStyle(KeycapStyle(kind: .console))
        .offset(y: lifted ? -10 : 0)
        .simultaneousGesture(
            DragGesture(minimumDistance: 12).onEnded { value in
                if value.translation.height < -24 { onOpen() }
            }
        )
        .onChange(of: hop) { _, _ in
            guard !reduceMotion else { return }
            withAnimation(Theme.hop) { lifted = true }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(240))
                withAnimation(Theme.hop) { lifted = false }
            }
        }
        .accessibilityLabel("Shelf")
        .accessibilityValue("\(pressedCount) of \(total) objects pressed")
        .accessibilityHint("Opens your collection and settings.")
    }
}
