import Foundation
import RealityKit
import simd
import UIKit

/// Bubble Wrap (bible §4 #1, VISUAL-TARGET §5.1), rebuilt for FOLD-REVIEW-5 N10: from above it must read as a sheet of
/// real bubble wrap. A tinted clear film with a milky heat-sealed margin and an opaque dark cut edge carries a regular
/// hex grid of glossy domes; each dome has an opaque blue-grey crease ring where it meets the film, a darker wall round a
/// clear crown, and two opaque glints (`BubbleWrapLook`, FOLD-REVIEW-6), so it reads on the P-48's bright steel, on the
/// Duo's mid-grey plate and in the shadow under the P-48's press plate.
/// As the press closes the domes squash and bulge, then pop one by one in the order of the press's pressure map
/// (`BubbleWrapGrid`: a ripple from the front rows to the back, seeded so no two presses pop alike); each pop leaves a
/// flat, crinkled, stress-whitened crater with radial creases and a ragged rim. Never holes.
/// Grid: 6 columns × 4 cells, columns staggered half a cell (a true hex packing), to match `BubbleWrapLayout`'s 24
/// fracture thresholds. Performance: every dome shares one three-slot shell mesh and one glint mesh, and every crater
/// one of three crinkle meshes (two slots), so RealityKit batches them: ≤ 5 × 25 + 2 × 25 small models,
/// squashed by entity scale only (no CPU deformation, no per-frame mesh upload).
/// Surprise `megaBubble`: the four centre cells are one 2× dome that strains three times and pops on the fourth.
@MainActor
final class BubbleWrapView: PressObjectView {
    let entity = Entity()
    let restHeight: Float
    let footprint: Float = 0.055
    private let minHeightRatio: Float = 0.3

    private let fx: SceneFX
    private var rng = SplitMix64(seed: 0)
    private let look: Look
    private var cells: [Cell] = []
    /// Fracture index → cell index (the pressure-map order, `BubbleWrapGrid.popOrder`).
    private let popOrder: [Int]
    private var mega: Cell?
    private var megaStrain = 0
    private var craterMeshes: [[MeshResource]] = []
    private let craterFilm: any Material
    private let craterCrease: any Material
    private var lowest: Float = .infinity
    /// Craters still snapping flat after their pop, with their settled radius (metres).
    private var snapping: [(crater: Entity, radius: Float, age: Float)] = []
    /// The storyboard (OBJECT-STORYBOARDS §1): an idle shimmer over the domes, ripples between pops.
    private let life: ObjectLife
    private var story: StoryCursor
    private var lastPopped: Cell?
    private var craters: [Entity] = []

    private final class Cell {
        /// Carries the squash: (R·spread, H·squash, R·spread) of the unit dome.
        let root: Entity
        let centre: SIMD2<Float>
        /// Radius and full height (metres) of this dome.
        let radius: Float
        let height: Float
        var popped = false
        var strain: Float = 0
        /// The ripple: a dome jiggles when a neighbour pops (OBJECT-STORYBOARDS §1).
        var wobble = JiggleSpring(value: 0, velocity: 0, omega: 2 * .pi * 9, zeta: 0.3)
        init(root: Entity, centre: SIMD2<Float>, radius: Float, height: Float) {
            self.root = root
            self.centre = centre
            self.radius = radius
            self.height = height
        }
    }

    init(variant: PressVariant, fx: SceneFX) {
        self.fx = fx
        let look = Look(variant)
        self.look = look
        let hasMega = variant.surprise == .megaBubble
        restHeight = BubbleWrapGrid.film + BubbleWrapGrid.domeHeight * (hasMega ? BubbleWrapGrid.megaHeightScale : 1)
        popOrder = BubbleWrapGrid.popOrder(seed: variant.seed)
        rng = SplitMix64(seed: variant.seed ^ 0xB0BB1E)
        life = ObjectLife(seed: variant.seed, idle: .still, amount: 0, rate: 0.3)
        story = StoryCursor(.bubbleWrap, seed: variant.seed)
        if look.golden {
            craterFilm = SceneMaterials.gold
            craterCrease = SceneMaterials.pbr(UIColor(hex: 0xB98A1E), roughness: 0.3, metallic: 1)
        } else {
            // Popped film: stress-whitened and crinkled (lit, so the folds catch the light), with opaque blue-grey
            // creases (FOLD-REVIEW-6: at 0.62 / 0.82 the craters were the only part of the sheet that read at all).
            craterFilm = SceneMaterials.enamel(UIColor(hex: BubbleWrapLook.craterTint), roughness: 0.3, clearcoat: 0.5,
                                               clearcoatRoughness: 0.2, specular: 0.7, opacity: BubbleWrapLook.craterOpacity)
            craterCrease = SceneMaterials.enamel(UIColor(hex: BubbleWrapLook.creaseTint), roughness: 0.28, clearcoat: 0.5,
                                                 clearcoatRoughness: 0.15)
        }
        build(hasMega: hasMega)
    }

    private func build(hasMega: Bool) {
        let golden = look.golden
        for k in 0..<BubbleWrapGrid.craterVariants {
            let slots = Self.slotResources("bubble.crater.\(k)", slots: 2) { BubbleWrapGrid.craterMesh(seed: 0xC41 &+ UInt64(k) &* 977) }
            let found = slots.compactMap { $0 }
            if found.count == 2 { craterMeshes.append(found) }
        }
        entity.orientation = Part.yaw(12)
        // Lifted 0.6 mm so the 0.8 mm film never z-fights the strike plate (FOLD-REVIEW-2 #8).
        entity.position = [0, 0.0006, 0]

        // The film (FOLD-REVIEW-6: invisible at 0.2 on the P-48's bright steel). A pale blue-grey film at 0.34, so the
        // sheet reads as a sheet on both plates without turning into a white card (R5 N10: 0.55), a denser milky seal
        // margin, and an opaque dark cut line on the edge, so the sheet's outline reads whatever the sort order.
        let size = BubbleWrapGrid.sheetSize, film = BubbleWrapGrid.film
        let filmMaterial = golden ? SceneMaterials.gold
            : SceneMaterials.enamel(UIColor(hex: BubbleWrapLook.filmTint), roughness: 0.08, clearcoat: 1,
                                    clearcoatRoughness: 0.04, specular: 1, opacity: BubbleWrapLook.filmOpacity)
        Part.add(cached: "bubble.sheet", {
            MeshKit.roundedBox([size.x, film, size.y], radius: BubbleWrapGrid.sheetCorner, bevel: 0.0003)
        }, filmMaterial, at: [0, film / 2, 0], to: entity)
        let sealMaterial = golden ? SceneMaterials.gold
            : SceneMaterials.enamel(UIColor(hex: BubbleWrapLook.sealTint), roughness: 0.2, clearcoat: 0.6,
                                    clearcoatRoughness: 0.1, opacity: BubbleWrapLook.sealOpacity)
        Part.add(cached: "bubble.seal", {
            BubbleWrapGrid.ring(size: size, corner: BubbleWrapGrid.sheetCorner, inset: BubbleWrapGrid.sealWidth)
        }, sealMaterial, at: [0, film + BubbleWrapGrid.layerStep * 3, 0], to: entity)
        let cutMaterial: any Material
        if golden {
            cutMaterial = SceneMaterials.pbr(UIColor(hex: 0xB98A1E), roughness: 0.3, metallic: 1)
        } else {
            cutMaterial = SceneMaterials.unlit(UIColor(hex: BubbleWrapLook.cutTint))
        }
        Part.add(cached: "bubble.cut", {
            BubbleWrapGrid.ring(size: size, corner: BubbleWrapGrid.sheetCorner, inset: BubbleWrapGrid.cutWidth)
        }, cutMaterial, at: [0, film + BubbleWrapGrid.layerStep * 4, 0], to: entity)

        // The domes (FOLD-REVIEW-6): every dome shares one shell in three slots — a clear crown (slot 0), an opaque dark
        // crease ring where it is moulded out of the film (slot 1) and a darker "refraction" wall (slot 2), so from above
        // each dome is a dark ring round a bright crown, as real bubble wrap reads on a bright surface. Two opaque
        // highlights (the key glint up-left, a small bounce glint low on the far side) give it its gloss even when
        // the translucent layers sort badly.
        let shellMaterial = golden ? SceneMaterials.gold
            : SceneMaterials.enamel(UIColor(hex: BubbleWrapLook.crownTint), roughness: 0.05, clearcoat: 1,
                                    clearcoatRoughness: 0.03, specular: 1, opacity: BubbleWrapLook.crownOpacity)
        let creaseMaterial: any Material = golden ? SceneMaterials.pbr(UIColor(hex: 0xB98A1E), roughness: 0.3, metallic: 1)
            : SceneMaterials.enamel(UIColor(hex: BubbleWrapLook.creaseTint), roughness: 0.25, clearcoat: 0.6,
                                    clearcoatRoughness: 0.1)
        let rimMaterial = golden ? SceneMaterials.gold
            : SceneMaterials.enamel(UIColor(hex: BubbleWrapLook.rimTint), roughness: 0.06, clearcoat: 1,
                                    clearcoatRoughness: 0.03, specular: 1, opacity: BubbleWrapLook.rimOpacity)
        let glintMaterial = SceneMaterials.unlit(UIColor(hex: 0xFFFFFF))
        let bounceMaterial = SceneMaterials.unlit(UIColor(hex: BubbleWrapLook.bounceTint))
        let dome = Self.slotResources("bubble.dome", slots: 3) { BubbleWrapGrid.domeMesh() }
        let domeMaterials: [any Material] = [shellMaterial, creaseMaterial, rimMaterial]
        let glintMesh = MeshCache.resource("bubble.glint") { MeshKit.ellipsoid(radii: [1, 0.3, 0.62], segments: 16, rings: 8) }
        let highlights = [(BubbleWrapGrid.glint, glintMaterial), (BubbleWrapGrid.bounceGlint, bounceMaterial)]

        func makeDome(centre: SIMD2<Float>, radius: Float, height: Float) -> Cell {
            let root = Entity()
            root.position = [centre.x, film + BubbleWrapGrid.layerStep, centre.y]
            for (slot, mesh) in dome.enumerated() where slot < domeMaterials.count {
                if let mesh { root.addChild(ModelEntity(mesh: mesh, materials: [domeMaterials[slot]])) }
            }
            if let glintMesh {
                for (highlight, material) in highlights {
                    let spot = ModelEntity(mesh: glintMesh, materials: [material])
                    spot.position = highlight.position
                    spot.orientation = simd_quatf(from: [0, 1, 0], to: highlight.normal)
                    spot.scale = SIMD3(repeating: highlight.size)
                    root.addChild(spot)
                }
            }
            entity.addChild(root)
            let cell = Cell(root: root, centre: centre, radius: radius, height: height)
            apply(cell, available: .infinity)
            return cell
        }

        let ranks = BubbleWrapGrid.ranks(popOrder)
        for index in 0..<BubbleWrapGrid.count {
            let height = BubbleWrapGrid.domeHeight * BubbleWrapGrid.heightScale(rank: ranks[index])
            let cell = makeDome(centre: BubbleWrapGrid.centre(index), radius: BubbleWrapGrid.radius, height: height)
            if hasMega && BubbleWrapGrid.megaCells.contains(index) {
                cell.root.isEnabled = false
                cell.popped = true
            }
            cells.append(cell)
        }
        if hasMega {
            mega = makeDome(centre: .zero, radius: BubbleWrapGrid.radius * BubbleWrapGrid.megaScale,
                            height: BubbleWrapGrid.domeHeight * BubbleWrapGrid.megaHeightScale)
        }
    }

    /// Cached resources for each material slot of one mesh (`key.slot`), indexed by slot; an empty slot is nil (so a
    /// missing slot never shifts the others onto the wrong material).
    private static func slotResources(_ key: String, slots: Int, _ build: () -> MeshData) -> [MeshResource?] {
        let mesh = MeshCache.mesh(key, build)
        let parts = mesh.splitByMaterial()
        var result: [MeshResource?] = []
        for slot in 0..<slots {
            let part = parts.first { $0.slot == slot }?.mesh ?? MeshData()
            result.append(part.isValid ? MeshCache.resource("\(key).\(slot)", { part }) : nil)
        }
        return result
    }

    func surfaceHeight(compression c: Float) -> Float {
        HeightCurve.linear(c, rest: restHeight, minRatio: minHeightRatio)
    }

    func update(_ state: PressVisualState) {
        // Latched at the deepest squash (FOLD-REVIEW-3 N6): unpopped domes don't re-inflate on reopening, so the
        // reveal is at least as pressed as the sealed frame.
        lowest = min(lowest, surfaceHeight(compression: state.compression))
        if life.update(state), !cells.isEmpty {
            // Idle shimmer: the light catches one dome's crown.
            let cell = cells[Int(rng.next() % UInt64(cells.count))]
            if !cell.popped {
                BeatFX.glint(fx, at: [cell.centre.x, BubbleWrapGrid.film + cell.height, cell.centre.y], in: entity, count: 1,
                             golden: look.golden, rng: &rng)
            }
        }
        for beat in story.advance(to: state.compression) { onBeat(beat) }
        let available = max(lowest - BubbleWrapGrid.film, 0.0003)
        for cell in cells where !cell.popped {
            cell.wobble.step(toward: 0, dt: state.dt)
            apply(cell, available: available)
        }
        if let mega, !mega.popped {
            apply(mega, available: available)
        }
        // A popped dome snaps flat in ~0.12 s: the film overshoots a little wide, then settles.
        if !snapping.isEmpty {
            for k in snapping.indices {
                snapping[k].age += state.dt
                let scale = snapping[k].radius * BubbleCrater.snapScale(age: snapping[k].age)
                snapping[k].crater.scale = SIMD3(repeating: scale)
            }
            snapping.removeAll { $0.age >= BubbleCrater.snapDuration }
        }
    }

    private func apply(_ cell: Cell, available: Float) {
        // The ripple only ever squashes a dome further (never up through the plate).
        let jiggle = 1 - 0.15 * abs(clamp(cell.wobble.value, -1, 1))
        let squash = BubbleWrapGrid.squash(available: available, height: cell.height) * (1 - 0.05 * cell.strain) * jiggle
        let spread = BubbleWrapGrid.spread(squash: squash)
        cell.root.scale = SIMD3(cell.radius * spread, cell.height / BubbleWrapGrid.unitHeight * squash, cell.radius * spread)
    }

    func fracture(index: Int, isFailure: Bool, state: PressVisualState) {
        guard !popOrder.isEmpty else { return }
        let cellIndex = popOrder[index % popOrder.count]
        if let mega, BubbleWrapGrid.megaCells.contains(cellIndex) {
            // One of the mega bubble's cells: strain three times, then the big pop.
            megaStrain += 1
            mega.strain = Float(min(megaStrain, 3))
            if megaStrain >= 4 && !mega.popped { pop(mega, big: true) }
            return
        }
        guard cellIndex < cells.count else { return }
        let cell = cells[cellIndex]
        guard !cell.popped else { return }
        pop(cell, big: false)
    }

    /// The ripple: the domes round a pop (within ~1.3 pitches) jiggle, the nearest hardest.
    private func ripple(from cell: Cell, strength: Float) {
        for other in cells where !other.popped && other !== cell {
            let d = simd_length(other.centre - cell.centre)
            guard d < BubbleWrapGrid.pitch * 1.35 else { continue }
            other.wobble.kick(strength * (1.4 - d / BubbleWrapGrid.pitch) / 0.4)
        }
    }

    /// One storyboard beat (OBJECT-STORYBOARDS §1): between pops the sheet ripples and shimmers.
    private func onBeat(_ beat: StoryBeat) {
        switch beat.kind {
        case .kiss:
            for cell in cells where !cell.popped { cell.wobble.kick(10) }
            if let first = popOrder.first, first < cells.count {
                let cell = cells[first]
                BeatFX.glint(fx, at: [cell.centre.x, BubbleWrapGrid.film + cell.height, cell.centre.y], in: entity, count: 2,
                             golden: look.golden, rng: &rng)
            }
        case .ripple:
            let source = lastPopped ?? cells.first(where: { !$0.popped })
            if let source { ripple(from: source, strength: 9) }
            let open = cells.filter { !$0.popped }
            if !open.isEmpty {
                let cell = open[Int(rng.next() % UInt64(open.count))]
                cell.wobble.kick(14)
                BeatFX.glint(fx, at: [cell.centre.x, BubbleWrapGrid.film + cell.height * 0.8, cell.centre.y], in: entity, count: 1,
                             golden: look.golden, rng: &rng)
            }
        case .crease, .settle, .sheen:
            // The popped film crinkles and catches the light across the sheet.
            for _ in 0..<min(3, craters.count) {
                let crater = craters[Int(rng.next() % UInt64(craters.count))]
                let p = crater.position
                BeatFX.glint(fx, at: [p.x, p.y + 0.001, p.z], in: entity, count: 1, golden: look.golden, rng: &rng)
            }
        default:
            break
        }
    }

    private func pop(_ cell: Cell, big: Bool) {
        cell.popped = true
        cell.root.isEnabled = false
        lastPopped = cell
        ripple(from: cell, strength: big ? 24 : 16)
        if !craterMeshes.isEmpty {
            let meshes = craterMeshes[Int(rng.next() % UInt64(craterMeshes.count))]
            let crater = Entity()
            crater.addChild(ModelEntity(mesh: meshes[0], materials: [craterFilm]))
            crater.addChild(ModelEntity(mesh: meshes[1], materials: [craterCrease]))
            crater.position = [cell.centre.x, BubbleWrapGrid.film + BubbleWrapGrid.layerStep * 2, cell.centre.y]
            crater.orientation = Part.yaw(Float.random(in: 0...360, using: &rng))
            let radius = cell.radius * BubbleCrater.radius
            crater.scale = SIMD3(repeating: radius * BubbleCrater.snapScale(age: 0))
            entity.addChild(crater)
            craters.append(crater)
            snapping.append((crater: crater, radius: radius, age: 0))
        }
        let puffAt = entity.convert(position: SIMD3(cell.centre.x, BubbleWrapGrid.film + 0.003, cell.centre.y), to: fx.root)
        fx.particles.burst(.dust, count: big ? 8 : 2, at: puffAt, speed: big ? 0.12 : 0.05,
                           colors: [look.tint(UIColor(hex: 0xF4FBFE))], size: big ? 0.005...0.009 : 0.003...0.005,
                           spread: big ? 0.012 : 0.003, upBias: 0.2, life: 0.45, rng: &rng)
        if big {
            fx.particles.burst(.flake, count: 4, at: puffAt, speed: 0.15, colors: [UIColor(hex: 0xE4F3FA)],
                               size: 0.003...0.004, upBias: 0.4, rng: &rng)
        }
    }
}

/// Popped-crater numbers (multiples of the dome radius), pure so SquishTests can pin them.
enum BubbleCrater {
    /// The flattened film covers a little more than the dome's footprint (its crease ring is at `creaseRadius` 1.12).
    static let radius: Float = 1.14
    /// How high the crinkled film stands off the sheet (≈ 0.9 mm on a normal cell: flat, under the closed plates).
    static let rise: Float = 0.11
    /// The snap: 18 % wide at the pop, settled after `snapDuration`.
    static let snapOvershoot: Float = 0.18
    static let snapDuration: Float = 0.12

    static func snapScale(age: Float) -> Float {
        let t = clamp(age / snapDuration, 0, 1)
        return 1 + snapOvershoot * (1 - t) * (1 - t)
    }
}

/// The sheet's colours (FOLD-REVIEW-6: the hex sheet was invisible on the P-48: a 0.2 film and 0.36 pale domes on a
/// bright plate, and nothing opaque but the craters). Pure, so SquishTests can pin the contrast. The rule: what has to
/// read whatever the sort order (the cut edge, the crease rings, the highlights, the crater creases) is opaque; what is
/// clear stays translucent but tinted, darker at the dome's wall than at its crown.
enum BubbleWrapLook {
    static let filmTint: UInt32 = 0xC2DAE7
    static let filmOpacity: Float = 0.34
    static let sealTint: UInt32 = 0xB3D0E0
    static let sealOpacity: Float = 0.6
    /// The cut edge (opaque, unlit).
    static let cutTint: UInt32 = 0x3D7394
    static let crownTint: UInt32 = 0xD3E8F3
    static let crownOpacity: Float = 0.42
    /// The dome's lower wall: the dark refraction ring that outlines every bubble from above.
    static let rimTint: UInt32 = 0x8DB4CC
    static let rimOpacity: Float = 0.7
    /// The crease ring round each dome and the creases of a popped crater (opaque).
    static let creaseTint: UInt32 = 0x4C80A3
    static let bounceTint: UInt32 = 0xE6F4FB
    static let craterTint: UInt32 = 0xE6F1F7
    static let craterOpacity: Float = 0.8

    /// Rec. 709 luma (0…255) of a hex colour.
    static func luma(_ hex: UInt32) -> Float {
        0.2126 * Float((hex >> 16) & 0xFF) + 0.7152 * Float((hex >> 8) & 0xFF) + 0.0722 * Float(hex & 0xFF)
    }
}

/// The sheet's layout, dome shape and the press's pressure map (FOLD-REVIEW-5 N10). Pure and deterministic, so the
/// platen's print can mirror it (`FoldStamps` should take `centre(_:)`, `radius` and `popOrder(seed:)` from here) and
/// SquishTests can pin it.
enum BubbleWrapGrid {
    static let columns = BubbleWrapLayout.columns
    static let rows = BubbleWrapLayout.rows
    static let count = BubbleWrapLayout.count
    /// Centre-to-centre distance between every pair of neighbours (hex packing).
    static let pitch: Float = 0.0196
    /// Column spacing along x: pitch · √3/2.
    static let columnPitch: Float = 0.0196 * 0.866_025_4
    static let radius: Float = 0.0080
    static let domeHeight: Float = 0.0070
    static let film: Float = 0.0008
    static let sheetSize = SIMD2<Float>(0.110, 0.090)
    static let sheetCorner: Float = 0.006
    /// Height step between the sheet's flat layers (dome feet, craters, seal, cut line) so none z-fights the film.
    static let layerStep: Float = 0.00007
    /// The milky heat-sealed margin and the crisp cut line along the sheet's edge.
    static let sealWidth: Float = 0.0032
    static let cutWidth: Float = 0.0011
    /// The mega bubble: the four centre cells (columns 2–3, rows 1–2) as one dome 2× as wide, 1.6× as tall.
    static let megaCells: Set<Int> = [1 * 6 + 2, 1 * 6 + 3, 2 * 6 + 2, 2 * 6 + 3]
    static let megaScale: Float = 2.0
    static let megaHeightScale: Float = 1.6
    /// The last dome to pop stands this much lower than the first (it is contacted later, as in a real sheet).
    static let heightSpread: Float = 0.10
    static let craterVariants = 3

    /// Cell `row · columns + column`'s centre (x, z) on the sheet, metres. Odd columns sit half a cell toward +z.
    static func centre(_ cell: Int) -> SIMD2<Float> {
        let column = cell % columns, row = cell / columns
        let x = columnPitch * (Float(column) - Float(columns - 1) / 2)
        let stagger: Float = column % 2 == 0 ? -0.25 : 0.25
        let z = pitch * (Float(row) - Float(rows - 1) / 2 + stagger)
        return SIMD2(x, z)
    }

    /// The press's pressure map: how early the plates bite on each cell, 0…1. A ripple from the front rows (+z,
    /// toward the eye on both presses) to the back, loosened by a seeded per-cell jitter so each press pops its own way.
    static func pressure(_ cell: Int, seed: UInt64) -> Float {
        let zMax = pitch * (Float(rows - 1) / 2 + 0.25)
        let front = (centre(cell).y + zMax) / (2 * zMax)
        var rng = SplitMix64(seed: (seed ^ 0xB0BB1E) &+ UInt64(cell + 1) &* 0x9E37_79B9_7F4A_7C15)
        let jitter = Float(rng.next() >> 40) / Float(1 << 24)
        return 0.7 * front + 0.3 * jitter
    }

    /// Fracture index → cell: highest pressure first (the fracture thresholds are ascending in compression).
    static func popOrder(seed: UInt64) -> [Int] {
        let p = (0..<count).map { pressure($0, seed: seed) }
        return (0..<count).sorted { p[$0] != p[$1] ? p[$0] > p[$1] : $0 < $1 }
    }

    /// Cell → its place in `order`.
    static func ranks(_ order: [Int]) -> [Int] {
        var result = [Int](repeating: count - 1, count: count)
        for (rank, cell) in order.enumerated() where cell >= 0 && cell < count { result[cell] = rank }
        return result
    }

    /// A dome's height relative to `domeHeight`: the first to pop is the tallest.
    static func heightScale(rank: Int) -> Float {
        1 - heightSpread * Float(clamp(rank, 0, count - 1)) / Float(count - 1)
    }

    /// Height ratio of a dome `height` tall under a plate `available` above the film.
    static func squash(available: Float, height: Float) -> Float {
        clamp(available / max(height, 1e-5), 0, 1)
    }

    /// The bulge as it squashes; capped so squashed neighbours only just meet (pitch / 2r = 1.225).
    static func spread(squash: Float) -> Float {
        1 + 0.22 * (1 - clamp(squash, 0, 1))
    }

    // MARK: Meshes (unit dome radius)

    /// The unit dome's height (`domeHeight / radius`).
    static var unitHeight: Float { domeHeight / radius }

    /// Outer radius of the crease ring (the flared foot), in dome radii: 1.12 (was 1.08, a hairline from above).
    static let creaseRadius: Float = 1.12
    /// Wall bands (above the foot) drawn in the darker "refraction" rim slot: the steep lower ~half of the wall.
    static let rimBands = 5
    /// Height of the flared foot, in dome radii.
    static let footHeight: Float = 0.09

    /// The dome profile (radius, y), base → apex: a flared foot where the bubble is moulded out of the film (the crease
    /// ring, slot 1), then a steep wall (its lower part the rim, slot 2) and a full, slightly flattened crown (slot 0).
    static var domeProfile: [SIMD2<Float>] {
        let h = unitHeight, foot = footHeight
        var profile: [SIMD2<Float>] = [SIMD2(creaseRadius, 0), SIMD2(1.05, foot * 0.4), SIMD2(1.0, foot)]
        for k in 1...14 {
            let t = Float.pi / 2 * Float(k) / 14
            let r = pow(max(cos(t), 0), 0.85)
            profile.append(SIMD2(k == 14 ? 0 : r, foot + (h - foot) * sin(t)))
        }
        return profile
    }

    /// The material slot of lathe band `band` of the dome: 1 the two foot bands, 2 the lower wall, 0 the crown.
    static func domeSlot(band: Int) -> UInt8 {
        if band < 2 { return 1 }
        return band < 2 + rimBands ? 2 : 0
    }

    /// Open at the base (it sits on the film). Slot 1: the crease foot; slot 2: the dark lower wall; slot 0: the crown.
    static func domeMesh() -> MeshData {
        MeshKit.lathe(profile: domeProfile, segments: 32, material: { (band: Int) -> UInt8 in Self.domeSlot(band: band) })
    }

    /// A highlight lying on the unit dome's surface at profile parameter `t` (0 foot … π/2 apex), toward `direction`
    /// (x, z), `size` dome radii long.
    static func highlight(t: Float, direction: SIMD2<Float>, size: Float)
        -> (position: SIMD3<Float>, normal: SIMD3<Float>, size: Float) {
        let h = unitHeight, foot = footHeight
        let r = pow(cos(t), 0.85)
        let y = foot + (h - foot) * sin(t)
        let dir = simd_normalize(direction)
        // The surface normal there (from the profile's slope), tilted toward `dir`.
        let dr = -0.85 * pow(cos(t), -0.15) * sin(t), dy = (h - foot) * cos(t)
        let n2 = simd_normalize(SIMD2<Float>(dy, -dr))
        let normal = simd_normalize(SIMD3<Float>(n2.x * dir.x, n2.y, n2.x * dir.y))
        let position = SIMD3<Float>(dir.x * r, y, dir.y * r) + normal * 0.02
        return (position, normal, size)
    }

    /// The key glint: up-left toward the key (−x, −z), high on the crown (FOLD-REVIEW-6: 0.24, was 0.2 and translucent).
    static var glint: (position: SIMD3<Float>, normal: SIMD3<Float>, size: Float) {
        highlight(t: 1.0, direction: SIMD2(-0.72, -0.69), size: 0.24)
    }

    /// The small bounce glint low on the far side (+x, +z), where the plate's light comes back through the bubble.
    static var bounceGlint: (position: SIMD3<Float>, normal: SIMD3<Float>, size: Float) {
        highlight(t: 0.42, direction: SIMD2(0.75, 0.66), size: 0.12)
    }

    /// A flat, top-facing band `inset` wide inside the rounded rectangle `size` (x, z) with corner radius `corner`.
    static func ring(size: SIMD2<Float>, corner: Float, inset: Float, cornerSteps: Int = 6) -> MeshData {
        let half = size / 2
        let r = min(corner, min(half.x, half.y))
        let inner = max(r - inset, 0)
        let centres: [SIMD2<Float>] = [SIMD2(half.x - r, half.y - r), SIMD2(-(half.x - r), half.y - r),
                                       SIMD2(-(half.x - r), -(half.y - r)), SIMD2(half.x - r, -(half.y - r))]
        var mesh = MeshData()
        var outerRing: [Int] = [], innerRing: [Int] = []
        let up = SIMD3<Float>(0, 1, 0)
        for (k, c) in centres.enumerated() {
            for step in 0...cornerSteps {
                let a = Float.pi / 2 * (Float(k) + Float(step) / Float(cornerSteps))
                let d = SIMD2<Float>(cos(a), sin(a))
                let o = c + d * r, i = c + d * inner
                outerRing.append(mesh.addVertex(SIMD3(o.x, 0, o.y), up))
                innerRing.append(mesh.addVertex(SIMD3(i.x, 0, i.y), up))
            }
        }
        let n = outerRing.count
        for j in 0..<n {
            let j1 = (j + 1) % n
            mesh.addTriangle(innerRing[j], outerRing[j], outerRing[j1])
            mesh.addTriangle(innerRing[j], outerRing[j1], innerRing[j1])
        }
        mesh.orientToNormals()
        return mesh
    }

    /// A popped crater (unit radius): the collapsed film lying crinkled on the sheet, a little raised in the middle,
    /// with seeded curving radial creases and a ragged rim (both slot 1) over stress-whitened film (slot 0).
    static func craterMesh(seed: UInt64, segments: Int = 40) -> MeshData {
        var rng = SplitMix64(seed: seed)
        let folds = Float(3 + Int(rng.next() % 2))
        let phase = Float.random(in: 0...(2 * .pi), using: &rng)
        let twist = Float.random(in: -0.8...0.8, using: &rng)
        var wobble: [(k: Float, amp: Float, phase: Float)] = []
        for k: Float in [3, 5, 7] {
            let amp = Float.random(in: 0.02...0.06, using: &rng)
            let wobblePhase = Float.random(in: 0...(2 * .pi), using: &rng)
            wobble.append((k: k, amp: amp, phase: wobblePhase))
        }
        let radii: [Float] = [0.25, 0.5, 0.72, 0.9, 1.0]
        func ridge(_ theta: Float, _ rho: Float) -> Float {
            abs(sin(folds * (theta + twist * rho) + phase))
        }
        func rim(_ theta: Float) -> Float {
            wobble.reduce(1) { $0 + $1.amp * sin($1.k * theta + $1.phase) }
        }
        var mesh = MeshData()
        let up = SIMD3<Float>(0, 1, 0)
        let centre = mesh.addVertex(SIMD3(0, BubbleCrater.rise * 0.55, 0), up)
        var rings: [[Int]] = []
        for rho in radii {
            var ring: [Int] = []
            for j in 0..<segments {
                let theta = Float(j) / Float(segments) * 2 * .pi
                let crinkle = 0.6 * ridge(theta, rho) + 0.4 * Float.random(in: 0...1, using: &rng)
                let y = BubbleCrater.rise * (0.4 + 0.6 * crinkle * pow(rho, 0.7)) * (1 - pow(rho, 6))
                let rr = rho * (rho > 0.8 ? rim(theta) : 1)
                ring.append(mesh.addVertex(SIMD3(cos(theta) * rr, y, sin(theta) * rr), up))
            }
            rings.append(ring)
        }
        let creaseLevel: Float = 0.93
        for j in 0..<segments {
            let j1 = (j + 1) % segments
            let mid = (Float(j) + 0.5) / Float(segments) * 2 * .pi
            let slot: UInt8 = ridge(mid, radii[0] / 2) > creaseLevel ? 1 : 0
            mesh.addTriangle(centre, rings[0][j], rings[0][j1], material: slot)
        }
        for b in 0..<(radii.count - 1) {
            let rho = (radii[b] + radii[b + 1]) / 2
            for j in 0..<segments {
                let j1 = (j + 1) % segments
                let mid = (Float(j) + 0.5) / Float(segments) * 2 * .pi
                let isRim = b == radii.count - 2
                let slot: UInt8 = isRim || (rho < 0.9 && ridge(mid, rho) > creaseLevel) ? 1 : 0
                let lower = rings[b], upper = rings[b + 1]
                mesh.addTriangle(lower[j], upper[j], upper[j1], material: slot)
                mesh.addTriangle(lower[j], upper[j1], lower[j1], material: slot)
            }
        }
        // Wind every triangle up (from the analytic up normals), then shade the crinkle from the real facets.
        mesh.orientToNormals()
        mesh.recomputeNormals()
        return mesh
    }
}
