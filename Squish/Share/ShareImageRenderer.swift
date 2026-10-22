import SwiftUI
import UIKit

/// The before/after share card (bible §10): 1080 × 1350 PNG (4:5, friendly to every feed).
/// "After" is the specimen card itself; "before" is a die-cut sticker of the object stuck on its corner.
/// A small "Squish · iPhone Duo" watermark sits underneath. System share sheet only — no SDKs, no tracking.
enum ShareImageRenderer {
    static let size = CGSize(width: 360, height: 450)
    static let scale: CGFloat = 3

    @MainActor static func render(specimen: SpecimenRecord, thumbnail: UIImage?) -> UIImage? {
        let renderer = ImageRenderer(content: ShareCard(specimen: specimen, thumbnail: thumbnail))
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(size)
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// Renders and writes a PNG to a temporary file with a friendly name, ready for the share sheet.
    @MainActor static func renderFile(specimen: SpecimenRecord, thumbnail: UIImage?) -> URL? {
        guard let image = render(specimen: specimen, thumbnail: thumbnail), let data = image.pngData() else { return nil }
        let name = "Squish-\(specimen.kind.displayName.replacingOccurrences(of: " ", with: "-"))-\(String(format: "%04ld", specimen.number)).png"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

/// Fixed composition: an image, not UI, so Dynamic Type is pinned to the default size.
private struct ShareCard: View {
    let specimen: SpecimenRecord
    let thumbnail: UIImage?

    var body: some View {
        ZStack {
            Theme.gel(for: specimen.kind, golden: specimen.variant.isGolden)
            PaperBackground(tone: .clear)
            VStack(spacing: 10) {
                SpecimenCardView(specimen: specimen, thumbnail: thumbnail, style: .detail)
                    .frame(width: 282)
                    .overlay(alignment: .topLeading) {
                        VStack(spacing: 4) {
                            Sticker(seed: specimen.variant.seed &+ 7) {
                                ObjectTile(kind: specimen.kind, cornerRadius: 10, golden: specimen.variant.isGolden)
                            }
                            .frame(width: 68, height: 68)
                            .rotationEffect(.degrees(-8))
                            Text("BEFORE")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .tracking(1)
                                .foregroundStyle(Theme.inkSecondary)
                        }
                        .offset(x: -30, y: -18)
                    }
                HStack(spacing: 6) {
                    Circle().fill(Theme.yellow).frame(width: 7, height: 7)
                    Text("Squish · iPhone Duo")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .padding(.top, 12)
        }
        .frame(width: ShareImageRenderer.size.width, height: ShareImageRenderer.size.height)
        .environment(\.dynamicTypeSize, .large)
        .environment(\.colorScheme, .light)
    }
}
