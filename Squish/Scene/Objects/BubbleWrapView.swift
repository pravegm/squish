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
        poppedMaterial = look.golden ? SceneMaterials.gold
            : SceneMaterials.enamel(UIColor(hex: 0xC6DCE7), roughness: 0.22, clearcoat: 0.6, clearcoatRoughness: 0.12,
                                    specular: 0.6, opacity: 0.80) // popped: stress-whitened but ~15 L darker so pops read (FOLD-REVIEW-1 #10)
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
        let filmMaterial = look.golden ? SceneMaterials.gold
            : SceneMaterials.enamel(UIColor(hex: 0xDDEFF8), roughness: 0.12, clearcoat: 0.6, clearcoatRoughness: 0.08,
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
        let h = surfaceHeight(compression: state.compression)
        let available = max(h - Self.film, 0.0003)
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
