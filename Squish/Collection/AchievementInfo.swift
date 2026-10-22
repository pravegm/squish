import Foundation

/// Player-facing copy for achievements (toasts, Settings). Game Center titles are configured
/// in App Store Connect with the same wording; IDs are `Achievement.gameCenterID`.
extension Achievement {
    var title: String {
        switch self {
        case .firstSquish: "First Squish"
        case .perfectionist: "Perfectionist"
        case .midas: "Midas"
        case .whatsInside: "What's Inside?"
        case .patience: "Patience"
        case .collector: "Collector"
        case .theSecret: "The Secret"
        case .popStar: "Pop Star"
        case .steadyHands: "Steady Hands"
        case .pumped: "Pumped"
        }
    }

    var detail: String {
        switch self {
        case .firstSquish: "Specimen №0001. The first of many."
        case .perfectionist: "Perfect Squishes on 5 different things."
        case .midas: "Pressed a golden one. 1 in 50."
        case .whatsInside: "Found two different surprises."
        case .patience: "One press, over 30 seconds. Very zen."
        case .collector: "All 10 pressed. Shelf complete."
        case .theSecret: "Met The Unsquishable. It won."
        case .popStar: "500 bubbles popped. Lifetime."
        case .steadyHands: "Ten Perfect Squishes. Steady."
        case .pumped: "Eased off and pressed again. Twice."
        }
    }

    var symbolName: String {
        switch self {
        case .firstSquish: "1.circle.fill"
        case .perfectionist: "sparkles"
        case .midas: "crown.fill"
        case .whatsInside: "gift.fill"
        case .patience: "hourglass"
        case .collector: "square.grid.3x3.fill"
        case .theSecret: "questionmark.circle.fill"
        case .popStar: "circle.grid.3x3.fill"
        case .steadyHands: "hand.raised.fill"
        case .pumped: "arrow.up.arrow.down"
        }
    }
}

/// Specimen copy shared by the cards, the share image and VoiceOver.
extension SpecimenRecord {
    var numberLabel: String { String(format: "№%04ld", number) }

    /// Two SF Mono data lines (VISUAL-TARGET §6.8): `CRUSHED AT 92° · 48 TONS` / `24 POPS · 8.4 S`.
    var labelLines: [String] {
        let first: String
        if kind != .unsquishable, let failureAngle {
            first = "CRUSHED AT \(Int(failureAngle.rounded()))° · \(tons) TONS"
        } else {
            first = "PEAK \(tons) TONS"
        }
        let second = kind.breaksLine(fractureCount: fractureCount) + String(format: " · %.1f S", duration)
        return [first, second]
    }

    /// The stamp's words: the Unsquishable wins (bible §4).
    var stampText: String { kind == .unsquishable ? "PRESS 0 – BALL 1" : "PRESSED" }

    struct Trait: Identifiable, Equatable {
        enum Tone { case perfect, golden, surprise, neutral }
        var id: String { text }
        let text: String
        let systemImage: String
        let tone: Tone
    }

    /// Golden first, then Perfect, surprise; a slam is shown neutrally (never as a reward, bible §2).
    var traits: [Trait] {
        var traits: [Trait] = []
        if variant.isGolden { traits.append(Trait(text: "GOLDEN", systemImage: "crown.fill", tone: .golden)) }
        if isPerfect { traits.append(Trait(text: "PERFECT SQUISH", systemImage: "sparkles", tone: .perfect)) }
        if let surprise = variant.surprise {
            traits.append(Trait(text: surprise.title, systemImage: "gift.fill", tone: .surprise))
        }
        if wasSlammed { traits.append(Trait(text: "SLAM", systemImage: "bolt.fill", tone: .neutral)) }
        if reversals >= 2 { traits.append(Trait(text: "PUMPED ×\(reversals)", systemImage: "arrow.up.arrow.down", tone: .neutral)) }
        return traits
    }

    /// The whole card as one VoiceOver sentence.
    var accessibilitySentence: String {
        var parts: [String] = ["Specimen number \(number), \(kind.displayName)"]
        if kind == .unsquishable {
            parts.append("press nil, ball one")
        } else if let failureAngle {
            parts.append("crushed at \(Int(failureAngle.rounded())) degrees")
        }
        parts.append("peak \(tons) tons")
        parts.append(kind.breaksLine(fractureCount: fractureCount).replacingOccurrences(of: " · ", with: ", ").lowercased())
        parts.append(String(format: "pressed in %.1f seconds", duration))
        let traitWords = traits.map { $0.text.lowercased().replacingOccurrences(of: "×", with: "times ") }
        var sentence = parts.joined(separator: ", ") + "."
        if !traitWords.isEmpty { sentence += " " + traitWords.joined(separator: ", ").capitalizedFirst + "." }
        sentence += " " + flavourLine
        return sentence
    }
}

fileprivate extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// Unlock hints with live progress (UX-REVIEW-1 P1-13): "SQUISH 3 DIFFERENT THINGS · 1/3".
extension CollectionStore {
    func progressHint(for kind: ObjectKind) -> String {
        switch kind.unlockRule {
        case .open:
            return ""
        case .squishDifferentKinds(let count):
            return "Squish \(count) different things · \(min(stats.squishedKinds.count, count))/\(count)"
        case .totalPresses(let count):
            return "Squish \(count) times · \(min(totalPresses, count))/\(count)"
        case .perfectSquish:
            return "Press slowly. Never ease off."
        case .allOthers:
            return kind.unlockHint
        }
    }

    /// Short lower-case form for the object chip menu's locked rows (P2-7).
    func menuHint(for kind: ObjectKind) -> String {
        switch kind.unlockRule {
        case .open: ""
        case .squishDifferentKinds(let count): "squish \(count) different things"
        case .totalPresses(let count): "squish \(count) times"
        case .perfectSquish: "press slowly, never ease off"
        case .allOthers: "some things refuse to be squished"
        }
    }
}
