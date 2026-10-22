import Foundation
import RealityKit
import simd
import UIKit

/// Bubble Wrap (bible §4 #1, VISUAL-TARGET §5.1): a clear film sheet with a grid of glossy domes.
/// Unpopped domes squash and spread under the plate; each pops at its own seeded threshold (one fracture per
/// bubble, no single failure) with a soft puff, and stays a flat, stress-whitened crinkle. Never holes.
/// Grid is 6 × 4 to match `BubbleWrapLayout` (Core; the art spec's 6 × 6 needs 36 thresholds).
/// Surprise `megaBubble`: the four centre cells are one 2.2× dome that strains three times and pops on the fourth.
@MainActor
final class BubbleWrapView: PressObjectView {
    private static let film: Float = 0.0008
    private static let radius: Float = 0.0075
    private static let domeHeight: Float = 0.0070
    private static let pitch = SIMD2<Float>(0.0175, 0.0195)
    private static let sheetSize = SIMD2<Float>(0.110, 0.090)
    private static let megaScale: Float = 2.2

    let entity = Entity()
    let restHeight: Float
    let footprint: Float = 0.055
    private let minHeightRatio: Float = 0.3

    private let fx: SceneFX
    private var rng = SplitMix64(seed: 0)
    private let look: Look
    private var cells: [Cell] = []
    /// Fracture index → cell index (seeded ripple order).
    private let popOrder: [Int]
    private var mega: Cell?
    private var megaCells: Set<Int> = []
    private var megaStrain = 0
    private var crinkles: [MeshResource] = []
    private let poppedMaterial: PhysicallyBasedMaterial
    /// Crater tells (FOLD-REVIEW-3 N9 / FOLD-REVIEW-4 F8): a 1 pt blue rim at 0.6 round each pop and a tiny bright
    /// pinhole, so popped cells read as craters on grey steel instead of grey on grey.
    private let craterRimMaterial: PhysicallyBasedMaterial
    private let pinholeMaterial: UnlitMaterial
    private var lowest: Float = .infinity

    private final class Cell {
        let model: ModelEntity
        let scale: Float
        var popped = false
        var tilt = simd_quatf(angle: 0, axis: [0, 1, 0])
        var strain: Float = 0
        init(model: ModelEntity, scale: Float) {
            self.model = model
            self.scale = scale
        }
    }

    init(variant: PressVariant, fx: SceneFX) {
        self.fx = fx
        let look = Look(variant)
        self.look = look
        var rng = SplitMix64(seed: variant.seed ^ 0xB0BB1E)
        let hasMega = variant.surprise == .megaBubble
        restHeight = Self.film + Self.domeHeight * (hasMega ? Self.megaScale : 1)
        popOrder = Array(0..<BubbleWrapLayout.count).shuffled(using: &rng)
        // Popped: stress-whitened, the crater centre a further ~15 L down (#C6DCE7 → #B8CDD7, FOLD-REVIEW-3 N9) so pops
        // read against the film.
        poppedMaterial = look.golden ? SceneMaterials.gold
            : SceneMaterials.enamel(UIColor(hex: 0xB8CDD7), roughness: 0.24, clearcoat: 0.6, clearcoatRoughness: 0.12,
                                    specular: 0.6, opacity: 0.82)
        craterRimMaterial = look.golden ? SceneMaterials.gold
            : SceneMaterials.enamel(UIColor(hex: 0x6FAED0), roughness: 0.3, clearcoat: 0.4, clearcoatRoughness: 0.15, opacity: 0.6)
        pinholeMaterial = SceneMaterials.unlit(UIColor(hex: 0xFFFFFF), opacity: 0.9)
        self.rng = rng
        build(variant: variant, hasMega: hasMega)
    }

    private func build(variant: PressVariant, hasMega: Bool) {
        for k in 0..<3 {
            if let crinkle = MeshCache.resource("bubble.crinkle.\(k)", {
                MeshKit.spreadDisc(seed: 0xC41 &+ UInt64(k) &* 977, height: 1, segments: 24, wobble: 0.24)
            }) { crinkles.append(crinkle) }
        }
        entity.orientation = Part.yaw(12)
        // Lifted 0.6 mm so the 0.8 mm film never z-fights the strike plate (FOLD-REVIEW-2 #8).
        entity.position = [0, 0.0006, 0]
        // Film base 6 % darker (#DDEFF8 → #D0E1E9, FOLD-REVIEW-4 F8): it was the brightest thing on the anvil at 180°.
        let filmMaterial = look.golden ? SceneMaterials.gold
            : SceneMaterials.enamel(UIColor(hex: 0xD0E1E9), roughness: 0.12, clearcoat: 0.6, clearcoatRoughness: 0.08,
                                    specular: 0.6, opacity: 0.55)
        let domeMaterial = look.golden ? SceneMaterials.gold
            : SceneMaterials.enamel(UIColor(hex: 0xB9DCEE), roughness: 0.12, clearcoat: 0.6, clearcoatRoughness: 0.08,
                                    specular: 0.6, opacity: 0.52)
        let sheet = Part.add(cached: "bubble.sheet", {
            MeshKit.roundedBox([Self.sheetSize.x, Self.film, Self.sheetSize.y], radius: 0.006, bevel: 0.0004)
        }, filmMaterial, at: [0, Self.film / 2, 0], to: entity)
        _ = sheet
        // A 1 mm blue edge so the clear sheet reads on pale steel (FOLD-REVIEW-1 #10).
        let edgeMaterial = look.golden ? SceneMaterials.gold
            : SceneMaterials.enamel(UIColor(hex: 0x6FAED0), roughness: 0.3, clearcoat: 0.4, clearcoatRoughness: 0.15)
        let w = Self.sheetSize.x, d = Self.sheetSize.y, t: Float = 0.0012
        for side: Float in [-1, 1] {
            Part.add(cached: "bubble.edge.x", { MeshKit.roundedBox([w - 0.008, Self.film + 0.0002, t], radius: 0.0005, bevel: 0.0002) },
                     edgeMaterial, at: [0, Self.film / 2, side * (d / 2 - t / 2)], to: entity)
            Part.add(cached: "bubble.edge.z", { MeshKit.roundedBox([t, Self.film + 0.0002, d - 0.008], radius: 0.0005, bevel: 0.0002) },
                     edgeMaterial, at: [side * (w / 2 - t / 2), Self.film / 2, 0], to: entity)
        }

        let domeMesh = MeshCache.resource("bubble.dome", { Self.dome() }) ?? MeshResource.generateSphere(radius: 1)
        let columns = BubbleWrapLayout.columns, rows = BubbleWrapLayout.rows
        if hasMega {
            megaCells = [1 * columns + 2, 1 * columns + 3, 2 * columns + 2, 2 * columns + 3]
        }
        for row in 0..<rows {
            for column in 0..<columns {
                let index = row * columns + column
                let model = ModelEntity(mesh: domeMesh, materials: [domeMaterial])
                model.position = [Self.pitch.x * (Float(column) - Float(columns - 1) / 2), Self.film,
                                  Self.pitch.y * (Float(row) - Float(rows - 1) / 2)]
                let cell = Cell(model: model, scale: 1)
                let axis = simd_normalize(SIMD3<Float>(Float.random(in: -1...1, using: &rng), 0.15,
                                                       Float.random(in: -1...1, using: &rng)))
                cell.tilt = simd_quatf(angle: Float.random(in: -0.18...0.18, using: &rng), axis: axis)
                if megaCells.contains(index) {
                    model.isEnabled = false
                    cell.popped = true
                }
                entity.addChild(model)
                cells.append(cell)
            }
        }
        if hasMega {
            let model = ModelEntity(mesh: domeMesh, materials: [domeMaterial])
            model.position = [0, Self.film, 0]
            entity.addChild(model)
            mega = Cell(model: model, scale: Self.megaScale)
        }
    }

    /// A closed dome of unit radius and `domeHeight / radius` height (flat base, quarter-ellipse cap).
    static func dome() -> MeshData {
        let h = domeHeight / radius
        var profile: [SIMD2<Float>] = [SIMD2(0, 0)]
        for k in 0...12 {
            let a = Float.pi / 2 * Float(k) / 12
            profile.append(SIMD2(cos(a), h * sin(a)))
        }
        profile[profile.count - 1].x = 0
        return MeshKit.lathe(profile: profile, segments: 24)
    }

    func surfaceHeight(compression c: Float) -> Float {
        HeightCurve.linear(c, rest: restHeight, minRatio: minHeightRatio)
    }

    func update(_ state: PressVisualState) {
        // Latched at the deepest squash (FOLD-REVIEW-3 N6): unpopped domes don't re-inflate on reopening, so the
        // reveal is at least as pressed as the sealed frame.
        lowest = min(lowest, surfaceHeight(compression: state.compression))
        let available = max(lowest - Self.film, 0.0003)
        for cell in cells where !cell.popped {
            apply(cell, available: available)
        }
        if let mega, !mega.popped {
            apply(mega, available: available)
        }
    }

    private func apply(_ cell: Cell, available: Float) {
        let full = Self.domeHeight * cell.scale
        let squashY = min(available / full, 1) * (1 - 0.05 * cell.strain)
        let spread = 1 + 0.42 * (1 - squashY)
        let r = Self.radius * cell.scale
        cell.model.scale = SIMD3(r * spread, r * squashY, r * spread)
    }

    func fracture(index: Int, isFailure: Bool, state: PressVisualState) {
        let cellIndex = popOrder[index % popOrder.count]
        if megaCells.contains(cellIndex), let mega {
            // One of the mega bubble's cells: strain three times, then the big pop.
            megaStrain += 1
            mega.strain = Float(min(megaStrain, 3))
            if megaStrain >= 4 { pop(mega, big: true) }
            return
        }
        let cell = cells[cellIndex]
        guard !cell.popped else { return }
        pop(cell, big: false)
    }

    private func pop(_ cell: Cell, big: Bool) {
        cell.popped = true
        if !crinkles.isEmpty {
            cell.model.model?.mesh = crinkles[Int(rng.next() % UInt64(crinkles.count))]
        }
        cell.model.model?.materials = [poppedMaterial]
        let r = Self.radius * cell.scale
        cell.model.scale = SIMD3(r * 1.25, 0.0006, r * 1.25)
        cell.model.orientation = cell.tilt
        cell.model.position.y = Self.film + 0.0002
        // The crater rim (a thin #6FAED0 ring at 0.6, ≈ 1 pt on the Duo) and a pinhole glint, tilted with the crinkle.
        if let rimMesh = MeshCache.resource("bubble.crater.rim", { MeshKit.torus(major: 1, minor: 0.03, segments: 40, sides: 6) }) {
            let rim = ModelEntity(mesh: rimMesh, materials: [craterRimMaterial])
            let ring = r * BubbleCrater.rimRadius
            rim.scale = SIMD3(ring, 0.0006, ring)
            rim.orientation = cell.tilt
            rim.position = cell.model.position + SIMD3(0, 0.0007, 0)
            entity.addChild(rim)
        }
        if let glintMesh = MeshCache.resource("bubble.crater.pinhole", { MeshKit.ellipsoid(radii: [1, 0.3, 1], segments: 12, rings: 6) }) {
            let glint = ModelEntity(mesh: glintMesh, materials: [pinholeMaterial])
            glint.scale = SIMD3(repeating: r * BubbleCrater.pinholeRadius)
            glint.orientation = cell.tilt
            // A little off-centre toward the key light (−X, −Z), so it reads as a highlight, not a hole.
            glint.position = cell.model.position + cell.tilt.act(SIMD3(-0.25 * r, 0.0008, -0.2 * r))
            entity.addChild(glint)
        }
        let puffAt = entity.convert(position: cell.model.position + SIMD3(0, 0.003, 0), to: fx.root)
        fx.particles.burst(.dust, count: big ? 8 : 2, at: puffAt, speed: big ? 0.12 : 0.05,
                           colors: [look.tint(UIColor(hex: 0xF4FBFE))], size: big ? 0.005...0.009 : 0.003...0.005,
                           spread: big ? 0.012 : 0.003, upBias: 0.2, life: 0.45, rng: &rng)
        if big {
            fx.particles.burst(.flake, count: 4, at: puffAt, speed: 0.15, colors: [UIColor(hex: 0xE4F3FA)],
                               size: 0.003...0.004, upBias: 0.4, rng: &rng)
        }
    }
}

/// Popped-crater sizes as multiples of the dome radius (FOLD-REVIEW-3 N9), pure so SquishTests can pin them.
enum BubbleCrater {
    /// The blue rim ring sits just inside the crinkle's ragged edge (the crinkle is 1.25× the dome).
    static let rimRadius: Float = 1.2
    /// The pinhole glint: ≈ 0.75 mm on a normal cell.
    static let pinholeRadius: Float = 0.1
}
