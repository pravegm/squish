import CoreGraphics
import Foundation
import simd
import Testing
@testable import Squish

/// Fold Press geometry (design/FOLD-PRESS.md §2.2–2.3, §4.3, §5, §9.2–9.3, §12 R2/R3).
@MainActor
struct FoldPressTests {
    private func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.01) -> Bool { abs(a - b) <= tolerance }
    private func near(_ a: Double, _ b: Double, _ tolerance: Double = 0.01) -> Bool { abs(a - b) <= tolerance }

    // MARK: Homography

    @Test func homographyMapsCornersExactly() throws {
        let source = [CGPoint(x: 12, y: 30), CGPoint(x: 610, y: 4), CGPoint(x: 700, y: 455), CGPoint(x: -40, y: 390)]
        let target = [CGPoint(x: 0, y: 0), CGPoint(x: 669, y: 0), CGPoint(x: 669, y: 455.5), CGPoint(x: 0, y: 455.5)]
        let h = try #require(FoldHomography.solve(from: source, to: target))
        for (s, t) in zip(source, target) {
            let p = h.apply(s)
            #expect(near(p.x, t.x, 1e-6) && near(p.y, t.y, 1e-6), "corner \(s) → \(p), want \(t)")
            #expect(h.w(at: s) > 0)
        }
    }

    @Test func homographyRecoversAKnownProjectiveMap() throws {
        let known = FoldHomography(m: [1.2, 0.1, 5, -0.05, 0.9, 12, 0.0004, -0.0002, 1])
        let source = [CGPoint(x: 0, y: 0), CGPoint(x: 300, y: 0), CGPoint(x: 300, y: 200), CGPoint(x: 0, y: 200)]
        let solved = try #require(FoldHomography.solve(from: source, to: source.map { known.apply($0) }))
        let probe = CGPoint(x: 123, y: 77)
        let a = known.apply(probe), b = solved.apply(probe)
        #expect(near(a.x, b.x, 1e-6) && near(a.y, b.y, 1e-6))
        let degenerate = FoldHomography.solve(from: [.zero, .zero, .zero, .zero], to: source)
        #expect(degenerate == nil)
    }

    @Test func coreAnimationLayoutMatchesSpec() {
        let h = FoldHomography(m: [1, 2, 3, 4, 5, 6, 7, 8, 9])
        let e = h.coreAnimationEntries
        // m11=h11 m21=h12 m41=h13 | m12=h21 m22=h22 m42=h23 | m14=h31 m24=h32 m44=h33 | m33=1
        #expect(e[0] == 1 && e[4] == 2 && e[12] == 3)
        #expect(e[1] == 4 && e[5] == 5 && e[13] == 6)
        #expect(e[3] == 7 && e[7] == 8 && e[15] == 9)
        #expect(e[10] == 1 && e[2] == 0 && e[14] == 0)
    }

    // MARK: Layout (§5, §9.2)

    @Test func tabletopLayoutFromUprightCanvas() {
        let layout = FoldLayout(canvas: CGSize(width: 669, height: 951))
        #expect(layout.axis == .horizontal)
        #expect(layout.platenHalf == CGRect(x: 0, y: 0, width: 669, height: 455.5))
        #expect(layout.creaseRect == CGRect(x: 0, y: 455.5, width: 669, height: 40))
        #expect(layout.anvilHalf == CGRect(x: 0, y: 495.5, width: 669, height: 455.5))
        #expect(near(layout.footprintCentre.x, 334.5) && near(layout.footprintCentre.y, 716.3, 0.05))
        #expect(near(layout.printCentre.x, 334.5) && near(layout.printCentre.y, 234.7, 0.05))
        #expect(near(layout.crownStrip.minY, 10) && near(layout.crownStrip.maxY, 74))
        #expect(near(layout.consoleBand.minY, 879) && near(layout.consoleBand.maxY, 941))
        let plate = layout.strikePlate(platen: false)
        #expect(near(plate.width, 300) && near(plate.height, 230))
    }

    @Test func bookLayoutFromSidewaysCanvas() {
        let layout = FoldLayout(canvas: CGSize(width: 951, height: 669))
        #expect(layout.axis == .vertical)
        #expect(layout.platenHalf == CGRect(x: 0, y: 0, width: 455.5, height: 669))
        #expect(layout.creaseRect == CGRect(x: 455.5, y: 0, width: 40, height: 669))
        #expect(layout.anvilHalf == CGRect(x: 495.5, y: 0, width: 455.5, height: 669))
        #expect(near(layout.footprintCentre.x, 716.3, 0.05) && near(layout.footprintCentre.y, 334.5))
        #expect(near(layout.printCentre.x, 234.7, 0.05))
        let plate = layout.strikePlate(platen: false)
        #expect(near(plate.width, 230) && near(plate.height, 300))
        // Book: crown on the leading (platen) page, console on the trailing (anvil) page.
        #expect(layout.platenHalf.contains(CGPoint(x: layout.crownStrip.midX, y: layout.crownStrip.midY)))
        #expect(layout.anvilHalf.contains(CGPoint(x: layout.consoleBand.midX, y: layout.consoleBand.midY)))
    }

    @Test func platesBoltsAndPinsAreMirrorExact() {
        for canvas in [CGSize(width: 669, height: 951), CGSize(width: 951, height: 669)] {
            let layout = FoldLayout(canvas: canvas)
            let a = layout.strikePlate(platen: false), p = layout.strikePlate(platen: true)
            let mirrored = layout.mirror(CGPoint(x: a.midX, y: a.midY))
            #expect(near(mirrored.x, p.midX, 0.01) && near(mirrored.y, p.midY, 0.01))
            let m = layout.mirror(layout.footprintCentre)
            #expect(near(m.x, layout.printCentre.x, 0.01) && near(m.y, layout.printCentre.y, 0.01))   // R3 ±4 pt
            for (x, y) in zip(layout.bolts(platen: false), layout.bolts(platen: true)) {
                let q = layout.mirror(x)
                #expect(near(q.x, y.x, 0.01) && near(q.y, y.y, 0.01))
            }
            for (x, y) in zip(layout.guidePins(platen: false), layout.guidePins(platen: true)) {
                let q = layout.mirror(x)
                #expect(near(q.x, y.x, 0.01) && near(q.y, y.y, 0.01))
            }
            // Nothing of the stage reaches into the crease band (R1); the footprint keeps 60 pt (R2).
            let crease = layout.creaseRect
            let intersects = [a, p, layout.anvilField, layout.platenField].map { $0.intersects(crease.insetBy(dx: 0.01, dy: 0.01)) }
            let anyIntersects = intersects.contains(true)
            #expect(!anyIntersects)
            let gap = FoldMetrics.footprintDepth - FoldMetrics.creaseHalf - 17 * FoldMetrics.pointsPerMM
            #expect(gap >= FoldMetrics.footprintClearance)
            // Rails line up across the crease (R4).
            let rails = layout.rails
            let lateral: (CGRect) -> (CGFloat, CGFloat) = { r in layout.isBook ? (r.minY, r.maxY) : (r.minX, r.maxX) }
            #expect(near(lateral(rails[0]).0, lateral(rails[1]).0) && near(lateral(rails[0]).1, lateral(rails[1]).1))
            #expect(near(lateral(rails[2]).0, lateral(rails[3]).0) && near(lateral(rails[2]).1, lateral(rails[3]).1))
        }
    }

    @Test func anvilFrameRoundTrips() {
        for canvas in [CGSize(width: 669, height: 951), CGSize(width: 951, height: 669)] {
            let layout = FoldLayout(canvas: canvas)
            let origin = layout.anvilMM(canvas: layout.footprintCentre)
            #expect(near(origin.x, 0, 1e-6) && near(origin.y, 0, 1e-6))
            let p = CGPoint(x: layout.anvilHalf.midX + 37, y: layout.anvilHalf.midY - 21)
            let back = layout.canvasPoint(anvilMM: layout.anvilMM(canvas: p))
            #expect(near(back.x, p.x, 1e-6) && near(back.y, p.y, 1e-6))
            // The anvil's crease edge is at z = −36.7 mm (§2.2), the hinge at −40 mm.
            let crease = layout.anvilCorners.glass.map { $0.z }.min() ?? 0
            #expect(near(crease, -36.68, 0.02))
        }
    }

    // MARK: Mapping (§4.1–4.3)

    @Test func eventAnglesMatchTheFoldPressTable() {
        // (kind, base fracture c → θ from FOLD-PRESS §4.3)
        let table: [(ObjectKind, [Double])] = [
            (.rubberDuck, [82, 66]), (.jelly, [91, 73]), (.sodaCan, [92, 82, 73, 65, 58]), (.cakeSlice, [98, 82, 69]),
            (.unsquishable, [98, 79, 64]), (.glassBottle, [98, 83, 69]), (.gummyBear, [86, 69]),
            (.crayon, [91, 75, 62]), (.egg, [108, 96, 76]),
        ]
        #expect(near(FoldCurve.contactAngle(), 132, 0.01))
        for (kind, expected) in table {
            let angles = kind.profile.fractures.map { FoldCurve.angle(forCompression: $0) }
            #expect(angles.count == expected.count, "\(kind)")
            for (got, want) in zip(angles, expected) {
                #expect(abs(got - want) <= 3, "\(kind): \(got)° vs \(want)°")
            }
        }
        // Bubble wrap: 24 pops spread ~121° → ~57°.
        let pops = MaterialProfile.bubbleWrap.fractures.map { FoldCurve.angle(forCompression: $0) }
        #expect(abs((pops.first ?? 0) - 121) <= 3 && abs((pops.last ?? 0) - 57) <= 3)
    }

    @Test func everyFailureStaysAboveSixtyTwoDegrees() {
        for kind in ObjectKind.allCases {
            let profile = kind.profile
            guard let index = profile.failureIndex else { continue }
            // Worst case = the material's own jitter. (§4.3 claims ≥ 63° at +0.04; the Unsquishable's 0.70 + 0.02
            // lands at 62.7°, still well above the 55° display-off floor.)
            let worst = min(1, profile.fractures[index] + profile.thresholdJitter)
            let angle = FoldCurve.angle(forCompression: worst)
            #expect(angle >= 62, "\(kind) fails at \(angle)°")
            // Arming at the lowest angle (130°) keeps it above the 55° display-off floor too.
            #expect(FoldCurve.angle(forCompression: worst, start: 130) >= 55, "\(kind) at θ0 130")
        }
    }

    @Test func printAndShadowCurves() {
        // §12: kiss/print radius 0.15–0.3 R at 120°, ≥ 0.55 R at 90°.
        let c120 = pow((132.0 - 120) / 84, 1.7), c90 = pow((132.0 - 90) / 84, 1.7)
        let f120 = FoldCurve.printFraction(compression: c120)
        #expect(f120 >= 0.15 && f120 <= 0.3)
        #expect(FoldCurve.printFraction(compression: c90) >= 0.55)
        let open = FoldCurve.shadow(gap: 1), shut = FoldCurve.shadow(gap: 0)
        #expect(near(open.blur, 40) && near(open.alpha, 0.08) && near(open.scale, 1.25))
        #expect(near(shut.blur, 4) && near(shut.alpha, 0.35) && near(shut.scale, 1))
        #expect(near(FoldCurve.platenDimming(angle: 45), 0.55) && near(FoldCurve.platenDimming(angle: 90), 1))
        #expect(near(FoldCurve.rimGain(angle: 180), 0.6) && near(FoldCurve.rimGain(angle: 90), 1))
    }

    // MARK: Eye model (§2.2)

    @Test func eyeModelSanity() {
        let eye = FoldEyeModel.standard
        #expect(near(eye.renderElevation(.tabletop), 47.5, 0.01))
        #expect(near(simd_length(eye.renderEye(.tabletop)), 380, 1e-6))
        let flat = eye.designEye(.book(hinge: 180))
        #expect(near(flat.x, 0) && near(flat.y, 320) && near(flat.z, -40))
        // The book eye drops toward the anvil as the book closes (the pop-up stands up).
        let e120 = eye.renderElevation(.book(hinge: 120)), e90 = eye.renderElevation(.book(hinge: 90))
        #expect(e120 > e90 && e90 >= eye.minRenderElevationDegrees)
        var straight = eye
        straight.anamorphicStrength = 0
        #expect(near(straight.renderElevation(.tabletop), 90, 1e-6))
        var full = eye
        full.anamorphicStrength = 1
        full.minRenderElevationDegrees = 0
        #expect(near(full.renderElevation(.tabletop), 40, 1e-6))
        #expect(near(eye.renderElevation(.handheld(pitch: 50)), 75 + 0.15 * 15, 1e-6))
    }

    /// R3 through the whole Tier B pipeline: the glass point under the object lands on the footprint centre.
    @Test func warpPutsTheGlassExactlyOnTheHalf() throws {
        let cases: [(CGSize, FoldPose)] = [
            (CGSize(width: 669, height: 951), .tabletop),
            (CGSize(width: 951, height: 669), .book(hinge: 180)),
            (CGSize(width: 951, height: 669), .book(hinge: 120)),
            (CGSize(width: 951, height: 669), .book(hinge: 90)),
            (CGSize(width: 951, height: 669), .book(hinge: 60)),
        ]
        let eye = FoldEyeModel.standard
        for (canvas, pose) in cases {
            let layout = FoldLayout(canvas: canvas)
            let corners = layout.anvilCorners
            let e = eye.renderEye(pose)
            let aspect = FoldCamera.naturalAspect(glass: corners.glass, eye: e)
            let size = FoldCamera.viewSize(half: layout.anvilHalf.size, aspect: aspect, oversample: 1.15)
            let s = try #require(FoldCamera.solve(glass: corners.glass, halfLocal: corners.local, eye: e, viewSize: size))
            // Every view corner keeps a positive projective w (Core Animation draws it).
            for p in [CGPoint.zero, CGPoint(x: size.width, y: 0), CGPoint(x: size.width, y: size.height), CGPoint(x: 0, y: size.height)] {
                #expect(s.homography.w(at: p) > 0, "\(pose) w at \(p)")
            }
            func screen(_ point: SIMD3<Double>) throws -> CGPoint {
                let uv = try #require(FoldCamera.project(point, eye: s.eye, right: s.right, up: s.up, forward: s.forward))
                let tanU = s.tanHalfV * Double(size.width / size.height)
                let view = CGPoint(x: (uv.x / tanU + 1) / 2 * Double(size.width), y: (1 - uv.y / s.tanHalfV) / 2 * Double(size.height))
                let local = s.homography.apply(view)
                return CGPoint(x: layout.anvilHalf.minX + local.x, y: layout.anvilHalf.minY + local.y)
            }
            let centre = try screen(SIMD3(0, -FoldMetrics.plateProudMM, 0))
            #expect(near(centre.x, layout.footprintCentre.x, 0.5) && near(centre.y, layout.footprintCentre.y, 0.5),
                    "\(pose): footprint at \(centre)")
            // A bolt corner on the glass too (zero-depth content is exact anywhere on the half).
            let bolt = layout.bolts(platen: false)[2]
            let boltMM = layout.anvilMM(canvas: bolt)
            let b = try screen(SIMD3(boltMM.x, -FoldMetrics.plateProudMM, boltMM.y))
            #expect(near(b.x, bolt.x, 0.5) && near(b.y, bolt.y, 0.5), "\(pose): bolt at \(b), want \(bolt)")
        }
    }

    /// R2: tall rigid objects lean toward the crease but never come within 24 pt of it, at every eye we render from.
    @Test func projectedSilhouettesClearTheCrease() {
        let eye = FoldEyeModel.standard
        let poses: [(CGSize, FoldPose)] = [(CGSize(width: 669, height: 951), .tabletop)]
            + [180.0, 120, 90, 60].map { (CGSize(width: 951, height: 669), FoldPose.book(hinge: $0)) }
        // The Unsquishable (a 24 mm ball at fold scale) and the soda can's lid rim (24 mm up, r 5.8 mm).
        var shapes: [[SIMD3<Double>]] = []
        var ball: [SIMD3<Double>] = []
        for i in 0..<24 {
            for j in 0...12 {
                let a = Double(i) / 24 * 2 * .pi, b = Double(j) / 12 * .pi - .pi / 2
                ball.append(SIMD3(12 * cos(b) * cos(a), 12 + 12 * sin(b), 12 * cos(b) * sin(a)))
            }
        }
        shapes.append(ball)
        shapes.append((0..<24).map { i in
            let a = Double(i) / 24 * 2 * .pi
            return SIMD3(5.8 * cos(a), 24, 5.8 * sin(a))
        })
        for (canvas, pose) in poses {
            let layout = FoldLayout(canvas: canvas)
            let e = eye.renderEye(pose)
            for shape in shapes {
                let deepest = shape.map { FoldEyeModel.projectOntoGlass($0, eye: e, glassY: -FoldMetrics.plateProudMM).y }.min() ?? 0
                // Distance (pt) from the anvil's crease-band edge (z = −36.68 mm).
                let creaseEdge = FoldMetrics.creaseHalf / FoldMetrics.pointsPerMM - FoldMetrics.footprintFromAxisMM
                let clearance = (deepest - creaseEdge) * FoldMetrics.pointsPerMM
                #expect(clearance >= FoldMetrics.silhouetteClearance, "\(pose) clearance \(clearance) pt")
                _ = layout
            }
        }
    }

    @Test func foldScaleCapsHeightAt24mm() {
        #expect(near(FoldMetrics.foldScale(restHeight: 0.107), 0.66, 0.01))   // gummy
        #expect(near(FoldMetrics.foldScale(restHeight: 0.085), 0.83, 0.01))   // duck
        #expect(near(FoldMetrics.foldScale(restHeight: 0.0765), 0.92, 0.01))  // jelly
        #expect(FoldMetrics.foldScale(restHeight: 0.022) == 1)                // crayon
        let k = FoldMetrics.metresPerMM(foldScale: 1)
        #expect(near(k, 0.00294, 0.00001))
    }

    // MARK: Prints (§3.2)

    @Test func stampsAreCentredOnTheFootprintAndDeterministic() {
        for kind in ObjectKind.allCases {
            let variant = PressVariant(kind: kind, seed: 7)
            let a = FoldStamps.stamp(for: kind, variant: variant, foldScale: 0.8)
            let b = FoldStamps.stamp(for: kind, variant: variant, foldScale: 0.8)
            let box = a.silhouette.boundingBoxOfPath
            #expect(!box.isEmpty, "\(kind)")
            // The silhouette straddles the footprint centre and fits the print canvas (strike plate + 40 pt).
            #expect(box.minX < 0 && box.maxX > 0 && box.minY < 0 && box.maxY > 0, "\(kind) box \(box)")
            #expect(FoldPrintCanvas.rect.contains(box), "\(kind) box \(box)")
            #expect(a.apex == b.apex && a.popOrder == b.popOrder)
        }
        let wrap = FoldStamps.stamp(for: .bubbleWrap, variant: PressVariant(kind: .bubbleWrap, seed: 9), foldScale: 1)
        #expect(wrap.features.count == BubbleWrapLayout.count)
        #expect(Set(wrap.popOrder).count == BubbleWrapLayout.count)
    }
}
