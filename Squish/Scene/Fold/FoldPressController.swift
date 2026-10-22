import Foundation
import QuartzCore
import RealityKit
import simd
import UIKit

/// Fold Press (design/FOLD-PRESS.md): on an iPhone Duo the two halves of the inner screen ARE the press plates.
/// Owned by the director as `fold`. It drives, in the same frame as the 3D scene (§3.4 "one clock"):
///  • the anvil half — `PressScene` in `.foldAnvil` framing, rendered from the eye-corrected design eye and
///    keystone-warped so the strike plate lies exactly in the glass (§2.2, §9.3 Tier B);
///  • the platen half — a 2D Core Animation stack: shadow → kiss → print → splat → monoprint (§3);
///  • the bezel — crease band, rails, hazard jaws, crown strip gauge and lamps, console, pilot lamp (§5).
@MainActor
final class FoldPressController {
    let anvil = FoldAnvil()
    let platen = FoldPlaten()
    let bezel = FoldBezel()
    /// The assumed eye (§9.4), exposed for the Tuning Lab.
    var eye = FoldEyeModel.standard {
        didSet { cameraDirty = true; sizeDirty = true }
    }

    private weak var scene: PressScene?
    private weak var host: FoldStageHostView?
    private(set) var layout: FoldLayout?

    // Object
    private var kind: ObjectKind = .bubbleWrap
    private var variant = PressVariant(kind: .bubbleWrap, seed: 1)
    private var stampKey: String?
    private var sinceSet: Double = 0
    private var firstObject = true
    private var hadObject = false
    private var appliedMetresPerMM = FoldMetrics.metresPerMM(foldScale: 1)
    private var targetMetresPerMM: Double?

    // Press
    private var clock: Double = 0
    private var contacted = false
    private var tell = false
    private var failureCompression: Double?
    private var printCompression: Double = 0
    private var renderCompression: Double = 0
    private var yolkBroke = false
    private var damage = 0
    private var hasFolded = false
    private var inviteClock: Double = 1.5
    private var revealAge: Double?

    // Instruments (same feel as the P-48's, VISUAL-TARGET §4.4–4.5)
    private var needleTons: Double = 0
    private var needleVelocity: Double = 0
    private var peakTons: Double = 0
    private var redTimer: Double = 0
    private var blink: Double = 0

    // Anvil camera
    private var viewSize: CGSize = .zero
    private var bookAngle: Double = 180
    private var lastCameraAngle: Double = -1
    private var cameraDirty = true
    private var sizeDirty = true
    private var solution: FoldCameraSolution?

    init() {}

    // MARK: - Hosting (FoldPressView)

    func attach(host: FoldStageHostView, scene: PressScene) {
        self.host = host
        self.scene = scene
        cameraDirty = true
        sizeDirty = true
        applyColours()
        if let layout { apply(layout: layout) }
    }

    func detach(host: FoldStageHostView) {
        guard self.host === host else { return }
        self.host = nil
    }

    /// Called once per canvas size (never on division-region activation, §9.2).
    func apply(layout: FoldLayout) {
        self.layout = layout
        platen.build(layout: layout)
        bezel.build(layout: layout)
        anvil.build(layout: layout)
        anvil.setScale(appliedMetresPerMM)
        applyColours()
        sizeDirty = true
        cameraDirty = true
        resizeAnvilViewIfNeeded()
    }

    private func resizeAnvilViewIfNeeded() {
        guard sizeDirty, let layout, let host else { return }
        sizeDirty = false
        let reference: FoldPose = layout.isBook ? .book(hinge: 120) : .tabletop
        let aspect = FoldCamera.naturalAspect(glass: layout.anvilCorners.glass, eye: eye.renderEye(reference))
        let thermal = ProcessInfo.processInfo.thermalState
        let oversample = (thermal == .serious || thermal == .critical) ? 1.0 : 1.15   // §9.7
        viewSize = FoldCamera.viewSize(half: layout.anvilHalf.size, aspect: aspect, oversample: oversample)
        host.setAnvilViewSize(viewSize)
        cameraDirty = true
    }

    private func applyColours() {
        let gel = StudioEnvironment.gel(for: kind, golden: variant.isGolden)
        let enamel = FoldTextures.enamel(gel: gel, golden: variant.isGolden)
        platen.setEnamel(enamel)
        anvil.setGel(gel, golden: variant.isGolden)
        host?.setEnamel(enamel)
    }

    // MARK: - Contract

    func setObject(_ kind: ObjectKind, variant: PressVariant) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        firstObject = !hadObject
        hadObject = true
        self.kind = kind
        self.variant = variant
        stampKey = nil
        sinceSet = 0
        contacted = false
        tell = false
        failureCompression = nil
        printCompression = 0
        renderCompression = 0
        yolkBroke = false
        damage = 0
        peakTons = 0
        redTimer = 0
        blink = 0
        revealAge = nil
        // The last print wipes off with a squeegee while the next object drops (§6.3 step 6).
        platen.wipe()
        bezel.repair()
        CATransaction.setDisableActions(false)
        applyColours()   // implicit 0.25 s crossfade of the enamel
    }

    func update(engine: PressEngine, context: FeedbackContext, dt: Float) {
        let dt = Double(min(max(dt, 0), 1.0 / 20.0))
        clock += dt
        sinceSet += dt
        let phase = engine.phase
        if phase == .pressing { hasFolded = true }
        if let revealAge { self.revealAge = revealAge + dt }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        resizeAnvilViewIfNeeded()
        updateObjectScale(engine: engine, reduceMotion: context.reduceMotion)

        // Press state, from the same engine fields the 3D scene reads this frame.
        let contactT = engine.mapping.contactT
        let approach = clamp(engine.renderDepth / max(contactT, 0.01), 0, 1)
        renderCompression = engine.renderCompression
        if contacted && (phase == .pressing || phase == .sealed) {
            printCompression = max(printCompression, renderCompression)
        }
        let angle = engine.angle
        let objectPresent = sinceSet > (firstObject ? 0.9 : 1.2) || phase == .pressing

        guard let layout else { return }
        let frame = FoldFrame(angle: angle, approach: approach, compression: renderCompression,
                              printCompression: printCompression, contacted: contacted, tell: tell,
                              failureCompression: failureCompression, objectPresent: objectPresent,
                              tabletop: !layout.isBook, reduceMotion: context.reduceMotion, time: clock, dt: dt,
                              sweep: sweep(engine: engine, angle: angle, objectPresent: objectPresent,
                                           reduceMotion: context.reduceMotion, dt: dt))
        platen.update(frame)
        bezel.update(instruments(engine: engine, approach: approach, reduceMotion: context.reduceMotion, dt: dt),
                     frame: frame)
        updateCamera(layout: layout, angle: angle, dt: dt)
    }

    func handle(_ event: PressEvent, context: FeedbackContext) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        switch event {
        case .contact:
            contacted = true
            needleVelocity += 2 * 18
            platen.kiss(reduceMotion: context.reduceMotion)
        case .preFailureTell:
            tell = true
        case let .fracture(index, isFailure):
            let c = max(printCompression, renderCompression)
            if kind == .egg && index >= 2 { yolkBroke = true }
            let effect = platen.fracture(index: index, isFailure: isFailure, compression: c,
                                         reduceMotion: context.reduceMotion, seed: variant.seed)
            if isFailure {
                tell = false
                failureCompression = c
                redTimer = 0.6
                needleVelocity += 5 * 18
            }
            if kind == .unsquishable {
                damage = isFailure ? 3 : max(damage, min(index + 1, 2))
                if effect == .platenBreaks { bezel.crackGauge(seed: variant.seed) }
            }
        case .reveal:
            revealAge = 0
            platen.reveal()
            let strands = strandCount()
            if strands > 0, let stamp = platen.stack?.stamp {
                bezel.startStrands(count: strands, color: stamp.ink, seed: variant.seed)
            }
        default:
            break
        }
    }

    // MARK: - Object scale (§2.3: rendered rest height ≤ 24 mm)

    /// The scene builds objects asynchronously; once it reports the new object, make its print and its fold scale.
    /// The scale (glass + eye size, so the plates never move) switches while the anvil is empty (rest beat).
    private func updateObjectScale(engine: PressEngine, reduceMotion: Bool) {
        let key = "\(kind.rawValue)-\(variant.seed)-\(variant.isGolden)"
        if stampKey != key, let info = scene?.foldObject, info.kind == kind {
            let scale = FoldMetrics.foldScale(restHeight: Double(info.restHeight))
            platen.setStamp(FoldStamps.stamp(for: kind, variant: variant, foldScale: scale), variant: variant)
            stampKey = key
            targetMetresPerMM = FoldMetrics.metresPerMM(foldScale: scale)
        }
        if let target = targetMetresPerMM {
            let delay = reduceMotion ? 0.45 : 0.8
            if firstObject || sinceSet >= delay || engine.phase == .pressing {
                targetMetresPerMM = nil
                if abs(target - appliedMetresPerMM) > 1e-9 {
                    appliedMetresPerMM = target
                    anvil.setScale(target)
                    cameraDirty = true
                }
            }
        }
    }

    // MARK: - Flat invitation (§7) and the "open me" sheen (§4.3)

    private func sweep(engine: PressEngine, angle: Double, objectPresent: Bool, reduceMotion: Bool, dt: Double) -> Double? {
        // Reveal, dry objects: a crisp peel shimmer across the print, crease → far edge (§6.3 step 2).
        if let age = revealAge, age < 0.45, strandCount() == 0, !reduceMotion {
            return 1 - smooth(age / 0.45)
        }
        guard objectPresent, !reduceMotion else { return nil }
        if !hasFolded && engine.phase == .armed && angle >= 172 && engine.measuredDepth < 0.01 {
            // The lid breathes: every 4 s the sheen sweeps far edge → crease in 800 ms.
            inviteClock += dt
            let t = inviteClock.truncatingRemainder(dividingBy: 4)
            return t < 0.8 ? smooth(t / 0.8) : nil
        }
        inviteClock = 1.5
        if engine.phase == .idle && angle < engine.config.armAngleMin {
            // Landed while folded below the arming angle: the sweep in reverse until it's opened.
            let t = clock.truncatingRemainder(dividingBy: 2.5)
            return t < 0.8 ? 1 - smooth(t / 0.8) : nil
        }
        return nil
    }

    private func smooth(_ t: Double) -> Double {
        let x = clamp(t, 0, 1)
        return x * x * (3 - 2 * x)
    }

    /// Goo strands across the crease at the reveal: jelly, cake, gummy, the egg's yolk, the duck's seam (§6.3).
    private func strandCount() -> Int {
        switch kind {
        case .jelly, .cakeSlice, .gummyBear: return 3
        case .egg: return yolkBroke ? 2 : 0
        case .rubberDuck: return failureCompression != nil ? 2 : 0
        case .bubbleWrap, .crayon, .sodaCan, .glassBottle, .unsquishable: return 0
        }
    }

    // MARK: - Gauge and lamps (2D on the crown strip, §5)

    private func instruments(engine: PressEngine, approach: Double, reduceMotion: Bool, dt: Double) -> FoldInstruments {
        var tons = 0.0
        switch engine.phase {
        case .armed, .pressing:
            if engine.renderDepth < engine.mapping.contactT {
                tons = 0.6 * approach + min(abs(engine.closingSpeed) / 200, 1) * 0.25
            } else if kind == .unsquishable {
                tons = 8 + 60 * renderCompression
            } else {
                tons = 4 + 52 * renderCompression
            }
            peakTons = max(peakTons, tons)
        case .sealed:
            tons = max(peakTons, kind == .unsquishable ? 64 : 50)
        case .idle, .revealing:
            tons = 0
        }
        // Needle: spring response ≈ 0.18 s, damping 0.55 (as the P-48's).
        if dt > 0 {
            let omega = 2 * Double.pi / 0.18, zeta = 0.55
            let steps = max(1, Int((dt * 480).rounded(.up)))
            let h = dt / Double(steps)
            for _ in 0..<steps {
                let accel = -2 * zeta * omega * needleVelocity - omega * omega * (needleTons - tons)
                needleVelocity += accel * h
                needleTons += needleVelocity * h
            }
        }
        var shown = min(needleTons, 63)
        let slamming = engine.isLoaded && engine.closingSpeed > engine.config.slamSpeed
        let buzz = kind == .unsquishable && engine.phase != .revealing && engine.phase != .idle && tons >= 60
        if !reduceMotion {
            if tell { shown += 0.8 / 4.5 * sin(clock * 2 * .pi * 14) }
            if slamming { shown += 3.5 * sin(clock * 2 * .pi * 19) * sin(clock * 2 * .pi * 3.1) }
            if buzz { shown = 62 + 0.6 * sin(clock * 2 * .pi * 23) }
            if !tell && !buzz && tons < 0.01 { shown += 0.3 / 4.5 * sin(clock * 2 * .pi * 0.4) }
        }

        if slamming { redTimer = max(redTimer, 0.6) }
        redTimer = max(redTimer - dt, 0)
        let loaded = engine.isLoaded || engine.phase == .sealed
        let broken = kind == .unsquishable && damage >= 3 && engine.phase != .revealing && engine.phase != .idle
        var ready = 1, load = 0
        if broken {
            blink += dt
            let on = Int(blink * 4) % 2 == 0
            ready = on ? 2 : 0
            load = on ? 2 : 0
        } else if redTimer > 0 {
            ready = 0
            load = 2
        } else if loaded {
            ready = 0
            load = 1
        }
        return FoldInstruments(needle: shown, ready: ready, load: load)
    }

    // MARK: - Anvil camera (§2.2, §9.3 Tier B)

    private func updateCamera(layout: FoldLayout, angle: Double, dt: Double) {
        let pose: FoldPose
        if layout.isBook {
            // Book: the eye rides the wedge bisector, so it moves every frame with θ (gently smoothed).
            bookAngle += (clamp(angle, 40, 180) - bookAngle) * (1 - pow(0.5, dt / 0.03))
            pose = .book(hinge: bookAngle)
            if abs(bookAngle - lastCameraAngle) > 0.02 { cameraDirty = true }
        } else {
            // Tabletop: the eye is fixed relative to the table; recompute on layout only.
            pose = .tabletop
        }
        if cameraDirty || solution == nil {
            cameraDirty = false
            lastCameraAngle = bookAngle
            let corners = layout.anvilCorners
            if viewSize.width > 1,
               let solved = FoldCamera.solve(glass: corners.glass, halfLocal: corners.local, eye: eye.renderEye(pose),
                                             viewSize: viewSize) {
                solution = solved
                host?.setWarp(solved.homography)
            }
        }
        guard let solution else { return }
        let k = appliedMetresPerMM
        func toScene(_ v: SIMD3<Double>) -> SIMD3<Float> { SIMD3<Float>(v * k) }
        let rotation = simd_float3x3(columns: (SIMD3<Float>(solution.right), SIMD3<Float>(solution.up),
                                               SIMD3<Float>(-solution.forward)))
        let distance = Float(simd_length(solution.eye) * k)
        let creaseZ = -(FoldMetrics.footprintFromAxisMM - FoldMetrics.creaseHalf / FoldMetrics.pointsPerMM)
        let lean = contacted ? Float(8 * Double.pi / 180 * renderCompression) : 0
        let stage = FoldStage(cameraPosition: toScene(solution.eye), cameraOrientation: simd_quatf(rotation),
                              verticalFOV: Float(solution.verticalFOV), near: max(0.01, distance * 0.1),
                              far: distance * 4, lean: lean, flashPosition: toScene(SIMD3<Double>(0, 30, creaseZ)),
                              rimGain: Float(FoldCurve.rimGain(angle: angle)))
        self.scene?.setFoldStage(stage)
    }
}
