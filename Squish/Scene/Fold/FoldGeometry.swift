import CoreGraphics
import Foundation
import simd

// Fold Press geometry (design/FOLD-PRESS.md §2.2, §2.3, §5, §9.2, §9.3). Pure maths: no UIKit, no RealityKit,
// no actor isolation, so every number here is unit-tested in SquishTests/FoldPressTests.swift.
//
// Two coordinate systems are used throughout:
//  • Fold space (points): `lateral` runs along the hinge (0…lateralLength) and `depth` is the signed distance
//    from the hinge axis, negative on the platen half, positive on the anvil half.
//  • Anvil frame (millimetres, §2.2): origin = the object's footprint centre on the glass, +y = glass normal,
//    +z = toward the anvil half's free (front) edge, x = y × z. The hinge axis is at z = −40 mm.

/// The fixed physical and bezel numbers of the Duo press (§2.3, §5). Points are inner-display points.
enum FoldMetrics {
    /// 951 pt ≈ 157.9 mm on the inner display (§2.3) [verify with the Week-0 100 mm ruler].
    static let pointsPerMM: Double = 6.02
    /// The hinge's division region: always 40 pt, centred on the axis (§9.2).
    static let creaseBand: Double = 40
    static var creaseHalf: Double { creaseBand / 2 }
    /// Object footprint centre (and its print) from the hinge axis (§2.3): 40 mm.
    static let footprintFromAxisMM: Double = 40
    static var footprintDepth: Double { footprintFromAxisMM * pointsPerMM }
    static let jaw: Double = 10
    static let rail: Double = 12
    static let crownDepth: Double = 64
    static let consoleDepth: Double = 62
    static let backLip: Double = 6
    /// Strike plates: 300 pt along the hinge × 230 pt across it, r 18 (§2.1).
    static let plateLateral: Double = 300
    static let plateDepth: Double = 230
    static let plateRadius: Double = 18
    static let boltDiameter: Double = 12
    static let boltInset: Double = 14
    static let pinDiameter: Double = 10
    static let pinFromSide: Double = 28
    static let pinFromCrease: Double = 60
    /// The plate stands 0.4 mm proud of the enamel field; the object's base (scene y = 0) is on the plate.
    static let plateProudMM: Double = 0.4
    /// P-48 asset scale: 1 scene metre = 340 mm (§2.2).
    static let mmPerSceneMetre: Double = 340
    /// Fold-mode height cap (§2.3): rendered rest height ≤ 24 mm.
    static let heightCapMM: Double = 24
    /// Projected silhouettes stay this far from the crease band edge (§2.3, §12 R2).
    static let silhouetteClearance: Double = 24
    /// Footprints stay this far from the crease band edge (§2.3).
    static let footprintClearance: Double = 60

    /// `foldScale = min(1, 0.0706 / restHeight)` (§2.3): the object's size relative to the glass.
    static func foldScale(restHeight: Double) -> Double {
        min(1, heightCapMM / mmPerSceneMetre / max(restHeight, 1e-4))
    }

    /// Scene metres per physical millimetre for an object drawn at `foldScale` (perspective is scale-invariant,
    /// so the object is shrunk by enlarging the glass and the eye instead of scaling its entity).
    static func metresPerMM(foldScale: Double) -> Double {
        1 / mmPerSceneMetre / max(foldScale, 0.05)
    }
}

/// Which way the hinge runs, decided once per canvas size (§9.2): wider than tall = book.
enum FoldAxis: Equatable, Sendable {
    /// Horizontal hinge (upright 669 × 951): platen = top half, anvil = bottom half. Tabletop.
    case horizontal
    /// Vertical hinge (sideways 951 × 669): platen = leading (left) page, anvil = trailing (right) page. Book.
    case vertical
}

/// Every rectangle of the Fold Press canvas (§5 bezel geometry), computed once per canvas size and never on
/// division-region activation (§9.2: activation lags ~1 s and would jump the plates mid-press).
struct FoldLayout: Equatable, Sendable {
    let canvas: CGSize
    let axis: FoldAxis
    /// The hinge axis along the depth direction (canvas y for a horizontal hinge, x for a vertical one).
    let axisPosition: Double
    /// Canvas length along the hinge.
    let lateralLength: Double
    /// Canvas length across the hinge.
    let depthLength: Double

    var isBook: Bool { axis == .vertical }

    /// From the canvas alone (§9.2 fallback): 669 × 951 → horizontal fold at y 475.5, 951 × 669 → vertical at x 475.5.
    /// `foldLine` overrides the axis position (e.g. from the division region's midline) when known.
    init(canvas: CGSize, foldLine: Double? = nil) {
        self.canvas = canvas
        let w = Double(max(canvas.width, 1)), h = Double(max(canvas.height, 1))
        axis = w > h ? .vertical : .horizontal
        lateralLength = axis == .horizontal ? w : h
        depthLength = axis == .horizontal ? h : w
        axisPosition = foldLine ?? depthLength / 2
    }

    // MARK: Fold space ↔ canvas

    /// Distance from the axis to the platen's free edge (positive number).
    var platenReach: Double { axisPosition }
    /// Distance from the axis to the anvil's free edge.
    var anvilReach: Double { depthLength - axisPosition }

    func point(lateral l: Double, depth d: Double) -> CGPoint {
        switch axis {
        case .horizontal: CGPoint(x: l, y: axisPosition + d)
        case .vertical: CGPoint(x: axisPosition + d, y: l)
        }
    }

    func foldCoordinates(of p: CGPoint) -> (lateral: Double, depth: Double) {
        switch axis {
        case .horizontal: (Double(p.x), Double(p.y) - axisPosition)
        case .vertical: (Double(p.y), Double(p.x) - axisPosition)
        }
    }

    func rect(lateral: ClosedRange<Double>, depth: ClosedRange<Double>) -> CGRect {
        let a = point(lateral: lateral.lowerBound, depth: depth.lowerBound)
        let b = point(lateral: lateral.upperBound, depth: depth.upperBound)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    /// Mirror across the crease midline: where a platen point lands on the anvil when the phone shuts.
    func mirror(_ p: CGPoint) -> CGPoint {
        switch axis {
        case .horizontal: CGPoint(x: p.x, y: 2 * axisPosition - p.y)
        case .vertical: CGPoint(x: 2 * axisPosition - p.x, y: p.y)
        }
    }

    // MARK: Regions (§5)

    private var all: ClosedRange<Double> { 0...lateralLength }
    private var c: Double { FoldMetrics.creaseHalf }

    var platenHalf: CGRect { rect(lateral: all, depth: -platenReach...(-c)) }
    var creaseRect: CGRect { rect(lateral: all, depth: -c...c) }
    var anvilHalf: CGRect { rect(lateral: all, depth: c...anvilReach) }

    var platenJaw: CGRect { rect(lateral: all, depth: -platenReach...(-platenReach + FoldMetrics.jaw)) }
    var anvilJaw: CGRect { rect(lateral: all, depth: (anvilReach - FoldMetrics.jaw)...anvilReach) }

    /// Tabletop: the 64 pt graphite band under the top jaw. Book: a band along the top of the platen page.
    var crownStrip: CGRect {
        switch axis {
        case .horizontal:
            let top = -platenReach + FoldMetrics.jaw
            return rect(lateral: all, depth: top...(top + FoldMetrics.crownDepth))
        case .vertical:
            let l0 = FoldMetrics.rail
            return rect(lateral: l0...(l0 + FoldMetrics.crownDepth), depth: (-platenReach + FoldMetrics.jaw)...(-c))
        }
    }

    /// Tabletop: 62 pt above the bottom jaw. Book: along the bottom of the anvil page, under the right thumb.
    var consoleBand: CGRect {
        switch axis {
        case .horizontal:
            let bottom = anvilReach - FoldMetrics.jaw
            return rect(lateral: all, depth: (bottom - FoldMetrics.consoleDepth)...bottom)
        case .vertical:
            let l1 = lateralLength - FoldMetrics.rail
            return rect(lateral: (l1 - FoldMetrics.consoleDepth)...l1, depth: c...(anvilReach - FoldMetrics.jaw))
        }
    }

    /// Depth ranges the side rails cover on each half (they stop at the crease band, aligned across it).
    var platenRailDepth: ClosedRange<Double> {
        let top = -platenReach + FoldMetrics.jaw + (isBook ? 0 : FoldMetrics.crownDepth)
        return top...(-c)
    }

    var anvilRailDepth: ClosedRange<Double> {
        let bottom = anvilReach - FoldMetrics.jaw - (isBook ? 0 : FoldMetrics.consoleDepth)
        return c...bottom
    }

    /// The four rails: (lateral range, depth range) for both edges of both halves.
    var rails: [CGRect] {
        let r = FoldMetrics.rail
        var rects: [CGRect] = []
        for lateral in [0...r, (lateralLength - r)...lateralLength] {
            rects.append(rect(lateral: lateral, depth: platenRailDepth))
            rects.append(rect(lateral: lateral, depth: anvilRailDepth))
        }
        return rects
    }

    /// Lateral range of the stage fields (inside the rails, and clear of the book crown / console bands).
    var platenFieldLateral: ClosedRange<Double> {
        let r = FoldMetrics.rail
        return isBook ? (r + FoldMetrics.crownDepth)...(lateralLength - r) : r...(lateralLength - r)
    }

    var anvilFieldLateral: ClosedRange<Double> {
        let r = FoldMetrics.rail
        return isBook ? r...(lateralLength - r - FoldMetrics.consoleDepth) : r...(lateralLength - r)
    }

    var platenField: CGRect { rect(lateral: platenFieldLateral, depth: platenRailDepth) }
    var anvilField: CGRect { rect(lateral: anvilFieldLateral, depth: anvilRailDepth) }

    // MARK: Plates (§2.1, §3.4: exact mirror images across the crease)

    var lateralCentre: Double { lateralLength / 2 }
    var footprintCentre: CGPoint { point(lateral: lateralCentre, depth: FoldMetrics.footprintDepth) }
    var printCentre: CGPoint { point(lateral: lateralCentre, depth: -FoldMetrics.footprintDepth) }

    func strikePlate(platen: Bool) -> CGRect {
        let d = platen ? -FoldMetrics.footprintDepth : FoldMetrics.footprintDepth
        return rect(lateral: (lateralCentre - FoldMetrics.plateLateral / 2)...(lateralCentre + FoldMetrics.plateLateral / 2),
                    depth: (d - FoldMetrics.plateDepth / 2)...(d + FoldMetrics.plateDepth / 2))
    }

    func bolts(platen: Bool) -> [CGPoint] {
        // The platen's bolts are the anvil's, mirrored across the hinge, index for index (so they meet at close).
        if platen { return bolts(platen: false).map(mirror) }
        let d = FoldMetrics.footprintDepth
        let dl = FoldMetrics.plateLateral / 2 - FoldMetrics.boltInset
        let dd = FoldMetrics.plateDepth / 2 - FoldMetrics.boltInset
        let signs: [SIMD2<Double>] = [SIMD2(-1, -1), SIMD2(1, -1), SIMD2(1, 1), SIMD2(-1, 1)]
        return signs.map { s in point(lateral: lateralCentre + s.x * dl, depth: d + s.y * dd) }
    }

    /// Guide pins (platen) and their bushings (anvil): 28 pt in from each side, 60 pt from the crease band edge.
    func guidePins(platen: Bool) -> [CGPoint] {
        let d = (FoldMetrics.creaseHalf + FoldMetrics.pinFromCrease) * (platen ? -1 : 1)
        // Book: the crown and console bands run along the page edges, so the pins move in to stay visible on both.
        let side = isBook ? FoldMetrics.rail + FoldMetrics.crownDepth + FoldMetrics.pinFromSide : FoldMetrics.pinFromSide
        return [side, lateralLength - side].map { point(lateral: $0, depth: d) }
    }

    // MARK: Canvas ↔ anvil frame (millimetres)

    /// Anvil-frame (x, z) in mm for a fold-space point on the anvil half.
    func anvilMM(lateral l: Double, depth d: Double) -> SIMD2<Double> {
        let ppm = FoldMetrics.pointsPerMM
        let x = axis == .horizontal ? (l - lateralCentre) / ppm : (lateralCentre - l) / ppm
        return SIMD2(x, d / ppm - FoldMetrics.footprintFromAxisMM)
    }

    func anvilMM(canvas p: CGPoint) -> SIMD2<Double> {
        let f = foldCoordinates(of: p)
        return anvilMM(lateral: f.lateral, depth: f.depth)
    }

    /// The canvas point of an anvil-frame (x, z) on the glass.
    func canvasPoint(anvilMM a: SIMD2<Double>) -> CGPoint {
        let ppm = FoldMetrics.pointsPerMM
        let d = (a.y + FoldMetrics.footprintFromAxisMM) * ppm
        let l = axis == .horizontal ? lateralCentre + a.x * ppm : lateralCentre - a.x * ppm
        return point(lateral: l, depth: d)
    }

    /// The four anvil-half corners in half-local points (top-left, top-right, bottom-right, bottom-left) and the
    /// matching glass corners in the anvil frame (mm, on the enamel field: y = −plateProudMM).
    var anvilCorners: (local: [CGPoint], glass: [SIMD3<Double>]) {
        let half = anvilHalf
        let local = [CGPoint(x: 0, y: 0), CGPoint(x: half.width, y: 0),
                     CGPoint(x: half.width, y: half.height), CGPoint(x: 0, y: half.height)]
        let glass = local.map { p -> SIMD3<Double> in
            let a = anvilMM(canvas: CGPoint(x: half.minX + p.x, y: half.minY + p.y))
            return SIMD3(a.x, -FoldMetrics.plateProudMM, a.y)
        }
        return (local, glass)
    }

    /// Print space → canvas offsets, as an affine about the print centre. Print space is the anvil frame seen
    /// top-down in points (x = anvil x · ppm, y = anvil z · ppm); the platen shows it mirrored across the crease.
    var platenPrintTransform: CGAffineTransform {
        switch axis {
        case .horizontal: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0)
        case .vertical: CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: 0, ty: 0)
        }
    }

    /// Print space → canvas offsets about the footprint centre, on the anvil (unmirrored).
    var anvilPrintTransform: CGAffineTransform {
        switch axis {
        case .horizontal: .identity
        case .vertical: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 0)
        }
    }
}

// MARK: - Eye model (§2.2, §9.4)

/// How the phone is being held, which sets the assumed (never tracked) eye.
enum FoldPose: Equatable, Sendable {
    /// Anvil half flat on a table; the eye is fixed relative to the table.
    case tabletop
    /// Horizontal fold held in the hands, the anvil pitched up toward the user by `pitch` degrees.
    case handheld(pitch: Double)
    /// Vertical fold held like a book open at `hinge` degrees; the eye sits on the wedge bisector.
    case book(hinge: Double)
}

/// The design eye in the anvil frame (mm) and the slightly steeper eye we actually render from (§2.2).
struct FoldEyeModel: Equatable, Sendable {
    var tabletopDistanceMM: Double = 380
    var elevationDegrees: Double = 40
    var bookDistanceMM: Double = 320
    /// 0 = straight down the glass normal, 1 = the full design eye (§2.2) [tune].
    var anamorphicStrength: Double = 0.85
    /// Floor on the rendered elevation, so tall objects never lean into the crease band (§12 R2) when the
    /// book eye drops low below ~70° [tune].
    var minRenderElevationDegrees: Double = 47.5

    static let standard = FoldEyeModel()

    func designEye(_ pose: FoldPose) -> SIMD3<Double> {
        switch pose {
        case .tabletop:
            return Self.polar(distance: tabletopDistanceMM, elevation: elevationDegrees)
        case let .handheld(pitch):
            return Self.polar(distance: tabletopDistanceMM, elevation: min(elevationDegrees + max(pitch, 0), 75))
        case let .book(hinge):
            let half = clamp(hinge, 20, 180) / 2 * .pi / 180
            let hingeAxis = SIMD3<Double>(0, 0, -FoldMetrics.footprintFromAxisMM)
            return hingeAxis + bookDistanceMM * SIMD3(0, sin(half), cos(half))
        }
    }

    /// ε_render = ε + (1 − s)(90° − ε), measured from the footprint centre (§2.2); the distance is kept.
    func renderEye(_ pose: FoldPose) -> SIMD3<Double> {
        let eye = designEye(pose)
        let distance = simd_length(eye)
        let elevation = atan2(eye.y, eye.z) * 180 / .pi
        var rendered = elevation + (1 - clamp(anamorphicStrength, 0, 1)) * (90 - elevation)
        rendered = clamp(rendered, minRenderElevationDegrees, 180 - minRenderElevationDegrees)
        return Self.polar(distance: distance, elevation: rendered)
    }

    /// Elevation (degrees above the glass, from the footprint centre, toward the front edge) of the rendered eye.
    func renderElevation(_ pose: FoldPose) -> Double {
        let eye = renderEye(pose)
        return atan2(eye.y, eye.z) * 180 / .pi
    }

    private static func polar(distance: Double, elevation degrees: Double) -> SIMD3<Double> {
        let e = degrees * .pi / 180
        return distance * SIMD3(0, sin(e), cos(e))
    }

    /// Where a point above the glass appears on the glass from `eye` (the anamorphic footprint of height).
    static func projectOntoGlass(_ point: SIMD3<Double>, eye: SIMD3<Double>, glassY: Double = 0) -> SIMD2<Double> {
        let ray = point - eye
        guard abs(ray.y) > 1e-9 else { return SIMD2(point.x, point.z) }
        let t = (glassY - eye.y) / ray.y
        let hit = eye + ray * t
        return SIMD2(hit.x, hit.z)
    }
}

// MARK: - Homography (§9.3 Tier B step 3)

/// A 3×3 projective map, row-major, h33 = 1: (x, y) → ((h11 x + h12 y + h13) / w, (h21 x + h22 y + h23) / w),
/// w = h31 x + h32 y + 1.
struct FoldHomography: Equatable, Sendable {
    var m: [Double]   // 9 entries, row-major

    static let identity = FoldHomography(m: [1, 0, 0, 0, 1, 0, 0, 0, 1])

    /// The standard 8 × 8 linear solve from four point pairs. Nil if the points are degenerate.
    static func solve(from source: [CGPoint], to target: [CGPoint]) -> FoldHomography? {
        guard source.count == 4, target.count == 4 else { return nil }
        var a = [[Double]](repeating: [Double](repeating: 0, count: 9), count: 8)
        for i in 0..<4 {
            let x = Double(source[i].x), y = Double(source[i].y)
            let u = Double(target[i].x), v = Double(target[i].y)
            a[2 * i] = [x, y, 1, 0, 0, 0, -u * x, -u * y, u]
            a[2 * i + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y, v]
        }
        // Gaussian elimination with partial pivoting.
        for col in 0..<8 {
            var pivot = col
            for row in (col + 1)..<8 where abs(a[row][col]) > abs(a[pivot][col]) { pivot = row }
            guard abs(a[pivot][col]) > 1e-12 else { return nil }
            if pivot != col { a.swapAt(pivot, col) }
            let p = a[col][col]
            for k in col..<9 { a[col][k] /= p }
            for row in 0..<8 where row != col {
                let f = a[row][col]
                if f != 0 {
                    for k in col..<9 { a[row][k] -= f * a[col][k] }
                }
            }
        }
        let h = (0..<8).map { a[$0][8] }
        guard h.allSatisfy({ $0.isFinite }) else { return nil }
        return FoldHomography(m: h + [1])
    }

    func apply(_ p: CGPoint) -> CGPoint {
        let x = Double(p.x), y = Double(p.y)
        let w = m[6] * x + m[7] * y + m[8]
        return CGPoint(x: (m[0] * x + m[1] * y + m[2]) / w, y: (m[3] * x + m[4] * y + m[5]) / w)
    }

    /// The projective denominator at `p` (must stay positive inside the view for Core Animation).
    func w(at p: CGPoint) -> Double { m[6] * Double(p.x) + m[7] * Double(p.y) + m[8] }

    /// Core Animation row-vector layout (§9.3 step 4): m11=h11 m21=h12 m41=h13 | m12=h21 m22=h22 m42=h23 |
    /// m14=h31 m24=h32 m44=h33 | m33=1. Returned as (m11 … m44) in row order, for `CATransform3D`.
    var coreAnimationEntries: [Double] {
        [m[0], m[3], 0, m[6],
         m[1], m[4], 0, m[7],
         0, 0, 1, 0,
         m[2], m[5], 0, m[8]]
    }
}

// MARK: - Off-axis camera, Tier B (§9.3): a symmetric camera at the eye plus a keystone warp of the view

struct FoldCameraSolution: Equatable, Sendable {
    /// Camera position and basis in the anvil frame (mm). The camera looks along `forward`.
    var eye: SIMD3<Double>
    var right: SIMD3<Double>
    var up: SIMD3<Double>
    var forward: SIMD3<Double>
    /// Vertical half-FOV tangent and the resulting vertical FOV in degrees.
    var tanHalfV: Double
    var verticalFOV: Double
    /// Maps ARView points to anvil-half-local points.
    var homography: FoldHomography
    /// The four glass corners in ARView points (for tests and the inverse hit test).
    var viewCorners: [CGPoint]
}

enum FoldCamera {
    /// Pinhole image-plane coordinates (tangent units) of `p` for a camera at `eye` with the given basis.
    static func project(_ p: SIMD3<Double>, eye: SIMD3<Double>, right: SIMD3<Double>, up: SIMD3<Double>,
                        forward: SIMD3<Double>) -> SIMD2<Double>? {
        let v = p - eye
        let depth = simd_dot(v, forward)
        guard depth > 1e-6 else { return nil }
        return SIMD2(simd_dot(v, right) / depth, simd_dot(v, up) / depth)
    }

    /// Camera basis looking from `eye` toward `target`. "Up" in the image is toward the crease (−z), which is
    /// never parallel to the view direction for any eye above the glass.
    static func basis(eye: SIMD3<Double>, target: SIMD3<Double>) -> (right: SIMD3<Double>, up: SIMD3<Double>, forward: SIMD3<Double>) {
        let forward = simd_normalize(target - eye)
        var right = simd_cross(forward, SIMD3(0, 0, -1))
        if simd_length(right) < 1e-6 { right = SIMD3(1, 0, 0) }
        right = simd_normalize(right)
        let up = simd_cross(right, forward)
        return (right, up, forward)
    }

    /// The aspect (width / height) the anvil ARView should have for this eye and glass, after centring.
    static func naturalAspect(glass: [SIMD3<Double>], eye: SIMD3<Double>) -> Double {
        let (_, _, _, extent) = aim(glass: glass, eye: eye)
        return extent.x / max(extent.y, 1e-6)
    }

    /// Aims the camera at the centre of the glass's projected bounding box (3 refinements) and returns the basis
    /// plus the half-extents (tangent units) of the projected glass.
    static func aim(glass: [SIMD3<Double>], eye: SIMD3<Double>)
        -> (right: SIMD3<Double>, up: SIMD3<Double>, forward: SIMD3<Double>, extent: SIMD2<Double>) {
        var target = glass.reduce(SIMD3<Double>.zero, +) / Double(max(glass.count, 1))
        var b = basis(eye: eye, target: target)
        var extent = SIMD2<Double>(1, 1)
        for _ in 0..<4 {
            let uv = glass.compactMap { project($0, eye: eye, right: b.right, up: b.up, forward: b.forward) }
            guard uv.count == glass.count else { break }
            let lo = uv.reduce(SIMD2(Double.infinity, .infinity)) { simd_min($0, $1) }
            let hi = uv.reduce(SIMD2(-Double.infinity, -.infinity)) { simd_max($0, $1) }
            let centre = (lo + hi) / 2
            extent = (hi - lo) / 2
            if simd_length(centre) < 1e-5 { break }
            target = eye + b.forward + b.right * centre.x + b.up * centre.y
            b = basis(eye: eye, target: target)
        }
        return (b.right, b.up, b.forward, extent)
    }

    /// The full Tier B solve: camera at `eye`, FOV fitted to a fixed ARView size, and the homography that puts the
    /// projected glass corners exactly on the half's corners.
    static func solve(glass: [SIMD3<Double>], halfLocal: [CGPoint], eye: SIMD3<Double>, viewSize: CGSize,
                      margin: Double = 1.01) -> FoldCameraSolution? {
        guard glass.count == 4, halfLocal.count == 4, viewSize.width > 1, viewSize.height > 1 else { return nil }
        let aimed = aim(glass: glass, eye: eye)
        let aspect = Double(viewSize.width / viewSize.height)
        let uv = glass.compactMap { project($0, eye: eye, right: aimed.right, up: aimed.up, forward: aimed.forward) }
        guard uv.count == 4 else { return nil }
        let maxU = uv.map { abs($0.x) }.max() ?? 1
        let maxV = uv.map { abs($0.y) }.max() ?? 1
        let tanV = max(maxV, maxU / aspect) * margin
        let tanU = tanV * aspect
        let w = Double(viewSize.width), h = Double(viewSize.height)
        let corners = uv.map { CGPoint(x: (($0.x / tanU) + 1) / 2 * w, y: (1 - $0.y / tanV) / 2 * h) }
        guard let homography = FoldHomography.solve(from: corners, to: halfLocal) else { return nil }
        return FoldCameraSolution(eye: eye, right: aimed.right, up: aimed.up, forward: aimed.forward,
                                  tanHalfV: tanV, verticalFOV: 2 * atan(tanV) * 180 / .pi,
                                  homography: homography, viewCorners: corners)
    }

    /// ARView size for a half: area = oversample² × half area, at the natural aspect, capped so a 3× drawable
    /// stays sane (§9.3 step 2, §9.7).
    static func viewSize(half: CGSize, aspect: Double, oversample: Double) -> CGSize {
        let area = oversample * oversample * Double(half.width * half.height)
        let a = clamp(aspect, 0.4, 4)
        var height = (area / a).squareRoot()
        var width = height * a
        let cap = 1400.0
        if width > cap { height *= cap / width; width = cap }
        if height > cap { width *= cap / height; height = cap }
        return CGSize(width: width.rounded(), height: height.rounded())
    }
}

// MARK: - The hinge curve, as seen from the Duo (§4)

enum FoldCurve {
    /// The hinge angle at which compression `c` is reached for a press armed at `start` (FOLD-PRESS §4.3:
    /// θ = 132 − 84·c^(1/1.7) for θ0 = 168).
    static func angle(forCompression c: Double, start: Double = 168, config: PressConfig = .standard) -> Double {
        let armed = config.armed(at: start)
        let depth = armed.contactT + (1 - armed.contactT) * clamp(c, 0, 1)
        return PressMapping.angle(forDepth: depth, start: min(start, config.armAngleMax), config: armed)
    }

    /// The contact angle for a press armed at `start`: min(132, θ0 − 12).
    static func contactAngle(start: Double = 168, config: PressConfig = .standard) -> Double {
        angle(forCompression: 0, start: start, config: config)
    }

    /// Sheen position along the strike plate, 0 = far edge (θ 180) … 1 = crease edge (θ 60), linear in θ (§3.3).
    static func sheenPosition(angle: Double) -> Double { clamp((180 - angle) / 120, 0, 1) }

    /// Sheen intensity 0…1, peaking around 120° (§3.3).
    static func sheenIntensity(angle: Double) -> Double {
        let x = (angle - 120) / 38
        return 0.30 + 0.70 * exp(-x * x)
    }

    /// Tabletop dimming multiplier for the platen field: 1 above 75°, 0.55 at 45° (§3.3).
    static func platenDimming(angle: Double) -> Double {
        1 - 0.45 * clamp((75 - angle) / 30, 0, 1)
    }

    /// Wedge light (§2.4): rimGain = 0.6 + 0.4·clamp((150 − θ)/60, 0, 1).
    static func rimGain(angle: Double) -> Double { 0.6 + 0.4 * clamp((150 - angle) / 60, 0, 1) }

    /// Print radius as a fraction of the full print: r = R·min(1, 1.1·√c) (§3.2).
    static func printFraction(compression c: Double) -> Double { min(1, 1.1 * max(c, 0).squareRoot()) }

    /// Approach-shadow parameters from the virtual gap s/s0 (§4.4): blur pt, alpha, scale.
    static func shadow(gap q: Double) -> (blur: Double, alpha: Double, scale: Double) {
        let q = clamp(q, 0, 1)
        return (4 + 36 * q, 0.08 + 0.27 * (1 - q), 1 + 0.25 * q)
    }
}
