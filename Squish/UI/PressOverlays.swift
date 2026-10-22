import SwiftUI

// Everything drawn over the stage on the Press screen (VISUAL-TARGET §6.1):
//   0–6%   nothing
//   6–44%  scene; overlays only for the reveal card, captions (22–42%) and the failure flash (0–50%)
//   45–80% STAGE: nothing, ever
//   80–86% toasts, one at a time
//   86–95% console: object chip, Shelf key, reveal actions
// Landscape (book pose): the camera rolls so the ram comes from the left; the console is in the right 22% column.
// Assumption shared with Scene: in book pose the moving (ram) half is the LEFT half.

// MARK: - First-run teaching (§6.1: through the machine, never text on the stage)

/// Duo only: a dotted "side-view hinge" arc — from the outer edge of the moving half, curving down to the
/// crease, arrowhead at the crease, dashes marching toward it — plus soft glows on the moving half's outer
/// edges (two-hand grip). Retired for good after the first contact (UX-REVIEW-1 P2-2, P2-17, P1-14).
struct PressHints: View {
    let director: PressDirector
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("squish.arcRetired") private var retired = false
    @State private var pulse = false

    private var visible: Bool {
        !retired && director.completedPresses == 0 && !director.usesTouchPress && director.engine.phase == .armed
            && director.engine.measuredDepth < 0.01 && !director.isShowingCover && director.revealed == nil
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let landscape = size.width > size.height
            ZStack {
                if visible {
                    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
                        let phase = reduceMotion ? 0 : CGFloat(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.6) / 0.6) * -11
                        GhostArc(landscape: landscape)
                            .stroke(Theme.graphite.opacity(pulse ? 0.55 : 0.25),
                                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [2, 9], dashPhase: phase))
                            .shadow(color: .white.opacity(0.8), radius: 2)
                    }
                    .frame(width: size.width, height: size.height)
                    EdgeGlow(pulse: pulse, landscape: landscape)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(Theme.fade, value: visible)
        .onChange(of: director.engine.phase) { _, phase in
            if phase == .pressing { retired = true }
        }
        .onAppear {
            guard !reduceMotion else { pulse = true; return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

/// The lid's path seen from the side: a quarter-curve from the moving half's outer edge down to the crease,
/// with an arrowhead along the tangent. Portrait stays above the 45% line.
struct GhostArc: Shape {
    var landscape: Bool

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let start, end, c1, c2: CGPoint
        if landscape {
            // Moving half = left; crease = vertical centre line.
            start = CGPoint(x: w * 0.06, y: h * 0.22)
            c1 = CGPoint(x: w * 0.30, y: h * 0.22)
            c2 = CGPoint(x: w * 0.44, y: h * 0.32)
            end = CGPoint(x: w * 0.47, y: h * 0.50)
        } else {
            start = CGPoint(x: w * 0.30, y: h * 0.10)
            c1 = CGPoint(x: w * 0.30 + w * 0.34, y: h * 0.10)
            c2 = CGPoint(x: w * 0.72, y: h * 0.26)
            end = CGPoint(x: w * 0.72, y: h * 0.42)
        }
        var path = Path()
        path.move(to: start)
        path.addCurve(to: end, control1: c1, control2: c2)
        // Arrowhead along the end tangent.
        let dx = end.x - c2.x, dy = end.y - c2.y
        let length = max(sqrt(dx * dx + dy * dy), 0.001)
        let ux = dx / length, uy = dy / length
        let back = CGPoint(x: end.x - ux * 14, y: end.y - uy * 14)
        path.move(to: CGPoint(x: back.x - uy * 8, y: back.y + ux * 8))
        path.addLine(to: end)
        path.addLine(to: CGPoint(x: back.x + uy * 8, y: back.y - ux * 8))
        return path
    }
}

/// Soft yellow glow on the moving half's two outer edges.
private struct EdgeGlow: View {
    let pulse: Bool
    let landscape: Bool

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            if landscape {
                // Left half: glow its top and bottom edges.
                VStack(spacing: 0) {
                    glowBar(startPoint: .top, endPoint: .bottom).frame(width: w * 0.44, height: 30)
                    Spacer(minLength: 0)
                    glowBar(startPoint: .bottom, endPoint: .top).frame(width: w * 0.44, height: 30)
                }
                .frame(width: w, height: h, alignment: .leading)
            } else {
                HStack(spacing: 0) {
                    glowBar(startPoint: .leading, endPoint: .trailing).frame(width: 30, height: h * 0.44)
                    Spacer(minLength: 0)
                    glowBar(startPoint: .trailing, endPoint: .leading).frame(width: 30, height: h * 0.44)
                }
                .frame(width: w, height: h, alignment: .top)
            }
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
                    // Book pose: keep captions on the moving (left) half, off the vertical crease.
                    let landscape = proxy.size.width > proxy.size.height
                    let x = proxy.size.width * (landscape ? 0.10 + 0.28 * Self.unit(item.id, salt: 3)
                                                          : 0.25 + 0.5 * Self.unit(item.id, salt: 3))
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

/// The moving half flashes white for 2–3 frames at a big failure (bible §3.1 beat 7), under 3 Hz:
/// the top half in portrait, the left half in book pose. Reduce Motion: 35% white for 150 ms (§6.12).
struct FailureFlash: View {
    let count: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var opacity = 0.0
    @State private var lastFlash = Date.distantPast

    var body: some View {
        GeometryReader { proxy in
            let landscape = proxy.size.width > proxy.size.height
            Color.white
                .opacity(opacity)
                .frame(width: landscape ? proxy.size.width / 2 : proxy.size.width,
                       height: landscape ? proxy.size.height : proxy.size.height / 2)
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
                opacity = 0.85
                // Hold the white for ~2 frames before fading; setting and animating back in the same
                // transaction would coalesce to "no change" and never show the flash.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(34))
                    withAnimation(.easeOut(duration: 0.05)) { opacity = 0 }
                }
            }
        }
    }
}

// MARK: - Tip toast (80–86%)

struct TipToast: View {
    let tip: SquishTip

    var body: some View {
        ToastView(title: tip.title, detail: tip.detail, glyph: .symbol(tip.symbol), accent: tip.accent)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(tip.title.capitalized). \(tip.detail)")
    }
}

// MARK: - Console (86–95%)

/// Idle console: the object chip (a quick picker) and the Shelf key. During a collect, only the Shelf key shows,
/// so the card has somewhere real to land.
struct IdleConsole: View {
    let director: PressDirector
    let landscape: Bool
    /// Increment to make the Shelf key hop once (first discovery).
    let hop: Int
    /// Increment when a card lands in the Shelf key.
    let bump: Int
    var shelfOnly = false
    let onShelf: () -> Void
    /// The Shelf key's global frame, for the collect flight.
    var onShelfFrame: (CGRect) -> Void = { _ in }

    /// Fixed console width: two fixed slots so nothing shifts between objects (VISUAL-REVIEW-1 #14).
    var width: CGFloat = 360

    var body: some View {
        Group {
            if landscape {
                VStack(spacing: Theme.s3) {
                    chip.frame(width: width)
                    key.frame(width: width)
                }
            } else {
                HStack(spacing: Theme.s3) {
                    chip.frame(width: (width - Theme.s3) * 0.54)
                    key.frame(width: (width - Theme.s3) * 0.46)
                }
            }
        }
        .frame(width: width)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// The chip keeps its slot during a collect (just hidden), so the Shelf key never moves.
    private var chip: some View {
        ObjectChipPicker(director: director)
            .opacity(shelfOnly ? 0 : 1)
            .allowsHitTesting(!shelfOnly)
            .accessibilityHidden(shelfOnly)
    }

    private var key: some View {
        ShelfKey(pressedCount: director.collection.pressedKindsCount,
                 total: ObjectKind.allCases.count, hop: hop, bump: bump, onOpen: onShelf)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onShelfFrame($0) }
    }
}

/// The object chip: tint dot + name (Mono 12) on a paper chip keycap; opens a menu of objects
/// (unlocked ones selectable, locked ones listed with their hint as a teaser).
struct ObjectChipPicker: View {
    let director: PressDirector

    var body: some View {
        let collection = director.collection
        let unlocked = ObjectKind.allCases.filter { collection.isUnlocked($0) }
        let locked = ObjectKind.allCases.filter { !collection.isUnlocked($0) }
        Menu {
            Section {
                ForEach(unlocked) { kind in
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
            }
            if !locked.isEmpty {
                Section("Locked") {
                    ForEach(locked) { kind in
                        Button {} label: {
                            Text("\(kind.isSecret ? "???" : kind.displayName) · \(collection.menuHint(for: kind))")
                        }
                        .disabled(true)
                    }
                }
            }
        } label: {
            HStack(spacing: Theme.s2) {
                TintDot(kind: director.currentKind)
                Text(director.currentKind.chipName)
                    .contentTransition(.opacity)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(.caption2, weight: .semibold))
            }
        }
        .buttonStyle(KeycapStyle(kind: .chip, fullWidth: true))
        .menuStyle(.button)
        .accessibilityLabel("Object: \(director.currentKind.displayName)")
        .accessibilityHint("Choose what goes on the anvil.")
    }
}

/// The Shelf key on the console: dark keycap with the quiet count (hidden until the first card, P2-3).
/// Swipe up also opens the Shelf. Hops once on discovery (a yellow glow under Reduce Motion), and sinks in
/// when a collected card lands.
struct ShelfKey: View {
    let pressedCount: Int
    let total: Int
    let hop: Int
    let bump: Int
    let onOpen: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lifted = false
    @State private var sunk = false
    @State private var glow = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: Theme.s2) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Text("Shelf")
                if pressedCount > 0 {
                    Text("\(pressedCount)/\(total)")
                        .font(Theme.label)
                        .foregroundStyle(Theme.paper.opacity(0.75))
                        .contentTransition(.numericText())
                        .animation(Theme.pop(reduceMotion), value: pressedCount)
                }
            }
        }
        .buttonStyle(KeycapStyle(kind: .console, fullWidth: true))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.yellow, lineWidth: 2)
                .padding(.bottom, 4)
                .opacity(glow ? 0.8 : 0)
                .allowsHitTesting(false)
        }
        .scaleEffect(sunk ? 0.94 : 1)
        .offset(y: (lifted ? -10 : 0) + (sunk ? 3 : 0))
        .simultaneousGesture(
            DragGesture(minimumDistance: 12).onEnded { value in
                if value.translation.height < -24 { onOpen() }
            }
        )
        .onChange(of: hop) { _, _ in
            Task { @MainActor in
                if reduceMotion {
                    for _ in 0..<2 {
                        withAnimation(.easeInOut(duration: 0.5)) { glow = true }
                        try? await Task.sleep(for: .milliseconds(500))
                        withAnimation(.easeInOut(duration: 0.5)) { glow = false }
                        try? await Task.sleep(for: .milliseconds(500))
                    }
                } else {
                    withAnimation(Theme.hop) { lifted = true }
                    try? await Task.sleep(for: .milliseconds(240))
                    withAnimation(Theme.hop) { lifted = false }
                }
            }
        }
        .onChange(of: bump) { _, _ in
            Task { @MainActor in
                withAnimation(Theme.keyDown) { sunk = true }
                UIFeel.success()
                try? await Task.sleep(for: .milliseconds(120))
                withAnimation(Theme.keyUp) { sunk = false }
            }
        }
        .accessibilityLabel("Shelf")
        .accessibilityValue(pressedCount > 0 ? "\(pressedCount) of \(total) objects pressed" : "")
        .accessibilityHint("Opens your collection and settings.")
    }
}

extension ObjectKind {
    /// Short console-chip name ("UNSQUISHABLE", not "THE UNSQUISHABLE").
    var chipName: String {
        let name = displayName.hasPrefix("The ") ? String(displayName.dropFirst(4)) : displayName
        return name.uppercased()
    }
}
