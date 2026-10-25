import SwiftUI
import UIKit

/// The one picture of an object everywhere you choose and collect (EXPERIENCE-REVIEW-1 #10): the Tray, the console's
/// tray chip, the cover lobby and the Shelf. It shows the object's real 3D render (`ObjectThumbnails`, the objects
/// engineer's offscreen renders), at rest or `crushed` (the pressed specimen, where one exists). Until a render is
/// ready, the candy tile (`ObjectTile`) stands in, so a tile is never blank.
struct ObjectArt: View {
    let kind: ObjectKind
    var crushed = false
    var cornerRadius: CGFloat = Theme.stickerRadius
    var golden = false

    /// One render size for every tile (points, square), so each object is rendered once per look and scaled down for
    /// small chips.
    static let renderSize = CGSize(width: 160, height: 160)

    @State private var rendered: UIImage?

    private var look: ObjectThumbnails.Look { crushed ? .crushed : .rest }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
            if let image = rendered ?? ObjectThumbnails.cached(kind, look: look, size: Self.renderSize) {
                Color.clear
                    .overlay {
                        Image(uiImage: image)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                    }
                    .clipShape(shape)
                    .overlay {
                        if golden { shape.strokeBorder(Theme.gold, lineWidth: 2) }
                    }
                    .transition(.opacity)
            } else {
                ObjectTile(kind: kind, cornerRadius: cornerRadius, golden: golden)
            }
        }
        .animation(Theme.fade, value: rendered)
        .task(id: "\(kind.rawValue)-\(look.rawValue)") {
            guard rendered == nil else { return }
            rendered = await ObjectThumbnails.image(kind, look: look, size: Self.renderSize)
        }
        .accessibilityHidden(true)
    }

    /// Renders every object (at rest, then crushed) in the background once the press room is up, so the Tray and the
    /// cover open on real pictures. Skips what is already on disk.
    @MainActor
    static func prewarm() async {
        await ObjectThumbnails.prewarm(size: renderSize)
    }
}
