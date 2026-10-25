import Foundation
import RealityKit
import simd
import UIKit

/// Real 3D pictures of every object, at rest and crushed (EXPERIENCE-REVIEW-1 #10: the Tray, the console chip, the
/// cover chips and the Shelf showed flat clip art while the app has detailed renders).
///
/// **API (for UI):**
/// - `ObjectThumbnails.cached(kind, look:, size:)` — the picture (synchronous, cheap; every kind and look ships).
/// - `await ObjectThumbnails.image(kind, look:, size:)` — the same, for callers that already await.
/// - `await ObjectThumbnails.prewarm(size:)` — loads every picture into memory (no rendering).
/// - `ObjectThumbnails.Look`: `.rest` (a ¾ hero view) or `.crushed` (the pressed specimen and its mess from higher up).
/// - Pictures are square, `pixelSize` pixels on the studio's warm white (`backdrop`); `size` is accepted for the API's
///   sake and ignored (SwiftUI scales them).
///
/// How (Launch QA): they are pre-rendered and ship in the bundle (`Resources/ObjectArt/objectart-<kind>-<look>.jpg`).
/// The app never renders them at run time: a second ARView alive next to the live press stage froze the Duo anvil's
/// picture (bubble wrap's pops never showed; the plate came out keystoned under the live warp). The generator is
/// `SquishTests/ThumbnailGenerator.swift` (run by `.github/workflows/thumbs.yml`): the same plain seed, full offscreen
/// press (`ObjectCrush`) and framing (`ThumbnailFraming`), so a re-run gives the same pictures for the same art.
@MainActor
enum ObjectThumbnails {
    enum Look: String, CaseIterable, Sendable {
        case rest
        case crushed
    }

    /// The art the shipped pictures were made from. When an object's look changes, re-run the generator
    /// (thumbs.yml), commit its pictures to Resources/ObjectArt and bump this.
    nonisolated static let artVersion = 3
    /// The shipped pictures' side (pixels): `ObjectArt.renderSize` (160 pt) at 3×.
    nonisolated static let pixelSize: CGFloat = 480
    /// The shipped pictures' JPEG quality.
    nonisolated static let jpegQuality: CGFloat = 0.82
    /// The default backdrop (the studio's warm white).
    static let backdrop = Palette.backdrop

    private static var memory: [String: UIImage] = [:]

    // MARK: Public

    /// The bundled picture's resource name (without the `jpg` extension).
    nonisolated static func resourceName(_ kind: ObjectKind, look: Look) -> String {
        "objectart-\(kind.rawValue)-\(look.rawValue)"
    }

    static func cached(_ kind: ObjectKind, look: Look = .rest, size: CGSize = .zero) -> UIImage? {
        let name = resourceName(kind, look: look)
        if let image = memory[name] { return image }
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg"),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data, scale: 3) else { return nil }
        memory[name] = image
        return image
    }

    static func image(_ kind: ObjectKind, look: Look = .rest, size: CGSize = .zero) async -> UIImage? {
        cached(kind, look: look, size: size)
    }

    /// Loads every picture into memory, a few per main-actor turn. `canRender` is kept for the API (nothing renders).
    static func prewarm(size: CGSize, canRender: @escaping @MainActor () -> Bool = { true }) async {
        // Earlier builds rendered at run time and kept their renders in Caches/ObjectThumbnails: drop them.
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            try? FileManager.default.removeItem(at: caches.appendingPathComponent("ObjectThumbnails", isDirectory: true))
        }
        for look in Look.allCases {
            for kind in ObjectKind.allCases {
                _ = cached(kind, look: look, size: size)
                await Task.yield()
            }
        }
    }

    /// The cache name of a picture (kept for the API): its resource name plus the art version.
    nonisolated static func cacheKey(_ kind: ObjectKind, look: Look, size: CGSize, scale: CGFloat) -> String {
        "\(resourceName(kind, look: look))-v\(artVersion)"
    }
}

/// Where the thumbnail camera sits (pure, for tests): a ¾ hero view at rest, higher for the crushed specimen, far
/// enough that the whole box fits the frame with a margin.
enum ThumbnailFraming {
    static let restElevation: Float = 32 * .pi / 180
    static let crushedElevation: Float = 58 * .pi / 180
    static let azimuth: Float = -28 * .pi / 180
    static let fieldOfView: Float = 24
    static let margin: Float = 1.12

    static func camera(min lo: SIMD3<Float>, max hi: SIMD3<Float>, look: ObjectThumbnails.Look, aspect: Float)
        -> (eye: SIMD3<Float>, target: SIMD3<Float>, fieldOfView: Float) {
        let centre = (lo + hi) / 2
        let radius = max(simd_length(hi - lo) / 2, 0.01)
        let elevation = look == .rest ? restElevation : crushedElevation
        // RealityKit's field of view is vertical; a narrow image needs more distance to fit the width.
        let halfV = fieldOfView / 2 * .pi / 180
        let halfH = atan(tan(halfV) * max(aspect, 0.2))
        let distance = radius * margin / sin(min(halfV, halfH))
        let dir = SIMD3<Float>(cos(elevation) * sin(azimuth), sin(elevation), cos(elevation) * cos(azimuth))
        let target = SIMD3<Float>(centre.x, centre.y * 0.8, centre.z)
        return (target + dir * distance, target, fieldOfView)
    }
}

/// Drives an object view through a full press offscreen, the way PressScene does (beats, fractures in threshold
/// order, the debris flattened under the plate), then seals and reveals it: the real crushed specimen, seeded. Used by
/// the thumbnails and by SceneTests (every object ends visibly crushed).
@MainActor
enum ObjectCrush {
    /// One idle frame at rest.
    static func rest(_ view: PressObjectView) {
        view.update(state(view, c: 0, dt: 1.0 / 60, time: 0, phase: .armed))
    }

    static func press(_ view: PressObjectView, fx: SceneFX, kind: ObjectKind, variant: PressVariant, steps: Int = 240) {
        let thresholds = PressObjectFactory.thresholds(kind, variant: variant)
        let failure = kind.profile.failureIndex
        var time: Float = 0
        view.update(state(view, c: 0, dt: 1.0 / 60, time: time, phase: .armed))
        view.handle(.contact, state: state(view, c: 0, dt: 0, time: time, phase: .pressing))
        var fired = 0
        for step in 0...(steps + 90) {
            let c = min(Float(step) / Float(steps), 1)
            time += 1.0 / 60
            let s = state(view, c: c, dt: 1.0 / 60, time: time, phase: .pressing)
            while fired < thresholds.count && c >= thresholds[fired] {
                view.fracture(index: fired, isFailure: fired == failure, state: s)
                fired += 1
            }
            view.update(s)
            fx.step(dt: 1.0 / 60, ceiling: view.surfaceHeight(compression: c), plateHalfExtent: SIMD2(repeating: 1))
        }
        let sealed = state(view, c: 1, dt: 0, time: time, phase: .sealed)
        view.handle(.sealed(blind: false), state: sealed)
        view.handle(.reveal, state: sealed)
        for _ in 0..<45 {
            time += 1.0 / 60
            view.update(state(view, c: 1, dt: 1.0 / 60, time: time, phase: .revealing))
            fx.step(dt: 1.0 / 60, ceiling: 10, plateHalfExtent: SIMD2(repeating: 1))
        }
    }

    static func state(_ view: PressObjectView, c: Float, dt: Float, time: Float, phase: PressPhase) -> PressVisualState {
        PressVisualState(compression: c, ramCompression: c, ramFace: view.surfaceHeight(compression: c),
                         approach: c > 0 ? 1 : 0.5, dt: dt, time: time, closingSpeed: 40, loaded: c > 0,
                         reduceMotion: false, phase: phase)
    }
}
