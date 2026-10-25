import Foundation
import RealityKit
import simd

/// What an object view sees each frame (internal to Scene/).
struct PressVisualState {
    /// Visual compression 0…1: max(plastic, render). Never re-inflates past the plastic ratchet.
    var compression: Float
    /// Compression the hand is asking for right now (render depth).
    var ramCompression: Float
    /// Displayed ram face height above the anvil.
    var ramFace: Float
    /// 0…1 approach of the ram before contact (1 = touching).
    var approach: Float
    /// Object time step; 0 during hit-stop.
    var dt: Float
    /// Scene clock (seconds).
    var time: Float
    /// Degrees per second, positive while closing.
    var closingSpeed: Float
    /// True while the press is loaded and moving the material.
    var loaded: Bool
    var reduceMotion: Bool
    var phase: PressPhase
    /// 0…1: how hard the object is fighting the plate right now ("fight, then give", EXPERIENCE-REVIEW-1 #1;
    /// `PressEngine.resistanceStrain`): ramps in over the last ~0.12 c before the failure, held through the hush and hit
    /// stop, released at the burst. The scene already widens the slot (a side bulge, height untouched) and trembles it;
    /// views can add their own push-back here: the centre doming up against the lid while the edges flatten, a bow, a
    /// shear, stress whitening. Never change the height with it (the height is locked to the hand).
    var resistanceBulge: Float = 0
    /// The give's over-collapse (compression ahead of the hand, 0 except for the 60–80 ms after the burst;
    /// `PressEngine.collapseLead`). Already included in `compression`; a view can use it to fling its squeeze-out
    /// outward in the same moment.
    var collapseLead: Float = 0
    /// 0…1 over the seal stroke, from the fully crushed angle to the real shut (`PressEngine.sealProgress`): the final
    /// creep and clamp. The scene creeps the slot a little; views can spread their ooze with it.
    var sealing: Float = 0
}

/// A pressable object. Its entity's origin sits on the anvil surface (y = 0), centred under the ram.
@MainActor
protocol PressObjectView: AnyObject {
    var entity: Entity { get }
    /// Height before any compression, in metres.
    var restHeight: Float { get }
    /// Footprint radius at rest, for the contact shadow.
    var footprint: Float { get }
    /// Current footprint growth (1 at rest), so the contact shadow spreads with the squash.
    var shadowSpread: Float { get }
    /// True when the ram should never get below `restHeight` (The Unsquishable).
    var isRigid: Bool { get }

    /// Where the ram face meets this object at compression `c` (0…1), given the fractures fired so far.
    /// Brittle objects return a rigid plateau until their failure, then lurch down.
    func surfaceHeight(compression c: Float) -> Float

    /// Apply the current state. Called every frame except during hit-stop.
    func update(_ state: PressVisualState)

    /// An irreversible material event (indices ascending in compression, see Core/MaterialProfile.swift).
    func fracture(index: Int, isFailure: Bool, state: PressVisualState)

    /// Non-fracture events (contact, tell, released, reveal…).
    func handle(_ event: PressEvent, state: PressVisualState)
}

extension PressObjectView {
    var shadowSpread: Float { 1 }
    var isRigid: Bool { false }
    func handle(_ event: PressEvent, state: PressVisualState) {}
}

/// Shared height curves.
enum HeightCurve {
    /// Soft objects: linear from `rest` at c = 0 to `rest × minRatio` at c = 1.
    static func linear(_ c: Float, rest: Float, minRatio: Float) -> Float {
        rest * (1 - clamp(c, 0, 1) * (1 - minRatio))
    }

    /// Brittle objects: an almost-rigid plateau (`rigidSquash` of the height at most) until the failure fires,
    /// then a lurch to `rest × afterRatio` at the failure threshold `failC`, then linear to `rest × minRatio`.
    static func brittle(_ c: Float, rest: Float, failC: Float, failed: Bool, rigidSquash: Float,
                        afterRatio: Float, minRatio: Float) -> Float {
        let c = clamp(c, 0, 1)
        if !failed {
            return rest * (1 - rigidSquash * min(c / max(failC, 0.01), 1))
        }
        let t = clamp((c - failC) / max(1 - failC, 0.01), 0, 1)
        let start = min(afterRatio, 1 - rigidSquash)
        return rest * (start + (minRatio - start) * t)
    }
}

/// Caches expensive procedural meshes (SDF blobs, lathes) for the session, so re-placing an object is instant.
@MainActor
enum MeshCache {
    private static var data: [String: MeshData] = [:]
    private static var resources: [String: MeshResource] = [:]

    static func mesh(_ key: String, _ build: () -> MeshData) -> MeshData {
        if let cached = data[key] { return cached }
        let built = build()
        data[key] = built
        return built
    }

    /// Inserts mesh data built off the main actor (see `ObjectMeshes`).
    static func store(_ key: String, _ mesh: MeshData) {
        if data[key] == nil { data[key] = mesh }
    }

    static func resource(_ key: String, _ build: () -> MeshData) -> MeshResource? {
        if let cached = resources[key] { return cached }
        guard let resource = mesh(key, build).resource(name: key) else { return nil }
        resources[key] = resource
        return resource
    }
}

/// Small entity helpers for object views.
@MainActor
enum Part {
    @discardableResult
    static func add(_ mesh: MeshData, _ material: any Material, at position: SIMD3<Float> = .zero, to parent: Entity) -> ModelEntity {
        let model = MeshKit.model(mesh, material: material)
        model.position = position
        parent.addChild(model)
        return model
    }

    @discardableResult
    static func add(cached key: String, _ build: () -> MeshData, _ material: any Material, at position: SIMD3<Float> = .zero,
                    to parent: Entity) -> ModelEntity {
        let resource = MeshCache.resource(key, build) ?? MeshResource.generateSphere(radius: 0.001)
        let model = ModelEntity(mesh: resource, materials: [material])
        model.position = position
        parent.addChild(model)
        return model
    }

    /// Converts a point in `entity`'s space to the FX root (anvil space).
    static func anvilPoint(_ p: SIMD3<Float>, in entity: Entity, fx: SceneFX) -> SIMD3<Float> {
        entity.convert(position: p, to: fx.root)
    }

    static let identity = simd_quatf(angle: 0, axis: [0, 1, 0])

    static func yaw(_ degrees: Float) -> simd_quatf {
        simd_quatf(angle: degrees * .pi / 180, axis: [0, 1, 0])
    }
}

@MainActor
enum PressObjectFactory {
    static func make(_ kind: ObjectKind, variant: PressVariant, fx: SceneFX) -> PressObjectView {
        let view = build(kind, variant: variant, fx: fx)
        // The mess's walls on the Duo: this object's strike plate (LAUNCH-QA #1).
        fx.foldPlateHalf = GlassDebris.containment(restHeight: view.restHeight, anvilHalf: SIMD2(repeating: 1), padding: 0)
        return view
    }

    private static func build(_ kind: ObjectKind, variant: PressVariant, fx: SceneFX) -> PressObjectView {
        switch kind {
        case .bubbleWrap: BubbleWrapView(variant: variant, fx: fx)
        case .rubberDuck: DuckView(variant: variant, fx: fx)
        case .jelly: JellyView(variant: variant, fx: fx)
        case .crayon: CrayonView(variant: variant, fx: fx)
        case .egg: EggView(variant: variant, fx: fx)
        case .cakeSlice: CakeSliceView(variant: variant, fx: fx)
        case .sodaCan: SodaCanView(variant: variant, fx: fx)
        case .gummyBear: GummyBearView(variant: variant, fx: fx)
        case .glassBottle: GlassBottleView(variant: variant, fx: fx)
        case .unsquishable: UnsquishableView(variant: variant, fx: fx)
        }
    }

    /// The jittered fracture thresholds for this press (identical to the engine's, same seed).
    static func thresholds(_ kind: ObjectKind, variant: PressVariant) -> [Float] {
        kind.profile.jitteredFractures(seed: variant.seed).map { Float($0) }
    }

    /// The failure threshold for this press, if the material has one.
    static func failureThreshold(_ kind: ObjectKind, variant: PressVariant) -> Float? {
        guard let index = kind.profile.failureIndex else { return nil }
        let t = thresholds(kind, variant: variant)
        return index < t.count ? t[index] : nil
    }
}
