import Foundation
import RealityKit
import simd
import UIKit

/// Real 3D thumbnails of every object, at rest and crushed (EXPERIENCE-REVIEW-1 #10: the Tray, the console chip, the
/// cover chips and the Shelf showed flat clip art while the app has detailed renders).
///
/// **API (for UI):**
/// - `ObjectThumbnails.cached(kind, look:, size:)` — the image if it is already in memory or on disk (synchronous,
///   cheap; returns nil the first time). Use it to draw a tile at once.
/// - `await ObjectThumbnails.image(kind, look:, size:)` — renders it if needed (≈ 0.3–1 s the first time for an
///   object, mostly waiting for its textures), caches it in memory and on disk, and returns it. Never throws; nil only
///   if no window could host the render.
/// - `await ObjectThumbnails.prewarm(size:)` — renders every object at rest, then every crushed look, in the
///   background order the Tray shows them; call once after launch (it skips what is already on disk).
/// - `ObjectThumbnails.Look`: `.rest` (a ¾ hero view) or `.crushed` (the pressed specimen and its mess from higher up).
/// - Images are square or not as asked (`size` in points, rendered at the screen scale), on a transparent-looking
///   paper background (`backdrop`, default the studio's warm white), and named by object, look, size and
///   `artVersion` (bump it when object art changes so old renders are dropped).
///
/// How: a small non-AR `ARView` parked behind the key window's content (it must be in a window to render), one object
/// at a time; the crushed look is the same full press PressScene drives (beats, fractures, debris under the plate),
/// run offscreen in a few hundred fixed steps, so it is the real specimen, seeded like a plain press.
@MainActor
enum ObjectThumbnails {
    enum Look: String, CaseIterable, Sendable {
        case rest
        case crushed
    }

    /// Bump when an object's look changes, so cached renders are re-made.
    nonisolated static let artVersion = 1
    /// The default backdrop (the studio's warm white).
    static let backdrop = Palette.backdrop

    private static var memory: [String: UIImage] = [:]
    private static var queue: Task<Void, Never>?
    private static var host: ARView?
    private static var light: Entity?

    // MARK: Public

    static func cached(_ kind: ObjectKind, look: Look = .rest, size: CGSize) -> UIImage? {
        let key = cacheKey(kind, look: look, size: size, scale: screenScale)
        if let image = memory[key] { return image }
        if let data = try? Data(contentsOf: fileURL(key)), let image = UIImage(data: data, scale: screenScale) {
            memory[key] = image
            return image
        }
        return nil
    }

    static func image(_ kind: ObjectKind, look: Look = .rest, size: CGSize) async -> UIImage? {
        if let image = cached(kind, look: look, size: size) { return image }
        // One render at a time: wait for whatever is in flight, then check again (it may have been this one).
        let previous = queue
        let task = Task { @MainActor () -> UIImage? in
            await previous?.value
            if let image = cached(kind, look: look, size: size) { return image }
            guard let image = await render(kind, look: look, size: size) else { return nil }
            let key = cacheKey(kind, look: look, size: size, scale: screenScale)
            memory[key] = image
            if let data = image.pngData() {
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try? data.write(to: fileURL(key), options: .atomic)
            }
            return image
        }
        queue = Task { _ = await task.value }
        return await task.value
    }

    static func prewarm(size: CGSize) async {
        for look in Look.allCases {
            for kind in ObjectKind.allCases {
                _ = await image(kind, look: look, size: size)
            }
        }
        park()
    }

    /// The cache file name (pure, for tests): object, look, pixel size, art version.
    nonisolated static func cacheKey(_ kind: ObjectKind, look: Look, size: CGSize, scale: CGFloat) -> String {
        let w = Int((size.width * scale).rounded()), h = Int((size.height * scale).rounded())
        return "\(kind.rawValue)-\(look.rawValue)-\(w)x\(h)-v\(artVersion)"
    }

    // MARK: Rendering

    private static var screenScale: CGFloat {
        hostWindow()?.screen.scale ?? 3
    }

    private static var directory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return caches.appendingPathComponent("ObjectThumbnails", isDirectory: true)
    }

    private static func fileURL(_ key: String) -> URL {
        directory.appendingPathComponent(key).appendingPathExtension("png")
    }

    private static func hostWindow() -> UIWindow? {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        return windows.first { $0.isKeyWindow } ?? windows.first
    }

    /// The renderer: in the window (it must be, to draw), behind everything else, the size of the requested image.
    private static func renderer(size: CGSize) -> ARView? {
        guard let window = hostWindow() else { return nil }
        let view: ARView
        if let host {
            view = host
        } else {
            view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
            view.renderOptions.insert(.disableMotionBlur)
            view.renderOptions.insert(.disableCameraGrain)
            view.renderOptions.insert(.disableDepthOfField)
            view.isUserInteractionEnabled = false
            host = view
        }
        view.frame = CGRect(origin: .zero, size: size)
        if view.superview !== window {
            window.insertSubview(view, at: 0)
        } else {
            window.sendSubviewToBack(view)
        }
        view.isHidden = false
        view.environment.background = .color(backdrop)
        return view
    }

    /// Takes the renderer out of the window between renders (it costs nothing while parked).
    private static func park() {
        host?.removeFromSuperview()
    }

    private static func render(_ kind: ObjectKind, look: Look, size: CGSize) async -> UIImage? {
        guard size.width >= 8, size.height >= 8, let view = renderer(size: size) else { return nil }
        await SurfaceDetail.warm(kind)
        if light == nil {
            light = await StudioEnvironment.makeLight(exponent: SceneStyle.standard.iblExponent)
        }
        let variant = PressVariant(kind: kind, seed: SpecimenPrint.plainSeed(for: kind))
        let fx = SceneFX()
        let object = PressObjectFactory.make(kind, variant: variant, fx: fx)
        ShadowCasting.offForTranslucent(in: object.entity)
        // Its own textures (labels, prints) arrive on tasks of their own.
        try? await Task.sleep(for: .milliseconds(350))
        if look == .crushed {
            await ObjectCrush.pressYielding(object, fx: fx, kind: kind, variant: variant)
            ShadowCasting.offForTranslucent(in: object.entity)
            ShadowCasting.offForTranslucent(in: fx.root)
        } else {
            ObjectCrush.rest(object)
        }

        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(object.entity)
        anchor.addChild(fx.root)
        if let light {
            let ibl = light.clone(recursive: true)
            anchor.addChild(ibl)
            let receiver = ImageBasedLightReceiverComponent(imageBasedLight: ibl)
            object.entity.components.set(receiver)
            fx.root.components.set(receiver)
        }
        let style = SceneStyle.standard
        let key = DirectionalLight()
        key.light.intensity = style.keyIntensity
        key.light.color = style.keyColor
        key.look(at: .zero, from: simd_normalize(style.keyDirection), relativeTo: nil)
        anchor.addChild(key)

        // Frame what is there (object + mess), from a ¾ view at rest or from higher up for the crushed specimen.
        let parts = [VisibleBounds.of(object.entity), VisibleBounds.of(fx.debris.root)].compactMap { $0 }
        var lo = parts.first?.min ?? SIMD3(-0.05, 0, -0.05), hi = parts.first?.max ?? SIMD3(0.05, 0.05, 0.05)
        for part in parts.dropFirst() {
            lo = simd_min(lo, part.min)
            hi = simd_max(hi, part.max)
        }
        let framing = ThumbnailFraming.camera(min: lo, max: hi, look: look, aspect: Float(size.width / size.height))
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = framing.fieldOfView
        camera.camera.near = 0.01
        camera.camera.far = 5
        camera.look(at: framing.target, from: framing.eye, upVector: [0, 1, 0], relativeTo: nil)
        anchor.addChild(camera)
        view.scene.addAnchor(anchor)

        // A few frames so the IBL, the textures and the mesh uploads are in, then the shot.
        try? await Task.sleep(for: .milliseconds(220))
        let image = await snapshot(view, timeout: 2)
        view.scene.removeAnchor(anchor)
        view.isHidden = true
        if let image, FoldSnapshot.isBlank(image) { return nil }
        return image
    }
}

/// Resumes a snapshot's continuation once (touched only on the main queue).
private final class SnapshotOnce: @unchecked Sendable {
    var done = false
}

@MainActor
extension ObjectThumbnails {
    /// `ARView.snapshot`, or nil after `timeout` seconds (a view that never draws must not stall the queue).
    fileprivate static func snapshot(_ view: ARView, timeout: Double) async -> UIImage? {
        let once = SnapshotOnce()
        return await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            view.snapshot(saveToHDR: false) { image in
                DispatchQueue.main.async {
                    guard !once.done else { return }
                    once.done = true
                    continuation.resume(returning: image)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                guard !once.done else { return }
                once.done = true
                continuation.resume(returning: nil)
            }
        }
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

    /// As `press`, in fewer steps and yielding the main actor every few frames, so a thumbnail never holds the UI.
    static func pressYielding(_ view: PressObjectView, fx: SceneFX, kind: ObjectKind, variant: PressVariant) async {
        let thresholds = PressObjectFactory.thresholds(kind, variant: variant)
        let failure = kind.profile.failureIndex
        let steps = 120
        var time: Float = 0
        view.update(state(view, c: 0, dt: 1.0 / 30, time: time, phase: .armed))
        view.handle(.contact, state: state(view, c: 0, dt: 0, time: time, phase: .pressing))
        var fired = 0
        for step in 0...(steps + 40) {
            let c = min(Float(step) / Float(steps), 1)
            time += 1.0 / 30
            let s = state(view, c: c, dt: 1.0 / 30, time: time, phase: .pressing)
            while fired < thresholds.count && c >= thresholds[fired] {
                view.fracture(index: fired, isFailure: fired == failure, state: s)
                fired += 1
            }
            view.update(s)
            fx.step(dt: 1.0 / 30, ceiling: view.surfaceHeight(compression: c), plateHalfExtent: SIMD2(repeating: 1))
            if step % 6 == 0 { await Task.yield() }
        }
        let sealed = state(view, c: 1, dt: 0, time: time, phase: .sealed)
        view.handle(.sealed(blind: false), state: sealed)
        view.handle(.reveal, state: sealed)
        for k in 0..<24 {
            time += 1.0 / 30
            view.update(state(view, c: 1, dt: 1.0 / 30, time: time, phase: .revealing))
            fx.step(dt: 1.0 / 30, ceiling: 10, plateHalfExtent: SIMD2(repeating: 1))
            if k % 6 == 0 { await Task.yield() }
        }
    }

    static func state(_ view: PressObjectView, c: Float, dt: Float, time: Float, phase: PressPhase) -> PressVisualState {
        PressVisualState(compression: c, ramCompression: c, ramFace: view.surfaceHeight(compression: c),
                         approach: c > 0 ? 1 : 0.5, dt: dt, time: time, closingSpeed: 40, loaded: c > 0,
                         reduceMotion: false, phase: phase)
    }
}
