import SwiftUI

// S10 Pause & Help (UX-AUDIT-2 §4.2): three illustrated how-to cards, and the pause card that appears when a press is
// left half-closed or the app goes to the background mid-press.

struct HelpView: View {
    /// Replays the first-run lesson (S1) on the press.
    var onReplayIntro: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    @Environment(\.windowIsLandscape) private var windowIsLandscape
    @AppStorage("squish.hasHinge") private var hasHinge = false

    var body: some View {
        if SheetPose.isBook(hasHinge: hasHinge, windowIsLandscape: windowIsLandscape) {
            // Book pose: the cards on the leading page, the reminders and the keys on the trailing one.
            BookSpread {
                VStack(alignment: .leading, spacing: Theme.s4) {
                    header
                    cards
                }
            } right: {
                VStack(alignment: .leading, spacing: Theme.s4) {
                    reminders
                }
            }
        } else {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, Theme.s4)
                    .padding(.top, 20)
                    .padding(.bottom, Theme.s3)
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity)
                ScrollView {
                    VStack(spacing: Theme.s4) {
                        cards
                        reminders
                    }
                    .padding(.horizontal, Theme.s4)
                    .padding(.bottom, Theme.s6)
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Theme.s1) {
                Text("How to press")
                    .font(Theme.sheetTitle)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(hasHinge ? "THREE WAYS. ALL OF THEM SLOWLY." : "ONE FINGER. SLOWLY.")
                    .font(Theme.label)
                    .tracking(Theme.labelTracking)
                    .foregroundStyle(Theme.inkSecondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(.subheadline, weight: .semibold))
            }
            .buttonStyle(KeycapStyle(kind: .secondary, round: true))
            .accessibilityLabel("Close")
        }
    }

    @ViewBuilder
    private var cards: some View {
        if !hasHinge {
            // Phones that don't fold: one way to press, and no fold talk at all.
            HelpCard(title: "Drag down",
                     detail: "Put a finger on the press and drag down, slowly. Let go to ease off.",
                     art: .drag)
        } else {
            HelpCard(title: "Like a tiny laptop",
                     detail: "Stand it on a table, open it wide, then push the top half down slowly.",
                     art: .tabletop)
            HelpCard(title: "Like a book",
                     detail: "Hold it open in both hands and close it slowly, like a book you're done with.",
                     art: .book)
            HelpCard(title: "Or drag",
                     detail: "Settings → Press without folding. Then drag down on the press. Same squish.",
                     art: .drag)
        }
    }

    @ViewBuilder
    private var reminders: some View {
            VStack(alignment: .leading, spacing: Theme.s2) {
                if hasHinge {
                    bullet("arrow.up.left.and.arrow.down.right", "Open it again to see what's left.")
                } else {
                    bullet("hand.draw.fill", "Squish it flat, then see what's left.")
                }
                bullet("pause.fill", "Ease off any time. The damage stays.")
                bullet("tortoise.fill", "Slow and steady earns a Perfect Squish.")
                bullet("hand.raised.fill", hasHinge ? "It's all on-screen. Never close your phone on real things."
                                                    : "It's all on-screen. Never squish real things.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let onReplayIntro {
                Button {
                    dismiss()
                    onReplayIntro()
                } label: {
                    KeyLabel(title: "Show me on the press", systemImage: "play.fill")
                }
                .buttonStyle(KeycapStyle(kind: .primary, fullWidth: true))
                .accessibilityHint("Replays the first-run lesson with bubble wrap.")
            }
            Button {
                dismiss()
            } label: {
                Text("Got it")
            }
            .buttonStyle(KeycapStyle(kind: .secondary, fullWidth: true))
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.s3) {
            Image(systemName: symbol)
                .font(.system(.footnote, weight: .bold))
                .foregroundStyle(Theme.graphite)
                .frame(width: 20)
            Text(text.keepingLastWordsTogether)
                .font(Theme.body)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One looping, illustrated how-to card. Reduce Motion: the art holds still, half-closed.
struct HelpCard: View {
    enum Art { case tabletop, book, drag }
    let title: String
    let detail: String
    let art: Art
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        HStack(spacing: Theme.s4) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.stickerRadius, style: .continuous)
                    .fill(Theme.paperShade.opacity(0.55))
                illustration
                    .padding(Theme.s2)
            }
            .frame(width: 120, height: 96)
            VStack(alignment: .leading, spacing: Theme.s1) {
                Text(title)
                    .font(Theme.headline)
                    .foregroundStyle(Theme.ink)
                Text(detail.keepingLastWordsTogether)
                    .font(Theme.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.s4)
        .background { shape.fill(Theme.paperWarm).elevation(.e1) }
        .topHighlight(cornerRadius: Theme.cardRadius)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var illustration: some View {
        switch art {
        case .drag:
            DragGlyph()
        case .tabletop, .book:
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
                let angle = reduceMotion ? 110 : Self.angle(at: context.date.timeIntervalSinceReferenceDate)
                HingeGlyph(angle: angle, ready: angle >= 130, readyFrom: 130)
                    // A book is the same fold, held on its side.
                    .rotationEffect(.degrees(art == .book ? -90 : 0))
            }
        }
    }

    /// 2.4 s close from 170° to 50°, 0.6 s hold, 1 s back open.
    nonisolated static func angle(at time: Double) -> Double {
        let t = time.truncatingRemainder(dividingBy: 4.0)
        func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }
        switch t {
        case ..<2.4: return 170 - 120 * ease(t / 2.4)
        case ..<3.0: return 50
        default: return 50 + 120 * ease((t - 3.0) / 1.0)
        }
    }
}

/// The automatic pause (S10): "Paused at 38 tons. Close to keep going, or open it up to ease off."
struct PauseCard: View {
    let tons: Int
    let touch: Bool
    let onResume: () -> Void
    let onHelp: () -> Void
    let onMenu: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: Theme.s3) {
            HStack(spacing: Theme.s2) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(.title2, weight: .bold))
                    .foregroundStyle(Theme.yellowLip)
                VStack(alignment: .leading, spacing: 1) {
                    Text("PAUSED AT \(tons) TONS")
                        .font(Theme.label)
                        .tracking(Theme.labelTracking)
                        .foregroundStyle(Theme.inkSecondary)
                    Text(touch ? "Drag to keep going." : "Close to keep going.")
                        .font(Theme.headline)
                        .foregroundStyle(Theme.ink)
                }
            }
            Text((touch ? "Or let go to ease off. The damage stays." : "Or open it up to ease off. The damage stays.").keepingLastWordsTogether)
                .font(Theme.footnote)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.s2) {
                Button(action: onResume) { KeyLabel(title: "Keep going", systemImage: "play.fill") }
                    .buttonStyle(KeycapStyle(kind: .primary, fullWidth: true, compact: true))
                Button(action: onHelp) {
                    Image(systemName: "questionmark")
                        .font(.system(.subheadline, weight: .bold))
                }
                .buttonStyle(KeycapStyle(kind: .secondary, round: true))
                .accessibilityLabel("How to press")
                Button(action: onMenu) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(.subheadline, weight: .bold))
                }
                .buttonStyle(KeycapStyle(kind: .secondary, round: true))
                .accessibilityLabel("Menu")
            }
        }
        .padding(Theme.s4)
        .background { PaperBackground().clipShape(shape).elevation(.e3) }
        .topHighlight(cornerRadius: Theme.cardRadius)
        .frame(maxWidth: 420)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .contain)
    }
}
