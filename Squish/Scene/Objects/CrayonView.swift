import Foundation
import RealityKit
import simd
import UIKit

/// Crayon (bible §4 #4, VISUAL-TARGET §5.4): a chunky toddler crayon lying on its side, tip toward front-right,
/// pre-sliced at two seeded planes into three lathe pieces with a paper wrapper band.
/// Rigid until the SNAP (fracture 0 = failure, ~0.30): the crayon breaks in two and the halves hop apart;
/// fracture 1 (~0.52) snaps the second plane; fracture 2 (~0.74) crumbles waxy flakes and leaves smears.
/// Pieces are rigid debris, so the descending ram flattens them into waxy slabs. Cut faces show the fresh-wax core
/// (raspberry for the `secondColourCore` surprise).
@MainActor
final class CrayonView: PressObjectView {
    let entity = Entity()
    /// Chunky toddler crayon: Ø 0.032 × 0.125 (VISUAL-REVIEW-1 fix 6).
    let restHeight: Float = 2 * CrayonView.radius
    let footprint: Float = 0.0625
    private static var wrapperTexture: TextureResource?

    private let fx: SceneFX
    private let look: Look
    private var rng = SplitMix64(seed: 0)
    private let body = Entity()
    private var pieces: [Entity] = []
    private var wrappers: [ModelEntity] = []
    private var chunk: Entity?
    private var failed = false
    private let failC: Float
    private let wax: UIColor

    static let kR: Float = 0.016 / 0.011
    static let kL: Float = 0.125 / 0.113
    static let radius: Float = 0.011 * kR
    static let length: Float = 0.113 * kL
    /// The art-spec profile (r, axial), with a 1.5 mm round where the tip cone meets the body, scaled up.
    static let profile: [SIMD2<Float>] = [
        SIMD2(0.000, 0.000), SIMD2(0.0095, 0.000), SIMD2(0.0110, 0.0015), SIMD2(0.0110, 0.0865), SIMD2(0.01065, 0.0895),
        SIMD2(0.0045, 0.1050), SIMD2(0.0025, 0.1090), SIMD2(0.0010, 0.1120), SIMD2(0.000, 0.1130),
    ].map { SIMD2($0.x * kR, $0.y * kL) }
    static let wrapperRange: ClosedRange<Float> = (0.008 * kL)...(0.078 * kL)

    init(variant: PressVariant, fx: SceneFX) {
        self.fx = fx
        let look = Look(variant)
        self.look = look
        var rng = SplitMix64(seed: variant.seed ^ 0xC4A7)
        failC = PressObjectFactory.failureThreshold(.crayon, variant: variant) ?? 0.3
        let wax = Palette.cobalt
        self.wax = wax
        let cut1 = Float.random(in: 0.030...0.048, using: &rng) * Self.kL
        let cut2 = Float.random(in: 0.062...0.080, using: &rng) * Self.kL
        self.rng = rng

        let waxMaterial = look.body(wax, roughness: 0.52, clearcoat: 0)
        let coreColour = variant.surprise == .secondColourCore ? Palette.raspberry : UIColor(hex: 0x6F8EF2)
        let coreMaterial = SceneMaterials.pbr(coreColour, roughness: 0.45)
        // Printed wrapper (cobalt wave band + "WAXO", VISUAL-REVIEW-1 fix 11); Golden prints in dark gold.
        // The print uploads asynchronously (never block main); plain paper shows until it lands.
        let cachedWrapper = look.golden ? nil : Self.wrapperTexture
        let paper: PhysicallyBasedMaterial
        if let cachedWrapper {
            paper = SceneMaterials.textured(cachedWrapper, roughness: 0.75)
        } else {
            paper = SceneMaterials.pbr(UIColor(hex: 0xF4ECDD), roughness: 0.75)
        }

        // Lying: lathe about local Y, rolled −90° about Z (tip → +X), centred on its length, resting on the anvil.
        body.orientation = simd_quatf(angle: -.pi / 2, axis: [0, 0, 1])
        body.position = [0, Self.radius, 0]
        let axial = Entity()
        axial.position = [0, -Self.length / 2, 0]
        body.addChild(axial)
        let ranges: [ClosedRange<Float>] = [0...cut1, cut1...cut2, cut2...Self.length]
        for (i, range) in ranges.enumerated() {
            let piece = Entity()
            let mid = (range.lowerBound + range.upperBound) / 2
            piece.position = [0, mid, 0]
            let mesh = Self.pieceMesh(range).translated([0, -mid, 0])
            Part.add(mesh, waxMaterial, to: piece)
            // Fresh-wax core discs on the cut faces (hidden while intact).
            if i > 0 {
                Part.add(cached: "crayon.core", { MeshKit.roundedCylinder(radius: 0.0052 * Self.kR, height: 0.0006, bevel: 0.0002, segments: 32) },
                         coreMaterial, at: [0, range.lowerBound - mid - 0.0005, 0], to: piece)
            }
            if i < 2 {
                Part.add(cached: "crayon.core", { MeshKit.roundedCylinder(radius: 0.0052 * Self.kR, height: 0.0006, bevel: 0.0002, segments: 32) },
                         coreMaterial, at: [0, range.upperBound - mid - 0.0001, 0], to: piece)
            }
            // Wrapper segment of this piece; v spans the whole wrapper so the print is continuous across the cuts.
            let lo = max(range.lowerBound, Self.wrapperRange.lowerBound), hi = min(range.upperBound, Self.wrapperRange.upperBound)
            if hi - lo > 0.001 {
                let r = 0.0114 * Self.kR
                let wrapper = MeshKit.latheUV(profile: [SIMD2(r, lo), SIMD2(r, (lo + hi) / 2), SIMD2(r, hi)], segments: 48,
                                              vRange: Self.wrapperRange)
                wrappers.append(Part.add(wrapper.translated([0, -mid, 0]), paper, to: piece))
            }
            axial.addChild(piece)
            pieces.append(piece)
        }
        entity.addChild(body)
        entity.orientation = Part.yaw(-20)
        if cachedWrapper == nil {
            let band = look.golden ? UIColor(hex: 0x8A5A00) : Palette.cobalt
            let golden = look.golden
            Task { @MainActor [weak self] in
                guard let texture = await Self.wrapper(band: band, golden: golden), let self else { return }
                let material = SceneMaterials.textured(texture, roughness: 0.75)
                for model in self.wrappers { model.model?.materials = [material] }
            }
        }
    }

    /// The WAXO wrapper print (drawn once; the Golden print is drawn on demand).
    private static func wrapper(band: UIColor, golden: Bool) async -> TextureResource? {
        if !golden, let cached = wrapperTexture { return cached }
        let texture = await StudioEnvironment.textureAsync(RigTextures.crayonWrapper(band: band), name: golden ? "crayon.wrapper.gold" : "crayon.wrapper")
        if !golden { wrapperTexture = texture }
        return texture
    }

    /// One capped lathe slice of the crayon profile between two axial positions.
    static func pieceMesh(_ range: ClosedRange<Float>) -> MeshData {
        func radius(_ y: Float) -> Float {
            for i in 0..<(profile.count - 1) where y <= profile[i + 1].y {
                let a = profile[i], b = profile[i + 1]
                return a.x + (b.x - a.x) * (y - a.y) / max(b.y - a.y, 1e-6)
            }
            return 0
        }
        var points: [SIMD2<Float>] = []
        let lo = range.lowerBound, hi = range.upperBound
        if lo > 0 {
            points.append(SIMD2(0, lo))
            points.append(SIMD2(radius(lo) - 0.0008, lo))
            points.append(SIMD2(radius(lo), lo + 0.0006))
        }
        for p in profile where p.y > lo + 0.0006 && p.y < hi - 0.0006 { points.append(p) }
        if lo == 0 { points.insert(contentsOf: profile.prefix { $0.y <= 0.0006 }, at: 0) }
        if hi < length {
            points.append(SIMD2(radius(hi), hi - 0.0006))
            points.append(SIMD2(radius(hi) - 0.0008, hi))
            points.append(SIMD2(0, hi))
        } else {
            points.append(contentsOf: profile.filter { $0.y >= hi - 0.0006 })
        }
        // Extra rings along long straight runs keep the shading smooth.
        var dense: [SIMD2<Float>] = []
        for (i, p) in points.enumerated() {
            if i > 0 {
                let q = points[i - 1]
                let steps = Int((abs(p.y - q.y) / 0.01).rounded(.down))
                if steps > 1 {
                    for k in 1..<steps {
                        let t = Float(k) / Float(steps)
                        dense.append(q + (p - q) * t)
                    }
                }
            }
            dense.append(p)
        }
        return MeshKit.lathe(profile: dense, segments: 48)
    }

    func surfaceHeight(compression c: Float) -> Float {
        HeightCurve.brittle(c, rest: restHeight, failC: failC, failed: failed, rigidSquash: 0.05,
                            afterRatio: 0.85, minRatio: 0.25)
    }

    func update(_ state: PressVisualState) {
        guard !failed else { return }
        // Before the snap the wax gives a hair and bows a little in the middle.
        let s = surfaceHeight(compression: state.compression) / restHeight
        // Body local X is world-vertical after the roll; local Z is the horizontal cross axis.
        body.scale = SIMD3(s, 1, 1 / s.squareRoot())
        let bow = 0.03 * min(state.compression / max(failC, 0.01), 1)
        if pieces.count == 3 {
            pieces[0].orientation = simd_quatf(angle: bow, axis: [0, 0, 1])
            pieces[2].orientation = simd_quatf(angle: -bow, axis: [0, 0, 1])
        }
    }

    func fracture(index: Int, isFailure: Bool, state: PressVisualState) {
        let m = fx.motionScale
        switch index {
        case 0:
            // SNAP: piece 0 flies one way, pieces 1+2 (one chunk) the other.
            failed = true
            body.scale = SIMD3(repeating: 1)
            let chunk = Entity()
            pieces[1].parent?.addChild(chunk)
            chunk.transform = pieces[1].transform
            pieces[1].setParent(chunk, preservingWorldTransform: true)
            pieces[2].setParent(chunk, preservingWorldTransform: true)
            self.chunk = chunk
            fx.debris.adopt(pieces[0], velocity: SIMD3(-0.18, 0.32, Float.random(in: -0.05...0.05, using: &rng)) * m,
                            spin: SIMD3(0, Float.random(in: -6...6, using: &rng), Float.random(in: 2...5, using: &rng)) * m)
            fx.debris.adopt(chunk, velocity: SIMD3(0.12, 0.22, Float.random(in: -0.05...0.05, using: &rng)) * m,
                            spin: SIMD3(0, Float.random(in: -4...4, using: &rng), -Float.random(in: 1...3, using: &rng)) * m)
            flakes(count: 5, at: pieces[1].convert(position: [0, -0.02, 0], to: fx.root))
        case 1:
            // Second snap: the chunk splits.
            guard let chunk, let body = fx.debris.release(chunk) else { return }
            for (k, piece) in [pieces[1], pieces[2]].enumerated() {
                let sign: Float = k == 0 ? -1 : 1
                fx.debris.adopt(piece, velocity: (body.velocity + SIMD3(sign * 0.12, 0.2, 0)) * m,
                                spin: SIMD3(0, sign * 4, sign * 3) * m)
            }
            chunk.removeFromParent()
            self.chunk = nil
            flakes(count: 5, at: pieces[2].convert(position: .zero, to: fx.root))
        default:
            // Waxy crumble: flakes and smears that persist.
            for piece in pieces {
                let p = piece.position(relativeTo: fx.root)
                let smear = ModelEntity(mesh: MeshCache.resource("crayon.smear") {
                    MeshKit.spreadDisc(seed: 0x5EA, height: 1, segments: 32, wobble: 0.18)
                } ?? .generateSphere(radius: 0.01), materials: [look.golden ? SceneMaterials.goldMess
                    : SceneMaterials.pbr(UIColor(hex: 0x6F8EF2), roughness: 0.45, clearcoat: 0.3)])
                smear.position = [p.x, 0.0003, p.z]
                smear.scale = [0.024, 0.0012, 0.011]
                // Flat on the anvil, long axis along the piece's (crayon) axis: yaw only.
                let axis = piece.convert(direction: [0, 1, 0], to: fx.root)
                smear.orientation = simd_quatf(angle: atan2(-axis.z, axis.x), axis: [0, 1, 0])
                fx.addMess(smear)
            }
            flakes(count: 10, at: SIMD3(0, 0.01, 0))
        }
    }

    private func flakes(count: Int, at position: SIMD3<Float>) {
        let colors = look.golden ? [Palette.gold, Palette.goldMessColor] : [wax, UIColor(hex: 0x6F8EF2)]
        fx.particles.burst(.flake, count: count, at: position, speed: 0.35 * max(fx.motionScale, 0.3), colors: colors,
                           size: 0.002...0.004, spread: 0.01, upBias: 0.4, rng: &rng)
    }
}
