import SwiftUI

// Everything drawn over the stage on the Press screen (VISUAL-TARGET §6.1):
//   0–6%   nothing
//   6–44%  scene; overlays only for the reveal card, captions (22–42%) and the failure flash (0–50%)
//   45–80% STAGE: nothing, ever
//   80–86% toasts, one at a time
//   86–95% console: object chip, Shelf key, reveal actions
// Landscape (book pose): the camera rolls so the ram comes from the left; the console is in the right 22% column.
// Assumption shared with Scene: in book pose the moving (ram) half is the LEFT half.

// MARK: - Pinch Press handle (non-folding iPhones)

/// The touch press's affordance (bible §2 "drag on the ram handle"; screenshots.md §C P1; FOLD-REVIEW-5 N6): a
/// graphite grip plate mounted on the front of the P-48's crosshead, with knurled grips and a yellow chevron, so the
/// idle machine shows what to grab. Until the third press it reads "DRAG DOWN TO PRESS". It sits on the crosshead
/// (≈ 39–44 % of the screen height, preset P framing), above the 45–80 % stage, so it keeps VISUAL-TARGET §6.1's
/// "nothing in the stage" rule, and it nudges down with the scene's teaching pulse rhythm (1.6 s).
///
/// Only at rest: it fades out as the press starts (zero UI during a press) and never shows on the Fold Press, in book
/// pose or on a Duo-shaped screen, where the crosshead isn't at these fractions. Never hit-testable: the whole stage
/// is the drag target, and the handle only tells you so.
struct PinchHandle: View {
    let director: PressDirector
    /// Hidden while the reveal card, cover or a collect is on screen.
    var suppressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Crosshead front face at rest, as fractions of the full screen height (r5 `01-launch`, 18 Pro: y 0.39–0.44).
    static let restCentreY: CGFloat = 0.414
    /// Tall portrait phones only (aspect ≤ 0.58): the scene uses camera preset P there, so the crosshead sits at the
    /// same height fraction on every modern iPhone. Wider screens (Duo inner, landscape) are framed differently.
    static let maxAspect: CGFloat = 0.58

    private var atRest: Bool {
        !suppressed && director.usesTouchPress && !director.usesFoldPress && !director.isShowingCover
            && director.revealed == nil && director.canChooseObject
    }

    private var showsWords: Bool { director.completedPresses < 3 }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let fits = size.height > 0 && size.width / size.height <= Self.maxAspect
            if fits && atRest {
                // ~270 pt on a 6.1"/6.9" phone: inside the crosshead's ~330 pt front face.
                let width = min(size.width * 0.68, size.height * 0.31)
                plate(width: width)
                    // A 3 pt downward nudge every 1.6 s ("this way"); static under Reduce Motion.
                    .phaseAnimator(reduceMotion ? [false] : [false, true]) { content, lowered in
                        content.offset(y: lowered ? 3 : 0)
                    } animation: { _ in
                        .easeInOut(duration: 0.8)
                    }
                    .position(x: size.width / 2, y: size.height * Self.restCentreY)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true) // the stage's own label and hint say "swipe up to press down"
        .animation(Theme.fade, value: atRest)
    }

    private func plate(width: CGFloat) -> some View {
        HStack(spacing: Theme.s2) {
            Grip()
            Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(Theme.yellow)
            if showsWords {
                Text("DRAG DOWN TO PRESS")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(Theme.microTracking)
                    .foregroundStyle(Theme.paper)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(Theme.yellow)
            }
            Grip()
        }
        .padding(.horizontal, Theme.s3)
        .frame(width: showsWords ? width : width * 0.55, height: 32)
        .background {
            // A raised graphite plate with a lip, like the console keycaps (§6.6), and a yellow keyline.
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.rgb(0x16171A))
                    .offset(y: 3)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.rgb(0x3A3D43), Theme.graphite],
                                         startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.yellow.opacity(0.55), lineWidth: 1)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.large) // painted on the machine: a fixed composition
    }

    /// Three knurled ridges at each end of the plate: "grab here".
    private struct Grip: View {
        var body: some View {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule().fill(Theme.paper.opacity(0.55)).frame(width: 2, height: 14)
                }
            }
        }
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
    var compact = false

    var body: some View {
        ToastView(title: tip.title, detail: tip.detail, glyph: tip.object.map { ToastView.Glyph.object($0) } ?? ToastView.Glyph.symbol(tip.symbol),
                  accent: tip.accent, compact: compact)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(tip.title.capitalized). \(tip.detail)")
    }
}

extension ObjectKind {
    /// Short console-chip name ("UNSQUISHABLE", not "THE UNSQUISHABLE").
    var chipName: String {
        let name = displayName.hasPrefix("The ") ? String(displayName.dropFirst(4)) : displayName
        return name.uppercased()
    }
}
