import Foundation
import RealityKit
import simd
import UIKit

/// Crayon Box (EXPERIENCE-PLAN §7, OBJECT-STORYBOARDS §4; was a single crayon, bible §4 #4): an open cardboard tray of
/// seven wax crayons in rainbow order, four on the bottom and three nested in the grooves on top, so from above it
/// reads as a rainbow. Every crayon is pre-split at a seeded point into two lathe pieces with a printed paper wrap and
/// fresh-wax core discs on the cut faces (raspberry for the `secondColourCore` surprise).
///
/// The press, top-down first (founder P0: the old crayon still looked intact after the press, because it only
/// flattened to half its thickness and, seen from above, a flattened crayon is still a crayon):
///  • strain: the tray's walls lean out and crease, the top crayons bow one by one (sideways, so it shows from
///    above), stress rings whiten at the bend;
///  • fracture 0 (failure, ~0.30): the top row SNAPs, each crayon's halves kink apart with a gap and wax flakes;
///  • the walls fold flat; the bottom row bows; fracture 1 (~0.52): the bottom row snaps;
///  • every crayon is crushed into a wide, flat waxy slab (≤ 22 % of the box's height, up to 2.4× its width), and
///    seven colour lanes smear out under them; fracture 2 (~0.74) crumbles them into a rainbow smear that runs out of
///    the flattened box.
/// No rigid debris: the pieces are posed analytically (`CrayonBox`), so the crushed box is identical on the Fold Press
/// and the P-48 and never rises back.
@MainActor
final class CrayonView: PressObjectView {
    let entity = Entity()
    /// Half the box's rest height (kept as `radius`: SpecimenPrint mirrors `2 × CrayonView.radius`, CollectionTests
    /// checks it). The crayons' own radius is `CrayonBox.crayonRadius`.
    static let radius: Float = 0.016
    let restHeight: Float = 2 * CrayonView.radius
    let footprint: Float = 0.060
    private static var wrapperTextures: [UInt32: TextureResource] = [:]

    private let fx: SceneFX
    private let look: Look
    private var rng = SplitMix64(seed: 0)
    private let life: ObjectLife
    private var story: StoryCursor
    private let thresholds: [Float]
    private var failedTop = false
    private var failedBottom = false
    private var crumbled = false
    private var crumbleC: Float = 1
    private var spread: Float = 1

    @MainActor
    private final class Crayon {
        let index: Int
        let top: Bool
        let colour: UIColor
        let node = Entity()
        let lay = Entity()
        let pieceA = Entity()
        let pieceB = Entity()
        var ring: ModelEntity?
        let rest: SIMD3<Float>
        let cut: Float
        /// Bow (horizontal), sag (vertical) and their eased values; the snap's kink spring and separation.
        var bowTarget: Float = 0
        var bow: Float = 0
        var broken = false
        var kink = JiggleSpring(value: 0, velocity: 0, omega: 30, zeta: 0.35)
        var kinkSide: Float = 1
        var separation: Float = 0
        var smear: ModelEntity?
        init(index: Int, top: Bool, colour: UIColor, rest: SIMD3<Float>, cut: Float) {
            self.index = index
            self.top = top
            self.colour = colour
            self.rest = rest
            self.cut = cut
        }
    }
    private var crayons: [Crayon] = []
    /// Box walls: (model pivot, outward direction in the box plane, target and eased fold angle).
    private var walls: [(pivot: Entity, height: Float, fold: Float, target: Float)] = []
    private var wallCreases: [ModelEntity] = []
    private var smearT: Float = 0
    private var smearSteps: Float = 0
    private var smearing = false
    private var smearC: Float = 1

    var shadowSpread: Float { spread }

    init(variant: PressVariant, fx: SceneFX) {
        self.fx = fx
        let look = Look(variant)
        self.look = look
        rng = SplitMix64(seed: variant.seed ^ 0xC4A7)
        life = ObjectLife(seed: variant.seed, idle: .still, amount: 0, rate: 0.3, pulseHz: 6, pulseDamping: 0.45)
        story = StoryCursor(.crayon, seed: variant.seed)
        thresholds = PressObjectFactory.thresholds(.crayon, variant: variant)
        build(variant: variant)
    }

    // MARK: Build

    private func build(variant: PressVariant) {
        let golden = look.golden
        let box = look.body(UIColor(hex: CrayonBox.boxTint), roughness: 0.78, clearcoat: 0.05)
        let boxInside = look.body(UIColor(hex: CrayonBox.boxInsideTint), roughness: 0.85, clearcoat: 0)
        let stripe = golden ? SceneMaterials.pbr(UIColor(hex: 0x8A5A00), roughness: 0.4, metallic: 1)
            : SceneMaterials.pbr(UIColor(hex: CrayonBox.stripeTint), roughness: 0.7)
        let size = CrayonBox.trayInner
        let t = CrayonBox.wallThickness
        // The tray floor.
        Part.add(cached: "crayonbox.floor", {
            MeshKit.roundedBox([size.x + 2 * t, CrayonBox.floor, size.y + 2 * t], radius: 0.0008, bevel: 0.0003)
        }, boxInside, at: [0, CrayonBox.floor / 2, 0], to: life.node)
        // Four walls, each on a pivot at its bottom outer edge so it can fold out flat.
        let wallH = CrayonBox.wallHeight
        let specs: [(position: SIMD3<Float>, yaw: Float, length: Float)] = [
            ([0, CrayonBox.floor, size.y / 2 + t], 0, size.x + 2 * t),          // front (+z)
            ([0, CrayonBox.floor, -(size.y / 2 + t)], .pi, size.x + 2 * t),     // back (−z)
            ([size.x / 2 + t, CrayonBox.floor, 0], .pi / 2, size.y),           // tip end (+x)
            ([-(size.x / 2 + t), CrayonBox.floor, 0], -.pi / 2, size.y),         // base end (−x)
        ]
        for (k, spec) in specs.enumerated() {
            let pivot = Entity()
            pivot.position = spec.position
            // Local +Z points outward from the box for every wall.
            pivot.orientation = simd_quatf(angle: spec.yaw, axis: [0, 1, 0])
            Part.add(cached: "crayonbox.wall.\(k < 2 ? "long" : "end")", {
                MeshKit.roundedBox([spec.length, wallH, t], radius: 0.0005, bevel: 0.0002)
            }, box, at: [0, wallH / 2, -t / 2], to: pivot)
            if k < 2 {
                // A printed green band round the outside of the long walls.
                Part.add(cached: "crayonbox.stripe", { MeshKit.roundedBox([spec.length * 0.98, wallH * 0.28, 0.0003], radius: 0.0001) },
                         stripe, at: [0, wallH * 0.55, 0.00025], to: pivot)
                // A crease, hidden until the wall strains.
                let crease = Part.add(cached: "crayonbox.crease", { MeshKit.roundedBox([0.0007, wallH * 0.9, 0.0004], radius: 0.0001) },
                                      SceneMaterials.pbr(UIColor(hex: 0x9C6B12), roughness: 0.8),
                                      at: [Float.random(in: -0.02...0.02, using: &rng), wallH * 0.5, 0.0004], to: pivot)
                crease.orientation = simd_quatf(angle: Float.random(in: -0.35...0.35, using: &rng), axis: [0, 0, 1])
                crease.isEnabled = false
                wallCreases.append(crease)
            }
            life.node.addChild(pivot)
            walls.append((pivot, wallH, 0, 0))
        }

        // The crayons: rainbow order across the tray (bottom, top, bottom, …).
        let colours = golden ? [UIColor](repeating: Palette.gold, count: 7) : CrayonBox.colours
        let coreOverride: UIColor? = variant.surprise == .secondColourCore ? Palette.raspberry : nil
        for slot in 0..<7 {
            let top = slot % 2 == 1
            let z = CrayonBox.laneZ(slot)
            let y = top ? CrayonBox.topCentreY(sb: 1, st: 1) : CrayonBox.bottomCentreY(sb: 1)
            let x = Float.random(in: -0.003...0.003, using: &rng) + (top ? 0.003 : 0)
            let cutIndex = Int(rng.next() % UInt64(CrayonBox.cuts.count))
            let crayon = Crayon(index: slot, top: top, colour: colours[slot], rest: [x, y, z], cut: CrayonBox.cuts[cutIndex])
            buildCrayon(crayon, cutIndex: cutIndex, core: coreOverride)
            crayons.append(crayon)
        }
        entity.addChild(life.node)
        entity.orientation = Part.yaw(-14)
    }

    private func buildCrayon(_ crayon: Crayon, cutIndex: Int, core: UIColor?) {
        let golden = look.golden
        let wax = golden ? SceneMaterials.gold
            : SceneMaterials.enamel(crayon.colour, roughness: 0.5, clearcoat: 0.25, clearcoatRoughness: 0.4)
        let coreMaterial = SceneMaterials.pbr(core ?? CrayonBox.lighter(crayon.colour), roughness: 0.45)
        let paper: PhysicallyBasedMaterial
        let hex = CrayonBox.hex(crayon.colour)
        if !golden, let texture = Self.wrapperTextures[hex] {
            paper = SceneMaterials.textured(texture, roughness: 0.8)
        } else {
            paper = golden ? SceneMaterials.pbr(UIColor(hex: 0x8A5A00), roughness: 0.5)
                : SceneMaterials.pbr(CrayonBox.lighter(crayon.colour), roughness: 0.8)
        }
        let length = CrayonBox.length
        let cut = crayon.cut * length
        crayon.node.position = crayon.rest
        // Lathe +Y → +X, axial 0 at the base end.
        crayon.lay.orientation = simd_quatf(angle: -.pi / 2, axis: [0, 0, 1])
        crayon.lay.position = [-length / 2, 0, 0]
        crayon.node.addChild(crayon.lay)
        var wrappers: [ModelEntity] = []
        var waxModels: [ModelEntity] = []
        for (part, piece) in [crayon.pieceA, crayon.pieceB].enumerated() {
            piece.position = [0, cut, 0]
            crayon.lay.addChild(piece)
            let range: ClosedRange<Float> = part == 0 ? 0...cut : cut...length
            waxModels.append(Part.add(cached: "crayonbox.piece.\(cutIndex).\(part)", {
                CrayonBox.pieceMesh(range).translated([0, -cut, 0])
            }, wax, to: piece))
            // The fresh-wax core on the cut face.
            Part.add(cached: "crayonbox.core", {
                MeshKit.roundedCylinder(radius: CrayonBox.crayonRadius * 0.55, height: 0.0005, bevel: 0.0002, segments: 24)
            }, coreMaterial, at: [0, part == 0 ? -0.0006 : 0.0001, 0], to: piece)
            let lo = max(range.lowerBound, CrayonBox.wrapperRange.lowerBound), hi = min(range.upperBound, CrayonBox.wrapperRange.upperBound)
            if hi - lo > 0.001 {
                let wrapper = Part.add(cached: "crayonbox.wrap.\(cutIndex).\(part)", {
                    let r = CrayonBox.crayonRadius * 1.035
                    return MeshKit.latheUV(profile: [SIMD2(r, lo), SIMD2(r, (lo + hi) / 2), SIMD2(r, hi)], segments: 40,
                                           vRange: CrayonBox.wrapperRange).translated([0, -cut, 0])
                }, paper, to: piece)
                wrappers.append(wrapper)
            }
        }
        // The stress ring at the bend (stress whitening), hidden until the tell.
        let ring = Part.add(cached: "crayonbox.ring", {
            MeshKit.torus(major: CrayonBox.crayonRadius * 1.02, minor: 0.0007, segments: 32, sides: 8)
        }, SceneMaterials.pbr(UIColor(hex: 0xFFFBF4), roughness: 0.6), at: [0, cut, 0], to: crayon.lay)
        ring.isEnabled = false
        crayon.ring = ring
        life.node.addChild(crayon.node)
        if !golden {
            // Wax detail (fidelity pass): fine streaks along the crayon under a soft sheen.
            let colour = crayon.colour
            let models = waxModels
            Task { @MainActor in
                guard let normal = await SurfaceDetail.waxNormal() else { return }
                var material = SceneMaterials.enamel(colour, roughness: 0.52, clearcoat: 0.25, clearcoatRoughness: 0.45)
                material.normal = .init(texture: .init(normal))
                for model in models { model.model?.materials = [material] }
            }
        }
        if !golden && Self.wrapperTextures[hex] == nil {
            let band = crayon.colour
            let wrapped = wrappers
            Task { @MainActor [weak self] in
                guard let texture = await Self.wrapper(band: band, hex: hex), self != nil else { return }
                let material = SceneMaterials.textured(texture, roughness: 0.8)
                for model in wrapped { model.model?.materials = [material] }
            }
        }
    }

    /// The WAXO wrap printed in one crayon's colour (drawn once per colour, 256² so seven stay cheap).
    private static func wrapper(band: UIColor, hex: UInt32) async -> TextureResource? {
        if let cached = wrapperTextures[hex] { return cached }
        let texture = await StudioEnvironment.textureAsync(RigTextures.crayonWrapper(band: band, width: 256, height: 256),
                                                           name: "crayonbox.wrap.\(hex)")
        wrapperTextures[hex] = texture
        return texture
    }

    // MARK: Press

    func surfaceHeight(compression c: Float) -> Float {
        let f1 = thresholds.first ?? 0.3
        let f2 = thresholds.count > 1 ? thresholds[1] : 0.52
        let rows = CrayonBox.rows(compression: c, f1: f1, f2: f2, failedTop: failedTop, failedBottom: failedBottom)
        if !failedTop { return restHeight * (1 - 0.04 * min(c / max(f1, 0.01), 1)) }
        return CrayonBox.stackTop(sb: rows.sb, st: rows.st)
    }

    func update(_ state: PressVisualState) {
        if life.update(state), let crayon = crayons.randomElement(using: &rng) {
            BeatFX.glint(fx, at: crayon.rest + SIMD3(Float.random(in: -0.03...0.03, using: &rng), CrayonBox.crayonRadius, 0),
                         in: entity, count: 1, golden: look.golden, rng: &rng)
        }
        for beat in story.advance(to: state.compression) { onBeat(beat, state: state) }
        let c = state.compression
        let f1 = thresholds.first ?? 0.3
        let f2 = thresholds.count > 1 ? thresholds[1] : 0.52
        let rows = CrayonBox.rows(compression: c, f1: f1, f2: f2, failedTop: failedTop, failedBottom: failedBottom)
        let dt = state.dt
        for crayon in crayons {
            crayon.bow = state.reduceMotion ? crayon.bowTarget : Deform.approach(crayon.bow, crayon.bowTarget, halfLife: 0.06, dt: dt)
            crayon.kink.step(toward: 0, dt: dt)
            let f = crayon.top ? rows.st : rows.sb
            let y = crayon.top ? CrayonBox.topCentreY(sb: rows.sb, st: rows.st) : CrayonBox.bottomCentreY(sb: rows.sb)
            crayon.node.position = SIMD3(crayon.rest.x, y, crayon.rest.z)
            crayon.node.scale = CrayonBox.slabScale(flatten: f)
            // Bow sideways (shows from above) and sag; once broken, the halves kink apart with a gap.
            let kink = crayon.broken ? CrayonBox.snapKink + 0.25 * crayon.kink.value : 0
            let yaw = (crayon.bow + kink) * crayon.kinkSide
            let sag = crayon.broken ? 0.02 * f : crayon.bow * 0.5
            let separation = crayon.broken ? CrayonBox.snapGap : 0
            let cut = crayon.cut * CrayonBox.length
            crayon.pieceA.position = [0, cut - separation, 0]
            crayon.pieceB.position = [0, cut + separation, 0]
            crayon.pieceA.orientation = simd_quatf(angle: -yaw, axis: [1, 0, 0]) * simd_quatf(angle: -sag, axis: [0, 0, 1])
            crayon.pieceB.orientation = simd_quatf(angle: yaw, axis: [1, 0, 0]) * simd_quatf(angle: sag, axis: [0, 0, 1])
        }
        // Walls lean, fold flat, and are squashed under the plate wherever they still stand.
        let room = max(surfaceHeight(compression: c) - CrayonBox.floor, 0.0005)
        for i in walls.indices {
            walls[i].fold = state.reduceMotion ? walls[i].target : Deform.approach(walls[i].fold, walls[i].target, halfLife: 0.08, dt: dt)
            let fold = walls[i].fold
            // Height above the floor of a wall leaning out by `fold`: h·cos(fold). Squash it under the plate.
            let standing = max(walls[i].height * cos(fold), 0.0005)
            let squash = min(1, room / standing)
            walls[i].pivot.orientation = CrayonBox.wallYaw(i) * simd_quatf(angle: fold, axis: [1, 0, 0])
            walls[i].pivot.scale = [1, squash, 1]
        }
        // The smear lanes (latched): they spread wider and run longer.
        if smearing {
            let t = clamp((c - smearC) / max(1 - smearC, 0.05), 0, 1)
            smearT = max(smearT, min(t + 0.12 * smearSteps, 1))
            for crayon in crayons {
                guard let smear = crayon.smear else { continue }
                let s = CrayonBox.smearSize(smearT, crumbled: crumbled)
                smear.scale = SIMD3(s.x, 0.0004, s.y)
            }
        }
        spread = 1 + 0.4 * (1 - rows.sb) + (smearing ? 0.3 * smearT : 0)
    }

    func handle(_ event: PressEvent, state: PressVisualState) {
        if event == .preFailureTell { life.tremor(0.3, level: 0.6) }
    }

    private func bend(_ crayon: Crayon, amount: Float) {
        guard !crayon.broken else { return }
        crayon.bowTarget = max(crayon.bowTarget, amount)
    }

    private func snap(top: Bool) {
        let m = max(fx.motionScale, 0.3)
        for crayon in crayons where crayon.top == top && !crayon.broken {
            crayon.broken = true
            crayon.bowTarget = 0
            crayon.kinkSide = rng.next() % 2 == 0 ? 1 : -1
            crayon.kink.kick(6 * m)
            crayon.ring?.isEnabled = false
            let at = crayon.node.convert(position: [crayon.cut * CrayonBox.length - CrayonBox.length / 2, CrayonBox.crayonRadius, 0],
                                         to: fx.root)
            fx.particles.burst(.flake, count: 3, at: at, speed: 0.25 * m,
                               colors: look.golden ? [Palette.gold] : [crayon.colour, CrayonBox.lighter(crayon.colour)],
                               size: 0.0018...0.0032, spread: 0.004, upBias: 0.45, rng: &rng)
        }
        life.kick(1.2)
    }

    private func startSmear(_ c: Float) {
        guard !smearing else {
            smearSteps += 1
            return
        }
        smearing = true
        smearC = c
        for (i, crayon) in crayons.enumerated() {
            let material = look.golden ? SceneMaterials.goldMess
                : SceneMaterials.enamel(crayon.colour, roughness: 0.45, clearcoat: 0.35, clearcoatRoughness: 0.35)
            let smear = Part.add(cached: "crayonbox.smear.\(i % 3)", {
                MeshKit.spreadDisc(seed: 0x5EA &+ UInt64(i % 3) &* 977, height: 1, segments: 40, wobble: 0.2)
            }, material, at: [crayon.rest.x, CrayonBox.floor + 0.0002 + 0.00004 * Float(i), crayon.rest.z], to: life.node)
            smear.scale = SIMD3(repeating: 0.0001)
            ShadowCasting.off(smear)
            crayon.smear = smear
        }
    }

    /// One storyboard beat (OBJECT-STORYBOARDS §4).
    private func onBeat(_ beat: StoryBeat, state: PressVisualState) {
        let c = state.compression
        switch beat.kind {
        case .kiss:
            life.kick(0.4)
        case .squash:
            // The tray's walls lean out under the load.
            for i in walls.indices { walls[i].target = max(walls[i].target, CrayonBox.lean) }
            life.kick(0.3)
        case .crease:
            for crease in wallCreases { crease.isEnabled = true }
            for i in walls.indices { walls[i].target = max(walls[i].target, CrayonBox.lean * 1.8) }
        case .bend:
            let candidates = crayons.filter { !$0.broken && $0.bowTarget == 0 && $0.top == !failedTop }
            let pick = candidates.isEmpty ? crayons.filter { !$0.broken } : candidates
            let take = failedTop ? 2 : 1
            for crayon in pick.prefix(take) { bend(crayon, amount: CrayonBox.bowAmount) }
            life.kick(0.3)
        case .tell, .strain:
            for crayon in crayons where crayon.bowTarget > 0 && !crayon.broken {
                crayon.ring?.isEnabled = true
                crayon.bowTarget = min(crayon.bowTarget * 1.4, CrayonBox.bowAmount * 1.8)
            }
            life.tremor(0.3, level: 0.6)
        case .fold:
            // Front first, then the ends, then the back.
            let order: [[Int]] = [[0], [2, 3], [1]]
            let which = order[min(beat.ordinal, order.count - 1)]
            for i in which where i < walls.count { walls[i].target = CrayonBox.folded }
            life.kick(0.4)
        case .chip:
            if let crayon = crayons.filter({ $0.broken }).randomElement(using: &rng) {
                let at = crayon.node.convert(position: [crayon.cut * CrayonBox.length - CrayonBox.length / 2, 0.004, 0], to: fx.root)
                fx.particles.burst(.flake, count: 3, at: at, speed: 0.12, colors: Palette.rainbow, size: 0.0015...0.003,
                                   spread: 0.01, upBias: 0.4, rng: &rng)
            }
        case .smear:
            startSmear(c)
        case .settle:
            BeatFX.glint(fx, at: [0, 0.006, 0], in: entity, count: 2, golden: look.golden, rng: &rng)
        default:
            life.kick(0.3)
        }
    }

    func fracture(index: Int, isFailure: Bool, state: PressVisualState) {
        switch index {
        case 0:
            failedTop = true
            snap(top: true)
            for i in walls.indices { walls[i].target = max(walls[i].target, CrayonBox.lean * 2.5) }
        case 1:
            failedBottom = true
            snap(top: false)
            // Whatever wall still stands goes flat now.
            for i in walls.indices { walls[i].target = CrayonBox.folded }
        default:
            // The crumble: the lanes run out of the box into a rainbow smear; rainbow flakes everywhere.
            crumbled = true
            crumbleC = state.compression
            startSmear(state.compression)
            smearSteps += 1
            fx.particles.burst(.flake, count: 12, at: entity.convert(position: [0, 0.008, 0], to: fx.root),
                               speed: 0.3 * max(fx.motionScale, 0.3), colors: look.golden ? [Palette.gold] : Palette.rainbow,
                               size: 0.002...0.0035, spread: 0.03, upBias: 0.35, rng: &rng)
            life.kick(0.8)
        }
    }
}

/// The Crayon Box's layout and crush (OBJECT-STORYBOARDS §4), pure so SquishTests can pin it. Metres, box-local.
enum CrayonBox {
    /// Tray floor thickness.
    static let floor: Float = 0.0012
    /// Seven crayons in two nested rows: the top surface sits exactly at the box's rest height (2 × 0.016).
    static let crayonDiameter: Float = (0.032 - floor) / (1 + 0.866_025_4)
    static var crayonRadius: Float { crayonDiameter / 2 }
    static let length: Float = 0.090
    static let wallThickness: Float = 0.0012
    /// The tray walls stand a little over the bottom row.
    static var wallHeight: Float { crayonDiameter * 1.1 }
    /// Inner size (x along the crayons, z across).
    static var trayInner: SIMD2<Float> { SIMD2(length + 0.008, 4 * crayonDiameter + 0.003) }
    static let boxTint: UInt32 = 0xFFC83A
    static let boxInsideTint: UInt32 = 0xEDB84A
    static let stripeTint: UInt32 = 0x2E8B45
    /// Rainbow order across the tray: bottom, top, bottom, top, bottom, top, bottom.
    static let colours: [UIColor] = [Palette.raspberry, Palette.tangerine, Palette.lemon, Palette.lime, Palette.aqua,
                                     Palette.cobalt, Palette.grape]
    /// The seeded split points (share of the length); quantised so the piece meshes are shared.
    static let cuts: [Float] = [0.40, 0.45, 0.50, 0.55, 0.60]
    static var wrapperRange: ClosedRange<Float> { (0.08 * length)...(0.72 * length) }
    /// The bow before a snap (radians, sideways), the snap's kink and gap, the walls' lean and folded angle.
    static let bowAmount: Float = 0.05
    static let snapKink: Float = 0.16
    static let snapGap: Float = 0.0022
    static let lean: Float = 0.08
    static let folded: Float = 1.45
    /// The crushed slab: never thinner than this share of a crayon, never wider than `maxWiden`.
    static let minTop: Float = 0.16
    static let minBottom: Float = 0.22
    static let maxWiden: Float = 2.4

    /// Lane `slot` (0…6) across the tray: bottom crayons on even slots, top ones nested between them.
    static func laneZ(_ slot: Int) -> Float {
        (Float(slot) - 3) * crayonDiameter * 0.5
    }

    static func bottomCentreY(sb: Float) -> Float {
        floor + crayonDiameter * sb / 2
    }

    static func topCentreY(sb: Float, st: Float) -> Float {
        floor + crayonDiameter * sb + crayonDiameter * st * (0.866_025_4 - 0.5)
    }

    /// The stack's top (the plate's height) for the rows' flatten factors.
    static func stackTop(sb: Float, st: Float) -> Float {
        floor + crayonDiameter * sb + 0.866_025_4 * crayonDiameter * st
    }

    /// The rows' flatten factors (1 = round): the snapped top row gives first, then the bottom row; both end flat.
    static func rows(compression c: Float, f1: Float, f2: Float, failedTop: Bool, failedBottom: Bool) -> (sb: Float, st: Float) {
        guard failedTop else { return (1, 1) }
        if !failedBottom {
            let t = clamp((c - f1) / max(f2 - f1, 0.02), 0, 1)
            return (1, 0.55 + (0.30 - 0.55) * t)
        }
        let t = clamp((c - f2) / max(1 - f2, 0.02), 0, 1)
        return (0.6 + (minBottom - 0.6) * t, 0.30 + (minTop - 0.30) * t)
    }

    /// A crayon slab's scale for flatten `f`: thinner (y), wider across (z), a little longer (x).
    static func slabScale(flatten f: Float) -> SIMD3<Float> {
        let f = clamp(f, 0.05, 1)
        return SIMD3(1 + 0.12 * (1 - f), f, min(1 / f.squareRoot() * (1 + 0.25 * (1 - f)), maxWiden))
    }

    /// A smear lane's half extents (x along the crayon, z across) at progress `t`; the crumble runs it out of the box.
    static func smearSize(_ t: Float, crumbled: Bool) -> SIMD2<Float> {
        let t = clamp(t, 0, 1)
        let long = length * (0.32 + 0.22 * t + (crumbled ? 0.14 * t : 0))
        let wide = crayonDiameter * (0.35 + 0.85 * t)
        return SIMD2(long, wide)
    }

    /// The fold yaw of wall `i` (front, back, tip end, base end): local +Z points out of the box.
    static func wallYaw(_ i: Int) -> simd_quatf {
        let yaws: [Float] = [0, .pi, .pi / 2, -.pi / 2]
        return simd_quatf(angle: yaws[clamp(i, 0, 3)], axis: [0, 1, 0])
    }

    /// The crayon's lathe profile (radius, axial): flat base, straight body, conical tip.
    static var profile: [SIMD2<Float>] {
        let r = crayonRadius, l = length
        return [
            SIMD2(0, 0), SIMD2(0.86 * r, 0), SIMD2(r, 0.10 * r), SIMD2(r, 0.77 * l), SIMD2(0.96 * r, 0.80 * l),
            SIMD2(0.42 * r, 0.93 * l), SIMD2(0.24 * r, 0.965 * l), SIMD2(0.09 * r, 0.99 * l), SIMD2(0, l),
        ]
    }

    static func radius(at y: Float) -> Float {
        let p = profile
        for i in 0..<(p.count - 1) where y <= p[i + 1].y {
            let a = p[i], b = p[i + 1]
            return a.x + (b.x - a.x) * (y - a.y) / max(b.y - a.y, 1e-6)
        }
        return 0
    }

    /// One capped lathe slice of the crayon between two axial positions (dense rings along the straight body).
    static func pieceMesh(_ range: ClosedRange<Float>) -> MeshData {
        let full = profile
        var points: [SIMD2<Float>] = []
        let lo = range.lowerBound, hi = range.upperBound
        if lo > 0 {
            points.append(SIMD2(0, lo))
            points.append(SIMD2(radius(at: lo) - 0.0006, lo))
            points.append(SIMD2(radius(at: lo), lo + 0.0005))
        }
        if lo == 0 { points.append(contentsOf: full.prefix { $0.y <= 0.0005 }) }
        for p in full where p.y > lo + 0.0005 && p.y < hi - 0.0005 { points.append(p) }
        if hi < length {
            points.append(SIMD2(radius(at: hi), hi - 0.0005))
            points.append(SIMD2(radius(at: hi) - 0.0006, hi))
            points.append(SIMD2(0, hi))
        } else {
            points.append(contentsOf: full.filter { $0.y >= hi - 0.0005 })
        }
        var dense: [SIMD2<Float>] = []
        for (i, p) in points.enumerated() {
            if i > 0 {
                let q = points[i - 1]
                let steps = Int((abs(p.y - q.y) / 0.008).rounded(.down))
                if steps > 1 {
                    for k in 1..<steps { dense.append(q + (p - q) * (Float(k) / Float(steps))) }
                }
            }
            dense.append(p)
        }
        // UVs (v along the crayon) so the wax-streak normal map runs along it.
        return MeshKit.latheUV(profile: dense, segments: 36, vRange: 0...length)
    }

    static func hex(_ colour: UIColor) -> UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        colour.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (UInt32(r * 255) << 16) | (UInt32(g * 255) << 8) | UInt32(b * 255)
    }

    /// The fresh wax inside (and the wrap's paper tint): the colour taken 40 % toward white.
    static func lighter(_ colour: UIColor) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        colour.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: r + (1 - r) * 0.4, green: g + (1 - g) * 0.4, blue: b + (1 - b) * 0.4, alpha: 1)
    }
}
