import Combine
import Observation
import RealityKit
import SwiftUI
import UIKit

/// The darkroom the share clip is developed in: a temporary window above the app hosting a fresh `PressScene` in its
/// own non-AR `ARView` (360 × 640 pt at 3× = 1080 × 1920 px, so `ARView.snapshot` returns clip-sized frames),
/// shown as a small live "film frame" above a progress card with Cancel.
///
/// RealityKit only renders views that are on screen, so the ARView is really in the window; the preview is the
/// ARView's container scaled down with a transform, which leaves the ARView's own bounds (and drawable) untouched.
@MainActor
final class ClipStudio {
    static let viewSize = CGSize(width: 360, height: 640)

    let scene: PressScene
    let arView: ARView
    let model: ClipStudioModel

    private let window: UIWindow
    private var updates: Cancellable?
    private(set) var renderedFrames = 0

    init(onCancel: @escaping () -> Void) throws {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else {
            throw ClipExporter.ExportError.noScreen
        }

        let scene = PressScene()
        let model = ClipStudioModel()
        model.onCancel = onCancel
        let view = ARView(frame: CGRect(origin: .zero, size: ClipStudio.viewSize), cameraMode: .nonAR,
                          automaticallyConfigureSession: false)
        // Same setup as PressSceneView, so the clip looks like the app.
        view.environment.background = .color(Palette.backdrop)
        view.renderOptions.insert(.disableMotionBlur)
        view.renderOptions.insert(.disableCameraGrain)
        view.renderOptions.insert(.disableDepthOfField)
        view.renderOptions.insert(.disableGroundingShadows)
        view.backgroundColor = Palette.backdrop
        view.isUserInteractionEnabled = false
        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(scene.root)
        view.scene.addAnchor(anchor)
        scene.attach(to: view)
        let window = UIWindow(windowScene: windowScene)
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 50)
        window.backgroundColor = .clear
        window.rootViewController = ClipStudioController(arView: view, model: model)
        window.alpha = 0
        window.isHidden = false
        self.scene = scene
        self.model = model
        self.window = window
        arView = view
        UIView.animate(withDuration: 0.25) { window.alpha = 1 }

        updates = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.renderedFrames &+= 1
            }
        }
    }

    /// Waits until RealityKit has rendered `count` more frames, or `timeout` passes (a paused renderer never hangs us).
    func waitForFrames(_ count: Int, timeout: Duration = .milliseconds(500)) async {
        let target = renderedFrames &+ count
        let deadline = ContinuousClock.now + timeout
        while renderedFrames < target, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(3))
        }
    }

    /// The scene builds its studio light and gel sweep asynchronously; give them time to land before frame one.
    func warmUp() async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !scene.root.children.contains(where: { $0.components.has(ImageBasedLightComponent.self) }),
              ContinuousClock.now < deadline {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(20))
        }
        // The sweep texture has no completion signal; it bakes in well under this.
        try await Task.sleep(for: .milliseconds(350))
        await waitForFrames(3)
    }

    /// One frame of the scene as rendered (retried once: the first snapshot after a layout can come back empty).
    func snapshot() async -> UIImage? {
        if let image = await scene.snapshot() { return image }
        await waitForFrames(1)
        return await scene.snapshot()
    }

    func close() {
        updates?.cancel()
        updates = nil
        arView.scene.anchors.removeAll()
        let window = self.window
        UIView.animate(withDuration: 0.2, animations: { window.alpha = 0 }, completion: { _ in
            window.isHidden = true
            window.rootViewController = nil
        })
    }
}

/// What the studio overlay shows.
@MainActor
@Observable
final class ClipStudioModel {
    var progress: Double = 0
    var stage = "Re-pressing it frame by frame…"
    @ObservationIgnored var onCancel: (() -> Void)?
}

/// Darkroom layout: graphite backdrop, the live preview as a white-bordered print, the progress card below.
private final class ClipStudioController: UIViewController {
    private let arView: ARView
    private let model: ClipStudioModel
    private let printView = UIView()
    private let film = UIView()
    private static let border: CGFloat = 8

    init(arView: ARView, model: ClipStudioModel) {
        self.arView = arView
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.graphite

        let size = ClipStudio.viewSize
        let border = Self.border
        printView.bounds = CGRect(x: 0, y: 0, width: size.width + border * 2, height: size.height + border * 2)
        printView.backgroundColor = .white
        printView.layer.cornerRadius = 30
        printView.layer.shadowColor = UIColor.black.cgColor
        printView.layer.shadowOpacity = 0.35
        printView.layer.shadowRadius = 24
        printView.layer.shadowOffset = CGSize(width: 0, height: 10)
        printView.isAccessibilityElement = false
        film.frame = CGRect(x: border, y: border, width: size.width, height: size.height)
        film.layer.cornerRadius = 22
        film.layer.cornerCurve = .continuous
        film.clipsToBounds = true
        arView.frame = film.bounds
        film.addSubview(arView)
        printView.addSubview(film)
        view.addSubview(printView)

        let host = UIHostingController(rootView: ClipStudioOverlay(model: model))
        host.view.backgroundColor = .clear
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.accessibilityViewIsModal = true
        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = view.bounds
        let safe = view.safeAreaInsets
        let printSize = printView.bounds.size
        let reserved: CGFloat = 250 // the progress card and its margins
        let available = bounds.height - safe.top - safe.bottom - reserved - 24
        let scale = max(0.25, min(0.62, available / printSize.height, (bounds.width - 96) / printSize.width))
        printView.transform = CGAffineTransform(scaleX: scale, y: scale)
        printView.center = CGPoint(x: bounds.midX, y: safe.top + 24 + printSize.height * scale / 2)
        printView.layer.shadowPath = UIBezierPath(roundedRect: printView.bounds, cornerRadius: 30).cgPath
    }
}

/// The progress card, in the app's paper-and-keycap language (matches the in-app "Developing your clip" card).
private struct ClipStudioOverlay: View {
    let model: ClipStudioModel

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: Theme.s4) {
                HStack(spacing: Theme.s3) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.graphite)
                        .frame(width: 40, height: 40)
                        .background(Theme.yellow, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rendering your squish…")
                            .font(Theme.headline)
                            .foregroundStyle(Theme.ink)
                        Text(model.stage)
                            .font(Theme.footnote)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.paperShade)
                        Capsule()
                            .fill(Theme.yellow)
                            .frame(width: max(14, proxy.size.width * model.progress))
                            .animation(.easeOut(duration: 0.2), value: model.progress)
                    }
                }
                .frame(height: 14)
                HStack {
                    Text("\(Int((model.progress * 100).rounded()))%")
                        .font(Theme.label)
                        .monospacedDigit()
                        .foregroundStyle(Theme.inkSecondary)
                    Spacer()
                    Button("Cancel") { model.onCancel?() }
                        .buttonStyle(KeycapStyle(kind: .secondary))
                }
            }
            .padding(Theme.s5)
            .background(PaperBackground().clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)))
            .topHighlight(cornerRadius: Theme.cardRadius)
            .elevation(.e3)
            .frame(maxWidth: 380)
            .padding(Theme.s5)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Rendering your clip, \(Int((model.progress * 100).rounded())) percent")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
