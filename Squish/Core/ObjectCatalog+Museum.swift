import Foundation

// "The Museum of Pressed Things" (design/EXPERIENCE-PLAN.md decision 7, EXPERIENCE-2 §F3): the roster as a museum
// that escalates soft → crunchy → tough, with a vault for the steel ball. This file only frames the catalogue (wings,
// verbs, stiffness, the order a first session meets things in); names and copy live in ObjectCatalog.swift.
// Pure and nonisolated, so tests and the collection can use it anywhere.

/// A wing of the museum. The first three are the galleries; the vault holds the one thing that won't squish.
enum MuseumWing: String, CaseIterable, Identifiable, Sendable {
    case soft, crunchy, tough, vault

    var id: String { rawValue }

    /// The three wings a player fills (the vault's single object never counts as "a full wing").
    static let galleries: [MuseumWing] = [.soft, .crunchy, .tough]

    var title: String {
        switch self {
        case .soft: "Soft Things"
        case .crunchy: "Crunchy & Cracking"
        case .tough: "Tough Stuff"
        case .vault: "The Vault"
        }
    }

    /// "WING 1" … "THE VAULT", for the small engraved plate above a wing.
    var plate: String {
        switch self {
        case .soft: "WING 1"
        case .crunchy: "WING 2"
        case .tough: "WING 3"
        case .vault: "BEHIND GLASS"
        }
    }

    /// One short line under the wing's title.
    var tagline: String {
        switch self {
        case .soft: "Squish, pop, ooze. Start here."
        case .crunchy: "Shells, snaps and things inside."
        case .tough: "They fight back. Then they don't."
        case .vault: "Do not press. (Press it.)"
        }
    }

    var kinds: [ObjectKind] {
        switch self {
        case .soft: [.bubbleWrap, .rubberDuck, .jelly, .cakeSlice]
        case .crunchy: [.egg, .crayon, .gummyBear]
        case .tough: [.sodaCan, .glassBottle]
        case .vault: [.unsquishable]
        }
    }
}

extension ObjectKind {
    /// The wing this object hangs in.
    var wing: MuseumWing {
        MuseumWing.allCases.first { $0.kinds.contains(self) } ?? .soft
    }

    /// Every object, wing by wing (the Tray's order).
    static var museumOrder: [ObjectKind] { MuseumWing.allCases.flatMap(\.kinds) }

    /// The one-word promise on a tile: what it does when you press it.
    var verb: String {
        switch self {
        case .bubbleWrap: "Pops"
        case .rubberDuck: "Squeaks"
        case .jelly: "Oozes"
        case .crayon: "Smears"
        case .egg: "Cracks"
        case .cakeSlice: "Squelches"
        case .sodaCan: "Buckles"
        case .gummyBear: "Splits"
        case .glassBottle: "Shatters"
        case .unsquishable: "Refuses"
        }
    }

    /// A slightly longer promise, for the selected tile and the "Up next" line.
    var behaviour: String {
        switch self {
        case .bubbleWrap: "Pops one bubble at a time."
        case .rubberDuck: "Squeaks, flattens, forgives you."
        case .jelly: "Wobbles, splits its skin, then oozes."
        case .crayon: "Snaps in a row, then smears a rainbow."
        case .egg: "Cracks, gives, and the yolk escapes."
        case .cakeSlice: "Collapses in layers. Jam goes everywhere."
        case .sodaCan: "Buckles ring by ring, then fizzes."
        case .gummyBear: "Stretches, then splits down the seam."
        case .glassBottle: "Holds, creaks, holds… then shatters."
        case .unsquishable: "Absolutely nothing. That's the point."
        }
    }

    /// How hard it fights the press, 1 (soft) … 5 (glass). The steel ball is off the scale (`isOffTheScale`).
    var stiffness: Int {
        switch self {
        case .bubbleWrap, .jelly, .cakeSlice: 1
        case .rubberDuck, .gummyBear: 2
        case .egg, .crayon: 3
        case .sodaCan: 4
        case .glassBottle, .unsquishable: 5
        }
    }

    var isOffTheScale: Bool { self == .unsquishable }

    /// The surprises this object can hide (empty for the duck and the ball).
    var possibleSurprises: [Surprise] { Surprise.allCases.filter { $0.kind == self } }

    /// Golden can roll for everything except the steel ball (`PressVariant`).
    var canBeGolden: Bool { self != .unsquishable }

    /// The order a first session meets things in (UX-AUDIT-2 §4.4: contrast, not the duck second): pops, then a gooey
    /// payoff, then a snap. Afterwards "Up next" walks the museum.
    static let tourOrder: [ObjectKind] = [.bubbleWrap, .egg, .jelly, .crayon, .cakeSlice, .rubberDuck,
                                          .sodaCan, .gummyBear, .glassBottle, .unsquishable]

    /// How much of its rest height a fully pressed object keeps (mirrors each object's `minHeightRatio` /
    /// `HeightCurve` floor in Scene/Objects, so the reveal's "42 mm → 1.8 mm" measures what the press drew).
    var pressedFloorRatio: Double {
        switch self {
        case .bubbleWrap: 0.30      // BubbleWrapView.minHeightRatio
        case .rubberDuck: 0.18      // DuckView.minHeightRatio
        case .jelly: 0.13           // JellyView.minHeightRatio
        case .crayon: 0.10
        case .egg: 0.07             // EggView: HeightCurve.brittle minRatio
        case .cakeSlice: 0.12
        case .sodaCan: 0.13         // SodaCanView.minHeightRatio
        case .gummyBear: 0.14       // GummyBearView.minHeightRatio
        case .glassBottle: 0.09     // GlassBottleView: HeightCurve.brittle minRatio
        case .unsquishable: 1.0     // it doesn't
        }
    }
}

extension Surprise {
    /// The object that hides this surprise (`Surprise.roll`).
    var kind: ObjectKind {
        switch self {
        case .megaBubble: .bubbleWrap
        case .fruitPieces: .jelly
        case .secondColourCore: .crayon
        case .toyChick, .doubleYolk: .egg
        case .jamCentre: .cakeSlice
        case .cherryFizz: .sodaCan
        case .rainbowCore: .gummyBear
        case .messageInABottle: .glassBottle
        }
    }
}
