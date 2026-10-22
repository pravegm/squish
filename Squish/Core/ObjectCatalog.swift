import Foundation

/// The ten launch objects (bible §4). Order is shelf order.
enum ObjectKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case bubbleWrap
    case rubberDuck
    case jelly
    case crayon
    case egg
    case cakeSlice
    case sodaCan
    case gummyBear
    case glassBottle
    case unsquishable

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bubbleWrap: "Bubble Wrap"
        case .rubberDuck: "Rubber Duck"
        case .jelly: "Jelly"
        case .crayon: "Crayon"
        case .egg: "Egg"
        case .cakeSlice: "Cake Slice"
        case .sodaCan: "Soda Can"
        case .gummyBear: "Gummy Bear"
        case .glassBottle: "Glass Bottle"
        case .unsquishable: "The Unsquishable"
        }
    }

    /// SF Symbol used in pickers and silhouettes.
    var symbolName: String {
        switch self {
        case .bubbleWrap: "circle.grid.3x3.fill"
        case .rubberDuck: "bird.fill"
        case .jelly: "drop.fill"
        case .crayon: "pencil.tip"
        case .egg: "oval.portrait.fill"
        case .cakeSlice: "birthday.cake.fill"
        case .sodaCan: "cylinder.fill"
        case .gummyBear: "teddybear.fill"
        case .glassBottle: "waterbottle.fill"
        case .unsquishable: "circle.fill"
        }
    }

    var profile: MaterialProfile {
        switch self {
        case .bubbleWrap: .bubbleWrap
        case .rubberDuck: .rubberDuck
        case .jelly: .jelly
        case .crayon: .crayon
        case .egg: .egg
        case .cakeSlice: .cakeSlice
        case .sodaCan: .sodaCan
        case .gummyBear: .gummyBear
        case .glassBottle: .glassBottle
        case .unsquishable: .unsquishable
        }
    }

    var unlockRule: UnlockRule {
        switch self {
        case .bubbleWrap, .rubberDuck, .jelly, .crayon, .egg, .cakeSlice: .open
        case .sodaCan: .squishDifferentKinds(3)
        case .gummyBear: .totalPresses(6)
        case .glassBottle: .perfectSquish
        case .unsquishable: .allOthers
        }
    }

    /// The secret object stays a silhouette with a teasing hint until unlocked.
    var isSecret: Bool { self == .unsquishable }

    /// Spoken by VoiceOver when the object is placed.
    var accessibilityDescription: String {
        switch self {
        case .bubbleWrap: "Bubble wrap. Twenty-four bubbles, each waiting to pop."
        case .rubberDuck: "Rubber duck. Squeaky, rubbery, surprisingly brave."
        case .jelly: "Jelly. Wobbly and translucent."
        case .crayon: "Crayon. Waxy and brittle."
        case .egg: "Egg. Fragile shell, runny inside."
        case .cakeSlice: "Cake slice. Sponge, frosting, one candle."
        case .sodaCan: "Soda can. Thin aluminium, still sealed."
        case .gummyBear: "Gummy bear. Chewy and glossy."
        case .glassBottle: "Glass bottle. Thick, clear and tense."
        case .unsquishable: "A steel ball bearing. Very, very hard."
        }
    }

    /// Flavour lines shown on the specimen card. The 12+ tone lives here, never in the imagery.
    var flavourLines: [String] {
        switch self {
        case .bubbleWrap: ["Every single one. You monster.", "Shipping department's worst nightmare.", "Popped with professional care."]
        case .rubberDuck: ["He'll be fine. Probably.", "Bath time is cancelled.", "Quack, but flatter."]
        case .jelly: ["Set for four hours. Lasted four seconds.", "Wobble: terminated.", "It's in the grout now."]
        case .crayon: ["Colouring outside the lines, permanently.", "Now a very short crayon.", "Wax on. Wax everywhere."]
        case .egg: ["Sunny side down.", "Some eggs-ceptional pressure.", "Breakfast is ruined. Worth it."]
        case .cakeSlice: ["It wasn't your birthday anyway.", "Make a wish. Too late.", "The cake was a lie. Now it's a pancake."]
        case .sodaCan: ["Freshly flattened. Do not recycle twice.", "Shaken, not stirred. Mostly crushed.", "Fizz has left the building."]
        case .gummyBear: ["Gummy bear, ex-bear.", "Unbearably flat.", "Chewed by four hundred tonnes."]
        case .glassBottle: ["Seven years' bad luck, minimum.", "Message received. Bottle not.", "Handle with care. Too late."]
        case .unsquishable: ["Press 0 – Ball 1.", "Some things don't break. Your press did.", "The ball sends its regards."]
        }
    }

    /// One-line hint on a locked shelf slot.
    var unlockHint: String {
        switch unlockRule {
        case .open: ""
        case .squishDifferentKinds(let n): "Squish \(n) different things"
        case .totalPresses(let n): "Squish \(n) times"
        case .perfectSquish: "Earn a Perfect Squish"
        case .allOthers: "Some things refuse to be squished…"
        }
    }

    /// The most compact stat for the specimen label, e.g. "24 POPS".
    func breaksLine(fractureCount: Int) -> String {
        switch self {
        case .bubbleWrap: "\(fractureCount) POPS"
        case .rubberDuck: fractureCount >= 2 ? "1 HONK · 1 SEAM POP" : "\(fractureCount) HONK"
        case .jelly: fractureCount >= 2 ? "SKIN SPLIT · SPLAT" : "SKIN SPLIT"
        case .crayon: "\(fractureCount) SNAPS"
        case .egg: fractureCount >= 2 ? "SHELL BREACHED" : "HAIRLINE CRACK"
        case .cakeSlice: fractureCount >= 3 ? "FROSTING ESCAPED" : "\(fractureCount) LAYERS COLLAPSED"
        case .sodaCan: "\(fractureCount) BUCKLES"
        case .gummyBear: fractureCount >= 1 ? "SEAM SPLIT" : "SQUISHED"
        case .glassBottle: fractureCount >= 2 ? "SHATTERED" : "CRACKED"
        case .unsquishable: "PRESS DAMAGED"
        }
    }
}

enum UnlockRule: Equatable, Sendable {
    case open
    case squishDifferentKinds(Int)
    case totalPresses(Int)
    case perfectSquish
    case allOthers
}
