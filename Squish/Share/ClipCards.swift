import SwiftUI
import UIKit

/// The share clip's title and end cards (bible §10), drawn with the app's own paper, type and colour tokens
/// (VISUAL-TARGET §6) at 360 × 640 pt × 3 = 1080 × 1920 px. Fixed compositions: Dynamic Type pinned, light mode.
enum ClipCards {
    static let size = CGSize(width: 360, height: 640)
    static let scale: CGFloat = 3

    /// "RUBBER DUCK vs SQUISH".
    @MainActor static func title(for specimen: SpecimenRecord) -> CGImage? {
        render(ClipTitleCard(specimen: specimen))
    }

    /// The specimen card (with the clip's own final frame as its photo), traits and the watermark.
    @MainActor static func end(for specimen: SpecimenRecord, still: UIImage?) -> CGImage? {
        render(ClipEndCard(specimen: specimen, still: still))
    }

    /// The flattened specimen from a full 9:16 frame: the stage band where the object sits (VISUAL-TARGET §3.2).
    static func specimenCrop(of frame: CGImage) -> UIImage? {
        let width = CGFloat(frame.width)
        let height = CGFloat(frame.height)
        let rect = CGRect(x: 0, y: height * 0.40, width: width, height: height * 0.46).integral
        guard let cropped = frame.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped)
    }

    @MainActor private static func render<Content: View>(_ content: Content) -> CGImage? {
        let renderer = ImageRenderer(content: content
            .frame(width: size.width, height: size.height)
            .environment(\.dynamicTypeSize, .large)
            .environment(\.colorScheme, .light))
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(size)
        renderer.isOpaque = true
        return renderer.cgImage
    }
}

/// Title card: the object as a die-cut sticker, its name, and a hydraulic-yellow SQUISH keycap.
private struct ClipTitleCard: View {
    let specimen: SpecimenRecord

    var body: some View {
        ZStack {
            Theme.gel(for: specimen.kind, golden: specimen.variant.isGolden)
            PaperBackground(tone: .clear)
            VStack(spacing: 22) {
                Spacer(minLength: 0)
                Sticker(seed: specimen.variant.seed, golden: specimen.variant.isGolden) {
                    ObjectTile(kind: specimen.kind, cornerRadius: Theme.stickerRadius, golden: specimen.variant.isGolden)
                }
                .frame(width: 150, height: 150)
                .rotationEffect(.degrees(-6))
                VStack(spacing: 10) {
                    Text(specimen.kind.displayName.uppercased())
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, 28)
                    Text("vs")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.inkSecondary)
                    Text("SQUISH")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(Theme.graphite)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 10)
                        .background {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Theme.yellowLip)
                                .offset(y: 5)
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Theme.yellow)
                        }
                        .rotationEffect(.degrees(-2))
                }
                Spacer(minLength: 0)
                Text(specimen.numberLabel)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .tracking(Theme.microTracking)
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.bottom, 40)
            }
        }
    }
}

/// End card: the pressed specimen card, its traits, and the small "Squish · iPhone Duo" watermark.
private struct ClipEndCard: View {
    let specimen: SpecimenRecord
    let still: UIImage?

    var body: some View {
        ZStack {
            Theme.gel(for: specimen.kind, golden: specimen.variant.isGolden)
            PaperBackground(tone: .clear)
            VStack(spacing: 16) {
                Spacer(minLength: 0)
                SpecimenCardView(specimen: specimen, thumbnail: still, style: .detail)
                    .frame(width: 292)
                if !specimen.traits.isEmpty {
                    FlowLayout(spacing: Theme.s2, lineSpacing: Theme.s2) {
                        ForEach(specimen.traits) { trait in
                            TraitChip(text: trait.text, systemImage: trait.systemImage, tone: trait.tone)
                        }
                    }
                    .frame(maxWidth: 292)
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Circle().fill(Theme.yellow).frame(width: 7, height: 7)
                    Text("Squish · iPhone Duo")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.inkSecondary)
                }
                .padding(.bottom, 36)
            }
        }
    }
}
