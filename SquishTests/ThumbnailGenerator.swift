import Foundation
import RealityKit
import simd
import Testing
import UIKit
@testable import Squish

/// The object pictures' generator (Launch QA: no second ARView may ever exist while the app runs a live press stage,
/// so the app ships these renders in its bundle instead of making them at run time; `ObjectThumbnails`).
///
/// Runs only when `SQUISH_THUMBS_OUT` names a directory (CI: `.github/workflows/thumbs.yml` passes
/// `TEST_RUNNER_SQUISH_THUMBS_OUT`), so ordinary test runs skip it. For every object, at rest and crushed, it builds the
/// object view with the plain seed, runs the crushed look's full press offscreen (`ObjectCrush.press`), frames it with
/// `ThumbnailFraming` and shoots it in a small non-AR ARView in a window of its own, then writes
/// `<ObjectThumbnails.resourceName>.jpg` (square, `ObjectThumbnails.pixelSize`, JPEG `ObjectThumbnails.jpegQuality`)
/// into that directory. Copy them to `Squish/Resources/ObjectArt/` to ship them.
@MainActor
struct ThumbnailGenerator {
    nonisolated static var outputDirectory: String? { ProcessInfo.processInfo.environment["SQUISH_THUMBS_OUT"] }

    @Test(.enabled(if: ThumbnailGenerator.outputDirectory != nil))
    func renderEveryObjectPicture() async throws {
        let directory = URL(fileURLWithPath: try #require(Self.outputDirectory), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let side = ObjectThumbnails.pixelSize
        let points = CGSize(width: side / 3, height: side / 3)
        let renderer = try #require(Renderer(size: points))
        var written: [String] = []
        for look in ObjectThumbnails.Look.allCases {
            for kind in ObjectKind.allCases {
                var image: UIImage?
                for _ in 0..<3 where image == nil {
                    image = await renderer.render(kind, look: look)
                }
                let name = ObjectThumbnails.resourceName(kind, look: look)
                guard let image else {
                    Issue.record("\(name): no render")
                    continue
                }
                let square = Self.square(image, side: side)
                let data = try #require(square.jpegData(compressionQuality: ObjectThumbnails.jpegQuality))
                try data.write(to: directory.appendingPathComponent(name).appendingPathExtension("jpg"), options: .atomic)
                written.append("\(name) \(data.count)")
            }
        }
        renderer.tearDown()
        print("SQUISH-THUMBS wrote \(written.count): " + written.joined(separator: ", "))
        #expect(written.count == ObjectKind.allCases.count * ObjectThumbnails.Look.allCases.count)
    }

    /// The render scaled (and centre-cropped) to exactly `side` × `side` pixels on the backdrop.
    static func square(_ image: UIImage, side: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
            ObjectThumbnails.backdrop.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
            let w = image.size.width * image.scale, h = image.size.height * image.scale
            let k = side / max(min(w, h), 1)
            let size = CGSize(width: w * k, height: h * k)
            image.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2,
                                  width: size.width, height: size.height))
        }
    }

    /// A small non-AR ARView in a window of its own, under the app's.
    @MainActor
    final class Renderer {
        let window: UIWindow
        let view: ARView
        private var light: Entity?

        init?(size: CGSize) {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            guard let scene = scenes.first else { return nil }
            window = UIWindow(windowScene: scene)
            window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue - 1)
            window.isUserInteractionEnabled = false
            window.frame = CGRect(origin: .zero, size: size)
            view = ARView(frame: CGRect(origin: .zero, size: size), cameraMode: .nonAR, automaticallyConfigureSession: false)
            view.renderOptions.insert(.disableMotionBlur)
            view.renderOptions.insert(.disableCameraGrain)
            view.renderOptions.insert(.disableDepthOfField)
            view.environment.background = .color(ObjectThumbnails.backdrop)
            window.addSubview(view)
            window.isHidden = false
        }

        func tearDown() {
            view.removeFromSuperview()
            window.isHidden = true
        }

        func render(_ kind: ObjectKind, look: ObjectThumbnails.Look) async -> UIImage? {
            await SurfaceDetail.warm(kind)
            if light == nil {
                light = await StudioEnvironment.makeLight(exponent: SceneStyle.standard.iblExponent)
            }
            let variant = PressVariant(kind: kind, seed: SpecimenPrint.plainSeed(for: kind))
            let fx = SceneFX()
            let object = PressObjectFactory.make(kind, variant: variant, fx: fx)
            ShadowCasting.offForTranslucent(in: object.entity)
            // Its own textures (labels, prints) arrive on tasks of their own.
            try? await Task.sleep(for: .milliseconds(600))
            if look == .crushed {
                ObjectCrush.press(object, fx: fx, kind: kind, variant: variant)
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
            // Frame what is there (object + mess): a ¾ view at rest, from higher up for the crushed specimen.
            let parts = [VisibleBounds.of(object.entity), VisibleBounds.of(fx.debris.root)].compactMap { $0 }
            var lo = parts.first?.min ?? SIMD3(-0.05, 0, -0.05), hi = parts.first?.max ?? SIMD3(0.05, 0.05, 0.05)
            for part in parts.dropFirst() {
                lo = simd_min(lo, part.min)
                hi = simd_max(hi, part.max)
            }
            let size = view.bounds.size
            let framing = ThumbnailFraming.camera(min: lo, max: hi, look: look, aspect: Float(size.width / size.height))
            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = framing.fieldOfView
            camera.camera.near = 0.01
            camera.camera.far = 5
            camera.look(at: framing.target, from: framing.eye, upVector: [0, 1, 0], relativeTo: nil)
            anchor.addChild(camera)
            view.scene.addAnchor(anchor)
            // Frames enough for the IBL, the textures and the mesh uploads, then the shot.
            try? await Task.sleep(for: .milliseconds(900))
            let image = await Self.snapshot(view, timeout: 4)
            view.scene.removeAnchor(anchor)
            if let image, FoldSnapshot.isBlank(image) { return nil }
            return image
        }

        private static func snapshot(_ view: ARView, timeout: Double) async -> UIImage? {
            final class Once { var done = false }
            let once = Once()
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
}
