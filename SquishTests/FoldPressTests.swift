import CoreGraphics
import Foundation
import simd
import Testing
import UIKit
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

    /// The provisional fold mapping (PressConfig, 25 Oct 2026): from the contact angle (100°) to the fully crushed angle
    /// (50°), linear in θ: θ = contact − (contact − end)·c, whatever the arm angle ≥ 118°. Both are Tuning Lab sliders.
    @Test func eventAnglesFollowTheProvisionalFoldMapping() {
        let contact = PressConfig.standard.contactCeiling, end = PressConfig.standard.endAngle
        #expect(contact == 104 && end == 55)
        #expect(near(FoldCurve.contactAngle(), contact, 0.01))
        #expect(near(FoldCurve.contactAngle(start: 130), contact, 0.01))
        for kind in ObjectKind.allCases {
            for c in kind.profile.fractures {
                #expect(near(FoldCurve.angle(forCompression: c), contact - (contact - end) * c, 0.01), "\(kind) c=\(c)")
            }
            // Resistance you can feel: every failure, even at its earliest jitter, lands ≥ 10° after contact.
            if let index = kind.profile.failureIndex {
                let earliest = kind.profile.fractures[index] - kind.profile.thresholdJitter
                #expect(FoldCurve.angle(forCompression: earliest) <= FoldCurve.contactAngle() - 10, "\(kind)")
            }
        }
        // Bubble wrap: 24 pops from just after contact (~102.5°) to ~63.3°.
        let pops = MaterialProfile.bubbleWrap.fractures.map { FoldCurve.angle(forCompression: $0) }
        #expect(abs((pops.first ?? 0) - 102.5) <= 1 && abs((pops.last ?? 0) - 63.3) <= 1)
    }

    /// The touch press (P-48) keeps the 1.0 mapping its store frames and CI expectations were made on.
    @Test func touchPressKeepsItsOneZeroMapping() {
        let touch = PressConfig.standard.armed(at: 168)
        #expect(near(touch.contactT, 0.3, 1e-9) && touch.easeExponent == 1.7)
        let fold = PressConfig.standard.armed(at: 168, hinge: true)
        #expect(near(fold.contactT, (168.0 - 104) / (168 - 55), 1e-9) && fold.easeExponent == 1.0 && fold.endAngle == 55)
        #expect(touch.endAngle == PressConfig.touchEndAngle)
    }

    @Test func everyFailureStaysAboveSixtyTwoDegrees() {
        for kind in ObjectKind.allCases {
            let profile = kind.profile
            guard let index = profile.failureIndex else { continue }
            // Worst case = the material's own jitter. (§4.3 claims ≥ 63° at +0.04; the Unsquishable's 0.70 + 0.02
            // lands at 62.7°, still well above the 55° display-off floor.)
            let worst = min(1, profile.fractures[index] + profile.thresholdJitter)
            let angle = FoldCurve.angle(forCompression: worst)
            #expect(angle >= PressFeel.failureFloorAngle, "\(kind) fails at \(angle)°")
            // …and well clear of the ~55° display-off angle, so the hit stop, burst and slow debris are lit.
            #expect(angle >= PressFeel.displayOffAngle + 7, "\(kind) fails at \(angle)°")
            // Arming at the lowest angle (130°) keeps it above the 55° display-off floor too.
            #expect(FoldCurve.angle(forCompression: worst, start: 130) >= 55, "\(kind) at θ0 130")
        }
    }

    @Test func printAndShadowCurves() {
        // §12, on the provisional mapping: the kiss/print radius is 0.15–0.3 R 3° past contact, ≥ 0.55 R 15° past it.
        let end = PressConfig.standard.endAngle
        let pressed: (Double) -> Double = { θ in (FoldCurve.contactAngle() - θ) / (FoldCurve.contactAngle() - end) }
        let kiss = FoldCurve.printFraction(compression: pressed(FoldCurve.contactAngle() - 3))
        #expect(kiss >= 0.15 && kiss <= 0.3)
        #expect(FoldCurve.printFraction(compression: pressed(FoldCurve.contactAngle() - 15)) >= 0.55)
        let open = FoldCurve.shadow(gap: 1), shut = FoldCurve.shadow(gap: 0)
        #expect(near(open.blur, 40) && near(open.alpha, 0.08) && near(open.scale, 1.25))
        #expect(near(shut.blur, 4) && near(shut.alpha, 0.35) && near(shut.scale, 1))
        #expect(near(FoldCurve.platenDimming(angle: 45), 0.55) && near(FoldCurve.platenDimming(angle: 90), 1))
        #expect(near(FoldCurve.rimGain(angle: 180), 0.6) && near(FoldCurve.rimGain(angle: 60), 0.8))
        // FOLD-REVIEW-1 #1: at least −0.5 EV in fold framing, more as the eye goes grazing. FOLD-REVIEW-3 N3: no
        // flat-pose term any more (the anvil field is unlit), so it depends on the eye only.
        let high = FoldCurve.exposure(eyeElevation: 85), low = FoldCurve.exposure(eyeElevation: 47.5)
        #expect(near(high.iblOffset, -0.5) && low.iblOffset < high.iblOffset && low.keyGain < high.keyGain)
        #expect(near(high.keyGain, 0.92) && near(low.iblOffset, -0.9) && near(low.keyGain, 0.80))
    }

    // MARK: Clamshell lean (§2.4, FOLD-REVIEW-3 N2)

    @Test func leanIsTwoAndAHalfDegreesTimesCompression() {
        let full = FoldLean.angle(compression: 1, contacted: true, failed: false, kind: .rubberDuck)
        #expect(near(full * 180 / .pi, 2.5, 1e-9))
        #expect(near(FoldLean.angle(compression: 0.4, contacted: true, failed: false, kind: .sodaCan) * 180 / .pi, 1.0, 1e-9))
        #expect(FoldLean.angle(compression: 1.6, contacted: true, failed: false, kind: .jelly) == full)
        // None before contact, none for sheets or the rigid ball, none once the object has failed (debris lies flat).
        #expect(FoldLean.angle(compression: 1, contacted: false, failed: false, kind: .rubberDuck) == 0)
        #expect(FoldLean.angle(compression: 1, contacted: true, failed: false, kind: .bubbleWrap) == 0)
        #expect(FoldLean.angle(compression: 1, contacted: true, failed: false, kind: .unsquishable) == 0)
        #expect(FoldLean.angle(compression: 1, contacted: true, failed: true, kind: .glassBottle) == 0)
    }

    @Test func leanPivotsOnTheBaseEdgeItTipsToward() {
        let r: Float = 17   // the largest fold footprint radius (mm; the maths is unit-free)
        for lean in [Float(2.5 * Double.pi / 180), Float(-2.5 * Double.pi / 180), Float(0.4 * Double.pi / 180)] {
            let rotation = simd_quatf(angle: lean, axis: [1, 0, 0])
            let shift = FoldLean.pivotShift(lean: lean, baseRadius: r)
            func placed(_ p: SIMD3<Float>) -> SIMD3<Float> { rotation.act(p) + shift }
            // No point of a round base sinks below the plate face (the bubble-film cut).
            for i in 0..<72 {
                let a = Float(i) / 72 * 2 * .pi
                let p = placed(SIMD3<Float>(r * cos(a), 0, r * sin(a)))
                #expect(p.y >= -1e-4, "lean \(lean): base point \(p) under the plate")
            }
            // The edge it tips toward stays exactly where it was.
            let edge: Float = lean > 0 ? r : -r
            let pivot = placed(SIMD3<Float>(0, 0, edge))
            #expect(abs(pivot.y) < 1e-4 && abs(pivot.z - edge) < 1e-4)
            // The footprint centre stays within ±6 pt of where it was (N2's CI assert).
            let centre = placed(.zero)
            #expect(Double(abs(centre.z)) * FoldMetrics.pointsPerMM <= 6)
            // The top goes the way the lean says: +z (the anvil's front edge, away from the hinge at −40 mm) for > 0.
            let top = placed(SIMD3<Float>(0, 24, 0))
            #expect(lean > 0 ? top.z > 0.1 : top.z < -0.1)
        }
        #expect(FoldLean.pivotShift(lean: 0, baseRadius: r) == .zero)
    }

    // MARK: Reveal stamp (FOLD-REVIEW-3 N12, FOLD-REVIEW-4 F9, FOLD-REVIEW-5 N9)

    @Test func printCoverageIsWhatThePlatenInks() {
        for book in [false, true] {
            let layout = FoldLayout(canvas: book ? CGSize(width: 951, height: 669) : CGSize(width: 669, height: 951))
            let centre = layout.printCentre
            let plate = layout.strikePlate(platen: true).offsetBy(dx: -centre.x, dy: -centre.y)
            for kind in [ObjectKind.rubberDuck, .sodaCan, .jelly, .egg] {
                let variant = PressVariant(kind: kind, seed: 4)
                let stamp = FoldStamps.stamp(for: kind, variant: variant, foldScale: 0.8)
                let rest = FoldPlaten.printCoverage(stamp, variant: variant, layout: layout, splatScale: 0)
                let failed = FoldPlaten.printCoverage(stamp, variant: variant, layout: layout, splatScale: 1.2)
                // The footprint centre is inked; the splat only ever adds ink.
                #expect(rest.isCovered(.zero) && failed.isCovered(.zero), "\(kind) book \(book)")
                #expect(failed.fraction(in: plate) >= rest.fraction(in: plate), "\(kind) book \(book)")
                #expect(rest.fraction(in: plate) > 0.02 && rest.fraction(in: plate) < 0.9, "\(kind) book \(book)")
            }
            // The duck's print never reaches the plate's corners.
            let duck = FoldStamps.stamp(for: .rubberDuck, variant: PressVariant(kind: .rubberDuck, seed: 4), foldScale: 0.8)
            let coverage = FoldPlaten.printCoverage(duck, variant: PressVariant(kind: .rubberDuck, seed: 4), layout: layout,
                                                    splatScale: 1.2)
            #expect(!coverage.isCovered(CGPoint(x: plate.minX + 8, y: plate.minY + 8)))
            #expect(!coverage.isCovered(CGPoint(x: plate.maxX - 8, y: plate.maxY - 8)))
        }
    }

    @Test func pressedStampLandsOnTheLeastInkedPartOfThePlate() {
        for book in [false, true] {
            let layout = FoldLayout(canvas: book ? CGSize(width: 951, height: 669) : CGSize(width: 669, height: 951))
            let plate = layout.strikePlate(platen: true)
            let centre = layout.printCentre
            let plateOffsets = plate.offsetBy(dx: -centre.x, dy: -centre.y)
            let keepOut = FoldPlaten.ribbonKeepOut(plate: plateOffsets)
            var seedOne: Set<String> = []
            for kind in ObjectKind.allCases {
                var poses: Set<String> = []
                for seed in UInt64(1)...30 {
                    let variant = PressVariant(kind: kind, seed: seed)
                    let stamp = FoldStamps.stamp(for: kind, variant: variant, foldScale: 0.8,
                                                 extraYaw: book ? FoldPressController.bookYaw(kind) : 0)
                    // At the reveal: the silhouette plus the failure splat at its full spread.
                    let coverage = FoldPlaten.printCoverage(stamp, variant: variant, layout: layout, splatScale: 1.2)
                    let a = FoldPlaten.pressedPose(seed: seed, coverage: coverage, plate: plateOffsets, keepOut: keepOut)
                    let b = FoldPlaten.pressedPose(seed: seed, coverage: coverage, plate: plateOffsets, keepOut: keepOut)
                    #expect(a.offset == b.offset && a.angle == b.angle)
                    let degrees = Double(a.angle) * 180 / .pi
                    #expect(degrees >= -18.1 && degrees <= 2.1)
                    // The landed stamp (150 × 57 at 85 %), rotated, stays on the strike plate and off the ribbon.
                    let scale = FoldPlaten.pressedScale
                    let size = FoldPlaten.pressedSize
                    let landed = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
                        .applying(CGAffineTransform(rotationAngle: a.angle).scaledBy(x: scale, y: scale))
                        .offsetBy(dx: a.offset.x, dy: a.offset.y)
                    #expect(plateOffsets.insetBy(dx: 3.9, dy: 3.9).contains(landed),
                            "\(kind) book \(book) seed \(seed): \(landed) outside \(plateOffsets)")
                    #expect(!keepOut.intersects(landed), "\(kind) book \(book) seed \(seed): under the ribbon")
                    // As clear of the ink as that tilt allows anywhere on the plate (the same 6 pt grid), give or take
                    // the seeded pick (0.02) and the pull toward the edges (0.05).
                    let ink = FoldPlaten.pressedInk(at: a.offset, angle: a.angle, coverage: coverage)
                    let hx = landed.width / 2, hy = landed.height / 2
                    var bestInk: CGFloat = 1
                    var y = plateOffsets.minY + 4 + hy
                    while y <= plateOffsets.maxY - 4 - hy + 0.001 {
                        var x = plateOffsets.minX + 4 + hx
                        while x <= plateOffsets.maxX - 4 - hx + 0.001 {
                            let box = CGRect(x: x - hx, y: y - hy, width: 2 * hx, height: 2 * hy)
                            if !keepOut.intersects(box) {
                                bestInk = min(bestInk, FoldPlaten.pressedInk(at: CGPoint(x: x, y: y), angle: a.angle,
                                                                             coverage: coverage))
                            }
                            x += 6
                        }
                        y += 6
                    }
                    #expect(ink <= bestInk + 0.0701, "\(kind) book \(book) seed \(seed): ink \(ink), best \(bestInk)")
                    // FOLD-REVIEW-5 N9: the duck and the can leave free corners, and the stamp takes one. (A lying bottle
                    // spans the book plate, so glass only gets "as clear as it can".)
                    if kind == .rubberDuck || kind == .sodaCan {
                        #expect(ink <= 0.3, "\(kind) book \(book) seed \(seed): \(ink) of the stamp on ink")
                    }
                    poses.insert(String(format: "%.1f %.1f %.3f", Double(a.offset.x), Double(a.offset.y), Double(a.angle)))
                    if seed == 1 { seedOne.insert(String(format: "%.0f %.0f", Double(a.offset.x), Double(a.offset.y))) }
                }
                #expect(poses.count > 25, "\(kind) book \(book): \(poses.count) distinct poses")
            }
            // Each object's prints leave different corners free, so the stamps move with the object too.
            #expect(seedOne.count > 4, "book \(book): seed-1 stamp positions \(seedOne)")
        }
    }

    @Test func escapedDropletsLandClearOfTheSpecimen() {
        let half = CGSize(width: 135, height: 120)   // a duck-sized pancake, print space (points)
        let radius: CGFloat = 4.5 * 1.6
        let ex = half.width * FoldStamps.sprayClearScale + radius + FoldStamps.sprayClearGap
        let ey = half.height * FoldStamps.sprayClearScale + radius + FoldStamps.sprayClearGap
        for i in 0..<24 {
            let a = CGFloat(i) / 24 * 2 * .pi
            let p = CGPoint(x: 30 * cos(a), y: 30 * sin(a))
            let landed = FoldStamps.sprayLanding(p, radius: radius, specimenCentre: .zero, specimenHalf: half)
            let again = FoldStamps.sprayLanding(p, radius: radius, specimenCentre: .zero, specimenHalf: half)
            #expect(landed == again)
            guard let q = landed else {
                Issue.record("droplet \(i) found nowhere to land")
                continue
            }
            #expect((q.x / ex) * (q.x / ex) + (q.y / ey) * (q.y / ey) >= 1 - 1e-6, "droplet \(i) at \(q) under the specimen")
            #expect(FoldStamps.sprayContained(FoldDroplet(centre: q, radius: radius), scale: 1,
                                              margin: FoldStamps.sprayEscapeMargin), "droplet \(i) at \(q) off the stage")
        }
        // Already clear: stays exactly where the platen put it.
        let clear = CGPoint(x: 140, y: 100)
        #expect(FoldStamps.sprayLanding(clear, radius: 3, specimenCentre: .zero, specimenHalf: CGSize(width: 40, height: 40)) == clear)
        // A specimen over the whole stage leaves nowhere.
        #expect(FoldStamps.sprayLanding(.zero, radius: 3, specimenCentre: .zero, specimenHalf: CGSize(width: 400, height: 400)) == nil)
    }

    /// FOLD-REVIEW-9 N9: the egg's white ran ~40 pt past the strike plate at full spread, and the shell ink's tan rim
    /// showed at the egg's far end. At the splat's widest spread nothing of it may leave the plate.
    @Test func eggSplatStaysOnThePlateAtFullSpread() throws {
        let canvas = FoldPrintCanvas.rect
        let spread = FoldStamps.splatMaxSpread
        // The egg's lying profile (EggView / FoldStamps.stamp): (radius, along), metres.
        let profile: [(Double, Double)] = [
            (0.000, 0.000), (0.017, 0.004), (0.026, 0.010), (0.034, 0.020), (0.0385, 0.032), (0.0400, 0.044),
            (0.0395, 0.056), (0.0370, 0.068), (0.0320, 0.080), (0.0255, 0.090), (0.0180, 0.098), (0.0105, 0.104),
            (0.0045, 0.108), (0.000, 0.110),
        ]
        for book in [false, true] {
            for seed in UInt64(1)...6 {
                let variant = PressVariant(kind: .egg, seed: seed)
                let stamp = FoldStamps.stamp(for: .egg, variant: variant, foldScale: SpecimenPrint.foldScale(.egg, variant: variant),
                                             extraYaw: book ? FoldPressController.bookYaw(.egg) : 0)
                var rng = SplitMix64(seed: 0xE66 &+ seed)
                let white = FoldStamps.eggWhitePath(stamp, rng: &rng)
                // At full spread the white stays inside the plate's 3 pt inset …
                let box = white.boundingBoxOfPath
                #expect(max(abs(box.minX), abs(box.maxX)) * spread <= CGFloat(FoldMetrics.plateLateral / 2 - 3))
                #expect(max(abs(box.minY), abs(box.maxY)) * spread <= CGFloat(FoldMetrics.plateDepth / 2 - 3))
                // … and from the reveal's spread (≥ 1.05) it covers the shell print's whole outline (no tan rim).
                let map = FoldStamps.LocalMap(k: Double(stamp.pointsPerMetre), yaw: stamp.yawRadians)
                for (radius, along) in profile {
                    for side in [-1.0, 1.0] {
                        let p = map(along - 0.055, side * radius)
                        let unspread = CGPoint(x: p.x / 1.05, y: p.y / 1.05)
                        #expect(white.contains(unspread), "egg seed \(seed) book \(book): shell print at \(p) uncovered")
                    }
                }
                // And the drawn splat: no ink at all outside the plate as it stands at full spread.
                let scale: CGFloat = 1
                let image = try #require(FoldStamps.splatImage(stamp, variant: variant, scale: scale))
                let data = try #require(image.dataProvider?.data)
                guard let bytes = CFDataGetBytePtr(data) else {
                    Issue.record("egg seed \(seed): no splat pixels")
                    continue
                }
                let hx = CGFloat(FoldMetrics.plateLateral / 2 - 3) / spread + 1
                let hy = CGFloat(FoldMetrics.plateDepth / 2 - 3) / spread + 1
                var stray = 0
                for py in 0..<image.height {
                    for px in 0..<image.width {
                        let x = canvas.minX + (CGFloat(px) + 0.5) / scale
                        let y = canvas.minY + (CGFloat(py) + 0.5) / scale
                        guard abs(x) > hx || abs(y) > hy else { continue }
                        if bytes[py * image.bytesPerRow + px * 4 + 3] > 0 { stray += 1 }
                    }
                }
                #expect(stray == 0, "egg seed \(seed) book \(book): \(stray) px of splat off the plate")
            }
        }
    }

    /// FOLD-REVIEW-9 N5: the idle picker is centred on the whole outer display and clears the clock column; the
    /// screws sit on the panel's corners, the trailing pair inside the hazard jaw.
    @Test func coverPickerCentresAndScrewsSitOnTheCorners() {
        // The Duo's outer display, with its ~75 pt clock column on the trailing edge.
        let display: CGFloat = 466, clock: CGFloat = 75
        let width = CoverLayout.idleWidth(display: display, leading: 0, trailing: clock, sideInset: 24)
        #expect(width >= CoverLayout.minIdleWidth && width <= CoverLayout.maxIdleWidth)
        // Centred on the display, its trailing edge stays clear of the clock column.
        #expect(display / 2 + width / 2 <= display - clock - CoverLayout.clockClearance + 0.5)
        #expect(display / 2 - width / 2 >= 24 - 0.5)
        // No column: the old 340 pt cap and 24 pt margins.
        #expect(CoverLayout.idleWidth(display: 466, leading: 0, trailing: 0, sideInset: 24) == CGFloat(340))
        #expect(CoverLayout.idleWidth(display: 300, leading: 0, trailing: 0, sideInset: 24) == CGFloat(252))
        #expect(CoverLayout.idleWidth(display: 200, leading: 0, trailing: 60, sideInset: 24) == CoverLayout.minIdleWidth)
        let panel = CGSize(width: display, height: 678)
        let screws = (0..<4).map { CoverLayout.screw($0, in: panel) }
        #expect(screws[0] == CGPoint(x: CoverLayout.screwInset, y: CoverLayout.screwInset))
        #expect(screws[1].x == panel.width - CoverLayout.jawWidth - CoverLayout.screwInset)
        #expect(screws[3].y == panel.height - CoverLayout.screwInset)
        // Mirror images across the panel (the jaw aside), never floating in the panel's middle.
        #expect(abs(screws[0].x - (panel.width - CoverLayout.jawWidth - screws[1].x)) < 0.5)
        #expect(screws[1].x > panel.width - clock)
    }

    @Test func pressedStampTurnsPaperWhiteOnRedPrints() {
        #expect(FoldPlaten.pressedOnPaper(Palette.raspberry))
        #expect(FoldPlaten.pressedOnPaper(UIColor(hex: 0xD0164F)))
        #expect(!FoldPlaten.pressedOnPaper(Palette.duckYellow))
        #expect(!FoldPlaten.pressedOnPaper(Palette.cobalt))
        #expect(!FoldPlaten.pressedOnPaper(UIColor(white: 1, alpha: 1)))
        #expect(!FoldPlaten.pressedOnPaper(UIColor(hex: 0xCFE8F5)))
    }

    // MARK: Splat that escapes the fold (FOLD-REVIEW-4 F3)

    @Test func anvilSprayMirrorsThePlatenSplatAndStaysOnThePlate() {
        let splatters: Set<ObjectKind> = [.rubberDuck, .jelly, .sodaCan, .egg, .cakeSlice, .gummyBear]
        let mirrored: Set<ObjectKind> = [.rubberDuck, .jelly, .sodaCan]
        for kind in ObjectKind.allCases {
            for seed in UInt64(1)...24 {
                let variant = PressVariant(kind: kind, seed: seed)
                for foldScale in [0.6, 0.8, 1.0] {
                    let stamp = FoldStamps.stamp(for: kind, variant: variant, foldScale: foldScale)
                    let a = FoldStamps.anvilSpray(stamp, variant: variant)
                    let b = FoldStamps.anvilSpray(stamp, variant: variant)
                    #expect(a?.droplets == b?.droplets, "\(kind) seed \(seed): not deterministic")
                    guard let spray = a else {
                        #expect(!splatters.contains(kind), "\(kind) seed \(seed) fs \(foldScale): no spray")
                        continue
                    }
                    #expect(splatters.contains(kind))
                    #expect(spray.droplets.count >= 1 && spray.droplets.count <= FoldStamps.sprayMaxCount)
                    for d in spray.droplets {
                        #expect(FoldStamps.sprayContained(d, scale: FoldStamps.sprayMaxScale),
                                "\(kind) seed \(seed) fs \(foldScale): \(d) past the plate + 16")
                    }
                    guard mirrored.contains(kind) else { continue }
                    // Every escaped droplet is one of the platen's, at its very spot, or that one pulled straight in.
                    let platen = FoldStamps.platenSplatDroplets(stamp, variant: variant)
                    for d in spray.droplets {
                        let match = platen.contains { p in
                            guard p.radius == d.radius else { return false }
                            let cross = p.centre.x * d.centre.y - p.centre.y * d.centre.x
                            let along = p.centre.x * d.centre.x + p.centre.y * d.centre.y
                            let pulledIn = FoldStamps.sprayReach(d) <= FoldStamps.sprayReach(p) + 1e-6
                            return abs(cross) < 1e-3 * max(1, along) && along >= 0 && pulledIn
                        }
                        #expect(match, "\(kind) seed \(seed) fs \(foldScale): \(d) is not a platen droplet")
                    }
                }
            }
        }
        // The replay is the platen's own draw: same count as the splat flicks.
        let duck = FoldStamps.stamp(for: .rubberDuck, variant: PressVariant(kind: .rubberDuck, seed: 3), foldScale: 0.8)
        #expect(FoldStamps.platenSplatDroplets(duck, variant: PressVariant(kind: .rubberDuck, seed: 3)).count == 10)
        let can = FoldStamps.stamp(for: .sodaCan, variant: PressVariant(kind: .sodaCan, seed: 3), foldScale: 0.8)
        #expect(FoldStamps.platenSplatDroplets(can, variant: PressVariant(kind: .sodaCan, seed: 3)).count == 26)
    }

    // MARK: Bubble wrap shadow (FOLD-REVIEW-3 N15)

    @Test func shadowWeightsBlendTheTwoNearestBlurs() {
        let stops: [Double] = [4, 16, 40]
        #expect(FoldStamps.shadowWeights(blur: 2, stops: stops) == [1, 0, 0])
        #expect(FoldStamps.shadowWeights(blur: 10, stops: stops) == [0.5, 0.5, 0])
        #expect(FoldStamps.shadowWeights(blur: 28, stops: stops) == [0, 0.5, 0.5])
        #expect(FoldStamps.shadowWeights(blur: 50, stops: stops) == [0, 0, 1])
        for blur in stride(from: 0.0, through: 48, by: 0.5) {
            let w = FoldStamps.shadowWeights(blur: blur, stops: stops)
            #expect(near(w.reduce(0, +), 1, 1e-9))
        }
        // Sheets never sharpen below 28 pt, and only their domes cast (FOLD-REVIEW-5 F8: no film-sized box).
        #expect(FoldStamps.shadowBlurs(.bubbleWrap).min() ?? 0 >= 28)
        #expect(FoldStamps.shadowBlurs(.rubberDuck) == [4, 16, 40])
        let wrap = FoldStamps.stamp(for: .bubbleWrap, variant: PressVariant(kind: .bubbleWrap, seed: 2), foldScale: 1)
        let outline = FoldStamps.shadowOutline(wrap)
        let box = wrap.silhouette.boundingBoxOfPath
        #expect(FoldPrintCanvas.rect.contains(outline.boundingBoxOfPath))
        // The domes sit inside the film, so their shadow is smaller than the film's outline on both axes.
        #expect(outline.boundingBoxOfPath.width < box.width - 1)
        #expect(outline.boundingBoxOfPath.height < box.height - 1)
        #expect(!outline.contains(CGPoint(x: box.minX + 2, y: box.minY + 2)))
    }

    // MARK: One gauge on both machines (FOLD-REVIEW-4 F12)

    @Test func oneTonnageScaleOnBothMachines() {
        #expect(PressGauge.maxTons == 80)
        #expect(Double(FoldTextures.gaugeMaxTons) == PressGauge.maxTons)
        // The same sweep on the P-48 face and the Fold crown: 0 t at 225°, 40 t straight up, 80 t at −45°.
        #expect(near(Double(RigTextures.gaugeAngle(tons: 0)), 225 * .pi / 180, 1e-9))
        #expect(near(Double(RigTextures.gaugeAngle(tons: 40)), .pi / 2, 1e-9))
        #expect(near(Double(RigTextures.gaugeAngle(tons: 80)), -45 * .pi / 180, 1e-9))
        #expect(near(Double(FoldTextures.needleRotation(tons: 0)), -135 * .pi / 180, 1e-9))
        #expect(near(Double(FoldTextures.needleRotation(tons: 40)), 0, 1e-9))
        #expect(near(Double(FoldTextures.needleRotation(tons: 80)), 135 * .pi / 180, 1e-9))
        // Every needle seals on the record's tonnage, which stays on the dial and out of the red for real objects.
        for kind in ObjectKind.allCases {
            for seed in UInt64(0)..<24 {
                for step in 0...20 {
                    let c = Double(step) / 20
                    let record = SpecimenRecord(id: UUID(), number: 1, kind: kind, date: Date(),
                                                variant: PressVariant(kind: kind, seed: seed), fractureCount: 1,
                                                maxCompression: c, failureAngle: nil, duration: 1, isPerfect: false,
                                                wasSlammed: false)
                    #expect(PressGauge.recordTons(kind: kind, maxCompression: c, seed: seed) == record.tons)
                    guard kind != .unsquishable else {
                        #expect(Double(record.tons) > PressGauge.maxTons)
                        continue
                    }
                    #expect(record.tons >= 1 && Double(record.tons) < PressGauge.redZoneTons)
                    // The live needle (the force) arrives on it at full crush (to within the rounding).
                    if step == 20 {
                        let live = PressGauge.liveTons(kind: kind, compression: 1, seed: seed, failed: true)
                        #expect(abs(live - Double(record.tons)) <= 0.5001, "\(kind) \(live) vs \(record.tons)")
                    }
                }
            }
        }
    }

    // MARK: Eye model (§2.2)

    @Test func eyeModelSanity() {
        let eye = FoldEyeModel.standard
        #expect(near(eye.renderElevation(.tabletop), 47.5, 0.01))
        #expect(near(simd_length(eye.renderEye(.tabletop)), 380, 1e-6))
        var bisector = eye
        bisector.bookTiltTowardTopDegrees = 0
        let flat = bisector.designEye(.book(hinge: 180))
        #expect(near(flat.x, 0) && near(flat.y, 320) && near(flat.z, -40))
        // FOLD-REVIEW-1 #3: the held book is seen from above its top edge (anvil +x), so the object gets a 3/4 face.
        let tilted = eye.designEye(.book(hinge: 180))
        #expect(tilted.x > 100 && near(simd_length(SIMD2(tilted.x, tilted.y)), 320, 1e-6))
        #expect(eye.renderElevation(.book(hinge: 180)) < 75)
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

    // MARK: Inner display (FOLD-REVIEW-7 N10)

    private func inputs(window: Bool = true, canvas: Bool = true, shut: Bool = false,
                        _ activation: InnerDisplayPolicy.Activation = .active) -> InnerDisplayPolicy.Inputs {
        InnerDisplayPolicy.Inputs(inWindow: window, canvasOK: canvas, shut: shut, activation: activation)
    }

    @Test func innerCanvasExcludesTheCoverAndZeroSize() {
        #expect(InnerDisplayPolicy.isInnerCanvas(CGSize(width: 669, height: 951)))
        #expect(InnerDisplayPolicy.isInnerCanvas(CGSize(width: 951, height: 669)))
        #expect(!InnerDisplayPolicy.isInnerCanvas(CGSize(width: 466, height: 678)))   // cover display
        #expect(!InnerDisplayPolicy.isInnerCanvas(.zero))
    }

    @Test func innerDisplayPausesWhenItCantBeSeen() {
        var policy = InnerDisplayPolicy()
        #expect(policy.evaluate(inputs(), now: 0) == .visible)
        #expect(policy.evaluate(inputs(shut: true), now: 1) == .closed)
        #expect(!policy.rendering)
        #expect(policy.evaluate(inputs(canvas: false), now: 2) == .size)
        #expect(policy.evaluate(inputs(window: false, shut: true), now: 3) == .window)
        #expect(policy.evaluate(inputs(shut: true, .background), now: 4) == .background)
        // Reopen: the first open sample renders again, whatever the scene's activity is doing.
        #expect(policy.evaluate(inputs(), now: 5) == .visible)
        #expect(policy.rendering)
    }

    @Test func innerDisplayInactiveNeedsAGraceAndNeverEatsAReopen() {
        var policy = InnerDisplayPolicy()
        _ = policy.evaluate(inputs(), now: 0)
        // Control Center: a short spell keeps rendering; a held one pauses; reactivation resumes.
        #expect(policy.evaluate(inputs(.inactive), now: 10) == .visible)
        #expect(policy.evaluate(inputs(.inactive), now: 10 + InnerDisplayPolicy.inactiveGrace / 2) == .visible)
        #expect(policy.evaluate(inputs(.inactive), now: 10 + InnerDisplayPolicy.inactiveGrace) == .inactive)
        #expect(policy.evaluate(inputs(.active), now: 11) == .visible)

        // Folding toggles scene activity on a Duo: shut, inactive, then the reopen sample. It renders at once and
        // stays rendering through the rest of the inactive spell.
        _ = policy.evaluate(inputs(shut: true), now: 20)
        _ = policy.evaluate(inputs(shut: true, .inactive), now: 21)
        #expect(policy.evaluate(inputs(.inactive), now: 25) == .visible)
        #expect(policy.evaluate(inputs(.inactive), now: 27) == .visible)

        // A spell that starts just after a reopen doesn't pause either; one long after it does.
        var late = InnerDisplayPolicy()
        _ = late.evaluate(inputs(shut: true), now: 0)
        _ = late.evaluate(inputs(), now: 1)
        _ = late.evaluate(inputs(.inactive), now: 1.5)
        #expect(late.evaluate(inputs(.inactive), now: 3) == .visible)
        _ = late.evaluate(inputs(), now: 4)
        _ = late.evaluate(inputs(.inactive), now: 10)
        #expect(late.evaluate(inputs(.inactive), now: 11) == .inactive)
    }

    @Test func revealBeatsWaitForTheDisplayToLight() {
        // The reopen from closed reveals at ~20°: dark. The display lights by 55°.
        #expect(FoldRevealLight.isDark(angle: 20.1))
        #expect(!FoldRevealLight.isDark(angle: FoldRevealLight.litAngle))
        var light = FoldRevealLight()
        var clock = 0.0
        // Opening steadily through the dark window (the CI log: ~10°/s): never lit before 55°.
        var angle = 20.0
        while angle < FoldRevealLight.litAngle {
            light.track(angle: angle, clock: clock)
            #expect(!light.isLit(angle: angle, clock: clock), "lit at \(angle)°")
            angle += 0.5
            clock += 1.0 / 20
        }
        light.track(angle: angle, clock: clock)
        #expect(light.isLit(angle: angle, clock: clock))

        // Held still in the dark window (±2° noise) for the hold: counts as lit (55° is a worst case).
        var still = FoldRevealLight()
        still.track(angle: 40, clock: 0)
        still.track(angle: 41.5, clock: 0.3)
        #expect(!still.isLit(angle: 41.5, clock: 0.3))
        still.track(angle: 39, clock: FoldRevealLight.stillHold)
        #expect(still.isLit(angle: 39, clock: FoldRevealLight.stillHold))
        // A real move restarts the hold.
        still.track(angle: 45, clock: 1.0)
        #expect(!still.isLit(angle: 45, clock: 1.0 + FoldRevealLight.stillHold / 2))
    }

    // MARK: The press, beat by beat (EXPERIENCE-PLAN; Fold side)

    private func tapeFrame(_ t: Double, c: Float, frozen: Bool = false) -> PressTape.Frame {
        PressTape.Frame(time: t, compression: c, ramCompression: c, approach: 1, closingSpeed: 20, loaded: true,
                        frozen: frozen, phase: .pressing)
    }

    /// The reveal replay keeps the last ~2 s of the press, centred on the break: 1.2 s before it, 0.8 s after.
    @Test func replayTapeIsCentredOnTheBreak() throws {
        var recorder = PressTapeRecorder()
        var t = 0.0
        while t < 3 {
            recorder.record(tapeFrame(t, c: Float(t / 10)))
            t += 1.0 / 60
        }
        recorder.mark(.contact, at: 0.5)
        recorder.mark(.fracture(index: 1, isFailure: true), at: 3)
        while t < 6 {
            recorder.record(tapeFrame(t, c: 0.5))
            t += 1.0 / 60
        }
        let tape = try #require(recorder.tape)
        #expect(recorder.isFinished)
        #expect(abs(tape.start - (3 - PressTapeRecorder.beforeBreak)) < 0.02)
        #expect(abs(tape.end - (3 + PressTapeRecorder.afterBreak)) < 0.02)
        #expect(abs(tape.duration - 2) < 0.03)
        #expect(tape.breakTime == Double(3))
        // Earlier events stay on the tape (they are applied at once when a replay starts).
        #expect(tape.marks.count == 2)
        // Interpolated in between frames, clamped outside.
        let mid = try #require(tape.frame(at: 2.5))
        #expect(abs(Double(mid.compression) - 0.25) < 0.003)
        #expect(tape.frame(at: -5)?.time == tape.start)
        // The push-in: wide early on, all the way in at the break, back out by the end.
        #expect(tape.focus(at: tape.start) == 0)
        #expect(tape.focus(at: 3) == 1 && tape.focus(at: 3.3) == 1)
        #expect(tape.focus(at: tape.end) < 0.01)
        // No break: the most recent 2 s, no push-in.
        var plain = PressTapeRecorder()
        for i in 0..<300 { plain.record(tapeFrame(Double(i) / 60, c: 0.1)) }
        let p = try #require(plain.tape)
        #expect(abs(p.duration - PressTapeRecorder.window) < 0.03 && p.focus(at: p.end) == 0)
    }

    @Test func inspectionSpinsWithInertiaThenSpringsHome() {
        var look = ObjectInspection()
        look.beginDrag()
        look.drag(dx: 50, dy: 400)
        #expect(abs(look.yaw - 50 * ObjectInspection.yawPerPoint) < 1e-9)
        look.step(dt: 0.5, allowed: true)
        #expect(look.tilt > 0 && look.tilt <= ObjectInspection.maxTilt + 1e-9)
        let turns = look.endDrag(vx: 800)
        #expect(turns > 1)
        let before = look.yaw
        look.step(dt: 1.0 / 60, allowed: true)
        #expect(look.yaw > before)   // inertia carries it on
        for _ in 0..<600 { look.step(dt: 1.0 / 60, allowed: true) }
        #expect(look.isAtRest)   // springs back to the nearest whole turn, then reads 0
        // A press under way: everything goes home quickly, and a drag is dropped.
        var pressed = ObjectInspection()
        pressed.beginDrag()
        pressed.drag(dx: 80, dy: 0)
        pressed.pinch(scale: 3, began: true)
        #expect(pressed.zoom == ObjectInspection.maxZoom)
        for _ in 0..<30 { pressed.step(dt: 1.0 / 60, allowed: false) }
        #expect(!pressed.dragging && abs(pressed.yaw) < 0.02 && abs(pressed.zoom - 1) < 0.02)
    }

    @Test func burstLooksAndTremorFollowTheScore() {
        // The tremor peaks in the hush and is frozen (held) through the hit stop, never above ~3 px.
        let rest: Float = 0.06
        let hush = PressScene.tremorAmplitude(tell: true, held: true, tension: 1, strain: 1, phase: .hush, rest: rest)
        let fight = PressScene.tremorAmplitude(tell: false, held: false, tension: 0, strain: 1, phase: .none, rest: rest)
        let early = PressScene.tremorAmplitude(tell: false, held: false, tension: 0, strain: 0.3, phase: .none, rest: rest)
        let tell = PressScene.tremorAmplitude(tell: true, held: false, tension: 0, strain: 0, phase: .none, rest: rest)
        let held = PressScene.tremorAmplitude(tell: false, held: true, tension: 0.5, strain: 0, phase: .none, rest: rest)
        #expect(hush > fight && fight > tell && tell > held && held > 0)
        #expect(early < fight)   // it rises toward the break
        #expect(PressScene.tremorAmplitude(tell: true, held: true, tension: 1, strain: 1, phase: .hitStop, rest: rest) == 0)
        // Visible: at full strain ~2 % of the rest height, which is ~3 px on the Duo anvil (24 mm ↔ the rest height).
        #expect(fight >= rest * 0.015 && hush <= rest * 0.03)
        #expect(PressScene.tremorAmplitude(tell: false, held: false, tension: 1, strain: 0, phase: .none, rest: rest) == 0)
        // Soft things squash under a poke, hard ones rattle.
        #expect(PressScene.pokeSoftness(.jelly) > PressScene.pokeSoftness(.egg))
        #expect(PressScene.pokeSoftness(.egg) > PressScene.pokeSoftness(.unsquishable))
    }

    /// The object anticipates the lid: a small lean as it comes, a wobble with the hinge speed, all within 2°.
    @Test func objectAnticipatesTheLid() {
        #expect(FoldLean.anticipation(approach: 0, closingSpeed: 0, time: 0.3) == 0)
        let near = FoldLean.anticipation(approach: 1, closingSpeed: 0, time: 0)
        #expect(abs(near * 180 / .pi - 1.2) < 1e-9)
        for i in 0..<100 {
            let a = FoldLean.anticipation(approach: 1, closingSpeed: 400, time: Double(i) * 0.013)
            #expect(abs(a * 180 / .pi) <= 1.8 + 1e-9)
        }
    }

    /// The close-style stamp renders for every word at the PRESSED stamp size (the pose rules depend on it).
    @Test func closeStyleStampsRenderAtOneSize() throws {
        let base = try #require(FoldTextures.pressedStamp(width: FoldPlaten.pressedSize.width))
        for style in [CloseStyle.perfect, .slammed, .pressed] {
            let image = try #require(FoldTextures.pressedStamp(width: FoldPlaten.pressedSize.width, text: style.stampText,
                                                               gentle: style.isGentle))
            #expect(image.width == base.width && image.height == base.height, "\(style)")
        }
    }

    /// P0 (CI run 40153721315): soft objects looked frozen before the break. End to end through the real scene: the CI
    /// capture's hinge (sparse reports, ~10 s holds) into a `PressEngine`, its events into a real `PressScene`, frames at
    /// 30 Hz. At every held moment the object view is updated each frame with the hand's compression, and every fracture
    /// the engine fires reaches the view (the bubbles keep popping, the failure lands by the 75° hold).
    @Test func sceneDeliversTheHandToTheObjectThroughTheCIHolds() async throws {
        for kind in [ObjectKind.gummyBear, .jelly, .cakeSlice, .bubbleWrap] {
            let scene = PressScene()
            let variant = PressVariant(kind: kind, seed: 42)
            scene.setObject(kind, variant: variant)
            var waited = 0
            while scene.foldObject == nil && waited < 600 {   // heavy meshes build off the main actor
                try await Task.sleep(nanoseconds: 50_000_000)
                waited += 1
            }
            try #require(scene.foldObject != nil, "\(kind) never built")
            let engine = PressEngine()
            var fired = 0
            var failureAt: Double?
            var now = 0.0
            engine.onEvent = { event in
                if case let .fracture(_, isFailure) = event {
                    fired += 1
                    if isFailure && failureAt == nil { failureAt = now }
                }
                let context = FeedbackContext(kind: kind, variant: variant, compression: Float(engine.measuredCompression),
                                              closingSpeed: Float(engine.closingSpeed), soundStyle: .workshop,
                                              reduceMotion: false)
                scene.handle(event, context: context)
            }
            let log = PressEngineTests.ciLog
            let t0 = log[0].time - 2
            engine.ingest(angle: 180, closed: false, at: t0)
            engine.load(kind, seed: 42, at: t0)
            var next = 0
            var lastReport = t0
            var heldChecks = 0
            var worst: Float = 0
            var notUpdated = 0
            var frame = 0
            while true {
                now = t0 + Double(frame) / 30
                if now > 76.5 { break }
                while next < log.count, log[next].time <= now {
                    engine.ingest(angle: log[next].angle, closed: false, at: log[next].time)
                    lastReport = log[next].time
                    next += 1
                }
                engine.step(now: now, dt: 1.0 / 30)
                let context = FeedbackContext(kind: kind, variant: variant, compression: Float(engine.measuredCompression),
                                              closingSpeed: Float(engine.closingSpeed), soundStyle: .workshop,
                                              reduceMotion: false)
                scene.update(engine: engine, context: context, dt: 1.0 / 30)
                if engine.phase == .pressing, now - lastReport >= 1, let state = scene.lastObjectState {
                    heldChecks += 1
                    worst = max(worst, abs(state.compression - Float(engine.measuredCompression)))
                    if !scene.objectUpdatedLastFrame { notUpdated += 1 }
                }
                frame += 1
            }
            #expect(heldChecks > 300, "\(kind): \(heldChecks) held frames")
            #expect(worst <= 0.04, "\(kind): the view was given \(worst) off the hand at a hold")
            #expect(notUpdated == 0, "\(kind): \(notUpdated) held frames skipped the view update")
            #expect(scene.deliveredFractures == fired, "\(kind): \(scene.deliveredFractures) of \(fired) fractures reached the view")
            if engine.failureThreshold != nil {
                let at = try #require(failureAt, "\(kind) never broke")
                #expect(at < 76.81, "\(kind) broke at \(at) s: only at the shut, not while lit")
            }
        }
    }
}
