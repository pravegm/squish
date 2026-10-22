import SwiftUI
import UIKit

/// The pressed-specimen card (VISUAL-TARGET §6.8, bible §5): a 3:4 paper card, the specimen render in the top
/// 62%, a hairline, then the label block (name, two SF Mono data lines, serial, flavour line). The red ink
/// PRESSED stamp overlaps the render's lower-right corner. Golden gets a foil border and two sparkles;
/// Perfect Squish gets a round seal. Reads as one sentence to VoiceOver.
struct SpecimenCardView: View {
    enum Style { case reveal, detail }

    let specimen: SpecimenRecord
    var thumbnail: UIImage?
    var style: Style = .detail
    /// Reveal only: the stamp falls a beat after the card lands.
    var animateStamp = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stampDown: Bool

    init(specimen: SpecimenRecord, thumbnail: UIImage? = nil, style: Style = .detail, animateStamp: Bool = false) {
        self.specimen = specimen
        self.thumbnail = thumbnail
        self.style = style
        self.animateStamp = animateStamp
        _stampDown = State(initialValue: !animateStamp)
    }

    private var golden: Bool { specimen.variant.isGolden }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous) }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let renderHeight = height * 0.62
            VStack(spacing: 0) {
                render
                    .frame(height: renderHeight)
                Rectangle()
                    .fill(Theme.paperEdge)
                    .frame(height: 1)
                    .padding(.horizontal, Theme.s3 + 2)
                labelBlock
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .overlay(alignment: .topLeading) {
                PressedStamp(seed: specimen.variant.seed, text: specimen.stampText, date: specimen.date,
                             fixedAngle: specimen.kind == .unsquishable ? -4 : nil)
                    .scaleEffect(style == .reveal ? 0.82 : 1)
                    .scaleEffect(stampDown ? 1 : (reduceMotion ? 1 : 1.6))
                    .opacity(stampDown ? 1 : 0)
                    .position(x: width * (specimen.kind == .unsquishable ? 0.62 : 0.74), y: renderHeight + 6)
            }
        }
        .aspectRatio(0.75, contentMode: .fit)
        .background { PaperBackground().clipShape(shape) }
        .overlay {
            if golden {
                shape.strokeBorder(AngularGradient(colors: [Theme.goldSoft, Theme.gold, Theme.goldSoft, Theme.gold, Theme.goldSoft],
                                                   center: .center), lineWidth: 3)
            } else {
                shape.strokeBorder(Theme.paperEdge, lineWidth: 1)
            }
        }
        .topHighlight(cornerRadius: Theme.cardRadius)
        .elevation(style == .reveal ? .e3 : .e2)
        .cardTypeCap(style == .reveal ? .xLarge : .xxxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(specimen.accessibilitySentence)
        .onAppear(perform: landStamp)
    }

    // MARK: Parts

    /// The specimen render on paper with a soft drop shadow, plus seal / sparkles / surprise tag.
    private var render: some View {
        SpecimenImage(specimen: specimen, thumbnail: thumbnail, cornerRadius: 12)
            .shadow(color: Theme.shadowInk.opacity(0.18), radius: 6, y: 3)
            .padding(Theme.s3 + 2)
            .animation(.easeInOut(duration: 0.5), value: thumbnail != nil)
            .overlay(alignment: .topTrailing) {
                if specimen.isPerfect {
                    PerfectSeal()
                        .scaleEffect(style == .reveal ? 0.85 : 1)
                        .padding(Theme.s1)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if let surprise = specimen.variant.surprise {
                    Text(surprise.title)
                        .font(Theme.micro)
                        .tracking(Theme.microTracking)
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Theme.rgb(0xDCEBFA), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .rotationEffect(.degrees(-3))
                        .padding(.leading, Theme.s2)
                        .padding(.bottom, Theme.s2)
                }
            }
            .overlay {
                if golden {
                    GeometryReader { proxy in
                        Sparkle().fill(Theme.gold).frame(width: 14, height: 14)
                            .position(x: proxy.size.width * 0.12, y: proxy.size.height * 0.14)
                        Sparkle().fill(Theme.goldSoft).frame(width: 10, height: 10)
                            .position(x: proxy.size.width * 0.88, y: proxy.size.height * 0.80)
                    }
                }
            }
    }

    private var labelBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.s2) {
                Text(specimen.kind.displayName)
                    .font(style == .reveal ? Theme.headline : Theme.display)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: Theme.s1)
                Text(specimen.numberLabel)
                    .font(Theme.micro)
                    .tracking(Theme.microTracking)
                    .foregroundStyle(golden ? Theme.rgb(0x8A5A00) : Theme.inkSecondary)
            }
            .padding(.bottom, 2)
            ForEach(specimen.labelLines, id: \.self) { line in
                Text(line)
                    .font(Theme.label)
                    .tracking(Theme.labelTracking)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Text(specimen.flavourLine)
                .font(Theme.footnote)
                .italic()
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(style == .reveal ? 1 : 2)
                .minimumScaleFactor(0.8)
                .padding(.top, 2)
        }
        .padding(.horizontal, Theme.s3 + 2)
        .padding(.top, Theme.s2 + 2)
        .padding(.bottom, Theme.s2)
    }

    /// Choreography (§6.8): the stamp falls ~350 ms after the card, with a haptic on contact.
    private func landStamp() {
        guard animateStamp, !stampDown else {
            stampDown = true
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(Theme.stampFall(reduceMotion)) { stampDown = true }
            try? await Task.sleep(for: .milliseconds(110))
            UIFeel.press()
        }
    }
}

/// Wrapping row for trait chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let childProposal = proposal.width.map { ProposedViewSize(width: $0, height: nil) } ?? .unspecified
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(childProposal)
            if x > 0 && x + size.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            widest = max(widest, x + size.width)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: widest, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let childProposal = ProposedViewSize(width: bounds.width, height: nil)
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(childProposal)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
