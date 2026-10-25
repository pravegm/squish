import SwiftUI
import UIKit

/// The one picture of an object everywhere you choose and collect (EXPERIENCE-REVIEW-1 #10): the Tray, the console's
/// tray chip, the cover lobby and the Shelf. It shows the object's real 3D render (`ObjectThumbnails`, the objects
/// engineer's offscreen renders), at rest or `crushed` (the pressed specimen, where one exists). Until a render is
/// ready, the candy tile (`ObjectTile`) stands in, so a tile is never blank. A crushed look never stands in with the
/// intact tile: use `CrushedBadge`, which shows nothing until the crushed render exists.
struct ObjectArt: View {
    let kind: ObjectKind
    var crushed = false
    var cornerRadius: CGFloat = Theme.stickerRadius
    var golden = false

    /// One render size for every tile (points, square), so each object is rendered once per look and scaled down for
    /// small chips.
    static let renderSize = CGSize(width: 160, height: 160)

    /// The press gate (launch QA #12): renders only start while this holds (between presses: idle or armed and still).
    /// RootView installs it with the background prewarm; until then (and in tests) renders may run.
    static var mayRender: @MainActor () -> Bool = { true }

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
            rendered = await Self.render(kind, look: look)
        }
        .accessibilityHidden(true)
    }

    /// The cached render, or one made once the press gate holds (never mid-press). Nil if the view went first.
    @MainActor
    static func render(_ kind: ObjectKind, look: ObjectThumbnails.Look) async -> UIImage? {
        if let image = ObjectThumbnails.cached(kind, look: look, size: renderSize) { return image }
        while !mayRender() {
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return nil }
        }
        return await ObjectThumbnails.image(kind, look: look, size: renderSize)
    }

    /// Renders every object (at rest, then crushed) in the background once the press room is up, so the Tray and the
    /// cover open on real pictures. Skips what is already on disk. `canRender` holds it off while a press is under way,
    /// and gates the on-demand renders of every tile too (`mayRender`).
    @MainActor
    static func prewarm(canRender: @escaping @MainActor () -> Bool) async {
        mayRender = canRender
        await ObjectThumbnails.prewarm(size: renderSize, canRender: canRender)
    }
}

/// The crushed 3D specimen in a tile's corner (Shelf, Tray): a white-rimmed badge that appears only once the crushed
/// render exists, never the intact candy tile standing in for a crushed one (launch QA #4).
struct CrushedBadge: View {
    let kind: ObjectKind
    var size: CGFloat = 30
    var cornerRadius: CGFloat = 7

    @State private var rendered: UIImage?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        // A clear frame that is always there (so the task runs), with the badge on it once there's a render.
        Color.clear
            .frame(width: size, height: size)
            .overlay {
                if let image = rendered ?? ObjectThumbnails.cached(kind, look: .crushed, size: ObjectArt.renderSize) {
                    Color.clear
                        .overlay {
                            Image(uiImage: image)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFill()
                        }
                        .clipShape(shape)
                        .overlay(shape.strokeBorder(Color.white, lineWidth: 2))
                        .elevation(.e1)
                        .transition(.opacity)
                }
            }
            .allowsHitTesting(false)
            .animation(Theme.fade, value: rendered)
        .task(id: kind.rawValue) {
            guard rendered == nil else { return }
            rendered = await ObjectArt.render(kind, look: .crushed)
        }
        .accessibilityHidden(true)
    }
}
